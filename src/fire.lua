local fire = {}
fire.scale = 0.8
fire.t = 0
fire.fireables = {}
fire.count = 100
fire_bodies = {}
-- local sprite = require('sprite')

local spriteImg = love.graphics.newImage('gfx/firelowres.png')
-- myMath = require("myMath")
function fire.load()

    Quads = sprite:constructsprite(spriteImg, 8, 8)
    fire.particleSystem = love.graphics.newParticleSystem(spriteImg, 500)
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
        love.graphics.draw(fire.particleSystem, player.body:getX() + 200 + math.sin(fire.t * 5 + i) * 20, player.body:getY() + math.cos(fire.t * 5 + i) * 20 + 45, 0,fire.scale,fire.scale)

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
            color = {0.13, 0.37, 1, 1},
            blend_mode = {"lighten", "premultiplied"},
            source_object_type = "fire_effect"
        })
        
for i = 1, fire.count do
    local fire_instance_x = player.body:getX() + (math.sin(fire.t * 5 + i)*(math.sin(fire.t) + 2)) * 30 + 200
    local fire_instance_y = player.body:getY() + (math.cos(fire.t * 5 + i)*(math.sin(fire.t)+ 2))* 30 + 45
    
    if i <= #fire.fireables then
        if not fire.fireables[i][3] then
            -- Set starting position
            fire.fireables[i][1] = vec2.new(fire_instance_x, fire_instance_y)
            
            -- print(vec2.norm(fire.fireables[i][1]))
            local _bod = love.physics.newBody(world, fire_instance_x, fire_instance_y,"static")
            table.insert(fire_bodies ,i,_bod)
            local _fixture = love.physics.newFixture(_bod, love.physics.newCircleShape(20))
            _fixture:setGroupIndex(666)
            -- _bod:applyForce(fire.fireables[i][2].x *fire.t,fire.fireables[i][2].y*fire.t)
            fire.fireables[i][3] = true  -- initialized
            -- direction is already stored in [2]
        else
            -- Move fireball using the pre-calculated direction
            -- print(fire_bodies[1]:getPosition())
            -- local tmp_fire = fire.fireables[i][1]
            fire.fireables[i][1] = fire.fireables[i][1] + fire.fireables[i][2]*2
            -- love.graphics.line(fire.fireables[i][1].x - 200, fire.fireables[i][1].y - 45, (tmp_fire.x - 200)*2, (tmp_fire.y - 45)*2) -- debug draw
            fire_bodies[i]:setPosition(fire.fireables[i][1].x - 200, fire.fireables[i][1].y - 45)
        end
        
        -- Draw fireball
        table.insert(dynamic_draw_list, {
            sort_y = fire.fireables[i][1].y + 100,
            image_or_particles = fire.particleSystem,
            quad = nil,
            x = fire.fireables[i][1].x,
            y = fire.fireables[i][1].y,
            rotation = 0,
            scale_x = fire.scale,
            scale_y = fire.scale,
            offset_x = 250,
            offset_y = 50,
            color = {1, 1, 1, 1},
            blend_mode = {"lighten", "premultiplied"},
            source_object_type = "fire_effect"
        })
    else
        -- Default fire effect
        table.insert(dynamic_draw_list, {
            sort_y = fire_instance_y + 100,
            image_or_particles = fire.particleSystem,
            quad = nil,
            x = fire_instance_x,
            y = fire_instance_y,
            rotation = 0,
            scale_x = fire.scale,
            scale_y = fire.scale,
            offset_x = 250,
            offset_y = 50,
            color = {1, 1, 1, 1},
            blend_mode = {"lighten", "premultiplied"},
            source_object_type = "fire_effect"
        })
    end
end
end


return fire
