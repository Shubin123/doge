-- Manages character animations from sprite sheets with 8-directional support using instanced rendering

local characterAnimator = {}
local DEFAULT_CONFIG = {
    directions = 8,
    frameRate = 20
}

characterAnimator.instanceCount = var.num_enemies -- for now just test with enemies
local uniformWidth = 128
local uniformHeight = 128

local mesh, instanceMesh, arrayTexture, shader
local spriteTypes = {}  -- {name = {directions, framesPerDirection, totalFrames}}
local frameOffsets = {} -- Starting layer for each sprite type
local spriteCount = 0
local instances = {}    -- Store all instances for populate

-- Calculate cumulative frame offsets
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
    -- Shader (unchanged)
    characterAnimator.shader = love.graphics.newShader([[
        #define MAX_LIGHTS 50

        uniform int numLights;
        uniform vec2 lightPositions[MAX_LIGHTS];
        uniform float lightIntensities[MAX_LIGHTS];
        uniform float lightRanges[MAX_LIGHTS];

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
    ]])
end

function characterAnimator.init(imageFiles, frameWidth, frameHeight)
    -- Process sprite sheets into array texture
    local imageDataList = {}
    local framesPerImageList = {}
    for i, filename in ipairs(imageFiles) do
        local directions = 8
        local originalImageData = love.image.newImageData(filename)
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
                    table.insert(imageDataList, uniformImageData)
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
    arrayTexture = love.graphics.newArrayImage(imageDataList)

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

    -- Create instance mesh
    local instanceFormat = {
        { "InstanceMatrix1", "float", 4 },
        { "InstanceMatrix2", "float", 4 },
        { "InstanceMatrix3", "float", 4 },
        { "InstanceMatrix4", "float", 4 },
        { "InstanceLayer",   "float", 1 }
    }

    local emptyInstanceData = {}
    for i = 1, characterAnimator.instanceCount * 17 do
        emptyInstanceData[i] = { 0 }
    end

    instanceMesh = love.graphics.newMesh(instanceFormat, emptyInstanceData, nil, "stream")

    mesh:attachAttribute("InstanceMatrix1", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceMatrix2", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceMatrix3", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceMatrix4", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceLayer", instanceMesh, "perinstance")

    -- Create multiple instances
    instances = {}                                -- Clear any existing instances
    for i = 1, characterAnimator.instanceCount do -- Create 10 instances for visibility
        local instance = createInstance()
        instance.x = love.math.random(0, love.graphics.getWidth() * 2)
        instance.y = love.math.random(0, love.graphics.getHeight() * 2)
        -- instance.currentState = imageFiles[math.min(i, #imageFiles)]:match("^(.-)%.png$")
        instance.currentState = math.random(1,5)
        instance.currentDirection = love.math.random(1, spriteTypes[instance.currentState].directions)
        instance.scale = 1
        -- instance.rotation = love.math.random() * math.pi * 2
    end

    print("Loaded " .. spriteCount .. " sprites into array texture")
    print("Created " .. #instances .. " instances")
    return instances -- Return first instance (e.g., princess) for compatibility
end

-- Calculate layer from direction and frame
local function getLayer(instance)
    local spriteType = spriteTypes[instance.currentState]
    local offset = frameOffsets[instance.currentState]
    local directions = spriteType.directions
    return offset + (instance.currentFrame - 1) * directions + (instance.currentDirection - 1)
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

        local instanceRow = {}
        for j = 1, 4 do instanceRow[j] = matrix[j] end
        for j = 1, 4 do instanceRow[4 + j] = matrix[4 + j] end
        for j = 1, 4 do instanceRow[8 + j] = matrix[8 + j] end
        for j = 1, 4 do instanceRow[12 + j] = matrix[12 + j] end
        instanceRow[17] = getLayer(instance)

        instanceData[i] = instanceRow
    end

    instanceMesh:setVertices(instanceData)
    -- print("Populated " .. activeInstanceCount .. " instances")
end

function characterAnimator.draw()
    love.graphics.setShader(characterAnimator.shader)
    love.graphics.drawInstanced(mesh, characterAnimator.instanceCount)
    love.graphics.setShader()
end

characterAnimator.frameTime = 0
function characterAnimator.update(dt)
    -- characterAnimator.frameTime = characterAnimator.frameTime + dt
    -- -- instances[1].x,instances[1].y = player.body:getPosition()
    -- if characterAnimator.frameTime > 1 / 24 then

    --     for i, instance in ipairs(instances) do
    --         instance.update(dt)           -- Update animation state
    --         if i ~= 1 then
    --         instance.x = instance.x + dt * 20 -- Move instances (example)
    --         instance.y = instance.y + dt * 20
    --         -- instance.setDirection(love.math.random(1, spriteTypes[1].directions)) -- Random direction for testing
    --         end
    --     end
    --     characterAnimator.frameTime = 0
    -- end
    -- -- end

    characterAnimator.populate() -- Ensure instanceMesh is updated
end

return characterAnimator
