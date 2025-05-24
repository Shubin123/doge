local fire = {}
fire.scale = 0.1
local sprite = require('sprite')
local player = require("player")
local spriteImg = love.graphics.newImage('gfx/fireball.png')
function fire.load()
    
    
    Quads = sprite:constructsprite(spriteImg, 8, 8)
    particleSystem = love.graphics.newParticleSystem(spriteImg, 500)

    --PARTICLE SYSTEM CONFIGURATION
    particleSystem:setParticleLifetime(1, 2)
    particleSystem:setEmissionRate(8)
    particleSystem:setSizeVariation(1)
    particleSystem:setDirection(1.5*3.14)
    particleSystem:setSpeed(0, 200)
    particleSystem:setLinearDamping(0.33)
    particleSystem:setSpin(-0.25, 0.95)
    particleSystem:setColors(255,255, 255, 255, 255, 255, 255, 0.1)
    particleSystem:setQuads(Quads)
    particleSystem:setRotation(0, 2*3.14)
    particleSystem:setOffset(sprite:getTileSize())
    particleSystem:setInsertMode('bottom')
end


function fire.update(dt)
    particleSystem:update(dt)
end

function fire.draw()
    
        -- love.graphics.setBlendMode("additive")
        love.graphics.setBlendMode("lighten","premultiplied")
        
        	-- love.graphics.setColor(.90, .17, .48, 1)
        love.graphics.setColor(.13, .37, 1, 1)
        love.graphics.draw(particleSystem, player.body:getX(),player.body:getY() ,0, fire.scale,fire.scale,-2348,-808 ) 

        love.graphics.setColor(.90, .17, .48, 1)
        love.graphics.draw(particleSystem, player.body:getX(),player.body:getY() ,0, fire.scale,fire.scale,-2008,-808 ) 

         love.graphics.setColor(.30, 1, .48, 1)
        love.graphics.draw(particleSystem, player.body:getX(),player.body:getY() ,0, fire.scale,fire.scale,-2048,-108 ) 
        
        love.graphics.setColor(1,1,1)
        love.graphics.draw(particleSystem, 500,200 ,0, fire.scale,fire.scale) 
   	
    --  'alpha', 'add', 'subtract', 'multiply', 'lighten', 'darken', 'screen', 'replace', 'none'

	-- love.graphics.circle("fill", 300, 300, 50, 5)   -- Draw red circle with five segments.

	love.graphics.setBlendMode("alpha") -- Default blend mode.


	-- love.graphics.setColor(.04, .39, .90)
	-- love.graphics.setBlendMode("multiply", "premultiplied")
	-- love.graphics.rectangle("fill", 75,75, 125,125)
end


return fire