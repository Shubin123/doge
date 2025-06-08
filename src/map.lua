local map = {}
local map_manager = require("map_manager")

-- Legacy compatibility layer - redirect to new system
map.currentMapId = "level1"
map.mapDefinitions = {}
map.loadedMaps = {}

-- Map data definition structure
function map.defineMap(mapId, definition)
    map.mapDefinitions[mapId] = {
        id = mapId,
        name = definition.name or mapId,
        tileset = definition.tileset,
        tileWidth = definition.tileWidth or 16,
        tileHeight = definition.tileHeight or 16,
        mapWidth = definition.mapWidth or 256,
        mapHeight = definition.mapHeight or 256,
        tileData = definition.tileData or {},
        enemies = definition.enemies or {},
        collectibles = definition.collectibles or {},
        playerSpawn = definition.playerSpawn or {x = 400, y = 400},
        interactables = definition.interactables or {}
    }
end

function newTiles(tilesetImage, tileWidth, tileHeight)
    local tiles = {}
    tiles.tilesetImage = tilesetImage
    tiles.tileWidth = tileWidth
    tiles.tileHeight = tileHeight
    tiles.quads = {}
    
    local tilesWide = math.floor(tilesetImage:getWidth() / tileWidth)
    local tilesHigh = math.floor(tilesetImage:getHeight() / tileHeight)
    
    local tileCount = 0
    for y = 0, tilesetImage:getHeight() - tileHeight, tileHeight do
        for x = 0, tilesetImage:getWidth() - tileWidth, tileWidth do
            tileCount = tileCount + 1
            tiles.quads[tileCount] = love.graphics.newQuad(x, y, tileWidth, tileHeight, tilesetImage:getDimensions())
        end
    end
    return tiles
end

function createMap(tiles, mapWidth, mapHeight, tileData, worldX, worldY)
    local map = {}
    map.tiles = tiles
    map.width = mapWidth
    map.height = mapHeight
    map.tileData = tileData or {}
    map.worldX = worldX or 0  -- World coordinate offset
    map.worldY = worldY or 0  -- World coordinate offset
    
    if not tileData then
        for y = 1, mapHeight do
            map.tileData[y] = {}
            for x = 1, mapWidth do
                map.tileData[y][x] = 0
            end
        end
    end
    
    map.draw = function(self, offsetX, offsetY, scale)
        offsetX = offsetX or 0
        offsetY = offsetY or 0
        scale = scale or 1
        
        -- Calculate world bounds for this map
        local map_world_x = self.worldX + offsetX
        local map_world_y = self.worldY + offsetY
        
        -- Use camera culling to determine visible tile range
        local tile_width_scaled = self.tiles.tileWidth * scale
        local tile_height_scaled = self.tiles.tileHeight * scale
        
        -- Calculate which tiles are potentially visible
        local start_col = math.max(1, math.floor((camera.view_bounds.x1 - map_world_x) / tile_width_scaled) + 1)
        local end_col = math.min(self.width, math.ceil((camera.view_bounds.x2 - map_world_x) / tile_width_scaled) + 1)
        local start_row = math.max(1, math.floor((camera.view_bounds.y1 - map_world_y) / tile_height_scaled) + 1)
        local end_row = math.min(self.height, math.ceil((camera.view_bounds.y2 - map_world_y) / tile_height_scaled) + 1)
        
        for row = start_row, end_row do
            for col = start_col, end_col do
                local tileId = self.tileData[row] and self.tileData[row][col]
                if tileId and tileId > 0 and self.tiles.quads[tileId] then
                    local tile_world_x = map_world_x + (col-1) * tile_width_scaled
                    local tile_world_y = map_world_y + (row-1) * tile_height_scaled
                    
                    -- Additional frustum culling check
                    if camera.isInView(tile_world_x, tile_world_y, tile_width_scaled, tile_height_scaled) then
                        love.graphics.draw(
                            self.tiles.tilesetImage,
                            self.tiles.quads[tileId],
                            tile_world_x,
                            tile_world_y,
                            0,
                            scale,
                            scale
                        )
                    end
                end
            end
        end
    end
    
    map.setTile = function(self, tileX, tileY, tileId)
        if tileX >= 1 and tileX <= self.width and tileY >= 1 and tileY <= self.height then
            self.tileData[tileY][tileX] = tileId
        end
    end
    
    map.getTile = function(self, tileX, tileY)
        if tileX >= 1 and tileX <= self.width and tileY >= 1 and tileY <= self.height then
            return self.tileData[tileY][tileX]
        end
        return 0
    end
    
    -- Convert world coordinates to tile coordinates
    map.worldToTile = function(self, worldX, worldY, scale)
        scale = scale or 1
        local tile_width_scaled = self.tiles.tileWidth * scale
        local tile_height_scaled = self.tiles.tileHeight * scale
        local relative_x = worldX - self.worldX
        local relative_y = worldY - self.worldY
        local tileX = math.floor(relative_x / tile_width_scaled) + 1
        local tileY = math.floor(relative_y / tile_height_scaled) + 1
        return tileX, tileY
    end
    
    -- Convert tile coordinates to world coordinates
    map.tileToWorld = function(self, tileX, tileY, scale)
        scale = scale or 1
        local tile_width_scaled = self.tiles.tileWidth * scale
        local tile_height_scaled = self.tiles.tileHeight * scale
        local worldX = self.worldX + (tileX - 1) * tile_width_scaled
        local worldY = self.worldY + (tileY - 1) * tile_height_scaled
        return worldX, worldY
    end
    return map
end

-- Load a specific map by ID
function map.loadMap(mapId)
    print("DEPRECATION WARNING: map.loadMap() is deprecated. Use MapManager.switchToMap() instead.")
    
    -- Forward to new system with blocking wait for legacy compatibility
    local success = false
    local completed = false
    
    map_manager.switchToMap(mapId, function(result, error)
        success = result
        completed = true
        if not result then
            print("Error loading map " .. mapId .. ": " .. tostring(error))
        end
    end)
    
    -- Block until completion for legacy sync behavior
    while not completed do
        coroutine.yield()
    end
    
    if success then
        map.currentMapId = mapId
        -- Update legacy data structures for compatibility
        local context = map_manager.getCurrentContext()
        if context then
            map.loadedMaps[mapId] = {
                definition = { id = mapId },
                context = context
            }
        end
    end
    
    return success
end

-- Unload a specific map
function map.unloadMap(mapId)
    print("DEPRECATION WARNING: map.unloadMap() is deprecated. Use MapManager.unloadContext() instead.")
    
    -- Forward to new system
    map_manager.unloadContext(mapId)
    
    -- Clean up legacy data structures
    if map.loadedMaps[mapId] then
        map.loadedMaps[mapId] = nil
        collectgarbage()
    end
end

-- Switch to a different map
function map.switchToMap(mapId)
    print("DEPRECATION WARNING: map.switchToMap() is deprecated. Use MapManager.switchToMap() instead.")
    
    -- Forward to new system with blocking wait for legacy compatibility
    local success = false
    local completed = false
    
    map_manager.switchToMap(mapId, function(result, error)
        success = result
        completed = true
        if not result then
            print("Failed to switch to map " .. mapId .. ": " .. tostring(error))
        end
    end)
    
    -- Block until completion for legacy sync behavior
    while not completed do
        coroutine.yield()
    end
    
    if success then
        map.currentMapId = mapId
        -- Update legacy data structures for compatibility
        local context = map_manager.getCurrentContext()
        if context then
            map.loadedMaps[mapId] = {
                definition = { id = mapId },
                context = context
            }
        end
    end
    
    return success
end

-- Get current map data
function map.getCurrentMap()
    print("DEPRECATION WARNING: map.getCurrentMap() is deprecated. Use MapManager.getCurrentContext() instead.")
    
    -- Try new system first
    local context = map_manager.getCurrentContext()
    if context and context.definition then
        return {
            definition = context.definition,
            context = context
        }
    end
    
    -- Fallback to legacy data
    return map.loadedMaps[map.currentMapId]
end

-- Add current map tiles to dynamic draw list for proper GI rendering
function map.addCurrentMapToDrawList()
    print("DEPRECATION WARNING: map.addCurrentMapToDrawList() is deprecated. Use MapManager drawing system instead.")
    
    -- Forward to new system - MapManager handles drawing internally
    local context = map_manager.getCurrentContext()
    if context then
        -- New system handles this automatically through context:draw()
        return {}
    end
    
    -- Fallback to legacy system
    local currentMap = map.getCurrentMap()
    if not currentMap then return {} end
    
    -- Use world coordinates instead of screen offsets
    return addMapToDynamicDrawList(currentMap.map, 0, 0, 1, 0)
end

-- Spawn entities for current map
function map.spawnMapEntities()
    print("DEPRECATION WARNING: map.spawnMapEntities() is deprecated. New MapManager system handles entity spawning automatically.")
    -- New system handles entity spawning internally during map loading
    -- This function kept for compatibility but no action needed
end

function map.load()
    print("DEPRECATION WARNING: map.load() is deprecated. Initialize MapManager directly and use switchToMap().")
    
    -- Initialize the new map manager system - requires physics world
    if not map_manager.world then
        print("Warning: MapManager not initialized with physics world. Legacy system may not work properly.")
    end
    
    -- Try to load initial map using new system
    local success = false
    local completed = false
    
    map_manager.switchToMap("level1", function(result, error)
        success = result
        completed = true
        if result then
            print("Initial map loaded via MapManager: level1")
            map.currentMapId = "level1"
        else
            print("Failed to load initial map via MapManager: " .. tostring(error))
        end
    end)
    
    -- Block until completion for legacy sync behavior
    while not completed do
        coroutine.yield()
    end
    
    -- Fallback to legacy system if new system failed
    if not success then
        print("Falling back to legacy map loading system")
        map.loadLegacyMaps()
    end
end

-- Fallback legacy map loading
function map.loadLegacyMaps()
    -- Keep legacy maps for compatibility with existing render code but use world coordinates
    local tilesetImage = love.graphics.newImage("gfx/TileSet/TX Tileset Grass.png")
    
    map.tiles = newTiles(tilesetImage, var.tile_w, var.tile_h)
    map.map = createMap(map.tiles, var.map_display_w, var.map_display_h, nil, 0, 0)
    for x = 1, 70 do 
        for y = 1, 50 do
            map.map:setTile(x, y, math.random(1,200))
        end
    end

    local tilesetImage3 = love.graphics.newImage("gfx/TileSet/TX Struct.png")
    map.tiles3 = newTiles(tilesetImage3, 98, 128)
    map.map3 = createMap(map.tiles3, var.map_display_w, var.map_display_h, nil, 100, 50)  -- World coordinates
    for x = 2, 5 do
        for y = 1, 3 do
            map.map3:setTile(x, y, 10)
        end
    end

    local tilesetImage4 = love.graphics.newImage("gfx/TileSet/TX Plant.png")
    map.tiles4 = newTiles(tilesetImage4, 156, 156)
    map.map4 = createMap(map.tiles4, var.map_display_w, var.map_display_h, nil, 100, 50)  -- World coordinates
    
    for x = 0, 3 do
        map.map4:setTile(2+x, 3, 1)
    end
end

-- function map.getMap()
--     return map.map
-- end

-- Add new map system interface functions
function map.update(dt)
    map_manager.update(dt)
end

function map.getCurrentMapObject()
    print("DEPRECATION WARNING: map.getCurrentMapObject() is deprecated. Use MapManager.getCurrentContext() instead.")
    return map_manager.getCurrentContext()
end

function map.getWorldBounds()
    print("DEPRECATION WARNING: map.getWorldBounds() is deprecated. Access bounds through MapContext instead.")
    local context = map_manager.getCurrentContext()
    if context and context.getWorldBounds then
        return context:getWorldBounds()
    end
    return nil
end

function map.isLoading()
    print("DEPRECATION WARNING: map.isLoading() is deprecated. Use MapManager progress callbacks instead.")
    -- Check if any async operations are in progress
    return map_manager.getCurrentContext() == nil and map.currentMapId ~= nil
end

function map.getTileAtWorldPos(world_x, world_y)
    print("DEPRECATION WARNING: map.getTileAtWorldPos() is deprecated. Access tiles through MapContext instead.")
    local context = map_manager.getCurrentContext()
    if context and context.getTileAtWorldPos then
        return context:getTileAtWorldPos(world_x, world_y)
    end
    return nil
end

function map.setTileAtWorldPos(world_x, world_y, tile_id)
    print("DEPRECATION WARNING: map.setTileAtWorldPos() is deprecated. Access tiles through MapContext instead.")
    local context = map_manager.getCurrentContext()
    if context and context.setTileAtWorldPos then
        return context:setTileAtWorldPos(world_x, world_y, tile_id)
    end
    return false
end

function map.getDebugInfo()
    print("DEPRECATION WARNING: map.getDebugInfo() is deprecated. Access debug info through MapContext instead.")
    local context = map_manager.getCurrentContext()
    if context and context.getDebugInfo then
        return context:getDebugInfo()
    end
    return {}
end

function map.cleanup()
    print("DEPRECATION WARNING: map.cleanup() is deprecated. Use MapManager.unloadAll() instead.")
    map_manager.unloadAll()
end

return map
