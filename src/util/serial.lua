-- Enhanced serial module with map data serialization
local serial = {}

function serial.create()
    local game_state = {}

    -- Update local player from physics before capturing
    renderer.updateLocalPlayerFromPhysics()

    -- Capture player state
    game_state.player = renderer.local_player_state

    -- Capture enemy data from physics bodies
    game_state.enemies = {}
    if enemies_bods then
        for i = 1, #enemies_bods do
            local ex, ey = enemies_bods[i]:getX(), enemies_bods[i]:getY()
            game_state.enemies[i] = {
                x = ex,
                y = ey,
                active = true
            }
        end
    end

    -- Capture coin data from physics bodies
    game_state.coins = {}
    if coin_bods then
        for i = 1, #coin_bods do
            local cx, cy = coin_bods[i]:getX(), coin_bods[i]:getY()
            game_state.coins[i] = {
                x = cx,
                y = cy,
                active = true
            }
        end
    end

    -- Capture fire effects
    game_state.fire_effects = fire.getNetworkData() or {}

    -- NEW: Capture map data
    game_state.map_data = serial.captureMapData()
    -- Capture command blocks (using the same serializable format as networking)
    game_state.command_blocks = command.getCommandBlocks()

    -- Capture additional game state data
    game_state.game_data = {
        level = var.level or 1,
        score = var.score or 0,
        time_played = var.time_played or 0,
        difficulty = var.difficulty or 1,
        -- Add any other global game variables you want to save
    }

    -- Add metadata
    game_state.metadata = {
        version = "1.1", -- Incremented version for map data support
        timestamp = os.time(),
        save_type = "offline"
    }

    return game_state
end

-- NEW: Function to capture map data including arches and trees
function serial.captureMapData()
    local map_data = {}
    
    -- Capture base tile map data if map module is available
    if map and map.map and map.map.tileData then
        map_data.base_tiles = {
            width = map.map.width,
            height = map.map.height,
            tile_data = {}
        }
        
        -- Deep copy tile data
        for y = 1, map.map.height do
            map_data.base_tiles.tile_data[y] = {}
            for x = 1, map.map.width do
                map_data.base_tiles.tile_data[y][x] = map.map.tileData[y] and map.map.tileData[y][x] or 0
            end
        end
    end
    
    -- Capture arch instances
    map_data.arches = {}
    if map and map.archInstances then
        for i, arch in ipairs(map.archInstances) do
            map_data.arches[i] = {
                pivot_x = arch.pivot_x,
                pivot_y = arch.pivot_y,
                id = arch.id,
                visual_offset_x = arch.visual_offset_x,
                visual_offset_y = arch.visual_offset_y
            }
        end
    end
    
    -- Capture tree instances
    map_data.trees = {}
    if map and map.treeInstances then
        for i, tree in ipairs(map.treeInstances) do
            map_data.trees[i] = {
                x = tree.x,
                y = tree.y,
                id = tree.id
            }
        end
    end
    
    return map_data
end




function serial.apply(game_state)
    -- Validate the save data
    if not game_state or not game_state.metadata or game_state.metadata.save_type ~= "offline" then
        return false, "Invalid save data"
    end

    -- Apply player state
    if game_state.player then
        -- Set player position and state
        if player.body then
            player.body:setPosition(game_state.player.x, game_state.player.y)
        end

        -- Restore player health and other stats
        player.health = game_state.player.health or 100

        -- Apply any other player-specific data
        renderer.local_player_state = game_state.player
    end

    -- Restore enemies
    if game_state.enemies then
        -- Clear existing enemies first
        if enemies_bods then
            for i = 1, #enemies_bods do
                if enemies_bods[i] then
                    enemies_bods[i]:destroy()
                end
            end
        end
        enemies_bods = {}

        -- Recreate enemies from save data
        for i, enemy_data in pairs(game_state.enemies) do
            if enemy_data.active then
                enemy.addEnemy(enemy_data.x, enemy_data.y)
            end
        end
    end

    -- Restore coins
    if game_state.coins then
        -- Clear existing coins first
        if coin_bods then
            for i = 1, #coin_bods do
                if coin_bods[i] then
                    coin_bods[i]:destroy()
                end
            end
        end
        coin_bods = {}

        -- Recreate coins from save data
        for i, coin_data in pairs(game_state.coins) do
            if coin_data.active then
                -- Create new coin body (adapt to your coin creation system)
                local coin_body = love.physics.newBody(world, coin_data.x, coin_data.y, "static")
                -- Add appropriate shape and fixture based on your coin system
                _fixture = love.physics.newFixture(coin_body, love.physics.newCircleShape(5))
                _fixture:setGroupIndex(69)

                table.insert(coin_bods, coin_body)
            end
        end
    end

    -- NEW: Restore map data
    if game_state.map_data then
        local success = map.restore(game_state.map_data)
        if not success then
            return false, "Failed to restore map data"
        end
    end
    if game_state.command_blocks then
        command.setCommandBlocks(game_state.command_blocks)
    end

    -- Restore fire effects (commented out in original)
    -- if game_state.fire_effects then
    --     fire.loadNetworkData(game_state.fire_effects)
    -- end

    -- Restore game data
    if game_state.game_data then
        var.level = game_state.game_data.level or 1
        var.score = game_state.game_data.score or 0
        var.time_played = game_state.game_data.time_played or 0
        var.difficulty = game_state.game_data.difficulty or 1
        -- Restore other game variables as needed
    end

    return true, "Save loaded successfully"
end

-- Save game state to file
function serial.saveToFile(filename)
    local game_state = serial.create()

    -- Convert to JSON and compress
    local json_string = json.encode(game_state)
    local compressed_data = love.data.compress("string", "zlib", json_string, 9)

    -- Write to file
    local f = io.open(filename, "w")
    if not f then
        return false, "Failed to open file for writing"
    end

    f:write(compressed_data) -- 3x smaller than raw json even on small data
    f:close()

    return true, "Game saved successfully"
end

function serial.saveToFileUncompressed(filename)
    local game_state = serial.create()

    -- Convert to JSON and compress
    local json_string = json.encode(game_state)
    -- local compressed_data = love.data.compress("string", "zlib", json_string, 9)

    -- Write to file
    local f = io.open(filename, "w")
    if not f then
        return false, "Failed to open file for writing"
    end

    f:write(json_string) -- 3x smaller than raw json even on small data
    f:close()

    return true, "Game saved successfully"
end

-- Load game state from file
function serial.loadFromFile(filename)
    -- Check if file exists by trying to open it
    local f = io.open(filename, "r")
    if not f then
        return false, "Save file not found"
    end
    
    -- Read compressed data from file
    local compressed_data = f:read("*all")
    f:close()
    
    if not compressed_data or compressed_data == "" then
        return false, "Failed to read save file"
    end
    
    -- Decompress and decode JSON
    local success, decompressed_data = pcall(love.data.decompress, "string", "zlib", compressed_data)
    if not success then
        return false, "Failed to decompress save file"
    end
    
    local success, game_state = pcall(json.decode, decompressed_data)
    if not success then
        return false, "Failed to parse save file"
    end
    
    -- Apply the loaded state
    local apply_success, apply_message = serial.apply(game_state)
    
    return apply_success, apply_message
end

-- Get list of available save files
function serial.getSaveFiles()
    local save_files = {}
    
    -- Use io.popen to list files in current directory
    local handle = io.popen("ls *.sav 2>/dev/null") -- Unix/Linux/Mac
    -- For Windows, use: local handle = io.popen("dir *.sav /b 2>nul")
    
    if handle then
        for filename in handle:lines() do
            -- Get file attributes using io.open and file:seek
            local f = io.open(filename, "r")
            if f then
                local size = f:seek("end")
                f:close()
                
                -- Get modification time using os.execute and stat (Unix/Linux/Mac)
                local stat_handle = io.popen("stat -c %Y " .. filename .. " 2>/dev/null")
                -- For Windows, use: local stat_handle = io.popen("forfiles /m " .. filename .. " /c \"cmd /c echo @fdate @ftime\"")
                
                local modtime = 0
                if stat_handle then
                    local time_str = stat_handle:read("*line")
                    if time_str then
                        modtime = tonumber(time_str) or 0
                    end
                    stat_handle:close()
                end
                
                table.insert(save_files, {
                    filename = filename,
                    size = size,
                    modified = modtime
                })
            end
        end
        handle:close()
    end
    
    -- Sort by modification time (newest first)
    table.sort(save_files, function(a, b)
        return a.modified > b.modified
    end)
    
    return save_files
end

-- Delete a save file
function serial.deleteSave(filename)
    local success = os.remove(filename)
    return success ~= nil
end

-- Quick save function (saves to "quicksave.sav")
function serial.quickSave()
    return serial.saveToFile("./quicksave.sav")
end

-- Quick load function (loads from "quicksave.sav")
function serial.quickLoad()
    return serial.loadFromFile("./quicksave.sav")
end

-- NEW: Utility function to get save file info including map data summary
function serial.getSaveInfo(filename)
    local f = io.open(filename, "r")
    if not f then
        return nil, "Save file not found"
    end
    
    local compressed_data = f:read("*all")
    f:close()
    
    if not compressed_data or compressed_data == "" then
        return nil, "Failed to read save file"
    end
    
    local success, decompressed_data = pcall(love.data.decompress, "string", "zlib", compressed_data)
    if not success then
        return nil, "Failed to decompress save file"
    end
    
    local success, game_state = pcall(json.decode, decompressed_data)
    if not success then
        return nil, "Failed to parse save file"
    end
    
    -- Extract summary information
    local info = {
        version = game_state.metadata and game_state.metadata.version or "Unknown",
        timestamp = game_state.metadata and game_state.metadata.timestamp or 0,
        level = game_state.game_data and game_state.game_data.level or "Unknown",
        score = game_state.game_data and game_state.game_data.score or 0,
        time_played = game_state.game_data and game_state.game_data.time_played or 0,
        enemy_count = game_state.enemies and #game_state.enemies or 0,
        coin_count = game_state.coins and #game_state.coins or 0,
    }
    
    -- Add map data summary if available
    if game_state.map_data then
        info.arch_count = game_state.map_data.arches and #game_state.map_data.arches or 0
        info.tree_count = game_state.map_data.trees and #game_state.map_data.trees or 0
        info.has_map_tiles = game_state.map_data.base_tiles ~= nil
    else
        info.arch_count = 0
        info.tree_count = 0
        info.has_map_tiles = false
    end
    
    return info, "Success"
end


return serial