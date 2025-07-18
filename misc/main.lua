-- Function pointer storage
local originalDraw = nil
local preLoadDraw = nil
local postLoadDraw = nil

-- Loading state
local loadingAssets = {}
local currentAsset = ""
local loadingProgress = 0
local totalAssets = 0
local isLoading = true

function setupDrawFunctions()
    -- Store original draw function (if any)
    originalDraw = love.draw
    
    -- Pre-load draw function - draws triangle during loading
    preLoadDraw = function()
        love.graphics.clear(0.1, 0.1, 0.2) -- Dark blue background
        
        -- Draw triangle
        love.graphics.setColor(1, 0.5, 0) -- Orange
        love.graphics.polygon("fill", 400, 200, 350, 300, 450, 300)
        
        -- Loading text based on current state
        love.graphics.setColor(1, 1, 1) -- White
        love.graphics.print("Loading...", 10, 10, 0, 2, 2)
        love.graphics.print("Current: " .. currentAsset, 10, 50, 0, 1.5, 1.5)
        
        -- Progress indicator
        love.graphics.print("Progress: " .. loadingProgress .. "/" .. totalAssets, 10, 100, 0, 1.5, 1.5)
        
        -- Progress bar
        love.graphics.setColor(0.3, 0.3, 0.3) -- Dark gray
        love.graphics.rectangle("fill", 10, 150, 300, 20)
        love.graphics.setColor(1, 0.5, 0) -- Orange
        local progressWidth = (loadingProgress / totalAssets) * 300
        love.graphics.rectangle("fill", 10, 150, progressWidth, 20)
    end
    
    -- Post-load draw function - draws circle after loading
    postLoadDraw = function()
        love.graphics.clear(0.2, 0.1, 0.1) -- Dark red background
        
        -- Draw circle
        love.graphics.setColor(0, 1, 0.5) -- Green
        love.graphics.circle("fill", 400, 250, 80)
        
        -- Game ready text
        love.graphics.setColor(1, 1, 1) -- White
        love.graphics.print("Game Loaded!", 10, 10, 0, 3, 3)
        love.graphics.print("Triangle changed to Circle!", 10, 60, 0, 1.5, 1.5)
        love.graphics.print("Press ESC to quit", 10, 400)
        
        -- Show all loaded assets
        local y = 120
        love.graphics.print("Loaded Assets:", 10, y)
        y = y + 25
        for i, asset in ipairs(loadingAssets) do
            love.graphics.print("• " .. asset, 20, y)
            y = y + 20
        end
    end
end

function love.load()
    setupDrawFunctions()
    
    -- Set to pre-load draw (triangle phase)
    love.draw = preLoadDraw
    
    -- Simulate asset loading
    local assetsToLoad = {
        "apple.png",
        "apple copy.png",
        "apple copy 2.png",
        "apple copy 3.png",
    }
    
    totalAssets = #assetsToLoad
    loadingProgress = 0
    
    for i, assetPath in ipairs(assetsToLoad) do
        -- Update current asset via callback
        currentAsset = assetPath
        
        -- Force a draw update during loading
        love.graphics.clear()
        love.draw() -- Call our triangle drawing function
        love.graphics.present()
        
        -- Simulate loading time
        love.timer.sleep(0.8)
        
        -- "Load" the asset (simulated) and update progress
        table.insert(loadingAssets, assetPath)
        loadingProgress = i
    end
    
    -- Loading complete - switch to post-load draw (circle phase)
    love.draw = postLoadDraw
    isLoading = false
    
    -- Final draw update to show the circle
    love.graphics.clear()
    love.draw()
    love.graphics.present()
    
    for _, assetPath in ipairs(assetsToLoad) do
        currentAsset = assetPath
        
        -- Force a draw update during loading
        love.graphics.clear()
        love.draw() -- Call our triangle drawing function
        love.graphics.present()
        
        -- Simulate loading time
        love.timer.sleep(0.8)
        
        -- "Load" the asset (simulated)
        table.insert(loadingAssets, assetPath)
    end
    
    -- Loading complete - switch to post-load draw (circle phase)
    love.draw = postLoadDraw
    isLoading = false
    
    -- Final draw update to show the circle
    love.graphics.clear()
    love.draw()
    love.graphics.present()
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    end
end