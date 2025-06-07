water = {}

-- print(vec4)
local vec4 = require("vec4")
local water_area =  vec4.new(0,0,0,0)



-- -- Parameters for the water effect
-- local water_area = {
--     x = 0,       -- World coordinates
--     y = 0,       -- World coordinates
--     width = 0,
--     height = 0
-- }

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
    -- water_distortion_shader = love.graphics.newShader([[
    --     //#pragma language glsl3
        
    --     uniform Image noiseTexture;
    --     uniform vec2 noiseScale = vec2(3.0, 3.0);
    --     uniform vec2 noiseOffset;
    --     uniform float distortionStrength = 2;
    --     uniform vec4 waterBounds; // x, y, width, height (screen space)
    --     uniform float time;
        
    --     vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    --         // Check if we're in the water area (sc is screen coordinates)
    --         vec2 relPos = sc - vec2(waterBounds.x, waterBounds.y);
    --         if (relPos.x >= 0.0 && relPos.x <= waterBounds.z && 
    --             relPos.y >= 0.0 && relPos.y <= waterBounds.w) {
                
    --             // Sample noise texture for distortion
    --             vec2 noiseCoord = (tc * noiseScale) + noiseOffset;
    --             vec4 noise = Texel(noiseTexture, noiseCoord);
                
    --             // Create wave motion
    --             float waveFactor = sin(time * 1.5 + tc.x * 10.0) * 0.5 + 0.5;
                
    --             // Apply distortion to texture coordinates
    --             vec2 distortedTC = tc + vec2(
    --                 (noise.r * 2.0 - 1.0) * distortionStrength * waveFactor,
    --                 (noise.g * 2.0 - 1.0) * distortionStrength * waveFactor
    --             );
                
    --             // Get the distorted pixel color
    --             vec4 texColor = Texel(tex, distortedTC);
                
    --             // Add blue tint to water
    --             vec4 waterColor = vec4(0.2, 0.5, 0.8, 0.8);
                
    --             // Combine water color with the distorted texture
    --             return texColor * waterColor * color;
    --         } else {
    --             // Outside water area, return normal texture
    --             return Texel(tex, tc) * color;
    --         }
    --     }
    -- ]])
        
    -- Final water shader that combines distortion and reflection
    water_final_shader = love.graphics.newShader([[
        //#pragma language glsl3
        
        uniform Image noiseTexture;
        uniform vec2 noiseScale = vec2(2.5, 2.5);
        uniform vec2 noiseOffset;
        uniform float distortionStrength = 0.015;
        uniform float reflectionStrength = 0.1;
        uniform vec4 waterBounds; // x, y, width, height (screen space)
        uniform float time;
        uniform Image reflectionTexture;
        
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            // Check if we're in the water area (sc is screen coordinates)
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

-- Set the water area coordinates in world space
function water.setWaterArea(x, y, width, height)
    -- water_area.x = x
    -- water_area.y = y
    -- water_area.width = width
    -- water_area.height = height
    water_area.x = x
    water_area.y = y
    water_area.w = width
    water_area.z = height
end

function water.update(dt)
    -- Update animation time
    time = time + dt
    
    -- Update noise texture offsets for animation
    local offsetX = math.sin(time * 0.3) * 0.05 + time * 0.05
    local offsetY = math.cos(time * 0.5) * 0.05 + time * 0.03
    
    -- Send uniforms to shaders
    -- water_distortion_shader:send("noiseOffset", {offsetX, offsetY})
    water_final_shader:send("noiseOffset", {offsetX * 0.5, offsetY * 0.5})
    
    -- water_distortion_shader:send("time", time)
    water_final_shader:send("time", time)
    
    -- Convert world space water bounds to screen space by subtracting camera offset
    local water_area = water_area*camera.zoom
    local screen_water = camera.pos + vec2.new(water_area.x ,water_area.y)

    -- Send screen-space water area bounds to shaders
    -- water_distortion_shader:send("waterBounds", {screen_water.x, screen_water.y, water_area.w, water_area.z})
    water_final_shader:send("waterBounds", {screen_water.x, screen_water.y, water_area.w, water_area.z})
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

return water