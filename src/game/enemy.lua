Enemy = {}
Enemy.__index = Enemy

-- What enemies shoot, by look and index: one of each of your weapons, and
-- attacks of their own (lasers, the multi-laser, black holes): all in
-- game/enemyWeapons.lua
local enemyWeapons = require("game.enemyWeapons")

--[[
  How each look shoots: the animation an attack plays once through, timed by
  the game rather than the animator's own clock, so every shot leaves on a
  frame of it and every time it plays it shoots.
    anim:   the animation (gfx/atlas/atlas_metadata3.lua)
    frames: frames it has, per direction
    from, count: the frames played, from `from` on, wrapping past the last
    fps:    how fast
    hits:   the frames its shots leave on: where the arm or guns are out, the
            art reaching furthest from the body (averaged over the eight
            directions)
  Its weapon fires once on each hit: a burst's rounds follow from there.
  `rest` is a loop it holds between attacks instead of its animation
  (animated_special's one animation is the whole attack, start to finish).
  `aim` (gun, a turntable of one weapon): no animation; its frame turns it
  to face you, and each shot kicks it back.
]]
local MOVES = {
    -- arm up (13-16), shot (1), down and up again, shot (12)
    watchman = { anim = "shoot", frames = 16, from = 13, count = 16, fps = 14, hits = { 1, 12 } },
    -- guns up (10-13), out (14), back, out again (2)
    mech = { anim = "shoot", frames = 15, from = 10, count = 15, fps = 14, hits = { 14, 2 } },
    -- no shooting animation: the stride with its arm out, held as a throw
    steve = { anim = "walk", frames = 25, from = 9, count = 6, fps = 12, hits = { 13 } },
    -- rears up, unfolds and strikes out (48), folds back
    animated_special = { anim = "default", frames = 93, from = 13, count = 81, fps = 32, hits = { 48 },
        rest = { from = 1, count = 12, fps = 8 } },
    gun = { aim = true, hits = {} },
}

-- The moves its special comes on (enemyWeapons.LOADOUT): a laser charges
-- from the move's start and burns from its hit
local CASTS = {
    -- raises its hand (2-6), the spell leaving it (7)
    watchman = { anim = "cast", frames = 15, from = 1, count = 15, fps = 12, hits = { 7 } },
    -- both guns up together, out at once (14)
    mech = { anim = "shoot", frames = 15, from = 10, count = 15, fps = 10, hits = { 14 } },
    animated_special = MOVES.animated_special,
    -- holds its aim on you while the beam charges
    gun = { aim = true, hits = {}, charge = 0.7 },
}
--[[
  Up close, the watchmen and mechs fight hand to hand: a move of the same
  kind, each hit a blow that lands if you're still within `reach` of it with
  nothing between (dodge out as it swings and it misses).
    damage: HP a blow (player.maxHealth is 1000)
    knock:  how hard it throws you, compared with a shot of that damage
  Half of each (by index, Enemy:setLook) are brawlers: they close in to
  fight this way rather than holding their weapon's range, and don't shoot.
]]
local MELEE = {
    -- a left (5), then a right (10)
    watchman = { anim = "punch", frames = 16, from = 1, count = 16, fps = 16, hits = { 5, 10 },
        reach = 70, damage = 35, knock = 1.2 },
    -- winds up, then spins, its blades out three times (19, 27, 45)
    mech = { anim = "attack", frames = 60, from = 12, count = 49, fps = 24, hits = { 19, 27, 45 },
        reach = 95, damage = 40, knock = 1.8 },
}

-- What each enemy looks like, by its index
local ENEMY_TYPES = {"watchman", "mech", "steve", "watchman", "mech", "animated_special", "gun"}

local function prepare(m)
    -- seconds into the move each hit comes, in order
    m.hitTimes = {}
    for _, f in ipairs(m.hits) do
        m.hitTimes[#m.hitTimes + 1] = ((f - m.from) % m.frames) / m.fps
    end
    table.sort(m.hitTimes)
    if m.aim then m.hitTimes[1] = m.charge or 0 end
    m.time = m.aim and (m.charge or 0) + 0.25 or m.count / m.fps
end
for _, m in pairs(MOVES) do prepare(m) end
for _, m in pairs(MELEE) do prepare(m) end
for _, m in pairs(CASTS) do if not m.hitTimes then prepare(m) end end

--[[
  How enemies think. Each thinks a few times a second rather than every
  frame (Enemy:think), staggered so they don't all think on the same frame,
  and between times steers toward the velocity it last decided on
  (Enemy:update): a force, so knockback still throws it about.

    * Far off (FAR) it only drifts your way; further still (IDLE) it waits.
    * With you in sight (one raycast a thought) and within ENGAGE, it holds
      its weapon's range, circling you one way or the other, so a crowd
      surrounds you rather than piling up, and turns about when it's stuck.
      It shoots only then (not through walls), leading you as you move.
    * Out of sight it comes for you round what's in the way: every enemy
      follows one flow field from where you are (lib/nav.lua), worked out
      at most twice a second, and only once you've moved.
    * Each keeps clear of the others nearby (a spatial hash a frame).
]]
local nav = require("lib.nav")
local AI = {
    ENGAGE = 650,         -- px: closer, with you in sight, it fights
    FAR = 2600,           -- px: further, it only drifts your way
    IDLE = 4000,          -- px: further still, it waits
    THINK_NEAR = 0.2,     -- s between thoughts: fighting or nearly
    THINK_MID = 0.4,      -- coming for you
    THINK_FAR = 1.0,      -- far off
    SPEED = 150,          -- px/s coming for you
    STRAFE = 110,         -- px/s circling you
    DRIFT = 60,           -- px/s far off
    STEER = 6,            -- how fast it takes up the velocity it wants (1/s)
    SPACE = 44,           -- px it keeps from the others
    FLOW_CELL = 48,       -- px, the flow field's grid
    FLOW_RADIUS = 24,     -- cells round you it covers
    FLOW_EVERY = 0.5,     -- s at most between flow fields
    now = 0,              -- s, enemy.update's clock
}
-- (an enemy's radius is 20: cells it fits in keep 22 px clear)
local grid = nav.new(AI.FLOW_CELL, 22)
local field, fieldAt = nil, -math.huge

-- The flow field to where you are, worked out again when it's old enough
-- and you've moved off its cell
local function flowTo(px, py, now)
    if not field or (now - fieldAt > AI.FLOW_EVERY and
            (math.floor(px / AI.FLOW_CELL) ~= field.gx or math.floor(py / AI.FLOW_CELL) ~= field.gy)) then
        field, fieldAt = grid:flow(px, py, AI.FLOW_RADIUS), now
    end
    return field
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

-- The spatial hash of live enemies (enemy.update fills it each frame), in
-- buckets SPACE px square
local buckets, usedBuckets = {}, {}
local function bucketKey(x, y)
    return math.floor(x / AI.SPACE) * 100003 + math.floor(y / AI.SPACE)
end

-- Which way to go to keep clear of the others round (x, y), stronger the closer they are
local function separation(self, x, y)
    local sx, sy = 0, 0
    local bx, by = math.floor(x / AI.SPACE), math.floor(y / AI.SPACE)
    for ox = -1, 1 do
        for oy = -1, 1 do
            local list = buckets[(bx + ox) * 100003 + by + oy]
            if list then
                for i = 1, list.n do
                    local other = list[i]
                    if other ~= self then
                        local ex, ey = other.body:getPosition()
                        local dx, dy = x - ex, y - ey
                        local d2 = dx * dx + dy * dy
                        if d2 < AI.SPACE * AI.SPACE and d2 > 1e-6 then
                            local d = math.sqrt(d2)
                            local k = (AI.SPACE - d) / AI.SPACE / d
                            sx, sy = sx + dx * k, sy + dy * k
                        end
                    end
                end
            end
        end
    end
    return sx, sy
end

function Enemy.new(world, x, y, max_health, scale, fire_cooldown, detection_range, projectile_speed, index)
    local self = setmetatable({}, Enemy)
    self.body = love.physics.newBody(world, x, y, "dynamic")

    self.fixture = love.physics.newFixture(self.body, love.physics.newCircleShape(20))
    self.fixture:setGroupIndex(-777) -- negative = enemies never collide with each other
    self.fixture:setDensity(2.0)
    self.fixture:setUserData(index)

    self.health = 1
    self.max_health = self.health
    self.scale = scale or 0.6
    self.burstLeft = 0   -- rounds of the current trigger pull still to fire
    self.burstTimer = 0
    self.detection_range = detection_range or 300
    self.last_fire_time = 0
    self.t = 0
    self.damage_indicators = {}
    self.damaged = false

    -- Its own ways, from its index (no random numbers): which way it circles,
    -- how near it likes to be within its weapon's range, how far ahead it aims
    local a, b = (index * 0.61803) % 1, (index * 0.38197) % 1
    self.orbit = index % 2 == 0 and 1 or -1
    self.rangeK = 0.85 + a * 0.3 -- of its weapon's range, where it holds (Enemy:setLook)
    self.lead = 0.3 + b * 0.6
    self.jitter = a           -- added to its cooldown, drawn again each shot
    self.thinkIn = (index % 10) * 0.03 -- staggered
    self.wantX, self.wantY = 0, 0
    self.index = index
    self.meleeReady = 0 -- self.t it can swing again
    self.specialReady = 2 + b * 4 -- self.t it can use its special
    self:setLook(ENEMY_TYPES[index % #ENEMY_TYPES + 1])

    return self
end

--- How it looks (a characterAnimator type), and so how it shoots (MOVES)
--- and fights up close (MELEE).
function Enemy:setLook(look)
    self.look = look
    self.move = MOVES[look] or MOVES.watchman
    self.cast = CASTS[look]
    self.weapon, self.special = enemyWeapons.pick(look, self.index)
    self.melee = MELEE[look]
    self.brawler = self.melee ~= nil and math.floor(self.index / 7) % 2 == 1
    -- where it holds: a brawler within reach, the rest its weapon's range
    self.range = self.brawler and self.melee.reach * 0.6 or self.weapon.range * self.rangeK
    -- As often as its weapon fired before, a shot a hit, and never quicker
    -- than its move plays
    self.fire_cooldown = math.max(self.weapon.cooldown * #self.move.hitTimes, self.move.time + 0.4)
end

-- Its slot's sprite (gun_enemies[index + 2]); none past the enemy slots,
-- where the other players' are
local function spriteOf(self)
    return self.index < var.num_enemies and gun_enemies and gun_enemies[self.index + 2] or nil
end

--- Start a move, its shooting one with its weapon unless others are given:
--- Enemy:update plays it through, the weapon firing (or a blow landing) on
--- each hit.
function Enemy:startAttack(m, w)
    m, w = m or self.move, w or self.weapon
    self.attack = { t = 0, hit = 1, move = m, weapon = w }
    local sprite = spriteOf(self)
    if sprite and m.anim then
        sprite.setAnimation(m.anim)
        sprite.setFrame(m.from)
    end
    if w.kind == "laser" or w.kind == "blackhole" then
        enemyWeapons.charge(self, w, m.hitTimes[1]) -- showing where it'll burn
    end
end

--- A blow of melee move `m`: it lands if you're still within its reach,
--- with nothing between. Whether it did.
function Enemy:strike(m)
    local ex, ey = self.body:getPosition()
    local px, py = player.body:getPosition()
    local dx, dy = px - ex, py - ey
    local d = math.sqrt(dx * dx + dy * dy)
    if d > m.reach or not inSight(ex, ey, px, py) then return false end
    local dir = d > 1e-3 and vec2.new(dx / d, dy / d) or vec2.new(1, 0)
    player.hurt(m.damage, dir)
    if not player.god and not player.isSafe() then
        player.applyKnockback(dir, m.damage * 1.5 * (m.knock - 1)) -- on top of hurt's
    end
    enemyWeapons.sparks(px - dir.x * 10, py - dir.y * 10, dir.x, dir.y, 10, math.rad(60),
        { { 1, 0.95, 0.8 }, { 1, 0.6, 0.3 } }, 220, 0.18)
    local src = audio.playSoundAt("explosion", px, py, 0.05)
    if src then src:setPitch(2.2) end -- a short thud
    return true
end

--- Decide what to do until next time: where to go, and whether to shoot.
function Enemy:think(px, py)
    local ex, ey = self.body:getPosition()
    local dx, dy = px - ex, py - ey
    local d = math.max(1e-3, math.sqrt(dx * dx + dy * dy))
    local ux, uy = dx / d, dy / d
    local wx, wy, speed = 0, 0, 0
    self.los = false
    if d > AI.IDLE then
        self.thinkIn = AI.THINK_FAR
    elseif d > AI.FAR then
        wx, wy, speed = ux, uy, AI.DRIFT
        self.thinkIn = AI.THINK_FAR
    else
        self.los = d < AI.ENGAGE and inSight(ex, ey, px, py)
        if self.los then
            -- hold its range, circling you; about turn now and then, or when stuck
            local radial = math.max(-1, math.min(1, (d - self.range) / (self.range * 0.5)))
            if self.stuck or math.random() < 0.04 then self.orbit = -self.orbit end
            local around = self.brawler and 0.3 or 0.8 -- a brawler comes straight on
            wx, wy = ux * radial - uy * self.orbit * around, uy * radial + ux * self.orbit * around
            speed = AI.STRAFE + math.abs(radial) * 40
            self.thinkIn = AI.THINK_NEAR
        else
            -- the way round what's in the way, where the flow field reaches
            local f = flowTo(px, py, AI.now)
            local fx, fy
            if f:covers(ex, ey) then fx, fy = f:dir(ex, ey) end
            wx, wy = fx or ux, fy or uy
            speed = AI.SPEED
            self.thinkIn = d < AI.ENGAGE * 1.5 and AI.THINK_NEAR or AI.THINK_MID
        end
    end
    if speed > 0 then
        local sx, sy = separation(self, ex, ey)
        wx, wy = wx + sx * 1.5, wy + sy * 1.5
        local n = math.sqrt(wx * wx + wy * wy)
        if n > 1e-6 then wx, wy = wx / n * speed, wy / n * speed end
    end
    -- stuck: it wanted to move, but hardly is
    local vx, vy = self.body:getLinearVelocity()
    self.stuck = speed > 50 and vx * vx + vy * vy < 20 * 20
    self.wantX, self.wantY = wx, wy

    -- Within reach, hit you if it can; or else (not a brawler) use its
    -- special when it's ready, or shoot, when it can see you and you're
    -- within the weapon's reach
    local w, mm, sp = self.weapon, self.melee, self.special
    if mm and self.los and not self.attack and d < mm.reach * 0.9 and self.t >= self.meleeReady then
        self:startAttack(mm)
        self.meleeReady = self.t + mm.time + 0.3
    elseif sp and self.cast and self.los and not self.attack and not self.brawler and d < sp.reach
            and self.t >= self.specialReady and enemyWeapons.ready(sp) then
        self:startAttack(self.cast, sp)
        self.specialReady = self.t + sp.cooldown + self.jitter * 3
        self.last_fire_time = self.t -- (not straight into a shot after)
    elseif self.los and not self.attack and not self.brawler and d < w.reach
            and self.t - self.last_fire_time >= self.fire_cooldown + self.jitter then
        self:startAttack()
        self.last_fire_time = self.t
        self.jitter = math.random()
    end
end

-- Pull the trigger of the weapon its move fires (its own between moves): a
-- bullet weapon's first round now, a burst weapon's others following from
-- Enemy:update; anything else is enemyWeapons'.
function Enemy:fireAtPlayer()
    local w = self.attack and self.attack.weapon or self.weapon
    if w.kind ~= "bullet" then
        return enemyWeapons.fire(self, w)
    end
    self.firing = w
    self:shoot()
    self.burstLeft = w.shots - 1
    self.burstTimer = w.interval or 0
end

-- One round of the weapon it's firing at where the player will be when it
-- gets there (as far as it can tell: some lead you more than others).
function Enemy:shoot()
    if not (player and player.body) then return end
    local w = self.firing or self.weapon
    local ex, ey = self.body:getPosition()
    local px, py = player.body:getPosition()
    local pvx, pvy = player.body:getLinearVelocity()
    local lead = math.sqrt((px - ex) ^ 2 + (py - ey) ^ 2) / w.speed * self.lead
    local dx, dy = px + pvx * lead - ex, py + pvy * lead - ey
    local d = math.sqrt(dx * dx + dy * dy)
    if d == 0 then return end
    dx, dy = dx / d, dy / d

    local muzzle = vec2.new(ex + dx * 24, ey + dy * 24) -- clear of its own body
    local aim = math.atan2(dy, dx)
    for _ = 1, w.pellets do
        local a = aim + (math.random() - 0.5) * w.spread
        bullet.new({
            pos = muzzle,
            dir = vec2.new(math.cos(a), math.sin(a)),
            speed = w.speed * (0.95 + math.random() * 0.1),
            damage = w.damage,
            radius = w.radius,
            lifetime = w.lifetime,
            neon = w.neon,
            hostile = true,
            burst = w.burst, -- a rocket's or a fireball's, where it lands
        })
    end
    bullet.createMuzzleFlash(muzzle, vec2.new(dx, dy), {
        duration = 0.06, coneAngle = math.rad(25), coneLength = 70, intensity = 0.5, color = w.neon.core
    })
    audio.playSoundAt("enemyGun", ex, ey, 0.08)
    if self.move.aim then
        -- a floating gun kicks back with each shot
        local kick = self.body:getMass() * 90
        self.body:applyLinearImpulse(-dx * kick, -dy * kick)
    end
end

function Enemy:getDirectionToPlayer(n)
    -- if (not self) then return false end
    -- Validate n
    if not n or type(n) ~= "number" or n < 1 then
        n = 8 -- Default to 8 directions
    end
    n = math.floor(n)

    -- Get positions
    local ex, ey = self.body:getPosition()
    local px, py = player.body:getPosition()

    -- Calculate vector to player
    local dx = px - ex
    local dy = py - ey

    -- Check if positions are too close
    if math.abs(dx) < 0.01 and math.abs(dy) < 0.01 then
        return nil -- Player is at enemy's position
    end

    -- Calculate angle in radians
    local angle = math.atan2(dx, dy) -- dx first in this case i dunno

    -- Apply transform (e.g., rotation offset in radians or function)
    -- if transform then
    --     if type(transform) == "number" then
    --         angle = angle + transform
    --     elseif type(transform) == "function" then
    --         angle = transform(angle, dx, dy)
    --     end
    -- end

    -- Convert to degrees and normalize to [0, 360)
    local angle_deg = math.deg(angle)
    if angle_deg < 0 then
        angle_deg = angle_deg + 360
    end

    -- Map to one of n directions
    local sector_size = 360 / n
    local direction = math.floor((angle_deg + sector_size / 2) / sector_size) % n + 1

    return direction
end

function Enemy:damageEnemy(damage)
    self.health = self.health - damage
    -- self.damaged = true

    -- local ex, ey = self.body:getPosition()
    -- local nearby_count = 0
    -- for _, ind in ipairs(self.damage_indicators) do
    --     local dist = math.sqrt((ind.x - ex) ^ 2 + (ind.y - ey) ^ 2)
    --     if dist < 50 then
    --         nearby_count = nearby_count + 1
    --     end
    -- end

    -- local angle = (nearby_count * 45) % 360
    -- local spread_radius = math.min(15 + nearby_count * 3, 35)
    -- local spread_x = math.cos(math.rad(angle)) * spread_radius
    -- local spread_y = math.sin(math.rad(angle)) * spread_radius * 0.5
    -- local base_duration = 1.0
    -- local duration_multiplier = math.max(0.3, 1.0 - (nearby_count * 0.1))
    -- local final_duration = base_duration * duration_multiplier

    -- table.insert(self.damage_indicators, {
    --     x = ex + spread_x,
    --     y = ey - 10 + spread_y,
    --     damage = damage,
    --     time = 0,
    --     duration = final_duration,
    --     velocity_y = -80 - (nearby_count * 5),
    --     velocity_x = math.random(-10, 10) + spread_x * 0.3,
    --     alpha = 1,
    --     scale = 1.2,
    --     bounce_factor = 0.95,
    --     nearby_count = nearby_count
    -- })

    if self.health <= 0 then
        if self.fixture then
            -- Its light leaves the body and is drawn into the player, while the
            -- sprite fades out (enemy.update) and the enemy is then released.
            suckLight.spawn(self.body:getPosition())
            inventory.enemyDrop(self.body:getPosition()) -- now and then it leaves something
            trinkets.onKill(self.body:getPosition()) -- (the Leech Fang feeds)
            self.sprite = spriteOf(self)
            self.fadeT = 0
            -- table.remove(enemy.enemies, self.fixture:getUserData() + 1)
            self:killEnemy()
        end
    end
end

function Enemy:killEnemy()
    -- Fixture first: destroying a body destroys its fixtures, so the other order
    -- crashes ("Attempt to use destroyed fixture") whenever a kill happens
    -- outside a physics callback, where LOVE doesn't defer the destroys.
    self.fixture:destroy()
    self.body:destroy()
    self.fixture = nil
    self.dead = true
end

function Enemy:update(dt)
    if self.dead then return end
    self.t = self.t + dt
    if not (player and player.body) then return end
    self.thinkIn = self.thinkIn - dt
    if self.thinkIn <= 0 then
        self:think(player.body:getPosition())
    end
    -- Its move: a shot on each hit while it can still see you, or a blow
    local a = self.attack
    local m = a and a.move or self.move
    local shown -- seconds into its move the frame shown is from
    if a then
        a.t = a.t + dt
        shown = a.t
        while m.hitTimes[a.hit] and a.t >= m.hitTimes[a.hit] do
            shown = m.hitTimes[a.hit] -- the hit's own frame, however late this frame comes
            a.hit = a.hit + 1
            if m.reach then
                self:strike(m)
            else
                -- (bullets only at you in sight; a beam, bolt or black hole
                -- is stopped by what's between)
                local ex, ey = self.body:getPosition()
                if a.weapon.kind ~= "bullet" or inSight(ex, ey, player.body:getPosition()) then
                    self:fireAtPlayer()
                end
            end
        end
        if a.t >= m.time then
            self.attack, self.anim = nil, nil -- back to walking (below)
            m = self.move
        end
    end
    -- Steer toward the velocity it wants: slowly while it shoots, pressing
    -- in on you while it swings
    local wx, wy = self.wantX, self.wantY
    if self.attack and m.reach then
        local ex, ey = self.body:getPosition()
        local px, py = player.body:getPosition()
        local dx, dy = px - ex, py - ey
        local d = math.sqrt(dx * dx + dy * dy)
        local press = d > m.reach * 0.55 and 90 / d or 0
        wx, wy = dx * press, dy * press
    elseif self.attack then
        wx, wy = wx * 0.35, wy * 0.35
    end
    local vx, vy = self.body:getLinearVelocity()
    local k = AI.STEER * self.body:getMass()
    self.body:applyForce((wx - vx) * k, (wy - vy) * k)
    if self.burstLeft > 0 then
        self.burstTimer = self.burstTimer - dt
        if self.burstTimer <= 0 then
            self:shoot()
            self.burstLeft = self.burstLeft - 1
            self.burstTimer = (self.firing or self.weapon).interval or 0
        end
    end

    local sprite = spriteOf(self)
    if not sprite then return end
    if self.attack and m.anim then
        -- the move's frame now
        sprite.setFrame((m.from - 1 + math.min(m.count - 1, math.floor(shown * m.fps + 1e-6))) % m.frames + 1)
    elseif m.aim then
        -- turned to face you
        local ex, ey = self.body:getPosition()
        local px, py = player.body:getPosition()
        sprite.setFrame(mymath.heading(px - ex, py - ey, sprite.frameCount()))
    elseif m.rest then
        sprite.setFrame(m.rest.from + math.floor(self.t * m.rest.fps) % m.rest.count)
    else
        -- Walking, running (backing off or circling fast), or still
        local moving = self.wantX * self.wantX + self.wantY * self.wantY
        local anim = moving > 130 * 130 and "run" or moving > 1 and "walk" or "idle"
        if anim ~= self.anim then
            -- (not every look has them all: walk does for any)
            if not sprite.setAnimation(anim) then sprite.setAnimation("walk") end
            self.anim = anim
        end
    end
    -- for i = #self.damage_indicators, 1, -1 do
    --     local indicator = self.damage_indicators[i]
    --     indicator.time = indicator.time + dt
    --     local progress = indicator.time / indicator.duration
    --     local ease_out = 1 - math.pow(1 - progress, 3)

    --     indicator.y = indicator.y + indicator.velocity_y * dt * indicator.bounce_factor
    --     indicator.x = indicator.x + indicator.velocity_x * dt
    --     indicator.velocity_y = indicator.velocity_y * 0.98
    --     indicator.velocity_x = indicator.velocity_x * 0.95

    --     local fade_start = indicator.nearby_count > 3 and 0.5 or 0.7
    --     if progress > fade_start then
    --         local fade_progress = (progress - fade_start) / (1.0 - fade_start)
    --         indicator.alpha = 1 - math.pow(fade_progress, 1.5)
    --     else
    --         indicator.alpha = 1
    --     end

    --     indicator.scale = 1.2 - (ease_out * 0.4)

        -- for j, other in ipairs(self.damage_indicators) do
        --     if i ~= j and other.time < other.duration then
        --         local dx = indicator.x - other.x
        --         local dy = indicator.y - other.y
        --         local dist = math.sqrt(dx * dx + dy * dy)
        --         if dist < 20 and dist > 0 then
        --             local separation_force = (20 - dist) / 20 * 15
        --             local norm_x = dx / dist
        --             local norm_y = dy / dist
        --             indicator.velocity_x = indicator.velocity_x + norm_x * separation_force * dt
        --             indicator.velocity_y = indicator.velocity_y + norm_y * separation_force * dt
        --         end
        --     end
        -- end

        -- if indicator.time >= indicator.duration then
        --     table.remove(self.damage_indicators, i)
        -- end
    -- end
end

-- Global enemy manager
local enemy = {
    enemies = {},
    scale = 0.6,
    t = 0,
    fire_cooldown = 1,
    detection_range = 300,
    projectile_speed = 400,
    max_health = 20,
    health = {},
    damage_indicators = {},
    enemy_damaged = {},
    last_fire_times = {},
    -- Staggered loading state
    spawnQueue = {},       -- remaining enemies to spawn
    spawnBatchSize = 20,   -- spawn N enemies per frame during load (tunable)
    spawningComplete = false,
    totalToSpawn = 0,
}

-- An enemy slot's sprite (gun_enemies[index + 2]) is hidden until an enemy
-- takes the slot (enemy.addEnemy) and again once it has gone: characterAnimator
-- makes every instance a visible princess somewhere round the home map, and
-- any not following an enemy would stand there like a villager.
local function hideSprite(sprite)
    sprite.on = false
    sprite.opacity = nil
    sprite.currentSpriteIndex = nil -- out of the instanced draw entirely
end

local function hideAllSprites()
    for i = 2, var.num_enemies + 1 do
        if gun_enemies and gun_enemies[i] then hideSprite(gun_enemies[i]) end
    end
end

function enemy.load()
    grid:reset() -- (a new world)
    field = nil
    enemyWeapons.load()
    hideAllSprites()
    -- Staggered spawn: queue all enemies, spawn a few per frame
    enemy.spawnQueue = {}
    enemy.totalToSpawn = var.num_enemies
    for i = 1, var.num_enemies do
        local x = math.random(100, var.screen_width)
        local y = math.random(100, var.screen_height)
        local charType = ENEMY_TYPES[((i - 1) % #ENEMY_TYPES) + 1]
        table.insert(enemy.spawnQueue, {x = x, y = y, charType = charType, index = i - 1})
    end
    enemy.spawningComplete = false
end

-- Seconds a dead enemy takes to fade out: about as long as its light takes
-- to stream into the player.
enemy.DEATH_FADE_TIME = 0.7

-- What a dead enemy's slot in enemy.enemies holds once it has faded out: one
-- shared, inert stand-in, so nothing of the enemy itself (behaviour tree,
-- physics, sprite) stays referenced. The list is never compacted:
-- fixture userData and gun_enemies use fixed indices into it.
local RELEASED = setmetatable({ dead = true, cleanedUp = true, released = true,
    damage_indicators = {} }, Enemy)

local function releaseEnemy(i)
    -- (An enemy removed rather than killed never recorded its sprite; slot i
    -- was index i - 1, whose sprite is gun_enemies[(i - 1) + 2].)
    local sprite = enemy.enemies[i].sprite or (i <= var.num_enemies and gun_enemies[i + 1])
    if sprite then hideSprite(sprite) end
    enemy.enemies[i] = RELEASED
end

function enemy.update(dt)
    enemy.t = enemy.t + dt
    AI.now = enemy.t

    -- Who's where, for keeping clear of each other (Enemy:think)
    for i = 1, #usedBuckets do
        local list = buckets[usedBuckets[i]]
        for j = 1, list.n do list[j] = nil end
        list.n, usedBuckets[i] = 0, nil
    end
    for _, e in ipairs(enemy.enemies) do
        if not e.dead then
            local key = bucketKey(e.body:getPosition())
            local list = buckets[key]
            if not list then
                list = { n = 0 }
                buckets[key] = list
            end
            if list.n == 0 then usedBuckets[#usedBuckets + 1] = key end
            list.n = list.n + 1
            list[list.n] = e
        end
    end

    -- Staggered enemy spawning: create a batch per frame to avoid load-time freeze
    if not enemy.spawningComplete and #enemy.spawnQueue > 0 then
        local batch = math.min(enemy.spawnBatchSize, #enemy.spawnQueue)
        for _ = 1, batch do
            local spawn = table.remove(enemy.spawnQueue)
            if spawn then
                enemy.addEnemy(spawn.x, spawn.y)
            end
        end
    elseif not enemy.spawningComplete and #enemy.spawnQueue == 0 then
        enemy.spawningComplete = true
        print("All " .. enemy.totalToSpawn .. " enemies spawned (staggered)")
    end

    for i = #enemy.enemies, 1, -1 do
        local e = enemy.enemies[i]
        if e.dead then
            -- One-time teardown for a dead enemy: release its behaviour tree.
            -- (Its shots are pooled bullets that fly on without it.) Note:
            -- enemy.enemies is NOT compacted, because the fixture userData
            -- stores a fixed index into it that damage/gun_enemies rely on.
            if not e.cleanedUp then
                e.cleanedUp = true
                -- These tables are keyed by the 0-based index (enemy.addEnemy).
                enemy.last_fire_times[i - 1] = nil
                enemy.health[i - 1] = nil
                enemy.enemy_damaged[i - 1] = nil
            end
            if not e.released then
                e.fadeT = (e.fadeT or 0) + dt
                local k = e.fadeT / enemy.DEATH_FADE_TIME
                if k < 1 and e.sprite then
                    e.sprite.opacity = 1 - k
                else
                    releaseEnemy(i)
                end
            end
        else
            e:update(dt)
        end
    end
    enemyWeapons.update(dt) -- their beams, bolts and bursts
end

function enemy.damageEnemy(enemy_index, damage)
    -- print(enemy_index,"getting damaged")

    local e = enemy.enemies[enemy_index + 1]
    -- print(enemy.enemies[enemy_index])
    if e then
        e:damageEnemy(damage)
        enemy.health[enemy_index] = e.health
        enemy.enemy_damaged[enemy_index] = e.damaged
    end
end

function enemy.killEnemy(enemy_index)
    local e = enemy.enemies[enemy_index]
    if e then
        e:killEnemy()
    end
end

-- A new enemy in the next slot, shown as `charType` (by default its index's)
function enemy.addEnemy(x, y, charType)
    local index = #enemy.enemies
    local e = Enemy.new(world, x, y, enemy.max_health, enemy.scale, enemy.fire_cooldown,
        enemy.detection_range, enemy.projectile_speed, index)
    table.insert(enemy.enemies, e)

    local look = charType or ENEMY_TYPES[index % #ENEMY_TYPES + 1]
    local sprite = spriteOf(e)
    if sprite then
        sprite.on, sprite.opacity = true, nil
        sprite.x, sprite.y = x, y
        -- dot-call, not a method: characterAnimator instances expose plain
        -- closures (`function instance.setCharacterType(t)`)
        if sprite.setCharacterType(look) then e:setLook(look) end
    end

    enemy.last_fire_times[index] = enemy.t - enemy.fire_cooldown
    enemy.health[index] = e.health
    enemy.enemy_damaged[index] = false


    return index, e.body
end

function enemy.removeEnemy(enemy_index)
    local e = enemy.enemies[enemy_index]
    if e then
        e:killEnemy()
    end
end

-- Plain-data snapshot of every enemy slot for save files (util/serial.lua).
-- Dead slots are kept so each live enemy keeps its index, and with it its sprite.
function enemy.getSaveData()
    local slots = {}
    for i, e in ipairs(enemy.enemies) do
        if e.dead then
            slots[i] = { dead = true }
        else
            local x, y = e.body:getPosition()
            local vx, vy = e.body:getLinearVelocity()
            local sprite = gun_enemies[i + 1]
            slots[i] = {
                x = x, y = y, vx = vx, vy = vy,
                health = e.health,
                character = sprite and sprite.getCharacterType(),
            }
        end
    end
    local queue = {}
    for i, spawn in ipairs(enemy.spawnQueue) do
        queue[i] = { x = spawn.x, y = spawn.y, charType = spawn.charType, index = spawn.index }
    end
    return { slots = slots, spawn_queue = queue }
end

--- Remove every enemy quietly (no death light, no fade) and hide every
--- enemy sprite, the dead ones' included.
function enemy.clear()
    for i, e in ipairs(enemy.enemies) do
        if not e.released then
            if not e.dead then
                e:killEnemy()
            end
            releaseEnemy(i)
        end
    end
    hideAllSprites()
    enemy.enemies = {}
    enemy.health = {}
    enemy.enemy_damaged = {}
    enemy.last_fire_times = {}
end

-- Replace every enemy with the ones in a getSaveData() snapshot. A dead
-- slot keeps its sprite hidden.
function enemy.restore(data)
    enemy.clear()
    for i, slot in ipairs(data.slots or {}) do
        if slot.dead then
            enemy.enemies[i] = RELEASED
        else
            local index = enemy.addEnemy(slot.x, slot.y, slot.character)
            local e = enemy.enemies[index + 1]
            e.body:setLinearVelocity(slot.vx or 0, slot.vy or 0)
            e.health = slot.health or e.health
            enemy.health[index] = e.health
        end
    end

    enemy.spawnQueue = data.spawn_queue or {}
    enemy.spawningComplete = #enemy.spawnQueue == 0
end

function enemy.fireAtPlayer(enemy_index, enemy_x, enemy_y, player_x, player_y)
    local e = enemy.enemies[enemy_index]
    if e then
        e:fireAtPlayer()
    end
end

channelPreserve = { 1, 0, 1 } -- its counter intuitive but you need to preserve the too channels that will get one color cycle, if you preserve 1 channel you get 2 color cycle
-- function enemy.populate()
--     -- print(#enemy.enemies)
--     for _, e in ipairs(enemy.enemies) do

--         for _, proj in ipairs(e.projectiles) do
--             table.insert(dynamic_draw_list, {
--                 sort_y = proj[1].y + 140,
--                 image_or_particles = enemy.particleSystem,
--                 quad = nil,
--                 x = proj[1].x,
--                 y = proj[1].y,
--                 rotation = 0,
--                 scale_x = 1,
--                 scale_y = 1,
--                 offset_x = 0,
--                 offset_y = 0,
--                 color = { 1, 0.4, 0.2, 1 },
--                 blend_mode = { "lighten", "premultiplied" },
--                 source_object_type = "fire_effect"
--             })
--         end

--         -- for _, indicator in ipairs(e.damage_indicators) do
--         --     local damage = indicator.damage
--         --     local base_color, is_critical, is_mega_critical, is_splash = { 0.8, 0.2, 0.2 }, false, false,
--         --         indicator.is_splash_indicator
--         --     if is_splash then
--         --         base_color = { 0.2, 0.8, 1 }
--         --         is_critical = true
--         --     elseif type(damage) == "string" then
--         --         base_color = { 0.2, 0.8, 1 }
--         --         is_critical = true
--         --     elseif damage >= 35 then
--         --         base_color = { 1, 0.2, 1 }
--         --         is_mega_critical = true
--         --         is_critical = true
--         --     elseif damage >= 25 then
--         --         base_color = { 1, 0.5, 0.1 }
--         --         is_critical = true
--         --     elseif damage >= 18 then
--         --         base_color = { 1, 0.9, 0.2 }
--         --         is_critical = true
--         --     elseif damage >= 12 then
--         --         base_color = { 1, 0.3, 0.1 }
--         --     elseif damage >= 8 then
--         --         base_color = { 1, 0.15, 0.15 }
--         --     end

--         --     local saturation_boost = math.min(1.3, 1.0 + (indicator.nearby_count * 0.05))
--         --     local final_color = {
--         --         math.min(1, base_color[1] * saturation_boost),
--         --         math.min(1, base_color[2] * saturation_boost),
--         --         math.min(1, base_color[3] * saturation_boost)
--         --     }

--         --     local y_offset = -200 - (indicator.nearby_count * 2)
--         --     local final_scale = indicator.scale
--         --     local display_text
--         --     if is_splash then
--         --         final_scale = final_scale * 1.6
--         --         display_text = indicator.damage
--         --     elseif type(damage) == "string" then
--         --         final_scale = final_scale * 1.3
--         --         display_text = damage
--         --     else
--         --         local text_prefix = is_mega_critical and "★-" or is_critical and "!-" or "-"
--         --         final_scale = is_mega_critical and final_scale * 1.4 or is_critical and final_scale * 1.2 or final_scale
--         --         display_text = text_prefix .. damage
--         --     end

--         --     table.insert(dynamic_draw_list, {
--         --         sort_y = indicator.y + y_offset,
--         --         text = display_text,
--         --         x = indicator.x,
--         --         y = indicator.y,
--         --         font = gameFont,
--         --         color = { final_color[1], final_color[2], final_color[3], indicator.alpha },
--         --         scale = final_scale,
--         --         outline_color = { 0, 0, 0, indicator.alpha * (is_critical and 1.0 or 0.9) },
--         --         is_critical = is_critical,
--         --         is_mega_critical = is_mega_critical,
--         --         nearby_count = indicator.nearby_count,
--         --         blend_mode = { "alpha" },
--         --         source_object_type = "damage_indicator"
--         --     })

--         --     if is_mega_critical or is_splash then
--         --         table.insert(dynamic_draw_list, {
--         --             sort_y = indicator.y + y_offset - 1,
--         --             text = display_text,
--         --             x = indicator.x,
--         --             y = indicator.y,
--         --             font = gameFont,
--         --             color = is_splash and { 0.5, 1, 1, indicator.alpha * 0.4 } or { 1, 1, 1, indicator.alpha * 0.3 },
--         --             scale = final_scale * 1.1,
--         --             outline_color = { 0, 0, 0, 0 },
--         --             blend_mode = { "add" },
--         --             source_object_type = "damage_indicator"
--         --         })
--         --     end
--         -- end

--         -- if e.damaged and e.health > 0 then
--         --     local ex, ey = e.body:getPosition()
--         --     local health_percent = e.health / e.max_health
--         --     table.insert(dynamic_draw_list, {
--         --         sort_y = ey - 50,
--         --         rectangle = { x = ex - 25, y = ey - 35, width = 50, height = 6 },
--         --         color = { 0.2, 0.2, 0.2, 0.8 },
--         --         blend_mode = { "alpha" },
--         --         source_object_type = "health_bar_bg"
--         --     })
--         --     table.insert(dynamic_draw_list, {
--         --         sort_y = ey - 49,
--         --         rectangle = { x = ex - 24, y = ey - 34, width = 48 * health_percent, height = 4 },
--         --         color = health_percent > 0.3 and { 0.2, 0.8, 0.2, 0.9 } or { 0.8, 0.2, 0.2, 0.9 },
--         --         blend_mode = { "alpha" },
--         --         source_object_type = "health_bar_fill"
--         --     })
--         -- end

--         -- local ex, ey = e.body:getPosition()
--         -- local enemy_color = { 1, 1, 1, 1 }
--         -- if e.health then
--         --     local health_percent = e.health / e.max_health
--         --     if health_percent <= 0.3 then
--         --         local red_intensity = 1 - (health_percent / 0.3) * 0.3
--         --         enemy_color = { 1, 1 - red_intensity, 1 - red_intensity, 1 }
--         --     end
--         -- end

--         -- table.insert(dynamic_draw_list, {
--         --     sort_y = ey + (enemy_image and enemy_image:getHeight() * 0.1 / 2 or 0) + 100,
--         --     image_or_particles = enemy_image,
--         --     x = ex,
--         --     y = ey,
--         --     rotation = 0,
--         --     scale_x = 1,
--         --     scale_y = 1,
--         --     offset_x = enemy_image and enemy_image:getWidth() / 2 or 0,
--         --     offset_y = enemy_image and enemy_image:getHeight() / 2 or 0,
--         --     color = enemy_color,
--         --     blend_mode = { "alpha" },
--         --     source_object_type = "enemy"
--         -- })

--         local enemyInstance = gun_enemies[math.min(_ + 1,#enemy.enemies + 1)] -- the drawn instances

--         -- local princessInstance = princess[_]
--         -- enemyInstance.x, enemyInstance.y = ex, ey
--         enemyInstance.x, enemyInstance.y = e.body:getPosition()
--         -- princessInstance.x,princessInstance.y = ex+10,ey+10
--         -- print(player.velocity_x)
--         -- print(e:getDirectionToPlayer())
--         enemyInstance.setDirection(e:getDirectionToPlayer() or 1)
--         -- enemyInstance.setState(math.random(1,5))
--         -- characterAnimator.shader:send("outlineWidth", 1*math.sin(fire.t))

--         -- enemyInstance.color = {math.cos(fire.t*2 + _)*channelPreserve[1],math.cos(fire.t*2 + _)*channelPreserve[2],math.cos(fire.t*2 + _)*channelPreserve[3],math.sin(fire.t*2 + _)}
--     end
-- end


-- An enemy's tint: a slow pulse, offset by its index so they don't all match
local function enemyColor(enemy_index, colorPhase)
    local idx_offset = enemy_index * 0.3
    return {
        math.cos(colorPhase + idx_offset) * channelPreserve[1],
        math.cos(colorPhase + idx_offset) * channelPreserve[2],
        math.cos(colorPhase + idx_offset) * channelPreserve[3],
        math.sin(colorPhase + idx_offset)
    }
end

--------------------------------------------------------------------------------
-- Multiplayer: the host runs every enemy; clients only draw them
--------------------------------------------------------------------------------

local function round(v)
    return math.floor(v + 0.5)
end

--- Host: every enemy still on screen anywhere (alive, or fading out), with
--- what a client needs to draw it: its slot, position, character, facing,
--- animation (and its frame, when the game times it) and, while it fades,
--- opacity.
function enemy.getNetworkData()
    local list = {}
    for i, e in ipairs(enemy.enemies) do
        if not e.released and e.body and not e.body:isDestroyed() then
            local sprite = gun_enemies[i + 1]
            if sprite then
                local x, y = e.body:getPosition()
                list[#list + 1] = {
                    i = i,
                    x = round(x),
                    y = round(y),
                    c = sprite.getCharacterType(),
                    a = sprite.getCurrentAnimation(),
                    f = sprite.progressPinned and sprite.currentFrame or nil, -- a frame the game times
                    d = sprite.currentDirection,
                    o = sprite.opacity,
                }
            end
        end
    end
    return list
end

-- Client: where each enemy sprite is heading (it glides there between
-- snapshots), by gun_enemies index
local netTargets = {}

--- Client: show the host's enemies (enemy.getNetworkData) on this side's
--- sprites; every other enemy sprite is hidden.
function enemy.applyNetworkData(list)
    for k in pairs(netTargets) do
        netTargets[k] = nil
    end
    for _, n in ipairs(list or {}) do
        local sprite = gun_enemies[n.i + 1]
        if sprite and n.c then
            if sprite.getCharacterType() ~= n.c then
                sprite.setCharacterType(n.c)
                sprite.x, sprite.y = n.x, n.y -- new to us: appear in place
            end
            if n.a and sprite.getCurrentAnimation() ~= n.a then
                sprite.setAnimation(n.a)
            end
            if n.f then
                sprite.setFrame(n.f) -- (its attack, or a gun turning to you)
            elseif sprite.progressPinned then
                sprite.setAnimation(sprite.getCurrentAnimation()) -- the animator's clock again
            end
            sprite.setDirection(n.d or 1)
            sprite.opacity = n.o
            netTargets[n.i + 1] = n
        end
    end
end

--- Client, every frame: glide each shown enemy to where the host has it.
function enemy.updateNetworked(dt)
    local k = math.min(1, dt * 15)
    local colorPhase = math.cos(fire.t * 2)
    for i = 2, var.num_enemies + 1 do
        local sprite = gun_enemies[i]
        local n = netTargets[i]
        if sprite and n then
            if not sprite.on then
                sprite.x, sprite.y = n.x, n.y
            end
            sprite.on = true
            sprite.x = sprite.x + (n.x - sprite.x) * k
            sprite.y = sprite.y + (n.y - sprite.y) * k
            sprite.color = enemyColor(i - 2, colorPhase)
        elseif sprite then
            sprite.on = false
        end
    end
end

function enemy.populate()
    -- Clear or reset gun_enemies positions for dead enemies
    for i = 1, #gun_enemies do
        gun_enemies[i].active = false -- Mark as inactive initially
    end

    -- Viewport bounds for culling (camera-relative)
    if not camera or not camera.pos then
        -- fallback: skip populate if camera not ready
        return
    end
    local halfW = var.screen_width / camera.zoom / 2 + 100
    local halfH = var.screen_height / camera.zoom / 2 + 100
    -- World point at the centre of the screen (screen = (world + camera/zoom) * zoom).
    -- This used to be -camera/zoom, the top-left corner, so enemies in the right
    -- and lower parts of the screen were treated as off-screen.
    local camX = (var.screen_width / 2 - camera.pos.x) / camera.zoom
    local camY = (var.screen_height / 2 - camera.pos.y) / camera.zoom
    local viewLeft = camX - halfW
    local viewRight = camX + halfW
    local viewTop = camY - halfH
    local viewBottom = camY + halfH

    -- Pre-compute color phase for all enemies (avoids 3 trig calls per enemy)
    local colorPhase = math.cos(fire.t * 2)

    -- Map living enemies to gun_enemies based on their stored index
    -- NOTE: written with nested ifs rather than `goto continue_enemy`. goto and
    -- ::labels:: are Lua 5.2+/LuaJIT syntax; the web build runs on plain Lua
    -- 5.1 (love.js), where they are a hard parse error and take the whole game
    -- down before the first frame. (Enemies' shots are bullets, drawn by
    -- bullet.draw with the player's.)
    for _, e in ipairs(enemy.enemies) do
        if e.fixture and e.fixture:getUserData() then
            local enemy_index = e.fixture:getUserData()
            if enemy_index and enemy_index >= 0 and enemy_index < var.num_enemies then
                local ex, ey = e.body:getPosition()
                -- Lua arrays start at 1 (+ player is all stuffed into one array rn)
                local enemyInstance = gun_enemies[enemy_index + 2]
                -- Every live sprite follows its body, culled or not: a culled one
                -- used to stay where it left the view (and be drawn there), and an
                -- enemy killed off-screen faded and glowed at that stale spot.
                if enemyInstance then
                    enemyInstance.x, enemyInstance.y = ex, ey
                end

                -- Viewport culling: skip the per-enemy direction/colour work
                local offscreen = ex < viewLeft or ex > viewRight or ey < viewTop or ey > viewBottom
                if not offscreen then
                    if enemyInstance then
                        enemyInstance.active = true
                        enemyInstance.setDirection(e:getDirectionToPlayer() or 1)
                        enemyInstance.color = enemyColor(enemy_index, colorPhase)
                    end
                end
            end
        end
    end
end

return enemy
