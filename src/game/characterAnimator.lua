-- Manages character animations from sprite sheets with 8-directional support using instanced rendering
-- WebGL/Emscripten compatible version - supports multiple animation states per character
local characterAnimator = {}
local DEFAULT_CONFIG = {
    directions = 8,
    animationSpeed = 0.5
}

characterAnimator.instanceCount = var.num_instances -- for now just test with enemies
local uniformWidth = 128
local uniformHeight = 128

local mesh, litmesh, instanceMesh, texture, shader
local spriteTypes = {} -- {name = {directions, framesPerDirection, totalFrames}}
local frameOffsets = {} -- Starting frame index for each sprite type
local characterDefinitions = {} -- Character types with their animation states

local spriteCount = 0
local instances = {} -- Store all instances for populate
local spriteLocationMap = {} -- Maps global sprite index to {u, v, uSize, vSize} coordinates

-- Define character types and their associated animation states
-- This maps sprite sheet indices to character types and animation names
local function defineCharacterTypes(metadata)

    characterDefinitions = metadata.characterDefinitions

    print("Defined character types:")
    for charType, def in pairs(characterDefinitions) do
        local animList = {}
        for animName, spriteIndex in pairs(def.animations) do
            table.insert(animList, animName .. "(" .. spriteIndex .. ")")
        end
        print("  " .. charType .. ": " .. table.concat(animList, ", "))
    end

end

-- Get character type names for easy access
local function getCharacterTypes()
    local types = {}
    for charType, _ in pairs(characterDefinitions) do
        table.insert(types, charType)
    end
    return types
end

-- Calculate cumulative frame offsets and create location map FROM METADATA ONLY
local function calculateFrameOffsetsFromMetadata(metadata)
    local offset = 0
    spriteTypes = {}
    frameOffsets = {}
    spriteLocationMap = {}

    -- Process each sprite type from metadata
    for i, framesCount in ipairs(metadata.framesPerImageList) do
        local filename = metadata.imageFiles[i]
        local spriteName = filename:match("^(.-)%.png$") or filename

        -- Calculate directions based on the total frames and standard patterns
        local directions = 1
        local framesPerDirection = framesCount

        -- For multi-frame sprites, try to infer direction count
        if framesCount > 1 then
            if framesCount % 8 == 0 and framesCount >= 8 then
                directions = 8
                framesPerDirection = framesCount / 8
                -- elseif framesCount % 4 == 0 and framesCount >= 4 then
                --     directions = 4
                --     framesPerDirection = framesCount / 4
            else
                directions = 1
                framesPerDirection = framesCount
            end
        end

        spriteTypes[i] = {
            directions = directions,
            framesPerDirection = framesPerDirection,
            totalFrames = framesCount,
            filename = filename
        }
        frameOffsets[i] = offset

        -- Create location map for this sprite type's frames
        for frameIdx = 0, framesCount - 1 do
            local globalIndex = offset + frameIdx
            local row = math.floor(globalIndex / metadata.spritesPerRow)
            local col = globalIndex % metadata.spritesPerRow

            spriteLocationMap[globalIndex] = {
                u = (col * uniformWidth) / metadata.textureWidth,
                v = (row * uniformHeight) / metadata.textureHeight,
                uSize = uniformWidth / metadata.textureWidth,
                vSize = uniformHeight / metadata.textureHeight
            }
        end

        offset = offset + framesCount
    end
    spriteCount = offset

    print("Calculated frame offsets from metadata:")
    for i, spriteType in ipairs(spriteTypes) do
        print(string.format("  Sprite %d (%s): %d directions, %d frames/dir, offset %d", i, spriteType.filename,
            spriteType.directions, spriteType.framesPerDirection, frameOffsets[i]))
    end
end

-- Enhanced metadata creation that includes direction information
--
-- NOTE: for the shipping atlas, this is superseded by tools/pack_atlas.py
-- (see the repo root README / tools/README.md) — a one-step CLI that does
-- this same extraction+packing plus BC3 encoding and zlib compression in
-- a single call, with a test suite and alpha-padding dilation the manual
-- LÖVE+bc-encoder+compress.lua workflow never had. This function is kept
-- as-is for quick in-editor one-off experiments (it's what the pipeline's
-- Python atlas_lib.extract_frames_from_source/pack_atlas were ported from,
-- and are tested for bit-for-bit fidelity against — see
-- tests/test_stage1_extraction.py); it just isn't how the
-- shipping gfx/atlas/atla.dds.zlib gets rebuilt any more.
function characterAnimator.createAndSaveAtlas(imageFiles, config, frameWidth, frameHeight, atlasFilename,
    metadataFilename)
    local allSpriteData = {}
    local framesPerImageList = {}
    local directionsPerImageList = {}

    -- First pass: extract all individual sprites
    for i, filename in ipairs(imageFiles) do
        local directions = config[i]
        print("Processing " .. filename .. " with " .. directions .. " directions")
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
                    table.insert(allSpriteData, uniformImageData)
                    framesPerImage = framesPerImage + 1
                end
            end
        else
            print("Failed to load image: " .. filename)
        end
        print("Frames for " .. filename .. ": " .. framesPerImage)
        framesPerImageList[i] = framesPerImage
        directionsPerImageList[i] = directions
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

    print("Creating texture atlas: " .. textureWidth .. "x" .. textureHeight .. " (" .. spritesPerRow ..
              " sprites per row)")

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
        directionsPerImageList = directionsPerImageList,
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

-- Create instance with character type support
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
        local ref = {i * 100, 100 + i, i}
        table.insert(instance.instanceData, ref)
        instance.instanceLookup[i] = i
    end

    -- Character and animation state
    instance.characterType = nil -- e.g., "watchman", "princess"
    instance.currentAnimation = nil -- e.g., "idle", "walk", "shoot"
    instance.currentSpriteIndex = 1 -- The actual sprite sheet index being used
    instance.currentDirection = 1
    instance.currentFrame = 1
    instance.timeAccumulator = 0
    instance.priority = 0
    instance.x = 0
    instance.y = 0
    instance.scale = 1
    instance.rotation = 0
    instance.on = true

    function instance.update(dt)
        if not instance.currentSpriteIndex then
            return
        end

        local stateData = spriteTypes[instance.currentSpriteIndex]
        if not stateData then
            print("Warning: Invalid sprite index '" .. tostring(instance.currentSpriteIndex) .. "' for instance")
            return
        end

        instance.timeAccumulator = instance.timeAccumulator + dt
        -- local frameInterval = 1 / instance.config.frameRate
        -- local frameInterval = dt*math.sin(fire.t)
        local frameInterval = dt / instance.config.animationSpeed

        if instance.timeAccumulator >= frameInterval then
            if stateData.directions > 1 then
                instance.currentFrame = (instance.currentFrame % stateData.framesPerDirection) + 1
            else
                -- instance.currentFrame = math.floor(math.abs((stateData.framesPerDirection)*math.sin(fire.t))) + 1
                instance.currentFrame = mymath.heading(gun.lastAimDirection.x, gun.lastAimDirection.y,
                    stateData.framesPerDirection)
            end
            instance.timeAccumulator = instance.timeAccumulator - frameInterval
        else
            instance.priority = 0
        end
    end

    function instance.setDirection(direction)
        if not instance.currentSpriteIndex then
            return
        end
        local stateData = spriteTypes[instance.currentSpriteIndex]
        instance.currentDirection = math.max(1, math.min(direction, stateData.directions))
    end

    -- Set character type and initialize with default animation
    function instance.setCharacterType(characterType)
        local charDef = characterDefinitions[characterType]
        if not charDef then
            print("Warning: Unknown character type '" .. characterType .. "'")
            return false
        end

        instance.characterType = characterType
        instance.setAnimation(charDef.defaultAnimation)
        return true
    end

    -- Change animation for the current character type
    function instance.setAnimation(animationName, priority)
        if not instance.characterType then
            print("Warning: No character type set for instance")
            return false
        end

        local charDef = characterDefinitions[instance.characterType]
        local spriteIndex = charDef.animations[animationName]

        if not spriteIndex then
            -- print("Warning: Animation '" .. animationName .. "' not found for character '" .. instance.characterType .. "'")
            return false
        end

        if priority then
            if instance.priority >= priority then
                return false -- Current animation has higher or equal priority
            end
            instance.priority = priority
        else
            instance.priority = 0
        end

        instance.currentAnimation = animationName
        instance.currentSpriteIndex = spriteIndex
        -- instance.currentFrame = 1
        instance.timeAccumulator = 0

        return true
    end

    function instance.getCharacterType()
        return instance.characterType
    end

    function instance.getCurrentAnimation()
        return instance.currentAnimation
    end

    table.insert(instances, instance)
    return instance
end

function characterAnimator.load()
    -- Universal shader that works on both desktop and web
   characterAnimator.shader = love.graphics.newShader([[
        // MAX_LIGHTS must match lighting.MAX_LIGHTS (shadow.lua); the Lighting
        // subsystem uploads numLights + lights[] (world space) here each frame.
        #define MAX_LIGHTS 64

        uniform int numLights;
        uniform vec4 lights[MAX_LIGHTS];

        // Outline uniforms
        uniform float outlineWidth;
        uniform vec3 outlineColor;
        
        // Normal map uniforms
        uniform Image NormalTex;
        uniform bool useNormalMap;
        
        // Steve's atlas bounds and frame info
        uniform vec4 steveAtlasUVBounds;  // minU, minV, maxU, maxV in main atlas
        uniform int steveFrameOffset;      // Starting frame index in atlas
        uniform int steveTotalFrames;      // Total number of frames (200 for Steve)
        uniform int steveColumns;          // Columns in normal map (16)
        uniform vec2 normalMapSpriteSize;  // Size of one sprite in normal map UV space
        
        varying vec4 VColor;
        varying vec2 VaryingUV;
        varying vec2 pos;

        #ifdef VERTEX
attribute vec4 InstanceUVData; 
attribute vec4 color;
attribute vec3 InstanceMatrix1; 
attribute vec3 InstanceMatrix2; 
attribute vec3 InstanceMatrix4; 
attribute float onoff;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
    if (int(onoff) == 1) {
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
}
        #endif

        #ifdef PIXEL
        uniform Image MainTex;

        vec3 decodeNormal(vec3 encodedNormal) {
            return normalize(encodedNormal * 2.0 - 1.0);
        }

        // Calculate which frame we're rendering and map to normal map coordinates
        vec2 remapAtlasUVToNormalMap(vec2 atlasUV, vec4 atlasUVBounds, int frameOffset, 
                                     int totalFrames, int columns, vec2 spriteSize) {
            // Atlas has 128 sprites per row (16384 / 128)
            float atlasSpritesPerRow = 128.0;
            float atlasSpriteSize = 1.0 / atlasSpritesPerRow; // UV size of one sprite
            
            // Calculate which sprite we're in within the atlas
            float atlasCol = floor(atlasUV.x / atlasSpriteSize);
            float atlasRow = floor(atlasUV.y / atlasSpriteSize);
            int globalSpriteIndex = int(atlasRow * atlasSpritesPerRow + atlasCol);
            
            // Convert to frame index relative to Steve's frames (0-199)
            int relativeFrameIndex = globalSpriteIndex - frameOffset;
            
            // Get local UV within the current sprite (0-1)
            vec2 localUV = vec2(
                fract(atlasUV.x / atlasSpriteSize),
                fract(atlasUV.y / atlasSpriteSize)
            );
            
            // Calculate position in normal map grid
            int normalMapCol = int(mod(float(relativeFrameIndex), float(columns)));
            int normalMapRow = relativeFrameIndex / columns;
            
            // Map to normal map UV space
            vec2 normalMapUV = vec2(
                (float(normalMapCol) + localUV.x) * spriteSize.x,
                (float(normalMapRow) + localUV.y) * spriteSize.y
            );
            
            return normalMapUV;
        }

        float calculateNormalLighting(vec3 normal, vec2 lightPos, vec2 fragPos) {
            vec2 toLight2D = lightPos - fragPos;
            float dist = length(toLight2D);
            float lightHeight = 50.0;
            vec3 toLight3D = (dist == 0.0) 
                ? vec3(0.0, 0.0, 1.0) 
                : normalize(vec3(toLight2D, lightHeight));
            
            float NdotL = max(dot(normal, toLight3D), 0.0);
            
            float attenuation = 1.0 / (0.001 + 0.02 * dist);
            float ambient = .5;
            
            return ambient + NdotL * attenuation * (1.0 - ambient);
        }

        void effect() {
            vec4 texColor = Texel(MainTex, VaryingUV);
            
            // Check if current UV is within Steve's atlas bounds
            bool isSteveWalk = useNormalMap && 
                               VaryingUV.x >= steveAtlasUVBounds.x && 
                               VaryingUV.x <= steveAtlasUVBounds.z &&
                               VaryingUV.y >= steveAtlasUVBounds.y && 
                               VaryingUV.y <= steveAtlasUVBounds.w;
            
            vec3 normal = vec3(0.0, 0.0, 1.0); // Default normal
            
            if (isSteveWalk) {
                // Remap atlas UV to normal map UV
                vec2 normalMapUV = remapAtlasUVToNormalMap(
                    VaryingUV, 
                    steveAtlasUVBounds, 
                    steveFrameOffset,
                    steveTotalFrames,
                    steveColumns,
                    normalMapSpriteSize
                );
                
                vec4 normalSample = Texel(NormalTex, normalMapUV);
                normal = decodeNormal(normalSample.rgb);
            }
            
            // Calculate lighting
            float totalLight = 0.0;
            
            for (int i = 0; i < MAX_LIGHTS; i++) {
                if (i >= numLights) {
                    break;
                }
                
                vec2 lightPos = vec2(lights[i][0], lights[i][1]);
                float lightIntensity = lights[i][2];
                float lightRadius = lights[i][3];
                if (lightRadius <= 0.0) continue; // skip empty / zero-range slots (no NaN)

                float distance = length(lightPos - pos);
                float attenuation = 1.0 - clamp(distance / lightRadius, 0.0, 1.0);
                attenuation *= attenuation; // smooth quadratic falloff

                float normalFactor = calculateNormalLighting(normal, lightPos, pos);
                totalLight += attenuation * lightIntensity * normalFactor;
            }

            // Ambient floor so sprites stay dim (not pure black) when unlit/indoors.
            float lit = min(1.0, 0.20 + totalLight);
            vec3 litColor = texColor.rgb * lit;
            
            vec4 finalColor = vec4(litColor, texColor.a);

            // Outline detection
            if (VColor.w > 0.0) {
                if (texColor.a < 0.1) {
                    float outline = 0.0;
                    float pixelOffset = VColor.w * 0.0001;

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
    
    
    -- Initialize shader uniforms
    local normalMapTexture = love.graphics.newImage("gfx/3d/princess/normals/walk2.png.wow")
    characterAnimator.shader:send("NormalTex", normalMapTexture)
    characterAnimator.shader:send("useNormalMap", true)

    
    -- Calculate sprite size in normal map UV space
    -- If normal map is 2048×128 (16 columns, 1 row), each sprite is 128×128
    local normalMapWidth = normalMapTexture:getWidth()
    local normalMapHeight = normalMapTexture:getHeight()
    local spriteSizeU = 128.0 / normalMapWidth  -- 128/2048 = 0.0625
    local spriteSizeV = 128.0 / normalMapHeight -- 128/128 = 1.0
    characterAnimator.shader:send("normalMapSpriteSize", {spriteSizeU, spriteSizeV})
    characterAnimator.shader:send("steveColumns", 8)
    
    -- characterAnimator.shader:send("steveAtlasUVBounds", {0, 0, 0, 0})
    -- characterAnimator.shader:send("steveFrameOffset", 0)
    -- characterAnimator.shader:send("steveTotalFrames", 200)
    
    -- UV bounds will be set after metadata is loaded
    -- characterAnimator.shader:send("steveWalkUVBounds", {0, 0, 0, 0})
    
    -- below shader is for fully lit sprites so no need for shadow/light info
    characterAnimator.shaderWithTransforms = love.graphics.newShader([[
        uniform vec3 cameraPosition; // z component is zoom
        //uniform int numLights;
        //uniform vec4 lights[MAX_LIGHTS];

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
attribute float onoff;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
if (int(onoff) == 0) {
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

    vec3 worldPos = instance_matrix * vec3(vertex_position.xy*cameraPosition.z + cameraPosition.xy, cameraPosition.z);
    

    pos = worldPos.xy;

    return transform_projection * vec4(worldPos.xy, 0, 1.0);
}
}
#endif

        #ifdef PIXEL
        uniform Image MainTex;

        void effect() {
            vec4 texColor = Texel(MainTex, VaryingUV);
            
            vec4 finalColor = vec4(texColor);

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

-- Add this helper function to calculate and set Steve's UV bounds
-- Updated function to set Steve's UV bounds correctly
function characterAnimator.setSteveWalkUVBounds(metadata)
    local steveWalkIndex = 19
    local offset = frameOffsets[steveWalkIndex]
    local spriteType = spriteTypes[steveWalkIndex]
    
    if not spriteType then
        print("Warning: Could not find Steve walk sprite data")
        return
    end
    
    -- Calculate atlas UV bounds for all Steve frames
    local minU, minV = 1, 1
    local maxU, maxV = 0, 0
    
    for frameIdx = 0, spriteType.totalFrames - 1 do
        local globalIndex = offset + frameIdx
        local location = spriteLocationMap[globalIndex]
        
        if location then
            minU = math.min(minU, location.u)
            minV = math.min(minV, location.v)
            maxU = math.max(maxU, location.u + location.uSize)
            maxV = math.max(maxV, location.v + location.vSize)
        end
    end
    
    print(string.format("Steve atlas UV bounds: minU=%.4f, minV=%.4f, maxU=%.4f, maxV=%.4f", 
                        minU, minV, maxU, maxV))
    
    characterAnimator.shader:send("steveAtlasUVBounds", {minU, minV, maxU, maxV})
    characterAnimator.shader:send("steveFrameOffset", offset)
    -- characterAnimator.shader:send("steveTotalFrames", spriteType.totalFrames)
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
        atlasImageData = love.image.newCompressedData(love.data.decompress("data", "zlib",
            love.filesystem.read(atlasFilename)))
    else
        atlasImageData = love.image.newImageData(atlasFilename)
    end

    texture = love.graphics.newImage(atlasImageData)
    atlasImageData = nil
    collectgarbage()

    local instances = characterAnimator.instancesFromTexture(texture, metadata)
    
    -- Set Steve's UV bounds after everything is loaded
    characterAnimator.setSteveWalkUVBounds(metadata)
    
    return instances
end

function characterAnimator.instancesFromTexture(texture, metadata)
    texture:setFilter("nearest", "nearest")

    print("Loaded atlas texture: " .. metadata.textureWidth .. "x" .. metadata.textureHeight)

    -- Use metadata-only calculation
    calculateFrameOffsetsFromMetadata(metadata)

    -- Define character types after loading sprite data
    defineCharacterTypes(metadata)

    print("Loaded " .. metadata.totalSprites .. " sprites from atlas")

    local size = metadata.uniformWidth / 2
    local vertices = {{-size, -size, 0, 0}, {size, -size, 1, 0}, {size, size, 1, 1}, {-size, size, 0, 1}}

    mesh = love.graphics.newMesh(vertices, "fan", "stream")
    litmesh = love.graphics.newMesh(vertices, "fan", "stream")
    mesh:setTexture(texture)
    litmesh:setTexture(texture)

    -- Instance format for 3x3 matrix
    local instanceFormat = {{"InstanceUVData", "float", 4}, {"color", "float", 4}, {"InstanceMatrix1", "float", 3},
                            {"InstanceMatrix2", "float", 3}, {"InstanceMatrix4", "float", 3}, {"onoff", "float", 1} -- bit repr for each instance
    }

    local emptyInstanceData = {}
    for i = 1, characterAnimator.instanceCount * 17 do -- 17 floats per instance
        table.insert(emptyInstanceData, {0})
    end

    instanceMesh = love.graphics.newMesh(instanceFormat, emptyInstanceData, nil, "stream")
    mesh:attachAttribute("InstanceUVData", instanceMesh, "perinstance")
    mesh:attachAttribute("color", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceMatrix1", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceMatrix2", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceMatrix4", instanceMesh, "perinstance")
    mesh:attachAttribute("onoff", instanceMesh, "perinstance")

    litmesh:attachAttribute("InstanceUVData", instanceMesh, "perinstance")
    litmesh:attachAttribute("color", instanceMesh, "perinstance")
    litmesh:attachAttribute("InstanceMatrix1", instanceMesh, "perinstance")
    litmesh:attachAttribute("InstanceMatrix2", instanceMesh, "perinstance")
    litmesh:attachAttribute("InstanceMatrix4", instanceMesh, "perinstance")
    litmesh:attachAttribute("onoff", instanceMesh, "perinstance")

    -- Create instances with character types
    instances = {}
    local characterTypes = getCharacterTypes()

    for i = 1, characterAnimator.instanceCount do
        local instance = createInstance()
        instance.x = love.math.random(0, love.graphics.getWidth() * 2)
        instance.y = love.math.random(0, love.graphics.getHeight() * 2)

        -- Randomly assign character types
        local randomCharType = characterTypes[math.random(1, #characterTypes)]
        -- local randomCharType = characterTypes[1]
        -- instance.setCharacterType(randomCharType)
        instance.setCharacterType("princess")

        -- Randomly choose direction if the character supports multiple directions
        if instance.currentSpriteIndex then
            local stateData = spriteTypes[instance.currentSpriteIndex]
            instance.currentDirection = love.math.random(1, stateData.directions)
        end

        instance.color = {1, 1, 1, 0}
    end

    print("Created " .. #instances .. " instances with character types")

    princess = instances[1]
    -- table.remove(instances, 1)
    princess.setCharacterType("princess")

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
        characterAnimator.createAndSaveAtlas(imageFiles, config, frameWidth, frameHeight, atlasFilename,
            metadataFilename)
        return characterAnimator.loadFromAtlas(atlasFilename, metadataFilename)
    end
end

-- Calculate UV coordinates from direction and frame
local function getUV(instance)
    if not instance.currentSpriteIndex then
        return 0, 0, 0.1, 0.1
    end

    local spriteType = spriteTypes[instance.currentSpriteIndex]
    local offset = frameOffsets[instance.currentSpriteIndex]
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
    local activeInstanceCount = 0

    for i, instance in ipairs(instances) do
        if instance.currentSpriteIndex and spriteTypes[instance.currentSpriteIndex] then
            activeInstanceCount = activeInstanceCount + 1
            sortedIndices[activeInstanceCount] = i
        end
    end

    table.sort(sortedIndices, function(a, b)
        return instances[a].y < instances[b].y
    end)

    -- Build instance data, pad to full instanceCount to prevent stale/ghost sprites
    local instanceData = {}
    local totalInstances = characterAnimator.instanceCount
    local defaultUV = {0, 0, 0.001, 0.001}  -- tiny UV to avoid sampling wrong texture

    for i = 1, totalInstances do
        if i <= activeInstanceCount then
            local instance = instances[sortedIndices[i]]
            local cos_r = math.cos(instance.rotation)
            local sin_r = math.sin(instance.rotation)
            local scale = instance.scale

            local u, v, uSize, vSize = getUV(instance)

            instanceData[i] = {u, v, uSize, vSize, -- InstanceUVData
            instance.color[1], instance.color[2], instance.color[3], instance.color[4],
            cos_r * scale, sin_r * scale, 0,       -- InstanceMatrix1
            -sin_r * scale, cos_r * scale, 0,       -- InstanceMatrix2
            instance.x, instance.y, 1,               -- InstanceMatrix4
            instance.on and 1 or 0}
        else
            -- Disabled padding entry (onoff=0 means shader skips it)
            instanceData[i] = {defaultUV[1], defaultUV[2], defaultUV[3], defaultUV[4],
            1, 1, 1, 0,
            1, 0, 0,
            0, 1, 0,
            -10000, -10000, 1,
            0}
        end
    end

    instanceMesh:setVertices(instanceData)
end

function characterAnimator.draw()
    -- yellowNeon.godsray.light_x ,yellowNeon.godsray.light_y = gun.lastAimDirection.x, gun.lastAimDirection.y

    if var.graphics_high then -- wont be toggle will light up when hit with bullets or spells
        love.graphics.push()
        love.graphics.reset()

        yellowNeon.godsray.exposure = math.abs(math.sin(fire.t))
        yellowNeon(function()
            local camPos = {camera.pos.x, camera.pos.y, camera.zoom}
            -- camPos[0] = {camera.pos.x,camera.pos.y}
            -- camPos[1] = {camera.pos.y}
            characterAnimator.shaderWithTransforms:send("cameraPosition", camPos)
            love.graphics.setShader(characterAnimator.shaderWithTransforms)
            love.graphics.drawInstanced(mesh, characterAnimator.instanceCount)
            love.graphics.setShader()

        end)
        love.graphics.pop()
    end
    -- else 

    love.graphics.setShader(characterAnimator.shader)
    love.graphics.drawInstanced(mesh, characterAnimator.instanceCount)
    love.graphics.setShader()

    -- end

end

-- Helper functions to interact with instances
function characterAnimator.getCharacterTypes()
    return getCharacterTypes()
end

function characterAnimator.getAnimationsForCharacter(characterType)
    local charDef = characterDefinitions[characterType]
    if not charDef then
        return {}
    end

    local animations = {}
    for animName, _ in pairs(charDef.animations) do
        table.insert(animations, animName)
    end
    return animations
end

-- Example usage functions for testing
function characterAnimator.testAnimationSwitching()
    if #instances > 0 then
        local instance = instances[1]
        if instance.characterType == "watchman" then
            -- Cycle through watchman animations
            local animations = {"idle", "walk", "shoot", "jump", "punch", "cast", "death"}
            local currentIndex = 1
            for _, anim in ipairs(animations) do
                if anim == instance.currentAnimation then
                    currentIndex = math.min(currentIndex + 1, #animations)
                    break
                end
                currentIndex = currentIndex + 1
            end
            if currentIndex > #animations then
                currentIndex = 1
            end
            instance.setAnimation(animations[currentIndex])
            print("Switched to animation: " .. animations[currentIndex])
        elseif instance.characterType == "princess" then
            -- Cycle through princess animations
            local animations = {"walk", "run", "shoot", "jump", "roll"}
            local currentIndex = 1
            for _, anim in ipairs(animations) do
                if anim == instance.currentAnimation then
                    currentIndex = math.min(currentIndex + 1, #animations)
                    break
                end
                currentIndex = currentIndex + 1
            end
            if currentIndex > #animations then
                currentIndex = 1
            end
            instance.setAnimation(animations[currentIndex])
            print("Switched to animation: " .. animations[currentIndex])
        end
    end
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
