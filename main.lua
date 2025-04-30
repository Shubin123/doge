--[[

    Wed Apr 30th #Andrew

- Refactored the code
- Changed stats display method
- created a initalize_game function --> works towards a loading screen method
- improved performance of game somehow it feels smoother
- cleaned up a lot of the code and random spacing/commenting
- "smoothed" a lot of the movement. 


]]

math.randomseed(os.time())

ScreenInfo = {
    screen_height = 600,
    screen_width = 600,
    screen_flags = {
        ["resizable"] = true
    }
}

PlayerInfo = {
    character_rotation = 0,
    prev_x = 0,
    prev_y = 0,
    linear_score = 0,
    player_score = 0
}

EntityInfo = {
    num_coins = 10,
    coin_bods = {},
    num_enemies = 1,
    enemies_bods = {}
}

LoadingInfo = {
    images_to_load = nil,
    loading_index = nil,
    assets = nil
}

StatsDisplay = {
    x = 10,                  
    y = 10,                  
    padding = 8,             
    width = 180,             
    lineHeight = 14,         
    bgColor = {0.1, 0.1, 0.1, 0.75}, 
    textColor = {0.9, 0.9, 0.9, 1.0}, 
    scoreY = 10,             
    scoreColor = {1.0, 1.0, 1.0, 1.0} 
}

Points = {}
State = nil

function love.load()
    success = love.window.setMode(ScreenInfo.screen_width, ScreenInfo.screen_height, ScreenInfo.screen_flags)
    State = "loading"
    LoadingInfo.images_to_load = {"doge.png", "coin.png", "enemy.png", "oldHero.png"}
    LoadingInfo.loading_index = 1
    LoadingInfo.assets = {}
end

function love.update(dt)
    if State == "loading" then
        local t = love.timer.getTime()
        while LoadingInfo.loading_index <= #LoadingInfo.images_to_load do
            local image_name = LoadingInfo.images_to_load[LoadingInfo.loading_index]
            LoadingInfo.assets[image_name] = love.graphics.newImage("gfx/" .. image_name)
            LoadingInfo.loading_index = LoadingInfo.loading_index + 1
            if love.timer.getTime() - t > 1/50 then
                break
            end
        end
        if LoadingInfo.loading_index > #LoadingInfo.images_to_load then
            State = "game"
            initialize_game()
        end
    elseif State == "game" then
        joint:setTarget(love.mouse.getPosition())
        world:update(dt)
        animation.currentTime = animation.currentTime + dt
        if animation.currentTime >= animation.duration then
            animation.currentTime = animation.currentTime - animation.duration
        end
    end
end

function initialize_game()

    world = love.physics.newWorld(0, 0)
    world:setCallbacks(beginContact, endContact, preSolve, postSolve)

    fence_body = love.physics.newBody(world, 0, 0, "static")
    fence_shape = love.physics.newChainShape(true, -100, -100, ScreenInfo.screen_width, -100, ScreenInfo.screen_width, ScreenInfo.screen_height, -100, ScreenInfo.screen_height)
    fence_fixture = love.physics.newFixture(fence_body, fence_shape)

    body = love.physics.newBody(world, love.mouse.getX(), love.mouse.getY(), "dynamic")
    shape = love.physics.newRectangleShape(90, 90)
    fixture = love.physics.newFixture(body, shape)
    joint = love.physics.newMouseJoint(body, love.mouse.getPosition())

    coin_shape = love.physics.newCircleShape(18)
    createCoins(EntityInfo.num_coins)

    enemy_shape = love.physics.newCircleShape(100)
    createEnemies(EntityInfo.num_enemies)

    character = LoadingInfo.assets["doge.png"]
    image = LoadingInfo.assets["coin.png"]
    enemy_image = LoadingInfo.assets["enemy.png"]
    animation = newAnimation(LoadingInfo.assets["oldHero.png"], 16, 18, 1)

    character_width, character_height = character:getDimensions()
    png_width, png_height = image:getDimensions()
    enemy_width, enemy_height = enemy_image:getDimensions()
end

function love.draw()
    if State == "loading" then

        love.graphics.print("Loading gfx", 0, 0)

        love.graphics.rectangle("fill", 2, 16, 256 * (LoadingInfo.loading_index - 1) / #LoadingInfo.images_to_load, 16)

    elseif State == "game" then

        local vx, vy = body:getLinearVelocity()
        local x, y = body:getPosition()
        PlayerInfo.linear_score = round(vx ^ 2 + vy ^ 2, -4) / 10000

        local heading = 0
        if PlayerInfo.linear_score > 1 then
            heading = math.atan2(y - PlayerInfo.prev_y, x - PlayerInfo.prev_x)
            PlayerInfo.prev_x = x
            PlayerInfo.prev_y = y
        end

        if math.abs(heading) > 0 then
            PlayerInfo.character_rotation = heading
        end

        love.graphics.draw(character, body:getX(), body:getY(), PlayerInfo.character_rotation, 1, 1, character_width / 2, character_height / 2)

        for i = 1, #EntityInfo.coin_bods do 
            if EntityInfo.coin_bods[i] then
                love.graphics.draw(image, EntityInfo.coin_bods[i]:getX(), EntityInfo.coin_bods[i]:getY(), 0, 1, 1, png_width / 2, png_height / 2)
            end
        end

        for i = 1, #EntityInfo.enemies_bods do 
            if EntityInfo.enemies_bods[i] then
                love.graphics.draw(enemy_image, EntityInfo.enemies_bods[i]:getX(), EntityInfo.enemies_bods[i]:getY(), 0, 1, 1, enemy_width / 2, enemy_height / 2)
            end
        end

        local spriteNum = math.floor(animation.currentTime / animation.duration * #animation.quads) + 1
        love.graphics.draw(animation.spriteSheet, animation.quads[spriteNum], 0, 0, 0, 4)

        local statsText = string.format(
            "FPS: %d\nSpeed: %.2f\nHeading: %.2f\nRotation: %.2f",
            love.timer.getFPS(),
            PlayerInfo.linear_score,
            round(heading, 2),
            round(PlayerInfo.character_rotation, 2)
        )

        local numLines = 4 
        local fontHeight = love.graphics.getFont():getHeight() 
        local panelHeight = (numLines * fontHeight) + (StatsDisplay.padding * 2)

        love.graphics.setColor(StatsDisplay.bgColor) 
        love.graphics.rectangle(
            'fill',                      
            StatsDisplay.x,              
            StatsDisplay.y,              
            StatsDisplay.width,          
            panelHeight,                 
            5, 5                         
         )

        love.graphics.setColor(StatsDisplay.textColor) 
        love.graphics.printf(
            statsText,                                  
            StatsDisplay.x + StatsDisplay.padding,      
            StatsDisplay.y + StatsDisplay.padding,      
            StatsDisplay.width - StatsDisplay.padding * 2, 
            'left'                                      
        )

        local scoreText = string.format("Score: %d", PlayerInfo.player_score)
        local scoreTextWidth = love.graphics.getFont():getWidth(scoreText)
        love.graphics.setColor(StatsDisplay.scoreColor)
        love.graphics.print(
             scoreText,
             math.floor((ScreenInfo.screen_width - scoreTextWidth) / 2), 
             StatsDisplay.scoreY                                         
         )

        love.graphics.setColor(1, 1, 1, 1)

    end
end

function love.resize(w, h)
    ScreenInfo.screen_width = w
    ScreenInfo.screen_height = h
    fence_fixture:destroy()
    fence_shape = love.physics.newChainShape(true, -100, -100, ScreenInfo.screen_width, -100, ScreenInfo.screen_width, ScreenInfo.screen_height, -100, ScreenInfo.screen_height)
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
    t = math.max(0, math.min(1, t))
    if t <= 0.5 then
        return lerp(a, b, 2 * t * t)
    else
        t = t - 1
        return lerp(a, b, 1 - 2 * t * t)
    end
end

function createCoins(n)
    for _ = 1, n do
        local _bod = love.physics.newBody(world, math.random(0, ScreenInfo.screen_width), math.random(0, ScreenInfo.screen_height), "dynamic")
        table.insert(EntityInfo.coin_bods, 1, _bod)
        _fixture = love.physics.newFixture(_bod, coin_shape)
        _fixture:setGroupIndex(69)

    end

end

function createEnemies(n)
    for _ = 1, n do
        local _bod = love.physics.newBody(world, math.random(0, ScreenInfo.screen_width), math.random(0, ScreenInfo.screen_height), "dynamic")
        table.insert(EntityInfo.enemies_bods, 1, _bod)
        _fixture = love.physics.newFixture(_bod, enemy_shape)
        _fixture:setGroupIndex(777)

    end

end

function beginContact(fixture_a, fixture_b, contact)
    local body_a = fixture_a:getBody()
    local body_b = fixture_b:getBody()
    if (fixture_a:getGroupIndex() == 69 or fixture_b:getGroupIndex() == 69) then
        local ball_body = nil
        if (body_a == body) then
            ball_body = body_b
        elseif (body_b == body) then
            ball_body = body_a
        end
        if ball_body then
            for i = #EntityInfo.coin_bods, 1, -1 do
                if EntityInfo.coin_bods[i] == ball_body then
                    print("Deleting ball at index", i)
                    EntityInfo.coin_bods[i]:destroy()
                    table.remove(EntityInfo.coin_bods, i)
                    EntityInfo.num_coins = EntityInfo.num_coins - 1
                    PlayerInfo.player_score = PlayerInfo.player_score + 1

                    break
                end
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