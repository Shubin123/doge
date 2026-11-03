--[[
  The black hole: time slows near it, it pulls everything in, and what
  crosses its horizon is gone.

    * Time: blackhole.timeScale (1 = normal) multiplies the frame's dt for
      the whole game (main.lua), easing down to MIN_SCALE as the nearest
      player closes on the horizon. In multiplayer the host works it out
      from every player and sends it with its snapshot; each side runs at
      the slower of that and its own.
    * Pull: the player, enemies, XP globs and bullets in flight fall towards
      it, harder the closer they are (1/d^2). Within ~90 px walking can't
      get you out.
    * Horizon: globs and enemies are swallowed (an enemy dies, its light
      streaming off as usual), bullets vanish, and the player takes damage
      while inside.
    * Look (blackhole.applyLensing, a screen-space pass over scene_canvas
      before GI): the scene bends round it, the shadow is black, and a hot,
      turning accretion disk and photon ring glow round it. They're drawn
      opaque, so GI spreads their light like any other bright wall. While
      time is slow the whole frame turns colder and greyer. The black hole
      gun's small holes (blackholeGun.lua) are drawn by the same shader in
      colder colours (blackhole.applySmallLensing).
    * Low graphics, with no screen-space passes: a stand-in in the sorted
      draw list (blackhole.populate, blackhole.drawFallback), the disk
      tilted towards you round the shadow, its far half behind it, the
      photon ring and the arc lensed over the top, its bands turning; and
      while time is slow a cold tint over the frame (blackhole.drawSlowTint).

  It sits at a fixed spot east of the home map; the console's
  `blackhole [x] [y]` moves it (to just ahead of you without coordinates).
]]
local blackhole = {}

blackhole.x, blackhole.y = 1400, 300

local HORIZON = 34        -- px: the shadow's radius, and where things are swallowed
local SLOW_RADIUS = 460   -- px: time starts to slow inside this
local MIN_SCALE = 0.2     -- the slowest time runs, at the horizon
local PULL_RADIUS = 560   -- px: the player feels it inside this
local ENEMY_PULL_RADIUS = 320 -- px: enemies (wider and it empties the map)
local GLOB_PULL_RADIUS = 220 -- px: globs only close in (or it would eat them all)
local PULL = 4.0e6        -- acceleration is PULL / d^2 px/s^2
local MAX_PULL = 2400     -- px/s^2, the cap close in
local DRAG = 2.5          -- 1/s: the player's fall settles at PULL / d^2 / DRAG px/s
local BULLET_PULL = 4     -- bullets are light: they bend round it four times as hard
local HURT_PER_SECOND = 300 -- HP inside the horizon (player.maxHealth is 1000)
local LENS_RADIUS = 10    -- horizons: how far out the scene visibly bends

blackhole.timeScale = 1
local hostScale = 1 -- multiplayer client: the shared world's pace, from the host
-- The player's fall towards it, px/s. Kept here, not in the body's velocity:
-- player.update's friction zeroes anything under 5 px/s every frame, so a
-- pull added to the velocity never built up. Added to the velocity for each
-- physics step, so walls still stop it.
local driftX, driftY = 0, 0

local lensShader, smallLensShader, tempCanvas
local t = 0

-- Disk and ring colours, prepended to LENS_SHADER as macros (constants, so
-- the hole's own shader compiles to exactly what it always did)
local HOT_PALETTE = [[
#define DISK_HOT vec3(1.0, 0.92, 0.70)
#define DISK_WARM vec3(0.95, 0.35, 0.08)
#define RING_COLOR vec3(1.0, 0.85, 0.65)
]]
-- The black hole gun's (blackholeGun.lua): blue-white through violet, like the portal gun's glow
local COLD_PALETTE = [[
#define DISK_HOT vec3(0.85, 0.93, 1.0)
#define DISK_WARM vec3(0.45, 0.22, 1.0)
#define RING_COLOR vec3(0.75, 0.85, 1.0)
]]

local LENS_SHADER = [[
uniform vec2  center;   // screen px
uniform float horizon;  // screen px
uniform float time;
uniform float slow;     // 0: time runs normally .. 1: as slow as it gets

const float LENS = 10.0;

vec3 diskColor(float k) {
    // white-hot at the inner edge, through orange to a dim red rim
    return mix(DISK_HOT, DISK_WARM, smoothstep(0.0, 0.6, k))
         * (1.0 - 0.55 * smoothstep(0.5, 1.0, k));
}

float bands(float a, float rd) {
    return 0.62 + 0.22 * sin(a * 5.0 - time * 2.6 + rd * 0.11)
                + 0.16 * sin(a * 11.0 + time * 4.1 - rd * 0.23);
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec2 d = sc - center;
    float r = length(d);
    float rs = horizon;
    vec2 size = love_ScreenSize.xy;

    // Lensing: what shows at radius r comes from nearer the hole (and, inside
    // the Einstein ring, from its far side); it fades out past LENS horizons
    float e2 = 2.4 * rs * rs;
    float bend = e2 / max(r, 0.5 * rs) * (1.0 - smoothstep(0.6 * LENS * rs, LENS * rs, r));
    // and the scene is dragged round with its spin
    float swirl = 0.35 * rs * rs / max(r * r, rs * rs);
    vec2 dir = r > 0.0 ? d / r : vec2(1.0, 0.0);
    float cs = cos(swirl), sn = sin(swirl);
    dir = vec2(cs * dir.x - sn * dir.y, sn * dir.x + cs * dir.y);
    vec2 src = center + dir * (r - bend);
    vec4 scene = Texel(tex, clamp(src / size, vec2(0.0), vec2(1.0)));

    // The shadow: nothing comes back from inside the horizon
    float lit = smoothstep(rs * 0.92, rs * 1.08, r);
    vec3 rgb = scene.rgb * lit;
    float alpha = mix(1.0, scene.a, lit);

    // Accretion disk, tilted towards us: its near half crosses in front of
    // the shadow, its far half is hidden behind it...
    vec2 q = vec2(d.x, d.y / 0.3);
    float rd = length(q);
    float a = atan(q.y, q.x);
    float k = (rd - 1.45 * rs) / (2.4 * rs);
    float disk = smoothstep(-0.08, 0.04, k) * (1.0 - smoothstep(0.75, 1.0, k));
    disk *= bands(a, rd);
    disk *= 1.0 + 0.55 * cos(a + 0.6);            // the side spinning towards us is brighter
    if (d.y < 0.0) disk *= lit;                    // behind the hole
    vec3 glow = diskColor(clamp(k, 0.0, 1.0)) * disk;

    // ...and lensed up over the top of it as an arc
    float arcR = 1.5 * rs + 0.25 * rs * clamp(-d.y / rs, 0.0, 1.0);
    float arc = exp(-pow((r - arcR) / (0.22 * rs), 2.0)) * smoothstep(0.3 * rs, -0.6 * rs, d.y);
    glow += diskColor(0.15) * arc * 0.7 * bands(atan(d.y, d.x), r);

    // Photon ring, thin and bright right at the shadow's edge
    float ring = exp(-pow((r - 1.12 * rs) / (0.07 * rs), 2.0));
    glow += RING_COLOR * ring * (0.6 + 0.2 * sin(atan(d.y, d.x) * 3.0 + time * 5.0));

    // Only the hottest part counts as a wall for GI, which spreads its colour
    // round (all of it made the whole neighbourhood glare white)
    rgb = rgb * (1.0 - 0.5 * min(disk, 1.0)) + glow;
    alpha = max(alpha, smoothstep(0.55, 1.1, dot(glow, vec3(0.299, 0.587, 0.114))));

    // Slow time: colder, greyer, darker at the edges
    if (slow > 0.0) {
        float grey = dot(rgb, vec3(0.299, 0.587, 0.114));
        vec3 cold = mix(rgb, vec3(grey) * vec3(0.78, 0.9, 1.15), 0.65 * slow);
        float vig = 1.0 - 0.45 * slow * smoothstep(0.35, 0.95, length(sc / size - 0.5) * 1.6);
        rgb = cold * vig;
    }
    return vec4(rgb, alpha) * color;
}
]]

function blackhole.load()
    lensShader = love.graphics.newShader(HOT_PALETTE .. LENS_SHADER)
    smallLensShader = love.graphics.newShader(COLD_PALETTE .. LENS_SHADER)
    blackhole.timeScale, hostScale, t = 1, 1, 0
    driftX, driftY = 0, 0
end

-- How slow time runs at distance d (1 = normal)
local function dilation(d)
    if d >= SLOW_RADIUS then return 1 end
    local k = 1 - math.max(0, d - HORIZON) / (SLOW_RADIUS - HORIZON)
    return 1 - (1 - MIN_SCALE) * k ^ 1.6
end

local function pullAt(x, y, radius)
    local dx, dy = blackhole.x - x, blackhole.y - y
    local d2 = dx * dx + dy * dy
    if d2 > radius * radius or d2 < 1 then return 0, 0, math.sqrt(d2) end
    local d = math.sqrt(d2)
    local a = math.min(MAX_PULL, PULL / d2)
    return dx / d * a, dy / d * a, d
end

local function pullBody(body, dt, radius)
    local ax, ay, d = pullAt(body:getX(), body:getY(), radius)
    if ax ~= 0 or ay ~= 0 then
        local vx, vy = body:getLinearVelocity()
        body:setLinearVelocity(vx + ax * dt, vy + ay * dt)
    end
    return d
end

local function distanceTo(x, y)
    return math.sqrt((x - blackhole.x) ^ 2 + (y - blackhole.y) ^ 2)
end

--- Before the physics step. `dt` is real time: this sets the pace (so it
--- doesn't slow itself), then pulls with the slowed dt.
function blackhole.update(dt)
    t = t + dt
    if not (player and player.body) then return end
    local px, py = player.body:getPosition()

    -- The pace: from the nearest player (the host counts everyone)
    local target = dilation(distanceTo(px, py))
    if var.multiplayer == 1 then
        for _, p in pairs(renderer.networked_state.players) do
            if p.active and p.x then
                target = math.min(target, dilation(distanceTo(p.x, p.y)))
            end
        end
    elseif var.multiplayer then
        target = math.min(target, hostScale)
    end
    blackhole.timeScale = blackhole.timeScale + (target - blackhole.timeScale) * math.min(1, dt * 4)
    local sdt = dt * blackhole.timeScale

    -- The player is pulled on every side; the rest only where the world is run
    local ax, ay, d = pullAt(px, py, PULL_RADIUS)
    local keep = math.max(0, 1 - DRAG * sdt)
    driftX, driftY = (driftX + ax * sdt) * keep, (driftY + ay * sdt) * keep
    if driftX * driftX + driftY * driftY > 0.01 then
        local vx, vy = player.body:getLinearVelocity()
        player.body:setLinearVelocity(vx + driftX, vy + driftY)
    end
    if d < HORIZON + 4 and player.hurt then
        player.hurt(HURT_PER_SECOND * sdt)
    end
    if var.multiplayer and var.multiplayer ~= 1 then return end

    for i, e in ipairs(enemy.enemies) do
        if not e.dead and e.body and not e.body:isDestroyed() then
            if pullBody(e.body, sdt, ENEMY_PULL_RADIUS) < HORIZON then
                e:damageEnemy(math.huge) -- swallowed: dies, its light streams off
            end
        end
    end

    for i = #coin_bods, 1, -1 do
        local body = coin_bods[i]
        if pullBody(body, sdt, GLOB_PULL_RADIUS) < HORIZON then
            table.remove(coin_bods, i)
            body:destroy()
            var.num_coins = var.num_coins - 1
        end
    end

    -- Bullets bend round it (they fly at a set speed along inst.dir)
    for i = #bullet.instances, 1, -1 do
        local inst = bullet.instances[i]
        local x, y = inst.body:getPosition()
        local ax, ay, bd = pullAt(x, y, PULL_RADIUS)
        if bd < HORIZON then
            bullet.returnToPool(inst, i)
        elseif ax ~= 0 or ay ~= 0 then
            local k = BULLET_PULL * sdt / math.max(1, inst.speed)
            local nx, ny = inst.dir.x + ax * k, inst.dir.y + ay * k
            local n = math.sqrt(nx * nx + ny * ny)
            inst.dir = vec2.new(nx / n, ny / n)
        end
    end
end

--- Its warm light on the ground round it. Before the lighting upload.
function blackhole.addLights()
    shadow.addTransientLight(blackhole.x, blackhole.y + 20, 0.5, 200)
end

--- Move it (the console's `blackhole`).
function blackhole.moveTo(x, y)
    blackhole.x, blackhole.y = x, y
    driftX, driftY = 0, 0
end

--- Multiplayer: the host sends where it is and the shared pace...
function blackhole.getNetworkData()
    return { x = math.floor(blackhole.x + 0.5), y = math.floor(blackhole.y + 0.5),
        s = math.floor(blackhole.timeScale * 1000 + 0.5) / 1000 }
end

--- ...and clients take both.
function blackhole.applyNetworkData(data)
    if data then
        blackhole.x, blackhole.y = data.x or blackhole.x, data.y or blackhole.y
        hostScale = data.s or 1
    end
end

-- Bend scene_canvas round a hole at screen (cx, cy) through `shader`, via
-- tempCanvas. With `clip` (a screen rect {x, y, w, h}) only that is touched.
local function lens(shader, cx, cy, horizon, slow, clip)
    local sw, sh = scene_canvas:getDimensions()
    if not tempCanvas or tempCanvas:getWidth() ~= sw or tempCanvas:getHeight() ~= sh then
        tempCanvas = love.graphics.newCanvas(sw, sh, { format = "rgba8" })
    end
    shader:send("center", { cx, cy })
    shader:send("horizon", horizon)
    shader:send("time", t)
    shader:send("slow", slow)

    -- Exact copies both ways (see explosion.applyShockwave)
    local r, g, b, a = love.graphics.getColor()
    local mode, alphaMode = love.graphics.getBlendMode()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setCanvas(tempCanvas)
    if clip then love.graphics.setScissor(clip[1], clip[2], clip[3], clip[4]) end
    love.graphics.setShader(shader)
    love.graphics.draw(scene_canvas)
    love.graphics.setShader()
    love.graphics.setCanvas(scene_canvas)
    if clip then love.graphics.setScissor(clip[1], clip[2], clip[3], clip[4]) end
    love.graphics.draw(tempCanvas)
    if clip then love.graphics.setScissor() end
    love.graphics.setBlendMode(mode, alphaMode)
    love.graphics.setColor(r, g, b, a)
end

--------------------------------------------------------------------------------
-- Low graphics
--------------------------------------------------------------------------------

-- The disk's colours, as LENS_SHADER has them (HOT_PALETTE)
local DISK_HOT, DISK_WARM, RING = { 1.0, 0.92, 0.70 }, { 0.95, 0.35, 0.08 }, { 1.0, 0.85, 0.65 }
local function smoothstep(a, b, x)
    local k = math.max(0, math.min(1, (x - a) / (b - a)))
    return k * k * (3 - 2 * k)
end
-- white-hot at the inner edge, through orange to a dim red rim
local function diskColor(k)
    local m, dim = smoothstep(0, 0.6, k), 1 - 0.55 * smoothstep(0.5, 1, k)
    return (DISK_HOT[1] + (DISK_WARM[1] - DISK_HOT[1]) * m) * dim,
        (DISK_HOT[2] + (DISK_WARM[2] - DISK_HOT[2]) * m) * dim,
        (DISK_HOT[3] + (DISK_WARM[3] - DISK_HOT[3]) * m) * dim
end
local function bands(a, rd)
    return 0.62 + 0.22 * math.sin(a * 5 - t * 2.6 + rd * 0.11) + 0.16 * math.sin(a * 11 + t * 4.1 - rd * 0.23)
end

local SEGMENTS = 40 -- round each half of the disk
local TILT = 0.3    -- the disk's height on screen over its width
local diskMesh, diskVerts = {}, {}

-- Half the disk (`far`: the top half, behind the shadow) as a mesh of
-- quads, each corner its band's colour and brightness
local function diskHalf(far)
    local verts = diskVerts[far]
    if not verts then
        verts = {}
        for i = 1, SEGMENTS * 6 do verts[i] = { 0, 0, 0, 0, 0, 0, 0, 0 } end
        diskVerts[far] = verts
        diskMesh[far] = love.graphics.newMesh(#verts, "triangles", "stream")
    end
    local inner, outer = 1.45 * HORIZON, 3.6 * HORIZON
    local a0 = far and math.pi or 0
    local function corner(v, a, rd)
        local k = (rd - 1.45 * HORIZON) / (2.4 * HORIZON)
        local glow = 1.4 * bands(a, rd) * (1 + 0.55 * math.cos(a + 0.6)) -- brighter spinning towards you
        local r, g, b = diskColor(k)
        v[1], v[2] = math.cos(a) * rd, math.sin(a) * rd * TILT
        v[5], v[6], v[7] = math.min(1, r * glow), math.min(1, g * glow), math.min(1, b * glow)
        v[8] = math.min(1, glow) * (1 - smoothstep(0.75, 1, k)) * smoothstep(-0.08, 0.04, k)
    end
    for i = 0, SEGMENTS - 1 do
        local a1 = a0 + math.pi * i / SEGMENTS
        local a2 = a0 + math.pi * (i + 1) / SEGMENTS
        local base = i * 6
        corner(verts[base + 1], a1, inner)
        corner(verts[base + 2], a1, outer)
        corner(verts[base + 3], a2, outer)
        corner(verts[base + 4], a1, inner)
        corner(verts[base + 5], a2, outer)
        corner(verts[base + 6], a2, inner)
    end
    diskMesh[far]:setVertices(verts)
    return diskMesh[far]
end

--- Low graphics: the stand-in for the lensing pass, in the sorted draw list
--- (renderer.lua's "blackhole" draw_type, blackhole.drawFallback).
function blackhole.populate()
    if var.graphics_high then return end
    table.insert(dynamic_draw_list, {
        draw_type = "blackhole",
        sort_y = blackhole.y + 140,
        x = blackhole.x,
        y = blackhole.y,
        color = { 1, 1, 1, 1 },
    })
end

function blackhole.drawFallback(d)
    local shader = love.graphics.getShader()
    local mode, alphaMode = love.graphics.getBlendMode()
    love.graphics.setShader()
    love.graphics.push()
    love.graphics.translate(d.x, d.y)

    -- a warm haze round it
    love.graphics.setBlendMode("add")
    love.graphics.setColor(DISK_WARM[1], DISK_WARM[2], DISK_WARM[3], 0.04)
    love.graphics.circle("fill", 0, 0, HORIZON * 3.4)
    love.graphics.setColor(DISK_WARM[1], DISK_WARM[2], DISK_WARM[3], 0.06)
    love.graphics.circle("fill", 0, 0, HORIZON * 2)
    -- the far half of the disk, behind it
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(diskHalf(true))
    -- the shadow
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.circle("fill", 0, 0, HORIZON)
    love.graphics.setBlendMode("add")
    -- the disk lensed up over the top of it as an arc
    local r, g, b = diskColor(0.15)
    love.graphics.setLineWidth(HORIZON * 0.3)
    for i = 0, 15 do
        local a1, a2 = math.pi + math.pi * i / 16, math.pi + math.pi * (i + 1) / 16
        local k = 0.7 * bands(a1, HORIZON * 1.6)
        love.graphics.setColor(r * k, g * k, b * k, 0.6)
        love.graphics.arc("line", "open", 0, 0, HORIZON * 1.6, a1, a2, 2)
    end
    -- the photon ring, thin and bright right at its edge
    love.graphics.setLineWidth(2)
    love.graphics.setColor(RING[1], RING[2], RING[3], 0.9)
    love.graphics.circle("line", 0, 0, HORIZON * 1.12)
    -- and the near half of the disk crossing in front
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(diskHalf(false))

    love.graphics.pop()
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode(mode, alphaMode)
    love.graphics.setShader(shader)
end

--- Low graphics, in screen space after the world: while time is slow, the
--- frame turns colder and darker at the edges, as the lensing pass turns it.
function blackhole.drawSlowTint()
    local slow = math.max(0, math.min(1, (1 - blackhole.timeScale) / (1 - MIN_SCALE)))
    if slow < 0.01 then return end
    local w, h = love.graphics.getDimensions()
    local mode, alphaMode = love.graphics.getBlendMode()
    love.graphics.setBlendMode("multiply", "premultiplied")
    love.graphics.setColor(1 - 0.35 * slow, 1 - 0.22 * slow, 1 - 0.05 * slow, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setBlendMode("alpha")
    -- darker at the edges
    local edge = math.min(w, h) * 0.12
    for i = 0, 3 do
        love.graphics.setColor(0, 0, 0.04, 0.09 * slow)
        local inset = i * edge * 0.5
        love.graphics.rectangle("fill", 0, 0, w, edge - inset)
        love.graphics.rectangle("fill", 0, h - edge + inset, w, edge - inset)
        love.graphics.rectangle("fill", 0, 0, edge - inset, h)
        love.graphics.rectangle("fill", w - edge + inset, 0, edge - inset, h)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode(mode, alphaMode)
end

--- Screen-space pass over scene_canvas, before GI (draw.lua): bends the
--- scene round the hole, draws its shadow, disk and ring, and turns the
--- frame cold while time is slow. Skipped when there's nothing to show.
function blackhole.applyLensing()
    local zoom = camera.zoom
    local cx, cy = camera.pos.x + blackhole.x * zoom, camera.pos.y + blackhole.y * zoom
    local reach = LENS_RADIUS * HORIZON * zoom
    local sw, sh = scene_canvas:getDimensions()
    local onScreen = cx + reach > 0 and cx - reach < sw and cy + reach > 0 and cy - reach < sh
    local slow = math.max(0, math.min(1, (1 - blackhole.timeScale) / (1 - MIN_SCALE)))
    if not onScreen and slow < 0.01 then
        return
    end
    lens(lensShader, cx, cy, HORIZON * zoom, slow)
end

--- The same pass for a small hole at world (x, y) whose shadow is `horizon`
--- px in radius, in the black hole gun's colder colours (blackholeGun.lua). Time
--- doesn't slow for it, so only the square round it that it bends is
--- touched, and nothing when that's off screen.
function blackhole.applySmallLensing(x, y, horizon)
    local zoom = camera.zoom
    local cx, cy = camera.pos.x + x * zoom, camera.pos.y + y * zoom
    local reach = LENS_RADIUS * horizon * zoom
    local sw, sh = scene_canvas:getDimensions()
    local x0, y0 = math.max(0, math.floor(cx - reach)), math.max(0, math.floor(cy - reach))
    local x1, y1 = math.min(sw, math.ceil(cx + reach)), math.min(sh, math.ceil(cy + reach))
    if x1 <= x0 or y1 <= y0 then
        return
    end
    lens(smallLensShader, cx, cy, horizon * zoom, 0, { x0, y0, x1 - x0, y1 - y0 })
end

return blackhole
