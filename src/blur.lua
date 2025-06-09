local blur = {}

function blur.load()
    blur.SHADERS = {}
    blur.current_time = 0
    
    -- Load shaders from directory if they exist
    local shader_files = love.filesystem.getDirectoryItems("resources/shaders")
    for k, filename in ipairs(shader_files) do
        local extension = string.sub(filename, -3)
        if extension == '.fs' then
            local shader_name = string.sub(filename, 1, -4)
            blur.SHADERS[shader_name] = love.graphics.newShader("resources/shaders/"..filename)
        end
    end
    
    -- Built-in efficient blur shader
    blur.SHADERS["blur"] = love.graphics.newShader([[
    
    #if defined(VERTEX) || __VERSION__ > 100 || defined(GL_FRAGMENT_PRECISION_HIGH)
        #define MY_HIGHP_OR_MEDIUMP highp
    #else
        #define MY_HIGHP_OR_MEDIUMP mediump
    #endif

    extern MY_HIGHP_OR_MEDIUMP number blur_radius;
    extern MY_HIGHP_OR_MEDIUMP vec2 blur_direction;

    vec4 effect(vec4 colour, Image texture, vec2 texture_coords, vec2 screen_coords)
    {
        MY_HIGHP_OR_MEDIUMP vec2 tex_offset = blur_radius / love_ScreenSize.xy;
        MY_HIGHP_OR_MEDIUMP vec4 result = vec4(0.0);
        
        // Simple 9-tap gaussian blur kernel
        // Center weight
        result += Texel(texture, texture_coords) * 0.227027;
        
        // First ring (4 samples)
        result += Texel(texture, texture_coords + (blur_direction * tex_offset * 1.3846153846)) * 0.3162162162;
        result += Texel(texture, texture_coords - (blur_direction * tex_offset * 1.3846153846)) * 0.3162162162;
        
        // Second ring (4 samples)  
        result += Texel(texture, texture_coords + (blur_direction * tex_offset * 3.2307692308)) * 0.0702702703;
        result += Texel(texture, texture_coords - (blur_direction * tex_offset * 3.2307692308)) * 0.0702702703;
        
        return result * colour;
    }
    
    ]])
    
    -- Alternative simple box blur for even better performance
    blur.SHADERS["box_blur"] = love.graphics.newShader([[
    
    extern number blur_radius;
    
    vec4 effect(vec4 colour, Image texture, vec2 texture_coords, vec2 screen_coords)
    {
        vec2 tex_offset = blur_radius / love_ScreenSize.xy;
        vec4 result = vec4(0.0);
        
        // Simple 5-tap box blur
        result += Texel(texture, texture_coords);
        result += Texel(texture, texture_coords + vec2(tex_offset.x, 0.0));
        result += Texel(texture, texture_coords - vec2(tex_offset.x, 0.0));
        result += Texel(texture, texture_coords + vec2(0.0, tex_offset.y));
        result += Texel(texture, texture_coords - vec2(0.0, tex_offset.y));
        
        return (result / 5.0) * colour;
    }
    
    ]])
    
    -- Shader parameters
    blur.params = {
        blur_radius = 3.0,
        blur_direction = {1.0, 1.0}
    }
    
    -- Canvas for capturing scene before blur
    blur.scene_canvas = love.graphics.newCanvas(love.graphics.getWidth(), love.graphics.getHeight())
    blur.temp_canvas = love.graphics.newCanvas(love.graphics.getWidth(), love.graphics.getHeight())
    
    -- Blur state tracking
    blur.is_capturing = false
    blur.blur_enabled = false
end

function blur.update(dt)
    blur.current_time = blur.current_time + dt
    
    -- Optional: animate blur radius
    -- blur.params.blur_radius = 3.0 + math.sin(blur.current_time * 0.5) * 2.0
end

-- Call this to start capturing the scene for blur
function blur.begin_capture()
    -- we have one prepass that fills scene_canvas
    if not blur.blur_enabled then return end
    
    blur.is_capturing = true
    love.graphics.setCanvas(blur.scene_canvas)
    love.graphics.clear()
end

-- Call this to end capture and apply blur
function blur.end_capture()
    if not blur.is_capturing then return end
    
    love.graphics.setCanvas() -- Reset to screen
    blur.is_capturing = false
end

-- Call this in your draw pass (similar to how you call shader.pass())
function blur.pass()
    if not blur.blur_enabled then return end
    
    local shader = blur.SHADERS["box_blur"] or blur.SHADERS["blur"]
    if not shader then return end
    
    -- Apply blur to captured scene and draw to screen
    shader:send("blur_radius", blur.params.blur_radius)
    -- if blur.SHADERS["blur"] then
    --     shader:send("blur_direction", blur.params.blur_direction)
    -- end
    
    love.graphics.setShader(shader)
    love.graphics.draw(scene_canvas)
    love.graphics.setShader()
end

-- Two-pass blur for higher quality (call instead of blur.pass())
function blur.pass_two_pass()
    if not blur.blur_enabled then return end
    
    local shader = blur.SHADERS["blur"]
    if not shader then
        blur.pass() -- Fallback to single pass
        return
    end
    
    local old_canvas = love.graphics.getCanvas()
    
    -- First pass: horizontal blur
    -- love.graphics.setCanvas(blur.temp_canvas)
    love.graphics.clear()
    shader:send("blur_radius", blur.params.blur_radius)
    shader:send("blur_direction", {1.0, 0.0})
    love.graphics.setShader(shader)
    love.graphics.draw(scene_canvas)
    
    -- Second pass: vertical blur to screen
    love.graphics.setCanvas(old_canvas)
    shader:send("blur_direction", {0.0, 1.0})
    love.graphics.draw(scene_canvas)
    love.graphics.setShader()
end

-- Utility functions
function blur.enable()
    blur.blur_enabled = true
end

function blur.disable()
    blur.blur_enabled = false
end

function blur.toggle()
    blur.blur_enabled = not blur.blur_enabled
end

function blur.set_radius(radius)
    blur.params.blur_radius = math.max(0, radius)
end

function blur.get_radius()
    return blur.params.blur_radius
end

function blur.is_enabled()
    return blur.blur_enabled
end

return blur
