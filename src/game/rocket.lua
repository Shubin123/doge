local vec2 = require("lib.math.vec2")
local physSafe = require("util.physics_safe")

local rocket = {}
rocket.rockets = {}
rocket.online_rockets = {}
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

-- Process deferred rocket destructions (called during update when world is not locked)
function rocket.processDeferredDestructions()
    for _, rkt_inst in ipairs(toDestroy) do
        -- Find and remove from rockets list
        for i = #rocket.rockets, 1, -1 do
            if rocket.rockets[i] == rkt_inst then
                rocket.destroyRocket(rkt_inst, i)
                break
            end
        end
    end
    toDestroy = {}  -- clear the list
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
        for k = #r.exhaustTrail, 1, -1 do
            local particle = r.exhaustTrail[k]
            particle.life = particle.life - dt
            particle.pos = particle.pos + particle.vel * dt
            particle.vel = particle.vel * 0.95  -- friction
            
            if particle.life <= 0 then
                table.remove(r.exhaustTrail, k)
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

function rocket.collision(fixture_a, fixture_b, _)
    if (var.multiplayer ~= 1) and var.multiplayer then return end
    -- detect rocket fixture
    local fa_ud = fixture_a:getUserData()
    local fb_ud = fixture_b:getUserData()
    local inst
    -- FIX: Changed the check from the generic 'birthTime' to the rocket-specific 'topSpeed'.
    -- This prevents other objects (like bullets) from being mistaken for rockets.
    if type(fa_ud) == "table" and fa_ud.topSpeed then
        inst = fa_ud
    elseif type(fb_ud) == "table" and fb_ud.topSpeed then
        inst = fb_ud
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

    -- Enhanced area damage with better scaling and effects
    if enemies_bods then
        local splash_enemies = {}  -- Track enemies hit for splash effects
        
        for i, eb in ipairs(enemies_bods) do
            if eb then  -- Safety check for enemy body
                local ex, ey = eb:getPosition()
                local distance = ((ex - x)^2 + (ey - y)^2)^0.5
                local damageRadius = inst.radius * 5  -- Increased splash radius
                
                if distance <= damageRadius then
                    -- Enhanced damage falloff calculation
                    local damageFactor = 1 - (distance / damageRadius)
                    damageFactor = damageFactor * damageFactor  -- Quadratic falloff for more realistic explosion
                    
                    -- Scaled damage based on distance
                    local baseDamage = 45  -- Increased base damage for rockets
                    local actualDamage = math.floor(baseDamage * damageFactor)
                    
                    -- Minimum damage for splash hits
                    if actualDamage < 5 and distance <= damageRadius * 0.8 then
                        actualDamage = 5  -- Minimum splash damage
                    end
                    
                    -- Enhanced blood effect with direction from explosion
                    if blood and blood.onEnemyDamage and actualDamage > 0 then
                        local direction = {
                            x = (ex - x) / (distance + 0.1),  -- Avoid division by zero
                            y = (ey - y) / (distance + 0.1)
                        }
                        blood.onEnemyDamage(ex, ey, actualDamage, direction)
                    end
                    
                    -- Apply damage using new health system
                    if enemy and enemy.damageEnemy and actualDamage > 0 then
                        enemy.damageEnemy(i, actualDamage)
                        
                        -- Add explosive knockback force (strongest of all weapons)
                        local knockback_direction = {
                            x = (ex - x) / (distance + 0.1),  -- Avoid division by zero
                            y = (ey - y) / (distance + 0.1)
                        }
                        
                        -- Scale knockback force by damage and proximity
                        local base_explosion_force = 150  -- Reduced base force for proper mass enemies
                        local distance_factor = math.max(0.2, 1 - (distance / damageRadius))  -- Minimum 20% force
                        local final_force = base_explosion_force * distance_factor
                        
                        -- Apply extra force for direct hits
                        if distance <= inst.radius then
                            final_force = final_force * 1.5  -- 50% bonus for direct hits
                        end
                        
                        local knockback_x = knockback_direction.x * final_force
                        local knockback_y = knockback_direction.y * final_force
                        
                        -- Apply the explosive knockback force to the enemy
                        physSafe.safeApplyImpulse(eb, knockback_x, knockback_y)
                        
                        -- Track splash hit for visual effects
                        table.insert(splash_enemies, {
                            index = i,
                            x = ex,
                            y = ey,
                            distance = distance,
                            damage = actualDamage,
                            is_direct_hit = distance <= inst.radius,
                            knockback_force = final_force
                        })
                    end
                end
            end
        end
        
        -- Add visual splash indicators for multiple enemy hits
        if #splash_enemies > 1 then
            -- Create a "SPLASH!" indicator at explosion center for multi-kills
            if enemy and enemy.damage_indicators then
                table.insert(enemy.damage_indicators, {
                    x = x,
                    y = y - 30,
                    damage = "SPLASH!",
                    time = 0,
                    duration = 1.5,
                    velocity_y = -60,
                    velocity_x = 0,
                    alpha = 1,
                    scale = 1.5,
                    bounce_factor = 0.95,
                    nearby_count = 0,
                    is_splash_indicator = true
                })
            end
        end
    end

    -- defer rocket destruction until after physics step
    table.insert(toDestroy, inst)
end

-- Destroy a rocket safely (called during update when world is not locked)
function rocket.destroyRocket(rocket_inst, index)
    if rocket_inst.body and rocket_inst.fixture then
        rocket_inst.fixture:destroy()
        rocket_inst.body:destroy()
    end
    rocket_inst.destroyed = true
    if index then
        table.remove(rocket.rockets, index)
    end
end


function rocket.getNetworkData()
    local network_data = {}
    for i = 1, #rocket.rockets do
        if rocket.rockets[i] and not rocket.rockets[i].destroyed then
            local rocket_x, rocket_y = rocket.rockets[i].body:getPosition()
            table.insert(network_data, {
                x = rocket_x,
                y = rocket_y,
                active = true,
                id = i
            })
        end
    end
    return network_data
end

function rocket.setOnline(index, pos)
    if rocket.online_rockets[index] then
        rocket.online_rockets[index]:setPosition(pos.x, pos.y)
    else
        if world then
            rocket.online_rockets[index] = love.physics.newBody(world, pos.x, pos.y, "dynamic")
            local shape = love.physics.newCircleShape(5)
            local fixture = love.physics.newFixture(rocket.online_rockets[index], shape)
            fixture:setGroupIndex(-3)
        end
    end
end

return rocket
