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
bullet.online_bullets = {}
 
 -- Initialize the bullet module with the physics world
 function bullet.load(world)
    bullet.world = world
    bullet.t = 0
    bullet.instances = {}
    bullet.pool = {}
    bullet.toReturn = {}
    bullet.muzzleFlashes = {}
    bullet.shells = {}
    
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

-- Populate dynamic draw list instead of drawing directly
function bullet.populate()
    -- Add muzzle flashes to draw list

    for _, flash in ipairs(bullet.muzzleFlashes) do
        local alpha = flash.life / flash.maxLife
        local size = flash.size * alpha
        
        -- Bright core
        table.insert(dynamic_draw_list, {
            sort_y = flash.pos.y + 140,
            draw_type = "muzzle_flash_core",
            x = flash.pos.x,
            y = flash.pos.y,
            size = size * 0.6,
            color = { 0.8, 0.8, 0.7, alpha * 0.8 },
            blend_mode = { "add" },
            source_object_type = "bullet_muzzle_flash"
        })
        
        -- Outer glow
        table.insert(dynamic_draw_list, {
            sort_y = flash.pos.y + 140,
            draw_type = "muzzle_flash_glow",
            x = flash.pos.x,
            y = flash.pos.y,
            size = size,
            color = { 0.8, 0.6, 0.2, alpha * 0.4 },
            blend_mode = { "add" },
            source_object_type = "bullet_muzzle_flash"
        })
        
        -- Directional flash
        local flashEnd = flash.pos + flash.dir * (size * 2)
        table.insert(dynamic_draw_list, {
            sort_y = flash.pos.y + 140,
            draw_type = "muzzle_flash_direction",
            x1 = flash.pos.x,
            y1 = flash.pos.y,
            x2 = flashEnd.x,
            y2 = flashEnd.y,
            line_width = size * 0.8,
            color = { 1, 0.9, 0.4, alpha * 0.7 },
            blend_mode = { "add" },
            source_object_type = "bullet_muzzle_flash"
        })
    end
    
    -- Add shell casings to draw list
    for _, shell in ipairs(bullet.shells) do
        local alpha = math.min(1, shell.life / shell.maxLife)
        if shell.life < 1 then
            alpha = shell.life  -- fade out in last second
        end
        
        -- Shell casing body
        table.insert(dynamic_draw_list, {
            sort_y = shell.pos.y + 140,
            draw_type = "shell_casing",
            x = shell.pos.x,
            y = shell.pos.y,
            rotation = shell.rotation,
            width = shell.size.width,
            height = shell.size.height,
            color = { shell.color[1], shell.color[2], shell.color[3], alpha },
            blend_mode = { "alpha" },
            source_object_type = "bullet_shell"
        })
        
        -- Shell casing highlight
        table.insert(dynamic_draw_list, {
            sort_y = shell.pos.y + 140.1, -- slightly above main shell
            draw_type = "shell_casing_highlight",
            x = shell.pos.x,
            y = shell.pos.y,
            rotation = shell.rotation,
            width = shell.size.width,
            height = shell.size.height,
            color = { 1, 1, 1, alpha * 0.5 },
            blend_mode = { "alpha" },
            source_object_type = "bullet_shell"
        })
    end
    
    -- Add bullet tracers to draw list
    for _, inst in ipairs(bullet.instances) do
        local x, y = inst.body:getPosition()
        local age = bullet.t - inst.birthTime
        
        -- Bullet trail segments (draw from back to front for proper alpha blending)
        if #inst.trail > 1 then
            for i = #inst.trail, 2, -1 do  -- reverse order for proper layering
                local p1 = inst.trail[i]
                local p2 = inst.trail[i - 1]
                local trailAlpha = (1 - (i / #inst.trail)) * 0.4
                
                table.insert(dynamic_draw_list, {
                    sort_y = math.max(p1.y + 140, p2.y + 140), -- use higher Y for sorting
                    draw_type = "bullet_trail",
                    x1 = p1.x,
                    y1 = p1.y,
                    x2 = p2.x,
                    y2 = p2.y,
                    line_width = 2,
                    color = { 1, 0.8, 0.4, trailAlpha },
                    blend_mode = { "add" },
                    source_object_type = "bullet_tracer"
                })
            end
        end
        
        -- Outer tracer glow
        table.insert(dynamic_draw_list, {
            sort_y = math.max(inst.prevPos.y+ 140, y + 140),
            draw_type = "bullet_tracer_glow",
            x1 = inst.prevPos.x,
            y1 = inst.prevPos.y,
            x2 = x,
            y2 = y,
            line_width = 6,
            color = { 0.8, 0.6, 0.3, 0.5 },
            blend_mode = { "add" },
            source_object_type = "bullet_tracer"
        })
        
        -- Bright tracer core
        table.insert(dynamic_draw_list, {
            sort_y = math.max(inst.prevPos.y, y) + 140.1, -- slightly above glow
            draw_type = "bullet_tracer_core",
            x1 = inst.prevPos.x,
            y1 = inst.prevPos.y,
            x2 = x,
            y2 = y,
            line_width = 3,
            color = { 0.9, 0.9, 0.7, 0.8 },
            blend_mode = { "add" },
            source_object_type = "bullet_tracer"
        })
        
        -- Bullet impact point
        table.insert(dynamic_draw_list, {
            sort_y = y + 140.2, -- above tracer
            draw_type = "bullet_point",
            x = x,
            y = y,
            radius = 2,
            color = { 1, 1, 1, 1 },
            blend_mode = { "alpha" },
            source_object_type = "bullet_tracer"
        })
    end


end

-- Handle collisions: bullet vs enemy or obstacles
function bullet.collision(fixture_a, fixture_b, contact)
    if (var.multiplayer ~= 1) and var.multiplayer then return end
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

function bullet.getNetworkData()
    local network_data = {}
    for i = 1, #bullet.instances do
        if bullet.instances[i] then
            local x, y = bullet.instances[i].body:getPosition()
            table.insert(network_data, {
                x = x,
                y = y,
                active = true,
                id = i
            })
        end
    end
    return network_data
end

function bullet.setOnline(index, pos)
    if bullet.online_bullets[index] then
        bullet.online_bullets[index]:setPosition(pos.x, pos.y)
    else
        bullet.online_bullets[index] = love.physics.newBody(world, pos.x, pos.y, "dynamic")
        local shape = love.physics.newCircleShape(5)
        local fixture = love.physics.newFixture(bullet.online_bullets[index], shape)
        fixture:setGroupIndex(bullet.groupIndex)
    end
end

return bullet