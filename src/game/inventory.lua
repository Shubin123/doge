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
    * Food heals, over time for bread and honey cake, or fills the light
      bar, or (a chili) makes you quick for a while.
    * Trinkets (game/trinkets.lua) take slots like the rest, and work while
      they're in the bag and equipped (framed in gold): using one equips or
      unequips it. Now and then an enemy leaves one you haven't got.
    * Armor (game/armor.lua) takes slots too, until it's worn: the panel shows
      what's worn down its left side, and using a piece wears it or takes it
      off.
    * The quest log (game/quests.lua) runs down the panel's right side.

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
local ENEMY_DROPS = {
    { "apple", 0.04 }, { "bandage", 0.035 }, { "light_cell", 0.025 }, { "glowberries", 0.025 },
    { "bread", 0.015 }, { "drumstick", 0.01 }, { "chili", 0.01 }, { "medkit", 0.01 },
}
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
    g = { 0.40, 0.75, 0.25 }, -- leaf
    G = { 0.18, 0.45, 0.12 }, -- dark leaf
    n = { 0.66, 0.36, 0.16 }, -- roast
    N = { 0.42, 0.20, 0.08 }, -- dark roast
}

local CHILI_SPEED, CHILI_TIME = 1.4, 15 -- how much quicker a chili makes you, for how long (s)
local effects = { regen = 0, regenRate = 0, quick = 0 } -- what you've eaten still doing its work

-- Food that heals `hp` at once
local function heals(hp)
    return function()
        if player.health >= player.maxHealth then return false, "Hearts are full" end
        player.health = math.min(player.maxHealth, player.health + hp)
        return true
    end
end

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
    apple = {
        name = "Apple", desc = "+1 heart", stack = 16, food = true,
        use = heals(100),
        icon = {
            "................",
            "........kk.kk...",
            "........kNkggk..",
            "....kkkkkNkkk...",
            "...krrrrrkrrrk..",
            "..krWrrrrrrrrrk.",
            "..krWrrrrrrrrRk.",
            "..krrrrrrrrrrRk.",
            "..krrrrrrrrrrRk.",
            "..krrrrrrrrrRRk.",
            "...krrrrrrrRRk..",
            "...krrrrrrRRRk..",
            "....krrRkkRRk...",
            ".....kkk..kkk...",
            "................",
            "................",
        },
    },
    bread = {
        name = "Bread", desc = "+3 hearts over 6 s", stack = 8, food = true,
        use = function()
            if player.health >= player.maxHealth then return false, "Hearts are full" end
            effects.regen = effects.regen + 300
            effects.regenRate = math.max(effects.regenRate, 50) -- (three hearts over six seconds)
            return true
        end,
        icon = {
            "................",
            "................",
            "................",
            "....kkkkkkkk....",
            "..kktttttttTkk..",
            ".ktTttTttTttTTk.",
            ".kttTttTttTttTk.",
            "kttttttttttttTTk",
            "kttttttttttttTTk",
            "kTttttttttttTTTk",
            "kTTTTTTTTTTTTTTk",
            ".kkkkkkkkkkkkkk.",
            "................",
            "................",
            "................",
            "................",
        },
    },
    drumstick = {
        name = "Drumstick", desc = "+4 hearts", stack = 8, food = true,
        use = heals(400),
        icon = {
            "................",
            "...kkkkk........",
            "..knnnnnk.......",
            ".knWnnnnnk......",
            ".knnnnnnnk......",
            ".knnnnnnNk......",
            ".kNnnnnNNk......",
            "..kNNNNNk.......",
            "...kkkkksk......",
            "........kssk....",
            ".........kssk...",
            "..........ksskk.",
            "..........ksssk.",
            "...........ksk..",
            "............k...",
            "................",
        },
    },
    glowberries = {
        name = "Glowberries", desc = "+35 light", stack = 16, food = true,
        use = function()
            if gun.ammo >= gun.maxAmmo then return false, "Light is full" end
            gun.addAmmo(35)
            return true
        end,
        icon = {
            "................",
            ".......kk.......",
            "......kGgk......",
            ".....kgGk.......",
            "...kkkkkkkk.....",
            "..kyyWkkyyWk....",
            "..kyyykkyyyk....",
            "..kYyykkYyyk....",
            "...kkkkkkkkkk...",
            "....kyyWkkyWyk..",
            "....kyyykkyyyk..",
            "....kYYykkYYyk..",
            ".....kkk..kkk...",
            "................",
            "................",
            "................",
        },
    },
    noodles = {
        name = "Noodles", desc = "+2 hearts, +20 light", stack = 8, food = true,
        use = function()
            if player.health >= player.maxHealth and gun.ammo >= gun.maxAmmo then
                return false, "Hearts and light are full"
            end
            player.health = math.min(player.maxHealth, player.health + 200)
            gun.addAmmo(20)
            return true
        end,
        icon = {
            "................",
            ".....W...W......",
            "......W...W.....",
            ".....W...W......",
            "................",
            "..kkkkkkkkkkkk..",
            ".kyyyYyyyYyyyyk.",
            ".kyYyyyYyyyYyyk.",
            ".krrrrrrrrrrrrk.",
            "..krrrrrrrrrrk..",
            "..kRrrrrrrrrRk..",
            "...kRRrrrrRRk...",
            "....kkkkkkkk....",
            "................",
            "................",
            "................",
        },
    },
    honey_cake = {
        name = "Honey cake", desc = "+5 hearts over 10 s", stack = 8, food = true,
        use = function()
            if player.health >= player.maxHealth then return false, "Hearts are full" end
            effects.regen = effects.regen + 500
            effects.regenRate = math.max(effects.regenRate, 50)
            return true
        end,
        icon = {
            "................",
            "................",
            "......kkkk......",
            "....kkyyyykk....",
            "..kkyyyyyyyykk..",
            ".kyyyyyyyyyyyyk.",
            ".kYyyYyyyyYyyYk.",
            ".ktYttYttYttYtk.",
            ".kttttttttttttk.",
            ".kTTTTTTTTTTTTk.",
            ".kttttttttttttk.",
            ".kTttttttttttTk.",
            ".kkkkkkkkkkkkkk.",
            "................",
            "................",
            "................",
        },
    },
    chili = {
        name = "Chili pepper", desc = "Quick for " .. CHILI_TIME .. " s", stack = 8, food = true,
        use = function()
            effects.quick = CHILI_TIME
            player.speedBoost = CHILI_SPEED
            return true, "Hot! You're quick for " .. CHILI_TIME .. " s"
        end,
        icon = {
            "................",
            "...........kk...",
            "..........kgk...",
            "........kkgGk...",
            ".......kGGGkk...",
            "......krrrrk....",
            ".....krWrrrk....",
            "....krWrrrRk....",
            "...krrrrrRk.....",
            "..krrrrrRRk.....",
            ".krrrrRRRk......",
            ".krrRRRkk.......",
            "..kkkkk.........",
            "................",
            "................",
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

-- `palette` (an item's own colours, by letter) goes before the bag's
local function makeImage(rows, palette)
    local data = love.image.newImageData(#rows[1], #rows)
    for y = 1, #rows do
        assert(#rows[y] == #rows[1], "inventory icon rows differ in width")
        for x = 1, #rows[y] do
            local ch = rows[y]:sub(x, x)
            local c = palette and palette[ch] or PALETTE[ch]
            if c then data:setPixel(x - 1, y - 1, c[1], c[2], c[3], 1) end
        end
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    return image
end
inventory.makeIcon = makeImage -- (armor's empty slots)

local function icon(id)
    local item = inventory.ITEMS[id]
    icons[id] = icons[id] or makeImage(item.icon, item.palette)
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
    effects.regen, effects.regenRate, effects.quick = 0, 0, 0
    if player then player.speedBoost = nil end
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

--- Use what's in slot i. True if it did something.
function inventory.use(i)
    local s = inventory.slots[i]
    if not s then return false end
    local item = inventory.ITEMS[s.id]
    local ok, why = item.use(s)
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
                local ok, reason = item.use(s)
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

--- Drop one from slot i a little ahead of you. True if it went.
function inventory.drop(i)
    local s = inventory.slots[i]
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

-- Each frame: what you've eaten works on; what's on the ground slides to you
-- once you're near, and goes in the bag when it reaches you (if there's room)
function inventory.update(dt)
    if effects.regen > 0 then
        local hp = math.min(effects.regen, effects.regenRate * dt)
        effects.regen = effects.regen - hp
        player.health = math.min(player.maxHealth, player.health + hp)
        if player.health >= player.maxHealth then effects.regen = 0 end
    end
    if effects.quick > 0 then
        effects.quick = effects.quick - dt
        if effects.quick <= 0 then player.speedBoost = nil end
    end
    if not (player.body and hosting()) then return end
    local px, py = player.body:getPosition()
    for i = #inventory.ground, 1, -1 do
        local g = inventory.ground[i]
        g.lockout = math.max(0, (g.lockout or 0) - dt)
        local dx, dy = px - g.x, py - g.y
        local d2 = dx * dx + dy * dy
        local item = inventory.ITEMS[g.id]
        if g.lockout <= 0 and d2 < MAGNET_RANGE * MAGNET_RANGE and inventory.room(g.id) > 0 then
            local d = math.sqrt(d2)
            if d < PICKUP_RANGE then
                local added = inventory.add(g.id, g.count)
                g.count = g.count - added
                say("+" .. added .. " " .. item.name)
                audio.playSoundAt("coin", g.x, g.y, 0.3)
                if g.count <= 0 then table.remove(inventory.ground, i) end
            elseif d > 0 then
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

local WORN_W = 26   -- the column of worn armor beside the bag, and the gap between them
local QUEST_W = 176 -- the quest log down the panel's right side, if the screen's that wide

-- The panel, its bag slots, its armor slots and its quest log in GUI units
local function layout(uw, uh)
    local bagW = inventory.COLS * 20 + 2 + 12 + WORN_W
    local questW = math.min(QUEST_W, math.floor(uw) - bagW - 8)
    local w = bagW + questW
    local h = 22 + #armor.SLOTS * 20 + 2 + 42
    local x, y = math.floor((uw - w) / 2), math.floor(uh / 2 - h / 2 - 20)
    local cells, worn = {}, {}
    for i = 1, inventory.SIZE do
        local col, row = (i - 1) % inventory.COLS, math.floor((i - 1) / inventory.COLS)
        cells[i] = { x = x + 7 + WORN_W + col * 20, y = y + 21 + row * 20, w = 20, h = 20 }
    end
    for k = 1, #armor.SLOTS do
        worn[k] = { x = x + 7, y = y + 21 + (k - 1) * 20, w = 20, h = 20 }
    end
    return { x = x, y = y, w = w, h = h }, cells, worn, { x = x + bagW + 5, y = y, w = questW - 11, h = h - 40 }
end

local function toggle()
    inventory.open = not inventory.open
end

-- The arrows: round the bag, off its sides onto the worn column (selected
-- past inventory.SIZE), and up and down that column
local function moveSelection(key)
    local size, cols, rows, worn = inventory.SIZE, inventory.COLS, inventory.ROWS, #armor.SLOTS
    if selected > size then
        local k = selected - size
        if key == "up" then
            selected = size + (k - 2) % worn + 1
        elseif key == "down" then
            selected = size + k % worn + 1
        else
            local row = math.min(rows - 1, math.floor((k - 1) * rows / worn))
            selected = row * cols + (key == "right" and 1 or cols)
        end
    elseif key == "left" and (selected - 1) % cols == 0 or key == "right" and selected % cols == 0 then
        selected = size + 1 + math.floor(math.floor((selected - 1) / cols) * worn / rows)
    elseif key == "left" then
        selected = selected - 1
    elseif key == "right" then
        selected = selected + 1
    elseif key == "up" then
        selected = (selected - 1 - cols) % size + 1
    else
        selected = (selected - 1 + cols) % size + 1
    end
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
        inventory.useFirst({ "bandage", "apple", "bread", "drumstick", "medkit" })
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
    elseif key == "left" or key == "right" or key == "up" or key == "down" then
        moveSelection(key)
    elseif key == "return" or key == "kpenter" then
        if selected > inventory.SIZE then
            armor.takeOff(selected - inventory.SIZE)
        else
            inventory.use(selected)
        end
    elseif key == "q" then
        if selected > inventory.SIZE then
            say("Take it off first")
        else
            inventory.drop(selected)
        end
    else
        return false
    end
    return true
end

--- A click (image coordinates) on the open bag: left uses, right drops; on a
--- worn piece, left takes it off. True when it was on the panel (so it
--- doesn't shoot).
function inventory.mousepressed(x, y, button)
    if not inventory.open then return false end
    local u = skin.guiScale()
    local sw, sh = love.graphics.getDimensions()
    local panel, cells, worn = layout(sw / u, sh / u)
    for k, cell in ipairs(worn) do
        if skin.contains(cell, x / u, y / u) then
            selected = inventory.SIZE + k
            if button == 1 then armor.takeOff(k) end
            return true
        end
    end
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
    local item = s and inventory.ITEMS[s.id]
    if item and item.trinket and s.on ~= false then
        -- an equipped trinket, framed in gold
        love.graphics.setColor(1.00, 0.84, 0.30, 0.9)
        love.graphics.rectangle("line", cell.x + 1.5, cell.y + 1.5, cell.w - 3, cell.h - 3)
    end
    if s then
        love.graphics.setColor(1, 1, 1, item.trinket and s.on == false and 0.4 or 1)
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

-- The quest log down the panel's right side: the current quest first, in
-- yellow with its steps, then the rest in order, ticked or just named. What
-- doesn't fit above the panel's foot is left off.
local function drawQuests(box, ts)
    love.graphics.setColor(0.64, 0.66, 0.73, 0.5)
    love.graphics.rectangle("fill", box.x - 5, box.y + 5, 1, box.h - 5)
    skin.printCentered("Quests", box.x + box.w / 2, box.y + 6, ts, skin.WHITE)
    local lineH = font:getHeight() * ts + 1
    local tick = font:getWidth("[x] ") * ts
    local y, bottom = box.y + 21, box.y + box.h
    local function entry(x, done, text, color)
        local _, wrapped = font:getWrap(text, (box.x + box.w - x - tick) / ts)
        for n, part in ipairs(wrapped) do
            if y + lineH <= bottom then
                if n == 1 then skin.print(done and "[x]" or "[ ]", x, y, ts, color) end
                skin.print(part, x + tick, y, ts, color)
            end
            y = y + lineH
        end
    end
    local log = quests.log()
    for _, q in ipairs(log) do
        if q.current then
            entry(box.x, false, q.title, skin.YELLOW)
            for _, s in ipairs(q.steps) do
                entry(box.x + 6, s.done, s.text, s.done and skin.GRAY or skin.WHITE)
            end
        end
    end
    for _, q in ipairs(log) do
        if not q.current then entry(box.x, q.done, q.title, skin.GRAY) end
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
        local panel, cells, worn, log = layout(sw / u, sh / u)
        love.graphics.setColor(0.08, 0.08, 0.10, 0.92)
        love.graphics.rectangle("fill", panel.x, panel.y, panel.w, panel.h)
        love.graphics.setColor(0.64, 0.66, 0.73, 1)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", panel.x + 0.5, panel.y + 0.5, panel.w - 1, panel.h - 1)
        skin.printCentered("Worn", worn[1].x + worn[1].w / 2, panel.y + 6, ts, skin.WHITE)
        skin.printCentered("Bag", cells[1].x + inventory.COLS * 10, panel.y + 6, ts, skin.WHITE)
        drawQuests(log, ts)

        local mx, my = crt.mouse()
        local hovered
        for i, cell in ipairs(cells) do
            local over = skin.contains(cell, mx / u, my / u)
            if over then hovered = i end
            drawCell(cell, inventory.slots[i], ts, over or i == selected)
        end
        for k, cell in ipairs(worn) do
            local over = skin.contains(cell, mx / u, my / u)
            if over then hovered = inventory.SIZE + k end
            local id = armor.wornAt(k)
            drawCell(cell, id and { id = id, count = 1 }, ts, over or selected == inventory.SIZE + k)
            if not id then
                love.graphics.setColor(1, 1, 1, 0.35)
                love.graphics.draw(armor.slotIcon(k), cell.x + 2, cell.y + 2)
            end
        end

        -- What it all adds up to, under the bag
        local lineH = font:getHeight() * ts + 1
        for n, line in ipairs(armor.statLines()) do
            local col, row = (n - 1) % 2, math.floor((n - 1) / 2)
            skin.print(line, cells[1].x + 1 + col * 90, cells[1].y + inventory.ROWS * 20 + 4 + row * lineH, ts, skin.WHITE)
        end

        local which = hovered or selected
        local wornSlot = which > inventory.SIZE and armor.SLOTS[which - inventory.SIZE]
        local s
        if wornSlot then
            local id = armor.worn[wornSlot]
            s = id and { id = id, count = 1 }
        else
            s = inventory.slots[which]
        end
        local item = s and inventory.ITEMS[s.id]
        local footY = panel.y + panel.h - 38
        local cx = panel.x + panel.w / 2
        if item and item.armor then
            local title = item.name .. " (" .. armor.slotName(item.armor) .. ")" .. (wornSlot and " - worn" or "")
            skin.printCentered(title, cx, footY, ts, skin.YELLOW)
            skin.printCentered(item.desc, cx, footY + 12, ts, skin.WHITE)
        elseif s then
            local state = item.trinket and (s.on == false and " - off" or " - equipped") or ""
            skin.printCentered(item.name .. ": " .. item.desc .. state, cx, footY + 6, ts, skin.YELLOW)
        elseif wornSlot then
            skin.printCentered(armor.slotName(wornSlot) .. ": nothing worn", cx, footY + 6, ts, skin.GRAY)
        else
            skin.printCentered("Empty", cx, footY + 6, ts, skin.GRAY)
        end
        local help
        if wornSlot then
            help = s and "Enter take off   I close" or "I close"
        else
            help = (item and item.armor and "Enter wear"
                or item and item.trinket and (s.on == false and "Enter equip" or "Enter unequip")
                or item and item.food and "Enter eat" or "Enter use") .. "   Q drop   I close"
        end
        skin.printCentered(help, cx, footY + 24, ts, skin.GRAY)
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
        if s then slots[#slots + 1] = { slot = i, id = s.id, count = s.count, on = s.on } end
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
            if s.on == false then inventory.slots[s.slot].on = false end -- (a trinket unequipped)
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
