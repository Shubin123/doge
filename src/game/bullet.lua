-- local vec2 = require("lib.math.vec2")
local physSafe = require("util.physics_safe")


local bullet = {}
bullet.world = nil
bullet.t = 0
-- bullet.instances = {}
-- bullet.pool = {}  -- object pool for reuse
bullet.groupIndex = -2  -- collision group for bullets
bullet.hostileGroupIndex = -6  -- enemies' bullets (collision.groups.enemyBullet)
bullet.toReturn = {}  -- deferred list for returning to pool
bullet.neonShader = nil  -- instanced tracer shader (shaders/bullet_neon.glsl)
bullet.muzzleFlashShader = nil
bullet.muzzleFlashes = {}  -- muzzle flash effects
bullet.shells = {}  -- ejected shell casings
bullet.particles = {}  -- gunpowder confetti particles
bullet.online_bullets = {}  -- online bullet bodies for multiplayer

-- Neon look of a tracer: `core` is the hot centre line, `halo` the wide glow
-- around it, `radius` the glow's reach in world pixels. Guns pass their own
-- core/halo through bullet.new's params.neon.
bullet.NEON = { core = {1.0, 0.16, 0.74}, halo = {0.1, 0.78, 1.0}, radius = 12 }

-- Enemies' shots when their weapon doesn't name its own colours: hostile red.
bullet.HOSTILE_NEON = { core = {1.0, 0.2, 0.12}, halo = {1.0, 0.0, 0.08}, radius = 10 }

-- Muzzle flashes: the drawn cone is kept faint (its layers stack additively)
-- and, with high graphics, is softened by the flashlight's glow chain
-- (light.renderLights); the brightness comes from the light it casts instead,
-- a point light of MUZZLE_LIGHT intensity (the player's key light is 1.0).
bullet.MUZZLE_OPACITY = 0.035
bullet.MUZZLE_LIGHT = 1.2

local TRACER_FORMAT = {
    {"InstSeg", "float", 4},   -- tail.xy, head.xy
    {"InstCore", "float", 4},  -- core rgb, intensity
    {"InstHalo", "float", 4},  -- halo rgb, radius
    {"InstPhase", "float", 1},
}

local function growTracerInstances(count)
    bullet.tracerCapacity = math.max(count, bullet.tracerCapacity * 2)
    bullet.tracerInstances = love.graphics.newMesh(TRACER_FORMAT, bullet.tracerCapacity, nil, "stream")
    for _, attribute in ipairs(TRACER_FORMAT) do
        bullet.tracerMesh:attachAttribute(attribute[1], bullet.tracerInstances, "perinstance")
    end
end

-- Bloom for the tracers: the same moonshine glow -> blur -> godray stack as the
-- neons in light.lua, tuned so the coloured core blooms rather than only pure
-- white. Built on the first shot (and rebuilt if the window size changes), so
-- its canvases and its eight full-screen passes cost nothing until bullets fly.
-- (Sharing scratch canvases between chains would save that VRAM, but measured
-- ~1.3 ms/frame slower on Apple silicon: each chain then waits on the last.)
local function ensureNeonChain()
    local w, h = love.graphics.getDimensions()
    if bullet.neonChain and bullet.neonChainW == w and bullet.neonChainH == h then
        return
    end
    local chain = moonshine(moonshine.effects.glow).chain(moonshine.effects.fastgaussianblur)
        .chain(moonshine.effects.godsray)
    chain.glow.min_luma = 0.45
    chain.glow.strength = 2
    chain.fastgaussianblur.taps = 9
    chain.godsray.exposure = 0.25
    chain.godsray.decay = 0.9
    chain.godsray.density = 0.25
    chain.godsray.weight = 0.4
    chain.godsray.samples = 30
    bullet.neonChain, bullet.neonChainW, bullet.neonChainH = chain, w, h
end

-- Initialize the bullet module with the physics world
function bullet.load(world)
    bullet.world = world
    bullet.t = 0
    bullet.instances = {}
    bullet.pool = {}
    bullet.hostilePool = {}
    bullet.toReturn = {}
    bullet.muzzleFlashes = {}
    bullet.shells = {}
    bullet.particles = {}
    bullet.online_bullets = {}
    
    -- Instanced neon tracers: one shared quad, one instance per live bullet.
    bullet.neonShader = love.graphics.newShader(love.filesystem.read("shaders/bullet_neon.glsl"))
    bullet.tracerMesh = love.graphics.newMesh({{"VertexPosition", "float", 2}},
        {{0, -1}, {1, -1}, {1, 1}, {0, 1}}, "fan", "static")
    bullet.tracerCapacity = 0
    growTracerInstances(128)
    
    -- Load muzzle flash shader
    local muzzle_shader_code = love.filesystem.read("shaders/muzzle_flash.frag")
    if muzzle_shader_code then
        bullet.muzzleFlashShader = love.graphics.newShader(muzzle_shader_code)
    end
    
end

-- Factory: create a new bullet (with pooling)
-- params = { pos = vec2, dir = vec2, speed = number, damage = number, radius = number, lifetime = number,
--            neon = {core, halo, radius}, hostile = bool }
-- A hostile bullet is an enemy's: a sensor in its own collision group, so it
-- passes through enemies, coins and other bullets without pushing them, and
-- only the player (who it hurts) and the map (which stops it) react to it.
-- Hostile and friendly bullets keep separate pools.
function bullet.new(params)
    assert(bullet.world, "bullet.load(world) must be called before creating bullets")
    local pos = params.pos or vec2.new(0, 0)
    local dir = params.dir or vec2.new(1, 0)
    dir = vec2.norm(dir)
    local speed = params.speed or 500
    local damage = params.damage or 1
    local radius = params.radius or 5
    local lifetime = params.lifetime or 5
    local hostile = params.hostile or false
    local neon = params.neon or (hostile and bullet.HOSTILE_NEON or bullet.NEON)
    local pool = hostile and bullet.hostilePool or bullet.pool

    local instance
    
    -- Try to reuse from pool
    if #pool > 0 then
        instance = table.remove(pool)
        if hostile then
            -- Enemy weapons differ in calibre; friendly bullets keep their first size
            instance.fixture:getShape():setRadius(radius)
        end
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
        instance.neon = neon
        instance.spent = false
    else
        -- Create new instance
        local body = love.physics.newBody(bullet.world, pos.x, pos.y, "dynamic")
        local shape = love.physics.newCircleShape(radius)
        local fixture = love.physics.newFixture(body, shape)
        fixture:setGroupIndex(hostile and bullet.hostileGroupIndex or bullet.groupIndex)
        fixture:setSensor(hostile)

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
            neon      = neon,
            hostile   = hostile,
            spent     = false, -- a hostile bullet that has already hit
        }
        
        -- allow collision callback to recover instance
        fixture:setUserData(instance)
    end

    -- Desynchronises each tracer's flicker from its neighbours'.
    instance.phase = (bullet.t * 61.7 + #bullet.instances * 2.39) % (2 * math.pi)
    if var.graphics_high and not hostile then ensureNeonChain() end

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

    -- Each live flash lights its surroundings through the lighting shader
    -- (shadow.lua), from a little ahead of the barrel so the light falls the
    -- way the gun fired. Must run before shadow.updateBothShaders this frame.
    local brightness = math.min(1, var.tracer_brightness or 1)
    for _, flash in ipairs(bullet.muzzleFlashes) do
        local reach = flash.coneLength
        shadow.addTransientLight(flash.pos.x + flash.dir.x * reach * 0.3,
            flash.pos.y + flash.dir.y * reach * 0.3,
            bullet.MUZZLE_LIGHT * flash.intensity * (flash.life / flash.maxLife) * brightness,
            reach * 2)
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

        local x, y = inst.body:getPosition()

        -- Record LAST frame's position. It has to lag one frame behind (the
        -- current position would make a zero-length streak); bullet.draw uses
        -- it as the tracer's tail until the trail has samples. trail[1] is
        -- still last frame's sample at this point (this frame's is pushed just
        -- below), so take it from there, and mutate in place rather than
        -- allocating a vec2 per bullet per frame.
        local prev = inst.trail[1]
        if prev then
            inst.prevPos.x, inst.prevPos.y = prev.x, prev.y
        else
            inst.prevPos.x, inst.prevPos.y = x, y
        end

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
    
    -- Add muzzle flashes to draw list with proper offset to avoid interfering with map elements.
    -- With high graphics they are drawn as light instead (light.renderLights).
    for _, flash in ipairs(var.graphics_high and {} or bullet.muzzleFlashes) do
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
            sort_y = shell.pos.y + 150, -- Shells fall on ground, should be behind most objects
            source_object_type = "shell_casing",
            shell_data = shell,
            color = {1, 1, 1, 1},
            blend_mode = {"alpha"}
        })
    end
    
    -- Bullet tracers are not sorted: bullet.draw() renders them all in one
    -- instanced call after the sorted list, glowing over everything.
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

    -- if hit an enemy, apply damage
    if otherGroup == -777 then
        -- Add blood effect at hit location
        local x, y = otherBody:getPosition()
        if blood and blood.onEnemyDamage then
            -- blood.onEnemyDamage(x, y, inst.damage or 1, inst.dir)
            blood.onEnemyDamage(x, y, 1, vec2.new(1,1))
        end
        
        -- Find enemy index and apply damage using the new health system
        for i = 1, #enemies_bods do
            if enemies_bods[i] and enemies_bods[i] == otherBody then
                if enemy and enemy.damageEnemy then
                    local damage_amount = math.random(8, 15)  -- Random damage 8-15
                    enemy.damageEnemy(i, damage_amount)
                    
                    -- Add knockback force from bullet impact
                    local bullet_force = 40  -- Reduced force for proper mass enemies
                    local knockback_x = math.random()* bullet_force
                    -- local knockback_x = inst.dir.x* bullet_force
                    local knockback_y = math.random()* bullet_force
                    -- local knockback_y = inst.dir.y* bullet_force
                    
                    -- Apply the knockback force to the enemy using safe utility
                    physSafe.safeApplyImpulse(otherBody, knockback_x, knockback_y)
                end
                break
            end
        end
    end

    
    -- if (var.multiplayer == 1) then
        if other_f:getGroupIndex() == -1 then
            
            -- Add blood effect at player hit location
            -- local x, y = player.body:getPosition()
            -- if blood and blood.onEnemyDamage then
            --     blood.onEnemyDamage(x, y, 1)
            -- end
            
            -- Damage player or trigger player hit logic here
            -- print("Player hit by enemy fire! or collided with enemy", not_enemy_proj:getBody())
            -- print(player.online.bodies)
            local hit_client = false -- for every collision check through client bodies if the collision was made was it then dont hit the player aswell
            for k,body in pairs(player.online.bodies) do
            -- print(body == not_enemy_proj:getBody())
                if body == other_f:getBody() then
            -- player.health = player.health - 1
                    -- print(k)
                    -- game_state
                    player.online.health[k] =  player.online.health[k] - 1
                    hit_client = true
                    
                    -- Add blood effect for online players
                    local px, py = body:getPosition()
                    if blood and blood.onEnemyDamage then
                        blood.onEnemyDamage(px, py, 1)
                    end
                end

            end

            if not hit_client then
            player.health = player.health - 1
            end
            -- You can add player damage logic here
        end
        -- end
    -- end


    -- defer removal until after physics step
    table.insert(bullet.toReturn, inst)
end

-- Return bullet to pool for reuse (instead of destroying)
function bullet.returnToPool(inst, index)
    -- Reset physics state but keep body/fixture for reuse
    inst.body:setLinearVelocity(0, 0)
    inst.body:setPosition(-1000, -1000)  -- move offscreen
    
    -- Add to pool if not too many (limit pool size)
    local pool = inst.hostile and bullet.hostilePool or bullet.pool
    if #pool < 50 then
        table.insert(pool, inst)
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
    for _, flash in ipairs(bullet.muzzleFlashes) do
        bullet.drawSingleMuzzleFlash(flash)
    end
    love.graphics.setColor(1, 1, 1, 1)
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
        groundY = ejectionPos.y + 100, -- approximate ground level
        sort_y = 1000,
    })
end

-- Draw shell casings
function bullet.drawShells()
    -- for _, shell in ipairs(bullet.shells) do
    --     local alpha = math.min(1, shell.life / shell.maxLife)
    --     if shell.life < 1 then
    --         alpha = shell.life  -- fade out in last second
    --     end
        
    --     love.graphics.push()
    --     love.graphics.translate(shell.pos.x, shell.pos.y)
    --     love.graphics.rotate(shell.rotation)
        
    --     -- Draw shell casing as small rectangle
    --     love.graphics.setColor(shell.color[1], shell.color[2], shell.color[3], alpha)
    --     love.graphics.rectangle("fill", -shell.size.width/2, -shell.size.height/2, 
    --                           shell.size.width, shell.size.height)
        
    --     -- Add rim highlight
    --     love.graphics.setColor(1, 1, 1, alpha * 0.5)
    --     love.graphics.rectangle("line", -shell.size.width/2, -shell.size.height/2, 
    --                           shell.size.width, shell.size.height)
        
    --     love.graphics.pop()
    -- end
    -- love.graphics.setColor(1, 1, 1, 1)
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
    -- The historical vfx branch established the additive muzzle/tracer look.
    -- Render that look through the current sorted renderer and WebGL-safe
    -- shader path rather than its obsolete flat-layout code.
    love.graphics.setBlendMode("add")
    local previous_shader = love.graphics.getShader()
    
    local alpha = flash.life / flash.maxLife
    local size = flash.size * alpha
    local opacity = bullet.MUZZLE_OPACITY * math.min(1, var.tracer_brightness or 1)
    
    -- Draw cone-shaped flash using triangular geometry
    local coneLength = flash.coneLength * alpha
    local coneAngle = flash.coneAngle
    
    -- Calculate cone vertices
    local perpDir = vec2.new(-flash.dir.y, flash.dir.x)
    local coneEnd = flash.pos + flash.dir * coneLength
    
    -- Wide saturated halo plus a hot white core. Alpha blending made these
    -- flashes nearly invisible against the game’s dark world pass.
    for i = 1, 6 do
        local gradientFactor = i / 6
        local currentAlpha = alpha * (1 - gradientFactor * 0.55) * flash.intensity * opacity
        local currentSize = coneLength * (1 - gradientFactor * 0.3)

        if bullet.muzzleFlashShader then
            bullet.muzzleFlashShader:send("flash_color", flash.color)
            bullet.muzzleFlashShader:send("intensity", 0.72 + gradientFactor * 0.46)
            bullet.muzzleFlashShader:send("pulse", bullet.t * 38.0 + i)
            love.graphics.setShader(bullet.muzzleFlashShader)
        end
        love.graphics.setColor(1, 0.82 + gradientFactor * 0.18, 0.42 + gradientFactor * 0.40, currentAlpha)
        
        local layerEnd = flash.pos + flash.dir * currentSize
        local layerLeft = layerEnd + perpDir * math.tan(coneAngle) * currentSize * gradientFactor
        local layerRight = layerEnd - perpDir * math.tan(coneAngle) * currentSize * gradientFactor
        
        love.graphics.polygon("fill", 
            flash.pos.x, flash.pos.y,
            layerLeft.x, layerLeft.y,
            layerRight.x, layerRight.y
        )
        love.graphics.setShader(previous_shader)
    end

    if bullet.muzzleFlashShader then
        bullet.muzzleFlashShader:send("flash_color", {1.0, 0.55, 0.12})
        bullet.muzzleFlashShader:send("intensity", 1.0)
        bullet.muzzleFlashShader:send("pulse", bullet.t * 44.0)
        love.graphics.setShader(bullet.muzzleFlashShader)
    end
    love.graphics.setColor(1, 0.96, 0.74, alpha * flash.intensity * opacity)
    love.graphics.circle("fill", flash.pos.x, flash.pos.y, size * 1.05)
    love.graphics.setShader(previous_shader)
    love.graphics.setColor(0.12, 0.72, 1.0, alpha * flash.intensity * 0.62 * opacity)
    love.graphics.circle("fill", flash.pos.x, flash.pos.y, size * 2.45)

    love.graphics.setBlendMode("alpha")
end

function bullet.drawSingleParticle(particle)
    -- Use alpha blending for particles to prevent map interference
    -- love.graphics.setBlendMode("alpha")
    
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

-- Per-instance rows for the tracer mesh, reused frame to frame.
local tracerRows, tracerRowPool = {}, {}
local tracerOrder = {}

-- Fills the instance mesh: the player's bullets first, then enemies'.
-- Returns how many in all and how many of them are the player's.
local function fillTracerInstances()
    local list = bullet.instances
    local n = #list
    if n == 0 then return 0, 0 end
    if n > bullet.tracerCapacity then growTracerInstances(n) end
    local friendly = 0
    for i = 1, n do
        if not list[i].hostile then
            friendly = friendly + 1
            tracerOrder[friendly] = list[i]
        end
    end
    local k = friendly
    for i = 1, n do
        if list[i].hostile then
            k = k + 1
            tracerOrder[k] = list[i]
        end
    end
    for i = n + 1, #tracerOrder do tracerOrder[i] = nil end
    for i = 1, n do
        local inst = tracerOrder[i]
        local x, y = inst.body:getPosition()
        local tail = inst.trail[#inst.trail] or inst.prevPos -- oldest sample: the streak's end
        local age = bullet.t - inst.birthTime
        -- Burn extra bright for the first frames, fade out over the last 0.3 s.
        local intensity = math.max(0, math.min(1, (inst.lifetime - age) / 0.3))
            * (1 + 0.6 * math.max(0, 1 - age / 0.08))
        local core, halo = inst.neon.core, inst.neon.halo
        local row = tracerRowPool[i]
        if not row then
            row = {}
            tracerRowPool[i] = row
        end
        row[1], row[2], row[3], row[4] = tail.x, tail.y, x, y
        row[5], row[6], row[7], row[8] = core[1], core[2], core[3], intensity
        row[9], row[10], row[11], row[12] = halo[1], halo[2], halo[3], inst.neon.radius or bullet.NEON.radius
        row[13] = inst.phase
        tracerRows[i] = row
    end
    for i = n + 1, #tracerRows do tracerRows[i] = nil end
    bullet.tracerInstances:setVertices(tracerRows)
    return n, friendly
end

local function drawTracers(n)
    love.graphics.setBlendMode("add", "premultiplied")
    love.graphics.setShader(bullet.neonShader)
    love.graphics.drawInstanced(bullet.tracerMesh, n)
end

--- Draw every live bullet as a neon tracer: one instanced draw into the
--- bulletNeon glow chain for the bloom, and one on top of it for the crisp
--- core. Call in world space (under camera.apply), after the sorted sprites.
--- Only the player's bullets bloom: enemies fire nearly all the time, and
--- the chain's eight full-screen passes would then run every frame (their
--- tracers still carry the shader's own neon halo).
function bullet.draw()
    local brightness = var.tracer_brightness or 1
    if brightness <= 0 then return end
    local n, friendly = fillTracerInstances()
    if n == 0 then return end

    local r, g, b, a = love.graphics.getColor()
    local blend, alphamode = love.graphics.getBlendMode()
    local shader = love.graphics.getShader()
    bullet.neonShader:send("time", bullet.t)
    bullet.neonShader:send("brightness", math.min(1, brightness))

    local chain = bullet.neonChain
    if friendly > 0 and var.graphics_high and chain and bullet.neonChainW == love.graphics.getWidth()
        and bullet.neonChainH == love.graphics.getHeight() then
        love.graphics.push()
        love.graphics.reset() -- the chain's full-screen passes must not inherit the camera
        chain(function()
            love.graphics.push()
            camera.apply()
            drawTracers(friendly)
            love.graphics.pop()
            -- Leave the state the chain's own passes expect, as the other neons do.
            love.graphics.setBlendMode("alpha")
            love.graphics.setShader()
        end)
        love.graphics.pop()
    end

    drawTracers(n)

    love.graphics.setColor(r, g, b, a)
    love.graphics.setBlendMode(blend, alphamode)
    love.graphics.setShader(shader)
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
        bullet.online_bullets[index] = love.physics.newBody(bullet.world, pos.x, pos.y, "dynamic")
        local shape = love.physics.newCircleShape(5)
        local fixture = love.physics.newFixture(bullet.online_bullets[index], shape)
        fixture:setGroupIndex(bullet.groupIndex)
        
    end
end

-- Draw a single networked bullet (for multiplayer)
function bullet.drawSingleNetworkedBullet(bullet_data, x, y)
    -- Draw bright bullet core
    love.graphics.setColor(0.9, 0.9, 0.7, 0.8)
    love.graphics.circle("fill", x, y, 3)
    
    -- Draw glowing outer bullet
    love.graphics.setColor(0.8, 0.6, 0.3, 0.5)
    love.graphics.circle("fill", x, y, 5)
    
    -- Draw bullet impact point
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", x, y, 2)
        bullet.setOnline(bullet_data.id,vec2.new(bullet_data.x,bullet_data.y))

    -- for k,v in pairs(bullet_data) do 
    --     -- print(k,v)
    --     bullet.setOnline(v.id,vec2.new(v.x,v.y))

    -- end
end

return bullet
