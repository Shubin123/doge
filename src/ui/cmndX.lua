-- cmdn.lua - In-game cmdn line for LÖVE 2D
local cmdn = {}

-- Module state
local isActive = false
local inputText = ""
local cursorPos = 0
local cursorTimer = 0
local cursorVisible = true
local history = {}
local historyIndex = 0
local output = {}
local maxOutputLines = 20
local scrollOffset = 0
local font
local lineHeight = 16
local padding = 10
local consoleHeight = 350
local consoleWidth = 500

-- Enhanced command state
local godmodeEnabled = false
local playerStates = {} -- Track godmode per player ID for multiplayer

-- Enhanced Live log viewer system with dynamic source detection
local gameLogsBuffer = {}
local maxLogLines = 1000
local originalPrint = print
local logFilter = ""
local liveLogsEnabled = false
local liveLogScrollOffset = 0
local liveLogHeight = 250
local liveLogWidth = 450
local liveLogX = 0  -- Will be set to right side
local liveLogY = 0  -- Will be set to bottom
local liveLogFont = nil
local liveLogLineHeight = 14
local maxLiveLogLines = 16
local liveLogPaused = false
local selectedLogIndex = -1
local pauseButtonHover = false
local clearButtonHover = false
local gameVersionShown = false
local liveLogLastUpdate = 0  -- Track last update time
local liveLogUpdateInterval = 0.1  -- Update every 100ms when paused

-- Log source detection and categorization
local function detectLogSource(message)
    local info = debug.getinfo(3, "S")
    local source = "UNKNOWN"
    local category = "system"
    
    if info and info.source then
        local sourcePath = info.source
        if sourcePath:find("mod_system") then
            source = "MOD_SYSTEM"
            category = "mod_system"
        elseif sourcePath:find("mods/") then
            local modName = sourcePath:match("mods/([^/]+)")
            source = "MOD:" .. (modName or "unknown")
            category = "mod"
        elseif sourcePath:find("rendererPlus") or sourcePath:find("new_renderer") then
            source = "rendererPlus"
            category = "renderer"
        elseif sourcePath:find("main%.lua") then
            source = "ENGINE"
            category = "core"
        elseif sourcePath:find("cmnd") then
            source = "CONSOLE"
            category = "debug"
        else
            source = "SYSTEM"
            category = "system"
        end
    end
    
    -- Further categorize based on message content
    if message:find("%[MOD_SYSTEM%]") then
        source = "MOD_SYSTEM"
        category = "mod_system"
    elseif message:find("%[MOD:([^%]]+)%]") then
        local modName = message:match("%[MOD:([^%]]+)%]")
        source = "MOD:" .. modName
        category = "mod"
    elseif message:find("%[rendererPlus%]") then
        source = "rendererPlus"
        category = "renderer"
    end
    
    return source, category
end

-- Common log filter patterns for autocomplete
local commonLogFilters = {
    "MOD_SYSTEM", "rendererPlus", "Error", "Warning", "Failed", 
    "player_core_mod", "weapons_core_mod", "combat_effects_mod",
    "projectiles_mod", "basic_enemies_mod", "bear_boss_mod",
    "health_damage_mod", "blood_effects_mod", "map_system",
    "GC collected", "World queue", "Loaded texture", "Success",
    "Initialization", "Complete", "Loading", "Spawned"
}

-- Window state
local windowX = 100
local windowY = 100
local isDragging = false
local dragOffsetX = 0
local dragOffsetY = 0
local titleBarHeight = 30

-- Autocomplete state
local autocompleteText = ""
local autocompleteIndex = 0
local autocompleteOptions = {}
local showingAutocomplete = false

-- Common log filter patterns for autocomplete
local commonLogFilters = {
    "MOD_SYSTEM", "rendererPlus", "player_core_mod", "weapons_core_mod", 
    "combat_effects_mod", "projectiles_mod", "health_damage_mod", "basic_enemies_mod",
    "bear_boss_mod", "blood_effects_mod", "ai_behaviors_mod", "damage_indicators_mod",
    "Error", "Warning", "Failed", "Success", "loaded", "initialized", "GC", "queue"
}

-- Command index for autocomplete (all available commands)
local commandIndex = {
    -- Console commands
    "help", "clear", "exit", "reload", "tp", "save", "load", "boss", "weapon",
    "godmode", "god", "invincible", -- Add godmode aliases
    "teleport", "tp player", "tp to", -- Enhanced teleport
    "logs", "logs off", "logs clear", "logs count", "logs filter", "logs remove filters", "logs gameStart",
    
    -- Log filter autocomplete
    "logs filter MOD_SYSTEM", "logs filter rendererPlus", "logs filter player_core_mod",
    "logs filter weapons_core_mod", "logs filter combat_effects_mod", "logs filter Error",
    "logs filter Warning", "logs filter GC", "logs filter queue",
    
    -- Lua built-ins
    "print", "type", "pairs", "ipairs", "math", "string", "table", "io", "os", "debug",
    
    -- Love2D framework
    "love", "world",
    
    -- Game modules  
    "player", "enemy", "gun", "camera", "map", "var", "fire", "bullet",
    "menu", "mymath", "effects", "mydraw", "shader", "water", "grass", "smoke", "sprite",
    "portal", "crt", "renderer", "snapshot", "blur", "serial", "editor", "multiplayer",
    "vec2", "vec4", "json",
    
    -- Game objects
    "coin_bods", "enemies_bods", "enemy_projectile_bodies", "fire_bodies", "fire_instances",
    "dynamic_draw_list", "map_a", "map_b",
    
    -- Assets
    "coin_image", "coin_quad", "coin_sprite", "enemy_image", "statsFont", "gameFont",
    "fireSpriteImg", "hitmarkerImage",
    
    -- Game state
    "W", "H", "game_area_x", "game_area_y",
    
    -- Useful functions
    "round", "lerp", "checkDestroy", "createAnimation"
}

-- Colors
local backgroundColor = {0.1, 0.1, 0.1, 0.8} -- Dark gray with transparency
local textColor = {0.9, 0.9, 0.9, 1}         -- Light gray
local promptColor = {0.2, 0.8, 0.2, 1}       -- Green for prompts
local errorColor = {0.8, 0.2, 0.2, 1}        -- Red for errors
local outputColor = {0.7, 0.7, 0.7, 1}       -- Medium gray for output

-- Manual color scheme for text parsing
local colorScheme = {
    green = {0.2, 0.8, 0.2, 1},
    yellow = {0.9, 0.9, 0.2, 1},
    cyan = {0.2, 0.9, 0.9, 1},
    blue = {0.3, 0.6, 1.0, 1},
    red = {0.9, 0.3, 0.3, 1},
    white = {0.9, 0.9, 0.9, 1}
}

-- Parse color markup text into segments
local function parseColorText(text)
    local segments = {}
    local pos = 1
    local currentColor = textColor
    
    while pos <= #text do
        local startTag = text:find("{", pos, true)
        if not startTag then
            -- No more tags, add remaining text
            if pos <= #text then
                table.insert(segments, {text = text:sub(pos), color = currentColor})
            end
            break
        end
        
        -- Add text before tag
        if startTag > pos then
            table.insert(segments, {text = text:sub(pos, startTag - 1), color = currentColor})
        end
        
        local endTag = text:find("}", startTag, true)
        if not endTag then
            -- Malformed tag, treat as regular text
            table.insert(segments, {text = text:sub(startTag), color = currentColor})
            break
        end
        
        local tagContent = text:sub(startTag + 1, endTag - 1)
        if tagContent:sub(1, 1) == "/" then
            -- Closing tag, reset to default color
            currentColor = textColor
        elseif colorScheme[tagContent] then
            -- Opening tag with valid color
            currentColor = colorScheme[tagContent]
        end
        
        pos = endTag + 1
    end
    
    return segments
end

-- Get object properties for dynamic inspection
local function getObjectProperties(objName)
    local properties = {}
    local success, obj = pcall(function() return _G[objName] end)
    
    if success and obj and (type(obj) == "table" or type(obj) == "userdata") then
        -- Try to get metatable methods
        local mt = getmetatable(obj)
        if mt and mt.__index then
            if type(mt.__index) == "table" then
                for key, value in pairs(mt.__index) do
                    if type(key) == "string" and type(value) == "function" then
                        table.insert(properties, key)
                    end
                end
            end
        end
        
        -- Get direct table properties
        if type(obj) == "table" then
            for key, value in pairs(obj) do
                if type(key) == "string" then
                    table.insert(properties, key)
                end
            end
        end
    end
    
    table.sort(properties)
    return properties
end

-- Find autocomplete options using simple search
local function findAutocompleteOptions(input)
    local options = {}
    if not input or input == "" then 
        return options 
    end
    
    -- Special handling for log filter commands
    if input:find("^logs filter ") then
        local filterPrefix = input:match("^logs filter (.*)") or ""
        for _, filter in ipairs(commonLogFilters) do
            if filter:lower():find(filterPrefix:lower(), 1, true) then
                table.insert(options, "logs filter " .. filter)
            end
        end
        return options
    end
    
    -- Check for dot notation (object.property)
    local dotPos = input:find("%.")
    if dotPos then
        local objName = input:sub(1, dotPos - 1)
        local propPrefix = input:sub(dotPos + 1)
        local properties = getObjectProperties(objName)
        
        for _, prop in ipairs(properties) do
            if prop:sub(1, #propPrefix):lower() == propPrefix:lower() then
                table.insert(options, objName .. "." .. prop)
            end
        end
        return options
    end
    
    -- Regular command completion
    if not commandIndex or type(commandIndex) ~= "table" then
        return options
    end
    
    local inputLower = input:lower()
    for i = 1, #commandIndex do
        local cmd = commandIndex[i]
        if cmd and type(cmd) == "string" then
            if cmd:sub(1, #inputLower):lower() == inputLower then
                table.insert(options, cmd)
            end
        end
    end
    
    -- Add global variables that match
    for name, value in pairs(_G) do
        if type(name) == "string" and name:sub(1, #inputLower):lower() == inputLower then
            if type(value) == "table" or type(value) == "function" or type(value) == "userdata" then
                table.insert(options, name)
            end
        end
    end
    
    return options
end

-- Update autocomplete based on current input
local function updateAutocomplete()
    if not inputText then
        showingAutocomplete = false
        autocompleteText = ""
        autocompleteIndex = 0
        autocompleteOptions = {}
        return
    end
    
    autocompleteOptions = findAutocompleteOptions(inputText)
    if autocompleteOptions and #autocompleteOptions > 0 then
        showingAutocomplete = true
        autocompleteIndex = 1
        autocompleteText = autocompleteOptions[1] or ""
    else
        showingAutocomplete = false
        autocompleteText = ""
        autocompleteIndex = 0
    end
end

-- Toggle console visibility
function cmdn.toggle()
    isActive = not isActive
    if isActive then
        inputText = ""
        cursorPos = 0
        historyIndex = #history + 1
        showingAutocomplete = false
        autocompleteText = ""
    end
    keyRepeatState = {}
end

-- Check if mouse is over title bar
local function isMouseOverTitleBar(mx, my)
    if not isActive then return false end
    return mx >= windowX and mx <= windowX + consoleWidth and
           my >= windowY and my <= windowY + titleBarHeight
end

-- Check if mouse is over window
local function isMouseOverWindow(mx, my)
    if not isActive then return false end
    return mx >= windowX and mx <= windowX + consoleWidth and
           my >= windowY and my <= windowY + consoleHeight
end

-- Handle mouse press
function cmdn.mousepressed(x, y, button)
    -- First check live log viewer interactions (even if console is closed)
    if cmdn.handleLiveLogMouse(x, y, button) then
        return  -- Live log viewer handled the click
    end
    
    if not isActive then return end
    
    if button == 1 then
        -- Check close button
        local closeButtonSize = titleBarHeight - 6
        local closeButtonX = windowX + consoleWidth - closeButtonSize - 3
        local closeButtonY = windowY + 3
        if x >= closeButtonX and x <= closeButtonX + closeButtonSize and
           y >= closeButtonY and y <= closeButtonY + closeButtonSize then
            cmdn.toggle()
            return
        end
        
        -- Check title bar for dragging
        if isMouseOverTitleBar(x, y) then
            isDragging = true
            dragOffsetX = x - windowX
            dragOffsetY = y - windowY
        end
    end
end

-- Handle mouse release
function cmdn.mousereleased(x, y, button)
    if button == 1 then
        isDragging = false
    end
end

-- Handle mouse movement
function cmdn.mousemoved(x, y, dx, dy)
    if isDragging then
        windowX = x - dragOffsetX
        windowY = y - dragOffsetY
        
        -- Keep window on screen
        local screenW = love.graphics.getWidth()
        local screenH = love.graphics.getHeight()
        windowX = math.max(0, math.min(screenW - consoleWidth, windowX))
        windowY = math.max(0, math.min(screenH - consoleHeight, windowY))
    end
end


-- Key repeat state
local keyRepeatState = {}
local keyRepeatDelay = 0.5  -- Initial delay before repeat starts
local keyRepeatRate = 0.05  -- Time between repeats

-- Initialize the cmdn module
function cmdn.load()
    -- Initialize log capture system first
    cmdn.initializeLogCapture()
    
    -- Auto-enable live log viewer for startup logs if flag file exists
    if love.filesystem.getInfo("cmdn_startup_logs.flag") then
        liveLogsEnabled = true
        cmdn.addOutput("Live log viewer auto-enabled for startup logs", outputColor)
        love.filesystem.remove("cmdn_startup_logs.flag")
    end
    
    -- Try to load the desired font, fallback to default if it fails
    local success, loadedFont = pcall(love.graphics.newFont, "gfx/menu/Px437_IBM_VGA_8x16.ttf", 16)
    if success then
        font = loadedFont
    else
        font = love.graphics.getFont() or love.graphics.newFont(16)
    end
    lineHeight = font:getHeight() + 2
    
    -- Initialize live log viewer font (smaller)
    local liveLogSuccess, liveLogLoadedFont = pcall(love.graphics.newFont, "gfx/menu/Px437_IBM_VGA_8x16.ttf", 10)
    if liveLogSuccess then
        liveLogFont = liveLogLoadedFont
    else
        liveLogFont = love.graphics.newFont(10)
    end
    liveLogLineHeight = liveLogFont:getHeight() + 1
    
    -- Set live log viewer position (bottom-right corner)
    liveLogX = love.graphics.getWidth() - liveLogWidth - 20
    liveLogY = love.graphics.getHeight() - liveLogHeight - 20
    
    -- consoleWidth is now fixed, not screen-dependent
    cmdn.addOutput("{green}=== {yellow}LUA DEBUG CONSOLE{/yellow} ==={/green}", promptColor)
    
    -- Show game version from var.game_version
    if var and var.game_version then
        cmdn.addOutput("{cyan}Game Version: {yellow}" .. var.game_version .. "{/yellow}{/cyan}", outputColor)
    end
    
    cmdn.addOutput("Type {yellow}help{/yellow} for available commands", outputColor)
    cmdn.addOutput("Press {cyan},{/cyan} to toggle console", outputColor)
    cmdn.addOutput("Autocomplete: {cyan}Tab{/cyan} to cycle/accept suggestions", outputColor)
    cmdn.addOutput("Try: {cyan}player.{/cyan} or {cyan}love.{/cyan} for object inspection", outputColor)
    cmdn.addOutput("Use {yellow}logs{/yellow} command to enable live log viewer!", outputColor)
    cmdn.addOutput("", outputColor)
    
    -- Initialize log capture
    cmdn.initializeLogCapture()
end

-- Wrap text to fit within console width
local function wrapText(text, maxWidth)
    local wrappedLines = {}
    local words = {}
    for word in text:gmatch("%S+") do
        table.insert(words, word)
    end
    if #words == 0 then
        return {text}
    end
    local currentLine = ""
    local spaceWidth = font:getWidth(" ")
    for _, word in ipairs(words) do
        local wordWidth = font:getWidth(word)
        local currentLineWidth = font:getWidth(currentLine)
        if currentLine ~= "" and currentLineWidth + spaceWidth + wordWidth > maxWidth then
            table.insert(wrappedLines, currentLine)
            currentLine = word
        else
            if currentLine ~= "" then
                currentLine = currentLine .. " " .. word
            else
                currentLine = word
            end
        end
    end
    if currentLine ~= "" then
        table.insert(wrappedLines, currentLine)
    end
    return wrappedLines
end

-- Add text to output buffer
function cmdn.addOutput(text, color)
    color = color or outputColor
    local textStr = tostring(text)
    
    -- Parse the text for color segments
    local segments = parseColorText(textStr)
    
    table.insert(output, {segments = segments, text = textStr, color = color})
    
    if #output > maxOutputLines * 3 then
        for i = 1, maxOutputLines do
            table.remove(output, 1)
        end
    end
    
    -- Auto-scroll to bottom when new content is added
    local contentHeight = consoleHeight - titleBarHeight - 2 * padding - lineHeight - 10
    local visibleLines = math.floor(contentHeight / lineHeight)
    scrollOffset = math.max(0, #output - visibleLines)
end

-- Execute a Lua cmdn
function cmdn.execute(cmd)
    if cmd == "" then return end
    table.insert(history, cmd)
    if #history > 50 then
        table.remove(history, 1)
    end
    historyIndex = #history + 1
    cmdn.addOutput("{green}> {/green}" .. cmd, promptColor)
    if string.find(cmd, "^help") then
        -- Enhanced help system with categories and specific command help
        local tokens = {}
        for token in cmd:gmatch("%S+") do
            table.insert(tokens, token)
        end
        
        if tokens[2] then
            -- Show help for specific command
            cmdn.showCommandHelp(tokens[2])
        else
            -- Show general help with categories
            cmdn.showHelp()
        end
    elseif cmd == "clear" then
        output = {}
    elseif cmd == "exit" then
        love.event.quit()
    elseif cmd == "reload" then
        love.event.push("quit", "restart")
    elseif string.find(cmd, "logs") or string.find(cmd, "log ") then
        -- Handle live log viewer commands
        local tokens = {}
        for token in cmd:gmatch("%S+") do
            table.insert(tokens, token)
        end
        
        if (tokens[1] == "log" or tokens[1] == "logs") and tokens[2] == "gameStart" then
            -- Persist startup log flag for next run and clear buffer
            love.filesystem.write("cmdn_startup_logs.flag", "1")
            gameLogsBuffer = {}  -- Clear current buffer for fresh start
            cmdn.addOutput("Startup log capture enabled - reloading game with log capture from start...", outputColor)
            -- Trigger game reload with log capture enabled
            love.event.push("quit", "restart")
        elseif tokens[2] == "clear" then
            gameLogsBuffer = {}
            cmdn.addOutput("Game logs cleared", outputColor)
        elseif tokens[2] == "count" then
            cmdn.addOutput("Total logs in buffer: " .. #gameLogsBuffer, outputColor)
        elseif tokens[2] == "filter" then
            local filterPattern = tokens[3] or ""
            if filterPattern == "" then
                logFilter = ""
                cmdn.addOutput("Log filter cleared", outputColor)
            else
                logFilter = filterPattern
                local filtered = cmdn.filterLogs(filterPattern)
                cmdn.addOutput("Log filter set to: '" .. filterPattern .. "' (" .. #filtered .. " matches)", outputColor)
            end
        elseif tokens[2] == "remove" and tokens[3] == "filters" then
            logFilter = ""
            cmdn.addOutput("All log filters removed", outputColor)
        elseif tokens[2] == "export" then
            -- Export logs to a file (optional feature)
            cmdn.addOutput("Log export feature not yet implemented", outputColor)
        elseif tokens[2] == "off" then
            liveLogsEnabled = false
            cmdn.addOutput("Live log viewer disabled", outputColor)
        else
            -- Toggle live log viewer
            liveLogsEnabled = not liveLogsEnabled
            if liveLogsEnabled then
                cmdn.addOutput("Live log viewer enabled (bottom-right corner, semi-transparent)", outputColor)
                cmdn.addOutput("Use 'logs off' to disable, 'logs filter <pattern>' to filter", outputColor)
                cmdn.addOutput("Click pause button to freeze scrolling, click logs to copy to console", outputColor)
            else
                cmdn.addOutput("Live log viewer disabled", outputColor)
            end
        end
    elseif string.find(cmd, "^godmode") or string.find(cmd, "^god") or string.find(cmd, "^invincible") then
        -- Handle godmode command
        local tokens = {}
        for token in cmd:gmatch("%S+") do
            table.insert(tokens, token)
        end
        
        local target = tokens[2] -- Optional player ID or "all"
        if target == "all" then
            -- Toggle godmode for all players
            godmodeEnabled = not godmodeEnabled
            cmdn.addOutput("{yellow}Godmode {/yellow}" .. (godmodeEnabled and "{green}ENABLED{/green}" or "{red}DISABLED{/red}") .. " for all players", outputColor)
            
            -- Store state for all players
            if multiplayerMode and multiplayer and multiplayer.players then
                for id, _ in pairs(multiplayer.players) do
                    playerStates[id] = {godmode = godmodeEnabled}
                end
            end
            playerStates["local"] = {godmode = godmodeEnabled}
        elseif target then
            -- Toggle godmode for specific player
            local playerId = target
            if not playerStates[playerId] then
                playerStates[playerId] = {}
            end
            playerStates[playerId].godmode = not (playerStates[playerId].godmode or false)
            cmdn.addOutput("{yellow}Godmode {/yellow}" .. (playerStates[playerId].godmode and "{green}ENABLED{/green}" or "{red}DISABLED{/red}") .. " for player " .. playerId, outputColor)
        else
            -- Toggle godmode for local player
            if not playerStates["local"] then
                playerStates["local"] = {}
            end
            playerStates["local"].godmode = not (playerStates["local"].godmode or false)
            godmodeEnabled = playerStates["local"].godmode
            cmdn.addOutput("{yellow}Godmode {/yellow}" .. (godmodeEnabled and "{green}ENABLED{/green}" or "{red}DISABLED{/red}") .. " for local player", outputColor)
        end
        
        -- Apply godmode effect
        if player then
            player.godmode = godmodeEnabled
            if godmodeEnabled and player.health then
                player.health = player.max_health or 100
            end
        end
    elseif string.find(cmd, "^tp") or string.find(cmd, "^teleport") then
        -- Enhanced teleport command
        local tokens = {}
        for token in cmd:gmatch("%S+") do
            table.insert(tokens, token)
        end
        
        if tokens[2] == "player" or tokens[2] == "to" then
            -- Teleport to player ID
            local targetId = tokens[3]
            if targetId and multiplayerMode and multiplayer and multiplayer.players and multiplayer.players[targetId] then
                local targetPlayer = multiplayer.players[targetId]
                if targetPlayer.body then
                    local tx, ty = targetPlayer.body:getX(), targetPlayer.body:getY()
                    if player and player.body then
                        player.body:setPosition(tx + 20, ty) -- Offset slightly to avoid overlap
                        cmdn.addOutput("Teleported to player " .. targetId .. " at (" .. math.floor(tx) .. ", " .. math.floor(ty) .. ")", outputColor)
                    end
                else
                    cmdn.addOutput("{red}Error:{/red} Target player has no valid position", errorColor)
                end
            else
                cmdn.addOutput("{red}Error:{/red} Player '" .. (targetId or "nil") .. "' not found", errorColor)
                -- List available players
                if multiplayerMode and multiplayer and multiplayer.players then
                    local playerList = {}
                    for id, _ in pairs(multiplayer.players) do
                        table.insert(playerList, id)
                    end
                    if #playerList > 0 then
                        cmdn.addOutput("Available players: " .. table.concat(playerList, ", "), outputColor)
                    end
                end
            end
        else
            -- Teleport to coordinates
            local tp_x = tonumber(tokens[2])
            local tp_y = tonumber(tokens[3])
            
            if tp_x and tp_y then
                -- Try to teleport using mod API
                local success = false
                
                -- First try through mod system
                if modSystem and modSystem.getLoadedMod then
                    local playerMod = modSystem.getLoadedMod("player_core_mod")
                    if playerMod and playerMod.instance and playerMod.instance.exports then
                        if playerMod.instance.exports.teleportPlayer then
                            playerMod.instance.exports.teleportPlayer(tp_x, tp_y)
                            success = true
                        end
                    end
                end
                
                -- Fallback to player proxy if available
                if not success and player and player.body then
                    local ok = pcall(function()
                        player.body:setPosition(tp_x, tp_y)
                        success = true
                    end)
                    if not ok then
                        success = false
                    end
                end
                
                if success then
                    cmdn.addOutput("Teleported to (" .. tp_x .. ", " .. tp_y .. ")", outputColor)
                else
                    cmdn.addOutput("{red}Error:{/red} Could not teleport - player not found", errorColor)
                end
            else
                cmdn.addOutput("{red}Error:{/red} Invalid teleport syntax. Use: tp <x> <y> or tp player <id>", errorColor)
            end
        end
    elseif cmd == "save" then
        if serial and serial.quickSave then
            serial.quickSave()
        end
    elseif cmd == "load" then
        if serial and serial.quickLoad then
            serial.quickLoad()
        end
    elseif string.find(cmd, "boss") then
        -- Handle boss commands
        local tokens = {}
        for token in cmd:gmatch("%S+") do
            table.insert(tokens, token)
        end
        
        if boss then
            if tokens[2] == "spawn" then
                local x = tonumber(tokens[3]) or (player and player.body and player.body:getX() or 0)
                local y = tonumber(tokens[4]) or (player and player.body and player.body:getY() or 0)
                local result = boss.requestSpawn(x, y)
                if result == "spawn_requested" then
                    cmdn.addOutput("Boss spawn requested (waiting for host)", outputColor)
                else
                    cmdn.addOutput("Boss spawned with ID: " .. result, outputColor)
                end
            elseif tokens[2] == "despawn" then
                if tokens[3] == "all" then
                    boss.despawnAll()
                    cmdn.addOutput("All bosses despawned", outputColor)
                else
                    local id = tonumber(tokens[3])
                    if id and boss.despawn(id) then
                        cmdn.addOutput("Boss " .. id .. " despawned", outputColor)
                    else
                        cmdn.addOutput("{red}Error:{/red} Invalid boss ID", errorColor)
                    end
                end
            elseif tokens[2] == "list" then
                local count = 0
                for id, _ in pairs(boss.bosses) do
                    count = count + 1
                end
                cmdn.addOutput("Active bosses: " .. count, outputColor)
            elseif tokens[2] == "damage" then
                local id = tonumber(tokens[3])
                local damage = tonumber(tokens[4]) or 100
                if id and boss.bosses[id] then
                    boss.damage(id, damage)
                    cmdn.addOutput("Dealt " .. damage .. " damage to boss " .. id, outputColor)
                else
                    cmdn.addOutput("{red}Error:{/red} Invalid boss ID", errorColor)
                end
            else
                cmdn.addOutput("Usage: boss spawn [x] [y] | boss despawn <id|all> | boss list | boss damage <id> [amount]", outputColor)
            end
        else
            cmdn.addOutput("{red}Error:{/red} Boss module not loaded", errorColor)
        end
    elseif string.find(cmd, "^map") or string.find(cmd, "^maps") then
        -- Handle map system commands
        local tokens = {}
        for token in cmd:gmatch("%S+") do
            table.insert(tokens, token)
        end
        
        -- Get map system
        local mapSystem = nil
        if modSystem and modSystem.getLoadedMod then
            local mapMod = modSystem.getLoadedMod("map_system")
            if mapMod and mapMod.instance and mapMod.instance.exports then
                mapSystem = mapMod.instance.exports
            end
        end
        
        if not mapSystem then
            cmdn.addOutput("{red}Error:{/red} Map system not loaded", errorColor)
            return
        end
        
        if tokens[2] == "list" then
            mapSystem.list()
        elseif tokens[2] == "load" then
            local mapId = tokens[3]
            if mapId then
                mapSystem.load(mapId)
            else
                cmdn.addOutput("{red}Error:{/red} Usage: map load <map_id>", errorColor)
            end
        elseif tokens[2] == "reload" then
            mapSystem.reload()
        elseif tokens[2] == "current" then
            mapSystem.current()
        else
            cmdn.addOutput("Map commands: map list | map load <id> | map reload | map current", outputColor)
            cmdn.addOutput("Or use: ms = modSystem.getLoadedMod('map_system').instance.exports", outputColor)
        end
    elseif string.find(cmd, "weapon") then
        -- Handle weapon debug commands
        local tokens = {}
        for token in cmd:gmatch("%S+") do
            table.insert(tokens, token)
        end
        
        if tokens[2] == "debug" then
            -- Toggle weapon debug mode (makes weapons very visible)
            local mod_system = _G.modSystem
            if mod_system and mod_system.getMod then
                local weapons_mod = mod_system.getMod("weapons_core_mod")
                if weapons_mod and weapons_mod.public and weapons_mod.public.toggleDebug then
                    local debug_state = weapons_mod.public.toggleDebug()
                    local state_text = debug_state and "enabled" or "disabled"
                    cmdn.addOutput("Weapon debug mode " .. state_text, outputColor)
                else
                    cmdn.addOutput("{red}Error:{/red} Weapons mod debug not available", errorColor)
                end
            else
                cmdn.addOutput("{red}Error:{/red} Mod system not available", errorColor)
            end
        else
            cmdn.addOutput("Usage: weapon debug", outputColor)
        end
    else
        local success, result = pcall(function()
            local func, err = load("return " .. cmd)
            if func then
                local results = {func()}
                if #results > 0 then
                    for _, v in ipairs(results) do
                        if type(v) == "table" then
                            cmdn.addOutput(cmdn.tableToString(v), outputColor)
                        else
                            cmdn.addOutput(tostring(v), outputColor)
                        end
                    end
                end
            else
                func, err = load(cmd)
                if func then
                    func()
                else
                    error(err)
                end
            end
        end)
        if not success then
            cmdn.addOutput("{red}Error:{/red} " .. tostring(result), errorColor)
        end
    end
    inputText = ""
    cursorPos = 0
end

-- Convert table to string representation
function cmdn.tableToString(t, indent, visited)
    indent = indent or 0
    visited = visited or {}
    if visited[t] then
        return "<circular reference>"
    end
    visited[t] = true
    local str = "{\n"
    local indentStr = string.rep("  ", indent + 1)
    for k, v in pairs(t) do
        str = str .. indentStr .. "[" .. tostring(k) .. "] = "
        if type(v) == "table" and indent < 3 then
            str = str .. cmdn.tableToString(v, indent + 1, visited)
        else
            str = str .. tostring(v)
        end
        str = str .. ",\n"
    end
    str = str .. string.rep("  ", indent) .. "}"
    visited[t] = nil
    return str
end

-- Command help documentation
local commandHelp = {
    -- Map Commands
    map = {
        category = "mod",
        usage = "map [list|load <id>|reload|current]",
        description = "Map system management commands",
        examples = {
            "map list" .. " - Show all available maps",
            "map load starter" .. " - Load the starter map",
            "map reload" .. " - Reload current map",
            "map current" .. " - Show current map"
        },
        aliases = {"maps"}
    },
    -- Admin Commands
    godmode = {
        category = "admin",
        usage = "godmode [player_id|all]",
        description = "Toggle invincibility for you or specified players",
        examples = {
            "godmode" .. " - Toggle godmode for yourself",
            "godmode all" .. " - Toggle godmode for all players",
            "godmode player_2" .. " - Toggle godmode for player_2"
        },
        aliases = {"god", "invincible"}
    },
    
    -- Gameplay Commands
    tp = {
        category = "gameplay",
        usage = "tp <x> <y> | tp player <id>",
        description = "Teleport to coordinates or another player",
        examples = {
            "tp 100 200" .. " - Teleport to coordinates (100, 200)",
            "tp player host" .. " - Teleport to the host player",
            "tp to player_2" .. " - Teleport to player_2"
        },
        aliases = {"teleport"}
    },
    
    save = {
        category = "gameplay",
        usage = "save",
        description = "Quick save the current game state",
        examples = {"save" .. " - Save current game"}
    },
    
    load = {
        category = "gameplay",
        usage = "load",
        description = "Quick load the last saved game state",
        examples = {"load" .. " - Load last saved game"}
    },
    
    boss = {
        category = "gameplay",
        usage = "boss spawn [x] [y] | boss despawn <id|all> | boss list | boss damage <id> [amount]",
        description = "Boss management commands",
        examples = {
            "boss spawn" .. " - Spawn boss at player location",
            "boss spawn 200 300" .. " - Spawn boss at specific location",
            "boss list" .. " - List all active bosses",
            "boss despawn all" .. " - Remove all bosses",
            "boss damage 1 500" .. " - Deal 500 damage to boss ID 1"
        }
    },
    
    weapon = {
        category = "gameplay",
        usage = "weapon debug",
        description = "Toggle weapon debug visualization",
        examples = {"weapon debug" .. " - Toggle weapon debug mode"}
    },
    
    -- Debug Commands
    logs = {
        category = "debug",
        usage = "logs [off|filter|clear|count|gameStart]",
        description = "Control the live log viewer overlay",
        examples = {
            "logs" .. " - Toggle log viewer",
            "logs filter error" .. " - Show only error logs",
            "logs filter MOD_SYSTEM" .. " - Show mod system logs",
            "logs clear" .. " - Clear log buffer",
            "logs gameStart" .. " - Enable startup log capture"
        }
    },
    
    clear = {
        category = "debug",
        usage = "clear",
        description = "Clear the console output",
        examples = {"clear" .. " - Clear all console text"}
    },
    
    reload = {
        category = "debug",
        usage = "reload",
        description = "Restart the game",
        examples = {"reload" .. " - Restart game immediately"}
    },
    
    -- System Commands
    help = {
        category = "system",
        usage = "help [command]",
        description = "Show help for all commands or a specific command",
        examples = {
            "help" .. " - Show all commands by category",
            "help godmode" .. " - Show detailed help for godmode",
            "help tp" .. " - Show detailed help for teleport"
        }
    },
    
    exit = {
        category = "system",
        usage = "exit",
        description = "Exit the game",
        examples = {"exit" .. " - Quit game immediately"}
    }
}

-- Command categories
local commandCategories = {
    admin = {"godmode"},
    gameplay = {"tp", "save", "load", "boss", "weapon"},
    debug = {"logs", "clear", "reload"},
    system = {"help", "exit"},
    mod = {} -- Will be populated by mods
}

-- Show help information
function cmdn.showHelp()
    cmdn.addOutput("{green}=== COMMAND HELP ==={/green}", promptColor)
    cmdn.addOutput("Type {yellow}help <command>{/yellow} for detailed information about a specific command", outputColor)
    cmdn.addOutput("", outputColor)
    
    -- Show commands by category
    local categoryOrder = {"admin", "gameplay", "debug", "system", "mod"}
    local categoryNames = {
        admin = "Admin Commands",
        gameplay = "Gameplay Commands",
        debug = "Debug Commands",
        system = "System Commands",
        mod = "Mod Commands"
    }
    
    for _, category in ipairs(categoryOrder) do
        local commands = commandCategories[category]
        if commands and #commands > 0 then
            cmdn.addOutput("{cyan}" .. categoryNames[category] .. ":{/cyan}", promptColor)
            
            for _, cmdName in ipairs(commands) do
                local cmdInfo = commandHelp[cmdName]
                if cmdInfo then
                    local aliasText = ""
                    if cmdInfo.aliases and #cmdInfo.aliases > 0 then
                        aliasText = " {blue}(" .. table.concat(cmdInfo.aliases, ", ") .. "){/blue}"
                    end
                    cmdn.addOutput(string.format("  {yellow}%-12s{/yellow} - %s%s", cmdName, cmdInfo.description, aliasText), outputColor)
                end
            end
            cmdn.addOutput("", outputColor)
        end
    end
    -- Keyboard shortcuts
    cmdn.addOutput("{green}Keyboard Shortcuts:{/green}", promptColor)
    cmdn.addOutput("  {blue},{/blue}              - Toggle console", outputColor)
    cmdn.addOutput("  {blue}Tab{/blue}            - Cycle/accept autocomplete", outputColor)
    cmdn.addOutput("  {blue}Up/Down{/blue}        - Navigate command history", outputColor)
    cmdn.addOutput("  {blue}Ctrl+C{/blue}         - Copy last output", outputColor)
    cmdn.addOutput("  {blue}PageUp/Down{/blue}    - Scroll output", outputColor)
    cmdn.addOutput("", outputColor)
    
    -- Quick tips
    cmdn.addOutput("{green}Tips:{/green}", promptColor)
    cmdn.addOutput("  • Commands support autocomplete - start typing and press Tab", outputColor)
    cmdn.addOutput("  • Use {cyan}player.{/cyan} or {cyan}love.{/cyan} to explore object properties", outputColor)
    cmdn.addOutput("  • Execute any Lua code directly in the console", outputColor)
    cmdn.addOutput("  • {yellow}Note:{/yellow} All players currently have access to all commands", outputColor)
    cmdn.addOutput("", outputColor)
end

-- Show detailed help for a specific command
function cmdn.showCommandHelp(cmdName)
    -- Check for aliases
    local actualCmd = cmdName
    for cmd, info in pairs(commandHelp) do
        if info.aliases then
            for _, alias in ipairs(info.aliases) do
                if alias == cmdName then
                    actualCmd = cmd
                    break
                end
            end
        end
    end
    
    local cmdInfo = commandHelp[actualCmd]
    if not cmdInfo then
        cmdn.addOutput("{red}Error:{/red} Unknown command '" .. cmdName .. "'. Type 'help' to see all commands.", errorColor)
        return
    end
    
    -- Show detailed help
    cmdn.addOutput("{green}=== HELP: " .. string.upper(actualCmd) .. " ==={/green}", promptColor)
    cmdn.addOutput("", outputColor)
    
    cmdn.addOutput("{cyan}Description:{/cyan} " .. cmdInfo.description, outputColor)
    cmdn.addOutput("", outputColor)
    
    cmdn.addOutput("{cyan}Usage:{/cyan} {yellow}" .. cmdInfo.usage .. "{/yellow}", outputColor)
    cmdn.addOutput("", outputColor)
    
    if cmdInfo.aliases and #cmdInfo.aliases > 0 then
        cmdn.addOutput("{cyan}Aliases:{/cyan} " .. table.concat(cmdInfo.aliases, ", "), outputColor)
        cmdn.addOutput("", outputColor)
    end
    
    if cmdInfo.examples and #cmdInfo.examples > 0 then
        cmdn.addOutput("{cyan}Examples:{/cyan}", outputColor)
        for _, example in ipairs(cmdInfo.examples) do
            cmdn.addOutput("  {yellow}" .. example .. "{/yellow}", outputColor)
        end
        cmdn.addOutput("", outputColor)
    end
    
    cmdn.addOutput("{cyan}Category:{/cyan} " .. cmdInfo.category, outputColor)
    cmdn.addOutput("", outputColor)
end


-- Handle key repeat for continuous key presses
local function handleKeyRepeat(key, dt)
    if not keyRepeatState[key] then return false end
    keyRepeatState[key].timer = keyRepeatState[key].timer + dt
    if not keyRepeatState[key].repeating then
        if keyRepeatState[key].timer >= keyRepeatDelay then
            keyRepeatState[key].repeating = true
            keyRepeatState[key].timer = 0
            return true
        end
    else
        if keyRepeatState[key].timer >= keyRepeatRate then
            keyRepeatState[key].timer = 0
            return true
        end
    end
    return false
end

-- Perform delete/backspace operations
local function performDelete()
    if cursorPos < #inputText then
        inputText = inputText:sub(1, cursorPos) .. inputText:sub(cursorPos + 2)
        updateAutocomplete()
    end
end

local function performBackspace()
    if cursorPos > 0 then
        inputText = inputText:sub(1, cursorPos - 1) .. inputText:sub(cursorPos + 1)
        cursorPos = cursorPos - 1
        updateAutocomplete()
    end
end

-- Check modifier keys
local function isModifierPressed()
    return love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")
end

-- Update function
function cmdn.update(dt)
    if not isActive then return end
    cursorTimer = cursorTimer + dt
    if cursorTimer >= 0.5 then
        cursorVisible = not cursorVisible
        cursorTimer = 0
    end
    if handleKeyRepeat("delete", dt) then performDelete() end
    if handleKeyRepeat("backspace", dt) then performBackspace() end
    
    -- Update scroll limits based on current content
    local contentHeight = consoleHeight - titleBarHeight - 2 * padding - lineHeight - 10
    local visibleLines = math.floor(contentHeight / lineHeight)
    local maxScroll = math.max(0, #output - visibleLines)
    scrollOffset = math.min(maxScroll, math.max(0, scrollOffset))
    
    -- Update live log viewer
    if liveLogsEnabled then
        liveLogLastUpdate = liveLogLastUpdate + dt
        
        -- When paused, only update every interval to prevent constant redraws
        if not liveLogPaused or liveLogLastUpdate >= liveLogUpdateInterval then
            liveLogLastUpdate = 0
            
            -- Calculate visible lines and scroll position
            local filteredLogs = cmdn.filterLogs(logFilter)
            local logAreaHeight = liveLogHeight - 30
            local visibleLines = math.floor(logAreaHeight / liveLogLineHeight)
            
            -- When not paused, always show latest logs
            if not liveLogPaused then
                liveLogScrollOffset = 0
            end
            
            -- Ensure scroll offset stays within bounds
            local maxScroll = math.max(0, #filteredLogs - visibleLines)
            liveLogScrollOffset = math.min(maxScroll, math.max(0, liveLogScrollOffset))
        end
    end
end

-- Handle text input
function cmdn.textinput(text)
    if not isActive then return end
    if text == "," then
        return  -- Ignore comma when console is active
    end
    inputText = inputText:sub(1, cursorPos) .. text .. inputText:sub(cursorPos + 1)
    cursorPos = cursorPos + #text
    updateAutocomplete()
end

-- Handle key presses
function cmdn.keypressed(key)
    -- Toggle console with comma
    if key == "," then
        cmdn.toggle()
        return
    end
    
    if not isActive then return end
    if isModifierPressed() then
        if key == "c" and #output > 0 then
            local lastOutput = output[#output].text
            love.system.setClipboardText(lastOutput)
            cmdn.addOutput("Copied: " .. lastOutput:sub(1, 10) .. "...", outputColor)
        elseif key == "v" then
            local clipboardText = love.system.getClipboardText()
            if clipboardText then
                clipboardText = clipboardText:gsub("[\r\n]+", " ")
                inputText = inputText:sub(1, cursorPos) .. clipboardText .. inputText:sub(cursorPos + 1)
                cursorPos = cursorPos + #clipboardText
            end
        end
        return
    end
    if key == "return" then
        if showingAutocomplete then
            -- First enter: accept autocomplete
            inputText = autocompleteText
            cursorPos = #inputText
            showingAutocomplete = false
            autocompleteText = ""
        else
            -- Second enter or no autocomplete: execute command
            cmdn.execute(inputText)
        end
    elseif key == "tab" then
        -- Cycle through autocomplete options or accept suggestion
        if showingAutocomplete and #autocompleteOptions > 0 then
            if #autocompleteOptions > 1 then
                -- Cycle to next option
                autocompleteIndex = autocompleteIndex + 1
                if autocompleteIndex > #autocompleteOptions then
                    autocompleteIndex = 1
                end
                autocompleteText = autocompleteOptions[autocompleteIndex] or ""
            else
                -- Only one option, accept it
                inputText = autocompleteText
                cursorPos = #inputText
                updateAutocomplete()
            end
        end
    elseif key == "backspace" then
        keyRepeatState.backspace = {timer = 0, repeating = false}
        performBackspace()
    elseif key == "delete" then
        keyRepeatState.delete = {timer = 0, repeating = false}
        performDelete()
    elseif key == "left" then
        cursorPos = math.max(0, cursorPos - 1)
    elseif key == "right" then
        cursorPos = math.min(#inputText, cursorPos + 1)
    elseif key == "up" then
        -- Command history navigation
        if historyIndex > 1 then
            historyIndex = historyIndex - 1
            inputText = history[historyIndex] or ""
            cursorPos = #inputText
            updateAutocomplete()
        end
    elseif key == "down" then
        -- Command history navigation
        if historyIndex <= #history then
            historyIndex = historyIndex + 1
            inputText = history[historyIndex] or ""
            cursorPos = #inputText
            updateAutocomplete()
        end
    elseif key == "pageup" then
        local contentHeight = consoleHeight - titleBarHeight - 2 * padding - lineHeight - 10
        local visibleLines = math.floor(contentHeight / lineHeight)
        scrollOffset = math.max(0, scrollOffset - math.floor(visibleLines / 2))
    elseif key == "pagedown" then
        local contentHeight = consoleHeight - titleBarHeight - 2 * padding - lineHeight - 10
        local visibleLines = math.floor(contentHeight / lineHeight)
        local maxScroll = math.max(0, #output - visibleLines)
        scrollOffset = math.min(maxScroll, scrollOffset + math.floor(visibleLines / 2))
    end
end

-- Handle mouse wheel scrolling
function cmdn.wheelmoved(x, y)
    if not isActive then return end
    local scrollAmount = 3
    local contentHeight = consoleHeight - titleBarHeight - 2 * padding - lineHeight - 10
    local visibleLines = math.floor(contentHeight / lineHeight)
    local maxScroll = math.max(0, #output - visibleLines)
    
    if y > 0 then
        scrollOffset = math.max(0, scrollOffset - scrollAmount)
    elseif y < 0 then
        scrollOffset = math.min(maxScroll, scrollOffset + scrollAmount)
    end
end

function cmdn.keyreleased(key)
    if not isActive then return end
    keyRepeatState[key] = nil
end

-- Draw the console
function cmdn.draw()
    -- Always draw live log viewer if enabled (separate from main console)
    cmdn.drawLiveLogViewer()
    
    if not isActive then return end
    
    local r, g, b, a = love.graphics.getColor()
    local currentFont = love.graphics.getFont()
    love.graphics.setFont(font)
    
    -- Draw main window background
    love.graphics.setColor(0.05, 0.05, 0.05, 0.95)  -- Very dark background
    love.graphics.rectangle("fill", windowX, windowY, consoleWidth, consoleHeight, 8)
    
    -- Draw window border
    love.graphics.setColor(0.2, 0.6, 0.9, 0.8)  -- Blue border
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", windowX, windowY, consoleWidth, consoleHeight, 8)
    
    -- Draw title bar
    local titleBarColor = isDragging and {0.3, 0.7, 1.0, 0.9} or {0.2, 0.6, 0.9, 0.8}
    love.graphics.setColor(titleBarColor)
    love.graphics.rectangle("fill", windowX, windowY, consoleWidth, titleBarHeight, 8)
    
    -- Draw title bar border
    love.graphics.setColor(0.4, 0.8, 1.0, 1.0)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", windowX, windowY, consoleWidth, titleBarHeight, 8)
    
    -- Draw title text
    love.graphics.setColor(1, 1, 1, 1)
    local titleText = "LUA DEBUG CONSOLE X"
    local titleWidth = font:getWidth(titleText)
    love.graphics.print(titleText, windowX + (consoleWidth - titleWidth) / 2, windowY + 6)
    
    -- Draw close button
    love.graphics.setColor(0.8, 0.2, 0.2, 0.8)
    local closeButtonSize = titleBarHeight - 6
    local closeButtonX = windowX + consoleWidth - closeButtonSize - 3
    local closeButtonY = windowY + 3
    love.graphics.rectangle("fill", closeButtonX, closeButtonY, closeButtonSize, closeButtonSize, 3)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("X", closeButtonX + 6, closeButtonY + 4)
    
    -- Calculate content area
    local contentY = windowY + titleBarHeight + padding
    local contentHeight = consoleHeight - titleBarHeight - 2 * padding - lineHeight - 10 -- Reserve space for input
    local visibleLines = math.floor(contentHeight / lineHeight)
    local startLine = math.max(1, #output - visibleLines - scrollOffset + 1)
    local endLine = math.min(#output, startLine + visibleLines - 1)
    
    -- Draw output text
    local y = contentY
    local lineCount = 0
    for i = startLine, endLine do
        local line = output[i]
        if line and lineCount < visibleLines then
            if line.segments then
                -- Draw color segments manually
                local x = windowX + padding
                for _, segment in ipairs(line.segments) do
                    love.graphics.setColor(segment.color)
                    love.graphics.print(segment.text, x, y)
                    x = x + font:getWidth(segment.text)
                end
                y = y + lineHeight
            else
                love.graphics.setColor(line.color or textColor)
                love.graphics.print(line.text, windowX + padding, y)
                y = y + lineHeight
            end
            lineCount = lineCount + 1
        end
    end
    
    -- Draw input area background
    local inputY = windowY + consoleHeight - lineHeight - padding - 5
    love.graphics.setColor(0.1, 0.1, 0.1, 0.8)
    love.graphics.rectangle("fill", windowX + 5, inputY - 3, consoleWidth - 10, lineHeight + 6, 4)
    
    -- Draw input prompt and text
    love.graphics.setColor(promptColor)
    love.graphics.print("> ", windowX + padding, inputY)
    love.graphics.setColor(textColor)
    local promptWidth = font:getWidth("> ")
    love.graphics.print(inputText, windowX + padding + promptWidth, inputY)
    
    -- Draw autocomplete preview (grayed out)
    if showingAutocomplete and autocompleteText ~= "" then
        local previewText = autocompleteText:sub(#inputText + 1)
        if previewText ~= "" then
            local inputWidth = font:getWidth(inputText)
            love.graphics.setColor(0.5, 0.5, 0.5, 0.7)
            love.graphics.print(previewText, windowX + padding + promptWidth + inputWidth, inputY)
        end
    end
    
    -- Draw cursor
    if cursorVisible then
        local cursorX = windowX + padding + promptWidth + font:getWidth(inputText:sub(1, cursorPos))
        love.graphics.setColor(0.3, 0.7, 1.0, 0.8)
        love.graphics.rectangle("fill", cursorX, inputY, 2, lineHeight)
    end
    
    -- Draw autocomplete dropdown (above input area)
    if showingAutocomplete and autocompleteOptions and #autocompleteOptions > 1 then
        local dropdownY = inputY - (lineHeight * #autocompleteOptions) - 10
        local maxWidth = 0
        for _, option in ipairs(autocompleteOptions) do
            local width = font:getWidth(option)
            if width > maxWidth then maxWidth = width end
        end
        maxWidth = maxWidth + 20
        
        -- Background for dropdown
        love.graphics.setColor(0.08, 0.08, 0.08, 0.95)
        love.graphics.rectangle("fill", windowX + padding + promptWidth, dropdownY, maxWidth, lineHeight * #autocompleteOptions, 5)
        
        -- Border
        love.graphics.setColor(0.2, 0.6, 0.9, 0.8)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", windowX + padding + promptWidth, dropdownY, maxWidth, lineHeight * #autocompleteOptions, 5)
        
        -- Options
        for i, option in ipairs(autocompleteOptions) do
            local optionY = dropdownY + (i - 1) * lineHeight
            if i == autocompleteIndex then
                -- Highlight selected option
                love.graphics.setColor(0.2, 0.5, 0.8, 0.7)
                love.graphics.rectangle("fill", windowX + padding + promptWidth + 2, optionY + 1, maxWidth - 4, lineHeight - 2, 3)
            end
            love.graphics.setColor(textColor)
            love.graphics.print(option, windowX + padding + promptWidth + 10, optionY)
        end
    end
    
    -- Draw scroll bar if needed
    if #output > visibleLines then
        local maxScroll = math.max(1, #output - visibleLines)  -- Prevent division by zero
        local scrollBarHeight = math.max(10, (visibleLines / #output) * contentHeight)
        local scrollableArea = contentHeight - scrollBarHeight
        local scrollBarY = contentY + (scrollOffset / maxScroll) * scrollableArea
        love.graphics.setColor(0.3, 0.7, 1.0, 0.6)
        love.graphics.rectangle("fill", windowX + consoleWidth - 8, scrollBarY, 4, scrollBarHeight, 2)
    end
    
    -- Draw live log viewer (separate from main console)
    cmdn.drawLiveLogViewer()
    
    love.graphics.setColor(r, g, b, a)
    love.graphics.setFont(currentFont)
end

-- Draw live log viewer (bottom-right, semi-transparent)
function cmdn.drawLiveLogViewer()
    if not liveLogsEnabled then return end
    
    -- Update position if screen size changed
    local screenW, screenH = love.graphics.getWidth(), love.graphics.getHeight()
    liveLogX = screenW - liveLogWidth - 20
    liveLogY = screenH - liveLogHeight - 20
    
    -- Get filtered logs
    local filteredLogs = cmdn.filterLogs(logFilter)
    local r, g, b, a = love.graphics.getColor()
    local currentFont = love.graphics.getFont()
    if liveLogFont then
        love.graphics.setFont(liveLogFont)
    end
    
    -- Draw background with semi-transparency (more transparent to not interfere with game)
    love.graphics.setColor(0.05, 0.05, 0.05, 0.6)
    love.graphics.rectangle("fill", liveLogX, liveLogY, liveLogWidth, liveLogHeight, 5)
    
    -- Draw border
    love.graphics.setColor(0.2, 0.6, 0.9, 0.6)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", liveLogX, liveLogY, liveLogWidth, liveLogHeight, 5)
    
    -- Draw title bar with pause button
    love.graphics.setColor(0.1, 0.1, 0.1, 0.9)
    love.graphics.rectangle("fill", liveLogX, liveLogY, liveLogWidth, 20, 5)
    
    -- Title text
    love.graphics.setColor(0.8, 0.8, 0.8, 0.9)
    love.graphics.print("Live Logs" .. (logFilter ~= "" and " [" .. logFilter .. "]" or ""), liveLogX + 5, liveLogY + 2)
    
    -- Pause button (wider with text)
    local pauseButtonWidth = 50
    local pauseButtonX = liveLogX + liveLogWidth - pauseButtonWidth - 5
    local pauseButtonY = liveLogY + 2
    local pauseColor = liveLogPaused and {0.9, 0.3, 0.3, 0.8} or {0.3, 0.7, 0.3, 0.8}
    if pauseButtonHover then
        pauseColor[4] = 1.0  -- Full opacity when hovering
    end
    love.graphics.setColor(pauseColor)
    love.graphics.rectangle("fill", pauseButtonX, pauseButtonY, pauseButtonWidth, 16, 2)
    love.graphics.setColor(1, 1, 1, 0.9)
    local buttonText = liveLogPaused and "Resume" or "Pause"
    love.graphics.print(buttonText, pauseButtonX + 8, pauseButtonY + 1)
    
    -- Clear button
    local clearButtonWidth = 60
    local clearButtonX = pauseButtonX - clearButtonWidth - 5
    local clearButtonY = pauseButtonY
    local clearColor = clearButtonHover and {0.9, 0.6, 0.2, 0.8} or {0.7, 0.4, 0.1, 0.8}
    if clearButtonHover then clearColor[4] = 1.0 end
    love.graphics.setColor(clearColor)
    love.graphics.rectangle("fill", clearButtonX, clearButtonY, clearButtonWidth, 16, 2)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.print("Clear", clearButtonX + 10, clearButtonY + 1)
    
    -- Draw logs (latest at bottom, scrolling upward)
    local logStartY = liveLogY + 25
    local logAreaHeight = liveLogHeight - 30
    local visibleLines = math.floor(logAreaHeight / liveLogLineHeight)
    
    -- Calculate which logs to show (latest at bottom)
    -- When not paused, automatically scroll to bottom (latest logs)
    if not liveLogPaused then
        liveLogScrollOffset = 0
    end
    
    local startIndex = math.max(1, #filteredLogs - visibleLines + 1 - liveLogScrollOffset)
    local endIndex = math.min(#filteredLogs - liveLogScrollOffset, startIndex + visibleLines - 1)
    
    -- Draw logs
    for i = startIndex, endIndex do
        if i > 0 and i <= #filteredLogs then
            local log = filteredLogs[i]
            local lineY = logStartY + (i - startIndex) * liveLogLineHeight
            
            -- Highlight selected log
            if selectedLogIndex == i then
                love.graphics.setColor(0.3, 0.3, 0.6, 0.6)
                love.graphics.rectangle("fill", liveLogX + 2, lineY - 1, liveLogWidth - 4, liveLogLineHeight)
            end
            
            -- Get log color based on source/content
            local logColor = cmdn.getLogColor(log.source, log.category, log.message)
            love.graphics.setColor(logColor)
            
            -- Truncate message if too long
            local displayMessage = log.timestamp .. " " .. log.source .. ": " .. log.message
            if liveLogFont and liveLogFont:getWidth(displayMessage) > liveLogWidth - 10 then
                local maxChars = math.floor((liveLogWidth - 10) / liveLogFont:getWidth("W"))
                displayMessage = displayMessage:sub(1, maxChars - 3) .. "..."
            end
            
            love.graphics.print(displayMessage, liveLogX + 5, lineY)
        end
    end
    
    -- Draw scroll indicator if needed
    if #filteredLogs > visibleLines then
        local scrollBarHeight = math.max(5, (visibleLines / #filteredLogs) * logAreaHeight)
        local scrollBarY = logStartY + ((liveLogScrollOffset / (#filteredLogs - visibleLines)) * (logAreaHeight - scrollBarHeight))
        love.graphics.setColor(0.6, 0.6, 0.6, 0.7)
        love.graphics.rectangle("fill", liveLogX + liveLogWidth - 5, scrollBarY, 3, scrollBarHeight, 1)
    end
    
    love.graphics.setColor(r, g, b, a)
    love.graphics.setFont(currentFont)
end

-- Handle mouse interaction with live log viewer
function cmdn.handleLiveLogMouse(x, y, button)
    if not liveLogsEnabled then return false end
    
    -- Check if mouse is over live log viewer
    if x >= liveLogX and x <= liveLogX + liveLogWidth and 
       y >= liveLogY and y <= liveLogY + liveLogHeight then
        
        -- Check pause button (updated coordinates)
        local pauseButtonWidth = 50
        local pauseButtonX = liveLogX + liveLogWidth - pauseButtonWidth - 5
        local pauseButtonY = liveLogY + 2
        if x >= pauseButtonX and x <= pauseButtonX + pauseButtonWidth and 
           y >= pauseButtonY and y <= pauseButtonY + 16 then
            if button == 1 then  -- Left click
                liveLogPaused = not liveLogPaused
                -- When resuming, reset scroll to show latest logs
                if not liveLogPaused then
                    liveLogScrollOffset = 0
                end
                cmdn.addOutput("Live log viewer " .. (liveLogPaused and "paused" or "resumed"), outputColor)
            end
            return true
        end
        
        -- Check log selection
        local logStartY = liveLogY + 25
        if y >= logStartY then
            local filteredLogs = cmdn.filterLogs(logFilter)
            local logAreaHeight = liveLogHeight - 30
            local visibleLines = math.floor(logAreaHeight / liveLogLineHeight)
            local startIndex = math.max(1, #filteredLogs - visibleLines + 1 - liveLogScrollOffset)
            
            local clickedLine = math.floor((y - logStartY) / liveLogLineHeight)
            local logIndex = startIndex + clickedLine
            
            if logIndex > 0 and logIndex <= #filteredLogs then
                if button == 1 then  -- Left click
                    selectedLogIndex = logIndex
                    local selectedLog = filteredLogs[logIndex]
                    -- Print selected log to console for easy copying
                    originalPrint("COPIED LOG: " .. selectedLog.fullMessage)
                    cmdn.addOutput("Log copied to terminal: " .. selectedLog.timestamp .. " " .. selectedLog.source, outputColor)
                end
            end
        end
        
        -- Check clear button
        local clearButtonWidth = 60
        local clearButtonX = pauseButtonX - clearButtonWidth - 5
        local clearButtonY = pauseButtonY
        if x >= clearButtonX and x <= clearButtonX + clearButtonWidth and 
           y >= clearButtonY and y <= clearButtonY + 16 then
            if button == 1 then
                gameLogsBuffer = {}
                liveLogScrollOffset = 0
                selectedLogIndex = -1
                cmdn.addOutput("Live logs cleared", outputColor)
            end
            return true
        end
        
        return true
    end
    
    -- Check if hovering over pause button (updated coordinates)
    local pauseButtonWidth = 50
    local pauseButtonX = liveLogX + liveLogWidth - pauseButtonWidth - 5
    local pauseButtonY = liveLogY + 2
    pauseButtonHover = (x >= pauseButtonX and x <= pauseButtonX + pauseButtonWidth and 
                       y >= pauseButtonY and y <= pauseButtonY + 16)
    
    local clearButtonWidth = 60
    local clearButtonX = pauseButtonX - clearButtonWidth - 5
    clearButtonHover = (x >= clearButtonX and x <= clearButtonX + clearButtonWidth and 
                        y >= pauseButtonY and y <= pauseButtonY + 16)
    
    return false
end

-- Get color for live log entry based on category and source
function cmdn.getLiveLogColor(log)
    if log.category == "error" then
        return {0.9, 0.3, 0.3, 1}  -- Red for errors
    elseif log.category == "system" then
        return {0.3, 0.6, 1.0, 1}  -- Blue for system
    elseif log.category == "mod" then
        return {0.2, 0.8, 0.2, 1}  -- Green for mods
    elseif log.category == "renderer" then
        return {0.2, 0.9, 0.9, 1}  -- Cyan for renderer
    elseif log.category == "gc" then
        return {0.9, 0.9, 0.2, 1}  -- Yellow for GC
    elseif log.category == "dev" then
        return {0.8, 0.6, 0.2, 1}  -- Orange for dev tools
    else
        return {0.8, 0.8, 0.8, 1}  -- White/gray for others
    end
end

-- Check if console is active
function cmdn.isActive()
    return isActive
end

-- Expose global access
function cmdn.setGlobal(name, value)
    _G[name] = value
end

-- Add game object references
function cmdn.setGameReferences(refs)
    for name, value in pairs(refs) do
        _G[name] = value
    end
end

-- Check if a player has godmode enabled
function cmdn.isGodmodeEnabled(playerId)
    if playerId then
        return playerStates[playerId] and playerStates[playerId].godmode or false
    else
        return godmodeEnabled
    end
end

-- Register a mod command (for mod integration)
function cmdn.registerModCommand(cmdName, cmdInfo)
    if not cmdName or not cmdInfo then return end
    
    -- Add to command help
    commandHelp[cmdName] = cmdInfo
    
    -- Add to mod category
    if not commandCategories.mod then
        commandCategories.mod = {}
    end
    table.insert(commandCategories.mod, cmdName)
    
    -- Add to autocomplete index
    table.insert(commandIndex, cmdName)
    if cmdInfo.aliases then
        for _, alias in ipairs(cmdInfo.aliases) do
            table.insert(commandIndex, alias)
        end
    end
end

-- Enhanced log capture functionality with dynamic source detection
function cmdn.initializeLogCapture()
    -- Override the global print function to capture all logs with source detection
    print = function(...)
        -- If paused, skip capturing and just call original print
        if liveLogPaused and liveLogsEnabled then
            return originalPrint(...)
        end
        local args = {...}
        local logMessage = ""
        for i, arg in ipairs(args) do
            if i > 1 then logMessage = logMessage .. "\t" end
            logMessage = logMessage .. tostring(arg)
        end
        
        -- Detect source and category dynamically
        local source, category = detectLogSource(logMessage)
        
        -- Add timestamp
        local timestamp = os.date("[%H:%M:%S]")
        local fullLogMessage = timestamp .. " " .. logMessage
        
        -- Store the current number of logs before adding new one
        local prevLogCount = #gameLogsBuffer
        
        -- Store in our buffer with enhanced metadata
        table.insert(gameLogsBuffer, {
            timestamp = timestamp,
            message = logMessage,
            fullMessage = fullLogMessage,
            source = source,
            category = category,
            rawMessage = logMessage,
            time = love.timer.getTime()  -- Add timestamp for sorting
        })
        
        -- Limit buffer size
        if #gameLogsBuffer > maxLogLines then
            table.remove(gameLogsBuffer, 1)
        end
        
        -- When paused, adjust scroll offset to maintain view position as new logs come in
        if liveLogPaused and liveLogsEnabled then
            -- Only adjust if we weren't at the bottom already
            if liveLogScrollOffset > 0 then
                -- Calculate how many visible lines we have
                local filteredLogs = cmdn.filterLogs(logFilter)
                local logAreaHeight = liveLogHeight - 30
                local visibleLines = math.floor(logAreaHeight / liveLogLineHeight)
                
                -- If new logs were added and we have room to scroll, maintain position
                if #filteredLogs > prevLogCount then
                    liveLogScrollOffset = liveLogScrollOffset + (#filteredLogs - prevLogCount)
                end
            end
        end
        
        -- Call original print so logs still appear in terminal
        originalPrint(...)
    end
end

-- Initialize live log viewer positioning
function cmdn.initializeLiveLogViewer()
    liveLogX = love.graphics.getWidth() - liveLogWidth - 10
    liveLogY = love.graphics.getHeight() - liveLogHeight - 10
end

-- Get color for log source/category
function cmdn.getLogColor(source, category, message)
    if source == "MOD_SYSTEM" then
        return {0.3, 0.6, 1.0, 0.7}  -- Blue, semi-transparent
    elseif source:find("MOD:") then
        return {0.2, 0.8, 0.2, 0.7}  -- Green, semi-transparent
    elseif source == "rendererPlus" then
        return {0.2, 0.9, 0.9, 0.7}  -- Cyan, semi-transparent
    elseif message:find("Error") or message:find("Failed") or message:find("Warning") then
        return {0.9, 0.3, 0.3, 0.8}  -- Red, more opaque for errors
    elseif message:find("GC collected") then
        return {0.9, 0.9, 0.2, 0.6}  -- Yellow, semi-transparent
    elseif message:find("Success") or message:find("complete") or message:find("loaded") then
        return {0.2, 0.8, 0.2, 0.7}  -- Green, semi-transparent
    else
        return {0.9, 0.9, 0.9, 0.6}  -- White, semi-transparent
    end
end

-- Filter logs based on pattern
function cmdn.filterLogs(pattern)
    if not pattern or pattern == "" then
        return gameLogsBuffer
    end
    
    local filtered = {}
    local lowerPattern = pattern:lower()
    
    for _, log in ipairs(gameLogsBuffer) do
        -- Check message, source, and category for matches
        if log.message:lower():find(lowerPattern, 1, true) or 
           log.source:lower():find(lowerPattern, 1, true) or
           log.category:lower():find(lowerPattern, 1, true) then
            table.insert(filtered, log)
        end
    end
    
    -- Sort by timestamp to ensure consistent order
    table.sort(filtered, function(a, b) return a.time < b.time end)
    
    return filtered
end

-- Display logs in console
function cmdn.displayLogs(count, filter)
    count = count or 50  -- Default to last 50 logs
    local logs = cmdn.filterLogs(filter)
    
    if #logs == 0 then
        cmdn.addOutput("{yellow}No logs found" .. (filter and " matching '" .. filter .. "'" or "") .. "{/yellow}", outputColor)
        return
    end
    
    local startIndex = math.max(1, #logs - count + 1)
    cmdn.addOutput("{cyan}=== GAME LOGS" .. (filter and " (filtered: '" .. filter .. "')" or "") .. " ==={/cyan}", promptColor)
    
    for i = startIndex, #logs do
        local log = logs[i]
        local coloredMessage = cmdn.colorizeLogMessage(log.fullMessage)
        cmdn.addOutput(coloredMessage, outputColor)
    end
    
    cmdn.addOutput("{cyan}=== END LOGS (showing " .. (#logs - startIndex + 1) .. " of " .. #logs .. ") ==={/cyan}", promptColor)
end

-- Colorize log messages based on content
function cmdn.colorizeLogMessage(message)
    -- Color based on log prefixes and keywords
    if message:find("%[MOD_SYSTEM%]") then
        return "{blue}" .. message .. "{/blue}"
    elseif message:find("%[MOD:") then
        return "{green}" .. message .. "{/green}"
    elseif message:find("%[rendererPlus%]") then
        return "{cyan}" .. message .. "{/cyan}"
    elseif message:find("Error") or message:find("Failed") or message:find("Warning") then
        return "{red}" .. message .. "{/red}"
    elseif message:find("Success") or message:find("complete") or message:find("loaded") then
        return "{green}" .. message .. "{/green}"
    elseif message:find("GC collected") then
        return "{yellow}" .. message .. "{/yellow}"
    else
        return message
    end
end

return cmdn