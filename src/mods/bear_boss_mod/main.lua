-- Bear Boss Mod - Main Entry Point
-- This mod adds the challenging Bear Boss with complex attack patterns

local bearBossMod = {}

-- Mod state
local active_bosses = {}
local boss_counter = 0
local mod_config = {}
local particle_systems = {}

-- Boss states
local BOSS_STATES = {
    IDLE = "idle",
    PREPARING_HOP = "preparing_hop",
    HOPPING = "hopping", 
    LANDING = "landing",
    CHARGING_LASER = "charging_laser",
    FIRING_LASER = "firing_laser",
    HEADLESS = "headless"
}

-- Boss configuration
local BOSS_CONFIG = {
    health = 500,
    max_health = 500,
    speed = 80,
    mass = 5.0,
    scale = 1.2,
    sprite = "bear_boss",
    headless_sprite = "bear_boss_headless",
    
    -- Attack timings
    hop_prepare_time = 1.5,
    hop_duration = 0.8,
    laser_charge_time = 2.0,
    laser_fire_time = 1.5,
    state_cooldown = 1.0,
    
    -- Attack damage
    ground_pound_damage = 50,
    ground_pound_radius = 100,
    laser_damage = 30,
    laser_range = 800,
    laser_width = 20,
    
    -- Phase thresholds
    headless_threshold = 0.2, -- 20% health
    rage_threshold = 0.5, -- 50% health
    
    -- AI parameters
    detection_range = 400,
    attack_range = 200,
    min_distance = 80
}

-- Initialize the mod
function bearBossMod.init(api)
    print("[BEAR_BOSS_MOD] Initializing Bear Boss Mod v1.0.0")
    
    -- Store API reference
    bearBossMod.api = api
    
    -- Load configuration
    mod_config = {
        max_bosses = 3,
        boss_health = 500,
        enable_laser_attacks = true,
        enable_ground_pounds = true,
        enable_headless_phase = true,
        enable_particles = true,
        enable_networking = true,
        boss_collision_group = -888,
        laser_damage = 30,
        ground_pound_damage = 50
    }
    
    -- Initialize particle systems
    bearBossMod.initializeParticles()
    
    -- Register network handler
    if mod_config.enable_networking then
        api.network.registerMessageHandler("bear_boss_mod", bearBossMod.handleNetworkMessage)
    end
    
    print("[BEAR_BOSS_MOD] Initialization complete!")
end

-- Initialize particle systems
function bearBossMod.initializeParticles()
    local api = bearBossMod.api
    
    -- Landing dust particles
    particle_systems.landing_dust = api.renderer.createParticleSystem("landing_dust", {
        texture = "particle_dust",
        emission_rate = 100,
        lifetime = 1.0,
        color = {0.7, 0.5, 0.3, 1},
        size_variation = 0.5
    })
    
    -- Laser charge particles  
    particle_systems.laser_charge = api.renderer.createParticleSystem("laser_charge", {
        texture = "particle_spark",
        emission_rate = 50,
        lifetime = 0.8,
        color = {1, 0.2, 0.2, 1},
        size_variation = 0.3
    })
    
    -- Laser beam particles
    particle_systems.laser_beam = api.renderer.createParticleSystem("laser_beam", {
        texture = "particle_laser",
        emission_rate = 200,
        lifetime = 0.3,
        color = {1, 0.1, 0.1, 1},
        size_variation = 0.2
    })
    
    -- Shockwave particles
    particle_systems.shockwave = api.renderer.createParticleSystem("shockwave", {
        texture = "particle_ring",
        emission_rate = 20,
        lifetime = 2.0,
        color = {0.8, 0.6, 0.4, 1},
        size_variation = 0.8
    })
end

-- Create a bear boss
function bearBossMod.createBoss(x, y, health)
    if #active_bosses >= mod_config.max_bosses then
        print("[BEAR_BOSS_MOD] Maximum boss limit reached")
        return nil
    end
    
    boss_counter = boss_counter + 1
    health = health or mod_config.boss_health
    
    -- Create physics body
    local body = bearBossMod.api.physics.createBody(x, y, "dynamic", mod_config.boss_collision_group, BOSS_CONFIG.mass, 0.3)
    if not body then
        print("[BEAR_BOSS_MOD] Failed to create physics body")
        return nil
    end
    
    -- Create shape and fixture
    local shape = bearBossMod.api.physics.createCircleShape(40)
    local fixture = bearBossMod.api.physics.createFixture(body, shape, mod_config.boss_collision_group, BOSS_CONFIG.mass, 0.3)
    
    if fixture then
        fixture:setGroupIndex(mod_config.boss_collision_group)
        fixture:setUserData({type = "boss", mod = "bear_boss_mod", id = boss_counter})
    end
    
    body:setMass(BOSS_CONFIG.mass)
    body:setLinearDamping(3)
    
    local boss = {
        id = boss_counter,
        body = body,
        fixture = fixture,
        x = x,
        y = y,
        health = health,
        max_health = health,
        active = true,
        
        -- State machine
        state = BOSS_STATES.IDLE,
        state_timer = 0,
        state_cooldown = 0,
        last_state_change = 0,
        
        -- Movement
        velocity_x = 0,
        velocity_y = 0,
        target_x = x,
        target_y = y,
        
        -- Attack data
        laser_start_x = 0,
        laser_start_y = 0,
        laser_end_x = 0,
        laser_end_y = 0,
        laser_active = false,
        ground_pound_x = 0,
        ground_pound_y = 0,
        
        -- Visual effects
        sprite = BOSS_CONFIG.sprite,
        scale = BOSS_CONFIG.scale,
        rotation = 0,
        flash_timer = 0,
        rage_glow = 0,
        
        -- AI data
        target_player = nil,
        last_seen_player_x = 0,
        last_seen_player_y = 0,
        decision_timer = 0,
        attack_cooldown = 0,
        
        -- Phase data
        is_headless = false,
        is_enraged = false,
        phase_transition = false,
        
        -- Network data
        network_data = {},
        last_network_sync = 0
    }
    
    -- Initialize AI behavior from ai_behaviors_mod if available
    local ai_mod = bearBossMod.api.mods and bearBossMod.api.mods.ai_behaviors_mod
    if ai_mod and ai_mod.exports then
        boss.ai_behavior = ai_mod.exports.createAIBehavior(boss, "tactical", {
            speed = BOSS_CONFIG.speed,
            detection_range = BOSS_CONFIG.detection_range,
            min_distance = BOSS_CONFIG.min_distance
        })
        
        boss.state_machine = ai_mod.exports.createStateMachine(boss, "basic_combat")
    end
    
    table.insert(active_bosses, boss)
    
    -- Sync with network if enabled
    if mod_config.enable_networking then
        bearBossMod.syncBossCreation(boss)
    end
    
    print("[BEAR_BOSS_MOD] Bear Boss spawned with " .. health .. " health!")
    return boss
end

-- Update all bosses
function bearBossMod.update(dt)
    local current_time = bearBossMod.api.utils.getTime()
    
    for i = #active_bosses, 1, -1 do
        local boss = active_bosses[i]
        if boss.active and boss.body and not boss.body:isDestroyed() then
            -- Update position from physics
            boss.x = boss.body:getX()
            boss.y = boss.body:getY()
            
            -- Update boss AI and state machine
            bearBossMod.updateBossAI(boss, dt, current_time)
            bearBossMod.updateBossState(boss, dt, current_time)
            
            -- Update visual effects
            bearBossMod.updateVisualEffects(boss, dt)
            
            -- Render boss
            bearBossMod.renderBoss(boss)
            
            -- Network sync
            if mod_config.enable_networking and current_time - boss.last_network_sync > 0.1 then
                bearBossMod.syncBossState(boss)
                boss.last_network_sync = current_time
            end
        else
            -- Remove dead boss
            if boss.body and not boss.body:isDestroyed() then
                boss.body:destroy()
            end
            table.remove(active_bosses, i)
        end
    end
end

-- Update boss AI
function bearBossMod.updateBossAI(boss, dt, current_time)
    local api = bearBossMod.api
    
    -- Get player position
    local player_x, player_y = api.game.getPlayerPosition()
    if not player_x then return end
    
    local distance = api.utils.math.distance(boss.x, boss.y, player_x, player_y)
    boss.target_player = {x = player_x, y = player_y}
    
    -- Update timers
    boss.decision_timer = boss.decision_timer + dt
    boss.attack_cooldown = math.max(0, boss.attack_cooldown - dt)
    boss.state_cooldown = math.max(0, boss.state_cooldown - dt)
    
    -- Phase transitions
    local health_ratio = boss.health / boss.max_health
    if health_ratio <= BOSS_CONFIG.headless_threshold and not boss.is_headless then
        boss.is_headless = true
        boss.sprite = BOSS_CONFIG.headless_sprite
        boss.phase_transition = true
        print("[BEAR_BOSS_MOD] Bear Boss entered headless phase!")
    end
    
    if health_ratio <= BOSS_CONFIG.rage_threshold and not boss.is_enraged then
        boss.is_enraged = true
        boss.rage_glow = 1.0
        print("[BEAR_BOSS_MOD] Bear Boss is enraged!")
    end
    
    -- AI decision making
    if boss.decision_timer >= 2.0 and boss.state_cooldown <= 0 then
        boss.decision_timer = 0
        bearBossMod.makeBossDecision(boss, distance, current_time)
    end
    
    -- Update AI behavior if available
    if boss.ai_behavior and bearBossMod.api.mods and bearBossMod.api.mods.ai_behaviors_mod then
        local ai_mod = bearBossMod.api.mods.ai_behaviors_mod
        if ai_mod.exports then
            ai_mod.exports.updateAIBehavior(boss.ai_behavior, boss.target_player, dt)
        end
    end
end

-- Make boss decision
function bearBossMod.makeBossDecision(boss, distance, current_time)
    if boss.attack_cooldown > 0 then return end
    
    local attack_chance = boss.is_enraged and 0.8 or 0.6
    local should_attack = math.random() < attack_chance
    
    if should_attack and distance <= BOSS_CONFIG.attack_range then
        -- Choose attack based on distance and conditions
        if distance > 150 and mod_config.enable_laser_attacks then
            bearBossMod.startLaserAttack(boss)
        elseif mod_config.enable_ground_pounds then
            bearBossMod.startGroundPound(boss)
        end
    else
        -- Movement decision
        if distance > BOSS_CONFIG.min_distance then
            boss.state = BOSS_STATES.IDLE
        end
    end
end

-- Start laser attack
function bearBossMod.startLaserAttack(boss)
    if boss.state ~= BOSS_STATES.IDLE then return end
    
    boss.state = BOSS_STATES.CHARGING_LASER
    boss.state_timer = 0
    boss.laser_active = false
    
    -- Set laser target
    if boss.target_player then
        boss.laser_end_x = boss.target_player.x
        boss.laser_end_y = boss.target_player.y
    end
    
    print("[BEAR_BOSS_MOD] Boss charging laser attack!")
end

-- Start ground pound
function bearBossMod.startGroundPound(boss)
    if boss.state ~= BOSS_STATES.IDLE then return end
    
    boss.state = BOSS_STATES.PREPARING_HOP
    boss.state_timer = 0
    
    -- Set ground pound target
    if boss.target_player then
        boss.ground_pound_x = boss.target_player.x
        boss.ground_pound_y = boss.target_player.y
    end
    
    print("[BEAR_BOSS_MOD] Boss preparing ground pound!")
end

-- Update boss state machine
function bearBossMod.updateBossState(boss, dt, current_time)
    boss.state_timer = boss.state_timer + dt
    
    if boss.state == BOSS_STATES.IDLE then
        bearBossMod.updateIdleState(boss, dt)
        
    elseif boss.state == BOSS_STATES.PREPARING_HOP then
        bearBossMod.updatePreparingHopState(boss, dt)
        
    elseif boss.state == BOSS_STATES.HOPPING then
        bearBossMod.updateHoppingState(boss, dt)
        
    elseif boss.state == BOSS_STATES.LANDING then
        bearBossMod.updateLandingState(boss, dt)
        
    elseif boss.state == BOSS_STATES.CHARGING_LASER then
        bearBossMod.updateChargingLaserState(boss, dt)
        
    elseif boss.state == BOSS_STATES.FIRING_LASER then
        bearBossMod.updateFiringLaserState(boss, dt)
        
    elseif boss.state == BOSS_STATES.HEADLESS then
        bearBossMod.updateHeadlessState(boss, dt)
    end
end

-- State update functions
function bearBossMod.updateIdleState(boss, dt)
    -- Gradual velocity reduction
    boss.velocity_x = boss.velocity_x * 0.95
    boss.velocity_y = boss.velocity_y * 0.95
    
    if boss.body then
        boss.body:setLinearVelocity(boss.velocity_x, boss.velocity_y)
    end
end

function bearBossMod.updatePreparingHopState(boss, dt)
    if boss.state_timer >= BOSS_CONFIG.hop_prepare_time then
        -- Start hopping
        boss.state = BOSS_STATES.HOPPING
        boss.state_timer = 0
        
        -- Calculate hop velocity
        local dx = boss.ground_pound_x - boss.x
        local dy = boss.ground_pound_y - boss.y
        local distance = math.sqrt(dx * dx + dy * dy)
        
        if distance > 0 then
            local hop_speed = 400
            boss.velocity_x = (dx / distance) * hop_speed
            boss.velocity_y = (dy / distance) * hop_speed
            
            if boss.body then
                boss.body:setLinearVelocity(boss.velocity_x, boss.velocity_y)
            end
        end
    end
end

function bearBossMod.updateHoppingState(boss, dt)
    if boss.state_timer >= BOSS_CONFIG.hop_duration then
        boss.state = BOSS_STATES.LANDING
        boss.state_timer = 0
        bearBossMod.executeGroundPound(boss)
    end
end

function bearBossMod.updateLandingState(boss, dt)
    if boss.state_timer >= 1.0 then
        boss.state = BOSS_STATES.IDLE
        boss.state_timer = 0
        boss.state_cooldown = BOSS_CONFIG.state_cooldown
        boss.attack_cooldown = boss.is_enraged and 1.0 or 2.0
    end
end

function bearBossMod.updateChargingLaserState(boss, dt)
    -- Spawn charge particles
    if mod_config.enable_particles then
        bearBossMod.api.renderer.addParticleEffect(
            "boss_laser_charge_" .. boss.id,
            boss.x - 20, -- Left eye
            boss.y - 15,
            "laser_charge",
            {
                lifetime = 0.3,
                color = {1, 0.2, 0.2, 1}
            }
        )
        
        bearBossMod.api.renderer.addParticleEffect(
            "boss_laser_charge2_" .. boss.id,
            boss.x + 20, -- Right eye
            boss.y - 15,
            "laser_charge",
            {
                lifetime = 0.3,
                color = {1, 0.2, 0.2, 1}
            }
        )
    end
    
    if boss.state_timer >= BOSS_CONFIG.laser_charge_time then
        boss.state = BOSS_STATES.FIRING_LASER
        boss.state_timer = 0
        boss.laser_active = true
        bearBossMod.startLaserBeam(boss)
    end
end

function bearBossMod.updateFiringLaserState(boss, dt)
    if boss.laser_active then
        bearBossMod.updateLaserBeam(boss, dt)
    end
    
    if boss.state_timer >= BOSS_CONFIG.laser_fire_time then
        boss.state = BOSS_STATES.IDLE
        boss.state_timer = 0
        boss.state_cooldown = BOSS_CONFIG.state_cooldown
        boss.attack_cooldown = boss.is_enraged and 1.5 or 3.0
        boss.laser_active = false
    end
end

function bearBossMod.updateHeadlessState(boss, dt)
    -- Headless phase: more aggressive, faster attacks
    boss.attack_cooldown = math.max(0, boss.attack_cooldown - dt * 1.5)
    bearBossMod.updateIdleState(boss, dt)
end

-- Execute ground pound attack
function bearBossMod.executeGroundPound(boss)
    local api = bearBossMod.api
    
    -- Create shockwave effect
    if mod_config.enable_particles then
        api.renderer.addParticleEffect(
            "boss_shockwave_" .. boss.id,
            boss.x,
            boss.y,
            "shockwave",
            {
                lifetime = 2.0,
                color = {0.8, 0.6, 0.4, 1},
                count = 20
            }
        )
    end
    
    -- Check for player damage
    local player_x, player_y = api.game.getPlayerPosition()
    if player_x then
        local distance = api.utils.math.distance(boss.x, boss.y, player_x, player_y)
        if distance <= BOSS_CONFIG.ground_pound_radius then
            local damage = BOSS_CONFIG.ground_pound_damage
            if boss.is_enraged then damage = damage * 1.5 end
            
            api.game.damagePlayer(1, damage)
            print("[BEAR_BOSS_MOD] Player hit by ground pound for " .. damage .. " damage!")
        end
    end
end

-- Start laser beam
function bearBossMod.startLaserBeam(boss)
    boss.laser_start_x = boss.x - 20
    boss.laser_start_y = boss.y - 15
    
    -- Update target if player moved
    if boss.target_player then
        boss.laser_end_x = boss.target_player.x
        boss.laser_end_y = boss.target_player.y
    end
end

-- Update laser beam
function bearBossMod.updateLaserBeam(boss, dt)
    local api = bearBossMod.api
    
    -- Gradually track player
    if boss.target_player then
        local track_speed = boss.is_enraged and 200 or 100
        local dx = boss.target_player.x - boss.laser_end_x
        local dy = boss.target_player.y - boss.laser_end_y
        
        boss.laser_end_x = boss.laser_end_x + dx * dt * track_speed / 100
        boss.laser_end_y = boss.laser_end_y + dy * dt * track_speed / 100
    end
    
    -- Check for laser hits via raycast (simplified)
    local player_x, player_y = api.game.getPlayerPosition()
    if player_x then
        -- Check if player is in laser path
        local laser_dx = boss.laser_end_x - boss.laser_start_x
        local laser_dy = boss.laser_end_y - boss.laser_start_y
        local laser_length = math.sqrt(laser_dx * laser_dx + laser_dy * laser_dy)
        
        if laser_length > 0 then
            -- Normalize laser direction
            laser_dx = laser_dx / laser_length
            laser_dy = laser_dy / laser_length
            
            -- Vector from laser start to player
            local player_dx = player_x - boss.laser_start_x
            local player_dy = player_y - boss.laser_start_y
            
            -- Project player onto laser line
            local projection = player_dx * laser_dx + player_dy * laser_dy
            
            -- Point on laser line closest to player
            local closest_x = boss.laser_start_x + projection * laser_dx
            local closest_y = boss.laser_start_y + projection * laser_dy
            
            -- Distance from player to laser line
            local distance_to_line = api.utils.math.distance(player_x, player_y, closest_x, closest_y)
            
            -- Check if hit
            if distance_to_line <= BOSS_CONFIG.laser_width and projection >= 0 and projection <= laser_length then
                local damage = BOSS_CONFIG.laser_damage
                if boss.is_enraged then damage = damage * 1.3 end
                
                api.game.damagePlayer(1, damage)
                print("[BEAR_BOSS_MOD] Player hit by laser for " .. damage .. " damage!")
            end
        end
    end
    
    -- Laser beam particles
    if mod_config.enable_particles then
        local steps = 10
        for i = 1, steps do
            local t = i / steps
            local beam_x = boss.laser_start_x + (boss.laser_end_x - boss.laser_start_x) * t
            local beam_y = boss.laser_start_y + (boss.laser_end_y - boss.laser_start_y) * t
            
            api.renderer.addParticleEffect(
                "laser_beam_" .. boss.id .. "_" .. i,
                beam_x,
                beam_y,
                "laser_beam",
                {
                    lifetime = 0.1,
                    color = {1, 0.1, 0.1, 0.8}
                }
            )
        end
    end
end

-- Update visual effects
function bearBossMod.updateVisualEffects(boss, dt)
    -- Flash effect when damaged
    boss.flash_timer = math.max(0, boss.flash_timer - dt)
    
    -- Rage glow effect
    if boss.is_enraged then
        boss.rage_glow = 0.5 + math.sin(bearBossMod.api.utils.getTime() * 5) * 0.3
    end
end

-- Render boss
function bearBossMod.renderBoss(boss)
    local api = bearBossMod.api
    
    -- Main boss sprite
    local color = {1, 1, 1, 1}
    if boss.flash_timer > 0 then
        color = {1, 0.5, 0.5, 1}
    elseif boss.is_enraged then
        color = {1, 0.7 + boss.rage_glow * 0.3, 0.7, 1}
    end
    
    api.renderer.addToQueue("world", {
        type = "sprite",
        texture_name = boss.sprite,
        x = boss.x,
        y = boss.y,
        rotation = boss.rotation,
        scale_x = boss.scale,
        scale_y = boss.scale,
        sort_y = boss.y,
        active = true,
        color = color
    })
    
    -- Laser beam visualization
    if boss.laser_active and boss.state == BOSS_STATES.FIRING_LASER then
        api.renderer.addToQueue("effects", {
            type = "line",
            x1 = boss.laser_start_x,
            y1 = boss.laser_start_y,
            x2 = boss.laser_end_x,
            y2 = boss.laser_end_y,
            width = BOSS_CONFIG.laser_width,
            sort_y = boss.y + 1,
            active = true,
            color = {1, 0.2, 0.2, 0.8}
        })
        
        -- Second laser beam (twin eyes)
        api.renderer.addToQueue("effects", {
            type = "line",
            x1 = boss.laser_start_x + 40,
            y1 = boss.laser_start_y,
            x2 = boss.laser_end_x,
            y2 = boss.laser_end_y,
            width = BOSS_CONFIG.laser_width,
            sort_y = boss.y + 1,
            active = true,
            color = {1, 0.2, 0.2, 0.8}
        })
    end
    
    -- Health bar
    bearBossMod.renderHealthBar(boss)
    
    -- Debug visualization
    if mod_config.debug_boss then
        bearBossMod.renderDebugInfo(boss)
    end
end

-- Render health bar
function bearBossMod.renderHealthBar(boss)
    local api = bearBossMod.api
    
    local health_percent = boss.health / boss.max_health
    local bar_width = 80
    local bar_height = 8
    local bar_y = boss.y - 60
    
    -- Background
    api.renderer.addToQueue("ui", {
        type = "rectangle",
        mode = "fill",
        x = boss.x - bar_width/2,
        y = bar_y,
        width = bar_width,
        height = bar_height,
        sort_y = 10000,
        active = true,
        color = {0.2, 0.2, 0.2, 0.9}
    })
    
    -- Health fill
    local health_color = {0.8, 0.2, 0.2, 0.9}
    if boss.is_headless then
        health_color = {0.5, 0.1, 0.1, 0.9}
    elseif boss.is_enraged then
        health_color = {1, 0.4, 0.1, 0.9}
    end
    
    api.renderer.addToQueue("ui", {
        type = "rectangle",
        mode = "fill",
        x = boss.x - bar_width/2 + 2,
        y = bar_y + 2,
        width = (bar_width - 4) * health_percent,
        height = bar_height - 4,
        sort_y = 10001,
        active = true,
        color = health_color
    })
    
    -- Boss name
    local boss_name = boss.is_headless and "HEADLESS BEAR BOSS" or "BEAR BOSS"
    api.renderer.addToQueue("ui", {
        type = "text",
        text = boss_name,
        x = boss.x,
        y = bar_y - 15,
        font = "default",
        sort_y = 10002,
        active = true,
        color = {1, 1, 1, 1},
        align = "center"
    })
end

-- Damage boss
function bearBossMod.damageBoss(boss_id, damage, from_player, attacker_x, attacker_y)
    local boss = nil
    for _, b in ipairs(active_bosses) do
        if b.id == boss_id then
            boss = b
            break
        end
    end
    
    if not boss or not boss.active then return end
    
    boss.health = boss.health - damage
    boss.flash_timer = 0.2
    
    -- Use health/damage mod if available
    local health_mod = bearBossMod.api.mods and bearBossMod.api.mods.health_damage_mod
    if health_mod and health_mod.exports then
        health_mod.exports.onEntityDamage(boss.id, boss.x, boss.y, damage, boss.health, boss.max_health, "boss")
    end
    
    -- Use blood effects mod if available
    local blood_mod = bearBossMod.api.mods and bearBossMod.api.mods.blood_effects_mod
    if blood_mod and blood_mod.exports then
        blood_mod.exports.onEntityDamage(boss.id, boss.x, boss.y, damage, attacker_x, attacker_y)
    end
    
    -- Check death
    if boss.health <= 0 then
        boss.active = false
        bearBossMod.handleBossDeath(boss, from_player)
    end
    
    -- Sync damage
    if mod_config.enable_networking then
        bearBossMod.syncBossDamage(boss_id, damage, boss.health, from_player)
    end
end

-- Handle boss death
function bearBossMod.handleBossDeath(boss, from_player)
    local api = bearBossMod.api
    
    -- Use blood effects mod for dramatic boss death if available
    local blood_mod = bearBossMod.api.mods and bearBossMod.api.mods.blood_effects_mod
    if blood_mod and blood_mod.exports then
        blood_mod.exports.onEntityDeath(boss.id, boss.x, boss.y, boss.max_health)
    end
    
    -- Hide health bar
    local health_mod = bearBossMod.api.mods and bearBossMod.api.mods.health_damage_mod
    if health_mod and health_mod.exports then
        health_mod.exports.hideHealthBar(boss.id)
    end
    
    -- Death explosion
    if mod_config.enable_particles then
        api.renderer.addParticleEffect(
            "boss_death_" .. boss.id,
            boss.x,
            boss.y,
            "explosion",
            {
                lifetime = 3.0,
                color = {1, 0.5, 0.1, 1},
                count = 20
            }
        )
    end
    
    -- Drop rewards
    for i = 1, 3 do
        local drop_x = boss.x + math.random(-50, 50)
        local drop_y = boss.y + math.random(-50, 50)
        api.game.spawnPickup(drop_x, drop_y, "health")
    end
    
    print("[BEAR_BOSS_MOD] Bear Boss defeated!")
end

-- Network synchronization
function bearBossMod.syncBossCreation(boss)
    local api = bearBossMod.api
    api.network.sendToAll({
        action = "create_boss",
        boss_data = {
            id = boss.id,
            x = boss.x,
            y = boss.y,
            health = boss.health
        }
    }, "bear_boss_mod")
end

function bearBossMod.syncBossState(boss)
    local api = bearBossMod.api
    api.network.sendToAll({
        action = "sync_boss_state",
        boss_id = boss.id,
        state = boss.state,
        x = boss.x,
        y = boss.y,
        health = boss.health,
        laser_active = boss.laser_active
    }, "bear_boss_mod")
end

function bearBossMod.syncBossDamage(boss_id, damage, new_health, from_player)
    local api = bearBossMod.api
    api.network.sendToAll({
        action = "damage_boss",
        boss_id = boss_id,
        damage = damage,
        new_health = new_health,
        from_player = from_player
    }, "bear_boss_mod")
end

-- Handle network messages
function bearBossMod.handleNetworkMessage(data)
    if data.action == "create_boss" then
        local boss_data = data.boss_data
        bearBossMod.createBoss(boss_data.x, boss_data.y, boss_data.health)
    elseif data.action == "damage_boss" then
        bearBossMod.damageBoss(data.boss_id, data.damage, data.from_player)
    elseif data.action == "sync_boss_state" then
        -- Update boss state from network
        for _, boss in ipairs(active_bosses) do
            if boss.id == data.boss_id then
                boss.state = data.state
                boss.laser_active = data.laser_active
                break
            end
        end
    end
end

-- Get collision handler
function bearBossMod.getCollisionHandler()
    return function(fixture_data, other_fixture_data, contact)
        if fixture_data.type == "boss" and other_fixture_data.type == "player_bullet" then
            -- Boss takes damage from player bullets
            bearBossMod.damageBoss(fixture_data.id, other_fixture_data.damage or 10, true)
        end
    end
end

-- Get mod statistics
function bearBossMod.getStats()
    local stats = {
        active_bosses = #active_bosses,
        bosses_by_state = {},
        total_boss_health = 0
    }
    
    for _, boss in ipairs(active_bosses) do
        stats.bosses_by_state[boss.state] = (stats.bosses_by_state[boss.state] or 0) + 1
        stats.total_boss_health = stats.total_boss_health + boss.health
    end
    
    return stats
end

-- Cleanup
function bearBossMod.cleanup()
    -- Destroy all physics bodies
    for _, boss in ipairs(active_bosses) do
        if boss.body and not boss.body:isDestroyed() then
            boss.body:destroy()
        end
    end
    
    active_bosses = {}
    boss_counter = 0
    
    print("[BEAR_BOSS_MOD] Cleanup complete")
end

-- Mod interface
return bearBossMod