local fire = {}
local physSafe = require("util.physics_safe")

-- Core system properties
fire.scale = 0.8
fire.t = 0
fire.fireables = {}
fire.online_fireables = {}
fire.count = 1
fire.max_fireballs = 7
fire.pierce = true
fire.loaded_effects = {}
fire.current_effect_index = 1

fire_bodies = {}
fire_instances = {}
fire_draw_data = {}


-- =============================================================================
-- ALL FX LOADED - Random selection available!
-- =============================================================================

fire.effects = {
    {path = 'gfx/firelowres.png', grid = {8, 8}},
    -- {path = 'gfx/fx/Spritesheets/Smoke-Sheet.png', grid = {4, 5}},
    -- {path = 'gfx/fx/Spritesheets/Water Vortex Splash-Sheet.png', grid = {5, 6}},
    -- {path = 'gfx/fx/Spritesheets/Blood Splat.png', grid = {5, 2}},
    -- {path = 'gfx/fx/Spritesheets/Eletric A-Sheet.png', grid = {3, 3}},
    -- {path = 'gfx/fx/Spritesheets/Eletric Aura.png', grid = {5, 2}},
    
    
    -- {path = 'gfx/fx/Spritesheets/Fire+Sparks-Sheet.png', grid = {5, 5}},
    
    

    -- -- {path = 'gfx/fx/Spritesheets/Gravity-Sheet.png', grid = {4, 5}},
    
    
    

    -- {path = 'gfx/fx/Spritesheets/Poison Cloud-Sheet.png', grid = {4, 4}},
    -- {path = 'gfx/fx/Spritesheets/Regen.png', grid = {5, 3}},


    -- {path = 'gfx/fx/Spritesheets/Leaves-Sheet.png', grid = {5, 3}},

    -- {path = 'gfx/fx/Spritesheets/Sakuras.png', grid = {5, 2}},
    
    -- -- {path = 'gfx/fx/Spritesheets/Rocket Fire 2-Sheet.png', grid = {6, 3}},
    -- -- {path = 'gfx/fx/Spritesheets/Flamethrower-Sheet.png', grid = {4, 3}},
    -- -- {path = 'gfx/fx/Spritesheets/Smoke2-Sheet.png', grid = {5, 8}},
    -- -- {path = 'gfx/fx/Spritesheets/Holy Light Aura.png', grid = {4, 3}},

    -- {path = 'gfx/fx/Spritesheets/Spark1-Sheet.png', grid = {4, 3}},
    -- {path = 'gfx/fx/Spritesheets/Sparks-Sheet.png', grid = {5, 8}},
    -- {path = 'gfx/fx/Spritesheets/Splatter-Sheet.png', grid = {4, 4}}
}


-- =============================================================================

function fire.load()
    -- Load all effects
    for i, effect in ipairs(fire.effects) do
        fire.loaded_effects[i] = {}
        fire.loaded_effects[i].image = love.graphics.newImage(effect.path)
        fire.loaded_effects[i].quads = sprite:constructsprite(fire.loaded_effects[i].image, effect.grid[1], effect.grid[2])
        fire.loaded_effects[i].particleSystem = love.graphics.newParticleSystem(fire.loaded_effects[i].image, 500)
        
        -- Configure particle system
        local ps = fire.loaded_effects[i].particleSystem
        ps:setParticleLifetime(1, 2)
        ps:setEmissionRate(8)
        ps:setSizeVariation(1)
        ps:setDirection(1.5 * 3.14)
        ps:setSpeed(0, 50)
        ps:setLinearDamping(0.33)
        ps:setSpin(-0.25, 0.95)
        ps:setColors(255, 255, 255, 255, 255, 255, 255, 0.1)
        ps:setQuads(fire.loaded_effects[i].quads)
        ps:setRotation(0, 2 * 3.14)
        ps:setOffset(sprite:getTileSize())
        ps:setInsertMode('bottom')
    end
    
    -- Set initial effect
    fire.setCurrentEffect(1)

    -- Initialize the fireball ring with starting count
    fire_instances = {}
    for i = 1, fire.count do
        table.insert(fire_instances, {
            pos = vec2.new(0, 0),
            ring_index = i,  -- Position in the ring
            active = true,
            effect_index = fire.current_effect_index  -- Each fireball can have its own effect
        })
    end
    
    -- Initialize draw data cache
    fire_draw_data = {}
end

function fire.setCurrentEffect(index)
    if fire.loaded_effects[index] then
        fire.current_effect_index = index
        fire.particleSystem = fire.loaded_effects[index].particleSystem
        particleSystem = fire.particleSystem
        Quads = fire.loaded_effects[index].quads
    end
end

function fire.randomizeEffect()
    -- local random_index = math.random(1, #fire.effects)
    -- fire.setCurrentEffect(random_index)
    -- return random_index
end

function fire.randomizeAllFireballs()
    -- Give each fireball in the ring a random effect
    for i, fire_instance in ipairs(fire_instances) do
        fire_instance.effect_index = math.random(1, #fire.effects)
    end
end

function fire.update(dt)
    -- Update all particle systems
    for i = 1, #fire.loaded_effects do
        fire.loaded_effects[i].particleSystem:update(dt)
    end
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
            
            -- Use the specific effect for this fireball
            local effect_ps = fire.loaded_effects[fire_instance.effect_index].particleSystem
            
            -- Cache draw data for fire instances
            table.insert(fire_draw_data, {
                sort_y = fire_instance.pos.y + 130,
                image_or_particles = effect_ps,
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
                -- Set starting position and assign random effect to new fireball
                if not fireable[4] then -- effect_index not set yet
                    fireable[4] = math.random(1, #fire.effects)
                end
                
                local _bod = love.physics.newBody(world, fireable[1].x, fireable[1].y, "dynamic")
                table.insert(fire_bodies, i, _bod)
                local _fixture = love.physics.newFixture(_bod, love.physics.newCircleShape(20))
                _fixture:setGroupIndex(-2)
                _fixture:setUserData({"fireball", 10}) -- needs to be different from bullets else it will do same damage as bullet
                fireable[3] = 1 -- initialized

            else
                -- Move fireball using the pre-calculated direction
                fireable[1] = fireable[1] + fireable[2] * 2
                
                -- Only update physics body position on host
                if (var.multiplayer == 1) and fire_bodies[i] then
                    fire_bodies[i]:setPosition(fireable[1].x, fireable[1].y)
                elseif not var.multiplayer then
                    fire_bodies[i]:setPosition(fireable[1].x, fireable[1].y)
                end
            end
            
            -- Use the specific effect for this fireable
            local effect_ps = fire.loaded_effects[fireable[4] or 1].particleSystem
            
            -- Cache draw data for fireables
            table.insert(fire_draw_data, {
                sort_y = fireable[1].y + 130,
                image_or_particles = effect_ps,
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

-- function fire.draw()
--     love.graphics.setBlendMode("lighten", "premultiplied")
--     love.graphics.setColor(.13, .37, 1, 1)

--     fire.fires(fire.count)
--     love.graphics.setColor(1, 1, 1)
--     love.graphics.draw(fire.particleSystem, 500, 200, 0, fire.scale, fire.scale)

--     love.graphics.setBlendMode("alpha") -- Default blend mode.
-- end

-- function fire.fires(n)
--     for i = 1, n do
--         love.graphics.draw(fire.particleSystem, player.body:getX() + 200 + math.sin(fire.t * 5 + i) * 20,
--             player.body:getY() + math.cos(fire.t * 5 + i) * 20 + 45, 0, fire.scale, fire.scale)
--     end
-- end

function fire.populate()
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
    if fixture_a:getGroupIndex() == -2 then
        not_fire = fixture_b
        firef = fixture_a
    elseif fixture_b:getGroupIndex() == -2 then
        not_fire = fixture_a
        firef = fixture_b
    end

    if not_fire ~= nil then
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
    end
end

function fire.addFireball()
    if #fire_instances < fire.max_fireballs then
        table.insert(fire_instances, {
            pos = vec2.new(0, 0),
            ring_index = #fire_instances + 1,
            active = true,
            effect_index = math.random(1, #fire.effects)  -- Random effect for new fireball
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

    -- Include fireball projectiles data
    for i = 1, #fire.fireables do
        if fire.fireables[i] and fire.fireables[i][3] ~= nil then -- initialized fireball
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

return fire