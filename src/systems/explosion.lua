local explosion = {}
explosion.explosions = {}

-- Explosion types
explosion.TYPES = {
    ROCKET = "rocket",
    DEATH = "death"
}

local explosion_image
local rocket_animation
local death_animation

function explosion.load()
    -- Initialize like portal.lua
    explosion.SHADERS = {}
    explosion.current_time = 0
    
    -- Load explosion spritesheet
    explosion_image = love.graphics.newImage("gfx/explosions/spritesheet/round_explosion/spritesheet/spritesheet.png")
    
    -- Create animations for different explosion types
    rocket_animation = createAnimation(explosion_image, 100, 100, 0.5, 60)
    death_animation = createAnimation(explosion_image, 128, 128, 1.067, 16)
    
    -- Create shockwave distortion shader like water.lua
    explosion.SHADERS["shockwave"] = love.graphics.newShader([[
        
        #if defined(VERTEX) || __VERSION__ > 100 || defined(GL_FRAGMENT_PRECISION_HIGH)
        #define MY_HIGHP_OR_MEDIUMP highp
        #else
        #define MY_HIGHP_OR_MEDIUMP mediump
        #endif

        extern MY_HIGHP_OR_MEDIUMP number time;
        extern MY_HIGHP_OR_MEDIUMP vec2 explosionCenter;
        extern MY_HIGHP_OR_MEDIUMP number explosionRadius;
        extern MY_HIGHP_OR_MEDIUMP number maxRadius;
        extern MY_HIGHP_OR_MEDIUMP number distortionStrength;
        
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            // Calculate distance from explosion center
            MY_HIGHP_OR_MEDIUMP number dist = distance(sc, explosionCenter);
            
            // Check if we're in the shockwave area
            MY_HIGHP_OR_MEDIUMP number waveFront = explosionRadius;
            MY_HIGHP_OR_MEDIUMP number waveThickness = maxRadius * 0.55;
            
            if (dist < waveFront + waveThickness && dist > waveFront - waveThickness) {
                // Calculate distortion based on distance from wave front
                MY_HIGHP_OR_MEDIUMP number distFromWave = abs(dist - waveFront);
                MY_HIGHP_OR_MEDIUMP number distortionFactor = 1.0 - (distFromWave / waveThickness);
                distortionFactor = distortionFactor * distortionFactor; // Square for sharper falloff
                
                // Calculate direction from explosion center
                MY_HIGHP_OR_MEDIUMP vec2 direction = normalize(sc - explosionCenter);
                
                // Add some ripple effects
                MY_HIGHP_OR_MEDIUMP number ripple = sin(dist * 0.1 + time * 5.0) * 0.9;
                
                // Apply radial distortion to texture coordinates
                MY_HIGHP_OR_MEDIUMP vec2 distortedTC = tc + direction * distortionFactor * distortionStrength * (1.0 + ripple);
                
                // Sample with distorted coordinates
                //return Texel(tex, distortedTC) * mix(color, vec4(1,0,0,1),1);
                return Texel(tex, distortedTC) * color;
            } else {
                // Outside shockwave area, return normal texture
                //return Texel(tex, tc) * mix(color, vec4(1,0,0,1),1);
                return Texel(tex, tc) * color;
            }
        }
    ]])
    
    -- Explosion parameters
    explosion.params = {
        time = 0,
        explosionCenter = {400, 300},
        explosionRadius = 0,
        maxRadius = 150,
        distortionStrength = 0.02
    }
end

-- Create a new explosion at the specified position with the given type
function explosion.create(x, y, explosion_type)
    local anim
    if explosion_type == explosion.TYPES.ROCKET then
        anim = rocket_animation
    elseif explosion_type == explosion.TYPES.DEATH then
        anim = death_animation
    else
        anim = rocket_animation -- Default to rocket animation
    end
    
    local inst = {
        x = x,
        y = y,
        type = explosion_type,
        animation = anim,
        currentTime = 0,
        completed = false,
        shockwaveRadius = 0,
        shockwaveMaxRadius = explosion_type == explosion.TYPES.DEATH and 500 or 350,
        shockwaveDuration = 4
    }
    table.insert(explosion.explosions, inst)
    return inst
end

function explosion.update(dt)
    explosion.current_time = explosion.current_time + dt
    
    for i = #explosion.explosions, 1, -1 do
        local e = explosion.explosions[i]
        e.currentTime = e.currentTime + dt
        
        -- Update shockwave radius
        if e.currentTime <= e.shockwaveDuration then
            e.shockwaveRadius = (e.currentTime / e.shockwaveDuration) * e.shockwaveMaxRadius
        end
        
        if e.currentTime >= e.animation.duration and e.currentTime >= e.shockwaveDuration then
            e.completed = true
            table.remove(explosion.explosions, i)
        end
    end
end

function explosion.populate()
    for _, e in ipairs(explosion.explosions) do
        if not e.completed then
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

    for _, e in ipairs(explosion.explosions) do
        if not e.completed and e.currentTime <= e.shockwaveDuration then
            -- Lazily create (or recreate on resize) the intermediate canvas
            if not explosion.temp_canvas or
               explosion.temp_canvas:getWidth() ~= W or
               explosion.temp_canvas:getHeight() ~= H then
                explosion.temp_canvas = love.graphics.newCanvas(W, H, {format = "rgba4"})
            end

            local screen_pos = camera.pos + vec2.new(e.x * camera.zoom, e.y * camera.zoom)
            shockwave_shader:send("time", explosion.current_time)
            shockwave_shader:send("explosionCenter", {screen_pos.x, screen_pos.y})
            shockwave_shader:send("explosionRadius", e.shockwaveRadius * camera.zoom)
            shockwave_shader:send("maxRadius", e.shockwaveMaxRadius * camera.zoom)
            shockwave_shader:send("distortionStrength", 0.5)

            -- Render distorted version of scene_canvas into temp_canvas
            love.graphics.setCanvas(explosion.temp_canvas)
            love.graphics.clear(0, 0, 0, 0)
            love.graphics.setShader(shockwave_shader)
            love.graphics.draw(scene_canvas)
            love.graphics.setShader()

            -- Write distorted result back into scene_canvas
            love.graphics.setCanvas(scene_canvas)
            love.graphics.clear(0, 0, 0, 0)
            love.graphics.draw(explosion.temp_canvas)

            break -- only apply one explosion per frame
        end
    end

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
                shader:send("distortionStrength", 0.5)
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