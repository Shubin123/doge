-- command.lua - The in-game console: one draggable window that runs console
-- commands (help, tp, boss ...; see ui/commandHints.lua) or any Lua.
-- "/" or "," opens it; Escape or its X closes it. While it's open it takes
-- every key, so typing doesn't also zoom, fire or open the menu.
--
-- It also owns command blocks: in god mode every Lua line that runs drops a
-- block where you stand, and clicking a block runs its line again. Blocks are
-- physics objects, shared over the network and kept in saves.
local command = {}

-- Console state
local isActive = false
local swallowText = nil -- the key that opened the console, not to be typed
local inputText = ""
local cursorPos = 0
local cursorTimer = 0
local cursorVisible = true
local history = {}
local historyIndex = 0
local output = {}
local maxOutputLines = 20
local scrollOffset = 0 -- lines scrolled up from the newest
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

-- Key repeat state
local keyRepeatState = {}
local keyRepeatDelay = 0.5 -- Initial delay before repeat starts
local keyRepeatRate = 0.05 -- Time between repeats

-- Command blocks
local command_blocks = {}
local next_block_id = 1
local command_block_instance = nil

local block = require("game.block")
local hints = require("ui.commandHints")

-- Autocomplete state
local autocompleteText = ""
local autocompleteIndex = 0
local autocompleteOptions = {}
local showingAutocomplete = false
local commandHintItems = {} -- hints.match() for the current input

-- Names to complete besides the console commands and whatever's in _G
local commandIndex = {
    -- Lua built-ins
    "print", "type", "pairs", "ipairs", "math", "string", "table", "io", "os", "debug",

    -- Love2D framework
    "love", "world",

    -- Game modules
    "player", "enemy", "gun", "camera", "map", "var", "fire", "bullet",
    "menu", "mymath", "effects", "mydraw", "shader", "grass", "smoke", "sprite",
    "portal", "crt", "renderer", "snapshot", "blur", "serial", "editor", "multiplayer",
    "vec2", "vec4", "json",

    -- Game objects
    "coin_bods", "enemies_bods", "enemy_projectile_bodies", "fire_bodies", "fire_instances",
    "dynamic_draw_list", "map_a", "map_b",

    -- Assets
    "xp", "enemy_image", "statsFont", "gameFont",
    "fireSpriteImg", "hitmarkerImage",

    -- Game state
    "W", "H", "game_area_x", "game_area_y",

    -- Useful functions
    "round", "lerp", "checkDestroy", "createAnimation"
}

-- Colors
local textColor = { 0.9, 0.9, 0.9, 1 }  -- Light gray
local promptColor = { 0.2, 0.8, 0.2, 1 } -- Green for prompts
local errorColor = { 0.8, 0.2, 0.2, 1 }  -- Red for errors
local outputColor = { 0.7, 0.7, 0.7, 1 } -- Medium gray for output

-- Manual color scheme for text parsing
local colorScheme = {
    green = { 0.2, 0.8, 0.2, 1 },
    yellow = { 0.9, 0.9, 0.2, 1 },
    cyan = { 0.2, 0.9, 0.9, 1 },
    blue = { 0.3, 0.6, 1.0, 1 },
    red = { 0.9, 0.3, 0.3, 1 },
    white = { 0.9, 0.9, 0.9, 1 }
}

-- Parse color markup text into segments
local function parseColorText(text, defaultColor)
    local segments = {}
    local pos = 1
    local currentColor = defaultColor or textColor

    while pos <= #text do
        local startTag = text:find("{", pos, true)
        if not startTag then
            -- No more tags, add remaining text
            table.insert(segments, { text = text:sub(pos), color = currentColor })
            break
        end

        -- Add text before tag
        if startTag > pos then
            table.insert(segments, { text = text:sub(pos, startTag - 1), color = currentColor })
        end

        local endTag = text:find("}", startTag, true)
        if not endTag then
            -- Malformed tag, treat as regular text
            table.insert(segments, { text = text:sub(startTag), color = currentColor })
            break
        end

        local tagContent = text:sub(startTag + 1, endTag - 1)
        if tagContent:sub(1, 1) == "/" then
            -- Closing tag, back to the line's own color
            currentColor = defaultColor or textColor
        elseif colorScheme[tagContent] then
            currentColor = colorScheme[tagContent]
        else
            -- Not a tag (a Lua table, say): keep it as text
            table.insert(segments, { text = text:sub(startTag, endTag), color = currentColor })
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
        if mt and type(mt.__index) == "table" then
            for key, value in pairs(mt.__index) do
                if type(key) == "string" and type(value) == "function" then
                    table.insert(properties, key)
                end
            end
        end

        -- Get direct table properties
        if type(obj) == "table" then
            for key in pairs(obj) do
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
    commandHintItems = {}
    if not input or input == "" then
        return options
    end

    -- A console command's subcommands, once its name is typed
    commandHintItems = hints.match(hints.commands, input)
    if input:find("%s") and #commandHintItems > 0 then
        for _, it in ipairs(commandHintItems) do
            if #it.complete > #input and it.complete:sub(1, #input):lower() == input:lower() then
                table.insert(options, it.complete)
            end
        end
        return options
    end

    -- Check for dot notation (object.property)
    local dotPos = input:find("%.")
    if dotPos then
        local objName = input:sub(1, dotPos - 1)
        local propPrefix = input:sub(dotPos + 1)
        for _, prop in ipairs(getObjectProperties(objName)) do
            if prop:sub(1, #propPrefix):lower() == propPrefix:lower() then
                table.insert(options, objName .. "." .. prop)
            end
        end
        return options
    end

    -- Console commands, then known names, then globals
    local inputLower = input:lower()
    local seen = {}
    local function add(name)
        if not seen[name] and name:sub(1, #inputLower):lower() == inputLower then
            table.insert(options, name)
            seen[name] = true
        end
    end
    for _, c in ipairs(hints.commands) do add(c[1]) end
    for _, name in ipairs(commandIndex) do add(name) end
    for name, value in pairs(_G) do
        if type(name) == "string" and (type(value) == "table" or type(value) == "function" or type(value) == "userdata") then
            add(name)
        end
    end

    return options
end

-- Update autocomplete based on current input. What's typed already is no
-- suggestion, so Enter on a complete name runs it straight away.
local function updateAutocomplete()
    autocompleteOptions = {}
    for _, option in ipairs(findAutocompleteOptions(inputText)) do
        if option ~= inputText then
            table.insert(autocompleteOptions, option)
        end
    end
    showingAutocomplete = #autocompleteOptions > 0
    autocompleteIndex = showingAutocomplete and 1 or 0
    autocompleteText = autocompleteOptions[1] or ""
end

-- Initialize the command module
function command.load()
    font = gameFont
    lineHeight = gameFont:getHeight() + 2

    command_block_instance = block.new("gfx/3d/apple_2.dds", 128, 128, 100, 400, 1)

    command.addOutput("{green}=== {yellow}LUA DEBUG CONSOLE{/yellow} ==={/green}", promptColor)
    command.addOutput("Type {yellow}help{/yellow} for available commands", outputColor)
    command.addOutput("Press {cyan}/{/cyan} or {cyan},{/cyan} to open, {cyan}Esc{/cyan} to close", outputColor)
    command.addOutput("Autocomplete: {cyan}Tab{/cyan} to cycle/accept suggestions", outputColor)
    command.addOutput("Try: {cyan}player.{/cyan} or {cyan}love.{/cyan} for object inspection", outputColor)
    command.addOutput("", outputColor)
end

local function visibleLineCount()
    local contentHeight = consoleHeight - titleBarHeight - 2 * padding - lineHeight - 10
    return math.floor(contentHeight / lineHeight), contentHeight
end

-- Add text to output buffer, one entry per line
function command.addOutput(text, color)
    color = color or outputColor
    local textStr = tostring(text)

    for line in (textStr .. "\n"):gmatch("(.-)\r?\n") do
        table.insert(output, { segments = parseColorText(line, color), text = line, color = color })
    end

    if #output > maxOutputLines * 3 then
        for _ = 1, #output - maxOutputLines * 3 do
            table.remove(output, 1)
        end
    end

    -- Back to the newest line
    scrollOffset = 0
end

-- Run a line as Lua: an expression's values are printed, else it runs as a
-- statement. Returns whether it ran without error.
local function runLua(cmd)
    local success, result = pcall(function()
        local func = load("return " .. cmd)
        if func then
            local results = { func() }
            for _, v in ipairs(results) do
                if type(v) == "table" then
                    command.addOutput(command.tableToString(v), outputColor)
                else
                    command.addOutput(tostring(v), outputColor)
                end
            end
        else
            local err
            func, err = load(cmd)
            if not func then error(err) end
            func()
        end
    end)
    if not success then
        command.addOutput("{red}Error:{/red} " .. tostring(result), errorColor)
    end
    return success
end

local function tokenize(cmd)
    local tokens = {}
    for token in cmd:gmatch("%S+") do
        table.insert(tokens, token)
    end
    return tokens
end

local function bossCommand(tokens)
    if not boss then
        command.addOutput("{red}Error:{/red} Boss module not loaded", errorColor)
        return
    end
    -- A bare "boss" spawns one, like "boss spawn"
    local sub = tokens[2] or "spawn"
    if sub == "spawn" then
        local x = tonumber(tokens[3]) or (player and player.body and player.body:getX() or 0)
        local y = tonumber(tokens[4]) or (player and player.body and player.body:getY() or 0)
        local result = boss.requestSpawn(x, y)
        if result == "spawn_requested" then
            command.addOutput("Boss spawn requested (waiting for host)", outputColor)
        else
            command.addOutput("Boss spawned with ID: " .. tostring(result), outputColor)
        end
    elseif sub == "despawn" then
        if tokens[3] == "all" then
            boss.despawnAll()
            command.addOutput("All bosses despawned", outputColor)
        else
            local id = tonumber(tokens[3])
            if id and boss.despawn(id) then
                command.addOutput("Boss " .. id .. " despawned", outputColor)
            else
                command.addOutput("{red}Error:{/red} Invalid boss ID", errorColor)
            end
        end
    elseif sub == "list" then
        local count = 0
        for _ in pairs(boss.bosses) do
            count = count + 1
        end
        command.addOutput("Active bosses: " .. count, outputColor)
    elseif sub == "damage" then
        local id = tonumber(tokens[3])
        local damage = tonumber(tokens[4]) or 100
        if id and boss.bosses[id] then
            boss.damage(id, damage)
            command.addOutput("Dealt " .. damage .. " damage to boss " .. id, outputColor)
        else
            command.addOutput("{red}Error:{/red} Invalid boss ID", errorColor)
        end
    else
        command.addOutput("Usage: boss spawn [x] [y] | boss despawn <id|all> | boss list | boss damage <id> [amount]",
            outputColor)
    end
end

local function profileCommand(tokens)
    if not profiler then
        command.addOutput("{red}Error:{/red} Profiler not loaded", errorColor)
        return
    end
    if tokens[2] == "report" then
        profiler.report(tonumber(tokens[3]) or 0)
    elseif tokens[2] == "reset" then
        profiler.reset()
        command.addOutput("Profiler reset", outputColor)
    elseif tokens[2] == "off" then
        profiler.disable()
        command.addOutput("Profiler disabled", outputColor)
    elseif tokens[2] == "on" then
        profiler.enable()
        command.addOutput("Profiler enabled", outputColor)
    elseif tokens[2] == "export" then
        local fn = tokens[3] or "profile_export.json"
        profiler.exportJSON(fn)
        command.addOutput("Profiler data exported to " .. fn, outputColor)
    else
        command.addOutput("Usage: profile report [min_ms] | profile reset | profile on/off | profile export [file]",
            outputColor)
    end
end

local function benchmarkCommand(tokens)
    if not profiler then
        command.addOutput("{red}Error:{/red} Profiler not loaded", errorColor)
        return
    end
    if tokens[2] == "run" then
        local duration = tonumber(tokens[3]) or 5
        command.addOutput("Running benchmark for " .. duration .. "s...", outputColor)
        profiler.reset()
        profiler.enable()
        -- We can't block, so just show the overlay and let the user observe
        profiler.overlay_visible = true
        command.addOutput("Watch the overlay for " .. duration .. " seconds (press F1 to hide)", outputColor)
    elseif tokens[2] == "report" then
        profiler.report()
    elseif tokens[2] == "export" then
        local fn = tokens[3] or "benchmark_export.json"
        profiler.exportJSON(fn)
        command.addOutput("Benchmark data exported to " .. fn, outputColor)
    else
        command.addOutput("Usage: benchmark run [seconds] | benchmark report | benchmark export [file]", outputColor)
    end
end

local function spawnCommand(tokens)
    if tokens[2] == "enemies" then
        local count = tonumber(tokens[3]) or 10
        local old = var.num_enemies
        var.num_enemies = count
        -- Despawn existing and re-create
        for _, e in ipairs(enemy.enemies) do
            if e.fixture then e:killEnemy() end
        end
        enemy.enemies = {}
        for _ = 1, count do
            enemy.addEnemy(math.random(100, var.screen_width), math.random(100, var.screen_height))
        end
        command.addOutput(string.format("Spawned %d enemies (was %d)", count, old), outputColor)
    elseif tokens[2] == "coins" then
        local count = tonumber(tokens[3]) or 50
        var.num_coins = count
        command.addOutput("Set XP glob count to " .. count .. " (restart to apply)", outputColor)
    else
        command.addOutput("Usage: spawn enemies <count> | spawn coins <count> (XP globs)", outputColor)
    end
end

-- Execute a console command or a line of Lua. `fromBlock` when a command
-- block runs its line again (which doesn't drop another block).
function command.execute(cmd, fromBlock)
    if cmd == "" then return end
    table.insert(history, cmd)
    if #history > 50 then
        table.remove(history, 1)
    end
    historyIndex = #history + 1
    command.addOutput("{green}> {/green}" .. cmd, textColor)

    -- Commands are matched on their first word, so Lua that merely contains
    -- one (print(output) has "tp") still runs as Lua
    local verb = cmd:match("^%s*(%S+)")
    if cmd == "help" then
        command.showHelp()
    elseif cmd == "clear" then
        output = {}
    elseif cmd == "cont" or cmd == "continue" then
        if isActive then command.toggle() end
    elseif cmd == "exit" then
        love.event.quit()
    elseif cmd == "reload" then
        love.event.push("quit", "restart")
    elseif verb == "tp" then
        local tokens = tokenize(cmd)
        if player and player.body then
            player.body:setPosition(tonumber(tokens[2]) or 0, tonumber(tokens[3]) or 0)
        end
    elseif cmd == "save" then
        serial.quickSave()
    elseif cmd == "load" then
        serial.quickLoad()
    elseif verb == "boss" then
        bossCommand(tokenize(cmd))
    elseif verb == "profile" then
        profileCommand(tokenize(cmd))
    elseif verb == "benchmark" then
        benchmarkCommand(tokenize(cmd))
    elseif verb == "spawn" then
        spawnCommand(tokenize(cmd))
    elseif runLua(cmd) and player.god and not fromBlock then
        command.createBlock(cmd)
    end
end

-- Convert table to string representation
function command.tableToString(t, indent, visited)
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
            str = str .. command.tableToString(v, indent + 1, visited)
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
function command.showHelp()
    command.addOutput("{green}Available commands:{/green}", promptColor)
    for _, c in ipairs(hints.commands) do
        for _, s in ipairs(c.sub or { false }) do
            local usage = s and (c[1] .. " " .. s[1] .. (s[2] and " " .. s[2] or ""))
                or (c[1] .. (c[2] and " " .. c[2] or ""))
            command.addOutput("  {yellow}" .. usage .. "{/yellow} - " .. (s and s[3] or c[3]), outputColor)
        end
    end
    command.addOutput("", outputColor)
    command.addOutput("{green}Lua expressions/statements:{/green}", promptColor)
    command.addOutput("  {cyan}print(value){/cyan}           - Print value", outputColor)
    command.addOutput("  {cyan}player.x = 100{/cyan}         - Set variables", outputColor)
    command.addOutput("  {cyan}love.graphics.getWidth(){/cyan} - Call functions", outputColor)
    command.addOutput("  In god mode each line that runs drops a command block; click it to run it again",
        outputColor)
    command.addOutput("", outputColor)
    command.addOutput("{green}Keyboard shortcuts:{/green}", promptColor)
    command.addOutput("  {blue}/{/blue} or {blue},{/blue} - Open console; {blue}Esc{/blue} - Close it", outputColor)
    command.addOutput("  {blue}Tab{/blue} - Cycle/accept autocomplete suggestions", outputColor)
    command.addOutput("  {blue}Up/Down{/blue} - Navigate command history", outputColor)
    command.addOutput("  {blue}Enter{/blue} - Accept autocomplete or execute command", outputColor)
    command.addOutput("  {blue}Ctrl+C/Cmd+C{/blue} - Copy last output", outputColor)
    command.addOutput("  {blue}Ctrl+V/Cmd+V{/blue} - Paste from clipboard", outputColor)
    command.addOutput("  {blue}PageUp/PageDown{/blue} - Scroll output", outputColor)
    command.addOutput("  {blue}Mouse wheel{/blue} - Scroll output", outputColor)
    command.addOutput("", outputColor)
end

-- Toggle console visibility
function command.toggle()
    isActive = not isActive
    if isActive then
        inputText = ""
        cursorPos = 0
        historyIndex = #history + 1
        showingAutocomplete = false
        autocompleteText = ""
        commandHintItems = {}
    end
    isDragging = false
    keyRepeatState = {}
end

function command.isOpen()
    return isActive
end

-- Check if mouse is over title bar
local function isMouseOverTitleBar(mx, my)
    return mx >= windowX and mx <= windowX + consoleWidth and
        my >= windowY and my <= windowY + titleBarHeight
end

-- Check if mouse is over window
local function isMouseOverWindow(mx, my)
    return mx >= windowX and mx <= windowX + consoleWidth and
        my >= windowY and my <= windowY + consoleHeight
end

-- A click on the console window, in screen coordinates (the console draws
-- on top of the CRT). Returns true when the window took it.
function command.mousepressed(x, y, button)
    if not isActive or not isMouseOverWindow(x, y) then return false end

    if button == 1 then
        -- Check close button
        local closeButtonSize = titleBarHeight - 6
        local closeButtonX = windowX + consoleWidth - closeButtonSize - 3
        local closeButtonY = windowY + 3
        if x >= closeButtonX and x <= closeButtonX + closeButtonSize and
            y >= closeButtonY and y <= closeButtonY + closeButtonSize then
            command.toggle()
            return true
        end

        -- Check title bar for dragging
        if isMouseOverTitleBar(x, y) then
            isDragging = true
            dragOffsetX = x - windowX
            dragOffsetY = y - windowY
        end
    end
    return true
end

function command.mousereleased(x, y, button)
    if button == 1 then
        isDragging = false
    end
end

function command.mousemoved(x, y, dx, dy)
    if isDragging then
        -- Keep window on screen
        local screenW = love.graphics.getWidth()
        local screenH = love.graphics.getHeight()
        windowX = math.max(0, math.min(screenW - consoleWidth, x - dragOffsetX))
        windowY = math.max(0, math.min(screenH - consoleHeight, y - dragOffsetY))
    end
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

function command.update(dt)
    if not isActive then return end
    cursorTimer = cursorTimer + dt
    if cursorTimer >= 0.5 then
        cursorVisible = not cursorVisible
        cursorTimer = 0
    end
    if handleKeyRepeat("delete", dt) then performDelete() end
    if handleKeyRepeat("backspace", dt) then performBackspace() end

    local maxScroll = math.max(0, #output - visibleLineCount())
    scrollOffset = math.min(maxScroll, math.max(0, scrollOffset))
end

function command.textinput(text)
    if not isActive then return end
    -- The "/" or "," that opened the console arrives here too
    if swallowText then
        local opener = swallowText
        swallowText = nil
        if text == opener then return end
    end
    inputText = inputText:sub(1, cursorPos) .. text .. inputText:sub(cursorPos + 1)
    cursorPos = cursorPos + #text
    updateAutocomplete()
end

-- Returns true when the console took the key: the one that opens it, and
-- every key while it's open
function command.keypressed(key)
    if not isActive then
        if key == "/" or key == "," then
            command.toggle()
            swallowText = key
            return true
        end
        return false
    end
    swallowText = nil

    if isModifierPressed() then
        if key == "c" and #output > 0 then
            local lastOutput = output[#output].text
            love.system.setClipboardText(lastOutput)
            command.addOutput("Copied: " .. lastOutput:sub(1, 10) .. "...", outputColor)
        elseif key == "v" then
            local clipboardText = love.system.getClipboardText()
            if clipboardText then
                clipboardText = clipboardText:gsub("[\r\n]+", " ")
                inputText = inputText:sub(1, cursorPos) .. clipboardText .. inputText:sub(cursorPos + 1)
                cursorPos = cursorPos + #clipboardText
                updateAutocomplete()
            end
        elseif key == "a" then
            cursorPos = #inputText
        end
        return true
    end

    if key == "escape" then
        command.toggle()
    elseif key == "return" or key == "kpenter" then
        if showingAutocomplete then
            -- First enter: accept autocomplete
            inputText = autocompleteText
            cursorPos = #inputText
            updateAutocomplete()
        else
            -- Second enter or no autocomplete: execute command
            local cmd = inputText
            inputText = ""
            cursorPos = 0
            command.execute(cmd)
            updateAutocomplete()
        end
    elseif key == "tab" then
        -- On an empty line: list every console command
        if inputText == "" and not showingAutocomplete then
            commandHintItems = hints.match(hints.commands, "")
            autocompleteOptions = {}
            for i, c in ipairs(hints.commands) do autocompleteOptions[i] = c[1] end
            showingAutocomplete = true
            autocompleteIndex = 1
            autocompleteText = autocompleteOptions[1]
            return true
        end
        -- Cycle through autocomplete options or accept suggestion
        if showingAutocomplete and #autocompleteOptions > 0 then
            if #autocompleteOptions > 1 then
                autocompleteIndex = autocompleteIndex % #autocompleteOptions + 1
                autocompleteText = autocompleteOptions[autocompleteIndex] or ""
            else
                -- Only one option, accept it
                inputText = autocompleteText
                cursorPos = #inputText
                updateAutocomplete()
            end
        end
    elseif key == "backspace" then
        keyRepeatState.backspace = { timer = 0, repeating = false }
        performBackspace()
    elseif key == "delete" then
        keyRepeatState.delete = { timer = 0, repeating = false }
        performDelete()
    elseif key == "left" then
        cursorPos = math.max(0, cursorPos - 1)
    elseif key == "right" then
        cursorPos = math.min(#inputText, cursorPos + 1)
    elseif key == "home" then
        cursorPos = 0
    elseif key == "end" then
        cursorPos = #inputText
    elseif key == "up" then
        -- Command history navigation
        if historyIndex > 1 then
            historyIndex = historyIndex - 1
            inputText = history[historyIndex] or ""
            cursorPos = #inputText
            updateAutocomplete()
        end
    elseif key == "down" then
        if historyIndex <= #history then
            historyIndex = historyIndex + 1
            inputText = history[historyIndex] or ""
            cursorPos = #inputText
            updateAutocomplete()
        end
    elseif key == "pageup" then
        local visibleLines = visibleLineCount()
        scrollOffset = math.min(math.max(0, #output - visibleLines), scrollOffset + math.floor(visibleLines / 2))
    elseif key == "pagedown" then
        scrollOffset = math.max(0, scrollOffset - math.floor(visibleLineCount() / 2))
    end
    return true
end

function command.keyreleased(key)
    keyRepeatState[key] = nil
end

-- Mouse wheel scrolls the output. Returns true when the console took it.
function command.wheelmoved(x, y)
    if not isActive then return false end
    local maxScroll = math.max(0, #output - visibleLineCount())
    if y > 0 then
        scrollOffset = math.min(maxScroll, scrollOffset + 3)
    elseif y < 0 then
        scrollOffset = math.max(0, scrollOffset - 3)
    end
    return true
end

-- Draw the console
function command.draw()
    if not isActive then return end

    local r, g, b, a = love.graphics.getColor()
    local currentFont = love.graphics.getFont()
    love.graphics.setFont(font)

    -- Draw main window background
    love.graphics.setColor(0.05, 0.05, 0.05, 0.95) -- Very dark background
    love.graphics.rectangle("fill", windowX, windowY, consoleWidth, consoleHeight, 8)

    -- Draw window border
    love.graphics.setColor(0.2, 0.6, 0.9, 0.8) -- Blue border
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", windowX, windowY, consoleWidth, consoleHeight, 8)

    -- Draw title bar
    local titleBarColor = isDragging and { 0.3, 0.7, 1.0, 0.9 } or { 0.2, 0.6, 0.9, 0.8 }
    love.graphics.setColor(titleBarColor)
    love.graphics.rectangle("fill", windowX, windowY, consoleWidth, titleBarHeight, 8)

    -- Draw title bar border
    love.graphics.setColor(0.4, 0.8, 1.0, 1.0)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", windowX, windowY, consoleWidth, titleBarHeight, 8)

    -- Draw title text
    love.graphics.setColor(1, 1, 1, 1)
    local titleText = "LUA DEBUG CONSOLE"
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
    local visibleLines, contentHeight = visibleLineCount()
    local startLine = math.max(1, #output - visibleLines - scrollOffset + 1)
    local endLine = math.min(#output, startLine + visibleLines - 1)

    -- Draw output text, clipped to the window
    love.graphics.setScissor(windowX + padding, contentY, consoleWidth - 2 * padding, contentHeight)
    local y = contentY
    for i = startLine, endLine do
        local x = windowX + padding
        for _, segment in ipairs(output[i].segments) do
            love.graphics.setColor(segment.color)
            love.graphics.print(segment.text, x, y)
            x = x + font:getWidth(segment.text)
        end
        y = y + lineHeight
    end
    love.graphics.setScissor()

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
    if inputText == "" and not showingAutocomplete then
        love.graphics.setColor(0.5, 0.5, 0.5, 0.7)
        love.graphics.print("command or Lua; Tab lists commands", windowX + padding + promptWidth + 4, inputY)
    end

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

    -- Autocomplete list (above the input area). Console commands show their
    -- arguments and what they do; while typing a command's arguments, its usage.
    local hinted = {}
    for _, it in ipairs(commandHintItems) do
        hinted[(it.complete:gsub("%s+$", ""))] = it
    end
    local rows = {}
    if showingAutocomplete then
        for i, option in ipairs(autocompleteOptions) do
            local it = hinted[(option:gsub("%s+$", ""))]
            rows[i] = { label = it and it.label or option, desc = it and it.desc }
        end
    else
        rows = commandHintItems
    end
    if #rows > 1 or (rows[1] and rows[1].desc) then
        hints.draw(rows, showingAutocomplete and autocompleteIndex or 0,
            windowX + padding + promptWidth - 8, inputY - 6, font, consoleWidth - 2 * padding)
    end

    -- Draw scroll bar if needed
    if #output > visibleLines then
        local maxScroll = math.max(1, #output - visibleLines) -- Prevent division by zero
        local scrollBarHeight = math.max(10, (visibleLines / #output) * contentHeight)
        local scrollableArea = contentHeight - scrollBarHeight
        local scrollBarY = contentY + (1 - scrollOffset / maxScroll) * scrollableArea
        love.graphics.setColor(0.3, 0.7, 1.0, 0.6)
        love.graphics.rectangle("fill", windowX + consoleWidth - 8, scrollBarY, 4, scrollBarHeight, 2)
    end

    love.graphics.setColor(r, g, b, a)
    love.graphics.setFont(currentFont)
end

--------------------------------------------------------------------------------
-- Command blocks
--------------------------------------------------------------------------------

local function createCommandBlockPhysics(block)
    -- Create physics bodies on all clients for consistent behavior
    if not world then
        error("Physics world not initialized!")
    end
    if not block.x or not block.y then
        error("Block position not set: x=" .. tostring(block.x) .. ", y=" .. tostring(block.y))
    end

    block.body = love.physics.newBody(world, block.x, block.y, "dynamic")
    block.shape = love.physics.newRectangleShape(30, 40)
    block.fixture = love.physics.newFixture(block.body, block.shape)
end

-- Drop a block that runs `cmd` where the player stands
function command.createBlock(cmd)
    local px, py = player.body:getPosition()
    local block_id = "client_" ..
        tostring(var.multiplayer or 0) .. "_" .. tostring(next_block_id) .. "_" .. tostring(love.timer.getTime())
    next_block_id = next_block_id + 1

    local new_block = {
        id = block_id,
        cmd = cmd,
        x = px,
        y = py,
        w = command_block_instance.width,
        h = command_block_instance.height,
        active = true,
        creator = var.multiplayer or 0 -- who created this block
    }

    -- Add to local list immediately (like sending a message)
    createCommandBlockPhysics(new_block)
    table.insert(command_blocks, new_block)

    -- If in multiplayer, broadcast this command block to everyone
    if var.multiplayer then
        command.broadcastCommandBlock(new_block)
    end
end

function command.getCommandBlocks()
    local serializable_blocks = {}
    for _, block in ipairs(command_blocks) do
        local bx, by = block.x, block.y
        local vx, vy = 0, 0
        if block.body then
            bx, by = block.body:getPosition()
            vx, vy = block.body:getLinearVelocity()
        end
        table.insert(serializable_blocks, {
            id = block.id,
            cmd = block.cmd,
            x = bx,
            y = by,
            vx = vx,
            vy = vy,
            active = block.active
        })
    end
    return serializable_blocks
end

function command.setCommandBlocks(blocks)
    -- Clear existing blocks first
    for _, block in ipairs(command_blocks) do
        if block.body and not block.body:isDestroyed() then
            block.body:destroy()
        end
    end
    command_blocks = {}

    for _, block_data in ipairs(blocks or {}) do
        command.addBlock(block_data)
    end
end

function command.addBlock(block_data)
    if not block_data.id then return end -- Can't add block without ID

    -- Check for duplicates
    for _, existing_block in ipairs(command_blocks) do
        if existing_block.id == block_data.id then
            return -- Block already exists
        end
    end

    createCommandBlockPhysics(block_data)
    table.insert(command_blocks, block_data)
end

function command.populate()
    local player_x, player_y = player.body:getPosition()
    for _, block in ipairs(command_blocks) do
        local vx, vy, bx, by = 0, 0, 0, 0
        if block.body then
            bx, by = block.body:getPosition()
            if not var.multiplayer or var.multiplayer == 1 then
                vx, vy = block.body:getLinearVelocity()
            elseif block.vx then
                vx, vy = block.vx, block.vy
            end
        end

        -- Use superclass to add to draw list with original offset values
        command_block_instance:addToDrawList(dynamic_draw_list, bx - 60, by - 60, vx, vy, 180, 0, 0)
        dynamic_draw_list[#dynamic_draw_list].source_object_type = "command"
        dynamic_draw_list[#dynamic_draw_list].command = block.cmd

        local dist = math.sqrt((player_x - bx) ^ 2 + (player_y - by) ^ 2)
        if dist < 100 then
            table.insert(dynamic_draw_list, {
                sort_y = block.y + 101, -- a bit higher than the block
                draw_type = "text",
                text = block.cmd,
                x = bx,
                y = by - 60,
                color = { 1, 1, 1, 1 },
                blend_mode = { "alpha" }
            })
        end
    end
end

-- A click in the world (image coordinates): runs the command block under it.
-- Returns true when there was one.
function command.clickBlock(x, y, button)
    if button ~= 1 then return false end
    local world_x, world_y = camera.screenToWorld(x, y)
    local clicked_block = nil

    -- Check local command blocks first (for server and single player)
    if var.multiplayer == 1 or not var.multiplayer then
        -- Expand the query area slightly to ensure detection
        local query_size = 10
        world:queryBoundingBox(world_x - query_size, world_y - query_size, world_x + query_size, world_y + query_size,
            function(fixture)
                for _, block in ipairs(command_blocks) do
                    if block.fixture == fixture then
                        clicked_block = block
                        return false -- stop querying
                    end
                end
                return true -- continue querying
            end)
    end

    -- If no local block found, check networked command blocks (for clients)
    if not clicked_block and renderer and renderer.networked_state then
        for _, block in pairs(renderer.networked_state.command_blocks) do
            if block.active then
                local dx = world_x - block.x
                local dy = world_y - block.y
                -- Hitbox from the sprite frame (128x128)
                if dx >= -64 and dx <= 64 and dy >= -64 and dy <= 64 then
                    clicked_block = block
                    break
                end
            end
        end
    end

    if clicked_block then
        command.execute(clicked_block.cmd, true)
        return true
    end
    return false
end

-- Broadcast a command block to all players (like sending a message)
function command.broadcastCommandBlock(block)
    if not var.multiplayer or not mp then return end

    -- Create serializable version (no physics bodies)
    local message = {
        type = "command_block",
        block = {
            id = block.id,
            cmd = block.cmd,
            x = block.x,
            y = block.y,
            w = block.w,
            h = block.h,
            active = block.active,
            creator = block.creator
        }
    }
    -- Plain JSON: messages are newline-framed, and JSON never holds a raw
    -- newline (compressed bytes could)
    local data = json.encode(message)
    if var.multiplayer == 1 then
        mp:broadcast(data) -- Server: to all clients
    else
        mp:sendToServer(data) -- Client: to the server
    end
end

-- Receive a command block from network (like receiving a message)
function command.receiveCommandBlock(block)
    -- Check if we already have this block
    for _, existing_block in ipairs(command_blocks) do
        if existing_block.id == block.id then
            return -- Already have this block
        end
    end

    createCommandBlockPhysics(block)
    table.insert(command_blocks, block)

    -- If we're the server, relay to all other clients
    if var.multiplayer == 1 and block.creator ~= 1 then
        command.broadcastCommandBlock(block)
    end
end

return command
