-- Utility function to serialize tables
local function serializeTable(val, name, skipnewlines, depth)
    skipnewlines = skipnewlines or false
    depth = depth or 0

    local tmp = string.rep(" ", depth)

    if name then 
        if type(name) == "number" then
            tmp = tmp .. "[" .. name .. "] = "
        else
            tmp = tmp .. name .. " = "
        end
    end

    if type(val) == "table" then
        tmp = tmp .. "{" .. (not skipnewlines and "\n" or "")

        for k, v in pairs(val) do
            tmp = tmp .. serializeTable(v, k, skipnewlines, depth + 1) .. "," .. (not skipnewlines and "\n" or "")
        end

        tmp = tmp .. string.rep(" ", depth) .. "}"
    elseif type(val) == "number" then
        tmp = tmp .. tostring(val)
    elseif type(val) == "string" then
        tmp = tmp .. string.format("%q", val)
    elseif type(val) == "boolean" then
        tmp = tmp .. (val and "true" or "false")
    else
        tmp = tmp .. "\"[inserializeable datatype:" .. type(val) .. "]\""
    end

    return tmp
end

-- Main stitching function
function stitchAtlas(oldAtlasPath, oldMetadataPath, newImageFiles, directionsConfig, frameWidth, frameHeight,
                     outputAtlasPath, outputMetadataPath)
    
    print("=== Atlas Stitching Process ===")
    print("Loading old atlas: " .. oldAtlasPath)
    print("Loading old metadata: " .. oldMetadataPath)
    
    -- Load old atlas and metadata
    local oldAtlasData = love.image.newImageData(oldAtlasPath)
    local oldMetadata = dofile(oldMetadataPath)
    
    if not oldAtlasData then
        error("Failed to load old atlas: " .. oldAtlasPath)
    end
    
    if not oldMetadata then
        error("Failed to load old metadata: " .. oldMetadataPath)
    end
    
    print("Old atlas size: " .. oldAtlasData:getWidth() .. "x" .. oldAtlasData:getHeight())
    print("Old atlas sprites: " .. (oldMetadata.totalSprites or 0))
    print("Old sprites per row: " .. (oldMetadata.spritesPerRow or 0))
    
    -- Extract uniform dimensions from old metadata
    local uniformWidth = oldMetadata.uniformWidth or frameWidth
    local uniformHeight = oldMetadata.uniformHeight or frameHeight
    
    print("Uniform sprite size: " .. uniformWidth .. "x" .. uniformHeight)
    
    -- Process new images
    local newSpriteData = {}
    local newFramesPerImageList = {}
    local newDirectionsPerImageList = {}
    
    print("\n=== Processing New Images ===")
    for i, filename in ipairs(newImageFiles) do
        local directions = directionsConfig[i]
        print("Processing " .. filename .. " with " .. directions .. " directions")
        
        local originalImageData = love.image.newImageData(filename)
        
        if originalImageData then
            local spriteWidth = frameWidth or (originalImageData:getWidth() / directions)
            local spriteHeight = frameHeight or spriteWidth
            local spritesX = directions
            local spritesY = math.floor(originalImageData:getHeight() / spriteHeight)
            
            local framesForThisImage = 0
            
            for sy = 0, spritesY - 1 do
                for sx = 0, spritesX - 1 do
                    local uniformImageData = love.image.newImageData(uniformWidth, uniformHeight)
                    local srcXStart = sx * spriteWidth
                    local srcYStart = sy * spriteHeight
                    
                    -- Resample sprite to uniform size
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
                    
                    table.insert(newSpriteData, uniformImageData)
                    framesForThisImage = framesForThisImage + 1
                end
            end
            
            print("  Extracted " .. framesForThisImage .. " frames")
            newFramesPerImageList[i] = framesForThisImage
            newDirectionsPerImageList[i] = directions
        else
            print("  Failed to load image: " .. filename)
            newFramesPerImageList[i] = 0
            newDirectionsPerImageList[i] = directions
        end
    end
    
    -- Calculate new atlas dimensions
    local oldSpritesCount = oldMetadata.totalSprites or 0
    local newSpritesCount = #newSpriteData
    local totalSprites = oldSpritesCount + newSpritesCount
    
    print("\n=== Creating New Atlas ===")
    print("Old sprites: " .. oldSpritesCount)
    print("New sprites: " .. newSpritesCount)
    print("Total sprites: " .. totalSprites)
    
    local spritesPerRow = math.ceil(math.sqrt(totalSprites))
    local textureWidth = spritesPerRow * uniformWidth
    local textureHeight = spritesPerRow * uniformHeight
    
    -- Ensure power of 2 dimensions
    textureWidth = math.pow(2, math.ceil(math.log(textureWidth) / math.log(2)))
    textureHeight = math.pow(2, math.ceil(math.log(textureHeight) / math.log(2)))
    spritesPerRow = math.floor(textureWidth / uniformWidth)
    
    print("New atlas size: " .. textureWidth .. "x" .. textureHeight)
    print("Sprites per row: " .. spritesPerRow)
    
    -- Create new atlas
    local newAtlasTexture = love.image.newImageData(textureWidth, textureHeight)
    
    -- Clear with transparent pixels
    for y = 0, textureHeight - 1 do
        for x = 0, textureWidth - 1 do
            newAtlasTexture:setPixel(x, y, 0, 0, 0, 0)
        end
    end
    
    -- Copy old atlas sprites
    print("\n=== Copying Old Sprites ===")
    local oldSpritesPerRow = oldMetadata.spritesPerRow
    print("Old sprites per row: " .. oldSpritesPerRow)
    
    for i = 0, oldSpritesCount - 1 do
        -- Calculate position in OLD atlas
        local oldRow = math.floor(i / oldSpritesPerRow)
        local oldCol = i % oldSpritesPerRow
        local srcX = oldCol * uniformWidth
        local srcY = oldRow * uniformHeight
        
        -- Calculate position in NEW atlas
        local newRow = math.floor(i / spritesPerRow)
        local newCol = i % spritesPerRow
        local destX = newCol * uniformWidth
        local destY = newRow * uniformHeight
        
        -- Debug output for first few sprites
        if i < 3 then
            print(string.format("  Sprite %d: old[%d,%d]->(%d,%d) new[%d,%d]->(%d,%d)", 
                i, oldCol, oldRow, srcX, srcY, newCol, newRow, destX, destY))
        end
        
        -- Copy sprite pixel by pixel
        for y = 0, uniformHeight - 1 do
            for x = 0, uniformWidth - 1 do
                local readX = srcX + x
                local readY = srcY + y
                
                if readX < oldAtlasData:getWidth() and readY < oldAtlasData:getHeight() then
                    local r, g, b, a = oldAtlasData:getPixel(readX, readY)
                    if destX + x < textureWidth and destY + y < textureHeight then
                        newAtlasTexture:setPixel(destX + x, destY + y, r, g, b, a)
                    end
                else
                    -- Out of bounds in old atlas
                    if i < 3 then
                        print(string.format("    WARNING: pixel (%d,%d) out of bounds", readX, readY))
                    end
                end
            end
        end
    end
    print("Copied " .. oldSpritesCount .. " old sprites")
    
    -- Add new sprites
    print("\n=== Adding New Sprites ===")
    for i, spriteData in ipairs(newSpriteData) do
        local spriteIndex = oldSpritesCount + i - 1
        local row = math.floor(spriteIndex / spritesPerRow)
        local col = spriteIndex % spritesPerRow
        local destX = col * uniformWidth
        local destY = row * uniformHeight
        
        if i <= 3 then
            print(string.format("  New sprite %d at [%d,%d]->(%d,%d)", i, col, row, destX, destY))
        end
        
        for y = 0, uniformHeight - 1 do
            for x = 0, uniformWidth - 1 do
                if destX + x < textureWidth and destY + y < textureHeight then
                    local r, g, b, a = spriteData:getPixel(x, y)
                    newAtlasTexture:setPixel(destX + x, destY + y, r, g, b, a)
                end
            end
        end
    end
    print("Added " .. newSpritesCount .. " new sprites")
    
    -- Save new atlas
    print("\n=== Saving New Atlas ===")
    local fileData = newAtlasTexture:encode("png")
    local success = pcall(function()
        local file = io.open(outputAtlasPath, "wb")
        if file then
            file:write(fileData:getString())
            file:close()
            print("Saved new atlas to: " .. outputAtlasPath .. " (in running directory)")
        else
            error("Could not open file for writing: " .. outputAtlasPath)
        end
    end)
    
    if not success then
        love.filesystem.write(outputAtlasPath, fileData)
        print("Saved new atlas to: " .. outputAtlasPath .. " (in LÖVE save directory)")
    end
    
    -- Merge metadata
    local mergedFramesPerImageList = {}
    local mergedDirectionsPerImageList = {}
    local mergedImageFiles = {}
    
    -- Add old metadata
    for i, frames in ipairs(oldMetadata.framesPerImageList or {}) do
        mergedFramesPerImageList[i] = frames
    end
    for i, dirs in ipairs(oldMetadata.directionsPerImageList or {}) do
        mergedDirectionsPerImageList[i] = dirs
    end
    for i, file in ipairs(oldMetadata.imageFiles or {}) do
        mergedImageFiles[i] = file
    end
    
    -- Add new metadata
    local oldCount = #mergedImageFiles
    for i, frames in ipairs(newFramesPerImageList) do
        mergedFramesPerImageList[oldCount + i] = frames
    end
    for i, dirs in ipairs(newDirectionsPerImageList) do
        mergedDirectionsPerImageList[oldCount + i] = dirs
    end
    for i, file in ipairs(newImageFiles) do
        mergedImageFiles[oldCount + i] = file
    end
    
    local newMetadata = {
        textureWidth = textureWidth,
        textureHeight = textureHeight,
        spritesPerRow = spritesPerRow,
        uniformWidth = uniformWidth,
        uniformHeight = uniformHeight,
        framesPerImageList = mergedFramesPerImageList,
        directionsPerImageList = mergedDirectionsPerImageList,
        imageFiles = mergedImageFiles,
        totalSprites = totalSprites
    }
    
    -- Save metadata
    local metadataString = "return " .. serializeTable(newMetadata)
    local success2 = pcall(function()
        local file = io.open(outputMetadataPath, "w")
        if file then
            file:write(metadataString)
            file:close()
            print("Saved new metadata to: " .. outputMetadataPath .. " (in running directory)")
        else
            error("Could not open file for writing: " .. outputMetadataPath)
        end
    end)
    
    if not success2 then
        love.filesystem.write(outputMetadataPath, metadataString)
        print("Saved new metadata to: " .. outputMetadataPath .. " (in LÖVE save directory)")
    end
    
    print("\n=== Stitching Complete ===")
    print("Total images in metadata: " .. #mergedImageFiles)
    return newMetadata
end

-- Example usage
--[[
stitchAtlas("gfx/atlas/oldatlas.png", "gfx/atlas/old_atlas_metadata.lua",
    { "gfx/3d/gun.png", "gfx/3d/lauchergun.png",
        "gfx/3d/portalGun.png", "gfx/vehicles/car.png",
        "gfx/vehicles/bike.png", "gfx/3d/apple_2.png",
        "gfx/3d/commodore64.png",            
        "gfx/TileSet/tree1.png", "gfx/TileSet/arch.png",
        "gfx/TileSet/coin128.png", "gfx/TileSet/house128.png",
        "gfx/watchmanOfDoom_lowres/walk.png", "gfx/watchmanOfDoom_lowres/shoot_pistol.png",
        "gfx/watchmanOfDoom_lowres/death.png", "gfx/watchmanOfDoom_lowres/punch.png",
        "gfx/watchmanOfDoom_lowres/cast.png", "gfx/watchmanOfDoom_lowres/idle.png",
        "gfx/watchmanOfDoom_lowres/jump.png",
        "gfx/3d/princess/walk copy.png", "gfx/3d/princess/run copy.png", "gfx/3d/princess/shoot copy.png",
        "gfx/3d/princess/jump copy.png", "gfx/3d/princess/roll3.png", "gfx/3d/animated2.png",
        "gfx/3d/steve/walk lowres.png",
        "gfx/3d/mech/mech_walklowlowres.png", "gfx/3d/mech/attack_lowres.png", "gfx/3d/mech/dying_lowres.png",
        "gfx/3d/mech/shoot_lowres.png" },
    { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8 }, 
    128, 128,
    "newatlas.png", "newatlas_metadata.lua")
--]]