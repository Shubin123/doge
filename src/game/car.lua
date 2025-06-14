local car = {}
car.cars = {} -- List to store multiple car instances
car.scale = 1

function newAnimation(image, width, height, duration, numFrames)
    local animation = {}
    animation.spriteSheet = image
    animation.quads = {}
    player.scale = 0.8
    
    player.totalPossibleFrames = math.floor(image:getWidth() / width) * math.floor(image:getHeight() / height)
    local framesToUse = numFrames or player.totalPossibleFrames
    framesToUse = math.min(framesToUse, player.totalPossibleFrames)
    
    local frameCount = 0
    for y = 0, image:getHeight() - height, height do
        for x = 0, image:getWidth() - width, width do
            table.insert(animation.quads, love.graphics.newQuad(x, y, width, height, image:getDimensions()))
            frameCount = frameCount + 1
            if frameCount >= framesToUse then
                break
            end
        end
        if frameCount >= framesToUse then
            break
        end
    end
    
    animation.duration = duration or 1
    animation.currentTime = 0
    return animation
end

-- Function to calculate sprite frame based on player's heading

function car.getSpriteForHeading(vx,vy)
    -- If player doesn't have angle property, calculate from velocity
        local angle = 0
    
        -- local vx, vy = carBody:getLinearVelocity()--when off vehicle
        

        if math.abs(vx) > 0.1 or math.abs(vy) > 0.1 then
            angle = math.atan2(vy, -vx)
        end
    
    
    local normalizedAngle = (angle % (2 * math.pi) + 2 * math.pi) % (2 * math.pi)
    
    -- Convert to degrees (0-360)
    local degrees = math.deg(normalizedAngle) + 1
    
    -- frames: North=1, west=91, South=181, east=271
    local adjustedDegrees = (degrees + 155) % 400 
    
    
    
    local spriteFrame = math.floor(adjustedDegrees) + 1
    
    -- Ensure we stay within bounds (1 to 360)
    spriteFrame = math.max(1, math.min(390, spriteFrame))
    
    return spriteFrame
end

function car.load(world)
    -- Load the sprite sheet for all cars to use
    car.spriteSheet = love.graphics.newImage("gfx/vehicles/bike.png")
    car.width, car.height = car.spriteSheet:getDimensions()
    -- With 456 frames, calculate frame dimensions
    local frameWidth = car.width / 5  -- Assuming 5 columns
    local frameHeight = car.height / (456 / 5)  -- Calculate rows needed for 456 frames
    car.animationTemplate = newAnimation(car.spriteSheet, 128, 128, 2, 450)
    
    -- Create an initial car instance for testing
    local newCar = {
        body = love.physics.newBody(world, var.game_width / 2 + 100, var.game_height / 2 + 100, "dynamic"),
        shape = love.physics.newRectangleShape(20, 40),
        animation = { 
            spriteSheet = car.spriteSheet,
            quads = car.animationTemplate.quads,
            duration = car.animationTemplate.duration,
            currentTime = 0,
        
        },
        inUse = false,
    }
    newCar.fixture = love.physics.newFixture(newCar.body, newCar.shape)
    newCar.fixture:setGroupIndex(-2) -- Different group from player to avoid collision initially
    table.insert(car.cars, newCar)
end

function car.update(dt)
    -- Update each car instance
    for _, currentCar in ipairs(car.cars) do
        -- Update animation time (though we'll use heading-based sprite selection)
        currentCar.animation.currentTime = currentCar.animation.currentTime + dt
        
        if currentCar.animation.currentTime >= currentCar.animation.duration then
            currentCar.animation.currentTime = currentCar.animation.currentTime - currentCar.animation.duration
        end
        
        -- Check for player interaction to enter/exit vehicle
        if not currentCar.inUse then
            local px, py = player.body:getX(), player.body:getY()
            local cx, cy = currentCar.body:getX(), currentCar.body:getY()
            local distance = math.sqrt((px - cx)^2 + (py - cy)^2)
            if distance < 50 and love.keyboard.isDown("e") then
                -- Player is close and presses 'E' to enter vehicle
                currentCar.inUse = true
                currentCar.controllingPlayer = var.multiplayer == 1 and "host" or "client_" .. var.multiplayer
            end
        else
            if love.keyboard.isDown("q") then
                -- Player presses 'Q' to exit vehicle
                currentCar.inUse = false
                currentCar.controllingPlayer = nil
            else
                if var.multiplayer == 1 then -- Only host handles physics updates
                    -- Apply player movement to car if in use
                    local maxSpeed = 150
                    local acceleration = 2000
                    local friction = 0.9
                    local vx, vy = currentCar.body:getLinearVelocity()
                    local inputX, inputY = 0, 0
                    
                    if love.keyboard.isDown("up") or love.keyboard.isDown("w") then
                        inputY = inputY - 1
                    end
                    if love.keyboard.isDown("down") or love.keyboard.isDown("s") then
                        inputY = inputY + 1
                    end
                    if love.keyboard.isDown("left") or love.keyboard.isDown("a") then
                        inputX = inputX - 1
                    end
                    if love.keyboard.isDown("right") or love.keyboard.isDown("d") then
                        inputX = inputX + 1
                    end
                    
                    if inputX ~= 0 or inputY ~= 0 then
                        local forceX = inputX * acceleration
                        local forceY = inputY * acceleration
                        currentCar.body:applyForce(forceX, forceY)
                        local speed = math.sqrt(vx^2 + vy^2)
                        if speed > maxSpeed then
                            local scale = maxSpeed / speed
                            currentCar.body:setLinearVelocity(vx * scale, vy * scale)
                        end
                    else
                        local newVX = vx * friction
                        local newVY = vy * friction
                        if math.abs(newVX) < 5 and math.abs(newVY) < 5 then
                            newVX, newVY = 0, 0
                        end
                        currentCar.body:setLinearVelocity(newVX, newVY)
                    end
                end
            end
        end
    end
end

function car.populate()
    -- Add each car to the dynamic draw list for rendering
    for i, currentCar in ipairs(car.cars) do
        local relVel = {}
        local cx, cy
        if var.multiplayer == 1 then -- Only host updates physics positions
            if currentCar.inUse then
                cx, cy = player.body:getX(), player.body:getY()
                currentCar.body:setPosition(player.body:getPosition())
                relVel.x, relVel.y = player.body:getLinearVelocity()
                currentCar.fixture:setGroupIndex(-1)
            else
                cx, cy = currentCar.body:getX(), currentCar.body:getY()
                relVel.x, relVel.y = currentCar.body:getLinearVelocity()
                currentCar.fixture:setGroupIndex(-3)
            end
        else
            -- Clients use networked data for rendering, no physics updates
            cx, cy = currentCar.body:getX(), currentCar.body:getY()
            relVel.x, relVel.y = currentCar.body:getLinearVelocity()
            currentCar.fixture:setGroupIndex(-3)
        end
        -- Get the appropriate sprite frame based on player's heading
        local spriteNum = car.getSpriteForHeading(relVel.x, relVel.y)
        table.insert(dynamic_draw_list, {
            sort_y = cy + 130, -- Adjust sorting position as needed
            image_or_particles = currentCar.animation.spriteSheet,
            quad = currentCar.animation.quads[spriteNum],
            x = cx,
            y = cy,
            rotation = 0,
            scale_x = car.scale,
            scale_y = car.scale,
            offset_x = car.width / 10, -- Center the sprite
            offset_y = (car.height / (456 / 5)) / 2,
            color = { 1, 1, 1, 1 },
            blend_mode = { "alpha" },
            source_object_type = "car",
            car_id = i
        })
    end
end

-- Update car positions and states from networked data (called by renderer or snapshot)
function car.updateFromNetwork(networkedCars)
    if var.multiplayer ~= 1 then -- Only clients update from network data
        for carId, carData in pairs(networkedCars) do
            local carIndex = tonumber(carId)
            if carIndex and car.cars[carIndex] then
                local currentCar = car.cars[carIndex]
                currentCar.body:setPosition(carData.x, carData.y)
                currentCar.body:setLinearVelocity(carData.vx, carData.vy)
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
