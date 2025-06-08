local EntityFactory = {}

local enemy = require("enemy")
local character_manager = require("character_manager")
local collectible = require("collectible")
local interactable = require("interactable")

--- Spawn all entities defined in a map.
-- @param entityDefs table containing:
--    enemies = { { type, x, y, properties = { ... } }, ... },
--    collectibles = { { type, x, y, properties = { ... } }, ... },
--    interactables = { { type, x, y, properties = { ... } }, ... },
--    playerSpawn = { x, y }
-- @param context table containing necessary context, e.g. context.world
-- @return table of spawned handles:
--    {
--      enemies = { { index=idx, body=body, properties=def }, ... },
--      collectibles = { handle1, handle2, ... },
--      interactables = { handle1, handle2, ... },
--      player = playerInstance or nil
--    }
function EntityFactory.spawnEntities(entityDefs, context)
    local spawned = {
        enemies = {},
        collectibles = {},
        interactables = {},
        player = nil
    }

    -- Spawn enemies
    if entityDefs.enemies then
        for _, def in ipairs(entityDefs.enemies) do
            -- def.type, def.x, def.y, def.properties
            -- enemy.addEnemy returns (enemyIndex, enemyBody)
            local idx, body = enemy.addEnemy(def.x, def.y, def.type)
            table.insert(spawned.enemies, {
                index = idx,
                body = body,
                properties = def.properties or def
            })
        end
    end

    -- Spawn collectibles
    if entityDefs.collectibles then
        for _, def in ipairs(entityDefs.collectibles) do
            -- Expect collectible.spawn(type, x, y, properties, context) -> handle
            local handle = collectible.spawn(def.type, def.x, def.y, def.properties or def, context)
            table.insert(spawned.collectibles, handle)
        end
    end

    -- Spawn interactables
    if entityDefs.interactables then
        for _, def in ipairs(entityDefs.interactables) do
            -- Expect interactable.spawn(type, x, y, properties, context) -> handle
            local handle = interactable.spawn(def.type, def.x, def.y, def.properties or def, context)
            table.insert(spawned.interactables, handle)
        end
    end

    -- Spawn player at designated spawn point
    if entityDefs.playerSpawn then
        local px = entityDefs.playerSpawn.x
        local py = entityDefs.playerSpawn.y
        -- character_manager.create_player_instance(world, character_id, x, y)
        local playerInstance = character_manager.create_player_instance(
            context.world,
            nil,
            px,
            py
        )
        spawned.player = playerInstance
    end

    return spawned
end

return EntityFactory