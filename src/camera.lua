-- Clean Camera System
local camera = {}

-- Core camera state
camera.x = 0
camera.y = 0
camera.pos = require("vec2").new(0, 0)  -- Required by other systems
camera.zoom = 1.0
camera.target_zoom = 1.0

-- Camera settings
camera.config = {
    lerp_speed = 8.0,  -- Smoother following (lower = smoother)
    zoom_speed = 12.0,
    dead_zone = 40,  -- Smaller deadzone for more responsive following
    dead_zone_lean = 0.2,  -- Less leaning for smoother movement
    look_ahead_time = 0.15,  -- Better prediction
    look_ahead_weight = 0.2,  -- Stronger look-ahead
    culling_margin = 200,
    mouse_influence = 0.1,  -- Reduced mouse influence for smoother movement
    mouse_max_distance = 120,  -- Reduced max distance
    -- Enhanced culling settings
    use_circular_culling = true,  -- Use circular instead of square culling
    dynamic_culling = true,  -- Adjust culling based on zoom and performance
    base_view_radius = 400,  -- Base view radius in world units
    performance_scaling = true,  -- Scale quality based on framerate
    min_culling_radius = 150,  -- Minimum culling radius
    max_culling_radius = 800,   -- Maximum culling radius
    culling_precision = 0.95  -- Higher precision for smoother circular culling (0.9-1.0)
}

-- Performance tracking
camera.screen_width = love.graphics.getWidth()
camera.screen_height = love.graphics.getHeight()
camera.transform_matrix = love.math.newTransform()
camera.view_bounds = {x1 = 0, y1 = 0, x2 = 0, y2 = 0}
camera.view_radius = 400  -- Current view radius for circular culling
camera.performance = {
    frame_times = {},
    avg_dt = 0.016,
    performance_factor = 1.0,
    sample_count = 60
}

-- Map boundaries (updated for expanded world)
camera.map_bounds = {
    enabled = true,
    x = 0, y = 0,
    width = 4000, height = 3000,
    soft_edges = true,
    resistance = 0.9  -- Slightly stronger resistance for smoother boundary behavior
}

-- Shader uniforms for integration
camera.shader_uniforms = {
    position = {0, 0},
    zoom = 1.0
}

function camera.setZoom(zoom, player)
    -- Set target zoom for smooth transition
    camera.target_zoom = zoom
    
    -- If player is provided, center on player, otherwise keep current center
    if player then
        local px, py = player.body:getX(), player.body:getY()
        camera.x = px
        camera.y = py
    end
    -- Don't immediately set camera.zoom - let it smoothly transition in update()
    
    -- Update position vector for compatibility
    camera.pos.x = camera.x
    camera.pos.y = camera.y
end

function camera.getZoom()
    return camera.zoom
end

function camera.setMapBounds(x, y, width, height)
    camera.map_bounds.x = x
    camera.map_bounds.y = y
    camera.map_bounds.width = width
    camera.map_bounds.height = height
end

function camera.updateScreenSize()
    camera.screen_width = love.graphics.getWidth()
    camera.screen_height = love.graphics.getHeight()
end

function camera.getIdealPosition(player)
    local px, py = player.body:getX(), player.body:getY()
    local vx, vy = player.body:getLinearVelocity()
    
    -- Camera position now represents center of view, so ideal position is just player position
    local ideal_x = px
    local ideal_y = py
    
    -- Add predictive look-ahead
    ideal_x = ideal_x + vx * camera.config.look_ahead_time * camera.config.look_ahead_weight
    ideal_y = ideal_y + vy * camera.config.look_ahead_time * camera.config.look_ahead_weight
    
    -- Add mouse gravitation effect
    local mouse_x, mouse_y = love.mouse.getPosition()
    
    -- Convert mouse position to world coordinates
    local mouse_world_x, mouse_world_y = camera.screenToWorld(mouse_x, mouse_y)
    
    -- Calculate offset from player position in world coordinates
    local mouse_offset_x = mouse_world_x - px
    local mouse_offset_y = mouse_world_y - py
    
    -- Limit mouse influence distance (also scaled by zoom)
    local mouse_distance = math.sqrt(mouse_offset_x^2 + mouse_offset_y^2)
    local max_distance = camera.config.mouse_max_distance / camera.zoom
    if mouse_distance > max_distance then
        local scale = max_distance / mouse_distance
        mouse_offset_x = mouse_offset_x * scale
        mouse_offset_y = mouse_offset_y * scale
    end
    
    -- Apply mouse influence to camera position
    ideal_x = ideal_x + mouse_offset_x * camera.config.mouse_influence
    ideal_y = ideal_y + mouse_offset_y * camera.config.mouse_influence
    
    return ideal_x, ideal_y
end

function camera.getDeadZoneInfo(player)
    local px, py = player.body:getX(), player.body:getY()
    
    -- Distance from camera center in world coordinates
    local offset_x = px - camera.x
    local offset_y = py - camera.y
    local distance = math.sqrt(offset_x^2 + offset_y^2)
    
    -- Convert deadzone from screen pixels to world units
    local deadzone_world = camera.config.dead_zone / camera.zoom
    
    -- Check if outside dead zone
    local outside_deadzone = distance > deadzone_world
    
    -- Calculate lean factor (0.0 at center, 1.0 at edge of deadzone)
    local lean_factor = math.min(distance / deadzone_world, 1.0)
    
    -- Calculate lean direction (normalized)
    local lean_x, lean_y = 0, 0
    if distance > 0 then
        lean_x = offset_x / distance
        lean_y = offset_y / distance
    end
    
    return {
        outside_deadzone = outside_deadzone,
        lean_factor = lean_factor,
        lean_x = lean_x,
        lean_y = lean_y,
        distance = distance
    }
end

function camera.constrainToMap()
    if not camera.map_bounds.enabled then return end
    
    local half_width = camera.screen_width * 0.5 / camera.zoom
    local half_height = camera.screen_height * 0.5 / camera.zoom
    
    -- Camera center should stay within bounds minus half-screen
    local min_x = camera.map_bounds.x + half_width
    local max_x = camera.map_bounds.x + camera.map_bounds.width - half_width
    local min_y = camera.map_bounds.y + half_height
    local max_y = camera.map_bounds.y + camera.map_bounds.height - half_height
    
    if camera.map_bounds.soft_edges then
        -- Soft boundary resistance
        local resistance = camera.map_bounds.resistance
        
        if camera.x < min_x then
            local penetration = min_x - camera.x
            camera.x = camera.x + penetration * resistance
        elseif camera.x > max_x then
            local penetration = camera.x - max_x
            camera.x = camera.x - penetration * resistance
        end
        
        if camera.y < min_y then
            local penetration = min_y - camera.y
            camera.y = camera.y + penetration * resistance
        elseif camera.y > max_y then
            local penetration = camera.y - max_y
            camera.y = camera.y - penetration * resistance
        end
    else
        -- Hard boundaries
        camera.x = math.max(min_x, math.min(camera.x, max_x))
        camera.y = math.max(min_y, math.min(camera.y, max_y))
    end
end

function camera.updateTransform()
    -- Camera position represents center of view, so we need to offset by screen center
    local offset_x = camera.screen_width * 0.5
    local offset_y = camera.screen_height * 0.5
    
    camera.transform_matrix:setTransformation(
        offset_x - camera.x * camera.zoom,
        offset_y - camera.y * camera.zoom,
        0, camera.zoom, camera.zoom,
        0, 0, 0, 0
    )
    
    -- Update shader uniforms
    camera.shader_uniforms.position = {camera.x, camera.y}
    camera.shader_uniforms.zoom = camera.zoom
end

function camera.calculateViewRadius()
    if not camera.config.dynamic_culling then
        return camera.config.base_view_radius
    end
    
    local base_radius = camera.config.base_view_radius
    
    -- Zoom factor scaling
    local zoom_factor = math.max(0.5, math.min(2.0, 1.0 / camera.zoom))
    
    -- Performance scaling
    local performance_factor = 1.0
    if camera.config.performance_scaling then
        performance_factor = camera.performance.performance_factor
    end
    
    -- Screen size factor - larger screens need larger radius
    local screen_diagonal = math.sqrt(camera.screen_width^2 + camera.screen_height^2)
    local screen_factor = math.max(0.8, screen_diagonal / 1000)  -- Normalize to ~1000px diagonal
    
    local dynamic_radius = base_radius * zoom_factor * performance_factor * screen_factor
    
    -- Clamp to min/max bounds
    return math.max(camera.config.min_culling_radius, 
                   math.min(camera.config.max_culling_radius, dynamic_radius))
end

function camera.updateViewBounds()
    if camera.config.use_circular_culling then
        -- Calculate dynamic view radius
        camera.view_radius = camera.calculateViewRadius()
        
        -- Set square bounds that encompass the circle for compatibility
        local radius = camera.view_radius
        camera.view_bounds.x1 = camera.x - radius
        camera.view_bounds.y1 = camera.y - radius
        camera.view_bounds.x2 = camera.x + radius
        camera.view_bounds.y2 = camera.y + radius
    else
        -- Original square culling
        local half_width = camera.screen_width * 0.5 / camera.zoom + camera.config.culling_margin
        local half_height = camera.screen_height * 0.5 / camera.zoom + camera.config.culling_margin
        
        camera.view_bounds.x1 = camera.x - half_width
        camera.view_bounds.y1 = camera.y - half_height
        camera.view_bounds.x2 = camera.x + half_width
        camera.view_bounds.y2 = camera.y + half_height
    end
end

function camera.isInView(x, y, width, height)
    width = width or 0
    height = height or 0
    
    if camera.config.use_circular_culling then
        -- Find closest point on object to camera center
        local closest_x = math.max(x, math.min(camera.x, x + width))
        local closest_y = math.max(y, math.min(camera.y, y + height))
        
        -- Calculate distance from camera center to closest point
        local dx = closest_x - camera.x
        local dy = closest_y - camera.y
        local distance_sq = dx * dx + dy * dy
        
        -- Apply precision factor for smoother circular culling
        local effective_radius = camera.view_radius * camera.config.culling_precision
        local radius_sq = effective_radius * effective_radius
        
        return distance_sq <= radius_sq
    else
        -- Original square culling
        return not (x + width < camera.view_bounds.x1 or
                    x > camera.view_bounds.x2 or
                    y + height < camera.view_bounds.y1 or
                    y > camera.view_bounds.y2)
    end
end

function camera.getDistanceToCamera(x, y)
    local dx = x - camera.x
    local dy = y - camera.y
    return math.sqrt(dx * dx + dy * dy)
end

-- Convert screen coordinates to world coordinates
function camera.screenToWorld(screen_x, screen_y)
    local world_x = (screen_x - camera.screen_width * 0.5) / camera.zoom + camera.x
    local world_y = (screen_y - camera.screen_height * 0.5) / camera.zoom + camera.y
    return world_x, world_y
end

-- Convert world coordinates to screen coordinates
function camera.worldToScreen(world_x, world_y)
    local screen_x = (world_x - camera.x) * camera.zoom + camera.screen_width * 0.5
    local screen_y = (world_y - camera.y) * camera.zoom + camera.screen_height * 0.5
    return screen_x, screen_y
end

function camera.shouldSkipObject(x, y, object_type)
    -- Simple LOD system for performance
    local distance = math.sqrt((x - camera.x)^2 + (y - camera.y)^2)
    local zoom_factor = camera.zoom / 0.5  -- threshold
    local distance_factor = distance / 500  -- threshold
    
    local lod_level = math.max(1, math.floor(distance_factor / zoom_factor))
    lod_level = math.min(lod_level, 4)  -- Cap at 4 levels
    
    if lod_level >= 3 then
        if object_type == "particle" or object_type == "decoration" then
            return true
        end
    end
    
    if lod_level >= 4 then
        if object_type ~= "player" and object_type ~= "enemy" and object_type ~= "important" then
            return true
        end
    end
    
    return false
end

function camera.updatePerformance(dt)
    -- Track frame times for performance scaling
    table.insert(camera.performance.frame_times, dt)
    
    -- Keep only recent samples
    if #camera.performance.frame_times > camera.performance.sample_count then
        table.remove(camera.performance.frame_times, 1)
    end
    
    -- Calculate average frame time
    local total = 0
    for _, frame_dt in ipairs(camera.performance.frame_times) do
        total = total + frame_dt
    end
    camera.performance.avg_dt = total / #camera.performance.frame_times
    
    -- Calculate performance factor (1.0 = 60fps, 0.5 = 30fps, 2.0 = 120fps)
    local target_dt = 1.0 / 60.0  -- 60 FPS target
    camera.performance.performance_factor = math.max(0.3, math.min(1.5, target_dt / camera.performance.avg_dt))
end

function camera.update(dt, player)
    -- Update performance tracking
    camera.updatePerformance(dt)
    
    -- Update screen dimensions
    camera.updateScreenSize()
    
    -- Smooth zoom transition
    if math.abs(camera.zoom - camera.target_zoom) > 0.001 then
        local zoom_lerp = 1.0 - math.exp(-camera.config.zoom_speed * dt)
        camera.zoom = camera.zoom + (camera.target_zoom - camera.zoom) * zoom_lerp
    else
        camera.zoom = camera.target_zoom
    end
    
    -- Get deadzone information
    local deadzone_info = camera.getDeadZoneInfo(player)
    
    -- Get ideal camera position (this includes mouse gravitation)
    local ideal_x, ideal_y = camera.getIdealPosition(player)
    
    -- Determine target position based on deadzone
    local target_x, target_y = camera.x, camera.y
    
    -- Always center camera on player initially
    if camera.x == 0 and camera.y == 0 then
        -- Initialize camera position to center on player
        camera.x = ideal_x
        camera.y = ideal_y
        target_x, target_y = ideal_x, ideal_y
    elseif deadzone_info.outside_deadzone then
        -- Player is outside deadzone, move camera to follow
        target_x = ideal_x
        target_y = ideal_y
    else
        -- Player is inside deadzone, apply leaning effect
        local lean_distance = camera.config.dead_zone * camera.config.dead_zone_lean / camera.zoom
        local lean_offset_x = deadzone_info.lean_x * deadzone_info.lean_factor * lean_distance
        local lean_offset_y = deadzone_info.lean_y * deadzone_info.lean_factor * lean_distance
        
        target_x = ideal_x + lean_offset_x
        target_y = ideal_y + lean_offset_y
    end
    
    -- Ultra smooth camera movement with higher lerp
    local move_lerp = 1.0 - math.exp(-camera.config.lerp_speed * dt)
    camera.x = camera.x + (target_x - camera.x) * move_lerp
    camera.y = camera.y + (target_y - camera.y) * move_lerp
    
    -- Apply map constraints
    camera.constrainToMap()
    
    -- Update position vector for compatibility
    camera.pos.x = camera.x
    camera.pos.y = camera.y
    
    -- Update derived values
    camera.updateTransform()
    camera.updateViewBounds()
end

function camera.apply()
    love.graphics.applyTransform(camera.transform_matrix)
end

function camera.applyToShader(shader)
    if shader then
        pcall(function() shader:send("camera_position", camera.shader_uniforms.position) end)
        pcall(function() shader:send("camera_zoom", camera.shader_uniforms.zoom) end)
    end
end

return camera