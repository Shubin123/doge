local explosionEffectsMod = {
    api = nil,
    config = nil,
    explosions = {},
    nextExplosionId = 1,
    scorchMarks = {},
    soundCache = {}
}

-- Explosion object structure
local function createExplosion(x, y, params)
    return {
        id = explosionEffectsMod.nextExplosionId,
        x = x,
        y = y,
        radius = params.radius or explosionEffectsMod.config.default_radius,
        damage = params.damage or explosionEffectsMod.config.default_damage,
        falloff = params.falloff or explosionEffectsMod.config.damage_falloff,
        owner = params.owner,
        team = params.team,
        startTime = love.timer.getTime(),
        particles = {},
        smokeParticles = {},
        flashAlpha = 1,
        shakeApplied = false,
        soundPlayed = false,
        damageDealt = false,
        color = params.color or {1, 0.8, 0.4},
        smokeColor = params.smokeColor or {0.3, 0.3, 0.3}
    }
end

-- Create particle for explosion effect
local function createParticle(explosion, angle)
    local speed = love.math.random(100, 400)
    return {
        x = explosion.x,
        y = explosion.y,
        vx = math.cos(angle) * speed,
        vy = math.sin(angle) * speed,
        size = love.math.random(3, 8),
        lifetime = love.math.random(0.3, 0.8),
        age = 0,
        color = {
            explosion.color[1] + love.math.random() * 0.2 - 0.1,
            explosion.color[2] + love.math.random() * 0.2 - 0.1,
            explosion.color[3] + love.math.random() * 0.2 - 0.1
        }
    }
end

-- Create smoke particle
local function createSmokeParticle(explosion)
    local angle = love.math.random() * math.pi * 2
    local distance = love.math.random(0, explosion.radius * 0.3)
    return {
        x = explosion.x + math.cos(angle) * distance,
        y = explosion.y + math.sin(angle) * distance,
        vx = love.math.random(-20, 20),
        vy = love.math.random(-50, -20),
        size = love.math.random(20, 40),
        targetSize = love.math.random(60, 100),
        lifetime = explosionEffectsMod.config.smoke_duration,
        age = 0,
        alpha = 0.6
    }
end

-- Calculate damage based on distance
local function calculateDamage(explosion, targetX, targetY)
    local dx = targetX - explosion.x
    local dy = targetY - explosion.y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    if distance > explosion.radius then
        return 0
    end
    
    -- Linear falloff
    local falloffFactor = 1 - (distance / explosion.radius) * explosion.falloff
    return explosion.damage * falloffFactor
end

-- Apply splash damage to all entities in radius
local function applySplashDamage(explosion)
    if explosion.damageDealt then return end
    explosion.damageDealt = true
    
    local api = explosionEffectsMod.api
    
    -- Query all bodies in explosion radius
    local bodies = api.physics.queryCircle(explosion.x, explosion.y, explosion.radius)
    
    for _, body in ipairs(bodies) do
        local userData = body:getUserData()
        if userData then
            local targetX, targetY = body:getPosition()
            local damage = calculateDamage(explosion, targetX, targetY)
            
            if damage > 0 then
                -- Check if we should apply damage based on team/friendly fire settings
                local shouldDamage = true
                
                if not explosionEffectsMod.config.friendly_fire then
                    if userData.type == "player" and explosion.owner == "player" then
                        shouldDamage = false
                    elseif userData.team and explosion.team and userData.team == explosion.team then
                        shouldDamage = false
                    end
                end
                
                if shouldDamage then
                    -- Apply damage
                    if userData.health then
                        userData.health = userData.health - damage
                        
                        -- Notify damage indicators mod if available
                        api.game.sendModMessage("damage_indicators", "show_damage", {
                            x = targetX,
                            y = targetY,
                            damage = math.floor(damage),
                            type = "explosion"
                        })
                        
                        -- Apply knockback
                        local dx = targetX - explosion.x
                        local dy = targetY - explosion.y
                        local dist = math.sqrt(dx * dx + dy * dy)
                        if dist > 0 then
                            local force = (1 - dist / explosion.radius) * 500
                            body:applyLinearImpulse(
                                (dx / dist) * force,
                                (dy / dist) * force
                            )
                        end
                    end
                end
            end
        end
    end
end

-- Apply screen shake based on distance
local function applyScreenShake(explosion)
    if explosion.shakeApplied then return end
    explosion.shakeApplied = true
    
    local api = explosionEffectsMod.api
    
    -- Check if getPlayerPosition exists
    if api.game.getPlayerPosition then
        local playerX, playerY = api.game.getPlayerPosition()
        
        if playerX and playerY then
            local dx = playerX - explosion.x
            local dy = playerY - explosion.y
            local distance = math.sqrt(dx * dx + dy * dy)
            
            -- Calculate shake intensity based on distance
            local maxShakeDistance = explosion.radius * 3
            if distance < maxShakeDistance then
                local intensity = (1 - distance / maxShakeDistance) * explosionEffectsMod.config.screen_shake_intensity
                
                -- Check if shakeCamera exists
                if api.game.shakeCamera then
                    api.game.shakeCamera(intensity, 0.3)
                end
            end
        end
    end
end

-- Initialize explosion
local function initializeExplosion(explosion)
    -- Create initial particles
    local particleCount = explosionEffectsMod.config.particle_count
    for i = 1, particleCount do
        local angle = (i / particleCount) * math.pi * 2
        table.insert(explosion.particles, createParticle(explosion, angle))
    end
    
    -- Create smoke particles
    local smokeCount = math.floor(particleCount * 0.3)
    for i = 1, smokeCount do
        table.insert(explosion.smokeParticles, createSmokeParticle(explosion))
    end
    
    -- Create scorch mark if enabled
    if explosionEffectsMod.config.scorch_marks then
        table.insert(explosionEffectsMod.scorchMarks, {
            x = explosion.x,
            y = explosion.y,
            radius = explosion.radius * 0.8,
            alpha = 0.5,
            lifetime = 30,
            age = 0
        })
    end
end

-- Update particle
local function updateParticle(particle, dt)
    particle.age = particle.age + dt
    if particle.age >= particle.lifetime then
        return false
    end
    
    -- Update position
    particle.x = particle.x + particle.vx * dt
    particle.y = particle.y + particle.vy * dt
    
    -- Apply gravity and drag
    particle.vy = particle.vy + 300 * dt
    particle.vx = particle.vx * (1 - 2 * dt)
    particle.vy = particle.vy * (1 - 2 * dt)
    
    return true
end

-- Update smoke particle
local function updateSmokeParticle(particle, dt)
    particle.age = particle.age + dt
    if particle.age >= particle.lifetime then
        return false
    end
    
    -- Update position
    particle.x = particle.x + particle.vx * dt
    particle.y = particle.y + particle.vy * dt
    
    -- Expand size
    local t = particle.age / particle.lifetime
    particle.size = particle.size + (particle.targetSize - particle.size) * dt * 2
    
    -- Fade out
    particle.alpha = 0.6 * (1 - t)
    
    return true
end

-- Update explosion
local function updateExplosion(explosion, dt)
    local age = love.timer.getTime() - explosion.startTime
    
    -- Play sound on first frame
    if not explosion.soundPlayed then
        explosion.soundPlayed = true
        if explosionEffectsMod.api.audio and explosionEffectsMod.api.audio.play then
            explosionEffectsMod.api.audio.play("explosion", explosion.x, explosion.y)
        end
    end
    
    -- Apply damage on first frame
    if not explosion.damageDealt and age > 0 then
        applySplashDamage(explosion)
        applyScreenShake(explosion)
    end
    
    -- Update flash
    explosion.flashAlpha = math.max(0, 1 - age / explosionEffectsMod.config.flash_duration)
    
    -- Update particles
    for i = #explosion.particles, 1, -1 do
        if not updateParticle(explosion.particles[i], dt) then
            table.remove(explosion.particles, i)
        end
    end
    
    -- Update smoke particles
    for i = #explosion.smokeParticles, 1, -1 do
        if not updateSmokeParticle(explosion.smokeParticles[i], dt) then
            table.remove(explosion.smokeParticles, i)
        end
    end
    
    -- Check if explosion is finished
    return #explosion.particles > 0 or #explosion.smokeParticles > 0 or explosion.flashAlpha > 0
end

-- Update scorch marks
local function updateScorchMarks(dt)
    for i = #explosionEffectsMod.scorchMarks, 1, -1 do
        local mark = explosionEffectsMod.scorchMarks[i]
        mark.age = mark.age + dt
        mark.alpha = 0.5 * (1 - mark.age / mark.lifetime)
        
        if mark.age >= mark.lifetime then
            table.remove(explosionEffectsMod.scorchMarks, i)
        end
    end
end

-- Render explosion
local function renderExplosion(explosion)
    local api = explosionEffectsMod.api
    
    -- Draw flash
    if explosion.flashAlpha > 0 then
        love.graphics.setColor(1, 1, 0.8, explosion.flashAlpha * 0.8)
        love.graphics.circle("fill", explosion.x, explosion.y, explosion.radius * 1.5)
    end
    
    -- Draw particles
    for _, particle in ipairs(explosion.particles) do
        local alpha = 1 - (particle.age / particle.lifetime)
        love.graphics.setColor(particle.color[1], particle.color[2], particle.color[3], alpha)
        love.graphics.circle("fill", particle.x, particle.y, particle.size)
    end
    
    -- Draw smoke particles
    for _, particle in ipairs(explosion.smokeParticles) do
        love.graphics.setColor(
            explosionEffectsMod.smokeColor[1],
            explosionEffectsMod.smokeColor[2],
            explosionEffectsMod.smokeColor[3],
            particle.alpha
        )
        love.graphics.circle("fill", particle.x, particle.y, particle.size)
    end
    
    love.graphics.setColor(1, 1, 1, 1)
end

-- Render scorch marks
local function renderScorchMarks()
    for _, mark in ipairs(explosionEffectsMod.scorchMarks) do
        love.graphics.setColor(0.1, 0.1, 0.1, mark.alpha)
        love.graphics.circle("fill", mark.x, mark.y, mark.radius)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- API function to create explosion
function explosionEffectsMod.createExplosion(x, y, params)
    params = params or {}
    
    -- Limit concurrent explosions
    if #explosionEffectsMod.explosions >= explosionEffectsMod.config.max_concurrent_explosions then
        table.remove(explosionEffectsMod.explosions, 1)
    end
    
    local explosion = createExplosion(x, y, params)
    initializeExplosion(explosion)
    table.insert(explosionEffectsMod.explosions, explosion)
    
    explosionEffectsMod.nextExplosionId = explosionEffectsMod.nextExplosionId + 1
    
    -- Sync to network if host
    if explosionEffectsMod.api.network.isHost() then
        explosionEffectsMod.api.network.sendToAll({
            type = "explosion_sync",
            x = x,
            y = y,
            params = params
        }, "explosion_effects")
    end
    
    return explosion.id
end

-- Network message handler
local function handleNetworkMessage(data, peerId)
    if data.type == "explosion_sync" and not explosionEffectsMod.api.network.isHost() then
        -- Create explosion on client
        local explosion = createExplosion(data.x, data.y, data.params)
        initializeExplosion(explosion)
        table.insert(explosionEffectsMod.explosions, explosion)
        explosionEffectsMod.nextExplosionId = explosionEffectsMod.nextExplosionId + 1
    end
end

-- Initialize mod
function explosionEffectsMod.init(api, config)
    explosionEffectsMod.api = api
    explosionEffectsMod.config = config
    
    -- Register network handler
    api.network.registerMessageHandler("explosion_effects", handleNetworkMessage)
    
    -- Register API for other mods
    api.game.registerModAPI("explosion_effects", {
        createExplosion = explosionEffectsMod.createExplosion
    })
    
    api.utils.log("Explosion Effects mod initialized", "explosion_effects")
end

-- Update explosions
function explosionEffectsMod.update(dt)
    -- Update all explosions
    for i = #explosionEffectsMod.explosions, 1, -1 do
        if not updateExplosion(explosionEffectsMod.explosions[i], dt) then
            table.remove(explosionEffectsMod.explosions, i)
        end
    end
    
    -- Update scorch marks
    updateScorchMarks(dt)
end

-- Draw explosions
function explosionEffectsMod.draw()
    -- Draw scorch marks first (on ground)
    renderScorchMarks()
    
    -- Draw explosions
    for _, explosion in ipairs(explosionEffectsMod.explosions) do
        renderExplosion(explosion)
    end
end

-- Handle mod messages
function explosionEffectsMod.onModMessage(fromMod, messageType, data)
    if messageType == "create_explosion" then
        return explosionEffectsMod.createExplosion(data.x, data.y, data.params)
    end
end

return explosionEffectsMod