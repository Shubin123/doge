-- Wind distortion shader for trees in LÖVE2D
local wind = {}

-- Shader code (GLSL)
local windCode = [[
uniform float time;
const float amplitude = 0.01;
uniform float time_scale = 0.04;
uniform float noise_scale = 0.001;
uniform float rotation_strength = 0.5;
uniform vec2 rotation_pivot = vec2(0.5, 1.0);
uniform bool render_noise = false;
uniform Image noise_texture;
uniform vec2 world_position;

vec2 get_sample_pos(vec2 pos, float scale, float offset) {
    pos *= scale;
    pos += offset;
    return pos;
}

vec2 rotate_vec(vec2 vec, vec2 pivot, float rotation) {
    float cosa = cos(rotation);
    float sina = sin(rotation);
    vec -= pivot;
    return vec2(
        cosa * vec.x - sina * vec.y,
        cosa * vec.y + sina * vec.x
    ) + pivot;
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    // Calculate world position based on screen coordinates
    vec2 world_pos = world_position + screen_coords;
    
    // Get noise from texture
    vec2 noise_sample_pos = get_sample_pos(world_pos, noise_scale, time * time_scale);
    float noise_amount = Texel(noise_texture, noise_sample_pos).r - 0.5;
    
    // Get rotation position around a pivot
    float rotation = amplitude * noise_amount;
    vec2 rotated_uvs = rotate_vec(texture_coords, rotation_pivot, rotation);
    
    // Blend original uvs and rotated uvs based on distance to pivot
    float dist = distance(texture_coords, rotation_pivot) * rotation_strength;
    vec2 result_uvs = mix(texture_coords, rotated_uvs, dist);
    
    // Sample the texture with distorted coordinates
    vec4 pixel_color = Texel(texture, result_uvs) * color;
    
    // Optional: preview noise texture for debugging
    if (render_noise) {
        vec4 noise_color = Texel(noise_texture, noise_sample_pos);
        return noise_color;
    }
    
    return pixel_color;
}
]]

-- Initialize the shader system
function wind.load()
    -- Create noise texture for wind effect
    wind.noiseTexture = wind.generateNoiseTexture(256, 256)
    
    -- Compile the shader
    wind.shader = love.graphics.newShader(windCode)
    
    -- Set default parameters
    wind.params = {
        amplitude = 0.2,
        time_scale = 0.04,
        noise_scale = 0.001,
        rotation_strength = 1.0,
        rotation_pivot = {0.5, 1.0},
        render_noise = false
    }
    
    -- Send noise texture to shader
    wind.shader:send("noise_texture", wind.noiseTexture)
    -- wind.updateShaderParams()
end

-- Generate a simple noise texture
function wind.generateNoiseTexture(width, height)
    local imageData = love.image.newImageData(width, height)
    
    -- Simple noise generation
    for x = 0, width - 1 do
        for y = 0, height - 1 do
            local noise = love.math.random()
            imageData:setPixel(x, y, noise, noise, noise, 1)
        end
    end
    
    local texture = love.graphics.newImage(imageData)
    texture:setWrap("repeat", "repeat")
    return texture
end

-- Update shader parameters
function wind.updateShaderParams()
    if wind.shader then
        wind.shader:send("amplitude", wind.params.amplitude)
        wind.shader:send("time_scale", wind.params.time_scale)
        wind.shader:send("noise_scale", wind.params.noise_scale)
        wind.shader:send("rotation_strength", wind.params.rotation_strength)
        wind.shader:send("rotation_pivot", wind.params.rotation_pivot)
        wind.shader:send("render_noise", wind.params.render_noise)
    end
end

-- Update the shader with time
function wind.update(dt)
    if wind.shader then
        wind.shader:send("time", love.timer.getTime())
    end
end

-- Integration with the map system
-- Modify the tree creation to include wind shader component
function map.createTreeWithWind(x, y)
    local tree = map.createDynamicObject({
        type = "tree",
        x = x + 78,
        y = y + 78,
        width = 156,
        height = 156,
        physics = {
            type = "static",
            shape = love.physics.newCircleShape(20),
        },
    })

    tree:addComponent("visual", {
        offset_x = -78,
        offset_y = -78,
        tilesetIndex = 4,
        tileId = 1,
        scale = 0.8,
        usewind = true, -- Enable wind shader for this tree
    })

    tree:addComponent("shadow", {
        init = function(self, owner)
            self.radius = 30
            self.opacity = 0.3
        end,
        getDynamicDrawItem = function(self, owner)
            return {
                sort_y = owner.y - 1,
                draw_type = "circle",
                x = owner.x,
                y = owner.y + 40,
                radius = self.radius,
                color = {0, 0, 0, self.opacity},
                blend_mode = {"alpha"},
                source_object_type = "tree_shadow",
            }
        end,
    })

    tree.x = x
    tree.y = y
    
    local originalMove = tree.move
    tree.move = function(self, new_x, new_y)
        self.x = new_x
        self.y = new_y
        originalMove(self, new_x + 78, new_y + 78)
    end

    table.insert(map.treeInstances, tree)
    return tree
end

-- Modified addMapToDynamicDrawList function for trees with wind shader
-- function map.addTreesWithWindToDynamicDrawList(mapData, map_x, map_y, map_scale, base_sort_y)
--     local drawItems = {}
    
--     if mapData == map.tree then
--         for _, tree in ipairs(map.treeInstances) do
--             if tree.active then
--                 local visual = tree:getComponent("visual")
--                 if visual then
--                     local shadow = tree:getComponent("shadow")
--                     if shadow and shadow.getDynamicDrawItem then
--                         table.insert(drawItems, shadow:getDynamicDrawItem(tree))
--                     end

--                     -- Create tree draw item with potential wind shader
--                     local drawItem = {
--                         sort_y = base_sort_y + tree.y,
--                         image_or_particles = map.tiles4.tilesetImage,
--                         quad = map.tiles4.quads[visual.tileId],
--                         x = tree.x + visual.offset_x,
--                         y = tree.y + visual.offset_y,
--                         rotation = tree.rotation,
--                         scale_x = map_scale * visual.scale * tree.scale,
--                         scale_y = map_scale * visual.scale * tree.scale,
--                         offset_x = 0,
--                         offset_y = 0,
--                         color = tree.color,
--                         blend_mode = {"alpha"},
--                         source_object_type = "tree",
--                         object_id = tree.id,
--                     }
                    
--                     -- Add wind shader if enabled
--                     if visual.usewind and wind.shader then
--                         drawItem.shader = wind.shader
--                         drawItem.shader_params = {
--                             world_position = {tree.x, tree.y}
--                         }
--                         drawItem.source_object_type = "tree_with_wind"
--                     end
                    
--                     table.insert(drawItems, drawItem)
--                     -- performance.objectsRendered = performance.objectsRendered + 1
--                 end
--             end
--         end
--     end
    
--     return drawItems
-- end

-- -- Integration with renderer
-- function wind.integrateWithRenderer()
--     -- Store original renderer function
--     local originalRenderFunction = renderer.renderSortedDrawList
    
--     -- Override the render function to handle wind shader
--     renderer.renderSortedDrawList = function()
--         -- Store current graphics state
--         local current_color = { love.graphics.getColor() }
--         local current_blend_mode = love.graphics.getBlendMode()
--         local current_shader = love.graphics.getShader()

--         local last_color = { 1, 1, 1, 1 }
--         local last_blend_mode = { "alpha" }

--         for _, drawable in ipairs(dynamic_draw_list) do
--             -- Set color if different from last
--             if drawable.color[1] ~= last_color[1] or drawable.color[2] ~= last_color[2] or
--                 drawable.color[3] ~= last_color[3] or drawable.color[4] ~= last_color[4] then
--                 love.graphics.setColor(drawable.color[1], drawable.color[2], drawable.color[3], drawable.color[4])
--                 last_color = drawable.color
--             end

--             -- Set blend mode if different from last
--             local blend_mode = drawable.blend_mode or {"alpha"}
--             if blend_mode[1] ~= last_blend_mode[1] or
--                 (blend_mode[2] and blend_mode[2] ~= last_blend_mode[2]) then
--                 if blend_mode[2] then
--                     love.graphics.setBlendMode(blend_mode[1], blend_mode[2])
--                 else
--                     love.graphics.setBlendMode(blend_mode[1])
--                 end
--                 last_blend_mode = blend_mode
--             end

--             -- Handle tree with wind shader
--             if drawable.source_object_type == "tree_with_wind" and drawable.shader then
--                 love.graphics.setShader(drawable.shader)
                
--                 -- Send world position to shader
--                 if drawable.shader_params and drawable.shader_params.world_position then
--                     drawable.shader:send("world_position", drawable.shader_params.world_position)
--                 end
                
--                 -- Draw the tree with shader
--                 if drawable.quad then
--                     love.graphics.draw(
--                         drawable.image_or_particles,
--                         drawable.quad,
--                         drawable.x,
--                         drawable.y,
--                         drawable.rotation or 0,
--                         drawable.scale_x or 1,
--                         drawable.scale_y or 1,
--                         drawable.offset_x or 0,
--                         drawable.offset_y or 0
--                     )
--                 end
                
--                 love.graphics.setShader()
--             else
--                 -- Handle other drawables normally (call original logic)
--                 -- ... (rest of the original rendering logic)
--                 if drawable.image_or_particles then
--                     if drawable.quad then
--                         love.graphics.draw(
--                             drawable.image_or_particles,
--                             drawable.quad,
--                             drawable.x,
--                             drawable.y,
--                             drawable.rotation or 0,
--                             drawable.scale_x or 1,
--                             drawable.scale_y or 1,
--                             drawable.offset_x or 0,
--                             drawable.offset_y or 0
--                         )
--                     else
--                         love.graphics.draw(
--                             drawable.image_or_particles,
--                             drawable.x,
--                             drawable.y,
--                             drawable.rotation or 0,
--                             drawable.scale_x or 1,
--                             drawable.scale_y or 1,
--                             drawable.offset_x or 0,
--                             drawable.offset_y or 0
--                         )
--                     end
--                 end
--             end
--         end

--         -- Restore original graphics state
--         love.graphics.setColor(current_color[1], current_color[2], current_color[3], current_color[4])
--         love.graphics.setBlendMode(current_blend_mode)
--         love.graphics.setShader(current_shader)
--     end
-- end

-- Usage example
function wind.createWindyForest(start_x, start_y, count_x, count_y, spacing)
    spacing = spacing or 200
    
    for x = 0, count_x - 1 do
        for y = 0, count_y - 1 do
            local tree_x = start_x + x * spacing + (love.math.random() - 0.5) * spacing * 0.3
            local tree_y = start_y + y * spacing + (love.math.random() - 0.5) * spacing * 0.3
            map.createTreeWithWind(tree_x, tree_y)
        end
    end
end

-- Settings for different wind effects
wind.presets = {
    calm = {
        amplitude = 0.05,
        time_scale = 0.02,
        noise_scale = 0.0005,
        rotation_strength = 0.5
    },
    gentle = {
        amplitude = 0.1,
        time_scale = 0.04,
        noise_scale = 0.001,
        rotation_strength = 1.0
    },
    strong = {
        amplitude = 0.3,
        time_scale = 0.08,
        noise_scale = 0.002,
        rotation_strength = 2.0
    },
    storm = {
        amplitude = 0.5,
        time_scale = 0.15,
        noise_scale = 0.004,
        rotation_strength = 3.0
    }
}

function wind.applyPreset(preset_name)
    local preset = wind.presets[preset_name]
    if preset then
        for key, value in pairs(preset) do
            wind.params[key] = value
        end
        wind.updateShaderParams()
    end
end

return wind