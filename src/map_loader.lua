local map_loader = {}

-- Asset cache for tilesets and textures
local asset_cache = {
    tilesets = {},
    textures = {},
    max_cache_size = 50, -- Maximum number of cached assets
    access_count = {},   -- Track asset access for LRU eviction
}

-- Map data cache with LRU eviction
local map_cache = {
    loaded_maps = {},
    max_cache_size = 8,  -- Maximum number of cached maps
    access_order = {},   -- LRU tracking
    last_access_time = {},
}

-- Streaming configuration
local streaming_config = {
    enabled = true,
    chunk_size = 32,     -- Load maps in 32x32 tile chunks
    preload_radius = 2,  -- Preload chunks within this radius
    unload_distance = 5, -- Unload chunks beyond this distance
    max_concurrent_loads = 3, -- Maximum simultaneous loading operations
}

-- Active loading operations
local loading_operations = {}

-- Map schema validation
local function validate_map_schema(map_data)
    local required_fields = {
        "id", "name", "tileset_path", "tile_width", "tile_height",
        "map_width", "map_height", "world_x", "world_y"
    }
    
    for _, field in ipairs(required_fields) do
        if not map_data[field] then
            error("Missing required field: " .. field .. " in map: " .. (map_data.id or "unknown"))
        end
    end
    
    -- Validate numeric fields
    local numeric_fields = {"tile_width", "tile_height", "map_width", "map_height", "world_x", "world_y"}
    for _, field in ipairs(numeric_fields) do
        if type(map_data[field]) ~= "number" then
            error("Field " .. field .. " must be a number in map: " .. map_data.id)
        end
    end
    
    return true
end

-- Asset management functions
local function load_tileset(tileset_path)
    if asset_cache.tilesets[tileset_path] then
        asset_cache.access_count[tileset_path] = (asset_cache.access_count[tileset_path] or 0) + 1
        return asset_cache.tilesets[tileset_path]
    end
    
    -- Check if we need to evict old assets
    if #asset_cache.tilesets >= asset_cache.max_cache_size then
        map_loader.evict_least_used_asset()
    end
    
    local success, image = pcall(love.graphics.newImage, tileset_path)
    if not success then
        error("Failed to load tileset: " .. tileset_path .. " - " .. tostring(image))
    end
    
    asset_cache.tilesets[tileset_path] = image
    asset_cache.access_count[tileset_path] = 1
    
    return image
end

function map_loader.evict_least_used_asset()
    local least_used_path = nil
    local least_count = math.huge
    
    for path, count in pairs(asset_cache.access_count) do
        if count < least_count then
            least_count = count
            least_used_path = path
        end
    end
    
    if least_used_path then
        asset_cache.tilesets[least_used_path] = nil
        asset_cache.access_count[least_used_path] = nil
    end
end

-- Chunk-based map loading
local function generate_map_chunk(map_id, chunk_x, chunk_y, chunk_size)
    local chunk_data = {}
    local seed = string.byte(map_id, 1) + chunk_x * 1000 + chunk_y * 10000
    math.randomseed(seed)
    
    for y = 1, chunk_size do
        chunk_data[y] = {}
        for x = 1, chunk_size do
            -- Generate tile based on position and map type
            if map_id == "level1" then
                chunk_data[y][x] = math.random(1, 200)
            elseif map_id == "level2" then
                chunk_data[y][x] = math.random(1, 5)
            else
                chunk_data[y][x] = math.random(1, 100)
            end
        end
    end
    
    math.randomseed(os.time()) -- Reset seed
    return chunk_data
end

-- Map definition registry
local map_definitions = {}

function map_loader.register_map(map_data)
    validate_map_schema(map_data)
    
    -- Set defaults
    map_data.chunk_size = map_data.chunk_size or streaming_config.chunk_size
    map_data.enemies = map_data.enemies or {}
    map_data.collectibles = map_data.collectibles or {}
    map_data.interactables = map_data.interactables or {}
    map_data.player_spawn = map_data.player_spawn or {x = map_data.world_x + 100, y = map_data.world_y + 100}
    
    map_definitions[map_data.id] = map_data
    return true
end

function map_loader.get_map_definition(map_id)
    return map_definitions[map_id]
end

-- Asynchronous map loading with coroutines
function map_loader.load_map_async(map_id, callback)
    if loading_operations[map_id] then
        return false -- Already loading
    end
    
    if #loading_operations >= streaming_config.max_concurrent_loads then
        return false -- Too many concurrent loads
    end
    
    local map_def = map_definitions[map_id]
    if not map_def then
        error("Map definition not found: " .. map_id)
    end
    
    -- Create loading coroutine
    local loading_coroutine = coroutine.create(function()
        local start_time = love.timer.getTime()
        
        -- Load tileset
        local tileset_image = load_tileset(map_def.tileset_path)
        coroutine.yield() -- Allow other operations
        
        -- Generate tile quads
        local tiles = map_loader.create_tileset(tileset_image, map_def.tile_width, map_def.tile_height)
        coroutine.yield()
        
        -- Generate or load tile data
        local tile_data = {}
        local chunks_wide = math.ceil(map_def.map_width / map_def.chunk_size)
        local chunks_high = math.ceil(map_def.map_height / map_def.chunk_size)
        
        for chunk_y = 0, chunks_high - 1 do
            for chunk_x = 0, chunks_wide - 1 do
                local chunk = generate_map_chunk(map_id, chunk_x, chunk_y, map_def.chunk_size)
                
                -- Merge chunk into main tile data
                for y = 1, map_def.chunk_size do
                    local global_y = chunk_y * map_def.chunk_size + y
                    if global_y <= map_def.map_height then
                        if not tile_data[global_y] then tile_data[global_y] = {} end
                        
                        for x = 1, map_def.chunk_size do
                            local global_x = chunk_x * map_def.chunk_size + x
                            if global_x <= map_def.map_width then
                                tile_data[global_y][global_x] = chunk[y][x]
                            end
                        end
                    end
                end
                
                -- Yield periodically to prevent blocking
                if (chunk_x + chunk_y) % 4 == 0 then
                    coroutine.yield()
                end
            end
        end
        
        -- Create map object
        local map_object = {
            id = map_id,
            definition = map_def,
            tiles = tiles,
            tile_data = tile_data,
            world_x = map_def.world_x,
            world_y = map_def.world_y,
            width = map_def.map_width,
            height = map_def.map_height,
            load_time = love.timer.getTime() - start_time,
            last_access = love.timer.getTime()
        }
        
        return map_object
    end)
    
    loading_operations[map_id] = {
        coroutine = loading_coroutine,
        callback = callback,
        start_time = love.timer.getTime()
    }
    
    return true
end

-- Update loading operations (call this every frame)
function map_loader.update(dt)
    local completed_loads = {}
    
    for map_id, operation in pairs(loading_operations) do
        local success, result = coroutine.resume(operation.coroutine)
        
        if not success then
            print("Error loading map " .. map_id .. ": " .. tostring(result))
            table.insert(completed_loads, map_id)
        elseif coroutine.status(operation.coroutine) == "dead" then
            -- Loading completed
            map_loader.cache_map(map_id, result)
            if operation.callback then
                operation.callback(result)
            end
            table.insert(completed_loads, map_id)
        end
    end
    
    -- Clean up completed operations
    for _, map_id in ipairs(completed_loads) do
        loading_operations[map_id] = nil
    end
end

-- Map caching with LRU eviction
function map_loader.cache_map(map_id, map_object)
    -- Remove from cache if already present
    if map_cache.loaded_maps[map_id] then
        map_loader.remove_from_access_order(map_id)
    end
    
    -- Check if we need to evict
    if #map_cache.access_order >= map_cache.max_cache_size then
        local oldest_map_id = table.remove(map_cache.access_order, 1)
        map_cache.loaded_maps[oldest_map_id] = nil
        map_cache.last_access_time[oldest_map_id] = nil
    end
    
    -- Add to cache
    map_cache.loaded_maps[map_id] = map_object
    table.insert(map_cache.access_order, map_id)
    map_cache.last_access_time[map_id] = love.timer.getTime()
end

function map_loader.remove_from_access_order(map_id)
    for i, id in ipairs(map_cache.access_order) do
        if id == map_id then
            table.remove(map_cache.access_order, i)
            break
        end
    end
end

function map_loader.get_cached_map(map_id)
    local map_object = map_cache.loaded_maps[map_id]
    if map_object then
        -- Update access order
        map_loader.remove_from_access_order(map_id)
        table.insert(map_cache.access_order, map_id)
        map_cache.last_access_time[map_id] = love.timer.getTime()
        map_object.last_access = love.timer.getTime()
    end
    return map_object
end

-- Tileset creation utility
function map_loader.create_tileset(tileset_image, tile_width, tile_height)
    local tiles = {
        tileset_image = tileset_image,
        tile_width = tile_width,
        tile_height = tile_height,
        quads = {}
    }
    
    local tiles_wide = math.floor(tileset_image:getWidth() / tile_width)
    local tiles_high = math.floor(tileset_image:getHeight() / tile_height)
    
    local tile_count = 0
    for y = 0, tileset_image:getHeight() - tile_height, tile_height do
        for x = 0, tileset_image:getWidth() - tile_width, tile_width do
            tile_count = tile_count + 1
            tiles.quads[tile_count] = love.graphics.newQuad(x, y, tile_width, tile_height, tileset_image:getDimensions())
        end
    end
    
    return tiles
end

-- High-level loading interface
function map_loader.load_map(map_id, callback)
    -- Check cache first
    local cached_map = map_loader.get_cached_map(map_id)
    if cached_map then
        if callback then callback(cached_map) end
        return cached_map
    end
    
    -- Start async loading
    local success = map_loader.load_map_async(map_id, callback)
    if not success then
        print("Failed to start loading map: " .. map_id)
        return nil
    end
    
    return "loading" -- Indicates async loading in progress
end

-- Synchronous loading for immediate use
function map_loader.load_map_sync(map_id)
    local cached_map = map_loader.get_cached_map(map_id)
    if cached_map then
        return cached_map
    end
    
    local map_def = map_definitions[map_id]
    if not map_def then
        error("Map definition not found: " .. map_id)
    end
    
    local start_time = love.timer.getTime()
    
    -- Load assets
    local tileset_image = load_tileset(map_def.tileset_path)
    local tiles = map_loader.create_tileset(tileset_image, map_def.tile_width, map_def.tile_height)
    
    -- Generate tile data
    local tile_data = {}
    for y = 1, map_def.map_height do
        tile_data[y] = {}
        for x = 1, map_def.map_width do
            if map_id == "level1" then
                tile_data[y][x] = math.random(1, 200)
            elseif map_id == "level2" then
                tile_data[y][x] = math.random(1, 5)
            else
                tile_data[y][x] = math.random(1, 100)
            end
        end
    end
    
    local map_object = {
        id = map_id,
        definition = map_def,
        tiles = tiles,
        tile_data = tile_data,
        world_x = map_def.world_x,
        world_y = map_def.world_y,
        width = map_def.map_width,
        height = map_def.map_height,
        load_time = love.timer.getTime() - start_time,
        last_access = love.timer.getTime()
    }
    
    map_loader.cache_map(map_id, map_object)
    return map_object
end

-- Clean up and memory management
function map_loader.cleanup()
    -- Clear all caches
    map_cache.loaded_maps = {}
    map_cache.access_order = {}
    map_cache.last_access_time = {}
    
    asset_cache.tilesets = {}
    asset_cache.access_count = {}
    
    -- Cancel all loading operations
    loading_operations = {}
    
    collectgarbage()
end

function map_loader.get_memory_usage()
    local map_count = 0
    local asset_count = 0
    
    for _ in pairs(map_cache.loaded_maps) do map_count = map_count + 1 end
    for _ in pairs(asset_cache.tilesets) do asset_count = asset_count + 1 end
    
    return {
        cached_maps = map_count,
        cached_assets = asset_count,
        loading_operations = #loading_operations,
        lua_memory = collectgarbage("count")
    }
end

return map_loader