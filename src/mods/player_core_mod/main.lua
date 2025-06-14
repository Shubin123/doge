-- Player Core Mod - Enhanced Version with LPC Assets
-- Provides the core player system with full LPC sprite animations
-- Implements acceleration-based movement, state machine, and 8-directional animations

local playerCoreMod = {}

-- Mod state
local player_data = {}
local mod_config = {}
local api = nil

-- Animation system with full LPC support
local animation_system = {
    animations = {},
    current_state = "IDLE",
    current_direction = "down",
    blend_time = 0.1,
    blend_timer = 0
}

-- Player movement states
local MOVEMENT_STATES = {
    IDLE = "IDLE",
    WALKING = "WALKING", 
    RUNNING = "RUNNING",
    DODGING = "DODGING",
    JUMPING = "JUMPING"
}

-- 8-directional movement mapping
local DIRECTIONS = {
    "down", "down_left", "left", "up_left",
    "up", "up_right", "right", "down_right"
}

-- Input state tracking
local input_state = {
    keys_down = {},
    key_pressed_this_frame = {},
    mouse_pressed = false,
    mouse_x = 0,
    mouse_y = 0,
    movement_vector = {x = 0, y = 0}
}

-- Enhanced player template with state machine
local PLAYER_TEMPLATE = {
    health = 100,
    max_health = 100,
    scale = 0.8,
    
    -- Movement physics
    max_walk_speed = 80,
    max_run_speed = 140,
    acceleration = 800,
    deceleration = 1200,
    friction = 0.85,
    
    -- Dodge system
    dodge_speed = 300,
    dodge_duration = 0.3,
    dodge_cooldown = 1.2,
    is_dodging = false,
    dodge_timer = 0,
    dodge_cooldown_timer = 0,
    dodge_direction = {x = 0, y = 0},
    
    -- State machine
    state = MOVEMENT_STATES.IDLE,
    previous_state = MOVEMENT_STATES.IDLE,
    state_timer = 0,
    
    -- Animation and direction
    current_animation = "idle",
    direction = "down",
    direction_angle = 0,
    
    -- Physics
    collision_group = -1,
    
    -- Velocity tracking
    velocity = {x = 0, y = 0}
}

-- Helper to create animation quads when texture is available
local function createAnimationQuads(texture, width, height, direction_count, frame_count)
    local quads = {}
    
    -- LPC standard: 8 directions, multiple frames per direction
    local directions = {"down", "left", "right", "up", "down_left", "down_right", "up_left", "up_right"}
    
    -- LPC row mapping (standard LPC format)
    local row_mapping = {
        down = 0,
        left = 1,
        right = 2,
        up = 3,
        down_left = 4,
        down_right = 5,
        up_left = 6,
        up_right = 7
    }
    
    for _, direction in ipairs(directions) do
        if direction_count >= 8 or row_mapping[direction] < direction_count then
            quads[direction] = {}
            
            local row = row_mapping[direction]
            for frame = 0, (frame_count or 4) - 1 do
                local quad = api.renderer.createQuad(
                    frame * width, row * height, 
                    width, height, 
                    texture:getDimensions()
                )
                table.insert(quads[direction], quad)
            end
        end
    end
    
    return quads
end

-- Get current animation frame
local function getCurrentAnimationFrame(animation, direction)
    if not animation then
        return nil
    end
    
    -- Safety check for frame count
    if not animation.frame_count or animation.frame_count <= 0 then
        return 1
    end
    
    -- Safety check for duration
    if not animation.duration or animation.duration <= 0 then
        return 1
    end
    
    -- For simplified animations, we'll create quads on demand
    -- This returns frame index instead of quad
    local frame_duration = animation.duration / animation.frame_count
    local current_frame = math.floor(animation.currentTime / frame_duration) + 1
    current_frame = math.min(current_frame, animation.frame_count)
    
    return current_frame
end

-- Calculate direction from movement vector
local function calculateDirection(vx, vy)
    if vx == 0 and vy == 0 then
        return player_data and player_data.direction or "down" -- Keep current direction when idle
    end
    
    local angle = math.atan2(vy, vx)
    
    -- Convert angle to degrees for easier debugging
    local degrees = angle * 180 / math.pi
    
    -- Normalize angle to [0, 2*pi)
    if angle < 0 then angle = angle + 2*math.pi end
    
    -- Convert to 8-directional index
    -- Add pi/8 to shift the boundaries so each direction covers 45 degrees centered on its angle
    local dir_index = math.floor((angle + math.pi/8) / (math.pi/4)) % 8
    
    -- Map indices to directions
    -- 0 = right (0°), 1 = down_right (45°), 2 = down (90°), etc.
    local direction_map = {
        [0] = "right",      -- 0° (East)
        [1] = "down_right", -- 45° (Southeast)
        [2] = "down",       -- 90° (South)
        [3] = "down_left",  -- 135° (Southwest)
        [4] = "left",       -- 180° (West)
        [5] = "up_left",    -- 225° (Northwest)
        [6] = "up",         -- 270° (North)
        [7] = "up_right"    -- 315° (Northeast)
    }
    
    local direction = direction_map[dir_index] or "down"
    
    -- Debug output
    print(string.format("[PLAYER_CORE_MOD] Direction calc: vx=%.2f, vy=%.2f, angle=%.1f°, dir=%s", vx, vy, degrees, direction))
    
    return direction
end

-- Initialize the mod
function playerCoreMod.init(mod_api)
    print(" * [PLAYER_CORE_MOD] Initializing Player Core System")
    
    api = mod_api
    print("[PLAYER_CORE_MOD DEBUG] API received")
    
    -- Enhanced configuration (matching PRD specs)
    mod_config = {
        player_health = 100,
        player_max_walk_speed = 100,      -- PRD: 100 units/s
        player_max_run_speed = 200,       -- PRD: 200 units/s
        player_acceleration = 2000,       -- PRD: 2000 units/s²
        player_deceleration = 1200,
        player_friction = 0.85,           -- PRD: 0.85
        dodge_speed = 300,
        dodge_duration = 0.3,
        dodge_cooldown = 1.2,
        player_scale = 0.8,
        collision_group = -1,
        enable_animations = true,
        enable_8_directional = true,
        enable_running = true,
        enable_dodge_system = true,
        enable_knockback = true,
        enable_networking = true,
        enable_state_machine = true,
        enable_visual_effects = true,     -- For damage flash, particles
        damage_flash_duration = 0.2,      -- PRD: 0.2s white tint
        animation_blend_time = 0.1        -- PRD: 0.1s transitions
    }
    
    -- Register input handlers for enhanced movement
    api.input.registerKeyHandler("w", function() playerCoreMod.handleKeyPress("w") end)
    api.input.registerKeyHandler("a", function() playerCoreMod.handleKeyPress("a") end)
    api.input.registerKeyHandler("s", function() playerCoreMod.handleKeyPress("s") end)
    api.input.registerKeyHandler("d", function() playerCoreMod.handleKeyPress("d") end)
    api.input.registerKeyHandler("space", function() playerCoreMod.handleKeyPress("space") end)
    api.input.registerKeyHandler("lshift", function() playerCoreMod.handleKeyPress("lshift") end)
    
    -- Register network handler
    if mod_config.enable_networking then
        api.network.registerMessageHandler("player_core_mod", playerCoreMod.handleNetworkMessage)
    end
    
    -- Initialize player
    print("[PLAYER_CORE_MOD DEBUG] About to create player...")
    playerCoreMod.createPlayer()
    
    print("[PLAYER_CORE_MOD] Player system initialized!")
end

-- Enhanced key press handling for acceleration-based movement
function playerCoreMod.handleKeyPress(key)
    if not player_data.active then return end
    
    input_state.key_pressed_this_frame[key] = true
    
    -- Update movement vector based on key presses
    playerCoreMod.updateMovementVector()
end

-- Update movement vector based on current key states
function playerCoreMod.updateMovementVector()
    local moveX, moveY = 0, 0
    
    -- Use api.input.isKeyDown to check current key state
    if api.input.isKeyDown("w") then moveY = moveY - 1 end
    if api.input.isKeyDown("s") then moveY = moveY + 1 end
    if api.input.isKeyDown("a") then moveX = moveX - 1 end
    if api.input.isKeyDown("d") then moveX = moveX + 1 end
    
    -- Normalize diagonal movement for 8-directional support
    if moveX ~= 0 and moveY ~= 0 then
        local length = math.sqrt(moveX * moveX + moveY * moveY)
        moveX = moveX / length
        moveY = moveY / length
    end
    
    input_state.movement_vector.x = moveX
    input_state.movement_vector.y = moveY
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
    
    -- Initialize enhanced player data with state machine
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
        
        -- Enhanced movement system
        max_walk_speed = mod_config.player_max_walk_speed,
        max_run_speed = mod_config.player_max_run_speed,
        acceleration = mod_config.player_acceleration,
        deceleration = mod_config.player_deceleration,
        friction = mod_config.player_friction,
        velocity = {x = 0, y = 0},
        
        -- State machine
        state = MOVEMENT_STATES.IDLE,
        previous_state = MOVEMENT_STATES.IDLE,
        state_timer = 0,
        
        -- Dodge system
        dodge_speed = mod_config.dodge_speed,
        dodge_duration = mod_config.dodge_duration,
        dodge_cooldown = mod_config.dodge_cooldown,
        is_dodging = false,
        dodge_timer = 0,
        dodge_cooldown_timer = 0,
        dodge_direction = {x = 0, y = 0},
        
        -- Enhanced animation system
        scale = mod_config.player_scale,
        current_animation_name = "idle",
        current_animation = nil,
        animations = {},
        direction = "down",
        direction_angle = 0,
        has_fallback = false,
        
        -- Network sync
        last_sync_time = 0,
        sync_interval = 0.1,  -- PRD: sync every 100ms
        
        -- Animation blending
        animation_blend_timer = 0,
        animation_blend_duration = mod_config.animation_blend_time,
        
        -- Visual effects
        damage_flash_timer = 0,
        footstep_timer = 0,
        footstep_interval = 0.3,
        
        -- Jumping state
        is_jumping = false,
        jump_timer = 0,
        jump_duration = 0.5,
        can_double_jump = false,
        has_double_jumped = false,
        
        -- Combat animation
        combat_animation_timer = nil,
        previous_animation_name = "idle"
    }
    
    -- Load textures and create animations
    print("[PLAYER_CORE_MOD DEBUG] About to initialize assets...")
    playerCoreMod.initializeAssets()
    
    print("[PLAYER_CORE_MOD] Player entity created successfully")
end

-- Load LPC assets from engine's preloaded textures
function playerCoreMod.initializeAssets()
    print("[PLAYER_CORE_MOD] Loading LPC sprite assets from engine...")
    
    -- Safety check: ensure renderer is available
    if not api or not api.renderer then
        print("[PLAYER_CORE_MOD] ERROR: Renderer API not available yet")
        return
    end
    
    -- Create animation objects using engine's preloaded textures
    player_data.animations = {}
    
    -- For now, let's use a simpler approach to avoid freezing
    -- We'll store texture names and get textures on demand during rendering
    local anim_configs = {
        -- Name, texture_name, duration, directions, frames
        {"idle", "player_idle", 2.0, 8, 1},
        {"walk", "player_walk", 1.0, 8, 9},
        {"run", "player_run", 0.8, 8, 8},
        {"jump", "player_jump", 0.6, 8, 6},
        {"hurt", "player_hurt", 0.5, 8, 6},
        {"slash", "player_slash", 0.4, 8, 6},
        {"shoot", "player_shoot", 0.4, 8, 13},
        {"spellcast", "player_spellcast", 0.8, 8, 7},
        {"thrust", "player_thrust", 0.4, 8, 8},
        {"dodge", "player_dodge", 0.3, 8, 6}  -- Using dodge animation if available
    }
    
    -- Create animations with just metadata (no texture loading yet)
    print("[PLAYER_CORE_MOD DEBUG] Starting animation loop with " .. #anim_configs .. " configs")
    for i, config in ipairs(anim_configs) do
        print("[PLAYER_CORE_MOD DEBUG] Processing config " .. i)
        if not config then
            print("[PLAYER_CORE_MOD ERROR] Config " .. i .. " is nil!")
            break
        end
        
        -- Direct access instead of unpack (more reliable in sandboxed environments)
        local name = config[1]
        local texture_name = config[2]
        local duration = config[3]
        local dirs = config[4]
        local frames = config[5]
        
        print("[PLAYER_CORE_MOD DEBUG] Config " .. i .. ": name=" .. tostring(name))
        
        -- Create a simplified animation structure with safety checks
        player_data.animations[name] = {
            texture_name = texture_name,
            duration = duration > 0 and duration or 1.0,  -- Ensure positive duration
            direction_count = dirs,
            frame_count = frames > 0 and frames or 1,     -- Ensure positive frame count
            currentTime = 0,
            width = 64,
            height = 64
        }
        print("[PLAYER_CORE_MOD] " .. name .. " animation configured")
    end
    print("[PLAYER_CORE_MOD DEBUG] Animation loop completed")
    
    -- Check if we have doge fallback (but don't load it yet)
    player_data.has_fallback = true
    
    -- Set default animation
    player_data.current_animation_name = "idle"
    player_data.current_animation = player_data.animations.idle
    
    -- Safety check
    if not player_data.current_animation then
        print("[PLAYER_CORE_MOD ERROR] Failed to set initial animation!")
        print("[PLAYER_CORE_MOD DEBUG] Available animations:")
        for name, _ in pairs(player_data.animations) do
            print("  - " .. name)
        end
    else
        print("[PLAYER_CORE_MOD] Initial animation set to 'idle' with currentTime=" .. tostring(player_data.current_animation.currentTime))
    end
    
    -- Initialize visual effects data
    player_data.damage_flash_timer = 0
    player_data.footstep_timer = 0
    player_data.footstep_interval = 0.3  -- Time between footstep particles
    
    print("[PLAYER_CORE_MOD] LPC assets initialization complete")
end

-- Update player system
function playerCoreMod.update(dt)
    if not player_data.active or not player_data.body then
        return
    end
    
    -- Debug: Log update calls periodically
    if not player_data.update_counter then player_data.update_counter = 0 end
    player_data.update_counter = player_data.update_counter + 1
    if player_data.update_counter % 60 == 0 then
        print("[PLAYER_CORE_MOD DEBUG] Update call #" .. player_data.update_counter)
    end
    
    -- Check if player is dead
    if player_data.health <= 0 then
        playerCoreMod.handlePlayerDeath()
        return
    end
    
    -- Update player position from physics
    player_data.x, player_data.y = player_data.body:getPosition()
    
    -- Update visual effects
    if mod_config.enable_visual_effects then
        playerCoreMod.updateVisualEffects(dt)
    end
    
    -- Update input state every frame
    playerCoreMod.updateMovementVector()
    
    -- Update dodge system
    playerCoreMod.updateDodgeSystem(dt)
    
    -- Update jump system
    playerCoreMod.updateJumpSystem(dt)
    
    -- Update movement (only if not dodging)
    if not player_data.is_dodging then
        playerCoreMod.updateMovement(dt)
    end
    
    -- Update animations with safety checks
    if player_data.current_animation and type(player_data.current_animation) == "table" then
        -- Safety check for valid dt
        if dt > 0 and dt < 1 then  -- Reasonable frame time (less than 1 second)
            -- Make sure currentTime exists
            if player_data.current_animation.currentTime then
                player_data.current_animation.currentTime = player_data.current_animation.currentTime + dt
            else
                player_data.current_animation.currentTime = 0
            end
            
            -- Use modulo for wrapping to avoid potential infinite subtraction loop
            if player_data.current_animation.duration and player_data.current_animation.duration > 0 then
                if player_data.current_animation.currentTime >= player_data.current_animation.duration then
                    player_data.current_animation.currentTime = player_data.current_animation.currentTime % player_data.current_animation.duration
                end
            else
                -- Reset to 0 if duration is invalid
                player_data.current_animation.currentTime = 0
            end
        end
    end
    
    -- Update animation blending
    if player_data.animation_blend_timer < player_data.animation_blend_duration then
        player_data.animation_blend_timer = player_data.animation_blend_timer + dt
    end
    
    -- Update state timer
    player_data.state_timer = player_data.state_timer + dt
    
    -- Update combat animation timer
    if player_data.combat_animation_timer and player_data.combat_animation_timer > 0 then
        player_data.combat_animation_timer = player_data.combat_animation_timer - dt
        if player_data.combat_animation_timer <= 0 then
            -- Return to previous animation
            player_data.current_animation_name = player_data.previous_animation_name or "idle"
            player_data.current_animation = player_data.animations[player_data.current_animation_name]
            player_data.combat_animation_timer = nil
        end
    end
    
    -- Network synchronization
    if mod_config.enable_networking then
        playerCoreMod.updateNetworkSync(dt)
    end
    
    -- Don't render here - do it in draw function instead
    
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
            player_data.state = MOVEMENT_STATES.IDLE
            playerCoreMod.updateAnimationState()
        end
    end
    
    if player_data.dodge_cooldown_timer > 0 then
        player_data.dodge_cooldown_timer = player_data.dodge_cooldown_timer - dt
    end
    
    -- Check for dodge input (space key)
    if input_state.key_pressed_this_frame["space"] and not player_data.is_dodging and player_data.dodge_cooldown_timer <= 0 then
        -- Get current movement direction for dodge
        local inputX, inputY = 0, 0
        
        if api.input.isKeyDown("a") then inputX = inputX - 1 end
        if api.input.isKeyDown("d") then inputX = inputX + 1 end
        if api.input.isKeyDown("w") then inputY = inputY - 1 end
        if api.input.isKeyDown("s") then inputY = inputY + 1 end
        
        -- If no movement keys, dodge forward based on last facing direction
        if inputX == 0 and inputY == 0 then
            inputX = math.cos(player_data.direction_angle or 0)
            inputY = math.sin(player_data.direction_angle or 0)
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
            player_data.state = MOVEMENT_STATES.DODGING
            playerCoreMod.updateAnimationState()
            
            -- Spawn dodge particles if visual effects enabled
            if mod_config.enable_visual_effects then
                playerCoreMod.spawnDodgeParticles()
            end
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

-- Enhanced acceleration-based movement with state machine
function playerCoreMod.updateMovement(dt)
    if player_data.is_dodging then return end
    
    local moveX = input_state.movement_vector.x
    local moveY = input_state.movement_vector.y
    local isMoving = (moveX ~= 0 or moveY ~= 0)
    local isRunning = input_state.keys_down["lshift"] and mod_config.enable_running
    
    -- Update state machine
    playerCoreMod.updateMovementState(isMoving, isRunning)
    
    -- Calculate target speed based on state
    local target_speed = 0
    if player_data.state == MOVEMENT_STATES.WALKING then
        target_speed = player_data.max_walk_speed
    elseif player_data.state == MOVEMENT_STATES.RUNNING then
        target_speed = player_data.max_run_speed
    end
    
    -- Get current velocity
    local vx, vy = player_data.body:getLinearVelocity()
    
    if isMoving then
        -- Calculate target velocity
        local target_vx = moveX * target_speed
        local target_vy = moveY * target_speed
        
        -- Apply acceleration towards target velocity
        local accel_rate = player_data.acceleration * dt
        local new_vx = vx + (target_vx - vx) * math.min(accel_rate / target_speed, 1)
        local new_vy = vy + (target_vy - vy) * math.min(accel_rate / target_speed, 1)
        
        player_data.body:setLinearVelocity(new_vx, new_vy)
        
        -- Update direction
        player_data.direction = calculateDirection(moveX, moveY)
        player_data.direction_angle = math.atan2(moveY, moveX)
        
    else
        -- Apply deceleration when not moving
        local decel_rate = player_data.deceleration * dt
        local speed = math.sqrt(vx * vx + vy * vy)
        
        if speed > 0 then
            local decel_factor = math.max(0, speed - decel_rate) / speed
            local new_vx = vx * decel_factor
            local new_vy = vy * decel_factor
            
            -- Stop completely if moving very slowly
            if math.abs(new_vx) < 5 and math.abs(new_vy) < 5 then
                new_vx, new_vy = 0, 0
            end
            
            player_data.body:setLinearVelocity(new_vx, new_vy)
        end
    end
    
    -- Update stored velocity for state tracking
    player_data.velocity.x, player_data.velocity.y = player_data.body:getLinearVelocity()
end

-- Add visual effects update function
function playerCoreMod.updateVisualEffects(dt)
    -- Update damage flash timer
    if player_data.damage_flash_timer > 0 then
        player_data.damage_flash_timer = player_data.damage_flash_timer - dt
    end
    
    -- Update footstep particles for movement
    if (player_data.state == MOVEMENT_STATES.WALKING or player_data.state == MOVEMENT_STATES.RUNNING) then
        player_data.footstep_timer = player_data.footstep_timer + dt
        
        if player_data.footstep_timer >= player_data.footstep_interval then
            player_data.footstep_timer = 0
            playerCoreMod.spawnFootstepParticle()
        end
    end
end

-- Spawn footstep particle
function playerCoreMod.spawnFootstepParticle()
    -- Calculate footstep position based on direction
    local offset_x = -math.cos(player_data.direction_angle) * 10
    local offset_y = -math.sin(player_data.direction_angle) * 10
    
    api.renderer.addToQueue("effects", {
        type = "particle",
        x = player_data.x + offset_x,
        y = player_data.y + offset_y,
        color = {0.5, 0.4, 0.3, 0.3},  -- Dusty brown
        lifetime = 0.5,
        scale = 0.5,
        fade_out = true
    })
end

-- Spawn dodge particles
function playerCoreMod.spawnDodgeParticles()
    for i = 1, 5 do
        local angle = (i / 5) * math.pi * 2
        local speed = 50 + math.random() * 50
        
        api.renderer.addToQueue("effects", {
            type = "particle",
            x = player_data.x,
            y = player_data.y,
            velocity_x = math.cos(angle) * speed,
            velocity_y = math.sin(angle) * speed,
            color = {0.8, 0.8, 1.0, 0.6},  -- Light blue
            lifetime = 0.4,
            scale = 0.8,
            fade_out = true
        })
    end
end

-- Update jump system
function playerCoreMod.updateJumpSystem(dt)
    -- Update jump timer
    if player_data.is_jumping then
        player_data.jump_timer = player_data.jump_timer - dt
        if player_data.jump_timer <= 0 then
            player_data.is_jumping = false
            player_data.has_double_jumped = false
            
            -- Return to previous state
            if input_state.movement_vector.x ~= 0 or input_state.movement_vector.y ~= 0 then
                player_data.state = input_state.keys_down["lshift"] and MOVEMENT_STATES.RUNNING or MOVEMENT_STATES.WALKING
            else
                player_data.state = MOVEMENT_STATES.IDLE
            end
            playerCoreMod.updateAnimationState()
        end
    end
    
    -- Check for jump input (future implementation)
    -- Currently jumping is not bound to any key in the PRD
end

-- Update movement state machine
function playerCoreMod.updateMovementState(isMoving, isRunning)
    local new_state = player_data.state
    
    -- Don't change state if dodging or jumping
    if player_data.is_dodging then
        return
    end
    
    if not isMoving then
        new_state = MOVEMENT_STATES.IDLE
    elseif isMoving and isRunning then
        new_state = MOVEMENT_STATES.RUNNING
    elseif isMoving then
        new_state = MOVEMENT_STATES.WALKING
    end
    
    -- Handle state transitions
    if new_state ~= player_data.state then
        player_data.previous_state = player_data.state
        player_data.state = new_state
        player_data.state_timer = 0
        
        -- Debug state changes
        print("[PLAYER_CORE_MOD] State: " .. player_data.state .. ", Direction: " .. player_data.direction)
        
        -- Trigger animation change
        playerCoreMod.updateAnimationState()
    end
end

-- Update animation based on current state
function playerCoreMod.updateAnimationState()
    local new_animation = "idle"
    
    if player_data.state == MOVEMENT_STATES.IDLE then
        new_animation = "idle"
    elseif player_data.state == MOVEMENT_STATES.WALKING then
        new_animation = "walk"
    elseif player_data.state == MOVEMENT_STATES.RUNNING then
        new_animation = "run"
    elseif player_data.state == MOVEMENT_STATES.DODGING then
        new_animation = "dodge" -- Use dodge animation if available
        if not player_data.animations.dodge then
            new_animation = "jump" -- Fallback to jump
        end
    elseif player_data.state == MOVEMENT_STATES.JUMPING then
        new_animation = "jump"
    end
    
    -- Only change animation if different
    if new_animation ~= player_data.current_animation_name then
        player_data.current_animation_name = new_animation
        player_data.current_animation = player_data.animations[new_animation]
        
        -- Reset animation timer for smooth transitions
        if player_data.current_animation then
            player_data.current_animation.currentTime = 0
        end
        
        player_data.animation_blend_timer = 0
    end
end

-- Render player
function playerCoreMod.renderPlayer()
    if not player_data.active then return end
    
    -- Debug: log player position every 60 frames
    -- if not player_data.debug_counter then player_data.debug_counter = 0 end
    -- player_data.debug_counter = player_data.debug_counter + 1
    -- if player_data.debug_counter % 60 == 0 then
    --     print("[PLAYER_CORE_MOD] Player rendering at: " .. player_data.x .. ", " .. player_data.y)
    -- end
    
    -- Calculate color tint for damage flash
    local color = {1, 1, 1, 1}
    if player_data.damage_flash_timer > 0 then
        -- White flash effect
        local flash_intensity = player_data.damage_flash_timer / mod_config.damage_flash_duration
        color = {1, 1, 1, 1}  -- Full white during flash
    end
    
    -- Enhanced LPC sprite rendering with 8-directional support
    if player_data.current_animation then
        local anim = player_data.current_animation
        local texture_name = anim.texture_name
        
        -- Get texture to create quad
        local texture = api.renderer.getTexture(texture_name)
        if texture then
            -- Calculate quad position for current frame and direction
            local frame_index = getCurrentAnimationFrame(anim, player_data.direction) or 1
            
            -- LPC row mapping for directions
            local row_mapping = {
                down = 0, left = 1, right = 2, up = 3,
                down_left = 4, down_right = 5, up_left = 6, up_right = 7
            }
            
            local row = row_mapping[player_data.direction] or 0
            local col = (frame_index - 1) % anim.frame_count
            
            -- Create quad for current frame
            local quad = api.renderer.createQuad(
                col * 64, row * 64,  -- x, y position in sprite sheet
                64, 64,              -- width, height of frame
                texture:getDimensions()
            )
            
            api.renderer.addToQueue("world", {
                type = "sprite_quad",
                texture_name = texture_name,
                quad = quad,
                x = player_data.x,
                y = player_data.y,
                rotation = 0,
                scale_x = player_data.scale,
                scale_y = player_data.scale,
                offset_x = 32, -- Half of 64 (LPC sprite width)
                offset_y = 32, -- Half of 64 (LPC sprite height)
                sort_y = player_data.y,
                active = true,
                color = color
            })
        else
            -- Fallback to simple sprite if texture not loaded
            api.renderer.addToQueue("world", {
                type = "sprite",
                texture_name = texture_name,
                x = player_data.x,
                y = player_data.y,
                rotation = 0,
                scale_x = player_data.scale,
                scale_y = player_data.scale,
                offset_x = 32,
                offset_y = 32,
                sort_y = player_data.y,
                active = true,
                color = color
            })
        end
    elseif player_data.fallback_texture then
        -- Ultimate fallback to doge texture
        api.renderer.addToQueue("world", {
            type = "sprite",
            texture_name = "doge",
            x = player_data.x,
            y = player_data.y,
            rotation = 0,
            scale_x = player_data.scale,
            scale_y = player_data.scale,
            offset_x = -150,
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
    
    -- Check godmode from console
    if cmdn and cmdn.isGodmodeEnabled and cmdn.isGodmodeEnabled("local") then
        print("[PLAYER_CORE_MOD] Godmode active - damage blocked: " .. damage)
        return
    end
    
    player_data.health = math.max(0, player_data.health - damage)
    
    -- Trigger damage flash effect
    if mod_config.enable_visual_effects then
        player_data.damage_flash_timer = mod_config.damage_flash_duration
    end
    
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

-- Teleport player to specific coordinates
function playerCoreMod.teleportPlayer(x, y)
    if player_data.body and not player_data.body:isDestroyed() then
        player_data.body:setPosition(x, y)
        player_data.x = x
        player_data.y = y
        print("[PLAYER_CORE_MOD] Teleported player to (" .. x .. ", " .. y .. ")")
        
        -- Sync teleport over network
        if mod_config.enable_networking then
            api.network.sendToAll({
                action = "player_teleport",
                x = x,
                y = y
            }, "player_core_mod")
        end
    end
end

-- Network synchronization
function playerCoreMod.updateNetworkSync(dt)
    player_data.last_sync_time = player_data.last_sync_time + dt
    
    if player_data.last_sync_time >= player_data.sync_interval then
        -- Only send delta updates for changed properties
        local sync_data = {
            action = "player_sync",
            client_id = api.network.getLocalClientId and api.network.getLocalClientId() or "local"
        }
        
        -- Track what changed
        local has_changes = false
        
        -- Position changes
        if not player_data.last_synced_x or math.abs(player_data.x - player_data.last_synced_x) > 1 or
           not player_data.last_synced_y or math.abs(player_data.y - player_data.last_synced_y) > 1 then
            sync_data.x = player_data.x
            sync_data.y = player_data.y
            player_data.last_synced_x = player_data.x
            player_data.last_synced_y = player_data.y
            has_changes = true
        end
        
        -- Health changes
        if not player_data.last_synced_health or player_data.health ~= player_data.last_synced_health then
            sync_data.health = player_data.health
            player_data.last_synced_health = player_data.health
            has_changes = true
        end
        
        -- Animation/state changes
        if not player_data.last_synced_animation or player_data.current_animation_name ~= player_data.last_synced_animation then
            sync_data.animation = player_data.current_animation_name
            sync_data.direction = player_data.direction
            player_data.last_synced_animation = player_data.current_animation_name
            has_changes = true
        end
        
        -- State changes
        if not player_data.last_synced_state or player_data.state ~= player_data.last_synced_state then
            sync_data.state = player_data.state
            player_data.last_synced_state = player_data.state
            has_changes = true
        end
        
        -- Only send if something changed
        if has_changes then
            api.network.sendToAll(sync_data, "player_core_mod")
        end
        
        player_data.last_sync_time = 0
    end
end

-- Handle network messages
function playerCoreMod.handleNetworkMessage(data)
    if data.action == "player_sync" then
        -- Only process updates from other clients
        if data.client_id and data.client_id ~= (api.network.getLocalClientId and api.network.getLocalClientId() or "local") then
            -- Apply delta updates with client-side prediction
            -- This is simplified - a full implementation would include interpolation
            print("[PLAYER_CORE_MOD] Received player sync from client: " .. (data.client_id or "unknown"))
        end
    elseif data.action == "player_damage" then
        -- Handle remote player damage
        print("[PLAYER_CORE_MOD] Remote player took damage: " .. data.damage)
    elseif data.action == "player_death" then
        -- Handle remote player death
        print("[PLAYER_CORE_MOD] Remote player died at " .. data.x .. ", " .. data.y)
    elseif data.action == "player_teleport" then
        -- Handle remote player teleport
        print("[PLAYER_CORE_MOD] Remote player teleported to " .. data.x .. ", " .. data.y)
    end
end

-- Draw function
function playerCoreMod.draw()
    -- Add player to render queue during draw phase
    if player_data.active then
        playerCoreMod.renderPlayer()
    end
end

-- Cleanup
function playerCoreMod.cleanup()
    if player_data.body and not player_data.body:isDestroyed() then
        player_data.body:destroy()
    end
    
    player_data = {}
    input_state = {keys_down = {}, mouse_pressed = false, mouse_x = 0, mouse_y = 0}
    
    print("[PLAYER_CORE_MOD] Cleanup complete * * *")
end

-- Play combat animation
function playerCoreMod.playCombatAnimation(animation_name)
    if not player_data.animations[animation_name] then
        print("[PLAYER_CORE_MOD] Combat animation not found: " .. animation_name)
        return
    end
    
    -- Override current animation temporarily
    player_data.previous_animation_name = player_data.current_animation_name
    player_data.current_animation_name = animation_name
    player_data.current_animation = player_data.animations[animation_name]
    
    if player_data.current_animation then
        player_data.current_animation.currentTime = 0
    end
    
    -- Set a timer to return to previous animation
    player_data.combat_animation_timer = player_data.current_animation and player_data.current_animation.duration or 0.5
end

-- Get player state for saving
function playerCoreMod.getPlayerState()
    return {
        x = player_data.x,
        y = player_data.y,
        health = player_data.health,
        max_health = player_data.max_health,
        state = player_data.state,
        direction = player_data.direction,
        animation = player_data.current_animation_name
    }
end

-- Restore player state from save data
function playerCoreMod.restorePlayerState(save_data)
    if not save_data then return end
    
    if save_data.x and save_data.y then
        playerCoreMod.teleportPlayer(save_data.x, save_data.y)
    end
    
    if save_data.health then
        player_data.health = save_data.health
    end
    
    if save_data.max_health then
        player_data.max_health = save_data.max_health
    end
    
    if save_data.state then
        player_data.state = save_data.state
    end
    
    if save_data.direction then
        player_data.direction = save_data.direction
    end
    
    if save_data.animation and player_data.animations[save_data.animation] then
        player_data.current_animation_name = save_data.animation
        player_data.current_animation = player_data.animations[save_data.animation]
    end
    
    print("[PLAYER_CORE_MOD] Player state restored from save")
end

-- Export PlayerCore Function
playerCoreMod.exports = {
    getPosition = playerCoreMod.getPosition,
    getHealth = playerCoreMod.getHealth,
    getAnimation = playerCoreMod.getAnimation,
    damagePlayer = playerCoreMod.damagePlayer,
    applyKnockback = playerCoreMod.applyKnockback,
    handleCollision = playerCoreMod.handleCollision,
    teleportPlayer = playerCoreMod.teleportPlayer,
    playCombatAnimation = playerCoreMod.playCombatAnimation,
    getPlayerState = playerCoreMod.getPlayerState,
    restorePlayerState = playerCoreMod.restorePlayerState,
    getDirection = function() return player_data.direction end,
    getVelocity = function() return player_data.velocity end,
    isRunning = function() return player_data.state == MOVEMENT_STATES.RUNNING end,
    isDodging = function() return player_data.is_dodging end
}

return playerCoreMod