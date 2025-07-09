-- characterAnimator.lua
-- Manages character animations from sprite sheets with 8-directional support

local characterAnimator = {}

-- Configuration
characterAnimator.directions = 8 -- Number of directional angles in the sprite sheet
characterAnimator.frameRate = 25 -- Frames per second for animation playback
characterAnimator.spriteSheetPath = "gfx/watchmanOfDoom/idle.png" -- Placeholder path, update with actual sprite sheet path

-- Internal state
characterAnimator.spriteSheet = nil
characterAnimator.frameWidth = 0
characterAnimator.frameHeight = 0
characterAnimator.framesPerDirection = 0
characterAnimator.columns = 0
characterAnimator.rows = 0
characterAnimator.currentDirection = 1 -- 1 to 8, representing each direction
characterAnimator.currentFrame = 1 -- Current frame in the animation sequence
characterAnimator.timeAccumulator = 0 -- For frame timing

-- Initialize the animator with a sprite sheet
function characterAnimator.init(spriteSheetPath, frameWidth, frameHeight, framesPerDirection)
    if spriteSheetPath then
        characterAnimator.spriteSheetPath = spriteSheetPath
    end
    
    -- Load sprite sheet (assuming a function or library to load images in your game engine)
    characterAnimator.spriteSheet = love.graphics.newImage(characterAnimator.spriteSheetPath)
    if not characterAnimator.spriteSheet then
        print("Error: Could not load sprite sheet at " .. characterAnimator.spriteSheetPath)
        return false
    
    end
    
    -- Set dimensions
    characterAnimator.frameWidth = frameWidth or (characterAnimator.spriteSheet:getWidth() / characterAnimator.directions)
    characterAnimator.frameHeight = frameHeight or characterAnimator.frameWidth
    characterAnimator.framesPerDirection = framesPerDirection or (characterAnimator.spriteSheet:getHeight() / characterAnimator.frameHeight)
    characterAnimator.columns = characterAnimator.directions
    characterAnimator.rows = characterAnimator.framesPerDirection
    
    -- Reset animation state
    characterAnimator.currentDirection = 1
    characterAnimator.currentFrame = 1
    characterAnimator.timeAccumulator = 0
    
    print("Character animator initialized with sprite sheet: " .. characterAnimator.spriteSheetPath)
    return true
end

-- Update the animation state based on delta time
function characterAnimator.update(dt)
    if not characterAnimator.spriteSheet then return end
    
    characterAnimator.timeAccumulator = characterAnimator.timeAccumulator + dt
    local frameInterval = 1 / characterAnimator.frameRate
    
    if characterAnimator.timeAccumulator >= frameInterval then
        characterAnimator.currentFrame = characterAnimator.currentFrame + 1
        if characterAnimator.currentFrame > characterAnimator.framesPerDirection then
            characterAnimator.currentFrame = 1 -- Loop back to the first frame of the direction
        end
        characterAnimator.timeAccumulator = 0
    end
end

-- Set the direction of the character (1 to 8)
function characterAnimator.setDirection(direction)
    if direction >= 1 and direction <= characterAnimator.directions then
        characterAnimator.currentDirection = direction
    else
        print("Invalid direction: " .. tostring(direction) .. ". Direction must be between 1 and " .. characterAnimator.directions , direction)
    end
end

-- Draw the current frame of the animation at the specified position
function characterAnimator.populate(x, y, scale, rotation)
    if not characterAnimator.spriteSheet then return end
    
    scale = scale or 1
    rotation = rotation or 0
    
    -- Calculate the source rectangle for the current frame
    local srcX = (characterAnimator.currentDirection - 1) * characterAnimator.frameWidth
    
    local srcY = (characterAnimator.framesPerDirection - characterAnimator.currentFrame) * characterAnimator.frameHeight -- Invert Y for correct orientation
    
    -- Create a quad for the current frame
    local quad = love.graphics.newQuad(srcX, srcY, characterAnimator.frameWidth, characterAnimator.frameHeight, 
                                       characterAnimator.spriteSheet:getWidth(), characterAnimator.spriteSheet:getHeight())
    
    -- -- Draw the current frame
    -- love.graphics.draw(characterAnimator.spriteSheet, quad, x, y, rotation, scale, scale, 
    --                    characterAnimator.frameWidth / 2, characterAnimator.frameHeight / 2)





    --  if not characterAnimator.spriteSheet then return end
    
    -- scale = scale or 1
    -- rotation = rotation or 0
    -- layer = layer or 1 -- Default layer for sorting
    
    -- -- Calculate the source rectangle for the current frame
    -- local srcX = (characterAnimator.currentDirection - 1) * characterAnimator.frameWidth
    -- local srcY = (characterAnimator.framesPerDirection - characterAnimator.currentFrame) * characterAnimator.frameHeight -- Invert Y for correct orientation
    
    -- -- Create a quad for the current frame
    -- local quad = love.graphics.newQuad(srcX, srcY, characterAnimator.frameWidth, characterAnimator.frameHeight, 
    --                                    characterAnimator.spriteSheet:getWidth(), characterAnimator.spriteSheet:getHeight())
    

    -- for i = 1, #coin_bods do
        -- local cx, cy = 0,0
        table.insert(dynamic_draw_list, {
            sort_y = 200,
            image_or_particles = characterAnimator.spriteSheet,
            quad = quad,
            x = 0,
            y = 0,
            rotation = 0,
            scale_x = scale,
            scale_y = scale,
            offset_x = 0,
            offset_y = 20,
            color = { 1, 1, 1, 1 },
            blend_mode = { "alpha" },
            source_object_type = "coin"
        })
    -- end

end



-- Example usage for player, enemy, or NPC
function characterAnimator.createCharacter(spriteSheetPath, frameWidth, frameHeight, framesPerDirection)
    local char = {}
    char.animator = {}
    
    -- Copy animator functions to character instance
    for k, v in pairs(characterAnimator) do
        if type(v) == "function" then
            char.animator[k] = v
        end
    end
    
    -- Initialize with specific sprite sheet if provided
    char.animator.init(spriteSheetPath or characterAnimator.spriteSheetPath, frameWidth, frameHeight, framesPerDirection)
    
    -- Additional character-specific properties can be added here
    char.x = 0
    char.y = 0
    char.direction = 1
    char.scale = 1
    char.rotation = 0
    
    -- Update function for character
    function char.update(dt)
        char.animator.update(dt)
        char.animator.setDirection(char.direction)
    end
    
    -- Draw function for character
    function char.draw()
        char.animator.draw(char.x, char.y, char.scale, char.rotation)
    end
    
    return char
end

return characterAnimator
