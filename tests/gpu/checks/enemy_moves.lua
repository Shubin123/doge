--[[
  Enemies' shots and their animations go together (game/enemy.lua's MOVES):

      python3 tests/gpu/run.py --checks --only enemy_moves

  1. every trigger pull leaves on the frame of its animation where the arm
     or guns are out (where the art reaches furthest: tests/gpu/README.md's
     way of finding them is in the MOVES comment), never between;
  2. each time an attack plays, its weapon fires on each of those frames;
  3. once it has played, the enemy walks again rather than going on
     playing it between shots;
  4. the floating gun turns to face you;
  5. it all runs on the game's clock: at 30 frames a second the shots
     land on the same frames.

  Leaves a frame of each look shooting in dist/gpu-test/checks-enemy_moves/.
]]
return function(h)
    player.god = true
    h.advance(10)

    -- The frames each look's shots leave on (its animation, and where in it
    -- the art reaches furthest from the body)
    local EXPECT = {
        watchman = { anim = "shoot", hits = { [1] = true, [12] = true }, per = 2 },
        mech = { anim = "shoot", hits = { [14] = true, [2] = true }, per = 2 },
        steve = { anim = "walk", hits = { [13] = true }, per = 1 },
        animated_special = { anim = "default", hits = { [48] = true }, per = 1 },
    }

    -- No enemies, and the next one in the first slot again (with a sprite:
    -- killed slots aren't reused)
    local function clearAll()
        enemy.restore({ slots = {} })
        h.advance(2)
    end
    local function stand(x, y)
        player.body:setPosition(x, y)
        player.body:setLinearVelocity(0, 0)
        camera.snap(player)
    end
    local function hold(frames)
        for _ = 1, frames do
            player.body:setLinearVelocity(0, 0)
            h.advance(1)
        end
    end

    -- Each trigger pull: who, and (once the frame's drawn) the frame it showed
    local pulls = {}
    local fire = Enemy.fireAtPlayer
    Enemy.fireAtPlayer = function(self)
        local sprite = gun_enemies[self.fixture:getUserData() + 2]
        pulls[#pulls + 1] = { e = self, look = sprite.getCharacterType(), sprite = sprite, frame = h.frame }
        return fire(self)
    end
    local function note()
        for _, p in ipairs(pulls) do
            if p.frame == h.frame and not p.anim then
                p.anim, p.shown = p.sprite.getCurrentAnimation(), p.sprite.currentFrame
            end
        end
    end

    local function look(e)
        return gun_enemies[e.fixture:getUserData() + 2].getCharacterType()
    end

    local function play(seconds)
        clearAll()
        pulls = {}
        local cx, cy = -800, 1400
        stand(cx, cy)
        -- one of each look, a few steps off round you
        for i = 0, 6 do
            local a = i / 7 * math.pi * 2
            enemy.addEnemy(cx + math.cos(a) * 170, cy + math.sin(a) * 170)
        end
        local walking, attacks, pinnedAfter = {}, {}, {}
        local wasAttacking = {}
        for f = 1, math.floor(seconds / h.dt) do
            hold(1)
            note()
            for _, e in ipairs(enemy.enemies) do
                if not e.dead then
                    local l = look(e)
                    local sprite = gun_enemies[e.fixture:getUserData() + 2]
                    local anim = sprite.getCurrentAnimation()
                    -- 3: a frame after a watchman's or mech's shooting stops, it walks
                    if wasAttacking[e] and not e.attack and (l == "watchman" or l == "mech") then
                        attacks[l] = (attacks[l] or 0) + 1
                        if anim == "shoot" then pinnedAfter[l] = (pinnedAfter[l] or 0) + 1 end
                    end
                    wasAttacking[e] = e.attack ~= nil
                end
            end
        end
        return attacks, pinnedAfter
    end

    -- 1-3 at 60 frames a second
    local attacks, pinnedAfter = play(14)
    h.capture("shooting")
    local byLook, off = {}, {}
    for _, p in ipairs(pulls) do
        local l = p.look
        local want = EXPECT[l]
        if want then
            byLook[l] = (byLook[l] or 0) + 1
            if not (p.anim == want.anim and want.hits[p.shown]) then
                off[#off + 1] = string.format("%s %s:%s", l, tostring(p.anim), tostring(p.shown))
            end
        end
    end
    local looks = 0
    for _ in pairs(byLook) do looks = looks + 1 end
    h.check("every shot leaves on its animation's shooting frame", #off == 0 and looks == 4,
        string.format("%d pulls from %d looks; %d off: %s", #pulls, looks, #off,
            table.concat(off, ", ", 1, math.min(#off, 6))))

    -- 2: each attack fires once per shooting frame
    local short = {}
    local starts = {}
    local start = Enemy.startAttack
    Enemy.startAttack = function(self)
        starts[self] = (starts[self] or 0) + 1
        return start(self)
    end
    local shotsBy = {}
    pulls = {}
    -- (play() clears and lays out a new set, so count again over it)
    play(10)
    Enemy.startAttack = start
    for _, p in ipairs(pulls) do shotsBy[p.e] = (shotsBy[p.e] or 0) + 1 end
    local played, matched = 0, 0
    for e, n in pairs(starts) do
        if e.fixture then
            local want = EXPECT[look(e)]
            if want then
                played = played + 1
                -- (the last may still be playing)
                local got = shotsBy[e] or 0
                if got >= (n - 1) * want.per and got <= n * want.per then
                    matched = matched + 1
                else
                    short[#short + 1] = string.format("%s %d plays %d shots", look(e), n, got)
                end
            end
        end
    end
    h.check("each time an attack plays, it fires on each of its frames", played >= 4 and matched == played,
        string.format("%d of %d%s", matched, played, #short > 0 and (": " .. table.concat(short, ", ")) or ""))

    local stuck, total = 0, 0
    for l, n in pairs(attacks) do
        total = total + n
        stuck = stuck + (pinnedAfter[l] or 0)
    end
    h.check("once it has played, they walk again", total > 0 and stuck == 0,
        string.format("%d of %d attacks left playing the shooting animation", stuck, total))

    -- 4: the floating gun faces you
    local faced, guns = 0, 0
    for _, e in ipairs(enemy.enemies) do
        if not e.dead and look(e) == "gun" then
            guns = guns + 1
            local sprite = gun_enemies[e.fixture:getUserData() + 2]
            local ex, ey = e.body:getPosition()
            local px, py = player.body:getPosition()
            local want = mymath.heading(px - ex, py - ey, sprite.frameCount and sprite.frameCount() or 455)
            if math.abs(sprite.currentFrame - want) <= 2 then faced = faced + 1 end
        end
    end
    h.check("the floating gun turns to face you", guns > 0 and faced == guns,
        string.format("%d of %d", faced, guns))

    -- 5: at 30 frames a second
    local dt = h.dt
    h.dt = 1 / 30
    play(12)
    h.dt = dt
    off = {}
    local n = 0
    for _, p in ipairs(pulls) do
        local want = EXPECT[p.look]
        if want then
            n = n + 1
            if not (p.anim == want.anim and want.hits[p.shown]) then
                off[#off + 1] = string.format("%s %s:%s", p.look, tostring(p.anim), tostring(p.shown))
            end
        end
    end
    h.check("at 30 frames a second too", n > 0 and #off == 0,
        string.format("%d pulls, %d off: %s", n, #off, table.concat(off, ", ", 1, math.min(#off, 6))))

    Enemy.fireAtPlayer = fire
end
