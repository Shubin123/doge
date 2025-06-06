-- Advanced Particle System for Dynamic Visual Effects
-- Replaces sprite-based effects with procedural, adaptive particles

local particle_system = {}

-- Particle system pools for performance
particle_system.pools = {}
particle_system.active_systems = {}
particle_system.effect_templates = {}

-- Simple colored particle texture (1x1 white pixel for dynamic coloring)
local particle_texture = nil

-- Effect categories
particle_system.EFFECT_TYPES = {
    EXPLOSION = "explosion",
    SPARKS = "sparks", 
    SMOKE = "smoke",
    ENERGY = "energy",
    BLOOD = "blood",
    MAGIC = "magic",
    FIRE = "fire",
    ELECTRIC = "electric",
    IMPACT = "impact",
    AURA = "aura",
    TRAIL = "trail"
}

function particle_system.load()
    -- Create a simple 4x4 white texture for particles
    local imageData = love.image.newImageData(4, 4)
    for x = 0, 3 do
        for y = 0, 3 do
            -- Create a soft circular gradient
            local distance = math.sqrt((x-1.5)^2 + (y-1.5)^2)
            local alpha = math.max(0, 1 - distance / 2)
            imageData:setPixel(x, y, 1, 1, 1, alpha)
        end
    end
    particle_texture = love.graphics.newImage(imageData)
    
    -- Initialize effect templates
    particle_system.createEffectTemplates()
    
    print("Particle System: Loaded with dynamic effects")
end

function particle_system.createEffectTemplates()
    local templates = particle_system.effect_templates
    
    -- Explosion effect template
    templates[particle_system.EFFECT_TYPES.EXPLOSION] = {
        particle_count = 50,
        lifetime = {0.8, 1.5},
        emission_rate = 200,
        speed = {100, 300},
        spread = math.pi * 2,
        size_start = {0.5, 1.5},
        size_end = {0.1, 0.3},
        colors = {
            {1.0, 0.8, 0.3, 1.0}, -- Bright orange
            {1.0, 0.4, 0.1, 0.8}, -- Orange-red
            {0.8, 0.2, 0.1, 0.3}, -- Dark red
            {0.3, 0.1, 0.1, 0.0}  -- Fade to dark
        },
        gravity = 200,
        linear_damping = 0.3
    }
    
    -- Sparks effect template
    templates[particle_system.EFFECT_TYPES.SPARKS] = {
        particle_count = 30,
        lifetime = {0.3, 0.8},
        emission_rate = 150,
        speed = {80, 200},
        spread = math.pi * 1.5,
        size_start = {0.2, 0.8},
        size_end = {0.1, 0.2},
        colors = {
            {1.0, 1.0, 0.6, 1.0}, -- Bright yellow
            {1.0, 0.8, 0.3, 0.8}, -- Orange
            {1.0, 0.4, 0.1, 0.3}, -- Red
            {0.2, 0.1, 0.0, 0.0}  -- Fade out
        },
        gravity = 300,
        linear_damping = 0.8
    }
    
    -- Energy effect template
    templates[particle_system.EFFECT_TYPES.ENERGY] = {
        particle_count = 40,
        lifetime = {1.0, 2.0},
        emission_rate = 80,
        speed = {20, 60},
        spread = math.pi * 2,
        size_start = {0.3, 1.0},
        size_end = {0.8, 1.5},
        colors = {
            {0.3, 0.8, 1.0, 0.8}, -- Bright blue
            {0.5, 0.6, 1.0, 0.6}, -- Light blue
            {0.2, 0.4, 0.8, 0.3}, -- Medium blue
            {0.1, 0.2, 0.4, 0.0}  -- Dark blue fade
        },
        gravity = -50, -- Float upward
        linear_damping = 0.5
    }
    
    -- Fire effect template
    templates[particle_system.EFFECT_TYPES.FIRE] = {
        particle_count = 35,
        lifetime = {0.8, 1.2},
        emission_rate = 60,
        speed = {30, 80},
        spread = math.pi * 0.8,
        size_start = {0.4, 1.2},
        size_end = {1.0, 2.0},
        colors = {
            {1.0, 0.2, 0.1, 0.9}, -- Bright red
            {1.0, 0.6, 0.1, 0.7}, -- Orange
            {1.0, 0.9, 0.3, 0.4}, -- Yellow
            {0.8, 0.4, 0.2, 0.0}  -- Smoke fade
        },
        gravity = -100, -- Rise like fire
        linear_damping = 0.2
    }
    
    -- Blood effect template
    templates[particle_system.EFFECT_TYPES.BLOOD] = {
        particle_count = 25,
        lifetime = {0.5, 1.0},
        emission_rate = 100,
        speed = {50, 120},
        spread = math.pi,
        size_start = {0.3, 0.8},
        size_end = {0.2, 0.4},
        colors = {
            {0.8, 0.1, 0.1, 1.0}, -- Dark red
            {0.6, 0.1, 0.1, 0.8}, -- Darker red
            {0.4, 0.1, 0.1, 0.5}, -- Very dark red
            {0.2, 0.05, 0.05, 0.0} -- Brown fade
        },
        gravity = 400,
        linear_damping = 0.9
    }
    
    -- Electric effect template
    templates[particle_system.EFFECT_TYPES.ELECTRIC] = {
        particle_count = 45,
        lifetime = {0.2, 0.6},
        emission_rate = 180,
        speed = {60, 150},
        spread = math.pi * 2,
        size_start = {0.1, 0.4},
        size_end = {0.05, 0.1},
        colors = {
            {0.9, 0.9, 1.0, 1.0}, -- Bright white
            {0.6, 0.8, 1.0, 0.8}, -- Light blue
            {0.3, 0.6, 1.0, 0.5}, -- Medium blue
            {0.1, 0.3, 0.8, 0.0}  -- Dark blue
        },
        gravity = 0,
        linear_damping = 0.6
    }
    
    -- Smoke effect template
    templates[particle_system.EFFECT_TYPES.SMOKE] = {
        particle_count = 30,
        lifetime = {2.0, 3.0},
        emission_rate = 20,
        speed = {10, 40},
        spread = math.pi * 0.5,
        size_start = {0.5, 1.0},
        size_end = {2.0, 3.5},
        colors = {
            {0.3, 0.3, 0.3, 0.6}, -- Gray
            {0.4, 0.4, 0.4, 0.4}, -- Light gray
            {0.5, 0.5, 0.5, 0.2}, -- Lighter gray
            {0.6, 0.6, 0.6, 0.0}  -- Very light fade
        },
        gravity = -30, -- Drift upward
        linear_damping = 0.1
    }
    
    -- Magic/Aura effect template
    templates[particle_system.EFFECT_TYPES.MAGIC] = {
        particle_count = 25,
        lifetime = {1.5, 2.5},
        emission_rate = 40,
        speed = {15, 45},
        spread = math.pi * 2,
        size_start = {0.2, 0.6},
        size_end = {0.4, 1.0},
        colors = {
            {0.8, 0.3, 1.0, 0.8}, -- Purple
            {0.6, 0.5, 1.0, 0.6}, -- Light purple
            {0.4, 0.7, 1.0, 0.4}, -- Blue-purple
            {0.2, 0.4, 0.8, 0.0}  -- Blue fade
        },
        gravity = -20,
        linear_damping = 0.3
    }
    
    -- Impact effect template
    templates[particle_system.EFFECT_TYPES.IMPACT] = {
        particle_count = 20,
        lifetime = {0.3, 0.7},
        emission_rate = 200,
        speed = {80, 160},
        spread = math.pi,
        size_start = {0.3, 0.7},
        size_end = {0.1, 0.2},
        colors = {
            {1.0, 1.0, 1.0, 1.0}, -- White flash
            {1.0, 0.8, 0.6, 0.7}, -- Warm white
            {0.8, 0.6, 0.4, 0.4}, -- Tan
            {0.4, 0.3, 0.2, 0.0}  -- Brown fade
        },
        gravity = 250,
        linear_damping = 0.7
    }
end

-- Create a dynamic particle effect
function particle_system.createEffect(effect_type, x, y, options)
    options = options or {}
    
    local template = particle_system.effect_templates[effect_type]
    if not template then
        print("Warning: Unknown effect type:", effect_type)
        return nil
    end
    
    -- Create particle system
    local ps = love.graphics.newParticleSystem(particle_texture, template.particle_count)
    
    -- Apply template settings with optional overrides
    local lifetime = options.lifetime or template.lifetime
    ps:setParticleLifetime(lifetime[1], lifetime[2])
    
    local emission_rate = options.emission_rate or template.emission_rate
    ps:setEmissionRate(emission_rate)
    
    local speed = options.speed or template.speed
    ps:setSpeed(speed[1], speed[2])
    
    local spread = options.spread or template.spread
    ps:setSpread(spread)
    
    -- Size variation
    local size_start = options.size_start or template.size_start
    local size_end = options.size_end or template.size_end
    ps:setSizes(size_start[1], size_end[1])
    ps:setSizeVariation(size_start[2] - size_start[1])
    
    -- Color progression
    local colors = options.colors or template.colors
    ps:setColors(unpack(colors))
    
    -- Physics
    local gravity = options.gravity or template.gravity or 0
    ps:setLinearAcceleration(0, gravity)
    
    local damping = options.linear_damping or template.linear_damping or 0
    ps:setLinearDamping(damping)
    
    -- Rotation and spin
    ps:setRotation(0, math.pi * 2)
    ps:setSpin(-2, 2)
    
    -- Position
    ps:setPosition(x, y)
    
    -- Burst emission
    local burst_count = options.burst_count or template.particle_count
    ps:emit(burst_count)
    
    -- Add to active systems
    local effect = {
        system = ps,
        x = x,
        y = y,
        type = effect_type,
        lifetime = 5.0, -- Max time before cleanup
        timer = 0,
        options = options
    }
    
    table.insert(particle_system.active_systems, effect)
    
    return effect
end

-- Create continuous particle effect (for auras, trails, etc.)
function particle_system.createContinuousEffect(effect_type, x, y, duration, options)
    local effect = particle_system.createEffect(effect_type, x, y, options)
    if effect then
        effect.continuous = true
        effect.duration = duration or 3.0
        effect.system:start()
    end
    return effect
end

-- Update all particle systems
function particle_system.update(dt)
    for i = #particle_system.active_systems, 1, -1 do
        local effect = particle_system.active_systems[i]
        
        effect.timer = effect.timer + dt
        effect.system:update(dt)
        
        -- Remove expired effects
        if effect.timer >= effect.lifetime and effect.system:getCount() == 0 then
            table.remove(particle_system.active_systems, i)
        elseif effect.continuous and effect.timer >= effect.duration then
            effect.system:stop()
            effect.continuous = false
        end
    end
end

-- Draw all particle systems
function particle_system.draw()
    love.graphics.setBlendMode("alpha", "premultiplied")
    
    for _, effect in ipairs(particle_system.active_systems) do
        love.graphics.draw(effect.system, effect.x, effect.y)
    end
    
    love.graphics.setBlendMode("alpha")
end

-- Add particles to dynamic draw list for depth sorting
function particle_system.populate()
    for _, effect in ipairs(particle_system.active_systems) do
        table.insert(dynamic_draw_list, {
            sort_y = effect.y + 50, -- Adjust for proper depth sorting
            image_or_particles = effect.system,
            x = effect.x,
            y = effect.y,
            color = {1, 1, 1, 1},
            blend_mode = {"alpha", "premultiplied"},
            source_object_type = "dynamic_particles"
        })
    end
end

-- Convenience functions for common effects

function particle_system.explosion(x, y, intensity, color_theme)
    local options = {}
    
    -- Scale based on intensity
    if intensity then
        options.particle_count = math.floor(30 + intensity * 20)
        options.speed = {80 + intensity * 40, 200 + intensity * 100}
        options.size_start = {0.5 * intensity, 1.5 * intensity}
    end
    
    -- Custom color theme
    if color_theme == "fire" then
        options.colors = {
            {1.0, 0.6, 0.1, 1.0},
            {1.0, 0.3, 0.1, 0.8},
            {0.8, 0.1, 0.1, 0.3},
            {0.3, 0.1, 0.1, 0.0}
        }
    elseif color_theme == "ice" then
        options.colors = {
            {0.7, 0.9, 1.0, 1.0},
            {0.5, 0.7, 1.0, 0.8},
            {0.3, 0.5, 0.9, 0.3},
            {0.1, 0.3, 0.7, 0.0}
        }
    elseif color_theme == "poison" then
        options.colors = {
            {0.6, 1.0, 0.2, 1.0},
            {0.4, 0.8, 0.2, 0.8},
            {0.2, 0.6, 0.1, 0.3},
            {0.1, 0.3, 0.1, 0.0}
        }
    end
    
    return particle_system.createEffect(particle_system.EFFECT_TYPES.EXPLOSION, x, y, options)
end

function particle_system.impact(x, y, direction, force)
    local options = {
        spread = math.pi * 0.8, -- More directional
    }
    
    if direction then
        -- Offset particle direction based on impact angle
        options.direction = direction
    end
    
    if force then
        options.speed = {60 * force, 120 * force}
    end
    
    return particle_system.createEffect(particle_system.EFFECT_TYPES.IMPACT, x, y, options)
end

function particle_system.aura(x, y, aura_type, intensity)
    local effect_type = particle_system.EFFECT_TYPES.MAGIC
    
    if aura_type == "fire" then
        effect_type = particle_system.EFFECT_TYPES.FIRE
    elseif aura_type == "electric" then
        effect_type = particle_system.EFFECT_TYPES.ELECTRIC
    elseif aura_type == "energy" then
        effect_type = particle_system.EFFECT_TYPES.ENERGY
    end
    
    local options = {
        emission_rate = 20 + (intensity or 1) * 15,
        speed = {10, 30}
    }
    
    return particle_system.createContinuousEffect(effect_type, x, y, nil, options)
end

-- Adaptive effects that respond to game context
function particle_system.adaptToContext(context_info)
    -- Adjust particle effects based on game state
    local templates = particle_system.effect_templates
    
    if context_info.environment == "dark" then
        -- Enhance glow effects in dark environments
        for _, template in pairs(templates) do
            if template.colors then
                -- Boost brightness for better visibility
                for i, color in ipairs(template.colors) do
                    template.colors[i] = {
                        math.min(1.0, color[1] * 1.2),
                        math.min(1.0, color[2] * 1.2), 
                        math.min(1.0, color[3] * 1.2),
                        color[4]
                    }
                end
            end
        end
    elseif context_info.environment == "underwater" then
        -- Add floating behavior to all particles
        for _, template in pairs(templates) do
            template.gravity = (template.gravity or 0) * 0.3 -- Reduce gravity
            template.linear_damping = (template.linear_damping or 0) + 0.4 -- More damping
        end
    elseif context_info.environment == "windy" then
        -- Add horizontal drift to particles
        for _, template in pairs(templates) do
            template.wind_force = context_info.wind_strength or 50
        end
    end
    
    -- Scale effects based on performance
    if context_info.performance_mode == "low" then
        for _, template in pairs(templates) do
            template.particle_count = math.floor(template.particle_count * 0.6)
            template.emission_rate = math.floor(template.emission_rate * 0.7)
        end
    elseif context_info.performance_mode == "high" then
        for _, template in pairs(templates) do
            template.particle_count = math.floor(template.particle_count * 1.4)
            template.emission_rate = math.floor(template.emission_rate * 1.3)
        end
    end
end

-- Dynamic effect scaling based on camera zoom
function particle_system.scaleForCamera(camera_zoom)
    local scale_factor = 1.0 / camera_zoom
    
    for _, effect in ipairs(particle_system.active_systems) do
        -- Adjust particle size based on zoom
        if effect.system and effect.system.setSizes then
            local current_sizes = {effect.system:getSizes()}
            if #current_sizes >= 2 then
                effect.system:setSizes(
                    current_sizes[1] * scale_factor,
                    current_sizes[2] * scale_factor
                )
            end
        end
    end
end

-- Weather-responsive particle effects
function particle_system.setWeather(weather_type, intensity)
    intensity = intensity or 1.0
    
    if weather_type == "rain" then
        -- Create rain particle effect
        local rain_options = {
            particle_count = math.floor(100 * intensity),
            lifetime = {1.0, 2.0},
            speed = {200, 400},
            colors = {
                {0.7, 0.8, 1.0, 0.6},
                {0.5, 0.6, 0.8, 0.3},
                {0.3, 0.4, 0.6, 0.1},
                {0.1, 0.2, 0.4, 0.0}
            },
            gravity = 500,
            size_start = {0.1, 0.2},
            size_end = {0.05, 0.1}
        }
        
        -- Create rain across the screen
        if camera then
            local cam_x, cam_y = camera.x, camera.y
            for i = 1, 5 do
                local x = cam_x + (i - 3) * 200
                local y = cam_y - 300
                particle_system.createContinuousEffect(
                    particle_system.EFFECT_TYPES.ENERGY, 
                    x, y, 10.0, rain_options
                )
            end
        end
        
    elseif weather_type == "snow" then
        -- Create snow particle effect
        local snow_options = {
            particle_count = math.floor(80 * intensity),
            lifetime = {3.0, 5.0},
            speed = {20, 60},
            colors = {
                {1.0, 1.0, 1.0, 0.8},
                {0.9, 0.9, 1.0, 0.6},
                {0.8, 0.8, 0.9, 0.3},
                {0.7, 0.7, 0.8, 0.0}
            },
            gravity = 100,
            size_start = {0.2, 0.5},
            size_end = {0.1, 0.3}
        }
        
        -- Create snow across the screen
        if camera then
            local cam_x, cam_y = camera.x, camera.y
            for i = 1, 4 do
                local x = cam_x + (i - 2.5) * 250
                local y = cam_y - 300
                particle_system.createContinuousEffect(
                    particle_system.EFFECT_TYPES.MAGIC,
                    x, y, 15.0, snow_options
                )
            end
        end
    end
end

-- Combat-responsive effects
function particle_system.setCombatIntensity(intensity)
    -- Adjust all active effects based on combat intensity
    for _, effect in ipairs(particle_system.active_systems) do
        if effect.type == particle_system.EFFECT_TYPES.SPARKS or 
           effect.type == particle_system.EFFECT_TYPES.EXPLOSION then
            -- Make combat effects more intense
            effect.system:setEmissionRate(effect.system:getEmissionRate() * (1 + intensity))
        end
    end
end

-- Clean up all particle systems
function particle_system.clear()
    particle_system.active_systems = {}
end

return particle_system