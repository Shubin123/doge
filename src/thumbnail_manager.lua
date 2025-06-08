-- c:/Users/admin/Desktop/JAMUBC_Cloned_repos/doge/src/thumbnail_manager.lua

local MapDescriptor    = require("map_descriptor")
local TileMapFactory   = require("tilemap_factory")

local ThumbnailManager = {}

-- Cache for completed thumbnails: mapId -> love.Canvas
local thumbnailCache   = {}

-- Active generation coroutines: mapId -> coroutine
local generators       = {}

-- Maximum thumbnail dimensions
local THUMB_MAX_SIZE = 128

--- Start generating a thumbnail for the given mapId.
-- If a thumbnail is already cached or generation is in progress, this is a no-op.
function ThumbnailManager.generateThumbnail(mapId)
    if thumbnailCache[mapId] or generators[mapId] then
        return
    end

    -- Coroutine that loads descriptor, creates tilemap, draws to canvas
    local co = coroutine.create(function()
        -- 1) Load map descriptor (must include tileset, tileWidth, tileHeight, mapWidth, mapHeight, tileData)
        local mapDef = MapDescriptor.loadDescriptor(mapId)
        coroutine.yield()

        -- 2) Set up world origin and scale to fit within THUMB_MAX_SIZE
        mapDef.worldX = 0
        mapDef.worldY = 0
        local fullW = mapDef.mapWidth * mapDef.tileWidth
        local fullH = mapDef.mapHeight * mapDef.tileHeight
        local scale = math.min(THUMB_MAX_SIZE / fullW, THUMB_MAX_SIZE / fullH)
        mapDef.scale = scale
        coroutine.yield()

        -- 3) Create the TileMap
        local tileMap = TileMapFactory.createTileMap(mapDef)
        coroutine.yield()

        -- 4) Create canvas and draw the tilemap into it
        local canvasW = math.ceil(fullW * scale)
        local canvasH = math.ceil(fullH * scale)
        local canvas  = love.graphics.newCanvas(canvasW, canvasH)

        love.graphics.push()
        love.graphics.setCanvas(canvas)
        love.graphics.clear()

        -- Fake camera that views the entire canvas
        local camera = {
            view_bounds = { x1 = 0, y1 = 0, x2 = canvasW, y2 = canvasH },
            isInView = function() return true end
        }
        tileMap:draw(camera)

        love.graphics.setCanvas()
        love.graphics.pop()

        -- 5) Store completed thumbnail
        thumbnailCache[mapId] = canvas
    end)

    generators[mapId] = co
end

--- Get a generated thumbnail canvas, or nil if not ready.
-- @param mapId string
-- @return love.Canvas or nil
function ThumbnailManager.getThumbnail(mapId)
    return thumbnailCache[mapId]
end

--- Advance generation coroutines by one step.
-- Call this every frame with dt to drive non-blocking thumbnail creation.
function ThumbnailManager.update(dt)
    for mapId, co in pairs(generators) do
        local ok, err = coroutine.resume(co, dt)
        if not ok then
            -- On error, drop this generator
            print(("Error generating thumbnail for '%s': %s"):format(mapId, tostring(err)))
            generators[mapId] = nil
        elseif coroutine.status(co) == "dead" then
            -- Finished successfully
            generators[mapId] = nil
        end
    end
end

return ThumbnailManager