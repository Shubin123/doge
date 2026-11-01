var = {}
var.multiplayer = tonumber(arg[2])--temp logic -- set to nil for offline
-- globals
var.screen_width = 800
var.screen_height = 600
var.screen_flags = {
    ["resizable"] = true,
    ["vsync"] = true -- doesnt always work (could cause performance hit with worse fps)
}

var.character_rotation = 0
var.prev_x = 0
var.prev_y = 0
var.linear_score = 0
var.player_score = 0
var.num_coins = 1000
var.coin_bods = {}
-- Active AI enemies. Each is a dynamic physics body + behaviour tree updated
-- every frame, so this is the single biggest CPU knob. 80 is a smooth default;
-- raise for bigger battles if your machine has headroom (increase to 500/1000
-- to stress-test with the profiler/benchmark framework -- see src/systems/profiler.lua).
var.num_enemies = 80
-- Other players' sprites in multiplayer (character instances after the
-- enemies'); more players than this connect fine but aren't drawn
var.max_remote_players = 4
var.num_instances = var.num_enemies + 1 + var.max_remote_players

-- Global illumination quality preset: "high" | "medium" | "low" (see shader.lua).
-- "high" matches the original look; drop to "medium"/"low" on weaker GPUs.
var.gi_quality = "high"

-- Brightness of the neon bullet tracers and tesla bolts and their glow, 0..1
-- (0 hides them). Cycled with "b" for testing; meant to follow the player's
-- light level.
var.tracer_brightness = 1.0

-- How far a rocket blast reaches, in world px from the impact to an enemy's
-- edge. Cycled in Settings > Rocket Splash.
var.rocket_splash_radius = 120

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

-- Settings > CRT Filter / Bloom: the CRT pass over the finished frame
-- (systems/crt.lua) and its bloom. Fancy graphics only.
var.crt_filter = true
var.crt_bloom = true

-- Settings > Grass: draw (and sway) the grass fields
var.grass = true

-- Settings > Screen Shake: camera.shake does nothing while off
var.screen_shake = true

var.indoors = false

-- Day and night (systems/daynight.lua): seconds of game time a whole day
-- takes, and the hour a new game starts at
var.day_length = 480
var.day_start = 8

function love.conf(t)
    -- Save directory name. Without it LOVE names the folder after however the
    -- game was launched (source folder, .love file, fused executable), so saves
    -- from one build wouldn't show up in another.
    t.identity = "doge"
    t.window.depth = 16
    -- t.window.fsaa = 20           
-- print(t)
for key, value in pairs(t) do
    -- print(key,value)
        

end

end

return var
