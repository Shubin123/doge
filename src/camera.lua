-- Camera module
local camera = {}

-- Camera state
camera.x = 0
camera.y = 0
camera.target_x = 0 
camera.target_y = 0
camera.zoom = 1.0
camera.target_zoom = 1.0
camera.lerp_speed = 3 -- Adjust this value (0.05 = slow, 0.2 = fast)
camera.zoom_lerp_speed = 1 -- Separate speed for zoom

function camera.update(dt, player)
    -- Update target position (adjust for zoom to keep player centered)
    local screen_center_x = love.graphics.getWidth() / 2
    local screen_center_y = love.graphics.getHeight() / 2
    
    camera.target_x = -player.body:getX() * camera.zoom + screen_center_x
    camera.target_y = -player.body:getY() * camera.zoom + screen_center_y
    
    -- Lerp to target
    camera.x = camera.x + (camera.target_x - camera.x) * camera.lerp_speed
    camera.y = camera.y + (camera.target_y - camera.y) * camera.lerp_speed
    
    -- Lerp zoom
    camera.zoom =  camera.zoom + (camera.target_zoom - camera.zoom) * camera.zoom_lerp_speed
end

function camera.apply()
    -- Apply zoom and translation together
    love.graphics.scale(camera.zoom, camera.zoom)
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
    camera.zoom = camera.zoom + (camera.target_zoom - camera.zoom) * zoom_lerp_amount
end

return camera

-- Usage in your main.lua:
--[[
local camera = require("camera")

function love.update(dt)
    -- ... your existing update code ...
    
    -- Update camera to follow player
    camera.update(dt, player)
    -- OR use frame-rate independent version:
    -- camera.update_framerate_independent(dt, player)
    
    -- Example zoom controls
    if love.keyboard.isDown("z") then
        camera.setZoom(2.0) -- Zoom in
    elseif love.keyboard.isDown("x") then
        camera.setZoom(0.5) -- Zoom out
    else
        camera.setZoom(1.0) -- Normal zoom
    end
end

function love.draw()
    love.graphics.push()
    camera.apply() -- This now handles both zoom and translation
    
    -- ... your existing drawing code ...
    -- shader.prepass()
    -- ... draw your game objects ...
    -- shader.pass(distance, sample)
    
    love.graphics.pop()
end
--]]