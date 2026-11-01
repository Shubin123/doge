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
