local snapshot = {}

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
    local game_state = {}
    
    -- Update local player first
    renderer.updateLocalPlayerFromPhysics()
    
    if var.multiplayer == 1 then
        -- HOST: Create full game state snapshot
        game_state = {
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
        game_state.players["client_1"] = renderer.local_player_state
        
        -- Add all accumulated client player data
        for client_id, player_data in pairs(accumulated_game_state.players) do
            -- print(client_id, player_data)
            if client_id ~= "client_1" then -- Don't overwrite host data
                game_state.players[client_id] = player_data
                local client_idNum = tonumber(string.sub(client_id,#client_id))
                -- print(client_idNum)
                
                game_state.players[client_id].health = player.online.health[client_idNum]
                -- game_state.players[client_id].health = 69
                
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
        
        -- Collect boss data
        if boss then
            game_state.bosses = boss.getNetworkData()
        end
        
        -- Collect car data from host and accumulated client data
        game_state.cars = {}
        if car then
            local hostCarData = car.getNetworkData()
            for k, v in pairs(hostCarData) do
                game_state.cars["host_" .. tostring(k)] = v
            end
        end
        for client_id, client_cars in pairs(accumulated_game_state.cars) do
            if client_cars then
                for k, v in pairs(client_cars) do
                    game_state.cars[client_id .. "_" .. tostring(k)] = v
                end
            end
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
        
        -- Add host's fire effects
        local host_fires = fire.getNetworkData()
        game_state.fire_effects = {}
        
        -- Convert host fires to string keys and add them
        if host_fires then
            for k, v in pairs(host_fires) do
                game_state.fire_effects["host_" .. tostring(k)] = v
            end
        end
        
        -- Add accumulated client fires with string keys
        for client_id, client_fires in pairs(accumulated_game_state.accumulated_fires) do
            if client_fires then
                for k, v in pairs(client_fires) do
                    game_state.fire_effects[client_id .. "_" .. tostring(k)] = v
                end
            end
        end

        -- Add host's bullets and rockets
        local host_bullets = bullet.getNetworkData()
        if host_bullets then
            for k, v in pairs(host_bullets) do
                game_state.bullets["host_" .. tostring(k)] = v
            end
        end

        -- local host_rockets = rocket.getNetworkData()
        -- if host_rockets then
        --     for k, v in pairs(host_rockets) do
        --         game_state.rockets["host_" .. tostring(k)] = v
        --     end
        -- end

        -- Add accumulated client bullets and rockets
        for client_id, client_bullets in pairs(accumulated_game_state.accumulated_bullets) do
            if client_bullets then
                for k, v in pairs(client_bullets) do
                    game_state.bullets[client_id .. "_" .. tostring(k)] = v
                end
            end
        end

        for client_id, client_rockets in pairs(accumulated_game_state.accumulated_rockets) do
            if client_rockets then
                for k, v in pairs(client_rockets) do
                    game_state.rockets[client_id .. "_" .. tostring(k)] = v
                end
            end
        end

        -- print(game_state.players)
        -- game_state.map_data = map.createSaveData()
        game_state.map_data = map.createSaveDataSmall() -- just arches and trees for the ground layer we can move that later


        
        -- Collect host's command blocks (which now includes accumulated client blocks)
        game_state.command_blocks = command.getCommandBlocks()
        
    else
        -- CLIENT: Create minimal update with player data and fire effects
        game_state = {
            type = "player_update",
            client_id = "client_" .. var.multiplayer,
            player_data = renderer.local_player_state,
            fire_effects = fire.getNetworkData(), -- Clients send their fire effects
            bullets = bullet.getNetworkData(),
            -- rockets = rocket.getNetworkData(),
            command_blocks = command.getCommandBlocks(),
            boss_spawn_request = boss and boss.getPendingSpawnRequest() or nil,  -- Add boss spawn request field
            cars = car and car.getNetworkData() or {}  -- Clients send their car data
        }
        

    end
    
    return game_state
end

function snapshot.apply(game_state)
    if var.multiplayer == 1 then
        -- HOST: Handle incoming client updates
        if game_state.type == "player_update" then
            -- Accumulate client player data and fire effects
            accumulated_game_state.players[game_state.client_id] = game_state.player_data
            
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
            
            -- Apply accumulated car data to host's renderer
            local all_cars = {}
            if car then
                local hostCarData = car.getNetworkData()
                for k, v in pairs(hostCarData) do
                    all_cars["host_" .. tostring(k)] = v
                end
            end
            for client_id, client_cars in pairs(accumulated_game_state.cars) do
                if client_cars then
                    for k, v in pairs(client_cars) do
                        all_cars[client_id .. "_" .. tostring(k)] = v
                    end
                end
            end
            renderer.setNetworkedCars(all_cars)
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
                else
                    -- print(player_data.health)
                    player.health = player_data.health
                end
            end
            
            renderer.setNetworkedPlayers(other_players)
        end

         if game_state.fire_effects then
            -- Filter out own fire effects to avoid duplication
            local other_fires = {}
            local own_client_prefix = "client_" .. var.multiplayer .. "_"
            
            for fire_id, fire_data in pairs(game_state.fire_effects) do
                if not string.match(fire_id, "^" .. own_client_prefix) then
                    other_fires[fire_id] = fire_data
                end
            end
            
            renderer.setNetworkedFireEffects(other_fires)
        end

        if game_state.bullets then
            local other_bullets = {}
            local own_client_prefix = "client_" .. var.multiplayer .. "_"
            for bullet_id, bullet_data in pairs(game_state.bullets) do
                if not string.match(bullet_id, "^" .. own_client_prefix) then
                    other_bullets[bullet_id] = bullet_data
                end
            end
            renderer.setNetworkedBullets(other_bullets)
        end

        if game_state.rockets then
            local other_rockets = {}
            local own_client_prefix = "client_" .. var.multiplayer .. "_"
            for rocket_id, rocket_data in pairs(game_state.rockets) do
                if not string.match(rocket_id, "^" .. own_client_prefix) then
                    other_rockets[rocket_id] = rocket_data
                end
            end
            renderer.setNetworkedRockets(other_rockets)
        end
        
        if game_state.enemies then
            renderer.setNetworkedEnemies(game_state.enemies)
        end
        
        if game_state.bosses then
            renderer.setNetworkedBosses(game_state.bosses)
        end
        
        if game_state.coins then
            renderer.setNetworkedCoins(game_state.coins)
        end
        
        if game_state.cars then
            renderer.setNetworkedCars(game_state.cars)
        end

        if game_state.map_data then
            map.restore(game_state.map_data)
        end

        if game_state.command_blocks then
            command.setCommandBlocks(game_state.command_blocks)
            renderer.setNetworkedCommandBlocks(game_state.command_blocks)
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
