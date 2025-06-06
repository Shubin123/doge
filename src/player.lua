local player = {}
local game_state = require("game_state")
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

function player.load(world)
    -- Start player at world coordinates (400, 300) instead of screen-relative coordinates
    player.body = love.physics.newBody(world, 400, 300, "dynamic")
    player.shape = love.physics.newCircleShape(10)
    player.fixture = love.physics.newFixture(player.body, player.shape)
    player.fixture:setGroupIndex(-1)
    
    -- Initialize directional animation system
    player.facing_direction = "down"  -- down, up, left, right
    player.current_state = "idle"     -- idle, walk, dash, attack
    player.character_data = nil       -- Will be set by character manager
    player.animations = {}            -- Will be populated by character manager
    
    -- Legacy fallback
    player.character = love.graphics.newImage("gfx/doge.png")
    player.width, player.height = player.character:getDimensions()
    player.animation = newAnimation(love.graphics.newImage("gfx/testCharacter/jump.png"), 64, 65, 2, 10)

end

-- Set character data from character manager
function player.set_character_data(character_data)
    player.character_data = character_data
    player.animations = character_data.animations
    
    -- Update physics properties (note: can't modify existing shape radius in Love2D)
    -- The shape radius will be set when creating a new character instance
    player.scale = character_data.physics.scale
    
    -- Update stats
    player.health = character_data.stats.health
    player.max_health = character_data.stats.health
    player.speed = character_data.stats.speed
    
    print("Player character set to: " .. character_data.definition.name)
end

-- Get current animation based on state and direction
function player.get_current_animation()
    if not player.character_data then
        return player.animation -- fallback to legacy
    end
    
    -- For simple character, just use basic states: idle, walk, dash
    local anim_name = player.current_state
    
    -- Check if this animation exists
    if player.animations[anim_name] then
        return player.animations[anim_name]
    end
    
    -- Final fallback to idle
    return player.animations["idle"] or player.animation
end

-- Update facing direction based on movement
function player.update_facing_direction(vx, vy)
    if math.abs(vx) > math.abs(vy) then
        if vx > 0 then
            player.facing_direction = "right"
        else
            player.facing_direction = "left"
        end
    else
        if vy > 0 then
            player.facing_direction = "down"
        else
            player.facing_direction = "up"
        end
    end
end

function player.update(dt)
    if player.health <= 0 then
        -- Use new game state system for death handling
        local current_state = game_state.getCurrentState()
        local states = game_state.getStates()
        
        if current_state == states.PLAYING then
            game_state.gameOver("Player defeated")
            player.death_timer = 2.0
        end
        
        -- Handle death timer
        if current_state == states.GAME_OVER then
            player.death_timer = (player.death_timer or 2.0) - dt
            if player.death_timer <= 0 then
                game_state.returnToMainMenu()
            end
            return -- Stop updating player when dead
        end
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
    
    -- Handle dodge/dash movement
    if player.isDodging then
        -- Apply dodge velocity
        local dodgeVX = player.dodgeDirection.x * player.dodgeSpeed
        local dodgeVY = player.dodgeDirection.y * player.dodgeSpeed
        player.body:setLinearVelocity(dodgeVX, dodgeVY)
        
        -- Update facing direction for dash
        player.update_facing_direction(dodgeVX, dodgeVY)
        
        -- Set dash animation
        player.current_state = "dash"
        return -- Skip normal movement during dodge
    end
    
    -- Normal movement (only when not dodging)
    local maxSpeed = player.speed or 100
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
    
    -- Update animation system
    local current_anim = player.get_current_animation()
    if current_anim then
        current_anim.current_time = current_anim.current_time + dt
        if current_anim.current_time >= current_anim.duration then
            current_anim.current_time = current_anim.current_time - current_anim.duration
        end
    end
    
    -- Update legacy animation fallback
    if player.animation then
        player.animation.currentTime = (player.animation.currentTime or 0) + dt
        if player.animation.currentTime >= (player.animation.duration or 1) then
            player.animation.currentTime = player.animation.currentTime - (player.animation.duration or 1)
        end
    end
    
    -- Update facing direction and animation state based on movement
    if newVX ~= 0 or newVY ~= 0 then
        -- Only update direction when actually moving
        local moveMagnitude = math.sqrt(newVX * newVX + newVY * newVY)
        if moveMagnitude > 10 then
            -- Update facing direction
            player.update_facing_direction(newVX, newVY)
            
            -- Set walk state
            player.current_state = "walk"
            
            -- Calculate direction angle for legacy compatibility
            player.direction = math.atan2(newVY, newVX)
            
            -- Legacy animation names for compatibility
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
        player.current_state = "idle"
        player.currentAnimation = "idle"
    end
end

function player.draw()
    local px, py = player.body:getX(), player.body:getY()
    
    -- Use new animation system if available
    local current_anim = player.get_current_animation()
    if current_anim and current_anim.quads and #current_anim.quads > 0 then
        
        -- Handle procedural rendering (rectangles/shapes)
        if current_anim.is_procedural then
            local scale = player.scale or 1.0
            local frame_width = current_anim.frame_width or 32
            local frame_height = current_anim.frame_height or 32
            local color = current_anim.color or {1, 1, 1, 1}
            
            -- Save current color
            local r, g, b, a = love.graphics.getColor()
            
            -- Set character color
            love.graphics.setColor(color[1], color[2], color[3], color[4])
            
            -- Draw rectangle character
            love.graphics.rectangle(
                "fill",
                px - (frame_width * scale) / 2,
                py - (frame_height * scale) / 2,
                frame_width * scale,
                frame_height * scale
            )
            
            -- Draw border for visibility
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.rectangle(
                "line",
                px - (frame_width * scale) / 2,
                py - (frame_height * scale) / 2,
                frame_width * scale,
                frame_height * scale
            )
            
            -- Restore original color
            love.graphics.setColor(r, g, b, a)
            
        else
            -- Handle sprite sheet rendering
            local spriteNum = math.floor(current_anim.current_time / current_anim.duration * #current_anim.quads) + 1
            spriteNum = math.max(1, math.min(#current_anim.quads, spriteNum))
            
            local scale = player.scale or 0.8
            local frame_width = current_anim.frame_width or 64
            local frame_height = current_anim.frame_height or 64
            
            love.graphics.draw(
                current_anim.sprite_sheet, 
                current_anim.quads[spriteNum], 
                px, py, 
                var.character_rotation or 0, 
                scale, scale, 
                frame_width / 2, frame_height / 2
            )
        end
    else
        -- Fallback to legacy animation system
        if player.animation and player.animation.quads and #player.animation.quads > 0 then
            local spriteNum = math.floor(player.animation.currentTime / player.animation.duration * #player.animation.quads) + 1
            love.graphics.draw(player.animation.spriteSheet, player.animation.quads[spriteNum], px, py, var.character_rotation, player.scale, player.scale, 32, 32)
        else
            -- Ultimate fallback: draw a simple square
            love.graphics.setColor(0.5, 0.5, 1.0, 1.0)
            love.graphics.rectangle("fill", px - 16, py - 16, 32, 32)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end
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
        var.num_coins = var.num_coins -1
        
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