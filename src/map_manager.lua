local map_manager = {}
local MapContext = require("map_context")

-- Map context registry
local currentContext = nil
local contextRegistry = {}
local progressCallbacks = {}

-- Initialize the map manager
function map_manager.initialize(world)
    assert(world, "MapManager requires a physics world")
    print("DEBUG: Initializing map manager with physics world")
    map_manager.world = world
end

-- Add progress callback for map loading events
function map_manager.addProgressCallback(callback)
    assert(type(callback) == "function", "Progress callback must be a function")
    table.insert(progressCallbacks, callback)
end

-- Remove progress callback
function map_manager.removeProgressCallback(callback)
    for i, cb in ipairs(progressCallbacks) do
        if cb == callback then
            table.remove(progressCallbacks, i)
            break
        end
    end
end

-- Emit progress event to all registered callbacks
local function emitProgress(stage, progress, message)
    for _, callback in ipairs(progressCallbacks) do
        callback(stage, progress, message)
    end
end

-- Switch to a different map asynchronously
function map_manager.switchToMap(mapId, onComplete)
    assert(type(mapId) == "string" and mapId ~= "", "switchToMap requires a valid map ID")
    assert(map_manager.world, "MapManager not initialized with physics world")
    
    -- Configuration for chunked loading
    local chunkSize = 50  -- Process this many items per chunk
    
    -- Start async loading process
    coroutine.wrap(function()
        emitProgress("unloading", 0.0, "Unloading current map...")
        
        -- Unload current context if exists
        if currentContext then
            currentContext:unload()
            currentContext = nil
        end
        coroutine.yield()
        
        emitProgress("parsing_metadata", 0.05, "Parsing metadata...")
        
        -- Create new context
        local context = MapContext:new(map_manager.world)
        
        -- Load the map with chunked processing
        local success, err = pcall(function()
            map_manager.loadMapChunked(context, mapId, chunkSize)
        end)
        
        if not success then
            emitProgress("error", 1.0, "Failed to load map: " .. tostring(err))
            if onComplete then onComplete(false, err) end
            return
        end
        
        emitProgress("finalizing", 0.95, "Finalizing map setup...")
        coroutine.yield()
        
        -- Register the context
        contextRegistry[mapId] = context
        currentContext = context
        
        emitProgress("complete", 1.0, "Map loaded successfully")
        
        if onComplete then onComplete(true) end
    end)()
end

-- Get current map context
function map_manager.getCurrentContext()
    return currentContext
end

-- Update current map context
function map_manager.update(dt)
    if currentContext then
        currentContext:update(dt)
    end
end

-- Draw current map context
function map_manager.draw(camera)
    if currentContext then
        currentContext:draw(camera)
    end
end

-- Unload a specific map context
function map_manager.unloadContext(mapId)
    local context = contextRegistry[mapId]
    if context then
        context:unload()
        contextRegistry[mapId] = nil
        if currentContext == context then
            currentContext = nil
        end
    end
end

-- Unload all map contexts
function map_manager.unloadAll()
    for mapId, context in pairs(contextRegistry) do
        context:unload()
    end
    contextRegistry = {}
    currentContext = nil
end

-- Get loaded context IDs
function map_manager.getLoadedContexts()
    local contexts = {}
    for mapId, _ in pairs(contextRegistry) do
        table.insert(contexts, mapId)
    end
    return contexts
end

-- Check if a context is loaded
function map_manager.isContextLoaded(mapId)
    return contextRegistry[mapId] ~= nil
end

-- Get specific context by ID
function map_manager.getContext(mapId)
    return contextRegistry[mapId]
end


-- Chunked map loading function
function map_manager.loadMapChunked(context, mapId, chunkSize)
    emitProgress("parsing_metadata", 0.1, "Loading map descriptor...")
    
    -- Load map descriptor (lightweight operation)
    local MapDescriptor = require("map_descriptor")
    local descriptor = MapDescriptor.loadDescriptor(mapId)
    coroutine.yield()
    
    emitProgress("parsing_metadata", 0.15, "Reading map file...")
    
    -- Read the full map file
    local mapFile = "maps/" .. mapId .. ".map"
    local content = love.filesystem.read(mapFile)
    if not content then
        error("Could not read map file: " .. mapFile)
    end
    
    -- Parse map sections
    local sections = {}
    local currentSection = nil
    local lines = {}
    for line in content:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    
    -- Parse sections from lines
    for i, line in ipairs(lines) do
        if line:match("^%[(.+)%]$") then
            currentSection = line:match("^%[(.+)%]$")
            sections[currentSection] = {}
        elseif currentSection and line ~= "" then
            table.insert(sections[currentSection], line)
        end
    end
    
    coroutine.yield()
    emitProgress("parsing_metadata", 0.2, "Processing map metadata...")
    
    -- Process metadata
    local mapData = {
        metadata = {},
        tileset = nil,
        dimensions = {},
        tiles = {},
        entities = {}
    }
    
    -- Parse metadata section
    if sections.metadata then
        for _, line in ipairs(sections.metadata) do
            local key, value = line:match("^(%w+)=(.+)$")
            if key and value then
                mapData.metadata[key] = value
            end
        end
    end
    
    -- Parse tileset
    if sections.tileset and sections.tileset[1] then
        mapData.tileset = sections.tileset[1]
    end
    
    -- Parse dimensions
    if sections.dimensions and sections.dimensions[1] then
        local w, h = sections.dimensions[1]:match("^(%d+)x(%d+)$")
        if w and h then
            mapData.dimensions.width = tonumber(w)
            mapData.dimensions.height = tonumber(h)
        end
    end
    
    coroutine.yield()
    emitProgress("loading_tiles", 0.25, "Loading tiles...")
    
    -- Parse tiles in chunks
    if sections.tiles then
        local totalTiles = #sections.tiles
        local processedTiles = 0
        
        for i = 1, totalTiles, chunkSize do
            local endIdx = math.min(i + chunkSize - 1, totalTiles)
            
            -- Process chunk of tiles
            for j = i, endIdx do
                local line = sections.tiles[j]
                local x, y, tileId = line:match("^(%d+),(%d+),(%d+)$")
                if x and y and tileId then
                    table.insert(mapData.tiles, {
                        x = tonumber(x),
                        y = tonumber(y),
                        id = tonumber(tileId)
                    })
                end
                processedTiles = processedTiles + 1
            end
            
            -- Update progress and yield
            local tileProgress = 0.25 + (processedTiles / totalTiles) * 0.4  -- 25% to 65%
            emitProgress("loading_tiles", tileProgress, 
                string.format("Loading tiles... (%d/%d)", processedTiles, totalTiles))
            coroutine.yield()
        end
    end
    
    emitProgress("spawning_entities", 0.65, "Spawning entities...")
    
    -- Parse entities in chunks
    if sections.entities then
        local totalEntities = #sections.entities
        local processedEntities = 0
        
        for i = 1, totalEntities, chunkSize do
            local endIdx = math.min(i + chunkSize - 1, totalEntities)
            
            -- Process chunk of entities
            for j = i, endIdx do
                local line = sections.entities[j]
                local entityType, x, y, params = line:match("^(%w+),([%d%.%-]+),([%d%.%-]+),?(.*)$")
                if entityType and x and y then
                    table.insert(mapData.entities, {
                        type = entityType,
                        x = tonumber(x),
                        y = tonumber(y),
                        params = params or ""
                    })
                end
                processedEntities = processedEntities + 1
            end
            
            -- Update progress and yield
            local entityProgress = 0.65 + (processedEntities / totalEntities) * 0.25  -- 65% to 90%
            emitProgress("spawning_entities", entityProgress, 
                string.format("Spawning entities... (%d/%d)", processedEntities, totalEntities))
            coroutine.yield()
        end
    end
    
    emitProgress("finalizing", 0.9, "Creating physics bodies...")
    
    -- Apply the loaded data to the context
    -- This would typically involve creating physics bodies, loading textures, etc.
    context.mapData = mapData
    context.descriptor = descriptor
    
    -- Simulate physics body creation with chunked processing
    local totalBodies = #mapData.tiles + #mapData.entities
    if totalBodies > 0 then
        local processedBodies = 0
        
        -- Process tiles for physics (if needed)
        for i = 1, #mapData.tiles, chunkSize do
            local endIdx = math.min(i + chunkSize - 1, #mapData.tiles)
            
            for j = i, endIdx do
                local tile = mapData.tiles[j]
                -- Create physics body for solid tiles (implementation would go here)
                processedBodies = processedBodies + 1
            end
            
            local bodyProgress = 0.9 + (processedBodies / totalBodies) * 0.05  -- 90% to 95%
            emitProgress("finalizing", bodyProgress, 
                string.format("Creating physics bodies... (%d/%d)", processedBodies, totalBodies))
            coroutine.yield()
        end
        
        -- Process entities for physics
        for i = 1, #mapData.entities, chunkSize do
            local endIdx = math.min(i + chunkSize - 1, #mapData.entities)
            
            for j = i, endIdx do
                local entity = mapData.entities[j]
                -- Create physics body for entities (implementation would go here)
                processedBodies = processedBodies + 1
            end
            
            local bodyProgress = 0.9 + (processedBodies / totalBodies) * 0.05  -- 90% to 95%
            emitProgress("finalizing", bodyProgress, 
                string.format("Creating physics bodies... (%d/%d)", processedBodies, totalBodies))
            coroutine.yield()
        end
    end
    
    coroutine.yield()
end

return map_manager
