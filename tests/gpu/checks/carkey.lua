--[[
  The car key (game/inventory.lua's car_key, car.summon in game/car.lua):

      python3 tests/gpu/run.py --checks --only carkey

  1. at first nobody has it: it lies in front of the car, and walking over
     picks it up;
  2. K calls the car: it drives itself over open ground, and round the house
     when you're behind it, and parks beside you, never inside a wall;
  3. you indoors, it gets as close as it can; too far off, it won't come;
  4. K again while it's coming stops it; a save made then keeps it parked;
  5. once it's there, E gets you in.

  Leaves screenshots of it on its way and parked in dist/gpu-test/checks-carkey/.
]]
return function(h)
    player.god = true
    h.advance(5)
    for _, e in ipairs(enemy.enemies) do
        if not e.dead then e:killEnemy() end
    end
    local c = car.cars[1]
    local function stand(x, y)
        player.body:setPosition(x, y)
        player.body:setLinearVelocity(0, 0)
        camera.snap(player)
    end
    local function carAt(x, y)
        c.body:setPosition(x, y)
        c.body:setLinearVelocity(0, 0)
        h.advance(1)
    end
    local function distance()
        local x, y = c.body:getPosition()
        local px, py = player.body:getPosition()
        return math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
    end
    -- Whether the car's middle is ever closer than its half-width to a wall
    local function inWall()
        local x, y = c.body:getPosition()
        local hit = false
        world:queryBoundingBox(x - 20, y - 20, x + 20, y + 20, function(f)
            if not f:isSensor() and f:getBody():getType() == "static" and f:getShape():getType() == "polygon" then
                local ax, ay, bx, by = f:getBoundingBox()
                if ax < x + 20 and bx > x - 20 and ay < y + 20 and by > y - 20 then hit = true end
            end
            return not hit
        end)
        return hit
    end
    -- Run until it parks (or `limit` s), standing still; seconds it took and
    -- whether it ever went into a wall
    local function await(limit)
        local frames, walls = 0, false
        while c.autopilot and frames < limit * 60 do
            player.body:setLinearVelocity(0, 0)
            h.advance(1)
            frames = frames + 1
            walls = walls or inWall()
        end
        return frames / 60, walls
    end

    -- 1. The key
    local key
    for _, g in ipairs(inventory.ground) do
        if g.id == "car_key" then key = g end
    end
    local kx, ky = car.keySpot()
    h.check("nobody has the key at first: it lies in front of the car",
        key ~= nil and math.abs(key.x - kx) < 1 and math.abs(key.y - ky) < 1 and inventory.count("car_key") == 0)
    love.keypressed("k")
    h.check("K without it does nothing", c.autopilot == nil)
    stand(kx, ky + 30)
    h.advance(30)
    h.check("walking over it picks it up", inventory.count("car_key") == 1)

    -- 2. Calling it over open ground
    local home = { c.body:getPosition() }
    stand(home[1] - 500, home[2] + 330)
    love.keypressed("k")
    h.check("K calls the car", c.autopilot ~= nil)
    h.advance(50)
    h.capture("on_its_way")
    local took, walls = await(30)
    h.check("over open ground it drives to you and parks", c.autopilot == nil and distance() < 90,
        string.format("%.1f s, parked %.0f px from you", took, distance()))
    h.check("and stays parked", select(1, c.body:getLinearVelocity()) == 0)
    h.capture("parked")

    -- round the house: you behind it, the car in front
    local house = map.houseInstances[1]
    carAt(house.x + 40, house.y + 150)
    stand(house.x, house.y - 140)
    love.keypressed("k")
    took, walls = await(40)
    h.check("with the house between you, it drives round it", c.autopilot == nil and distance() < 90,
        string.format("%.1f s, parked %.0f px from you", took, distance()))
    h.check("never going through a wall", not walls)

    -- 3. You indoors; you far off
    carAt(house.x + 260, house.y + 200)
    stand(house.x, house.y + 20)
    h.advance(2)
    love.keypressed("k")
    took = await(40)
    local hx, hy = house.x, house.y
    local cx, cy = c.body:getPosition()
    h.check("you indoors, it gets as close as it can", c.autopilot == nil
        and math.sqrt((cx - hx) ^ 2 + (cy - hy) ^ 2) < 260,
        string.format("%.1f s, parked %.0f px from the house", took, math.sqrt((cx - hx) ^ 2 + (cy - hy) ^ 2)))
    stand(home[1] + 6000, home[2])
    love.keypressed("k")
    h.check("too far off, it won't come", c.autopilot == nil)

    -- 4. Stopping it; saving while it comes
    carAt(home[1], home[2])
    stand(home[1] - 500, home[2] + 330)
    love.keypressed("k")
    h.advance(30)
    love.keypressed("k")
    h.check("K again while it's coming stops it", c.autopilot == nil
        and select(1, c.body:getLinearVelocity()) == 0)
    love.keypressed("k")
    h.advance(30)
    local saved = serial.create().cars[1]
    h.check("a save made while it's coming keeps it parked", saved.vx == 0 and saved.vy == 0)
    await(30)

    -- 5. In
    stand(c.body:getX() - 50, c.body:getY())
    love.keypressed("e")
    h.check("once it's there, E gets you in", car.driving == c)
    love.keypressed("e")
end
