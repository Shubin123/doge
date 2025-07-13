-- LÖVE 2D Combined Object and Shadow Shaders
local objectShader
local shadowShader
local shadowOffset = 20

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
        
        // Calculate direction from current pixel to light (not light to pixel)
        vec2 lightDir = normalize(lightPos - pos);
        
        // Create a shadow intensity based on distance and direction from light
        float distance = length(lightPos - pos);
        float shadowIntensity = 1.0 - clamp(distance * 0.01, 0.0, 1.0); // Closer = brighter
        
        // Optional: Add directional component if you want directional lighting
        // shadowIntensity *= (dot(lightDir, vec2(0.0, -1.0)) * 0.5 + 0.5);
        
        // Apply shadow as a darkening effect (black/white gradient)
        vec3 shadowColor = mix(vec3(0.0), mix(texColor.rgb,vec3(0,1,0),0.5), shadowIntensity);
        
        // Preserve the original alpha and blend with the input color
        return vec4(shadowColor * color.rgb, texColor.a * color.a);
    }
    #endif
]])
    
    -- Create the shadow casting shader
    shadowShader = love.graphics.newShader([[
    uniform vec2 midpoint;
    uniform float offset;
    
    varying float originalAlpha;
    
    #ifdef VERTEX
    vec4 position(mat4 transform_projection, vec4 vertex_position) {
        vec2 vert = vertex_position.xy;
        vec2 vert2 = normalize(vert - midpoint);
        float mult = offset;
        
        // Use the real Z coordinate - Z = 0 for objects, Z = 1 for shadows
        mult = mix(offset, 10000.0, 0);
        
        vert += vert2 * mult;
        
        // Preserve the original alpha channel
        originalAlpha = VaryingColor.a;
        
        return transform_projection * vec4(vert, 0.0, 1.0);
    }
    #endif
    
    #ifdef PIXEL
    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
        // Use the original alpha channel instead of hardcoded 0.5
        return vec4(0.0, 0.0, 0.0, originalAlpha); // Semi-transparent black shadows with original alpha
    }
    #endif
]])

    a = love.graphics.newImage("apple.png")
end
local lightPos = {}
function love.update(dt)
    -- Update light position with mouse
    lightPos[1] = love.mouse.getX()
    lightPos[2] = love.mouse.getY()
    
    -- Shadow distance control
    if love.keyboard.isDown("=") or love.keyboard.isDown("kp+") then
        shadowOffset = shadowOffset + dt * 30
    elseif love.keyboard.isDown("-") or love.keyboard.isDown("kp-") then
        shadowOffset = shadowOffset - dt * 30
    end
    shadowOffset = math.max(1, shadowOffset) -- Minimum shadow distance
    
    -- Send uniforms to shaders
    objectShader:send("lightPos", lightPos)
    shadowShader:send("midpoint", lightPos)
    shadowShader:send("offset", shadowOffset)
end

-- Helper function to create shadow geometry
function createShadowMesh(x, y, w, h)
    local vertices = {
        -- Original object vertices (Z = 0)
        {x, y, 0, 0, 0, 1, 1, 1, 1},
        {x + w, y, 0, 1, 0, 1, 1, 1, 1},
        {x + w, y + h, 0, 1, 1, 1, 1, 1, 1},
        {x, y + h, 0, 0, 1, 1, 1, 1, 1},
        
        -- Shadow vertices (Z = 1)
        {x, y, 1, 0, 0, 1, 1, 1, 1},
        {x + w, y, 1, 1, 0, 1, 1, 1, 1},
        {x + w, y + h, 1, 1, 1, 1, 1, 1, 1},
        {x, y + h, 1, 0, 1, 1, 1, 1, 1},
    }
    
    local indices = {
        -- Object quad
        1, 2, 3, 1, 3, 4,
        -- Shadow quad
        5, 6, 7, 5, 7, 8
    }
    
    local mesh = love.graphics.newMesh(vertices, "triangles")
    mesh:setVertexMap(indices)
    return mesh
end

function love.draw()
    -- Dark background
    love.graphics.clear(0.3,0.3,0.3, 1)
    -- love.graphics.clear(0.5,0,0, 1)
    
    love.graphics.circle("fill", 100, 150, 30)
    love.graphics.circle("fill", 100, 500, 50)
    -- Define some objects
    local objects = {
        {x = 200, y = 200, w = 100, h = 80},
        {x = 450, y = 300, w = 80, h = 60},
        {x = 300, y = 400, w = 120, h = 40},
        {x = 150, y = 350, w = 60, h = 100}
    }
    
    -- PASS 1: Draw shadows using shadow shader
    love.graphics.setShader(shadowShader)
    -- love.graphics.setColor(1, 1, 1, 1)
    
    for _, obj in ipairs(objects) do
        local shadowMesh = createShadowMesh(obj.x, obj.y, obj.w, obj.h)
        love.graphics.draw(shadowMesh)
    end
    
    -- PASS 2: Draw objects with directional shader
    love.graphics.setShader()
    -- love.graphics.setColor(1, 1, 1, 0.8) -- Alpha affects the shader intensity
    
    for _, obj in ipairs(objects) do
        love.graphics.rectangle("fill", obj.x, obj.y, obj.w, obj.h)
    end
    
    -- Draw some circles with the directional shader
    love.graphics.circle("fill", 100, 100, 40)
    love.graphics.circle("fill", 600, 150, 30)
    love.graphics.circle("fill", 500, 500, 50)
    -- love.graphics.setBlendMode("screen","premultiplied")

    love.graphics.draw(a,100,100,0,1)
    -- love.graphics.setBlendMode("alpha")

    
    -- Reset shader
    love.graphics.setShader()
    
    -- Draw light source
    love.graphics.setColor(1, 1, 0, 0.8)
    love.graphics.circle("fill", lightPos[1], lightPos[2], 12)
    love.graphics.setColor(1, 1, 1, 0.2)
    love.graphics.circle("line", lightPos[1], lightPos[2], 40)
    
    -- Draw UI
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Combined Object & Shadow Shaders", 10, 10)
    love.graphics.print("Shadow Distance: " .. string.format("%.1f", shadowOffset), 10, 30)
    love.graphics.print("Light Position: " .. lightPos[1] .. ", " .. lightPos[2], 10, 50)
    love.graphics.print("", 10, 70)
    love.graphics.print("Controls:", 10, 90)
    love.graphics.print("  Mouse: Move light source", 10, 110)
    love.graphics.print("  +/-: Control shadow distance", 10, 130)
    love.graphics.print("", 10, 150)
    love.graphics.print("Objects show directional lighting", 10, 170)
    love.graphics.print("based on light position", 10, 190)
end

function love.keypressed(key)
    -- Remove viewangle reset since it's now light-based
end