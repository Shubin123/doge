-- the intensity of a indivual light CAN be negative (weird) but no light can have negative range else all other direct lights break!!!
local shadow = {}
local lights = {}
MAX_LIGHTS = 50
function shadow.addLight(x, y, intensity, range)
    if #lights >= MAX_LIGHTS then
        return false
    end
    
    table.insert(lights, {
        x = x or 0,
        y = y or 0,
        intensity = intensity or 1.0,
        range = range or 200
    })
    return true
end

function shadow.removeLight(index)
    if index > 0 and index <= #lights then
        table.remove(lights, index)
    end
end

function shadow.updateLight(index, x, y, intensity, range)
    if index > 0 and index <= #lights then
        local light = lights[index]
        light.x = x or light.x
        light.y = y or light.y
        light.intensity = intensity or light.intensity
        light.range = range or light.range
    end
end

function shadow.clearLights()
    lights = {}
end

-- function shadow.update(dt)
--     -- Update first light to follow mouse
--     if #lights > 0 then
--         lights[1].x = love.mouse.getX()
--         lights[1].y = love.mouse.getY()

--         -- lights[2].x = player.body:getX()
--         -- lights[2].y = player.body:getY()
--     end
    
--     -- Send data to shader
--     objectShader:send("numLights", #lights)
    
--     if #lights > 0 then
--         local positions = {}
--         local intensities = {}
--         local ranges = {}
        
--         for i, light in ipairs(lights) do
--             -- positions[i] = {light.x + camera.x, light.y + camera.y}
--             positions[i] = {light.x , light.y}

--             intensities[i] = light.intensity
--             ranges[i] = light.range
--         end
        
--         objectShader:send("lightPositions", unpack(positions))
--         objectShader:send("lightIntensities", unpack(intensities))
--         objectShader:send("lightRanges", unpack(ranges))
--     end
-- end



local objectShader
local objectShaderWithCamera

function shadow.load()
    -- Create the same shader code twice
    local shaderCode = [[
        #define MAX_LIGHTS 50
        uniform int numLights;
        uniform vec2 lightPositions[MAX_LIGHTS];
        uniform float lightIntensities[MAX_LIGHTS];
        uniform float lightRanges[MAX_LIGHTS];
        
        varying vec2 pos;
        
        #ifdef VERTEX
        vec4 position(mat4 transform_projection, vec4 vertex_position) {
            pos = vertex_position.xy;
            return transform_projection * vertex_position;
        }
        #endif
        
        #ifdef PIXEL
        vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
            vec4 texColor = Texel(texture, texture_coords);
            float totalLight = 0.0;
            
            for (int i = 0; i < numLights && i < MAX_LIGHTS; i++) {
                float distance = length(lightPositions[i] - pos);
                float attenuation = 1.0 - clamp(distance / lightRanges[i], 0.0, 1.0);
                totalLight += attenuation * lightIntensities[i];
            }
            
            totalLight = clamp(totalLight, 0.0, 1.0);
            vec3 finalColor = mix(vec3(0.0), texColor.rgb, totalLight);
            
            return vec4(finalColor * color.rgb, texColor.a * color.a);
        }
        #endif
    ]]
    
    objectShader = love.graphics.newShader(shaderCode)
    objectShaderWithCamera = love.graphics.newShader(shaderCode)
    
    -- Initialize lights
    shadow.addLight(love.mouse.getX(), love.mouse.getY(), 1.0, 200)
    shadow.addLight(100, 200, 1.0, 50)
    
    for i=1,10 do
    for j=1,10 do

    --     -- print("wow")
    -- shadow.addLight(math.random(150,300), math.random(100,300),  1, math.random(10,50))
    shadow.addLight(100*i, 200*j, 1.0, 500)
    
    end
    end
end

function shadow.updateBothShaders(dt)
    -- Update mouse light
    if #lights > 0 then
        lights[1].x = love.mouse.getX()
        lights[1].y = love.mouse.getY()
        lights[2].x = math.sin(fire.t)*100
        lights[2].range = (math.cos(fire.t) + 1)*100
        for i=3,#lights do
        lights[i].range = (math.cos(fire.t/i) + 1)*100
        end
    end
    
    if #lights > 0 then
        local positions = {}
        local positionsWithCamera = {}
        local intensities = {}
        local ranges = {}
        
        for i, light in ipairs(lights) do
            positions[i] = {light.x, light.y}
            positionsWithCamera[i] = {light.x*camera.zoom + camera.x, light.y*camera.zoom + camera.y}
            intensities[i] = light.intensity
            ranges[i] = light.range
        end
        
        -- Update first shader (without camera)
        objectShader:send("numLights", #lights)
        objectShader:send("lightPositions", unpack(positions))
        objectShader:send("lightIntensities", unpack(intensities))
        objectShader:send("lightRanges", unpack(ranges))
        
        -- Update second shader (with camera)
        objectShaderWithCamera:send("numLights", #lights)
        objectShaderWithCamera:send("lightPositions", unpack(positionsWithCamera))
        objectShaderWithCamera:send("lightIntensities", unpack(intensities))
        objectShaderWithCamera:send("lightRanges", unpack(ranges))
    end
end

function shadow.getShader(useCamera)
    return useCamera and objectShaderWithCamera or objectShader
end

return shadow