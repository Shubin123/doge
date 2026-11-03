-- Camera module
local camera = {}

-- Camera state. The camera follows a world point, the one at the middle of
-- the screen (cx, cy), and zooming scales the view round it, so a zoom never
-- moves it. camera.x, camera.y (camera.pos: the screen offset everything is
-- drawn with, screen = world * zoom + offset) are worked out from it and the
-- zoom every update, in whole pixels, so they always agree with the zoom and
-- with what camera.apply() draws. (They used to be eased on their own, in
-- screen px, which a zoom knocked out of step with the zoom by the player's
-- distance from the world's origin times its change: tens of px out in the
-- regions, 20000 px east.)
camera.x = 0
camera.y = 0
camera.pos = require("lib.math.vec2").new(0,0)
camera.cx, camera.cy = nil, nil -- (until the first update or snap)

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
    -- Apply zoom and translation together, the translation in whole screen
    -- pixels, shake included (flooring it in world units snapped it by up to
    -- `zoom` px, by a different amount every frame of a zoom)
    love.graphics.scale(camera.zoom,camera.zoom)
    love.graphics.translate(
        math.floor(camera.x + camera.shake_offset_x) / camera.zoom,
        math.floor(camera.y + camera.shake_offset_y) / camera.zoom
    )
end

-- camera.x, camera.y from the point it follows and the zoom
local function place()
    camera.x = math.floor(love.graphics.getWidth() / 2 - camera.cx * camera.zoom)
    camera.y = math.floor(love.graphics.getHeight() / 2 - camera.cy * camera.zoom)
    camera.pos.x = camera.x
    camera.pos.y = camera.y
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
    if not var.screen_shake then return end -- Settings > Screen Shake
    camera.shake_intensity = intensity or 2
    camera.shake_duration = duration or 0.1
    camera.shake_timer = camera.shake_duration
end

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
    
    -- Zoom, frame-rate independent, settling on the target at the end
    local zoom_lerp_amount = 1.0 - math.exp(-camera.zoom_lerp_speed * dt)
    camera.zoom = camera.zoom + (camera.target_zoom - camera.zoom) * zoom_lerp_amount
    if math.abs(camera.target_zoom - camera.zoom) < 0.001 then
        camera.zoom = camera.target_zoom
    end

    -- Follow the player, frame-rate independent, in the world, so it carries
    -- on just the same through a zoom
    local px, py = player.body:getPosition()
    if not camera.cx then
        -- (where the screen offset had it)
        camera.cx = (love.graphics.getWidth() / 2 - camera.x) / camera.zoom
        camera.cy = (love.graphics.getHeight() / 2 - camera.y) / camera.zoom
    end
    local lerp_amount = 1.0 - math.exp(-camera.lerp_speed * dt)
    camera.cx = camera.cx + (px - camera.cx) * lerp_amount
    camera.cy = camera.cy + (py - camera.cy) * lerp_amount
    place()
end


-- Jump straight onto the player (after a teleport) instead of gliding there
function camera.snap(player)
    camera.cx, camera.cy = player.body:getPosition()
    place()
end

function camera.screenToWorld(x, y)
    local worldX = (x - camera.x) / camera.zoom
    local worldY = (y - camera.y) / camera.zoom
    return worldX, worldY
end

-- The screen rect {x0, y0, x1, y1} a world rect lands on under camera.apply()
-- (its flooring and shake included)
function camera.screenRect(x0, y0, x1, y1)
    love.graphics.push()
    love.graphics.origin()
    camera.apply()
    local ax, ay = love.graphics.transformPoint(x0, y0)
    local bx, by = love.graphics.transformPoint(x1, y1)
    love.graphics.pop()
    return { math.min(ax, bx), math.min(ay, by), math.max(ax, bx), math.max(ay, by) }
end

function camera.worldToScreen(x, y)
    local screenX = (x * camera.zoom) + camera.x
    local screenY = (y * camera.zoom) + camera.y
    return screenX, screenY
end

return camera