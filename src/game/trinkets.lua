--[[
  Trinkets: small things you wear that work on their own, each paying for
  what it does from your light (gun.ammo, the HUD's light bar, the same light
  every weapon but the fireball spends). Without the light it does nothing, and the light bar
  flashes red.

    Mirror Ward      a force field round you: an enemy's shot that reaches
                     it is turned back at them (4 light a shot)
    Ember Heart      when you're hurt, a ring of fire bursts out round you
                     (12 light, at most every 1.2 s)
    Leech Fang       a kill heals half a heart, while you're hurt (3 light)
    Lantern Moth     a moth circles you and zaps the nearest enemy in sight
                     (2 light a zap, about one a second)
    Phoenix Feather  what would kill you doesn't: you're back on three
                     hearts in a blaze, unhurt for a moment (80 light; then
                     it smoulders 90 s before it can again)
    Static Soles     each dodge roll ends in a shock round you (6 light)

  They take bag slots like everything else (game/inventory.lua), one to a
  slot, and work while they're there and equipped: picked up or bought,
  one's equipped; using it (Enter) unequips it, or equips it again, so you
  can keep one without paying for it. Shops sell them (game/shops.lua says
  which, and puts out a few you haven't got each morning); now and then an
  enemy drops one. What they do to enemies happens where the world runs
  (host, single player). The bag's save keeps what's equipped.

  var.equip_all_trinkets (conf.lua, for play-testing) puts every one in the
  bag, equipped, at every start and load.
]]
local inventory = require("game.inventory")

local trinkets = {}

local WARD_RADIUS = 52     -- px: a shot this close to you meets the Mirror Ward
local EMBER_RADIUS = 110   -- px: the Ember Heart's ring of fire...
local EMBER_EVERY = 1.2    -- s: ...at most this often
local LEECH_HEAL = 50      -- HP a kill (half a heart)
local MOTH_RANGE = 170     -- px: the moth zaps what's this near you...
local MOTH_EVERY = 0.9     -- s: ...this often
local MOTH_ORBIT = 34      -- px from you it flies
local PHOENIX_HEALTH = 300 -- HP you're back on (three hearts)
local PHOENIX_SAFE = 1.5   -- s nothing hurts you after
local PHOENIX_RADIUS = 150 -- px of blaze
local PHOENIX_REST = 90    -- s before it can again
local SOLES_RADIUS = 85    -- px: the shock at the end of a roll

-- The trinkets, in the order the shop and drops know them
trinkets.LIST = { "mirror_ward", "ember_heart", "leech_fang", "lantern_moth", "phoenix_feather", "static_soles" }

trinkets.DEFS = {
    mirror_ward = {
        name = "Mirror Ward", desc = "Turns shots back at them", cost = 4, price = 220,
        icon = {
            "................",
            "......kkkk......",
            "....kkccCCkk....",
            "...kcWccccCCk...",
            "..kcWccccccCCk..",
            "..kcWcccccccCk..",
            ".kccccckkcccCCk.",
            ".kcccckWWkccCCk.",
            ".kcccckWWkcccCk.",
            ".kccccckkccccCk.",
            "..kcccccccccCk..",
            "..kCccccccccCk..",
            "...kCCccccCCk...",
            "....kkCCCCkk....",
            "......kkkk......",
            "................",
        },
    },
    ember_heart = {
        name = "Ember Heart", desc = "Hurt, it bursts into flame", cost = 12, price = 180,
        icon = {
            "................",
            "................",
            "..kkk......kkk..",
            ".kooook..kooook.",
            "kooyyookkoooooRk",
            "koyWyooooooooRRk",
            "koyyoooooooooRRk",
            "kooooooooooooRRk",
            ".kooooooooooRRk.",
            "..kooooooooRRk..",
            "...kooooooRRk...",
            "....kooooRRk....",
            ".....kooRRk.....",
            "......kRRk......",
            ".......kk.......",
            "................",
        },
    },
    leech_fang = {
        name = "Leech Fang", desc = "Kills heal half a heart", cost = 3, price = 160,
        icon = {
            "................",
            "..kkkkkkkkkkkk..",
            "..kWWWWWWWWWWk..",
            "..kwWWWWWWWWwk..",
            "...kWWkkkkWWk...",
            "...kWWk..kWWk...",
            "...kWWk..kWWk...",
            "....kWk..kWk....",
            "....kWk..kWk....",
            "....kRk..kWk....",
            ".....k...kRk....",
            "....krk...k.....",
            "...krrrk........",
            "...kRRRk........",
            "....kkk.........",
            "................",
        },
    },
    lantern_moth = {
        name = "Lantern Moth", desc = "A moth zaps what's near", cost = 2, price = 240,
        icon = {
            "................",
            "...k........k...",
            "....k......k....",
            "..kkkk.kk.kkkk..",
            ".kppppkyykppppk.",
            "kppWPpkyykpPWppk",
            "kpPPppkyykppPPpk",
            "kppppkkyykkppppk",
            ".kpPPkkyykkPPpk.",
            "..kppkkyykkppk..",
            "...kk.kyyk.kk...",
            "......kYYk......",
            ".......kk.......",
            "................",
            "................",
            "................",
        },
    },
    phoenix_feather = {
        name = "Phoenix Feather", desc = "Cheats death, then rests", cost = 80, price = 320,
        icon = {
            "................",
            "...........kkk..",
            "..........kyyok.",
            ".........kyyook.",
            "........kyyoork.",
            ".......kyyoorRk.",
            "......kyyoorRk..",
            ".....kyyoorRk...",
            "....kyyoorRk....",
            "...kyoorRRk.....",
            "...koorRRk......",
            "..kkorRRk.......",
            ".kk.kRRk........",
            "kk...kk.........",
            "k...............",
            "................",
        },
    },
    static_soles = {
        name = "Static Soles", desc = "Dodging leaves a shock", cost = 6, price = 150,
        icon = {
            "................",
            "....kkkk....k...",
            "....kmmk...kyk..",
            "....kmmk..kyyk..",
            "....kmmk.kyyk...",
            "....kmmk.kyyyk..",
            "....kmmkk..kyk..",
            "...kmmmmmk.kk...",
            "..kmmmmmmmkk....",
            ".kmmmmmmmmmmk...",
            ".kllllllllllk...",
            ".kkkkkkkkkkkk...",
            "................",
            "................",
            "................",
            "................",
        },
    },
}

-- Each is one of the bag's items (a stack of one): using it equips or
-- unequips it, and keeps it
for _, id in ipairs(trinkets.LIST) do
    local d = trinkets.DEFS[id]
    d.id = id
    inventory.ITEMS[id] = {
        name = d.name, desc = d.desc .. " (" .. d.cost .. " light)", stack = 1, trinket = true, keep = true,
        icon = d.icon,
        use = function(slot) return trinkets.toggle(slot) end,
    }
end

local usedAt, failedAt = {}, {} -- id -> when it last paid, and last couldn't
local emberReady, phoenixReady, safeUntil = 0, 0, -math.huge
local mothAngle, mothTimer = 0, 0
local wasDodging = false
local tried = setmetatable({}, { __mode = "k" }) -- shots the ward has met (bullet -> its birth)
local effects = {} -- rings, zaps, heals and the ward's flashes, drawn in trinkets.draw

local function hosting()
    return not var.multiplayer or var.multiplayer == 1
end

local function now()
    return love.timer.getTime()
end

--- Whether `id` is at work: in the bag and equipped.
function trinkets.wears(id)
    for i = 1, inventory.SIZE do
        local s = inventory.slots[i]
        if s and s.id == id and s.on ~= false then return true end
    end
    return false
end

--- Whether you have `id` at all, equipped or not.
function trinkets.owns(id)
    return inventory.count(id) > 0
end

--- Equip or unequip the trinket in bag slot `s` (inventory.use). True, and
--- which it is now.
function trinkets.toggle(s)
    if not s then return false end
    local name = trinkets.DEFS[s.id].name
    if s.on == false then
        s.on = nil
        return true, "Equipped the " .. name
    end
    s.on = false
    return true, "Unequipped the " .. name
end

--- Play-testing (var.equip_all_trinkets): every trinket in the bag, equipped.
function trinkets.equipAll()
    for _, id in ipairs(trinkets.LIST) do
        if not trinkets.owns(id) then inventory.add(id, 1) end
    end
    for i = 1, inventory.SIZE do
        local s = inventory.slots[i]
        if s and trinkets.DEFS[s.id] then s.on = nil end
    end
end

--- A trinket you haven't got, picked with `r` (a love RandomGenerator), or nil.
function trinkets.unowned(r, except)
    local list = {}
    for _, id in ipairs(trinkets.LIST) do
        if not trinkets.owns(id) and not (except and except[id]) then list[#list + 1] = id end
    end
    if #list == 0 then return nil end
    return list[math.floor(r:random() * #list) + 1]
end

--- A shop's row selling `id` for `price` XP (game/shop.lua); `bought` is
--- told when it's sold.
function trinkets.offer(id, price, bought)
    local d = trinkets.DEFS[id]
    return { name = d.name, desc = d.desc .. ", " .. d.cost .. " light", price = price, trinket = id,
        can = function()
            if trinkets.owns(id) then return false, "You have it" end
            return inventory.room(id) > 0, "Bag is full"
        end,
        buy = function()
            inventory.add(id, 1) -- (equipped)
            if bought then bought(id) end
        end }
end

function trinkets.load()
    usedAt, failedAt, effects = {}, {}, {}
    emberReady, phoenixReady, safeUntil = 0, 0, -math.huge
    mothAngle, mothTimer, wasDodging = 0, 0, false
    if var.equip_all_trinkets then trinkets.equipAll() end
end

-- Pay `id`'s light. True when it did (and it shows on the HUD either way).
local function pay(id)
    if gun.useAmmo(trinkets.DEFS[id].cost) then
        usedAt[id] = now()
        return true
    end
    failedAt[id] = now()
    return false
end

-- A ring at (x, y), out to `radius`: every enemy inside is gone, and the
-- ring shows for a moment in `color`
local function ring(x, y, radius, color)
    if hosting() then
        for _, e in ipairs(enemy.enemies) do
            if not e.dead and e.body and not e.body:isDestroyed() then
                local ex, ey = e.body:getPosition()
                if (ex - x) ^ 2 + (ey - y) ^ 2 < radius * radius then
                    e:damageEnemy(math.huge)
                end
            end
        end
    end
    effects[#effects + 1] = { kind = "ring", x = x, y = y, r = radius, t = 0, life = 0.35, color = color }
    shadow.addTransientLight(x, y, 1.0, radius * 1.6)
end

--- player.hurt asks first: how much of `amount` you take. The Ember Heart
--- answers with fire; the Phoenix Feather with none at all, when it would
--- have killed you; nothing hurts you for a moment after.
function trinkets.onHurt(amount)
    if amount <= 0 then return amount end
    if now() < safeUntil then return 0 end
    if trinkets.wears("phoenix_feather") and player.health - amount <= 0 and now() >= phoenixReady
            and pay("phoenix_feather") then
        local px, py = player.body:getPosition()
        player.health = math.max(player.health, PHOENIX_HEALTH)
        safeUntil, phoenixReady = now() + PHOENIX_SAFE, now() + PHOENIX_REST
        effects[#effects + 1] = { kind = "pending", what = "phoenix", x = px, y = py }
        inventory.notify("The Phoenix Feather burns: you live")
        return 0
    end
    if trinkets.wears("ember_heart") and now() >= emberReady and pay("ember_heart") then
        emberReady = now() + EMBER_EVERY
        local px, py = player.body:getPosition()
        -- (out of the physics step: this can come from inside it)
        effects[#effects + 1] = { kind = "pending", what = "ember", x = px, y = py }
    end
    return amount
end

--- An enemy died at (x, y) (Enemy:damageEnemy): the Leech Fang feeds.
function trinkets.onKill(x, y)
    if not trinkets.wears("leech_fang") or not player.body then return end
    if player.health >= player.maxHealth or player.health <= 0 then return end
    if pay("leech_fang") then
        player.health = math.min(player.maxHealth, player.health + LEECH_HEAL)
        local px, py = player.body:getPosition()
        effects[#effects + 1] = { kind = "heal", x = px, y = py, sx = x, sy = y, t = 0, life = 0.5 }
    end
end

-- The Mirror Ward: shots reaching it go back the way they came, at the
-- nearest enemy if there's one ahead
local WARD_NEON = { core = { 0.85, 1.0, 1.0 }, halo = { 0.2, 0.85, 1.0 }, radius = 10 }
local function ward(px, py)
    for i = #bullet.instances, 1, -1 do
        local inst = bullet.instances[i]
        if inst.hostile and not inst.spent and tried[inst] ~= inst.birthTime then
            local x, y = inst.body:getPosition()
            local dx, dy = px - x, py - y
            local d2 = dx * dx + dy * dy
            if d2 < WARD_RADIUS * WARD_RADIUS and dx * inst.dir.x + dy * inst.dir.y > 0 then
                tried[inst] = inst.birthTime
                if pay("mirror_ward") then
                    -- back at whoever's nearest the way it came
                    local bx, by = -inst.dir.x, -inst.dir.y
                    local best, bestD = nil, 450 * 450
                    for _, e in ipairs(enemy.enemies) do
                        if not e.dead and e.body and not e.body:isDestroyed() then
                            local ex, ey = e.body:getPosition()
                            local ed2 = (ex - x) ^ 2 + (ey - y) ^ 2
                            if ed2 < bestD and (ex - x) * bx + (ey - y) * by > 0 then best, bestD = e, ed2 end
                        end
                    end
                    if best then
                        local ex, ey = best.body:getPosition()
                        local n = math.sqrt(bestD)
                        bx, by = (ex - x) / n, (ey - y) / n
                    end
                    bullet.new({ pos = vec2.new(x, y), dir = vec2.new(bx, by), speed = math.max(inst.speed, 520),
                        damage = 1, radius = 3, lifetime = 1.2, neon = WARD_NEON })
                    bullet.returnToPool(inst, i)
                    effects[#effects + 1] = { kind = "ward", a = math.atan2(y - py, x - px), t = 0, life = 0.25 }
                    audio.playSoundAt("coin", x, y, 0.15)
                end
            end
        end
    end
end

-- Where the moth is: circling you, bobbing
local function mothAt(px, py)
    return px + math.cos(mothAngle) * MOTH_ORBIT, py + math.sin(mothAngle) * MOTH_ORBIT * 0.6 - 18
end

-- The moth zaps the nearest enemy in sight within MOTH_RANGE
local function moth(px, py, dt)
    mothAngle = mothAngle + dt * 2.4
    local mx, my = mothAt(px, py)
    shadow.addTransientLight(mx, my + 18, 0.25, 60)
    mothTimer = mothTimer - dt
    if mothTimer > 0 or not hosting() then return end
    mothTimer = 0.15 -- (looks again soon when there's nothing to zap)
    local best, bestD = nil, MOTH_RANGE * MOTH_RANGE
    for _, e in ipairs(enemy.enemies) do
        if not e.dead and e.body and not e.body:isDestroyed() then
            local ex, ey = e.body:getPosition()
            local d2 = (ex - px) ^ 2 + (ey - py) ^ 2
            if d2 < bestD then best, bestD = e, d2 end
        end
    end
    if not best then return end
    local ex, ey = best.body:getPosition()
    local clear = true
    world:rayCast(px, py, ex, ey, function(f)
        if not f:isSensor() and f:getBody():getType() == "static" then
            clear = false
            return 0
        end
        return -1
    end)
    if not clear then return end
    mothTimer = MOTH_EVERY
    if pay("lantern_moth") then
        effects[#effects + 1] = { kind = "zap", x1 = mx, y1 = my, x2 = ex, y2 = ey, t = 0, life = 0.14 }
        shadow.addTransientLight(ex, ey, 0.8, 90)
        best:damageEnemy(math.huge)
    end
end

--- Every frame, before the lighting upload (main.lua, after the bag): the
--- ward meets shots, the moth flies, a roll's end shocks, the fire and blaze
--- of a moment ago go off.
function trinkets.update(dt)
    if not player.body then return end
    local px, py = player.body:getPosition()

    if trinkets.wears("mirror_ward") then ward(px, py) end
    if trinkets.wears("lantern_moth") then moth(px, py, dt) end

    local dodging = player.isDodging and true or false
    if wasDodging and not dodging and trinkets.wears("static_soles") and pay("static_soles") then
        ring(px, py, SOLES_RADIUS, { 0.55, 0.85, 1.0 })
    end
    wasDodging = dodging

    for i = #effects, 1, -1 do
        local f = effects[i]
        if f.kind == "pending" then
            table.remove(effects, i)
            if f.what == "ember" then
                ring(f.x, f.y, EMBER_RADIUS, { 1.0, 0.45, 0.08 })
            else
                ring(f.x, f.y, PHOENIX_RADIUS, { 1.0, 0.75, 0.25 })
            end
        else
            f.t = f.t + dt
            if f.t >= f.life then table.remove(effects, i) end
        end
    end
end

--- In world space after the sorted sprites (draw.lua): the ward round you,
--- the moth, rings, zaps and the heal's red thread.
function trinkets.draw()
    if not player.body then return end
    local ward = trinkets.wears("mirror_ward")
    local mothOn = trinkets.wears("lantern_moth")
    if not ward and not mothOn and #effects == 0 then return end
    local px, py = player.body:getPosition()
    local shader = love.graphics.getShader()
    local mode, alphaMode = love.graphics.getBlendMode()
    love.graphics.setShader()
    love.graphics.setBlendMode("add")
    local t = now()

    if ward then
        -- a faint hex shimmer while it has the light to answer with
        local lit = gun.ammo >= trinkets.DEFS.mirror_ward.cost
        local a = lit and (0.16 + 0.05 * math.sin(t * 3)) or 0.05
        love.graphics.setColor(0.3, 0.9, 1.0, a)
        love.graphics.setLineWidth(1.5)
        local pts = {}
        for k = 0, 6 do
            local ang = k / 6 * math.pi * 2 + t * 0.4
            pts[#pts + 1] = px + math.cos(ang) * WARD_RADIUS
            pts[#pts + 1] = py + math.sin(ang) * WARD_RADIUS * 0.8
        end
        love.graphics.line(pts)
    end

    for _, f in ipairs(effects) do
        local k = 1 - f.t / f.life
        if f.kind == "ward" then
            -- where the shot met it
            love.graphics.setColor(0.6, 1.0, 1.0, 0.9 * k)
            love.graphics.setLineWidth(3)
            love.graphics.arc("line", "open", px, py, WARD_RADIUS, f.a - 0.5, f.a + 0.5, 8)
        elseif f.kind == "ring" then
            local c = f.color
            local r = f.r * (0.35 + 0.65 * (1 - k * k))
            love.graphics.setColor(c[1], c[2], c[3], 0.25 * k)
            love.graphics.circle("fill", f.x, f.y, r)
            love.graphics.setColor(c[1], c[2], c[3], 0.9 * k)
            love.graphics.setLineWidth(4 * k + 1)
            love.graphics.circle("line", f.x, f.y, r)
        elseif f.kind == "zap" then
            love.graphics.setColor(1.0, 0.95, 0.6, k)
            love.graphics.setLineWidth(2)
            local mx, my = (f.x1 + f.x2) / 2 + (f.y2 - f.y1) * 0.1, (f.y1 + f.y2) / 2 - (f.x2 - f.x1) * 0.1
            love.graphics.line(f.x1, f.y1, mx, my, f.x2, f.y2)
        elseif f.kind == "heal" then
            love.graphics.setColor(1.0, 0.2, 0.25, 0.7 * k)
            love.graphics.setLineWidth(2)
            local e = 1 - k
            love.graphics.line(f.sx, f.sy, f.sx + (px - f.sx) * e, f.sy + (py - f.sy) * e)
            love.graphics.circle("fill", f.sx + (px - f.sx) * e, f.sy + (py - f.sy) * e, 3)
        end
    end

    if mothOn then
        -- wings and body drawn solid (outlined, so they show by day too),
        -- then its lantern's glow
        local mx, my = mothAt(px, py)
        local flap = 0.35 + 0.65 * math.abs(math.sin(t * 18))
        local lit = gun.ammo >= trinkets.DEFS.lantern_moth.cost
        love.graphics.setBlendMode("alpha")
        for side = -1, 1, 2 do
            local wx = mx + side * (2 + 3 * flap)
            love.graphics.setColor(0.08, 0.08, 0.10, 1)
            love.graphics.ellipse("fill", wx, my - 1, 4 * flap + 1.5, 4.5)
            love.graphics.setColor(lit and 0.70 or 0.42, lit and 0.56 or 0.36, lit and 0.98 or 0.55, 1)
            love.graphics.ellipse("fill", wx, my - 1, 4 * flap + 0.5, 3.5)
        end
        love.graphics.setColor(0.08, 0.08, 0.10, 1)
        love.graphics.rectangle("fill", mx - 1.5, my - 3, 3, 7)
        love.graphics.setColor(lit and 1.0 or 0.5, lit and 0.85 or 0.45, lit and 0.35 or 0.2, 1)
        love.graphics.rectangle("fill", mx - 0.5, my - 2, 1, 5)
        love.graphics.setBlendMode("add")
        love.graphics.setColor(1.0, 0.85, 0.4, lit and 0.35 or 0.06)
        love.graphics.circle("fill", mx, my, 7)
    end

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode(mode, alphaMode)
    love.graphics.setShader(shader)
end

local PER_ROW = 3 -- HUD icons in a row, rows stacking up

--- On the HUD (GUI units), right-aligned to `right`, the bottom row at `y`:
--- what's equipped, each flashing when it pays, red when it couldn't, dim
--- without the light for it; the Phoenix Feather greyed while it smoulders.
function trinkets.drawHUD(right, y)
    local t = now()
    local list = {}
    for i = 1, inventory.SIZE do
        local s = inventory.slots[i]
        if s and trinkets.DEFS[s.id] and s.on ~= false then list[#list + 1] = s.id end
    end
    for n, id in ipairs(list) do
        local col, row = (n - 1) % PER_ROW, math.floor((n - 1) / PER_ROW)
        local x, iy = right - (PER_ROW - col) * 13 + 1, y - row * 15
        local d = trinkets.DEFS[id]
        local resting = id == "phoenix_feather" and t < phoenixReady
        local lit = gun.ammo >= d.cost and not resting
        love.graphics.setColor(0.08, 0.08, 0.10, 0.7)
        love.graphics.rectangle("fill", x - 1, iy - 1, 14, 14)
        love.graphics.setColor(1, 1, 1, lit and 1 or 0.4)
        love.graphics.draw(inventory.icon(id), x, iy, 0, 0.75, 0.75)
        local used = t - (usedAt[id] or -math.huge)
        local failed = t - (failedAt[id] or -math.huge)
        if used < 0.35 then
            love.graphics.setColor(1, 1, 1, 0.6 * (1 - used / 0.35))
            love.graphics.rectangle("fill", x - 1, iy - 1, 14, 14)
        elseif failed < 0.45 then
            love.graphics.setColor(0.86, 0.14, 0.10, 0.5)
            love.graphics.rectangle("fill", x - 1, iy - 1, 14, 14)
        end
        if resting then
            -- how long it has left to smoulder, draining from the top
            local left = (phoenixReady - t) / PHOENIX_REST
            love.graphics.setColor(0, 0, 0, 0.55)
            love.graphics.rectangle("fill", x - 1, iy - 1, 14, 14 * left)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

--- The feather's rest, for a save (the bag keeps the rest).
function trinkets.getSaveData()
    return { phoenix = math.max(0, phoenixReady - now()) }
end

--- Put back what getSaveData gave (after the bag: inventory.restore).
function trinkets.restore(data)
    phoenixReady, safeUntil = 0, -math.huge
    if type(data) == "table" then
        phoenixReady = now() + (tonumber(data.phoenix) or 0)
    end
    if var.equip_all_trinkets then trinkets.equipAll() end
end

return trinkets
