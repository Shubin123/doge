local fire = {}
fire.scale = 0.8
fire.t = 0
-- local sprite = require('sprite')

local spriteImg = love.graphics.newImage('gfx/firelowres.png')
-- myMath = require("myMath")
function fire.load()

    Quads = sprite:constructsprite(spriteImg, 8, 8)
    particleSystem = love.graphics.newParticleSystem(spriteImg, 500)

    -- PARTICLE SYSTEM CONFIGURATION
    -- particleSystem:setParticleLifetime(3, 3)
    particleSystem:setParticleLifetime(1, 2)
    particleSystem:setEmissionRate(8)
    particleSystem:setSizeVariation(1)
    particleSystem:setDirection(1.5 * 3.14)
    particleSystem:setSpeed(0, 50)
    particleSystem:setLinearDamping(0.33)
    particleSystem:setSpin(-0.25, 0.95)
    particleSystem:setColors(255, 255, 255, 255, 255, 255, 255, 0.1)
    particleSystem:setQuads(Quads)
    particleSystem:setRotation(0, 2 * 3.14)
    particleSystem:setOffset(sprite:getTileSize())
    particleSystem:setInsertMode('bottom')
end

function fire.update(dt)
    particleSystem:update(dt)
    fire.t = fire.t + dt
end
fire.count = 0
function fire.draw()

    -- love.graphics.setBlendMode("add")
    love.graphics.setBlendMode("lighten", "premultiplied")

    -- love.graphics.setColor(.90, .17, .48, 1)
    love.graphics.setColor(.13, .37, 1, 1)
    
    fire.fires(fire.count)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(particleSystem, 500, 200, 0, fire.scale, fire.scale)

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
        -- love.graphics.draw(particleSystem, player.body:getX() + math.sin(fire.t * 5 + 30 + 10 * i) * 20 - 35, player.body:getY() + math.cos(fire.t * 5 + 30 + 10 * i) * 20 - 30, 0, fire.scale, fire.scale, -2348, -808)
        love.graphics.draw(particleSystem, player.body:getX() + 200 + math.sin(fire.t * 5 + i) * 20, player.body:getY() + math.cos(fire.t * 5 + i) * 20 + 45, 0,fire.scale,fire.scale)

    end
end

return fire
