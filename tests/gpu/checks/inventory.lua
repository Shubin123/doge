--[[
  The bag (game/inventory.lua):

      python3 tests/gpu/run.py --checks --only inventory

  1. items stack up to their limit, then fill empty slots, until it's full;
  2. using one does what it says and uses it up (and keeps it when it can't);
     H heals with a bandage;
  3. the shop sells into the bag;
  4. items on the ground slide into the bag; a dropped one lands ahead and
     comes back only after a moment; enemies leave some behind;
  5. saves keep the bag and the ground, and a save from before the bag
     empties it;
  6. I opens the panel and Esc closes it (not the menu).

  Leaves a screenshot of the open bag in dist/gpu-test/checks-inventory/.
]]
return function(h)
    player.god = true
    h.advance(5)
    inventory.reset()
    local function stand(x, y)
        player.body:setPosition(x, y)
        player.body:setLinearVelocity(0, 0)
        camera.snap(player)
    end
    -- somewhere quiet: no enemies about to bump into
    for _, e in ipairs(enemy.enemies) do
        if not e.dead then e:killEnemy() end
    end
    stand(-600, 1200)
    h.advance(2)

    -- 1. Stacks
    h.check("20 bandages go in", inventory.add("bandage", 20) == 20 and inventory.count("bandage") == 20)
    h.check("as a stack of 16 and one of 4", inventory.slots[1].count == 16 and inventory.slots[2].count == 4)
    inventory.add("bandage", 3)
    h.check("more top up the stack that has room", inventory.slots[2].count == 7 and not inventory.slots[3])
    local medkits = inventory.add("medkit", 1000)
    h.check("medkits fill every other slot and no more", medkits == 16 * 8 and inventory.room("medkit") == 0,
        medkits .. " went in")
    h.check("and a full bag takes nothing", inventory.add("light_cell", 1) == 0)
    inventory.remove("medkit", 1000)
    h.check("remove takes them out again", inventory.count("medkit") == 0 and inventory.count("bandage") == 23)

    -- 2. Using
    player.health = player.maxHealth / 2
    local before = player.health
    inventory.use(1)
    h.check("a bandage heals two hearts", player.health == before + player.maxHealth / 5,
        string.format("%.0f -> %.0f", before, player.health))
    h.check("and is used up", inventory.count("bandage") == 22)
    player.health = player.maxHealth
    inventory.use(1)
    h.check("at full hearts it's kept", inventory.count("bandage") == 22)
    player.health = player.maxHealth / 2
    love.keypressed("h")
    h.check("H heals with one", player.health > player.maxHealth / 2 and inventory.count("bandage") == 21)
    inventory.add("light_cell", 1)
    gun.ammo = 0
    for i = 1, inventory.SIZE do
        if inventory.slots[i] and inventory.slots[i].id == "light_cell" then inventory.use(i) end
    end
    h.check("a light cell fills the light bar", gun.ammo == gun.maxAmmo and inventory.count("light_cell") == 0)

    -- 3. The shop
    local bandages = inventory.count("bandage")
    for _, item in ipairs(shop.ITEMS) do
        if item.name == "Bandage" then
            h.check("the shop can sell a bandage", (item.can()))
            item.buy()
        end
    end
    h.check("and it goes in the bag", inventory.count("bandage") == bandages + 1)

    -- 4. The ground
    inventory.reset()
    local px, py = player.body:getPosition()
    inventory.place("medkit", 2, px + 50, py)
    inventory.place("light_cell", 1, px + 400, py)
    h.advance(30)
    h.check("an item nearby slides into the bag", inventory.count("medkit") == 2 and #inventory.ground == 1,
        #inventory.ground .. " left on the ground")
    h.check("one far off stays put", inventory.count("light_cell") == 0)
    gun.lastAimDirection.x, gun.lastAimDirection.y = 1, 0
    inventory.drop(1)
    h.check("a dropped one lands ahead", inventory.count("medkit") == 1 and #inventory.ground == 2
        and inventory.ground[2].x > px + 10)
    h.advance(30)
    h.check("and doesn't come straight back", inventory.count("medkit") == 1, "0.5 s on")
    h.advance(90)
    h.check("but does after a moment", inventory.count("medkit") == 2)
    inventory.ground = {}
    for _ = 1, 1000 do inventory.enemyDrop(0, 0) end
    h.check("enemies leave something now and then", #inventory.ground > 30 and #inventory.ground < 200,
        #inventory.ground .. " of 1000")
    inventory.ground = {}

    -- 5. Saves
    inventory.reset()
    inventory.add("bandage", 5)
    inventory.add("light_cell", 2)
    inventory.place("medkit", 1, 123, 456)
    local state = serial.create()
    inventory.reset()
    serial.apply(state)
    -- (the car key lies by the car whenever nobody has it: game/car.lua's check covers it)
    local function lying()
        local list = {}
        for _, g in ipairs(inventory.ground) do
            if g.id ~= "car_key" then list[#list + 1] = g end
        end
        return list
    end
    h.check("a save keeps the bag", inventory.count("bandage") == 5 and inventory.count("light_cell") == 2)
    h.check("and what's on the ground", #lying() == 1 and lying()[1].x == 123 and lying()[1].id == "medkit")
    state.bag = nil
    serial.apply(state)
    h.check("a save from before the bag empties it", inventory.count("bandage") == 0 and #lying() == 0)

    -- 6. The panel
    inventory.add("bandage", 12)
    inventory.add("medkit", 3)
    inventory.add("light_cell", 1)
    love.keypressed("i")
    h.check("I opens the bag", inventory.open)
    love.keypressed("right")
    h.advance(2)
    h.capture("bag")
    love.keypressed("escape")
    h.check("Esc closes it, not the menu", not inventory.open and var.State ~= "menu", var.State)
    love.keypressed("tab")
    h.check("Tab opens it too", inventory.open)
    love.keypressed("tab")
end
