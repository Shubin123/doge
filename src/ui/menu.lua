-- menu.lua

local menu = {}
menu.blur = false
menu.currentMenu = "main" -- "main", "settings", or "saves"

-- Import required modules
local serial = require("lib.utils.serial")
local logger = require("lib.utils.logger")

local font
local ps

-- Save management state
local saveFiles = {}
local selectedSaveIndex = 1
local saveListNeedsRefresh = true
local popupMessage = nil
local popupTimer = 0
local popupDuration = 3.0

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
local backSettingsButton = { y = 350, text = "[ Back ]" }

-- Saves menu buttons
local saveGameButton = { y = 220, text = "[ Save Game ]" }
local loadGameButton = { y = 260, text = "[ Load Game ]" }
local deleteSaveButton = { y = 300, text = "[ Delete Save ]" }
local refreshSavesButton = { y = 330, text = "[ Refresh List ]" }
local backSavesButton = { y = 360, text = "[ Back ]" }

-- Save list display settings
local saveListStartY = 400
local saveListItemHeight = 20
local maxVisibleSaves = 8

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
    particles = true
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
    font = love.graphics.newFont("gfx/menu/PixelGameFont.ttf", 16)
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
    
    -- Update popup timer
    if popupMessage and popupTimer > 0 then
        popupTimer = popupTimer - dt
        if popupTimer <= 0 then
            popupMessage = nil
        end
    end
    
    -- Refresh save list when entering saves menu
    if menu.currentMenu == "saves" and saveListNeedsRefresh then
        menu.listSaves()
        saveListNeedsRefresh = false
    end
end

function menu.draw()
    if graphicsSettings.particles then
        love.graphics.draw(ps)
    end

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

        love.graphics.printf(backSettingsButton.text, 0, backSettingsButton.y, var.screen_width, "center")

    elseif menu.currentMenu == "saves" then
        love.graphics.printf("Save Management", 0, 180, var.screen_width, "center")
        love.graphics.printf(saveGameButton.text, 0, saveGameButton.y, var.screen_width, "center")
        love.graphics.printf(loadGameButton.text, 0, loadGameButton.y, var.screen_width, "center")
        love.graphics.printf(deleteSaveButton.text, 0, deleteSaveButton.y, var.screen_width, "center")
        love.graphics.printf(refreshSavesButton.text, 0, refreshSavesButton.y, var.screen_width, "center")
        love.graphics.printf(backSavesButton.text, 0, backSavesButton.y, var.screen_width, "center")
        
        -- Draw save file list
        menu.drawSaveList()
    end
    
    -- Draw popup message if active
    if popupMessage and popupTimer > 0 then
        menu.drawPopup()
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
        if inBounds(startButton) then return "running" end
        if inBounds(settingsButton) then menu.currentMenu = "settings" return nil end
        if inBounds(savesButton) then 
            menu.currentMenu = "saves"
            saveListNeedsRefresh = true
            return nil 
        end
        if inBounds(exitButton) then return "exit" end

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
        if inBounds(refreshSavesButton) then 
            menu.listSaves()
            menu.showPopup("Save list refreshed", "info")
        end
        if inBounds(backSavesButton) then menu.currentMenu = "main" end
        
        -- Handle save file selection
        menu.handleSaveListClick(x, y, screenInfo)
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

-- List available save files with metadata
function menu.listSaves()
    if not serial or not serial.ready then
        logger.error("Serial module not available or not ready")
        saveFiles = {}
        return
    end
    
    saveFiles = serial.getSaveFiles()
    logger.info("Loaded " .. #saveFiles .. " save files")
    
    -- Ensure selected index is valid
    if selectedSaveIndex > #saveFiles then
        selectedSaveIndex = math.max(1, #saveFiles)
    end
end

-- Enhanced save game function with slot/filename selection
function menu.saveGame()
    if not serial or not serial.ready then
        menu.showPopup("Save system not available", "error")
        return
    end
    
    local success, msg
    
    -- If we have a selected save file, use its filename, otherwise create new quicksave
    if #saveFiles > 0 and selectedSaveIndex <= #saveFiles then
        local selectedSave = saveFiles[selectedSaveIndex]
        if selectedSave.info and selectedSave.info.slot then
            -- Use slot-based saving for quicksaves
            success, msg = serial.quickSave(selectedSave.info.slot)
        else
            -- Use filename-based saving for manual saves
            local filename = selectedSave.filename:gsub("%.sav$", "")
            success, msg = serial.saveToFile(filename)
        end
    else
        -- Default to quicksave slot 1
        success, msg = serial.quickSave(1)
    end
    
    -- Log and display result
    if success then
        logger.info("Save successful: " .. msg)
        menu.showPopup("Game saved successfully", "info")
        saveListNeedsRefresh = true
    else
        logger.error("Save failed: " .. msg)
        menu.showPopup("Save failed: " .. msg, "error")
    end
end

-- Enhanced load game function with slot/filename selection
function menu.loadGame()
    if not serial or not serial.ready then
        menu.showPopup("Save system not available", "error")
        return
    end
    
    if #saveFiles == 0 then
        menu.showPopup("No save files available", "error")
        return
    end
    
    if selectedSaveIndex > #saveFiles then
        menu.showPopup("Invalid save file selection", "error")
        return
    end
    
    local selectedSave = saveFiles[selectedSaveIndex]
    local success, msg
    
    if selectedSave.info and selectedSave.info.slot then
        -- Use slot-based loading for quicksaves
        success, msg = serial.quickLoad(selectedSave.info.slot)
    else
        -- Use filename-based loading for manual saves
        local filename = selectedSave.filename:gsub("%.sav$", "")
        success, msg = serial.loadFromFile(filename)
    end
    
    -- Log and display result
    if success then
        logger.info("Load successful: " .. msg)
        menu.showPopup("Game loaded successfully", "info")
        -- Switch back to game after successful load
        return "running"
    else
        logger.error("Load failed: " .. msg)
        menu.showPopup("Load failed: " .. msg, "error")
    end
end

-- Enhanced delete save function with actual file deletion
function menu.deleteSave()
    if not serial or not serial.ready then
        menu.showPopup("Save system not available", "error")
        return
    end
    
    if #saveFiles == 0 then
        menu.showPopup("No save files to delete", "error")
        return
    end
    
    if selectedSaveIndex > #saveFiles then
        menu.showPopup("Invalid save file selection", "error")
        return
    end
    
    local selectedSave = saveFiles[selectedSaveIndex]
    local filename = selectedSave.filename:gsub("%.sav$", "")
    
    local success, msg = serial.deleteSave(filename)
    
    -- Log and display result
    if success then
        logger.info("Delete successful: " .. msg)
        menu.showPopup("Save file deleted", "info")
        
        -- Refresh the save list and adjust selection
        menu.listSaves()
        if selectedSaveIndex > #saveFiles and #saveFiles > 0 then
            selectedSaveIndex = #saveFiles
        elseif #saveFiles == 0 then
            selectedSaveIndex = 1
        end
    else
        logger.error("Delete failed: " .. msg)
        menu.showPopup("Delete failed: " .. msg, "error")
    end
end

-- Draw the save file list
function menu.drawSaveList()
    if #saveFiles == 0 then
        love.graphics.printf("No save files found", 0, saveListStartY, var.screen_width, "center")
        return
    end
    
    local startIndex = math.max(1, selectedSaveIndex - math.floor(maxVisibleSaves / 2))
    local endIndex = math.min(#saveFiles, startIndex + maxVisibleSaves - 1)
    
    for i = startIndex, endIndex do
        local save = saveFiles[i]
        local y = saveListStartY + (i - startIndex) * saveListItemHeight
        
        -- Highlight selected save
        if i == selectedSaveIndex then
            love.graphics.setColor(0.3, 0.3, 0.8, 0.5)
            love.graphics.rectangle("fill", 50, y - 2, var.screen_width - 100, saveListItemHeight)
            love.graphics.setColor(1, 1, 1, 1)
        end
        
        -- Format save file info
        local displayText = save.filename
        if save.info then
            local timeStr = save.info.timestamp_formatted or "Unknown"
            local levelStr = save.info.level or "?"
            local typeStr = save.info.save_type or "Manual"
            displayText = string.format("%s - %s (Level %s) - %s", 
                save.filename:gsub("%.sav$", ""), typeStr, levelStr, timeStr)
        elseif save.error then
            displayText = save.filename .. " (Error: " .. save.error .. ")"
            love.graphics.setColor(1, 0.5, 0.5, 1)
        end
        
        love.graphics.printf(displayText, 60, y, var.screen_width - 120, "left")
        love.graphics.setColor(1, 1, 1, 1)
    end
    
    -- Draw scroll indicators
    if startIndex > 1 then
        love.graphics.printf("↑ More saves above", 0, saveListStartY - 20, var.screen_width, "center")
    end
    if endIndex < #saveFiles then
        love.graphics.printf("↓ More saves below", 0, saveListStartY + maxVisibleSaves * saveListItemHeight, var.screen_width, "center")
    end
    
    -- Draw selection info
    if selectedSaveIndex <= #saveFiles then
        love.graphics.printf(string.format("Selected: %d/%d", selectedSaveIndex, #saveFiles), 
            0, saveListStartY + maxVisibleSaves * saveListItemHeight + 20, var.screen_width, "center")
    end
end

-- Handle clicks on the save list
function menu.handleSaveListClick(x, y, screenInfo)
    if #saveFiles == 0 then return end
    
    local startIndex = math.max(1, selectedSaveIndex - math.floor(maxVisibleSaves / 2))
    local endIndex = math.min(#saveFiles, startIndex + maxVisibleSaves - 1)
    
    for i = startIndex, endIndex do
        local itemY = saveListStartY + (i - startIndex) * saveListItemHeight
        if y >= itemY - 2 and y <= itemY + saveListItemHeight + 2 and
           x >= 50 and x <= var.screen_width - 50 then
            selectedSaveIndex = i
            break
        end
    end
end

-- Show popup message with color coding
function menu.showPopup(message, level)
    popupMessage = {
        text = message,
        level = level or "info"
    }
    popupTimer = popupDuration
    
    -- Also log the message
    if level == "error" then
        logger.error(message)
    elseif level == "warn" then
        logger.warn(message)
    else
        logger.info(message)
    end
end

-- Draw popup message
function menu.drawPopup()
    if not popupMessage then return end
    
    local alpha = math.min(1, popupTimer / 0.5) -- Fade out in last 0.5 seconds
    local bgColor = {0, 0, 0, 0.8 * alpha}
    local textColor = {1, 1, 1, alpha}
    
    -- Color code based on level
    if popupMessage.level == "error" then
        textColor = {1, 0.3, 0.3, alpha}
    elseif popupMessage.level == "warn" then
        textColor = {1, 0.8, 0, alpha}
    elseif popupMessage.level == "info" then
        textColor = {0.3, 1, 0.3, alpha}
    end
    
    -- Draw background
    love.graphics.setColor(bgColor)
    local textWidth = font:getWidth(popupMessage.text)
    local textHeight = font:getHeight()
    local popupX = (var.screen_width - textWidth) / 2 - 20
    local popupY = 50
    love.graphics.rectangle("fill", popupX, popupY, textWidth + 40, textHeight + 20)
    
    -- Draw text
    love.graphics.setColor(textColor)
    love.graphics.printf(popupMessage.text, 0, popupY + 10, var.screen_width, "center")
    love.graphics.setColor(1, 1, 1, 1)
end

return menu
