local pm = require("polyman")

-- globals
screen_height = 600
screen_width = 600
screen_flags =  {["resizable"]= true}

character_rotation = 0
prev_x = 0
prev_y = 0

num_coins = 50
coin_bods = {}

points = {}

function love.load()
    -- window -- 
    success = love.window.setMode( screen_width, screen_height, screen_flags )


    -- physics --
    
    world = love.physics.newWorld(0, 0)
    world:setCallbacks(beginContact, endContact, preSolve, postSolve)

    fence_body = love.physics.newBody(world,0,0,"static")
    fence_shape = love.physics.newChainShape(true, -100,-100,screen_width,-100,screen_width,screen_height,-100,screen_height)
    fence_fixture = love.physics.newFixture(fence_body,fence_shape)

    body = love.physics.newBody(world, love.mouse.getX(), love.mouse.getY(), "dynamic")
    shape = love.physics.newRectangleShape(90,90) -- collision is non-sense rn
    fixture = love.physics.newFixture(body, shape)
    joint = love.physics.newMouseJoint(body, love.mouse.getPosition())

    

    coin_shape = love.physics.newCircleShape(18)    
    createCoins(num_coins)
    

    -- graphics --
    character = love.graphics.newImage("gfx/doge.png")
    image = love.graphics.newImage("gfx/coin.png")
    character_width, character_height = character:getDimensions()
    png_width,png_height = image:getDimensions()

end

function love.draw()
    -- physics updates --
    local vx, vy = body:getLinearVelocity()
    local x, y = body:getPosition()
    local linear_score = round(vx ^ 2 + vy ^ 2, -4) / 10000

    -- Calculate the correct heading angle based on velocity direction
    local heading = 0
    if linear_score > 1 then
        heading = math.atan2(y - prev_y, x - prev_x)
        prev_x = x
        prev_y = y
    end

    -- Smoothly interpolate between current rotation and target heading
    -- character_rotation = quad_in_out(character_rotation, heading, 0.8) -- broken in signed axis 
    if math.abs(heading) > 0 then
        character_rotation = heading
    end

    -- draw updates --
    love.graphics.print("fps: " .. love.timer.getFPS(), 0, 0)
    love.graphics.print("linear_score: " .. linear_score, 0, 10)
    love.graphics.print("heading: " .. round(heading, 2), 0, 20)
    love.graphics.print("rotation: " .. round(character_rotation, 2), 0, 30)

    -- Draw character with correct rotation
    -- Adjust the origin to the center of the image for proper rotation
    
    love.graphics.draw(character, -- image
    body:getX(), -- x position
    body:getY(), -- y position
    character_rotation, -- rotation
    1, 1, -- scale x, scale y
    character_width / 2, character_height / 2 -- origin offset (center of image)
    )


    -- debug updates --
    -- score(linear_score)
    
    
    for i=1,num_coins do
    love.graphics.draw(image, coin_bods[i]:getX(), coin_bods[i]:getY(), 0,1,1,png_width/2, png_height/2)
    end
    -- print(points)

    -- table.insert(points,1,1)
    -- table.insert(points,1,1)
    

end

function love.update(dt)
    joint:setTarget(love.mouse.getPosition()) -- if mobile use love.touch.getPosition() -- can be an array with multiple touch points id = love.touch.getTouches()
    world:update(dt)
end

function love.resize(w, h)
    -- Update global dimensions
    screen_width = w
    screen_height = h
    
    -- Destroy the old fence fixture
    fence_fixture:destroy()
    
    -- Create a new fence with updated dimensions
    fence_shape = love.physics.newChainShape(true, -100, -100, screen_width + 100, -100, 
                                           screen_width + 100, screen_height + 100, -100, screen_height + 100)
    fence_fixture = love.physics.newFixture(fence_body, fence_shape)
    fence_fixture:setUserData("fence")
end

function round(x, n)
    n = math.pow(10, n or 0)
    x = x * n
    if x >= 0 then
        x = math.floor(x + 0.5)
    else
        x = math.ceil(x - 0.5)
    end
    return x / n
end

function score(linear_score)
    if linear_score > 1000 then
        print("+")
    elseif linear_score > 1 then
        print("-")
    end
end

function lerp(a, b, t)
    return a * (1 - t) + b * t
end


function quad_in_out(a, b, t)
    t = math.max(0, math.min(1, t)) -- Clamp t between 0 and 1
    if t <= 0.5 then
        return lerp(a, b, 2 * t * t)
    else
        t = t - 1
        return lerp(a, b, 1 - 2 * t * t)
    end
end

function load()
    -- Load image data and image
    imageData = love.image.newImageData("gfx/apple copy.png")
    _image = love.graphics.newImage(imageData)

    -- Get the dimensions of the image
    width, height = _image:getDimensions()

    -- Create a table that will contain the points of each opaque pixel
    -- (this is a crude method, avoided on large images)

    -- points = {}
    for x = 0, width - 1 do
        for y = 0, height - 1 do

            -- Get alpha value of pixel
            local _, _, _, alpha = imageData:getPixel(x, y)

            -- Apply a threshold to the alpha value
            if alpha >= .5 then
                table.insert(points, x)
                table.insert(points, y)
            end

        end
    end

    -- Apply convex hull
    points = pm.operations.convexHull(points)
    cull(points)
    return points
    -- Apply color background
    -- love.graphics.setBackgroundColor(0,.5,0)

end

function cull(array)
    for i = 0, 24/2 +3 do
        local rand = math.random(1, table.getn(array))
        table.remove(array, rand)
        table.remove(array, rand)
    end
end

function createCoins(n)
    for _=1,n do
    local _bod = love.physics.newBody(world,math.random(0,screen_width), math.random(0,screen_height), "dynamic")
    table.insert(coin_bods,1,_bod)
    _fixture = love.physics.newFixture(_bod,coin_shape)
    _fixture:setGroupIndex(69)
    end
    
end

function beginContact(fixture_a, fixture_b, contact)
    -- print(fixture_a,fixture_b, contact)
    -- print(fixture_b:getBody() == body)
    if fixture_a:getGroupIndex() == 69 then
        print("Player touched coin")
    end
end
-- function endContact(fixture_a, fixture_b, contact)
-- 	-- print(fixture_a,fixture_b, contact)
--     print(contact:getPositions())
-- end