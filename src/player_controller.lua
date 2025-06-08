local player_controller = {}
local character_save_system = require("character_save_system")

-- Try to load particle system (may not exist in all builds)
local particle_system = nil
pcall(function()
    particle_system = require("particle_system")
end)

-- Player controller state
local controller = {
    -- Character data
    character_data = nil,
    current_character_id = nil,
    
    -- Physics
    body = nil,
    shape = nil,
    fixture = nil,
    
    -- Movement settings
    movement = {
        max_speed = 100,
        acceleration = 2000,
        friction = 0.85,
        dodge_speed = 300,
        dodge_duration = 0.2,
        dodge_cooldown = 1.0
    },
    
    -- Animation state
    animation = {
        current_state = "idle", -- idle, walk, dash, attack
        facing_direction = "down", -- down, up, left, right
        current_animation = nil,
        time = 0
    },
    
    -- Dodge/dash system
    dodge = {
        is_dodging = false,
        timer = 0,
        cooldown_timer = 0,
        direction = {x = 0, y = 0}
    },
    
    -- Input state
    input = {
        move_x = 0,
        move_y = 0,
        dodge_pressed = false,
        attack_pressed = false
    },
    
    -- Player state
    health = 100,
    max_health = 100,
    alive = true,
    respawn_timer = 0
}

-- Initialize the player controller
function player_controller.initialize()
    character_save_system.initialize()
    print("Player controller initialized")
end

-- Create a new player instance with a specific character
function player_controller.create_player(world, character_id, x, y)
    assert(world, "World physics object required")
    assert(character_id, "Character ID required")
    
    print("DEBUG: Loading character with ID: " .. tostring(character_id))
    
    -- Load character data
    local character_data = character_save_system.load_character(character_id)
    if not character_data then
        print("ERROR: Character not found: " .. tostring(character_id))
        error("Failed to load character: " .. character_id)
    end
    
    print("DEBUG: Loaded character: " .. character_data.name .. " (class: " .. character_data.class .. ")")
    
    -- Clean up existing physics body
    if controller.body and not controller.body:isDestroyed() then
        controller.body:destroy()
    end
    
    -- Create physics body
    controller.body = love.physics.newBody(world, x or 400, y or 300, "dynamic")
    controller.shape = love.physics.newCircleShape(12) -- Slightly larger for better collision
    controller.fixture = love.physics.newFixture(controller.body, controller.shape)
    controller.fixture:setGroupIndex(-1) -- Prevent collision with own projectiles
    
    -- Set character data
    controller.character_data = character_data
    controller.current_character_id = character_id
    
    -- Update stats from character
    controller.health = character_data.stats.health
    controller.max_health = character_data.stats.max_health
    controller.movement.max_speed = (character_data.stats.agility or 10) * 8 + 60 -- Scale agility to speed
    
    -- Reset state
    controller.animation.current_state = "idle"
    controller.animation.facing_direction = "down"
    controller.animation.time = 0
    controller.dodge.is_dodging = false
    controller.dodge.timer = 0
    controller.dodge.cooldown_timer = 0
    controller.alive = true
    controller.respawn_timer = 0
    
    print("Player created with character: " .. character_data.name)
    return controller
end

-- Update player input
function player_controller.update_input(dt)
    -- Movement input
    controller.input.move_x = 0
    controller.input.move_y = 0
    
    if love.keyboard.isDown("a") or love.keyboard.isDown("left") then
        controller.input.move_x = controller.input.move_x - 1
    end
    if love.keyboard.isDown("d") or love.keyboard.isDown("right") then
        controller.input.move_x = controller.input.move_x + 1
    end
    if love.keyboard.isDown("w") or love.keyboard.isDown("up") then
        controller.input.move_y = controller.input.move_y - 1
    end
    if love.keyboard.isDown("s") or love.keyboard.isDown("down") then
        controller.input.move_y = controller.input.move_y + 1
    end
    
    -- Normalize diagonal movement
    if controller.input.move_x ~= 0 and controller.input.move_y ~= 0 then
        local length = math.sqrt(controller.input.move_x^2 + controller.input.move_y^2)
        controller.input.move_x = controller.input.move_x / length
        controller.input.move_y = controller.input.move_y / length
    end
    
    -- Dodge input
    controller.input.dodge_pressed = love.keyboard.isDown("space")
    
    -- Attack input
    controller.input.attack_pressed = love.mouse.isDown(1) -- Left mouse button
end

-- Update facing direction based on movement
function player_controller.update_facing_direction(vx, vy)
    if math.abs(vx) > math.abs(vy) then
        if vx > 0 then
            controller.animation.facing_direction = "right"
        else
            controller.animation.facing_direction = "left"
        end
    else
        if vy > 0 then
            controller.animation.facing_direction = "down"
        else
            controller.animation.facing_direction = "up"
        end
    end
end

-- Update dodge system
function player_controller.update_dodge(dt)
    -- Update dodge timers
    if controller.dodge.timer > 0 then
        controller.dodge.timer = controller.dodge.timer - dt
        if controller.dodge.timer <= 0 then
            controller.dodge.is_dodging = false
        end
    end
    
    if controller.dodge.cooldown_timer > 0 then
        controller.dodge.cooldown_timer = controller.dodge.cooldown_timer - dt
    end
    
    -- Check for dodge activation
    if controller.input.dodge_pressed and not controller.dodge.is_dodging and controller.dodge.cooldown_timer <= 0 then
        -- Determine dodge direction
        local dodge_x, dodge_y = controller.input.move_x, controller.input.move_y
        
        -- If no movement input, dodge in facing direction
        if dodge_x == 0 and dodge_y == 0 then
            if controller.animation.facing_direction == "right" then
                dodge_x, dodge_y = 1, 0
            elseif controller.animation.facing_direction == "left" then
                dodge_x, dodge_y = -1, 0
            elseif controller.animation.facing_direction == "up" then
                dodge_x, dodge_y = 0, -1
            else -- down
                dodge_x, dodge_y = 0, 1
            end
        end
        
        -- Start dodge if we have a direction
        if dodge_x ~= 0 or dodge_y ~= 0 then
            controller.dodge.direction.x = dodge_x
            controller.dodge.direction.y = dodge_y
            controller.dodge.is_dodging = true
            controller.dodge.timer = controller.movement.dodge_duration
            controller.dodge.cooldown_timer = controller.movement.dodge_cooldown
            controller.animation.current_state = "dash"
        end
    end
end

-- Update movement physics
function player_controller.update_movement(dt)
    if not controller.body or controller.body:isDestroyed() then
        return
    end
    
    local vx, vy = controller.body:getLinearVelocity()
    
    -- Handle dodge/dash movement
    if controller.dodge.is_dodging then
        local dodge_vx = controller.dodge.direction.x * controller.movement.dodge_speed
        local dodge_vy = controller.dodge.direction.y * controller.movement.dodge_speed
        controller.body:setLinearVelocity(dodge_vx, dodge_vy)
        
        -- Update facing direction during dodge
        player_controller.update_facing_direction(dodge_vx, dodge_vy)
        return
    end
    
    -- Normal movement
    local target_vx = controller.input.move_x * controller.movement.max_speed
    local target_vy = controller.input.move_y * controller.movement.max_speed
    
    local new_vx, new_vy
    
    if controller.input.move_x ~= 0 or controller.input.move_y ~= 0 then
        -- Accelerate toward target velocity
        local accel_factor = math.min(dt * controller.movement.acceleration / controller.movement.max_speed, 1)
        new_vx = vx + (target_vx - vx) * accel_factor
        new_vy = vy + (target_vy - vy) * accel_factor
        
        -- Update facing direction and animation state
        player_controller.update_facing_direction(new_vx, new_vy)
        controller.animation.current_state = "walk"
    else
        -- Apply friction when no input
        new_vx = vx * controller.movement.friction
        new_vy = vy * controller.movement.friction
        
        -- Stop completely if moving very slowly
        if math.abs(new_vx) < 5 and math.abs(new_vy) < 5 then
            new_vx, new_vy = 0, 0
        end
        
        -- Set idle animation when not moving
        if math.abs(new_vx) < 10 and math.abs(new_vy) < 10 then
            controller.animation.current_state = "idle"
        end
    end
    
    -- Apply velocity
    controller.body:setLinearVelocity(new_vx, new_vy)
end

-- Update animation system
function player_controller.update_animation(dt)
    controller.animation.time = controller.animation.time + dt
    
    -- Animation timing - cycle every 0.5 seconds for walk, static for idle
    if controller.animation.current_state == "walk" then
        -- Walk animation cycles
        if controller.animation.time >= 0.5 then
            controller.animation.time = 0
        end
    elseif controller.animation.current_state == "dash" then
        -- Dash animation
        if controller.animation.time >= 0.1 then
            controller.animation.time = 0
        end
    else
        -- Idle animation - slower cycle
        if controller.animation.time >= 1.0 then
            controller.animation.time = 0
        end
    end
end

-- Main update function
function player_controller.update(dt)
    if not controller.alive then
        controller.respawn_timer = controller.respawn_timer + dt
        return
    end
    
    -- Update input
    player_controller.update_input(dt)
    
    -- Update dodge system
    player_controller.update_dodge(dt)
    
    -- Update movement
    player_controller.update_movement(dt)
    
    -- Update animation
    player_controller.update_animation(dt)
    
    -- Update character playtime
    if controller.character_data and controller.current_character_id then
        character_save_system.update_playtime(controller.current_character_id, controller.character_data, dt)
    end
    
    -- Check for death
    if controller.health <= 0 and controller.alive then
        controller.alive = false
        controller.respawn_timer = 0
        print("Player died!")
    end
end

-- Draw the player
function player_controller.draw()
    if not controller.body or controller.body:isDestroyed() or not controller.alive then
        return
    end
    
    local px, py = controller.body:getPosition()
    
    -- Use character data for rendering if available
    if controller.character_data then
        local class = controller.character_data.class
        local scale = 1.0
        local size = 24
        
        -- Character class colors and shapes
        local class_info = {
            warrior = {color = {0.8, 0.3, 0.3, 1}, shape = "square"},  -- Red square
            mage = {color = {0.3, 0.3, 0.8, 1}, shape = "circle"},     -- Blue circle
            archer = {color = {0.3, 0.8, 0.3, 1}, shape = "triangle"}, -- Green triangle
            rogue = {color = {0.6, 0.2, 0.8, 1}, shape = "diamond"}    -- Purple diamond
        }
        
        local info = class_info[class] or {color = {0.7, 0.7, 0.7, 1}, shape = "square"}
        local color = info.color
        
        -- Draw character based on class shape
        love.graphics.setColor(color[1], color[2], color[3], color[4])
        
        if info.shape == "circle" then
            love.graphics.circle("fill", px, py, size/2)
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.circle("line", px, py, size/2)
        elseif info.shape == "triangle" then
            love.graphics.polygon("fill", px, py - size/2, px - size/2, py + size/2, px + size/2, py + size/2)
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.polygon("line", px, py - size/2, px - size/2, py + size/2, px + size/2, py + size/2)
        elseif info.shape == "diamond" then
            love.graphics.polygon("fill", px, py - size/2, px + size/2, py, px, py + size/2, px - size/2, py)
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.polygon("line", px, py - size/2, px + size/2, py, px, py + size/2, px - size/2, py)
        else -- square (warrior and default)
            love.graphics.rectangle("fill", px - size/2, py - size/2, size, size)
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.rectangle("line", px - size/2, py - size/2, size, size)
        end
        
        -- Draw facing direction indicator
        love.graphics.setColor(1, 1, 1, 1)
        local arrow_size = 6
        local arrow_x, arrow_y = px, py
        
        if controller.animation.facing_direction == "right" then
            arrow_x = px + size/3
        elseif controller.animation.facing_direction == "left" then
            arrow_x = px - size/3
        elseif controller.animation.facing_direction == "up" then
            arrow_y = py - size/3
        else -- down
            arrow_y = py + size/3
        end
        
        love.graphics.circle("fill", arrow_x, arrow_y, arrow_size/2)
        
        -- Draw dodge effect
        if controller.dodge.is_dodging then
            love.graphics.setColor(1, 1, 1, 0.5)
            love.graphics.circle("line", px, py, size)
        end
        
        -- Draw health bar
        local bar_width = 40
        local bar_height = 6
        local bar_x = px - bar_width/2
        local bar_y = py - size/2 - 15
        
        -- Health bar background
        love.graphics.setColor(0.3, 0.3, 0.3, 0.8)
        love.graphics.rectangle("fill", bar_x, bar_y, bar_width, bar_height)
        
        -- Health bar fill
        local health_percent = controller.health / controller.max_health
        love.graphics.setColor(1 - health_percent, health_percent, 0, 1)
        love.graphics.rectangle("fill", bar_x, bar_y, bar_width * health_percent, bar_height)
        
        -- Health bar border
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("line", bar_x, bar_y, bar_width, bar_height)
        
    else
        -- Fallback rendering
        love.graphics.setColor(0.5, 0.5, 1.0, 1.0)
        love.graphics.rectangle("fill", px - 16, py - 16, 32, 32)
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("line", px - 16, py - 16, 32, 32)
    end
    
    -- Reset color
    love.graphics.setColor(1, 1, 1, 1)
end

-- Get player position
function player_controller.get_position()
    if controller.body and not controller.body:isDestroyed() then
        return controller.body:getPosition()
    end
    return 0, 0
end

-- Get player velocity
function player_controller.get_velocity()
    if controller.body and not controller.body:isDestroyed() then
        return controller.body:getLinearVelocity()
    end
    return 0, 0
end

-- Get player body for camera system
function player_controller.get_body()
    return controller.body
end

-- Get player health info
function player_controller.get_health()
    return {
        current = controller.health,
        max = controller.max_health,
        alive = controller.alive
    }
end

-- Get current character data
function player_controller.get_character_data()
    return controller.character_data
end

-- Get current character ID
function player_controller.get_character_id()
    return controller.current_character_id
end

-- Save current character state
function player_controller.save_character()
    if controller.character_data and controller.current_character_id then
        -- Update position in character data
        if controller.body and not controller.body:isDestroyed() then
            local px, py = controller.body:getPosition()
            controller.character_data.position.x = px
            controller.character_data.position.y = py
        end
        
        -- Update health
        controller.character_data.stats.health = controller.health
        
        -- Save to file
        character_save_system.save_character(controller.current_character_id, controller.character_data)
        print("Character saved: " .. controller.character_data.name)
    end
end

-- Handle collision with other objects
function player_controller.handle_collision(other_fixture, contact)
    if not controller.alive then return end
    
    -- This would be expanded to handle different collision types
    -- For now, just basic damage from enemies
    local other_body = other_fixture:getBody()
    local user_data = other_fixture:getUserData()
    
    if user_data == "enemy" then
        controller.health = controller.health - 10
        print("Player took damage! Health: " .. controller.health)
        
        -- Spawn blood effect at player position
        if particle_system and particle_system.createEffect then
            local player_x, player_y = controller.body:getPosition()
            particle_system.createEffect(particle_system.EFFECT_TYPES.BLOOD, player_x, player_y, {count=20})
        end
    elseif user_data == "coin" then
        -- Handle coin collection
        print("Coin collected!")
    end
end

-- Respawn player
function player_controller.respawn()
    if controller.character_data then
        controller.health = controller.max_health
        controller.alive = true
        controller.respawn_timer = 0
        
        -- Reset position to spawn point
        if controller.body and not controller.body:isDestroyed() then
            controller.body:setPosition(
                controller.character_data.position.x or 400,
                controller.character_data.position.y or 300
            )
            controller.body:setLinearVelocity(0, 0)
        end
        
        print("Player respawned!")
    end
end

-- Get all saved characters for character selection
function player_controller.get_all_characters()
    return character_save_system.get_all_characters()
end

-- Create a new character
function player_controller.create_new_character(name, class)
    return character_save_system.create_character(name, class)
end

-- Delete a character
function player_controller.delete_character(character_id)
    return character_save_system.delete_character(character_id)
end

return player_controller
