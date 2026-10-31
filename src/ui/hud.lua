-- hud.lua
-- Minecraft-style HUD: a hotbar of weapons and items along the bottom of the
-- screen with pixel-art icons, hearts for health, flashlights for the universal
-- ammo (light-based, where Minecraft has hunger), and points on an XP bar.
-- Everything is laid out in GUI units (one icon pixel) and scaled up by a whole
-- number so the pixel art stays crisp.

local hud = {}

local SLOTS = 9              -- hotbar slots; weapons fill from the left
local HEARTS = 10            -- each heart is two halves of player.maxHealth / 20
local FLASHLIGHTS = 10       -- likewise for gun.maxAmmo
local POINTS_PER_LEVEL = 100 -- the XP bar fills once per this many points
local NAME_SHOW_TIME = 2.0   -- seconds the weapon name stays up after a switch
local NAME_FADE_TIME = 0.5

local WEAPON_NAMES = { "Pistol", "SMG", "Shotgun", "Assault Rifle", "Rocket Launcher", "Tesla Coil", "Bow", "Fireball" }

local PALETTE = {
    k = { 0.08, 0.08, 0.10 }, -- outline
    d = { 0.24, 0.25, 0.29 }, -- dark metal
    m = { 0.42, 0.44, 0.50 }, -- metal
    l = { 0.64, 0.66, 0.73 }, -- light metal
    h = { 0.86, 0.88, 0.94 }, -- metal highlight
    w = { 0.33, 0.19, 0.10 }, -- dark wood
    b = { 0.55, 0.34, 0.17 }, -- wood
    B = { 0.74, 0.50, 0.27 }, -- light wood
    g = { 0.60, 1.00, 0.15 }, -- acid green (SMG tracer)
    o = { 1.00, 0.50, 0.08 }, -- orange (shotgun tracer)
    O = { 0.66, 0.26, 0.05 }, -- dark orange
    c = { 0.40, 0.80, 1.00 }, -- ice blue (rifle tracer)
    u = { 0.58, 0.62, 0.34 }, -- light olive
    v = { 0.42, 0.46, 0.22 }, -- olive
    V = { 0.28, 0.31, 0.14 }, -- dark olive
    y = { 1.00, 0.84, 0.20 }, -- yellow / brass
    Y = { 0.70, 0.50, 0.10 }, -- dark brass
    r = { 0.86, 0.14, 0.10 }, -- red
    R = { 0.52, 0.06, 0.05 }, -- dark red
    p = { 0.84, 0.48, 0.22 }, -- copper
    P = { 0.52, 0.26, 0.10 }, -- dark copper
    e = { 0.35, 0.60, 1.00 }, -- electric blue (tesla glow)
    W = { 1.00, 1.00, 1.00 }, -- white
    s = { 0.90, 0.90, 0.84 }, -- bow string
    L = { 1.00, 0.95, 0.60 }, -- light rays (dropped from empty icons)
    x = { 0.20, 0.20, 0.22 }, -- empty heart / fireball socket
}

-- 16x16 weapon icons, in gun.guns order.
local ICONS = {
    { -- Pistol
        "................",
        "................",
        "................",
        ".kkkkkkkkkkkkkk.",
        ".khhhhhhhhhhhhk.",
        ".kllldldllllllk.",
        ".kmmmmmmmmmmmmk.",
        ".kddddddddddddk.",
        ".kBbbbkkkkkkkkk.",
        ".kBbwbk.d..k....",
        ".kBbwbkkkkkk....",
        "kBbwbk..........",
        "kBbbbk..........",
        "kkkkkk..........",
        "................",
        "................",
    },
    { -- SMG
        "................",
        "................",
        "................",
        "..kkkkkkkkkk....",
        "kkkhhhhhhhhkkkkk",
        "k.kggggggggmmmlk",
        "kkkmmmmmmmmddddk",
        "..kddddddddkkkkk",
        "..kBbbkkkddk....",
        "..kBwbk.kddk....",
        "..kBwbk.kddk....",
        "..kBbbk.kddk....",
        "..kkkkk.kkkk....",
        "................",
        "................",
        "................",
    },
    { -- Shotgun
        "................",
        "................",
        "................",
        "................",
        ".....kkkkkkkkkkk",
        "...kkdhhhhhhhhhk",
        "kkkBBdmmmmmmmmmk",
        "kBBbbddkkkkkkkkk",
        "kbbbkkdkmooooomk",
        "kbbwk.kkOOOOOOk.",
        "kbwwk...kkkkkk..",
        "kkkkk...........",
        "................",
        "................",
        "................",
        "................",
    },
    { -- Assault Rifle
        "................",
        "................",
        "................",
        "......kkkk......",
        "kkkk..kcck......",
        "kddkkkkkkkkkkkkk",
        "kdmmhhhhhhhllllk",
        "kdmmmmmmmmmkkkkk",
        "kddkdcccccdk....",
        "kkkkwbkmdk......",
        "...kwbkkmdk.....",
        "...kkkk.kmdk....",
        "........kkkk....",
        "................",
        "................",
        "................",
    },
    { -- Rocket Launcher
        "................",
        "................",
        "................",
        "......kk........",
        ".kkkkkkkkkkkk...",
        ".kuyuuuuuyuukk..",
        ".kvyvvvvvyvvRrk.",
        ".kvyvvvvvyvvRrrk",
        ".kVyVVVVVyVVRrk.",
        ".kVyVVVVVyVVkk..",
        ".kkkkkkkkkkkk...",
        "....kbk..kbk....",
        "....kwk..kwk....",
        "....kkk..kkk....",
        "................",
        "................",
    },
    { -- Tesla Coil
        ".e............e.",
        "e.e..kkkkkk..e.e",
        "...ekhhlllmke...",
        "eeekhllllmmdkeee",
        "....kmmmmmdk....",
        ".....kkkkkk.....",
        ".....kppppk.....",
        ".....kPPPPk.....",
        ".....kppppk.....",
        ".....kPPPPk.....",
        ".....kppppk.....",
        ".....kPPPPk.....",
        "....kmmmmmmk....",
        "...kddddddddk...",
        "...kkkkkkkkkk...",
        "................",
    },
    { -- Bow
        "............mhh.",
        "..wwwwww....lhh.",
        ".wbBBBBbww..Bmm.",
        ".wsbbbbbBbwB....",
        "..wsk...kbBw....",
        "...ws.....Bbw...",
        "....s....BkBw...",
        ".....s..B..Bbw..",
        "......sB...kBw..",
        "......Bs....bw..",
        ".....B..s...Bbw.",
        "....B....s..kbw.",
        "...B......s.kbw.",
        ".WB........sbw..",
        "WW..........ww..",
        ".W..............",
    },
    { -- Fireball
        ".......kk.......",
        "....k.krrk.k....",
        "...krkkookkrk...",
        "...kokkoykkok...",
        "...koykyykyok...",
        "...kyooyyooyk...",
        "..krooooooorrk..",
        "..krrooooorrrk..",
        "..krooyyyoorrk..",
        "..kooyWWyyorRk..",
        "..kooyWWyyoRRk..",
        "..kooyyyyyoRRk..",
        "..krooyyyooRRk..",
        "...kroooooRRk...",
        "....krroRRRk....",
        ".....kkkkkk.....",
    },
}

local HEART = {
    ".kkk.kkk.",
    "kWrrkrrrk",
    "kWrrrrrrk",
    "krrrrrrRk",
    ".krrrrRk.",
    "..krrRk..",
    "...kRk...",
    "....k....",
}

local FLASHLIGHT = {
    "L...L...L",
    ".LkkkkkL.",
    ".kyWWWyk.",
    ".kmlllmk.",
    "..kmldk..",
    "..kmrdk..",
    "..kmldk..",
    "..kmldk..",
    "..kkkkk..",
}

local icons = {}
local heart, heartEmpty, heartHalf, flashlight, flashlightEmpty, flashlightHalf
local font
local lastWeapon
local nameShownAt = -math.huge

-- Turns a grid of palette characters into a nearest-filtered image.
local function makeImage(rows)
    local data = love.image.newImageData(#rows[1], #rows)
    for y = 1, #rows do
        for x = 1, #rows[y] do
            local c = PALETTE[rows[y]:sub(x, x)]
            if c then data:setPixel(x - 1, y - 1, c[1], c[2], c[3], 1) end
        end
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    return image
end

-- Same outline, everything inside filled with the empty-socket colour and
-- any light rays switched off.
local function makeEmpty(rows)
    local empty = {}
    for i, row in ipairs(rows) do
        empty[i] = row:gsub("L", "."):gsub("[^k%.]", "x")
    end
    return makeImage(empty)
end

function hud.load()
    for i, rows in ipairs(ICONS) do
        icons[i] = makeImage(rows)
    end
    heart, heartEmpty = makeImage(HEART), makeEmpty(HEART)
    flashlight, flashlightEmpty = makeImage(FLASHLIGHT), makeEmpty(FLASHLIGHT)
    -- Hearts empty from the right and flashlights from the left, as in Minecraft.
    heartHalf = love.graphics.newQuad(0, 0, 5, #HEART, heart:getDimensions())
    flashlightHalf = love.graphics.newQuad(4, 0, 5, #FLASHLIGHT, flashlight:getDimensions())
    font = love.graphics.newFont("gfx/menu/Px437_IBM_VGA_8x16.ttf", 16)
    font:setFilter("nearest", "nearest")
end

-- Largest whole GUI scale that fits a 320x240 layout, like Minecraft's "auto".
local function guiScale()
    local w, h = love.graphics.getDimensions()
    return math.max(1, math.min(math.floor(w / 320), math.floor(h / 240)))
end

local function box(x, y, w, h)
    love.graphics.rectangle("fill", x, y, w, h)
end

local function border(x, y, w, h, t)
    box(x, y, w, t)
    box(x, y + h - t, w, t)
    box(x, y + t, t, h - 2 * t)
    box(x + w - t, y + t, t, h - 2 * t)
end

-- Fraction of the weapon's reload still to go (0 when ready). Only the
-- Gun-prototype weapons have a fire-rate cooldown.
local function cooldownFraction(weapon)
    if weapon.fireRate and weapon.cooldown > 0 then
        return math.min(1, weapon.cooldown * weapon.fireRate)
    end
    return 0
end

local function drawHotbar(x, y, slots, ts)
    local width = slots * 20 + 2
    love.graphics.setColor(0.05, 0.05, 0.05, 0.85)
    box(x, y, width, 22)
    for i = 0, slots - 1 do
        local sx, sy = x + 1 + i * 20, y + 1
        love.graphics.setColor(0.45, 0.45, 0.47, 0.9)
        border(sx, sy, 20, 20, 1)
        love.graphics.setColor(0.12, 0.12, 0.13, 0.55)
        box(sx + 1, sy + 1, 18, 18)
        love.graphics.setColor(0, 0, 0, 0.35) -- inset shadow
        box(sx + 1, sy + 1, 18, 1)
        box(sx + 1, sy + 2, 1, 17)
    end

    for i, weapon in ipairs(gun.guns) do
        if i > slots then break end
        local ix, iy = x + 3 + (i - 1) * 20, y + 3
        if icons[i] then
            -- Faded when out of ammo (or, for an item, out of stock)
            love.graphics.setColor(1, 1, 1, gun.canFire(weapon) and 1 or 0.35)
            love.graphics.draw(icons[i], ix, iy)
        end
        local f = cooldownFraction(weapon)
        if f > 0 then
            love.graphics.setColor(1, 1, 1, 0.5)
            box(ix, iy + 16 * (1 - f), 16, 16 * f)
        end
        local count = weapon.getCount and weapon:getCount() or 0
        if count > 1 then
            -- Stack size in the bottom-right corner, like a Minecraft item stack
            local text = tostring(count)
            local tx = ix + 17 - font:getWidth(text) * ts
            local ty = iy + 17 - font:getBaseline() * ts
            love.graphics.setColor(0.25, 0.25, 0.25, 1)
            love.graphics.print(text, tx + ts, ty + ts, 0, ts, ts)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(text, tx, ty, 0, ts, ts)
        end
    end

    local sel = gun.currentWeaponIndex - 1
    local sx, sy = x + sel * 20 - 1, y - 1
    love.graphics.setColor(0, 0, 0, 0.9)
    border(sx, sy, 24, 24, 1)
    love.graphics.setColor(0.95, 0.95, 0.95, 1)
    border(sx + 1, sy + 1, 22, 22, 2)
    love.graphics.setColor(0.55, 0.55, 0.58, 1)
    border(sx + 3, sy + 3, 18, 18, 1)
end

local function drawHearts(x, y)
    local maxHealth = player.maxHealth or player.health
    local halves = math.ceil(math.max(0, math.min(1, player.health / maxHealth)) * HEARTS * 2)
    love.graphics.setColor(1, 1, 1, 1)
    for i = 0, HEARTS - 1 do
        local hx = x + i * 8
        love.graphics.draw(heartEmpty, hx, y)
        if halves >= i * 2 + 2 then
            love.graphics.draw(heart, hx, y)
        elseif halves == i * 2 + 1 then
            love.graphics.draw(heart, heartHalf, hx, y)
        end
    end
end

-- Universal ammo, filling from the right like Minecraft's hunger bar.
local function drawAmmo(right, y)
    local halves = math.ceil(math.max(0, math.min(1, gun.ammo / gun.maxAmmo)) * FLASHLIGHTS * 2)
    love.graphics.setColor(1, 1, 1, 1)
    for i = 0, FLASHLIGHTS - 1 do
        local fx = right - 9 - i * 8
        love.graphics.draw(flashlightEmpty, fx, y)
        if halves >= i * 2 + 2 then
            love.graphics.draw(flashlight, fx, y)
        elseif halves == i * 2 + 1 then
            love.graphics.draw(flashlight, flashlightHalf, fx + 4, y)
        end
    end
end

-- Text in GUI units; one font pixel is `ts` units.
local function outlinedText(text, x, y, ts, color, outline)
    love.graphics.setColor(outline)
    love.graphics.print(text, x - ts, y, 0, ts, ts)
    love.graphics.print(text, x + ts, y, 0, ts, ts)
    love.graphics.print(text, x, y - ts, 0, ts, ts)
    love.graphics.print(text, x, y + ts, 0, ts, ts)
    love.graphics.setColor(color)
    love.graphics.print(text, x, y, 0, ts, ts)
end

local function drawXP(x, y, width, ts)
    local score = var.player_score
    local progress = (score % POINTS_PER_LEVEL) / POINTS_PER_LEVEL
    love.graphics.setColor(0, 0, 0, 0.85)
    box(x, y, width, 5)
    love.graphics.setColor(0.16, 0.18, 0.14, 0.9)
    box(x + 1, y + 1, width - 2, 3)
    local fill = math.floor((width - 2) * progress)
    if fill > 0 then
        love.graphics.setColor(0.36, 0.82, 0.10, 1)
        box(x + 1, y + 1, fill, 3)
        love.graphics.setColor(0.62, 1.00, 0.28, 1)
        box(x + 1, y + 1, fill, 1)
    end

    local text = tostring(score)
    local tx = x + (width - font:getWidth(text) * ts) / 2
    local ty = y + 1 - font:getBaseline() * ts -- digits sit on the bar's top edge
    outlinedText(text, tx, ty, ts, { 0.50, 1.00, 0.13, 1 }, { 0, 0, 0, 1 })
end

local function drawWeaponName(cx, y, ts)
    local index = gun.currentWeaponIndex
    if lastWeapon and index ~= lastWeapon then
        nameShownAt = love.timer.getTime()
    end
    lastWeapon = index

    local age = love.timer.getTime() - nameShownAt
    if age > NAME_SHOW_TIME + NAME_FADE_TIME then return end
    local alpha = math.min(1, (NAME_SHOW_TIME + NAME_FADE_TIME - age) / NAME_FADE_TIME)
    local text = WEAPON_NAMES[index] or ("Weapon " .. index)
    local tx = cx - font:getWidth(text) * ts / 2
    love.graphics.setColor(0.25, 0.25, 0.25, alpha)
    love.graphics.print(text, tx + ts, y + ts, 0, ts, ts)
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.print(text, tx, y, 0, ts, ts)
end

function hud.draw()
    local u = guiScale()
    local screenW, screenH = love.graphics.getDimensions()
    local slots = math.max(SLOTS, #gun.guns)
    local width = slots * 20 + 2
    -- Hotbar position in units, snapped to whole pixels.
    local x = math.floor((screenW / u - width) / 2)
    local y = math.floor(screenH / u) - 23
    -- One font pixel in units: the 16px font reads like Minecraft's 8-unit text.
    local ts = math.max(1, math.floor(u / 2)) / u

    local prevFont = love.graphics.getFont()
    love.graphics.setShader()
    love.graphics.setFont(font)
    love.graphics.push()
    love.graphics.origin()
    love.graphics.scale(u)

    drawHotbar(x, y, slots, ts)
    drawXP(x, y - 7, width, ts)
    drawHearts(x, y - 17)
    drawAmmo(x + width, y - 17)
    drawWeaponName(x + width / 2, y - 17 - 4 - font:getHeight() * ts, ts)

    love.graphics.pop()
    love.graphics.setFont(prevFont)
    love.graphics.setColor(1, 1, 1, 1)
end

return hud
