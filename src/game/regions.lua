--[[
  Regions: the far-off places the portal travels to (see game/portal.lua).

  Each region's art was cut from its own sprite sheet into gfx/regions/<id>.png,
  with every sprite's rect and category in gfx/regions/<id>.lua (and its ground
  textures in <id>_floor.png). At load each region is laid out procedurally from
  its seed, far east of the home map so nothing overlaps:
    - seamless ground: its floor textures fading into each other over a noise
      field, so there's no tile grid to see,
    - walls along the edge (a physics chain keeps everyone inside),
    - streets of facades with props and lamps in front, a landmark or two,
    - a pool, puddles and grass wherever a noise field puts them.
  Everything is lit by its height (see SPRITE_SHADER): tall things block light
  and are lit up their faces, things underfoot are part of the ground.
  The same seed gives the same layout, so every client in a multiplayer game
  agrees on it without sending anything.
]]
local regions = {}

local TILE = 128        -- world px each ground texture covers before it repeats
local W, H = 2560, 1920 -- region size, inside its walls
local SPACING = 20000   -- world px between region origins (home is around 0, 0)
local MARGIN = 512      -- ground past the walls, so the edge of the world never shows
local CELL = 16         -- occupancy grid cell, for keeping things apart
local TOP = 170         -- the top wall's base, below the region's top edge
local ROWS = { 0.25, 0.46, 0.67 } -- facade street baselines, as fractions of H
-- The draw list sorts characters by body y + characterAnimator.sortYOffset (130),
-- and their feet are ~25 px below the body: a sprite whose base is at world y
-- sorts with a character standing on that line.
local SORT_OFFSET = 105
local ALPHA = { "alpha" }
-- Cut-out sprites write their colour and their own alpha straight into the
-- scene, so each decides whether the GI pass sees it as a wall (alpha > 0.5)
local REPLACE = { "replace", "premultiplied" }
local GROUND_ALPHA = 0.4  -- the map's ground alpha (draw.lua): never blocks light
-- Buildings, walls, towers, landmarks, lamps and anything glowing block light
-- like a wall (and give off their colour); props only when they're over head
-- height. (A sprite's height is no guide below that: an isometric car's
-- includes its roof seen from above.)
local TALL = { facade = true, wall = true, tower = true, landmark = true, light = true }
local OCCLUDE_HEIGHT = 96 -- world px

regions.list = {
    {
        id = "home",
        name = "Courtyard",
        portal = { x = 290, y = 150 }, -- top left of the portal's 35 x 50 rect
    },
    {
        id = "wasteland",
        name = "Wasteland",
        seed = 1101,
        scale = 1,
        edge = { "jersey_a", "jersey_b", "slab_a", "slab_b", "slab_c", "slab_e", "fence_sheet",
            "fence_gate", "fence_iron_a", "fence_iron_b", "fence_rusty", "slab_graffiti_b", "slab_graffiti_e" },
        posts = { "pillar_block", "fire_escape" },
        facades = { "shop_a", "shop_b", "ruin_a", "brick_block", "corner_a", "corner_b", "corner_escape",
            "corner_c", "corner_d", "corner_e", "pillar_block", "scaffold_a", "scaffold_b", "fire_escape",
            "slab_graffiti_a", "slab_graffiti_c", "slab_graffiti_d", "slab_d" },
        landmarks = { "bus" },
        props = { "car_a", "car_b", "car_c", "bins", "hydrant_a", "hydrant_b", "jersey_fallen",
            "fence_broken", "fence_brick" },
        decor = { "rubble_a", "rubble_b", "rubble_c", "rubble_d", "rubble_e", "can_a", "can_b", "can_c",
            "can_d", "brick", "chainlink_a", "chainlink_b" },
        -- lying on the ground: walked over, drawn into the ground, never block light
        flat = { "rubble_a", "rubble_b", "rubble_c", "rubble_d", "rubble_e", "can_a", "can_b", "can_c",
            "can_d", "brick", "chainlink_a", "chainlink_b" },
        lights = {},
        portalLights = {},
        glows = {},
        grass = { patches = 14, tint = { 2.1, 0.62, 0.7 } }, -- dry, straw coloured
        puddles = 16,
    },
    {
        id = "castle",
        name = "Castle",
        seed = 2202,
        scale = 1,
        edge = { "wall_plain", "wall_crenel", "wall_crenel", "wall_crenel_narrow" },
        posts = { "round_tower", "round_tower_b", "banner_pillar" },
        facades = { "corner_brick", "blue_window", "blue_corner", "corner_hall", "corner_window_a",
            "corner_window_b", "corner_window_c", "corner_hall_windows", "gate_wall", "gothic_wall",
            "cell_wall", "great_gate", "dungeon_wall_a", "dungeon_wall_b", "ruin_wall", "ruin_windows",
            "tower_stair", "round_tower", "arch", "portcullis_arch" },
        landmarks = { "gatehouse", "stained_glass", "long_wall" },
        props = { "chest", "banner_blue", "banner_red", "column_a", "column_b", "column_c", "column_d",
            "column_e", "portcullis", "ice_barrier", "spiral_stair" },
        decor = { "coins", "rune_carpet" },
        flat = { "coins", "rune_carpet" },
        lights = { "brazier_a", "brazier_b", "brazier_c", "candelabra" },
        portalLights = { "brazier_b", "brazier_b" },
        glows = {},
        grass = { patches = 22, tint = { 0.85, 1.0, 0.85 } },
        puddles = 8,
    },
    {
        id = "neon",
        name = "Neon City",
        seed = 3303,
        scale = 0.8,
        edge = { "wall_cyan", "wall_pink_pipe", "wall_pipes", "wall_blue_neon", "wall_pink_neon",
            "wall_green_neon", "wall_vent", "wall_panel" },
        posts = { "lamp_a", "lamp_b", "terminal_b" },
        facades = { "tower_ramen", "tower_tech", "block_cyber", "block_glass", "spire", "tower_tech",
            "block_cyber", "block_glass" },
        landmarks = { "holo_big", "laser_fence" },
        props = { "trash_a", "trash_b", "terminal_a", "terminal_b", "terminal_c", "panel_box", "plant_a",
            "plant_b", "plant_c", "vent_box", "holo_cyan", "holo_purple", "holo_laser", "shutter",
            "holo_frame", "grate_fence", "net_fence", "jersey_striped", "blocks", "barrier_a", "barrier_b",
            "barrier_c", "barrier_hazard" },
        decor = { "sign_arrows", "sign_updown", "sign_triangle", "sign_bowl", "sign_ramen", "sign_cyber",
            "sign_kanji", "neon_bar_a", "neon_bar_b", "grate_a", "grate_b", "manhole", "rail", "laser_small" },
        flat = { "grate_a", "grate_b", "manhole", "rail" },
        lights = { "lamp_a", "lamp_b" },
        portalLights = { "lamp_a", "lamp_b" },
        glows = { sign_arrows = true, sign_updown = true, sign_triangle = true, sign_bowl = true,
            sign_ramen = true, sign_cyber = true, sign_kanji = true, neon_bar_a = true, neon_bar_b = true,
            holo_cyan = true, holo_purple = true, holo_laser = true, holo_big = true, laser_fence = true },
        grass = { patches = 6, tint = { 0.45, 0.85, 1.25 } }, -- a few verges, neon-lit
        puddles = 22,
    },
    {
        id = "sanctum",
        name = "Sanctum",
        seed = 4404,
        scale = 1,
        edge = { "glass_wall", "glass_panel", "door_wall_a", "door_wall_b", "door_wall_c", "curtain_wall" },
        posts = { "crystal_pillar_a", "crystal_pillar_b", "crystal_pillar_c", "crystal_pillar_d" },
        facades = { "cathedral_a", "cathedral_b", "cathedral_c", "dome_a", "dome_b", "dome_c", "dome_d",
            "chapel", "altar_a", "altar_b", "altar_c", "shrine_b", "curtain_arch_a", "curtain_arch_b",
            "curtain_arch_c", "rune_glass_c", "rune_glass_d", "rune_glass_e" },
        landmarks = { "cathedral_d", "pavilion" },
        props = { "angel", "angel_b", "stool_a", "stool_b", "table", "flowers_a", "flowers_b", "plant_a",
            "plant_b", "lectern", "bench", "rune_glass_a", "rune_glass_b", "spire_a", "spire_b" },
        decor = { "orb_a", "orb_b", "orb_c", "lotus_a", "lotus_b", "scroll_a", "scroll_b", "book",
            "sun_emblem" },
        flat = { "scroll_a", "scroll_b", "book", "sun_emblem" },
        lights = { "lantern_a", "lantern_b", "fountain", "urn", "shrine_a", "shrine_c" },
        portalLights = { "lantern_b", "lantern_b" },
        glows = { orb_a = true, orb_b = true, orb_c = true, lotus_a = true, lotus_b = true, sun_emblem = true },
        cellular = true, -- its marble swaps whole tiles, at the grout
        grass = { patches = 14, tint = { 1.0, 1.05, 0.75 } },
        puddles = 10,
    },
}

regions.current = regions.list[1]

--------------------------------------------------------------------------------
-- Occupancy grid: rects things were placed in, so nothing lands on anything else
--------------------------------------------------------------------------------

local function newGrid(r)
    return {
        x0 = r.ox - MARGIN,
        y0 = r.oy - MARGIN,
        cols = math.ceil((W + 2 * MARGIN) / CELL),
        rows = math.ceil((H + 2 * MARGIN) / CELL),
        cells = {},
    }
end

local function cellRange(g, x, y, w, h)
    local c0 = math.max(0, math.floor((x - g.x0) / CELL))
    local r0 = math.max(0, math.floor((y - g.y0) / CELL))
    local c1 = math.min(g.cols - 1, math.floor((x + w - g.x0) / CELL))
    local r1 = math.min(g.rows - 1, math.floor((y + h - g.y0) / CELL))
    return c0, r0, c1, r1
end

local function mark(g, x, y, w, h)
    local c0, r0, c1, r1 = cellRange(g, x, y, w, h)
    for row = r0, r1 do
        for col = c0, c1 do
            g.cells[row * g.cols + col] = true
        end
    end
end

local function isFree(g, x, y, w, h)
    local c0, r0, c1, r1 = cellRange(g, x, y, w, h)
    for row = r0, r1 do
        for col = c0, c1 do
            if g.cells[row * g.cols + col] then return false end
        end
    end
    return true
end

local function freeAt(g, x, y)
    local col = math.floor((x - g.x0) / CELL)
    local row = math.floor((y - g.y0) / CELL)
    return not g.cells[row * g.cols + col]
end

--------------------------------------------------------------------------------
-- Art
--------------------------------------------------------------------------------

-- Dark asphalt plates for the neon city, whose sheet has no floor: clean
-- plates and grimy ones, both tiling seamlessly (their seams fall every 64 px,
-- the grime is noise wrapped round a torus).
local function neonFloor()
    local size, layers = 128, 2
    local data = love.image.newImageData(size * layers, size)
    local rng = love.math.newRandomGenerator(77)
    local tau = 2 * math.pi
    for v = 0, layers - 1 do
        for y = 0, size - 1 do
            for x = 0, size - 1 do
                local g = 0.2 + rng:random() * 0.04
                if v == 1 then
                    local a, b = x / size * tau, y / size * tau
                    g = g * (0.6 + 0.45 * love.math.noise(math.cos(a) * 1.3, math.sin(a) * 1.3,
                        math.cos(b) * 1.3 + 7, math.sin(b) * 1.3 + 7))
                end
                local cr, cg, cb = g * 0.95, g, g * 1.25
                if x % 64 == 0 or y % 64 == 0 then
                    cr, cg, cb = cr * 0.55, cg * 0.55, cb * 0.6
                elseif x % 64 == 1 or y % 64 == 1 then
                    cr, cg, cb = cr * 1.3, cg * 1.3, cb * 1.3
                end
                if v == 0 and (x % 64 == 6 or x % 64 == 57) and (y % 64 == 6 or y % 64 == 57) then
                    cr, cg, cb = 0.42, 0.44, 0.5 -- rivets
                end
                data:setPixel(v * size + x, y, cr, cg, cb, 1)
            end
        end
    end
    return love.graphics.newImage(data), layers
end

-- The ground: one quad per region, textured in TILEs from the region's corner.
-- Each floor texture (side by side in the region's floor image, each tiling
-- seamlessly) repeats across it; the first covers everything and the others
-- fade in over it wherever a soft noise field is high, so no tile edge ever
-- shows. A tiled floor (cellular) swaps whole textures instead, at its grout.
-- Lit like the map, by the same lights (shadow.lua).
local GROUND_SHADER = [[
    #define MAX_LIGHTS 64
    uniform int   numLights;
    uniform vec4  lights[MAX_LIGHTS]; // (x, y, intensity, range) in screen px
    uniform float u_ambient;

    uniform float layers;   // floor textures in the image
    uniform float cellular; // 1: whole textures swap; 0: they blend
    uniform vec2  seed;

    float hash(vec2 p) {
        return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
    }

    float vnoise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
                   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
    }

    vec3 layer(Image floors, float k, vec2 uv) {
        return Texel(floors, vec2((k + fract(uv.x)) / layers, fract(uv.y))).rgb;
    }

    vec4 effect(vec4 color, Image floors, vec2 uv, vec2 screen_coords) {
        vec3 c = layer(floors, 0.0, uv);
        vec2 at = mix(uv, floor(uv) + 0.5, cellular);
        for (int k = 1; k < 4; k++) {
            float fk = float(k);
            if (fk >= layers) break;
            // two octaves, so the patches have ragged edges
            float n = vnoise(at * 0.3 + seed + fk * 17.31) * 0.7
                    + vnoise(at * 1.1 + seed - fk * 5.7) * 0.3;
            float w = mix(smoothstep(0.56, 0.66, n), step(0.6, n), cellular);
            c = mix(c, layer(floors, fk, uv), w);
        }
        // broad light and dark drifts, so the repeat doesn't read
        c *= 0.88 + 0.24 * vnoise(uv * 0.13 + seed.yx);

        float ambient = (u_ambient > 0.0) ? u_ambient : 0.20;
        float totalLight = 0.0;
        for (int i = 0; i < MAX_LIGHTS; i++) {
            if (i >= numLights) break;
            float range = lights[i].w;
            if (range <= 0.0) continue;
            float dist = distance(lights[i].xy, screen_coords);
            if (dist >= range) continue;
            float att = 1.0 - dist / range;
            totalLight += att * att * lights[i].z;
        }
        float lit = min(1.0, ambient + totalLight);
        return vec4(c * lit * color.rgb, color.a);
    }
]]
local groundShader

local function groundMesh(r)
    local x0, y0 = r.ox - MARGIN, r.oy - MARGIN
    local w, h = W + 2 * MARGIN, H + 2 * MARGIN
    local mesh = love.graphics.newMesh({
        { x0, y0, 0, 0 },
        { x0 + w, y0, w / TILE, 0 },
        { x0 + w, y0 + h, w / TILE, h / TILE },
        { x0, y0 + h, 0, h / TILE },
    }, "fan", "static")
    mesh:setTexture(r.floorImage)
    return mesh
end

-- Region sprites are lit as what they are: an upright thing is a face standing
-- on its base, not a picture lying on the ground. Each texel's height above
-- the base comes from its row (the sprite's base row in the atlas is packed
-- into the vertex colour's red and green bytes; blue holds flags), so
--   - a light's falloff runs from the point on the ground under the texel up
--     to it: a building's roof isn't lit by a lamp merely above it on screen,
--   - a light behind an upright face's base doesn't light it (faces look
--     toward the camera, +y),
--   - the foot of anything upright sits in a little contact shadow.
-- The alpha it writes decides what the GI pass makes of it (> 0.5: a wall
-- that blocks light and gives off its colour). Tall things do; low props
-- don't; flat things underfoot are drawn into the ground, as dim as it is.
-- Flags: 1 tall, 2 glass (blended with its own alpha), 4 flat.
local SPRITE_SHADER = [[
    #define MAX_LIGHTS 64
    uniform int   numLights;
    uniform vec4  lights[MAX_LIGHTS]; // (x, y, intensity, range) in screen px
    uniform float u_ambient;

    uniform float atlasHeight; // texels
    uniform float spriteScale; // world px per texel
    uniform float zoom;
    uniform float groundAlpha;

    const float LIGHT_HEIGHT = 40.0; // world px: lamps and the player's light, about head height

    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 screen_coords) {
        vec4 texel = Texel(tex, tc);
        float flags = floor(color.b * 255.0 + 0.5);
        bool isFlat = flags >= 4.0;
        bool isGlass = mod(flags, 4.0) >= 2.0;
        bool isTall = mod(flags, 2.0) >= 1.0;
        if (!isGlass && texel.a < 0.5) discard;

        float base = floor(color.r * 255.0 + 0.5) * 256.0 + floor(color.g * 255.0 + 0.5);
        float zs = isFlat ? 0.0 : max(0.0, base - tc.y * atlasHeight) * spriteScale * zoom;
        vec2 ground = screen_coords + vec2(0.0, zs);
        float lightZ = isFlat ? 0.0 : LIGHT_HEIGHT * zoom;
        float upright = min(zs / (12.0 * zoom), 1.0);

        float ambient = (u_ambient > 0.0) ? u_ambient : 0.20;
        float totalLight = 0.0;
        for (int i = 0; i < MAX_LIGHTS; i++) {
            if (i >= numLights) break;
            float range = lights[i].w;
            if (range <= 0.0) continue;
            float dist = length(vec3(lights[i].xy - ground, lightZ - zs));
            if (dist >= range) continue;
            float att = 1.0 - dist / range;
            float facing = mix(1.0, smoothstep(-24.0 * zoom, 8.0 * zoom, lights[i].y - ground.y), upright);
            totalLight += att * att * facing * lights[i].z;
        }
        float contact = mix(0.65, 1.0, smoothstep(0.0, 18.0 * zoom, zs));
        if (isFlat) contact = 1.0;
        vec3 rgb = texel.rgb * min(1.0, ambient + totalLight) * contact;

        if (isFlat) return vec4(rgb * groundAlpha, groundAlpha);
        if (isGlass) return vec4(rgb, texel.a);
        return vec4(rgb, isTall ? 1.0 : groundAlpha);
    }
]]
local function sendSpriteUniforms(r)
    local shader = regions.spriteShader
    shader:send("atlasHeight", r.image:getHeight())
    shader:send("spriteScale", r.scale)
    shader:send("zoom", camera.zoom)
    shader:send("groundAlpha", GROUND_ALPHA)
    shadow.sendLights(shader)
end

local function loadArt(r)
    local meta = require("gfx.regions." .. r.id)
    r.image = love.graphics.newImage(meta.image)
    r.image:setFilter("nearest", "nearest")
    r.sprites = {}
    local iw, ih = r.image:getDimensions()
    for name, s in pairs(meta.sprites) do
        r.sprites[name] = {
            w = s.w, h = s.h, cat = s.cat, glass = s.glass,
            base = s.y + s.h - 2, -- the row its art stands on (2 px of padding below)
            quad = love.graphics.newQuad(s.x, s.y, s.w, s.h, iw, ih),
        }
    end
    -- A typo in a pool would otherwise only show up as a hole in the layout
    for _, pool in ipairs({ "edge", "posts", "facades", "landmarks", "props", "decor", "lights", "portalLights", "flat" }) do
        for _, name in ipairs(r[pool]) do
            assert(r.sprites[name], ("region %s: no sprite %q (%s)"):format(r.id, name, pool))
        end
    end
    r.flatSet = {}
    for _, name in ipairs(r.flat) do r.flatSet[name] = true end

    if meta.floorImage then
        r.floorImage = love.graphics.newImage(meta.floorImage)
        r.floorLayers = #meta.floors
    else
        r.floorImage, r.floorLayers = neonFloor()
    end
    r.floorImage:setFilter("nearest", "nearest")
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

-- Collision depth (world px) up from the base, per category: a building's
-- footprint, a wall's thickness. Decor never blocks.
local DEPTH = { facade = 0.3, wall = 0.18, tower = 0.25, barrier = 0.2, prop = 0.2, light = 0.15, landmark = 0.3 }

-- Put sprite `name` with its left edge at x and its base on `base`. Returns
-- its width and the item, or nil if `check` is set and something's in the way.
local function place(r, name, x, base, check)
    local s = r.sprites[name]
    local scale = r.scale
    local w, h = s.w * scale, s.h * scale
    local depth = DEPTH[s.cat]
    local fh = depth and math.max(10, math.min(h * depth, 70)) or 0
    local fx, fw = x + w * 0.08, w * 0.84
    if check and not isFree(r.grid, fx, base - math.max(fh, 8), fw, math.max(fh, 8)) then
        return nil
    end
    -- How it meets the light (SPRITE_SHADER): its base row and flags ride in
    -- the vertex colour
    local flat = r.flatSet[name]
    local tall = not flat and (TALL[s.cat] or r.glows[name] or (s.h - 4) * scale >= OCCLUDE_HEIGHT)
    local flags = (tall and 1 or 0) + (s.glass and 2 or 0) + (flat and 4 or 0)
    local color = { math.floor(s.base / 256) / 255, s.base % 256 / 255, flags / 255, 1 }
    -- the sprite's bottom 2 px are padding: drop it so its art sits on the base
    local item = {
        sort_y = base + SORT_OFFSET,
        image_or_particles = r.image,
        quad = s.quad,
        x = math.floor(x + 0.5),
        y = math.floor(base - h + 2 * scale + 0.5),
        rotation = 0,
        scale_x = scale,
        scale_y = scale,
        offset_x = 0,
        offset_y = 0,
        color = color,
        blend_mode = s.glass and ALPHA or REPLACE,
        source_object_type = "region",
    }
    item.x1, item.y1 = item.x + w, base
    if flat then
        -- underfoot: drawn with the ground, so whoever walks over it is on top
        r.flatBatch:setColor(unpack(color))
        r.flatBatch:add(s.quad, item.x, item.y, 0, scale, scale)
    else
        r.items[#r.items + 1] = item
    end
    if depth then
        r.solids[#r.solids + 1] = { fx, base - fh, fw, fh }
        mark(r.grid, fx, base - fh, fw, fh)
    else
        mark(r.grid, x + w * 0.2, base - 6, w * 0.6, 6)
    end
    if s.cat == "light" then
        r.lightList[#r.lightList + 1] = { x + w / 2, base - h * 0.6, 0.9, 230 }
    elseif r.glows and r.glows[name] then
        r.lightList[#r.lightList + 1] = { x + w / 2, base - h * 0.5, 0.45, 140 }
    end
    return w, item
end

local function generate(r, index)
    local rng = love.math.newRandomGenerator(r.seed)
    local function rand(a, b) return a + rng:random() * (b - a) end
    local function pick(list) return list[rng:random(#list)] end
    local function width(name) return r.sprites[name].w * r.scale end

    r.ox, r.oy = SPACING * (index - 1), 0
    local ox, oy = r.ox, r.oy
    r.grid = newGrid(r)
    r.items, r.solids, r.lightList = {}, {}, {}
    r.flatBatch = love.graphics.newSpriteBatch(r.image, 128, "static")

    r.ground = groundMesh(r)

    -- The portal stands at the bottom middle in a clear plaza, lights either side
    r.portal = { x = math.floor(ox + W / 2 - 17), y = oy + H - 330 }
    r.spawn = { x = r.portal.x + 17, y = r.portal.y + 100 }
    if #r.portalLights == 2 then
        local base = r.portal.y + 58
        place(r, r.portalLights[1], r.portal.x - 50 - width(r.portalLights[1]), base)
        place(r, r.portalLights[2], r.portal.x + 85, base)
    end
    local plaza = { x = r.portal.x - 230, y = r.portal.y - 140, w = 495, h = 330 }
    mark(r.grid, plaza.x, plaza.y, plaza.w, plaza.h)

    -- Walls: a run along the top and bottom, posts down either side
    local function wallRun(base)
        local x = ox - 40
        while x < ox + W + 40 do
            local name = pick(r.edge)
            x = x + place(r, name, x, base) - 3 * r.scale
            if #r.posts > 0 and rng:random() < 0.12 then
                local post = pick(r.posts)
                x = x + place(r, post, x, base + 4) - 3 * r.scale
            end
        end
    end
    wallRun(oy + TOP)
    wallRun(oy + H + 40)
    if #r.posts > 0 then
        local y = oy + TOP + 120
        while y < oy + H do
            local a, b = pick(r.posts), pick(r.posts)
            place(r, a, ox - width(a) / 2, y)
            place(r, b, ox + W - width(b) / 2, y)
            y = y + rand(110, 170)
        end
    end
    mark(r.grid, ox - MARGIN, oy - MARGIN, W + 2 * MARGIN, MARGIN + TOP + 20)
    mark(r.grid, ox - MARGIN, oy + H - 10, W + 2 * MARGIN, MARGIN + 10)

    -- A landmark in a gap in the middle street, maybe another in the top one
    local reserved = {}
    local landmarks = {}
    for i = 1, #r.landmarks do landmarks[i] = r.landmarks[i] end
    for i = #landmarks, 2, -1 do
        local j = rng:random(i)
        landmarks[i], landmarks[j] = landmarks[j], landmarks[i]
    end
    for i, rowIndex in ipairs({ 2, 1 }) do
        local name = landmarks[i]
        if name then
            local w = width(name)
            local x = ox + W * rand(0.35, 0.65) - w / 2
            reserved[rowIndex] = { x - 60, x + w + 60 }
            place(r, name, x, oy + H * ROWS[rowIndex] + 30)
        end
    end

    -- Facade streets, lamps along the pavement, props in front of the doors
    for rowIndex, f in ipairs(ROWS) do
        local base = oy + H * f
        local x = ox + rand(40, 120)
        local gap = reserved[rowIndex]
        while x < ox + W - 80 do
            local name = pick(r.facades)
            local w = width(name)
            if gap and x + w > gap[1] and x < gap[2] then
                x = gap[2]
            elseif x + w > ox + W - 40 then
                break
            else
                place(r, name, x, base + rand(-6, 6))
                if rng:random() < 0.55 then
                    local prop = pick(r.props)
                    local px = x + rand(0, math.max(0, w - width(prop)))
                    place(r, prop, px, base + rand(45, 120), true)
                end
                -- alleys now and then, otherwise the fronts nearly touch
                x = x + w + (rng:random() < 0.22 and rand(110, 200) or rand(0, 22))
            end
        end
        if #r.lights > 0 then
            local lx = ox + rand(60, 200)
            while lx < ox + W - 60 do
                place(r, pick(r.lights), lx, base + rand(62, 78), true)
                lx = lx + rand(240, 360)
            end
        end
    end

    -- Water: a pool in the open ground beside the plaza, puddles anywhere free
    local side = rng:random() < 0.5 and 0.22 or 0.78
    local px, py = ox + W * side, oy + H * 0.86
    local prx, pry = rand(170, 230), rand(70, 90)
    puddle.add(px, py, prx, pry)
    mark(r.grid, px - prx, py - pry, prx * 2, pry * 2)
    -- the water shader's distortion, kept well inside the pool's wobbly edge
    r.water = { px - prx * 0.48, py - pry * 0.48, prx * 0.96, pry * 0.96 }
    for _ = 1, r.puddles do
        for _ = 1, 12 do
            local rx, ry = rand(26, 70), rand(12, 28)
            local x, y = rand(ox + 80, ox + W - 80), rand(oy + TOP + 60, oy + H - 60)
            if isFree(r.grid, x - rx, y - ry, rx * 2, ry * 2) then
                puddle.add(x, y, rx, ry)
                mark(r.grid, x - rx, y - ry, rx * 2, ry * 2)
                break
            end
        end
    end

    -- Scattered props, then things underfoot that don't block
    for _ = 1, 30 do
        local name = pick(r.props)
        place(r, name, rand(ox + 60, ox + W - 160), rand(oy + TOP + 80, oy + H - 40), true)
    end
    if #r.decor > 0 then
        for _ = 1, math.min(70, #r.decor * 6) do
            local name = pick(r.decor)
            local w = width(name)
            local x, y = rand(ox + 40, ox + W - 40 - w), rand(oy + TOP + 60, oy + H - 20)
            if isFree(r.grid, x, y - 12, w, 12) then
                place(r, name, x, y)
            end
        end
    end

    -- Grass in ragged patches on open ground: each its own field, so only the
    -- ones on screen are drawn
    local nx, ny = r.seed * 0.37, r.seed * 0.11
    for _ = 1, r.grass.patches do
        local cx, cy = rand(ox + 80, ox + W - 80), rand(oy + TOP + 80, oy + H - 60)
        if freeAt(r.grid, cx, cy) then
            local hw, hh = rand(110, 230), rand(70, 140)
            local field = grass.public.addField(cx - hw, cy - hh, hw * 2, hh * 2, math.floor(hw * hh * 4 / 18),
                function(x, y)
                    local d = ((x - cx) / hw) ^ 2 + ((y - cy) / hh) ^ 2
                    return d < 1 and freeAt(r.grid, x, y)
                        and love.math.noise(x * 0.02 + nx, y * 0.02 + ny) > 0.3 + 0.55 * d
                end, r.grass.tint)
            field.occludes = false -- ankle high: light passes over it
        end
    end

    -- Physics: every footprint, and a fence just inside the walls
    r.body = love.physics.newBody(world, 0, 0, "static")
    for _, s in ipairs(r.solids) do
        local fixture = love.physics.newFixture(r.body,
            love.physics.newRectangleShape(s[1] + s[3] / 2, s[2] + s[4] / 2, s[3], s[4]))
        fixture:setGroupIndex(collision.groups.map)
        fixture:setUserData({ type = "region", region = r.id })
    end
    local fence = love.physics.newFixture(r.body, love.physics.newChainShape(true,
        ox + 24, oy + TOP - 8, ox + W - 24, oy + TOP - 8,
        ox + W - 24, oy + H - 40, ox + 24, oy + H - 40))
    fence:setGroupIndex(collision.groups.map)
    fence:setUserData({ type = "region", region = r.id })

    r.grid = nil -- only needed while laying out (and by the grass, which is built)
end

function regions.load()
    groundShader = love.graphics.newShader(GROUND_SHADER)
    regions.spriteShader = love.graphics.newShader(SPRITE_SHADER)
    for i, r in ipairs(regions.list) do
        if r.seed then
            loadArt(r)
            generate(r, i)
        end
    end
    regions.current = regions.list[1]
end

--------------------------------------------------------------------------------
-- Per frame
--------------------------------------------------------------------------------

-- The world rect on screen, padded by `pad` px
function regions.view(pad)
    pad = pad or 0
    local zoom = camera.zoom
    local x0 = -camera.x / zoom
    local y0 = -camera.y / zoom
    return x0 - pad, y0 - pad,
        x0 + love.graphics.getWidth() / zoom + pad, y0 + love.graphics.getHeight() / zoom + pad
end

local function overlaps(r, x0, y0, x1, y1)
    return r.ox and r.ox - MARGIN < x1 and r.ox + W + MARGIN > x0
        and r.oy - MARGIN < y1 and r.oy + H + MARGIN > y0
end

--- The region world point (x, y) is in (home when it's in none of them).
function regions.at(x, y)
    for _, r in ipairs(regions.list) do
        if r.ox and x >= r.ox - MARGIN and x <= r.ox + W + MARGIN
            and y >= r.oy - MARGIN and y <= r.oy + H + MARGIN then
            return r
        end
    end
    return regions.list[1]
end

function regions.update(dt)
    if not (player and player.body) then return end
    local px, py = player.body:getPosition()
    local here = regions.at(px, py)
    if here ~= regions.current then
        regions.current = here
        if here.water then
            water.setWaterArea(unpack(here.water))
        else
            water.setWaterArea(0, 0, 0, 0)
        end
    end

    -- Lamps and braziers on screen light the scene this frame
    if here.lightList then
        local x0, y0, x1, y1 = regions.view(240)
        for _, l in ipairs(here.lightList) do
            if l[1] > x0 and l[1] < x1 and l[2] > y0 and l[2] < y1 then
                shadow.addTransientLight(l[1], l[2], l[3], l[4])
            end
        end
    end
end

--- Region ground, under the camera transform with the map's colour.
function regions.drawGround()
    local x0, y0, x1, y1 = regions.view(0)
    local prev
    for _, r in ipairs(regions.list) do
        if r.ground and overlaps(r, x0, y0, x1, y1) then
            if not prev then
                prev = love.graphics.getShader()
                love.graphics.setShader(groundShader)
                shadow.sendLights(groundShader)
            end
            groundShader:send("layers", r.floorLayers)
            groundShader:send("cellular", r.cellular and 1 or 0)
            groundShader:send("seed", { r.seed % 97, r.seed % 89 })
            love.graphics.draw(r.ground)

            -- grates, carpets, rubble: part of the ground, cut out over it
            sendSpriteUniforms(r)
            love.graphics.setShader(regions.spriteShader)
            local mode, alphaMode = love.graphics.getBlendMode()
            love.graphics.setBlendMode("replace", "premultiplied")
            love.graphics.draw(r.flatBatch)
            love.graphics.setBlendMode(mode, alphaMode)
            love.graphics.setShader(groundShader)
        end
    end
    if prev then
        love.graphics.setShader(prev)
    end
end

--- Add the region sprites on screen to the dynamic draw list (the renderer
--- draws them with regions.spriteShader).
function regions.populate()
    local x0, y0, x1, y1 = regions.view(32)
    for _, r in ipairs(regions.list) do
        if r.items and overlaps(r, x0, y0, x1, y1) then
            sendSpriteUniforms(r)
            for _, item in ipairs(r.items) do
                if item.x < x1 and item.x1 > x0 and item.y < y1 and item.y1 > y0 then
                    dynamic_draw_list[#dynamic_draw_list + 1] = item
                end
            end
        end
    end
end

--- Put the player at region r's arrival point, just in front of its portal.
function regions.teleport(r)
    local x, y = r.spawn and r.spawn.x or r.portal.x + 17, r.spawn and r.spawn.y or r.portal.y + 100
    player.body:setPosition(x, y)
    player.body:setLinearVelocity(0, 0)
    player.isDodging = false
    camera.snap(player)
end

return regions
