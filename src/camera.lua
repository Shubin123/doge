-- Camera module
local camera = {}

-- Camera state
camera.x = 0
camera.y = 0
camera.pos = require("vec2").new(0,0)

camera.target_x = 0 
camera.target_y = 0
camera.zoom = 1.0
camera.target_zoom = 1.0
camera.lerp_speed = 3 -- Adjust this value (0.05 = slow, 0.2 = fast)
camera.zoom_lerp_speed = 1 -- Separate speed for zoom


function camera.apply()
    -- Apply zoom and translation together
    
    love.graphics.scale( camera.zoom, camera.zoom)
    
    -- Floor the camera position to prevent jitter
    love.graphics.translate(math.floor(camera.x / camera.zoom), math.floor(camera.y / camera.zoom))
end

function camera.setSpeed(speed)
    camera.lerp_speed = speed
end

function camera.setZoomSpeed(speed)
    camera.zoom_lerp_speed = speed
end

function camera.setZoom(zoom)
    camera.target_zoom = zoom
end

function camera.getZoom()
    return camera.zoom
end

-- Alternative implementation with frame-rate independent smoothing
function camera.update_framerate_independent(dt, player)
    
    
    -- Update target position (adjust for zoom to keep player centered)
    local screen_center_x = love.graphics.getWidth() / 2 - 200*camera.target_zoom
    local screen_center_y = love.graphics.getHeight() / 2 - 100
    
    camera.target_x = -player.body:getX() * camera.zoom + screen_center_x
    camera.target_y = -player.body:getY() * camera.zoom + screen_center_y
    
    -- Frame-rate independent lerping
    local lerp_amount = 1.0 - math.exp(-camera.lerp_speed * dt)
    local zoom_lerp_amount = 1.0 - math.exp(-camera.lerp_speed * dt)
    
    camera.x = camera.x + (camera.target_x - camera.x) * lerp_amount
    camera.y = camera.y + (camera.target_y - camera.y) * lerp_amount
    camera.pos.x = camera.x
    camera.pos.y = camera.y
    camera.zoom =  camera.zoom + (camera.target_zoom - camera.zoom) * zoom_lerp_amount
end

return camera
