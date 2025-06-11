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
camera.lerp_speed = 2 -- Adjust this value (1 = slow, 10 = fast)
camera.zoom_lerp_speed = 10 -- Separate speed for zoom

-- Screen shake variables
camera.shake_intensity = 0
camera.shake_duration = 0
camera.shake_timer = 0
camera.shake_offset_x = 0
camera.shake_offset_y = 0

function camera.apply()
    -- Apply zoom and translation together
    love.graphics.scale(camera.zoom,camera.zoom)
    -- Floor the camera position to prevent jitter and add shake offset
    love.graphics.translate(
        math.floor((camera.x + camera.shake_offset_x) / camera.zoom), 
        math.floor((camera.y + camera.shake_offset_y) / camera.zoom)
    )
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

-- Trigger screen shake effect
function camera.shake(intensity, duration)
    camera.shake_intensity = intensity or 2
    camera.shake_duration = duration or 0.1
    camera.shake_timer = camera.shake_duration
end

-- Fixed implementation with aggressive zoom compensation
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
    
    -- Store previous zoom for compensation
    local prev_zoom = camera.zoom
    
    -- Update zoom first
    local zoom_lerp_amount = 1.0 - math.exp(-camera.zoom_lerp_speed * dt)
    camera.zoom = camera.zoom + (camera.target_zoom - camera.zoom) * zoom_lerp_amount
    
        local target_screen_x = love.graphics.getWidth() / 2
        local target_screen_y = love.graphics.getHeight() / 2

    -- Aggressive compensation for zoom change to keep character locked in center
    if math.abs(prev_zoom - camera.zoom) > 0.0001 then
        

        
        -- Force camera position to keep player exactly at target screen position
        camera.x = target_screen_x - player.body:getX() * camera.zoom
        camera.y = target_screen_y - player.body:getY() * camera.zoom
        
        -- Also update targets to prevent lerping away from this position
        camera.target_x = camera.x
        camera.target_y = camera.y
    else
        -- Normal target calculation when zoom is stable
        -- local screen_center_x = love.graphics.getWidth() / 2 - 3000*camera.zoom 
        local screen_center_y = love.graphics.getHeight() / 2 - 100
        
        camera.target_x = -player.body:getX() * camera.zoom + target_screen_x
        camera.target_y = -player.body:getY() * camera.zoom + target_screen_y
        
        -- Frame-rate independent lerping for position only when not compensating zoom
        local lerp_amount = 1.0 - math.exp(-camera.lerp_speed * dt)
        
        camera.x = camera.x + (camera.target_x - camera.x) * lerp_amount
        camera.y = camera.y + (camera.target_y - camera.y) * lerp_amount
    end
    
    camera.pos.x = camera.x 
    camera.pos.y = camera.y
    
    -- print(math.abs(camera.target_zoom - camera.zoom))
    
    if math.abs(camera.target_zoom - camera.zoom) < 0.001 then
        camera.zoom = camera.target_zoom
        -- if blur.is_enabled() then
        
        -- blur.disable()
        -- blur.set_radius(3)
        -- end

    else
        -- shader.sample = 4
        -- shader.distance = 10
        -- if not blur.is_enabled() then
        -- blur.enable()
        -- blur.set_radius(5*math.abs(camera.target_zoom - camera.zoom))
        -- end
        
    end
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