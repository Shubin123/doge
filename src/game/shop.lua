--[[
  Shops: the house on the home map, and stalls scattered through each
  region, every one of them set out in game/shops.lua (what it sells and
  for how much, where it stands, its hours and colours: edit that file, not
  this one). A keeper behind a counter sells for XP while the shop's open,
  and sleeps while it's shut.

    * Walk up to the counter and press E: a panel lists what's for sale.
      Up/Down pick, Enter buy (or 1-9 to buy at once, or click one), Esc or
      E closes. It closes on its own if you walk off or the shop shuts.
    * The house's shop is inside it, where you're safe (player.isSafe:
      nothing hurts you there, and its door is too narrow for enemies).
    * A stall stands out in the open, on the square round a region's portal
      or its market square: a striped awning on two posts, the keeper under
      it and a counter in front with a lantern on it. Nothing's safe there.
      It's only there once its region's boss is beaten (bosses.cleared:
      game/bosses.lua); until then its counter's body is switched off.
    * Besides its stock a shop can put out a few trinkets you haven't got
      (its shelf), new each morning.

  What's sold costs XP (var.player_score, the globs you've picked up) and
  goes in your bag (game/inventory.lua), trinkets equipped, but for
  fireballs, which go straight onto the hotbar. Saves keep the shelves.
]]
local skin = require("ui.skin")
local normalmap = require("lib.graphics.normalmap")
local nav = require("lib.nav")
local inventory = require("game.inventory")
local SHOPS = require("game.shops")

local shop = {}

local REACH = 70        -- px from the keeper you can trade at
local SIGN_RANGE = 260  -- px: this close, a stall's name shows over it
local DAWN = 6          -- the hour shelves are restocked
local STALL_W = 32      -- a stall's counter, in its sprite's texels (drawn at twice that)

shop.list = {}    -- every shop: its entry in shops.lua, where its keeper stands, its shelf
shop.byId = {}
shop.current = nil -- the one whose panel is open (or was last)
shop.ITEMS = {}   -- its rows
shop.open = false
local selected = 1
local message, messageAt = nil, -math.huge
local font
local rng -- what goes on the shelves
local lastHour

local PALETTE = {
    k = { 0.08, 0.08, 0.10 }, -- outline
    h = { 0.36, 0.22, 0.12 }, -- hair
    s = { 0.93, 0.75, 0.60 }, -- skin
    S = { 0.78, 0.58, 0.45 }, -- skin shadow
    e = { 0.10, 0.10, 0.14 }, -- eye
    m = { 0.48, 0.31, 0.17 }, -- moustache
    c = { 0.27, 0.48, 0.78 }, -- shirt
    a = { 0.88, 0.85, 0.74 }, -- apron
    A = { 0.66, 0.62, 0.52 }, -- apron shadow
    p = { 0.30, 0.30, 0.36 }, -- trousers
    b = { 0.32, 0.20, 0.12 }, -- boots
    B = { 0.74, 0.50, 0.27 }, -- light wood
    w = { 0.55, 0.34, 0.17 }, -- wood
    W = { 0.33, 0.19, 0.10 }, -- dark wood
    y = { 1.00, 0.84, 0.35 }, -- lantern glass
    l = { 0.64, 0.66, 0.73 }, -- lantern metal
}

-- The shopkeeper, 12x18: awake, then asleep (eyes shut)
local KEEPER = {
    "...kkkkkk...",
    "..khhhhhhk..",
    ".khhhhhhhhk.",
    ".khsssssshk.",
    ".ksesssessk.",
    ".kssssssssk.",
    ".ksmmmmmmsk.",
    "..kssssssk..",
    ".kckkaakkck.",
    "kcckaaaakcck",
    "kcckaaaakcck",
    "kskaaaaaAksk",
    ".kkaaaaaAkk.",
    "..kaaaaaAk..",
    "..kppppppk..",
    "..kppkkppk..",
    "..kbbk.kbbk.",
    "..kkkk.kkkk.",
}
local ASLEEP_EYES = ".ksSSssSSsk."

-- The counter, with a lantern at its right end, 22x11
local COUNTER = {
    "...................kk.",
    "..................klyk",
    "..................kyyk",
    "..................kyyk",
    "..................kllk",
    "kkkkkkkkkkkkkkkkkkkkkk",
    "kBBBBBBBBBBBBBBBBBBBBk",
    "kwwwwwwwwwwwwwwwwwwwwk",
    "kWwwWwwWwwWwwWwwWwwWwk",
    "kWwwWwwWwwWwwWwwWwwWwk",
    "kkkkkkkkkkkkkkkkkkkkkk",
}

local function makeImage(rows, palette)
    palette = palette or PALETTE
    local data = love.image.newImageData(#rows[1], #rows)
    for y = 1, #rows do
        assert(#rows[y] == #rows[1], "shop sprite rows differ in width")
        for x = 1, #rows[y] do
            local c = palette[rows[y]:sub(x, x)]
            if c then data:setPixel(x - 1, y - 1, c[1], c[2], c[3], 1) end
        end
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    return image
end

local counter, counterNormals, floor -- the house's

-- The room's floor, 64x64 drawn at twice that over the house's 128 px walls:
-- planks in rows of uneven lengths, the walls dark round the edge, and the
-- door's gap in the middle of the front (bottom) wall
local function newFloorImage()
    local n = 64
    local data = love.image.newImageData(n, n)
    local rng = love.math.newRandomGenerator(31)
    local woods = { PALETTE.w, PALETTE.B, { 0.62, 0.40, 0.21 } }
    for row = 0, n / 4 - 1 do
        local x, wood = 0, woods[rng:random(#woods)]
        local plankEnd = rng:random(10, 24)
        for px = 0, n - 1 do
            if px >= plankEnd then
                plankEnd, wood = px + rng:random(10, 24), woods[rng:random(#woods)]
            end
            for py = row * 4, row * 4 + 3 do
                local c = wood
                if py == row * 4 + 3 or px == plankEnd - 1 then
                    c = PALETTE.W -- seams
                end
                local grain = (rng:random() - 0.5) * 0.05
                data:setPixel(px, py, c[1] + grain, c[2] + grain, c[3] + grain, 1)
            end
        end
    end
    -- Walls, with the door's gap
    for i = 0, n - 1 do
        for t = 0, 2 do
            local door = i >= n / 2 - 8 and i < n / 2 + 8
            local wall = PALETTE.k
            data:setPixel(i, t, wall[1], wall[2], wall[3], 1)
            data:setPixel(t, i, wall[1], wall[2], wall[3], 1)
            data:setPixel(n - 1 - t, i, wall[1], wall[2], wall[3], 1)
            if not door then
                data:setPixel(i, n - 1 - t, wall[1], wall[2], wall[3], 1)
            end
        end
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    return image
end


-- The stall's counter, STALL_W wide: the house's, longer, its lantern at the right
local function stallCounterRows()
    local rows = {}
    for i = 1, 5 do rows[i] = string.rep(".", STALL_W - 4) .. COUNTER[i]:sub(-4) end
    for i = 6, #COUNTER do
        local row = COUNTER[i]
        rows[i] = row:sub(1, 1) .. string.rep(row:sub(2, 2), STALL_W - 2) .. row:sub(-1)
    end
    return rows
end

-- A stall's awning on its posts, 48x44 texels: stripes of its two colours,
-- scalloped along the bottom, shaded under the fold
local function newStallImage(colours)
    local w, h = 48, 44
    local data = love.image.newImageData(w, h)
    local k, W_, w_ = PALETTE.k, PALETTE.W, PALETTE.w
    local function set(x, y, c, shade)
        shade = shade or 1
        data:setPixel(x, y, c[1] * shade, c[2] * shade, c[3] * shade, 1)
    end
    -- posts, behind the awning
    for y = 12, h - 1 do
        for _, x in ipairs({ 3, 4, 43, 44 }) do set(x, y, (x == 3 or x == 43) and W_ or w_) end
        set(2, y, k)
        set(5, y, k)
        set(42, y, k)
        set(45, y, k)
    end
    -- the awning
    for x = 0, w - 1 do
        local c = colours[math.floor(x / 6) % 2 + 1]
        for y = 1, 11 do
            set(x, y, c, y >= 9 and 0.78 or (y <= 2 and 1.12 or 1))
        end
        set(x, 0, k)
        -- the scallops: each stripe's edge hangs in a curve
        local m = x % 6
        if m >= 1 and m <= 4 then set(x, 12, c, 0.7) else set(x, 12, k) end
        if m == 2 or m == 3 then set(x, 13, k) end
    end
    for y = 0, 12 do
        set(0, y, k)
        set(w - 1, y, k)
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    return image
end

-- The keeper's sprites, awake and asleep, in their own colours
local function keeperImages(colours)
    local palette = {}
    for key, c in pairs(PALETTE) do palette[key] = c end
    colours = colours or {}
    local function shaded(c, k) return { c[1] * k, c[2] * k, c[3] * k } end
    if colours.hair then palette.h, palette.m = colours.hair, shaded(colours.hair, 0.85) end
    if colours.shirt then palette.c = colours.shirt end
    if colours.apron then palette.a, palette.A = colours.apron, shaded(colours.apron, 0.75) end
    if colours.skin then palette.s, palette.S = colours.skin, shaded(colours.skin, 0.84) end
    local asleep = {}
    for i, row in ipairs(KEEPER) do asleep[i] = row end
    asleep[5] = ASLEEP_EYES
    return makeImage(KEEPER, palette), makeImage(asleep, palette)
end

--------------------------------------------------------------------------------
-- Reading shops.lua
--------------------------------------------------------------------------------

local REGIONS = { home = true, wasteland = true, castle = true, neon = true, sanctum = true }

local function check(ok, d, what)
    if not ok then
        error(("game/shops.lua: shop %q: %s"):format(tostring(d.id), what), 0)
    end
end

-- Every shop's entry, checked before anything's built from it
local function validate(list)
    local seen = {}
    for i, d in ipairs(list) do
        check(type(d.id) == "string" and d.id ~= "", d, "needs an id (entry " .. i .. ")")
        check(not seen[d.id], d, "has the same id as another")
        seen[d.id] = true
        check(type(d.name) == "string", d, "needs a name")
        check(REGIONS[d.region], d, "region must be home, wasteland, castle, neon or sanctum")
        if d.region == "home" then
            check(d.at == "house", d, "at must be \"house\" for a home shop")
        else
            check(d.at == "plaza" or d.at == "square", d, "at must be \"plaza\" or \"square\"")
        end
        check(d.offset == nil or (type(d.offset) == "table" and tonumber(d.offset[1]) and tonumber(d.offset[2])),
            d, "offset must be { x, y }")
        check(d.hours == "always" or (type(d.hours) == "table" and tonumber(d.hours[1]) and tonumber(d.hours[2])),
            d, "hours must be { open, close } or \"always\"")
        check(type(d.stock) == "table", d, "needs a stock list")
        for j, e in ipairs(d.stock) do
            local where = "stock entry " .. j
            check(tonumber(e.price) and e.price >= 0, d, where .. " needs a price")
            if e.item then
                check(inventory.ITEMS[e.item] and not inventory.ITEMS[e.item].trinket, d,
                    where .. ": no bag item " .. tostring(e.item))
            elseif e.trinket then
                check(trinkets.DEFS[e.trinket], d, where .. ": no trinket " .. tostring(e.trinket))
            else
                check(tonumber(e.fireballs), d, where .. " must be an item, a trinket or fireballs")
            end
        end
        check(#d.stock + (d.shelf or 0) <= 9, d, "sells more than nine things (stock and shelf)")
    end
end

--- Check shops.lua's entries (shop.load does): an error naming the shop
--- and what's wrong with it.
shop.validate = validate

-- Whether `s` is open at `hour` (now, unless given)
local function openAt(s, hour)
    local hours = s.def.hours
    if hours == "always" then return true end
    hour = hour or daynight.hour
    local o, c = hours[1], hours[2]
    if o <= c then return hour >= o and hour < c end
    return hour >= o or hour < c -- (open past midnight)
end

--- Whether shop `s` is open now.
shop.isOpenNow = openAt

local function opensAt(s)
    return type(s.def.hours) == "table" and s.def.hours[1] or 0
end

-- Somewhere clear for a stall at (x, y) or near it: nothing of the region's
-- (its sprites, drawn or flat, or anything static) over the stall's picture
-- or the ground in front where you stand, and clear of the portal
local function clearSpot(r, x, y)
    local portalX, portalY = r.portal.x + 17, r.portal.y + 60
    local function clear(cx, cy)
        if (cx - portalX) ^ 2 + (cy - portalY) ^ 2 < 140 * 140 then return false end
        local x0, y0, x1, y1 = cx - 56, cy - 72, cx + 56, cy + 70
        for _, item in ipairs(r.items) do
            if item.x < x1 and item.x1 > x0 and item.y < y1 and item.y1 > y0 then return false end
        end
        local blocked = false
        world:queryBoundingBox(x0, y0, x1, y1, function(f)
            if not f:isSensor() and f:getBody():getType() == "static" then
                blocked = true
                return false
            end
            return true
        end)
        return not blocked
    end
    for ring = 0, 14 do
        local n = ring == 0 and 1 or 12
        for k = 0, n - 1 do
            local a = k / n * math.pi * 2
            local cx, cy = x + math.cos(a) * ring * 32, y + math.sin(a) * ring * 32
            if clear(cx, cy) then return cx, cy end
        end
    end
    return x, y
end

-- A shop from its entry: where it stands, its keeper, and a stall to stand at
local function build(d)
    local s = { def = d, id = d.id, name = d.name, shelf = {} }
    s.awake, s.asleep = keeperImages(d.keeper)
    if d.at == "house" then
        s.house = true
        return s
    end
    local r
    for _, region in ipairs(regions.list) do
        if region.id == d.region then r = region end
    end
    local area = (d.at == "square" and r.square) or r.plaza
    local ox, oy = d.offset and d.offset[1] or 0, d.offset and d.offset[2] or 0
    s.x, s.y = clearSpot(r, area.x + area.w / 2 + ox, area.y + area.h / 2 + oy)
    s.x, s.y = math.floor(s.x + 0.5), math.floor(s.y + 0.5)
    s.stall = newStallImage(d.stall or { { 0.78, 0.16, 0.12 }, { 0.95, 0.90, 0.78 } })
    s.stallNormals = normalmap.of(s.stall)
    s.counter = makeImage(stallCounterRows())
    s.counterNormals = normalmap.of(s.counter)
    -- the counter stops you (and enemies, and shots); you trade across it
    s.body = love.physics.newBody(world, s.x, s.y + 16, "static")
    s.fixture = love.physics.newFixture(s.body, love.physics.newRectangleShape(STALL_W * 2 - 4, 14))
    s.fixture:setGroupIndex(collision.groups.map)
    return s
end

--------------------------------------------------------------------------------
-- Stock and shelves
--------------------------------------------------------------------------------

-- One of the bag's items (inventory.ITEMS[id]) for `price` XP
local function bagged(id, price)
    local item = inventory.ITEMS[id]
    return { name = item.name, desc = item.desc, price = price,
        can = function() return inventory.room(id) > 0, "Bag is full" end,
        buy = function() inventory.add(id, 1) end }
end

local function fireballs(n, price)
    return { name = "Fireballs", desc = "+" .. n .. " fireballs", price = price,
        can = function() return fire.getAvailableCount() < fire.max_fireballs, "Fireballs are full" end,
        buy = function()
            for _ = 1, n do
                if fire.getAvailableCount() < fire.max_fireballs then fire.addFireball() end
            end
        end }
end

--- What shop `s` has for sale: its stock in order, then its shelf.
function shop.rows(s)
    local rows = {}
    for _, e in ipairs(s.def.stock) do
        if e.item then
            rows[#rows + 1] = bagged(e.item, e.price)
        elseif e.trinket then
            rows[#rows + 1] = trinkets.offer(e.trinket, e.price)
        else
            rows[#rows + 1] = fireballs(e.fireballs, e.price)
        end
    end
    for _, id in ipairs(s.shelf) do
        local price = math.floor(trinkets.DEFS[id].price * (s.def.shelfPrice or 1) + 0.5)
        if not trinkets.owns(id) then -- (found one since the morning)
            rows[#rows + 1] = trinkets.offer(id, price, function()
                for i, other in ipairs(s.shelf) do
                    if other == id then table.remove(s.shelf, i) break end
                end
            end)
        end
    end
    return rows
end

--- Fill every shop's shelf again (each morning) with trinkets you haven't
--- got, different ones from shop to shop while there are enough.
function shop.restock()
    local taken = {}
    for _, s in ipairs(shop.list) do
        s.shelf = {}
        for _ = 1, s.def.shelf or 0 do
            local id = trinkets.unowned(rng, taken) or trinkets.unowned(rng)
            if not id then break end
            local again = false
            for _, other in ipairs(s.shelf) do again = again or other == id end
            if not again then
                taken[id] = true
                s.shelf[#s.shelf + 1] = id
            end
        end
    end
end

function shop.load()
    counter = makeImage(COUNTER)
    counterNormals = normalmap.of(counter) -- it stands up (lib/graphics/normalmap.lua)
    floor = newFloorImage()
    font = love.graphics.newFont("gfx/menu/Px437_IBM_VGA_8x16.ttf", 16)
    font:setFilter("nearest", "nearest")
    rng = love.math.newRandomGenerator(love.math.random(0, 2 ^ 31 - 1))
    validate(SHOPS)
    shop.list, shop.byId = {}, {}
    for _, d in ipairs(SHOPS) do
        local s = build(d)
        shop.list[#shop.list + 1] = s
        shop.byId[s.id] = s
    end
    shop.restock()
    shop.current = shop.byId.home or shop.list[1]
    shop.ITEMS = shop.current and shop.rows(shop.current) or {}
    shop.open, selected, message = false, 1, nil
    lastHour = nil
end

-- The house the home shop is in
local function house()
    return map.houseInstances and map.houseInstances[1]
end

-- Whether shop s is there: the house's always, a stall once its region's
-- boss is beaten
local function standing(s)
    return s.house or bosses.cleared(s.def.region)
end

-- Where shop s's keeper stands (the back of the house's room, or behind
-- the stall's counter); nil while it isn't there
local function keeperPosition(s)
    if s.house then
        local h = house()
        if not h then return nil end
        return h.x, h.y - 34
    end
    if not standing(s) then return nil end
    return s.x, s.y
end

--- Inside the house, where nothing can hurt you.
function shop.isSafe()
    return var.indoors == true
end

-- The shop you're at the counter of, if any
local function nearest()
    if not player.body then return nil end
    local px, py = player.body:getPosition()
    local best, bestD = nil, REACH * REACH
    for _, s in ipairs(shop.list) do
        local kx, ky = keeperPosition(s)
        if kx and (not s.house or var.indoors) then
            local d = (px - kx) ^ 2 + (py - ky) ^ 2
            if d < bestD then best, bestD = s, d end
        end
    end
    return best
end

local function say(text)
    message, messageAt = text, love.timer.getTime()
end

local function close()
    shop.open = false
end

local function buy(i)
    local item = shop.ITEMS[i]
    if not item then return end
    local ok, why = item.can()
    if var.player_score < item.price then
        say("Not enough XP")
    elseif not ok then
        say(why)
    else
        var.player_score = var.player_score - item.price
        item.buy()
        say("Bought " .. item.name)
        if item.trinket then
            shop.ITEMS = shop.rows(shop.current) -- (off the shelf)
            selected = math.max(1, math.min(selected, #shop.ITEMS))
        end
        local px, py = player.body:getPosition()
        audio.playSoundAt("coin", px, py, 0.4)
    end
end

function shop.update(dt)
    -- a new morning: new trinkets on the shelves
    local hour = daynight.hour
    if lastHour and lastHour < DAWN and hour >= DAWN then shop.restock() end
    lastHour = hour

    -- a stall's counter only stops you once the stall's there
    for _, s in ipairs(shop.list) do
        if s.body and s.body:isActive() ~= standing(s) then
            s.body:setActive(standing(s))
            nav.forget(s.x - STALL_W, s.y, s.x + STALL_W, s.y + 32)
        end
    end

    if shop.open then
        local s = shop.current
        if nearest() ~= s or not openAt(s) then
            if not openAt(s) then say("Closing time. Come back at " .. string.format("%02d:00", opensAt(s))) end
            close()
        end
    end
end

--- The room's floor while you're in it (from outside the house covers it).
--- In the ground pass, under the camera transform with the map's shader;
--- at the ground's alpha, so GI doesn't take it for a wall.
function shop.drawFloor()
    local h = house()
    if not (h and var.indoors) then return end
    love.graphics.setColor(1, 1, 1, 0.4)
    love.graphics.draw(floor, h.x - 64, h.y - 64, 0, 2, 2)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Whether world (x, y) is in view, give or take `pad`
local function inView(x, y, pad)
    local x0, y0, x1, y1 = regions.view(pad)
    return x > x0 and x < x1 and y > y0 and y < y1
end

--- Each shop's lantern, lighting it. Before the lighting upload.
function shop.addLights()
    for _, s in ipairs(shop.list) do
        local kx, ky = keeperPosition(s)
        if kx and inView(kx, ky, 200) then
            if s.house then
                shadow.addTransientLight(kx + 20, ky + 14, 0.6, 110)
            else
                shadow.addTransientLight(kx + STALL_W - 4, ky + 6, 0.7, 130)
            end
        end
    end
end

--- Each shop's keeper and counter (the house's under the house: hidden by
--- it from outside, it turns see-through while you're in), and a stall's
--- awning behind them.
function shop.populate()
    local t = love.timer.getTime()
    for i, s in ipairs(shop.list) do
        local kx, ky = keeperPosition(s)
        if kx and inView(kx, ky, 120) then
            local open = openAt(s)
            -- awake while it's open, with a blink now and then; asleep when it's shut
            local image = (not open or (t + i * 0.7) % 4.3 < 0.15) and s.asleep or s.awake
            local bob = open and math.floor(math.sin(t * 2 + i) * 0.6 + 0.5) or 0
            if s.stall then
                dynamic_draw_list[#dynamic_draw_list + 1] = {
                    sort_y = ky + 90,
                    image_or_particles = s.stall,
                    x = kx, y = ky + 22,
                    rotation = 0, scale_x = 2, scale_y = 2,
                    offset_x = 24, offset_y = 44,
                    color = { 1, 1, 1, 1 },
                    blend_mode = { "alpha" },
                    normal_map = s.stallNormals,
                    source_object_type = "shop_stall"
                }
            end
            dynamic_draw_list[#dynamic_draw_list + 1] = {
                sort_y = ky + 100,
                image_or_particles = image,
                x = kx, y = ky + bob,
                rotation = 0, scale_x = 2, scale_y = 2,
                offset_x = 6, offset_y = 17,
                color = { 1, 1, 1, 1 },
                blend_mode = { "alpha" },
                source_object_type = "shopkeeper"
            }
            local c = s.counter or counter
            dynamic_draw_list[#dynamic_draw_list + 1] = {
                sort_y = ky + 120,
                image_or_particles = c,
                x = kx, y = ky + 14,
                rotation = 0, scale_x = 2, scale_y = 2,
                offset_x = s.stall and STALL_W / 2 or 9, offset_y = 7,
                color = { 1, 1, 1, 1 },
                blend_mode = { "alpha" },
                normal_map = s.counterNormals or counterNormals,
                source_object_type = "shop_counter"
            }
        end
    end
end

-- The panel's layout in GUI units
local ROW = 18 -- GUI units a row takes (enough of them fit the screen)

local function layout(sw, sh)
    local w = 220
    local h = 34 + #shop.ITEMS * ROW + 22
    local x = math.floor((sw - w) / 2)
    local y = math.max(4, math.floor((sh - h) / 2 - 10))
    local rows = {}
    for i, item in ipairs(shop.ITEMS) do
        rows[i] = { x = x + 8, y = y + 34 + (i - 1) * ROW, w = w - 16, h = ROW - 2, index = i, item = item }
    end
    return { x = x, y = y, w = w, h = h }, rows
end

--- Open shop `s`'s panel (E at its counter). False, and why not, when it's shut.
function shop.openAt(s)
    if not openAt(s) then
        return false, "Zzz... Open at " .. string.format("%02d:00", opensAt(s))
    end
    shop.current = s
    shop.ITEMS = shop.rows(s)
    shop.open, selected = true, 1
    return true
end

--- Returns true when the shop took the key: E at a counter, and every key
--- the open panel uses.
function shop.keypressed(key)
    if var.State == "menu" then return false end
    if shop.open then
        if key == "escape" or key == "e" then
            close()
        elseif key == "up" then
            selected = (selected - 2) % #shop.ITEMS + 1
        elseif key == "down" then
            selected = selected % #shop.ITEMS + 1
        elseif key == "return" or key == "kpenter" then
            buy(selected)
        elseif tonumber(key) and shop.ITEMS[tonumber(key)] then
            selected = tonumber(key)
            buy(selected)
        else
            return false
        end
        return true
    end
    local s = key == "e" and nearest()
    if s then
        local ok, why = shop.openAt(s)
        if not ok then say(why) end
        return true
    end
    return false
end

--- A click (image coordinates): buys the row under it. True when taken.
function shop.mousepressed(x, y, button)
    if not shop.open then return false end
    local u = skin.guiScale()
    local sw, sh = love.graphics.getDimensions()
    local panel, rows = layout(sw / u, sh / u)
    for _, row in ipairs(rows) do
        if skin.contains(row, x / u, y / u) then
            selected = row.index
            buy(row.index)
            return true
        end
    end
    return skin.contains(panel, x / u, y / u) -- clicks on the panel don't shoot
end

--- The stalls' names as you come near, the prompt over the counter you're
--- at, the trade panel, and what just happened. Screen space, under the CRT
--- with the rest of the UI.
function shop.drawUI()
    if var.State == "menu" then return end
    local u = skin.guiScale()
    local ts = skin.textScale(u)
    local sw, sh = love.graphics.getDimensions()
    local prevFont = love.graphics.getFont()
    love.graphics.push()
    love.graphics.origin()
    love.graphics.setShader()
    love.graphics.setFont(font)
    love.graphics.scale(u)

    if var.indoors then
        skin.printCentered("Safe inside", sw / u / 2, 6, ts, { 0.55, 1.00, 0.55 })
    end

    local here = nearest()
    local px, py = player.body:getPosition()
    for _, s in ipairs(shop.list) do
        local kx, ky = keeperPosition(s)
        if kx then
            local sx = (camera.pos.x + kx * camera.zoom) / u
            if s == here and not shop.open then
                -- The prompt, over the keeper's head
                local open = openAt(s)
                local text = open and ("[E] " .. (s.house and "Trade" or s.name))
                    or ("Zzz... closed until " .. string.format("%02d:00", opensAt(s)))
                local sy = (camera.pos.y + (ky - (s.stall and 104 or 52)) * camera.zoom) / u
                skin.printCentered(text, sx, sy, ts, open and skin.YELLOW or skin.GRAY)
            elseif s.stall and s ~= here and (px - kx) ^ 2 + (py - ky) ^ 2 < SIGN_RANGE * SIGN_RANGE then
                -- a stall's name over its awning as you come near
                local sy = (camera.pos.y + (ky - 104) * camera.zoom) / u
                skin.printCentered(s.name, sx, sy, ts, openAt(s) and skin.WHITE or skin.GRAY, 0.8)
            end
        end
    end

    if shop.open then
        local panel, rows = layout(sw / u, sh / u)
        love.graphics.setColor(0.08, 0.08, 0.10, 0.92)
        love.graphics.rectangle("fill", panel.x, panel.y, panel.w, panel.h)
        love.graphics.setColor(0.64, 0.66, 0.73, 1)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", panel.x + 0.5, panel.y + 0.5, panel.w - 1, panel.h - 1)
        skin.printCentered(shop.current.name, panel.x + panel.w / 2, panel.y + 6, ts, skin.WHITE)
        skin.printCentered(var.player_score .. " XP", panel.x + panel.w / 2, panel.y + 18, ts, { 0.50, 1.00, 0.13 })

        local mx, my = crt.mouse()
        for i, row in ipairs(rows) do
            local item = row.item
            local ok = item.can()
            row.enabled = ok and var.player_score >= item.price
            row.label = string.format("%d  %s (%s) - %d XP", i, item.name, item.desc, item.price)
            skin.button(row, ts, i == selected or skin.contains(row, mx / u, my / u))
        end
        skin.printCentered("Enter buy   Esc close", panel.x + panel.w / 2, panel.y + panel.h - 13, ts, skin.GRAY)
    end

    local age = love.timer.getTime() - messageAt
    if message and age < 2 then
        skin.printCentered(message, sw / u / 2, sh / u / 2 + 70, ts, skin.WHITE, math.min(1, (2 - age) * 2))
    end

    love.graphics.pop()
    love.graphics.setFont(prevFont)
    love.graphics.setColor(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- Saves
--------------------------------------------------------------------------------

--- Every shop's shelf, for a save.
function shop.getSaveData()
    local shelves = {}
    for _, s in ipairs(shop.list) do shelves[s.id] = s.shelf end
    return { shelves = shelves }
end

--- Put back what getSaveData gave (after the bag, so nothing you have is
--- offered). A shop the save doesn't know (new in shops.lua, or a save from
--- before them) is stocked afresh.
function shop.restore(data)
    local shelves = type(data) == "table" and data.shelves or nil
    if not shelves then
        shop.restock()
        return
    end
    for _, s in ipairs(shop.list) do
        local saved = shelves[s.id]
        if type(saved) == "table" then
            s.shelf = {}
            for _, id in ipairs(saved) do
                if trinkets.DEFS[id] and not trinkets.owns(id) and #s.shelf < (s.def.shelf or 0) then
                    s.shelf[#s.shelf + 1] = id
                end
            end
        end
    end
end

return shop
