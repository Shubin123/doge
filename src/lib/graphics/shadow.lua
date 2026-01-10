-- the intensity of a indivual light CAN be negative (weird) but no light can have negative range else all other direct lights break!!!
local shadow = {}
local lights = {}
MAX_LIGHTS = 1000
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

local objectShader
local objectShaderWithCamera

function shadow.load()
    -- Create the same shader code twice
    local shaderCode = [[
        #define MAX_LIGHTS 350
        uniform int numLights;
        //uniform vec2 lightPositions[MAX_LIGHTS];
        //uniform float lightIntensities[MAX_LIGHTS];
        //uniform float lightRanges[MAX_LIGHTS];
        uniform vec4 lights[MAX_LIGHTS]; //posx[0],posy[1],intensity[2],range[3]
        varying vec2 pos;

        #ifdef VERTEX
        attribute vec2 InstancePosition;
        vec4 position(mat4 transform_projection, vec4 vertex_position) {
            //pos = vertex_position.xy;
            //return transform_projection * vertex_position;
            vec4 instancedPosition = vertex_position + vec4(InstancePosition.xy, 0.0, 0.0);
            pos = instancedPosition.xy;
            return transform_projection * instancedPosition;
        }
        #endif

        #ifdef PIXEL
        vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
            vec4 texColor = Texel(texture, texture_coords);
            float totalLight = 0.0;

            for (int i = 0; i < MAX_LIGHTS; i++) {
                if (i == numLights) { //cmp uniform this way
                break;
                }


                float distance = length(vec2(lights[i][0],lights[i][1]) - pos);
                if (distance > lights[i][3]) continue; // skip if out of range

                float attenuation = 1.0 - clamp(distance / lights[i][3], 0.0, 1.0);
                totalLight += attenuation * lights[i][2];
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
    shadow.addLight(player.body:getX(), player.body:getY(), 1.0, 300)

    for i = 1, 100 do
        for j = 1, 10 do
            --     -- print("wow")
            -- shadow.addLight(math.random(150,300), math.random(100,300),  1, math.random(10,50))
            shadow.addLight(100 * i, 200 * j, 1.0, 500)
        end
    end
end

function shadow.updateBothShaders(dt)
    -- Update mouse light
    if #lights > 0 then
        -- lights[1].x = love.mouse.getX()
        -- lights[1].y = love.mouse.getY()
        lights[2].x = math.sin(fire.t) * 100
        lights[2].range = (math.cos(fire.t) + 1) * 100
        lights[3].x, lights[3].y = player.body:getX() + gun.currentVel.x*100, player.body:getY() + gun.currentVel.y*100

        
        -- local positions = {}
        -- local positionsWithCamera = {}
        -- local intensities = {}
        -- local ranges = {}
        local lightData = {}
        local lightDataCam = {}
        local numLights = 1
        for i, light in ipairs(lights) do
            -- positions[i] = {light.x, light.y}
            -- positionsWithCamera[i] = {light.x*camera.zoom + camera.x, light.y*camera.zoom + camera.y}
            -- intensities[i] = light.intensity
            -- ranges[i] = light.range
            if 4 < i and i < 500 then
                light.x = light.x + math.sin(fire.t + i)
                light.y = light.y + math.cos(fire.t + i)
                -- light.intensity = light.intensity + math.abs(math.sin(fire.t + i))
                light.range = (math.cos(fire.t + i) + 1) * 100
            end

            if 500 < i then
                -- print(bullet.instances[math.abs(501 - i)])
                   if bullet.instances[math.abs(501 - i)] then
                    local x, y = bullet.instances[math.abs(501 - i)].body:getPosition()
                    -- print(x,y)
                    light.x = x
                    light.y = y
                   end
            end

            local halfW = var.screen_width / 2 + 100
            local halfH = var.screen_height / 2 + 100
            local playerX,playerY = player.body:getPosition()
            
            -- If camera.x/y is center:
            if not (
                    light.x + light.range < playerX - halfW or
                    light.x - light.range > playerX + halfW or
                    light.y + light.range < playerY - halfH or
                    light.y - light.range > playerY + halfH)
            then
                light.intensity = var.indoors and 0 or 1
                lightData[numLights] = { light.x, light.y,light.intensity, light.range } 
                lightDataCam[numLights] = { light.x * camera.zoom + camera.x, light.y * camera.zoom + camera.y, light.intensity, light.range }
                numLights = numLights + 1
            else
                -- print("excluding light",i)
            end
        end


        -- Update first shader (without camera)

        -- if #lightData > 0 then
            objectShader:send("numLights", numLights)
            objectShader:send("lights", unpack(lightData))

            -- objectShader:send("lightPositions", unpack(positions))
            -- objectShader:send("lightIntensities", unpack(intensities))
            -- objectShader:send("lightRanges", unpack(ranges))

            -- Update second shader (with camera)
            objectShaderWithCamera:send("numLights", numLights)
            objectShaderWithCamera:send("lights", unpack(lightDataCam))
            -- objectShaderWithCamera:send("lightIntensities", unpack(intensities))
            -- objectShaderWithCamera:send("lightRanges", unpack(ranges))

            -- characterAnimator (takes into account instanced vertex positions)
            characterAnimator.shader:send("numLights", numLights)
            characterAnimator.shader:send("lights", unpack(lightData))
            -- characterAnimator.shader:send("lightIntensities",unpack(intensities))
            -- characterAnimator.shader:send("lightRanges",unpack(ranges))
        -- end
    end

    
end

function shadow.getShader(useCamera)
    return useCamera and objectShaderWithCamera or objectShader
end

return shadow
