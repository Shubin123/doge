-- Map System Mod - Core map generation and management
-- Migrated from legacy src/game/map.lua to modular architecture

local mapSystemMod = {}

-- Mod state
local map = {}
local mod_config = {}
local performance = {}

-- Configuration
local MAP_CONFIG = {
    CHUNK_SIZE = 16,
    VISIBLE_CHUNKS_RADIUS = 3,
    MAX_POOL_SIZE = 100,
    LAYER_GROUND = 1,
    LAYER_DECORATION = 2,
    LAYER_COLLISION = 3,
    LAYER_OVERLAY = 4,
    Z_OFFSET_TILE = 0,
    Z_OFFSET_DECORATION = 100,
    Z_OFFSET_OBJECT = 200,
    Z_OFFSET_OVERLAY = 300,
}

-- Object pools for performance
local objectPools = {
    drawItems = {},
    chunks = {},
}

-- Store object instances
map.archInstances = {}
map.treeInstances = {}
map.dynamicObjects = {}
map.chunks = {}
map.layers = {}

-- Performance monitoring
performance = {
    chunksRendered = 0,
    tilesRendered = 0,
    objectsRendered = 0,
    lastFrameTime = 0,
}

-- Initialize object pool
local function initPool(poolName, createFunc, resetFunc)
    objectPools[poolName] = objectPools[poolName] or {
        items = {},
        createFunc = createFunc,
        resetFunc = resetFunc,
        active = 0,
    }
end

-- Get object from pool
local function getFromPool(poolName)
    local pool = objectPools[poolName]
    if #pool.items > 0 then
        return table.remove(pool.items)
    else
        return pool.createFunc()
    end
end

-- Return object to pool
local function returnToPool(poolName, obj)
    local pool = objectPools[poolName]
    if #pool.items < MAP_CONFIG.MAX_POOL_SIZE then
        pool.resetFunc(obj)
        table.insert(pool.items, obj)
    end
end

-- Chunk management for large maps
local function getChunkKey(cx, cy)
    return cx .. "," .. cy
end

local function worldToChunk(x, y, tileSize)
    local cx = math.floor(x / (MAP_CONFIG.CHUNK_SIZE * tileSize))
    local cy = math.floor(y / (MAP_CONFIG.CHUNK_SIZE * tileSize))
    return cx, cy
end

local function createChunk(cx, cy)
    local chunk = {
        x = cx,
        y = cy,
        tiles = {},
        objects = {},
        dirty = true,
        lastAccess = api.utils.getTime(),
    }

    for y = 1, MAP_CONFIG.CHUNK_SIZE do
        chunk.tiles[y] = {}
        for x = 1, MAP_CONFIG.CHUNK_SIZE do
            chunk.tiles[y][x] = {}
        end
    end

    return chunk
end

-- Tileset creation
function newTiles(tilesetImage, tileWidth, tileHeight, api)
    local tiles = {}
    tiles.tilesetImage = tilesetImage
    tiles.tileWidth = tileWidth
    tiles.tileHeight = tileHeight
    tiles.quads = {}
    
    local tileCount = 0
    for y = 0, tilesetImage:getHeight() - tileHeight, tileHeight do
        for x = 0, tilesetImage:getWidth() - tileWidth, tileWidth do
            tileCount = tileCount + 1
            tiles.quads[tileCount] = api.renderer.createQuad(x, y, tileWidth, tileHeight, tilesetImage:getDimensions())
        end
    end
    return tiles
end

-- Enhanced tile system with metadata
function map.newTilesetAdvanced(config)
    local tileset = {
        image = config.image,
        tileWidth = config.tileWidth,
        tileHeight = config.tileHeight,
        quads = {},
        metadata = {},
        animations = {},
    }

    local tilesWide = math.floor(tileset.image:getWidth() / tileset.tileWidth)
    local tilesHigh = math.floor(tileset.image:getHeight() / tileset.tileHeight)

    local tileId = 0
    for y = 0, tilesHigh - 1 do
        for x = 0, tilesWide - 1 do
            tileId = tileId + 1
            tileset.quads[tileId] = api.renderer.createQuad(
                x * tileset.tileWidth,
                y * tileset.tileHeight,
                tileset.tileWidth,
                tileset.tileHeight,
                tileset.image:getDimensions()
            )

            tileset.metadata[tileId] = config.metadata and config.metadata[tileId] or {
                walkable = true,
                transparent = true,
                friction = 1.0,
                tags = {},
            }
        end
    end

    if config.animations then
        for animName, animData in pairs(config.animations) do
            tileset.animations[animName] = {
                frames = animData.frames,
                duration = animData.duration,
                currentFrame = 1,
                timer = 0,
            }
        end
    end

    return tileset
end

-- Create basic map
function createMap(tiles, mapWidth, mapHeight, tileData)
    local mapData = {}
    mapData.tiles = tiles
    mapData.width = mapWidth
    mapData.height = mapHeight
    mapData.tileData = tileData or {}
    
    if not tileData then
        for y = 1, mapHeight do
            mapData.tileData[y] = {}
            for x = 1, mapWidth do
                mapData.tileData[y][x] = 0
            end
        end
    end
    
    mapData.draw = function(self, x, y, scale)
        x = x or 0
        y = y or 0
        scale = scale or 1
        local max_tiles_x = math.ceil(mod_config.game_width / (self.tiles.tileWidth * scale)) + 200
        local max_tiles_y = math.ceil(mod_config.game_height / (self.tiles.tileHeight * scale))
        for row = 1, max_tiles_y do
            for col = 1, max_tiles_x do
                local tileId = self.tileData[row] and self.tileData[row][col]
                if tileId and tileId > 0 and self.tiles.quads[tileId] then
                    -- Note: This draw function is for legacy compatibility
                    -- In practice, the mod should use api.renderer.addToQueue
                    -- This function might be called from legacy code
                end
            end
        end
    end
    
    mapData.setTile = function(self, x, y, tileId)
        if x >= 1 and x <= self.width and y >= 1 and y <= self.height then
            self.tileData[y][x] = tileId
        end
    end
    
    mapData.getTile = function(self, x, y)
        if x >= 1 and x <= self.width and y >= 1 and y <= self.height then
            return self.tileData[y][x]
        end
        return 0
    end
    return mapData
end

-- Enhanced map creation with layers and chunks
function map.createAdvancedMap(config, api)
    local advancedMap = {
        tilesets = config.tilesets or {},
        width = config.width,
        height = config.height,
        tileWidth = config.tileWidth,
        tileHeight = config.tileHeight,
        layers = {},
        chunks = {},
        camera = config.camera,
    }

    for i, layerConfig in ipairs(config.layers or {{name = "default"}}) do
        advancedMap.layers[i] = {
            name = layerConfig.name,
            visible = layerConfig.visible ~= false,
            opacity = layerConfig.opacity or 1.0,
            tilesetIndex = layerConfig.tilesetIndex or 1,
            data = {},
        }
    end

    advancedMap.setTile = function(self, x, y, tileId, layer)
        layer = layer or 1
        local cx, cy = worldToChunk(x * self.tileWidth, y * self.tileHeight, self.tileWidth)
        local chunkKey = getChunkKey(cx, cy)

        if not self.chunks[chunkKey] then
            self.chunks[chunkKey] = createChunk(cx, cy)
        end

        local chunk = self.chunks[chunkKey]
        local localX = ((x - 1) % MAP_CONFIG.CHUNK_SIZE) + 1
        local localY = ((y - 1) % MAP_CONFIG.CHUNK_SIZE) + 1

        chunk.tiles[localY][localX][layer] = tileId
        chunk.dirty = true
    end

    advancedMap.getTile = function(self, x, y, layer)
        layer = layer or 1
        local cx, cy = worldToChunk(x * self.tileWidth, y * self.tileHeight, self.tileWidth)
        local chunkKey = getChunkKey(cx, cy)

        local chunk = self.chunks[chunkKey]
        if not chunk then return 0 end

        local localX = ((x - 1) % MAP_CONFIG.CHUNK_SIZE) + 1
        local localY = ((y - 1) % MAP_CONFIG.CHUNK_SIZE) + 1

        return chunk.tiles[localY][localX][layer] or 0
    end

    return advancedMap
end

-- Enhanced object system with components using mod API
function map.createDynamicObject(config, api)
    local obj = {
        id = config.id or (#map.dynamicObjects + 1),
        type = config.type,
        x = config.x,
        y = config.y,
        width = config.width or 32,
        height = config.height or 32,
        components = {},
        active = true,

        sprite = config.sprite,
        scale = config.scale or 1,
        rotation = config.rotation or 0,
        color = config.color or {1, 1, 1, 1},

        body = nil,
        fixtures = {},

        tags = config.tags or {},
        userData = config.userData or {},
    }

    obj.addComponent = function(self, name, component)
        self.components[name] = component
        if component.init then
            component:init(self)
        end
    end

    obj.getComponent = function(self, name)
        return self.components[name]
    end

    obj.update = function(self, dt)
        for name, component in pairs(self.components) do
            if component.update then
                component:update(self, dt)
            end
        end
    end

    obj.move = function(self, new_x, new_y)
        local dx = new_x - self.x
        local dy = new_y - self.y

        self.x = new_x
        self.y = new_y

        if self.body and not self.body:isDestroyed() then
            self.body:setPosition(new_x, new_y)
        end

        for name, component in pairs(self.components) do
            if component.onMove then
                component:onMove(self, dx, dy)
            end
        end
    end

    obj.destroy = function(self)
        self.active = false

        if self.body and not self.body:isDestroyed() then
            self.body:destroy()
        end

        for name, component in pairs(self.components) do
            if component.destroy then
                component:destroy(self)
            end
        end
    end

    if config.physics and api then
        local world = api.physics.getWorld()
        if world then
            obj.body = api.physics.createBody(config.x, config.y, config.physics.type or "static")

            if config.physics.shape then
                local fixture = api.physics.createFixture(obj.body, config.physics.shape, config.physics.group_index)
                fixture:setUserData({
                    type = config.type,
                    id = obj.id,
                    object = obj,
                })
                table.insert(obj.fixtures, fixture)
            end
        end
    end

    table.insert(map.dynamicObjects, obj)
    return obj
end

-- Improved arch creation using the new system
function map.createArches(pivot_x, pivot_y, api)
    local arch = map.createDynamicObject({
        type = "arch",
        x = pivot_x,
        y = pivot_y,
        width = 98,
        height = 128,
        physics = {
            type = "static",
        },
    }, api)

    arch:addComponent("collision", {
        init = function(self, owner)
            local world = api.physics.getWorld()
            if world and owner.body then
                local left_shape = api.physics.createRectangleShape(6, 6)
                local right_shape = api.physics.createRectangleShape(6, 6)

                -- Manually position shapes since mod API may not support offset fixtures
                local left_fixture = api.physics.createFixture(owner.body, left_shape, -101)
                local right_fixture = api.physics.createFixture(owner.body, right_shape, -101)

                left_fixture:setUserData({type = "arch", id = owner.id, side = "left", object = owner})
                right_fixture:setUserData({type = "arch", id = owner.id, side = "right", object = owner})

                table.insert(owner.fixtures, left_fixture)
                table.insert(owner.fixtures, right_fixture)
            end
        end,
    })

    arch:addComponent("visual", {
        offset_x = -49,
        offset_y = -64,
        tilesetIndex = 3,
        tileId = 10,
    })

    arch.pivot_x = pivot_x
    arch.pivot_y = pivot_y
    arch.visual_offset_x = -49
    arch.visual_offset_y = -64

    arch.left_body = arch.body
    arch.right_body = arch.body
    
    local originalMove = arch.move
    arch.move = function(self, new_pivot_x, new_pivot_y)
        self.pivot_x = new_pivot_x
        self.pivot_y = new_pivot_y
        originalMove(self, new_pivot_x, new_pivot_y)
    end

    table.insert(map.archInstances, arch)
    return arch
end

-- Improved tree creation
function map.createTree(x, y, api)
    local tree = map.createDynamicObject({
        type = "tree",
        x = x + 20,
        y = y,
        width = 156,
        height = 156,
        physics = {
            type = "static",
            shape = api.physics.createCircleShape(3),
        },
    }, api)

    tree:addComponent("visual", {
        offset_x = -78,
        offset_y = -78,
        tilesetIndex = 4,
        tileId = 1,
        scale = 0.8,
    })

    tree:addComponent("shadow", {
        init = function(self, owner)
            self.radius = 30
            self.opacity = 0.3
        end,
        getDynamicDrawItem = function(self, owner)
            return {
                sort_y = owner.y - 1,
                draw_type = "circle",
                x = owner.x,
                y = owner.y + 40,
                radius = self.radius,
                color = {0, 0, 0, self.opacity},
                blend_mode = {"alpha"},
                source_object_type = "tree_shadow",
            }
        end,
    })

    local originalMove = tree.move
    tree.move = function(self, new_x, new_y)
        self.x = new_x
        self.y = new_y
        originalMove(self, new_x + 78, new_y + 78)
    end

    table.insert(map.treeInstances, tree)
    return tree
end

-- Find arch by any of its fixture
function map.findArchByFixture(fixture)
    local userData = fixture:getUserData()
    if userData and userData.type == "arch" then
        for _, arch in ipairs(map.archInstances) do
            if arch.id == userData.id then
                return arch
            end
        end
    end
    return nil
end

-- Find tree by fixture
function map.findTreeByFixture(fixture)
    local userData = fixture:getUserData()
    if userData and userData.type == "tree" then
        for _, tree in ipairs(map.treeInstances) do
            if tree.id == userData.id then
                return tree
            end
        end
    end
    return nil
end

-- Load map assets and initialize
function map.load(api)
    -- Load grass tileset using API
    local tilesetImage = api.utils.loadTexture("tileset_grass", "../gfx/TileSet/TX Tileset Grass.png")
    if not tilesetImage then
        -- Fallback: try to get from preloaded textures
        tilesetImage = api.renderer.getTexture("tileset_grass")
    end
    if tilesetImage then
        map.tiles = newTiles(tilesetImage, mod_config.tile_w, mod_config.tile_h, api)
        map.map = createMap(map.tiles, mod_config.map_display_w, mod_config.map_display_h)
        
        for x = 1, 70 do 
            for y = 1, 50 do
                map.map:setTile(x, y, math.random(1,200))
            end
        end
    end

    -- Load arch tileset using API
    local tilesetImage3 = api.utils.loadTexture("tileset_struct", "../gfx/TileSet/TX Struct.png")
    if not tilesetImage3 then
        tilesetImage3 = api.renderer.getTexture("tileset_struct")
    end
    if tilesetImage3 then
        map.tiles3 = newTiles(tilesetImage3, 98, 128, api)
        map.arches = createMap(map.tiles3, 1, 1)
        map.arches:setTile(1, 1, 10)
    end

    -- Load tree tileset using API
    local tilesetImage4 = api.utils.loadTexture("tileset_plant", "../gfx/TileSet/TX Plant.png")
    if not tilesetImage4 then
        tilesetImage4 = api.renderer.getTexture("tileset_plant")
    end
    if tilesetImage4 then
        map.tiles4 = newTiles(tilesetImage4, 156, 156, api)
        map.tree = createMap(map.tiles4, 1, 1)
        map.tree:setTile(1, 1, 1)
    end
end

-- Optimized dynamic draw list generation for the new renderer
function map.addMapToDynamicDrawList(mapData, map_x, map_y, map_scale, base_sort_y, api)
    local drawItems = {}
    performance.objectsRendered = 0
    map_x = map_x or 0
    map_y = map_y or 0
    map_scale = map_scale or 1

    if mapData == map.arches then
        for _, arch in ipairs(map.archInstances) do
            if arch.active then
                local visual = arch:getComponent("visual")
                if visual then
                    local visual_x = arch.pivot_x + visual.offset_x
                    local visual_y = arch.pivot_y + visual.offset_y

                    api.renderer.addToQueue("world", {
                        type = "sprite",
                        texture = map.tiles3.tilesetImage,
                        quad = map.tiles3.quads[visual.tileId],
                        x = visual_x,
                        y = visual_y,
                        rotation = arch.rotation,
                        scale_x = map_scale * arch.scale,
                        scale_y = map_scale * arch.scale,
                        sort_y = base_sort_y + visual_y,
                        active = true,
                        color = arch.color,
                        blend_mode = {"alpha"},
                    })
                    performance.objectsRendered = performance.objectsRendered + 1
                end
            end
        end
    elseif mapData == map.tree then
        for _, tree in ipairs(map.treeInstances) do
            if tree.active then
                local visual = tree:getComponent("visual")
                if visual then
                    local shadow = tree:getComponent("shadow")
                    if shadow and shadow.getDynamicDrawItem then
                        local shadowItem = shadow:getDynamicDrawItem(tree)
                        api.renderer.addToQueue("world", {
                            type = "circle",
                            mode = "fill",
                            x = shadowItem.x,
                            y = shadowItem.y,
                            radius = shadowItem.radius,
                            sort_y = shadowItem.sort_y,
                            active = true,
                            color = shadowItem.color,
                            blend_mode = shadowItem.blend_mode,
                        })
                    end

                    api.renderer.addToQueue("world", {
                        type = "sprite",
                        texture = map.tiles4.tilesetImage,
                        quad = map.tiles4.quads[visual.tileId],
                        x = tree.x + visual.offset_x,
                        y = tree.y + visual.offset_y,
                        rotation = tree.rotation,
                        scale_x = map_scale * visual.scale * tree.scale,
                        scale_y = map_scale * visual.scale * tree.scale,
                        sort_y = base_sort_y + tree.y - 100,
                        active = true,
                        color = tree.color,
                        blend_mode = {"alpha"},
                    })
                    performance.objectsRendered = performance.objectsRendered + 1
                end
            end
        end
    elseif mapData.draw then
        local max_tiles_x = math.ceil(mod_config.game_width / (mapData.tiles.tileWidth * map_scale))
        local max_tiles_y = math.ceil(mod_config.game_height / (mapData.tiles.tileHeight * map_scale))

        for row = 1, max_tiles_y do
            for col = 1, max_tiles_x do
                local tileId = mapData.tileData[row] and mapData.tileData[row][col]
                if tileId and tileId > 0 and mapData.tiles.quads[tileId] then
                    local tile_x = map_x + (col - 1) * mapData.tiles.tileWidth * map_scale
                    local tile_y = map_y + (row - 1) * mapData.tiles.tileHeight * map_scale

                    api.renderer.addToQueue("background", {
                        type = "sprite",
                        texture = mapData.tiles.tilesetImage,
                        quad = mapData.tiles.quads[tileId],
                        x = tile_x,
                        y = tile_y,
                        rotation = 0,
                        scale_x = map_scale,
                        scale_y = map_scale,
                        sort_y = base_sort_y + tile_y,
                        active = true,
                        color = {1, 1, 1, 1},
                        blend_mode = {"alpha"},
                    })
                end
            end
        end
    end

    return drawItems
end

-- Create serializable map data for saving
function map.createSaveData()
    local map_data = {}
    
    if map.map and map.map.tileData then
        map_data.base_tiles = {
            width = map.map.width,
            height = map.map.height,
            tile_data = {}
        }
        
        for y = 1, map.map.height do
            map_data.base_tiles.tile_data[y] = {}
            for x = 1, map.map.width do
                map_data.base_tiles.tile_data[y][x] = map.map.tileData[y] and map.map.tileData[y][x] or 0
            end
        end
    end
    
    map_data.arches = {}
    for i, arch in ipairs(map.archInstances) do
        map_data.arches[i] = {
            pivot_x = arch.pivot_x,
            pivot_y = arch.pivot_y,
            id = arch.id,
            visual_offset_x = arch.visual_offset_x,
            visual_offset_y = arch.visual_offset_y
        }
    end
    
    map_data.trees = {}
    for i, tree in ipairs(map.treeInstances) do
        map_data.trees[i] = {
            x = tree.x,
            y = tree.y,
            id = tree.id
        }
    end
    
    return map_data
end

function map.createSaveDataSmall()
    local map_data = {}
    
    map_data.arches = {}
    for i, arch in ipairs(map.archInstances) do
        map_data.arches[i] = {
            pivot_x = arch.pivot_x,
            pivot_y = arch.pivot_y,
            id = arch.id,
            visual_offset_x = arch.visual_offset_x,
            visual_offset_y = arch.visual_offset_y
        }
    end
    
    map_data.trees = {}
    for i, tree in ipairs(map.treeInstances) do
        map_data.trees[i] = {
            x = tree.x,
            y = tree.y,
            id = tree.id
        }
    end
    
    return map_data
end

-- Restore map from save data
function map.restore(map_data, api)
    if not map_data then
        return true
    end
    
    if map_data.base_tiles and map.map then
        if map.map.width ~= map_data.base_tiles.width or map.map.height ~= map_data.base_tiles.height then
            map.map.width = map_data.base_tiles.width
            map.map.height = map_data.base_tiles.height
            map.map.tileData = {}
        end
        
        for y = 1, map_data.base_tiles.height do
            map.map.tileData[y] = {}
            for x = 1, map_data.base_tiles.width do
                map.map.tileData[y][x] = map_data.base_tiles.tile_data[y] and map_data.base_tiles.tile_data[y][x] or 0
            end
        end
    end
    
    for _, arch in ipairs(map.archInstances) do
        arch:destroy()
    end
    map.archInstances = {}
    
    if map_data.arches then
        for _, arch_data in ipairs(map_data.arches) do
            local new_arch = map.createArches(arch_data.pivot_x, arch_data.pivot_y, api)
            
            if arch_data.visual_offset_x then
                new_arch.visual_offset_x = arch_data.visual_offset_x
            end
            if arch_data.visual_offset_y then
                new_arch.visual_offset_y = arch_data.visual_offset_y
            end
        end
    end
    
    for _, tree in ipairs(map.treeInstances) do
        tree:destroy()
    end
    map.treeInstances = {}
    
    if map_data.trees then
        for _, tree_data in ipairs(map_data.trees) do
            map.createTree(tree_data.x, tree_data.y, api)
        end
    end
    
    return true
end

-- Clear all dynamic map objects
function map.clearDynamicObjects()
    for _, arch in ipairs(map.archInstances) do
        arch:destroy()
    end
    map.archInstances = {}

    for _, tree in ipairs(map.treeInstances) do
        tree:destroy()
    end
    map.treeInstances = {}

    for _, obj in ipairs(map.dynamicObjects) do
        obj:destroy()
    end
    map.dynamicObjects = {}
end

-- Get summary of current map state
function map.getSummary()
    return {
        arch_count = #map.archInstances,
        tree_count = #map.treeInstances,
        dynamic_object_count = #map.dynamicObjects,
        map_width = map.map and map.map.width or 0,
        map_height = map.map and map.map.height or 0,
        has_tiles = map.map and map.map.tileData ~= nil,
        chunks_loaded = map.chunks and #map.chunks or 0,
        performance_stats = {
            chunks_rendered = performance.chunksRendered,
            tiles_rendered = performance.tilesRendered,
            objects_rendered = performance.objectsRendered,
        }
    }
end

-- Performance monitoring functions
function map.getPerformanceStats()
    return performance
end

function map.resetPerformanceStats()
    performance.chunksRendered = 0
    performance.tilesRendered = 0
    performance.objectsRendered = 0
end

-- Initialize the mod
function mapSystemMod.init(api)
    print("Initializing Map System Mod v1.0.0")
    
    -- Store API reference
    mapSystemMod.api = api
    
    -- Load configuration from var system (fallback values)
    mod_config = {
        tile_w = 16,
        tile_h = 16,
        map_display_w = 256,
        map_display_h = 256,
        game_width = 400,
        game_height = 400,
        chunk_size = 16,
        visible_chunks_radius = 3,
        max_pool_size = 100,
        enable_dynamic_objects = true,
        enable_performance_monitoring = true,
        enable_networking = true,
    }
    
    -- Initialize object pools
    initPool("drawItems", 
        function() return {} end,
        function(item) 
            for k in pairs(item) do 
                item[k] = nil 
            end 
        end
    )

    initPool("chunks",
        function() return createChunk(0, 0) end,
        function(chunk) 
            chunk.dirty = true
            chunk.lastAccess = api.utils.getTime()
            for y = 1, MAP_CONFIG.CHUNK_SIZE do
                for x = 1, MAP_CONFIG.CHUNK_SIZE do
                    chunk.tiles[y][x] = {}
                end
            end
            chunk.objects = {}
        end
    )
    
    -- Load map assets
    map.load(api)
    
    -- Register input handlers for testing
    api.input.registerKeyHandler("p", function()
        local player_x, player_y = api.game.getPlayerPosition()
        map.createArches(player_x + 50, player_y, api)
        print("[MAP_SYSTEM] Spawned arch at player location")
    end)
    
    api.input.registerKeyHandler("o", function()
        local player_x, player_y = api.game.getPlayerPosition()
        map.createTree(player_x + 50, player_y, api)
        print("[MAP_SYSTEM] Spawned tree at player location")
    end)
    
    -- Register network handler if enabled
    if mod_config.enable_networking then
        api.network.registerMessageHandler("map_system", mapSystemMod.handleNetworkMessage)
    end
    
    print("[MAP_SYSTEM] Initialization complete! Press 'P' for arch, 'O' for tree")
    
    -- Export functions to global namespace for compatibility
    _G.map = map
end

-- Update map system
function mapSystemMod.update(dt)
    local api = mapSystemMod.api
    
    -- Update dynamic objects
    for i = #map.dynamicObjects, 1, -1 do
        local obj = map.dynamicObjects[i]
        if obj.active then
            obj:update(dt)
        else
            table.remove(map.dynamicObjects, i)
        end
    end
    
    -- Add map tiles to render queue
    if map.map then
        map.addMapToDynamicDrawList(map.map, 0, 0, 1, 0, api)
    end
    
    -- Add arches to render queue
    if map.arches then
        map.addMapToDynamicDrawList(map.arches, 0, 0, 1, 200, api)
    end
    
    -- Add trees to render queue
    if map.tree then
        map.addMapToDynamicDrawList(map.tree, 0, 0, 0.8, 240, api)
    end
end

-- Handle network messages
function mapSystemMod.handleNetworkMessage(data)
    local api = mapSystemMod.api
    
    if data.action == "spawn_arch" then
        map.createArches(data.x, data.y, api)
    elseif data.action == "spawn_tree" then
        map.createTree(data.x, data.y, api)
    elseif data.action == "sync_map_data" then
        map.restore(data.map_data, api)
    end
end

-- Get mod statistics
function mapSystemMod.getStats()
    return map.getSummary()
end

-- Cleanup
function mapSystemMod.cleanup()
    map.clearDynamicObjects()
    print("[MAP_SYSTEM] Cleanup complete")
end

-- Export main functions for external access
mapSystemMod.map = map
mapSystemMod.createArches = function(x, y) return map.createArches(x, y, mapSystemMod.api) end
mapSystemMod.createTree = function(x, y) return map.createTree(x, y, mapSystemMod.api) end
mapSystemMod.findArchByFixture = map.findArchByFixture
mapSystemMod.findTreeByFixture = map.findTreeByFixture
mapSystemMod.createSaveData = map.createSaveData
mapSystemMod.createSaveDataSmall = map.createSaveDataSmall
mapSystemMod.restore = function(data) return map.restore(data, mapSystemMod.api) end
mapSystemMod.addMapToDynamicDrawList = function(...) return map.addMapToDynamicDrawList(..., mapSystemMod.api) end

return mapSystemMod