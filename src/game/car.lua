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

function car.load(world)
    -- Load the sprite sheet for all cars to use
    car.spriteSheet = love.graphics.newImage("gfx/vehicles/car.png")
    car.width, car.height = car.spriteSheet:getDimensions()
    -- Assuming 5 columns and 168 total frames, calculate frame width and height
    local frameWidth = car.width / 5
    local frameHeight = car.height / (168 / 5)
    car.animationTemplate = newAnimation(car.spriteSheet, 128, 128, 2, 456)
    
    -- Create an initial car instance for testing
    local newCar = {
        body = love.physics.newBody(world, var.game_width / 2, var.game_height / 2, "dynamic"),
        shape = love.physics.newRectangleShape(20, 40),
        animation = { 
            spriteSheet = car.spriteSheet,
            quads = car.animationTemplate.quads,
            duration = car.animationTemplate.duration,
            currentTime = 0
        }
    }
    newCar.fixture = love.physics.newFixture(newCar.body, newCar.shape)
    newCar.fixture:setGroupIndex(-2) -- Different group from player to avoid collision initially
    table.insert(car.cars, newCar)
end

function car.update(dt)
    -- Update each car instance
    for _, currentCar in ipairs(car.cars) do
        -- Update animation
        currentCar.animation.currentTime = currentCar.animation.currentTime + dt
        
        if currentCar.animation.currentTime >= currentCar.animation.duration then
            currentCar.animation.currentTime = currentCar.animation.currentTime - currentCar.animation.duration
        end
        
        -- Basic movement for testing (can be replaced with proper controls)
        local maxSpeed = 150
        local acceleration = 2000
        local friction = 0.9
        local vx, vy = currentCar.body:getLinearVelocity()
        local inputX, inputY = 0, 0
        
        -- Placeholder for movement logic (e.g., AI or player control)
        -- For now, the car will be stationary or move based on simple logic
        -- This can be expanded later as needed
        
        local newVX = vx * friction
        local newVY = vy * friction
        if math.abs(newVX) < 5 and math.abs(newVY) < 5 then
            newVX, newVY = 0, 0
        end
        currentCar.body:setLinearVelocity(newVX, newVY)
    end
end

function car.populate()
    -- Add each car to the dynamic draw list for rendering
    for i, currentCar in ipairs(car.cars) do
        -- local cx, cy = currentCar.body:getX(), currentCar.body:getY()
        local cx, cy = player.body:getX(), player.body:getY() + 100

        local spriteNum = math.floor(currentCar.animation.currentTime / currentCar.animation.duration * #currentCar.animation.quads) + 1

      

        table.insert(dynamic_draw_list, {
            sort_y = cy + 40, -- Adjust sorting position as needed
            image_or_particles = currentCar.animation.spriteSheet,
            quad = currentCar.animation.quads[spriteNum],
            x = cx,
            y = cy,
            rotation = 0,
            scale_x = car.scale,
            scale_y = car.scale,
            offset_x = car.width / 10, -- Center the sprite
            offset_y = (car.height / (168 / 5)) / 2,
            color = { 1, 1, 1, 1 },
            blend_mode = { "alpha" },
            source_object_type = "car",
            car_id = i
        })
    end
end

return car
