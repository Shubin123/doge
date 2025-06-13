-- Combat Effects Mod - Main Entry Point
-- Provides visual effects for combat including muzzle flashes, explosions, shell casings, and blood

local combatEffectsMod = {}

-- Mod state
local active_effects = {}
local muzzle_flashes = {}
local shell_casings = {}
local blood_splatters = {}
local explosions = {}
local particles = {}
local mod_config = {}
local mod_time = 0

-- API reference
local api = nil

-- Effect defaults
local EFFECT_DEFAULTS = {
    muzzle_flash = {
        duration = 0.1,
        size = 1.0,
        color = {1, 0.9, 0.7, 1},
        cone_angle = math.rad(30),
        cone_length = 40,
        intensity = 1.0
    },
    explosion = {
        duration = 0.8,
        size = 1.0,
        color = {1, 0.5, 0.2, 1},
        particle_count = 20,
        shockwave_radius = 100
    },
    shell_ejection = {
        duration = 3.0,
        velocity = {x = -100, y = -150},
        spin = 10,
        gravity = 980,
        bounce = 0.3,
        friction = 0.8
    },
    blood_splatter = {
        duration = 2.0,
        particle_count = 8,
        spread = math.rad(45),
        velocity = 150,
        color = {0.8, 0.1, 0.1, 1}
    }
}

-- Initialize the mod
function combatEffectsMod.init(mod_api)
    print("[COMBAT_EFFECTS_MOD] Initializing Combat Effects System v1.0.0")
    
    api = mod_api
    
    -- Load configuration
    mod_config = {
        enable_muzzle_flash = true,
        enable_shell_ejection = true,
        enable_blood_effects = true,
        enable_explosions = true,
        enable_particle_physics = true,
        max_particles = 500,
        effect_lifetime = 5.0,
        blood_splatter_intensity = 1.0
    }
    
    -- Load shaders
    combatEffectsMod.loadShaders()
    
    print("[COMBAT_EFFECTS_MOD] Initialization complete!")
end

-- Load effect shaders
function combatEffectsMod.loadShaders()
    -- These would load from the mod's shader directory
    -- For now we'll just log that they would be loaded
    api.utils.log("Loading muzzle flash shader", "combat_effects_mod")
    api.utils.log("Loading explosion shader", "combat_effects_mod")
    api.utils.log("Loading blood effect shader", "combat_effects_mod")
end

-- Create sophisticated muzzle flash effect (enhanced from legacy system)
function combatEffectsMod.createMuzzleFlash(x, y, direction, params)
    if not mod_config.enable_muzzle_flash then return end
    
    params = params or {}
    local defaults = EFFECT_DEFAULTS.muzzle_flash
    
    -- Normalize direction
    local dir_length = math.sqrt(direction.x^2 + direction.y^2)
    if dir_length > 0 then
        direction.x = direction.x / dir_length
        direction.y = direction.y / dir_length
    end
    
    local flash = {
        type = "muzzle_flash",
        pos = {x = x, y = y},
        direction = direction,
        duration = params.duration or defaults.duration,
        max_duration = params.duration or defaults.duration,
        size = params.size or math.random(12, 20),  -- randomized size like legacy
        color = params.color or defaults.color,
        cone_angle = params.cone_angle or defaults.cone_angle,
        cone_length = params.cone_length or defaults.cone_length,
        intensity = params.intensity or defaults.intensity,
        use_shader = params.use_shader ~= false,  -- default to true
        birth_time = mod_time
    }
    
    table.insert(muzzle_flashes, flash)
    
    -- Add to renderer queue with enhanced parameters
    api.renderer.addParticleEffect("muzzle_flash", x, y, "flash", {
        direction = direction,
        size = flash.size,
        duration = flash.duration,
        color = flash.color,
        cone_angle = flash.cone_angle,
        cone_length = flash.cone_length,
        intensity = flash.intensity
    })
    
    api.utils.log("Created muzzle flash at " .. x .. "," .. y, "combat_effects_mod")
end

-- Create explosion effect
function combatEffectsMod.createExplosion(x, y, radius, params)
    if not mod_config.enable_explosions then return end
    
    params = params or {}
    local defaults = EFFECT_DEFAULTS.explosion
    
    local explosion = {
        type = "explosion",
        pos = {x = x, y = y},
        radius = radius or 50,
        duration = params.duration or defaults.duration,
        max_duration = params.duration or defaults.duration,
        size = params.size or defaults.size,
        color = params.color or defaults.color,
        particle_count = params.particle_count or defaults.particle_count,
        shockwave_radius = params.shockwave_radius or defaults.shockwave_radius,
        birth_time = mod_time,
        particles = {}
    }
    
    -- Create explosion particles
    for i = 1, explosion.particle_count do
        local angle = (i / explosion.particle_count) * math.pi * 2
        local speed = 100 + math.random() * 200
        local particle = {
            x = x,
            y = y,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed,
            life = explosion.duration,
            max_life = explosion.duration,
            size = 2 + math.random() * 4,
            color = {explosion.color[1], explosion.color[2], explosion.color[3], 1}
        }
        table.insert(explosion.particles, particle)
    end
    
    table.insert(explosions, explosion)
    
    -- Add to renderer
    api.renderer.addParticleEffect("explosion", x, y, "explosion", {
        radius = radius,
        intensity = 1.0,
        particle_count = explosion.particle_count
    })
    
    api.utils.log("Created explosion at " .. x .. "," .. y .. " radius:" .. radius, "combat_effects_mod")
end

-- Create sophisticated shell ejection effect (enhanced from legacy system)
function combatEffectsMod.createShellEjection(x, y, direction, shell_type, params)
    if not mod_config.enable_shell_ejection then return end
    
    params = params or {}
    local defaults = EFFECT_DEFAULTS.shell_ejection
    
    -- Calculate ejection direction (perpendicular to gun direction, right side)
    local eject_dir = {x = -direction.y, y = direction.x}  -- perpendicular right
    
    -- Determine shell properties based on type (from legacy system)
    local shell_props = combatEffectsMod.getShellProperties(shell_type or "small")
    
    local shell = {
        type = "shell_casing",
        shell_type = shell_type or "small",
        pos = {x = x + eject_dir.x * 8, y = y + eject_dir.y * 8},
        vel = {
            x = eject_dir.x * (80 + math.random() * 40),  -- rightward velocity with variation
            y = eject_dir.y * (80 + math.random() * 40) - (50 + math.random() * 30)  -- slight upward component
        },
        rotation = math.random() * math.pi * 2,
        rot_speed = (math.random() - 0.5) * 10,  -- random spin
        duration = params.duration or (3 + math.random() * 1),  -- 3-4 seconds like legacy
        max_duration = params.duration or 4,
        birth_time = mod_time,
        gravity = defaults.gravity,
        bounce = defaults.bounce,
        friction = defaults.friction,
        ground_y = y + 100,  -- approximate ground level
        properties = shell_props
    }
    
    table.insert(shell_casings, shell)
    
    api.utils.log("Ejected " .. shell_type .. " shell", "combat_effects_mod")
end

-- Get shell properties based on type (enhanced from legacy system)
function combatEffectsMod.getShellProperties(shell_type)
    local props = {
        pistol = {
            color = {0.9, 0.7, 0.3, 1},  -- brass
            size = {width = 4, height = 8}
        },
        smg = {
            color = {0.9, 0.7, 0.3, 1},  -- brass  
            size = {width = 4, height = 10}
        },
        rifle = {
            color = {0.9, 0.7, 0.3, 1},  -- brass
            size = {width = 5, height = 15}
        },
        shotgun = {
            color = {0.8, 0.2, 0.2, 1},  -- red plastic
            size = {width = 6, height = 12}
        },
        small = {
            color = {0.9, 0.7, 0.3, 1},  -- brass (fallback)
            size = {width = 4, height = 8}
        }
    }
    
    return props[shell_type] or props.small
end

-- Create blood splatter effect
function combatEffectsMod.createBloodSplatter(x, y, direction, intensity, params)
    if not mod_config.enable_blood_effects then return end
    
    params = params or {}
    local defaults = EFFECT_DEFAULTS.blood_splatter
    intensity = intensity or 1.0
    
    local splatter = {
        type = "blood_splatter",
        pos = {x = x, y = y},
        direction = direction or {x = 1, y = 0},
        intensity = intensity * mod_config.blood_splatter_intensity,
        duration = params.duration or defaults.duration,
        max_duration = params.duration or defaults.duration,
        particle_count = math.floor((params.particle_count or defaults.particle_count) * intensity),
        spread = params.spread or defaults.spread,
        velocity = params.velocity or defaults.velocity,
        color = params.color or defaults.color,
        birth_time = mod_time,
        particles = {}
    }
    
    -- Create blood particles
    for i = 1, splatter.particle_count do
        local angle = math.atan2(direction.y, direction.x) + (math.random() - 0.5) * splatter.spread
        local speed = splatter.velocity * (0.5 + math.random() * 0.5)
        local particle = {
            x = x,
            y = y,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed,
            life = splatter.duration * (0.5 + math.random() * 0.5),
            max_life = splatter.duration,
            size = 1 + math.random() * 3,
            color = {splatter.color[1], splatter.color[2], splatter.color[3], 1}
        }
        table.insert(splatter.particles, particle)
    end
    
    table.insert(blood_splatters, splatter)
    
    -- Add to renderer
    api.renderer.addParticleEffect("blood_splatter", x, y, "blood", {
        direction = direction,
        intensity = intensity,
        particle_count = splatter.particle_count
    })
    
    api.utils.log("Created blood splatter", "combat_effects_mod")
end

-- Create gunpowder particle effect (from legacy system)
function combatEffectsMod.createParticleEffect(x, y, direction, params)
    params = params or {}
    local count = params.count or 8
    local colors = params.colors or {{1, 0.8, 0.3}, {1, 0.5, 0.2}}
    local lifespan = params.lifespan or 0.3
    local speed = params.speed or {min = 120, max = 250}
    local size = params.size or {min = 1, max = 3}
    local spread_angle = params.spread_angle or 0.44
    
    local effect = {
        type = "gunpowder_particles",
        pos = {x = x, y = y},
        particles = {},
        duration = lifespan,
        birth_time = mod_time
    }
    
    for i = 1, count do
        -- Calculate random direction within the spread cone
        local base_angle = math.atan2(direction.y, direction.x)
        local random_spread = (math.random() - 0.5) * spread_angle * 2
        local particle_angle = base_angle + random_spread
        
        -- Calculate velocity
        local particle_speed = speed.min + math.random() * (speed.max - speed.min)
        
        -- Random color from the provided palette
        local color = colors[math.random(#colors)]
        
        -- Random size
        local particle_size = size.min + math.random() * (size.max - size.min)
        
        local particle = {
            x = x,
            y = y,
            vx = math.cos(particle_angle) * particle_speed,
            vy = math.sin(particle_angle) * particle_speed,
            life = lifespan + math.random() * lifespan * 0.3, -- slight variation
            max_life = lifespan,
            size = particle_size,
            color = {color[1], color[2], color[3], 1},
            rotation = math.random() * math.pi * 2,
            rot_speed = (math.random() - 0.5) * 10
        }
        table.insert(effect.particles, particle)
    end
    
    table.insert(particles, effect)
    
    api.utils.log("Created gunpowder particle effect", "combat_effects_mod")
end

-- Create sparks effect
function combatEffectsMod.createSparks(x, y, direction, params)
    params = params or {}
    
    local spark_count = params.count or 6
    local sparks = {
        type = "sparks",
        pos = {x = x, y = y},
        particles = {},
        duration = 0.5,
        birth_time = mod_time
    }
    
    for i = 1, spark_count do
        local angle = math.atan2(direction.y, direction.x) + (math.random() - 0.5) * math.rad(60)
        local speed = 80 + math.random() * 120
        local particle = {
            x = x,
            y = y,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed,
            life = 0.3 + math.random() * 0.2,
            max_life = 0.5,
            size = 1,
            color = {1, 0.8, 0.2, 1}
        }
        table.insert(sparks.particles, particle)
    end
    
    table.insert(particles, sparks)
    
    api.utils.log("Created sparks effect", "combat_effects_mod")
end

-- Update function
function combatEffectsMod.update(dt)
    mod_time = mod_time + dt
    
    -- Update muzzle flashes
    combatEffectsMod.updateMuzzleFlashes(dt)
    
    -- Update explosions
    combatEffectsMod.updateExplosions(dt)
    
    -- Update shell casings
    combatEffectsMod.updateShellCasings(dt)
    
    -- Update blood splatters
    combatEffectsMod.updateBloodSplatters(dt)
    
    -- Update misc particles
    combatEffectsMod.updateParticles(dt)
end

-- Update muzzle flashes with sophisticated cone rendering (from legacy system)
function combatEffectsMod.updateMuzzleFlashes(dt)
    for i = #muzzle_flashes, 1, -1 do
        local flash = muzzle_flashes[i]
        flash.duration = flash.duration - dt
        
        if flash.duration <= 0 then
            table.remove(muzzle_flashes, i)
        else
            -- Enhanced muzzle flash rendering with cone geometry
            local alpha = flash.duration / flash.max_duration
            local size = flash.size * alpha
            
            -- Draw cone-shaped flash using triangular geometry (from legacy)
            local cone_length = flash.cone_length * alpha
            local cone_angle = flash.cone_angle
            
            -- Calculate cone vertices
            local perp_dir = {x = -flash.direction.y, y = flash.direction.x}  -- perpendicular
            local cone_end_x = flash.pos.x + flash.direction.x * cone_length
            local cone_end_y = flash.pos.y + flash.direction.y * cone_length
            local left_vertex_x = cone_end_x + perp_dir.x * math.tan(cone_angle) * cone_length
            local left_vertex_y = cone_end_y + perp_dir.y * math.tan(cone_angle) * cone_length
            local right_vertex_x = cone_end_x - perp_dir.x * math.tan(cone_angle) * cone_length
            local right_vertex_y = cone_end_y - perp_dir.y * math.tan(cone_angle) * cone_length
            
            -- Draw cone with gradient effect (multiple passes for smooth gradient)
            for j = 1, 5 do
                local gradient_factor = j / 5
                local current_alpha = alpha * (1 - gradient_factor * 0.7) * flash.intensity * 0.8
                local current_size = cone_length * (1 - gradient_factor * 0.3)
                
                if current_alpha > 0 then
                    -- Calculate vertices for this gradient layer
                    local layer_end_x = flash.pos.x + flash.direction.x * current_size
                    local layer_end_y = flash.pos.y + flash.direction.y * current_size
                    local layer_left_x = layer_end_x + perp_dir.x * math.tan(cone_angle) * current_size * gradient_factor
                    local layer_left_y = layer_end_y + perp_dir.y * math.tan(cone_angle) * current_size * gradient_factor
                    local layer_right_x = layer_end_x - perp_dir.x * math.tan(cone_angle) * current_size * gradient_factor
                    local layer_right_y = layer_end_y - perp_dir.y * math.tan(cone_angle) * current_size * gradient_factor
                    
                    -- Add triangle to renderer queue
                    api.renderer.addToQueue("effects", {
                        type = "polygon",
                        points = {flash.pos.x, flash.pos.y, layer_left_x, layer_left_y, layer_right_x, layer_right_y},
                        color = {flash.color[1], flash.color[2], flash.color[3], current_alpha},
                        mode = "fill",
                        active = true
                    })
                end
            end
            
            -- Draw bright core at muzzle
            api.renderer.addToQueue("effects", {
                type = "circle",
                x = flash.pos.x,
                y = flash.pos.y,
                radius = size * 0.8,
                color = {flash.color[1], flash.color[2], flash.color[3], alpha * flash.intensity},
                mode = "fill",
                active = true
            })
            
            -- Draw outer glow
            api.renderer.addToQueue("effects", {
                type = "circle",
                x = flash.pos.x,
                y = flash.pos.y,
                radius = size * 1.5,
                color = {flash.color[1] * 0.6, flash.color[2] * 0.4, flash.color[3] * 0.2, alpha * 0.3},
                mode = "fill",
                active = true
            })
        end
    end
end

-- Update explosions
function combatEffectsMod.updateExplosions(dt)
    for i = #explosions, 1, -1 do
        local explosion = explosions[i]
        explosion.duration = explosion.duration - dt
        
        -- Update explosion particles
        for j = #explosion.particles, 1, -1 do
            local particle = explosion.particles[j]
            particle.life = particle.life - dt
            particle.x = particle.x + particle.vx * dt
            particle.y = particle.y + particle.vy * dt
            
            -- Apply gravity and drag
            particle.vy = particle.vy + 200 * dt  -- gravity
            particle.vx = particle.vx * 0.98      -- drag
            particle.vy = particle.vy * 0.98
            
            if particle.life <= 0 then
                table.remove(explosion.particles, j)
            else
                -- Add particle to renderer queue
                local alpha = particle.life / particle.max_life
                api.renderer.addToQueue("effects", {
                    type = "circle",
                    x = particle.x,
                    y = particle.y,
                    radius = particle.size,
                    color = {particle.color[1], particle.color[2], particle.color[3], alpha},
                    mode = "fill",
                    active = true
                })
            end
        end
        
        if explosion.duration <= 0 then
            table.remove(explosions, i)
        end
    end
end

-- Update shell casings
function combatEffectsMod.updateShellCasings(dt)
    for i = #shell_casings, 1, -1 do
        local shell = shell_casings[i]
        shell.duration = shell.duration - dt
        shell.rotation = shell.rotation + shell.rot_speed * dt
        
        -- Apply physics
        shell.vel.y = shell.vel.y + shell.gravity * dt  -- gravity
        shell.pos.x = shell.pos.x + shell.vel.x * dt
        shell.pos.y = shell.pos.y + shell.vel.y * dt
        
        -- Ground collision
        if shell.pos.y > shell.ground_y and shell.vel.y > 0 then
            shell.pos.y = shell.ground_y
            shell.vel.y = -shell.vel.y * shell.bounce
            shell.vel.x = shell.vel.x * shell.friction
            shell.rot_speed = shell.rot_speed * 0.7
        end
        
        if shell.duration <= 0 then
            table.remove(shell_casings, i)
        else
            -- Add shell casing to renderer queue
            local alpha = math.min(1, shell.duration / shell.max_duration)
            if shell.duration < 1 then
                alpha = shell.duration  -- fade out in last second
            end
            
            local props = shell.properties
            api.renderer.addToQueue("world", {
                type = "rectangle",
                x = shell.pos.x,
                y = shell.pos.y,
                width = props.size.width,
                height = props.size.height,
                rotation = shell.rotation,
                color = {props.color[1], props.color[2], props.color[3], alpha},
                mode = "fill",
                active = true
            })
        end
    end
end

-- Update blood splatters
function combatEffectsMod.updateBloodSplatters(dt)
    for i = #blood_splatters, 1, -1 do
        local splatter = blood_splatters[i]
        splatter.duration = splatter.duration - dt
        
        -- Update blood particles
        for j = #splatter.particles, 1, -1 do
            local particle = splatter.particles[j]
            particle.life = particle.life - dt
            particle.x = particle.x + particle.vx * dt
            particle.y = particle.y + particle.vy * dt
            
            -- Apply gravity and drag
            particle.vy = particle.vy + 300 * dt  -- gravity
            particle.vx = particle.vx * 0.95      -- drag
            particle.vy = particle.vy * 0.98
            
            if particle.life <= 0 then
                table.remove(splatter.particles, j)
            else
                -- Add blood particle to renderer queue
                local alpha = particle.life / particle.max_life
                api.renderer.addToQueue("world", {
                    type = "circle",
                    x = particle.x,
                    y = particle.y,
                    radius = particle.size,
                    color = {particle.color[1], particle.color[2], particle.color[3], alpha},
                    mode = "fill",
                    active = true
                })
            end
        end
        
        if splatter.duration <= 0 then
            table.remove(blood_splatters, i)
        end
    end
end

-- Update misc particles (enhanced for gunpowder particles)
function combatEffectsMod.updateParticles(dt)
    for i = #particles, 1, -1 do
        local effect = particles[i]
        effect.duration = effect.duration - dt
        
        -- Update particles
        for j = #effect.particles, 1, -1 do
            local particle = effect.particles[j]
            particle.life = particle.life - dt
            particle.x = particle.x + particle.vx * dt
            particle.y = particle.y + particle.vy * dt
            
            -- Apply physics based on effect type
            if effect.type == "sparks" then
                particle.vy = particle.vy + 300 * dt  -- gravity
                particle.vx = particle.vx * 0.95      -- drag
            elseif effect.type == "gunpowder_particles" then
                -- Apply drag/friction (from legacy system)
                particle.vx = particle.vx * 0.98
                particle.vy = particle.vy * 0.98
                
                -- Slight gravity for realism
                particle.vy = particle.vy + 50 * dt
                
                -- Update rotation
                if particle.rotation and particle.rot_speed then
                    particle.rotation = particle.rotation + particle.rot_speed * dt
                end
            end
            
            if particle.life <= 0 then
                table.remove(effect.particles, j)
            else
                -- Add particle to renderer queue
                local alpha = particle.life / particle.max_life
                
                if effect.type == "sparks" then
                    api.renderer.addToQueue("effects", {
                        type = "circle",
                        x = particle.x,
                        y = particle.y,
                        radius = particle.size,
                        color = {particle.color[1], particle.color[2], particle.color[3], alpha},
                        mode = "fill",
                        active = true
                    })
                elseif effect.type == "gunpowder_particles" then
                    -- Draw gunpowder particle as a small glowing rectangle (from legacy)
                    api.renderer.addToQueue("effects", {
                        type = "rectangle",
                        x = particle.x,
                        y = particle.y,
                        width = particle.size,
                        height = particle.size / 2,
                        rotation = particle.rotation or 0,
                        color = {particle.color[1], particle.color[2], particle.color[3], alpha * 0.7},
                        mode = "fill",
                        active = true
                    })
                    
                    -- Draw glow effect (subtle)
                    api.renderer.addToQueue("effects", {
                        type = "rectangle",
                        x = particle.x,
                        y = particle.y,
                        width = particle.size * 2,
                        height = particle.size,
                        rotation = particle.rotation or 0,
                        color = {particle.color[1], particle.color[2], particle.color[3], alpha * 0.2},
                        mode = "fill",
                        active = true
                    })
                end
            end
        end
        
        if effect.duration <= 0 then
            table.remove(particles, i)
        end
    end
end

-- Draw function is no longer needed - new renderer handles everything
function combatEffectsMod.draw()
    -- All rendering now handled by new renderer queue system in update functions
end


-- Public API
combatEffectsMod.public = {
    createMuzzleFlash = combatEffectsMod.createMuzzleFlash,
    createExplosion = combatEffectsMod.createExplosion,
    createShellEjection = combatEffectsMod.createShellEjection,
    createBloodSplatter = combatEffectsMod.createBloodSplatter,
    createParticleEffect = combatEffectsMod.createParticleEffect,
    createSparks = combatEffectsMod.createSparks
}

return combatEffectsMod