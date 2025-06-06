-- Camera module with matrix-based transformations
local camera = {}

-- Camera state
camera.x = 0
camera.y = 0
camera.pos = require("vec2").new(0,0)
camera.zoom = 1.0
camera.target_zoom = 1.0
camera.lerp_speed = 8.0
camera.zoom_lerp_speed = 10.0

-- Enhanced camera properties
camera.deadZone = {
    inner = 80,
    outer = 150,
    adaptive = true
}

camera.predictive = {
    enabled = true,
    lookAheadTime = 0.3,
    weight = 0.2
}

function camera.apply()
    -- Apply zoom and translation using matrix transformations
    love.graphics.scale(camera.zoom, camera.zoom)
    love.graphics.translate(-camera.x, -camera.y)
end

function camera.setZoom(zoom)
    camera.target_zoom = zoom
end

function camera.getZoom()
    return camera.zoom
end

function camera.update_framerate_independent(dt, player)
    local px, py = player.body:getX(), player.body:getY()
    local vx, vy = player.body:getLinearVelocity()
    
    -- Update zoom smoothly
    local zoom_lerp = 1.0 - math.exp(-camera.zoom_lerp_speed * dt)
    camera.zoom = camera.zoom + (camera.target_zoom - camera.zoom) * zoom_lerp
    
    -- Screen center
    local screen_center_x = love.graphics.getWidth() / (2 * camera.zoom)
    local screen_center_y = love.graphics.getHeight() / (2 * camera.zoom)
    
    -- Calculate ideal camera position (player at screen center)
    local ideal_cam_x = px - screen_center_x
    local ideal_cam_y = py - screen_center_y
    
    -- Add predictive component
    if camera.predictive.enabled then
        local predict_x = px + vx * camera.predictive.lookAheadTime
        local predict_y = py + vy * camera.predictive.lookAheadTime
        
        local predictive_cam_x = predict_x - screen_center_x
        local predictive_cam_y = predict_y - screen_center_y
        
        -- Blend ideal and predictive positions
        ideal_cam_x = ideal_cam_x * (1 - camera.predictive.weight) + predictive_cam_x * camera.predictive.weight
        ideal_cam_y = ideal_cam_y * (1 - camera.predictive.weight) + predictive_cam_y * camera.predictive.weight
    end
    
    -- Calculate player position relative to current camera view
    local player_screen_x = (px - camera.x) * camera.zoom
    local player_screen_y = (py - camera.y) * camera.zoom
    local screen_width = love.graphics.getWidth()
    local screen_height = love.graphics.getHeight()
    
    -- Distance from screen center
    local center_offset_x = player_screen_x - screen_width / 2
    local center_offset_y = player_screen_y - screen_height / 2
    local distance_from_center = math.sqrt(center_offset_x^2 + center_offset_y^2)
    
    -- Adaptive dead zone based on speed
    local speed = math.sqrt(vx^2 + vy^2)
    local speed_factor = math.min(speed / 500.0, 1.0)
    local current_dead_zone = camera.deadZone.inner + (camera.deadZone.outer - camera.deadZone.inner) * speed_factor
    
    -- Calculate target camera position
    local target_x = camera.x
    local target_y = camera.y
    
    if distance_from_center > current_dead_zone then
        -- Move camera toward ideal position
        local move_factor = (distance_from_center - current_dead_zone) / current_dead_zone
        move_factor = math.min(move_factor, 1.0)
        
        target_x = camera.x + (ideal_cam_x - camera.x) * move_factor
        target_y = camera.y + (ideal_cam_y - camera.y) * move_factor
    end
    
    -- Smooth camera movement
    local lerp_factor = 1.0 - math.exp(-camera.lerp_speed * dt)
    camera.x = camera.x + (target_x - camera.x) * lerp_factor
    camera.y = camera.y + (target_y - camera.y) * lerp_factor
    
    -- Update position vector
    camera.pos.x = camera.x
    camera.pos.y = camera.y
end

return camera