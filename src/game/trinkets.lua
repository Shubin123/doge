--[[
  Trinkets: small things you wear that work on their own, each paying for
  what it does from your light (gun.ammo, the HUD's light bar, the same light
  every weapon spends). Without the light it does nothing, and the light bar
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

  You wear up to trinkets.SLOTS. One you pick up is worn if there's a free
  slot, else it goes in the bag (game/inventory.lua, where using it puts it
  on and using a worn one takes it off). The shop keeps two on its shelf,
  ones you haven't got, restocked each morning; now and then an enemy drops
  one. What they do to enemies happens where the world runs (host, single
  player). Saves keep what you wear and the shelf.
]]
local inventory = require("game.inventory")

local trinkets = {}

trinkets.SLOTS = 3
trinkets.worn = {}   -- [1..SLOTS]: id or nil
trinkets.shelf = {}  -- the shop's: ids

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
local SHELF = 2            -- trinkets on the shop's shelf

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

-- Each is one of the bag's items too (a stack of one): using it puts it on
for _, id in ipairs(trinkets.LIST) do
    local d = trinkets.DEFS[id]
    d.id = id
    inventory.ITEMS[id] = {
        name = d.name, desc = d.desc .. " (" .. d.cost .. " light)", stack = 1, trinket = true, icon = d.icon,
        use = function() return trinkets.wear(id) end,
        pickup = function() return trinkets.wear(id, true) end, -- straight on, if there's a free slot
    }
end

local usedAt, failedAt = {}, {} -- id -> when it last paid, and last couldn't
local emberReady, phoenixReady, safeUntil = 0, 0, -math.huge
local mothAngle, mothTimer = 0, 0
local wasDodging, wasOpen = false, nil
local tried = setmetatable({}, { __mode = "k" }) -- shots the ward has met (bullet -> its birth)
local effects = {} -- rings, zaps, heals and the ward's flashes, drawn in trinkets.draw
local rng

local function hosting()
    return not var.multiplayer or var.multiplayer == 1
end

local function now()
    return love.timer.getTime()
end

--- Whether you're wearing `id`.
function trinkets.wears(id)
    for i = 1, trinkets.SLOTS do
        if trinkets.worn[i] == id then return true end
    end
    return false
end

--- Whether you have `id` at all: worn or in the bag.
function trinkets.owns(id)
    return trinkets.wears(id) or inventory.count(id) > 0
end

--- Put on `id` (from the bag, or `fromGround`). True if it's on; false and
--- why not.
function trinkets.wear(id, fromGround)
    if trinkets.wears(id) then return false, "Already wearing the " .. trinkets.DEFS[id].name end
    for i = 1, trinkets.SLOTS do
        if not trinkets.worn[i] then
            trinkets.worn[i] = id
            inventory.notify("Wearing the " .. trinkets.DEFS[id].name)
            return true, "Wearing the " .. trinkets.DEFS[id].name
        end
    end
    if fromGround then return false end -- (into the bag instead)
    return false, "Trinket slots full: take one off first"
end

--- Take off the one in slot i, into the bag. True if it went.
function trinkets.unwear(i)
    local id = trinkets.worn[i]
    if not id then return false end
    if inventory.room(id) <= 0 then
        inventory.notify("Bag is full")
        return false
    end
    trinkets.worn[i] = nil
    inventory.add(id, 1)
    inventory.notify("Took off the " .. trinkets.DEFS[id].name)
    return true
end

--- Give `id` (the shop): worn if there's room, else in the bag. False when
--- neither has room.
function trinkets.give(id)
    if trinkets.wear(id, true) then return true end
    return inventory.add(id, 1) > 0
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

--- Fill the shop's shelf again (each morning) with ones you haven't got.
function trinkets.restock()
    trinkets.shelf = {}
    local taken = {}
    for _ = 1, SHELF do
        local id = trinkets.unowned(rng, taken)
        if not id then break end
        taken[id] = true
        trinkets.shelf[#trinkets.shelf + 1] = id
    end
end

--- What's on the shelf for the shop to sell (game/shop.lua's rows).
function trinkets.shopItems()
    local rows = {}
    for _, id in ipairs(trinkets.shelf) do
        local d = trinkets.DEFS[id]
        rows[#rows + 1] = { name = d.name, desc = d.desc .. ", " .. d.cost .. " light", price = d.price, trinket = id,
            can = function()
                if trinkets.owns(id) then return false, "You have it" end
                for i = 1, trinkets.SLOTS do
                    if not trinkets.worn[i] then return true end
                end
                return inventory.room(id) > 0, "Bag is full"
            end,
            buy = function()
                trinkets.give(id)
                for i, s in ipairs(trinkets.shelf) do
                    if s == id then table.remove(trinkets.shelf, i) break end
                end
            end }
    end
    return rows
end

function trinkets.load()
    rng = love.math.newRandomGenerator(love.math.random(0, 2 ^ 31 - 1))
    trinkets.worn = {}
    usedAt, failedAt, effects = {}, {}, {}
    emberReady, phoenixReady, safeUntil = 0, 0, -math.huge
    mothAngle, mothTimer, wasDodging, wasOpen = 0, 0, false, nil
    trinkets.restock()
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
--- of a moment ago go off, the shelf restocks in the morning.
function trinkets.update(dt)
    local open = daynight.isOpen()
    if wasOpen == false and open then trinkets.restock() end -- a new day's stock
    wasOpen = open
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

--- On the HUD (GUI units), right-aligned to `right` at `y`: what you wear,
--- each flashing when it pays, red when it couldn't, dim without the light
--- for it; the Phoenix Feather greyed while it smoulders.
function trinkets.drawHUD(right, y)
    local t = now()
    local n = 0
    for i = 1, trinkets.SLOTS do
        if trinkets.worn[i] then n = n + 1 end
    end
    if n == 0 then return end
    local x = right - n * 13 + 1
    for i = 1, trinkets.SLOTS do
        local id = trinkets.worn[i]
        if id then
            local d = trinkets.DEFS[id]
            local resting = id == "phoenix_feather" and t < phoenixReady
            local lit = gun.ammo >= d.cost and not resting
            love.graphics.setColor(0.08, 0.08, 0.10, 0.7)
            love.graphics.rectangle("fill", x - 1, y - 1, 14, 14)
            love.graphics.setColor(1, 1, 1, lit and 1 or 0.4)
            love.graphics.draw(inventory.icon(id), x, y, 0, 0.75, 0.75)
            local used = t - (usedAt[id] or -math.huge)
            local failed = t - (failedAt[id] or -math.huge)
            if used < 0.35 then
                love.graphics.setColor(1, 1, 1, 0.6 * (1 - used / 0.35))
                love.graphics.rectangle("fill", x - 1, y - 1, 14, 14)
            elseif failed < 0.45 then
                love.graphics.setColor(0.86, 0.14, 0.10, 0.5)
                love.graphics.rectangle("fill", x - 1, y - 1, 14, 14)
            end
            if resting then
                -- how long it has left to smoulder, draining from the top
                local k = (phoenixReady - t) / PHOENIX_REST
                love.graphics.setColor(0, 0, 0, 0.55)
                love.graphics.rectangle("fill", x - 1, y - 1, 14, 14 * k)
            end
            x = x + 13
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

--- What you wear, the shelf and the feather's rest, for a save.
function trinkets.getSaveData()
    local worn = {}
    for i = 1, trinkets.SLOTS do worn[i] = trinkets.worn[i] or false end
    return { worn = worn, shelf = trinkets.shelf, phoenix = math.max(0, phoenixReady - now()) }
end

--- Put back what getSaveData gave; nil (a save from before them) takes them all off.
function trinkets.restore(data)
    trinkets.worn = {}
    phoenixReady, safeUntil = 0, -math.huge
    if type(data) ~= "table" then
        trinkets.restock()
        return
    end
    for i = 1, trinkets.SLOTS do
        local id = data.worn and data.worn[i]
        if id and trinkets.DEFS[id] and not trinkets.wears(id) then trinkets.worn[i] = id end
    end
    trinkets.shelf = {}
    for _, id in ipairs(data.shelf or {}) do
        if trinkets.DEFS[id] and not trinkets.owns(id) then trinkets.shelf[#trinkets.shelf + 1] = id end
    end
    phoenixReady = now() + (tonumber(data.phoenix) or 0)
end

return trinkets
