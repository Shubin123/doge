var = {}
var.multiplayer = tonumber(arg[2])--temp logic -- set to nil for offline
-- globals
var.screen_height = 600
var.screen_width = 800
var.screen_flags = {
    ["resizable"] = true,
    ["vsync"] = true -- doesnt always work (could cause performance hit with worse fps)
}

var.character_rotation = 0
var.prev_x = 0
var.prev_y = 0
var.linear_score = 0
var.player_score = 0
var.num_coins = 100
var.coin_bods = {}
var.num_enemies = 1
var.enemies_bods = {}


var.max_grass = 20000 -- max grass blades per quadrant

var.sprite_height = 100
var.sprite_width = 100

 var.map_display_h = 256
 var.map_display_w = 256
 var.map_offset_x = 32
 var.map_offset_y = 32
--  var.tile_w = 128
--  var.tile_h = 160

 var.tile_w = 16
 var.tile_h = 16


 var.ScreenInfo = {
    screen_height = var.screen_height,
    screen_width = var.screen_width,
    screen_flags = {
        ["resizable"] = true
    }
}
 var.points = {}

 var.State = "running"

 var.game_width = 400
 var.game_height = 400
 var.header_height = 50

var.graphics_high = true -- for now just a high settings for all the shaders or nothing

var.indoors = false

function love.conf(t)
    t.window.depth = 16
-- print(t)
for key, value in pairs(t) do
    -- print(key,value)
        

end

end

return var
