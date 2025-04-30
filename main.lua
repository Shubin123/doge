math.randomseed(os.time())

-- globals
screen_height = 600
screen_width = 600
screen_flags = {
    ["resizable"] = true
}

character_rotation = 0
prev_x = 0
prev_y = 0
linear_score = 0
player_score = 0
num_coins = 300
coin_bods = {}
num_enemies = 2
enemies_bods = {}


points = {}

function love.load()
    -- window -- 
    success = love.window.setMode(screen_width, screen_height, screen_flags)

    -- physics --

    world = love.physics.newWorld(0, 0)
    world:setCallbacks(beginContact, endContact, preSolve, postSolve)

    fence_body = love.physics.newBody(world, 0, 0, "static")
    fence_shape = love.physics.newChainShape(true, -100, -100, screen_width, -100, screen_width, screen_height, -100,
        screen_height)
    fence_fixture = love.physics.newFixture(fence_body, fence_shape)

    body = love.physics.newBody(world, love.mouse.getX(), love.mouse.getY(), "dynamic")
    shape = love.physics.newRectangleShape(90, 90) -- collision is non-sense rn
    fixture = love.physics.newFixture(body, shape)
    joint = love.physics.newMouseJoint(body, love.mouse.getPosition())

    coin_shape = love.physics.newCircleShape(18)
    createCoins(num_coins)

    enemy_shape = love.physics.newCircleShape(100)
    createEnemies(num_enemies)
    -- graphics --
    character = love.graphics.newImage("gfx/doge.png")
    image = love.graphics.newImage("gfx/coin.png")
    enemy_image = love.graphics.newImage("gfx/enemy.png")

    character_width, character_height = character:getDimensions()
    png_width, png_height = image:getDimensions()
    enemy_width, enemy_height = enemy_image:getDimensions()

    animation = newAnimation(love.graphics.newImage("oldHero.png"), 16, 18, 1)

end

function love.draw()
    -- physics updates --
    local vx, vy = body:getLinearVelocity()
    local x, y = body:getPosition()
    linear_score = round(vx ^ 2 + vy ^ 2, -4) / 10000

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
    love.graphics.print("score: " .. player_score, screen_width / 2, 40)

    love.graphics.draw(character, -- image
    body:getX(), -- x position
    body:getY(), -- y position
    character_rotation, -- rotation
    1, 1, -- scale x, scale y
    character_width / 2, character_height / 2 -- origin offset (center of image)
    )

    

    for i = 1, num_coins do
        love.graphics.draw(image, coin_bods[i]:getX(), coin_bods[i]:getY(), 0, 1, 1, png_width / 2, png_height / 2)
    end
   

    for i = 1,num_enemies do
        love.graphics.draw(enemy_image, enemies_bods[i]:getX(),enemies_bods[i]:getY(), 0, 1, 1, png_width / 2, png_height / 2)
    end

end

function love.update(dt)
    -- love.graphics.draw(love.graphics.newImage("gfx/apple.png"))
    joint:setTarget(love.mouse.getPosition()) -- if mobile use love.touch.getPosition() -- can be an array with multiple touch points id = love.touch.getTouches()
    world:update(dt)

    animation.currentTime = animation.currentTime + dt
    if animation.currentTime >= animation.duration then
        animation.currentTime = animation.currentTime - animation.duration
    end
end

function love.resize(w, h)
    -- Update global dimensions
    screen_width = w
    screen_height = h

    -- Destroy the old fence fixture
    fence_fixture:destroy()

    -- Create a new fence with updated dimensions
    fence_shape = love.physics.newChainShape(true, -100, -100, screen_width, -100, screen_width, screen_height, -100,screen_height)
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

function createCoins(n)
    for _ = 1, n do
        local _bod = love.physics.newBody(world, math.random(0, screen_width), math.random(0, screen_height), "dynamic")
        table.insert(coin_bods, 1, _bod)
        _fixture = love.physics.newFixture(_bod, coin_shape)
        _fixture:setGroupIndex(69)
        
    end

end

function createEnemies(n)
    for _ = 1, n do
        local _bod = love.physics.newBody(world, math.random(0, screen_width), math.random(0, screen_height), "dynamic")
        table.insert(enemies_bods, 1, _bod)
        _fixture = love.physics.newFixture(_bod, enemy_shape)
        _fixture:setGroupIndex(777)

    end

end

function beginContact(fixture_a, fixture_b, contact)
    local body_a = fixture_a:getBody()
    local body_b = fixture_b:getBody()
    if (fixture_a:getGroupIndex() == 69 or fixture_b:getGroupIndex() == 69) then
        local ball_body = 0
        if (body_a == body) then 
            ball_body = body_b
        elseif (body_b == body) then
            ball_body = body_b
        end

        for i = 1, num_coins do
            if coin_bods[i] == ball_body then
                print("Deleting ball at index", i)
                table.remove(coin_bods, i)
                num_coins = num_coins - 1
                player_score = player_score + 1
                
                break

            end
        end
    end
end

function newAnimation(image, width, height, duration)
    local animation = {}
    animation.spriteSheet = image;
    animation.quads = {};

    for y = 0, image:getHeight() - height, height do
        for x = 0, image:getWidth() - width, width do
            table.insert(animation.quads, love.graphics.newQuad(x, y, width, height, image:getDimensions()))
        end
    end

    animation.duration = duration or 1
    animation.currentTime = 0

    return animation
end