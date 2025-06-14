-- pause.lua - Comprehensive pause system for multiplayer

local pause = {}

-- Pause states
local PauseState = {
    NONE = "none",
    HOST_PAUSE = "host_pause",     -- Host-initiated game-wide pause
    CLIENT_PAUSE = "client_pause",  -- Client local pause (rendering only)
    SYNC_PAUSE = "sync_pause"       -- System pause for sync operations
}

-- Module state
local state = {
    current_state = PauseState.NONE,
    previous_state = PauseState.NONE,
    pause_time = 0,
    stored_game_state = nil,
    pause_overlay_alpha = 0,
    pause_reason = "",
    can_unpause = true,
    network_handlers_registered = false
}

-- References
local multiplayer = nil
local modSystem = nil
local var = nil
local snapshot = nil
local notifications = nil

-- Configuration
local CONFIG = {
    overlay_fade_speed = 5,
    overlay_max_alpha = 0.7,
    notification_duration = 3000,
    sync_pause_timeout = 5000
}

-- Initialize the pause system
function pause.init(mp, mod_sys, vars, snap)
    multiplayer = mp
    modSystem = mod_sys
    var = vars
    snapshot = snap
    
    -- Try to get notifications API if available
    if modSystem and modSystem.getGlobalAPI then
        local api = modSystem.getGlobalAPI()
        if api and api.notifications then
            notifications = api.notifications
        end
    end
    
    -- Register network handlers if multiplayer is active
    if multiplayer and var.multiplayer and var.multiplayer ~= 0 and not state.network_handlers_registered then
        pause.registerNetworkHandlers()
        state.network_handlers_registered = true
    end
end

-- Register network message handlers
function pause.registerNetworkHandlers()
    -- Host sends pause command to all clients
    if var.multiplayer == 1 then -- Host
        -- No need to register handler for host sending
    else -- Client
        -- Clients receive pause commands from host
        multiplayer:onMessage("pause_command", function(message, peer, role)
            if message.command == "pause" then
                pause.handleHostPause(message.reason)
            elseif message.command == "unpause" then
                pause.handleHostUnpause()
            elseif message.command == "sync_pause" then
                pause.handleSyncPause(message.reason)
            elseif message.command == "sync_unpause" then
                pause.handleSyncUnpause()
            end
        end)
    end
end

-- Check if the game is paused
function pause.isPaused()
    return state.current_state ~= PauseState.NONE
end

-- Check if gameplay should be frozen
function pause.isGameplayPaused()
    return state.current_state == PauseState.HOST_PAUSE or 
           state.current_state == PauseState.SYNC_PAUSE
end

-- Check if rendering should be paused
function pause.isRenderingPaused()
    return state.current_state ~= PauseState.NONE
end

-- Get current pause state
function pause.getState()
    return state.current_state
end

-- Get pause reason
function pause.getReason()
    return state.pause_reason
end

-- Toggle pause (called when ESC is pressed)
function pause.toggle()
    if state.current_state == PauseState.NONE then
        if var.multiplayer == 1 then
            -- Host initiates game-wide pause
            pause.hostPause("Host paused the game")
        elseif var.multiplayer == 2 then
            -- Client initiates local pause
            pause.clientPause("Local pause")
        else
            -- Single player pause
            pause.localPause("Game paused")
        end
    else
        -- Try to unpause
        pause.tryUnpause()
    end
end

-- Host pauses the entire game
function pause.hostPause(reason)
    if var.multiplayer ~= 1 then return false end
    
    state.previous_state = state.current_state
    state.current_state = PauseState.HOST_PAUSE
    state.pause_reason = reason or "Host paused"
    state.pause_time = love.timer.getTime()
    
    -- Send pause command to all clients
    local message = {
        type = "pause_command",
        command = "pause",
        reason = state.pause_reason
    }
    
    -- Compress and send
    local json_string = json.encode(message)
    local compressed_data = love.data.compress("string", "zlib", json_string, 9)
    multiplayer:broadcast(compressed_data)
    
    -- Show notification
    if notifications then
        notifications.showWarning("Game Paused", state.pause_reason, CONFIG.notification_duration)
    end
    
    -- Notify mods about pause
    if modSystem then
        modSystem.notifyPause(true)
    end
    
    return true
end

-- Client pauses locally
function pause.clientPause(reason)
    if var.multiplayer ~= 2 then return false end
    
    -- Store current game state for resync
    state.stored_game_state = snapshot.create()
    
    state.previous_state = state.current_state
    state.current_state = PauseState.CLIENT_PAUSE
    state.pause_reason = reason or "Local pause"
    state.pause_time = love.timer.getTime()
    
    -- Show notification
    if notifications then
        notifications.showInfo("Local Pause", "Rendering paused locally", CONFIG.notification_duration)
    end
    
    return true
end

-- Local pause (single player)
function pause.localPause(reason)
    if var.multiplayer and var.multiplayer ~= 0 then return false end
    
    state.previous_state = state.current_state
    state.current_state = PauseState.HOST_PAUSE -- Use host pause for single player
    state.pause_reason = reason or "Game paused"
    state.pause_time = love.timer.getTime()
    
    -- Notify mods about pause
    if modSystem then
        modSystem.notifyPause(true)
    end
    
    return true
end

-- System-initiated sync pause
function pause.syncPause(reason)
    state.previous_state = state.current_state
    state.current_state = PauseState.SYNC_PAUSE
    state.pause_reason = reason or "Synchronizing..."
    state.pause_time = love.timer.getTime()
    state.can_unpause = false -- Cannot manually unpause sync pauses
    
    -- If host, notify all clients
    if var.multiplayer == 1 then
        local message = {
            type = "pause_command",
            command = "sync_pause",
            reason = state.pause_reason
        }
        
        local json_string = json.encode(message)
        local compressed_data = love.data.compress("string", "zlib", json_string, 9)
        multiplayer:broadcast(compressed_data)
    end
    
    -- Show notification
    if notifications then
        notifications.showInfo("Synchronizing", state.pause_reason, CONFIG.sync_pause_timeout)
    end
    
    -- Notify mods about pause
    if modSystem then
        modSystem.notifyPause(true)
    end
    
    return true
end

-- Try to unpause
function pause.tryUnpause()
    if not state.can_unpause then
        if notifications then
            notifications.showError("Cannot Unpause", "Wait for synchronization to complete", 2000)
        end
        return false
    end
    
    if state.current_state == PauseState.HOST_PAUSE and var.multiplayer == 1 then
        -- Host unpauses for everyone
        pause.hostUnpause()
    elseif state.current_state == PauseState.CLIENT_PAUSE and var.multiplayer == 2 then
        -- Client unpauses locally
        pause.clientUnpause()
    elseif state.current_state == PauseState.HOST_PAUSE and not var.multiplayer then
        -- Single player unpause
        pause.localUnpause()
    end
end

-- Host unpauses the game
function pause.hostUnpause()
    if var.multiplayer ~= 1 or state.current_state ~= PauseState.HOST_PAUSE then return false end
    
    state.current_state = PauseState.NONE
    state.pause_reason = ""
    
    -- Send unpause command to all clients
    local message = {
        type = "pause_command",
        command = "unpause"
    }
    
    local json_string = json.encode(message)
    local compressed_data = love.data.compress("string", "zlib", json_string, 9)
    multiplayer:broadcast(compressed_data)
    
    -- Show notification
    if notifications then
        notifications.showSuccess("Game Resumed", "Host resumed the game", 2000)
    end
    
    -- Notify mods about unpause
    if modSystem then
        modSystem.notifyPause(false)
    end
    
    return true
end

-- Client unpauses locally
function pause.clientUnpause()
    if var.multiplayer ~= 2 or state.current_state ~= PauseState.CLIENT_PAUSE then return false end
    
    state.current_state = PauseState.NONE
    state.pause_reason = ""
    
    -- Request resync from host if needed
    if state.stored_game_state then
        -- Could implement resync request here
        state.stored_game_state = nil
    end
    
    -- Show notification
    if notifications then
        notifications.showSuccess("Resumed", "Local rendering resumed", 2000)
    end
    
    return true
end

-- Local unpause (single player)
function pause.localUnpause()
    if var.multiplayer and var.multiplayer ~= 0 then return false end
    
    state.current_state = PauseState.NONE
    state.pause_reason = ""
    
    -- Notify mods about unpause
    if modSystem then
        modSystem.notifyPause(false)
    end
    
    return true
end

-- System unpauses from sync
function pause.syncUnpause()
    if state.current_state ~= PauseState.SYNC_PAUSE then return false end
    
    state.current_state = PauseState.NONE
    state.pause_reason = ""
    state.can_unpause = true
    
    -- If host, notify all clients
    if var.multiplayer == 1 then
        local message = {
            type = "pause_command",
            command = "sync_unpause"
        }
        
        local json_string = json.encode(message)
        local compressed_data = love.data.compress("string", "zlib", json_string, 9)
        multiplayer:broadcast(compressed_data)
    end
    
    -- Show notification
    if notifications then
        notifications.showSuccess("Sync Complete", "Synchronization finished", 2000)
    end
    
    -- Notify mods about unpause
    if modSystem then
        modSystem.notifyPause(false)
    end
    
    return true
end

-- Handle host pause command (client side)
function pause.handleHostPause(reason)
    state.previous_state = state.current_state
    state.current_state = PauseState.HOST_PAUSE
    state.pause_reason = reason or "Host paused the game"
    state.pause_time = love.timer.getTime()
    
    -- Show notification
    if notifications then
        notifications.showWarning("Game Paused", state.pause_reason, CONFIG.notification_duration)
    end
    
    -- Notify mods about pause
    if modSystem then
        modSystem.notifyPause(true)
    end
end

-- Handle host unpause command (client side)
function pause.handleHostUnpause()
    if state.current_state == PauseState.HOST_PAUSE then
        state.current_state = PauseState.NONE
        state.pause_reason = ""
        
        -- Show notification
        if notifications then
            notifications.showSuccess("Game Resumed", "Host resumed the game", 2000)
        end
        
        -- Notify mods about unpause
        if modSystem then
            modSystem.notifyPause(false)
        end
    end
end

-- Handle sync pause command (client side)
function pause.handleSyncPause(reason)
    state.previous_state = state.current_state
    state.current_state = PauseState.SYNC_PAUSE
    state.pause_reason = reason or "Synchronizing..."
    state.pause_time = love.timer.getTime()
    state.can_unpause = false
    
    -- Show notification
    if notifications then
        notifications.showInfo("Synchronizing", state.pause_reason, CONFIG.sync_pause_timeout)
    end
    
    -- Notify mods about pause
    if modSystem then
        modSystem.notifyPause(true)
    end
end

-- Handle sync unpause command (client side)
function pause.handleSyncUnpause()
    if state.current_state == PauseState.SYNC_PAUSE then
        state.current_state = PauseState.NONE
        state.pause_reason = ""
        state.can_unpause = true
        
        -- Show notification
        if notifications then
            notifications.showSuccess("Sync Complete", "Synchronization finished", 2000)
        end
        
        -- Notify mods about unpause
        if modSystem then
            modSystem.notifyPause(false)
        end
    end
end

-- Update pause overlay animation
function pause.update(dt)
    -- Update overlay alpha
    if pause.isPaused() then
        state.pause_overlay_alpha = math.min(CONFIG.overlay_max_alpha, 
            state.pause_overlay_alpha + dt * CONFIG.overlay_fade_speed)
    else
        state.pause_overlay_alpha = math.max(0, 
            state.pause_overlay_alpha - dt * CONFIG.overlay_fade_speed)
    end
    
    -- Check for sync timeout
    if state.current_state == PauseState.SYNC_PAUSE then
        local elapsed = (love.timer.getTime() - state.pause_time) * 1000
        if elapsed > CONFIG.sync_pause_timeout then
            -- Force unpause after timeout
            pause.syncUnpause()
            if notifications then
                notifications.showWarning("Sync Timeout", "Synchronization timed out", 2000)
            end
        end
    end
end

-- Draw pause overlay
function pause.draw()
    if state.pause_overlay_alpha > 0 then
        -- Draw dark overlay
        love.graphics.setColor(0, 0, 0, state.pause_overlay_alpha)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        
        -- Draw pause text
        love.graphics.setColor(1, 1, 1, state.pause_overlay_alpha)
        local font = love.graphics.getFont()
        local text = "PAUSED"
        local text_width = font:getWidth(text)
        local text_height = font:getHeight()
        
        -- Draw main pause text
        love.graphics.print(text, 
            love.graphics.getWidth() / 2 - text_width / 2,
            love.graphics.getHeight() / 2 - text_height / 2 - 20)
        
        -- Draw pause reason
        if state.pause_reason ~= "" then
            local reason_width = font:getWidth(state.pause_reason)
            love.graphics.print(state.pause_reason,
                love.graphics.getWidth() / 2 - reason_width / 2,
                love.graphics.getHeight() / 2 - text_height / 2 + 10)
        end
        
        -- Draw instructions
        local instructions = ""
        if state.current_state == PauseState.HOST_PAUSE then
            if var.multiplayer == 1 then
                instructions = "Press ESC to resume for all players"
            else
                instructions = "Press ESC to resume"
            end
        elseif state.current_state == PauseState.CLIENT_PAUSE then
            instructions = "Press ESC to resume locally"
        elseif state.current_state == PauseState.SYNC_PAUSE then
            instructions = "Please wait..."
        end
        
        if instructions ~= "" then
            local inst_width = font:getWidth(instructions)
            love.graphics.print(instructions,
                love.graphics.getWidth() / 2 - inst_width / 2,
                love.graphics.getHeight() / 2 - text_height / 2 + 40)
        end
    end
end

return pause