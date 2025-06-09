local UniformBuilder = {}

-- Build separate arrays for each light property to send to shader uniforms
function UniformBuilder.buildLightArrays(lightList, maxLights)
    -- Initialize six empty tables for each light property
    local posTable = {}
    local colorTable = {}
    local intensity = {}
    local size = {}
    local dirTable = {}
    local seed = {}
    
    -- Loop through maxLights, using actual lights or zero fallbacks
    for i = 1, maxLights do
        local light = lightList[i]
        
        if light then
            -- Use currentIntensity if available (for faded lights), otherwise use base intensity
            local lightIntensity = light.currentIntensity or light.intensity or 1.0
            
            -- Sanitize all light data with safe defaults
            local x = (type(light.x) == "number") and light.x or 0.0
            local y = (type(light.y) == "number") and light.y or 0.0
            
            local color = light.color or {1.0, 1.0, 1.0}
            if type(color) ~= "table" or #color < 3 then
                color = {1.0, 1.0, 1.0}
            end
            local r = (type(color[1]) == "number") and color[1] or 1.0
            local g = (type(color[2]) == "number") and color[2] or 1.0
            local b = (type(color[3]) == "number") and color[3] or 1.0
            
            local intensityValue = (type(lightIntensity) == "number") and lightIntensity or 1.0
            local lightSize = (type(light.size) == "number") and light.size or 50.0
            
            local dir = light.dir or {0.0, 1.0}
            if type(dir) ~= "table" or #dir < 2 then
                dir = {0.0, 1.0}
            end
            local dirX = (type(dir[1]) == "number") and dir[1] or 0.0
            local dirY = (type(dir[2]) == "number") and dir[2] or 1.0
            
            local lightSeed = (type(light.seed) == "number") and light.seed or math.random()
            
            -- Insert sanitized values
            posTable[#posTable + 1] = {x, y}
            colorTable[#colorTable + 1] = {r, g, b}
            table.insert(intensity, intensityValue)
            table.insert(size, lightSize)
            table.insert(seed, lightSeed)
            dirTable[#dirTable + 1] = {dirX, dirY}
        else
            -- Zero-value fallback for unused light slots
            -- Position as table {x, y}
            posTable[#posTable + 1] = {0, 0}
            
            -- Color as table {r, g, b}
            colorTable[#colorTable + 1] = {0, 0, 0}
            
            -- Scalar values
            table.insert(intensity, 0)
            table.insert(size, 0)
            table.insert(seed, 0)
            
            -- Direction as table {x, y}
            dirTable[#dirTable + 1] = {0, 0}
        end
    end
    
    -- Return all six arrays in order
    return posTable, colorTable, intensity, size, dirTable, seed
end

return UniformBuilder
