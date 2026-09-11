local p2p_permissions = {}

-- Player permission management for P2P multiplayer
local player_permissions = {}
local is_host = false
local host_player_id = nil

-- Permission levels
local PERMISSION_LEVELS = {
    GUEST = 1,
    PLAYER = 2,
    ADMIN = 3,
    DEVELOPER = 4
}

-- Initialize P2P permission system
function p2p_permissions.init(is_hosting, my_player_id)
    is_host = is_hosting
    
    if is_host then
        -- Host starts as developer level
        host_player_id = my_player_id
        player_permissions[my_player_id] = PERMISSION_LEVELS.DEVELOPER
    else
        -- Joining players start as player level
        player_permissions[my_player_id] = PERMISSION_LEVELS.PLAYER
    end
end

-- Get permission level for a specific player
function p2p_permissions.getPlayerPermission(player_id)
    return player_permissions[player_id] or PERMISSION_LEVELS.GUEST
end

-- Set permission level for a player (only host can do this)
function p2p_permissions.setPlayerPermission(target_player_id, level, requesting_player_id)
    requesting_player_id = requesting_player_id or host_player_id
    
    -- Only host can change permissions
    if requesting_player_id ~= host_player_id then
        return false, "Only the host can change permissions"
    end
    
    -- Validate permission level
    if type(level) ~= "number" or level < 1 or level > 4 then
        return false, "Invalid permission level (1-4)"
    end
    
    -- Can't demote yourself as host
    if target_player_id == host_player_id and level < PERMISSION_LEVELS.DEVELOPER then
        return false, "Host cannot demote themselves"
    end
    
    player_permissions[target_player_id] = level
    
    -- Broadcast permission change to all players
    p2p_permissions.broadcastPermissionChange(target_player_id, level)
    
    return true, "Permission updated"
end

-- Check if current player is host
function p2p_permissions.isHost(player_id)
    return player_id == host_player_id
end

-- Get all player permissions (for host menu)
function p2p_permissions.getAllPermissions()
    return player_permissions
end

-- Add a new player (when someone joins)
function p2p_permissions.addPlayer(player_id, is_joining_player)
    if is_joining_player then
        -- New players start as PLAYER level
        player_permissions[player_id] = PERMISSION_LEVELS.PLAYER
    end
    
    -- Notify host of new player
    if is_host then
        return true, "New player added with PLAYER permissions"
    end
    
    return true, "Player joined"
end

-- Remove a player (when someone leaves)
function p2p_permissions.removePlayer(player_id)
    player_permissions[player_id] = nil
    
    -- If host leaves, transfer host to another player
    if player_id == host_player_id then
        p2p_permissions.transferHost()
    end
end

-- Transfer host to another player
function p2p_permissions.transferHost()
    -- Find highest permission player to become new host
    local new_host = nil
    local highest_level = 0
    
    for player_id, level in pairs(player_permissions) do
        if level > highest_level then
            highest_level = level
            new_host = player_id
        end
    end
    
    if new_host then
        host_player_id = new_host
        player_permissions[new_host] = PERMISSION_LEVELS.DEVELOPER
        is_host = (new_host == var.multiplayer) -- Check if we're the new host
        
        p2p_permissions.broadcastHostTransfer(new_host)
    end
end

-- Create host permission menu data
function p2p_permissions.createHostMenu()
    if not is_host then
        return nil, "You are not the host"
    end
    
    local menu_data = {
        title = "Player Permissions",
        players = {}
    }
    
    local level_names = {"Guest", "Player", "Admin", "Developer"}
    
    for player_id, level in pairs(player_permissions) do
        table.insert(menu_data.players, {
            id = player_id,
            name = "Player " .. tostring(player_id),
            current_level = level,
            current_level_name = level_names[level],
            is_host = (player_id == host_player_id)
        })
    end
    
    return menu_data
end

-- Console commands for permission management
function p2p_permissions.handleConsoleCommand(cmd, requesting_player_id)
    local level_names = {"Guest", "Player", "Admin", "Developer"}
    
    -- List all players and their permissions
    if cmd == "perms.list" then
        local output = {}
        table.insert(output, "{cyan}Player Permissions:{/cyan}")
        
        for player_id, level in pairs(player_permissions) do
            local is_host_marker = (player_id == host_player_id) and " {yellow}(HOST){/yellow}" or ""
            local line = string.format("  Player %s: {green}%d{/green} (%s)%s", 
                tostring(player_id), level, level_names[level], is_host_marker)
            table.insert(output, line)
        end
        
        return true, output
    end
    
    -- Grant permission to a player
    if cmd:match("^perms%.grant%s+%d+%s+%d+$") then
        local target_id, level = cmd:match("perms%.grant%s+(%d+)%s+(%d+)")
        target_id = tonumber(target_id)
        level = tonumber(level)
        
        local success, message = p2p_permissions.setPlayerPermission(target_id, level, requesting_player_id)
        
        if success then
            return true, {string.format("{green}Granted %s level %d (%s){/green}", 
                tostring(target_id), level, level_names[level])}
        else
            return false, {"{red}" .. message .. "{/red}"}
        end
    end
    
    -- Show current player's permission
    if cmd == "perms.me" then
        local my_level = p2p_permissions.getPlayerPermission(requesting_player_id)
        local is_host_text = p2p_permissions.isHost(requesting_player_id) and " {yellow}(HOST){/yellow}" or ""
        
        return true, {string.format("{cyan}Your permission level: {green}%d{/green} (%s)%s{/cyan}", 
            my_level, level_names[my_level], is_host_text)}
    end
    
    return false, {"{red}Unknown permission command{/red}"}
end

-- Network message handlers
function p2p_permissions.broadcastPermissionChange(player_id, new_level)
    if not multiplayer or not multiplayer.broadcast then return end
    
    local message = {
        type = "permission_change",
        player_id = player_id,
        new_level = new_level,
        timestamp = love.timer.getTime()
    }
    
    multiplayer.broadcast(json.encode(message))
end

function p2p_permissions.broadcastHostTransfer(new_host_id)
    if not multiplayer or not multiplayer.broadcast then return end
    
    local message = {
        type = "host_transfer",
        new_host_id = new_host_id,
        timestamp = love.timer.getTime()
    }
    
    multiplayer.broadcast(json.encode(message))
end

function p2p_permissions.handleNetworkMessage(message_data)
    if message_data.type == "permission_change" then
        player_permissions[message_data.player_id] = message_data.new_level
        return true
    elseif message_data.type == "host_transfer" then
        host_player_id = message_data.new_host_id
        is_host = (message_data.new_host_id == var.multiplayer)
        return true
    end
    
    return false
end

-- Get permission constants for external use
function p2p_permissions.getPermissionLevels()
    return PERMISSION_LEVELS
end

-- Get current user's permission (for sandbox integration)
function p2p_permissions.getCurrentUserPermission()
    local my_id = var.multiplayer or 1
    return p2p_permissions.getPlayerPermission(my_id)
end

return p2p_permissions