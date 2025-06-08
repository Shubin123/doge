-- src/loading_coordinator.lua
local map_manager = require("map_manager")

local loading_coordinator = {}

-- Callback registries
local startCallbacks = {}
local progressCallbacks = {}
local completeCallbacks = {}

-- Internal progress handler
local function onMapProgress(stage, progress, message)
    -- Convert to percent
    local percent = math.floor(progress * 100)
    for _, cb in ipairs(progressCallbacks) do
        cb(percent, message)
    end
end

-- Register a callback for when loading starts
function loading_coordinator.registerStart(callback)
    assert(type(callback) == "function", "Start callback must be a function")
    table.insert(startCallbacks, callback)
end

-- Register a callback for progress updates
-- Callback signature: function(percent, message)
function loading_coordinator.registerProgress(callback)
    assert(type(callback) == "function", "Progress callback must be a function")
    table.insert(progressCallbacks, callback)
end

-- Register a callback for when loading completes
-- Callback signature: function(success, err)
function loading_coordinator.registerComplete(callback)
    assert(type(callback) == "function", "Complete callback must be a function")
    table.insert(completeCallbacks, callback)
end

-- Start loading a map by ID
function loading_coordinator.startLoading(mapId)
    assert(type(mapId) == "string" and mapId ~= "", "startLoading requires a valid map ID")
    -- Notify start
    for _, cb in ipairs(startCallbacks) do
        cb()
    end
    -- Subscribe to map_manager progress events
    map_manager.addProgressCallback(onMapProgress)
    -- Kick off map loading
    map_manager.switchToMap(mapId, function(success, err)
        -- Unsubscribe progress handler
        map_manager.removeProgressCallback(onMapProgress)
        -- Notify completion
        for _, cb in ipairs(completeCallbacks) do
            cb(success, err)
        end
    end)
end

return loading_coordinator