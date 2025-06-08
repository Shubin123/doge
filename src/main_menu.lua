local main_menu = {}
local game_state = require("game_state")
local character_manager = require("character_manager")
local loading_screen = require("loading_screen")
local theme = require("theme")
local UI = require("ui")

-- Screen definitions
local screens = {
    main = {
        type = "list",
        title = "Doge Adventures",
        subtitle = "An Epic Journey Awaits",
        version = "v1.0.0",
        items = {
            {text = "[START] Start Adventure", icon = "[START]", onSelect = function() main_menu.change_screen("character_select") end},
            {text = "[CHAR] Character Selection", icon = "[CHAR]", onSelect = function() main_menu.change_screen("character_select") end},
            {text = "[MAP] Map Selection", icon = "[MAP]", onSelect = function() main_menu.change_screen("map_select") end},
            {text = "[SETTINGS] Settings", icon = "[SETTINGS]", onSelect = function() main_menu.change_screen("settings") end},
            {text = "[CREDITS] Credits", icon = "[CREDITS]", onSelect = function() main_menu.change_screen("credits") end},
            {text = "[EXIT] Exit", icon = "[EXIT]", onSelect = function() love.event.quit() end}
        }
    },
    character_select = {
        type = "grid",
        title = "Choose Your Hero",
        getItems = function()
            local list = {}
            for _, c in ipairs(character_manager.get_unlocked_characters()) do
                table.insert(list, {
                    id = c.id,
                    image = c.loaded_data and c.loaded_data.portrait,
                    name = c.definition.name,
                    stats = c.definition.stats,
                    selected = (c.id == character_manager.get_selected_character())
                })
            end
            return list
        end,
        columns = theme and theme.getMetric("char_per_row") or 3,
        onSelect = function(index)
            local chars = character_manager.get_unlocked_characters()
            local sel = chars[index]
            if sel then
                character_manager.set_selected_character(sel.id)
                main_menu.change_screen("map_select")
            end
        end,
        back = function() main_menu.change_screen("main") end
    },
    map_select = {
        type = "grid",
        title = "Select Adventure",
        getItems = function()
            local maps = {
                {id="level1", name="Grassland Level", description="A peaceful grassland perfect for getting started", difficulty="Easy"},
                {id="level2", name="Forest Level", description="Dense forest with mysterious creatures", difficulty="Medium"},
                {id="level3", name="Stone Ruins", description="Ancient ruins filled with danger", difficulty="Hard"}
            }
            local list = {}
            for _, m in ipairs(maps) do
                table.insert(list, {
                    id = m.id,
                    icon = "[MAP]",
                    title = m.name,
                    description = m.description,
                    difficulty = m.difficulty,
                    selected = (m.id == (game_state.getStateData("selected_map") or "level1"))
                })
            end
            return list
        end,
        columns = theme and theme.getMetric("map_per_row") or 2,
        onSelect = function(index)
            local maps = {
                {id="level1", name="Grassland Level", description="A peaceful grassland perfect for getting started", difficulty="Easy"},
                {id="level2", name="Forest Level", description="Dense forest with mysterious creatures", difficulty="Medium"},
                {id="level3", name="Stone Ruins", description="Ancient ruins filled with danger", difficulty="Hard"}
            }
            local sel = maps[index]
            if sel then
                game_state.setStateData("selected_map", sel.id)
                loading_screen.start_loading(
                    character_manager.get_selected_character(),
                    sel.id,
                    function() print("Game loaded - Character: " .. character_manager.get_selected_character() .. ", Map: " .. sel.id) end
                )
                game_state.showLoading("Preparing Adventure...")
            end
        end,
        back = function() main_menu.change_screen("main") end
    },
    settings = {
        type = "list",
        title = "Settings",
        items = {
            {text="[AUDIO] Audio Settings", onSelect=function() end},
            {text="[VIDEO] Video Settings", onSelect=function() end},
            {text="[CONTROLS] Controls", onSelect=function() end},
            {text="[BACK] to Main Menu", icon="←", onSelect=function() main_menu.change_screen("main") end}
        }
    },
    credits = {
        type = "list",
        title = "Credits",
        items = {
            {text="Game Development: Doge Team"},
            {text="Art Assets: Various Artists"},
            {text="Music: Original Compositions"},
            {text="Special Thanks: The Community"},
            {text=""},
            {text="Built with LOVE 2D"},
            {text="Made with [HEART] for indie game lovers"},
            {text="[BACK] to Main Menu", icon="←", onSelect=function() main_menu.change_screen("main") end}
        }
    }
}

-- Menu state
local menu_state = {
    current_screen = "main",
    selected_index = 1,
    animation_time = 0,
    transition_progress = 0,
    is_transitioning = false,
    last_input_type = "keyboard",
    mouse_x = 0,
    mouse_y = 0
}

-- Background elements and particle system
local background_elements = {}
local particle_system = nil

-- Initialize main menu
function main_menu.initialize()
    theme.initialize()
    main_menu.initialize_particles()
    main_menu.initialize_background()
    menu_state.current_screen = "main"
    menu_state.selected_index = 1
    menu_state.animation_time = 0
    menu_state.is_transitioning = false
    menu_state.transition_progress = 0
    print("Main menu initialized")
end

function main_menu.initialize_particles()
    if love.filesystem.getInfo("gfx/doge.png") then
        local tex = love.graphics.newImage("gfx/doge.png")
        particle_system = love.graphics.newParticleSystem(tex, theme.getMetric("particle_count"))
        particle_system:setParticleLifetime(theme.getMetric("particle_lifetime_min"), theme.getMetric("particle_lifetime_max"))
        particle_system:setEmissionRate(theme.getMetric("particle_emission_rate"))
        particle_system:setSizes(theme.getMetric("particle_size_min"), theme.getMetric("particle_size_max"))
        particle_system:setColors(unpack(theme.getParticleColors()))
        particle_system:setSpeed(theme.getMetric("particle_speed_min"), theme.getMetric("particle_speed_max"))
        particle_system:setDirection(theme.getMetric("particle_direction"))
        particle_system:setSpread(theme.getMetric("particle_spread"))
        particle_system:setSpin(theme.getMetric("particle_spin_min"), theme.getMetric("particle_spin_max"))
        particle_system:setPosition(love.graphics.getWidth()/2, love.graphics.getHeight() + theme.getMetric("particle_y_offset"))
        particle_system:start()
    end
end

function main_menu.initialize_background()
    background_elements = {}
    for i=1, theme.getMetric("background_circles_count") do
        table.insert(background_elements, {
            type="circle",
            x = math.random(0, love.graphics.getWidth()),
            y = math.random(0, love.graphics.getHeight()),
            radius = math.random(theme.getMetric("background_circle_min_radius"), theme.getMetric("background_circle_max_radius")),
            speed = math.random(theme.getMetric("background_min_speed"), theme.getMetric("background_max_speed")),
            direction = math.random() * 2 * math.pi,
            opacity = math.random() * (theme.getMetric("background_circle_opacity_max") - theme.getMetric("background_circle_opacity_min")) + theme.getMetric("background_circle_opacity_min"),
            color = theme.generateBackgroundCircleColor()
        })
    end
    for i=1, theme.getMetric("background_rectangles_count") do
        table.insert(background_elements, {
            type="rectangle",
            x = math.random(0, love.graphics.getWidth()),
            y = math.random(0, love.graphics.getHeight()),
            width = math.random(theme.getMetric("background_rect_min_size"), theme.getMetric("background_rect_max_size")),
            height = math.random(theme.getMetric("background_rect_min_size"), theme.getMetric("background_rect_max_size")),
            speed = math.random(theme.getMetric("background_min_speed"), theme.getMetric("background_max_speed")),
            direction = math.random() * 2 * math.pi,
            rotation = math.random() * 2 * math.pi,
            rotation_speed = math.random(-1,1),
            opacity = math.random() * (theme.getMetric("background_rect_opacity_max") - theme.getMetric("background_rect_opacity_min")) + theme.getMetric("background_rect_opacity_min"),
            color = theme.generateBackgroundRectColor()
        })
    end
end

function main_menu.update(dt)
    menu_state.animation_time = menu_state.animation_time + dt
    if particle_system then particle_system:update(dt) end
    -- Update background
    local w,h = love.graphics.getWidth(), love.graphics.getHeight()
    for _, e in ipairs(background_elements) do
        e.x = e.x + math.cos(e.direction) * e.speed * dt
        e.y = e.y + math.sin(e.direction) * e.speed * dt
        if e.type=="rectangle" then e.rotation = e.rotation + (e.rotation_speed * dt) end
        if e.x < -theme.getMetric("background_wrap_margin") then e.x = w + theme.getMetric("background_wrap_margin") end
        if e.x > w + theme.getMetric("background_wrap_margin") then e.x = -theme.getMetric("background_wrap_margin") end
        if e.y < -theme.getMetric("background_wrap_margin") then e.y = h + theme.getMetric("background_wrap_margin") end
        if e.y > h + theme.getMetric("background_wrap_margin") then e.y = -theme.getMetric("background_wrap_margin") end
    end
    -- Transition
    if menu_state.is_transitioning then
        menu_state.transition_progress = menu_state.transition_progress + dt * theme.getMetric("transition_speed")
        if menu_state.transition_progress >= 1 then
            menu_state.is_transitioning = false
            menu_state.transition_progress = 0
        end
    end
end

function main_menu.draw()
    local w,h = love.graphics.getWidth(), love.graphics.getHeight()
    love.graphics.clear(theme.getColor("background"))
    UI.drawBackgroundElements(background_elements, theme)
    if particle_system then
        love.graphics.setColor(theme.getColorWithAlpha("text",0.6))
        love.graphics.draw(particle_system)
    end

    local screen = screens[menu_state.current_screen]
    if not screen then return end

    -- Title and subtitle
    UI.drawTextCentered(screen.title, w/2, theme.getMetric("title_y_base"), theme.getFont("title"), theme.getColor("accent"), theme)
    if screen.subtitle then
        UI.drawTextCentered(screen.subtitle, w/2, theme.getMetric("subtitle_y_offset"), theme.getFont("subtitle"), theme.getColorWithAlpha("text",0.8), theme)
    end
    if screen.version then
        UI.drawTextCentered(screen.version, w/2, theme.getMetric("version_y_offset"), theme.getFont("small"), theme.getColorWithAlpha("text",0.6), theme)
    end

    -- Content
    if screen.type == "list" and screen.items then
        local container = { x = w*0.2, y = theme.getMetric("main_buttons_y"), width = w*0.6, height = h - theme.getMetric("main_buttons_y") }
        local layout = UI.calculateListLayout(#screen.items, container, theme.getMetric("button_height"), theme.getMetric("button_spacing"))
        UI.drawList(screen.items, layout, menu_state.selected_index, theme)
    elseif screen.type == "grid" and screen.getItems then
        local items = screen.getItems()
        local layout = {
            start_x = (w - (screen.columns * theme.getMetric("char_spacing")))/2,
            start_y = theme.getMetric("char_row_spacing"),
            columns = screen.columns,
            item_width = theme.getMetric("char_size"),
            item_height = theme.getMetric("char_size"),
            item_spacing_x = theme.getMetric("char_spacing"),
            item_spacing_y = theme.getMetric("char_row_spacing"),
            max_items = #items
        }
        UI.drawGrid(items, layout, menu_state.selected_index, theme)
        -- Back button
        local bw = 120
        local bh = theme.getMetric("button_height")
        local bx = 20
        local by = h - theme.getMetric("back_button_y_offset")
        UI.drawButton({text="[BACK]"}, bx, by, bw, bh, false, false, theme)
    end

    UI.drawTransitionOverlay(menu_state, theme)
    love.graphics.setColor(1,1,1,1)
end

function main_menu.handle_input(key, action)
    if action ~= "press" then return end
    local screen = screens[menu_state.current_screen]
    if not screen then return end
    local nav = { type = screen.type }
    if screen.type == "list" and screen.items then
        nav.max_items = #screen.items
    elseif screen.type == "grid" and screen.getItems then
        nav.columns = screen.columns
        nav.max_items = #screen.getItems()
    end
    menu_state = UI.handleKeyboard(key, action, menu_state, nav)
    if menu_state.action_triggered then
        if screen.type == "list" and screen.items and menu_state.selected_action then
            local selected_item = screen.items[menu_state.selected_action]
            if selected_item and selected_item.onSelect then
                selected_item.onSelect()
            end
        elseif screen.onSelect and menu_state.selected_action then
            screen.onSelect(menu_state.selected_action)
        end
    end
    if menu_state.back_triggered and screen.back then
        screen.back()
    end
end

function main_menu.handle_mouse(x, y, button, action)
    menu_state.mouse_x, menu_state.mouse_y = x, y
    menu_state.last_input_type = "mouse"
    if action ~= "press" or button ~= 1 then return end
    local screen = screens[menu_state.current_screen]
    if not screen then return end
    local picked = nil
    if screen.type == "list" and screen.items then
        local container = { x = love.graphics.getWidth()*0.2, y = theme.getMetric("main_buttons_y"), width = love.graphics.getWidth()*0.6, height = love.graphics.getHeight() - theme.getMetric("main_buttons_y") }
        local layout = UI.calculateListLayout(#screen.items, container, theme.getMetric("button_height"), theme.getMetric("button_spacing"))
        picked = UI.getListItemAt(x, y, layout)
    elseif screen.type == "grid" and screen.getItems then
        local items = screen.getItems()
        local layout = {
            start_x = (love.graphics.getWidth() - (screen.columns * theme.getMetric("char_spacing")))/2,
            start_y = theme.getMetric("char_row_spacing"),
            columns = screen.columns,
            item_spacing_x = theme.getMetric("char_spacing"),
            item_spacing_y = theme.getMetric("char_row_spacing"),
            max_items = #items
        }
        picked = UI.getGridItemAt(x, y, layout)
        -- back click
        local bw = 120; local bh = theme.getMetric("button_height")
        local bx = 20; local by = love.graphics.getHeight() - theme.getMetric("back_button_y_offset")
        if x >= bx and x <= bx + bw and y >= by and y <= by + bh then
            if screen.back then screen.back() end
            return
        end
    end
    if picked then
        if screen.type == "list" and screen.items then
            local selected_item = screen.items[picked]
            if selected_item and selected_item.onSelect then
                selected_item.onSelect()
            end
        elseif screen.onSelect then
            screen.onSelect(picked)
        end
    end
end

function main_menu.change_screen(new_screen)
    if new_screen == menu_state.current_screen then return end
    menu_state.current_screen = new_screen
    menu_state.selected_index = 1
    menu_state.is_transitioning = true
    menu_state.transition_progress = 0
    print("Changed to screen: " .. new_screen)
end

function main_menu.cleanup()
    if particle_system then particle_system:stop() end
    background_elements = {}
end

return main_menu