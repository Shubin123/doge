-- menu.lua

local menu = {}
menu.blur = false
menu.currentMenu = "main" -- "main", "settings", or "saves"
menu.pauseMenu = false -- Whether menu was opened from pause

local font
local ps

-- Main menu buttons
local startButton = { y = 250, text = "[ Start Game ]" }
local resumeButton = { y = 250, text = "[ Resume Game ]" } -- For pause menu
local settingsButton = { y = 280, text = "[ Settings ]" }
local savesButton = { y = 310, text = "[ Saves ]" }
local exitButton = { y = 340, text = "[ Exit ]" }
local exitToMenuButton = { y = 340, text = "[ Exit to Menu ]" } -- For pause menu

-- Settings menu buttons and options
local resolutionButton = { y = 220, text = "Resolution: " }
local fullscreenButton = { y = 250, text = "Fullscreen: " }
local vsyncButton = { y = 280, text = "V-Sync: " }
local particlesButton = { y = 310, text = "Particles: " }
local backSettingsButton = { y = 350, text = "[ Back ]" }

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
    fullscreen = false,  -- fullscreen and windowed modes
    vsync = true,
    particles = true
    -- global illumination
    -- enable blood
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

    ps = love.graphics.newParticleSystem(particle, 1000)
    ps:setParticleLifetime(6, 12)
    ps:setEmissionRate(10)
    ps:setSizes(2)
    ps:setColors({0.5,0.5,0.5,0}, {0.5,0.5,0.5,0.5}, {0.5,0.5,0.5,0})
    ps:setSpeed(50, 100)
    ps:setDirection(math.pi / 2)
    ps:setSpread(0.4)
    ps:setEmissionArea("uniform", screenInfo.screen_width, 1)
    ps:setPosition(screenInfo.screen_width / 2, -50)
    ps:setEmitterLifetime(-1)
    ps:start()
end

function menu.update(dt)
    if graphicsSettings.particles then
        ps:update(dt)
    end
end

function menu.draw()
    if graphicsSettings.particles then
        love.graphics.draw(ps)
    end

    love.graphics.setColor(1, 1, 1, 1)

    if menu.currentMenu == "main" then
        love.graphics.printf("Doge.", 0, 90, var.screen_width/2, "center", 0, 2, 2)
        love.graphics.printf("Game Version = " .. var.game_version, 0, 125, var.screen_width/0.8, "center", 0, 0.8, 0.8)
        
        -- Show resume button if we're in pause menu, otherwise start button
        if menu.pauseMenu then
            love.graphics.printf(resumeButton.text, 0, resumeButton.y, var.screen_width, "center")
        else
            love.graphics.printf(startButton.text, 0, startButton.y, var.screen_width, "center")
        end
        
        love.graphics.printf(settingsButton.text, 0, settingsButton.y, var.screen_width, "center")
        love.graphics.printf(savesButton.text, 0, savesButton.y, var.screen_width, "center")
        
        -- Show different exit button if we're in pause menu
        if menu.pauseMenu then
            love.graphics.printf(exitToMenuButton.text, 0, exitToMenuButton.y, var.screen_width, "center")
        else
            love.graphics.printf(exitButton.text, 0, exitButton.y, var.screen_width, "center")
        end

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

        love.graphics.printf(backSettingsButton.text, 0, backSettingsButton.y, var.screen_width, "center")

    elseif menu.currentMenu == "saves" then
        love.graphics.printf("Save Management", 0, 180, var.screen_width, "center")
        love.graphics.printf(saveGameButton.text, 0, saveGameButton.y, var.screen_width, "center")
        love.graphics.printf(loadGameButton.text, 0, loadGameButton.y, var.screen_width, "center")
        love.graphics.printf(deleteSaveButton.text, 0, deleteSaveButton.y, var.screen_width, "center")
        love.graphics.printf(backSavesButton.text, 0, backSavesButton.y, var.screen_width, "center")
    end
end

function menu.mousepressed(x, y, button, screenInfo)
    if button ~= 1 then return nil end

    local function inBounds(b)
        local bounds = getButtonBounds(b, screenInfo)
        return x >= bounds.x and x <= bounds.x + bounds.width and
               y >= bounds.y and y <= bounds.y + bounds.height
    end

    if menu.currentMenu == "main" then
        -- Check resume/start button
        if menu.pauseMenu then
            if inBounds(resumeButton) then return "resume" end
        else
            if inBounds(startButton) then return "running" end
        end
        
        if inBounds(settingsButton) then menu.currentMenu = "settings" return nil end
        if inBounds(savesButton) then menu.currentMenu = "saves" return nil end
        
        -- Check exit button
        if menu.pauseMenu then
            if inBounds(exitToMenuButton) then 
                menu.pauseMenu = false
                return "exit_to_menu" 
            end
        else
            if inBounds(exitButton) then return "exit" end
        end

    elseif menu.currentMenu == "settings" then
        local res = graphicsSettings.resolutions[graphicsSettings.currentResolution]
        if inBounds({y = resolutionButton.y, text = resolutionButton.text .. res.text}) then
            graphicsSettings.currentResolution = graphicsSettings.currentResolution % #graphicsSettings.resolutions + 1
            menu.applyResolution()
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
    if serial then
        serial.quickSave()
    end
end

function menu.loadGame()
    print("Load game triggered.")
    if serial then
        serial.quickLoad()
    end
end

function menu.deleteSave()
    print("Delete save triggered.")
    -- TODO: Implement save deletion
end

-- Set whether menu is opened from pause
function menu.setPauseMode(isPause)
    menu.pauseMenu = isPause
end

return menu
