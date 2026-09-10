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

--==========================================================================--
-- Shaders
--==========================================================================--

-- The one true forward-lighting model, shared (in spirit) with the character
-- shader. Lights and the fragment are expressed in the SAME space by the caller
-- (screen space here), so the math is space-agnostic.
local OBJECT_SHADER_SRC = [[
    #define MAX_LIGHTS 64

    uniform int   numLights;
    uniform vec4  lights[MAX_LIGHTS]; // (x, y, intensity, range) in screen px
    uniform float u_ambient;          // ambient floor; <= 0 falls back to 0.20

    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 screen_coords) {
        vec4 texColor = Texel(tex, tc);

        float ambient = (u_ambient > 0.0) ? u_ambient : 0.20;

        float totalLight = 0.0;
        for (int i = 0; i < MAX_LIGHTS; i++) {
            if (i >= numLights) break;               // honour the live count

            float range = lights[i].w;
            if (range <= 0.0) continue;              // skip empty / zero-range slots

            float dist = distance(lights[i].xy, screen_coords);
            if (dist >= range) continue;             // outside this light's reach

            float att = 1.0 - dist / range;          // smooth quadratic falloff
            att *= att;
            totalLight += att * lights[i].z;
        }

        // Saturate toward full albedo when well lit; bottom out at the ambient floor.
        float lit = min(1.0, ambient + totalLight);
        return vec4(texColor.rgb * lit * color.rgb, texColor.a * color.a);
    }
]]

local objectShader

function lighting.load()
    objectShader = love.graphics.newShader(OBJECT_SHADER_SRC)
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
    for i = 1, #lights do
        local l = lights[i]
        if l.range > 0 and not (
                l.x + l.range < viewX - halfW or
                l.x - l.range > viewX + halfW or
                l.y + l.range < viewY - halfH or
                l.y - l.range > viewY + halfH) then
            n = n + 1
            -- World space for the instanced character shader.
            worldLights[n]  = { l.x, l.y, l.intensity, l.range }
            -- Screen space for ordinary draws: position AND range scaled by zoom
            -- so on-screen falloff matches the world falloff at any zoom.
            screenLights[n] = { l.x * zoom + camX, l.y * zoom + camY, l.intensity, l.range * zoom }
        end
    end
    -- Drop stale trailing entries from previous, busier frames.
    for i = #screenLights, n + 1, -1 do
        screenLights[i] = nil
        worldLights[i]  = nil
    end

    -- Object shader (screen space). Always set the count; only unpack a non-empty
    -- array (unpack of an empty table errors). count == 0 -> ambient-only fallback.
    objectShader:send("numLights", n)
    objectShader:send("u_ambient", lighting.ambient)
    if n > 0 then
        objectShader:send("lights", unpack(screenLights))
    end

    -- Instanced character shader (world space).
    if characterAnimator and characterAnimator.shader then
        characterAnimator.shader:send("numLights", n)
        if n > 0 then
            characterAnimator.shader:send("lights", unpack(worldLights))
        end
    end
end

-- Legacy alias: main.lua calls shadow.updateBothShaders(dt).
lighting.updateBothShaders = lighting.update

return lighting
