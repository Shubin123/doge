--[[
  The car (game/car.lua), driven through the game's input:

      python3 tests/gpu/run.py --checks

  1. next to the parked car, the indicator offers it; E gets you in;
  2. driving, you're as wide as the car and go faster than on foot, and
     you can't shoot;
  3. E gets you out beside it, and it's parked where you stopped.
]]
return function(h)
    player.god = true
    h.advance(10)
    local c = car.cars[1]
    local cx, cy = c.body:getPosition()
    local function stand(x, y)
        player.body:setPosition(x, y)
        player.body:setLinearVelocity(0, 0)
        camera.snap(player)
        h.advance(2)
    end

    stand(cx - 300, cy)
    h.check("far from it, nothing's offered", car.nearest(player.body:getPosition()) == nil)
    love.keypressed("e")
    h.check("and E does nothing", car.driving == nil)

    stand(cx - 50, cy)
    h.check("next to it, the indicator offers it", car.nearest(player.body:getPosition()) == c)
    local walkSpeed = player.maxSpeed
    love.keypressed("e")
    h.check("E gets you in", car.driving == c and player.inCar == c)
    h.check("you're as wide as the car", player.fixture:getShape():getRadius() > 20,
        string.format("radius %.0f", player.fixture:getShape():getRadius()))
    h.check("and faster than on foot", player.maxSpeed > walkSpeed,
        string.format("%d px/s, %d on foot", player.maxSpeed, walkSpeed))
    local bullets = #bullet.instances
    love.mousepressed(600, 300, 1)
    h.advance(1)
    h.check("no shooting from the car", #bullet.instances == bullets and not gun.mousePressed)
    love.mousereleased(600, 300, 1)

    -- drive a little way
    player.body:setLinearVelocity(300, 0)
    h.advance(20)
    local px, py = player.body:getPosition()
    love.keypressed("e")
    h.advance(1)
    local parkedX, parkedY = c.body:getPosition()
    h.check("E gets you out", car.driving == nil and player.inCar == nil
        and math.abs(player.fixture:getShape():getRadius() - 10) < 1e-6 and player.maxSpeed == walkSpeed)
    h.check("the car's parked where you stopped",
        math.abs(parkedX - px) < 2 and math.abs(parkedY - py) < 2 and c.body:isActive(),
        string.format("car at %.0f, %.0f; stopped at %.0f, %.0f", parkedX, parkedY, px, py))
    local ox, oy = player.body:getPosition()
    h.check("and you're beside it", math.sqrt((ox - parkedX) ^ 2 + (oy - parkedY) ^ 2) > 30)
end
