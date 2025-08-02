-- LÖVE 2D Instanced Sprite Rendering with Array Texture
-- Supports sprite sheets with directions (columns) and animation frames (rows)

local sprites = {}
local mesh
local instanceMesh
local arrayTexture
local maxInstances = 10
local uniformWidth = 256
local uniformHeight = 256

-- Centralized configuration: filename and number of directions
local imageFiles = {
    {filename = "apple.png", directions = 1}, -- Single sprite
    {filename = "doge.png", directions = 1}, -- Single sprite
    {filename = "enemy.png", directions = 1}, -- Single sprite
    {filename = "run.png", directions = 8}, -- 88 frames / 8 directions
    {filename = "walk.png", directions = 8} -- 288 frames / 8 directions
}

local spriteTypes = {} -- Populated dynamically: {name = {directions, framesPerDirection, totalFrames}}
local frameOffsets = {} -- Starting layer for each sprite type
local frameCounter = {} -- Total frames per sprite type
local spriteCount = 0

-- Calculate cumulative frame offsets and populate spriteTypes
local function calculateFrameOffsets(framesPerImageList)
    local offset = 0
    for i, fileInfo in ipairs(imageFiles) do
        local spriteName = fileInfo.filename:match("^(.-)%.png$") -- Extract name without .png
        spriteTypes[spriteName] = {
            directions = fileInfo.directions,
            framesPerDirection = framesPerImageList[i] / fileInfo.directions,
            totalFrames = framesPerImageList[i]
        }
        frameOffsets[spriteName] = offset
        frameCounter[i] = framesPerImageList[i]
        offset = offset + framesPerImageList[i]
    end
    spriteCount = offset
end

local function stripey(x, y, r, g, b, a)
    if x > 256 or y > 256 then
        return 0, 0, 0, 0
    end
    r = math.min(r * math.sin(x * 100) * 2, 1)
    g = math.min(g * math.cos(x * 150) * 2, 1)
    b = math.min(b * math.sin(x * 50) * 2, 1)
    return r, g, b, a
end

function love.load()
    local imageDataList = {}
    local framesPerImageList = {}
    for i, fileInfo in ipairs(imageFiles) do
        local filename = fileInfo.filename
        local directions = fileInfo.directions
        local originalImageData = love.image.newImageData(filename)
        local framesPerImage = 0
        if originalImageData then
            local spriteWidth = uniformWidth
            local spriteHeight = uniformHeight
            local paddingX, paddingY = 0, 0
            local spritesX = directions -- Columns = directions
            local spritesY = math.floor(originalImageData:getHeight() / (spriteHeight + paddingY)) -- Rows = frames per direction

            for sy = 0, spritesY - 1 do -- Rows (animation frames)
                for sx = 0, spritesX - 1 do -- Columns (directions)
                    local uniformImageData = love.image.newImageData(spriteWidth, spriteHeight)
                    local srcXStart = sx * (spriteWidth + paddingX)
                    local srcYStart = sy * (spriteHeight + paddingY)

                    for y = 0, spriteHeight - 1 do
                        for x = 0, spriteWidth - 1 do
                            local srcX, srcY = srcXStart + x, srcYStart + y
                            if srcX < originalImageData:getWidth() and srcY < originalImageData:getHeight() then
                                uniformImageData:setPixel(x, y, originalImageData:getPixel(srcX, srcY))
                            else
                                uniformImageData:setPixel(x, y, 0, 0, 0, 0)
                            end
                        end
                    end
                    table.insert(imageDataList, uniformImageData)
                    framesPerImage = framesPerImage + 1
                end
            end
        end
        print("Frames for " .. filename .. ": " .. framesPerImage)
        framesPerImageList[i] = framesPerImage
    end

    calculateFrameOffsets(framesPerImageList)
    arrayTexture = love.graphics.newArrayImage(imageDataList)

    -- Create mesh for a single quad
    local size = 128
    local vertices = {
        {-size, -size, 0, 0},
        {size, -size, 1, 0},
        {size, size, 1, 1},
        {-size, size, 0, 1}
    }
    
    mesh = love.graphics.newMesh(vertices, "fan", "stream")
    mesh:setTexture(arrayTexture)
    
    -- Create instance mesh
    local instanceFormat = {
        {"InstanceMatrix1", "float", 4},
        {"InstanceMatrix2", "float", 4},
        {"InstanceMatrix3", "float", 4},
        {"InstanceMatrix4", "float", 4},
        {"InstanceLayer", "float", 1}
    }
    
    local emptyInstanceData = {}
    for i = 1, maxInstances * 17 do
        emptyInstanceData[i] = {0}
    end
    
    instanceMesh = love.graphics.newMesh(instanceFormat, emptyInstanceData, nil, "stream")
    
    mesh:attachAttribute("InstanceMatrix1", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceMatrix2", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceMatrix3", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceMatrix4", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceLayer", instanceMesh, "perinstance")
    
    -- Initialize sprites
    for i = 1, maxInstances do
        local fileInfo = imageFiles[math.min(i, #imageFiles)]
        local spriteType = fileInfo.filename:match("^(.-)%.png$")
        sprites[i] = {
            x = love.math.random(-size, love.graphics.getWidth() + size),
            y = love.math.random(-size, love.graphics.getHeight() + size),
            rotation = 0,
            scale = 1,
            spriteType = spriteType,
            direction = 0, -- 0-based index for direction (column)
            frameIndex = 0, -- 0-based index for frame (row)
            layer = frameOffsets[spriteType], -- Computed in update
            vx = 0,
            vy = 0,
            angular_velocity = 0
        }
    end
    
    -- Shader (unchanged)
    local shaderCode = [[
        #define MAX_LIGHTS 5
        
        const int numLights = 3;
        const vec2 lightPositions[MAX_LIGHTS] = vec2[MAX_LIGHTS](
            vec2(400.0, 300.0),
            vec2(200.0, 150.0), 
            vec2(600.0, 450.0),
            vec2(0.0, 0.0),
            vec2(0.0, 0.0)
        );
        const float lightIntensities[MAX_LIGHTS] = float[MAX_LIGHTS](
            1.0, 0.8, 0.6, 0.0, 0.0
        );
        const float lightRanges[MAX_LIGHTS] = float[MAX_LIGHTS](
            2000.0, 150.0, 250.0, 0.0, 0.0
        );
        
        varying float VaryingLayer;
        varying vec2 pos;
        
        #ifdef VERTEX
        attribute vec4 InstanceMatrix1;
        attribute vec4 InstanceMatrix2; 
        attribute vec4 InstanceMatrix3;
        attribute vec4 InstanceMatrix4;
        attribute float InstanceLayer;
        
        vec4 position(mat4 transform_projection, vec4 vertex_position) {
            VaryingLayer = InstanceLayer;
            
            mat4 instance_matrix = mat4(
                InstanceMatrix1,
                InstanceMatrix2,
                InstanceMatrix3, 
                InstanceMatrix4
            );
            
            vec4 worldPos = instance_matrix * vertex_position;
            pos = worldPos.xy;
            
            return transform_projection * worldPos;
        }
        #endif
        
        #ifdef PIXEL
        uniform ArrayImage MainTex;
        
        void effect() {
            vec4 texColor = Texel(MainTex, vec3(VaryingTexCoord.xy, VaryingLayer));
            
            float totalLight = 0.0;
            for (int i = 0; i < MAX_LIGHTS; i++) {
                if (i >= numLights) {
                    break;
                }
                float distance = length(lightPositions[i] - pos);
                float attenuation = 1.0 - clamp(distance / lightRanges[i], 0.0, 1.0);
                totalLight += attenuation * lightIntensities[i];
            }
            
            totalLight = clamp(totalLight, 0.0, 1.0);
            vec3 finalColor = mix(vec3(0.0), texColor.rgb, totalLight);
            
            love_Canvases[0] = vec4(finalColor, texColor.a);
        }
        #endif
    ]]
    
    shader = love.graphics.newShader(shaderCode)
    
    print("Loaded " .. spriteCount .. " sprites into array texture")
    print("Max instances: " .. maxInstances)
end

local t = 0
local animationSpeed = 1/10 -- 10 FPS animation

-- Calculate layer from direction and frame
local function getLayer(sprite)
    local spriteType = sprite.spriteType
    local offset = frameOffsets[spriteType]
    local directions = spriteTypes[spriteType].directions
    return offset + sprite.frameIndex * directions + sprite.direction
end

function love.update(dt)
    -- Update first sprite to follow mouse and respond to direction input
    sprites[1].x, sprites[1].y = love.mouse.getPosition()
    sprites[1].spriteType = "run"
    
    -- Handle direction input for first sprite
    if love.keyboard.isDown("left") then
        sprites[1].direction = math.max(0, sprites[1].direction - 1)
    elseif love.keyboard.isDown("right") then
        sprites[1].direction = math.min(spriteTypes[sprites[1].spriteType].directions - 1, sprites[1].direction + 1)
    end

    -- Update animation timer
    t = t + dt
    if t >= animationSpeed then
        for i = 1, maxInstances do
            local sprite = sprites[i]
            local spriteType = sprite.spriteType
            sprite.frameIndex = (sprite.frameIndex + 1) % spriteTypes[spriteType].framesPerDirection
            sprite.layer = getLayer(sprite)
            
            -- Randomly change direction for non-player sprites
            if i > 1 and love.math.random() < 0.02 then
                sprite.direction = love.math.random(0, spriteTypes[spriteType].directions - 1)
            end
        end
        t = t - animationSpeed
    end

    -- Update sprite positions
    for i = 2, maxInstances do
        local sprite = sprites[i]
        sprite.x = sprite.x + sprite.vx * dt
        sprite.y = sprite.y + sprite.vy * dt
        sprite.rotation = sprite.rotation + sprite.angular_velocity * dt
        sprite.layer = getLayer(sprite)
    end
    
    -- Create sorted list of sprite indices by Y position
    local sortedIndices = {}
    for i = 1, maxInstances do
        sortedIndices[i] = i
    end
    
    table.sort(sortedIndices, function(a, b)
        return sprites[a].y < sprites[b].y
    end)
    
    -- Build instance data
    local instanceData = {}
    for i = 1, maxInstances do
        local spriteIndex = sortedIndices[i]
        local sprite = sprites[spriteIndex]
        
        local cos_r = math.cos(sprite.rotation)
        local sin_r = math.sin(sprite.rotation)
        local scale = sprite.scale
        
        local matrix = {
            cos_r * scale, sin_r * scale, 0, 0,
            -sin_r * scale, cos_r * scale, 0, 0,
            0, 0, 1, 0,
            sprite.x, sprite.y, 0, 1
        }
        
        local instanceRow = {}
        for j = 1, 4 do instanceRow[j] = matrix[j] end
        for j = 1, 4 do instanceRow[4+j] = matrix[4+j] end
        for j = 1, 4 do instanceRow[8+j] = matrix[8+j] end
        for j = 1, 4 do instanceRow[12+j] = matrix[12+j] end
        instanceRow[17] = sprite.layer
        
        instanceData[i] = instanceRow
    end
    
    instanceMesh:setVertices(instanceData)
end

function love.draw()
    love.graphics.setShader(shader)
    love.graphics.drawInstanced(mesh, maxInstances)
    love.graphics.setShader()

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Sprites: " .. maxInstances, 10, 10)
    love.graphics.print("Y-sorted instances (back to front)", 10, 30)
    love.graphics.print("Press SPACE to randomize", 10, 50)
    love.graphics.print("Press ESC to quit", 10, 70)
    love.graphics.print("Use LEFT/RIGHT arrows for direction", 10, 90)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "space" then
        for i = 1, maxInstances do
            local fileInfo = imageFiles[math.min(i, #imageFiles)]
            local spriteType = fileInfo.filename:match("^(.-)%.png$")
            sprites[i].x = love.math.random(0, love.graphics.getWidth())
            sprites[i].y = love.math.random(0, love.graphics.getHeight())
            sprites[i].rotation = love.math.random() * math.pi * 2
            sprites[i].vx = love.math.random(-100, 100)
            sprites[i].vy = love.math.random(-100, 100)
            sprites[i].spriteType = spriteType
            sprites[i].direction = love.math.random(0, spriteTypes[spriteType].directions - 1)
            sprites[i].frameIndex = 0
            sprites[i].layer = getLayer(sprites[i])
        end
    end
end