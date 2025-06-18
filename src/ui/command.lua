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
local backgroundColor = { 0, 0, 0, 0.3 }
local textColor = { 1, 1, 1, 1 }
local promptColor = { 0, 1, 0, 1 }
local errorColor = { 1, 0.3, 0.3, 1 }
local outputColor = { 0.8, 0.8, 0.8, 1 }
local command_blocks = {}
local next_block_id = 1
local command_block_img = love.graphics.newImage('gfx/3d/apple_2.png')
local command_block_font = nil
local command_block_instance = nil
local command_block_instance2 = nil
local command_block_scale = 10
-- Console dimensions
local consoleHeight = 300
local consoleWidth = 0 -- Will be set to screen width

-- Key repeat state
local keyRepeatState = {}
local keyRepeatDelay = 0.5 -- Initial delay before repeat starts
local keyRepeatRate = 0.05 -- Time between repeats

local block = require("game.block")

-- Initialize the command module
function command.load()
    font = love.graphics.getFont() or love.graphics.newFont(12)
    lineHeight = font:getHeight() + 2
    consoleWidth = love.graphics.getWidth()
    
    -- Load command block font
    command_block_font = love.graphics.newFont("gfx/menu/Px437_IBM_VGA_8x16.ttf", 16)
    font = love.graphics.newFont("gfx/menu/Px437_IBM_VGA_8x16.ttf", 16)

    -- Setup command block animation using superclass
    -- command_block_instance = block.new("gfx/3d/apple_2.png", 128, 128, 100, 400, 1)
    command_block_instance = block.new("gfx/3d/apple_2.png", 128, 128, 100, 400, 1)
    

    -- Add initial help message
    command.addOutput("=== LUA DEBUG CONSOLE ===", promptColor)
    command.addOutput("Type 'help' for available commands", outputColor)
    command.addOutput("Press '/' to toggle console", outputColor)
    command.addOutput("Ctrl+C/Cmd+C to copy, Ctrl+V/Cmd+V to paste", outputColor)
    command.addOutput("", outputColor)

    createBlock("welcome_to_the_game")
end

-- Wrap text to fit within console width
local function wrapText(text, maxWidth)
    local wrappedLines = {}
    local words = {}

    -- Split text into words, preserving spaces
    for word in text:gmatch("%S+") do
        table.insert(words, word)
    end

    if #words == 0 then
        return { text }
    end

    local currentLine = ""
    local spaceWidth = font:getWidth(" ")

    for i, word in ipairs(words) do
        local wordWidth = font:getWidth(word)
        local currentLineWidth = font:getWidth(currentLine)

        -- Check if adding this word would exceed the max width
        if currentLine ~= "" and currentLineWidth + spaceWidth + wordWidth > maxWidth then
            -- Start a new line
            table.insert(wrappedLines, currentLine)
            currentLine = word
        else
            -- Add word to current line
            if currentLine ~= "" then
                currentLine = currentLine .. " " .. word
            else
                currentLine = word
            end
        end
    end

    -- Add the last line if it's not empty
    if currentLine ~= "" then
        table.insert(wrappedLines, currentLine)
    end

    -- If no lines were created, return the original text
    if #wrappedLines == 0 then
        return { text }
    end

    return wrappedLines
end

-- Add text to output buffer
function command.addOutput(text, color)
    color = color or outputColor
    local textStr = tostring(text)

    -- Calculate available width for text (accounting for padding and scroll bar)
    local availableWidth = consoleWidth - (padding * 2) - 20 -- 20px for potential scroll bar

    -- Wrap the text if it's too long
    local wrappedLines = wrapText(textStr, availableWidth)

    -- Add each wrapped line as a separate output entry
    for _, line in ipairs(wrappedLines) do
        table.insert(output, { text = line, color = color })
    end

    -- Limit output buffer size
    if #output > maxOutputLines * 3 then -- Increased limit due to wrapped lines
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
    elseif cmd == "tp" then
        player.body:setPosition(0, 0)
        return
    elseif cmd == "save" then
        -- for this function expect 3 tokens "tp", "x: float", "y: float"
        -- we extract second and third index for x,y if they dont exist tp to 0
        serial.quickSave()
        return
    elseif cmd == "load" then
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
    else
        -- On success, create a command block message
        if player.god then
            createBlock(cmd)
        end
    end
end

function createBlock(cmd)
    local px, py = player.body:getPosition()
    local block_id = "client_" ..
    tostring(var.multiplayer or 0) .. "_" .. tostring(next_block_id) .. "_" .. tostring(love.timer.getTime())
    next_block_id = next_block_id + 1

    local new_block = {
        id = block_id,
        cmd = cmd,
        x = 0,
        y = 0,
        w = command_block_img:getWidth(),
        h = command_block_img:getHeight(),
        active = true,
        creator = var.multiplayer or 0     -- who created this block
    }

    -- Add to local list immediately (like sending a message)
    createCommandBlockPhysics(new_block)
    table.insert(command_blocks, new_block)

    -- If in multiplayer, broadcast this command block to everyone
    if var.multiplayer then
        command.broadcastCommandBlock(new_block)
    end
end

function createCommandBlockPhysics(block)
    -- Only create physics bodies on server (like fire effects)
    if var.multiplayer == 1 or not var.multiplayer then
        if not world then
            error("Physics world not initialized!")
        end
        if not block.x or not block.y then
            error("Block position not set: x=" .. tostring(block.x) .. ", y=" .. tostring(block.y))
        end
        if not block.w or not block.h then
            error("Block dimensions not set: w=" .. tostring(block.w) .. ", h=" .. tostring(block.h))
        end

        block.body = love.physics.newBody(world, block.x, block.y, "dynamic")
        block.shape = love.physics.newRectangleShape(30,40)
        block.fixture = love.physics.newFixture(block.body, block.shape, 1)
        -- block.fixture:setSensor(true)
    end
    -- Clients don't create physics bodies, just store the block data for networking
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
    command.addOutput("Keyboard shortcuts:", promptColor)
    command.addOutput("  Ctrl+C/Cmd+C - Copy last output line", outputColor)
    command.addOutput("  Ctrl+V/Cmd+V - Paste from clipboard", outputColor)
    command.addOutput("  Ctrl+A/Cmd+A - Select all text", outputColor)
    command.addOutput("  PageUp/PageDown - Scroll output", outputColor)
    command.addOutput("  Mouse wheel - Scroll output", outputColor)
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
    -- Clear key repeat state when toggling
    keyRepeatState = {}
end

-- Handle key repeat for continuous key presses
local function handleKeyRepeat(key, dt)
    if not keyRepeatState[key] then
        return false
    end

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

-- Perform delete operation
local function performDelete()
    if cursorPos < #inputText then
        inputText = inputText:sub(1, cursorPos) .. inputText:sub(cursorPos + 2)
    end
end

-- Perform backspace operation
local function performBackspace()
    if cursorPos > 0 then
        inputText = inputText:sub(1, cursorPos - 1) .. inputText:sub(cursorPos + 1)
        cursorPos = cursorPos - 1
    end
end

-- Check if modifier keys are pressed
local function isModifierPressed()
    return love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")
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

    -- Handle key repeats
    if handleKeyRepeat("delete", dt) then
        performDelete()
    end

    if handleKeyRepeat("backspace", dt) then
        performBackspace()
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

    -- Handle modifier key combinations first
    if isModifierPressed() then
        if key == "c" then
            -- Copy last line output to clipboard
            if #output > 0 then
                local lastOutput = output[#output].text

                love.system.setClipboardText(string.sub(lastOutput, 2, #lastOutput))
                command.addOutput("Copied to clipboard: " .. string.sub(lastOutput, 1, 10), outputColor)
            else
                command.addOutput("No output to copy", errorColor)
            end
            return
        elseif key == "v" then
            -- Paste from clipboard
            local clipboardText = love.system.getClipboardText()
            if clipboardText and clipboardText ~= "" then
                -- Remove newlines and clean up the text
                clipboardText = clipboardText:gsub("[\r\n]+", " ")
                -- Insert text at cursor position
                inputText = inputText:sub(1, cursorPos) .. clipboardText .. inputText:sub(cursorPos + 1)
                cursorPos = cursorPos + #clipboardText
            end
            return
        elseif key == "a" then
            -- Select all text (move cursor to end)
            cursorPos = #inputText
            return
        end
    end

    -- Regular key handling
    if key == "escape" then
        command.toggle()
    elseif key == "return" then
        command.execute(inputText)
        inputText = ""
        cursorPos = 0
    elseif key == "backspace" then
        -- Start key repeat state
        keyRepeatState.backspace = { timer = 0, repeating = false }
        performBackspace()
    elseif key == "delete" then
        -- Start key repeat state
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
        scrollOffset = math.max(0, scrollOffset - 10)
    elseif key == "pagedown" then
        scrollOffset = math.min(math.max(0, #output - maxOutputLines + 3), scrollOffset + 10)
    end
end

-- Handle mouse wheel scrolling
function command.wheelmoved(x, y)
    if not isActive then return end

    -- Scroll up/down with mouse wheel
    local scrollAmount = 3
    if y > 0 then
        -- Scroll up
        scrollOffset = math.max(0, scrollOffset - scrollAmount)
    elseif y < 0 then
        -- Scroll down
        scrollOffset = math.min(math.max(0, #output - maxOutputLines + 3), scrollOffset + scrollAmount)
    end
end

function command.keyreleased(key)
    if not isActive then return end

    -- Stop key repeat when key is released
    if keyRepeatState[key] then
        keyRepeatState[key] = nil
    end
end

-- Draw the console
function command.draw()
    if not isActive then return end

    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()
    -- local consoleHeight = 200  -- Height of the bottom console
    local consoleY = screenHeight - consoleHeight

    -- Save current graphics state
    local r, g, b, a = love.graphics.getColor()
    local currentFont = love.graphics.getFont()

    -- Set font
    love.graphics.setFont(font)

    -- Background
    love.graphics.setColor(backgroundColor or { 0.1, 0.1, 0.1, 0.95 }) -- Slightly transparent dark gray
    love.graphics.rectangle("fill", 0, consoleY, screenWidth, consoleHeight, 8, 8)

    -- Border (subtle)
    love.graphics.setColor(0.3, 0.3, 0.3, 0.7)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", 0, consoleY, screenWidth, consoleHeight, 8, 8)

    -- Draw output text
    local y = consoleY + padding
    local visibleLines = math.floor((consoleHeight - 60) / lineHeight)
    local startLine = math.max(1, #output - visibleLines - scrollOffset + 1)
    local endLine = math.min(#output, startLine + visibleLines - 1)

    for i = startLine, endLine do
        if output[i] then
            love.graphics.setColor(output[i].color or textColor)
            love.graphics.print(output[i].text, padding, y)
            y = y + lineHeight
        end
    end

    -- Draw input line
    local inputY = consoleY + consoleHeight - 40
    love.graphics.setColor(promptColor)
    love.graphics.print("< ", padding, inputY)

    -- Input text
    love.graphics.setColor(textColor)
    local promptWidth = font:getWidth("< ")
    love.graphics.print(inputText, padding + promptWidth, inputY)

    -- Cursor
    if cursorVisible then
        local textBeforeCursor = inputText:sub(1, cursorPos)
        local cursorX = padding + promptWidth + font:getWidth(textBeforeCursor)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(textColor)
        love.graphics.line(cursorX, inputY, cursorX, inputY + lineHeight)
    end

    -- Scroll bar
    if #output > maxOutputLines then
        love.graphics.setColor(0.5, 0.5, 0.5, 0.1)
        local maxScroll = math.max(0, #output - maxOutputLines + 3)
        local scrollPercent = maxScroll > 0 and (scrollOffset / maxScroll) or 0
        local scrollBarHeight = math.max(20, (maxOutputLines / math.max(maxOutputLines, #output)) * (consoleHeight - 60))
        local scrollBarY = consoleY + 10 + scrollPercent * (consoleHeight - 60 - scrollBarHeight)

        love.graphics.rectangle("fill", screenWidth - 8, scrollBarY, 4, scrollBarHeight, 2, 2)

        -- Optional scroll position text (fade look)
        love.graphics.setColor(0.7, 0.7, 0.7, 0.1)
        local scrollText = string.format("%d/%d", math.max(0, #output - maxOutputLines - scrollOffset + 3), #output)
        local textWidth = font:getWidth(scrollText)
        love.graphics.print(scrollText, screenWidth - textWidth - 16, consoleY + consoleHeight - 25)
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

function command.getCommandBlocks()
    local serializable_blocks = {}
    for _, block in ipairs(command_blocks) do
        table.insert(serializable_blocks, {
            id = block.id,
            cmd = block.cmd,
            x = block.x,
            y = block.y,
            w = block.w,
            h = block.h,
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

    -- Create physics only on server/single player
    createCommandBlockPhysics(block_data)
    table.insert(command_blocks, block_data)
end

function command.populate()
    local player_x, player_y = player.body:getPosition()
    local player_vx, player_vy = player.body:getLinearVelocity()
    for i, block in ipairs(command_blocks) do
        -- Only create physics bodies on server/single player
        -- if not block.body and (var.multiplayer == 1 or not var.multiplayer) then
        --     createCommandBlockPhysics(block)
        -- end

        -- Use superclass to add to draw list with original offset values
        local vx,vy = block.body:getLinearVelocity()
        local bx,by = block.body:getPosition()
        command_block_instance:addToDrawList(dynamic_draw_list, bx - 60, by - 60, vx, vy, 180, 0, 0)
        dynamic_draw_list[#dynamic_draw_list].source_object_type = "command"
        dynamic_draw_list[#dynamic_draw_list].command = block.cmd
        
        local dist = math.sqrt((player_x - bx) ^ 2 + (player_y - by) ^ 2)
        if dist < 100 then
            table.insert(dynamic_draw_list, {
                sort_y = block.y + block.h + 101, -- a bit higher than the block
                draw_type = "text",
                text = block.cmd,
                x = bx - 60, 
                y = by - 60,
                color = { 1, 1, 1, 1 },
                blend_mode = { "alpha" }
            })
        end
    end
end

function command.mousepressed(x, y, button)
    if button == 1 then -- Left-click
        local world_x, world_y = camera.screenToWorld(x, y)
        local clicked_block = nil

        -- Check local command blocks first (for server and single player)
        if var.multiplayer == 1 or not var.multiplayer then
            -- Expand the query area slightly to ensure detection
            local query_size = 10
            world:queryBoundingBox(world_x - query_size, world_y - query_size, world_x + query_size, world_y + query_size, function(fixture)
                for i, block in ipairs(command_blocks) do
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
                    -- Use a hitbox size based on sprite frame dimensions (128x128 as per animation setup)
                    local half_w = 64 -- Half of 128, adjusted for sprite frame
                    local half_h = 64 -- Half of 128, adjusted for sprite frame

                    if dx >= -half_w and dx <= half_w and dy >= -half_h and dy <= half_h then
                        clicked_block = block
                        break
                    end
                end
            end
        end

        if clicked_block then
            command.execute(clicked_block.cmd)
            return true
        end
    end
    return false
end

-- Broadcast a command block to all players (like sending a message)
function command.broadcastCommandBlock(block)
    if not var.multiplayer then return end

    -- Create serializable version (no physics bodies)
    local serializable_block = {
        id = block.id,
        cmd = block.cmd,
        x = block.x,
        y = block.y,
        w = block.w,
        h = block.h,
        active = block.active,
        creator = block.creator
    }

    local message = {
        type = "command_block",
        block = serializable_block
    }

    if var.multiplayer == 1 then
        -- Server: broadcast to all clients
        if mp then
            local json_string = json.encode(message)
            local compressed_data = love.data.compress("string", "zlib", json_string, 9)
            mp:broadcast(compressed_data)
        end
    else
        -- Client: send to server
        if mp then
            local json_string = json.encode(message)
            local compressed_data = love.data.compress("string", "zlib", json_string, 9)
            mp:sendToServer(compressed_data)
        end
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

    -- Add the received block
    createCommandBlockPhysics(block)
    table.insert(command_blocks, block)

    -- If we're the server, relay to all other clients
    if var.multiplayer == 1 and block.creator ~= 1 then
        command.broadcastCommandBlock(block)
    end
end

-- Get command block font for external use
function command.getCommandBlockFont()
    return command_block_font
end

return command
