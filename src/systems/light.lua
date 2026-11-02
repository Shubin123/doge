local light = {}
local SHADOW_SHADER -- (with the beam, below)
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
  light.shadowShader = love.graphics.newShader(SHADOW_SHADER)
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

-- The beam stops at what stands in its way: where the buildings, walls and
-- props around meet the ground (their footprints, lib/graphics/footprint.lua;
-- the ground is where the beam runs), the arch's pillars, the tree's trunk,
-- the house's walls and the parked car (shadow.eachFoot). light.update
-- gathers the ones in its reach each frame as segments. The pool on the floor and the glow at the gun
-- are dark, pixel by pixel, wherever the line from the player crosses one
-- (SHADOW_SHADER), so shadows fit what casts them. The lights strung along
-- the beam fade out against what's in its way, their light landing on that,
-- and light nothing it can't see (shadow.setBeam: every lit shader leaves
-- them out past what's in the way), so none of it bleeds through.
local MAX_FEET = 64     -- segments, nearest first (SHADOW_SHADER's array, shadow.MAX_BEAM_FEET)
local SPREAD = math.rad(24) -- each side of the aim: the pool fades out by 22 degrees
local REACH = BEAM_LENGTH / math.cos(SPREAD) -- px, the furthest the pool gets
local WALL_GAP = 12     -- px short of what's in the way, a light from the beam lands
local WALL_FADE = 80    -- px further, and a light that was past it has gone
-- How far the beam's bright middle gets: rays this far off the aim (degrees)
local RAYS = { -12, -8, -4, 0, 4, 8, 12 }
local rayCos, raySin = {}, {}
for i, deg in ipairs(RAYS) do
  rayCos[i], raySin[i] = math.cos(math.rad(deg)), math.sin(math.rad(deg))
end

SHADOW_SHADER = [[
  #define MAX_FEET 64
  uniform int  numFeet;
  uniform vec4 feet[MAX_FEET]; // segments in its way, screen px
  uniform vec2 origin;         // where the beam starts, screen px

  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 screen_coords) {
    vec2 d = screen_coords - origin;
    for (int i = 0; i < MAX_FEET; i++) {
      if (i >= numFeet) break;
      vec2 a = feet[i].xy - origin;
      vec2 e = feet[i].zw - feet[i].xy;
      float den = d.x * e.y - d.y * e.x;
      if (abs(den) < 1e-6) continue; // running alongside it
      float t = (a.x * e.y - a.y * e.x) / den; // how far along the way here it's crossed
      float u = (a.x * d.y - a.y * d.x) / den; // and where along it
      if (t > 0.0 && t < 1.0 && u >= 0.0 && u <= 1.0) return vec4(0.0);
    }
    return Texel(tex, tc) * color;
  }
]]

local feet = {}       -- this frame's, world px: {x0, y0, x1, y1, ...}
local nearby = {}     -- scratch while gathering: {distance^2, x0, y0, x1, y1}
local screenFeet = {} -- feet on screen, for SHADOW_SHADER
local shadowed        -- whether this frame's draws go through it

-- Squared distance from (px, py) to the segment (x0, y0)-(x1, y1)
local function distance2(px, py, x0, y0, x1, y1)
  local ex, ey = x1 - x0, y1 - y0
  local len2 = ex * ex + ey * ey
  local t = len2 > 0 and math.max(0, math.min(1, ((px - x0) * ex + (py - y0) * ey) / len2)) or 0
  local dx, dy = x0 + ex * t - px, y0 + ey * t - py
  return dx * dx + dy * dy
end

-- The footprints ahead of (px, py) aimed at angle, nearest first, into feet:
-- the whole half round in front, as the lights along the beam spill wider
-- than it
local function gather(px, py, angle)
  local n = 0
  local dx, dy = math.cos(angle), math.sin(angle)
  local function add(x0, y0, x1, y1)
    if (x0 - px) * dx + (y0 - py) * dy < 0 and (x1 - px) * dx + (y1 - py) * dy < 0 then
      return -- behind
    end
    local d2 = distance2(px, py, x0, y0, x1, y1)
    if d2 < REACH * REACH then
      n = n + 1
      local f = nearby[n] or {}
      f[1], f[2], f[3], f[4], f[5] = d2, x0, y0, x1, y1
      nearby[n] = f
    end
  end
  shadow.eachFoot(px - REACH, py - REACH, px + REACH, py + REACH, px, py, add)
  for i = #nearby, n + 1, -1 do nearby[i] = nil end
  if n > MAX_FEET then
    table.sort(nearby, function(a, b) return a[1] < b[1] end)
  end
  local k = 0
  for i = 1, math.min(n, MAX_FEET) do
    local f = nearby[i]
    feet[k + 1], feet[k + 2], feet[k + 3], feet[k + 4] = f[2], f[3], f[4], f[5]
    k = k + 4
  end
  for i = #feet, k + 1, -1 do feet[i] = nil end
end

-- How far from (px, py) along (dx, dy) to the first of feet, up to max
local function cast(px, py, dx, dy, max)
  local best = max
  for i = 1, #feet, 4 do
    local ax, ay = feet[i] - px, feet[i + 1] - py
    local ex, ey = feet[i + 2] - feet[i], feet[i + 3] - feet[i + 1]
    local den = dx * ey - dy * ex
    if den ~= 0 then
      local t = (ax * ey - ay * ex) / den
      local u = (ax * dy - ay * dx) / den
      if t > 0 and t < best and u >= 0 and u <= 1 then best = t end
    end
  end
  return best
end

-- Hand this frame's feet to SHADOW_SHADER, on screen (under the camera
-- transform); whether there are any
local function sendFeet(px, py)
  local n = #feet / 4
  shadowed = n > 0
  if not shadowed then return false end
  for i = 1, n do
    local f = screenFeet[i] or {}
    f[1], f[2] = love.graphics.transformPoint(feet[4 * i - 3], feet[4 * i - 2])
    f[3], f[4] = love.graphics.transformPoint(feet[4 * i - 1], feet[4 * i])
    screenFeet[i] = f
  end
  for i = #screenFeet, n + 1, -1 do screenFeet[i] = nil end
  local shader = light.shadowShader
  shader:send("numFeet", n)
  shader:send("feet", unpack(screenFeet))
  shader:send("origin", { love.graphics.transformPoint(px, py) })
  return true
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

--- The flashlight's pool on the ground, under the camera transform, over the
--- floor and grass and under the sprites standing in it, dark behind what's
--- in its way.
function light.drawBeam()
  if not player.lightsOn then return end
  local px, py = player.body:getPosition()
  local w, h = light.beamImage:getDimensions()
  local shader = love.graphics.getShader()
  local mode, alphaMode = love.graphics.getBlendMode()
  love.graphics.setShader(sendFeet(px, py) and light.shadowShader or nil)
  love.graphics.setBlendMode("add", "premultiplied")
  local k = daynight.glow() -- a flashlight hardly shows in daylight
  love.graphics.setColor(BEAM_COLOR[1] * k, BEAM_COLOR[2] * k, BEAM_COLOR[3] * k, 1)
  love.graphics.draw(light.beamImage, px, py, aim(), BEAM_LENGTH / w, BEAM_WIDTH / h, 0, h / 2)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setBlendMode(mode, alphaMode)
  love.graphics.setShader(shader)
end

-- Before the lighting upload (shadow.update)
function light.update(dt)
  if not player.lightsOn then
    shadow.setBeam()
    return
  end
  local px, py = player.body:getPosition()
  local angle = aim()
  gather(px, py, angle) -- for the draws too
  shadow.setBeam(px, py, feet)
  local dx, dy = math.cos(angle), math.sin(angle)
  -- how far along the aim its bright middle gets, on average
  local ahead = 0
  for i = 1, #RAYS do
    local rx, ry = dx * rayCos[i] - dy * raySin[i], dy * rayCos[i] + dx * raySin[i]
    ahead = ahead + cast(px, py, rx, ry, BEAM_LENGTH / rayCos[i]) * rayCos[i]
  end
  local stop = ahead / #RAYS - WALL_GAP
  for _, b in ipairs(BEAM) do
    local d, k = b[1], 1
    if d > stop then
      -- it lands on what's in the way, the less the further past it it was
      d, k = math.max(0, stop), 1 - (d - stop) / WALL_FADE
    end
    if k > 0 then
      shadow.addTransientLight(px + dx * d, py + dy * d, b[3] * k, b[2], true)
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

      -- Trapezoid: tip corners (small rectangle at car end), then the base
      -- corners (wide end)
      cone = {
        tipX + perpX * tipWidth / 2, tipY + perpY * tipWidth / 2,
        baseX + perpX * coneWidth / 2, baseY + perpY * coneWidth / 2,
        baseX - perpX * coneWidth / 2, baseY - perpY * coneWidth / 2,
        tipX - perpX * tipWidth / 2, tipY - perpY * tipWidth / 2,
      }
      bounds = light.pointsBounds(cone, 2)
    end
    if flashes then
      local r = bullet.muzzleFlashBounds()
      bounds = light.cover(bounds, camera.screenRect(r[1], r[2], r[3], r[4]))
    end

    love.graphics.reset()
    
    blueNeon(function()
      if cone then
      -- dark behind what's in the way, like the pool (feet sent by light.drawBeam)
      if shadowed then love.graphics.setShader(light.shadowShader) end
      love.graphics.setColor(0.17, 0.46, 1, 0.5 * daynight.glow())
      love.graphics.polygon("fill", cone)
      love.graphics.setColor(1, 1, 1, 1)
      if shadowed then love.graphics.setShader() end
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
