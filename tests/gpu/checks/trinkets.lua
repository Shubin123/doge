--[[
  Trinkets (game/trinkets.lua): in the bag and equipped, they work on their
  own, each paying in light when it does something, and doing nothing
  without the light:

      python3 tests/gpu/run.py --checks --only trinkets

  1. the Mirror Ward turns an enemy's shot back at them (4 light); without
     the light the shot hurts you;
  2. the Ember Heart, when you're hurt, burns what's round you (12 light);
  3. the Leech Fang heals half a heart a kill while you're hurt (3 light),
     and costs nothing at full hearts;
  4. the Lantern Moth zaps a nearby enemy (2 light);
  5. the Phoenix Feather saves you from a killing blow once (80 light),
     then rests: the next one kills you;
  6. the Static Soles shock what's round you as a roll ends (6 light);
  7. they take bag slots like everything else: one picked up goes in a
     slot, equipped, and a full bag leaves it on the ground; using it
     unequips it (it does nothing then, and costs nothing), and again
     equips it; saves keep one unequipped;
  8. the shop's shelf has two you haven't got, and buying one puts it in
     the bag, equipped;
  9. the play-testing loadout (var.equip_all_trinkets) has every one in
     the bag, equipped.

  Leaves frames of the ward, the moth and the bag in
  dist/gpu-test/checks-trinkets/.
]]
return function(h)
    player.god = true
    h.advance(10)
    local cx, cy = -800, 1400
    -- (dead enemies' light streaming back into you would refill what a
    -- trinket just spent)
    local addAmmo = gun.addAmmo
    gun.addAmmo = function() end

    local function stand(x, y)
        player.body:setPosition(x, y)
        player.body:setLinearVelocity(0, 0)
        camera.snap(player)
    end
    local function only(list)
        enemy.restore({ slots = {} })
        local made = {}
        for _, p in ipairs(list) do
            enemy.addEnemy(p[1], p[2])
            local e = enemy.enemies[#enemy.enemies]
            e.thinkIn, e.wantX, e.wantY = math.huge, 0, 0 -- still, and not shooting
            made[#made + 1] = e
        end
        return made
    end
    local function hold(frames)
        for _ = 1, frames do
            player.body:setPosition(cx, cy)
            player.body:setLinearVelocity(0, 0)
            h.advance(1)
        end
    end
    -- Only these in the bag, equipped
    local function wearOnly(...)
        inventory.reset()
        for _, id in ipairs({ ... }) do inventory.add(id, 1) end
    end
    local function fresh(light)
        player.god = false
        player.health = player.maxHealth
        gun.ammo = light or gun.maxAmmo
        stand(cx, cy)
    end
    local function alive(list)
        local n = 0
        for _, e in ipairs(list) do if not e.dead then n = n + 1 end end
        return n
    end

    -- 1. Mirror Ward: a pistol round from 160 px off
    local function shotAt(light)
        fresh(light)
        local e = only({ { cx + 160, cy } })[1]
        e.firing = enemyWeapons.WEAPONS.pistol
        e.lead = 0
        e:shoot()
        local friendly = 0
        for _ = 1, 40 do
            hold(1)
            for _, b in ipairs(bullet.instances) do
                if not b.hostile then friendly = friendly + 1 end
            end
        end
        return player.maxHealth - player.health, (light or gun.maxAmmo) - gun.ammo, friendly, e
    end
    wearOnly("mirror_ward")
    local hurt, spent, back, e = shotAt()
    h.check("the Mirror Ward turns a shot back at them", hurt == 0 and spent == 4 and back > 0 and e.dead,
        string.format("%d HP, %d light, %s", hurt, spent, e.dead and "the shooter's down" or "the shooter stands"))
    h.capture("mirror_ward")
    hurt, spent = shotAt(2)
    h.check("without the light it can't, and the shot hurts", hurt > 0 and spent == 0,
        string.format("%d HP, %d light", hurt, spent))

    -- 2. Ember Heart
    fresh()
    wearOnly("ember_heart")
    local near = only({ { cx + 60, cy }, { cx - 70, cy + 20 }, { cx + 300, cy } })
    player.hurt(50)
    hold(3)
    h.check("the Ember Heart burns what's round you when you're hurt", near[1].dead and near[2].dead and not near[3].dead
        and gun.maxAmmo - gun.ammo == 12, string.format("%d of 3 standing, %d light", alive(near), gun.maxAmmo - gun.ammo))

    -- 3. Leech Fang
    fresh()
    wearOnly("leech_fang")
    local prey = only({ { cx + 200, cy }, { cx + 240, cy } })
    player.health = 500
    prey[1]:damageEnemy(math.huge)
    hold(1)
    local healed, cost = player.health - 500, gun.maxAmmo - gun.ammo
    player.health = player.maxHealth
    gun.ammo = gun.maxAmmo
    prey[2]:damageEnemy(math.huge)
    hold(1)
    h.check("the Leech Fang heals half a heart a kill while you're hurt", healed == 50 and cost == 3
        and gun.ammo == gun.maxAmmo, string.format("+%d HP for %d light; at full hearts %d light",
            healed, cost, gun.maxAmmo - gun.ammo))

    -- 4. Lantern Moth
    fresh()
    wearOnly("lantern_moth")
    local moths = only({ { cx + 120, cy + 30 }, { cx + 600, cy } })
    hold(20)
    h.capture("lantern_moth")
    hold(70)
    h.check("the Lantern Moth zaps a nearby enemy", moths[1].dead and not moths[2].dead
        and gun.maxAmmo - gun.ammo == 2, string.format("%d of 2 standing, %d light", alive(moths), gun.maxAmmo - gun.ammo))

    -- 5. Phoenix Feather
    fresh()
    wearOnly("phoenix_feather")
    local around = only({ { cx + 80, cy } })
    player.health = 100
    player.hurt(400)
    local saved = player.health
    hold(3)
    h.check("the Phoenix Feather saves you from a killing blow", saved == 300 and around[1].dead
        and gun.maxAmmo - gun.ammo == 80, string.format("%d HP after, %d light", saved, gun.maxAmmo - gun.ammo))
    hold(100) -- past the moment nothing hurts you
    gun.ammo = gun.maxAmmo
    player.health = 100
    player.hurt(400)
    local after = player.health
    player.health = player.maxHealth
    h.check("then it rests: the next one kills you", after == 0, string.format("%d HP", after))

    -- 6. Static Soles: a roll ending
    fresh()
    wearOnly("static_soles")
    local soles = only({ { cx + 50, cy + 10 }, { cx + 260, cy } })
    player.isDodging, player.dodgeTimer = true, 0.05
    hold(10)
    h.check("the Static Soles shock what's round you as a roll ends", soles[1].dead and not soles[2].dead
        and gun.maxAmmo - gun.ammo == 6, string.format("%d of 2 standing, %d light", alive(soles), gun.maxAmmo - gun.ammo))
    enemy.restore({ slots = {} })
    player.god = true

    -- 7. Bag slots like everything else
    inventory.reset()
    stand(cx, cy)
    inventory.place("lantern_moth", 1, cx + 12, cy)
    hold(4)
    local slot
    for i = 1, inventory.SIZE do
        if inventory.slots[i] and inventory.slots[i].id == "lantern_moth" then slot = i end
    end
    h.check("one picked up goes in a bag slot, equipped", slot ~= nil and trinkets.wears("lantern_moth"))
    for i = 1, inventory.SIZE do
        if not inventory.slots[i] then inventory.slots[i] = { id = "bandage", count = 16 } end
    end
    inventory.place("ember_heart", 1, cx + 12, cy)
    hold(10)
    h.check("a full bag leaves one on the ground", not trinkets.owns("ember_heart") and #inventory.ground > 0)
    inventory.reset()
    inventory.add("lantern_moth", 1)
    inventory.use(1)
    gun.ammo = gun.maxAmmo
    local idle = only({ { cx + 100, cy } })
    hold(60)
    h.check("using it unequips it: it does nothing, and costs nothing", not trinkets.wears("lantern_moth")
        and not idle[1].dead and gun.ammo == gun.maxAmmo and inventory.count("lantern_moth") == 1)
    local data = inventory.getSaveData()
    inventory.restore(data)
    h.check("saves keep it unequipped", inventory.count("lantern_moth") == 1 and not trinkets.wears("lantern_moth"))
    inventory.use(1)
    hold(60)
    h.check("using it again equips it", trinkets.wears("lantern_moth") and idle[1].dead)
    inventory.add("mirror_ward", 1)
    inventory.add("apple", 5)
    inventory.slots[2].on = false
    inventory.open = true
    h.capture("bag")
    inventory.open = false
    enemy.restore({ slots = {} })

    -- 8. The shop's shelf
    wearOnly("mirror_ward")
    trinkets.restock()
    local shelf = trinkets.shopItems()
    local fine = #shelf == 2
    for _, row in ipairs(shelf) do
        if trinkets.owns(row.trinket) then fine = false end
    end
    local first = shelf[1] and shelf[1].trinket
    if shelf[1] and shelf[1].can() then shelf[1].buy() end
    h.check("the shop shelves two you haven't got; one bought goes in the bag, equipped", fine and first ~= nil
        and trinkets.wears(first) and #trinkets.shopItems() == 1,
        string.format("%d on the shelf; bought %s", #shelf, tostring(first)))

    -- 9. The play-testing loadout
    inventory.reset()
    trinkets.equipAll()
    local all = 0
    for _, id in ipairs(trinkets.LIST) do
        if trinkets.wears(id) then all = all + 1 end
    end
    h.check("the play-testing loadout has every one in the bag, equipped", all == #trinkets.LIST,
        string.format("%d of %d", all, #trinkets.LIST))
    h.capture("everything_equipped")

    wearOnly()
    inventory.reset()
    player.health = player.maxHealth
    gun.ammo = gun.maxAmmo
    gun.addAmmo = addAmmo
end
