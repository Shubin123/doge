local player = {}
player.health = 100
player.online = {}
player.online.bodies = {}
player.online.health = {}

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

function player.load(world)
    player.body = love.physics.newBody(world, var.game_width / 2, var.game_height / 2, "dynamic")
    player.shape = love.physics.newCircleShape(10)
    player.fixture = love.physics.newFixture(player.body, player.shape)
    player.fixture:setGroupIndex(-1)
    player.character = love.graphics.newImage("gfx/doge.png")
    player.width, player.height = player.character:getDimensions()
    -- player.animation = newAnimation(love.graphics.newImage("gfx/Spritepack/1.png"), 16, 24, 2, 16)
    
    -- player.animation = newAnimation(love.graphics.newImage("gfx/SoldierSpriteSheets/Soldier_Idle.png"), 100,100, 1, 6)
    player.animation = newAnimation(love.graphics.newImage("gfx/testCharacter/jump.png"), 64, 65, 2, 10)

    -- for i=1,mp.max_peers do 

    -- table.insert(player.online.bodies,  love.physics.newBody(world, var.game_width / 2, var.game_height / 2, "dynamic")  )-- set an online player body for testing
    
    -- player.online.fixture = love.physics.newFixture(player.online.bodies[i], player.shape)
    -- player.online.fixture:setGroupIndex(-1)
    --assuming online players size is same -- doesnt have to be but would have to have more replicated data
    
    -- end


end

function player.update(dt)
    if player.health <= 0 then
        var.State = "menu"
    end
    
    -- Dodge system variables (initialize these in player.load() if not already)
    player.dodgeSpeed = player.dodgeSpeed or 300
    player.dodgeDuration = player.dodgeDuration or 0.2
    player.dodgeCooldown = player.dodgeCooldown or 1.0
    player.isDodging = player.isDodging or false
    player.dodgeTimer = player.dodgeTimer or 0
    player.dodgeCooldownTimer = player.dodgeCooldownTimer or 0
    player.dodgeDirection = player.dodgeDirection or {x = 0, y = 0}
    
    -- Update dodge timers
    if player.dodgeTimer > 0 then
        player.dodgeTimer = player.dodgeTimer - dt
        if player.dodgeTimer <= 0 then
            player.isDodging = false
        end
    end
    
    if player.dodgeCooldownTimer > 0 then
        player.dodgeCooldownTimer = player.dodgeCooldownTimer - dt
    end
    
    -- Check for dodge input (space key)
    if love.keyboard.isDown("space") and not player.isDodging and player.dodgeCooldownTimer <= 0 then
        -- Get current movement direction for dodge
        local inputX, inputY = 0, 0
        
        if love.keyboard.isDown("a") then inputX = inputX - 1 end
        if love.keyboard.isDown("d") then inputX = inputX + 1 end
        if love.keyboard.isDown("w") then inputY = inputY - 1 end
        if love.keyboard.isDown("s") then inputY = inputY + 1 end
        
        -- If no movement keys, dodge forward based on last facing direction
        if inputX == 0 and inputY == 0 then
            inputX = math.cos(player.direction or 0)
            inputY = math.sin(player.direction or 0)
        end
        
        -- Normalize dodge direction
        if inputX ~= 0 or inputY ~= 0 then
            local length = math.sqrt(inputX * inputX + inputY * inputY)
            player.dodgeDirection.x = inputX / length
            player.dodgeDirection.y = inputY / length
            
            -- Start dodge
            player.isDodging = true
            player.dodgeTimer = player.dodgeDuration
            player.dodgeCooldownTimer = player.dodgeCooldown
        end
    end
    
    -- Handle dodge movement
    if player.isDodging then
        -- Apply dodge velocity
        local dodgeVX = player.dodgeDirection.x * player.dodgeSpeed
        local dodgeVY = player.dodgeDirection.y * player.dodgeSpeed
        player.body:setLinearVelocity(dodgeVX, dodgeVY)
        
        -- Set dodge animation
        player.currentAnimation = "dodge"
        return -- Skip normal movement during dodge
    end
    
    -- Normal movement (only when not dodging)
    local maxSpeed = 100
    local acceleration = 2000
    local friction = 0.85
    
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
        if moveMagnitude > 10 then
            -- Calculate direction angle
            player.direction = math.atan2(newVY, newVX)
            
            -- Determine animation based on movement direction
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

-- Simple momentum-based knockback system
function player.applyKnockback(direction, force)
    if not player.body then return end
    
    -- Get current velocity
    local vx, vy = player.body:getLinearVelocity()
    
    -- Apply direct momentum transfer (Newton's laws!)
    local knockbackVx = direction.x * force
    local knockbackVy = direction.y * force
    
    -- Add knockback to current velocity for immediate visible effect
    player.body:setLinearVelocity(vx + knockbackVx, vy + knockbackVy)
end

function player.draw()
    local px, py = player.body:getX(), player.body:getY()
    local spriteNum = math.floor(player.animation.currentTime / player.animation.duration * #player.animation.quads) + 1
    -- print( player.animation.duration)
    love.graphics.draw(player.animation.spriteSheet, player.animation.quads[spriteNum],   px,  py, var.character_rotation, player.scale, player.scale, -150, 0)
end

function player.collision(fixture_a,fixture_b,contact)
    local body_a = fixture_a:getBody()
    local body_b = fixture_b:getBody()

    local not_player -- either enemy or coin for now
    if body_a == player.body then
        not_player = body_b
    elseif body_b == player.body then
        not_player = body_a
    else
        return
    end
    -- print(fixture_a:getGroupIndex(),fixture_b:getGroupIndex())
    
    -- print(fixture_a:getMask(),fixture_b:getMask())
    -- print(fixture_a:getCategory(),fixture_b:getCategory())
    

    
    if checkDestroy(coin_bods, not_player) then
        var.player_score = var.player_score + 1
        var.num_coins = var.num_coins - 1
        -- Add fireball to ring when collecting coins
        if fire and fire.addFireball then
            fire.addFireball()
        end
        
    elseif  checkDestroy(enemies_bods, not_player) then
        player.health = player.health - 1
        -- var.num_enemies = var.num_enemies - 1
     
     end


end

function player.getPosition()
    return player.body:getX(), player.body:getY()
end

function player.getAnimation()
    return player.animation
end

return player