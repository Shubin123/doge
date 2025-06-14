-- Camera module
local camera = {}

-- Camera state
camera.x = 0
camera.y = 0
camera.pos = require("lib.math.vec2").new(0,0)

camera.zoom = 1.5
camera.target_zoom = 1.5
camera.zoom_lerp_speed = 3

-- Deadzone configuration (as percentage of screen)
camera.deadzone_x = 0.15 -- 15% of screen width
camera.deadzone_y = 0.15 -- 15% of screen height
camera.lag_speed = 5 -- Speed when player is within deadzone
camera.catch_up_speed = 8 -- Speed when player exits deadzone

-- Screen shake variables
camera.shake_intensity = 0
camera.shake_duration = 0
camera.shake_timer = 0
camera.shake_offset_x = 0
camera.shake_offset_y = 0

-- Internal tracking
camera.player_world_x = 0
camera.player_world_y = 0

function camera.apply()
    -- Apply zoom and translation together
    love.graphics.scale(camera.zoom, camera.zoom)
    -- Floor the camera position to prevent jitter and add shake offset
    love.graphics.translate(
        math.floor((camera.x + camera.shake_offset_x) / camera.zoom), 
        math.floor((camera.y + camera.shake_offset_y) / camera.zoom)
    )
end

function camera.setZoom(zoom)
    camera.target_zoom = zoom
end

function camera.getZoom()
    return camera.zoom
end

-- Trigger screen shake effect
function camera.shake(intensity, duration)
    camera.shake_intensity = intensity or 2
    camera.shake_duration = duration or 0.1
    camera.shake_timer = camera.shake_duration
end

-- Completely reworked camera system with proper zoom centering
function camera.update(dt, player)
    
    -- Update screen shake
    if camera.shake_timer > 0 then
        camera.shake_timer = camera.shake_timer - dt
        
        -- Calculate shake intensity based on remaining time
        local shake_factor = camera.shake_timer / camera.shake_duration
        local current_intensity = camera.shake_intensity * shake_factor
        
        -- Generate random shake offset
        camera.shake_offset_x = (math.random() - 0.5) * 2 * current_intensity
        camera.shake_offset_y = (math.random() - 0.5) * 2 * current_intensity
    else
        -- No shake, reset offsets
        camera.shake_offset_x = 0
        camera.shake_offset_y = 0
    end
    
    -- Get player world position through mod system
    local player_x, player_y = 0, 0
    if modSystem and modSystem.getPlayerPosition then
        player_x, player_y = modSystem.getPlayerPosition()
    elseif player and player.body then
        -- Fallback to legacy player if available
        player_x, player_y = player.body:getPosition()
    end
    camera.player_world_x = player_x
    camera.player_world_y = player_y
    
    -- Get screen dimensions
    local screen_width = love.graphics.getWidth()
    local screen_height = love.graphics.getHeight()
    local screen_center_x = screen_width / 2
    local screen_center_y = screen_height / 2
    
    -- Store previous zoom for smooth transitions
    local prev_zoom = camera.zoom
    
    -- Smooth zoom update
    local zoom_diff = camera.target_zoom - camera.zoom
    if math.abs(zoom_diff) > 0.001 then
        local zoom_lerp_amount = 1.0 - math.exp(-camera.zoom_lerp_speed * dt)
        camera.zoom = camera.zoom + zoom_diff * zoom_lerp_amount
    else
        camera.zoom = camera.target_zoom
    end
    
    -- Calculate the ideal camera position to center player on screen
    local ideal_cam_x = screen_center_x - player_x * camera.zoom
    local ideal_cam_y = screen_center_y - player_y * camera.zoom
    
    -- If zoom changed significantly, prioritize maintaining player center
    if math.abs(camera.zoom - prev_zoom) > 0.001 then
        -- During zoom transitions, directly center on player
        camera.x = ideal_cam_x
        camera.y = ideal_cam_y
    else
        -- Normal operation: use deadzone system for smooth following
        
        -- Calculate where the player currently appears on screen
        local player_screen_x = (player_x * camera.zoom) + camera.x
        local player_screen_y = (player_y * camera.zoom) + camera.y
        
        -- Calculate deadzone bounds
        local deadzone_width = screen_width * camera.deadzone_x
        local deadzone_height = screen_height * camera.deadzone_y
        local deadzone_left = screen_center_x - deadzone_width / 2
        local deadzone_right = screen_center_x + deadzone_width / 2
        local deadzone_top = screen_center_y - deadzone_height / 2
        local deadzone_bottom = screen_center_y + deadzone_height / 2
        
        -- Check if player is outside deadzone
        local outside_deadzone = false
        if player_screen_x < deadzone_left or player_screen_x > deadzone_right or
           player_screen_y < deadzone_top or player_screen_y > deadzone_bottom then
            outside_deadzone = true
        end
        
        -- Determine movement speed and target
        local target_x, target_y
        local lerp_speed
        
        if outside_deadzone then
            -- Player is outside deadzone, move camera to recenter player
            target_x = ideal_cam_x
            target_y = ideal_cam_y
            lerp_speed = camera.catch_up_speed
        else
            -- Player is within deadzone, use gentle drift toward center
            target_x = camera.x + (ideal_cam_x - camera.x) * 0.1
            target_y = camera.y + (ideal_cam_y - camera.y) * 0.1
            lerp_speed = camera.lag_speed
        end
        
        -- Smooth camera movement
        local lerp_amount = 1.0 - math.exp(-lerp_speed * dt)
        camera.x = camera.x + (target_x - camera.x) * lerp_amount
        camera.y = camera.y + (target_y - camera.y) * lerp_amount
    end
    
    -- Update camera position vector for external systems
    camera.pos.x = camera.x 
    camera.pos.y = camera.y
end

function camera.screenToWorld(x, y)
    local worldX = (x - camera.x) / camera.zoom
    local worldY = (y - camera.y) / camera.zoom
    return worldX, worldY
end

function camera.worldToScreen(x, y)
    local screenX = (x * camera.zoom) + camera.x
    local screenY = (y * camera.zoom) + camera.y
    return screenX, screenY
end

return camera