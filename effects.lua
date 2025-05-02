local effects = {}

local hitmarkers = {}
hitmarkerImage = nil

function effects.load()

    hitmarkerImage = love.graphics.newImage("gfx/menu/hitmarker_1.png")
end

function effects.newHitMarker(x, y)

    local hitmarker = {
        x = x,
        y = y,
        scale = 1.5,  
        rotation = 0, 
        alpha = 1,    
        lifetime = 0.5, 
        timer = 0     
    }

    table.insert(hitmarkers, hitmarker)

end

function effects.update(dt)

    for i = #hitmarkers, 1, -1 do
        local hm = hitmarkers[i]
        hm.timer = hm.timer + dt

        local lifePercent = hm.timer / hm.lifetime
        hm.scale = 1.5 - (0.5 * lifePercent)  
        hm.alpha = 1 - lifePercent            

        if hm.timer >= hm.lifetime then
            table.remove(hitmarkers, i)
        end
    end
end

function effects.draw()

    love.graphics.setBlendMode("alpha")

    for _, hm in ipairs(hitmarkers) do

        local r, g, b, a = love.graphics.getColor()

        love.graphics.setColor(1, 1, 1, hm.alpha)

        love.graphics.draw(
            hitmarkerImage,
            hm.x,
            hm.y,
            hm.rotation,          
            hm.scale, hm.scale,   
            hitmarkerImage:getWidth() / 2,  
            hitmarkerImage:getHeight() / 2  
        )

        love.graphics.setColor(r, g, b, a)
    end
end

function effects.clear()
    hitmarkers = {}
end

return effects