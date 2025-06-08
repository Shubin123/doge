local map_editor = {}
local map_loader = require("map_loader")
local map_manager = require("map_manager")
local map_serializer = require("map_serializer")

-- Editor state
local editor_state = {
    enabled = false,
    mode = "tile", -- "tile", "entity", "selection"
    current_map = nil,
    selected_tile_id = 1,
    selected_entity_type = "enemy",
    brush_size = 1,
    camera_lock = false,
    show_grid = true,
    show_debug = false,
    history = {},
    history_index = 0,
    max_history = 50,
    clipboard = nil
}

-- Tool configurations
local tools = {
    tile = {
        name = "Tile Brush",
        icon = "T",
        modes = {"paint", "erase", "fill", "pick"}
    },
    entity = {
        name = "Entity Tool",
        icon = "E",
        modes = {"place", "move", "delete"}
    },
    selection = {
        name = "Selection Tool", 
        icon = "S",
        modes = {"select", "move", "copy", "paste"}
    }
}

local current_tool_mode = "paint"
local selection_area = {x1 = 0, y1 = 0, x2 = 0, y2 = 0, active = false}

-- Initialize editor
function map_editor.initialize()
    print("Map Editor initialized. Press 'e' to toggle editor mode.")
end

-- Toggle editor mode
function map_editor.toggle()
    editor_state.enabled = not editor_state.enabled
    
    if editor_state.enabled then
        -- Save current map state for undo
        map_editor.save_state()
        print("Map Editor ENABLED")
        print("Controls:")
        print("  1-9: Select tile ID")
        print("  Q/E: Change brush size")
        print("  Tab: Switch tool mode")
        print("  G: Toggle grid")
        print("  Ctrl+S: Quick save")
        print("  Ctrl+Z: Undo")
        print("  Ctrl+Y: Redo")
    else
        print("Map Editor DISABLED")
    end
    
    return editor_state.enabled
end

-- Get current editor state
function map_editor.is_enabled()
    return editor_state.enabled
end

-- Save state for undo system
function map_editor.save_state()
    if not editor_state.current_map then return end
    
    -- Remove states after current index (for branching undo)
    while #editor_state.history > editor_state.history_index do
        table.remove(editor_state.history)
    end
    
    -- Deep copy current map state
    local state = {
        tile_data = {},
        entities = {}
    }
    
    -- Copy tile data
    for y, row in pairs(editor_state.current_map.tile_data) do
        state.tile_data[y] = {}
        for x, tile in pairs(row) do
            state.tile_data[y][x] = tile
        end
    end
    
    -- Copy entity data
    local map_def = editor_state.current_map.definition
    for i, enemy in ipairs(map_def.enemies) do
        table.insert(state.entities, {type = "enemy", x = enemy.x, y = enemy.y, data = enemy})
    end
    for i, item in ipairs(map_def.collectibles) do
        table.insert(state.entities, {type = "collectible", x = item.x, y = item.y, data = item})
    end
    
    table.insert(editor_state.history, state)
    editor_state.history_index = #editor_state.history
    
    -- Limit history size
    if #editor_state.history > editor_state.max_history then
        table.remove(editor_state.history, 1)
        editor_state.history_index = #editor_state.history
    end
end

-- Undo last action
function map_editor.undo()
    if editor_state.history_index > 1 then
        editor_state.history_index = editor_state.history_index - 1
        map_editor.restore_state(editor_state.history[editor_state.history_index])
        print("Undo: Restored previous state")
        return true
    end
    return false
end

-- Redo last undone action
function map_editor.redo()
    if editor_state.history_index < #editor_state.history then
        editor_state.history_index = editor_state.history_index + 1
        map_editor.restore_state(editor_state.history[editor_state.history_index])
        print("Redo: Restored next state")
        return true
    end
    return false
end

-- Restore state from history
function map_editor.restore_state(state)
    if not editor_state.current_map or not state then return end
    
    -- Restore tile data
    editor_state.current_map.tile_data = {}
    for y, row in pairs(state.tile_data) do
        editor_state.current_map.tile_data[y] = {}
        for x, tile in pairs(row) do
            editor_state.current_map.tile_data[y][x] = tile
        end
    end
    
    -- Restore entities (simplified - would need full entity management integration)
    local map_def = editor_state.current_map.definition
    map_def.enemies = {}
    map_def.collectibles = {}
    
    for _, entity in ipairs(state.entities) do
        if entity.type == "enemy" then
            table.insert(map_def.enemies, {x = entity.x, y = entity.y, type = entity.data.type})
        elseif entity.type == "collectible" then
            table.insert(map_def.collectibles, {x = entity.x, y = entity.y, type = entity.data.type})
        end
    end
    
    -- Respawn entities
    map_manager.spawn_map_entities()
end

-- Handle mouse input for editing
function map_editor.handle_mouse(x, y, button, is_pressed)
    if not editor_state.enabled or not editor_state.current_map then return false end
    
    -- Convert screen to world coordinates
    local world_x, world_y = camera.screenToWorld(x, y)
    
    if editor_state.mode == "tile" then
        map_editor.handle_tile_editing(world_x, world_y, button, is_pressed)
    elseif editor_state.mode == "entity" then
        map_editor.handle_entity_editing(world_x, world_y, button, is_pressed)
    elseif editor_state.mode == "selection" then
        map_editor.handle_selection_editing(world_x, world_y, button, is_pressed)
    end
    
    return true -- Editor consumed the input
end

-- Handle tile editing
function map_editor.handle_tile_editing(world_x, world_y, button, is_pressed)
    if button ~= 1 and button ~= 2 then return end
    
    local map_obj = editor_state.current_map
    local map_def = map_obj.definition
    
    -- Convert to tile coordinates
    local tile_x = math.floor((world_x - map_obj.world_x) / map_def.tile_width) + 1
    local tile_y = math.floor((world_y - map_obj.world_y) / map_def.tile_height) + 1
    
    if tile_x < 1 or tile_x > map_obj.width or tile_y < 1 or tile_y > map_obj.height then
        return
    end
    
    if current_tool_mode == "paint" then
        if button == 1 then -- Left click - paint
            map_editor.paint_tiles(tile_x, tile_y, editor_state.selected_tile_id, editor_state.brush_size)
        elseif button == 2 then -- Right click - erase
            map_editor.paint_tiles(tile_x, tile_y, 0, editor_state.brush_size)
        end
    elseif current_tool_mode == "pick" and button == 1 then
        -- Pick tile under cursor
        if map_obj.tile_data[tile_y] and map_obj.tile_data[tile_y][tile_x] then
            editor_state.selected_tile_id = map_obj.tile_data[tile_y][tile_x]
            print("Picked tile ID: " .. editor_state.selected_tile_id)
        end
    elseif current_tool_mode == "fill" and button == 1 then
        -- Flood fill
        map_editor.flood_fill(tile_x, tile_y, editor_state.selected_tile_id)
    end
end

-- Paint tiles with brush
function map_editor.paint_tiles(center_x, center_y, tile_id, brush_size)
    if not editor_state.current_map then return end
    
    local map_obj = editor_state.current_map
    local radius = math.floor(brush_size / 2)
    local changes_made = false
    
    for dy = -radius, radius do
        for dx = -radius, radius do
            local x = center_x + dx
            local y = center_y + dy
            
            -- Check if within brush radius (circular brush)
            if dx * dx + dy * dy <= radius * radius then
                if x >= 1 and x <= map_obj.width and y >= 1 and y <= map_obj.height then
                    if not map_obj.tile_data[y] then map_obj.tile_data[y] = {} end
                    
                    if map_obj.tile_data[y][x] ~= tile_id then
                        map_obj.tile_data[y][x] = tile_id
                        changes_made = true
                    end
                end
            end
        end
    end
    
    if changes_made then
        map_editor.save_state()
    end
end

-- Flood fill algorithm
function map_editor.flood_fill(start_x, start_y, new_tile_id)
    local map_obj = editor_state.current_map
    if not map_obj.tile_data[start_y] then return end
    
    local original_tile_id = map_obj.tile_data[start_y][start_x]
    if original_tile_id == new_tile_id then return end
    
    local stack = {{start_x, start_y}}
    local filled = {}
    
    while #stack > 0 do
        local current = table.remove(stack)
        local x, y = current[1], current[2]
        
        if x < 1 or x > map_obj.width or y < 1 or y > map_obj.height then
            goto continue
        end
        
        local key = x .. "," .. y
        if filled[key] then goto continue end
        
        if not map_obj.tile_data[y] then map_obj.tile_data[y] = {} end
        local current_tile = map_obj.tile_data[y][x] or 0
        
        if current_tile == original_tile_id then
            map_obj.tile_data[y][x] = new_tile_id
            filled[key] = true
            
            -- Add neighbors to stack
            table.insert(stack, {x + 1, y})
            table.insert(stack, {x - 1, y})
            table.insert(stack, {x, y + 1})
            table.insert(stack, {x, y - 1})
        end
        
        ::continue::
    end
    
    map_editor.save_state()
    print("Flood fill completed")
end

-- Handle entity editing
function map_editor.handle_entity_editing(world_x, world_y, button, is_pressed)
    if button ~= 1 then return end
    
    if current_tool_mode == "place" then
        -- Place new entity
        local map_def = editor_state.current_map.definition
        
        if editor_state.selected_entity_type == "enemy" then
            table.insert(map_def.enemies, {x = world_x, y = world_y, type = "basic"})
            print("Placed enemy at " .. world_x .. ", " .. world_y)
        elseif editor_state.selected_entity_type == "collectible" then
            table.insert(map_def.collectibles, {x = world_x, y = world_y, type = "coin"})
            print("Placed collectible at " .. world_x .. ", " .. world_y)
        end
        
        -- Respawn entities to show changes immediately
        map_manager.spawn_map_entities()
        map_editor.save_state()
    end
end

-- Handle selection editing
function map_editor.handle_selection_editing(world_x, world_y, button, is_pressed)
    if button == 1 then
        if not selection_area.active then
            -- Start selection
            selection_area.x1 = world_x
            selection_area.y1 = world_y
            selection_area.x2 = world_x
            selection_area.y2 = world_y
            selection_area.active = true
        else
            -- Update selection end point
            selection_area.x2 = world_x
            selection_area.y2 = world_y
        end
    end
end

-- Handle keyboard input
function map_editor.handle_key(key, is_pressed)
    if not editor_state.enabled then return false end
    
    if not is_pressed then return false end
    
    -- Tool switching
    if key == "tab" then
        local modes = tools[editor_state.mode].modes
        local current_index = 1
        for i, mode in ipairs(modes) do
            if mode == current_tool_mode then
                current_index = i
                break
            end
        end
        current_tool_mode = modes[(current_index % #modes) + 1]
        print("Tool mode: " .. current_tool_mode)
        return true
    end
    
    -- Mode switching
    if key == "t" then
        editor_state.mode = "tile"
        print("Mode: Tile editing")
        return true
    elseif key == "r" then
        editor_state.mode = "entity"
        print("Mode: Entity editing")
        return true
    elseif key == "s" and love.keyboard.isDown("lctrl", "rctrl") then
        -- Quick save
        map_editor.quick_save()
        return true
    elseif key == "z" and love.keyboard.isDown("lctrl", "rctrl") then
        map_editor.undo()
        return true
    elseif key == "y" and love.keyboard.isDown("lctrl", "rctrl") then
        map_editor.redo()
        return true
    end
    
    -- Tile selection (1-9)
    local tile_num = tonumber(key)
    if tile_num and tile_num >= 1 and tile_num <= 9 then
        editor_state.selected_tile_id = tile_num
        print("Selected tile ID: " .. tile_num)
        return true
    end
    
    -- Brush size
    if key == "q" then
        editor_state.brush_size = math.max(1, editor_state.brush_size - 1)
        print("Brush size: " .. editor_state.brush_size)
        return true
    elseif key == "e" then
        editor_state.brush_size = math.min(10, editor_state.brush_size + 1)
        print("Brush size: " .. editor_state.brush_size)
        return true
    end
    
    -- Grid toggle
    if key == "g" then
        editor_state.show_grid = not editor_state.show_grid
        print("Grid: " .. (editor_state.show_grid and "ON" or "OFF"))
        return true
    end
    
    return false
end

-- Update editor (call every frame)
function map_editor.update(dt)
    if not editor_state.enabled then return end
    
    -- Update current map reference
    editor_state.current_map = map_manager.get_current_map()
    
    -- Handle continuous mouse input for painting
    if love.mouse.isDown(1) or love.mouse.isDown(2) then
        local mx, my = love.mouse.getPosition()
        map_editor.handle_mouse(mx, my, love.mouse.isDown(1) and 1 or 2, true)
    end
end

-- Draw editor UI and overlays
function map_editor.draw()
    if not editor_state.enabled then return end
    
    -- Draw grid
    if editor_state.show_grid and editor_state.current_map then
        map_editor.draw_grid()
    end
    
    -- Draw selection area
    if selection_area.active then
        love.graphics.push()
        camera.apply()
        love.graphics.setColor(1, 1, 0, 0.3)
        love.graphics.rectangle("fill", 
            math.min(selection_area.x1, selection_area.x2),
            math.min(selection_area.y1, selection_area.y2),
            math.abs(selection_area.x2 - selection_area.x1),
            math.abs(selection_area.y2 - selection_area.y1)
        )
        love.graphics.setColor(1, 1, 0, 1)
        love.graphics.rectangle("line", 
            math.min(selection_area.x1, selection_area.x2),
            math.min(selection_area.y1, selection_area.y2),
            math.abs(selection_area.x2 - selection_area.x1),
            math.abs(selection_area.y2 - selection_area.y1)
        )
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.pop()
    end
    
    -- Draw UI
    map_editor.draw_ui()
end

-- Draw grid overlay
function map_editor.draw_grid()
    local map_obj = editor_state.current_map
    local map_def = map_obj.definition
    
    love.graphics.push()
    camera.apply()
    
    love.graphics.setColor(1, 1, 1, 0.2)
    love.graphics.setLineWidth(1)
    
    -- Vertical lines
    for x = 0, map_obj.width do
        local world_x = map_obj.world_x + x * map_def.tile_width
        love.graphics.line(world_x, map_obj.world_y, world_x, map_obj.world_y + map_obj.height * map_def.tile_height)
    end
    
    -- Horizontal lines
    for y = 0, map_obj.height do
        local world_y = map_obj.world_y + y * map_def.tile_height
        love.graphics.line(map_obj.world_x, world_y, map_obj.world_x + map_obj.width * map_def.tile_width, world_y)
    end
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.pop()
end

-- Draw editor UI
function map_editor.draw_ui()
    local ui_y = 10
    
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 10, ui_y, 300, 120)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("line", 10, ui_y, 300, 120)
    
    ui_y = ui_y + 10
    love.graphics.print("MAP EDITOR", 15, ui_y)
    ui_y = ui_y + 20
    love.graphics.print("Mode: " .. editor_state.mode .. " (" .. current_tool_mode .. ")", 15, ui_y)
    ui_y = ui_y + 15
    love.graphics.print("Tile ID: " .. editor_state.selected_tile_id .. " | Brush: " .. editor_state.brush_size, 15, ui_y)
    ui_y = ui_y + 15
    love.graphics.print("Entity: " .. editor_state.selected_entity_type, 15, ui_y)
    ui_y = ui_y + 15
    love.graphics.print("History: " .. editor_state.history_index .. "/" .. #editor_state.history, 15, ui_y)
    ui_y = ui_y + 15
    
    if editor_state.current_map then
        love.graphics.print("Map: " .. editor_state.current_map.id, 15, ui_y)
    end
end

-- Quick save current map
function map_editor.quick_save()
    if not editor_state.current_map then
        print("No map to save")
        return false
    end
    
    local success = map_serializer.quick_save(editor_state.current_map, 1)
    if success then
        print("Map quick-saved successfully")
    end
    return success
end

-- Create new map
function map_editor.create_new_map(id, name, width, height)
    local template = map_serializer.create_template(id, name, width, height)
    
    -- Register with map loader
    map_loader.register_map(template)
    
    -- Switch to new map
    map_manager.loadMap(id)
    
    return true
end

-- Load map from file
function map_editor.load_map_file(file_path)
    local loaded_data = map_serializer.load_map(file_path)
    if not loaded_data then
        print("Failed to load map from: " .. file_path)
        return false
    end
    
    -- Register loaded map
    map_loader.register_map(loaded_data.definition)
    
    -- Switch to loaded map
    map_manager.loadMap(loaded_data.definition.id)
    
    return true
end

-- Export current map
function map_editor.export_map(file_path, format)
    if not editor_state.current_map then
        print("No map to export")
        return false
    end
    
    format = format or "binary"
    
    if format == "lua" then
        return map_serializer.export_as_lua(editor_state.current_map, file_path)
    else
        return map_serializer.save_map(editor_state.current_map, file_path, format)
    end
end

return map_editor