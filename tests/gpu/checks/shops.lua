--[[
  Shops across the regions (game/shops.lua, read by game/shop.lua):

      python3 tests/gpu/run.py --checks --only shops

  1. every shop in shops.lua is there: the house's, and stalls in every
     region (two each), on clear ground in it;
  2. each sells what shops.lua says, and no two sell the same; between them
     there's food and trinkets;
  3. at each stall, E opens its panel while it's open, and something bought
     goes in the bag; shut, E says when it opens;
  4. a stall's counter stands in your way;
  5. a typo in shops.lua stops the game naming the shop and the field;
  6. saves keep the shelves.

  Leaves a frame of each region's stalls in dist/gpu-test/checks-shops/.
]]
return function(h)
    player.god = true
    h.advance(10)
    enemy.restore({ slots = {} })
    inventory.reset()

    local function stand(x, y)
        player.body:setPosition(x, y)
        player.body:setLinearVelocity(0, 0)
        camera.snap(player)
        h.advance(2)
    end
    local function regionOf(id)
        for _, r in ipairs(regions.list) do
            if r.id == id then return r end
        end
    end

    -- 1.
    local stalls, byRegion, outside = 0, {}, {}
    for _, s in ipairs(shop.list) do
        if s.stall then
            stalls = stalls + 1
            local r = regionOf(s.def.region)
            byRegion[r.id] = (byRegion[r.id] or 0) + 1
            if not (s.x > r.ox and s.x < r.ox + 2560 and s.y > r.oy and s.y < r.oy + 1920) then
                outside[#outside + 1] = s.id
            end
        end
    end
    local every = byRegion.wasteland == 2 and byRegion.castle == 2 and byRegion.neon == 2 and byRegion.sanctum == 2
    h.check("every region has its two stalls, the house its shop", every and shop.byId.home ~= nil and #outside == 0,
        string.format("%d stalls (%d wasteland, %d castle, %d neon, %d sanctum)%s", stalls, byRegion.wasteland or 0,
            byRegion.castle or 0, byRegion.neon or 0, byRegion.sanctum or 0,
            #outside > 0 and ("; outside their region: " .. table.concat(outside, ", ")) or ""))

    -- 2.
    local seen, same, food, trinketsSold = {}, {}, 0, 0
    for _, s in ipairs(shop.list) do
        local parts = {}
        for _, e in ipairs(s.def.stock) do
            parts[#parts + 1] = (e.item or e.trinket or "fireballs") .. ":" .. e.price
            if e.item and inventory.ITEMS[e.item].food then food = food + 1 end
            if e.trinket then trinketsSold = trinketsSold + 1 end
        end
        local key = table.concat(parts, ",")
        if seen[key] then same[#same + 1] = s.id .. " = " .. seen[key] end
        seen[key] = s.id
        local rows = shop.rows(s)
        if #rows < #s.def.stock then same[#same + 1] = s.id .. " lists less than its stock" end
    end
    h.check("each sells its own stock, food and trinkets among them", #same == 0 and food > 8 and trinketsSold > 5,
        string.format("%d foods and %d trinkets on sale%s", food, trinketsSold,
            #same > 0 and ("; " .. table.concat(same, "; ")) or ""))

    -- 3. At each stall: open at a time it keeps, shut at one it doesn't
    local function openHour(s)
        local hrs = s.def.hours
        if hrs == "always" then return 12 end
        return (hrs[1] + 1) % 24
    end
    local function shutHour(s)
        local hrs = s.def.hours
        if hrs == "always" or (hrs[1] == 0 and hrs[2] == 24) then return nil end
        return (hrs[2] + 1) % 24
    end
    local opened, bought, closed, shutChecked, failed = 0, 0, 0, 0, {}
    local captured = {}
    for _, s in ipairs(shop.list) do
        if s.stall then
            daynight.setHour(openHour(s))
            stand(s.x, s.y + 45)
            love.keypressed("e")
            if shop.open and shop.current == s then
                opened = opened + 1
                if not captured[s.def.region] then
                    captured[s.def.region] = true
                    love.keypressed("escape")
                    h.advance(1)
                    h.capture(s.def.region .. "_stall")
                    love.keypressed("e")
                end
                -- buy the first thing there's room for
                var.player_score = 10000
                local before = 0
                for i = 1, inventory.SIZE do
                    if inventory.slots[i] then before = before + inventory.slots[i].count end
                end
                love.keypressed("1")
                local after = 0
                for i = 1, inventory.SIZE do
                    if inventory.slots[i] then after = after + inventory.slots[i].count end
                end
                if after > before or s.def.stock[1].fireballs then bought = bought + 1 else failed[#failed + 1] = s.id end
                love.keypressed("escape")
                inventory.reset()
            else
                failed[#failed + 1] = s.id .. " (wouldn't open)"
            end
            local shut = shutHour(s)
            if shut then
                shutChecked = shutChecked + 1
                daynight.setHour(shut)
                h.advance(2)
                love.keypressed("e")
                if not shop.open then closed = closed + 1 end
                if shop.open then love.keypressed("escape") end -- (Esc with no panel is the menu)
            end
        end
    end
    h.check("at each stall E opens its panel, and what you buy goes in the bag", opened == stalls and bought == stalls,
        string.format("%d opened, %d sold%s", opened, bought, #failed > 0 and ("; " .. table.concat(failed, ", ")) or ""))
    h.check("shut, E won't open it", closed == shutChecked and shutChecked > 0,
        string.format("%d of %d shut", closed, shutChecked))

    -- 4. Walking into the counter from the front
    local s = shop.list[2]
    daynight.setHour(12)
    stand(s.x, s.y + 60)
    for _ = 1, 60 do
        player.body:setLinearVelocity(0, -200)
        h.advance(1)
    end
    local _, py = player.body:getPosition()
    h.check("a stall's counter stands in your way", py > s.y + 16, string.format("stopped %d px below its keeper", py - s.y))

    -- 5. A typo
    local ok, err = pcall(shop.validate, { { id = "typo", name = "Typo", region = "castle", at = "square",
        hours = { 8, 18 }, stock = { { item = "aple", price = 10 } } } })
    h.check("a typo in shops.lua names the shop and what's wrong", not ok and tostring(err):find("typo")
        and tostring(err):find("aple"), tostring(err))

    -- 6. Saves
    shop.restock()
    local data = shop.getSaveData()
    local want = {}
    for _, sh in ipairs(shop.list) do want[sh.id] = table.concat(sh.shelf, ",") end
    for _, sh in ipairs(shop.list) do sh.shelf = {} end
    shop.restore(data)
    local kept = true
    for _, sh in ipairs(shop.list) do
        if table.concat(sh.shelf, ",") ~= want[sh.id] then kept = false end
    end
    h.check("saves keep the shelves", kept)

    var.player_score = 0
    daynight.setHour(var.day_start)
end
