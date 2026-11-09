--[[
  Princess rig: works out a 3D skeleton for every frame of the princess's
  sprite sheets and writes it to src/gfx/3d/princess/rig.lua, which
  game/armorModel.lua poses the armor on.

  The sheets are turntables: a row is one pose, its eight columns that pose
  from yaw k * 45 degrees, the same orthographic camera as the weapon models
  (55 degrees up, the axis at x 64.5). So a pose's silhouettes carve a visual
  hull, and the skeleton is read off that: the head is where the hair is
  thickest, the feet are the white shoes, the spine and legs follow the
  hull's middle from one to the other (a shortest path that keeps away from
  its surface), and each arm is the straightest way from its shoulder that
  stays inside the hull and outside the torso.

  Usage: love tools/princess_rig <out.lua> [debug.png]
]]

local ffi = require("ffi")

local ROOT = "src/gfx/3d/princess/"
local ANIMS = {
    { "walk", "walk copy.png", 18 },
    { "run", "run copy.png", 11 },
    { "shoot", "shoot copy.png", 15 },
    { "jump", "jump copy.png", 14 },
    { "roll", "roll3.png", 14 },
}

local F = 128
local CX, CY = 64.5, 70
local EL = math.rad(55)
local CE, SE = math.cos(EL), math.sin(EL)
local NX, NY, NZ = 80, 170, 80
local X0, Y0, Z0 = -40, -70, -40
local N = NX * NY * NZ

local cs, sn = {}, {}
for k = 0, 7 do cs[k], sn[k] = math.cos(k * math.pi / 4), math.sin(k * math.pi / 4) end

-- Body proportions, in texels: measured off the walk's hulls
local HEAD_DROP, CHEST_DROP = 11, 22 -- from the head's centre down the spine to the neck, the chest
local SPINE = 37                     -- head to pelvis, along it
local HIP, SHOULDER = 5.5, 8.5       -- out from the middle
local SHOULDER_DROP = 9              -- shoulder height, down the spine from the head
local ARM = 25                       -- shoulder to hand
local UPPER = 0.48                   -- of the arm, above the elbow
local ANKLE = 4                      -- up from the shoe's middle
local THIGH, SHIN = 16, 16

local function at(x, y, z) return (x - X0) + (z - Z0) * NX + (y - Y0) * NX * NZ end
local function project(k, x, y, z)
    local xr = x * cs[k] + z * sn[k]
    local zr = -x * sn[k] + z * cs[k]
    return CX + xr, CY - (y * CE - zr * SE), y * SE + zr * CE
end

local function readImage(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return love.image.newImageData(love.filesystem.newFileData(s, "x.png"))
end

local function isWhite(r, g, b) return math.min(r, g, b) > 0.74 end
local function isHair(r, g, b) return not isWhite(r, g, b) and g >= b * 1.4 and r >= b * 1.2 end

local function carve(img, row)
    local solid, grown, kind = {}, {}, {}
    for k = 0, 7 do
        local s, g, c = ffi.new("uint8_t[?]", F * F), ffi.new("uint8_t[?]", F * F), ffi.new("uint8_t[?]", F * F)
        for y = 0, F - 1 do
            for x = 0, F - 1 do
                local r, gg, b, a = img:getPixel(k * F + x, row * F + y)
                if a >= 0.25 then
                    s[y * F + x] = 1
                    c[y * F + x] = isWhite(r, gg, b) and 2 or isHair(r, gg, b) and 1 or 3
                end
            end
        end
        for y = 1, F - 2 do
            for x = 1, F - 2 do
                local v = 0
                for dy = -1, 1 do for dx = -1, 1 do v = v + s[(y + dy) * F + x + dx] end end
                g[y * F + x] = v > 0 and 1 or 0
            end
        end
        solid[k], grown[k], kind[k] = s, g, c
    end

    local inside = ffi.new("uint8_t[?]", N)
    local list, n = ffi.new("int32_t[?]", N), 0
    for y = Y0, Y0 + NY - 1 do
        for z = Z0, Z0 + NZ - 1 do
            for x = X0, X0 + NX - 1 do
                local ok = true
                for k = 0, 7 do
                    local u, v = project(k, x, y, z)
                    u, v = math.floor(u), math.floor(v)
                    if u < 0 or u >= F or v < 0 or v >= F or grown[k][v * F + u] == 0 then
                        ok = false
                        break
                    end
                end
                if ok then
                    inside[at(x, y, z)] = 1
                    list[n] = at(x, y, z)
                    n = n + 1
                end
            end
        end
    end

    -- What each voxel looks like, from the views it's the nearest thing in
    local hair, shoe = ffi.new("uint8_t[?]", N), ffi.new("uint8_t[?]", N)
    local votes = ffi.new("uint8_t[?]", N)
    local function decode(i)
        local y = math.floor(i / (NX * NZ))
        local rest = i - y * NX * NZ
        local z = math.floor(rest / NX)
        return rest - z * NX + X0, y + Y0, z + Z0
    end
    for k = 0, 7 do
        local top = ffi.new("float[?]", F * F)
        for i = 0, F * F - 1 do top[i] = -1e9 end
        for j = 0, n - 1 do
            local u, v, d = project(k, decode(list[j]))
            local i = math.floor(v) * F + math.floor(u)
            if d > top[i] then top[i] = d end
        end
        for j = 0, n - 1 do
            local u, v, d = project(k, decode(list[j]))
            local i = math.floor(v) * F + math.floor(u)
            if d >= top[i] - 1.5 and solid[k][i] == 1 then
                votes[list[j]] = votes[list[j]] + 1
                if kind[k][i] == 1 then hair[list[j]] = hair[list[j]] + 1 end
                if kind[k][i] == 2 then shoe[list[j]] = shoe[list[j]] + 1 end
            end
        end
    end

    -- How far each voxel is from the surface
    local dist = ffi.new("float[?]", N)
    for i = 0, N - 1 do dist[i] = inside[i] == 1 and 1e6 or 0 end
    local a, b, c = 1, 1.414, 1.732
    local function pass(sx)
        local ys, ye = sx > 0 and 1 or NY - 2, sx > 0 and NY - 2 or 1
        for iy = ys, ye, sx do
            for iz = (sx > 0 and 1 or NZ - 2), (sx > 0 and NZ - 2 or 1), sx do
                for ix = (sx > 0 and 1 or NX - 2), (sx > 0 and NX - 2 or 1), sx do
                    local i = ix + iz * NX + iy * NX * NZ
                    if inside[i] == 1 then
                        local best = dist[i]
                        for dy = -1, 0 do
                            for dz = -1, 1 do
                                for dx = -1, 1 do
                                    local before = dy < 0 or dz < 0 or (dz == 0 and dx < 0)
                                    if before then
                                        local m = math.abs(dx) + math.abs(dy) + math.abs(dz)
                                        local j = (ix + dx * sx) + (iz + dz * sx) * NX + (iy + dy * sx) * NX * NZ
                                        local v = dist[j] + (m == 1 and a or m == 2 and b or c)
                                        if v < best then best = v end
                                    end
                                end
                            end
                        end
                        dist[i] = best
                    end
                end
            end
        end
    end
    pass(1)
    pass(-1)

    return { inside = inside, list = list, n = n, hair = hair, shoe = shoe, votes = votes, dist = dist, decode = decode }
end

local function findHead(p, prev)
    -- A box the size of the head round wherever most hair is: long hair
    -- hanging down the back is only ever on one side of it
    local W, H = NX + 1, NZ + 1
    local sum = ffi.new("int32_t[?]", W * H * (NY + 1))
    for iy = 1, NY do
        for iz = 1, NZ do
            for ix = 1, NX do
                local i = (ix - 1) + (iz - 1) * NX + (iy - 1) * NX * NZ
                local v = (p.hair[i] > 0 and p.hair[i] * 2 >= p.votes[i]) and 1 or 0
                local function s(x, z, y) return sum[x + z * W + y * W * H] end
                sum[ix + iz * W + iy * W * H] = v + s(ix - 1, iz, iy) + s(ix, iz - 1, iy) + s(ix, iz, iy - 1)
                    - s(ix - 1, iz - 1, iy) - s(ix - 1, iz, iy - 1) - s(ix, iz - 1, iy - 1) + s(ix - 1, iz - 1, iy - 1)
            end
        end
    end
    local R = 8
    local function count(ix, iy, iz)
        local x0, x1 = math.max(ix - R, 0), math.min(ix + R + 1, NX)
        local y0, y1 = math.max(iy - R, 0), math.min(iy + R + 1, NY)
        local z0, z1 = math.max(iz - R, 0), math.min(iz + R + 1, NZ)
        local function s(x, z, y) return sum[x + z * W + y * W * H] end
        return s(x1, z1, y1) - s(x0, z1, y1) - s(x1, z0, y1) - s(x1, z1, y0)
            + s(x0, z0, y1) + s(x0, z1, y0) + s(x1, z0, y0) - s(x0, z0, y0)
    end
    local best, bx, by, bz = -1
    for j = 0, p.n - 1 do
        local x, y, z = p.decode(p.list[j])
        local c = count(x - X0, y - Y0, z - Z0)
        if prev then
            local dx, dy, dz = x - prev[1], y - prev[2], z - prev[3]
            c = c - 2 * math.sqrt(dx * dx + dy * dy + dz * dz)
        end
        if c > best then best, bx, by, bz = c, x, y, z end
    end
    -- The middle of the head: the thickest place near there
    local d, hx, hy, hz = -1, bx, by, bz
    for j = 0, p.n - 1 do
        local x, y, z = p.decode(p.list[j])
        local dx, dy, dz = x - bx, y - by, z - bz
        if dx * dx + dy * dy + dz * dz <= 36 and p.dist[p.list[j]] > d then
            d, hx, hy, hz = p.dist[p.list[j]], x, y, z
        end
    end
    return { hx, hy, hz }
end

-- The shoes are white, and so is the frill round her hips: it's only ever
-- close to the head (standing) or the middle of her (tumbling)
local function findFeet(p, prev, head, tumbling)
    local seen, comps = ffi.new("uint8_t[?]", N), {}
    local mx, my, mz, frill = 0, 0, 0, nil
    for j = 0, p.n - 1 do
        local x, y, z = p.decode(p.list[j])
        mx, my, mz = mx + x, my + y, mz + z
    end
    mx, my, mz = mx / p.n, my / p.n, mz / p.n
    for j = 0, p.n - 1 do
        local i = p.list[j]
        if p.shoe[i] > 0 and seen[i] == 0 then
            local stack, comp = { i }, { n = 0, x = 0, y = 0, z = 0 }
            seen[i] = 1
            while #stack > 0 do
                local v = table.remove(stack)
                local x, y, z = p.decode(v)
                comp.n, comp.x, comp.y, comp.z = comp.n + 1, comp.x + x, comp.y + y, comp.z + z
                for dy = -2, 2 do
                    for dz = -2, 2 do
                        for dx = -2, 2 do
                            local nx, ny, nz = x + dx, y + dy, z + dz
                            if nx >= X0 and nx < X0 + NX and ny >= Y0 and ny < Y0 + NY and nz >= Z0 and nz < Z0 + NZ then
                                local w = at(nx, ny, nz)
                                if p.shoe[w] > 0 and seen[w] == 0 then
                                    seen[w] = 1
                                    stack[#stack + 1] = w
                                end
                            end
                        end
                    end
                end
            end
            local c = { comp.x / comp.n, comp.y / comp.n, comp.z / comp.n, n = comp.n }
            if not frill or c.n > frill.n then
                if (c[1] - mx) ^ 2 + (c[2] - my) ^ 2 + (c[3] - mz) ^ 2 < 14 * 14 then frill = c end
            end
            local keep
            if not prev then
                keep = c.n >= 3
            elseif tumbling then
                keep = (c[1] - mx) ^ 2 + (c[2] - my) ^ 2 + (c[3] - mz) ^ 2 > 9 * 9
            else
                keep = head[2] - c[2] >= 42
            end
            if keep then comps[#comps + 1] = c end
        end
    end
    table.sort(comps, function(a, b) return a.n > b.n end)
    local function d2(p1, p2)
        return (p1[1] - p2[1]) ^ 2 + (p1[2] - p2[2]) ^ 2 + (p1[3] - p2[3]) ^ 2
    end
    if not prev then -- every animation starts on its feet: the two lowest, apart
        table.sort(comps, function(a, b) return a[2] < b[2] end)
        local a, b = comps[1], comps[1]
        for i = 2, #comps do
            if d2(a, comps[i]) >= 36 then
                b = comps[i]
                break
            end
        end
        if a[1] > b[1] then return a, b end -- +x is her left (she faces +z, the camera)
        return b, a
    end
    if tumbling then -- each shoe is whatever's nearest where it just was
        local function track(foot, taken)
            local best, bd = foot, 18 * 18
            for _, c in ipairs(comps) do
                local d = d2(c, foot)
                if c ~= taken and c.n >= 5 and d < bd then best, bd = c, d end
            end
            return best
        end
        local l = track(prev.footL)
        return l, track(prev.footR, l), frill
    end
    local a, b = comps[1], comps[2]
    if b and b.n < 3 then b = nil end
    if a and a.n < 3 then a = nil end
    if a and b then
        if d2(a, prev.footL) + d2(b, prev.footR) <= d2(a, prev.footR) + d2(b, prev.footL) then return a, b end
        return b, a
    end
    if a then
        if d2(a, prev.footL) <= d2(a, prev.footR) then return a, prev.footR end
        return prev.footL, a
    end
    return prev.footL, prev.footR
end

local function nearestInside(p, q)
    local best, bd = nil, 1e18
    for j = 0, p.n - 1 do
        local x, y, z = p.decode(p.list[j])
        local d = (x - q[1]) ^ 2 + (y - q[2]) ^ 2 + (z - q[3]) ^ 2 - 0.2 * p.dist[p.list[j]]
        if d < bd then best, bd = p.list[j], d end
    end
    return best
end

-- Shortest paths through the hull from `source`, keeping to its middle
local function middlePaths(p, source)
    local cost, from = ffi.new("float[?]", N), ffi.new("int32_t[?]", N)
    for j = 0, p.n - 1 do cost[p.list[j]] = 1e18 end
    cost[source] = 0
    from[source] = -1
    local heap, size, hc = {}, 0, {}
    local function push(i, c)
        size = size + 1
        local s = size
        heap[s], hc[s] = i, c
        while s > 1 do
            local u = math.floor(s / 2)
            if hc[u] <= hc[s] then break end
            heap[u], heap[s], hc[u], hc[s] = heap[s], heap[u], hc[s], hc[u]
            s = u
        end
    end
    local function pop()
        local i, c = heap[1], hc[1]
        heap[1], hc[1] = heap[size], hc[size]
        heap[size], hc[size] = nil, nil
        size = size - 1
        local s = 1
        while true do
            local l, r, m = s * 2, s * 2 + 1, s
            if l <= size and hc[l] < hc[m] then m = l end
            if r <= size and hc[r] < hc[m] then m = r end
            if m == s then break end
            heap[m], heap[s], hc[m], hc[s] = heap[s], heap[m], hc[s], hc[m]
            s = m
        end
        return i, c
    end
    push(source, 0)
    while size > 0 do
        local i, c = pop()
        if c <= cost[i] then
            local x, y, z = p.decode(i)
            for dy = -1, 1 do
                for dz = -1, 1 do
                    for dx = -1, 1 do
                        if dx ~= 0 or dy ~= 0 or dz ~= 0 then
                            local j = at(x + dx, y + dy, z + dz)
                            if j >= 0 and j < N and p.inside[j] == 1 then
                                local len = math.sqrt(dx * dx + dy * dy + dz * dz)
                                local nc = c + len * (1 + 40 / (p.dist[j] ^ 2 + 0.5))
                                if nc < cost[j] then
                                    cost[j], from[j] = nc, i
                                    push(j, nc)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return function(target) -- points from source to target, smoothed
        local pts, i = {}, target
        while i ~= -1 do
            local x, y, z = p.decode(i)
            table.insert(pts, 1, { x, y, z })
            i = from[i]
        end
        local out = {}
        for k = 1, #pts do
            local sx, sy, sz, c = 0, 0, 0, 0
            for m = math.max(1, k - 2), math.min(#pts, k + 2) do
                sx, sy, sz, c = sx + pts[m][1], sy + pts[m][2], sz + pts[m][3], c + 1
            end
            out[k] = { sx / c, sy / c, sz / c }
        end
        return out
    end
end

-- The point `dist` along a path; `path` runs from its first point
local function along(path, dist)
    local run = 0
    for i = 2, #path do
        local a, b = path[i - 1], path[i]
        local seg = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
        if run + seg >= dist and seg > 0 then
            local t = (dist - run) / seg
            return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
        end
        run = run + seg
    end
    return { path[#path][1], path[#path][2], path[#path][3] }
end

local function reversed(path)
    local out = {}
    for i = #path, 1, -1 do out[#out + 1] = path[i] end
    return out
end

local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function add(a, b, s) s = s or 1; return { a[1] + b[1] * s, a[2] + b[2] * s, a[3] + b[3] * s } end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function len(a) return math.sqrt(dot(a, a)) end
local function unit(a) local l = len(a); return l > 1e-5 and { a[1] / l, a[2] / l, a[3] / l } or { 0, 1, 0 } end
local function cross(a, b)
    return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end

local function sample(p, q)
    local x, y, z = math.floor(q[1] + 0.5), math.floor(q[2] + 0.5), math.floor(q[3] + 0.5)
    if x < X0 or x >= X0 + NX or y < Y0 or y >= Y0 + NY or z < Z0 or z >= Z0 + NZ then return 0 end
    return p.dist[at(x, y, z)]
end

-- Where the arm from `shoulder` goes: as far as you can walk through the
-- hull without going through her torso, head, hair or legs
local function findArm(p, shoulder, chest, pelvis, head, right, prevHand)
    local axis = unit(sub(chest, pelvis))
    local forward = cross(right, axis)
    local outward = dot(sub(shoulder, chest), right) > 0 and 1 or -1
    local function allowed(x, y, z, i)
        if p.hair[i] > 0 and p.hair[i] * 2 >= p.votes[i] then return false end
        local q = { x, y, z }
        if len(sub(q, head)) < 12 then return false end
        local d = sub(q, pelvis)
        local up, across, depth = dot(d, axis), dot(d, right), dot(d, forward)
        if up < -8 or across * outward < 1 then return false end
        local waist = up < 12 and 11.5 or 8 -- her hips are wider than her chest
        return (across / waist) ^ 2 + (depth / 8) ^ 2 >= 1
    end

    local start, best = nil, 1e18
    for j = 0, p.n - 1 do
        local x, y, z = p.decode(p.list[j])
        if allowed(x, y, z, p.list[j]) then
            local d = (x - shoulder[1]) ^ 2 + (y - shoulder[2]) ^ 2 + (z - shoulder[3]) ^ 2
            if d < best then start, best = p.list[j], d end
        end
    end
    local fallback = { shoulder[1] + outward * 2, shoulder[2] - ARM, shoulder[3] }
    if not start or best > 36 then return fallback, add(shoulder, sub(fallback, shoulder), UPPER) end

    -- Spread out from the shoulder; `cost` is how far you've walked
    local cost, from, queue, head1 = { [start] = 0 }, { [start] = -1 }, { start }, 1
    while head1 <= #queue do
        local i = queue[head1]
        head1 = head1 + 1
        local x, y, z = p.decode(i)
        for dy = -1, 1 do
            for dz = -1, 1 do
                for dx = -1, 1 do
                    if dx ~= 0 or dy ~= 0 or dz ~= 0 then
                        local j = at(x + dx, y + dy, z + dz)
                        if j >= 0 and j < N and p.inside[j] == 1 then
                            local c = cost[i] + math.sqrt(dx * dx + dy * dy + dz * dz)
                            if c <= ARM * 1.15 and (not cost[j] or c < cost[j] - 1e-3) and allowed(x + dx, y + dy, z + dz, j) then
                                cost[j], from[j] = c, i
                                queue[#queue + 1] = j
                            end
                        end
                    end
                end
            end
        end
    end

    -- The hand: furthest from the shoulder and out from her, near where it just was
    local hand, score = nil, -1e18
    for i, c in pairs(cost) do
        if c >= 10 then
            local x, y, z = p.decode(i)
            local q = { x, y, z }
            local d = sub(q, pelvis)
            local s = len(sub(q, shoulder)) + c * 0.2 + len(sub(d, axis, dot(d, axis))) * 0.8 -- out from her, not down her side
            if prevHand then s = s - len(sub(q, prevHand)) * 0.12 end
            if s > score then hand, score = i, s end
        end
    end
    if not hand then return fallback, add(shoulder, sub(fallback, shoulder), UPPER) end

    local path, i = {}, hand
    while i ~= -1 do
        local x, y, z = p.decode(i)
        table.insert(path, 1, { x, y, z })
        i = from[i]
    end
    table.insert(path, 1, shoulder)
    local smooth = {}
    for k = 1, #path do
        local sx, sy, sz, c = 0, 0, 0, 0
        for m = math.max(1, k - 2), math.min(#path, k + 2) do
            sx, sy, sz, c = sx + path[m][1], sy + path[m][2], sz + path[m][3], c + 1
        end
        smooth[k] = { sx / c, sy / c, sz / c }
    end
    local total = 0
    for k = 2, #smooth do total = total + len(sub(smooth[k], smooth[k - 1])) end
    return smooth[#smooth], along(smooth, total * UPPER)
end

-- A two-bone chain's middle joint: bent toward `bend`, its lengths kept
local function ik(a, b, l1, l2, bend)
    local d = sub(b, a)
    local dist = math.min(len(d), (l1 + l2) * 0.999)
    local u = unit(d)
    local x = (dist * dist + l1 * l1 - l2 * l2) / (2 * dist)
    local h = math.sqrt(math.max(0, l1 * l1 - x * x))
    local side = unit(sub(bend, u, dot(bend, u)))
    return add(add(a, u, x), side, h)
end

local function fit(p, prev, tumbling)
    local head = findHead(p, prev and prev.head)
    local footL, footR, frill = findFeet(p, prev, head, tumbling)

    local paths = middlePaths(p, nearestInside(p, head))
    local toL = paths(nearestInside(p, footL))
    local toR = paths(nearestInside(p, footR))

    local spine = #toL >= #toR and toL or toR
    if tumbling then -- curled up, the middle of the hull has no spine to follow: its hips are the frill
        local hips = (frill and frill.n >= 15) and frill or (prev and prev.pelvis) or along(spine, SPINE)
        spine = { head, { hips[1], hips[2], hips[3] } }
    end
    local pelvis = along(spine, SPINE)
    local neck = along(spine, HEAD_DROP)
    local chest = along(spine, CHEST_DROP)
    local shoulderMid = along(spine, SHOULDER_DROP)

    local up = unit(sub(neck, pelvis))
    local right = { 1, 0, 0 } -- she faces +z throughout, even tumbling (about this axis)
    local forward = cross(right, up)

    local hipL, hipR = add(pelvis, right, HIP), add(pelvis, right, -HIP)
    local shoulderL, shoulderR = add(shoulderMid, right, SHOULDER), add(shoulderMid, right, -SHOULDER)

    local function leg(hip, foot, path)
        local fromFoot = reversed(path)
        local ankle = along(fromFoot, ANKLE)
        local knee = along(fromFoot, ANKLE + 16)
        return ankle, knee
    end
    local ankleL, kneeL = leg(hipL, footL, toL)
    local ankleR, kneeR = leg(hipR, footR, toR)
    if tumbling then
        ankleL, ankleR = add(footL, unit(sub(pelvis, footL)), ANKLE), add(footR, unit(sub(pelvis, footR)), ANKLE)
        kneeL, kneeR = ik(hipL, ankleL, THIGH, SHIN, forward), ik(hipR, ankleR, THIGH, SHIN, forward)
    end

    local handL, elbowL = findArm(p, shoulderL, chest, pelvis, head, right, prev and prev.handL)
    local handR, elbowR = findArm(p, shoulderR, chest, pelvis, head, right, prev and prev.handR)

    return {
        head = head, neck = neck, chest = chest, pelvis = pelvis,
        shoulderL = shoulderL, shoulderR = shoulderR, elbowL = elbowL, elbowR = elbowR, handL = handL, handR = handR,
        hipL = hipL, hipR = hipR, kneeL = kneeL, kneeR = kneeR, ankleL = ankleL, ankleR = ankleR,
        footL = footL, footR = footR,
    }
end

-- The arms are the least certain joints: take out a frame's stray guess (the
-- median of three) and ease what's left. Every animation but the roll loops.
local function smoothArms(poses)
    local n = #poses
    for _, name in ipairs({ "elbowL", "elbowR", "handL", "handR" }) do
        local out = {}
        for i = 1, n do
            local a, b, c = poses[(i - 2) % n + 1][name], poses[i][name], poses[i % n + 1][name]
            local q = {}
            for k = 1, 3 do
                local t = { a[k], b[k], c[k] }
                table.sort(t)
                q[k] = t[2]
            end
            out[i] = q
        end
        for i = 1, n do
            local a, b, c = out[(i - 2) % n + 1], out[i], out[i % n + 1]
            poses[i][name] = { (a[1] + 2 * b[1] + c[1]) / 4, (a[2] + 2 * b[2] + c[2]) / 4, (a[3] + 2 * b[3] + c[3]) / 4 }
        end
    end
end

local JOINTS = {
    "head", "neck", "chest", "pelvis", "shoulderL", "shoulderR", "elbowL", "elbowR", "handL", "handR",
    "hipL", "hipR", "kneeL", "kneeR", "ankleL", "ankleR", "footL", "footR",
}
local LINES = {
    { "head", "neck", 1, 1, 0 }, { "neck", "chest", 1, 0, 0 }, { "chest", "pelvis", 1, 0, 0 },
    { "shoulderL", "shoulderR", 0, 1, 1 }, { "hipL", "hipR", 0, 1, 1 },
    { "shoulderL", "elbowL", 0, 1, 0 }, { "elbowL", "handL", 0, 0.6, 0 },
    { "shoulderR", "elbowR", 0, 0.5, 1 }, { "elbowR", "handR", 0, 0.3, 0.7 },
    { "hipL", "kneeL", 0, 1, 0 }, { "kneeL", "ankleL", 0, 0.6, 0 }, { "ankleL", "footL", 1, 1, 1 },
    { "hipR", "kneeR", 0, 0.5, 1 }, { "kneeR", "ankleR", 0, 0.3, 0.7 }, { "ankleR", "footR", 1, 1, 1 },
}

local function debugSheet(results, out, images)
    local S, C = 5, 72
    local picks = {}
    local want = { walk = 5, run = 5, shoot = 9, jump = 8, roll = 4 }
    for _, r in ipairs(results) do picks[#picks + 1] = { r, want[r.name] } end
    local COLS = { 0, 1, 2, 4 }
    local W, H = #COLS * C * S, #picks * C * S
    local im = love.image.newImageData(W, H)
    local function dot2(x, y, r, g, b) if x >= 0 and y >= 0 and x < W and y < H then im:setPixel(x, y, r, g, b, 1) end end
    for i, pick in ipairs(picks) do
        local r, frame = pick[1], pick[2]
        local img, pose = images[r.name], r.poses[frame]
        for c, k in ipairs(COLS) do
            local ox, oy = (c - 1) * C * S, (i - 1) * C * S
            local top = r.name == "roll" and 44 or 12
            for y = 0, C - 1 do
                for x = 0, C - 1 do
                    local sx, sy = x + 28, y + top
                    local cr, cg, cb, a = img:getPixel(k * F + sx, (frame - 1) * F + sy)
                    local bg = 0.13
                    for a1 = 0, S - 1 do
                        for b1 = 0, S - 1 do
                            dot2(ox + x * S + a1, oy + y * S + b1, cr * a + bg * (1 - a), cg * a + bg * (1 - a), cb * a + bg * (1 - a))
                        end
                    end
                end
            end
            local function pt(q)
                local u, v = project(k, q[1], q[2], q[3])
                return ox + (u - 28) * S, oy + (v + 0.5 - top) * S
            end
            for _, l in ipairs(LINES) do
                local x1, y1 = pt(pose[l[1]])
                local x2, y2 = pt(pose[l[2]])
                local steps = math.max(math.abs(x2 - x1), math.abs(y2 - y1), 1)
                for t = 0, steps do
                    local px, py = math.floor(x1 + (x2 - x1) * t / steps), math.floor(y1 + (y2 - y1) * t / steps)
                    dot2(px, py, l[3], l[4], l[5]); dot2(px + 1, py, l[3], l[4], l[5]); dot2(px, py + 1, l[3], l[4], l[5])
                end
            end
        end
    end
    local f = assert(io.open(out, "wb"))
    f:write(im:encode("png"):getString())
    f:close()
end

function love.errorhandler(msg)
    print(debug.traceback(tostring(msg), 2))
    os.exit(1)
end

function love.load(args)
    local out = assert(args[1], "usage: love tools/princess_rig <out.lua> [debug.png]")
    local base = love.filesystem.getSource() .. "/../../"
    local results, images = {}, {}
    for _, anim in ipairs(ANIMS) do
        local img = readImage(base .. ROOT .. anim[2])
        images[anim[1]] = img
        local r = { name = anim[1], poses = {} }
        local prev
        for row = 0, anim[3] - 1 do
            local p = carve(img, row)
            local pose = fit(p, prev, anim[1] == "roll")
            r.poses[row + 1] = pose
            prev = pose
        end
        smoothArms(r.poses)
        results[#results + 1] = r
        print(anim[1], #r.poses)
    end

    local lines = {
        "-- Generated by tools/princess_rig (don't edit): a 3D skeleton for each frame of",
        "-- each of the princess's animations, in sprite texels: +x her left, +y up, +z",
        "-- the way she faces.",
        "return {",
        "    joints = { \"" .. table.concat(JOINTS, "\", \"") .. "\" },",
    }
    for _, r in ipairs(results) do
        lines[#lines + 1] = "    " .. r.name .. " = {"
        for _, pose in ipairs(r.poses) do
            local v = {}
            for _, j in ipairs(JOINTS) do
                local q = pose[j]
                v[#v + 1] = string.format("%.1f,%.1f,%.1f", q[1], q[2], q[3])
            end
            lines[#lines + 1] = "        { " .. table.concat(v, ", ") .. " },"
        end
        lines[#lines + 1] = "    },"
    end
    lines[#lines + 1] = "}"
    local f = assert(io.open(out, "w"))
    f:write(table.concat(lines, "\n"), "\n")
    f:close()
    print("wrote " .. out)

    if args[2] then debugSheet(results, args[2], images) end
    love.event.quit()
end
