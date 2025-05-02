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
local coin_bods = {}
local enemies_bods = {}
local coin_shape, enemy_shape
local image, enemy_image
local png_width, png_height, enemy_width, enemy_height


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
    world = love.physics.newWorld(0, 1000)
    world:setCallbacks(beginContact, endContact, preSolve, postSolve)
    
    fence_body = love.physics.newBody(world, 0, 0, "static")
    fence_shape = love.physics.newChainShape(true, 0, 0, var.game_width, 0, var.game_width, var.game_height, 0, var.game_height)
    fence_fixture = love.physics.newFixture(fence_body, fence_shape)
    
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

    body = love.physics.newBody(world, 0 ,0 ,'dynamic')
    
    animation = newAnimation(love.graphics.newImage("gfx/WarriorSpriteSheet/Warrior_Sheet-Effect.png"), 69, 44, 1, 30)

end

function love.draw()
    if State == "menu" then
        menu.draw(ScreenInfo)
        love.graphics.draw(cursorImage, love.mouse.getX(), love.mouse.getY(), 0, 0.05, 0.05)
        return
    end
    
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()
    local game_area_x = (W - var.game_width) / 2
    local game_area_y = var.header_height
    
    -- Draw header
    love.graphics.setColor(0.2, 0.2, 0.2)
    love.graphics.rectangle("fill", 0, 0, W, var.header_height)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Health: 100", 10, 10)
    love.graphics.print("Points: " .. var.player_score, W - 100, 10)
    
    -- Draw left panel (inventory)
    local left_panel_width = game_area_x
    if left_panel_width > 0 then
        love.graphics.setColor(0.3, 0.3, 0.3)
        love.graphics.rectangle("fill", 0, var.header_height, left_panel_width, H - var.header_height)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Inventory", 10, var.header_height + 10)
    end
    
    -- Draw right panel (map)
    local right_panel_x = game_area_x + var.game_width
    local right_panel_width = W - right_panel_x
    if right_panel_width > 0 then
        love.graphics.setColor(0.3, 0.3, 0.3)
        love.graphics.rectangle("fill", right_panel_x, var.header_height, right_panel_width, H - var.header_height)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Map", right_panel_x + 10, var.header_height + 10)
    end
    
    -- Draw game area
    love.graphics.setScissor(game_area_x, game_area_y, var.game_width, var.game_height)
    
    -- Draw map (only visible tiles)
    -- map:draw(game_area_x, game_area_y, 1)
    
    -- Draw coins
    for i = 1, var.num_coins do
        local px, py = coin_bods[i]:getX(), coin_bods[i]:getY()
        love.graphics.draw(image, game_area_x + px, game_area_y + py, 0, 1, 1, png_width / 2, png_height / 2)
    end
    
    -- Draw enemies
    for i = 1, var.num_enemies do
        local px, py = enemies_bods[i]:getX(), enemies_bods[i]:getY()
        love.graphics.draw(enemy_image, game_area_x + px, game_area_y + py, 0, 1, 1, enemy_width / 2, enemy_height / 2)
    end
    
    -- Draw character
    local px, py = body:getX(), body:getY()
    local spriteNum = math.floor(animation.currentTime / animation.duration * #animation.quads) + 1
    love.graphics.draw(animation.spriteSheet, animation.quads[spriteNum], game_area_x + px, game_area_y + py, var.character_rotation, 1, 1, var.sprite_width / 2, var.sprite_height / 2)
    
    -- Reset scissor
    love.graphics.setScissor()
    
    -- Draw white borders
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", 0, 0, W, var.header_height)
    if left_panel_width > 0 then
        love.graphics.rectangle("line", 0, var.header_height, left_panel_width, H - var.header_height)
    end
    if right_panel_width > 0 then
        love.graphics.rectangle("line", right_panel_x, var.header_height, right_panel_width, H - var.header_height)
    end
    love.graphics.rectangle("line", game_area_x, game_area_y, var.game_width, var.game_height)
    
    -- Debug info
    love.graphics.print("State: " .. var.State, 10, 70)
    -- mydraw.mydraw()
end

function love.update(dt)
    if State == "menu" then
        menu.update(dt)
        return
    elseif State == "loading" then
        State = "game"
    end
    
    world:update(dt)
    
    if State == "game" then
        player.update(dt)
    end
    
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
    if x >= 0 then x = math.floor(x + 0.5) else x = math.ceil(x - 0.5) end
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
        local _bod = love.physics.newBody(world, math.random(0, var.game_width), math.random(0, var.game_height), "dynamic")
        table.insert(coin_bods, 1, _bod)
        _fixture = love.physics.newFixture(_bod, coin_shape)
        _fixture:setGroupIndex(69)
    end
end

function createEnemies(n)
    for _ = 1, n do
        local _bod = love.physics.newBody(world, math.random(0, var.game_width), math.random(0, var.game_height), "dynamic")
        table.insert(enemies_bods, 1, _bod)
        _fixture = love.physics.newFixture(_bod, enemy_shape)
        _fixture:setGroupIndex(777)
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
        else return
        end
        for i = 1, #coin_bods do
            if coin_bods[i] == ball_body then
                print("Deleting ball at index", i)
                table.remove(coin_bods, i)
                var.num_coins = var.num_coins - 1
                var.player_score = var.player_score + 1
                break
            end
        end
    end
end

function endContact(a, b, contact) end
function preSolve(a, b, contact) end
function postSolve(a, b, contact, normalimpulse, tangentimpulse) end