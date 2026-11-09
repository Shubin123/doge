--[[
  Neon City's boss (game/bosses.lua's "arm"): a robotic arm bolted to the
  street at its lair, in front of the holo billboard.

  Its parts are two-bone IK chains (ik2: the law of cosines, the middle
  joint bent to one side):
    the arm    shoulder, elbow and wrist, solved in the upright plane through
               its base and where the claw's going, so it turns on its base,
               rears up and reaches like the real thing; the hand pitched at
               the end, a hydraulic ram across the elbow
    the claw   two fingers, knuckle and tip, reaching for points that spread
               open or close together
    the guns   two small arms on the base, each holding a barrel out at you
  A point here is on the ground plane with a height z over it: (x, y, z)
  draws at (x, y - z), and each piece sorts by the ground under it, so the
  arm passes behind and in front of what stands round it as it swings.

  What it does, where the world runs (host, single player; clients draw it
  where the host says):
    rest    folded down until you come within SIGHT
    track   the claw hovers between it and you, swinging after you
    slam    it rears up over you (a ring shows where it'll land), comes down
            hard, and stays down a moment: its claw, the weak point, takes
            far more while it's stuck
    sweep   down to the street at one side of you and across through you;
            a roll goes under it
    grab    the claw opens and lunges: caught, you're held and squeezed,
            then thrown. Hurt the claw enough and it lets go
    guns    all the while it's awake, bolts at you; quicker once it's half
            broken, when its neon turns red
  Its parts (bosses.lua) are a static body for the base and kinematic
  sensors the arm carries where it's drawn, so what you see is what you hit.
  The art is baked at load, in texels of PX world px.
]]
local robotArm = {}

local nav = require("lib.nav")

robotArm.NAME = "ASSEMBLY ARM"
robotArm.arms = {} -- the live ones, where the world runs
robotArm.net = {}  -- as the host sent them (clients)

local PX = 2             -- world px per texel of its art
local SORT = 105         -- sort_y past the ground line (as region sprites')
local BASE_R = 34        -- the pedestal's footprint (its static body)
local SHOULDER_Z = 58    -- the shoulder's height, on the turntable
local SHOULDER_OUT = 6   -- and how far out from the middle, toward the claw
local UPPER, FORE = 132, 118 -- shoulder to elbow, elbow to wrist
local HAND = 24          -- wrist to where the fingers close
local MIN_REACH = 72     -- nearest the claw comes to the base, over the ground
local REACH = 250        -- and furthest
local FINGER = { 14, 12 } -- knuckle, tip
local GUN = { 22, 18 }
local GUN_ROOT = { 30, 40 } -- a gun arm's shoulder: either side of the base, and up
local HEALTH = 300       -- (a pistol shot is 1, a rocket up to 45)
local SIGHT = 620        -- px: this close, it wakes
local GUN_RANGE = 560

local SLAM = { rise = 0.55, hold = 0.42, strike = 0.11, stuck = 0.75, radius = 58, damage = 160 }
local SWEEP = { wind = 0.5, swing = 0.62, recover = 0.4, reach = 40, damage = 120, arc = 2.4 }
local GRAB = { open = 0.45, lunge = 0.16, hold = 1.1, missed = 0.5, recover = 0.5, reach = 38,
    dps = 60, throw = 50, speed = 650, breakFree = 25 }
local BOLT = { speed = 430, damage = 18, radius = 4, lifetime = 1.6, every = 0.95, angry = 0.45 }
local MOVES = { "slam", "slam", "slam", "sweep", "sweep", "grab", "grab" }
-- what each part takes of a hit; the claw stuck in the street, `exposed`
local WEAK = { base = 0.6, upper = 0.75, fore = 0.75, claw = 1.5, exposed = 3 }
-- the sensors it carries: along a bone (from, to, k of the way), at a joint, or fixed
local SENSORS = {
    { name = "upper", from = "shoulder", to = "elbow", k = 0.2, r = 15 },
    { name = "upper", from = "shoulder", to = "elbow", k = 0.5, r = 15 },
    { name = "upper", from = "shoulder", to = "elbow", k = 0.8, r = 15 },
    { name = "fore", from = "elbow", to = "wrist", k = 0.25, r = 13 },
    { name = "fore", from = "elbow", to = "wrist", k = 0.55, r = 13 },
    { name = "fore", from = "elbow", to = "wrist", k = 0.85, r = 13 },
    { name = "claw", joint = "palm", r = 18 },
    { name = "base", top = true, r = 26 }, -- the turret, over its footprint
}
local DEATH = { { 0.1, "palm" }, { 0.35, "wrist" }, { 0.6, "elbow" }, { 0.85, "shoulder" } }
local DEATH_TIME = 1.3

local CALM = { 0.25, 0.95, 1.0 }  -- its neon, fighting
local ANGRY = { 1.0, 0.22, 0.42 } -- and half broken
local BOLT_NEON = { core = { 0.7, 1.0, 1.0 }, halo = { 0.1, 0.8, 1.0 }, radius = 12 }
local ANGRY_NEON = { core = { 1.0, 0.7, 0.8 }, halo = { 1.0, 0.1, 0.35 }, radius = 12 }

--------------------------------------------------------------------------------
-- Two-bone IK
--------------------------------------------------------------------------------

-- From a root to a target (dx, dy) with bones a and b, the middle joint on
-- side `bend` (+1: counter-clockwise of the line to the target). Out of
-- reach the chain straightens toward it. The middle joint and the end,
-- relative to the root.
local function ik2(dx, dy, a, b, bend)
    local far, near = (a + b) * 0.999, math.abs(a - b) + 0.001
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 1e-6 then dx, dy, d = near, 0, near end
    local k = math.max(near, math.min(far, d)) / d
    dx, dy, d = dx * k, dy * k, d * k
    local A = math.acos(math.max(-1, math.min(1, (a * a + d * d - b * b) / (2 * a * d))))
    local angle = math.atan2(dy, dx) + bend * A
    return math.cos(angle) * a, math.sin(angle) * a, dx, dy
end

-- ik2 on the screen from (rx, ry) to (tx, ty), the middle joint toward (sx, sy)
local function ik2Toward(rx, ry, tx, ty, a, b, sx, sy)
    local dx, dy = tx - rx, ty - ry
    local mx, my, ex, ey = ik2(dx, dy, a, b, dx * sy - dy * sx >= 0 and 1 or -1)
    return rx + mx, ry + my, rx + ex, ry + ey
end

local function unit(x, y)
    local l = math.sqrt(x * x + y * y)
    if l < 1e-6 then return 1, 0 end
    return x / l, y / l
end

-- Where everything is, from where the claw closes (a.cx, a.cy over the
-- ground, a.cz up), the hand's pitch in the arm's plane (0 out, -pi/2
-- down), its grip (0 open, 1 shut) and the guns' aims: each joint's ground
-- point (gx, gy), height (z) and where it draws (x, y)
local function solve(a)
    local dx, dy = a.cx - a.x, a.cy - a.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d > 1e-3 then a.ux, a.uy = dx / d, dy / d end
    local ux, uy = a.ux, a.uy
    local hx, hz = math.cos(a.pitch) * HAND, math.sin(a.pitch) * HAND
    -- the arm in its plane: out along (ux, uy) over the ground, and up
    local ex, ez, wx, wz = ik2(d - SHOULDER_OUT - hx, a.cz - SHOULDER_Z - hz, UPPER, FORE, 1)
    local J = a.joints
    local function at(j, out, z)
        j.gx, j.gy, j.z = a.x + ux * out, a.y + uy * out, z
        j.x, j.y = j.gx, j.gy - z
    end
    at(J.shoulder, SHOULDER_OUT, SHOULDER_Z)
    at(J.elbow, SHOULDER_OUT + ex, SHOULDER_Z + ez)
    at(J.wrist, SHOULDER_OUT + wx, SHOULDER_Z + wz)
    at(J.grip, SHOULDER_OUT + wx + hx, math.max(0, SHOULDER_Z + wz + hz))

    -- the claw on the screen: the palm, and the fingers on it reaching for
    -- tips spread open or shut together
    local hsx, hsy = J.grip.x - J.wrist.x, J.grip.y - J.wrist.y
    local hl = math.sqrt(hsx * hsx + hsy * hsy)
    if hl < 6 then -- (the hand end on to you: along the forearm instead)
        hsx, hsy = J.wrist.x - J.elbow.x, J.wrist.y - J.elbow.y
        hl = HAND
    end
    local hux, huy = unit(hsx, hsy)
    a.hand.x, a.hand.y = hux, huy
    local nx, ny = -huy, hux
    J.palm.x, J.palm.y = J.wrist.x + hux * hl * 0.4, J.wrist.y + huy * hl * 0.4
    local open = 1 - a.grip
    for i, s in ipairs({ -1, 1 }) do
        local f = J.fingers[i]
        f.rx, f.ry = J.palm.x + hux * 5 + nx * s * 6, J.palm.y + huy * 5 + ny * s * 6
        local tx = J.grip.x + hux * 7 * open + nx * s * (1.5 + 12 * open)
        local ty = J.grip.y + huy * 7 * open + ny * s * (1.5 + 12 * open)
        f.kx, f.ky, f.tx, f.ty = ik2Toward(f.rx, f.ry, tx, ty, FINGER[1], FINGER[2], nx * s, ny * s)
    end

    -- the guns: each holds its barrel out along its aim, kicked back by a shot
    for i, s in ipairs({ -1, 1 }) do
        local g = a.guns[i]
        g.rx, g.ry = a.x + s * GUN_ROOT[1], a.y - GUN_ROOT[2]
        local out = 30 - 8 * (g.kick or 0)
        local tx, ty = g.rx + math.cos(g.aim) * out + s * 4, g.ry + math.sin(g.aim) * out - 10
        g.kx, g.ky, g.ex, g.ey = ik2Toward(g.rx, g.ry, tx, ty, GUN[1], GUN[2], s * 0.7, -0.7)
        g.mx, g.my = g.ex + math.cos(g.aim) * 20, g.ey + math.sin(g.aim) * 20 -- the muzzle
    end
end

--------------------------------------------------------------------------------
-- Art, baked at load: each piece's body (lit) and its neon (glowing, tinted)
--------------------------------------------------------------------------------

local K = { 0.05, 0.05, 0.08 } -- outline
local D = { 0.13, 0.14, 0.19 } -- dark metal
local M = { 0.25, 0.27, 0.34 } -- metal
local L = { 0.43, 0.46, 0.55 } -- light metal
local H = { 0.68, 0.72, 0.80 } -- highlight
local Y = { 0.96, 0.74, 0.14 } -- hazard yellow
local GLOW = { 1, 1, 1 }
local art

local function bake(w, h, fn)
    local data = love.image.newImageData(w, h)
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local c = fn(x, y)
            if c then data:setPixel(x, y, c[1], c[2], c[3], 1) end
        end
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    return image
end

-- A bone `len` texels joint to joint and `thick` across, rounded over its
-- joints: plated and riveted, hazard stripes by its ends, a neon strip
local function limb(len, thick, stripes)
    local r = thick / 2
    local function edge(x, y)
        local cx = math.max(r, math.min(len + r, x + 0.5))
        return math.sqrt((x + 0.5 - cx) ^ 2 + (y + 0.5 - r) ^ 2)
    end
    local body = bake(len + thick, thick, function(x, y)
        local d = edge(x, y)
        if d > r then return nil end
        if d > r - 1 then return K end
        local v, u = (y + 0.5) / thick, x - r
        local c = v < 0.25 and H or v < 0.42 and L or v < 0.78 and M or D
        if u > 3 and u < len - 3 then
            if u % 14 == 0 then c = D end -- panel seams
            if (u % 14 == 3 or u % 14 == 11) and y == math.floor(thick * 0.3) then c = H end -- rivets
        end
        if stripes and v >= 0.42 and v < 0.78 and ((u >= 2 and u < 8) or (u > len - 8 and u <= len - 2)) then
            c = (x + y) % 4 < 2 and Y or K
        end
        return c
    end)
    local glow = bake(len + thick, thick, function(x, y)
        local u = x - r
        if y == math.floor(thick * 0.6) and u >= 10 and u <= len - 10 and u % 14 ~= 0 then return GLOW end
    end)
    return { body = body, glow = glow, len = len, r = r }
end

-- A joint's disc, `size` across: a rim lit from the top left, a pin, a lit ring
local function disc(size)
    local r = size / 2
    local function at(x, y) return x + 0.5 - r, y + 0.5 - r end
    local body = bake(size, size, function(x, y)
        local dx, dy = at(x, y)
        local q = math.sqrt(dx * dx + dy * dy)
        if q > r then return nil end
        if q > r - 1 then return K end
        if q < 1.2 then return H end
        if q < 2.2 then return D end
        if q > r - 2 then return dx + dy < 0 and L or D end
        return dx + dy < -1 and L or M
    end)
    local glow = bake(size, size, function(x, y)
        local dx, dy = at(x, y)
        local q = math.sqrt(dx * dx + dy * dy)
        if size > 7 and q >= 2.2 and q < 3.1 then return GLOW end
    end)
    return { body = body, glow = glow, r = r }
end

-- The pedestal, 40 x 44 texels, standing on (20, 38): a footing plate bolted
-- to the street, a ribbed column with a hazard band, a turntable on top; its
-- face (two eyes in a window) and a band of lights
local BASE_W, BASE_H, BASE_AX, BASE_AY = 40, 44, 20, 38
local function pedestal()
    local function ell(x, y, cx, cy, rx, ry)
        return ((x + 0.5 - cx) / rx) ^ 2 + ((y + 0.5 - cy) / ry) ^ 2
    end
    local body = bake(BASE_W, BASE_H, function(x, y)
        local top = ell(x, y, 20, 12, 12.5, 4.5)
        if top <= 1 then
            if top > 0.78 then return K end
            local hub = ell(x, y, 20, 12, 5, 1.8)
            if hub <= 1 then return hub > 0.6 and K or D end
            if top > 0.5 and top < 0.62 then return M end -- the turntable's ring
            return x < 20 and H or L
        end
        if x >= 8 and x < 32 and y >= 12 and y < 38 then
            if x == 8 or x == 31 then return K end
            local s = (x + 0.5 - 20) / 12 -- across the column, -1 to 1
            local c = s < -0.6 and D or s < -0.15 and M or s < 0.35 and L or s < 0.7 and M or D
            if (x == 13 or x == 26) and y > 14 and y < 29 then c = D end -- ribs
            if y == 30 or y == 35 then c = K elseif y > 30 and y < 35 then c = (x + y) % 4 < 2 and Y or K end
            if x >= 16 and x < 24 and y >= 17 and y < 23 then -- the window
                c = (x == 16 or x == 23 or y == 17 or y == 22) and K or D
            end
            return c
        end
        local f = ell(x, y, 20, 38, 19.5, 5.5)
        if f <= 1 then
            if f > 0.8 then return K end
            if ((y == 38 or y == 39) and (x == 3 or x == 36)) or (y == 41 and (x == 10 or x == 29)) then return H end
            return y < 37 and M or D
        end
    end)
    local glow = bake(BASE_W, BASE_H, function(x, y)
        if (y == 19 or y == 20) and (x == 18 or x == 21) then return GLOW end -- eyes
        if y == 27 and x >= 10 and x <= 30 and x % 3 == 1 then return GLOW end -- lights
    end)
    return { body = body, glow = glow }
end

-- The palm, 12 x 12 texels about its middle, pointing along +x: a block
-- with its corners cut and a lens (the weak point)
local function palm()
    local body = bake(12, 12, function(x, y)
        local dx, dy = x + 0.5 - 6, y + 0.5 - 6
        local m = math.abs(dx) + math.abs(dy)
        if math.abs(dx) > 5.5 or math.abs(dy) > 5.5 or m > 9 then return nil end
        if math.abs(dx) > 4.5 or math.abs(dy) > 4.5 or m > 8 then return K end
        local q = math.sqrt((dx - 1) ^ 2 + dy ^ 2)
        if q < 2.6 then return q > 1.8 and K or D end
        return dy < -1.5 and L or dy < 2 and M or D
    end)
    local glow = bake(12, 12, function(x, y)
        if math.sqrt((x + 0.5 - 7) ^ 2 + (y + 0.5 - 6) ^ 2) < 1.8 then return GLOW end
    end)
    return { body = body, glow = glow }
end

-- A gun's barrel, 10 x 5 texels along +x from its breech, the muzzle lit
local function barrel()
    local body = bake(10, 5, function(x, y)
        if y == 0 or y == 4 or x == 9 then return K end
        if x < 2 then return D end
        return y == 1 and H or y == 2 and L or M
    end)
    local glow = bake(10, 5, function(x, y)
        if x == 9 and y >= 1 and y <= 3 then return GLOW end
    end)
    return { body = body, glow = glow }
end

function robotArm.load()
    art = {
        upper = limb(UPPER / PX, 14, true),
        fore = limb(FORE / PX, 12, true),
        finger = limb(FINGER[1] / PX, 4),
        tip = limb(FINGER[2] / PX, 4),
        gun = limb(GUN[1] / PX, 5),
        gunTip = limb(GUN[2] / PX, 5),
        joint = disc(11),
        wrist = disc(9),
        pin = disc(5),
        base = pedestal(),
        palm = palm(),
        barrel = barrel(),
    }
    robotArm.arms, robotArm.net = {}, {}
end

--------------------------------------------------------------------------------
-- Life and death
--------------------------------------------------------------------------------

local function hosting()
    return not var.multiplayer or var.multiplayer == 1
end

-- An arm's state as it's drawn (the host's arms, and clients' copies)
local function shell()
    return {
        joints = { shoulder = {}, elbow = {}, wrist = {}, grip = {}, palm = {}, fingers = { {}, {} } },
        guns = { { aim = math.pi * 0.6, kick = 0 }, { aim = math.pi * 0.4, kick = 0 } },
        hand = { x = 1, y = 0 }, ux = 0, uy = 1, time = 0, flash = 0, ringK = 0, ringX = 0, ringY = 0,
    }
end

-- A hit on one of its parts (bosses.hit has scaled it by the part's weakness)
local function hurt(a, damage)
    if a.dying or a.gone then return end
    a.health = math.max(0, a.health - damage)
    a.flash = 0.12
    if a.state == "held" then a.holdHits = a.holdHits + damage end
end

local function addPart(a, body, fixture, radius, name)
    local part = { type = "boss", boss = a, body = body, radius = radius, name = name, weak = WEAK[name], hit = hurt }
    fixture:setUserData(part)
    fixture:setGroupIndex(-888) -- (bosses' group: game/boss.lua's bear is in it too)
    bosses.register(part)
    a.parts[#a.parts + 1] = part
    if name == "claw" then a.clawPart = part end
    return part
end

-- Carry the sensors to where the arm is drawn
local function placeSensors(a)
    local J = a.joints
    for _, s in ipairs(a.sensors) do
        local d = s.def
        local x, y
        if d.joint then
            x, y = J[d.joint].x, J[d.joint].y
        elseif d.top then
            x, y = a.x, a.y - 40
        else
            local p, q = J[d.from], J[d.to]
            x, y = p.x + (q.x - p.x) * d.k, p.y + (q.y - p.y) * d.k
        end
        s.body:setPosition(x, y)
    end
end

--- A new arm bolted down at (x, y); `lair`, the region it guards (game/bosses.lua)
function robotArm.spawnAt(x, y, lair)
    local a = shell()
    a.x, a.y, a.lair = x, y, lair
    a.health, a.max_health = HEALTH, HEALTH
    a.cx, a.cy, a.cz, a.pitch, a.grip = x, y + 80, 30, -1.3, 0.7
    a.state, a.t, a.dur = "rest", 0, 0
    a.gunT, a.gunNext, a.holdHits = 1.5, 1, 0
    a.rng = love.math.newRandomGenerator(math.floor(x * 3 + y) % 100000 + 1)
    a.parts, a.sensors = {}, {}
    a.body = love.physics.newBody(world, x, y, "static")
    a.fixture = love.physics.newFixture(a.body, love.physics.newCircleShape(BASE_R))
    addPart(a, a.body, a.fixture, BASE_R, "base")
    for _, d in ipairs(SENSORS) do
        local body = love.physics.newBody(world, x, y, "kinematic")
        local f = love.physics.newFixture(body, love.physics.newCircleShape(d.r))
        f:setSensor(true)
        a.sensors[#a.sensors + 1] = { def = d, body = body, part = addPart(a, body, f, d.r, d.name) }
    end
    nav.forget(x - BASE_R, y - BASE_R, x + BASE_R, y + BASE_R) -- (enemies and the car go round it)
    solve(a)
    placeSensors(a)
    robotArm.arms[#robotArm.arms + 1] = a
    return a
end

function robotArm.alive(a)
    return not a.gone
end

-- Let go of you
local function release(a)
    a.holding = false
end

--- Take arm `a` away. One that was dying is beaten (bosses.defeated), but
--- `quiet`ly (a save being loaded) it just goes.
function robotArm.despawnInst(a, quiet)
    if a.gone then return end
    a.gone = true
    for i, other in ipairs(robotArm.arms) do
        if other == a then
            table.remove(robotArm.arms, i)
            break
        end
    end
    for _, p in ipairs(a.parts) do bosses.unregister(p) end
    for _, s in ipairs(a.sensors) do s.body:destroy() end
    a.body:destroy()
    nav.forget(a.x - BASE_R, a.y - BASE_R, a.x + BASE_R, a.y + BASE_R)
    release(a)
    if a.dying and not quiet then bosses.defeated(a.lair, a.x, a.y + BASE_R + 16) end
end

function robotArm.despawnAll()
    for i = #robotArm.arms, 1, -1 do robotArm.despawnInst(robotArm.arms[i], true) end
end

--- fn(arm) for each live arm (here, or as the host sent them)
function robotArm.eachLive(fn)
    for _, a in ipairs(hosting() and robotArm.arms or robotArm.net) do fn(a) end
end

--------------------------------------------------------------------------------
-- What it does
--------------------------------------------------------------------------------

local function ease(v, target, rate, dt)
    return v + (target - v) * (1 - math.exp(-rate * dt))
end

-- Ease the claw toward (x, y, z) at `rate`
local function toward(a, x, y, z, rate, dt)
    a.cx, a.cy, a.cz = ease(a.cx, x, rate, dt), ease(a.cy, y, rate, dt), ease(a.cz, z, rate, dt)
end

local function turnToward(angle, target, step)
    local d = (target - angle + math.pi) % (2 * math.pi) - math.pi
    return angle + math.max(-step, math.min(step, d))
end

-- (x, y) brought into the ring round the base the claw reaches over the
-- ground, lo to hi from its middle
local function inReach(a, x, y, lo, hi)
    lo, hi = lo or MIN_REACH, hi or REACH
    local dx, dy = x - a.x, y - a.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 1e-3 then dx, dy, d = a.ux, a.uy, 1 end
    local k = math.max(lo, math.min(math.max(lo, hi), d)) / d
    return a.x + dx * k, a.y + dy * k
end

local function setState(a, state, dur)
    a.state, a.t, a.dur = state, 0, dur * (a.angry and 0.75 or 1)
end

-- Come down: what's under it is hit, the street shakes
local function impact(a)
    local x, y = a.ringX, a.ringY
    local px, py = player.body:getPosition()
    local d = math.sqrt((px - x) ^ 2 + (py - y) ^ 2)
    if d < SLAM.radius + 10 then
        player.hurt(SLAM.damage * (a.angry and 1.2 or 1), vec2.new((px - x) / (d + 0.1), (py - y) / (d + 0.1)), "blow")
    end
    explosion.create(x, y, explosion.TYPES.IMPLOSION) -- the wave alone
    enemyWeapons.sparks(x, y, 0, -1, 26, math.pi, { { 1, 0.9, 0.55 }, a.angry and ANGRY or CALM }, 280, 0.5)
    local src = audio.playSoundAt("explosion", x, y, 0.1, 0.5)
    if src then src:setPitch(0.75) end
    camera.shake(7, 0.3)
end

-- One of its moves, at you (px, py), `dist` from its base
local function start(a, move, px, py, dist)
    a.last = move
    if move == "slam" then
        a.ringX, a.ringY = inReach(a, px, py)
        setState(a, "rise", SLAM.rise)
    elseif move == "sweep" then
        a.side = a.rng:random() < 0.5 and -1 or 1
        a.radius = math.max(MIN_REACH + 20, math.min(REACH - 10, dist))
        a.from = math.atan2(py - a.y, px - a.x) - a.side * SWEEP.arc / 2
        a.struck = false
        setState(a, "wind", SWEEP.wind)
    else
        setState(a, "open", GRAB.open)
    end
end

local function think(a, dt)
    local px, py = player.body:getPosition()
    local dist = math.sqrt((px - a.x) ^ 2 + (py - a.y) ^ 2)
    a.t = a.t + dt
    local k = math.min(1, a.t / math.max(1e-3, a.dur))
    local s = a.state
    a.ringK = 0
    a.clawPart.weak = s == "stuck" and WEAK.exposed or WEAK.claw

    if s == "rest" then
        -- folded down in front of its base, breathing
        toward(a, a.x + a.ux * 80, a.y + a.uy * 80, 30 + math.sin(a.time * 1.3) * 4, 2, dt)
        a.pitch, a.grip = ease(a.pitch, -1.3, 3, dt), ease(a.grip, 0.7, 3, dt)
        if dist < SIGHT then
            setState(a, "track", 0.9)
            local src = audio.playSoundAt("explosion", a.x, a.y, 0.05, 0.4)
            if src then src:setPitch(0.5) end
        end
    elseif s == "track" then
        local tx, ty = inReach(a, px, py, MIN_REACH + 10, math.min(REACH * 0.75, dist - 70))
        toward(a, tx, ty, 90 + math.sin(a.time * 2.1) * 10, 3.5, dt)
        a.pitch, a.grip = ease(a.pitch, -0.5, 4, dt), ease(a.grip, 0.35, 4, dt)
        if dist > SIGHT * 1.3 then
            setState(a, "rest", 0)
        elseif k >= 1 then
            if dist <= REACH + 30 then
                local move = MOVES[a.rng:random(#MOVES)]
                if move == a.last then move = MOVES[a.rng:random(#MOVES)] end
                if move == "grab" and player.inCar then move = "slam" end
                start(a, move, px, py, dist)
            else
                a.t = 0 -- out of reach: its guns do the work
            end
        end

    -- Slam: up over you, a moment's aim, down
    elseif s == "rise" then
        local tx, ty = inReach(a, px, py)
        a.ringX, a.ringY = ease(a.ringX, tx, 5, dt), ease(a.ringY, ty, 5, dt)
        toward(a, a.ringX, a.ringY, 150, 6, dt)
        a.pitch, a.grip = ease(a.pitch, -1.45, 5, dt), ease(a.grip, 1, 6, dt)
        a.ringK = 0.35
        if k >= 1 then setState(a, "hold", SLAM.hold) end
    elseif s == "hold" then
        toward(a, a.ringX, a.ringY, 160, 8, dt)
        a.ringK = 0.6 + 0.4 * math.abs(math.sin(a.time * 18))
        if k >= 1 then
            a.fromZ = a.cz
            setState(a, "strike", SLAM.strike)
        end
    elseif s == "strike" then
        a.cx, a.cy = ease(a.cx, a.ringX, 30, dt), ease(a.cy, a.ringY, 30, dt)
        a.cz = a.fromZ * (1 - k * k)
        a.ringK = 1
        if k >= 1 then
            a.cz = 0
            impact(a)
            setState(a, "stuck", SLAM.stuck)
        end
    elseif s == "stuck" then
        toward(a, a.ringX + math.sin(a.time * 40) * 1.5, a.ringY, 0, 10, dt)
        if k >= 1 then setState(a, "recover", 0.5) end

    -- Sweep: down at one side of you, across through you
    elseif s == "wind" then
        toward(a, a.x + math.cos(a.from) * a.radius, a.y + math.sin(a.from) * a.radius, 16, 7, dt)
        a.pitch, a.grip = ease(a.pitch, -0.15, 6, dt), ease(a.grip, 0.85, 6, dt)
        if k >= 1 then setState(a, "swing", SWEEP.swing) end
    elseif s == "swing" then
        local angle = a.from + a.side * SWEEP.arc * k * k * (3 - 2 * k)
        a.cx, a.cy, a.cz = a.x + math.cos(angle) * a.radius, a.y + math.sin(angle) * a.radius, 14
        local tx, ty = -math.sin(angle) * a.side, math.cos(angle) * a.side -- the way it's going
        if not a.struck and not player.isDodging
            and (px - a.cx) ^ 2 + (py - a.cy) ^ 2 < SWEEP.reach * SWEEP.reach then
            a.struck = true
            player.hurt(SWEEP.damage * (a.angry and 1.2 or 1), vec2.new(tx, ty), "blow")
            player.applyKnockback(vec2.new(tx, ty), 420 * armor.knockback())
        end
        enemyWeapons.sparks(a.cx, a.cy, -tx, -ty, 1, 0.6, { { 1, 0.85, 0.4 }, { 1, 1, 0.8 } }, 160, 0.3)
        if k >= 1 then setState(a, "recover", SWEEP.recover) end

    -- Grab: open, lunge, and hold on to what it caught
    elseif s == "open" then
        local tx, ty = inReach(a, px, py, MIN_REACH, dist - 60)
        toward(a, tx, ty, 46, 6, dt)
        a.pitch, a.grip = ease(a.pitch, -0.45, 6, dt), ease(a.grip, 0, 8, dt)
        if k >= 1 then
            local vx, vy = player.body:getLinearVelocity()
            a.lungeX, a.lungeY = inReach(a, px + vx * 0.12, py + vy * 0.12)
            setState(a, "lunge", GRAB.lunge)
        end
    elseif s == "lunge" then
        toward(a, a.lungeX, a.lungeY, 18, 22, dt)
        if k >= 1 then
            if (px - a.cx) ^ 2 + (py - a.cy) ^ 2 < GRAB.reach * GRAB.reach and not player.isDodging
                and not player.inCar and not player.isSafe() and not player.god then
                a.holding, a.holdHits, a.squeeze = true, 0, 0
                a.throwAt = math.atan2(py - a.y, px - a.x) + (a.rng:random() < 0.5 and -1 or 1) * 0.9
                setState(a, "held", GRAB.hold)
            else
                setState(a, "missed", GRAB.missed)
            end
        end
    elseif s == "held" then
        a.grip = ease(a.grip, 1, 12, dt)
        local r = math.max(MIN_REACH + 20, math.min(REACH * 0.7, dist))
        toward(a, a.x + math.cos(a.throwAt) * r, a.y + math.sin(a.throwAt) * r, 44, 2.5, dt)
        -- you, in its grip
        player.body:setPosition(a.cx, a.cy + 6)
        player.body:setLinearVelocity(0, 0)
        player.isDodging = false
        a.squeeze = a.squeeze + GRAB.dps * dt -- hurt in ticks, so the shake stays small
        if a.squeeze >= 20 then
            player.hurt(a.squeeze, nil, "blow")
            a.squeeze = 0
        end
        if a.holdHits >= GRAB.breakFree then
            release(a) -- shot loose
            setState(a, "recover", 0.6)
        elseif k >= 1 then
            -- thrown
            release(a)
            local dx, dy = unit(a.cx - a.x, a.cy - a.y)
            player.hurt(GRAB.throw, vec2.new(dx, dy), "blow")
            player.body:setLinearVelocity(dx * GRAB.speed, dy * GRAB.speed)
            camera.shake(5, 0.2)
            setState(a, "recover", GRAB.recover)
        end
    elseif s == "missed" then
        a.grip = ease(a.grip, 1, 10, dt)
        if k >= 1 then setState(a, "recover", 0.4) end

    elseif s == "recover" then
        toward(a, a.cx, a.cy, 70, 4, dt) -- back up off the street
        a.pitch = ease(a.pitch, -0.6, 4, dt)
        if k >= 1 then setState(a, "track", 0.7 + a.rng:random() * 0.7) end
    end
    return px, py, dist
end

-- The guns turn after you, and fire in turn while it's awake
local function guns(a, dt, px, py, dist)
    for _, g in ipairs(a.guns) do
        g.aim = turnToward(g.aim, math.atan2(py - 10 - g.ey, px - g.ex), 4 * dt)
        g.kick = math.max(0, g.kick - dt * 5)
    end
    if a.state == "rest" or a.state == "held" or dist > GUN_RANGE then return end
    a.gunT = a.gunT - dt
    if a.gunT > 0 then return end
    a.gunT = a.angry and BOLT.angry or BOLT.every
    local g = a.guns[a.gunNext]
    a.gunNext = 3 - a.gunNext
    local dx, dy = unit(px - g.mx, py - g.my)
    local neon = a.angry and ANGRY_NEON or BOLT_NEON
    bullet.new({
        pos = vec2.new(g.mx, g.my), dir = vec2.new(dx, dy), speed = BOLT.speed, damage = BOLT.damage,
        radius = BOLT.radius, lifetime = BOLT.lifetime, neon = neon, hostile = true,
    })
    bullet.createMuzzleFlash(vec2.new(g.mx, g.my), vec2.new(dx, dy), {
        duration = 0.06, coneAngle = math.rad(25), coneLength = 50, intensity = 0.5, color = neon.core
    })
    audio.playSoundAt("enemyGun", g.mx, g.my, 0.08)
    g.kick = 1
end

-- Broken: it goes limp, the claw dropping, and goes up joint by joint
local function die(a, dt)
    a.dying = a.dying + dt
    a.cz = math.max(0, a.cz - dt * 260 * a.dying)
    a.pitch, a.grip = ease(a.pitch, -1.5, 3, dt), ease(a.grip, 0, 2, dt)
    for i, d in ipairs(DEATH) do
        if not a.blown[i] and a.dying >= d[1] then
            a.blown[i] = true
            local j = a.joints[d[2]]
            explosion.create(j.x, j.y, explosion.TYPES.BLAST)
            audio.playSoundAt("explosion", j.x, j.y, 0.08, 0.35)
            camera.shake(4, 0.15)
        end
    end
    if a.dying >= DEATH_TIME then
        explosion.create(a.x, a.y - 30, explosion.TYPES.DEATH)
        audio.playSoundAt("explosion", a.x, a.y, 0.1, 0.7)
        camera.shake(9, 0.45)
        robotArm.despawnInst(a)
    end
end

-- Its glow lighting the street, from the ground under the claw and the base
local function addLights(a)
    local x0, y0, x1, y1 = regions.view(300)
    if a.x < x0 - REACH or a.x > x1 + REACH or a.y < y0 - REACH or a.y > y1 + REACH then return end
    local k = a.dying and 0.5 + 0.5 * love.math.random() or 1
    local J = a.joints
    shadow.addTransientLight(J.grip.gx, J.grip.gy + 6, 0.45 * k, 130)
    shadow.addTransientLight(a.x, a.y + 12, 0.35 * k, 120)
end

--- Each frame, before the lighting upload: where the world runs, each arm
--- thinks and moves; everywhere, each is solved for drawing and lights the
--- street.
function robotArm.update(dt)
    if hosting() then
        for i = #robotArm.arms, 1, -1 do
            local a = robotArm.arms[i]
            a.time = a.time + dt
            a.flash = math.max(0, a.flash - dt)
            if not a.dying and a.health <= 0 then
                -- broken: no more hits, and it lets go
                a.dying, a.blown, a.ringK = 0, {}, 0
                for _, p in ipairs(a.parts) do bosses.unregister(p) end
                release(a)
            end
            if a.dying then
                die(a, dt)
            elseif player and player.body then
                a.angry = a.health <= a.max_health * 0.5
                guns(a, dt, think(a, dt)) -- (aiming from where it was drawn last)
            end
            if not a.gone then
                solve(a)
                placeSensors(a)
                addLights(a)
            end
        end
    else
        for _, a in ipairs(robotArm.net) do
            a.time = a.time + dt
            solve(a)
            addLights(a)
        end
    end
end

--------------------------------------------------------------------------------
-- Network
--------------------------------------------------------------------------------

--- Host: what clients need to draw each arm
function robotArm.getNetworkData()
    local list = {}
    for i, a in ipairs(robotArm.arms) do
        list[i] = {
            x = a.x, y = a.y, h = a.health, m = a.max_health, cx = a.cx, cy = a.cy, cz = a.cz,
            p = a.pitch, g = a.grip, ux = a.ux, uy = a.uy, f = a.flash, an = a.angry or nil,
            a1 = a.guns[1].aim, a2 = a.guns[2].aim, k1 = a.guns[1].kick, k2 = a.guns[2].kick,
            rk = a.ringK, rx = a.ringX, ry = a.ringY, d = a.dying,
        }
    end
    return list
end

--- Client: the arms as the host sent them (each keeps its joints from last time)
function robotArm.applyNetworkData(list)
    local net = {}
    for i, d in ipairs(list or {}) do
        local a = robotArm.net[i] or shell()
        a.x, a.y, a.health, a.max_health = d.x, d.y, d.h, d.m
        a.cx, a.cy, a.cz, a.pitch, a.grip, a.ux, a.uy = d.cx, d.cy, d.cz, d.p, d.g, d.ux, d.uy
        a.flash, a.angry, a.dying = d.f or 0, d.an, d.d
        a.guns[1].aim, a.guns[2].aim, a.guns[1].kick, a.guns[2].kick = d.a1, d.a2, d.k1, d.k2
        a.ringK, a.ringX, a.ringY = d.rk or 0, d.rx or 0, d.ry or 0
        net[i] = a
    end
    robotArm.net = net
end

--------------------------------------------------------------------------------
-- Drawing (lib/graphics/renderer.lua hands each piece to robotArm.drawPiece)
--------------------------------------------------------------------------------

-- A bone's art from (x1, y1) to (x2, y2), its top kept up
local function bone(piece, x1, y1, x2, y2, glow)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.max(math.sqrt(dx * dx + dy * dy), piece.len * PX * 0.3)
    love.graphics.draw(glow and piece.glow or piece.body, x1, y1, math.atan2(dy, dx),
        len / piece.len, dx < 0 and -PX or PX, piece.r, piece.r)
end

local function joint(piece, x, y, glow)
    love.graphics.draw(glow and piece.glow or piece.body, x, y, 0, PX, PX, piece.r, piece.r)
end

local function halo(x, y, radius, c, k)
    love.graphics.setColor(c[1] * k, c[2] * k, c[3] * k, 1)
    love.graphics.draw(regions.glow, x - radius, y - radius, 0, radius * 2 / 64, radius * 2 / 64)
end

local function neon(a)
    local c = a.angry and ANGRY or CALM
    local k = a.dying and love.math.random() or 0.85 + 0.15 * math.sin(a.time * 6)
    return { c[1] * k, c[2] * k, c[3] * k }
end

-- On the ground, under everything: its shadow, and the ring where a slam lands
local function drawGround(a)
    local J = a.joints
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.ellipse("fill", a.x, a.y + 4, BASE_R + 6, (BASE_R + 6) * 0.45)
    love.graphics.setColor(0, 0, 0, 0.18)
    love.graphics.setLineWidth(14)
    love.graphics.line(J.shoulder.gx, J.shoulder.gy, J.elbow.gx, J.elbow.gy, J.wrist.gx, J.wrist.gy,
        J.grip.gx, J.grip.gy)
    local lift = math.min(1, J.grip.z / 220)
    love.graphics.setColor(0, 0, 0, 0.35 * (1 - lift))
    love.graphics.ellipse("fill", J.grip.gx, J.grip.gy, 16 + lift * 10, (16 + lift * 10) * 0.55)
    if a.ringK > 0 then
        love.graphics.setBlendMode("add")
        love.graphics.setColor(1, 0.15, 0.25, 0.3 * a.ringK)
        love.graphics.circle("fill", a.ringX, a.ringY, SLAM.radius)
        love.graphics.setLineWidth(2)
        love.graphics.setColor(1, 0.3, 0.35, 0.9 * a.ringK)
        love.graphics.circle("line", a.ringX, a.ringY, SLAM.radius)
        love.graphics.setBlendMode("alpha")
    end
    love.graphics.setLineWidth(1)
end

local PIECES = {}

function PIECES.base(a, glow)
    love.graphics.draw(glow and art.base.glow or art.base.body, a.x, a.y, 0, PX, PX, BASE_AX, BASE_AY)
    for _, g in ipairs(a.guns) do
        bone(art.gun, g.rx, g.ry, g.kx, g.ky, glow)
        bone(art.gunTip, g.kx, g.ky, g.ex, g.ey, glow)
        love.graphics.draw(glow and art.barrel.glow or art.barrel.body, g.ex, g.ey, g.aim,
            PX, math.cos(g.aim) < 0 and -PX or PX, 1, 2.5)
        joint(art.pin, g.kx, g.ky, glow)
        joint(art.pin, g.rx, g.ry, glow)
    end
    if glow then halo(a.x, a.y - 2 * (BASE_AY - 19.5), 18, neon(a), 0.35) end
end

function PIECES.upper(a, glow)
    local J = a.joints
    local S, E, W = J.shoulder, J.elbow, J.wrist
    if not glow then
        -- the hydraulic ram: from the upper arm by its shoulder to the
        -- forearm past the elbow, sliding out as the elbow opens
        local r, g, b = love.graphics.getColor()
        local ux, uy = unit(E.x - S.x, E.y - S.y)
        local fx, fy = unit(W.x - E.x, W.y - E.y)
        local nux, nuy = uy, -ux
        if nuy > 0 then nux, nuy = -nux, -nuy end -- (on its upper side)
        local nfx, nfy = fy, -fx
        if nfy > 0 then nfx, nfy = -nfx, -nfy end
        local p1x, p1y = S.x + ux * 30 + nux * 10, S.y + uy * 30 + nuy * 10
        local p2x, p2y = E.x + fx * 22 + nfx * 8, E.y + fy * 22 + nfy * 8
        local mx, my = p1x + (p2x - p1x) * 0.55, p1y + (p2y - p1y) * 0.55
        love.graphics.setColor(r * 0.12, g * 0.13, b * 0.17, 1)
        love.graphics.setLineWidth(7)
        love.graphics.line(p1x, p1y, mx, my)
        love.graphics.setColor(r * 0.75, g * 0.78, b * 0.85, 1)
        love.graphics.setLineWidth(3)
        love.graphics.line(mx, my, p2x, p2y)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(r, g, b, 1)
    end
    bone(art.upper, S.x, S.y, E.x, E.y, glow)
    joint(art.joint, S.x, S.y, glow)
    if a.elbowOnUpper then joint(art.joint, E.x, E.y, glow) end
end

function PIECES.fore(a, glow)
    local J = a.joints
    bone(art.fore, J.elbow.x, J.elbow.y, J.wrist.x, J.wrist.y, glow)
    joint(art.wrist, J.wrist.x, J.wrist.y, glow)
    if not a.elbowOnUpper then joint(art.joint, J.elbow.x, J.elbow.y, glow) end
end

function PIECES.claw(a, glow)
    local J = a.joints
    for _, f in ipairs(J.fingers) do
        bone(art.finger, f.rx, f.ry, f.kx, f.ky, glow)
        bone(art.tip, f.kx, f.ky, f.tx, f.ty, glow)
    end
    love.graphics.draw(glow and art.palm.glow or art.palm.body, J.palm.x, J.palm.y,
        math.atan2(a.hand.y, a.hand.x), PX, a.hand.x < 0 and -PX or PX, 6, 6)
    if glow then
        local c = a.state == "stuck" and { 1, 0.95, 0.6 } or neon(a) -- (stuck: open to you)
        halo(J.palm.x, J.palm.y, a.state == "stuck" and 30 or 20, c, 0.45)
    end
end

--- One piece of an arm, from the sorted list: lit like everything else,
--- then its neon over it at full strength (it lights the GI its colour)
function robotArm.drawPiece(d)
    local a = d.arm
    local shader = love.graphics.getShader()
    if d.piece == "ground" then
        love.graphics.setShader()
        drawGround(a)
    else
        local f = a.flash > 0 and 0.55 or 0
        love.graphics.setColor(1, 1 - f, 1 - f, 1)
        PIECES[d.piece](a, false)
        love.graphics.setShader()
        love.graphics.setBlendMode("add")
        local c = neon(a)
        love.graphics.setColor(c[1], c[2], c[3], 1)
        PIECES[d.piece](a, true)
        love.graphics.setBlendMode("alpha")
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(shader)
end

--- Each arm on screen into the dynamic draw list, a piece at a time, each
--- sorted by the ground under it
function robotArm.populate()
    local x0, y0, x1, y1 = regions.view(REACH + 60)
    for _, a in ipairs(hosting() and robotArm.arms or robotArm.net) do
        if a.joints.grip.x and a.x > x0 and a.x < x1 and a.y > y0 and a.y < y1 then
            local J = a.joints
            local function piece(name, gy)
                dynamic_draw_list[#dynamic_draw_list + 1] = {
                    sort_y = gy, draw_type = "robotArm", arm = a, piece = name
                }
            end
            local upper, fore = (J.shoulder.gy + J.elbow.gy) / 2, (J.elbow.gy + J.wrist.gy) / 2
            a.elbowOnUpper = upper > fore -- (the elbow's disc over whichever bone is nearer)
            piece("ground", -1e9)
            piece("base", a.y - 4 + SORT)
            piece("upper", upper + SORT)
            piece("fore", fore + SORT)
            piece("claw", J.grip.gy + 2 + SORT)
        end
    end
end

return robotArm
