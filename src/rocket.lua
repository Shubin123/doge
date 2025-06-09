local vec2 = require("vec2")

local rocket = {}
rocket.rockets = {}
local world = nil

-- simple explosion effect tracking
local explosions = {}
-- deferred destruction list
local toDestroy = {}

function rocket.load(w)
    world = w
    rocket.rockets = {}
    explosions = {}
    toDestroy = {}
end

-- params = { pos = vec2, dir = vec2 (normalized), topSpeed = number, accelTime = number, damage = number, radius = number }
function rocket.new(params)
    assert(world, "rocket.load(world) must be called before creating rockets")
    local pos, dir = params.pos, params.dir
    local topSpeed, accelTime = params.topSpeed, params.accelTime
    local damage, radius = params.damage, params.radius

    -- create physics body and fixture
    local body = love.physics.newBody(world, pos.x, pos.y, "dynamic")
    local shape = love.physics.newCircleShape(radius)
    local fixture = love.physics.newFixture(body, shape)
    fixture:setGroupIndex(-3)  -- unique group for rockets
    
    -- instance table
    local inst = {
        body = body,
        fixture = fixture,
        dir = vec2.new(dir.x, dir.y),
        currentSpeed = 0,
        topSpeed = topSpeed,
        accelTime = accelTime,
        damage = damage,
        radius = radius,
        birthTime = love.timer.getTime(),
        destroyed = false,  -- flag to prevent multiple destructions
        exhaustTrail = {},  -- exhaust particle trail
        thrustIntensity = 0  -- current thrust for visual effects
    }
    -- user data for collision identification
    fixture:setUserData(inst)

    table.insert(rocket.rockets, inst)
    return inst
end

function rocket.update(dt)
    local now = love.timer.getTime()
    
    -- Process deferred destructions first (world is not locked during update)
    rocket.processDeferredDestructions()
    
    -- update rockets
    for i = #rocket.rockets, 1, -1 do
        local r = rocket.rockets[i]
        
        -- skip destroyed rockets
        if r.destroyed then
            goto continue
        end
        
        -- accelerate
        local accel = r.topSpeed / r.accelTime
        r.currentSpeed = math.min(r.topSpeed, r.currentSpeed + accel * dt)
        
        -- calculate thrust intensity for visual effects
        r.thrustIntensity = math.min(1, r.currentSpeed / r.topSpeed)
        
        -- set velocity
        local vx, vy = r.dir.x * r.currentSpeed, r.dir.y * r.currentSpeed
        r.body:setLinearVelocity(vx, vy)
        
        -- add exhaust particles
        local x, y = r.body:getPosition()
        local exhaustPos = vec2.new(x, y) - r.dir * (r.radius * 1.5)
        
        -- add exhaust trail particles
        for j = 1, math.ceil(r.thrustIntensity * 3) do
            local spread = (math.random() - 0.5) * 0.3
            local exhaustDir = vec2.new(
                -r.dir.x + spread * r.dir.y,
                -r.dir.y - spread * r.dir.x
            )
            
            table.insert(r.exhaustTrail, {
                pos = vec2.new(exhaustPos.x, exhaustPos.y),
                vel = exhaustDir * (50 + math.random() * 50),
                life = 0.3 + math.random() * 0.2,
                maxLife = 0.5,
                size = 2 + math.random() * 3
            })
        end
        
        -- update exhaust particles
        for j = #r.exhaustTrail, 1, -1 do
            local particle = r.exhaustTrail[j]
            particle.life = particle.life - dt
            particle.pos = particle.pos + particle.vel * dt
            particle.vel = particle.vel * 0.95  -- friction
            
            if particle.life <= 0 then
                table.remove(r.exhaustTrail, j)
            end
        end
        -- lifetime check
        if now - r.birthTime > 10 then
            rocket.destroyRocket(r, i)
        end
        
        ::continue::
    end
    -- update explosions
    for i = #explosions, 1, -1 do
        local e = explosions[i]
        e.t = e.t + dt
        if e.t > 0.5 then
            table.remove(explosions, i)
        end
    end
end

function rocket.populate()
    -- Add rockets to the dynamic draw list
    for _, r in ipairs(rocket.rockets) do
        if not r.destroyed then
            local x, y = r.body:getPosition()
            local angle = math.atan2(r.dir.y, r.dir.x)
            local sort_y = y + 140 -- Base sorting value

            -- Exhaust trail particles
            for _, particle in ipairs(r.exhaustTrail) do
                local alpha = particle.life / particle.maxLife
                local size = particle.size * alpha
                table.insert(dynamic_draw_list, {
                    draw_type = "rocket_exhaust",
                    sort_y = particle.pos.y + 140,
                    x = particle.pos.x,
                    y = particle.pos.y,
                    size = size,
                    alpha = alpha,
                    color = {1, 1, 0.8, alpha * 0.8}, -- Hot core
                    blend_mode = {"alpha"}
                })
            end

            -- Main rocket thrust
            if r.thrustIntensity > 0 then
                local thrustLength = r.radius * 2 * r.thrustIntensity
                local thrustPos = vec2.new(x, y) - r.dir * r.radius
                local thrustEnd = thrustPos - r.dir * thrustLength
                table.insert(dynamic_draw_list, {
                    draw_type = "rocket_thrust",
                    sort_y = sort_y,
                    x1 = thrustPos.x, y1 = thrustPos.y,
                    x2 = thrustEnd.x, y2 = thrustEnd.y,
                    radius = r.radius,
                    color = {1, 1, 0.9, 0.8},
                    blend_mode = {"add"}
                })
            end

            -- Rocket body
            table.insert(dynamic_draw_list, {
                draw_type = "rocket_body",
                sort_y = sort_y,
                x = x, y = y,
                angle = angle,
                radius = r.radius,
                color = {0.7, 0.7, 0.7, 1},
                blend_mode = {"alpha"}
            })
        end
    end

    -- Add explosions to the dynamic draw list
    for _, e in ipairs(explosions) do
        local progress = e.t / 0.5
        local alpha = 1 - progress
        local currentRadius = e.radius * progress
        
        table.insert(dynamic_draw_list, {
            draw_type = "rocket_explosion",
            sort_y = e.pos.y + 140,
            x = e.pos.x, y = e.pos.y,
            radius = currentRadius,
            alpha = alpha,
            shockwaveRadius = e.shockwaveRadius and (e.shockwaveRadius * progress) or nil,
            color = {1, 1, 0.9, alpha * 0.9},
            blend_mode = {"add"}
        })
    end
end

function rocket.collision(fixture_a, fixture_b, contact)
    -- detect rocket fixture
    local fa_ud = fixture_a:getUserData()
    local fb_ud = fixture_b:getUserData()
    local inst, other_ud
    -- FIX: Changed the check from the generic 'birthTime' to the rocket-specific 'topSpeed'.
    -- This prevents other objects (like bullets) from being mistaken for rockets.
    if type(fa_ud) == "table" and fa_ud.topSpeed then
        inst, other_ud = fa_ud, fb_ud
    elseif type(fb_ud) == "table" and fb_ud.topSpeed then
        inst, other_ud = fb_ud, fa_ud
    else
        return
    end

    -- check if rocket is already destroyed to prevent multiple collisions
    if inst.destroyed then
        return
    end

    -- mark as destroyed immediately to prevent duplicate processing
    inst.destroyed = true

    -- get explosion position (body still exists at this point)
    local x, y = inst.body:getPosition()
    
    -- Create large explosion effect
    table.insert(explosions, {
        pos = vec2.new(x, y),
        t = 0,
        radius = inst.radius * 4,
        maxRadius = inst.radius * 4,
        damage = inst.damage,
        shockwaveRadius = inst.radius * 6  -- larger shockwave
    })

    -- area damage: iterate enemies_bods if exists
    if enemies_bods then
        for _, eb in ipairs(enemies_bods) do
            local ex, ey = eb:getPosition()
            local d = ((ex - x)^2 + (ey - y)^2)^0.5
            local damageRadius = inst.radius * 4  -- larger damage radius
            
            if d <= damageRadius then
                -- Calculate damage falloff based on distance
                local damageFactor = 1 - (d / damageRadius)
                local actualDamage = inst.damage * damageFactor
                
                if eb.applyDamage then
                    eb:applyDamage(actualDamage)
                elseif checkDestroy then
                    -- If no applyDamage method, just destroy if close enough
                    if d <= inst.radius * 2 then
                        checkDestroy(enemies_bods, eb)
                    end
                end
            end
        end
    end

    -- defer rocket destruction until after physics step
    table.insert(toDestroy, inst)
end

-- Destroy a rocket safely (called during update when world is not locked)
function rocket.destroyRocket(inst, index)
    if inst.body and inst.fixture then
        inst.fixture:destroy()
        inst.body:destroy()
    end
    inst.destroyed = true
    if index then
        table.remove(rocket.rockets, index)
    end
end

-- Process deferred rocket destructions (called during update when world is not locked)
function rocket.processDeferredDestructions()
    for _, inst in ipairs(toDestroy) do
        -- Find and remove from rockets list
        for i = #rocket.rockets, 1, -1 do
            if rocket.rockets[i] == inst then
                rocket.destroyRocket(inst, i)
                break
            end
        end
    end
    toDestroy = {}  -- clear the list
end

return rocket