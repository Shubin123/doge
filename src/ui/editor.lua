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
    editor.selectedObject = editor.findObjectAtPosition(x - camera.pos.x, y - camera.pos.y)
    if button == 1 then -- Left mouse button
        editor.mouseX = x
        editor.mouseY = y
        editor.isPressed = true
        
        if editor.mode == "select" then
            -- Find object at mouse position
            

            if editor.selectedObject then
                -- Calculate drag offset
                if editor.selectedObject.type == "arch" then
                    editor.dragOffset.x = x - editor.selectedObject.pivot_x
                    editor.dragOffset.y = y - editor.selectedObject.pivot_y
                elseif editor.selectedObject.type == "tree" then
                    editor.dragOffset.x = x - editor.selectedObject.x
                    editor.dragOffset.y = y - editor.selectedObject.y
                end
            end
        elseif editor.mode == "create_arch" then
            -- Create new arch at mouse position
            -- print(x,y)
            map.createArches((x - camera.pos.x) / camera.zoom, (y - camera.pos.y) / camera.zoom)
            map_a = map.addMapToDynamicDrawList(map.arches, 0, 0, 1, 200) -- since the editor can modify this live this needs to be called again when redrawn at different position
        elseif editor.mode == "create_tree" then
            -- Create new tree at mouse position
            map.createTree((x - camera.pos.x - 50) / camera.zoom, (y - camera.pos.y - 50) / camera.zoom)
            map_b = map.addMapToDynamicDrawList(map.tree, 0, 0, 0.8, 240) -- since the editor can modify this live this needs to be called again when redrawn at different position
        end
    elseif button == 2 then                                               -- Right mouse button
        -- Delete object at position
        -- local objectToDelete = editor.findObjectAtPosition(x - camera.pos.x, y - camera.pos.y)
        if editor.selectedObject then
            editor.deleteObject(editor.selectedObject)
        end
    end
end

-- Handle mouse movement
function editor.mousemoved(x, y, dx, dy)
    editor.mouseX = x
    editor.mouseY = y
end

-- Handle mouse release
function editor.mousereleased(x, y, button)
    if button == 1 then
        editor.isPressed = false
        -- editor.selectedObject = nil
        editor.dragOffset = { x = 0, y = 0 }
    end
end

-- Find object at world position using physics world query
function editor.findObjectAtPosition(x, y)
    local foundObjects = {}

    -- Query a small area around the mouse position
    editor.world:queryBoundingBox(x - 20, y - 20, x + 20, y + 20, function(fixture)
        local userData = fixture:getUserData()

        if userData and type(userData) == "table" then
            if userData.type == "arch" then
                -- Find the arch object
                for _, arch in ipairs(editor.map.archInstances) do
                    if arch.id == userData.id then
                        table.insert(foundObjects, { object = arch, type = "arch", priority = 1 })
                        break
                    end
                end
            elseif userData.type == "tree" then
                -- Find the tree object
                for _, tree in ipairs(editor.map.treeInstances) do
                    if tree.id == userData.id then
                        table.insert(foundObjects, { object = tree, type = "tree", priority = 2 })
                        break
                    end
                end
            end
        end
        return true -- Continue querying
    end)

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
    -- if obj.type == "arch" then
    --     -- Remove from arch instances
    --     for i, arch in ipairs(editor.map.archInstances) do
    --         if arch.id == obj.id then
    --             arch:destroy()
    --             table.remove(editor.map.archInstances, i)
    --             break
    --         end
    --     end
    -- elseif obj.type == "tree" then
    --     -- Remove from tree instances
    --     for i, tree in ipairs(editor.map.treeInstances) do
    --         if tree.id == obj.id then
    --             tree:destroy()
    --             table.remove(editor.map.treeInstances, i)
    --             break
    --         end
    --     end
    -- end

    if obj then
        
    
        for k, arch in pairs(map.archInstances) do
            if arch == editor.selectedObject then
                table.remove(map.archInstances, k)
            end
        end
        for k, tree in pairs(map.treeInstances) do
            if tree == editor.selectedObject then
                table.remove(map.treeInstances, k)
            end
        end
        map_b = map.addMapToDynamicDrawList(map.tree, 0, 0, 0.8, 240)     -- this reloads trees draw
        map_a = map.addMapToDynamicDrawList(map.arches, 0, 0, 1, 200)     -- this reloads map that draws all arches
        editor.selectedObject.markedDestory = true
    end
end

-- Update function (call this in love.update)
function editor.update(dt)
    -- Move selected object if dragging
    -- if editor.isPressed and editor.selectedObject and editor.mode == "select" then
    if editor.selectedObject then
        -- local newX = editor.mouseX - editor.dragOffset.x
        -- local newY = editor.mouseY - editor.dragOffset.y

        if editor.selectedObject.move then
            -- print(editor.selectedObject[1])
            -- for k, v in pairs(editor.selectedObject) do
            --     print(k, v)
            -- end
            
            editor.selectedObject:move((editor.mouseX - camera.pos.x) / camera.zoom,
                (editor.mouseY - camera.pos.y) / camera.zoom)

            map_b = map.addMapToDynamicDrawList(map.tree, 0, 0, 0.8, 240) -- this reloads trees draw
            map_a = map.addMapToDynamicDrawList(map.arches, 0, 0, 1, 200) -- this reloads map that draws all arches
        end
        if editor.selectedObject.markedDestory then
            editor.selectedObject:destroy()
        end
    end
end

-- Handle keyboard input for mode switching
function editor.keypressed(key)
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

-- Debug drawing function
function editor.debugDraw()
    local font = love.graphics.getFont()

    -- Draw mode indicator
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Mode: " .. editor.mode, 10, 10)
    love.graphics.print("1: Select | 2: Create Arch | 3: Create Tree | RMB: Delete", 10, 30)

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

    -- Draw selected object highlight
    if editor.selectedObject then
        love.graphics.setColor(1, 0, 0, 0.8) -- Red
        if editor.selectedObject.type == "arch" then
            love.graphics.circle("line", editor.selectedObject.pivot_x, editor.selectedObject.pivot_y, 15)
            love.graphics.print("Selected Arch " .. editor.selectedObject.id, 10, 60)
        elseif editor.selectedObject.type == "tree" then
            love.graphics.circle("line", editor.selectedObject.x + 78, editor.selectedObject.y + 78, 15)
            love.graphics.print("Selected Tree " .. editor.selectedObject.id, 10, 60)
        end
    end

    -- Draw object counts
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Arches: " .. #editor.map.archInstances, 10, 80)
    love.graphics.print("Trees: " .. #editor.map.treeInstances, 10, 100)

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
