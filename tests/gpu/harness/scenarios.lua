-- The scripted play-through every run renders, baseline and candidate alike.
-- Each capture() is one frame that run.py diffs pixel-for-pixel, so together
-- they should reach every render path: flashlight on/off, indoors (the warm
-- neon light), an explosion shockwave, zoom, a GI quality change that reloads
-- shaders and canvases, tesla bolts and arrows, bullets.
--
-- Only call game APIs that exist in the baseline revision as well: this file
-- is run against both trees.
return function(h)
    -- Enemies shoot to hurt now; the player standing still among them would
    -- die and drop to the menu partway through. (player.god predates that,
    -- so the baseline accepts it too.)
    player.god = true
    h.advance(90) -- every enemy spawned, physics settled
    h.capture("default")

    player.lightsOn = false
    h.capture("flashlight_off")
    player.lightsOn = true

    var.indoors = true
    h.capture("indoors")
    var.indoors = false
    h.advance(1)

    local px, py = player.body:getPosition()
    explosion.create(px + 80, py + 20, explosion.TYPES.ROCKET)
    h.advance(6)
    h.capture("shockwave")
    h.advance(30)
    h.capture("shockwave_late")

    camera.setZoom(2)
    h.advance(45)
    h.capture("zoom2")
    camera.setZoom(1)
    h.advance(45)

    var.gi_quality = "low"
    shader.load()
    h.capture("gi_low")
    var.gi_quality = "high"
    shader.load()
    h.capture("gi_reloaded")

    -- Tesla bolts and arrows: their glow chains only run while they exist.
    local px, py = player.body:getPosition()
    teslaCoil.fireAt(px + 200, py - 80, world)
    arrows.fireAt(px + 220, py + 40, world)
    h.capture("tesla_arrows")
    teslaCoil:update(teslaCoil.cooldown) -- cooldown expiry clears both again
    arrows:update(arrows.cooldown)
    h.advance(1)

    -- Bullets in flight: a stream from each gun, fanned left over open ground.
    -- Masked from collisions (coins and enemies by the player would absorb
    -- them within frames); this checks how they draw, not what they hit.
    local function volley()
        local x, y = player.body:getPosition()
        for i = 1, 4 do
            local a = math.pi * (0.72 + 0.17 * i)
            local c, s = math.cos(a), math.sin(a)
            local b = bullet.new({ pos = vec2.new(x + c * 40, y + s * 40), dir = vec2.new(c, s),
                                   speed = 750, lifetime = 3, neon = gun.guns[i].tracer })
            b.fixture:setMask(1)
        end
    end
    for _ = 1, 6 do
        volley()
        h.advance(5)
    end
    h.capture("bullets")
    var.tracer_brightness = 0.3 -- a dark player light level
    h.capture("bullets_dim")
    var.tracer_brightness = 1.0
    -- Let every bullet expire, so the timed frames that follow have none.
    for _ = 1, 600 do
        if #bullet.instances == 0 then break end
        h.advance(1)
    end
    for _, b in ipairs(bullet.pool) do b.fixture:setMask() end
end
