local vec2 = require("vec2")

local bullet = {}
bullet.world = nil
bullet.t = 0
bullet.instances = {}
bullet.pool = {}  -- object pool for reuse
bullet.groupIndex = -2  -- collision group for bullets
bullet.toReturn = {}  -- deferred list for returning to pool
bullet.tracerShader = nil
bullet.muzzleFlashes = {}  -- muzzle flash effects
bullet.shells = {}  -- ejected shell casings

-- Dynamic rendering system
bullet.renderEvents = {}  -- event queue for rendering changes
bullet.renderSettings = {
    maxVisible = 50,  -- maximum bullets to render at once
    lodDistance = 200,  -- distance threshold for LOD
    cullDistance = 500,  -- distance to cull bullets
    adaptiveQuality = true,  -- enable adaptive quality
    currentQuality = 1.0,  -- current render quality (0.1 to 1.0)
    lastFrameTime = 0,  -- track frame time for adaptive quality
    targetFrameTime = 1/60,  -- target 60 FPS
    densityThreshold = 20,  -- bullet count threshold for density adjustments
    densityHistory = {},  -- track bullet count over time
    performanceMode = false  -- emergency performance mode
}

-- Initialize the bullet module with the physics world
function bullet.load(world)
    bullet.world = world
    bullet.t = 0
    bullet.instances = {}
    bullet.pool = {}
    bullet.toReturn = {}
    bullet.muzzleFlashes = {}
    bullet.shells = {}
    bullet.renderEvents = {}
    
    -- Load tracer shader
    local shader_code = love.filesystem.read("shaders_/bullet_tracer.frag")
    if shader_code then
        bullet.tracerShader = love.graphics.newShader(shader_code)
    end
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
        
        -- Dynamic rendering properties
        instance.visible = true
        instance.lodLevel = 0  -- 0=full detail, 1=medium, 2=low detail
        instance.lastCullCheck = bullet.t
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
            
            -- Dynamic rendering properties
            visible = true,
            lodLevel = 0,  -- 0=full detail, 1=medium, 2=low detail
            lastCullCheck = bullet.t
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
    
    -- Track frame time for adaptive quality
    bullet.renderSettings.lastFrameTime = dt
    
    -- Process deferred returns first (world is not locked during update)
    bullet.processDeferredReturns()
    
    -- Process rendering events
    bullet.processRenderEvents()
    
    -- Update adaptive quality based on performance
    bullet.updateAdaptiveQuality(dt)
    
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
    
    for i = #bullet.instances, 1, -1 do
        local inst = bullet.instances[i]

        -- record last position for drawing
        local x, y = inst.body:getPosition()
        inst.prevPos = vec2.new(x, y)
        
        -- Dynamic culling and LOD check (every few frames to save performance)
        if bullet.t - inst.lastCullCheck > 0.1 then  -- check every 0.1 seconds
            bullet.updateBulletLOD(inst, x, y)
            inst.lastCullCheck = bullet.t
        end
        
        -- Add to trail for visual effect (scale with LOD)
        local trailLength = math.max(2, 8 - inst.lodLevel * 3)  -- reduce trail length for distant bullets
        if inst.visible and inst.lodLevel < 2 then
            table.insert(inst.trail, 1, {x = x, y = y, time = bullet.t})
            if #inst.trail > trailLength then
                table.remove(inst.trail)
            end
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

-- Draw bullets with advanced tracer effects
function bullet.draw()
    -- Draw muzzle flashes first
    bullet.drawMuzzleFlashes()
    
    -- Draw shell casings
    bullet.drawShells()
    
    -- Draw bullet tracers with dynamic LOD
    local renderedCount = 0
    local maxRender = math.floor(bullet.renderSettings.maxVisible * bullet.renderSettings.currentQuality)
    
    -- Sort bullets by priority for rendering (closer bullets first, newer bullets prioritized)
    local sortedBullets = bullet.getSortedBulletsForRendering()
    
    for _, inst in ipairs(sortedBullets) do
        -- Skip invisible or culled bullets
        if not inst.visible or renderedCount >= maxRender then
            goto continue
        end
        
        local x, y = inst.body:getPosition()
        local age = bullet.t - inst.birthTime
        
        -- LOD-based rendering
        if inst.lodLevel == 0 then
            -- Full detail rendering
            bullet.drawBulletFullDetail(inst, x, y)
        elseif inst.lodLevel == 1 then
            -- Medium detail rendering
            bullet.drawBulletMediumDetail(inst, x, y)
        else
            -- Low detail rendering (just a simple dot)
            bullet.drawBulletLowDetail(inst, x, y)
        end
        
        renderedCount = renderedCount + 1
        ::continue::
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
    
    -- Add impact lighting effect
    local x, y = inst.body:getPosition()
    local shader = require("shader")
    if shader.addLight then
        -- Small impact flash
        shader.addLight(x, y, 1.2, {1.0, 0.8, 0.4}, 20, 0.15)
    end

  -- DOING DAMAGE :
    -- if otherGroup == -777 then
            -- damage effect here and call
    --     if checkDestroy then
    --         checkDestroy(enemies_bods, otherBody)
    --     end
    -- end

    -- defer removal until after physics step
    table.insert(bullet.toReturn, inst)
end

function bullet.returnToPool(inst, index)
    inst.body:setLinearVelocity(0, 0)
    inst.body:setPosition(-1000, -1000)
    if #bullet.pool < 50 then
        table.insert(bullet.pool, inst)
    else
        inst.body:destroy()
    end
    if index then
        table.remove(bullet.instances, index)
    end
end

function bullet.processDeferredReturns()
    for _, inst in ipairs(bullet.toReturn) do
        for i = #bullet.instances, 1, -1 do
            if bullet.instances[i] == inst then
                bullet.returnToPool(inst, i)
                break
            end
        end
    end
    bullet.toReturn = {}
end

-- Create muzzle flash effect
function bullet.createMuzzleFlash(pos, dir)
    table.insert(bullet.muzzleFlashes, {
        pos = vec2.new(pos.x, pos.y),
        dir = vec2.new(dir.x, dir.y),
        life = 0.1,  -- flash duration
        maxLife = 0.1,
        size = math.random(8, 15)
    })
end

-- Draw muzzle flash effects
function bullet.drawMuzzleFlashes()
    for _, flash in ipairs(bullet.muzzleFlashes) do
        local alpha = flash.life / flash.maxLife
        local size = flash.size * alpha
        
        -- Add dynamic lighting for muzzle flash
        local shader = require("shader")
        if shader.addMuzzleFlash then
            shader.addMuzzleFlash(flash.pos.x, flash.pos.y, flash.dir)
        end
        
        -- Draw bright core
        love.graphics.setColor(1.0, 0.9, 0.7, alpha * 0.9)
        love.graphics.circle("fill", flash.pos.x, flash.pos.y, size * 0.6)
        
        -- Draw outer glow
        love.graphics.setColor(1.0, 0.7, 0.3, alpha * 0.5)
        love.graphics.circle("fill", flash.pos.x, flash.pos.y, size)
        
        -- Draw directional flash
        local flashEnd = flash.pos + flash.dir * (size * 2)
        love.graphics.setColor(1, 0.9, 0.4, alpha * 0.8)
        love.graphics.setLineWidth(size * 0.8)
        love.graphics.line(flash.pos.x, flash.pos.y, flashEnd.x, flashEnd.y)
    end
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

-- Dynamic rendering system functions
function bullet.updateBulletLOD(inst, x, y)
    local player = require("player")
    local camera = require("camera")
    
    -- Get player position for distance calculation
    local playerX, playerY = player.getPosition()
    local distance = math.sqrt((x - playerX)^2 + (y - playerY)^2)
    
    -- Check if bullet is on screen
    local screenBounds = bullet.getScreenBounds()
    local onScreen = (x >= screenBounds.left and x <= screenBounds.right and 
                     y >= screenBounds.top and y <= screenBounds.bottom)
    
    -- Cull distant bullets
    if distance > bullet.renderSettings.cullDistance or not onScreen then
        inst.visible = false
        return
    else
        inst.visible = true
    end
    
    -- Set LOD level based on distance
    if distance < bullet.renderSettings.lodDistance * 0.5 then
        inst.lodLevel = 0  -- Full detail
    elseif distance < bullet.renderSettings.lodDistance then
        inst.lodLevel = 1  -- Medium detail
    else
        inst.lodLevel = 2  -- Low detail
    end
end

function bullet.getScreenBounds()
    local camera = require("camera")
    local zoom = camera.getZoom()
    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()
    local player = require("player")
    local playerX, playerY = player.getPosition()
    
    local halfWidth = (screenWidth / zoom) * 0.5
    local halfHeight = (screenHeight / zoom) * 0.5
    
    return {
        left = playerX - halfWidth - 100,  -- extra margin for smooth culling
        right = playerX + halfWidth + 100,
        top = playerY - halfHeight - 100,
        bottom = playerY + halfHeight + 100
    }
end

function bullet.drawBulletFullDetail(inst, x, y)
    -- Add dynamic lighting for bullet glow
    local shader = require("shader")
    if shader.addBulletGlow then
        shader.addBulletGlow(x, y)
    end
    
    -- Draw bright tracer core
    love.graphics.setColor(1.0, 1.0, 0.8, 0.9)
    love.graphics.setLineWidth(3)
    love.graphics.line(inst.prevPos.x, inst.prevPos.y, x, y)
    
    -- Draw glowing outer tracer
    love.graphics.setColor(1.0, 0.7, 0.4, 0.6)
    love.graphics.setLineWidth(6)
    love.graphics.line(inst.prevPos.x, inst.prevPos.y, x, y)
    
    -- Draw enhanced fading trail
    if #inst.trail > 1 then
        for i = 1, #inst.trail - 1 do
            local p1 = inst.trail[i]
            local p2 = inst.trail[i + 1]
            local trailAlpha = (1 - (i / #inst.trail)) * 0.5
            love.graphics.setColor(1, 0.9, 0.5, trailAlpha)
            love.graphics.setLineWidth(2)
            love.graphics.line(p1.x, p1.y, p2.x, p2.y)
        end
    end
    
    -- Draw enhanced bullet impact point with glow
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", x, y, 2)
    love.graphics.setColor(1, 0.9, 0.7, 0.6)
    love.graphics.circle("fill", x, y, 4)
end

function bullet.drawBulletMediumDetail(inst, x, y)
    -- Add reduced lighting for medium detail bullets
    local shader = require("shader")
    if shader.addBulletGlow and math.random() < 0.3 then -- Only 30% chance for performance
        shader.addLight(x, y, 0.4, {1.0, 0.9, 0.7}, 8, 0.03)
    end
    
    -- Simplified tracer
    love.graphics.setColor(1.0, 1.0, 0.8, 0.7)
    love.graphics.setLineWidth(2)
    love.graphics.line(inst.prevPos.x, inst.prevPos.y, x, y)
    
    -- Reduced trail
    if #inst.trail > 1 then
        for i = 1, math.min(4, #inst.trail - 1) do
            local p1 = inst.trail[i]
            local p2 = inst.trail[i + 1]
            local trailAlpha = (1 - (i / 4)) * 0.4
            love.graphics.setColor(1, 0.9, 0.5, trailAlpha)
            love.graphics.setLineWidth(1)
            love.graphics.line(p1.x, p1.y, p2.x, p2.y)
        end
    end
    
    -- Small impact point
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.circle("fill", x, y, 1)
end

function bullet.drawBulletLowDetail(inst, x, y)
    -- Just a simple moving dot
    love.graphics.setColor(1, 1, 0.8, 0.5)
    love.graphics.circle("fill", x, y, 1)
end

function bullet.updateAdaptiveQuality(dt)
    if not bullet.renderSettings.adaptiveQuality then return end
    
    local targetTime = bullet.renderSettings.targetFrameTime
    local currentTime = bullet.renderSettings.lastFrameTime
    local bulletCount = #bullet.instances
    local settings = bullet.renderSettings
    
    -- Track bullet density over time
    table.insert(settings.densityHistory, bulletCount)
    if #settings.densityHistory > 10 then
        table.remove(settings.densityHistory, 1)
    end
    
    -- Calculate average bullet density
    local avgDensity = 0
    for _, count in ipairs(settings.densityHistory) do
        avgDensity = avgDensity + count
    end
    avgDensity = avgDensity / #settings.densityHistory
    
    -- Detect bullet density spikes (burst fire scenarios)
    local densitySpike = bulletCount > avgDensity * 1.8 and bulletCount > settings.densityThreshold
    
    -- Emergency performance mode detection
    if currentTime > targetTime * 2.0 and bulletCount > 40 then
        settings.performanceMode = true
    elseif currentTime < targetTime * 1.2 and bulletCount < 15 then
        settings.performanceMode = false
    end
    
    -- Adjust quality based on multiple factors
    if settings.performanceMode or densitySpike then
        -- Emergency quality reduction
        settings.currentQuality = math.max(0.2, settings.currentQuality - dt * 1.0)
        settings.maxVisible = math.max(15, settings.maxVisible * 0.95)
        settings.lodDistance = math.max(100, settings.lodDistance * 0.98)
    elseif currentTime > targetTime * 1.5 or bulletCount > 30 then
        -- Standard quality reduction
        settings.currentQuality = math.max(0.3, settings.currentQuality - dt * 0.5)
        settings.maxVisible = math.max(25, settings.maxVisible * 0.99)
    elseif currentTime < targetTime * 0.8 and bulletCount < 20 and avgDensity < settings.densityThreshold then
        -- Performance is good, increase quality
        settings.currentQuality = math.min(1.0, settings.currentQuality + dt * 0.2)
        settings.maxVisible = math.min(50, settings.maxVisible * 1.01)
        settings.lodDistance = math.min(200, settings.lodDistance * 1.002)
    end
end

function bullet.processRenderEvents()
    for i = #bullet.renderEvents, 1, -1 do
        local event = bullet.renderEvents[i]
        local eventAge = bullet.t - event.time
        
        if event.type == "burst_fire" then
            -- Temporarily reduce quality during burst fire
            local intensity = math.max(0, 1 - eventAge / 2.0)  -- fade over 2 seconds
            if intensity > 0 then
                bullet.renderSettings.currentQuality = math.max(0.4, bullet.renderSettings.currentQuality * (0.7 + intensity * 0.2))
                bullet.renderSettings.maxVisible = math.max(20, bullet.renderSettings.maxVisible * (0.8 + intensity * 0.15))
            end
        elseif event.type == "explosion" then
            -- Temporarily reduce bullet rendering during explosions
            local intensity = math.max(0, 1 - eventAge / 1.5)  -- fade over 1.5 seconds
            if intensity > 0 then
                bullet.renderSettings.maxVisible = math.max(15, bullet.renderSettings.maxVisible * (0.6 + intensity * 0.3))
                bullet.renderSettings.currentQuality = math.max(0.3, bullet.renderSettings.currentQuality * (0.8 + intensity * 0.15))
            end
        end
        
        -- Remove events that have expired
        if eventAge > 3.0 then  -- events last max 3 seconds
            table.remove(bullet.renderEvents, i)
        end
    end
end

function bullet.addRenderEvent(eventType, data)
    table.insert(bullet.renderEvents, {
        type = eventType,
        data = data or {},
        time = bullet.t
    })
end

function bullet.getSortedBulletsForRendering()
    local player = require("player")
    local playerX, playerY = player.getPosition()
    
    -- Create a list of visible bullets with priority scores
    local bulletPriorities = {}
    
    for _, inst in ipairs(bullet.instances) do
        if inst.visible then
            local x, y = inst.body:getPosition()
            local distance = math.sqrt((x - playerX)^2 + (y - playerY)^2)
            local age = bullet.t - inst.birthTime
            
            -- Calculate priority score (lower score = higher priority)
            local priority = distance * 0.1  -- closer bullets get higher priority
            priority = priority + age * 5    -- newer bullets get slight priority
            priority = priority - inst.lodLevel * 50  -- high detail bullets get priority
            
            -- Special priority boosts
            if inst.lodLevel == 0 then
                priority = priority - 100  -- full detail bullets always prioritized
            end
            
            table.insert(bulletPriorities, {
                bullet = inst,
                priority = priority
            })
        end
    end
    
    -- Sort by priority (ascending - lower numbers first)
    table.sort(bulletPriorities, function(a, b)
        return a.priority < b.priority
    end)
    
    -- Extract sorted bullets
    local sortedBullets = {}
    for _, entry in ipairs(bulletPriorities) do
        table.insert(sortedBullets, entry.bullet)
    end
    
    return sortedBullets
end

return bullet