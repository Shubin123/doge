-- Player Core Mod - Enhanced and Stable Version
-- Combines the best features of both implementations with compatibility fixes
-- Features: Acceleration-based movement, 8-directional animations, dodge mechanics, networking, and data persistence

local playerCoreMod = {}

-- Mod state
local player_data = {}
local mod_config = {}
local api = nil

-- Animation system with directional support
local animation_system = {
    -- Structure: animation_system[STATE][DIRECTION]
    -- e.g., animation_system["WALKING"]["up_right"]
}

-- Input state tracking
local input_state = {
    direction_vector = { x = 0, y = 0 },
    is_running = false,
    dodge_pressed = false,
    keys_down = {}
}

-- Player entity template
local PLAYER_TEMPLATE = {
    health = 100,
    max_health = 100,
    scale = 0.8,
    
    -- Movement
    state = "IDLE", -- State machine: IDLE, WALKING, RUNNING, DODGING
    max_speed_walk = 100,
    max_speed_run = 200,
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
    current_animation_set = nil,
    facing_direction_str = "down", -- e.g., "up", "down", "left", "right", "up_left", etc.
    
    -- UX Feedback
    damage_flash_timer = 0,
    damage_flash_duration = 0.2,
    
    -- Physics
    collision_group = -1
}

-- Animation creation helper
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
            if frameCount >= framesToUse then break end
        end
        if frameCount >= framesToUse then break end
    end
    
    animation.duration = duration or 1
    animation.currentTime = 0
    return animation
end

-- Initialize the mod
function playerCoreMod.init(mod_api)
    print(" * [PLAYER_CORE_MOD] Initializing Enhanced Player Core System")
    
    api = mod_api
    
    -- Load configuration
    mod_config = {
        player_health = 100,
        player_max_speed_walk = 100,
        player_max_speed_run = 200,
        player_acceleration = 2000,
        player_friction = 0.85,
        dodge_speed = 300,
        dodge_duration = 0.2,
        dodge_cooldown = 1.0,
        player_scale = 0.8,
        collision_group = -1,
        enable_networking = true
    }
    
    -- Register input handlers
    api.input.registerKeyHandler("w", function() input_state.keys_down["w"] = true end)
    api.input.registerKeyHandler("a", function() input_state.keys_down["a"] = true end)
    api.input.registerKeyHandler("s", function() input_state.keys_down["s"] = true end)
    api.input.registerKeyHandler("d", function() input_state.keys_down["d"] = true end)
    api.input.registerKeyHandler("shift", function() input_state.keys_down["shift"] = true end)
    api.input.registerKeyHandler("space", function() input_state.dodge_pressed = true end)
    
    -- Register key release handlers
    api.input.registerKeyReleaseHandler("w", function() input_state.keys_down["w"] = nil end)
    api.input.registerKeyReleaseHandler("a", function() input_state.keys_down["a"] = nil end)
    api.input.registerKeyReleaseHandler("s", function() input_state.keys_down["s"] = nil end)
    api.input.registerKeyReleaseHandler("d", function() input_state.keys_down["d"] = nil end)
    api.input.registerKeyReleaseHandler("shift", function() input_state.keys_down["shift"] = nil end)
    
    -- Register network handler
    if mod_config.enable_networking then
        api.network.registerMessageHandler("player_core_mod", playerCoreMod.handleNetworkMessage)
    end
    
    -- Initialize player
    playerCoreMod.createPlayer()
    
    -- Load player state from disk
    playerCoreMod.loadPlayerData()
    
    print("[PLAYER_CORE_MOD] Player system initialized!")
end

-- Create the player entity
function playerCoreMod.createPlayer()
    local world = api.physics.getWorld()
    if not world then
        print("[PLAYER_CORE_MOD] Warning: Physics world not available")
        return
    end
    
    local game_width, game_height = api.renderer.getGameDimensions()
    
    -- Create physics body
    local body = api.physics.createBody(game_width / 2, game_height / 2, "dynamic")
    body:setLinearDamping(0) -- Handle friction/deceleration manually
    body:setFixedRotation(true)
    
    local shape = api.physics.createCircleShape(10)
    local fixture = api.physics.createFixture(body, shape, 1.0)
    
    -- Initialize player data from the template
    player_data = {}
    for k, v in pairs(PLAYER_TEMPLATE) do player_data[k] = v end

    player_data.active = true
    player_data.body = body
    player_data.fixture = fixture
    player_data.x = game_width / 2
    player_data.y = game_height / 2
    
    -- Add collision metadata
    fixture:setUserData({
        type = "player",
        mod = "player_core_mod",
        id = "player"
    })
    
    -- Load textures and animations
    playerCoreMod.initializeAssets()
    
    print("[PLAYER_CORE_MOD] Player entity created successfully")
end

-- Initialize player assets with fallback
function playerCoreMod.initializeAssets()
    print("[PLAYER_CORE_MOD] Loading animations...")
    local directions = {"up", "up_right", "right", "down_right", "down", "down_left", "left", "up_left"}
    
    -- Try to load LPC animations or use fallback
    local loaded_any = false
    
    -- Fallback animation sets
    local fallback_animations = {
        IDLE = {name="idle", texture_path="../gfx/fallback/idle.png", width=64, height=64, frames=1, duration=1.0},
        WALKING = {name="walk", texture_path="../gfx/fallback/walk.png", width=64, height=64, frames=4, duration=0.8},
        RUNNING = {name="run", texture_path="../gfx/fallback/run.png", width=64, height=64, frames=6, duration=0.6},
        DODGING = {name="dodge", texture_path="../gfx/fallback/dodge.png", width=64, height=64, frames=5, duration=0.2}
    }
    
    for state, anim_data in pairs(fallback_animations) do
        animation_system[state] = {}
        local texture = api.utils.loadTexture(anim_data.name, anim_data.texture_path)
        
        if texture then
            loaded_any = true
            for _, dir in ipairs(directions) do
                animation_system[state][dir] = createAnimation(
                    texture, 
                    anim_data.width, 
                    anim_data.height, 
                    anim_data.duration, 
                    anim_data.frames
                )
            end
        else
            print(string.format("[PLAYER_CORE_MOD] ERROR: Failed to load texture at %s", anim_data.texture_path))
        end
    end
    
    if not loaded_any then
        -- Ultimate fallback: create placeholder textures
        print("[PLAYER_CORE_MOD] Creating placeholder animations")
        for state, anim_data in pairs(fallback_animations) do
            animation_system[state] = {}
            local placeholder = api.utils.createPlaceholderTexture(64, 64, state == "IDLE" and {0.2, 0.8, 0.2} or {0.8, 0.2, 0.2})
            for _, dir in ipairs(directions) do
                animation_system[state][dir] = createAnimation(placeholder, 64, 64, anim_data.duration, anim_data.frames)
            end
        end
    end
    
    -- Set initial animation
    player_data.current_animation_set = animation_system["IDLE"]["down"]
    
    print("[PLAYER_CORE_MOD] Animations loaded.")
end

-- Main update loop
function playerCoreMod.update(dt)
    if not player_data.active or not player_data.body then return end

    -- Reset input state
    input_state.dodge_pressed = false
    
    -- 1. Handle Input
    playerCoreMod.updateInput()

    -- 2. Update State Machine
    playerCoreMod.updateState(dt)

    -- 3. Update Movement
    playerCoreMod.updateMovement(dt)

    -- 4. Update Animations
    playerCoreMod.updateAnimation(dt)
    
    -- 5. Update timers
    playerCoreMod.updateTimers(dt)
    
    -- 6. Network Synchronization
    playerCoreMod.updateNetworkSync(dt)

    -- Update position from physics
    player_data.x, player_data.y = player_data.body:getPosition()
end

-- Process input
function playerCoreMod.updateInput()
    input_state.direction_vector = { x = 0, y = 0 }
    input_state.is_running = input_state.keys_down["shift"] or false

    if input_state.keys_down["w"] then input_state.direction_vector.y = -1 end
    if input_state.keys_down["s"] then input_state.direction_vector.y = 1 end
    if input_state.keys_down["a"] then input_state.direction_vector.x = -1 end
    if input_state.keys_down["d"] then input_state.direction_vector.x = 1 end

    -- Normalize diagonal movement
    local len = math.sqrt(input_state.direction_vector.x^2 + input_state.direction_vector.y^2)
    if len > 0 then
        input_state.direction_vector.x = input_state.direction_vector.x / len
        input_state.direction_vector.y = input_state.direction_vector.y / len
    end
end

-- Manage player state transitions
function playerCoreMod.updateState(dt)
    -- Dodge state has priority
    if input_state.dodge_pressed and player_data.state ~= "DODGING" and player_data.dodge_cooldown_timer <= 0 then
        player_data.state = "DODGING"
        player_data.is_dodging = true
        player_data.dodge_timer = player_data.dodge_duration
        player_data.dodge_cooldown_timer = player_data.dodge_cooldown
        
        -- Dodge in movement direction or facing direction if not moving
        if input_state.direction_vector.x == 0 and input_state.direction_vector.y == 0 then
            if player_data.facing_direction_str == "up" then
                player_data.dodge_direction = { x = 0, y = -1 }
            elseif player_data.facing_direction_str == "down" then
                player_data.dodge_direction = { x = 0, y = 1 }
            elseif player_data.facing_direction_str == "left" then
                player_data.dodge_direction = { x = -1, y = 0 }
            elseif player_data.facing_direction_str == "right" then
                player_data.dodge_direction = { x = 1, y = 0 }
            else
                -- Default to down direction
                player_data.dodge_direction = { x = 0, y = 1 }
            end
        else
            player_data.dodge_direction = { 
                x = input_state.direction_vector.x, 
                y = input_state.direction_vector.y 
            }
        end
        return
    end
    
    -- Transition out of dodge state
    if player_data.state == "DODGING" and not player_data.is_dodging then
        player_data.state = "IDLE"
    end

    -- Regular state transitions
    if player_data.state ~= "DODGING" then
        local is_moving = (input_state.direction_vector.x ~= 0 or input_state.direction_vector.y ~= 0)
        if is_moving then
            player_data.state = input_state.is_running and "RUNNING" or "WALKING"
        else
            player_data.state = "IDLE"
        end
    end
end

-- Movement system
function playerCoreMod.updateMovement(dt)
    if player_data.state == "DODGING" and player_data.is_dodging then
        local dodgeVX = player_data.dodge_direction.x * player_data.dodge_speed
        local dodgeVY = player_data.dodge_direction.y * player_data.dodge_speed
        player_data.body:setLinearVelocity(dodgeVX, dodgeVY)
        return
    end

    local current_max_speed = (player_data.state == "RUNNING") and player_data.max_speed_run or player_data.max_speed_walk
    local target_vx = input_state.direction_vector.x * current_max_speed
    local target_vy = input_state.direction_vector.y * current_max_speed
    
    local current_vx, current_vy = player_data.body:getLinearVelocity()
    local new_vx, new_vy
    
    local is_moving = (input_state.direction_vector.x ~= 0 or input_state.direction_vector.y ~= 0)

    if is_moving then
        -- Accelerate towards target velocity
        new_vx = current_vx + (target_vx - current_vx) * player_data.acceleration * dt * 0.1
        new_vy = current_vy + (target_vy - current_vy) * player_data.acceleration * dt * 0.1
    else
        -- Apply friction to decelerate
        local friction_factor = math.pow(1.0 - player_data.friction, dt * 60)
        new_vx = current_vx * friction_factor
        new_vy = current_vy * friction_factor
        -- Stop completely if slow enough
        if math.abs(new_vx) < 1 and math.abs(new_vy) < 1 then
            new_vx, new_vy = 0, 0
        end
    end
    
    -- Clamp to max speed
    local speed = math.sqrt(new_vx^2 + new_vy^2)
    if speed > current_max_speed then
        local scale = current_max_speed / speed
        new_vx = new_vx * scale
        new_vy = new_vy * scale
    end
    
    player_data.body:setLinearVelocity(new_vx, new_vy)
end

-- Update animation based on state and direction
function playerCoreMod.updateAnimation(dt)
    -- Determine facing direction from movement vector
    local vec = input_state.direction_vector
    if vec.x ~= 0 or vec.y ~= 0 then
        if vec.y < -0.5 then
            player_data.facing_direction_str = "up"
        elseif vec.y > 0.5 then
            player_data.facing_direction_str = "down"
        end
        
        if vec.x < -0.5 then
            if player_data.facing_direction_str == "up" then 
                player_data.facing_direction_str = "up_left"
            elseif player_data.facing_direction_str == "down" then 
                player_data.facing_direction_str = "down_left"
            else 
                player_data.facing_direction_str = "left" 
            end
        elseif vec.x > 0.5 then
            if player_data.facing_direction_str == "up" then 
                player_data.facing_direction_str = "up_right"
            elseif player_data.facing_direction_str == "down" then 
                player_data.facing_direction_str = "down_right"
            else 
                player_data.facing_direction_str = "right" 
            end
        end
    end

    -- Select the correct animation set
    local desired_anim_set = animation_system[player_data.state][player_data.facing_direction_str]

    -- Switch to new animation set
    if player_data.current_animation_set ~= desired_anim_set then
        player_data.current_animation_set = desired_anim_set
        if player_data.current_animation_set then
            player_data.current_animation_set.currentTime = 0
        end
    end
    
    -- Advance animation
    if player_data.current_animation_set then
        local anim = player_data.current_animation_set
        anim.currentTime = anim.currentTime + dt
        if anim.currentTime >= anim.duration then
            anim.currentTime = anim.currentTime - anim.duration
        end
    end
end

-- Update cooldowns and timers
function playerCoreMod.updateTimers(dt)
    if player_data.dodge_timer > 0 then
        player_data.dodge_timer = player_data.dodge_timer - dt
        if player_data.dodge_timer <= 0 then
            player_data.is_dodging = false
            player_data.body:setLinearVelocity(0, 0)
        end
    end
    
    if player_data.dodge_cooldown_timer > 0 then
        player_data.dodge_cooldown_timer = player_data.dodge_cooldown_timer - dt
    end
    
    if player_data.damage_flash_timer > 0 then
        player_data.damage_flash_timer = player_data.damage_flash_timer - dt
    end
end

-- Render the player
function playerCoreMod.renderPlayer()
    if not player_data.active or not player_data.current_animation_set then return end
    
    local anim = player_data.current_animation_set
    local spriteNum = math.floor(anim.currentTime / anim.duration * #anim.quads) + 1
    spriteNum = math.min(spriteNum, #anim.quads)
    
    -- Damage flash effect
    local r, g, b, a = 1, 1, 1, 1
    if player_data.damage_flash_timer > 0 then
        -- Flash between white and normal color
        local flash_factor = math.sin(player_data.damage_flash_timer * 30) * 0.5 + 0.5
        r = 1
        g = 1 - flash_factor * 0.5
        b = 1 - flash_factor * 0.5
    end

    api.renderer.addToQueue("world", {
        type = "sprite_quad",
        texture_name = anim.spriteSheet:getDebugName(),
        quad = anim.quads[spriteNum],
        x = player_data.x,
        y = player_data.y,
        rotation = 0,
        scale_x = player_data.scale,
        scale_y = player_data.scale,
        offset_x = 32, -- Center horizontally
        offset_y = 48, -- Adjusted for ground alignment
        sort_y = player_data.y,
        color = {r, g, b, a}
    })
    
    -- Render health bar
    if player_data.health < player_data.max_health then
        playerCoreMod.renderHealthBar()
    end
end

-- Render health bar
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
        color = health_percent > 0.5 and {0.2, 0.8, 0.2, 0.9} or {0.8, 0.2, 0.2, 0.9}
    })
end

-- Draw function
function playerCoreMod.draw()
    if player_data.active then
        playerCoreMod.renderPlayer()
    end
end

-- Save player data
function playerCoreMod.savePlayerData()
    print("[PLAYER_CORE_MOD] Saving player data...")
    local data_to_save = {
        position = { x = player_data.x, y = player_data.y },
        health = player_data.health,
        state = player_data.state,
        facing_direction = player_data.facing_direction_str
    }
    api.data.save("player_save.json", data_to_save)
    print("[PLAYER_CORE_MOD] Data saved.")
end

-- Load player data
function playerCoreMod.loadPlayerData()
    print("[PLAYER_CORE_MOD] Loading player data...")
    local saved_data = api.data.load("player_save.json")
    if saved_data then
        player_data.body:setPosition(saved_data.position.x, saved_data.position.y)
        player_data.health = saved_data.health or player_data.health
        player_data.state = saved_data.state or "IDLE"
        player_data.facing_direction_str = saved_data.facing_direction or "down"
        print("[PLAYER_CORE_MOD] Data loaded.")
    else
        print("[PLAYER_CORE_MOD] No save data found.")
    end
end

-- Network synchronization
function playerCoreMod.updateNetworkSync(dt)
    -- Placeholder implementation
    -- In a real implementation, you'd send state changes to the server
end

function playerCoreMod.handleNetworkMessage(data)
    -- Handle network messages
    if data.action == "server_correction" then
        player_data.body:setPosition(data.x, data.y)
    elseif data.action == "player_damage" then
        player_data.health = data.new_health
        player_data.damage_flash_timer = player_data.damage_flash_duration
    end
end

-- Apply damage to player
function playerCoreMod.damagePlayer(damage, source)
    if not player_data.active then return end
    player_data.health = math.max(0, player_data.health - damage)
    player_data.damage_flash_timer = player_data.damage_flash_duration
    print("[PLAYER_CORE_MOD] Player took " .. damage .. " damage. Health: " .. player_data.health)
    
    if player_data.health <= 0 then
        playerCoreMod.handlePlayerDeath()
    end
end

-- Handle player death
function playerCoreMod.handlePlayerDeath()
    print("[PLAYER_CORE_MOD] Player died!")
    player_data.active = false
    -- Additional death handling would go here
end

-- Apply knockback
function playerCoreMod.applyKnockback(direction, force)
    if not player_data.body then return end
    
    local vx, vy = player_data.body:getLinearVelocity()
    local knockbackVx = direction.x * force
    local knockbackVy = direction.y * force
    
    player_data.body:setLinearVelocity(vx + knockbackVx, vy + knockbackVy)
    print("[PLAYER_CORE_MOD] Applied knockback: " .. force)
end

-- Teleport player
function playerCoreMod.teleportPlayer(x, y)
    if player_data.body then
        player_data.body:setPosition(x, y)
        player_data.x = x
        player_data.y = y
        print("[PLAYER_CORE_MOD] Teleported player to (" .. x .. ", " .. y .. ")")
    end
end

-- Handle collisions
function playerCoreMod.handleCollision(fixture_a, fixture_b, contact)
    local user_data = fixture_a:getUserData() or fixture_b:getUserData()
    
    if user_data and user_data.type == "player" then
        print("[PLAYER_CORE_MOD] Player collision detected")
        -- Collision handling logic would go here
    end
end

-- Cleanup
function playerCoreMod.cleanup()
    playerCoreMod.savePlayerData()
    if player_data.body then
        player_data.body:destroy()
    end
    player_data = {}
    print("[PLAYER_CORE_MOD] Cleanup complete.")
end

-- Export PlayerCore Functions
playerCoreMod.exports = {
    getPosition = function() return player_data.x, player_data.y end,
    getHealth = function() return player_data.health, player_data.max_health end,
    damagePlayer = playerCoreMod.damagePlayer,
    teleportPlayer = playerCoreMod.teleportPlayer,
    applyKnockback = playerCoreMod.applyKnockback,
    handleCollision = playerCoreMod.handleCollision
}

return playerCoreMod