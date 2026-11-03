--[[
  Watchmen and mechs fight hand to hand up close (game/enemy.lua's MELEE):

      python3 tests/gpu/run.py --checks --only enemy_melee

  1. a watchman next to you punches: its punch animation plays, and each
     blow lands on a frame where its fist is out (5, 10);
  2. a mech spins its blades at you: its attack animation, blows on the
     frames they're out (19, 27, 45), harder and throwing you further;
  3. step out of reach as it swings and the blow misses;
  4. it goes on swinging while you stay in reach;
  5. brawlers (half of each) come in from afar to fight like this, and
     don't shoot.

  Leaves a frame of each swinging in dist/gpu-test/checks-enemy_melee/.
]]
return function(h)
    player.god = true
    h.advance(10)
    local cx, cy = -800, 1400

    local function stand(x, y)
        player.body:setPosition(x, y)
        player.body:setLinearVelocity(0, 0)
        camera.snap(player)
    end
    -- Only these enemies, `dead` empty slots before them (an enemy's index
    -- picks its look and whether it's a brawler)
    local function only(dead, list)
        local slots = {}
        for i = 1, dead do slots[i] = { dead = true } end
        enemy.restore({ slots = slots })
        local made = {}
        for _, p in ipairs(list) do
            enemy.addEnemy(p[1], p[2])
            made[#made + 1] = enemy.enemies[#enemy.enemies]
        end
        h.advance(1)
        return made
    end
    local function spriteOf(e)
        return gun_enemies[e.fixture:getUserData() + 2]
    end

    -- Every blow that lands: the animation and frame its enemy shows
    local blows = {}
    local hurt = player.hurt
    local current
    player.hurt = function(amount, dir)
        blows[#blows + 1] = { amount = amount, frame = h.frame, e = current }
        return hurt(amount, dir)
    end
    local strike = Enemy.strike
    local swings = 0
    if strike then
        Enemy.strike = function(self, m)
            swings = swings + 1
            current = self
            local ok = strike(self, m)
            current = nil
            return ok
        end
    end
    local shots = 0
    local fire = Enemy.fireAtPlayer
    Enemy.fireAtPlayer = function(self)
        shots = shots + 1
        return fire(self)
    end

    -- Hold you still for `frames`, noting what each blow's enemy showed
    -- on the frame it landed
    local function hold(frames, x, y)
        for _ = 1, frames do
            if x then player.body:setPosition(x, y) end
            player.body:setLinearVelocity(0, 0)
            h.advance(1)
            for _, b in ipairs(blows) do
                if b.frame == h.frame and b.e and not b.anim then
                    local s = spriteOf(b.e)
                    b.anim, b.shown = s.getCurrentAnimation(), s.currentFrame
                end
            end
        end
    end

    local function landed(want, hits)
        local n, off = 0, {}
        for _, b in ipairs(blows) do
            n = n + 1
            if not (b.anim == want and hits[b.shown]) then
                off[#off + 1] = tostring(b.anim) .. ":" .. tostring(b.shown)
            end
        end
        return n, off
    end

    player.god = false
    player.health = player.maxHealth

    -- 1. A watchman right by you (slot 7, a brawler: the others back off to
    -- their gun's range after a swing)
    stand(cx, cy)
    only(7, { { cx + 45, cy } })
    blows = {}
    hold(60 * 3, cx, cy)
    local n, off = landed("punch", { [5] = true, [10] = true })
    h.check("a watchman next to you punches, on its fists' frames", n >= 2 and #off == 0,
        string.format("%d blows, %d off: %s", n, #off, table.concat(off, ", ")))
    local punched = n
    h.check("and goes on swinging while you stay in reach", punched >= 4,
        string.format("%d blows in 3 s", punched))

    -- 2. A mech (slot 8, a brawler)
    player.health = player.maxHealth
    stand(cx, cy)
    local mech = only(8, { { cx + 60, cy } })[1]
    blows = {}
    local hurtTaken = 0
    for _ = 1, 60 * 3 do
        hold(1, cx, cy)
        if mech.attack and mech.attack.t > 1.2 and not h.flags then
            h.flags = true
            h.capture("mech_spin")
        end
    end
    h.flags = nil
    n, off = landed("attack", { [19] = true, [27] = true, [45] = true })
    for _, b in ipairs(blows) do hurtTaken = math.max(hurtTaken, b.amount) end
    h.check("a mech spins its blades at you, on their frames", n >= 3 and #off == 0,
        string.format("%d blows, %d off: %s", n, #off, table.concat(off, ", ")))
    h.check("harder than a punch", hurtTaken > 35, string.format("%d HP a blow", hurtTaken))

    -- 3. Out of reach as it swings
    player.health = player.maxHealth
    stand(cx, cy)
    local w = only(7, { { cx + 45, cy } })[1]
    for _ = 1, 60 do
        hold(1, cx, cy)
        if w.attack then break end
    end
    blows = {}
    local swung = w.attack ~= nil
    hold(60, cx - 300, cy) -- (it gives chase, but can't reach you in time)
    h.check("step out of reach as it swings and it misses", swung and #blows == 0,
        string.format("%s, %d blows landed", swung and "it swung" or "it never swung", #blows))
    h.capture("missed")

    -- 5. A brawler (slot 7: a watchman) from afar
    player.god = true
    stand(cx, cy)
    local b = only(7, { { cx + 450, cy } })[1]
    blows, shots, swings = {}, 0, 0
    local closest = math.huge
    for _ = 1, 60 * 6 do
        hold(1, cx, cy)
        local bx, by = b.body:getPosition()
        closest = math.min(closest, math.sqrt((bx - cx) ^ 2 + (by - cy) ^ 2))
    end
    h.check("brawlers come in from afar and swing at you", closest < 70 and swings > 0,
        string.format("closest %.0f px, %d swings", closest, swings))
    h.check("and don't shoot", shots == 0, shots .. " shots")

    player.hurt = hurt
    Enemy.fireAtPlayer = fire
    if strike then Enemy.strike = strike end
    player.health = player.maxHealth
end
