local fire = {}
fire.scale = 0.8
fire.t = 0
fire.fireables = {}
fire.count = 10
fire.pierce = true
fire_bodies = {}    -- only have collision when they are shot, not spinning (maybe change?)
fire_instances = {} -- no collision on these for now
-- local sprite = require('sprite')

fireSpriteImg = love.graphics.newImage('gfx/firelowres.png')
-- myMath = require("myMath")
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

    for i = 1, fire.count do
        table.insert(fire_instances, vec2.new(0, 0))
    end
end

function fire.update(dt)
    fire.particleSystem:update(dt)
    fire.t = fire.t + dt
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
    local fire_main_x, fire_main_y = 500, 200
    table.insert(dynamic_draw_list, {
        sort_y = fire_main_y,
        image_or_particles = fire.particleSystem,
        quad = nil,
        x = fire_main_x,
        y = fire_main_y,
        rotation = 0,
        scale_x = fire.scale,
        scale_y = fire.scale,
        offset_x = 0,
        offset_y = 0,
        color = { 0.13, 0.37, 1, 1 },
        blend_mode = { "lighten", "premultiplied" },
        source_object_type = "fire_effect"
    })

    for i, fire_instance in pairs(fire_instances) do
    -- local fire_instance_x = player.body:getX() + (math.sin(fire.t * 1 + i) * (math.sin(fire.t * 2) + 2)) * 30 + 200
    -- local fire_instance_y = player.body:getY() + (math.cos(fire.t * 1 + i) * (math.sin(fire.t * 2) + 2)) * 30 + 45
    
    -- fire_instance.x = player.body:getX() + (math.sin(fire.t * 1 + i) * (math.sin(fire.t * 2) + 2)) * 30 + 200
    fire_instance.x = player.body:getX() + 10
    
    -- fire_instance.y = player.body:getY() + (math.cos(fire.t * 1 + i) * (math.sin(fire.t * 2) + 2)) * 30 + 45
    fire_instance.y = player.body:getY() + 10
    -- table.insert(fire_instances, {fire_instance_x, fire_instance_y})
    
    -- Default fire effect
    table.insert(dynamic_draw_list, {
        sort_y = fire_instance.y + 100,
        image_or_particles = fire.particleSystem,
        quad = nil,
        x = fire_instance.x,
        y = fire_instance.y,
        rotation = 0,
        scale_x = fire.scale,
        scale_y = fire.scale,
        offset_x = 250,
        offset_y = 50,
        color = { 1, 1, 1, 1 },
        blend_mode = { "lighten", "premultiplied" },
        source_object_type = "fire_effect"
    })
end

-- Fireables loop using pairs
for i, fireable in pairs(fire.fireables) do
    if fireable[1] then
    if not fireable[3] then
        
        -- Set starting position
        -- fireable[1] = vec2.new(fire_instances[i].x, fire_instances[i].y)
        
        -- print(vec2.norm(fireable[1]))
        local _bod = love.physics.newBody(world, fireable[1].x - 200, fireable[1].y - 45, "dynamic")
        
        table.insert(fire_bodies, i, _bod)
        local _fixture = love.physics.newFixture(_bod, love.physics.newCircleShape(20))
        _fixture:setGroupIndex(-1)
        -- _fixture:setFilterData(500,1, -1)
        -- _bod:applyForce(fireable[2].x *fire.t,fireable[2].y*fire.t)
        fireable[3] = 1 -- initialized
        -- direction is already stored in [2]


    else
        -- Move fireball using the pre-calculated direction
        -- print(fire_bodies[1]:getPosition())
        -- local tmp_fire = fireable[1]
        fireable[1] = fireable[1] + fireable[2] * 2
        -- love.graphics.line(fireable[1].x - 200, fireable[1].y - 45, (tmp_fire.x - 200)*2, (tmp_fire.y - 45)*2) -- debug draw
        fire_bodies[i]:setPosition(fireable[1].x - 200, fireable[1].y - 45)
    end
    
    -- Draw fireball
    table.insert(dynamic_draw_list, {
        sort_y = fireable[1].y + 100,
        image_or_particles = fire.particleSystem,
        quad = nil,
        x = fireable[1].x,
        y = fireable[1].y,
        rotation = 0,
        scale_x = fire.scale,
        scale_y = fire.scale,
        offset_x = 250,
        offset_y = 50,
        color = { 1, 1, 1, 1 },
        blend_mode = { "lighten", "premultiplied" },
        source_object_type = "fire_effect"
    })
end
end
    
end

function fire.collision(fixture_a, fixture_b, contact)
    if not (var.multiplayer == 2) then


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
        if (checkDestroy(enemies_bods, not_fire:getBody())) then
            fire.count = fire.count + (math.random() < 0.1 and 1  or 0)
        end
        if (checkDestroy(coin_bods, not_fire:getBody())) then
            fire.count = fire.count + (math.random() < 0.1 and 1 or 0)
        end
        if not fire.pierce then
            table.remove(fire.fireables, checkDestroy(fire_bodies, firef:getBody()) or 0) -- remove line for piercing !!
        end
        -- checkDestroy(fire_bodies, firef:getBody())
        -- print()
    end
end
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
                -- position = {
                x = fire.fireables[i][1].x,
                y = fire.fireables[i][1].y,
                -- },
                -- direction = {
                --     x = fire.fireables[i][2].x,
                --     y = fire.fireables[i][2].y
                -- },
                -- initialized = fire.fireables[i][3],
                active = true
            })
        end
        end
    end

    -- Include fire bodies physics data (for collision sync)
    -- network_data.fire_bodies = {}
    -- print(fire_instances)
    -- for k,v in pairs(fire_instances) do print(k,v.x) end


    for i = 1, #fire_instances do
        -- local fire_instance_x = player.body:getX() + (math.sin(fire.t * 1 + i)*(math.sin(fire.t*2) + 2)) * 30 + 200
        -- local fire_instance_y = player.body:getY() + (math.cos(fire.t * 1 + i)*(math.sin(fire.t*2)+ 2))* 30 + 45
        -- local index = #fire.fireables + i
        table.insert(network_data, {
            x = fire_instances[i].x,
            y = fire_instances[i].y,
            active = true
            -- type = "spinning"
        })
    end

    return network_data
end

return fire
