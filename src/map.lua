local map = {}

-- Store arch instances for management
map.archInstances = {}
map.treeInstances = {}

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
        x = x or 0
        y = y or 0
        scale = scale or 1
        local max_tiles_x = math.ceil(var.game_width / (self.tiles.tileWidth * scale)) + 200
        local max_tiles_y = math.ceil(var.game_height / (self.tiles.tileHeight * scale))
        for row = 1, max_tiles_y do
            for col = 1, max_tiles_x do
                local tileId = self.tileData[row] and self.tileData[row][col]
                if tileId and tileId > 0 and self.tiles.quads[tileId] then
                    love.graphics.draw(
                        self.tiles.tilesetImage,
                        self.tiles.quads[tileId],
                        x + (col-1) * self.tiles.tileWidth * scale,
                        y + (row-1) * self.tiles.tileHeight * scale,
                        0,
                        scale,
                        scale
                    )
                end
            end
        end
    end
    
    map.setTile = function(self, x, y, tileId)
        if x >= 1 and x <= self.width and y >= 1 and y <= self.height then
            self.tileData[y][x] = tileId
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

-- Create arches at pivot position (your existing interface)
function map.createArches(pivot_x, pivot_y)
    local arch = {}
    arch.pivot_x = pivot_x
    arch.pivot_y = pivot_y
    arch.id = #map.archInstances + 1
    arch.bodies = {}
    arch.fixtures = {}
    
    -- Create two colliders for the arch (left and right pillars)
    local left_shape = love.physics.newRectangleShape(3, 3)
    local right_shape = love.physics.newRectangleShape(3, 3)
    
    arch.left_body = love.physics.newBody(world, pivot_x - 15, pivot_y, "static")
    arch.right_body = love.physics.newBody(world, pivot_x + 30, pivot_y, "static")
    
    arch.left_fixture = love.physics.newFixture(arch.left_body, left_shape)
    arch.right_fixture = love.physics.newFixture(arch.right_body, right_shape)
    
    -- Mark these as grouped so editor knows they move together
    arch.left_fixture:setUserData({type = "arch", id = arch.id, group = "arch_" .. arch.id, pivot_x = pivot_x, pivot_y = pivot_y})
    arch.right_fixture:setUserData({type = "arch", id = arch.id, group = "arch_" .. arch.id, pivot_x = pivot_x, pivot_y = pivot_y})
    
    table.insert(arch.bodies, arch.left_body)
    table.insert(arch.bodies, arch.right_body)
    table.insert(arch.fixtures, arch.left_fixture)
    table.insert(arch.fixtures, arch.right_fixture)
    
    -- Store visual offset for rendering
    arch.visual_offset_x = -49
    arch.visual_offset_y = -64
    
    -- Add move function
    arch.move = function(self, new_pivot_x, new_pivot_y)
        local delta_x = new_pivot_x - self.pivot_x
        local delta_y = new_pivot_y - self.pivot_y
        
        -- Move both bodies
        self.left_body:setPosition(new_pivot_x - 24, new_pivot_y)
        self.right_body:setPosition(new_pivot_x + 24, new_pivot_y)
        
        -- Update pivot
        self.pivot_x = new_pivot_x
        self.pivot_y = new_pivot_y
        
        -- Update user data
        self.left_fixture:setUserData({type = "arch", id = self.id, group = "arch_" .. self.id, pivot_x = new_pivot_x, pivot_y = new_pivot_y})
        self.right_fixture:setUserData({type = "arch", id = self.id, group = "arch_" .. self.id, pivot_x = new_pivot_x, pivot_y = new_pivot_y})
    end
    
    arch.destroy = function(self)
        for _, body in ipairs(self.bodies) do
            if not body:isDestroyed() then
                body:destroy()
            end
        end
        self.bodies = {}
        self.fixtures = {}
    end
    
    table.insert(map.archInstances, arch)
    return arch
end

-- Create tree at position with matching collider
function map.createTree(x, y)
    local tree = {}
    tree.x = x
    tree.y = y
    tree.id = #map.treeInstances + 1
    
    -- Create single collider for the tree (roughly matching the visual)
    local tree_shape = love.physics.newRectangleShape(5,5) -- Adjust size to match your tree visual
    tree.body = love.physics.newBody(world, x + 60, y + 120, "static") -- Offset to center on tree sprite
    tree.fixture = love.physics.newFixture(tree.body, tree_shape)
    
    tree.fixture:setUserData({type = "tree", id = tree.id, x = x, y = y})
    
    tree.move = function(self, new_x, new_y)
        self.body:setPosition(new_x + 78, new_y + 78)
        self.x = new_x
        self.y = new_y
        self.fixture:setUserData({type = "tree", id = self.id, x = new_x, y = new_y})
    end
    
    tree.destroy = function(self)
        if not self.body:isDestroyed() then
            self.body:destroy()
        end
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

function map.load()
    local tilesetImage = love.graphics.newImage("gfx/TileSet/TX Tileset Grass.png")
    map.tiles = newTiles(tilesetImage, var.tile_w, var.tile_h)
    map.map = createMap(map.tiles, var.map_display_w, var.map_display_h)
    
    for x = 1, 70 do 
        for y = 1, 50 do
            map.map:setTile(x, y, math.random(1,200))
        end
    end

    -- Load arch tileset
    local tilesetImage3 = love.graphics.newImage("gfx/TileSet/TX Struct.png")
    map.tiles3 = newTiles(tilesetImage3, 98, 128)
    map.arches = createMap(map.tiles3, 1, 1) -- Just for tileset storage
    map.arches:setTile(1, 1, 10) -- Default arch tile

    -- Load tree tileset
    local tilesetImage4 = love.graphics.newImage("gfx/TileSet/TX Plant.png")
    map.tiles4 = newTiles(tilesetImage4, 156, 156)
    map.tree = createMap(map.tiles4, 1, 1) -- Just for tileset storage
    map.tree:setTile(1, 1, 1) -- Default tree tile
end

function map.addMapToDynamicDrawList(mapData, map_x, map_y, map_scale, base_sort_y)
    map_x = map_x or 0
    map_y = map_y or 0
    map_scale = map_scale or 1

    local dynamic_draw_lists = {}
    
    -- Handle arch rendering
    if mapData == map.arches then
        for _, arch in ipairs(map.archInstances) do
            local visual_x = arch.pivot_x + arch.visual_offset_x
            local visual_y = arch.pivot_y + arch.visual_offset_y
            
            table.insert(dynamic_draw_lists, {
                sort_y = base_sort_y + visual_y,
                image_or_particles = map.tiles3.tilesetImage,
                quad = map.tiles3.quads[10],
                x = visual_x,
                y = visual_y,
                rotation = 0,
                scale_x = map_scale,
                scale_y = map_scale,
                offset_x = 0,
                offset_y = 0,
                color = { 1, 1, 1, 1 },
                blend_mode = { "alpha" },
                source_object_type = "arch"
            })
        end
    -- Handle tree rendering
    elseif mapData == map.tree then
        for _, tree in ipairs(map.treeInstances) do
            table.insert(dynamic_draw_lists, {
                sort_y = base_sort_y + tree.y,
                image_or_particles = map.tiles4.tilesetImage,
                quad = map.tiles4.quads[1],
                x = tree.x,
                y = tree.y,
                rotation = 0,
                scale_x = map_scale,
                scale_y = map_scale,
                offset_x = 0,
                offset_y = 0,
                color = { 1, 1, 1, 1 },
                blend_mode = { "alpha" },
                source_object_type = "tree"
            })
        end
    -- Handle regular map tiles
    else
        local max_tiles_x = math.ceil(var.game_width / (mapData.tiles.tileWidth * map_scale))
        local max_tiles_y = math.ceil(var.game_height / (mapData.tiles.tileHeight * map_scale))
        
        for row = 1, max_tiles_y do
            for col = 1, max_tiles_x do
                local tileId = mapData.tileData[row] and mapData.tileData[row][col]
                if tileId and tileId > 0 and mapData.tiles.quads[tileId] then
                    local tile_x = map_x + (col - 1) * mapData.tiles.tileWidth * map_scale
                    local tile_y = map_y + (row - 1) * mapData.tiles.tileHeight * map_scale
                    local tile_sort_y = base_sort_y + tile_y

                    table.insert(dynamic_draw_lists, {
                        sort_y = tile_sort_y,
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
                        source_object_type = "map_tile"
                    })
                end
            end
        end
    end

    return dynamic_draw_lists
end

return map