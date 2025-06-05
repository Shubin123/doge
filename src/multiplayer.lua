-- multiplayer.lua - ENet LAN multiplayer Module
local enet = require("enet")

local multiplayer = {}
multiplayer.__index = multiplayer

-- Create new multiplayer instance
function multiplayer.new(config)
    local self = setmetatable({}, multiplayer)

    -- Configuration
    self.config = config or {}

    self.port = self.config.port or 6750
    self.max_peers = self.config.max_peers or 32
    self.timeout = self.config.timeout or 100

    -- State
    self.is_host = false
    self.is_client = false
    self.host = nil
    self.client = nil
    self.server_peer = nil
    self.connected_peers = {}
    self.message_handlers = {}
    self.connection_handlers = {}

    return self
end

-- Start as host (server)
function multiplayer:startHost(ip)
    if self.host then
        self:stop()
    end

    local address = ip .. ":" .. self.port
    self.host = enet.host_create(address, self.max_peers)

    if self.host then
        self.is_host = true
        print("Host started on " .. address)
        return true
    else
        print("Failed to start host")
        return false
    end
end

-- Connect as client
function multiplayer:connectToHost(host_address)
    if self.client then
        self:stop()
    end

    host_address = host_address
    local address = host_address .. ":" .. self.port

    self.client = enet.host_create()
    if self.client then
        self.server_peer = self.client:connect(address)
        if self.server_peer then
            self.is_client = true
            print("Attempting to connect to " .. address)
            return true
        else
            print("Failed to create connection to " .. address)
            self.client = nil
            return false
        end
    else
        print("Failed to create client")
        return false
    end
end

-- Update networking (call this every frame)
function multiplayer:update()
    if self.is_host then
        self:_updateHost()
    end

    if self.is_client then
        self:_updateClient()
    end
end

-- Host update logic
function multiplayer:_updateHost()
    if not self.host then return end

    local event = self.host:service(self.timeout)

    while event do
        if event.type == "connect" then
            print("Client connected: " .. tostring(event.peer))
            self.connected_peers[event.peer] = {
                peer = event.peer,
                connect_time = love and love.timer.getTime() or os.time()
            }
            self:_callConnectionHandler("connect", event.peer)
        elseif event.type == "disconnect" then
            print("Client disconnected: " .. tostring(event.peer))
            self.connected_peers[event.peer] = nil
            self:_callConnectionHandler("disconnect", event.peer)
        elseif event.type == "receive" then
            self:_handleMessage(event.data, event.peer, "host")
        end

        event = self.host:service(0) -- Check for more events without waiting
    end
end

-- Client update logic
function multiplayer:_updateClient()
    -- if not self.client then return end

    local event = self.client:service(self.timeout)
    -- print(event)
    while event do
        if event.type == "connect" then
            print("Connected to server")
            self:_callConnectionHandler("connect", event.peer)
        elseif event.type == "disconnect" then
            print("Disconnected from server")
            self.server_peer = nil
            self:_callConnectionHandler("disconnect", event.peer)
        elseif event.type == "receive" then
            self:_handleMessage(event.data, event.peer, "client")
        end

        event = self.client:service(0)
    end
end

-- Send message to specific peer (host only)
function multiplayer:sendToPeer(peer, message, channel)
    if not self.is_host or not peer then
        return false
    end

    channel = channel or 0
    peer:send(message, channel)
    return true
end

-- Send message to all connected peers (host only)
function multiplayer:broadcast(message, channel, exclude_peer)
    if not self.is_host then
        return false
    end

    channel = channel or 0
    local sent_count = 0

    for peer, peer_info in pairs(self.connected_peers) do
        if peer ~= exclude_peer then
            peer:send(message, channel)
            sent_count = sent_count + 1
        end
    end

    return sent_count
end

-- Send message to server (client only)
function multiplayer:sendToServer(message, channel)
    if not self.is_client or not self.server_peer then
        return false
    end

    channel = channel or 0
    self.server_peer:send(message, channel)
    return true
end



function multiplayer.sendMovementMessage()
    game_state = snapshot.create()
    
    -- Convert to JSON first, then compress with maximum compression
    local json_string = json.encode(game_state)
    local compressed_data = love.data.compress("string", "zlib", json_string, 9)  -- 9 = max compression level
    
    if var.multiplayer == 1 then
        mp:broadcast(compressed_data)
    else
        -- client info to send to server -- doesnt work correctly for more than one client
        mp:sendToServer(compressed_data)
    end
end

-- Handle incoming messages
function multiplayer:_handleMessage(data, peer, role)
    -- Decompress the data, then decode JSON
    local decompressed_data = love.data.decompress("string", "zlib", data)
    local game_state = json.decode(decompressed_data)
    
    if role == "client" then
        -- print("")
        -- print(data)
        -- debug.debug()
        -- renderer.applyGameStateSnapshot(game_state)
        snapshot.apply(game_state)
    end
    
    if role == "host" then                      
        -- print(mymath.len(game_state))
        -- for k,v in pairs(game_state.player_data) do print(k,v) end
        player.online.body:setPosition(game_state.player_data.x,game_state.player_data.y) -- assuming one online player (starting from 2)
                      
        snapshot.apply(game_state)
    end
    
    -- print(string.format("[%s] Received: %s from %s",
    --       role:upper(), tostring(json.decode(data)), tostring(peer)))
    -- Call registered message handlers
    -- for pattern, handler in pairs(self.message_handlers) do
    --     if type(message) == "string" and message:match(pattern) then
    --         handler(message, peer, role)
    --     elseif type(message) == "table" and message.type and message.type:match(pattern) then
    --         handler(message, peer, role)
    --     end
    -- end
    
    -- -- Call generic message handler if exists
    -- if self.message_handlers["*"] then
    --     self.message_handlers["*"](message, peer, role)
    -- end
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
        info.connected_to_server = self.server_peer ~= nil
    end

    return info
end

-- Stop networking
function multiplayer:stop()
    if self.host then
        self.host:destroy()
        self.host = nil
    end

    if self.client then
        if self.server_peer then
            self.server_peer:disconnect()
        end
        self.client:destroy()
        self.client = nil
        self.server_peer = nil
    end

    self.is_host = false
    self.is_client = false
    self.connected_peers = {}

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

-- Utility: Send JSON message
-- function multiplayer:sendJSON(target, message, channel)
--     local json_str = tostring(message)
--     if type(message) == "table" then
--         -- Simple JSON encoding (you might want to use a proper JSON library)
--         local success, json_lib = pcall(function() return require("json") end)
--         if success and json_lib then
--             json_str = json_lib.encode(message)
--         else
--             -- Fallback: simple table serialization for basic cases
--             if message.type and message.data then
--                 json_str = string.format('{"type":"%s","data":"%s"}',
--                     tostring(message.type), tostring(message.data))
--             else
--                 json_str = tostring(message)
--             end
--         end
--     end

--     if target == "server" then
--         return self:sendToServer(json_str, channel)
--     elseif target == "broadcast" then
--         return self:broadcast(json_str, channel)
--     elseif type(target) == "userdata" then -- peer object
--         return self:sendToPeer(target, json_str, channel)
--     end

--     return false
-- end

function multiplayer.load()
    mp = multiplayer.new({
        port = 6750,
        max_peers = 8,
        timeout = 10 --IMPORANT !!!
    })



    mp:onMessage("player_move", function(message, peer, role)
        print("Player moved:", message, "from", peer)
    end)

    -- Set up connection handlers
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
        -- print(arg[3])
    local ip = arg[3] and arg[3] or "localhost"

    if var.multiplayer == 1  then
        mp:startHost(ip)
    else
        mp:connectToHost(ip)
    end

    end
end






return multiplayer
