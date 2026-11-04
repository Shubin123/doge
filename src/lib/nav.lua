--[[
  Finding the way on a grid over the physics world, for things that move
  round walls on their own: the car the key calls (game/car.lua) and the
  enemies (game/enemy.lua).

  A grid (nav.new(cell, clearance)) knows which of its cells something
  `clearance` px from its middle to its edge fits in: each cell is tested
  against the world's static fixtures (house walls, region buildings and
  fences, the arches, the tree) the first time it's asked about, and
  remembered. Make a new grid, or :reset() one, when the world changes;
  nav.forget(rect) when something's built or knocked down there.

    grid:path(x, y, tx, ty)  a way there (A*), straightened
    grid:flow(tx, ty, r)     which way leads to (tx, ty) from every cell
                             within r cells of it (one search for everyone
                             heading there)
]]
local nav = {}
nav.__index = nav

local KEY = 100003 -- cells' keys: cx * KEY + cy

local grids = setmetatable({}, { __mode = "k" }) -- every grid there is, for nav.forget

--- A grid of `cell` px cells for something `clearance` px from its middle
--- to its edge.
function nav.new(cell, clearance)
    local grid = setmetatable({ cell = cell, clearance = clearance, cells = {} }, nav)
    grids[grid] = true
    return grid
end

--- Forget what's been tested (the world changed).
function nav:reset()
    self.cells = {}
end

--- Every grid forgets what it tested near the world rect x0, y0 - x1, y1
--- (something there was knocked down: game/destruction.lua).
function nav.forget(x0, y0, x1, y1)
    for grid in pairs(grids) do
        local pad = grid.clearance + grid.cell
        local c0, r0 = grid:cellAt(x0 - pad, y0 - pad)
        local c1, r1 = grid:cellAt(x1 + pad, y1 + pad)
        for cx = c0, c1 do
            for cy = r0, r1 do grid.cells[cx * KEY + cy] = nil end
        end
    end
end

-- Whether the segment (x1, y1)-(x2, y2) crosses the box (Liang-Barsky)
local function segmentInBox(x1, y1, x2, y2, bx0, by0, bx1, by1)
    local dx, dy = x2 - x1, y2 - y1
    local t0, t1 = 0, 1
    local function clip(p, q)
        if p == 0 then return q >= 0 end
        local t = q / p
        if p < 0 then
            if t > t1 then return false end
            if t > t0 then t0 = t end
        else
            if t < t0 then return false end
            if t < t1 then t1 = t end
        end
        return true
    end
    return clip(-dx, x1 - bx0) and clip(dx, bx1 - x1) and clip(-dy, y1 - by0) and clip(dy, by1 - y1)
end

--- Whether fixture f stands in the way: static, solid, and within r (a
--- square) of (x, y). Its box, or for a chain or edge (a region's fence)
--- each of its edges.
function nav.blocks(f, x, y, r)
    local body = f:getBody()
    if f:isSensor() or body:getType() ~= "static" then return false end
    local shape = f:getShape()
    local kind = shape:getType()
    if kind == "chain" or kind == "edge" then
        for i = 1, kind == "chain" and shape:getChildCount() or 1 do
            local edge = kind == "chain" and shape:getChildEdge(i) or shape
            local x1, y1, x2, y2 = body:getWorldPoints(edge:getPoints())
            if segmentInBox(x1, y1, x2, y2, x - r, y - r, x + r, y + r) then return true end
        end
        return false
    end
    local ax, ay, bx, by = f:getBoundingBox()
    return ax < x + r and bx > x - r and ay < y + r and by > y - r
end

--- The cell world point (x, y) is in.
function nav:cellAt(x, y)
    return math.floor(x / self.cell), math.floor(y / self.cell)
end

--- Whether it fits in cell (cx, cy).
function nav:free(cx, cy)
    local key = cx * KEY + cy
    local v = self.cells[key]
    if v == nil then
        local cell, r = self.cell, self.clearance
        local x, y = (cx + 0.5) * cell, (cy + 0.5) * cell
        v = true
        world:queryBoundingBox(x - r, y - r, x + r, y + r, function(f)
            if nav.blocks(f, x, y, r) then
                v = false
                return false
            end
            return true
        end)
        self.cells[key] = v
    end
    return v
end

--- Whether it can go straight from (x1, y1) to (x2, y2): every cell along
--- the way is free.
function nav:straight(x1, y1, x2, y2)
    local cell = self.cell
    local d = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
    local steps = math.ceil(d / (cell / 2))
    for i = 1, steps do
        local t = i / steps
        if not self:free(math.floor((x1 + (x2 - x1) * t) / cell), math.floor((y1 + (y2 - y1) * t) / cell)) then
            return false
        end
    end
    return true
end

local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

-- Whether a step of (sx, sy) from cell (cx, cy) is open: diagonally only
-- past two free sides, so nothing clips a corner
function nav:step(cx, cy, sx, sy)
    return self:free(cx + sx, cy + sy)
        and (sx == 0 or sy == 0 or (self:free(cx + sx, cy) and self:free(cx, cy + sy)))
end

--- A way from (x, y) to (tx, ty) as a list of points ({ x, y } each), or to
--- the cell nearest it the search reached when there's no way there (looking
--- at up to maxSearch cells). {} when nowhere it can reach is nearer than
--- where it is; nil when it can't move at all.
function nav:path(x, y, tx, ty, maxSearch)
    local cell = self.cell
    local sx, sy = self:cellAt(x, y)
    local gx, gy = self:cellAt(tx, ty)
    local function guess(cx, cy) -- octile distance to the goal
        local dx, dy = math.abs(cx - gx), math.abs(cy - gy)
        return math.max(dx, dy) + 0.4142 * math.min(dx, dy)
    end
    -- open list: a binary heap of keys by f
    local heap, f, g, from, cellOf, closed = {}, {}, {}, {}, {}, {}
    local function push(k)
        heap[#heap + 1] = k
        local i = #heap
        while i > 1 do
            local parent = math.floor(i / 2)
            if f[heap[parent]] <= f[heap[i]] then break end
            heap[parent], heap[i] = heap[i], heap[parent]
            i = parent
        end
    end
    local function pop()
        local top, last = heap[1], table.remove(heap)
        if #heap > 0 then
            heap[1] = last
            local i = 1
            while true do
                local l, r, m = i * 2, i * 2 + 1, i
                if heap[l] and f[heap[l]] < f[heap[m]] then m = l end
                if heap[r] and f[heap[r]] < f[heap[m]] then m = r end
                if m == i then break end
                heap[m], heap[i] = heap[i], heap[m]
                i = m
            end
        end
        return top
    end

    local start = sx * KEY + sy
    g[start], f[start], cellOf[start] = 0, guess(sx, sy), { sx, sy }
    push(start)
    local best, bestH, searched = start, guess(sx, sy), 0
    while #heap > 0 and searched < (maxSearch or 6000) do
        local k = pop()
        if not closed[k] then
            closed[k] = true
            searched = searched + 1
            local cx, cy = cellOf[k][1], cellOf[k][2]
            local h = guess(cx, cy)
            if h < bestH then best, bestH = k, h end
            if cx == gx and cy == gy then break end
            for _, n in ipairs(NEIGHBOURS) do
                local nx, ny = cx + n[1], cy + n[2]
                local nk = nx * KEY + ny
                if not closed[nk] and self:step(cx, cy, n[1], n[2]) then
                    local cost = g[k] + ((n[1] == 0 or n[2] == 0) and 1 or 1.4142)
                    if not g[nk] or cost < g[nk] then
                        g[nk], f[nk], from[nk], cellOf[nk] = cost, cost + guess(nx, ny), k, { nx, ny }
                        push(nk)
                    end
                end
            end
        end
    end
    if best == start then
        if bestH == 0 then return { { tx, ty } } end
        return searched > 1 and {} or nil -- (none nearer than where it is)
    end

    -- Back from the goal (or the nearest it got), then straightened: from
    -- each point, on to the furthest of the next few it can go straight to
    local cells = {}
    local k = best
    while k do
        table.insert(cells, 1, cellOf[k])
        k = from[k]
    end
    local points = {}
    for i, c in ipairs(cells) do points[i] = { (c[1] + 0.5) * cell, (c[2] + 0.5) * cell } end
    if best == gx * KEY + gy then points[#points] = { tx, ty } end
    local path, i = {}, 1
    local px, py = x, y
    while i <= #points do
        local j = math.min(#points, i + 10)
        while j > i and not self:straight(px, py, points[j][1], points[j][2]) do j = j - 1 end
        path[#path + 1] = points[j]
        px, py = points[j][1], points[j][2]
        i = j + 1
    end
    return path
end

--------------------------------------------------------------------------------
-- Flow fields
--------------------------------------------------------------------------------

local Field = {}
Field.__index = Field

--- Which way leads to (tx, ty) from every free cell within `radius` cells
--- of it: one breadth-first search out from its cell, steps counted in
--- cells (a diagonal is one), so everyone heading there shares it.
function nav:flow(tx, ty, radius)
    local gx, gy = self:cellAt(tx, ty)
    local steps = {}
    local queue, head = { gx * KEY + gy }, 1
    local cx0, cy0 = { gx }, { gy }
    steps[gx * KEY + gy] = 0
    while head <= #queue do
        local cx, cy = cx0[head], cy0[head]
        local s = steps[queue[head]] + 1
        head = head + 1
        for _, n in ipairs(NEIGHBOURS) do
            local nx, ny = cx + n[1], cy + n[2]
            local nk = nx * KEY + ny
            if not steps[nk] and math.abs(nx - gx) <= radius and math.abs(ny - gy) <= radius
                and self:step(cx, cy, n[1], n[2]) then
                steps[nk] = s
                queue[#queue + 1], cx0[#cx0 + 1], cy0[#cy0 + 1] = nk, nx, ny
            end
        end
    end
    return setmetatable({ grid = self, steps = steps, gx = gx, gy = gy, radius = radius, tx = tx, ty = ty }, Field)
end

--- Which way to go from world point (x, y): a unit vector toward the
--- neighbouring cell fewest steps from the goal (straight at the goal from
--- its own cell); nil outside the field or where nothing leads there.
function Field:dir(x, y)
    local grid = self.grid
    local cx, cy = grid:cellAt(x, y)
    local here = self.steps[cx * KEY + cy]
    local bx, by
    if here == 0 then
        bx, by = self.tx, self.ty
    else
        local best = here or math.huge
        for _, n in ipairs(NEIGHBOURS) do
            local s = self.steps[(cx + n[1]) * KEY + cy + n[2]]
            -- from a cell it doesn't fit in (squeezed against a wall), any way back in
            if s and s < best and (not here or grid:step(cx, cy, n[1], n[2])) then
                best, bx, by = s, (cx + n[1] + 0.5) * grid.cell, (cy + n[2] + 0.5) * grid.cell
            end
        end
        if not bx then return nil end
    end
    local dx, dy = bx - x, by - y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 1e-6 then return nil end
    return dx / d, dy / d
end

--- How many steps it is from world point (x, y) to the goal; nil outside
--- the field or where nothing leads there.
function Field:stepsAt(x, y)
    local cx, cy = self.grid:cellAt(x, y)
    return self.steps[cx * KEY + cy]
end

--- Whether world point (x, y) is inside the field's square.
function Field:covers(x, y)
    local cx, cy = self.grid:cellAt(x, y)
    return math.abs(cx - self.gx) <= self.radius and math.abs(cy - self.gy) <= self.radius
end

return nav
