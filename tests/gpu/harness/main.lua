-- GPU regression harness entry point (see tests/gpu/README.md).
-- tests/gpu/run.py assembles a game directory where this file stands in for
-- src/main.lua, the real one is __game_main.lua and this folder is
-- __gpu_harness/. The game loads exactly as it normally would; only love.run
-- is replaced, by a fixed-timestep driver that captures frames and GPU stats.
local harness = require("__gpu_harness.harness")
love.errorhandler = harness.errorhandler

assert(love.filesystem.load("__game_main.lua"))()

love.run = harness.run
love.errorhandler = harness.errorhandler
love.errhand = nil
