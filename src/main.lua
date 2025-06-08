-- Enhanced main.lua file for DOGE Adventures
-- This uses the improved menu system with character management and physics-based player movement

local improved_menu = require("improved_menu")
local settings_manager = require("settings_manager")
local game_engine = require("game_engine")
local character_menu = require("character_menu")
local player_controller = require("player_controller")
local camera = require("camera")
local ui = require("ui")

-- Game state
local game_state = "menu" -- "menu", "character_menu", "loading", or "playing"
local last_frame_time = 0
local fps_timer = 0

-- Game world
local world = nil
local current_player = nil

function love.load()
    -- Set window title
    love.window.setTitle("Doge Adventures - Enhanced Edition")
    
    -- Initialize settings manager first
    settings_manager.initialize()
    
    -- Apply initial settings
    local settings = settings_manager.get_settings()
    love.window.setMode(
        settings.graphics.resolution_width, 
        settings.graphics.resolution_height, 
        {
            fullscreen = settings.graphics.fullscreen,
            vsync = settings.graphics.vsync,
            resizable = true,
            minwidth = 800,
            minheight = 600
        }
    )
    
    -- Initialize game systems
    improved_menu.initialize()
    character_menu.initialize()
    player_controller.initialize()
    
    -- Create physics world
    world = love.physics.newWorld(0, 0, true) -- No gravity for top-down game
    
    print("Doge Adventures Enhanced Edition loaded successfully!")
    print("Settings loaded and applied")
end

function love.update(dt)
    -- FPS limiting
    local settings = settings_manager.get_settings()
    if settings.graphics.max_fps > 0 then
        local target_dt = 1 / settings.graphics.max_fps
        if dt < target_dt then
            love.timer.sleep(target_dt - dt)
        end
    end
    
    if game_state == "menu" then
        improved_menu.update(dt)
        
        -- Check if we should go to character menu
        if improved_menu.is_game_started() then
            game_state = "character_menu"
            character_menu.reset()
        end
    elseif game_state == "character_menu" then
        character_menu.update(dt)
        
        -- Check if character is selected and ready to play
        if character_menu.can_start_game() then
            local selected_character = character_menu.get_selected_character()
            if selected_character then
                -- Start game with selected character (centered in expanded world)
                current_player = player_controller.create_player(world, selected_character.id, 2000, 1500)
                camera.setZoom(1.0, current_player)
                camera.setMapBounds(0, 0, 4000, 3000)
                
                game_state = "playing"
                print("Game started with character: " .. selected_character.name)
            end
        end
    elseif game_state == "playing" then
        -- Update physics world
        world:update(dt)
        
        -- Update player
        if current_player then
            player_controller.update(dt)
            
            -- Update camera to follow player
            camera.update(dt, current_player)
        end
    end
end

function love.draw()
    if game_state == "menu" then
        improved_menu.draw()
    elseif game_state == "character_menu" then
        character_menu.draw()
    elseif game_state == "playing" then
        -- Apply camera transform
        love.graphics.push()
        camera.apply()
        
        -- Draw game world (expanded background)
        love.graphics.setColor(0.1, 0.3, 0.1, 1)
        love.graphics.rectangle("fill", 0, 0, 4000, 3000)
        
        -- Draw grid for reference
        love.graphics.setColor(0.2, 0.4, 0.2, 0.5)
        for x = 0, 4000, 50 do
            love.graphics.line(x, 0, x, 3000)
        end
        for y = 0, 3000, 50 do
            love.graphics.line(0, y, 4000, y)
        end
        
        -- Draw player
        if current_player then
            player_controller.draw()
        end
        
        love.graphics.pop()
        
        -- Draw HUD health bar
        if current_player then
            local health_info = player_controller.get_health()
            ui.draw_health_bar(10, 10, 200, 20, health_info.current, health_info.max)
        end
        
        -- Draw UI elements (not affected by camera)
        love.graphics.setColor(1, 1, 1, 1)
        
        -- Draw character info
        if current_player then
            local character_data = player_controller.get_character_data()
            local health_info = player_controller.get_health()
            
            if character_data then
                love.graphics.print("Character: " .. character_data.name .. " (" .. character_data.class .. ")", 10, 10)
                love.graphics.print("Health: " .. health_info.current .. "/" .. health_info.max, 10, 30)
                
                -- Draw controls
                love.graphics.print("Controls: WASD to move, Space to dodge, ESC to return to menu", 10, love.graphics.getHeight() - 40)
                
                -- Draw position
                local px, py = player_controller.get_position()
                love.graphics.print("Position: " .. math.floor(px) .. ", " .. math.floor(py), 10, 50)
            end
        end
    end
end

function love.keypressed(key)
    if game_state == "menu" then
        improved_menu.handle_key(key)
    elseif game_state == "character_menu" then
        local handled = character_menu.keypressed(key)
        
        -- Handle escape key if character menu didn't handle it
        if not handled and key == "escape" then
            local current_screen = character_menu.get_current_screen()
            if current_screen == "character_list" then
                game_state = "menu"
            elseif current_screen == "create_character" or current_screen == "character_details" then
                character_menu.set_screen("character_list")
            end
        end
    elseif game_state == "playing" then
        if key == "escape" then
            -- Save character before returning to menu
            if current_player then
                player_controller.save_character()
            end
            game_state = "menu"
            current_player = nil
        end
    end
end

function love.mousepressed(x, y, button, istouch, presses)
    if game_state == "menu" then
        improved_menu.handle_mouse(x, y, button, "press")
    elseif game_state == "character_menu" then
        character_menu.mousepressed(x, y, button)
    end
end

function love.mousemoved(x, y, dx, dy, istouch)
    if game_state == "menu" then
        improved_menu.handle_mouse(x, y, nil, "move")
    end
    -- Mouse movement affects camera in playing state (handled by camera system)
end

function love.textinput(text)
    if game_state == "character_menu" then
        character_menu.textinput(text)
    end
end

function love.wheelmoved(x, y)
    if game_state == "menu" then
        -- Handle scrolling in settings menus
        if string.find(improved_menu.current_screen() or "", "settings_") then
            local scroll_amount = y * 90 -- 2 lines per scroll
            local current_offset = improved_menu.get_scroll_offset()
            improved_menu.set_scroll_offset(math.max(0, current_offset - scroll_amount))
        end
    end
end

function love.resize(w, h)
    -- Update settings when window is resized (if not in fullscreen)
    local settings = settings_manager.get_settings()
    if not settings.graphics.fullscreen then
        settings_manager.set_setting("graphics", "resolution_width", w)
        settings_manager.set_setting("graphics", "resolution_height", h)
        settings_manager.save_settings()
    end
    print("Window resized to " .. w .. "x" .. h)
end

function love.quit()
    -- Save settings before quitting
    settings_manager.save_settings()
    print("Settings saved. Goodbye!")
    return false -- Allow quit
end

-- Error handling
function love.errorhandler(msg)
    print("Error occurred: " .. msg)
    print("Attempting to save settings before crash...")
    
    -- Try to save settings even if there's an error
    pcall(function()
        settings_manager.save_settings()
    end)
    
    -- Return default error handler
    return function()
        local trace = debug.traceback()
        local message = "Error: " .. msg .. "\n\n" .. trace
        
        love.graphics.clear(0.1, 0.1, 0.2, 1)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(message, 20, 20)
        love.graphics.present()
        
        if love.keyboard.isDown("escape") then
            return
        end
    end
end
