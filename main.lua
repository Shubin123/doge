math.randomseed(os.time())

local menu = require("menu")
local mymath = require("mymath")
local effects = require("effects")
-- local mydraw = require("draw")
local var = require("var")
local map = require("map")
local player = require("player")
local mydraw = require("draw")

-- Game variables
local world
local fence_body, fence_shape, fence_fixture
coin_bods = {}
enemies_bods = {}
local coin_shape, enemy_shape
image, enemy_image = 0
png_width, png_height, enemy_width, enemy_height = 0

function love.load()
    love.mouse.setVisible(false)

    -- Window setup
    success = love.window.setMode(var.screen_width, var.screen_height, var.screen_flags)

    -- Load fonts
    statsFont = love.graphics.newFont("gfx/menu/PixelGameFont.ttf", 16)
    gameFont = love.graphics.newFont("gfx/menu/PixelGameFont.ttf", 16)

    -- Initialize the menu
    menu.load(var.ScreenInfo)

    -- Physics setup
    world = love.physics.newWorld(0, 0)
    world:setCallbacks(beginContact, endContact, preSolve, postSolve)

    fence_body = love.physics.newBody(world, 0, 0, "static")

    fence_shape = love.physics.newChainShape(true, 0, 0, var.game_width, 0,
        var.game_width, var.game_height, 0, var.game_height)
    fence_fixture = love.physics.newFixture(fence_body, fence_shape)

    createArches()
    -- if player.body:getX() > 200 or player.body:getX() < 170  or  player.body:getY()  > 190  or player.body:getY()  < 140 then

    -- Load map and player
    map.load()
    player.load(world)

    -- Coins and enemies
    coin_shape = love.physics.newCircleShape(18)
    createCoins(var.num_coins)

    enemy_shape = love.physics.newCircleShape(100)
    createEnemies(var.num_enemies)

    -- Graphics
    image = love.graphics.newImage("gfx/coin.png")
    enemy_image = love.graphics.newImage("gfx/enemy.png")

    png_width, png_height = image:getDimensions()
    enemy_width, enemy_height = enemy_image:getDimensions()

    -- body = love.physics.newBody(world, 0 ,0 ,'dynamic')

    -- animation = newAnimation(love.graphics.newImage("gfx/WarriorSpriteSheet/Warrior_Sheet-Effect.png"), 69, 44, 2, 30)

end

local W = love.graphics.getWidth()
local H = love.graphics.getHeight()
local game_area_x = (W - var.game_width) / 2
local game_area_y = var.header_height

function love.draw()

    mydraw.mydraw()
    -- if player.body:getX() > 200 or player.body:getX() < 170 or player.body:getY() > 180 or player.body:getY() < 100 then
    -- print(player.body:getX(),player.body:getY())
    mydraw.coins()
    if checkBoundsGrid(player.body:getX(), player.body:getY()) then

        player.draw()
        map.map3:draw(100, game_area_y, 1)
    else
        map.map3:draw(100, game_area_y, 1)
        player.draw()

    end

end

function checkBounds(cx1, cy1, cx2, cy2, x, y)
    -- print(cx1,cy1,cx2,cy2,x,y)
    return x < cx1 and x > cx2 and y < cy1 and y > cy2
end

function checkBoundsGrid(x, y)
    if checkBounds(1000, 180, 0, 100, x, y) then
        return true
    end
    if checkBounds(1000, 180 + 130, 0, 100 + 130, x, y) then
        return true
    end

    -- for i=0,8 do
    --     -- local offset_x = 30*i

    -- end
    -- return false
end

function love.update(dt)
    if State == "menu" then
        menu.update(dt)
        -- return
    elseif State == "loading" then
        State = "game"
    end

    world:update(dt)

    -- if State == "game" then
    player.update(dt)
    -- end

    if love.mouse.isDown(1) then
        local x, y = love.mouse.getPosition()
        effects.newHitMarker(x, y)
    end
end

function love.resize(w, h)
    var.screen_width = w
    var.screen_height = h
    var.ScreenInfo.screen_width = w
    var.ScreenInfo.screen_height = h
end

function love.mousepressed(x, y, button, istouch, presses)
    if State == "menu" then
        local nextStateAction = menu.mousepressed(x, y, button, var.ScreenInfo)
        if nextStateAction == "loading" then
            State = "loading"
        elseif nextStateAction == "exit" then
            love.event.quit()
        end
    end
end

function love.keypressed(key, scancode, isrepeat)
    if State == "game" and key == "space" then
        player.body:applyLinearImpulse(0, -1000)
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
    for _ = 1, n do
        local _bod = love.physics.newBody(world, math.random(0, var.game_width), math.random(0, var.game_height),
            "dynamic")
        table.insert(coin_bods, 1, _bod)
        _fixture = love.physics.newFixture(_bod, coin_shape)
        _fixture:setGroupIndex(69)
    end
end

function createEnemies(n)
    for _ = 1, n do
        local _bod = love.physics.newBody(world, math.random(0, var.game_width), math.random(0, var.game_height),
            "dynamic")
        table.insert(enemies_bods, 1, _bod)
        _fixture = love.physics.newFixture(_bod, enemy_shape)
        _fixture:setGroupIndex(777)
    end
end

function createArches()
    for i=0,7 do 

        arch_body = love.physics.newBody(world, 30 + 48*i , 180 - 130, "static")
        arch_shape = love.physics.newRectangleShape(1, 1)
        love.physics.newFixture(arch_body, arch_shape)

        arch_body = love.physics.newBody(world, 30 + 48*i , 180, "static")
        arch_shape = love.physics.newRectangleShape(1, 1)
        love.physics.newFixture(arch_body, arch_shape)

        arch_body = love.physics.newBody(world, 30 + 48*i , 180 + 130, "static")
        arch_shape = love.physics.newRectangleShape(1, 1)
        love.physics.newFixture(arch_body, arch_shape)

        -- arch_body = love.physics.newBody(world, 180 - 50*2 , 180, "static")
        -- arch_shape = love.physics.newRectangleShape(1, 1)
        -- love.physics.newFixture(arch_body, arch_shape)

        -- arch_body = love.physics.newBody(world, 180 - 50 , 180, "static")
        -- arch_shape = love.physics.newRectangleShape(1, 1)
        -- love.physics.newFixture(arch_body, arch_shape)

        -- arch_body = love.physics.newBody(world, 180, 180, "static")
        -- arch_shape = love.physics.newRectangleShape(1, 1)
        -- love.physics.newFixture(arch_body, arch_shape)

       
    end
end

function createAnimation(image, width, height, duration, numFrames)
    local animation = {}
    animation.spriteSheet = image
    animation.quads = {}

    -- Calculate the total possible frames in the sprite sheet
    local totalPossibleFrames = math.floor(image:getWidth() / width) * math.floor(image:getHeight() / height)

    -- If numFrames is not provided, use all possible frames
    local framesToUse = numFrames or totalPossibleFrames

    -- Make sure we don't try to use more frames than are available
    framesToUse = math.min(framesToUse, totalPossibleFrames)

    local frameCount = 0

    for y = 0, image:getHeight() - height, height do
        for x = 0, image:getWidth() - width, width do
            table.insert(animation.quads, love.graphics.newQuad(x, y, width, height, image:getDimensions()))

            frameCount = frameCount + 1
            if frameCount >= framesToUse then
                break -- Stop adding frames once we've reached the desired number
            end
        end

        if frameCount >= framesToUse then
            break -- Also break from the outer loop
        end
    end

    animation.duration = duration or 1
    animation.currentTime = 0

    return animation
end

function beginContact(fixture_a, fixture_b, contact)
    local body_a = fixture_a:getBody()
    local body_b = fixture_b:getBody()
    if fixture_a:getGroupIndex() == 69 or fixture_b:getGroupIndex() == 69 then
        local ball_body
        if body_a == player.body then
            ball_body = body_b
        elseif body_b == player.body then
            ball_body = body_a
        else
            return
        end
        for i = 1, #coin_bods do
            if coin_bods[i] == ball_body then
                print("Deleting ball at index", i)
                coin_bods[i]:destroy()
                table.remove(coin_bods, i)

                var.num_coins = var.num_coins - 1
                var.player_score = var.player_score + 1
                break
            end
        end
    end
end

function endContact(a, b, contact)
end
function preSolve(a, b, contact)
end
function postSolve(a, b, contact, normalimpulse, tangentimpulse)
end
