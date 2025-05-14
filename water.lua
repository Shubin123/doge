water = {}
local var = require("var")
local map = require("map")
local W = love.graphics.getWidth()
local H = love.graphics.getHeight()
local game_area_x = (W - var.game_width) / 2
local game_area_y = var.header_height

-- Parameters for the water effect
local water_area = {
    x = 0,       -- Will be set in the update function
    y = 0,       -- Will be set in the update function
    width = 0,   -- Will be set in the update function
    height = 0   -- Will be set in the update function
}

local time = 0  -- Time accumulator for water animation

function water.load()
    -- Create canvases for different stages of the effect
    -- scene_canvas = love.graphics.newCanvas(var.game_width, var.game_height, { format = "rgba8" })
    
    reflection_canvas = love.graphics.newCanvas(var.game_width, var.game_height, { format = "rgba8" })
    water_canvas = love.graphics.newCanvas(var.game_width, var.game_height, { format = "rgba8" })
    
    -- Load noise texture for water distortion
    noise_texture = love.graphics.newImage("gfx/noise.png")
    noise_texture:setWrap("repeat", "repeat")
    
    -- Water distortion shader
    water_distortion_shader = love.graphics.newShader([[
        #pragma language glsl3
        
        uniform Image noiseTexture;
        uniform vec2 noiseScale = vec2(3.0, 3.0);
        uniform vec2 noiseOffset;
        uniform float distortionStrength = 0.02;
        uniform vec4 waterBounds; // x, y, width, height
        uniform float time;
        
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            // Check if we're in the water area
            vec2 relPos = sc - vec2(waterBounds.x, waterBounds.y);
            if (relPos.x >= 0.0 && relPos.x <= waterBounds.z && 
                relPos.y >= 0.0 && relPos.y <= waterBounds.w) {
                
                // Sample noise texture for distortion
                vec2 noiseCoord = (tc * noiseScale) + noiseOffset;
                vec4 noise = Texel(noiseTexture, noiseCoord);
                
                // Create wave motion
                float waveFactor = sin(time * 1.5 + tc.x * 10.0) * 0.5 + 0.5;
                
                // Apply distortion to texture coordinates
                vec2 distortedTC = tc + vec2(
                    (noise.r * 2.0 - 1.0) * distortionStrength * waveFactor,
                    (noise.g * 2.0 - 1.0) * distortionStrength * waveFactor
                );
                
                // Get the distorted pixel color
                vec4 texColor = Texel(tex, distortedTC);
                
                // Add blue tint to water
                vec4 waterColor = vec4(0.2, 0.5, 0.8, 0.8);
                
                // Combine water color with the distorted texture
                return texColor * waterColor * color;
            } else {
                // Outside water area, return normal texture
                return Texel(tex, tc) * color;
            }
        }
    ]])
    
    -- Water reflection shader
    water_reflection_shader = love.graphics.newShader([[
        #pragma language glsl3
        
        uniform Image reflectionTexture;
        uniform Image noiseTexture;
        uniform vec2 noiseScale = vec2(2.0, 2.0);
        uniform vec2 noiseOffset;
        uniform float reflectionStrength = 0.5;
        uniform float rippleStrength = 0.03;
        uniform vec4 waterBounds; // x, y, width, height
        uniform float time;
        
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            // Check if we're in the water area
            vec2 relPos = sc - vec2(waterBounds.x, waterBounds.y);
            if (relPos.x >= 0.0 && relPos.x <= waterBounds.z && 
                relPos.y >= 0.0 && relPos.y <= waterBounds.w) {
                
                // Sample noise texture for ripples
                vec2 noiseCoord = (tc * noiseScale) + noiseOffset;
                vec4 noise = Texel(noiseTexture, noiseCoord);
                
                // Create ripple effect
                float ripple = sin(time * 2.0 + noise.r * 10.0) * rippleStrength;
                
                // Get the base texture color
                vec4 baseColor = Texel(tex, tc);
                
                // Calculate reflection coordinates with ripple distortion
                vec2 reflectionTC = vec2(tc.x, tc.y * -1.0 + 2.0 * (waterBounds.y + waterBounds.w/2) / love_ScreenSize.y);
                reflectionTC += vec2(noise.r * 2.0 - 1.0, noise.g * 2.0 - 1.0) * rippleStrength;
                
                // Get reflection color
                vec4 reflectionColor = Texel(reflectionTexture, reflectionTC);
                
                // Add water blue tint
                vec4 waterColor = vec4(0.2, 0.5, 0.8, 0.7);
                
                // Fade reflection based on y-position within water area
                float reflectionFactor = reflectionStrength * (1.0 - (relPos.y / waterBounds.w) * 0.5);
                
                // Combine colors
                return mix(baseColor * waterColor, reflectionColor, reflectionFactor) * color;
            } else {
                // Outside water area, return normal texture
                return Texel(tex, tc) * color;
            }
        }
    ]])
    
    -- Final water shader that combines distortion and reflection
    water_final_shader = love.graphics.newShader([[
        #pragma language glsl3
        
        uniform Image noiseTexture;
        uniform vec2 noiseScale = vec2(2.5, 2.5);
        uniform vec2 noiseOffset;
        uniform float distortionStrength = 0.025;
        uniform float reflectionStrength = 0.6;
        uniform vec4 waterBounds; // x, y, width, height
        uniform float time;
        uniform Image reflectionTexture;
        
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            // Check if we're in the water area
            vec2 relPos = sc - vec2(waterBounds.x, waterBounds.y);
            if (relPos.x >= 0.0 && relPos.x <= waterBounds.z && 
                relPos.y >= 0.0 && relPos.y <= waterBounds.w) {
                
                // Sample noise texture for distortion and ripples
                vec2 noiseCoord = (tc * noiseScale) + noiseOffset;
                vec4 noise = Texel(noiseTexture, noiseCoord);
                
                // Create ripple effect
                float rippleX = sin(time * 1.5 + tc.y * 20.0) * 0.01;
                float rippleY = cos(time * 2.0 + tc.x * 15.0) * 0.01;
                
                // Apply distortion to texture coordinates
                vec2 distortedTC = tc + vec2(
                    (noise.r * 2.0 - 1.0) * distortionStrength + rippleX,
                    (noise.g * 2.0 - 1.0) * distortionStrength + rippleY
                );
                
                // Get the distorted pixel color
                vec4 texColor = Texel(tex, distortedTC);
                
                // Calculate reflection coordinates
                vec2 reflectionTC = vec2(
                    distortedTC.x,
                    -distortedTC.y + 2.0 * (waterBounds.y + waterBounds.w/2) / love_ScreenSize.y
                );
                
                // Get reflection color with distortion
                vec4 reflectionColor = Texel(reflectionTexture, reflectionTC);
                
                // Add blue tint to water
                vec4 waterColor = vec4(0.2, 0.5, 1, 0.8);
                
                // Fade reflection based on y-position within water area
                float reflectionFactor = reflectionStrength * (1.0 - (relPos.y / waterBounds.w) * 0.5);
                reflectionFactor *= (1.0 + sin(time * 3.0 + noise.b * 5.0) * 0.1); // Animate reflection intensity
                
                // Combine colors
                return mix(texColor * waterColor, reflectionColor, reflectionFactor) * color;
            } else {
                // Outside water area, return normal texture
                return Texel(tex, tc) * color;
            }
        }
    ]])
end

-- Set the water area coordinates - call this to define where the water should appear
function water.setWaterArea(x, y, width, height)
    water_area.x = x
    water_area.y = y
    water_area.width = width
    water_area.height = height
end

function water.update(dt)
    -- Update animation time
    time = time + dt
    
    -- Update noise texture offsets for animation
    local offsetX = math.sin(time * 0.3) * 0.05 + time * 0.05
    local offsetY = math.cos(time * 0.5) * 0.05 + time * 0.03
    
    -- Send uniforms to shaders
    water_distortion_shader:send("noiseOffset", {offsetX, offsetY})
    water_reflection_shader:send("noiseOffset", {offsetX * 0.7, offsetY * 0.7})
    water_final_shader:send("noiseOffset", {offsetX * 0.5, offsetY * 0.5})
    
    water_distortion_shader:send("time", time)
    water_reflection_shader:send("time", time)
    water_final_shader:send("time", time)
    
    -- Send water area bounds to shaders
    water_distortion_shader:send("waterBounds", {water_area.x, water_area.y, water_area.width, water_area.height})
    water_reflection_shader:send("waterBounds", {water_area.x, water_area.y, water_area.width, water_area.height})
    water_final_shader:send("waterBounds", {water_area.x, water_area.y, water_area.width, water_area.height})
end

-- Render the scene that will be reflected in water (usually game objects)
function water.prepass()
    -- Capture the scene before water rendering
    -- love.graphics.setCanvas(scene_canvas)
    -- love.graphics.clear(0, 0, 0, 0)
    
    -- -- Your game rendering code goes here
    -- -- ...
    
    -- -- Capture scene for reflection
    -- love.graphics.setCanvas(reflection_canvas)
    -- love.graphics.clear(0, 0, 0, 0)
    
    -- Draw objects that should be reflected
    -- You can apply a vertical flip here if needed
    
    -- love.graphics.draw(scene_canvas)

end

-- Apply the water effect
function water.pass()
    -- Send the reflection texture to the shader
    water_final_shader:send("reflectionTexture", reflection_canvas)
    water_final_shader:send("noiseTexture", noise_texture)
        

    -- Apply the water effect
    love.graphics.setShader(water_final_shader)
    love.graphics.draw(scene_canvas)
    love.graphics.setShader()
end

-- Example usage in your main.lua
--[[
function love.load()
    water_shader.load()
    -- Set water area (x, y, width, height)
    water_shader.setWaterArea(100, 200, 400, 300)
end

function love.update(dt)
    water_shader.update(dt)
end

function love.draw()
    -- Render the scene that will be reflected
    water_shader.prepass()
    
    -- Draw your game objects here
    -- ...
    
    -- Apply water effect
    water_shader.pass()
end
]]--

return water