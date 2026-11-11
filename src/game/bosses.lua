--[[
  Bosses: the way out of home, who guards which region, and how your
  weapons reach them.

  The gate: the home portal starts sealed. Standing in it offers to summon
  its guardian (game/portal.lua: bosses.summon), the bear, which comes out a
  little in front of it; beat it and the gate opens for good. Past it the
  regions open one at a time, in regions.list's order, each once the boss of
  every region before it is beaten (bosses.isRegionOpen: game/portal.lua goes
  by it, game/quests.lua tells you). Region portals always take you home.

  Lairs: a region with a `boss` in regions.list has one waiting at its lair
  (`r.lair`, the junction in front of its main landmark: game/regions.lua).
  It comes out while you're in that region and goes when you leave, back at
  full health next time. Beaten, it stays beaten, and the region's stalls go
  up (bosses.cleared: game/shop.lua); a region without a boss has its stalls
  from the start. Host and single player only: clients draw what the host
  sends and get the gate and what's beaten in the snapshot. Saves keep both
  (bosses.getSaveData). With var.region_bosses off (the GPU harness) there
  are no lair bosses, the gate's open and every stall's up.

  Kinds (KINDS): the bear (game/boss.lua, the gate's), the Wasteland's
  Connectome (game/swarmBoss.lua, with its flies, game/swarm.lua), the
  Castle's Castellan (game/castellan.lua, with her guard), Neon City's robot
  arm (game/robotArm.lua) and the Sanctum's Choir (game/choir.lua: three that
  rise again unless they fall together). Each has spawnAt(x, y, lair) ->
  inst, despawnInst(inst, quiet) and alive(inst), and calls
  bosses.defeated(lair, x, y) when one dies.

  Hits: each boss body's fixture carries a part, { type = "boss", boss =
  inst, body, radius, weak, hit = fn(inst, damage, x, y, kind) }, registered
  here while it can be hurt (bosses.register). util/collision.lua (bullets,
  fireballs, rockets and their splash), arrows.lua, teslaCoil.lua and
  blackholeGun.lua hand what lands on one to bosses.hit; bosses.parts lists
  them for the weapons that look for targets rather than touch them. `weak`
  scales what a part takes (the arm's claw more, its base less).
]]
local bosses = {}

local KINDS = { bear = "game.boss", arm = "game.robotArm", swarm = "game.swarmBoss",
    castellan = "game.castellan", choir = "game.choir" }
local GATE = "gate"       -- the lair id of the gate's guardian
local GATE_BOSS = "bear"
local HUD_RANGE = 900     -- px: the nearest live boss this close shows its bar over the HUD

bosses.parts = {}         -- every hittable part of every live boss
bosses.beaten = {}        -- region id -> true
bosses.gateOpen = false   -- the home portal's guardian is beaten
local live = {}           -- lair id -> the instance out of it
local lairKind = {}       -- lair id -> its boss's kind (for the gate: GATE_BOSS)

local function hosting()
    return not var.multiplayer or var.multiplayer == 1
end

local function kind(name)
    return require(KINDS[name])
end

--------------------------------------------------------------------------------
-- Progress
--------------------------------------------------------------------------------

--- Whether the home portal takes you anywhere yet
function bosses.isGateOpen()
    return bosses.gateOpen or not var.region_bosses
end

--- Whether region `id`'s boss is beaten (or it never had one): its stalls are up
function bosses.cleared(id)
    if not var.region_bosses or bosses.beaten[id] then return true end
    for _, r in ipairs(regions.list) do
        if r.id == id then return not r.boss end
    end
    return true
end

--- The first region before `id` in regions.list whose boss still stands, or
--- nil if none does
function bosses.blockedBy(id)
    for _, r in ipairs(regions.list) do
        if r.id == id then return nil end
        if not bosses.cleared(r.id) then return r end
    end
end

--- Whether the portals will take you to region `id`: home always, the rest
--- past the gate and in order
function bosses.isRegionOpen(id)
    if id == regions.list[1].id then return true end
    return bosses.isGateOpen() and not bosses.blockedBy(id)
end

--- Whether the gate's guardian is out
function bosses.gateFight()
    local inst = live[GATE]
    return inst ~= nil and kind(GATE_BOSS).alive(inst)
end

-- Where the gate's guardian comes out: the first clear ground in front of
-- the home portal
local function gateSpot()
    local p = regions.list[1].portal
    local x, y = p.x + 17, p.y + 200
    local function clear(cx, cy)
        local blocked = false
        world:queryBoundingBox(cx - 40, cy - 40, cx + 40, cy + 40, function(f)
            if not f:isSensor() and f:getBody():getType() == "static" then
                blocked = true
                return false
            end
            return true
        end)
        return not blocked
    end
    for ring = 0, 10 do
        local n = ring == 0 and 1 or 10
        for k = 0, n - 1 do
            local a = math.pi / 2 + k / n * math.pi * 2
            local cx, cy = x + math.cos(a) * ring * 40, y + math.sin(a) * ring * 40
            if clear(cx, cy) then return cx, cy end
        end
    end
    return x, y
end

--- The gate's guardian comes out (game/portal.lua's prompt). True if it did.
function bosses.summon()
    if not hosting() or bosses.isGateOpen() or bosses.gateFight() then return false end
    local x, y = gateSpot()
    live[GATE], lairKind[GATE] = kind(GATE_BOSS).spawnAt(x, y, GATE), GATE_BOSS
    camera.shake(6, 0.4)
    inventory.notify("The gate's guardian wakes")
    return true
end

--------------------------------------------------------------------------------
-- Hits
--------------------------------------------------------------------------------

--- A boss part's fixture user data, or nil if f isn't one.
function bosses.part(f)
    local ud = f:getUserData()
    if type(ud) == "table" and ud.type == "boss" then return ud end
end

function bosses.register(part)
    bosses.parts[#bosses.parts + 1] = part
end

function bosses.unregister(part)
    for i = #bosses.parts, 1, -1 do
        if bosses.parts[i] == part then table.remove(bosses.parts, i) end
    end
end

--- `damage` lands on `part` at (x, y), a hit of `kind` ("hole", "scorch").
--- Safe inside a physics callback: a boss that dies goes in its own update.
function bosses.hit(part, damage, x, y, kind_)
    if not hosting() or not part.boss or damage <= 0 then return end
    part.hit(part.boss, damage * (part.weak or 1), x, y, kind_)
end

--- The part of a live boss within `radius` of (x, y) (to its edge), or nil
function bosses.near(x, y, radius)
    for _, p in ipairs(bosses.parts) do
        if p.body and not p.body:isDestroyed() then
            local px, py = p.body:getPosition()
            local r = radius + (p.radius or 0)
            if (px - x) ^ 2 + (py - y) ^ 2 < r * r then return p end
        end
    end
end

-- Each boss with a part within `radius` of (x, y): fn(part, k), its
-- nearest part and how near (1 at the middle, 0 at the edge)
local function eachReached(x, y, radius, fn)
    local best = {}
    for _, p in ipairs(bosses.parts) do
        if p.body and not p.body:isDestroyed() then
            local px, py = p.body:getPosition()
            local d = math.max(0, math.sqrt((px - x) ^ 2 + (py - y) ^ 2) - (p.radius or 0))
            if d <= radius then
                local k = 1 - d / radius
                local b = best[p.boss]
                if not b or k > b.k then best[p.boss] = { part = p, k = k } end
            end
        end
    end
    for _, b in pairs(best) do fn(b.part, b.k) end
end

--- A blast at (x, y) reaching `radius`: each boss it reaches takes up to
--- `damage` (falling off with distance squared, as a rocket's on enemies,
--- never under 5) once, at its nearest part.
function bosses.blast(x, y, radius, damage)
    swarm.blast(x, y, radius, damage) -- (and the flies, the brood, the heaps)
    eachReached(x, y, radius, function(part, k)
        local px, py = part.body:getPosition()
        bosses.hit(part, math.max(5, damage * k * k), px, py, "scorch")
    end)
end

--- `dps` for `dt` to each boss within `radius` of (x, y): a black hole too
--- small to swallow one gnawing at it
function bosses.drain(x, y, radius, dps, dt)
    swarm.drain(x, y, radius, dt) -- (flies it can swallow)
    eachReached(x, y, radius, function(part)
        local px, py = part.body:getPosition()
        bosses.hit(part, dps * dt, px, py, "scorch")
    end)
end

--------------------------------------------------------------------------------
-- Lairs
--------------------------------------------------------------------------------

local BOSS_GEM = 30 -- XP in each of the six gems a boss leaves

--- A boss died at (x, y), out of lair `lair` (a region's id, GATE, or nil
--- for one from the console). What it leaves: its light, a ring of XP gems,
--- a trinket you haven't got (or a medkit) and a medkit.
function bosses.defeated(lair, x, y)
    if lair == GATE then
        bosses.gateOpen = true
        portal.opened() -- (the flash, and word that it's open)
    elseif lair then
        bosses.beaten[lair] = true
        for i, r in ipairs(regions.list) do
            if r.id == lair then
                local ahead = regions.list[i + 1]
                local way = ahead and bosses.isRegionOpen(ahead.id) and ", and the way to " .. ahead.name or ""
                inventory.notify(r.name .. " is free: its stalls open" .. way)
            end
        end
    end
    for i = 1, 6 do
        local a = i / 6 * math.pi * 2
        suckLight.spawn(x + math.cos(a) * 24, y + math.sin(a) * 16)
        xp.drop(x + math.cos(a) * 44, y + math.sin(a) * 30, BOSS_GEM)
    end
    local id = trinkets.unowned(love.math.newRandomGenerator(math.floor(x + y * 7) % 100000 + 1))
    inventory.place(id or "medkit", 1, x - 18, y + 10)
    inventory.place("medkit", 1, x + 18, y + 10)
end

--- Each frame where the world runs: bosses come out of their lairs while
--- you're in their region and go when you leave.
function bosses.update(dt)
    if not hosting() then return end
    if live[GATE] and not kind(GATE_BOSS).alive(live[GATE]) then live[GATE] = nil end
    local here = regions.current
    for _, r in ipairs(regions.list) do
        if r.boss and r.lair then
            local M = kind(r.boss)
            local inst = live[r.id]
            if inst and not M.alive(inst) then
                inst, live[r.id] = nil, nil -- killed (bosses.defeated), or cleared from the console
            end
            if inst and here ~= r then
                M.despawnInst(inst)
                live[r.id] = nil
            elseif not inst and here == r and var.region_bosses and not bosses.beaten[r.id] then
                live[r.id], lairKind[r.id] = M.spawnAt(r.lair.x, r.lair.y, r.id), r.boss
            end
        end
    end
end

--------------------------------------------------------------------------------
-- HUD
--------------------------------------------------------------------------------

-- fn(name, health, max, x, y) for each live boss, here or as the host sent them
local function each(fn)
    if hosting() then
        for _, b in pairs(boss.bosses) do
            local x, y = b.body:getPosition()
            fn("BEAR BOSS", b.health, b.max_health, x, y)
        end
    else
        for _, b in pairs(renderer.networked_state.bosses) do
            if b.health > 0 then fn("BEAR BOSS", b.health, b.max_health, b.x, b.y) end
        end
    end
    robotArm.eachLive(function(a)
        fn(robotArm.NAME, a.health, a.max_health, a.x, a.y)
    end)
    swarmBoss.eachLive(function(a)
        fn(swarmBoss.NAME .. " x" .. a.adults, a.health, a.max_health, a.x, a.y)
    end)
    castellan.eachLive(function(a)
        fn(castellan.NAME, a.health, a.max_health, a.x, a.y)
    end)
    choir.eachLive(function(m) -- (each of the three standing: the nearest one's shown)
        fn(choir.NAME .. ": " .. m.def.name, m.health, m.max_health, m.x, m.y)
    end)
end

--- The nearest live boss's name and health across the top of the screen
--- (ui/hud.lua: in GUI units `w` wide, text at scale `ts`)
function bosses.drawHUD(w, font, ts)
    if not (player and player.body) then return end
    local px, py = player.body:getPosition()
    local name, health, max, nearest
    each(function(n, h, m, x, y)
        local d = (x - px) ^ 2 + (y - py) ^ 2
        if d < HUD_RANGE * HUD_RANGE and (not nearest or d < nearest) then
            name, health, max, nearest = n, h, m, d
        end
    end)
    if not name then return end
    local bw, bh = 160, 5
    local x, y = math.floor((w - bw) / 2), 34
    local fill = math.floor(bw * math.max(0, math.min(1, health / math.max(1, max))) + 0.5)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", x - 1, y - 1, bw + 2, bh + 2)
    love.graphics.setColor(0.25, 0.05, 0.06, 0.9)
    love.graphics.rectangle("fill", x, y, bw, bh)
    love.graphics.setColor(0.9, 0.15, 0.2, 1)
    love.graphics.rectangle("fill", x, y, fill, bh)
    love.graphics.setColor(1, 0.55, 0.55, 1)
    love.graphics.rectangle("fill", x, y, fill, 1)
    local tx, ty = math.floor((w - font:getWidth(name) * ts) / 2), y - 2 - font:getHeight() * ts
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.print(name, tx + 1, ty + 1, 0, ts, ts)
    love.graphics.setColor(1, 0.9, 0.9, 1)
    love.graphics.print(name, tx, ty, 0, ts, ts)
end

--------------------------------------------------------------------------------
-- Saves and the network
--------------------------------------------------------------------------------

-- What's beaten, and the gate (the bosses out of lairs aren't kept: they
-- come back out at full health)
function bosses.getSaveData()
    local list = {}
    for id in pairs(bosses.beaten) do list[#list + 1] = id end
    table.sort(list)
    return { beaten = list, gate = bosses.gateOpen }
end

--- Put back a getSaveData() (nil, for a save from before the gate: sealed,
--- nothing beaten)
function bosses.restore(data)
    for id, inst in pairs(live) do
        kind(lairKind[id]).despawnInst(inst, true)
        live[id] = nil
    end
    robotArm.despawnAll() -- (and any from the console)
    swarmBoss.despawnAll()
    castellan.despawnAll()
    choir.despawnAll()
    bosses.beaten = {}
    for _, id in ipairs(data and data.beaten or {}) do bosses.beaten[id] = true end
    bosses.gateOpen = data and data.gate == true or false
end

--- Host: the gate and what's beaten, for clients' portals and stalls
function bosses.getNetworkData()
    return bosses.getSaveData()
end

function bosses.applyNetworkData(data)
    if not data then return end
    bosses.beaten = {}
    for _, id in ipairs(data.beaten or {}) do bosses.beaten[id] = true end
    bosses.gateOpen = data.gate == true
end

return bosses
