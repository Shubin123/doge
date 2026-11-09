--[[
  Enemies' weapons (game/enemy.lua fires them on its moves' hit frames): one
  of each of yours, and attacks of their own. Damage is in player HP:
  player.maxHealth is 1000, ten hearts of 100.

  Kinds:
    bullet     hostile bullets (bullet.new { hostile = true }), neon tracers
               in the weapon's colours that hurt you and stop at walls: the
               pistol, SMG, shotgun, rifle, bow, orb, and the rocket and
               fireball, which burst where they land (`burst`: an explosion
               or a flare of fire, hurting you within its radius and
               knocking at what stands there)
    tesla      a bolt jumps from it to you, when you're within reach with
               nothing between; otherwise it strikes the ground short of you
    laser      beams that first charge (a thin flickering line showing where
               they'll burn, turning after you) and then burn for a moment,
               sweeping slowly after you; walls stop them, and you burn in
               them. `beams` of them fanned across `fan` is the multi-laser
    blackhole  a small black hole thrown to where you stand (blackholeGun.lua's
               hostile kind): it pulls you in and hurts at its heart

  Each look's primary weapon and special come from LOADOUT, by its index
  (enemyWeapons.pick). Lasers and bolts are worked out where the world runs
  (host, single player) and sent to clients to draw.

    range:    how far off it likes to fight from (px)
    reach:    how far it can hurt you from (px); for bullets their flight
    cooldown: seconds between trigger pulls (plus up to 1 s of jitter)
    shots, interval, pellets, spread, speed, damage, radius, lifetime, neon:
              a bullet weapon's rounds (see bullet.new)
]]
local enemyWeapons = {}

local W = {
    pistol = { kind = "bullet", range = 280, shots = 1, pellets = 1, spread = math.rad(4),
        speed = 560, damage = 20, radius = 3, lifetime = 1.4, cooldown = 2.2,
        neon = { core = { 1.0, 0.2, 0.12 }, halo = { 1.0, 0.0, 0.08 }, radius = 10 } },
    smg = { kind = "bullet", range = 230, shots = 3, interval = 0.1, pellets = 1, spread = math.rad(7),
        speed = 500, damage = 12, radius = 3, lifetime = 1.4, cooldown = 2.8,
        neon = { core = { 1.0, 0.85, 0.25 }, halo = { 1.0, 0.2, 0.0 }, radius = 9 } },
    shotgun = { kind = "bullet", range = 150, shots = 1, pellets = 5, spread = math.rad(30),
        speed = 430, damage = 8, radius = 2, lifetime = 0.8, cooldown = 3.0,
        neon = { core = { 1.0, 0.4, 0.6 }, halo = { 0.9, 0.0, 0.35 }, radius = 8 } },
    orb = { kind = "bullet", range = 320, shots = 1, pellets = 1, spread = 0,
        speed = 220, damage = 45, radius = 7, lifetime = 2.6, cooldown = 3.6,
        neon = { core = { 1.0, 0.65, 1.0 }, halo = { 0.6, 0.0, 1.0 }, radius = 22 } },
    -- quick and hard-hitting, from far off
    rifle = { kind = "bullet", range = 420, shots = 1, pellets = 1, spread = math.rad(1.5),
        speed = 950, damage = 34, radius = 2, lifetime = 0.85, cooldown = 3.2,
        neon = { core = { 0.85, 1.0, 1.0 }, halo = { 0.1, 0.6, 1.0 }, radius = 8 } },
    -- an arrow: thin and pale, slower
    bow = { kind = "bullet", range = 340, shots = 1, pellets = 1, spread = math.rad(2),
        speed = 480, damage = 26, radius = 2, lifetime = 1.5, cooldown = 2.6,
        neon = { core = { 1.0, 0.95, 0.8 }, halo = { 0.8, 0.5, 0.1 }, radius = 6 } },
    fireball = { kind = "bullet", range = 260, shots = 1, pellets = 1, spread = math.rad(3),
        speed = 280, damage = 30, radius = 6, lifetime = 1.6, cooldown = 3.2,
        neon = { core = { 1.0, 0.85, 0.3 }, halo = { 1.0, 0.3, 0.0 }, radius = 24 },
        burst = { radius = 60, damage = 15, look = "fire" } },
    rocket = { kind = "bullet", range = 360, shots = 1, pellets = 1, spread = math.rad(2),
        speed = 330, damage = 45, radius = 5, lifetime = 1.4, cooldown = 4.2,
        neon = { core = { 1.0, 1.0, 0.85 }, halo = { 1.0, 0.45, 0.05 }, radius = 16 },
        burst = { radius = 90, damage = 40, look = "rocket" } },
    tesla = { kind = "tesla", range = 200, reach = 260, damage = 28, cooldown = 2.6,
        color = { 0.55, 0.85, 1.0 } },
    laser = { kind = "laser", range = 360, reach = 560, beams = 1, fan = 0, dps = 240, burn = 0.45,
        cooldown = 9, color = { 1.0, 0.15, 0.2 } },
    multilaser = { kind = "laser", range = 320, reach = 480, beams = 5, fan = math.rad(64), dps = 150,
        burn = 0.4, cooldown = 11, color = { 1.0, 0.2, 0.9 } },
    blackhole = { kind = "blackhole", range = 340, reach = 440, cooldown = 12 },
}
for name, w in pairs(W) do
    w.name = name
    if w.kind == "bullet" then w.reach = w.speed * w.lifetime * 0.9 end
end
enemyWeapons.WEAPONS = W

-- What each look carries: its primary weapon by index, and a special it
-- uses now and then (enemy.lua's CASTS move)
enemyWeapons.LOADOUT = {
    watchman = { primary = { "pistol", "smg", "rifle" }, special = { "laser", "blackhole" } },
    mech = { primary = { "shotgun", "rocket", "smg" }, special = { "multilaser" } },
    steve = { primary = { "bow", "fireball" } },
    animated_special = { primary = { "tesla", "orb" }, special = { "blackhole", "multilaser" } },
    gun = { primary = { "rifle", "smg", "pistol" }, special = { "laser" } },
}

--- The weapons an enemy of `look` with `index` carries: primary, special (or nil).
function enemyWeapons.pick(look, index)
    local l = enemyWeapons.LOADOUT[look] or enemyWeapons.LOADOUT.watchman
    local primary = W[l.primary[math.floor(index / 7) % #l.primary + 1]]
    local special = l.special and W[l.special[math.floor(index / 14) % #l.special + 1]]
    return primary, special
end

local beams, bolts, bursts, sparks = {}, {}, {}, {}
local casting = {} -- enemy -> its black hole, thrown at its move's hit (enemyWeapons.ready counts them)
enemyWeapons.beams, enemyWeapons.bolts = beams, bolts

local BEAM_WIDTH = 14  -- px either side of a beam's line that burns you
local MAX_BEAMS = 6    -- beams charging or burning at once, all told, and black holes
local MAX_HOLES = 2    -- open: a crowd takes turns (and each hole is a lensing pass)
local CHARGE_TURN = 2.2 -- rad/s a charging beam turns after you...
local BURN_TURN = 0.45  -- ...and a burning one
local MUZZLE = 26       -- px from the enemy's middle its beams and bolts leave

function enemyWeapons.load()
    for e in pairs(casting) do casting[e] = nil end
    for i = #sparks, 1, -1 do sparks[i] = nil end
    for i = #beams, 1, -1 do beams[i] = nil end
    for i = #bolts, 1, -1 do bolts[i] = nil end
    for i = #bursts, 1, -1 do bursts[i] = nil end
end

local function angleTo(ex, ey)
    local px, py = player.body:getPosition()
    return math.atan2(py - ey, px - ex)
end

local function turnToward(a, target, step)
    local d = (target - a + math.pi) % (2 * math.pi) - math.pi
    return a + math.max(-step, math.min(step, d))
end

-- Where a line from (x, y) at angle `a` meets a wall within `reach`
local function wallAlong(x, y, a, reach)
    local x2, y2 = x + math.cos(a) * reach, y + math.sin(a) * reach
    local hx, hy = x2, y2
    world:rayCast(x, y, x2, y2, function(f, fx, fy, _, _, fraction)
        if not f:isSensor() and f:getBody():getType() == "static" then
            hx, hy = fx, fy
            return fraction
        end
        return -1
    end)
    return hx, hy
end

-- Whether nothing static stands between (x1, y1) and (x2, y2)
local function clear(x1, y1, x2, y2)
    local ok = true
    world:rayCast(x1, y1, x2, y2, function(f)
        if not f:isSensor() and f:getBody():getType() == "static" then
            ok = false
            return 0
        end
        return -1
    end)
    return ok
end

--- Whether another enemy can use special `w` now: a crowd's lasers and
--- black holes take turns (MAX_BEAMS, MAX_HOLES at once).
function enemyWeapons.ready(w)
    if w.kind == "laser" then return #beams + w.beams <= MAX_BEAMS end
    if w.kind == "blackhole" then
        local n = 0
        for _, h in ipairs(blackholeGun.holes) do
            if h.hostile then n = n + 1 end
        end
        for e in pairs(casting) do
            if e.dead or not (e.attack and e.attack.weapon == w) then
                casting[e] = nil -- thrown, or never will be
            else
                n = n + 1
            end
        end
        return n < MAX_HOLES
    end
    return true
end

--- Enemy `e` starts the move that fires special `w`: a laser's beams start
--- to charge (they burn when enemyWeapons.fire comes, `charge` seconds on);
--- a black hole is spoken for.
function enemyWeapons.charge(e, w, charge)
    if w.kind == "blackhole" then
        casting[e] = true
        return
    end
    local ex, ey = e.body:getPosition()
    local aim = angleTo(ex, ey)
    for i = 1, w.beams do
        local off = w.beams > 1 and (i - 1) / (w.beams - 1) - 0.5 or 0
        beams[#beams + 1] = {
            owner = e, w = w, offset = off * w.fan, aim = aim,
            charging = true, t = 0, charge = charge, tick = 0,
            x1 = ex, y1 = ey, x2 = ex, y2 = ey,
        }
    end
end

--- Enemy `e` fires weapon `w` (anything but bullets: enemy.lua shoots those).
function enemyWeapons.fire(e, w)
    local ex, ey = e.body:getPosition()
    local px, py = player.body:getPosition()
    local a = math.atan2(py - ey, px - ex)
    local mx, my = ex + math.cos(a) * MUZZLE, ey + math.sin(a) * MUZZLE
    if w.kind == "laser" then
        local any = false
        for _, b in ipairs(beams) do
            if b.owner == e and b.charging then
                b.charging, b.t, any = false, 0, true
            end
        end
        if not any then
            -- (fired without charging first: burn at once)
            enemyWeapons.charge(e, w, 0)
            return enemyWeapons.fire(e, w)
        end
        audio.playSoundAt("fire", ex, ey, 0.25)
    elseif w.kind == "tesla" then
        local d = math.sqrt((px - ex) ^ 2 + (py - ey) ^ 2)
        local tx, ty
        if d <= w.reach and clear(mx, my, px, py) then
            tx, ty = px, py
            player.hurt(w.damage, vec2.new(math.cos(a), math.sin(a)), "energy")
        else
            -- short of you: to the first wall, or as far as it reaches
            tx, ty = wallAlong(mx, my, a, math.min(d, w.reach))
        end
        bolts[#bolts + 1] = { x1 = mx, y1 = my, x2 = tx, y2 = ty, t = 0, life = 0.2, color = w.color, seed = 0 }
        local src = audio.playSoundAt("gun4", ex, ey, 0.2)
        if src then src:setPitch(1.6) end
    elseif w.kind == "blackhole" then
        casting[e] = nil
        local d = math.sqrt((px - ex) ^ 2 + (py - ey) ^ 2)
        blackholeGun.new({ from = vec2.new(ex, ey), dir = vec2.new(math.cos(a), math.sin(a)),
            muzzle = MUZZLE, range = math.min(d, w.reach), hostile = true })
        local src = audio.playSoundAt("explosion", ex, ey, 0.04)
        if src then src:setPitch(0.7) end
    end
end

--- `n` sparks flying from (x, y) along (dx, dy), within `cone` radians of
--- it, in `colours`: a blow landing, a fireball's flare. Drawn in one batch
--- with the beams (enemyWeapons.draw) rather than as particles in the
--- sorted list, where among a crowd each splits the characters' draws.
function enemyWeapons.sparks(x, y, dx, dy, n, cone, colours, speed, life)
    local base = math.atan2(dy, dx)
    for _ = 1, n do
        local a = base + (math.random() - 0.5) * 2 * cone
        local v = speed * (0.4 + math.random() * 0.6)
        local c = colours[math.random(#colours)]
        sparks[#sparks + 1] = { x = x, y = y, vx = math.cos(a) * v, vy = math.sin(a) * v,
            t = 0, life = life * (0.7 + math.random() * 0.3), c = c, size = 1 + math.random() * 2 }
    end
end

--- A bullet with a burst (a rocket, a fireball) landed at (x, y): it goes
--- off in enemyWeapons.update, out of the physics step.
function enemyWeapons.burst(inst, x, y)
    if inst.burst then
        bursts[#bursts + 1] = { burst = inst.burst, x = x, y = y }
        inst.burst = nil -- once
    end
end

-- Distance from (px, py) to the segment (x1, y1)-(x2, y2), and how far along it
local function toSegment(px, py, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local len2 = dx * dx + dy * dy
    local k = len2 > 0 and math.max(0, math.min(1, ((px - x1) * dx + (py - y1) * dy) / len2)) or 0
    local cx, cy = x1 + dx * k, y1 + dy * k
    return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
end

--- Every frame where the world runs (enemy.update), before the lighting
--- upload: beams charge, turn and burn, bolts fade, bursts go off.
function enemyWeapons.update(dt)
    local px, py = player.body:getPosition()
    for i = #beams, 1, -1 do
        local b = beams[i]
        local e = b.owner
        b.t = b.t + dt
        local gone = e.dead or not e.body or e.body:isDestroyed()
            or (b.charging and b.t > b.charge + 0.3) -- its move never fired
            or (not b.charging and b.t >= b.w.burn)
        if gone then
            table.remove(beams, i)
        else
            local ex, ey = e.body:getPosition()
            b.aim = turnToward(b.aim, angleTo(ex, ey), (b.charging and CHARGE_TURN or BURN_TURN) * dt)
            local a = b.aim + b.offset
            b.x1, b.y1 = ex + math.cos(a) * MUZZLE, ey + math.sin(a) * MUZZLE
            b.x2, b.y2 = wallAlong(b.x1, b.y1, a, b.w.reach)
            if not b.charging then
                -- you burn in it; hurt in ticks, so the shake stays small
                if toSegment(px, py, b.x1, b.y1, b.x2, b.y2) < BEAM_WIDTH then
                    b.tick = b.tick + b.w.dps * dt
                end
                if b.tick >= 20 then
                    player.hurt(b.tick, nil, "energy")
                    b.tick = 0
                end
                local k = 1 - b.t / b.w.burn
                shadow.addTransientLight((b.x1 + b.x2) / 2, (b.y1 + b.y2) / 2, 0.6 * k, 160)
            end
        end
    end

    for i = #bolts, 1, -1 do
        local b = bolts[i]
        b.t = b.t + dt
        if b.t >= b.life then
            table.remove(bolts, i)
        else
            shadow.addTransientLight(b.x2, b.y2, 0.8 * (1 - b.t / b.life), 120)
        end
    end

    for i = #sparks, 1, -1 do
        local s = sparks[i]
        s.t = s.t + dt
        if s.t >= s.life then
            sparks[i] = sparks[#sparks]
            sparks[#sparks] = nil
        else
            s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
            s.vx, s.vy = s.vx * 0.94, s.vy * 0.94 + 50 * dt
        end
    end

    for i = #bursts, 1, -1 do
        local s = bursts[i]
        bursts[i] = nil
        local r = s.burst.radius
        if s.burst.look == "rocket" then
            explosion.create(s.x, s.y, explosion.TYPES.BLAST)
            audio.playSoundAt("explosion", s.x, s.y, 0.35)
            destruction.blast(s.x, s.y, r, destruction.BLAST)
        else
            enemyWeapons.sparks(s.x, s.y, 0, -1, 18, math.pi,
                { { 1, 0.9, 0.4 }, { 1, 0.45, 0.1 }, { 0.9, 0.2, 0.0 } }, 200, 0.4)
            shadow.addTransientLight(s.x, s.y, 1.0, r * 2.5)
            audio.playSoundAt("fire", s.x, s.y, 0.3)
        end
        local d = math.sqrt((px - s.x) ^ 2 + (py - s.y) ^ 2)
        if d < r then
            local k = 1 - d / r
            player.hurt(s.burst.damage * (0.4 + 0.6 * k),
                d > 1 and vec2.new((px - s.x) / d, (py - s.y) / d) or nil, "blast")
        end
    end
end

-- The jagged line of a bolt, made again every few hundredths of a second
local function boltPoints(b)
    local seg = math.max(3, math.floor(math.sqrt((b.x2 - b.x1) ^ 2 + (b.y2 - b.y1) ^ 2) / 18))
    local pts = { b.x1, b.y1 }
    local nx, ny = -(b.y2 - b.y1), b.x2 - b.x1
    local n = math.sqrt(nx * nx + ny * ny)
    if n > 0 then nx, ny = nx / n, ny / n end
    local rng = love.math.newRandomGenerator(math.floor(b.t * 30) + 1 + math.floor(b.x1 + b.y2))
    for i = 1, seg - 1 do
        local k = i / seg
        local j = (rng:random() - 0.5) * 22 * math.sin(k * math.pi)
        pts[#pts + 1] = b.x1 + (b.x2 - b.x1) * k + nx * j
        pts[#pts + 1] = b.y1 + (b.y2 - b.y1) * k + ny * j
    end
    pts[#pts + 1], pts[#pts + 2] = b.x2, b.y2
    return pts
end

--- In world space, after the sorted sprites (draw.lua): beams, bolts and
--- sparks, glowing.
function enemyWeapons.draw()
    if #beams == 0 and #bolts == 0 and #sparks == 0 then return end
    local shader = love.graphics.getShader()
    local mode, alphaMode = love.graphics.getBlendMode()
    love.graphics.setShader()
    love.graphics.setBlendMode("add")
    local time = love.timer.getTime()
    for _, b in ipairs(beams) do
        local c = b.w.color
        if b.charging then
            -- where it'll burn: thin, flickering, brighter as it's about to
            local k = math.min(1, b.t / math.max(0.05, b.charge))
            love.graphics.setLineWidth(1 + k)
            love.graphics.setColor(c[1], c[2], c[3], (0.25 + 0.45 * k) * (0.75 + 0.25 * math.sin(time * 40)))
            love.graphics.line(b.x1, b.y1, b.x2, b.y2)
        else
            local k = 1 - b.t / b.w.burn
            love.graphics.setLineWidth(16 * k + 4)
            love.graphics.setColor(c[1], c[2], c[3], 0.35 * k)
            love.graphics.line(b.x1, b.y1, b.x2, b.y2)
            love.graphics.setLineWidth(6 * k + 2)
            love.graphics.setColor(c[1], c[2], c[3], 0.8 * k)
            love.graphics.line(b.x1, b.y1, b.x2, b.y2)
            love.graphics.setLineWidth(2)
            love.graphics.setColor(1, 1, 1, k)
            love.graphics.line(b.x1, b.y1, b.x2, b.y2)
            love.graphics.setColor(c[1], c[2], c[3], 0.6 * k)
            love.graphics.circle("fill", b.x2, b.y2, 7 + 6 * k)
        end
    end
    for _, b in ipairs(bolts) do
        local k = 1 - b.t / b.life
        local pts = boltPoints(b)
        local c = b.color
        love.graphics.setLineWidth(6)
        love.graphics.setColor(c[1], c[2], c[3], 0.35 * k)
        love.graphics.line(pts)
        love.graphics.setLineWidth(2)
        love.graphics.setColor(0.9, 0.97, 1, k)
        love.graphics.line(pts)
        love.graphics.setColor(c[1], c[2], c[3], 0.5 * k)
        love.graphics.circle("fill", b.x2, b.y2, 9)
    end
    for _, s in ipairs(sparks) do
        local k = 1 - s.t / s.life
        love.graphics.setColor(s.c[1], s.c[2], s.c[3], k)
        love.graphics.rectangle("fill", s.x - s.size / 2, s.y - s.size / 2, s.size, s.size)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode(mode, alphaMode)
    love.graphics.setShader(shader)
end

--- Host: the beams and bolts to draw, for clients (empty rather than nil,
--- so a snapshot's update clears the last ones)...
function enemyWeapons.getNetworkData()
    local list = {}
    local function r(v) return math.floor(v + 0.5) end
    for _, b in ipairs(beams) do
        list[#list + 1] = { k = "beam", w = b.w.name, c = b.charging and 1 or 0, t = b.t, ch = b.charge,
            x1 = r(b.x1), y1 = r(b.y1), x2 = r(b.x2), y2 = r(b.y2) }
    end
    for _, b in ipairs(bolts) do
        list[#list + 1] = { k = "bolt", t = b.t, x1 = r(b.x1), y1 = r(b.y1), x2 = r(b.x2), y2 = r(b.y2) }
    end
    return list
end

--- ...and clients draw them where the host has them (until the next snapshot).
function enemyWeapons.applyNetworkData(list)
    for i = #beams, 1, -1 do beams[i] = nil end
    for i = #bolts, 1, -1 do bolts[i] = nil end
    for _, n in ipairs(list or {}) do
        if n.k == "beam" and W[n.w] then
            beams[#beams + 1] = { w = W[n.w], charging = n.c == 1, t = n.t or 0, charge = n.ch or 0.5,
                x1 = n.x1, y1 = n.y1, x2 = n.x2, y2 = n.y2 }
        elseif n.k == "bolt" then
            bolts[#bolts + 1] = { t = n.t or 0, life = 0.2, color = W.tesla.color,
                x1 = n.x1, y1 = n.y1, x2 = n.x2, y2 = n.y2 }
        end
    end
end

return enemyWeapons
