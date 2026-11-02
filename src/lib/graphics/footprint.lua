--[[
  Footprints: where an upright sprite meets the ground, as line segments,
  which is what stops the flashlight's beam (systems/light.lua).

  A sprite stands on its contact line: along its bottom, each column's lowest
  opaque texel. The line runs on along the art for as long as it climbs or
  falls gently (a wall seen at an angle, its base receding up the screen) and
  stops where it jumps (a tree's canopy over its trunk, a lamp's arm out from
  its post, the opening of an arch), so what overhangs the ground doesn't
  count. Each stretch is simplified to a few straight segments.
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

--- The contact line of the sprite in rect (x, y, w, h) of imageData: a flat
--- list {x0, y0, x1, y1, ...} of segments, in texels from the rect's top
--- left. bottom is its lowest row of art (by default the rect's lowest row
--- with anything opaque in it).
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
    local segments = {}
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
            for k = 2, #keep do
                local a, b = pts[keep[k - 1]], pts[keep[k]]
                segments[#segments + 1] = a[1]
                segments[#segments + 1] = a[2]
                segments[#segments + 1] = b[1]
                segments[#segments + 1] = b[2]
            end
            c = last + 1
        else
            c = c + 1
        end
    end
    return segments
end

--- The segments of the footprint `feet` (from footprint.of) for the sprite
--- drawn with its top left at world (x, y), `scale` world px per texel,
--- appended to `out` (a flat list, world px).
function footprint.place(feet, x, y, scale, out)
    out = out or {}
    for i = 1, #feet do
        local v = feet[i] * scale
        out[#out + 1] = (i % 2 == 1) and x + v or y + v
    end
    return out
end

return footprint
