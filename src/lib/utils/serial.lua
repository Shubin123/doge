-- Enhanced serial module with comprehensive game state serialization
local serial = {}
local logger = require("lib.utils.logger")

-- Configuration
serial.config = {
    save_directory = "saves/",
    auto_save_interval = 60, -- seconds
    max_save_slots = 10,
    quick_save_slots = 3,
    compression_level = 9
}

-- Internal state
serial.last_auto_save = 0
serial.save_in_progress = false
serial.ready = false

-- Ensure save directory exists
local function ensureSaveDirectory()
    local info = love.filesystem.getInfo(serial.config.save_directory)
    if not info then
        local success = love.filesystem.createDirectory(serial.config.save_directory)
        if not success then
            logger.error("Failed to create save directory: " .. serial.config.save_directory)
            return false
        end
    end
    return true
end

-- Initialize serial module
function serial.init(cfgTbl)
    cfgTbl = cfgTbl or {}
    
    -- Override default save directory if provided
    if cfgTbl.save_directory then
        serial.config.save_directory = cfgTbl.save_directory
    else
        -- Use love.filesystem save directory by default
        serial.config.save_directory = "saves/"
    end
    
    -- Apply other config overrides
    for k, v in pairs(cfgTbl) do
        if serial.config[k] then
            serial.config[k] = v
        end
    end
    
    -- Ensure save directory exists
    ensureSaveDirectory()
    
    serial.ready = true
    logger.info("Serial module initialized with save directory: " .. serial.config.save_directory)
    
    return true, "Serial module initialized successfully"
end

-- Version check to reject saves from newer versions
local function oldVersionCheck(save_version)
    local current_version = "2.1"
    
    -- Simple version comparison (assumes format X.Y)
    local function parseVersion(v)
        local major, minor = v:match("(%d+)%.(%d+)")
        return tonumber(major) or 0, tonumber(minor) or 0
    end
    
    local save_major, save_minor = parseVersion(save_version or "1.0")
    local curr_major, curr_minor = parseVersion(current_version)
    
    if save_major > curr_major or (save_major == curr_major and save_minor > curr_minor) then
        return false, "Save file is from a newer version (" .. save_version .. ") and cannot be loaded"
    end
    
    return true, "Version check passed"
end

-- Generate timestamp for save files
local function getTimestamp()
    return os.date("%Y%m%d_%H%M%S")
end

-- Format timestamp for display
local function formatTimestamp(timestamp)
    if type(timestamp) == "number" then
        return os.date("%Y-%m-%d %H:%M:%S", timestamp)
    elseif type(timestamp) == "string" then
        -- Parse YYYYMMDD_HHMMSS format
        local year, month, day, hour, min, sec = timestamp:match("(%d%d%d%d)(%d%d)(%d%d)_(%d%d)(%d%d)(%d%d)")
        if year then
            return string.format("%s-%s-%s %s:%s:%s", year, month, day, hour, min, sec)
        end
    end
    return "Unknown"
end

-- Calculate checksum for save validation
local function calculateChecksum(data)
    local sum = 0
    local str = json.encode(data)
    for i = 1, #str do
        sum = sum + string.byte(str, i)
    end
    return sum % 65536
end

function serial.create()
    local game_state = {}

    -- Update local player from physics before capturing
    if renderer and renderer.updateLocalPlayerFromPhysics then
        renderer.updateLocalPlayerFromPhysics()
    end

    -- Capture player state with more details
    game_state.player = {}
    if player then
        if player.body and not player.body:isDestroyed() then
            game_state.player.x = player.body:getX()
            game_state.player.y = player.body:getY()
            local vx, vy = player.body:getLinearVelocity()
            game_state.player.velocity_x = vx
            game_state.player.velocity_y = vy
        end
        game_state.player.health = player.health or 100
        game_state.player.kills = player.kills or 0
        game_state.player.deaths = player.deaths or 0
        -- Add any other player stats you track
    end
    
    -- Capture renderer's local player state if available
    if renderer and renderer.local_player_state then
        for k, v in pairs(renderer.local_player_state) do
            if not game_state.player[k] then
                game_state.player[k] = v
            end
        end
    end

    -- Capture enemy data from physics bodies
    game_state.enemies = {}
    if enemies_bods then
        for i = 1, #enemies_bods do
            if enemies_bods[i] and not enemies_bods[i]:isDestroyed() then
                local ex, ey = enemies_bods[i]:getX(), enemies_bods[i]:getY()
                local vx, vy = enemies_bods[i]:getLinearVelocity()
                game_state.enemies[i] = {
                    x = ex,
                    y = ey,
                    velocity_x = vx,
                    velocity_y = vy,
                    active = true,
                    health = enemy.enemies and enemy.enemies[i] and enemy.enemies[i].health or 100
                }
            end
        end
    end

    -- Capture coin data from physics bodies
    game_state.coins = {}
    if coin_bods then
        for i = 1, #coin_bods do
            if coin_bods[i] and not coin_bods[i]:isDestroyed() then
                local cx, cy = coin_bods[i]:getX(), coin_bods[i]:getY()
                game_state.coins[i] = {
                    x = cx,
                    y = cy,
                    active = true
                }
            end
        end
    end

    -- Capture fire effects
    game_state.fire_effects = {}
    if fire and fire.getNetworkData then
        game_state.fire_effects = fire.getNetworkData() or {}
    end

    -- Capture gun/projectile data
    game_state.projectiles = {}
    if gun and gun.projectiles then
        for i, proj in ipairs(gun.projectiles) do
            if proj.body and not proj.body:isDestroyed() then
                local px, py = proj.body:getX(), proj.body:getY()
                local vx, vy = proj.body:getLinearVelocity()
                table.insert(game_state.projectiles, {
                    x = px,
                    y = py,
                    velocity_x = vx,
                    velocity_y = vy,
                    damage = proj.damage or 10,
                    type = proj.type or "bullet"
                })
            end
        end
    end

    -- Capture map data using the map module's function
    if map and map.createSaveData then
        game_state.map_data = map.createSaveData()
    else
        game_state.map_data = serial.captureMapData()
    end

    -- Capture camera state
    game_state.camera = {}
    if camera then
        game_state.camera.x = camera.x or 0
        game_state.camera.y = camera.y or 0
        game_state.camera.scale = camera.scale or 1
        game_state.camera.rotation = camera.rotation or 0
    end

    -- Capture additional game state data
    game_state.game_data = {
        level = var.level or 1,
        score = var.score or 0,
        time_played = var.time_played or 0,
        difficulty = var.difficulty or 1,
        game_width = var.game_width,
        game_height = var.game_height,
        state = var.State or "game",
        multiplayer = var.multiplayer or false,
        graphics_high = var.graphics_high,
        -- Add any other global game variables you want to save
    }

    -- Add metadata
    game_state.metadata = {
        version = "2.1", -- Incremented version for enhanced features
        timestamp = os.time(),
        timestamp_str = getTimestamp(),
        save_type = "offline",
        checksum = 0 -- Will be calculated after encoding
    }

    -- Calculate checksum
    game_state.metadata.checksum = calculateChecksum(game_state)

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
    if not game_state or not game_state.metadata then
        local msg = "Invalid save data: missing metadata"
        logger.error(msg)
        return false, msg
    end
    
    -- Check version compatibility
    local version_ok, version_msg = oldVersionCheck(game_state.metadata.version)
    if not version_ok then
        logger.error(version_msg)
        return false, version_msg
    end
    
    if game_state.metadata.save_type ~= "offline" then
        local msg = "Invalid save type: " .. tostring(game_state.metadata.save_type)
        logger.error(msg)
        return false, msg
    end
    
    -- Validate checksum
    local original_checksum = game_state.metadata.checksum
    game_state.metadata.checksum = 0
    local calculated_checksum = calculateChecksum(game_state)
    game_state.metadata.checksum = original_checksum
    
    if original_checksum ~= calculated_checksum then
        -- Log warning but continue loading
        logger.warn("Save file checksum mismatch!")
    end
    
    local errors = {}
    
    -- Apply player state
    if game_state.player then
        local success, err = pcall(function()
            -- Set player position and state
            if player and player.body and not player.body:isDestroyed() then
                player.body:setPosition(game_state.player.x or 400, game_state.player.y or 300)
                
                -- Set velocity if saved
                if game_state.player.velocity_x and game_state.player.velocity_y then
                    player.body:setLinearVelocity(game_state.player.velocity_x, game_state.player.velocity_y)
                else
                    player.body:setLinearVelocity(0, 0)
                end
            end

            -- Restore player stats
            if player then
                player.health = game_state.player.health or 100
                player.kills = game_state.player.kills or 0
                player.deaths = game_state.player.deaths or 0
            end

            -- Apply to renderer if available
            if renderer then
                renderer.local_player_state = game_state.player
            end
        end)
        
        if not success then
            table.insert(errors, "Player restore error: " .. tostring(err))
        end
    end
    -- Restore enemies
    if game_state.enemies then
        local success, err = pcall(function()
            -- Clear existing enemies first
            if enemies_bods then
                for i = #enemies_bods, 1, -1 do
                    if enemies_bods[i] and not enemies_bods[i]:isDestroyed() then
                        enemies_bods[i]:destroy()
                    end
                end
            end
            enemies_bods = {}
            
            -- Clear enemy data structures if they exist
            if enemy and enemy.enemies then
                enemy.enemies = {}
            end

            -- Recreate enemies from save data
            for i, enemy_data in pairs(game_state.enemies) do
                if enemy_data.active and enemy and enemy.addEnemy then
                    -- Use enemy module's addEnemy if available
                    local new_enemy = enemy.addEnemy(enemy_data.x, enemy_data.y)
                    
                    -- Set additional properties if possible
                    if new_enemy and enemy_data.health then
                        new_enemy.health = enemy_data.health
                    end
                    
                    -- Set velocity if we have direct access to body
                    if enemies_bods[#enemies_bods] and enemy_data.velocity_x and enemy_data.velocity_y then
                        enemies_bods[#enemies_bods]:setLinearVelocity(enemy_data.velocity_x, enemy_data.velocity_y)
                    end
                elseif enemy_data.active then
                    -- Fallback: create enemy manually
                    local enemy_body = love.physics.newBody(world, enemy_data.x, enemy_data.y, "dynamic")
                    local enemy_shape = love.physics.newCircleShape(10)
                    local enemy_fixture = love.physics.newFixture(enemy_body, enemy_shape)
                    enemy_fixture:setGroupIndex(-777)
                    
                    table.insert(enemies_bods, enemy_body)
                    
                    if enemy_data.velocity_x and enemy_data.velocity_y then
                        enemy_body:setLinearVelocity(enemy_data.velocity_x, enemy_data.velocity_y)
                    end
                end
            end
            
            -- Update enemy count
            if var then
                var.num_enemies = #enemies_bods
            end
        end)
        
        if not success then
            table.insert(errors, "Enemy restore error: " .. tostring(err))
        end
    end
    -- Restore coins
    if game_state.coins then
        local success, err = pcall(function()
            -- Clear existing coins first
            if coin_bods then
                for i = #coin_bods, 1, -1 do
                    if coin_bods[i] and not coin_bods[i]:isDestroyed() then
                        coin_bods[i]:destroy()
                    end
                end
            end
            coin_bods = {}

            -- Recreate coins from save data
            for i, coin_data in pairs(game_state.coins) do
                if coin_data.active then
                    local coin_body = love.physics.newBody(world, coin_data.x, coin_data.y, "dynamic")
                    local coin_shape = love.physics.newCircleShape(5)
                    local coin_fixture = love.physics.newFixture(coin_body, coin_shape)
                    coin_fixture:setGroupIndex(69)
                    
                    table.insert(coin_bods, coin_body)
                end
            end
            
            -- Update coin count and sprite batch
            if var then
                var.num_coins = #coin_bods
            end
            
            -- Recreate sprite batch if needed
            if coin_sprite and coin_image and #coin_bods > 0 then
                coin_sprite = love.graphics.newSpriteBatch(coin_image, #coin_bods, "stream")
            end
        end)
        
        if not success then
            table.insert(errors, "Coin restore error: " .. tostring(err))
        end
    end
    -- Restore map data
    if game_state.map_data then
        local success, err = pcall(function()
            if map and map.restore then
                local restore_success = map.restore(game_state.map_data)
                if not restore_success then
                    error("Map restoration failed")
                end
            else
                -- Fallback if map doesn't have restore function
                print("Warning: Map module doesn't have restore function")
            end
        end)
        
        if not success then
            table.insert(errors, "Map restore error: " .. tostring(err))
        end
    end

    -- Restore camera state
    if game_state.camera and camera then
        local success, err = pcall(function()
            if camera.setPosition then
                camera.setPosition(game_state.camera.x or 0, game_state.camera.y or 0)
            end
            if camera.setZoom then
                camera.setZoom(game_state.camera.scale or 1)
            end
            if camera.setRotation then
                camera.setRotation(game_state.camera.rotation or 0)
            end
        end)
        
        if not success then
            table.insert(errors, "Camera restore error: " .. tostring(err))
        end
    end
    -- Restore game data
    if game_state.game_data then
        local success, err = pcall(function()
            if var then
                var.level = game_state.game_data.level or 1
                var.score = game_state.game_data.score or 0
                var.time_played = game_state.game_data.time_played or 0
                var.difficulty = game_state.game_data.difficulty or 1
                var.State = game_state.game_data.state or "game"
                -- Don't restore multiplayer state for safety
                -- var.multiplayer = game_state.game_data.multiplayer
                var.graphics_high = game_state.game_data.graphics_high
            end
        end)
        
        if not success then
            table.insert(errors, "Game data restore error: " .. tostring(err))
        end
    end

    -- Report results
    if #errors > 0 then
        local error_msg = "Save loaded with errors:\n" .. table.concat(errors, "\n")
        logger.warn(error_msg)
        return true, error_msg -- Still return true as partial load succeeded
    else
        local success_msg = "Save loaded successfully"
        logger.info(success_msg)
        return true, success_msg
    end
end

-- Save game state to file with slot support
function serial.saveToFile(filename, slot)
    if serial.save_in_progress then
        local msg = "Save already in progress"
        logger.warn(msg)
        return false, msg
    end
    
    if not serial.ready then
        local msg = "Serial module not initialized"
        logger.error(msg)
        return false, msg
    end
    
    serial.save_in_progress = true
    
    local dir_ok = ensureSaveDirectory()
    if not dir_ok then
        serial.save_in_progress = false
        local msg = "Failed to ensure save directory exists"
        logger.error(msg)
        return false, msg
    end
    
    local game_state = serial.create()
    
    -- Add slot information to metadata
    if slot then
        game_state.metadata.slot = slot
        game_state.metadata.slot_name = filename
    end

    -- Convert to JSON and compress
    local success, json_string = pcall(json.encode, game_state)
    if not success then
        serial.save_in_progress = false
        local msg = "Failed to encode save data: " .. tostring(json_string)
        logger.error(msg)
        return false, msg
    end
    
    local success, compressed_data = pcall(love.data.compress, "string", "zlib", json_string, serial.config.compression_level)
    if not success then
        serial.save_in_progress = false
        local msg = "Failed to compress save data: " .. tostring(compressed_data)
        logger.error(msg)
        return false, msg
    end

    -- Ensure filename has correct extension
    if not filename:match("%.sav$") then
        filename = filename .. ".sav"
    end
    
    -- Full path
    local filepath = serial.config.save_directory .. filename

    -- Write to file using love.filesystem
    local success, err = pcall(love.filesystem.write, filepath, compressed_data)
    if not success then
        serial.save_in_progress = false
        local msg = "Failed to write save file: " .. tostring(err)
        logger.error(msg)
        return false, msg
    end
    
    serial.save_in_progress = false
    local success_msg = "Game saved to " .. filename
    logger.info(success_msg)
    return true, success_msg
end
-- Load game state from file
function serial.loadFromFile(filename)
    if not serial.ready then
        local msg = "Serial module not initialized"
        logger.error(msg)
        return false, msg
    end
    
    ensureSaveDirectory()
    
    -- Ensure filename has correct extension
    if not filename:match("%.sav$") then
        filename = filename .. ".sav"
    end
    
    -- Full path
    local filepath = serial.config.save_directory .. filename
    
    -- Check if file exists
    local info = love.filesystem.getInfo(filepath)
    if not info then
        local msg = "Save file not found: " .. filename
        logger.error(msg)
        return false, msg
    end
    
    -- Read compressed data from file
    local success, compressed_data = pcall(love.filesystem.read, filepath)
    if not success then
        local msg = "Failed to read save file: " .. filename .. " - " .. tostring(compressed_data)
        logger.error(msg)
        return false, msg
    end
    
    if not compressed_data or compressed_data == "" then
        local msg = "Save file is empty: " .. filename
        logger.error(msg)
        return false, msg
    end
    
    -- Decompress and decode JSON
    local success, decompressed_data = pcall(love.data.decompress, "string", "zlib", compressed_data)
    if not success then
        local msg = "Failed to decompress save file: " .. tostring(decompressed_data)
        logger.error(msg)
        return false, msg
    end
    
    local success, game_state = pcall(json.decode, decompressed_data)
    if not success then
        local msg = "Failed to parse save file: " .. tostring(game_state)
        logger.error(msg)
        return false, msg
    end
    
    -- Apply the loaded state
    local apply_success, apply_message = serial.apply(game_state)
    
    return apply_success, apply_message
end

-- Get list of available save files with enhanced information
function serial.getSaveFiles()
    if not serial.ready then
        logger.error("Serial module not initialized")
        return {}
    end
    
    ensureSaveDirectory()
    local save_files = {}
    
    -- Get directory items using love.filesystem
    local success, items = pcall(love.filesystem.getDirectoryItems, serial.config.save_directory)
    if not success then
        logger.error("Failed to read save directory: " .. tostring(items))
        return {}
    end
    
    for _, filename in ipairs(items) do
        -- Only process .sav files
        if filename:match("%.sav$") then
            local filepath = serial.config.save_directory .. filename
            local info = love.filesystem.getInfo(filepath)
            
            if info and info.type == "file" then
                -- Try to get save info
                local save_info, err = serial.getSaveInfo(filename)
                
                table.insert(save_files, {
                    filename = filename,
                    filepath = filepath,
                    size = info.size,
                    modified = info.modtime or 0,
                    info = save_info,
                    error = err
                })
            end
        end
    end
    
    -- Sort by modification time (newest first)
    table.sort(save_files, function(a, b)
        return a.modified > b.modified
    end)
    
    return save_files
end
-- Delete a save file
function serial.deleteSave(filename)
    if not serial.ready then
        local msg = "Serial module not initialized"
        logger.error(msg)
        return false, msg
    end
    
    ensureSaveDirectory()
    
    -- Ensure filename has correct extension
    if not filename:match("%.sav$") then
        filename = filename .. ".sav"
    end
    
    local filepath = serial.config.save_directory .. filename
    
    -- Check if file exists first
    local info = love.filesystem.getInfo(filepath)
    if not info then
        local msg = "Save file not found: " .. filename
        logger.warn(msg)
        return false, msg
    end
    
    local success = love.filesystem.remove(filepath)
    if success then
        local msg = "Save file deleted: " .. filename
        logger.info(msg)
        return true, msg
    else
        local msg = "Failed to delete save file: " .. filename
        logger.error(msg)
        return false, msg
    end
end

-- Async save placeholder (future extension)
function serial.saveAsync(name, slot, callback)
    -- Placeholder for future coroutine-based async saving
    -- For now, just call synchronous version and invoke callback
    local success, msg = serial.saveToFile(name, slot)
    if callback then
        callback(success, msg)
    end
    logger.info("Async save placeholder called - using synchronous save")
    return success, msg
end

-- Quick save function with slot support
function serial.quickSave(slot)
    slot = slot or 1
    slot = math.max(1, math.min(serial.config.quick_save_slots, slot))
    local filename = string.format("quicksave_%d", slot)
    return serial.saveToFile(filename, slot)
end

-- Quick load function with slot support
function serial.quickLoad(slot)
    slot = slot or 1
    slot = math.max(1, math.min(serial.config.quick_save_slots, slot))
    local filename = string.format("quicksave_%d", slot)
    return serial.loadFromFile(filename)
end

-- Auto save function
function serial.autoSave()
    local filename = "autosave_" .. getTimestamp()
    local success, msg = serial.saveToFile(filename)
    
    if success then
        logger.info("Auto save completed: " .. filename)
        -- Clean up old autosaves (keep only the 3 most recent)
        serial.cleanupAutoSaves(3)
    else
        logger.error("Auto save failed: " .. msg)
    end
    
    return success, msg
end

-- Clean up old autosaves
function serial.cleanupAutoSaves(keep_count)
    keep_count = keep_count or 3
    local save_files = serial.getSaveFiles()
    local autosaves = {}
    
    -- Filter for autosaves
    for _, save in ipairs(save_files) do
        if save.filename:match("^autosave_") then
            table.insert(autosaves, save)
        end
    end
    
    -- Delete old autosaves
    if #autosaves > keep_count then
        for i = keep_count + 1, #autosaves do
            serial.deleteSave(autosaves[i].filename)
        end
    end
end

-- Get detailed save file info
function serial.getSaveInfo(filename)
    if not serial.ready then
        return nil, "Serial module not initialized"
    end
    
    ensureSaveDirectory()
    
    -- Ensure filename has correct extension
    if not filename:match("%.sav$") then
        filename = filename .. ".sav"
    end
    
    local filepath = serial.config.save_directory .. filename
    
    -- Check if file exists
    local info = love.filesystem.getInfo(filepath)
    if not info then
        return nil, "Save file not found"
    end
    
    -- Read compressed data from file
    local success, compressed_data = pcall(love.filesystem.read, filepath)
    if not success then
        return nil, "Failed to read save file"
    end
    
    if not compressed_data or compressed_data == "" then
        return nil, "Save file is empty"
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
        filename = filename,
        version = game_state.metadata and game_state.metadata.version or "Unknown",
        timestamp = game_state.metadata and game_state.metadata.timestamp or 0,
        timestamp_str = game_state.metadata and game_state.metadata.timestamp_str or "Unknown",
        timestamp_formatted = formatTimestamp(game_state.metadata and game_state.metadata.timestamp),
        slot = game_state.metadata and game_state.metadata.slot,
        level = game_state.game_data and game_state.game_data.level or "Unknown",
        score = game_state.game_data and game_state.game_data.score or 0,
        time_played = game_state.game_data and game_state.game_data.time_played or 0,
        player_health = game_state.player and game_state.player.health or 0,
        player_position = game_state.player and string.format("(%.0f, %.0f)", game_state.player.x or 0, game_state.player.y or 0) or "Unknown",
        enemy_count = game_state.enemies and #game_state.enemies or 0,
        coin_count = game_state.coins and #game_state.coins or 0,
        save_type = filename:match("^quicksave_") and "Quick Save" or
                    filename:match("^autosave_") and "Auto Save" or
                    "Manual Save"
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

-- Format time duration
function serial.formatDuration(seconds)
    if not seconds or seconds < 0 then return "0:00" end
    
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    
    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, secs)
    else
        return string.format("%d:%02d", minutes, secs)
    end
end

-- Check if auto save is needed
function serial.checkAutoSave(dt)
    serial.last_auto_save = serial.last_auto_save + dt
    
    if serial.last_auto_save >= serial.config.auto_save_interval then
        serial.last_auto_save = 0
        return true
    end
    
    return false
end

-- List save slots with info
function serial.listSaveSlots()
    local slots = {}
    local save_files = serial.getSaveFiles()
    
    -- Quick save slots
    for i = 1, serial.config.quick_save_slots do
        local filename = string.format("quicksave_%d.sav", i)
        local found = false
        
        for _, save in ipairs(save_files) do
            if save.filename == filename then
                slots[i] = save
                found = true
                break
            end
        end
        
        if not found then
            slots[i] = {
                filename = filename,
                empty = true,
                slot = i,
                save_type = "Quick Save"
            }
        end
    end
    
    return slots
end

return serial
