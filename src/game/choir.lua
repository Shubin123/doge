--[[
  The Sanctum's boss (game/bosses.lua's "choir"): three of the old orders of
  angels, keeping its lair before the cathedral (gfx/EnemiesSpriteSheets):
    the Seraph  an eye in flaming wings: spirals of holy fire (hymn), and
                fans of it aimed at you (gaze)
    the Ophan   a wheel with an eye: rings of light (halo); a well opened
                under you that drags you to its heart and burns you there
                (fx Gravity); and its ward (fx Electric Aura) over one of the
                others, which takes a quarter of what lands while it lasts
    the Cherub  a beetle-bodied guardian on two thrusters: it dips, a line on
                the street shows its way, and it charges through you (a roll
                goes under it); and it spits
  They wake when you come within SIGHT of the lair and hover round you a
  third of a circle apart, circling as they go; past GIVE_UP they go home.

  The rite: one brought down falls to the street in a burst
  (enemy-explosion.png) and lies in a ring of holy light (fx Holy Light
  Aura), rising RISE.time s later with RISE.health of its health (fx Regen),
  as long as either of the others still stands. While one's down the others
  grieve: GRIEF quicker at everything. Bring all three down together and the
  Choir is silenced (bosses.defeated).

  Their parts (bosses.lua) are kinematic sensors where each is drawn, up off
  the street (the ward makes one's part weak); what they shoot are hostile
  bullets (bullet.lua), so a mirror turns them back. Their art is drawn at
  PX world px a texel, facing you; each sorts by the street under it.
]]
local choir = {}

choir.NAME = "THE CHOIR"
choir.live = nil -- where the world runs
choir.net = nil  -- as the host sent it (clients)

local PX = 3              -- world px per texel of their art
local SORT = 105          -- sort_y past the ground line (as region sprites')
local HOVER = 56          -- px a member floats over the street
local SIGHT = 700         -- px from the lair: this close, they wake
local GIVE_UP = 1400      -- px from the lair: further, they go home
local SPIN = 0.22         -- rad/s they circle you
local GRIEF = 1.3         -- while one's down, the others this much quicker
local RISE = { time = 12, health = 0.4 }
local SILENCE_TIME = 1.4  -- s from the last falling to the Choir's light
local FW = 48             -- a frame of their art, square, in texels

local MEMBERS = {
    { id = "seraph", name = "SERAPH", sheet = "enemy-03.png", frames = 4, fps = 8, health = 160, r = 34,
        orbit = 300, speed = 150, moves = { "hymn", "gaze", "gaze" },
        neon = { core = { 1, 0.85, 0.5 }, halo = { 1, 0.35, 0.05 }, radius = 12 }, glow = { 1, 0.5, 0.15 } },
    { id = "ophan", name = "OPHAN", sheet = "enemy-02.png", frames = 4, fps = 6, health = 120, r = 30,
        orbit = 260, speed = 130, moves = { "halo", "well", "ward", "halo" },
        neon = { core = { 0.75, 0.9, 1 }, halo = { 0.2, 0.45, 1 }, radius = 12 }, glow = { 0.3, 0.55, 1 } },
    { id = "cherub", name = "CHERUB", sheet = "enemy-01.png", frames = 5, fps = 10, health = 140, r = 30,
        orbit = 220, speed = 160, moves = { "charge", "spit", "charge" },
        neon = { core = { 0.85, 1, 0.6 }, halo = { 0.3, 0.9, 0.2 }, radius = 11 }, glow = { 0.4, 1, 0.3 } },
}
local REST = { 1.6, 2.8 }  -- s between one's moves, least and most
local SHOT = { speed = 220, damage = 14, radius = 5, lifetime = 3 }
local HYMN = { time = 2.4, every = 0.09, arms = 3, angryArms = 4, turn = 2.3, speed = 210 }
local GAZE = { shots = 7, spread = 0.9, volleys = { 0.15, 0.5 }, time = 0.9, speed = 300, damage = 16 }
local HALO = { shots = 18, volleys = { 0.1, 0.5 }, time = 0.8, speed = 170 }
local WELL = { tell = 0.8, time = 2.6, radius = 240, pull = 6.0e4, maxPull = 1200, drag = 2.5, maxDrift = 22,
    heart = 30, dps = 90 }
local WARD = { time = 4.5, weak = 0.25, every = 9 }
local CHARGE = { tell = 0.7, speed = 820, far = 560, over = 140, width = 34, damage = 110, push = 480, low = 26 }
local SPIT = { volleys = 3, every = 0.25, spread = 0.18, speed = 320, damage = 15 }

local art -- their sheets and quads, the burst, and the fx (needArt)

--------------------------------------------------------------------------------
-- Art
--------------------------------------------------------------------------------

local function sheet(path)
    local image = love.graphics.newImage(path)
    image:setFilter("nearest", "nearest")
    return image
end

-- `count` frames of w x h texels, `cols` to a row, from index `from`
local function quads(image, w, h, cols, from, count)
    local list = {}
    local iw, ih = image:getDimensions()
    for i = 0, count - 1 do
        local k = from + i
        list[i] = love.graphics.newQuad((k % cols) * w, math.floor(k / cols) * h, w, h, iw, ih)
    end
    return list
end

function choir.load()
    art = nil
    choir.live, choir.net = nil, nil
end

-- Their art, the first time they're out (most games never meet them: 2 MB
-- of texture kept off the GPU until then)
local function needArt()
    if art then return end
    art = { members = {} }
    for i, def in ipairs(MEMBERS) do
        local image = sheet("gfx/EnemiesSpriteSheets/" .. def.sheet)
        art.members[i] = { image = image, frames = quads(image, FW, FW, def.frames, 0, def.frames) }
    end
    art.burst = sheet("gfx/EnemiesSpriteSheets/enemy-explosion.png")
    art.burstFrames = quads(art.burst, 80, 80, 7, 0, 7)
    art.holy = sheet("gfx/fx/Spritesheets/Holy Light Aura.png")
    art.holyFlame = quads(art.holy, 96, 96, 5, 0, 7)
    art.holyRing = quads(art.holy, 96, 96, 5, 10, 7)
    art.spark = sheet("gfx/fx/Spritesheets/Eletric Aura.png")
    art.sparkFrames = quads(art.spark, 96, 96, 5, 0, 7)
    art.regen = sheet("gfx/fx/Spritesheets/Regen.png")
    art.regenFrames = quads(art.regen, 96, 96, 5, 0, 8)
    art.gravity = sheet("gfx/fx/Spritesheets/Gravity-Sheet.png")
    art.gravityFrames = quads(art.gravity, 96, 80, 4, 0, 20)
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function hosting()
    return not var.multiplayer or var.multiplayer == 1
end

local function unit(x, y)
    local l = math.sqrt(x * x + y * y)
    if l < 1e-6 then return 1, 0, 0 end
    return x / l, y / l, l
end

local function ease(v, target, rate, dt)
    return v + (target - v) * (1 - math.exp(-rate * dt))
end

local function looped(frames, count, fps, t)
    return frames[math.floor(t * fps) % count]
end

-- A hostile shot from (x, y) along angle `ang`
local function shoot(x, y, ang, neon, speed, damage)
    bullet.new({
        pos = vec2.new(x, y), dir = vec2.new(math.cos(ang), math.sin(ang)), speed = speed or SHOT.speed,
        damage = damage or SHOT.damage, radius = SHOT.radius, lifetime = SHOT.lifetime, neon = neon, hostile = true,
    })
end

local function chime(x, y, pitch)
    local src = audio.playSoundAt("enemyGun", x, y, 0.05, 0.3)
    if src then src:setPitch(pitch) end
end

--------------------------------------------------------------------------------
-- Life and death
--------------------------------------------------------------------------------

-- A hit on one (bosses.hit has scaled it by its part's weakness, the ward's
-- included): safe in the physics step, it falls in the Choir's update
local function hurt(m, damage)
    if m.fallen or m.health <= 0 then return end
    m.health = math.max(0, m.health - damage)
    m.flash = 0.12
end

-- Its part: a kinematic sensor where it's drawn
local function addBody(m)
    m.part = { type = "boss", boss = m, radius = m.def.r, hit = hurt }
    m.body = love.physics.newBody(world, m.x, m.y - m.z, "kinematic")
    local f = love.physics.newFixture(m.body, love.physics.newCircleShape(m.def.r))
    f:setSensor(true)
    f:setGroupIndex(-888) -- (bosses' group: game/boss.lua's bear is in it too)
    f:setUserData(m.part)
    m.part.body = m.body
    bosses.register(m.part)
end

local function dropBody(m)
    if m.part then bosses.unregister(m.part) end
    if m.body and not m.body:isDestroyed() then m.body:destroy() end
    m.part, m.body = nil, nil
end

-- What's drawn of the Choir (the host's, and clients' copies)
local function shell()
    local c = { members = {}, wells = {}, time = 0 }
    for i, def in ipairs(MEMBERS) do
        c.members[i] = { def = def, index = i, x = 0, y = 0, z = HOVER, flash = 0, health = def.health,
            max_health = def.health }
    end
    return c
end

--- The Choir comes out round (x, y); `lair`, the region it keeps (game/bosses.lua)
function choir.spawnAt(x, y, lair)
    needArt()
    if choir.live then choir.despawnInst(choir.live, true) end
    local c = shell()
    c.x, c.y, c.lair = x, y, lair
    c.state, c.spin = "wait", 0
    c.rng = love.math.newRandomGenerator(math.floor(x * 7 + y) % 100000 + 1)
    c.wardReady = 0
    for i, m in ipairs(c.members) do
        local a = (i - 1) / 3 * math.pi * 2 - math.pi / 2
        m.x, m.y = x + math.cos(a) * 90, y + math.sin(a) * 70
        m.ready = 0
        addBody(m)
    end
    choir.live = c
    return c
end

function choir.alive(c)
    return not c.gone
end

--- Take the Choir away. One that was silenced is beaten (bosses.defeated),
--- but `quiet`ly (a save being loaded) it just goes.
function choir.despawnInst(c, quiet)
    if c.gone then return end
    c.gone = true
    for _, m in ipairs(c.members) do dropBody(m) end
    if choir.live == c then choir.live = nil end
    if c.silenced and not quiet then bosses.defeated(c.lair, c.x, c.y) end
end

function choir.despawnAll()
    if choir.live then choir.despawnInst(choir.live, true) end
end

--- fn(member) for each one standing (here, or as the host sent them): the
--- HUD shows the nearest one's health
function choir.eachLive(fn)
    local c = hosting() and choir.live or choir.net
    if not c then return end
    for _, m in ipairs(c.members) do
        if not m.fallen then fn(m) end
    end
end

--------------------------------------------------------------------------------
-- The rite
--------------------------------------------------------------------------------

local function standing(c)
    local n = 0
    for _, m in ipairs(c.members) do
        if not m.fallen then n = n + 1 end
    end
    return n
end

-- Brought down: it bursts, and falls to the street to wait
local function fall(c, m)
    m.fallen, m.health, m.riseIn, m.burst = true, 0, RISE.time, 0
    m.burstX, m.burstY = m.x, m.y - m.z
    m.move, m.phase, m.lineK = nil, nil, 0
    dropBody(m)
    if c.ward and (c.ward.target == m or c.ward.from == m) then c.ward = nil end
    audio.playSoundAt("explosion", m.x, m.y, 0.08, 0.5)
    camera.shake(5, 0.25)
    if standing(c) == 0 then
        -- all three down together: the Choir is silenced
        c.silenced = 0
        c.wells = {}
        inventory.notify("The Choir falls silent")
    elseif not c.told then
        c.told = true
        inventory.notify("The " .. m.def.name:sub(1, 1) .. m.def.name:sub(2):lower()
            .. " will rise again unless all three fall")
    end
end

-- Risen again, with some of its health back
local function rise(c, m)
    m.fallen, m.riseIn = false, nil
    m.health = math.floor(m.max_health * RISE.health)
    m.regen, m.z = 0, 0
    m.ready = c.time + 1.2
    addBody(m)
    chime(m.x, m.y, 0.6)
end

--------------------------------------------------------------------------------
-- What they do
--------------------------------------------------------------------------------

local function begin(m, move)
    m.move, m.mt, m.fired = move, 0, 0
end

-- Fire the volleys of a move whose times have come (each once)
local function volleys(m, times, fn)
    while m.fired < #times and m.mt >= times[m.fired + 1] do
        m.fired = m.fired + 1
        fn(m.fired)
    end
end

-- One step of member m's move, at you (px, py); true when it's over
local MOVES = {}

function MOVES.hymn(c, m, dt, px, py)
    local arms = c.grief and HYMN.angryArms or HYMN.arms
    m.spinDir = m.spinDir or 1
    m.hymnAng = (m.hymnAng or 0) + HYMN.turn * dt * m.spinDir
    m.nextShot = (m.nextShot or 0) - dt
    if m.nextShot <= 0 then
        m.nextShot = HYMN.every
        for k = 0, arms - 1 do
            shoot(m.x, m.y - m.z, m.hymnAng + k / arms * math.pi * 2, m.def.neon, HYMN.speed)
        end
        if math.floor(m.mt / 0.3) ~= math.floor((m.mt - dt) / 0.3) then chime(m.x, m.y, 1.5) end
    end
    if m.mt >= HYMN.time then
        m.spinDir = -m.spinDir
        return true
    end
end

function MOVES.gaze(c, m, dt, px, py)
    volleys(m, GAZE.volleys, function()
        local base = math.atan2(py - 10 - (m.y - m.z), px - m.x)
        for k = 1, GAZE.shots do
            local ang = base + (k - (GAZE.shots + 1) / 2) / (GAZE.shots - 1) * GAZE.spread
            shoot(m.x, m.y - m.z, ang, m.def.neon, GAZE.speed, GAZE.damage)
        end
        chime(m.x, m.y, 1.1)
    end)
    return m.mt >= GAZE.time
end

function MOVES.halo(c, m, dt, px, py)
    volleys(m, HALO.volleys, function(k)
        local n = HALO.shots + (c.grief and 6 or 0)
        local off = (k % 2) * 0.5 / n * math.pi * 2
        for i = 0, n - 1 do
            shoot(m.x, m.y - m.z, off + i / n * math.pi * 2, m.def.neon, HALO.speed)
        end
        chime(m.x, m.y, 0.8)
    end)
    return m.mt >= HALO.time
end

function MOVES.well(c, m, dt, px, py)
    if m.fired == 0 then
        m.fired = 1
        if #c.wells == 0 then
            c.wells[1] = { x = px, y = py, t = 0, driftX = 0, driftY = 0 }
            chime(px, py, 0.5)
        end
    end
    return m.mt >= 0.5
end

function MOVES.ward(c, m, dt, px, py)
    if m.fired == 0 then
        m.fired = 1
        -- over whichever other one stands and is most hurt
        local best
        for _, o in ipairs(c.members) do
            if o ~= m and not o.fallen and (not best or o.health / o.max_health < best.health / best.max_health) then
                best = o
            end
        end
        if best then
            c.ward = { from = m, target = best, t = WARD.time }
            c.wardReady = c.time + WARD.every
            chime(best.x, best.y, 1.8)
        end
    end
    return m.mt >= 0.5
end

function MOVES.charge(c, m, dt, px, py)
    if m.phase == nil then
        m.phase = "tell"
    end
    if m.phase == "tell" then
        -- dips low, the way it'll go shown on the street; still aiming for
        -- the first half of it
        if m.mt < CHARGE.tell * 0.5 then
            local dx, dy, d = unit(px - m.x, py - m.y)
            m.chargeX, m.chargeY, m.chargeLeft = dx, dy, math.min(CHARGE.far, d + CHARGE.over)
        end
        m.lineK = math.min(1, m.mt / 0.3)
        m.lineX, m.lineY = m.x + m.chargeX * m.chargeLeft, m.y + m.chargeY * m.chargeLeft
        m.z = ease(m.z, CHARGE.low, 6, dt)
        if m.mt >= CHARGE.tell then
            m.phase, m.struck = "rush", false
            chime(m.x, m.y, 0.7)
        end
    elseif m.phase == "rush" then
        m.lineK = 0
        local step = CHARGE.speed * dt
        m.chargeLeft = m.chargeLeft - step
        if not m.struck and not player.isDodging then
            local qx, qy = px - m.x, py - m.y
            local along = qx * m.chargeX + qy * m.chargeY
            local across = math.abs(qx * m.chargeY - qy * m.chargeX)
            if along > -10 and along < step + CHARGE.width and across < CHARGE.width then
                m.struck = true
                local sx, sy = -m.chargeY, m.chargeX
                if qx * sx + qy * sy < 0 then sx, sy = -sx, -sy end
                player.hurt(CHARGE.damage * (c.grief and 1.15 or 1), vec2.new(sx, sy), "blow")
                player.applyKnockback(vec2.new(sx, sy), CHARGE.push * armor.knockback())
            end
        end
        m.x, m.y = m.x + m.chargeX * step, m.y + m.chargeY * step
        enemyWeapons.sparks(m.x, m.y - m.z, -m.chargeX, -m.chargeY, 1, 0.5,
            { m.def.neon.core, m.def.glow }, 140, 0.3)
        if m.chargeLeft <= 0 then
            m.phase = "after"
            m.mt = CHARGE.tell -- (from here, mt runs on as recovery)
        end
    elseif m.mt >= CHARGE.tell + 0.45 then
        m.phase = nil
        return true
    end
end

function MOVES.spit(c, m, dt, px, py)
    local times = {}
    for k = 1, SPIT.volleys do times[k] = (k - 1) * SPIT.every end
    volleys(m, times, function()
        local base = math.atan2(py - 10 - (m.y - m.z), px - m.x)
        for k = -1, 1 do shoot(m.x, m.y - m.z + 10, base + k * SPIT.spread, m.def.neon, SPIT.speed, SPIT.damage) end
        chime(m.x, m.y, 1.3)
    end)
    return m.mt >= SPIT.volleys * SPIT.every + 0.2
end

-- Pick member m's next move: its own list, the ward only when it's ready
-- and someone else stands, a well only when there isn't one
local function pick(c, m)
    for _ = 1, 4 do
        local move = m.def.moves[c.rng:random(#m.def.moves)]
        if move == "ward" and (c.time < c.wardReady or c.ward or standing(c) < 2) then move = nil end
        if move == "well" and #c.wells > 0 then move = nil end
        if move == "charge" and player.inCar then move = "spit" end
        if move and move ~= m.lastMove then
            m.lastMove = move
            return move
        end
    end
    return m.def.moves[1]
end

-- One standing member, a step: to its place round you, and its moves
local function think(c, m, dt, px, py, pace)
    m.flash = math.max(0, m.flash - dt)
    if m.regen then
        m.regen = m.regen + dt
        if m.regen > 1.2 then m.regen = nil end
    end
    local charging = m.move == "charge" and m.phase == "rush"
    if not charging then
        -- its place in the ring round you (or round the lair, waiting)
        local cx, cy, orbit = px, py, m.def.orbit
        if c.state ~= "awake" then cx, cy, orbit = c.x, c.y, 90 end
        local ang = c.spin + (m.index - 1) / 3 * math.pi * 2
        local tx, ty = cx + math.cos(ang) * orbit, cy + math.sin(ang) * orbit * 0.75
        local dx, dy, d = unit(tx - m.x, ty - m.y)
        local step = math.min(d, m.def.speed * pace * dt * math.min(1, d / 60 + 0.3))
        m.x, m.y = m.x + dx * step, m.y + dy * step
        if not (m.move == "charge") then
            m.z = ease(m.z, HOVER + math.sin(c.time * 2 + m.index * 2.1) * 8, 3, dt)
        end
    end
    if c.state ~= "awake" then return end
    if m.move then
        m.mt = m.mt + dt * pace
        if MOVES[m.move](c, m, dt * pace, px, py) then
            m.move, m.lineK = nil, 0
            m.ready = c.time + (REST[1] + c.rng:random() * (REST[2] - REST[1])) / pace
        end
    elseif c.time >= m.ready then
        begin(m, pick(c, m))
    end
end

-- The Ophan's wells: open, drag you to their hearts, burn you there, close
local function wells(c, dt, px, py)
    for i = #c.wells, 1, -1 do
        local w = c.wells[i]
        w.t = w.t + dt
        if w.t >= WELL.tell + WELL.time then
            table.remove(c.wells, i)
        elseif w.t >= WELL.tell and not player.inCar then
            -- a drift kept here and added to your velocity (as the enemies'
            -- black holes: game/blackholeGun.lua's pullPlayer)
            local dx, dy, d = unit(w.x - px, w.y - py)
            local keep = math.max(0, 1 - WELL.drag * dt)
            w.driftX, w.driftY = w.driftX * keep, w.driftY * keep
            if d > 0.5 and d < WELL.radius then
                local a = math.min(WELL.maxPull, WELL.pull / d) * dt
                w.driftX, w.driftY = w.driftX + dx * a, w.driftY + dy * a
            end
            local cap = WELL.maxDrift * math.min(1, d / 40)
            local s = math.sqrt(w.driftX * w.driftX + w.driftY * w.driftY)
            if s > cap then w.driftX, w.driftY = w.driftX / s * cap, w.driftY / s * cap end
            if w.driftX * w.driftX + w.driftY * w.driftY > 0.01 then
                local vx, vy = player.body:getLinearVelocity()
                player.body:setLinearVelocity(vx + w.driftX, vy + w.driftY)
            end
            if d < WELL.heart then
                w.burn = (w.burn or 0) + WELL.dps * dt -- (hurt in ticks, so the shake stays small)
                if w.burn >= 20 then
                    player.hurt(w.burn, nil, "energy")
                    w.burn = 0
                end
            end
        end
    end
end

-- Their glow lights the street under them
local function addLights(c)
    local x0, y0, x1, y1 = regions.view(300)
    if c.x < x0 - GIVE_UP or c.x > x1 + GIVE_UP or c.y < y0 - GIVE_UP or c.y > y1 + GIVE_UP then return end
    for _, m in ipairs(c.members) do
        if m.fallen then
            shadow.addTransientLight(m.x, m.y, 0.3, 100)
        else
            shadow.addTransientLight(m.x, m.y + 6, 0.45, 140)
        end
    end
    for _, w in ipairs(c.wells) do shadow.addTransientLight(w.x, w.y, 0.3, 120) end
end

local function update(c, dt)
    c.time = c.time + dt
    for _, m in ipairs(c.members) do
        if m.burst then
            m.burst = m.burst + dt
            if m.burst > 0.6 then m.burst = nil end
        end
    end
    if c.silenced then
        c.silenced = c.silenced + dt
        for _, m in ipairs(c.members) do
            m.riseIn, m.z = nil, math.max(0, m.z - dt * 300)
        end
        if c.silenced >= SILENCE_TIME then
            local x, y = 0, 0
            for _, m in ipairs(c.members) do x, y = x + m.x / 3, y + m.y / 3 end
            c.x, c.y = x, y
            explosion.create(x, y - 30, explosion.TYPES.DEATH)
            audio.playSoundAt("explosion", x, y, 0.1, 0.7)
            camera.shake(9, 0.45)
            choir.despawnInst(c)
        end
        return
    end
    if not (player and player.body) then return end
    local px, py = player.body:getPosition()
    local fromLair = math.sqrt((px - c.x) ^ 2 + (py - c.y) ^ 2)
    if c.state == "wait" and fromLair < SIGHT then
        c.state = "awake"
        for i, m in ipairs(c.members) do m.ready = c.time + 1 + i * 0.8 end
        chime(c.x, c.y, 0.5)
    elseif c.state == "awake" and fromLair > GIVE_UP then
        c.state, c.wells, c.ward = "wait", {}, nil
        for _, m in ipairs(c.members) do m.move, m.phase, m.lineK = nil, nil, 0 end
    end
    c.grief = standing(c) < 3
    local pace = c.grief and GRIEF or 1
    c.spin = c.spin + SPIN * dt * pace
    -- the ward wears off
    if c.ward then
        c.ward.t = c.ward.t - dt
        if c.ward.t <= 0 then c.ward = nil end
    end
    for _, m in ipairs(c.members) do
        if not m.fallen and m.health <= 0 then fall(c, m) end
        if c.silenced then return end
        if m.fallen then
            m.z = math.max(0, m.z - dt * 300)
            m.riseIn = m.riseIn - dt
            if m.riseIn <= 0 then rise(c, m) end
        else
            think(c, m, dt, px, py, pace)
            m.part.weak = c.ward and c.ward.target == m and WARD.weak or 1
            m.body:setPosition(m.x, m.y - m.z)
        end
    end
    wells(c, dt, px, py)
end

--- Each frame, before the lighting upload: where the world runs, the Choir
--- thinks, moves and keeps its rite; everywhere, it lights the street.
function choir.update(dt)
    local c = hosting() and choir.live or choir.net
    if not c then return end
    if hosting() then
        update(c, dt)
        if c.gone then return end
    else
        c.time = c.time + dt
    end
    addLights(c)
end

--------------------------------------------------------------------------------
-- Network
--------------------------------------------------------------------------------

--- Host: what clients need to draw it (nil: no Choir)
function choir.getNetworkData()
    local c = choir.live
    if not c then return nil end
    local members, wellList = {}, {}
    for i, m in ipairs(c.members) do
        members[i] = {
            x = m.x, y = m.y, z = m.z, h = m.health, m = m.max_health, f = m.flash, fl = m.fallen or nil,
            ri = m.riseIn, bu = m.burst, bx = m.burstX, by = m.burstY, rg = m.regen,
            lk = m.lineK, lx = m.lineX, ly = m.lineY,
        }
    end
    for i, w in ipairs(c.wells) do wellList[i] = { x = w.x, y = w.y, t = w.t } end
    return {
        x = c.x, y = c.y, members = members, wells = wellList, gr = c.grief or nil, si = c.silenced,
        wf = c.ward and c.ward.from.index, wt = c.ward and c.ward.target.index,
    }
end

--- Client: the Choir as the host sent it
function choir.applyNetworkData(d)
    if not d then
        choir.net = nil
        return
    end
    needArt()
    local c = choir.net or shell()
    c.x, c.y, c.grief, c.silenced = d.x, d.y, d.gr, d.si
    for i, s in ipairs(d.members or {}) do
        local m = c.members[i]
        if m then
            m.x, m.y, m.z, m.health, m.max_health, m.flash = s.x, s.y, s.z, s.h, s.m, s.f or 0
            m.fallen, m.riseIn, m.burst, m.burstX, m.burstY, m.regen = s.fl, s.ri, s.bu, s.bx, s.by, s.rg
            m.lineK, m.lineX, m.lineY = s.lk or 0, s.lx, s.ly
        end
    end
    c.wells = d.wells or {}
    c.ward = d.wf and { from = c.members[d.wf], target = c.members[d.wt] } or nil
    choir.net = c
end

--------------------------------------------------------------------------------
-- Drawing (lib/graphics/renderer.lua hands each piece to choir.drawPiece)
--------------------------------------------------------------------------------

local function halo(x, y, radius, c, k)
    love.graphics.setColor(c[1] * k, c[2] * k, c[3] * k, 1)
    love.graphics.draw(regions.glow, x - radius, y - radius, 0, radius * 2 / 64, radius * 2 / 64)
end

-- On the street, under everything: shadows, the Cherub's line, the wells,
-- and the fallen in their rings of holy light, counting down
local function drawGround(c)
    for _, m in ipairs(c.members) do
        if not m.fallen then
            local lift = math.min(1, m.z / 120)
            love.graphics.setColor(0, 0, 0, 0.32 * (1 - lift * 0.5))
            love.graphics.ellipse("fill", m.x, m.y, 30 + lift * 10, (30 + lift * 10) * 0.4)
        end
    end
    love.graphics.setBlendMode("add")
    for _, m in ipairs(c.members) do
        if (m.lineK or 0) > 0 and m.lineX then
            local pulse = 0.6 + 0.4 * math.abs(math.sin(c.time * 16))
            local g = m.def.glow
            love.graphics.setLineWidth(CHARGE.width * 2)
            love.graphics.setColor(g[1] * 0.3, g[2] * 0.3, g[3] * 0.3, m.lineK * pulse)
            love.graphics.line(m.x, m.y, m.lineX, m.lineY)
            love.graphics.setLineWidth(2)
            love.graphics.setColor(g[1], g[2], g[3], 0.8 * m.lineK * pulse)
            love.graphics.line(m.x, m.y, m.lineX, m.lineY)
            love.graphics.setLineWidth(1)
        end
    end
    for _, w in ipairs(c.wells) do
        local open = math.min(1, w.t / WELL.tell)
        local closing = math.max(0, (w.t - WELL.tell - WELL.time + 0.4) / 0.4)
        local k = open * (1 - closing) * (w.t < WELL.tell and 0.5 or 1)
        local s = WELL.radius * 2 / 96 * (0.4 + 0.6 * open)
        love.graphics.setColor(k, k, k, 1)
        love.graphics.draw(art.gravity, looped(art.gravityFrames, 20, 16, w.t), w.x, w.y, 0, s, s * 0.6, 48, 41)
    end
    for _, m in ipairs(c.members) do
        if m.fallen and m.riseIn and not c.silenced then
            local left = m.riseIn / RISE.time
            local k = 0.6 + 0.4 * math.sin(c.time * 4)
            love.graphics.setColor(k, k, k, 1)
            love.graphics.draw(art.holy, looped(art.holyRing, 7, 10, c.time), m.x, m.y, 0, 2.2, 2.2, 48, 63)
            -- what's left of its wait, as an arc round it
            love.graphics.setLineWidth(3)
            love.graphics.setColor(0.6, 0.85, 1, 0.8)
            love.graphics.arc("line", "open", m.x, m.y - 4, 62, -math.pi / 2, -math.pi / 2 + left * math.pi * 2, 40)
            love.graphics.setLineWidth(1)
        end
    end
    love.graphics.setBlendMode("alpha")
end

local function drawMember(c, m)
    local A = art.members[m.index]
    local quad = looped(A.frames, m.def.frames, m.def.fps * (c.grief and GRIEF or 1), c.time + m.index * 0.37)
    local x, y = m.x, m.y - m.z
    local f = m.flash > 0 and 0.55 or 0
    love.graphics.setColor(1, 1 - f, 1 - f, 1)
    love.graphics.draw(A.image, quad, x, y, 0, PX, PX, FW / 2, FW / 2)
    love.graphics.setShader()
    love.graphics.setBlendMode("add")
    halo(x, y, 70, m.def.glow, (c.grief and 0.4 or 0.28) * (0.85 + 0.15 * math.sin(c.time * 3 + m.index)))
    if c.ward and c.ward.target == m then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(art.spark, looped(art.sparkFrames, 7, 14, c.time), x, y, 0, 1.6, 1.6, 48, 48)
    end
    if m.regen then
        love.graphics.setColor(1, 1, 1, 1)
        local i = math.min(7, math.floor(m.regen / 1.2 * 8))
        love.graphics.draw(art.regen, art.regenFrames[i], x, y + 20, 0, 1.8, 1.8, 48, 60)
    end
    love.graphics.setBlendMode("alpha")
end

-- One that's fallen: lying dim on the street, its burst over it, and the holy
-- light rising round it as it comes back
local function drawFallen(c, m)
    local A = art.members[m.index]
    love.graphics.setColor(0.45, 0.45, 0.5, 0.85)
    love.graphics.draw(A.image, A.frames[0], m.x, m.y - m.z - 16, 0, PX, PX * 0.85, FW / 2, FW / 2)
    love.graphics.setShader()
    love.graphics.setBlendMode("add")
    if m.riseIn and m.riseIn < 3 and not c.silenced then
        local k = 1 - m.riseIn / 3
        love.graphics.setColor(k, k, k, 1)
        love.graphics.draw(art.holy, looped(art.holyFlame, 7, 12, c.time), m.x, m.y, 0, 2 + k, 2 + k * 2, 48, 58)
    end
    love.graphics.setBlendMode("alpha")
    if m.burst then
        local i = math.min(6, math.floor(m.burst / 0.5 * 7))
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(art.burst, art.burstFrames[i], m.burstX or m.x, m.burstY or m.y, 0, 2.5, 2.5, 40, 40)
    end
end

-- The ward: a crackling line from the Ophan to the one it keeps
local function drawLink(c)
    local w = c.ward
    if not (w and w.from and w.target) then return end
    local a, b = w.from, w.target
    love.graphics.setShader()
    love.graphics.setBlendMode("add")
    local x1, y1, x2, y2 = a.x, a.y - a.z, b.x, b.y - b.z
    local nx, ny = unit(-(y2 - y1), x2 - x1)
    local points = { x1, y1 }
    for i = 1, 7 do
        local t = i / 8
        local j = (love.math.random() - 0.5) * 14
        points[#points + 1] = x1 + (x2 - x1) * t + nx * j
        points[#points + 1] = y1 + (y2 - y1) * t + ny * j
    end
    points[#points + 1] = x2
    points[#points + 1] = y2
    love.graphics.setLineWidth(5)
    love.graphics.setColor(0.15, 0.3, 0.9, 0.6)
    love.graphics.line(points)
    love.graphics.setLineWidth(2)
    love.graphics.setColor(0.75, 0.9, 1, 1)
    love.graphics.line(points)
    love.graphics.setLineWidth(1)
    love.graphics.setBlendMode("alpha")
end

--- One piece of the Choir, from the sorted list: each member lit like
--- everything else, its glow added over it
function choir.drawPiece(d)
    local c = d.choir
    local shader = love.graphics.getShader()
    if d.piece == "ground" then
        love.graphics.setShader()
        drawGround(c)
    elseif d.piece == "member" then
        drawMember(c, d.member)
    elseif d.piece == "fallen" then
        drawFallen(c, d.member)
    elseif d.piece == "link" then
        drawLink(c)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(shader)
end

--- The Choir, if it's on screen, into the dynamic draw list: each member
--- sorted by the street under it
function choir.populate()
    local c = hosting() and choir.live or choir.net
    if not c then return end
    local x0, y0, x1, y1 = regions.view(500)
    local seen = false
    for _, m in ipairs(c.members) do
        if m.x > x0 and m.x < x1 and m.y > y0 and m.y < y1 then seen = true end
    end
    if not seen then return end
    local list = dynamic_draw_list
    list[#list + 1] = { sort_y = -1e9, draw_type = "choir", choir = c, piece = "ground" }
    for _, m in ipairs(c.members) do
        list[#list + 1] = { sort_y = m.y + SORT, draw_type = "choir", choir = c, member = m,
            piece = m.fallen and "fallen" or "member" }
    end
    if c.ward then list[#list + 1] = { sort_y = renderer.ON_TOP, draw_type = "choir", choir = c, piece = "link" } end
end

return choir
