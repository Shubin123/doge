--[[
  The shop: the house on the home map. Inside it you're safe (player.isSafe:
  nothing hurts you there, and its door is too narrow for enemies), and
  a shopkeeper behind a counter sells for XP, by day only.

    * By day (daynight.isOpen, 07:00-19:00) walk up to the counter and press
      E: a panel lists what's for sale. Up/Down pick, Enter buy (or 1-4 to
      buy at once, or click one), Esc or E closes. It closes on its own if you walk off or the
      shop shuts.
    * At night the shopkeeper sleeps behind the counter and won't sell, but
      the house is still a safe place to wait for morning.

  What's sold costs XP (var.player_score, the globs you've picked up) and
  goes in your bag (game/inventory.lua) to use when you need it, but for
  fireballs, which go straight onto the hotbar. Two trinkets you haven't
  got are on the shelf after them (game/trinkets.lua), worn as you buy one,
  restocked each morning.
]]
local skin = require("ui.skin")
local normalmap = require("lib.graphics.normalmap")
local inventory = require("game.inventory")

local shop = {}

local REACH = 70 -- px from the shopkeeper you can trade at

-- One of the bag's items (inventory.ITEMS[id]) for `price` XP
local function bagged(id, price)
    local item = inventory.ITEMS[id]
    return { name = item.name, desc = item.desc, price = price,
        can = function() return inventory.room(id) > 0, "Bag is full" end,
        buy = function() inventory.add(id, 1) end }
end

local STOCK = {
    bagged("bandage", 40),
    bagged("medkit", 120),
    bagged("light_cell", 50),
    { name = "Fireballs", desc = "+3 fireballs", price = 45,
        can = function() return fire.getAvailableCount() < fire.max_fireballs, "Fireballs are full" end,
        buy = function()
            for _ = 1, 3 do
                if fire.getAvailableCount() < fire.max_fireballs then fire.addFireball() end
            end
        end },
}
shop.ITEMS = STOCK

-- What's for sale now: the stock, then the trinkets on the shelf
local function restock()
    shop.ITEMS = {}
    for _, item in ipairs(STOCK) do shop.ITEMS[#shop.ITEMS + 1] = item end
    for _, item in ipairs(trinkets.shopItems()) do shop.ITEMS[#shop.ITEMS + 1] = item end
end

shop.open = false
local selected = 1
local message, messageAt = nil, -math.huge
local font

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

local function makeImage(rows)
    local data = love.image.newImageData(#rows[1], #rows)
    for y = 1, #rows do
        assert(#rows[y] == #rows[1], "shop sprite rows differ in width")
        for x = 1, #rows[y] do
            local c = PALETTE[rows[y]:sub(x, x)]
            if c then data:setPixel(x - 1, y - 1, c[1], c[2], c[3], 1) end
        end
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    return image
end

local keeperAwake, keeperAsleep, counter, counterNormals, floor

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

function shop.load()
    keeperAwake = makeImage(KEEPER)
    local asleep = {}
    for i, row in ipairs(KEEPER) do asleep[i] = row end
    asleep[5] = ASLEEP_EYES
    keeperAsleep = makeImage(asleep)
    counter = makeImage(COUNTER)
    counterNormals = normalmap.of(counter) -- it stands up (lib/graphics/normalmap.lua)
    floor = newFloorImage()
    font = love.graphics.newFont("gfx/menu/Px437_IBM_VGA_8x16.ttf", 16)
    font:setFilter("nearest", "nearest")
    shop.open, selected, message = false, 1, nil
end

-- The house the shop is in, and where its keeper stands (the back of the room)
local function house()
    return map.houseInstances and map.houseInstances[1]
end

local function keeperPosition()
    local h = house()
    if not h then return nil end
    return h.x, h.y - 34
end

--- Inside the shop, where nothing can hurt you.
function shop.isSafe()
    return var.indoors == true
end

local function inReach()
    local kx, ky = keeperPosition()
    if not (kx and var.indoors and player.body) then return false end
    local px, py = player.body:getPosition()
    return (px - kx) ^ 2 + (py - ky) ^ 2 < REACH * REACH
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
            restock() -- (off the shelf)
            selected = math.min(selected, #shop.ITEMS)
        end
        local px, py = player.body:getPosition()
        audio.playSoundAt("coin", px, py, 0.4)
    end
end

function shop.update(dt)
    if shop.open and (not inReach() or not daynight.isOpen()) then
        if not daynight.isOpen() then say("Closing time. Come back in the morning") end
        close()
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

--- The shopkeeper's lantern, lighting the room. Before the lighting upload.
function shop.addLights()
    local kx, ky = keeperPosition()
    if kx then
        shadow.addTransientLight(kx + 20, ky + 14, 0.6, 110)
    end
end

--- The shopkeeper and the counter, under the house (hidden by it from
--- outside; it turns see-through while you're in)
function shop.populate()
    local kx, ky = keeperPosition()
    if not kx then return end
    local open = daynight.isOpen()
    -- Awake by day, with a blink now and then; asleep at night
    local t = love.timer.getTime()
    local image = (not open or t % 4.3 < 0.15) and keeperAsleep or keeperAwake
    local bob = open and math.floor(math.sin(t * 2) * 0.6 + 0.5) or 0
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
    dynamic_draw_list[#dynamic_draw_list + 1] = {
        sort_y = ky + 120,
        image_or_particles = counter,
        x = kx, y = ky + 14,
        rotation = 0, scale_x = 2, scale_y = 2,
        offset_x = 9, offset_y = 7,
        color = { 1, 1, 1, 1 },
        blend_mode = { "alpha" },
        normal_map = counterNormals,
        source_object_type = "shop_counter"
    }
end

-- The panel's layout in GUI units
local function layout(sw, sh)
    local w = 200
    local x = math.floor((sw - w) / 2)
    local y = math.floor(sh / 2 - 80)
    local rows = {}
    for i, item in ipairs(shop.ITEMS) do
        rows[i] = { x = x + 8, y = y + 34 + (i - 1) * 24, w = w - 16, h = 20, index = i, item = item }
    end
    return { x = x, y = y, w = w, h = 34 + #shop.ITEMS * 24 + 26 }, rows
end

--- Returns true when the shop took the key: E at the counter, and every
--- key the open panel uses.
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
    if key == "e" and inReach() then
        if daynight.isOpen() then
            restock()
            shop.open, selected = true, 1
        else
            say("Zzz... Open at " .. string.format("%02d:00", daynight.opensAt()))
        end
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

--- The prompt over the counter, the trade panel, and what just happened.
--- Screen space, under the CRT with the rest of the UI.
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

    -- The prompt, over the shopkeeper's head
    local kx, ky = keeperPosition()
    if kx and inReach() and not shop.open then
        local text = daynight.isOpen() and "[E] Trade" or "Zzz... closed until "
            .. string.format("%02d:00", daynight.opensAt())
        local sx = (camera.pos.x + kx * camera.zoom) / u
        local sy = (camera.pos.y + (ky - 52) * camera.zoom) / u
        skin.printCentered(text, sx, sy, ts, daynight.isOpen() and skin.YELLOW or skin.GRAY)
    end

    if shop.open then
        local panel, rows = layout(sw / u, sh / u)
        love.graphics.setColor(0.08, 0.08, 0.10, 0.92)
        love.graphics.rectangle("fill", panel.x, panel.y, panel.w, panel.h)
        love.graphics.setColor(0.64, 0.66, 0.73, 1)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", panel.x + 0.5, panel.y + 0.5, panel.w - 1, panel.h - 1)
        skin.printCentered("Shop", panel.x + panel.w / 2, panel.y + 6, ts, skin.WHITE)
        skin.printCentered(var.player_score .. " XP", panel.x + panel.w / 2, panel.y + 18, ts, { 0.50, 1.00, 0.13 })

        local mx, my = crt.mouse()
        for i, row in ipairs(rows) do
            local item = row.item
            local ok = item.can()
            row.enabled = ok and var.player_score >= item.price
            row.label = string.format("%d  %s (%s) - %d XP", i, item.name, item.desc, item.price)
            skin.button(row, ts, i == selected or skin.contains(row, mx / u, my / u))
        end
        skin.printCentered("Enter buy   Esc close", panel.x + panel.w / 2, panel.y + panel.h - 14, ts, skin.GRAY)
    end

    local age = love.timer.getTime() - messageAt
    if message and age < 2 then
        skin.printCentered(message, sw / u / 2, sh / u / 2 + 70, ts, skin.WHITE, math.min(1, (2 - age) * 2))
    end

    love.graphics.pop()
    love.graphics.setFont(prevFont)
    love.graphics.setColor(1, 1, 1, 1)
end

return shop
