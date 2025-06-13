local boss = {}

-- Boss configuration
boss.scale = 1.8  -- Final adjustment to better match game scale
boss.t = 0
boss.bosses = {} -- All boss instances
boss.boss_bodies = {} -- Physics bodies for bosses

-- Health system
boss.max_health = 500
boss.damage_flash_duration = 0.15

-- Movement configuration  
boss.hop_distance = 0.25  -- Reduced from 150
boss.hop_prepare_time = 1.5 -- Time for squish and shake animation
boss.hop_duration = 0.4
boss.hop_cooldown = 2.5
boss.ground_pound_radius = 30  -- Reduced from 200
boss.ground_pound_damage = 50

-- Laser configuration
boss.laser_charge_time = 2.0
boss.laser_duration = 1.5
boss.laser_damage = 25
boss.laser_width = 5  -- Reduced from 30
boss.laser_cooldown = 4.0

-- Animation states
boss.STATES = {
    IDLE = "idle",
    PREPARING_HOP = "preparing_hop", 
    HOPPING = "hopping",
    LANDING = "landing",
    CHARGING_LASER = "charging_laser",
    FIRING_LASER = "firing_laser"
}

-- Sprite assets
boss.sprites = {}
boss.current_sprites = {}

-- Particle systems
boss.landing_particles = {}
boss.laser_charge_particles = {}

function boss.load()
    -- Load boss sprites
    local sprite_path = 'gfx/EnemiesSpriteSheets/BearBoss/'
    boss.sprites.default = love.graphics.newImage(sprite_path .. 'bear_enemy_default_state.png')
    boss.sprites.threatening = love.graphics.newImage(sprite_path .. 'bear_enemy_laser_threatening.png')
    boss.sprites.shooting = love.graphics.newImage(sprite_path .. 'bear_enemy_laser_shooting.png')
    
    -- Create particle system for landing impact
    local dustImg = love.graphics.newImage('gfx/EnemiesSpriteSheets/BearBoss/bear_dust_landing.png')
    boss.landing_particle_system = love.graphics.newParticleSystem(dustImg, 100)
    boss.landing_particle_system:setParticleLifetime(0.3, 0.6)
    boss.landing_particle_system:setEmissionRate(0) -- Burst emission
    boss.landing_particle_system:setSizeVariation(1)
    boss.landing_particle_system:setSpeed(50, 150)  -- Reduced from 100, 300
    boss.landing_particle_system:setSpread(2 * math.pi)
    boss.landing_particle_system:setColors(
        0.6, 0.5, 0.4, 1,  -- Brown dust
        0.5, 0.4, 0.3, 0.5,
        0.4, 0.3, 0.2, 0
    )
    boss.landing_particle_system:setSizes(1, 2, 0.5)  -- Reduced from 2, 4, 1
    boss.landing_particle_system:setLinearDamping(3)
    
    -- Create particle system for laser charging
    local laser_charge_sprite = love.graphics.newImage('gfx/EnemiesSpriteSheets/BearBoss/laser_charging_particles.png')
    boss.laser_charge_particle_system = love.graphics.newParticleSystem(laser_charge_sprite, 50)
    boss.laser_charge_particle_system:setParticleLifetime(0.3, 0.5)
    boss.laser_charge_particle_system:setEmissionRate(30)
    boss.laser_charge_particle_system:setSizeVariation(0.5)
    boss.laser_charge_particle_system:setSpeed(50, 100)
    boss.laser_charge_particle_system:setColors(
        1, 0.2, 0.2, 1,    -- Red
        1, 0.5, 0.2, 0.8,  -- Orange
        1, 1, 0.2, 0       -- Yellow fade
    )
    boss.laser_charge_particle_system:setSizes(0.3, 0.6, 0.2)  -- Reduced from 0.5, 1, 0.3
    boss.laser_charge_particle_system:setRadialAcceleration(-100, -50)
    
    -- Create particle system for laser beam
    boss.laser_beam_particle_system = love.graphics.newParticleSystem(laser_charge_sprite, 200)
    boss.laser_beam_particle_system:setParticleLifetime(0.3, 0.5)  -- Increased from 0.1, 0.2
    boss.laser_beam_particle_system:setEmissionRate(200)  -- Increased from 100
    boss.laser_beam_particle_system:setSizeVariation(0.3)
    boss.laser_beam_particle_system:setSpeed(1200, 1500)  -- Increased for faster beam
    boss.laser_beam_particle_system:setSpread(0.05) -- Very tight beam
    boss.laser_beam_particle_system:setColors(
        1, 0.2, 0.2, 1,    -- Red
        1, 0.5, 0.2, 0.8,  -- Orange
        1, 0.8, 0.2, 0     -- Yellow fade
    )
    boss.laser_beam_particle_system:setSizes(1, 0.7, 0.3)  -- Reduced from 1.5, 1, 0.5
    boss.laser_beam_particle_system:setLinearDamping(0)
    boss.laser_beam_particle_system:setLinearAcceleration(0, 0, 0, 0) -- No gravity
    
    -- Create shockwave particle system using the same dust texture
    boss.shockwave_particle_system = love.graphics.newParticleSystem(dustImg, 50)
    boss.shockwave_particle_system:setParticleLifetime(0.5, 0.7)
    boss.shockwave_particle_system:setEmissionRate(0)
    boss.shockwave_particle_system:setSizeVariation(1)
    boss.shockwave_particle_system:setSpeed(100, 200)
    boss.shockwave_particle_system:setSpread(2 * math.pi)
    boss.shockwave_particle_system:setColors(1, 1, 1, 1, 1, 1, 1, 0.5, 1, 1, 1, 0)
    boss.shockwave_particle_system:setSizes(1, 2, 0.5)
    boss.shockwave_particle_system:setLinearDamping(3)
end

-- Network support for client spawn requests
boss.pending_spawn_request = nil

function boss.requestSpawn(x, y)
    if var.multiplayer and var.multiplayer ~= 1 then
        -- Client: store spawn request to send to host
        boss.pending_spawn_request = {x = x, y = y}
        return "spawn_requested"
    else
        -- Host or single player: spawn directly
        return boss.spawn(x, y)
    end
end

function boss.getPendingSpawnRequest()
    local request = boss.pending_spawn_request
    boss.pending_spawn_request = nil
    return request
end

function boss.spawn(x, y)
    -- Generate unique ID
    local boss_id = 1
    while boss.bosses[boss_id] do
        boss_id = boss_id + 1
    end
    
    -- Create physics body
    local body = love.physics.newBody(world, x, y, "dynamic")
    local shape = love.physics.newCircleShape(30) -- Reduced from 60 to match scale
    local fixture = love.physics.newFixture(body, shape)
    fixture:setGroupIndex(-888) -- Unique group for bosses
    fixture:setDensity(10.0) -- Very heavy
    body:resetMassData()
    body:setLinearDamping(5.0)
    body:setAngularDamping(10.0)
    
    -- Create boss instance
    local new_boss = {
        id = boss_id,
        body = body,
        fixture = fixture,
        health = boss.max_health,
        max_health = boss.max_health,
        state = boss.STATES.IDLE,
        state_timer = 0,
        facing_right = true,
        
        -- Movement data
        hop_target_x = x,
        hop_target_y = y,
        hop_start_x = x,
        hop_start_y = y,
        last_hop_time = 0,
        squish_amount = 1.0,
        shake_offset_x = 0,
        shake_offset_y = 0,
        
        -- Laser data
        laser_target_x = 0,
        laser_target_y = 0,
        laser_angle = 0,
        last_laser_time = 0,
        laser_charge_amount = 0,
        laser_damage = boss.laser_damage,
        
        -- Visual effects
        damage_flash_timer = 0,
        particle_emitters = {
            landing = love.graphics.newParticleSystem(boss.landing_particle_system:getTexture(), 100),
            laser_charge = love.graphics.newParticleSystem(boss.laser_charge_particle_system:getTexture(), 50),
            laser_beam = love.graphics.newParticleSystem(boss.laser_beam_particle_system:getTexture(), 200),
            shockwave = love.graphics.newParticleSystem(boss.shockwave_particle_system:getTexture(), 50)
        }
    }
    
    -- Copy particle settings
    new_boss.particle_emitters.landing:setParticleLifetime(0.3, 0.6)
    new_boss.particle_emitters.landing:setEmissionRate(0)
    new_boss.particle_emitters.landing:setSizeVariation(1)
    new_boss.particle_emitters.landing:setSpeed(50, 150)
    new_boss.particle_emitters.landing:setSpread(2 * math.pi)
    new_boss.particle_emitters.landing:setColors(0.6, 0.5, 0.4, 1, 0.5, 0.4, 0.3, 0.5, 0.4, 0.3, 0.2, 0)
    new_boss.particle_emitters.landing:setSizes(1, 2, 0.5)
    new_boss.particle_emitters.landing:setLinearDamping(3)
    
    new_boss.particle_emitters.laser_charge:setParticleLifetime(0.3, 0.5)
    new_boss.particle_emitters.laser_charge:setEmissionRate(0)
    new_boss.particle_emitters.laser_charge:setSizeVariation(0.5)
    new_boss.particle_emitters.laser_charge:setSpeed(50, 100)
    new_boss.particle_emitters.laser_charge:setColors(1, 0.2, 0.2, 1, 1, 0.5, 0.2, 0.8, 1, 1, 0.2, 0)
    new_boss.particle_emitters.laser_charge:setSizes(0.3, 0.6, 0.2)
    new_boss.particle_emitters.laser_charge:setRadialAcceleration(-100, -50)
    
    new_boss.particle_emitters.laser_beam:setParticleLifetime(0.3, 0.5)
    new_boss.particle_emitters.laser_beam:setEmissionRate(0)
    new_boss.particle_emitters.laser_beam:setSizeVariation(0.3)
    new_boss.particle_emitters.laser_beam:setSpeed(1200, 1500)
    new_boss.particle_emitters.laser_beam:setSpread(0.05)
    new_boss.particle_emitters.laser_beam:setColors(1, 0.2, 0.2, 1, 1, 0.5, 0.2, 0.8, 1, 0.8, 0.2, 0)
    new_boss.particle_emitters.laser_beam:setSizes(1, 0.7, 0.3)
    new_boss.particle_emitters.laser_beam:setLinearDamping(0)
    new_boss.particle_emitters.laser_beam:setLinearAcceleration(0, 0, 0, 0)
    
    new_boss.particle_emitters.shockwave:setParticleLifetime(0.5, 0.7)
    new_boss.particle_emitters.shockwave:setEmissionRate(0)
    new_boss.particle_emitters.shockwave:setSizeVariation(1)
    new_boss.particle_emitters.shockwave:setSpeed(100, 200)
    new_boss.particle_emitters.shockwave:setSpread(2 * math.pi)
    new_boss.particle_emitters.shockwave:setColors(1, 1, 1, 1, 1, 1, 1, 0.5, 1, 1, 1, 0)
    new_boss.particle_emitters.shockwave:setSizes(1, 2, 0.5)
    new_boss.particle_emitters.shockwave:setLinearDamping(3)
    
    boss.bosses[boss_id] = new_boss
    boss.boss_bodies[boss_id] = body
    
    return boss_id
end

function boss.despawn(boss_id)
    local boss_instance = boss.bosses[boss_id]
    if boss_instance then
        -- Destroy physics body
        if boss_instance.body then
            boss_instance.body:destroy()
        end
        
        -- Clean up
        boss.bosses[boss_id] = nil
        boss.boss_bodies[boss_id] = nil
        
        return true
    end
    return false
end

function boss.despawnAll()
    for id, _ in pairs(boss.bosses) do
        boss.despawn(id)
    end
end

function boss.update(dt)
    boss.t = boss.t + dt
    
    for id, boss_instance in pairs(boss.bosses) do
        if boss_instance then
            boss.updateBoss(boss_instance, dt)
        end
    end
end

function boss.updateBoss(boss_instance, dt)
    -- Update timers
    boss_instance.state_timer = boss_instance.state_timer + dt
    boss_instance.damage_flash_timer = math.max(0, boss_instance.damage_flash_timer - dt)
    
    -- Update particle systems
    boss_instance.particle_emitters.landing:update(dt)
    boss_instance.particle_emitters.laser_charge:update(dt)
    boss_instance.particle_emitters.laser_beam:update(dt)
    boss_instance.particle_emitters.shockwave:update(dt)
    
    -- Get boss position
    local bx, by = boss_instance.body:getPosition()
    
    -- Find nearest player
    local target_x, target_y = boss.findNearestPlayer(bx, by)
    
    -- Update facing direction
    if target_x then
        boss_instance.facing_right = target_x > bx
    end
    
    -- Calculate rage factor based on health loss
    local rage_factor = 1 - (boss_instance.health / boss_instance.max_health)
    local effective_hop_cooldown = boss.hop_cooldown * (1 - 0.5 * rage_factor)
    local effective_laser_cooldown = boss.laser_cooldown * (1 - 0.5 * rage_factor)
    local effective_ground_pound_damage = boss.ground_pound_damage * (1 + rage_factor)
    local effective_laser_damage = boss.laser_damage * (1 + rage_factor)
    boss_instance.laser_damage = effective_laser_damage -- Update instance damage
    
    -- State machine
    if boss_instance.state == boss.STATES.IDLE then
        -- Decide next action
        local time_since_hop = boss.t - boss_instance.last_hop_time
        local time_since_laser = boss.t - boss_instance.last_laser_time
        
        if time_since_hop > effective_hop_cooldown and target_x then
            -- Start hop sequence
            boss_instance.state = boss.STATES.PREPARING_HOP
            boss_instance.state_timer = 0
            boss_instance.hop_target_x = target_x
            boss_instance.hop_target_y = target_y
            boss_instance.hop_start_x = bx
            boss_instance.hop_start_y = by
        elseif time_since_laser > effective_laser_cooldown and target_x then
            -- Start laser sequence
            boss_instance.state = boss.STATES.CHARGING_LASER
            boss_instance.state_timer = 0
            boss_instance.laser_target_x = target_x
            boss_instance.laser_target_y = target_y
            boss_instance.laser_angle = math.atan2(target_y - by, target_x - bx)
            boss_instance.particle_emitters.laser_charge:setEmissionRate(30)
        end
        
    elseif boss_instance.state == boss.STATES.PREPARING_HOP then
        -- Squish and shake animation
        local progress = boss_instance.state_timer / boss.hop_prepare_time
        
        -- Squish effect (compress vertically)
        boss_instance.squish_amount = 1.0 - (progress * 0.3)
        
        -- Shake effect (intensifies over time)
        local shake_intensity = progress * 5  -- Reduced from 10
        boss_instance.shake_offset_x = (math.random() - 0.5) * shake_intensity
        boss_instance.shake_offset_y = (math.random() - 0.5) * shake_intensity
        
        if boss_instance.state_timer >= boss.hop_prepare_time then
            -- Start hopping
            boss_instance.state = boss.STATES.HOPPING
            boss_instance.state_timer = 0
            boss_instance.last_hop_time = boss.t
            
            -- Calculate hop vector
            local dx = boss_instance.hop_target_x - boss_instance.hop_start_x
            local dy = boss_instance.hop_target_y - boss_instance.hop_start_y
            local dist = math.sqrt(dx*dx + dy*dy)
            local hop_dist = math.min(dist, boss.hop_distance)
            
            -- Apply hop impulse
            local hop_power = 800
            local vx = (dx / dist) * hop_dist * hop_power / boss.hop_duration
            local vy = ((dy / dist) * hop_dist * hop_power / boss.hop_duration) - 400 -- Add upward arc
            boss_instance.body:setLinearVelocity(vx, vy)
        end
        
    elseif boss_instance.state == boss.STATES.HOPPING then
        -- Reset visual effects during hop
        boss_instance.squish_amount = 1.0
        boss_instance.shake_offset_x = 0
        boss_instance.shake_offset_y = 0
        
        if boss_instance.state_timer >= boss.hop_duration then
            -- Landing
            boss_instance.state = boss.STATES.LANDING
            boss_instance.state_timer = 0
            
            -- Create landing impact
            boss.createLandingImpact(boss_instance)
        end
        
    elseif boss_instance.state == boss.STATES.LANDING then
        boss_instance.ground_pound_damage = effective_ground_pound_damage -- Update damage on landing
        if boss_instance.state_timer >= 0.5 then
            boss_instance.state = boss.STATES.IDLE
            boss_instance.state_timer = 0
        end
        
    elseif boss_instance.state == boss.STATES.CHARGING_LASER then
        -- Charge laser
        boss_instance.laser_charge_amount = boss_instance.state_timer / boss.laser_charge_time
        
        -- Update particle position for laser charging
        local eye_offset_x = boss_instance.facing_right and 15 or -15  -- Reduced from 30
        boss_instance.particle_emitters.laser_charge:setPosition(bx + eye_offset_x, by - 10)  -- Adjusted Y offset
        
        if boss_instance.state_timer >= boss.laser_charge_time then
            -- Fire laser
            boss_instance.state = boss.STATES.FIRING_LASER
            boss_instance.state_timer = 0
            boss_instance.last_laser_time = boss.t
            boss_instance.particle_emitters.laser_charge:setEmissionRate(0)
        end
        
    elseif boss_instance.state == boss.STATES.FIRING_LASER then
        -- Update laser beam particles
        local eye_offset_x = boss_instance.facing_right and 15 or -15  -- Reduced from 30
        boss_instance.particle_emitters.laser_beam:setPosition(bx + eye_offset_x, by - 10)  -- Adjusted Y offset
        boss_instance.particle_emitters.laser_beam:setDirection(boss_instance.laser_angle)
        boss_instance.particle_emitters.laser_beam:setEmissionRate(200)  -- Increased from 100
        
        -- Check for laser hits
        boss.checkLaserHits(boss_instance)
        
        if boss_instance.state_timer >= boss.laser_duration then
            boss_instance.state = boss.STATES.IDLE
            boss_instance.state_timer = 0
            boss_instance.laser_charge_amount = 0
            boss_instance.particle_emitters.laser_beam:setEmissionRate(0)
        end
    end
end

function boss.findNearestPlayer(bx, by)
    local nearest_dist = math.huge
    local target_x, target_y = nil, nil
    
    -- Check local player
    if player and player.body then
        local px, py = player.body:getPosition()
        local dist = math.sqrt((px - bx)^2 + (py - by)^2)
        if dist < nearest_dist then
            nearest_dist = dist
            target_x, target_y = px, py
        end
    end
    
    -- Check online players in multiplayer
    if player.online and player.online.bodies then
        for _, body in pairs(player.online.bodies) do
            if body then
                local px, py = body:getPosition()
                local dist = math.sqrt((px - bx)^2 + (py - by)^2)
                if dist < nearest_dist then
                    nearest_dist = dist
                    target_x, target_y = px, py
                end
            end
        end
    end
    
    return target_x, target_y
end

function boss.createLandingImpact(boss_instance)
    local bx, by = boss_instance.body:getPosition()
    
    -- Emit shockwave particles
    boss_instance.particle_emitters.shockwave:setPosition(bx, by + 20)
    boss_instance.particle_emitters.shockwave:emit(20)
    
    -- Emit dust particles at ground level
    boss_instance.particle_emitters.landing:setPosition(bx, by + 20)  -- Adjusted offset
    boss_instance.particle_emitters.landing:emit(30)  -- Reduced particle count
    
    -- Apply damage to nearby players (use effective damage based on rage)
    local damage = boss_instance.ground_pound_damage or boss.ground_pound_damage
    boss.applyAreaDamage(bx, by, boss.ground_pound_radius, damage)
    
    -- Screen shake effect (if implemented in your game)
    if camera and camera.shake then
        camera.shake(0.3, 10)
    end
end

function boss.applyAreaDamage(x, y, radius, damage)
    -- Use the passed damage parameter instead of the global boss.ground_pound_damage
    -- Damage local player
    if player and player.body then
        local px, py = player.body:getPosition()
        local dist = math.sqrt((px - x)^2 + (py - y)^2)
        if dist <= radius then
            player.health = player.health - damage
            -- Add visual feedback
            if blood and blood.onEnemyDamage then
                blood.onEnemyDamage(px, py, damage / 10)
            end
        end
    end
    
    -- Damage online players
    if player.online and player.online.bodies and player.online.health then
        for k, body in pairs(player.online.bodies) do
            if body then
                local px, py = body:getPosition()
                local dist = math.sqrt((px - x)^2 + (py - y)^2)
                if dist <= radius then
                    player.online.health[k] = player.online.health[k] - damage
                    if blood and blood.onEnemyDamage then
                        blood.onEnemyDamage(px, py, damage / 10)
                    end
                end
            end
        end
    end
end

function boss.checkLaserHits(boss_instance)
    local bx, by = boss_instance.body:getPosition()
    local eye_offset_x = boss_instance.facing_right and 15 or -15  -- Reduced from 30
    local start_x = bx + eye_offset_x
    local start_y = by - 10  -- Adjusted Y offset
    
    -- Calculate laser end point
    local laser_length = 1000
    local end_x = start_x + math.cos(boss_instance.laser_angle) * laser_length
    local end_y = start_y + math.sin(boss_instance.laser_angle) * laser_length
    
    -- Check collision with players using raycasting
    world:rayCast(start_x, start_y, end_x, end_y, function(fixture, x, y, xn, yn, fraction)
        -- Check if hit player
        if fixture:getGroupIndex() == -1 then -- Player group
            -- Apply laser damage
            if player and player.body and fixture:getBody() == player.body then
                player.health = player.health - boss_instance.laser_damage
                if blood and blood.onEnemyDamage then
                    blood.onEnemyDamage(x, y, boss_instance.laser_damage / 10)
                end
            end
            
            -- Check online players
            if player.online and player.online.bodies then
                for k, body in pairs(player.online.bodies) do
                    if body == fixture:getBody() then
                        player.online.health[k] = player.online.health[k] - boss_instance.laser_damage
                        if blood and blood.onEnemyDamage then
                            blood.onEnemyDamage(x, y, boss_instance.laser_damage / 10)
                        end
                    end
                end
            end
            
            -- Add impact particles at hit location
            boss_instance.particle_emitters.landing:setPosition(x, y)
            boss_instance.particle_emitters.landing:emit(10)
            
            return 0 -- Stop at first hit
        end
        return 1 -- Continue
    end)
end

function boss.damage(boss_id, damage)
    local boss_instance = boss.bosses[boss_id]
    if not boss_instance then return end
    
    boss_instance.health = math.max(0, boss_instance.health - damage)
    boss_instance.damage_flash_timer = boss.damage_flash_duration
    
    -- Create damage indicator
    if enemy and enemy.damage_indicators then
        local bx, by = boss_instance.body:getPosition()
        table.insert(enemy.damage_indicators, {
            x = bx + math.random(-30, 30),
            y = by - 60,
            damage = damage,
            time = 0,
            duration = 1.0,
            velocity_y = -100,
            velocity_x = math.random(-20, 20),
            alpha = 1,
            scale = 1.5,
            bounce_factor = 0.95,
            nearby_count = 0
        })
    end
    
    -- Check if boss dies
    if boss_instance.health <= 0 then
        boss.kill(boss_id)
    end
end

function boss.kill(boss_id)
    -- Create death effects here if needed
    boss.despawn(boss_id)
end

-- Rendering
function boss.populate()
    local boss_count = 0
    for id, _ in pairs(boss.bosses) do
        boss_count = boss_count + 1
    end
    
    -- Remove debug prints after testing
    -- if boss_count > 0 then
    --     print("Boss populate: rendering", boss_count, "bosses")
    -- end
    
    for id, boss_instance in pairs(boss.bosses) do
        local bx, by = boss_instance.body:getPosition()
        -- print("Rendering boss", id, "at", bx, by)  -- Debug line, commented out
        
        -- Add shake offset
        local render_x = bx + boss_instance.shake_offset_x
        local render_y = by + boss_instance.shake_offset_y
        
        -- Determine sprite based on state
        local sprite = boss.sprites.default
        if boss_instance.state == boss.STATES.CHARGING_LASER then
            sprite = boss.sprites.threatening
        elseif boss_instance.state == boss.STATES.FIRING_LASER then
            sprite = boss.sprites.shooting
        end
        
        -- Calculate color (flash red when damaged)
        local color = {1, 1, 1, 1}
        if boss_instance.damage_flash_timer > 0 then
            local flash_intensity = boss_instance.damage_flash_timer / boss.damage_flash_duration
            color = {1, 1 - flash_intensity * 0.7, 1 - flash_intensity * 0.7, 1}
        end
        
        -- Calculate rage factor for visual effects
        local rage_factor = 1 - (boss_instance.health / boss_instance.max_health)
        
        -- Add rage glow effect behind boss if angry
        if rage_factor > 0 then
            table.insert(dynamic_draw_list, {
                sort_y = render_y + 99,
                image_or_particles = sprite,
                x = render_x,
                y = render_y,
                rotation = 0,
                scale_x = (boss_instance.facing_right and boss.scale or -boss.scale) * (1 + rage_factor * 0.2),
                scale_y = boss.scale * boss_instance.squish_amount * (1 + rage_factor * 0.2),
                offset_x = sprite:getWidth() / 2,
                offset_y = sprite:getHeight() / 2,
                color = {1, 0, 0, rage_factor * 0.3},
                blend_mode = {"add"},
                source_object_type = "boss_glow"
            })
        end
        
        -- Add boss sprite to draw list
        table.insert(dynamic_draw_list, {
            sort_y = render_y + 100,
            image_or_particles = sprite,
            quad = nil,
            x = render_x,
            y = render_y,
            rotation = 0,
            scale_x = boss_instance.facing_right and boss.scale or -boss.scale,
            scale_y = boss.scale * boss_instance.squish_amount,
            offset_x = sprite:getWidth() / 2,
            offset_y = sprite:getHeight() / 2,
            color = color,
            blend_mode = {"alpha"},
            source_object_type = "boss"
        })
        
        -- Draw laser
        if boss_instance.state == boss.STATES.CHARGING_LASER then
            -- Draw laser targeting line
            local eye_offset_x = boss_instance.facing_right and 15 or -15
            local start_x = render_x + eye_offset_x
            local start_y = render_y - 10
            local end_x = start_x + math.cos(boss_instance.laser_angle) * 1000
            local end_y = start_y + math.sin(boss_instance.laser_angle) * 1000
            table.insert(dynamic_draw_list, {
                sort_y = render_y + 95,
                line = {start_x, start_y, end_x, end_y},
                color = {1, 0, 0, 0.3},
                width = 1,
                blend_mode = {"alpha"},
                source_object_type = "laser_targeting"
            })
        end
        
        if boss_instance.state == boss.STATES.FIRING_LASER then
            -- Draw solid laser beam
            local eye_offset_x = boss_instance.facing_right and 15 or -15
            local start_x = render_x + eye_offset_x
            local start_y = render_y - 10
            local end_x = start_x + math.cos(boss_instance.laser_angle) * 1000
            local end_y = start_y + math.sin(boss_instance.laser_angle) * 1000
            table.insert(dynamic_draw_list, {
                sort_y = render_y + 95,
                line = {start_x, start_y, end_x, end_y},
                color = {1, 0, 0, 0.7},
                width = boss.laser_width,
                blend_mode = {"add"},
                source_object_type = "laser_beam"
            })
            
            -- Draw laser beam particles
            table.insert(dynamic_draw_list, {
                sort_y = render_y + 95,
                image_or_particles = boss_instance.particle_emitters.laser_beam,
                blend_mode = {"add"},
                source_object_type = "boss_laser_particles"
            })
        end
        
        -- Draw particles
        table.insert(dynamic_draw_list, {
            sort_y = render_y + 150,
            image_or_particles = boss_instance.particle_emitters.landing,
            x = render_x,
            y = render_y,
            color = {1, 1, 1, 1},
            blend_mode = {"alpha"},
            source_object_type = "boss_particles"
        })
        
        table.insert(dynamic_draw_list, {
            sort_y = render_y + 90,
            image_or_particles = boss_instance.particle_emitters.laser_charge,
            x = render_x,
            y = render_y,
            color = {1, 1, 1, 1},
            blend_mode = {"add"},
            source_object_type = "boss_particles"
        })
        
        -- Draw shockwave particles
        table.insert(dynamic_draw_list, {
            sort_y = render_y + 145,
            image_or_particles = boss_instance.particle_emitters.shockwave,
            x = render_x,
            y = render_y,
            color = {1, 1, 1, 1},
            blend_mode = {"alpha"},
            source_object_type = "boss_shockwave"
        })
        
        -- Draw health bar
        local health_percent = boss_instance.health / boss_instance.max_health
        local bar_width = 60  -- Reduced from 120
        local bar_height = 8   -- Reduced from 12
        local bar_y = render_y - 60  -- Adjusted position
        
        -- Health bar background
        table.insert(dynamic_draw_list, {
            sort_y = bar_y,
            rectangle = {
                x = render_x - bar_width/2,
                y = bar_y,
                width = bar_width,
                height = bar_height
            },
            color = {0.2, 0.2, 0.2, 0.8},
            blend_mode = {"alpha"},
            source_object_type = "health_bar_bg"
        })
        
        -- Health bar fill
        table.insert(dynamic_draw_list, {
            sort_y = bar_y + 1,
            rectangle = {
                x = render_x - bar_width/2 + 1,
                y = bar_y + 1,
                width = (bar_width - 2) * health_percent,
                height = bar_height - 2
            },
            color = health_percent > 0.3 and {0.8, 0.2, 0.2, 0.9} or {1, 0, 0, 0.9},
            blend_mode = {"alpha"},
            source_object_type = "health_bar_fill"
        })
        
        -- Boss name
        table.insert(dynamic_draw_list, {
            sort_y = bar_y - 5,
            text = "BEAR BOSS",
            x = render_x - 25,  -- Adjusted offset for smaller text
            y = bar_y - 15,
            font = gameFont,
            color = {1, 1, 1, 0.9},
            scale = 0.8,  -- Reduced from 1.2
            outline_color = {0, 0, 0, 0.9},
            source_object_type = "damage_indicator"  -- Use existing text handler
        })
    end
end

-- Network data for multiplayer
function boss.getNetworkData()
    local data = {}
    for id, boss_instance in pairs(boss.bosses) do
        local bx, by = boss_instance.body:getPosition()
        data[id] = {
            x = bx,
            y = by,
            health = boss_instance.health,
            max_health = boss_instance.max_health,
            state = boss_instance.state,
            facing_right = boss_instance.facing_right,
            squish_amount = boss_instance.squish_amount,
            shake_offset_x = boss_instance.shake_offset_x,
            shake_offset_y = boss_instance.shake_offset_y,
            laser_angle = boss_instance.laser_angle,
            laser_charge_amount = boss_instance.laser_charge_amount
        }
    end
    return data
end

function boss.applyNetworkData(data)
    -- This would be used for client-side rendering of bosses
    -- For now, bosses are only managed by the host
end

-- Collision handling
function boss.collision(fixture_a, fixture_b, contact)
    local boss_fixture = nil
    local other_fixture = nil
    
    -- Check if one fixture is a boss
    if fixture_a:getGroupIndex() == -888 then
        boss_fixture = fixture_a
        other_fixture = fixture_b
    elseif fixture_b:getGroupIndex() == -888 then
        boss_fixture = fixture_b
        other_fixture = fixture_a
    end
    
    if boss_fixture then
        -- Find which boss this is
        local boss_id = nil
        for id, boss_instance in pairs(boss.bosses) do
            if boss_instance.fixture == boss_fixture then
                boss_id = id
                break
            end
        end
        
        if boss_id then
            -- Check if hit by player projectile
            if other_fixture:getGroupIndex() == -2 then -- Player fire group
                -- Apply damage from player fire
                boss.damage(boss_id, 10) -- Base fire damage
            end
        end
    end
end

-- Console commands
function boss.registerCommands()
    if command and command.register then
        command.register("boss", function(args)
            if args[2] == "spawn" then
                local x = tonumber(args[3]) or (player and player.body and player.body:getX() or 0)
                local y = tonumber(args[4]) or (player and player.body and player.body:getY() or 0)
                local id = boss.spawn(x, y)
                return "Boss spawned with ID: " .. id
            elseif args[2] == "despawn" then
                if args[3] == "all" then
                    boss.despawnAll()
                    return "All bosses despawned"
                else
                    local id = tonumber(args[3])
                    if id and boss.despawn(id) then
                        return "Boss " .. id .. " despawned"
                    else
                        return "Invalid boss ID"
                    end
                end
            elseif args[2] == "list" then
                local count = 0
                for id, _ in pairs(boss.bosses) do
                    count = count + 1
                end
                return "Active bosses: " .. count
            elseif args[2] == "damage" then
                local id = tonumber(args[3])
                local damage = tonumber(args[4]) or 100
                if id and boss.bosses[id] then
                    boss.damage(id, damage)
                    return "Dealt " .. damage .. " damage to boss " .. id
                else
                    return "Invalid boss ID"
                end
            else
                return "Usage: boss spawn [x] [y] | boss despawn <id|all> | boss list | boss damage <id> [amount]"
            end
        end)
    end
end

return boss
