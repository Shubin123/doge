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

  -- (pixelNeon and pixelate chains removed: never drawn, but each held two or
  -- three screen-sized canvases of VRAM.)

  light.passBreak = love.graphics.newCanvas(1, 1) -- see light.skipChain
  light.beamImage = light.newBeamImage()
end

-- A glow chain given nothing visible to draw adds exactly nothing to
-- scene_canvas (measured: no pixel changes), yet costs eight full-screen
-- passes, so callers skip it with light.skipChain(), which keeps the chain's
-- other effects:
--   * scene_canvas is left bound, and the blend mode's alpha mode is back at
--     its default (moonshine's chain.draw restores only the mode name);
--   * scene_canvas's render pass is ended. The chain renders to its own
--     canvases, which ends the pass, and that is not neutral: blending into
--     the rgba4 scene_canvas rounds differently across a pass boundary on some
--     GPUs (Apple's tile memory), so draws after it land 1/15 apart. Ending the
--     pass with a 1x1 clear instead keeps every later pixel bit-identical.
function light.skipChain()
  love.graphics.setCanvas(light.passBreak)
  love.graphics.clear()
  love.graphics.setCanvas(scene_canvas)
  love.graphics.setBlendMode((love.graphics.getBlendMode()))
end

-- Indoor key light: a soft warm glow rendered through the godray/glow chain.
-- Only visible while indoors (outdoors it is drawn with alpha 0).
function light.draw()
  if not var.indoors then
    light.skipChain()
    return
  end
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

-- The flashlight's heading: the gun's current velocity, else to the right.
local function aim()
  local velX, velY = gun.currentVel.x, gun.currentVel.y
  if math.abs(velX) > 0.1 or math.abs(velY) > 0.1 then
    return math.atan2(velY, velX)
  end
  return 0
end

-- The beam on the ground: lights strung out ahead of the player, each further
-- one wider and dimmer, so the floor (and puddles, grass, anyone standing in
-- it) is lit in a widening pool through the same shaders as every other light.
-- { distance ahead, range, intensity }
local BEAM = {
  { 60, 60, 0.9 },
  { 130, 85, 0.75 },
  { 205, 110, 0.6 },
  { 285, 135, 0.45 },
}

-- The beam's pool of light on the floor: points along +x from its middle
-- left edge, brightest a little way out and fading to its far end and its
-- sides. Its strength is in rgb and alpha 0, so drawn with ("add",
-- "premultiplied") it brightens the ground and leaves the scene's alpha (what
-- the GI pass reads as walls) alone.
local BEAM_LENGTH = 320 -- px
local BEAM_WIDTH = 260  -- px across at the far end
local BEAM_COLOR = { 0.55, 0.68, 0.85 }

function light.newBeamImage()
  local w, h = 128, 64
  local data = love.image.newImageData(w, h)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local u = (x + 0.5) / w
      local v = math.abs((y + 0.5) / h * 2 - 1)
      local side = 1 - math.min(1, math.max(0, (v / u - 0.55) / 0.45)) -- soft cone edge
      local along = math.min(1, u / 0.12) * (1 - u) ^ 1.4
      local f = side * side * along * 1.6
      data:setPixel(x, y, f, f, f, 0)
    end
  end
  return love.graphics.newImage(data)
end

--- The flashlight's pool on the ground, under the camera transform, over the
--- floor and grass and under the sprites standing in it.
function light.drawBeam()
  if not player.lightsOn then return end
  local px, py = player.body:getPosition()
  local w, h = light.beamImage:getDimensions()
  local shader = love.graphics.getShader()
  local mode, alphaMode = love.graphics.getBlendMode()
  love.graphics.setShader()
  love.graphics.setBlendMode("add", "premultiplied")
  love.graphics.setColor(BEAM_COLOR[1], BEAM_COLOR[2], BEAM_COLOR[3], 1)
  love.graphics.draw(light.beamImage, px, py, aim(), BEAM_LENGTH / w, BEAM_WIDTH / h, 0, h / 2)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setBlendMode(mode, alphaMode)
  love.graphics.setShader(shader)
end

-- Before the lighting upload (shadow.update)
function light.update(dt)
  if not player.lightsOn then return end
  local px, py = player.body:getPosition()
  local angle = aim()
  local dx, dy = math.cos(angle), math.sin(angle)
  for _, b in ipairs(BEAM) do
    shadow.addTransientLight(px + dx * b[1], py + dy * b[1], b[3], b[2])
  end
end

function light.populate()
  table.insert(dynamic_draw_list, {
    sort_y = player.body:getY() + 100,
    x = 0,
    y = 0,
    draw_type = "light"
  })
end

-- The flashlight cone, and any muzzle flashes, drawn through the blueNeon
-- glow so they read as soft light rather than flat shapes.
function light.renderLights(drawable)
  local flashes = bullet and #bullet.muzzleFlashes > 0
  if drawable.draw_type == "light" and (player.lightsOn or flashes) then
    love.graphics.push()

    love.graphics.reset()
    
    blueNeon(function()
      if player.lightsOn then
      love.graphics.setColor(0.17, 0.46, 1, 0.5)

      -- Aim the flashlight cone along the gun's current velocity/heading.
      local playerX, playerY = player.body:getPosition()
      local angle = aim()

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
      end

      if flashes then
        love.graphics.push()
        camera.apply()
        bullet.drawMuzzleFlashes()
        love.graphics.pop()
        love.graphics.setShader()
      end
    end)

    love.graphics.pop()
  end
end

return light
