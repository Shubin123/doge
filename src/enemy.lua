local enemy = {}
enemy.scale = 0.6
enemy.t = 0
enemy.projectiles = {}
enemy.max_projectiles_per_enemy = 3
enemy.fire_cooldown = 2.0  -- seconds between shots
enemy.last_fire_times = {}  -- track when each enemy last fired
enemy.detection_range = 300  -- pixels
enemy.projectile_speed = 80
enemy_projectile_bodies = {}

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
    -- local fireImg = getFireSprite()
    
    -- Create particle system for enemy projectiles (different color/settings
    Quads = sprite:constructsprite(fireSpriteImg, 8, 8)
    print(fireSpriteImg)
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
        enemies_bods[i]:applyForce(0, 1)
        
        -- AI logic for each enemy
        enemy.updateEnemyAI(i, dt)
    end
    
    -- Update existing projectiles
    enemy.updateProjectiles(dt)
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
    
    -- Check if player is in range and enough time has passed since last shot
    local current_time = enemy.t
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
        local move_force = 30
        enemy_body:applyForce(dx/distance * move_force, dy/distance * move_force)
    elseif distance < ideal_distance - 50 then
        -- Move away from player
        local move_force = 20
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
        if player and player.body and not_enemy_proj:getBody() == player.body then
            -- Damage player or trigger player hit logic here
            -- print("Player hit by enemy fire!")
            player.health = player.health - 1
            -- You can add player damage logic here
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

-- Helper function to add new enemy (call when spawning enemies)
function enemy.addEnemy(enemy_index)
    enemy.last_fire_times[enemy_index] = enemy.t
end

-- Helper function to remove enemy data (call when enemy dies)
function enemy.removeEnemy(enemy_index)
    enemy.last_fire_times[enemy_index] = nil
end

return enemy