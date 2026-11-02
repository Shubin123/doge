--[[
  Load-time cache: things that are slow to work out at startup but only
  change when the code or art behind them does (the courtyard's tile
  layout, the sprite atlas unpacked), kept in the save directory's cache/
  folder so the next launch reads them back instead.

  Each entry is stored under a key, a hash of everything it was worked out
  from (cache.key); one whose key doesn't match, or that didn't finish
  writing, is ignored and worked out again. So deleting cache/ is always
  safe, and editing the code or art never shows a stale result.

  Nothing else lives in cache/: saves are *.sav (util/serial.lua) and
  settings are settings.json (util/settings.lua), both beside it.
]]
local cache = {}

cache.DIR = "cache"
cache.VERSION = 1 -- bump to drop every entry (a change to this file's format)

local function path(name)
    return cache.DIR .. "/" .. name
end

--- A key for data worked out from the given parts (strings or numbers):
--- the same parts give the same key, any change gives another.
function cache.key(...)
    local parts = { cache.VERSION, love.getVersion() }
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    return love.data.encode("string", "hex", love.data.hash("md5", table.concat(parts, "\0")))
end

--- A file as a part for cache.key: its path, size and when it last changed.
--- Much quicker than its contents for a big file (hashing the 9 MB sprite
--- atlas took 25 ms a launch), and any edit, copy or checkout changes it.
--- Nil when there's no such file.
function cache.stamp(path)
    local info = love.filesystem.getInfo(path, "file")
    return info and (path .. " " .. info.size .. " " .. tostring(info.modtime)) or nil
end

--- The image file at `path` decoded (an ImageData), from a copy of its
--- pixels kept LZ4 packed after the first time: decoding a 2048 px PNG takes
--- about 10 ms, unpacking the copy one. The browser decodes it every time
--- (like the atlas, characterAnimator.lua) rather than keep a copy.
function cache.imageData(path)
    if love.system.getOS() == "Web" then return love.image.newImageData(path) end
    local name = "image_" .. path:gsub("[^%w%.%-]", "_") .. ".lz4"
    local key = cache.key(cache.stamp(path))
    local stored = cache.get(name, key)
    if stored then
        -- "<width><height><format>" then the pixels
        local ok, w, h, format, start = pcall(love.data.unpack, "<I4I4s1", stored)
        if ok then
            local unpacked, pixels = pcall(love.data.decompress, "data", "lz4", stored:sub(start))
            if unpacked then
                local made, data = pcall(love.image.newImageData, w, h, format, pixels)
                if made then return data end
            end
        end
    end
    local data = love.image.newImageData(path)
    cache.put(name, key, love.data.pack("string", "<I4I4s1", data:getWidth(), data:getHeight(), data:getFormat())
        .. love.data.compress("string", "lz4", data:getString()))
    return data
end

--- love.graphics.newImage(path, settings), its pixels from cache.imageData.
function cache.newImage(path, settings)
    return love.graphics.newImage(cache.imageData(path), settings)
end

--- The string stored as `name` under `key`; nil when there is none, it was
--- stored under another key, or it was cut short.
function cache.get(name, key)
    local contents = love.filesystem.getInfo(path(name), "file") and love.filesystem.read(path(name))
    if not contents then return nil end
    -- "<key> <length>\n" then the data
    local stamp, length, start = contents:match("^(%x+) (%d+)\n()")
    if stamp ~= key or #contents - start + 1 ~= tonumber(length) then return nil end
    return contents:sub(start)
end

--- Store `data` (a string) as `name` under `key`. Failing to (a full or
--- read-only disk) only means working it out again next time.
function cache.put(name, key, data)
    love.filesystem.createDirectory(cache.DIR)
    local ok, err = love.filesystem.write(path(name), key .. " " .. #data .. "\n" .. data)
    if not ok then print("cache: couldn't write " .. path(name) .. ": " .. tostring(err)) end
    return ok
end

return cache
