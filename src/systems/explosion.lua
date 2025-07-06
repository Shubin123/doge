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
    -- Load explosion spritesheet
    explosion_image = love.graphics.newImage("gfx/explosions/spritesheet/round_explosion/spritesheet/spritesheet.png")
    -- Create animations for different explosion types
    -- Assuming the spritesheet has frames of 128x128 pixels based on typical explosion sprite sizes
    -- Rocket explosion: shorter, more intense (16 frames at 15 FPS = ~1.067s)
    rocket_animation = createAnimation(explosion_image, 100, 100, 0.5, 60)
    -- Death explosion: slightly different animation if needed (16 frames for now)
    death_animation = createAnimation(explosion_image, 128, 128, 1.067, 16)
    
    -- Load shockwave shader
    shockwave_shader = love.graphics.newShader("shaders/shockwave.frag")
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
        shockwaveMaxRadius = 200, -- Max radius for shockwave effect
        shockwaveDuration = 1.5   -- Duration for shockwave to fully expand
    }
    table.insert(explosion.explosions, inst)
    return inst
end

function explosion.update(dt)
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
                    scale_x = 1.5, -- Scale for visibility
                    scale_y = 1.5,
                    offset_x = 50, -- Center for 100x100 frame
                    offset_y = 50,
                    color = {1, 1, 1, 1},
                    blend_mode = {"alpha"}
                })
            end
        end
    end
end

-- Helper function to create animation (copied from main.lua for completeness)
function createAnimation(image, width, height, duration, numFrames)
    local animation = {}
    animation.spriteSheet = image
    animation.quads = {}

    -- Calculate the total possible frames in the sprite sheet
    local totalPossibleFrames = math.floor(image:getWidth() / width) * math.floor(image:getHeight() / height)

    -- If numFrames is not provided, use all possible frames
    local framesToUse = numFrames or totalPossibleFrames

    -- Make sure we don't try to use more frames than are available
    framesToUse = math.min(framesToUse, totalPossibleFrames)

    local frameCount = 0

    for y = 0, image:getHeight() - height, height do
        for x = 0, image:getWidth() - width, width do
            table.insert(animation.quads, love.graphics.newQuad(x, y, width, height, image:getDimensions()))

            frameCount = frameCount + 1
            if frameCount >= framesToUse then
                break -- Stop adding frames once we've reached the desired number
            end
        end

        if frameCount >= framesToUse then
            break -- Also break from the outer loop
        end
    end

    animation.duration = duration or 1
    animation.currentTime = 0

    return animation
end

return explosion
