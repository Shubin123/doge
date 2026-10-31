--[[
  Save / load. A save is the whole game state as JSON, zlib-compressed, in
  LÖVE's save directory. Only LÖVE builtins touch the disk (love.filesystem,
  love.data), never io/os paths, so it works wherever LÖVE does: desktop,
  fused apps whose own folder is read-only, mobile, and the browser build
  (where the save directory is IndexedDB).

  Systems with more than a handful of fields own their snapshot format
  (map.createSaveData / map.restore, enemy.getSaveData / enemy.restore,
  boss.getSaveData / boss.restore, command.getCommandBlocks /
  command.setCommandBlocks); this module gathers them and applies them.
]]
local serial = {}

serial.VERSION = 2
serial.EXTENSION = ".sav"
serial.QUICKSAVE = "quicksave" .. serial.EXTENSION

local function captureCoins()
    local coins = {}
    for _, body in ipairs(coin_bods) do
        if not body:isDestroyed() then
            local x, y = body:getPosition()
            local vx, vy = body:getLinearVelocity()
            local fixture = body:getFixtures()[1]
            local data = fixture and fixture:getUserData()
            table.insert(coins, {
                x = x, y = y, vx = vx, vy = vy,
                -- Merged coins carry their grown size and summed value
                size = type(data) == "table" and data.size or nil,
                value = type(data) == "table" and data.value or nil,
            })
        end
    end
    return coins
end

local function restoreCoins(coins)
    for _, body in ipairs(coin_bods) do
        if not body:isDestroyed() then
            body:destroy()
        end
    end
    coin_bods = {}
    -- createCoin inserts at the front, so go backwards to keep the order
    for i = #coins, 1, -1 do
        local c = coins[i]
        local body, fixture = createCoin(c.x, c.y)
        body:setLinearVelocity(c.vx or 0, c.vy or 0)
        if c.size or c.value then
            fixture:setUserData({ size = c.size, value = c.value })
        end
    end
    var.num_coins = #coins
end

local function captureCars()
    local cars = {}
    for i, c in ipairs(car.cars) do
        local x, y = c.body:getPosition()
        local vx, vy = c.body:getLinearVelocity()
        cars[i] = { x = x, y = y, vx = vx, vy = vy, angle = c.body:getAngle() }
    end
    return cars
end

local function restoreCars(cars)
    for i, saved in ipairs(cars) do
        local c = car.cars[i]
        if c and c.body then
            c.body:setPosition(saved.x, saved.y)
            c.body:setLinearVelocity(saved.vx or 0, saved.vy or 0)
            c.body:setAngle(saved.angle or 0)
        end
    end
end

-- The whole game state as plain, JSON-encodable data.
function serial.create()
    local px, py = player.body:getPosition()
    local pvx, pvy = player.body:getLinearVelocity()

    return {
        version = serial.VERSION,
        timestamp = os.time(),
        platform = love.system.getOS(),

        player = {
            x = px, y = py, vx = pvx, vy = pvy,
            health = player.health,
            lights_on = player.lightsOn,
        },
        inventory = {
            weapon = gun.currentWeaponIndex,
            ammo = gun.ammo,
            fireballs = fire.getAvailableCount(),
            fireball_regen = fire.regen_timer,
        },
        world = {
            score = var.player_score,
            indoors = var.indoors,
        },
        map = map.createSaveData(),
        coins = captureCoins(),
        enemies = enemy.getSaveData(),
        bosses = boss.getSaveData(),
        cars = captureCars(),
        command_blocks = command.getCommandBlocks(),
    }
end

-- Put the game into a state produced by serial.create.
function serial.apply(state)
    if type(state) ~= "table" or state.version ~= serial.VERSION then
        return false, "Unsupported save version " .. tostring(type(state) == "table" and state.version)
    end

    -- The world first, then what lives in it
    if state.map and not map.restore(state.map) then
        return false, "Failed to restore map data"
    end
    if state.coins then restoreCoins(state.coins) end
    if state.enemies then enemy.restore(state.enemies) end
    if state.bosses then boss.restore(state.bosses) end
    if state.cars then restoreCars(state.cars) end
    if state.command_blocks then command.setCommandBlocks(state.command_blocks) end

    local p = state.player
    if p then
        player.body:setPosition(p.x, p.y)
        player.body:setLinearVelocity(p.vx or 0, p.vy or 0)
        player.health = p.health or player.maxHealth
        player.lightsOn = p.lights_on ~= false
    end

    local inv = state.inventory
    if inv then
        gun.switchGun(inv.weapon or 1)
        gun.ammo = math.min(inv.ammo or gun.maxAmmo, gun.maxAmmo)
        local fireballs = math.min(inv.fireballs or 0, fire.max_fireballs)
        while fire.getAvailableCount() > fireballs do fire.removeFireball() end
        while fire.getAvailableCount() < fireballs do fire.addFireball() end
        fire.regen_timer = inv.fireball_regen or 0
    end

    if state.world then
        var.player_score = state.world.score or 0
        var.indoors = state.world.indoors or false
    end

    return true, "Save loaded"
end

-- Read and decode a save file; nil and a message on failure.
local function readState(filename)
    if not love.filesystem.getInfo(filename, "file") then
        return nil, "Save file not found: " .. filename
    end
    local contents, err = love.filesystem.read(filename)
    if not contents then
        return nil, "Failed to read " .. filename .. ": " .. tostring(err)
    end
    -- Saves are compressed; saveToFileUncompressed writes plain JSON
    local inflated, text = pcall(love.data.decompress, "string", "zlib", contents)
    local ok, state = pcall(json.decode, inflated and text or contents)
    if not ok or type(state) ~= "table" then
        return nil, "Failed to parse " .. filename
    end
    return state
end

local function encodeState()
    local ok, result = pcall(function() return json.encode(serial.create()) end)
    if not ok then
        return nil, "Failed to capture game state: " .. tostring(result)
    end
    return result
end

-- Save game state to a file in the save directory
function serial.saveToFile(filename)
    local encoded, err = encodeState()
    if not encoded then return false, err end

    local written, writeErr = love.filesystem.write(filename, love.data.compress("data", "zlib", encoded, 9))
    if not written then
        return false, "Failed to write " .. filename .. ": " .. tostring(writeErr)
    end
    return true, "Game saved to " .. love.filesystem.getSaveDirectory() .. "/" .. filename
end

-- Same as saveToFile but human-readable JSON, for debugging; loads the same way
function serial.saveToFileUncompressed(filename)
    local encoded, err = encodeState()
    if not encoded then return false, err end

    local written, writeErr = love.filesystem.write(filename, encoded)
    if not written then
        return false, "Failed to write " .. filename .. ": " .. tostring(writeErr)
    end
    return true, "Game saved to " .. love.filesystem.getSaveDirectory() .. "/" .. filename
end

-- Load game state from a file in the save directory
function serial.loadFromFile(filename)
    local state, err = readState(filename)
    if not state then return false, err end

    local ok, applied, message = pcall(serial.apply, state)
    if not ok then
        return false, "Failed to apply save: " .. tostring(applied)
    end
    return applied, message
end

-- Saves in the save directory, newest first
function serial.getSaveFiles()
    local save_files = {}
    for _, filename in ipairs(love.filesystem.getDirectoryItems("")) do
        if filename:sub(-#serial.EXTENSION) == serial.EXTENSION then
            local info = love.filesystem.getInfo(filename, "file")
            if info then
                table.insert(save_files, {
                    filename = filename,
                    size = info.size or 0,
                    modified = info.modtime or 0
                })
            end
        end
    end

    table.sort(save_files, function(a, b)
        return a.modified > b.modified
    end)

    return save_files
end

function serial.deleteSave(filename)
    return love.filesystem.remove(filename)
end

function serial.quickSave()
    local ok, message = serial.saveToFile(serial.QUICKSAVE)
    print(message)
    return ok, message
end

function serial.quickLoad()
    local ok, message = serial.loadFromFile(serial.QUICKSAVE)
    print(message)
    return ok, message
end

-- Summary of a save file without loading it
function serial.getSaveInfo(filename)
    local state, err = readState(filename)
    if not state then return nil, err end

    local alive = 0
    for _, slot in ipairs(state.enemies and state.enemies.slots or {}) do
        if not slot.dead then alive = alive + 1 end
    end
    local map_data = state.map or {}

    return {
        version = state.version,
        timestamp = state.timestamp or 0,
        platform = state.platform,
        score = state.world and state.world.score or 0,
        health = state.player and state.player.health,
        ammo = state.inventory and state.inventory.ammo,
        enemy_count = alive,
        boss_count = state.bosses and #state.bosses or 0,
        coin_count = state.coins and #state.coins or 0,
        arch_count = map_data.arches and #map_data.arches or 0,
        tree_count = map_data.trees and #map_data.trees or 0,
        house_count = map_data.houses and #map_data.houses or 0,
        has_map_tiles = map_data.base_tiles ~= nil,
    }, "Success"
end

return serial
