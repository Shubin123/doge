local map_manager = {}
local map_loader = require("map_loader")

-- Current game state
local current_map_id = nil
local current_map_object = nil
local transition_state = "idle" -- "idle", "loading", "transitioning"
local transition_callback = nil

-- Map bounds and world management
local world_bounds = {
    x = 0, y = 0, width = 1000, height = 1000
}

-- Entity management
local entity_manager = {
    entities = {},
    spawn_queue = {},
    cleanup_queue = {}
}

-- Initialize the map manager
function map_manager.initialize()
    -- Register default maps
    map_loader.register_map({
        id = "level1",
        name = "Grassland Level",
        tileset_path = "gfx/TileSet/TX Tileset Grass.png",
        tile_width = 16,
        tile_height = 16,
        map_width = 70,
        map_height = 50,
        world_x = 0,
        world_y = 0,
        player_spawn = {x = 400, y = 300},
        enemies = {
            {x = 300, y = 200, type = "basic"},
            {x = 500, y = 300, type = "basic"},
            {x = 700, y = 400, type = "basic"},
            {x = 200, y = 500, type = "basic"},
            {x = 600, y = 150, type = "basic"}
        },
        collectibles = {
            {x = 250, y = 250, type = "coin"},
            {x = 350, y = 350, type = "coin"},
            {x = 450, y = 450, type = "coin"},
            {x = 550, y = 200, type = "coin"},
            {x = 400, y = 500, type = "coin"}
        }
    })
    
    map_loader.register_map({
        id = "level2",
        name = "Forest Level",
        tileset_path = "gfx/TileSet/TX Plant.png",
        tile_width = 156,
        tile_height = 156,
        map_width = 20,
        map_height = 20,
        world_x = 1200,
        world_y = 0,
        player_spawn = {x = 1400, y = 200},
        enemies = {
            {x = 1300, y = 300, type = "forest"},
            {x = 1500, y = 400, type = "forest"},
            {x = 1400, y = 500, type = "forest"}
        },
        collectibles = {
            {x = 1350, y = 300, type = "coin"},
            {x = 1450, y = 300, type = "coin"},
            {x = 1400, y = 400, type = "coin"}
        }
    })
    
    map_loader.register_map({
        id = "level3",
        name = "Stone Ruins",
        tileset_path = "gfx/TileSet/TX Struct.png",
        tile_width = 98,
        tile_height = 128,
        map_width = 30,
        map_height = 25,
        world_x = 0,
        world_y = 1000,
        player_spawn = {x = 200, y = 1200},
        enemies = {
            {x = 300, y = 1300, type = "stone"},
            {x = 500, y = 1400, type = "stone"}
        },
        collectibles = {
            {x = 400, y = 1350, type = "coin"}
        }
    })
    
end

-- Load and switch to a map
function map_manager.switch_to_map(map_id, callback)
    if transition_state ~= "idle" then
        print("Map transition already in progress")
        return false
    end
    
    if current_map_id == map_id then
        if callback then callback(current_map_object) end
        return true
    end
    
    transition_state = "loading"
    transition_callback = callback
    
    -- Clean up current entities
    map_manager.cleanup_current_entities()
    
    -- Start loading new map
    local result = map_loader.load_map(map_id, function(loaded_map)
        map_manager.complete_map_transition(map_id, loaded_map)
    end)
    
    if result and result ~= "loading" then
        -- Map was loaded synchronously from cache
        map_manager.complete_map_transition(map_id, result)
        return true
    end
    
    return result == "loading"
end

function map_manager.complete_map_transition(map_id, loaded_map)
    if not loaded_map then
        print("Failed to load map: " .. map_id)
        transition_state = "idle"
        return
    end
    
    transition_state = "transitioning"
    
    -- Update current map
    current_map_id = map_id
    current_map_object = loaded_map
    
    -- Update world bounds
    local map_def = loaded_map.definition
    world_bounds.x = map_def.world_x
    world_bounds.y = map_def.world_y
    world_bounds.width = map_def.map_width * map_def.tile_width
    world_bounds.height = map_def.map_height * map_def.tile_height
    
    -- Update camera bounds if camera module exists
    if camera then
        camera.setMapBounds(world_bounds.x, world_bounds.y, world_bounds.width, world_bounds.height)
        camera.map_bounds.enabled = true
    end
    
    -- Spawn entities for the new map
    map_manager.spawn_map_entities()
    
    -- Set player position
    if player and player.body then
        player.body:setPosition(map_def.player_spawn.x, map_def.player_spawn.y)
    end
    
    transition_state = "idle"
    
    if transition_callback then
        transition_callback(loaded_map)
        transition_callback = nil
    end
    
    print("Successfully switched to map: " .. map_id .. " (load time: " .. string.format("%.3f", loaded_map.load_time) .. "s)")
end

-- Entity spawning and management
function map_manager.spawn_map_entities()
    if not current_map_object then return end
    
    local map_def = current_map_object.definition
    
    -- Clear existing entities (if systems exist)
    map_manager.cleanup_current_entities()
    
    -- Spawn enemies
    if enemies_bods and enemy_shape then
        for _, enemy_data in ipairs(map_def.enemies) do
            local body = love.physics.newBody(world, enemy_data.x, enemy_data.y, "dynamic")
            table.insert(enemies_bods, body)
            local fixture = love.physics.newFixture(body, enemy_shape)
            fixture:setGroupIndex(-777)
            
            -- Store entity reference
            table.insert(entity_manager.entities, {
                type = "enemy",
                body = body,
                fixture = fixture,
                data = enemy_data
            })
        end
    end
    
    -- Spawn collectibles
    if coin_bods and coin_shape then
        for _, collectible in ipairs(map_def.collectibles) do
            local body = love.physics.newBody(world, collectible.x, collectible.y, "dynamic")
            table.insert(coin_bods, body)
            local fixture = love.physics.newFixture(body, coin_shape)
            fixture:setGroupIndex(69)
            
            -- Store entity reference
            table.insert(entity_manager.entities, {
                type = "collectible",
                body = body,
                fixture = fixture,
                data = collectible
            })
        end
    end
    
    -- Update global counters if they exist
    if var then
        var.num_coins = #coin_bods
        var.num_enemies = #enemies_bods
    end
end

function map_manager.cleanup_current_entities()
    -- Clean up physics bodies
    for _, entity in ipairs(entity_manager.entities) do
        if entity.body and not entity.body:isDestroyed() then
            entity.body:destroy()
        end
    end
    
    -- Clear entity lists
    entity_manager.entities = {}
    
    -- Clear global entity lists if they exist
    if coin_bods then
        for i = #coin_bods, 1, -1 do
            if not coin_bods[i]:isDestroyed() then
                coin_bods[i]:destroy()
            end
            table.remove(coin_bods, i)
        end
    end
    
    if enemies_bods then
        for i = #enemies_bods, 1, -1 do
            if not enemies_bods[i]:isDestroyed() then
                enemies_bods[i]:destroy()
            end
            table.remove(enemies_bods, i)
        end
    end
end

-- Map rendering interface
function map_manager.get_visible_tiles()
    if not current_map_object then return {} end
    
    -- Use camera bounds if available
    local view_bounds = camera and camera.view_bounds or {
        x1 = -200, y1 = -200, x2 = 1000, y2 = 800
    }
    
    local tiles = {}
    local map_obj = current_map_object
    local map_def = map_obj.definition
    
    -- Calculate tile dimensions
    local tile_width = map_def.tile_width
    local tile_height = map_def.tile_height
    
    -- Calculate visible tile range
    local start_col = math.max(1, math.floor((view_bounds.x1 - map_obj.world_x) / tile_width) + 1)
    local end_col = math.min(map_obj.width, math.ceil((view_bounds.x2 - map_obj.world_x) / tile_width) + 1)
    local start_row = math.max(1, math.floor((view_bounds.y1 - map_obj.world_y) / tile_height) + 1)
    local end_row = math.min(map_obj.height, math.ceil((view_bounds.y2 - map_obj.world_y) / tile_height) + 1)
    
    for row = start_row, end_row do
        for col = start_col, end_col do
            local tile_id = map_obj.tile_data[row] and map_obj.tile_data[row][col]
            if tile_id and tile_id > 0 and map_obj.tiles.quads[tile_id] then
                local tile_world_x = map_obj.world_x + (col - 1) * tile_width
                local tile_world_y = map_obj.world_y + (row - 1) * tile_height
                
                table.insert(tiles, {
                    x = tile_world_x,
                    y = tile_world_y,
                    tile_id = tile_id,
                    quad = map_obj.tiles.quads[tile_id],
                    tileset_image = map_obj.tiles.tileset_image,
                    sort_y = tile_world_y,
                    source_object_type = "map_tile"
                })
            end
        end
    end
    
    return tiles
end

-- Update function (call every frame)
function map_manager.update(dt)
    map_loader.update(dt)
    
    -- Process entity spawn/cleanup queues
    map_manager.process_entity_queues()
end

function map_manager.process_entity_queues()
    -- Process spawn queue
    for _, spawn_data in ipairs(entity_manager.spawn_queue) do
        map_manager.spawn_entity(spawn_data)
    end
    entity_manager.spawn_queue = {}
    
    -- Process cleanup queue
    for _, entity in ipairs(entity_manager.cleanup_queue) do
        map_manager.cleanup_entity(entity)
    end
    entity_manager.cleanup_queue = {}
end

function map_manager.spawn_entity(spawn_data)
    -- Implementation depends on entity type and available systems
    print("Spawning entity:", spawn_data.type, spawn_data.x, spawn_data.y)
end

function map_manager.cleanup_entity(entity)
    if entity.body and not entity.body:isDestroyed() then
        entity.body:destroy()
    end
    
    -- Remove from entity manager
    for i, managed_entity in ipairs(entity_manager.entities) do
        if managed_entity == entity then
            table.remove(entity_manager.entities, i)
            break
        end
    end
end

-- Utility functions
function map_manager.get_current_map()
    return current_map_object
end

function map_manager.get_current_map_id()
    return current_map_id
end

function map_manager.get_world_bounds()
    return world_bounds
end

function map_manager.is_loading()
    return transition_state == "loading"
end

function map_manager.get_transition_state()
    return transition_state
end

-- Map data access
function map_manager.get_tile_at_world_pos(world_x, world_y)
    if not current_map_object then return 0 end
    
    local map_obj = current_map_object
    local map_def = map_obj.definition
    
    -- Convert to local coordinates
    local local_x = world_x - map_obj.world_x
    local local_y = world_y - map_obj.world_y
    
    -- Convert to tile coordinates
    local tile_x = math.floor(local_x / map_def.tile_width) + 1
    local tile_y = math.floor(local_y / map_def.tile_height) + 1
    
    if tile_x >= 1 and tile_x <= map_obj.width and tile_y >= 1 and tile_y <= map_obj.height then
        return map_obj.tile_data[tile_y] and map_obj.tile_data[tile_y][tile_x] or 0
    end
    
    return 0
end

function map_manager.set_tile_at_world_pos(world_x, world_y, tile_id)
    if not current_map_object then return false end
    
    local map_obj = current_map_object
    local map_def = map_obj.definition
    
    -- Convert to local coordinates
    local local_x = world_x - map_obj.world_x
    local local_y = world_y - map_obj.world_y
    
    -- Convert to tile coordinates
    local tile_x = math.floor(local_x / map_def.tile_width) + 1
    local tile_y = math.floor(local_y / map_def.tile_height) + 1
    
    if tile_x >= 1 and tile_x <= map_obj.width and tile_y >= 1 and tile_y <= map_obj.height then
        if not map_obj.tile_data[tile_y] then map_obj.tile_data[tile_y] = {} end
        map_obj.tile_data[tile_y][tile_x] = tile_id
        return true
    end
    
    return false
end

-- Cleanup
function map_manager.cleanup()
    map_manager.cleanup_current_entities()
    map_loader.cleanup()
    current_map_id = nil
    current_map_object = nil
    transition_state = "idle"
end

-- Debug information
function map_manager.get_debug_info()
    local memory_usage = map_loader.get_memory_usage()
    
    return {
        current_map = current_map_id,
        transition_state = transition_state,
        world_bounds = world_bounds,
        entity_count = #entity_manager.entities,
        memory_usage = memory_usage
    }
end

return map_manager