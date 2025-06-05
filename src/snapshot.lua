local snapshot = {}

-- Host maintains accumulated game state
local accumulated_game_state = {
    players = {},
    enemies = {},
    coins = {},
    fire_effects = {}
}

function snapshot.create()
    local game_state = {}
    
    -- Update local player first
    renderer.updateLocalPlayerFromPhysics()
    
    if var.multiplayer == 1 then
        -- HOST: Create full game state snapshot
        game_state = {
            players = {},
            enemies = {},
            coins = {},
            fire_effects = {}
        }
        
        -- Add host's player data
        game_state.players["client_1"] = renderer.local_player_state
        
        -- Add all accumulated client player data
        for client_id, player_data in pairs(accumulated_game_state.players) do
            if client_id ~= "client_1" then -- Don't overwrite host data
                game_state.players[client_id] = player_data
            end
        end
        
        -- Collect enemy data from physics bodies
        for i = 1, #enemies_bods do
            local ex, ey = enemies_bods[i]:getX(), enemies_bods[i]:getY()
            game_state.enemies[tostring(i)] = {
                x = ex,
                y = ey,
                active = true
            }
        end
        
        -- Collect coin data from physics bodies
        for i = 1, #coin_bods do
            local cx, cy = coin_bods[i]:getX(), coin_bods[i]:getY()
            game_state.coins[tostring(i)] = {
                x = cx,
                y = cy,
                active = true
            }
        end
        
        -- Add fire effects data
        game_state.fire_effects = fire.getNetworkData()
        
    else
        -- CLIENT: Create minimal update with only player data
        game_state = {
            type = "player_update",
            client_id = "client_" .. var.multiplayer,
            player_data = renderer.local_player_state,
            fire_effects = fire.getNetworkData() -- Clients can still send fire effects
        }
    end
    
    return game_state
end

function snapshot.apply(game_state)
    if var.multiplayer == 1 then
        -- HOST: Handle incoming client updates
        if game_state.type == "player_update" then
            -- Accumulate client player data
            accumulated_game_state.players[game_state.client_id] = game_state.player_data
            
            -- Apply fire effects from client
            if game_state.fire_effects then
                renderer.setNetworkedFireEffects(game_state.fire_effects)
            end
            
            -- Create combined player data with only CLIENT players (not host)
            local client_players = {}
            for client_id, player_data in pairs(accumulated_game_state.players) do
                client_players[client_id] = player_data -- Only client players
            end
            
            -- Apply only the client player data (host draws itself locally)
            renderer.setNetworkedPlayers(client_players)
        else
            -- Handle full game state (shouldn't happen on host)
            if game_state.players then
                renderer.setNetworkedPlayers(game_state.players)
            end
        end
    else
        -- CLIENT: Apply full game state from host
        if game_state.players then
            -- Filter out own player data to avoid drawing self twice
            local other_players = {}
            local own_client_id = "client_" .. var.multiplayer
            
            for client_id, player_data in pairs(game_state.players) do
                if client_id ~= own_client_id then
                    other_players[client_id] = player_data
                end
            end
            
            renderer.setNetworkedPlayers(other_players)
        end
        
        if game_state.fire_effects then
            renderer.setNetworkedFireEffects(game_state.fire_effects)
        end
        
        if game_state.enemies then
            renderer.setNetworkedEnemies(game_state.enemies)
        end
        
        if game_state.coins then
            renderer.setNetworkedCoins(game_state.coins)
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