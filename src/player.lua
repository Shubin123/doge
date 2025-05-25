local player = {}
player.health = 100


function newAnimation(image, width, height, duration, numFrames)
    local animation = {}
    animation.spriteSheet = image
    animation.quads = {}
    player.scale = 1
    
    local totalPossibleFrames = math.floor(image:getWidth() / width) * math.floor(image:getHeight() / height)
    local framesToUse = numFrames or totalPossibleFrames
    framesToUse = math.min(framesToUse, totalPossibleFrames)
    
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

function player.load(world)
    player.body = love.physics.newBody(world, var.game_width / 2, var.game_height / 2, "dynamic")
    player.shape = love.physics.newCircleShape(10)
    player.fixture = love.physics.newFixture(player.body, player.shape)
    player.character = love.graphics.newImage("gfx/doge.png")
    player.width, player.height = player.character:getDimensions()
    -- player.animation = newAnimation(love.graphics.newImage("gfx/Spritepack/1.png"), 16, 24, 2, 16)
    
    player.animation = newAnimation(love.graphics.newImage("gfx/SoldierSpriteSheets/Soldier_Idle.png"), 100,100, 1, 6)
end

function player.update(dt)
    if player.health <= 0 then
        var.State = "menu"
    end
    
    
    -- Movement configuration
    local maxSpeed = 100
    local acceleration = 2000
    local friction = 0.85  -- Lower value = more friction
    
    -- Get current velocity
    local vx, vy = player.body:getLinearVelocity()
    
    -- Track if keys are pressed for this frame
    local keyPressed = false
    
    -- Calculate input direction
    local inputX, inputY = 0, 0
    
    if love.keyboard.isDown("a") then
        inputX = inputX - 1
        keyPressed = true
    end
    
    if love.keyboard.isDown("d") then
        inputX = inputX + 1
        keyPressed = true
    end
    
    if love.keyboard.isDown("w") then
        inputY = inputY - 1
        keyPressed = true
    end
    
    if love.keyboard.isDown("s") then
        inputY = inputY + 1
        keyPressed = true
    end
    
    -- Normalize diagonal movement to maintain consistent speed
    if inputX ~= 0 and inputY ~= 0 then
        -- Pythagorean normalization
        local length = math.sqrt(inputX * inputX + inputY * inputY)
        inputX = inputX / length
        inputY = inputY / length
    end
    
    -- Apply acceleration in the input direction
    local targetVX = inputX * maxSpeed
    local targetVY = inputY * maxSpeed
    
    -- Smoothly interpolate toward target velocity
    local newVX, newVY
    
    if keyPressed then
        -- When keys are pressed, accelerate toward target velocity
        newVX = vx + (targetVX - vx) * math.min(dt * acceleration / maxSpeed, 1)
        newVY = vy + (targetVY - vy) * math.min(dt * acceleration / maxSpeed, 1)
    else
        -- When no keys are pressed, apply friction
        newVX = vx * friction
        newVY = vy * friction
        
        -- Stop completely if moving very slowly
        if math.abs(newVX) < 5 and math.abs(newVY) < 5 then
            newVX, newVY = 0, 0
        end
    end
    
    -- Apply the calculated velocity
    player.body:setLinearVelocity(newVX, newVY)
    
    -- Update animation
    player.animation.currentTime = player.animation.currentTime + dt
    
    if player.animation.currentTime >= player.animation.duration then
        player.animation.currentTime = player.animation.currentTime - player.animation.duration
    end
    
    -- Update facing direction based on movement
    if newVX ~= 0 or newVY ~= 0 then
        -- Only update direction when actually moving
        local moveMagnitude = math.sqrt(newVX * newVX + newVY * newVY)
        if moveMagnitude > 10 then  -- Small threshold to avoid direction changes when almost stopped
            -- Calculate direction angle
            player.direction = math.atan2(newVY, newVX)
            
            -- Determine animation based on movement direction
            -- This can be expanded based on your animation system
            if math.abs(newVX) > math.abs(newVY) then
                if newVX > 0 then
                    player.currentAnimation = "walkRight"
                else
                    player.currentAnimation = "walkLeft"
                end
            else
                if newVY > 0 then
                    player.currentAnimation = "walkDown"
                else
                    player.currentAnimation = "walkUp"
                end
            end
        end
    else
        -- Set idle animation when not moving
        player.currentAnimation = "idle"
    end
end

function player.draw()
    local px, py = player.body:getX(), player.body:getY()
    local spriteNum = math.floor(player.animation.currentTime / player.animation.duration * #player.animation.quads) + 1
    -- print( player.animation.duration)
    love.graphics.draw(player.animation.spriteSheet, player.animation.quads[spriteNum],   px,  py, var.character_rotation, player.scale, player.scale, -150, 0)
end

function player.getPosition()
    return player.body:getX(), player.body:getY()
end

function player.getAnimation()
    return player.animation
end

return player