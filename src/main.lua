math.randomseed(os.time())

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

-- hotreloader
local lurker = require("lurker")

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
-- Remove screen-based offsets in favor of pure world coordinates
-- game_area_x and game_area_y are now handled by camera transform
game_area_x = 0  -- No longer needed with proper world coordinate system
game_area_y = 0  -- No longer needed with proper world coordinate system

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

    -- Create world boundaries using proper world coordinates
    fence_body = love.physics.newBody(world, 0, 0, "static")
    
    -- Get the current map definition to set proper world boundaries
    local currentMap = map.getCurrentMap()
    local world_left = 0
    local world_top = 0
    local world_right = 1120  -- 70 * 16 for level1
    local world_bottom = 800  -- 50 * 16 for level1
    
    if currentMap then
        local mapDef = currentMap.definition
        world_left = mapDef.worldX or 0
        world_top = mapDef.worldY or 0
        world_right = world_left + (mapDef.mapWidth * mapDef.tileWidth)
        world_bottom = world_top + (mapDef.mapHeight * mapDef.tileHeight)
    end
    
    fence_shape = love.physics.newChainShape(true, 
        world_left, world_top, 
        world_right, world_top, 
        world_right, world_bottom, 
        world_left, world_bottom
    )
    fence_fixture = love.physics.newFixture(fence_body, fence_shape)

    createArches()
    -- if player.body:getX() > 200 or player.body:getX() < 170  or  player.body:getY()  > 190  or player.body:getY()  < 140 then

    -- Load map and player
    map.load()
    -- Use world coordinates for legacy maps - these will be generated dynamically in renderer
    -- No need to pre-generate static map lists since we now use dynamic culling
    map_a = {}  -- Will be populated dynamically
    map_b = {}  -- Will be populated dynamically


    player.load(world)
    enemy.load()
    
    -- Set up camera map boundaries using world coordinates
    local currentMap = map.getCurrentMap()
    if currentMap then
        local mapDef = currentMap.definition
        local mapWorldWidth = mapDef.mapWidth * mapDef.tileWidth
        local mapWorldHeight = mapDef.mapHeight * mapDef.tileHeight
        camera.setMapBounds(mapDef.worldX or 0, mapDef.worldY or 0, mapWorldWidth, mapWorldHeight)
        camera.map_bounds.enabled = true
    end


    -- Coins and enemies
    coin_shape = love.physics.newCircleShape(5)
    createCoins(var.num_coins)

    enemy_shape = love.physics.newCircleShape(10)
    createEnemies(var.num_enemies)

    -- Graphics
    coin_image = love.graphics.newImage("gfx/coin.png")
    coin_x, coin_y = coin_image:getDimensions()
    coin_quad = love.graphics.newQuad(0, 0, 36, 36, coin_x, coin_y)
    coin_sprite = love.graphics.newSpriteBatch(coin_image, var.num_coins, "stream")

    enemy_image = love.graphics.newImage("gfx/enemy.png")
    enemy_width, enemy_height = enemy_image:getDimensions()



    -- Shaders
    grass.demo.load()

    fire.load()

    shader.load()
    water.load()
    smoke.load()
    portal.load()
    crt.load()

    water.setWaterArea(320, 238, 165, 67)
    smoke.setsmokeArea(320, 138, 165, 67)
end

local W = love.graphics.getWidth()
local H = love.graphics.getHeight()
-- Remove screen-based coordinate calculations
-- All positioning now handled in world coordinates via camera



function love.draw()
    if var.State == "menu" then
        menu.draw()
        return
    end
    

    love.graphics.push()
    
    shader.prepass()
    camera.apply()
    
    -- Draw neutral background layer for gameplay visibility
    love.graphics.setColor(0.4, 0.4, 0.4, 1.0)
    love.graphics.rectangle("fill", -2000, -2000, 4000, 4000)
    love.graphics.setColor(1, 1, 1, 1)
    
    -- Populate and sort dynamic draw list if neccessary
    renderer.populateDynamicDrawList()
    table.sort(dynamic_draw_list, renderer.sortByRenderY)
    -- Render sorted entities (includes map tiles now)
    renderer.renderSortedDrawList()
    
    grass.demo.draw()

    -- else
    --     map.map3:draw(100, game_area_y, 1)
    --     map.map4:draw(100, game_area_y, 0.8)
    --     player.draw()

    -- end



    love.graphics.pop()
    -- order is IMPORTANT HERE shader-> smoke -> water
    shader.pass()
    
    -- smoke.pass() -- Disabled for seamless shader effects
    
    -- water.pass() -- Disabled for seamless shader effects
    -- crtShader.endCapture() -- Disabled CRT effect for seamless shaders        
    
        

        
    mydraw.mydraw() -- ui last

end

function love.update(dt)
    if var.State == "menu" then
        menu.update(dt)
        return
    end

    world:update(dt)

    -- if State == "game" then
    player.update(dt)
    camera.update(dt, player)
    -- end

    water.update(dt)
    smoke.update(dt)
    fire.update(dt)
    
    -- crtShader:setTime(love.timer.getTime())
    -- crtShader:setMousePos(love.mouse.getX(), love.mouse.getY())

    grass.demo.update(dt)
    enemy.update(dt)
    portal.update(dt)
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
    if checkBounds(1000, 180 - 130, 0, 100 - 130, x, y) then
        return true
    end

    -- for i=0,8 do
    --     -- local offset_x = 30*i
    -- end
    -- return false
end

function love.resize(w, h)
    var.screen_width = w
    var.screen_height = h
    var.ScreenInfo.screen_width = w
    var.ScreenInfo.screen_height = h
end

local restartcount = tonumber(love.restart) or 0

function resetGame()
    -- Reset player
    player.health = 100
    player.body:setLinearVelocity(0, 0)
    
    -- Reset game variables
    var.player_score = 0
    
    -- Reset fire system
    fire.fireables = {}
    
    -- Reset enemy system
    enemy.reset()
    
    -- Use new map system to spawn entities and set player position
    map.spawnMapEntities()
end

function love.mousepressed(x, y, button, istouch, presses)
    if var.State == "menu" then
        local nextStateAction = menu.mousepressed(x, y, button, var.ScreenInfo)
        if nextStateAction == "running" then
            resetGame()
            var.State = "game"

        elseif nextStateAction == "exit" then
            love.event.quit()
        end
    elseif var.State == "game" or var.State == "running" then
        -- Only handle gameplay clicks when actually in game
        -- Convert mouse position to world coordinates
        local world_x, world_y = camera.screenToWorld(x, y)
        local player_x, player_y = player.body:getX(), player.body:getY()

        local direction = vec2.new(world_x - player_x, world_y - player_y)
        local normalized_direction = vec2.norm(direction)
        -- print(fire.count)
        -- if fire.count == 0 then
        if #fire.fireables < fire.count then
            table.insert(fire.fireables, { vec2.new(0, 0), normalized_direction, false })
        end
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
            camera.setZoom(2, player)
        else
            camera.setZoom(1, player)
        end

        zoomToggle = not zoomToggle
    end
    if key == "p" then
        fire.pierce = not fire.pierce
        enemy.addEnemy(var.game_width/2,var.game_height/2)
        -- var.num_enemies  = var.num_enemies  + 1
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
        -- Use proper world coordinates based on current map bounds
        local currentMap = map.getCurrentMap()
        local mapDef = currentMap and currentMap.definition
        local mapWorldX = (mapDef and mapDef.worldX) or 0
        local mapWorldY = (mapDef and mapDef.worldY) or 0
        local mapWorldWidth = (mapDef and mapDef.mapWidth * mapDef.tileWidth) or 800
        local mapWorldHeight = (mapDef and mapDef.mapHeight * mapDef.tileHeight) or 600
        
        local _bod = love.physics.newBody(world, 
            math.random(mapWorldX + 50, mapWorldX + mapWorldWidth - 50),
            math.random(mapWorldY + 50, mapWorldY + mapWorldHeight - 50),
            "dynamic")
        table.insert(coin_bods, 1, _bod)
        _fixture = love.physics.newFixture(_bod, coin_shape)
        _fixture:setGroupIndex(69)
    end
end

function createEnemies(n)
    for _ = 1, n do
        -- Use proper world coordinates based on current map bounds
        local currentMap = map.getCurrentMap()
        local mapDef = currentMap and currentMap.definition
        local mapWorldX = (mapDef and mapDef.worldX) or 0
        local mapWorldY = (mapDef and mapDef.worldY) or 0
        local mapWorldWidth = (mapDef and mapDef.mapWidth * mapDef.tileWidth) or 800
        local mapWorldHeight = (mapDef and mapDef.mapHeight * mapDef.tileHeight) or 600
        
        local _bod = love.physics.newBody(world, 
            math.random(mapWorldX + 50, mapWorldX + mapWorldWidth - 50),
            math.random(mapWorldY + 50, mapWorldY + mapWorldHeight - 50),
            "dynamic")
        table.insert(enemies_bods, 1, _bod)
        _fixture = love.physics.newFixture(_bod, enemy_shape)
        _fixture:setGroupIndex(-777)
    end
end

function createArches()
    arch_shape = love.physics.newRectangleShape(20, 30)
    -- Use world coordinates for arch placement
    local arch_start_x = 230  -- World coordinate
    local arch_start_y = 100  -- World coordinate
    for x = 0, 7 do
        for y = 0, 2 do
            arch_body = love.physics.newBody(world, arch_start_x + 48 * x, arch_start_y + y * 130, "static")
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
