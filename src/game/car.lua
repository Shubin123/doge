local block = require("game.block")
local car = {}
car.cars = {} -- List to store multiple car instances
car.scale = 1

function car.load(world)
    -- Clear existing cars to prevent duplicates on reload
    car.cars = {}
    -- Create a block instance for car using the superclass
    car.blockInstance = block.new("gfx/vehicles/car.png", 128, 128, 2, 450, car.scale, world, var.game_width / 2 + 100, var.game_height / 2 + 100)
    
    -- Create an initial car instance for all players
    table.insert(car.cars, car.blockInstance)
    car.blockInstance:setInUse(false)
    -- Disable physics on clients, only host handles physics and collisions
    if var.multiplayer and var.multiplayer > 1 then
        car.blockInstance.body:setActive(false)
    end
end

function car.populate()
    -- Add cars to the dynamic draw list for rendering
    for i, currentCar in ipairs(car.cars) do
        -- Only draw host's car if multiplayer > 2
        -- if var.multiplayer > 2 and i > 1 then
        --     -- Skip drawing non-host cars in this mode
        --     goto continue
        -- end
        
        local cx, cy = 0, 0
        local v =0
        local vx, vy = 0, 0
        if currentCar.inUse then 
            
            cx,cy,v = currentCar:updatePhysics(player.body)
            vx = v.x
            vy = v.y
        else
            cx, cy = currentCar.body:getX(), currentCar.body:getY()
            vx, vy = currentCar.body:getLinearVelocity()
            currentCar.body:getFixtures()[1]:setGroupIndex(-2)
        end
        
        -- On clients, use networked position directly since physics is disabled
        if var.multiplayer then
        if var.multiplayer > 1 and renderer.networked_state and renderer.networked_state.cars and renderer.networked_state.cars[tostring(i)] then
            local netCar = renderer.networked_state.cars[tostring(i)]
            cx, cy = netCar.x, netCar.y
            vx, vy = netCar.vx or 0, netCar.vy or 0
        end
    end
        -- Add to draw list using superclass method
        currentCar:addToDrawList(dynamic_draw_list, cx, cy, vx, vy, 160, currentCar.width / 10, (currentCar.height / (456 / 5)) / 2)
        -- Update the source_object_type and car_id for identification
        dynamic_draw_list[#dynamic_draw_list].source_object_type = "car"
        dynamic_draw_list[#dynamic_draw_list].car_id = i
        
        -- ::continue::
    end
end

function car.updateFromNetwork(networkedCars)
    if var.multiplayer and var.multiplayer > 1 then -- Only clients update from network data
        for carId, carData in pairs(networkedCars) do
            local carIndex = tonumber(carId)
            if carIndex and car.cars[carIndex] then
                local currentCar = car.cars[carIndex]
                currentCar.body:setX(carData.x)
                currentCar.body:setY(carData.y)
                if carData.vx and carData.vy then
                    currentCar.body:setLinearVelocity(carData.vx, carData.vy)
                end
                currentCar.inUse = carData.inUse
                currentCar.controllingPlayer = carData.controllingPlayer or ""
            end
        end
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
