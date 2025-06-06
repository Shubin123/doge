local area_manager = require("area_manager")
local player = {}
player.health = 100


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

function player.load(world, start_x, start_y)
    -- Destroy existing body if it exists
    if player.body then
        player.body:destroy()
        player.body = nil
    end
    player.body = love.physics.newBody(world, start_x, start_y, "dynamic")
    player.body:setAwake(true) -- Ensure the body is awake immediately after creation
    player.shape = love.physics.newCircleShape(10)
    player.fixture = love.physics.newFixture(player.body, player.shape)
    player.fixture:setGroupIndex(-1)
    player.character = love.graphics.newImage("gfx/doge.png")
    player.width, player.height = player.character:getDimensions()
    -- player.animation = newAnimation(love.graphics.newImage("gfx/Spritepack/1.png"), 16, 24, 2, 16)

    -- player.animation = newAnimation(love.graphics.newImage("gfx/SoldierSpriteSheets/Soldier_Idle.png"), 100,100, 1, 6)
    player.animation = newAnimation(love.graphics.newImage("gfx/testCharacter/jump.png"), 64, 65, 2, 10)

    -- Reset player state and velocity
    player.body:setLinearVelocity(0, 0)
    player.isDodging = false
    player.dodgeTimer = 0
    player.dodgeCooldownTimer = 0

    print("Player load: Loaded at: " .. start_x .. ", " .. start_y .. " in world: " .. tostring(world) .. ". Initial Body Pos: " .. player.body:getX() .. ", " .. player.body:getY())
    print("Player load: Body active: " .. tostring(player.body:isActive()) .. ", Awake: " .. tostring(player.body:isAwake()))
end

function player.update(dt)
    if not player.body then
        -- print("Player update start: NO BODY") -- Commented out for less verbose logging
        return
    end
    -- print("Player update start: Pos: " .. player.body:getX() .. ", " .. player.body:getY() .. " Vel: " .. player.body:getLinearVelocity() .. " Active: " .. tostring(player.body:isActive()) .. " Awake: " .. tostring(player.body:isAwake())) -- Commented out
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

    local lerpFactor = math.min(dt * acceleration / maxSpeed, 1) -- Factor for smooth acceleration

    if keyPressed then
        -- When keys are pressed, accelerate toward target velocity
        newVX = vx + (targetVX - vx) * lerpFactor
        newVY = vy + (targetVY - vy) * lerpFactor
    else
        -- When no keys are pressed, apply friction
        local frictionFactor = 0.9 -- Adjusted friction for smoother deceleration
        newVX = vx * frictionFactor
        newVY = vy * frictionFactor

        -- Stop completely if moving very slowly
        if math.abs(newVX) < 1 and math.abs(newVY) < 1 then -- Lowered threshold for stopping
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
        if moveMagnitude > 1 then -- Lowered threshold for updating direction
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
    -- Temporary logging for debugging movement
    local current_vx, current_vy = player.body:getLinearVelocity()
    -- print("Player update: Velocity = (" .. current_vx .. ", " .. current_vy .. "), Input = (" .. inputX .. ", " .. inputY .. "), isDodging = " .. tostring(player.isDodging)) -- Commented out for less verbose logging
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

    local other_body
    local other_fixture
    if body_a == player.body then
        other_body = body_b
        other_fixture = fixture_b
    elseif body_b == player.body then
        other_body = body_a
        other_fixture = fixture_a
    else
        -- This collision doesn't involve the player, so ignore it here.
        -- print("player.collision: Neither body is player. Body A type: " .. body_a:getType() .. ", Body B type: " .. body_b:getType())
        return
    end

    local current_area = area_manager.getCurrentArea()
    if not current_area then
        print("player.collision: CRITICAL - No current_area found!")
        return
    end

    local other_group_idx = other_fixture:getGroupIndex()
    print("player.collision: Player (Group " .. fixture_a:getGroupIndex() .. ") collided with Other (Group " .. other_group_idx .. "). Other body type: " .. other_body:getType())

    -- Check against current area's coins
    if current_area.coin_bods and #current_area.coin_bods > 0 then
        if checkDestroy(current_area.coin_bods, other_body) then
            print("player.collision: Destroyed a coin from current area.")
            var.player_score = var.player_score + 1
            -- Note: var.num_coins might be desynced if not managed carefully with area transitions.
            -- For now, focusing on collision.
            return -- Assuming coin collision means no other type of collision for this event
        end
    end

    -- Check against current area's enemies
    if current_area.enemies_bods and #current_area.enemies_bods > 0 then
        if checkDestroy(current_area.enemies_bods, other_body) then
            print("player.collision: Collided with an enemy from current area.")
            player.health = player.health - 1
            -- var.num_enemies might also be desynced.
            return -- Assuming enemy collision means no other type of collision
        end
    end
    
    -- If it's not a coin or an enemy from the current area, it might be a wall or other static object.
    -- Box2D should handle the physical collision response (stopping) by default for dynamic vs static.
    -- If player is still passing through walls, the issue might be elsewhere (e.g. fixture properties, world updates).
    print("player.collision: Collision with non-coin/enemy object. Type: " .. other_body:getType() .. ", Group: " .. other_group_idx .. ". Default Box2D response should occur.")

end

function player.getPosition()
    return player.body:getX(), player.body:getY()
end

function player.getAnimation()
    return player.animation
end

function player.moveTo(x, y)
  if player.body then
    player.body:setPosition(x, y)
    print("Player moveTo: Moved to: " .. x .. ", " .. y .. ". Body Active: " .. tostring(player.body:isActive()) .. ", Awake: " .. tostring(player.body:isAwake()))
  else
    print("Player moveTo: Attempted to move, but NO BODY.")
  end
end

function player.unload()
    if player.body then
        print("Player unload: Destroying body. Current Pos: " .. player.body:getX() .. ", " .. player.body:getY() .. " Active: " .. tostring(player.body:isActive()))
        player.body:destroy()
        player.body = nil
    end
end

return player