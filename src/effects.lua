local effects = {}

-- Enhanced effect systems
local hitmarkers = {}
local damage_numbers = {}
local screen_shakes = {}
local particle_bursts = {}

-- Effect resources
hitmarkerImage = nil
local sparks_image = nil
local blood_image = nil
local electric_image = nil

-- Screen shake system
effects.screen_shake = {
    intensity = 0,
    duration = 0,
    frequency = 20,
    offset_x = 0,
    offset_y = 0
}

function effects.load()
    -- Load effect images with transparency handling
    hitmarkerImage = love.graphics.newImage("gfx/menu/hitmarker_1.png")
    sparks_image = love.graphics.newImage("gfx/fx/Spritesheets/Sparks-Sheet.png")
    blood_image = love.graphics.newImage("gfx/fx/Spritesheets/Blood Splat.png")
    electric_image = love.graphics.newImage("gfx/fx/Spritesheets/Eletric A-Sheet.png")
    
    -- Set proper filtering for better transparency
    hitmarkerImage:setFilter("linear", "linear")
    sparks_image:setFilter("linear", "linear")
    blood_image:setFilter("linear", "linear")
    electric_image:setFilter("linear", "linear")
    
    -- Create particle systems for various effects
    effects.spark_particles = love.graphics.newParticleSystem(sparks_image, 100)
    effects.spark_particles:setParticleLifetime(0.3, 0.8)
    effects.spark_particles:setEmissionRate(50)
    effects.spark_particles:setSizeVariation(0.5)
    effects.spark_particles:setSpeed(50, 150)
    effects.spark_particles:setLinearDamping(0.5)
    effects.spark_particles:setColors(1, 1, 0.3, 1, 1, 0.5, 0.1, 0)
    
    effects.blood_particles = love.graphics.newParticleSystem(blood_image, 50)
    effects.blood_particles:setParticleLifetime(0.5, 1.2)
    effects.blood_particles:setEmissionRate(30)
    effects.blood_particles:setSizeVariation(0.8)
    effects.blood_particles:setSpeed(20, 80)
    effects.blood_particles:setLinearDamping(0.8)
    effects.blood_particles:setColors(0.8, 0.1, 0.1, 1, 0.5, 0.05, 0.05, 0)
end

function effects.newHitMarker(x, y)

    local hitmarker = {
        x = x,
        y = y,
        scale = 1.5,  
        rotation = 0, 
        alpha = 1,    
        lifetime = 0.5, 
        timer = 0     
    }

    table.insert(hitmarkers, hitmarker)

end

function effects.update(dt)
    -- Update hitmarkers
    for i = #hitmarkers, 1, -1 do
        local hm = hitmarkers[i]
        hm.timer = hm.timer + dt

        local lifePercent = hm.timer / hm.lifetime
        hm.scale = 1.5 - (0.5 * lifePercent)  
        hm.alpha = 1 - lifePercent            

        if hm.timer >= hm.lifetime then
            table.remove(hitmarkers, i)
        end
    end
    
    -- Update damage numbers
    for i = #damage_numbers, 1, -1 do
        local dn = damage_numbers[i]
        dn.timer = dn.timer + dt
        
        local lifePercent = dn.timer / dn.lifetime
        dn.y = dn.y - dt * 50 -- Float upward
        dn.alpha = 1 - lifePercent
        dn.scale = 1.0 + lifePercent * 0.5
        
        if dn.timer >= dn.lifetime then
            table.remove(damage_numbers, i)
        end
    end
    
    -- Update screen shake
    if effects.screen_shake.duration > 0 then
        effects.screen_shake.duration = effects.screen_shake.duration - dt
        
        if effects.screen_shake.duration > 0 then
            local shake_amount = effects.screen_shake.intensity * (effects.screen_shake.duration / 0.5)
            effects.screen_shake.offset_x = (math.random() - 0.5) * shake_amount
            effects.screen_shake.offset_y = (math.random() - 0.5) * shake_amount
        else
            effects.screen_shake.offset_x = 0
            effects.screen_shake.offset_y = 0
            effects.screen_shake.intensity = 0
        end
    end
    
    -- Update particle systems
    if effects.spark_particles then
        effects.spark_particles:update(dt)
    end
    if effects.blood_particles then
        effects.blood_particles:update(dt)
    end
    
    -- Update particle bursts
    for i = #particle_bursts, 1, -1 do
        local burst = particle_bursts[i]
        burst.timer = burst.timer + dt
        burst.particles:update(dt)
        
        if burst.timer >= burst.lifetime then
            table.remove(particle_bursts, i)
        end
    end
end

function effects.draw()
    love.graphics.setBlendMode("alpha")
    
    -- Draw hitmarkers
    for _, hm in ipairs(hitmarkers) do
        local r, g, b, a = love.graphics.getColor()
        love.graphics.setColor(1, 1, 1, hm.alpha)
        
        love.graphics.draw(
            hitmarkerImage,
            hm.x,
            hm.y,
            hm.rotation,          
            hm.scale, hm.scale,   
            hitmarkerImage:getWidth() / 2,  
            hitmarkerImage:getHeight() / 2  
        )
        
        love.graphics.setColor(r, g, b, a)
    end
    
    -- Draw damage numbers
    love.graphics.setFont(love.graphics.getFont()) -- Ensure font is set
    
    for _, dn in ipairs(damage_numbers) do
        local r, g, b, a = love.graphics.getColor()
        love.graphics.setColor(dn.color[1], dn.color[2], dn.color[3], dn.alpha)
        
        local text = tostring(dn.damage)
        local font = love.graphics.getFont()
        local text_width = font:getWidth(text)
        local text_height = font:getHeight()
        
        love.graphics.print(
            text,
            dn.x - text_width/2,
            dn.y - text_height/2,
            0,
            dn.scale,
            dn.scale
        )
        
        love.graphics.setColor(r, g, b, a)
    end
    
    -- Draw particle bursts
    love.graphics.setBlendMode("lighten")
    
    for _, burst in ipairs(particle_bursts) do
        love.graphics.draw(burst.particles, burst.x, burst.y)
    end
    
    love.graphics.setBlendMode("alpha")
end

function effects.clear()
    hitmarkers = {}
    damage_numbers = {}
    particle_bursts = {}
    effects.screen_shake.intensity = 0
    effects.screen_shake.duration = 0
    effects.screen_shake.offset_x = 0
    effects.screen_shake.offset_y = 0
end

-- Enhanced effect creation functions

-- Create floating damage number
function effects.newDamageNumber(x, y, damage, color)
    color = color or {1, 1, 1} -- Default white
    
    local damage_number = {
        x = x,
        y = y,
        damage = damage,
        color = color,
        alpha = 1,
        scale = 1,
        lifetime = 2.0,
        timer = 0
    }
    
    table.insert(damage_numbers, damage_number)
end

-- Create screen shake effect
function effects.addScreenShake(intensity, duration)
    duration = duration or 0.3
    
    if intensity > effects.screen_shake.intensity then
        effects.screen_shake.intensity = intensity
        effects.screen_shake.duration = duration
    end
end

-- Get screen shake offset for camera
function effects.getScreenShakeOffset()
    return effects.screen_shake.offset_x, effects.screen_shake.offset_y
end

-- Create particle burst effect
function effects.createParticleBurst(x, y, effect_type, color)
    color = color or {1, 1, 1}
    
    local particles
    if effect_type == "sparks" then
        particles = love.graphics.newParticleSystem(sparks_image, 30)
        particles:setParticleLifetime(0.2, 0.6)
        particles:setEmissionRate(100)
        particles:setSpeed(80, 200)
        particles:setSpread(math.pi * 2)
        particles:setColors(color[1], color[2], color[3], 1, color[1]*0.5, color[2]*0.5, color[3]*0.5, 0)
    elseif effect_type == "blood" then
        particles = love.graphics.newParticleSystem(blood_image, 20)
        particles:setParticleLifetime(0.5, 1.0)
        particles:setEmissionRate(50)
        particles:setSpeed(30, 100)
        particles:setSpread(math.pi)
        particles:setColors(0.8, 0.1, 0.1, 1, 0.5, 0.05, 0.05, 0)
    else
        -- Default energy burst
        particles = love.graphics.newParticleSystem(electric_image, 25)
        particles:setParticleLifetime(0.3, 0.8)
        particles:setEmissionRate(80)
        particles:setSpeed(50, 150)
        particles:setSpread(math.pi * 2)
        particles:setColors(color[1], color[2], color[3], 1, color[1]*0.3, color[2]*0.3, color[3]*0.3, 0)
    end
    
    particles:setLinearDamping(0.5)
    particles:setSizeVariation(0.5)
    particles:emit(particles:getCount())
    
    local burst = {
        x = x,
        y = y,
        particles = particles,
        timer = 0,
        lifetime = 3.0
    }
    
    table.insert(particle_bursts, burst)
end

-- Enhanced hit marker with dynamic particles
function effects.newEnhancedHitMarker(x, y, damage, is_critical)
    -- Standard hit marker
    effects.newHitMarker(x, y)
    
    -- Damage number
    local color = is_critical and {1, 0.3, 0.3} or {1, 1, 0.5}
    effects.newDamageNumber(x, y - 20, damage, color)
    
    -- Dynamic particle effect based on damage and critical status
    if particle_system then
        if is_critical then
            -- Critical hit - blood and sparks
            particle_system.createEffect(particle_system.EFFECT_TYPES.BLOOD, x, y, {
                particle_count = 20,
                speed = {40, 100}
            })
            particle_system.createEffect(particle_system.EFFECT_TYPES.SPARKS, x, y, {
                particle_count = 15,
                speed = {80, 150}
            })
        else
            -- Normal hit - impact effect
            particle_system.impact(x, y, nil, damage / 3)
        end
    end
    
    -- Screen shake for big hits
    if damage >= 3 or is_critical then
        effects.addScreenShake(damage * 2, 0.2)
    end
end

return effects