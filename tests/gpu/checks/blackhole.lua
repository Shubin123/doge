--[[
  The black hole (game/blackhole.lua), in the running game:

      python3 tests/gpu/run.py --checks

  1. far from it time runs normally; close to it, it slows, and the game's
     own clock (xp.time, fed the frame's dt) really advances slower;
  2. an idle player is drawn towards it;
  3. a glob at the horizon is swallowed;
  4. a bullet flying past bends towards it;
  5. inside the horizon the player is hurt.
]]
return function(h)
    player.god = true
    h.advance(10)

    -- Somewhere quiet, well away from the enemies
    local px, py = 3000, 300
    local function place(x, y)
        player.body:setPosition(x, y)
        player.body:setLinearVelocity(0, 0)
        camera.snap(player)
    end

    place(px, py)
    blackhole.moveTo(px + 900, py)
    h.advance(60)
    h.check("far away, time runs normally", math.abs(blackhole.timeScale - 1) < 0.01,
        string.format("time scale %.3f", blackhole.timeScale))

    blackhole.moveTo(px + 110, py)
    h.advance(90)
    local scale = blackhole.timeScale
    h.check("close to it, time slows", scale < 0.6, string.format("time scale %.3f", scale))
    local before = xp.time
    h.advance(10)
    local ran = (xp.time - before) / (10 * h.dt)
    h.check("the game's clock runs at that pace", math.abs(ran - blackhole.timeScale) < 0.05,
        string.format("clock ran at %.3f, time scale %.3f", ran, blackhole.timeScale))

    blackhole.moveTo(px + 110, py) -- (also stills the fall it's had so far)
    place(px, py)
    h.advance(20)
    local x0 = player.body:getX()
    h.check("an idle player is drawn in", x0 > px + 1, string.format("moved %.1f px towards it", x0 - px))

    local body = createCoin(blackhole.x + 12, blackhole.y)
    var.num_coins = var.num_coins + 1
    h.advance(2)
    local swallowed = body:isDestroyed()
    h.check("a glob at the horizon is swallowed", swallowed)

    place(px - 400, py)
    blackhole.moveTo(px + 2000, py) -- out of the way while the bullet is aimed
    h.advance(30)
    local b = bullet.new({ pos = vec2.new(blackhole.x - 300, blackhole.y + 120), dir = vec2.new(1, 0),
        speed = 300, lifetime = 3 })
    b.fixture:setMask(1)
    h.advance(20)
    h.check("a bullet flying past bends towards it", b.dir.y < -0.05,
        string.format("heading %.3f, %.3f", b.dir.x, b.dir.y))

    player.god = false
    local health = player.health
    place(blackhole.x, blackhole.y)
    h.advance(5)
    h.check("inside the horizon the player is hurt", player.health < health,
        string.format("health %d -> %d", health, player.health))
    player.health = player.maxHealth
    player.god = true
    blackhole.moveTo(1400, 300)
    place(px, py)
    h.advance(5)
end
