shader = {}

shader.radiance = 0

-- Global-illumination quality presets. One knob controls all three costs:
--   rays        : directions marched per pixel  (angular quality)
--   steps       : ray-march iterations per ray  (light reach)
--   pixelBudget : target GI-buffer area; lower -> GI runs at a smaller canvas
-- "high" reproduces the original look; "medium"/"low" trade fidelity for FPS.
shader.qualityPresets = {
    high   = { rays = 30, steps = 8, pixelBudget = 500000 },
    medium = { rays = 24, steps = 6, pixelBudget = 360000 },
    low    = { rays = 16, steps = 5, pixelBudget = 240000 },
}

function shader.getQuality()
    return shader.qualityPresets[var.gi_quality or "high"] or shader.qualityPresets.high
end

function shader.load()
    -- Calculate GI resolution based on performance target
    -- Scale down GI resolution for larger screens to maintain performance
    local quality = shader.getQuality()
    local pixel_count = W * H
    local gi_scale = math.min(1.0, math.sqrt(quality.pixelBudget / pixel_count)) -- GI runs at this fraction of screen res
    
    -- GI resolution (lower for performance)
    local gi_w = math.max(128, math.floor(W * gi_scale))
    local gi_h = math.max(128, math.floor(H * gi_scale))
    
    -- Create canvases with specific formats
    scene_canvas = love.graphics.newCanvas(W, H, {format  = "rgba4"}) -- rgba8

    -- JFA needs two canvases for ping-pong, RG for UV (at GI resolution)
    jfa_canvas1 = love.graphics.newCanvas(gi_w, gi_h, {format  = "rgba16f"}) --rg16f 
    jfa_canvas2 = love.graphics.newCanvas(gi_w, gi_h,  {format  = "rgba16f"})

    -- Distance field canvas, R for distance (at GI resolution)
    df_canvas = love.graphics.newCanvas(gi_w, gi_h) -- r16f
    
    -- GI result canvas (at GI resolution)
    gi_canvas = love.graphics.newCanvas(gi_w, gi_h)
    
    -- Store scales for later use
    shader.gi_scale = gi_scale
    shader.gi_w = gi_w
    shader.gi_h = gi_h

    -- Return all visible surface as their UV coords
    seed_shader = love.graphics.newShader([[
        //#pragma language glsl3
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            return Texel(tex, tc).a > 0.5 ? vec4(tc, 0.0, 1.0) : vec4(0.0);
        }
    ]])

    -- Run jump flood, which sets each pixel to be the UV which is the UV of the nearest surface
    jfa_shader = love.graphics.newShader([[
        //#pragma language glsl3
        uniform float stepSize;
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec2 offset = stepSize / vec2(love_ScreenSize.x, love_ScreenSize.y);
            vec2 bestPoint = vec2(-2.0);
            float bestDist = 1e9;
            for(float y = -1.0; y <= 1.0; y += 1.0) {
                for(float x = -1.0; x <= 1.0; x += 1.0) {
                    vec2 sampleTC = tc + vec2(x, y) * offset;
                    if(sampleTC.x < 0.0 || sampleTC.x > 1.0 ||
                       sampleTC.y < 0.0 || sampleTC.y > 1.0) continue;
                    vec2 data = Texel(tex, sampleTC).xy;
                    if(data.x > 0.0 || data.y > 0.0) {
                        float dist = length(tc - data);
                        if(dist < bestDist) {
                            bestDist = dist;
                            bestPoint = data;
                        }
                    }
                }
            }
            return vec4(bestPoint, 0.0, 1.0);
        }
    ]])

    -- Calculate the distance from every coordinate to every minimum distance jump
    df_shader = love.graphics.newShader([[
       //#pragma language glsl3
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            float dist = length(tc - Texel(tex, tc).xy);
            return vec4(dist, 0.0, 0.0, 1.0);
        }
    ]])

    -- Optimized GI shader - same as original but will run at lower resolution.
    -- Ray/step counts are injected as compile-time constants (GLSL ES needs
    -- constant loop bounds for web builds), driven by the quality preset.
    local gi_src = [[
    //#pragma language glsl3
    
    #if defined(VERTEX) || __VERSION__ > 100 || defined(GL_FRAGMENT_PRECISION_HIGH)
        #define MY_HIGHP_OR_MEDIUMP highp
    #else
        #define MY_HIGHP_OR_MEDIUMP mediump
    #endif
    
    uniform sampler2D surfaceTexture;
    const MY_HIGHP_OR_MEDIUMP number PI = 3.14159265359;
    
    extern MY_HIGHP_OR_MEDIUMP number baseRadiance;
    
    
    MY_HIGHP_OR_MEDIUMP number rand(vec2 co) {
      return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
    }
    
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        // Rays reach slightly further toward screen edges to mask the lower
        // effective resolution there (see stepMultiplier below).
        MY_HIGHP_OR_MEDIUMP number distFromCenter = distance(tc, vec2(0.5));

        MY_HIGHP_OR_MEDIUMP number oneOverRays = 1.0 / __RAYS__;
        MY_HIGHP_OR_MEDIUMP number tauOverRays = 2.0 * PI * oneOverRays;
        vec2 oneOverSize = vec2(1.0) / vec2(love_ScreenSize.x, love_ScreenSize.y);
        vec2 ratio = normalize(oneOverSize);
        MY_HIGHP_OR_MEDIUMP number minStepSize = min(oneOverSize.x, oneOverSize.y) * 0.1;
        vec3 radiance = vec3(baseRadiance);
        MY_HIGHP_OR_MEDIUMP number noise = rand(tc);
        
        MY_HIGHP_OR_MEDIUMP number stepMultiplier = 1.0 + distFromCenter * 0.3;
        
        for(MY_HIGHP_OR_MEDIUMP number i = 0.0; i < __RAYS__; i += 1.0) {
            MY_HIGHP_OR_MEDIUMP number angle = (0.5 + i + noise) * tauOverRays;
            vec2 rayDirection = vec2(cos(angle), sin(angle));
            vec2 sampleTC = tc;
            
            for (MY_HIGHP_OR_MEDIUMP number step = 0.0; step < __STEPS__; step += 1.0) {
              MY_HIGHP_OR_MEDIUMP number df = Texel(tex, sampleTC).r;
              sampleTC += rayDirection * df * ratio * stepMultiplier;
              
              if (df <= minStepSize) {
                radiance.rgb += pow(Texel(surfaceTexture, sampleTC).rgb, vec3(2.2));
                break;
              }
            }
        }
        return vec4(pow(radiance * oneOverRays, vec3(1.0 / 2.2)), 1.0);
    }
]]
    gi_src = gi_src:gsub("__RAYS__", string.format("%d.0", quality.rays))
    gi_src = gi_src:gsub("__STEPS__", string.format("%d.0", quality.steps))
    gi_shader = love.graphics.newShader(gi_src)

    -- Upscale shader for final composite
    upscale_shader = love.graphics.newShader([[
        //#pragma language glsl3
        uniform sampler2D giTexture;
        
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            // Upscale the low-res GI buffer (hardware bilinear) and add it on top
            // of the full-res scene as an additive indirect-light term.
            vec4 gi    = Texel(giTexture, tc);
            vec4 scene = Texel(tex, tc);
            return scene + gi;
        }
    ]])
end

function render(in_canvas, shader, target_canvas)
    love.graphics.setCanvas(target_canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setShader(shader)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(in_canvas)
end

function shader.prepass()
    love.graphics.setCanvas(scene_canvas)
    love.graphics.clear(0, 0, 0, 0)
end

function shader.pass()
    -- Downscale scene for GI processing
    love.graphics.setCanvas(jfa_canvas1)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setShader(seed_shader)
    love.graphics.draw(scene_canvas, 0, 0, 0, shader.gi_scale, shader.gi_scale)
    
    gi_shader:send("surfaceTexture", scene_canvas)
    gi_shader:send("baseRadiance", shader.radiance)
    
    -- JFA passes at GI resolution.
    -- Jump Flood needs exactly ceil(log2(maxDim)) halving passes to fully
    -- propagate. The old "+ 20" ran ~20 extra fullscreen passes whose stepSize
    -- was bigger than the whole canvas, so every neighbour sample landed
    -- off-canvas and overwrote the seeded UVs -- wasting GPU time *and*
    -- corrupting the distance field. One extra "JFA+1" pass is kept for edge
    -- accuracy at negligible cost.
    local passes = math.ceil(math.log(math.max(shader.gi_w, shader.gi_h), 2)) + 1
    
    for i = 1, passes do
        jfa_shader:send("stepSize", math.pow(2, passes - i))
        
        love.graphics.setCanvas(jfa_canvas2)
        love.graphics.setShader(jfa_shader)
        love.graphics.draw(jfa_canvas1)
        
        jfa_canvas1, jfa_canvas2 = jfa_canvas2, jfa_canvas1
    end
    
    -- Distance field pass at GI resolution
    render(jfa_canvas1, df_shader, df_canvas)
    
    -- Global illumination pass at GI resolution
    render(df_canvas, gi_shader, gi_canvas)
    
    -- Final composite: upscale GI and blend with scene
    love.graphics.setCanvas()
    love.graphics.setShader(upscale_shader)
    upscale_shader:send("giTexture", gi_canvas)
    love.graphics.draw(scene_canvas)
    


    love.graphics.setShader()
end

return shader