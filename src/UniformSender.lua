-- UniformSender.lua - Robust shader uniform transmission for Love2D
local UniformSender = {}

-- Safe uniform sending with automatic type detection
function UniformSender.sendUniform(shader, name, value)
    if not shader:hasUniform(name) then
        return false -- Uniform doesn't exist
    end
    
    local valueType = type(value)
    
    if valueType == "number" then
        -- Single number (float/int)
        shader:send(name, value)
        
    elseif valueType == "table" then
        local len = #value
        
        if len == 0 then
            -- Empty table, skip
            return false
            
        elseif len == 1 then
            -- Single value table
            shader:send(name, value[1])
            
        elseif len == 2 then
            -- vec2
            shader:send(name, {value[1], value[2]})
            
        elseif len == 3 then
            -- vec3
            shader:send(name, {value[1], value[2], value[3]})
            
        elseif len == 4 then
            -- vec4
            shader:send(name, {value[1], value[2], value[3], value[4]})
            
        else
            -- Array - use unpack
            shader:send(name, unpack(value))
        end
        
    elseif valueType == "userdata" then
        -- Texture/Canvas
        shader:send(name, value)
        
    elseif valueType == "boolean" then
        -- Convert boolean to number
        shader:send(name, value and 1.0 or 0.0)
        
    else
        -- Unknown type, try direct send
        shader:send(name, value)
    end
    
    return true
end

-- Send multiple uniforms at once
function UniformSender.sendUniforms(shader, uniforms)
    for name, value in pairs(uniforms) do
        UniformSender.sendUniform(shader, name, value)
    end
end

-- Debug function to check uniform types
function UniformSender.debugUniform(name, value)
    local valueType = type(value)
    local info = string.format("Uniform '%s': type=%s", name, valueType)
    
    if valueType == "table" then
        info = info .. string.format(", length=%d, values=[", #value)
        for i = 1, math.min(#value, 4) do
            info = info .. tostring(value[i])
            if i < math.min(#value, 4) then info = info .. ", " end
        end
        if #value > 4 then info = info .. "..." end
        info = info .. "]"
    else
        info = info .. ", value=" .. tostring(value)
    end
    
    print(info)
end

return UniformSender