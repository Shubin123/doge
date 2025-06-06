local renderer = {}
-- Dynamic draw list for Y-sorting
local area_manager = require("area_manager")
dynamic_draw_list = {}

-- Sorting function for Y-axis rendering
function renderer.sortByRenderY(drawable_a, drawable_b)
    return drawable_a.sort_y < drawable_b.sort_y
end
flipQuads = true
-- Function to populate dynamic draw list
function renderer.populateDynamicDrawList()
    -- Clear the list
    dynamic_draw_list = {}

    -- Get the current area
    local current_area = area_manager.getCurrentArea()

    -- Add map layers from the current area
    if current_area and current_area.map_layers then
        for _, map_layer in ipairs(current_area.map_layers) do
            -- Assuming addMapToDynamicDrawList takes map data and returns drawables
            -- Need to determine appropriate x, y, scale, and base_sort_y for each layer
            -- For now, using placeholder values or assuming map data includes positioning
            local map_drawables = addMapToDynamicDrawList(map_layer, 100, var.header_height, 1, 200) -- Adjust parameters as needed
            rebuildArray(dynamic_draw_list, map_drawables)
        end
    end

    -- Player drawable
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
    -- Need to get portal positions from the current area's transition_points
    if current_area and current_area.transition_points then
        for _, portal_data in ipairs(current_area.transition_points) do
            table.insert(dynamic_draw_list, {
                sort_y = portal_data.y + 180, -- Adjust depth as needed
                shader = portal.SHADERS["portal"],
                shader_params = portal.params, -- Assuming portal.params is globally accessible or managed
                x = portal_data.x,
                y = portal_data.y,
                width = 35, -- Assuming portal size
                height = 50, -- Assuming portal size
                color = { 1, 1, 1, 1 },
                blend_mode = { "alpha" },
                source_object_type = "portal_shader"
            })
        end
    end
    
    -- Enemies drawables
    -- Assuming enemies_bods is now populated by area_manager.loadArea
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

    -- Coins drawables
    -- Assuming coin_bods is now populated by area_manager.loadArea
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
    -- Assuming fire bodies are now populated by area_manager.loadArea
    -- Need to iterate through fire bodies and add drawables
    -- This part needs to be implemented based on how fire effects are drawn
    -- For now, leaving this section as a placeholder or using existing fire drawing logic if it's separate
    -- The previous fire.populate call is removed as it's in area_manager
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
    -- table.insert(dynamic_draw_list,map_b[1])
    -- table.insert(dynamic_draw_list,map_b[2])
    -- table.insert(dynamic_draw_list,map_b[3])
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