--[[
  Puddles: shallow water on the ground that rings with waves wherever the
  player, an enemy or a boss wades through it.

  Each puddle is a wobbly ellipse in world space. puddle.update() watches
  every walker: stepping into a puddle splashes, and every few px of wading
  after that drops another ring. Rings spread, fade and interfere in the
  puddle shader.

  They draw straight onto the ground in scene_canvas, under everything that
  walks through them, in two passes that leave the canvas's alpha untouched:
  the global-illumination pass treats alpha > 0.5 as a wall (the ground is
  drawn at 0.4 so it never is), and a puddle mustn't become one.
    1. multiply: the wet ground darkens and turns blue, deepest mid-puddle;
    2. add:      wave crests and the wet rim catch the light (the same point
                 lights as the rest of the scene, so puddles stay dark at night).
]]
local puddle = {}

puddle.list = {}
puddle.time = 0

local MAX_RIPPLES = 24 -- per puddle; must match the shader
local STEP = 14        -- px waded between rings
local RING_SPEED = 42  -- px/s, must match the shader
local RING_LIFE = 1.6  -- s, must match the shader

-- Who's standing where: body -> { x, y, inside = puddle or nil, wade = px since the last ring }
local walkers = setmetatable({}, { __mode = "k" })

local shaderSrc = require("lib.graphics.shadow").REACH_GLSL .. [[
#define MAX_RIPPLES 24
#define MAX_LIGHTS 64

uniform vec4  shape;                // centre x, y and radii x, y (world px)
uniform float seed;                 // per-puddle edge wobble
uniform highp float time;
uniform int   numRipples;
uniform vec4  ripples[MAX_RIPPLES]; // x, y (world px), birth time, strength
uniform float shine;                // 0: the multiply pass, 1: the add pass

uniform int   numLights;
uniform vec4  lights[MAX_LIGHTS];   // shadow.lua's screen-space lights
uniform float u_ambient;

const float RING_SPEED = 42.0;
const float RING_LIFE = 1.6;
const float RING_WIDTH = 3.5;       // px, the wave packet's spread
const float RING_K = 1.05;          // rad/px, ~6 px between crests

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    // The quad spans the puddle's bounds; its texture coordinates give the
    // world position (vertex positions arrive already transformed to screen
    // px when LÖVE batches the draw)
    vec2 q = tc * 2.0 - 1.0;
    vec2 worldPos = shape.xy + q * shape.zw;

    // Normalised radius, the edge wobbling with angle so it isn't an ellipse
    float a = atan(q.y, q.x);
    float edge = 0.86 + 0.08 * sin(3.0 * a + seed) + 0.05 * sin(5.0 * a + seed * 1.7)
               + 0.03 * sin(8.0 * a + seed * 2.3);
    float d = length(q) / edge;
    if (d >= 1.0) discard;
    float cover = 1.0 - smoothstep(0.82, 1.0, d);

    // Height and slope: every live ring's wave packet, plus a faint idle shimmer
    float h = 0.0;
    vec2 grad = vec2(0.0);
    for (int i = 0; i < MAX_RIPPLES; i++) {
        if (i >= numRipples) break;
        float age = time - ripples[i].z;
        if (age < 0.0 || age > RING_LIFE) continue;
        vec2 dv = worldPos - ripples[i].xy;
        float dist = length(dv);
        float r = RING_SPEED * age;
        float x = dist - r;
        if (abs(x) > 3.0 * RING_WIDTH) continue;
        float fade = 1.0 - age / RING_LIFE;
        float amp = ripples[i].w * fade * fade / (1.0 + r * 0.04);
        float env = exp(-x * x / (2.0 * RING_WIDTH * RING_WIDTH));
        float ph = x * RING_K;
        h += amp * env * cos(ph);
        float dh = amp * env * (-RING_K * sin(ph) - x / (RING_WIDTH * RING_WIDTH) * cos(ph));
        grad += dh * dv / max(dist, 0.001);
    }
    vec2 sp = worldPos * vec2(0.21, 0.29);
    h += 0.04 * sin(sp.x + time * 1.3) * sin(sp.y - time * 1.1);
    grad += 0.04 * vec2(0.21 * cos(sp.x + time * 1.3) * sin(sp.y - time * 1.1),
                        0.29 * sin(sp.x + time * 1.3) * cos(sp.y - time * 1.1));

    if (shine < 0.5) {
        // Wet ground: darker and bluer, deepest in the middle; troughs darker
        float depth = cover * (0.75 + 0.25 * (1.0 - d));
        vec3 tint = mix(vec3(1.0), vec3(0.42, 0.55, 0.78), depth);
        tint *= 1.0 + clamp(h, -1.0, 1.0) * 0.35 * cover;
        return vec4(tint, 1.0); // alpha 1: multiply leaves the canvas's alpha be
    }

    // Light on the water: a sky-blue sheen, slopes facing the light, crests
    // and the wet rim, only as bright as the scene's lights are here
    float lit = (u_ambient > 0.0) ? u_ambient : 0.20;
    float beam = -1.0; // beamReaches(sc), once a beam light needs it (shadow.lua)
    for (int i = 0; i < MAX_LIGHTS; i++) {
        if (i >= numLights) break;
        float range = lightRange(lights[i]);
        if (range <= 0.0) continue;
        float dist = distance(lights[i].xy, sc);
        if (dist >= range) continue;
        float att = 1.0 - dist / range;
        lit += att * att * lights[i].z * reaches(i, lights[i], range, sc, beam); // not past what's in the way
    }
    lit = min(lit, 1.0);

    float slope = max(dot(grad, vec2(-0.6, -0.8)), 0.0);
    float crest = smoothstep(0.25, 0.8, h);
    float rim = smoothstep(0.7, 0.9, d) * (1.0 - smoothstep(0.9, 1.0, d));
    float glint = (slope * 2.2 + crest * 0.8 + rim * 0.35) * cover * lit;
    vec3 sheen = vec3(0.10, 0.18, 0.32) * cover * (1.0 - 0.5 * d) * lit;
    return vec4(sheen + vec3(0.62, 0.8, 1.0) * glint, 0.0); // alpha 0: add leaves it be
}
]]

--- Add a puddle centred on world (x, y) with radii rx, ry. Returns it.
function puddle.add(x, y, rx, ry)
    local p = { x = x, y = y, rx = rx, ry = ry, seed = #puddle.list * 1.618 + 0.7,
                ripples = {}, next = 1 }
    puddle.list[#puddle.list + 1] = p
    return p
end

function puddle.clear()
    puddle.list = {}
end

function puddle.load()
    puddle.shader = love.graphics.newShader(shaderSrc)
    -- 1x1 white texel stretched over each puddle: its 0..1 texture
    -- coordinates are what the shader maps onto the puddle
    local white = love.image.newImageData(1, 1)
    white:setPixel(0, 0, 1, 1, 1, 1)
    puddle.quad = love.graphics.newImage(white)
    puddle.clear()
    -- Open ground around the start, clear of the house, arch and tree
    puddle.add(330, 400, 70, 30)
    puddle.add(640, 450, 90, 36)
    puddle.add(190, 290, 55, 24)
    puddle.add(720, 260, 60, 26)
    puddle.add(450, 560, 100, 40)
    puddle.add(100, 480, 50, 22)
    puddle.add(820, 560, 65, 28)
end

--- The puddle (world) point x, y is in, if any.
function puddle.at(x, y)
    for _, p in ipairs(puddle.list) do
        local dx, dy = (x - p.x) / p.rx, (y - p.y) / p.ry
        if dx * dx + dy * dy < 0.8 then -- inside the wobbly edge all round
            return p
        end
    end
end

--- Start a ring in puddle p at world (x, y); strength ~0.3 (a step) .. 1 (a splash).
function puddle.ripple(p, x, y, strength)
    p.ripples[p.next] = { x, y, puddle.time, strength }
    p.next = p.next % MAX_RIPPLES + 1
end

local function wade(body, dt)
    if not body or body:isDestroyed() then return end
    local x, y = body:getPosition()
    local w = walkers[body]
    if not w then
        w = { x = x, y = y, wade = 0 }
        walkers[body] = w
    end
    local moved = math.sqrt((x - w.x) ^ 2 + (y - w.y) ^ 2)
    w.x, w.y = x, y

    local p = puddle.at(x, y)
    if p and p ~= w.inside then
        puddle.ripple(p, x, y, 1.0) -- splash in
        w.wade = 0
    elseif p then
        w.wade = w.wade + moved
        if w.wade >= STEP then
            local speed = dt > 0 and moved / dt or 0
            puddle.ripple(p, x, y, math.max(0.3, math.min(1.0, speed / 160)))
            w.wade = 0
        end
    end
    w.inside = p
end

function puddle.update(dt)
    puddle.time = puddle.time + dt
    if #puddle.list == 0 then return end

    if player and player.body then wade(player.body, dt) end
    if enemy and enemy.enemies then
        for _, e in ipairs(enemy.enemies) do
            if not e.dead and e.body then wade(e.body, dt) end
        end
    end
    if boss and boss.bosses then
        for _, b in pairs(boss.bosses) do
            if b.body then wade(b.body, dt) end
        end
    end
end

-- Scratch list of the live rings sent per puddle (reused, no per-frame tables)
local live = {}

local function sendRipples(p)
    local n = 0
    for i = 1, MAX_RIPPLES do
        local r = p.ripples[i]
        if r and puddle.time - r[3] <= RING_LIFE then
            n = n + 1
            live[n] = r
        end
    end
    for i = #live, n + 1, -1 do live[i] = nil end
    puddle.shader:send("numRipples", n)
    if n > 0 then puddle.shader:send("ripples", unpack(live)) end
end

--- Draw every puddle on screen, onto the ground (call under the camera
--- transform, after the map and before anything that walks through them).
function puddle.draw()
    if #puddle.list == 0 or not var.puddles then return end -- (Settings > Puddles)

    -- Visible world rectangle
    local zoom = camera.zoom
    local x0 = -camera.x / zoom
    local y0 = -camera.y / zoom
    local x1 = x0 + love.graphics.getWidth() / zoom
    local y1 = y0 + love.graphics.getHeight() / zoom

    love.graphics.push("all")
    love.graphics.setShader(puddle.shader)
    love.graphics.setColor(1, 1, 1, 1)
    puddle.shader:send("time", puddle.time)
    shadow.sendLights(puddle.shader)

    for _, p in ipairs(puddle.list) do
        if p.x + p.rx > x0 and p.x - p.rx < x1 and p.y + p.ry > y0 and p.y - p.ry < y1 then
            puddle.shader:send("shape", { p.x, p.y, p.rx, p.ry })
            puddle.shader:send("seed", p.seed)
            sendRipples(p)
            puddle.shader:send("shine", 0)
            love.graphics.setBlendMode("multiply", "premultiplied")
            love.graphics.draw(puddle.quad, p.x - p.rx, p.y - p.ry, 0, p.rx * 2, p.ry * 2)
            puddle.shader:send("shine", 1)
            -- (lit where it's drawn: only by the lights that reach its quad)
            local sx0, sy0 = love.graphics.transformPoint(p.x - p.rx, p.y - p.ry)
            local sx1, sy1 = love.graphics.transformPoint(p.x + p.rx, p.y + p.ry)
            shadow.cullLights(puddle.shader, math.min(sx0, sx1) - 1, math.min(sy0, sy1) - 1,
                math.max(sx0, sx1) + 1, math.max(sy0, sy1) + 1)
            love.graphics.setBlendMode("add", "premultiplied")
            love.graphics.draw(puddle.quad, p.x - p.rx, p.y - p.ry, 0, p.rx * 2, p.ry * 2)
        end
    end

    love.graphics.pop()
end

return puddle
