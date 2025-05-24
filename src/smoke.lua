smoke = {}
local var = require("var")
local map = require("map")
local player = require("player")
local W = love.graphics.getWidth()
local H = love.graphics.getHeight()
local game_area_x = (W - var.game_width) / 2
local game_area_y = var.header_height
local camera = require("camera") -- Add camera module reference

-- Parameters for the smoke effect
local smoke_area = {
    x = 0,       -- Will be set in the update function
    y = 0,       -- Will be set in the update function
    width = 0,   -- Will be set in the update function
    height = 0   -- Will be set in the update function
}

local time = 0  -- Time accumulator for smoke animation

function smoke.load()
    -- Create canvases for different stages of the effect
    -- scene_canvas = love.graphics.newCanvas(var.game_width, var.game_height, { format = "rgba8" })
    
    reflection_canvas = love.graphics.newCanvas(var.game_width, var.game_height, { format = "rgba8" })
    smoke_canvas = love.graphics.newCanvas(var.game_width, var.game_height, { format = "rgba8" })
    
    -- Load noise texture for smoke distortion
    noise_texture = love.graphics.newImage("gfx/noise.png")
    noise_texture:setWrap("repeat", "repeat")
    
    -- smoke distortion shader
    smoke_distortion_shader = love.graphics.newShader([[
        //#pragma language glsl3
        
        uniform Image noiseTexture;
        uniform vec2 noiseScale = vec2(3.0, 3.0);
        uniform vec2 noiseOffset;
        uniform float distortionStrength = 2;
        uniform vec4 smokeBounds; // x, y, width, height
        uniform float time;
        
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            // Check if we're in the smoke area
            vec2 relPos = sc - vec2(smokeBounds.x, smokeBounds.y);
            if (relPos.x >= 0.0 && relPos.x <= smokeBounds.z && 
                relPos.y >= 0.0 && relPos.y <= smokeBounds.w) {
                
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
                
                // Add blue tint to smoke
                vec4 smokeColor = vec4(0.2, 0.5, 0.8, 0.8);
                
                // Combine smoke color with the distorted texture
                return texColor * smokeColor * color;
            } else {
                // Outside smoke area, return normal texture
                return Texel(tex, tc) * color;
            }
        }
    ]])
        
    -- Final smoke shader that combines distortion and reflection
    smoke_final_shader = love.graphics.newShader([[
        //#pragma language glsl3
        
        uniform Image noiseTexture;
        uniform vec2 noiseScale = vec2(2.5, 2.5);
        uniform vec2 noiseOffset;
        uniform float distortionStrength = 0.015;
        uniform float reflectionStrength = 0.1;
        uniform vec4 smokeBounds; // x, y, width, height
        uniform float time;
        uniform Image reflectionTexture;
        
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            // Check if we're in the smoke area
            vec2 relPos = sc - vec2(smokeBounds.x, smokeBounds.y);
            if (relPos.x >= 0.0 && relPos.x <= smokeBounds.z && 
                relPos.y >= 0.0 && relPos.y <= smokeBounds.w) {
                
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
                    -distortedTC.y + 2.0 * (smokeBounds.y + smokeBounds.w/2) / love_ScreenSize.y
                );
                
                // Get reflection color with distortion
                vec4 reflectionColor = Texel(reflectionTexture, reflectionTC);
                
                // Add blue tint to smoke
                vec4 smokeColor = vec4(0.1, 0.1, 0.1, 0.6);
                
                // Fade reflection based on y-position within smoke area
                float reflectionFactor = reflectionStrength * (1.0 - (relPos.y / smokeBounds.w) * 0.5);
                reflectionFactor *= (1.0 + sin(time * 3.0 + noise.b * 5.0) * 0.1); // Animate reflection intensity
                
                // Combine colors
                return mix(texColor * smokeColor, reflectionColor, reflectionFactor) * color;
            } else {
                // Outside smoke area, return normal texture
                return Texel(tex, tc) * color;
            }
        }
    ]])
end

-- Set the smoke area coordinates - call this to define where the smoke should appear
function smoke.setsmokeArea(x, y, width, height)
    smoke_area.x = x
    smoke_area.y = y
    smoke_area.width = width
    smoke_area.height = height
end

function smoke.update(dt)
    -- Update animation time
    time = time + dt
    
    -- Update noise texture offsets for animation
    local offsetX = math.sin(time * 0.3) * 0.05 + time * 0.05
    local offsetY = math.cos(time * 0.5) * 0.05 + time * 0.03
    
    -- Send uniforms to shaders
    smoke_distortion_shader:send("noiseOffset", {offsetX, offsetY})
    -- smoke_reflection_shader:send("noiseOffset", {offsetX * 0.7, offsetY * 0.7})
    smoke_final_shader:send("noiseOffset", {offsetX * 0.5, offsetY * 0.5})
    
    smoke_distortion_shader:send("time", time)
    -- smoke_reflection_shader:send("time", time)
    smoke_final_shader:send("time", time)
    -- smoke_area.x = player.body:getX()
    
    -- smoke_area.y = player.body:getY()
    
    -- Send smoke area bounds to shaders
    smoke_distortion_shader:send("smokeBounds", {camera.x + smoke_area.x, camera.y + smoke_area.y, smoke_area.width, smoke_area.height})
    -- smoke_reflection_shader:send("smokeBounds", {smoke_area.x, smoke_area.y, smoke_area.width, smoke_area.height})
    smoke_final_shader:send("smokeBounds", {camera.x + smoke_area.x, camera.y+smoke_area.y, smoke_area.width, smoke_area.height})
end


-- Apply the smoke effect
function smoke.pass()
    
    
    -- Send the reflection texture to the shader
    smoke_final_shader:send("reflectionTexture", reflection_canvas)
    smoke_final_shader:send("noiseTexture", noise_texture)
        

    -- Apply the smoke effect
    love.graphics.setShader(smoke_final_shader)
    love.graphics.draw(scene_canvas)
    love.graphics.setShader()
    
end

return smoke