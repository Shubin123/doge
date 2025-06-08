-- src/physics_builder.lua

local PhysicsBuilder = {}

-- Build static physics bodies for the map:
-- 1) World boundary loop
-- 2) Individual collidable tiles (non-zero tile IDs)
-- 3) Chain shapes if provided in mapDef.chainShapes
function PhysicsBuilder.buildPhysics(mapDef, world)
    -- Helpers for unpack (Lua 5.1 vs 5.2+)
    local unpack = table.unpack or unpack

    -- Read tile size and world offset from metadata (defaults if missing)
    local m = mapDef.metadata or {}
    local tileWidth  = tonumber(m.tile_width ) or 32
    local tileHeight = tonumber(m.tile_height) or tileWidth
    local offsetX    = tonumber(m.world_x    ) or 0
    local offsetY    = tonumber(m.world_y    ) or 0

    -- Compute map dimensions in pixels
    local mapW = (mapDef.mapWidth  or 0) * tileWidth
    local mapH = (mapDef.mapHeight or 0) * tileHeight

    local physicsObjects = {}

    -- 1) World boundary as closed loop chain shape
    do
        local body = love.physics.newBody(world, 0, 0, "static")
        local pts = {
            offsetX,          offsetY,
            offsetX + mapW,   offsetY,
            offsetX + mapW,   offsetY + mapH,
            offsetX,          offsetY + mapH
        }
        local shape = love.physics.newChainShape(true, unpack(pts))
        local fixture = love.physics.newFixture(body, shape)
        table.insert(physicsObjects, { body = body, fixture = fixture, shape = shape })
    end

    -- 2) Collidable tiles: any numeric tile > 0
    if mapDef.tileData then
        for rowIdx, row in ipairs(mapDef.tileData) do
            for colIdx, tile in ipairs(row) do
                if type(tile) == "number" and tile > 0 then
                    local cx = offsetX + (colIdx - 1) * tileWidth + tileWidth * 0.5
                    local cy = offsetY + (rowIdx - 1) * tileHeight + tileHeight * 0.5
                    local body = love.physics.newBody(world, cx, cy, "static")
                    local shape = love.physics.newRectangleShape(tileWidth, tileHeight)
                    local fixture = love.physics.newFixture(body, shape)
                    table.insert(physicsObjects, { body = body, fixture = fixture, shape = shape })
                end
            end
        end
    end

    -- 3) Additional chain shapes (if any)
    if mapDef.chainShapes and type(mapDef.chainShapes) == "table" then
        for _, chain in ipairs(mapDef.chainShapes) do
            if chain.points and #chain.points >= 4 then
                local body = love.physics.newBody(world, 0, 0, "static")
                local shape = love.physics.newChainShape(chain.loop == true, unpack(chain.points))
                local fixture = love.physics.newFixture(body, shape)
                table.insert(physicsObjects, { body = body, fixture = fixture, shape = shape })
            end
        end
    end

    return physicsObjects
end

return PhysicsBuilder