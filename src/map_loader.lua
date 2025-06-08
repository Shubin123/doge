-- local MapDescriptor = require("src.map_descriptor")
local map_loader = {}

-- Map file format constants
local MAP_HEADER = "DOGE_MAP"
local MAP_VERSION = "1.0"

-- Load a map from a file
function map_loader.loadFromFile(filePath)
    local content, size = love.filesystem.read(filePath)
    if not content then
        error("Could not open map file: " .. filePath)
    end
    -- Parse the map data
    local mapData = map_loader.parseMapData(content)
    return mapData
end

-- Parse map data from string content
function map_loader.parseMapData(content)
    local mapData = {
        header = "",
        version = "",
        metadata = {},
        tileset = "",
        tileWidth = 16,
        tileHeight = 16,
        mapWidth = 0,
        mapHeight = 0,
        tileData = {},
        enemies = {},
        collectibles = {},
        playerSpawn = {x = 0, y = 0},
        interactables = {}
    }

    -- Split content into lines
    local lines = {}
    for line in content:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    -- Parse header
    if #lines < 2 then
        error("Invalid map file: Missing header")
    end

    mapData.header = lines[1]
    mapData.version = lines[2]

    if mapData.header ~= MAP_HEADER then
        error("Invalid map file: Wrong header format")
    end

    -- Parse metadata
    local currentSection = nil
    for i = 3, #lines do
        local line = lines[i]
        
        -- Skip empty lines
        if line:match("^%s*$") then
            goto continue
        end

        -- Check for section headers
        if line:match("^%[.*%]$") then
            currentSection = line:match("^%[(.*)%]$")
            goto continue
        end

        -- Parse sections
        if currentSection == "metadata" then
            local key, value = line:match("([^=]+)=(.+)")
            if key and value then
                mapData.metadata[key:trim()] = value:trim()
            end
        elseif currentSection == "tileset" then
            mapData.tileset = line
        elseif currentSection == "dimensions" then
            local width, height = line:match("(%d+)x(%d+)")
            if width and height then
                mapData.mapWidth = tonumber(width)
                mapData.mapHeight = tonumber(height)
            end
        elseif currentSection == "tiles" then
            local row = {}
            for tile in line:gmatch("%d+") do
                table.insert(row, tonumber(tile))
            end
            table.insert(mapData.tileData, row)
        elseif currentSection == "enemies" then
            local enemyData = map_loader.parseEntityData(line)
            if enemyData then
                table.insert(mapData.enemies, enemyData)
            end
        elseif currentSection == "collectibles" then
            local collectibleData = map_loader.parseEntityData(line)
            if collectibleData then
                table.insert(mapData.collectibles, collectibleData)
            end
        elseif currentSection == "player_spawn" then
            local x, y = line:match("(%d+),(%d+)")
            if x and y then
                mapData.playerSpawn = {
                    x = tonumber(x),
                    y = tonumber(y)
                }
            end
        elseif currentSection == "interactables" then
            local interactableData = map_loader.parseEntityData(line)
            if interactableData then
                table.insert(mapData.interactables, interactableData)
            end
        end

        ::continue::
    end

    return mapData
end

-- Parse entity data from a line
function map_loader.parseEntityData(line)
    local data = {}
    local parts = {}
    for part in line:gmatch("[^,]+") do
        table.insert(parts, part:trim())
    end

    if #parts >= 3 then
        data.type = parts[1]
        data.x = tonumber(parts[2])
        data.y = tonumber(parts[3])
        
        -- Parse additional properties
        for i = 4, #parts do
            local key, value = parts[i]:match("([^=]+)=(.+)")
            if key and value then
                data[key:trim()] = value:trim()
            end
        end
        
        return data
    end
    
    return nil
end

-- Save a map to a file
function map_loader.saveToFile(mapData, filePath)
    local file = io.open(filePath, "w")
    if not file then
        error("Could not create map file: " .. filePath)
    end

    -- Write header
    file:write(MAP_HEADER .. "\n")
    file:write(MAP_VERSION .. "\n\n")

    -- Write metadata
    file:write("[metadata]\n")
    for key, value in pairs(mapData.metadata) do
        file:write(string.format("%s=%s\n", key, value))
    end
    file:write("\n")

    -- Write tileset
    file:write("[tileset]\n")
    file:write(mapData.tileset .. "\n\n")

    -- Write dimensions
    file:write("[dimensions]\n")
    file:write(string.format("%dx%d\n\n", mapData.mapWidth, mapData.mapHeight))

    -- Write tiles
    file:write("[tiles]\n")
    for _, row in ipairs(mapData.tileData) do
        local line = table.concat(row, ",")
        file:write(line .. "\n")
    end
    file:write("\n")

    -- Write enemies
    if #mapData.enemies > 0 then
        file:write("[enemies]\n")
        for _, enemy in ipairs(mapData.enemies) do
            local line = string.format("%s,%d,%d", enemy.type, enemy.x, enemy.y)
            for key, value in pairs(enemy) do
                if key ~= "type" and key ~= "x" and key ~= "y" then
                    line = line .. string.format(",%s=%s", key, value)
                end
            end
            file:write(line .. "\n")
        end
        file:write("\n")
    end

    -- Write collectibles
    if #mapData.collectibles > 0 then
        file:write("[collectibles]\n")
        for _, collectible in ipairs(mapData.collectibles) do
            local line = string.format("%s,%d,%d", collectible.type, collectible.x, collectible.y)
            for key, value in pairs(collectible) do
                if key ~= "type" and key ~= "x" and key ~= "y" then
                    line = line .. string.format(",%s=%s", key, value)
                end
            end
            file:write(line .. "\n")
        end
        file:write("\n")
    end

    -- Write player spawn
    file:write("[player_spawn]\n")
    file:write(string.format("%d,%d\n\n", mapData.playerSpawn.x, mapData.playerSpawn.y))

    -- Write interactables
    if #mapData.interactables > 0 then
        file:write("[interactables]\n")
        for _, interactable in ipairs(mapData.interactables) do
            local line = string.format("%s,%d,%d", interactable.type, interactable.x, interactable.y)
            for key, value in pairs(interactable) do
                if key ~= "type" and key ~= "x" and key ~= "y" then
                    line = line .. string.format(",%s=%s", key, value)
                end
            end
            file:write(line .. "\n")
        end
    end

    file:close()
end

return map_loader
