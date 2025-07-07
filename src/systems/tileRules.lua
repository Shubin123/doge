-- Pattern-based tile placement system
local TileRules = {}

-- Define tile patterns where 0 indicates a row break
-- TileRules.patterns = {
--     -- 1x2 patterns
--     [1] = {2, 3},           -- horizontal 1x2
--     [2] = {2, 0, 3},        -- vertical 2x1 (0 indicates new row)


--     -- 3x3 pattern example
--     [3] = {6, 7, 8, 0, 10, 11, 12, 0, 15, 16, 17}, -- 3x3 with row breaks
--     [6] = {4,6, 8, 0, 10, 11, 12, 0, 15, 17}, -- 3x3 with row breaks

--     -- 2x1 pattern example
--     [4] = {1,1,1},        -- vertical 2x1
--     [5] = {4}
--     -- [0] =
-- }

TileRules.patterns = {
    -- -- 1x2 patterns
    -- [1] = { 1, 2, 3, 0, 9, 10, 11, 0, 17, 18, 19 }, -- horizontal 1x2
    -- [2] = {145,167,147},
    -- [2] = {154},

    -- [4] = {170},  --stairs

    -- [3] = {48},
    -- [2] = {121,122,123},
    [5] = {121 ,122 ,123 ,0 ,129 ,130 ,131 ,0 ,137 ,138 ,139  },
    -- [5] = {145,146,147,0,153,154,155,0,161,162,163},

    -- [6] = {148,0,156,0,164},
    -- [7] = {149,150,151},
    -- [8] = {149,175,151},
    -- [9] = {149,176,151},
    -- [10] = {154}, -- debug tiles

    -- [10] = {160},


    -- [8] = {175}

}


-- for i in l:
--     if i != 0:
--         print(i-24,",",end="")
--     else:
--         print(0,",",end="")



-- Parse pattern into 2D structure
function TileRules.parsePattern(pattern)
    local rows = { {} }
    local currentRow = 1

    for _, value in ipairs(pattern) do
        if value == 0 then
            currentRow = currentRow + 1
            table.insert(rows, {})
        else
            table.insert(rows[currentRow], value)
        end
    end

    return rows
end

-- Get pattern dimensions
function TileRules.getPatternSize(pattern)
    local rows = TileRules.parsePattern(pattern)
    local height = #rows
    local width = 0

    for _, row in ipairs(rows) do
        if #row > width then
            width = #row
        end
    end

    return width, height
end

-- Check if pattern can fit at position
function TileRules.canFitPattern(map, x, y, pattern)
    local width, height = TileRules.getPatternSize(pattern)

    -- Check bounds
    if x + width - 1 > 700 or y + height - 1 > 900 then
        return false
    end

    -- Check if area is empty (assuming 0 or nil means empty)
    local rows = TileRules.parsePattern(pattern)
    for rowIdx, row in ipairs(rows) do
        for colIdx, tileId in ipairs(row) do
            local checkX = x + colIdx - 1
            local checkY = y + rowIdx - 1
            local existingTile = map:getTile(checkX, checkY)
            if existingTile and existingTile > 0 then
                return false
            end
        end
    end

    return true
end

-- Place pattern at position
function TileRules.placePattern(map, x, y, pattern)
    local rows = TileRules.parsePattern(pattern)

    for rowIdx, row in ipairs(rows) do
        for colIdx, tileId in ipairs(row) do
            local placeX = x + colIdx - 1
            local placeY = y + rowIdx - 1
            map:setTile(placeX, placeY, tileId)
        end
    end
end

-- Get valid tile for position considering patterns
function TileRules.getValidTile(x, y)
    -- Check if this position is already filled
    local existingTile = map.map:getTile(x, y)
    if existingTile and existingTile > 0 then
        return existingTile
    end

    -- Try to find a pattern that can start at this position
    local availablePatterns = {}

    for tileId, pattern in pairs(TileRules.patterns) do
        if TileRules.canFitPattern(map.map, x, y, pattern) then
            table.insert(availablePatterns, { tile = tileId, pattern = pattern })
        end
    end

    -- If patterns can fit, randomly choose one and place it
    if #availablePatterns > 0 then
        local chosen = availablePatterns[math.random(1, #availablePatterns)]
        TileRules.placePattern(map.map, x, y, chosen.pattern)

        -- Return the actual tile that was placed at position (x,y)
        local rows = TileRules.parsePattern(chosen.pattern)
        return rows[1][1] -- First tile in the pattern (top-left)
    end

    -- Fallback: place single tile if no patterns fit
    return math.random(1, 17)
end

-- Modified placement system that respects patterns
function TileRules.generateMapWithPatterns(map)
    for y = 1, 900 do
        for x = 1, 700 do
            -- Only try to place if position is empty
            local existingTile = map:getTile(x, y)
            if not existingTile or existingTile == 0 then
                local tileId = TileRules.getValidTile(x, y)
                -- Note: tile might already be placed by pattern placement
                if not map:getTile(x, y) or map:getTile(x, y) == 0 then
                    map:setTile(x, y, tileId)
                end
            end
        end
    end
end

-- Usage in your existing code:
--[[
local tilesetImage = love.graphics.newImage("gfx/TileSet/grounds.png")
map.tiles = newTiles(tilesetImage, var.tile_w, var.tile_h)
map.map = createMap(map.tiles, var.map_display_w, var.map_display_h)

-- Instead of the double loop with math.random(1,17):
TileRules.generateMapWithPatterns(map.map)

-- OR if you want to keep your existing loop structure:
for x = 1, 700 do
    for y = 1, 900 do
        local existingTile = map.map:getTile(x, y)
        if not existingTile or existingTile == 0 then
            map.map:setTile(x, y, TileRules.getValidTile(map.map, x, y))
        end
    end
end
--]]

return TileRules
