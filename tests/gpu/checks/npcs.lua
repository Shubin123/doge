--[[
  Nobody stands about outside the house: the only character that isn't you
  or an enemy is the shopkeeper (drawn by game/shop.lua, inside).

      python3 tests/gpu/run.py --checks --only npcs

  characterAnimator makes every instance a visible princess at a random spot
  round the home map; an enemy sprite not following a live enemy used to be
  left like that. It happened:

  1. while enemies spawn, a batch a frame, to the slots not yet taken;
  2. loading a save with dead enemies in it (every launch carries on from
     the newest save), to each dead slot;
  3. after the console's `spawn enemies`, to every sprite of the old ones.
]]
return function(h)
    player.god = true

    -- Characters drawn that are neither you nor a live (or fading) enemy
    local function strays()
        local live = {}
        for i, e in ipairs(enemy.enemies) do
            if not e.released then live[i + 1] = true end
        end
        local n, where = 0, {}
        for i = 2, #gun_enemies do
            local g = gun_enemies[i]
            if g.on and g.currentSpriteIndex and not live[i] then
                n = n + 1
                if #where < 4 then
                    where[#where + 1] = string.format("%s at %.0f,%.0f", tostring(g.characterType), g.x, g.y)
                end
            end
        end
        return n, table.concat(where, "; ")
    end

    local function stand(x, y)
        player.body:setPosition(x, y)
        player.body:setLinearVelocity(0, 0)
        camera.snap(player)
    end

    -- 1. a fresh world (as the harness starts), enemies still spawning
    h.advance(1)
    local n, where = strays()
    h.check("while enemies spawn, no sprite waits in the open", n == 0,
        string.format("%d stray (%s), %d spawned", n, where, #enemy.enemies))
    h.advance(10)
    n, where = strays()
    h.check("once they're all out, every sprite is an enemy", n == 0 and #enemy.enemies == var.num_enemies,
        string.format("%d stray (%s), %d enemies", n, where, #enemy.enemies))

    -- 2. a save with dead enemies, loaded at launch: sprites as
    -- characterAnimator makes them (visible princesses round home), then
    -- restored
    for i = 1, 30 do enemy.enemies[i]:damageEnemy(math.huge) end
    h.advance(60)
    local data = enemy.getSaveData()
    for i = 2, var.num_enemies + 1 do
        local g = gun_enemies[i]
        g.on, g.opacity = true, nil
        g.setCharacterType("princess")
        g.x, g.y = 100 + i * 15, 100 + (i * 37) % 800
    end
    enemy.restore(data)
    h.advance(2)
    local alive = 0
    for _, e in ipairs(enemy.enemies) do
        if not e.dead then alive = alive + 1 end
    end
    n, where = strays()
    h.check("loading a save, a dead enemy's sprite stays hidden", n == 0 and alive == var.num_enemies - 30,
        string.format("%d stray (%s), %d alive", n, where, alive))
    local types = {}
    for i, e in ipairs(enemy.enemies) do
        if not e.dead then
            local t = gun_enemies[i + 1].getCharacterType()
            types[t] = (types[t] or 0) + 1
        end
    end
    h.check("and no live enemy is shown as the princess", not types.princess,
        string.format("%d princesses", types.princess or 0))

    -- 3. the console
    command.execute("spawn enemies 10")
    h.advance(2)
    n, where = strays()
    local shown = 0
    for i = 2, var.num_enemies + 1 do
        if gun_enemies[i].on and gun_enemies[i].currentSpriteIndex then shown = shown + 1 end
    end
    h.check("spawn enemies 10 leaves 10 enemies and nobody else", n == 0 and shown == 10,
        string.format("%d stray (%s), %d shown", n, where, shown))

    -- In the open by the house, by day: you and the enemies only
    local house = map.houseInstances[1]
    daynight.setHour(12)
    stand(house.x - 260, house.y + 160)
    h.advance(5)
    h.capture("outside_house")
    daynight.setHour(var.day_start)
end
