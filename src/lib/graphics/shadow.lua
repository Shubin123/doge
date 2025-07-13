shadow = {}
function shadow.load()
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
        float shadowIntensity = 1.0 - clamp(distance * 0.002, 0.0, 1.0); // Closer = brighter
        
        // Optional: Add directional component if you want directional lighting
        // shadowIntensity *= (dot(lightDir, vec2(0.0, -1.0)) * 0.5 + 0.5);
        
        // Apply shadow as a darkening effect (black/white gradient)
        vec3 shadowColor = mix(vec3(0), texColor.rgb, shadowIntensity);
        
        // Preserve the original alpha and blend with the input color
        return vec4(shadowColor * color.rgb, texColor.a * color.a);
    }
    #endif
]])

end
-- shadowOffset = 0
function shadow.update()
    -- local x,y  =  love.graphics.transformPoint(player.body:getPosition())
    -- x = camera.pos.x
    -- y =  camera.pos.x
    -- lightPos = {x,y}
    lightPos = {}
    lightPos[1] = love.mouse.getX()
    lightPos[2] = love.mouse.getY()
    
    -- Shadow distance control
    -- if love.keyboard.isDown("=") or love.keyboard.isDown("kp+") then
    --     shadowOffset = shadowOffset + dt * 30
    -- elseif love.keyboard.isDown("-") or love.keyboard.isDown("kp-") then
    --     shadowOffset = shadowOffset - dt * 30
    -- end
    -- shadowOffset = math.max(1, shadowOffset) -- Minimum shadow distance
    
    -- Send uniforms to shaders
    objectShader:send("lightPos", lightPos)
    -- shadowShader:send("midpoint", lightPos)
    -- shadowShader:send("offset", shadowOffset)
end

-- function shadow.

return shadow