local main_menu = {}
local game_state = require("game_state")
local character_manager = require("character_manager")

-- Menu configuration
local menu_config = {
    title = "Doge Adventures",
    subtitle = "An Epic Journey Awaits",
    version = "v1.0.0",
    
    -- Visual settings
    background_color = {0.05, 0.05, 0.15, 1},
    accent_color = {0.3, 0.7, 1.0, 1},
    text_color = {1, 1, 1, 1},
    button_color = {0.2, 0.2, 0.4, 0.8},
    button_hover_color = {0.3, 0.3, 0.6, 0.9},
    
    -- Animation settings
    title_bounce_speed = 2.0,
    particle_count = 100,
    background_scroll_speed = 20
}

-- Menu state
local menu_state = {
    current_screen = "main", -- "main", "character_select", "map_select", "settings", "credits"
    selected_button = 1,
    button_hover_time = 0,
    animation_time = 0,
    transition_progress = 0,
    is_transitioning = false,
    
    -- Input handling
    mouse_x = 0,
    mouse_y = 0,
    last_input_type = "keyboard" -- "keyboard" or "mouse"
}

-- Button definitions
local buttons = {
    main = {
        {text = "Start Adventure", action = "start_game", icon = "▶"},
        {text = "Character Selection", action = "character_select", icon = "👤"},
        {text = "Map Selection", action = "map_select", icon = "🗺"},
        {text = "Settings", action = "settings", icon = "⚙"},
        {text = "Credits", action = "credits", icon = "📜"},
        {text = "Exit", action = "exit", icon = "✕"}
    },
    
    character_select = {
        {text = "Back to Main Menu", action = "back_to_main", icon = "←"}
    },
    
    map_select = {
        {text = "Back to Main Menu", action = "back_to_main", icon = "←"}
    },
    
    settings = {
        {text = "Audio Settings", action = "audio_settings", icon = "🔊"},
        {text = "Video Settings", action = "video_settings", icon = "📺"},
        {text = "Controls", action = "controls", icon = "🎮"},
        {text = "Back to Main Menu", action = "back_to_main", icon = "←"}
    },
    
    credits = {
        {text = "Back to Main Menu", action = "back_to_main", icon = "←"}
    }
}

-- Particles for background effect
local particles = {}
local particle_system = nil

-- Fonts
local fonts = {}

-- Background elements
local background_elements = {}

-- Initialize main menu
function main_menu.initialize()
    -- Load fonts
    fonts.title = love.graphics.newFont("gfx/menu/PixelGameFont.ttf", 48)
    fonts.subtitle = love.graphics.newFont("gfx/menu/PixelGameFont.ttf", 20)
    fonts.button = love.graphics.newFont("gfx/menu/PixelGameFont.ttf", 18)
    fonts.small = love.graphics.newFont("gfx/menu/PixelGameFont.ttf", 14)
    
    -- Initialize particle system for background
    main_menu.initialize_particles()
    
    -- Initialize background elements
    main_menu.initialize_background()
    
    -- Reset menu state
    menu_state.current_screen = "main"
    menu_state.selected_button = 1
    menu_state.animation_time = 0
    
    print("Main menu initialized")
end

-- Initialize particle system
function main_menu.initialize_particles()
    if love.filesystem.getInfo("gfx/doge.png") then
        local particle_texture = love.graphics.newImage("gfx/doge.png")
        particle_system = love.graphics.newParticleSystem(particle_texture, menu_config.particle_count)
        
        particle_system:setParticleLifetime(3, 8)
        particle_system:setEmissionRate(15)
        particle_system:setSizes(0.1, 0.3)
        particle_system:setColors(
            {1, 1, 1, 0}, -- Start transparent
            {0.7, 0.8, 1, 0.3}, -- Fade in
            {0.5, 0.6, 0.8, 0.1}, -- Fade out
            {1, 1, 1, 0} -- End transparent
        )
        particle_system:setSpeed(30, 80)
        particle_system:setDirection(-math.pi/2) -- Upward
        particle_system:setSpread(math.pi/3)
        particle_system:setRotation(0, 2*math.pi)
        particle_system:setSpin(-2, 2)
        particle_system:setEmissionArea("uniform", love.graphics.getWidth(), 1)
        particle_system:setPosition(love.graphics.getWidth()/2, love.graphics.getHeight() + 50)
        particle_system:start()
    end
end

-- Initialize background elements
function main_menu.initialize_background()
    background_elements = {}
    
    -- Create floating geometric shapes
    for i = 1, 20 do
        table.insert(background_elements, {
            type = "circle",
            x = math.random(0, love.graphics.getWidth()),
            y = math.random(0, love.graphics.getHeight()),
            radius = math.random(10, 50),
            speed = math.random(10, 30),
            direction = math.random() * 2 * math.pi,
            opacity = math.random(0.05, 0.15),
            color = {
                math.random(50, 100) / 100,
                math.random(60, 100) / 100,
                math.random(80, 100) / 100
            }
        })
    end
    
    -- Create floating rectangles
    for i = 1, 15 do
        table.insert(background_elements, {
            type = "rectangle",
            x = math.random(0, love.graphics.getWidth()),
            y = math.random(0, love.graphics.getHeight()),
            width = math.random(20, 80),
            height = math.random(20, 80),
            speed = math.random(15, 40),
            direction = math.random() * 2 * math.pi,
            rotation = math.random() * 2 * math.pi,
            rotation_speed = math.random(-1, 1),
            opacity = math.random(0.03, 0.1),
            color = {
                math.random(40, 80) / 100,
                math.random(50, 90) / 100,
                math.random(70, 100) / 100
            }
        })
    end
end

-- Update main menu
function main_menu.update(dt)
    menu_state.animation_time = menu_state.animation_time + dt
    
    -- Update particle system
    if particle_system then
        particle_system:update(dt)
    end
    
    -- Update background elements
    main_menu.update_background(dt)
    
    -- Update button hover animation
    if menu_state.last_input_type == "mouse" then
        menu_state.button_hover_time = menu_state.button_hover_time + dt
    end
    
    -- Handle transitions
    if menu_state.is_transitioning then
        menu_state.transition_progress = menu_state.transition_progress + dt * 3
        if menu_state.transition_progress >= 1 then
            menu_state.is_transitioning = false
            menu_state.transition_progress = 0
        end
    end
end

-- Update background elements
function main_menu.update_background(dt)
    local screen_width = love.graphics.getWidth()
    local screen_height = love.graphics.getHeight()
    
    for _, element in ipairs(background_elements) do
        -- Move element
        element.x = element.x + math.cos(element.direction) * element.speed * dt
        element.y = element.y + math.sin(element.direction) * element.speed * dt
        
        -- Rotate rectangles
        if element.type == "rectangle" then
            element.rotation = element.rotation + element.rotation_speed * dt
        end
        
        -- Wrap around screen edges
        if element.x < -100 then
            element.x = screen_width + 100
        elseif element.x > screen_width + 100 then
            element.x = -100
        end
        
        if element.y < -100 then
            element.y = screen_height + 100
        elseif element.y > screen_height + 100 then
            element.y = -100
        end
    end
end

-- Draw main menu
function main_menu.draw()
    local screen_width = love.graphics.getWidth()
    local screen_height = love.graphics.getHeight()
    
    -- Clear background
    love.graphics.clear(menu_config.background_color)
    
    -- Draw background elements
    main_menu.draw_background()
    
    -- Draw particle system
    if particle_system then
        love.graphics.setColor(1, 1, 1, 0.6)
        love.graphics.draw(particle_system)
    end
    
    -- Draw current screen
    if menu_state.current_screen == "main" then
        main_menu.draw_main_screen()
    elseif menu_state.current_screen == "character_select" then
        main_menu.draw_character_select()
    elseif menu_state.current_screen == "map_select" then
        main_menu.draw_map_select()
    elseif menu_state.current_screen == "settings" then
        main_menu.draw_settings()
    elseif menu_state.current_screen == "credits" then
        main_menu.draw_credits()
    end
    
    -- Draw transition overlay
    if menu_state.is_transitioning then
        love.graphics.setColor(0, 0, 0, 1 - menu_state.transition_progress)
        love.graphics.rectangle("fill", 0, 0, screen_width, screen_height)
    end
    
    -- Reset color
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw background elements
function main_menu.draw_background()
    for _, element in ipairs(background_elements) do
        love.graphics.setColor(element.color[1], element.color[2], element.color[3], element.opacity)
        
        if element.type == "circle" then
            love.graphics.circle("fill", element.x, element.y, element.radius)
        elseif element.type == "rectangle" then
            love.graphics.push()
            love.graphics.translate(element.x + element.width/2, element.y + element.height/2)
            love.graphics.rotate(element.rotation)
            love.graphics.rectangle("fill", -element.width/2, -element.height/2, element.width, element.height)
            love.graphics.pop()
        end
    end
    
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw main screen
function main_menu.draw_main_screen()
    local screen_width = love.graphics.getWidth()
    local screen_height = love.graphics.getHeight()
    
    -- Draw title with bounce animation
    love.graphics.setFont(fonts.title)
    love.graphics.setColor(menu_config.text_color)
    
    local title_y = 100 + math.sin(menu_state.animation_time * menu_config.title_bounce_speed) * 5
    local title_width = fonts.title:getWidth(menu_config.title)
    
    -- Title shadow
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.print(menu_config.title, screen_width/2 - title_width/2 + 3, title_y + 3)
    
    -- Title text with gradient effect
    love.graphics.setColor(menu_config.accent_color)
    love.graphics.print(menu_config.title, screen_width/2 - title_width/2, title_y)
    
    -- Subtitle
    love.graphics.setFont(fonts.subtitle)
    love.graphics.setColor(menu_config.text_color[1], menu_config.text_color[2], menu_config.text_color[3], 0.8)
    local subtitle_width = fonts.subtitle:getWidth(menu_config.subtitle)
    love.graphics.print(menu_config.subtitle, screen_width/2 - subtitle_width/2, title_y + 60)
    
    -- Version
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(menu_config.text_color[1], menu_config.text_color[2], menu_config.text_color[3], 0.6)
    local version_width = fonts.small:getWidth(menu_config.version)
    love.graphics.print(menu_config.version, screen_width/2 - version_width/2, title_y + 90)
    
    -- Draw buttons
    main_menu.draw_buttons("main", 250)
end

-- Draw character selection screen
function main_menu.draw_character_select()
    local screen_width = love.graphics.getWidth()
    local screen_height = love.graphics.getHeight()
    
    -- Title
    love.graphics.setFont(fonts.title)
    love.graphics.setColor(menu_config.text_color)
    local title = "Choose Your Hero"
    local title_width = fonts.title:getWidth(title)
    love.graphics.print(title, screen_width/2 - title_width/2, 50)
    
    -- Get available characters
    local characters = character_manager.get_unlocked_characters()
    local char_per_row = 3
    local char_size = 120
    local char_spacing = 150
    
    local start_x = screen_width/2 - (char_per_row * char_spacing)/2
    local start_y = 150
    
    love.graphics.setFont(fonts.button)
    
    for i, char_data in ipairs(characters) do
        local row = math.floor((i-1) / char_per_row)
        local col = (i-1) % char_per_row
        
        local x = start_x + col * char_spacing
        local y = start_y + row * 180
        
        -- Check if mouse is over this character (for mouse interaction)
        local mouse_over = false
        if menu_state.last_input_type == "mouse" then
            local card_left = x - char_size/2
            local card_right = x + char_size/2
            local card_top = y - char_size/2
            local card_bottom = y + char_size/2
            
            mouse_over = menu_state.mouse_x >= card_left and menu_state.mouse_x <= card_right and
                        menu_state.mouse_y >= card_top and menu_state.mouse_y <= card_bottom
        end
        
        -- Character card background
        local is_selected = char_data.id == character_manager.get_selected_character()
        local card_color = menu_config.button_color
        
        if is_selected then
            card_color = menu_config.accent_color
        elseif mouse_over then
            card_color = menu_config.button_hover_color
        end
        
        love.graphics.setColor(card_color)
        love.graphics.rectangle("fill", x - char_size/2, y - char_size/2, char_size, char_size, 10)
        
        -- Character portrait
        if char_data.loaded_data and char_data.loaded_data.portrait then
            love.graphics.setColor(1, 1, 1, 1)
            local portrait = char_data.loaded_data.portrait
            local scale = math.min(char_size * 0.8 / portrait:getWidth(), char_size * 0.8 / portrait:getHeight())
            love.graphics.draw(portrait, x, y, 0, scale, scale, portrait:getWidth()/2, portrait:getHeight()/2)
        else
            -- Placeholder
            love.graphics.setColor(menu_config.text_color[1], menu_config.text_color[2], menu_config.text_color[3], 0.5)
            love.graphics.rectangle("fill", x - 40, y - 40, 80, 80, 5)
        end
        
        -- Character name
        love.graphics.setColor(menu_config.text_color)
        local name_width = fonts.button:getWidth(char_data.definition.name)
        love.graphics.print(char_data.definition.name, x - name_width/2, y + char_size/2 + 10)
        
        -- Stats preview
        love.graphics.setFont(fonts.small)
        local stats = char_data.definition.stats
        local stats_text = string.format("HP:%d SPD:%d ATK:%d DEF:%d", stats.health, stats.speed, stats.attack, stats.defense)
        local stats_width = fonts.small:getWidth(stats_text)
        love.graphics.setColor(menu_config.text_color[1], menu_config.text_color[2], menu_config.text_color[3], 0.8)
        love.graphics.print(stats_text, x - stats_width/2, y + char_size/2 + 35)
    end
    
    -- Draw back button
    main_menu.draw_buttons("character_select", screen_height - 80)
end

-- Draw map selection screen
function main_menu.draw_map_select()
    local screen_width = love.graphics.getWidth()
    local screen_height = love.graphics.getHeight()
    
    -- Title
    love.graphics.setFont(fonts.title)
    love.graphics.setColor(menu_config.text_color)
    local title = "Select Adventure"
    local title_width = fonts.title:getWidth(title)
    love.graphics.print(title, screen_width/2 - title_width/2, 50)
    
    -- Available maps
    local available_maps = {
        {
            id = "level1",
            name = "Grassland Level", 
            description = "A peaceful grassland perfect for getting started",
            difficulty = "Easy",
            unlocked = true
        },
        {
            id = "level2",
            name = "Forest Level",
            description = "Dense forest with mysterious creatures",
            difficulty = "Medium", 
            unlocked = true
        },
        {
            id = "level3",
            name = "Stone Ruins",
            description = "Ancient ruins filled with danger",
            difficulty = "Hard",
            unlocked = true
        }
    }
    
    local map_per_row = 2
    local map_size = 200
    local map_spacing = 250
    
    local start_x = screen_width/2 - (map_per_row * map_spacing)/2
    local start_y = 150
    
    love.graphics.setFont(fonts.button)
    
    for i, map_data in ipairs(available_maps) do
        local row = math.floor((i-1) / map_per_row)
        local col = (i-1) % map_per_row
        
        local x = start_x + col * map_spacing
        local y = start_y + row * 220
        
        -- Check if mouse is over this map
        local mouse_over = false
        if menu_state.last_input_type == "mouse" then
            local card_left = x - map_size/2
            local card_right = x + map_size/2
            local card_top = y - map_size/2
            local card_bottom = y + map_size/2
            
            mouse_over = menu_state.mouse_x >= card_left and menu_state.mouse_x <= card_right and
                        menu_state.mouse_y >= card_top and menu_state.mouse_y <= card_bottom
        end
        
        -- Map card background
        local is_selected = map_data.id == (game_state.getStateData("selected_map") or "level1")
        local card_color = menu_config.button_color
        
        if is_selected then
            card_color = menu_config.accent_color
        elseif mouse_over then
            card_color = menu_config.button_hover_color
        end
        
        love.graphics.setColor(card_color)
        love.graphics.rectangle("fill", x - map_size/2, y - map_size/2, map_size, map_size, 15)
        
        -- Map preview (placeholder)
        love.graphics.setColor(menu_config.text_color[1], menu_config.text_color[2], menu_config.text_color[3], 0.3)
        love.graphics.rectangle("fill", x - map_size/2 + 20, y - map_size/2 + 20, map_size - 40, map_size * 0.6, 5)
        
        -- Map icon/preview
        love.graphics.setColor(menu_config.text_color[1], menu_config.text_color[2], menu_config.text_color[3], 0.6)
        love.graphics.setFont(fonts.title)
        local icon = "🗺"
        local icon_width = fonts.title:getWidth(icon)
        love.graphics.print(icon, x - icon_width/2, y - 50)
        
        -- Map name
        love.graphics.setFont(fonts.button)
        love.graphics.setColor(menu_config.text_color)
        local name_width = fonts.button:getWidth(map_data.name)
        love.graphics.print(map_data.name, x - name_width/2, y + map_size/2 - 60)
        
        -- Map description
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(menu_config.text_color[1], menu_config.text_color[2], menu_config.text_color[3], 0.8)
        love.graphics.printf(map_data.description, x - map_size/2 + 10, y + map_size/2 - 40, map_size - 20, "center")
        
        -- Difficulty
        love.graphics.setColor(menu_config.accent_color[1], menu_config.accent_color[2], menu_config.accent_color[3], 0.9)
        local diff_text = "Difficulty: " .. map_data.difficulty
        local diff_width = fonts.small:getWidth(diff_text)
        love.graphics.print(diff_text, x - diff_width/2, y + map_size/2 - 15)
        
        -- Selection indicator
        if is_selected then
            love.graphics.setColor(menu_config.accent_color)
            love.graphics.setLineWidth(3)
            love.graphics.rectangle("line", x - map_size/2 - 5, y - map_size/2 - 5, map_size + 10, map_size + 10, 15)
        end
    end
    
    -- Selected character info
    local selected_char = character_manager.get_selected_character()
    if selected_char then
        local char_def = character_manager.get_character_definition(selected_char)
        if char_def then
            love.graphics.setFont(fonts.small)
            love.graphics.setColor(menu_config.text_color[1], menu_config.text_color[2], menu_config.text_color[3], 0.7)
            local char_text = "Selected Character: " .. char_def.name
            love.graphics.print(char_text, 20, screen_height - 120)
        end
    end
    
    -- Draw back button
    main_menu.draw_buttons("map_select", screen_height - 80)
end

-- Draw settings screen
function main_menu.draw_settings()
    local screen_width = love.graphics.getWidth()
    local screen_height = love.graphics.getHeight()
    
    -- Title
    love.graphics.setFont(fonts.title)
    love.graphics.setColor(menu_config.text_color)
    local title = "Settings"
    local title_width = fonts.title:getWidth(title)
    love.graphics.print(title, screen_width/2 - title_width/2, 50)
    
    -- Draw buttons
    main_menu.draw_buttons("settings", 200)
end

-- Draw credits screen
function main_menu.draw_credits()
    local screen_width = love.graphics.getWidth()
    local screen_height = love.graphics.getHeight()
    
    -- Title
    love.graphics.setFont(fonts.title)
    love.graphics.setColor(menu_config.text_color)
    local title = "Credits"
    local title_width = fonts.title:getWidth(title)
    love.graphics.print(title, screen_width/2 - title_width/2, 50)
    
    -- Credits content
    love.graphics.setFont(fonts.button)
    love.graphics.setColor(menu_config.text_color[1], menu_config.text_color[2], menu_config.text_color[3], 0.9)
    
    local credits_text = {
        "Game Development: Doge Team",
        "Art Assets: Various Artists",
        "Music: Original Compositions", 
        "Special Thanks: The Community",
        "",
        "Built with LÖVE 2D",
        "Made with ❤ for indie game lovers"
    }
    
    for i, line in ipairs(credits_text) do
        local line_width = fonts.button:getWidth(line)
        love.graphics.print(line, screen_width/2 - line_width/2, 150 + i * 30)
    end
    
    -- Draw back button
    main_menu.draw_buttons("credits", screen_height - 80)
end

-- Draw buttons for current screen
function main_menu.draw_buttons(screen, start_y)
    local screen_width = love.graphics.getWidth()
    local current_buttons = buttons[screen]
    
    if not current_buttons then return end
    
    love.graphics.setFont(fonts.button)
    local button_height = 40
    local button_spacing = 50
    
    for i, button in ipairs(current_buttons) do
        local y = start_y + (i-1) * button_spacing
        local is_selected = (menu_state.selected_button == i and menu_state.last_input_type == "keyboard")
        
        -- Button background
        local button_color = is_selected and menu_config.button_hover_color or menu_config.button_color
        love.graphics.setColor(button_color)
        
        local button_text = button.icon .. " " .. button.text
        local button_width = fonts.button:getWidth(button_text) + 40
        local button_x = screen_width/2 - button_width/2
        
        love.graphics.rectangle("fill", button_x, y - button_height/2, button_width, button_height, 5)
        
        -- Button border for selected
        if is_selected then
            love.graphics.setColor(menu_config.accent_color)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", button_x, y - button_height/2, button_width, button_height, 5)
        end
        
        -- Button text
        love.graphics.setColor(menu_config.text_color)
        love.graphics.print(button_text, button_x + 20, y - fonts.button:getHeight()/2)
    end
    
    love.graphics.setColor(1, 1, 1, 1)
end

-- Handle input
function main_menu.handle_input(key, action)
    if action ~= "press" then return end
    
    local current_buttons = buttons[menu_state.current_screen]
    if not current_buttons then return end
    
    menu_state.last_input_type = "keyboard"
    
    if key == "up" or key == "w" then
        menu_state.selected_button = math.max(1, menu_state.selected_button - 1)
    elseif key == "down" or key == "s" then
        menu_state.selected_button = math.min(#current_buttons, menu_state.selected_button + 1)
    elseif key == "return" or key == "space" then
        main_menu.activate_button(menu_state.selected_button)
    elseif key == "escape" then
        if menu_state.current_screen ~= "main" then
            main_menu.change_screen("main")
        end
    end
end

-- Handle mouse input
function main_menu.handle_mouse(x, y, button, action)
    menu_state.mouse_x = x
    menu_state.mouse_y = y
    menu_state.last_input_type = "mouse"
    
    if action == "press" and button == 1 then
        -- Check for character selection in character select screen
        if menu_state.current_screen == "character_select" then
            local clicked_character = main_menu.get_character_at_position(x, y)
            if clicked_character then
                character_manager.set_selected_character(clicked_character)
                
                -- Go to map selection instead of loading directly
                main_menu.change_screen("map_select")
                return
            end
        end
        
        -- Check for map selection in map select screen
        if menu_state.current_screen == "map_select" then
            local clicked_map = main_menu.get_map_at_position(x, y)
            if clicked_map then
                game_state.setStateData("selected_map", clicked_map)
                
                -- Now start loading with both character and map selected
                loading_screen.start_loading(
                    character_manager.get_selected_character(),
                    clicked_map,
                    function()
                        print("Game loaded - Character: " .. character_manager.get_selected_character() .. ", Map: " .. clicked_map)
                    end
                )
                game_state.showLoading("Preparing Adventure...")
                return
            end
        end
        
        local clicked_button = main_menu.get_button_at_position(x, y)
        if clicked_button then
            main_menu.activate_button(clicked_button)
        end
    end
end

-- Get character at mouse position (for character select screen)
function main_menu.get_character_at_position(x, y)
    if menu_state.current_screen ~= "character_select" then return nil end
    
    local characters = character_manager.get_unlocked_characters()
    local char_per_row = 3
    local char_size = 120
    local char_spacing = 150
    
    local screen_width = love.graphics.getWidth()
    local start_x = screen_width/2 - (char_per_row * char_spacing)/2
    local start_y = 150
    
    for i, char_data in ipairs(characters) do
        local row = math.floor((i-1) / char_per_row)
        local col = (i-1) % char_per_row
        
        local char_x = start_x + col * char_spacing
        local char_y = start_y + row * 180
        
        local card_left = char_x - char_size/2
        local card_right = char_x + char_size/2
        local card_top = char_y - char_size/2
        local card_bottom = char_y + char_size/2
        
        if x >= card_left and x <= card_right and y >= card_top and y <= card_bottom then
            return char_data.id
        end
    end
    
    return nil
end

-- Get map at mouse position (for map select screen)
function main_menu.get_map_at_position(x, y)
    if menu_state.current_screen ~= "map_select" then return nil end
    
    -- Available maps (should match the ones in draw_map_select)
    local available_maps = {
        {
            id = "level1",
            name = "Grassland Level", 
            description = "A peaceful grassland perfect for getting started",
            difficulty = "Easy",
            unlocked = true
        },
        {
            id = "level2",
            name = "Forest Level",
            description = "Dense forest with mysterious creatures",
            difficulty = "Medium", 
            unlocked = true
        },
        {
            id = "level3",
            name = "Stone Ruins",
            description = "Ancient ruins filled with danger",
            difficulty = "Hard",
            unlocked = true
        }
    }
    
    local map_per_row = 2
    local map_size = 200
    local map_spacing = 250
    
    local screen_width = love.graphics.getWidth()
    local start_x = screen_width/2 - (map_per_row * map_spacing)/2
    local start_y = 150
    
    for i, map_data in ipairs(available_maps) do
        local row = math.floor((i-1) / map_per_row)
        local col = (i-1) % map_per_row
        
        local map_x = start_x + col * map_spacing
        local map_y = start_y + row * 220
        
        local card_left = map_x - map_size/2
        local card_right = map_x + map_size/2
        local card_top = map_y - map_size/2
        local card_bottom = map_y + map_size/2
        
        if x >= card_left and x <= card_right and y >= card_top and y <= card_bottom then
            return map_data.id
        end
    end
    
    return nil
end

-- Get button at mouse position
function main_menu.get_button_at_position(x, y)
    local current_buttons = buttons[menu_state.current_screen]
    if not current_buttons then return nil end
    
    local screen_width = love.graphics.getWidth()
    local start_y = menu_state.current_screen == "main" and 250 or 200
    local button_height = 40
    local button_spacing = 50
    
    for i, button in ipairs(current_buttons) do
        local button_y = start_y + (i-1) * button_spacing
        local button_text = button.icon .. " " .. button.text
        local button_width = fonts.button:getWidth(button_text) + 40
        local button_x = screen_width/2 - button_width/2
        
        if x >= button_x and x <= button_x + button_width and
           y >= button_y - button_height/2 and y <= button_y + button_height/2 then
            return i
        end
    end
    
    return nil
end

-- Activate button
function main_menu.activate_button(button_index)
    local current_buttons = buttons[menu_state.current_screen]
    if not current_buttons or not current_buttons[button_index] then return end
    
    local button = current_buttons[button_index]
    print("Activated button: " .. button.text)
    
    if button.action == "start_game" then
        main_menu.change_screen("character_select")
    elseif button.action == "character_select" then
        main_menu.change_screen("character_select")
    elseif button.action == "map_select" then
        main_menu.change_screen("map_select")
    elseif button.action == "settings" then
        main_menu.change_screen("settings")
    elseif button.action == "credits" then
        main_menu.change_screen("credits")
    elseif button.action == "back_to_main" then
        main_menu.change_screen("main")
    elseif button.action == "exit" then
        love.event.quit()
    end
end

-- Change screen
function main_menu.change_screen(new_screen)
    if new_screen == menu_state.current_screen then return end
    
    menu_state.current_screen = new_screen
    menu_state.selected_button = 1
    menu_state.is_transitioning = true
    menu_state.transition_progress = 0
    
    print("Changed to screen: " .. new_screen)
end

-- Cleanup
function main_menu.cleanup()
    if particle_system then
        particle_system:stop()
    end
    particles = {}
    background_elements = {}
end

return main_menu