shader = {}

shader.distance = 30
shader.sample = 40

-- Quality scaling settings
shader.quality = {
    adaptive = true,  -- Enable adaptive quality
    base_distance = 30,  -- Base distance for sampling
    base_sample = 40,  -- Base sample count
    min_distance = 15,  -- Minimum distance
    max_distance = 60,  -- Maximum distance
    min_sample = 20,  -- Minimum sample count
    max_sample = 80,  -- Maximum sample count
    performance_scaling = true,  -- Scale with performance
    zoom_scaling = true  -- Scale with zoom level
}

-- Fog of war settings - reduced density for better visibility
shader.fog_of_war = {
    enabled = false,
    base_fade_distance = 140,  -- Increased for less dense fog
    space_color = {0.01, 0.01, 0.05},  -- Darker space for more contrast
    space_intensity = 0.25,  -- Reduced intensity for subtle background
    star_density = 0.008,  -- Reduced for smaller, more realistic stars
    min_fade_distance = 60,  -- Increased minimum for less aggressive fade
    max_fade_distance = 250  -- Increased maximum for gentler transition
}

function shader.load()
    -- Create canvases with specific formats
    scene_canvas = love.graphics.newCanvas(W, H, { format = "rgba8" })
    
    -- JFA needs two canvases for ping-pong, RG for UV
    jfa_canvas1 = love.graphics.newCanvas(W, H, { format = "rg16f" })
    jfa_canvas2 = love.graphics.newCanvas(W, H, { format = "rg16f" })
    
    -- Distance field canvas, R for distance
    df_canvas = love.graphics.newCanvas(W, H, { format = "r16f" })
    
    -- Additional canvases for effects
    bloom_canvas1 = love.graphics.newCanvas(W, H, { format = "rgba8" })
    bloom_canvas2 = love.graphics.newCanvas(W, H, { format = "rgba8" })
    final_canvas = love.graphics.newCanvas(W, H, { format = "rgba8" })
    gi_canvas = love.graphics.newCanvas(W, H, { format = "rgba8" })
    fog_canvas = love.graphics.newCanvas(W, H, { format = "rgba8" })
    
    -- Load shaders from external files
    seed_shader = love.graphics.newShader("shaders_/seed.frag")
    
    jfa_shader = love.graphics.newShader("shaders_/jfa.frag")
    
    df_shader = love.graphics.newShader("shaders_/distance_field.frag")
    
    gi_shader = love.graphics.newShader("shaders_/global_illumination.frag")
    
    bloom_extract = love.graphics.newShader("shaders_/bloom_extract.frag")
    
    blur_shader = love.graphics.newShader("shaders_/blur.frag")
    
    composite_shader = love.graphics.newShader("shaders_/composite.frag")
    
    fog_of_war_shader = love.graphics.newShader("shaders_/fog_of_war.frag")
    
    shader.pixel_shader = love.graphics.newShader("shaders_/pixel.frag")
    shader.pixel_enabled = false
    
    -- Set default uniforms for playable twilight atmosphere
    df_shader:send("smoothness", 0.05)
    gi_shader:send("ambientColor", {0.4, 0.4, 0.4}) -- Neutral gray ambient for visibility
    gi_shader:send("glowIntensity", 1.2) -- Reduced for subtlety
    gi_shader:send("colorVibrancy", 1.1)
    bloom_extract:send("threshold", 0.7) -- Higher threshold for selective bloom
    blur_shader:send("blurSize", 1.0)
    composite_shader:send("bloomStrength", 0.6) -- Subtle bloom for light sources
    composite_shader:send("giStrength", 0.5) -- Blend GI with original scene
    composite_shader:send("contrast", 1.1)
    composite_shader:send("saturation", 1.2)
    composite_shader:send("tintColor", {1.0, 1.0, 1.0}) -- Neutral tint for clarity
    
    -- Set fog of war uniforms (fade_distance will be set dynamically in pass())
    fog_of_war_shader:send("space_color", shader.fog_of_war.space_color)
    fog_of_war_shader:send("space_intensity", shader.fog_of_war.space_intensity)
    fog_of_war_shader:send("screen_size", {W, H})
end

function render(in_canvas, shader, target_canvas)
    love.graphics.setCanvas(target_canvas)
    love.graphics.clear(0, 0, 0, 0) -- Clear to transparent
    love.graphics.setShader(shader)
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(in_canvas)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
end

function shader.prepass()
    love.graphics.setCanvas(scene_canvas)
    love.graphics.clear(0, 0, 0, 0) -- Clear to transparent, not gray
end

function shader.postpass()
    -- This is where you should draw your scene to scene_canvas
    love.graphics.setCanvas(scene_canvas)
end

function shader.updateQuality()
    if not shader.quality.adaptive then
        shader.distance = shader.quality.base_distance
        shader.sample = shader.quality.base_sample
        return
    end
    
    local quality_factor = 1.0
    
    -- Performance scaling
    if shader.quality.performance_scaling and camera and camera.performance then
        quality_factor = quality_factor * camera.performance.performance_factor
    end
    
    -- Zoom scaling - higher zoom = need higher quality
    if shader.quality.zoom_scaling and camera then
        local zoom_factor = math.max(0.5, math.min(2.0, camera.zoom))
        quality_factor = quality_factor * zoom_factor
    end
    
    -- View radius scaling - larger view distance = can reduce quality slightly
    if camera and camera.view_radius then
        local radius_factor = math.max(0.8, math.min(1.2, 400 / camera.view_radius))
        quality_factor = quality_factor * radius_factor
    end
    
    -- Clamp quality factor to reasonable range
    quality_factor = math.max(0.5, math.min(2.0, quality_factor))
    
    -- Apply scaling to distance and sample count
    shader.distance = math.floor(shader.quality.base_distance * quality_factor)
    shader.sample = math.floor(shader.quality.base_sample * quality_factor)
    
    -- Clamp to min/max values
    shader.distance = math.max(shader.quality.min_distance, 
                              math.min(shader.quality.max_distance, shader.distance))
    shader.sample = math.max(shader.quality.min_sample, 
                            math.min(shader.quality.max_sample, shader.sample))
end

function shader.setPixelEnabled(on)
    shader.pixel_enabled = on
end

function shader.pass()
    -- Update adaptive quality based on performance and camera settings
    shader.updateQuality()
    
    -- Update time uniform
    local time = love.timer.getTime()
    gi_shader:send("time", time)
    
    -- Apply camera uniforms to shaders for consistent rendering
    camera.applyToShader(gi_shader)
    camera.applyToShader(composite_shader)
    
    -- Seed pass
    render(scene_canvas, seed_shader, jfa_canvas1)
    
    -- Send uniforms to GI shader
    gi_shader:send("surfaceTexture", scene_canvas)
    gi_shader:send("maxDistance", shader.distance)
    gi_shader:send("sampleCount", shader.sample)
    
    -- JFA passes
    local passes = math.ceil(math.log(math.max(W, H)) / math.log(2)) + 1
    
    for i = 1, passes do
        jfa_shader:send("stepSize", math.pow(2, passes - i))
        
        love.graphics.setCanvas(jfa_canvas2)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setShader(jfa_shader)
        love.graphics.draw(jfa_canvas1)
        
        -- Swap canvases
        jfa_canvas1, jfa_canvas2 = jfa_canvas2, jfa_canvas1
    end
    
    -- Distance field pass
    render(jfa_canvas1, df_shader, df_canvas)
    
    -- Global illumination pass
    render(df_canvas, gi_shader, gi_canvas)
    
    -- Bloom effect
    -- Extract bright pixels from scene
    render(scene_canvas, bloom_extract, bloom_canvas2)
    
    -- Horizontal blur
    blur_shader:send("direction", {1.0, 0.0})
    render(bloom_canvas2, blur_shader, bloom_canvas1)
    
    -- Vertical blur
    blur_shader:send("direction", {0.0, 1.0})
    render(bloom_canvas1, blur_shader, bloom_canvas2)
    
    -- Final composition
    composite_shader:send("bloomTexture", bloom_canvas2)
    composite_shader:send("giTexture", gi_canvas)
    render(scene_canvas, composite_shader, final_canvas)
    
    -- Apply fog of war effect if enabled
    if shader.fog_of_war.enabled then
        -- Calculate dynamic fade distance based on zoom and view radius
        local view_radius = camera.view_radius or camera.config.base_view_radius
        local zoom_factor = 1.0 / camera.zoom  -- Higher zoom = smaller fade distance
        local fade_distance = shader.fog_of_war.base_fade_distance * zoom_factor
        fade_distance = math.max(shader.fog_of_war.min_fade_distance, 
                                math.min(shader.fog_of_war.max_fade_distance, fade_distance))
        
        -- Update fog of war uniforms with current camera state
        fog_of_war_shader:send("camera_position", {camera.x, camera.y})
        fog_of_war_shader:send("camera_zoom", camera.zoom)
        fog_of_war_shader:send("view_radius", view_radius)
        fog_of_war_shader:send("fade_distance", fade_distance)
        fog_of_war_shader:send("time", time)
        
        -- Apply fog of war to final composition
        render(final_canvas, fog_of_war_shader, fog_canvas)
        
        -- Draw fog results
        love.graphics.setShader()
        love.graphics.setCanvas()
        love.graphics.setBlendMode("alpha", "premultiplied")
        love.graphics.setColor(1, 1, 1, 1)
        if shader.pixel_enabled then
            shader.pixel_shader:send("pixel_size", 8.0)
            shader.pixel_shader:send("screen_size", {W, H})
            love.graphics.setShader(shader.pixel_shader)
            love.graphics.draw(fog_canvas)
            love.graphics.setShader()
        else
            love.graphics.draw(fog_canvas)
        end
        love.graphics.setBlendMode("alpha")
    else
        -- Draw final results without fog
        love.graphics.setShader()
        love.graphics.setCanvas()
        love.graphics.setBlendMode("alpha", "premultiplied")
        love.graphics.setColor(1, 1, 1, 1)
        if shader.pixel_enabled then
            shader.pixel_shader:send("pixel_size", 8.0)
            shader.pixel_shader:send("screen_size", {W, H})
            love.graphics.setShader(shader.pixel_shader)
            love.graphics.draw(final_canvas)
            love.graphics.setShader()
        else
            love.graphics.draw(final_canvas)
        end
        love.graphics.setBlendMode("alpha")
    end
end

return shader
