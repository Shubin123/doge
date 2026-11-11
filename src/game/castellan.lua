--[[
  The Castle's boss (game/bosses.lua's "castellan"): the keeper of the
  castle, a swordswoman in a purple cloak (gfx/WarriorSpriteSheet), on guard
  at her lair in front of the keep, and the guard she calls
  (gfx/SoldierSpriteSheets).

  What she does, where the world runs (host, single player; clients draw her
  where the host says):
    wait     on guard at her lair until you come within SIGHT
    advance  runs at you, round what's in the way (lib/nav.lua's flow field)
    combo    two cuts in a row: one across in front of her, then one over
             her head that reaches behind her too
    throw    from out of reach, a cut thrown as a crescent that flies along
             the street until a wall stops it (three in a fan once she's
             angry); a roll goes under it
    dash     she drops into a crouch (a line on the street shows her way),
             dashes along it through you and ends in a lunge; a roll goes
             under it
    call     at each of CALLS' share of her health she plants her sword and
             her guard comes: swordsmen who close in and cut, archers who
             keep back and loose arrows
    reel     hurt POISE.limit faster than she shrugs it off, she reels a
             moment and takes more (POISE.weak)
  Under half health she's angry: quicker at everything, and violet with it.
  She gives up on you past GIVE_UP and walks back to her lair.

  Her parts (bosses.lua) are her feet (a dynamic body: walls stop her, she
  shoves you) and a sensor over her body, where she's drawn; each guard's
  the same, smaller. A guard killed leaves an enemy's XP gem; when she
  falls, so does her guard. Her sheet faces right: facing left is it
  mirrored, about where she stands.
]]
local castellan = {}

local nav = require("lib.nav")

castellan.NAME = "THE CASTELLAN"
castellan.live = {} -- where the world runs
castellan.net = {}  -- as the host sent them (clients)

local PX = 3            -- world px per texel of her art (and her guard's)
local SORT = 105        -- sort_y past the ground line (as region sprites')
local HEALTH = 300      -- (a pistol shot is 1, a rocket up to 45)
local FEET_R = 16       -- her feet's circle
local BODY_Y, BODY_R = -42, 24 -- the sensor over her body, from her feet
local SIGHT = 640       -- px: this close, she comes for you
local GIVE_UP = 1100    -- px: further, she goes back to her lair
local SPEED = 170       -- px/s running at you
local ANGRY_PACE = 1.25 -- under half health, everything she does, this much quicker
local STEER = 10        -- how fast she takes up the velocity she wants (1/s)
local POISE = { limit = 32, mend = 14, weak = 1.6 }
local COMBO = { reach = 100, damage = { 90, 110 }, push = 380, step = 150 }
local WAVE = { speed = 430, life = 1.5, radius = 26, height = 30, damage = 80, near = 200, far = 560,
    fan = 0.3, every = 3.2 }
local DASH = { speed = 900, far = 480, over = 110, width = 36, damage = 120, push = 520, near = 170,
    every = 4.5, reach = 90, lunge = 100 }
local CALL_TIME = 1.1   -- s she stands calling
local CALLS = {         -- her share of health left, and who comes
    { at = 0.7, guards = { "sword", "sword", "bow" } },
    { at = 0.4, guards = { "sword", "bow", "sword", "bow" } },
}
local DEATH_TIME = 2.4  -- s from her fall to her light (bosses.defeated)

local GUARD = {
    health = 6, speed = 125, feet = 8, bodyY = -22, bodyR = 13, spread = { 190, 300 },
    sword = { reach = 46, damage = 45, every = 1.0 },
    bow = { near = 190, keep = 300, range = 480, every = 2.2,
        arrow = { speed = 430, damage = 24, radius = 3, lifetime = 1.4 } },
}
local ARROW_NEON = { core = { 1, 0.95, 0.8 }, halo = { 0.95, 0.55, 0.2 }, radius = 8 }
local WAVE_CORE = { 1, 1, 1 }
local WAVE_EDGE = { 0.62, 0.56, 0.92 } -- the lavender of her sheet's cuts
local FURY = { 0.32, 0.12, 0.5 }       -- added over her, angry

-- Her sheet: 69 x 44 texel frames, six to a row, standing on (27, 42.5)
local FW, FH, FOOT_X, FOOT_Y = 69, 44, 27, 42.5
local ANIMS = { -- first frame, last, frames a second, loops
    idle = { 0, 5, 8, true },
    run = { 6, 13, 14, true },
    combo = { 14, 25, 11 },  -- cuts on 19 (in front) and 23 (over her head)
    throw = { 14, 22, 12 },  -- the combo's first cut, thrown on 19
    death = { 26, 36, 9 },
    reel = { 37, 40, 10 },
    crouch = { 63, 67, 9 },
    dash = { 69, 72, 16, true },
    lunge = { 78, 83, 13 },  -- cuts on 79
    call = { 84, 85, 3, true },
}
-- Her guard's: 100 x 100 texel frames, nine to a row, standing on (48, 56.5)
local GW, GH, GFOOT_X, GFOOT_Y = 100, 100, 48, 56.5
local GANIMS = {
    idle = { 0, 5, 8, true },
    walk = { 9, 16, 12, true },
    cut = { 18, 23, 12 },   -- a swing round, landing on 21
    chop = { 27, 32, 12 },  -- down in front, landing on 30
    shoot = { 36, 44, 12 }, -- the arrow loosed on 43
    reel = { 54, 58, 14 },
    death = { 63, 66, 8 },
}

local art -- the sheets, their quads and the crescent (needArt)

--------------------------------------------------------------------------------
-- Art
--------------------------------------------------------------------------------

local function quads(image, w, h, cols, count)
    local list = {}
    local iw, ih = image:getDimensions()
    for i = 0, count - 1 do
        list[i] = love.graphics.newQuad((i % cols) * w, math.floor(i / cols) * h, w, h, iw, ih)
    end
    return list
end

-- A thrown cut: a crescent 18 x 40 texels, its back along +x (the way it
-- flies), white at the rim and lavender inside
local CW, CH = 18, 40
local function crescent()
    local data = love.image.newImageData(CW, CH)
    for y = 0, CH - 1 do
        for x = 0, CW - 1 do
            local u, v = x + 0.5, y + 0.5 - CH / 2
            local outer = math.sqrt(u * u + v * v)
            local inner = math.sqrt((u + 7) ^ 2 + v * v)
            if outer <= CH / 2 - 1 and inner > CH / 2 then
                local c = CH / 2 - 1 - outer < 1.6 and WAVE_CORE or WAVE_EDGE
                data:setPixel(x, y, c[1], c[2], c[3], 1)
            end
        end
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    return image
end

function castellan.load()
    art = nil
    castellan.live, castellan.net = {}, {}
end

-- Her art, the first time she's out (most games never meet her: 4 MB of
-- texture kept off the GPU until then)
local function needArt()
    if art then return end
    local sheet = love.graphics.newImage("gfx/WarriorSpriteSheet/Warrior_Sheet-Effect.png")
    local guard = love.graphics.newImage("gfx/SoldierSpriteSheets/Soldier.png")
    sheet:setFilter("nearest", "nearest")
    guard:setFilter("nearest", "nearest")
    art = {
        sheet = sheet, frames = quads(sheet, FW, FH, 6, 99),
        guard = guard, guardFrames = quads(guard, GW, GH, 9, 72),
        crescent = crescent(),
    }
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

-- The frame `t` s into animation `name` of `anims`, and whether it's played through
local function frameOf(anims, name, t)
    local A = anims[name]
    local n = A[2] - A[1] + 1
    local i = math.floor(t * A[3])
    if A[4] then return A[1] + i % n, false end
    return A[1] + math.min(i, n - 1), i >= n
end

-- Whether nothing static stands between (x1, y1) and (x2, y2)
local function inSight(x1, y1, x2, y2)
    local clear = true
    world:rayCast(x1, y1, x2, y2, function(f)
        if not f:isSensor() and f:getBody():getType() == "static" then
            clear = false
            return 0
        end
        return -1
    end)
    return clear
end

-- Whether a circle of radius r at (x, y) is clear of everything static
local function clearAt(x, y, r)
    local clear = true
    world:queryBoundingBox(x - r, y - r, x + r, y + r, function(f)
        if not f:isSensor() and f:getBody():getType() == "static" then
            clear = false
            return false
        end
        return true
    end)
    return clear
end

-- One flow field to you, shared by her and her guard (as enemy.lua's)
local FLOW_CELL, FLOW_RADIUS, FLOW_EVERY = 48, 22, 0.5
local grid = nav.new(FLOW_CELL, FEET_R + 2)
local field, fieldAt = nil, -math.huge
local function flowTo(px, py, now)
    if not field or (now - fieldAt > FLOW_EVERY and
            (math.floor(px / FLOW_CELL) ~= field.gx or math.floor(py / FLOW_CELL) ~= field.gy)) then
        field, fieldAt = grid:flow(px, py, FLOW_RADIUS), now
    end
    return field
end

-- Which way to go from (x, y) to you at (px, py): straight while it can see
-- you, else round what's in the way
local function wayTo(x, y, px, py)
    local dx, dy = unit(px - x, py - y)
    if inSight(x, y, px, py) then return dx, dy, true end
    local f = flowTo(px, py, love.timer.getTime())
    if f:covers(x, y) then
        local fx, fy = f:dir(x, y)
        if fx then return fx, fy, false end
    end
    return dx, dy, false
end

local function steer(body, wx, wy, speed, dt)
    local vx, vy = body:getLinearVelocity()
    local k = math.min(1, STEER * dt)
    body:setLinearVelocity(vx + (wx * speed - vx) * k, vy + (wy * speed - vy) * k)
end

-- A blow landing on you from (x, y)
local function strike(x, y, damage, push, kind)
    local px, py = player.body:getPosition()
    local dx, dy = unit(px - x, py - y)
    player.hurt(damage, vec2.new(dx, dy), kind or "blow")
    if push then player.applyKnockback(vec2.new(dx, dy), push * armor.knockback()) end
end

local function swish(x, y, pitch)
    local src = audio.playSoundAt("fire", x, y, 0.05, 0.35)
    if src then src:setPitch(pitch or 1.7) end
end

--------------------------------------------------------------------------------
-- Life and death
--------------------------------------------------------------------------------

-- A hit (bosses.hit has scaled it by the part's weakness): safe in the
-- physics step, she reels or dies in her update
local function hurt(a, damage)
    if a.dying or a.gone or a.health <= 0 then return end
    a.health = math.max(0, a.health - damage)
    a.flash = 0.12
    a.poise = a.poise + damage
end

local function hurtGuard(g, damage)
    if g.dying or g.health <= 0 then return end
    g.health = math.max(0, g.health - damage)
    g.flash = 0.12
    g.reel = true
end

-- A dynamic body standing at (x, y): its feet (stopped by walls, shoving
-- you) and a sensor over it, both the one part. The body and its feet.
local function newBody(x, y, feetR, bodyY, bodyR, density, part)
    local body = love.physics.newBody(world, x, y, "dynamic")
    body:setFixedRotation(true)
    local feet = love.physics.newFixture(body, love.physics.newCircleShape(feetR), density)
    local over = love.physics.newFixture(body, love.physics.newCircleShape(0, bodyY, bodyR), 0)
    over:setSensor(true)
    for _, f in ipairs({ feet, over }) do
        f:setGroupIndex(-888) -- (bosses' group: game/boss.lua's bear is in it too)
        f:setUserData(part)
    end
    part.body = body
    bosses.register(part)
    return body, feet
end

-- What's drawn of her (the host's, and clients' copies)
local function shell()
    return { x = 0, y = 0, frame = 0, facing = 1, flash = 0, time = 0, lineK = 0,
        guards = {}, waves = {} }
end

--- She comes out at (x, y); `lair`, the region she guards (game/bosses.lua)
function castellan.spawnAt(x, y, lair)
    needArt()
    local a = shell()
    a.x, a.y, a.homeX, a.homeY, a.lair = x, y, x, y, lair
    a.health, a.max_health = HEALTH, HEALTH
    a.state, a.anim, a.t = "wait", "idle", 0
    a.poise, a.called = 0, 0
    a.waveReady, a.dashReady = 0, 0
    a.rng = love.math.newRandomGenerator(math.floor(x * 5 + y) % 100000 + 1)
    a.part = { type = "boss", boss = a, radius = FEET_R, hit = hurt }
    a.body, a.feet = newBody(x, y, FEET_R, BODY_Y, BODY_R, 8, a.part)
    castellan.live[#castellan.live + 1] = a
    return a
end

function castellan.alive(a)
    return not a.gone
end

local function dropGuard(g)
    if g.part then
        bosses.unregister(g.part)
        g.part = nil
    end
    if g.body and not g.body:isDestroyed() then g.body:destroy() end
    g.body = nil
end

--- Take her away, and her guard. One that was dying is beaten
--- (bosses.defeated), but `quiet`ly (a save being loaded) she just goes.
function castellan.despawnInst(a, quiet)
    if a.gone then return end
    a.gone = true
    for i, other in ipairs(castellan.live) do
        if other == a then
            table.remove(castellan.live, i)
            break
        end
    end
    bosses.unregister(a.part)
    if a.body and not a.body:isDestroyed() then a.body:destroy() end
    for _, g in ipairs(a.guards) do dropGuard(g) end
    a.guards, a.waves = {}, {}
    if a.dying and not quiet then bosses.defeated(a.lair, a.x, a.y) end
end

function castellan.despawnAll()
    for i = #castellan.live, 1, -1 do castellan.despawnInst(castellan.live[i], true) end
end

--- fn(castellan) for each live one (here, or as the host sent them)
function castellan.eachLive(fn)
    for _, a in ipairs(hosting() and castellan.live or castellan.net) do fn(a) end
end

--------------------------------------------------------------------------------
-- Her guard
--------------------------------------------------------------------------------

-- Her guard comes: each of `kinds` on clear ground round her
local function call(a, kinds)
    local n = #kinds
    for i, kind in ipairs(kinds) do
        local base = i / n * math.pi * 2 + a.rng:random() * 0.5
        local x, y
        for try = 0, 9 do
            local ang = base + try * 0.7
            local r = GUARD.spread[1] + a.rng:random() * (GUARD.spread[2] - GUARD.spread[1])
            local cx, cy = a.x + math.cos(ang) * r, a.y + math.sin(ang) * r * 0.8
            if clearAt(cx, cy, 20) then
                x, y = cx, cy
                break
            end
        end
        if x then
            local g = { kind = kind, x = x, y = y, health = GUARD.health, flash = 0, fade = 0, facing = 1,
                state = "come", anim = "walk", t = 0, frame = 9, ready = a.time + 0.6 + i * 0.25, nextCut = "cut" }
            g.part = { type = "boss", boss = g, radius = GUARD.bodyR, hit = hurtGuard }
            g.body = newBody(x, y, GUARD.feet, GUARD.bodyY, GUARD.bodyR, 2, g.part)
            a.guards[#a.guards + 1] = g
            enemyWeapons.sparks(x, y - 20, 0, -1, 10, math.pi, { { 1, 0.9, 0.7 }, WAVE_EDGE }, 140, 0.45)
        end
    end
    camera.shake(3, 0.25)
end

local function setGuard(g, state, anim)
    g.state, g.anim, g.t = state, anim or state, 0
end

local function killGuard(g)
    g.dying, g.health = true, 0
    setGuard(g, "dead", "death")
    dropGuard(g)
    xp.drop(g.x, g.y) -- (an enemy's gem)
end

-- One guard, a step: closes in and cuts, or keeps back and shoots
local function guardThink(a, g, dt, px, py)
    g.t = g.t + dt
    g.flash = math.max(0, g.flash - dt)
    local prev = g.frame
    g.frame, g.done = frameOf(GANIMS, g.anim, g.t)
    local fresh = g.frame ~= prev
    if g.dying then
        g.fade = g.t < 1.2 and 1 or math.max(0, 1 - (g.t - 1.2) * 2)
        return g.fade <= 0
    end
    g.fade = math.min(1, g.fade + dt * 2.5)
    g.x, g.y = g.body:getPosition()
    if g.health <= 0 then
        killGuard(g)
        return false
    end
    local dx, dy, d = unit(px - g.x, py - g.y)
    local wx, wy, speed = 0, 0, 0
    if g.reel and g.state ~= "reel" and g.state ~= "shoot" then setGuard(g, "reel") end
    g.reel = false

    if g.state == "come" then
        g.facing = dx >= 0 and 1 or -1
        local wayX, wayY, sight = wayTo(g.x, g.y, px, py)
        if g.kind == "sword" then
            local W = GUARD.sword
            if sight and d < W.reach * 0.85 and a.time >= g.ready then
                setGuard(g, g.nextCut)
                g.nextCut = g.nextCut == "cut" and "chop" or "cut"
            elseif d > W.reach * 0.6 then
                wx, wy, speed = wayX, wayY, GUARD.speed
            end
        else
            local W = GUARD.bow
            if sight and d > W.near and d < W.range and a.time >= g.ready then
                setGuard(g, "shoot")
            elseif sight and d < W.near then
                wx, wy, speed = -dx, -dy, GUARD.speed * 0.8 -- back off
            elseif not sight or d > W.keep then
                wx, wy, speed = wayX, wayY, GUARD.speed
            end
        end
        if g.state == "come" then g.anim = speed > 0 and "walk" or "idle" end
    elseif g.state == "cut" or g.state == "chop" then
        if fresh and (g.frame == 21 or g.frame == 30) then
            local W = GUARD.sword
            local ahead = (px - g.x) * g.facing
            local round = g.frame == 21 -- (the swing round reaches behind it too)
            if not player.isDodging and math.abs(py - g.y) < W.reach * 0.7
                and (round and math.abs(px - g.x) < W.reach or (not round and ahead > -10 and ahead < W.reach)) then
                strike(g.x, g.y, W.damage, 160)
            end
            swish(g.x, g.y, 2.1)
        end
        if g.done then
            g.ready = a.time + GUARD.sword.every
            setGuard(g, "come", "walk")
        end
    elseif g.state == "shoot" then
        if g.t < 0.35 then g.facing = dx >= 0 and 1 or -1 end
        if fresh and g.frame == 43 then
            local W = GUARD.bow.arrow
            local mx, my = g.x + g.facing * 30, g.y - 22
            local ax, ay = unit(px - mx, py - 10 - my)
            bullet.new({
                pos = vec2.new(mx, my), dir = vec2.new(ax, ay), speed = W.speed, damage = W.damage,
                radius = W.radius, lifetime = W.lifetime, neon = ARROW_NEON, hostile = true,
            })
            audio.playSoundAt("enemyGun", mx, my, 0.06, 0.25)
        end
        if g.done then
            g.ready = a.time + GUARD.bow.every * (0.8 + a.rng:random() * 0.4)
            setGuard(g, "come", "walk")
        end
    elseif g.state == "reel" then
        if g.done then setGuard(g, "come", "walk") end
    end

    -- keep apart from the rest of the guard, and from her
    if speed > 0 then
        for _, o in ipairs(a.guards) do
            if o ~= g and not o.dying then
                local ox, oy, od = unit(g.x - o.x, g.y - o.y)
                if od < 40 then wx, wy = wx + ox * (1 - od / 40) * 1.5, wy + oy * (1 - od / 40) * 1.5 end
            end
        end
        wx, wy = unit(wx, wy)
    end
    steer(g.body, wx, wy, speed, dt)
    return false
end

--------------------------------------------------------------------------------
-- What she does
--------------------------------------------------------------------------------

local function setState(a, state, anim)
    a.state, a.anim, a.t = state, anim or state, 0
end

-- A pause between moves, on guard (shorter angry)
local function rest(a, s)
    setState(a, "rest", "idle")
    a.restFor = (s or (0.35 + a.rng:random() * 0.4)) * (a.angry and 0.6 or 1)
end

-- A cut: `which` 1 across in front of her, 2 over her head (round her), 3
-- the dash's lunge (further in front)
local function cut(a, which, px, py)
    local reach = which == 3 and DASH.reach or COMBO.reach
    local dx, dy = px - a.x, py - a.y
    local ahead = dx * a.facing
    local hit
    if which == 2 then
        hit = (dx / reach) ^ 2 + (dy / (reach * 0.7)) ^ 2 <= 1
    else
        hit = ahead > -20 and ahead < reach and math.abs(dy) < reach * 0.6
    end
    swish(a.x, a.y, which == 2 and 1.4 or 1.7)
    if hit and not player.isDodging then
        local damage = which == 3 and DASH.damage or COMBO.damage[which]
        strike(a.x, a.y, damage * (a.angry and 1.15 or 1), COMBO.push)
    end
    a.stepT = 0.12 -- a step into it
end

-- Crescents thrown at you: one, or three in a fan
local function throw(a, px, py)
    local ox, oy = a.x + a.facing * 34, a.y
    local base = math.atan2(py - oy, px - ox)
    local n = a.angry and 3 or 1
    for i = 1, n do
        local ang = base + (i - (n + 1) / 2) * WAVE.fan
        a.waves[#a.waves + 1] = { x = ox, y = oy, dx = math.cos(ang), dy = math.sin(ang), life = WAVE.life }
    end
    swish(ox, oy, 1.2)
end

-- The crescents fly: a wall stops one; one through you hurts you once
local function moveWaves(a, dt)
    local px, py = player.body:getPosition()
    for i = #a.waves, 1, -1 do
        local w = a.waves[i]
        local nx, ny = w.x + w.dx * WAVE.speed * dt, w.y + w.dy * WAVE.speed * dt
        w.life = w.life - dt
        if w.life <= 0 or not inSight(w.x, w.y, nx, ny) then
            enemyWeapons.sparks(w.x, w.y - WAVE.height, -w.dx, -w.dy, 8, 1.2, { WAVE_CORE, WAVE_EDGE }, 160, 0.35)
            table.remove(a.waves, i)
        else
            w.x, w.y = nx, ny
            if not w.spent and not player.isDodging
                and (px - w.x) ^ 2 + (py - w.y) ^ 2 < (WAVE.radius + 12) ^ 2 then
                w.spent = true
                player.hurt(WAVE.damage, vec2.new(w.dx, w.dy), "energy")
            end
        end
    end
end

local function think(a, dt)
    local px, py = player.body:getPosition()
    local dx, dy, dist = unit(px - a.x, py - a.y)
    a.t = a.t + dt * (a.angry and ANGRY_PACE or 1)
    local prev = a.frame
    a.frame, a.done = frameOf(ANIMS, a.anim, a.t)
    local fresh = a.frame ~= prev
    local wx, wy, speed = 0, 0, 0
    local s = a.state
    a.lineK = 0
    a.part.weak = s == "reel" and POISE.weak or 1

    -- reeling, and her guard's calls, come first
    a.poise = math.max(0, a.poise - POISE.mend * dt)
    if a.poise >= POISE.limit and s ~= "reel" and s ~= "call" and s ~= "dash" then
        a.poise = 0
        setState(a, "reel")
        s = "reel"
    end
    local nextCall = CALLS[a.called + 1]

    if s == "wait" then
        a.facing = dx >= 0 and 1 or -1
        if dist < SIGHT then
            setState(a, "advance", "run")
            a.waveReady, a.dashReady = a.time + 1.2, a.time + 2.5
            swish(a.x, a.y, 0.8)
        end
    elseif s == "home" then
        -- back to her lair, and on guard there
        local hx, hy, hd = unit(a.homeX - a.x, a.homeY - a.y)
        wx, wy, speed = hx, hy, SPEED
        a.facing = hx >= 0 and 1 or -1
        if hd < 24 then setState(a, "wait", "idle") end
        if dist < SIGHT * 0.8 then setState(a, "advance", "run") end
    elseif s == "advance" or s == "rest" then
        a.facing = dx >= 0 and 1 or -1
        if s == "rest" then
            if a.t >= a.restFor then setState(a, "advance", "run") end
        elseif nextCall and a.health <= a.max_health * nextCall.at then
            setState(a, "call")
            a.calling = nextCall
            a.called = a.called + 1
        elseif dist > GIVE_UP then
            setState(a, "home", "run")
        else
            local wayX, wayY, sight = wayTo(a.x, a.y, px, py)
            if sight and dist < COMBO.reach * 0.85 then
                setState(a, "combo")
            elseif sight and a.time >= a.dashReady and dist > DASH.near and dist < DASH.far
                and a.rng:random() < 0.6 then
                -- the way she'll dash: through you, a little past
                local len = math.min(DASH.far, dist + DASH.over)
                a.dashX, a.dashY, a.dashLeft = dx, dy, len
                a.dashReady = a.time + DASH.every * (0.8 + a.rng:random() * 0.4)
                setState(a, "crouch")
            elseif sight and a.time >= a.waveReady and dist > WAVE.near and dist < WAVE.far then
                a.waveReady = a.time + WAVE.every * (0.8 + a.rng:random() * 0.4)
                setState(a, "throw")
            else
                wx, wy, speed = wayX, wayY, SPEED
            end
        end
        if a.state == "advance" then a.anim = speed > 0 and "run" or "idle" end

    elseif s == "combo" then
        if fresh and a.frame == 19 then cut(a, 1, px, py) end
        if fresh and a.frame == 23 then
            a.facing = dx >= 0 and 1 or -1 -- (the second cut follows you round)
            cut(a, 2, px, py)
        end
        if a.done then rest(a) end
    elseif s == "throw" then
        if a.frame < 19 then a.facing = dx >= 0 and 1 or -1 end
        if fresh and a.frame == 19 then throw(a, px, py) end
        if a.done then rest(a) end

    elseif s == "crouch" then
        -- down low, the way she'll go shown on the street; still aiming
        -- for the first half of it
        if a.t < 0.3 then
            local len = math.min(DASH.far, dist + DASH.over)
            a.dashX, a.dashY, a.dashLeft = dx, dy, len
        end
        a.facing = a.dashX >= 0 and 1 or -1
        a.lineK = math.min(1, a.t / 0.3)
        a.lineX, a.lineY = a.x + a.dashX * a.dashLeft, a.y + a.dashY * a.dashLeft
        if a.done then
            setState(a, "dash")
            a.struck = false
            a.feet:setSensor(true) -- (through you: walls stop her by sight, below)
            swish(a.x, a.y, 1.0)
        end
    elseif s == "dash" then
        local step = DASH.speed * dt
        a.dashLeft = a.dashLeft - step
        -- through you, unless you roll under it
        if not a.struck and not player.isDodging then
            local qx, qy = px - a.x, py - a.y
            local along = qx * a.dashX + qy * a.dashY
            local across = math.abs(qx * a.dashY - qy * a.dashX)
            if along > -FEET_R and along < step + DASH.width and across < DASH.width then
                a.struck = true
                local sx, sy = -a.dashY, a.dashX
                if qx * sx + qy * sy < 0 then sx, sy = -sx, -sy end
                player.hurt(DASH.damage * (a.angry and 1.15 or 1), vec2.new(sx, sy), "blow")
                player.applyKnockback(vec2.new(sx, sy), DASH.push * armor.knockback())
            end
        end
        local reach = step + FEET_R + 4
        if a.dashLeft <= 0 or not inSight(a.x, a.y, a.x + a.dashX * reach, a.y + a.dashY * reach) then
            a.feet:setSensor(false)
            a.body:setLinearVelocity(a.dashX * DASH.lunge, a.dashY * DASH.lunge)
            setState(a, "lunge")
        else
            a.body:setLinearVelocity(a.dashX * DASH.speed, a.dashY * DASH.speed)
        end
        return
    elseif s == "lunge" then
        if fresh and a.frame == 79 then cut(a, 3, px, py) end
        if a.done then rest(a, 0.5) end

    elseif s == "call" then
        if a.t >= 0.4 and a.calling then
            call(a, a.calling.guards)
            a.calling = nil
        end
        if a.t >= CALL_TIME then rest(a, 0.2) end
    elseif s == "reel" then
        if a.done then rest(a, 0.25) end
    end

    -- a step into a cut
    if a.stepT and a.stepT > 0 then
        a.stepT = a.stepT - dt
        wx, wy, speed = a.facing, 0, COMBO.step
    end
    steer(a.body, wx, wy, speed * (a.angry and ANGRY_PACE or 1), dt)
end

-- Fallen: she stays down, and her guard falls with her
local function die(a, dt)
    a.dying = a.dying + dt
    a.t = a.t + dt
    a.frame = frameOf(ANIMS, "death", a.t)
    if a.dying >= DEATH_TIME then
        explosion.create(a.x, a.y - 20, explosion.TYPES.IMPLOSION) -- (the wave alone)
        audio.playSoundAt("explosion", a.x, a.y, 0.1, 0.6)
        camera.shake(7, 0.35)
        castellan.despawnInst(a)
    end
end

-- Her crescents light the street as they fly
local function addLights(a)
    for _, w in ipairs(a.waves) do shadow.addTransientLight(w.x, w.y, 0.35, 90) end
end

--- Each frame, before the lighting upload: where the world runs, she and
--- her guard think and move; everywhere, her crescents light the street.
function castellan.update(dt)
    if hosting() then
        for i = #castellan.live, 1, -1 do
            local a = castellan.live[i]
            a.time = a.time + dt
            a.flash = math.max(0, a.flash - dt)
            if not a.dying then a.x, a.y = a.body:getPosition() end
            if not a.dying and a.health <= 0 then
                -- down: no more hits, and her guard falls with her
                a.dying, a.lineK, a.waves = 0, 0, {}
                bosses.unregister(a.part)
                a.body:destroy()
                for _, g in ipairs(a.guards) do
                    if not g.dying then killGuard(g) end
                end
                setState(a, "dead", "death")
                swish(a.x, a.y, 0.7)
            end
            if a.dying then
                die(a, dt)
            elseif player and player.body then
                a.angry = a.health <= a.max_health * 0.5
                think(a, dt)
                moveWaves(a, dt)
            end
            if not a.gone and player and player.body then
                local px, py = player.body:getPosition()
                for j = #a.guards, 1, -1 do
                    if guardThink(a, a.guards[j], dt, px, py) then table.remove(a.guards, j) end
                end
                addLights(a)
            end
        end
    else
        for _, a in ipairs(castellan.net) do
            a.time = a.time + dt
            addLights(a)
        end
    end
end

--------------------------------------------------------------------------------
-- Network
--------------------------------------------------------------------------------

--- Host: what clients need to draw each of them
function castellan.getNetworkData()
    local list = {}
    for i, a in ipairs(castellan.live) do
        local guards, waves = {}, {}
        for j, g in ipairs(a.guards) do
            guards[j] = { x = g.x, y = g.y, fr = g.frame, fc = g.facing, al = g.fade, f = g.flash }
        end
        for j, w in ipairs(a.waves) do waves[j] = { x = w.x, y = w.y, dx = w.dx, dy = w.dy } end
        list[i] = {
            x = a.x, y = a.y, h = a.health, m = a.max_health, fr = a.frame, fc = a.facing, f = a.flash,
            an = a.angry or nil, d = a.dying, lk = a.lineK, lx = a.lineX, ly = a.lineY,
            guards = guards, waves = waves,
        }
    end
    return list
end

--- Client: each of them as the host sent them
function castellan.applyNetworkData(list)
    local net = {}
    for i, d in ipairs(list or {}) do
        needArt()
        local a = castellan.net[i] or shell()
        a.x, a.y, a.health, a.max_health = d.x, d.y, d.h, d.m
        a.frame, a.facing, a.flash, a.angry, a.dying = d.fr, d.fc, d.f or 0, d.an, d.d
        a.lineK, a.lineX, a.lineY = d.lk or 0, d.lx, d.ly
        a.guards, a.waves = {}, {}
        for j, g in ipairs(d.guards or {}) do
            a.guards[j] = { x = g.x, y = g.y, frame = g.fr, facing = g.fc, fade = g.al, flash = g.f or 0 }
        end
        for j, w in ipairs(d.waves or {}) do a.waves[j] = { x = w.x, y = w.y, dx = w.dx, dy = w.dy } end
        net[i] = a
    end
    castellan.net = net
end

--------------------------------------------------------------------------------
-- Drawing (lib/graphics/renderer.lua hands each piece to castellan.drawPiece)
--------------------------------------------------------------------------------

-- On the ground, under everything: shadows, and the line she'll dash along
local function drawGround(a)
    love.graphics.setColor(0, 0, 0, 0.32)
    love.graphics.ellipse("fill", a.x, a.y + 2, 30, 11)
    for _, g in ipairs(a.guards) do
        love.graphics.setColor(0, 0, 0, 0.28 * (g.fade or 1))
        love.graphics.ellipse("fill", g.x, g.y + 1, 15, 6)
    end
    if a.lineK > 0 and a.lineX then
        local pulse = 0.6 + 0.4 * math.abs(math.sin(a.time * 16))
        love.graphics.setBlendMode("add")
        love.graphics.setLineWidth(DASH.width * 2)
        love.graphics.setColor(0.45, 0.2, 0.6, 0.22 * a.lineK * pulse)
        love.graphics.line(a.x, a.y, a.lineX, a.lineY)
        love.graphics.setLineWidth(2)
        love.graphics.setColor(0.85, 0.7, 1, 0.8 * a.lineK * pulse)
        love.graphics.line(a.x, a.y, a.lineX, a.lineY)
        love.graphics.setBlendMode("alpha")
        love.graphics.setLineWidth(1)
    end
end

local function drawHer(a)
    local quad = art.frames[a.frame or 0]
    local f = a.flash > 0 and 0.55 or 0
    love.graphics.setColor(1, 1 - f, 1 - f, 1)
    love.graphics.draw(art.sheet, quad, a.x, a.y, 0, PX * a.facing, PX, FOOT_X, FOOT_Y)
    if a.angry and not a.dying then
        -- violet with fury, over whatever lights her
        local k = 0.6 + 0.4 * math.sin(a.time * 5)
        love.graphics.setShader()
        love.graphics.setBlendMode("add")
        love.graphics.setColor(FURY[1] * k, FURY[2] * k, FURY[3] * k, 1)
        love.graphics.draw(art.sheet, quad, a.x, a.y, 0, PX * a.facing, PX, FOOT_X, FOOT_Y)
        love.graphics.setBlendMode("alpha")
    end
end

local function drawGuard(g)
    local f = (g.flash or 0) > 0 and 0.55 or 0
    love.graphics.setColor(1, 1 - f, 1 - f, g.fade or 1)
    love.graphics.draw(art.guard, art.guardFrames[g.frame or 0], g.x, g.y, 0, PX * (g.facing or 1), PX,
        GFOOT_X, GFOOT_Y)
end

-- The crescents in flight, glowing (after everything: they're in the air)
local function drawWaves(a)
    love.graphics.setShader()
    love.graphics.setBlendMode("add")
    for _, w in ipairs(a.waves) do
        local x, y = w.x, w.y - WAVE.height
        love.graphics.setColor(WAVE_EDGE[1] * 0.4, WAVE_EDGE[2] * 0.4, WAVE_EDGE[3] * 0.4, 1)
        love.graphics.draw(regions.glow, x - 50, y - 50, 0, 100 / 64, 100 / 64)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(art.crescent, x, y, math.atan2(w.dy, w.dx), 2.5, 2.5, CW / 2, CH / 2)
    end
    love.graphics.setBlendMode("alpha")
end

--- One piece of her, from the sorted list: her and her guard lit like
--- everything else; her crescents glowing over it all
function castellan.drawPiece(d)
    local a = d.boss
    local shader = love.graphics.getShader()
    if d.piece == "ground" then
        love.graphics.setShader()
        drawGround(a)
    elseif d.piece == "her" then
        drawHer(a)
    elseif d.piece == "guard" then
        drawGuard(d.guard)
    elseif d.piece == "waves" then
        drawWaves(a)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(shader)
end

--- Each one on screen into the dynamic draw list: her and each guard sorted
--- by where they stand
function castellan.populate()
    local x0, y0, x1, y1 = regions.view(400)
    for _, a in ipairs(hosting() and castellan.live or castellan.net) do
        if a.x > x0 and a.x < x1 and a.y > y0 and a.y < y1 then
            local list = dynamic_draw_list
            list[#list + 1] = { sort_y = -1e9, draw_type = "castellan", boss = a, piece = "ground" }
            list[#list + 1] = { sort_y = a.y + SORT, draw_type = "castellan", boss = a, piece = "her" }
            for _, g in ipairs(a.guards) do
                list[#list + 1] = { sort_y = g.y + SORT, draw_type = "castellan", boss = a, piece = "guard", guard = g }
            end
            if #a.waves > 0 then
                list[#list + 1] = { sort_y = renderer.ON_TOP, draw_type = "castellan", boss = a, piece = "waves" }
            end
        end
    end
end

return castellan
