-- test-glass-refraction.lua
-- Standalone LÖVE2D demo: Glass refraction as a GI game mechanic
-- Implements a minimal JFA → DF → glass-aware ray march pipeline
-- Controls:
--   Mouse       : Move the glass pane
--   Up/Down     : Adjust IOR (index of refraction)
--   G           : Toggle glass on/off
--   C           : Cycle glass color (clear, red, blue, green, amber)
--   R           : Reset scene
--   1/2/3       : Switch scenes (basic, prism, maze)
--   Space       : Pause/Resume
--   Escape      : Quit

local lg = love.graphics
local W, H

-- ─── Tunable Parameters ───
local params = {
    ior = 1.5,          -- Glass index of refraction
    ior_min = 1.0,
    ior_max = 3.0,
    ior_step = 0.05,
    gi_rays = 30,       -- Rays per pixel for GI
    gi_steps = 8,       -- Max steps per ray
    base_radiance = 0.05,
    glass_enabled = true,
    paused = false,
    scene = 1,
    glass_color_index = 1,
}

local glass_colors = {
    {name = "Clear",  color = {0.9, 0.95, 1.0}},
    {name = "Red",    color = {1.0, 0.2, 0.15}},
    {name = "Blue",   color = {0.15, 0.3, 1.0}},
    {name = "Green",  color = {0.15, 0.9, 0.2}},
    {name = "Amber",  color = {1.0, 0.7, 0.1}},
}

-- Glass pane state (world coords)
local glass = {
    x = 0, y = 0,
    width = 12, height = 120,
    angle = 0,
}

-- Additional glass objects for scenes
local glass_objects = {}

-- Light emitters
local lights = {}

-- Solid walls
local walls = {}

-- ─── Canvases & Shaders ───
local scene_canvas, jfa1, jfa2, df_canvas, gi_canvas
local seed_shader, jfa_shader, df_shader, gi_shader, upscale_shader

-- ─── GLASS-ALPHA ENCODING ───
-- We draw glass with alpha = 0.25 so the GI shader can identify it
local GLASS_ALPHA = 0.25

function love.load()
    love.window.setTitle("Glass Refraction GI Demo")
    love.window.setMode(800, 600, {resizable = true, vsync = true})
    W = lg.getWidth()
    H = lg.getHeight()

    glass.x = W / 2
    glass.y = H / 2

    setupScene(params.scene)
    createCanvasesAndShaders()
end

function setupScene(sceneId)
    lights = {}
    walls = {}
    glass_objects = {}

    if sceneId == 1 then
        -- Basic scene: two lights, one wall, one glass pane (mouse-controlled)
        table.insert(lights, {x = 150, y = 200, r = 40, color = {1.0, 0.9, 0.5}})
        table.insert(lights, {x = 650, y = 400, r = 30, color = {0.3, 0.6, 1.0}})
        table.insert(lights, {x = 400, y = 100, r = 25, color = {1.0, 0.3, 0.4}})

        -- Solid walls
        table.insert(walls, {x = 300, y = 350, w = 200, h = 12})
        table.insert(walls, {x = 100, y = 150, w = 12, h = 200})

    elseif sceneId == 2 then
        -- Prism scene: single white light, triangular glass prism
        table.insert(lights, {x = 100, y = H/2, r = 50, color = {1.0, 1.0, 1.0}})

        -- Three glass panes forming a triangle prism
        local cx, cy = W/2, H/2
        table.insert(glass_objects, {x = cx - 30, y = cy - 60, w = 8, h = 120, color = {1.0, 0.3, 0.3}})
        table.insert(glass_objects, {x = cx + 30, y = cy - 60, w = 8, h = 120, color = {0.3, 0.3, 1.0}})
        table.insert(glass_objects, {x = cx - 30, y = cy + 55, w = 68, h = 8, color = {0.3, 1.0, 0.3}})

        table.insert(walls, {x = 600, y = 100, w = 12, h = 400})

    elseif sceneId == 3 then
        -- Maze scene: lights outside, glass windows in walls
        table.insert(lights, {x = 50, y = 50, r = 35, color = {1.0, 0.8, 0.3}})
        table.insert(lights, {x = 750, y = 550, r = 35, color = {0.3, 0.8, 1.0}})

        -- Maze walls with glass "windows"
        table.insert(walls, {x = 200, y = 50,  w = 12, h = 180})
        -- glass window gap
        table.insert(glass_objects, {x = 200, y = 230, w = 12, h = 40, color = {0.9, 0.9, 1.0}})
        table.insert(walls, {x = 200, y = 270, w = 12, h = 280})

        table.insert(walls, {x = 400, y = 100, w = 12, h = 200})
        table.insert(glass_objects, {x = 400, y = 300, w = 12, h = 50, color = {1.0, 0.5, 0.2}})
        table.insert(walls, {x = 400, y = 350, w = 12, h = 200})

        table.insert(walls, {x = 600, y = 50,  w = 12, h = 250})
        table.insert(glass_objects, {x = 600, y = 300, w = 12, h = 40, color = {0.3, 1.0, 0.5}})
        table.insert(walls, {x = 600, y = 340, w = 12, h = 210})
    end
end

function createCanvasesAndShaders()
    -- Calculate GI resolution (scale down for performance)
    local pixel_count = W * H
    local gi_scale = math.min(1.0, math.sqrt(400000 / pixel_count))
    local gi_w = math.max(128, math.floor(W * gi_scale))
    local gi_h = math.max(128, math.floor(H * gi_scale))

    scene_canvas = lg.newCanvas(W, H)
    jfa1 = lg.newCanvas(gi_w, gi_h, {format = "rgba16f"})
    jfa2 = lg.newCanvas(gi_w, gi_h, {format = "rgba16f"})
    df_canvas = lg.newCanvas(gi_w, gi_h)
    gi_canvas = lg.newCanvas(gi_w, gi_h)

    -- Store for pass
    params.gi_scale = gi_scale
    params.gi_w = gi_w
    params.gi_h = gi_h

    -- Seed shader: surfaces → UV coords
    seed_shader = lg.newShader([[
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec4 p = Texel(tex, tc);
            // Anything with alpha > 0.1 is a surface (opaque or glass)
            return p.a > 0.1 ? vec4(tc, 0.0, 1.0) : vec4(0.0);
        }
    ]])

    -- JFA shader: jump flood for nearest surface
    jfa_shader = lg.newShader([[
        uniform float stepSize;
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec2 offset = stepSize / vec2(love_ScreenSize.x, love_ScreenSize.y);
            vec2 bestPoint = vec2(-2.0);
            float bestDist = 1e9;
            for (float y = -1.0; y <= 1.0; y += 1.0) {
                for (float x = -1.0; x <= 1.0; x += 1.0) {
                    vec2 s = tc + vec2(x, y) * offset;
                    if (s.x < 0.0 || s.x > 1.0 || s.y < 0.0 || s.y > 1.0) continue;
                    vec2 data = Texel(tex, s).xy;
                    if (data.x > 0.0 || data.y > 0.0) {
                        float d = length(tc - data);
                        if (d < bestDist) { bestDist = d; bestPoint = data; }
                    }
                }
            }
            return vec4(bestPoint, 0.0, 1.0);
        }
    ]])

    -- Distance field shader
    df_shader = lg.newShader([[
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            float dist = length(tc - Texel(tex, tc).xy);
            return vec4(dist, 0.0, 0.0, 1.0);
        }
    ]])

    -- Glass-aware GI shader (inline for standalone test)
    gi_shader = lg.newShader([[
        #if defined(VERTEX) || __VERSION__ > 100 || defined(GL_FRAGMENT_PRECISION_HIGH)
            #define HP highp
        #else
            #define HP mediump
        #endif

        uniform sampler2D surfaceTexture;
        uniform HP float baseRadiance;
        uniform HP float ior;
        uniform bool glassEnabled;

        const HP float PI = 3.14159265359;
        const HP float GLASS_ALPHA_MIN = 0.15;
        const HP float GLASS_ALPHA_MAX = 0.40;

        HP float rand(vec2 co) {
            return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
        }

        bool isGlass(vec4 p) {
            return glassEnabled && p.a >= GLASS_ALPHA_MIN && p.a <= GLASS_ALPHA_MAX;
        }

        // Estimate normal from DF gradient
        vec2 getNormal(Image dfTex, vec2 tc) {
            vec2 ts = vec2(1.0) / vec2(love_ScreenSize.x, love_ScreenSize.y);
            float dL = Texel(dfTex, tc - vec2(ts.x, 0.0)).r;
            float dR = Texel(dfTex, tc + vec2(ts.x, 0.0)).r;
            float dU = Texel(dfTex, tc - vec2(0.0, ts.y)).r;
            float dD = Texel(dfTex, tc + vec2(0.0, ts.y)).r;
            vec2 g = vec2(dR - dL, dD - dU);
            float l = length(g);
            return l > 0.001 ? g / l : vec2(0.0, 1.0);
        }

        // 2D refract with TIR fallback
        vec2 refract2D(vec2 inc, vec2 n, float eta) {
            float cosI = -dot(inc, n);
            if (cosI < 0.0) { n = -n; cosI = -cosI; }
            float sinT2 = eta * eta * (1.0 - cosI * cosI);
            if (sinT2 > 1.0) {
                // Total internal reflection
                return inc - 2.0 * dot(inc, n) * n;
            }
            float cosT = sqrt(1.0 - sinT2);
            return eta * inc + (eta * cosI - cosT) * n;
        }

        // Schlick Fresnel
        float fresnel(float cosT, float n1, float n2) {
            float r0 = (n1 - n2) / (n1 + n2);
            r0 = r0 * r0;
            return r0 + (1.0 - r0) * pow(1.0 - cosT, 5.0);
        }

        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            HP float oneOverRays = 1.0 / 30.0;
            HP float tauOverRays = 2.0 * PI * oneOverRays;
            vec2 oneOverSize = vec2(1.0) / vec2(love_ScreenSize.x, love_ScreenSize.y);
            vec2 ratio = normalize(oneOverSize);
            HP float minStep = min(oneOverSize.x, oneOverSize.y) * 0.1;

            vec3 radiance = vec3(baseRadiance);
            HP float noise = rand(tc);

            for (HP float i = 0.0; i < 30.0; i += 1.0) {
                HP float angle = (0.5 + i + noise) * tauOverRays;
                vec2 rayDir = vec2(cos(angle), sin(angle));
                vec2 pos = tc;
                vec3 tint = vec3(1.0);
                int bounces = 2;
                HP float totalDist = 0.0;

                for (HP float step = 0.0; step < 12.0; step += 1.0) {
                    HP float df = Texel(tex, pos).r;
                    pos += rayDir * df * ratio;
                    totalDist += df;

                    if (pos.x < 0.0 || pos.x > 1.0 || pos.y < 0.0 || pos.y > 1.0) break;

                    if (df <= minStep) {
                        vec4 hit = Texel(surfaceTexture, pos);

                        // ── Glass: refract and continue ──
                        if (isGlass(hit) && bounces > 0) {
                            bounces--;
                            vec2 n = getNormal(tex, pos);
                            float cosT = abs(dot(rayDir, n));
                            float refl = fresnel(cosT, 1.0, ior);

                            // Tint by glass color
                            vec3 gc = pow(hit.rgb, vec3(2.2));
                            tint *= mix(gc, vec3(1.0), 0.3);

                            // Reflected contribution
                            float falloff = 1.0 - smoothstep(0.0, 8.0, totalDist);
                            radiance += gc * falloff * refl * 0.4;

                            // Refract and push past surface
                            rayDir = normalize(refract2D(rayDir, n, 1.0 / ior));
                            pos += rayDir * minStep * 5.0 * ratio;
                            continue;
                        }

                        // ── Opaque hit ──
                        vec3 hc = pow(hit.rgb, vec3(2.2));
                        float falloff = 1.0 - smoothstep(0.0, 8.0, totalDist);
                        radiance += hc * falloff * tint;
                        break;
                    }
                }
            }

            return vec4(pow(radiance * oneOverRays, vec3(1.0 / 2.2)), 1.0);
        }
    ]])

    -- Upscale + composite shader
    upscale_shader = lg.newShader([[
        uniform sampler2D giTexture;
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec4 gi = Texel(giTexture, tc);
            vec4 scene = Texel(tex, tc);
            // Blend: scene lit by GI
            return scene * 0.4 + gi * 0.8;
        }
    ]])
end

function love.resize(w, h)
    W, H = w, h
    createCanvasesAndShaders()
end

function love.update(dt)
    if params.paused then return end

    -- Glass follows mouse
    local mx, my = love.mouse.getPosition()
    glass.x = mx
    glass.y = my
end

-- ─── Render the scene to the scene canvas ───
function drawScene()
    lg.setCanvas(scene_canvas)
    lg.clear(0, 0, 0, 0)

    -- Draw solid walls (fully opaque)
    lg.setColor(0.5, 0.45, 0.4, 1.0)
    for _, w in ipairs(walls) do
        lg.rectangle("fill", w.x, w.y, w.w, w.h)
    end

    -- Draw light emitters (bright colored circles)
    for _, l in ipairs(lights) do
        lg.setColor(l.color[1], l.color[2], l.color[3], 1.0)
        lg.circle("fill", l.x, l.y, l.r)
        -- Soft outer glow
        lg.setColor(l.color[1], l.color[2], l.color[3], 0.5)
        lg.circle("fill", l.x, l.y, l.r * 1.5)
    end

    -- Draw glass objects (alpha = GLASS_ALPHA for detection)
    local gc = glass_colors[params.glass_color_index].color
    if params.glass_enabled then
        -- Mouse-controlled glass pane
        lg.setColor(gc[1], gc[2], gc[3], GLASS_ALPHA)
        lg.rectangle("fill", glass.x - glass.width/2, glass.y - glass.height/2,
                     glass.width, glass.height)
        -- Slight edge highlight
        lg.setColor(gc[1], gc[2], gc[3], 0.6)
        lg.setLineWidth(1)
        lg.rectangle("line", glass.x - glass.width/2, glass.y - glass.height/2,
                     glass.width, glass.height)
    end

    -- Draw fixed glass objects from scene
    for _, go in ipairs(glass_objects) do
        lg.setColor(go.color[1], go.color[2], go.color[3], GLASS_ALPHA)
        lg.rectangle("fill", go.x, go.y, go.w, go.h)
        lg.setColor(go.color[1], go.color[2], go.color[3], 0.5)
        lg.rectangle("line", go.x, go.y, go.w, go.h)
    end

    lg.setColor(1, 1, 1, 1)
    lg.setCanvas()
end

-- ─── Run the GI pipeline ───
function renderGI()
    local gi_scale = params.gi_scale

    -- 1. Seed pass: scene → UV coords
    lg.setCanvas(jfa1)
    lg.clear(0, 0, 0, 0)
    lg.setShader(seed_shader)
    lg.draw(scene_canvas, 0, 0, 0, gi_scale, gi_scale)

    -- 2. JFA passes
    local passes = math.ceil(math.log(math.max(params.gi_w, params.gi_h)) / math.log(2)) + 2
    for i = 1, passes do
        jfa_shader:send("stepSize", math.pow(2, passes - i))
        lg.setCanvas(jfa2)
        lg.setShader(jfa_shader)
        lg.draw(jfa1)
        jfa1, jfa2 = jfa2, jfa1
    end

    -- 3. Distance field
    lg.setCanvas(df_canvas)
    lg.clear(0, 0, 0, 0)
    lg.setShader(df_shader)
    lg.draw(jfa1)

    -- 4. Glass-aware GI ray march
    gi_shader:send("surfaceTexture", scene_canvas)
    gi_shader:send("baseRadiance", params.base_radiance)
    gi_shader:send("ior", params.ior)
    gi_shader:send("glassEnabled", params.glass_enabled)

    lg.setCanvas(gi_canvas)
    lg.clear(0, 0, 0, 0)
    lg.setShader(gi_shader)
    lg.draw(df_canvas)

    -- 5. Final composite: upscale GI + scene
    lg.setCanvas()
    lg.setShader(upscale_shader)
    upscale_shader:send("giTexture", gi_canvas)
    lg.draw(scene_canvas)
    lg.setShader()
end

function love.draw()
    drawScene()
    renderGI()
    drawHUD()
end

function drawHUD()
    lg.setColor(0, 0, 0, 0.6)
    lg.rectangle("fill", 5, 5, 320, 220)
    lg.setColor(1, 1, 1, 1)

    local y = 12
    local function line(text)
        lg.print(text, 12, y)
        y = y + 18
    end

    line("── Glass Refraction GI Demo ──")
    line(string.format("IOR: %.2f  (Up/Down to adjust)", params.ior))
    line(string.format("Glass: %s  (G to toggle)", params.glass_enabled and "ON" or "OFF"))
    line(string.format("Color: %s  (C to cycle)", glass_colors[params.glass_color_index].name))
    line(string.format("Scene: %d/3  (1/2/3 to switch)", params.scene))
    line("")
    line("Mouse: Move glass pane")
    line("Space: Pause/Resume")
    line("R: Reset   Esc: Quit")
    line("")
    line(string.format("FPS: %d  |  GI res: %dx%d",
        love.timer.getFPS(), params.gi_w, params.gi_h))

    if params.paused then
        lg.setColor(1, 1, 0, 1)
        lg.print("PAUSED", W/2 - 30, 20)
    end

    lg.setColor(1, 1, 1, 1)
end

function love.keypressed(key)
    if key == "up" then
        params.ior = math.min(params.ior + params.ior_step, params.ior_max)
    elseif key == "down" then
        params.ior = math.max(params.ior - params.ior_step, params.ior_min)
    elseif key == "g" then
        params.glass_enabled = not params.glass_enabled
    elseif key == "c" then
        params.glass_color_index = (params.glass_color_index % #glass_colors) + 1
    elseif key == "space" then
        params.paused = not params.paused
    elseif key == "r" then
        glass.x, glass.y = W/2, H/2
        params.ior = 1.5
        params.glass_enabled = true
        params.glass_color_index = 1
        setupScene(params.scene)
    elseif key == "1" then
        params.scene = 1; setupScene(1)
    elseif key == "2" then
        params.scene = 2; setupScene(2)
    elseif key == "3" then
        params.scene = 3; setupScene(3)
    elseif key == "escape" then
        love.event.quit()
    end
end
