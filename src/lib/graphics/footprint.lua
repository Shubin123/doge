--[[
  Footprints: where an upright sprite meets the ground, as line segments,
  which is what stops the flashlight's beam (systems/light.lua).

  A sprite stands on its contact line: along its bottom, each column's lowest
  opaque texel. The line runs on along the art for as long as it climbs or
  falls gently (a wall seen at an angle, its base receding up the screen) and
  stops where it jumps (a tree's canopy over its trunk, a lamp's arm out from
  its post, the opening of an arch), so what overhangs the ground doesn't
  count. Each stretch is simplified to a few straight segments, and placed
  in the world it's closed into a shape that deep (footprint.place): its
  ends run back that far and a back edge joins them, so light from the side
  can't pass behind its front.
]]
local footprint = {}

local SEED = 2      -- texels above the bottom a column can start the line from
local STEP = 2      -- texels the line may climb or fall from one column to the next
local GAP = 2       -- empty columns the line steps over (a slit in the art isn't a way through)
local TOLERANCE = 1 -- texels a simplified segment may stray from the line

-- Douglas-Peucker: the points of pts[i..j] worth keeping, into keep
local function simplify(pts, i, j, keep)
    local ax, ay, bx, by = pts[i][1], pts[i][2], pts[j][1], pts[j][2]
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    local worst, at = 0, nil
    for k = i + 1, j - 1 do
        local px, py = pts[k][1] - ax, pts[k][2] - ay
        local d = len > 0 and math.abs(px * dy - py * dx) / len or math.sqrt(px * px + py * py)
        if d > worst then worst, at = d, k end
    end
    if at and worst > TOLERANCE then
        simplify(pts, i, at, keep)
        simplify(pts, at, j, keep)
    else
        keep[#keep + 1] = j
    end
end

--- The contact line of the sprite in rect (x, y, w, h) of imageData: a list
--- of stretches, each a polyline {x0, y0, x1, y1, ...} in texels from the
--- rect's top left. bottom is its lowest row of art (by default the rect's
--- lowest row with anything opaque in it).
function footprint.of(data, x, y, w, h, bottom)
    local function opaque(c, r)
        local _, _, _, a = data:getPixel(x + c, y + r)
        return a > 0.5
    end
    if not bottom then
        for r = h - 1, 0, -1 do
            for c = 0, w - 1 do
                if opaque(c, r) then bottom = r break end
            end
            if bottom then break end
        end
        if not bottom then return {} end
    end
    -- Column c's lowest opaque texel, if it's between rows lo and hi
    local function lowest(c, lo, hi)
        for r = bottom, math.max(lo, 0), -1 do
            if opaque(c, r) then return r <= hi and r or nil end
        end
    end

    -- The line: columns standing on the bottom, then on out from them while
    -- it's gentle
    local line = {}
    for c = 0, w - 1 do line[c] = lowest(c, bottom - SEED, bottom) end
    for c = 1, w - 1 do
        if not line[c] and line[c - 1] then line[c] = lowest(c, line[c - 1] - STEP, line[c - 1] + STEP) end
    end
    for c = w - 2, 0, -1 do
        if not line[c] and line[c + 1] then line[c] = lowest(c, line[c + 1] - STEP, line[c + 1] + STEP) end
    end

    -- Each stretch of it (over slits up to GAP wide) as a polyline along the
    -- bottom edges of its texels, simplified
    local stretches = {}
    local c = 0
    while c < w do
        if line[c] then
            local pts = { { c, line[c] + 1 } }
            local last = c
            while true do
                pts[#pts + 1] = { last + 1, line[last] + 1 }
                local nextc
                for k = last + 1, math.min(last + 1 + GAP, w - 1) do
                    if line[k] then
                        if math.abs(line[k] - line[last]) <= STEP then nextc = k end
                        break
                    end
                end
                if not nextc then break end
                last = nextc
            end
            local keep = { 1 }
            simplify(pts, 1, #pts, keep)
            local line = {}
            for _, k in ipairs(keep) do
                line[#line + 1] = pts[k][1]
                line[#line + 1] = pts[k][2]
            end
            stretches[#stretches + 1] = line
            c = last + 1
        else
            c = c + 1
        end
    end
    return stretches
end

--- The footprint `feet` (from footprint.of) of the sprite drawn with its top
--- left at world (x, y), `scale` world px per texel, as a flat list of
--- segments {x0, y0, x1, y1, ...} (world px): each stretch's front, and its
--- ends and back `depth` world px behind it.
function footprint.place(feet, x, y, scale, depth)
    local out = {}
    local function add(x0, y0, x1, y1)
        out[#out + 1], out[#out + 2], out[#out + 3], out[#out + 4] = x0, y0, x1, y1
    end
    for _, line in ipairs(feet) do
        local n = #line
        for i = 1, n - 3, 2 do
            add(x + line[i] * scale, y + line[i + 1] * scale, x + line[i + 2] * scale, y + line[i + 3] * scale)
        end
        local fx, fy = x + line[1] * scale, y + line[2] * scale
        local lx, ly = x + line[n - 1] * scale, y + line[n] * scale
        add(fx, fy, fx, fy - depth)
        add(lx, ly, lx, ly - depth)
        add(fx, fy - depth, lx, ly - depth)
    end
    return out
end

return footprint
