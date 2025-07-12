-- characterAnimator.lua
-- Manages character animations from sprite sheets with 8-directional support

local characterAnimator = {}

-- Default configuration
local DEFAULT_CONFIG = {
    directions = 8,
    frameRate = 20
}

-- Create a new animator instance
local function createInstance(spriteSheetPaths, frameWidth, frameHeight)
    local instance = {}
    
    -- Configuration
    instance.config = {}
    for k, v in pairs(DEFAULT_CONFIG) do
        instance.config[k] = v
    end
    
    -- Handle single sprite sheet or table of sprite sheets
    local paths = {}
    if type(spriteSheetPaths) == "string" then
        paths = {spriteSheetPaths}
    else
        paths = spriteSheetPaths
    end
    
    -- Load all sprite sheets
    instance.states = {}
    for i, path in ipairs(paths) do
        local spriteSheet = love.graphics.newImage(path)
        if spriteSheet then
            local calcFrameWidth = frameWidth or (spriteSheet:getWidth() / instance.config.directions)
            local calcFrameHeight = frameHeight or calcFrameWidth
            local calcFramesPerDirection = spriteSheet:getHeight() / calcFrameHeight
            
            instance.states[i] = {
                spriteSheet = spriteSheet,
                frameWidth = calcFrameWidth,
                frameHeight = calcFrameHeight,
                framesPerDirection = calcFramesPerDirection
            }
        end
    end
    
    -- Set initial state
    instance.currentState = 1
    instance.currentDirection = 1
    instance.currentFrame = 1
    instance.timeAccumulator = 0
    
    function instance.update(dt)
        local stateData = instance.states[instance.currentState]
        if not stateData then return end
        
        instance.timeAccumulator = instance.timeAccumulator + dt
        local frameInterval = 1 / instance.config.frameRate
        
        if instance.timeAccumulator >= frameInterval then
            instance.currentFrame = instance.currentFrame + 1
            if instance.currentFrame > stateData.framesPerDirection then
                instance.currentFrame = 1
            end
            instance.timeAccumulator = 0
        end
    end
    
    function instance.setDirection(direction)
        if direction >= 1 and direction <= instance.config.directions then
            instance.currentDirection = direction
        end
    end
    
    function instance.setState(stateNumber)
        if instance.states[stateNumber] then
            instance.currentState = stateNumber
            -- instance.currentFrame = 1
            -- instance.timeAccumulator = 0
        end
    end
    function instance.getState()
        return instance.currentState
    end
    
    function instance.populate(x, y, scale, rotation, layer)
        local stateData = instance.states[instance.currentState]
        if not stateData then return end
        
        x = x or 0
        y = y or 0
        scale = scale or 1
        rotation = rotation or 0
        layer = layer or 200
        
        local srcX = (instance.currentDirection - 1) * stateData.frameWidth
        local srcY = (stateData.framesPerDirection - instance.currentFrame) * stateData.frameHeight
        
        local quad = love.graphics.newQuad(
            srcX, srcY, 
            stateData.frameWidth, stateData.frameHeight,
            stateData.spriteSheet:getWidth(), stateData.spriteSheet:getHeight()
        )
        
        table.insert(dynamic_draw_list, {
            sort_y = layer,
            image_or_particles = stateData.spriteSheet,
            quad = quad,
            x = x,
            y = y,
            rotation = rotation,
            scale_x = scale,
            scale_y = scale,
            offset_x = 0,
            offset_y = 0,
            color = { 1, 1, 1, 1 },
            blend_mode = { "alpha" },
            source_object_type = "character_animator"
        })
    end
    
    return instance
end

-- Main init function
function characterAnimator.init(spriteSheetPaths, frameWidth, frameHeight)
    return createInstance(spriteSheetPaths, frameWidth, frameHeight)
end

return characterAnimator