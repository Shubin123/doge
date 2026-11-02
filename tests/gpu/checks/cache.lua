--[[
  The load-time cache (util/cache.lua) gives back what working it out gives:

      python3 tests/gpu/run.py --checks --only cache

  1. a cached image's pixels are the PNG's;
  2. a region's grass from the cache is the grass grown fresh: the same
     patches, blade counts and vertices, and it loads faster;
  3. a sound's cached mono mix is the mp3 mixed down;
  4. a file's stamp changes when it does.
]]
return function(h)
    local cache = require("util.cache")
    h.advance(2)

    -- 1. Images
    local path = "gfx/regions/neon.png"
    local fresh = love.image.newImageData(path)
    cache.imageData(path) -- stores it, if it wasn't already
    local cached = cache.imageData(path)
    h.check("a cached image is the PNG's pixels", cached:getWidth() == fresh:getWidth()
        and cached:getHeight() == fresh:getHeight() and cached:getFormat() == fresh:getFormat()
        and cached:getString() == fresh:getString(),
        string.format("%dx%d %s", cached:getWidth(), cached:getHeight(), cached:getFormat()))

    -- 2. Region grass: grown fresh (nothing cached), then from the cache
    local function regionFields()
        local list = {}
        for i, f in ipairs(grass.public.fields()) do
            if f.grassMesh then
                local n = f.grassMesh:getVertexCount()
                local sample = {}
                for _, v in ipairs({ 1, math.floor(n / 2), n }) do
                    for _, c in ipairs({ f.grassMesh:getVertex(v) }) do sample[#sample + 1] = c end
                end
                list[#list + 1] = { f.x, f.y, f.width, f.height, f.grassCount, table.concat(sample, ",") }
            end
        end
        return list
    end
    local function reload()
        grass.public.load()
        local start = os.clock()
        regions.load()
        return os.clock() - start
    end
    for _, item in ipairs(love.filesystem.getDirectoryItems("cache")) do
        if item:find("^grass%-") then love.filesystem.remove("cache/" .. item) end
    end
    local grownIn = reload()
    local grown = regionFields()
    local hasCache = love.filesystem.getInfo("cache/grass-neon") ~= nil
    local cachedIn = reload()
    local fromCache = regionFields()
    h.check("growing a region's grass caches it", hasCache)
    local same = #grown == #fromCache and #grown > 0
    for i = 1, math.min(#grown, #fromCache) do
        for k = 1, 6 do
            if grown[i][k] ~= fromCache[i][k] then same = false end
        end
    end
    h.check("grass from the cache is the grass grown fresh", same,
        string.format("%d patches grown, %d from the cache", #grown, #fromCache))
    h.check("and loads faster", cachedIn < grownIn * 0.5,
        string.format("regions.load %.0f ms grown, %.0f ms from the cache", grownIn * 1000, cachedIn * 1000))

    -- 3. Sounds: the cached mono mix is the mp3's two channels averaged
    local mp3 = "/audio/fire.mp3"
    audio.loadSounds() -- stores it, if it wasn't already
    local stored = cache.get("sound_" .. mp3:gsub("[^%w%.%-]", "_") .. ".lz4", cache.key(cache.stamp(mp3), "mono"))
    local ok = stored ~= nil
    local detail = "not cached"
    if stored then
        local frames, rate, bits, start = love.data.unpack("<I4I4I1", stored)
        local pcm = love.data.decompress("data", "lz4", stored:sub(start))
        local decoded = love.sound.newSoundData(mp3)
        local mono = love.sound.newSoundData(frames, rate, bits, 1)
        local ffi = require("ffi")
        ffi.copy(mono:getFFIPointer(), pcm:getFFIPointer(), pcm:getSize())
        ok = frames == decoded:getSampleCount() and rate == decoded:getSampleRate()
        local worst = 0
        for i = 0, frames - 1, 97 do
            local want = decoded:getChannelCount() == 1 and decoded:getSample(i)
                or (decoded:getSample(i, 1) + decoded:getSample(i, 2)) * 0.5
            worst = math.max(worst, math.abs(mono:getSample(i) - want))
        end
        ok = ok and worst <= 1.5 / 32767 -- (a 16-bit sample is within a step of it)
        detail = string.format("%d frames at %d Hz, worst sample off by %.6f", frames, rate, worst)
    end
    h.check("a sound's cached mono mix is the mp3 mixed down", ok, detail)

    -- 4. Stamps
    love.filesystem.write("stamp-check.txt", "one")
    local before = cache.stamp("stamp-check.txt")
    love.filesystem.write("stamp-check.txt", "three")
    local after = cache.stamp("stamp-check.txt")
    love.filesystem.remove("stamp-check.txt")
    h.check("a file's stamp changes with it", before and after and before ~= after, tostring(before) .. " / " .. tostring(after))
    h.check("and there's none for no file", cache.stamp("no-such-file") == nil)
end
