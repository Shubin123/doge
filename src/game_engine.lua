local game_engine = {}

-- Game state management
local game_engine_state = {
    current_map = nil,
    player_character = nil,
    is_loading = false,
    loading_progress = 0,
    loading_message = "",
    camera = {x = 0, y = 0, zoom = 1},
    tileset_cache = {}
}

-- Map data structure
local function create_empty_map()
    return {
        metadata = {},
        tileset_path = "",
        tileset_image = nil,
        tiles = nil,
        dimensions = {width = 0, height = 0},
        tile_data = {},
        player_spawn = {x = 0, y = 0},
        enemies = {},
        collectibles = {},
        tile_size = 16
    }
end

-- Parse map file format
local function parse_map_file(content)
    local map_data = create_empty_map()
    local lines = {}
    
    -- Split content into lines
    for line in content:gmatch("[^\r\n]+") do
        -- Trim whitespace manually
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" then
            table.insert(lines, line)
        end
    end
    
    if #lines < 2 then
        error("Invalid map file format")
    end
    
    -- Verify header
    if lines[1] ~= "DOGE_MAP" then
        error("Invalid map file header")
    end
    
    local current_section = nil
    local tile_row = 0
    
    for i = 3, #lines do  -- Skip header and version
        local line = lines[i]
        
        if line:match("%[(.+)%]") then
            current_section = line:match("%[(.+)%]")
        elseif current_section == "metadata" then
            local key, value = line:match("(.+)=(.+)")
            if key and value then
                map_data.metadata[key] = value
            end
        elseif current_section == "tileset" then
            map_data.tileset_path = line
        elseif current_section == "dimensions" then
            local w, h = line:match("(%d+)x(%d+)")
            if w and h then
                map_data.dimensions.width = tonumber(w)
                map_data.dimensions.height = tonumber(h)
            end
        elseif current_section == "tiles" then
            tile_row = tile_row + 1
            map_data.tile_data[tile_row] = {}
            local col = 0
            for tile_id in line:gmatch("([^,]+)") do
                col = col + 1
                map_data.tile_data[tile_row][col] = tonumber(tile_id) or 0
            end
        elseif current_section == "player_spawn" then
            local x, y = line:match("(%d+),(%d+)")
            if x and y then
                map_data.player_spawn.x = tonumber(x)
                map_data.player_spawn.y = tonumber(y)
            end
        elseif current_section == "enemies" then
            local enemy_type, x, y = line:match("([^,]+),(%d+),(%d+)")
            if enemy_type and x and y then
                table.insert(map_data.enemies, {
                    type = enemy_type,
                    x = tonumber(x),
                    y = tonumber(y)
                })
            end
        elseif current_section == "collectibles" then
            local item_type, x, y = line:match("([^,]+),(%d+),(%d+)")
            if item_type and x and y then
                table.insert(map_data.collectibles, {
                    type = item_type,
                    x = tonumber(x),
                    y = tonumber(y)
                })
            end
        end
    end
    
    return map_data
end

-- Load tileset and create quads
local function load_tileset(tileset_path)
    if game_engine_state.tileset_cache[tileset_path] then
        return game_engine_state.tileset_cache[tileset_path]
    end
    
    local success, tileset_image = pcall(love.graphics.newImage, tileset_path)
    if not success then
        print("Warning: Could not load tileset: " .. tileset_path)
        return nil
    end
    
    local tile_size = 16
    local tiles_wide = math.floor(tileset_image:getWidth() / tile_size)
    local tiles_high = math.floor(tileset_image:getHeight() / tile_size)
    
    local quads = {}
    local tile_id = 1
    
    for y = 0, tiles_high - 1 do
        for x = 0, tiles_wide - 1 do
            quads[tile_id] = love.graphics.newQuad(
                x * tile_size, y * tile_size, 
                tile_size, tile_size, 
                tileset_image:getDimensions()
            )
            tile_id = tile_id + 1
        end
    end
    
    local tileset = {
        image = tileset_image,
        quads = quads,
        tile_size = tile_size,
        tiles_wide = tiles_wide,
        tiles_high = tiles_high
    }
    
    game_engine_state.tileset_cache[tileset_path] = tileset
    return tileset
end

-- Load map from file
function game_engine.load_map(map_name, character_id, on_complete)
    game_engine_state.is_loading = true
    game_engine_state.loading_progress = 0
    game_engine_state.loading_message = "Loading map: " .. map_name
    game_engine_state.player_character = character_id
    
    -- Start loading process
    coroutine.wrap(function()
        local map_file = "maps/" .. map_name .. ".map"
        
        -- Check if map file exists
        local info = love.filesystem.getInfo(map_file)
        if not info then
            print("Error: Map file not found: " .. map_file)
            game_engine_state.is_loading = false
            return
        end
        
        game_engine_state.loading_progress = 0.2
        game_engine_state.loading_message = "Reading map data..."
        
        -- Read map file
        local content = love.filesystem.read(map_file)
        if not content then
            print("Error: Could not read map file: " .. map_file)
            game_engine_state.is_loading = false
            return
        end
        
        game_engine_state.loading_progress = 0.4
        game_engine_state.loading_message = "Parsing map structure..."
        
        -- Parse map data
        local map_data = parse_map_file(content)
        
        game_engine_state.loading_progress = 0.6
        game_engine_state.loading_message = "Loading tileset..."
        
        -- Load tileset
        map_data.tiles = load_tileset(map_data.tileset_path)
        if not map_data.tiles then
            print("Warning: Using placeholder tileset")
            -- Create a simple placeholder tileset
            map_data.tiles = {
                image = nil,
                quads = {},
                tile_size = 16
            }
        end
        
        game_engine_state.loading_progress = 0.8
        game_engine_state.loading_message = "Initializing game world..."
        
        -- Set current map
        game_engine_state.current_map = map_data
        
        -- Initialize camera to player spawn
        game_engine.center_camera_on_player()
        
        game_engine_state.loading_progress = 1.0
        game_engine_state.loading_message = "Complete!"
        
        -- Small delay to show completion
        love.timer.sleep(0.5)
        
        game_engine_state.is_loading = false
        
        if on_complete then
            on_complete()
        end
        
        print("Map loaded successfully: " .. map_name)
        print("Player spawn: " .. map_data.player_spawn.x .. ", " .. map_data.player_spawn.y)
        print("Map dimensions: " .. map_data.dimensions.width .. "x" .. map_data.dimensions.height)
    end)()
end

-- Center camera on player spawn point
function game_engine.center_camera_on_player()
    if game_engine_state.current_map then
        local spawn = game_engine_state.current_map.player_spawn
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()
        
        game_engine_state.camera.x = spawn.x - w / 2
        game_engine_state.camera.y = spawn.y - h / 2
    end
end

-- Update game engine
function game_engine.update(dt)
    -- Handle any game updates here
end

-- Draw the current map
function game_engine.draw()
    if game_engine_state.is_loading then
        game_engine.draw_loading_screen()
        return
    end
    
    if not game_engine_state.current_map then
        game_engine.draw_no_map()
        return
    end
    
    local map = game_engine_state.current_map
    local camera = game_engine_state.camera
    
    -- Clear screen
    love.graphics.clear(0.2, 0.4, 0.2, 1)
    
    -- Apply camera transform
    love.graphics.push()
    love.graphics.translate(-camera.x, -camera.y)
    love.graphics.scale(camera.zoom, camera.zoom)
    
    -- Draw tiles
    if map.tiles and map.tiles.image then
        game_engine.draw_tilemap(map)
    else
        game_engine.draw_placeholder_map(map)
    end
    
    -- Draw player spawn point
    love.graphics.setColor(0, 1, 0, 0.8)
    love.graphics.circle("fill", map.player_spawn.x, map.player_spawn.y, 8)
    
    -- Draw enemies
    love.graphics.setColor(1, 0, 0, 0.8)
    for _, enemy in ipairs(map.enemies) do
        love.graphics.circle("fill", enemy.x, enemy.y, 6)
    end
    
    -- Draw collectibles
    love.graphics.setColor(1, 1, 0, 0.8)
    for _, collectible in ipairs(map.collectibles) do
        love.graphics.circle("fill", collectible.x, collectible.y, 4)
    end
    
    love.graphics.pop()
    
    -- Draw UI
    game_engine.draw_ui()
end

-- Draw tilemap using tileset
function game_engine.draw_tilemap(map)
    local tiles = map.tiles
    local tile_size = tiles.tile_size
    
    love.graphics.setColor(1, 1, 1, 1)
    
    for row = 1, map.dimensions.height do
        for col = 1, map.dimensions.width do
            local tile_id = map.tile_data[row] and map.tile_data[row][col]
            if tile_id and tile_id > 0 and tiles.quads[tile_id] then
                local x = (col - 1) * tile_size
                local y = (row - 1) * tile_size
                
                love.graphics.draw(tiles.image, tiles.quads[tile_id], x, y)
            end
        end
    end
end

-- Draw placeholder map when tileset is missing
function game_engine.draw_placeholder_map(map)
    local tile_size = 16
    
    for row = 1, map.dimensions.height do
        for col = 1, map.dimensions.width do
            local tile_id = map.tile_data[row] and map.tile_data[row][col]
            if tile_id and tile_id > 0 then
                local x = (col - 1) * tile_size
                local y = (row - 1) * tile_size
                
                -- Color based on tile ID
                if tile_id == 1 then
                    love.graphics.setColor(0.5, 0.3, 0.1, 1) -- Brown for walls
                else
                    love.graphics.setColor(0.2, 0.8, 0.2, 1) -- Green for grass
                end
                
                love.graphics.rectangle("fill", x, y, tile_size, tile_size)
            end
        end
    end
end

-- Draw loading screen
function game_engine.draw_loading_screen()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    
    -- Background
    love.graphics.clear(0.1, 0.1, 0.2, 1)
    
    -- Title
    love.graphics.setColor(1, 1, 1, 1)
    local title_font = love.graphics.newFont(32)
    love.graphics.setFont(title_font)
    local title = "Loading Map..."
    local title_width = title_font:getWidth(title)
    love.graphics.print(title, w/2 - title_width/2, h/2 - 100)
    
    -- Progress bar
    local bar_width = 400
    local bar_height = 20
    local bar_x = w/2 - bar_width/2
    local bar_y = h/2 - 10
    
    -- Progress bar background
    love.graphics.setColor(0.3, 0.3, 0.3, 1)
    love.graphics.rectangle("fill", bar_x, bar_y, bar_width, bar_height)
    
    -- Progress bar fill
    love.graphics.setColor(0.2, 0.8, 0.2, 1)
    love.graphics.rectangle("fill", bar_x, bar_y, bar_width * game_engine_state.loading_progress, bar_height)
    
    -- Progress bar border
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", bar_x, bar_y, bar_width, bar_height)
    
    -- Progress text
    local progress_font = love.graphics.newFont(16)
    love.graphics.setFont(progress_font)
    local progress_text = string.format("%.0f%% - %s", game_engine_state.loading_progress * 100, game_engine_state.loading_message)
    local progress_width = progress_font:getWidth(progress_text)
    love.graphics.print(progress_text, w/2 - progress_width/2, bar_y + 40)
    
    -- Character info
    if game_engine_state.player_character then
        local char_text = "Character: " .. game_engine_state.player_character
        local char_width = progress_font:getWidth(char_text)
        love.graphics.print(char_text, w/2 - char_width/2, h/2 + 100)
    end
end

-- Draw when no map is loaded
function game_engine.draw_no_map()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    
    love.graphics.clear(0.1, 0.1, 0.1, 1)
    love.graphics.setColor(1, 1, 1, 1)
    
    local font = love.graphics.newFont(24)
    love.graphics.setFont(font)
    local text = "No map loaded"
    local text_width = font:getWidth(text)
    love.graphics.print(text, w/2 - text_width/2, h/2)
end

-- Draw game UI
function game_engine.draw_ui()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    
    -- Character info
    if game_engine_state.player_character then
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.setFont(love.graphics.newFont(16))
        love.graphics.print("Character: " .. game_engine_state.player_character, 10, 10)
    end
    
    -- Map info
    if game_engine_state.current_map then
        local map_name = game_engine_state.current_map.metadata.name or "Unknown Map"
        love.graphics.print("Map: " .. map_name, 10, 30)
    end
    
    -- Controls
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.setFont(love.graphics.newFont(14))
    love.graphics.print("ESC - Return to Menu | WASD - Move Camera | +/- - Zoom", 10, h - 30)
end

-- Handle input
function game_engine.handle_key(key, dt)
    if not game_engine_state.current_map then return end
    
    local camera_speed = 200
    local zoom_speed = 0.5
    
    -- Camera movement
    if love.keyboard.isDown("w") or love.keyboard.isDown("up") then
        game_engine_state.camera.y = game_engine_state.camera.y - camera_speed * dt
    end
    if love.keyboard.isDown("s") or love.keyboard.isDown("down") then
        game_engine_state.camera.y = game_engine_state.camera.y + camera_speed * dt
    end
    if love.keyboard.isDown("a") or love.keyboard.isDown("left") then
        game_engine_state.camera.x = game_engine_state.camera.x - camera_speed * dt
    end
    if love.keyboard.isDown("d") or love.keyboard.isDown("right") then
        game_engine_state.camera.x = game_engine_state.camera.x + camera_speed * dt
    end
    
    -- Zoom
    if key == "=" or key == "+" then
        game_engine_state.camera.zoom = math.min(3, game_engine_state.camera.zoom + zoom_speed)
    elseif key == "-" then
        game_engine_state.camera.zoom = math.max(0.5, game_engine_state.camera.zoom - zoom_speed)
    elseif key == "0" then
        game_engine_state.camera.zoom = 1
    elseif key == "space" then
        game_engine.center_camera_on_player()
    end
end

-- Get available maps
function game_engine.get_available_maps()
    local maps = {}
    local files = love.filesystem.getDirectoryItems("maps")
    
    for _, file in ipairs(files) do
        if file:match("%.map$") then
            local map_name = file:gsub("%.map$", "")
            table.insert(maps, map_name)
        end
    end
    
    return maps
end

-- Get game state for external access
function game_engine.is_loading()
    return game_engine_state.is_loading
end

function game_engine.get_current_map()
    return game_engine_state.current_map
end

function game_engine.get_player_character()
    return game_engine_state.player_character
end

return game_engine