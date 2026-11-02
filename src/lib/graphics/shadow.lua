--[[============================================================================
  Lighting subsystem
  (historically `shadow.lua`; kept at this path / global name `shadow` so existing
   call sites keep working — the module is a deferred-shaded point-light system,
   not an occlusion/shadow system. True occlusion is handled by the JFA global
   illumination pass in `shader.lua`.)

  Responsibilities
  ----------------
    1. LightSet ........ an encapsulated, capacity-bounded pool of point lights.
    2. Object shader ... screen-space forward lighting for ordinary (non-instanced)
                         sprite/map draws.
    3. Frame upload .... per frame, cull lights to the view, then push them to the
                         object shader (screen space) and to the instanced
                         character shader (world space).

  Coordinate spaces — the bug this rewrite fixes
  ----------------------------------------------
    `camera.apply()` does  scale(zoom) ; translate(camera.{x,y}/zoom)
    so a world point maps to the screen as:

        screen = world * zoom + camera.{x,y}

    Ordinary draws (map, sorted sprites) have NO per-object model matrix exposed
    to their shader, so the old code's `pos` varying (derived from an *unbound*
    `InstancePosition` attribute) was meaningless — lighting was computed in local
    quad space and never matched the lights. We instead light those draws in screen
    space using the built-in `screen_coords`, and upload lights pre-transformed to
    screen space (position AND range scaled by zoom, so falloff matches the world).

    The instanced character shader (`characterAnimator.shader`) reconstructs a real
    world position from its instance matrix, so it is fed lights in world space.
    Both spaces use the identical attenuation model, so everything stays consistent.
============================================================================]]--

local lighting = {}
local normalmap = require("lib.graphics.normalmap")

--==========================================================================--
-- Configuration
--==========================================================================--

-- Hard cap on simultaneous lights. Must not exceed the array size declared in
-- the shaders (object shader below + characterAnimator's `lights[MAX_LIGHTS]`).
lighting.MAX_LIGHTS = 64

-- Ambient floor: unlit / indoor areas are dimmed to this, never pure black.
lighting.ambient = 0.20

-- Default key light that follows the player so the play area is always lit.
lighting.PLAYER_LIGHT_RANGE     = 450
lighting.PLAYER_LIGHT_INTENSITY = 1.0

-- How high the lights are over the ground (world px), for which way they
-- strike an upright thing's normals: about head height, as in regions'
-- sprite shader
lighting.LIGHT_HEIGHT = 40

--==========================================================================--
-- LightSet — encapsulated light pool
--
-- A light is { x, y, intensity, range }. `intensity` may be negative (a
-- "dark" light) but `range` must be > 0 or the light is ignored (a zero range
-- previously produced divide-by-zero NaNs -> black speckles).
--==========================================================================--

local lights = {}

--- Add a light. Returns its index, or nil if the pool is full.
function lighting.addLight(x, y, intensity, range)
    if #lights >= lighting.MAX_LIGHTS then
        return nil
    end
    lights[#lights + 1] = {
        x         = x or 0,
        y         = y or 0,
        intensity = intensity or 1.0,
        range     = range or 200,
    }
    return #lights
end

function lighting.removeLight(index)
    if index and index > 0 and index <= #lights then
        table.remove(lights, index)
    end
end

function lighting.updateLight(index, x, y, intensity, range)
    local l = lights[index]
    if not l then return end
    l.x         = x         or l.x
    l.y         = y         or l.y
    l.intensity = intensity or l.intensity
    l.range     = range     or l.range
end

function lighting.clearLights()
    lights = {}
end

function lighting.count()
    return #lights
end

-- One-frame lights (muzzle flashes and the like): submitted every frame they
-- should shine, before lighting.update, which uploads them after the pool's
-- lights (into whatever slots are left) and then forgets them. `beam` marks
-- the flashlight's (below).
local transientLights = {}

function lighting.addTransientLight(x, y, intensity, range, beam)
    if range and range > 0 then
        transientLights[#transientLights + 1] = { x = x, y = y, intensity = intensity or 1.0, range = range,
            beam = beam }
    end
end

--==========================================================================--
-- What stands in the way
--
-- Lights don't shine through what stands on the ground. Where each thing
-- stands is a footprint, segments along the ground (lighting.eachFoot:
-- lib/graphics/footprint.lua for sprites, the house's walls, the car's
-- body). Each frame lighting.update works out, for every light, how far it
-- reaches in each of BINS directions round it before one is in the way: a
-- row of the reach map (REACH_SHADER), and every lit shader leaves a light
-- out of a point beyond that (REACH_GLSL's lightReaches: the point on the
-- ground, or for an upright thing the ground under it, a character's feet).
-- A light's row rides in its range: w = range + row * LIGHT_SLOT.
--
-- The flashlight's lights go by where the flashlight is, not where they
-- are: it hands over its origin and the footprints in its beam
-- (lighting.setBeam, systems/light.lua), and its lights are left out of
-- whatever the line from there crosses one to (beamReaches), so none of it
-- lands past a wall or in a pillar's shadow.
--==========================================================================--

lighting.MAX_BEAM_FEET = 64
lighting.MAX_OCCLUDERS = 256 -- footprint segments the reach map takes, nearest the player first
lighting.REACH_BINS = 512    -- directions round each light
local LIGHT_SLOT = 8192      -- a light's range is under this (screen px too: 450 x zoom)

lighting.REACH_GLSL = [[
    #define MAX_BEAM_FEET 64
    const float LIGHT_SLOT = 8192.0;
    const float REACH_BINS = 512.0;
    const float REACH_BIAS = 3.0;         // px: a wall is lit where it stands

    uniform Image lightReach;             // a row per light: how far it gets each way, of its range
    uniform float lightRows;              // rows in lightReach
    uniform bool  lightsBlocked;          // anything in the way this frame

    uniform vec2 beamLights;              // lights[x] to lights[x + y - 1] are the flashlight's
    uniform vec2 beamOrigin;              // where it shines from
    uniform int  numBeamFeet;
    uniform vec4 beamFeet[MAX_BEAM_FEET]; // what's in its way: segments where things stand

    // Light l's range (its row rides in it)
    float lightRange(vec4 l) {
        return l.w - floor(l.w / LIGHT_SLOT) * LIGHT_SLOT;
    }

    float reachAt(float bin, float row) {
        vec4 c = Texel(lightReach, vec2((mod(bin, REACH_BINS) + 0.5) / REACH_BINS, row));
        return (floor(c.r * 255.0 + 0.5) * 256.0 + floor(c.g * 255.0 + 0.5)) / 65535.0;
    }

    // How much of light l (range `range`) reaches ground point p: 1, or 0
    // beyond what's in its way that way (soft across one direction's width)
    float lightReaches(vec4 l, float range, vec2 p) {
        if (!lightsBlocked) return 1.0;
        vec2 d = p - l.xy;
        float dist = length(d);
        if (dist <= REACH_BIAS) return 1.0;
        float row = (floor(l.w / LIGHT_SLOT) + 0.5) / lightRows;
        float x = (atan(d.y, d.x) / 6.28318531 + 0.5) * REACH_BINS - 0.5;
        float bin = floor(x);
        float r0 = reachAt(bin, row) * range + REACH_BIAS;
        float r1 = reachAt(bin + 1.0, row) * range + REACH_BIAS;
        return mix(dist <= r0 ? 1.0 : 0.0, dist <= r1 ? 1.0 : 0.0, x - bin);
    }

    bool isBeamLight(int i) {
        float k = float(i);
        return k >= beamLights.x && k < beamLights.x + beamLights.y;
    }

    // 1 if the flashlight reaches ground point p, 0 if something's in the
    // way (short of the last 2 px, so a wall is lit where it stands)
    float beamReaches(vec2 p) {
        vec2 d = p - beamOrigin;
        float len = length(d);
        if (len <= 2.0) return 1.0;
        float limit = 1.0 - 2.0 / len;
        for (int i = 0; i < MAX_BEAM_FEET; i++) {
            if (i >= numBeamFeet) break;
            vec2 a = beamFeet[i].xy - beamOrigin;
            vec2 e = beamFeet[i].zw - beamFeet[i].xy;
            float den = d.x * e.y - d.y * e.x;
            if (abs(den) < 1e-6) continue; // running alongside it
            float t = (a.x * e.y - a.y * e.x) / den; // how far along the way to p it's crossed
            float u = (a.x * d.y - a.y * d.x) / den; // and where along it
            if (t > 0.0 && t < limit && u >= 0.0 && u <= 1.0) return 0.0;
        }
        return 1.0;
    }

    // How much of lights[i] (l, range `range`) reaches ground point p;
    // beam caches beamReaches(p) (start it at -1)
    float reaches(int i, vec4 l, float range, vec2 p, inout float beam) {
        if (isBeamLight(i)) {
            if (beam < 0.0) beam = beamReaches(p);
            return beam;
        }
        return lightReaches(l, range, p);
    }
]]

-- The reach map: a row per light (world space), a column per direction
local REACH_SHADER = [[
    #define MAX_LIGHTS 64
    #define MAX_OCCLUDERS 256
    const float LIGHT_SLOT = 8192.0;
    const float REACH_BINS = 512.0;
    uniform vec4 lights[MAX_LIGHTS];         // world px, rows riding in w
    uniform int  numOccluders;
    uniform vec4 occluders[MAX_OCCLUDERS];   // footprint segments, world px

    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 screen_coords) {
        float row = floor(screen_coords.y);
        vec4 l = vec4(0.0);
        for (int i = 0; i < MAX_LIGHTS; i++) {
            if (float(i) == row) { l = lights[i]; break; }
        }
        float range = l.w - floor(l.w / LIGHT_SLOT) * LIGHT_SLOT;
        float angle = (floor(screen_coords.x) + 0.5) / REACH_BINS * 6.28318531 - 3.14159265;
        vec2 d = vec2(cos(angle), sin(angle));
        float best = range;
        for (int i = 0; i < MAX_OCCLUDERS; i++) {
            if (i >= numOccluders) break;
            vec2 a = occluders[i].xy - l.xy;
            vec2 e = occluders[i].zw - occluders[i].xy;
            float den = d.x * e.y - d.y * e.x;
            if (abs(den) < 1e-6) continue;
            float t = (a.x * e.y - a.y * e.x) / den;
            float u = (a.x * d.y - a.y * d.x) / den;
            if (t > 0.0 && t < best && u >= 0.0 && u <= 1.0) best = t;
        }
        float h = floor((range > 0.0 ? best / range : 1.0) * 65535.0 + 0.5);
        float hi = floor(h / 256.0);
        return vec4(hi / 255.0, (h - hi * 256.0) / 255.0, 0.0, 1.0);
    }
]]

local beamX, beamY, beamWorldFeet -- this frame's, from lighting.setBeam

--- Where the flashlight shines from this frame (world px) and what's in its
--- way: a flat list {x0, y0, x1, y1, ...} of segments (world px, nearest
--- first). Before lighting.update; nothing (nil) while it's off.
function lighting.setBeam(x, y, feet)
    beamX, beamY, beamWorldFeet = x, y, feet
end

-- Whether (px, py) is inside the closed footprint `feet` (an odd number of
-- its segments cross the line from it to the right)
local function inside(feet, px, py)
    local odd = false
    for i = 1, #feet, 4 do
        local ax, ay, bx, by = feet[i], feet[i + 1], feet[i + 2], feet[i + 3]
        if (ay > py) ~= (by > py) and ax + (py - ay) * (bx - ax) / (by - ay) > px then
            odd = not odd
        end
    end
    return odd
end

local carFeet = {}

--- fn(x0, y0, x1, y1) for each segment of what stands in the world rect
--- x0, y0 - x1, y1 (world px): region sprites', the arch's and the tree's
--- footprints (lib/graphics/footprint.lua), the house's walls and the parked
--- car's body. Not a sprite's whose footprint (px, py) is in (someone can
--- walk into a prop's: their light isn't shut in there with them).
function lighting.eachFoot(x0, y0, x1, y1, px, py, fn)
    local function each(feet, solid)
        if solid and inside(feet, px, py) then return end
        for i = 1, #feet, 4 do
            fn(feet[i], feet[i + 1], feet[i + 2], feet[i + 3])
        end
    end
    regions.eachFoot(x0, y0, x1, y1, function(feet) each(feet, true) end)
    for _, list in ipairs({ map.archInstances, map.treeInstances, map.houseInstances }) do
        for _, o in ipairs(list) do
            if o.active and o.feet then each(o.feet, list ~= map.houseInstances) end -- (walls, not a solid)
        end
    end
    for _, c in ipairs(car.cars or {}) do
        if c.body and not c.inUse then
            local cx, cy = c.body:getPosition()
            if cx > x0 - 100 and cx < x1 + 100 and cy > y0 - 100 and cy < y1 + 100 then
                for _, fixture in ipairs(c.body:getFixtures()) do
                    local shape = fixture:getShape()
                    if shape:getType() == "polygon" then
                        local pts = { c.body:getWorldPoints(shape:getPoints()) }
                        local k = 0
                        for i = 1, #pts, 2 do
                            local j = i + 2 <= #pts and i + 2 or 1
                            carFeet[k + 1], carFeet[k + 2], carFeet[k + 3], carFeet[k + 4] =
                                pts[i], pts[i + 1], pts[j], pts[j + 1]
                            k = k + 4
                        end
                        for i = #carFeet, k + 1, -1 do carFeet[i] = nil end
                        each(carFeet, false)
                    end
                end
            end
        end
    end
end

--==========================================================================--
-- Shaders
--==========================================================================--

-- The one true forward-lighting model, shared (in spirit) with the character
-- shader. Lights and the fragment are expressed in the SAME space by the caller
-- (screen space here), so the math is space-agnostic.
-- An upright thing with a normal map (lighting.setNormals) is shaded by it
-- too: each texel stands over the point on its ground line below it, and
-- faces each light, and the sky, or not (lib/graphics/normalmap.lua).
local OBJECT_SHADER_SRC = normalmap.GLSL .. lighting.REACH_GLSL .. [[
    #define MAX_LIGHTS 64

    uniform int   numLights;
    uniform vec4  lights[MAX_LIGHTS]; // (x, y, intensity, range) in screen px
    uniform float u_ambient;          // ambient floor; <= 0 falls back to 0.20

    uniform bool  hasNormals;  // this draw is an upright thing with normalMap
    uniform Image normalMap;
    uniform float baseY;       // its ground line, screen px
    uniform float lightHeight; // the lights' height, screen px

    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 screen_coords) {
        vec4 texColor = Texel(tex, tc);

        float ambient = (u_ambient > 0.0) ? u_ambient : 0.20;
        vec3 n = vec3(0.0, 0.0, 1.0);
        float zs = 0.0; // the texel's height over its ground line
        vec2 ground = screen_coords; // the point on the ground under it
        if (hasNormals) {
            n = faceNormal(normalMap, tc);
            zs = max(0.0, baseY - screen_coords.y);
            ambient *= skyShade(n);
            ground.y = baseY;
        }
        float beam = -1.0; // beamReaches(ground), once a beam light needs it

        float totalLight = 0.0;
        for (int i = 0; i < MAX_LIGHTS; i++) {
            if (i >= numLights) break;               // honour the live count

            float range = lightRange(lights[i]);
            if (range <= 0.0) continue;              // skip empty / zero-range slots

            float dist = distance(lights[i].xy, screen_coords);
            if (dist >= range) continue;             // outside this light's reach

            float att = 1.0 - dist / range;          // smooth quadratic falloff
            att *= att;
            if (hasNormals) {
                att *= faceShade(n, vec3(lights[i].x - screen_coords.x,
                    lights[i].y - baseY, lightHeight - zs));
            }
            att *= reaches(i, lights[i], range, ground, beam); // not past what's in the way
            totalLight += att * lights[i].z;
        }

        // Saturate toward full albedo when well lit; bottom out at the ambient floor.
        float lit = min(1.0, ambient + totalLight);
        return vec4(texColor.rgb * lit * color.rgb, texColor.a * color.a);
    }
]]

local objectShader
local reachShader, reachMap

function lighting.load()
    objectShader = love.graphics.newShader(OBJECT_SHADER_SRC)
    -- (a GPU without room for its uniforms just lets light through)
    local ok, shader = pcall(love.graphics.newShader, REACH_SHADER)
    reachShader = ok and shader or nil
    reachMap = love.graphics.newCanvas(lighting.REACH_BINS, lighting.MAX_LIGHTS, { format = "rgba8", dpiscale = 1 })
    reachMap:setFilter("nearest", "nearest")
    lighting.clearLights()
    lighting.setupDefaultLights()
end

--- Seed the scene with the default key light (index 1) that tracks the player.
function lighting.setupDefaultLights()
    lighting.addLight(0, 0, lighting.PLAYER_LIGHT_INTENSITY, lighting.PLAYER_LIGHT_RANGE)
end

--- Returns the forward-lighting shader for ordinary draws.
-- `useCamera` is retained for call-site compatibility; both the map pass and the
-- sprite pass now light in screen space, so a single shader serves both.
function lighting.getShader(useCamera)
    return objectShader
end

--==========================================================================--
-- Per-frame upload
--==========================================================================--

-- Reused scratch tables so the hot path allocates nothing per frame.
local screenLights = {}
local worldLights  = {}
local lightIsBeam  = {} -- whether each is the flashlight's
local beamRange    = { 0, 0 } -- where the flashlight's lights are: first (from 0), count
local screenBeamOrigin, worldBeamOrigin = { 0, 0 }, { 0, 0 }
local screenBeamFeet, worldBeamFeet = {}, {}
local occluders, nearby = {}, {} -- the reach map's segments; scratch while gathering
local blocked = false           -- whether the reach map has anything in it

-- What stands in the way (REACH_GLSL), lights[range] being the flashlight's
local function sendReach(shader, origin, feet, range)
    shader:send("lightsBlocked", blocked)
    if blocked then
        shader:send("lightReach", reachMap)
        shader:send("lightRows", lighting.MAX_LIGHTS)
    end
    shader:send("beamLights", range)
    shader:send("beamOrigin", origin)
    shader:send("numBeamFeet", #feet)
    if #feet > 0 then shader:send("beamFeet", unpack(feet)) end
end

-- Each light's reach round it, into reachMap: the footprints near enough to
-- any of the n lights (nearest the player first), then a row per light
local function mapReach(n, px, py)
    blocked = false
    if not reachShader or n == 0 or not var.light_shadows then return end -- (Settings > Shadows)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for i = 1, n do
        local l = worldLights[i]
        x0, y0 = math.min(x0, l[1] - l[5]), math.min(y0, l[2] - l[5])
        x1, y1 = math.max(x1, l[1] + l[5]), math.max(y1, l[2] + l[5])
    end
    local m = 0
    lighting.eachFoot(x0, y0, x1, y1, px, py, function(ax, ay, bx, by)
        m = m + 1
        local f = nearby[m] or {}
        f[1], f[2], f[3], f[4] = ax, ay, bx, by
        f[5] = math.min((ax - px) ^ 2 + (ay - py) ^ 2, (bx - px) ^ 2 + (by - py) ^ 2)
        nearby[m] = f
    end)
    for i = #nearby, m + 1, -1 do nearby[i] = nil end
    if m == 0 then return end
    if m > lighting.MAX_OCCLUDERS then
        table.sort(nearby, function(a, b) return a[5] < b[5] end)
        m = lighting.MAX_OCCLUDERS
    end
    for i = 1, m do occluders[i] = nearby[i] end
    for i = #occluders, m + 1, -1 do occluders[i] = nil end

    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setScissor()
    love.graphics.setCanvas(reachMap)
    love.graphics.setShader(reachShader)
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    reachShader:send("lights", unpack(worldLights))
    reachShader:send("numOccluders", m)
    reachShader:send("occluders", unpack(occluders))
    love.graphics.rectangle("fill", 0, 0, lighting.REACH_BINS, n)
    love.graphics.pop()
    blocked = true
end

--- Cull lights to the visible region, build the screen- and world-space arrays,
--- and upload them to the object shader and the instanced character shader.
function lighting.update(dt)
    -- Keep the key light locked to the player; dimmed to nothing while indoors
    -- (indoor illumination is provided by the neon/god-ray pass in light.lua).
    if lights[1] and player and player.body then
        lights[1].x, lights[1].y = player.body:getPosition()
        lights[1].intensity = var.indoors and 0 or lighting.PLAYER_LIGHT_INTENSITY
    end

    local zoom = camera.zoom
    local camX, camY = camera.x, camera.y

    -- View bounds in world space (padded), centred on the player.
    local halfW = var.screen_width  / 2 + 100
    local halfH = var.screen_height / 2 + 100
    local viewX, viewY = 0, 0
    if player and player.body then
        viewX, viewY = player.body:getPosition()
    end

    local n = 0
    local cap = math.min(lighting.MAX_LIGHTS, var.max_lights or lighting.MAX_LIGHTS) -- Settings > Max Lights
    local function cull(list)
        for i = 1, #list do
            local l = list[i]
            if n < cap and l.range > 0 and not (
                    l.x + l.range < viewX - halfW or
                    l.x - l.range > viewX + halfW or
                    l.y + l.range < viewY - halfH or
                    l.y - l.range > viewY + halfH) then
                n = n + 1
                lightIsBeam[n] = l.beam or false
                -- Its row in the reach map rides in its range (REACH_GLSL),
                -- the range itself fifth, for culling here.
                local slot = (n - 1) * LIGHT_SLOT
                -- World space for the instanced character shader.
                worldLights[n]  = { l.x, l.y, l.intensity, l.range + slot, l.range }
                -- Screen space for ordinary draws: position AND range scaled by zoom
                -- so on-screen falloff matches the world falloff at any zoom.
                screenLights[n] = { l.x * zoom + camX, l.y * zoom + camY, l.intensity,
                    l.range * zoom + slot, l.range * zoom }
            end
        end
    end
    cull(lights)
    cull(transientLights)
    for i = #transientLights, 1, -1 do transientLights[i] = nil end
    -- Drop stale trailing entries from previous, busier frames.
    for i = #screenLights, n + 1, -1 do
        screenLights[i] = nil
        worldLights[i]  = nil
        lightIsBeam[i]  = nil
    end

    -- The flashlight's lights (it adds them together, so they're in a row)
    -- and what's in its way, in both spaces
    local first, count = 0, 0
    for i = 1, n do
        if lightIsBeam[i] then
            if count == 0 then first = i - 1 end
            count = count + 1
        end
    end
    beamRange[1], beamRange[2] = first, count
    local m = 0
    if count > 0 and beamX then
        screenBeamOrigin[1], screenBeamOrigin[2] = beamX * zoom + camX, beamY * zoom + camY
        worldBeamOrigin[1], worldBeamOrigin[2] = beamX, beamY
        local f = beamWorldFeet
        m = math.min(#f / 4, lighting.MAX_BEAM_FEET)
        for i = 1, m do
            local w, sc = worldBeamFeet[i] or {}, screenBeamFeet[i] or {}
            w[1], w[2], w[3], w[4] = f[4 * i - 3], f[4 * i - 2], f[4 * i - 1], f[4 * i]
            sc[1], sc[2] = w[1] * zoom + camX, w[2] * zoom + camY
            sc[3], sc[4] = w[3] * zoom + camX, w[4] * zoom + camY
            worldBeamFeet[i], screenBeamFeet[i] = w, sc
        end
    end
    for i = #screenBeamFeet, m + 1, -1 do
        screenBeamFeet[i], worldBeamFeet[i] = nil, nil
    end

    lighting.shown = n -- lights this frame's draws are lit by
    mapReach(n, viewX, viewY)

    -- Object shader (screen space). Always set the count; only unpack a non-empty
    -- array (unpack of an empty table errors). count == 0 -> ambient-only fallback.
    objectShader:send("numLights", n)
    objectShader:send("u_ambient", lighting.ambient)
    objectShader:send("lightHeight", lighting.LIGHT_HEIGHT * zoom)
    if n > 0 then
        objectShader:send("lights", unpack(screenLights))
    end
    sendReach(objectShader, screenBeamOrigin, screenBeamFeet, beamRange)

    -- Instanced character shader (world space).
    if characterAnimator and characterAnimator.shader then
        characterAnimator.shader:send("numLights", n)
        characterAnimator.shader:send("u_ambient", lighting.ambient)
        if n > 0 then
            characterAnimator.shader:send("lights", unpack(worldLights))
        end
        sendReach(characterAnimator.shader, worldBeamOrigin, worldBeamFeet, beamRange)
    end
end

--- Light the object shader's next draws as an upright thing with this
--- normal map (lib/graphics/normalmap.lua) standing on world row baseY;
--- nil goes back to lighting them flat.
function lighting.setNormals(normals, baseY)
    if normals then
        objectShader:send("normalMap", var.normal_maps and normals or normalmap.flat()) -- (Settings > Normal Maps)
        objectShader:send("baseY", baseY * camera.zoom + camera.y)
        objectShader:send("hasNormals", true)
    else
        objectShader:send("hasNormals", false)
    end
end

--- Upload this frame's screen-space lights to another shader that declares
--- the object shader's uniforms (numLights, lights, u_ambient), so it is lit
--- the same way. Call after lighting.update.
function lighting.sendLights(shader)
    local n = #screenLights
    shader:send("numLights", n)
    shader:send("u_ambient", lighting.ambient)
    if n > 0 then
        shader:send("lights", unpack(screenLights))
    end
    if shader:hasUniform("beamLights") then
        sendReach(shader, screenBeamOrigin, screenBeamFeet, beamRange)
    end
end

--==========================================================================--
-- Tiled draws
--
-- A full-screen draw lit by many lights loops over all of them at every
-- pixel, though most only reach a corner of the screen (a street of lamps,
-- a spill of XP globs). Drawn once per screen tile instead, under a scissor,
-- each tile is sent only the lights that reach it, in their order: every
-- pixel then adds up the same lights in the same order and comes out
-- exactly as before, for a fraction of the work. With few lights the extra
-- draws aren't worth it, so it is one plain draw below TILE_MIN_LIGHTS.
--==========================================================================--

lighting.TILE_SIZE = 400 -- px, about
lighting.TILE_MIN_LIGHTS = 12

local tileLights = {}
local tileBeam = { 0, 0 }

--- Draw `draw(y0, y1)` lit through `shader` (bound, and sent this frame's
--- lights: lighting.sendLights), tile by tile over the render target;
--- y0..y1 is the band of screen rows the call must cover (the whole target
--- when untiled). Leaves `shader` with the full light list again.
function lighting.drawTiled(shader, draw)
    local n = #screenLights
    local canvas = love.graphics.getCanvas()
    local w, h
    if canvas then w, h = canvas:getDimensions() else w, h = love.graphics.getDimensions() end
    if n < lighting.TILE_MIN_LIGHTS then
        draw(0, h)
        return
    end

    local sx, sy, sw, sh = love.graphics.getScissor()
    local beamShader = shader:hasUniform("beamLights")
    local cols = math.max(1, math.ceil(w / lighting.TILE_SIZE))
    local rows = math.max(1, math.ceil(h / lighting.TILE_SIZE))
    for row = 0, rows - 1 do
        local y0, y1 = math.floor(h * row / rows), math.floor(h * (row + 1) / rows)
        for col = 0, cols - 1 do
            local x0, x1 = math.floor(w * col / cols), math.floor(w * (col + 1) / cols)
            -- the tile within any scissor already set
            local cx0, cy0, cx1, cy1 = x0, y0, x1, y1
            if sx then
                cx0, cy0 = math.max(cx0, sx), math.max(cy0, sy)
                cx1, cy1 = math.min(cx1, sx + sw), math.min(cy1, sy + sh)
            end
            if cx1 > cx0 and cy1 > cy0 then
                -- the lights whose reach (the shader's dist < range) touches
                -- the tile, a pixel's slack for rounding
                local k = 0
                tileBeam[1], tileBeam[2] = 0, 0
                for i = 1, n do
                    local l = screenLights[i]
                    local dx = math.max(cx0 - l[1], 0, l[1] - cx1)
                    local dy = math.max(cy0 - l[2], 0, l[2] - cy1)
                    if l[5] > 0 and dx * dx + dy * dy < (l[5] + 1) ^ 2 then
                        k = k + 1
                        tileLights[k] = l
                        if lightIsBeam[i] then
                            if tileBeam[2] == 0 then tileBeam[1] = k - 1 end
                            tileBeam[2] = tileBeam[2] + 1
                        end
                    end
                end
                for i = #tileLights, k + 1, -1 do tileLights[i] = nil end
                love.graphics.setScissor(cx0, cy0, cx1 - cx0, cy1 - cy0)
                shader:send("numLights", k)
                if k > 0 then shader:send("lights", unpack(tileLights)) end
                if beamShader then shader:send("beamLights", tileBeam) end
                draw(cy0, cy1)
            end
        end
    end
    love.graphics.setScissor(sx, sy, sw, sh)
    shader:send("numLights", n)
    shader:send("lights", unpack(screenLights))
    if beamShader then shader:send("beamLights", beamRange) end
end

-- Legacy alias: main.lua calls shadow.updateBothShaders(dt).
lighting.updateBothShaders = lighting.update

return lighting
