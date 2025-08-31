-- menu.lua

local menu = {}
menu.blur = false
menu.currentMenu = "main" -- "main", "settings", or "saves"

local font
local ps

-- Main menu buttons
local startButton = { y = 250, text = "[ Start Game ]" }
local settingsButton = { y = 280, text = "[ Settings ]" }
local savesButton = { y = 310, text = "[ Saves ]" }
local exitButton = { y = 340, text = "[ Exit ]" }

-- Settings menu buttons and options
local resolutionButton = { y = 220, text = "Resolution: " }
local fullscreenButton = { y = 250, text = "Fullscreen: " }
local vsyncButton = { y = 280, text = "V-Sync: " }
local particlesButton = { y = 310, text = "Particles: " }
local highqualityButton = { y = 350, text = "Toggle Quality: " }
local backSettingsButton = { y = 430, text = "[ Back ]" }

-- Saves menu buttons
local saveGameButton = { y = 220, text = "[ Save Game ]" }
local loadGameButton = { y = 260, text = "[ Load Game ]" }
local deleteSaveButton = { y = 300, text = "[ Delete Save ]" }
local backSavesButton = { y = 340, text = "[ Back ]" }

-- Graphics settings data
local graphicsSettings = {
    resolutions = {
        {width = 800, height = 600, text = "800x600"},
        {width = 1024, height = 768, text = "1024x768"},
        {width = 1280, height = 720, text = "1280x720"},
        {width = 1920, height = 1080, text = "1920x1080"}
    },
    currentResolution = 1,
    fullscreen = false,
    vsync = true,
    particles = true,
    highquality = var.graphics_high
}

local function getButtonBounds(buttonInfo, screenInfo)
    local bounds = {}
    bounds.height = font:getHeight()
    bounds.width = font:getWidth(buttonInfo.text)
    bounds.x = (screenInfo.screen_width - bounds.width) / 2
    bounds.y = buttonInfo.y
    return bounds
end

local function getSettingsButtonBounds(buttonInfo, optionText, screenInfo)
    local fullText = buttonInfo.text .. optionText
    local bounds = {}
    bounds.height = font:getHeight()
    bounds.width = font:getWidth(fullText)
    bounds.x = (screenInfo.screen_width - bounds.width) / 2
    bounds.y = buttonInfo.y
    return bounds
end

function menu.load(screenInfo)
    font = love.graphics.newFont("gfx/menu/Px437_IBM_VGA_8x16.ttf", 16)
    particle = love.graphics.newImage("gfx/doge.png")
    love.graphics.setFont(font)

    -- ps = love.graphics.newParticleSystem(particle, 1000)
    -- ps:setParticleLifetime(6, 12)
    -- ps:setEmissionRate(10)
    -- ps:setSizes(2)
    -- ps:setColors({0.5,0.5,0.5,0}, {0.5,0.5,0.5,0.5}, {0.5,0.5,0.5,0})
    -- ps:setSpeed(50, 100)
    -- ps:setDirection(math.pi / 2)
    -- ps:setSpread(0.4)
    -- ps:setEmissionArea("uniform", screenInfo.screen_width, 1)
    -- ps:setPosition(screenInfo.screen_width / 2, -50)
    -- ps:setEmitterLifetime(-1)
    -- ps:start()
end

function menu.update(dt)
    -- if graphicsSettings.particles then
    --     ps:update(dt)
    -- end
end

function menu.draw()
    


    -- if graphicsSettings.particles then
    --     love.graphics.draw(ps)
    -- end

    love.graphics.setColor(1, 1, 1, 1)

    if menu.currentMenu == "main" then
        love.graphics.printf("Doge.", 0, 90, var.screen_width/2, "center", 0, 2, 2)
        love.graphics.printf("Game Version = alpha 0.0.2", 0, 125, var.screen_width/0.8, "center", 0, 0.8, 0.8)
        love.graphics.printf(startButton.text, 0, startButton.y, var.screen_width, "center")
        love.graphics.printf(settingsButton.text, 0, settingsButton.y, var.screen_width, "center")
        love.graphics.printf(savesButton.text, 0, savesButton.y, var.screen_width, "center")
        love.graphics.printf(exitButton.text, 0, exitButton.y, var.screen_width, "center")

    elseif menu.currentMenu == "settings" then
        love.graphics.printf("Graphics Settings", 0, 180, var.screen_width, "center")

        local resText = graphicsSettings.resolutions[graphicsSettings.currentResolution].text
        love.graphics.printf(resolutionButton.text .. resText, 0, resolutionButton.y, var.screen_width, "center")

        local fullscreenText = graphicsSettings.fullscreen and "ON" or "OFF"
        love.graphics.printf(fullscreenButton.text .. fullscreenText, 0, fullscreenButton.y, var.screen_width, "center")

        local vsyncText = graphicsSettings.vsync and "ON" or "OFF"
        love.graphics.printf(vsyncButton.text .. vsyncText, 0, vsyncButton.y, var.screen_width, "center")

        local particlesText = graphicsSettings.particles and "ON" or "OFF"
        love.graphics.printf(particlesButton.text .. particlesText, 0, particlesButton.y, var.screen_width, "center")

        local highqualtyText = graphicsSettings.highquality and "ON" or "OFF"
        love.graphics.printf(highqualityButton.text .. highqualtyText, 0, highqualityButton.y, var.screen_width, "center")

        love.graphics.printf(backSettingsButton.text, 0, backSettingsButton.y, var.screen_width, "center")

    elseif menu.currentMenu == "saves" then
        love.graphics.printf("Save Management", 0, 180, var.screen_width, "center")
        love.graphics.printf(saveGameButton.text, 0, saveGameButton.y, var.screen_width, "center")
        love.graphics.printf(loadGameButton.text, 0, loadGameButton.y, var.screen_width, "center")
        love.graphics.printf(deleteSaveButton.text, 0, deleteSaveButton.y, var.screen_width, "center")
        love.graphics.printf(backSavesButton.text, 0, backSavesButton.y, var.screen_width, "center")
    end
end

function menu.drawUI()
    if var.State == "menu" then
        menu.draw()
        love.graphics.draw(oldhand, love.mouse.getX(), love.mouse.getY(), 0, 0.05, 0.05)
        return
    end
    

    -- Draw header
    love.graphics.setColor(0.2, 0.2, 0.2)
    love.graphics.rectangle("fill", 0, 0, W, var.header_height)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Health: "..player.health, 10, 10)
    love.graphics.print("Points: " .. var.player_score, W - 100, 10)
end

function menu.mousepressed(x, y, button, screenInfo)
    if button ~= 1 then return nil end

    local function inBounds(b)
        local bounds = getButtonBounds(b, screenInfo)
        return x >= bounds.x and x <= bounds.x + bounds.width and
               y >= bounds.y and y <= bounds.y + bounds.height
    end

    if menu.currentMenu == "main" then
        if inBounds(startButton) then return "running" end
        if inBounds(settingsButton) then menu.currentMenu = "settings" return nil end
        if inBounds(savesButton) then menu.currentMenu = "saves" return nil end
        if inBounds(exitButton) then return "exit" end

    elseif menu.currentMenu == "settings" then
        local res = graphicsSettings.resolutions[graphicsSettings.currentResolution]
        if inBounds({y = resolutionButton.y, text = resolutionButton.text .. res.text}) then
            
            graphicsSettings.currentResolution = graphicsSettings.currentResolution % #graphicsSettings.resolutions + 1
            menu.applyResolution()
            love.resize(graphicsSettings.resolutions[graphicsSettings.currentResolution].width,graphicsSettings.resolutions[graphicsSettings.currentResolution].height)
            -- love.resize(w, h)
            
            return nil
        end

        local fs = graphicsSettings.fullscreen and "ON" or "OFF"
        if inBounds({y = fullscreenButton.y, text = fullscreenButton.text .. fs}) then
            graphicsSettings.fullscreen = not graphicsSettings.fullscreen
            menu.applyFullscreen()
            return nil
        end

        local vs = graphicsSettings.vsync and "ON" or "OFF"
        if inBounds({y = vsyncButton.y, text = vsyncButton.text .. vs}) then
            graphicsSettings.vsync = not graphicsSettings.vsync
            menu.applyVsync()
            return nil
        end

        local pt = graphicsSettings.particles and "ON" or "OFF"
        if inBounds({y = particlesButton.y, text = particlesButton.text .. pt}) then
            graphicsSettings.particles = not graphicsSettings.particles
            return nil
        end

        local ht = graphicsSettings.highquality and "ON" or "OFF"
        if inBounds({y = highqualityButton.y, text = highqualityButton.text .. ht}) then
            graphicsSettings.particles = not graphicsSettings.particles
            var.graphics_high = not var.graphics_high
            
            return nil
        end

        if inBounds(backSettingsButton) then
            menu.currentMenu = "main"
            return nil
        end

    elseif menu.currentMenu == "saves" then
        if inBounds(saveGameButton) then menu.saveGame() end
        if inBounds(loadGameButton) then menu.loadGame() end
        if inBounds(deleteSaveButton) then menu.deleteSave() end
        if inBounds(backSavesButton) then menu.currentMenu = "main" end
    end

    return nil
end

function menu.applyResolution()
    local res = graphicsSettings.resolutions[graphicsSettings.currentResolution]
    love.window.setMode(res.width, res.height, {
        fullscreen = graphicsSettings.fullscreen,
        vsync = graphicsSettings.vsync
    })
    if var then
        var.screen_width = res.width
        var.screen_height = res.height
    end
    print("Resolution changed to: " .. res.text)
end

function menu.applyFullscreen()
    local res = graphicsSettings.resolutions[graphicsSettings.currentResolution]
    love.window.setMode(res.width, res.height, {
        fullscreen = graphicsSettings.fullscreen,
        vsync = graphicsSettings.vsync
    })
end

function menu.applyVsync()
    local res = graphicsSettings.resolutions[graphicsSettings.currentResolution]
    love.window.setMode(res.width, res.height, {
        fullscreen = graphicsSettings.fullscreen,
        vsync = graphicsSettings.vsync
    })
end

function menu.saveGame()
    print("Save game triggered.")
    serial.quickSave()
    
end

function menu.loadGame()
    print("Load game triggered.")
    serial.quickLoad()

end

function menu.deleteSave()
    print("Delete save triggered.")
    
end




return menu
