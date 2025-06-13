

-- math.randomseed(os.time())

menu = require("ui.menu")  -- base game engine component (no ui modding support yet)
mymath = require("lib.math.myMath")
effects = require("lib.graphics.effects")
var = require("config.var")
-- map = require("game.map") -- MIGRATED TO MOD SYSTEM
player = require("game.player") -- base game engine component
mydraw = require("lib.graphics.draw")
shader = require("lib.graphics.shader")
water = require("systems.water")
grass = require("systems.grass")
smoke = require("systems.smoke")
sprite = require('lib.graphics.sprite')
fire = require("systems.fire")
gun = require("game.gun")
camera = require("lib.graphics.camera") -- base game engine component
vec2 = require("lib.math.vec2")
vec4 = require("lib.math.vec4")
player = require("game.player")
-- enemy = require("game.enemy") -- MIGRATED TO MOD SYSTEM
-- boss = require("game.boss")   -- MIGRATED TO MOD SYSTEM  
portal = require("game.portal")
crt = require("systems.crt")
-- renderer = require("lib.graphics.renderer") -- MIGRATED TO NEW RENDERER SYSTEM
rendererPlus = require("lib.graphics.new_renderer")
modSystem = require("engine.mod_system")  -- base game engine component
snapshot = require("config.snapshot")
blur = require ("systems.blur")
serial = require("lib.utils.serial")
editor = require("ui.editor")  -- base game engine component (to be added)
multiplayer = require("network.multiplayer")  -- base game engine component
bullet = require("game.bullet")
rocket = require("game.rocket")
moonshine = require("lib.graphics.moonshine")
light = require("systems.light")  -- base game engine component
blood = require("systems.blood")
wind = require("lib.graphics.wind")

command = require("ui.command")  -- base game engine component
cmdn = require("ui.cmndX")  -- base game engine component
-- hotreloader / helpers
local lurker = require("lib.utils.lurker")  -- base game engine component
json = require("lib.utils.json")  -- base game engine component

-- Game variables
world = 0
t = 0  -- Timer for network updates
local fence_body, fence_shape, fence_fixture
-- coin_bods = {} -- MIGRATE TO MOD SYSTEM
-- enemies_bods = {} -- MIGRATED TO MOD SYSTEM
local coin_shape, enemy_shape
coin_image, coin_quad, coin_sprite = 0, 0, 0
png_width, png_height, enemy_width, enemy_height = 0, 0, 0, 0
-- enemy_image = 0 -- MIGRATED TO MOD SYSTEM

W = love.graphics.getWidth()
H = love.graphics.getHeight()
game_area_x = (W - var.game_width) / 2
game_area_y = var.header_height


function love.load()

    -- * Default Window Settings *
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()
    local game_area_x = (W - var.game_width) / 2
    local game_area_y = var.header_height

    -- Initialize new renderer and mod system
    rendererPlus.init()
    --success = love.window.setMode(var.screen_width, var.screen_height, var.screen_flags) ??? what for

 
    statsFont = love.graphics.newFont("gfx/menu/Px437_IBM_VGA_8x16.ttf", 16)
    gameFont = love.graphics.newFont("gfx/menu/Px437_IBM_VGA_8x16.ttf", 16)

    -- Initialize the menu, the menu is constant accross clients its a base component of the game. Currently it lacks mod support.
    menu.load(var.ScreenInfo)

    -- Physics setup, this is a baked in feature of the game, the physics world is always created regardless of mods or multiplayer state.
    world = love.physics.newWorld(0, 0)
    world:setCallbacks(beginContact, endContact, preSolve, postSolve) -- might need to be changed to use the new physic/game_engine system's callbacks

    -- this is a base component of the game, the fence is always created regardless of mods or multiplayer state. The fence is modifyable only by the server host or in singleplayer.
    -- need some changes to the fence system to allow for modding and multiplayer support, but for now it is a static fence.
    fence_body = love.physics.newBody(world, 0, 0, "static")
    fence_shape = love.physics.newChainShape(true, 200, 50, var.game_width + 200, 50, var.game_width + 200,
        var.game_height + 50, 200,
        var.game_height + 50)
    fence_fixture = love.physics.newFixture(fence_body, fence_shape)

    multiplayer.load() -- needs refactoring/revisition after new game engine system overhaul, specifically in handling syncing and updates - we want to ensure that the improved mutliplayer accounts for optimiziations done by the rendering and phsyics engine.
    player.load(world) -- Baked in feature, the player is always spawned regardless of mods or multiplayer state.
    -- enemy.load() -- MIGRATED TO MOD SYSTEM: basic_enemies_mod
    -- boss.load()  -- MIGRATED TO MOD SYSTEM: bear_boss_mod

    -- Do not touch these, baked feature to allow console access for a number of features, including debugging, modding, and multiplayer commands.
    command.load()
    cmdn.load()
    -- do not touch cmnd and command load() calls.



    -- Coins and enemies 
    -- physics

    -- print(shape_sizes)
    -- need migrate to new rendering and mod system, furthermore this multiplayer functionality might be legacy and no longer supported.
    -- if not var.multiplayer or var.multiplayer == 1 then
    -- coin_shape = love.physics.newCircleShape(5)
    -- -- createCoins(var.num_coins) -- migrate this logic to the new "pickups" mod

    -- enemy_shape = love.physics.newCircleShape(10)
    -- --createEnemies(var.num_enemies)
    -- end

    -- Graphics that need to be migrated to the pickups and integrated with the mod system for collisions and score and fireball circling mod!!!
    -- if var.num_coins > 0 then
    -- coin_image = love.graphics.newImage("gfx/coin.png")
    -- coin_x, coin_y = coin_image:getDimensions()
    -- coin_quad = love.graphics.newQuad(0, 0, 36, 36, coin_x, coin_y)
    -- coin_sprite = love.graphics.newSpriteBatch(coin_image, var.num_coins, "stream")
    -- end

    -- enemy_image = love.graphics.newImage("gfx/enemy.png") -- MIGRATED TO MOD SYSTEM
    -- enemy_width, enemy_height = enemy_image:getDimensions()


    -- editor needs complete reimplementation and design overhaul due to migration and new renderer system, consider this feature deprecated for now.
    -- local mapCompat = {
    --     archInstances = {},
    --     treeInstances = {},
    --     createArches = function(x, y)
    --         local mapMod = modSystem.loaded_mods and modSystem.loaded_mods["map_system"]
    --         if mapMod and mapMod.instance and mapMod.instance.createArches then
    --             return mapMod.instance.createArches(x, y)
    --         end
    --     end,
    --     createTree = function(x, y)
    --         local mapMod = modSystem.loaded_mods and modSystem.loaded_mods["map_system"]
    --         if mapMod and mapMod.instance and mapMod.instance.createTree then
    --             return mapMod.instance.createTree(x, y)
    --         end
    --     end,
    --     addMapToDynamicDrawList = function(...)
    --         local mapMod = modSystem.loaded_mods and modSystem.loaded_mods["map_system"]
    --         if mapMod and mapMod.instance and mapMod.instance.addMapToDynamicDrawList then
    --             return mapMod.instance.addMapToDynamicDrawList(...)
    --         end
    --         return {}
    --     end
    -- }
    
    -- -- Populate compatibility arrays with mod data
    -- function updateMapCompat()
    --     local mapMod = modSystem.loaded_mods and modSystem.loaded_mods["map_system"]
    --     if mapMod and mapMod.instance and mapMod.instance.map then
    --         mapCompat.archInstances = mapMod.instance.map.archInstances or {}
    --         mapCompat.treeInstances = mapMod.instance.map.treeInstances or {}
    --         mapCompat.arches = mapMod.instance.map.arches
    --         mapCompat.tree = mapMod.instance.map.tree
    --     end
    -- end
    -- updateMapCompat()
    
    -- Make the compatibility wrapper available globally for editor
    -- _G.map = mapCompat
    
    -- editor.load(world, mapCompat)


    -- Shaders to be migrated to the new renderer system
    -- grass.public.load()
    -- wind.load()

    --  grass:setGrassArea(320, 398, 165, 37, 2000)
    fire.load()

    shader.load()
    water.load()
    smoke.load()
    portal.load()
    crt.load()
    blur.load()
    --light.load()
    blood.load()

    
    -- Initialize mod system with engine components
    local engine_systems = {
        renderer = rendererPlus,
        physics = world,
        multiplayer = multiplayer
    }
    modSystem.init(engine_systems)
    
    -- Load core system mods first
    modSystem.loadMod("map_system")
    --modSystem.loadMod("glowing_tree_mod")
    
    -- Load combat mods
    modSystem.loadMod("weapons_core_mod")
    modSystem.loadMod("projectiles_mod")
    modSystem.loadMod("combat_effects_mod")
    
    -- Load enemy and boss mods
    modSystem.loadMod("health_damage_mod")
    modSystem.loadMod("blood_effects_mod")
    modSystem.loadMod("ai_behaviors_mod")
    modSystem.loadMod("basic_enemies_mod")
    modSystem.loadMod("bear_boss_mod")

    -- TO BE MIGRATED TO MOD SYSTEM
    -- water.setWaterArea(320, 238, 165, 67)
    -- smoke.setsmokeArea(320, 138, 165, 67)

end



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
         
    --   blueNeon(function()
    -- love.graphics.setColor(0.17, 0.46, 1)
    --     -- print( -camera.pos.x)
    --     -- print( -player.body:getX())
    --     -- neon light bar right next to player with all transforms applied correctly, such that after the pop it still works.
    -- --   love.graphics.rectangle("fill",(camera.pos.x + player.body:getX()*camera.zoom), (camera.pos.y + player.body:getY()*camera.zoom), 100*camera.zoom, 3*camera.zoom, 5, 5, 20)
    --   love.graphics.circle("fill",(camera.pos.x + player.body:getX()*camera.zoom - 2), (camera.pos.y + player.body:getY()*camera.zoom  + 6), 20*camera.zoom)
        
    -- love.graphics.setColor(1,1,1,1)
    -- end)

    -- yellowNeon(function()
    -- love.graphics.setColor(1, 0.46, 0.3)
    -- local mx = player.body:getX() + 20*math.sin(fire.t)
    -- local my = player.body:getY() + 20*math.cos(fire.t)
    

    --   love.graphics.circle("fill",(camera.pos.x + (mx)*camera.zoom), (camera.pos.y +  (my)*camera.zoom)  , 10*camera.zoom)
        
    -- love.graphics.setColor(1,1,1,1)
    -- end)
    -- end 
    
   
    love.graphics.push() --push all camera transforms (move everything when player moves)
   

    camera.apply()

    love.graphics.setColor(1, 1, 1, 0.35)
    -- Legacy map drawing removed - now handled by map_system mod
    -- if blood and blood.drawBackground then
    --     blood.drawBackground(map.map, game_area_x, game_area_y)
    -- else
    --     map.map:draw(game_area_x, game_area_y, 1)
    -- end
    love.graphics.setColor(1, 1, 1, 1)


    

    -- Clear render queues for new frame
    rendererPlus.clearQueue()
    
    -- Legacy renderer disabled - using new renderer system
    -- grass.public.draw()
    -- if var.multiplayer then
    --     renderer.populateDynamicDrawListNetworked()

    --     if var.multiplayer == 1 then
    --         renderer.populateDynamicDrawListNETHOST()
    --     end
    -- else
    --     renderer.populateDynamicDrawList()
    -- end
    
    -- Legacy systems disabled - now handled by mods
    -- bullet.populate()
    -- rocket.populate()  
    -- Legacy systems completely removed - all rendering now handled by new renderer and mods
    blood.populate()
    
    -- Update and render mod system
    modSystem.update(love.timer.getDelta())
    
    -- Update map compatibility wrapper with current mod data
    if updateMapCompat then
        updateMapCompat()
    end
    
    -- Render everything with new renderer
    rendererPlus.render(love.timer.getDelta())
    
    -- Draw mod system UI elements on top
    modSystem.draw()

    


    love.graphics.pop() -- pop back into base world space
    -- order is IMPORTANT HERE shader-> smoke -> water

    
    
  

    if var.graphics_high then
    shader.pass()
    smoke.pass()
    water.pass()
    crtShader.endCapture()
    blur.pass()
    end

    mydraw.mydraw() -- ui last
    command.draw() -- Draw console on top
    cmdn.draw() -- Draw improved console on top
    -- editor.debugDraw()
end

local t = 0
function love.update(dt) --assume online cannot pause right now. debugger still works
    -- migrated, left here to assist with migration fixing, this is how the old update loop worked, furthermore the editor must be redone and handled with a mod.
    -- editor.update(dt)

    if var.State == "menu" then
        menu.update(dt)
        if not var.multiplayer then return end -- cannot pause the game in multiplayer.lua:92 Error during service. otherwise game physics pauses nicely

        -- return
    elseif State == "running" then
        var.State = "game"
    end
    world:update(dt)
    -- t = t + dt
    -- if t > 0.05 then  -- 20 updates per second for smoother multiplayer
        if var.multiplayer then
            mp:update()
            multiplayer.sendMovementMessage()
        end
        -- t = 0
    -- end
    
    player.update(dt)
    
    -- Legacy renderer interpolation removed - handled by new renderer
    
    camera.update(dt, player)
    water.update(dt)
    smoke.update(dt)
    fire.update(dt)
    grass.public.update(dt)
    portal.update(dt)
    blur.update(dt)
    command.update(dt)
    cmdn.update(dt)
    blood.update(dt)

    
    if var.multiplayer == 1 or not var.multiplayer  then
        -- enemy.update(dt) -- MIGRATED TO MOD SYSTEM: basic_enemies_mod
        -- boss.update(dt)  -- MIGRATED TO MOD SYSTEM: bear_boss_mod
    end
    
    -- Legacy combat systems disabled - now handled by mods
    -- gun.update(dt)
    -- bullet.update(dt)
    -- rocket.update(dt)

    wind.update(dt)



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
    
    -- Forward mouse input to mod system
    modSystem.mousepressed(x, y, button)
    
    -- Legacy gun input disabled - now handled by weapons_core_mod
    -- gun.mousepressed(x, y, button)
    
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

    -- deprecated handling of editor.
--    editor.mousepressed(x, y, button)

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
    
    -- Forward input to mod system
    modSystem.keypressed(key)

    -- Legacy editor input disabled - now handled by mods
    -- editor.keypressed(key)
    command.keypressed(key)
    cmdn.keypressed(key)
    -- Legacy gun input disabled - now handled by weapons_core_mod
    -- gun.keypressed(key)
end

function love.mousereleased(x, y, button, istouch, presses)
    -- Handle console mouse events first
    cmdn.mousereleased(x, y, button)
    
    if var.State ~= "menu" then
        -- Legacy gun input disabled - now handled by weapons_core_mod
        -- gun.mousereleased(x, y, button)
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

-- Legacy coin creation function - TO BE MIGRATED TO a new "pickups" mod
-- function createCoins(n)
--     for _ = 1, n do
--         local _bod = love.physics.newBody(world, math.random(200, var.game_width + 200),
--             math.random(50, var.game_height + 50),
--             "dynamic")
--         table.insert(coin_bods, 1, _bod)
--         _fixture = love.physics.newFixture(_bod, coin_shape)
--         _fixture:setGroupIndex(69)
--     end
-- end

-- Legacy enemy creation function - migrated to basic_enemies_mod
--[[
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
--]]


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
    -- enemy.collision(fixture_a, fixture_b, contact) -- MIGRATED TO MOD SYSTEM: basic_enemies_mod
    -- boss.collision(fixture_a, fixture_b, contact)  -- MIGRATED TO MOD SYSTEM: bear_boss_mod
    -- Legacy gun collision disabled - now handled by projectiles_mod
    -- gun.collision(fixture_a, fixture_b, contact)
    
    -- editor.collision(fixture_a, fixture_b, contact)


end

-- function checkDestroy(t, v)
--     for i = 1, #t do
--         if t[i] == v then
--             v:destroy()
--             table.remove(t, i)
--             return i
--         end
--     end
--     return false -- should never reach
-- end

function endContact(a, b, contact)
end

function preSolve(a, b, contact)
end

function postSolve(a, b, contact, normalimpulse, tangentimpulse)
end
