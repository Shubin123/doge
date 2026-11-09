--[[
  The black hole gun's shots (gun.lua, held as the portal gun).

  Each shot is a tiny black hole that flies out to where you aimed, stopping
  short at a wall or on an enemy, and opens up there: for a few seconds it
  drags enemies in, harder the closer they are, and swallows them at its
  horizon, along with enemies' bullets (they bend round it on the way). Then
  it collapses with a shockwave.

    * Unlike blackhole.lua's hole it doesn't slow time or pull the player.
    * Its look is blackhole.applySmallLensing (draw.lua, after the black
      hole's own): the same lensed shadow, disk and ring, blue-white and
      violet. On low graphics, with no screen-space passes, a plain dark
      disk and ring stand in for it (blackholeGun.populate).
    * It pulls and swallows only where the world is run (host, single
      player); a client sees its own shots and nothing more.
    * Enemies throw them too (game/enemyWeapons.lua: `hostile`): one of
      theirs flies through enemies and opens on you, pulls you in rather
      than them, hurts you at its heart, and burns red and orange like the
      big black hole rather than blue.
]]
local blackholeGun = {}
blackholeGun.holes = {}

local SPEED = 420              -- px/s in flight
local MIN_RANGE, MAX_RANGE = 60, 520 -- px past the muzzle where it opens
local FLIGHT_HORIZON = 5       -- px: the shadow's radius in flight...
local HORIZON = 14             -- ...and open
local OPEN_TIME = 0.25         -- s to grow from one to the other
local LIFE = 3.5               -- s open, the collapse included
local COLLAPSE_TIME = 0.35     -- s it shrinks away at the end
local MAX_HOLES = 3            -- a fourth opening starts the oldest collapsing
local PULL_RADIUS = 240        -- px: enemies and their bullets feel it inside this
local PULL = 1.6e5             -- acceleration is PULL / d px/s^2...
local MAX_PULL = 3200          -- ...up to this
local DRAG = 3                 -- 1/s: inside, enemies lose their own way, so they fall in rather than orbit
local SWALLOW = HORIZON + 10   -- px: an enemy's centre this close is gone
local BOSS_DPS = 35            -- what it does to a boss within 2.5 x that a second
local BULLET_PULL = 4          -- enemies' bullets bend round it (as blackhole.lua's)
local HIT_ENEMY = 24           -- px: in flight it stops on an enemy this close
local HIT_PLAYER = 30          -- px: an enemy's stops on you this close
local PLAYER_PULL = 7.0e4      -- an enemy's pulls you at PLAYER_PULL / d px/s^2 (up to MAX_PULL)...
local PLAYER_DRAG = 2.5        -- 1/s: ...your fall settling at that over PLAYER_DRAG px/s...
local MAX_DRIFT = 28           -- ...up to this a frame (you keep your speed, less friction: about
                               -- 160 px/s standing, under your 200 walking out)
local HURT_PER_SECOND = 220    -- HP at an enemy's heart (player.maxHealth is 1000)

local passGroups -- fixtures a shot flies through (blackholeGun.load)

function blackholeGun.load()
    blackholeGun.holes = {}
    local g = collision.groups
    passGroups = {
        [g.player] = true, [g.projectile] = true, [g.rocket] = true,
        [g.tesla] = true, [g.enemyBullet] = true, [g.coin] = true,
    }
end

-- Shadow radius now: grows as it opens, shrinks to nothing as it collapses.
local function horizonOf(h)
    if h.flying then return FLIGHT_HORIZON end
    local grow = math.min(1, h.age / OPEN_TIME)
    local fade = math.max(0, math.min(1, (LIFE - h.age) / COLLAPSE_TIME))
    return (FLIGHT_HORIZON + (HORIZON - FLIGHT_HORIZON) * grow) * fade
end

-- Where the line from (x1, y1) to (x2, y2) first meets a wall, a prop or an
-- enemy (nil when nothing's in the way); a `hostile` one flies through
-- enemies.
local function firstHit(x1, y1, x2, y2, hostile)
    if (x1 - x2) ^ 2 + (y1 - y2) ^ 2 < 1e-6 then return nil end
    local hx, hy
    world:rayCast(x1, y1, x2, y2, function(fixture, x, y, xn, yn, fraction)
        local group = fixture:getGroupIndex()
        if fixture:isSensor() or passGroups[group] or (hostile and group == collision.groups.enemy) then
            return -1
        end
        hx, hy = x, y
        return fraction -- keep looking for a nearer one
    end)
    return hx, hy
end

local function enemyNear(x, y, radius)
    for _, e in ipairs(enemy.enemies) do
        if not e.dead and e.body and not e.body:isDestroyed() then
            local ex, ey = e.body:getPosition()
            if (ex - x) ^ 2 + (ey - y) ^ 2 < radius * radius then
                return true
            end
        end
    end
    return false
end

local function open(h)
    h.flying = false
    h.age = 0
    local holes = {}
    for _, other in ipairs(blackholeGun.holes) do
        if not other.flying and not other.hostile == not h.hostile then holes[#holes + 1] = other end
    end
    -- The list is oldest first
    for i = 1, #holes - MAX_HOLES do
        holes[i].age = math.max(holes[i].age, LIFE - COLLAPSE_TIME)
    end
end

-- Move a shot in flight up to `step` px, opening it where it stops.
local function advance(h, step)
    step = math.min(step, h.left)
    local nx, ny = h.x + h.dx * step, h.y + h.dy * step
    local hx, hy = firstHit(h.x, h.y, nx, ny, h.hostile)
    if hx then
        -- Just this side of what it hit
        h.x, h.y = hx - h.dx * FLIGHT_HORIZON, hy - h.dy * FLIGHT_HORIZON
        open(h)
        return
    end
    h.x, h.y, h.left = nx, ny, h.left - step
    local stop
    if h.hostile then
        local px, py = player.body:getPosition()
        stop = (px - h.x) ^ 2 + (py - h.y) ^ 2 < HIT_PLAYER * HIT_PLAYER
    else
        stop = enemyNear(h.x, h.y, HIT_ENEMY) or bosses.near(h.x, h.y, HIT_ENEMY) ~= nil
    end
    if h.left <= 0 or stop then
        open(h)
    end
end

--- Fire one. params = { from = vec2 (the player), dir = vec2 (unit),
--- muzzle = px from `from` it leaves at, range = px from `from` it opens at,
--- hostile = an enemy's }
function blackholeGun.new(params)
    local h = {
        x = params.from.x, y = params.from.y,
        dx = params.dir.x, dy = params.dir.y,
        left = params.muzzle + math.max(MIN_RANGE, math.min(MAX_RANGE, (params.range or MAX_RANGE) - params.muzzle)),
        flying = true,
        age = 0,
        hostile = params.hostile or nil,
        driftX = 0, driftY = 0, -- an enemy's: your fall towards it, px/s
    }
    table.insert(blackholeGun.holes, h)
    advance(h, params.muzzle) -- out of the barrel, unless a wall is right there
    return h
end

-- Drag enemies in and swallow them; bend enemies' bullets and swallow those.
local function pull(h, dt)
    local horizon = horizonOf(h)
    local k = horizon / HORIZON
    for _, e in ipairs(enemy.enemies) do
        if not e.dead and e.body and not e.body:isDestroyed() then
            local ex, ey = e.body:getPosition()
            local dx, dy = h.x - ex, h.y - ey
            local d = math.sqrt(dx * dx + dy * dy)
            if d < SWALLOW * k then
                e:damageEnemy(math.huge) -- swallowed: dies, its light streams off
            elseif d > 0.5 and d < PULL_RADIUS then
                local a = math.min(MAX_PULL, PULL / d) * k * dt
                local keep = math.max(0, 1 - DRAG * k * dt)
                local vx, vy = e.body:getLinearVelocity()
                e.body:setLinearVelocity(vx * keep + dx / d * a, vy * keep + dy / d * a)
            end
        end
    end

    -- a boss is too much to swallow: it gnaws at it (game/bosses.lua)
    bosses.drain(h.x, h.y, SWALLOW * k * 2.5, BOSS_DPS, dt)

    for i = #bullet.instances, 1, -1 do
        local inst = bullet.instances[i]
        if inst.hostile and not inst.spent then
            local x, y = inst.body:getPosition()
            local dx, dy = h.x - x, h.y - y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < horizon + 4 then
                bullet.returnToPool(inst, i) -- swallowed
            elseif d < PULL_RADIUS then
                local a = math.min(MAX_PULL, PULL / d) * k * BULLET_PULL * dt / math.max(1, inst.speed)
                local nx, ny = inst.dir.x + dx / d * a, inst.dir.y + dy / d * a
                local n = math.sqrt(nx * nx + ny * ny)
                inst.dir = vec2.new(nx / n, ny / n)
            end
        end
    end
end

-- An enemy's: pull you in (a drift kept here and added to your velocity, as
-- blackhole.lua does: player.update's friction eats a small pull added to
-- it), and hurt you at its heart.
local function pullPlayer(h, dt)
    local k = horizonOf(h) / HORIZON
    local px, py = player.body:getPosition()
    local dx, dy = h.x - px, h.y - py
    local d = math.sqrt(dx * dx + dy * dy)
    local keep = math.max(0, 1 - PLAYER_DRAG * dt)
    h.driftX, h.driftY = h.driftX * keep, h.driftY * keep
    if d > 0.5 and d < PULL_RADIUS then
        local a = math.min(MAX_PULL, PLAYER_PULL / d) * k * dt
        h.driftX, h.driftY = h.driftX + dx / d * a, h.driftY + dy / d * a
    end
    -- no faster than you can walk out, and easing off at its heart (or you'd
    -- be flung through and out the far side)
    local cap = MAX_DRIFT * math.min(1, d / 40)
    local s = math.sqrt(h.driftX * h.driftX + h.driftY * h.driftY)
    if s > cap then
        h.driftX, h.driftY = h.driftX / s * cap, h.driftY / s * cap
    end
    if h.driftX * h.driftX + h.driftY * h.driftY > 0.01 then
        local vx, vy = player.body:getLinearVelocity()
        player.body:setLinearVelocity(vx + h.driftX, vy + h.driftY)
    end
    if d < SWALLOW * k then
        player.hurt(HURT_PER_SECOND * dt)
    end
end

local function collapse(h)
    explosion.create(h.x, h.y, explosion.TYPES.IMPLOSION)
    local src = audio.playSoundAt("explosion", h.x, h.y, 0.05, 0.4)
    if src then src:setPitch(src:getPitch() * 0.55) end -- a deep thump
end

--- Every frame, whichever weapon is held (gun.update). Before the lighting
--- upload: each hole lights the ground round it.
function blackholeGun.update(dt)
    local runsWorld = not var.multiplayer or var.multiplayer == 1
    for i = #blackholeGun.holes, 1, -1 do
        local h = blackholeGun.holes[i]
        if h.flying then
            advance(h, SPEED * dt)
        else
            h.age = h.age + dt
        end
        if not h.flying and h.age >= LIFE then
            collapse(h)
            table.remove(blackholeGun.holes, i)
        else
            if not h.flying and runsWorld then
                if h.hostile then pullPlayer(h, dt) else pull(h, dt) end
            end
            local k = horizonOf(h) / HORIZON
            shadow.addTransientLight(h.x, h.y + 10, 0.45 * k, 60 + 100 * k)
        end
    end
end

--- Screen-space, after blackhole.applyLensing (draw.lua): bend the scene
--- round each hole and draw its disk.
function blackholeGun.applyLensing()
    for _, h in ipairs(blackholeGun.holes) do
        local horizon = horizonOf(h)
        if horizon > 0.5 then
            blackhole.applySmallLensing(h.x, h.y, horizon, h.hostile)
        end
    end
end

--- Low graphics: a stand-in for each hole in the sorted draw list
--- (renderer.lua's "blackholeGun" draw_type, blackholeGun.drawFallback).
function blackholeGun.populate()
    if var.graphics_high then return end
    for _, h in ipairs(blackholeGun.holes) do
        table.insert(dynamic_draw_list, {
            draw_type = "blackholeGun",
            sort_y = renderer.ON_TOP,
            x = h.x,
            y = h.y,
            radius = horizonOf(h),
            hostile = h.hostile,
            color = { 1, 1, 1, 1 },
        })
    end
end

function blackholeGun.drawFallback(d)
    local shader = love.graphics.getShader()
    love.graphics.setShader()
    if d.hostile then
        love.graphics.setColor(0.95, 0.35, 0.08, 0.45) -- an enemy's: hot
    else
        love.graphics.setColor(0.45, 0.22, 1.0, 0.45)
    end
    love.graphics.circle("fill", d.x, d.y, d.radius * 2.4)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.circle("fill", d.x, d.y, d.radius)
    if d.hostile then
        love.graphics.setColor(1.0, 0.85, 0.65, 1)
    else
        love.graphics.setColor(0.75, 0.85, 1.0, 1)
    end
    love.graphics.setLineWidth(1.5)
    love.graphics.circle("line", d.x, d.y, d.radius * 1.12)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(shader)
end

return blackholeGun
