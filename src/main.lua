

-- math.randomseed(os.time())

menu = require("ui.menu")
mymath = require("lib.math.myMath")
effects = require("lib.graphics.effects")
map = require("game.map")
player = require("game.player")
mydraw = require("lib.graphics.draw")
shader = require("lib.graphics.shader")
water = require("systems.water")
grass = require("systems.grass")
smoke = require("systems.smoke")
sprite = require('lib.graphics.sprite')
fire = require("systems.fire")
gun = require("game.gun")
camera = require("lib.graphics.camera")
vec2 = require("lib.math.vec2")
vec4 = require("lib.math.vec4")
enemy = require("game.enemy")
boss = require("game.boss")
portal = require("game.portal")
crt = require("systems.crt")
renderer = require("lib.graphics.renderer")
snapshot = require("network.snapshot")
blur = require ("systems.blur")
serial = require("util.serial")
editor = require("ui.editor")
multiplayer = require("network.multiplayer")
bullet = require("game.bullet")
rocket = require("game.rocket")
moonshine = require("lib.graphics.moonshine")
light = require("systems.light")
blood = require("systems.blood")
wind = require("lib.graphics.wind")
car = require("game.car")


command = require("ui.command") -- no admin seperatation for multiplayer yet! (kinda bad ngl vm escape -> rce -> ooops)
cmdn = require("ui.cmndX") -- improved console - always active
-- hotreloader / helpers
local lurker = require("util.lurker")
json = require("util.json")

-- Game variables
world = 0
t = 0  -- Timer for network updates
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

-- function love.errhand(msg)
--     print("error:" ..msg)
--     print("BEHAVIOUR IS UNDEFINED BEYOND THIS POINT")
-- end


function love.load()
    -- love.mouse.setVisible(false)

    -- Window setup
    success = love.window.setMode(var.screen_width, var.screen_height, var.screen_flags)

    -- Load fonts
    statsFont = love.graphics.newFont("gfx/menu/Px437_IBM_VGA_8x16.ttf", 16)
    gameFont = love.graphics.newFont("gfx/menu/Px437_IBM_VGA_8x16.ttf", 16)

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

    map.createArches(300,200)
    map.createTree(400,100)
    map.createHouse(500,300)
    -- map.createTreeWithWind(500,100)
    -- if player.body:getX() > 200 or player.body:getX() < 170  or  player.body:getY()  > 190  or player.body:nthY()  < 140 then

    -- Load map and player
    map.load()
    map_a = map.addMapToDynamicDrawList(map.arches, 0,0,1, 200) -- since the editor can modify this live this needs to be called again when redrawn at different position
    map_b = map.addMapToDynamicDrawList(map.tree, 0,0, 0.8, 240)
    map.houseInstances[1].color = {1,1,1,0.2}
    -- print(map.houseInstances)
    -- for index, value in pairs(map.houseInstances) do
    --     print(index,value)
    -- end
    map_c = map.addMapToDynamicDrawList(map.house, 0,0, 0.8, 100)
    
                    -- for key, value in pairs(map.house.color) do
                    --     print(key,value)
                    -- end

    multiplayer.load()
    player.load(world)
    enemy.load()
    boss.load()

    gun.load(world)
    bullet.load(world)
    rocket.load(world)

    command.load()
    cmdn.load()
    -- Coins and enemies 
    
    -- physics

    -- print(shape_sizes)
    if not var.multiplayer or var.multiplayer == 1 then
    coin_shape = love.physics.newCircleShape(5)
    createCoins(var.num_coins)

    enemy_shape = love.physics.newCircleShape(10)
    createEnemies(var.num_enemies)
    end

    -- Graphics
    if var.num_coins > 0 then
    coin_image = love.graphics.newImage("gfx/coin.png")
    coin_x, coin_y = coin_image:getDimensions()
    coin_quad = love.graphics.newQuad(0, 0, 36, 36, coin_x, coin_y)
    coin_sprite = love.graphics.newSpriteBatch(coin_image, var.num_coins, "stream")
    end

    enemy_image = love.graphics.newImage("gfx/enemy.png")
    enemy_width, enemy_height = enemy_image:getDimensions()


    editor.load(world,map)


    -- Shaders
    grass.public.load()
    -- wind.load()

    -- grass:setGrassArea(320, 398, 165, 37, 2000)
    fire.load()

    shader.load()
    water.load()
    -- smoke.load()
    portal.load()
    crt.load()
    blur.load()
    light.load()
    blood.load()
    car.load(world)

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

    -- if moonshine then 
        
    --  light.draw()
    -- end 
    

    love.graphics.push() --push all camera transforms (move everything when player moves)


    camera.apply()

    love.graphics.setColor(1, 1, 1, 0.35)
    -- Draw map with blood effects
    if blood and blood.drawBackground then
        blood.drawBackground(map.map, game_area_x, game_area_y)
    else
        map.map:draw(game_area_x, game_area_y, 1)
    end
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
    

    
    bullet.populate()
    rocket.populate()  
    blood.populate()
    car.populate()
    light.populate()
    gun.drawWorld()

    table.sort(dynamic_draw_list, renderer.sortByRenderY)
    -- Render sorted entities
    
    

    renderer.renderSortedDrawList()
    
    
    



    love.graphics.pop() -- pop back into base world space
    -- order is IMPORTANT HERE shader-> smoke -> water
    
    
     light.draw()


    if var.graphics_high then
    shader.pass()
    -- smoke.pass()
    water.pass()
    crtShader.endCapture()
    -- blur.pass()
    end

    mydraw.mydraw() -- ui last
    command.draw() -- Draw console on top
    cmdn.draw() -- Draw improved console on top
    -- editor.debugDraw()
end

local t = 0
function love.update(dt) --assume online cannot pause right now. debugger still works
    map.houseInstances[1].color = {1,1,1,1*math.sin(fire.t)}
    map_c = map.addMapToDynamicDrawList(map.house, 0,0, 0.8, 100)



    if var.multiplayer then
            mp:update()
            multiplayer.sendMovementMessage()
    end
    
    editor.update(dt)

    if var.State == "menu" then
        menu.update(dt)
        -- if not var.multiplayer then
            
            return 
                
            -- end -- 

        -- return
    elseif State == "running" then
        var.State = "game"
    end
    world:update(dt)
    -- t = t + dt
    -- if t > 0.05 then  -- 20 updates per second for smoother multiplayer

        -- t = 0
    -- end

    player.update(dt)

    -- Update player interpolation for smooth multiplayer movement
    if var.multiplayer then
        renderer.updateInterpolation(dt)
    end

    camera.update(dt, player)
    water.update(dt)
    -- smoke.update(dt)
    fire.update(dt)
    grass.public.update(dt)
    portal.update(dt)
    -- blur.update(dt)
    blood.update(dt)
    command.update(dt)
    cmdn.update(dt)
    

    if var.multiplayer == 1 or not var.multiplayer  then
        enemy.update(dt)
        boss.update(dt)
    end

    gun.update(dt)
    bullet.update(dt)
    rocket.update(dt)

    -- wind.update(dt)

end

function love.resize(w, h)
    var.screen_width = w
    var.screen_height = h
    var.ScreenInfo.screen_width = w
    var.ScreenInfo.screen_height = h
end

function love.mousepressed(x, y, button, istouch, presses)
    -- Handle console mouse events first
    cmdn.mousepressed(x, y, button)
    
    if var.State == "menu" then
        local nextStateAction = menu.mousepressed(x, y, button, var.ScreenInfo)
        print(nextStateAction)
        if nextStateAction == "running" then
            var.State = "running"
            -- player.health = 100
            --reset game here
            love.event.push("quit", "restart")
        elseif nextStateAction == "exit" then
            love.event.quit()
        end
        return  -- Don't process game input when in menu
    end

    if command.mousepressed(x, y, button) then
        return -- command block was clicked
    end
    -- Delegate to gun system for shooting (only when not in menu)
    gun.mousepressed(x, y, button)
    
    local center_x = love.graphics.getWidth() / 2 -- or player's screen position
    local center_y = love.graphics.getHeight() / 2

    local direction = vec2.new(x - center_x, y - center_y)
    local normalized_direction = vec2.norm(direction)
    
    -- Check if we have fireballs available in the ring
    if fire.getAvailableCount() > 0 then
        -- Get the position of the last fireball in the ring
        local fireball_pos = fire_instances[#fire_instances].pos
        
        -- Create a projectile fireball
        table.insert(fire.fireables, { 
            vec2.new(fireball_pos.x, fireball_pos.y), 
            normalized_direction, 
            false 
        })
        
        -- Remove the fireball from the ring
        fire.removeFireball()
    end

    editor.mousepressed(x, y, button)
    
    lurker.scan()
end

function love.textinput(text)
    command.textinput(text)
    cmdn.textinput(text)
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
    
    -- if key == "p" then
    --     -- fire.pierce = not fire.pierce
    --     -- enemy.addEnemy(var.game_width / 2, var.game_height / 2)
    --     -- var.num_enemies  = var.num_enemies  + 1
        
    --     debug.debug()
    -- end

    if key == "escape" then
        var.State = (var.State == "menu") and "running" or "menu" 
        -- print(var.State)
        menu.blur = not menu.blur
        blur.blur_enabled = not blur.blur_enabled
        
        -- blur.set_radius(0.00001)
    end

    editor.keypressed(key)
    command.keypressed(key)
    cmdn.keypressed(key)
    gun.keypressed(key)
end

function love.mousereleased(x, y, button, istouch, presses)
    -- Handle console mouse events first
    cmdn.mousereleased(x, y, button)
    
    if var.State ~= "menu" then
        gun.mousereleased(x, y, button)
    end
end

function love.mousemoved(x, y, dx, dy, istouch)
    -- Handle console dragging
    cmdn.mousemoved(x, y, dx, dy)
end

function love.keyreleased(key)
 command.keyreleased(key)
 cmdn.keyreleased(key)
end

function love.wheelmoved(x, y)
    command.wheelmoved(x, y)
    cmdn.wheelmoved(x, y)
    -- your other mouse wheel handling
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
        
        -- Set enemy mass and physics properties for proper knockback
        _fixture:setDensity(2.0)  -- Give enemies substantial mass
        _bod:resetMassData()  -- Apply the density changes
        _bod:setLinearDamping(3.0)  -- Add damping so they don't slide forever
        _bod:setAngularDamping(5.0)  -- Prevent excessive spinning
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
    
    player.collision(fixture_a, fixture_b, contact)
    fire.collision(fixture_a, fixture_b, contact)
    enemy.collision(fixture_a, fixture_b, contact)
    boss.collision(fixture_a, fixture_b, contact)
    gun.collision(fixture_a, fixture_b, contact)
    
    -- editor.collision(fixture_a, fixture_b, contact)


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
