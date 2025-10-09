shader = {}

-- shader.distance = 0.1
-- shader.sample = 40
shader.radiance = 0

function shader.load()
    -- Calculate GI resolution based on performance target
    -- Scale down GI resolution for larger screens to maintain performance
    local pixel_count = W * H
    local gi_scale = math.min(1.0, math.sqrt(500000 / pixel_count)) -- Target ~1M pixels for GI *2mil to expensive 500k min otherwise too jittery
    
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

    -- Optimized GI shader - same as original but will run at lower resolution
    gi_shader = love.graphics.newShader([[
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
        // Adaptive sampling based on distance from center
        MY_HIGHP_OR_MEDIUMP number distFromCenter = distance(tc, vec2(0.5));
        MY_HIGHP_OR_MEDIUMP number sampleMultiplier = 1.0;
        sampleMultiplier = max(0.01, sampleMultiplier);
        
        MY_HIGHP_OR_MEDIUMP number oneOverRays = 1.0 / 30.0;
        MY_HIGHP_OR_MEDIUMP number tauOverRays = 2.0 * PI * oneOverRays;
        vec2 oneOverSize = vec2(1.0) / vec2(love_ScreenSize.x, love_ScreenSize.y);
        vec2 ratio = normalize(oneOverSize);
        MY_HIGHP_OR_MEDIUMP number minStepSize = min(oneOverSize.x, oneOverSize.y) * 0.1;
        vec3 radiance = vec3(baseRadiance);
        MY_HIGHP_OR_MEDIUMP number noise = rand(tc);
        
        MY_HIGHP_OR_MEDIUMP number stepMultiplier = 1.0 + distFromCenter * 0.3;
        
        for(MY_HIGHP_OR_MEDIUMP number i = 0.0; i < 30.0; i += 1.0) {
            MY_HIGHP_OR_MEDIUMP number angle = (0.5 + i + noise) * tauOverRays;
            vec2 rayDirection = vec2(cos(angle), sin(angle));
            vec2 sampleTC = tc;
            
            for (MY_HIGHP_OR_MEDIUMP number step = 0.0; step < 8.0; step += 1.0) {
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
]])

    -- Upscale shader for final composite
    upscale_shader = love.graphics.newShader([[
        //#pragma language glsl3
        uniform sampler2D giTexture;
        
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            // Bilinear upscaling with slight blur for smoother result
            vec2 texelSize = 1.0 / vec2(love_ScreenSize.x, love_ScreenSize.y);
            vec4 gi = Texel(giTexture, tc);
            
            // Blend scene with GI
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
    -- gi_shader:send("sampleCount", shader.sample)
    gi_shader:send("baseRadiance", shader.radiance)
    
    -- JFA passes at GI resolution
    local passes = math.ceil(math.log(math.max(shader.gi_w, shader.gi_h), 2))  + 20
    
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