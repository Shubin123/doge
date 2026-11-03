--[[
  Every shop in the game, as data. game/shop.lua reads this at load and
  checks it: a typo stops the game with the shop and the field it's in.
  To add a shop, copy one and change it; to change what one sells, edit its
  `stock`. Shops are listed in no particular order.

    id       a name of its own (saves keep its shelf by it)
    name     at the top of its panel, and over its stall
    region   where it is: "home", "wasteland", "castle", "neon" or "sanctum"
    at       where in the region:
               "house"   the house on the home map (home only): inside it,
                         where nothing can hurt you
               "plaza"   the square round the portal
               "square"  the market square, across from the pool, its
                         centrepiece in the middle (the Wasteland has none:
                         a stall there goes on the plaza instead)
    offset   { x, y }: px from the middle of `at` (y down). If something
             stands there, the stall goes to the nearest clear ground.
    hours    { open, close } on the 24 h clock, e.g. { 7, 19 }; a close
             before the open runs past midnight ({ 18, 6 } is a night
             market); or "always". Closed, the keeper sleeps.
    stall    { colour, colour }: its awning's stripes (not for the house)
    keeper   the keeper's colours, any of: hair, shirt, apron, skin
    stock    what it sells, in order (keys 1-9 buy at once; nine at most,
             the shelf included):
               { item = "<id>", price = <XP> }      into the bag:
                   bandage, medkit, light_cell,
                   apple, bread, drumstick, glowberries, chili, noodles,
                   honey_cake
               { trinket = "<id>", price = <XP> }   into the bag, equipped:
                   mirror_ward, ember_heart, leech_fang, lantern_moth,
                   phoenix_feather, static_soles
               { fireballs = <n>, price = <XP> }    onto the hotbar
    shelf    how many trinkets you haven't got it puts out besides, new
             each morning (left out: none)
    shelfPrice  what a shelf trinket costs here, as a share of its usual
             price (left out: 1)

  Colours are { r, g, b }, each 0 to 1. Item and trinket ids are the keys of
  inventory.ITEMS (game/inventory.lua) and trinkets.DEFS (game/trinkets.lua).
]]

local RED, CREAM = { 0.78, 0.16, 0.12 }, { 0.95, 0.90, 0.78 }

return {
    -- The house on the home map
    {
        id = "home", name = "Shop", region = "home", at = "house", hours = { 7, 19 },
        stock = {
            { item = "bandage", price = 40 },
            { item = "medkit", price = 120 },
            { item = "light_cell", price = 50 },
            { item = "apple", price = 15 },
            { item = "bread", price = 30 },
            { item = "glowberries", price = 35 },
            { fireballs = 3, price = 45 },
        },
        shelf = 2,
    },

    -- Wasteland: scavengers
    {
        id = "wasteland_scrap", name = "Scrap Market", region = "wasteland", at = "plaza", offset = { 170, 60 },
        hours = { 6, 20 },
        stall = { { 0.55, 0.40, 0.22 }, { 0.32, 0.30, 0.26 } },
        keeper = { hair = { 0.20, 0.18, 0.16 }, shirt = { 0.45, 0.42, 0.30 }, apron = { 0.52, 0.44, 0.32 } },
        stock = {
            { item = "bandage", price = 35 },
            { item = "light_cell", price = 45 },
            { item = "chili", price = 30 },
            { trinket = "static_soles", price = 140 },
            { trinket = "leech_fang", price = 150 },
        },
        shelf = 1, shelfPrice = 0.9,
    },
    {
        id = "wasteland_grill", name = "Roadside Grill", region = "wasteland", at = "plaza", offset = { -170, 60 },
        hours = { 10, 23 },
        stall = { RED, { 0.20, 0.20, 0.22 } },
        keeper = { hair = { 0.62, 0.30, 0.12 }, shirt = { 0.70, 0.20, 0.14 } },
        stock = {
            { item = "drumstick", price = 40 },
            { item = "bread", price = 25 },
            { item = "apple", price = 12 },
            { item = "chili", price = 25 },
        },
    },

    -- Castle: the larder and the armoury
    {
        id = "castle_larder", name = "Castle Larder", region = "castle", at = "square", offset = { -110, -40 },
        hours = { 6, 18 },
        stall = { { 0.25, 0.35, 0.70 }, CREAM },
        keeper = { hair = { 0.85, 0.75, 0.45 }, shirt = { 0.25, 0.35, 0.70 } },
        stock = {
            { item = "bread", price = 20 },
            { item = "honey_cake", price = 55 },
            { item = "drumstick", price = 45 },
            { item = "apple", price = 10 },
            { item = "medkit", price = 110 },
        },
    },
    {
        id = "castle_armoury", name = "Armourer", region = "castle", at = "plaza", offset = { 170, 60 },
        hours = { 8, 20 },
        stall = { { 0.45, 0.10, 0.12 }, { 0.80, 0.65, 0.25 } },
        keeper = { hair = { 0.30, 0.30, 0.32 }, shirt = { 0.40, 0.42, 0.48 }, apron = { 0.32, 0.22, 0.14 } },
        stock = {
            { trinket = "ember_heart", price = 170 },
            { trinket = "phoenix_feather", price = 300 },
            { trinket = "mirror_ward", price = 230 },
            { item = "bandage", price = 40 },
        },
        shelf = 1,
    },

    -- Neon City: never closes
    {
        id = "neon_market", name = "Night Market", region = "neon", at = "square", offset = { -110, -40 },
        hours = "always",
        stall = { { 0.95, 0.20, 0.65 }, { 0.15, 0.85, 0.95 } },
        keeper = { hair = { 0.85, 0.25, 0.75 }, shirt = { 0.12, 0.12, 0.16 }, apron = { 0.20, 0.75, 0.85 } },
        stock = {
            { item = "glowberries", price = 30 },
            { item = "light_cell", price = 40 },
            { trinket = "mirror_ward", price = 200 },
            { trinket = "lantern_moth", price = 220 },
            { trinket = "static_soles", price = 150 },
        },
        shelf = 2, shelfPrice = 1.1,
    },
    {
        id = "neon_noodles", name = "Noodle Bar", region = "neon", at = "plaza", offset = { -170, 60 },
        hours = { 18, 6 },
        stall = { { 0.90, 0.75, 0.15 }, { 0.75, 0.12, 0.12 } },
        keeper = { hair = { 0.10, 0.10, 0.12 }, shirt = { 0.85, 0.85, 0.80 }, apron = { 0.75, 0.12, 0.12 } },
        stock = {
            { item = "noodles", price = 35 },
            { item = "chili", price = 30 },
            { item = "glowberries", price = 30 },
            { item = "drumstick", price = 50 },
        },
    },

    -- Sanctum: relics, and bread for pilgrims
    {
        id = "sanctum_reliquary", name = "Reliquary", region = "sanctum", at = "square", offset = { -110, -40 },
        hours = { 0, 24 },
        stall = { { 0.55, 0.35, 0.85 }, { 0.95, 0.85, 0.50 } },
        keeper = { hair = { 0.92, 0.92, 0.95 }, shirt = { 0.55, 0.35, 0.85 }, apron = { 0.95, 0.85, 0.50 } },
        stock = {
            { trinket = "phoenix_feather", price = 280 },
            { trinket = "leech_fang", price = 140 },
            { trinket = "lantern_moth", price = 230 },
            { item = "medkit", price = 100 },
        },
        shelf = 1, shelfPrice = 0.85,
    },
    {
        id = "sanctum_rest", name = "Pilgrims' Rest", region = "sanctum", at = "plaza", offset = { 170, 60 },
        hours = { 5, 21 },
        stall = { CREAM, { 0.35, 0.55, 0.35 } },
        keeper = { hair = { 0.55, 0.40, 0.25 }, shirt = { 0.35, 0.55, 0.35 } },
        stock = {
            { item = "apple", price = 12 },
            { item = "bread", price = 22 },
            { item = "honey_cake", price = 50 },
            { item = "glowberries", price = 30 },
            { item = "bandage", price = 35 },
        },
    },
}
