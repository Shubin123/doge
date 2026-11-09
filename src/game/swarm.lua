--[[
  The swarm: flywire-swarm (js/sim.js, js/heuristics.js, js/game.js,
  js/cluster.js) living in the Wasteland, around its boss (game/swarmBoss.lua).
  It runs while that boss is unbeaten and you're in its region, so the place
  is full of flies until you kill it.

  Each fly runs its own reduced FlyWire connectome (game/flywire.lua):
    senses       sugar and bitter on the ground, odour, looming things (LPLC2),
                 jostling (Johnston's organ), its goal's bearing (into PFL3)
    what it does Giant Fiber: escape take-off; MDN: back off; DNp09: walk;
                 DNa02/DNa01: turn; MN9: feed; octopamine: pick the selfish play
  and over them the rest of the original, in its numbers (distances x U):
    heuristics   take-the-best on patches, A* to them (lib/nav.lua), satisficing
    game theory  Hawk-Dove (or Stag Hunt, Prisoner's Dilemma) on the food, in
                 expected payoffs; hawks wound each other; flies copy richer
                 neighbours with the Fermi rule, so the mix evolves
    clusters     DBSCAN swarms (the bird dives the biggest), k-means on neural
                 activity for behavioural modes
    life cycle   adults mate on the ground, females lay on food, eggs, larvae
                 (crowded ones starve) and pupae, then new adults. Nothing tops
                 the population up: it's births minus deaths
    predators    the bird's dives, dragonflies running down the wounded
  You are the anti-fly measure now: a body rushing at them looms (speed, not
  size, as the original's robots: walk up slowly and they don't startle),
  your shots go through them, blasts clear the heaps, and hawks bite.

  Where the world runs (host, single player) it steps at the original's 30 Hz;
  clients draw the flies the host sends. A fly that's part of the boss's body
  (role 1) goes where the boss's formation puts it, over walls and all.

  Drawn from small baked sprites: the flies a band of the sorted list at a
  time, what's on the ground first. Everything writes the ground's alpha, so
  the GI pass doesn't take a fly for a wall.
]]
local swarm = {}

local flywire = require("game.flywire")
local nav = require("lib.nav")
local random = love.math.random
local sin, cos, atan2, sqrt, floor, max, min, abs, exp = math.sin, math.cos, math.atan2, math.sqrt, math.floor,
    math.max, math.min, math.abs, math.exp

local U = 16              -- world px per unit of the original's arena
local DT = 1 / 30         -- the original's tick
local TAU = math.pi * 2
local CAP = 300           -- adults at once
local START_FLIES = 190
local BROOD_CAP = 520
local CORPSE_CAP = 320
local CORPSE_LIFE = 14    -- seconds a dead fly lies there (the original: 6)
local LAND = 0.6 * U      -- this low it's on the ground
local BRAINS = rawget(_G, "jit") and 140 or 6 -- brains a tick (each fly every other, with a JIT)
local PLANS = rawget(_G, "jit") and 3 or 1    -- A* searches a tick
local NI, NO = flywire.NI, flywire.NO

-- the life cycle: 20 % egg, 50 % larva, 30 % pupa of `develop` seconds
local EGG_END, LARVA_END = 0.2, 0.7
local MATURE_AGE = 6
local EGG_COST, LAY_RESERVE, LAY_GAP = 1, 4, 12
local LARVA_FOOD, LARVA_ROOM = 0.01, 0.09
local NURSERY_CROWD, PUPATE_FED = 6, 0.4

local BITE_R, BITE_Z = 18, 70       -- px: this near you, and this low, it can bite
local BITE_BODY, BITE_WILD = 5, 2   -- HP

local GAMES = {
    hawkdove = function(V, C) return { { (V - C) / 2, V }, { 0, V / 2 } } end,
    pd = function(V, C) return { { 0, V }, { -C, V - C } } end,
    stag = function(V, C) return { { C, C }, { 0, V } } end,
}

local FLOATS = { "x", "y", "z", "px", "py", "pz", "h", "speed", "vz", "energy", "age", "life", "kvx", "kvy", "hp",
    "hurt", "hawk", "gainG", "intake", "wing", "escape", "cooldown", "decide", "oa", "residence", "payoff",
    "mateHawk", "mateGain", "layTimer", "wear", "threatX", "threatY", "startle", "biteCd", "slot", "flash" }
local INTS = { "played", "lastHawk", "target", "pathIdx", "label", "mode", "generation", "feeding", "id", "sex",
    "mated", "degree", "role", "strike" }

local S -- the running simulation; nil where there's no swarm

local function hosting()
    return not var.multiplayer or var.multiplayer == 1
end

local function wrap(a) return atan2(sin(a), cos(a)) end
local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end
local function sigmoid(x) return 1 / (1 + exp(-x)) end
local function gauss() return sqrt(-2 * math.log(random() + 1e-12)) * cos(TAU * random()) end

local function disposition(i) return sigmoid(4 * S.f.hawk[i]) end
-- octopamine pushes it toward the selfish play
local function choiceProb(i) return sigmoid(4 * S.f.hawk[i] + 3 * (S.f.oa[i] - 0.05)) end

--------------------------------------------------------------------------------
-- Spatial hash: linked lists through arrays, rebuilt each tick
--------------------------------------------------------------------------------

local function hashBuild()
    local head, nxt, X, Y = S.head, S.nxt, S.f.x, S.f.y
    local cols, rows, x0, y0, cell = S.cols, S.rows, S.x0, S.y0, S.cell
    for c = 0, cols * rows - 1 do head[c] = -1 end
    for i = 0, S.n - 1 do
        local cx = max(0, min(cols - 1, floor((X[i] - x0) / cell)))
        local cy = max(0, min(rows - 1, floor((Y[i] - y0) / cell)))
        local c = cy * cols + cx
        nxt[i] = head[c]
        head[c] = i
    end
end

-- Flies within r (<= a cell) of (x, y) into `out`; how many
local function query(x, y, r, out)
    local head, nxt, X, Y = S.head, S.nxt, S.f.x, S.f.y
    local cols, rows, cell = S.cols, S.rows, S.cell
    local ci, cj = floor((x - S.x0) / cell), floor((y - S.y0) / cell)
    local r2, m = r * r, 0
    for cy = max(0, cj - 1), min(rows - 1, cj + 1) do
        for cx = max(0, ci - 1), min(cols - 1, ci + 1) do
            local i = head[cy * cols + cx]
            while i >= 0 do
                local dx, dy = X[i] - x, Y[i] - y
                if dx * dx + dy * dy <= r2 then
                    m = m + 1
                    out[m] = i
                end
                i = nxt[i]
            end
        end
    end
    return m
end

--------------------------------------------------------------------------------
-- The food: rotting heaps (sugar) and sludge (bitter)
--------------------------------------------------------------------------------

local function freeAt(x, y)
    local grid = S.grid
    local cx, cy = grid:cellAt(x, y)
    return grid:free(cx, cy)
end

local function roomFor(x, y, r)
    if not freeAt(x, y) then return false end
    for k = 0, 7 do
        local a = k / 8 * TAU
        if not freeAt(x + cos(a) * r, y + sin(a) * r) then return false end
    end
    return true
end

local function newPatch(bitter, near)
    local rng = S.rng
    for _ = 1, 300 do
        local x, y
        if near then
            local a, d = rng:random() * TAU, 260 + rng:random() * 280
            x, y = S.lairX + cos(a) * d, S.lairY + sin(a) * d
        else
            x = S.ox + 160 + rng:random() * (S.w - 320)
            y = S.oy + 200 + rng:random() * (S.h - 400)
        end
        local r = bitter and 4 * U or (3.8 + rng:random() * 2.4) * U
        local clear = roomFor(x, y, r) and (x - S.lairX) ^ 2 + (y - S.lairY) ^ 2 > (r + 120) ^ 2
        if clear and S.region.portal then
            clear = (x - S.region.portal.x) ^ 2 + (y - S.region.portal.y) ^ 2 > (r + 200) ^ 2
        end
        for _, q in ipairs(S.patches) do
            if clear and (q.x - x) ^ 2 + (q.y - y) ^ 2 < (q.r + r + 6 * U) ^ 2 then clear = false end
        end
        if clear then
            local p = { x = x, y = y, r = r, bitter = bitter, sugar = bitter and 0 or 0.6 + rng:random() * 0.4,
                occupants = 0, brood = 0, age = 0, pieces = {} }
            if not bitter then
                for k = 1, floor(r / 4) do
                    local a, d = rng:random() * TAU, sqrt(rng:random()) * (r - 8)
                    p.pieces[k] = { x = x + cos(a) * d, y = y + sin(a) * d * 0.75, kind = rng:random(1, 6),
                        flip = rng:random() < 0.5 and -1 or 1 }
                end
            end
            return p
        end
    end
    return { x = S.lairX, y = S.lairY + 300, r = 3 * U, bitter = bitter, sugar = bitter and 0 or 1, occupants = 0,
        brood = 0, age = 0, pieces = {} }
end

local function patchAt(x, y)
    for _, p in ipairs(S.patches) do
        if (p.x - x) ^ 2 + (p.y - y) ^ 2 < p.r * p.r then return p end
    end
end

local function odorAt(x, y)
    local c, sigma = 0, 2 * (16 * U) ^ 2
    for _, p in ipairs(S.patches) do
        if not p.bitter and p.sugar > 0.02 then
            c = c + p.sugar * exp(-((p.x - x) ^ 2 + (p.y - y) ^ 2) / sigma)
        end
    end
    return c
end

local function larvaRoom(p)
    return LARVA_ROOM * S.params.food * (p.r / U) ^ 2
end

--------------------------------------------------------------------------------
-- Flies
--------------------------------------------------------------------------------

local function broodStage(b)
    local D = S.params.develop
    return b.age < EGG_END * D and 0 or (b.age < LARVA_END * D and 1 or 2)
end

local function seedBrood()
    local food = {}
    for _, p in ipairs(S.patches) do
        if not p.bitter then food[#food + 1] = p end
    end
    if #food == 0 then return end
    local p = food[random(#food)]
    local a, r = random() * TAU, sqrt(random()) * p.r * 0.85
    local age = random() * S.params.develop
    S.brood[#S.brood + 1] = { x = p.x + cos(a) * r, y = p.y + sin(a) * r, age = age,
        fed = age > EGG_END * S.params.develop and 0.5 + 0.5 * random() or 0, vigor = 0.6 + 0.8 * random(),
        hawk = (random() - 0.5) * 3, gain = 1 + (random() - 0.5) * 0.3, gen = 0 }
end

-- A founder (pupa nil: random genes, somewhere near food, any adult age) or an
-- adult eclosing from a pupa (well-fed larvae make adults with bigger reserves)
local function spawn(i, pupa)
    local f = S.f
    if pupa then
        f.x[i], f.y[i], f.z[i] = pupa.x, pupa.y, 0
        f.hawk[i], f.gainG[i], f.generation[i] = pupa.hawk, pupa.gain, pupa.gen
        f.energy[i], f.wear[i] = 2 + 4 * pupa.fed, 0
    else
        local x, y = S.lairX, S.lairY
        for _ = 1, 12 do
            local p = S.patches[random(#S.patches)]
            x, y = p.x + gauss() * 150, p.y + gauss() * 150
            if freeAt(x, y) then break end
        end
        f.x[i], f.y[i], f.z[i] = x, y, (1 + random() * 3) * U
        f.hawk[i], f.gainG[i], f.generation[i] = (random() - 0.5) * 3, 1 + (random() - 0.5) * 0.3, 0
        f.energy[i], f.wear[i] = 4, random() * 0.5
    end
    flywire.reset(S.pool, i)
    f.px[i], f.py[i], f.pz[i] = f.x[i], f.y[i], f.z[i]
    f.id[i] = S.nextId
    S.nextId = S.nextId + 1
    f.sex[i] = random() < 0.5 and 0 or 1
    f.mated[i], f.mateHawk[i], f.mateGain[i], f.layTimer[i] = 0, 0, 0, 0
    f.h[i], f.speed[i], f.vz[i] = random() * TAU, 3 * U, 0
    f.hp[i], f.hurt[i], f.kvx[i], f.kvy[i] = 1, 9, 0, 0
    f.life[i] = 0.75 + random() * 0.5
    f.age[i] = f.wear[i] * f.life[i] * S.params.lifespan
    f.intake[i], f.residence[i], f.payoff[i], f.played[i] = 0.3, 0, 0, 0
    f.escape[i], f.cooldown[i], f.decide[i], f.target[i] = 0, 0, random(), -1
    f.lastHawk[i], f.wing[i], f.oa[i] = -1, random() * TAU, 0
    f.startle[i], f.biteCd[i], f.flash[i], f.role[i], f.strike[i] = 0, random(), 0, 0, 0
    f.slot[i] = random()
    f.path[i] = nil
end

local function moveFly(from, to)
    local f = S.f
    for _, name in ipairs(FLOATS) do f[name][to] = f[name][from] end
    for _, name in ipairs(INTS) do f[name][to] = f[name][from] end
    f.path[to] = f.path[from]
    flywire.move(S.pool, from, to)
end

-- `dmg` to fly i's body; at no health it's dead, come lifeCycle. True if this killed it
local function wound(i, dmg)
    local f = S.f
    if f.hp[i] <= 0 then return false end
    f.hp[i] = max(0, f.hp[i] - dmg)
    f.hurt[i] = 0
    f.flash[i] = 1
    return f.hp[i] <= 0
end

local function push(i, dvx, dvz, dvy)
    S.f.kvx[i] = S.f.kvx[i] + dvx
    S.f.kvy[i] = S.f.kvy[i] + dvy
    S.f.vz[i] = S.f.vz[i] + dvz
end

local function gravid(i)
    local f = S.f
    return f.sex[i] == 0 and f.mated[i] == 1 and f.age[i] >= MATURE_AGE
        and f.energy[i] >= LAY_RESERVE + EGG_COST * min(4, max(1, S.params.clutch))
end

--------------------------------------------------------------------------------
-- Heuristics
--------------------------------------------------------------------------------

local PATCH_CUES = {
    { label = "richer", better = function(a, b) return a.sugar - b.sugar end, jnd = 0.25 },
    { label = "rivals", better = function(a, b) return b.crowd - a.crowd end, jnd = 2 },
    { label = "closer", better = function(a, b) return b.dist - a.dist end, jnd = 3 * U },
}
-- a female carrying eggs looks for a nursery first
local NURSERY_CUES = { { label = "room", better = function(a, b) return a.room - b.room end, jnd = 0.3 },
    PATCH_CUES[1], PATCH_CUES[2], PATCH_CUES[3] }

-- Take-the-best: compare options cue by cue and decide on the first that discriminates
local function takeTheBest(options, cues)
    local best = options[1]
    for k = 2, #options do
        local o = options[k]
        for _, cue in ipairs(cues) do
            local d = cue.better(o, best)
            if abs(d) >= cue.jnd then
                if d > 0 then best = o end
                break
            end
        end
    end
    return best
end

local function choosePatch(i)
    local f = S.f
    local opts = {}
    for k, p in ipairs(S.patches) do
        if not p.bitter and p.sugar >= 0.08 then
            opts[#opts + 1] = { k = k, sugar = p.sugar * 3 + gauss() * 0.15, crowd = p.occupants,
                dist = sqrt((p.x - f.x[i]) ^ 2 + (p.y - f.y[i]) ^ 2),
                room = 1 - p.brood / max(1e-6, NURSERY_CROWD * larvaRoom(p)) }
        end
    end
    f.path[i] = nil
    if #opts == 0 then
        f.target[i] = -1
        return
    end
    for a = #opts, 2, -1 do -- (so ties don't always break the same way)
        local b = random(a)
        opts[a], opts[b] = opts[b], opts[a]
    end
    f.target[i] = takeTheBest(opts, gravid(i) and NURSERY_CUES or PATCH_CUES).k
end

local function planPath(i)
    local f = S.f
    local p = S.patches[f.target[i]]
    local path
    if not S.grid:straight(f.x[i], f.y[i], p.x, p.y) then path = S.grid:path(f.x[i], f.y[i], p.x, p.y, 1200) end
    if not path or #path == 0 then path = { { p.x, p.y } } end
    f.path[i] = path
    f.pathIdx[i] = 1
end

--------------------------------------------------------------------------------
-- A tick of the original's step: senses -> connectome -> body
--------------------------------------------------------------------------------

-- What's looming this think, by side, and the strongest (out here so that
-- think, run for every fly, makes no closure and stays on trace)
local loomL, loomR, strongest = 0, 0, 0
local function loom(f, i, x, y, h, tx, ty, size)
    if wrap(atan2(ty - y, tx - x) - h) > 0 then
        if size > loomR then loomR = size end
    elseif size > loomL then
        loomL = size
    end
    if size > strongest then
        strongest, f.threatX[i], f.threatY[i] = size, tx, ty
    end
end

-- What fly i senses, and one tick of its brain
local function think(i)
    local f, I, IN, base = S.f, S.pool.I, flywire.IN, i * NI
    local x, y, h, z = f.x[i], f.y[i], f.h[i], f.z[i]
    S.pool.gain[i] = S.params.gain * f.gainG[i]

    local patch = patchAt(x, y)
    local landed = z < LAND
    local sugar = (patch and not patch.bitter and landed) and clamp01(patch.sugar * 1.4) or 0
    local bitter = (patch and patch.bitter and landed) and 1 or 0
    I[base + IN.sugar], I[base + IN.sugar + 1] = sugar, sugar
    I[base + IN.bitter], I[base + IN.bitter + 1] = bitter, bitter

    local hunger = clamp01(1 - f.energy[i] / 8)
    I[base + IN.orn] = 0.15 * hunger * clamp01(odorAt(x + cos(h - 0.6) * 0.8 * U, y + sin(h - 0.6) * 0.8 * U))
    I[base + IN.orn + 1] = 0.15 * hunger * clamp01(odorAt(x + cos(h + 0.6) * 0.8 * U, y + sin(h + 0.6) * 0.8 * U))

    -- what looms, by which side it's on; the strongest is what it flees
    loomL, loomR, strongest = 0, 0, 0
    local b = S.bird
    local dx, dy, dz = b.x - x, b.y - y, b.z - z
    local d = sqrt(dx * dx + dy * dy + dz * dz)
    if d < 22 * U then loom(f, i, x, y, h, b.x, b.y, clamp01(2.5 * U / d) * (b.mode == "dive" and 1.4 or 0.6)) end
    for _, c in ipairs(S.chasers) do
        dx, dy, dz = c.x - x, c.y - y, c.z - z
        d = sqrt(dx * dx + dy * dy + dz * dz)
        if d <= 8 * U then loom(f, i, x, y, h, c.x, c.y, clamp01(1.2 * U / d) * (c.target == f.id[i] and 1.3 or 0.7)) end
    end
    -- you. LPLC2 responds to approach, not size: come slowly and you go unnoticed
    if S.playerX and not (f.role[i] == 1 and f.strike[i] == 1) then
        dx, dy = S.playerX - x, S.playerY - y
        d = sqrt(dx * dx + dy * dy)
        if d < 6 * U then
            local approach = -(S.playerVX * dx + S.playerVY * dy) / (d + 1e-6)
            local size = clamp01(1.5 * U / d) * clamp01(approach / (4 * U))
            if size > 0 then loom(f, i, x, y, h, S.playerX, S.playerY, size) end
        end
    end
    if f.startle[i] > 0 then
        loomL = max(loomL, f.startle[i])
        loomR = max(loomR, f.startle[i])
    end
    I[base + IN.loom], I[base + IN.loom + 1] = clamp01(loomL), clamp01(loomR)

    -- mechanosensation: jostling neighbours; and the social graph's degree
    local nb = S.q1
    local m = query(x, y, S.params.socialRadius, nb)
    local jostling = 0
    local close = (1.2 * U) ^ 2
    for k = 1, m do
        local j = nb[k]
        if (f.x[j] - x) ^ 2 + (f.y[j] - y) ^ 2 <= close then jostling = jostling + 1 end
    end
    f.degree[i] = m - 1
    local crowd = clamp01((jostling - 1) * 0.15)
    I[base + IN.mech], I[base + IN.mech + 1] = crowd * 0.5, crowd * 0.5

    -- the goal's bearing, into PFL3
    local path = f.path[i]
    local bearing, goalDist = 0, math.huge
    if path then
        local w = path[f.pathIdx[i]]
        if w and (w[1] - x) ^ 2 + (w[2] - y) ^ 2 < (2 * U) ^ 2 and f.pathIdx[i] < #path then
            f.pathIdx[i] = f.pathIdx[i] + 1
            w = path[f.pathIdx[i]]
        end
        if w then bearing = wrap(atan2(w[2] - y, w[1] - x) - h) end
        local tp = S.patches[f.target[i]]
        if tp then goalDist = sqrt((tp.x - x) ^ 2 + (tp.y - y) ^ 2) end
    end
    local drive = (path and goalDist > U) and clamp01(abs(bearing) / 1.2) * 0.9 or 0
    I[base + flywire.PFL_RIGHT] = bearing > 0 and drive or 0
    I[base + flywire.PFL_LEFT] = bearing < 0 and drive or 0

    flywire.step(S.pool, i)
end

-- The reflex layer (separation, walls); the brain does the deliberate turning
local function avoidTurn(i, h)
    local f = S.f
    local x, y = f.x[i], f.y[i]
    local look, avoid = 3 * U, 0
    if not freeAt(x + cos(h) * look, y + sin(h) * look) then
        local left = freeAt(x + cos(h - 0.8) * look, y + sin(h - 0.8) * look)
        local right = freeAt(x + cos(h + 0.8) * look, y + sin(h + 0.8) * look)
        avoid = (right and not left) and 0.22 or ((left and not right) and -0.22 or (random() < 0.5 and 0.3 or -0.3))
    end
    local nb = S.q2
    local m = query(x, y, 0.8 * U, nb)
    for k = 1, m do
        local j = nb[k]
        if j ~= i then
            local a = wrap(atan2(f.y[j] - y, f.x[j] - x) - h)
            avoid = avoid - (a > 0 and 0.03 or -0.03)
        end
    end
    for _, p in ipairs(S.patches) do -- (sludge is bitter: they keep off it)
        if p.bitter and (p.x - x) ^ 2 + (p.y - y) ^ 2 < (p.r + 2 * U) ^ 2 and f.z[i] < 2 * U then
            avoid = avoid + wrap(atan2(y - p.y, x - p.x) - h) * 0.15
        end
    end
    return avoid
end

-- A bite, if you're there to be bitten
local function maybeBite(i)
    local f = S.f
    if not S.playerX or f.biteCd[i] > 0 or f.z[i] > BITE_Z then return end
    local dx, dy = S.playerX - f.x[i], S.playerY - f.y[i]
    if dx * dx + dy * dy > BITE_R * BITE_R then return end
    if player.isDodging or player.inCar then return end
    local body = f.role[i] == 1
    if not body and disposition(i) < 0.6 then return end -- only hawks pick a fight
    local dmg = body and BITE_BODY or BITE_WILD
    f.biteCd[i] = body and 1.2 or 5 + random() * 4
    if S.biteBudget >= dmg then
        S.biteBudget = S.biteBudget - dmg
        S.bites = S.bites + dmg
    end
end

local function bodies()
    local f, R, OUT, P = S.f, S.pool.R, flywire.OUT, S.params
    local plans = 0
    local X, Y, Z, H, SP = f.x, f.y, f.z, f.h, f.speed
    for i = 0, S.n - 1 do
        local o = i * NO
        local turn = R[o + OUT.dna02 + 1] + 0.5 * R[o + OUT.dna01 + 1] - R[o + OUT.dna02] - 0.5 * R[o + OUT.dna01]
        local gf = max(R[o + OUT.gf], R[o + OUT.gf + 1])
        local mdn = (R[o + OUT.mdn] + R[o + OUT.mdn + 1]) / 2
        local p9 = (R[o + OUT.p9] + R[o + OUT.p9 + 1]) / 2
        local mn9 = max(R[o + OUT.mn9], R[o + OUT.mn9 + 1])
        f.oa[i] = R[o + OUT.oa]
        local x, y = X[i], Y[i]
        f.px[i], f.py[i], f.pz[i] = x, y, Z[i]

        -- Giant Fiber escape take-off: up and away from what loomed
        if gf > 0.3 and f.escape[i] <= 0 then
            f.escape[i] = 1.4
            H[i] = atan2(y - f.threatY[i], x - f.threatX[i]) + (random() - 0.5) * 0.8
            f.vz[i], SP[i] = 9 * U, 14 * U
            f.path[i], f.target[i] = nil, -1
        end
        f.startle[i] = max(0, f.startle[i] - DT * 2)
        f.biteCd[i] = f.biteCd[i] - DT
        f.flash[i] = max(0, f.flash[i] - DT * 6)

        local inBody = f.role[i] == 1 and f.escape[i] <= 0 and S.formation
        if inBody then
            -- the boss's: straight there, its own neurons shaking the line
            local fx, fy, fz, top = S.formation(f.slot[i], f.strike[i] == 1)
            local dx, dy = fx - x, fy - y
            local d = sqrt(dx * dx + dy * dy) + 1e-6
            H[i] = atan2(dy, dx) + turn * 0.5
            SP[i] = min(d * 8, top)
            x = x + (cos(H[i]) * SP[i] + f.kvx[i]) * DT
            y = y + (sin(H[i]) * SP[i] + f.kvy[i]) * DT
            Z[i] = max(0, Z[i] + (fz - Z[i]) * min(1, 10 * DT))
            f.feeding[i] = 0
        else
            local patch = patchAt(x, y)
            local onFood = patch and not patch.bitter and patch.sugar > 0.02
            local tp = f.target[i] >= 0 and S.patches[f.target[i]] or nil

            -- the heuristic layer: where to go next
            f.decide[i] = f.decide[i] - DT
            if f.decide[i] <= 0 then
                f.decide[i] = 0.8 + random() * 0.6
                local onTarget = tp and patch == tp
                local depleted = tp and tp.sugar < 0.05
                local settled = onTarget and f.residence[i] > 4
                local sated = settled and f.energy[i] > 10
                -- satisficing: leave once intake falls below the aspiration level
                if not tp or depleted or sated
                    or (settled and f.intake[i] < P.aspiration and f.energy[i] > 2) then
                    choosePatch(i)
                    tp = f.target[i] >= 0 and S.patches[f.target[i]] or nil
                end
            end
            if tp and not f.path[i] and plans < PLANS and f.escape[i] <= 0 then
                planPath(i)
                plans = plans + 1
            end

            local avoid = avoidTurn(i, H[i])
            local landed = Z[i] < LAND
            local feeding = (onFood and landed) and mn9 or 0
            f.residence[i] = (patch and patch == tp and landed) and f.residence[i] + DT or 0
            f.feeding[i] = feeding > 0.15 and 1 or 0

            -- torn wings: the wounded are slower
            local base = (5.5 + 5 * p9 - 6 * mdn) * (0.4 + 0.6 * f.hp[i]) * U
            local goalNear = false
            if tp then
                local d = sqrt((tp.x - x) ^ 2 + (tp.y - y) ^ 2)
                goalNear = d < tp.r * 0.9
                if d < tp.r then base = base * (0.25 + 0.75 * (1 - feeding)) end
            end
            if f.escape[i] > 0 then
                f.escape[i] = f.escape[i] - DT
                base = max(base, 12 * U * f.escape[i])
            else
                H[i] = H[i] + (turn * 4.2 + (random() - 0.5) * 1.6) * DT
            end
            H[i] = H[i] + avoid
            SP[i] = SP[i] + (base - SP[i]) * 0.15

            -- altitude: cruise over the floor, land on the target, climb to flee
            local goalZ = 2.2 * U
            if goalNear then goalZ = 0 end
            if f.escape[i] > 0 then goalZ = 8 * U end
            f.vz[i] = f.vz[i] + ((goalZ - Z[i]) * 2.5 * (0.5 + 0.5 * f.hp[i]) - f.vz[i] * 1.5) * DT
            Z[i] = max(0, Z[i] + f.vz[i] * DT)
            if Z[i] == 0 and f.vz[i] < 0 then f.vz[i] = 0 end

            local nx = x + (cos(H[i]) * SP[i] + f.kvx[i]) * DT
            local ny = y + (sin(H[i]) * SP[i] + f.kvy[i]) * DT
            if freeAt(x, y) and not freeAt(nx, ny) then -- (slide along what's in the way)
                if freeAt(nx, y) then
                    ny = y
                elseif freeAt(x, ny) then
                    nx = x
                else
                    nx, ny = x, y
                end
            end
            x, y = nx, ny

            -- energy: feeding through MN9, burning it flying
            local gain = 0
            if feeding > 0 then
                gain = feeding * patch.sugar * 1.6 * DT
                patch.sugar = max(0, patch.sugar - gain * 0.001)
            end
            f.intake[i] = f.intake[i] + (gain / DT - f.intake[i]) * 0.02
            f.energy[i] = min(12, f.energy[i] + gain - (0.08 + 0.008 * SP[i] / U) * P.metabolism * DT)
        end

        local drag = exp(-3 * DT)
        f.kvx[i], f.kvy[i] = f.kvx[i] * drag, f.kvy[i] * drag
        X[i], Y[i] = max(S.x0, min(S.x1, x)), max(S.y0, min(S.y1, y))

        f.cooldown[i] = f.cooldown[i] - DT
        f.layTimer[i] = f.layTimer[i] - DT
        f.hurt[i] = f.hurt[i] + DT
        if f.hp[i] > 0 then f.hp[i] = min(1, f.hp[i] + 0.02 * DT) end
        f.age[i] = f.age[i] + DT
        f.wear[i] = f.wear[i] + DT / (f.life[i] * P.lifespan)
        f.wing[i] = f.wing[i] + (Z[i] > 0.05 * U and 1.6 or 0.15) * (1 + SP[i] / U * 0.05)
        maybeBite(i)
    end
end

--------------------------------------------------------------------------------
-- Game theory
--------------------------------------------------------------------------------

local function contests()
    local f, P = S.f, S.params
    local nb = S.q1
    local matrix = GAMES[P.game](P.V, P.C)
    for i = 0, S.n - 1 do
        if f.cooldown[i] <= 0 and f.z[i] <= LAND and f.role[i] == 0 then
            local patch = patchAt(f.x[i], f.y[i])
            if patch and not patch.bitter and patch.sugar >= 0.05 then
                local m, j = query(f.x[i], f.y[i], 1.5 * U, nb), -1
                for k = 1, m do
                    local q = nb[k]
                    if q ~= i and f.cooldown[q] <= 0 and f.z[q] < LAND and f.role[q] == 0 then
                        j = q
                        break
                    end
                end
                if j >= 0 then
                    local hi, hj = random() < choiceProb(i), random() < choiceProb(j)
                    -- expected payoffs, as in the replicator equation
                    local ri, ci = hi and 1 or 2, hj and 1 or 2
                    local ai, aj = matrix[ri][ci], matrix[ci][ri]
                    f.energy[i] = f.energy[i] + P.payoffEnergy * ai
                    f.energy[j] = f.energy[j] + P.payoffEnergy * aj
                    f.played[i], f.played[j] = f.played[i] + 1, f.played[j] + 1
                    f.payoff[i] = f.payoff[i] + (ai - f.payoff[i]) / min(8, f.played[i])
                    f.payoff[j] = f.payoff[j] + (aj - f.payoff[j]) / min(8, f.played[j])
                    if P.game == "hawkdove" and hi and hj then -- an escalated fight wounds both
                        wound(i, 0.03 * P.C)
                        wound(j, 0.03 * P.C)
                    end
                    patch.sugar = max(0, patch.sugar - (max(0, ai) + max(0, aj)) * 0.002)
                    f.lastHawk[i], f.lastHawk[j] = hi and 1 or 0, hj and 1 or 0
                    -- the loser is jostled, not chased off
                    local loser = ai < aj and i or (aj < ai and j or -1)
                    if loser >= 0 then
                        S.pool.I[loser * NI + flywire.IN.mech] = 1
                        S.pool.I[loser * NI + flywire.IN.mech + 1] = 1
                        f.vz[loser] = 2 * U
                    end
                    f.cooldown[i], f.cooldown[j] = 1.5, 1.5
                end
            end
        end
    end
end

-- Social learning along the proximity graph: copy a neighbour's disposition
-- with the Fermi probability (Traulsen, Nowak & Pacheco 2006)
local function imitate()
    local f, P = S.f, S.params
    if S.n == 0 then return end
    local expected = S.n * DT / 8
    local tries = floor(expected) + (random() < expected % 1 and 1 or 0)
    local nb = S.q2
    for _ = 1, tries do
        local i = random(0, S.n - 1)
        if f.played[i] >= 2 then
            local m = query(f.x[i], f.y[i], P.socialRadius, nb)
            if m > 1 then
                local j = nb[random(m)]
                if j ~= i and f.played[j] >= 2 then
                    local copy = 1 / (1 + exp(-P.selection * (f.payoff[j] - f.payoff[i])))
                    if random() < copy then f.hawk[i] = f.hawk[j] + gauss() * P.mutation * 0.2 end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Predators
--------------------------------------------------------------------------------

local function updateBird()
    local p, f = S.bird, S.f
    p.timer = p.timer - DT
    if p.mode == "patrol" then
        local a = S.t * 0.25
        local tx, ty = S.lairX + cos(a) * 45 * U * 0.8, S.lairY + sin(a * 1.3) * 30 * U
        p.vx = p.vx + (tx - p.x) * 0.01
        p.vy = p.vy + (ty - p.y) * 0.01
        p.vz = p.vz + (24 * U - p.z) * 0.02
        local biggest = S.swarms.biggest
        if p.timer <= 0 and biggest then -- Hamilton's selfish herd: the largest swarm's the target
            p.mode, p.timer, p.tx, p.ty = "dive", 3.5, biggest.x, biggest.y
        end
    else
        p.vx = p.vx + (p.tx - p.x) * 0.04
        p.vy = p.vy + (p.ty - p.y) * 0.04
        p.vz = p.vz + (0.8 * U - p.z) * 0.05
        if p.timer <= 0 then
            p.mode, p.timer = "patrol", 10.5 * (0.7 + 0.6 * random())
        end
        for i = 0, S.n - 1 do
            if f.hp[i] > 0 then
                local dx, dy, dz = f.x[i] - p.x, f.y[i] - p.y, f.z[i] - p.z
                local d = sqrt(dx * dx + dy * dy + dz * dz)
                if d < 1.8 * U then
                    wound(i, 1)
                elseif d < 4 * U and f.hurt[i] > 1 then
                    wound(i, 0.3 + 0.45 * (1 - d / (4 * U)))
                    local a, s = atan2(dy, dx), 12 * U * (1 - d / (4 * U))
                    push(i, cos(a) * s + p.vx * 3, -3 * U, sin(a) * s + p.vy * 3)
                end
            end
        end
    end
    p.vx, p.vy, p.vz = p.vx * 0.94, p.vy * 0.94, p.vz * 0.94
    p.x, p.y, p.z = p.x + p.vx * DT * 6, p.y + p.vy * DT * 6, p.z + p.vz * DT * 6
end

-- Dragonflies intercept single flies, favouring slow, wounded, isolated ones
local function updateChasers()
    local f = S.f
    for _, c in ipairs(S.chasers) do
        c.retarget, c.bite = c.retarget - DT, c.bite - DT
        local i = c.target and S.slotOf(c.target)
        if not i or c.retarget <= 0 then
            local best, score = nil, math.huge
            for k = 0, S.n - 1 do
                local d = sqrt((f.x[k] - c.x) ^ 2 + (f.y[k] - c.y) ^ 2)
                local v = d * (0.35 + 0.65 * f.hp[k]) * (1 + 0.15 * min(6, f.degree[k]))
                if v < score then best, score = k, v end
            end
            i = best
            c.target = i and f.id[i] or nil
            c.retarget = 3 + random() * 2
        end
        local ax, ay, az = 0, 0, (5 * U - c.z) * 0.5
        if i and c.bite <= 0 then
            local tx = f.x[i] + cos(f.h[i]) * f.speed[i] * 0.25
            local ty = f.y[i] + sin(f.h[i]) * f.speed[i] * 0.25
            local dx, dy, dz = tx - c.x, ty - c.y, f.z[i] + 0.2 * U - c.z
            local d = sqrt(dx * dx + dy * dy + dz * dz) + 1e-6
            ax, ay, az = dx / d * 60 * U, dy / d * 60 * U, dz / d * 60 * U
            if (f.x[i] - c.x) ^ 2 + (f.y[i] - c.y) ^ 2 + (f.z[i] - c.z) ^ 2 < (1.1 * U) ^ 2 then
                c.bite = 0.8 -- handling time, then the chase resumes
                push(i, c.vx * 0.3, -2 * U, c.vy * 0.3)
                if wound(i, 0.75) then c.target = nil end
            end
        end
        c.vx, c.vy, c.vz = c.vx + ax * DT, c.vy + ay * DT, c.vz + az * DT
        local sp, top = sqrt(c.vx * c.vx + c.vy * c.vy + c.vz * c.vz), 13.5 * U
        if sp > top then c.vx, c.vy, c.vz = c.vx * top / sp, c.vy * top / sp, c.vz * top / sp end
        c.h = atan2(c.vy, c.vx)
        c.x = max(S.x0, min(S.x1, c.x + c.vx * DT))
        c.y = max(S.y0, min(S.y1, c.y + c.vy * DT))
        c.z = max(0.3 * U, c.z + c.vz * DT)
    end
end

--------------------------------------------------------------------------------
-- Life cycle
--------------------------------------------------------------------------------

local function breed()
    local f, P = S.f, S.params
    local nb = S.q1
    local clutch = max(1, P.clutch)
    for i = 0, S.n - 1 do
        if f.sex[i] == 0 and f.age[i] >= MATURE_AGE and f.z[i] <= LAND and f.hp[i] > 0 and f.role[i] == 0 then
            if (f.mated[i] == 0 or random() < 0.05) and (i + S.tick) % 4 == 0 then
                local m = query(f.x[i], f.y[i], 1.5 * U, nb)
                for k = 1, m do
                    local j = nb[k]
                    if f.sex[j] == 1 and f.age[j] >= MATURE_AGE and f.z[j] <= LAND then
                        f.mated[i], f.mateHawk[i], f.mateGain[i] = 1, f.hawk[j], f.gainG[j]
                        break
                    end
                end
            end
            if gravid(i) and f.layTimer[i] <= 0 then
                local p = patchAt(f.x[i], f.y[i])
                if p and not p.bitter and p.sugar >= 0.05 then
                    if p.brood > NURSERY_CROWD * larvaRoom(p) then
                        -- not where larvae already crowd it: look for another nursery
                        if S.patches[f.target[i]] == p then
                            f.target[i], f.path[i], f.decide[i] = -1, nil, 0
                        end
                        f.layTimer[i] = 2
                    else
                        local eggs = min(clutch, floor((f.energy[i] - LAY_RESERVE) / EGG_COST), BROOD_CAP - #S.brood)
                        for _ = 1, eggs do
                            local ex, ey = f.x[i] + gauss() * 0.5 * U, f.y[i] + gauss() * 0.5 * U
                            local dx, dy = ex - p.x, ey - p.y
                            local d, lim = sqrt(dx * dx + dy * dy), p.r * 0.9
                            if d > lim then ex, ey = p.x + dx / d * lim, p.y + dy / d * lim end
                            -- offspring blend both parents' genes, plus mutation
                            S.brood[#S.brood + 1] = { x = ex, y = ey, age = 0, fed = 0, vigor = 0.6 + 0.8 * random(),
                                gen = f.generation[i] + 1,
                                hawk = (f.hawk[i] + f.mateHawk[i]) / 2 + gauss() * P.mutation * 0.6,
                                gain = min(1.4, max(0.7, (f.gainG[i] + f.mateGain[i]) / 2 + gauss() * P.mutation * 0.1)) }
                        end
                        f.energy[i] = f.energy[i] - EGG_COST * max(0, eggs)
                        f.layTimer[i] = LAY_GAP
                    end
                end
            end
        end
    end
end

local function bigger(a, b)
    return a.fed + 0.2 * a.vigor > b.fed + 0.2 * b.vigor
end

-- Larvae compete for the food they sit on, the biggest first; pupae wait; adults eclose
local function updateBrood()
    local P = S.params
    local D = max(1, P.develop)
    local eat = DT / ((LARVA_END - EGG_END) * D * 0.7)
    local groups = {}
    for _, p in ipairs(S.patches) do p.brood = 0 end
    for _, b in ipairs(S.brood) do
        local st = broodStage(b)
        local p = st < 2 and patchAt(b.x, b.y) or nil
        if p then
            p.brood = p.brood + 1
            if st == 1 then
                groups[p] = groups[p] or {}
                table.insert(groups[p], b)
            end
        end
    end
    for p, g in pairs(groups) do
        if not p.bitter then
            local food = p.sugar > 0.03 and larvaRoom(p) * eat or 0
            table.sort(g, bigger)
            for _, b in ipairs(g) do
                local bite = min(eat * b.vigor, 1 - b.fed, food)
                if bite > 0 then
                    b.fed = b.fed + bite
                    food = food - bite
                    p.sugar = max(0, p.sugar - bite * LARVA_FOOD)
                end
            end
        end
    end
    local w = 0
    local list = S.brood
    for r = 1, #list do
        local b = list[r]
        local was = broodStage(b)
        b.age = b.age + DT
        local st = broodStage(b)
        local keep = true
        if st == 2 and was == 1 and b.fed < PUPATE_FED then
            keep = false -- starved as a larva
        elseif b.age >= D then
            if S.n < CAP and not S.winding then
                spawn(S.n, b)
                S.n = S.n + 1
                keep = false
            elseif b.age > D * 1.3 then
                keep = false
            end
        end
        if keep then
            w = w + 1
            list[w] = b
        end
    end
    for r = #list, w + 1, -1 do list[r] = nil end
end

local function lifeCycle()
    breed()
    local f = S.f
    local dead = {}
    for i = 0, S.n - 1 do
        if f.energy[i] <= 0 or f.hp[i] <= 0 or f.wear[i] >= 1 then
            -- the body drops where it died, with the momentum it died with
            local corpses = S.corpses
            if #corpses >= CORPSE_CAP then table.remove(corpses, 1) end
            corpses[#corpses + 1] = { x = f.x[i], y = f.y[i], z = f.z[i], vz = f.vz[i], h = f.h[i], age = 0,
                vx = cos(f.h[i]) * f.speed[i] + f.kvx[i], vy = sin(f.h[i]) * f.speed[i] + f.kvy[i],
                splat = random(4) }
            dead[#dead + 1] = i
        end
    end
    -- the last living fly takes each free slot, highest first so arrays stay dense
    for k = #dead, 1, -1 do
        local d, last = dead[k], S.n - 1
        if d ~= last then moveFly(last, d) end
        S.n = S.n - 1
    end
    updateBrood()
    if #dead > 0 then hashBuild() end
end

local function updateCorpses()
    local drag = exp(-1.2 * DT)
    local g = 20 * U
    local list, w = S.corpses, 0
    for r = 1, #list do
        local c = list[r]
        c.age = c.age + DT
        c.vz = (c.vz - g * DT) * drag
        c.vx, c.vy = c.vx * drag, c.vy * drag
        c.x, c.y, c.z = c.x + c.vx * DT, c.y + c.vy * DT, c.z + c.vz * DT
        if c.z <= 0 then
            c.z = 0
            c.vz = c.vz < -3 * U and -c.vz * 0.2 or 0
            local k = max(0, 1 - 0.5 * g * DT / (sqrt(c.vx * c.vx + c.vy * c.vy) + 1e-3))
            c.vx, c.vy = c.vx * k, c.vy * k
        end
        if c.age < CORPSE_LIFE then
            w = w + 1
            list[w] = c
        end
    end
    for r = #list, w + 1, -1 do list[r] = nil end
end

local function updatePatches()
    if S.winding then return end
    local f = S.f
    for k, p in ipairs(S.patches) do
        p.age = p.age + DT
        if not p.bitter then
            p.sugar = min(1, p.sugar + 0.02 * S.params.food * DT)
            if p.sugar < 0.03 and p.age > 20 / max(0.05, S.params.food) then
                -- exhausted heaps turn up somewhere else
                S.patches[k] = newPatch(false, k <= 3)
                for i = 0, S.n - 1 do
                    if f.target[i] == k then f.target[i], f.path[i] = -1, nil end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Clustering
--------------------------------------------------------------------------------

-- DBSCAN (Ester, Kriegel, Sander & Xu 1996)
local function swarmClusters()
    local f, n = S.f, S.n
    local L, X, Y = f.label, f.x, f.y
    local eps, minPts = S.params.dbEps, S.params.dbMin
    local nb, nb2 = S.q1, S.q2
    for i = 0, n - 1 do L[i] = -2 end
    local count = 0
    for i = 0, n - 1 do
        if L[i] == -2 then
            local m = query(X[i], Y[i], eps, nb)
            if m < minPts then
                L[i] = -1
            else
                local c = count
                count = count + 1
                L[i] = c
                local seeds = {}
                for s = 1, m do seeds[s] = nb[s] end
                local s = 1
                while s <= #seeds do
                    local j = seeds[s]
                    s = s + 1
                    if L[j] == -1 then L[j] = c end
                    if L[j] == -2 then
                        L[j] = c
                        local m2 = query(X[j], Y[j], eps, nb2)
                        if m2 >= minPts then
                            for t = 1, m2 do
                                if L[nb2[t]] < 0 then seeds[#seeds + 1] = nb2[t] end
                            end
                        end
                    end
                end
            end
        end
    end
    local sizes, cx, cy = {}, {}, {}
    for i = 0, n - 1 do
        local c = L[i]
        if c >= 0 then
            sizes[c] = (sizes[c] or 0) + 1
            cx[c], cy[c] = (cx[c] or 0) + X[i], (cy[c] or 0) + Y[i]
        end
    end
    local biggest
    for c = 0, count - 1 do
        if sizes[c] and (not biggest or sizes[c] > biggest.size) then
            biggest = { size = sizes[c], x = cx[c] / sizes[c], y = cy[c] / sizes[c] }
        end
    end
    S.swarms = { count = count, biggest = biggest }
end

local function dist2(a, b)
    local s = 0
    for k = 1, 4 do s = s + (a[k] - b[k]) ^ 2 end
    return s
end

-- k-means++ seeding (warm-started once it has centroids) and Lloyd iterations
local function kmeans(data, k)
    local n = #data
    local C = S.centroids
    if not C then
        C = { { unpack(data[random(n)]) } }
        while #C < k do
            local D, sum = {}, 0
            for i = 1, n do
                local best = math.huge
                for _, c in ipairs(C) do best = min(best, dist2(data[i], c)) end
                D[i], sum = best, sum + best
            end
            local r, pick = random() * sum, 1
            while pick < n and r > D[pick] do
                r = r - D[pick]
                pick = pick + 1
            end
            C[#C + 1] = { unpack(data[pick]) }
        end
    end
    local labels = {}
    for _ = 1, 12 do
        local sums, cnt = {}, {}
        for c = 1, k do sums[c], cnt[c] = { 0, 0, 0, 0 }, 0 end
        for i = 1, n do
            local best, bd = 1, math.huge
            for c = 1, k do
                local d = dist2(data[i], C[c])
                if d < bd then best, bd = c, d end
            end
            labels[i] = best
            cnt[best] = cnt[best] + 1
            local row, into = data[i], sums[best]
            for d = 1, 4 do into[d] = into[d] + row[d] end
        end
        for c = 1, k do
            if cnt[c] > 0 then
                for d = 1, 4 do C[c][d] = sums[c][d] / cnt[c] end
            end
        end
    end
    S.centroids = C
    return labels, C
end

-- Behavioural modes from each fly's motor and neuromodulatory activity
-- (1 foraging, 2 feeding, 3 escaping, 4 aroused). What senses drive stands in
-- for the sensory neurons' own rates, which a fly's reduced sweep doesn't read.
local function behaviourModes()
    local n = S.n
    if n < S.params.k then return end
    local f, R, I, OUT, IN = S.f, S.pool.R, S.pool.I, flywire.OUT, flywire.IN
    local data, mu, sd = {}, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
    for i = 0, n - 1 do
        local o, b = i * NO, i * NI
        local function mean(arr, at, slot) return (arr[at + slot] + arr[at + slot + 1]) / 2 end
        data[i + 1] = {
            abs(R[o + OUT.dna02 + 1] - R[o + OUT.dna02]) + mean(I, b, IN.orn),
            mean(R, o, OUT.mn9) + mean(I, b, IN.sugar),
            max(R[o + OUT.gf], R[o + OUT.gf + 1]) + mean(I, b, IN.loom) + (f.escape[i] > 0 and 0.5 or 0),
            f.oa[i] + mean(R, o, OUT.mdn) + mean(I, b, IN.mech),
        }
    end
    for _, row in ipairs(data) do
        for d = 1, 4 do mu[d] = mu[d] + row[d] / n end
    end
    for _, row in ipairs(data) do
        for d = 1, 4 do sd[d] = sd[d] + (row[d] - mu[d]) ^ 2 / n end
    end
    for d = 1, 4 do sd[d] = sqrt(sd[d]) + 0.05 end
    for _, row in ipairs(data) do
        for d = 1, 4 do row[d] = (row[d] - mu[d]) / sd[d] end
    end
    local labels, C = kmeans(data, S.params.k)
    local names = {}
    for c = 1, S.params.k do
        local best = 1
        for d = 2, 4 do
            if C[c][d] > C[c][best] then best = d end
        end
        names[c] = C[c][best] < 0.5 and 1 or best
    end
    local counts = { 0, 0, 0, 0 }
    for i = 1, n do
        local mode = names[labels[i]]
        f.mode[i - 1] = mode
        counts[mode] = counts[mode] + 1
    end
    S.modeCounts = counts
end

--------------------------------------------------------------------------------
-- The step
--------------------------------------------------------------------------------

local function step()
    S.t, S.tick = S.t + DT, S.tick + 1
    hashBuild()
    local f = S.f
    for _, p in ipairs(S.patches) do p.occupants = 0 end
    for i = 0, S.n - 1 do
        if f.z[i] < LAND then
            local p = patchAt(f.x[i], f.y[i])
            if p then p.occupants = p.occupants + 1 end
        end
    end

    -- the brains, as many as there's time for, in turn (15 Hz each with a JIT)
    local want = min(BRAINS, max(1, floor((S.n + 1) / 2)))
    for _ = 1, S.n > 0 and want or 0 do
        S.brainAt = S.brainAt % S.n
        think(S.brainAt)
        S.brainAt = S.brainAt + 1
    end

    bodies()
    contests()
    imitate()
    updateBird()
    updateChasers()
    lifeCycle()
    updateCorpses()
    updatePatches()
    if S.tick % 10 == 0 then swarmClusters() end
    if S.tick % 30 == 0 then behaviourModes() end

    S.biteBudget = min(S.biteCap * 0.4, S.biteBudget + S.biteCap * DT)
    if S.bites >= 8 and player and player.body then
        player.hurt(S.bites, nil, "bite")
        S.bites = 0
    end
    if S.winding and S.n == 0 and #S.corpses == 0 then S = nil end
end

--------------------------------------------------------------------------------
-- How your weapons reach them (host and single player)
--------------------------------------------------------------------------------

--- Whether there's a swarm where the world runs
function swarm.active()
    return S ~= nil and not S.client
end

local function kick(i, dirx, diry, force)
    S.f.kvx[i] = S.f.kvx[i] + dirx * force
    S.f.kvy[i] = S.f.kvy[i] + diry * force
end

--- A shot from (x0, y0) to (x1, y1), `radius` wide: flies it passes (as drawn)
--- die, at most `maxHits`. How many it killed.
function swarm.sweep(x0, y0, x1, y1, radius, maxHits)
    if not swarm.active() then return 0 end
    local f = S.f
    local dx, dy = x1 - x0, y1 - y0
    local len2 = dx * dx + dy * dy
    if len2 < 1e-6 then return 0 end
    local len = sqrt(len2)
    local lo_x, hi_x = min(x0, x1) - radius, max(x0, x1) + radius
    local lo_y, hi_y = min(y0, y1) - radius, max(y0, y1) + radius
    local hits = 0
    for i = 0, S.n - 1 do
        local fx, fy = f.x[i], f.y[i] - f.z[i]
        if fx >= lo_x and fx <= hi_x and fy >= lo_y and fy <= hi_y and f.hp[i] > 0 then
            local t = clamp01(((fx - x0) * dx + (fy - y0) * dy) / len2)
            local ex, ey = x0 + dx * t - fx, y0 + dy * t - fy
            if ex * ex + ey * ey <= radius * radius then
                wound(i, 1)
                kick(i, dx / len, dy / len, 14 * U)
                hits = hits + 1
                if hits >= maxHits then return hits end
            end
        end
    end
    return hits
end

--- A blast at (x, y): flies and brood in `radius` caught, heaps torn up, the
--- rest startled
function swarm.blast(x, y, radius, damage)
    if not swarm.active() then return end
    local f = S.f
    for i = 0, S.n - 1 do
        local dx, dy = f.x[i] - x, f.y[i] - y
        local d = sqrt(dx * dx + dy * dy) + 1e-6
        if d < radius then
            local k = 1 - d / radius
            wound(i, max(0.4, damage * k * k / 15))
            kick(i, dx / d, dy / d, 30 * U * k)
            f.startle[i], f.threatX[i], f.threatY[i] = 1, x, y
        elseif d < radius * 2.2 then
            f.startle[i], f.threatX[i], f.threatY[i] = max(f.startle[i], 0.8), x, y
        end
    end
    local r2 = radius * radius
    local list, w = S.brood, 0
    for r = 1, #list do
        local b = list[r]
        if (b.x - x) ^ 2 + (b.y - y) ^ 2 >= r2 then
            w = w + 1
            list[w] = b
        end
    end
    for r = #list, w + 1, -1 do list[r] = nil end
    for _, p in ipairs(S.patches) do
        if not p.bitter and (p.x - x) ^ 2 + (p.y - y) ^ 2 < (p.r + radius) ^ 2 then p.sugar = p.sugar * 0.55 end
    end
end

--- Burning for `dt` within `radius` of (x, y)
function swarm.scorch(x, y, radius, dt)
    if not swarm.active() then return end
    local f = S.f
    for i = 0, S.n - 1 do
        local dx, dy = f.x[i] - x, f.y[i] - f.z[i] - y
        if dx * dx + dy * dy < radius * radius then wound(i, 5 * dt) end
    end
end

--- The tesla coil, from (x, y) along (ax, ay): the nearest flies in its cone
--- for `dt`
function swarm.zap(x, y, ax, ay, range, cosLimit, dt)
    if not swarm.active() then return end
    local f = S.f
    local alen = sqrt(ax * ax + ay * ay) + 1e-6
    local found, r2 = {}, range * range
    for i = 0, S.n - 1 do
        local dx, dy = f.x[i] - x, f.y[i] - f.z[i] - y
        local d2 = dx * dx + dy * dy
        if d2 < r2 and (dx * ax + dy * ay) / (sqrt(d2) * alen + 1e-6) >= cosLimit then
            found[#found + 1] = { i, d2 }
        end
    end
    table.sort(found, function(a, b) return a[2] < b[2] end)
    for k = 1, min(14, #found) do wound(found[k][1], 9 * dt) end
end

--- A small black hole at (x, y): what's inside `radius` is swallowed, what's near drawn in
function swarm.drain(x, y, radius, dt)
    if not swarm.active() then return end
    local f = S.f
    for i = 0, S.n - 1 do
        local dx, dy = x - f.x[i], y - f.y[i]
        local d = sqrt(dx * dx + dy * dy) + 1e-6
        if d < radius then
            wound(i, 1)
        elseif d < radius * 4 then
            kick(i, dx / d, dy / d, 70 * U * dt)
        end
    end
end

-- Bullets through the swarm (the world doesn't know the flies are there)
local function shotsThrough()
    for _, inst in ipairs(bullet.instances) do
        if not inst.hostile and not inst.spent and inst.body and not inst.body:isDestroyed() then
            local x, y = inst.body:getPosition()
            local ox, oy = inst.swarmX, inst.swarmY
            if inst.swarmBirth ~= inst.birthTime then
                inst.swarmBirth, inst.swarmHits = inst.birthTime, 0
                ox, oy = inst.startPos.x, inst.startPos.y
            end
            inst.swarmX, inst.swarmY = x, y
            if inst.swarmHits < 3 then
                inst.swarmHits = inst.swarmHits + swarm.sweep(ox, oy, x, y, 7, 3 - inst.swarmHits)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- What the boss asks of it
--------------------------------------------------------------------------------

--- Start a swarm in region r, with its boss's lair at (lx, ly)
function swarm.begin(r, lx, ly)
    flywire.ensure()
    swarm.ensureArt()
    local rw, rh = r.ox and regions.W or 1800, r.ox and regions.H or 1400
    local ox, oy = r.ox or lx - rw / 2, r.oy or ly - rh / 2
    S = {
        region = r, lairX = lx, lairY = ly, ox = ox, oy = oy, w = rw, h = rh, x0 = ox, y0 = oy,
        x1 = ox + rw, y1 = oy + rh,
        params = { game = "hawkdove", V = 2, C = 5, mutation = 0.25, selection = 2, payoffEnergy = 0.3, lifespan = 120,
            clutch = 3, develop = 24, metabolism = 1, food = 1, gain = 9, aspiration = 0.12, socialRadius = 3.5 * U,
            dbEps = 3.5 * U, dbMin = 4, k = 4 },
        rng = love.math.newRandomGenerator((r.seed or 783) + 783),
        t = 0, tick = 0, acc = 0, lerp = 1, n = 0, nextId = 0, brainAt = 0, bites = 0, biteBudget = 0, biteCap = 18,
        patches = {}, brood = {}, corpses = {}, chasers = {}, swarms = { count = 0 }, modeCounts = { 0, 0, 0, 0 },
        grid = nav.new(24, 6), f = { path = {} }, q1 = {}, q2 = {},
        cell = 3.5 * U,
    }
    for _, name in ipairs(FLOATS) do S.f[name] = flywire.floats(CAP) end
    for _, name in ipairs(INTS) do S.f[name] = flywire.ints(CAP) end
    S.pool = flywire.pool(CAP)
    S.cols, S.rows = math.ceil(rw / S.cell) + 2, math.ceil(rh / S.cell) + 2
    S.head, S.nxt = flywire.ints(S.cols * S.rows), flywire.ints(CAP)
    function S.slotOf(id)
        local f = S.f
        for i = 0, S.n - 1 do
            if f.id[i] == id then return i end
        end
    end

    -- the first three heaps round the lair, the rest about the place, as the
    -- original's nine of sugar and three bitter
    for i = 1, 3 do S.patches[i] = newPatch(false, true) end
    for i = 4, 9 do S.patches[i] = newPatch(false, false) end
    for i = 10, 12 do S.patches[i] = newPatch(true, false) end
    S.bird = { x = lx, y = ly, z = 24 * U, vx = 0, vy = 0, vz = 0, mode = "patrol", timer = 10, tx = 0, ty = 0,
        wing = 0 }
    for k = 1, 2 do
        local a = k * 2.4
        S.chasers[k] = { x = lx + cos(a) * 500, y = ly + sin(a) * 400, z = 6 * U, vx = 0, vy = 0, vz = 0, retarget = 0,
            bite = 0, h = 0, wing = 0 }
    end
    for i = 0, START_FLIES - 1 do spawn(i, nil) end
    S.n = START_FLIES
    for _ = 1, START_FLIES * 0.25 do seedBrood() end
end

--- No more swarm, at once
function swarm.stop()
    S = nil
    if swarm.buzz then swarm.buzz:stop() end
end

--- The brain's gone: every fly drops dead where it is, the brood with them
function swarm.dieOff()
    if not S then return end
    S.winding, S.formation = true, nil
    for i = 0, S.n - 1 do wound(i, 1) end
    S.brood = {}
    for _, p in ipairs(S.patches) do p.sugar = 0 end
end

function swarm.setFormation(fn)
    if S then S.formation = fn end
end

function swarm.setBiteCap(cap)
    if S then S.biteCap = cap end
end

function swarm.setGame(game, V, C)
    if S then S.params.game, S.params.V, S.params.C = game, V, C end
end

--- Flies within `radius` of (x, y) join the boss's body, up to `want` of them
function swarm.conscript(x, y, radius, want)
    if not S then return end
    local f, r2 = S.f, radius * radius
    for i = 0, S.n - 1 do
        if want <= 0 then break end
        if f.role[i] == 0 and (f.x[i] - x) ^ 2 + (f.y[i] - y) ^ 2 < r2 then
            f.role[i] = 1
            want = want - 1
        end
    end
end

--- Everyone in the region answers the boss's call
function swarm.callAll(want)
    swarm.conscript(S and S.lairX or 0, S and S.lairY or 0, 1e6, want)
end

function swarm.releaseAll()
    if not S then return end
    local f = S.f
    for i = 0, S.n - 1 do
        f.role[i], f.strike[i] = 0, 0
    end
end

--- Each of the body picks its strategy (Hawk, Hare, Defect: it strikes)
function swarm.assignStrike()
    if not S then return end
    local f = S.f
    for i = 0, S.n - 1 do
        f.strike[i] = (f.role[i] == 1 and random() < choiceProb(i)) and 1 or 0
    end
end

--- Scare the flies near (x, y): they take off
function swarm.startle(x, y, radius)
    if not S then return end
    local f, r2 = S.f, radius * radius
    for i = 0, S.n - 1 do
        if (f.x[i] - x) ^ 2 + (f.y[i] - y) ^ 2 < r2 then
            f.startle[i], f.threatX[i], f.threatY[i] = 1, x, y
        end
    end
end

--- Adults, brood
function swarm.population()
    if not S then return 0, 0 end
    if S.client then return S.netN or S.n, 0 end
    return S.n, #S.brood
end

--- How many of the boss's body there are, and how many within `radius` of (x, y)
function swarm.bodyCount(x, y, radius)
    if not S then return 0, 0 end
    local f, r2, all, near = S.f, radius * radius, 0, 0
    for i = 0, S.n - 1 do
        if f.role[i] == 1 then
            all = all + 1
            if (f.x[i] - x) ^ 2 + (f.y[i] - y) ^ 2 < r2 then near = near + 1 end
        end
    end
    return all, near
end

--- The share of behavioural mode `k` among the adults (1 foraging .. 4 aroused)
function swarm.modeShare(k)
    if not S or S.n == 0 then return 0 end
    return S.modeCounts[k] / S.n
end

--- The heap nearest (x, y) with something on it, by take-the-best's own rule
--- (the richest, unless they're too close to call, then the closest); or nil
function swarm.bestHeap(x, y, reach)
    if not S then return nil end
    local opts = {}
    for _, p in ipairs(S.patches) do
        local d = sqrt((p.x - x) ^ 2 + (p.y - y) ^ 2)
        if not p.bitter and p.sugar >= 0.08 and d < reach then
            opts[#opts + 1] = { p = p, sugar = p.sugar * 3, crowd = 0, dist = d }
        end
    end
    if #opts == 0 then return nil end
    return takeTheBest(opts, PATCH_CUES).p
end

--- What's under (x, y) if it's food
function swarm.heapAt(x, y)
    if not S then return nil end
    local p = patchAt(x, y)
    return (p and not p.bitter) and p or nil
end

--------------------------------------------------------------------------------
-- Each frame
--------------------------------------------------------------------------------

function swarm.update(dt)
    if not S then return end
    if S.client then return end
    if player and player.body then
        S.playerX, S.playerY = player.body:getPosition()
        S.playerVX, S.playerVY = player.body:getLinearVelocity()
    else
        S.playerX = nil
    end
    shotsThrough()
    S.acc = min(S.acc + dt, DT * 4)
    while S and S.acc >= DT do
        S.acc = S.acc - DT
        step()
    end
    if not S then
        if swarm.buzz then swarm.buzz:stop() end
        return
    end
    S.lerp = S.acc / DT
    swarm.updateBuzz()
end

--------------------------------------------------------------------------------
-- Network
--------------------------------------------------------------------------------

local NET_FLIES = 110

--- Host: the flies nearest the middle of things and the heaps, rounded
function swarm.getNetworkData()
    if not S or S.client then return nil end
    local f = S.f
    local list = {}
    local step_ = max(1, floor(S.n / NET_FLIES))
    for i = 0, S.n - 1, step_ do
        list[#list + 1] = floor(f.x[i])
        list[#list + 1] = floor(f.y[i])
        list[#list + 1] = floor(f.z[i])
        list[#list + 1] = (disposition(i) >= 0.5 and 1 or 0) + (f.role[i] == 1 and 2 or 0)
            + floor(f.h[i] % TAU / TAU * 8) * 4
    end
    local heaps = {}
    for _, p in ipairs(S.patches) do
        heaps[#heaps + 1] = floor(p.x)
        heaps[#heaps + 1] = floor(p.y)
        heaps[#heaps + 1] = floor(p.r)
        heaps[#heaps + 1] = p.bitter and -1 or floor(p.sugar * 100)
    end
    return { f = list, p = heaps, n = S.n }
end

--- Client: draw what the host sent (nil: no swarm)
function swarm.applyNetworkData(d)
    if not d then
        if S and S.client then swarm.stop() end
        return
    end
    swarm.ensureArt()
    if not S then
        S = { client = true, f = {}, patches = {}, brood = {}, corpses = {}, chasers = {}, lerp = 1, n = 0 }
        for _, name in ipairs(FLOATS) do S.f[name] = flywire.floats(NET_FLIES + 1) end
    end
    local f = S.f
    local n = min(NET_FLIES, floor(#d.f / 4))
    S.netN = d.n or n
    for i = 0, n - 1 do
        f.x[i], f.y[i], f.z[i] = d.f[i * 4 + 1], d.f[i * 4 + 2], d.f[i * 4 + 3]
        f.px[i], f.py[i], f.pz[i] = f.x[i], f.y[i], f.z[i]
        local flags = d.f[i * 4 + 4]
        f.hawk[i] = flags % 2 == 1 and 1 or -1
        f.h[i] = floor(flags / 4) / 8 * TAU
        f.hp[i], f.wing[i], f.age[i], f.flash[i] = 1, love.timer.getTime() * 40 + i, 60, 0
    end
    S.n = n
    S.patches = {}
    for k = 1, #d.p, 4 do
        local c = d.p[k + 3]
        S.patches[#S.patches + 1] = { x = d.p[k], y = d.p[k + 1], r = d.p[k + 2], bitter = c < 0,
            sugar = c < 0 and 0 or c / 100, pieces = {} }
    end
end

--------------------------------------------------------------------------------
-- Art, baked once
--------------------------------------------------------------------------------

local art
local flyQuads, broodQuads, cornerQuads, fruitQuads
local shader
local CELL = 9
local GROUND_ALPHA = 0.4

local SWARM_SHADER = [[
    #define MAX_LIGHTS 64
    uniform int   numLights;
    uniform vec4  lights[MAX_LIGHTS];
    uniform float u_ambient;
    uniform float groundAlpha;
    uniform float daylight;

    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec4 texel = Texel(tex, tc);
        if (texel.a < 0.5) discard;
        float ambient = (u_ambient > 0.0) ? u_ambient : 0.20;
        float totalLight = 0.0;
        float beam = -1.0;
        for (int i = 0; i < MAX_LIGHTS; i++) {
            if (i >= numLights) break;
            float range = lightRange(lights[i]);
            if (range <= 0.0) continue;
            float dist = length(lights[i].xy - sc);
            if (dist >= range) continue;
            float att = 1.0 - dist / range;
            totalLight += att * att * lights[i].z * reaches(i, lights[i], range, sc, beam);
        }
        float lit = min(1.0, ambient + totalLight);
        vec3 rgb = texel.rgb;
        float glowing = 0.0;
        if (texel.r > 0.9 && texel.g < 0.25) glowing = 1.0;        // an eye
        else if (texel.b < 0.6) rgb *= color.rgb;                  // the body takes its tint
        rgb = glowing > 0.5 ? rgb : rgb * lit;
        rgb = mix(rgb, vec3(1.0), 1.0 - color.a);                  // a hit flashes it
        return vec4(rgb * groundAlpha / mix(groundAlpha, 1.0, daylight), groundAlpha);
    }
]]

local function bake(w, h, fn)
    local data = love.image.newImageData(w, h)
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local c = fn(x, y)
            if c then data:setPixel(x, y, c[1], c[2], c[3], c[4] or 1) end
        end
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    return image
end

local BODY = { 0.45, 0.42, 0.40 }
local THORAX = { 0.56, 0.52, 0.46 }
local EYE = { 1, 0.13, 0.1 }
local WING = { 0.78, 0.86, 0.96 }
local BELLY = { 0.62, 0.58, 0.5 }
local LEG = { 0.2, 0.18, 0.17 }

-- A fly in its 9 x 9 cell at column `dir` (of 8), frame 0 / 1 wings out, 2 landed, 3 dead on its back
local function plotFly(data, col, row, frame)
    local a = col / 8 * TAU
    local fx, fy, sx, sy = cos(a), sin(a), -sin(a), cos(a)
    local ox, oy = col * CELL + 4, row * CELL + 4
    local function put(u, v, c)
        local px = floor(ox + fx * u + sx * v + 0.5)
        local py = floor(oy + fy * u + sy * v + 0.5)
        if px >= col * CELL and px < (col + 1) * CELL and py >= row * CELL and py < (row + 1) * CELL then
            data:setPixel(px, py, c[1], c[2], c[3], 1)
        end
    end
    if frame == 3 then
        for u = -2, 2 do put(u, 0, BELLY) end
        put(-1, -1, BELLY)
        put(-1, 1, BELLY)
        put(0, -1, BELLY)
        put(0, 1, BELLY)
        for u = -1, 1 do
            put(u, -2, LEG)
            put(u, 2, LEG)
        end
        return
    end
    if frame == 0 then
        for s = -1, 1, 2 do
            put(-1, s * 2, WING)
            put(-2, s * 3, WING)
            put(-3, s * 3, WING)
            put(-2, s * 2, WING)
        end
    elseif frame == 1 then
        for s = -1, 1, 2 do
            put(-2, s * 1, WING)
            put(-3, s * 2, WING)
        end
    else
        put(-3, -1, WING)
        put(-3, 1, WING)
        put(-2, -1, WING)
        put(-2, 1, WING)
    end
    for u = -2, 1 do put(u, 0, BODY) end
    put(0, -1, THORAX)
    put(0, 1, THORAX)
    put(1, 0, THORAX)
    put(-1, -1, BODY)
    put(-1, 1, BODY)
    put(2, -1, EYE)
    put(2, 1, EYE)
    put(2, 0, BODY)
end

local function newFlyAtlas()
    local data = love.image.newImageData(CELL * 8, CELL * 5)
    for frame = 0, 3 do
        for col = 0, 7 do plotFly(data, col, frame, frame) end
    end
    -- the brood, in the last row's cells: egg, larvae (two wriggles), pupa
    local function put(cx, x, y, c)
        data:setPixel(cx * CELL + x, 4 * CELL + y, c[1], c[2], c[3], 1)
    end
    local EGG, LARVA, HEAD, PUPA, DARK = { 0.86, 0.82, 0.68 }, { 0.84, 0.78, 0.62 }, { 0.42, 0.34, 0.2 },
        { 0.46, 0.3, 0.14 }, { 0.3, 0.2, 0.1 }
    put(0, 4, 3, EGG)
    put(0, 4, 4, EGG)
    put(0, 4, 5, EGG)
    for x = 2, 5 do put(1, x, 4, LARVA) end
    put(1, 6, 4, HEAD)
    for x = 2, 5 do put(2, x, x % 2 == 0 and 4 or 5, LARVA) end
    put(2, 6, 5, HEAD)
    for x = 3, 5 do
        for y = 3, 5 do put(3, x, y, (x == 3 or y == 3) and PUPA or DARK) end
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    flyQuads = {}
    local w, h = data:getDimensions()
    for frame = 0, 3 do
        flyQuads[frame] = {}
        for col = 0, 7 do
            flyQuads[frame][col] = love.graphics.newQuad(col * CELL, frame * CELL, CELL, CELL, w, h)
        end
    end
    broodQuads = {}
    for k = 0, 3 do broodQuads[k] = love.graphics.newQuad(k * CELL, 4 * CELL, CELL, CELL, w, h) end
    return image
end

-- White (multiplied in: nothing) with marks: a shadow and four splats
local function newDecals()
    local W_, H_ = 80, 16
    local data = love.image.newImageData(W_, H_)
    data:mapPixel(function() return 1, 1, 1, 1 end)
    local rng = love.math.newRandomGenerator(783)
    local function dot(x, y, r, g, b)
        if x >= 0 and y >= 0 and x < W_ and y < H_ then data:setPixel(x, y, r, g, b, 1) end
    end
    for y = 6, 9 do
        for x = 5, 10 do
            if ((x - 7.5) / 3.2) ^ 2 + ((y - 7.5) / 2.2) ^ 2 < 1 then dot(x, y, 0.62, 0.62, 0.64) end
        end
    end
    for k = 1, 4 do
        local ox, oy = k * 16 + 8, 8
        for _ = 1, 26 do
            local a, d = rng:random() * TAU, rng:random() ^ 2 * 7
            dot(floor(ox + cos(a) * d), floor(oy + sin(a) * d * 0.7), 0.55, 0.42, 0.33)
        end
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    cornerQuads = {}
    for k = 0, 4 do cornerQuads[k] = love.graphics.newQuad(k * 16, 0, 16, 16, W_, H_) end
    return image
end

local FRUIT = { { 0.6, 0.16, 0.12 }, { 0.75, 0.55, 0.14 }, { 0.42, 0.5, 0.16 }, { 0.5, 0.28, 0.1 }, { 0.3, 0.32, 0.12 },
    { 0.55, 0.42, 0.28 } }
local ROT = { 0.14, 0.11, 0.07 }

-- Rotting food, six kinds of 16 x 12: whole fruit gone soft, rinds, cores
local function newFruit()
    local rng = love.math.newRandomGenerator(4)
    local data = love.image.newImageData(16 * 6, 12)
    for k = 0, 5 do
        local c = FRUIT[k + 1]
        for y = 0, 11 do
            for x = 0, 15 do
                local dx, dy = (x + 0.5 - 8) / (k % 2 == 0 and 7 or 6.5), (y + 0.5 - 6.5) / 4.6
                local e = dx * dx + dy * dy
                local keep = e < 1
                if k == 2 and x > 11 then keep = false end -- a half
                if k == 3 then keep = e < 1 and e > 0.28 end -- a rind
                if keep then
                    local spot = rng:random() < 0.2
                    local shade = 0.72 + 0.4 * (1 - (y + 0.5) / 12)
                    local r, g, b = c[1] * shade, c[2] * shade, c[3] * shade
                    if spot then r, g, b = ROT[1], ROT[2], ROT[3] end
                    if e > 0.84 then r, g, b = r * 0.5, g * 0.5, b * 0.5 end
                    data:setPixel(k * 16 + x, y, r, g, b, 1)
                end
            end
        end
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    fruitQuads = {}
    for k = 0, 5 do fruitQuads[k + 1] = love.graphics.newQuad(k * 16, 0, 16, 12, 96, 12) end
    return image
end

local function newSludge()
    local rng = love.math.newRandomGenerator(3)
    local lumps = {}
    for k = 1, 9 do lumps[k] = { 36 + (rng:random() - 0.5) * 34, 20 + (rng:random() - 0.5) * 16, 9 + rng:random() * 9 } end
    return bake(72, 40, function(x, y)
        local v = 0
        for _, l in ipairs(lumps) do
            local d = ((x + 0.5 - l[1]) / l[3]) ^ 2 + ((y + 0.5 - l[2]) / (l[3] * 0.7)) ^ 2
            if d < 1 then v = v + (1 - d) end
        end
        if v > 0.55 then
            if v > 1.8 and (x * 7 + y * 13) % 11 == 0 then return { 0.55, 0.65, 0.2, 1 } end -- scum
            return { 0.13 + v * 0.06, 0.26 + v * 0.1, 0.07, 1 }
        elseif v > 0.32 then
            return { 0.09, 0.14, 0.05, 1 }
        end
    end)
end

-- The machines that fought them, out of the original: each a 2 px-a-texel sprite
local function newWrecks()
    local K, D, M, L, G, O = { 0.05, 0.05, 0.08 }, { 0.13, 0.14, 0.19 }, { 0.28, 0.29, 0.35 }, { 0.5, 0.52, 0.58 },
        { 0.62, 0.72, 0.8 }, { 0.72, 0.4, 0.13 }
    local rng = love.math.newRandomGenerator(5)
    local dead = {}
    for k = 1, 22 do dead[k] = { 4 + rng:random(16), 31 - rng:random(0, 7) } end
    local jar = bake(26, 40, function(x, y) -- the killing jar, its lid askew, full of dead flies
        if y >= 0 and y <= 3 then
            if x >= 1 + y and x <= 15 + y then
                return (y == 0 or y == 3 or x == 1 + y or x == 15 + y) and K or M
            end
            return nil
        end
        if x >= 3 and x <= 22 and y >= 5 and y <= 37 then
            for _, d in ipairs(dead) do
                if d[1] == x and d[2] == y then return K end
            end
            if x == 3 or x == 22 or y == 37 then return K end
            if y > 31 then return D end
            if x == 7 and y > 7 and y < 30 then return G end
            if (x + y) % 3 == 0 then return { 0.38, 0.5, 0.56, 1 } end
            return nil
        end
        if y == 38 or y == 39 then
            if x >= 2 and x <= 23 then return y == 38 and M or K end
        end
    end)
    local tower = bake(40, 24, function(x, y) -- the stacker's blocks, toppled
        local blocks = { { 2, 15, O }, { 12, 17, M }, { 22, 14, L }, { 30, 18, O }, { 7, 8, M }, { 17, 7, O }, { 26, 8, L }, { 33, 11, M } }
        for _, b in ipairs(blocks) do
            if x >= b[1] and x < b[1] + 7 and y >= b[2] and y < b[2] + 5 then
                if x == b[1] or x == b[1] + 6 or y == b[2] + 4 then return K end
                return y == b[2] and L or b[3]
            end
        end
    end)
    local net = bake(38, 44, function(x, y) -- the net on its hoop, on a broken arm
        local hx, hy = x + 0.5 - 22, (y + 0.5 - 13) / 0.6
        local d = sqrt(hx * hx + hy * hy)
        if d > 11 and d < 13 and y < 16 then return L end
        if y >= 13 and y <= 38 and abs(x + 0.5 - 22) < 11 - (y - 13) * 0.3 and (x + y) % 3 == 0 then
            return { 0.46, 0.46, 0.42, 1 }
        end
        if y >= 26 and y <= 36 and x >= 18 and x <= 26 and (x * 3 + y * 5) % 7 == 0 then return K end -- what it caught
        -- the arm, down to its base at the left
        local t = (x - 6) / 16
        local py = 42 - t * 28
        if x >= 6 and x <= 22 and y > py - 2 and y < py + 2 then
            return abs(y - py) > 1 and K or M
        end
        if x <= 12 and y >= 38 then return (y == 38 or x == 0 or x == 12) and K or D end
    end)
    local turret = bake(30, 26, function(x, y) -- the ball turret, its balls spent
        local dx, dy = x + 0.5 - 12, y + 0.5 - 10
        if dx * dx + dy * dy < 49 then
            if dx * dx + dy * dy > 34 then return K end
            return (dx + dy < 0) and L or M
        end
        if x >= 14 and x <= 25 and y >= 7 and y <= 11 then
            return (y == 7 or y == 11 or x == 25) and K or D
        end
        if x >= 8 and x <= 16 and y >= 17 and y <= 24 then
            return (x == 8 or x == 16 or y == 24) and K or D
        end
        for _, b in ipairs({ { 2, 22 }, { 22, 21 }, { 27, 24 } }) do
            local bx, by = x + 0.5 - b[1], y + 0.5 - b[2]
            if bx * bx + by * by < 5 then return bx * bx + by * by > 3 and K or O end
        end
    end)
    return {
        { image = jar, w = 26, h = 40 },
        { image = tower, w = 40, h = 24 },
        { image = net, w = 38, h = 44 },
        { image = turret, w = 30, h = 26 },
    }
end

local function newBird()
    local K, D, B = { 0.05, 0.05, 0.08 }, { 0.14, 0.14, 0.17 }, { 0.75, 0.6, 0.2 }
    local function frame(lift)
        return function(x, y)
            local dx, dy = x + 0.5 - 12, y + 0.5 - 8
            if dx * dx / 16 + dy * dy / 5 < 1 then return abs(dx) < 2 and D or K end
            if x >= 16 and x <= 18 and y >= 7 and y <= 8 then return B end
            local span = abs(dx)
            local wy = 8 - lift * (1 - span / 12) * 6
            if span < 12 and abs(y + 0.5 - wy) < 1.4 - span * 0.05 then return K end
        end
    end
    return { bake(24, 16, frame(1)), bake(24, 16, frame(-0.7)) }
end

local function newDragonfly()
    local K, T, W = { 0.05, 0.05, 0.08 }, { 0.12, 0.5, 0.5 }, { 0.75, 0.85, 0.95 }
    local function frame(up)
        return function(x, y)
            if y == 7 and x >= 0 and x <= 14 then return (x % 3 == 0) and K or T end
            if x >= 14 and x <= 16 and y >= 6 and y <= 8 then return T end
            if y >= (up and 1 or 4) and y <= (up and 5 or 6) and (x == 11 or x == 13) then return W end
            if y >= 9 and y <= (up and 10 or 13) and (x == 11 or x == 13) then return W end
        end
    end
    return { bake(18, 15, frame(true)), bake(18, 15, frame(false)) }
end

-- A second of wings, cycles whole so it loops
local function newBuzz()
    local rate = 22050
    local data = love.sound.newSoundData(rate, rate, 16, 1)
    local function saw(hz, t)
        local v = hz * t
        return 2 * (v - floor(v)) - 1
    end
    for s = 0, rate - 1 do
        local t = s / rate
        local v = 0.5 * saw(187, t) + 0.3 * saw(211, t) + 0.2 * saw(233, t)
        v = v * (0.75 + 0.25 * sin(TAU * 9 * t)) * 0.4
        data:setSample(s, v)
    end
    local src = love.audio.newSource(data)
    src:setLooping(true)
    src:setVolume(0)
    return src
end

function swarm.ensureArt()
    if art then return end
    art = { fly = newFlyAtlas(), decals = newDecals(), fruit = newFruit(), sludge = newSludge(), wrecks = newWrecks(),
        bird = newBird(), dragonfly = newDragonfly() }
    shader = love.graphics.newShader(shadow.REACH_GLSL .. SWARM_SHADER)
    shader:send("groundAlpha", GROUND_ALPHA)
    art.flies = love.graphics.newSpriteBatch(art.fly, CAP + 16, "stream")
    art.onGround = love.graphics.newSpriteBatch(art.fly, BROOD_CAP + CORPSE_CAP + 16, "stream")
    art.marks = love.graphics.newSpriteBatch(art.decals, CAP + CORPSE_CAP + 16, "stream")
    art.heaps = love.graphics.newSpriteBatch(art.fruit, 400, "stream")
    if not swarm.buzz then
        local ok, src = pcall(newBuzz)
        if ok then swarm.buzz = src end
    end
end

--- The swarm's noise: how many are round you
function swarm.updateBuzz()
    local src = swarm.buzz
    if not src or not S or S.client then return end
    local near, f = 0, S.f
    if S.playerX then
        for i = 0, S.n - 1 do
            if (f.x[i] - S.playerX) ^ 2 + (f.y[i] - S.playerY) ^ 2 < 280 * 280 then near = near + 1 end
        end
    end
    local v = audio.volumes or {}
    local gain = min(1, near / 45) * 0.32 * (v.master or 1) * (v.weapon or 1)
    if audio.muted then gain = 0 end
    src:setVolume(gain)
    if gain > 0 and not src:isPlaying() then src:play() end
    src:setPitch(0.92 + min(1, near / 60) * 0.2)
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local BAND = 96 -- px of ground each slice of the flies covers in the sorted list
local SORT = 105 -- sort_y past the ground line

local function tint(i)
    local f = S.f
    local hawk = clamp01((f.hawk[i] + 1.5) / 3)
    -- doves slate blue, hawks rust; the wounded darker; just eclosed, pale
    local r, g, b = 0.45 + 0.65 * hawk, 0.6 - 0.2 * hawk, 0.7 - 0.45 * hawk
    local pale = (f.age[i] < 4) and (1 - f.age[i] / 4) or 0
    r, g, b = r + (1.5 - r) * pale, g + (1.5 - g) * pale, b + (1.3 - b) * pale
    local dark = 0.5 + 0.5 * f.hp[i]
    return r * dark, g * dark, b * dark, 1 - f.flash[i] * 0.9
end

local bands, bandCount = {}, {}

-- This frame's flies into their batches: band by band of ground, nearest last
local function fillFlies(x0, y0, x1, y1)
    local f = S.f
    local lerp = S.lerp
    for b in pairs(bandCount) do bandCount[b] = 0 end
    local lo, hi = math.huge, -math.huge
    for i = 0, S.n - 1 do
        local x = f.px[i] + (f.x[i] - f.px[i]) * lerp
        local y = f.py[i] + (f.y[i] - f.py[i]) * lerp
        if x > x0 and x < x1 and y > y0 and y < y1 + 140 then
            local b = floor(y / BAND)
            local list = bands[b]
            if not list then
                list = {}
                bands[b] = list
            end
            local c = (bandCount[b] or 0) + 1
            bandCount[b] = c
            list[c] = i
            if b < lo then lo = b end
            if b > hi then hi = b end
        end
    end
    art.flies:clear()
    art.marks:clear()
    local entries = {}
    if lo > hi then return entries end
    for b = lo, hi do
        local c = bandCount[b]
        if c and c > 0 then
            local first = art.flies:getCount()
            for k = 1, c do
                local i = bands[b][k]
                local x = f.px[i] + (f.x[i] - f.px[i]) * lerp
                local y = f.py[i] + (f.y[i] - f.py[i]) * lerp
                local z = f.pz[i] + (f.z[i] - f.pz[i]) * lerp
                local dir = floor(f.h[i] % TAU / TAU * 8 + 0.5) % 8
                local frame = z < 3 and 2 or floor(f.wing[i] * 0.5) % 2
                local r, g, bl, a = tint(i)
                art.flies:setColor(min(1, r), min(1, g), min(1, bl), a)
                local size = f.sex and f.sex[i] == 0 and 1.15 or 1
                art.flies:add(flyQuads[frame][dir], floor(x), floor(y - z), 0, size, size, 4, 4)
                if z >= 3 then art.marks:add(cornerQuads[0], floor(x), floor(y), 0, 0.7, 0.7, 8, 8) end
            end
            entries[#entries + 1] = { sort_y = (b + 1) * BAND + SORT, draw_type = "swarm", piece = "flies",
                first = first, count = c }
        end
    end
    return entries
end

local function fillGround(x0, y0, x1, y1)
    art.onGround:clear()
    art.heaps:clear()
    for _, p in ipairs(S.patches) do
        if not p.bitter and p.x > x0 - p.r and p.x < x1 + p.r and p.y > y0 - p.r and p.y < y1 + p.r then
            for k = 1, math.ceil(#p.pieces * clamp01(p.sugar + 0.15)) do
                local piece = p.pieces[k]
                local c = 0.45 + 0.55 * p.sugar
                art.heaps:setColor(c, c, c, 1)
                art.heaps:add(fruitQuads[piece.kind], piece.x, piece.y, 0, piece.flip, 1, 8, 6)
            end
        end
    end
    art.heaps:setColor(1, 1, 1, 1)
    art.onGround:setColor(1, 1, 1, 1)
    local t = love.timer.getTime()
    for _, b in ipairs(S.brood) do
        if b.x > x0 and b.x < x1 and b.y > y0 and b.y < y1 then
            local st = broodStage(b)
            local q = broodQuads[st == 0 and 0 or (st == 2 and 3 or (floor(t * 4 + b.x) % 2 == 0 and 1 or 2))]
            local grow = st == 1 and 0.7 + 0.5 * b.fed or 1
            art.onGround:add(q, floor(b.x), floor(b.y), 0, grow, grow, 4, 4)
        end
    end
    for _, c in ipairs(S.corpses) do
        if c.x > x0 and c.x < x1 and c.y > y0 and c.y < y1 then
            local dir = floor(c.h % TAU / TAU * 8 + 0.5) % 8
            local fade = clamp01((CORPSE_LIFE - c.age) / 2)
            art.onGround:setColor(fade, fade, fade, 1)
            art.onGround:add(flyQuads[3][dir], floor(c.x), floor(c.y - c.z), 0, 1, 1, 4, 4)
            if c.z < 1 then art.marks:add(cornerQuads[c.splat], floor(c.x), floor(c.y), 0, 1, 1, 8, 8) end
        end
    end
    art.onGround:setColor(1, 1, 1, 1)
end

--- The wrecks round a lair: where they go is worked out once, from the lair alone
local function wrecksOf(r)
    if r.wrecks then return r.wrecks end
    local grid = nav.new(24, 14)
    local rng = love.math.newRandomGenerator((r.seed or 783) + 7)
    local list = {}
    for k = 1, #art.wrecks do
        for _ = 1, 40 do
            local a, d = rng:random() * TAU, 210 + rng:random() * 190
            local x, y = r.lair.x + cos(a) * d, r.lair.y + sin(a) * d * 0.8
            local cx, cy = grid:cellAt(x, y)
            if grid:free(cx, cy) then
                list[#list + 1] = { x = x, y = y, kind = k, flip = rng:random() < 0.5 and -1 or 1 }
                break
            end
        end
    end
    r.wrecks = list
    return list
end

--- The sorted list's entries for the swarm: what's on the ground first, the
--- flies in slices, the wrecks round the lair (which stay after it's dead)
function swarm.populate()
    local here = regions.current
    local wrecks = here and here.boss == "swarm" and here.lair and var.region_bosses
    if wrecks or S then
        swarm.ensureArt()
        shadow.sendLights(shader)
        shader:send("daylight", daynight.daylight())
    end
    if wrecks then
        for _, w in ipairs(wrecksOf(here)) do
            dynamic_draw_list[#dynamic_draw_list + 1] = { sort_y = w.y + SORT, draw_type = "swarm", piece = "wreck",
                wreck = w }
        end
    end
    if not S then return end
    local x0, y0, x1, y1 = regions.view(48)
    local entries = fillFlies(x0, y0, x1, y1)
    if not S.client then fillGround(x0, y0, x1, y1) end
    dynamic_draw_list[#dynamic_draw_list + 1] = { sort_y = -1e9, draw_type = "swarm", piece = "ground" }
    for _, e in ipairs(entries) do dynamic_draw_list[#dynamic_draw_list + 1] = e end
    if not S.client then
        dynamic_draw_list[#dynamic_draw_list + 1] = { sort_y = renderer.ON_TOP, draw_type = "swarm", piece = "hunters" }
    end
end

local function drawGround()
    local t = love.timer.getTime()
    -- the ground's stained where the food's rotted, and sludge lies in pools
    love.graphics.setBlendMode("multiply", "premultiplied")
    love.graphics.setShader()
    for _, p in ipairs(S.patches) do
        if not p.bitter then
            local c = 0.82 - 0.2 * p.sugar
            love.graphics.setColor(c, c * 0.93, c * 0.8, 1)
            love.graphics.ellipse("fill", p.x, p.y, p.r, p.r * 0.75)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(art.marks)
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setShader(shader)
    love.graphics.setColor(1, 1, 1, 1)
    for _, p in ipairs(S.patches) do
        if p.bitter then
            love.graphics.draw(art.sludge, p.x - p.r, p.y - p.r * 0.72, 0, p.r * 2 / 72, p.r * 1.44 / 40)
        end
    end
    love.graphics.draw(art.heaps)
    love.graphics.draw(art.onGround)
    love.graphics.setShader()
    love.graphics.setBlendMode("add", "premultiplied")
    for _, p in ipairs(S.patches) do
        if p.bitter then
            local k = 0.12 + 0.05 * sin(t * 2 + p.x)
            love.graphics.setColor(0.35 * k, 0.75 * k, 0.15 * k, 0)
            love.graphics.draw(regions.glow, p.x - p.r * 1.4, p.y - p.r, 0, p.r * 2.8 / 64, p.r * 2 / 64)
        end
    end
end

--- One entry of the sorted list (lib/graphics/renderer.lua)
function swarm.drawPiece(d)
    local keep = love.graphics.getShader()
    local mode, alphaMode = love.graphics.getBlendMode()
    if d.piece == "wreck" then
        local w, sprite = d.wreck, art.wrecks[d.wreck.kind]
        love.graphics.setBlendMode("replace", "premultiplied")
        love.graphics.setShader(shader)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(sprite.image, w.x, w.y, 0, 2 * w.flip, 2, sprite.w / 2, sprite.h)
    elseif S then
        if d.piece == "ground" then
            drawGround()
        elseif d.piece == "flies" then
            love.graphics.setBlendMode("replace", "premultiplied")
            love.graphics.setShader(shader)
            love.graphics.setColor(1, 1, 1, 1)
            art.flies:setDrawRange(d.first + 1, d.count)
            love.graphics.draw(art.flies)
            art.flies:setDrawRange()
        elseif d.piece == "hunters" then
            local b = S.bird
            love.graphics.setBlendMode("replace", "premultiplied")
            love.graphics.setShader(shader)
            love.graphics.setColor(1, 1, 1, 1)
            b.wing = b.wing + love.timer.getDelta() * 12
            love.graphics.draw(art.bird[floor(b.wing) % 2 + 1], b.x, b.y - b.z * 0.5,
                atan2(b.vy - b.vz * 0.5, b.vx), 2, 2, 12, 8)
            for _, c in ipairs(S.chasers) do
                c.wing = c.wing + love.timer.getDelta() * 30
                love.graphics.draw(art.dragonfly[floor(c.wing) % 2 + 1], c.x, c.y - c.z, c.h, 1, 1, 15, 7)
            end
        end
    end
    love.graphics.setShader(keep)
    love.graphics.setBlendMode(mode, alphaMode)
    love.graphics.setColor(1, 1, 1, 1)
end

return swarm
