-- cmdn.lua - In-game cmdn line for LÖVE 2D
local cmdn = {}
local sandbox = require("security.sandbox")
local p2p_permissions = require("security.p2p_permissions")

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

-- Command index for autocomplete (all available commands)
local commandIndex = {
    -- Console commands
    "help", "clear", "exit", "reload", "tp", "save", "load", "editor",
    
    -- Lua built-ins
    "print", "type", "pairs", "ipairs", "math", "string", "table", "io", "os", "debug",
    
    -- Love2D framework
    "love", "world",
    
    -- Game modules  
    "player", "enemy", "gun", "camera", "map", "var", "fire", "bullet",
    "menu", "mymath", "effects", "mydraw", "shader", "water", "grass", "smoke", "sprite",
    "portal", "crt", "renderer", "snapshot", "blur", "serial", "editor", "multiplayer",
    "vec2", "vec4", "json",
    
    -- Editor commands  
    "editor.enable", "editor.disable", "editor.status",
    
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
    local exactMatches = {}
    local partialMatches = {}
    
    if not input or input == "" then 
        return options 
    end
    
    -- Check for dot notation (object.property)
    local dotPos = input:find("%.")
    if dotPos then
        local objName = input:sub(1, dotPos - 1)
        local propPrefix = input:sub(dotPos + 1)
        
        -- First, check predefined commands for exact matches
        local inputLower = input:lower()
        for i = 1, #commandIndex do
            local cmd = commandIndex[i]
            if cmd and type(cmd) == "string" then
                if cmd:lower() == inputLower then
                    table.insert(exactMatches, cmd)
                elseif cmd:sub(1, #inputLower):lower() == inputLower then
                    table.insert(partialMatches, cmd)
                end
            end
        end
        
        -- Then add properties from the object
        local properties = getObjectProperties(objName)
        for _, prop in ipairs(properties) do
            local fullCommand = objName .. "." .. prop
            if fullCommand:lower() == inputLower then
                table.insert(exactMatches, fullCommand)
            elseif prop:sub(1, #propPrefix):lower() == propPrefix:lower() then
                table.insert(partialMatches, fullCommand)
            end
        end
        
        -- Combine results: exact matches first, then partial matches
        for _, match in ipairs(exactMatches) do
            table.insert(options, match)
        end
        for _, match in ipairs(partialMatches) do
            table.insert(options, match)
        end
        
        return options
    end
    
    -- Regular command completion
    if not commandIndex or type(commandIndex) ~= "table" then
        return options
    end
    
    local inputLower = input:lower()
    
    -- First pass: exact matches from commandIndex
    for i = 1, #commandIndex do
        local cmd = commandIndex[i]
        if cmd and type(cmd) == "string" then
            if cmd:lower() == inputLower then
                table.insert(exactMatches, cmd)
            end
        end
    end
    
    -- Second pass: partial matches from commandIndex
    for i = 1, #commandIndex do
        local cmd = commandIndex[i]
        if cmd and type(cmd) == "string" then
            if cmd:sub(1, #inputLower):lower() == inputLower and cmd:lower() ~= inputLower then
                table.insert(partialMatches, cmd)
            end
        end
    end
    
    -- Third pass: global variables (always partial since they're dynamic)
    for name, value in pairs(_G) do
        if type(name) == "string" and name:sub(1, #inputLower):lower() == inputLower then
            if type(value) == "table" or type(value) == "function" or type(value) == "userdata" then
                table.insert(partialMatches, name)
            end
        end
    end
    
    -- Combine results: exact matches first, then partial matches
    for _, match in ipairs(exactMatches) do
        table.insert(options, match)
    end
    for _, match in ipairs(partialMatches) do
        table.insert(options, match)
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

-- Track if sandbox is fully initialized
local sandbox_fully_initialized = false

-- Ensure sandbox is fully initialized when console is first opened
local function ensureSandboxInitialized()
    if not sandbox_fully_initialized then
        sandbox.init()
        sandbox_fully_initialized = true
    end
end

-- Toggle console visibility
function cmdn.toggle()
    isActive = not isActive
    if isActive then
        -- Initialize sandbox security when console is first opened
        ensureSandboxInitialized()
        
        inputText = ""
        cursorPos = 0
        historyIndex = #history + 1
        showingAutocomplete = false
        autocompleteText = ""
    end
    keyRepeatState = {}  -- Clear key repeat state
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
    -- Only do basic sandbox initialization during game load
    sandbox.initBasic()
    
    -- Try to load the desired font, fallback to default if it fails
    local success, loadedFont = pcall(love.graphics.newFont, "gfx/menu/Px437_IBM_VGA_8x16.ttf", 16)
    if success then
        font = loadedFont
    else
        font = love.graphics.getFont() or love.graphics.newFont(16)
    end
    lineHeight = font:getHeight() + 2
    -- consoleWidth is now fixed, not screen-dependent
    cmdn.addOutput("{green}=== LUA DEBUG CONSOLE X ==={/green}", promptColor)
    cmdn.addOutput("Sandbox: {red}DISABLED{/red} - Full system access", outputColor)
    cmdn.addOutput("Type {yellow}help{/yellow} for available commands", outputColor)
    cmdn.addOutput("Press {cyan},{/cyan} to toggle console", outputColor)
    
    cmdn.addOutput("Autocomplete: {cyan}Tab{/cyan} to cycle/accept suggestions", outputColor)
    cmdn.addOutput("", outputColor)
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
    if cmd == "help" then
        cmdn.showHelp()
    elseif cmd == "clear" then
        output = {}
    elseif cmd == "editor" then
        cmdn.showEditorPrompt()
    elseif cmd == "editor.enable" then
        if _G.editor then
            _G.editor.setEnabled(true)
            cmdn.addOutput("{green}✓ Map editor {yellow}ENABLED{/yellow}. Click objects to select and move them.{/green}", outputColor)
            cmdn.addOutput("Use {cyan}1{/cyan}, {cyan}2{/cyan}, {cyan}3{/cyan} to switch modes. {cyan}RMB{/cyan} to delete objects.", outputColor)
        else
            cmdn.addOutput("{red}✗ Editor module not available.{/red}", errorColor)
        end
    elseif cmd == "editor.disable" then
        if _G.editor then
            _G.editor.setEnabled(false)
            cmdn.addOutput("{yellow}✓ Map editor {red}DISABLED{/red}. Objects are now protected from editing.{/yellow}", outputColor)
        else
            cmdn.addOutput("{red}✗ Editor module not available.{/red}", errorColor)
        end
    elseif cmd == "editor.status" then
        if _G.editor then
            local status = _G.editor.isEnabled() and "{green}ENABLED{/green}" or "{red}DISABLED{/red}"
            local mode = _G.editor.isEnabled() and _G.editor.getMode() or "N/A"
            cmdn.addOutput("{cyan}Map Editor Status: " .. status .. "{/cyan}", outputColor)
            cmdn.addOutput("{cyan}Current Mode: {yellow}" .. mode .. "{/yellow}{/cyan}", outputColor)
        else
            cmdn.addOutput("{red}✗ Editor module not available.{/red}", errorColor)
        end
    elseif cmd == "security.level" then
        local current_level = sandbox.getPermissionLevel()
        local level_names = {"Guest", "Player", "Admin", "Developer"}
        cmdn.addOutput("{cyan}Current Security Level: {yellow}" .. current_level .. " (" .. (level_names[current_level] or "Unknown") .. "){/yellow}{/cyan}", outputColor)
    elseif cmd:match("^security%.setlevel%s+%d+$") then
        local level = tonumber(cmd:match("%d+"))
        if level and level >= 1 and level <= 4 then
            sandbox.setPermissionLevel(level)
            local level_names = {"Guest", "Player", "Admin", "Developer"}
            cmdn.addOutput("{green}Security level set to: {yellow}" .. level .. " (" .. (level_names[level] or "Unknown") .. "){/yellow}{/green}", outputColor)
        else
            cmdn.addOutput("{red}Invalid security level. Use 1-4{/red}", errorColor)
        end
    elseif cmd:match("^perms%.") then
        -- Handle P2P permission commands
        local my_player_id = (_G.var and _G.var.multiplayer) or 1
        local success, output = p2p_permissions.handleConsoleCommand(cmd, my_player_id)
        
        if success and output then
            for _, line in ipairs(output) do
                cmdn.addOutput(line, outputColor)
            end
        elseif not success and output then
            for _, line in ipairs(output) do
                cmdn.addOutput(line, errorColor)
            end
        end
    elseif cmd:match("^tp%s+") then
        -- Handle teleport command directly (bypass sandbox)
        local x_str, y_str = cmd:match("^tp%s+([%d.-]+)%s+([%d.-]+)")
        if x_str and y_str then
            local x = tonumber(x_str)
            local y = tonumber(y_str)
            if x and y and _G.player and _G.player.body then
                _G.player.body:setPosition(x, y)
                cmdn.addOutput("{green}✓ Teleported to ({yellow}" .. x .. "{/yellow}, {yellow}" .. y .. "{/yellow}){/green}", outputColor)
            else
                cmdn.addOutput("{red}✗ Invalid coordinates or player not available{/red}", errorColor)
            end
        else
            cmdn.addOutput("{red}✗ Usage: tp <x> <y>{/red}", errorColor)
        end
    elseif cmd == "god" then
        -- Handle god mode toggle directly (bypass sandbox)
        if _G.player then
            _G.player.god = not _G.player.god
            local status = _G.player.god and "{green}ENABLED{/green}" or "{red}DISABLED{/red}"
            cmdn.addOutput("{yellow}✓ God mode " .. status .. "{/yellow}", outputColor)
        else
            cmdn.addOutput("{red}✗ Player not available{/red}", errorColor)
        end
    elseif cmd == "exit" then
        -- Handle exit command directly (bypass sandbox)
        cmdn.addOutput("{red}Exiting game...{/red}", outputColor)
        love.event.quit()
    elseif cmd == "reload" then
        -- Handle reload command directly (bypass sandbox)
        cmdn.addOutput("{yellow}Reloading game...{/yellow}", outputColor)
        love.event.push("quit", "restart")
    elseif cmd == "cont" or cmd == "continue" then
        -- Handle continue command (close console)
        cmdn.addOutput("{green}Continuing game...{/green}", outputColor)
        cmdn.toggle()
    elseif cmd == "save" then
        -- Handle save command directly (bypass sandbox)
        if _G.serial and _G.serial.quickSave then
            _G.serial.quickSave()
            cmdn.addOutput("{green}✓ Game saved{/green}", outputColor)
        else
            cmdn.addOutput("{red}✗ Save system not available{/red}", errorColor)
        end
    elseif cmd == "load" then
        -- Handle load command directly (bypass sandbox)
        if _G.serial and _G.serial.quickLoad then
            _G.serial.quickLoad()
            cmdn.addOutput("{green}✓ Game loaded{/green}", outputColor)
        else
            cmdn.addOutput("{red}✗ Load system not available{/red}", errorColor)
        end
    else
        -- Validate code first
        local valid, errors = sandbox.validateCode(cmd)
        if not valid then
            cmdn.addOutput("{red}Security Error:{/red}", errorColor)
            for _, error_msg in ipairs(errors) do
                cmdn.addOutput("  " .. error_msg, errorColor)
            end
            return
        end
        
        -- Execute with sandbox security
        local permission_level = sandbox.getPermissionLevel()
        local success, result = sandbox.executeCode(cmd, permission_level)
        
        if success then
            if result ~= nil then
                if type(result) == "table" then
                    cmdn.addOutput(cmdn.tableToString(result), outputColor)
                else
                    cmdn.addOutput(tostring(result), outputColor)
                end
            end
        else
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

-- Show help information
function cmdn.showHelp()
    cmdn.addOutput("{green}Available cmdns:{/green}", promptColor)
    cmdn.addOutput("  {yellow}help{/yellow}          - Show this help", outputColor)
    cmdn.addOutput("  {yellow}clear{/yellow}         - Clear console output", outputColor)
    cmdn.addOutput("  {yellow}tp x y{/yellow}        - Teleport player to coordinates", outputColor)
    cmdn.addOutput("  {yellow}god{/yellow}           - Toggle invincibility (for testing)", outputColor)
    cmdn.addOutput("  {yellow}exit{/yellow}          - Quit game", outputColor)
    cmdn.addOutput("  {yellow}reload{/yellow}        - Reload/restart game", outputColor)
    cmdn.addOutput("  {yellow}cont/continue{/yellow} - Close console and continue", outputColor)
    cmdn.addOutput("  {yellow}save{/yellow}          - Quick save game", outputColor)
    cmdn.addOutput("  {yellow}load{/yellow}          - Quick load game", outputColor)
    cmdn.addOutput("  {cyan}player.body:setPosition(x, y){/cyan} - Teleport player", outputColor)
    cmdn.addOutput("  {cyan}serial.quickSave(){/cyan}        - Quick save", outputColor)
    cmdn.addOutput("  {cyan}serial.quickLoad(){/cyan}        - Quick load", outputColor)
    cmdn.addOutput("  {cyan}love.event.quit(){/cyan}         - Quit game", outputColor)
    cmdn.addOutput("  {cyan}border.create(world, w, h){/cyan} - Create map border", outputColor)
    cmdn.addOutput("  {yellow}editor{/yellow}        - Map editor interface", outputColor)
    cmdn.addOutput("", outputColor)
    cmdn.addOutput("{green}Security Commands:{/green}", promptColor)
    cmdn.addOutput("  {yellow}security.level{/yellow}     - Show current permission level", outputColor)
    cmdn.addOutput("  {yellow}security.setlevel N{/yellow} - Set permission level (1-4)", outputColor)
    cmdn.addOutput("    {cyan}1=Guest, 2=Player, 3=Admin, 4=Developer{/cyan}", outputColor)
    cmdn.addOutput("", outputColor)
    cmdn.addOutput("{green}Multiplayer Permissions (Host Only):{/green}", promptColor)
    cmdn.addOutput("  {yellow}perms.list{/yellow}         - List all player permissions", outputColor)
    cmdn.addOutput("  {yellow}perms.me{/yellow}           - Show your permission level", outputColor)
    cmdn.addOutput("  {yellow}perms.grant ID LEVEL{/yellow} - Grant permission to player", outputColor)
    cmdn.addOutput("    {cyan}Example: perms.grant 2 3{/cyan} (give Player 2 Admin level)", outputColor)
    cmdn.addOutput("", outputColor)
    cmdn.addOutput("{green}Lua expressions/statements:{/green}", promptColor)
    cmdn.addOutput("  {cyan}print(value){/cyan}           - Print value", outputColor)
    cmdn.addOutput("  {cyan}player.x = 100{/cyan}         - Set variables", outputColor)
    cmdn.addOutput("  {cyan}love.graphics.getWidth(){/cyan} - Call functions", outputColor)
    cmdn.addOutput("", outputColor)
    cmdn.addOutput("{green}Keyboard shortcuts:{/green}", promptColor)
    cmdn.addOutput("  {blue},{/blue} - Toggle console", outputColor)
    cmdn.addOutput("  {blue}Tab{/blue} - Cycle/accept autocomplete suggestions", outputColor)
    cmdn.addOutput("  {blue}Up/Down{/blue} - Navigate command history", outputColor)
    cmdn.addOutput("  {blue}Enter{/blue} - Accept autocomplete or execute command", outputColor)
    cmdn.addOutput("  {blue}Ctrl+C/Cmd+C{/blue} - Copy last output", outputColor)
    cmdn.addOutput("  {blue}Ctrl+V/Cmd+V{/blue} - Paste from clipboard", outputColor)
    cmdn.addOutput("  {blue}PageUp/PageDown{/blue} - Scroll output", outputColor)
    cmdn.addOutput("  {blue}Mouse wheel{/blue} - Scroll output", outputColor)
    cmdn.addOutput("", outputColor)
end

-- Show editor prompt with terminal-style interface
function cmdn.showEditorPrompt()
    cmdn.addOutput("", outputColor)
    cmdn.addOutput("{cyan}┌─────────────────────────────────────────┐{/cyan}", outputColor)
    cmdn.addOutput("{cyan}│{/cyan}           {yellow}MAP EDITOR INTERFACE{/yellow}           {cyan}│{/cyan}", outputColor)
    cmdn.addOutput("{cyan}├─────────────────────────────────────────┤{/cyan}", outputColor)
    
    local editorStatus = (_G.editor and _G.editor.isEnabled()) and "{green}ENABLED{/green}" or "{red}DISABLED{/red}"
    cmdn.addOutput("{cyan}│{/cyan} Status: " .. editorStatus .. "                        {cyan}│{/cyan}", outputColor)
    cmdn.addOutput("{cyan}│{/cyan}                                         {cyan}│{/cyan}", outputColor)
    cmdn.addOutput("{cyan}│{/cyan} {white}Commands:{/white}                             {cyan}│{/cyan}", outputColor)
    cmdn.addOutput("{cyan}│{/cyan}   {yellow}editor.enable(){/yellow}  - Enable editor       {cyan}│{/cyan}", outputColor)
    cmdn.addOutput("{cyan}│{/cyan}   {yellow}editor.disable(){/yellow} - Disable editor      {cyan}│{/cyan}", outputColor)
    cmdn.addOutput("{cyan}│{/cyan}   {yellow}editor.status(){/yellow}  - Show current status {cyan}│{/cyan}", outputColor)
    cmdn.addOutput("{cyan}│{/cyan}                                         {cyan}│{/cyan}", outputColor)
    cmdn.addOutput("{cyan}│{/cyan} {white}When enabled:{/white}                        {cyan}│{/cyan}", outputColor)
    cmdn.addOutput("{cyan}│{/cyan}   {blue}1{/blue} - Select/move mode                {cyan}│{/cyan}", outputColor)
    cmdn.addOutput("{cyan}│{/cyan}   {blue}2{/blue} - Create arch mode               {cyan}│{/cyan}", outputColor)
    cmdn.addOutput("{cyan}│{/cyan}   {blue}3{/blue} - Create tree mode               {cyan}│{/cyan}", outputColor)
    cmdn.addOutput("{cyan}│{/cyan}   {blue}RMB{/blue} - Delete selected object        {cyan}│{/cyan}", outputColor)
    cmdn.addOutput("{cyan}│{/cyan}   {blue}ESC{/blue} - Clear selection               {cyan}│{/cyan}", outputColor)
    cmdn.addOutput("{cyan}└─────────────────────────────────────────┘{/cyan}", outputColor)
    cmdn.addOutput("", outputColor)
    
    if _G.editor and _G.editor.isEnabled() then
        cmdn.addOutput("{green}Editor is currently {yellow}ACTIVE{/yellow}. Click objects to select and move them.{/green}", outputColor)
    else
        cmdn.addOutput("{yellow}Editor is currently {red}INACTIVE{/red}. Use {cyan}editor.enable(){/cyan} to start editing.{/yellow}", outputColor)
    end
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
            -- Check if the current input is an exact match for any command
            local isExactMatch = false
            for _, option in ipairs(autocompleteOptions) do
                if option:lower() == inputText:lower() then
                    isExactMatch = true
                    break
                end
            end
            
            if isExactMatch then
                -- Execute directly if it's an exact match
                cmdn.execute(inputText)
            else
                -- Accept autocomplete suggestion
                inputText = autocompleteText
                cursorPos = #inputText
                showingAutocomplete = false
                autocompleteText = ""
            end
        else
            -- No autocomplete: execute command
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
function cmdn.wheelmoved(_, y)
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
    
    love.graphics.setColor(r, g, b, a)
    love.graphics.setFont(currentFont)
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

return cmdn