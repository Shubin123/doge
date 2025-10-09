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

function light.draw()
  --   blueNeon(function()
  --     love.graphics.setColor(0.17, 0.46, 1)

  --     -- Get car position and velocity
  --     local carX = player.body:getX()
  --     local carY = player.body:getY()
  --     local velX, velY = player.body:getLinearVelocity()

  --     -- Calculate car's heading angle using the same logic as getSpriteForHeading
  --     local angle = 0
  --     if math.abs(velX) > 0.1 or math.abs(velY) > 0.1 then
  --         angle = math.atan2(velY, velX)
  --     end

  --     -- Convert angle to direction vector for cone positioning
  --     local dirX = math.cos(angle)
  --     local dirY = math.sin(angle)

  --     -- Distance to place cone in front of car
  --     local lightDistance = 50

  --     -- Calculate cone tip position in front of car based on heading
  --     local tipX = camera.pos.x + (carX + dirX * lightDistance) * camera.zoom
  --     local tipY = camera.pos.y + (carY + dirY * lightDistance) * camera.zoom

  --     -- Cone dimensions
  --     local coneLength = 100 * camera.zoom
  --     local coneWidth = 50 * camera.zoom

  --     -- Calculate perpendicular vector for cone base
  --     local perpX = -dirY
  --     local perpY = dirX

  --     -- Base of cone extends further in heading direction from tip
  --     local baseX = tipX + dirX * coneLength
  --     local baseY = tipY + dirY * coneLength

  --     -- Cone tip width (small rectangle at the tip)
  --     local tipWidth = 20 * camera.zoom

  --     -- Tip corners (small rectangle at car end)
  --     local tipCorner1X = tipX + perpX * tipWidth / 2
  --     local tipCorner1Y = tipY + perpY * tipWidth / 2
  --     local tipCorner2X = tipX - perpX * tipWidth / 2
  --     local tipCorner2Y = tipY - perpY * tipWidth / 2

  --     -- Base corners (wide end of trapezoid)
  --     local baseCorner1X = baseX + perpX * coneWidth / 2
  --     local baseCorner1Y = baseY + perpY * coneWidth / 2
  --     local baseCorner2X = baseX - perpX * coneWidth / 2
  --     local baseCorner2Y = baseY - perpY * coneWidth / 2

  --     -- Draw trapezoid (4 vertices: tip rectangle + base rectangle)
  --     love.graphics.polygon("fill",
  --         tipCorner1X, tipCorner1Y,    -- tip corner 1
  --         baseCorner1X, baseCorner1Y,  -- base corner 1
  --         baseCorner2X, baseCorner2Y,  -- base corner 2
  --         tipCorner2X, tipCorner2Y)    -- tip corner 2

  --     love.graphics.setColor(1, 1, 1, 1)
  -- end)

  yellowNeon(function()
    love.graphics.setColor(1, 0.46, 0.3, var.indoors and 1 or 0)
    -- local mx = player.body:getX() + 20*math.sin(fire.t)
    -- local my = player.body:getY() + 20*math.cos(fire.t)

    local mx = 500 - 2
    local my = 300 - 25




    love.graphics.circle("fill", (camera.pos.x + (mx) * camera.zoom), (camera.pos.y + (my) * camera.zoom), 8 *
    camera.zoom)

    -- love.graphics.setColor(1,1,1,1)
  end)

--   yellowNeon(function()
--     love.graphics.setColor(1, 0.46, 0.3, var.indoors and 0.8 or 0)
    
--     local mx = 500 - 2
--     local my = 300 - 25
    
--     -- Transform coordinates for camera
--     local screenX = camera.pos.x + mx * camera.zoom
--     local screenY = camera.pos.y + my * camera.zoom
    
--     -- God rays parameters
--     local numRays = 8  -- Number of rays
--     local rayLength = 120 * camera.zoom  -- Length of each ray
--     local rayWidth = 15 * camera.zoom    -- Width at the base of rays
--     local raySpread = math.pi * 0.6      -- Spread angle of the rays (in radians)
--     local startAngle = -math.pi/2 - raySpread/2  -- Start angle (pointing downward)
    
--     -- Optional: Add some subtle animation
--     local time = love.timer.getTime()
--     local flicker = 0.9 + 0.1 * math.sin(time * 2)
    
--     -- Draw each god ray
--     for i = 0, numRays - 1 do
--         local angle = startAngle + (raySpread * i / (numRays - 1))
        
--         -- Add slight randomness to each ray for more natural look
--         local rayLengthVariation = rayLength * (0.8 + 0.4 * math.sin(time * 0.5 + i))
        
--         -- Calculate ray endpoints
--         local endX = screenX + math.cos(angle) * rayLengthVariation
--         local endY = screenY + math.sin(angle) * rayLengthVariation
        
--         -- Create trapezoid shape for the ray
--         local halfWidth = rayWidth * 0.5
--         local taperedWidth = rayWidth * 0.1  -- Ray gets thinner at the end
        
--         -- Calculate perpendicular vectors for ray width
--         local perpX = -math.sin(angle)
--         local perpY = math.cos(angle)
        
--         -- Ray vertices (trapezoid)
--         local vertices = {
--             screenX - perpX * halfWidth, screenY - perpY * halfWidth,  -- Base left
--             screenX + perpX * halfWidth, screenY + perpY * halfWidth,  -- Base right
--             endX + perpX * taperedWidth, endY + perpY * taperedWidth,  -- End right
--             endX - perpX * taperedWidth, endY - perpY * taperedWidth   -- End left
--         }
        
--         -- Set opacity with flicker effect
--         love.graphics.setColor(1, 0.46, 0.3, (var.indoors and 0.3 or 0) * flicker)
--         love.graphics.polygon("fill", vertices)
        
--         -- Optional: Add a brighter center line for each ray
--         love.graphics.setColor(1, 0.6, 0.4, (var.indoors and 0.5 or 0) * flicker)
--         love.graphics.setLineWidth(2 * camera.zoom)
--         love.graphics.line(screenX, screenY, endX, endY)
--     end
    
--     -- Optional: Add a bright source point at the window/ceiling
--     love.graphics.setColor(1, 0.7, 0.5, var.indoors and 0.8 or 0)
--     love.graphics.circle("fill", screenX, screenY, 4 * camera.zoom)
    
--     -- Reset line width
--     love.graphics.setLineWidth(1)
-- end)
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

      -- Get car position and velocity
      local playerX, playerY = player.body:getPosition()
      
      -- local targetVelX, targetVelY = gun.lastAimDirection.x, gun.lastAimDirection.y
      -- local velX, velY = player.body:getLinearVelocity()
      -- local velX, velY = gun.lastAimDirection.x,  gun.lastAimDirection.y

      -- if playerVX > 20 or playerVY > 20 then

      --   -- velX, velY = playerVX , playerVY
      --      velX, velY = mymath.lerpVec2({velX, velY}, {playerVX, playerVY}, 0.1)

      -- end

      -- gun.currentVel = gun.currentVel or { x = gun.lastAimDirection.x, y = gun.lastAimDirection.y }

      -- Then in your update code:


local velX, velY = gun.currentVel.x, gun.currentVel.y

      -- Calculate car's heading angle using the same logic as getSpriteForHeading
      local angle = 0
      if math.abs(velX) > 0.1 or math.abs(velY) > 0.1 then
        angle = math.atan2(velY, velX)
      end

      -- Convert angle to direction vector for cone positioning
      -- local dirX = math.cos(angle)
      -- local dirY = math.sin(angle)
      -- print(gun.lastAimDirection.x)
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
      -- light.x,light.y =baseX,baseY
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
