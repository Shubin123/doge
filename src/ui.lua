local UI = {}

-- Pure function to draw text centered at a position
function UI.drawTextCentered(text, x, y, font, color, theme)
    if not text or not x or not y then return end
    
    local current_font = love.graphics.getFont()
    local current_color = {love.graphics.getColor()}
    
    -- Set font if provided
    if font then
        love.graphics.setFont(font)
    end
    
    -- Set color if provided, otherwise use theme default
    if color then
        love.graphics.setColor(color)
    elseif theme and theme.colors.text then
        love.graphics.setColor(theme.colors.text)
    end
    
    -- Calculate centered position
    local text_width = love.graphics.getFont():getWidth(text)
    local text_height = love.graphics.getFont():getHeight()
    local centered_x = x - text_width / 2
    local centered_y = y - text_height / 2
    
    love.graphics.print(text, centered_x, centered_y)
    
    -- Restore previous state
    love.graphics.setFont(current_font)
    love.graphics.setColor(current_color)
end

-- Pure function to draw a button
function UI.drawButton(button_def, x, y, width, height, is_selected, is_hovered, theme)
    if not button_def or not x or not y or not width or not height then return end
    
    local current_color = {love.graphics.getColor()}
    local current_font = love.graphics.getFont()
    
    -- Determine button color based on state
    local button_color = theme.colors.button
    if is_selected or is_hovered then
        button_color = theme.colors.button_hover
    end
    
    -- Draw button background
    love.graphics.setColor(button_color)
    love.graphics.rectangle("fill", x, y, width, height, theme.metrics.button_radius or 5)
    
    -- Draw button border if selected
    if is_selected then
        love.graphics.setColor(theme.colors.accent)
        love.graphics.setLineWidth(theme.metrics.border_width or 2)
        love.graphics.rectangle("line", x, y, width, height, theme.metrics.button_radius or 5)
    end
    
    -- Draw button text
    if theme.fonts.button then
        love.graphics.setFont(theme.fonts.button)
    end
    
    local button_text = (button_def.icon and (button_def.icon .. " ") or "") .. (button_def.text or "")
    love.graphics.setColor(theme.colors.text)
    
    local text_width = love.graphics.getFont():getWidth(button_text)
    local text_height = love.graphics.getFont():getHeight()
    local text_x = x + width/2 - text_width/2
    local text_y = y + height/2 - text_height/2
    
    love.graphics.print(button_text, text_x, text_y)
    
    -- Restore previous state
    love.graphics.setColor(current_color)
    love.graphics.setFont(current_font)
end

-- Pure function to draw a list of items
function UI.drawList(items, layout, selected_index, theme)
    if not items or not layout or not theme then return end
    
    local current_color = {love.graphics.getColor()}
    local current_font = love.graphics.getFont()
    
    if theme.fonts.list then
        love.graphics.setFont(theme.fonts.list)
    end
    
    for i, item in ipairs(items) do
        local y = layout.start_y + (i - 1) * layout.item_spacing
        local is_selected = (i == selected_index)
        
        -- Draw item background if selected
        if is_selected then
            love.graphics.setColor(theme.colors.list_selection)
            love.graphics.rectangle("fill", layout.x, y - layout.item_height/2, layout.width, layout.item_height, theme.metrics.list_radius or 3)
        end
        
        -- Draw item text
        love.graphics.setColor(theme.colors.text)
        local item_text = item.text or tostring(item)
        love.graphics.print(item_text, layout.x + layout.text_padding, y - love.graphics.getFont():getHeight()/2)
        
        -- Draw item icon if present
        if item.icon then
            love.graphics.setColor(theme.colors.accent)
            love.graphics.print(item.icon, layout.x + layout.text_padding - 25, y - love.graphics.getFont():getHeight()/2)
        end
    end
    
    -- Restore previous state
    love.graphics.setColor(current_color)
    love.graphics.setFont(current_font)
end

-- Pure function to draw a grid of items
function UI.drawGrid(items, layout, selected_index, theme)
    if not items or not layout or not theme then return end
    
    local current_color = {love.graphics.getColor()}
    local current_font = love.graphics.getFont()
    
    for i, item in ipairs(items) do
        local grid_layout = UI.calculateGridLayout(i, layout)
        local is_selected = (i == selected_index)
        
        -- Determine card color based on state
        local card_color = theme.colors.card
        if item.selected then
            card_color = theme.colors.accent
        elseif is_selected then
            card_color = theme.colors.card_hover
        end
        
        -- Draw card background
        love.graphics.setColor(card_color)
        love.graphics.rectangle("fill", 
            grid_layout.x - layout.item_width/2, 
            grid_layout.y - layout.item_height/2, 
            layout.item_width, 
            layout.item_height, 
            theme.metrics.card_radius or 10)
        
        -- Draw selection border
        if is_selected or item.selected then
            love.graphics.setColor(theme.colors.accent)
            love.graphics.setLineWidth(theme.metrics.border_width or 3)
            love.graphics.rectangle("line", 
                grid_layout.x - layout.item_width/2 - 5, 
                grid_layout.y - layout.item_height/2 - 5, 
                layout.item_width + 10, 
                layout.item_height + 10, 
                theme.metrics.card_radius or 10)
        end
        
        -- Draw item content
        if item.image then
            love.graphics.setColor(1, 1, 1, 1)
            local scale = math.min(
                (layout.item_width * 0.8) / item.image:getWidth(),
                (layout.item_height * 0.6) / item.image:getHeight()
            )
            love.graphics.draw(item.image, grid_layout.x, grid_layout.y - layout.item_height/4, 0, scale, scale, 
                item.image:getWidth()/2, item.image:getHeight()/2)
        elseif item.icon then
            if theme.fonts.icon then
                love.graphics.setFont(theme.fonts.icon)
            end
            love.graphics.setColor(theme.colors.text)
            UI.drawTextCentered(item.icon, grid_layout.x, grid_layout.y - layout.item_height/4, nil, nil, theme)
        else
            -- Placeholder
            love.graphics.setColor(theme.colors.text[1], theme.colors.text[2], theme.colors.text[3], 0.5)
            love.graphics.rectangle("fill", 
                grid_layout.x - 40, grid_layout.y - layout.item_height/4 - 40, 
                80, 80, 5)
        end
        
        -- Draw item title
        if item.name or item.title then
            if theme.fonts.card_title then
                love.graphics.setFont(theme.fonts.card_title)
            end
            love.graphics.setColor(theme.colors.text)
            UI.drawTextCentered(item.name or item.title, grid_layout.x, grid_layout.y + layout.item_height/2 - 30, nil, nil, theme)
        end
        
        -- Draw item description
        if item.description then
            if theme.fonts.card_description then
                love.graphics.setFont(theme.fonts.card_description)
            end
            love.graphics.setColor(theme.colors.text[1], theme.colors.text[2], theme.colors.text[3], 0.8)
            love.graphics.printf(item.description, 
                grid_layout.x - layout.item_width/2 + 10, 
                grid_layout.y + layout.item_height/2 - 15, 
                layout.item_width - 20, "center")
        end
        
        -- Draw additional info (like stats or difficulty)
        if item.stats then
            if theme.fonts.small then
                love.graphics.setFont(theme.fonts.small)
            end
            love.graphics.setColor(theme.colors.text[1], theme.colors.text[2], theme.colors.text[3], 0.8)
            local stats_text = string.format("HP:%d SPD:%d ATK:%d DEF:%d", 
                item.stats.health or 0, item.stats.speed or 0, item.stats.attack or 0, item.stats.defense or 0)
            UI.drawTextCentered(stats_text, grid_layout.x, grid_layout.y + layout.item_height/2 + 5, nil, nil, theme)
        elseif item.difficulty then
            if theme.fonts.small then
                love.graphics.setFont(theme.fonts.small)
            end
            love.graphics.setColor(theme.colors.accent)
            local diff_text = "Difficulty: " .. item.difficulty
            UI.drawTextCentered(diff_text, grid_layout.x, grid_layout.y + layout.item_height/2 + 5, nil, nil, theme)
        end
    end
    
    -- Restore previous state
    love.graphics.setColor(current_color)
    love.graphics.setFont(current_font)
end

-- Pure function to draw background elements
function UI.drawBackgroundElements(elements, theme)
    if not elements or not theme then return end
    
    local current_color = {love.graphics.getColor()}
    
    for _, element in ipairs(elements) do
        love.graphics.setColor(element.color[1], element.color[2], element.color[3], element.opacity)
        
        if element.type == "circle" then
            love.graphics.circle("fill", element.x, element.y, element.radius)
        elseif element.type == "rectangle" then
            love.graphics.push()
            love.graphics.translate(element.x + element.width/2, element.y + element.height/2)
            love.graphics.rotate(element.rotation or 0)
            love.graphics.rectangle("fill", -element.width/2, -element.height/2, element.width, element.height)
            love.graphics.pop()
        elseif element.type == "line" then
            love.graphics.setLineWidth(element.width or 1)
            love.graphics.line(element.x1, element.y1, element.x2, element.y2)
        end
    end
    
    -- Restore previous state
    love.graphics.setColor(current_color)
end

-- Pure function to draw transition overlay
function UI.drawTransitionOverlay(transition_state, theme)
    if not transition_state or not transition_state.active then return end
    
    local screen_width = love.graphics.getWidth()
    local screen_height = love.graphics.getHeight()
    local current_color = {love.graphics.getColor()}
    
    local alpha = 1 - transition_state.progress
    if transition_state.type == "fade_in" then
        alpha = transition_state.progress
    end
    
    love.graphics.setColor(0, 0, 0, alpha)
    love.graphics.rectangle("fill", 0, 0, screen_width, screen_height)
    
    -- Restore previous state
    love.graphics.setColor(current_color)
end

-- Pure function to handle keyboard input
function UI.handleKeyboard(key, action, state, navigation_config)
    if action ~= "press" or not state or not navigation_config then 
        return state 
    end
    
    local new_state = {}
    for k, v in pairs(state) do
        new_state[k] = v
    end
    
    new_state.last_input_type = "keyboard"
    
    if key == "up" or key == "w" then
        if navigation_config.type == "list" or navigation_config.type == "buttons" then
            new_state.selected_index = math.max(1, (new_state.selected_index or 1) - 1)
        elseif navigation_config.type == "grid" then
            local current_row = math.floor(((new_state.selected_index or 1) - 1) / navigation_config.columns)
            if current_row > 0 then
                new_state.selected_index = (new_state.selected_index or 1) - navigation_config.columns
            end
        end
    elseif key == "down" or key == "s" then
        if navigation_config.type == "list" or navigation_config.type == "buttons" then
            new_state.selected_index = math.min(navigation_config.max_items or 1, (new_state.selected_index or 1) + 1)
        elseif navigation_config.type == "grid" then
            local max_items = navigation_config.max_items or 1
            local current_row = math.floor(((new_state.selected_index or 1) - 1) / navigation_config.columns)
            local max_rows = math.ceil(max_items / navigation_config.columns)
            if current_row < max_rows - 1 then
                new_state.selected_index = math.min(max_items, (new_state.selected_index or 1) + navigation_config.columns)
            end
        end
    elseif key == "left" or key == "a" then
        if navigation_config.type == "grid" then
            local current_col = ((new_state.selected_index or 1) - 1) % navigation_config.columns
            if current_col > 0 then
                new_state.selected_index = (new_state.selected_index or 1) - 1
            end
        end
    elseif key == "right" or key == "d" then
        if navigation_config.type == "grid" then
            local max_items = navigation_config.max_items or 1
            local current_col = ((new_state.selected_index or 1) - 1) % navigation_config.columns
            if current_col < navigation_config.columns - 1 and (new_state.selected_index or 1) < max_items then
                new_state.selected_index = (new_state.selected_index or 1) + 1
            end
        end
    elseif key == "return" or key == "space" then
        new_state.action_triggered = true
        new_state.selected_action = new_state.selected_index or 1
    elseif key == "escape" then
        new_state.back_triggered = true
    end
    
    return new_state
end

-- Pure function to handle mouse input
function UI.handleMouse(x, y, button, action, state, interactive_elements)
    if not state or not interactive_elements then 
        return state 
    end
    
    local new_state = {}
    for k, v in pairs(state) do
        new_state[k] = v
    end
    
    new_state.mouse_x = x
    new_state.mouse_y = y
    new_state.last_input_type = "mouse"
    
    -- Check for hover and clicks on interactive elements
    for i, element in ipairs(interactive_elements) do
        local is_inside = UI.isPointInRect(x, y, element.bounds)
        
        if is_inside then
            new_state.hovered_index = i
            
            if action == "press" and button == 1 then
                new_state.action_triggered = true
                new_state.selected_action = i
                new_state.selected_index = i
            end
        end
    end
    
    return new_state
end

-- Helper function to check if point is inside rectangle
function UI.isPointInRect(x, y, rect)
    return x >= rect.x and x <= rect.x + rect.width and 
           y >= rect.y and y <= rect.y + rect.height
end

-- Pure function to calculate grid layout for an item
function UI.calculateGridLayout(index, layout)
    local row = math.floor((index - 1) / layout.columns)
    local col = (index - 1) % layout.columns
    
    local x = layout.start_x + col * layout.item_spacing_x
    local y = layout.start_y + row * layout.item_spacing_y
    
    return {
        x = x,
        y = y,
        row = row,
        col = col
    }
end

-- Pure function to calculate list layout
function UI.calculateListLayout(item_count, container_bounds, item_height, spacing)
    local total_height = item_count * item_height + (item_count - 1) * spacing
    local start_y = container_bounds.y + (container_bounds.height - total_height) / 2
    
    return {
        x = container_bounds.x,
        start_y = start_y,
        width = container_bounds.width,
        item_height = item_height,
        item_spacing = item_height + spacing,
        text_padding = 10
    }
end

-- Helper function to get grid item at position
function UI.getGridItemAt(x, y, layout)
    if not layout then return nil end
    
    local col = math.floor((x - layout.start_x + layout.item_spacing_x/2) / layout.item_spacing_x)
    local row = math.floor((y - layout.start_y + layout.item_spacing_y/2) / layout.item_spacing_y)
    
    if col >= 0 and col < layout.columns and row >= 0 then
        local index = row * layout.columns + col + 1
        if index <= (layout.max_items or math.huge) then
            return index
        end
    end
    
    return nil
end

-- Helper function to get list item at position
function UI.getListItemAt(x, y, layout)
    if not layout then return nil end
    
    if x >= layout.x and x <= layout.x + layout.width then
        local relative_y = y - layout.start_y
        local index = math.floor(relative_y / layout.item_spacing) + 1
        
        if index >= 1 and index <= (layout.max_items or math.huge) then
            local item_y = layout.start_y + (index - 1) * layout.item_spacing
            if y >= item_y - layout.item_height/2 and y <= item_y + layout.item_height/2 then
                return index
            end
        end
    end
    
    return nil
end

-- Helper function to get button at position
function UI.getButtonAt(x, y, buttons_layout)
    if not buttons_layout or not buttons_layout.buttons then return nil end
    
    for i, button_bounds in ipairs(buttons_layout.buttons) do
        if UI.isPointInRect(x, y, button_bounds) then
            return i
        end
    end
    
    return nil
end

-- Pure function to draw a health bar
function UI.draw_health_bar(x, y, width, height, current_hp, max_hp, border_thickness, enable_pulse)
    if not x or not y or not width or not height or not current_hp or not max_hp then return end
    if max_hp <= 0 then return end
    
    local current_color = {love.graphics.getColor()}
    local current_line_width = love.graphics.getLineWidth()
    
    -- Default values for optional parameters
    border_thickness = border_thickness or 1
    enable_pulse = enable_pulse ~= false -- default to true unless explicitly false
    
    -- Draw semi-transparent background rectangle
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", x, y, width, height)
    
    -- Calculate health percentage and bar width
    local health_percentage = math.max(0, math.min(1, current_hp / max_hp))
    local bar_width = width * health_percentage
    
    if bar_width > 0 then
        -- Smoother color gradient calculation
        local red, green, blue = 1, 0, 0
        
        if health_percentage > 0.5 then
            -- Transition from yellow to green (50% to 100%)
            local t = (health_percentage - 0.5) * 2
            red = 1 - t
            green = 1
            blue = 0
        elseif health_percentage > 0.25 then
            -- Transition from red to yellow (25% to 50%)
            local t = (health_percentage - 0.25) * 4
            red = 1
            green = t
            blue = 0
        else
            -- Stay red (0% to 25%)
            red = 1
            green = 0
            blue = 0
        end
        
        -- Apply pulsing effect for low health
        local alpha = 1
        if enable_pulse and health_percentage <= 0.25 then
            local time = love.timer.getTime()
            local pulse_speed = 4 + (1 - health_percentage) * 6 -- Faster pulse at lower health
            alpha = 0.7 + 0.3 * math.sin(time * pulse_speed)
        end
        
        love.graphics.setColor(red, green, blue, alpha)
        
        -- Draw health bar fill
        love.graphics.rectangle("fill", x, y, bar_width, height)
    end
    
    -- Draw configurable white border
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(border_thickness)
    love.graphics.rectangle("line", x, y, width, height)
    
    -- Restore previous state
    love.graphics.setColor(current_color)
    love.graphics.setLineWidth(current_line_width)
end

return UI
