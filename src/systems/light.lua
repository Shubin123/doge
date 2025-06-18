local light = {}

function light.load()
      blueNeon = moonshine(moonshine.effects.glow).chain(moonshine.effects.fastgaussianblur).chain(moonshine.effects.godsray)
  blueNeon.godsray.exposure = 1 --number between 0 and 1
  blueNeon.godsray.decay = 0.8 -- number between 0 and 1
  blueNeon.godsray.density = 0.05 -- number between 0 and 1
  blueNeon.godsray.weight = 0.9 -- number between 0 and 1
  blueNeon.godsray.light_x = 0.5 -- number
  blueNeon.godsray.light_y = 0.5 -- number
  blueNeon.godsray.samples = 30 -- number >= 1
  blueNeon.glow.min_luma = 0
  blueNeon.glow.strength = 5

  yellowNeon = moonshine(moonshine.effects.glow).chain(moonshine.effects.fastgaussianblur).chain(moonshine.effects.godsray)
  yellowNeon.godsray.exposure = 1 --number between 0 and 1
  yellowNeon.godsray.decay = 0.8 -- number between 0 and 1
  yellowNeon.godsray.density = 1 -- number between 0 and 1
  yellowNeon.godsray.weight = 0.9 -- number between 0 and 1
  yellowNeon.godsray.light_x = 0.5 -- number
  yellowNeon.godsray.light_y = 0.5 -- number
  yellowNeon.godsray.samples = 30 -- number >= 1
  yellowNeon.glow.min_luma = 3
  yellowNeon.glow.strength = 5
  yellowNeon.fastgaussianblur.taps = 9
end

function light.draw()
  blueNeon(function()
    love.graphics.setColor(0.17, 0.46, 1)
        -- print( -camera.pos.x)
        -- print( -player.body:getX())
        -- neon light bar right next to player with all transforms applied correctly, such that after the pop it still works.
    --   love.graphics.rectangle("fill",(camera.pos.x + player.body:getX()*camera.zoom), (camera.pos.y + player.body:getY()*camera.zoom), 100*camera.zoom, 3*camera.zoom, 5, 5, 20)
      love.graphics.circle("fill",(camera.pos.x + player.body:getX()*camera.zoom - 2), (camera.pos.y + player.body:getY()*camera.zoom  + 6), 20*camera.zoom)
        
    love.graphics.setColor(1,1,1,1)
    end)

    yellowNeon(function()
    love.graphics.setColor(1, 0.46, 0.3)
    local mx = player.body:getX() + 20*math.sin(fire.t)
    local my = player.body:getY() + 20*math.cos(fire.t)
    

      love.graphics.circle("fill",(camera.pos.x + (mx)*camera.zoom), (camera.pos.y +  (my)*camera.zoom)  , 10*camera.zoom)
        
    love.graphics.setColor(1,1,1,1)
    end)
end

return light