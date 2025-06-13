-- Basic Enemies Mod - Main Entry Point
-- This mod adds standard enemy types to the game world

local basicEnemiesMod = {}

-- Mod state
local enemies = {}
local enemy_counter = 0
local projectiles = {}
local projectile_counter = 0
local mod_config = {}
local enemy_types = {}

-- Enemy type definitions
local ENEMY_TYPES = {
    grunt = {
        health = 50,
        speed = 80,
        damage = 10,
        fire_rate = 2.0,
        fire_range = 250,
        detection_range = 300,
        sprite = "enemy_pig",
        scale = 0.8,
        mass = 1.0,
        drop_chance = 0.3,
        projectile_speed = 300,
        ai_type = "aggressive"
    },
    soldier = {
        health = 100,
        speed = 60,
        damage = 15,
        fire_rate = 1.5,
        fire_range = 350,
        detection_range = 400,
        sprite = "enemy_pig",
        scale = 1.0,
        mass = 1.5,
        drop_chance = 0.5,
        projectile_speed = 400,
        ai_type = "tactical"
    },
    sniper = {
        health = 75,
        speed = 40,
        damage = 25,
        fire_rate = 3.0,
        fire_range = 500,
        detection_range = 600,
        sprite = "enemy_pig",
        scale = 0.9,
        mass = 1.2,
        drop_chance = 0.7,
        projectile_speed = 600,
        ai_type = "cautious"
    }
}

-- Initialize the mod
function basicEnemiesMod.init(api)
    print("[BASIC_ENEMIES_MOD] Initializing Basic Enemies Mod v1.0.0")
    
    -- Store API reference
    basicEnemiesMod.api = api
    
    -- Load configuration
    mod_config = {
        max_enemies = 100,
        enemy_spawn_rate = 5.0,
        enable_projectiles = true,
        enable_particles = true,
        enable_networking = true,
        enemy_collision_group = -777,
        projectile_collision_group = -777
    }
    
    -- Register network handler
    if mod_config.enable_networking then
        api.network.registerMessageHandler("basic_enemies_mod", basicEnemiesMod.handleNetworkMessage)
    end
    
    -- Initialize enemy types
    for type_name, type_data in pairs(ENEMY_TYPES) do
        enemy_types[type_name] = type_data
    end
    
    -- Spawn initial enemies
    basicEnemiesMod.spawnInitialEnemies()
    
    print("[BASIC_ENEMIES_MOD] Initialization complete!")
end

-- Spawn initial enemies in the world
function basicEnemiesMod.spawnInitialEnemies()
    local spawn_positions = {
        {x = 400, y = 300, type = "grunt"},
        {x = 600, y = 200, type = "soldier"},
        {x = 300, y = 500, type = "sniper"},
        {x = 700, y = 400, type = "grunt"},
        {x = 500, y = 600, type = "soldier"}
    }
    
    for _, pos in ipairs(spawn_positions) do
        basicEnemiesMod.createEnemy(pos.x, pos.y, pos.type)
    end
    
    print("[BASIC_ENEMIES_MOD] Spawned " .. #spawn_positions .. " initial enemies")
end

-- Create a new enemy
function basicEnemiesMod.createEnemy(x, y, enemy_type)
    if #enemies >= mod_config.max_enemies then
        print("[BASIC_ENEMIES_MOD] Maximum enemy limit reached")
        return nil
    end
    
    enemy_type = enemy_type or "grunt"
    local type_config = ENEMY_TYPES[enemy_type]
    if not type_config then
        print("[BASIC_ENEMIES_MOD] Unknown enemy type: " .. enemy_type)
        return nil
    end
    
    enemy_counter = enemy_counter + 1
    
    -- Create physics body
    local body = basicEnemiesMod.api.physics.createBody(x, y, "dynamic", mod_config.enemy_collision_group, 1.0, 0.3)
    if not body then
        print("[BASIC_ENEMIES_MOD] Failed to create physics body")
        return nil
    end
    
    -- Create shape and fixture
    local shape = basicEnemiesMod.api.physics.createCircleShape(16)
    local fixture = basicEnemiesMod.api.physics.createFixture(body, shape, mod_config.enemy_collision_group, 1.0, 0.3)
    
    if fixture then
        fixture:setGroupIndex(mod_config.enemy_collision_group)
        fixture:setUserData({type = "enemy", mod = "basic_enemies_mod", id = enemy_counter})
    end
    
    body:setMass(type_config.mass)
    body:setLinearDamping(5)
    
    local enemy = {
        id = enemy_counter,
        type = enemy_type,
        config = type_config,
        body = body,
        fixture = fixture,
        x = x,
        y = y,
        health = type_config.health,
        max_health = type_config.health,
        active = true,
        fire_cooldown = 0,
        last_fire_time = 0,
        state = "idle",
        target_player = nil,
        velocity_x = 0,
        velocity_y = 0,
        damage_indicators = {},
        health_bar_visible = false,
        health_bar_timer = 0,
        ai_state_timer = 0,
        last_decision_time = 0
    }
    
    table.insert(enemies, enemy)
    
    -- Sync with network if enabled
    if mod_config.enable_networking then
        basicEnemiesMod.syncEnemyCreation(enemy)
    end
    
    return enemy
end

-- Update all enemies
function basicEnemiesMod.update(dt)
    local current_time = basicEnemiesMod.api.utils.getTime()
    
    -- Update enemies
    for i = #enemies, 1, -1 do
        local enemy = enemies[i]
        if enemy.active and enemy.body and not enemy.body:isDestroyed() then
            -- Update position from physics
            enemy.x = enemy.body:getX()
            enemy.y = enemy.body:getY()
            
            -- Update AI
            basicEnemiesMod.updateEnemyAI(enemy, dt, current_time)
            
            -- Update health bar visibility
            if enemy.health_bar_visible then
                enemy.health_bar_timer = enemy.health_bar_timer - dt
                if enemy.health_bar_timer <= 0 then
                    enemy.health_bar_visible = false
                end
            end
            
            -- Update damage indicators
            for j = #enemy.damage_indicators, 1, -1 do
                local indicator = enemy.damage_indicators[j]
                indicator.timer = indicator.timer - dt
                indicator.y = indicator.y - dt * 30
                indicator.alpha = indicator.alpha - dt * 2
                
                if indicator.timer <= 0 then
                    table.remove(enemy.damage_indicators, j)
                end
            end
            
            -- Add to render queue
            basicEnemiesMod.renderEnemy(enemy)
        else
            -- Remove dead enemy
            if enemy.body and not enemy.body:isDestroyed() then
                enemy.body:destroy()
            end
            table.remove(enemies, i)
        end
    end
    
    -- Update projectiles
    for i = #projectiles, 1, -1 do
        local proj = projectiles[i]
        if proj.active and proj.body and not proj.body:isDestroyed() then
            proj.x = proj.body:getX()
            proj.y = proj.body:getY()
            proj.lifetime = proj.lifetime - dt
            
            if proj.lifetime <= 0 then
                proj.active = false
            else
                basicEnemiesMod.renderProjectile(proj)
            end
        else
            if proj.body and not proj.body:isDestroyed() then
                proj.body:destroy()
            end
            table.remove(projectiles, i)
        end
    end
end

-- Update enemy AI
function basicEnemiesMod.updateEnemyAI(enemy, dt, current_time)
    local api = basicEnemiesMod.api
    
    -- Get nearest player position
    local player_x, player_y = api.game.getPlayerPosition()
    local distance = api.utils.math.distance(enemy.x, enemy.y, player_x, player_y)
    
    -- Update fire cooldown
    enemy.fire_cooldown = math.max(0, enemy.fire_cooldown - dt)
    
    -- AI behavior based on type
    if enemy.config.ai_type == "aggressive" then
        -- Always move towards player
        if distance > 100 then
            local dx = player_x - enemy.x
            local dy = player_y - enemy.y
            local length = math.sqrt(dx * dx + dy * dy)
            if length > 0 then
                enemy.velocity_x = (dx / length) * enemy.config.speed
                enemy.velocity_y = (dy / length) * enemy.config.speed
            end
        else
            -- Too close, back off slightly
            local dx = enemy.x - player_x
            local dy = enemy.y - player_y
            local length = math.sqrt(dx * dx + dy * dy)
            if length > 0 then
                enemy.velocity_x = (dx / length) * enemy.config.speed * 0.5
                enemy.velocity_y = (dy / length) * enemy.config.speed * 0.5
            end
        end
        
    elseif enemy.config.ai_type == "tactical" then
        -- Move in and out of range
        if current_time - enemy.last_decision_time > 2.0 then
            enemy.last_decision_time = current_time
            if distance < 200 then
                enemy.state = "retreat"
            elseif distance > 300 then
                enemy.state = "advance"
            else
                enemy.state = "strafe"
            end
        end
        
        if enemy.state == "advance" then
            local dx = player_x - enemy.x
            local dy = player_y - enemy.y
            local length = math.sqrt(dx * dx + dy * dy)
            if length > 0 then
                enemy.velocity_x = (dx / length) * enemy.config.speed
                enemy.velocity_y = (dy / length) * enemy.config.speed
            end
        elseif enemy.state == "retreat" then
            local dx = enemy.x - player_x
            local dy = enemy.y - player_y
            local length = math.sqrt(dx * dx + dy * dy)
            if length > 0 then
                enemy.velocity_x = (dx / length) * enemy.config.speed
                enemy.velocity_y = (dy / length) * enemy.config.speed
            end
        elseif enemy.state == "strafe" then
            -- Strafe around player
            local angle = math.atan2(player_y - enemy.y, player_x - enemy.x) + math.pi/2
            enemy.velocity_x = math.cos(angle) * enemy.config.speed * 0.7
            enemy.velocity_y = math.sin(angle) * enemy.config.speed * 0.7
        end
        
    elseif enemy.config.ai_type == "cautious" then
        -- Keep distance, fire from afar
        if distance < 400 then
            local dx = enemy.x - player_x
            local dy = enemy.y - player_y
            local length = math.sqrt(dx * dx + dy * dy)
            if length > 0 then
                enemy.velocity_x = (dx / length) * enemy.config.speed
                enemy.velocity_y = (dy / length) * enemy.config.speed
            end
        else
            -- Stand still when at optimal range
            enemy.velocity_x = 0
            enemy.velocity_y = 0
        end
    end
    
    -- Apply velocity to physics body
    if enemy.body then
        enemy.body:setLinearVelocity(enemy.velocity_x, enemy.velocity_y)
    end
    
    -- Fire at player if in range
    if distance <= enemy.config.fire_range and enemy.fire_cooldown <= 0 then
        basicEnemiesMod.fireProjectile(enemy, player_x, player_y)
        enemy.fire_cooldown = enemy.config.fire_rate
    end
end

-- Fire projectile
function basicEnemiesMod.fireProjectile(enemy, target_x, target_y)
    if not mod_config.enable_projectiles then return end
    
    projectile_counter = projectile_counter + 1
    
    -- Calculate direction
    local dx = target_x - enemy.x
    local dy = target_y - enemy.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length == 0 then return end
    
    dx = dx / length
    dy = dy / length
    
    -- Create projectile physics
    local proj_x = enemy.x + dx * 20
    local proj_y = enemy.y + dy * 20
    
    local body = basicEnemiesMod.api.physics.createBody(proj_x, proj_y, "dynamic", mod_config.projectile_collision_group, 0.1, 0)
    if not body then return end
    
    local shape = basicEnemiesMod.api.physics.createCircleShape(4)
    local fixture = basicEnemiesMod.api.physics.createFixture(body, shape, mod_config.projectile_collision_group, 0.1, 0)
    
    if fixture then
        fixture:setGroupIndex(mod_config.projectile_collision_group)
        fixture:setUserData({type = "enemy_projectile", mod = "basic_enemies_mod", id = projectile_counter, damage = enemy.config.damage})
    end
    
    body:setBullet(true)
    body:setLinearVelocity(dx * enemy.config.projectile_speed, dy * enemy.config.projectile_speed)
    
    local projectile = {
        id = projectile_counter,
        body = body,
        fixture = fixture,
        x = proj_x,
        y = proj_y,
        velocity_x = dx * enemy.config.projectile_speed,
        velocity_y = dy * enemy.config.projectile_speed,
        damage = enemy.config.damage,
        lifetime = 5.0,
        active = true,
        enemy_id = enemy.id
    }
    
    table.insert(projectiles, projectile)
    
    -- Particle effect at muzzle
    if mod_config.enable_particles then
        basicEnemiesMod.api.renderer.addParticleEffect(
            "enemy_fire_" .. enemy.id,
            proj_x,
            proj_y,
            "fire_burst",
            {
                lifetime = 0.3,
                color = {1, 0.6, 0.2, 1}
            }
        )
    end
end

-- Render enemy
function basicEnemiesMod.renderEnemy(enemy)
    local api = basicEnemiesMod.api
    
    -- Main enemy sprite
    api.renderer.addToQueue("world", {
        type = "sprite",
        texture_name = enemy.config.sprite,
        x = enemy.x,
        y = enemy.y,
        rotation = 0,
        scale_x = enemy.config.scale,
        scale_y = enemy.config.scale,
        sort_y = enemy.y,
        active = true,
        color = {1, 1, 1, 1}
    })
    
    -- Health bar if damaged
    if enemy.health_bar_visible and enemy.health < enemy.max_health then
        local health_percent = enemy.health / enemy.max_health
        local bar_width = 30
        local bar_height = 4
        local bar_y = enemy.y - 25
        
        -- Background
        api.renderer.addToQueue("ui", {
            type = "rectangle",
            mode = "fill",
            x = enemy.x - bar_width/2,
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
            x = enemy.x - bar_width/2 + 1,
            y = bar_y + 1,
            width = (bar_width - 2) * health_percent,
            height = bar_height - 2,
            sort_y = 10001,
            active = true,
            color = health_percent > 0.5 and {0.2, 0.8, 0.2, 0.9} or {0.8, 0.2, 0.2, 0.9}
        })
    end
    
    -- Damage indicators
    for _, indicator in ipairs(enemy.damage_indicators) do
        api.renderer.addToQueue("ui", {
            type = "text",
            text = tostring(indicator.damage),
            x = indicator.x,
            y = indicator.y,
            font = "default",
            sort_y = 10002,
            active = true,
            color = {indicator.color[1], indicator.color[2], indicator.color[3], indicator.alpha}
        })
    end
end

-- Render projectile
function basicEnemiesMod.renderProjectile(proj)
    local api = basicEnemiesMod.api
    
    -- Projectile sprite
    api.renderer.addToQueue("world", {
        type = "circle",
        mode = "fill",
        x = proj.x,
        y = proj.y,
        radius = 4,
        sort_y = proj.y,
        active = true,
        color = {1, 0.4, 0.1, 1}
    })
    
    -- Trail effect
    if mod_config.enable_particles then
        api.renderer.addParticleEffect(
            "proj_trail_" .. proj.id,
            proj.x,
            proj.y,
            "smoke_trail",
            {
                lifetime = 0.2,
                color = {1, 0.6, 0.2, 0.5}
            }
        )
    end
end

-- Damage enemy
function basicEnemiesMod.damageEnemy(enemy_id, damage, from_player, attacker_x, attacker_y)
    local enemy = nil
    for _, e in ipairs(enemies) do
        if e.id == enemy_id then
            enemy = e
            break
        end
    end
    
    if not enemy or not enemy.active then return end
    
    enemy.health = enemy.health - damage
    
    -- Use health/damage mod if available
    local health_mod = basicEnemiesMod.api.mods and basicEnemiesMod.api.mods.health_damage_mod
    if health_mod and health_mod.exports then
        health_mod.exports.onEntityDamage(enemy.id, enemy.x, enemy.y, damage, enemy.health, enemy.max_health, "enemy")
    else
        -- Fallback to basic indicators
        enemy.health_bar_visible = true
        enemy.health_bar_timer = 3.0
        
        local indicator = {
            damage = damage,
            x = enemy.x + math.random(-15, 15),
            y = enemy.y - 20,
            timer = 1.0,
            alpha = 1.0,
            color = damage > 20 and {1, 0.2, 0.2} or {1, 0.8, 0.2}
        }
        table.insert(enemy.damage_indicators, indicator)
    end
    
    -- Use blood effects mod if available
    local blood_mod = basicEnemiesMod.api.mods and basicEnemiesMod.api.mods.blood_effects_mod
    if blood_mod and blood_mod.exports then
        blood_mod.exports.onEntityDamage(enemy.id, enemy.x, enemy.y, damage, attacker_x, attacker_y)
    end
    
    -- Check death
    if enemy.health <= 0 then
        enemy.active = false
        basicEnemiesMod.handleEnemyDeath(enemy, from_player)
    end
    
    -- Sync damage
    if mod_config.enable_networking then
        basicEnemiesMod.syncEnemyDamage(enemy_id, damage, enemy.health, from_player)
    end
end

-- Handle enemy death
function basicEnemiesMod.handleEnemyDeath(enemy, from_player)
    -- Use blood effects mod for death if available
    local blood_mod = basicEnemiesMod.api.mods and basicEnemiesMod.api.mods.blood_effects_mod
    if blood_mod and blood_mod.exports then
        blood_mod.exports.onEntityDeath(enemy.id, enemy.x, enemy.y, enemy.max_health)
    end
    
    -- Hide health bar
    local health_mod = basicEnemiesMod.api.mods and basicEnemiesMod.api.mods.health_damage_mod
    if health_mod and health_mod.exports then
        health_mod.exports.hideHealthBar(enemy.id)
    end
    
    -- Drop items
    if math.random() < enemy.config.drop_chance then
        local drop_type = math.random() < 0.5 and "health" or "ammo"
        basicEnemiesMod.api.game.spawnPickup(enemy.x, enemy.y, drop_type)
    end
    
    -- Death particles
    if mod_config.enable_particles then
        basicEnemiesMod.api.renderer.addParticleEffect(
            "enemy_death_" .. enemy.id,
            enemy.x,
            enemy.y,
            "explosion",
            {
                lifetime = 1.0,
                color = {0.8, 0.2, 0.2, 1},
                count = 8
            }
        )
    end
    
    print("[BASIC_ENEMIES_MOD] Enemy " .. enemy.type .. " killed!")
end

-- Network synchronization
function basicEnemiesMod.syncEnemyCreation(enemy)
    local api = basicEnemiesMod.api
    api.network.sendToAll({
        action = "create_enemy",
        enemy_data = {
            id = enemy.id,
            x = enemy.x,
            y = enemy.y,
            type = enemy.type,
            health = enemy.health
        }
    }, "basic_enemies_mod")
end

function basicEnemiesMod.syncEnemyDamage(enemy_id, damage, new_health, from_player)
    local api = basicEnemiesMod.api
    api.network.sendToAll({
        action = "damage_enemy",
        enemy_id = enemy_id,
        damage = damage,
        new_health = new_health,
        from_player = from_player
    }, "basic_enemies_mod")
end

-- Handle network messages
function basicEnemiesMod.handleNetworkMessage(data)
    if data.action == "create_enemy" then
        local enemy_data = data.enemy_data
        basicEnemiesMod.createEnemy(enemy_data.x, enemy_data.y, enemy_data.type)
    elseif data.action == "damage_enemy" then
        basicEnemiesMod.damageEnemy(data.enemy_id, data.damage, data.from_player)
    end
end

-- Get collision handler
function basicEnemiesMod.getCollisionHandler()
    return function(fixture_data, other_fixture_data, contact)
        if fixture_data.type == "enemy_projectile" and other_fixture_data.type == "player" then
            -- Damage player
            basicEnemiesMod.api.game.damagePlayer(other_fixture_data.id, fixture_data.damage)
            
            -- Destroy projectile
            for _, proj in ipairs(projectiles) do
                if proj.id == fixture_data.id then
                    proj.active = false
                    break
                end
            end
        end
    end
end

-- Get mod statistics
function basicEnemiesMod.getStats()
    local stats = {
        total_enemies = #enemies,
        active_enemies = 0,
        enemies_by_type = {},
        active_projectiles = #projectiles
    }
    
    for _, enemy in ipairs(enemies) do
        if enemy.active then
            stats.active_enemies = stats.active_enemies + 1
            stats.enemies_by_type[enemy.type] = (stats.enemies_by_type[enemy.type] or 0) + 1
        end
    end
    
    return stats
end

-- Cleanup
function basicEnemiesMod.cleanup()
    -- Destroy all physics bodies
    for _, enemy in ipairs(enemies) do
        if enemy.body and not enemy.body:isDestroyed() then
            enemy.body:destroy()
        end
    end
    
    for _, proj in ipairs(projectiles) do
        if proj.body and not proj.body:isDestroyed() then
            proj.body:destroy()
        end
    end
    
    enemies = {}
    projectiles = {}
    enemy_counter = 0
    projectile_counter = 0
    
    print("[BASIC_ENEMIES_MOD] Cleanup complete")
end

-- Mod interface
return basicEnemiesMod