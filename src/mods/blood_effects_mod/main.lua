-- Blood Effects Mod - Main Entry Point
-- This mod provides realistic blood splatter and particle effects

local bloodEffectsMod = {}

-- Mod state
local blood_splatters = {}
local blood_pools = {}
local blood_particles = {}
local effect_counter = 0
local mod_config = {}
local blood_shaders = {}

-- Blood effect configurations
local BLOOD_CONFIG = {
    -- Splatter effects
    splatter = {
        base_size = 8,
        size_variation = 0.5,
        lifetime = 20.0,
        fade_start_time = 15.0,
        colors = {
            fresh = {0.8, 0.1, 0.1, 1.0},
            old = {0.4, 0.05, 0.05, 0.7}
        },
        splatter_count_min = 3,
        splatter_count_max = 8,
        velocity_range = 50
    },
    
    -- Blood pool effects
    pool = {
        base_size = 15,
        growth_rate = 5,
        max_size = 30,
        lifetime = 30.0,
        fade_start_time = 25.0,
        color = {0.6, 0.05, 0.05, 0.8},
        threshold_damage = 20  -- Minimum damage to create a pool
    },
    
    -- Particle effects
    particles = {
        count_min = 5,
        count_max = 15,
        lifetime = 1.0,
        velocity_min = 30,
        velocity_max = 80,
        gravity = 200,
        color = {0.9, 0.1, 0.1, 1.0},
        size = 2
    }
}

-- Initialize the mod
function bloodEffectsMod.init(api)
    print("[BLOOD_EFFECTS_MOD] Initializing Blood Effects System v1.0.0")
    
    -- Store API reference
    bloodEffectsMod.api = api
    
    -- Load configuration
    mod_config = {
        enable_blood_splatters = true,
        enable_blood_pools = true,
        enable_blood_particles = true,
        max_blood_splatters = 100,
        max_blood_pools = 50,
        blood_lifetime = 30.0,
        splatter_size_variation = 0.5,
        blood_intensity = 1.0
    }
    
    -- Load blood shaders
    bloodEffectsMod.loadShaders()
    
    print("[BLOOD_EFFECTS_MOD] Initialization complete!")
end

-- Load blood effect shaders
function bloodEffectsMod.loadShaders()
    local api = bloodEffectsMod.api
    
    -- Blood splatter shader for realistic splat effects
    blood_shaders.splatter = api.renderer.loadShader("blood_splatter", nil, "mods/blood_effects_mod/shaders/blood_splatter.frag")
    if not blood_shaders.splatter then
        print("[BLOOD_EFFECTS_MOD] Warning: Could not load blood splatter shader")
    end
    
    -- Blood pool shader for pooling effects
    blood_shaders.pool = api.renderer.loadShader("blood_pool", nil, "mods/blood_effects_mod/shaders/blood_pool.frag")
    if not blood_shaders.pool then
        print("[BLOOD_EFFECTS_MOD] Warning: Could not load blood pool shader")
    end
end

-- Create blood splatter effect
function bloodEffectsMod.createBloodSplatter(x, y, damage, direction_x, direction_y)
    if not mod_config.enable_blood_splatters then return end
    
    local config = BLOOD_CONFIG.splatter
    local splatter_count = math.random(config.splatter_count_min, config.splatter_count_max)
    
    -- Scale effect based on damage
    local damage_scale = math.min(damage / 50, 2.0) * mod_config.blood_intensity
    
    for i = 1, splatter_count do
        if #blood_splatters >= mod_config.max_blood_splatters then
            -- Remove oldest splatter
            table.remove(blood_splatters, 1)
        end
        
        effect_counter = effect_counter + 1
        
        -- Calculate splatter position and size
        local angle = math.atan2(direction_y or 0, direction_x or 0) + (math.random() - 0.5) * math.pi * 0.5
        local distance = math.random(10, 30) * damage_scale
        
        local splatter_x = x + math.cos(angle) * distance
        local splatter_y = y + math.sin(angle) * distance
        
        local size = config.base_size * (1 + (math.random() - 0.5) * config.size_variation) * damage_scale
        
        local splatter = {
            id = effect_counter,
            x = splatter_x,
            y = splatter_y,
            size = size,
            rotation = math.random() * math.pi * 2,
            color = {config.colors.fresh[1], config.colors.fresh[2], config.colors.fresh[3], config.colors.fresh[4]},
            timer = config.lifetime,
            lifetime = config.lifetime,
            fade_start = config.fade_start_time,
            active = true,
            splatter_type = math.random(1, 3) -- Different splatter sprites
        }
        
        table.insert(blood_splatters, splatter)
    end
end

-- Create blood pool effect
function bloodEffectsMod.createBloodPool(x, y, damage)
    if not mod_config.enable_blood_pools or damage < BLOOD_CONFIG.pool.threshold_damage then return end
    
    -- Check if there's already a pool nearby
    for _, pool in ipairs(blood_pools) do
        local distance = bloodEffectsMod.api.utils.math.distance(x, y, pool.x, pool.y)
        if distance < 20 then
            -- Expand existing pool
            pool.target_size = math.min(pool.target_size + damage * 0.5, BLOOD_CONFIG.pool.max_size)
            pool.timer = BLOOD_CONFIG.pool.lifetime -- Reset timer
            return pool
        end
    end
    
    if #blood_pools >= mod_config.max_blood_pools then
        -- Remove oldest pool
        table.remove(blood_pools, 1)
    end
    
    effect_counter = effect_counter + 1
    
    local config = BLOOD_CONFIG.pool
    local damage_scale = math.min(damage / 30, 1.5) * mod_config.blood_intensity
    
    local pool = {
        id = effect_counter,
        x = x,
        y = y,
        size = 0,
        target_size = config.base_size * damage_scale,
        color = {config.color[1], config.color[2], config.color[3], config.color[4]},
        timer = config.lifetime,
        lifetime = config.lifetime,
        fade_start = config.fade_start_time,
        active = true,
        growth_rate = config.growth_rate
    }
    
    table.insert(blood_pools, pool)
    return pool
end

-- Create blood particle effect
function bloodEffectsMod.createBloodParticles(x, y, damage, direction_x, direction_y)
    if not mod_config.enable_blood_particles then return end
    
    local config = BLOOD_CONFIG.particles
    local particle_count = math.random(config.count_min, config.count_max)
    
    -- Scale particles based on damage
    local damage_scale = math.min(damage / 25, 2.0) * mod_config.blood_intensity
    particle_count = math.floor(particle_count * damage_scale)
    
    local base_angle = math.atan2(direction_y or 0, direction_x or 0)
    
    for i = 1, particle_count do
        effect_counter = effect_counter + 1
        
        -- Calculate particle velocity
        local angle = base_angle + (math.random() - 0.5) * math.pi * 0.8
        local speed = math.random(config.velocity_min, config.velocity_max) * damage_scale
        
        local particle = {
            id = effect_counter,
            x = x + (math.random() - 0.5) * 10,
            y = y + (math.random() - 0.5) * 10,
            velocity_x = math.cos(angle) * speed,
            velocity_y = math.sin(angle) * speed,
            size = config.size * (0.5 + math.random() * 0.5),
            color = {config.color[1], config.color[2], config.color[3], config.color[4]},
            timer = config.lifetime,
            lifetime = config.lifetime,
            active = true
        }
        
        table.insert(blood_particles, particle)
    end
end

-- Update all blood effects
function bloodEffectsMod.update(dt)
    -- Update blood splatters
    for i = #blood_splatters, 1, -1 do
        local splatter = blood_splatters[i]
        
        if splatter.active then
            splatter.timer = splatter.timer - dt
            
            -- Fade out effect
            if splatter.timer <= splatter.fade_start then
                local fade_progress = splatter.timer / splatter.fade_start
                splatter.color[4] = BLOOD_CONFIG.splatter.colors.fresh[4] * fade_progress
                
                -- Change color to old blood
                local age_factor = 1 - fade_progress
                splatter.color[1] = bloodEffectsMod.lerp(BLOOD_CONFIG.splatter.colors.fresh[1], BLOOD_CONFIG.splatter.colors.old[1], age_factor)
                splatter.color[2] = bloodEffectsMod.lerp(BLOOD_CONFIG.splatter.colors.fresh[2], BLOOD_CONFIG.splatter.colors.old[2], age_factor)
                splatter.color[3] = bloodEffectsMod.lerp(BLOOD_CONFIG.splatter.colors.fresh[3], BLOOD_CONFIG.splatter.colors.old[3], age_factor)
            end
            
            if splatter.timer <= 0 then
                table.remove(blood_splatters, i)
            else
                bloodEffectsMod.renderBloodSplatter(splatter)
            end
        else
            table.remove(blood_splatters, i)
        end
    end
    
    -- Update blood pools
    for i = #blood_pools, 1, -1 do
        local pool = blood_pools[i]
        
        if pool.active then
            pool.timer = pool.timer - dt
            
            -- Grow pool to target size
            if pool.size < pool.target_size then
                pool.size = math.min(pool.size + pool.growth_rate * dt, pool.target_size)
            end
            
            -- Fade out effect
            if pool.timer <= pool.fade_start then
                local fade_progress = pool.timer / pool.fade_start
                pool.color[4] = BLOOD_CONFIG.pool.color[4] * fade_progress
            end
            
            if pool.timer <= 0 then
                table.remove(blood_pools, i)
            else
                bloodEffectsMod.renderBloodPool(pool)
            end
        else
            table.remove(blood_pools, i)
        end
    end
    
    -- Update blood particles
    for i = #blood_particles, 1, -1 do
        local particle = blood_particles[i]
        
        if particle.active then
            particle.timer = particle.timer - dt
            
            -- Apply physics
            particle.x = particle.x + particle.velocity_x * dt
            particle.y = particle.y + particle.velocity_y * dt
            particle.velocity_y = particle.velocity_y + BLOOD_CONFIG.particles.gravity * dt
            
            -- Apply drag
            particle.velocity_x = particle.velocity_x * 0.98
            particle.velocity_y = particle.velocity_y * 0.98
            
            -- Fade out
            local fade_progress = particle.timer / particle.lifetime
            particle.color[4] = BLOOD_CONFIG.particles.color[4] * fade_progress
            
            if particle.timer <= 0 then
                -- Create splatter when particle lands
                if math.random() < 0.3 then
                    bloodEffectsMod.createBloodSplatter(particle.x, particle.y, 5, 0, 0)
                end
                table.remove(blood_particles, i)
            else
                bloodEffectsMod.renderBloodParticle(particle)
            end
        else
            table.remove(blood_particles, i)
        end
    end
end

-- Render blood splatter
function bloodEffectsMod.renderBloodSplatter(splatter)
    local api = bloodEffectsMod.api
    
    if blood_shaders.splatter then
        -- Use shader for advanced splatter effect
        api.renderer.addToQueue("background", {
            type = "shader_sprite",
            texture_name = "blood_splat",
            shader = blood_shaders.splatter,
            x = splatter.x,
            y = splatter.y,
            rotation = splatter.rotation,
            scale_x = splatter.size / 8,
            scale_y = splatter.size / 8,
            sort_y = splatter.y - 1000, -- Behind everything
            active = true,
            color = splatter.color,
            shader_params = {
                time = splatter.lifetime - splatter.timer,
                splatter_type = splatter.splatter_type
            }
        })
    else
        -- Fallback to simple circle
        api.renderer.addToQueue("background", {
            type = "circle",
            mode = "fill",
            x = splatter.x,
            y = splatter.y,
            radius = splatter.size,
            sort_y = splatter.y - 1000,
            active = true,
            color = splatter.color
        })
    end
end

-- Render blood pool
function bloodEffectsMod.renderBloodPool(pool)
    local api = bloodEffectsMod.api
    
    if blood_shaders.pool and pool.size > 0 then
        -- Use shader for realistic pool effect
        api.renderer.addToQueue("background", {
            type = "shader_circle",
            shader = blood_shaders.pool,
            x = pool.x,
            y = pool.y,
            radius = pool.size,
            sort_y = pool.y - 1001, -- Behind splatters
            active = true,
            color = pool.color,
            shader_params = {
                time = pool.lifetime - pool.timer,
                pool_size = pool.size
            }
        })
    elseif pool.size > 0 then
        -- Fallback to simple circle
        api.renderer.addToQueue("background", {
            type = "circle",
            mode = "fill",
            x = pool.x,
            y = pool.y,
            radius = pool.size,
            sort_y = pool.y - 1001,
            active = true,
            color = pool.color
        })
    end
end

-- Render blood particle
function bloodEffectsMod.renderBloodParticle(particle)
    local api = bloodEffectsMod.api
    
    api.renderer.addToQueue("effects", {
        type = "circle",
        mode = "fill",
        x = particle.x,
        y = particle.y,
        radius = particle.size,
        sort_y = particle.y,
        active = true,
        color = particle.color
    })
end

-- Handle entity damage (called by other mods)
function bloodEffectsMod.onEntityDamage(entity_id, x, y, damage, attacker_x, attacker_y)
    -- Calculate blood direction based on attack direction
    local direction_x = 0
    local direction_y = 0
    
    if attacker_x and attacker_y then
        direction_x = x - attacker_x
        direction_y = y - attacker_y
        local length = math.sqrt(direction_x * direction_x + direction_y * direction_y)
        if length > 0 then
            direction_x = direction_x / length
            direction_y = direction_y / length
        end
    end
    
    -- Create blood effects
    bloodEffectsMod.createBloodParticles(x, y, damage, direction_x, direction_y)
    bloodEffectsMod.createBloodSplatter(x, y, damage, direction_x, direction_y)
    bloodEffectsMod.createBloodPool(x, y, damage)
end

-- Handle entity death (called by other mods)
function bloodEffectsMod.onEntityDeath(entity_id, x, y, max_health)
    -- Create large blood effect for death
    local death_damage = max_health * 0.5 -- Use half of max health for effect intensity
    
    -- Create multiple blood effects for dramatic death
    for i = 1, 3 do
        local offset_x = (math.random() - 0.5) * 20
        local offset_y = (math.random() - 0.5) * 20
        local random_direction_x = (math.random() - 0.5) * 2
        local random_direction_y = (math.random() - 0.5) * 2
        
        bloodEffectsMod.createBloodParticles(x + offset_x, y + offset_y, death_damage, random_direction_x, random_direction_y)
        bloodEffectsMod.createBloodSplatter(x + offset_x, y + offset_y, death_damage, random_direction_x, random_direction_y)
    end
    
    -- Create large death pool
    bloodEffectsMod.createBloodPool(x, y, death_damage * 2)
end

-- Clear all blood effects
function bloodEffectsMod.clearBlood()
    blood_splatters = {}
    blood_pools = {}
    blood_particles = {}
    print("[BLOOD_EFFECTS_MOD] All blood effects cleared")
end

-- Set blood intensity
function bloodEffectsMod.setBloodIntensity(intensity)
    mod_config.blood_intensity = math.max(0, math.min(intensity, 2.0))
    print("[BLOOD_EFFECTS_MOD] Blood intensity set to " .. mod_config.blood_intensity)
end

-- Utility function for linear interpolation
function bloodEffectsMod.lerp(a, b, t)
    return a + (b - a) * t
end

-- Get statistics
function bloodEffectsMod.getStats()
    return {
        active_splatters = #blood_splatters,
        active_pools = #blood_pools,
        active_particles = #blood_particles,
        total_effects_created = effect_counter,
        blood_intensity = mod_config.blood_intensity
    }
end

-- Cleanup
function bloodEffectsMod.cleanup()
    blood_splatters = {}
    blood_pools = {}
    blood_particles = {}
    effect_counter = 0
    print("[BLOOD_EFFECTS_MOD] Cleanup complete")
end

-- Mod interface - exports for other mods
bloodEffectsMod.exports = {
    createBloodSplatter = bloodEffectsMod.createBloodSplatter,
    createBloodPool = bloodEffectsMod.createBloodPool,
    createBloodParticles = bloodEffectsMod.createBloodParticles,
    clearBlood = bloodEffectsMod.clearBlood,
    setBloodIntensity = bloodEffectsMod.setBloodIntensity,
    onEntityDamage = bloodEffectsMod.onEntityDamage,
    onEntityDeath = bloodEffectsMod.onEntityDeath,
    getStats = bloodEffectsMod.getStats
}

return bloodEffectsMod