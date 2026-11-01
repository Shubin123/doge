--[[
  The courtyard's ground (the home map's tile map, map.map): always grass,
  from TX Tileset Grass's 16 px tiles, laid out so it looks grown rather
  than dealt:

    * the sheet's tiles are sorted by what's on them when it loads (plain
      grass, tufts, pebbles, flowers, paving slabs whole or broken), so the
      layout asks for a kind of tile, not a number;
    * grass is mostly plain, with tufts thick in clumps and thin between
      (a noise field), flowers in a few patches, and pebbles scattered,
      more of them along the paths;
    * flagstone paths join the portal, the house's door, the car, and lead
      off east towards the black hole and away south and west. Their middle
      is whole slabs; at their edges slabs are broken and missing, with the
      odd stray one in the grass beside them; and there's a paved apron in
      front of the door and a pad where the car parks.

  The same seed gives the same courtyard on every machine. Laying it out
  takes a moment, so the result is kept in util/cache.lua, keyed by this
  file and the sheet: the next launch just reads it back.
]]
local cache = require("util.cache")

local courtyard = {}

courtyard.TILESET = "gfx/TileSet/TX Tileset Grass.png"
local T = 16
-- The tile map's size in tiles, and where its first tile lands in the world
-- (draw.lua draws it at -11800, 100; createMap puts the origin at -9800, 2100):
-- the courtyard runs -2000..3760 across and -2000..2800 down
courtyard.COLS, courtyard.ROWS = 360, 300
local ORIGIN_X, ORIGIN_Y = -2000, -2000
local SEED = 4242

-- Paths as world-space points, and how wide their whole slabs run (px from
-- the middle). Bends are smoothed and wobbled when they're laid.
local PATHS = {
    { width = 20, points = { { 307, 212 }, { 330, 300 }, { 420, 360 }, { 500, 384 } } },     -- portal to the door
    { width = 22, points = { { 500, 384 }, { 515, 560 }, { 470, 820 }, { 520, 1100 }, { 480, 1700 },
        { 540, 2300 }, { 500, 2900 } } },                                                         -- south
    { width = 18, points = { { 500, 400 }, { 600, 404 } } },                                  -- door to the car
    { width = 18, points = { { 610, 410 }, { 820, 430 }, { 1060, 360 }, { 1290, 310 } } },    -- east, to the black hole
    { width = 16, points = { { 330, 300 }, { 150, 330 }, { -60, 300 }, { -500, 360 }, { -1100, 290 },
        { -2100, 330 } } },                                                                       -- west
}
local PADS = {
    { 466, 366, 70, 40 },  -- the apron before the door (x, y, w, h)
    { 556, 352, 100, 70 }, -- where the car parks
}

-- Sort the sheet's tiles into kinds by their pixels
local function classify(data)
    local cols, rows = data:getWidth() / T, data:getHeight() / T
    -- the grass colour: tile 1's average
    local gr, gg, gb = 0, 0, 0
    for y = 0, T - 1 do
        for x = 0, T - 1 do
            local r, g, b = data:getPixel(x, y)
            gr, gg, gb = gr + r, gg + g, gb + b
        end
    end
    gr, gg, gb = gr / (T * T), gg / (T * T), gb / (T * T)

    local kinds = { plain = {}, tuft = {}, pebble = {}, flower = {}, slab = {}, broken = {} }
    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            local grey, flower, odd, tuft = 0, 0, 0, 0
            for y = row * T, row * T + T - 1 do
                for x = col * T, col * T + T - 1 do
                    local r, g, b, a = data:getPixel(x, y)
                    local hi, lo = math.max(r, g, b), math.min(r, g, b)
                    if a < 0.5 then
                        odd = odd + 1
                    elseif hi - lo < 0.09 and (r + g + b) / 3 > 0.36 then
                        grey = grey + 1
                    elseif r > 0.65 and r - b > 0.3 and g > 0.3 and math.abs(g - gg) > 0.08 then
                        flower = flower + 1
                    elseif b > g + 0.08 and r > g then
                        odd = odd + 1 -- stray marks on the sheet
                    elseif math.abs(r - gr) + math.abs(g - gg) + math.abs(b - gb) > 0.07 then
                        tuft = tuft + 1
                    end
                end
            end
            local id = row * cols + col + 1
            local kind
            if odd > 0 then
                kind = nil
            elseif grey >= 150 then
                kind = "slab"
            elseif grey >= 60 then
                kind = "broken"
            elseif flower > 0 then
                kind = "flower"
            elseif grey > 0 then
                kind = "pebble"
            elseif tuft > 6 then
                kind = "tuft"
            else
                kind = "plain"
            end
            if kind then table.insert(kinds[kind], id) end
        end
    end
    return kinds
end

-- A path's points smoothed into short steps, each bend wobbling a little
local function trace(path, rng)
    local pts = path.points
    local out = {}
    for i = 1, #pts - 1 do
        local x0, y0 = pts[i][1], pts[i][2]
        local x1, y1 = pts[i + 1][1], pts[i + 1][2]
        local len = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
        local nx, ny = -(y1 - y0) / len, (x1 - x0) / len
        local steps = math.max(2, math.floor(len / 12))
        local phase, amp = rng:random() * 6.28, math.min(14, len * 0.05)
        for s = 0, steps - 1 do
            local t = s / steps
            local wobble = math.sin(t * math.pi) * math.sin(t * 6.28 + phase) * amp
            out[#out + 1] = { x0 + (x1 - x0) * t + nx * wobble, y0 + (y1 - y0) * t + ny * wobble }
        end
    end
    out[#out + 1] = { pts[#pts][1], pts[#pts][2] }
    return out
end

-- The layout stops looking at a tile's distance from the paths at NEAR px
-- (pebbles thin out there), so a tile only measures the segments that could
-- be that close: the courtyard is cut into CELL px cells, each listing the
-- segments that come within NEAR of it. Same tiles as measuring them all.
local NEAR, CELL = 60, 64

-- The traced paths' segments ({ ax, ay, bx, by, width }) by cell, and how
-- many cells a row has
local function binSegments(traced, cols, rows)
    local nx, ny = math.ceil(cols * T / CELL), math.ceil(rows * T / CELL)
    local bins = {}
    for _, p in ipairs(traced) do
        local pts = p.points
        local reach = p.width + NEAR + 1 -- a px to spare
        for i = 1, #pts - 1 do
            local ax, ay, bx, by = pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]
            local segment = { ax, ay, bx, by, p.width }
            local c0 = math.max(0, math.floor((math.min(ax, bx) - reach - ORIGIN_X) / CELL))
            local c1 = math.min(nx - 1, math.floor((math.max(ax, bx) + reach - ORIGIN_X) / CELL))
            local r0 = math.max(0, math.floor((math.min(ay, by) - reach - ORIGIN_Y) / CELL))
            local r1 = math.min(ny - 1, math.floor((math.max(ay, by) + reach - ORIGIN_Y) / CELL))
            for r = r0, r1 do
                for c = c0, c1 do
                    local bin = bins[r * nx + c]
                    if not bin then
                        bin = {}
                        bins[r * nx + c] = bin
                    end
                    bin[#bin + 1] = segment
                end
            end
        end
    end
    return bins, nx
end

-- How far (px) world point x, y is from the nearest path's middle, minus
-- that path's width: <= 0 is on the slabs (math.huge past NEAR from them all)
local function pathDistance(bins, nx, x, y)
    local best = math.huge
    local bin = bins[math.floor((y - ORIGIN_Y) / CELL) * nx + math.floor((x - ORIGIN_X) / CELL)]
    for _, s in ipairs(bin or {}) do
        local ax, ay, bx, by = s[1], s[2], s[3], s[4]
        local dx, dy = bx - ax, by - ay
        local t = math.max(0, math.min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
        local d = math.sqrt((x - ax - dx * t) ^ 2 + (y - ay - dy * t) ^ 2) - s[5]
        if d < best then best = d end
    end
    for _, r in ipairs(PADS) do
        local dx = math.max(r[1] - x, 0, x - (r[1] + r[3]))
        local dy = math.max(r[2] - y, 0, y - (r[2] + r[4]))
        local d = math.sqrt(dx * dx + dy * dy)
        if d < best then best = d end
    end
    return best
end

local function smooth(a, b, v)
    local k = math.max(0, math.min(1, (v - a) / (b - a)))
    return k * k * (3 - 2 * k)
end

-- Every tile's id, a row at a time, worked out from the sheet and the seed
local function layout(cols, rows)
    local kinds = classify(love.image.newImageData(courtyard.TILESET))
    assert(#kinds.plain > 0 and #kinds.slab > 0, "courtyard: the grass sheet has no plain grass or slabs")
    local rng = love.math.newRandomGenerator(SEED)
    local function pick(list) return list[rng:random(#list)] end

    local traced = {}
    for i, p in ipairs(PATHS) do
        traced[i] = { width = p.width, points = trace(p, rng) }
    end
    local bins, nx = binSegments(traced, cols, rows)

    local ids = {}
    for row = 1, rows do
        local line = {}
        for col = 1, cols do
            local x = ORIGIN_X + (col - 0.5) * T
            local y = ORIGIN_Y + (row - 0.5) * T
            local d = pathDistance(bins, nx, x, y)
            local id
            if d <= 0 then
                -- the path: whole slabs, a few cracked
                id = rng:random() < 0.12 and pick(kinds.broken) or pick(kinds.slab)
            elseif d <= 14 then
                -- its edge: worn, broken, gaps of grass
                local r = rng:random()
                id = r < 0.3 and pick(kinds.broken) or r < 0.5 and pick(kinds.slab) or nil
            elseif d <= 40 and rng:random() < 0.05 then
                id = pick(kinds.broken) -- a stray slab
            end
            if not id then
                local clump = love.math.noise(x * 0.011 + 3.7, y * 0.011 + 9.1)
                local patch = love.math.noise(x * 0.024 + 41.3, y * 0.024 - 7.7)
                local r = rng:random()
                if patch > 0.8 and r < 0.4 and #kinds.flower > 0 then
                    id = pick(kinds.flower)
                elseif r < (d < NEAR and 0.08 or 0.012) and #kinds.pebble > 0 then
                    id = pick(kinds.pebble)
                elseif r < 0.06 + 0.5 * smooth(0.45, 0.85, clump) then
                    id = pick(kinds.tuft)
                else
                    id = pick(kinds.plain)
                end
            end
            line[col] = id
        end
        ids[row] = line
    end
    return ids
end

-- The ids as the cache keeps them: 2 bytes each, row after row, zlib'd
local function encode(ids, cols)
    local fmt = "<" .. ("I2"):rep(cols)
    local packed = {}
    for row, line in ipairs(ids) do
        packed[row] = love.data.pack("string", fmt, unpack(line, 1, cols))
    end
    return love.data.compress("string", "zlib", table.concat(packed))
end

-- encode's data back into rows of ids; nil if it isn't a cols x rows layout
local function decode(data, cols, rows)
    local ok, raw = pcall(love.data.decompress, "string", "zlib", data)
    if not ok or #raw ~= cols * rows * 2 then return nil end
    local fmt = "<" .. ("I2"):rep(cols)
    local ids, pos = {}, 1
    for row = 1, rows do
        local line = { love.data.unpack(fmt, raw, pos) }
        pos = table.remove(line) -- unpack ends with where it got to
        ids[row] = line
    end
    return ids
end

--- Fill tileMap (a createMap from courtyard.TILESET's tiles, whose image is
--- tilesetImage) with the courtyard: from the cache when this file and the
--- sheet are as they were when it was last laid out.
function courtyard.fill(tileMap, tilesetImage)
    local cols, rows = tileMap.width, tileMap.height
    local key = cache.key(love.filesystem.read("game/courtyard.lua"),
        love.filesystem.read(courtyard.TILESET), cols, rows)
    local stored = cache.get("courtyard", key)
    local ids = stored and decode(stored, cols, rows)
    if not ids then
        ids = layout(cols, rows)
        cache.put("courtyard", key, encode(ids, cols))
    end
    for row = 1, rows do
        local line = ids[row]
        for col = 1, cols do
            tileMap:setTile(col, row, line[col])
        end
    end
end

return courtyard
