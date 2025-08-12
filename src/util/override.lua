local currentAsset --local to ovrriden mem how?
local loadingAssets = {}

-- love.graphics.image override procedure --

-- Store the original function
local originalNewImage = love.graphics.newImage

-- Create your override function
local function compressedImage(f, s)
    -- print(f)
    -- s = {mipmaps=true,linear=true}
    currentAsset = f
    table.insert(loadingAssets,f)

    love.graphics.clear()
    preLoadDraw()    
    love.graphics.present()
    
    -- love.timer.sleep(1)    

    return originalNewImage(f, s) -- Call the original function
end

-- Override the function
-- love.graphics.newImage = compressedImage

-- ENDOF love.graphics.image override procedure --

-- love.graphics.draw override procedure --
    

-- function setup()
preLoadDraw = function()
    -- print(currentAsset)
    if type(currentAsset) == "string" then
    love.graphics.clear(0.1, 0.1, 0.2)     -- Dark blue background


    -- Loading text
    love.graphics.setColor(1, 1, 1)     -- White
    love.graphics.print("Loading...", 10, 10, 0, 2, 2)
    love.graphics.print("Current: " .. currentAsset, 10, 50, 0, 1.5, 1.5)

    -- -- Show loaded assets
    local y = 100
    for i, asset in pairs(loadingAssets) do
        if type(asset) == "string" then
        -- print(i,asset)
        
        love.graphics.print("+ " .. asset, 10, y)
        y = y + 10
        end
    end

    -- -- Progress indicator
    -- love.graphics.print("Assets loaded: " .. #loadingAssets, 10, 400)
    end
end
-- love.draw = preLoadDraw
-- end

-- ENDOF love.graphics.draw override procedure --