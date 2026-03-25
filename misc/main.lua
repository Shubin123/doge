-- Glass Refraction GI Demo (Radiance Cascade style)
-- Based on: "Refracting Radiance Cascades" approach
-- Light rays passing through glass objects visibly bend, tint, and create caustics.
--
-- Controls:
--   Mouse        : Move the glass block
--   Up/Down      : Adjust IOR (index of refraction)
--   Left/Right   : Rotate the glass block
--   V/B          : Decrease/Increase glass clarity (frosted ↔ clear)
--   S            : Cycle glass shape (rect, circle, triangle, hex, lens)
--   M            : Cycle material (glass, mirror, prism)
--   G            : Toggle glass on/off
--   C            : Cycle glass color
--   1/2/3        : Switch scenes
--   +/-          : Adjust glass thickness
--   Space        : Pause
--   R            : Reset
--   Escape       : Quit

local lg = love.graphics
local W, H

local params = {
    ior = 1.45,
    ior_min = 1.0,
    ior_max = 30.0,
    ior_step = 0.05,
    base_radiance = 0.2,
    glass_enabled = true,
    paused = false,
    scene = 1,
    glass_color_index = 1,
    glass_thickness = 50,  -- pixels, much thicker for visible refraction
    glass_clarity = 0.8,  -- 0.0 = fully frosted, 1.0 = perfectly clear
    clarity_step = 0.05,
    shape_index = 1,
    material_index = 1,  -- 1=Glass, 2=Mirror, 3=Prism
}

local glass_shapes = {"Rectangle", "Circle", "Triangle", "Hexagon", "Lens"}
local materials = {"Glass", "Mirror", "Prism"}

local glass_colors = {
    {name = "Clear",  color = {0.85, 0.9, 1.0}},
    {name = "Red",    color = {1.0, 0.15, 0.1}},
    {name = "Blue",   color = {0.1, 0.25, 1.0}},
    {name = "Green",  color = {0.1, 0.85, 0.15}},
    {name = "Amber",  color = {1.0, 0.65, 0.05}},
    {name = "Purple", color = {0.7, 0.1, 1.0}},
}

-- Mouse-controlled glass block
local glass = {
    x = 0, y = 0,
    width = 50,
    height = 160,
    angle = 0,       -- rotation in radians
}

local glass_objects = {}
local mirror_objects = {}
local prism_objects = {}
local lights = {}
local walls = {}

-- Alpha encoding for materials
local MIRROR_ALPHA = 0.48  -- between glass (0.43) and wall (0.5)
local PRISM_ALPHA = 0.46   -- between glass and mirror

-- Canvases & Shaders
local scene_canvas, scene_material, jfa1, jfa2, df_canvas, gi_canvas
local seed_shader, jfa_shader, df_shader, gi_shader, upscale_shader

-- Glass alpha is dynamic based on clarity:
-- clarity 1.0 (clear)   → alpha ≈ 0.16 (barely visible, max transmission)
-- clarity 0.0 (frosted) → alpha ≈ 0.40 (visibly opaque, blocks most light)
local function getGlassAlpha()
    return 0.40 - params.glass_clarity * 0.24
end

function love.load()
    love.window.setTitle("Glass Refraction GI — Radiance Cascade Style")
    love.window.setMode(800, 600, {resizable = true, vsync = true})
    W = lg.getWidth()
    H = lg.getHeight()
    glass.x = W / 2
    glass.y = H / 2
    glass.width = params.glass_thickness
    setupScene(params.scene)
    createCanvasesAndShaders()
end

function setupScene(id)
    lights = {}
    walls = {}
    glass_objects = {}
    mirror_objects = {}
    prism_objects = {}

    if id == 1 then
        -- Basic: lights + walls + mirror
        table.insert(lights, {x = 120, y = 180, r = 50, color = {1.0, 0.95, 0.6}})
        table.insert(lights, {x = 680, y = 420, r = 40, color = {0.3, 0.5, 1.0}})
        table.insert(lights, {x = 400, y = 80,  r = 30, color = {1.0, 0.25, 0.3}})

        table.insert(walls, {x = 50,  y = 450, w = 300, h = 14})
        table.insert(walls, {x = 500, y = 200, w = 14,  h = 250})
        table.insert(walls, {x = 200, y = 100, w = 14,  h = 200})

        -- A mirror on the right side
        table.insert(mirror_objects, {x = 700, y = 150, w = 10, h = 140, color = {0.9, 0.9, 0.95}})

    elseif id == 2 then
        -- Prism scene: white light through prism creates rainbow
        table.insert(lights, {x = 80, y = H/2, r = 60, color = {1.0, 1.0, 1.0}})

        -- Prism in the center
        local cx, cy = W/2, H/2
        table.insert(prism_objects, {x = cx - 30, y = cy - 70, w = 60, h = 140, color = {0.9, 0.92, 1.0}, shape = "triangle"})

        -- Mirrors to bounce light around
        table.insert(mirror_objects, {x = 650, y = 100, w = 10, h = 200, color = {0.9, 0.9, 0.95}})
        table.insert(mirror_objects, {x = 650, y = 400, w = 10, h = 150, color = {0.9, 0.9, 0.95}})

        -- Catching wall
        table.insert(walls, {x = 50,  y = 500, w = 700, h = 14})

    elseif id == 3 then
        -- Full scene: glass windows, mirrors, prism
        table.insert(lights, {x = 50,  y = 60,  r = 45, color = {1.0, 0.85, 0.3}})
        table.insert(lights, {x = 750, y = 540, r = 45, color = {0.3, 0.7, 1.0}})
        table.insert(lights, {x = 400, y = 300, r = 35, color = {1.0, 1.0, 1.0}})

        -- Walls with glass windows
        table.insert(walls, {x = 200, y = 40,  w = 14, h = 160})
        table.insert(glass_objects, {x = 195, y = 200, w = 24, h = 60, color = {0.9, 0.9, 1.0}, angle = 0})
        table.insert(walls, {x = 200, y = 260, w = 14, h = 300})

        table.insert(walls, {x = 400, y = 80,  w = 14, h = 180})
        table.insert(glass_objects, {x = 395, y = 260, w = 24, h = 70, color = {1.0, 0.5, 0.15}, angle = 0})
        table.insert(walls, {x = 400, y = 330, w = 14, h = 230})

        -- Mirrors
        table.insert(mirror_objects, {x = 600, y = 40, w = 10, h = 200, color = {0.9, 0.9, 0.95}})
        table.insert(mirror_objects, {x = 300, y = 450, w = 200, h = 10, color = {0.9, 0.9, 0.95}})

        -- Prism
        table.insert(prism_objects, {x = 500, y = 400, w = 50, h = 100, color = {0.92, 0.92, 1.0}, shape = "triangle"})
    end
end

function createCanvasesAndShaders()
    local pixel_count = W * H
    local gi_scale = math.min(1.0, math.sqrt(500000 / pixel_count))
    local gi_w = math.max(128, math.floor(W * gi_scale))
    local gi_h = math.max(128, math.floor(H * gi_scale))

    scene_canvas = lg.newCanvas(W, H)
    -- Material canvas: R = is_glass (1.0), G = ior_encoded, B = glass_thickness_norm
    scene_material = lg.newCanvas(W, H)
    jfa1 = lg.newCanvas(gi_w, gi_h, {format = "rgba16f"})
    jfa2 = lg.newCanvas(gi_w, gi_h, {format = "rgba16f"})
    df_canvas = lg.newCanvas(gi_w, gi_h)
    gi_canvas = lg.newCanvas(gi_w, gi_h)

    params.gi_scale = gi_scale
    params.gi_w = gi_w
    params.gi_h = gi_h

    -- Seed: ALL surfaces with any alpha → UV coords
    -- Glass, walls, and lights are all seeded so the DF catches everything.
    -- The GI shader handles glass specially (jumps through instead of stopping).
    seed_shader = lg.newShader([[
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec4 p = Texel(tex, tc);
            return p.a > 0.08 ? vec4(tc, 0.0, 1.0) : vec4(0.0);
        }
    ]])

    -- JFA
    jfa_shader = lg.newShader([[
        uniform float stepSize;
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec2 off = stepSize / vec2(love_ScreenSize.xy);
            vec2 best = vec2(-2.0);
            float bestD = 1e9;
            for (float dy = -1.0; dy <= 1.0; dy += 1.0) {
                for (float dx = -1.0; dx <= 1.0; dx += 1.0) {
                    vec2 s = tc + vec2(dx, dy) * off;
                    if (s.x < 0.0 || s.x > 1.0 || s.y < 0.0 || s.y > 1.0) continue;
                    vec2 d = Texel(tex, s).xy;
                    if (d.x > 0.0 || d.y > 0.0) {
                        float dist = length(tc - d);
                        if (dist < bestD) { bestD = dist; best = d; }
                    }
                }
            }
            return vec4(best, 0.0, 1.0);
        }
    ]])

    -- Distance field
    df_shader = lg.newShader([[
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            float d = length(tc - Texel(tex, tc).xy);
            return vec4(d, 0.0, 0.0, 1.0);
        }
    ]])

    -- ═══════════════════════════════════════════════════════════
    -- Glass-Aware GI Shader (Jump-Through Refraction)
    -- ═══════════════════════════════════════════════════════════
    -- Glass IS in the DF, so rays always find it reliably.
    -- On glass hit: refract the ray, scan forward to find the
    -- exit boundary, jump past it, and resume DF marching.
    -- This is efficient (no step cap) and reliable.
    gi_shader = lg.newShader([[
        #if defined(VERTEX) || __VERSION__ > 100 || defined(GL_FRAGMENT_PRECISION_HIGH)
            #define HP highp
        #else
            #define HP mediump
        #endif

        uniform sampler2D surfaceTexture;
        uniform HP float baseRadiance;
        uniform HP float ior;
        uniform HP float clarity;
        uniform bool glassEnabled;

        const HP float PI = 3.14159265359;
        const HP float GLASS_ALPHA_MIN = 0.13;
        const HP float GLASS_ALPHA_MAX = 0.43;

        HP float rand(vec2 co) {
            return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
        }

        bool isGlass(float a) {
            return glassEnabled && a >= GLASS_ALPHA_MIN && a <= GLASS_ALPHA_MAX;
        }

        // Mirror: alpha ~0.48
        bool isMirror(float a) {
            return a >= 0.47 && a <= 0.49;
        }

        // Prism: alpha ~0.46
        bool isPrism(float a) {
            return a >= 0.44 && a < 0.47;
        }

        bool isEmitterAlpha(float a) {
            return a >= 0.9;
        }

        // DF gradient → surface normal
        vec2 getNormal(Image dfTex, vec2 tc) {
            vec2 ts = 1.0 / vec2(love_ScreenSize.xy);
            float dL = Texel(dfTex, tc - vec2(ts.x, 0.0)).r;
            float dR = Texel(dfTex, tc + vec2(ts.x, 0.0)).r;
            float dU = Texel(dfTex, tc - vec2(0.0, ts.y)).r;
            float dD = Texel(dfTex, tc + vec2(0.0, ts.y)).r;
            vec2 g = vec2(dR - dL, dD - dU);
            float l = length(g);
            return l > 0.001 ? g / l : vec2(0.0, 1.0);
        }

        // Snell's law 2D
        vec2 refract2D(vec2 inc, vec2 n, float eta) {
            float cI = -dot(inc, n);
            if (cI < 0.0) { n = -n; cI = -cI; }
            float sT2 = eta * eta * (1.0 - cI * cI);
            if (sT2 > 1.0) return reflect(inc, n);
            return eta * inc + (eta * cI - sqrt(1.0 - sT2)) * n;
        }

        float fresnel(float cosT, float n1, float n2) {
            float r0 = (n1 - n2) / (n1 + n2);
            r0 *= r0;
            return r0 + (1.0 - r0) * pow(max(0.0, 1.0 - cosT), 5.0);
        }

        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            const int NUM_RAYS = 40;
            HP float oneOverRays = 1.0 / float(NUM_RAYS);
            HP float tauOverRays = 2.0 * PI * oneOverRays;
            vec2 pixSize = 1.0 / vec2(love_ScreenSize.xy);
            vec2 ratio = normalize(pixSize);
            HP float minStep = min(pixSize.x, pixSize.y) * 0.15;
            // Step size for scanning through glass interior
            HP float scanStep = min(pixSize.x, pixSize.y) * 2.0;

            vec3 radiance = vec3(baseRadiance);
            HP float noise = rand(tc);

            for (int i = 0; i < NUM_RAYS; i++) {
                HP float angle = (0.5 + float(i) + noise) * tauOverRays;
                vec2 rayDir = vec2(cos(angle), sin(angle));
                vec2 pos = tc;
                vec3 tint = vec3(1.0);
                HP float totalDist = 0.0;
                int refractions = 3;

                for (int step = 0; step < 48; step++) {
                    HP float df = Texel(tex, pos).r;
                    pos += rayDir * max(df, minStep * 0.5) * ratio;
                    totalDist += df;

                    if (pos.x < 0.0 || pos.x > 1.0 || pos.y < 0.0 || pos.y > 1.0) break;
                    if (totalDist > 0.7) break;

                    if (df <= minStep) {
                        vec4 hit = Texel(surfaceTexture, pos);
                        float hitAlpha = hit.a;

                        // ── GLASS HIT: refract and jump through ──
                        if (isGlass(hitAlpha) && refractions > 0) {
                            refractions--;

                            // Entry refraction
                            vec2 normal = getNormal(tex, pos);
                            float cosTheta = abs(dot(-rayDir, normal));
                            float eta = 1.0 / ior;

                            // Transmission based on clarity
                            float transmission = 0.6 + clarity * 0.4;

                            // Tint by glass color
                            vec3 gc = hit.rgb;
                            gc = hitAlpha > 0.01 ? gc / hitAlpha : vec3(1.0);
                            float tintStr = mix(0.7, 0.2, clarity);
                            tint *= mix(vec3(1.0), gc, tintStr) * transmission;

                            // Refract entry direction
                            vec2 refDir = normalize(refract2D(rayDir, normal, eta));

                            // Frosted scatter
                            float scatter = (1.0 - clarity) * 0.35;
                            float sa = scatter * (rand(pos + vec2(float(i))) - 0.5) * PI;
                            float cs = cos(sa), sn = sin(sa);
                            refDir = normalize(vec2(refDir.x*cs - refDir.y*sn,
                                                    refDir.x*sn + refDir.y*cs));

                            // Scan forward to find exit boundary
                            vec2 scanPos = pos + refDir * scanStep * 2.0 * ratio;
                            for (int s = 0; s < 40; s++) {
                                vec4 sp = Texel(surfaceTexture, scanPos);
                                if (!isGlass(sp.a)) break;
                                scanPos += refDir * scanStep * ratio;
                            }

                            // Exit refraction
                            vec2 exitNormal = getNormal(tex, scanPos);
                            rayDir = normalize(refract2D(refDir, -exitNormal, ior));
                            pos = scanPos + rayDir * minStep * 4.0 * ratio;
                            continue;
                        }

                        // ── MIRROR HIT: reflect ray ──
                        if (isMirror(hitAlpha) && refractions > 0) {
                            refractions--;
                            vec2 normal = getNormal(tex, pos);
                            // Ensure normal faces against the ray
                            if (dot(rayDir, normal) > 0.0) normal = -normal;
                            rayDir = reflect(rayDir, normal);
                            // Push away from mirror surface
                            pos += rayDir * minStep * 4.0 * ratio;
                            continue;
                        }

                        // ── PRISM HIT: refract with chromatic dispersion ──
                        if (isPrism(hitAlpha) && refractions > 0) {
                            refractions--;

                            vec2 normal = getNormal(tex, pos);
                            float cosTheta = abs(dot(-rayDir, normal));

                            // Per-channel IOR for dispersion
                            // Red bends least, blue bends most
                            float iorR = ior * 0.97;
                            float iorG = ior;
                            float iorB = ior * 1.03;

                            // Refract entry
                            vec2 refDirR = normalize(refract2D(rayDir, normal, 1.0 / iorR));
                            vec2 refDirG = normalize(refract2D(rayDir, normal, 1.0 / iorG));
                            vec2 refDirB = normalize(refract2D(rayDir, normal, 1.0 / iorB));

                            // Average direction for scanning through prism body
                            vec2 refDir = normalize(refDirG);

                            // Scan to find exit
                            vec2 scanPos = pos + refDir * scanStep * 2.0 * ratio;
                            for (int s = 0; s < 40; s++) {
                                vec4 sp = Texel(surfaceTexture, scanPos);
                                if (!isPrism(sp.a)) break;
                                scanPos += refDir * scanStep * ratio;
                            }

                            // Exit with dispersion: shift tint by channel separation
                            vec2 exitNormal = getNormal(tex, scanPos);
                            vec2 exitR = normalize(refract2D(refDirR, -exitNormal, iorR));
                            vec2 exitG = normalize(refract2D(refDirG, -exitNormal, iorG));
                            vec2 exitB = normalize(refract2D(refDirB, -exitNormal, iorB));

                            // Color the tint based on angular separation
                            float spreadR = dot(exitR, exitG);
                            float spreadB = dot(exitB, exitG);
                            // Enhance color separation
                            tint.r *= 1.0 + (1.0 - spreadR) * 8.0;
                            tint.b *= 1.0 + (1.0 - spreadB) * 8.0;
                            tint *= 0.85; // slight absorption

                            // Use green channel direction as primary
                            rayDir = exitG;
                            pos = scanPos + rayDir * minStep * 4.0 * ratio;
                            continue;
                        }

                        // ── EMITTER HIT ──
                        if (isEmitterAlpha(hitAlpha)) {
                            vec3 hc = hit.rgb;
                            hc = hitAlpha > 0.01 ? hc / hitAlpha : hc;
                            hc = pow(hc, vec3(2.2));
                            float falloff = 1.0 - smoothstep(0.0, 0.6, totalDist);
                            falloff = pow(falloff, 0.7);
                            radiance += hc * falloff * tint;
                            break;
                        }

                        // ── WALL HIT (alpha 0.5..0.9) ──
                        if (hitAlpha > 0.5) {
                            break; // wall blocks ray
                        }

                        // ── EMPTY PIXEL near surface ──
                        // df is small but pixel is empty (just past glass edge, etc.)
                        // Push forward and keep marching
                        pos += rayDir * minStep * 3.0 * ratio;
                        continue;
                    }
                }
            }

            vec3 result = radiance * oneOverRays;
            result = result / (result + vec3(1.0));
            result = pow(result, vec3(1.0 / 2.2));
            return vec4(result, 1.0);
        }
    ]])

    -- Composite: upscale GI and blend with scene
    -- Only emitters (alpha >= 0.9) show their color directly.
    -- Walls and glass are invisible here — walls block GI, glass refracts it.
    upscale_shader = lg.newShader([[
        uniform sampler2D giTexture;
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec4 scene = Texel(tex, tc);
            vec4 gi = Texel(giTexture, tc);
            // Only emitters (alpha >= 0.9) show directly
            float isEmitter = step(0.9, scene.a);
            vec3 lit = scene.rgb * 0.3 * isEmitter + gi.rgb * 1.2;
            return vec4(lit, 1.0);
        }
    ]])
end

function love.resize(w, h)
    W, H = w, h
    createCanvasesAndShaders()
end

function love.update(dt)
    if params.paused then return end
    local mx, my = love.mouse.getPosition()
    glass.x = mx
    glass.y = my
    glass.width = params.glass_thickness
end

-- ─── Draw the scene to scene_canvas ───
function drawScene()
    lg.setCanvas(scene_canvas)
    lg.clear(0, 0, 0, 0)

    -- Solid walls: alpha = 0.7 (opaque blocker, NOT an emitter)
    lg.setColor(0.55, 0.5, 0.42, 0.7)
    for _, w in ipairs(walls) do
        lg.rectangle("fill", w.x, w.y, w.w, w.h)
    end

    -- Light emitters: alpha = 1.0 (only they emit radiance)
    for _, l in ipairs(lights) do
        -- Outer glow (still an emitter)
        lg.setColor(l.color[1], l.color[2], l.color[3], 0.95)
        lg.circle("fill", l.x, l.y, l.r * 2.0)
        -- Mid glow
        lg.setColor(l.color[1], l.color[2], l.color[3], 0.95)
        lg.circle("fill", l.x, l.y, l.r * 1.3)
        -- Core
        lg.setColor(l.color[1], l.color[2], l.color[3], 1.0)
        lg.circle("fill", l.x, l.y, l.r)
    end

    -- Fixed glass objects from scene (thick, with glass alpha)
    for _, go in ipairs(glass_objects) do
        lg.push()
        lg.translate(go.x + go.w/2, go.y + go.h/2)
        if go.angle then lg.rotate(go.angle) end
        lg.setColor(go.color[1], go.color[2], go.color[3], getGlassAlpha())
        lg.rectangle("fill", -go.w/2, -go.h/2, go.w, go.h)
        lg.pop()
    end

    -- Mirror objects (highly reflective, alpha = MIRROR_ALPHA)
    for _, mo in ipairs(mirror_objects) do
        lg.push()
        lg.translate(mo.x + mo.w/2, mo.y + mo.h/2)
        lg.setColor(mo.color[1], mo.color[2], mo.color[3], MIRROR_ALPHA)
        lg.rectangle("fill", -mo.w/2, -mo.h/2, mo.w, mo.h)
        lg.pop()
    end

    -- Prism objects (alpha = PRISM_ALPHA)
    for _, po in ipairs(prism_objects) do
        lg.push()
        lg.translate(po.x + po.w/2, po.y + po.h/2)
        lg.setColor(po.color[1], po.color[2], po.color[3], PRISM_ALPHA)
        if po.shape == "triangle" then
            local w2, h2 = po.w/2, po.h/2
            lg.polygon("fill", 0, -h2, -w2, h2, w2, h2)
        else
            lg.rectangle("fill", -po.w/2, -po.h/2, po.w, po.h)
        end
        lg.pop()
    end

    -- Mouse-controlled object (material depends on params.material_index)
    if params.glass_enabled then
        local gc = glass_colors[params.glass_color_index].color
        local mat = materials[params.material_index]
        local alpha
        if mat == "Mirror" then
            alpha = MIRROR_ALPHA
        elseif mat == "Prism" then
            alpha = PRISM_ALPHA
        else
            alpha = getGlassAlpha()
        end

        lg.push()
        lg.translate(glass.x, glass.y)
        lg.rotate(glass.angle)
        lg.setColor(gc[1], gc[2], gc[3], alpha)

        local shape = glass_shapes[params.shape_index]
        local w2, h2 = glass.width/2, glass.height/2

        if shape == "Rectangle" then
            lg.rectangle("fill", -w2, -h2, glass.width, glass.height)
        elseif shape == "Circle" then
            lg.circle("fill", 0, 0, math.max(w2, h2))
        elseif shape == "Triangle" then
            lg.polygon("fill", 0, -h2, -w2, h2, w2, h2)
        elseif shape == "Hexagon" then
            local r = math.max(w2, h2)
            local verts = {}
            for i = 0, 5 do
                local a = math.rad(60 * i - 30)
                table.insert(verts, math.cos(a) * r)
                table.insert(verts, math.sin(a) * r)
            end
            lg.polygon("fill", verts)
        elseif shape == "Lens" then
            lg.ellipse("fill", 0, 0, w2, h2)
        end

        lg.pop()
    end

    lg.setColor(1, 1, 1, 1)
    lg.setCanvas()
end

-- ─── GI Pipeline ───
function renderGI()
    local gs = params.gi_scale

    -- 1. Seed
    lg.setCanvas(jfa1)
    lg.clear(0, 0, 0, 0)
    lg.setShader(seed_shader)
    lg.draw(scene_canvas, 0, 0, 0, gs, gs)

    -- 2. JFA
    local passes = math.ceil(math.log(math.max(params.gi_w, params.gi_h)) / math.log(2)) + 2
    for i = 1, passes do
        jfa_shader:send("stepSize", math.pow(2, passes - i))
        lg.setCanvas(jfa2)
        lg.setShader(jfa_shader)
        lg.draw(jfa1)
        jfa1, jfa2 = jfa2, jfa1
    end

    -- 3. Distance Field
    lg.setCanvas(df_canvas)
    lg.clear(0, 0, 0, 0)
    lg.setShader(df_shader)
    lg.draw(jfa1)

    -- 4. Glass-aware GI
    gi_shader:send("surfaceTexture", scene_canvas)
    gi_shader:send("baseRadiance", params.base_radiance)
    gi_shader:send("ior", params.ior)
    gi_shader:send("clarity", params.glass_clarity)
    gi_shader:send("glassEnabled", params.glass_enabled)

    lg.setCanvas(gi_canvas)
    lg.clear(0, 0, 0, 0)
    lg.setShader(gi_shader)
    lg.draw(df_canvas)

    -- 5. Composite
    lg.setCanvas()
    lg.setShader(upscale_shader)
    upscale_shader:send("giTexture", gi_canvas)
    lg.draw(scene_canvas)
    lg.setShader()
end

function love.draw()
    lg.clear(0.02, 0.02, 0.04)
    drawScene()
    renderGI()
    drawHUD()
end

function drawHUD()
    lg.setColor(0, 0, 0, 0.65)
    lg.rectangle("fill", 4, 4, 340, 270, 6, 6)
    lg.setColor(1, 1, 1, 0.95)

    local y = 12
    local function line(t)
        lg.print(t, 14, y)
        y = y + 17
    end

    line("═══ Glass Refraction GI Demo ═══")
    line(string.format("IOR: %.2f  (Up/Down)", params.ior))
    line(string.format("Glass: %s  (G)", params.glass_enabled and "ON" or "OFF"))
    line(string.format("Color: %s  (C)", glass_colors[params.glass_color_index].name))
    line(string.format("Material: %s  (M)", materials[params.material_index]))
    line(string.format("Shape: %s  (S)", glass_shapes[params.shape_index]))
    line(string.format("Clarity: %.0f%%  (V/B)", params.glass_clarity * 100))
    line(string.format("Thickness: %dpx  (+/-)", params.glass_thickness))
    line(string.format("Rotation: %.0f°  (Left/Right)", math.deg(glass.angle)))
    line(string.format("Scene: %d/3  (1/2/3)", params.scene))
    line("")
    line("Mouse: Move glass block")
    line("Space: Pause  |  R: Reset")
    line("")
    line(string.format("FPS: %d  |  GI: %dx%d  |  Scale: %.0f%%",
        love.timer.getFPS(), params.gi_w, params.gi_h, params.gi_scale * 100))

    -- Visual IOR indicator
    y = y + 5
    local barW = 200
    local iorNorm = (params.ior - params.ior_min) / (params.ior_max - params.ior_min)
    lg.setColor(0.3, 0.3, 0.3, 0.8)
    lg.rectangle("fill", 14, y, barW, 10, 3, 3)
    lg.setColor(0.4, 0.8, 1.0, 0.9)
    lg.rectangle("fill", 14, y, barW * iorNorm, 10, 3, 3)
    lg.setColor(1, 1, 1, 0.7)
    lg.print("Air 1.0          Glass 1.5         Diamond 2.4", 14, y + 12)

    if params.paused then
        lg.setColor(1, 1, 0, 1)
        local font = lg.getFont()
        lg.print("⏸ PAUSED", W/2 - 40, 20)
    end

    lg.setColor(1, 1, 1, 1)
end

function love.keypressed(key)
    if key == "up" then
        params.ior = math.min(params.ior + params.ior_step, params.ior_max)
    elseif key == "down" then
        params.ior = math.max(params.ior - params.ior_step, params.ior_min)
    elseif key == "left" then
        glass.angle = glass.angle - math.rad(5)
    elseif key == "right" then
        glass.angle = glass.angle + math.rad(5)
    elseif key == "g" then
        params.glass_enabled = not params.glass_enabled
    elseif key == "c" then
        params.glass_color_index = (params.glass_color_index % #glass_colors) + 1
    elseif key == "s" then
        params.shape_index = (params.shape_index % #glass_shapes) + 1
    elseif key == "m" then
        params.material_index = (params.material_index % #materials) + 1
    elseif key == "=" or key == "kp+" then
        params.glass_thickness = math.min(params.glass_thickness + 10, 200)
    elseif key == "-" or key == "kp-" then
        params.glass_thickness = math.max(params.glass_thickness - 10, 10)
    elseif key == "v" then
        params.glass_clarity = math.max(0.0, params.glass_clarity - params.clarity_step)
    elseif key == "b" then
        params.glass_clarity = math.min(1.0, params.glass_clarity + params.clarity_step)
    elseif key == "space" then
        params.paused = not params.paused
    elseif key == "r" then
        glass.x, glass.y = W/2, H/2
        glass.angle = 0
        params.ior = 1.45
        params.glass_enabled = true
        params.glass_color_index = 1
        params.glass_thickness = 50
        params.glass_clarity = 0.85
        params.shape_index = 1
        params.material_index = 1
        setupScene(params.scene)
    elseif key == "1" then params.scene = 1; setupScene(1)
    elseif key == "2" then params.scene = 2; setupScene(2)
    elseif key == "3" then params.scene = 3; setupScene(3)
    elseif key == "escape" then love.event.quit()
    end
end
