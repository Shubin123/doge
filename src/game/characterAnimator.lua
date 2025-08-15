-- Manages character animations from sprite sheets with 8-directional support using instanced rendering
-- WebGL/Emscripten compatible version - avoids array textures completely on web

local characterAnimator = {}
local DEFAULT_CONFIG = {
    directions = 8,
    frameRate = 20
}

characterAnimator.instanceCount = var.num_enemies -- for now just test with enemies
local uniformWidth = 128
local uniformHeight = 128

local mesh, instanceMesh, texture, shader
local spriteTypes = {}       -- {name = {directions, framesPerDirection, totalFrames}}
local frameOffsets = {}      -- Starting frame index for each sprite type
local spriteCount = 0
local instances = {}         -- Store all instances for populate
local spriteLocationMap = {} -- Maps global sprite index to {u, v, uSize, vSize} coordinates

-- Calculate cumulative frame offsets and create location map FROM METADATA ONLY
local function calculateFrameOffsetsFromMetadata(metadata)
    local offset = 0
    spriteTypes = {}
    frameOffsets = {}
    spriteLocationMap = {}
    
    -- Process each sprite type from metadata
    for i, framesCount in ipairs(metadata.framesPerImageList) do
        -- local filename = metadata.imageFiles[i]
        -- local spriteName = filename:match("^(.-)%.png$") or filename
        
        -- Calculate directions based on the total frames and standard patterns
        -- For single frame sprites (like static objects), use 1 direction
        local directions = 1
        local framesPerDirection = framesCount
        
        -- For multi-frame sprites, try to infer direction count
        -- This is a heuristic - you may need to adjust based on your sprite conventions
        if framesCount > 1 then
            -- Common patterns: 8-directional (8, 16, 24, 32...), 4-directional (4, 8, 12...)
            if framesCount % 8 == 0 and framesCount >= 8 then
                directions = 8
                framesPerDirection = framesCount / 8
            elseif framesCount % 4 == 0 and framesCount >= 4 then
                directions = 4
                framesPerDirection = framesCount / 4
            else
                -- Assume single direction for irregular frame counts
                directions = 1
                framesPerDirection = framesCount
            end
        end
        
        spriteTypes[i] = {
            directions = directions,
            framesPerDirection = framesPerDirection,
            totalFrames = framesCount
        }
        frameOffsets[i] = offset

        -- Create location map for this sprite type's frames
        for frameIdx = 0, framesCount - 1 do
            local globalIndex = offset + frameIdx
            local row = math.floor(globalIndex / metadata.spritesPerRow)
            local col = globalIndex % metadata.spritesPerRow

            spriteLocationMap[globalIndex] = {
                u = (col * uniformWidth) / metadata.textureWidth,   -- UV coordinate (0-1)
                v = (row * uniformHeight) / metadata.textureHeight, -- UV coordinate (0-1)
                uSize = uniformWidth / metadata.textureWidth,       -- UV size for this sprite
                vSize = uniformHeight / metadata.textureHeight
            }
        end

        offset = offset + framesCount
    end
    spriteCount = offset
    
    print("Calculated frame offsets from metadata:")
    for i, spriteType in ipairs(spriteTypes) do
        print(string.format("  Sprite %d: %d directions, %d frames/dir, offset %d", 
              i, spriteType.directions, spriteType.framesPerDirection, frameOffsets[i]))
    end
end

-- Enhanced metadata creation that includes direction information
function characterAnimator.createAndSaveAtlas(imageFiles, config, frameWidth, frameHeight, atlasFilename, metadataFilename)
    -- Process sprite sheets into a single large texture atlas
    local allSpriteData = {}
    local framesPerImageList = {}
    local directionsPerImageList = {}

    -- First pass: extract all individual sprites
    for i, filename in ipairs(imageFiles) do
        local directions = config[i]
        print("Processing " .. filename .. " with " .. directions .. " directions")
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
        directionsPerImageList[i] = directions -- Store the actual directions used
    end

    -- Create single texture atlas (same as before)
    local totalSprites = #allSpriteData
    local spritesPerRow = math.ceil(math.sqrt(totalSprites))
    local textureWidth = spritesPerRow * uniformWidth
    local textureHeight = spritesPerRow * uniformHeight

    -- Ensure power of 2 dimensions for better compatibility
    textureWidth = math.pow(2, math.ceil(math.log(textureWidth) / math.log(2)))
    textureHeight = math.pow(2, math.ceil(math.log(textureHeight) / math.log(2)))

    -- Recalculate sprites per row based on final texture dimensions
    spritesPerRow = math.floor(textureWidth / uniformWidth)

    print("Creating texture atlas: " ..
        textureWidth .. "x" .. textureHeight .. " (" .. spritesPerRow .. " sprites per row)")

    local atlasTexture = love.image.newImageData(textureWidth, textureHeight)

    -- Clear the texture with transparent pixels
    for y = 0, textureHeight - 1 do
        for x = 0, textureWidth - 1 do
            atlasTexture:setPixel(x, y, 0, 0, 0, 0)
        end
    end

    -- Pack sprites into atlas
    for i, spriteData in ipairs(allSpriteData) do
        local spriteIndex = i - 1
        local row = math.floor(spriteIndex / spritesPerRow)
        local col = spriteIndex % spritesPerRow
        local destX = col * uniformWidth
        local destY = row * uniformHeight

        -- Copy sprite to atlas
        for y = 0, uniformHeight - 1 do
            for x = 0, uniformWidth - 1 do
                if destX + x < textureWidth and destY + y < textureHeight then
                    local r, g, b, a = spriteData:getPixel(x, y)
                    atlasTexture:setPixel(destX + x, destY + y, r, g, b, a)
                end
            end
        end
    end

    -- Save the atlas texture as PNG
    local fileData = atlasTexture:encode("png")
    local success = pcall(function()
        local file = io.open(atlasFilename, "wb")
        if file then
            file:write(fileData:getString())
            file:close()
            print("Saved atlas texture to: " .. atlasFilename .. " (in running directory)")
        else
            error("Could not open file for writing: " .. atlasFilename)
        end
    end)

    if not success then
        love.filesystem.write(atlasFilename, fileData)
        print("Saved atlas texture to: " .. atlasFilename .. " (in LÖVE save directory)")
    end

    -- Enhanced metadata with direction information
    local metadata = {
        textureWidth = textureWidth,
        textureHeight = textureHeight,
        spritesPerRow = spritesPerRow,
        uniformWidth = uniformWidth,
        uniformHeight = uniformHeight,
        framesPerImageList = framesPerImageList,
        directionsPerImageList = directionsPerImageList, -- NEW: Include actual directions
        imageFiles = imageFiles,
        totalSprites = totalSprites
    }

    -- Save metadata
    local metadataString = "return " .. serializeTable(metadata)
    local success2 = pcall(function()
        local file = io.open(metadataFilename, "w")
        if file then
            file:write(metadataString)
            file:close()
            print("Saved metadata to: " .. metadataFilename .. " (in running directory)")
        else
            error("Could not open file for writing: " .. metadataFilename)
        end
    end)

    if not success2 then
        love.filesystem.write(metadataFilename, metadataString)
        print("Saved metadata to: " .. metadataFilename .. " (in LÖVE save directory)")
    end

    return metadata
end

-- Helper function to serialize a table to string
function serializeTable(t, indent)
    indent = indent or ""
    local result = "{\n"
    for k, v in pairs(t) do
        local key = type(k) == "string" and ("\"" .. k .. "\"") or tostring(k)
        result = result .. indent .. "  [" .. key .. "] = "

        if type(v) == "table" then
            result = result .. serializeTable(v, indent .. "  ")
        elseif type(v) == "string" then
            result = result .. "\"" .. v .. "\""
        else
            result = result .. tostring(v)
        end
        result = result .. ",\n"
    end
    result = result .. indent .. "}"
    return result
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
    -- Universal shader that works on both desktop and web
    characterAnimator.shader = love.graphics.newShader([[
        #define MAX_LIGHTS 500

        uniform int numLights;
        uniform vec4 lights[MAX_LIGHTS];

        // Outline uniforms
        uniform float outlineWidth;
        uniform vec3 outlineColor;
        
        varying vec4 VColor;
        varying vec2 VaryingUV;
        varying vec2 pos;

        #ifdef VERTEX
attribute vec4 InstanceUVData; 
attribute vec4 color;
attribute vec3 InstanceMatrix1; 
attribute vec3 InstanceMatrix2; 
attribute vec3 InstanceMatrix4; 

vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec2 localUV = VaryingTexCoord.xy;
    VColor = vec4(color);
    VaryingUV = vec2(
        InstanceUVData.x + localUV.x * InstanceUVData.z,
        InstanceUVData.y + localUV.y * InstanceUVData.w
    );

    mat3 instance_matrix = mat3(
        InstanceMatrix1,
        InstanceMatrix2, 
        InstanceMatrix4
    );

    vec3 worldPos = instance_matrix * vec3(vertex_position.xy, 1.0);
    pos = worldPos.xy;

    return transform_projection * vec4(worldPos.xy, 0, 1.0);
}
#endif

        #ifdef PIXEL
        uniform Image MainTex;

        void effect() {
            vec4 texColor = Texel(MainTex, VaryingUV);
            
            // Calculate lighting
            float totalLight = 0.0;
            for (int i = 0; i < MAX_LIGHTS; i++) {
                if (i >= numLights) {
                    break;
                }
                float distance = length(vec2(lights[i][0],lights[i][1]) - pos);
                float attenuation = 1.0 - clamp(distance / lights[i][3], 0.0, 1.0);
                totalLight += attenuation * lights[i][2];
            }

            totalLight = clamp(totalLight, 0.0, 1.0);
            vec3 litColor = mix(vec3(0.0), texColor.rgb, totalLight);

            // Outline detection
            vec4 finalColor = vec4(litColor, texColor.a);

            if (VColor.w > 0.0) {
                // If current pixel is transparent, check if any nearby pixels are opaque
                if (texColor.a < 0.1) {
                    float outline = 0.0;

                    // Use a small fixed offset for sampling (adjust based on your atlas resolution)
                    float pixelOffset = VColor.w * 0.0001; // Adjust this value as needed

                    // 8-directional sampling for outline detection
                    for (int x = -1; x <= 1; x++) {
                        for (int y = -1; y <= 1; y++) {
                            if (x == 0 && y == 0) continue;

                            vec2 offset = vec2(float(x), float(y)) * pixelOffset;
                            vec4 sampleColor = Texel(MainTex, VaryingUV + offset);

                            if (sampleColor.a > 0.1) {
                                outline = 1.0;
                                break;
                            }
                        }
                        if (outline > 0.0) break;
                    }

                    if (outline > 0.0) {
                        finalColor = VColor;
                    }
                }
            }

            love_Canvases[0] = finalColor;
        }
        #endif
    ]])
end

-- Fast loading function that uses ONLY metadata
function characterAnimator.loadFromAtlas(atlasFilename, metadataFilename, compressed)
    -- Load metadata
    local metadataChunk = love.filesystem.load(metadataFilename)
    if not metadataChunk then
        error("Could not load metadata file: " .. metadataFilename)
    end
    local metadata = metadataChunk()
    print("Loaded metadata from LÖVE directory: " .. metadataFilename)

    -- Load atlas texture
    local atlasImageData
    if compressed then
        atlasImageData = love.image.newCompressedData(
            love.data.decompress("data", "zlib", love.filesystem.read(atlasFilename)), 
            "ktx"
        )
    else
        atlasImageData = love.image.newImageData(atlasFilename)
    end

    texture = love.graphics.newImage(atlasImageData)
    atlasImageData = nil
    collectgarbage()
    
    return characterAnimator.instancesFromTexture(texture, metadata)
end

function characterAnimator.instancesFromTexture(texture, metadata)
    texture:setFilter("nearest", "nearest")

    print("Loaded atlas texture: " .. metadata.textureWidth .. "x" .. metadata.textureHeight)

    -- Use metadata-only calculation - NO original image loading!
    calculateFrameOffsetsFromMetadata(metadata)

    print("Loaded " .. metadata.totalSprites .. " sprites from atlas")

    local size = metadata.uniformWidth / 2
    local vertices = {
        { -size, -size, 0, 0 },
        { size,  -size, 1, 0 },
        { size,  size,  1, 1 },
        { -size, size,  0, 1 }
    }

    mesh = love.graphics.newMesh(vertices, "fan", "stream")
    mesh:setTexture(texture)

    -- Instance format for 3x3 matrix
    local instanceFormat = {
        { "InstanceUVData",  "float", 4 },
        { "color",           "float", 4 },
        { "InstanceMatrix1", "float", 3 },
        { "InstanceMatrix2", "float", 3 },
        { "InstanceMatrix4", "float", 3 },
    }

    local emptyInstanceData = {}
    for i = 1, characterAnimator.instanceCount * 17 do -- 17 floats per instance
        table.insert(emptyInstanceData, { 0 })
    end

    instanceMesh = love.graphics.newMesh(instanceFormat, emptyInstanceData, nil, "stream")
    mesh:attachAttribute("InstanceUVData", instanceMesh, "perinstance")
    mesh:attachAttribute("color", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceMatrix1", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceMatrix2", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceMatrix4", instanceMesh, "perinstance")

    -- Create instances
    instances = {}
    for i = 1, characterAnimator.instanceCount do
        local instance = createInstance()
        instance.x = love.math.random(0, love.graphics.getWidth() * 2)
        instance.y = love.math.random(0, love.graphics.getHeight() * 2)
        instance.currentState = math.random(1, #metadata.framesPerImageList)
        instance.currentDirection = love.math.random(1, spriteTypes[instance.currentState].directions)
        instance.color = { 1, 1, 1, 0 }
    end

    print("Created " .. #instances .. " instances")
    return instances
end

-- Function to check if files exist
function characterAnimator.checkFilesExist(atlasFilename, metadataFilename)
    local atlasExists = false
    local metadataExists = false

    pcall(function()
        local file = io.open(atlasFilename, "r")
        if file then
            file:close()
            atlasExists = true
        end
    end)

    pcall(function()
        local file = io.open(metadataFilename, "r")
        if file then
            file:close()
            metadataExists = true
        end
    end)

    if not atlasExists then
        atlasExists = love.filesystem.getInfo(atlasFilename) ~= nil
    end

    if not metadataExists then
        metadataExists = love.filesystem.getInfo(metadataFilename) ~= nil
    end

    return atlasExists and metadataExists
end

-- Convenience function
function characterAnimator.initFromCache(imageFiles, config, frameWidth, frameHeight, atlasFilename, metadataFilename)
    atlasFilename = atlasFilename or "atlas2.png"
    metadataFilename = metadataFilename or "atlas_metadata2.lua"

    print("Looking for atlas files...")

    if characterAnimator.checkFilesExist(atlasFilename, metadataFilename) then
        print("Loading from cached atlas...")
        return characterAnimator.loadFromAtlas(atlasFilename, metadataFilename)
    else
        print("Creating new atlas...")
        characterAnimator.createAndSaveAtlas(imageFiles, config, frameWidth, frameHeight, atlasFilename, metadataFilename)
        return characterAnimator.loadFromAtlas(atlasFilename, metadataFilename)
    end
end

-- Calculate UV coordinates from direction and frame
local function getUV(instance)
    local spriteType = spriteTypes[instance.currentState]
    local offset = frameOffsets[instance.currentState]
    local directions = spriteType.directions
    local globalIndex = offset + (instance.currentFrame - 1) * directions + (instance.currentDirection - 1)

    local location = spriteLocationMap[globalIndex]
    if location then
        return location.u, location.v, location.uSize, location.vSize
    else
        print("Warning: No location found for global index " .. globalIndex)
        return 0, 0, 0.1, 0.1
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

        local u, v, uSize, vSize = getUV(instance)

        instanceData[i] = {
            u, v, uSize, vSize,                        -- InstanceUVData
            instance.color[1], instance.color[2], instance.color[3], instance.color[4],
            cos_r * scale, sin_r * scale, 0,           -- InstanceMatrix1 (row 1)
            -sin_r * scale, cos_r * scale, 0,          -- InstanceMatrix2 (row 2)  
            instance.x, instance.y, 1,                 -- InstanceMatrix4 (row 3)
        }
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
        end
        characterAnimator.frameTime = 0
    end

    characterAnimator.populate()
end

return characterAnimator