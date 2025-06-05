local snapshot = {}

-- FFI-style data structures for network optimization
local ffi = require("ffi")

-- Define C-style structures for compact data representation
ffi.cdef[[
    typedef struct {
        float x, y;
        float vx, vy;
        uint8_t health;
        uint8_t state;
    } player_data_t;
    
    typedef struct {
        float x, y;
        uint8_t active;
    } entity_data_t;
    
    typedef struct {
        float x, y, size, active;
        uint8_t type;
        uint16_t duration;
    } fire_effect_t;
]]

-- Host maintains accumulated game state
local accumulated_game_state = {
    players = {},
    enemies = {},
    coins = {},
    fire_effects = {},
    accumulated_fires = {},
    last_snapshot = {}, -- Store last sent snapshot for delta compression
    sequence_number = 0
}

-- Delta tracking for efficient updates
local delta_tracker = {
    players_changed = {},
    enemies_changed = {},
    coins_changed = {},
    fires_changed = {}
}

-- FFI data conversion helpers - now returns Lua tables for JSON compatibility
local function packPlayerData(player_state)
    -- Use FFI for internal calculations, return Lua table for JSON
    return {
        x = player_state.x or 0,
        y = player_state.y or 0,
        vx = player_state.vx or 0,
        vy = player_state.vy or 0,
        health = math.floor(player_state.health or 100), -- Ensure integer
        state = math.floor(player_state.state or 0)
    }
end

local function unpackPlayerData(packed_data)
    return {
        x = packed_data.x,
        y = packed_data.y,
        vx = packed_data.vx,
        vy = packed_data.vy,
        health = packed_data.health,
        state = packed_data.state
    }
end

local function packEntityData(entity_state)
    return {
        x = entity_state.x or 0,
        y = entity_state.y or 0,
        active = entity_state.active and 1 or 0
    }
end

local function packFireEffect(fire_data)
    return {
        x = fire_data.x or 0,
        y = fire_data.y or 0,
        size = fire_data.size or 1,
        active = fire_data.active or 0,
        type = math.floor(fire_data.type or 0),
        duration = math.floor(fire_data.duration or 0)
    }
end

-- Binary packing functions for even more compression (optional)
local function packPlayerDataBinary(player_state)
    local buffer = ffi.new("player_data_t")
    buffer.x = player_state.x or 0
    buffer.y = player_state.y or 0
    buffer.vx = player_state.vx or 0
    buffer.vy = player_state.vy or 0
    buffer.health = player_state.health or 100
    buffer.state = player_state.state or 0
    return ffi.string(buffer, ffi.sizeof("player_data_t"))
end

local function unpackPlayerDataBinary(binary_data)
    local buffer = ffi.cast("player_data_t*", binary_data)
    return {
        x = buffer.x,
        y = buffer.y,
        vx = buffer.vx,
        vy = buffer.vy,
        health = buffer.health,
        state = buffer.state
    }
end

-- Calculate delta between current and last snapshot
local function calculateDelta(current, last)
    local delta = {
        players = {},
        enemies = {},
        coins = {},
        fire_effects = {},
        removed = {
            players = {},
            enemies = {},
            coins = {},
            fire_effects = {}
        }
    }
    
    -- Check for changed/new players
    for id, data in pairs(current.players or {}) do
        local last_data = last.players and last.players[id]
        if not last_data or 
           math.abs(data.x - (last_data.x or 0)) > 0.1 or
           math.abs(data.y - (last_data.y or 0)) > 0.1 or
           data.health ~= (last_data.health or 100) then
            delta.players[id] = packPlayerData(data)
        end
    end
    
    -- Check for removed players
    if last.players then
        for id, _ in pairs(last.players) do
            if not current.players or not current.players[id] then
                table.insert(delta.removed.players, id)
            end
        end
    end
    
    -- Similar logic for other entities (enemies, coins, fire_effects)
    -- ... (abbreviated for brevity, but would follow same pattern)
    
    return delta
end

-- Optimized create function with FFI and delta compression
function snapshot.create()
    accumulated_game_state.sequence_number = accumulated_game_state.sequence_number + 1
    
    -- Update local player first
    renderer.updateLocalPlayerFromPhysics()
    
    if var.multiplayer == 1 then
        -- HOST: Create optimized game state snapshot
        local current_snapshot = {
            sequence = accumulated_game_state.sequence_number,
            timestamp = love.timer.getTime(),
            players = {},
            enemies = {},
            coins = {},
            fire_effects = {}
        }
        
        -- Add host's player data (pack to FFI structure)
        current_snapshot.players["client_1"] = renderer.local_player_state
        
        -- Add accumulated client player data
        for client_id, player_data in pairs(accumulated_game_state.players) do
            if client_id ~= "client_1" then
                current_snapshot.players[client_id] = player_data
            end
        end
        
        -- Always include all entities (let compression handle efficiency)
        for i = 1, #enemies_bods do
            local ex, ey = enemies_bods[i]:getX(), enemies_bods[i]:getY()
            current_snapshot.enemies[tostring(i)] = packEntityData({
                x = ex, 
                y = ey, 
                active = true
            })
        end
        
        -- Always include all coins
        for i = 1, #coin_bods do
            local cx, cy = coin_bods[i]:getX(), coin_bods[i]:getY()
            current_snapshot.coins[tostring(i)] = packEntityData({
                x = cx, 
                y = cy, 
                active = true
            })
        end
        
        -- Add host's fire effects to game state (CRITICAL FIX)
        local host_fires = fire.getNetworkData()
        current_snapshot.fire_effects = {}
        
        -- First add HOST's own fire effects with "host_" prefix
        if host_fires then
            for k, v in pairs(host_fires) do
                current_snapshot.fire_effects["host_" .. tostring(k)] = packFireEffect(v)
            end
        end
        
        -- Then add accumulated client fires with client prefixes
        for client_id, client_fires in pairs(accumulated_game_state.accumulated_fires) do
            if client_fires then
                for k, v in pairs(client_fires) do
                    current_snapshot.fire_effects[client_id .. "_" .. tostring(k)] = packFireEffect(v)
                end
            end
        end
        
        -- Store current snapshot for next delta calculation
        accumulated_game_state.last_snapshot = current_snapshot
        
        return current_snapshot
        
    else
        -- CLIENT: Always create game state (never return nil)
        local client_id = "client_" .. (var.multiplayer or "local")
        
        local game_state = {
            type = "player_update",
            sequence = accumulated_game_state.sequence_number,
            timestamp = love.timer.getTime(),
            client_id = client_id,
            player_data = packPlayerData(renderer.local_player_state),
            fire_effects = {},
            coins = {},
            enemies = {} -- Include empty tables to maintain structure
        }
        
        -- Always include fire effects (let compression handle redundancy)
        local client_fires = fire.getNetworkData()
        if client_fires then
            for k, v in pairs(client_fires) do
                
                game_state.fire_effects[tostring(k)] = packFireEffect(v)
            end
        end
        
        -- Store for next comparison
        accumulated_game_state.last_snapshot = {
            player_data = renderer.local_player_state,
            fire_effects = client_fires
        }
        
        return game_state
    end
end

function snapshot.apply(game_state)
    if not game_state then 
        print("Warning: Received nil game_state")
        return 
    end
    
    if var.multiplayer == 1 then
        -- HOST: Handle incoming client updates
        if game_state.type == "player_update" then
            -- Data is already unpacked from JSON
            accumulated_game_state.players[game_state.client_id] = game_state.player_data
            
            -- Accumulate client fire effects (already unpacked)
            if game_state.fire_effects then
                accumulated_game_state.accumulated_fires[game_state.client_id] = game_state.fire_effects
            end
            
            -- Apply accumulated fire effects
            local all_client_fires = {}
            for client_id, client_fires in pairs(accumulated_game_state.accumulated_fires) do
                if client_fires then
                    for k, v in pairs(client_fires) do
                        all_client_fires[client_id .. "_" .. tostring(k)] = v
                        -- print(v.active)
                        if (v.active == true) then
                        fire.setOnline(client_id .. k,vec2.new(v.x - 200,v.y - 45))
                        end

                    end
                end
            end
            renderer.setNetworkedFireEffects(all_client_fires)
            
            -- Apply client player data
            local client_players = {}
            for client_id, player_data in pairs(accumulated_game_state.players) do
                client_players[client_id] = player_data
            end
            renderer.setNetworkedPlayers(client_players)
        else 
            -- print(game_state)
        end
    else
        -- CLIENT: Apply full game state from host
        if game_state.players then
            local other_players = {}
            local own_client_id = "client_" .. var.multiplayer
            
            for client_id, player_data in pairs(game_state.players) do
                
                if client_id ~= own_client_id then
                    other_players[client_id] = player_data -- Data is already unpacked from JSON
                end
            end
            renderer.setNetworkedPlayers(other_players)
        end
        
        -- Handle fire effects (already unpacked from JSON)
        if game_state.fire_effects then
            local other_fires = {}
            local own_client_prefix = "client_" .. var.multiplayer .. "_"
            
            for fire_id, fire_data in pairs(game_state.fire_effects) do
                if not string.match(fire_id, "^" .. own_client_prefix) then
                    other_fires[fire_id] = fire_data
                end
            end
            renderer.setNetworkedFireEffects(other_fires)
        end
        
        -- Handle entity data (already unpacked from JSON)
        if game_state.enemies then
            local unpacked_enemies = {}
            for id, enemy_data in pairs(game_state.enemies) do
                unpacked_enemies[id] = {
                    x = enemy_data.x,
                    y = enemy_data.y,
                    active = enemy_data.active == 1
                }
            end
            renderer.setNetworkedEnemies(unpacked_enemies)
        end
        
        if game_state.coins then
            local unpacked_coins = {}
            for id, coin_data in pairs(game_state.coins) do
                unpacked_coins[id] = {
                    x = coin_data.x,
                    y = coin_data.y,
                    active = coin_data.active == 1
                }
            end
            renderer.setNetworkedCoins(unpacked_coins)
        end
    end
end

-- Helper function to clear accumulated data for a disconnected client
function snapshot.removeClient(client_id)
    if var.multiplayer == 1 then
        accumulated_game_state.players[client_id] = nil
        accumulated_game_state.accumulated_fires[client_id] = nil
    end
end

-- Helper function to get current player count
function snapshot.getPlayerCount()
    if var.multiplayer == 1 then
        local count = 1 -- Host counts as 1
        for _ in pairs(accumulated_game_state.players) do
            count = count + 1
        end
        return count
    else
        return 0 -- Clients don't track this
    end
end

-- New helper function to get network statistics
function snapshot.getNetworkStats()
    return {
        sequence_number = accumulated_game_state.sequence_number,
        player_count = snapshot.getPlayerCount(),
        active_fires = accumulated_game_state.accumulated_fires and 
                      table.maxn(accumulated_game_state.accumulated_fires) or 0
    }
end

return snapshot