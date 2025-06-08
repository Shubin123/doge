-- src/map_parser.lua

local map_parser = {}

-- Trim whitespace from both ends of a string
local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

-- Split a string by a given separator
local function split(s, sep)
    local parts = {}
    local pattern = "([^" .. sep .. "]+)"
    for token in s:gmatch(pattern) do
        parts[#parts + 1] = token
    end
    return parts
end

-- Parse raw map file content into a structured MapDefinition table
function map_parser.parseMapData(content)
    local mapDef = {
        metadata     = {},
        tileset      = "",
        mapWidth     = 0,
        mapHeight    = 0,
        tileData     = {},
        enemies      = {},
        collectibles = {},
        interactables= {},
        playerSpawn  = { x = 0, y = 0 },
    }

    local section

    for rawLine in content:gmatch("[^\r\n]+") do
        local line = trim(rawLine)
        if line == "" then
            -- skip empty lines
        else
            local newSec = line:match("^%[(.-)%]$")
            if newSec then
                -- Enter new section
                section = newSec
            elseif not section then
                -- Skip anything before the first [section]
            else
                -- Handle content based on current section
                if section == "metadata" then
                    local key, value = line:match("^(.-)=(.*)$")
                    if key and value then
                        mapDef.metadata[trim(key)] = trim(value)
                    end

                elseif section == "tileset" then
                    mapDef.tileset = line

                elseif section == "dimensions" then
                    local w, h = line:match("^(%d+)x(%d+)$")
                    mapDef.mapWidth  = tonumber(w) or 0
                    mapDef.mapHeight = tonumber(h) or 0

                elseif section == "tiles" then
                    local row = {}
                    for cell in line:gmatch("([^,]+)") do
                        cell = trim(cell)
                        local num = tonumber(cell)
                        row[#row + 1] = (num ~= nil) and num or cell
                    end
                    table.insert(mapDef.tileData, row)

                elseif section == "enemies"
                   or section == "collectibles"
                   or section == "interactables" then

                    local parts = split(line, ",")
                    if #parts >= 3 then
                        local obj = {
                            type = trim(parts[1]),
                            x    = tonumber(trim(parts[2])) or trim(parts[2]),
                            y    = tonumber(trim(parts[3])) or trim(parts[3]),
                        }
                        -- Additional key=value properties
                        for i = 4, #parts do
                            local kv = trim(parts[i])
                            local k, v = kv:match("^(.-)=(.*)$")
                            if k and v then
                                v = trim(v)
                                local num = tonumber(v)
                                obj[trim(k)] = (num ~= nil) and num or v
                            end
                        end
                        table.insert(mapDef[section], obj)
                    end

                elseif section == "player_spawn" then
                    local x, y = line:match("^(%-?%d+),%s*(%-?%d+)$")
                    mapDef.playerSpawn.x = tonumber(x) or 0
                    mapDef.playerSpawn.y = tonumber(y) or 0
                end
            end
        end
    end

    return mapDef
end

return map_parser