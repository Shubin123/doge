function love.load()
    local filename = "bc5.dds"

    -- Load the raw DDS data using LÖVE
    local rawData, size = love.filesystem.read(filename)
    if not rawData then
        error("Failed to load DDS file: " .. filename)
    end
    print("Loaded:", filename, "Size:", size)

    -- Compress using zlib
    local compressedData = love.data.compress("data", "zlib", rawData, 9)
    local compressedString = compressedData:getString()

    -- Use io.open to write directly to the execution directory
    local outputFilename = filename .. ".zlib"
    local f = io.open(outputFilename, "wb")
    if not f then
        error("Failed to open file for writing: " .. outputFilename)
    end
    f:write(compressedString)
    f:close()

    print("Compressed file written directly to disk as:", outputFilename, "size: ",compressedData:getSize())

        -- Optional Step 4: Decompress to verify correctness
    local decompressedData = love.data.decompress("data", "zlib", compressedData)

    if decompressedData:getString() == rawData then
        print("✅ Decompression check passed (data matches)")
    else
        print("❌ Decompression check failed (data mismatch)")
    end
end