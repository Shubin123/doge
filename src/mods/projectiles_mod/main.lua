-- Projectiles Mod - Main Entry Point
-- Enhanced projectile system with object pooling, sophisticated visual effects, and performance optimizations
-- Migrated from legacy bullet.lua with all advanced features preserved

local projectilesMod = {}

-- Vec2 compatibility helper (for mods that don't have access to vec2 library)
local function vec2_new(x, y)
    return {x = x or 0, y = y or 0}
end

-- Mod state
local active_projectiles = {}
local projectile_pool = {}  -- Object pool for efficient reuse
local projectile_templates = {}
local deferred_removals = {}
local mod_config = {}
local mod_time = 0

-- Enhanced effect systems (from legacy)
local muzzle_flashes = {}  -- Muzzle flash effects
local shells = {}  -- Ejected shell casings
local particles = {}  -- Gunpowder confetti particles
local online_bullets = {}  -- Multiplayer bullet bodies

-- Shader integration
local tracer_shader = nil
local muzzle_flash_shader = nil
local muzzle_flash_canvas = nil

-- API reference
local api = nil

-- Collision groups
local COLLISION_GROUPS = {
    PROJECTILE = -2,
    ROCKET = -3,
    EXPLOSION = -4,
    PLAYER = -1,
    ENEMY = -777,
    BOSS = -888
}

-- Default projectile template
local PROJECTILE_DEFAULTS = {
    type = "bullet",
    speed = 800,
    damage = 10,
    lifetime = 5.0,
    radius = 3,
    mass = 0.1,
    gravity = 0,
    drag = 0,
    penetration = 0,
    explosion_radius = 0,
    knockback = 50,
    trail_enabled = true,
    trail_length = 8,
    collision_group = COLLISION_GROUPS.PROJECTILE
}

-- Initialize the mod
function projectilesMod.init(mod_api)
    print("[PROJECTILES_MOD] Initializing Enhanced Projectiles System v2.0.0")
    
    api = mod_api
    
    -- Load configuration
    mod_config = {
        enable_bullet_trails = true,
        enable_collision_effects = true,
        enable_networking = true,
        max_projectiles = 200,
        projectile_cleanup_time = 10.0,
        damage_falloff = false,
        enable_object_pooling = true,
        max_pool_size = 50,
        enable_shaders = true,
        enable_muzzle_flashes = true,
        enable_shell_ejection = true,
        enable_particle_effects = true
    }
    
    -- Initialize effect systems
    muzzle_flashes = {}
    shells = {}
    particles = {}
    online_bullets = {}
    
    -- Load shaders if available
    projectilesMod.loadShaders()
    
    -- Register built-in projectile templates
    projectilesMod.registerBuiltinProjectiles()
    
    -- Register network handler
    if mod_config.enable_networking then
        api.network.registerMessageHandler("projectiles_mod", projectilesMod.handleNetworkMessage)
    end
    
    -- Create canvas for muzzle flash rendering if needed
    if mod_config.enable_shaders and api.renderer.createCanvas then
        local width, height = 800, 600  -- Default dimensions
        if api.input.getScreenDimensions then
            width, height = api.input.getScreenDimensions()
        end
        muzzle_flash_canvas = api.renderer.createCanvas(width, height)
    end
    
    print("[PROJECTILES_MOD] Initialization complete! Enhanced projectiles ready with object pooling and advanced effects")
end

-- Load shader files (from legacy system)
function projectilesMod.loadShaders()
    if not mod_config.enable_shaders then
        return
    end
    
    -- Try to load tracer shader
    if api.renderer.loadShader then
        tracer_shader = api.renderer.loadShader("shaders/bullet_tracer.frag")
        muzzle_flash_shader = api.renderer.loadShader("shaders/muzzle_flash.frag")
        
        if tracer_shader then
            api.utils.log("Loaded bullet tracer shader", "projectiles_mod")
        end
        if muzzle_flash_shader then
            api.utils.log("Loaded muzzle flash shader", "projectiles_mod")
        end
    end
end

-- Register built-in projectile templates
function projectilesMod.registerBuiltinProjectiles()
    -- Standard bullet
    projectilesMod.registerProjectile("bullet", {
        type = "bullet",
        speed = 800,
        damage = 10,
        lifetime = 5.0,
        radius = 3,
        trail_enabled = true,
        trail_color = {1, 1, 0.8, 0.8},
        hit_effect = "bullet_impact"
    })
    
    -- Fast tracer round
    projectilesMod.registerProjectile("tracer", {
        type = "tracer",
        speed = 1000,
        damage = 12,
        lifetime = 4.0,
        radius = 2,
        trail_enabled = true,
        trail_color = {1, 0.5, 0.2, 1.0},
        hit_effect = "tracer_impact"
    })
    
    -- Rocket projectile
    projectilesMod.registerProjectile("rocket", {
        type = "rocket",
        speed = 500,
        damage = 100,
        lifetime = 8.0,
        radius = 8,
        mass = 2.0,
        explosion_radius = 100,
        collision_group = COLLISION_GROUPS.ROCKET,
        trail_enabled = true,
        trail_color = {1, 0.8, 0.3, 1.0},
        exhaust_enabled = true,
        hit_effect = "explosion",
        acceleration = 100  -- rockets accelerate
    })
    
    -- Plasma bolt
    projectilesMod.registerProjectile("plasma", {
        type = "plasma",
        speed = 600,
        damage = 25,
        lifetime = 6.0,
        radius = 6,
        trail_enabled = true,
        trail_color = {0.2, 0.8, 1.0, 0.9},
        hit_effect = "plasma_burst",
        energy_decay = 0.95  -- loses energy over time
    })
end

-- Register a projectile template
function projectilesMod.registerProjectile(id, template)
    -- Merge with defaults
    local projectile = {}
    for k, v in pairs(PROJECTILE_DEFAULTS) do
        projectile[k] = v
    end
    for k, v in pairs(template) do
        projectile[k] = v
    end
    
    projectile.id = id
    projectile_templates[id] = projectile
    
    api.utils.log("Registered projectile: " .. id, "projectiles_mod")
end

-- Spawn a projectile with object pooling (enhanced from legacy system)
function projectilesMod.spawnProjectile(template_id, x, y, dx, dy, params)
    local template = projectile_templates[template_id]
    if not template then
        api.utils.log("Unknown projectile template: " .. template_id, "projectiles_mod")
        return nil
    end
    
    -- Check projectile limit
    if #active_projectiles >= mod_config.max_projectiles then
        -- Remove oldest projectile
        projectilesMod.removeProjectile(active_projectiles[1])
    end
    
    -- Normalize direction
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 0 then
        dx = dx / length
        dy = dy / length
    else
        dx, dy = 1, 0  -- default direction
    end
    
    -- Merge parameters with template
    local projectile = {}
    for k, v in pairs(template) do
        projectile[k] = v
    end
    if params then
        for k, v in pairs(params) do
            projectile[k] = v
        end
    end
    
    -- Store owner information if provided (for PvP)
    if params and params.owner_id then
        projectile.owner_id = params.owner_id
        projectile.owner_client_id = params.owner_client_id  -- For network identification
    end
    
    local instance
    
    -- Try to reuse from pool (object pooling from legacy system)
    if mod_config.enable_object_pooling and #projectile_pool > 0 then
        instance = table.remove(projectile_pool)
        
        -- Reset position and properties
        instance.body:setPosition(x, y)
        instance.body:setLinearVelocity(0, 0)
        instance.direction = {x = dx, y = dy}
        instance.params = projectile
        instance.birth_time = mod_time
        instance.prev_pos = {x = x, y = y}
        instance.start_pos = {x = x, y = y}
        instance.trail = {}
        instance.template_id = template_id
        instance.current_speed = projectile.speed
        
        -- Reset network data
        instance.network_data = {
            x = x, y = y,
            dx = dx, dy = dy,
            active = true,
            id = #active_projectiles + 1
        }
    else
        -- Create new instance
        local body = api.physics.createBody(x, y, "dynamic", projectile.collision_group, projectile.mass)
        local shape = api.physics.createCircleShape(projectile.radius)
        local fixture = api.physics.createFixture(body, shape, projectile.collision_group, projectile.mass, 0.1)
        
        if not body or not fixture then
            api.utils.log("Failed to create physics body for projectile", "projectiles_mod")
            return nil
        end
        
        instance = {
            id = #active_projectiles + 1,
            template_id = template_id,
            body = body,
            fixture = fixture,
            direction = {x = dx, y = dy},
            birth_time = mod_time,
            trail = {},
            params = projectile,
            start_pos = {x = x, y = y},
            prev_pos = {x = x, y = y},  -- For tracer rendering
            current_speed = projectile.speed,
            network_data = {
                x = x, y = y,
                dx = dx, dy = dy,
                active = true,
                id = #active_projectiles + 1
            }
        }
        
        -- Set fixture user data for collision detection
        fixture:setUserData(instance)
    end
    
    -- Set initial velocity
    instance.body:setLinearVelocity(dx * projectile.speed, dy * projectile.speed)
    
    table.insert(active_projectiles, instance)
    
    -- Sync in multiplayer
    if mod_config.enable_networking then
        api.network.sendToAll({
            action = "projectile_spawn",
            template_id = template_id,
            x = x, y = y,
            dx = dx, dy = dy,
            params = params
        }, "projectiles_mod")
    end
    
    return instance
end

-- Update function (enhanced from legacy system)
function projectilesMod.update(dt)
    mod_time = mod_time + dt
    
    -- Process deferred removals first
    projectilesMod.processDeferredRemovals()
    
    -- Update muzzle flashes
    for i = #muzzle_flashes, 1, -1 do
        local flash = muzzle_flashes[i]
        flash.life = flash.life - dt
        if flash.life <= 0 then
            table.remove(muzzle_flashes, i)
        end
    end
    
    -- Update shell casings (physics simulation)
    for i = #shells, 1, -1 do
        local shell = shells[i]
        shell.life = shell.life - dt
        shell.rotation = shell.rotation + shell.rot_speed * dt
        
        -- Simple physics simulation
        shell.vel.y = shell.vel.y + 980 * dt  -- gravity
        shell.pos.x = shell.pos.x + shell.vel.x * dt
        shell.pos.y = shell.pos.y + shell.vel.y * dt
        
        -- Ground bounce (simple)
        if shell.pos.y > shell.ground_y and shell.vel.y > 0 then
            shell.pos.y = shell.ground_y
            shell.vel.y = -shell.vel.y * 0.3  -- bounce with dampening
            shell.vel.x = shell.vel.x * 0.8   -- friction
            shell.rot_speed = shell.rot_speed * 0.7  -- rotation dampening
        end
        
        -- Remove when life expires
        if shell.life <= 0 then
            table.remove(shells, i)
        end
    end
    
    -- Update gunpowder particles
    for i = #particles, 1, -1 do
        local particle = particles[i]
        particle.life = particle.life - dt
        
        -- Update position
        particle.pos.x = particle.pos.x + particle.vel.x * dt
        particle.pos.y = particle.pos.y + particle.vel.y * dt
        
        -- Apply drag/friction
        particle.vel.x = particle.vel.x * 0.98
        particle.vel.y = particle.vel.y * 0.98
        
        -- Slight gravity for realism
        particle.vel.y = particle.vel.y + 50 * dt
        
        -- Remove when life expires
        if particle.life <= 0 then
            table.remove(particles, i)
        end
    end
    
    -- Update active projectiles
    for i = #active_projectiles, 1, -1 do
        local proj = active_projectiles[i]
        
        -- Check if body is destroyed
        if not proj.body or proj.body:isDestroyed() then
            table.remove(active_projectiles, i)
            goto continue
        end
        
        -- Record last position for drawing tracers
        local x, y = proj.body:getPosition()
        proj.prev_pos = {x = x, y = y}
        
        -- Check lifetime
        local age = mod_time - proj.birth_time
        if age > proj.params.lifetime then
            projectilesMod.returnToPool(proj, i)
            goto continue
        end
        
        -- Add to trail for visual effect (limit trail length)
        table.insert(proj.trail, 1, {x = x, y = y, time = mod_time})
        if #proj.trail > 8 then  -- keep last 8 positions
            table.remove(proj.trail)
        end
        
        -- Update network data
        proj.network_data.x = x
        proj.network_data.y = y
        
        -- Apply special effects based on projectile type
        if proj.params.type == "rocket" then
            projectilesMod.updateRocket(proj, dt)
        elseif proj.params.type == "plasma" then
            projectilesMod.updatePlasma(proj, dt)
        end
        
        -- Set constant velocity (from legacy system)
        if proj.body and not proj.body:isDestroyed() then
            proj.body:setLinearVelocity(
                proj.direction.x * proj.current_speed,
                proj.direction.y * proj.current_speed
            )
        end
        
        ::continue::
    end
    
    -- Populate renderer with all projectile effects
    projectilesMod.populateRenderer()
end

-- Update rocket-specific behavior
function projectilesMod.updateRocket(proj, dt)
    -- Accelerate
    if proj.params.acceleration then
        proj.current_speed = proj.current_speed + proj.params.acceleration * dt
    end
    
    -- Create exhaust trail
    if proj.params.exhaust_enabled then
        local x, y = proj.body:getPosition()
        api.renderer.addParticleEffect("rocket_exhaust", x, y, "exhaust", {
            direction = {-proj.direction.x, -proj.direction.y},
            intensity = 0.8
        })
    end
end

-- Update plasma-specific behavior
function projectilesMod.updatePlasma(proj, dt)
    -- Energy decay
    if proj.params.energy_decay then
        proj.current_speed = proj.current_speed * proj.params.energy_decay
        proj.params.damage = proj.params.damage * proj.params.energy_decay
    end
end

-- Handle projectile collision
function projectilesMod.handleCollision(projectile_fixture, other_fixture, contact)
    local proj = projectile_fixture:getUserData()
    if not proj or not proj.params then return end
    
    -- Get collision data
    local other_data = other_fixture:getUserData()
    local other_group = other_fixture:getGroupIndex()
    local other_body = other_fixture:getBody()
    local x, y = other_body:getPosition()
    
    -- Check if this is a projectile (to determine who fired it)
    local is_projectile = type(proj) == "table" and proj.params and proj.template_id
    if not is_projectile then
        -- Swap if the other fixture is the projectile
        proj, other_data = other_data, proj
        projectile_fixture, other_fixture = other_fixture, projectile_fixture
        if not proj or not proj.params then return end
    end
    
    -- Skip if projectile hit its owner (check owner field if available)
    if proj.params.owner_id and other_data and other_data.id == proj.params.owner_id then
        return
    end
    
    -- For multiplayer, also check client ID to prevent self-damage
    if proj.params.owner_client_id and other_data and other_data.client_id == proj.params.owner_client_id then
        return
    end
    
    -- Handle different collision types
    if other_group == COLLISION_GROUPS.ENEMY then
        projectilesMod.handleEnemyHit(proj, other_body, x, y)
    elseif other_group == COLLISION_GROUPS.PLAYER then
        -- Check if this is player vs player damage (PvP)
        if other_data and other_data.type == "player" then
            -- In multiplayer, allow damage between different players
            local isMultiplayer = api.network and api.network.isMultiplayer and api.network.isMultiplayer()
            if isMultiplayer then
                -- Check if this is a different player (not the owner)
                if not proj.params.owner_id or other_data.id ~= proj.params.owner_id then
                    projectilesMod.handlePlayerHit(proj, other_body, x, y, other_data)
                end
            else
                -- Single player mode - normal player hit
                projectilesMod.handlePlayerHit(proj, other_body, x, y, other_data)
            end
        end
    elseif other_group == COLLISION_GROUPS.BOSS then
        projectilesMod.handleBossHit(proj, other_body, x, y)
    else
        -- Hit environment
        projectilesMod.handleEnvironmentHit(proj, x, y)
    end
    
    -- Create hit effect
    if proj.params.hit_effect then
        projectilesMod.createHitEffect(proj, x, y)
    end
    
    -- Handle explosion for rockets
    if proj.params.explosion_radius > 0 then
        projectilesMod.createExplosion(x, y, proj.params.explosion_radius, proj.params.damage)
    end
    
    -- Schedule for removal
    table.insert(deferred_removals, proj)
end

-- Handle enemy hit
function projectilesMod.handleEnemyHit(proj, enemy_body, x, y)
    -- Apply damage (this would integrate with enemy system)
    local damage = math.random(proj.params.damage - 2, proj.params.damage + 2)
    
    -- Apply knockback
    if proj.params.knockback > 0 then
        local force_x = proj.direction.x * proj.params.knockback
        local force_y = proj.direction.y * proj.params.knockback
        -- Use safe physics utility when available
        enemy_body:applyLinearImpulse(force_x, force_y)
    end
    
    -- Create blood effect
    api.renderer.addParticleEffect("blood_splatter", x, y, "impact", {
        direction = proj.direction,
        intensity = damage / 10
    })
    
    api.utils.log("Enemy hit for " .. damage .. " damage", "projectiles_mod")
end

-- Handle player hit
function projectilesMod.handlePlayerHit(proj, player_body, x, y, player_data)
    -- Get the player core mod for damage handling
    local player_mod = api.mods and api.mods.player_core_mod
    
    -- Determine if this is local player or remote player
    local isLocalPlayer = true
    if player_data and player_data.client_id then
        -- Check if this is the local player based on client ID
        local localClientId = api.network and api.network.getLocalClientId and api.network.getLocalClientId()
        isLocalPlayer = (player_data.client_id == localClientId)
    end
    
    if isLocalPlayer then
        -- Apply damage to local player
        if player_mod and player_mod.exports and player_mod.exports.damagePlayer then
            -- Apply damage through player core mod
            player_mod.exports.damagePlayer(proj.params.damage, "projectile")
            
            -- Apply knockback if available
            if proj.params.knockback > 0 and player_mod.exports.applyKnockback then
                player_mod.exports.applyKnockback(proj.direction, proj.params.knockback)
            end
        else
            -- Fallback to direct API if available
            local current_health = api.game.getPlayerHealth()
            api.game.setPlayerHealth(current_health - proj.params.damage)
        end
    end
    
    -- Create blood effect for any player hit
    api.renderer.addParticleEffect("blood_splatter", x, y, "impact", {
        direction = proj.direction,
        intensity = proj.params.damage / 10
    })
    
    -- Network sync damage event
    if mod_config.enable_networking then
        api.network.sendToAll({
            action = "player_hit",
            damage = proj.params.damage,
            x = x,
            y = y,
            direction = proj.direction,
            hit_player_id = player_data and player_data.id,
            hit_client_id = player_data and player_data.client_id,
            attacker_id = proj.params.owner_id,
            attacker_client_id = proj.params.owner_client_id
        }, "projectiles_mod")
    end
    
    api.utils.log("Player hit for " .. proj.params.damage .. " damage (Local: " .. tostring(isLocalPlayer) .. ")", "projectiles_mod")
end

-- Handle boss hit
function projectilesMod.handleBossHit(proj, boss_body, x, y)
    -- Boss damage handling would go here
    api.utils.log("Boss hit", "projectiles_mod")
end

-- Handle environment hit
function projectilesMod.handleEnvironmentHit(proj, x, y)
    -- Spark effect for environment hits
    api.renderer.addParticleEffect("sparks", x, y, "impact", {
        direction = proj.direction,
        intensity = 0.5
    })
end

-- Create hit effect
function projectilesMod.createHitEffect(proj, x, y)
    if proj.params.hit_effect == "explosion" then
        api.renderer.addParticleEffect("explosion", x, y, "explosion", {
            radius = proj.params.explosion_radius,
            intensity = 1.0
        })
    elseif proj.params.hit_effect == "bullet_impact" then
        api.renderer.addParticleEffect("impact", x, y, "small_impact", {
            direction = proj.direction
        })
    elseif proj.params.hit_effect == "plasma_burst" then
        api.renderer.addParticleEffect("plasma_burst", x, y, "energy", {
            color = proj.params.trail_color
        })
    end
end

-- Create explosion effect
function projectilesMod.createExplosion(x, y, radius, damage)
    -- Visual explosion effect
    api.renderer.addParticleEffect("explosion", x, y, "explosion", {
        radius = radius,
        intensity = 1.0
    })
    
    -- Damage entities in radius (would need integration with game systems)
    api.utils.log("Explosion at " .. x .. "," .. y .. " radius:" .. radius, "projectiles_mod")
end

-- Return projectile to pool for reuse (from legacy system)
function projectilesMod.returnToPool(proj, index)
    if not mod_config.enable_object_pooling then
        -- Destroy if pooling disabled
        if proj.body and proj.body:isDestroyed() == false then
            proj.body:destroy()
        end
    else
        -- Reset physics state but keep body/fixture for reuse
        if proj.body and proj.body:isDestroyed() == false then
            proj.body:setLinearVelocity(0, 0)
            proj.body:setPosition(-1000, -1000)  -- move offscreen
        end
        
        -- Add to pool if not too many (limit pool size)
        if #projectile_pool < mod_config.max_pool_size then
            table.insert(projectile_pool, proj)
        else
            -- Destroy if pool is full
            if proj.body and proj.body:isDestroyed() == false then
                proj.body:destroy()
            end
        end
    end
    
    if index then
        table.remove(active_projectiles, index)
    else
        -- Find and remove
        for i = #active_projectiles, 1, -1 do
            if active_projectiles[i] == proj then
                table.remove(active_projectiles, i)
                break
            end
        end
    end
end

-- Remove projectile (fallback for immediate destruction)
function projectilesMod.removeProjectile(proj, index)
    if proj.body and proj.body:isDestroyed() == false then
        proj.body:destroy()
    end
    
    if index then
        table.remove(active_projectiles, index)
    else
        -- Find and remove
        for i = #active_projectiles, 1, -1 do
            if active_projectiles[i] == proj then
                table.remove(active_projectiles, i)
                break
            end
        end
    end
end

-- Process deferred removals
function projectilesMod.processDeferredRemovals()
    for _, proj in ipairs(deferred_removals) do
        projectilesMod.returnToPool(proj)
    end
    deferred_removals = {}
end

-- Populate dynamic draw list with projectile effects for Y-sorting (from legacy system)
function projectilesMod.populateRenderer()
    -- Add muzzle flashes to draw list
    for _, flash in ipairs(muzzle_flashes) do
        api.renderer.addToQueue("effects", {
            type = "muzzle_flash",
            x = flash.pos.x,
            y = flash.pos.y,
            sort_y = flash.pos.y + 10,
            flash_data = flash,
            color = {1, 1, 1, 1},
            active = true
        })
    end
    
    -- Add gunpowder particles to draw list
    for _, particle in ipairs(particles) do
        api.renderer.addToQueue("effects", {
            type = "gunpowder_particle",
            x = particle.pos.x,
            y = particle.pos.y,
            sort_y = particle.pos.y + 5,
            particle_data = particle,
            color = {1, 1, 1, 1},
            active = true
        })
    end
    
    -- Add shell casings to draw list
    for _, shell in ipairs(shells) do
        api.renderer.addToQueue("world", {
            type = "shell_casing",
            x = shell.pos.x,
            y = shell.pos.y,
            sort_y = shell.pos.y + 50,
            shell_data = shell,
            color = {1, 1, 1, 1},
            active = true
        })
    end
    
    -- Add bullet tracers to draw list with sophisticated rendering
    for _, proj in ipairs(active_projectiles) do
        -- Skip destroyed bodies
        if not proj.body or proj.body:isDestroyed() then
            goto continue
        end
        
        local x, y = proj.body:getPosition()
        
        -- Calculate distance from player for fading effect
        local px, py = 0, 0
        if api.game.getPlayerPosition then
            px, py = api.game.getPlayerPosition()
        end
        local distance = math.sqrt((x - px)^2 + (y - py)^2)
        
        api.renderer.addToQueue("world", {
            type = "bullet_tracer",
            x = x,
            y = y,
            sort_y = y + 150,
            bullet_data = proj,
            distance = distance,
            color = {1, 1, 1, 1},
            active = true
        })
        
        ::continue::
    end
end

-- Draw function (legacy compatibility)
function projectilesMod.draw()
    -- Legacy renderer compatibility - draw effects directly
    projectilesMod.drawMuzzleFlashes()
    projectilesMod.drawParticles()
    projectilesMod.drawShells()
    projectilesMod.drawBulletTracers()
end

-- Network message handler
function projectilesMod.handleNetworkMessage(data)
    if data.action == "projectile_spawn" then
        -- Spawn projectile from network data
        projectilesMod.spawnProjectile(data.template_id, data.x, data.y, data.dx, data.dy, data.params)
    elseif data.action == "player_hit" then
        -- Handle networked player hit (for effects and synchronization)
        -- Create blood effect at hit location
        api.renderer.addParticleEffect("blood_splatter", data.x, data.y, "impact", {
            direction = data.direction,
            intensity = data.damage / 10
        })
        
        -- If this hit was on the local player, damage was already applied locally
        -- This is just for visual effects and logging
        api.utils.log("Networked player hit: " .. (data.hit_client_id or "unknown") .. " damaged by " .. (data.attacker_client_id or "unknown"), "projectiles_mod")
    end
end

-- Get projectile data for networking
function projectilesMod.getNetworkData()
    local network_data = {}
    for _, proj in ipairs(active_projectiles) do
        table.insert(network_data, proj.network_data)
    end
    return network_data
end

-- Create muzzle flash effect (from legacy system)
function projectilesMod.createMuzzleFlash(pos, dir, params)
    if not mod_config.enable_muzzle_flashes then
        return
    end
    
    params = params or {}
    table.insert(muzzle_flashes, {
        pos = {x = pos.x, y = pos.y},
        dir = {x = dir.x / math.sqrt(dir.x^2 + dir.y^2), y = dir.y / math.sqrt(dir.x^2 + dir.y^2)},
        life = params.duration or 0.08,
        max_life = params.duration or 0.08,
        size = params.size or math.random(12, 20),
        cone_angle = params.cone_angle or 0.61,  -- 35 degree half-angle
        cone_length = params.cone_length or 150,  -- cone extends 150 pixels
        color = params.color or {1, 0.9, 0.7},  -- warm white/yellow
        intensity = params.intensity or 1.0,
        use_shader = params.use_shader ~= false  -- default to true
    })
end

-- Create particle effect (gunpowder confetti from legacy system)
function projectilesMod.createParticleEffect(pos, dir, params)
    if not mod_config.enable_particle_effects then
        return
    end
    
    params = params or {}
    local count = params.count or 8
    local colors = params.colors or {{1, 0.8, 0.3}, {1, 0.5, 0.2}}
    local lifespan = params.lifespan or 0.3
    local speed = params.speed or {min = 120, max = 250}
    local size = params.size or {min = 1, max = 3}
    local spread_angle = params.spread_angle or 0.44
    
    for i = 1, count do
        -- Calculate random direction within the spread cone
        local base_angle = math.atan2(dir.y, dir.x)
        local random_spread = (math.random() - 0.5) * spread_angle * 2
        local particle_angle = base_angle + random_spread
        
        -- Calculate velocity
        local particle_speed = speed.min + math.random() * (speed.max - speed.min)
        local vel = {
            x = math.cos(particle_angle) * particle_speed,
            y = math.sin(particle_angle) * particle_speed
        }
        
        -- Random color from the provided palette
        local color = colors[math.random(#colors)]
        
        -- Random size
        local particle_size = size.min + math.random() * (size.max - size.min)
        
        table.insert(particles, {
            pos = {x = pos.x, y = pos.y},
            vel = vel,
            life = lifespan + math.random() * lifespan * 0.3, -- slight variation
            max_life = lifespan,
            color = {color[1], color[2], color[3]},
            size = particle_size,
            rotation = math.random() * math.pi * 2,
            rot_speed = (math.random() - 0.5) * 10
        })
    end
end

-- Create shell ejection effect (from legacy system)
function projectilesMod.createShellEjection(gun_pos, gun_dir, shell_type)
    if not mod_config.enable_shell_ejection then
        return
    end
    
    -- Calculate ejection position (right side of gun barrel)
    local right_dir = {x = -gun_dir.y, y = gun_dir.x}  -- perpendicular to gun direction
    local ejection_pos = {
        x = gun_pos.x + right_dir.x * 8,
        y = gun_pos.y + right_dir.y * 8
    }
    
    -- Calculate ejection velocity
    local ejection_vel = {
        x = right_dir.x * (80 + math.random() * 40),  -- rightward velocity
        y = right_dir.y * (80 + math.random() * 40) - (50 + math.random() * 30)  -- slight upward component
    }
    
    -- Determine shell color and size based on type
    local color, size
    if shell_type == "shotgun" then
        color = {0.8, 0.2, 0.2}  -- red
        size = {width = 6, height = 12}
    elseif shell_type == "pistol" then
        color = {0.9, 0.7, 0.3}  -- brass
        size = {width = 4, height = 8}
    elseif shell_type == "rifle" then
        color = {0.9, 0.7, 0.3}  -- brass
        size = {width = 5, height = 15}
    else  -- SMG or default
        color = {0.9, 0.7, 0.3}  -- brass
        size = {width = 4, height = 10}
    end
    
    table.insert(shells, {
        pos = {x = ejection_pos.x, y = ejection_pos.y},
        vel = ejection_vel,
        rotation = math.random() * math.pi * 2,
        rot_speed = (math.random() - 0.5) * 10,  -- random spin
        life = 3 + math.random() * 1,  -- 3-4 seconds
        max_life = 4,
        color = color,
        size = size,
        ground_y = ejection_pos.y + 100  -- approximate ground level
    })
end

-- Individual drawing functions for direct rendering
function projectilesMod.drawMuzzleFlashes()
    -- Implementation would use direct Love2D drawing
    -- For now, effects are handled by the renderer queue
end

function projectilesMod.drawParticles()
    -- Implementation would use direct Love2D drawing
    -- For now, effects are handled by the renderer queue
end

function projectilesMod.drawShells()
    -- Implementation would use direct Love2D drawing
    -- For now, effects are handled by the renderer queue
end

function projectilesMod.drawBulletTracers()
    -- Implementation would use direct Love2D drawing with tracer shader
    -- For now, effects are handled by the renderer queue
end

-- Public API
projectilesMod.public = {
    spawnProjectile = projectilesMod.spawnProjectile,
    registerProjectile = projectilesMod.registerProjectile,
    getActiveProjectiles = function() return active_projectiles end,
    handleCollision = projectilesMod.handleCollision,
    createMuzzleFlash = projectilesMod.createMuzzleFlash,
    createParticleEffect = projectilesMod.createParticleEffect,
    createShellEjection = projectilesMod.createShellEjection
}

-- Export for collision handling
projectilesMod.exports = {
    handleCollision = projectilesMod.handleCollision
}

return projectilesMod