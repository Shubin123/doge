shader = {}

shader.distance = 30
shader.sample = 40

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
    
    -- Return all visible surface as their UV coords
    seed_shader = love.graphics.newShader([[
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec4 pixel = Texel(tex, tc);
            // Add edge detection for sprite outlines
            float edgeThreshold = 0.3;
            if (pixel.a > edgeThreshold) {
                return vec4(tc, 0.0, 1.0);
            }
            return vec4(0.0);
        }
    ]])
    
    -- Enhanced JFA shader with better sampling
    jfa_shader = love.graphics.newShader([[
        uniform float stepSize;
        
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec2 offset = stepSize / vec2(love_ScreenSize.x, love_ScreenSize.y);
            vec2 bestPoint = vec2(-2.0);
            float bestDist = 1e9;
            
            // Enhanced 3x3 sampling with slight jitter for smoother results
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
    
    -- Enhanced distance field with smooth falloff
    df_shader = love.graphics.newShader([[
        uniform float smoothness;
        
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec2 nearestPoint = Texel(tex, tc).xy;
            float dist = length(tc - nearestPoint);
            
            // Apply smoothstep for nicer falloff
            dist = smoothstep(0.0, smoothness, dist);
            
            return vec4(dist, 0.0, 0.0, 1.0);
        }
    ]])
    
    -- Enhanced GI shader with modern arcade effects
    gi_shader = love.graphics.newShader([[
        uniform sampler2D surfaceTexture;
        uniform float maxDistance;
        uniform int sampleCount;
        uniform float time;
        uniform vec3 ambientColor;
        uniform float glowIntensity;
        uniform float colorVibrancy;
        
        const float PI = 3.14159265359;
        
        float rand(vec2 co) {
            return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
        }
        
        // Color enhancement function
        vec3 enhanceColor(vec3 color) {
            // Increase saturation for arcade feel
            float luminance = dot(color, vec3(0.299, 0.587, 0.114));
            vec3 saturated = mix(vec3(luminance), color, colorVibrancy);
            
            // Apply slight color grading
            saturated.r = pow(saturated.r, 0.95);
            saturated.g = pow(saturated.g, 1.0);
            saturated.b = pow(saturated.b, 1.05);
            
            return saturated;
        }
        
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            float oneOverRays = 1.0 / float(sampleCount);
            float tauOverRays = 2.0 * PI * oneOverRays;
            vec2 oneOverSize = vec2(1.0) / vec2(love_ScreenSize.x, love_ScreenSize.y);
            vec2 ratio = normalize(oneOverSize);
            float minStepSize = min(oneOverSize.x, oneOverSize.y) * 0.5;
            
            vec3 radiance = ambientColor * 0.15; // Arcade-style ambient lighting
            vec3 glowAccum = vec3(0.0);
            float noise = rand(tc + vec2(time * 0.01));
            
            // Get original pixel for glow calculation
            vec4 originalPixel = Texel(surfaceTexture, tc);
            
            for(int i = 0; i < sampleCount; i++) {
                float angle = (0.5 + float(i) + noise) * tauOverRays;
                vec2 rayDirection = vec2(cos(angle), sin(angle));
                vec2 sampleTC = tc;
                
                float totalDistance = 0.0;
                
                for (int step = 0; step < maxDistance; step += 1) {
                    float df = Texel(tex, sampleTC).r;
                    sampleTC += rayDirection * df * ratio;
                    totalDistance += df;
                    
                    if(sampleTC.x < 0.0 || sampleTC.x > 1.0 ||
                       sampleTC.y < 0.0 || sampleTC.y > 1.0) break;
                    
                    if (df <= minStepSize) {
                        vec3 hitColor = Texel(surfaceTexture, sampleTC).rgb;
                        hitColor = pow(hitColor, vec3(2.2)); // From sRGB
                        
                        // Distance-based falloff with glow
                        float falloff = 1.0 - smoothstep(0.0, maxDistance * 0.8, totalDistance);
                        falloff = pow(falloff, 0.8); // Softer falloff for arcade feel
                        
                        // Add color bleeding for vibrant arcade look
                        vec3 enhancedColor = enhanceColor(hitColor);
                        radiance += enhancedColor * falloff;
                        
                        // Accumulate glow from bright objects
                        float brightness = dot(hitColor, vec3(0.299, 0.587, 0.114));
                        if (brightness > 0.5) {
                            glowAccum += hitColor * falloff * glowIntensity;
                        }
                        
                        break;
                    }
                }
            }
            
            // Average and apply enhancements
            vec3 finalColor = radiance * oneOverRays;
            finalColor += glowAccum * oneOverRays * 0.5; // Add glow contribution
            
            // Apply tone mapping for arcade style
            finalColor = finalColor / (finalColor + vec3(1.0));
            finalColor = pow(finalColor, vec3(1.0 / 2.2)); // To sRGB
            
            // Mix with original for sprites
            if (originalPixel.a > 0.5) {
                finalColor = mix(finalColor, enhanceColor(originalPixel.rgb), 0.3);
            }
            
            return vec4(finalColor, 1.0);
        }
    ]])
    
    -- Bloom extraction shader
    bloom_extract = love.graphics.newShader([[
        uniform float threshold;
        
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec4 pixel = Texel(tex, tc);
            float brightness = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
            
            if (brightness > threshold) {
                return vec4(pixel.rgb * (brightness - threshold), pixel.a);
            }
            return vec4(0.0, 0.0, 0.0, 0.0);
        }
    ]])
    
    -- Gaussian blur shader for bloom
    blur_shader = love.graphics.newShader([[
        uniform vec2 direction;
        uniform float blurSize;
        
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec2 onePixel = vec2(1.0) / vec2(love_ScreenSize.x, love_ScreenSize.y);
            vec4 result = vec4(0.0);
            float total = 0.0;
            
            // 9-tap Gaussian blur
            float weights[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);
            
            result += Texel(tex, tc) * weights[0];
            total += weights[0];
            
            for (int i = 1; i < 5; i++) {
                vec2 offset = onePixel * direction * float(i) * blurSize;
                result += Texel(tex, tc + offset) * weights[i];
                result += Texel(tex, tc - offset) * weights[i];
                total += weights[i] * 2.0;
            }
            
            return result / total;
        }
    ]])
    
    -- Final composition shader
    composite_shader = love.graphics.newShader([[
        uniform sampler2D bloomTexture;
        uniform float bloomStrength;
        uniform float contrast;
        uniform float saturation;
        uniform vec3 tintColor;
        
        vec3 adjustContrast(vec3 color, float contrast) {
            return (color - 0.5) * contrast + 0.5;
        }
        
        vec3 adjustSaturation(vec3 color, float saturation) {
            float gray = dot(color, vec3(0.299, 0.587, 0.114));
            return mix(vec3(gray), color, saturation);
        }
        
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec4 base = Texel(tex, tc);
            vec4 bloom = Texel(bloomTexture, tc);
            
            // Combine base and bloom
            vec3 result = base.rgb + bloom.rgb * bloomStrength;
            
            // Apply post-processing
            result = adjustContrast(result, contrast);
            result = adjustSaturation(result, saturation);
            
            // Apply subtle color tint
            result = mix(result, result * tintColor, 0.1);
            
            // Vignette effect
            float vignette = 1.0 - length(tc - vec2(0.5)) * 0.5;
            vignette = smoothstep(0.3, 1.0, vignette);
            result *= vignette;
            
            return vec4(result, base.a);
        }
    ]])
    
    -- Set default uniforms
    df_shader:send("smoothness", 0.05)
    gi_shader:send("ambientColor", {0.15, 0.1, 0.2}) -- Purple-ish ambient
    gi_shader:send("glowIntensity", 1.5)
    gi_shader:send("colorVibrancy", 1.4)
    bloom_extract:send("threshold", 0.6)
    blur_shader:send("blurSize", 1.5)
    composite_shader:send("bloomStrength", 0.8)
    composite_shader:send("contrast", 1.1)
    composite_shader:send("saturation", 1.3)
    composite_shader:send("tintColor", {1.0, 0.98, 0.95}) -- Slight warm tint
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
    -- Update time uniform
    local time = love.timer.getTime()
    gi_shader:send("time", time)
    
    -- Seed pass
    render(scene_canvas, seed_shader, jfa_canvas1)
    
    -- Send uniforms to GI shader
    gi_shader:send("surfaceTexture", scene_canvas)
    gi_shader:send("maxDistance", shader.distance)
    gi_shader:send("sampleCount", shader.sample)
    
    -- JFA passes
    local passes = math.ceil(math.log(math.max(var.game_width, var.game_height), 2)) + 1
    
    for i = 1, passes do
        jfa_shader:send("stepSize", math.pow(2, passes - i))
        
        love.graphics.setCanvas(jfa_canvas2)
        love.graphics.setShader(jfa_shader)
        love.graphics.draw(jfa_canvas1)
        
        -- Swap canvases
        jfa_canvas1, jfa_canvas2 = jfa_canvas2, jfa_canvas1
    end
    
    -- Distance field pass
    render(jfa_canvas1, df_shader, df_canvas)
    
    -- Global illumination pass
    render(df_canvas, gi_shader, bloom_canvas1)
    
    -- Bloom effect
    -- Extract bright pixels
    render(bloom_canvas1, bloom_extract, bloom_canvas2)
    
    -- Horizontal blur
    blur_shader:send("direction", {1.0, 0.0})
    render(bloom_canvas2, blur_shader, bloom_canvas1)
    
    -- Vertical blur
    blur_shader:send("direction", {0.0, 1.0})
    render(bloom_canvas1, blur_shader, bloom_canvas2)
    
    -- Final composition
    composite_shader:send("bloomTexture", bloom_canvas2)
    render(bloom_canvas1, composite_shader, final_canvas)
    
    -- Draw final results
    love.graphics.setShader()
    love.graphics.setCanvas()
    love.graphics.draw(final_canvas)
    
    -- Draw original sprites on top with slight transparency for integration
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.draw(scene_canvas)
    love.graphics.setColor(1, 1, 1, 1)
end

return shader