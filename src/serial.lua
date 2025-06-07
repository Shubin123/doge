-- very simillar to snap shot system however, when saving locally, we need to reset the game ai behaviours of the enemy first.
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
    game_state.fire_effects = fire.getNetworkData() or {} --works fine for offline / serial 

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
        version = "1.0",
        timestamp = os.time(),
        save_type = "offline"
    }

    return game_state
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
                -- Create new enemy body (you'll need to adapt this to your enemy creation system)
                -- local enemy_body = love.physics.newBody(world, enemy_data.x, enemy_data.y, "dynamic")


                enemy.addEnemy(enemy_data.x, enemy_data.y)
                -- -- local _fixtures = 
                -- local enemy_fixture = love.physics.newFixture(enemy_body, love.physics.newCircleShape(25))
                -- enemy_fixture:setGroupIndex(-777)
                -- -- Add appropriate shape and fixture based on your enemy system
                -- -- This is just an example - adapt to your actual enemy creation code
                -- table.insert(enemies_bods, enemy_body)
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

    -- Restore fire effects
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
    -- local success = love.filesystem.write(filename, compressed_data)

    local f = io.open(filename, "w")

    f:write(compressed_data) -- 3x smaller than raw json even on small data

    f:close()


    -- if success then
    --     return true, "Game saved successfully"
    -- else
    --     return false, "Failed to save game"
    -- end
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

-- Quick save function (saves to "quicksave.sav"). the io read/write may not work on ios.
function serial.quickSave()
    return serial.saveToFile("./quicksave.sav")
end

-- Quick load function (loads from "quicksave.sav")
function serial.quickLoad()
    return serial.loadFromFile("./quicksave.sav")
end

return serial
