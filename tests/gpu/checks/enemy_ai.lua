--[[
  How enemies fight (game/enemy.lua's Enemy:think):

      python3 tests/gpu/run.py --checks --only enemy_ai

  1. in the open they hold their weapon's range, spread round you rather
     than piling up;
  2. they never shoot without a clear line to you;
  3. one with the house between you comes round it and gets you in sight;
  4. they lead you as you move;
  5. knockback still throws them, and they recover;
  6. 400 of them cost little.

  Leaves a screenshot of a crowd round you in dist/gpu-test/checks-enemy_ai/.
]]
return function(h)
    player.god = true
    h.advance(10)
    local function clear()
        for _, e in ipairs(enemy.enemies) do
            if not e.dead then e:killEnemy() end
        end
        h.advance(2)
    end
    local function stand(x, y)
        player.body:setPosition(x, y)
        player.body:setLinearVelocity(0, 0)
        camera.snap(player)
    end
    local function hold(frames, vx, vy)
        for _ = 1, frames do
            player.body:setLinearVelocity(vx or 0, vy or 0)
            h.advance(1)
        end
    end
    local function alive()
        local list = {}
        for _, e in ipairs(enemy.enemies) do
            if not e.dead then list[#list + 1] = e end
        end
        return list
    end
    local function sight(x1, y1, x2, y2)
        local clear = true
        world:rayCast(x1, y1, x2, y2, function(f)
            if not f:isSensor() and f:getBody():getType() == "static" then
                clear = false
                return 0
            end
            return -1
        end)
        return clear
    end

    -- Every shot: was the shooter in sight of you, and which way did it go
    local shots, blind = 0, 0
    local shoot = Enemy.shoot
    Enemy.shoot = function(self)
        local ex, ey = self.body:getPosition()
        shots = shots + 1
        if not sight(ex, ey, player.body:getPosition()) then blind = blind + 1 end
        return shoot(self)
    end

    -- 1. In the open
    clear()
    local cx, cy = -800, 1400
    stand(cx, cy)
    for i = 1, 12 do
        local a = (i % 3) * 0.3 -- all from one side
        enemy.addEnemy(cx + 600 * math.cos(a) + i * 6, cy + 600 * math.sin(a) + i * 4)
    end
    hold(60 * 6)
    local crowd = alive()
    local inRange, octants, nearest = 0, {}, {}
    for _, e in ipairs(crowd) do
        local ex, ey = e.body:getPosition()
        local d = math.sqrt((ex - cx) ^ 2 + (ey - cy) ^ 2)
        if d > e.range * 0.5 and d < e.range * 1.6 then inRange = inRange + 1 end
        octants[math.floor((math.atan2(ey - cy, ex - cx) + math.pi) / (math.pi / 4)) % 8] = true
        local best = math.huge
        for _, o in ipairs(crowd) do
            if o ~= e then
                local ox, oy = o.body:getPosition()
                best = math.min(best, math.sqrt((ox - ex) ^ 2 + (oy - ey) ^ 2))
            end
        end
        nearest[#nearest + 1] = best
    end
    local sides = 0
    for _ in pairs(octants) do sides = sides + 1 end
    table.sort(nearest)
    h.check("in the open they hold their weapon's range", inRange >= #crowd * 0.75,
        string.format("%d of %d within range", inRange, #crowd))
    h.check("they spread round you", sides >= 5, string.format("%d of 8 sides, all came from one", sides))
    h.check("rather than piling up", nearest[math.ceil(#nearest / 2)] > 30,
        string.format("median gap to the nearest %.0f px", nearest[math.ceil(#nearest / 2)]))
    h.check("and shoot", shots > 0, shots .. " shots")
    h.capture("crowd")

    -- 3. Round the house
    clear()
    local house = map.houseInstances[1]
    stand(house.x, house.y - 160)
    enemy.addEnemy(house.x + 10, house.y + 170)
    local e = alive()[1]
    local ex, ey = e.body:getPosition()
    h.check("one with the house between you can't see you", not sight(ex, ey, house.x, house.y - 160))
    local seenAfter
    for frame = 1, 60 * 8 do
        hold(1)
        if e.los then
            seenAfter = frame / 60
            break
        end
    end
    h.check("comes round it and gets you in sight", seenAfter ~= nil,
        seenAfter and string.format("%.1f s", seenAfter) or "never in 8 s")

    -- 2. Not through walls
    hold(60 * 3)
    h.check("they never shoot without a clear line to you", blind == 0 and shots > 0,
        string.format("%d of %d shots blind", blind, shots))

    -- 4. Leading
    clear()
    stand(cx, cy)
    enemy.addEnemy(cx, cy + 250)
    e = alive()[1]
    -- ready at once, quick to fire again, and reaching you wherever you get to
    local w = {}
    for k, v in pairs(e.weapon) do w[k] = v end
    w.lifetime, w.shots, w.pellets, w.spread = 3, 1, 1, 0
    e.weapon, e.fire_cooldown, e.jitter, e.last_fire_time, e.lead = w, 0.4, 0, -10, 0.9
    local new = bullet.new
    local dirs = {}
    bullet.new = function(params)
        if params.hostile then dirs[#dirs + 1] = params.dir end
        return new(params)
    end
    hold(60 * 3, 150, 0)
    bullet.new = new
    local ahead = 0
    for _, d in ipairs(dirs) do
        if d.x > 0.05 then ahead = ahead + 1 end
    end
    h.check("they lead you as you move", #dirs > 0 and ahead >= #dirs * 0.7,
        string.format("%d of %d shots aimed ahead of you", ahead, #dirs))
    Enemy.shoot = shoot

    -- 5. Knockback
    clear()
    stand(cx, cy)
    enemy.addEnemy(cx + 250, cy)
    e = alive()[1]
    hold(30)
    e.body:applyLinearImpulse(e.body:getMass() * 600, 0)
    hold(2)
    local vx, vy = e.body:getLinearVelocity()
    local thrown = math.sqrt(vx * vx + vy * vy)
    hold(60)
    vx, vy = e.body:getLinearVelocity()
    local after = math.sqrt(vx * vx + vy * vy)
    h.check("knockback still throws them", thrown > 400, string.format("%.0f px/s", thrown))
    h.check("and they recover", after < 200, string.format("%.0f px/s a second later", after))

    -- 6. Cost
    clear()
    stand(cx, cy)
    for i = 1, 400 do
        local a = i * 2.39996
        enemy.addEnemy(cx + math.cos(a) * (150 + i * 3), cy + math.sin(a) * (150 + i * 3))
    end
    h.advance(5)
    local update, total = enemy.update, 0
    enemy.update = function(dt)
        local t = os.clock()
        update(dt)
        total = total + os.clock() - t
    end
    hold(240)
    enemy.update = update
    h.check("400 of them cost little", total / 240 < 2e-3,
        string.format("enemy.update %.3f ms a frame", total / 240 * 1000))
end
