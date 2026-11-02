local explosion = {}
explosion.explosions = {}

-- Explosion types
explosion.TYPES = {
    ROCKET = "rocket",
    DEATH = "death",
    IMPLOSION = "implosion" -- a black hole gun's hole collapsing: the wave alone
}

-- Blast wave per type: how far it spreads (px) and how long that takes (s).
-- The shader fades it out as it reaches the edge, so it's gone right on time.
local SHOCKWAVES = {
    [explosion.TYPES.ROCKET] = { radius = 350, duration = 0.6 },
    [explosion.TYPES.DEATH] = { radius = 500, duration = 0.9 },
    [explosion.TYPES.IMPLOSION] = { radius = 220, duration = 0.45 },
}

explosion.MAX_SHOCKWAVES = 4 -- waves distorted at once; the newest win

local explosion_image
local rocket_animation
local death_animation
local NO_SPRITE = { duration = 0, quads = {} }

function explosion.load()
    -- Initialize like portal.lua
    explosion.SHADERS = {}
    explosion.current_time = 0
    
    -- Load explosion spritesheet
    explosion_image = love.graphics.newImage("gfx/explosions/spritesheet/round_explosion/spritesheet/spritesheet.png")
    
    -- Create animations for different explosion types
    rocket_animation = createAnimation(explosion_image, 100, 100, 0.5, 60)
    death_animation = createAnimation(explosion_image, 128, 128, 1.067, 16)
    
    -- Create shockwave distortion shader
    explosion.SHADERS["shockwave"] = love.graphics.newShader([[

        #if defined(VERTEX) || __VERSION__ > 100 || defined(GL_FRAGMENT_PRECISION_HIGH)
        #define MY_HIGHP_OR_MEDIUMP highp
        #else
        #define MY_HIGHP_OR_MEDIUMP mediump
        #endif
        #define HP MY_HIGHP_OR_MEDIUMP

        extern HP number time;
        extern HP vec2  explosionCenter;   // wavefront origin, screen pixels
        extern HP number explosionRadius;  // current wavefront radius, screen pixels
        extern HP number maxRadius;        // radius at which the wave dissipates, screen pixels
        extern HP number distortionStrength; // peak refraction, in PIXELS (not tex units)

        // A real blast distorts the scene like a thin moving lens: the compressed
        // air at the front refracts light outward just ahead of the shell and pulls
        // it back just behind, the energy bleeds off as the shell expands, and the
        // superheated front glows and splits colour (chromatic refraction). We model
        // all of that around a narrow gaussian shell instead of a hard if() band.
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            HP vec2  toCenter = sc - explosionCenter;
            HP number dist = length(toCenter);
            HP vec2  dir  = dist > 0.001 ? toCenter / dist : vec2(0.0);

            // pixels -> texture coords for THIS canvas
            HP vec2 texel = 1.0 / love_ScreenSize.xy;

            // Narrow shell centred on the wavefront. Signed, normalised distance.
            HP number thickness = max(maxRadius * 0.10, 8.0);
            HP number d = (dist - explosionRadius) / thickness;
            HP number gauss = exp(-d * d * 2.5);     // bright at the shell, 0 elsewhere
            HP number lens  = -d * gauss;            // outward push ahead, inward pull behind

            // Energy fades as the shell grows; fade faster late in its life.
            HP number expand = clamp(explosionRadius / maxRadius, 0.0, 1.0);
            HP number decay  = (1.0 - expand) * (1.0 - expand);

            // Heat shimmer riding the shell: two detuned waves so it never repeats cleanly.
            HP number shimmer = sin(dist * 0.35 - time * 18.0)
                              + sin(dist * 0.17 + time * 11.0);

            HP number amp = distortionStrength * decay
                          * (lens + 0.12 * gauss * shimmer);

            HP vec2 disp = dir * amp * texel;

            // Chromatic refraction: the lens bends wavelengths by slightly different
            // amounts, so split the channels along the displacement direction.
            HP vec2 ca = dir * amp * 0.35 * texel;
            HP number r = Texel(tex, tc + disp + ca).r;
            HP number g = Texel(tex, tc + disp).g;
            vec4     bs = Texel(tex, tc + disp - ca);
            HP number b = bs.b;

            vec4 outc = vec4(r, g, b, bs.a);

            // Incandescent rim: hot, sharp at the shell, fading with the blast.
            HP number rim = gauss * decay;
            outc.rgb += vec3(1.0, 0.55, 0.22) * rim * 0.28;

            return outc * color;
        }
    ]])
    
    -- Explosion parameters
    explosion.params = {
        time = 0,
        explosionCenter = {400, 300},
        explosionRadius = 0,
        maxRadius = 150,
        distortionStrength = 22.0 -- peak refraction in screen pixels
    }
end

-- Create a new explosion at the specified position with the given type
function explosion.create(x, y, explosion_type)
    local anim
    if explosion_type == explosion.TYPES.ROCKET then
        anim = rocket_animation
    elseif explosion_type == explosion.TYPES.DEATH then
        anim = death_animation
    elseif explosion_type == explosion.TYPES.IMPLOSION then
        anim = NO_SPRITE
    else
        anim = rocket_animation -- Default to rocket animation
    end
    
    local wave = SHOCKWAVES[explosion_type] or SHOCKWAVES[explosion.TYPES.ROCKET]
    local inst = {
        x = x,
        y = y,
        type = explosion_type,
        animation = anim,
        currentTime = 0,
        completed = false,
        shockwaveRadius = 0,
        shockwaveMaxRadius = wave.radius,
        shockwaveDuration = wave.duration
    }
    table.insert(explosion.explosions, inst)
    return inst
end

function explosion.update(dt)
    explosion.current_time = explosion.current_time + dt
    
    for i = #explosion.explosions, 1, -1 do
        local e = explosion.explosions[i]
        e.currentTime = e.currentTime + dt
        
        -- Update shockwave radius. Ease-out: the front leaves fast (already
        -- visible on the first frame) and slows as it spreads and fades.
        if e.currentTime <= e.shockwaveDuration then
            local k = 1 - e.currentTime / e.shockwaveDuration
            e.shockwaveRadius = (1 - k * k) * e.shockwaveMaxRadius
        end
        
        if e.currentTime >= e.animation.duration and e.currentTime >= e.shockwaveDuration then
            e.completed = true
            table.remove(explosion.explosions, i)
        end
    end
end

function explosion.populate()
    for _, e in ipairs(explosion.explosions) do
        if not e.completed and #e.animation.quads > 0 then
            -- Add explosion sprite animation
            local frameNum = math.floor(e.currentTime / e.animation.duration * #e.animation.quads) + 1
            if frameNum <= #e.animation.quads then
                table.insert(dynamic_draw_list, {
                    sort_y = e.y + 140,
                    image_or_particles = e.animation.spriteSheet,
                    quad = e.animation.quads[frameNum],
                    x = e.x,
                    y = e.y,
                    scale_x = 1.5,
                    scale_y = 1.5,
                    offset_x = 50,
                    offset_y = 50,
                    color = {1, 1, 1, 1},
                    blend_mode = {"alpha"}
                })
            end
        end
    end
end

-- Apply shockwave distortion into scene_canvas using a temp canvas (avoids read/write hazard).
-- Call this BEFORE shader.pass() so the GI pass processes the distorted scene.
function explosion.applyShockwave()
    local shockwave_shader = explosion.SHADERS["shockwave"]
    if not shockwave_shader then return end

    -- Every live wave, newest first (each is two full-screen copies)
    local active = {}
    for i = #explosion.explosions, 1, -1 do
        local e = explosion.explosions[i]
        if not e.completed and e.currentTime <= e.shockwaveDuration then
            active[#active + 1] = e
            if #active == explosion.MAX_SHOCKWAVES then break end
        end
    end
    if #active == 0 then return end

    -- Lazily create (or recreate on resize) the intermediate canvas
    if not explosion.temp_canvas or
       explosion.temp_canvas:getWidth() ~= W or
       explosion.temp_canvas:getHeight() ~= H then
        explosion.temp_canvas = love.graphics.newCanvas(W, H, {format = "rgba8"})
    end

    -- Both copies must be exact: the default alpha blend multiplies RGB
    -- by alpha on every draw, and the current colour tints it, so the
    -- scene came back darker wherever it isn't fully opaque.
    local r, g, b, a = love.graphics.getColor()
    local blend_mode, alpha_mode = love.graphics.getBlendMode()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("replace", "premultiplied")

    for _, e in ipairs(active) do
        local screen_pos = camera.pos + vec2.new(e.x * camera.zoom, e.y * camera.zoom)
        shockwave_shader:send("time", explosion.current_time)
        shockwave_shader:send("explosionCenter", {screen_pos.x, screen_pos.y})
        shockwave_shader:send("explosionRadius", e.shockwaveRadius * camera.zoom)
        shockwave_shader:send("maxRadius", e.shockwaveMaxRadius * camera.zoom)
        shockwave_shader:send("distortionStrength", 22.0)

        -- Render distorted version of scene_canvas into temp_canvas
        love.graphics.setCanvas(explosion.temp_canvas)
        love.graphics.setShader(shockwave_shader)
        love.graphics.draw(scene_canvas)
        love.graphics.setShader()

        -- Write distorted result back into scene_canvas
        love.graphics.setCanvas(scene_canvas)
        love.graphics.draw(explosion.temp_canvas)
    end

    love.graphics.setBlendMode(blend_mode, alpha_mode)
    love.graphics.setColor(r, g, b, a)
    love.graphics.setCanvas(scene_canvas)
end

-- Legacy pass kept for low-graphics mode (draws scene_canvas to screen with shockwave overlay)
function explosion.pass()
    local shader = explosion.SHADERS["shockwave"]
    if shader then
        for _, e in ipairs(explosion.explosions) do
            if not e.completed and e.currentTime <= e.shockwaveDuration then
                local screen_pos = camera.pos + vec2.new(e.x * camera.zoom, e.y * camera.zoom)
                shader:send("time", explosion.current_time)
                shader:send("explosionCenter", {screen_pos.x, screen_pos.y})
                shader:send("explosionRadius", e.shockwaveRadius * camera.zoom)
                shader:send("maxRadius", e.shockwaveMaxRadius * camera.zoom)
                shader:send("distortionStrength", 22.0)
                love.graphics.setShader(shader)
                love.graphics.draw(scene_canvas)
                love.graphics.setShader()
                break
            end
        end
    end
end

-- Helper function to create animation
function createAnimation(image, width, height, duration, numFrames)
    local animation = {}
    animation.spriteSheet = image
    animation.quads = {}

    local totalPossibleFrames = math.floor(image:getWidth() / width) * math.floor(image:getHeight() / height)
    local framesToUse = numFrames or totalPossibleFrames
    framesToUse = math.min(framesToUse, totalPossibleFrames)

    local frameCount = 0

    for y = 0, image:getHeight() - height, height do
        for x = 0, image:getWidth() - width, width do
            table.insert(animation.quads, love.graphics.newQuad(x, y, width, height, image:getDimensions()))

            frameCount = frameCount + 1
            if frameCount >= framesToUse then
                break
            end
        end

        if frameCount >= framesToUse then
            break
        end
    end

    animation.duration = duration or 1
    animation.currentTime = 0

    return animation
end

return explosion