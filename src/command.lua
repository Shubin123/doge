-- command.lua - In-game command line for LÖVE 2D
local command = {}

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
local backgroundColor = { 0, 0, 0, 0.8 }
local textColor = { 1, 1, 1, 1 }
local promptColor = { 0, 1, 0, 1 }
local errorColor = { 1, 0.3, 0.3, 1 }
local outputColor = { 0.8, 0.8, 0.8, 1 }

-- Console dimensions
local consoleHeight = 300
local consoleWidth = 0 -- Will be set to screen width

-- Initialize the command module
function command.load()
    font = love.graphics.getFont() or love.graphics.newFont(12)
    lineHeight = font:getHeight() + 2
    consoleWidth = love.graphics.getWidth()

    -- Add initial help message
    command.addOutput("=== LUA DEBUG CONSOLE ===", promptColor)
    command.addOutput("Type 'help' for available commands", outputColor)
    command.addOutput("Press '/' to toggle console", outputColor)
    command.addOutput("", outputColor)
end

-- Add text to output buffer
function command.addOutput(text, color)
    color = color or outputColor
    table.insert(output, { text = tostring(text), color = color })

    -- Limit output buffer size
    if #output > maxOutputLines * 2 then
        for i = 1, maxOutputLines do
            table.remove(output, 1)
        end
    end

    -- Auto-scroll to bottom
    scrollOffset = math.max(0, #output - maxOutputLines + 3)
end

-- Execute a Lua command
function command.execute(cmd)
    if cmd == "" then return end

    -- Add command to history
    table.insert(history, cmd)
    if #history > 50 then
        table.remove(history, 1)
    end
    historyIndex = #history + 1

    -- Show command in output
    command.addOutput("< " .. cmd, promptColor)

    -- Handle special commands
    if cmd == "help" then
        command.showHelp()
        return
    elseif cmd == "clear" then
        output = {}
        return
    elseif cmd == "cont" or cmd == "continue" then
        command.toggle()
        return
    elseif cmd == "exit" then
        love.event.quit()
        return
    elseif cmd == "reload" then
        love.event.push("quit", "restart")

        return
    elseif string.find(cmd, "tp") then
        -- for this function expect 3 tokens "tp", "x: float", "y: float"
        -- we extract second and third index for x,y if they dont exist tp to 0

        local tokens = mymath.tokens(cmd)
        print(tokens[1], tokens[2])
        local tp_x = tonumber(tokens[1]) or 0
        local tp_y = tonumber(tokens[2]) or 0
        player.body:setPosition(tp_x, tp_y)

        return
    elseif string.find(cmd, "save") then
        -- for this function expect 3 tokens "tp", "x: float", "y: float"
        -- we extract second and third index for x,y if they dont exist tp to 0
        serial.quickSave()

        return
    elseif string.find(cmd, "load") then
        -- for this function expect 3 tokens "tp", "x: float", "y: float"
        -- we extract second and third index for x,y if they dont exist tp to 0
        serial.quickLoad()

        return
    end


    -- Try to execute as Lua code
    local success, result = pcall(function()
        -- First try as expression (for print-like behavior)
        local func, err = load("return " .. cmd)
        if func then
            local results = { func() }
            if #results > 0 then
                for i, v in ipairs(results) do
                    if type(v) == "table" then
                        command.addOutput(command.tableToString(v), outputColor)
                    else
                        command.addOutput(tostring(v), outputColor)
                    end
                end
            end
        else
            -- Try as statement
            func, err = load(cmd)
            if func then
                func()
            else
                error(err)
            end
        end
    end)

    if not success then
        command.addOutput("Error: " .. tostring(result), errorColor)
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
    command.addOutput("Available commands:", promptColor)
    command.addOutput("  help          - Show this help", outputColor)
    command.addOutput("  clear         - Clear console output", outputColor)
    command.addOutput("  cont/continue - Close console and continue", outputColor)
    command.addOutput("  exit          - Quit game", outputColor)
    command.addOutput("", outputColor)
    command.addOutput("Lua expressions and statements:", promptColor)
    command.addOutput("  print(value)           - Print a value", outputColor)
    command.addOutput("  player.x = 100         - Set variables", outputColor)
    command.addOutput("  love.graphics.getWidth() - Call functions", outputColor)
    command.addOutput("  var                     - Access global table", outputColor)
    command.addOutput("  tp (x) (y) - teleport player ", outputColor)
    command.addOutput("", outputColor)
end

-- Toggle console visibility
function command.toggle()
    isActive = not isActive
    if isActive then
        inputText = ""
        cursorPos = 0
        historyIndex = #history + 1
    end
end

-- Update function
function command.update(dt)
    if not isActive then return end

    -- Update cursor blink
    cursorTimer = cursorTimer + dt
    if cursorTimer >= 0.5 then
        cursorVisible = not cursorVisible
        cursorTimer = 0
    end

    -- Update console width if window was resized
    consoleWidth = love.graphics.getWidth()
end

-- Handle text input
function command.textinput(text)
    if not isActive then return end
    if text == "/" then
        text = ""
    end
    -- Insert text at cursor position
    inputText = inputText:sub(1, cursorPos) .. text .. inputText:sub(cursorPos + 1)
    cursorPos = cursorPos + #text
end

-- Handle key presses
function command.keypressed(key)
    -- Toggle console with slash key
    if key == "/" then
        command.toggle()
        return
    end

    if not isActive then return end

    if key == "escape" then
        command.toggle()
    elseif key == "return" then
        command.execute(inputText)
        inputText = ""
        cursorPos = 0
    elseif key == "backspace" then
        if cursorPos > 0 then
            inputText = inputText:sub(1, cursorPos - 1) .. inputText:sub(cursorPos + 1)
            cursorPos = cursorPos - 1
        end
    elseif key == "delete" then
        if cursorPos < #inputText then
            inputText = inputText:sub(1, cursorPos) .. inputText:sub(cursorPos + 2)
        end
    elseif key == "left" then
        cursorPos = math.max(0, cursorPos - 1)
    elseif key == "right" then
        cursorPos = math.min(#inputText, cursorPos + 1)
    elseif key == "home" then
        cursorPos = 0
    elseif key == "end" then
        cursorPos = #inputText
    elseif key == "up" then
        if historyIndex > 1 then
            historyIndex = historyIndex - 1
            inputText = history[historyIndex] or ""
            cursorPos = #inputText
        end
    elseif key == "down" then
        if historyIndex <= #history then
            historyIndex = historyIndex + 1
            inputText = history[historyIndex] or ""
            cursorPos = #inputText
        end
    elseif key == "pageup" then
        scrollOffset = math.max(0, scrollOffset - 5)
    elseif key == "pagedown" then
        scrollOffset = math.min(#output - maxOutputLines + 3, scrollOffset + 5)
    end
end

-- Draw the console
function command.draw()
    if not isActive then return end

    local width = consoleWidth
    local height = consoleHeight

    -- Save current graphics state
    local r, g, b, a = love.graphics.getColor()
    local currentFont = love.graphics.getFont()

    -- Set console font
    love.graphics.setFont(font)

    -- Draw background
    love.graphics.setColor(backgroundColor)
    love.graphics.rectangle("fill", 0, 0, width, height)

    -- Draw border
    love.graphics.setColor(promptColor)
    love.graphics.rectangle("line", 0, 0, width, height)

    -- Draw output text
    local y = padding
    local visibleLines = math.floor((height - 60) / lineHeight)
    local startLine = math.max(1, #output - visibleLines - scrollOffset + 1)
    local endLine = math.min(#output, startLine + visibleLines - 1)

    for i = startLine, endLine do
        if output[i] then
            love.graphics.setColor(output[i].color)
            love.graphics.print(output[i].text, padding, y)
            y = y + lineHeight
        end
    end

    -- Draw input line
    local inputY = height - 40
    love.graphics.setColor(promptColor)
    love.graphics.print("< ", padding, inputY)

    -- Draw input text
    love.graphics.setColor(textColor)
    local promptWidth = font:getWidth("< ")
    love.graphics.print(inputText, padding + promptWidth, inputY)

    -- Draw cursor
    if cursorVisible then
        local textBeforeCursor = inputText:sub(1, cursorPos)
        local cursorX = padding + promptWidth + font:getWidth(textBeforeCursor)
        love.graphics.line(cursorX, inputY, cursorX, inputY + lineHeight)
    end

    -- Draw scroll indicator
    if #output > maxOutputLines then
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        local scrollPercent = scrollOffset / math.max(1, #output - maxOutputLines + 3)
        local scrollBarHeight = math.max(10, (visibleLines / #output) * (height - 80))
        local scrollBarY = 10 + scrollPercent * (height - 80 - scrollBarHeight)
        love.graphics.rectangle("fill", width - 10, scrollBarY, 5, scrollBarHeight)
    end

    -- Restore graphics state
    love.graphics.setColor(r, g, b, a)
    love.graphics.setFont(currentFont)
end

-- Check if console is active
function command.isActive()
    return isActive
end

-- Expose global access for easier debugging
function command.setGlobal(name, value)
    _G[name] = value
end

-- Add reference to common game objects (call this from your main game)
-- not needed potentially
function command.setGameReferences(refs)
    for name, value in pairs(refs) do
        _G[name] = value
    end
end

return command
