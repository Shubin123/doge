--[[
  The FlyWire connectome, from flywire-swarm (js/connectome.js): every fly in
  game/swarm.lua and the Connectome boss (game/swarmBoss.lua) run on it.

  618 cell types x hemisphere, 9,144 signed edges (game/flywire_data.lua, built
  by tools/build_flywire_data.py). A brain tick is the same rate model: activity
  goes HOPS synapses out from the senses, r[k+1] = tanh(I + g W r[k] - theta)
  where that's positive and 0 where it isn't, and what's read is a leaky average
  of the last hop.

  A fly only reads a few motor neurons and the octopaminergic cells, and r[0]
  is zero, so at hop h only the neurons both within h - 1 synapses of a sense
  and within HOPS - h of something read can change the result. flyLayers holds
  just those (about 3,500 operations a brain instead of 39,000) and gives the
  same numbers. The boss's brain runs them all (fullLayers): it's drawn firing.

  A pool is `cap` brains side by side: I (its senses, NI per brain), R (what's
  read, NO per brain), gain. Silencing a cell type (flywire.silence) works as
  in the original: those neurons stay at zero, in every brain.
]]
local flywire = {}

local has_ffi, ffi = pcall(require, "ffi")
if not has_ffi then ffi = nil end

local HOPS, THETA, NOISE, ALPHA = 4, 0.05, 0.03, 0.5
local random, tanh = math.random, math.tanh

-- Senses, left then right
flywire.IN = { sugar = 0, bitter = 2, orn = 4, loom = 6, mech = 8, pfl = 10 }
flywire.NI = 12
-- What's read, left then right; oa is the mean over its cell types
flywire.OUT = { dna02 = 0, dna01 = 2, gf = 4, mdn = 6, p9 = 8, mn9 = 10, oa = 12 }
flywire.NO = 13
flywire.N = 0
local NI, NO = flywire.NI, flywire.NO
local INPUTS = { "sugar", "bitter", "orn", "loom", "mech", "pfl3" }
local READS = { "dna02", "dna01", "gf", "mdn", "p9", "mn9" }

--- Arrays numbered from 0: C's where there's a JIT to use them, tables in the browser
function flywire.floats(n)
    if ffi then return ffi.new("float[?]", n) end
    local t = {}
    for i = 0, n - 1 do t[i] = 0 end
    return t
end

function flywire.ints(n)
    if ffi then return ffi.new("int32_t[?]", n) end
    local t = {}
    for i = 0, n - 1 do t[i] = 0 end
    return t
end

local ready = false
local N, edgeS, edgeT, edgeW, incoming
local inputNodes, readNodes, oaNodes
local A, B, drive -- one brain's working arrays
local flyLayers, fullLayers
local silenced = {}

--------------------------------------------------------------------------------
-- Layers: what each hop has to compute
--------------------------------------------------------------------------------

local function newSet(list)
    local set = {}
    for _, v in ipairs(list) do set[v] = true end
    return set
end

-- The hop-by-hop work. `reads`: the neurons wanted at the last hop, or nil for all
local function buildLayers(reads)
    local fw, bw = {}, {}
    if reads then
        fw[1] = {}
        for _, v in ipairs(inputNodes) do
            if not silenced[v] then fw[1][v] = true end
        end
        for h = 2, HOPS do
            local set = {}
            for k in pairs(fw[1]) do set[k] = true end
            for e = 1, #edgeS do
                if fw[h - 1][edgeS[e]] and not silenced[edgeT[e]] then set[edgeT[e]] = true end
            end
            fw[h] = set
        end
        bw[HOPS] = newSet(reads)
        for h = HOPS - 1, 1, -1 do
            local set = {}
            for e = 1, #edgeS do
                if bw[h + 1][edgeT[e]] then set[edgeS[e]] = true end
            end
            bw[h] = set
        end
    else
        local all = {}
        for t = 0, N - 1 do
            if not silenced[t] then all[t] = true end
        end
        for h = 1, HOPS do fw[h], bw[h] = all, all end
    end

    local L = { nodes = {}, first = {}, src = {}, wgt = {} }
    local live = {}
    for h = 1, HOPS do
        local set, list = {}, {}
        for t = 0, N - 1 do
            if fw[h][t] and bw[h][t] then
                set[t] = true
                list[#list + 1] = t
            end
        end
        live[h] = set
        local first, src, wgt = {}, {}, {}
        for k, t in ipairs(list) do
            first[k] = #src + 1
            if h > 1 then -- (hop 1 starts from nothing)
                for _, e in ipairs(incoming[t] or {}) do
                    if live[h - 1][edgeS[e]] then
                        src[#src + 1] = edgeS[e]
                        wgt[#wgt + 1] = edgeW[e]
                    end
                end
            end
        end
        first[#list + 1] = #src + 1
        L.nodes[h], L.first[h], L.src[h], L.wgt[h] = list, first, src, wgt
    end
    L.last = live[HOPS]
    return L
end

local function rebuild()
    local reads = {}
    for _, v in ipairs(readNodes) do reads[#reads + 1] = v end
    for _, v in ipairs(oaNodes) do reads[#reads + 1] = v end
    flyLayers = buildLayers(reads)
    fullLayers = buildLayers(nil)
    for t in pairs(silenced) do A[t], B[t] = 0, 0 end
end

--------------------------------------------------------------------------------
-- Brains
--------------------------------------------------------------------------------

-- Propagate from what's in `drive`; the last hop's activity
local function sweep(L, g)
    local prev, cur = A, B
    for h = 1, HOPS do
        local nodes, first, src, wgt = L.nodes[h], L.first[h], L.src[h], L.wgt[h]
        for k = 1, #nodes do
            local t = nodes[k]
            local x = drive[t] - THETA
            for e = first[k], first[k + 1] - 1 do
                x = x + g * wgt[e] * prev[src[e]]
            end
            if h == HOPS then x = x + NOISE * (random() - 0.5) end
            cur[t] = x > 0 and tanh(x) or 0
        end
        prev, cur = cur, prev
    end
    return prev
end

--- A pool of `cap` brains; `full`: all 618 neurons run, smoothed in pool.activity
function flywire.pool(cap, full)
    local pool = { cap = cap, full = full, R = flywire.floats(cap * NO), I = flywire.floats(cap * NI),
        gain = flywire.floats(cap) }
    if full then pool.activity = flywire.floats(N) end
    for f = 0, cap - 1 do pool.gain[f] = 9 end
    return pool
end

function flywire.reset(pool, f)
    for k = 0, NO - 1 do pool.R[f * NO + k] = 0 end
    for k = 0, NI - 1 do pool.I[f * NI + k] = 0 end
end

--- Brain `from`'s state into slot `to` (`to`'s fly has died)
function flywire.move(pool, from, to)
    for k = 0, NO - 1 do pool.R[to * NO + k] = pool.R[from * NO + k] end
    for k = 0, NI - 1 do pool.I[to * NI + k] = pool.I[from * NI + k] end
    pool.gain[to] = pool.gain[from]
end

--- One tick of brain `f`
function flywire.step(pool, f)
    local I, R, o = pool.I, pool.R, f * NO
    for k = 1, NI do drive[inputNodes[k]] = I[f * NI + k - 1] end
    local L = pool.full and fullLayers or flyLayers
    local last, live = sweep(L, pool.gain[f]), L.last
    for k = 1, #readNodes do
        local t = readNodes[k]
        R[o + k - 1] = R[o + k - 1] + ALPHA * ((live[t] and last[t] or 0) - R[o + k - 1])
    end
    local sum = 0
    for k = 1, #oaNodes do
        local t = oaNodes[k]
        if live[t] then sum = sum + last[t] end
    end
    R[o + NO - 1] = R[o + NO - 1] + ALPHA * (sum / #oaNodes - R[o + NO - 1])
    if pool.full then
        local a = pool.activity
        for t = 0, N - 1 do
            a[t] = a[t] + ALPHA * ((live[t] and last[t] or 0) - a[t])
        end
    end
end

--- Silence a cell type (a key of the data's io, or "oa") in every brain
function flywire.silence(key)
    local nodes = key == "oa" and oaNodes or flywire.io[key]
    for _, t in ipairs(nodes) do
        if t >= 0 then silenced[t] = true end
    end
    rebuild()
end

--- Back to the whole connectome
function flywire.silenceNone()
    if next(silenced) == nil then return end
    silenced = {}
    rebuild()
end

-- Which PFL3 hemisphere turns the fly right (their axons cross the midline), as
-- Sim.calibrate: drive each in turn and see which DNa02 answers
local function calibrate()
    local pool, IN, OUT = flywire.pool(1), flywire.IN, flywire.OUT
    local function probe(slot)
        flywire.reset(pool, 0)
        pool.I[slot] = 1
        for _ = 1, 60 do flywire.step(pool, 0) end
        return pool.R[OUT.dna02 + 1] - pool.R[OUT.dna02]
    end
    local l, r = probe(IN.pfl), probe(IN.pfl + 1)
    flywire.PFL_RIGHT = l > r and IN.pfl or IN.pfl + 1 -- drive this to turn right
    flywire.PFL_LEFT = l > r and IN.pfl + 1 or IN.pfl
end

--- Read the data (the first time: it's only needed where there's a swarm)
function flywire.ensure()
    if ready then return end
    local data = require("game.flywire_data")
    N, flywire.N = data.N, data.N
    edgeS, edgeT, edgeW, incoming = {}, {}, {}, {}
    for s, t, w in data.edges:gmatch("(%d+)%s+(%d+)%s+(%S+)") do
        local e = #edgeS + 1
        edgeS[e], edgeT[e], edgeW[e] = tonumber(s), tonumber(t), tonumber(w)
        local list = incoming[edgeT[e]]
        if not list then
            list = {}
            incoming[edgeT[e]] = list
        end
        list[#list + 1] = e
    end
    flywire.io, oaNodes = data.io, data.oa
    inputNodes, readNodes = {}, {}
    for _, key in ipairs(INPUTS) do
        for _, t in ipairs(data.io[key]) do inputNodes[#inputNodes + 1] = t end
    end
    for _, key in ipairs(READS) do
        for _, t in ipairs(data.io[key]) do readNodes[#readNodes + 1] = t end
    end
    A, B, drive = flywire.floats(N), flywire.floats(N), flywire.floats(N)

    -- the brain's anatomy: each cell type's place, and neurons' positions, -0.5..0.5
    flywire.positions = {}
    local t = 0
    for x, y, z in data.positions:gmatch("(%S+)%s+(%S+)%s+(%S+)") do
        flywire.positions[t] = { tonumber(x), tonumber(y), tonumber(z) }
        t = t + 1
    end
    flywire.cloud = {}
    local q = data.quant
    for x, y, z, g in data.cloud:gmatch("(%d+)%s+(%d+)%s+(%d+)%s+(%-?%d+)") do
        flywire.cloud[#flywire.cloud + 1] = { tonumber(x) / q - 0.5, tonumber(y) / q - 0.5, tonumber(z) / q - 0.5,
            tonumber(g) }
    end

    -- the strongest wiring, drawn when it fires
    local order = {}
    for e = 1, #edgeS do order[e] = e end
    table.sort(order, function(a, b) return math.abs(edgeW[a]) > math.abs(edgeW[b]) end)
    flywire.wires = {}
    for k = 1, math.min(420, #order) do
        local e = order[k]
        flywire.wires[k] = { edgeS[e], edgeT[e], edgeW[e] }
    end

    rebuild()
    calibrate()
    ready = true
end

return flywire
