--[[
  Food (game/inventory.lua's apple, bread, drumstick, glowberries, chili):

      python3 tests/gpu/run.py --checks --only food

  1. an apple heals a heart, a drumstick four, and neither is eaten at
     full hearts;
  2. bread heals three hearts over six seconds;
  3. glowberries put 35 back in the light bar;
  4. a chili makes you quicker for 15 s, then you're back to your pace;
  5. H eats something when there's no bandage;
  6. the shop sells some, and enemies leave some behind.
]]
return function(h)
    player.god = true
    h.advance(10)
    enemy.restore({ slots = {} })
    local cx, cy = -800, 1400
    player.body:setPosition(cx, cy)
    camera.snap(player)
    local function eat(id)
        inventory.reset()
        inventory.add(id, 2)
        return inventory.use(1)
    end

    -- 1.
    player.health = 500
    eat("apple")
    local apple = player.health - 500
    player.health = 500
    eat("drumstick")
    local drumstick = player.health - 500
    player.health = player.maxHealth
    local eaten = eat("apple")
    h.check("an apple heals a heart, a drumstick four", apple == 100 and drumstick == 400,
        string.format("+%d, +%d", apple, drumstick))
    h.check("and at full hearts they're kept", not eaten and inventory.count("apple") == 2)

    -- 2.
    player.health = 500
    eat("bread")
    local at = player.health
    h.advance(180)
    local half = player.health
    h.advance(200)
    h.check("bread heals three hearts over six seconds", at == 500 and half > 600 and half < 700
        and math.abs(player.health - 800) < 1, string.format("%d at once, %d after 3 s, %d after", at, half, player.health))

    -- 3.
    gun.ammo = 40
    eat("glowberries")
    h.check("glowberries put 35 back in the light bar", gun.ammo == 75, string.format("%d light", gun.ammo))
    gun.ammo = gun.maxAmmo

    -- 4. Walking right, before and after a chili
    local isDown = love.keyboard.isDown
    love.keyboard.isDown = function(k) return k == "d" end
    local function pace()
        player.body:setPosition(cx, cy)
        h.advance(60)
        return (player.body:getLinearVelocity())
    end
    local before = pace()
    eat("chili")
    local quick = pace()
    h.advance(60 * 14)
    local after = pace()
    love.keyboard.isDown = isDown
    player.body:setLinearVelocity(0, 0)
    h.check("a chili makes you quicker for 15 s, then you're back to your pace",
        quick > before * 1.3 and math.abs(after - before) < 5,
        string.format("%.0f px/s, %.0f with it, %.0f after", before, quick, after))

    -- 5.
    inventory.reset()
    inventory.add("apple", 3)
    player.health = 500
    love.keypressed("h")
    h.check("H eats something when there's no bandage", player.health == 600 and inventory.count("apple") == 2)
    player.health = player.maxHealth

    -- 6.
    local sold = {}
    for _, item in ipairs(shop.ITEMS) do sold[item.name] = true end
    h.check("the shop sells apples, bread and glowberries", sold.Apple and sold.Bread and sold.Glowberries and true or false)
    inventory.reset()
    for i = 1, 400 do inventory.enemyDrop(cx + i, cy + 300) end
    local food = 0
    for _, g in ipairs(inventory.ground) do
        if inventory.ITEMS[g.id].food then food = food + 1 end
    end
    h.check("enemies leave food behind now and then", food > 10, string.format("%d of 400 left food", food))
    inventory.reset()
end
