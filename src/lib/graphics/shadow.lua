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
