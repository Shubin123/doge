-- c:/Users/admin/Desktop/JAMUBC_Cloned_repos/doge/src/tilemap_factory.lua

local ResourceCache = require("resource_cache")

local TileMapFactory = {}

--- Create a tile map from a map definition.
-- @param mapDef table Map definition containing:
--   tileset     = string path to tileset image
--   tileWidth   = number width of each tile
--   tileHeight  = number height of each tile
--   mapWidth    = number number of columns
--   mapHeight   = number of rows
--   tileData    = table 2D array of tile IDs
--   worldX      = number (optional) world offset X, default 0
--   worldY      = number (optional) world offset Y, default 0
--   scale       = number (optional) draw scale, default 1
-- @return TileMap object with methods draw(camera), getTile(x,y), setTile(x,y,id), worldToTile(wx,wy), tileToWorld(tx,ty)
function TileMapFactory.createTileMap(mapDef)
    assert(type(mapDef) == "table", "createTileMap requires a mapDef table")
    assert(type(mapDef.tileset) == "string", "mapDef.tileset must be a string")
    assert(type(mapDef.tileWidth) == "number" and type(mapDef.tileHeight) == "number",
           "mapDef.tileWidth and mapDef.tileHeight must be numbers")
    assert(type(mapDef.mapWidth) == "number" and type(mapDef.mapHeight) == "number",
           "mapDef.mapWidth and mapDef.mapHeight must be numbers")
    assert(type(mapDef.tileData) == "table", "mapDef.tileData must be a table")

    local image   = ResourceCache.loadImage(mapDef.tileset)
    local tileW   = mapDef.tileWidth
    local tileH   = mapDef.tileHeight
    local quads   = ResourceCache.getQuadSheet(image, tileW, tileH)

    local width   = mapDef.mapWidth
    local height  = mapDef.mapHeight
    local data    = mapDef.tileData
    local worldX  = mapDef.worldX or 0
    local worldY  = mapDef.worldY or 0
    local scale   = mapDef.scale or 1

    local TileMap = {}

    -- Draw only visible tiles using camera culling
    function TileMap:draw(camera)
        local vw1, vy1, vx2, vy2 = camera.view_bounds.x1, camera.view_bounds.y1,
                                   camera.view_bounds.x2, camera.view_bounds.y2
        local tileWScaled = tileW * scale
        local tileHScaled = tileH * scale

        local startCol = math.max(1, math.floor((vw1 - worldX) / tileWScaled) + 1)
        local endCol   = math.min(width, math.ceil((vx2 - worldX) / tileWScaled) + 1)
        local startRow = math.max(1, math.floor((vy1 - worldY) / tileHScaled) + 1)
        local endRow   = math.min(height, math.ceil((vy2 - worldY) / tileHScaled) + 1)

        for row = startRow, endRow do
            local rowData = data[row]
            if rowData then
                for col = startCol, endCol do
                    local tid = rowData[col]
                    if tid and tid > 0 and quads[tid] then
                        local x = worldX + (col - 1) * tileWScaled
                        local y = worldY + (row - 1) * tileHScaled
                        if camera.isInView(x, y, tileWScaled, tileHScaled) then
                            love.graphics.draw(image, quads[tid], x, y, 0, scale, scale)
                        end
                    end
                end
            end
        end
    end

    -- Get the tile ID at tile coordinates (1-based). Returns nil if out of bounds.
    function TileMap:getTile(tx, ty)
        if tx >= 1 and tx <= width and ty >= 1 and ty <= height then
            return data[ty][tx]
        end
        return nil
    end

    -- Set the tile ID at tile coordinates (1-based). No-op if out of bounds.
    function TileMap:setTile(tx, ty, tid)
        if tx >= 1 and tx <= width and ty >= 1 and ty <= height then
            data[ty][tx] = tid
        end
    end

    -- Convert world coordinates to tile coordinates (1-based)
    function TileMap:worldToTile(wx, wy)
        local tx = math.floor((wx - worldX) / (tileW * scale)) + 1
        local ty = math.floor((wy - worldY) / (tileH * scale)) + 1
        return tx, ty
    end

    -- Convert tile coordinates (1-based) to world coordinates
    function TileMap:tileToWorld(tx, ty)
        local wx = worldX + (tx - 1) * tileW * scale
        local wy = worldY + (ty - 1) * tileH * scale
        return wx, wy
    end

    return TileMap
end

return TileMapFactory