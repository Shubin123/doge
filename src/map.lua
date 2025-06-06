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
    if not map.mapDefinitions[mapId] then
        print("Error: Map definition not found for " .. mapId)
        return false
    end
    
    local mapDef = map.mapDefinitions[mapId]
    
    -- Load tileset
    local tilesetImage = love.graphics.newImage(mapDef.tileset)
    local tiles = newTiles(tilesetImage, mapDef.tileWidth, mapDef.tileHeight)
    local mapObject = createMap(tiles, mapDef.mapWidth, mapDef.mapHeight, mapDef.tileData, mapDef.worldX or 0, mapDef.worldY or 0)
    
    -- Store loaded map
    map.loadedMaps[mapId] = {
        definition = mapDef,
        map = mapObject,
        tiles = tiles
    }
    
    return true
end

-- Unload a specific map
function map.unloadMap(mapId)
    if map.loadedMaps[mapId] then
        map.loadedMaps[mapId] = nil
        collectgarbage()
    end
end

-- Switch to a different map
function map.switchToMap(mapId)
    if not map.loadedMaps[mapId] then
        if not map.loadMap(mapId) then
            return false
        end
    end
    
    -- Unload current map if different
    if map.currentMapId ~= mapId and map.loadedMaps[map.currentMapId] then
        map.unloadMap(map.currentMapId)
    end
    
    map.currentMapId = mapId
    return true
end

-- Get current map data
function map.getCurrentMap()
    return map.loadedMaps[map.currentMapId]
end

-- Add current map tiles to dynamic draw list for proper GI rendering
function map.addCurrentMapToDrawList()
    -- Use new map manager system
    local tiles = map_manager.get_visible_tiles()
    if #tiles > 0 then
        return tiles
    end
    
    -- Fallback to legacy system
    local currentMap = map.getCurrentMap()
    if not currentMap then return {} end
    
    -- Use world coordinates instead of screen offsets
    return addMapToDynamicDrawList(currentMap.map, 0, 0, 1, 0)
end

-- Spawn entities for current map
function map.spawnMapEntities()
    -- Use new map manager system - it handles entity spawning internally
    -- This function kept for compatibility but actual work is done by map_manager
    print("Legacy map.spawnMapEntities() called - new system handles this automatically")
end

function map.load()
    -- Initialize the new map manager system
    map_manager.initialize()
    
    -- Load the first map using the new system
    local result = map_manager.switch_to_map("level1", function(loaded_map)
        print("Initial map loaded: " .. loaded_map.id)
    end)
    
    if not result then
        print("Failed to load initial map, falling back to legacy system")
        map.loadLegacyMaps()
    else
        map.currentMapId = "level1"
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

function map.switchToMap(map_id, callback)
    return map_manager.switch_to_map(map_id, callback)
end

function map.getCurrentMapObject()
    return map_manager.get_current_map()
end

function map.getWorldBounds()
    return map_manager.get_world_bounds()
end

function map.isLoading()
    return map_manager.is_loading()
end

function map.getTileAtWorldPos(world_x, world_y)
    return map_manager.get_tile_at_world_pos(world_x, world_y)
end

function map.setTileAtWorldPos(world_x, world_y, tile_id)
    return map_manager.set_tile_at_world_pos(world_x, world_y, tile_id)
end

function map.getDebugInfo()
    return map_manager.get_debug_info()
end

function map.cleanup()
    map_manager.cleanup()
end

return map