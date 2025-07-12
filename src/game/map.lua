local map = {}

-- Configuration
local MAP_CONFIG = {
    -- Chunk system for performance
    CHUNK_SIZE = 16,           -- tiles per chunk
    VISIBLE_CHUNKS_RADIUS = 3, -- chunks to render around camera

    -- Object pooling
    MAX_POOL_SIZE = 100,

    -- Layers
    LAYER_GROUND = 1,
    LAYER_DECORATION = 2,
    LAYER_COLLISION = 3,
    LAYER_OVERLAY = 4,

    -- Z-sorting offsets
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
map.houseInstances = {}
map.dynamicObjects = {} -- Generic dynamic objects
map.chunks = {}         -- Spatial chunks for optimization
map.layers = {}         -- Multiple map layers

-- Performance monitoring
local performance = {
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
        lastAccess = love.timer.getTime(),
    }

    for y = 1, MAP_CONFIG.CHUNK_SIZE do
        chunk.tiles[y] = {}
        for x = 1, MAP_CONFIG.CHUNK_SIZE do
            chunk.tiles[y][x] = {}
        end
    end

    return chunk
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
            tileset.quads[tileId] = love.graphics.newQuad(
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

function createMap(tiles, mapWidth, mapHeight, tileData)
    local map = {}
    map.tiles = tiles
    map.width = mapWidth
    map.height = mapHeight
    map.tileData = tileData or {}

    if not tileData then
        for y = 1, mapHeight do
            map.tileData[y] = {}
            for x = 1, mapWidth do
                map.tileData[y][x] = 0
            end
        end
    end

    map.draw = function(self, x, y, scale)
        scale = scale or 1
        local max_tiles_x = math.ceil(var.game_width / (self.tiles.tileWidth * scale)) + 200
        local max_tiles_y = math.ceil(var.game_height / (self.tiles.tileHeight * scale)) + 200
        
        -- Initialize spriteBatch if not already created
        if not self.spriteBatch then
            self.spriteBatch = love.graphics.newSpriteBatch(self.tiles.tilesetImage, max_tiles_x * max_tiles_y)
            self.dirty = true
        end
        
        -- Rebuild spriteBatch only if map data has changed
        if self.dirty then
            self.spriteBatch:clear()
            for row = 1, max_tiles_y do
                for col = 1, max_tiles_x do
                    local tileId = self.tileData[row] and self.tileData[row][col]
                    if tileId and tileId > 0 and self.tiles.quads[tileId] then
                        self.spriteBatch:add(
                            self.tiles.quads[tileId],
                            x + (col - 1) * self.tiles.tileWidth * scale,
                            y + (row - 1) * self.tiles.tileHeight * scale,
                            0,
                            scale,
                            scale,
                            -9800,
                            y + 2000
                        )
                    end
                end
            end
            self.dirty = false
        end
        
        -- Draw the existing spriteBatch
        love.graphics.draw(self.spriteBatch)
    end

    map.setTile = function(self, x, y, tileId)
        if x >= 1 and x <= self.width and y >= 1 and y <= self.height then
            self.tileData[y][x] = tileId
            self.dirty = true -- Mark map as dirty to rebuild spriteBatch on next draw
        end
    end

    map.getTile = function(self, x, y)
        if x >= 1 and x <= self.width and y >= 1 and y <= self.height then
            return self.tileData[y][x]
        end
        return 0
    end
    return map
end

-- Enhanced map creation with layers and chunks
function map.createAdvancedMap(config)
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

    for i, layerConfig in ipairs(config.layers or { { name = "default" } }) do
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

    advancedMap.draw = function(self, camera_x, camera_y, scale, screen_width, screen_height)
        performance.chunksRendered = 0
        performance.tilesRendered = 0

        local startChunkX, startChunkY = worldToChunk(camera_x, camera_y, self.tileWidth * scale)
        local endChunkX, endChunkY = worldToChunk(
            camera_x + screen_width,
            camera_y + screen_height,
            self.tileWidth * scale
        )

        for cy = startChunkY - 1, endChunkY + 1 do
            for cx = startChunkX - 1, endChunkX + 1 do
                local chunkKey = getChunkKey(cx, cy)
                local chunk = self.chunks[chunkKey]

                if chunk then
                    performance.chunksRendered = performance.chunksRendered + 1
                    self:drawChunk(chunk, camera_x, camera_y, scale)
                end
            end
        end
    end

    advancedMap.drawChunk = function(self, chunk, camera_x, camera_y, scale)
        local baseX = chunk.x * MAP_CONFIG.CHUNK_SIZE * self.tileWidth * scale
        local baseY = chunk.y * MAP_CONFIG.CHUNK_SIZE * self.tileHeight * scale

        for layerIndex, layer in ipairs(self.layers) do
            if layer.visible then
                local tileset = self.tilesets[layer.tilesetIndex]
                if tileset then
                    love.graphics.setColor(1, 1, 1, layer.opacity)

                    for y = 1, MAP_CONFIG.CHUNK_SIZE do
                        for x = 1, MAP_CONFIG.CHUNK_SIZE do
                            local tileId = chunk.tiles[y][x][layerIndex]
                            if tileId and tileId > 0 and tileset.quads[tileId] then
                                performance.tilesRendered = performance.tilesRendered + 1

                                love.graphics.draw(
                                    tileset.image,
                                    tileset.quads[tileId],
                                    baseX + (x - 1) * self.tileWidth * scale - camera_x,
                                    baseY + (y - 1) * self.tileHeight * scale - camera_y,
                                    0,
                                    scale,
                                    scale
                                )
                            end
                        end
                    end

                    love.graphics.setColor(1, 1, 1, 1)
                end
            end
        end
    end

    return advancedMap
end

-- function map.collision(fixture_a, fixture_b, contact)
--     local not_map
--     if (fixture_a:getGroupIndex() == 4) then
--         not_map = fixture_b
--     elseif fixture_b:getGroupIndex() == 4 then
--         not_map = fixture_a
--     end
--     if not_map then
--         -- print("friction", contact:getFriction())
--         -- print("normal", contact:getNormal())
--         local nx, ny = contact:getNormal()
--         -- print(norm)
--         local hit   = vec2.new(nx, ny)
--         hit         = 200 * hit
--         -- print(hit)
--         not_map:getBody():applyLinearImpulse(hit.x, hit.y)

--         if not_map:getGroupIndex() == -1 then
--             var.indoors = not var.indoors
--         end


--         -- if hit == vec2.new(0,0) then
--         --     not_map:getBody():applyLinearImpulse(math.random(-200,200),math.random(-200,200))
--         -- end
--     end

--     --  or (fixture_a:getGroupIndex() == -1 and fixture_b:getGroupIndex() == 4)
-- end

-- Enhanced object system with components
function map.createDynamicObject(config)
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
        color = config.color or { 1, 1, 1, 1 },

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

    if config.physics and world then
        obj.body = love.physics.newBody(world, config.x, config.y, config.physics.type or "static")

        if config.physics.shape then
            local fixture = love.physics.newFixture(obj.body, config.physics.shape)

            fixture:setUserData({
                type = config.type,
                id = obj.id,
                object = obj,
            })

            table.insert(obj.fixtures, fixture)
        end
    end

    table.insert(map.dynamicObjects, obj)
    return obj
end

-- Improved arch creation using the new system
function map.createArches(pivot_x, pivot_y)
    local arch = map.createDynamicObject({
        type = "arch",
        x = pivot_x,
        y = pivot_y,
        width = 98,
        height = 128,
        physics = {
            type = "static",
        },
    })

    arch:addComponent("collision", {
        init = function(self, owner)
            local left_shape = love.physics.newRectangleShape(-24, 0, 6, 6)
            local right_shape = love.physics.newRectangleShape(24, 0, 6, 6)

            local left_fixture = love.physics.newFixture(owner.body, left_shape)
            local right_fixture = love.physics.newFixture(owner.body, right_shape)

            left_fixture:setUserData({ type = "arch", id = owner.id, side = "left", object = owner })
            right_fixture:setUserData({ type = "arch", id = owner.id, side = "right", object = owner })

            table.insert(owner.fixtures, left_fixture)
            table.insert(owner.fixtures, right_fixture)
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
function map.createTree(x, y)
    local tree = map.createDynamicObject({
        type = "tree",
        x = x + 20,
        y = y,
        width = 156,
        height = 156,
        physics = {
            type = "static",
            shape = love.physics.newCircleShape(-27, 15, 3),
        },
    })

    tree:addComponent("visual", {
        offset_x = -78,
        offset_y = -78,
        tilesetIndex = 4,
        tileId = 1,
        scale = 0.8,
    })

    -- tree:addComponent("collision", {
    --     init = function(self, owner)



    --         local left_fixture = love.physics.newFixture(owner.body,love.physics.newCircleShape(20))


    --         left_fixture:setUserData({type = "arch", id = owner.id, side = "left", object = owner})


    --         table.insert(owner.fixtures, left_fixture)
    --     end,
    -- })

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
                color = { 0, 0, 0, self.opacity },
                blend_mode = { "alpha" },
                source_object_type = "tree_shadow",
            }
        end,
    })

    -- tree.x = x
    -- tree.y = y

    local originalMove = tree.move
    tree.move = function(self, new_x, new_y)
        self.x = new_x
        self.y = new_y
        originalMove(self, new_x + 78, new_y + 78)
    end

    table.insert(map.treeInstances, tree)
    return tree
end

-- House creation
function map.createHouse(x, y)
    local house = map.createDynamicObject({
        type = "house",
        x = x,
        y = y,
        width = 0,
        height = 0,
        physics = {
            -- type = "static",
            -- shape = love.physics.newRectangleShape(0, 0, 0, 0),
        },
    })

    house:addComponent("visual", {
        offset_x = -70,
        offset_y = -130,
        tilesetIndex = 5,
        tileId = 1,
        scale = 2.0,
    })
    house:addComponent("collision", {
        -- Configurable parameters
        width = 128,    -- Total house width
        height = 128,   -- Total house height
        wall_thickness = 6, -- Wall thickness
        door_gap = 30,  -- Width of door opening
        trigger_size = 100, -- Size of the trigger area for AABB check

        init = function(self, owner)
            local half_width = self.width / 2
            local half_height = self.height / 2
            local half_door_gap = self.door_gap / 2

            -- Left wall
            local left_shape = love.physics.newRectangleShape(-half_width, 0, self.wall_thickness, self.height)
            local left_fixture = love.physics.newFixture(owner.body, left_shape)
            left_fixture:setUserData({ type = "house", id = owner.id, side = "left", object = owner })
            table.insert(owner.fixtures, left_fixture)

            -- Right wall
            local right_shape = love.physics.newRectangleShape(half_width, 0, self.wall_thickness, self.height)
            local right_fixture = love.physics.newFixture(owner.body, right_shape)
            right_fixture:setUserData({ type = "house", id = owner.id, side = "right", object = owner })
            table.insert(owner.fixtures, right_fixture)

            -- Back wall
            local back_shape = love.physics.newRectangleShape(0, -half_height, self.width, self.wall_thickness)
            local back_fixture = love.physics.newFixture(owner.body, back_shape)
            back_fixture:setUserData({ type = "house", id = owner.id, side = "back", object = owner })
            table.insert(owner.fixtures, back_fixture)

            -- Front walls (with door opening in the middle)
            local front_wall_width = (self.width - self.door_gap) / 2
            local front_wall_offset = half_door_gap + front_wall_width / 2

            -- Left side of front wall
            local front_left_shape = love.physics.newRectangleShape(-front_wall_offset, half_height, front_wall_width,
                self.wall_thickness)
            local front_left_fixture = love.physics.newFixture(owner.body, front_left_shape)
            front_left_fixture:setUserData({ type = "house", id = owner.id, side = "front_left", object = owner })
            table.insert(owner.fixtures, front_left_fixture)

            -- Right side of front wall
            local front_right_shape = love.physics.newRectangleShape(front_wall_offset, half_height, front_wall_width,
                self.wall_thickness)
            local front_right_fixture = love.physics.newFixture(owner.body, front_right_shape)
            front_right_fixture:setUserData({ type = "house", id = owner.id, side = "front_right", object = owner })
            table.insert(owner.fixtures, front_right_fixture)
            
            -- Set collision group for wall fixtures
            for _, _fixture in pairs(owner.fixtures) do
                _fixture:setGroupIndex(4)
            end
        end,
    })
    
    house:addComponent("proximityCheck", {
        trigger_size = 128, -- Size of the AABB area for indoors check
        
        init = function(self, owner)
            self.half_size = self.trigger_size / 2
        end,
        
        update = function(self, owner, dt)
            if player and player.body then
                local px, py = player.body:getPosition()
                local hx, hy = owner.body:getPosition()
                
                -- AABB check for player position within house trigger area
                if px > hx - self.half_size and px < hx + self.half_size and
                   py > hy - self.half_size and py < hy + self.half_size then
                    var.indoors = true
                else
                    var.indoors = false
                end
            end
        end,
    })

    -- house:addComponent("shadow", {
    --     init = function(self, owner)
    --         self.radius = 40
    --         self.opacity = 0.4
    --     end,
    --     getDynamicDrawItem = function(self, owner)
    --         return {
    --             sort_y = owner.y - 1,
    --             draw_type = "circle",
    --             x = owner.x,
    --             y = owner.y + 30,
    --             radius = self.radius,
    --             color = {0, 0, 0, self.opacity},
    --             blend_mode = {"alpha"},
    --             source_object_type = "house_shadow",
    --         }
    --     end,
    -- })

    house.x = x
    house.y = y

    local originalMove = house.move
    house.move = function(self, new_x, new_y)
        self.x = new_x
        self.y = new_y
        originalMove(self, new_x, new_y)
    end

    table.insert(map.houseInstances, house)
    return house
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

-- Update all house instances to check for player proximity
function map.updateHouses(dt)
    for _, house in ipairs(map.houseInstances) do
        if house.active then
            house:update(dt)
        end
    end
end

function map.load()

    -- local tilesetImage = love.graphics.newImage("gfx/TileSet/TX Tileset Grass.png")
    -- map.tiles = newTiles(tilesetImage, var.tile_w, var.tile_h)
    -- map.map = createMap(map.tiles, var.map_display_w, var.map_display_h)
    


    -- for x = 1, 700 do
    --     for y = 1, 900 do
    --         map.map:setTile(x, y, math.random(1,200))
    --     end
    -- end

    

    local tilesetImage = love.graphics.newImage("gfx/TileSet/grounds.png")
    map.tiles = newTiles(tilesetImage, var.tile_w, var.tile_h)
    map.map = createMap(map.tiles, var.map_display_w, var.map_display_h)
    


    -- local tilesetImage =  love.graphics.newImage("gfx/TileSet/houseInterior.png")
    -- map.tiles = newTiles(tilesetImage, 16, 16)
    -- map.map = createMap(map.tiles, var.map_display_w, var.map_display_h)



    for x = 1, 200 do
        for y = 1, 200 do
            
            map.map:setTile(x, y, tileRules.getValidTile(x, y))
            -- end
        end
    end

    -- Load arch tileset
    local tilesetImage3 = love.graphics.newImage("gfx/TileSet/TX Struct.png")
    map.tiles3 = newTiles(tilesetImage3, 98, 128)
    map.arches = createMap(map.tiles3, 1, 1) -- Just for tileset storage
    map.arches:setTile(1, 1, 10)             -- Default arch tile

    -- Load tree tileset
    local tilesetImage4 = love.graphics.newImage("gfx/TileSet/TX Plant.png")
    map.tiles4 = newTiles(tilesetImage4, 156, 156)
    map.tree = createMap(map.tiles4, 1, 1) -- Just for tileset storage
    map.tree:setTile(1, 1, 1)              -- Default tree tile



    local tilesetImage5 = love.graphics.newImage("gfx/TileSet/house.png")
    map.tiles5 = newTiles(tilesetImage5, 100, 100)
    map.house = createMap(map.tiles5, var.map_display_w, var.map_display_h)
    for x = 1, 70 do
        for y = 1, 50 do
            map.house:setTile(x, y, math.random(1, 200))
        end
    end
end

-- Optimized dynamic draw list generation
function map.addMapToDynamicDrawList(mapData, map_x, map_y, map_scale, base_sort_y)
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

                    table.insert(drawItems, {
                        sort_y = base_sort_y + visual_y,
                        image_or_particles = map.tiles3.tilesetImage,
                        quad = map.tiles3.quads[visual.tileId],
                        x = visual_x,
                        y = visual_y,
                        rotation = arch.rotation,
                        scale_x = map_scale * arch.scale,
                        scale_y = map_scale * arch.scale,
                        offset_x = 0,
                        offset_y = 0,
                        color = arch.color,
                        blend_mode = { "alpha" },
                        source_object_type = "arch",
                        object_id = arch.id,
                    })
                    performance.objectsRendered = performance.objectsRendered + 1
                end
            end
        end
        -- elseif mapData == map.tree then
        --     for _, tree in ipairs(map.treeInstances) do
        --         if tree.active then
        --             local visual = tree:getComponent("visual")
        --             if visual then
        --                 local shadow = tree:getComponent("shadow")
        --                 if shadow and shadow.getDynamicDrawItem then
        --                     table.insert(drawItems, shadow:getDynamicDrawItem(tree))
        --                 end

        --                 table.insert(drawItems, {
        --                     sort_y = base_sort_y + tree.y,
        --                     image_or_particles = map.tiles4.tilesetImage,
        --                     quad = map.tiles4.quads[visual.tileId],
        --                     x = tree.x + visual.offset_x,
        --                     y = tree.y + visual.offset_y,
        --                     rotation = tree.rotation,
        --                     scale_x = map_scale * visual.scale * tree.scale,
        --                     scale_y = map_scale * visual.scale * tree.scale,
        --                     offset_x = 0,
        --                     offset_y = 0,
        --                     color = tree.color,
        --                     blend_mode = {"alpha"},
        --                     source_object_type = "tree",
        --                     object_id = tree.id,
        --                 })
        --                 performance.objectsRendered = performance.objectsRendered + 1
        --             end
        --         end
        --     end
    elseif mapData == map.tree then
        for _, tree in ipairs(map.treeInstances) do
            if tree.active then
                local visual = tree:getComponent("visual")
                if visual then
                    local shadow = tree:getComponent("shadow")
                    if shadow and shadow.getDynamicDrawItem then
                        table.insert(drawItems, shadow:getDynamicDrawItem(tree))
                    end

                    -- Create tree draw item with potential wind shader
                    local drawItem = {
                        sort_y = base_sort_y + tree.y - 100,
                        image_or_particles = map.tiles4.tilesetImage,
                        quad = map.tiles4.quads[visual.tileId],
                        x = tree.x + visual.offset_x,
                        y = tree.y + visual.offset_y,
                        rotation = tree.rotation,
                        scale_x = map_scale * visual.scale * tree.scale,
                        scale_y = map_scale * visual.scale * tree.scale,
                        offset_x = 0,
                        offset_y = 0,
                        color = tree.color,
                        blend_mode = { "alpha" },
                        source_object_type = "tree",
                        object_id = tree.id,
                    }
                    -- print(visual.usewind, wind.shader)

                    -- Add wind shader if enabled
                    -- if visual.usewind and wind.shader then
                    drawItem.shader = wind.shader
                    drawItem.shader_params = {
                        world_position = { tree.x, tree.y }
                    }
                    drawItem.source_object_type = "tree_with_wind"
                    -- end

                    table.insert(drawItems, drawItem)
                    -- performance.objectsRendered = performance.objectsRendered + 1
                end
            end
        end
    elseif mapData == map.house then
        for _, house in ipairs(map.houseInstances) do
            if house.active then
                local visual = house:getComponent("visual")
                if visual then
                    local shadow = house:getComponent("shadow")
                    if shadow and shadow.getDynamicDrawItem then
                        table.insert(drawItems, shadow:getDynamicDrawItem(house))
                    end
                    -- for key, value in pairs(house.color) do
                    --     print(key,value)
                    -- end

                    table.insert(drawItems, {
                        sort_y = base_sort_y + house.y + 100,
                        image_or_particles = map.tiles5.tilesetImage,
                        quad = map.tiles5.quads[visual.tileId],
                        x = house.x + visual.offset_x,
                        y = house.y + visual.offset_y,
                        rotation = house.rotation,
                        scale_x = map_scale * visual.scale * house.scale,
                        scale_y = map_scale * visual.scale * house.scale,
                        offset_x = 0,
                        offset_y = 0,
                        color = house.color,
                        blend_mode = { "alpha" },
                        source_object_type = "house",
                        object_id = house.id,
                    })
                    performance.objectsRendered = performance.objectsRendered + 1
                end
            end
        end
    elseif mapData.draw then
        local max_tiles_x = math.ceil(var.game_width / (mapData.tiles.tileWidth * map_scale))
        local max_tiles_y = math.ceil(var.game_height / (mapData.tiles.tileHeight * map_scale))

        for row = 1, max_tiles_y do
            for col = 1, max_tiles_x do
                local tileId = mapData.tileData[row] and mapData.tileData[row][col]
                if tileId and tileId > 0 and mapData.tiles.quads[tileId] then
                    local tile_x = map_x + (col - 1) * mapData.tiles.tileWidth * map_scale
                    local tile_y = map_y + (row - 1) * mapData.tiles.tileHeight * map_scale

                    table.insert(drawItems, {
                        sort_y = base_sort_y + tile_y,
                        image_or_particles = mapData.tiles.tilesetImage,
                        quad = mapData.tiles.quads[tileId],
                        x = tile_x,
                        y = tile_y,
                        rotation = 0,
                        scale_x = map_scale,
                        scale_y = map_scale,
                        offset_x = 0,
                        offset_y = 0,
                        color = { 1, 1, 1, 1 },
                        blend_mode = { "alpha" },
                        source_object_type = "map_tile",
                    })
                end
            end
        end
    end

    return drawItems
end

-- NEW: Serialization functions for save/load system

-- Create serializable map data for saving
function map.createSaveData()
    local map_data = {}

    -- Capture base tile map data
    if map.map and map.map.tileData then
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
    for i, arch in ipairs(map.archInstances) do
        map_data.arches[i] = {
            pivot_x = arch.pivot_x,
            pivot_y = arch.pivot_y,
            id = arch.id,
            visual_offset_x = arch.visual_offset_x,
            visual_offset_y = arch.visual_offset_y
        }
    end

    -- Capture tree instances
    map_data.trees = {}
    for i, tree in ipairs(map.treeInstances) do
        map_data.trees[i] = {
            x = tree.x,
            y = tree.y,
            id = tree.id
        }
    end

    -- Capture house instances
    map_data.houses = {}
    for i, house in ipairs(map.houseInstances) do
        map_data.houses[i] = {
            x = house.x,
            y = house.y,
            id = house.id
        }
    end

    return map_data
end

function map.createSaveDataSmall()
    local map_data = {}

    -- -- Capture base tile map data
    -- if map.map and map.map.tileData then
    --     map_data.base_tiles = {
    --         width = map.map.width,
    --         height = map.map.height,
    --         tile_data = {}
    --     }

    --     -- Deep copy tile data
    --     for y = 1, map.map.height do
    --         map_data.base_tiles.tile_data[y] = {}
    --         for x = 1, map.map.width do
    --             map_data.base_tiles.tile_data[y][x] = map.map.tileData[y] and map.map.tileData[y][x] or 0
    --         end
    --     end
    -- end

    -- Capture arch instances
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

    -- Capture tree instances
    map_data.trees = {}
    for i, tree in ipairs(map.treeInstances) do
        map_data.trees[i] = {
            x = tree.x,
            y = tree.y,
            id = tree.id
        }
    end

    -- Capture house instances
    map_data.houses = {}
    for i, house in ipairs(map.houseInstances) do
        map_data.houses[i] = {
            x = house.x,
            y = house.y,
            id = house.id
        }
    end

    return map_data
end

-- Restore map from save data
function map.restore(map_data)
    if not map_data then
        return true -- No map data to restore, but not an error
    end

    -- Restore base tile map
    if map_data.base_tiles and map.map then
        -- Ensure map dimensions match or resize if needed
        if map.map.width ~= map_data.base_tiles.width or map.map.height ~= map_data.base_tiles.height then
            map.map.width = map_data.base_tiles.width
            map.map.height = map_data.base_tiles.height
            map.map.tileData = {}
        end

        -- Restore tile data
        for y = 1, map_data.base_tiles.height do
            map.map.tileData[y] = {}
            for x = 1, map_data.base_tiles.width do
                map.map.tileData[y][x] = map_data.base_tiles.tile_data[y] and map_data.base_tiles.tile_data[y][x] or 0
            end
        end
    end

    -- Clear existing arches
    for _, arch in ipairs(map.archInstances) do
        arch:destroy()
    end
    map.archInstances = {}

    -- Restore arches
    if map_data.arches then
        for _, arch_data in ipairs(map_data.arches) do
            local new_arch = map.createArches(arch_data.pivot_x, arch_data.pivot_y)

            -- Restore any additional arch properties if needed
            if arch_data.visual_offset_x then
                new_arch.visual_offset_x = arch_data.visual_offset_x
            end
            if arch_data.visual_offset_y then
                new_arch.visual_offset_y = arch_data.visual_offset_y
            end
        end
        map_a = map.addMapToDynamicDrawList(map.arches, 0, 0, 1, 200) -- reload
    end

    -- Clear existing trees
    for _, tree in ipairs(map.treeInstances) do
        tree:destroy()
    end
    map.treeInstances = {}

    -- Restore trees
    if map_data.trees then
        for _, tree_data in ipairs(map_data.trees) do
            map.createTree(tree_data.x, tree_data.y)
        end
        map_b = map.addMapToDynamicDrawList(map.tree, 0, 0, 0.8, 240)
    end

    -- Restore houses
    if map_data.houses then
        for _, house_data in ipairs(map_data.houses) do
            map.createHouse(house_data.x, house_data.y)
        end
        map_c = map.addMapToDynamicDrawList(map.house, 0, 0, 0.8, 240)
    end

    return true
end

-- Clear all dynamic map objects (useful for resetting/loading)
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
        chunk.lastAccess = love.timer.getTime()
        for y = 1, MAP_CONFIG.CHUNK_SIZE do
            for x = 1, MAP_CONFIG.CHUNK_SIZE do
                chunk.tiles[y][x] = {}
            end
        end
        chunk.objects = {}
    end
)

return map
