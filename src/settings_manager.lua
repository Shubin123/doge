local settings_manager = {}

-- Default settings
local default_settings = {
    graphics = {
        fullscreen = false,
        resolution_width = 1024,
        resolution_height = 768,
        vsync = true,
        max_fps = 60,
        fidelity = "medium", -- "low", "medium", "high", "ultra"
        anti_aliasing = false,
        ray_tracing = false,
        ray_marching = false,
        particle_quality = "medium",
        shadow_quality = "medium",
        texture_quality = "high",
        post_processing = true,
        bloom = true,
        motion_blur = false,
        depth_of_field = false,
        use_map_shaders = true,
        use_pixel_shader = false
    },
    audio = {
        master_volume = 0.8,
        music_volume = 0.7,
        sfx_volume = 0.9,
        muted = false
    },
    controls = {
        mouse_sensitivity = 1.0,
        keyboard_layout = "qwerty",
        invert_mouse = false
    },
    memory = {
        texture_cache_size = 256, -- MB
        auto_optimize = true,
        preload_assets = true,
        garbage_collection = "auto" -- "auto", "manual", "aggressive"
    }
}

local current_settings = {}
local settings_file = "doge_settings.json"

-- Initialize settings system
function settings_manager.initialize()
    settings_manager.load_settings()
    settings_manager.apply_settings()
    print("Settings manager initialized")
end

-- Deep copy function
local function deep_copy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deep_copy(orig_key)] = deep_copy(orig_value)
        end
        setmetatable(copy, deep_copy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- Load settings from file
function settings_manager.load_settings()
    current_settings = deep_copy(default_settings)
    
    if love.filesystem.getInfo(settings_file) then
        local success, contents = pcall(love.filesystem.read, settings_file)
        if success then
            local success_decode, data = pcall(function()
                -- Simple JSON-like parsing for Lua tables
                return loadstring("return " .. contents)()
            end)
            
            if success_decode and type(data) == "table" then
                -- Merge loaded settings with defaults
                for category, settings in pairs(data) do
                    if current_settings[category] then
                        for key, value in pairs(settings) do
                            if current_settings[category][key] ~= nil then
                                current_settings[category][key] = value
                            end
                        end
                    end
                end
                print("Settings loaded successfully")
            else
                print("Failed to parse settings file, using defaults")
            end
        else
            print("Failed to read settings file, using defaults")
        end
    else
        print("No settings file found, using defaults")
    end
end

-- Save settings to file
function settings_manager.save_settings()
    local function serialize_table(t, indent)
        indent = indent or 0
        local spacing = string.rep("  ", indent)
        local result = "{\n"
        
        for k, v in pairs(t) do
            local key = type(k) == "string" and string.format('"%s"', k) or tostring(k)
            result = result .. spacing .. "  " .. key .. " = "
            
            if type(v) == "table" then
                result = result .. serialize_table(v, indent + 1)
            elseif type(v) == "string" then
                result = result .. string.format('"%s"', v)
            else
                result = result .. tostring(v)
            end
            result = result .. ",\n"
        end
        
        result = result .. spacing .. "}"
        return result
    end
    
    local serialized = serialize_table(current_settings)
    local success = pcall(love.filesystem.write, settings_file, serialized)
    
    if success then
        print("Settings saved successfully")
    else
        print("Failed to save settings")
    end
end

-- Apply current settings to the engine
function settings_manager.apply_settings()
    local gfx = current_settings.graphics
    
    -- Apply graphics settings
    if gfx.fullscreen ~= love.window.getFullscreen() then
        love.window.setFullscreen(gfx.fullscreen)
    end
    
    local current_width, current_height = love.graphics.getDimensions()
    if gfx.resolution_width ~= current_width or gfx.resolution_height ~= current_height then
        love.window.setMode(gfx.resolution_width, gfx.resolution_height, {
            fullscreen = gfx.fullscreen,
            vsync = gfx.vsync,
            resizable = true
        })
    end
    
    -- Apply FPS limit (Love2D doesn't have built-in FPS limiting, so we'll track this)
    settings_manager.target_fps = gfx.max_fps
    
    -- Apply pixel shader setting
    if shader then
        shader.setPixelEnabled(gfx.use_pixel_shader)
    end
    
    print("Settings applied to engine")
end

-- Get current settings
function settings_manager.get_settings()
    return current_settings
end

-- Get specific setting
function settings_manager.get_setting(category, key)
    if current_settings[category] and current_settings[category][key] ~= nil then
        return current_settings[category][key]
    end
    return nil
end

-- Set specific setting
function settings_manager.set_setting(category, key, value)
    if current_settings[category] then
        current_settings[category][key] = value
        print("Setting updated: " .. category .. "." .. key .. " = " .. tostring(value))
    end
end

-- Toggle boolean setting
function settings_manager.toggle_setting(category, key)
    local current = settings_manager.get_setting(category, key)
    if type(current) == "boolean" then
        settings_manager.set_setting(category, key, not current)
        return not current
    end
    return current
end

-- Cycle through enum values
function settings_manager.cycle_setting(category, key, values)
    local current = settings_manager.get_setting(category, key)
    local current_index = 1
    
    for i, value in ipairs(values) do
        if value == current then
            current_index = i
            break
        end
    end
    
    local next_index = (current_index % #values) + 1
    local next_value = values[next_index]
    settings_manager.set_setting(category, key, next_value)
    return next_value
end

-- Get available resolutions
function settings_manager.get_available_resolutions()
    local modes = love.window.getFullscreenModes()
    local resolutions = {}
    
    -- Add some common resolutions
    local common = {
        {1024, 768}, {1280, 720}, {1366, 768}, {1600, 900},
        {1920, 1080}, {2560, 1440}, {3840, 2160}
    }
    
    for _, res in ipairs(common) do
        table.insert(resolutions, {width = res[1], height = res[2]})
    end
    
    -- Add system resolutions
    for _, mode in ipairs(modes) do
        local found = false
        for _, existing in ipairs(resolutions) do
            if existing.width == mode.width and existing.height == mode.height then
                found = true
                break
            end
        end
        if not found then
            table.insert(resolutions, {width = mode.width, height = mode.height})
        end
    end
    
    return resolutions
end

-- Reset to defaults
function settings_manager.reset_to_defaults()
    current_settings = deep_copy(default_settings)
    settings_manager.apply_settings()
    settings_manager.save_settings()
    print("Settings reset to defaults")
end

-- Get performance impact description
function settings_manager.get_performance_impact(category, key)
    local impacts = {
        ray_tracing = "Very High - May significantly reduce FPS",
        ray_marching = "High - Complex lighting calculations",
        anti_aliasing = "Medium - Smooths edges but costs GPU performance",
        particle_quality = "Medium - Affects visual effects complexity",
        shadow_quality = "Medium - Higher quality shadows cost more",
        texture_quality = "Low-Medium - Affects VRAM usage",
        post_processing = "Medium - Screen effects processing",
        bloom = "Low - Subtle lighting effect",
        motion_blur = "Low-Medium - Movement blur effect",
        depth_of_field = "Low-Medium - Focus blur effect"
    }
    
    return impacts[key] or "Minimal impact"
end

return settings_manager

