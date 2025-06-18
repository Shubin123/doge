local snapshot = {}
local json = require("util/json")

-- Store last created snapshot for delta comparison
local last_created_snapshot = nil
-- Store last full game state for client to merge with delta updates
local last_full_game_state = nil
-- Counter for forcing full updates periodically for host
local frame_counter = 0
local full_update_interval = 5 -- Send full update every 5 frames to prevent flashing of stationary objects

-- Host maintains accumulated game state
local accumulated_game_state = {
    players = {},
    enemies = {},
    coins = {},
    fire_effects = {},
    bullets = {},
    rockets = {},
    command_blocks = {},
    arches = {},
    trees = {},
    map_data = {},
    bosses = {},  -- Add boss tracking
    cars = {},    -- Add car tracking
    accumulated_fires = {}, -- Track fire effects from all clients
    accumulated_bullets = {},
    accumulated_rockets = {},
    accumulated_command_blocks = {}
}

function snapshot.create()
    local full_game_state = {}
    
    -- Update local player first
    renderer.updateLocalPlayerFromPhysics()
    
    if var.multiplayer == 1 then
        -- HOST: Create full game state snapshot
        full_game_state = {
            players = {},
            enemies = {},
            coins = {},
            fire_effects = {},
            bullets = {},
            rockets = {},
            command_blocks = {},
            arches = {},
            trees = {},
            map_data = {},
            bosses = {},  -- Add boss data
            cars = {}     -- Add car data
        }
        
        -- Add host's player data
        full_game_state.players["client_1"] = renderer.local_player_state
        
        -- Add all accumulated client player data
        for client_id, player_data in pairs(accumulated_game_state.players) do
            if client_id ~= "client_1" then -- Don't overwrite host data
                full_game_state.players[client_id] = player_data
                local client_idNum = tonumber(string.sub(client_id,#client_id))
                full_game_state.players[client_id].health = player.online.health[client_idNum]
            end
        end
        
        -- Collect enemy data from physics bodies
        for i = 1, #enemies_bods do
            local ex, ey = enemies_bods[i]:getX(), enemies_bods[i]:getY()
            full_game_state.enemies[tostring(i)] = {
                x = ex,
                y = ey,
                active = true
            }
        end
        
        -- Collect boss data
        if boss then
            full_game_state.bosses = boss.getNetworkData()
        end
        
        -- Collect car data from host
        full_game_state.cars = {}
        if car then
            local hostCarData = car.getNetworkData()
            for k, v in pairs(hostCarData) do
                full_game_state.cars[tostring(k)] = v
            end
        end
        
        -- Collect coin data from physics bodies
        for i = 1, #coin_bods do
            local cx, cy = coin_bods[i]:getX(), coin_bods[i]:getY()
            full_game_state.coins[tostring(i)] = {
                x = cx,
                y = cy,
                active = true
            }
        end
        
        -- Add host's fire effects
        local host_fires = fire.getNetworkData()
        full_game_state.fire_effects = {}
        
        -- Convert host fires to string keys and add them
        if host_fires then
            for k, v in pairs(host_fires) do
                full_game_state.fire_effects["host_" .. tostring(k)] = v
            end
        end
        
        -- Add accumulated client fires with string keys
        for client_id, client_fires in pairs(accumulated_game_state.accumulated_fires) do
            if client_fires then
                for k, v in pairs(client_fires) do
                    full_game_state.fire_effects[client_id .. "_" .. tostring(k)] = v
                end
            end
        end

        -- Add host's bullets and rockets
        local host_bullets = bullet.getNetworkData()
        if host_bullets then
            for k, v in pairs(host_bullets) do
                full_game_state.bullets["host_" .. tostring(k)] = v
            end
        end

        -- Add accumulated client bullets and rockets
        for client_id, client_bullets in pairs(accumulated_game_state.accumulated_bullets) do
            if client_bullets then
                for k, v in pairs(client_bullets) do
                    full_game_state.bullets[client_id .. "_" .. tostring(k)] = v
                end
            end
        end

        for client_id, client_rockets in pairs(accumulated_game_state.accumulated_rockets) do
            if client_rockets then
                for k, v in pairs(client_rockets) do
                    full_game_state.rockets[client_id .. "_" .. tostring(k)] = v
                end
            end
        end

        full_game_state.map_data = map.createSaveDataSmall() -- just arches and trees for the ground layer

        -- Collect host's command blocks (which now includes accumulated client blocks)
        full_game_state.command_blocks = command.getCommandBlocks()

    else
        -- CLIENT: Create minimal update with player data and fire effects
        full_game_state = {
            type = "player_update",
            client_id = "client_" .. var.multiplayer,
            player_data = renderer.local_player_state,
            fire_effects = fire.getNetworkData(), -- Clients send their fire effects
            bullets = bullet.getNetworkData(),
            command_blocks = command.getCommandBlocks(),
            boss_spawn_request = boss and boss.getPendingSpawnRequest() or nil,  -- Add boss spawn request field
            cars =  {}  -- Clients send their car data
        }
    end

    -- Always send full state for host to prevent flashing issues on client
    local delta_game_state = full_game_state
    if var.multiplayer ~= 1 then
        -- For client, create minimal update
        delta_game_state = {
            type = "player_update",
            client_id = full_game_state.client_id,
            player_data = full_game_state.player_data
        }
        if full_game_state.fire_effects and (not last_created_snapshot or json.encode(full_game_state.fire_effects) ~= json.encode(last_created_snapshot.fire_effects or {})) then
            delta_game_state.fire_effects = full_game_state.fire_effects
        end
        if full_game_state.bullets and (not last_created_snapshot or json.encode(full_game_state.bullets) ~= json.encode(last_created_snapshot.bullets or {})) then
            delta_game_state.bullets = full_game_state.bullets
        end
        if full_game_state.command_blocks and (not last_created_snapshot or json.encode(full_game_state.command_blocks) ~= json.encode(last_created_snapshot.command_blocks or {})) then
            delta_game_state.command_blocks = full_game_state.command_blocks
        end
        if full_game_state.boss_spawn_request and (not last_created_snapshot or json.encode(full_game_state.boss_spawn_request or {}) ~= json.encode(last_created_snapshot.boss_spawn_request or {})) then
            delta_game_state.boss_spawn_request = full_game_state.boss_spawn_request
        end
        if full_game_state.cars and (not last_created_snapshot or json.encode(full_game_state.cars) ~= json.encode(last_created_snapshot.cars or {})) then
            delta_game_state.cars = full_game_state.cars
        end
    end

    -- Store the full game state as the last created snapshot for next comparison
    last_created_snapshot = full_game_state
    
    return delta_game_state
end

function snapshot.apply(game_state)
    if var.multiplayer == 1 then
        -- HOST: Handle incoming client updates
        if game_state.type == "player_update" then
            -- Accumulate client player data and fire effects
            if game_state.player_data then
                accumulated_game_state.players[game_state.client_id] = game_state.player_data
            end
            
            -- Accumulate client fire effects
            if game_state.fire_effects then
                accumulated_game_state.accumulated_fires[game_state.client_id] = game_state.fire_effects
            end
            if game_state.bullets then
                accumulated_game_state.accumulated_bullets[game_state.client_id] = game_state.bullets
            end
            if game_state.rockets then
                accumulated_game_state.accumulated_rockets[game_state.client_id] = game_state.rockets
            end
            if game_state.cars then
                accumulated_game_state.cars[game_state.client_id] = game_state.cars
            end
            if game_state.command_blocks then
                accumulated_game_state.accumulated_command_blocks[game_state.client_id] = game_state.command_blocks
                -- Apply client command blocks to host's command system
                for _, block_data in ipairs(game_state.command_blocks) do
                    command.addBlock(block_data)
                end
                
                -- Update networked command blocks for rendering
                local all_client_command_blocks = {}
                for client_id, client_blocks in pairs(accumulated_game_state.accumulated_command_blocks) do
                    if client_blocks then
                        for _, block_data in ipairs(client_blocks) do
                            table.insert(all_client_command_blocks, block_data)
                        end
                    end
                end
                renderer.setNetworkedCommandBlocks(all_client_command_blocks)
            end
            
            -- Handle boss spawn request from client
            if game_state.boss_spawn_request and boss then
                local request = game_state.boss_spawn_request
                boss.spawn(request.x, request.y)
            end
            
            -- Apply all accumulated fire effects to host's renderer
            local all_client_fires = {}
            for client_id, client_fires in pairs(accumulated_game_state.accumulated_fires) do
                if client_fires then
                    for k, v in pairs(client_fires) do
                        all_client_fires[client_id .. "_" .. tostring(k)] = v
                    end
                end
            end
            renderer.setNetworkedFireEffects(all_client_fires)

            local all_client_bullets = {}
            for client_id, client_bullets in pairs(accumulated_game_state.accumulated_bullets) do
                if client_bullets then
                    for k, v in pairs(client_bullets) do
                        all_client_bullets[client_id .. "_" .. tostring(k)] = v
                    end
                end
            end
            renderer.setNetworkedBullets(all_client_bullets)

            local all_client_rockets = {}
            for client_id, client_rockets in pairs(accumulated_game_state.accumulated_rockets) do
                if client_rockets then
                    for k, v in pairs(client_rockets) do
                        all_client_rockets[client_id .. "_" .. tostring(k)] = v
                    end
                end
            end
            renderer.setNetworkedRockets(all_client_rockets)
            
            -- Create combined player data with only CLIENT players (not host)
            local client_players = {}
            for client_id, player_data in pairs(accumulated_game_state.players) do
                client_players[client_id] = player_data -- Only client players
            end
            
            -- Apply only the client player data (host draws itself locally)
            renderer.setNetworkedPlayers(client_players)
            
            -- Apply car data to host's renderer
            local all_cars = {}
            if car then
                local hostCarData = car.getNetworkData()
                for k, v in pairs(hostCarData) do
                    all_cars[tostring(k)] = v
                end
            end
            renderer.setNetworkedCars(all_cars)
        else
            -- Handle full game state or delta updates
            if game_state.players then
                renderer.setNetworkedPlayers(game_state.players)
            end
        end
    else
        -- CLIENT: Apply full game state or delta updates from host
        -- If this is a full update, store it as the last full state
        if game_state.type == "full_update" or not last_full_game_state then
            last_full_game_state = game_state
        else
            -- Merge delta update with last full state
            for category, data in pairs(game_state) do
                if category ~= "type" then
                    if last_full_game_state[category] then
                        -- Update existing entries and add new ones
                        for key, value in pairs(data) do
                            if value == nil then
                                -- Handle removal of elements
                                last_full_game_state[category][key] = nil
                            else
                                last_full_game_state[category][key] = value
                            end
                        end
                    else
                        -- If category doesn't exist in full state, add it
                        last_full_game_state[category] = data
                    end
                end
            end
        end

        -- Now apply the merged full state to the renderer
        if last_full_game_state.players then
            -- Filter out own player data to avoid drawing self twice
            local other_players = {}
            local own_client_id = "client_" .. var.multiplayer
            
            for client_id, player_data in pairs(last_full_game_state.players) do
                if client_id ~= own_client_id then
                    other_players[client_id] = player_data
                else
                    player.health = player_data.health
                end
            end
            
            renderer.setNetworkedPlayers(other_players)
        end

        if last_full_game_state.fire_effects then
            -- Filter out own fire effects to avoid duplication
            local other_fires = {}
            local own_client_prefix = "client_" .. var.multiplayer .. "_"
            
            for fire_id, fire_data in pairs(last_full_game_state.fire_effects) do
                if not string.match(fire_id, "^" .. own_client_prefix) then
                    other_fires[fire_id] = fire_data
                end
            end
            
            renderer.setNetworkedFireEffects(other_fires)
        end

        if last_full_game_state.bullets then
            local other_bullets = {}
            local own_client_prefix = "client_" .. var.multiplayer .. "_"
            for bullet_id, bullet_data in pairs(last_full_game_state.bullets) do
                if not string.match(bullet_id, "^" .. own_client_prefix) then
                    other_bullets[bullet_id] = bullet_data
                end
            end
            renderer.setNetworkedBullets(other_bullets)
        end

        if last_full_game_state.rockets then
            local other_rockets = {}
            local own_client_prefix = "client_" .. var.multiplayer .. "_"
            for rocket_id, rocket_data in pairs(last_full_game_state.rockets) do
                if not string.match(rocket_id, "^" .. own_client_prefix) then
                    other_rockets[rocket_id] = rocket_data
                end
            end
            renderer.setNetworkedRockets(other_rockets)
        end
        
        if last_full_game_state.enemies then
            renderer.setNetworkedEnemies(last_full_game_state.enemies)
        end
        
        if last_full_game_state.bosses then
            renderer.setNetworkedBosses(last_full_game_state.bosses)
        end
        
        if last_full_game_state.coins then
            renderer.setNetworkedCoins(last_full_game_state.coins)
        end
        
        if last_full_game_state.cars then
            renderer.setNetworkedCars(last_full_game_state.cars)
        end

        if last_full_game_state.map_data then
            map.restore(last_full_game_state.map_data)
        end

        if last_full_game_state.command_blocks then
            command.setCommandBlocks(last_full_game_state.command_blocks)
            renderer.setNetworkedCommandBlocks(last_full_game_state.command_blocks)
        end
    end
end

-- Helper function to clear accumulated data for a disconnected client
function snapshot.removeClient(client_id)
    if var.multiplayer == 1 then
        accumulated_game_state.players[client_id] = nil
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

return snapshot
