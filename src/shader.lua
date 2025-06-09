shader = {}

shader.distance = 40
shader.sample = 32
shader.radiance = 0.2
shader.glowIntensity = 1.5
shader.colorVibrancy = 1.3
shader.ambientColor = {0.1, 0.1, 0.15}
shader.dynamicLights = {}
shader.maxLights = 16
shader.time = 0

function shader.load()
    scene_canvas = love.graphics.newCanvas(W, H, { format = "rgba8" })
    
    -- Enhanced canvases for dynamic lighting
    jfa_canvas1 = love.graphics.newCanvas(W, H, { format = "rg16f" })
    jfa_canvas2 = love.graphics.newCanvas(W, H, { format = "rg16f" })
    df_canvas = love.graphics.newCanvas(W, H, { format = "r16f" })
    
    -- Additional lighting canvases
    light_canvas = love.graphics.newCanvas(W, H, { format = "rgba16f" })
    composite_canvas = love.graphics.newCanvas(W, H, { format = "rgba8" })

    -- Load external shaders
    seed_shader = love.graphics.newShader("shaders_/seed.frag")
    jfa_shader = love.graphics.newShader("shaders_/jfa.frag")
    df_shader = love.graphics.newShader("shaders_/distance_field.frag")
    gi_shader = love.graphics.newShader("shaders_/global_illumination.frag")
    
    -- Initialize dynamic lights array
    shader.dynamicLights = {}
    shader.time = 0

end

function render(in_canvas, shader, target_canvas)
    
    love.graphics.setCanvas(target_canvas)
    love.graphics.clear(0, 0, 0, 0)
    -- love.graphics.clear(255,255,255,0.1,1,1)
    love.graphics.setShader(shader)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(in_canvas)
    
end

function shader.prepass()
    love.graphics.setCanvas(scene_canvas)
    love.graphics.clear(0, 0, 0, 0)
end

-- Add dynamic light (muzzle flash, bullet glow, explosion)
function shader.addLight(x, y, intensity, color, size, lifetime)
    if #shader.dynamicLights >= shader.maxLights then
        table.remove(shader.dynamicLights, 1) -- Remove oldest light
    end
    
    table.insert(shader.dynamicLights, {
        x = x,
        y = y,
        intensity = intensity or 1.0,
        color = color or {1.0, 1.0, 1.0},
        size = size or 50.0,
        lifetime = lifetime or 0.5,
        age = 0.0,
        type = "point"
    })
end

-- Add muzzle flash light with realistic parameters
function shader.addMuzzleFlash(x, y, dir)
    -- Bright, short-lived, hot white-orange flash
    shader.addLight(x, y, 3.2, {1.0, 0.9, 0.7}, 35, 0.08)
end

-- Add bullet glow with realistic tracer effect
function shader.addBulletGlow(x, y)
    -- Subtle, warm tracer glow
    shader.addLight(x, y, 0.6, {1.0, 0.8, 0.5}, 12, 0.04)
end

-- Add explosion light with realistic blast characteristics
function shader.addExplosion(x, y, size)
    -- Intense, hot, orange-white explosion with irregular shape
    shader.addLight(x, y, 5.5, {1.0, 0.7, 0.3}, (size or 80) * 1.2, 0.8)
end

-- Update dynamic lights
function shader.updateLights(dt)
    shader.time = shader.time + dt
    
    for i = #shader.dynamicLights, 1, -1 do
        local light = shader.dynamicLights[i]
        light.age = light.age + dt
        
        if light.age >= light.lifetime then
            table.remove(shader.dynamicLights, i)
        else
            -- Fade light over time
            local fade = 1.0 - (light.age / light.lifetime)
            light.currentIntensity = light.intensity * fade
        end
    end
end

local function render_pass(input_texture, shader, output_canvas)
    love.graphics.setCanvas({ canvas = output_canvas, clear = true })
    love.graphics.setShader(shader)
    love.graphics.draw(input_texture)
    love.graphics.setCanvas()
end


function shader.pass()
    gi_shader:send("maxDistance", shader.distance)
    gi_shader:send("sampleCount", shader.sample)
    gi_shader:send("time", shader.time)
    gi_shader:send("ambientColor", shader.ambientColor)
    gi_shader:send("glowIntensity", shader.glowIntensity)
    gi_shader:send("colorVibrancy", shader.colorVibrancy)
    
    -- Send dynamic lights efficiently
    local numLights = math.min(#shader.dynamicLights, shader.maxLights)
    gi_shader:send("numLights", numLights)
    
    -- Send lights individually to avoid array issues
    for i = 0, shader.maxLights - 1 do
        local light = shader.dynamicLights[i + 1]
        if light then
            local intensity = light.currentIntensity or light.intensity
            gi_shader:send("lights[" .. i .. "].pos", {light.x / W, light.y / H})
            gi_shader:send("lights[" .. i .. "].color", light.color)
            gi_shader:send("lights[" .. i .. "].intensity", intensity)
            gi_shader:send("lights[" .. i .. "].size", light.size / math.max(W, H))
        else
            gi_shader:send("lights[" .. i .. "].pos", {0.0, 0.0})
            gi_shader:send("lights[" .. i .. "].color", {0.0, 0.0, 0.0})
            gi_shader:send("lights[" .. i .. "].intensity", 0.0)
            gi_shader:send("lights[" .. i .. "].size", 0.0)
        end
    end

    
    render_pass(scene_canvas, seed_shader, jfa_canvas1)
    
    local passes = math.ceil(math.log(math.max(var.game_width, var.game_height), 2))
    for i = 1, passes do
        jfa_shader:send("stepSize", 2 ^ (passes - i))
        render_pass(jfa_canvas1, jfa_shader, jfa_canvas2)
        jfa_canvas1, jfa_canvas2 = jfa_canvas2, jfa_canvas1
    end
    
    df_shader:send("smoothness", 0.02)
    render_pass(jfa_canvas1, df_shader, df_canvas)
    
    love.graphics.setShader(gi_shader)
    gi_shader:send("surfaceTexture", scene_canvas)
    love.graphics.draw(df_canvas)
    love.graphics.setShader()
end

-- Update function to be called each frame
function shader.update(dt)
    shader.updateLights(dt)
end

-- Clear all dynamic lights
function shader.clearLights()
    shader.dynamicLights = {}
end

-- Get light count for debugging
function shader.getLightCount()
    return #shader.dynamicLights
end

return shader