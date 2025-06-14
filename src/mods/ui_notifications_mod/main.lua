local uiNotificationsMod = {}

-- Notification types and their visual properties
local NOTIFICATION_TYPES = {
    info = {
        color = {0.2, 0.6, 1, 1},
        bg_color = {0.1, 0.3, 0.5, 0.9},
        icon = "ℹ"
    },
    warning = {
        color = {1, 0.8, 0.2, 1},
        bg_color = {0.5, 0.4, 0.1, 0.9},
        icon = "⚠"
    },
    error = {
        color = {1, 0.3, 0.3, 1},
        bg_color = {0.5, 0.15, 0.15, 0.9},
        icon = "✖"
    },
    success = {
        color = {0.3, 1, 0.3, 1},
        bg_color = {0.15, 0.5, 0.15, 0.9},
        icon = "✓"
    }
}

-- Module state
local notifications = {}
local notification_id_counter = 0
local api = nil
local config = nil
local font = nil
local title_font = nil

-- Easing function for smooth animations
local function easeOutCubic(t)
    t = t - 1
    return t * t * t + 1
end

-- Create a new notification
local function createNotification(type, title, message, duration, persistent, callback)
    notification_id_counter = notification_id_counter + 1
    
    local notification = {
        id = notification_id_counter,
        type = type,
        title = title,
        message = message,
        duration = duration or config.default_duration,
        persistent = persistent or false,
        callback = callback,
        created_at = love.timer.getTime() * 1000,
        animation_start = love.timer.getTime() * 1000,
        state = "entering", -- entering, visible, exiting, expired
        alpha = 0,
        x_offset = 0,
        y_offset = 0,
        target_y = 0,
        clicked_button = nil
    }
    
    -- Add to notifications list
    table.insert(notifications, 1, notification)
    
    -- Remove oldest notifications if exceeding max visible
    while #notifications > config.max_visible do
        local oldest = notifications[#notifications]
        if not oldest.persistent then
            oldest.state = "exiting"
            oldest.animation_start = love.timer.getTime() * 1000
        end
    end
    
    -- Update positions for all notifications
    updateNotificationPositions()
    
    return notification.id
end

-- Update target positions for all notifications
function updateNotificationPositions()
    local y_offset = config.position_y_offset
    
    for i, notification in ipairs(notifications) do
        if notification.state ~= "expired" then
            notification.target_y = y_offset
            y_offset = y_offset + config.notification_height + config.notification_spacing
        end
    end
end

-- Update notification animations and states
local function updateNotifications(dt)
    local current_time = love.timer.getTime() * 1000
    local notifications_changed = false
    
    for i = #notifications, 1, -1 do
        local notification = notifications[i]
        local animation_progress = (current_time - notification.animation_start) / config.animation_duration
        
        -- Update animation based on state
        if notification.state == "entering" then
            if animation_progress >= 1 then
                notification.state = "visible"
                notification.alpha = 1
                notification.x_offset = 0
            else
                local eased = easeOutCubic(animation_progress)
                notification.alpha = eased
                notification.x_offset = (1 - eased) * config.notification_width
            end
        elseif notification.state == "visible" then
            -- Check if non-persistent notification should expire
            if not notification.persistent and (current_time - notification.created_at) > notification.duration then
                notification.state = "exiting"
                notification.animation_start = current_time
            end
        elseif notification.state == "exiting" then
            if animation_progress >= 1 then
                notification.state = "expired"
                notifications_changed = true
            else
                local eased = 1 - easeOutCubic(animation_progress)
                notification.alpha = eased
                notification.x_offset = (1 - eased) * config.notification_width
            end
        elseif notification.state == "expired" then
            table.remove(notifications, i)
            notifications_changed = true
        end
        
        -- Smooth y position animation
        local y_diff = notification.target_y - notification.y_offset
        notification.y_offset = notification.y_offset + y_diff * dt * 10
    end
    
    if notifications_changed then
        updateNotificationPositions()
    end
end

-- Draw a single notification
local function drawNotification(notification, x, y)
    local type_config = NOTIFICATION_TYPES[notification.type]
    
    -- Draw background
    love.graphics.setColor(type_config.bg_color[1], type_config.bg_color[2], 
                          type_config.bg_color[3], type_config.bg_color[4] * notification.alpha)
    love.graphics.rectangle("fill", x, y, config.notification_width, config.notification_height, 8, 8)
    
    -- Draw border
    love.graphics.setColor(type_config.color[1], type_config.color[2], 
                          type_config.color[3], type_config.color[4] * notification.alpha)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, config.notification_width, config.notification_height, 8, 8)
    
    -- Draw icon
    love.graphics.setFont(title_font)
    love.graphics.print(type_config.icon, x + 10, y + 10)
    
    -- Draw title
    love.graphics.setColor(1, 1, 1, notification.alpha)
    love.graphics.print(notification.title, x + 40, y + 10)
    
    -- Draw message
    love.graphics.setFont(font)
    love.graphics.setColor(0.9, 0.9, 0.9, notification.alpha)
    love.graphics.printf(notification.message, x + 40, y + 35, config.notification_width - 50, "left")
    
    -- Draw buttons for persistent notifications
    if notification.persistent then
        local button_width = 60
        local button_height = 25
        local button_y = y + config.notification_height - button_height - 10
        
        -- Yes button
        local yes_x = x + config.notification_width - button_width * 2 - 15
        local yes_color = notification.clicked_button == "yes" and {0.3, 0.7, 0.3} or {0.2, 0.5, 0.2}
        love.graphics.setColor(yes_color[1], yes_color[2], yes_color[3], notification.alpha)
        love.graphics.rectangle("fill", yes_x, button_y, button_width, button_height, 4, 4)
        love.graphics.setColor(1, 1, 1, notification.alpha)
        love.graphics.printf("Yes", yes_x, button_y + 5, button_width, "center")
        
        -- No button
        local no_x = x + config.notification_width - button_width - 5
        local no_color = notification.clicked_button == "no" and {0.7, 0.3, 0.3} or {0.5, 0.2, 0.2}
        love.graphics.setColor(no_color[1], no_color[2], no_color[3], notification.alpha)
        love.graphics.rectangle("fill", no_x, button_y, button_width, button_height, 4, 4)
        love.graphics.setColor(1, 1, 1, notification.alpha)
        love.graphics.printf("No", no_x, button_y + 5, button_width, "center")
        
        -- Store button positions for click detection
        notification.yes_button = {x = yes_x, y = button_y, w = button_width, h = button_height}
        notification.no_button = {x = no_x, y = button_y, w = button_width, h = button_height}
    end
end

-- Handle mouse clicks on notifications
local function handleMousePressed(x, y, button)
    if button ~= 1 then return end
    
    local screen_width = love.graphics.getWidth()
    
    for _, notification in ipairs(notifications) do
        if notification.persistent and notification.state == "visible" then
            local notif_x = screen_width - config.notification_width - config.position_x_offset + notification.x_offset
            local notif_y = notification.y_offset
            
            -- Check yes button
            if notification.yes_button and 
               x >= notif_x + notification.yes_button.x and 
               x <= notif_x + notification.yes_button.x + notification.yes_button.w and
               y >= notif_y + notification.yes_button.y and 
               y <= notif_y + notification.yes_button.y + notification.yes_button.h then
                
                notification.clicked_button = "yes"
                if notification.callback then
                    notification.callback(true)
                end
                notification.state = "exiting"
                notification.animation_start = love.timer.getTime() * 1000
                return
            end
            
            -- Check no button
            if notification.no_button and
               x >= notif_x + notification.no_button.x and 
               x <= notif_x + notification.no_button.x + notification.no_button.w and
               y >= notif_y + notification.no_button.y and 
               y <= notif_y + notification.no_button.y + notification.no_button.h then
                
                notification.clicked_button = "no"
                if notification.callback then
                    notification.callback(false)
                end
                notification.state = "exiting"
                notification.animation_start = love.timer.getTime() * 1000
                return
            end
        end
    end
end

-- Network message handlers
local function handleNetworkNotification(data, sender_id)
    if data.type and data.title and data.message then
        -- Check if this is for a specific player
        if data.target_player_id then
            local local_player = api.game.getLocalPlayer()
            if local_player and local_player.id == data.target_player_id then
                createNotification(data.type, data.title, data.message, data.duration, data.persistent)
            end
        else
            -- Broadcast notification
            createNotification(data.type, data.title, data.message, data.duration, data.persistent)
        end
    end
end

-- Public API functions
local function showNotification(type, title, message, duration)
    return createNotification(type, title, message, duration, false)
end

local function showPersistent(type, title, message, callback)
    return createNotification(type, title, message, nil, true, callback)
end

local function sendToClient(player_id, type, title, message, duration)
    if api.network.isHost() then
        api.network.sendToAll({
            type = type,
            title = title,
            message = message,
            duration = duration,
            target_player_id = player_id
        }, "ui_notifications_mod")
    end
end

local function broadcast(type, title, message, duration)
    if api.network.isHost() then
        api.network.sendToAll({
            type = type,
            title = title,
            message = message,
            duration = duration
        }, "ui_notifications_mod")
    else
        -- Clients can only show local notifications
        createNotification(type, title, message, duration, false)
    end
end

-- Initialize the mod
function uiNotificationsMod.init(mod_api, mod_config)
    api = mod_api
    config = (mod_config and mod_config.configuration) or {
        max_visible_notifications = 3,
        default_duration = 3.0,
        notification_width = 300,
        notification_height = 80,
        notification_margin = 10,
        slide_speed = 5.0,
        fade_speed = 2.0
    }
    
    -- Use default fonts (mods can't create fonts in sandboxed environment)
    font = nil  -- Will use default font
    title_font = nil  -- Will use default font
    
    -- Register network handler
    api.network.registerMessageHandler("ui_notifications_mod", handleNetworkNotification)
    
    -- Register mouse handler
    api.input.registerMouseHandler("pressed", handleMousePressed)
    
    -- Register API functions for other mods
    api.utils.registerGlobalFunction("notifications", {
        showInfo = function(title, message, duration)
            return showNotification("info", title, message, duration)
        end,
        showWarning = function(title, message, duration)
            return showNotification("warning", title, message, duration)
        end,
        showError = function(title, message, duration)
            return showNotification("error", title, message, duration)
        end,
        showSuccess = function(title, message, duration)
            return showNotification("success", title, message, duration)
        end,
        showPersistent = function(title, message, callback, type)
            return showPersistent(type or "info", title, message, callback)
        end,
        sendToClient = sendToClient,
        broadcast = broadcast,
        dismiss = function(id)
            for _, notification in ipairs(notifications) do
                if notification.id == id and notification.state == "visible" then
                    notification.state = "exiting"
                    notification.animation_start = love.timer.getTime() * 1000
                    return true
                end
            end
            return false
        end,
        dismissAll = function()
            for _, notification in ipairs(notifications) do
                if notification.state == "visible" then
                    notification.state = "exiting"
                    notification.animation_start = love.timer.getTime() * 1000
                end
            end
        end
    })
    
    -- Log initialization
    api.utils.log("UI Notifications System initialized", "ui_notifications_mod")
    
    -- Show welcome notification
    showNotification("success", "Notifications Ready", "The notification system has been initialized successfully!", 3000)
end

-- Update function
function uiNotificationsMod.update(dt)
    updateNotifications(dt)
end

-- Draw function
function uiNotificationsMod.draw()
    local screen_width = love.graphics.getWidth()
    
    -- Draw notifications from bottom to top
    for i = #notifications, 1, -1 do
        local notification = notifications[i]
        if notification.state ~= "expired" then
            local x = screen_width - config.notification_width - config.position_x_offset + notification.x_offset
            local y = notification.y_offset
            
            drawNotification(notification, x, y)
        end
    end
end

-- Cleanup function
function uiNotificationsMod.cleanup()
    notifications = {}
    if api then
        api.utils.unregisterGlobalFunction("notifications")
    end
end

-- Export the notification API for other systems
uiNotificationsMod.exports = {
    showInfo = function(title, message, duration)
        return showNotification("info", title, message, duration)
    end,
    showWarning = function(title, message, duration)
        return showNotification("warning", title, message, duration)
    end,
    showError = function(title, message, duration)
        return showNotification("error", title, message, duration)
    end,
    showSuccess = function(title, message, duration)
        return showNotification("success", title, message, duration)
    end,
    showPersistent = function(title, message, callback, type)
        return showPersistent(type or "info", title, message, callback)
    end,
    sendToClient = sendToClient,
    broadcast = broadcast,
    dismiss = function(id)
        for _, notification in ipairs(notifications) do
            if notification.id == id and notification.state == "visible" then
                notification.state = "exiting"
                notification.animation_start = love.timer.getTime() * 1000
                return true
            end
        end
        return false
    end,
    dismissAll = function()
        for _, notification in ipairs(notifications) do
            if notification.state == "visible" then
                notification.state = "exiting"
                notification.animation_start = love.timer.getTime() * 1000
            end
        end
    end
}

return uiNotificationsMod