local simple_menu = {}

-- Simple menu state
local menu = {
    current_screen = "main",
    selected_index = 1,
    mouse_x = 0,
    mouse_y = 0
}

-- Simple menu screens
local screens = {
    main = {
        title = "DOGE ADVENTURES",
        items = {
            {text = "Start Game", action = function() 
                menu.current_screen = "character_select"
                menu.selected_index = 1
            end},
            {text = "Settings", action = function() 
                menu.current_screen = "settings"
                menu.selected_index = 1
            end},
            {text = "Exit", action = function() 
                love.event.quit() 
            end}
        }
    },
    character_select = {
        title = "Choose Character",
        items = {
            {text = "Warrior", action = function() 
                simple_menu.start_game("warrior")
            end},
            {text = "Mage", action = function() 
                simple_menu.start_game("mage")
            end},
            {text = "Archer", action = function() 
                simple_menu.start_game("archer")
            end},
            {text = "Back", action = function() 
                menu.current_screen = "main"
                menu.selected_index = 1
            end}
        }
    },
    settings = {
        title = "Settings",
        items = {
            {text = "Audio Settings", action = function() end},
            {text = "Video Settings", action = function() end},
            {text = "Controls", action = function() end},
            {text = "Back", action = function() 
                menu.current_screen = "main"
                menu.selected_index = 1
            end}
        }
    }
}

function simple_menu.initialize()
    menu.current_screen = "main"
    menu.selected_index = 1
    print("Simple menu initialized")
end

function simple_menu.update(dt)
    -- Simple update logic if needed
end

function simple_menu.draw()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    
    -- Clear background
    love.graphics.clear(0.1, 0.1, 0.2, 1)
    
    local screen = screens[menu.current_screen]
    if not screen then return end
    
    -- Draw title
    love.graphics.setColor(1, 1, 1, 1)
    local title_font = love.graphics.newFont(32)
    love.graphics.setFont(title_font)
    local title_width = title_font:getWidth(screen.title)
    love.graphics.print(screen.title, w/2 - title_width/2, 100)
    
    -- Draw menu items
    local button_font = love.graphics.newFont(20)
    love.graphics.setFont(button_font)
    
    local start_y = 250
    local button_height = 50
    local button_spacing = 60
    local button_width = 300
    
    for i, item in ipairs(screen.items) do
        local x = w/2 - button_width/2
        local y = start_y + (i - 1) * button_spacing
        
        -- Check if mouse is over this button
        local mouse_over = menu.mouse_x >= x and menu.mouse_x <= x + button_width and
                          menu.mouse_y >= y and menu.mouse_y <= y + button_height
        
        -- Button background
        if i == menu.selected_index or mouse_over then
            love.graphics.setColor(0.3, 0.3, 0.6, 0.8)
        else
            love.graphics.setColor(0.2, 0.2, 0.4, 0.6)
        end
        love.graphics.rectangle("fill", x, y, button_width, button_height, 5)
        
        -- Button border
        if i == menu.selected_index then
            love.graphics.setColor(0.5, 0.7, 1, 1)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", x, y, button_width, button_height, 5)
        end
        
        -- Button text
        love.graphics.setColor(1, 1, 1, 1)
        local text_width = button_font:getWidth(item.text)
        local text_x = x + button_width/2 - text_width/2
        local text_y = y + button_height/2 - button_font:getHeight()/2
        love.graphics.print(item.text, text_x, text_y)
    end
    
    -- Instructions
    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    local info_font = love.graphics.newFont(16)
    love.graphics.setFont(info_font)
    love.graphics.print("Use arrow keys or mouse to navigate, Enter or click to select", 10, h - 30)
end

function simple_menu.handle_key(key)
    local screen = screens[menu.current_screen]
    if not screen then return end
    
    if key == "up" then
        menu.selected_index = math.max(1, menu.selected_index - 1)
    elseif key == "down" then
        menu.selected_index = math.min(#screen.items, menu.selected_index + 1)
    elseif key == "return" or key == "space" then
        local item = screen.items[menu.selected_index]
        if item and item.action then
            item.action()
        end
    elseif key == "escape" then
        if menu.current_screen == "main" then
            love.event.quit()
        else
            menu.current_screen = "main"
            menu.selected_index = 1
        end
    end
end

function simple_menu.handle_mouse(x, y, button, action)
    menu.mouse_x = x
    menu.mouse_y = y
    
    if action == "press" and button == 1 then
        local screen = screens[menu.current_screen]
        if not screen then return end
        
        local w = love.graphics.getWidth()
        local start_y = 250
        local button_height = 50
        local button_spacing = 60
        local button_width = 300
        
        for i, item in ipairs(screen.items) do
            local button_x = w/2 - button_width/2
            local button_y = start_y + (i - 1) * button_spacing
            
            if x >= button_x and x <= button_x + button_width and
               y >= button_y and y <= button_y + button_height then
                menu.selected_index = i
                if item.action then
                    item.action()
                end
                break
            end
        end
    end
end

function simple_menu.start_game(character)
    print("Starting game with character: " .. character)
    -- Initialize game state here
    -- For now, just print a message
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Game would start here with " .. character, 100, 100)
end

return simple_menu