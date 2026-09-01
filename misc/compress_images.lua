-- DEPRECATED / superseded by tools/pack_atlas.py — this was a one-off,
-- hardcoded-file-list zlib compressor for gfx/3d -> gfx/3dC that predates
-- the atlas pipeline entirely and was never wired into anything that
-- actually runs. Left here for reference only.
-- Image Compressor for game assets
local compress = {}

-- Function to ensure directory exists (Note: This is limited with io, may need manual creation)
local function ensureDirectoryExists(dir)
    -- With io, we can't create directories directly in a cross-platform way
    -- This function is a placeholder; directories may need to be created manually
    print("Please ensure the directory " .. dir .. " exists, as io cannot create directories.")
end

-- Function to compress images from source to destination folder
function compress.compressFolder(sourceDir, destDir)
    ensureDirectoryExists(destDir)
    
    local count = 0
    local totalSizeBefore = 0
    local totalSizeAfter = 0
    
    -- Hardcoded list of files since io doesn't provide directory listing
    local files = {
        "apple_2.png",
        "commodore64.png",
        "gun.png",
        "portalGun.png",
        "skybox.png"
    }
    
    for _, file in ipairs(files) do
        local sourcePath = sourceDir .. "/" .. file
        local destPath = destDir .. "/" .. file
        
        -- Read the original image data
        local f = io.open(sourcePath, "rb")
        if f then
            local imageData = f:read("*all")
            f:close()
            
            totalSizeBefore = totalSizeBefore + #imageData
            
            -- Compress the image data using zlib
            local compressedData = love.data.compress("string", "zlib", imageData, 9)
            
            totalSizeAfter = totalSizeAfter + #compressedData
            
            -- Write compressed data to destination
            f = io.open(destPath, "wb")
            if f then
                f:write(compressedData)
                f:close()
                count = count + 1
                print("Compressed: " .. file .. " (Original: " .. #imageData .. " bytes, Compressed: " .. #compressedData .. " bytes)")
            else
                print("Failed to write compressed file: " .. destPath)
            end
        else
            print("Failed to read file: " .. sourcePath)
        end
    end
    
    print("Compression complete. Processed " .. count .. " files.")
    print("Total size before: " .. totalSizeBefore .. " bytes")
    print("Total size after: " .. totalSizeAfter .. " bytes")
    print("Reduction: " .. string.format("%.2f", (totalSizeBefore - totalSizeAfter) / totalSizeBefore * 100) .. "%")
    
    return count
end

-- Function to decompress a single file (for testing or integration)
function compress.decompressFile(compressedPath)
    local f = io.open(compressedPath, "rb")
    if not f then
        print("Failed to read compressed file: " .. compressedPath)
        return nil
    end
    
    local compressedData = f:read("*all")
    f:close()
    
    local success, decompressedData = pcall(love.data.decompress, "string", "zlib", compressedData)
    if not success then
        print("Failed to decompress file: " .. compressedPath)
        return nil
    end
    
    return decompressedData
end

-- Main execution for compressing gfx/3d to gfx/3dC
local sourceDir = "src/gfx/3d"
local destDir = "src/gfx/3dC"
print("Starting compression of images from " .. sourceDir .. " to " .. destDir)
compress.compressFolder(sourceDir, destDir)

return compress
