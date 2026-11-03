--[[
  Trinkets (game/trinkets.lua): worn, they work on their own, each paying in
  light when it does something, and doing nothing without the light:

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
  7. one picked up is worn, a fourth goes in the bag; using it there with
     the slots full says so; taking one off puts it in the bag;
  8. the shop's shelf has two you haven't got, and buying one wears it;
  9. saves keep what you wear.

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
    local function wearOnly(...)
        trinkets.worn = { ... }
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

    -- 7. Picking up, the bag, taking off
    inventory.reset()
    wearOnly()
    stand(cx, cy)
    local order = { "ember_heart", "leech_fang", "lantern_moth", "static_soles" }
    for i, id in ipairs(order) do
        inventory.place(id, 1, cx + 10 + i, cy)
        hold(4)
    end
    local worn = #trinkets.worn
    h.check("one picked up is worn, a fourth goes in the bag", worn == 3 and inventory.count("static_soles") == 1,
        string.format("%d worn, %d in the bag", worn, inventory.count("static_soles")))
    local slot
    for i = 1, inventory.SIZE do
        if inventory.slots[i] and inventory.slots[i].id == "static_soles" then slot = i end
    end
    local ok = slot and inventory.use(slot)
    h.check("using it with the slots full doesn't", not ok and inventory.count("static_soles") == 1)
    trinkets.unwear(2)
    ok = slot and inventory.use(slot)
    h.check("taking one off puts it in the bag, and then it goes on", ok and trinkets.wears("static_soles")
        and inventory.count("leech_fang") == 1, table.concat({ tostring(trinkets.worn[1]), tostring(trinkets.worn[2]),
            tostring(trinkets.worn[3]) }, ", "))
    inventory.open = true
    h.capture("bag")
    inventory.open = false

    -- 8. The shop's shelf
    wearOnly("mirror_ward")
    inventory.reset()
    trinkets.restock()
    local shelf = trinkets.shopItems()
    local fine = #shelf == 2
    for _, row in ipairs(shelf) do
        if trinkets.owns(row.trinket) then fine = false end
    end
    var.player_score = 1000
    local first = shelf[1] and shelf[1].trinket
    if shelf[1] and shelf[1].can() then shelf[1].buy() end
    h.check("the shop shelves two you haven't got, and buying one wears it", fine and first ~= nil
        and trinkets.wears(first) and #trinkets.shopItems() == 1,
        string.format("%d on the shelf; bought %s", #shelf, tostring(first)))

    -- 9. Saves
    local data = trinkets.getSaveData()
    wearOnly()
    trinkets.restore(data)
    h.check("saves keep what you wear", trinkets.wears("mirror_ward") and trinkets.wears(first))

    wearOnly()
    inventory.reset()
    player.health = player.maxHealth
    gun.ammo = gun.maxAmmo
    gun.addAmmo = addAmmo
end
