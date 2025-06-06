local renderer = {}
-- Dynamic draw list for Y-sorting
dynamic_draw_list = {}

-- Spatial indexing system for efficient culling
renderer.spatial = {
    enabled = true,
    grid_size = 128,  -- Size of each grid cell in world units
    grid = {},  -- 2D grid of object lists
    dirty = true,  -- Whether grid needs rebuilding
    last_camera_x = 0,
    last_camera_y = 0,
    last_view_radius = 0,
    update_threshold = 64  -- Only rebuild if camera moved this much
}

-- Sorting function for Y-axis rendering
function renderer.sortByRenderY(drawable_a, drawable_b)
    local sort_y_a = drawable_a.sort_y or 0
    local sort_y_b = drawable_b.sort_y or 0
    return sort_y_a < sort_y_b
end

-- Spatial indexing functions
function renderer.worldToGrid(world_x, world_y)
    local grid_x = math.floor(world_x / renderer.spatial.grid_size)
    local grid_y = math.floor(world_y / renderer.spatial.grid_size)
    return grid_x, grid_y
end

function renderer.getGridKey(grid_x, grid_y)
    return grid_x .. "," .. grid_y
end

function renderer.addToSpatialGrid(object, x, y, width, height)
    if not renderer.spatial.enabled then return end
    
    width = width or 32
    height = height or 32
    
    -- Calculate grid cells this object spans
    local min_grid_x, min_grid_y = renderer.worldToGrid(x, y)
    local max_grid_x, max_grid_y = renderer.worldToGrid(x + width, y + height)
    
    -- Add object to all relevant grid cells
    for grid_x = min_grid_x, max_grid_x do
        for grid_y = min_grid_y, max_grid_y do
            local key = renderer.getGridKey(grid_x, grid_y)
            if not renderer.spatial.grid[key] then
                renderer.spatial.grid[key] = {}
            end
            table.insert(renderer.spatial.grid[key], object)
        end
    end
end

function renderer.getObjectsInRadius(center_x, center_y, radius)
    if not renderer.spatial.enabled then return {} end
    
    local objects = {}
    local seen = {}  -- Prevent duplicates
    
    -- Calculate grid cells within radius
    local min_grid_x, min_grid_y = renderer.worldToGrid(center_x - radius, center_y - radius)
    local max_grid_x, max_grid_y = renderer.worldToGrid(center_x + radius, center_y + radius)
    
    for grid_x = min_grid_x, max_grid_x do
        for grid_y = min_grid_y, max_grid_y do
            local key = renderer.getGridKey(grid_x, grid_y)
            local cell_objects = renderer.spatial.grid[key]
            
            if cell_objects then
                for _, obj in ipairs(cell_objects) do
                    if not seen[obj] then
                        seen[obj] = true
                        table.insert(objects, obj)
                    end
                end
            end
        end
    end
    
    return objects
end

function renderer.clearSpatialGrid()
    renderer.spatial.grid = {}
end

function renderer.shouldUpdateSpatialGrid()
    if not renderer.spatial.enabled then return false end
    
    if renderer.spatial.dirty then return true end
    
    local dx = math.abs(camera.x - renderer.spatial.last_camera_x)
    local dy = math.abs(camera.y - renderer.spatial.last_camera_y)
    local distance_moved = math.sqrt(dx * dx + dy * dy)
    
    local radius_changed = math.abs(camera.view_radius - renderer.spatial.last_view_radius) > 50
    
    return distance_moved > renderer.spatial.update_threshold or radius_changed
end

function renderer.rebuildSpatialGrid()
    if not renderer.spatial.enabled then return end
    
    -- Clear the grid
    renderer.clearSpatialGrid()
    
    -- Get all map tiles and add them to spatial grid
    local currentMapTiles = map.addCurrentMapToDrawList()
    for _, tile in ipairs(currentMapTiles) do
        local tile_width = tile.width or 32
        local tile_height = tile.height or 32
        renderer.addToSpatialGrid(tile, tile.x, tile.y, tile_width, tile_height)
    end
    
    -- Add enemies to spatial grid
    if enemies_bods then
        for i = 1, #enemies_bods do
            local ex, ey = enemies_bods[i]:getX(), enemies_bods[i]:getY()
            local enemy_width = enemy_image and (enemy_image:getWidth() * 0.1) or 32
            local enemy_height = enemy_image and (enemy_image:getHeight() * 0.1) or 32
            
            local enemy_obj = {
                x = ex, y = ey, width = enemy_width, height = enemy_height,
                body = enemies_bods[i], type = "enemy", index = i
            }
            renderer.addToSpatialGrid(enemy_obj, ex - enemy_width/2, ey - enemy_height/2, enemy_width, enemy_height)
        end
    end
    
    -- Add coins to spatial grid
    if coin_bods then
        for i = 1, #coin_bods do
            local cx, cy = coin_bods[i]:getX(), coin_bods[i]:getY()
            local coin_width = coin_image and (coin_image:getWidth() * 0.5) or 16
            local coin_height = coin_image and (coin_image:getHeight() * 0.5) or 16
            
            local coin_obj = {
                x = cx, y = cy, width = coin_width, height = coin_height,
                body = coin_bods[i], type = "coin", index = i
            }
            renderer.addToSpatialGrid(coin_obj, cx - coin_width/2, cy - coin_height/2, coin_width, coin_height)
        end
    end
    
    -- Update tracking variables
    renderer.spatial.last_camera_x = camera.x
    renderer.spatial.last_camera_y = camera.y
    renderer.spatial.last_view_radius = camera.view_radius
    renderer.spatial.dirty = false
end

flipQuads = true

-- Function to add background filler beyond map edges
function renderer.addBackgroundFiller()
    -- Only add filler if camera can see beyond map boundaries
    local map_bounds = camera.map_bounds
    if not map_bounds.enabled then return end
    
    local view_bounds = camera.view_bounds
    local filler_size = 64  -- Size of filler rectangles
    
    -- Create a seamless dark background beyond map edges
    local filler_color = {0.2, 0.2, 0.25, 1.0}  -- Dark blue-gray
    
    -- Left edge filler
    if view_bounds.x1 < map_bounds.x then
        table.insert(dynamic_draw_list, {
            sort_y = -1000,  -- Behind everything
            x = view_bounds.x1,
            y = view_bounds.y1,
            width = map_bounds.x - view_bounds.x1,
            height = view_bounds.y2 - view_bounds.y1,
            color = filler_color,
            blend_mode = { "alpha" },
            source_object_type = "background_filler"
        })
    end
    
    -- Right edge filler
    if view_bounds.x2 > map_bounds.x + map_bounds.width then
        table.insert(dynamic_draw_list, {
            sort_y = -1000,
            x = map_bounds.x + map_bounds.width,
            y = view_bounds.y1,
            width = view_bounds.x2 - (map_bounds.x + map_bounds.width),
            height = view_bounds.y2 - view_bounds.y1,
            color = filler_color,
            blend_mode = { "alpha" },
            source_object_type = "background_filler"
        })
    end
    
    -- Top edge filler
    if view_bounds.y1 < map_bounds.y then
        table.insert(dynamic_draw_list, {
            sort_y = -1000,
            x = view_bounds.x1,
            y = view_bounds.y1,
            width = view_bounds.x2 - view_bounds.x1,
            height = map_bounds.y - view_bounds.y1,
            color = filler_color,
            blend_mode = { "alpha" },
            source_object_type = "background_filler"
        })
    end
    
    -- Bottom edge filler
    if view_bounds.y2 > map_bounds.y + map_bounds.height then
        table.insert(dynamic_draw_list, {
            sort_y = -1000,
            x = view_bounds.x1,
            y = map_bounds.y + map_bounds.height,
            width = view_bounds.x2 - view_bounds.x1,
            height = view_bounds.y2 - (map_bounds.y + map_bounds.height),
            color = filler_color,
            blend_mode = { "alpha" },
            source_object_type = "background_filler"
        })
    end
end
-- Function to populate dynamic draw list with frustum culling and edge handling
function renderer.populateDynamicDrawList()
    -- Clear the list and add current map tiles (with culling)
    local currentMapTiles = map.addCurrentMapToDrawList()
    dynamic_draw_list = {}
    
    -- Update spatial grid if needed
    if renderer.shouldUpdateSpatialGrid() then
        renderer.rebuildSpatialGrid()
    end
    
    -- Add background filler tiles for areas beyond map edges
    renderer.addBackgroundFiller()
    
    -- Apply frustum culling and LOD to map tiles
    if renderer.spatial.enabled then
        -- Use spatial indexing for more efficient culling
        local visible_tiles = renderer.getObjectsInRadius(camera.x, camera.y, camera.view_radius)
        for _, tile in ipairs(visible_tiles) do
            local tile_width = tile.width or 32
            local tile_height = tile.height or 32
            if camera.isInView(tile.x, tile.y, tile_width, tile_height) and 
               not camera.shouldSkipObject(tile.x, tile.y, tile.source_object_type or "map_tile") then
                table.insert(dynamic_draw_list, tile)
            end
        end
    else
        -- Original linear search
        for i = 1, #currentMapTiles do
            local tile = currentMapTiles[i]
            local tile_width = tile.width or 32
            local tile_height = tile.height or 32
            if camera.isInView(tile.x, tile.y, tile_width, tile_height) and 
               not camera.shouldSkipObject(tile.x, tile.y, tile.source_object_type or "map_tile") then
                table.insert(dynamic_draw_list, tile)
            end
        end
    end
    
    -- Add legacy maps for compatibility using world coordinates
    if map.map3 then
        local map3_tiles = addMapToDynamicDrawList(map.map3, 0, 0, 1, 200)
        rebuildArray(dynamic_draw_list, map3_tiles)
    end
    
    if map.map4 then
        local map4_tiles = addMapToDynamicDrawList(map.map4, 0, 0, 0.8, 240)
        rebuildArray(dynamic_draw_list, map4_tiles)
    end

    -- Player drawable (always visible, no culling needed)
    local px, py = player.body:getX(), player.body:getY()
    local spriteNum = math.floor(player.animation.currentTime / (player.animation.duration) * #player.animation.quads) + 1
    local sort_y = py + (100 * player.scale)
    
    table.insert(dynamic_draw_list, {
        sort_y = sort_y + 45,
        image_or_particles = player.animation.spriteSheet,
        quad = player.animation.quads[spriteNum] or player.animation.quads[1],
        x = px,
        y = py,
        rotation = var.character_rotation,
        scale_x = player.scale,
        scale_y = player.scale,
        offset_x = 32,
        offset_y = 32,
        color = { 1.0, 1.0, 1.0, 1 },
        blend_mode = { "alpha" },
        source_object_type = "player"
    })
    
    -- Portal shader drawable (positioned at specific world location)
    local portal_world_x = 400  -- World coordinates
    local portal_world_y = 300  -- World coordinates
    if camera.isInView(portal_world_x, portal_world_y, 35, 50) then
        table.insert(dynamic_draw_list, {
            sort_y = portal_world_y + 50, -- Use world Y for sorting
            shader = portal.SHADERS["portal"],
            shader_params = portal.params,
            x = portal_world_x,
            y = portal_world_y,
            width = 35,
            height = 50,
            color = { 1.4, 1.2, 1.8, 1 }, -- Moderate purple-blue portal light source
            blend_mode = { "lighten", "premultiplied" },
            source_object_type = "portal_light_source"
        })
    end
    
    -- Enemies drawables with frustum culling
    for i = 1, #enemies_bods do
        local ex, ey = enemies_bods[i]:getX(), enemies_bods[i]:getY()
        local enemy_width = enemy_image:getWidth() * 0.1
        local enemy_height = enemy_image:getHeight() * 0.1
        
        if camera.isInView(ex - enemy_width/2, ey - enemy_height/2, enemy_width, enemy_height) then
            local enemy_sort_y = ey + enemy_height / 2

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
    end

    -- Coins drawables with frustum culling
    for i = 1, #coin_bods do
        local cx, cy = coin_bods[i]:getX(), coin_bods[i]:getY()
        local coin_width = coin_image:getWidth() * 0.5
        local coin_height = coin_image:getHeight() * 0.5
        
        if camera.isInView(cx - coin_width/2, cy - coin_height/2, coin_width, coin_height) and
           not camera.shouldSkipObject(cx, cy, "coin") then
            local coin_sort_y = cy + coin_height / 2

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
    end

    -- Fire effects drawables
    fire.populate()
    enemy.populate()
    
    -- Dynamic particle effects drawables
    if particle_system then
        particle_system.populate()
    end
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
        -- Ensure drawable has color field
        local drawable_color = drawable.color or {1, 1, 1, 1}
        
        -- Set color if different from last
        if drawable_color[1] ~= last_color[1] or drawable_color[2] ~= last_color[2] or
            drawable_color[3] ~= last_color[3] or drawable_color[4] ~= last_color[4] then
            love.graphics.setColor(drawable_color[1], drawable_color[2], drawable_color[3], drawable_color[4])
            last_color = drawable_color
        end

        -- Ensure drawable has blend_mode field
        local drawable_blend_mode = drawable.blend_mode or {"alpha"}
        
        -- Set blend mode if different from last
        if drawable_blend_mode[1] ~= last_blend_mode[1] or
            (drawable_blend_mode[2] and drawable_blend_mode[2] ~= last_blend_mode[2]) then
            if drawable_blend_mode[2] then
                love.graphics.setBlendMode(drawable_blend_mode[1], drawable_blend_mode[2])
            else
                love.graphics.setBlendMode(drawable_blend_mode[1])
            end
            last_blend_mode = drawable_blend_mode
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
            
        -- Handle background filler rectangles
        elseif drawable.source_object_type == "background_filler" then
            love.graphics.rectangle("fill", drawable.x, drawable.y, drawable.width, drawable.height)
            
        -- Handle new map system tiles (from map_manager)
        elseif drawable.quad and drawable.tileset_image then
            love.graphics.draw(
                drawable.tileset_image,
                drawable.quad,
                drawable.x,
                drawable.y,
                drawable.rotation or 0,
                drawable.scale_x or 1,
                drawable.scale_y or 1,
                drawable.offset_x or 0,
                drawable.offset_y or 0
            )
            
        -- Handle regular image drawing
        elseif drawable.image_or_particles then
            -- Apply image shader if specified
            if drawable.image_shader then
                love.graphics.setShader(drawable.image_shader)
                
                -- Send shader uniforms if present
                if drawable.shader_uniforms then
                    for uniform_name, uniform_value in pairs(drawable.shader_uniforms) do
                        drawable.image_shader:send(uniform_name, uniform_value)
                    end
                end
            end
            
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
            
            -- Reset shader after image drawing
            if drawable.image_shader then
                love.graphics.setShader()
            end
        end
    end

    -- Restore original graphics state
    love.graphics.setColor(current_color[1], current_color[2], current_color[3], current_color[4])
    love.graphics.setBlendMode(current_blend_mode)
    love.graphics.setShader(current_shader)
end

function rebuildArray(arr, innerElements)
    -- table.insert(dynamic_draw_list,map_b[1])
    -- table.insert(dynamic_draw_list,map_b[2])
    -- table.insert(dynamic_draw_list,map_b[3])
    for i = 1, #innerElements do
        table.insert(arr, innerElements[i])
    end
end

function addMapToDynamicDrawList(mapData, offset_x, offset_y, map_scale, base_sort_y)
    offset_x = offset_x or 0
    offset_y = offset_y or 0
    map_scale = map_scale or 1

    local dynamic_draw_lists = {}
    
    -- Use world coordinates from the map object if available
    local map_world_x = (mapData.worldX or 0) + offset_x
    local map_world_y = (mapData.worldY or 0) + offset_y
    
    -- Calculate tile dimensions
    local tile_width_scaled = mapData.tiles.tileWidth * map_scale
    local tile_height_scaled = mapData.tiles.tileHeight * map_scale
    
    -- Calculate which tiles are potentially visible based on camera view
    local start_col = math.max(1, math.floor((camera.view_bounds.x1 - map_world_x) / tile_width_scaled) + 1)
    local end_col = math.min(mapData.width or 256, math.ceil((camera.view_bounds.x2 - map_world_x) / tile_width_scaled) + 1)
    local start_row = math.max(1, math.floor((camera.view_bounds.y1 - map_world_y) / tile_height_scaled) + 1)
    local end_row = math.min(mapData.height or 256, math.ceil((camera.view_bounds.y2 - map_world_y) / tile_height_scaled) + 1)

    for row = start_row, end_row do
        for col = start_col, end_col do
            local tileId = mapData.tileData[row] and mapData.tileData[row][col]
            if tileId and tileId > 0 and mapData.tiles.quads[tileId] then
                local tile_world_x = map_world_x + (col - 1) * tile_width_scaled
                local tile_world_y = map_world_y + (row - 1) * tile_height_scaled
                
                -- Additional frustum culling check
                if camera.isInView(tile_world_x, tile_world_y, tile_width_scaled, tile_height_scaled) then
                    local tile_sort_y = base_sort_y + tile_world_y

                    table.insert(dynamic_draw_lists, {
                        sort_y = tile_sort_y,
                        image_or_particles = mapData.tiles.tilesetImage,
                        quad = mapData.tiles.quads[tileId],
                        x = tile_world_x,
                        y = tile_world_y,
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
    end

    return dynamic_draw_lists
end

-- usage in the main.lua -- 
-- function love.draw 

    -- sprite draws: 

    ---- Populate and sort dynamic draw list if neccessary
    -- renderer.populateDynamicDrawList()
    -- table.sort(dynamic_draw_list, renderer.sortByRenderY)
    ---- Render sorted entities
    -- renderer.renderSortedDrawList()

--  end

return renderer