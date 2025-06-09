local UniformBuilder = require("UniformBuilder")

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
shader.bulletLights = {}  -- separate tracking for bullet lights
shader.nextLightId = 1

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
function shader.addLight(x, y, intensity, color, size, lifetime, dir)
    if #shader.dynamicLights >= shader.maxLights then
        table.remove(shader.dynamicLights, 1) -- Remove oldest light
    end
    
    -- Ensure all parameters are valid
    local validDir = dir or {0.0, 1.0}
    if type(validDir) ~= "table" or #validDir < 2 then
        validDir = {0.0, 1.0}
    end
    if type(validDir[1]) ~= "number" then validDir[1] = 0.0 end
    if type(validDir[2]) ~= "number" then validDir[2] = 1.0 end
    
    local validColor = color or {1.0, 1.0, 1.0}
    if type(validColor) ~= "table" or #validColor < 3 then
        validColor = {1.0, 1.0, 1.0}
    end
    if type(validColor[1]) ~= "number" then validColor[1] = 1.0 end
    if type(validColor[2]) ~= "number" then validColor[2] = 1.0 end
    if type(validColor[3]) ~= "number" then validColor[3] = 1.0 end
    
    table.insert(shader.dynamicLights, {
        x = x or 0,
        y = y or 0,
        intensity = intensity or 1.0,
        color = validColor,
        size = size or 50.0,
        lifetime = lifetime or 0.5,
        age = 0.0,
        type = "point",
        dir = validDir,
        seed = math.random()
    })
end

-- Add muzzle flash light
function shader.addMuzzleFlash(x, y, dir)
    shader.addLight(x, y, 2.5, {1.0, 0.8, 0.4}, 40, 0.1, dir or {0.0, 1.0})
end

-- Create persistent bullet light that follows the bullet
function shader.createBulletLight(x, y)
    local lightId = shader.nextLightId
    shader.nextLightId = shader.nextLightId + 1
    
    local light = {
        id = lightId,
        x = x,
        y = y,
        intensity = 0.8,
        color = {1.0, 0.9, 0.7},
        size = 15,
        lifetime = 999,  -- very long lifetime
        age = 0.0,
        type = "bullet",
        dir = {0.0, 1.0},
        seed = math.random()
    }
    
    table.insert(shader.dynamicLights, light)
    shader.bulletLights[lightId] = light
    
    return lightId
end

-- Update bullet light position
function shader.updateBulletLight(lightId, x, y)
    local light = shader.bulletLights[lightId]
    if light then
        light.x = x
        light.y = y
        light.age = 0  -- keep it alive
    end
end

-- Remove bullet light
function shader.removeBulletLight(lightId)
    local light = shader.bulletLights[lightId]
    if light then
        -- Mark for removal from dynamic lights
        for i, dynLight in ipairs(shader.dynamicLights) do
            if dynLight.id == lightId then
                table.remove(shader.dynamicLights, i)
                break
            end
        end
        shader.bulletLights[lightId] = nil
    end
end

-- Add explosion light
function shader.addExplosion(x, y, size)
    shader.addLight(x, y, 4.0, {1.0, 0.6, 0.2}, size or 80, 1.0, {0.0, 1.0})
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
    -- Lua 5.1/5.2 compatibility for unpack
    local unpack = table.unpack or unpack
    
    -- Send basic uniforms with correct types
    gi_shader:send("maxDistance", shader.distance)
    gi_shader:send("sampleCount", shader.sample)
    gi_shader:send("time", shader.time)
    gi_shader:send("ambientColor", shader.ambientColor)  -- vec3 as table
    gi_shader:send("glowIntensity", shader.glowIntensity)
    gi_shader:send("colorVibrancy", shader.colorVibrancy)
    
    -- Build light arrays with new structured data
    local posTable, colorTable, intensityArr, sizeArr, dirTable, seedArr =
        UniformBuilder.buildLightArrays(shader.dynamicLights, shader.maxLights)

    -- Send light arrays properly for Love2D array uniforms
    if gi_shader:hasUniform("lightPos") and #posTable > 0 then
        gi_shader:send("lightPos", unpack(posTable))
    end
    if gi_shader:hasUniform("lightColor") and #colorTable > 0 then
        gi_shader:send("lightColor", unpack(colorTable))
    end
    if gi_shader:hasUniform("lightIntensity") and #intensityArr > 0 then
        gi_shader:send("lightIntensity", unpack(intensityArr))
    end
    if gi_shader:hasUniform("lightSize") and #sizeArr > 0 then
        gi_shader:send("lightSize", unpack(sizeArr))
    end
    if gi_shader:hasUniform("lightDir") and #dirTable > 0 then
        gi_shader:send("lightDir", unpack(dirTable))
    end
    if gi_shader:hasUniform("lightSeed") and #seedArr > 0 then
        gi_shader:send("lightSeed", unpack(seedArr))
    end
    
    gi_shader:send("numLights", math.min(#shader.dynamicLights, shader.maxLights))

    
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
