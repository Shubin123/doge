-- testing multiplayer - Example usage of the multiplayer module
local Multiplayer = require("src.multiplayer")


local role = nil
local messages = {}
local input_text = ""
local host_ip = ""
local max_messages = 10

function love.load()
    -- Create multiplayer instance
    Multiplayer.load(0)

end

function love.update(dt)
    if mp then
        mp:update()
        sendMovementMessage()
    end
end

function love.draw()
    love.graphics.setColor(1, 1, 1)
    local y = 10
    
    if not role then
        -- Setup screen with IP input
        love.graphics.print("=== MULTIPLAYER SETUP ===", 10, y)
        y = y + 30
        
        love.graphics.print("Host IP Address:", 10, y)
        y = y + 20
        
        -- IP input box
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle("fill", 10, y, 300, 25)
        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("line", 10, y, 300, 25)
        love.graphics.print(host_ip .. "_", 15, y + 5)
        y = y + 35
        
        -- Host/Client buttons
        love.graphics.print("Press 'H' to HOST  |  Press 'C' to CONNECT", 10, y)
        y = y + 30
        
    else
        -- Connected screen
        love.graphics.print("Role: " .. role, 10, y)
        y = y + 20
        love.graphics.print("Host IP: " .. host_ip, 10, y)
        y = y + 20
        
        local info = Multiplayer:getConnectionInfo()
        if info.is_host then
            love.graphics.print("Connected peers: " .. info.peer_count, 10, y)
        elseif info.is_client then
            love.graphics.print("Connected to server: " .. tostring(info.connected_to_server), 10, y)
        end
        y = y + 30
        
        -- Chat input
        love.graphics.print("Message:", 10, y)
        y = y + 20
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle("fill", 10, y, 400, 25)
        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("line", 10, y, 400, 25)
        love.graphics.print(input_text .. "_", 15, y + 5)
        y = y + 35
        
        love.graphics.print("Enter to send | M for movement | D to disconnect", 10, y)
        y = y + 30
    end
    
    -- Messages
    if #messages > 0 then
        love.graphics.print("=== MESSAGES ===", 10, y)
        y = y + 20
        
        for i, msg in ipairs(messages) do
            local text = string.format("[%s] %s: %s", 
                                     msg.role:upper(), msg.peer, msg.text)
            love.graphics.print(text, 10, y)
            y = y + 15
        end
    end
end

function love.textinput(text)
    if not role then
        host_ip = host_ip .. text
    else
        input_text = input_text .. text
    end
end

function love.keypressed(key)
    if not role then
        if key == "h" then
            -- print(host_ip)
            startHost("localhost")
        elseif key == "c" then
            connectToHost("localhost")
        elseif key == "backspace" then
            host_ip = host_ip:sub(1, -2)
        end
    else
        if key == "return" and input_text ~= "" then
            sendChatMessage()
        elseif key == "backspace" then
            input_text = input_text:sub(1, -2)
        elseif key == "d" then
            disconnect()
        elseif key == "m" then
            sendMovementMessage()
        end
    end
    
    if key == "q" then
        if mp then mp:stop() end
        love.event.quit()
    end
end

function startHost(host_ip)
    if mp:startHost(host_ip) then
        role = "HOST"
        print("Started as host on IP: " .. host_ip)
    else
        print("Failed to start host")
    end
end

function connectToHost(host_ip)
    
    if mp:connectToHost(host_ip) then
        role = "CLIENT"
        print("Connecting to host at: " .. host_ip)
    else
        print("Failed to connect to host at: " .. host_ip)
    end
end

function disconnect()
    if mp then
        mp:stop()
    end
    role = nil
    messages = {}
    input_text = ""
    print("Disconnected")
end

function sendChatMessage()
    if not mp or not role or input_text == "" then
        return
    end
    
    local message = "chat:" .. input_text
    
    if role == "HOST" then
        mp:broadcast(message)
        table.insert(messages, {
            text = input_text,
            peer = "HOST (you)",
            role = "host",
            time = love.timer.getTime()
        })
    elseif role == "CLIENT" then
        mp:sendToServer(message)
        table.insert(messages, {
            text = input_text,
            peer = "CLIENT (you)",
            role = "client", 
            time = love.timer.getTime()
        })
    end
    
    input_text = ""
end

function sendMovementMessage()
    if not mp or not role then
        return
    end
    
    local x, y = love.mouse.getPosition()
    local message = string.format("player_move:%.2f,%.2f", x, y)
    
    if role == "HOST" then
        mp:broadcast(message)
    elseif role == "CLIENT" then
        -- mp:sendToServer(message)
    end
    
    -- print("Sent movement:", x, y)
end