--[[
  Armor: what you wear. Five slots (head, shoulders, chest, legs, feet), one
  piece in each, and every piece is one of a kind with its own stats. There's
  no wear and tear: a piece is as good as new for as long as you have it.

    * You start in the starter set.
    * Each region has a set of its own, a piece to a slot, lying about in it
      (armor.placeMissing): the Courtyard's round where you start, and in
      the others the feet on the portal's square, the legs halfway up the
      main avenue, the head and shoulders out along the middle street, and
      the chest at the lair, under its boss's nose. Walk over one and it
      goes in the bag.
    * The bag's panel (game/inventory.lua) shows what's worn down its left
      side. Using a piece in the bag wears it (what was in that slot goes
      back in the bag); using a worn one takes it off.
    * What's worn is drawn on the player, as 3D models of each piece (game/armorModel.lua).

  The stats (a piece's add up with the rest):

    defense   % less of every hit                     shots   % less from bullets and arrows
    hearts    HP you can hold (100 is a heart)        blows   % less from fists, slams and throws
    regen     HP back a second                        energy  % less from lasers and tesla bolts
    speed     % quicker on foot                       blast   % less from explosions
    roll      % faster and further a dodge roll goes  bites   % less from the swarm
    light     more room in the light bar              poise   % less knockback

  player.hurt asks armor.absorb what's left of a hit, by its kind. Saves keep
  what's worn (serial.lua); pieces in the bag or on the ground are the bag's.
  A piece that's nowhere (a new game, or a save from before there was armor)
  is put back where it's found. In multiplayer each player has their own, and
  only the host and single player have items on the ground to pick up.

  var.player_armor off (the GPU harness): nothing worn, nothing lying about.
]]
local inventory = require("game.inventory")
local armorModel = require("game.armorModel")

local armor = {}

armor.SLOTS = { "head", "shoulders", "chest", "legs", "feet" }
local SLOT_NAMES = { head = "Head", shoulders = "Shoulders", chest = "Chest", legs = "Legs", feet = "Feet" }

local MAX_CUT = 75    -- % at most any hit is cut by, whatever you wear
local MAX_POISE = 90  -- % at most knockback is cut by
local STREET = 860    -- px along the middle street from the lair the head and shoulders lie
-- The Courtyard's pieces: px from where a new game starts you, in the open
-- on the side away from the house
local HOME_SPOTS = { head = { -130, 10 }, shoulders = { -120, 70 }, chest = { -70, 115 },
    legs = { -10, 135 }, feet = { 50, 140 } }

-- The stats in the order they're listed, and how each reads
local function percent(label)
    return function(v) return string.format("%+d%% %s", v, label) end
end
local STATS = {
    { key = "defense", show = percent("defense") },
    { key = "hearts", show = function(v)
        local n = v / 100
        return string.format("%+g %s", n, math.abs(n) > 1 and "hearts" or "heart")
    end },
    { key = "regen", show = function(v) return string.format("%+g HP/s", v) end },
    { key = "speed", show = percent("speed") },
    { key = "roll", show = percent("roll") },
    { key = "light", show = function(v) return string.format("%+d light", v) end },
    { key = "shots", show = percent("vs shots") },
    { key = "blows", show = percent("vs blows") },
    { key = "energy", show = percent("vs energy") },
    { key = "blast", show = percent("vs blasts") },
    { key = "bites", show = percent("vs bites") },
    { key = "poise", show = percent("poise") },
}

-- What each kind of hit (player.hurt's `kind`) is resisted by
local RESIST = { shot = "shots", blow = "blows", energy = "energy", blast = "blast", bite = "bites" }

-- Icons: a shape per slot in each style, in the set's colours (a main, b
-- shade, d trim, e highlight; k the bag's outline)
local ICONS = {
    cloth = {
        head = {
            "................",
            ".....kkkkkk.....",
            "...kkaaaaaakk...",
            "..kaeeaaaaaabk..",
            "..kaeaaaaaaabk..",
            ".kaaaaaaaaaaabk.",
            ".kaaakkkkkkaabk.",
            ".kaak......kabk.",
            ".kaak......kabk.",
            ".kaaak....kaabk.",
            "..kaaakkkkaabk..",
            "..kdddddddddbk..",
            "...kbbbbbbbbk...",
            "....kkkkkkkk....",
            "................",
            "................",
        },
        shoulders = {
            "................",
            "................",
            "................",
            "......kkkk......",
            "..kkkkkddkkkkk..",
            ".kaaaakddkaaabk.",
            "kaeaaaakkaaaaabk",
            "kaeaaaabbaaaaabk",
            "kaaaaabkkbaaaabk",
            ".kaaabk..kbaabk.",
            "..kddk....kddk..",
            "...kk......kk...",
            "................",
            "................",
            "................",
            "................",
        },
        chest = {
            "................",
            "...kkk....kkk...",
            "..kaaak..kaabk..",
            ".kaeaaakkaaaabk.",
            ".kaeaaaddaaaabk.",
            ".kaaaaaddaaaabk.",
            "..kaaaaddaaabk..",
            "..kaaaaddaaabk..",
            "..kaaaaddaaabk..",
            "..kaaaaddaaabk..",
            "..kaaaaddaaabk..",
            "..kbbbbddbbbbk..",
            "..kddddddddddk..",
            "...kkkkkkkkkk...",
            "................",
            "................",
        },
        legs = {
            "................",
            "...kkkkkkkkkk...",
            "...kddddddddk...",
            "...kaaaaaaabk...",
            "...kaeaaaaabk...",
            "...kaeaakaabk...",
            "...kaaak.kabk...",
            "...kaabk.kabk...",
            "...kaabk.kabk...",
            "...kaabk.kabk...",
            "...kaabk.kabk...",
            "...kaabk.kabk...",
            "...kddbk.kddk...",
            "...kkkk...kkk...",
            "................",
            "................",
        },
        feet = {
            "................",
            "................",
            "................",
            "...kkkk..kkkk...",
            "...kaek..kaek...",
            "...kaak..kaak...",
            "...kaak..kaak...",
            "...kaak..kaak...",
            "...kaak..kaak...",
            "...kaakk.kaakk..",
            "...kaaabkkaaabk.",
            "...kaaabkkaaabk.",
            "...kddddkkddddk.",
            "...kkkkkkkkkkkk.",
            "................",
            "................",
        },
    },
    plate = {
        head = {
            "................",
            ".....kkkkkk.....",
            "....kddddddk....",
            "...kaaeeaaabk...",
            "..kaaeaaaaaabk..",
            "..kaaaaaaaaabk..",
            "..kkkkkkkkkkkk..",
            "..kdkkdkkdkkdk..",
            "..kkkkkkkkkkkk..",
            "..kaaaabbaaabk..",
            "...kaaabbaabk...",
            "....kkaaaakk....",
            "......kkkk......",
            "................",
            "................",
            "................",
        },
        shoulders = {
            "................",
            "................",
            "...kkkk..kkkk...",
            "..kaeaak.kaeabk.",
            ".kaeaaak.kaaaabk",
            ".kaaaabk.kaaaabk",
            ".kddddbk.kddddbk",
            ".kaaaabk.kaaaabk",
            "..kaaabk.kaaabk.",
            "...kbbk...kbbk..",
            "....kk.....kk...",
            "................",
            "................",
            "................",
            "................",
            "................",
        },
        chest = {
            "................",
            "..kkkk....kkkk..",
            ".kaeaak..kaaabk.",
            ".kaeaaakkaaaabk.",
            ".kaaaaeaaaaaabk.",
            ".kaaadaaaadaabk.",
            "..kaaadddddabk..",
            "..kaaaaaaaaabk..",
            "..kaaaaaaaaabk..",
            "..kaaaaaaaaabk..",
            "...kaaaaaaabk...",
            "...kbbbbbbbbk...",
            "...kddddddddk...",
            "....kkkkkkkk....",
            "................",
            "................",
        },
        legs = {
            "................",
            "...kkkkkkkkkk...",
            "...kddddddddk...",
            "...kaaaaaaabk...",
            "...kaeaaaaabk...",
            "...kaeaakaabk...",
            "...kaaak.kabk...",
            "..kddddk.kdddk..",
            "...kaebk.kaek...",
            "...kaebk.kabk...",
            "...kaabk.kabk...",
            "...kaabk.kabk...",
            "...kddbk.kddk...",
            "...kkkk...kkk...",
            "................",
            "................",
        },
        feet = {
            "................",
            "................",
            "................",
            "...kkkk..kkkk...",
            "...kaek..kaek...",
            "...kddk..kddk...",
            "...kaek..kaek...",
            "...kaak..kaak...",
            "...kaakk.kaakk..",
            "...kaeadkkaeadk.",
            "...kaaadkkaaadk.",
            "...kbbbbkkbbbbk.",
            "...kddddkkddddk.",
            "...kkkkkkkkkkkk.",
            "................",
            "................",
        },
    },
}

-- The sets. `region` is where its pieces lie (none: the starter set, worn
-- from the start); style picks the icons; gloss, how much it shines on you.
-- Each piece: { id, name, stats }.
local SETS = {
    {
        id = "starter", style = "cloth", gloss = 0,
        colors = { a = { 0.30, 0.36, 0.50 }, b = { 0.19, 0.23, 0.34 }, d = { 0.66, 0.48, 0.26 }, e = { 0.46, 0.53, 0.68 } },
        pieces = {
            head = { "patched_hood", "Patched Hood", { defense = 1, light = 5 } },
            shoulders = { "quilted_mantle", "Quilted Mantle", { defense = 1, poise = 5 } },
            chest = { "padded_vest", "Padded Vest", { defense = 2, blows = 2 } },
            legs = { "canvas_trousers", "Canvas Trousers", { defense = 1, speed = 2 } },
            feet = { "worn_boots", "Worn Boots", { speed = 3, roll = 5 } },
        },
    },
    {
        id = "courtyard", region = "home", style = "cloth", gloss = 0,
        colors = { a = { 0.38, 0.58, 0.26 }, b = { 0.22, 0.36, 0.16 }, d = { 0.72, 0.55, 0.25 }, e = { 0.60, 0.78, 0.42 } },
        pieces = {
            head = { "gardeners_sunhat", "Gardener's Sunhat", { defense = 2, light = 10 } },
            shoulders = { "ivy_shawl", "Ivy Shawl", { defense = 2, regen = 1 } },
            chest = { "bark_jerkin", "Bark Jerkin", { defense = 4, blows = 6 } },
            legs = { "mossy_breeches", "Mossy Breeches", { defense = 3, poise = 10 } },
            feet = { "garden_clogs", "Garden Clogs", { defense = 2, speed = 4 } },
        },
    },
    {
        id = "scrap", region = "wasteland", style = "plate", gloss = 0.25,
        colors = { a = { 0.52, 0.40, 0.28 }, b = { 0.32, 0.22, 0.16 }, d = { 0.85, 0.52, 0.14 }, e = { 0.72, 0.62, 0.48 } },
        pieces = {
            head = { "gas_mask", "Gas Mask", { defense = 3, bites = 25 } },
            shoulders = { "tyre_pauldrons", "Tyre Pauldrons", { defense = 4, blows = 10, poise = 25 } },
            chest = { "scrap_plate", "Scrap Plate", { defense = 8, shots = 12, speed = -4 } },
            legs = { "chain_chaps", "Chain Chaps", { defense = 5, shots = 10 } },
            feet = { "road_boots", "Road Boots", { speed = 6, blast = 12 } },
        },
    },
    {
        id = "steel", region = "castle", style = "plate", gloss = 0.7,
        colors = { a = { 0.66, 0.68, 0.74 }, b = { 0.40, 0.42, 0.48 }, d = { 0.88, 0.72, 0.30 }, e = { 0.92, 0.93, 0.97 } },
        pieces = {
            head = { "great_helm", "Great Helm", { defense = 10, speed = -2 } },
            shoulders = { "steel_pauldrons", "Steel Pauldrons", { defense = 8, poise = 35 } },
            chest = { "knights_cuirass", "Knight's Cuirass", { defense = 14, hearts = 100, speed = -6 } },
            legs = { "plate_greaves", "Plate Greaves", { defense = 10, blows = 15, speed = -4 } },
            feet = { "iron_sabatons", "Iron Sabatons", { defense = 6, blast = 20, speed = -3 } },
        },
    },
    {
        id = "synth", region = "neon", style = "cloth", gloss = 0.4,
        colors = { a = { 0.16, 0.14, 0.28 }, b = { 0.09, 0.08, 0.18 }, d = { 0.20, 0.95, 0.95 }, e = { 0.90, 0.30, 0.85 } },
        pieces = {
            head = { "holo_visor", "Holo Visor", { light = 30, energy = 15 } },
            shoulders = { "arc_epaulets", "Arc Epaulets", { energy = 20, roll = 10 } },
            chest = { "synth_jacket", "Synth Jacket", { defense = 6, speed = 8, light = 20 } },
            legs = { "flex_leggings", "Flex Leggings", { speed = 10, roll = 15 } },
            feet = { "mag_sneakers", "Mag Sneakers", { speed = 12, roll = 20, shots = 5 } },
        },
    },
    {
        id = "vestments", region = "sanctum", style = "cloth", gloss = 0.1,
        colors = { a = { 0.90, 0.86, 0.72 }, b = { 0.62, 0.56, 0.42 }, d = { 0.60, 0.40, 0.90 }, e = { 1.00, 0.97, 0.85 } },
        pieces = {
            head = { "halo_circlet", "Halo Circlet", { regen = 3, light = 25 } },
            shoulders = { "vestal_mantle", "Vestal Mantle", { hearts = 100, regen = 2 } },
            chest = { "reliquary_robe", "Reliquary Robe", { defense = 8, hearts = 200 } },
            legs = { "pilgrims_wraps", "Pilgrim's Wraps", { hearts = 100, speed = 6 } },
            feet = { "ash_sandals", "Ash Sandals", { regen = 4, speed = 8 } },
        },
    },
}

-- A piece's stats as text, in STATS order
local function describe(stats)
    local parts = {}
    for _, s in ipairs(STATS) do
        if stats[s.key] then parts[#parts + 1] = s.show(stats[s.key]) end
    end
    return table.concat(parts, ", ")
end

armor.DEFS = {}       -- id -> { id, name, slot, set, stats, region, colors, gloss }
armor.worn = {}       -- slot -> the id of what's in it
local placed = {}     -- the pieces lying about, in the regions' order
local starter = {}    -- slot -> the starter set's id
local totals = {}     -- stat -> what everything worn adds up to
local base            -- what you have with nothing on: { health, light }
local slotIcons = {}  -- slot -> an empty slot's outline (built the first time it's shown)
for _, s in ipairs(STATS) do totals[s.key] = 0 end

-- Each is one of the bag's items (a stack of one): using it wears it
for _, set in ipairs(SETS) do
    for slot, p in pairs(set.pieces) do
        local id, name, stats = p[1], p[2], p[3]
        local def = { id = id, name = name, slot = slot, set = set.id, stats = stats, region = set.region,
            colors = set.colors, gloss = set.gloss }
        armor.DEFS[id] = def
        if set.region then placed[#placed + 1] = def else starter[slot] = id end
        inventory.ITEMS[id] = {
            name = name, desc = describe(stats), stack = 1, armor = slot, keep = true,
            icon = ICONS[set.style][slot], palette = set.colors,
            use = function(s) return armor.equip(s) end,
        }
    end
end
table.sort(placed, function(a, b) return a.id < b.id end) -- (the same order every time: pairs above isn't)

-- Add up what's worn, and put it to work: hearts, light, and the look of it
local function apply()
    for _, s in ipairs(STATS) do totals[s.key] = 0 end
    for _, slot in ipairs(armor.SLOTS) do
        local def = armor.DEFS[armor.worn[slot]]
        if def then
            for k, v in pairs(def.stats) do totals[k] = totals[k] + v end
        end
    end
    -- The same share of your hearts as before, so swapping pieces can't heal you
    local max = base.health + totals.hearts
    if max ~= player.maxHealth then
        player.health = player.health * max / player.maxHealth
        player.maxHealth = max
    end
    gun.maxAmmo = base.light + totals.light
    gun.ammo = math.min(gun.ammo, gun.maxAmmo)

    local pieces = {}
    for _, slot in ipairs(armor.SLOTS) do
        pieces[#pieces + 1] = armor.DEFS[armor.worn[slot]]
    end
    armorModel.setWorn(pieces)
end

local function wearStarter()
    armor.worn = {}
    for slot, id in pairs(starter) do armor.worn[slot] = id end
end

-- Whether you have the piece, or it's lying about somewhere
local function accountedFor(def)
    if armor.worn[def.slot] == def.id or inventory.count(def.id) > 0 then return true end
    for _, g in ipairs(inventory.ground) do
        if g.id == def.id then return true end
    end
    return false
end

-- Clear ground as near as there is to (x, y)
local function clearNear(x, y)
    local function clear(cx, cy)
        local blocked = false
        world:queryBoundingBox(cx - 14, cy - 14, cx + 14, cy + 14, function(f)
            if not f:isSensor() and f:getBody():getType() == "static" then
                blocked = true
                return false
            end
            return true
        end)
        return not blocked
    end
    for ring = 0, 8 do
        local n = ring == 0 and 1 or 10
        for k = 0, n - 1 do
            local a = k / n * math.pi * 2
            local cx, cy = x + math.cos(a) * ring * 28, y + math.sin(a) * ring * 28
            if clear(cx, cy) then return cx, cy end
        end
    end
    return x, y
end

-- Where in region `r` the piece for `slot` lies
local function spotIn(r, slot)
    if r.id == "home" then
        local o = HOME_SPOTS[slot]
        return var.game_width / 2 + o[1], var.game_height / 2 + o[2]
    end
    local plaza, lair = r.plaza, r.lair
    if slot == "feet" then return plaza.x + plaza.w / 2, plaza.y + 50 end
    if slot == "legs" then return lair.x, (lair.y + plaza.y) / 2 end
    if slot == "head" then return lair.x + STREET, lair.y end
    if slot == "shoulders" then return lair.x - STREET, lair.y end
    return lair.x, lair.y + 40 -- the chest, at the lair
end

--- Every region's pieces you don't have and aren't on the ground, back where
--- they're found (host and single player: inventory.place).
function armor.placeMissing()
    if not var.player_armor then return end
    for _, r in ipairs(regions.list) do
        for _, def in ipairs(placed) do
            if def.region == r.id and not accountedFor(def) then
                local x, y = clearNear(spotIn(r, def.slot))
                inventory.place(def.id, 1, x, y)
            end
        end
    end
end

function armor.load()
    base = base or { health = player.maxHealth, light = gun.maxAmmo } -- (once: not with armor on)
    armor.worn = {}
    if var.player_armor then wearStarter() end
    apply()
    gun.ammo = gun.maxAmmo -- (a new game starts with a full bar, however long it now is)
    armor.placeMissing()
end

--- Wear the piece in bag slot `s` (inventory.use). What was in its slot goes
--- back in the bag, in its place. True, and what happened.
function armor.equip(s)
    local def = armor.DEFS[s.id]
    local old = armor.worn[def.slot]
    armor.worn[def.slot] = def.id
    if old then
        s.id = old
    else
        for i = 1, inventory.SIZE do
            if inventory.slots[i] == s then inventory.slots[i] = nil end
        end
    end
    apply()
    return true, "Wearing the " .. def.name
end

--- Take off what's in the k-th slot of armor.SLOTS, into the bag. True if it
--- came off.
function armor.takeOff(k)
    local def = armor.DEFS[armor.worn[armor.SLOTS[k]]]
    if not def then return false end
    if inventory.room(def.id) <= 0 then
        inventory.notify("Bag is full")
        return false
    end
    inventory.add(def.id, 1)
    armor.worn[def.slot] = nil
    apply()
    inventory.notify("Took off the " .. def.name)
    if player.body then
        audio.playSoundAt("coin", player.body:getX(), player.body:getY(), 0.3)
    end
    return true
end

--- The id of what's in the k-th slot of armor.SLOTS, or nil.
function armor.wornAt(k)
    return armor.worn[armor.SLOTS[k]]
end

--- A slot's name, for showing.
function armor.slotName(slot)
    return SLOT_NAMES[slot]
end

--- The outline an empty k-th slot shows.
function armor.slotIcon(k)
    local slot = armor.SLOTS[k]
    if not slotIcons[slot] then
        local grey = { 0.5, 0.5, 0.52 }
        slotIcons[slot] = inventory.makeIcon(ICONS.cloth[slot], { a = grey, b = grey, d = grey, e = grey })
    end
    return slotIcons[slot]
end

--- What everything worn adds up to, as lines of text in STATS order.
function armor.statLines()
    local lines = {}
    for _, s in ipairs(STATS) do
        if totals[s.key] ~= 0 then lines[#lines + 1] = s.show(totals[s.key]) end
    end
    return lines
end

--- What's left of `amount` HP of a hit of `kind` (player.hurt: "shot", "blow",
--- "energy", "blast", "bite", or nil for what only defense counts against).
function armor.absorb(amount, kind)
    local cut = totals.defense + (totals[RESIST[kind]] or 0)
    return amount * (1 - math.min(MAX_CUT, cut) / 100)
end

--- What knockback is multiplied by.
function armor.knockback()
    return 1 - math.min(MAX_POISE, totals.poise) / 100
end

--- What your walking speed is multiplied by.
function armor.speedScale()
    return 1 + totals.speed / 100
end

--- What a dodge roll's speed is multiplied by.
function armor.rollScale()
    return 1 + totals.roll / 100
end

--- Each frame: what mends you does.
function armor.update(dt)
    if totals.regen > 0 and player.health > 0 and player.health < player.maxHealth then
        player.health = math.min(player.maxHealth, player.health + totals.regen * dt)
    end
end

--- What's worn, for a save (the bag keeps the rest).
function armor.getSaveData()
    local worn = {}
    for slot, id in pairs(armor.worn) do worn[slot] = id end
    return { worn = worn }
end

--- Put back what getSaveData gave (after the bag: inventory.restore); nil (a
--- save from before armor) dresses you in the starter set. Pieces the game
--- no longer has are left off.
function armor.restore(data)
    armor.worn = {}
    if var.player_armor then
        if type(data) == "table" and type(data.worn) == "table" then
            for _, slot in ipairs(armor.SLOTS) do
                local def = armor.DEFS[data.worn[slot]]
                if def and def.slot == slot then armor.worn[slot] = def.id end
            end
        else
            wearStarter()
        end
    end
    apply()
    armor.placeMissing()
end

return armor
