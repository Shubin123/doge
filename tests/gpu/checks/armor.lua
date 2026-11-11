--[[
  Armor (game/armor.lua):

      python3 tests/gpu/run.py --checks --only armor

  1. five slots, the starter set on from the start, and it shows on the sprite;
  2. every piece is one of a kind, and each region has two for every slot;
  3. each region's pieces lie on clear ground in it that you can walk to;
  4. walking over one collects it, using it wears it, and what was on goes
     back in the bag;
  5. each stat does what it says, and nothing wears out;
  6. the panel's keys and clicks reach the worn column;
  7. saves keep what's worn, and every piece stays one of one;
  8. every piece has a 3D model of its own, and what's worn turns and moves
     with her.

  Leaves the sprite and the open bag in dist/gpu-test/checks-armor/.
]]
local nav = require("lib.nav")
local skin = require("ui.skin")

return function(h)
    local function check(name, ok, detail)
        h.check(name, ok, detail ~= nil and tostring(detail) or nil)
    end

    player.god = true
    while fire.getAvailableCount() > 0 do fire.removeFireball() end -- (they'd hide the sprite)
    player.lightsOn = false
    h.advance(5)
    for _, e in ipairs(enemy.enemies) do
        if not e.dead then e:killEnemy() end
    end
    local W, H = h.cfg.width, h.cfg.height
    local QUIET_X, QUIET_Y = -600, 1200

    local function stand(x, y)
        player.body:setPosition(x, y)
        player.body:setLinearVelocity(0, 0)
        camera.snap(player)
    end
    local function quiet()
        stand(QUIET_X, QUIET_Y)
        h.advance(2)
    end

    local function frame(name)
        h.capture(name)
        local f = assert(io.open(h.cfg.out .. "/" .. name .. ".rgba", "rb"))
        local data = f:read("*a")
        f:close()
        return data
    end
    -- How many pixels round the middle of the screen are the bare sprite's skin
    local function skinPixels(a)
        local n = 0
        for y = H / 2 - 42, H / 2 + 14 do -- (just the body: not the gun or what's flying round it)
            for x = W / 2 - 12, W / 2 + 6 do
                local i = (math.floor(y) * W + math.floor(x)) * 4
                local r, g, b = a:byte(i + 1), a:byte(i + 2), a:byte(i + 3)
                if r > 60 and r > g * 1.15 and b > g * 0.85 then n = n + 1 end
            end
        end
        return n
    end

    local function piecesOf(region)
        local list = {}
        for _, def in pairs(armor.DEFS) do
            if def.region == region then list[#list + 1] = def end
        end
        table.sort(list, function(a, b) return a.id < b.id end)
        return list
    end
    local function lying(id)
        local list = {}
        for _, g in ipairs(inventory.ground) do
            if g.id == id then list[#list + 1] = g end
        end
        return list
    end
    local function slotOf(id)
        for i = 1, inventory.SIZE do
            local s = inventory.slots[i]
            if s and s.id == id then return i end
        end
    end
    local function wear(id)
        inventory.add(id, 1)
        inventory.use(slotOf(id))
    end
    local function undress()
        for k = 1, #armor.SLOTS do armor.takeOff(k) end
        inventory.reset()
    end
    local function near(a, b, tolerance)
        return math.abs(a - b) <= (tolerance or 1e-6)
    end
    -- Every piece exists exactly once: worn, in the bag or on the ground
    local function oneOfEach()
        local wrong = {}
        for id, def in pairs(armor.DEFS) do
            local n = (armor.worn[def.slot] == id and 1 or 0) + inventory.count(id) + #lying(id)
            if n ~= 1 then wrong[#wrong + 1] = id .. "=" .. n end
        end
        table.sort(wrong)
        return #wrong == 0, table.concat(wrong, " ")
    end

    -- 1. Slots and the starter set (the harness starts undressed; this is
    -- the launch's own path)
    inventory.reset()
    quiet()
    local bare = frame("bare")
    var.player_armor = true
    armor.load()
    h.advance(1)
    local dressed = frame("starter")
    check("five slots", #armor.SLOTS == 5, table.concat(armor.SLOTS, ", "))
    local on = 0
    for _, slot in ipairs(armor.SLOTS) do
        local def = armor.DEFS[armor.worn[slot]]
        if def and def.set == "starter" and def.slot == slot then on = on + 1 end
    end
    check("the starter set is on from the start", on == 5, on .. " of 5")
    check("a new game has full hearts and light", player.health == player.maxHealth and gun.ammo == gun.maxAmmo,
        player.health .. "/" .. player.maxHealth .. " " .. gun.ammo .. "/" .. gun.maxAmmo)
    local before, after = skinPixels(bare), skinPixels(dressed)
    check("it shows on the sprite", before > 120 and after < before * 0.5, before .. " px of skin -> " .. after)

    -- 2. One of a kind
    local count, ids, names, looks, plain = 0, {}, {}, {}, {}
    for id, def in pairs(armor.DEFS) do
        count = count + 1
        names[def.name] = true
        local keys = {}
        for k, v in pairs(def.stats) do keys[#keys + 1] = k .. "=" .. v end
        table.sort(keys)
        looks[def.slot .. ":" .. table.concat(keys, ",")] = true
        ids[id] = true
        local item = inventory.ITEMS[id]
        if #keys == 0 or not item or item.armor ~= def.slot or item.stack ~= 1 or item.desc == "" then
            plain[#plain + 1] = id
        end
    end
    local function size(t)
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end
    check("fifty-five pieces", count == 55, count .. " pieces")
    check("each with a name of its own", size(names) == count, size(names) .. " names")
    check("and stats of its own", size(looks) == count, size(looks) .. " stat lines")
    check("each a one-to-a-slot bag item that lists its stats", #plain == 0, table.concat(plain, " "))
    check("five regions", #regions.list == 5)
    for _, r in ipairs(regions.list) do
        local slots = {}
        for _, def in ipairs(piecesOf(r.id)) do slots[def.slot] = (slots[def.slot] or 0) + 1 end
        local every = true
        for _, slot in ipairs(armor.SLOTS) do every = every and slots[slot] == 2 end
        check(r.name .. " has two pieces for every slot", every)
    end

    -- 3. Where they lie
    check("every piece is accounted for", oneOfEach())
    local grid = nav.new(24, 10)
    for _, r in ipairs(regions.list) do
        local from = r.spawn or { x = var.game_width / 2, y = var.game_height / 2 }
        local field = grid:flow(from.x, from.y, 110)
        local inside, clear, walkable, where = 0, 0, 0, {}
        for _, def in ipairs(piecesOf(r.id)) do
            local g = lying(def.id)[1]
            if g then
                if regions.at(g.x, g.y) == r then inside = inside + 1 end
                local blocked = false
                world:queryBoundingBox(g.x - 4, g.y - 4, g.x + 4, g.y + 4, function(f)
                    if not f:isSensor() and f:getBody():getType() == "static" then
                        blocked = true
                        return false
                    end
                    return true
                end)
                if not blocked then clear = clear + 1 end
                if field:stepsAt(g.x, g.y) then
                    walkable = walkable + 1
                else
                    where[#where + 1] = string.format("%s (%.0f, %.0f)", def.id, g.x, g.y)
                end
            end
        end
        check(r.name .. ": its pieces lie in it", inside == 10, inside .. " of 10")
        check(r.name .. ": on clear ground", clear == 10, clear .. " of 10")
        check(r.name .. ": that you can walk to", walkable == 10,
            walkable .. " of 10 " .. table.concat(where, ", "))
    end

    -- 4. Collecting and wearing, region by region
    for _, r in ipairs(regions.list) do
        local got, worn = 0, 0
        for _, def in ipairs(piecesOf(r.id)) do
            local g = lying(def.id)[1]
            if g then
                stand(g.x + 8, g.y)
                h.advance(2)
                if inventory.count(def.id) == 1 and #lying(def.id) == 0 then got = got + 1 end
                local before = armor.worn[def.slot]
                local i = slotOf(def.id)
                if i then
                    inventory.use(i)
                    if armor.worn[def.slot] == def.id and inventory.count(def.id) == 0
                        and (not before or inventory.slots[i] and inventory.slots[i].id == before) then
                        worn = worn + 1
                    end
                end
                if before then inventory.remove(before) end -- (room for the next region's)
            end
        end
        check(r.name .. ": walking over each collects it", got == 10, got .. " of 10")
        check(r.name .. ": using each wears it, the old one back in the bag", worn == 10, worn .. " of 10")
    end
    quiet()
    inventory.reset()
    armor.load()
    check("a piece gone from everywhere is back where it's found", oneOfEach())

    -- 5. What the stats do
    undress()
    check("nothing on: nothing added", player.maxHealth == 1000 and gun.maxAmmo == 100 and armor.speedScale() == 1
        and armor.rollScale() == 1 and armor.knockback() == 1 and #armor.statLines() == 0,
        player.maxHealth .. " " .. gun.maxAmmo)

    player.god = false
    player.health = 1000
    player.hurt(100, nil, "shot")
    check("bare, a shot takes all it does", near(player.health, 900), player.health)
    wear("scrap_plate") -- +8 defense, +12 vs shots, -4 speed
    player.health = 1000
    player.hurt(100, nil, "shot")
    check("defense and a resistance both cut a shot", near(player.health, 920), player.health)
    player.health = 1000
    player.hurt(100, nil, "blow")
    check("only defense cuts a blow", near(player.health, 908), player.health)
    player.health = 1000
    player.hurt(100)
    check("and what has no kind", near(player.health, 908), player.health)
    undress()

    wear("gas_mask") -- +3 defense, +25 vs bites
    player.health = 1000
    player.hurt(100, nil, "bite")
    check("a gas mask cuts bites", near(player.health, 928), player.health)
    undress()

    wear("steel_pauldrons") -- +8 defense, +35 poise
    player.health = 1000
    player.body:setLinearVelocity(0, 0)
    player.hurt(100, vec2.new(1, 0), "blow")
    local vx = player.body:getLinearVelocity()
    check("poise cuts knockback", near(vx, 92 * 1.5 * 0.65, 0.01), vx)
    undress()
    player.god = true

    player.health = 500
    wear("knights_cuirass") -- +14 defense, +1 heart, -6 speed
    check("hearts add to your maximum", player.maxHealth == 1100, player.maxHealth)
    check("wearing them can't heal you", near(player.health / player.maxHealth, 0.5), player.health)
    armor.takeOff(3)
    check("nor taking them off", near(player.health, 500) and player.maxHealth == 1000, player.health)
    undress()
    player.health = 1000

    player.health = 500
    wear("ash_sandals") -- +4 HP/s, +8 speed
    h.advance(60)
    check("regen heals over time", near(player.health, 504, 0.5), player.health)
    undress()
    player.health = 1000

    wear("holo_visor") -- +30 light, +15 vs energy
    gun.addAmmo(1000)
    check("light makes the bar longer", gun.maxAmmo == 130 and gun.ammo == 130, gun.ammo .. "/" .. gun.maxAmmo)
    armor.takeOff(1)
    check("and off, what's over goes", gun.maxAmmo == 100 and gun.ammo == 100, gun.ammo .. "/" .. gun.maxAmmo)
    undress()

    local function walkSpeed()
        quiet()
        local isDown = love.keyboard.isDown
        love.keyboard.isDown = function(k) return k == "d" end
        h.advance(40)
        local v = player.body:getLinearVelocity()
        love.keyboard.isDown = isDown
        quiet()
        return v
    end
    local function rollSpeed()
        quiet()
        player.dodgeCooldownTimer = 0
        local isDown = love.keyboard.isDown
        love.keyboard.isDown = function(k) return k == "d" or k == "space" end
        h.advance(2)
        local v = player.body:getLinearVelocity()
        love.keyboard.isDown = isDown
        h.advance(30)
        quiet()
        return v
    end
    local walk0, roll0 = walkSpeed(), rollSpeed()
    wear("flex_leggings") -- +10 speed, +15 roll
    local walk1, roll1 = walkSpeed(), rollSpeed()
    check("speed makes you quicker on foot", near(walk1 / walk0, 1.10, 0.01), string.format("%.0f -> %.0f", walk0, walk1))
    check("roll makes a roll faster", near(roll1 / roll0, 1.15, 0.01), string.format("%.0f -> %.0f", roll0, roll1))
    undress()
    wear("great_helm") -- +10 defense, -2 speed
    local walk2 = walkSpeed()
    check("heavy armor slows you", near(walk2 / walk0, 0.98, 0.01), string.format("%.0f -> %.0f", walk0, walk2))
    undress()

    -- Nothing wears out
    wear("bark_jerkin")
    local fresh = table.concat(armor.statLines(), ",")
    player.god = false
    for _ = 1, 300 do
        player.hurt(1, nil, "blow")
        player.health = 1000
    end
    player.god = true
    check("no wear: a piece is as good after 300 hits", table.concat(armor.statLines(), ",") == fresh, fresh)
    undress()

    -- 6. The panel
    armor.restore(nil)
    inventory.reset()
    armor.placeMissing()
    inventory.add("gas_mask", 1)
    love.keypressed("i")
    check("I opens the bag", inventory.open)
    love.keypressed("left") -- off the bag's left edge, onto the head slot
    love.keypressed("return")
    check("left onto the worn column, Enter takes it off",
        armor.worn.head == nil and inventory.count("patched_hood") == 1)
    love.keypressed("right") -- back to the gas mask
    love.keypressed("return")
    check("right back to the bag, Enter wears it", armor.worn.head == "gas_mask" and inventory.count("gas_mask") == 0)
    love.keypressed("right")
    love.keypressed("return")
    check("wearing over a worn piece swaps them",
        armor.worn.head == "patched_hood" and inventory.count("gas_mask") == 1 and inventory.count("patched_hood") == 0)
    love.keypressed("left")
    love.keypressed("left") -- round to the head slot again
    love.keypressed("down")
    love.keypressed("q")
    check("Q on a worn piece doesn't drop it", armor.worn.shoulders == "quilted_mantle")

    -- (the middle of a cell, as the panel lays them out on this screen)
    local u = skin.guiScale()
    local _, bagCells, wornCells = inventory.layout()
    local function middle(c) return (c.x + c.w / 2) * u, (c.y + c.h / 2) * u end
    local function wornCell(k) return middle(wornCells[k]) end
    local function bagCell(i) return middle(bagCells[i]) end
    local x, y = wornCell(3)
    local took = inventory.mousepressed(x, y, 1)
    check("a click on a worn piece takes it off", took and armor.worn.chest == nil and inventory.count("padded_vest") == 1)
    x, y = bagCell(slotOf("padded_vest"))
    took = inventory.mousepressed(x, y, 1)
    check("a click on a piece in the bag wears it", took and armor.worn.chest == "padded_vest")
    x, y = bagCell(slotOf("gas_mask"))
    took = inventory.mousepressed(x, y, 2)
    check("a right click drops one", took and inventory.count("gas_mask") == 0 and #lying("gas_mask") == 2,
        #lying("gas_mask") .. " lying")
    love.keypressed("escape")

    inventory.reset()
    inventory.add("medkit", inventory.SIZE * 8)
    local off = armor.takeOff(1)
    check("a full bag can't take what you take off", off == false and armor.worn.head == "patched_hood")
    inventory.remove("medkit", 8) -- (a stack: one slot's worth, for the mask)
    wear("gas_mask")
    check("but you can swap in a full bag", armor.worn.head == "gas_mask" and inventory.count("patched_hood") == 1)
    inventory.reset()

    -- 7. Saves
    armor.restore(nil)
    local g = lying("bark_jerkin")[1]
    stand(g.x + 8, g.y)
    h.advance(2)
    inventory.use(slotOf("bark_jerkin"))
    quiet()
    local state = serial.create()
    undress()
    serial.apply(state)
    check("a save keeps what's worn", armor.worn.chest == "bark_jerkin" and armor.worn.head == "patched_hood")
    check("what's in the bag", inventory.count("padded_vest") == 1)
    check("and a load leaves one of each", oneOfEach())
    state.armor, state.bag = nil, nil
    serial.apply(state)
    check("a save from before armor puts the starter set on", armor.worn.chest == "padded_vest")
    check("and lays out every piece", oneOfEach())

    -- What it looks like
    quiet()
    wear("great_helm")
    wear("arc_epaulets")
    wear("knights_cuirass")
    wear("flex_leggings")
    wear("mag_sneakers")
    inventory.add("gas_mask", 1)
    inventory.add("reliquary_robe", 1)
    while fire.getAvailableCount() > 0 do fire.removeFireball() end -- (they've grown back)
    h.advance(2)
    h.capture("worn")
    love.keypressed("i")
    h.advance(2)
    h.capture("bag_open")
    love.keypressed("escape")

    -- The models
    local armorModel = require("game.armorModel")
    local function painted(animation, frame, direction)
        local image = armorModel.render(animation, frame, direction):newImageData()
        local count, sum = 0, 0
        for y = 0, image:getHeight() - 1 do
            for x = 0, image:getWidth() - 1 do
                local r, g, b, a = image:getPixel(x, y)
                if a > 0.5 then
                    count = count + 1
                    sum = (sum * 31 + x * 7 + y * 13 + math.floor((r + g * 2 + b * 3) * 255)) % 1000003
                end
            end
        end
        return count, sum
    end
    local function distinct(list)
        local seen, n = {}, 0
        for _, v in ipairs(list) do
            if not seen[v] then seen[v], n = true, n + 1 end
        end
        return n
    end

    local turns, moves = {}, {}
    for direction = 1, 8 do
        local _, sum = painted("walk", 5, direction)
        turns[direction] = sum
    end
    for frame = 1, 18 do
        local _, sum = painted("walk", frame, 1)
        moves[frame] = sum
    end
    check("what's worn turns with her: all eight directions differ", distinct(turns) == 8, distinct(turns))
    check("and moves with her: the walk's frames differ", distinct(moves) >= 14, distinct(moves))

    local bare, looks, count = {}, {}, 0
    for id, def in pairs(armor.DEFS) do
        count = count + 1
        if armorModel.MODELS[id] then
            armorModel.setWorn({ def })
            local n, sum = painted("walk", 5, 1)
            if n < 12 then bare[#bare + 1] = id end
            looks[#looks + 1] = sum
        else
            bare[#bare + 1] = id
        end
    end
    check("every piece has a model that shows", #bare == 0, table.concat(bare, " "))
    check("and no two pieces look the same", distinct(looks) == count, distinct(looks) .. " of " .. count)
end
