-- block.lua - A superclass for game objects with 360-degree sprite rotation and physics collision
local block = {}
block.__index = block

-- Constructor for a new block instance
function block.new(spriteSheetPath, frameWidth, frameHeight, duration, numFrames, scale, world, x, y)
    local self = setmetatable({}, block)
    self.spriteSheet = love.graphics.newImage(spriteSheetPath)
    self.scale = scale or 1
    self.width, self.height = self.spriteSheet:getDimensions()
    self.animation = self:newAnimation(frameWidth, frameHeight, duration or 1, numFrames)
    self.inUse = false
    -- Physics setup
    if world then
        self.body = love.physics.newBody(world, x or 0, y or 0, "dynamic")
        self.shape = love.physics.newRectangleShape(frameWidth * self.scale * 0.5, frameHeight * self.scale * 0.5)
        self.fixture = love.physics.newFixture(self.body, self.shape)
        self.fixture:setGroupIndex(-2) -- Default group to avoid initial collisions
    end
    return self
end

-- Function to create a new animation from a sprite sheet
function block:newAnimation(width, height, duration, numFrames)
    local animation = {}
    animation.spriteSheet = self.spriteSheet
    animation.quads = {}
    local totalPossibleFrames = math.floor(self.spriteSheet:getWidth() / width) * math.floor(self.spriteSheet:getHeight() / height)
    local framesToUse = numFrames or totalPossibleFrames
    framesToUse = math.min(framesToUse, totalPossibleFrames)
    
    local frameCount = 0
    for y = 0, self.spriteSheet:getHeight() - height, height do
        for x = 0, self.spriteSheet:getWidth() - width, width do
            table.insert(animation.quads, love.graphics.newQuad(x, y, width, height, self.spriteSheet:getDimensions()))
            frameCount = frameCount + 1
            if frameCount >= framesToUse then
                break
            end
        end
        if frameCount >= framesToUse then
            break
        end
    end
    
    animation.duration = duration
    animation.currentTime = 0
    return animation
end

-- Function to calculate sprite frame based on velocity/heading
function block:getSpriteForHeading(vx, vy, maxFrames, angleOffset, mod, invert)
    local angle = 0
    if math.abs(vx) > 0.1 or math.abs(vy) > 0.1 then
        angle = math.atan2(vy, -vx)
        if invert then
            angle = math.atan2(-vy, vx)
        end
    end
    
    local normalizedAngle = (angle % (2 * math.pi) + 2 * math.pi) % (2 * math.pi)
    local degrees = math.deg(normalizedAngle) + 1
    local adjustedDegrees = (degrees + (angleOffset or 155)) % (mod or 400)
    local spriteFrame = math.floor(adjustedDegrees) + 1
    
    -- Ensure frame is within bounds
    maxFrames = maxFrames or #self.animation.quads
    spriteFrame = math.max(1, math.min(maxFrames, spriteFrame))
    return spriteFrame
end

-- function command.getSpriteForHeading(vx, vy)
--     local angle = 0
--     if math.abs(vx) > 0.1 or math.abs(vy) > 0.1 then
--         angle = math.atan2(vy, -vx)
--     end
--     local normalizedAngle = (angle % (2 * math.pi) + 2 * math.pi) % (2 * math.pi)
--     local degrees = math.deg(normalizedAngle) + 1
--     local adjustedDegrees = (degrees + 155) % 400 
--     local spriteFrame = math.floor(adjustedDegrees) + 1
--     spriteFrame = math.max(1, math.min(100, spriteFrame))
--     return spriteFrame
-- end

-- Function to add sprite to dynamic draw list for rendering
function block:addToDrawList(drawList, x, y, vx, vy, sortYOffset, offsetX, offsetY, maxFrames, angleOffset, mod, invert)
    local spriteNum = self:getSpriteForHeading(vx, vy,maxFrames,angleOffset,mod,invert)
    table.insert(drawList, {
        sort_y = y + (sortYOffset or 0),
        image_or_particles = self.animation.spriteSheet,
        quad = self.animation.quads[spriteNum],
        x = x,
        y = y,
        rotation = 0,
        scale_x = self.scale,
        scale_y = self.scale,
        offset_x = offsetX or (self.width / 2),
        offset_y = offsetY or (self.height / 2),
        color = { 1, 1, 1, 1 },
        blend_mode = { "alpha" },
        source_object_type = "block"
    })
end

-- Function to update physics properties
function block:updatePhysics(playerBody, multiplayer)
    if not self.body then return end
    
    local cx, cy = self.body:getX(), self.body:getY()
    local relVel = {x = 0, y = 0}
    
    if multiplayer == 1 or not multiplayer then -- Only host updates physics positions
        if self.inUse and playerBody then
            self.body:setPosition(playerBody:getPosition())
            relVel.x, relVel.y = playerBody:getLinearVelocity()
            self.fixture:setGroupIndex(-1) -- Adjust collision group when in use
        else
            relVel.x, relVel.y = self.body:getLinearVelocity()
            self.fixture:setGroupIndex(-2) -- Different group when not in use
        end
    end
    return cx, cy, relVel
end

-- Function to set whether the block is in use
function block:setInUse(state, playerId)
    self.inUse = state
    self.controllingPlayer = playerId or ""
end

return block
