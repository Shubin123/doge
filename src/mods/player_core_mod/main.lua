-- Player Core Mod - Main Entry Point
-- Provides the core player system migrated from hardcoded main.lua implementation
-- Handles movement, physics, health, dodge mechanics, animations, and collision responses

local playerCoreMod = {}

-- Mod state
local player_data = {}
local mod_config = {}
local api = nil

-- Animation system
local animation_system = {}

-- Input state tracking (since we can't directly access love.keyboard in sandbox)
local input_state = {
    keys_down = {},
    key_pressed_this_frame = {},
    mouse_pressed = false,
    mouse_x = 0,
    mouse_y = 0
}

-- Player entity template
local PLAYER_TEMPLATE = {
    health = 100,
    max_health = 100,
    scale = 0.8,
    max_speed = 100,
    acceleration = 2000,
    friction = 0.85,
    
    -- Dodge system
    dodge_speed = 300,
    dodge_duration = 0.2,
    dodge_cooldown = 1.0,
    is_dodging = false,
    dodge_timer = 0,
    dodge_cooldown_timer = 0,
    dodge_direction = {x = 0, y = 0},
    
    -- Animation
    current_animation = "idle",
    direction = 0,
    
    -- Physics
    collision_group = -1
}

-- Animation creation helper (migrated from player.lua)
function createAnimation(texture, width, height, duration, numFrames)
    local animation = {}
    animation.spriteSheet = texture
    animation.quads = {}
    
    local totalPossibleFrames = math.floor(texture:getWidth() / width) * math.floor(texture:getHeight() / height)
    local framesToUse = numFrames or totalPossibleFrames
    framesToUse = math.min(framesToUse, totalPossibleFrames)
    
    local frameCount = 0
    for y = 0, texture:getHeight() - height, height do
        for x = 0, texture:getWidth() - width, width do
            table.insert(animation.quads, api.renderer.createQuad(x, y, width, height, texture:getDimensions()))
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

-- Initialize the mod
function playerCoreMod.init(mod_api)
    print("[PLAYER_CORE_MOD] Initializing Player Core System v1.0.0")
    
    api = mod_api
    
    -- Load configuration
    mod_config = {
        player_health = 100,
        player_max_speed = 100,
        player_acceleration = 2000,
        player_friction = 0.85,
        dodge_speed = 300,
        dodge_duration = 0.2,
        dodge_cooldown = 1.0,
        player_scale = 0.8,
        collision_group = -1,
        enable_animations = true,
        enable_dodge_system = true,
        enable_knockback = true,
        enable_networking = true
    }
    
    -- Register input handlers for movement (key presses only)
    api.input.registerKeyHandler("w", function() playerCoreMod.handleKeyPress("w") end)
    api.input.registerKeyHandler("a", function() playerCoreMod.handleKeyPress("a") end)
    api.input.registerKeyHandler("s", function() playerCoreMod.handleKeyPress("s") end)
    api.input.registerKeyHandler("d", function() playerCoreMod.handleKeyPress("d") end)
    api.input.registerKeyHandler("space", function() playerCoreMod.handleKeyPress("space") end)
    
    -- Register network handler
    if mod_config.enable_networking then
        api.network.registerMessageHandler("player_core_mod", playerCoreMod.handleNetworkMessage)
    end
    
    -- Initialize player
    playerCoreMod.createPlayer()
    
    print("[PLAYER_CORE_MOD] Player system initialized!")
end

-- Handle key press events (called by input handlers)
function playerCoreMod.handleKeyPress(key)
    if not player_data.active then return end
    
    input_state.key_pressed_this_frame[key] = true
    
    -- For movement keys, apply immediate impulse-based movement
    if key == "w" or key == "a" or key == "s" or key == "d" then
        playerCoreMod.applyMovementImpulse(key)
    end
    
    -- Set key as currently down (we'll assume it's held for a short duration)
    input_state.keys_down[key] = api.utils.getTime() + 0.2  -- Hold for 200ms for better responsiveness
end

-- Apply movement impulse (called immediately on key press)
function playerCoreMod.applyMovementImpulse(key)
    if not player_data.body or player_data.is_dodging then return end
    
    local impulse_strength = 15  -- Impulse force
    local vx, vy = player_data.body:getLinearVelocity()
    
    -- Apply impulse based on key
    if key == "w" then
        player_data.body:setLinearVelocity(vx, math.max(vy - impulse_strength, -player_data.max_speed))
        player_data.current_animation = "walkUp"
        player_data.direction = -math.pi/2
    elseif key == "s" then
        player_data.body:setLinearVelocity(vx, math.min(vy + impulse_strength, player_data.max_speed))
        player_data.current_animation = "walkDown"
        player_data.direction = math.pi/2
    elseif key == "a" then
        player_data.body:setLinearVelocity(math.max(vx - impulse_strength, -player_data.max_speed), vy)
        player_data.current_animation = "walkLeft"
        player_data.direction = math.pi
    elseif key == "d" then
        player_data.body:setLinearVelocity(math.min(vx + impulse_strength, player_data.max_speed), vy)
        player_data.current_animation = "walkRight"
        player_data.direction = 0
    end
end

-- Create the player entity
function playerCoreMod.createPlayer()
    local world = api.physics.getWorld()
    if not world then
        print("[PLAYER_CORE_MOD] Warning: Physics world not available")
        return
    end
    
    -- Get game dimensions
    local game_width = 400  -- var.game_width
    local game_height = 400 -- var.game_height
    
    -- Create player physics body
    local body = api.physics.createBody(game_width / 2, game_height / 2, "dynamic", mod_config.collision_group, 1.0, 0.3)
    if not body then
        print("[PLAYER_CORE_MOD] Failed to create player physics body")
        return
    end
    
    -- Create collision shape and fixture
    local shape = api.physics.createCircleShape(10)
    local fixture = api.physics.createFixture(body, shape, mod_config.collision_group, 1.0, 0.3)
    
    if fixture then
        fixture:setGroupIndex(mod_config.collision_group)
        
        -- Get client ID for multiplayer identification
        local client_id = nil
        if api.network and api.network.getLocalClientId then
            client_id = api.network.getLocalClientId()
        elseif api.game and api.game.getMultiplayerMode then
            local mp_mode = api.game.getMultiplayerMode()
            if mp_mode then
                client_id = "client_" .. mp_mode
            end
        end
        
        fixture:setUserData({
            type = "player",
            mod = "player_core_mod",
            id = "player",
            client_id = client_id
        })
    end
    
    -- Initialize player data
    player_data = {
        -- Core properties
        health = mod_config.player_health,
        max_health = mod_config.player_health,
        active = true,
        
        -- Physics
        body = body,
        fixture = fixture,
        x = game_width / 2,
        y = game_height / 2,
        
        -- Movement
        max_speed = mod_config.player_max_speed,
        acceleration = mod_config.player_acceleration,
        friction = mod_config.player_friction,
        
        -- Dodge system
        dodge_speed = mod_config.dodge_speed,
        dodge_duration = mod_config.dodge_duration,
        dodge_cooldown = mod_config.dodge_cooldown,
        is_dodging = false,
        dodge_timer = 0,
        dodge_cooldown_timer = 0,
        dodge_direction = {x = 0, y = 0},
        
        -- Animation and rendering
        scale = mod_config.player_scale,
        current_animation = "idle",
        direction = 0,
        animation = nil,
        character_texture = nil,
        
        -- Network sync
        last_sync_time = 0,
        sync_interval = 1/30  -- 30 FPS sync rate
    }
    
    -- Load textures and create animations
    playerCoreMod.initializeAssets()
    
    print("[PLAYER_CORE_MOD] Player entity created successfully")
end

-- Initialize player assets (textures and animations)
function playerCoreMod.initializeAssets()
    -- Load main character texture (using shared assets)
    player_data.character_texture = api.utils.loadTexture("doge", "../gfx/doge.png")
    
    -- Load animation texture (using shared assets)
    local anim_texture = api.utils.loadTexture("player_jump_anim", "../gfx/testCharacter/jump.png")
    
    if anim_texture then
        player_data.animation = createAnimation(anim_texture, 64, 65, 2, 10)
        print("[PLAYER_CORE_MOD] Player animation loaded successfully")
    else
        print("[PLAYER_CORE_MOD] Warning: Failed to load player animation texture")
    end
    
    if player_data.character_texture then
        player_data.width, player_data.height = player_data.character_texture:getDimensions()
        print("[PLAYER_CORE_MOD] Player textures loaded successfully")
    else
        print("[PLAYER_CORE_MOD] Warning: Failed to load player character texture")
    end
end

-- Update player system
function playerCoreMod.update(dt)
    if not player_data.active or not player_data.body then
        return
    end
    
    -- Check if player is dead
    if player_data.health <= 0 then
        playerCoreMod.handlePlayerDeath()
        return
    end
    
    -- Update player position from physics
    player_data.x, player_data.y = player_data.body:getPosition()
    
    -- Update dodge system
    playerCoreMod.updateDodgeSystem(dt)
    
    -- Update movement (only if not dodging)
    if not player_data.is_dodging then
        playerCoreMod.updateMovement(dt)
    end
    
    -- Update animations
    if player_data.animation then
        player_data.animation.currentTime = player_data.animation.currentTime + dt
        if player_data.animation.currentTime >= player_data.animation.duration then
            player_data.animation.currentTime = player_data.animation.currentTime - player_data.animation.duration
        end
    end
    
    -- Network synchronization
    if mod_config.enable_networking then
        playerCoreMod.updateNetworkSync(dt)
    end
    
    -- Add player to render queue
    playerCoreMod.renderPlayer()
    
    -- Update input state - expire old key presses
    local current_time = api.utils.getTime()
    for key, expire_time in pairs(input_state.keys_down) do
        if current_time > expire_time then
            input_state.keys_down[key] = nil
        end
    end
    
    -- Clear this frame's input flags
    input_state.key_pressed_this_frame = {}
end

-- Update dodge system
function playerCoreMod.updateDodgeSystem(dt)
    -- Update dodge timers
    if player_data.dodge_timer > 0 then
        player_data.dodge_timer = player_data.dodge_timer - dt
        if player_data.dodge_timer <= 0 then
            player_data.is_dodging = false
        end
    end
    
    if player_data.dodge_cooldown_timer > 0 then
        player_data.dodge_cooldown_timer = player_data.dodge_cooldown_timer - dt
    end
    
    -- Check for dodge input (space key)
    if input_state.key_pressed_this_frame["space"] and not player_data.is_dodging and player_data.dodge_cooldown_timer <= 0 then
        -- Get current movement direction for dodge
        local inputX, inputY = 0, 0
        
        if input_state.keys_down["a"] then inputX = inputX - 1 end
        if input_state.keys_down["d"] then inputX = inputX + 1 end
        if input_state.keys_down["w"] then inputY = inputY - 1 end
        if input_state.keys_down["s"] then inputY = inputY + 1 end
        
        -- If no movement keys, dodge forward based on last facing direction
        if inputX == 0 and inputY == 0 then
            inputX = math.cos(player_data.direction or 0)
            inputY = math.sin(player_data.direction or 0)
        end
        
        -- Normalize dodge direction
        if inputX ~= 0 or inputY ~= 0 then
            local length = math.sqrt(inputX * inputX + inputY * inputY)
            player_data.dodge_direction.x = inputX / length
            player_data.dodge_direction.y = inputY / length
            
            -- Start dodge
            player_data.is_dodging = true
            player_data.dodge_timer = player_data.dodge_duration
            player_data.dodge_cooldown_timer = player_data.dodge_cooldown
            
            print("[PLAYER_CORE_MOD] Player dodging!")
        end
    end
    
    -- Handle dodge movement
    if player_data.is_dodging then
        -- Apply dodge velocity
        local dodgeVX = player_data.dodge_direction.x * player_data.dodge_speed
        local dodgeVY = player_data.dodge_direction.y * player_data.dodge_speed
        player_data.body:setLinearVelocity(dodgeVX, dodgeVY)
        
        -- Set dodge animation
        player_data.current_animation = "dodge"
    end
end

-- Update player movement (simplified for impulse-based system)
function playerCoreMod.updateMovement(dt)
    -- Get current velocity
    local vx, vy = player_data.body:getLinearVelocity()
    
    -- Apply friction to gradually slow down
    local friction_factor = math.pow(player_data.friction, dt * 60) -- Frame-rate independent friction
    local newVX = vx * friction_factor
    local newVY = vy * friction_factor
    
    -- Stop completely if moving very slowly
    if math.abs(newVX) < 5 and math.abs(newVY) < 5 then
        newVX, newVY = 0, 0
        player_data.current_animation = "idle"
    end
    
    -- Apply the calculated velocity
    player_data.body:setLinearVelocity(newVX, newVY)
end

-- Render player
function playerCoreMod.renderPlayer()
    if not player_data.active then return end
    
    -- Debug: log player position every 60 frames
    if not player_data.debug_counter then player_data.debug_counter = 0 end
    player_data.debug_counter = player_data.debug_counter + 1
    if player_data.debug_counter % 60 == 0 then
        print("[PLAYER_CORE_MOD] Player rendering at: " .. player_data.x .. ", " .. player_data.y)
    end
    
    -- Add player to render queue
    if player_data.animation and player_data.animation.spriteSheet then
        local spriteNum = math.floor(player_data.animation.currentTime / player_data.animation.duration * #player_data.animation.quads) + 1
        if spriteNum > #player_data.animation.quads then spriteNum = #player_data.animation.quads end
        
        -- Use sprite_quad type for animated sprites
        api.renderer.addToQueue("world", {
            type = "sprite_quad",
            texture_name = "player_jump", -- Use the preloaded texture name
            quad = player_data.animation.quads[spriteNum],
            x = player_data.x,
            y = player_data.y,
            rotation = 0,
            scale_x = player_data.scale,
            scale_y = player_data.scale,
            offset_x = 32, -- Half of 64 (sprite width) to center
            offset_y = 32, -- Half of 64 (approximate sprite height) to center
            sort_y = player_data.y,
            active = true,
            color = {1, 1, 1, 1}
        })
    elseif player_data.character_texture then
        -- Fallback to static character texture
        api.renderer.addToQueue("world", {
            type = "sprite",
            texture_name = "doge",
            x = player_data.x,
            y = player_data.y,
            rotation = 0,
            scale_x = player_data.scale,
            scale_y = player_data.scale,
            offset_x = -150, -- Add missing offset
            offset_y = 0,
            sort_y = player_data.y,
            active = true,
            color = {1, 1, 1, 1}
        })
    end
    
    -- Render health bar if damaged
    if player_data.health < player_data.max_health then
        playerCoreMod.renderHealthBar()
    end
end

-- Render player health bar
function playerCoreMod.renderHealthBar()
    local health_percent = player_data.health / player_data.max_health
    local bar_width = 40
    local bar_height = 6
    local bar_y = player_data.y - 30
    
    -- Background
    api.renderer.addToQueue("ui", {
        type = "rectangle",
        mode = "fill",
        x = player_data.x - bar_width/2,
        y = bar_y,
        width = bar_width,
        height = bar_height,
        sort_y = 10000,
        active = true,
        color = {0.2, 0.2, 0.2, 0.8}
    })
    
    -- Health fill
    api.renderer.addToQueue("ui", {
        type = "rectangle",
        mode = "fill",
        x = player_data.x - bar_width/2 + 1,
        y = bar_y + 1,
        width = (bar_width - 2) * health_percent,
        height = bar_height - 2,
        sort_y = 10001,
        active = true,
        color = health_percent > 0.5 and {0.2, 0.8, 0.2, 0.9} or {0.8, 0.2, 0.2, 0.9}
    })
end

-- Apply knockback to player (from original player.applyKnockback)
function playerCoreMod.applyKnockback(direction, force)
    if not player_data.body or not mod_config.enable_knockback then return end
    
    -- Get current velocity
    local vx, vy = player_data.body:getLinearVelocity()
    
    -- Apply direct momentum transfer
    local knockbackVx = direction.x * force
    local knockbackVy = direction.y * force
    
    -- Add knockback to current velocity for immediate visible effect
    player_data.body:setLinearVelocity(vx + knockbackVx, vy + knockbackVy)
    
    print("[PLAYER_CORE_MOD] Applied knockback: " .. force)
end

-- Handle player damage
function playerCoreMod.damagePlayer(damage, source)
    if not player_data.active then return end
    
    player_data.health = math.max(0, player_data.health - damage)
    
    print("[PLAYER_CORE_MOD] Player took " .. damage .. " damage. Health: " .. player_data.health)
    
    -- Show damage indicator using damage_indicators_mod
    local damage_mod = api.mods and api.mods.damage_indicators_mod
    if damage_mod and damage_mod.exports then
        damage_mod.exports.onPlayerDamage("player", player_data.x, player_data.y, damage, "physical", source)
    end
    
    -- Show health bar update using health_damage_mod
    local health_mod = api.mods and api.mods.health_damage_mod
    if health_mod and health_mod.exports then
        health_mod.exports.updateHealthBar("player", player_data.health, player_data.max_health, player_data.x, player_data.y)
    end
    
    -- Check for death
    if player_data.health <= 0 then
        playerCoreMod.handlePlayerDeath()
    end
    
    -- Sync damage over network
    if mod_config.enable_networking then
        api.network.sendToAll({
            action = "player_damage",
            damage = damage,
            new_health = player_data.health,
            source = source
        }, "player_core_mod")
    end
end

-- Handle player death
function playerCoreMod.handlePlayerDeath()
    player_data.health = 0
    
    print("[PLAYER_CORE_MOD] Player died!")
    
    -- Trigger game state change (this would need to be exposed through the API)
    -- For now, we'll just log it
    print("[PLAYER_CORE_MOD] Game should transition to menu state")
    
    -- Network sync
    if mod_config.enable_networking then
        api.network.sendToAll({
            action = "player_death",
            x = player_data.x,
            y = player_data.y
        }, "player_core_mod")
    end
end

-- Handle collisions
function playerCoreMod.handleCollision(fixture_a, fixture_b, contact)
    local body_a = fixture_a:getBody()
    local body_b = fixture_b:getBody()
    
    local not_player -- either enemy or coin for now
    if body_a == player_data.body then
        not_player = body_b
    elseif body_b == player_data.body then
        not_player = body_a
    else
        return
    end
    
    -- This would need to be expanded to handle specific collision types
    -- For now, we'll just log the collision
    print("[PLAYER_CORE_MOD] Player collision detected")
end

-- Get player position (API for other mods)
function playerCoreMod.getPosition()
    if player_data.body then
        return player_data.body:getX(), player_data.body:getY()
    end
    return 0, 0
end

-- Get player health (API for other mods)
function playerCoreMod.getHealth()
    return player_data.health, player_data.max_health
end

-- Get player animation (API for other mods)
function playerCoreMod.getAnimation()
    return player_data.animation
end

-- Network synchronization
function playerCoreMod.updateNetworkSync(dt)
    player_data.last_sync_time = player_data.last_sync_time + dt
    
    if player_data.last_sync_time >= player_data.sync_interval then
        -- Send player state
        api.network.sendToAll({
            action = "player_sync",
            x = player_data.x,
            y = player_data.y,
            health = player_data.health,
            animation = player_data.current_animation,
            direction = player_data.direction
        }, "player_core_mod")
        
        player_data.last_sync_time = 0
    end
end

-- Handle network messages
function playerCoreMod.handleNetworkMessage(data)
    if data.action == "player_sync" then
        -- Handle remote player state updates
        -- This would need more complex logic for multiplayer
        print("[PLAYER_CORE_MOD] Received player sync from network")
    elseif data.action == "player_damage" then
        -- Handle remote player damage
        print("[PLAYER_CORE_MOD] Remote player took damage: " .. data.damage)
    elseif data.action == "player_death" then
        -- Handle remote player death
        print("[PLAYER_CORE_MOD] Remote player died at " .. data.x .. ", " .. data.y)
    end
end

-- Cleanup
function playerCoreMod.cleanup()
    if player_data.body and not player_data.body:isDestroyed() then
        player_data.body:destroy()
    end
    
    player_data = {}
    input_state = {keys_down = {}, mouse_pressed = false, mouse_x = 0, mouse_y = 0}
    
    print("[PLAYER_CORE_MOD] Cleanup complete")
end

-- Export functions for other mods to use
playerCoreMod.exports = {
    getPosition = playerCoreMod.getPosition,
    getHealth = playerCoreMod.getHealth,
    getAnimation = playerCoreMod.getAnimation,
    damagePlayer = playerCoreMod.damagePlayer,
    applyKnockback = playerCoreMod.applyKnockback,
    handleCollision = playerCoreMod.handleCollision
}

return playerCoreMod