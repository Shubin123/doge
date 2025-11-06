local bezierArrow = {}

local config = {
    arrow_count = 8,
    arrow_speed = 800,
    arrow_length = 25,
    arrow_width = 4,
    curve_height = 150, -- How high the bezier curve goes
    spread_angle = 45, -- Degrees of spread for multiple arrows
    arrow_lifetime = 2, -- Seconds before arrow disappears
    collision_radius = 8,
    colors = {
        arrow = { 1, 0.9, 0.7 },
        trail = { 1, 0.7, 0.4, 0.5 }
    }
}

local state = {
    arrows = {},
    colliders = {}
}

bezierArrow.firing = false
bezierArrow.timer = 0
bezierArrow.cooldown = 1.5

-- Cubic bezier curve calculation
local function cubicBezier(t, p0, p1, p2, p3)
    local u = 1 - t
    local tt = t * t
    local uu = u * u
    local uuu = uu * u
    local ttt = tt * t
    
    return uuu * p0 + 3 * uu * t * p1 + 3 * u * tt * p2 + ttt * p3
end

-- Calculate bezier curve point
local function bezierPoint(t, x0, y0, x1, y1)
    -- Control points for the curve
    local dx = x1 - x0
    local dy = y1 - y0
    local dist = math.sqrt(dx * dx + dy * dy)
    
    -- Create arc by placing control points perpendicular to the line
    local mid_x = (x0 + x1) / 2
    local mid_y = (y0 + y1) / 2
    
    -- Perpendicular offset
    local perp_x = -dy / dist
    local perp_y = dx / dist
    
    -- Control points create the arc
    local c1_x = x0 + dx * 0.25 + perp_x * config.curve_height * 0.5
    local c1_y = y0 + dy * 0.25 + perp_y * config.curve_height * 0.5
    local c2_x = x0 + dx * 0.75 + perp_x * config.curve_height * 0.5
    local c2_y = y0 + dy * 0.75 + perp_y * config.curve_height * 0.5
    
    local x = cubicBezier(t, x0, c1_x, c2_x, x1)
    local y = cubicBezier(t, y0, c1_y, c2_y, y1)
    
    return x, y
end

-- Calculate tangent angle at point t on bezier curve
local function bezierTangent(t, x0, y0, x1, y1)
    local dt = 0.01
    local x1_calc, y1_calc = bezierPoint(math.max(0, t - dt), x0, y0, x1, y1)
    local x2_calc, y2_calc = bezierPoint(math.min(1, t + dt), x0, y0, x1, y1)
    return math.atan2(y2_calc - y1_calc, x2_calc - x1_calc)
end

-- Raycast to check collision
local function checkArrowCollision(world, arrow)
    if not world then return false, nil end
    
    local hit = false
    local hit_object = nil
    
    world:rayCast(arrow.prev_x, arrow.prev_y, arrow.x, arrow.y, function(fixture, x, y, xn, yn, fraction)
        local body = fixture:getBody()
        local userData = body:getUserData()
        
        -- Skip arrow colliders
        if userData and userData.collision_group and userData.collision_group < 0 then
            return 1
        end
        
        hit = true
        hit_object = body
        arrow.x = x
        arrow.y = y
        arrow.stuck = true
        return 0
    end)
    
    return hit, hit_object
end

-- Create arrow object
local function createArrow(start_x, start_y, end_x, end_y, curve_variation)
    return {
        start_x = start_x,
        start_y = start_y,
        end_x = end_x,
        end_y = end_y,
        x = start_x,
        y = start_y,
        prev_x = start_x,
        prev_y = start_y,
        t = 0, -- Progress along bezier curve (0 to 1)
        angle = 0,
        lifetime = 0,
        stuck = false,
        curve_variation = curve_variation or 0,
        trail = {}
    }
end

-- Draw curved arrow body using bezier
local function drawArrow(arrow)
    love.graphics.setColor(config.colors.arrow)
    
    -- Draw the arrow as a bezier curve from start to current position
    if arrow.t > 0.05 then
        local segments = 20
        local curve_points = {}
        
        -- Generate bezier curve points from start to current t
        for i = 0, segments do
            local t_segment = (i / segments) * arrow.t
            local x, y = bezierPoint(t_segment, arrow.start_x, arrow.start_y, arrow.end_x, arrow.end_y)
            -- Apply camera transform
            table.insert(curve_points, camera.pos.x + x * camera.zoom)
            table.insert(curve_points, camera.pos.y + y * camera.zoom)
        end
        
        -- Draw the curved arrow body
        if #curve_points >= 4 then
            love.graphics.setLineWidth(3)
            love.graphics.line(curve_points)
            love.graphics.setLineWidth(1)
        end
    end
    
    -- Draw arrow head at current position
    local head_length = config.arrow_length
    local head_width = config.arrow_width
    
    local cos_a = math.cos(arrow.angle)
    local sin_a = math.sin(arrow.angle)
    
    -- Apply camera transform to arrow head
    local x1 = camera.pos.x + arrow.x * camera.zoom
    local y1 = camera.pos.y + arrow.y * camera.zoom
    local x2 = camera.pos.x + (arrow.x - head_length * cos_a + head_width * sin_a) * camera.zoom
    local y2 = camera.pos.y + (arrow.y - head_length * sin_a - head_width * cos_a) * camera.zoom
    local x3 = camera.pos.x + (arrow.x - head_length * cos_a - head_width * sin_a) * camera.zoom
    local y3 = camera.pos.y + (arrow.y - head_length * sin_a + head_width * cos_a) * camera.zoom
    
    love.graphics.polygon("fill", x1, y1, x2, y2, x3, y3)
end

local function drawArrowNoTF(arrow)
    love.graphics.setColor(config.colors.arrow)
    
    -- Draw the arrow as a bezier curve from start to current position
    if arrow.t > 0.05 then
        local segments = 20
        local curve_points = {}
        
        -- Generate bezier curve points from start to current t
        for i = 0, segments do
            local t_segment = (i / segments) * arrow.t
            local x, y = bezierPoint(t_segment, arrow.start_x, arrow.start_y, arrow.end_x, arrow.end_y)
            table.insert(curve_points, x)
            table.insert(curve_points, y)
        end
        
        -- Draw the curved arrow body
        if #curve_points >= 4 then
            love.graphics.setLineWidth(3)
            love.graphics.line(curve_points)
            love.graphics.setLineWidth(1)
        end
    end
    
    -- Draw arrow head at current position
    local head_length = config.arrow_length
    local head_width = config.arrow_width
    
    local cos_a = math.cos(arrow.angle)
    local sin_a = math.sin(arrow.angle)
    
    -- Arrow head vertices
    local x1 = arrow.x
    local y1 = arrow.y
    local x2 = arrow.x - head_length * cos_a + head_width * sin_a
    local y2 = arrow.y - head_length * sin_a - head_width * cos_a
    local x3 = arrow.x - head_length * cos_a - head_width * sin_a
    local y3 = arrow.y - head_length * sin_a + head_width * cos_a
    
    love.graphics.polygon("fill", x1, y1, x2, y2, x3, y3)
end

-- Populate draw list
local function populateArrowDrawList()
    table.insert(dynamic_draw_list, {
        sort_y = player.body:getY(),
        arrows = state.arrows,
        draw_type = "bezierArrow"
    })
end

-- Populate draw list
local function populateArrowDrawList()
    table.insert(dynamic_draw_list, {
        sort_y = player.body:getY(),
        arrows = state.arrows,
        draw_type = "bezierArrow"
    })
end

function bezierArrow.renderArrows()
    if var.graphics_high then
        local currentShader =  love.graphics.getShader()
    love.graphics.push()

    love.graphics.reset()
    whiteNeon(function()
    
    for _, arrow in ipairs(state.arrows) do
        drawArrow(arrow)
    end
    end)
      love.graphics.pop()
  love.graphics.setShader(currentShader)
else
    for _, arrow in ipairs(state.arrows) do
        drawArrowNoTF(arrow)
    end
end

end

function bezierArrow.populate()
    populateArrowDrawList()
end

-- Fire arrows
function bezierArrow.fireAt(x, y, world)
    state.arrows = {}
    
    local start_x = player.body:getX() + gun.lastAimDirection.x * 50
    local start_y = player.body:getY() + gun.lastAimDirection.y * 50
    
    local angle_to_target = math.atan2(y - start_y, x - start_x)
    local spread_rad = math.rad(config.spread_angle*math.random(0.5,1))
    
    for i = 1, config.arrow_count do
        -- Calculate spread angle for this arrow
        local spread = (i - (config.arrow_count + 1) / 2) / config.arrow_count * spread_rad
        local arrow_angle = angle_to_target + spread
        
        -- Calculate end point
        local distance = math.sqrt((x - start_x)^2 + (y - start_y)^2)
        local end_x = start_x + math.cos(arrow_angle) * distance
        local end_y = start_y + math.sin(arrow_angle) * distance
        
        -- Create arrow with slight curve variation
        local curve_var = (math.random() - 0.5) * 0.3
        local arrow = createArrow(start_x, start_y, end_x, end_y, curve_var)
        
        table.insert(state.arrows, arrow)
    end
end

function bezierArrow:update(dt)
    -- Update timer
    bezierArrow.timer = bezierArrow.timer + dt
    
    if bezierArrow.timer < bezierArrow.cooldown and bezierArrow.firing then
        -- Update all arrows
        for i = #state.arrows, 1, -1 do
            local arrow = state.arrows[i]
            arrow.lifetime = arrow.lifetime + dt
            
            -- Remove old arrows
            if arrow.lifetime > config.arrow_lifetime then
                table.remove(state.arrows, i)
            elseif not arrow.stuck then
                -- Update position along bezier curve
                arrow.prev_x = arrow.x
                arrow.prev_y = arrow.y
                
                arrow.t = arrow.t + (dt * config.arrow_speed) / math.sqrt((arrow.end_x - arrow.start_x)^2 + (arrow.end_y - arrow.start_y)^2)
                
                if arrow.t >= 1 then
                    arrow.t = 1
                    arrow.stuck = true
                end
                
                arrow.x, arrow.y = bezierPoint(arrow.t, arrow.start_x, arrow.start_y, arrow.end_x, arrow.end_y)
                arrow.angle = bezierTangent(arrow.t, arrow.start_x, arrow.start_y, arrow.end_x, arrow.end_y)
                
                -- Add to trail
                table.insert(arrow.trail, {x = arrow.x, y = arrow.y})
                if #arrow.trail > 10 then
                    table.remove(arrow.trail, 1)
                end
                
                -- Check collision
                if world then
                    checkArrowCollision(world, arrow)
                end
            end
        end
    elseif bezierArrow.timer >= bezierArrow.cooldown then
        bezierArrow.timer = 0
        bezierArrow.firing = false
        state.arrows = {}
    end
end

function bezierArrow:drawBarrel()
    -- Inherited function - implement if needed
end

function bezierArrow:shoot()
    bezierArrow.firing = true
    bezierArrow.timer = 0
    
    -- Fire immediately on shoot
    bezierArrow.fireAt(player.body:getX() + gun.lastAimDirection.x * 400,
        player.body:getY() + gun.lastAimDirection.y * 400, world)
end

-- Get active arrows (for damage checking, etc.)
function bezierArrow.getActiveArrows()
    return state.arrows
end

return bezierArrow