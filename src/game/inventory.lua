--[[
  The bag: what you carry besides your weapons. Two rows of nine slots, each
  a stack of one kind of item (up to that item's `stack`).

    * I or Tab opens it. Arrows (or the mouse) pick a slot; Enter or a click
      uses what's in it, Q or a right click drops one at your feet; Esc, I or
      Tab closes it. The game goes on while it's open.
    * H uses a Bandage, or a Medkit without one, when your hearts aren't full.
    * K uses the car key: the car drives itself to you (car.summon). Nobody
      has it at first: it lies on the ground in front of the car.
    * Items lie about the world too (inventory.ground): dropped ones, and
      what enemies leave behind now and then. Walk near one and it slides
      into the bag, if there's room.
    * The shop (game/shop.lua) sells into the bag.
    * Trinkets (game/trinkets.lua) are worn in the panel's Worn row: one
      picked up is worn if there's a free slot; using one in the bag puts it
      on, using a worn one takes it off (Q drops it). Now and then an enemy
      leaves one you haven't got.

  Saves keep the bag and what's on the ground (serial.lua). In multiplayer
  only the host (and single player) has items on the ground; everyone has
  their own bag.
]]
local skin = require("ui.skin")

local inventory = {}

inventory.COLS, inventory.ROWS = 9, 2
inventory.SIZE = inventory.COLS * inventory.ROWS

local PICKUP_RANGE = 22  -- px: this close, an item's in the bag
local MAGNET_RANGE = 64  -- px: this close, it slides toward you
local MAGNET_SPEED = 220 -- px/s
local DROP_AHEAD = 30    -- px in front of you a dropped item lands
local DROP_LOCKOUT = 1.2 -- s a dropped item won't come straight back
local MESSAGE_TIME = 2   -- s a message shows
-- What a dead enemy leaves behind: the chance of each, rolled in order, one at most
local ENEMY_DROPS = { { "bandage", 0.05 }, { "light_cell", 0.04 }, { "medkit", 0.01 } }
local TRINKET_DROP = 0.006 -- and else, the chance of a trinket you haven't got

local PALETTE = {
    k = { 0.08, 0.08, 0.10 }, -- outline
    W = { 1.00, 1.00, 1.00 }, -- white
    s = { 0.96, 0.95, 0.90 }, -- gauze
    w = { 0.72, 0.72, 0.70 }, -- gauze shadow
    t = { 0.93, 0.78, 0.60 }, -- plaster
    T = { 0.76, 0.58, 0.42 }, -- plaster shadow
    r = { 0.86, 0.14, 0.10 }, -- red
    R = { 0.52, 0.06, 0.05 }, -- dark red
    y = { 1.00, 0.84, 0.20 }, -- yellow
    Y = { 0.70, 0.50, 0.10 }, -- dark yellow
    m = { 0.42, 0.44, 0.50 }, -- metal
    l = { 0.64, 0.66, 0.73 }, -- light metal
    c = { 0.35, 0.85, 1.00 }, -- cyan
    C = { 0.10, 0.45, 0.70 }, -- dark cyan
    o = { 1.00, 0.50, 0.10 }, -- orange
    p = { 0.62, 0.48, 0.92 }, -- violet
    P = { 0.36, 0.24, 0.62 }, -- dark violet
}

-- What there is to carry. use() does what it does and returns true, or
-- false and why not (the item's kept); keep: using it doesn't use it up.
inventory.ITEMS = {
    bandage = {
        name = "Bandage", desc = "+2 hearts", stack = 16,
        use = function()
            if player.health >= player.maxHealth then return false, "Hearts are full" end
            player.health = math.min(player.maxHealth, player.health + player.maxHealth / 5)
            return true
        end,
        icon = {
            "................",
            "................",
            "................",
            "................",
            "..kkkkkkkkkkkk..",
            ".ktttkssssktttk.",
            "ktTtTksswskTtTtk",
            "kttttksssskttttk",
            "ktTtTkswsskTtTtk",
            ".ktttkssssktttk.",
            "..kkkkkkkkkkkk..",
            "................",
            "................",
            "................",
            "................",
            "................",
        },
    },
    medkit = {
        name = "Medkit", desc = "Full hearts", stack = 8,
        use = function()
            if player.health >= player.maxHealth then return false, "Hearts are full" end
            player.health = player.maxHealth
            return true
        end,
        icon = {
            "................",
            "................",
            ".....kkkkkk.....",
            ".....k....k.....",
            "..kkkkkkkkkkkk..",
            "..krrrrrrrrrrk..",
            "..krrrrWWrrrrk..",
            "..krrrrWWrrrrk..",
            "..krrWWWWWWrrk..",
            "..krrWWWWWWrrk..",
            "..krrrrWWrrrrk..",
            "..krrrrWWrrrrk..",
            "..kRRRRRRRRRRk..",
            "..kkkkkkkkkkkk..",
            "................",
            "................",
        },
    },
    car_key = {
        name = "Car key", desc = "Calls the car to you", stack = 1, keep = true,
        use = function() return car.summon() end,
        icon = {
            "................",
            "................",
            "................",
            "..kkkk..........",
            ".kyyyyk.........",
            "kyykkyyk........",
            "kyk..kykkkkkkkk.",
            "kyk..kyyyyyyyyyk",
            "kyykkyykkkYkkYkk",
            ".kyyyyk..kYk.kYk",
            "..kkkk...kkk.kkk",
            "................",
            "................",
            "................",
            "................",
            "................",
        },
    },
    light_cell = {
        name = "Light cell", desc = "Fills the light bar", stack = 16,
        use = function()
            if gun.ammo >= gun.maxAmmo then return false, "Light is full" end
            gun.ammo = gun.maxAmmo
            return true
        end,
        icon = {
            "................",
            "......kkkk......",
            "......kllk......",
            "....kkkkkkkk....",
            "....klmmmmmk....",
            "....kyyyyyyk....",
            "....kyyyWyyk....",
            "....kyyWWyyk....",
            "....kyWWWWyk....",
            "....kyyWWyyk....",
            "....kyyWyyyk....",
            "....kyyyyyyk....",
            "....kYYYYYYk....",
            "....kmmmmmmk....",
            "....kkkkkkkk....",
            "................",
        },
    },
}

inventory.slots = {}  -- [1..SIZE]: { id =, count = } or nil
inventory.ground = {} -- lying about: { id =, count =, x =, y =, lockout = }
inventory.open = false
local selected = 1
local message, messageAt = nil, -math.huge
local icons = {} -- built the first time each is shown
local font
local drops -- what enemies leave rolls on its own, so it doesn't shift anything else's random numbers

local function makeImage(rows)
    local data = love.image.newImageData(#rows[1], #rows)
    for y = 1, #rows do
        assert(#rows[y] == #rows[1], "inventory icon rows differ in width")
        for x = 1, #rows[y] do
            local c = PALETTE[rows[y]:sub(x, x)]
            if c then data:setPixel(x - 1, y - 1, c[1], c[2], c[3], 1) end
        end
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    return image
end

local function icon(id)
    icons[id] = icons[id] or makeImage(inventory.ITEMS[id].icon)
    return icons[id]
end
inventory.icon = icon -- (the HUD shows the worn trinkets')

local function hosting()
    return not var.multiplayer or var.multiplayer == 1
end

local function say(text)
    message, messageAt = text, love.timer.getTime()
end

--- Show a line of text over the hotbar for a moment (what just happened).
inventory.notify = say

-- The car key lies in front of the car while nobody has it (a new game, or
-- a save from before it)
local function placeKey()
    if inventory.count("car_key") > 0 then return end
    for _, g in ipairs(inventory.ground) do
        if g.id == "car_key" then return end
    end
    local x, y = car.keySpot()
    if x then inventory.place("car_key", 1, x, y) end
end

--- An empty bag and nothing on the ground (a new game, or a save from
--- before there was a bag).
function inventory.reset()
    inventory.slots, inventory.ground = {}, {}
    inventory.open, selected = false, 1
end

function inventory.load()
    drops = love.math.newRandomGenerator(love.math.random(0, 2 ^ 31 - 1))
    font = love.graphics.newFont("gfx/menu/Px437_IBM_VGA_8x16.ttf", 16)
    font:setFilter("nearest", "nearest")
    message = nil
    inventory.reset()
    placeKey()
end

--- How many of item `id` are in the bag.
function inventory.count(id)
    local n = 0
    for i = 1, inventory.SIZE do
        local s = inventory.slots[i]
        if s and s.id == id then n = n + s.count end
    end
    return n
end

--- How many more of item `id` fit in the bag.
function inventory.room(id)
    local stack, n = inventory.ITEMS[id].stack, 0
    for i = 1, inventory.SIZE do
        local s = inventory.slots[i]
        if not s then
            n = n + stack
        elseif s.id == id then
            n = n + stack - s.count
        end
    end
    return n
end

--- Put up to `count` (1) of item `id` in the bag: onto its stacks first,
--- then into empty slots. Returns how many went in.
function inventory.add(id, count)
    count = count or 1
    local stack, added = inventory.ITEMS[id].stack, 0
    for pass = 1, 2 do
        for i = 1, inventory.SIZE do
            if added >= count then return added end
            local s = inventory.slots[i]
            if pass == 1 and s and s.id == id and s.count < stack then
                local n = math.min(stack - s.count, count - added)
                s.count, added = s.count + n, added + n
            elseif pass == 2 and not s then
                local n = math.min(stack, count - added)
                inventory.slots[i], added = { id = id, count = n }, added + n
            end
        end
    end
    return added
end

--- Take up to `count` (1) of item `id` out of the bag, from its last stacks
--- first. Returns how many came out.
function inventory.remove(id, count)
    count = count or 1
    local removed = 0
    for i = inventory.SIZE, 1, -1 do
        local s = inventory.slots[i]
        if removed >= count then break end
        if s and s.id == id then
            local n = math.min(s.count, count - removed)
            s.count, removed = s.count - n, removed + n
            if s.count == 0 then inventory.slots[i] = nil end
        end
    end
    return removed
end

--- Use what's in slot i (past the bag's: take off that worn trinket). True
--- if it did something.
function inventory.use(i)
    if i > inventory.SIZE then return trinkets.unwear(i - inventory.SIZE) end
    local s = inventory.slots[i]
    if not s then return false end
    local item = inventory.ITEMS[s.id]
    local ok, why = item.use()
    if not ok then
        say(why or ("Can't use the " .. item.name))
        return false
    end
    if why then say(why) end -- what it's doing
    if not item.keep then
        s.count = s.count - 1
        if s.count == 0 then inventory.slots[i] = nil end
    end
    if player.body then
        audio.playSoundAt("coin", player.body:getX(), player.body:getY(), 0.3)
    end
    return true
end

--- Use the first of these items in the bag that will (in order). True if one did.
function inventory.useFirst(ids)
    local why
    for _, id in ipairs(ids) do
        for i = 1, inventory.SIZE do
            local s = inventory.slots[i]
            if s and s.id == id then
                local item = inventory.ITEMS[id]
                local ok, reason = item.use()
                if ok then
                    if not item.keep then
                        s.count = s.count - 1
                        if s.count == 0 then inventory.slots[i] = nil end
                    end
                    say(reason or ("Used a " .. item.name))
                    return true
                end
                why = why or reason
                break
            end
        end
    end
    say(why or "Nothing to use")
    return false
end

--- Lay `count` of item `id` on the ground at (x, y). `lockout` seconds pass
--- before it can be picked up (so a dropped one doesn't come straight back).
function inventory.place(id, count, x, y, lockout)
    if not hosting() or not inventory.ITEMS[id] then return nil end
    local g = { id = id, count = count or 1, x = x, y = y, lockout = lockout or 0,
        phase = (x * 0.37 + y * 0.11) % 6.283 }
    inventory.ground[#inventory.ground + 1] = g
    return g
end

--- Drop one from slot i a little ahead of you (past the bag's: that worn
--- trinket). True if it went.
function inventory.drop(i)
    local worn = i > inventory.SIZE and trinkets.worn[i - inventory.SIZE]
    local s = worn and { id = worn, count = 1 } or inventory.slots[i]
    if not (s and player.body) then return false end
    if not hosting() then
        say("Only the host can drop things")
        return false
    end
    local px, py = player.body:getPosition()
    local hx, hy = gun.lastAimDirection and gun.lastAimDirection.x or 1, gun.lastAimDirection and gun.lastAimDirection.y or 0
    local n = math.sqrt(hx * hx + hy * hy)
    if n < 1e-6 then hx, hy, n = 1, 0, 1 end
    inventory.place(s.id, 1, px + hx / n * DROP_AHEAD, py + hy / n * DROP_AHEAD, DROP_LOCKOUT)
    if worn then
        trinkets.worn[i - inventory.SIZE] = nil
        say("Dropped the " .. inventory.ITEMS[s.id].name)
        return true
    end
    say("Dropped a " .. inventory.ITEMS[s.id].name)
    s.count = s.count - 1
    if s.count == 0 then inventory.slots[i] = nil end
    return true
end

--- A dead enemy at (x, y) may leave something behind (ENEMY_DROPS), or
--- else, rarely, a trinket you haven't got.
function inventory.enemyDrop(x, y)
    for _, d in ipairs(ENEMY_DROPS) do
        if drops:random() < d[2] then
            inventory.place(d[1], 1, x, y)
            return
        end
    end
    if drops:random() < TRINKET_DROP then
        local id = trinkets.unowned(drops)
        if id then inventory.place(id, 1, x, y) end
    end
end

-- Each frame: what's on the ground slides to you once you're near, and goes
-- in the bag when it reaches you (if there's room)
function inventory.update(dt)
    if not (player.body and hosting()) then return end
    local px, py = player.body:getPosition()
    for i = #inventory.ground, 1, -1 do
        local g = inventory.ground[i]
        g.lockout = math.max(0, (g.lockout or 0) - dt)
        local dx, dy = px - g.x, py - g.y
        local d2 = dx * dx + dy * dy
        local item = inventory.ITEMS[g.id]
        if g.lockout <= 0 and d2 < MAGNET_RANGE * MAGNET_RANGE and (inventory.room(g.id) > 0 or item.pickup) then
            local d = math.sqrt(d2)
            if d < PICKUP_RANGE and item.pickup and item.pickup() then
                -- straight on (a trinket, with a free slot)
                audio.playSoundAt("coin", g.x, g.y, 0.3)
                g.count = g.count - 1
                if g.count <= 0 then table.remove(inventory.ground, i) end
            elseif d < PICKUP_RANGE and inventory.room(g.id) > 0 then
                local added = inventory.add(g.id, g.count)
                g.count = g.count - added
                say("+" .. added .. " " .. item.name)
                audio.playSoundAt("coin", g.x, g.y, 0.3)
                if g.count <= 0 then table.remove(inventory.ground, i) end
            elseif d >= PICKUP_RANGE then
                local step = math.min(d, MAGNET_SPEED * dt)
                g.x, g.y = g.x + dx / d * step, g.y + dy / d * step
            end
        end
    end
end

-- The bob of a lying item
local function bob(g)
    return math.floor(math.sin(love.timer.getTime() * 3 + g.phase) * 1.5 + 0.5)
end

--- What's on the ground, into the sorted draw list.
function inventory.populate()
    if not hosting() then return end
    local x0, y0, x1, y1 = regions.view(32)
    for _, g in ipairs(inventory.ground) do
        if g.x > x0 and g.x < x1 and g.y > y0 and g.y < y1 then
            dynamic_draw_list[#dynamic_draw_list + 1] = {
                sort_y = g.y + 100,
                image_or_particles = icon(g.id),
                x = g.x,
                y = g.y - 6 + bob(g),
                rotation = 0,
                scale_x = 1,
                scale_y = 1,
                offset_x = 8,
                offset_y = 8,
                color = { 1, 1, 1, 1 },
                blend_mode = { "alpha" },
                source_object_type = "item"
            }
        end
    end
end

--- A glow round each item on the ground, so it shows in the dark (over the
--- sorted sprites, under the camera transform).
function inventory.drawGlow()
    if not hosting() or #inventory.ground == 0 then return end
    local x0, y0, x1, y1 = regions.view(40)
    local shader = love.graphics.getShader()
    local mode, alphaMode = love.graphics.getBlendMode()
    love.graphics.setShader()
    love.graphics.setBlendMode("add", "premultiplied")
    local k = 0.3 * daynight.glow()
    for _, g in ipairs(inventory.ground) do
        if g.x > x0 and g.x < x1 and g.y > y0 and g.y < y1 then
            local pulse = k * (0.8 + 0.2 * math.sin(love.timer.getTime() * 4 + g.phase))
            love.graphics.setColor(pulse, pulse, pulse * 0.85, 1)
            love.graphics.draw(xp.haloImage, g.x - 18, g.y - 6 + bob(g) - 18, 0, 36 / 32, 36 / 32)
        end
    end
    love.graphics.setBlendMode(mode, alphaMode)
    love.graphics.setShader(shader)
    love.graphics.setColor(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

-- The panel and its slots in GUI units: the bag's, then the Worn row's
-- (cells SIZE + 1 on)
local function layout(uw, uh)
    local w = inventory.COLS * 20 + 2 + 12
    local h = 22 + inventory.ROWS * 20 + 2 + 24 + 30
    local x, y = math.floor((uw - w) / 2), math.floor(uh / 2 - h / 2 - 20)
    local cells = {}
    for i = 1, inventory.SIZE do
        local col, row = (i - 1) % inventory.COLS, math.floor((i - 1) / inventory.COLS)
        cells[i] = { x = x + 7 + col * 20, y = y + 21 + row * 20, w = 20, h = 20 }
    end
    local wornY = y + 21 + inventory.ROWS * 20 + 4
    for j = 1, trinkets.SLOTS do
        cells[inventory.SIZE + j] = { x = x + 7 + (j - 1) * 20, y = wornY, w = 20, h = 20 }
    end
    return { x = x, y = y, w = w, h = h, wornY = wornY }, cells
end

-- Move the selection: across every cell, or up and down the rows (the Worn
-- row has only its first few columns)
local function step(dx, dy)
    local total = inventory.SIZE + trinkets.SLOTS
    if dx ~= 0 then
        selected = (selected - 1 + dx) % total + 1
        return
    end
    local cols, rows = inventory.COLS, inventory.ROWS + 1
    local col, row = (selected - 1) % cols, math.floor((selected - 1) / cols)
    repeat
        row = (row + dy) % rows
    until row < inventory.ROWS or col < trinkets.SLOTS
    selected = row * cols + col + 1
end

local function toggle()
    inventory.open = not inventory.open
end

--- I / Tab open and close the bag; while it's open, its keys. H heals.
--- True when it took the key.
function inventory.keypressed(key)
    if var.State == "menu" then return false end
    if key == "i" or key == "tab" then
        toggle()
        return true
    end
    if key == "h" then
        inventory.useFirst({ "bandage", "medkit" })
        return true
    end
    if key == "k" then
        if inventory.count("car_key") > 0 then
            inventory.useFirst({ "car_key" })
        else
            say("You haven't got the car key")
        end
        return true
    end
    if not inventory.open then return false end
    if key == "escape" then
        inventory.open = false
    elseif key == "left" then
        step(-1, 0)
    elseif key == "right" then
        step(1, 0)
    elseif key == "up" then
        step(0, -1)
    elseif key == "down" then
        step(0, 1)
    elseif key == "return" or key == "kpenter" then
        inventory.use(selected)
    elseif key == "q" then
        inventory.drop(selected)
    else
        return false
    end
    return true
end

--- A click (image coordinates) on the open bag: left uses, right drops.
--- True when it was on the panel (so it doesn't shoot).
function inventory.mousepressed(x, y, button)
    if not inventory.open then return false end
    local u = skin.guiScale()
    local sw, sh = love.graphics.getDimensions()
    local panel, cells = layout(sw / u, sh / u)
    for i, cell in ipairs(cells) do
        if skin.contains(cell, x / u, y / u) then
            selected = i
            if button == 1 then
                inventory.use(i)
            elseif button == 2 then
                inventory.drop(i)
            end
            return true
        end
    end
    return skin.contains(panel, x / u, y / u)
end

local function drawCell(cell, s, ts, highlighted)
    love.graphics.setColor(0.45, 0.45, 0.47, 0.9)
    love.graphics.rectangle("fill", cell.x, cell.y, cell.w, 1)
    love.graphics.rectangle("fill", cell.x, cell.y + cell.h - 1, cell.w, 1)
    love.graphics.rectangle("fill", cell.x, cell.y + 1, 1, cell.h - 2)
    love.graphics.rectangle("fill", cell.x + cell.w - 1, cell.y + 1, 1, cell.h - 2)
    if highlighted then
        love.graphics.setColor(1, 1, 1, 0.22)
    else
        love.graphics.setColor(0.12, 0.12, 0.13, 0.55)
    end
    love.graphics.rectangle("fill", cell.x + 1, cell.y + 1, cell.w - 2, cell.h - 2)
    if s then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(icon(s.id), cell.x + 2, cell.y + 2)
        if s.count > 1 then
            local text = tostring(s.count)
            local tx = cell.x + 19 - font:getWidth(text) * ts
            local ty = cell.y + 19 - font:getBaseline() * ts
            love.graphics.setColor(0.25, 0.25, 0.25, 1)
            love.graphics.print(text, tx + ts, ty + ts, 0, ts, ts)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(text, tx, ty, 0, ts, ts)
        end
    end
end

--- The open bag, and what just happened (picked up, used, dropped). Screen
--- space, under the CRT with the rest of the UI.
function inventory.drawUI()
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

    if inventory.open then
        local panel, cells = layout(sw / u, sh / u)
        love.graphics.setColor(0.08, 0.08, 0.10, 0.92)
        love.graphics.rectangle("fill", panel.x, panel.y, panel.w, panel.h)
        love.graphics.setColor(0.64, 0.66, 0.73, 1)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", panel.x + 0.5, panel.y + 0.5, panel.w - 1, panel.h - 1)
        skin.printCentered("Bag", panel.x + panel.w / 2, panel.y + 6, ts, skin.WHITE)

        local mx, my = crt.mouse()
        local hovered
        local function slot(i)
            if i <= inventory.SIZE then return inventory.slots[i] end
            local id = trinkets.worn[i - inventory.SIZE]
            return id and { id = id, count = 1 }
        end
        for i, cell in ipairs(cells) do
            local over = skin.contains(cell, mx / u, my / u)
            if over then hovered = i end
            drawCell(cell, slot(i), ts, over or i == selected)
        end
        local last = cells[inventory.SIZE + trinkets.SLOTS]
        love.graphics.setColor(skin.GRAY)
        love.graphics.print("Worn: trinkets pay in light", last.x + last.w + 5,
            panel.wornY + 10 - font:getBaseline() * ts / 2 - 2, 0, ts, ts)
        local i = hovered or selected
        local s = slot(i)
        local footY = panel.y + panel.h - 26
        if s then
            local item = inventory.ITEMS[s.id]
            skin.printCentered(item.name .. ": " .. item.desc, panel.x + panel.w / 2, footY, ts, skin.YELLOW)
        else
            skin.printCentered("Empty", panel.x + panel.w / 2, footY, ts, skin.GRAY)
        end
        local help = i > inventory.SIZE and "Enter take off   Q drop   I close"
            or (s and inventory.ITEMS[s.id].trinket and "Enter wear   Q drop   I close")
            or "Enter use   Q drop   I close"
        skin.printCentered(help, panel.x + panel.w / 2, footY + 12, ts, skin.GRAY)
    end

    local age = love.timer.getTime() - messageAt
    if message and age < MESSAGE_TIME then
        skin.printCentered(message, sw / u / 2, sh / u - 62, ts, skin.WHITE,
            math.min(1, (MESSAGE_TIME - age) * 2))
    end

    love.graphics.pop()
    love.graphics.setFont(prevFont)
    love.graphics.setColor(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- Saves
--------------------------------------------------------------------------------

--- The bag and what's on the ground, as plain data for a save.
function inventory.getSaveData()
    local slots, ground = {}, {}
    for i = 1, inventory.SIZE do
        local s = inventory.slots[i]
        if s then slots[#slots + 1] = { slot = i, id = s.id, count = s.count } end
    end
    for _, g in ipairs(inventory.ground) do
        ground[#ground + 1] = { id = g.id, count = g.count, x = g.x, y = g.y }
    end
    return { slots = slots, ground = ground }
end

--- Put back what getSaveData gave; nil (a save from before the bag) empties it.
--- Items the game no longer has are left out.
function inventory.restore(data)
    inventory.reset()
    if type(data) ~= "table" then return end
    for _, s in ipairs(data.slots or {}) do
        local item = inventory.ITEMS[s.id]
        if item and type(s.slot) == "number" and s.slot >= 1 and s.slot <= inventory.SIZE
            and not inventory.slots[s.slot] then
            inventory.slots[s.slot] = { id = s.id, count = math.max(1, math.min(item.stack, s.count or 1)) }
        end
    end
    for _, g in ipairs(data.ground or {}) do
        if inventory.ITEMS[g.id] and g.x and g.y then
            inventory.place(g.id, g.count or 1, g.x, g.y)
        end
    end
    placeKey()
end

return inventory
