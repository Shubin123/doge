local enemy = {}

-- Visual and animation settings
enemy.scale = 0.6
enemy.t = 0
enemy.animation_speed = 8

-- Combat system
enemy.projectiles = {}
enemy.max_projectiles_per_enemy = 30
enemy.fire_cooldown = 1.5
enemy.last_fire_times = {}
enemy.detection_range = 350
enemy.projectile_speed = 450
enemy_projectile_bodies = {}

-- RPG-style enemy types and stats
enemy.types = {
    grunt = {
        health = 3,
        speed = 150,
        damage = 1,
        fire_rate = 2.0,
        detection_range = 300,
        sprite_sheet = "enemy-01.png",
        aura_color = {1.0, 0.5, 0.3},
        death_color = {1.0, 0.3, 0.1},
        experience = 10
    },
    warrior = {
        health = 6,
        speed = 120,
        damage = 2,
        fire_rate = 1.5,
        detection_range = 400,
        sprite_sheet = "enemy-02.png",
        aura_color = {0.8, 0.3, 1.0},
        death_color = {0.6, 0.2, 0.8},
        experience = 25
    },
    elite = {
        health = 10,
        speed = 100,
        damage = 3,
        fire_rate = 1.0,
        detection_range = 500,
        sprite_sheet = "enemy-03.png",
        aura_color = {0.3, 0.8, 1.0},
        death_color = {0.1, 0.6, 1.0},
        experience = 50
    }
}

-- Enemy instances with RPG stats
enemy.instances = {}
enemy.death_effects = {}
enemy.sprite_sheets = {}

-- Sprites that need white background removal
enemy.sprites_needing_transparency = {
    "enemy-01.png",
    "enemy-02.png", 
    "enemy-03.png",
    "enemy-explosion.png"
}

-- AI States for RPG-style behavior
enemy.AI_STATES = {
    IDLE = "idle",
    PATROL = "patrol",
    CHASE = "chase",
    ATTACK = "attack",
    RETREAT = "retreat",
    STUNNED = "stunned",
    DYING = "dying"
}

-- Pathfinding grid for RPG-style movement
enemy.pathfinding = {
    grid_size = 32,
    grid = {},
    width = 0,
    height = 0
}

-- Reuse the same fire sprite from the fire module
local function getFireSprite()
    -- if sprite.spriteImg then
    --     return spriteImg
    -- else
    --     return love.graphics.newImage('gfx/firelowres.png')
    -- end
     return love.graphics.newImage('gfx/firelowres.png')
end

function enemy.load()
    -- Load ray marching shaders for stunning visual effects
    enemy.aura_shader = love.graphics.newShader("shaders_/enemy_aura.frag")
    enemy.death_shader = love.graphics.newShader("shaders_/enemy_death.frag")
    enemy.sprite_transparency_shader = love.graphics.newShader("shaders_/sprite_transparency.frag")
    
    -- Load enemy sprite sheets with proper transparency handling
    for type_name, type_data in pairs(enemy.types) do
        local img = love.graphics.newImage("gfx/EnemiesSpriteSheets/" .. type_data.sprite_sheet)
        -- Pre-multiply alpha to handle transparency better
        img:setFilter("linear", "linear")
        enemy.sprite_sheets[type_name] = img
    end
    
    -- Initialize particle system effects for each enemy type
    enemy.aura_effects = {} -- Store continuous aura effects for each enemy
    
    -- Define particle effect themes for each enemy type
    enemy.effect_themes = {
        grunt = {
            aura = "fire",
            projectile = "fire", 
            death = "fire",
            impact = "impact",
            colors = {fire = true}
        },
        warrior = {
            aura = "electric",
            projectile = "electric",
            death = "electric", 
            impact = "electric",
            colors = {electric = true}
        },
        elite = {
            aura = "energy",
            projectile = "energy",
            death = "ice",
            impact = "energy", 
            colors = {energy = true, ice = true}
        }
    }
    
    -- Initialize pathfinding grid
    enemy.initializePathfinding()
    
    -- Initialize existing enemies with types
    for i = 1, #enemies_bods do
        enemy.initializeEnemyInstance(i)
    end
end

function enemy.update(dt)
    enemy.t = enemy.t + dt
    
    -- Update particle system
    if particle_system then
        particle_system.update(dt)
    end
    
    -- Update enemy aura effects positions
    for enemy_id, aura_effect in pairs(enemy.aura_effects) do
        if enemies_bods[enemy_id] and enemy.instances[enemy_id] then
            local x, y = enemies_bods[enemy_id]:getPosition()
            aura_effect.x = x
            aura_effect.y = y
            aura_effect.system:setPosition(x, y)
        else
            -- Remove invalid aura effects
            enemy.aura_effects[enemy_id] = nil
        end
    end
    
    -- Update enemy instances with RPG-style AI
    for i = 1, #enemies_bods do
        if enemy.instances[i] then
            enemy.updateEnemyRPG(i, dt)
        end
    end
    
    -- Update projectiles
    enemy.updateProjectiles(dt)
    
    -- Update death effects
    enemy.updateDeathEffects(dt)
end

-- RPG-style enemy AI system
function enemy.updateEnemyRPG(enemy_index, dt)
    if not enemies_bods[enemy_index] or not player or not player.body then
        return
    end
    
    local instance = enemy.instances[enemy_index]
    if not instance then return end
    
    local enemy_body = enemies_bods[enemy_index]
    local enemy_x, enemy_y = enemy_body:getPosition()
    local player_x, player_y = player.body:getPosition()
    
    -- Calculate distance to player
    local dx = player_x - enemy_x
    local dy = player_y - enemy_y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    -- Update animation timer
    instance.animation_timer = instance.animation_timer + dt * enemy.animation_speed
    
    -- Update state timers
    if instance.state_timer > 0 then
        instance.state_timer = instance.state_timer - dt
    end
    
    -- Update stun
    if instance.stun_timer > 0 then
        instance.stun_timer = instance.stun_timer - dt
        if instance.stun_timer <= 0 then
            enemy.changeState(enemy_index, enemy.AI_STATES.IDLE)
        end
        return -- Skip AI while stunned
    end
    
    -- RPG-style state machine
    if instance.state == enemy.AI_STATES.IDLE then
        enemy.updateIdleState(enemy_index, distance, dx, dy, dt)
    elseif instance.state == enemy.AI_STATES.PATROL then
        enemy.updatePatrolState(enemy_index, distance, dx, dy, dt)
    elseif instance.state == enemy.AI_STATES.CHASE then
        enemy.updateChaseState(enemy_index, distance, dx, dy, dt)
    elseif instance.state == enemy.AI_STATES.ATTACK then
        enemy.updateAttackState(enemy_index, distance, dx, dy, dt)
    elseif instance.state == enemy.AI_STATES.RETREAT then
        enemy.updateRetreatState(enemy_index, distance, dx, dy, dt)
    elseif instance.state == enemy.AI_STATES.DYING then
        enemy.updateDeathState(enemy_index, dt)
    end
end

-- Initialize enemy instance with RPG stats
function enemy.initializeEnemyInstance(enemy_index)
    local type_name = "grunt" -- Default type, can be randomized
    
    -- Random enemy type selection weighted by difficulty
    local rand = math.random()
    if rand < 0.6 then
        type_name = "grunt"
    elseif rand < 0.85 then
        type_name = "warrior"
    else
        type_name = "elite"
    end
    
    local type_data = enemy.types[type_name]
    
    enemy.instances[enemy_index] = {
        type = type_name,
        health = type_data.health,
        max_health = type_data.health,
        speed = type_data.speed,
        damage = type_data.damage,
        detection_range = type_data.detection_range,
        fire_rate = type_data.fire_rate,
        
        -- AI state
        state = enemy.AI_STATES.IDLE,
        state_timer = 0,
        last_fire_time = 0,
        
        -- Animation
        animation_timer = 0,
        facing_direction = 1, -- 1 for right, -1 for left
        
        -- Status effects
        stun_timer = 0,
        
        -- Pathfinding
        path = {},
        path_index = 1,
        stuck_timer = 0,
        
        -- Visual effects
        aura_intensity = 1.0,
        damage_flash = 0,
        death_progress = 0
    }
    
    enemy.last_fire_times[enemy_index] = 0
end

-- State management
function enemy.changeState(enemy_index, new_state)
    local instance = enemy.instances[enemy_index]
    if not instance then return end
    
    instance.state = new_state
    instance.state_timer = 0
    
    -- State-specific initialization
    if new_state == enemy.AI_STATES.PATROL then
        instance.state_timer = math.random(2, 5)
    elseif new_state == enemy.AI_STATES.ATTACK then
        instance.state_timer = 0.5
    elseif new_state == enemy.AI_STATES.RETREAT then
        instance.state_timer = math.random(1, 3)
    end
end

-- Enhanced projectile firing with visual effects
function enemy.fireAtPlayer(enemy_index, enemy_x, enemy_y, player_x, player_y)
    local instance = enemy.instances[enemy_index]
    if not instance then return end
    
    local type_data = enemy.types[instance.type]
    
    -- Calculate direction to player with some accuracy variation
    local dx = player_x - enemy_x
    local dy = player_y - enemy_y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    if distance == 0 then return end
    
    -- Add accuracy variation based on enemy type
    local accuracy = 1.0
    if instance.type == "grunt" then accuracy = 0.85
    elseif instance.type == "warrior" then accuracy = 0.95
    else accuracy = 0.98 end
    
    local spread = (1.0 - accuracy) * 0.5
    local angle_offset = (math.random() - 0.5) * spread
    
    local base_angle = math.atan2(dy, dx)
    local final_angle = base_angle + angle_offset
    
    local dir_x = math.cos(final_angle)
    local dir_y = math.sin(final_angle)
    
    -- Create enhanced projectile
    local projectile = {
        vec2.new(enemy_x, enemy_y),  -- position
        vec2.new(dir_x * enemy.projectile_speed, dir_y * enemy.projectile_speed),  -- velocity
        true,  -- initialized
        enemy_index,  -- which enemy fired this
        enemy.t + 6.0,  -- despawn time
        instance.type,  -- enemy type for visual effects
        type_data.damage,  -- damage amount
        0  -- travel time for effects
    }
    
    -- Create physics body
    local proj_body = love.physics.newBody(world, enemy_x, enemy_y, "dynamic")
    local proj_fixture = love.physics.newFixture(proj_body, love.physics.newCircleShape(12))
    proj_fixture:setGroupIndex(-777)
    
    table.insert(enemy.projectiles, projectile)
    table.insert(enemy_projectile_bodies, proj_body)
    
    -- Trigger firing effects
    enemy.triggerFireEffect(enemy_index, enemy_x, enemy_y, instance.type)
end

-- Visual effects for firing using dynamic particles
function enemy.triggerFireEffect(enemy_index, x, y, enemy_type)
    if not particle_system then return end
    
    local theme = enemy.effect_themes[enemy_type] or enemy.effect_themes.grunt
    
    -- Create muzzle flash effect
    if theme.projectile == "fire" then
        particle_system.createEffect(particle_system.EFFECT_TYPES.FIRE, x, y, {
            particle_count = 15,
            speed = {40, 80},
            lifetime = {0.3, 0.6},
            size_start = {0.3, 0.8}
        })
    elseif theme.projectile == "electric" then
        particle_system.createEffect(particle_system.EFFECT_TYPES.ELECTRIC, x, y, {
            particle_count = 20,
            speed = {60, 120},
            lifetime = {0.2, 0.5}
        })
    elseif theme.projectile == "energy" then
        particle_system.createEffect(particle_system.EFFECT_TYPES.ENERGY, x, y, {
            particle_count = 25,
            speed = {30, 70},
            lifetime = {0.5, 1.0}
        })
    end
end

-- AI State Functions --

-- Idle state: Look around, occasionally patrol
function enemy.updateIdleState(enemy_index, distance, dx, dy, dt)
    local instance = enemy.instances[enemy_index]
    
    -- Check for player detection
    if distance <= instance.detection_range then
        enemy.changeState(enemy_index, enemy.AI_STATES.CHASE)
        return
    end
    
    -- Randomly start patrolling
    if instance.state_timer <= 0 and math.random() < 0.3 then
        enemy.changeState(enemy_index, enemy.AI_STATES.PATROL)
    end
end

-- Patrol state: Move in a pattern
function enemy.updatePatrolState(enemy_index, distance, dx, dy, dt)
    local instance = enemy.instances[enemy_index]
    local enemy_body = enemies_bods[enemy_index]
    
    -- Check for player detection
    if distance <= instance.detection_range then
        enemy.changeState(enemy_index, enemy.AI_STATES.CHASE)
        return
    end
    
    -- Simple patrol movement
    if instance.state_timer > 0 then
        local move_x = math.sin(enemy.t + enemy_index) * 100
        local move_y = math.cos(enemy.t * 0.5 + enemy_index) * 50
        enemy_body:applyForce(move_x, move_y)
    else
        enemy.changeState(enemy_index, enemy.AI_STATES.IDLE)
    end
end

-- Chase state: Pursue the player
function enemy.updateChaseState(enemy_index, distance, dx, dy, dt)
    local instance = enemy.instances[enemy_index]
    local enemy_body = enemies_bods[enemy_index]
    
    -- Check if player is too far
    if distance > instance.detection_range * 1.5 then
        enemy.changeState(enemy_index, enemy.AI_STATES.IDLE)
        return
    end
    
    -- Check if close enough to attack
    if distance <= 200 then
        enemy.changeState(enemy_index, enemy.AI_STATES.ATTACK)
        return
    end
    
    -- Move toward player with pathfinding
    local norm_dx = dx / distance
    local norm_dy = dy / distance
    
    local move_force = instance.speed
    enemy_body:applyForce(norm_dx * move_force, norm_dy * move_force)
    
    -- Update facing direction
    instance.facing_direction = dx > 0 and 1 or -1
end

-- Attack state: Fire at player and maintain distance
function enemy.updateAttackState(enemy_index, distance, dx, dy, dt)
    local instance = enemy.instances[enemy_index]
    local enemy_body = enemies_bods[enemy_index]
    
    -- Check if player moved too far
    if distance > 300 then
        enemy.changeState(enemy_index, enemy.AI_STATES.CHASE)
        return
    end
    
    -- Check if player is too close
    if distance < 100 then
        enemy.changeState(enemy_index, enemy.AI_STATES.RETREAT)
        return
    end
    
    -- Fire at player
    local current_time = enemy.t
    if (current_time - instance.last_fire_time) >= instance.fire_rate then
        local enemy_x, enemy_y = enemy_body:getPosition()
        local player_x, player_y = player.body:getPosition()
        enemy.fireAtPlayer(enemy_index, enemy_x, enemy_y, player_x, player_y)
        instance.last_fire_time = current_time
    end
    
    -- Maintain optimal distance with strafing
    local ideal_distance = 180
    local distance_diff = distance - ideal_distance
    
    if math.abs(distance_diff) > 30 then
        local norm_dx = dx / distance
        local norm_dy = dy / distance
        
        -- Move toward or away from player
        local direction = distance_diff > 0 and -1 or 1
        enemy_body:applyForce(norm_dx * direction * 200, norm_dy * direction * 200)
    end
    
    -- Add strafing movement
    local strafe_x = -dy / distance * 150 * math.sin(enemy.t * 2 + enemy_index)
    local strafe_y = dx / distance * 150 * math.sin(enemy.t * 2 + enemy_index)
    enemy_body:applyForce(strafe_x, strafe_y)
end

-- Retreat state: Move away from player
function enemy.updateRetreatState(enemy_index, distance, dx, dy, dt)
    local instance = enemy.instances[enemy_index]
    local enemy_body = enemies_bods[enemy_index]
    
    -- Check if far enough to resume attack
    if distance > 250 then
        enemy.changeState(enemy_index, enemy.AI_STATES.ATTACK)
        return
    end
    
    -- Move away from player
    local norm_dx = dx / distance
    local norm_dy = dy / distance
    
    enemy_body:applyForce(-norm_dx * instance.speed * 1.5, -norm_dy * instance.speed * 1.5)
end

-- Death state: Handle death animation and effects
function enemy.updateDeathState(enemy_index, dt)
    local instance = enemy.instances[enemy_index]
    
    instance.death_progress = instance.death_progress + dt * 2.0
    
    if instance.death_progress >= 1.0 then
        -- Complete death, remove enemy
        enemy.removeEnemy(enemy_index)
    end
end

-- Pathfinding initialization
function enemy.initializePathfinding()
    -- Simple grid-based pathfinding setup
    enemy.pathfinding.width = math.ceil(W / enemy.pathfinding.grid_size)
    enemy.pathfinding.height = math.ceil(H / enemy.pathfinding.grid_size)
    
    for x = 1, enemy.pathfinding.width do
        enemy.pathfinding.grid[x] = {}
        for y = 1, enemy.pathfinding.height do
            enemy.pathfinding.grid[x][y] = true -- true = walkable
        end
    end
end

function enemy.updateProjectiles(dt)
    -- Update projectile positions and remove expired ones
    for i = #enemy.projectiles, 1, -1 do
        local proj = enemy.projectiles[i]
        
        -- Update travel time for effects
        proj[8] = proj[8] + dt
        
        -- Check if projectile should despawn
        if enemy.t > proj[5] then
            -- Remove physics body
            if enemy_projectile_bodies[i] then
                enemy_projectile_bodies[i]:destroy()
                table.remove(enemy_projectile_bodies, i)
            end
            table.remove(enemy.projectiles, i)
        else
            -- Update position
            proj[1] = proj[1] + proj[2] * dt
            
            -- Update physics body position
            if enemy_projectile_bodies[i] then
                enemy_projectile_bodies[i]:setPosition(proj[1].x, proj[1].y)
            end
        end
    end
end

-- Update death effects
function enemy.updateDeathEffects(dt)
    for i = #enemy.death_effects, 1, -1 do
        local effect = enemy.death_effects[i]
        effect.progress = effect.progress + dt * 2.0
        
        if effect.progress >= 1.0 then
            table.remove(enemy.death_effects, i)
        end
    end
end
--
function enemy.populate()
    -- Add enemies with aura effects to dynamic draw list
    for i = 1, #enemies_bods do
        local instance = enemy.instances[i]
        if instance and enemies_bods[i] then
            local enemy_x, enemy_y = enemies_bods[i]:getPosition()
            local type_data = enemy.types[instance.type]
            
            -- Add enemy sprite
            local sprite_sheet = enemy.sprite_sheets[instance.type]
            if sprite_sheet then
                local type_data = enemy.types[instance.type]
                local sprite_filename = type_data.sprite_sheet
                
                -- Check if this sprite needs transparency shader
                local needs_transparency = false
                for _, filename in ipairs(enemy.sprites_needing_transparency) do
                    if filename == sprite_filename then
                        needs_transparency = true
                        break
                    end
                end
                
                local draw_item = {
                    sort_y = enemy_y + 100,
                    image_or_particles = sprite_sheet,
                    quad = nil,
                    x = enemy_x,
                    y = enemy_y,
                    rotation = 0,
                    scale_x = enemy.scale * instance.facing_direction,
                    scale_y = enemy.scale,
                    offset_x = sprite_sheet:getWidth() / 2,
                    offset_y = sprite_sheet:getHeight() / 2,
                    color = {1, 1, 1, 1},
                    blend_mode = {"alpha", "premultiplied"},
                    source_object_type = "enemy_sprite"
                }
                
                -- Add transparency shader if needed
                if needs_transparency and enemy.sprite_transparency_shader then
                    draw_item.image_shader = enemy.sprite_transparency_shader
                    draw_item.shader_uniforms = {
                        threshold = 0.85,
                        smoothness = 0.1
                    }
                end
                
                table.insert(dynamic_draw_list, draw_item)
            end
            
            -- Add particle aura effect for living enemies
            if instance.state ~= enemy.AI_STATES.DYING then
                -- Create or update aura effect
                if not enemy.aura_effects[i] and particle_system then
                    local theme = enemy.effect_themes[instance.type] or enemy.effect_themes.grunt
                    enemy.aura_effects[i] = particle_system.aura(enemy_x, enemy_y, theme.aura, instance.aura_intensity)
                end
            else
                -- Remove aura effect when dying
                if enemy.aura_effects[i] then
                    enemy.aura_effects[i] = nil
                end
            end
        end
    end
    
    -- Enemy projectiles now create trailing particle effects automatically
    -- The particle_system handles projectile trails and impacts
    
    -- Death effects are now handled by the particle system
    -- Dynamic explosions are created when enemies die
end

function enemy.collision(fixture_a, fixture_b, contact)
    local not_enemy_proj
    local enemy_proj_fixture
    
    -- Check if one of the fixtures is an enemy projectile
    if fixture_a:getGroupIndex() == -777 then
        enemy_proj_fixture = fixture_a
        not_enemy_proj = fixture_b
    elseif fixture_b:getGroupIndex() == -777 then
        enemy_proj_fixture = fixture_b
        not_enemy_proj = fixture_a
    end
    
    if enemy_proj_fixture ~= nil then
        -- Enemy projectile hit something
        local proj_body = enemy_proj_fixture:getBody()
        local proj_x, proj_y = proj_body:getPosition()
        
        -- Find which projectile this is
        local projectile_data = nil
        local proj_index = nil
        
        for i = #enemy_projectile_bodies, 1, -1 do
            if enemy_projectile_bodies[i] == proj_body then
                projectile_data = enemy.projectiles[i]
                proj_index = i
                break
            end
        end
        
        -- Check if it hit the player
        if player and player.body and not_enemy_proj:getBody() == player.body then
            if projectile_data then
                local damage = projectile_data[7] or 1 -- Get damage from projectile
                player.health = player.health - damage
                
                -- Add enhanced hit effects
                if effects and effects.newHitMarker then
                    effects.newHitMarker(proj_x, proj_y)
                end
                
                -- Screen shake on hit
                if camera and camera.addShake then
                    camera.addShake(damage * 0.5)
                end
                
                -- Play hit sound (if sound system exists)
                -- Add player knockback
                if projectile_data then
                    local knockback_force = 200 * damage
                    local dx = proj_x - player.body:getPosition()
                    local dy = proj_y - player.body:getPosition()
                    local dist = math.sqrt(dx*dx + dy*dy)
                    if dist > 0 then
                        player.body:applyLinearImpulse(dx/dist * knockback_force, dy/dist * knockback_force)
                    end
                end
            end
        end
        
        -- Create impact effect
        enemy.createImpactEffect(proj_x, proj_y, projectile_data and projectile_data[6] or "grunt")
        
        -- Remove the projectile
        if proj_index then
            proj_body:destroy()
            table.remove(enemy_projectile_bodies, proj_index)
            table.remove(enemy.projectiles, proj_index)
        end
    end
end

-- Create visual impact effects using dynamic particles
function enemy.createImpactEffect(x, y, enemy_type)
    if not particle_system then return end
    
    local theme = enemy.effect_themes[enemy_type] or enemy.effect_themes.grunt
    
    -- Create impact effect based on projectile type
    if theme.impact == "impact" then
        particle_system.impact(x, y, nil, 1.0)
    elseif theme.impact == "electric" then
        particle_system.createEffect(particle_system.EFFECT_TYPES.ELECTRIC, x, y, {
            particle_count = 15,
            speed = {40, 100}
        })
    elseif theme.impact == "energy" then
        particle_system.createEffect(particle_system.EFFECT_TYPES.ENERGY, x, y, {
            particle_count = 20,
            speed = {30, 80}
        })
    end
    
    -- Add sparks for extra impact
    particle_system.createEffect(particle_system.EFFECT_TYPES.SPARKS, x, y, {
        particle_count = 10,
        speed = {60, 120}
    })
end

-- Damage enemy function for player attacks
function enemy.damageEnemy(enemy_index, damage, attacker_x, attacker_y)
    local instance = enemy.instances[enemy_index]
    if not instance or instance.state == enemy.AI_STATES.DYING then
        return false
    end
    
    local enemy_body = enemies_bods[enemy_index]
    local enemy_x, enemy_y = enemy_body:getPosition()
    
    -- Apply damage
    instance.health = instance.health - damage
    instance.damage_flash = 0.3 -- Flash effect duration
    
    -- Add knockback
    local dx = enemy_x - attacker_x
    local dy = enemy_y - attacker_y
    local dist = math.sqrt(dx*dx + dy*dy)
    if dist > 0 then
        local knockback_force = 300 * damage
        enemy_body:applyLinearImpulse(dx/dist * knockback_force, dy/dist * knockback_force)
    end
    
    -- Check for death
    if instance.health <= 0 then
        enemy.killEnemy(enemy_index)
        return true -- Enemy died
    else
        -- Stun briefly when damaged
        instance.stun_timer = 0.2
        enemy.changeState(enemy_index, enemy.AI_STATES.STUNNED)
        
        -- Create blood splat effect
        enemy.createBloodEffect(enemy_x, enemy_y)
        
        return false -- Enemy survived
    end
end

-- Kill enemy with dynamic death effects
function enemy.killEnemy(enemy_index)
    local instance = enemy.instances[enemy_index]
    if not instance then return end
    
    local enemy_body = enemies_bods[enemy_index]
    local enemy_x, enemy_y = enemy_body:getPosition()
    local type_data = enemy.types[instance.type]
    local theme = enemy.effect_themes[instance.type] or enemy.effect_themes.grunt
    
    -- Remove aura effect
    if enemy.aura_effects[enemy_index] then
        enemy.aura_effects[enemy_index] = nil
    end
    
    -- Create dynamic death explosion based on enemy type
    if particle_system then
        local intensity = 1.0
        if instance.type == "warrior" then intensity = 1.5
        elseif instance.type == "elite" then intensity = 2.0 end
        
        particle_system.explosion(enemy_x, enemy_y, intensity, theme.death)
        
        -- Add secondary effects
        if theme.death == "electric" then
            particle_system.createEffect(particle_system.EFFECT_TYPES.ELECTRIC, enemy_x, enemy_y, {
                particle_count = 30,
                speed = {80, 160}
            })
        elseif theme.death == "ice" then
            particle_system.createEffect(particle_system.EFFECT_TYPES.ENERGY, enemy_x, enemy_y, {
                particle_count = 40,
                colors = {
                    {0.7, 0.9, 1.0, 1.0},
                    {0.5, 0.7, 1.0, 0.8}, 
                    {0.3, 0.5, 0.9, 0.3},
                    {0.1, 0.3, 0.7, 0.0}
                }
            })
        end
        
        -- Add smoke effect
        particle_system.createEffect(particle_system.EFFECT_TYPES.SMOKE, enemy_x, enemy_y, {
            particle_count = 20
        })
    end
    
    -- Grant experience to player
    if player and player.addExperience then
        player.addExperience(type_data.experience)
    end
    
    -- Change to dying state for animation
    enemy.changeState(enemy_index, enemy.AI_STATES.DYING)
end

-- Create blood effect using dynamic particles
function enemy.createBloodEffect(x, y)
    if particle_system then
        particle_system.createEffect(particle_system.EFFECT_TYPES.BLOOD, x, y, {
            particle_count = 15,
            speed = {30, 80}
        })
    end
end

-- Enhanced enemy spawning with type selection
function enemy.addEnemy(x, y, enemy_type)
    enemy_type = enemy_type or "grunt" -- Default type
    
    local type_data = enemy.types[enemy_type]
    if not type_data then
        enemy_type = "grunt"
        type_data = enemy.types.grunt
    end
    
    -- Create new enemy physics body
    local enemy_body = love.physics.newBody(world, x, y, "dynamic")
    local enemy_fixture = love.physics.newFixture(enemy_body, love.physics.newCircleShape(25))
    enemy_fixture:setGroupIndex(-777)
    
    -- Add to enemies_bods table
    table.insert(enemies_bods, enemy_body)
    local enemy_index = #enemies_bods
    
    -- Initialize enemy instance with specified type
    local instance = {
        type = enemy_type,
        health = type_data.health,
        max_health = type_data.health,
        speed = type_data.speed,
        damage = type_data.damage,
        detection_range = type_data.detection_range,
        fire_rate = type_data.fire_rate,
        
        -- AI state
        state = enemy.AI_STATES.IDLE,
        state_timer = 0,
        last_fire_time = enemy.t - type_data.fire_rate, -- Allow immediate firing
        
        -- Animation
        animation_timer = 0,
        facing_direction = 1,
        
        -- Status effects
        stun_timer = 0,
        
        -- Pathfinding
        path = {},
        path_index = 1,
        stuck_timer = 0,
        
        -- Visual effects
        aura_intensity = 1.0,
        damage_flash = 0,
        death_progress = 0
    }
    
    enemy.instances[enemy_index] = instance
    enemy.last_fire_times[enemy_index] = instance.last_fire_time
    
    return enemy_index, enemy_body
end


-- Enhanced reset function
function enemy.reset()
    -- Clear all enemy projectiles
    for i = #enemy_projectile_bodies, 1, -1 do
        enemy_projectile_bodies[i]:destroy()
        table.remove(enemy_projectile_bodies, i)
    end
    
    -- Clear all data
    enemy.projectiles = {}
    enemy.instances = {}
    enemy.death_effects = {}
    enemy.last_fire_times = {}
    enemy.t = 0
    
    -- Clear particle effects
    enemy.aura_effects = {}
    if particle_system then
        particle_system.clear()
    end
    
    -- Re-initialize existing enemies
    for i = 1, #enemies_bods do
        enemy.initializeEnemyInstance(i)
    end
end

-- Utility functions for enhanced gameplay

-- Get enemy at position (for targeting)
function enemy.getEnemyAtPosition(x, y, radius)
    radius = radius or 50
    
    for i = 1, #enemies_bods do
        if enemy.instances[i] and enemies_bods[i] then
            local ex, ey = enemies_bods[i]:getPosition()
            local dist = math.sqrt((x - ex)^2 + (y - ey)^2)
            if dist <= radius then
                return i
            end
        end
    end
    
    return nil
end

-- Stun enemy (for special attacks)
function enemy.stunEnemy(enemy_index, duration)
    local instance = enemy.instances[enemy_index]
    if instance then
        instance.stun_timer = duration
        enemy.changeState(enemy_index, enemy.AI_STATES.STUNNED)
        
        -- Visual stun effect
        instance.aura_intensity = 0.3
    end
end

-- Heal enemy (for special enemy types)
function enemy.healEnemy(enemy_index, amount)
    local instance = enemy.instances[enemy_index]
    if instance then
        instance.health = math.min(instance.max_health, instance.health + amount)
        
        -- Visual healing effect
        instance.aura_intensity = 1.5
    end
end

-- Get total enemy count by type
function enemy.getEnemyCountByType(enemy_type)
    local count = 0
    for _, instance in pairs(enemy.instances) do
        if instance.type == enemy_type then
            count = count + 1
        end
    end
    return count
end

-- Spawn wave of enemies for RPG-style encounters
function enemy.spawnWave(wave_data)
    for _, spawn_info in ipairs(wave_data) do
        enemy.addEnemy(spawn_info.x, spawn_info.y, spawn_info.type)
    end
end

-- Update shader uniforms for enhanced effects
function enemy.updateShaderUniforms()
    if enemy.aura_shader then
        enemy.aura_shader:send("time", enemy.t)
        if camera then
            enemy.aura_shader:send("camera_position", {camera.x, camera.y})
            enemy.aura_shader:send("camera_zoom", camera.zoom)
        end
        enemy.aura_shader:send("screen_size", {W, H})
    end
    
    if enemy.death_shader then
        enemy.death_shader:send("time", enemy.t)
        if camera then
            enemy.death_shader:send("camera_position", {camera.x, camera.y})
            enemy.death_shader:send("camera_zoom", camera.zoom)
        end
        enemy.death_shader:send("screen_size", {W, H})
    end
end

-- Utility function to add transparency shader to any sprite
function enemy.addTransparencyToDrawItem(draw_item, filename)
    -- Check if filename needs transparency
    local needs_transparency = false
    
    -- List of files that commonly have white backgrounds
    local files_needing_transparency = {
        "enemy-01.png", "enemy-02.png", "enemy-03.png", "enemy-explosion.png",
        "Blood Splat.png", "Sparks-Sheet.png", "Eletric A-Sheet.png",
        "Fire+Sparks-Sheet.png", "Smoke-Sheet.png", "Splatter-Sheet.png"
    }
    
    for _, transparent_file in ipairs(files_needing_transparency) do
        if filename and filename:find(transparent_file, 1, true) then
            needs_transparency = true
            break
        end
    end
    
    -- Add transparency shader if needed
    if needs_transparency and enemy.sprite_transparency_shader then
        draw_item.image_shader = enemy.sprite_transparency_shader
        draw_item.shader_uniforms = {
            threshold = 0.85,
            smoothness = 0.1
        }
    end
    
    return draw_item
end

return enemy