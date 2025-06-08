local character_menu = {}
local character_save_system = require("character_save_system")

-- Menu state
local menu_state = {
    current_screen = "character_list", -- character_list, create_character, character_details
    selected_index = 1,
    characters = {},
    selected_character = nil,
    character_ready_to_play = false,
    
    -- Character creation
    new_character_name = "",
    new_character_class = "warrior",
    class_index = 1,
    
    -- Input handling
    text_input_active = false,
    confirmation_dialog = nil -- {type, message, character_id}
}

local character_classes = {
    {id = "warrior", name = "Warrior", description = "Strong melee fighter with high defense"},
    {id = "mage", name = "Mage", description = "Master of magical arts with powerful spells"},
    {id = "archer", name = "Archer", description = "Swift ranged combatant with precision"},
    {id = "rogue", name = "Rogue", description = "Sneaky assassin with critical strikes"}
}

-- Initialize character menu
function character_menu.initialize()
    character_save_system.initialize()
    
    -- Test the save system
    local test_passed = character_save_system.test_save_system()
    if not test_passed then
        print("WARNING: Save system test failed - characters may not persist!")
    end
    
    character_menu.refresh_character_list()
    print("Character menu initialized")
end

-- Refresh the character list from saved files
function character_menu.refresh_character_list()
    print("DEBUG: Refreshing character list...")
    menu_state.characters = character_save_system.get_all_characters()
    print("DEBUG: Refreshed list contains " .. #menu_state.characters .. " characters")
    menu_state.selected_index = math.max(1, math.min(menu_state.selected_index, #menu_state.characters + 1))
end

-- Get current screen
function character_menu.get_current_screen()
    return menu_state.current_screen
end

-- Set screen
function character_menu.set_screen(screen)
    menu_state.current_screen = screen
    menu_state.selected_index = 1
    
    if screen == "character_list" then
        character_menu.refresh_character_list()
    elseif screen == "create_character" then
        -- Reset create character form
        menu_state.new_character_name = ""
        menu_state.new_character_class = "warrior"
        menu_state.class_index = 1
        menu_state.text_input_active = false
        print("DEBUG: Reset create character form")
    end
end

-- Update menu
function character_menu.update(dt)
    -- Nothing special needed for now
end

-- Draw the menu
function character_menu.draw()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    
    -- Draw background
    love.graphics.clear(0.1, 0.1, 0.2, 1)
    
    if menu_state.current_screen == "character_list" then
        character_menu.draw_character_list()
    elseif menu_state.current_screen == "create_character" then
        character_menu.draw_create_character()
    elseif menu_state.current_screen == "character_details" then
        character_menu.draw_character_details()
    end
    
    -- Draw confirmation dialog if active
    if menu_state.confirmation_dialog then
        character_menu.draw_confirmation_dialog()
    end
end

-- Draw character list screen
function character_menu.draw_character_list()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local font_title = love.graphics.newFont(32)
    local font_text = love.graphics.newFont(18)
    local font_small = love.graphics.newFont(14)
    
    -- Title
    love.graphics.setFont(font_title)
    love.graphics.setColor(1, 1, 1, 1)
    local title = "Character Management"
    local title_width = font_title:getWidth(title)
    love.graphics.print(title, w/2 - title_width/2, 50)
    
    -- Instructions
    love.graphics.setFont(font_small)
    love.graphics.setColor(0.8, 0.8, 0.8, 1)
    local instructions = "Select a character to play, create new, or manage existing characters"
    local inst_width = font_small:getWidth(instructions)
    love.graphics.print(instructions, w/2 - inst_width/2, 90)
    
    -- Character list
    love.graphics.setFont(font_text)
    local start_y = 140
    local item_height = 80
    local card_width = math.min(600, w - 100)
    local card_x = w/2 - card_width/2
    
    -- Show helpful message if no characters exist
    if #menu_state.characters == 0 then
        love.graphics.setColor(0.8, 0.8, 0.8, 1)
        local no_chars_text = "No characters found. Create your first character below!"
        local text_width = font_text:getWidth(no_chars_text)
        love.graphics.print(no_chars_text, w/2 - text_width/2, start_y + 50)
    end
    
    -- Draw character cards
    for i, character in ipairs(menu_state.characters) do
        local y = start_y + (i - 1) * item_height
        local selected = (i == menu_state.selected_index)
        
        -- Character card background
        if selected then
            love.graphics.setColor(0.3, 0.5, 0.8, 0.8)
        else
            love.graphics.setColor(0.2, 0.2, 0.4, 0.8)
        end
        love.graphics.rectangle("fill", card_x, y, card_width, item_height - 10, 8)
        
        -- Character info
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(character.name, card_x + 20, y + 10)
        
        love.graphics.setColor(0.8, 0.8, 0.8, 1)
        love.graphics.print("Class: " .. character.class:gsub("^%l", string.upper), card_x + 20, y + 35)
        love.graphics.print("Level: " .. character.level, card_x + 200, y + 35)
        
        local display_info = character_save_system.get_character_display_info(character)
        if display_info then
            love.graphics.print("Playtime: " .. display_info.playtime, card_x + 300, y + 35)
            love.graphics.print("Last played: " .. display_info.last_played, card_x + 20, y + 55)
            
            -- Health bar
            local health_percent = display_info.health_percent / 100
            local bar_width = 100
            local bar_height = 8
            local bar_x = card_x + card_width - bar_width - 20
            local bar_y = y + 20
            
            love.graphics.setColor(0.3, 0.3, 0.3, 1)
            love.graphics.rectangle("fill", bar_x, bar_y, bar_width, bar_height)
            love.graphics.setColor(1 - health_percent, health_percent, 0, 1)
            love.graphics.rectangle("fill", bar_x, bar_y, bar_width * health_percent, bar_height)
        end
        
        -- Selection indicator
        if selected then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", card_x, y, card_width, item_height - 10, 8)
        end
    end
    
    -- Create new character option
    local create_y = start_y + #menu_state.characters * item_height
    local create_selected = (menu_state.selected_index == #menu_state.characters + 1)
    
    if create_selected then
        love.graphics.setColor(0.3, 0.8, 0.3, 0.8)
    else
        love.graphics.setColor(0.2, 0.4, 0.2, 0.8)
    end
    love.graphics.rectangle("fill", card_x, create_y, card_width, item_height - 10, 8)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(font_text)
    local create_text = "+ Create New Character"
    local create_width = font_text:getWidth(create_text)
    love.graphics.print(create_text, card_x + card_width/2 - create_width/2, create_y + item_height/2 - 10)
    
    if create_selected then
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", card_x, create_y, card_width, item_height - 10, 8)
    end
    
    -- Controls
    love.graphics.setFont(font_small)
    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    local controls = "Click character to view details - Delete key: Remove Character - Escape: Back to Main Menu"
    love.graphics.print(controls, 20, h - 40)
end

-- Draw create character screen
function character_menu.draw_create_character()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local font_title = love.graphics.newFont(28)
    local font_text = love.graphics.newFont(18)
    local font_small = love.graphics.newFont(14)
    
    -- Title
    love.graphics.setFont(font_title)
    love.graphics.setColor(1, 1, 1, 1)
    local title = "Create New Character"
    local title_width = font_title:getWidth(title)
    love.graphics.print(title, w/2 - title_width/2, 50)
    
    -- Character name input
    love.graphics.setFont(font_text)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Character Name:", 100, 120)
    
    -- Name input box
    menu_state.name_box = {x = 100, y = 150, width = 300, height = 30}
    local name_box = menu_state.name_box
    
    if menu_state.text_input_active then
        love.graphics.setColor(0.4, 0.6, 0.8, 0.8)
    else
        love.graphics.setColor(0.3, 0.3, 0.3, 0.8)
    end
    love.graphics.rectangle("fill", name_box.x, name_box.y, name_box.width, name_box.height)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("line", name_box.x, name_box.y, name_box.width, name_box.height)
    
    -- Name text
    local display_name = menu_state.new_character_name
    if menu_state.text_input_active and math.floor(love.timer.getTime() * 2) % 2 == 0 then
        display_name = display_name .. "|"
    end
    love.graphics.print(display_name, name_box.x + 10, name_box.y + 5)
    
    -- Class selection
    love.graphics.print("Character Class:", 100, 220)
    
    local class_start_y = 250
    local class_height = 100
    menu_state.class_cards = {}
    
    for i, class_info in ipairs(character_classes) do
        local y = class_start_y + (i - 1) * class_height
        local selected = (i == menu_state.class_index)
        
        -- Store class card bounds for mouse detection
        menu_state.class_cards[i] = {x = 100, y = y, width = 500, height = class_height - 10}
        
        -- Class card
        if selected then
            love.graphics.setColor(0.3, 0.5, 0.8, 0.8)
        else
            love.graphics.setColor(0.2, 0.2, 0.4, 0.8)
        end
        love.graphics.rectangle("fill", 100, y, 500, class_height - 10, 8)
        
        -- Class info
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(class_info.name, 120, y + 10)
        
        love.graphics.setFont(font_small)
        love.graphics.setColor(0.8, 0.8, 0.8, 1)
        love.graphics.printf(class_info.description, 120, y + 35, 460, "left")
        
        -- Show stats without creating temp character (use hardcoded values for performance)
        local stats_text = ""
        if class_info.id == "warrior" then
            stats_text = "HP: 120 | STR: 15 | INT: 10 | AGI: 10"
        elseif class_info.id == "mage" then
            stats_text = "HP: 80 | STR: 10 | INT: 15 | AGI: 10"
        elseif class_info.id == "archer" then
            stats_text = "HP: 90 | STR: 12 | INT: 10 | AGI: 15"
        elseif class_info.id == "rogue" then
            stats_text = "HP: 85 | STR: 12 | INT: 8 | AGI: 12"
        end
        love.graphics.print(stats_text, 120, y + 65)
        
        love.graphics.setFont(font_text)
        
        if selected then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", 100, y, 500, class_height - 10, 8)
        end
    end
    
    -- Create button
    local create_button_y = class_start_y + #character_classes * class_height + 20
    local can_create = string.len(menu_state.new_character_name) > 0
    menu_state.create_button = {x = 100, y = create_button_y, width = 200, height = 40}
    
    if can_create then
        love.graphics.setColor(0.3, 0.8, 0.3, 0.8)
    else
        love.graphics.setColor(0.3, 0.3, 0.3, 0.5)
    end
    love.graphics.rectangle("fill", menu_state.create_button.x, menu_state.create_button.y, 
                           menu_state.create_button.width, menu_state.create_button.height, 8)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Create Character", menu_state.create_button.x + 20, menu_state.create_button.y + 10)
    
    -- Back button
    local back_button_y = create_button_y
    menu_state.back_button = {x = menu_state.create_button.x + menu_state.create_button.width + 20, y = back_button_y, width = 100, height = 40}
    
    love.graphics.setColor(0.6, 0.2, 0.2, 0.8)
    love.graphics.rectangle("fill", menu_state.back_button.x, menu_state.back_button.y, 
                           menu_state.back_button.width, menu_state.back_button.height, 8)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("[BACK]", menu_state.back_button.x + 15, menu_state.back_button.y + 10)
    
    -- Controls
    love.graphics.setFont(font_small)
    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    local controls = "Click name box to edit - Click class to select - Click Create Character button - Click Back to see existing characters"
    love.graphics.print(controls, 20, h - 40)
end

-- Draw character details screen  
function character_menu.draw_character_details()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    
    if not menu_state.selected_character then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("No character selected", w/2 - 100, h/2)
        return
    end
    
    local character = menu_state.selected_character
    local font_title = love.graphics.newFont(28)
    local font_text = love.graphics.newFont(18)
    local font_small = love.graphics.newFont(14)
    
    -- Title
    love.graphics.setFont(font_title)
    love.graphics.setColor(1, 1, 1, 1)
    local title = character.name .. " - Details"
    local title_width = font_title:getWidth(title)
    love.graphics.print(title, w/2 - title_width/2, 50)
    
    -- Character stats
    love.graphics.setFont(font_text)
    local info_x, info_y = 100, 120
    local line_height = 25
    
    love.graphics.print("Class: " .. character.class:gsub("^%l", string.upper), info_x, info_y)
    love.graphics.print("Level: " .. character.level, info_x, info_y + line_height)
    love.graphics.print("Experience: " .. character.experience, info_x, info_y + line_height * 2)
    
    -- Stats
    love.graphics.print("Health: " .. character.stats.health .. "/" .. character.stats.max_health, info_x, info_y + line_height * 4)
    love.graphics.print("Mana: " .. character.stats.mana .. "/" .. character.stats.max_mana, info_x, info_y + line_height * 5)
    love.graphics.print("Strength: " .. character.stats.strength, info_x, info_y + line_height * 6)
    love.graphics.print("Intelligence: " .. character.stats.intelligence, info_x, info_y + line_height * 7)
    love.graphics.print("Agility: " .. character.stats.agility, info_x, info_y + line_height * 8)
    love.graphics.print("Defense: " .. character.stats.defense, info_x, info_y + line_height * 9)
    
    -- Playtime info
    local display_info = character_save_system.get_character_display_info(character)
    if display_info then
        love.graphics.print("Playtime: " .. display_info.playtime, info_x + 300, info_y)
        love.graphics.print("Last played: " .. display_info.last_played, info_x + 300, info_y + line_height)
        love.graphics.print("Current map: " .. display_info.map_name, info_x + 300, info_y + line_height * 2)
    end
    
    -- Action buttons
    local button_y = info_y + line_height * 11
    local button_width = 150
    local button_height = 40
    
    -- Play button
    love.graphics.setColor(0.3, 0.8, 0.3, 0.8)
    love.graphics.rectangle("fill", info_x, button_y, button_width, button_height, 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Play Character", info_x + 10, button_y + 10)
    
    -- Delete button
    love.graphics.setColor(0.8, 0.3, 0.3, 0.8)
    love.graphics.rectangle("fill", info_x + button_width + 20, button_y, button_width, button_height, 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Delete Character", info_x + button_width + 30, button_y + 10)
    
    -- Back button
    local back_x = info_x + (button_width + 20) * 2
    love.graphics.setColor(0.3, 0.3, 0.6, 0.8)
    love.graphics.rectangle("fill", back_x, button_y, 100, button_height, 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("[BACK]", back_x + 15, button_y + 10)
    
    -- Store back button bounds for click detection
    menu_state.details_back_button = {x = back_x, y = button_y, width = 100, height = button_height}
    
    -- Controls
    love.graphics.setFont(font_small)
    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    local controls = "Click Play Character to start - Click Delete to remove - Click Back to return to character list"
    love.graphics.print(controls, 20, h - 40)
end

-- Draw confirmation dialog
function character_menu.draw_confirmation_dialog()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local dialog_width, dialog_height = 400, 200
    local dialog_x = w/2 - dialog_width/2
    local dialog_y = h/2 - dialog_height/2
    
    -- Background overlay
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, w, h)
    
    -- Dialog box
    love.graphics.setColor(0.2, 0.2, 0.3, 0.95)
    love.graphics.rectangle("fill", dialog_x, dialog_y, dialog_width, dialog_height, 10)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("line", dialog_x, dialog_y, dialog_width, dialog_height, 10)
    
    -- Dialog text
    local font_text = love.graphics.newFont(18)
    love.graphics.setFont(font_text)
    love.graphics.setColor(1, 1, 1, 1)
    
    local message = menu_state.confirmation_dialog.message
    love.graphics.printf(message, dialog_x + 20, dialog_y + 40, dialog_width - 40, "center")
    
    -- Buttons
    local button_width = 100
    local button_height = 35
    local button_y = dialog_y + dialog_height - 60
    local yes_button_x = dialog_x + dialog_width/2 - button_width - 10
    local no_button_x = dialog_x + dialog_width/2 + 10
    
    -- Yes button
    love.graphics.setColor(0.8, 0.3, 0.3, 0.8)
    love.graphics.rectangle("fill", yes_button_x, button_y, button_width, button_height, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Yes", yes_button_x + 35, button_y + 8)
    
    -- No button
    love.graphics.setColor(0.3, 0.6, 0.3, 0.8)
    love.graphics.rectangle("fill", no_button_x, button_y, button_width, button_height, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("No", no_button_x + 40, button_y + 8)
    
    -- Instructions
    local font_small = love.graphics.newFont(14)
    love.graphics.setFont(font_small)
    love.graphics.setColor(0.8, 0.8, 0.8, 1)
    love.graphics.print("Y: Yes  N: No  Escape: Cancel", dialog_x + 20, dialog_y + dialog_height - 20)
end

-- Handle keyboard input
function character_menu.keypressed(key)
    -- Handle confirmation dialog
    if menu_state.confirmation_dialog then
        if key == "y" then
            character_menu.handle_confirmation(true)
        elseif key == "n" or key == "escape" then
            character_menu.handle_confirmation(false)
        end
        return true -- Key was handled
    end
    
    -- Handle main menu navigation
    local handled = false
    if menu_state.current_screen == "character_list" then
        handled = character_menu.handle_character_list_input(key)
    elseif menu_state.current_screen == "create_character" then
        handled = character_menu.handle_create_character_input(key)
    elseif menu_state.current_screen == "character_details" then
        handled = character_menu.handle_character_details_input(key)
    end
    
    return handled -- Return whether the key was handled
end

-- Handle character list input
function character_menu.handle_character_list_input(key)
    local max_index = #menu_state.characters + 1 -- +1 for create new option
    
    if key == "up" then
        menu_state.selected_index = math.max(1, menu_state.selected_index - 1)
        return true
    elseif key == "down" then
        menu_state.selected_index = math.min(max_index, menu_state.selected_index + 1)
        return true
    elseif key == "return" then
        if menu_state.selected_index <= #menu_state.characters then
            -- Select existing character
            menu_state.selected_character = menu_state.characters[menu_state.selected_index]
            menu_state.current_screen = "character_details"
        else
            -- Create new character
            menu_state.current_screen = "create_character"
        end
        return true
    elseif key == "delete" then
        if menu_state.selected_index <= #menu_state.characters then
            local character = menu_state.characters[menu_state.selected_index]
            menu_state.confirmation_dialog = {
                type = "delete",
                message = "Are you sure you want to delete character '" .. character.name .. "'?\nThis action cannot be undone.",
                character_id = character.id
            }
        end
        return true
    elseif key == "escape" then
        -- Let main.lua handle escape to return to main menu
        return false
    end
    
    return false -- Key not handled
end

-- Handle create character input
function character_menu.handle_create_character_input(key)
    if key == "escape" then
        menu_state.current_screen = "character_list"
        menu_state.text_input_active = false
        return true
    elseif key == "tab" then
        menu_state.text_input_active = not menu_state.text_input_active
        return true
    elseif key == "up" and not menu_state.text_input_active then
        menu_state.class_index = math.max(1, menu_state.class_index - 1)
        menu_state.new_character_class = character_classes[menu_state.class_index].id
        return true
    elseif key == "down" and not menu_state.text_input_active then
        menu_state.class_index = math.min(#character_classes, menu_state.class_index + 1)
        menu_state.new_character_class = character_classes[menu_state.class_index].id
        return true
    elseif key == "return" then
        if string.len(menu_state.new_character_name) > 0 then
            character_menu.create_character()
        end
        return true
    elseif key == "backspace" and menu_state.text_input_active then
        menu_state.new_character_name = string.sub(menu_state.new_character_name, 1, -2)
        return true
    end
    
    return false -- Key not handled
end

-- Handle character details input
function character_menu.handle_character_details_input(key)
    if key == "escape" then
        menu_state.current_screen = "character_list"
        return true
    elseif key == "return" then
        -- This character is selected for play
        menu_state.character_ready_to_play = true
        return true
    end
    
    return false -- Key not handled
end

-- Handle mouse input
function character_menu.mousepressed(x, y, button)
    if button ~= 1 then return end -- Only handle left click
    
    if menu_state.confirmation_dialog then
        -- Handle confirmation dialog clicks
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()
        local dialog_width, dialog_height = 400, 200
        local dialog_x = w/2 - dialog_width/2
        local dialog_y = h/2 - dialog_height/2
        
        local button_width = 100
        local button_height = 35
        local button_y = dialog_y + dialog_height - 60
        local yes_button_x = dialog_x + dialog_width/2 - button_width - 10
        local no_button_x = dialog_x + dialog_width/2 + 10
        
        if x >= yes_button_x and x <= yes_button_x + button_width and
           y >= button_y and y <= button_y + button_height then
            character_menu.handle_confirmation(true)
        elseif x >= no_button_x and x <= no_button_x + button_width and
               y >= button_y and y <= button_y + button_height then
            character_menu.handle_confirmation(false)
        end
        return
    end
    
    if menu_state.current_screen == "character_list" then
        character_menu.handle_character_list_mouse(x, y)
    elseif menu_state.current_screen == "create_character" then
        character_menu.handle_create_character_mouse(x, y)
    elseif menu_state.current_screen == "character_details" then
        character_menu.handle_character_details_mouse(x, y)
    end
end

-- Handle mouse for character list
function character_menu.handle_character_list_mouse(x, y)
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local start_y = 140
    local item_height = 80
    local card_width = math.min(600, w - 100)
    local card_x = w/2 - card_width/2
    
    -- Check character cards
    for i, character in ipairs(menu_state.characters) do
        local card_y = start_y + (i - 1) * item_height
        
        if x >= card_x and x <= card_x + card_width and
           y >= card_y and y <= card_y + item_height - 10 then
            menu_state.selected_index = i
            menu_state.selected_character = character
            menu_state.current_screen = "character_details"
            return
        end
    end
    
    -- Check create new character option
    local create_y = start_y + #menu_state.characters * item_height
    if x >= card_x and x <= card_x + card_width and
       y >= create_y and y <= create_y + item_height - 10 then
        character_menu.set_screen("create_character")
    end
end

-- Handle mouse for create character screen
function character_menu.handle_create_character_mouse(x, y)
    print("DEBUG: Mouse click in create character at " .. x .. "," .. y)
    
    -- Check name input box
    if menu_state.name_box then
        local name_box = menu_state.name_box
        if x >= name_box.x and x <= name_box.x + name_box.width and
           y >= name_box.y and y <= name_box.y + name_box.height then
            print("DEBUG: Clicked name input box")
            menu_state.text_input_active = true
            return
        else
            if menu_state.text_input_active then
                print("DEBUG: Clicked outside name input box")
            end
            menu_state.text_input_active = false
        end
    end
    
    -- Check class cards
    if menu_state.class_cards then
        for i, card in ipairs(menu_state.class_cards) do
            if x >= card.x and x <= card.x + card.width and
               y >= card.y and y <= card.y + card.height then
                print("DEBUG: Clicked class card " .. i .. " (" .. character_classes[i].id .. ")")
                menu_state.class_index = i
                menu_state.new_character_class = character_classes[i].id
                return
            end
        end
    end
    
    -- Check create button
    if menu_state.create_button then
        local btn = menu_state.create_button
        if x >= btn.x and x <= btn.x + btn.width and
           y >= btn.y and y <= btn.y + btn.height then
            print("DEBUG: Clicked create button")
            if string.len(menu_state.new_character_name) > 0 then
                character_menu.create_character()
            else
                print("DEBUG: Cannot create character - no name entered")
            end
            return
        end
    end
    
    -- Check back button
    if menu_state.back_button then
        local btn = menu_state.back_button
        if x >= btn.x and x <= btn.x + btn.width and
           y >= btn.y and y <= btn.y + btn.height then
            print("DEBUG: Clicked back button")
            character_menu.set_screen("character_list")
            return
        end
    end
end

-- Handle mouse for character details screen
function character_menu.handle_character_details_mouse(x, y)
    if not menu_state.selected_character then return end
    
    local info_x, info_y = 100, 120
    local line_height = 25
    local button_y = info_y + line_height * 11
    local button_width = 150
    local button_height = 40
    
    -- Play button
    if x >= info_x and x <= info_x + button_width and
       y >= button_y and y <= button_y + button_height then
        menu_state.character_ready_to_play = true
        return
    end
    
    -- Delete button
    local delete_x = info_x + button_width + 20
    if x >= delete_x and x <= delete_x + button_width and
       y >= button_y and y <= button_y + button_height then
        local character = menu_state.selected_character
        menu_state.confirmation_dialog = {
            type = "delete",
            message = "Are you sure you want to delete character '" .. character.name .. "'?\nThis action cannot be undone.",
            character_id = character.id
        }
        return
    end
    
    -- Back button
    if menu_state.details_back_button then
        local btn = menu_state.details_back_button
        if x >= btn.x and x <= btn.x + btn.width and
           y >= btn.y and y <= btn.y + btn.height then
            print("DEBUG: Clicked back button in character details")
            character_menu.set_screen("character_list")
            return
        end
    end
end

-- Handle text input for character name
function character_menu.textinput(text)
    if menu_state.current_screen == "create_character" and menu_state.text_input_active then
        if string.len(menu_state.new_character_name) < 20 then -- Limit name length
            menu_state.new_character_name = menu_state.new_character_name .. text
        end
    end
end

-- Create new character
function character_menu.create_character()
    print("DEBUG: Creating character with name='" .. (menu_state.new_character_name or "nil") .. "' class='" .. (menu_state.new_character_class or "nil") .. "'")
    
    -- Validate inputs
    if not menu_state.new_character_name or string.len(menu_state.new_character_name) == 0 then
        print("ERROR: No character name provided")
        return
    end
    
    if not menu_state.new_character_class then
        print("ERROR: No character class provided")
        return
    end
    
    local character_id, character_data = character_save_system.create_character(
        menu_state.new_character_name,
        menu_state.new_character_class
    )
    
    if character_id then
        print("Created character: " .. menu_state.new_character_name .. " (" .. menu_state.new_character_class .. ")")
        -- Reset form
        menu_state.new_character_name = ""
        menu_state.new_character_class = "warrior"
        menu_state.class_index = 1
        menu_state.text_input_active = false
        -- Go back to character list
        menu_state.current_screen = "character_list"
        character_menu.refresh_character_list()
    else
        print("Failed to create character")
    end
end

-- Handle confirmation dialog result
function character_menu.handle_confirmation(confirmed)
    if confirmed and menu_state.confirmation_dialog then
        if menu_state.confirmation_dialog.type == "delete" then
            local success = character_save_system.delete_character(menu_state.confirmation_dialog.character_id)
            if success then
                character_menu.refresh_character_list()
                print("Character deleted")
            else
                print("Failed to delete character")
            end
        end
    end
    
    menu_state.confirmation_dialog = nil
end

-- Get selected character for game start
function character_menu.get_selected_character()
    return menu_state.selected_character
end

-- Check if a character is selected and ready to play
function character_menu.can_start_game()
    return menu_state.character_ready_to_play and menu_state.selected_character ~= nil
end

-- Reset menu state
function character_menu.reset()
    menu_state.current_screen = "character_list"
    menu_state.selected_index = 1
    menu_state.selected_character = nil
    menu_state.character_ready_to_play = false
    menu_state.confirmation_dialog = nil
    character_menu.refresh_character_list()
end

return character_menu