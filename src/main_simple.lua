-- Simple main.lua file for DOGE Adventures
-- This replaces the broken legacy menu system

local simple_menu = require("simple_menu")

-- Game state
local game_state = "menu" -- "menu" or "playing"

function love.load()
    -- Set window title
    love.window.setTitle("Doge Adventures")
    
    -- Set window size
    love.window.setMode(1024, 768, {resizable = true})
    
    -- Initialize simple menu
    simple_menu.initialize()
    
    print("Doge Adventures loaded successfully!")
end

function love.update(dt)
    if game_state == "menu" then
        simple_menu.update(dt)
    elseif game_state == "playing" then
        -- Game update logic would go here
    end
end

function love.draw()
    if game_state == "menu" then
        simple_menu.draw()
    elseif game_state == "playing" then
        -- Game drawing logic would go here
        love.graphics.clear(0.2, 0.4, 0.2, 1)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("Game is running! Press ESC to return to menu", 100, 100)
    end
end

function love.keypressed(key)
    if game_state == "menu" then
        simple_menu.handle_key(key)
    elseif game_state == "playing" then
        if key == "escape" then
            game_state = "menu"
            simple_menu.initialize()
        end
    end
end

function love.mousepressed(x, y, button, istouch, presses)
    if game_state == "menu" then
        simple_menu.handle_mouse(x, y, button, "press")
    end
end

function love.mousemoved(x, y, dx, dy, istouch)
    if game_state == "menu" then
        simple_menu.handle_mouse(x, y, nil, "move")
    end
end

function love.resize(w, h)
    -- Handle window resize
    print("Window resized to " .. w .. "x" .. h)
end