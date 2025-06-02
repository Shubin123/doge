local renderer = {}
-- Dynamic draw list for Y-sorting
dynamic_draw_list = {}

-- Networked game state (managed by server, synced to clients)
renderer.networked_state = {
    players = {}, -- { player_id = { x, y, animation_frame, scale, rotation, ... } }
    enemies = {}, -- { enemy_id = { x, y, active, ... } }
    coins = {},   -- { coin_id = { x, y, active, ... } }
    fire_effects = {}, -- { effect_id = { x, y, active, ... } }
    -- Add other networked objects as needed
}

-- Local player state (for smooth interpolation/prediction)
renderer.local_player_state = {
    x = 0, y = 0,
    animation_frame = 1,
    scale = 1,
    rotation = 0
}

-- Sorting function for Y-axis rendering
function renderer.sortByRenderY(drawable_a, drawable_b)
    return drawable_a.sort_y < drawable_b.sort_y
end

flipQuads = true

-- Set networked player data (called by multiplayer system)
function renderer.setNetworkedPlayers(players_data)
    renderer.networked_state.players = players_data or {}
end

-- Set networked enemy data (called by multiplayer system)
function renderer.setNetworkedEnemies(enemies_data)
    renderer.networked_state.enemies = enemies_data or {}
end

-- Set networked coin data (called by multiplayer system)
function renderer.setNetworkedCoins(coins_data)
    renderer.networked_state.coins = coins_data or {}
end

-- Set networked fire effects data (called by multiplayer system)
function renderer.setNetworkedFireEffects(fire_data)
    renderer.networked_state.fire_effects = fire_data or {}
end

-- Update local player state (for host/single player)
function renderer.updateLocalPlayerFromPhysics()
    if player and player.body then
        local px, py = player.body:getX(), player.body:getY()
        renderer.local_player_state = {
            x = px,
            y = py,
            animation_frame = math.floor(player.animation.currentTime / (player.animation.duration) * #player.animation.quads) + 1,
            scale = player.scale,
            rotation = var.character_rotation or 0,
            active = true
        }
    end
end

-- Get local player state for network transmission
function renderer.getLocalPlayerState()
    return renderer.local_player_state
end

-- Function to populate dynamic draw list (multiplayer version)
function renderer.populateDynamicDrawListNetworked()
    -- Clear the list
    dynamic_draw_list = { unpack(map_a, 1, #map_a) }
    rebuildArray(dynamic_draw_list, map_b)

    -- Draw networked players
    for player_id, player_data in pairs(renderer.networked_state.players) do
        if player_data.active then
            local sort_y = player_data.y + (100 * player_data.scale)
            
            table.insert(dynamic_draw_list, {
                sort_y = sort_y + 45,
                image_or_particles = player.animation.spriteSheet, -- Assume same spritesheet for all players
                quad = player.animation.quads[((player_data.animation_frame + 5) % 5) + 6] or var.nullquad,
                x = player_data.x,
                y = player_data.y,
                rotation = player_data.rotation,
                scale_x = player_data.scale,
                scale_y = player_data.scale,
                offset_x = 35,
                offset_y = 50,
                color = { 1, 1, 1, 1 },
                blend_mode = { "alpha" },
                source_object_type = "networked_player",
                player_id = player_id
            })
        end
    end
    
    -- Portal shader drawable (positioned at specific location)
    table.insert(dynamic_draw_list, {
        sort_y = 370, -- Adjust depth as needed
        shader = portal.SHADERS["portal"],
        shader_params = portal.params,
        x = 236,
        y = 190,
        width = 35,
        height = 50,
        color = { 1, 1, 1, 1 },
        blend_mode = { "alpha" },
        source_object_type = "portal_shader"
    })
    
    -- Draw networked enemies
    for enemy_id, enemy_data in pairs(renderer.networked_state.enemies) do
        if enemy_data.active then
            local enemy_sort_y = enemy_data.y + (enemy_image:getHeight() * 0.1) / 2

            table.insert(dynamic_draw_list, {
                sort_y = enemy_sort_y + 100,
                image_or_particles = enemy_image,
                quad = nil,
                x = enemy_data.x,
                y = enemy_data.y,
                rotation = 0,
                scale_x = 0.1,
                scale_y = 0.1,
                offset_x = enemy_image:getWidth() / 2,
                offset_y = enemy_image:getHeight() / 2,
                color = { 1, 1, 1, 1 },
                blend_mode = { "alpha" },
                source_object_type = "networked_enemy",
                enemy_id = enemy_id
            })
        end
    end

    -- Draw networked coins
    for coin_id, coin_data in pairs(renderer.networked_state.coins) do
        if coin_data.active then
            local coin_sort_y = coin_data.y + (coin_image:getHeight() * 0.5) / 2

            table.insert(dynamic_draw_list, {
                sort_y = coin_sort_y + 100,
                image_or_particles = coin_image,
                quad = nil,
                x = coin_data.x,
                y = coin_data.y,
                rotation = 0,
                scale_x = 0.5,
                scale_y = 0.5,
                offset_x = coin_image:getWidth() / 2,
                offset_y = coin_image:getHeight() / 2,
                color = { 1, 1, 1, 1 },
                blend_mode = { "alpha" },
                source_object_type = "networked_coin",
                coin_id = coin_id
            })
        end
    end

    -- Draw networked fire effects
    for effect_id, fire_data in pairs(renderer.networked_state.fire_effects) do
        if fire_data.active then
            -- You'll need to adapt this based on your fire effect structure
            table.insert(dynamic_draw_list, {
                sort_y = fire_data.y + 50,
                image_or_particles = fire_data.particle_system or fire_data.image,
                quad = fire_data.quad,
                x = fire_data.x,
                y = fire_data.y,
                rotation = fire_data.rotation or 0,
                scale_x = fire_data.scale_x or 1,
                scale_y = fire_data.scale_y or 1,
                offset_x = fire_data.offset_x or 0,
                offset_y = fire_data.offset_y or 0,
                color = fire_data.color or { 1, 1, 1, 1 },
                blend_mode = fire_data.blend_mode or { "alpha" },
                source_object_type = "networked_fire_effect",
                effect_id = effect_id
            })
        end
    end
end

-- Original function for local/single player (keeps physics body access)
function renderer.populateDynamicDrawList()
    -- Clear the list
    dynamic_draw_list = { unpack(map_a, 1, #map_a) }
    rebuildArray(dynamic_draw_list, map_b)

    -- Player drawable (from physics body)
    local px, py = player.body:getX(), player.body:getY()
    local spriteNum = math.floor(player.animation.currentTime / (player.animation.duration) * #player.animation.quads) + 1
    local sort_y = py + (100 * player.scale)
    
    table.insert(dynamic_draw_list, {
        sort_y = sort_y + 45,
        image_or_particles = player.animation.spriteSheet,
        quad = player.animation.quads[(spriteNum + 5)%5 + 6] or var.nullquad,
        x = px,
        y = py,
        rotation = var.character_rotation,
        scale_x = player.scale,
        scale_y = player.scale,
        offset_x = 35,
        offset_y = 50,
        color = { 1, 1, 1, 1 },
        blend_mode = { "alpha" },
        source_object_type = "player"
    })
    
    -- Portal shader drawable (positioned at specific location)
    table.insert(dynamic_draw_list, {
        sort_y = 370, -- Adjust depth as needed
        shader = portal.SHADERS["portal"],
        shader_params = portal.params,
        x = 236,
        y = 190,
        width = 35,
        height = 50,
        color = { 1, 1, 1, 1 },
        blend_mode = { "alpha" },
        source_object_type = "portal_shader"
    })
    
    -- Enemies drawables (from physics bodies)
    for i = 1, #enemies_bods do
        local ex, ey = enemies_bods[i]:getX(), enemies_bods[i]:getY()
        local enemy_sort_y = ey + (enemy_image:getHeight() * 0.1) / 2

        table.insert(dynamic_draw_list, {
            sort_y = enemy_sort_y + 100,
            image_or_particles = enemy_image,
            quad = nil,
            x = ex,
            y = ey,
            rotation = 0,
            scale_x = 0.1,
            scale_y = 0.1,
            offset_x = enemy_image:getWidth() / 2,
            offset_y = enemy_image:getHeight() / 2,
            color = { 1, 1, 1, 1 },
            blend_mode = { "alpha" },
            source_object_type = "enemy"
        })
    end

    -- Coins drawables (from physics bodies)
    for i = 1, #coin_bods do
        local cx, cy = coin_bods[i]:getX(), coin_bods[i]:getY()
        local coin_sort_y = cy + (coin_image:getHeight() * 0.5) / 2

        table.insert(dynamic_draw_list, {
            sort_y = coin_sort_y + 100,
            image_or_particles = coin_image,
            quad = nil,
            x = cx,
            y = cy,
            rotation = 0,
            scale_x = 0.5,
            scale_y = 0.5,
            offset_x = coin_image:getWidth() / 2,
            offset_y = coin_image:getHeight() / 2,
            color = { 1, 1, 1, 1 },
            blend_mode = { "alpha" },
            source_object_type = "coin"
        })
    end

    -- Fire effects drawables
    fire.populate()
    enemy.populate()
end

-- Updated render function to handle shaders
function renderer.renderSortedDrawList()
    -- Store current graphics state
    local current_color = { love.graphics.getColor() }
    local current_blend_mode = love.graphics.getBlendMode()
    local current_shader = love.graphics.getShader()

    local last_color = { 1, 1, 1, 1 }
    local last_blend_mode = { "alpha" }

    for _, drawable in ipairs(dynamic_draw_list) do
        -- Set color if different from last
        if drawable.color[1] ~= last_color[1] or drawable.color[2] ~= last_color[2] or
            drawable.color[3] ~= last_color[3] or drawable.color[4] ~= last_color[4] then
            love.graphics.setColor(drawable.color[1], drawable.color[2], drawable.color[3], drawable.color[4])
            last_color = drawable.color
        end

        -- Set blend mode if different from last
        if drawable.blend_mode[1] ~= last_blend_mode[1] or
            (drawable.blend_mode[2] and drawable.blend_mode[2] ~= last_blend_mode[2]) then
            if drawable.blend_mode[2] then
                love.graphics.setBlendMode(drawable.blend_mode[1], drawable.blend_mode[2])
            else
                love.graphics.setBlendMode(drawable.blend_mode[1])
            end
            last_blend_mode = drawable.blend_mode
        end

        -- Handle shader drawing
        if drawable.shader then
            -- Set shader and parameters
            love.graphics.setShader(drawable.shader)
            if drawable.shader_params then
                drawable.shader:send("time", drawable.shader_params.time)
                drawable.shader:send("spin_time", drawable.shader_params.spin_time)
                drawable.shader:send("colour_1", drawable.shader_params.colour_1)
                drawable.shader:send("colour_2", drawable.shader_params.colour_2)
                drawable.shader:send("colour_3", drawable.shader_params.colour_3)
                drawable.shader:send("contrast", drawable.shader_params.contrast)
                drawable.shader:send("spin_amount", drawable.shader_params.spin_amount)
            end
            
            -- Draw shader rectangle
            love.graphics.rectangle("fill", drawable.x, drawable.y, drawable.width, drawable.height)
            
            -- Reset shader
            love.graphics.setShader()
            
        -- Handle regular image drawing
        elseif drawable.image_or_particles then
            if drawable.quad then
                love.graphics.draw(
                    drawable.image_or_particles,
                    drawable.quad,
                    drawable.x,
                    drawable.y,
                    drawable.rotation or 0,
                    drawable.scale_x or 1,
                    drawable.scale_y or 1,
                    drawable.offset_x or 0,
                    drawable.offset_y or 0
                )
            else
                love.graphics.draw(
                    drawable.image_or_particles,
                    drawable.x,
                    drawable.y,
                    drawable.rotation or 0,
                    drawable.scale_x or 1,
                    drawable.scale_y or 1,
                    drawable.offset_x or 0,
                    drawable.offset_y or 0
                )
            end
        end
    end

    -- Restore original graphics state
    love.graphics.setColor(current_color[1], current_color[2], current_color[3], current_color[4])
    love.graphics.setBlendMode(current_blend_mode)
    love.graphics.setShader(current_shader)
end

function rebuildArray(arr, innerElements)
    for i = 1, #innerElements do
        table.insert(arr, innerElements[i])
    end
end

function addMapToDynamicDrawList(mapData, map_x, map_y, map_scale, base_sort_y)
    map_x = map_x or 0
    map_y = map_y or 0
    map_scale = map_scale or 1

    local max_tiles_x = math.ceil(var.game_width / (mapData.tiles.tileWidth * map_scale))
    local max_tiles_y = math.ceil(var.game_height / (mapData.tiles.tileHeight * map_scale))

    local dynamic_draw_lists = {}

    for row = 1, max_tiles_y do
        for col = 1, max_tiles_x do
            local tileId = mapData.tileData[row] and mapData.tileData[row][col]
            if tileId and tileId > 0 and mapData.tiles.quads[tileId] then
                local tile_x = map_x + (col - 1) * mapData.tiles.tileWidth * map_scale
                local tile_y = map_y + (row - 1) * mapData.tiles.tileHeight * map_scale
                local tile_sort_y = base_sort_y + tile_y -- Use tile's Y position for sorting

                table.insert(dynamic_draw_lists, {
                    sort_y = tile_sort_y,
                    image_or_particles = mapData.tiles.tilesetImage,
                    quad = mapData.tiles.quads[tileId],
                    x = tile_x,
                    y = tile_y,
                    rotation = 0,
                    scale_x = map_scale,
                    scale_y = map_scale,
                    offset_x = 0,
                    offset_y = 0,
                    color = { 1, 1, 1, 1 },
                    blend_mode = { "alpha" },
                    source_object_type = "map_tile"
                })
            end
        end
    end

    return dynamic_draw_lists
end

-- Utility function to create a complete game state snapshot (for server)
function renderer.createGameStateSnapshot()
    local game_state = {
        players = {},
        enemies = {},
        coins = {},
        fire_effects = {}
    }
    
    -- Update local player first if this is the server
    renderer.updateLocalPlayerFromPhysics()
    game_state.players["local"] = renderer.local_player_state
    
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
    
    -- Add fire effects data (you'll need to adapt this based on your fire system)
    -- game_state.fire_effects = fire.getNetworkData() -- Implement this in your fire module
    
    return game_state
end

-- Apply received game state (for clients)
function renderer.applyGameStateSnapshot()



    if game_state.players then
        renderer.setNetworkedPlayers(game_state)
    end
    if game_state.enemies then
        renderer.setNetworkedEnemies(game_state.enemies)
    end
    if game_state.coins then
        renderer.setNetworkedCoins(game_state.coins)
    end
    if game_state.fire_effects then
        renderer.setNetworkedFireEffects(game_state.fire_effects)
    end
end

-- Usage in main.lua for multiplayer:
-- function love.draw()
--     if is_multiplayer then
--         -- Use networked rendering
--         renderer.populateDynamicDrawListNetworked()
--     else
--         -- Use local physics-based rendering
--         renderer.populateDynamicDrawList()
--     end
--     
--     table.sort(dynamic_draw_list, renderer.sortByRenderY)
--     renderer.renderSortedDrawList()
-- end

-- Server usage:
-- function love.update(dt)
--     -- Server updates physics and creates snapshots
--     local game_state = renderer.createGameStateSnapshot()
--     multiplayer:broadcast(multiplayer:createMessage("game_state", game_state))
-- end

-- Client usage:
-- multiplayer:onMessage("game_state", function(message, peer, role)
--     renderer.applyGameStateSnapshot(message.data)
-- end)

return renderer