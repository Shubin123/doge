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

-- Platform detection


-- Calculate cumulative frame offsets and create location map
local function calculateFrameOffsets(framesPerImageList, imageFiles, textureWidth, textureHeight, spritesPerRow)
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
            local row = math.floor(globalIndex / spritesPerRow)
            local col = globalIndex % spritesPerRow

            spriteLocationMap[globalIndex] = {
                u = (col * uniformWidth) / textureWidth,   -- UV coordinate (0-1)
                v = (row * uniformHeight) / textureHeight, -- UV coordinate (0-1)
                uSize = uniformWidth / textureWidth,       -- UV size for this sprite
                vSize = uniformHeight / textureHeight
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
    -- Universal shader that works on both desktop and web
    characterAnimator.shader = love.graphics.newShader([[
        #define MAX_LIGHTS 500

        uniform int numLights;
        //uniform vec2 lightPositions[MAX_LIGHTS];
        //uniform float lightIntensities[MAX_LIGHTS];
        //uniform float lightRanges[MAX_LIGHTS];
        uniform vec4 lights[MAX_LIGHTS];

        // Outline uniforms
        uniform float outlineWidth;
        uniform vec3 outlineColor;
        //uniform bool enableOutline; //dont need this since vertexColorOutline can determine per instance enable or disable
        
        varying vec4 VColor;
        varying vec2 VaryingUV;
        varying vec2 pos;
        //varying float dissolveAmount;

        #ifdef VERTEX
attribute vec4 InstanceUVData; 
attribute vec4 color;
attribute vec3 InstanceMatrix1; 
attribute vec3 InstanceMatrix2; 
attribute vec3 InstanceMatrix4; 


vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec2 localUV = VaryingTexCoord.xy;
    VColor = vec4(color);
    //dissolveAmount = InstanceMatrix1[2]; // we have extra space here so use it
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
            //texColor = mix(texColor,VColor,1); -- dont do mix here wait for light mix
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

            //litColor = mix(litColor,VColor.xyz , totalLight/5);

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
                        // finalColor = vec4(outlineColor, 0.5);
                        finalColor = VColor;
                    }
                }
            }

            love_Canvases[0] = finalColor;
        }
        #endif
    ]])
    -- characterAnimator.shader:send("outlineWidth", 1)
    -- characterAnimator.shader:send("outlineColor", {1, 1, 1}) -- white by default
    -- characterAnimator.shader:send("enableOutline", true)
end

-- Helper function to set outline parameters
-- function characterAnimator.setOutline(width, color, enabled)
--     if characterAnimator.shader then
--         characterAnimator.shader:send("outlineWidth", width or 1.0)
--         characterAnimator.shader:send("outlineColor", color or {1, 1, 1}) -- white by default
--         characterAnimator.shader:send("enableOutline", enabled ~= false) -- enabled by default
--     end
-- end

-- Example usage:
-- characterAnimator.setOutline(2.0, {1, 0, 0}, true) -- Red outline, 2 pixels wide

-- Function to create and save atlas to disk
function characterAnimator.createAndSaveAtlas(imageFiles, config, frameWidth, frameHeight, atlasFilename,
                                              metadataFilename)
    -- Process sprite sheets into a single large texture atlas (same as original init)
    local allSpriteData = {}
    local framesPerImageList = {}

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
    end

    -- Create single texture atlas
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

    -- Save the atlas texture as PNG in running directory
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
        -- Fallback to LÖVE filesystem if direct file access fails
        love.filesystem.write(atlasFilename, fileData)
        print("Saved atlas texture to: " .. atlasFilename .. " (in LÖVE save directory)")
    end

    -- Save metadata needed for loading
    local metadata = {
        textureWidth = textureWidth,
        textureHeight = textureHeight,
        spritesPerRow = spritesPerRow,
        uniformWidth = uniformWidth,
        uniformHeight = uniformHeight,
        framesPerImageList = framesPerImageList,
        imageFiles = imageFiles,
        totalSprites = totalSprites
    }

    -- Convert metadata to string and save in running directory
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
        -- Fallback to LÖVE filesystem if direct file access fails
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

-- Fast loading function that replaces the original init
function characterAnimator.loadFromAtlas(atlasFilename, metadataFilename, compressed)
    -- Try to load metadata from running directory first
    local metadata

    local metadataChunk = love.filesystem.load(metadataFilename)
    if not metadataChunk then
        error("Could not load metadata file: " .. metadataFilename)
    end
    metadata = metadataChunk()
    print("Loaded metadata from LÖVE directory: " .. metadataFilename)
    -- end

    -- Try to load atlas texture from running directory first
    local atlasImageData
    -- local success2 = pcall(function()
    --     local file = io.open(atlasFilename, "rb")
    --     if file then
    --         local content = file:read("*a")
    --         file:close()
    --         local fileData = love.filesystem.newFileData(content, atlasFilename)
    --         atlasImageData = love.image.newImageData(fileData)
    --         print("Loaded atlas from running directory: " .. atlasFilename)
    --     end
    -- end)
    if (compressed) then
        -- local compressedData, size = love.filesystem.read(atlasFilename)
        -- if not compressedData then
        --     error("Failed to load compressed file: " .. atlasImageData)
        -- end

        -- Decompress the data
        -- local decompressedData = love.data.decompress("data", "zlib", compressedData)
        -- atlasImageData = love.image.newCompressedData(decompressedData,"dds")
        -- Create compressed data object and image
        atlasImageData = love.image.newCompressedData(love.data.decompress("data", "zlib", love.filesystem.read(atlasFilename)), "ktx")

        
        -- decompressedData = nil
        
        -- compressedData = nil

        -- texture = love.graphics.newImage(atlasImageData)
    else
        atlasImageData = love.image.newImageData(atlasFilename)
    end

    -- if not success2 or not atlasImageData then
    -- Fallback to LÖVE filesystem

    -- print("Loaded atlas from LÖVE directory: " .. atlasFilename)
    -- end

    texture = love.graphics.newImage(atlasImageData)
    atlasImageData = nil
    collectgarbage() -- At this point, decompressedData and cd can be garbage collected explicitly nil and free ~600mb of memory when loading a 16k squared texture
    return characterAnimator.instancesFromTexture(texture, metadata)
end

function characterAnimator.instancesFromTexture(texture, metadata)
    texture:setFilter("nearest", "nearest")

    print("Loaded atlas texture: " .. metadata.textureWidth .. "x" .. metadata.textureHeight)

    calculateFrameOffsets(metadata.framesPerImageList, metadata.imageFiles,
        metadata.textureWidth, metadata.textureHeight, metadata.spritesPerRow)

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

    -- Updated instance format for 3x3 matrix:
    local instanceFormat = {
        { "InstanceUVData",  "float", 4 },
        { "color",           "float", 4 },
        { "InstanceMatrix1", "float", 3 },  -- Changed from 4 to 3
        { "InstanceMatrix2", "float", 3 },  -- Changed from 4 to 3
        { "InstanceMatrix4", "float", 3 },  -- Changed from 4 to 3 (skip Matrix3)
    }

    local emptyInstanceData = {}
    for i = 1, characterAnimator.instanceCount * 17 do -- 17 floats per instance (3+3+3+4+4)
        table.insert(emptyInstanceData, { 0 })
    end

    instanceMesh = love.graphics.newMesh(instanceFormat, emptyInstanceData, nil, "stream")
    mesh:attachAttribute("InstanceUVData", instanceMesh, "perinstance")
    mesh:attachAttribute("color", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceMatrix1", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceMatrix2", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceMatrix4", instanceMesh, "perinstance")  -- Skip Matrix3
    

    -- Create instances (same as before)
    instances = {}
    for i = 1, characterAnimator.instanceCount do
        local instance = createInstance()
        instance.x = love.math.random(0, love.graphics.getWidth() * 2)
        instance.y = love.math.random(0, love.graphics.getHeight() * 2)
        instance.currentState = math.random(1, #metadata.imageFiles)
        instance.currentDirection = love.math.random(1, spriteTypes[instance.currentState].directions)
        -- instance.scale = math.random(0.5, 1)
        instance.color = { 1, 1, 1, 0 }
    end

    print("Created " .. #instances .. " instances")
    return instances
end

-- Function to check if files exist in running directory
function characterAnimator.checkFilesExist(atlasFilename, metadataFilename)
    -- Check running directory first
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

    -- If not found in running directory, check LÖVE filesystem
    if not atlasExists then
        atlasExists = love.filesystem.getInfo(atlasFilename) ~= nil
    end

    if not metadataExists then
        metadataExists = love.filesystem.getInfo(metadataFilename) ~= nil
    end

    return atlasExists and metadataExists
end

-- Convenience function to check if atlas files exist and decide whether to create or load
function characterAnimator.initFromCache(imageFiles, config, frameWidth, frameHeight, atlasFilename, metadataFilename)
    atlasFilename = atlasFilename or "atlas2.png"
    metadataFilename = metadataFilename or "atlas_metadata2.lua"

    print("Looking for atlas files in running directory...")

    -- Check if both atlas and metadata files exist
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

        -- Extract the 3x3 matrix from your working 4x4:
        -- From: cos_r * scale, sin_r * scale, 0, 0,
        --       -sin_r * scale, cos_r * scale, 0, 0,
        --       0, 0, 1, 0,
        --       instance.x, instance.y, 0, 1
        -- To:   cos_r * scale, sin_r * scale, 0,
        --       -sin_r * scale, cos_r * scale, 0, 
        --       instance.x, instance.y, 1

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
            -- if i ~= 1 then
            --     instance.x = instance.x + dt * 20
            --     instance.y = instance.y + dt * 20
            -- end
        end
        characterAnimator.frameTime = 0
    end

    characterAnimator.populate()
end

return characterAnimator