-- Hit Effect Distortion Module for LÖVE
-- Integrates with existing rendering system for hit effects

local hit = {}

-- Shader code
local shaderCode = [[
extern float distortion_strength;
extern float distortion_seed;
extern vec2 distortion_center;
extern float distortion_falloff;
extern vec2 sprite_size;

// Simple random function using seed
float random(vec2 st, float seed) {
    return fract(sin(dot(st.xy + seed, vec2(12.9898, 78.233))) * 43758.5453123);
}

// 2D random vector
vec2 random2(vec2 st, float seed) {
    return vec2(
        random(st, seed),
        random(st, seed + 1.0)
    ) * 2.0 - 1.0;
}

#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position) {
    if (distortion_strength <= 0.0) {
        return transform_projection * vertex_position;
    }
    
    // Convert to normalized coordinates within the sprite
    vec2 normalized_pos = vertex_position.xy / sprite_size;
    
    // Calculate distance from distortion center
    vec2 center_offset = normalized_pos - distortion_center;
    float dist_from_center = length(center_offset);
    
    // Create randomized offset
    vec2 random_offset = random2(normalized_pos, distortion_seed);
    
    // Calculate distortion intensity (adapted from original formula)
    float mid_dist = dist_from_center;
    float base_intensity = 0.2 * (-0.03 - 0.3 * max(0.0, 0.3 - mid_dist));
    float distance_factor = (dist_from_center * dist_from_center) / (2.0 - mid_dist);
    
    // Apply randomized distortion
    float distortion_amount = base_intensity * distortion_strength * distance_factor * distortion_falloff;
    vec2 distortion_vector = random_offset * distortion_amount;
    
    // Apply distortion to vertex position
    vec4 distorted_position = vertex_position;
    distorted_position.xy += distortion_vector * sprite_size;
    
    // Add depth displacement for "bulge" effect
    float depth_displacement = distortion_amount * 1;
    
    return transform_projection * distorted_position + vec4(0, 0, 0, depth_displacement);
}
#endif
]]

-- Initialize module
function hit.init()
    hit.shader = love.graphics.newShader(shaderCode)
    hit.hitEffects = {} -- Track active hit effects
    
    -- Default settings
    hit.defaultStrength = 0.8
    hit.defaultDuration = 0.5
    hit.defaultCenter = {0.5, 0.5}
    hit.defaultFalloff = 1.0
end

-- Mark an object as hit (call this when something gets hit)
function hit.markHit(objectId, strength, duration)
    hit.hitEffects[objectId] = {
        startTime = love.timer.getTime(),
        startStrength = strength or hit.defaultStrength,
        duration = duration or hit.defaultDuration,
        seed = love.math.random() * 1000
    }
end

-- Remove hit effect (manual cleanup)
function hit.removeHit(objectId)
    hit.hitEffects[objectId] = nil
end

-- Check if object should have distortion applied
function hit.shouldDistort(objectId)
    local effect = hit.hitEffects[objectId]
    if not effect then return false end
    
    local elapsed = love.timer.getTime() - effect.startTime
    if elapsed >= effect.duration then
        hit.hitEffects[objectId] = nil -- Auto cleanup
        return false
    end
    
    return true
end

-- Get current distortion strength for an object
function hit.getDistortionStrength(objectId)
    local effect = hit.hitEffects[objectId]
    if not effect then return 0 end
    
    local elapsed = love.timer.getTime() - effect.startTime
    local progress = elapsed / effect.duration
    
    if progress >= 1 then
        hit.hitEffects[objectId] = nil
        return 0
    end
    
    -- Linear falloff
    return effect.startStrength * (1 - progress)
end

-- Apply distortion shader for a specific drawable
function hit.applyToDrawable(drawable, objectId)
    -- if not hit.shouldDistort(objectId) then
    --     return false -- No distortion needed
    -- end
    
    
    -- local effect = hit.hitEffects[objectId]
    
    local strength = 1
    -- print()
    -- for k,v in pairs(effect) do print(k,v) end
    -- Get sprite dimensions
    local width, height = 32, 32 -- Default fallback
    if drawable.image_or_particles and drawable.image_or_particles.getWidth then
        width = drawable.image_or_particles:getWidth() * (drawable.scale_x or 1)
        height = drawable.image_or_particles:getHeight() * (drawable.scale_y or 1)
    end
    
    hit.defaultCenter = require("vec2").new( 0.5,0.5)*player.body:getPosition()
    -- Set shader parameters
    hit.shader:send("distortion_strength", 1)
    hit.shader:send("distortion_seed", 0.01)
    hit.shader:send("distortion_center", {hit.defaultCenter.x , hit.defaultCenter.y } )
    hit.shader:send("distortion_falloff", 0.05)
    hit.shader:send("sprite_size", {1,1})
    
    return true -- Distortion was applied
end

-- Modified render function that integrates with your existing system
function hit.renderDrawableWithDistortion(drawable)
    local objectId = drawable.source_object_type
    
    -- Check if this object needs distortion
    local needsDistortion = hit.shouldDistort(objectId)
    -- if needsDistortion then
    --     print(needsDistortion)
    --     print(objectId)
    --     debug.debug()
    -- end
    -- if (needsDistortion) then
    -- print(drawable.source_object_type, needsDistortion)
    -- end
    local prevShader = nil
    
    -- if needsDistortion then
        prevShader = love.graphics.getShader()
        hit.applyToDrawable(drawable, drawable.source_object_type)
        love.graphics.setShader(hit.shader)
    -- end
    
    -- Draw the sprite normally
    if drawable.image_or_particles then
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
    
    -- Restore previous shader
    -- if needsDistortion then
        -- love.graphics.setShader(prevShader)
    -- end
end

-- Integration helper: modify your existing renderSortedDrawList function
function hit.integrateWithRenderLoop()
    -- This replaces the image drawing part in your renderSortedDrawList function
    return function(drawable)
        -- Handle shader drawing (your existing shader code)
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
            
        -- Handle regular image drawing with potential distortion
        elseif drawable.image_or_particles then
            hit.renderDrawableWithDistortion(drawable)
        end
    end
end

-- Usage example for integration:
--[[
-- In your initialization:
hit.init()

-- When something gets hit (e.g., player takes damage):
hit.markHit("player", 1.0, 0.5) -- Strong distortion for 0.5 seconds

-- When enemy gets hit:
hit.markHit("enemy_" .. enemyIndex, 0.6, 0.3)

-- In your populateDynamicDrawList, add object_id to drawables:
table.insert(dynamic_draw_list, {
    sort_y = sort_y + 45,
    image_or_particles = player.animation.spriteSheet,
    quad = player.animation.quads[spriteNum],
    x = px, y = py,
    rotation = var.character_rotation,
    scale_x = player.scale, scale_y = player.scale,
    offset_x = 35, offset_y = 50,
    color = { 1, 1, 1, 1 },
    blend_mode = { "alpha" },
    source_object_type = "player",
    object_id = "main" -- Add this for unique identification
})

-- Replace your image drawing section in renderSortedDrawList with:
elseif drawable.image_or_particles then
    hit.renderDrawableWithDistortion(drawable)
--]]

return hit