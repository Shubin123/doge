local light = {}
-- light.x,light.y = 0,0
function light.load()
  blueNeon = moonshine(moonshine.effects.glow).chain(moonshine.effects.fastgaussianblur).chain(moonshine.effects.godsray)
  blueNeon.godsray.exposure = 1  --number between 0 and 1
  blueNeon.godsray.decay = 0.8   -- number between 0 and 1
  blueNeon.godsray.density = 15  -- number between 0 and 1
  blueNeon.godsray.weight = 1    -- number between 0 and 1
  blueNeon.godsray.light_x = 0.5 -- number
  blueNeon.godsray.light_y = 0.5 -- number
  blueNeon.godsray.samples = 30  -- number >= 1
  blueNeon.glow.min_luma = 0
  blueNeon.glow.strength = 1
  blueNeon.fastgaussianblur.taps = 9

  yellowNeon = moonshine(moonshine.effects.glow).chain(moonshine.effects.fastgaussianblur).chain(moonshine.effects
  .godsray)
  yellowNeon.godsray.exposure = 1  --number between 0 and 1
  yellowNeon.godsray.decay = 0.8   -- number between 0 and 1
  yellowNeon.godsray.density = 1   -- number between 0 and 1
  yellowNeon.godsray.weight = 0.9  -- number between 0 and 1
  yellowNeon.godsray.light_x = 0.5 -- number
  yellowNeon.godsray.light_y = 0.5 -- number
  yellowNeon.godsray.samples = 30  -- this does nothing now since hardbaked since opengl es3 with js build
  yellowNeon.glow.min_luma = 20
  yellowNeon.glow.strength = 1
  yellowNeon.fastgaussianblur.taps = 9

  whiteNeon = moonshine(moonshine.effects.glow).chain(moonshine.effects.fastgaussianblur).chain(moonshine.effects
  .godsray)
  whiteNeon.godsray.exposure = 1  --number between 0 and 1
  whiteNeon.godsray.decay = 0.8   -- number between 0 and 1
  whiteNeon.godsray.density = 0.5   -- number between 0 and 1
  whiteNeon.godsray.weight = 0.9  -- number between 0 and 1
  whiteNeon.godsray.light_x = 0.5 -- number
  whiteNeon.godsray.light_y = 0.5 -- number
  whiteNeon.godsray.samples = 30  -- this does nothing now since hardbaked since opengl es3 with js build
  whiteNeon.glow.min_luma = 20
  whiteNeon.glow.strength = 1
  whiteNeon.fastgaussianblur.taps = 9

  pixelNeon = moonshine(moonshine.effects.glow).chain(moonshine.effects.fastgaussianblur).chain(moonshine.effects
  .godsray).chain(moonshine.effects.pixelate)
  pixelNeon.godsray.exposure = 10  --number between 0 and 1
  pixelNeon.godsray.decay = 0.8   -- number between 0 and 1
  pixelNeon.godsray.density = 0.5   -- number between 0 and 1
  pixelNeon.godsray.weight = 0.1  -- number between 0 and 1
  pixelNeon.godsray.light_x = 0.1 -- number
  pixelNeon.godsray.light_y = 0.1 -- number
  pixelNeon.godsray.samples = 1  -- this does nothing now since hardbaked since opengl es3 with js build
  pixelNeon.glow.min_luma = 10
  pixelNeon.glow.strength = 10
  pixelNeon.fastgaussianblur.taps = 9


  pixelate = moonshine(moonshine.effects.pixelate)
end

-- Indoor key light: a soft warm glow rendered through the godray/glow chain.
-- Only visible while indoors (alpha gates on var.indoors).
function light.draw()
  yellowNeon(function()
    love.graphics.setColor(1, 0.46, 0.3, var.indoors and 1 or 0)
    -- local mx = player.body:getX() + 20*math.sin(fire.t)
    -- local my = player.body:getY() + 20*math.cos(fire.t)

    local mx = 500 - 2
    local my = 300 - 25




    love.graphics.circle("fill", (camera.pos.x + (mx) * camera.zoom), (camera.pos.y + (my) * camera.zoom), 8 *
    camera.zoom)
  end)
end

function light.populate()
  table.insert(dynamic_draw_list, {
    sort_y = player.body:getY() + 100,
    x = 0,
    y = 0,
    draw_type = "light"
  })
end

function light.renderLights(drawable)
  if drawable.draw_type == "light" and player.lightsOn then
    love.graphics.push()

    love.graphics.reset()
    
    blueNeon(function()
      love.graphics.setColor(0.17, 0.46, 1, 0.5)

      -- Aim the flashlight cone along the gun's current velocity/heading.
      local playerX, playerY = player.body:getPosition()
      local velX, velY = gun.currentVel.x, gun.currentVel.y

      -- Calculate the heading angle
      local angle = 0
      if math.abs(velX) > 0.1 or math.abs(velY) > 0.1 then
        angle = math.atan2(velY, velX)
      end

      -- Convert angle to a direction vector for cone positioning
      local dirX = math.cos(angle)
      local dirY = math.sin(angle)

      -- Distance to place cone in front of car
      local lightDistance = 50

      -- Calculate cone tip position in front of car based on heading
      local tipX = camera.pos.x + (playerX + dirX * lightDistance) * camera.zoom
      local tipY = camera.pos.y + (playerY + dirY * lightDistance) * camera.zoom

      -- Cone dimensions
      local coneLength = 60 * camera.zoom
      local coneWidth = 55 * camera.zoom

      -- Calculate perpendicular vector for cone base
      local perpX = -dirY
      local perpY = dirX

      -- Base of cone extends further in heading direction from tip
      local baseX = tipX + dirX * coneLength
      local baseY = tipY + dirY * coneLength

      -- Cone tip width (small rectangle at the tip)
      local tipWidth = 20 * camera.zoom

      -- Tip corners (small rectangle at car end)
      local tipCorner1X = tipX + perpX * tipWidth / 2
      local tipCorner1Y = tipY + perpY * tipWidth / 2
      local tipCorner2X = tipX - perpX * tipWidth / 2
      local tipCorner2Y = tipY - perpY * tipWidth / 2

      -- Base corners (wide end of trapezoid)
      local baseCorner1X = baseX + perpX * coneWidth / 2
      local baseCorner1Y = baseY + perpY * coneWidth / 2
      local baseCorner2X = baseX - perpX * coneWidth / 2
      local baseCorner2Y = baseY - perpY * coneWidth / 2
      -- Draw trapezoid (4 vertices: tip rectangle + base rectangle)
      love.graphics.polygon("fill",
        tipCorner1X, tipCorner1Y,           -- tip corner 1
        baseCorner1X, baseCorner1Y,         -- base corner 1
        baseCorner2X, baseCorner2Y,         -- base corner 2
        tipCorner2X, tipCorner2Y)           -- tip corner 2

      love.graphics.setColor(1, 1, 1, 1)
    end)

    love.graphics.pop()
  end
end

return light
