--[[
  The car: parked on the home map, and yours to drive. Walk up to it and an
  arrow bobs over it with "[E] Drive"; press E and you're in. Driving, the
  player's body is the car's (the car is drawn where it is, facing the way
  it moves): faster, slower to get going, coasting when you let go, and as
  wide as the car, so it won't fit through doors. You can't shoot or dodge
  from it. E again gets you out beside it, and it stays parked facing the
  way it stopped. In multiplayer only the host (and single player) drives;
  clients see the host's car.

  The car key (an item in the bag, game/inventory.lua; it starts on the
  ground beside the car) calls it to you: it drives itself over, finding a
  way round what's in the way, and parks beside you. Using the key again
  while it's coming stops it.
]]
local block = require("game.block")
local skin = require("ui.skin")
local normalmap = require("lib.graphics.normalmap")
local nav = require("lib.nav")
local car = {}
car.cars = {} -- List to store multiple car instances
car.scale = 1

local ENTER_RANGE = 80     -- px from the car you can get in
local CAR_RADIUS = 24      -- px, the player's body while driving
local HANDLING = { maxSpeed = 440, acceleration = 650, friction = 0.97 }
local HINT_TIME = 3        -- seconds "[E] Get out" shows after getting in

car.driving = nil          -- the car the player's in, if any
local walking              -- the player's own handling, back on getting out
local enteredAt = -math.huge
local font

function car.load(world)
    -- Clear existing cars to prevent duplicates on reload
    car.cars = {}
    -- Create a block instance for car using the superclass
    car.blockInstance = block.new("gfx/vehicles/car.dds", 128, 128, 2, 450, car.scale, world, var.game_width / 2 + 200, var.game_height / 2 + 100)
    
    -- Create an initial car instance for all players
    table.insert(car.cars, car.blockInstance)
    -- it stands up, so it's lit by its normals (lib/graphics/normalmap.lua)
    car.normals = normalmap.of(car.blockInstance.spriteSheet, car.blockInstance.animation.quads,
        "gfx/vehicles/car.dds")
    car.blockInstance:setInUse(false)
    car.blockInstance.headingX, car.blockInstance.headingY = 1, 0.35
    -- Disable physics on clients, only host handles physics and collisions
    if var.multiplayer and var.multiplayer > 1 then
        car.blockInstance.body:setActive(false)
    end
    car.driving, walking = nil, nil
    font = love.graphics.newFont("gfx/menu/Px437_IBM_VGA_8x16.ttf", 16)
    font:setFilter("nearest", "nearest")
end

local function canDrive()
    return not var.multiplayer or var.multiplayer == 1
end

--- The parked car within reach of (x, y), if any.
function car.nearest(x, y)
    local best, bestD = nil, ENTER_RANGE
    for _, c in ipairs(car.cars) do
        if not c.inUse then
            local d = math.sqrt((c.body:getX() - x) ^ 2 + (c.body:getY() - y) ^ 2)
            if d < bestD then
                best, bestD = c, d
            end
        end
    end
    return best
end

-- The player's collision circle: the car's while driving, their own after
local function setPlayerRadius(r)
    local old = player.fixture
    local fixture = love.physics.newFixture(player.body, love.physics.newCircleShape(r))
    fixture:setGroupIndex(old:getGroupIndex())
    fixture:setUserData(old:getUserData())
    old:destroy()
    player.fixture = fixture
end

function car.enter(c)
    c:setInUse(true, "player")
    car.driving = c
    player.inCar = c
    enteredAt = love.timer.getTime()
    player.body:setPosition(c.body:getPosition())
    player.body:setLinearVelocity(0, 0)
    c.body:setActive(false) -- the player's body is the car now
    setPlayerRadius(CAR_RADIUS)
    walking = { maxSpeed = player.maxSpeed, acceleration = player.acceleration, friction = player.friction }
    player.maxSpeed, player.acceleration, player.friction = HANDLING.maxSpeed, HANDLING.acceleration,
        HANDLING.friction
    if princess then princess.on = false end
    gun.mousePressed = false
end

--- Get out beside the car, which stays parked where it stopped.
function car.exit()
    local c = car.driving
    if not c then return end
    local x, y = player.body:getPosition()
    c:setInUse(false)
    c.body:setActive(true)
    c.body:setPosition(x, y)
    c.body:setLinearVelocity(0, 0)
    car.driving, player.inCar = nil, nil
    setPlayerRadius(10)
    player.maxSpeed, player.acceleration, player.friction = walking.maxSpeed, walking.acceleration, walking.friction
    -- out of the driver's side: to the left of the way it faces
    local hx, hy = c.headingX or 1, c.headingY or 0
    local n = math.sqrt(hx * hx + hy * hy)
    player.body:setPosition(x + hy / n * 46, y - hx / n * 46)
    player.body:setLinearVelocity(0, 0)
    if princess then princess.on = true end
end

--- E: get in the car you're next to, or out of the one you're in. True
--- when it took the key.
function car.keypressed(key)
    if key ~= "e" or var.State == "menu" or not canDrive() then return false end
    if car.driving then
        car.exit()
        return true
    end
    if var.indoors then return false end
    local c = car.nearest(player.body:getPosition())
    if c then
        car.enter(c)
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- Autopilot: the car key calls the car to you. It plans a way on a grid
-- (lib/nav.lua: A*, each cell tested against the world's static fixtures,
-- grown by the car's size, the first time the search reaches it), and
-- drives it, turning no faster than a car can. It plans again as you move,
-- and when it's held up, after backing off.
--------------------------------------------------------------------------------

local CELL = 32           -- px, the planning grid
local CLEARANCE = 36      -- px from the car's middle to anything it mustn't touch
local MAX_SEARCH = 6000   -- cells a plan looks at before making for the nearest it reached
local SUMMON_RANGE = 4000 -- px: further off, it's out of the key's reach
local ARRIVE = 72         -- px from you it parks
local CRUISE = 300        -- px/s
local TURN_RATE = 5       -- rad/s
local REPLAN = 1.0        -- s between plans while you move about
local PROGRESS = 0.75     -- s it has to get closer in, or it's held up
local BACK_OFF = 0.5      -- s it backs off for when it's held up
local GIVE_UP = 45        -- s

-- Stop it where it is, with a word about why
local function park(c, text)
    c.autopilot = nil
    c.body:setLinearVelocity(0, 0)
    c.body:setAngularVelocity(0)
    if text then inventory.notify(text) end
end

local function drive(c, dt)
    local ap = c.autopilot
    local x, y = c.body:getPosition()
    local px, py = player.body:getPosition()
    local d = math.sqrt((px - x) ^ 2 + (py - y) ^ 2)
    if d < ARRIVE then return park(c, "Your car is here") end
    ap.t = ap.t + dt
    if ap.t > GIVE_UP then return park(c, "The car couldn't get to you") end

    -- Held up: hardly any closer for a while. Back off a moment, then plan again.
    ap.check = ap.check + dt
    if ap.check > PROGRESS then
        if ap.checkD - d < 20 and ap.back <= 0 then
            ap.back, ap.path = BACK_OFF, nil
        end
        ap.check, ap.checkD = 0, d
    end
    -- (its heading is its own: backing off doesn't turn it round)
    local heading = math.atan2(c.headingY or 0, c.headingX or 1)
    local vx, vy = c.body:getLinearVelocity()
    local speed = math.max(0, vx * math.cos(heading) + vy * math.sin(heading))
    if ap.back > 0 then
        ap.back = ap.back - dt
        c.body:setLinearVelocity(-math.cos(heading) * 120, -math.sin(heading) * 120)
        c.body:setAngularVelocity(0)
        return
    end

    ap.since = ap.since + dt
    if not ap.path or (ap.since > REPLAN and (px - ap.goalX) ^ 2 + (py - ap.goalY) ^ 2 > CELL * CELL) then
        ap.path, ap.since, ap.goalX, ap.goalY, ap.next = ap.grid:path(x, y, px, py, MAX_SEARCH), 0, px, py, 1
        if not ap.path then return park(c, "The car can't get out") end
        if #ap.path == 0 then return park(c, "The car got as close as it could") end
    end
    -- The next point on the way, past any it's reached
    local path = ap.path
    while ap.next < #path and (path[ap.next][1] - x) ^ 2 + (path[ap.next][2] - y) ^ 2 < (CELL * 0.75) ^ 2 do
        ap.next = ap.next + 1
    end
    local wx, wy = path[ap.next][1], path[ap.next][2]
    if ap.next == #path and (wx - x) ^ 2 + (wy - y) ^ 2 < (CELL * 0.75) ^ 2 then
        -- as near as it can get (you're somewhere it doesn't fit)
        return park(c, d < ARRIVE * 2.5 and "Your car is here" or "The car got as close as it could")
    end

    -- Turn toward it no faster than TURN_RATE; slow down for a tight turn and near you
    local want = math.atan2(wy - y, wx - x)
    local turn = (want - heading + math.pi) % (2 * math.pi) - math.pi
    heading = heading + math.max(-TURN_RATE * dt, math.min(TURN_RATE * dt, turn))
    local target = math.min(CRUISE, math.max(70, (d - ARRIVE) * 2))
    if math.abs(turn) > 1.2 then target = math.min(target, 110) end
    speed = speed + math.max(-HANDLING.acceleration * 2 * dt, math.min(HANDLING.acceleration * dt, target - speed))
    c.body:setLinearVelocity(math.cos(heading) * speed, math.sin(heading) * speed)
    c.body:setAngularVelocity(0)
    c.headingX, c.headingY = math.cos(heading), math.sin(heading)
end

--- The car key: call the parked car to you, or stop it if it's on its way.
--- True and what's happening, or false and why not.
function car.summon()
    if not canDrive() then return false, "Only the host can call the car" end
    if car.driving then return false, "You're in the car" end
    local c = car.cars[1]
    if not (c and c.body and player.body) then return false, "There's no car" end
    if c.autopilot then
        park(c)
        return true, "The car stops"
    end
    local x, y = c.body:getPosition()
    local px, py = player.body:getPosition()
    local d = math.sqrt((px - x) ^ 2 + (py - y) ^ 2)
    if d > SUMMON_RANGE then return false, "The car's too far away" end
    if d < ARRIVE + 16 then return false, "The car's right here" end
    -- (a grid of its own each time: the world may have changed since)
    c.autopilot = { t = 0, since = 0, grid = nav.new(CELL, CLEARANCE), check = 0, checkD = d, back = 0 }
    return true, "The car's on its way"
end

--- Where the key lies when nobody has it: just in front of the car.
function car.keySpot()
    local c = car.cars[1]
    if not (c and c.body) then return nil end
    local x, y = c.body:getPosition()
    return x - 40, y + 56
end

--- Each frame: the car you're in faces the way you're going (and keeps that
--- heading when you stop); a car the key called drives itself over.
function car.update(dt)
    for _, c in ipairs(car.cars) do
        if c.autopilot then
            if c.inUse or not canDrive() or not player.body then
                c.autopilot = nil
            else
                drive(c, dt)
            end
        end
    end
    local c = car.driving
    if not c then return end
    local vx, vy = player.body:getLinearVelocity()
    if vx * vx + vy * vy > 25 * 25 then
        c.headingX, c.headingY = vx, vy
    end
end

--- The indicator: an arrow bobbing over a car you can get in, with
--- "[E] Drive", and for a moment after getting in, "[E] Get out". Screen
--- space, under the CRT with the rest of the UI.
function car.drawUI()
    if var.State == "menu" or not canDrive() or not player.body then return end
    local c, text
    if car.driving then
        if love.timer.getTime() - enteredAt < HINT_TIME then
            c, text = car.driving, "[E] Get out"
        end
    elseif not var.indoors then
        c = car.nearest(player.body:getPosition())
        text = "[E] Drive"
    end
    if not c then return end

    local u = skin.guiScale()
    local ts = skin.textScale(u)
    local x, y = c.body:getPosition()
    if c == car.driving then x, y = player.body:getPosition() end
    local sx = (camera.pos.x + x * camera.zoom) / u
    local sy = (camera.pos.y + (y - 40) * camera.zoom) / u
    local bob = math.floor(math.sin(love.timer.getTime() * 6) * 2 + 0.5)

    local prevFont = love.graphics.getFont()
    love.graphics.push()
    love.graphics.origin()
    love.graphics.setShader()
    love.graphics.setFont(font)
    love.graphics.scale(u)
    if not car.driving then
        -- a down arrow, outlined, bobbing over the car
        local ay = sy - 6 + bob
        love.graphics.setColor(0.08, 0.08, 0.10, 1)
        love.graphics.polygon("fill", sx - 6, ay - 5, sx + 6, ay - 5, sx, ay + 3)
        love.graphics.setColor(1.00, 0.84, 0.20, 1)
        love.graphics.polygon("fill", sx - 4, ay - 4, sx + 4, ay - 4, sx, ay + 1)
        skin.printCentered(text, sx, ay - 16, ts, skin.YELLOW)
    else
        skin.printCentered(text, sx, sy - 12, ts, skin.WHITE)
    end
    love.graphics.pop()
    love.graphics.setFont(prevFont)
    love.graphics.setColor(1, 1, 1, 1)
end

function car.populate()
    -- Add cars to the dynamic draw list for rendering
    for i, currentCar in ipairs(car.cars) do
        -- Only draw host's car if multiplayer > 2
        -- if var.multiplayer > 2 and i > 1 then
        --     -- Skip drawing non-host cars in this mode
        --     goto continue
        -- end
        
        local cx, cy = 0, 0
        local v =0
        local vx, vy = 0, 0
        if currentCar.inUse then 
            
            cx,cy,v = currentCar:updatePhysics(player.body)
            cx, cy = player.body:getPosition() -- where it is this frame, not last
            vx = v.x
            vy = v.y
        else
            cx, cy = currentCar.body:getX(), currentCar.body:getY()
            vx, vy = currentCar.body:getLinearVelocity()
            currentCar.body:getFixtures()[1]:setGroupIndex(-2)
        end
        -- Stopped (or parked), it keeps facing the way it last went; driving
        -- itself, the way it's heading (even backing off)
        if (vx * vx + vy * vy < 25 * 25 or currentCar.autopilot) and currentCar.headingX then
            vx, vy = currentCar.headingX, currentCar.headingY
        end
        
        -- On clients, use networked position directly since physics is disabled
        if var.multiplayer then
        if var.multiplayer > 1 and renderer.networked_state and renderer.networked_state.cars and renderer.networked_state.cars[tostring(i)] then
            local netCar = renderer.networked_state.cars[tostring(i)]
            cx, cy = netCar.x, netCar.y
            vx, vy = netCar.vx or 0, netCar.vy or 0
        end
    end
        -- Add to draw list using superclass method
        -- Centred on its body: the car sits in the middle of each 128 px frame,
        -- a little low (the offset was a fraction of the whole sheet, which
        -- drew it ~140 px left of and ~50 px below where it really was)
        currentCar:addToDrawList(dynamic_draw_list, cx, cy, vx, vy, 130, 64, 70)
        -- Update the source_object_type and car_id for identification
        dynamic_draw_list[#dynamic_draw_list].source_object_type = "car"
        dynamic_draw_list[#dynamic_draw_list].car_id = i
        dynamic_draw_list[#dynamic_draw_list].normal_map = car.normals
        
        -- ::continue::
    end
end

function car.updateFromNetwork(networkedCars)
    if var.multiplayer and var.multiplayer > 1 then -- Only clients update from network data
        for carId, carData in pairs(networkedCars) do
            local carIndex = tonumber(carId)
            if carIndex and car.cars[carIndex] then
                local currentCar = car.cars[carIndex]
                currentCar.body:setX(carData.x)
                currentCar.body:setY(carData.y)
                if carData.vx and carData.vy then
                    currentCar.body:setLinearVelocity(carData.vx, carData.vy)
                end
                currentCar.inUse = carData.inUse
                currentCar.controllingPlayer = carData.controllingPlayer or ""
            end
        end
    end
end

function car.getNetworkData()
    local carData = {}
    for i, currentCar in ipairs(car.cars) do
        local cx, cy = currentCar.body:getX(), currentCar.body:getY()
        local vx, vy = currentCar.body:getLinearVelocity()
        carData[tostring(i)] = {
            x = cx,
            y = cy,
            vx = vx,
            vy = vy,
            inUse = currentCar.inUse,
            controllingPlayer = currentCar.controllingPlayer or ""
        }
    end
    return carData
end

return car
