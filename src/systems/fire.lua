local fire = {}
local physSafe = require("util.physics_safe")
fire.scale = 0.8
fire.t = 0
fire.fireables = {}
fire.online_fireables = {}
fire.count = 1  -- Start with 6 fireballs
fire.max_fireballs = 1  -- Maximum fireballs allowed
fire.pierce = true
fire_bodies = {}    -- only have collision when they are shot, not spinning (maybe change?)
fire_instances = {} -- Active fireballs in the ring - no collision on these for now
fire_draw_data = {} -- cached draw data updated only in fire.update()
-- local sprite = require('lib.graphics.sprite')

fireSpriteImg = love.graphics.newImage('gfx/firelowres.png')
-- myMath = require("lib.math.myMath")
function fire.load()
    Quads = sprite:constructsprite(fireSpriteImg, 8, 8)
    fire.particleSystem = love.graphics.newParticleSystem(fireSpriteImg, 500)
    particleSystem = fire.particleSystem

    -- PARTICLE SYSTEM CONFIGURATION
    -- fire.particleSystem:setParticleLifetime(3, 3)
    fire.particleSystem:setParticleLifetime(1, 2)
    fire.particleSystem:setEmissionRate(8)
    fire.particleSystem:setSizeVariation(1)
    fire.particleSystem:setDirection(1.5 * 3.14)
    fire.particleSystem:setSpeed(0, 50)
    fire.particleSystem:setLinearDamping(0.33)
    fire.particleSystem:setSpin(-0.25, 0.95)
    fire.particleSystem:setColors(255, 255, 255, 255, 255, 255, 255, 0.1)
    fire.particleSystem:setQuads(Quads)
    fire.particleSystem:setRotation(0, 2 * 3.14)
    fire.particleSystem:setOffset(sprite:getTileSize())
    fire.particleSystem:setInsertMode('bottom')

    -- Initialize the fireball ring with starting count
    fire_instances = {}
    for i = 1, fire.count do
        table.insert(fire_instances, {
            pos = vec2.new(0, 0),
            ring_index = i,  -- Position in the ring
            active = true
        })
    end
    
    -- Initialize draw data cache
    fire_draw_data = {}
end

function fire.update(dt)
    fire.particleSystem:update(dt)
    fire.t = fire.t + dt
    
    -- Clear previous draw data
    fire_draw_data = {}
    
    -- Update fire instance positions in ring formation
    local active_count = #fire_instances
    for i, fire_instance in ipairs(fire_instances) do
        if fire_instance.active then
            -- Calculate ring position based on index and total active fireballs
            local angle = (i - 1) * (2 * math.pi / active_count) + fire.t * 0.5  -- Slow rotation
            local radius = 40 + math.sin(fire.t * 2) * 10  -- Pulsing radius
            
            -- Get player position - no offsets, ring should be centered on player
            local player_x, player_y = player.getPosition()
            
            fire_instance.pos.x = player_x + math.cos(angle) * radius
            fire_instance.pos.y = player_y + math.sin(angle) * radius
            
            -- Cache draw data for fire instances
            table.insert(fire_draw_data, {
                sort_y = fire_instance.pos.y + 130,
                image_or_particles = fire.particleSystem,
                quad = nil,
                x = fire_instance.pos.x,
                y = fire_instance.pos.y,
                rotation = 0,
                scale_x = fire.scale,
                scale_y = fire.scale,
                offset_x = 0,
                offset_y = 0,
                color = { 1, 1, 1, 1 },
                blend_mode = { "lighten", "premultiplied" },
                source_object_type = "fire_effect"
            })
        end
    end
    
    -- Update fireables positions and physics
    for i, fireable in pairs(fire.fireables) do
        if fireable[1] then
            if not fireable[3] then
                -- Set starting position
                -- fireable[1] = vec2.new(fire_instances[i].x, fire_instances[i].y)
                
                -- Only create physics bodies on host (var.multiplayer == 1)
                -- Clients still initialize fireballs for visual purposes but no physics
                -- if (var.multiplayer == 1) then
                    -- print(vec2.norm(fireable[1]))
                    local _bod = love.physics.newBody(world, fireable[1].x, fireable[1].y, "dynamic")
                    table.insert(fire_bodies, i, _bod)
                    local _fixture = love.physics.newFixture(_bod, love.physics.newCircleShape(20))
                    _fixture:setGroupIndex(-1)
                    -- _fixture:setFilterData(500,1, -1)
                    -- _bod:applyForce(fireable[2].x *fire.t,fireable[2].y*fire.t)
                -- end
                fireable[3] = 1 -- initialized (both host and client mark as initialized)
                -- direction is already stored in [2]

            else
                -- Move fireball using the pre-calculated direction
                -- This happens on both host and clients for local prediction/rendering
                fireable[1] = fireable[1] + fireable[2] * 2
                
                -- Only update physics body position on host
                if (var.multiplayer == 1) and fire_bodies[i] then
                    fire_bodies[i]:setPosition(fireable[1].x, fireable[1].y)
                elseif not var.multiplayer then
                    fire_bodies[i]:setPosition(fireable[1].x, fireable[1].y)
                end
            end
            
            -- Cache draw data for fireables
            table.insert(fire_draw_data, {
                sort_y = fireable[1].y + 100,
                image_or_particles = fire.particleSystem,
                quad = nil,
                x = fireable[1].x,
                y = fireable[1].y,
                rotation = 0,
                scale_x = fire.scale,
                scale_y = fire.scale,
                offset_x = 0,
                offset_y = 0,
                color = { 1, 1, 1, 1 },
                blend_mode = { "lighten", "premultiplied" },
                source_object_type = "fire_effect"
            })
        end
    end
end

function fire.draw()
    -- love.graphics.setBlendMode("add")
    love.graphics.setBlendMode("lighten", "premultiplied")

    -- love.graphics.setColor(.90, .17, .48, 1)
    love.graphics.setColor(.13, .37, 1, 1)

    fire.fires(fire.count)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(fire.particleSystem, 500, 200, 0, fire.scale, fire.scale)

    --  'alpha', 'add', 'subtract', 'multiply', 'lighten', 'darken', 'screen', 'replace', 'none'

    -- love.graphics.circle("fill", 300, 300, 50, 5)   -- Draw red circle with five segments.

    love.graphics.setBlendMode("alpha") -- Default blend mode.

    -- love.graphics.setColor(.04, .39, .90)
    -- love.graphics.setBlendMode("multiply", "premultiplied")
    -- love.graphics.rectangle("fill", 75,75, 125,125)
end

function fire.fires(n)
    for i = 1, n do
        -- love.graphics.setColor(1,1,1, 1)
        -- love.graphics.draw(fire.particleSystem, player.body:getX() + math.sin(fire.t * 5 + 30 + 10 * i) * 20 - 35, player.body:getY() + math.cos(fire.t * 5 + 30 + 10 * i) * 20 - 30, 0, fire.scale, fire.scale, -2348, -808)
        love.graphics.draw(fire.particleSystem, player.body:getX() + 200 + math.sin(fire.t * 5 + i) * 20,
            player.body:getY() + math.cos(fire.t * 5 + i) * 20 + 45, 0, fire.scale, fire.scale)
    end
end

function fire.populate()
    -- Main static fire
    -- local fire_main_x, fire_main_y = 500, 200
    -- table.insert(dynamic_draw_list, {
    --     sort_y = fire_main_y,
    --     image_or_particles = fire.particleSystem,
    --     quad = nil,
    --     x = fire_main_x,
    --     y = fire_main_y,
    --     rotation = 0,
    --     scale_x = fire.scale,
    --     scale_y = fire.scale,
    --     offset_x = 0,
    --     offset_y = 0,
    --     color = { 0.13, 0.37, 1, 1 },
    --     blend_mode = { "lighten", "premultiplied" },
    --     source_object_type = "fire_effect"
    -- })

    -- Add all cached draw data to dynamic_draw_list
    for _, draw_item in pairs(fire_draw_data) do
        table.insert(dynamic_draw_list, draw_item)
    end
end

function fire.collision(fixture_a, fixture_b, contact)
    -- Only process collisions on host since physics only happens on host's world
    if (var.multiplayer ~= 1) and var.multiplayer then return end

    local not_fire
    local firef
    if fixture_a:getGroupIndex() == -1 then
        not_fire = fixture_b
        firef = fixture_a
    elseif fixture_b:getGroupIndex() == -1 then
        not_fire = fixture_a
        firef = fixture_b
    end

    -- print(fixture_a:getGroupIndex() == -1 , fixture_b:getGroupIndex() == -1)
    -- print(math.random() < 0.01 and 1 or 0)
    if not_fire ~= nil then
        -- print(not_fire:getGroupIndex())
        -- Check if hit an enemy  
        for i = 1, #enemies_bods do
            if enemies_bods[i] and enemies_bods[i] == not_fire:getBody() then
                -- Apply fire damage to enemy using new health system
                if enemy and enemy.damageEnemy then
                    local damage_amount = math.random(15, 25)  -- Fire does more damage than bullets
                    enemy.damageEnemy(i, damage_amount)
                    
                    -- Add knockback force from fire impact (stronger than bullets)
                    local enemy_body = enemies_bods[i]
                    if firef then
                        local fire_body = firef:getBody()
                        if fire_body then
                            local fx, fy = fire_body:getPosition()
                            local ex, ey = physSafe.safeGetPosition(enemy_body)
                            
                            if ex and ey then
                                -- Calculate knockback direction from fire to enemy
                                local dx = ex - fx
                                local dy = ey - fy
                                local distance = math.sqrt(dx*dx + dy*dy)
                                
                                if distance > 0 then
                                    local fire_force = 70  -- Reduced but still stronger than bullets
                                    local knockback_x = (dx / distance) * fire_force
                                    local knockback_y = (dy / distance) * fire_force
                                    
                                    -- Apply the knockback force to the enemy using safe method
                                    physSafe.safeApplyImpulse(enemy_body, knockback_x, knockback_y)
                                end
                            end
                        end
                    end
                end
                
                -- 10% chance to add fireball when hitting enemy
                if math.random() < 0.1 then
                    fire.addFireball()
                end
                break
            end
        end
        if (checkDestroy(coin_bods, not_fire:getBody())) then
            -- 10% chance to add fireball when hitting coin with fireball
            if math.random() < 0.1 then
                fire.addFireball()
            end
        end
        if not fire.pierce then
            table.remove(fire.fireables, checkDestroy(fire_bodies, firef:getBody()) or 0) -- remove line for piercing !!
        end
        -- checkDestroy(fire_bodies, firef:getBody())
        -- print()
    end

end

-- Add a fireball to the ring (when collecting coins)
function fire.addFireball()
    if #fire_instances < fire.max_fireballs then
        table.insert(fire_instances, {
            pos = vec2.new(0, 0),
            ring_index = #fire_instances + 1,
            active = true
        })
        fire.count = #fire_instances
    end
end

-- Remove a fireball from the ring (when shooting)
function fire.removeFireball()
    if #fire_instances > 0 then
        -- Remove the last fireball in the ring
        table.remove(fire_instances)
        fire.count = #fire_instances
        return true
    end
    return false
end

-- Get available fireball count
function fire.getAvailableCount()
    return #fire_instances
end

function fire.getNetworkData()
    local network_data = {}

    -- Include main fire system state
    -- -- network_data.main_fire = {
    --     t = fire.t,
    --     count = fire.count,
    --     scale = fire.scale,
    --     active = true
    -- }

    -- Include fireball projectiles data
    -- network_data.fireables = {}
    for i = 1, #fire.fireables do
        if fire.fireables[i] and fire.fireables[i][3] ~= nil then -- initialized fireball
        -- print(fire.fireables[i][1].x)
        if (fire.fireables[i][1]) then
            table.insert(network_data, {
                x = fire.fireables[i][1].x + 200,
                y = fire.fireables[i][1].y + 45,
                active = true,
                id = i
            })
        end
        end
    end

    

    -- Include fire bodies physics data (for collision sync)
    for i = 1, #fire_instances do
        table.insert(network_data, {
            x = fire_instances[i].pos.x + 200,
            y = fire_instances[i].pos.y + 45,
            active = false -- starts in this state by the time its non active again it should just be deleted (collided)
        })
    end

    return network_data
end



function fire.setOnline(index,pos)

  if fire.online_fireables[index] then
    -- print("table index already in use setting")
    fire.online_fireables[index]:setPosition(pos.x, pos.y)
  else 
    fire.online_fireables[index] = love.physics.newBody(world, pos.x, pos.y, "dynamic")
    local _fixture = love.physics.newFixture(fire.online_fireables[index], love.physics.newCircleShape(20))
    _fixture:setGroupIndex(-1)
  end


end

return fire
