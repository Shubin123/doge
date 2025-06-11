shader = {}

shader.distance = 10
shader.sample = 40
shader.radiance = 0

function shader.load()
    -- Create canvases with specific formats
    -- print("shader width", width)
    scene_canvas = love.graphics.newCanvas(W, H, { format = "rgba8" })

    -- JFA needs two canvases for ping-pong, RG for UV
    jfa_canvas1 = love.graphics.newCanvas(W, H, { format = "rg16f" })
    jfa_canvas2 = love.graphics.newCanvas(W, H, { format = "rg16f" })

    -- Distance field canvas, R for distance
    df_canvas = love.graphics.newCanvas(W, H, { format = "r16f" })

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

    -- Ray march!
    gi_shader = love.graphics.newShader([[
        //#pragma language glsl3
        uniform sampler2D surfaceTexture;
        const float PI = 3.14159265359;
        //const int NUM_SAMPLES = 16;
        //const int NUM_SAMPLES = 64;
        //const float MAX_DISTANCE = 40; // Should break out of the loop way before this
         uniform float maxDistance;
        uniform int sampleCount;
        uniform float baseRadiance;
        //const float MAX_DISTANCE = 80; // Should break out of the loop way before this
        float rand(vec2 co) {
          return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
        }
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            float oneOverRays = 1.0 / float(sampleCount);
            float tauOverRays = 2.0 * PI * oneOverRays;
            vec2 oneOverSize = vec2(1.0) / vec2(love_ScreenSize.x, love_ScreenSize.y);
            vec2 ratio = normalize(oneOverSize);
            float minStepSize = min(oneOverSize.x, oneOverSize.y) * 0.5;
            vec3 radiance = vec3(baseRadiance); //shift down (-) for night or up (+) for day
            float noise = rand(tc);
            for(int i = 0; i < sampleCount; i ++) { // can not stride more here
                float angle = (0.5 + float(i) + noise) * tauOverRays; // Jitter the angle
                vec2 rayDirection = vec2(cos(angle), sin(angle));
                vec2 sampleTC = tc;
                for (int step = 0; step < maxDistance; step += 1) {
                  float df = Texel(tex, sampleTC).r;
                  sampleTC += rayDirection * df * ratio;
                  if(sampleTC.x < 0.0 || sampleTC.x > 1.0 ||
                    sampleTC.y < 0.0 || sampleTC.y > 1.0) break;
                  if (df <= minStepSize) {
                    //vec3 hitColor = pow(Texel(surfaceTexture, sampleTC).rgb, vec3(2.2)); // FROM SRGB
                    // Clamp brightness to prevent spazzing from muzzle flashes/tracers
                    // hitColor = min(hitColor, vec3(2.0));
                    // radiance.rgb += hitColor;
                    radiance.rgb += pow(Texel(surfaceTexture, sampleTC).rgb, vec3(2.2)); // FROM SRGB
                    break;
                  }
                }
            }
            return vec4(pow(radiance * oneOverRays, vec3(1.0 / 2.2)), 1.0);  // Average, then TO SRGB
        }
    ]])
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
    -- love.graphics.clear(255,255,255,0.1,1,1)


end

function shader.pass()
        

    -- Seed pass
    render(scene_canvas, seed_shader, jfa_canvas1)
    
    gi_shader:send("surfaceTexture", scene_canvas)
    gi_shader:send("maxDistance", shader.distance)
    gi_shader:send("sampleCount", shader.sample)
    gi_shader:send("baseRadiance", shader.radiance)
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
    render(df_canvas, gi_shader)
    
    --if water / smoke doesnt get drawn then these last two calls are necessary
    -- love.graphics.setShader() 
    -- love.graphics.draw(scene_canvas)

end

return shader