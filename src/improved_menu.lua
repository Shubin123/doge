local improved_menu = {}
local settings_manager = require("settings_manager")

-- Menu state
local menu = {
    current_screen = "main",
    selected_index = 1,
    scroll_offset = 0,
    game_started = false
}

-- Menu options and data
local fidelity_options = {"low", "medium", "high", "ultra"}
local quality_options = {"low", "medium", "high", "ultra"}
local fps_options = {30, 60, 120, 144, 240, 0}

function improved_menu.initialize()
    menu.current_screen = "main"
    menu.selected_index = 1
    menu.scroll_offset = 0
    menu.game_started = false
    print("Improved menu initialized")
end

function improved_menu.update(dt)
    -- Update logic if needed
end

function improved_menu.draw()
    -- Basic draw function - this should be expanded based on the actual menu system
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    
    love.graphics.setColor(0.1, 0.1, 0.2, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("DOGE Adventures", w/2 - 100, h/2 - 50)
    love.graphics.print("Press Enter to Start", w/2 - 80, h/2)
end

function improved_menu.handle_key(key)
    if key == "return" or key == "space" then
        menu.game_started = true
    end
end

function improved_menu.handle_mouse(x, y, button, action)
    -- Basic mouse handling
    if action == "press" and button == 1 then
        menu.game_started = true
    end
end

function improved_menu.is_game_started()
    return menu.game_started
end

function improved_menu.current_screen()
    return menu.current_screen
end

function improved_menu.get_scroll_offset()
    return menu.scroll_offset
end

function improved_menu.set_scroll_offset(offset)
    menu.scroll_offset = offset
end

function improved_menu.cycle_resolution()
    -- Basic resolution cycling logic
    local resolutions = {{800, 600}, {1024, 768}, {1280, 720}, {1920, 1080}}
    local current_settings = settings_manager.get_settings()
    local current_w = current_settings.graphics.resolution_width
    local current_h = current_settings.graphics.resolution_height
    
    for i, res in ipairs(resolutions) do
        if res[1] == current_w and res[2] == current_h then
            local next_res = resolutions[(i % #resolutions) + 1]
            settings_manager.set_setting("graphics", "resolution_width", next_res[1])
            settings_manager.set_setting("graphics", "resolution_height", next_res[2])
            break
        end
    end
end

function improved_menu.draw_graphics_settings(gfx)
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local font = love.graphics.newFont(18)
    love.graphics.setFont(font)

    local start_y = 100
    local line_height = 35
    local current_y = start_y - (menu.scroll_offset or 0)
    local setting_index = 0

    -- Helper function to draw setting row
    local function draw_setting(label, value, description, is_clickable)
        setting_index = setting_index + 1
        local selected = setting_index == menu.selected_index

        if current_y > -line_height and current_y < h - 100 then
            -- Background
            if selected then
                love.graphics.setColor(0.2, 0.3, 0.6, 0.6)
                love.graphics.rectangle("fill", 50, current_y - 2, w - 100, line_height, 3)
            end

            -- Label
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(label, 70, current_y + 5)

            -- Value
            if is_clickable then
                if selected then
                    love.graphics.setColor(0.4, 1, 0.4, 1)
                else
                    love.graphics.setColor(0.3, 0.8, 0.3, 1)
                end
            else
                love.graphics.setColor(0.8, 0.8, 0.3, 1)
            end
            love.graphics.print(tostring(value), w - 200, current_y + 5)
        end

        current_y = current_y + line_height
        return setting_index
    end

    -- Display mode
    local display_text = gfx.fullscreen and "Fullscreen" or "Windowed"
    draw_setting("Display Mode", display_text, "Toggle fullscreen", true)

    -- Resolution
    local res_text = gfx.resolution_width .. "x" .. gfx.resolution_height
    draw_setting("Resolution", res_text, "Screen resolution", true)

    -- VSync
    local vsync_text = gfx.vsync and "Enabled" or "Disabled"
    draw_setting("VSync", vsync_text, "Sync with monitor", true)

    -- Max FPS
    local fps_text = gfx.max_fps == 0 and "Unlimited" or tostring(gfx.max_fps)
    draw_setting("Max FPS", fps_text, "Frame rate limit", true)

    -- Fidelity
    draw_setting("Overall Fidelity", gfx.fidelity:upper(), "Graphics quality", true)

    -- Anti-aliasing
    local aa_text = gfx.anti_aliasing and "Enabled" or "Disabled"
    draw_setting("Anti-Aliasing", aa_text, "Smooth edges", true)

    -- Ray tracing
    local rt_text = gfx.ray_tracing and "Enabled" or "Disabled"
    draw_setting("Ray Tracing", rt_text, "Advanced lighting", true)

    -- Ray marching
    local rm_text = gfx.ray_marching and "Enabled" or "Disabled"
    draw_setting("Ray Marching", rm_text, "Complex lighting", true)

    -- Particle quality
    draw_setting("Particle Quality", gfx.particle_quality:upper(), "Effects quality", true)

    -- Shadow quality
    draw_setting("Shadow Quality", gfx.shadow_quality:upper(), "Shadow detail", true)

    -- Texture quality
    draw_setting("Texture Quality", gfx.texture_quality:upper(), "Texture detail", true)

    -- Post-processing
    local pp_text = gfx.post_processing and "Enabled" or "Disabled"
    draw_setting("Post-Processing", pp_text, "Screen effects", true)

    -- Bloom
    local bloom_text = gfx.bloom and "Enabled" or "Disabled"
    draw_setting("Bloom", bloom_text, "Light bloom", true)

    -- Motion blur
    local mb_text = gfx.motion_blur and "Enabled" or "Disabled"
    draw_setting("Motion Blur", mb_text, "Movement blur", true)

    -- Depth of field
    local dof_text = gfx.depth_of_field and "Enabled" or "Disabled"
    draw_setting("Depth of Field", dof_text, "Focus blur", true)

    -- Use map shaders
    local map_shaders_text = gfx.use_map_shaders and "Enabled" or "Disabled"
    draw_setting("Enable map loading effects", map_shaders_text, "Map transition effects", true)

    -- Pixel Shader
    draw_setting(
      "Pixel Shader",
      settings_manager.get_setting("graphics","use_pixel_shader") and "Enabled" or "Disabled",
      "Toggle blocky post-process effect",
      true
    )

    menu.max_setting_index = setting_index

    -- Instructions
    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    local info_font = love.graphics.newFont(14)
    love.graphics.setFont(info_font)
    love.graphics.print("Use arrow keys or mouse to navigate - Enter/Click to change - Mouse wheel to scroll", 70, h - 90)
end

-- ... (all intervening content remains unchanged)

function improved_menu.toggle_setting()
    if menu.current_screen == "settings_graphics" then
        local settings_order = {
            "fullscreen", "resolution", "vsync", "max_fps", "fidelity",
            "anti_aliasing", "ray_tracing", "ray_marching", "particle_quality",
            "shadow_quality", "texture_quality", "post_processing", "bloom",
            "motion_blur", "depth_of_field", "use_map_shaders", "use_pixel_shader"
        }

        local setting_key = settings_order[menu.selected_index]
        if not setting_key then return end

        if setting_key == "fullscreen" or setting_key == "vsync" or
           setting_key == "anti_aliasing" or setting_key == "ray_tracing" or
           setting_key == "ray_marching" or setting_key == "post_processing" or
           setting_key == "bloom" or setting_key == "motion_blur" or
           setting_key == "depth_of_field" or setting_key == "use_map_shaders" then
            settings_manager.toggle_setting("graphics", setting_key)
            settings_manager.apply_settings()
        elseif setting_key == "use_pixel_shader" then
            settings_manager.toggle_setting("graphics", "use_pixel_shader")
            settings_manager.apply_settings()
        elseif setting_key == "fidelity" then
            settings_manager.cycle_setting("graphics", setting_key, fidelity_options)
        elseif setting_key == "particle_quality" or setting_key == "shadow_quality" or setting_key == "texture_quality" then
            settings_manager.cycle_setting("graphics", setting_key, quality_options)
        elseif setting_key == "max_fps" then
            settings_manager.cycle_setting("graphics", setting_key, fps_options)
        elseif setting_key == "resolution" then
            improved_menu.cycle_resolution()
        end
    end
end

-- ... (all remaining content remains unchanged)

return improved_menu
