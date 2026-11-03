--[[
  Which way the flashlight points (gun.heading / gun.currentVel in
  game/gun.lua, systems/light.lua's aim):

      python3 tests/gpu/run.py --checks --only flashlight

  1. it follows the way you go;
  2. doubling back turns it round;
  3. when you stop it turns to the cursor;
  4. moving again, it follows the way you go, not the cursor;
  5. the weapons still aim at the cursor.
]]
return function(h)
    player.god = true
    h.advance(5)
    for _, e in ipairs(enemy.enemies) do
        if not e.dead then e:killEnemy() end
    end
    player.body:setPosition(-800, 1400)
    camera.snap(player)
    player.lightsOn = true

    -- The cursor up and to the left of you
    local getPosition, getX, getY = love.mouse.getPosition, love.mouse.getX, love.mouse.getY
    local mx, my = 120, 90
    love.mouse.getPosition = function() return mx, my end
    love.mouse.getX = function() return mx end
    love.mouse.getY = function() return my end

    local function beam()
        return math.deg(math.atan2(gun.currentVel.y, gun.currentVel.x))
    end
    local function near(a, b, tolerance)
        return math.abs((a - b + 180) % 360 - 180) <= (tolerance or 5)
    end
    local function move(vx, vy, frames)
        for _ = 1, frames do
            player.body:setLinearVelocity(vx, vy)
            h.advance(1)
        end
    end
    local function rest(frames) -- let go: you slow to a stop
        h.advance(frames)
    end

    local function cursor()
        return math.deg(math.atan2(gun.lastAimDirection.y, gun.lastAimDirection.x))
    end

    move(300, 0, 60)
    h.check("it follows the way you go", near(beam(), 0), string.format("%.0f degrees", beam()))
    move(-300, 0, 60)
    h.check("doubling back turns it round", near(beam(), 180), string.format("%.0f degrees", beam()))
    rest(180)
    local vx, vy = player.body:getLinearVelocity()
    h.check("you've stopped", vx * vx + vy * vy < 1)
    h.check("and it turns to the cursor", near(beam(), cursor()),
        string.format("%.0f degrees; the cursor's at %.0f", beam(), cursor()))

    move(0, 300, 60)
    h.check("moving again, it follows the way you go", near(beam(), 90),
        string.format("%.0f degrees; the cursor's at %.0f", beam(), cursor()))

    local ax, ay = gun.lastAimDirection.x, gun.lastAimDirection.y
    h.check("the weapons still aim at the cursor", ax < 0 and ay < 0,
        string.format("aiming %.2f, %.2f", ax, ay))

    love.mouse.getPosition, love.mouse.getX, love.mouse.getY = getPosition, getX, getY
end
