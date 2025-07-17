-- LÖVE 2D Screen Space Drop Shadow System
local objectShader
local shadowShader
local canvas
local shadowOffset = {20, 20}

function love.load()
    -- Create the light-based directional shader for objects
    objectShader = love.graphics.newShader([[
        uniform vec2 lightPos;
        varying vec2 pos;
        
        #ifdef VERTEX
        vec4 position(mat4 transform_projection, vec4 vertex_position) {
            pos = vertex_position.xy;
            return transform_projection * vertex_position;
        }
        #endif
        
        #ifdef PIXEL
        vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
            // Get the original texture color
            vec4 texColor = Texel(texture, texture_coords);
            
            // Calculate direction from current pixel to light
            vec2 lightDir = normalize(lightPos - pos);
            
            // Create a shadow intensity based on distance from light
            float distance = length(lightPos - pos);
            float shadowIntensity = 1.0 - clamp(distance * 0.01, 0.0, 1.0); // Closer = brighter
            
            // Apply lighting effect
            vec3 shadowColor = mix(vec3(0.5), mix(texColor.rgb, vec3(0,1,0), 0.5), shadowIntensity);
            
            // Preserve the original alpha and blend with the input color
            return vec4(shadowColor * color.rgb, texColor.a * color.a);
        }
        #endif
    ]])
    
    -- Create the screen space drop shadow shader
    shadowShader = love.graphics.newShader([[
        uniform vec4 background_color;
        uniform vec4 shadow_color;
        uniform vec2 offset_in_pixels;
        uniform vec2 screen_size;
        
        #ifdef VERTEX
        vec4 position(mat4 transform_projection, vec4 vertex_position) {
            return transform_projection * vertex_position;
        }
        #endif
        
        #ifdef PIXEL
        vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
            // Read current pixel from screen texture
            vec4 current_color = Texel(texture, texture_coords);
            
            // Check if the current color is our background color
            if (length(current_color.rgb - background_color.rgb) < 0.01) {
                
                // Calculate offset texture coordinates using screen_size
                vec2 offset_uv = texture_coords - offset_in_pixels / screen_size;
                
                // Make sure we're within bounds
                if (offset_uv.x >= 0.0 && offset_uv.x <= 1.0 && offset_uv.y >= 0.0 && offset_uv.y <= 1.0) {
                    vec4 offset_color = Texel(texture, offset_uv);
                    
                    // Check if at our offset position we have a color which is not the background
                    if (length(offset_color.rgb - background_color.rgb) > 0.01) {
                        // If so set it to our shadow color
                        current_color = mix(shadow_color,vec4(1),0.5);
                    }
                }
            }
            
            return current_color;
        }
        #endif
    ]])

    a = love.graphics.newImage("apple.png")
    
    -- Create canvas for screen space effects
    canvas = love.graphics.newCanvas(love.graphics.getWidth(), love.graphics.getHeight())
end

local lightPos = {}
function love.update(dt)
    -- Update light position with mouse
    lightPos[1] = love.mouse.getX()
    lightPos[2] = love.mouse.getY()
    
    -- Shadow offset control
    if love.keyboard.isDown("=") or love.keyboard.isDown("kp+") then
        shadowOffset[1] = shadowOffset[1] + dt * 30
        shadowOffset[2] = shadowOffset[2] + dt * 30
    elseif love.keyboard.isDown("-") or love.keyboard.isDown("kp-") then
        shadowOffset[1] = shadowOffset[1] - dt * 30
        shadowOffset[2] = shadowOffset[2] - dt * 30
    end
    -- shadowOffset[1] = math.max(1, shadowOffset[1])
    -- shadowOffset[2] = math.max(1, shadowOffset[2])
    
    -- Arrow key controls for shadow direction
    if love.keyboard.isDown("up") then
        shadowOffset[2] = shadowOffset[2] - dt * 30
    elseif love.keyboard.isDown("down") then
        shadowOffset[2] = shadowOffset[2] + dt * 30
    end
    if love.keyboard.isDown("left") then
        shadowOffset[1] = shadowOffset[1] - dt * 30
    elseif love.keyboard.isDown("right") then
        shadowOffset[1] = shadowOffset[1] + dt * 30
    end
    
    -- Send uniforms to shaders
    objectShader:send("lightPos", lightPos)
    shadowShader:send("background_color", {0.3, 0.3, 0.3, 1.0})
    shadowShader:send("shadow_color", {1, 0.0, 0.0, 0.5})
    shadowShader:send("offset_in_pixels", {love.mouse.getX(), love.mouse.getY()})
    shadowShader:send("screen_size", {love.graphics.getWidth(), love.graphics.getHeight()})
end

function love.draw()
    -- PASS 1: Render scene to canvas
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.3, 0.3, 0.3, 1) -- Background color
    
    -- Draw objects with lighting shader
    love.graphics.setShader(objectShader)
    love.graphics.setColor(1, 1, 1, 1)
    
    -- Draw rectangles
    love.graphics.rectangle("fill", 200, 200, 100, 80)
    love.graphics.rectangle("fill", 450, 300, 80, 60)
    love.graphics.rectangle("fill", 300, 400, 120, 40)
    love.graphics.rectangle("fill", 150, 350, 60, 100)
    
    -- Draw circles
    love.graphics.circle("fill", 100, 150, 30)
    love.graphics.circle("fill", 100, 500, 50)
    love.graphics.circle("fill", 100, 100, 40)
    love.graphics.circle("fill", 600, 150, 30)
    love.graphics.circle("fill", 500, 500, 50)
    
    -- Draw image
    love.graphics.draw(a, 100, 100, 0, 1)
    
    -- Draw light source
    love.graphics.setShader()
    love.graphics.setColor(1, 1, 0, 0.8)
    love.graphics.circle("fill", lightPos[1], lightPos[2], 12)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("line", lightPos[1], lightPos[2], 40)
    
    love.graphics.setCanvas()
    
    -- PASS 2: Apply drop shadow effect to the rendered scene
    love.graphics.setShader(shadowShader)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas, 0, 0)
    
    -- Reset shader for UI
    love.graphics.setShader()
    
    -- Draw UI
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Screen Space Drop Shadow System", 10, 10)
    love.graphics.print("Shadow Offset: " .. string.format("%.1f, %.1f", shadowOffset[1], shadowOffset[2]), 10, 30)
    love.graphics.print("Light Position: " .. lightPos[1] .. ", " .. lightPos[2], 10, 50)
    love.graphics.print("", 10, 70)
    love.graphics.print("Controls:", 10, 90)
    love.graphics.print("  Mouse: Move light source", 10, 110)
    love.graphics.print("  +/-: Control shadow distance", 10, 130)
    love.graphics.print("  Arrow keys: Control shadow direction", 10, 150)
    love.graphics.print("", 10, 170)
    love.graphics.print("Screen space shadows - no duplicate draws!", 10, 190)
    love.graphics.print("Objects show directional lighting", 10, 210)
end

function love.resize(w, h)
    -- Recreate canvas on window resize
    canvas = love.graphics.newCanvas(w, h)
    -- Update screen size uniform
    shadowShader:send("screen_size", {w, h})
end