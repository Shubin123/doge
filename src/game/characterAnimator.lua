-- Manages character animations from sprite sheets with 8-directional support using instanced rendering
-- Optimized with texture packing to utilize 2048x2048 layers efficiently

local characterAnimator = {}
local DEFAULT_CONFIG = {
    directions = 8,
    frameRate = 20
}

characterAnimator.instanceCount = var.num_enemies -- for now just test with enemies
local uniformWidth = 128
local uniformHeight = 128
local LAYER_SIZE = 2048  -- Target layer size for packing
local SPRITES_PER_ROW = math.floor(LAYER_SIZE / uniformWidth)  -- 16 sprites per row
local SPRITES_PER_LAYER = SPRITES_PER_ROW * SPRITES_PER_ROW    -- 256 sprites per layer

local mesh, instanceMesh, arrayTexture, shader
local spriteTypes = {}  -- {name = {directions, framesPerDirection, totalFrames}}
local frameOffsets = {} -- Starting frame index for each sprite type
local spriteCount = 0
local instances = {}    -- Store all instances for populate
local spriteLocationMap = {} -- Maps global sprite index to {layer, u, v} coordinates

-- Calculate cumulative frame offsets and create location map
local function calculateFrameOffsets(framesPerImageList, imageFiles)
    local offset = 0
    for i, filename in ipairs(imageFiles) do
        local spriteName = filename:match("^(.-)%.png$")
        local originalImageData = love.image.newImageData(filename)
        local directions = math.floor(originalImageData:getWidth() / uniformWidth)
        spriteTypes[i] = {
            directions = directions,
            framesPerDirection = framesPerImageList[i] / directions,
            totalFrames = framesPerImageList[i]
        }
        frameOffsets[i] = offset
        
        -- Create location map for this sprite type's frames
        for frameIdx = 0, framesPerImageList[i] - 1 do
            local globalIndex = offset + frameIdx
            local layer = math.floor(globalIndex / SPRITES_PER_LAYER)
            local indexInLayer = globalIndex % SPRITES_PER_LAYER
            local row = math.floor(indexInLayer / SPRITES_PER_ROW)
            local col = indexInLayer % SPRITES_PER_ROW
            
            spriteLocationMap[globalIndex] = {
                layer = layer,
                u = col / SPRITES_PER_ROW,      -- UV coordinate (0-1)
                v = row / SPRITES_PER_ROW,      -- UV coordinate (0-1)
                uSize = 1.0 / SPRITES_PER_ROW, -- UV size for this sprite
                vSize = 1.0 / SPRITES_PER_ROW
            }
        end
        
        offset = offset + framesPerImageList[i]
    end
    spriteCount = offset
end

-- Create instance
local function createInstance()
    local instance = {}

    instance.config = {}
    for k, v in pairs(DEFAULT_CONFIG) do
        instance.config[k] = v
    end

    instance.instanceData = {}
    instance.instanceLookup = {}

    -- Initialize instance data (x, y, id)
    for i = 1, characterAnimator.instanceCount do
        local ref = { i * 100, 100 + i, i }
        table.insert(instance.instanceData, ref)
        instance.instanceLookup[i] = i
    end

    instance.states = {}
    instance.currentState = 1
    instance.currentDirection = 1
    instance.currentFrame = 1
    instance.timeAccumulator = 0
    instance.priority = 0
    instance.x = 0
    instance.y = 0
    instance.scale = 1
    instance.rotation = 0

    function instance.update(dt)
        local stateData = spriteTypes[instance.currentState]
        if not stateData then
            print("Warning: Invalid state '" .. tostring(instance.currentState) .. "' for instance")
            return
        end

        instance.timeAccumulator = instance.timeAccumulator + dt
        local frameInterval = 1 / instance.config.frameRate

        if instance.timeAccumulator >= frameInterval then
            instance.currentFrame = (instance.currentFrame % stateData.framesPerDirection) + 1
            instance.timeAccumulator = instance.timeAccumulator - frameInterval
        end
    end

    function instance.setDirection(direction)
        local stateData = spriteTypes[instance.currentState]
        instance.currentDirection = math.max(1, math.min(direction, stateData.directions))
    end

    function instance.setState(stateName, priority)
        if spriteTypes[stateName] then
            if priority then
                if instance.priority < priority then
                    instance.priority = priority
                    return
                end
            else
                instance.currentState = stateName
                instance.currentFrame = 1
                return
            end

            instance.currentState = stateName
            instance.currentFrame = 1
            instance.priority = priority
        end
    end

    function instance.getState()
        return instance.currentState
    end

    table.insert(instances, instance)
    return instance
end

function characterAnimator.load()
    -- Updated shader to handle UV coordinates for packed textures
    characterAnimator.shader = love.graphics.newShader([[
        #define MAX_LIGHTS 50

        uniform int numLights;
        uniform vec2 lightPositions[MAX_LIGHTS];
        uniform float lightIntensities[MAX_LIGHTS];
        uniform float lightRanges[MAX_LIGHTS];

        varying float VaryingLayer;
        varying vec2 VaryingUV;
        varying vec2 pos;

        #ifdef VERTEX
        attribute vec4 InstanceMatrix1;
        attribute vec4 InstanceMatrix2;
        attribute vec4 InstanceMatrix3;
        attribute vec4 InstanceMatrix4;
        attribute float InstanceLayer;
        attribute vec4 InstanceUVData; // u, v, uSize, vSize

        vec4 position(mat4 transform_projection, vec4 vertex_position) {
            VaryingLayer = InstanceLayer;
            
            // Transform UV coordinates based on sprite location in packed texture
            vec2 localUV = VaryingTexCoord.xy;
            VaryingUV = vec2(
                InstanceUVData.x + localUV.x * InstanceUVData.z,
                InstanceUVData.y + localUV.y * InstanceUVData.w
            );

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
            vec4 texColor = Texel(MainTex, vec3(VaryingUV, VaryingLayer));

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
    ]])
end

function characterAnimator.init(imageFiles, frameWidth, frameHeight)
    -- Process sprite sheets into packed array texture layers
    local allSpriteData = {}
    local framesPerImageList = {}
    
    -- First pass: extract all individual sprites
    for i, filename in ipairs(imageFiles) do
        local directions = 8
        local originalImageData = love.image.newImageData(filename)
        local spritesForThisImage = {}

        local framesPerImage = 0
        if originalImageData then
            local spriteWidth = frameWidth or (originalImageData:getWidth() / directions)
            local spriteHeight = frameHeight or spriteWidth
            local paddingX, paddingY = 0, 0
            local spritesX = directions
            local spritesY = math.floor(originalImageData:getHeight() / (spriteHeight + paddingY))
            
            for sy = 0, spritesY - 1 do
                for sx = 0, spritesX - 1 do
                    local uniformImageData = love.image.newImageData(uniformWidth, uniformHeight)
                    local srcXStart = sx * (spriteWidth + paddingX)
                    local srcYStart = sy * (spriteHeight + paddingY)

                    for y = 0, uniformHeight - 1 do
                        for x = 0, uniformWidth - 1 do
                            local srcX = math.floor(x * spriteWidth / uniformWidth)
                            local srcY = math.floor(y * spriteHeight / uniformHeight)
                            srcX = srcXStart + math.max(0, math.min(srcX, spriteWidth - 1))
                            srcY = srcYStart + math.max(0, math.min(srcY, spriteHeight - 1))
                            if srcX < originalImageData:getWidth() and srcY < originalImageData:getHeight() then
                                uniformImageData:setPixel(x, y, originalImageData:getPixel(srcX, srcY))
                            else
                                uniformImageData:setPixel(x, y, 0, 0, 0, 0)
                            end
                        end
                    end
                    table.insert(allSpriteData, uniformImageData)
                    framesPerImage = framesPerImage + 1
                end
            end
        else
            print("Failed to load image: " .. filename)
        end
        print("Frames for " .. filename .. ": " .. framesPerImage)
        framesPerImageList[i] = framesPerImage
    end

    calculateFrameOffsets(framesPerImageList, imageFiles)
    
    -- Second pass: pack sprites into 2048x2048 layers
    local numLayers = math.ceil(#allSpriteData / SPRITES_PER_LAYER)
    local packedLayers = {}
    
    for layer = 0, numLayers - 1 do
        local layerImageData = love.image.newImageData(LAYER_SIZE, LAYER_SIZE)
        
        for i = 0, SPRITES_PER_LAYER - 1 do
            local spriteIndex = layer * SPRITES_PER_LAYER + i + 1
            if spriteIndex <= #allSpriteData then
                local spriteData = allSpriteData[spriteIndex]
                local row = math.floor(i / SPRITES_PER_ROW)
                local col = i % SPRITES_PER_ROW
                local destX = col * uniformWidth
                local destY = row * uniformHeight
                
                -- Copy sprite to packed layer
                for y = 0, uniformHeight - 1 do
                    for x = 0, uniformWidth - 1 do
                        local r, g, b, a = spriteData:getPixel(x, y)
                        layerImageData:setPixel(destX + x, destY + y, r, g, b, a)
                    end
                end
            end
        end
        
        table.insert(packedLayers, layerImageData)
    end

    arrayTexture = love.graphics.newArrayImage(packedLayers)
    print("Created " .. numLayers .. " packed layers from " .. #allSpriteData .. " sprites")

    -- Create mesh for a single quad
    local size = uniformWidth / 2
    local vertices = {
        { -size, -size, 0, 0 },
        { size,  -size, 1, 0 },
        { size,  size,  1, 1 },
        { -size, size,  0, 1 }
    }

    mesh = love.graphics.newMesh(vertices, "fan", "stream")
    mesh:setTexture(arrayTexture)

    -- Create instance mesh with UV data
    local instanceFormat = {
        { "InstanceMatrix1", "float", 4 },
        { "InstanceMatrix2", "float", 4 },
        { "InstanceMatrix3", "float", 4 },
        { "InstanceMatrix4", "float", 4 },
        { "InstanceLayer",   "float", 1 },
        { "InstanceUVData",  "float", 4 }  -- u, v, uSize, vSize
    }

    local emptyInstanceData = {}
    for i = 1, characterAnimator.instanceCount * 21 do  -- Updated for new attribute count
        emptyInstanceData[i] = { 0 }
    end

    instanceMesh = love.graphics.newMesh(instanceFormat, emptyInstanceData, nil, "stream")

    mesh:attachAttribute("InstanceMatrix1", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceMatrix2", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceMatrix3", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceMatrix4", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceLayer", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceUVData", instanceMesh, "perinstance")

    -- Create multiple instances
    instances = {}
    for i = 1, characterAnimator.instanceCount do
        local instance = createInstance()
        instance.x = love.math.random(0, love.graphics.getWidth() * 2)
        instance.y = love.math.random(0, love.graphics.getHeight() * 2)
        instance.currentState = math.random(1,13)
        instance.currentDirection = love.math.random(1, spriteTypes[instance.currentState].directions)
        instance.scale = 1
    end

    print("Loaded " .. spriteCount .. " sprites into " .. numLayers .. " packed array texture layers")
    print("Created " .. #instances .. " instances")
    return instances
end

-- Calculate layer and UV coordinates from direction and frame
local function getLayerAndUV(instance)
    local spriteType = spriteTypes[instance.currentState]
    local offset = frameOffsets[instance.currentState]
    local directions = spriteType.directions
    local globalIndex = offset + (instance.currentFrame - 1) * directions + (instance.currentDirection - 1)
    
    local location = spriteLocationMap[globalIndex]
    if location then
        return location.layer, location.u, location.v, location.uSize, location.vSize
    else
        print("Warning: No location found for global index " .. globalIndex)
        return 0, 0, 0, 1.0 / SPRITES_PER_ROW, 1.0 / SPRITES_PER_ROW
    end
end

function characterAnimator.populate()
    local sortedIndices = {}
    local instanceData = {}
    local activeInstanceCount = 0

    for i, instance in ipairs(instances) do
        local stateData = spriteTypes[instance.currentState]
        if stateData then
            activeInstanceCount = activeInstanceCount + 1
            sortedIndices[activeInstanceCount] = i
        else
            print("Warning: Invalid state '" .. tostring(instance.currentState) .. "' for instance " .. i)
        end
    end

    table.sort(sortedIndices, function(a, b)
        return instances[a].y < instances[b].y
    end)

    for i = 1, activeInstanceCount do
        local instance = instances[sortedIndices[i]]
        local cos_r = math.cos(instance.rotation)
        local sin_r = math.sin(instance.rotation)
        local scale = instance.scale

        local matrix = {
            cos_r * scale, sin_r * scale, 0, 0,
            -sin_r * scale, cos_r * scale, 0, 0,
            0, 0, 1, 0,
            instance.x, instance.y, 0, 1
        }

        local layer, u, v, uSize, vSize = getLayerAndUV(instance)

        local instanceRow = {}
        for j = 1, 4 do instanceRow[j] = matrix[j] end
        for j = 1, 4 do instanceRow[4 + j] = matrix[4 + j] end
        for j = 1, 4 do instanceRow[8 + j] = matrix[8 + j] end
        for j = 1, 4 do instanceRow[12 + j] = matrix[12 + j] end
        instanceRow[17] = layer
        instanceRow[18] = u
        instanceRow[19] = v
        instanceRow[20] = uSize
        instanceRow[21] = vSize

        instanceData[i] = instanceRow
    end

    instanceMesh:setVertices(instanceData)
end

function characterAnimator.draw()
    love.graphics.setShader(characterAnimator.shader)
    love.graphics.drawInstanced(mesh, characterAnimator.instanceCount)
    love.graphics.setShader()
end

characterAnimator.frameTime = 0
function characterAnimator.update(dt)
    characterAnimator.frameTime = characterAnimator.frameTime + dt
    if characterAnimator.frameTime > 1 / 24 then
        for i, instance in ipairs(instances) do
            instance.update(dt)
            if i ~= 1 then
                instance.x = instance.x + dt * 20
                instance.y = instance.y + dt * 20
            end
        end
        characterAnimator.frameTime = 0
    end

    characterAnimator.populate()
end

return characterAnimator