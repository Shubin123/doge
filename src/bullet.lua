local vec2 = require("vec2")

local bullet = {}
bullet.world = nil
bullet.t = 0
bullet.instances = {}
bullet.pool = {}  -- object pool for reuse
bullet.groupIndex = -2  -- collision group for bullets
bullet.toReturn = {}  -- deferred list for returning to pool
bullet.tracerShader = nil
bullet.muzzleFlashShader = nil
bullet.muzzleFlashes = {}  -- muzzle flash effects
bullet.shells = {}  -- ejected shell casings
bullet.particles = {}  -- gunpowder confetti particles
bullet.muzzleFlashCanvas = nil  -- canvas for rendering muzzle flashes

-- Initialize the bullet module with the physics world
function bullet.load(world)
    bullet.world = world
    bullet.t = 0
    bullet.instances = {}
    bullet.pool = {}
    bullet.toReturn = {}
    bullet.muzzleFlashes = {}
    bullet.shells = {}
    bullet.particles = {}
    
    -- Load tracer shader
    local shader_code = love.filesystem.read("shaders_/bullet_tracer.frag")
    if shader_code then
        bullet.tracerShader = love.graphics.newShader(shader_code)
    end
    
    -- Load muzzle flash shader
    local muzzle_shader_code = love.filesystem.read("shaders_/muzzle_flash.frag")
    if muzzle_shader_code then
        bullet.muzzleFlashShader = love.graphics.newShader(muzzle_shader_code)
    end
    
    -- Create canvas for muzzle flash rendering
    local width, height = love.graphics.getDimensions()
    bullet.muzzleFlashCanvas = love.graphics.newCanvas(width, height)
end

-- Factory: create a new bullet (with pooling)
-- params = { pos = vec2, dir = vec2, speed = number, damage = number, radius = number, lifetime = number }
function bullet.new(params)
    assert(bullet.world, "bullet.load(world) must be called before creating bullets")
    local pos = params.pos or vec2.new(0, 0)
    local dir = params.dir or vec2.new(1, 0)
    dir = vec2.norm(dir)
    local speed = params.speed or 500
    local damage = params.damage or 1
    local radius = params.radius or 5
    local lifetime = params.lifetime or 5

    local instance
    
    -- Try to reuse from pool
    if #bullet.pool > 0 then
        instance = table.remove(bullet.pool)
        -- Reset position and properties
        instance.body:setPosition(pos.x, pos.y)
        instance.body:setLinearVelocity(0, 0)
        instance.dir = dir
        instance.speed = speed
        instance.damage = damage
        instance.lifetime = lifetime
        instance.birthTime = bullet.t
        instance.prevPos = vec2.new(pos.x, pos.y)
        instance.startPos = vec2.new(pos.x, pos.y)
        instance.trail = {}
    else
        -- Create new instance
        local body = love.physics.newBody(bullet.world, pos.x, pos.y, "dynamic")
        local shape = love.physics.newCircleShape(radius)
        local fixture = love.physics.newFixture(body, shape)
        fixture:setGroupIndex(bullet.groupIndex)

        instance = {
            body      = body,
            fixture   = fixture,
            dir       = dir,
            speed     = speed,
            damage    = damage,
            lifetime  = lifetime,
            birthTime = bullet.t,
            prevPos   = vec2.new(pos.x, pos.y),
            startPos  = vec2.new(pos.x, pos.y),  -- for tracer rendering
            trail     = {},  -- trail positions for visual effect
        }
        
        -- allow collision callback to recover instance
        fixture:setUserData(instance)
    end

    table.insert(bullet.instances, instance)
    return instance
end

-- Update all bullets: advance time, move, expire old bullets
function bullet.update(dt)
    bullet.t = bullet.t + dt
    
    -- Process deferred returns first (world is not locked during update)
    bullet.processDeferredReturns()
    
    -- Update muzzle flashes
    for i = #bullet.muzzleFlashes, 1, -1 do
        local flash = bullet.muzzleFlashes[i]
        flash.life = flash.life - dt
        if flash.life <= 0 then
            table.remove(bullet.muzzleFlashes, i)
        end
    end
    
    -- Update shell casings
    for i = #bullet.shells, 1, -1 do
        local shell = bullet.shells[i]
        shell.life = shell.life - dt
        shell.rotation = shell.rotation + shell.rotSpeed * dt
        
        -- Simple physics simulation
        shell.vel.y = shell.vel.y + 980 * dt  -- gravity
        shell.pos.x = shell.pos.x + shell.vel.x * dt
        shell.pos.y = shell.pos.y + shell.vel.y * dt
        
        -- Ground bounce (simple)
        if shell.pos.y > shell.groundY and shell.vel.y > 0 then
            shell.pos.y = shell.groundY
            shell.vel.y = -shell.vel.y * 0.3  -- bounce with dampening
            shell.vel.x = shell.vel.x * 0.8   -- friction
            shell.rotSpeed = shell.rotSpeed * 0.7  -- rotation dampening
        end
        
        -- Remove when life expires
        if shell.life <= 0 then
            table.remove(bullet.shells, i)
        end
    end
    
    -- Update gunpowder particles
    for i = #bullet.particles, 1, -1 do
        local particle = bullet.particles[i]
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
            table.remove(bullet.particles, i)
        end
    end
    
    for i = #bullet.instances, 1, -1 do
        local inst = bullet.instances[i]

        -- record last position for drawing
        local x, y = inst.body:getPosition()
        inst.prevPos = vec2.new(x, y)
        
        -- Add to trail for visual effect (limit trail length)
        table.insert(inst.trail, 1, {x = x, y = y, time = bullet.t})
        if #inst.trail > 8 then  -- keep last 8 positions
            table.remove(inst.trail)
        end

        -- set constant velocity
        inst.body:setLinearVelocity(inst.dir.x * inst.speed, inst.dir.y * inst.speed)

        -- check lifetime expiration
        local age = bullet.t - inst.birthTime
        if age > inst.lifetime then
            bullet.returnToPool(inst, i)
        end
    end
end

-- Populate dynamic draw list with bullet effects for Y-sorting
function bullet.populate()
    if not dynamic_draw_list then
        return -- Safety check
    end
    
    -- Add muzzle flashes to draw list with proper offset to avoid interfering with map elements
    for _, flash in ipairs(bullet.muzzleFlashes) do
        table.insert(dynamic_draw_list, {
            sort_y = flash.pos.y + 10, -- Small offset to ensure proper layering
            source_object_type = "muzzle_flash",
            flash_data = flash,
            color = {1, 1, 1, 1},
            blend_mode = {"alpha"} -- Changed from "add" to "alpha" to prevent map interference
        })
    end
    
    -- Add gunpowder particles to draw list
    for _, particle in ipairs(bullet.particles) do
        table.insert(dynamic_draw_list, {
            sort_y = particle.pos.y + 5, -- Small offset for particles
            source_object_type = "gunpowder_particle", 
            particle_data = particle,
            color = {1, 1, 1, 1},
            blend_mode = {"alpha"} -- Changed from "add" to "alpha" for consistency
        })
    end
    
    -- Add shell casings to draw list (ground level objects)
    for _, shell in ipairs(bullet.shells) do
        table.insert(dynamic_draw_list, {
            sort_y = shell.pos.y + 50, -- Shells fall on ground, should be behind most objects
            source_object_type = "shell_casing",
            shell_data = shell,
            color = {1, 1, 1, 1},
            blend_mode = {"alpha"}
        })
    end
    
    -- Add bullet tracers to draw list with proper depth handling
    for _, inst in ipairs(bullet.instances) do
        local x, y = inst.body:getPosition()
        
        -- Calculate distance from player for fading effect
        local playerX, playerY = player.getPosition()
        local distance = math.sqrt((x - playerX)^2 + (y - playerY)^2)
        
        -- Use much larger Y offset for distant bullets so they render behind objects
        local sort_offset = 1
        if distance > 200 then
            -- Distant bullets should render behind most objects
            sort_offset = 80 -- This puts them behind walls/trees that typically have +45-75 offsets
        elseif distance > 100 then
            -- Medium distance bullets get moderate depth
            sort_offset = 40
        end
        
        table.insert(dynamic_draw_list, {
            sort_y = y + sort_offset,
            source_object_type = "bullet_tracer",
            bullet_data = inst,
            x = x,
            y = y,
            distance = distance, -- Pass distance for fading calculations
            color = {1, 1, 1, 1},
            blend_mode = {"alpha"}
        })
    end
end

-- Draw bullets with advanced tracer effects
function bullet.draw()
    -- This function is now deprecated in favor of populate()
    -- Keeping for backward compatibility
    bullet.drawMuzzleFlashes()
    bullet.drawShells() 
    bullet.drawParticles()
    
    -- Draw bullet tracers
    for _, inst in ipairs(bullet.instances) do
        local x, y = inst.body:getPosition()
        local age = bullet.t - inst.birthTime
        
        -- Draw bright tracer core (reduced brightness to prevent shader issues)
        love.graphics.setColor(0.9, 0.9, 0.7, 0.8)
        love.graphics.setLineWidth(3)
        love.graphics.line(inst.prevPos.x, inst.prevPos.y, x, y)
        
        -- Draw glowing outer tracer (reduced brightness)
        love.graphics.setColor(0.8, 0.6, 0.3, 0.5)
        love.graphics.setLineWidth(6)
        love.graphics.line(inst.prevPos.x, inst.prevPos.y, x, y)
        
        -- Draw fading trail
        if #inst.trail > 1 then
            for i = 1, #inst.trail - 1 do
                local p1 = inst.trail[i]
                local p2 = inst.trail[i + 1]
                local trailAlpha = (1 - (i / #inst.trail)) * 0.4
                love.graphics.setColor(1, 0.8, 0.4, trailAlpha)
                love.graphics.setLineWidth(2)
                love.graphics.line(p1.x, p1.y, p2.x, p2.y)
            end
        end
        
        -- Draw bullet impact point
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.circle("fill", x, y, 2)
    end
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- Handle collisions: bullet vs enemy or obstacles
function bullet.collision(fixture_a, fixture_b, contact)
    local bullet_f, other_f
    if fixture_a:getGroupIndex() == bullet.groupIndex then
        bullet_f = fixture_a
        other_f  = fixture_b
    elseif fixture_b:getGroupIndex() == bullet.groupIndex then
        bullet_f = fixture_b
        other_f  = fixture_a
    end
    if not bullet_f then return end

    local inst = bullet_f:getUserData()
    local otherBody = other_f:getBody()
    local otherGroup = other_f:getGroupIndex()

    -- if hit an enemy, apply damage (here we destroy on hit)
    if otherGroup == -777 then
        -- destroys the enemy physics body and removes it from enemies_bods
        if checkDestroy then
            checkDestroy(enemies_bods, otherBody)
        end
    end

    -- defer removal until after physics step
    table.insert(bullet.toReturn, inst)
end

-- Return bullet to pool for reuse (instead of destroying)
function bullet.returnToPool(inst, index)
    -- Reset physics state but keep body/fixture for reuse
    inst.body:setLinearVelocity(0, 0)
    inst.body:setPosition(-1000, -1000)  -- move offscreen
    
    -- Add to pool if not too many (limit pool size)
    if #bullet.pool < 50 then
        table.insert(bullet.pool, inst)
    else
        -- Destroy if pool is full
        inst.body:destroy()
    end
    
    if index then
        table.remove(bullet.instances, index)
    end
end

-- Process deferred bullet returns (called during update when world is not locked)
function bullet.processDeferredReturns()
    for _, inst in ipairs(bullet.toReturn) do
        -- Find and remove from instances
        for i = #bullet.instances, 1, -1 do
            if bullet.instances[i] == inst then
                bullet.returnToPool(inst, i)
                break
            end
        end
    end
    bullet.toReturn = {}  -- clear the list
end

-- Create particle effect (gunpowder confetti)
function bullet.createParticleEffect(pos, dir, params)
    params = params or {}
    local count = params.count or 8
    local colors = params.colors or {{1, 0.8, 0.3}, {1, 0.5, 0.2}}
    local lifespan = params.lifespan or 0.3
    local speed = params.speed or {min = 120, max = 250}
    local size = params.size or {min = 1, max = 3}
    local spreadAngle = params.spreadAngle or math.rad(25)
    
    for i = 1, count do
        -- Calculate random direction within the spread cone
        local baseAngle = math.atan2(dir.y, dir.x)
        local randomSpread = (math.random() - 0.5) * spreadAngle * 2
        local particleAngle = baseAngle + randomSpread
        
        -- Calculate velocity
        local particleSpeed = speed.min + math.random() * (speed.max - speed.min)
        local vel = vec2.new(
            math.cos(particleAngle) * particleSpeed,
            math.sin(particleAngle) * particleSpeed
        )
        
        -- Random color from the provided palette
        local color = colors[math.random(#colors)]
        
        -- Random size
        local particleSize = size.min + math.random() * (size.max - size.min)
        
        table.insert(bullet.particles, {
            pos = vec2.new(pos.x, pos.y),
            vel = vel,
            life = lifespan + math.random() * lifespan * 0.3, -- slight variation
            maxLife = lifespan,
            color = {color[1], color[2], color[3]},
            size = particleSize,
            rotation = math.random() * math.pi * 2,
            rotSpeed = (math.random() - 0.5) * 10
        })
    end
end

-- Create muzzle flash effect
function bullet.createMuzzleFlash(pos, dir, params)
    params = params or {}
    table.insert(bullet.muzzleFlashes, {
        pos = vec2.new(pos.x, pos.y),
        dir = vec2.norm(vec2.new(dir.x, dir.y)),
        life = params.duration or 0.08,  -- flash duration
        maxLife = params.duration or 0.08,
        size = params.size or math.random(12, 20),
        coneAngle = params.coneAngle or math.rad(35),  -- 35 degree half-angle
        coneLength = params.coneLength or 150,  -- cone extends 150 pixels
        color = params.color or {1, 0.9, 0.7},  -- warm white/yellow
        intensity = params.intensity or 1.0,
        useShader = params.useShader ~= false  -- default to true
    })
end

-- Draw muzzle flash effects
function bullet.drawMuzzleFlashes()
    if #bullet.muzzleFlashes == 0 then return end
    
    -- Set additive blend mode for brighter effect
    love.graphics.setBlendMode("add")
    
    for _, flash in ipairs(bullet.muzzleFlashes) do
        local alpha = flash.life / flash.maxLife
        local size = flash.size * alpha
        
        -- Draw cone-shaped flash using triangular geometry
        local coneLength = flash.coneLength * alpha
        local coneAngle = flash.coneAngle
        
        -- Calculate cone vertices
        local perpDir = vec2.new(-flash.dir.y, flash.dir.x)  -- perpendicular to direction
        local coneEnd = flash.pos + flash.dir * coneLength
        local leftVertex = coneEnd + perpDir * math.tan(coneAngle) * coneLength
        local rightVertex = coneEnd - perpDir * math.tan(coneAngle) * coneLength
        
        -- Draw cone with gradient effect (multiple passes for smooth gradient)
        for i = 1, 5 do
            local gradientFactor = i / 5
            local currentAlpha = alpha * (1 - gradientFactor * 0.7) * flash.intensity * 1.5  -- Increased intensity
            local currentSize = coneLength * (1 - gradientFactor * 0.3)
            
            love.graphics.setColor(flash.color[1], flash.color[2], flash.color[3], currentAlpha)
            
            -- Calculate vertices for this gradient layer
            local layerEnd = flash.pos + flash.dir * currentSize
            local layerLeft = layerEnd + perpDir * math.tan(coneAngle) * currentSize * gradientFactor
            local layerRight = layerEnd - perpDir * math.tan(coneAngle) * currentSize * gradientFactor
            
            -- Draw triangle
            love.graphics.polygon("fill", 
                flash.pos.x, flash.pos.y,
                layerLeft.x, layerLeft.y,
                layerRight.x, layerRight.y
            )
        end
        
        -- Draw bright core at muzzle
        love.graphics.setColor(flash.color[1], flash.color[2], flash.color[3], alpha * flash.intensity)
        love.graphics.circle("fill", flash.pos.x, flash.pos.y, size * 0.8)
        
        -- Draw outer glow
        love.graphics.setColor(flash.color[1] * 0.6, flash.color[2] * 0.4, flash.color[3] * 0.2, alpha * 0.5)
        love.graphics.circle("fill", flash.pos.x, flash.pos.y, size * 1.5)
    end
    
    -- Reset blend mode
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
end

-- Apply muzzle flash shader as a post-processing effect
function bullet.applyMuzzleFlashShader(canvas)
    if #bullet.muzzleFlashes == 0 or not bullet.muzzleFlashShader then
        return canvas
    end
    
    -- Create a temporary canvas for the effect
    love.graphics.push()
    love.graphics.origin()
    
    local width, height = canvas:getDimensions()
    love.graphics.setCanvas(bullet.muzzleFlashCanvas)
    love.graphics.clear()
    
    -- Apply shader for each flash
    for _, flash in ipairs(bullet.muzzleFlashes) do
        if flash.useShader then
            local alpha = flash.life / flash.maxLife
            
            love.graphics.setShader(bullet.muzzleFlashShader)
            
            -- Send uniforms to shader
            bullet.muzzleFlashShader:send("flash_pos", {flash.pos.x, flash.pos.y})
            bullet.muzzleFlashShader:send("flash_dir", {flash.dir.x, flash.dir.y})
            bullet.muzzleFlashShader:send("flash_intensity", flash.intensity * alpha)
            bullet.muzzleFlashShader:send("cone_angle", flash.coneAngle)
            bullet.muzzleFlashShader:send("cone_length", flash.coneLength)
            bullet.muzzleFlashShader:send("flash_color", flash.color)
            bullet.muzzleFlashShader:send("time", bullet.t)
            
            -- Draw the canvas with shader applied
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(canvas, 0, 0)
            
            -- Update canvas for next flash
            canvas = bullet.muzzleFlashCanvas
        end
    end
    
    love.graphics.setShader()
    love.graphics.setCanvas()
    love.graphics.pop()
    
    return canvas
end

-- Create shell ejection effect
function bullet.createShellEjection(gunPos, gunDir, shellType)
    -- Calculate ejection position (right side of gun barrel)
    local rightDir = vec2.new(-gunDir.y, gunDir.x)  -- perpendicular to gun direction
    local ejectionPos = gunPos + rightDir * 8  -- eject to the right side
    
    -- Calculate ejection velocity
    local ejectionVel = rightDir * (80 + math.random() * 40)  -- rightward velocity
    ejectionVel.y = ejectionVel.y - (50 + math.random() * 30)  -- slight upward component
    
    -- Determine shell color and size based on type
    local color, size
    if shellType == "shotgun" then
        color = {0.8, 0.2, 0.2}  -- red
        size = {width = 6, height = 12}
    elseif shellType == "pistol" then
        color = {0.9, 0.7, 0.3}  -- brass
        size = {width = 4, height = 8}
    elseif shellType == "rifle" then
        color = {0.9, 0.7, 0.3}  -- brass
        size = {width = 5, height = 15}
    else  -- SMG or default
        color = {0.9, 0.7, 0.3}  -- brass
        size = {width = 4, height = 10}
    end
    
    table.insert(bullet.shells, {
        pos = vec2.new(ejectionPos.x, ejectionPos.y),
        vel = ejectionVel,
        rotation = math.random() * math.pi * 2,
        rotSpeed = (math.random() - 0.5) * 10,  -- random spin
        life = 3 + math.random() * 1,  -- 3-4 seconds
        maxLife = 4,
        color = color,
        size = size,
        groundY = ejectionPos.y + 100  -- approximate ground level
    })
end

-- Draw shell casings
function bullet.drawShells()
    for _, shell in ipairs(bullet.shells) do
        local alpha = math.min(1, shell.life / shell.maxLife)
        if shell.life < 1 then
            alpha = shell.life  -- fade out in last second
        end
        
        love.graphics.push()
        love.graphics.translate(shell.pos.x, shell.pos.y)
        love.graphics.rotate(shell.rotation)
        
        -- Draw shell casing as small rectangle
        love.graphics.setColor(shell.color[1], shell.color[2], shell.color[3], alpha)
        love.graphics.rectangle("fill", -shell.size.width/2, -shell.size.height/2, 
                              shell.size.width, shell.size.height)
        
        -- Add rim highlight
        love.graphics.setColor(1, 1, 1, alpha * 0.5)
        love.graphics.rectangle("line", -shell.size.width/2, -shell.size.height/2, 
                              shell.size.width, shell.size.height)
        
        love.graphics.pop()
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw gunpowder particles
function bullet.drawParticles()
    for _, particle in ipairs(bullet.particles) do
        bullet.drawSingleParticle(particle)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Individual drawing functions for Y-sorted rendering
function bullet.drawSingleMuzzleFlash(flash)
    -- Set additive blending only for this effect
    love.graphics.setBlendMode("add")
    
    local alpha = flash.life / flash.maxLife
    local size = flash.size * alpha
    
    -- Draw cone-shaped flash using triangular geometry
    local coneLength = flash.coneLength * alpha
    local coneAngle = flash.coneAngle
    
    -- Calculate cone vertices
    local perpDir = vec2.new(-flash.dir.y, flash.dir.x)
    local coneEnd = flash.pos + flash.dir * coneLength
    
    -- Draw cone with gradient effect (reduced intensity to prevent map interference)
    for i = 1, 5 do
        local gradientFactor = i / 5
        local currentAlpha = alpha * (1 - gradientFactor * 0.7) * flash.intensity * 0.8 -- Reduced from 1.5 to 0.8
        local currentSize = coneLength * (1 - gradientFactor * 0.3)
        
        love.graphics.setColor(flash.color[1], flash.color[2], flash.color[3], currentAlpha)
        
        local layerEnd = flash.pos + flash.dir * currentSize
        local layerLeft = layerEnd + perpDir * math.tan(coneAngle) * currentSize * gradientFactor
        local layerRight = layerEnd - perpDir * math.tan(coneAngle) * currentSize * gradientFactor
        
        love.graphics.polygon("fill", 
            flash.pos.x, flash.pos.y,
            layerLeft.x, layerLeft.y,
            layerRight.x, layerRight.y
        )
    end
    
    -- Draw bright core at muzzle (reduced intensity)
    love.graphics.setColor(flash.color[1], flash.color[2], flash.color[3], alpha * flash.intensity * 0.6)
    love.graphics.circle("fill", flash.pos.x, flash.pos.y, size * 0.8)
    
    -- Draw outer glow (reduced intensity)
    love.graphics.setColor(flash.color[1] * 0.6, flash.color[2] * 0.4, flash.color[3] * 0.2, alpha * 0.3)
    love.graphics.circle("fill", flash.pos.x, flash.pos.y, size * 1.5)
    
    -- Reset blend mode
    love.graphics.setBlendMode("alpha")
end

function bullet.drawSingleParticle(particle)
    -- Use alpha blending for particles to prevent map interference
    love.graphics.setBlendMode("alpha")
    
    local alpha = particle.life / particle.maxLife
    
    love.graphics.push()
    love.graphics.translate(particle.pos.x, particle.pos.y)
    love.graphics.rotate(particle.rotation)
    
    -- Draw particle as a small glowing rectangle/string (reduced opacity)
    love.graphics.setColor(particle.color[1], particle.color[2], particle.color[3], alpha * 0.7)
    love.graphics.rectangle("fill", -particle.size/2, -particle.size/4, particle.size, particle.size/2)
    
    -- Draw glow effect (much more subtle)
    love.graphics.setColor(particle.color[1], particle.color[2], particle.color[3], alpha * 0.2)
    love.graphics.rectangle("fill", -particle.size, -particle.size/2, particle.size * 2, particle.size)
    
    love.graphics.pop()
end

function bullet.drawSingleShell(shell)
    local alpha = math.min(1, shell.life / shell.maxLife)
    if shell.life < 1 then
        alpha = shell.life
    end
    
    love.graphics.push()
    love.graphics.translate(shell.pos.x, shell.pos.y)
    love.graphics.rotate(shell.rotation)
    
    -- Draw shell casing as small rectangle
    love.graphics.setColor(shell.color[1], shell.color[2], shell.color[3], alpha)
    love.graphics.rectangle("fill", -shell.size.width/2, -shell.size.height/2, 
                          shell.size.width, shell.size.height)
    
    -- Add rim highlight
    love.graphics.setColor(1, 1, 1, alpha * 0.5)
    love.graphics.rectangle("line", -shell.size.width/2, -shell.size.height/2, 
                          shell.size.width, shell.size.height)
    
    love.graphics.pop()
end

function bullet.drawSingleTracer(inst, x, y, distance)
    -- Use alpha blending to prevent map interference
    love.graphics.setBlendMode("alpha")
    
    local age = bullet.t - inst.birthTime
    distance = distance or 0
    
    -- Calculate distance-based fade factor
    local fade_factor = 1.0
    if distance > 150 then
        -- Start fading after 150 pixels
        fade_factor = math.max(0.1, 1.0 - ((distance - 150) / 200)) -- Fade over 200 pixels
    end
    
    -- Apply distance fade to all alpha values
    local core_alpha = 0.6 * fade_factor
    local glow_alpha = 0.3 * fade_factor
    local trail_alpha_base = 0.2 * fade_factor
    
    -- Skip drawing if too faded
    if fade_factor < 0.15 then
        return
    end
    
    -- Draw bright tracer core (with distance fade)
    love.graphics.setColor(0.9, 0.9, 0.7, core_alpha)
    love.graphics.setLineWidth(3)
    love.graphics.line(inst.prevPos.x, inst.prevPos.y, x, y)
    
    -- Draw glowing outer tracer (with distance fade)
    love.graphics.setColor(0.8, 0.6, 0.3, glow_alpha)
    love.graphics.setLineWidth(6)
    love.graphics.line(inst.prevPos.x, inst.prevPos.y, x, y)
    
    -- Draw fading trail (with distance fade)
    if #inst.trail > 1 and fade_factor > 0.3 then -- Only draw trail if not too distant
        for i = 1, #inst.trail - 1 do
            local p1 = inst.trail[i]
            local p2 = inst.trail[i + 1]
            local trailAlpha = (1 - (i / #inst.trail)) * trail_alpha_base
            love.graphics.setColor(1, 0.8, 0.4, trailAlpha)
            love.graphics.setLineWidth(2)
            love.graphics.line(p1.x, p1.y, p2.x, p2.y)
        end
    end
    
    -- Draw bullet impact point (with distance fade)
    love.graphics.setColor(1, 1, 1, fade_factor)
    love.graphics.circle("fill", x, y, 2)
    love.graphics.setLineWidth(1)
end

return bullet