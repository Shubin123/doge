--[[
  The Wasteland's boss (game/bosses.lua's "swarm"): the Connectome, a fly's
  brain the size of a car hanging over its lair, drawn from real FlyWire neuron
  positions and firing in its own connectome (game/flywire.lua), with the
  region's flies (game/swarm.lua) for a body.

  Its moves come out of its wiring, the same pathways the flies have:
    LPLC2 -> Giant Fiber  rush it and it startles: it darts off, flies bursting
    Johnston's organ -> MDN  hit it and it backs away
    sugar -> MN9          low on health it finds the best heap (take-the-best),
                          lands, and heals only while MN9 fires
    PFL3 -> DNa02, DNp09  it steers toward you and walks
    octopamine            how often it attacks, and how selfish the flies play
  What you see firing is what it's about to do; the pathways are named as
  they go.

  What it does with its body, the flies it's conscripted (they can't be fed
  or bred while they serve, but they're still flies, and escape if spooked):
    cloud    round it, thick enough to shield it (it takes less through them)
    lance    each fly picks Hawk or Dove as it would on food: the hawks come at you
    engulf   a ring closes on where you stood, with a gap on the far side
    giant    they form one huge fly over a line through you, and dive it; a
             roll goes under
    call     every fly in the region comes to it
  All along it spits maggots at you.

  Four lobes on it can be shot out. Each silences that cell type in every
  brain, as the original's silencing does: MN9 (no feeding, it can't heal), the
  Giant Fiber (no escapes), PFL3 (they lose their aim), octopamine (they calm).
  Each is worth a good piece of its health.

  As it's hurt it changes the game they're playing on the food: Hawk-Dove, then
  Stag Hunt, then Prisoner's Dilemma, every fly for itself. When it dies every
  fly drops dead with it, and the region is free.
]]
local swarmBoss = {}

local flywire = require("game.flywire")
local sin, cos, atan2, sqrt, abs, min, max, floor = math.sin, math.cos, math.atan2, math.sqrt, math.abs, math.min,
    math.max, math.floor

swarmBoss.NAME = "THE CONNECTOME"
swarmBoss.live = nil -- where the world runs
swarmBoss.net = nil  -- as the host sent it (clients)

local U = 16
local TAU = math.pi * 2
local HEALTH = 340
local HOVER = 88         -- px over the ground
local CORE_R, LOBE_R = 30, 14
local LOBE_HP = 28       -- (a pistol shot is 1; lobes take WEAK_LOBE of that)
local WEAK_LOBE = 1.6
local LOBE_WORTH = 0.08  -- share of its health that goes with each lobe
local BRAIN_SCALE = 190  -- px across its widest, about
local SIGHT = 760        -- px: this close, it wakes
local LEASH = 560        -- it doesn't go further than this from its lair
local BODY_WANT = 110    -- flies in its body, as near as it can
local SHIELD_FULL = 60   -- this many close by and it takes the least it can
local SHIELD_MIN = 0.45  -- and that's this share of a hit
local BRAIN_HZ = rawget(_G, "jit") and 15 or 6
local SORT = 105

local LANCE = { dur = 2.6, speed = 430 }
local ENGULF = { dur = 1.7, from = 175, to = 30, gap = 0.5, damage = 80 }
local GIANT = { form = 1.0, dive = 0.42, reach = 420, radius = 54, damage = 90, knock = 360 }
local CALL = { dur = 1.2, every = 16 }
local FEED = { heal = 12, reach = 520, every = 14, seek = 3.5, dur = 6, breakAt = 22 }
local EGG = { speed = 250, damage = 14, radius = 4, life = 2.4, every = 1.2, range = 520 }
local EGG_NEON = { core = { 0.8, 1, 0.4 }, halo = { 0.4, 0.9, 0.1 }, radius = 10 }
local DEATH_TIME = 2.4
-- the game the flies play as it weakens: the health it starts at, what it pays, the bite rate it allows
local PHASES = {
    { above = 2 / 3, game = "hawkdove", V = 2, C = 5, cap = 55 },
    { above = 1 / 3, game = "stag", V = 4, C = 1.5, cap = 75, say = "Stag Hunt: they move as one" },
    { above = 0, game = "pd", V = 3, C = 1, cap = 105, say = "Prisoner's Dilemma: every fly for itself" },
}
local LOBES = {
    { key = "mn9", label = "MN9", dx = 0, dy = 0.32, dz = 0.1, color = { 0.45, 1, 0.5 },
        say = "MN9 silenced: it can't feed" },
    { key = "gf", label = "GF", dx = -0.42, dy = -0.04, dz = 0.12, color = { 0.4, 0.75, 1 },
        say = "Giant Fiber silenced: they can't escape" },
    { key = "pfl3", label = "PFL3", dx = 0, dy = -0.32, dz = -0.1, color = { 1, 0.85, 0.35 },
        say = "PFL3 silenced: they lose their aim" },
    { key = "oa", label = "OA", dx = 0.42, dy = -0.04, dz = -0.12, color = { 1, 0.4, 0.55 },
        say = "Octopamine silenced: the swarm calms" },
}

local function hosting()
    return not var.multiplayer or var.multiplayer == 1
end

local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end
local function wrap(a) return atan2(sin(a), cos(a)) end
local function unit(x, y)
    local l = sqrt(x * x + y * y)
    if l < 1e-6 then return 1, 0 end
    return x / l, y / l
end

--------------------------------------------------------------------------------
-- Life and death
--------------------------------------------------------------------------------

local function hurt(a, damage)
    if a.dying or a.gone then return end
    a.health = max(0, a.health - damage)
    a.flash = 0.12
    a.jolt = min(1, a.jolt + damage / 12) -- felt through Johnston's organ
    a.startle = max(a.startle, min(1, damage / 25)) -- and a big hit looms
    a.feedHits = a.feedHits + damage
    if a.state == "sleep" then a.state, a.t, a.dur = "hover", 0, 1.2 end
end

local function hitLobe(lobe, a, damage)
    if a.dying or a.gone or lobe.dead then return end
    lobe.hp = lobe.hp - damage
    lobe.flash = 0.15
    hurt(a, damage * 0.5)
    if lobe.hp <= 0 then lobe.dying = true end -- (silenced in the update, out of the physics step)
end

local function addPart(a, body, fixture, radius, weak, hit)
    local part = { type = "boss", boss = a, body = body, radius = radius, weak = weak, hit = hit }
    fixture:setUserData(part)
    fixture:setGroupIndex(-888)
    bosses.register(part)
    a.parts[#a.parts + 1] = part
    return part
end

local function sensor(a, radius)
    local body = love.physics.newBody(world, a.x, a.y - a.z, "kinematic")
    local fixture = love.physics.newFixture(body, love.physics.newCircleShape(radius))
    fixture:setSensor(true)
    a.bodies[#a.bodies + 1] = body
    return body, fixture
end

local ensureBrainArt

--- A new brain over (x, y), and its swarm; `lair`, the region it guards
function swarmBoss.spawnAt(x, y, lair)
    if swarmBoss.live then swarmBoss.despawnInst(swarmBoss.live, true) end
    flywire.ensure()
    flywire.silenceNone()
    swarm.begin(regions.at(x, y), x, y)
    ensureBrainArt()
    local a = { x = x, y = y, homeX = x, homeY = y, z = HOVER, h = 0, spin = 0, lair = lair, health = HEALTH,
        max_health = HEALTH, state = "sleep", t = 0, dur = 0, time = 0, flash = 0, phase = 1, jolt = 0, startle = 0,
        startleCd = 2, feedCd = 8, callCd = 6, eggT = 2, brainT = 0, feedHits = 0, conscriptT = 0, rage = 0,
        ringR = 0, ringK = 0, ringX = 0, ringY = 0, gapDir = 0, labels = {}, labelCd = {}, parts = {}, bodies = {},
        o = { turn = 0, gf = 0, mdn = 0, p9 = 0, mn9 = 0, oa = 0 } }
    a.rng = love.math.newRandomGenerator(floor(x * 3 + y) % 100000 + 1)
    a.brain = flywire.pool(1, true)
    local body, fixture = sensor(a, CORE_R)
    a.core = addPart(a, body, fixture, CORE_R, 1, hurt)
    a.lobes = {}
    for _, def in ipairs(LOBES) do
        local lobe = { def = def, hp = LOBE_HP, flash = 0 }
        lobe.body, fixture = sensor(a, LOBE_R)
        lobe.part = addPart(a, lobe.body, fixture, LOBE_R, WEAK_LOBE, function(inst, damage) hitLobe(lobe, inst, damage) end)
        a.lobes[#a.lobes + 1] = lobe
    end
    swarm.setFormation(swarmBoss.formation)
    swarmBoss.live = a
    return a
end

function swarmBoss.alive(a)
    return not a.gone
end

--- Take brain `a` away, and its swarm. One that died is beaten
--- (bosses.defeated), but `quiet`ly (a save being loaded) it just goes.
function swarmBoss.despawnInst(a, quiet)
    if a.gone then return end
    a.gone = true
    for _, p in ipairs(a.parts) do bosses.unregister(p) end
    for _, body in ipairs(a.bodies) do
        if not body:isDestroyed() then body:destroy() end
    end
    if swarmBoss.live == a then swarmBoss.live = nil end
    if a.dying and not quiet then
        bosses.defeated(a.lair, a.x, a.y + 26)
    else
        swarm.stop() -- (the corpses of one it killed lie where they fell)
    end
end

function swarmBoss.despawnAll()
    if swarmBoss.live then swarmBoss.despawnInst(swarmBoss.live, true) end
end

--- fn(a) for the live brain (here, or as the host sent it); a.adults is what
--- the HUD shows beside its name
function swarmBoss.eachLive(fn)
    local a = hosting() and swarmBoss.live or swarmBoss.net
    if a then
        a.adults = swarm.population()
        fn(a)
    end
end

local function say(text)
    inventory.notify(text)
end

--------------------------------------------------------------------------------
-- The body's formations (game/swarm.lua asks each fly's place, every tick)
--------------------------------------------------------------------------------

local function cloud(a, u)
    local t = a.time
    local around = u * 47.9 + t * (0.7 + u * 0.6)
    local el = math.asin(2 * ((u * 13.37) % 1) - 1)
    local r = 64 + 34 * ((u * 29.1) % 1) + 8 * sin(t * 3 + u * 40)
    local ce = cos(el)
    return a.x + ce * cos(around) * r, a.y + ce * sin(around) * r * 0.4, a.z + sin(el) * r * 0.6, 280
end

-- A fly from above, nose along +x: its slots spread over a body and two wings
local function giantShape(u)
    local k = (u * 97.13) % 1
    if u < 0.55 then
        local angle = k * TAU
        local r = sqrt((u / 0.55 * 11.7) % 1)
        return cos(angle) * r * 66, sin(angle) * r * 26
    end
    local side = u < 0.775 and -1 or 1
    local s, t = (u * 31.7) % 1, (u * 57.3) % 1
    if s + t > 1 then s, t = 1 - s, 1 - t end
    return -8 - s * 66 + t * 24, side * (20 + s * 78 + t * 54)
end

function swarmBoss.formation(u, strike)
    local a = swarmBoss.live
    if not a then return 0, 0, 40, 200 end
    local s = a.state
    if s == "lance" and strike then
        local spread = a.lobes[3].dead and 110 or 16 -- (PFL3 gone: they can't hold a line)
        return a.px + cos(u * 53) * spread, a.py + sin(u * 71) * spread, 16, a.phase == 3 and 520 or LANCE.speed
    elseif s == "engulf" then
        local angle = a.gapDir + ENGULF.gap + u * (TAU - 2 * ENGULF.gap)
        return a.ringX + cos(angle) * a.ringR, a.ringY + sin(angle) * a.ringR, 18, 560
    elseif s == "form" or s == "dive" then
        local sx, sy = giantShape(u)
        local c, si = cos(a.diveDir), sin(a.diveDir)
        return a.giantX + sx * c - sy * si, a.giantY + (sx * si + sy * c) * 0.8, 46, s == "dive" and 1600 or 520
    end
    return cloud(a, u)
end

--------------------------------------------------------------------------------
-- Its brain: senses in, outputs read, the pathways named as they fire
--------------------------------------------------------------------------------

local function fired(a, name, text, x)
    if (a.labelCd[name] or 0) > 0 then return end
    a.labelCd[name] = 1.5
    a.labels[#a.labels + 1] = { text = text, t = 0, x = x or (a.rng:random() - 0.5) * 80 }
end

local activityData, activityTex, brainMesh, brainShader, labelFont

-- This tick's activity into the texture the neurons are coloured from
local function uploadActivity(a)
    local activity = a.brain.activity
    for t = 0, flywire.N - 1 do
        activityData:setPixel(t, 0, clamp01(activity[t]), 0, 0, 1)
    end
    activityTex:replacePixels(activityData)
end

local function think(a, px, py, pvx, pvy, dist)
    local I, IN, R, OUT = a.brain.I, flywire.IN, a.brain.R, flywire.OUT
    -- looming, as for a fly: speed toward it, not size
    local approach = -(pvx * (px - a.x) + pvy * (py - a.y)) / (dist + 1e-6)
    local size = dist < 260 and clamp01(70 / dist) * clamp01(approach / (4 * U)) or 0
    size = max(size, a.startle)
    local bearing = wrap(atan2(py - a.y, px - a.x) - a.h)
    I[IN.loom], I[IN.loom + 1] = bearing <= 0 and size or 0, bearing > 0 and size or 0

    local heap = a.state == "feed" and swarm.heapAt(a.x, a.y) or nil
    local sugar = heap and clamp01(heap.sugar * 1.4) or 0
    I[IN.sugar], I[IN.sugar + 1] = sugar, sugar
    I[IN.mech], I[IN.mech + 1] = a.jolt * 0.6, a.jolt * 0.6
    local hunger = clamp01(1 - a.health / a.max_health)
    I[IN.orn], I[IN.orn + 1] = 0.15 * hunger, 0.15 * hunger

    local goal = bearing
    if a.goalHeap then goal = wrap(atan2(a.goalHeap.y - a.y, a.goalHeap.x - a.x) - a.h) end
    local drive = clamp01(abs(goal) / 1.2) * 0.9
    I[flywire.PFL_RIGHT], I[flywire.PFL_LEFT] = goal > 0 and drive or 0, goal < 0 and drive or 0

    flywire.step(a.brain, 0)

    local o = a.o
    o.turn = R[OUT.dna02 + 1] + 0.5 * R[OUT.dna01 + 1] - R[OUT.dna02] - 0.5 * R[OUT.dna01]
    o.gf = max(R[OUT.gf], R[OUT.gf + 1])
    o.mdn = (R[OUT.mdn] + R[OUT.mdn + 1]) / 2
    o.p9 = (R[OUT.p9] + R[OUT.p9 + 1]) / 2
    o.mn9 = max(R[OUT.mn9], R[OUT.mn9 + 1])
    o.oa = R[OUT.oa]
    a.rage = a.rage + (clamp01(o.oa / 0.3) * 0.6 + swarm.modeShare(4) * 0.4 - a.rage) * 0.1

    if o.gf > 0.3 then fired(a, "gf", "LPLC2>GF", -46) end
    if o.mdn > 0.25 then fired(a, "mdn", "JO>MDN", 40) end
    if o.mn9 > 0.15 then fired(a, "mn9", "SUGAR>MN9", 0) end
    if abs(o.turn) > 0.25 then fired(a, "turn", "PFL3>DNa02", 0) end
    if o.oa > 0.12 then fired(a, "oa", "OCTOPAMINE", -30) end
    uploadActivity(a)
end

--------------------------------------------------------------------------------
-- What it does
--------------------------------------------------------------------------------

local function setState(a, state, dur)
    a.state, a.t, a.dur = state, 0, dur
end

local function ease(v, target, rate, dt)
    return v + (target - v) * (1 - math.exp(-rate * dt))
end

-- Move toward (gx, gy) at `speed`, with its own connectome's heading stirred in
local function drift(a, dt, gx, gy, speed)
    local o = a.o
    a.h = a.h + (o.turn * 4.2 + (a.rng:random() - 0.5) * 1.6) * dt
    local walk = (1.5 + 3 * o.p9 - 6 * o.mdn) * U * 0.5
    local ux, uy = unit(gx - a.x, gy - a.y)
    local vx, vy = cos(a.h) * walk + ux * speed, sin(a.h) * walk + uy * speed
    a.x, a.y = a.x + vx * dt, a.y + vy * dt
    local hx, hy = a.x - a.homeX, a.y - a.homeY
    local d = sqrt(hx * hx + hy * hy)
    if d > LEASH then a.x, a.y = a.homeX + hx / d * LEASH, a.homeY + hy / d * LEASH end
end

local function spit(a, px, py)
    local x, y = a.x, a.y - a.z + 30
    local dx, dy = unit(px - x, py - 10 - y)
    if a.lobes[3].dead then -- (no aim)
        local err = (a.rng:random() - 0.5) * 0.9
        dx, dy = dx * cos(err) - dy * sin(err), dx * sin(err) + dy * cos(err)
    end
    bullet.new({ pos = vec2.new(x, y), dir = vec2.new(dx, dy), speed = EGG.speed, damage = EGG.damage,
        radius = EGG.radius, lifetime = EGG.life, neon = EGG_NEON, hostile = true })
    audio.playSoundAt("enemyGun", x, y, 0.1)
end

-- Pick a move, by how aroused it is and which game they're playing
local function nextMove(a, px, py, dist)
    local body = swarm.bodyCount(a.x, a.y, 200)
    if a.callCd <= 0 and body < BODY_WANT * 0.3 then
        a.callCd = CALL.every
        setState(a, "call", CALL.dur)
        return
    end
    if a.health < a.max_health * 0.7 and a.feedCd <= 0 and not a.lobes[1].dead then
        a.feedCd = FEED.every
        local heap = swarm.bestHeap(a.x, a.y, FEED.reach)
        if heap then
            a.goalHeap = heap
            setState(a, "seek", FEED.seek)
            return
        end
    end
    if dist > 620 then
        a.t = 0
        return
    end
    local lance, engulf, giant = 3 + 4 * a.rage, 2.2 + (a.phase == 2 and 1.5 or 0), 1.2 + 0.7 * a.phase
    if player.inCar then giant = 0 end
    local roll = a.rng:random() * (lance + engulf + giant)
    if roll < lance then
        swarm.assignStrike()
        a.px, a.py = px, py
        setState(a, "lance", LANCE.dur)
    elseif roll < lance + engulf then
        a.ringX, a.ringY, a.ringR = px, py, ENGULF.from
        a.gapDir = atan2(py - a.y, px - a.x)
        setState(a, "engulf", ENGULF.dur)
    else
        local ux, uy = unit(px - a.x, py - a.y)
        a.diveDir = atan2(uy, ux)
        a.giantX, a.giantY = px - ux * GIANT.reach, py - uy * GIANT.reach
        a.diveX, a.diveY = px + ux * GIANT.reach, py + uy * GIANT.reach
        a.struck = false
        setState(a, "form", GIANT.form)
    end
end

local function act(a, dt, px, py, dist)
    a.t = a.t + dt
    local k = min(1, a.t / max(1e-3, a.dur))
    local s = a.state
    a.ringK = 0
    if a.state ~= "sleep" and a.startleCd <= 0 and a.o.gf > 0.3 and s ~= "dive" and s ~= "feed" then
        -- the Giant Fiber's fired: off, its flies bursting from it
        a.startleCd = 6
        a.dartX, a.dartY = unit(a.x - px, a.y - py)
        swarm.startle(a.x, a.y, 200)
        setState(a, "startle", 0.35)
        camera.shake(3, 0.15)
        return
    end

    if s == "sleep" then
        a.x, a.y = ease(a.x, a.homeX, 1, dt), ease(a.y, a.homeY, 1, dt)
        if dist < SIGHT then
            local src = audio.playSoundAt("explosion", a.x, a.y, 0.05, 0.4)
            if src then src:setPitch(0.6) end
            setState(a, "hover", 1.2)
        end
    elseif s == "hover" then
        local standoff = 240
        local ux, uy = unit(a.x - px, a.y - py)
        drift(a, dt, px + ux * standoff, py + uy * standoff, 55)
        a.eggT = a.eggT - dt
        if a.eggT <= 0 and dist < EGG.range then
            a.eggT = (a.phase == 3 and 0.7 or EGG.every) * (1.2 - a.rage * 0.4)
            spit(a, px, py)
        end
        if dist > SIGHT * 1.4 then
            setState(a, "sleep", 0)
            swarm.releaseAll()
        elseif k >= 1 then
            a.dur = (1.6 + a.rng:random() * 1.4) * (1.1 - 0.5 * a.rage)
            a.t = 0
            nextMove(a, px, py, dist)
        end
    elseif s == "startle" then
        a.x, a.y = a.x + a.dartX * 420 * (1 - k) * dt * 2, a.y + a.dartY * 420 * (1 - k) * dt * 2
        if k >= 1 then setState(a, "hover", 1) end
    elseif s == "lance" then
        a.px, a.py = px, py
        drift(a, dt, a.x, a.y, 0)
        if k >= 1 then setState(a, "hover", 1.4) end
    elseif s == "engulf" then
        a.ringR = ENGULF.from + (ENGULF.to - ENGULF.from) * k * k
        a.ringK = 0.5 + 0.5 * k
        drift(a, dt, a.x, a.y, 0)
        if k >= 1 then
            if (px - a.ringX) ^ 2 + (py - a.ringY) ^ 2 < (ENGULF.to + 30) ^ 2 and not player.isDodging then
                local dx, dy = unit(px - a.ringX + 0.01, py - a.ringY)
                player.hurt(ENGULF.damage, vec2.new(dx, dy), "bite")
                camera.shake(5, 0.2)
            end
            setState(a, "hover", 1.3)
        end
    elseif s == "form" then
        a.ringK = 0.6 + 0.4 * math.abs(sin(a.time * 14))
        drift(a, dt, a.x, a.y, 0)
        if k >= 1 then setState(a, "dive", GIANT.dive) end
    elseif s == "dive" then
        local fromX, fromY = a.diveX - cos(a.diveDir) * 2 * GIANT.reach, a.diveY - sin(a.diveDir) * 2 * GIANT.reach
        a.giantX, a.giantY = fromX + (a.diveX - fromX) * k, fromY + (a.diveY - fromY) * k
        a.ringK = 1
        if not a.struck and not player.isDodging
            and (px - a.giantX) ^ 2 + (py - a.giantY) ^ 2 < GIANT.radius * GIANT.radius then
            a.struck = true
            local dir = vec2.new(cos(a.diveDir), sin(a.diveDir))
            player.hurt(GIANT.damage, dir, "blow")
            player.applyKnockback(dir, GIANT.knock * armor.knockback())
            camera.shake(7, 0.3)
        end
        if k >= 1 then setState(a, "hover", 1.6) end
    elseif s == "call" then
        drift(a, dt, a.x, a.y, 0)
        if a.t >= 0.3 and not a.called then
            a.called = true
            swarm.callAll(BODY_WANT)
            say("It calls the swarm")
        end
        if k >= 1 then
            a.called = nil
            setState(a, "hover", 0.8)
        end
    elseif s == "seek" then
        drift(a, dt, a.goalHeap.x, a.goalHeap.y, 150)
        if (a.goalHeap.x - a.x) ^ 2 + (a.goalHeap.y - a.y) ^ 2 < (a.goalHeap.r * 0.7) ^ 2 then
            a.feedHits = 0
            setState(a, "feed", FEED.dur)
        elseif k >= 1 then
            a.goalHeap = nil
            setState(a, "hover", 0.6)
        end
    elseif s == "feed" then
        -- MN9 does the eating: no sugar under it, or no MN9, and nothing comes of it
        if a.o.mn9 > 0.12 then a.health = min(a.max_health, a.health + FEED.heal * dt) end
        if a.feedHits >= FEED.breakAt or k >= 1 then
            a.goalHeap = nil
            setState(a, "hover", 0.8)
        end
    end
end

-- Silence what's been shot out (not in the physics step)
local function settleLobes(a, dt)
    for _, lobe in ipairs(a.lobes) do
        lobe.flash = max(0, lobe.flash - dt)
        if lobe.dying and not lobe.dead then
            lobe.dead, lobe.dying = true, nil
            flywire.silence(lobe.def.key)
            bosses.unregister(lobe.part)
            lobe.body:destroy()
            a.health = max(0, a.health - a.max_health * LOBE_WORTH)
            explosion.create(lobe.x or a.x, lobe.y or a.y, explosion.TYPES.BLAST)
            audio.playSoundAt("explosion", a.x, a.y, 0.08, 0.35)
            camera.shake(4, 0.2)
            say(lobe.def.say)
        end
    end
end

-- Keep what can be hit where it's drawn
local function placeParts(a)
    local cx, cy = a.x, a.y - a.z
    a.core.body:setPosition(cx, cy)
    local c, s = cos(a.spin), sin(a.spin)
    for _, lobe in ipairs(a.lobes) do
        local def = lobe.def
        lobe.x, lobe.y = cx + (def.dx * c + def.dz * s) * BRAIN_SCALE, cy + def.dy * BRAIN_SCALE
        if not lobe.dead then lobe.body:setPosition(lobe.x, lobe.y) end
    end
end

local function die(a, dt)
    a.dying = a.dying + dt
    a.z = max(20, a.z - dt * 30)
    if a.dying >= DEATH_TIME then
        explosion.create(a.x, a.y - a.z, explosion.TYPES.DEATH)
        audio.playSoundAt("explosion", a.x, a.y, 0.1, 0.7)
        camera.shake(9, 0.45)
        swarmBoss.despawnInst(a)
    end
end

local function addLights(a)
    local x0, y0, x1, y1 = regions.view(300)
    if a.x < x0 or a.x > x1 or a.y < y0 or a.y > y1 then return end
    local k = a.dying and 0.4 * love.math.random() or 0.35 + 0.35 * a.rage
    shadow.addTransientLight(a.x, a.y + 8, k, 190)
end

local function update(a, dt)
    a.time = a.time + dt
    a.flash = max(0, a.flash - dt)
    a.spin = a.spin + dt * 0.35
    a.jolt = max(0, a.jolt - dt * 1.2)
    a.startle = max(0, a.startle - dt * 2)
    a.startleCd, a.feedCd, a.callCd = a.startleCd - dt, a.feedCd - dt, a.callCd - dt
    for key, v in pairs(a.labelCd) do a.labelCd[key] = v - dt end
    for i = #a.labels, 1, -1 do
        local l = a.labels[i]
        l.t = l.t + dt
        if l.t > 1.2 then table.remove(a.labels, i) end
    end
    settleLobes(a, dt)

    if not a.dying and a.health <= 0 then
        a.dying, a.ringK = 0, 0
        for _, p in ipairs(a.parts) do bosses.unregister(p) end
        swarm.dieOff()
    end
    if a.dying then
        die(a, dt)
    elseif player and player.body then
        local px, py = player.body:getPosition()
        local pvx, pvy = player.body:getLinearVelocity()
        local dist = sqrt((px - a.x) ^ 2 + (py - a.y) ^ 2)
        a.brainT = a.brainT - dt
        if a.brainT <= 0 then
            a.brainT = 1 / BRAIN_HZ
            think(a, px, py, pvx, pvy, dist)
        end

        -- the game they're playing goes by how much of it is left
        local share = a.health / a.max_health
        local phase = #PHASES
        for i, def in ipairs(PHASES) do
            if share > def.above then
                phase = i
                break
            end
        end
        if phase ~= a.phase then
            a.phase = phase
            local def = PHASES[phase]
            swarm.setGame(def.game, def.V, def.C)
            if def.say then say(def.say) end
            a.callCd = 0
        end
        swarm.setBiteCap(a.state == "sleep" and 18 or PHASES[phase].cap)

        a.conscriptT = a.conscriptT - dt
        if a.conscriptT <= 0 and a.state ~= "sleep" then
            a.conscriptT = 0.5
            local have = swarm.bodyCount(a.x, a.y, 200)
            if have < BODY_WANT then swarm.conscript(a.x, a.y, 420, BODY_WANT - have) end
        end
        local _, close = swarm.bodyCount(a.x, a.y, 130)
        a.core.weak = 1 - (1 - SHIELD_MIN) * clamp01(close / SHIELD_FULL)

        act(a, dt, px, py, dist)
    end
    if not a.gone then
        a.z = ease(a.z, a.state == "feed" and 34 or HOVER + sin(a.time * 1.1) * 6, 3, dt)
        placeParts(a)
        addLights(a)
    end
end

--- Each frame, before the lighting upload
function swarmBoss.update(dt)
    if hosting() then
        local a = swarmBoss.live
        if a then update(a, dt) end
    else
        local a = swarmBoss.net
        if a then
            a.time = a.time + dt
            a.spin = a.spin + dt * 0.35
            a.brainT = a.brainT - dt
            if a.brainT <= 0 then
                a.brainT = 1 / 8
                flywire.step(a.brain, 0)
                uploadActivity(a)
            end
            addLights(a)
        end
    end
    swarm.update(dt)
end

function swarmBoss.load()
    swarmBoss.live, swarmBoss.net = nil, nil
end

--------------------------------------------------------------------------------
-- Network
--------------------------------------------------------------------------------

--- Host: what clients need to draw it, and its swarm (nil: there's none)
function swarmBoss.getNetworkData()
    local a = swarmBoss.live
    if not a then return nil end
    local inputs = {}
    for k = 0, flywire.NI - 1 do inputs[k + 1] = floor(a.brain.I[k] * 100) / 100 end
    local dead = 0
    for i, lobe in ipairs(a.lobes) do
        if lobe.dead then dead = dead + 2 ^ (i - 1) end
    end
    return { x = floor(a.x), y = floor(a.y), z = floor(a.z), h = a.health, m = a.max_health, st = a.state,
        f = a.flash, rk = a.ringK, rr = a.ringR, rx = a.ringX, ry = a.ringY, gd = a.gapDir, gx = a.giantX, gy = a.giantY,
        dd = a.diveDir, dx = a.diveX, dy = a.diveY, i = inputs, d = dead, sw = swarm.getNetworkData() }
end

--- Client: as the host sent it (nil: there's none)
function swarmBoss.applyNetworkData(d)
    if not d then
        swarmBoss.net = nil
        swarm.applyNetworkData(nil)
        return
    end
    flywire.ensure()
    ensureBrainArt()
    local a = swarmBoss.net
    if not a then
        a = { time = 0, spin = 0, brainT = 0, ringK = 0, labels = {}, rage = 0, brain = flywire.pool(1, true), lobes = {} }
        for _, def in ipairs(LOBES) do a.lobes[#a.lobes + 1] = { def = def, flash = 0 } end
        swarmBoss.net = a
    end
    a.x, a.y, a.z, a.health, a.max_health, a.state, a.flash = d.x, d.y, d.z, d.h, d.m, d.st, d.f or 0
    a.ringK, a.ringR, a.ringX, a.ringY, a.gapDir = d.rk or 0, d.rr or 0, d.rx or 0, d.ry or 0, d.gd or 0
    a.giantX, a.giantY, a.diveDir, a.diveX, a.diveY = d.gx, d.gy, d.dd, d.dx, d.dy
    for k, v in ipairs(d.i or {}) do a.brain.I[k - 1] = v end
    for i, lobe in ipairs(a.lobes) do
        local dead = floor((d.d or 0) / 2 ^ (i - 1)) % 2 == 1
        if dead and not lobe.dead then flywire.silence(lobe.def.key) end
        lobe.dead = dead
    end
    swarm.applyNetworkData(d.sw)
end

--------------------------------------------------------------------------------
-- Drawing (lib/graphics/renderer.lua hands each piece to swarmBoss.drawPiece)
--------------------------------------------------------------------------------

local BRAIN_SHADER = [[
    varying float shade;

    #ifdef VERTEX
    uniform vec2 center;
    uniform float scale;
    uniform float spin;
    vec4 position(mat4 transform_projection, vec4 vertex_position) {
        float c = cos(spin), s = sin(spin);
        vec3 p = vertex_position.xyz;
        vec2 q = vec2(p.x * c + p.z * s, p.y);
        shade = 0.55 + 0.45 * clamp(0.5 - (p.z * c - p.x * s) * 1.2, 0.0, 1.0);
        return transform_projection * vec4(center + q * scale, 0.0, 1.0);
    }
    #endif

    #ifdef PIXEL
    uniform float flash;
    uniform float awake;
    // activity to colour, dark to red to orange to pale yellow (brainview.js)
    vec3 ramp(float a) {
        if (a < 0.35) return mix(vec3(0.12, 0.04, 0.3), vec3(0.78, 0.16, 0.35), a / 0.35);
        if (a < 0.7) return mix(vec3(0.78, 0.16, 0.35), vec3(1.0, 0.52, 0.1), (a - 0.35) / 0.35);
        return mix(vec3(1.0, 0.52, 0.1), vec3(1.0, 0.95, 0.6), (a - 0.7) / 0.3);
    }
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        float a = tc.y < 0.5 ? Texel(tex, vec2(tc.x, 0.5)).r : 0.0;
        vec3 rgb = ramp(a) * (0.35 + 1.5 * a) + vec3(0.1, 0.05, 0.12);
        rgb = mix(rgb * shade * awake, vec3(1.0), flash);
        return vec4(rgb, 1.0);
    }
    #endif
]]

--- The brain's mesh (each neuron a point) and the texture of what fires
ensureBrainArt = function()
    if brainMesh then return end
    local N = flywire.N
    activityData = love.image.newImageData(N, 1)
    activityTex = love.graphics.newImage(activityData)
    activityTex:setFilter("nearest", "nearest")
    local vertices = {}
    for i, p in ipairs(flywire.cloud) do
        local g = p[4]
        -- u: its cell type in the activity texture; v: 1 = not one the graph has
        vertices[i] = { p[1], p[2], p[3] * 1.6, (max(0, g) + 0.5) / N, g < 0 and 1 or 0 }
    end
    brainMesh = love.graphics.newMesh({ { "VertexPosition", "float", 3 }, { "VertexTexCoord", "float", 2 } }, vertices,
        "points", "static")
    brainMesh:setTexture(activityTex)
    brainShader = love.graphics.newShader(BRAIN_SHADER)
    labelFont = love.graphics.newFont("gfx/menu/Px437_IBM_VGA_8x16.ttf", 8)
    labelFont:setFilter("nearest", "nearest")
end

local function drawGround(a)
    love.graphics.setShader()
    love.graphics.setBlendMode("multiply", "premultiplied")
    local lift = clamp01(a.z / 120)
    love.graphics.setColor(0.68 + 0.14 * lift, 0.68 + 0.14 * lift, 0.7 + 0.14 * lift, 1)
    love.graphics.ellipse("fill", a.x, a.y + 6, 92, 38)
    love.graphics.setBlendMode("add", "premultiplied")
    love.graphics.setLineWidth(2)
    local k = a.ringK or 0
    if a.state == "engulf" and k > 0 then
        love.graphics.setColor(1 * k, 0.15 * k, 0.25 * k, 0)
        love.graphics.circle("fill", a.ringX, a.ringY, a.ringR)
        love.graphics.setColor(1 * k, 0.3 * k, 0.35 * k, 0)
        love.graphics.arc("line", "open", a.ringX, a.ringY, a.ringR, a.gapDir + ENGULF.gap,
            a.gapDir + TAU - ENGULF.gap, 48)
        love.graphics.setColor(0.3 * k, 1 * k, 0.5 * k, 0)
        love.graphics.arc("line", "open", a.ringX, a.ringY, a.ringR, a.gapDir - ENGULF.gap, a.gapDir + ENGULF.gap, 12)
    elseif (a.state == "form" or a.state == "dive") and a.diveX then
        love.graphics.setLineWidth(GIANT.radius * 2)
        love.graphics.setColor(0.5 * k, 0.08 * k, 0.12 * k, 0)
        local fromX, fromY = a.diveX - cos(a.diveDir) * 2 * GIANT.reach, a.diveY - sin(a.diveDir) * 2 * GIANT.reach
        love.graphics.line(fromX, fromY, a.diveX, a.diveY)
    end
    love.graphics.setLineWidth(1)
end

local function drawBrain(a)
    local cx, cy = a.x, a.y - a.z
    local alive = a.dying and clamp01(1 - a.dying / DEATH_TIME) or 1
    love.graphics.setShader()
    love.graphics.setBlendMode("add", "premultiplied")
    -- a sickly halo, brighter the more it's aroused
    local glow = (0.14 + 0.32 * a.rage) * alive
    love.graphics.setColor(0.9 * glow, 0.3 * glow, 0.18 * glow, 0)
    love.graphics.draw(regions.glow, cx - 140, cy - 105, 0, 280 / 64, 210 / 64)

    -- the strongest wiring where it's firing
    local activity = a.brain.activity
    local c, s = cos(a.spin), sin(a.spin)
    local P = flywire.positions
    local drawn = 0
    love.graphics.setLineWidth(1)
    for _, wire in ipairs(flywire.wires) do
        local act = activity[wire[1]]
        if act > 0.25 then
            local p, q = P[wire[1]], P[wire[2]]
            local k = min(1, act) * alive * 0.5
            local r, g, b = 1, 0.5, 0.2
            if wire[3] < 0 then r, g, b = 0.3, 0.55, 1 end -- inhibitory
            love.graphics.setColor(r * k, g * k, b * k, 0)
            love.graphics.line(cx + (p[1] * c + p[3] * 1.6 * s) * BRAIN_SCALE, cy + p[2] * BRAIN_SCALE,
                cx + (q[1] * c + q[3] * 1.6 * s) * BRAIN_SCALE, cy + q[2] * BRAIN_SCALE)
            drawn = drawn + 1
            if drawn >= 70 then break end
        end
    end

    -- every neuron, coloured by its cell type's activity; they light the street (alpha 1)
    love.graphics.setShader(brainShader)
    brainShader:send("center", { cx, cy })
    brainShader:send("scale", BRAIN_SCALE)
    brainShader:send("spin", a.spin)
    brainShader:send("flash", a.flash > 0 and 0.75 or 0)
    brainShader:send("awake", alive * (a.state == "sleep" and 0.55 or 1))
    love.graphics.setColor(1, 1, 1, 1)
    local size = love.graphics.getPointSize()
    love.graphics.setPointSize(max(1, 1.6 * camera.zoom))
    love.graphics.draw(brainMesh)
    love.graphics.setPointSize(size)

    -- the lobes that can be shot out, and the pathways firing
    love.graphics.setShader()
    for _, lobe in ipairs(a.lobes) do
        local def = lobe.def
        local x = cx + (def.dx * c + def.dz * s) * BRAIN_SCALE
        local y = cy + def.dy * BRAIN_SCALE
        if lobe.dead then
            love.graphics.setColor(0.08, 0.08, 0.08, 0)
            love.graphics.circle("line", x, y, LOBE_R * 0.6)
        else
            local col = def.color
            local k = (0.5 + 0.5 * sin(a.time * 5 + def.dx * 9)) * alive
            if (lobe.flash or 0) > 0 then k = 1.6 end
            love.graphics.setColor(col[1] * k * 0.6, col[2] * k * 0.6, col[3] * k * 0.6, 0)
            love.graphics.draw(regions.glow, x - 22, y - 22, 0, 44 / 64, 44 / 64)
            love.graphics.setColor(col[1] * k, col[2] * k, col[3] * k, 0)
            love.graphics.circle("line", x, y, LOBE_R)
        end
    end
    if labelFont and #a.labels > 0 then
        local font = love.graphics.getFont()
        love.graphics.setFont(labelFont)
        love.graphics.setBlendMode("add", "premultiplied")
        for _, l in ipairs(a.labels) do
            local k = 1 - l.t / 1.2
            love.graphics.setColor(1 * k, 0.9 * k, 0.55 * k, 0)
            love.graphics.print(l.text, cx + l.x - labelFont:getWidth(l.text) / 2, cy - 70 - l.t * 22)
        end
        love.graphics.setFont(font)
    end
end

--- One piece of it, from the sorted list
function swarmBoss.drawPiece(d)
    local a = d.boss
    local keep = love.graphics.getShader()
    local mode, alphaMode = love.graphics.getBlendMode()
    if d.piece == "ground" then
        drawGround(a)
    else
        drawBrain(a)
    end
    love.graphics.setBlendMode(mode, alphaMode)
    love.graphics.setShader(keep)
    love.graphics.setColor(1, 1, 1, 1)
end

--- Into the sorted list while it's on screen
function swarmBoss.populate()
    local a = hosting() and swarmBoss.live or swarmBoss.net
    if a and a.x then
        local x0, y0, x1, y1 = regions.view(220)
        if a.x > x0 and a.x < x1 and a.y > y0 and a.y < y1 then
            dynamic_draw_list[#dynamic_draw_list + 1] = { sort_y = -1e9, draw_type = "swarmBoss", boss = a, piece = "ground" }
            dynamic_draw_list[#dynamic_draw_list + 1] = { sort_y = a.y + SORT, draw_type = "swarmBoss", boss = a, piece = "brain" }
        end
    end
end

return swarmBoss
