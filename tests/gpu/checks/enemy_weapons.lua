--[[
  Enemies fire every weapon you have, and attacks of their own
  (game/enemyWeapons.lua):

      python3 tests/gpu/run.py --checks --only enemy_weapons

  1. between them the enemies carry all of your weapons (pistol, SMG,
     shotgun, rifle, rocket launcher, tesla coil, bow, fireball, black hole
     gun) and the laser and multi-laser, each look its own set;
  2. each, fired by an enemy that carries it, hurts you: bullets in the
     weapon's colours, rockets and fireballs bursting, a tesla bolt jumping
     to you, a laser charging (showing where) and then burning, the
     multi-laser's fan of five, a black hole thrown at you that pulls you in
     and hurts at its heart;
  3. a wall stops a laser;
  4. they use their specials of their own accord.

  Leaves a frame of each in dist/gpu-test/checks-enemy_weapons/.
]]
return function(h)
    player.god = true
    h.advance(10)
    local W = enemyWeapons.WEAPONS
    local cx, cy = -800, 1400

    local function stand(x, y)
        player.body:setPosition(x, y)
        player.body:setLinearVelocity(0, 0)
        camera.snap(player)
    end
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

    -- 1. What they carry, over every enemy slot
    local carried, byLook = {}, {}
    for i = 0, var.num_enemies - 1 do
        local types = { "watchman", "mech", "steve", "watchman", "mech", "animated_special", "gun" }
        local look = types[i % #types + 1]
        local p, s = enemyWeapons.pick(look, i)
        carried[p.name] = true
        byLook[look] = byLook[look] or {}
        byLook[look][p.name] = true
        if s then
            carried[s.name] = true
            byLook[look][s.name] = true
        end
    end
    local missing = {}
    for _, name in ipairs({ "pistol", "smg", "shotgun", "rifle", "rocket", "tesla", "bow", "fireball",
            "blackhole", "laser", "multilaser" }) do
        if not carried[name] then missing[#missing + 1] = name end
    end
    h.check("between them they carry all your weapons, lasers and black holes", #missing == 0,
        #missing > 0 and ("missing " .. table.concat(missing, ", ")) or nil)
    local own = byLook.watchman.laser and byLook.mech.multilaser and byLook.animated_special.blackhole
        and byLook.gun.laser and byLook.steve.bow and byLook.mech.rocket and byLook.animated_special.tesla
    h.check("each look its own: watchmen lasers, mechs the multi-laser and rockets...", own and true or false)

    -- 2. Each fired at you by an enemy that carries it. Hold still `dist`
    -- off it; how much you were hurt, and what was seen on the way.
    local made = {}
    local new = bullet.new
    bullet.new = function(params)
        if params.hostile then made[#made + 1] = params end
        return new(params)
    end
    local function fire(slot, name, special, dist, seconds, watch)
        player.god = false
        player.health = player.maxHealth
        stand(cx, cy)
        local e = only(slot, { { cx + dist, cy } })[1]
        e.thinkIn = math.huge -- it does only what it's told
        e.wantX, e.wantY = 0, 0
        made = {}
        e:startAttack(special and e.cast or e.move, W[name])
        local seen = {}
        for f = 1, math.floor(seconds * 60) do
            player.body:setPosition(cx, cy)
            player.body:setLinearVelocity(0, 0)
            h.advance(1)
            if watch then watch(seen, f, e) end
        end
        local hurt = player.maxHealth - player.health
        player.health = player.maxHealth
        player.god = true
        return hurt, seen, e
    end

    local function bulletWeapon(slot, name)
        local hurt = fire(slot, name, false, 200, 2.5)
        local colour = #made > 0 and made[1].neon == W[name].neon
        h.check(string.format("an enemy's %s hurts you, in its colours", name), hurt > 0 and colour,
            string.format("%d HP, %d rounds", hurt, #made))
    end
    bulletWeapon(0, "pistol")
    bulletWeapon(0, "smg")
    bulletWeapon(0, "rifle")
    bulletWeapon(1, "shotgun")
    bulletWeapon(2, "bow")
    bulletWeapon(5, "orb")

    for _, b in ipairs({ { 1, "rocket" }, { 2, "fireball" } }) do
        local before = #explosion.explosions
        local exploded = false
        local hurt = fire(b[1], b[2], false, 200, 2.5, function(seen)
            if #explosion.explosions > before then exploded = true end
        end)
        local direct = W[b[2]].damage
        h.check(string.format("an enemy's %s bursts where it lands", b[2]), hurt > direct,
            string.format("%d HP (%d a direct hit)%s", hurt, direct, exploded and ", an explosion" or ""))
    end

    local hurt, seen = fire(5, "tesla", false, 180, 2.5, function(seen)
        if #enemyWeapons.bolts > 0 and not seen.bolt then
            seen.bolt = true
            h.capture("tesla")
        end
    end)
    h.check("an enemy's tesla bolt jumps to you", hurt >= W.tesla.damage and seen.bolt,
        string.format("%d HP%s", hurt, seen.bolt and ", a bolt" or ", no bolt"))

    local function laser(slot, name, beams, label)
        local hurt, seen = fire(slot, name, true, 220, 2.5, function(seen)
            local charging, burning = 0, 0
            for _, b in ipairs(enemyWeapons.beams) do
                if b.charging then charging = charging + 1 else burning = burning + 1 end
            end
            seen.charging = math.max(seen.charging or 0, charging)
            seen.burning = math.max(seen.burning or 0, burning)
            if burning > 0 and not seen.shot then
                seen.shot = true
                h.capture(label)
            end
        end)
        h.check(string.format("an enemy's %s charges, then burns you (%s)", name, label),
            hurt > 30 and seen.charging == beams and seen.burning == beams,
            string.format("%d HP; %d beams charging, %d burning", hurt, seen.charging or 0, seen.burning or 0))
    end
    laser(0, "laser", 1, "watchman")
    laser(1, "multilaser", 5, "mech")
    laser(6, "laser", 1, "floating gun") -- its aim held on you while it charges

    -- the black hole: thrown at you, it pulls you in and hurts at its heart
    local pulled
    hurt, seen = fire(5, "blackhole", true, 220, 1.6, function(seen)
        for _, hole in ipairs(blackholeGun.holes) do
            if hole.hostile and not hole.flying then seen.hole = hole end
        end
    end)
    local hole = seen.hole
    if hole then
        -- let go of you: you fall in
        player.god = false
        player.health = player.maxHealth
        local x0, y0 = player.body:getPosition()
        local d0 = math.sqrt((hole.x - x0) ^ 2 + (hole.y - y0) ^ 2)
        for _ = 1, 90 do h.advance(1) end
        h.capture("blackhole")
        local x1, y1 = player.body:getPosition()
        pulled = d0 - math.sqrt((hole.x - x1) ^ 2 + (hole.y - y1) ^ 2)
        hurt = player.maxHealth - player.health
        player.health = player.maxHealth
        player.god = true
    end
    h.check("an enemy's black hole opens on you and pulls you in", hole ~= nil and pulled and pulled > 10,
        hole and string.format("%.0f px off you, pulled %.0f px in", math.sqrt((hole.x - cx) ^ 2 + (hole.y - cy) ^ 2),
            pulled or 0) or "none opened")
    h.check("and hurts at its heart", hurt > 0, string.format("%d HP", hurt))
    for i = #blackholeGun.holes, 1, -1 do table.remove(blackholeGun.holes, i) end

    -- 3. A wall stops a laser: the house between you
    local house = map.houseInstances[1]
    player.god = false
    player.health = player.maxHealth
    local px, py = house.x, house.y - 170
    stand(px, py)
    local e = only(0, { { house.x + 10, house.y + 170 } })[1]
    e.thinkIn, e.wantX, e.wantY = math.huge, 0, 0
    e:startAttack(e.cast, W.laser)
    local short = true
    for _ = 1, 90 do
        player.body:setPosition(px, py)
        player.body:setLinearVelocity(0, 0)
        h.advance(1)
        for _, b in ipairs(enemyWeapons.beams) do
            if b.y2 < house.y - 120 then short = false end
        end
    end
    hurt = player.maxHealth - player.health
    player.health = player.maxHealth
    player.god = true
    h.check("a wall stops a laser", short and hurt == 0, string.format("%d HP", hurt))

    -- 4. Of their own accord: a watchman and a mech left to it, in sight
    local specials = {}
    local start = Enemy.startAttack
    Enemy.startAttack = function(self, m, w)
        if w and w == self.special then specials[w.name] = true end
        return start(self, m, w)
    end
    stand(cx, cy)
    only(0, { { cx + 260, cy }, { cx - 260, cy } }) -- slots 0 and 1
    for _ = 1, 60 * 10 do
        player.body:setLinearVelocity(0, 0)
        h.advance(1)
    end
    Enemy.startAttack = start
    h.check("they use their specials of their own accord", specials.laser and specials.multilaser and true or false,
        (specials.laser and "a laser " or "") .. (specials.multilaser and "a multi-laser" or ""))

    bullet.new = new
    enemy.restore({ slots = {} })
end
