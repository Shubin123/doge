local img
local shader

function love.load()
    local filename = "out3.dds.zlib"
    
    -- Load the compressed DDS data
    local compressedData, size = love.filesystem.read(filename)
    if not compressedData then
        error("Failed to load compressed file: " .. filename)
    end
    
    -- Decompress the data
    local decompressedData = love.data.decompress("data", "zlib", compressedData)
    
    -- Create compressed data object and image
    local cd = love.image.newCompressedData(decompressedData, "dds")
    img = love.graphics.newImage(cd)
    
    -- At this point, decompressedData and cd can be garbage collected
    -- explicitly nil and free ~600mb of memory when loading a 16k squared texture
    decompressedData = nil
    cd = nil
    compressedData = nil
    collectgarbage()
end

function love.draw()
    -- Draw raw texture (for debugging what BC5 contains)
    -- love.graphics.setShader(rawShader)
    -- love.graphics.draw(img, 100, 100)
    -- love.graphics.setShader()
    
    -- -- Draw reconstructed normal map
    -- love.graphics.setShader(shader)
    -- love.graphics.draw(img, 300, 100)
    -- love.graphics.setShader()
    
    -- -- Labels
    -- love.graphics.print("Raw BC5 (RG only)", 100, 80)
    -- love.graphics.print("Reconstructed Normal", 300, 80)
    -- love.graphics.scale(camera.zoom,camera.zoom)
    love.graphics.draw(img, 100, 100)

end