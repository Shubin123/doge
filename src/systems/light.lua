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
  light.beamMesh = love.graphics.newMesh(light.RAYS + 1, "fan", "stream")
  light.beamMesh:setTexture(light.beamImage)
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

-- Union of two {x0, y0, x1, y1} rects (either may be nil)
function light.cover(a, b)
  if not a then return b end
  if not b then return a end
  return { math.min(a[1], b[1]), math.min(a[2], b[2]), math.max(a[3], b[3]), math.max(a[4], b[4]) }
end

-- {x0, y0, x1, y1} round points {x1, y1, x2, y2, ...}, m pixels out
function light.pointsBounds(points, m)
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for i = 1, #points - 1, 2 do
    x0, x1 = math.min(x0, points[i]), math.max(x1, points[i])
    y0, y1 = math.min(y0, points[i + 1]), math.max(y1, points[i + 1])
  end
  return { x0 - m, y0 - m, x1 + m, y1 + m }
end

-- Screen rect a love.graphics.line through points {x1, y1, x2, y2, ...} of
-- this width draws inside, for a glow chain's bounds; nil when it can't be
-- told. A miter join (the default) reaches half the width over sin(half the
-- corner's angle) from its point, which runs away as the line doubles back,
-- so a corner within ~0.1 degree of that, or a zero-length segment, gives
-- nil. Each point gets 1% and 3 px to spare (LOVE works it out in floats,
-- and a smooth line's edge is feathered).
function light.lineBounds(points, width)
  local n = #points / 2
  if n < 2 then return nil end
  local hw = width / 2
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for i = 1, n do
    local x, y = points[2 * i - 1], points[2 * i]
    local reach = hw
    if i > 1 then
      local sx, sy = x - points[2 * i - 3], y - points[2 * i - 2]
      local ls = math.sqrt(sx * sx + sy * sy)
      if ls == 0 then return nil end
      if i < n then
        local tx, ty = points[2 * i + 1] - x, points[2 * i + 2] - y
        local lt = math.sqrt(tx * tx + ty * ty)
        if lt == 0 then return nil end
        -- the corner's angle phi: sin(phi / 2)^2 = (1 + cos turn) / 2
        local half = (1 + (sx * tx + sy * ty) / (ls * lt)) / 2
        if half < 1e-6 then return nil end
        reach = hw / math.sqrt(half)
      end
    end
    reach = reach * 1.01 + 3
    x0, y0 = math.min(x0, x - reach), math.min(y0, y - reach)
    x1, y1 = math.max(x1, x + reach), math.max(y1, y + reach)
  end
  return { x0, y0, x1, y1 }
end

-- Indoor key light: a soft warm glow rendered through the godray/glow chain.
-- Only visible while indoors (outdoors it is drawn with alpha 0).
function light.draw()
  if not var.indoors then
    light.skipChain()
    return
  end
  -- local mx = player.body:getX() + 20*math.sin(fire.t)
  -- local my = player.body:getY() + 20*math.cos(fire.t)
  local mx = 500 - 2
  local my = 300 - 25
  local x, y, r = camera.pos.x + (mx) * camera.zoom, camera.pos.y + (my) * camera.zoom, 8 * camera.zoom
  yellowNeon(function()
    love.graphics.setColor(1, 0.46, 0.3, var.indoors and 1 or 0)
    love.graphics.circle("fill", x, y, r)
  end, { x - r - 2, y - r - 2, x + r + 2, y + r + 2 })
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

-- The beam stops at what stands in its way. It's cast as a fan of rays
-- across its width, each ending where it meets a wall, a building, a prop, a
-- pillar of the arch, the parked car or a tree's trunk: their footprints on
-- the ground, which is where the beam runs. The pool on the floor is drawn
-- out to where each ray ends, the lights strung along the beam stop at the
-- first thing its middle meets (the rest of its light lands on that), and
-- the glow at the gun is cut short there too.
light.RAYS = 41
local SPREAD = math.rad(24) -- each side of the aim: the pool fades out by 22 degrees
local CENTER = (light.RAYS + 1) / 2
local WALL_GAP = 12         -- px short of what it hits, a light from the beam lands
-- what stops it, by the userData type of the fixtures in its way
local BLOCKS = { region = true, house = true, arch = true }

local rayCos, raySin = {}, {}
for i = 1, light.RAYS do
  local a = -SPREAD + 2 * SPREAD * (i - 1) / (light.RAYS - 1)
  rayCos[i], raySin[i] = math.cos(a), math.sin(a)
end

local reach = {}          -- px, how far each ray gets
local castX, castY, castAngle

local function blocks(fixture)
  if fixture:isSensor() then return false end
  local data = fixture:getUserData()
  if type(data) == "table" and BLOCKS[data.type] then return true end
  local body = fixture:getBody()
  for _, c in ipairs(car.cars or {}) do
    if c.body == body then return not c.inUse end
  end
  return false
end

local rayMax, rayHit
local function onRay(fixture, x, y, xn, yn, fraction)
  if not blocks(fixture) then return -1 end
  rayHit = math.min(rayHit, fraction * rayMax)
  return fraction -- only nearer ones from here
end

-- How far from (x, y) along (dx, dy) the beam gets, up to max
local function castRay(x, y, dx, dy, max)
  rayMax, rayHit = max, max
  world:rayCast(x, y, x + dx * max, y + dy * max, onRay)
  for _, tree in ipairs(map.treeInstances) do
    local t = tree.active and tree.trunk
    if t then
      local ox, oy = t.x - x, t.y - y
      local along = ox * dx + oy * dy
      local off2 = ox * ox + oy * oy - along * along
      if along > 0 and off2 < t.r * t.r then
        local enter = along - math.sqrt(t.r * t.r - off2)
        if enter >= 0 then rayHit = math.min(rayHit, enter) end
      end
    end
  end
  return rayHit
end

-- Cast the beam's rays from (x, y) aimed at angle, unless that's what was
-- cast last (light.update casts each frame; the two draws reuse it)
local function castBeam(x, y, angle)
  if x == castX and y == castY and angle == castAngle then return end
  castX, castY, castAngle = x, y, angle
  local dx, dy = math.cos(angle), math.sin(angle)
  for i = 1, light.RAYS do
    -- turned by the ray's angle off the aim; unblocked, out to the far end of the pool
    local rx, ry = dx * rayCos[i] - dy * raySin[i], dy * rayCos[i] + dx * raySin[i]
    reach[i] = castRay(x, y, rx, ry, BEAM_LENGTH / rayCos[i])
  end
end

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

local beamVertices = {}

--- The flashlight's pool on the ground, under the camera transform, over the
--- floor and grass and under the sprites standing in it: a fan out to where
--- each ray ends, textured as the pool would be there.
function light.drawBeam()
  if not player.lightsOn then return end
  local px, py = player.body:getPosition()
  local angle = aim()
  castBeam(px, py, angle)
  local dx, dy = math.cos(angle), math.sin(angle)
  beamVertices[1] = { px, py, 0, 0.5, 1, 1, 1, 1 }
  for i = 1, light.RAYS do
    -- along the aim and across it, and where that is in the pool's image
    local along, across = reach[i] * rayCos[i], reach[i] * raySin[i]
    beamVertices[i + 1] = { px + along * dx - across * dy, py + along * dy + across * dx,
      along / BEAM_LENGTH, 0.5 + across / BEAM_WIDTH, 1, 1, 1, 1 }
  end
  light.beamMesh:setVertices(beamVertices)
  local shader = love.graphics.getShader()
  local mode, alphaMode = love.graphics.getBlendMode()
  love.graphics.setShader()
  love.graphics.setBlendMode("add", "premultiplied")
  local k = daynight.glow() -- a flashlight hardly shows in daylight
  love.graphics.setColor(BEAM_COLOR[1] * k, BEAM_COLOR[2] * k, BEAM_COLOR[3] * k, 1)
  love.graphics.draw(light.beamMesh)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setBlendMode(mode, alphaMode)
  love.graphics.setShader(shader)
end

-- Before the lighting upload (shadow.update)
function light.update(dt)
  if not player.lightsOn then return end
  local px, py = player.body:getPosition()
  local angle = aim()
  castX = nil -- things move (the car): cast afresh each frame, the draws reuse it
  castBeam(px, py, angle)
  local dx, dy = math.cos(angle), math.sin(angle)
  local ahead = reach[CENTER]
  for _, b in ipairs(BEAM) do
    if b[1] < ahead then
      shadow.addTransientLight(px + dx * b[1], py + dy * b[1], b[3], b[2])
    else
      -- it lights what's in the way, and stops there
      local d = math.max(0, ahead - WALL_GAP)
      shadow.addTransientLight(px + dx * d, py + dy * d, b[3], b[2])
      break
    end
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

    -- The screen rect it all draws inside, so the chain only runs where the
    -- glow can reach (see moonshine's chain.draw)
    local bounds

    local cone
    if player.lightsOn then
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

      -- Cone dimensions, cut short by whatever the beam meets
      castBeam(playerX, playerY, angle)
      local length = math.min(60, reach[CENTER] - lightDistance)
      local coneLength = length * camera.zoom
      local coneWidth = (20 + 35 * length / 60) * camera.zoom

      -- Calculate perpendicular vector for cone base
      local perpX = -dirY
      local perpY = dirX

      -- Base of cone extends further in heading direction from tip
      local baseX = tipX + dirX * coneLength
      local baseY = tipY + dirY * coneLength

      -- Cone tip width (small rectangle at the tip)
      local tipWidth = 20 * camera.zoom

      -- Trapezoid: tip corners (small rectangle at car end), then the base
      -- corners (wide end)
      cone = {
        tipX + perpX * tipWidth / 2, tipY + perpY * tipWidth / 2,
        baseX + perpX * coneWidth / 2, baseY + perpY * coneWidth / 2,
        baseX - perpX * coneWidth / 2, baseY - perpY * coneWidth / 2,
        tipX - perpX * tipWidth / 2, tipY - perpY * tipWidth / 2,
      }
      bounds = light.pointsBounds(cone, 2)
      if length <= 0 then cone, bounds = nil, nil end -- right up against it
    end
    if flashes then
      local r = bullet.muzzleFlashBounds()
      bounds = light.cover(bounds, camera.screenRect(r[1], r[2], r[3], r[4]))
    end
    if not (cone or flashes) then
      love.graphics.pop()
      return
    end

    love.graphics.reset()
    
    blueNeon(function()
      if cone then
      love.graphics.setColor(0.17, 0.46, 1, 0.5 * daynight.glow())
      love.graphics.polygon("fill", cone)
      love.graphics.setColor(1, 1, 1, 1)
      end

      if flashes then
        love.graphics.push()
        camera.apply()
        bullet.drawMuzzleFlashes()
        love.graphics.pop()
        love.graphics.setShader()
      end
    end, bounds)

    love.graphics.pop()
  end
end

return light
