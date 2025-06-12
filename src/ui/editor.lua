local editor = {}

-- Initialize the editor module
function editor.load(world, mapModule)
    editor.world = world
    editor.map = mapModule
    editor.selectedObject = nil
    editor.mouseX = 0
    editor.mouseY = 0
    editor.isPressed = false
    editor.dragOffset = { x = 0, y = 0 }
    editor.mode = "select" -- "select", "create_arch", "create_tree"
    editor.enabled = false -- Editor is disabled by default
end

-- Set editor mode
function editor.setMode(mode)
    editor.mode = mode
end

-- Get editor mode
function editor.getMode()
    return editor.mode
end

-- Handle mouse press events
function editor.mousepressed(x, y, button)
    if not editor.enabled then return end -- Only process if editor is enabled
    
    editor.selectedObject = editor.findObjectAtPosition(x - camera.pos.x, y - camera.pos.y)
    if button == 1 then -- Left mouse button
        editor.mouseX = x
        editor.mouseY = y
        editor.isPressed = true
        
        if editor.mode == "select" then
            -- Find object at mouse position
            

            if editor.selectedObject then
                -- Calculate drag offset in world coordinates
                local worldMouseX = (x - camera.pos.x) / camera.zoom
                local worldMouseY = (y - camera.pos.y) / camera.zoom
                
                if editor.selectedObject.type == "arch" then
                    editor.dragOffset.x = worldMouseX - editor.selectedObject.pivot_x
                    editor.dragOffset.y = worldMouseY - editor.selectedObject.pivot_y
                elseif editor.selectedObject.type == "tree" then
                    editor.dragOffset.x = worldMouseX - editor.selectedObject.x
                    editor.dragOffset.y = worldMouseY - editor.selectedObject.y
                end
            end
        elseif editor.mode == "create_arch" then
            -- Create new arch at mouse position
            -- print(x,y)
            map.createArches((x - camera.pos.x) / camera.zoom, (y - camera.pos.y) / camera.zoom)
            map_a = map.addMapToDynamicDrawList(map.arches, 0, 0, 1, 200) -- since the editor can modify this live this needs to be called again when redrawn at different position
        elseif editor.mode == "create_tree" then
            -- Create new tree at mouse position
            map.createTree((x - camera.pos.x) / camera.zoom, (y - camera.pos.y) / camera.zoom)
            map_b = map.addMapToDynamicDrawList(map.tree, 0, 0, 0.8, 240) -- since the editor can modify this live this needs to be called again when redrawn at different position
        end
    elseif button == 2 and editor.mode == "select" then -- Right mouse button (only in select mode)
        -- Delete object at position (only in select/move mode)
        if editor.selectedObject then
            editor.deleteObject(editor.selectedObject)
        end
    end
end

-- Handle mouse movement
function editor.mousemoved(x, y, dx, dy)
    editor.mouseX = x
    editor.mouseY = y
    -- Note: Hover detection is now handled by visual glow effect in select mode
end

-- Handle mouse release
function editor.mousereleased(x, y, button)
    if button == 1 then
        editor.isPressed = false
        -- editor.selectedObject = nil
        editor.dragOffset = { x = 0, y = 0 }
    end
end

-- Find object at world position using visual bounds instead of physics
function editor.findObjectAtPosition(x, y)
    local foundObjects = {}

    -- Check arches (use visual bounds around pivot point)
    for _, arch in ipairs(editor.map.archInstances) do
        if arch.active then
            -- Arch visual size is 98x128, centered on pivot
            local visual_left = arch.pivot_x - 49  -- 98/2
            local visual_right = arch.pivot_x + 49
            local visual_top = arch.pivot_y - 64   -- 128/2
            local visual_bottom = arch.pivot_y + 64
            
            if x >= visual_left and x <= visual_right and y >= visual_top and y <= visual_bottom then
                table.insert(foundObjects, { object = arch, type = "arch", priority = 1 })
            end
        end
    end

    -- Check trees (use visual bounds around position)
    for _, tree in ipairs(editor.map.treeInstances) do
        if tree.active then
            -- Tree visual size is 156x156, offset by -78,-78 from tree.x,tree.y
            local visual_left = tree.x - 78   -- visual offset
            local visual_right = tree.x + 78  -- 156/2 = 78
            local visual_top = tree.y - 78
            local visual_bottom = tree.y + 78
            
            if x >= visual_left and x <= visual_right and y >= visual_top and y <= visual_bottom then
                table.insert(foundObjects, { object = tree, type = "tree", priority = 2 })
            end
        end
    end

    -- Return the highest priority object (arch before tree)
    if #foundObjects > 0 then
        table.sort(foundObjects, function(a, b) return a.priority < b.priority end)
        local result = foundObjects[1].object
        result.type = foundObjects[1].type
        return result
    end

    return nil
end

-- Delete an object
function editor.deleteObject(obj)
    if not obj then return end
    
    -- Properly destroy and remove the object
    if obj.type == "arch" then
        -- Remove from arch instances
        for i, arch in ipairs(editor.map.archInstances) do
            if arch.id == obj.id then
                arch:destroy() -- Clean up physics bodies
                table.remove(editor.map.archInstances, i)
                break
            end
        end
        -- Refresh arch drawing list
        map_a = map.addMapToDynamicDrawList(map.arches, 0, 0, 1, 200)
        
    elseif obj.type == "tree" then
        -- Remove from tree instances
        for i, tree in ipairs(editor.map.treeInstances) do
            if tree.id == obj.id then
                tree:destroy() -- Clean up physics bodies
                table.remove(editor.map.treeInstances, i)
                break
            end
        end
        -- Refresh tree drawing list
        map_b = map.addMapToDynamicDrawList(map.tree, 0, 0, 0.8, 240)
    end
    
    -- Clear selection after deletion
    editor.selectedObject = nil
end

-- Update function (call this in love.update)
function editor.update(dt)
    if not editor.enabled then return end -- Only update if editor is enabled
    
    -- Move selected object if dragging (only when mouse is pressed and in select mode)
    if editor.isPressed and editor.selectedObject and editor.mode == "select" then
        if editor.selectedObject.move then
            -- Calculate new position using drag offset
            local worldMouseX = (editor.mouseX - camera.pos.x) / camera.zoom
            local worldMouseY = (editor.mouseY - camera.pos.y) / camera.zoom
            
            local newX = worldMouseX - editor.dragOffset.x
            local newY = worldMouseY - editor.dragOffset.y
            
            -- Move object to new position
            if editor.selectedObject.type == "arch" then
                editor.selectedObject:move(newX, newY)
            elseif editor.selectedObject.type == "tree" then
                editor.selectedObject:move(newX, newY)
            end

            map_b = map.addMapToDynamicDrawList(map.tree, 0, 0, 0.8, 240) -- this reloads trees draw
            map_a = map.addMapToDynamicDrawList(map.arches, 0, 0, 1, 200) -- this reloads map that draws all arches
        end
    end
end

-- Enable/disable editor
function editor.setEnabled(enabled)
    editor.enabled = enabled
    if not enabled then
        editor.selectedObject = nil -- Clear selection when disabling
    end
end

function editor.isEnabled()
    return editor.enabled
end

-- Handle keyboard input for mode switching
function editor.keypressed(key)
    if not editor.enabled then return end -- Only process keys if editor is enabled
    
    if key == "1" then
        editor.setMode("select")
    elseif key == "2" then
        editor.setMode("create_arch")
    elseif key == "3" then
        editor.setMode("create_tree")
    elseif key == "escape" then
        editor.setMode("select")
        editor.selectedObject = nil
    end
end

-- Convert world coordinates to screen coordinates
local function worldToScreen(worldX, worldY)
    -- Apply camera transformation
    local screenX = (worldX * camera.zoom) + camera.pos.x
    local screenY = (worldY * camera.zoom) + camera.pos.y
    return screenX, screenY
end

-- Draw glow effect for objects (renders on top of all game effects)
local function drawObjectGlow()
    if not (editor.enabled and editor.mode == "select") then
        return
    end
    
    -- Set additive blend mode for glow effect
    love.graphics.setBlendMode("add")
    
    -- Draw glow for arches
    for _, arch in ipairs(editor.map.archInstances) do
        if arch.active then
            local visual = arch:getComponent("visual")
            if visual then
                local visual_x = arch.pivot_x + visual.offset_x
                local visual_y = arch.pivot_y + visual.offset_y
                local screenX, screenY = worldToScreen(visual_x, visual_y)
                
                -- Create multiple glow layers for CSGO-style effect
                for i = 1, 3 do
                    local glow_scale = camera.zoom * (1.0 + (i * 0.1)) -- 1.1, 1.2, 1.3
                    local glow_alpha = 0.3 - (i * 0.08) -- 0.22, 0.14, 0.06
                    
                    love.graphics.setColor(0.2, 0.8, 1.0, glow_alpha)
                    love.graphics.draw(
                        editor.map.tiles3.tilesetImage,
                        editor.map.tiles3.quads[visual.tileId],
                        screenX,
                        screenY,
                        arch.rotation,
                        glow_scale,
                        glow_scale,
                        49, -- offset to center (98/2)
                        64  -- offset to center (128/2)
                    )
                end
            end
        end
    end
    
    -- Draw glow for trees
    for _, tree in ipairs(editor.map.treeInstances) do
        if tree.active then
            local visual = tree:getComponent("visual")
            if visual then
                local visual_x = tree.x + visual.offset_x
                local visual_y = tree.y + visual.offset_y
                local screenX, screenY = worldToScreen(visual_x, visual_y)
                
                -- Create multiple glow layers for CSGO-style effect
                for i = 1, 3 do
                    local glow_scale = camera.zoom * visual.scale * (1.0 + (i * 0.1)) -- 1.1, 1.2, 1.3
                    local glow_alpha = 0.3 - (i * 0.08) -- 0.22, 0.14, 0.06
                    
                    love.graphics.setColor(0.2, 0.8, 1.0, glow_alpha)
                    love.graphics.draw(
                        editor.map.tiles4.tilesetImage,
                        editor.map.tiles4.quads[visual.tileId],
                        screenX,
                        screenY,
                        tree.rotation,
                        glow_scale,
                        glow_scale,
                        78, -- offset to center (156/2)
                        78  -- offset to center (156/2)
                    )
                end
            end
        end
    end
    
    -- Reset blend mode
    love.graphics.setBlendMode("alpha")
end

-- Debug drawing function
function editor.debugDraw()
    local screenHeight = love.graphics.getHeight()
    local bottomY = screenHeight - 120 -- Start from bottom, leave some margin

    if not editor.enabled then
        love.graphics.setColor(1, 1, 1, 1)
        return
    end
    
    -- Draw glow effects on top of all game rendering (only if editor is enabled)
    drawObjectGlow()
    
    -- Draw mode indicator
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Mode: " .. editor.mode, 10, bottomY + 20)
    love.graphics.print("1: Select | 2: Create Arch | 3: Create Tree | RMB: Delete (select mode only)", 10, bottomY + 40)

    -- Draw mouse cursor based on mode
    if editor.mode == "select" then
        love.graphics.setColor(1, 1, 0, 0.7) -- Yellow
        love.graphics.circle("line", editor.mouseX, editor.mouseY, 8)
    elseif editor.mode == "create_arch" then
        love.graphics.setColor(0, 1, 0, 0.7) -- Green
        love.graphics.circle("fill", editor.mouseX, editor.mouseY, 5)
        love.graphics.print("Arch", editor.mouseX + 10, editor.mouseY - 5)
    elseif editor.mode == "create_tree" then
        love.graphics.setColor(0, 0, 1, 0.7) -- Blue
        love.graphics.circle("fill", editor.mouseX, editor.mouseY, 5)
        love.graphics.print("Tree", editor.mouseX + 10, editor.mouseY - 5)
    end
    
    -- Draw selected object highlight with proper coordinate transformation
    if editor.selectedObject then
        love.graphics.setColor(1, 0, 0, 0.8) -- Red
        love.graphics.setLineWidth(2)
        if editor.selectedObject.type == "arch" then
            local screenX, screenY = worldToScreen(editor.selectedObject.pivot_x, editor.selectedObject.pivot_y)
            love.graphics.circle("line", screenX, screenY, 18 * camera.zoom)
            love.graphics.print("Selected Arch " .. editor.selectedObject.id, 10, bottomY + 60)
        elseif editor.selectedObject.type == "tree" then
            local screenX, screenY = worldToScreen(editor.selectedObject.x + 78, editor.selectedObject.y + 78)
            love.graphics.circle("line", screenX, screenY, 22 * camera.zoom)
            love.graphics.print("Selected Tree " .. editor.selectedObject.id, 10, bottomY + 60)
        end
        love.graphics.setLineWidth(1)
    end

    -- Draw object counts and instructions
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Arches: " .. #editor.map.archInstances, 10, bottomY + 80)
    love.graphics.print("Trees: " .. #editor.map.treeInstances, 10, bottomY + 100)
    
    -- Show glow effect info
    if editor.mode == "select" then
        love.graphics.setColor(0.2, 0.8, 1.0, 1)
        love.graphics.print("Objects glow cyan when hoverable - Click to select and drag", 200, bottomY + 60)
    end

    love.graphics.setColor(1, 1, 1, 1) -- Reset color
end

-- Get selected object info
function editor.getSelectedObject()
    return editor.selectedObject
end

-- Clear selection
function editor.clearSelection()
    editor.selectedObject = nil
end

return editor
