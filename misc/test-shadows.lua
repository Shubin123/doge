-- LÖVE 2D Shader Implementation
local shader

function love.load()
    -- Create the shader
    shader = love.graphics.newShader([[
        uniform float viewangle;
        varying vec2 pos;
        varying float alpha;
        
        #ifdef VERTEX
        vec4 position(mat4 transform_projection, vec4 vertex_position) {
            pos = vertex_position.xy;
            alpha = VaryingColor.a;
            return transform_projection * vertex_position;
        }
        #endif
        
        #ifdef PIXEL
        vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
            vec2 delta = vec2(
                pos.x * cos(viewangle) - pos.y * sin(viewangle),
                pos.x * sin(viewangle) + pos.y * cos(viewangle)
            );
            delta = normalize(-delta);
            delta.y *= -1.0;
            return vec4(delta.xyx * alpha * 0.10, 1.0);
        }
        #endif
    ]])
    
    -- Set initial view angle
    viewangle = 0
end

function love.update(dt)
    -- Auto rotation (comment out if you want manual control only)
    viewangle = viewangle + dt * 0.5
    
    -- Manual control
    if love.keyboard.isDown("up") then
        viewangle = viewangle + dt * 2
    elseif love.keyboard.isDown("down") then
        viewangle = viewangle - dt * 2
    end
    
    -- Send the uniform to the shader
    shader:send("viewangle", viewangle)
end

function love.draw()
    -- Use the shader
    love.graphics.setShader(shader)
    
    -- Draw some geometry to see the effect
    -- You can replace this with your actual geometry
    love.graphics.setColor(1, 1, 1, 0.8) -- Set alpha for the effect
    
    -- Draw a rectangle
    love.graphics.rectangle("fill", 200, 200, 400, 300)
    
    -- Draw some circles
    love.graphics.circle("fill", 100, 100, 50)
    love.graphics.circle("fill", 700, 500, 80)
    
    -- Reset shader
    love.graphics.setShader()
    
    -- Draw instructions
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("View Angle: " .. string.format("%.2f", viewangle), 10, 10)
    love.graphics.print("Press SPACE to reset angle", 10, 30)
    love.graphics.print("Press UP/DOWN to manually control angle", 10, 50)
end

function love.keypressed(key)
    if key == "space" then
        viewangle = 0
    end
end