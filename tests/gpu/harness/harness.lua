--[[
  Deterministic frame driver for the GPU regression suite.

  Replaces love.run. Everything that would make two runs of the same tree
  differ is pinned: the RNG seeds, the clock (love.timer.getTime returns
  simulated time), dt (fixed), the mouse and keyboard (stubbed to a fixed
  aim, nothing pressed) and window events (ignored, except quit).

  Configured through environment variables (set by tests/gpu/run.py):
    DOGE_GPU_OUT          absolute directory for frames + results.json (required)
    DOGE_GPU_W/H          window size (default 800x600, the game's own default)
    DOGE_GPU_SEED         RNG seed (default 1337)
    DOGE_GPU_PERF_FRAMES  timed frames at the end; 0 skips timing (default 120)
    DOGE_GPU_LABEL        free-form label copied into results.json
    DOGE_GPU_SCENARIO     absolute path of a script to run instead of scenarios.lua

  Writes, into DOGE_GPU_OUT:
    <capture>.rgba   raw RGBA8 framebuffer (what run.py diffs)
    <capture>.png    the same frame, for humans
    results.json     per-capture stats, perf summary, renderer info, errors
]]

local H = {}

-- Unbuffered, so a run killed by run.py's timeout still leaves its log.
io.stdout:setvbuf("no")

local realTime = love.timer.getTime

local function env(name, default)
    local v = os.getenv(name)
    if v == nil or v == "" then return default end
    return v
end

local cfg = {
    out        = env("DOGE_GPU_OUT"),
    width      = tonumber(env("DOGE_GPU_W", "800")),
    height     = tonumber(env("DOGE_GPU_H", "600")),
    seed       = tonumber(env("DOGE_GPU_SEED", "1337")),
    perfFrames = tonumber(env("DOGE_GPU_PERF_FRAMES", "120")),
    label      = env("DOGE_GPU_LABEL", "run"),
}
H.cfg = cfg
H.dt = 1 / 60
H.simTime = 0
H.frame = 0

local results = {
    label = cfg.label,
    ok = false,
    captures = {},
    order = {},
    log = {},
}

--------------------------------------------------------------------------------
-- Minimal JSON encoder (no dependency on the game tree under test).
--------------------------------------------------------------------------------
local encode
local function encodeString(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
        return map[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end
encode = function(v)
    local t = type(v)
    if t == "nil" then return "null" end
    if t == "boolean" then return tostring(v) end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
        return string.format("%.6g", v)
    end
    if t == "string" then return encodeString(v) end
    if t == "table" then
        if #v > 0 or next(v) == nil then
            local parts = {}
            for i = 1, #v do parts[i] = encode(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        local parts = {}
        for _, k in ipairs(keys) do parts[#parts + 1] = encodeString(k) .. ":" .. encode(v[k]) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return encodeString(tostring(v))
end

local function writeFile(path, data)
    local f = assert(io.open(path, "wb"))
    f:write(data)
    f:close()
end

local function log(msg)
    results.log[#results.log + 1] = msg
    print("[gpu-harness] " .. msg)
end
H.log = log

--------------------------------------------------------------------------------
-- Pinning nondeterminism
--------------------------------------------------------------------------------
local function pinInputs()
    love.timer.getTime = function() return H.simTime end

    -- Aim right of and slightly above centre; never pressed.
    local function aim() return cfg.width / 2 + 120, cfg.height / 2 - 40 end
    love.mouse.getPosition = aim
    love.mouse.getX = function() return (aim()) end
    love.mouse.getY = function() local _, y = aim() return y end
    love.mouse.isDown = function() return false end
    love.keyboard.isDown = function() return false end
    love.keyboard.isScancodeDown = function() return false end
end

-- Pinned the moment the harness is required, i.e. before the game's main
-- chunk runs: some modules draw random numbers at require time (the grass
-- texture, for one), so seeding in love.load would be too late.
math.randomseed(cfg.seed)
love.math.setRandomSeed(cfg.seed)
pinInputs()

local function pumpEvents()
    love.event.pump()
    for name in love.event.poll() do
        if name == "quit" then error("harness window was closed", 0) end
        -- Everything else (focus, resize, real input) is dropped on purpose.
    end
end

--------------------------------------------------------------------------------
-- GPU synchronisation: queue a pass after everything love.draw() submitted and
-- read one pixel of it back. glReadPixels cannot return until the GPU has
-- executed all prior work, so wall time up to here covers the whole frame.
--------------------------------------------------------------------------------
local syncCanvas
local function gpuSync()
    syncCanvas = syncCanvas or love.graphics.newCanvas(1, 1)
    love.graphics.push("all")
    love.graphics.setCanvas(syncCanvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 1, 1)
    love.graphics.pop()
    syncCanvas:newImageData()
end

local function copyStats(s)
    return {
        drawcalls = s.drawcalls,
        drawcallsbatched = s.drawcallsbatched,
        canvasswitches = s.canvasswitches,
        shaderswitches = s.shaderswitches,
        texturememory = s.texturememory,
        canvases = s.canvases,
        images = s.images,
    }
end

--------------------------------------------------------------------------------
-- Render-pass trace. While installed, every render-target change is recorded
-- with the code that made it and the draw calls that landed on the previous
-- target: the frame's pass list (which passes run, at what size, from where).
--------------------------------------------------------------------------------
local Trace = {}
Trace.__index = Trace

function Trace.begin()
    local self = setmetatable({ passes = {}, orig = love.graphics.setCanvas }, Trace)
    local w, h = love.graphics.getPixelDimensions()
    self.current = { target = "screen", w = w, h = h, from = "frame start" }
    self.lastDraws = love.graphics.getStats().drawcalls
    love.graphics.setCanvas = function(c, ...)
        self:close()
        local info = debug.getinfo(2, "Sl")
        local target, cw, ch = "screen", love.graphics.getPixelDimensions()
        if type(c) == "userdata" then
            target = c:getFormat()
            cw, ch = c:getPixelDimensions()
        elseif type(c) == "table" then
            target = "multiple"
        end
        self.current = { target = target, w = cw, h = ch,
                         from = info and (info.short_src .. ":" .. info.currentline) or "?" }
        return self.orig(c, ...)
    end
    return self
end

function Trace:close()
    local draws = love.graphics.getStats().drawcalls
    self.current.draws = draws - self.lastDraws
    self.lastDraws = draws
    if self.current.draws > 0 then self.passes[#self.passes + 1] = self.current end
end

--- Uninstall (must run before present(), which resets the draw counter).
function Trace:finish()
    self:close()
    love.graphics.setCanvas = self.orig
    local pixels = 0
    for _, p in ipairs(self.passes) do pixels = pixels + p.w * p.h end
    return { passes = self.passes, pass_count = #self.passes, pass_pixels = pixels }
end

--------------------------------------------------------------------------------
-- One frame, exactly like LÖVE 11's default love.run but with a fixed dt.
--------------------------------------------------------------------------------
local pendingCapture
local function step(opts)
    opts = opts or {}
    pumpEvents()
    H.frame = H.frame + 1
    H.simTime = H.simTime + H.dt

    local t0 = realTime()
    love.update(H.dt)
    local t1 = realTime()

    love.graphics.origin()
    love.graphics.clear(love.graphics.getBackgroundColor())
    local trace = opts.trace and Trace.begin()
    local ok, err = xpcall(love.draw, debug.traceback)
    local traced = trace and trace:finish()
    if not ok then error(err, 0) end
    local stats = copyStats(love.graphics.getStats())

    local t2
    if opts.timed then
        gpuSync()
        t2 = realTime()
    end

    if opts.capture then
        local name = opts.capture
        pendingCapture = name
        love.graphics.captureScreenshot(function(img)
            local w, h = img:getDimensions()
            writeFile(cfg.out .. "/" .. name .. ".rgba", img:getString())
            writeFile(cfg.out .. "/" .. name .. ".png", img:encode("png"):getString())
            results.captures[name].width = w
            results.captures[name].height = h
            pendingCapture = nil
        end)
        results.captures[name] = { frame = H.frame, stats = stats, trace = traced }
        results.order[#results.order + 1] = name
    end

    love.graphics.present()
    assert(pendingCapture == nil, "screenshot callback did not run at present()")
    return stats, t1 - t0, t2 and (t2 - t1)
end

--------------------------------------------------------------------------------
-- Scenario API (used by scenarios.lua)
--------------------------------------------------------------------------------
function H.advance(n)
    for _ = 1, n do step() end
end

--- Record a functional check (scripts in tests/gpu/checks/, run.py --checks).
function H.check(name, ok, detail)
    results.checks = results.checks or {}
    results.checks[#results.checks + 1] = { name = name, ok = ok and true or false, detail = detail }
    log(string.format("check %-44s %s%s", name, ok and "ok" or "FAILED", detail and ("  " .. detail) or ""))
end

--- Render one frame, save it for comparison, and record its pass trace.
function H.capture(name)
    assert(not results.captures[name], "duplicate capture name: " .. name)
    step({ capture = name, trace = true })
end

local function median(t)
    local c = {}
    for i = 1, #t do c[i] = t[i] end
    table.sort(c)
    if #c == 0 then return 0 end
    local m = math.floor((#c + 1) / 2)
    if #c % 2 == 1 then return c[m] end
    return (c[m] + c[m + 1]) / 2
end

local function percentile(t, p)
    local c = {}
    for i = 1, #t do c[i] = t[i] end
    table.sort(c)
    if #c == 0 then return 0 end
    return c[math.max(1, math.min(#c, math.ceil(#c * p)))]
end

--- Timed frames: update time is CPU only; render time is love.draw() plus the
--- wait for the GPU to finish the frame (see gpuSync).
function H.perf(n)
    if n <= 0 then return end
    -- A few untimed frames so shader compilation / first-use costs are excluded.
    for _ = 1, 10 do step({ timed = true }) end
    local render, update = {}, {}
    local sums = {}
    for i = 1, n do
        local stats, u, r = step({ timed = true })
        update[i], render[i] = u * 1000, r * 1000
        for k, v in pairs(stats) do sums[k] = (sums[k] or 0) + v end
    end
    local avg = {}
    for k, v in pairs(sums) do avg[k] = v / n end

    -- Frame cost under load: frames back to back, with one wait for the GPU
    -- at the end of each batch, so it stays busy at its working clock. The
    -- per-frame timing above leaves the GPU idle between frames, and Apple
    -- GPUs then clock down: less GPU work can come back later (taking the
    -- death light's eight passes out of an unchanged tree read ~20% slower
    -- there). This is the frame's GPU cost, or its CPU cost if that's more.
    local batch, frame = math.max(1, math.floor(n / 10)), {}
    for i = 1, 10 do
        local t0 = realTime()
        for _ = 1, batch do step() end
        gpuSync()
        frame[i] = (realTime() - t0) / batch * 1000
    end

    results.perf = {
        frames = n,
        render_ms_median = median(render),
        render_ms_p90 = percentile(render, 0.9),
        update_ms_median = median(update),
        frame_ms_median = median(frame),
        stats_avg = avg,
    }
    log(string.format("perf: render %.3f ms median (p90 %.3f), update %.3f ms, %d frames; under load %.3f ms a frame",
        results.perf.render_ms_median, results.perf.render_ms_p90, results.perf.update_ms_median, n,
        results.perf.frame_ms_median))
end

--------------------------------------------------------------------------------
-- love.run replacement
--------------------------------------------------------------------------------
local function main()
    assert(cfg.out, "DOGE_GPU_OUT must be set (run tests/gpu/run.py)")

    -- The game's love.load opens the window from these.
    var.screen_width, var.screen_height = cfg.width, cfg.height
    var.ScreenInfo.screen_width, var.ScreenInfo.screen_height = cfg.width, cfg.height
    var.screen_flags = { resizable = false, vsync = 0, highdpi = false }

    local t0 = realTime()
    love.load(love.arg.parseGameArguments(arg), arg)
    results.load_s = realTime() - t0
    -- And again for the play-through, so it doesn't depend on how many
    -- random numbers loading drew: that changes with what came out of the
    -- load-time cache (util/cache.lua) rather than being worked out.
    math.randomseed(cfg.seed)
    love.math.setRandomSeed(cfg.seed)
    if love.audio then love.audio.setVolume(0) end

    local name, version, vendor, device = love.graphics.getRendererInfo()
    results.renderer = { name = name, version = version, vendor = vendor, device = device }
    results.window = { love.graphics.getPixelDimensions() }

    -- DOGE_GPU_SCENARIO=/abs/path.lua swaps in another script (same shape as
    -- scenarios.lua), e.g. to render a one-off scene while working on a look.
    local custom = os.getenv("DOGE_GPU_SCENARIO")
    local scenarios = custom and assert(loadfile(custom))() or require("__gpu_harness.scenarios")
    scenarios(H)

    H.perf(cfg.perfFrames)
    results.ok = true
end

local function finish(ok, err)
    if not ok then
        results.ok = false
        results.error = tostring(err)
        print("[gpu-harness] FAILED: " .. tostring(err))
    end
    if cfg.out then
        writeFile(cfg.out .. "/results.json", encode(results))
    end
    local code = ok and 0 or 3
    return function() return code end
end

function H.run()
    return finish(xpcall(main, debug.traceback))
end

-- LOVE's default handler shows an error screen and waits for a human; record
-- the error and exit instead, so a broken tree fails fast rather than hanging.
function H.errorhandler(msg)
    return finish(false, debug.traceback(tostring(msg), 2))
end

return H
