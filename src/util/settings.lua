--[[
  Settings: the choices on the menu's Settings screen, kept in settings.json
  in LÖVE's save directory. settings.load puts them back at the top of
  love.load, before the window opens and anything that reads them loads;
  the Settings screen calls settings.save after every change, and quitting
  writes any made elsewhere (the "b" tracer key, the FPS keys).

  They are never part of a save. Saves (*.sav, util/serial.lua) hold the
  game's state and nothing else, loading one leaves these alone, and serial
  only ever reads, writes or deletes names ending in .sav, so it can't
  touch this file. The cache/ folder (util/cache.lua) is separate again.
]]
local settings = {}

settings.FILE = "settings.json"
settings.VERSION = 1

local function isBoolean(v) return type(v) == "boolean" end
local function isNumber(v) return type(v) == "number" and v == v end
local function isFraction(v) return isNumber(v) and v >= 0 and v <= 1 end
local function isPositive(v) return isNumber(v) and v > 0 end
local function isSize(v) return isNumber(v) and v >= 1 and v <= 16384 and v % 1 == 0 end
local function isQuality(v) return type(v) == "string" and shader.qualityPresets[v] ~= nil end
local function isWhole(v) return isNumber(v) and v >= 0 and v <= 1000 and v % 1 == 0 end
local function isLightCount(v) return isWhole(v) and v >= 1 and v <= shadow.MAX_LIGHTS end

-- What's kept: its name in the file, where the game keeps it, and what a
-- value read back must look like to be used (anything else is skipped and
-- that setting keeps its default)
local function varField(name, key, valid)
    return { name, function() return var[key] end, function(v) var[key] = v end, valid }
end
local function flagField(name, key, valid)
    return { name, function() return var.screen_flags[key] end, function(v) var.screen_flags[key] = v end, valid }
end
local FIELDS = {
    varField("window_width", "window_width", isSize), -- Resolution
    varField("window_height", "window_height", isSize),
    flagField("fullscreen", "fullscreen", isBoolean),
    flagField("vsync", "vsync", isBoolean),
    { "show_fps", function() return profiler.overlay_visible end,
        function(v) profiler.overlay_visible = v end, isBoolean },
    varField("minimap", "minimap", isBoolean),
    varField("minimap_size", "minimap_size", isWhole),
    varField("graphics_high", "graphics_high", isBoolean),
    varField("gi_quality", "gi_quality", isQuality), -- Lighting
    varField("crt_filter", "crt_filter", isBoolean),
    varField("crt_bloom", "crt_bloom", isBoolean),
    varField("grass", "grass", isBoolean),
    varField("tracer_brightness", "tracer_brightness", isFraction),
    varField("menu_particles", "menu_particles", isBoolean),
    varField("screen_shake", "screen_shake", isBoolean),
    varField("rocket_splash_radius", "rocket_splash_radius", isPositive),
    varField("fps_cap", "fps_cap", isWhole),
    varField("gui_scale", "gui_scale", isWhole),
    varField("max_lights", "max_lights", isLightCount),
    varField("light_shadows", "light_shadows", isBoolean),
    varField("normal_maps", "normal_maps", isBoolean),
    varField("puddles", "puddles", isBoolean),
    varField("lamp_glows", "lamp_glows", isBoolean),
    varField("shockwaves", "shockwaves", isBoolean),
}

-- Settings > Preset: the Graphics tab's choices together, cheapest first.
-- "high" is the defaults (conf.lua).
settings.PRESET_ORDER = { "low", "medium", "high" }
settings.PRESETS = {
    low = { graphics_high = false, gi_quality = "low", max_lights = 16, light_shadows = false,
        normal_maps = false, grass = false, puddles = false, lamp_glows = false },
    medium = { graphics_high = true, gi_quality = "medium", max_lights = 32, light_shadows = true,
        normal_maps = false, grass = true, puddles = true, lamp_glows = true },
    high = { graphics_high = true, gi_quality = "high", max_lights = 64, light_shadows = true,
        normal_maps = true, grass = true, puddles = true, lamp_glows = true },
}

--- The preset the Graphics tab matches; nil when it's been changed from one.
function settings.preset()
    for _, name in ipairs(settings.PRESET_ORDER) do
        local matches = true
        for key, value in pairs(settings.PRESETS[name]) do
            if var[key] ~= value then matches = false break end
        end
        if matches then return name end
    end
end

--- Set the Graphics tab to preset `name`.
function settings.applyPreset(name)
    local gi = var.gi_quality
    for key, value in pairs(settings.PRESETS[name]) do
        var[key] = value
    end
    if var.gi_quality ~= gi then
        shader.load() -- the preset sets the GI canvases' size and the shader's loops
    end
end

-- Each setting as settings.json last had it (the defaults without one)
local written = {}

local function remember()
    for _, field in ipairs(FIELDS) do
        written[field[1]] = field[2]()
    end
end

-- Apply settings.json's values; false without a usable file
local function apply()
    if not love.filesystem.getInfo(settings.FILE, "file") then return false end
    local contents = love.filesystem.read(settings.FILE)
    local ok, saved = pcall(json.decode, contents or "")
    if not ok or type(saved) ~= "table" then
        print("settings: ignoring unreadable " .. settings.FILE)
        return false
    end
    for _, field in ipairs(FIELDS) do
        local name, set, valid = field[1], field[3], field[4]
        if saved[name] ~= nil then
            if valid(saved[name]) then
                set(saved[name])
            else
                print("settings: ignoring " .. name .. " = " .. tostring(saved[name]))
            end
        end
    end
    -- The window opens at the chosen resolution
    var.screen_width, var.screen_height = var.window_width, var.window_height
    var.ScreenInfo.screen_width, var.ScreenInfo.screen_height = var.window_width, var.window_height
    return true
end

--- Put back what settings.json holds. A missing or unreadable file, or a
--- value that doesn't fit, leaves the defaults (config/var in conf.lua).
function settings.load()
    local loaded = apply()
    remember()
    return loaded
end

--- Write every setting to settings.json.
function settings.save()
    local out = { version = settings.VERSION }
    for _, field in ipairs(FIELDS) do
        out[field[1]] = field[2]()
    end
    local ok, err = love.filesystem.write(settings.FILE, json.encode(out))
    if ok then
        remember()
    else
        print("settings: couldn't write " .. settings.FILE .. ": " .. tostring(err))
    end
    return ok
end

--- settings.save, if any setting differs from what settings.json has.
function settings.saveIfChanged()
    for _, field in ipairs(FIELDS) do
        if field[2]() ~= written[field[1]] then
            return settings.save()
        end
    end
    return true
end

return settings
