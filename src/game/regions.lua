--[[
  Regions: the far-off places the portal travels to (see game/portal.lua).

  Each region's art was cut from its own sprite sheet into gfx/regions/<id>.png,
  with every sprite's rect and category in gfx/regions/<id>.lua (and its ground
  textures in <id>_floor.png). At load each region is laid out procedurally from
  its seed, far east of the home map so nothing overlaps:
    - a street plan: rows of buildings each with a pavement and a road in
      front, and across the road another pavement and a wall, so every road
      runs between buildings and a wall; avenues crossing them in line
      (through gaps flanked by posts, and lined with posts between the
      streets), the main one running from the portal's square to a
      landmark; gateways in the walls into the yards behind; a square across
      from the pool,
    - ground that follows it: every 64 px cell is open ground, pavement,
      road or square, each with its own floor, blending over ragged edges
      (or, for tiled floors, changing at the cell's edge),
    - walls along the edge (a physics chain keeps everyone inside),
    - blocks of buildings shoulder to shoulder with alleys between, and the
      rest where it would be: lamps along the kerbs, things against walls
      and gates, cars parked by the kerb, road works, manholes, puddles in
      the roads, clutter and grass on open ground.
  Everything is lit by its height (see SPRITE_SHADER): tall things block light
  and are lit up their faces, things underfoot are part of the ground. Things
  that give off light (lamps, flames, neon, glowing glass) shine whatever the
  dark, light the scene around them and glow (see the emitters below).
  The same seed gives the same layout, so every client in a multiplayer game
  agrees on it without sending anything.
  Everything with collision is a structure (game/destruction.lua): shot, it
  takes marks and cracks, sheds shards, and at last comes down.
]]
local regions = {}
local normalmap = require("lib.graphics.normalmap")
local footprint = require("lib.graphics.footprint")
local cache = require("util.cache")
local destruction = require("game.destruction")
local lighting = require("lib.graphics.shadow") -- (the global shadow; this loads first)

local TILE = 128        -- world px each ground texture covers before it repeats
local W, H = 2560, 1920 -- region size, inside its walls
local SPACING = 20000   -- world px between region origins (home is around 0, 0)
local MARGIN = 512      -- ground past the walls, so the edge of the world never shows
local CELL = 16         -- occupancy grid cell, for keeping things apart
local TOP = 170         -- the top wall's base, below the region's top edge
local ROWS = { 0.25, 0.46, 0.67 } -- facade street baselines, as fractions of H
local ZONE = 64         -- world px per ground cell (the street plan's grid)
-- The draw list sorts characters by body y + characterAnimator.sortYOffset (130),
-- and their feet are ~25 px below the body: a sprite whose base is at world y
-- sorts with a character standing on that line.
local SORT_OFFSET = 105
local ALPHA = { "alpha" }
-- Cut-out sprites write their colour and their own alpha straight into the
-- scene, so each decides whether the GI pass sees it as a wall (alpha > 0.5)
local REPLACE = { "replace", "premultiplied" }
local GROUND_ALPHA = 0.4  -- the map's ground alpha (draw.lua): never blocks light
-- Buildings, walls, towers, landmarks, lamps and anything that glows block light
-- like a wall (and give off their colour); props only when they're over head
-- height. (A sprite's height is no guide below that: an isometric car's
-- includes its roof seen from above.)
local TALL = { facade = true, wall = true, tower = true, landmark = true, light = true }
local OCCLUDE_HEIGHT = 96 -- world px

-- Each region's sprites, by what they're for in its streets (see generate):
--   edge, posts ........ the perimeter wall, and posts in it and down its sides
--   layout.facades ..... buildings that make up a street's blocks; corners
--                        end a block; separators stand between buildings now
--                        and then (towers, arches, fire escapes)
--   layout.landmarks ... at the end of the main avenue and the top street
--                        ("row"), or parked in a road ("road")
--   layout.gates ....... facades with a way in, flanked by `flank` pairs
--   layout.lights ...... along the kerbs, every lightSpacing px
--   layout.kerb ........ small things on the pavement between the lights
--   layout.wall ........ against a building's front (bins, banners, lecterns)
--   layout.parked ...... in a road's near lane
--   layout.roadworks ... a run of barriers in a road's far lane
--   layout.alleyFences . across an alley's mouth
--   layout.wallGates ... across some gateways in the walls along the roads
--   layout.square ...... a square's corner pieces (ring), its centrepiece
--                        (feature) and what lies in its middle (centre)
--   layout.roadFlat .... down a road's middle; kerbFlat along its kerb
--   layout.lot ......... loose on open ground; lotFlat lying on it
--   layout.companions .. what lies beside a thing (cans by bins)
--   layout.ground ...... which floor layer each kind of ground uses: lot,
--                        walk (pavements), road, plaza; roadAlt/lotAlt mix
--                        in where a noise field is high; hard floors change
--                        at the cell edge, the rest blend over ragged edges
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
        -- lying on the ground: walked over, drawn into the ground, never block light
        flat = { "rubble_a", "rubble_b", "rubble_c", "rubble_d", "rubble_e", "can_a", "can_b", "can_c",
            "can_d", "brick", "chainlink_a", "chainlink_b" },
        portalLights = {},
        boss = "swarm", -- a fly's brain and every fly in the place (game/swarmBoss.lua)
        layout = {
            facades = { "shop_a", "shop_b", "ruin_a", "brick_block" },
            corners = { "corner_a", "corner_b", "corner_c", "corner_d", "corner_e", "corner_escape" },
            separators = { "fire_escape", "pillar_block", "scaffold_a", "scaffold_b" },
            separatorChance = 0.18,
            -- a block that's lost a building: a graffitied wall where it stood
            infill = { "slab_graffiti_a", "slab_graffiti_c", "slab_graffiti_d", "slab_d" },
            wallGates = { "fence_gate" },
            landmarks = { "bus" },
            landmarkIn = "road",
            lights = {},
            kerb = { "hydrant_a", "hydrant_b" },
            kerbChance = 0.3,
            wall = { "bins" },
            wallChance = 0.22,
            parked = { "car_a", "car_b", "car_c" },
            parkedChance = 0.35,
            roadworks = { "jersey_a", "jersey_b", "jersey_fallen" },
            alleyFences = { "fence_broken", "fence_rusty", "fence_iron_a", "fence_iron_b", "fence_gate",
                "fence_sheet", "fence_brick" },
            roadFlat = { "rubble_e", "brick" },
            lot = { "jersey_fallen", "fence_broken", "bins" },
            lotFlat = { "rubble_a", "rubble_b", "rubble_c", "rubble_d", "rubble_e", "brick", "can_d" },
            companions = {
                bins = { "can_a", "can_b", "can_c", "can_d" },
                fence_broken = { "chainlink_a", "chainlink_b" },
                fence_rusty = { "chainlink_b" },
                ruin_a = { "rubble_c", "brick", "rubble_d" },
                scaffold_a = { "brick", "rubble_e" },
                scaffold_b = { "brick", "rubble_a" },
                bus = { "rubble_b" },
            },
            ground = { lot = 1, lotAlt = 0, walk = 0, road = 2, plaza = 0, rough = 0.9 },
        },
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
        flat = { "coins", "rune_carpet" },
        portalLights = { "brazier_b", "brazier_b" },
        boss = "bear", -- guarding its lair (game/bosses.lua)
        layout = {
            facades = { "blue_window", "cell_wall", "gothic_wall", "gate_wall", "great_gate", "dungeon_wall_a",
                "dungeon_wall_b", "ruin_windows", "ruin_wall" },
            corners = { "corner_brick", "blue_corner", "corner_hall", "corner_hall_windows", "corner_window_a",
                "corner_window_b", "corner_window_c" },
            separators = { "round_tower", "round_tower_b", "tower_stair", "arch", "portcullis_arch" },
            separatorChance = 0.3,
            landmarks = { "gatehouse", "stained_glass", "long_wall" },
            landmarkIn = "row",
            gates = { "great_gate", "gate_wall", "portcullis_arch", "gatehouse", "arch" },
            wallGates = { "portcullis" },
            flank = { "brazier_b" },
            lights = { "brazier_a", "brazier_c", "candelabra" },
            lightSpacing = 340,
            kerb = {},
            wall = { "banner_blue", "banner_red", "banner_blue", "banner_red", "chest" },
            wallChance = 0.4,
            alleyFences = { "portcullis", "ice_barrier" },
            square = { ring = { "column_a", "column_b", "column_c", "column_d", "column_e" },
                feature = { "spiral_stair" } },
            lot = { "column_a", "column_d", "chest" },
            lotFlat = {},
            companions = {
                chest = { "coins" },
                great_gate = { "rune_carpet" },
                gatehouse = { "rune_carpet" },
            },
            ground = { lot = 0, walk = 0, road = 1, plaza = 2, rough = 0.6 },
        },
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
        flat = { "grate_a", "grate_b", "manhole", "rail" },
        portalLights = { "lamp_a", "lamp_b" },
        boss = "arm", -- bolted down at its lair (game/robotArm.lua)
        layout = {
            facades = { "tower_ramen", "tower_tech", "block_cyber", "block_glass" },
            corners = {},
            separators = { "spire" },
            separatorChance = 0.12,
            wallGates = { "shutter" },
            landmarks = { "holo_big" },
            landmarkIn = "row",
            lights = { "lamp_a", "lamp_b" },
            lightSpacing = 260,
            kerb = { "plant_a", "plant_b", "plant_c", "terminal_a", "terminal_b", "trash_a", "trash_b",
                "sign_arrows", "sign_updown", "sign_triangle", "sign_bowl", "sign_ramen", "sign_cyber", "sign_kanji" },
            kerbChance = 0.75,
            wall = { "vent_box", "panel_box", "terminal_c", "trash_a", "trash_b" },
            wallChance = 0.45,
            roadworks = { "barrier_a", "barrier_b", "barrier_c", "barrier_hazard", "blocks", "jersey_striped" },
            alleyFences = { "grate_fence", "laser_fence", "net_fence", "shutter" },
            square = { ring = { "holo_cyan", "holo_purple", "holo_frame" }, feature = { "holo_laser" },
                edge = { "neon_bar_a", "neon_bar_b", "neon_bar_c", "neon_bar_d" } },
            roadFlat = { "manhole", "grate_a", "grate_b" },
            kerbFlat = { "rail" },
            lot = { "vent_box", "panel_box", "terminal_c" },
            lotFlat = { "grate_a", "grate_b" },
            companions = { laser_fence = { "laser_small" }, terminal_c = { "trash_a" } },
            -- asphalt (clean, grimy) for the roads; the dark tiles' plates for
            -- pavements and open ground, their grates and plates for squares
            ground = { lot = 2, walk = 2, road = 0, roadAlt = 1, plaza = 3, hard = true },
        },
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
        flat = { "scroll_a", "scroll_b", "book", "sun_emblem" },
        portalLights = { "lantern_b", "lantern_b" },
        layout = {
            facades = { "cathedral_a", "cathedral_b", "cathedral_c", "dome_a", "dome_b", "dome_c", "dome_d",
                "chapel" },
            corners = {},
            separators = { "curtain_arch_a", "curtain_arch_b", "curtain_arch_c", "rune_glass_c", "rune_glass_d",
                "rune_glass_e", "altar_a", "altar_b", "altar_c" },
            separatorChance = 0.3,
            landmarks = { "cathedral_d", "pavilion" },
            landmarkIn = "row",
            gates = { "cathedral_a", "cathedral_b", "cathedral_c", "chapel", "cathedral_d" },
            wallGates = { "door_wall_a", "door_wall_b", "door_wall_c" },
            flank = { "angel", "angel_b" },
            lights = { "lantern_a", "lantern_b" },
            lightSpacing = 240,
            kerb = { "flowers_a", "flowers_b", "plant_a", "plant_b", "bench" },
            kerbChance = 0.6,
            wall = { "lectern", "table", "stool_a", "stool_b", "shrine_b" },
            wallChance = 0.3,
            alleyFences = { "curtain_wall", "glass_panel" },
            square = { ring = { "spire_a", "spire_b", "rune_glass_a", "rune_glass_b" },
                feature = { "fountain", "shrine_a", "shrine_c", "urn" }, centre = { "sun_emblem" } },
            lot = { "flowers_a", "flowers_b", "plant_a", "urn", "bench" },
            lotFlat = {},
            companions = {
                lectern = { "book", "scroll_a" },
                table = { "scroll_b", "book" },
                fountain = { "lotus_a", "lotus_b", "orb_a", "orb_b" },
                shrine_a = { "orb_a", "orb_c" },
                shrine_c = { "orb_b", "lotus_a" },
                urn = { "orb_c" },
            },
            -- golden streets, crystal pavements and squares, marble between
            ground = { lot = 0, walk = 1, road = 2, plaza = 1, hard = true },
        },
        grass = { patches = 14, tint = { 1.0, 1.05, 0.75 } },
        puddles = 10,
    },
}

regions.current = regions.list[1]
regions.W, regions.H = W, H -- a region's size, inside its walls

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

-- Neon City's floors, its sheet having none. Its roads are dark asphalt
-- plates, clean and grimy, tiling seamlessly (seams every 64 px, the grime
-- noise wrapped round a torus). Its pavements and squares are
-- TileSet/grounds.png's dark sci-fi tiles at 32 px, each piece of several
-- tiles put together as drawn (2|3 a plate two wide, 5 over 9 one two tall,
-- 4 a single plate, 13 a vent, and the mesh grate's nine pieces 6 7 8 /
-- 10 11 12 / 15 16 17), and every piece kept inside a 64 px cell so a
-- floor changing at a cell's edge never cuts one.
local NEON_TILES = {
    -- pavement: a 4x4 of tiles per 128 px, a cell (2x2) at a time
    { { 2, 3, 5, 5 }, { 2, 3, 9, 9 }, { 4, 13, 2, 3 }, { 4, 4, 4, 4 } },
    -- squares: framed mesh grates and plates in a checker
    { { 6, 8, 2, 3 }, { 15, 17, 2, 3 }, { 5, 5, 6, 8 }, { 9, 9, 15, 17 } },
}

local function neonFloor()
    local size = 128
    local layers = 2 + #NEON_TILES
    local data = love.image.newImageData(size * layers, size)
    local rng = love.math.newRandomGenerator(77)
    local tau = 2 * math.pi
    for v = 0, 1 do
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
    local tiles = love.image.newImageData("gfx/TileSet/grounds.png")
    for i, layout in ipairs(NEON_TILES) do
        local lx = (1 + i) * size
        for ty, row in ipairs(layout) do
            for tx, id in ipairs(row) do
                local sx = (id - 1) * 16
                for y = 0, 31 do
                    for x = 0, 31 do
                        local r, g, b = tiles:getPixel(sx + math.floor(x / 2), math.floor(y / 2))
                        data:setPixel(lx + (tx - 1) * 32 + x, (ty - 1) * 32 + y, r, g, b, 1)
                    end
                end
            end
        end
    end
    return love.graphics.newImage(data), layers
end

-- The ground: one quad per region, textured in TILEs from the region's corner.
-- Each floor texture (side by side in the region's floor image, each tiling
-- seamlessly) repeats across it; the first covers everything and the others
-- go over it where the street plan says (r.zones: a texel per ZONE cell, the
-- weight of layers 1-3 in r, g, b, and in a its shade: roads a little darker
-- and pavements lighter, so a street reads whatever its floors look like). Most floors blend over ragged edges
-- (the weights filtered between cells and pushed about by noise); a tiled
-- one (hard) changes at the cell's edge, which falls on its grout.
-- Lit like the map, by the same lights (shadow.lua).
local GROUND_SHADER = lighting.REACH_GLSL .. [[
    #define MAX_LIGHTS 64
    uniform int   numLights;
    uniform vec4  lights[MAX_LIGHTS]; // (x, y, intensity, range) in screen px
    uniform float u_ambient;

    uniform float layers;   // floor textures in the image
    uniform float hard;     // 1: floors change at a cell's edge; 0: they blend
    uniform float rough;    // how ragged blended edges are
    uniform vec2  seed;
    uniform Image zones;    // the street plan: a texel per cell
    uniform vec2  zoneSize; // cells
    uniform float zoneScale; // cells per uv unit (TILE / ZONE)

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
        vec4 z = Texel(zones, uv * zoneScale / zoneSize);
        for (int k = 1; k < 4; k++) {
            float fk = float(k);
            if (fk >= layers) break;
            float target = z.r;
            if (k == 2) target = z.g;
            if (k == 3) target = z.b;
            float w;
            if (hard > 0.5) {
                w = step(0.5, target);
            } else {
                // two octaves, so blended edges are ragged. The noise only
                // moves the edge rough / 2 either way (each octave is in
                // [0, 1)): further from it than that, or than the first
                // octave leaves the second able to, it's all one floor or
                // the other, which the smoothstep gives exactly, so the
                // rest isn't worked out
                float spread = abs(rough) * 0.5 + 0.001;
                if (target + spread < 0.42) {
                    w = 0.0;
                } else if (target - spread > 0.58) {
                    w = 1.0;
                } else {
                    float n1 = vnoise(uv * 1.3 + seed + fk * 17.31);
                    float lo = target + (n1 * 0.65 - 0.5) * rough;
                    float hi = target + (n1 * 0.65 - 0.15) * rough;
                    if (min(lo, hi) > 0.581) {
                        w = 1.0;
                    } else if (max(lo, hi) < 0.419) {
                        w = 0.0;
                    } else {
                        float n = n1 * 0.65
                                + vnoise(uv * 3.7 + seed - fk * 5.7) * 0.35;
                        w = smoothstep(0.42, 0.58, target + (n - 0.5) * rough);
                    }
                }
            }
            // (all the floor below: as mixed in, exactly)
            if (w > 0.0) c = mix(c, layer(floors, fk, uv), w);
        }
        // the kind of ground's shade, then broad light and dark drifts, so
        // the repeat doesn't read
        c *= z.a * 1.5;
        c *= 0.88 + 0.24 * vnoise(uv * 0.13 + seed.yx);

        float ambient = (u_ambient > 0.0) ? u_ambient : 0.20;
        float totalLight = 0.0;
        float beam = -1.0; // beamReaches, once a beam light needs it
        for (int i = 0; i < MAX_LIGHTS; i++) {
            if (i >= numLights) break;
            float range = lightRange(lights[i]);
            if (range <= 0.0) continue;
            float dist = distance(lights[i].xy, screen_coords);
            if (dist >= range) continue;
            float att = 1.0 - dist / range;
            // not past what's in the way (shadow.lua)
            totalLight += att * att * lights[i].z * reaches(i, lights[i], range, screen_coords, beam);
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
--     and a light behind a face doesn't light it (normalmap.lua's faceShade),
--   - the foot of anything upright sits in a little contact shadow.
-- The alpha it writes decides what the GI pass makes of it (> 0.5: a wall
-- that blocks light and gives off its colour). Tall things do; low props
-- don't; flat things underfoot are drawn into the ground, as dim as it is.
-- By day the composite divides the scene by its alpha (shader.lua: it undoes
-- the ground's dimming), so a low prop is dimmed to match first, and shows
-- as bright as a tall thing beside it.
-- Upright things have normal maps too (lib/graphics/normalmap.lua): each
-- light, and the sky's ambient light, shades a texel by which way it faces.
-- The buildings' own relief (brickwork, windows, trim) is baked deeper than
-- the props', by category:
local RELIEF = { facade = 1.6, wall = 1.4, tower = 1.4, landmark = 1.4 }
-- Texels marked in the region's glow map are light sources themselves (a
-- flame, a bulb, a neon tube): they shine at full strength however dark it is,
-- and being bright in the scene, the GI pass spreads their colour around.
-- Flags: 1 tall, 2 glass (blended with its own alpha), 4 flat.
local SPRITE_SHADER = normalmap.GLSL .. lighting.REACH_GLSL .. [[
    #define MAX_LIGHTS 64
    uniform int   numLights;
    uniform vec4  lights[MAX_LIGHTS]; // (x, y, intensity, range) in screen px
    uniform float u_ambient;

    uniform float atlasHeight; // texels
    uniform float spriteScale; // world px per texel
    uniform float zoom;
    uniform float groundAlpha;
    uniform Image glowMap;     // the atlas's layout: how much each texel gives off light
    uniform Image normalMap;   // and which way each texel faces
    uniform float daylight;    // 0 night .. 1 day (systems/daynight.lua)

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
        // things underfoot are part of the ground, which is flat
        vec3 n = isFlat ? vec3(0.0, 0.0, 1.0) : faceNormal(normalMap, tc);
        // and what stands is lit through a point out in front of its foot
        // (shadow.lua's faceGround), not on its own footprint
        vec2 through = isFlat ? ground : faceGround(ground, n, FACE_GAP * zoom);

        float ambient = (u_ambient > 0.0) ? u_ambient : 0.20;
        if (!isFlat) ambient *= skyShade(n);
        float totalLight = 0.0;
        float beam = -1.0; // beamReaches(through), once a beam light needs it
        for (int i = 0; i < MAX_LIGHTS; i++) {
            if (i >= numLights) break;
            float range = lightRange(lights[i]);
            if (range <= 0.0) continue;
            float lightZ = isFlat ? 0.0 : lightHeightOf(i, LIGHT_HEIGHT * zoom);
            vec3 toLight = vec3(lights[i].xy - ground, lightZ - zs);
            float dist = length(toLight);
            if (dist >= range) continue;
            float att = 1.0 - dist / range;
            float k = att * att * lights[i].z;
            if (!isFlat) k *= faceShade(n, toLight);
            totalLight += k * reaches(i, lights[i], range, through, beam); // not past what's in the way
        }
        float contact = mix(0.65, 1.0, smoothstep(0.0, 18.0 * zoom, zs));
        if (isFlat) contact = 1.0;
        float lit = min(1.0, ambient + totalLight) * contact;
        if (isFlat) lit *= groundAlpha;
        float glow = Texel(glowMap, tc).r;
        vec3 rgb = texel.rgb * mix(lit, 1.2, glow);

        if (isFlat) return vec4(rgb, groundAlpha);
        if (isGlass) return vec4(rgb, texel.a);
        if (isTall) return vec4(rgb, 1.0);
        // night shows it as drawn, day divides it by groundAlpha: between
        // them, both together leave it as bright as a tall thing
        return vec4(rgb * groundAlpha / mix(groundAlpha, 1.0, daylight), groundAlpha);
    }
]]
-- r: a region, or anything drawn from a sheet like one (image, scale,
-- glowImage, normalImage: the arch's shards, game/destruction.lua)
local function sendSpriteUniforms(r)
    local shader = regions.spriteShader
    shader:send("atlasHeight", r.image:getHeight())
    shader:send("spriteScale", r.scale)
    shader:send("zoom", camera.zoom)
    shader:send("groundAlpha", GROUND_ALPHA)
    shader:send("glowMap", r.glowImage)
    shader:send("normalMap", var.normal_maps and r.normalImage or normalmap.flat()) -- (Settings > Normal Maps)
    shader:send("daylight", daynight.daylight())
    shadow.sendLights(shader)
end

local function loadArt(r)
    local meta = require("gfx.regions." .. r.id)
    local data = cache.imageData(meta.image) -- (decoding the PNG is slow: cache.lua)
    r.data = data -- (what's opaque: game/destruction.lua's marks and shards)
    r.image = love.graphics.newImage(data)
    r.image:setFilter("nearest", "nearest")
    r.sprites = {}
    local iw, ih = r.image:getDimensions()
    for name, s in pairs(meta.sprites) do
        r.sprites[name] = {
            w = s.w, h = s.h, cat = s.cat, glass = s.glass, glow = s.glow,
            base = s.y + s.h - 2, -- the row its art stands on (2 px of padding below)
            quad = love.graphics.newQuad(s.x, s.y, s.w, s.h, iw, ih),
            -- where it meets the ground, which stops the flashlight; glass lets it through
            feet = not s.glass and footprint.of(data, s.x, s.y, s.w, s.h, s.h - 3) or nil,
        }
    end
    -- A typo in a pool would otherwise only show up as a hole in the layout
    local function check(list, where)
        for key, v in pairs(list) do
            if type(v) == "string" then
                assert(r.sprites[v], ("region %s: no sprite %q (%s)"):format(r.id, v, where))
            elseif type(v) == "table" then
                check(v, where .. "." .. tostring(key))
            end
        end
    end
    check({ edge = r.edge, posts = r.posts, portalLights = r.portalLights, flat = r.flat }, "")
    local L = r.layout
    for key, v in pairs(L) do
        if type(v) == "table" and key ~= "ground" then check(v, key) end
    end
    for name in pairs(L.companions or {}) do
        assert(r.sprites[name], ("region %s: companions for no sprite %q"):format(r.id, name))
    end
    r.flatSet = {}
    for _, name in ipairs(r.flat) do r.flatSet[name] = true end
    if meta.glowImage then
        r.glowImage = cache.newImage(meta.glowImage)
    else
        -- nothing here gives off light: one black texel says so everywhere
        local none = love.image.newImageData(1, 1)
        none:setPixel(0, 0, 0, 0, 0, 1)
        r.glowImage = love.graphics.newImage(none)
    end
    r.glowImage:setFilter("nearest", "nearest")
    -- (in name order, so it bakes the same every time), facades and the
    -- rest of the buildings with their brickwork, windows and trim deepest
    local names, quads, detail = {}, {}, {}
    for name in pairs(r.sprites) do names[#names + 1] = name end
    table.sort(names)
    for i, name in ipairs(names) do
        local s = r.sprites[name]
        quads[i] = s.quad
        detail[s.quad] = RELIEF[s.cat] or 1
    end
    r.normalImage = normalmap.of(r.image, quads, meta.image, detail)

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

-- A footprint's fixture, on the region's body: s = { x, y, w, h, item }
local function solidFixture(r, s)
    local fixture = love.physics.newFixture(r.body,
        love.physics.newRectangleShape(s[1] + s[3] / 2, s[2] + s[4] / 2, s[3], s[4]))
    fixture:setGroupIndex(collision.groups.map)
    fixture:setUserData({ type = "region", region = r.id, item = s.item })
    return fixture
end

-- A structure knocked down (game/destruction.lua): out of the world, its
-- light out
local function takeDown(item)
    if item.fixture and not item.fixture:isDestroyed() then item.fixture:destroy() end
    item.fixture = nil
    local items = item.region.items
    for i = #items, 1, -1 do
        if items[i] == item then
            table.remove(items, i)
            break
        end
    end
    if item.emitter then item.emitter.dead = true end
end

-- and back up (a save from before it fell)
local function putBack(item)
    if not item.fixture then item.fixture = solidFixture(item.region, item.solid) end
    local items = item.region.items
    items[#items + 1] = item
    if item.emitter then item.emitter.dead = nil end
end

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
    local tall = not flat and (TALL[s.cat] or s.glow or (s.h - 4) * scale >= OCCLUDE_HEIGHT)
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
    if s.feet and not flat then
        -- as deep as its collision, or as a prop's would be
        item.feet = footprint.place(s.feet, item.x, item.y, scale, depth and fh or math.max(10, math.min(h * 0.2, 70)))
    end
    if flat then
        -- underfoot: drawn with the ground, so whoever walks over it is on top
        r.flatBatch:setColor(unpack(color))
        r.flatBatch:add(s.quad, item.x, item.y, 0, scale, scale)
    else
        r.items[#r.items + 1] = item
    end
    if depth then
        local solid = { fx, base - fh, fw, fh }
        r.solids[#r.solids + 1] = solid
        mark(r.grid, fx, base - fh, fw, fh)
        if not flat then
            -- it can be shot to pieces and brought down (game/destruction.lua);
            -- its key is its place in the layout, the same every time
            r.structures[#r.structures + 1] = item
            item.key = r.id .. ":" .. #r.structures
            item.look, item.region, item.solid = r, r, solid
            item.qx, item.qy, item.qw, item.qh = s.quad:getViewport()
            item.scale, item.base, item.depth, item.glass = scale, base, fh, s.glass
            item.foot = { fx, base - fh, fx + fw, base }
            item.takeDown, item.putBack = takeDown, putBack
            solid.item = item
            destruction.register(item)
        end
    else
        mark(r.grid, x + w * 0.2, base - 6, w * 0.6, 6)
    end
    if s.glow then
        local g = s.glow
        -- about as wide as the part that glows; street lamps are lamps whatever their bulb
        local size = math.sqrt(g.area) * scale
        local lamp = s.cat == "light"
        r.emitters[#r.emitters + 1] = {
            x = item.x + g.x * scale, -- the glow itself
            y = item.y + g.y * scale,
            base = base,              -- the ground under it, where its light pools
            r = g.r, g = g.g, b = g.b,
            size = size,
            flicker = g.kind == "fire",
            intensity = lamp and 0.9 or math.min(1, 0.3 + size / 40),
            range = lamp and 240 or math.max(110, math.min(80 + size * 6, 280)),
            halo = lamp and 30 or math.max(14, math.min(size * 2.2, 70)), -- px
            lamp = lamp,
            phase = #r.emitters * 1.37,
        }
        item.emitter = r.emitters[#r.emitters] -- (out when it's knocked down)
    end
    return w, item
end

-- Ground kinds, one per ZONE x ZONE cell: which floor each cell gets
-- (layout.ground) and what may stand on it
local LOT, WALK, ROAD, PLAZA = 1, 2, 3, 4
-- and how light or dark each is (layout.ground.shade overrides)
local SHADE = { [LOT] = 1.0, [WALK] = 1.07, [ROAD] = 0.8, [PLAZA] = 1.05 }
-- and its colour on the minimap (ui/minimap.lua)
local PLAN = {
    [LOT] = { 0.12, 0.14, 0.11, 1 },
    [WALK] = { 0.31, 0.31, 0.33, 1 },
    [ROAD] = { 0.20, 0.20, 0.23, 1 },
    [PLAZA] = { 0.38, 0.34, 0.27, 1 },
}

-- A region's grass in cache/: how many fields, then each one's rect and
-- blade count and its vertex data (grass.lua's VERTEX_FORMAT), LZ4 packed
local GRASS_FIELD = "<ddddI4"

-- The key a region's grass is cached under: everything its layout follows
-- (this file, grass.lua, the region's sprite sizes, its seed and place). Nil
-- where fields keep no vertex data (the browser): it's grown every time.
local function grassKey(r, index)
    if not grass.public.VERTEX_SIZE then return nil end
    return cache.key(love.filesystem.read("game/regions.lua"), love.filesystem.read("systems/grass.lua"),
        love.filesystem.read("gfx/regions/" .. r.id .. ".lua"), r.id, r.seed, index, var.max_grass)
end

local function packGrass(fields)
    local parts = { love.data.pack("string", "<I4", #fields) }
    for _, f in ipairs(fields) do
        local n = f.vertexData and f.grassCount or 0
        parts[#parts + 1] = love.data.pack("string", GRASS_FIELD, f.x or 0, f.y or 0, f.width or 0, f.height or 0, n)
        if n > 0 then parts[#parts + 1] = f.vertexData:getString() end
    end
    return love.data.compress("string", "lz4", table.concat(parts))
end

-- The fields packGrass packed, each straight from its vertex data; false
-- if it won't unpack (and nothing's added)
local function unpackGrass(stored)
    local ok, data = pcall(love.data.decompress, "data", "lz4", stored)
    if not ok then return false end
    local size = grass.public.VERTEX_SIZE * 4 -- a blade's
    local count, pos = love.data.unpack("<I4", data)
    local fields = {}
    for i = 1, count do
        local x, y, w, h, n
        x, y, w, h, n, pos = love.data.unpack(GRASS_FIELD, data, pos)
        if pos - 1 + n * size > data:getSize() then return false end
        fields[i] = { x, y, w, h, n, pos - 1 }
        pos = pos + n * size
    end
    for _, f in ipairs(fields) do
        if f[5] > 0 then
            local field = grass.public.addFieldFrom(f[1], f[2], f[3], f[4], f[5],
                love.data.newDataView(data, f[6], f[5] * size))
            field.occludes = false
        end
    end
    return true
end

local function generate(r, index)
    local rng = love.math.newRandomGenerator(r.seed)
    local function rand(a, b) return a + rng:random() * (b - a) end
    local function pick(list) return list[rng:random(#list)] end
    local function width(name) return r.sprites[name].w * r.scale end
    local function height(name) return r.sprites[name].h * r.scale end
    local L = r.layout

    r.ox, r.oy = SPACING * (index - 1), 0
    local ox, oy = r.ox, r.oy
    local x0, y0 = ox - MARGIN, oy - MARGIN
    r.grid = newGrid(r)
    r.items, r.solids, r.emitters, r.structures = {}, {}, {}, {}
    r.flatBatch = love.graphics.newSpriteBatch(r.image, 256, "static")
    r.ground = groundMesh(r)

    ----------------------------------------------------------------------------
    -- The plan: streets, avenues, squares, and the ground under them
    ----------------------------------------------------------------------------

    local zcols, zrows = (W + 2 * MARGIN) / ZONE, (H + 2 * MARGIN) / ZONE
    local zone = {}
    for i = 0, zcols * zrows - 1 do zone[i] = LOT end
    local function setZone(kind, x, y, w, h)
        local c0 = math.max(0, math.floor((x - x0) / ZONE))
        local r0 = math.max(0, math.floor((y - y0) / ZONE))
        local c1 = math.min(zcols - 1, math.ceil((x + w - x0) / ZONE) - 1)
        local r1 = math.min(zrows - 1, math.ceil((y + h - y0) / ZONE) - 1)
        for row = r0, r1 do
            for col = c0, c1 do zone[row * zcols + col] = kind end
        end
    end
    local function zoneAt(x, y)
        return zone[math.floor((y - y0) / ZONE) * zcols + math.floor((x - x0) / ZONE)] or LOT
    end
    local function snapX(x) return x0 + math.floor((x - x0) / ZONE + 0.5) * ZONE end

    -- Streets: a row of buildings stands on each, a pavement (one cell) and a
    -- road (two) in front of it, all on the zone grid
    local streets = {}
    for i, f in ipairs(ROWS) do
        local cell = math.floor((oy + H * f - 24 - y0) / ZONE + 0.5)
        local walkTop = y0 + cell * ZONE
        -- across the road: a pavement, and the wall on its far edge
        streets[i] = { base = walkTop + 24, walkTop = walkTop, kerb = walkTop + ZONE,
            roadBottom = walkTop + 3 * ZONE, wall = walkTop + 4 * ZONE - 6, gaps = {} }
    end

    -- The portal stands at the bottom middle in a clear square
    r.portal = { x = math.floor(ox + W / 2 - 17), y = oy + H - 330 }
    r.spawn = { x = r.portal.x + 17, y = r.portal.y + 100 }
    local plaza = { x = r.portal.x - 230, y = r.portal.y - 140, w = 495, h = 330 }
    r.plaza = plaza -- (game/shop.lua's stalls stand on the squares)

    -- Avenues: two cross every street, lined up; the main one runs from the
    -- portal's square up to the middle street, where a landmark ends it
    local avenues = {
        { x = snapX(ox + W * rand(0.2, 0.27)), top = oy + TOP, bottom = oy + H * 0.84 },
        { x = snapX(ox + W * rand(0.73, 0.8)), top = oy + TOP, bottom = oy + H * 0.84 },
        { x = snapX(ox + W / 2) - ZONE, top = streets[2].roadBottom, bottom = plaza.y + 60, main = true },
    }
    -- A boss's lair (game/bosses.lua): the junction where the main avenue
    -- meets the middle street, in front of the landmark that ends it
    local main = avenues[3]
    r.lair = { x = main.x + ZONE, y = streets[2].kerb + ZONE }
    -- Out of the way, in the roads: where the side avenues cross the top and
    -- bottom streets, and the top street's middle (game/armor.lua's second sets)
    local function roadAt(x, s) return { x = x + ZONE, y = s.kerb + ZONE } end
    r.outskirts = {
        topLeft = roadAt(avenues[1].x, streets[1]), topRight = roadAt(avenues[2].x, streets[1]),
        topMiddle = roadAt(main.x, streets[1]),
        bottomLeft = roadAt(avenues[1].x, streets[3]), bottomRight = roadAt(avenues[2].x, streets[3]),
    }
    for _, a in ipairs(avenues) do
        a.w = 2 * ZONE
        for _, s in ipairs(streets) do
            if a.top < s.base and a.bottom > s.base then
                s.gaps[#s.gaps + 1] = { a.x - 36, a.x + a.w + 36 }
            end
        end
    end

    -- Landmarks: at the end of the main avenue, then the top street's middle
    -- (or parked in a road, for a bus)
    local landmarks = {}
    for i = 1, #L.landmarks do landmarks[i] = L.landmarks[i] end
    for i = #landmarks, 2, -1 do
        local j = rng:random(i)
        landmarks[i], landmarks[j] = landmarks[j], landmarks[i]
    end
    local slots = {}
    if L.landmarkIn == "row" then
        for i, streetIndex in ipairs({ 2, 1 }) do
            local name = landmarks[i]
            if name then
                local s = streets[streetIndex]
                local w = width(name)
                local x = ox + W / 2 - w / 2
                s.gaps[#s.gaps + 1] = { x - 50, x + w + 50 }
                slots[#slots + 1] = { name = name, x = x, w = w, street = s }
            end
        end
    end

    -- The ground: lots everywhere, then pavements, roads and squares
    for _, s in ipairs(streets) do
        setZone(WALK, ox, s.walkTop, W, ZONE)
        setZone(WALK, ox, s.roadBottom, W, ZONE) -- the far pavement, under the wall
    end
    for _, a in ipairs(avenues) do
        setZone(WALK, a.x - ZONE, a.top, ZONE, a.bottom - a.top)
        setZone(WALK, a.x + a.w, a.top, ZONE, a.bottom - a.top)
    end
    for _, s in ipairs(streets) do
        setZone(ROAD, ox, s.kerb, W, 2 * ZONE)
    end
    for _, a in ipairs(avenues) do
        setZone(ROAD, a.x, a.top, a.w, a.bottom - a.top)
    end
    setZone(PLAZA, plaza.x, plaza.y, plaza.w, plaza.h)
    for _, slot in ipairs(slots) do
        setZone(PLAZA, slot.x - 50, slot.street.walkTop, slot.w + 100, ZONE) -- its forecourt
    end
    -- the pool on one side of the portal's square, a square on the other
    local poolSide = rng:random() < 0.5 and 0.22 or 0.78
    local square
    if L.square then
        local cx = snapX(ox + W * (1 - poolSide))
        -- below the bottom street's wall
        local top = y0 + math.ceil((streets[3].wall + 40 - y0) / ZONE) * ZONE
        square = { x = cx - 3 * ZONE, y = top, w = 6 * ZONE, h = 4 * ZONE }
        setZone(PLAZA, square.x, square.y, square.w, square.h)
    end
    r.square = square

    -- Which floor each cell gets: one texel per cell, the weight of floor
    -- layers 1-3 in r, g, b (layer 0 lies under everything)
    local g = L.ground
    local zdata = love.image.newImageData(zcols, zrows)
    for row = 0, zrows - 1 do
        for col = 0, zcols - 1 do
            local kind = zone[row * zcols + col]
            local k
            if kind == ROAD then
                k = g.road
                if g.roadAlt and love.math.noise(col * 0.31 + r.seed * 0.01, row * 0.31) > 0.62 then k = g.roadAlt end
            elseif kind == WALK then
                k = g.walk
            elseif kind == PLAZA then
                k = g.plaza
            else
                k = g.lot
                if g.lotAlt and love.math.noise(col * 0.14 + r.seed * 0.013, row * 0.14 + 3.1) > 0.58 then
                    k = g.lotAlt
                end
            end
            k = math.min(k, r.floorLayers - 1)
            local shade = g.shade and g.shade[kind] or SHADE[kind]
            zdata:setPixel(col, row, k == 1 and 1 or 0, k == 2 and 1 or 0, k == 3 and 1 or 0, shade / 1.5)
        end
    end
    r.zones = love.graphics.newImage(zdata)
    r.zones:setFilter(g.hard and "nearest" or "linear", g.hard and "nearest" or "linear")
    r.zoneSize = { zcols, zrows }
    -- the street plan again for the minimap, a texel per cell from (x0, y0)
    local pdata = love.image.newImageData(zcols, zrows)
    pdata:mapPixel(function(col, row) return unpack(PLAN[zone[row * zcols + col]]) end)
    r.plan = { image = love.graphics.newImage(pdata), x = x0, y = y0, cell = ZONE }
    r.plan.image:setFilter("nearest", "nearest")
    r.hardGround = g.hard and 1 or 0
    r.rough = g.rough or 0.8

    ----------------------------------------------------------------------------
    -- Placing things
    ----------------------------------------------------------------------------

    local function tryPlace(name, x, base) return place(r, name, x, base, true) end
    local function inAvenue(x0_, x1_, pad)
        for _, a in ipairs(avenues) do
            if x1_ > a.x - pad and x0_ < a.x + a.w + pad then return a end
        end
    end
    -- What lies beside a thing: one or two of its companions, in front of it
    local function companions(name, x, w, base)
        local list = L.companions and L.companions[name]
        if not list then return end
        for _ = 1, rng:random(1, 2) do
            local c = pick(list)
            local cw = width(c)
            tryPlace(c, rand(x - cw * 0.6, x + w - cw * 0.4), base + rand(8, 30))
        end
    end

    -- The portal's lights, either side of it
    if #r.portalLights == 2 then
        local base = r.portal.y + 58
        place(r, r.portalLights[1], r.portal.x - 50 - width(r.portalLights[1]), base)
        place(r, r.portalLights[2], r.portal.x + 85, base)
    end
    mark(r.grid, plaza.x, plaza.y, plaza.w, plaza.h)
    if square then mark(r.grid, square.x, square.y, square.w, square.h) end

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

    -- Every building and landmark that went up: { name, x, w, base }
    local fronts = {}
    for _, slot in ipairs(slots) do
        place(r, slot.name, slot.x, slot.street.base + 6)
        fronts[#fronts + 1] = { name = slot.name, x = slot.x, w = slot.w, base = slot.street.base + 6, landmark = true }
    end

    -- Blocks of buildings shoulder to shoulder along each street: a corner at
    -- each end (where the region has them), towers or arches between now and
    -- then, an alley between blocks. A stretch too short for a building gets
    -- a wall where one fell down.
    local minFacade = math.huge
    for _, n in ipairs(L.facades) do minFacade = math.min(minFacade, width(n)) end
    local function pickFit(list, room, avoid)
        local options = {}
        for _, n in ipairs(list) do
            if width(n) <= room and n ~= avoid then options[#options + 1] = n end
        end
        if #options == 0 and avoid then return pickFit(list, room) end
        return #options > 0 and pick(options) or nil
    end
    local alleys = {}
    for _, s in ipairs(streets) do
        table.sort(s.gaps, function(a, b) return a[1] < b[1] end)
        local stretches, from = {}, ox + 30
        for _, gap in ipairs(s.gaps) do
            if gap[1] > from then stretches[#stretches + 1] = { from, gap[1] } end
            from = math.max(from, gap[2])
        end
        if ox + W - 30 > from then stretches[#stretches + 1] = { from, ox + W - 30 } end

        for _, st in ipairs(stretches) do
            local x, stop = st[1], st[2]
            while stop - x >= minFacade do
                -- one block
                local size, built, prev = rng:random(3, 6), 0, nil
                while stop - x >= minFacade do
                    local room = stop - x
                    local last = built + 1 >= size or room - minFacade < minFacade
                    local name
                    if (built == 0 or last) and #L.corners > 0 then
                        name = pickFit(L.corners, room, prev and prev[1])
                    elseif built > 0 and not last and L.separators and #L.separators > 0
                        and not (prev and prev.separator) and rng:random() < (L.separatorChance or 0) then
                        name = pickFit(L.separators, room)
                        if name then name = { name, separator = true } end
                    end
                    if not name then name = pickFit(L.facades, room, prev and prev[1]) end
                    if not name then break end
                    local entry = type(name) == "table" and name or { name }
                    local w = width(entry[1])
                    place(r, entry[1], x, s.base + (entry.separator and 4 or 0))
                    if not entry.separator then
                        fronts[#fronts + 1] = { name = entry[1], x = x, w = w, base = s.base }
                    end
                    x = x + w - 3 * r.scale
                    built, prev = built + 1, entry
                    if last then break end
                end
                -- an alley, if another block fits after it
                if stop - x >= minFacade * 3 + 60 then
                    local aw = rand(60, 96)
                    alleys[#alleys + 1] = { x0 = x, x1 = x + aw, street = s }
                    x = x + aw
                else
                    break
                end
            end
            -- the stretch's end: a fallen building's wall, where there's one
            if L.infill and stop - x > 40 then
                local name = pickFit(L.infill, stop - x)
                if name then place(r, name, x + (stop - x - width(name)) / 2, s.base) end
            end
        end
    end

    -- Gates flanked by a pair; against other fronts, a thing or two (bins,
    -- banners, a lectern) with what lies beside it
    local gates = {}
    for _, n in ipairs(L.gates or {}) do gates[n] = true end
    for _, f in ipairs(fronts) do
        if gates[f.name] and L.flank then
            local pair = pick(L.flank)
            local pw = width(pair)
            local cx = f.x + f.w / 2
            tryPlace(pair, cx - f.w * 0.34 - pw / 2, f.base + 18)
            tryPlace(pair, cx + f.w * 0.34 - pw / 2, f.base + 18)
            local carpet = L.companions and L.companions[f.name]
            if carpet then
                local c = pick(carpet)
                tryPlace(c, cx - width(c) / 2, f.base + height(c) + 6)
            end
        elseif not f.landmark then
            companions(f.name, f.x, f.w, f.base)
            if L.wall and #L.wall > 0 and rng:random() < (L.wallChance or 0) then
                local name = pick(L.wall)
                local w = width(name)
                local x = rand(f.x + 6, f.x + math.max(6, f.w - w - 6))
                local base = f.base + rand(10, 18)
                if tryPlace(name, x, base) then companions(name, x, w, base) end
            end
        end
    end

    -- Each road's far side: a wall along the back of its pavement, so the road
    -- runs between buildings and wall. It breaks where an avenue crosses (a
    -- post either side) and every few lengths for a gateway into the yard
    -- behind, sometimes with a gate across it.
    -- where a wall at y must open: an avenue crossing, or the portal's square
    local openings = {}
    for _, a in ipairs(avenues) do openings[#openings + 1] = { x = a.x, w = a.w, top = a.top, bottom = a.bottom } end
    openings[#openings + 1] = { x = plaza.x + 30, w = plaza.w - 60, top = plaza.y, bottom = plaza.y + plaza.h }
    local function avenueAt(x0_, x1_, y, pad)
        for _, a in ipairs(openings) do
            if y > a.top and y < a.bottom and x1_ > a.x - pad and x0_ < a.x + a.w + pad then return a end
        end
    end
    local function post(x, base, side)
        if #r.posts == 0 then return end
        local name = pick(r.posts)
        place(r, name, side < 0 and x - width(name) or x, base + 4)
    end
    for _, s in ipairs(streets) do
        local x, run, nextGate = ox - 20, 0, rng:random(4, 7)
        while x < ox + W + 20 do
            local name = pick(r.edge)
            local w = width(name)
            local a = avenueAt(x, x + w, s.wall, 30)
            if a then
                post(a.x - 30, s.wall, -1)
                post(a.x + a.w + 30, s.wall, 1)
                x, run = a.x + a.w + 30 + (#r.posts > 0 and width(r.posts[1]) or 0), 0
            elseif run >= nextGate and x < ox + W - 200 then
                local gw = rand(84, 112)
                if L.wallGates and rng:random() < 0.3 then
                    local gate = pickFit(L.wallGates, gw + 24)
                    if gate then place(r, gate, x + (gw - width(gate)) / 2, s.wall) end
                end
                x, run, nextGate = x + gw, 0, rng:random(4, 7)
            else
                place(r, name, x, s.wall)
                x, run = x + w - 3 * r.scale, run + 1
            end
        end
    end
    -- The avenues lined with posts between the streets, like a colonnade
    local function crossesStreet(y)
        for _, s in ipairs(streets) do
            if y > s.walkTop - 40 and y < s.wall + 30 then return true end
        end
        return y > plaza.y - 20 or (square and y > square.y - 20 and y < square.y + square.h + 20)
    end
    if #r.posts > 0 then
        for _, a in ipairs(avenues) do
            local y = a.top + 60
            while y < a.bottom - 10 do
                if not crossesStreet(y) then
                    local name = pick(r.posts)
                    local w = width(name)
                    tryPlace(name, a.x - ZONE / 2 - w / 2, y)
                    tryPlace(name, a.x + a.w + ZONE / 2 - w / 2, y)
                end
                y = y + 130
            end
        end
    end

    -- Alleys: some fenced off across their mouth
    for _, a in ipairs(alleys) do
        if L.alleyFences and rng:random() < 0.55 then
            local name = pickFit(L.alleyFences, a.x1 - a.x0 + 30)
            if name then
                local w = width(name)
                place(r, name, (a.x0 + a.x1) / 2 - w / 2, a.street.base + 2)
                companions(name, (a.x0 + a.x1) / 2 - w / 2, w, a.street.base + 2)
            end
        end
    end

    -- Along each street's kerb: lights at a steady spacing (not in the
    -- avenues' roads), small things between them, rails at the road's edge
    for _, s in ipairs(streets) do
        local spacing = L.lightSpacing or 300
        local x = ox + rand(50, 90)
        while x < ox + W - 60 do
            if not inAvenue(x, x + 40, 24) then
                if #L.lights > 0 then
                    local name = pick(L.lights)
                    tryPlace(name, x, s.kerb - 2)
                end
                -- between this light and the next
                local mx = x + spacing / 2 + rand(-30, 30)
                if L.kerb and #L.kerb > 0 and rng:random() < (L.kerbChance or 0)
                    and not inAvenue(mx, mx + 60, 24) then
                    local name = pick(L.kerb)
                    tryPlace(name, mx, s.kerb - 4)
                end
                if L.kerbFlat and rng:random() < 0.35 then
                    local name = pick(L.kerbFlat)
                    if not inAvenue(mx, mx + width(name), 16) then tryPlace(name, mx, s.kerb + 20) end
                end
            end
            x = x + spacing + rand(-20, 20)
        end
    end
    -- and down both sides of each avenue, between the streets
    local function onStreet(y)
        for _, s in ipairs(streets) do
            if y > s.kerb - 12 and y < s.roadBottom + 12 then return true end
        end
    end
    for _, a in ipairs(avenues) do
        if #L.lights > 0 then
            local y, left = a.top + 90, true
            while y < a.bottom - 20 do
                local name = pick(L.lights)
                local x = left and a.x - width(name) - 6 or a.x + a.w + 6
                if not onStreet(y) then tryPlace(name, x, y) end
                left = not left
                y = y + (L.lightSpacing or 300) * 0.6
            end
        end
    end

    -- Roads: cars parked in the near lane, road works in the far lane of
    -- one or two, manholes and the like down the middle
    for _, s in ipairs(streets) do
        if L.parked and #L.parked > 0 then
            local x = ox + rand(40, 120)
            while x < ox + W - 160 do
                local name = pick(L.parked)
                local w = width(name)
                local a = inAvenue(x, x + w, 20)
                if a then
                    x = a.x + a.w + 24
                elseif rng:random() < (L.parkedChance or 0) then
                    if tryPlace(name, x, s.kerb + 58) then x = x + w + rand(16, 50) else x = x + 60 end
                else
                    x = x + rand(110, 220)
                end
            end
        end
        if L.roadFlat and #L.roadFlat > 0 then
            local x = ox + rand(80, 200)
            while x < ox + W - 80 do
                local name = pick(L.roadFlat)
                if not inAvenue(x, x + width(name), 10) and rng:random() < 0.7 then
                    tryPlace(name, x, s.kerb + ZONE + height(name) / 2)
                end
                x = x + rand(260, 420)
            end
        end
    end
    if L.roadworks and #L.roadworks > 0 then
        for _ = 1, rng:random(1, 2) do
            local s = pick(streets)
            local x = rand(ox + 120, ox + W - 600)
            if not inAvenue(x, x + 480, 30) then
                for _ = 1, rng:random(2, 4) do
                    local name = pick(L.roadworks)
                    local w = place(r, name, x, s.roadBottom - 8, true)
                    x = x + (w or width(name)) + rand(-6, 8)
                end
            end
        end
    end
    if L.landmarkIn == "road" then
        -- a landmark that's a vehicle: left in a road, half across a lane
        for i, name in ipairs(landmarks) do
            local s = streets[(i % #streets) + 1]
            for _ = 1, 10 do
                local x = rand(ox + 200, ox + W - 200 - width(name))
                if not inAvenue(x, x + width(name), 30) and tryPlace(name, x, s.kerb + rand(80, 110)) then
                    companions(name, x, width(name), s.kerb + 100)
                    break
                end
            end
        end
    end

    -- Squares: the portal's has a piece at each corner; the other has a
    -- centrepiece with what goes round it, corner pieces and edges
    local sq = L.square
    if sq and sq.ring then
        local name = pick(sq.ring)
        local w = width(name)
        place(r, name, plaza.x + 20, plaza.y + 70)
        place(r, name, plaza.x + plaza.w - 20 - w, plaza.y + 70)
        place(r, name, plaza.x + 20, plaza.y + plaza.h - 10)
        place(r, name, plaza.x + plaza.w - 20 - w, plaza.y + plaza.h - 10)
        for _, slot in ipairs(slots) do -- either side of a landmark's forecourt
            place(r, name, slot.x - 50, slot.street.kerb - 4)
            place(r, name, slot.x + slot.w + 50 - w, slot.street.kerb - 4)
        end
    end
    if square then
        local cx, cy = square.x + square.w / 2, square.y + square.h / 2
        if sq.feature then
            local name = pick(sq.feature)
            local w, h = width(name), height(name)
            place(r, name, cx - w / 2, cy + h * 0.25)
            companions(name, cx - w / 2, w, cy + h * 0.25)
            if sq.centre then
                local c = pick(sq.centre)
                place(r, c, cx - width(c) / 2, cy + h * 0.25 + height(c) + 10)
            end
        end
        if sq.ring then
            local name = pick(sq.ring)
            local w = width(name)
            place(r, name, square.x + 14, square.y + 60)
            place(r, name, square.x + square.w - 14 - w, square.y + 60)
            place(r, name, square.x + 14, square.y + square.h - 6)
            place(r, name, square.x + square.w - 14 - w, square.y + square.h - 6)
        end
        if sq.edge then
            local name = pick(sq.edge)
            place(r, name, cx - width(name) - 10, square.y + square.h - 4)
            place(r, name, cx + 10, square.y + square.h - 4)
        end
    end

    -- Water: the pool by the portal's square, puddles where water lies (on
    -- roads mostly, some on open ground)
    local px, py = ox + W * poolSide, oy + H * 0.86
    local prx, pry = rand(170, 230), rand(70, 90)
    puddle.add(px, py, prx, pry)
    mark(r.grid, px - prx, py - pry, prx * 2, pry * 2)
    for i = 1, r.puddles do
        for _ = 1, 16 do
            local rx, ry = rand(26, 70), rand(12, 28)
            local x, y
            if i % 5 < 3 then
                local s = pick(streets)
                x, y = rand(ox + 80, ox + W - 80), rand(s.kerb + ry + 6, s.roadBottom - ry - 6)
            else
                x, y = rand(ox + 80, ox + W - 80), rand(oy + TOP + 60, oy + H - 60)
            end
            local kind = zoneAt(x, y)
            if (kind == ROAD or kind == LOT) and isFree(r.grid, x - rx, y - ry, rx * 2, ry * 2) then
                puddle.add(x, y, rx, ry)
                mark(r.grid, x - rx, y - ry, rx * 2, ry * 2)
                break
            end
        end
    end

    -- Open ground: things left lying about in clumps, not evenly
    local clumpX, clumpY = r.seed * 0.17, r.seed * 0.29
    for _ = 1, 140 do
        local x, y = rand(ox + 60, ox + W - 140), rand(oy + TOP + 80, oy + H - 40)
        if zoneAt(x, y) == LOT and love.math.noise(x * 0.004 + clumpX, y * 0.004 + clumpY) > 0.55 then
            if L.lot and #L.lot > 0 and rng:random() < 0.3 then
                local name = pick(L.lot)
                if tryPlace(name, x, y) then companions(name, x, width(name), y) end
            elseif L.lotFlat and #L.lotFlat > 0 then
                tryPlace(pick(L.lotFlat), x, y)
            end
        end
    end

    -- Grass in ragged patches on open ground: each its own field, so only the
    -- ones on screen are drawn. Laying it out is most of the time a region
    -- takes to load, so it grows from its own generator, the same blades
    -- every time, and they're kept in cache/ (cache.lua) for the next launch.
    local key = grassKey(r, index)
    local stored = key and cache.get("grass-" .. r.id, key)
    if not (stored and unpackGrass(stored)) then
        local blades = love.math.newRandomGenerator(r.seed, 1)
        local function random() return blades:random() end
        local grown = {}
        local nx, ny = r.seed * 0.37, r.seed * 0.11
        for _ = 1, r.grass.patches do
            for _ = 1, 8 do
                local cx, cy = rand(ox + 80, ox + W - 80), rand(oy + TOP + 80, oy + H - 60)
                if zoneAt(cx, cy) == LOT and freeAt(r.grid, cx, cy) then
                    local hw, hh = rand(110, 230), rand(70, 140)
                    local field = grass.public.addField(cx - hw, cy - hh, hw * 2, hh * 2,
                        math.floor(hw * hh * 4 / 18),
                        function(x, y)
                            local d = ((x - cx) / hw) ^ 2 + ((y - cy) / hh) ^ 2
                            return d < 1 and zoneAt(x, y) == LOT and freeAt(r.grid, x, y)
                                and love.math.noise(x * 0.02 + nx, y * 0.02 + ny) > 0.3 + 0.55 * d
                        end, r.grass.tint, random)
                    field.occludes = false -- ankle high: light passes over it
                    grown[#grown + 1] = field
                    break
                end
            end
        end
        if key then cache.put("grass-" .. r.id, key, packGrass(grown)) end
    end

    -- Physics: every footprint, and a fence just inside the walls
    r.body = love.physics.newBody(world, 0, 0, "static")
    for _, s in ipairs(r.solids) do
        local fixture = solidFixture(r, s)
        if s.item then s.item.fixture = fixture end
    end
    local fence = love.physics.newFixture(r.body, love.physics.newChainShape(true,
        ox + 24, oy + TOP - 8, ox + W - 24, oy + TOP - 8,
        ox + W - 24, oy + H - 40, ox + 24, oy + H - 40))
    fence:setGroupIndex(collision.groups.map)
    fence:setUserData({ type = "region", region = r.id })

    r.grid = nil -- only needed while laying out (and by the grass, which is built)
end

-- A soft spot of light, its strength in rgb and alpha 0, so drawn with
-- ("add", "premultiplied") it brightens what's there and leaves the scene's
-- alpha (what the GI pass reads as walls) alone
local function glowImage()
    local n = 64
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

function regions.load()
    regions.time = 0
    regions.glow = glowImage()
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
    regions.current = here

    regions.time = regions.time + dt
    -- What gives off light on screen lights the scene this frame, from the
    -- ground under it (so faces it's behind stay dark: see SPRITE_SHADER)
    if here.emitters then
        local x0, y0, x1, y1 = regions.view(280)
        for _, e in ipairs(here.emitters) do
            if not e.dead and e.x > x0 and e.x < x1 and e.base > y0 and e.y < y1 then
                e.now = e.flicker and 0.8 + 0.2 * love.math.noise(regions.time * 7, e.phase) or 1
                shadow.addTransientLight(e.x, e.base + 8, e.intensity * e.now, e.range)
            end
        end
    end
end

-- Draw each emitter on screen: fn(e, strength) places the spot
local function drawEmitters(r, fn)
    local x0, y0, x1, y1 = regions.view(300)
    love.graphics.push("all")
    love.graphics.setShader()
    love.graphics.setBlendMode("add", "premultiplied")
    for _, e in ipairs(r.emitters) do
        if not e.dead and e.x > x0 and e.x < x1 and e.base > y0 and e.y < y1 then
            fn(e, e.intensity * (e.now or 1) * daynight.glow())
        end
    end
    love.graphics.pop()
end

-- Its colour pooling on the ground around its foot
local function drawPool(e, k)
    local radius = e.range * 0.5
    k = k * (e.lamp and 0.3 or 0.22)
    love.graphics.setColor(e.r * k, e.g * k, e.b * k, 1)
    love.graphics.draw(regions.glow, e.x - radius, e.base + 8 - radius * 0.55, 0,
        radius * 2 / 64, radius * 1.1 / 64)
end

-- A halo round the glowing part itself
local function drawHalo(e, k)
    local radius = e.halo
    k = k * (e.lamp and 0.65 or 0.4)
    love.graphics.setColor(e.r * k, e.g * k, e.b * k, 1)
    love.graphics.draw(regions.glow, e.x - radius, e.y - radius, 0, radius * 2 / 64, radius * 2 / 64)
end

--- Halos round everything that gives off light, over the sorted sprites
--- (under the camera transform).
function regions.drawGlows()
    if not var.lamp_glows then return end -- (Settings > Lamp Glows)
    local x0, y0, x1, y1 = regions.view(0)
    for _, r in ipairs(regions.list) do
        if r.emitters and #r.emitters > 0 and overlaps(r, x0, y0, x1, y1) then
            drawEmitters(r, drawHalo)
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
            groundShader:send("hard", r.hardGround)
            groundShader:send("rough", r.rough)
            groundShader:send("seed", { r.seed % 97, r.seed % 89 })
            groundShader:send("zones", r.zones)
            groundShader:send("zoneSize", r.zoneSize)
            groundShader:send("zoneScale", TILE / ZONE)
            shadow.drawTiled(groundShader, function() love.graphics.draw(r.ground) end)

            -- grates, carpets, rubble: part of the ground, cut out over it
            sendSpriteUniforms(r)
            love.graphics.setShader(regions.spriteShader)
            local mode, alphaMode = love.graphics.getBlendMode()
            love.graphics.setBlendMode("replace", "premultiplied")
            love.graphics.draw(r.flatBatch)
            love.graphics.setBlendMode(mode, alphaMode)
            if #r.emitters > 0 and var.lamp_glows then
                drawEmitters(r, drawPool) -- light spilling onto the ground
            end
            love.graphics.setShader(groundShader)
        end
    end
    if prev then
        love.graphics.setShader(prev)
    end
end

--- Before region sprite `item` is drawn (or what's left of it, its shards'
--- mesh: the same texels at the same place), with the sprite shader bound
--- under the camera transform: send it only the lights that reach where it's
--- lit (shadow.cullLights). SPRITE_SHADER lights an upright texel from the
--- ground under it, on the sprite's base row, two texels above its bottom;
--- the two rows of padding below that, from where they are.
function regions.cullLights(item)
    local _, _, qw, qh = item.quad:getViewport()
    local bottom = item.y + qh * item.scale_y
    local x0, y0 = love.graphics.transformPoint(item.x, bottom - 2 * item.scale_y)
    local x1, y1 = love.graphics.transformPoint(item.x + qw * item.scale_x, bottom)
    shadow.cullLights(regions.spriteShader, math.min(x0, x1) - 1, math.min(y0, y1) - 1,
        math.max(x0, x1) + 1, math.max(y0, y1) + 1)
end

--- Bind the sprite shader for things drawn from `look`'s sheet (a region,
--- or another with its fields: see sendSpriteUniforms).
function regions.useLook(look)
    sendSpriteUniforms(look)
    love.graphics.setShader(regions.spriteShader)
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

--- fn(feet) for the footprint of each region sprite in the world rect
--- x0, y0 - x1, y1: where it stands, a flat list {x0, y0, x1, y1, ...} of
--- segments in world px (lib/graphics/footprint.lua).
function regions.eachFoot(x0, y0, x1, y1, fn)
    for _, r in ipairs(regions.list) do
        if r.items and overlaps(r, x0, y0, x1, y1) then
            for _, item in ipairs(r.items) do
                if item.feet and item.x < x1 and item.x1 > x0 and item.y < y1 and item.y1 > y0 then
                    fn(item.feet)
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
