local teslaCoil = {}
local config = {
    base_x = 0,
    base_y = 0,
    coil_height = 10,
    spark_count = 10,
    spark_range = 10,
    bolt_segments = 10,
    bolt_deviation = 50,
    endpoint_spread = 80, -- How much the endpoints spread out
    endpoint_deviation = 30, -- Additional random deviation at endpoints
    animation_speed = 1,
    collision_radius = 15, -- Radius for endpoint collision detection
    colors = {
        spark = { 1, 1, 1 }
    }
}

local state = {
    bolts = {},
    pos = 0,
    colliders = {}, -- Store collider bodies for cleanup
    encapsulated_objects = {} -- Objects hit by tesla coil
}
teslaCoil.firing = false
teslaCoil.timer = 0
teslaCoil.cooldown = 1

-- Generate a Collatz sequence
local function collatz(n)
    local seq = {}
    while n ~= 1 do
        table.insert(seq, n)
        if n % 2 == 0 then n = n / 2 else n = 3 * n + 1 end
    end
    table.insert(seq, 1)
    return seq
end

-- Raycast to find collision point
local function raycastToCollision(world, x1, y1, x2, y2)
    local hit_x, hit_y = x2, y2
    local hit_object = nil
    
    -- Perform raycast from start to end point
    world:rayCast(x1, y1, x2, y2, function(fixture, x, y, xn, yn, fraction)
        -- Skip tesla coil's own colliders (negative collision group)
        local body = fixture:getBody()
        local userData = body:getUserData()
        
        -- Skip if it's a tesla coil collider (negative index)
        if userData and userData.collision_group and userData.collision_group < 0 then
            return 1 -- Continue raycast
        end
        
        -- We hit something, stop here
        hit_x, hit_y = x, y
        hit_object = body
        return 0 -- Stop raycast
    end)
    
    return hit_x, hit_y, hit_object
end

-- Create endpoint collider
local function createEndpointCollider(world, x, y, hit_object)
    local body = love.physics.newBody(world, x, y, "static")
    local shape = love.physics.newCircleShape(config.collision_radius)
    local fixture = love.physics.newFixture(body, shape)
    
    -- Set negative collision group so tesla coil parts don't collide with each other
    fixture:setGroupIndex(-1)
    fixture:setSensor(true) -- Make it a sensor so it doesn't physically collide
    
    -- Store reference to hit object
    body:setUserData({
        type = "tesla_endpoint",
        collision_group = -1,
        hit_object = hit_object
    })
    
    return body
end

-- Create jagged bolt segments with collision detection
local function generateBolt(world, x1, y1, x2, y2, collatz_val)
    local segments = {}
    
    -- First, check for collision along the path
    local final_x, final_y, hit_object = raycastToCollision(world, x1, y1, x2, y2)
    
    -- If we hit something, record it
    if hit_object then
        table.insert(state.encapsulated_objects, hit_object)
    end
    
    -- Generate segments to the collision point (or original endpoint)
    local dx, dy = final_x - x1, final_y - y1
    local len = math.sqrt(dx * dx + dy * dy)

    for i = 0, config.bolt_segments do
        local t = i / config.bolt_segments
        local base_x = x1 + dx * t
        local base_y = y1 + dy * t

        -- Increase deviation factor towards the end
        local dev_factor = (1 - math.abs(t - 0.5) * 2) -- stronger in the middle
        local endpoint_factor = t * t -- quadratic increase towards endpoint
        
        local angle = math.pi * 2 * ((collatz_val % 360) / 360)
        local base_deviation = config.bolt_deviation * dev_factor
        local endpoint_deviation = config.endpoint_deviation * endpoint_factor
        
        local offset_x = math.cos(angle + i) * (base_deviation + endpoint_deviation) * (math.random() - 0.5)
        local offset_y = math.sin(angle + i) * (base_deviation + endpoint_deviation) * (math.random() - 0.5)

        table.insert(segments, { x = base_x + offset_x, y = base_y + offset_y })
    end
    
    -- Create collider at the endpoint
    if world then
        local collider = createEndpointCollider(world, final_x, final_y, hit_object)
        table.insert(state.colliders, collider)
    end

    return segments
end

local function drawPixelLine(x0, y0, x1, y1)
    x0 = math.floor(x0 + 0.5)
    y0 = math.floor(y0 + 0.5)
    x1 = math.floor(x1 + 0.5)
    y1 = math.floor(y1 + 0.5)

    local dx = math.abs(x1 - x0)
    local dy = -math.abs(y1 - y0)
    local sx = x0 < x1 and 1 or -1
    local sy = y0 < y1 and 1 or -1
    local err = dx + dy
    local pixel_size = 2
    while true do
        love.graphics.rectangle("fill", x0 - pixel_size / 2, y0 - pixel_size / 2, pixel_size, pixel_size)

        if x0 == x1 and y0 == y1 then break end
        local e2 = 2 * err
        if e2 >= dy then
            err = err + dy; x0 = x0 + sx
        end
        if e2 <= dx then
            err = err + dx; y0 = y0 + sy
        end
    end
end

-- Bresenham line plot
function teslaCoil.renderPixelLine(drawable)
    if var.graphics_high then
        local currentShader =  love.graphics.getShader()
    love.graphics.push()

    love.graphics.reset()
    
    whiteNeon(function()
    for _, bolt in ipairs(state.bolts) do
        for i = 1, #bolt - 1 do
            drawPixelLine(camera.pos.x + bolt[i].x* camera.zoom,camera.pos.y + bolt[i].y * camera.zoom,camera.pos.x + bolt[i + 1].x * camera.zoom,camera.pos.y + bolt[i + 1].y * camera.zoom)
        end
    end
  end)
  love.graphics.pop()
  love.graphics.setShader(currentShader)

else
     for _, bolt in ipairs(state.bolts) do
        for i = 1, #bolt - 1 do
            drawPixelLine(bolt[i].x, bolt[i].y, bolt[i + 1].x, bolt[i + 1].y)
        end
    end
    end
end

local function populatePixelLineBatched(bolts)
    table.insert(dynamic_draw_list, {
        sort_y = -state.pos + 300,
        bolt = bolts,
        draw_type = "teslaCoil"
    })
end

-- Draw bolts
function teslaCoil.populate()
    local color = config.colors.spark
    populatePixelLineBatched(state.bolts)
end

-- Clean up colliders
local function cleanupColliders()
    for _, collider in ipairs(state.colliders) do
        if collider and not collider:isDestroyed() then
            collider:destroy()
        end
    end
    state.colliders = {}
    state.encapsulated_objects = {}
end

-- Create new bolts with collision detection
function teslaCoil.fireAt(x, y, world)
    cleanupColliders() -- Clean up previous colliders
    state.bolts = {}
    
    local sx, sy = player.body:getX() + gun.lastAimDirection.x * 50, player.body:getY() + gun.lastAimDirection.y * 50
    state.pos = y
    
    for i = 1, config.spark_count do
        local start_num = 3 + i * 2
        local seq = collatz(start_num)
        local seq_pos = (i % #seq) + 1
        local val = seq[seq_pos]

        -- Create more spread in the angle calculation
        local base_angle = (val % 360) * (math.pi / 180)
        local spread_angle = (i / config.spark_count) * math.pi * 2 -- Full circle spread
        local random_spread = (math.random() - 0.5) * (config.endpoint_spread * math.pi / 180) -- Random spread in radians
        
        local angle = base_angle + spread_angle + random_spread
        local dist = config.spark_range + (val % 10) + math.random() * 20 -- Add some distance variation
        
        local tx = x + math.cos(angle) * dist
        local ty = y + math.sin(angle) * dist

        local bolt = generateBolt(world, sx, sy, tx, ty, val)
        table.insert(state.bolts, bolt)
    end
end

function teslaCoil.update(dt)
    teslaCoil.timer = teslaCoil.timer + dt
    if teslaCoil.timer < teslaCoil.cooldown and teslaCoil.firing then
        -- You'll need to pass the physics world here
        teslaCoil.fireAt(player.body:getX() + gun.lastAimDirection.x * 400,
            player.body:getY() + gun.lastAimDirection.y * 400, world)
    elseif teslaCoil.timer >= teslaCoil.cooldown then
        teslaCoil.timer = 0
        teslaCoil.firing = false
        cleanupColliders() -- Clean up when stopping
        state = {
            bolts = {},
            pos = 0,
            colliders = {},
            encapsulated_objects = {}
        }
    end
end

function teslaCoil.start()
    teslaCoil.firing = true
end

-- Get list of objects currently encapsulated by tesla coil
function teslaCoil.getEncapsulatedObjects()
    return state.encapsulated_objects
end

-- Check if a specific object is encapsulated
function teslaCoil.isObjectEncapsulated(object)
    for _, encap_obj in ipairs(state.encapsulated_objects) do
        if encap_obj == object then
            return true
        end
    end
    return false
end

return teslaCoil