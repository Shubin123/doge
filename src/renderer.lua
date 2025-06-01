local renderer = {}

-- Hash map for efficient rendering
local draw_hash_map = {}
local sorted_draw_list = {}
local needs_resort = false
local last_frame_counts = {
    enemies = 0,
    coins = 0,
    fire_effects = 0,
    enemy_effects = 0
}

flipQuads = true

-- Sorting function for Y-axis rendering
function renderer.sortByRenderY(drawable_a, drawable_b)
    return drawable_a.sort_y < drawable_b.sort_y
end

-- Initialize static elements (call once at start)
function renderer.initializeStaticElements()
    -- Add map elements to hash map
    for i = 1, map_a do
        draw_hash_map["map_a_" .. i] = map_a[i]
    end
    
    for i = 1, map_b do
        draw_hash_map["map_b_" .. i] = map_b[i]
    end
    
    needs_resort = true
end

-- Add map tiles using the existing function
function renderer.addMapToHashMap(mapData, map_x, map_y, map_scale, base_sort_y, map_key_prefix)
    map_key_prefix = map_key_prefix or "map_tiles"
    local map_drawables = addMapToDynamicDrawList(mapData, map_x, map_y, map_scale, base_sort_y)
    
    -- Add each tile to the hash map with unique keys
    for i, drawable in ipairs(map_drawables) do
        draw_hash_map[map_key_prefix .. "_" .. i] = drawable
    end
    
    needs_resort = true
    return #map_drawables -- Return count for tracking if needed
end

-- Function to remove a specific map from hash map (useful for dynamic maps)
function renderer.removeMapFromHashMap(map_key_prefix, tile_count)
    for i = 1, tile_count do
        draw_hash_map[map_key_prefix .. "_" .. i] = nil
    end
    needs_resort = true
end

-- Update player drawable (call when player moves/animates)
function renderer.updatePlayer()
    local px, py = player.body:getX(), player.body:getY()
    local spriteNum = math.floor(player.animation.currentTime / (player.animation.duration) * #player.animation.quads) + 1
    local sort_y = py + (100 * player.scale)
    
    draw_hash_map["player"] = {
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
    }
    
    needs_resort = true
end

-- Update portal shader drawable
function renderer.updatePortal()
    draw_hash_map["portal"] = {
        sort_y = 370,
        shader = portal.SHADERS["portal"],
        shader_params = portal.params,
        x = 236,
        y = 190,
        width = 35,
        height = 50,
        color = { 1, 1, 1, 1 },
        blend_mode = { "alpha" },
        source_object_type = "portal_shader"
    }
    
    needs_resort = true
end

-- Update enemies (handles size changes efficiently)
function renderer.updateEnemies()
    local current_enemy_count = #enemies_bods
    
    -- If count decreased, remove excess enemies from hash map
    if current_enemy_count < last_frame_counts.enemies then
        for i = current_enemy_count + 1, last_frame_counts.enemies do
            draw_hash_map["enemy_" .. i] = nil
        end
        needs_resort = true
    end
    
    -- Update existing/new enemies
    for i = 1, current_enemy_count do
        local ex, ey = enemies_bods[i]:getX(), enemies_bods[i]:getY()
        local enemy_sort_y = ey + (enemy_image:getHeight() * 0.1) / 2
        
        local old_drawable = draw_hash_map["enemy_" .. i]
        local new_sort_y = enemy_sort_y + 100
        
        -- Only update if position changed or it's a new enemy
        if not old_drawable or old_drawable.x ~= ex or old_drawable.y ~= ey then
            draw_hash_map["enemy_" .. i] = {
                sort_y = new_sort_y,
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
            }
            
            -- Check if Y position changed enough to need resorting
            if not old_drawable or math.abs(old_drawable.sort_y - new_sort_y) > 1 then
                needs_resort = true
            end
        end
    end
    
    last_frame_counts.enemies = current_enemy_count
end

-- Update coins (handles size changes efficiently)
function renderer.updateCoins()
    local current_coin_count = #coin_bods
    
    -- If count decreased, remove excess coins from hash map
    if current_coin_count < last_frame_counts.coins then
        for i = current_coin_count + 1, last_frame_counts.coins do
            draw_hash_map["coin_" .. i] = nil
        end
        needs_resort = true
    end
    
    -- Update existing/new coins
    for i = 1, current_coin_count do
        local cx, cy = coin_bods[i]:getX(), coin_bods[i]:getY()
        local coin_sort_y = cy + (coin_image:getHeight() * 0.5) / 2
        
        local old_drawable = draw_hash_map["coin_" .. i]
        local new_sort_y = coin_sort_y + 100
        
        -- Only update if position changed or it's a new coin
        if not old_drawable or old_drawable.x ~= cx or old_drawable.y ~= cy then
            draw_hash_map["coin_" .. i] = {
                sort_y = new_sort_y,
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
            }
            
            -- Check if Y position changed enough to need resorting
            if not old_drawable or math.abs(old_drawable.sort_y - new_sort_y) > 1 then
                needs_resort = true
            end
        end
    end
    
    last_frame_counts.coins = current_coin_count
end

-- Update fire effects (assumes fire.getDrawables() returns current fire effects)
function renderer.updateFireEffects()
    local fire_drawables = fire.getDrawables() or {}
    local current_fire_count = #fire_drawables
    
    -- If count decreased, remove excess fire effects
    if current_fire_count < last_frame_counts.fire_effects then
        for i = current_fire_count + 1, last_frame_counts.fire_effects do
            draw_hash_map["fire_" .. i] = nil
        end
        needs_resort = true
    end
    
    -- Update fire effects
    for i = 1, current_fire_count do
        local fire_drawable = fire_drawables[i]
        local old_drawable = draw_hash_map["fire_" .. i]
        
        -- Only update if changed or new
        if not old_drawable or 
           old_drawable.x ~= fire_drawable.x or 
           old_drawable.y ~= fire_drawable.y or
           old_drawable.sort_y ~= fire_drawable.sort_y then
            
            draw_hash_map["fire_" .. i] = fire_drawable
            needs_resort = true
        end
    end
    
    last_frame_counts.fire_effects = current_fire_count
end

-- Update enemy effects (assumes enemy.getDrawables() returns current enemy effects)
function renderer.updateEnemyEffects()
    local enemy_drawables = enemy.getDrawables() or {}
    local current_enemy_effects_count = #enemy_drawables
    
    -- If count decreased, remove excess enemy effects
    if current_enemy_effects_count < last_frame_counts.enemy_effects then
        for i = current_enemy_effects_count + 1, last_frame_counts.enemy_effects do
            draw_hash_map["enemy_effect_" .. i] = nil
        end
        needs_resort = true
    end
    
    -- Update enemy effects
    for i = 1, current_enemy_effects_count do
        local enemy_drawable = enemy_drawables[i]
        local old_drawable = draw_hash_map["enemy_effect_" .. i]
        
        -- Only update if changed or new
        if not old_drawable or 
           old_drawable.x ~= enemy_drawable.x or 
           old_drawable.y ~= enemy_drawable.y or
           old_drawable.sort_y ~= enemy_drawable.sort_y then
            
            draw_hash_map["enemy_effect_" .. i] = enemy_drawable
            needs_resort = true
        end
    end
    
    last_frame_counts.enemy_effects = current_enemy_effects_count
end

-- Smart populate function - only updates what's necessary
function renderer.smartPopulateDynamicDrawList()
    -- Update only moving/changing elements
    -- renderer.updatePlayer()
    renderer.updatePortal() -- Only if portal params change
    -- renderer.updateEnemies()
    renderer.updateCoins()
    -- renderer.updateFireEffects()
    -- renderer.updateEnemyEffects()
    
    -- Only rebuild sorted list if something changed
    if needs_resort then
        sorted_draw_list = {}
        for key, drawable in pairs(draw_hash_map) do
            if drawable then -- Make sure it's not nil
                table.insert(sorted_draw_list, drawable)
            end
        end
        
        table.sort(sorted_draw_list, renderer.sortByRenderY)
        needs_resort = false
    end
end

-- Optimized render function
function renderer.renderSortedDrawList()
    -- Store current graphics state
    local current_color = { love.graphics.getColor() }
    local current_blend_mode = love.graphics.getBlendMode()
    local current_shader = love.graphics.getShader()

    local last_color = { 1, 1, 1, 1 }
    local last_blend_mode = { "alpha" }

    for _, drawable in ipairs(sorted_draw_list) do
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
            
            love.graphics.rectangle("fill", drawable.x, drawable.y, drawable.width, drawable.height)
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

-- Force a complete rebuild (use sparingly)
function renderer.forceRebuild()
    draw_hash_map = {}
    sorted_draw_list = {}
    last_frame_counts = {
        enemies = 0,
        coins = 0,
        fire_effects = 0,
        enemy_effects = 0
    }
    needs_resort = true
    
    renderer.initializeStaticElements()
end

-- Helper functions for external modules
function renderer.markForResort()
    needs_resort = true
end

function renderer.addCustomDrawable(key, drawable)
    draw_hash_map[key] = drawable
    needs_resort = true
end

function renderer.removeCustomDrawable(key)
    draw_hash_map[key] = nil
    needs_resort = true
end

-- Usage in main.lua:
--[[
function love.load()
    renderer.initializeStaticElements() -- Call once at start
    
    -- Add any additional maps using the preserved function
    renderer.addMapToHashMap(someMapData, 0, 0, 1.0, 0, "background_map")
    renderer.addMapToHashMap(foregroundMapData, 0, 0, 1.0, 1000, "foreground_map")
end

function love.draw()
    -- Smart populate - only updates what changed
    renderer.smartPopulateDynamicDrawList()
    
    -- Render (uses cached sorted list unless something changed)
    renderer.renderSortedDrawList()
end
]]--

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

return renderer