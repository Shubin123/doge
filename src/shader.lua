shader = {}

shader.distance = 30
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
            const float invGamma = 1.0 / 2.2;
            const float gamma = 2.2;
            
            float rayWeight = 1.0 / float(sampleCount);
            float angleStep = 2.0 * PI * rayWeight;
            vec2 pixelSize = vec2(1.0) / vec2(love_ScreenSize.x, love_ScreenSize.y);
            vec2 aspectRatio = normalize(pixelSize);
            float minStep = min(pixelSize.x, pixelSize.y) * 0.5;
            
            vec3 totalRadiance = vec3(baseRadiance);
            float jitter = rand(tc);
            
            for(int ray = 0; ray < sampleCount; ray++) {
                float angle = (0.5 + float(ray) + jitter) * angleStep;
                vec2 direction = vec2(cos(angle), sin(angle));
                vec2 position = tc;
                
                for(int step = 0; step < maxDistance; step++) {
                    float distance = Texel(tex, position).r;
                    position += direction * distance * aspectRatio;
                    
                    if(any(lessThan(position, vec2(0.0))) || any(greaterThan(position, vec2(1.0))))
                        break;
                    
                    if(distance <= minStep) {
                        vec3 surfaceColor = pow(Texel(surfaceTexture, position).rgb, vec3(gamma));
                        surfaceColor = min(surfaceColor, vec3(1.2));
                        totalRadiance += surfaceColor;
                        break;
                    }
                }
            }
            
            vec3 finalColor = pow(totalRadiance * rayWeight, vec3(invGamma));
            return vec4(finalColor, 1.0);
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

-- It's good practice to define a helper function for a standard render pass.
-- This reduces repetition and prevents common errors like forgetting to clear a canvas.
local function render_pass(input_texture, shader, output_canvas)
    -- A table of canvases can be passed to render to multiple targets.
    love.graphics.setCanvas({ canvas = output_canvas, clear = true })
    love.graphics.setShader(shader)
    love.graphics.draw(input_texture)
    love.graphics.setCanvas() -- Reset canvas to the screen
end

-- We'll assume your shader object is structured something like this:
-- shader = {
--     distance = 500,
--     sample = 32,
--     radiance = {1.0, 0.8, 0.6},
--     composite_original_scene = true, -- A flag to control final composition
--     -- ... your shaders and canvases
-- }

-- It's good practice to define a helper function for a standard render pass.
-- This reduces repetition and prevents common errors like forgetting to clear a canvas.
local function render_pass(input_texture, shader, output_canvas)
    -- A table of canvases can be passed to render to multiple targets.
    love.graphics.setCanvas({ canvas = output_canvas, clear = true })
    love.graphics.setShader(shader)
    love.graphics.draw(input_texture)
    love.graphics.setCanvas() -- Reset canvas to the screen
end

-- We'll assume your shader object is structured something like this:
-- shader = {
--     distance = 500,
--     sample = 32,
--     radiance = {1.0, 0.8, 0.6},
--     composite_original_scene = true, -- A flag to control final composition
--     -- ... your shaders and canvases
-- }

function shader.pass()
    --//------------------------------------------------------------------//
    --// STEP 0: SETUP AND SEND UNIFORMS                                  //
    --//------------------------------------------------------------------//
    -- Send uniforms that are constant for the entire GI effect.
    gi_shader:send("maxDistance", shader.distance)
    gi_shader:send("sampleCount", shader.sample)
    gi_shader:send("baseRadiance", shader.radiance)

    --//------------------------------------------------------------------//
    --// STEP 1: SEED PASS                                                //
    --// Identifies initial seed points (e.g., light sources) from the   //
    --// main scene and draws them to the first JFA canvas.               //
    --//------------------------------------------------------------------//
    render_pass(scene_canvas, seed_shader, jfa_canvas1)

    --//------------------------------------------------------------------//
    --// STEP 2: JUMP FLOOD ALGORITHM (JFA)                               //
    --// Progressively floods the canvas to find the nearest seed point  //
    --// for each pixel. We ping-pong between two canvases.               //
    --//------------------------------------------------------------------//
    local passes = math.ceil(math.log(math.max(var.game_width, var.game_height), 2))

    for i = 1, passes do
        local step_size = 2 ^ (passes - i)
        jfa_shader:send("stepSize", step_size)

        -- Perform one pass of the JFA, reading from jfa_canvas1 and writing to jfa_canvas2
        render_pass(jfa_canvas1, jfa_shader, jfa_canvas2)

        -- Swap canvases for the next iteration (ping-pong)
        jfa_canvas1, jfa_canvas2 = jfa_canvas2, jfa_canvas1
    end
    -- After the loop, jfa_canvas1 contains the final JFA result.

    --//------------------------------------------------------------------//
    --// STEP 3: DISTANCE FIELD PASS                                      //
    --// Converts the JFA result (containing coordinates of nearest     //
    --// seeds) into a grayscale distance field.                          //
    --//------------------------------------------------------------------//
    render_pass(jfa_canvas1, df_shader, df_canvas)

    --//------------------------------------------------------------------//
    --// STEP 4: GLOBAL ILLUMINATION PASS                                 //
    --// Uses the distance field to calculate and draw the illumination.  //
    --// This is the final effect, drawn directly to the screen.          //
    --//------------------------------------------------------------------//
    love.graphics.setShader(gi_shader)
    -- The GI shader needs both the distance field (which we draw) and the
    -- original scene texture to know where surfaces are.
    gi_shader:send("surfaceTexture", scene_canvas)
    love.graphics.draw(df_canvas)

    --//------------------------------------------------------------------//
    --// STEP 5: FINAL COMPOSITION & CLEANUP                              //
    --//------------------------------------------------------------------//
    
    -- Optionally, draw the original scene on top of the GI effect.
    -- This is useful if your GI is just for lighting and not for drawing
    -- the primary objects themselves.
    if shader.composite_original_scene then
        love.graphics.setBlendMode("alpha", "premultiplied")
        love.graphics.setShader() -- Use default shader to draw the original scene
        love.graphics.draw(scene_canvas)
        love.graphics.setBlendMode("alpha") -- Reset blend mode
    end

    -- CRITICAL: Always reset the shader at the end so subsequent drawing
    -- operations in your game don't accidentally use the GI shader.
    love.graphics.setShader()
end

return shader