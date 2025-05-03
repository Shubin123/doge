local map = {}
local var = require("var")

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
        local max_tiles_x = math.ceil(var.game_width / (self.tiles.tileWidth * scale))
        local max_tiles_y = math.ceil(var.game_height / (self.tiles.tileHeight * scale))
        for row = 1, max_tiles_y do
            for col = 1, max_tiles_x do
                local tileId = self.tileData[row][col]
                if tileId > 0 and self.tiles.quads[tileId] then
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

function map.load()
    
    local tilesetImage = love.graphics.newImage("gfx/TileSet/TX Tileset Grass.png")
    
    map.tiles = newTiles(tilesetImage, var.tile_w, var.tile_h)
    map.map = createMap(map.tiles, var.map_display_w, var.map_display_h)
    for x = 1, 26 do 
        for y = 1, 26 do
            
            map.map:setTile(x, y, math.random(1,200))
        end
    end


    local tilesetImage2 = love.graphics.newImage("gfx/TileSet/TX Tileset Wall.png")
    
    -- for i = 1, 20 do
    --     map.map:setTile(i, 10, 30)
    -- end
    
end

function map.getMap()
    return map.map
end

return map