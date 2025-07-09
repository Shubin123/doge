-- Store the original function
local originalNewImage = love.graphics.newImage

-- Create your override function
local function compressedImage(f, s)
    -- print(f)
    -- s = {mipmaps=true,linear=true}
    return originalNewImage(f, s)  -- Call the original function
end

-- Override the function
love.graphics.newImage = compressedImage