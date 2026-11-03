--[[
  Destruction: what stands takes hits, cracks, and comes down.

  A structure is anything upright with collision: every region sprite that
  has a footprint (buildings, walls, towers, landmarks, lamps, barriers,
  props: regions.lua registers them as it lays a region out) and the home
  map's arch (map.lua, through destruction.forArch). Each has health from
  its size and what it's built of.

    - A hit leaves a mark on its face where the shot meets it, about chest
      height up from where it struck the footprint: a bullet hole, or a
      blast's scorch peppered with shrapnel. Marks multiply what's there,
      so they darken the face in whatever light it's in, and are clipped
      to the sprite's own opaque texels (DECAL_SHADER).
    - The sprite is cut into shards (a jittered grid, each cell split along
      a diagonal; worked out once per sprite and shared by every copy of
      it). As it's hurt the edges between shards near the hits show as
      cracks, loose shards on its outline come away, its top crumbles as
      its health passes each of CRUMBLE, and a blast knocks a hole through.
      Once a shard is gone it's drawn from the shards it has left (fmesh),
      and whatever no longer rests on the ground through its neighbours
      falls too.
    - With no health left it comes down: its collision, its footprint (so
      light passes) and its light (a lamp goes out) go, every shard falls in
      a cloud of dust, and they lie where they land, rubble that's part of
      the ground from then on.
  Shards are drawn with the region sprite shader like the sprite they came
  from, lit by their height above the ground (which rides in their vertex
  colour, see regions.lua's SPRITE_SHADER); lying down they're flat.

  The host (or single player) decides what's hit and what falls: the
  snapshot carries its recent hits (for the marks) and what's down to the
  clients, and saves keep what's down, by key (the region and the
  structure's place in its layout, which the seed keeps the same).
]]
local destruction = {}
local nav = require("lib.nav")

-- Health: per world px² of sprite, within MIN_HP..MAX_HP, by what it's built
-- of (its region's id; the home map's is "home") and far less for glass
local HP_PER_PX = 1 / 70
local MIN_HP, MAX_HP = 25, 1200
local MATERIAL = { wasteland = 0.9, castle = 1.5, neon = 1, sanctum = 1.2, home = 1.3 }
local GLASS = 0.35

-- What each kind of hit does to a structure
destruction.BULLET = 10  -- per point of a bullet's damage
destruction.HOSTILE = 2  -- an enemy's bullet
destruction.ARROW = 14
destruction.FIRE = 30    -- a fireball
destruction.BLAST = 170  -- a rocket's, where it goes off (var.rocket_splash_radius across)

local GRAVITY = 900                -- world px/s², for what falls
local LIFT_MIN, LIFT_MAX = 10, 44  -- world px up the face from the footprint a shot lands
local SEARCH = 48                  -- texels up or down its column a mark may move to land on it
local MAX_MARKS = 48               -- holes and scorches on one structure; then the oldest go
local MAX_CRACKS = 160             -- crack segments on one
local CRUMBLE = { 0.72, 0.58, 0.44, 0.3, 0.16 } -- health left at which its top crumbles
local SETTLE = 0.4                 -- s a fallen heap lies still before it's ground
local MAX_RUBBLE = 16000           -- shards lying about; past that the oldest heaps go
local CHIP_LIFE = 1.4              -- s a chip knocked off by a shot lies about
local MAX_PUFFS = 400
local HIT_MEMORY = 0.5             -- s the host keeps a hit for the snapshot

local ALPHA = { "alpha" }
local REPLACE = { "replace", "premultiplied" }
local WHITE = { 1, 1, 1, 1 }

local registry = {} -- key -> structure
local down = {}     -- keys of the regions' structures that are down
local pending = {}  -- knocked down during the physics step: brought down after it
local groups = {}   -- shards in the air, and chips
local rubble = {}   -- heaps on the ground for good, oldest first
local rubbleCount = 0
local puffs = {}    -- dust
local hitLog, hitTimes, hitSeq, lastSeen = {}, {}, 0, 0 -- (the host's, and when each was)
local synced = false -- a client that's had what's down from the host

local function isHost()
    return not var.multiplayer or var.multiplayer == 1
end

--------------------------------------------------------------------------------
-- Art: the marks, the dust, and how marks are drawn
--------------------------------------------------------------------------------

-- The marks, one small image: four bullet holes, a scorch and a block for
-- cracks. Each texel is what it multiplies the face by (white: no change).
local HOLE, SCORCH, CRACK = 8, 24, 4
local HOLE_RECTS = { { 0, 0, HOLE, HOLE }, { HOLE, 0, HOLE, HOLE }, { 2 * HOLE, 0, HOLE, HOLE },
    { 3 * HOLE, 0, HOLE, HOLE } }
local SCORCH_RECT = { 4 * HOLE, 0, SCORCH, SCORCH }
local CRACK_RECT = { 4 * HOLE + SCORCH + 1, 1, CRACK - 2, CRACK - 2 } -- (inside it: no bleeding)
local markImage, markW, markH

local function newMarkImage()
    local data = love.image.newImageData(4 * HOLE + SCORCH + CRACK, SCORCH)
    data:mapPixel(function() return 1, 1, 1, 1 end)
    local rng = love.math.newRandomGenerator(9)
    -- holes: a dark pit in a ring of chipped face, ragged
    for k = 0, 3 do
        local inner, outer = 1 + rng:random() * 0.7, 2.4 + rng:random()
        for y = 0, HOLE - 1 do
            for x = 0, HOLE - 1 do
                local dx, dy = x + 0.5 - HOLE / 2, y + 0.5 - HOLE / 2
                local d = math.sqrt(dx * dx + dy * dy) + (rng:random() - 0.5) * 0.9
                local v = 1
                if d < inner then
                    v = 0.1
                elseif d < outer then
                    v = 0.5 + 0.25 * (d - inner) / (outer - inner)
                elseif d < outer + 1 and rng:random() < 0.3 then
                    v = 0.82
                end
                data:setPixel(k * HOLE + x, y, v, v * 0.97, v * 0.94, 1)
            end
        end
    end
    -- the scorch: sooty, soft, ragged at the edge
    local sx = 4 * HOLE
    for y = 0, SCORCH - 1 do
        for x = 0, SCORCH - 1 do
            local dx, dy = x + 0.5 - SCORCH / 2, y + 0.5 - SCORCH / 2
            local d = math.sqrt(dx * dx + dy * dy) / (SCORCH / 2)
            local k = math.max(0, 1 - d - (love.math.noise(x * 0.35, y * 0.35, 3.7) - 0.5) * 0.6)
            local v = 1 - 0.72 * math.min(1, k * 1.7)
            data:setPixel(sx + x, y, v, v * 0.95, v * 0.9, 1)
        end
    end
    for y = 0, CRACK - 1 do
        for x = 0, CRACK - 1 do
            data:setPixel(sx + SCORCH + x, y, 0.4, 0.38, 0.36, 1)
        end
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    return image, data:getDimensions()
end

-- A soft white blot for dust
local puffImage
local function newPuffImage()
    local n = 32
    local data = love.image.newImageData(n, n)
    for y = 0, n - 1 do
        for x = 0, n - 1 do
            local d = math.sqrt((x + 0.5 - n / 2) ^ 2 + (y + 0.5 - n / 2) ^ 2) / (n / 2)
            local a = math.max(0, 1 - d)
            a = a * a * (0.7 + 0.6 * love.math.noise(x * 0.22, y * 0.22, 1.3))
            data:setPixel(x, y, 1, 1, 1, math.min(1, a))
        end
    end
    return love.graphics.newImage(data)
end

-- Marks over a structure, multiplied into what's there (drawn with the
-- "multiply" blend: alpha 1 leaves the scene's alpha, what the GI pass
-- reads as walls, as it was). Each vertex also carries where it lies on
-- the structure's own sheet, so a mark only shows over the sprite's
-- opaque texels, inside its rect.
local DECAL_SHADER = [[
    varying vec2 vAtlas;
    #ifdef VERTEX
    attribute vec2 AtlasCoord;
    vec4 position(mat4 transform_projection, vec4 vertex_position) {
        vAtlas = AtlasCoord;
        return transform_projection * vertex_position;
    }
    #endif
    #ifdef PIXEL
    uniform Image atlas;
    uniform vec4 bounds;     // the sprite's rect in the sheet (uv)
    uniform float minAlpha;  // what counts as the sprite
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 screen_coords) {
        bool inside = vAtlas.x >= bounds.x && vAtlas.y >= bounds.y && vAtlas.x < bounds.z && vAtlas.y < bounds.w;
        if (!inside || Texel(atlas, vAtlas).a < minAlpha) return vec4(1.0);
        return vec4(Texel(tex, tc).rgb, 1.0);
    }
    #endif
]]
local decalShader

local noGlow -- the home map's sheets give off no light

function destruction.load()
    markImage, markW, markH = newMarkImage()
    puffImage = newPuffImage()
    decalShader = love.graphics.newShader(DECAL_SHADER)
end

--------------------------------------------------------------------------------
-- Structures
--------------------------------------------------------------------------------

--- Make t a structure. It needs: key (unique, the same every run), look (its
--- sheet: id, image, data (its ImageData), scale, glowImage, normalImage),
--- qx, qy, qw, qh (its rect in the sheet), x, y (world, its top left),
--- scale, base (its ground line), depth (its collision, px up from base),
--- foot (its collision, { x0, y0, x1, y1 }), sort_y, glass, and takeDown(t)
--- to take it out of the world, putBack(t) to put it back.
function destruction.register(t)
    local hp = math.max(MIN_HP, math.min(MAX_HP, t.qw * t.qh * t.scale * t.scale * HP_PER_PX))
    hp = hp * (MATERIAL[t.look.id] or 1) * (t.glass and GLASS or 1)
    t.structure = t
    t.maxHp, t.hp = hp, hp
    t.iw, t.ih = t.look.image:getDimensions()
    t.alphaMin = t.glass and 0.12 or 0.5
    registry[t.key] = t
    return t
end

--- The structure fixture f belongs to, if it's still standing.
function destruction.of(f)
    local ud = f:getUserData()
    if type(ud) ~= "table" then return nil end
    local st = ud.item or (ud.object and ud.object.structure)
    if st and st.hp and not st.down then return st end
end

-- The home map's arch: a structure while it stands where it's drawn (the
-- editor moving it makes a new one)
local archLook

--- The arch's structure, for its draw item (map.addMapToDynamicDrawList).
function destruction.forArch(arch, item)
    local st = arch.structure
    if st and st.x == item.x and st.y == item.y and not st.down then return st end
    if not noGlow then
        local data = love.image.newImageData(1, 1)
        data:setPixel(0, 0, 0, 0, 0, 1)
        noGlow = love.graphics.newImage(data)
    end
    archLook = archLook or { id = "home", image = map.tiles3.tilesetImage, data = map.tiles3.data,
        scale = item.scale_x, glowImage = noGlow, normalImage = map.tiles3.normals }
    local qx, qy, qw, qh = item.quad:getViewport()
    -- its art's lowest row stands on the ground
    local bottom = qh - 1
    while bottom > 0 do
        local found = false
        for u = 0, qw - 1 do
            local _, _, _, a = archLook.data:getPixel(qx + u, qy + bottom)
            if a >= 0.5 then found = true break end
        end
        if found then break end
        bottom = bottom - 1
    end
    local scale = item.scale_x
    local base = item.y + (bottom + 1) * scale
    local depth = 12 * scale
    st = {
        key = "arch:" .. arch.id, look = archLook,
        qx = qx, qy = qy, qw = qw, qh = qh, x = item.x, y = item.y, scale = scale,
        base = base, depth = depth, foot = { item.x, base - depth, item.x + qw * scale, base },
        sort_y = item.sort_y,
        takeDown = function()
            arch:destroy()
            for i = #map.archInstances, 1, -1 do
                if map.archInstances[i] == arch then table.remove(map.archInstances, i) end
            end
            map_a = map.addMapToDynamicDrawList(map.arches, 0, 0, 1, 200) -- (main.lua: what draws the arches)
        end,
    }
    arch.structure = st
    return destruction.register(st)
end

--------------------------------------------------------------------------------
-- Shards: a pattern per sprite
--------------------------------------------------------------------------------

local patterns = setmetatable({}, { __mode = "k" }) -- look -> { [rect] = pattern }

-- How far (x, y) is inside the edge a -> b of a counter-clockwise triangle
local function inside(x, y, ax, ay, bx, by)
    local ex, ey = bx - ax, by - ay
    local len = math.sqrt(ex * ex + ey * ey)
    if len == 0 then return 0 end
    return ((x - ax) * ey - (y - ay) * ex) / len
end

-- Whether (x, y) is in triangle t of pattern P, or within `slack` texels of it
local function inTri(P, t, x, y, slack)
    local ax, ay, bx, by, cx, cy = P.px[t[1]], P.py[t[1]], P.px[t[2]], P.py[t[2]], P.px[t[3]], P.py[t[3]]
    return inside(x, y, ax, ay, bx, by) >= -slack and inside(x, y, bx, by, cx, cy) >= -slack
        and inside(x, y, cx, cy, ax, ay) >= -slack
end

-- Cut a sprite (qw x qh texels at qx, qy in look's sheet) into shards: a grid
-- of about 70 cells, each corner but the outline's pushed about, each cell
-- split along one diagonal or the other. A shard over nothing but
-- transparent texels is left out. Points are in texels from the sprite's
-- top left.
local function buildPattern(look, qx, qy, qw, qh, alphaMin)
    local data = look.data
    local rng = love.math.newRandomGenerator(qx * 7919 + qy * 104729 + 17)
    local c = math.max(7, math.min(20, math.sqrt(qw * qh / 70)))
    local cols = math.max(1, math.floor(qw / c + 0.5))
    local rows = math.max(1, math.floor(qh / c + 0.5))
    local cw, ch = qw / cols, qh / rows
    local P = { cols = cols, rows = rows, cw = cw, ch = ch, px = {}, py = {}, tris = {}, cell = {}, edges = {} }
    local function pid(i, j) return j * (cols + 1) + i + 1 end
    for j = 0, rows do
        for i = 0, cols do
            local x, y = i * cw, j * ch
            if i > 0 and i < cols then x = x + (rng:random() - 0.5) * 0.64 * cw end
            if j > 0 and j < rows then y = y + (rng:random() - 0.5) * 0.64 * ch end
            P.px[pid(i, j)], P.py[pid(i, j)] = x, y
        end
    end

    local function opaque(u, v)
        local _, _, _, a = data:getPixel(qx + u, qy + v)
        return a >= alphaMin
    end
    -- (wound so that `inside` is positive within it)
    local function tri(i, j, a, b, c3, sides)
        local ax, ay = P.px[a], P.py[a]
        if (P.px[b] - ax) * (P.py[c3] - ay) - (P.py[b] - ay) * (P.px[c3] - ax) > 0 then b, c3 = c3, b end
        local t = { a, b, c3, i = i, j = j, nb = {} }
        for _, s in ipairs(sides) do t[s] = true end
        local xs = { P.px[a], P.px[b], P.px[c3] }
        local ys = { P.py[a], P.py[b], P.py[c3] }
        t.cu, t.cv = (xs[1] + xs[2] + xs[3]) / 3, (ys[1] + ys[2] + ys[3]) / 3
        t.maxV = math.max(ys[1], ys[2], ys[3])
        -- kept if it covers any of the sprite (a texel's breadth of slack, so
        -- a hairline of art along its edge isn't lost)
        local u0, u1 = math.max(0, math.floor(math.min(xs[1], xs[2], xs[3]) - 1)),
            math.min(qw - 1, math.ceil(math.max(xs[1], xs[2], xs[3]) + 1))
        local v0, v1 = math.max(0, math.floor(math.min(ys[1], ys[2], ys[3]) - 1)),
            math.min(qh - 1, math.ceil(t.maxV + 1))
        for v = v0, v1 do
            for u = u0, u1 do
                if inTri(P, t, u + 0.5, v + 0.5, 1) and opaque(u, v) then
                    t.kept = true
                    break
                end
            end
            if t.kept then break end
        end
        P.tris[#P.tris + 1] = t
        return #P.tris
    end
    for j = 0, rows - 1 do
        for i = 0, cols - 1 do
            local tl, tr, br, bl = pid(i, j), pid(i + 1, j), pid(i + 1, j + 1), pid(i, j + 1)
            local a, b
            if rng:random() < 0.5 then
                a = tri(i, j, tl, tr, br, { "top", "right" })
                b = tri(i, j, tl, br, bl, { "bottom", "left" })
                P.tris[a].diag = { tl, br }
            else
                a = tri(i, j, tl, tr, bl, { "top", "left" })
                b = tri(i, j, tr, br, bl, { "right", "bottom" })
                P.tris[a].diag = { tr, bl }
            end
            P.cell[(j * cols + i) * 2 + 1], P.cell[(j * cols + i) * 2 + 2] = a, b
        end
    end

    -- Neighbours (shards that share an edge), and the edges between kept
    -- ones, where cracks run
    local function sideOf(i, j, side)
        local a, b = P.cell[(j * cols + i) * 2 + 1], P.cell[(j * cols + i) * 2 + 2]
        return P.tris[a][side] and a or b
    end
    local function link(t1, t2, p, q)
        local a, b = P.tris[t1], P.tris[t2]
        if not (a.kept and b.kept) then return end
        a.nb[#a.nb + 1], b.nb[#b.nb + 1] = t2, t1
        P.edges[#P.edges + 1] = { p, q, t1, t2, mx = (P.px[p] + P.px[q]) / 2, my = (P.py[p] + P.py[q]) / 2 }
    end
    for j = 0, rows - 1 do
        for i = 0, cols - 1 do
            local a, b = P.cell[(j * cols + i) * 2 + 1], P.cell[(j * cols + i) * 2 + 2]
            link(a, b, P.tris[a].diag[1], P.tris[a].diag[2])
            if j > 0 then link(sideOf(i, j, "top"), sideOf(i, j - 1, "bottom"), pid(i, j), pid(i + 1, j)) end
            if i > 0 then link(sideOf(i, j, "left"), sideOf(i - 1, j, "right"), pid(i, j), pid(i, j + 1)) end
        end
    end

    -- The art's lowest row (what stands on the ground) and its colour, for dust
    P.bottom = 0
    local r, g, b, n = 0, 0, 0, 0
    for v = qh - 1, 0, -1 do
        for u = 0, qw - 1 do
            if opaque(u, v) then P.bottom = math.max(P.bottom, v) end
        end
        if P.bottom > 0 then break end
    end
    for v = 0, qh - 1, 3 do
        for u = 0, qw - 1, 3 do
            local pr, pg, pb, pa = data:getPixel(qx + u, qy + v)
            if pa >= alphaMin then r, g, b, n = r + pr, g + pg, b + pb, n + 1 end
        end
    end
    n = math.max(1, n)
    P.dust = { 0.45 + 0.45 * r / n, 0.43 + 0.45 * g / n, 0.4 + 0.45 * b / n }
    return P
end

-- st's pattern, and its own shards still standing
local function fracture(st)
    if st.pattern then return st.pattern end
    local byLook = patterns[st.look]
    if not byLook then
        byLook = {}
        patterns[st.look] = byLook
    end
    local key = st.qx * 65536 + st.qy
    local P = byLook[key] or buildPattern(st.look, st.qx, st.qy, st.qw, st.qh, st.alphaMin)
    byLook[key] = P
    st.pattern = P
    st.alive, st.cracked = {}, {}
    for k, t in ipairs(P.tris) do
        if t.kept then st.alive[k] = true end
    end
    return P
end

-- Where to look for the shard over a point: its grid cell, then round it
-- (corners move up to a third of a cell)
local NEAR = { 0, 0, -1, 0, 1, 0, 0, -1, 0, 1, -1, -1, 1, -1, -1, 1, 1, 1 }

-- The shard over texel point (u, v) of st, standing or not
local function shardAt(st, u, v)
    local P = st.pattern
    local i0, j0 = math.floor(u / P.cw), math.floor(v / P.ch)
    for n = 1, #NEAR, 2 do
        local i, j = i0 + NEAR[n], j0 + NEAR[n + 1]
        if i >= 0 and j >= 0 and i < P.cols and j < P.rows then
            for k = 1, 2 do
                local idx = P.cell[(j * P.cols + i) * 2 + k]
                if inTri(P, P.tris[idx], u, v, 0) then return idx end
            end
        end
    end
end

-- The standing shard over texel (u, v) if the sprite's there, else nil
local function solidAt(st, u, v)
    local _, _, _, a = st.look.data:getPixel(st.qx + u, st.qy + v)
    if a < st.alphaMin then return nil end
    local idx = shardAt(st, u + 0.5, v + 0.5)
    return idx and st.alive[idx] and idx or nil
end

-- Where a hit on st's footprint at world (x, y) shows on its face: `lift`
-- px up from there, then up or down its column onto what's left of it.
-- Texel point on the sprite and the shard there, or nil.
local function facePoint(st, x, y, lift)
    local u = math.max(0, math.min(st.qw - 1, math.floor((x - st.x) / st.scale)))
    local v0 = math.max(0, math.min(st.qh - 1, math.floor((math.min(y, st.base) - lift - st.y) / st.scale)))
    for d = 0, SEARCH do
        local v = v0 + d
        if v < st.qh then
            local idx = solidAt(st, u, v)
            if idx then return u + 0.5, v + 0.5, idx end
        end
        v = v0 - d
        if d > 0 and v >= 0 then
            local idx = solidAt(st, u, v)
            if idx then return u + 0.5, v + 0.5, idx end
        end
    end
end

-- Whether shard idx of st is on its outline: a neighbour gone, or fewer
-- than three to begin with
local function loose(st, idx)
    local t = st.pattern.tris[idx]
    if #t.nb < 3 then return true end
    for _, n in ipairs(t.nb) do
        if not st.alive[n] then return true end
    end
    return false
end

-- st's standing shards that no longer rest on the ground through their
-- neighbours (the ground: those reaching its art's lowest row)
local function unsupported(st)
    local P = st.pattern
    local seen, queue = {}, {}
    for idx in pairs(st.alive) do
        if P.tris[idx].maxV >= P.bottom - 2 then
            seen[idx] = true
            queue[#queue + 1] = idx
        end
    end
    local head = 1
    while head <= #queue do
        for _, n in ipairs(P.tris[queue[head]].nb) do
            if st.alive[n] and not seen[n] then
                seen[n] = true
                queue[#queue + 1] = n
            end
        end
        head = head + 1
    end
    local fall = {}
    for idx in pairs(st.alive) do
        if not seen[idx] then fall[#fall + 1] = idx end
    end
    return fall
end

-- What's left of st, drawn in place of its quad (in texels: drawn at its
-- x, y and scale)
local SHAPE_FORMAT = { { "VertexPosition", "float", 2 }, { "VertexTexCoord", "float", 2 } }
local function reshape(st)
    local P = st.pattern
    local verts = {}
    for idx in pairs(st.alive) do
        local t = P.tris[idx]
        for k = 1, 3 do
            local x, y = P.px[t[k]], P.py[t[k]]
            verts[#verts + 1] = { x, y, (st.qx + x) / st.iw, (st.qy + y) / st.ih }
        end
    end
    if #verts == 0 then
        st.fmesh = nil
        return
    end
    st.fmesh = love.graphics.newMesh(SHAPE_FORMAT, verts, "triangles", "static")
    st.fmesh:setTexture(st.look.image)
end

--------------------------------------------------------------------------------
-- Marks
--------------------------------------------------------------------------------

local DECAL_FORMAT = { { "VertexPosition", "float", 2 }, { "VertexTexCoord", "float", 2 },
    { "AtlasCoord", "float", 2 } }
local SLOTS = MAX_MARKS + MAX_CRACKS
local ZERO = { 0, 0, 0, 0, 0, 0 }
local ZEROS = { ZERO, ZERO, ZERO, ZERO, ZERO, ZERO }
local CORNERS = { -1, -1, 1, -1, 1, 1, -1, -1, 1, 1, -1, 1 } -- a quad as two triangles
local quadVerts = {}
for i = 1, 6 do quadVerts[i] = { 0, 0, 0, 0, 0, 0 } end

local function marksOf(st)
    if st.decals then return st.decals end
    local verts = {}
    for i = 1, SLOTS * 6 do verts[i] = ZERO end
    local mesh = love.graphics.newMesh(DECAL_FORMAT, verts, "triangles", "dynamic")
    mesh:setTexture(markImage)
    st.bounds = { st.qx / st.iw, st.qy / st.ih, (st.qx + st.qw) / st.iw, (st.qy + st.qh) / st.ih }
    st.decals = { mesh = mesh, marks = {}, nextMark = 1, cracks = 0 }
    return st.decals
end

-- Mark m in slot `slot` of st: m = { u, v (its middle, texels on the
-- sprite), w, h (world px), angle, rect (in the marks image) }
local function writeMark(st, slot, m)
    local cx, cy = st.x + m[1] * st.scale, st.y + m[2] * st.scale
    local c, s = math.cos(m[5]), math.sin(m[5])
    local rect = m[6]
    for k = 1, 6 do
        local ox, oy = CORNERS[2 * k - 1] * m[3] / 2, CORNERS[2 * k] * m[4] / 2
        local wx, wy = cx + ox * c - oy * s, cy + ox * s + oy * c
        local q = quadVerts[k]
        q[1], q[2] = wx, wy
        q[3] = (rect[1] + (CORNERS[2 * k - 1] + 1) / 2 * rect[3]) / markW
        q[4] = (rect[2] + (CORNERS[2 * k] + 1) / 2 * rect[4]) / markH
        q[5] = (st.qx + (wx - st.x) / st.scale) / st.iw
        q[6] = (st.qy + (wy - st.y) / st.scale) / st.ih
    end
    st.decals.mesh:setVertices(quadVerts, (slot - 1) * 6 + 1)
end

local function addMark(st, m)
    local d = marksOf(st)
    local slot = d.nextMark
    d.nextMark = slot % MAX_MARKS + 1
    d.marks[slot] = m
    writeMark(st, slot, m)
end

local function hole(st, u, v, tri)
    addMark(st, { u, v, HOLE, HOLE, love.math.random(0, 3) * math.pi / 2, HOLE_RECTS[love.math.random(4)], tri = tri })
end

-- Cracks along the edges between st's standing shards nearest texel point
-- (u, v), up to `count` of them within `radius`: each a dark line in three
-- jagged pieces
local function crack(st, u, v, radius, count)
    local P = st.pattern
    local d = marksOf(st)
    local near = {}
    for e, edge in ipairs(P.edges) do
        if not st.cracked[e] and st.alive[edge[3]] and st.alive[edge[4]] then
            local dist = (edge.mx - u) ^ 2 + (edge.my - v) ^ 2
            if dist < radius * radius then near[#near + 1] = { e, dist } end
        end
    end
    table.sort(near, function(a, b) return a[2] < b[2] end)
    for n = 1, math.min(count, #near) do
        if d.cracks + 3 > MAX_CRACKS then return end
        local e = near[n][1]
        st.cracked[e] = true
        local edge = P.edges[e]
        local ax, ay, bx, by = P.px[edge[1]], P.py[edge[1]], P.px[edge[2]], P.py[edge[2]]
        local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
        if len > 0 then
            local nx, ny = -(by - ay) / len, (bx - ax) / len
            local j1, j2 = (love.math.random() - 0.5) * 1.6, (love.math.random() - 0.5) * 1.6
            local pts = { ax, ay, ax + (bx - ax) / 3 + nx * j1, ay + (by - ay) / 3 + ny * j1,
                ax + (bx - ax) * 2 / 3 + nx * j2, ay + (by - ay) * 2 / 3 + ny * j2, bx, by }
            for s = 1, 3 do
                local x1, y1, x2, y2 = pts[2 * s - 1], pts[2 * s], pts[2 * s + 1], pts[2 * s + 2]
                local piece = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) * st.scale
                d.cracks = d.cracks + 1
                local slot = MAX_MARKS + d.cracks
                d.marks[slot] = { (x1 + x2) / 2, (y1 + y2) / 2, piece + 0.6, 1, math.atan2(y2 - y1, x2 - x1),
                    CRACK_RECT, edge = e }
                writeMark(st, slot, d.marks[slot])
            end
        end
    end
end

-- Marks on shards that are gone go with them
local function pruneMarks(st)
    local d = st.decals
    if not d then return end
    local edges = st.pattern.edges
    for slot, m in pairs(d.marks) do
        local gone
        if m.tri then
            gone = not st.alive[m.tri]
        elseif m.edge then
            gone = not (st.alive[edges[m.edge][3]] and st.alive[edges[m.edge][4]])
        end
        if gone then
            d.marks[slot] = nil
            d.mesh:setVertices(ZEROS, (slot - 1) * 6 + 1)
        end
    end
end

--------------------------------------------------------------------------------
-- What falls: shards and chips, in groups (one per structure at a time)
--------------------------------------------------------------------------------

local DEBRIS_FORMAT = { { "VertexPosition", "float", 2 }, { "VertexTexCoord", "float", 2 },
    { "VertexColor", "float", 4 } }

local function groupOf(st)
    local g = st.debris
    if g and not g.done then return g end
    g = { st = st, look = st.look, scale = st.scale, glass = st.glass, shards = {}, still = 0, sort_y = st.sort_y + 1,
        list = {}, pool = {}, cap = 0, count = 0 }
    g.entry = { sort_y = g.sort_y, source_object_type = "debris", group = g, color = WHITE,
        blend_mode = g.glass and ALPHA or REPLACE }
    st.debris = g
    groups[#groups + 1] = g
    return g
end

-- A shard flying off st: pts round its middle (world px), uv on the sheet,
-- at world (wx, wy) on screen over ground y gy; pushed (px, py) with `power`
-- (0 a crumble, 1 a blast)
local function launch(g, st, pts, uv, row, wx, wy, gy, px, py, power)
    if gy < wy then gy = wy end
    local spread = 30 + 170 * power
    local s = {
        pts = pts, uv = uv, row = row,
        x = wx, y = gy, z = gy - wy,
        vx = px * spread * (0.5 + love.math.random()) + (love.math.random() - 0.5) * 60,
        vy = py * spread * (0.5 + love.math.random()) + love.math.random() * 45, -- spills out in front
        vz = power * (60 + love.math.random() * 200) + (love.math.random() - 0.3) * 40,
        rot = 0, vr = (love.math.random() - 0.5) * (3 + 12 * power),
        squash = 1, delay = 0,
    }
    g.shards[#g.shards + 1] = s
    g.still = 0
    return s
end

local function addShard(g, st, idx, px, py, power)
    local P = st.pattern
    local t = P.tris[idx]
    local pts, uv = {}, {}
    for k = 1, 3 do
        local x, y = P.px[t[k]], P.py[t[k]]
        pts[2 * k - 1], pts[2 * k] = (x - t.cu) * st.scale, (y - t.cv) * st.scale
        uv[2 * k - 1], uv[2 * k] = (st.qx + x) / st.iw, (st.qy + y) / st.ih
    end
    -- the ground under it: somewhere in its footprint
    local gy = st.base - love.math.random() * st.depth * 0.7
    return launch(g, st, pts, uv, st.qy + t.cv, st.x + t.cu * st.scale, st.y + t.cv * st.scale, gy, px, py, power)
end

-- A chip knocked off the face at texel point (u, v), over ground y gy
local function addChip(g, st, u, v, gy, px, py)
    local size = 1 + love.math.random() * 2 -- texels
    local u0 = math.max(0, math.min(st.qw - size, u - size / 2))
    local v0 = math.max(0, math.min(st.qh - size, v - size / 2))
    local h = size * st.scale / 2
    local pts = { -h, -h, h, -h, h, h, -h, -h, h, h, -h, h }
    local a0, b0 = (st.qx + u0) / st.iw, (st.qy + v0) / st.ih
    local a1, b1 = (st.qx + u0 + size) / st.iw, (st.qy + v0 + size) / st.ih
    local uv = { a0, b0, a1, b0, a1, b1, a0, b0, a1, b1, a0, b1 }
    local s = launch(g, st, pts, uv, st.qy + v, st.x + u * st.scale, st.y + v * st.scale, gy, px, py, 0)
    local speed = 40 + love.math.random() * 110
    s.vx, s.vy = px * speed + (love.math.random() - 0.5) * 50, py * speed + (love.math.random() - 0.5) * 30
    s.vz = 40 + love.math.random() * 110
    s.vr = (love.math.random() - 0.5) * 20
    s.chip, s.life = true, CHIP_LIFE
end

-- The group's shards as triangles: in the air, lit as low things at their
-- height (the vertex colour: their middle's sheet row plus how high it is,
-- see SPRITE_SHADER); lying still (flat), as part of the ground
local function build(g, flat)
    local list, pool, n = g.list, g.pool, 0
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, s in ipairs(g.shards) do
        local c, sn = math.cos(s.rot), math.sin(s.rot)
        local k = s.chip and math.min(1, s.life / 0.3) or 1
        local cr, cg, cb
        if flat then
            cr, cg, cb = 0, 0, 4 / 255
        else
            local base = math.max(0, math.floor(s.row + s.z / g.scale + 0.5))
            cr, cg, cb = math.floor(base / 256) / 255, base % 256 / 255, (g.glass and 2 or 0) / 255
        end
        local sy = s.y - s.z
        for p = 1, #s.pts, 2 do
            local ox, oy = s.pts[p] * k, s.pts[p + 1] * k
            n = n + 1
            local v = pool[n]
            if not v then
                v = {}
                pool[n] = v
            end
            v[1] = s.x + ox * c - oy * sn
            v[2] = sy + (ox * sn + oy * c) * s.squash
            v[3], v[4] = s.uv[p], s.uv[p + 1]
            v[5], v[6], v[7], v[8] = cr, cg, cb, 1
            list[n] = v
            if v[1] < x0 then x0 = v[1] end
            if v[1] > x1 then x1 = v[1] end
            if v[2] < y0 then y0 = v[2] end
            if v[2] > y1 then y1 = v[2] end
        end
    end
    for i = n + 1, #list do list[i] = nil end
    g.count = n
    g.x0, g.y0, g.x1, g.y1 = x0, y0, x1, y1
    if n == 0 then return end
    if n > g.cap then
        g.cap = math.max(n, g.cap * 2, 96)
        g.mesh = love.graphics.newMesh(DEBRIS_FORMAT, g.cap, "triangles", "stream")
        g.mesh:setTexture(g.look.image)
    end
    g.mesh:setVertices(list)
    g.mesh:setDrawRange(1, n)
end

-- A heap that's lain still becomes ground; the oldest go past MAX_RUBBLE
local function settle(g)
    g.done = true
    for i = #g.shards, 1, -1 do
        if g.shards[i].chip then table.remove(g.shards, i) end
    end
    if #g.shards == 0 then return end
    build(g, true)
    g.list, g.pool = nil, nil
    rubble[#rubble + 1] = g
    rubbleCount = rubbleCount + #g.shards
    while rubbleCount > MAX_RUBBLE and #rubble > 1 do
        rubbleCount = rubbleCount - #table.remove(rubble, 1).shards
    end
end

-- Move a group on; true once it's settled (or there's nothing left of it).
-- `quiet`: not drawn till it's settled
local function step(g, dt, quiet)
    local moving = false
    for i = #g.shards, 1, -1 do
        local s = g.shards[i]
        if s.delay > 0 then
            s.delay = s.delay - dt
            moving = true
        elseif not s.rest then
            s.vz = s.vz - GRAVITY * dt
            s.x, s.y, s.z = s.x + s.vx * dt, s.y + s.vy * dt, s.z + s.vz * dt
            s.rot = s.rot + s.vr * dt
            if s.z <= 0 then
                s.z = 0
                if s.vz < -70 then -- bounce
                    s.vz = -s.vz * 0.28
                    s.vx, s.vy, s.vr = s.vx * 0.55, s.vy * 0.55, s.vr * 0.5
                else
                    s.rest, s.vz = true, 0
                end
            end
            moving = true
        end
        if s.z == 0 and s.squash > 0.5 then -- tipping over onto the ground
            s.squash = math.max(0.5, s.squash - dt * 4)
            moving = true
        end
        if s.chip and s.rest then
            s.life = s.life - dt
            if s.life <= 0 then table.remove(g.shards, i) end
            moving = true
        end
    end
    if #g.shards == 0 then
        g.done = true
        return true
    end
    if moving then
        g.still = 0
        if not quiet then build(g, false) end
        return false
    end
    g.still = g.still + dt
    if g.still >= SETTLE then
        settle(g)
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- Dust
--------------------------------------------------------------------------------

local function puff(x, y, z, size, life, color, vx, vy, vz, alpha)
    if #puffs >= MAX_PUFFS then table.remove(puffs, 1) end
    puffs[#puffs + 1] = { x = x, y = y, z = z, size = size, life = life, max = life, color = color,
        vx = vx or 0, vy = vy or 0, vz = vz or 12, alpha = alpha or 0.5, rot = love.math.random() * 6.28 }
end

--------------------------------------------------------------------------------
-- Breaking
--------------------------------------------------------------------------------

-- Shards `list` of st come away, pushed (px, py) with `power`; so does
-- whatever that leaves without support
local function breakOff(st, list, px, py, power)
    if #list == 0 then return end
    local g = groupOf(st)
    local any = false
    for _, idx in ipairs(list) do
        if st.alive[idx] then
            st.alive[idx] = nil
            addShard(g, st, idx, px, py, power)
            any = true
        end
    end
    if not any then return end
    for _, idx in ipairs(unsupported(st)) do
        st.alive[idx] = nil
        addShard(g, st, idx, px * 0.3, py * 0.3, power * 0.3)
    end
    st.broken = true
    reshape(st)
    pruneMarks(st)
    if not st.fmesh and not st.down and isHost() then
        -- nothing of it is left standing
        st.hp = math.min(st.hp, 0)
        pending[#pending + 1] = st
    end
end

-- The top crumbles above column u: one to three shards on its outline,
-- highest first
local function crumble(st, u, px, py)
    local P = st.pattern
    local near = {}
    for idx in pairs(st.alive) do
        if math.abs(P.tris[idx].cu - u) < 26 and loose(st, idx) then near[#near + 1] = idx end
    end
    table.sort(near, function(a, b) return P.tris[a].cv < P.tris[b].cv end)
    local list = {}
    for n = 1, math.min(#near, love.math.random(1, 3)) do list[n] = near[n] end
    breakOff(st, list, px * 0.3, py * 0.3, 0.05)
end

-- A hole knocked through around texel point (u, v), `radius` texels
local function punch(st, u, v, radius, px, py)
    local P = st.pattern
    local list = {}
    for idx in pairs(st.alive) do
        local t = P.tris[idx]
        if (t.cu - u) ^ 2 + (t.cv - v) ^ 2 < radius * radius then list[#list + 1] = idx end
    end
    breakOff(st, list, px, py, 1)
end

--- Structure st was hit at world (x, y) on its footprint by something
--- travelling (dx, dy), for `damage`: kind "bullet" (a hole, chips, now and
--- then a loose shard), "blast" (a scorch, shrapnel holes, a hole knocked
--- through) or "fire" (a scorch). `remote`: a client replaying the host's
--- hit (the host says when anything falls).
function destruction.hit(st, x, y, dx, dy, damage, kind, remote)
    if not st.hp or st.down then return end
    local P = fracture(st)
    local blast = kind == "blast"
    if not remote and var.multiplayer == 1 then
        hitSeq = hitSeq + 1
        hitLog[#hitLog + 1] = { hitSeq, st.key, math.floor(x * 10 + 0.5) / 10, math.floor(y * 10 + 0.5) / 10,
            math.floor(dx * 100 + 0.5) / 100, math.floor(dy * 100 + 0.5) / 100, math.floor(damage * 10 + 0.5) / 10,
            kind }
        hitTimes[#hitLog] = love.timer.getTime()
    end

    local before = st.hp / st.maxHp
    st.hp = st.hp - damage
    if remote then st.hp = math.max(st.hp, 1) end
    local after = math.max(0, st.hp / st.maxHp)
    st.push = { -dx, -dy } -- what falls comes back out of the face, the way the hit came from

    local lift = blast and (LIFT_MIN + LIFT_MAX) / 2 or LIFT_MIN + love.math.random() * (LIFT_MAX - LIFT_MIN)
    local u, v, tri = facePoint(st, x, y, lift)
    if u then
        local wx, wy = st.x + u * st.scale, st.y + v * st.scale
        if blast then
            -- a hole knocked through, soot round it (and into it), shrapnel
            -- holes in what's left
            local k = math.min(1, damage / destruction.BLAST)
            punch(st, u, v, (5 + 14 * k) / st.scale, -dx, -dy)
            addMark(st, { u, v, SCORCH, SCORCH, love.math.random(0, 3) * math.pi / 2, SCORCH_RECT })
            for _ = 1, 3 + math.floor(4 * k) do
                local su = u + (love.math.random() - 0.5) * 40 / st.scale
                local sv = v + (love.math.random() - 0.5) * 30 / st.scale
                su = math.max(0, math.min(st.qw - 1, math.floor(su)))
                sv = math.max(0, math.min(st.qh - 1, math.floor(sv)))
                local idx = solidAt(st, su, sv)
                if idx then hole(st, su + 0.5, sv + 0.5, idx) end
            end
            crack(st, u, v, 18 + 60 * (1 - after), 4 + math.floor(6 * k))
            for _ = 1, 4 do
                puff(wx + (love.math.random() - 0.5) * 24, y, y - wy, 16 + love.math.random() * 14,
                    1 + love.math.random() * 0.8, P.dust, -dx * 20, -dy * 20, 18, 0.55)
            end
        elseif kind == "fire" then
            addMark(st, { u, v, SCORCH, SCORCH, love.math.random(0, 3) * math.pi / 2, SCORCH_RECT, tri = tri })
            if after < 0.9 then crack(st, u, v, 10 + 60 * (1 - after), 2) end
            puff(wx, y, y - wy, 12 + love.math.random() * 8, 0.9 + love.math.random() * 0.5, { 0.3, 0.28, 0.26 },
                0, 0, 24, 0.5)
        else
            hole(st, u, v, tri)
            local g = groupOf(st)
            for _ = 1, love.math.random(2, 4) do addChip(g, st, u, v, y, -dx, -dy) end
            puff(wx, y, y - wy, 6 + love.math.random() * 5, 0.5 + love.math.random() * 0.3, P.dust,
                -dx * 25, -dy * 25, 10, 0.35)
            if after < 0.9 then
                crack(st, u, v, 10 + 60 * (1 - after), 1 + math.floor(damage / 8))
            end
            -- a loose shard on its outline may come away
            if tri and st.alive[tri] and loose(st, tri) and love.math.random() < 0.06 + 0.3 * (1 - after) then
                breakOff(st, { tri }, -dx, -dy, 0.15)
            end
        end
        for _, at in ipairs(CRUMBLE) do
            if before > at and after <= at then crumble(st, u, -dx, -dy) end
        end
    end
    if st.hp <= 0 and not remote then pending[#pending + 1] = st end
end

--- A shot hit fixture f at world (x, y), travelling (dx, dy): if it's a
--- structure's, that takes `damage` (kind: see destruction.hit; a bullet's
--- if not given).
function destruction.hitFixture(f, x, y, dx, dy, damage, kind)
    local st = destruction.of(f)
    if st then destruction.hit(st, x, y, dx, dy, damage, kind or "bullet") end
end

-- Every structure in the world rect, standing: the region's there, or the
-- home map's
local function near(x0, y0, x1, y1, fn)
    local r = regions.at((x0 + x1) / 2, (y0 + y1) / 2)
    if r.structures then
        for _, st in ipairs(r.structures) do
            local f = st.foot
            if not st.down and f[1] < x1 and f[3] > x0 and f[2] < y1 and f[4] > y0 then fn(st) end
        end
    else
        for _, arch in ipairs(map.archInstances) do
            local st = arch.structure
            if st and not st.down then
                local f = st.foot
                if f[1] < x1 and f[3] > x0 and f[2] < y1 and f[4] > y0 then fn(st) end
            end
        end
    end
end

--- A blast at world (x, y) reaching `radius` px: each structure it reaches
--- takes up to `damage`, less the further its footprint is from it.
function destruction.blast(x, y, radius, damage)
    near(x - radius, y - radius, x + radius, y + radius, function(st)
        local f = st.foot
        local nx, ny = math.max(f[1], math.min(f[3], x)), math.max(f[2], math.min(f[4], y))
        local dx, dy = nx - x, ny - y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < radius then
            if d > 0.001 then dx, dy = dx / d, dy / d else dx, dy = 0, -1 end
            destruction.hit(st, nx, ny, dx, dy, damage * (1 - d / radius), "blast")
        end
    end)
end

-- Bring st down: out of the world, every shard falling, dust. `instant`:
-- straight to a heap of rubble (a save loading)
local function collapse(st, instant)
    if st.down then return end
    st.down = true
    st.hp = 0
    fracture(st)
    if st.takeDown then st.takeDown(st) end
    local f = st.foot
    nav.forget(f[1], f[2], f[3], f[4])
    if st.look.id ~= "home" then down[st.key] = true end

    local g = groupOf(st)
    local push = st.push or { 0, 1 }
    local P = st.pattern
    for idx in pairs(st.alive) do
        local s = addShard(g, st, idx, push[1] * 0.25, push[2] * 0.25, 0.05)
        s.delay = instant and 0 or love.math.random() * 0.1 + (1 - P.tris[idx].cv / st.qh) * 0.06
    end
    st.alive = {}
    st.fmesh, st.decals, st.broken = nil, nil, false

    if instant then
        for i = #groups, 1, -1 do
            if groups[i] == g then table.remove(groups, i) end
        end
        for _ = 1, 90 do
            if step(g, 1 / 30, true) then break end
        end
        if not g.done then settle(g) end
        st.debris = nil
        return
    end

    -- dust along its foot, rising
    local w = st.qw * st.scale
    local size = math.min(1, w * st.qh * st.scale / 30000)
    for _ = 1, math.max(6, math.min(30, math.floor(w / 8))) do
        local px = st.x + love.math.random() * w
        local py = st.base - love.math.random() * st.depth
        puff(px, py, love.math.random() * st.qh * st.scale * 0.4, 18 + love.math.random() * 22 * (0.5 + size),
            1.4 + love.math.random() * 1.4, P.dust, (love.math.random() - 0.5) * 50, love.math.random() * 30,
            8 + love.math.random() * 20, 0.6)
    end
    local cx = st.x + w / 2
    audio.playSoundAt("explosion", cx, st.base, 0.1, 0.25 + 0.4 * size)
    if player and player.body then
        local px, py = player.body:getPosition()
        if (px - cx) ^ 2 + (py - st.base) ^ 2 < 700 * 700 then camera.shake(1.5 + 3 * size, 0.2 + 0.25 * size) end
    end
end

-- st as it was before anything hit it, standing
local function reset(st)
    if st.down and st.putBack then
        st.putBack(st)
        local f = st.foot
        nav.forget(f[1], f[2], f[3], f[4])
    end
    st.down = false
    down[st.key] = nil
    st.hp = st.maxHp
    st.pattern, st.alive, st.cracked, st.broken = nil, nil, nil, false
    st.fmesh, st.decals, st.push, st.debris = nil, nil, nil, nil
end

--------------------------------------------------------------------------------
-- Per frame
--------------------------------------------------------------------------------

function destruction.update(dt)
    -- what was knocked down in the physics step comes down now it's over
    if #pending > 0 then
        local list = pending
        pending = {}
        for _, st in ipairs(list) do
            if st.hp <= 0 then collapse(st) end
        end
    end
    for i = #groups, 1, -1 do
        if step(groups[i], dt) then
            local g = table.remove(groups, i)
            if g.st.debris == g then g.st.debris = nil end
        end
    end
    for i = #puffs, 1, -1 do
        local p = puffs[i]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(puffs, i)
        else
            p.x, p.y, p.z = p.x + p.vx * dt, p.y + p.vy * dt, p.z + p.vz * dt
            p.vx, p.vy = p.vx * (1 - 1.5 * dt), p.vy * (1 - 1.5 * dt)
        end
    end
    if #hitLog > 0 then
        local old = love.timer.getTime() - HIT_MEMORY
        while hitTimes[1] and hitTimes[1] < old do
            table.remove(hitLog, 1)
            table.remove(hitTimes, 1)
        end
    end
end

--- Shards in the air on screen into the dynamic draw list.
function destruction.populate()
    if #groups == 0 then return end
    local x0, y0, x1, y1 = regions.view(64)
    for _, g in ipairs(groups) do
        if g.count > 0 and g.x0 < x1 and g.x1 > x0 and g.y0 < y1 and g.y1 > y0 then
            dynamic_draw_list[#dynamic_draw_list + 1] = g.entry
        end
    end
end

--- A group of shards (the renderer's "debris"), lit like the sprite they
--- came from.
function destruction.drawGroup(g)
    if g.count == 0 or not g.mesh then return end
    local shader = love.graphics.getShader()
    regions.useLook(g.look)
    love.graphics.draw(g.mesh)
    love.graphics.setShader(shader)
end

--- st's marks, over it, after it's drawn (the renderer).
function destruction.drawMarks(st)
    local d = st.decals
    if not d then return end
    local shader = love.graphics.getShader()
    local r, g, b, a = love.graphics.getColor()
    local mode, alphaMode = love.graphics.getBlendMode()
    love.graphics.setShader(decalShader)
    decalShader:send("atlas", st.look.image)
    decalShader:send("bounds", st.bounds)
    decalShader:send("minAlpha", st.alphaMin)
    love.graphics.setBlendMode("multiply", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(d.mesh)
    love.graphics.setBlendMode(mode, alphaMode)
    love.graphics.setColor(r, g, b, a)
    love.graphics.setShader(shader)
end

--- Rubble on screen, with the ground (draw.lua, after regions.drawGround).
function destruction.drawRubble()
    if #rubble == 0 then return end
    local x0, y0, x1, y1 = regions.view(16)
    local shader = love.graphics.getShader()
    local mode, alphaMode = love.graphics.getBlendMode()
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    local look
    for _, g in ipairs(rubble) do
        if g.x0 < x1 and g.x1 > x0 and g.y0 < y1 and g.y1 > y0 then
            if g.look ~= look then
                look = g.look
                regions.useLook(look)
            end
            love.graphics.draw(g.mesh)
        end
    end
    love.graphics.setBlendMode(mode, alphaMode)
    love.graphics.setShader(shader)
end

--- Dust, over the sorted sprites (under the camera transform). It leaves
--- the scene's alpha (what the GI pass reads as walls) alone.
function destruction.drawEffects()
    if #puffs == 0 then return end
    love.graphics.push("all")
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
    love.graphics.setColorMask(true, true, true, false)
    local light = math.min(1, (shadow.ambient or 0.2) * 1.25 + 0.12)
    for _, p in ipairs(puffs) do
        local t = 1 - p.life / p.max -- 0 .. 1 through its life
        local a = p.alpha * math.min(1, t * 6) * (1 - t)
        local size = p.size * (0.5 + 1.1 * t)
        love.graphics.setColor(p.color[1] * light, p.color[2] * light, p.color[3] * light, a)
        love.graphics.draw(puffImage, p.x, p.y - p.z, p.rot + t, size / 32, size / 32, 16, 16)
    end
    love.graphics.pop()
end

--------------------------------------------------------------------------------
-- Saves and multiplayer
--------------------------------------------------------------------------------

--- The keys of what's down, for a save.
function destruction.getSaveData()
    local list = {}
    for key in pairs(down) do list[#list + 1] = key end
    table.sort(list)
    return list
end

--- Everything as a save says (`list`, the keys of what's down; nil: all of
--- it standing): what it has down lies in heaps, the rest stands unhurt.
function destruction.restore(list)
    pending, groups, rubble, puffs = {}, {}, {}, {}
    rubbleCount = 0
    local want = {}
    for _, key in ipairs(type(list) == "table" and list or {}) do want[key] = true end
    for key, st in pairs(registry) do
        if st.look.id ~= "home" then
            reset(st)
            if want[key] then collapse(st, true) end
        else
            st.debris = nil
        end
    end
end

--- The host's: what's down, and its latest hits (for the marks).
function destruction.getNetworkData()
    local keys = {}
    for key in pairs(down) do keys[#keys + 1] = key end
    return { down = table.concat(keys, ","), hits = hitLog }
end

--- A client: the host's hits it hasn't seen leave their marks, and what's
--- down comes down (what's back up, a save the host loaded, goes back up).
function destruction.applyNetworkData(data)
    if type(data) ~= "table" then return end
    local hits = data.hits
    if type(hits) == "table" and #hits > 0 then
        if hits[#hits][1] < lastSeen then lastSeen = 0 end -- the host started over
        for _, h in ipairs(hits) do
            if h[1] > lastSeen then
                lastSeen = h[1]
                local st = registry[h[2]]
                if st then destruction.hit(st, h[3], h[4], h[5], h[6], h[7], h[8], true) end
            end
        end
    end
    if type(data.down) ~= "string" then return end
    local want = {}
    for key in data.down:gmatch("[^,]+") do want[key] = true end
    for key in pairs(want) do
        local st = registry[key]
        if st and not st.down then collapse(st, not synced) end -- (joining: already rubble)
    end
    synced = true
    for key in pairs(down) do
        if not want[key] and registry[key] then reset(registry[key]) end
    end
end

return destruction
