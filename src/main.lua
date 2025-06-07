

-- math.randomseed(os.time())

menu = require("menu")
mymath = require("myMath")
effects = require("effects")
var = require("var")
map = require("map")
player = require("player")
mydraw = require("draw")
shader = require("shader")
water = require("water")
grass = require("grass")
smoke = require("smoke")
sprite = require('sprite')
fire = require("fire")
camera = require("camera")
vec2 = require("vec2")
vec4 = require("vec4")
player = require("player")
enemy = require("enemy")
portal = require("portal")
crt = require("crt")
renderer = require("renderer")
snapshot = require("snapshot")
blur = require ("blur")
serial = require("serial")

multiplayer = require("multiplayer")

-- hotreloader / helpers
local lurker = require("lurker")
json = require("json")

-- Game variables
world = 0
local fence_body, fence_shape, fence_fixture
coin_bods = {}
enemies_bods = {}
local coin_shape, enemy_shape
coin_image, coin_quad, coin_sprite = 0, 0, 0
png_width, png_height, enemy_width, enemy_height = 0, 0, 0, 0
enemy_image = 0

W = love.graphics.getWidth()
H = love.graphics.getHeight()
game_area_x = (W - var.game_width) / 2
game_area_y = var.header_height


-- lighting variables
-- local ldist = 30 -- 5-80
-- local lsample = 40 -- 10-64

function love.load()
    -- love.mouse.setVisible(false)

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
    fence_shape = love.physics.newChainShape(true, 200, 50, var.game_width + 200, 50, var.game_width + 200,
        var.game_height + 50, 200,
        var.game_height + 50)
    fence_fixture = love.physics.newFixture(fence_body, fence_shape)

    createArches()
    -- if player.body:getX() > 200 or player.body:getX() < 170  or  player.body:getY()  > 190  or player.body:getY()  < 140 then

    -- Load map and player
    map.load()
    map_a = addMapToDynamicDrawList(map.map3, 100, game_area_y, 1, 200) -- base_sort_y of 200 for arches
    map_b = addMapToDynamicDrawList(map.map4, 100, game_area_y, 0.8, 240)

    multiplayer.load()
    player.load(world)
    enemy.load()


    -- Coins and enemies
    
    
    



    -- print(shape_sizes)
    coin_shape = love.physics.newCircleShape(5)
    createCoins(var.num_coins)

    enemy_shape = love.physics.newCircleShape(10)
    createEnemies(var.num_enemies)

    

    -- Graphics
    
    if var.num_coins > 0 then
    coin_image = love.graphics.newImage("gfx/coin.png")
    coin_x, coin_y = coin_image:getDimensions()
    coin_quad = love.graphics.newQuad(0, 0, 36, 36, coin_x, coin_y)
    coin_sprite = love.graphics.newSpriteBatch(coin_image, var.num_coins, "stream")
    end

    enemy_image = love.graphics.newImage("gfx/enemy.png")
    enemy_width, enemy_height = enemy_image:getDimensions()



    -- Shaders
    grass.public.load()

    --  grass:setGrassArea(320, 398, 165, 37, 2000)
    fire.load()

    shader.load()
    water.load()
    smoke.load()
    portal.load()
    crt.load()
    blur.load()

    water.setWaterArea(320, 238, 165, 67)
    smoke.setsmokeArea(320, 138, 165, 67)


    
end

local W = love.graphics.getWidth()
local H = love.graphics.getHeight()
local game_area_x = (W - var.game_width) / 2
local game_area_y = var.header_height



function love.draw()
    if var.State == "menu" then
        menu.draw()
        -- blur.enable()
    --     return
    end
    
    if var.graphics_high then
    shader.prepass()
    end
    love.graphics.push()
    
    

    camera.apply()

    love.graphics.setColor(1, 1, 1, 0.35)
    map.map:draw(game_area_x, game_area_y, 1)
    love.graphics.setColor(1, 1, 1, 1)


    -- Populate and sort dynamic draw list if neccessary    
    grass.public.draw()
    if var.multiplayer then
        renderer.populateDynamicDrawListNetworked()

        if var.multiplayer == 1 then
            renderer.populateDynamicDrawListNETHOST()
        end
    else
        renderer.populateDynamicDrawList()
    end
    
    



    table.sort(dynamic_draw_list, renderer.sortByRenderY)
    -- Render sorted entities
    renderer.renderSortedDrawList()



    

    love.graphics.pop()
    -- order is IMPORTANT HERE shader-> smoke -> water
    if var.graphics_high then
    shader.pass()
    smoke.pass()
    water.pass()
    crtShader.endCapture()
    blur.pass()
    end


    mydraw.mydraw() -- ui last
end

local t = 0
function love.update(dt) --assume online cannot pause right now. debugger still works
    if var.State == "menu" then
        menu.update(dt)
        if not var.multiplayer then return end -- cannot pause the game in multiplayer.lua:92 Error during service. otherwise game physics pauses nicely

        -- return
    elseif State == "running" then
        var.State = "game"
    end
    world:update(dt)
    -- t  = t + dt
    -- if t > 0.1 then
    if var.multiplayer then
    mp:update()
    multiplayer.sendMovementMessage()
    end
    -- t = 0
    -- end
    player.update(dt)
    camera.update(dt, player)
    water.update(dt)
    smoke.update(dt)
    fire.update(dt)
    grass.public.update(dt)
    portal.update(dt)
    blur.update(dt)
    
    if var.multiplayer == 1 or not var.multiplayer  then
        enemy.update(dt)
    end


end




function love.resize(w, h)
    var.screen_width = w
    var.screen_height = h
    var.ScreenInfo.screen_width = w
    var.ScreenInfo.screen_height = h
end

local restartcount = tonumber(love.restart) or 0

function love.mousepressed(x, y, button, istouch, presses)
    if var.State == "menu" then
        local nextStateAction = menu.mousepressed(x, y, button, var.ScreenInfo)
        if nextStateAction == "running" then
            var.State = "running"
            -- player.health = 100
            --reset game here
            love.event.push("quit", "restart")
        elseif nextStateAction == "exit" then
            love.event.quit()
        end
    end

    local center_x = love.graphics.getWidth() / 2 -- or player's screen position
    local center_y = love.graphics.getHeight() / 2

    local direction = vec2.new(x - center_x, y - center_y)
    local normalized_direction = vec2.norm(direction)
    -- print(fire.count)
    -- if fire.count == 0 then
    if #fire.fireables < fire.count then
        
        table.insert(fire.fireables, { table.remove(fire_instances, #fire_instances), normalized_direction, false }) -- since we pop directly any position of the spin (instances) table can be inserted
        
    end


    lurker.scan()

    -- love.event.restart(restartcount + 1)
end

lurker.preswap = function(file)
    -- var.num_coins=0
    -- love.load()
    love.event.push("quit", "restart")
end

local zoomToggle = false;

function love.keypressed(key)
    if key == "z" then
        if not zoomToggle then
            camera.setZoom(2)
            -- player.body:applyForce(1000,0)
        else
            camera.setZoom(1)
        end

        zoomToggle = not zoomToggle
    end
    if key == "p" then
        -- fire.pierce = not fire.pierce
        -- enemy.addEnemy(var.game_width / 2, var.game_height / 2)
        -- var.num_enemies  = var.num_enemies  + 1

        debug.debug()
    end

    if key == "escape" then
        var.State = (var.State == "menu") and "running" or "menu" 
        
        menu.blur = not menu.blur
        blur.blur_enabled = not blur.blur_enabled
        
        -- blur.set_radius(0.00001)
    end
end

function round(x, n)
    n = 10 ^ (n or 0)
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
        local _bod = love.physics.newBody(world, math.random(200, var.game_width + 200),
            math.random(50, var.game_height + 50),
            "dynamic")
        table.insert(coin_bods, 1, _bod)
        _fixture = love.physics.newFixture(_bod, coin_shape)
        _fixture:setGroupIndex(69)
    end
end

function createEnemies(n)
    for _ = 1, n do
        local _bod = love.physics.newBody(world, math.random(200, var.game_width + 200),
            math.random(50, var.game_height + 50),
            "dynamic")
        table.insert(enemies_bods, 1, _bod)
        _fixture = love.physics.newFixture(_bod, enemy_shape)
        _fixture:setGroupIndex(-777)
    end
end

function createArches()
    arch_shape = love.physics.newRectangleShape(20, 30)
    for x = 0, 7 do
        for y = 0, 2 do
            arch_body = love.physics.newBody(world, 230 + 48 * x, 100 + y * 130, "static")
            love.physics.newFixture(arch_body, arch_shape)
        end
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
    
    -- player.collision(fixture_a,fixture_b,contact)
    fire.collision(fixture_a, fixture_b, contact)
    enemy.collision(fixture_a, fixture_b, contact)

end

function checkDestroy(t, v)
    for i = 1, #t do
        if t[i] == v then
            v:destroy()
            table.remove(t, i)
            return i
        end
    end
    return false -- should never reach
end

function endContact(a, b, contact)
end

function preSolve(a, b, contact)
end

function postSolve(a, b, contact, normalimpulse, tangentimpulse)
end
