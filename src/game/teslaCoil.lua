local teslaCoil = {}
local config = {
    base_x = 0,
    base_y = 0,
    coil_height = 10,
    spark_count = 5,
    spark_range = 10,
    bolt_segments = 10, --with statup
    bolt_deviation = 50,
    endpoint_spread = 80, -- How much the endpoints spread out
    endpoint_deviation = 30, -- Additional random deviation at endpoints
    animation_speed = 1,
    collision_radius = 15, -- Radius for endpoint collision detection
    lock_range = 400, -- Bolts attach to enemies up to this far from the coil...
    lock_angle = 60, -- ...and up to this many degrees either side of the aim
    colors = {
        spark = { 1, 1, 1 },
        glow = { 0.35, 0.6, 1.0 } -- electric blue around the white core
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
teslaCoil.cooldown = 5
teslaCoil.ammoPerSecond = 4 -- universal ammo drained while the bolts are live

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
    
    -- Its own negative group, so endpoints never touch each other and contacts
    -- route as "tesla". (They used -1, the player's group: every endpoint that
    -- landed on an enemy hurt the player, and on a coin, collected it.)
    fixture:setGroupIndex(collision.groups.tesla)
    fixture:setSensor(true) -- Make it a sensor so it doesn't physically collide
    
    -- Store reference to hit object
    body:setUserData({
        type = "tesla_endpoint",
        collision_group = collision.groups.tesla,
        hit_object = hit_object
    })
    
    return body
end

-- Create jagged bolt segments with collision detection. With `target_body`
-- the bolt is attached to it: no raycast (nothing in between stops it short)
-- and its last point lands exactly on (x2, y2).
local function generateBolt(world, x1, y1, x2, y2, collatz_val, target_body)
    local segments = {}
    
    -- First, check for collision along the path
    local final_x, final_y, hit_object = x2, y2, target_body
    if not target_body then
        final_x, final_y, hit_object = raycastToCollision(world, x1, y1, x2, y2)
    end
    
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
    if target_body then
        -- The endpoint jitter above would leave the arc hanging off the enemy.
        segments[#segments] = { x = final_x, y = final_y }
    end
    
    -- Create collider at the endpoint
    if world then
        local collider = createEndpointCollider(world, final_x, final_y, hit_object)
        table.insert(state.colliders, collider)
    end

    return segments
end

local function drawPixelLine(x0, y0, x1, y1, pixel_size)
    x0 = math.floor(x0 + 0.5)
    y0 = math.floor(y0 + 0.5)
    x1 = math.floor(x1 + 0.5)
    y1 = math.floor(y1 + 0.5)

    local dx = math.abs(x1 - x0)
    local dy = -math.abs(y1 - y0)
    local sx = x0 < x1 and 1 or -1
    local sy = y0 < y1 and 1 or -1
    local err = dx + dy
    pixel_size = pixel_size or 2
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

-- Draw every bolt as an electric arc, additively: a wide blue haze, a
-- blue-white body, then the white pixel core (the only part whiteNeon's glow
-- threshold blooms). `toX/toY` map a bolt point to the space being drawn in;
-- `scale` is that space's pixels per world unit. Brightness follows
-- var.tracer_brightness, like the bullet tracers.
local arcPoints = {}
local function drawArcs(toX, toY, scale)
    local brightness = math.min(1, var.tracer_brightness or 1)
    local glow, spark = config.colors.glow, config.colors.spark
    love.graphics.setBlendMode("add")
    local layers = {
        { 12, glow[1], glow[2], glow[3], 0.4 },
        { 4, (glow[1] + 1) / 2, (glow[2] + 1) / 2, (glow[3] + 1) / 2, 0.75 },
    }
    for _, layer in ipairs(layers) do
        love.graphics.setLineWidth(layer[1] * scale)
        love.graphics.setColor(layer[2], layer[3], layer[4], layer[5] * brightness)
        for _, bolt in ipairs(state.bolts) do
            if #bolt > 1 then
                for i = 1, #bolt do
                    arcPoints[2 * i - 1], arcPoints[2 * i] = toX(bolt[i].x), toY(bolt[i].y)
                end
                for i = 2 * #bolt + 1, #arcPoints do arcPoints[i] = nil end
                love.graphics.line(arcPoints)
            end
        end
    end
    love.graphics.setColor(spark[1], spark[2], spark[3], brightness)
    for _, bolt in ipairs(state.bolts) do
        for i = 1, #bolt - 1 do
            drawPixelLine(toX(bolt[i].x), toY(bolt[i].y), toX(bolt[i + 1].x), toY(bolt[i + 1].y), 2 * scale)
        end
    end
end

local function worldX(x) return x end
local function screenX(x) return camera.pos.x + x * camera.zoom end
local function screenY(y) return camera.pos.y + y * camera.zoom end

function teslaCoil.renderPixelLine(drawable)
    local visible = #state.bolts > 0 and (var.tracer_brightness or 1) > 0
    if var.graphics_high then
        local currentShader =  love.graphics.getShader()
    love.graphics.push()

    love.graphics.reset()
    if not visible then
        light.skipChain() -- nothing to glow (see light.skipChain)
    else
    -- Into the glow chain for the bloom (screen space: the chain's passes
    -- need an untransformed reset() state)...
    whiteNeon(function()
        drawArcs(screenX, screenY, camera.zoom)
        love.graphics.setBlendMode("alpha")
        love.graphics.setColor(1, 1, 1, 1)
    end)
    end
  love.graphics.pop()
    -- ...and again on top of it, under the camera transform, so the arc stays
    -- crisp instead of only showing through the blur.
    if visible then
        drawArcs(worldX, worldX, 1)
        love.graphics.setBlendMode("alpha")
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setLineWidth(1)
    end
  love.graphics.setShader(currentShader)

else
    if visible then
        drawArcs(worldX, worldX, 1)
        love.graphics.setBlendMode("alpha")
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setLineWidth(1)
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

-- Enemies the bolts can attach to: alive, within lock_range of the coil and
-- within lock_angle of the aim (any direction while there is no aim yet),
-- nearest first.
local function findTargets(sx, sy, aim_x, aim_y)
    local targets = {}
    if not (enemy and enemy.enemies) then return targets end
    local aim_len = math.sqrt(aim_x * aim_x + aim_y * aim_y)
    local min_cos = math.cos(math.rad(config.lock_angle))
    for _, e in ipairs(enemy.enemies) do
        if not e.dead and e.body and not e.body:isDestroyed() then
            local ex, ey = e.body:getPosition()
            local dx, dy = ex - sx, ey - sy
            local d = math.sqrt(dx * dx + dy * dy)
            if d <= config.lock_range and (aim_len < 1e-6 or d < 1e-6
                    or (dx * aim_x + dy * aim_y) / (d * aim_len) >= min_cos) then
                targets[#targets + 1] = { body = e.body, x = ex, y = ey, d = d }
            end
        end
    end
    table.sort(targets, function(a, b) return a.d < b.d end)
    return targets
end

-- Create new bolts. Each one attaches to an enemy in range (spread over the
-- nearest; with fewer enemies than bolts, several converge on one), and
-- since this runs every frame while firing, the arcs follow them. With no
-- enemy in range the bolts spray around (x, y) as before.
function teslaCoil.fireAt(x, y, world)
    cleanupColliders() -- Clean up previous colliders
    state.bolts = {}
    
    local sx, sy = player.body:getX() + gun.lastAimDirection.x * 50, player.body:getY() + gun.lastAimDirection.y * 50
    state.pos = y
    local targets = findTargets(sx, sy, gun.lastAimDirection.x, gun.lastAimDirection.y)
    
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

        local target = targets[(i - 1) % math.max(1, #targets) + 1]
        local bolt
        if target then
            bolt = generateBolt(world, sx, sy, target.x, target.y, val, target.body)
        else
            bolt = generateBolt(world, sx, sy, tx, ty, val)
        end
        table.insert(state.bolts, bolt)
    end
end

function teslaCoil:update(dt)
    teslaCoil.timer = teslaCoil.timer + dt
    if teslaCoil.timer < teslaCoil.cooldown and teslaCoil.firing then
        if gun.useAmmo(teslaCoil.ammoPerSecond * dt) then
            -- You'll need to pass the physics world here
            teslaCoil.fireAt(player.body:getX() + gun.lastAimDirection.x * 400,
                player.body:getY() + gun.lastAimDirection.y * 400, world)
        else
            teslaCoil.timer = teslaCoil.cooldown -- out of ammo: wind down next frame
        end
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

--  inherited function
function teslaCoil:drawBarrel()
end

function teslaCoil:shoot()
    if not gun.canFire(teslaCoil) then return end
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