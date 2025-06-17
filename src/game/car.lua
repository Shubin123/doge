local block = require("game.block")
local car = {}
car.cars = {} -- List to store multiple car instances
car.scale = 1

function car.load(world)
    -- Clear existing cars to prevent duplicates on reload
    car.cars = {}
    -- Create a block instance for car using the superclass
    car.blockInstance = block.new("gfx/vehicles/car.png", 128, 128, 2, 450, car.scale, world, var.game_width / 2 + 100, var.game_height / 2 + 100)
    
    -- Create an initial car instance for testing
    if not var.multiplayer or var.multiplayer == 1 then
        table.insert(car.cars, car.blockInstance)
        car.blockInstance:setInUse(true)
    end
end

function car.populate()
    -- Add each car to the dynamic draw list for rendering
    for i, currentCar in ipairs(car.cars) do
        local cx, cy, relVel = currentCar:updatePhysics(player.body, var.multiplayer)
        if not cx or not cy then
            cx, cy = currentCar.body:getX(), currentCar.body:getY()
            relVel = {x = 0, y = 0}
        end
        -- Add to draw list using superclass method
        currentCar:addToDrawList(dynamic_draw_list, cx, cy, relVel.x, relVel.y, 160, currentCar.width / 10, (currentCar.height / (456 / 5)) / 2)
        -- Update the source_object_type and car_id for identification
        dynamic_draw_list[#dynamic_draw_list].source_object_type = "car"
        dynamic_draw_list[#dynamic_draw_list].car_id = i
    end
end

function car.getNetworkData()
    local carData = {}
    for i, currentCar in ipairs(car.cars) do
        local cx, cy = currentCar.body:getX(), currentCar.body:getY()
        local vx, vy = currentCar.body:getLinearVelocity()
        carData[tostring(i)] = {
            x = cx,
            y = cy,
            vx = vx,
            vy = vy,
            inUse = currentCar.inUse,
            controllingPlayer = currentCar.controllingPlayer or ""
        }
    end
    return carData
end

return car
