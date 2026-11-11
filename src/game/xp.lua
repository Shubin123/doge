--[[
  XP gems: what a kill leaves behind (xp.drop, from dying enemies and bosses;
  nothing else makes them, so none lie about a new map). Each is a chip of
  prismatic crystal on the ground (coin_bods, one sensor body each, group
  collision.groups.coin), which drifts to the player once they're close.
  Walking into one adds its value to var.player_score, which fills the HUD's
  XP bar (see collision.lua's player/coin response). Gems that touch merge,
  the bigger one carrying both values, and what a gem's worth sets its size
  (TIERS).

  The stones are cut at load rather than drawn: each is a ball sliced by uneven
  planes (cutStone) and ray-cast a texel at a time (bakeStone), so the outline
  comes out lopsided and every facet has an exact normal, in normalmap.lua's
  encoding. The art's channels aren't colours: red and green seed the hue of
  the facet in front and the one behind it, blue is how thick the stone is
  there, and alpha is 1, or 0.75 along a cut line.

  GEM_SHADER makes the colour: a spectrum that runs across the facets with
  their angle and with where the gem is on screen (so it shifts as you walk
  round it), lit by the scene's lights through the normal map, each facet
  flashing white as the stone's slow sway turns it to mirror a light. It's
  see-through, drawn with alpha writes off so it's never a wall to the GI
  (which reads the scene's alpha); its colour is scaled as low props' are, for
  the composite's divide by the ground's alpha.
]]
local xp = {}

local normalmap = require("lib.graphics.normalmap")

local MAGNET_RANGE = 96  -- px: gems this close drift to the player
local MAGNET_SPEED = 260 -- px/s at the player, slower further out
local ENEMY_VALUE = { 9, 15 } -- XP an enemy's gem is worth, least and most
local HOP_TIME, HOP_HEIGHT = 0.35, 14 -- a fresh gem's toss: seconds, px
local GROUND_ALPHA = 0.4 -- the map's ground alpha (draw.lua)
local CUTS = 6           -- different stones of each size
local PROBE = 20         -- samples each way from the middle, measuring a stone

-- What a gem's worth makes it: from this much XP up, this tall (texels), and
-- how far its glow reaches (px)
local TIERS = {
    { worth = 0, height = 11, glow = 16 },
    { worth = 8, height = 15, glow = 20 },
    { worth = 25, height = 21, glow = 28 },
    { worth = 80, height = 29, glow = 40 },
}

local GEM_SHADER = [[
    #define MAX_LIGHTS 64
    uniform int   numLights;
    uniform vec4  lights[MAX_LIGHTS]; // (x, y, intensity, range) in screen px
    uniform float u_ambient;

    uniform Image normalMap;
    uniform float baseY;       // its ground line, screen px
    uniform float lightHeight; // the lights' height, screen px
    uniform float zoom;
    uniform float groundAlpha;
    uniform float daylight;    // 0 night .. 1 day (systems/daynight.lua)
    uniform float time;
    uniform float phase;       // staggers one gem from the next

    const float BODY_ALPHA = 0.5;  // how much of it there is where it's thick
    const float RIM_ALPHA = 0.85;  // and at its thin edges
    const float EMBER = 0.5;       // how much of it shows however dark it is
    const float GLINT_POWER = 24.0;
    const float SWAY = 0.3;

    vec3 spectrum(float h) {
        return 0.5 + 0.5 * cos(6.28318531 * (h + vec3(0.0, 0.33, 0.67)));
    }

    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 screen_coords) {
        vec4 texel = Texel(tex, tc);
        if (texel.a < 0.5) discard;
        vec3 n = faceNormal(normalMap, tc);

        // the stone sways a little, so its facets catch the light in turn
        float sway = sin(time * 1.3 + phase) * SWAY;
        vec3 turned = normalize(vec3(n.x + n.z * sway, n.y, n.z - n.x * sway));
        vec3 mirrored = reflect(vec3(0.0, 0.0, -1.0), turned);

        // lit as the object shader lights an upright thing, standing on baseY
        vec2 ground = vec2(screen_coords.x, baseY);
        vec2 through = faceGround(ground, n, FACE_GAP * zoom);
        float zs = max(0.0, baseY - screen_coords.y);
        float ambient = ((u_ambient > 0.0) ? u_ambient : 0.20) * skyShade(n);
        float glint = pow(max(dot(mirrored, SKY), 0.0), GLINT_POWER) * ambient;
        float totalLight = 0.0;
        float beam = -1.0; // beamReaches(through), once a beam light needs it
        for (int i = 0; i < MAX_LIGHTS; i++) {
            if (i >= numLights) break;
            float range = lightRange(lights[i]);
            if (range <= 0.0) continue;
            vec3 toLight = vec3(lights[i].xy - ground, lightHeightOf(i, lightHeight) - zs);
            float dist = length(toLight);
            if (dist >= range) continue;
            float att = 1.0 - dist / range;
            att = att * att * lights[i].z * reaches(i, lights[i], range, through, beam);
            totalLight += att * faceShade(n, toLight);
            vec3 d = vec3(toLight.x, toLight.z, toLight.y) / max(dist, 0.001);
            glint += att * pow(max(dot(mirrored, d), 0.0), GLINT_POWER);
        }

        // the facet in front, the one behind it, and the angle it's seen at
        float hue = texel.r * 0.35 + texel.g * 0.25 + turned.x * 0.45 - turned.y * 0.2
                  + time * 0.07 + phase + screen_coords.x / (320.0 * zoom);
        vec3 body = mix(vec3(0.82), spectrum(hue), 0.85) * mix(0.78, 1.15, texel.r);
        body *= max(min(1.0, ambient + totalLight), EMBER);
        if (texel.a < 0.9) body = mix(body, vec3(1.0), 0.35); // a cut line catches the light

        float sparkle = min(1.0, glint);
        float alpha = max(mix(RIM_ALPHA, BODY_ALPHA, texel.b), sparkle);
        vec3 rgb = mix(body, vec3(1.0), sparkle);
        // as low props: night shows it as drawn, day divides it by the ground's alpha
        return vec4(rgb * groundAlpha / mix(groundAlpha, 1.0, daylight), alpha);
    }
]]

local gemShader, sheet, sheetNormals
local sprites = {}  -- by index: (tier - 1) * CUTS + cut
local pending = {}  -- drops waiting for xp.update, out of the physics step
local shown = {}    -- this frame's draw-list entries, for xp.drawGlow
local rng
local haloImage, haloBatch
local pulled = setmetatable({}, { __mode = "k" }) -- bodies the player is drawing in

local function hosting()
    return not var.multiplayer or var.multiplayer == 1
end

-- The planes that cut a stone, each a * p <= d in the sprite's frame (x right,
-- y up, z toward the viewer), a ball of radius about 1 before them: spread
-- evenly round it, each cut to its own depth, and the whole thing narrowed
-- and leaned a little, so no two are alike and none is symmetrical.
local function cutStone(random, facets)
    local wide, tall = 0.72 + random:random() * 0.28, 1.05 + random:random() * 0.3
    local lean = (random:random() - 0.5) * 0.45
    local planes = {}
    for i = 1, facets do
        local y = 1 - (i - 0.5) / facets * 2 + (random:random() - 0.5) * 0.25
        y = math.max(-1, math.min(1, y))
        local r = math.sqrt(1 - y * y)
        local a = i * 2.39996 + random:random() * 0.9 -- (the golden angle, jittered)
        local nx, nz = math.cos(a) * r, math.sin(a) * r
        local ax, ay = nx / wide, y / tall - nx * lean / wide
        local len = math.sqrt(ax * ax + ay * ay + nz * nz)
        planes[i] = {
            x = ax, y = ay, z = nz, d = 0.62 + random:random() * 0.38,
            nx = ax / len, ny = ay / len, nz = nz / len,
            hue = random:random(),
        }
    end
    return planes
end

-- Along the line of sight through (px, py): the facets it enters and leaves
-- the stone by and how far apart they are, or nothing if it misses
local function trace(planes, px, py)
    local near, far, front, back = math.huge, -math.huge, nil, nil
    for i = 1, #planes do
        local p = planes[i]
        local room = p.d - p.x * px - p.y * py
        if p.z > 0.001 then
            local z = room / p.z
            if z < near then near, front = z, p end
        elseif p.z < -0.001 then
            local z = room / p.z
            if z > far then far, back = z, p end
        elseif room < 0 then
            return
        end
    end
    if front and back and far <= near then return front, back, near - far end
end

-- One stone into its cell of the sheets, at (ox, oy); returns the row just
-- under its lowest texel
local function bakeStone(art, normals, planes, ox, oy, tier)
    -- First how big it came out, to fit it to the height it's meant to be
    local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
    for j = -PROBE, PROBE do
        for i = -PROBE, PROBE do
            local px, py = i / PROBE * 2.5, j / PROBE * 2.5
            if trace(planes, px, py) then
                x0, x1 = math.min(x0, px), math.max(x1, px)
                y0, y1 = math.min(y0, py), math.max(y1, py)
            end
        end
    end
    local scale = (tier.height - 1) / (y1 - y0)
    local midX = (x0 + x1) / 2
    local cell = tier.cell

    local hits, thickest, bottom = {}, 0.001, 0
    for row = 0, cell - 1 do
        for col = 0, cell - 1 do
            local front, back, depth = trace(planes, (col + 0.5 - cell / 2) / scale + midX,
                y1 - (row - 0.5) / scale)
            if front then
                hits[row * cell + col] = { front = front, back = back, depth = depth }
                thickest = math.max(thickest, depth)
                bottom = math.max(bottom, row + 1)
            end
        end
    end
    for key, hit in pairs(hits) do
        local row, col = math.floor(key / cell), key % cell
        -- a cut line runs where the next texel across or down is another facet
        local right = col < cell - 1 and hits[key + 1]
        local below = hits[key + cell]
        local line = (right and right.front ~= hit.front) or (below and below.front ~= hit.front)
        local x, y = ox + col, oy + row
        art:setPixel(x, y, hit.front.hue, hit.back.hue, hit.depth / thickest, line and 0.75 or 1)
        normals:setPixel(x, y, hit.front.nx * 0.5 + 0.5, hit.front.ny * 0.5 + 0.5, hit.front.nz * 0.5 + 0.5, 1)
    end
    return bottom
end

-- Every stone, a row of cuts per tier, on one sheet and its normal map
local function bakeSheet()
    local w, h = 0, 0
    for _, tier in ipairs(TIERS) do
        tier.cell = math.ceil(tier.height * 1.6) + 2
        w, h = math.max(w, tier.cell * CUTS), h + tier.cell
    end
    local art = love.image.newImageData(w, h)
    local normals = love.image.newImageData(w, h)
    local top = 0
    for t, tier in ipairs(TIERS) do
        for cut = 1, CUTS do
            local random = love.math.newRandomGenerator(t * 1000 + cut)
            local ox = (cut - 1) * tier.cell
            local foot = bakeStone(art, normals, cutStone(random, 8 + 3 * t), ox, top, tier)
            sprites[(t - 1) * CUTS + cut] = {
                quad = love.graphics.newQuad(ox, top, tier.cell, tier.cell, w, h),
                cell = tier.cell, foot = foot, glow = tier.glow,
            }
        end
        top = top + tier.cell
    end
    sheet = love.graphics.newImage(art)
    sheetNormals = love.graphics.newImage(normals)
    sheet:setFilter("nearest", "nearest")
    sheetNormals:setFilter("nearest", "nearest")
end

-- A soft spot, its strength in rgb and alpha 0: drawn with ("add",
-- "premultiplied") it brightens what's under it and leaves the scene's alpha
-- (what the GI pass reads as walls) alone.
local function newHaloImage()
    local n = 32
    local data = love.image.newImageData(n, n)
    for y = 0, n - 1 do
        for x = 0, n - 1 do
            local d = math.min(1, math.sqrt((x + 0.5 - n / 2) ^ 2 + (y + 0.5 - n / 2) ^ 2) / (n / 2))
            local f = (1 - d) ^ 2
            data:setPixel(x, y, f, f, f, 0)
        end
    end
    return love.graphics.newImage(data)
end

function xp.load()
    gemShader = love.graphics.newShader(normalmap.GLSL .. shadow.REACH_GLSL .. GEM_SHADER)
    gemShader:send("groundAlpha", GROUND_ALPHA)
    bakeSheet()
    haloImage = newHaloImage()
    xp.haloImage = haloImage -- (items on the ground glow with it too, game/inventory.lua)
    haloBatch = love.graphics.newSpriteBatch(haloImage, 512, "stream")
    rng = love.math.newRandomGenerator(love.math.random(0, 2 ^ 31 - 1))
    xp.time = 0
end

--- A gem worth `value` XP (nil: what an enemy's is worth) lands at (x, y).
--- Host and single player; safe in the physics step, it's made in xp.update.
function xp.drop(x, y, value)
    if not hosting() then return end
    pending[#pending + 1] = { x, y, value or rng:random(ENEMY_VALUE[1], ENEMY_VALUE[2]) }
end

-- Every gem drifts toward the player once it's in range, faster the closer
-- it gets, so it slides in and is picked up.
function xp.update(dt)
    xp.time = xp.time + dt
    for i = #pending, 1, -1 do
        local g = pending[i]
        pending[i] = nil
        local _, fixture = createCoin(g[1], g[2])
        fixture:setUserData({ value = g[3], cut = rng:random(CUTS), born = xp.time })
        var.num_coins = var.num_coins + 1
    end
    if not (player and player.body) then return end
    local px, py = player.body:getPosition()
    for i = 1, #coin_bods do
        local body = coin_bods[i]
        local x, y = body:getPosition()
        local dx, dy = px - x, py - y
        if math.abs(dx) < MAGNET_RANGE and math.abs(dy) < MAGNET_RANGE then
            local d = math.sqrt(dx * dx + dy * dy)
            if d < MAGNET_RANGE and d > 1 then
                local speed = MAGNET_SPEED * (1 - d / MAGNET_RANGE * 0.7)
                body:setLinearVelocity(dx / d * speed, dy / d * speed)
                pulled[body] = true
            end
        elseif pulled[body] then
            body:setLinearVelocity(0, 0) -- you got away: it settles where it is
            pulled[body] = nil
        end
    end
end

-- A gem's place on the sheet, from its fixture's user data
local function spriteOf(data)
    local value = data and data.value or 1
    local t = 1
    for i = 2, #TIERS do
        if value >= TIERS[i].worth then t = i end
    end
    return (t - 1) * CUTS + (data and data.cut or 1)
end

-- How high a fresh gem is in its toss
local function lift(data)
    local age = data and data.born and xp.time - data.born or HOP_TIME
    if age >= HOP_TIME then return 0 end
    return math.sin(age / HOP_TIME * math.pi) * HOP_HEIGHT
end

-- This frame's uniforms for the gems' shader
local function prepare()
    gemShader:send("time", xp.time)
    gemShader:send("zoom", camera.zoom)
    gemShader:send("lightHeight", shadow.LIGHT_HEIGHT * camera.zoom)
    gemShader:send("daylight", daynight.daylight())
    gemShader:send("normalMap", var.normal_maps and sheetNormals or normalmap.flat()) -- (Settings > Normal Maps)
    shadow.sendLights(gemShader)
end

-- Draw-list entry for a gem lying at (x, y), `height` px up in its toss
local function addGem(x, y, index, height)
    local entry = {
        sort_y = y + 100,
        draw_type = "xpGem",
        x = x,
        y = y,
        height = height,
        sprite = sprites[index] or sprites[1],
        phase = index * 2.4,
    }
    dynamic_draw_list[#dynamic_draw_list + 1] = entry
    shown[#shown + 1] = entry
end

--- Add the gems on screen (this host's physics bodies) to the dynamic draw
--- list (under the camera transform: the world rect it shows, shake and all).
function xp.populate()
    if #coin_bods == 0 then return end
    prepare()
    local w, h = love.graphics.getDimensions()
    local x0, y0 = love.graphics.inverseTransformPoint(0, 0)
    local x1, y1 = love.graphics.inverseTransformPoint(w, h)
    for i = 1, #coin_bods do
        local body = coin_bods[i]
        local x, y = body:getPosition()
        if x + 48 > x0 and x - 48 < x1 and y + 48 > y0 and y - 48 < y1 then
            local data = body:getFixtures()[1]:getUserData()
            addGem(x, y, spriteOf(data), lift(data))
        end
    end
end

--- Host: every gem for the snapshot, flat to keep it small:
--- { x1, y1, sprite1, x2, ... } in whole px.
function xp.getNetworkData()
    local flat = {}
    for i = 1, #coin_bods do
        local body = coin_bods[i]
        local x, y = body:getPosition()
        local n = #flat
        flat[n + 1] = math.floor(x + 0.5)
        flat[n + 2] = math.floor(y + 0.5)
        flat[n + 3] = spriteOf(body:getFixtures()[1]:getUserData())
    end
    return flat
end

--- Client: add the host's gems (xp.getNetworkData) to the draw list.
function xp.populateNetworked(flat)
    if #flat == 0 then return end
    prepare()
    for i = 1, #flat - 2, 3 do
        addGem(flat[i], flat[i + 1], flat[i + 2], 0)
    end
end

--- One gem from the sorted list (lib/graphics/renderer.lua), under the camera
--- transform: its shadow on the ground, then the stone over it.
function xp.drawPiece(d)
    local keep = love.graphics.getShader()
    local mode, alphaMode = love.graphics.getBlendMode()
    local s = d.sprite
    love.graphics.setBlendMode("alpha")
    love.graphics.setColorMask(true, true, true, false) -- (the scene's alpha stays the ground's)

    love.graphics.setShader()
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.ellipse("fill", d.x, d.y, s.foot * 0.42, s.foot * 0.16, 12)

    love.graphics.setShader(gemShader)
    local zoom = camera.zoom
    local ground = d.y * zoom + camera.y
    local reach = s.cell / 2 * zoom
    local middle = d.x * zoom + camera.x
    shadow.cullLights(gemShader, middle - reach - 1, ground - 1, middle + reach + 1, ground + 1)
    gemShader:send("baseY", ground)
    gemShader:send("phase", d.phase)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(sheet, s.quad, d.x, d.y - d.height, 0, 1, 1, s.cell / 2, s.foot)

    love.graphics.setColorMask()
    love.graphics.setShader(keep)
    love.graphics.setBlendMode(mode, alphaMode)
end

--- A pool of coloured light on the ground under each gem on screen, over the
--- sorted sprites (under the camera transform), so they shine in the dark.
function xp.drawGlow()
    if #shown == 0 then return end
    haloBatch:clear()
    local k = 0.35 * daynight.glow()
    for i = #shown, 1, -1 do
        local g = shown[i]
        shown[i] = nil
        if haloBatch:getCount() < haloBatch:getBufferSize() then
            local radius = g.sprite.glow
            local hue = (g.phase + xp.time * 0.5) * 6.283
            haloBatch:setColor((0.5 + 0.5 * math.cos(hue)) * k, (0.5 + 0.5 * math.cos(hue + 2.07)) * k,
                (0.5 + 0.5 * math.cos(hue + 4.21)) * k, 1)
            haloBatch:add(g.x - radius, g.y - radius * 0.45, 0, radius * 2 / 32, radius * 0.9 / 32)
        end
    end
    local shader = love.graphics.getShader()
    local mode, alphaMode = love.graphics.getBlendMode()
    love.graphics.setShader()
    love.graphics.setBlendMode("add", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(haloBatch)
    love.graphics.setBlendMode(mode, alphaMode)
    love.graphics.setShader(shader)
end

return xp
