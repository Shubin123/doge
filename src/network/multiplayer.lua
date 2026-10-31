-- multiplayer.lua - Socket-based LAN Multiplayer Module using TCP
--
-- luasocket is not present in every LÖVE distribution the game ships to --
-- notably love.js (the web/wasm build), which has no TCP sockets at all.
-- main.lua requires this module unconditionally, so a hard `require "socket"`
-- would take the whole game down on those platforms before it drew a frame.
-- Degrade instead: without sockets the module loads, single-player runs
-- normally, and only the host/join entry points refuse.
local ok, socket = pcall(require, "socket")
if not ok then
    socket = nil
end

local multiplayer = {}
multiplayer.__index = multiplayer

-- Snapshots per second each side sends. Every snapshot replaces the last, so
-- a connection still draining an older one just skips the next.
multiplayer.SEND_RATE = 20
-- Bytes a connection may have queued before snapshots to it are skipped
local BACKLOG_LIMIT = 256 * 1024

-- Outgoing data for one socket: whole messages queued, sent as far as the
-- socket takes each frame. A non-blocking send that times out partway used
-- to drop the rest of the message, which broke the newline framing of
-- everything after it.
local function newConnection(sock)
    return { socket = sock, queue = {}, head = 1, sent = 0, queued = 0, buffer = "" }
end

local function enqueue(conn, message)
    conn.queue[#conn.queue + 1] = message .. "\n"
    conn.queued = conn.queued + #message + 1
end

-- Send what the socket will take. Returns false once it's closed.
local function flush(conn)
    while conn.queue[conn.head] do
        local data = conn.queue[conn.head]
        local last, err, partial = conn.socket:send(data, conn.sent + 1)
        last = last or partial
        if last and last > conn.sent then
            conn.queued = conn.queued - (last - conn.sent)
            conn.sent = last
        end
        if conn.sent >= #data then
            conn.queue[conn.head] = nil
            conn.head = conn.head + 1
            conn.sent = 0
        elseif err == "closed" then
            return false
        else
            return true -- the socket's full (or still connecting): rest next frame
        end
    end
    conn.queue, conn.head = {}, 1
    return true
end

-- Every complete (newline-terminated) message received so far
local function receive(conn, onMessage)
    local data, err, partial = conn.socket:receive("*a")
    local chunk = data or partial
    if chunk and chunk ~= "" then
        conn.buffer = conn.buffer .. chunk
        local start = 1
        while true do
            local newline = conn.buffer:find("\n", start, true)
            if not newline then break end
            if newline > start then
                onMessage(conn.buffer:sub(start, newline - 1))
            end
            start = newline + 1
        end
        conn.buffer = conn.buffer:sub(start)
    end
    return err ~= "closed"
end

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
    if not socket then
        print("multiplayer: no luasocket on this platform (web/wasm has none) -- staying offline")
        return false
    end

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
    if not socket then
        print("multiplayer: no luasocket on this platform (web/wasm has none) -- staying offline")
        return false
    end

    if self.server_socket or self.client_socket then
        self:stop()
    end

    self.address = host_address or self.address
    self.client_socket = socket.tcp()
    if self.client_socket then
        self.client_socket:settimeout(0) -- Non-blocking
        self.client_socket:setoption("tcp-nodelay", true)
        local success, err = self.client_socket:connect(self.address, self.port)
        
        -- In non-blocking mode, connect() may return "timeout" which means connection is in progress
        -- (until it's made, sends fail and stay queued)
        if success or err == "timeout" then
            self.is_client = true
            self.server = newConnection(self.client_socket)
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
        client_socket:setoption("tcp-nodelay", true)
        local ip, port = client_socket:getpeername()
        local peer_key = ip .. ":" .. port
        print("Client connected: " .. peer_key)
        local peer_info = newConnection(client_socket)
        peer_info.ip, peer_info.port = ip, port
        peer_info.connect_time = love and love.timer.getTime() or os.time()
        self.connected_peers[peer_key] = peer_info
        self:_callConnectionHandler("connect", peer_key)
    end

    -- Send what's queued and handle messages from connected clients
    local disconnected_peers = {}
    for peer_key, peer_info in pairs(self.connected_peers) do
        local open = flush(peer_info) and receive(peer_info, function(message)
            self:_handleMessage(message, peer_key, "host")
        end)
        if not open then
            print("Client disconnected: " .. peer_key)
            peer_info.socket:close()
            table.insert(disconnected_peers, peer_key)
        end
    end

    for _, peer_key in ipairs(disconnected_peers) do
        local client_id = self.connected_peers[peer_key].client_id
        self.connected_peers[peer_key] = nil
        self:_callConnectionHandler("disconnect", client_id or peer_key)
    end
end

-- Client update logic
function multiplayer:_updateClient()
    if not self.server then return end

    local open = flush(self.server) and receive(self.server, function(message)
        self:_handleMessage(message, "server", "client")
    end)
    if not open then
        print("Disconnected from server")
        self.client_socket:close()
        self.client_socket = nil
        self.server = nil
        self.is_client = false
        self:_callConnectionHandler("disconnect", nil)
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
        enqueue(peer_info, message)
        return true
    end
    return false
end

-- Send message to all connected peers (host only). A `droppable` message
-- (a snapshot, which the next one replaces) skips peers still draining a
-- backlog.
function multiplayer:broadcast(message, channel, exclude_peer, droppable)
    if self.fallback_mode then
        print("Cannot broadcast in fallback mode")
        return false
    end

    if not self.is_host then
        return false
    end

    local sent_count = 0
    for peer_key, peer_info in pairs(self.connected_peers) do
        if peer_key ~= exclude_peer and peer_info.socket
            and not (droppable and peer_info.queued > BACKLOG_LIMIT) then
            enqueue(peer_info, message)
            sent_count = sent_count + 1
        end
    end
    return sent_count > 0
end

-- Send message to server (client only)
function multiplayer:sendToServer(message, channel, droppable)
    if self.fallback_mode then
        print("Cannot send to server in fallback mode")
        return false
    end

    if not self.is_client or not self.server then
        return false
    end
    if droppable and self.server.queued > BACKLOG_LIMIT then
        return false
    end

    enqueue(self.server, message)
    return true
end

-- Send this side's snapshot, multiplayer.SEND_RATE times a second
local sendTimer = 0
function multiplayer.sendMovementMessage(dt)
    if not mp or mp.fallback_mode then
        return
    end
    sendTimer = sendTimer + (dt or 0)
    if sendTimer < 1 / multiplayer.SEND_RATE then
        return
    end
    sendTimer = sendTimer % (1 / multiplayer.SEND_RATE)
    if var.multiplayer == 1 and next(mp.connected_peers) == nil then
        return -- nobody to send to
    end

    local game_state = snapshot.create()
    local json_string = json.encode(game_state)

    if var.multiplayer == 1 then
        mp:broadcast(json_string, nil, nil, true)
    else
        mp:sendToServer(json_string, nil, true)
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
        if not (game_state.client_id and game_state.player_data) then
            return
        end
        local peer_info = self.connected_peers[peer]
        if peer_info then
            peer_info.client_id = game_state.client_id -- to forget them when they leave
        end
        local player_id = tonumber(game_state.client_id:match("%d+$"))
        if not player.online.bodies[player_id] then
            player.online.bodies[player_id] = love.physics.newBody(world, game_state.player_data.x, game_state.player_data.y)
            player.online.fixture = love.physics.newFixture(player.online.bodies[player_id], player.shape)
            player.online.fixture:setGroupIndex(-1)
            player.online.health[player_id] = player.maxHealth
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
    self.server = nil
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
        print("host be aware:", peer, "has joined!")
    end)

    -- The host gets the client's id ("client_2"), or its address if it left
    -- before sending anything; a client gets nil
    mp:onConnection("disconnect", function(client_id)
        print("Disconnection event:", client_id)
        if mp.is_host and client_id then
            snapshot.removeClient(client_id)
        end
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
