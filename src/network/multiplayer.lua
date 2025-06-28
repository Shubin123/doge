-- multiplayer.lua - Socket-based LAN Multiplayer Module using TCP
local socket = require "socket"

local multiplayer = {}
multiplayer.__index = multiplayer

-- Create new multiplayer instance
function multiplayer.new(config)
    local self = setmetatable({}, multiplayer)

    -- Configuration
    self.config = config or {}
    self.port = self.config.port or 6750
    self.address = self.config.address or "localhost"
    self.timeout = self.config.timeout or 100

    -- State
    self.is_host = false
    self.is_client = false
    self.server_socket = nil -- TCP server socket (host only)
    self.client_socket = nil -- TCP client socket (client only)
    self.connected_peers = {} -- For host to track clients {socket, ip, port, connect_time}
    self.message_handlers = {}
    self.connection_handlers = {}
    self.fallback_mode = false -- Fallback for unsupported environments

    return self
end

-- Start as host (server)
function multiplayer:startHost(ip)
    if self.server_socket or self.client_socket then
        self:stop()
    end

    local address = ip or "*"
    self.server_socket = socket.tcp()
    if self.server_socket then
        self.server_socket:settimeout(0) -- Non-blocking
        local success, err = self.server_socket:bind(address, self.port)
        if success then
            local listen_success, listen_err = self.server_socket:listen(32) -- Allow up to 32 pending connections
            if listen_success then
                self.is_host = true
                print("Host started on " .. address .. ":" .. self.port)
                return true
            else
                print("Failed to listen on " .. address .. ":" .. self.port .. ": " .. tostring(listen_err))
                self.server_socket:close()
                self.server_socket = nil
                self.fallback_mode = true
                print("Falling back to mock networking mode (host)")
                return false
            end
        else
            print("Failed to bind host to " .. address .. ":" .. self.port .. ": " .. tostring(err))
            self.server_socket:close()
            self.server_socket = nil
            self.fallback_mode = true
            print("Falling back to mock networking mode (host)")
            return false
        end
    else
        print("Failed to create TCP socket for host")
        self.fallback_mode = true
        print("Falling back to mock networking mode (host)")
        return false
    end
end

-- Connect as client
function multiplayer:connectToHost(host_address)
    if self.server_socket or self.client_socket then
        self:stop()
    end

    self.address = host_address or self.address
    self.client_socket = socket.tcp()
    if self.client_socket then
        self.client_socket:settimeout(0) -- Non-blocking
        local success, err = self.client_socket:connect(self.address, self.port)
        
        -- In non-blocking mode, connect() may return "timeout" which means connection is in progress
        if success or err == "timeout" then
            self.is_client = true
            print("Attempting to connect to " .. self.address .. ":" .. self.port)
            return true
        else
            print("Failed to connect to " .. self.address .. ":" .. self.port .. ": " .. tostring(err))
            self.client_socket:close()
            self.client_socket = nil
            self.fallback_mode = true
            print("Falling back to mock networking mode (client)")
            return false
        end
    else
        print("Failed to create TCP socket for client")
        self.fallback_mode = true
        print("Falling back to mock networking mode (client)")
        return false
    end
end

-- Update networking (call this every frame)
function multiplayer:update()
    if self.fallback_mode then
        -- In fallback mode, do nothing or simulate minimal networking
        return
    end

    if self.is_host then
        self:_updateHost()
    end

    if self.is_client then
        self:_updateClient()
    end
end

-- Host update logic
function multiplayer:_updateHost()
    if not self.server_socket then return end

    -- Accept new connections
    local client_socket = self.server_socket:accept()
    if client_socket then
        client_socket:settimeout(0) -- Make client socket non-blocking
        local ip, port = client_socket:getpeername()
        local peer_key = ip .. ":" .. port
        print("Client connected: " .. peer_key)
        self.connected_peers[peer_key] = {
            socket = client_socket,
            ip = ip,
            port = port,
            connect_time = love and love.timer.getTime() or os.time(),
            buffer = "" -- Buffer for incomplete messages
        }
        self:_callConnectionHandler("connect", peer_key)
    end

    -- Handle messages from connected clients
    local disconnected_peers = {}
    for peer_key, peer_info in pairs(self.connected_peers) do
        local data, err, partial = peer_info.socket:receive("*a")
        
        if err == "closed" then
            print("Client disconnected: " .. peer_key)
            peer_info.socket:close()
            table.insert(disconnected_peers, peer_key)
            self:_callConnectionHandler("disconnect", peer_key)
        elseif data or partial then
            -- Append received data to buffer
            peer_info.buffer = peer_info.buffer .. (data or partial or "")
            
            -- Process complete messages (assuming messages are newline-delimited)
            while true do
                local newline_pos = peer_info.buffer:find("\n")
                if not newline_pos then break end
                
                local message_data = peer_info.buffer:sub(1, newline_pos - 1)
                peer_info.buffer = peer_info.buffer:sub(newline_pos + 1)
                
                if message_data ~= "" then
                    self:_handleMessage(message_data, peer_key, "host")
                end
            end
        end
    end

    -- Remove disconnected peers
    for _, peer_key in ipairs(disconnected_peers) do
        self.connected_peers[peer_key] = nil
    end

    -- Reduce CPU usage
    socket.sleep(0.01)
end

-- Client update logic
function multiplayer:_updateClient()
    if not self.client_socket then return end

    -- Initialize buffer if it doesn't exist
    if not self.client_buffer then
        self.client_buffer = ""
    end

    local data, err, partial = self.client_socket:receive("*a")
    
    if err == "closed" then
        print("Disconnected from server")
        self.client_socket:close()
        self.client_socket = nil
        self.is_client = false
        self:_callConnectionHandler("disconnect", nil)
        return
    elseif data or partial then
        -- Append received data to buffer
        self.client_buffer = self.client_buffer .. (data or partial or "")
        
        -- Process complete messages (newline-delimited)
        while true do
            local newline_pos = self.client_buffer:find("\n")
            if not newline_pos then break end
            
            local message_data = self.client_buffer:sub(1, newline_pos - 1)
            self.client_buffer = self.client_buffer:sub(newline_pos + 1)
            
            if message_data ~= "" then
                self:_handleMessage(message_data, "server", "client")
            end
        end
    end
end

-- Send message to specific peer (host only)
function multiplayer:sendToPeer(peer, message, channel)
    if self.fallback_mode then
        print("Cannot send to peer in fallback mode")
        return false
    end

    if not self.is_host or not peer then
        return false
    end

    local peer_info = self.connected_peers[peer]
    if peer_info and peer_info.socket then
        local success, err = peer_info.socket:send(message .. "\n")
        if success then
            return true
        else
            print("Failed to send to peer " .. peer .. ": " .. tostring(err))
            return false
        end
    end
    return false
end

-- Send message to all connected peers (host only)
function multiplayer:broadcast(message, channel, exclude_peer)
    if self.fallback_mode then
        print("Cannot broadcast in fallback mode")
        return false
    end

    if not self.is_host then
        return false
    end

    local sent_count = 0
    for peer_key, peer_info in pairs(self.connected_peers) do
        if peer_key ~= exclude_peer and peer_info.socket then
            local success, err = peer_info.socket:send(message .. "\n")
            if success then
                sent_count = sent_count + 1
            else
                print("Failed to broadcast to peer " .. peer_key .. ": " .. tostring(err))
            end
        end
    end
    return sent_count > 0
end

-- Send message to server (client only)
function multiplayer:sendToServer(message, channel)
    if self.fallback_mode then
        print("Cannot send to server in fallback mode")
        return false
    end

    if not self.is_client or not self.client_socket then
        return false
    end

    local success, err = self.client_socket:send(message .. "\n")
    if success then
        return true
    else
        print("Failed to send to server: " .. tostring(err))
        return false
    end
end

-- Handle sending movement messages
function multiplayer.sendMovementMessage()
    if not mp or mp.fallback_mode then
        if mp and mp.fallback_mode then
            print("Cannot send movement message in fallback mode")
        end
        return
    end

    local game_state = snapshot.create()
    local json_string = json.encode(game_state)

    if var.multiplayer == 1 then
        mp:broadcast(json_string)
    else
        mp:sendToServer(json_string)
    end
end

-- Handle incoming messages
function multiplayer:_handleMessage(data, peer, role)
    local decode_success, message = pcall(json.decode, data)
    if not decode_success then
        print("Failed to decode JSON from " .. tostring(peer))
        return
    end
    
    if message.type == "command_block" then
        command.receiveCommandBlock(message.block)
        return
    end
    
    local game_state = message
    
    if role == "client" then
        snapshot.apply(game_state)
    end
    
    if role == "host" then
        local player_id = tonumber(string.sub(game_state.client_id, #game_state.client_id))
        if not player.online.bodies[player_id] then
            player.online.bodies[player_id] = love.physics.newBody(world, game_state.player_data.x, game_state.player_data.y)
            player.online.fixture = love.physics.newFixture(player.online.bodies[player_id], player.shape)
            player.online.fixture:setGroupIndex(-1)
            player.online.health[player_id] = 100
        end

        player.online.bodies[player_id]:setPosition(game_state.player_data.x, game_state.player_data.y)
        snapshot.apply(game_state)
    end
end

-- Register message handler
function multiplayer:onMessage(pattern, handler)
    self.message_handlers[pattern] = handler
end

-- Register connection handler
function multiplayer:onConnection(event_type, handler)
    self.connection_handlers[event_type] = handler
end

-- Call connection handlers
function multiplayer:_callConnectionHandler(event_type, peer)
    if self.connection_handlers[event_type] then
        self.connection_handlers[event_type](peer)
    end
end

-- Get connection info
function multiplayer:getConnectionInfo()
    local info = {
        is_host = self.is_host,
        is_client = self.is_client,
        peer_count = 0,
        connected_peers = {}
    }

    if self.is_host then
        for peer, peer_info in pairs(self.connected_peers) do
            info.peer_count = info.peer_count + 1
            table.insert(info.connected_peers, {
                peer = tostring(peer),
                connect_time = peer_info.connect_time
            })
        end
    elseif self.is_client then
        info.connected_to_server = self.client_socket ~= nil
    end

    return info
end

-- Stop networking
function multiplayer:stop()
    -- Close client connections if host
    if self.is_host and self.connected_peers then
        for peer_key, peer_info in pairs(self.connected_peers) do
            if peer_info.socket then
                peer_info.socket:close()
            end
        end
        self.connected_peers = {}
    end

    -- Close server socket if host
    if self.server_socket then
        self.server_socket:close()
        self.server_socket = nil
    end

    -- Close client socket if client
    if self.client_socket then
        self.client_socket:close()
        self.client_socket = nil
    end

    self.is_host = false
    self.is_client = false
    self.connected_peers = {}
    self.client_buffer = nil
    self.fallback_mode = false

    print("Networking stopped")
end

-- Utility: Create JSON message
function multiplayer:createMessage(msg_type, data)
    return {
        type = msg_type,
        data = data,
        timestamp = love and love.timer.getTime() or os.time()
    }
end

-- Load multiplayer settings
function multiplayer.load()
    mp = multiplayer.new({
        port = 6750,
        timeout = 200
    })

    mp:onMessage("player_move", function(message, peer, role)
        print("Player moved:", message, "from", peer)
    end)

    mp:onConnection("connect", function(peer)
        print("Connection event:", peer)
        if not mp.is_host then
            mp:sendToPeer(peer, "Welcome to the server!")
        else
            print("host be aware:", peer, "has joined!")
        end
    end)

    mp:onConnection("disconnect", function(peer)
        print("Disconnection event:", peer)
    end)

    if var.multiplayer then
        local ip = arg[3] and arg[3] or "localhost"
        if var.multiplayer == 1 then
            mp:startHost(ip)
        else
            mp:connectToHost(ip)
        end
    end
end

return multiplayer