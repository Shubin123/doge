local map_serializer = {}

-- JSON-like serialization for map data
local function serialize_value(value, indent_level)
    indent_level = indent_level or 0
    local indent = string.rep("  ", indent_level)
    
    if type(value) == "string" then
        return '"' .. value:gsub('"', '\\"') .. '"'
    elseif type(value) == "number" then
        return tostring(value)
    elseif type(value) == "boolean" then
        return tostring(value)
    elseif type(value) == "table" then
        if #value > 0 then
            -- Array
            local result = "[\n"
            for i, v in ipairs(value) do
                result = result .. indent .. "  " .. serialize_value(v, indent_level + 1)
                if i < #value then result = result .. "," end
                result = result .. "\n"
            end
            result = result .. indent .. "]"
            return result
        else
            -- Object
            local result = "{\n"
            local keys = {}
            for k in pairs(value) do table.insert(keys, k) end
            table.sort(keys)
            
            for i, k in ipairs(keys) do
                result = result .. indent .. "  " .. serialize_value(k, indent_level + 1) .. ": " .. serialize_value(value[k], indent_level + 1)
                if i < #keys then result = result .. "," end
                result = result .. "\n"
            end
            result = result .. indent .. "}"
            return result
        end
    else
        return "null"
    end
end

-- Optimized binary serialization for large tile data
local function serialize_tile_data_binary(tile_data, width, height)
    local binary_data = {}
    
    -- Header: width (4 bytes) + height (4 bytes)
    table.insert(binary_data, string.pack("<I4I4", width, height))
    
    -- Compress tile data using RLE (Run-Length Encoding)
    local compressed = {}
    local current_tile = nil
    local count = 0
    
    for y = 1, height do
        for x = 1, width do
            local tile = (tile_data[y] and tile_data[y][x]) or 0
            
            if tile == current_tile then
                count = count + 1
            else
                if current_tile ~= nil then
                    -- Write previous run
                    table.insert(compressed, string.pack("<I2I4", current_tile, count))
                end
                current_tile = tile
                count = 1
            end
        end
    end
    
    -- Write final run
    if current_tile ~= nil then
        table.insert(compressed, string.pack("<I2I4", current_tile, count))
    end
    
    -- Combine header and compressed data
    table.insert(binary_data, table.concat(compressed))
    
    return table.concat(binary_data)
end

local function deserialize_tile_data_binary(binary_data)
    local pos = 1
    
    -- Read header
    local width, height = string.unpack("<I4I4", binary_data, pos)
    pos = pos + 8
    
    -- Decompress tile data
    local tile_data = {}
    for y = 1, height do
        tile_data[y] = {}
    end
    
    local x, y = 1, 1
    while pos <= #binary_data do
        local tile_id, count = string.unpack("<I2I4", binary_data, pos)
        pos = pos + 6
        
        -- Fill tiles with RLE data
        for i = 1, count do
            if y <= height and x <= width then
                tile_data[y][x] = tile_id
                x = x + 1
                if x > width then
                    x = 1
                    y = y + 1
                end
            end
        end
    end
    
    return tile_data, width, height
end

-- Save map to file
function map_serializer.save_map(map_object, file_path, format)
    format = format or "json" -- "json" or "binary"
    
    local map_def = map_object.definition
    local save_data = {
        version = "1.0",
        format = format,
        created = os.date("%Y-%m-%d %H:%M:%S"),
        map_definition = {
            id = map_def.id,
            name = map_def.name,
            tileset_path = map_def.tileset_path,
            tile_width = map_def.tile_width,
            tile_height = map_def.tile_height,
            map_width = map_def.map_width,
            map_height = map_def.map_height,
            world_x = map_def.world_x,
            world_y = map_def.world_y,
            player_spawn = map_def.player_spawn,
            enemies = map_def.enemies,
            collectibles = map_def.collectibles,
            interactables = map_def.interactables
        }
    }
    
    local success, err = pcall(function()
        if format == "binary" then
            -- Save metadata as JSON, tile data as binary
            local metadata = serialize_value(save_data, 0)
            local tile_binary = serialize_tile_data_binary(map_object.tile_data, map_object.width, map_object.height)
            
            local file = io.open(file_path, "wb")
            if not file then
                error("Could not open file for writing: " .. file_path)
            end
            
            -- Write metadata length + metadata + binary tile data
            local metadata_length = #metadata
            file:write(string.pack("<I4", metadata_length))
            file:write(metadata)
            file:write(tile_binary)
            file:close()
        else
            -- Pure JSON format
            save_data.tile_data = map_object.tile_data
            local json_data = serialize_value(save_data, 0)
            
            local file = io.open(file_path, "w")
            if not file then
                error("Could not open file for writing: " .. file_path)
            end
            
            file:write(json_data)
            file:close()
        end
    end)
    
    if not success then
        print("Error saving map: " .. tostring(err))
        return false
    end
    
    print("Map saved successfully: " .. file_path .. " (format: " .. format .. ")")
    return true
end

-- Simple JSON parser for loading
local function parse_json_value(str, pos)
    pos = pos or 1
    
    -- Skip whitespace
    while pos <= #str and str:sub(pos, pos):match("%s") do
        pos = pos + 1
    end
    
    if pos > #str then return nil, pos end
    
    local char = str:sub(pos, pos)
    
    if char == '"' then
        -- String
        pos = pos + 1
        local start = pos
        while pos <= #str and str:sub(pos, pos) ~= '"' do
            if str:sub(pos, pos) == '\\' then pos = pos + 1 end
            pos = pos + 1
        end
        local value = str:sub(start, pos - 1):gsub('\\"', '"')
        return value, pos + 1
    elseif char:match("[%d%-]") then
        -- Number
        local start = pos
        while pos <= #str and str:sub(pos, pos):match("[%d%-%+%.eE]") do
            pos = pos + 1
        end
        return tonumber(str:sub(start, pos - 1)), pos
    elseif char == '[' then
        -- Array
        local array = {}
        pos = pos + 1
        
        while pos <= #str do
            -- Skip whitespace
            while pos <= #str and str:sub(pos, pos):match("%s") do
                pos = pos + 1
            end
            
            if pos <= #str and str:sub(pos, pos) == ']' then
                return array, pos + 1
            end
            
            local value, new_pos = parse_json_value(str, pos)
            table.insert(array, value)
            pos = new_pos
            
            -- Skip whitespace and comma
            while pos <= #str and str:sub(pos, pos):match("[%s,]") do
                pos = pos + 1
            end
        end
    elseif char == '{' then
        -- Object
        local object = {}
        pos = pos + 1
        
        while pos <= #str do
            -- Skip whitespace
            while pos <= #str and str:sub(pos, pos):match("%s") do
                pos = pos + 1
            end
            
            if pos <= #str and str:sub(pos, pos) == '}' then
                return object, pos + 1
            end
            
            -- Parse key
            local key, new_pos = parse_json_value(str, pos)
            pos = new_pos
            
            -- Skip whitespace and colon
            while pos <= #str and str:sub(pos, pos):match("[%s:]") do
                pos = pos + 1
            end
            
            -- Parse value
            local value, new_pos = parse_json_value(str, pos)
            object[key] = value
            pos = new_pos
            
            -- Skip whitespace and comma
            while pos <= #str and str:sub(pos, pos):match("[%s,]") do
                pos = pos + 1
            end
        end
    elseif str:sub(pos, pos + 3) == "true" then
        return true, pos + 4
    elseif str:sub(pos, pos + 4) == "false" then
        return false, pos + 5
    elseif str:sub(pos, pos + 3) == "null" then
        return nil, pos + 4
    end
    
    return nil, pos
end

-- Load map from file
function map_serializer.load_map(file_path)
    local success, result = pcall(function()
        local file = io.open(file_path, "rb")
        if not file then
            error("Could not open file for reading: " .. file_path)
        end
        
        local content = file:read("*all")
        file:close()
        
        if #content < 4 then
            error("File too small to be valid map data")
        end
        
        -- Try to determine format by checking if it starts with metadata length (binary)
        local metadata_length = string.unpack("<I4", content:sub(1, 4))
        
        local map_data, tile_data
        
        if metadata_length > 0 and metadata_length < #content then
            -- Binary format
            local metadata_str = content:sub(5, 4 + metadata_length)
            local tile_binary = content:sub(5 + metadata_length)
            
            map_data = parse_json_value(metadata_str)
            tile_data = deserialize_tile_data_binary(tile_binary)
        else
            -- JSON format
            map_data = parse_json_value(content)
            tile_data = map_data.tile_data
        end
        
        if not map_data or not map_data.map_definition then
            error("Invalid map data structure")
        end
        
        return {
            metadata = map_data,
            tile_data = tile_data,
            definition = map_data.map_definition
        }
    end)
    
    if not success then
        print("Error loading map: " .. tostring(result))
        return nil
    end
    
    print("Map loaded successfully: " .. file_path)
    return result
end

-- Quick save current map
function map_serializer.quick_save(map_object, slot)
    slot = slot or 1
    local filename = string.format("maps/quicksave_%02d.map", slot)
    
    -- Ensure maps directory exists
    os.execute("mkdir -p maps")
    
    return map_serializer.save_map(map_object, filename, "binary")
end

-- Quick load map
function map_serializer.quick_load(slot)
    slot = slot or 1
    local filename = string.format("maps/quicksave_%02d.map", slot)
    
    return map_serializer.load_map(filename)
end

-- Export map as Lua code for easy embedding
function map_serializer.export_as_lua(map_object, file_path)
    local map_def = map_object.definition
    
    local lua_code = string.format([[-- Auto-generated map: %s
-- Created: %s

local map_data = {
    id = %q,
    name = %q,
    tileset_path = %q,
    tile_width = %d,
    tile_height = %d,
    map_width = %d,
    map_height = %d,
    world_x = %d,
    world_y = %d,
    player_spawn = {x = %d, y = %d},
]], 
        map_def.name,
        os.date("%Y-%m-%d %H:%M:%S"),
        map_def.id,
        map_def.name,
        map_def.tileset_path,
        map_def.tile_width,
        map_def.tile_height,
        map_def.map_width,
        map_def.map_height,
        map_def.world_x,
        map_def.world_y,
        map_def.player_spawn.x,
        map_def.player_spawn.y
    )
    
    -- Add enemies
    lua_code = lua_code .. "    enemies = {\n"
    for _, enemy in ipairs(map_def.enemies) do
        lua_code = lua_code .. string.format("        {x = %d, y = %d, type = %q},\n", 
            enemy.x, enemy.y, enemy.type or "basic")
    end
    lua_code = lua_code .. "    },\n"
    
    -- Add collectibles
    lua_code = lua_code .. "    collectibles = {\n"
    for _, item in ipairs(map_def.collectibles) do
        lua_code = lua_code .. string.format("        {x = %d, y = %d, type = %q},\n", 
            item.x, item.y, item.type or "coin")
    end
    lua_code = lua_code .. "    },\n"
    
    -- Add tile data (compressed representation)
    lua_code = lua_code .. "    tile_data = {\n"
    for y = 1, map_object.height do
        if map_object.tile_data[y] then
            lua_code = lua_code .. "        [" .. y .. "] = {"
            for x = 1, map_object.width do
                if x > 1 then lua_code = lua_code .. "," end
                lua_code = lua_code .. (map_object.tile_data[y][x] or 0)
            end
            lua_code = lua_code .. "},\n"
        end
    end
    lua_code = lua_code .. "    }\n}\n\nreturn map_data"
    
    local success, err = pcall(function()
        local file = io.open(file_path, "w")
        if not file then
            error("Could not open file for writing: " .. file_path)
        end
        file:write(lua_code)
        file:close()
    end)
    
    if not success then
        print("Error exporting map as Lua: " .. tostring(err))
        return false
    end
    
    print("Map exported as Lua: " .. file_path)
    return true
end

-- List available map files
function map_serializer.list_maps(directory)
    directory = directory or "maps"
    local maps = {}
    
    -- Simple directory listing (Unix/Linux)
    local handle = io.popen("ls " .. directory .. "/*.map 2>/dev/null")
    if handle then
        for file in handle:lines() do
            local name = file:match(".*/(.+)%.map$") or file:match("(.+)%.map$")
            if name then
                table.insert(maps, {
                    name = name,
                    path = file
                })
            end
        end
        handle:close()
    end
    
    return maps
end

-- Create map template
function map_serializer.create_template(id, name, width, height, tileset_path)
    return {
        id = id,
        name = name,
        tileset_path = tileset_path or "gfx/TileSet/TX Tileset Grass.png",
        tile_width = 16,
        tile_height = 16,
        map_width = width or 50,
        map_height = height or 50,
        world_x = 0,
        world_y = 0,
        player_spawn = {x = 100, y = 100},
        enemies = {},
        collectibles = {},
        interactables = {}
    }
end

return map_serializer