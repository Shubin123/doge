local enemy = {}
local physSafe = require 'src.util.physics_safe'
enemy.scale = 0.6
enemy.t = 0
enemy.projectiles = {}
enemy.max_projectiles_per_enemy = 30
enemy.fire_cooldown = 2.0  -- seconds between shots
enemy.last_fire_times = {}  -- track when each enemy last fired
enemy.detection_range = 300  -- pixels
enemy.projectile_speed = 400
enemy_projectile_bodies = {}

-- Health system
enemy.health = {}  -- health per enemy index
enemy.max_health = 100
-- damage indicators now handled by indicators module
enemy.enemy_damaged = {}  -- track which enemies have been damaged (for health bars)
enemy.noticed_player = {}  -- track which enemies have noticed the player
enemy.first_notice_time = {}  -- track when enemies first noticed player

-- Reuse the same fire sprite from the fire module
local function getFireSprite()
    -- if sprite.spriteImg then
    --     return spriteImg
    -- else
    --     return love.graphics.newImage('gfx/firelowres.png')
    -- end
     return love.graphics.newImage('gfx/firelowres.png')
end

function enemy.damageEnemy(enemy_index, damage)
    if not enemy.health[enemy_index] then
        enemy.health[enemy_index] = enemy.max_health
    end
    
    enemy.health[enemy_index] = enemy.health[enemy_index] - damage
    enemy.enemy_damaged[enemy_index] = true
    
    -- Create floating damage indicator using new modular system
    if enemies_bods[enemy_index] then
        local ex, ey = enemies_bods[enemy_index]:getPosition()
        
        -- Determine if this is a critical hit based on damage thresholds
        local is_mega_critical = damage >= 35
        local is_critical = damage >= 18
        
        indicators.createDamage(ex, ey, damage, is_critical, is_mega_critical)
        print("Created damage indicator:", damage, "at", ex, ey)
    end
    
    -- Check if enemy dies
    if enemy.health[enemy_index] <= 0 then
        enemy.killEnemy(enemy_index)
    end
end

function enemy.killEnemy(enemy_index)
    if enemies_bods[enemy_index] then
        enemies_bods[enemy_index]:destroy()
        table.remove(enemies_bods, enemy_index)
        
        -- Clean up all enemy tracking data
        enemy.health[enemy_index] = nil
        enemy.enemy_damaged[enemy_index] = nil
        enemy.last_fire_times[enemy_index] = nil
        enemy.noticed_player[enemy_index] = nil
        enemy.first_notice_time[enemy_index] = nil
        
        -- Shift indices for remaining enemies
        local new_health = {}
        local new_damaged = {}
        local new_fire_times = {}
        local new_noticed = {}
        local new_notice_times = {}
        for i = 1, #enemies_bods do
            if i < enemy_index then
                new_health[i] = enemy.health[i]
                new_damaged[i] = enemy.enemy_damaged[i]
                new_fire_times[i] = enemy.last_fire_times[i]
                new_noticed[i] = enemy.noticed_player[i]
                new_notice_times[i] = enemy.first_notice_time[i]
            else
                new_health[i] = enemy.health[i + 1]
                new_damaged[i] = enemy.enemy_damaged[i + 1]
                new_fire_times[i] = enemy.last_fire_times[i + 1]
                new_noticed[i] = enemy.noticed_player[i + 1]
                new_notice_times[i] = enemy.first_notice_time[i + 1]
            end
        end
        enemy.health = new_health
        enemy.enemy_damaged = new_damaged
        enemy.last_fire_times = new_fire_times
        enemy.noticed_player = new_noticed
        enemy.first_notice_time = new_notice_times
    end
end

function enemy.load()
    -- local fireImg = getFireSprite()
    
    -- Create particle system for enemy projectiles (different color/settings
    Quads = sprite:constructsprite(fireSpriteImg, 8, 8)
    enemy.particleSystem = love.graphics.newParticleSystem(fireSpriteImg, 200)
    
    -- ENEMY PROJECTILE CONFIGURATION (different from player fire)
    enemy.particleSystem:setParticleLifetime(0.8, 1.5)
    enemy.particleSystem:setEmissionRate(12)
    enemy.particleSystem:setSizeVariation(0.8)
    enemy.particleSystem:setDirection(1.5 * 3.14)
    enemy.particleSystem:setSpeed(10, 30)
    enemy.particleSystem:setLinearDamping(0.2)
    enemy.particleSystem:setSpin(-0.5, 0.5)
    enemy.particleSystem:setColors(255, 100, 50, 255, 255, 50, 0, 0.1)  -- Orange/red fire
    if Quads then
        enemy.particleSystem:setQuads(Quads)
    end
    enemy.particleSystem:setRotation(0, 2 * 3.14)
    enemy.particleSystem:setOffset(sprite:getTileSize())
    enemy.particleSystem:setInsertMode('bottom')
    
    -- Initialize fire times for existing enemies
    for i = 1, #enemies_bods do
        enemy.last_fire_times[i] = 0
    end
end

function enemy.update(dt)
    enemy.particleSystem:update(dt)
    enemy.t = enemy.t + dt
    
    -- Apply basic gravity/movement to enemies
    for i = 1, #enemies_bods do
        -- enemies_bods[i]:applyForce(0, 1)
        
        -- AI logic for each enemy
        enemy.updateEnemyAI(i, dt)
        
        -- Initialize health if not set
        if not enemy.health[i] then
            enemy.health[i] = enemy.max_health
        end
    end
    
    -- Update existing projectiles
    enemy.updateProjectiles(dt)
    
    -- Damage indicators are now handled by the indicators module
end

-- helpers
function enemy.updateEnemyAI(enemy_index, dt)
    if not enemies_bods[enemy_index] or not player or not player.body then
        return
    end
    
    local enemy_body = enemies_bods[enemy_index]
    local enemy_x, enemy_y = enemy_body:getPosition()
    local player_x, player_y = player.body:getPosition()
    
    -- Calculate distance to player
    local dx = player_x - enemy_x
    local dy = player_y - enemy_y
    local distance = math.sqrt(dx * dx + dy * dy)
    local current_time = enemy.t
    
    -- Check if enemy notices player for first time
    if distance <= enemy.detection_range and not enemy.noticed_player[enemy_index] then
        enemy.noticed_player[enemy_index] = true
        enemy.first_notice_time[enemy_index] = current_time
        -- Create "noticed" indicator
        indicators.createNoticed(enemy_x, enemy_y - 30, "!")
    end
    
    -- Check if player is in range and enough time has passed since last shot
    local last_fire = enemy.last_fire_times[enemy_index] or 0
    
    if distance <= enemy.detection_range and 
       (current_time - last_fire) >= enemy.fire_cooldown then
        
        -- Fire projectile at player
        enemy.fireAtPlayer(enemy_index, enemy_x, enemy_y, player_x, player_y)
        enemy.last_fire_times[enemy_index] = current_time
    end
    
    -- Simple movement AI - move slightly toward player if far, away if too close
    local ideal_distance = 150
    
    if distance > ideal_distance + 50 then
        -- Move toward player
        local move_force = 500
        enemy_body:applyForce(dx/distance * move_force, dy/distance * move_force)
    elseif distance < ideal_distance - 50 then
        -- Move away from player
        local move_force = 200
        enemy_body:applyForce(-dx/distance * move_force, -dy/distance * move_force)
    end
end

function enemy.fireAtPlayer(enemy_index, enemy_x, enemy_y, player_x, player_y)
    -- Calculate direction to player
    local dx = player_x - enemy_x
    local dy = player_y - enemy_y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    if distance == 0 then return end
    
    -- Normalize direction
    local dir_x = dx / distance
    local dir_y = dy / distance
    
    -- Create projectile data structure similar to fire.fireables
    local projectile = {
        vec2.new(enemy_x, enemy_y),  -- position
        vec2.new(dir_x * enemy.projectile_speed, dir_y * enemy.projectile_speed),  -- velocity
        true,  -- initialized
        enemy_index,  -- which enemy fired this
        enemy.t + 5.0  -- despawn time (5 seconds from now)
    }
    
    -- Create physics body for projectile
    local proj_body = love.physics.newBody(world, enemy_x, enemy_y, "dynamic")
    local proj_fixture = love.physics.newFixture(proj_body, love.physics.newCircleShape(15))
    proj_fixture:setGroupIndex(-777)  -- Different group from player fire (-1)
    
    table.insert(enemy.projectiles, projectile)
    table.insert(enemy_projectile_bodies, proj_body)
end

function enemy.updateProjectiles(dt)
    -- Update projectile positions and remove expired ones
    for i = #enemy.projectiles, 1, -1 do
        local proj = enemy.projectiles[i]
        
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
--
function enemy.populate()
    -- Add enemy projectiles to dynamic draw list
    for i = 1, #enemy.projectiles do
        local proj = enemy.projectiles[i]
        
        table.insert(dynamic_draw_list, {
            sort_y = proj[1].y + 140,
            image_or_particles = enemy.particleSystem,
            quad = nil,
            x = proj[1].x,
            y = proj[1].y,
            rotation = 0,
            scale_x = enemy.scale,
            scale_y = enemy.scale,
            offset_x = 0,
            offset_y = 0,
            color = {1, 0.4, 0.2, 1},  -- Orange tint for enemy fire
            blend_mode = {"lighten", "premultiplied"},
            source_object_type = "enemy_fire_effect"
        })
    end
    
    -- Damage indicators are now handled by the indicators module
    
    -- Add health bars for damaged enemies
    for i = 1, #enemies_bods do
        if enemy.enemy_damaged[i] and enemy.health[i] and enemy.health[i] > 0 then
            local ex, ey = enemies_bods[i]:getPosition()
            local health_percent = enemy.health[i] / enemy.max_health
            
            -- Health bar background
            table.insert(dynamic_draw_list, {
                sort_y = ey - 50,
                rectangle = {x = ex - 25, y = ey - 35, width = 50, height = 6},
                color = {0.2, 0.2, 0.2, 0.8},  -- Dark background
                blend_mode = {"alpha"},
                source_object_type = "health_bar_bg"
            })
            
            -- Health bar fill
            table.insert(dynamic_draw_list, {
                sort_y = ey - 49,
                rectangle = {x = ex - 24, y = ey - 34, width = 48 * health_percent, height = 4},
                color = health_percent > 0.3 and {0.2, 0.8, 0.2, 0.9} or {0.8, 0.2, 0.2, 0.9},  -- Green or red
                blend_mode = {"alpha"},
                source_object_type = "health_bar_fill"
            })
        end
    end
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
    
    if  enemy_proj_fixture  ~= nil then
        -- Enemy projectile hit something
        local proj_body = enemy_proj_fixture:getBody()
        
        -- Check if it hit the player
        if (var.multiplayer == 1 or not var.multiplayer) then
        if player and player.body and not_enemy_proj:getGroupIndex() == -1 then
            -- Add blood effect at player hit location
            local x, y = player.body:getPosition()
            if blood and blood.onEnemyDamage then
                blood.onEnemyDamage(x, y, 1)
            end
            
            -- Damage player or trigger player hit logic here
            -- print("Player hit by enemy fire! or collided with enemy", not_enemy_proj:getBody())
            -- print(player.online.bodies)
            local hit_client = false -- for every collision check through client bodies if the collision was made was it then dont hit the player aswell
            for k,body in pairs(player.online.bodies) do
            -- print(body == not_enemy_proj:getBody())
                if body == not_enemy_proj:getBody() then
            -- player.health = player.health - 1
                    -- print(k)
                    -- game_state
                       player.online.health[k] =  player.online.health[k] - 1
                    hit_client = true
                    
                    -- Add blood effect for online players
                    local px, py = body:getPosition()
                    if blood and blood.onEnemyDamage then
                        blood.onEnemyDamage(px, py, 1)
                    end
                end

            end
            if not hit_client then
                if not player.god then
                    player.health = player.health - 1
                end
            end
            -- You can add player damage logic here
        end
        end

        
        -- Remove the projectile
        for i = #enemy_projectile_bodies, 1, -1 do
            if enemy_projectile_bodies[i] == proj_body then
                proj_body:destroy()
                table.remove(enemy_projectile_bodies, i)
                table.remove(enemy.projectiles, i)
                break
            end
        end
    end
end

-- Helper function to spawn a new enemy on the map
function enemy.addEnemy(x, y)
    -- Create new enemy physics body
    local enemy_body = love.physics.newBody(world, x, y, "dynamic")
    local enemy_fixture = love.physics.newFixture(enemy_body, love.physics.newCircleShape(25))
    enemy_fixture:setGroupIndex(-777)
    
    -- Set enemy mass and physics properties for proper knockback
    enemy_fixture:setDensity(2.0)  -- Give enemies substantial mass
    enemy_body:resetMassData()  -- Apply the density changes
    enemy_body:setLinearDamping(3.0)  -- Add damping so they don't slide forever
    enemy_body:setAngularDamping(5.0)  -- Prevent excessive spinning
    
    -- Add to enemies_bods table
    table.insert(enemies_bods, enemy_body)
    local enemy_index = #enemies_bods
    
    -- Initialize fire timing for this enemy
    enemy.last_fire_times[enemy_index] = enemy.t - enemy.fire_cooldown -- Allow immediate firing
    
    -- Initialize health for this enemy
    enemy.health[enemy_index] = enemy.max_health
    enemy.enemy_damaged[enemy_index] = false
    
    -- Initialize noticed state for this enemy
    enemy.noticed_player[enemy_index] = false
    enemy.first_notice_time[enemy_index] = nil
    
    return enemy_index, enemy_body
end

-- Apply knockback force to an enemy
function enemy.applyKnockback(enemy_index, source_x, source_y, force_multiplier)
    if not enemies_bods[enemy_index] then return end
    
    local enemy_body = enemies_bods[enemy_index]
    local ex, ey = physSafe.safeGetPosition(enemy_body)
    
    if ex and ey then
        -- Calculate knockback direction from source to enemy
        local dx = ex - source_x
        local dy = ey - source_y
        local distance = math.sqrt(dx*dx + dy*dy)
        
        if distance > 0 then
            local knockback_x = (dx / distance) * force_multiplier
            local knockback_y = (dy / distance) * force_multiplier
            
            -- Apply the knockback force to the enemy using safe method
            physSafe.safeApplyImpulse(enemy_body, knockback_x, knockback_y)
        end
    end
end

-- Helper function to remove enemy data (call when enemy dies)
function enemy.removeEnemy(enemy_index)
    enemy.last_fire_times[enemy_index] = nil
    enemy.health[enemy_index] = nil
    enemy.enemy_damaged[enemy_index] = nil
    enemy.noticed_player[enemy_index] = nil
    enemy.first_notice_time[enemy_index] = nil
end

return enemy