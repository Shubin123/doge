-- GPU regression harness: conf.lua for the assembled test game directory.
-- tests/gpu/run.py copies the game's own src/conf.lua next to this file as
-- __game_conf.lua; load it unchanged (it defines the global `var` and
-- love.conf), then pin the few window settings that would otherwise make
-- frames or timings depend on the machine.
require("__game_conf")

local gameConf = love.conf
function love.conf(t)
    if gameConf then gameConf(t) end
    t.identity = "doge-gpu-harness"
    t.window.vsync = 0        -- timings must measure work, not the display refresh
    t.window.resizable = false
    t.window.highdpi = false  -- 1 framebuffer pixel per point on every display
end
