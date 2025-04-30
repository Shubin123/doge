math.randomseed(os.time())

local MainMenu = require("menu")

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

world = nil
fence_body = nil
fence_shape = nil
fence_fixture = nil
body = nil
shape = nil
fixture = nil
joint = nil
coin_shape = nil
enemy_shape = nil
character = nil
image = nil
enemy_image = nil
animation = nil
character_width = 0
character_height = 0
png_width = 0
png_height = 0
enemy_width = 0
enemy_height = 0

function love.load()
    success = love.window.setMode(ScreenInfo.screen_width, ScreenInfo.screen_height, ScreenInfo.screen_flags)
    State = "menu"
end

function love.update(dt)
    if State == "menu" then
        MainMenu.update(dt)
    elseif State == "loading" then
        if not LoadingInfo.images_to_load then
             LoadingInfo.images_to_load = {"doge.png", "coin.png", "enemy.png", "oldHero.png"}
             LoadingInfo.loading_index = 1
             LoadingInfo.assets = {}
        end
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
            LoadingInfo.images_to_load = nil 
            LoadingInfo.loading_index = nil
        end
    elseif State == "game" then
        if joint then joint:setTarget(love.mouse.getPosition()) end
        if world then world:update(dt) end
        if animation then
            animation.currentTime = animation.currentTime + dt
            if animation.currentTime >= animation.duration then
                animation.currentTime = animation.currentTime - animation.duration
            end
        end
    end
end

function initialize_game()

    world = love.physics.newWorld(0, 0)
    world:setCallbacks(beginContact, endContact, preSolve, postSolve)

    fence_body = love.physics.newBody(world, 0, 0, "static")
    fence_shape = love.physics.newChainShape(true, -100, -100, ScreenInfo.screen_width, -100, ScreenInfo.screen_width, ScreenInfo.screen_height, -100, ScreenInfo.screen_height)
    fence_fixture = love.physics.newFixture(fence_body, fence_shape)
    fence_fixture:setUserData("fence")

    body = love.physics.newBody(world, love.mouse.getX(), love.mouse.getY(), "dynamic")
    shape = love.physics.newRectangleShape(90, 90)
    fixture = love.physics.newFixture(body, shape)
    joint = love.physics.newMouseJoint(body, love.mouse.getPosition())

    coin_shape = love.physics.newCircleShape(18)
    EntityInfo.coin_bods = {} 
    createCoins(EntityInfo.num_coins)

    enemy_shape = love.physics.newCircleShape(100)
    EntityInfo.enemies_bods = {} 
    createEnemies(EntityInfo.num_enemies)

    character = LoadingInfo.assets["doge.png"]
    image = LoadingInfo.assets["coin.png"]
    enemy_image = LoadingInfo.assets["enemy.png"]
    animation = newAnimation(LoadingInfo.assets["oldHero.png"], 16, 18, 1)

    character_width, character_height = character:getDimensions()
    png_width, png_height = image:getDimensions()
    enemy_width, enemy_height = enemy_image:getDimensions()
    
    PlayerInfo.player_score = 0
    PlayerInfo.prev_x = body:getX()
    PlayerInfo.prev_y = body:getY()

end

function love.draw()
    if State == "menu" then
        MainMenu.draw(ScreenInfo)
    elseif State == "loading" then
        love.graphics.print("Loading gfx", 0, 0)
        local loadProgress = 0
        if LoadingInfo.images_to_load and LoadingInfo.loading_index and #LoadingInfo.images_to_load > 0 then
             loadProgress = (LoadingInfo.loading_index - 1) / #LoadingInfo.images_to_load
        end
        love.graphics.rectangle("fill", 2, 16, 256 * loadProgress, 16)

    elseif State == "game" then

        local vx, vy = body:getLinearVelocity()
        local x, y = body:getPosition()
        PlayerInfo.linear_score = round(vx ^ 2 + vy ^ 2, -4) / 10000

        local heading = PlayerInfo.character_rotation 
        if PlayerInfo.linear_score > 1 then
            heading = math.atan2(y - PlayerInfo.prev_y, x - PlayerInfo.prev_x)
            PlayerInfo.prev_x = x
            PlayerInfo.prev_y = y
            PlayerInfo.character_rotation = heading 
        end

        if character then
            love.graphics.draw(character, body:getX(), body:getY(), PlayerInfo.character_rotation, 1, 1, character_width / 2, character_height / 2)
        end

        if image then
            for i = 1, #EntityInfo.coin_bods do 
                if EntityInfo.coin_bods[i] and not EntityInfo.coin_bods[i]:isDestroyed() then
                    love.graphics.draw(image, EntityInfo.coin_bods[i]:getX(), EntityInfo.coin_bods[i]:getY(), 0, 1, 1, png_width / 2, png_height / 2)
                end
            end
        end

        if enemy_image then
            for i = 1, #EntityInfo.enemies_bods do 
                if EntityInfo.enemies_bods[i] and not EntityInfo.enemies_bods[i]:isDestroyed() then
                    love.graphics.draw(enemy_image, EntityInfo.enemies_bods[i]:getX(), EntityInfo.enemies_bods[i]:getY(), 0, 1, 1, enemy_width / 2, enemy_height / 2)
                end
            end
        end

        if animation and animation.quads and #animation.quads > 0 then
             local spriteNum = math.floor(animation.currentTime / animation.duration * #animation.quads) + 1
             love.graphics.draw(animation.spriteSheet, animation.quads[spriteNum], 0, 0, 0, 4)
        end

        local statsText = string.format(
            "FPS: %d\nSpeed: %.2f\nHeading: %.2f\nRotation: %.2f",
            love.timer.getFPS(),
            PlayerInfo.linear_score,
            round(heading, 2),
            round(PlayerInfo.character_rotation, 2)
        )

        local numLines = 4 
        local font = love.graphics.getFont()
        local fontHeight = font:getHeight() 
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
        local scoreTextWidth = font:getWidth(scoreText)
        love.graphics.setColor(StatsDisplay.scoreColor)
        love.graphics.print(
             scoreText,
             math.floor((ScreenInfo.screen_width - scoreTextWidth) / 2), 
             StatsDisplay.scoreY                                         
         )

        love.graphics.setColor(1, 1, 1, 1)

    end
end

function love.mousepressed(x, y, button, istouch, presses)
    if State == "menu" then
        local nextStateAction = MainMenu.mousepressed(x, y, button, ScreenInfo) 
        if nextStateAction == "loading" then
            State = "loading" 
        elseif nextStateAction == "exit" then
            love.event.quit() 
        end
    elseif State == "game" then
        
    end
end

function love.resize(w, h)
    ScreenInfo.screen_width = w
    ScreenInfo.screen_height = h
    if fence_fixture and fence_body then 
        fence_fixture:destroy()
        fence_shape = love.physics.newChainShape(true, -100, -100, ScreenInfo.screen_width, -100, ScreenInfo.screen_width, ScreenInfo.screen_height, -100, ScreenInfo.screen_height)
        fence_fixture = love.physics.newFixture(fence_body, fence_shape)
        fence_fixture:setUserData("fence")
    end
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
    if not world or not coin_shape then return end
    for _ = 1, n do
        local x_pos = math.random(50, ScreenInfo.screen_width - 50)
        local y_pos = math.random(50, ScreenInfo.screen_height - 50)
        local _bod = love.physics.newBody(world, x_pos, y_pos, "dynamic") 
        table.insert(EntityInfo.coin_bods, 1, _bod)
        local _fixture = love.physics.newFixture(_bod, coin_shape)
        _fixture:setGroupIndex(69)
        _fixture:setUserData("coin") 
        _fixture:setSensor(true) 
    end
end

function createEnemies(n)
     if not world or not enemy_shape then return end
    for _ = 1, n do
        local x_pos = math.random(50, ScreenInfo.screen_width - 50)
        local y_pos = math.random(50, ScreenInfo.screen_height - 50)
        local _bod = love.physics.newBody(world, x_pos, y_pos, "dynamic") 
        table.insert(EntityInfo.enemies_bods, 1, _bod)
        local _fixture = love.physics.newFixture(_bod, enemy_shape)
        _fixture:setGroupIndex(777)
        _fixture:setUserData("enemy") 
    end
end

function beginContact(fixture_a, fixture_b, contact)
    local body_a = fixture_a:getBody()
    local body_b = fixture_b:getBody()

    local playerFixture, otherFixture
    if body_a == body then
        playerFixture = fixture_a
        otherFixture = fixture_b
    elseif body_b == body then
        playerFixture = fixture_b
        otherFixture = fixture_a
    else
        return 
    end

    local otherUserData = otherFixture:getUserData()
    local otherBody = otherFixture:getBody()

    if otherUserData == "coin" then
        if otherBody and not otherBody:isDestroyed() then
            print("Contact with coin")
            PlayerInfo.player_score = PlayerInfo.player_score + 1
            for i = #EntityInfo.coin_bods, 1, -1 do
                if EntityInfo.coin_bods[i] == otherBody then
                    table.remove(EntityInfo.coin_bods, i)
                    break
                end
            end
            otherBody:destroy() 
        end
     elseif otherUserData == "enemy" then
        print("Contact with enemy")
     elseif otherUserData == "fence" then
         print("Contact with fence")
    end
end

function endContact(fA, fB, contact) end
function preSolve(fA, fB, contact) end
function postSolve(fA, fB, contact, impulses) end


function newAnimation(image, width, height, duration)
    if not image then return nil end
    local animation = {}
    animation.spriteSheet = image;
    animation.quads = {};
    local imgWidth, imgHeight = image:getDimensions()
    for y = 0, imgHeight - height, height do
        for x = 0, imgWidth - width, width do
            local quadW = math.min(width, imgWidth - x)
            local quadH = math.min(height, imgHeight - y)
             if quadW > 0 and quadH > 0 then
                table.insert(animation.quads, love.graphics.newQuad(x, y, quadW, quadH, imgWidth, imgHeight))
            end
        end
    end
    animation.duration = duration or 1
    animation.currentTime = 0
    if #animation.quads == 0 then
         print("Warning: newAnimation created no quads for image.")
    end
    return animation
end