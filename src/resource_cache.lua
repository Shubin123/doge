-- c:/Users/admin/Desktop/JAMUBC_Cloned_repos/doge/src/resource_cache.lua

local ResourceCache = {}

-- Stores loaded images and their reference counts by path
local imageCache = {}

-- Weak-keyed table mapping image objects to their quad sheets
local quadCache = setmetatable({}, { __mode = "k" })

--- Loads an image from disk or returns a cached one.
-- Increments the reference count for the image.
-- @param path string Path to the image file
-- @return love.Image the loaded image
function ResourceCache.loadImage(path)
    local entry = imageCache[path]
    if entry then
        entry.count = entry.count + 1
        return entry.image
    end
    local img = love.graphics.newImage(path)
    imageCache[path] = { image = img, count = 1 }
    return img
end

--- Returns a table of quads for the given image tiled at tileW x tileH.
-- Caches quads per image and tile size.
-- @param image love.Image the image object
-- @param tileW number width of a single tile
-- @param tileH number height of a single tile
-- @return table array of love.Quad
function ResourceCache.getQuadSheet(image, tileW, tileH)
    local sheets = quadCache[image]
    if not sheets then
        sheets = {}
        quadCache[image] = sheets
    end
    local key = tileW .. "x" .. tileH
    if sheets[key] then
        return sheets[key]
    end

    local imgW, imgH = image:getDimensions()
    local quads = {}
    for y = 0, imgH - tileH, tileH do
        for x = 0, imgW - tileW, tileW do
            quads[#quads + 1] = love.graphics.newQuad(x, y, tileW, tileH, imgW, imgH)
        end
    end
    sheets[key] = quads
    return quads
end

--- Decrements the reference count for an image and unloads it if count reaches zero.
-- Also clears any cached quad sheets for that image.
-- @param path string Path to the image file
function ResourceCache.releaseImage(path)
    local entry = imageCache[path]
    if not entry then
        return
    end
    entry.count = entry.count - 1
    if entry.count <= 0 then
        local img = entry.image
        imageCache[path] = nil
        quadCache[img] = nil
    end
end

return ResourceCache