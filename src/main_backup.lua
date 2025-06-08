package.path = package.path .. ";./?.lua"
math.randomseed(os.time())

main_menu = require("main_menu")
loading_screen = require("loading_screen")
game_state = require("game_state")
character_manager = require("character_manager")
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
enemy_demo = require("enemy_demo")
particle_system = require("particle_system")
portal = require("portal")
crt = require("crt")
renderer = require("renderer")
map_editor = require("map_editor")
map_hotreloader = require("map_hotreloader")

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

    -- Initialize game systems
    game_state.initialize()
    character_manager.initialize()
    main_menu.initialize()
    loading_screen.initialize()
    
    -- Set initial game state
    game_state.showMainMenu()

    -- Physics setup
    world = love.physics.newWorld(0, 0)
    world:setCallbacks(beginContact, endContact, preSolve, postSolve)

    -- Initialize map manager with physics world
    local map_manager = require("map_manager")
    map_manager.initialize(world)

    -- Create world boundaries using default coordinates (will be updated after map loads)
    fence_body = love.physics.newBody(world, 0, 0, "static")
    
    -- Use default boundaries initially
    local world_left = 0
    local world_top = 0
    local world_right = 1120  -- Default size
    local world_bottom = 800  -- Default size
    
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
    
    -- Set up camera map boundaries using world coordinates (after map is loaded)
    local currentMap = map.getCurrentMap()
    if currentMap and currentMap.definition then
        local mapDef = currentMap.definition
        if mapDef.mapWidth and mapDef.tileWidth and mapDef.mapHeight and mapDef.tileHeight then
            local mapWorldWidth = mapDef.mapWidth * mapDef.tileWidth
            local mapWorldHeight = mapDef.mapHeight * mapDef.tileHeight
            camera.setMapBounds(mapDef.worldX or 0, mapDef.worldY or 0, mapWorldWidth, mapWorldHeight)
            camera.map_bounds.enabled = true
        end
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
    particle_system.load()
    water.load()
    smoke.load()
    portal.load()
    crt.load()

    water.setWaterArea(320, 238, 165, 67)
    smoke.setsmokeArea(320, 138, 165, 67)
    
    -- Initialize map editor and hot-reloader
    map_editor.initialize()
    map_hotreloader.initialize()
end

local W = love.graphics.getWidth()
local H = love.graphics.getHeight()
-- Remove screen-based coordinate calculations
-- All positioning now handled in world coordinates via camera



function love.draw()
    local current_state = game_state.getCurrentState()
    local states = game_state.getStates()
    
    if current_state == states.MAIN_MENU then
        main_menu.draw()
        return
    elseif current_state == states.CHARACTER_SELECT then
        main_menu.draw()
        return
    elseif current_state == states.MAP_SELECT then
        main_menu.draw()
        return
    elseif current_state == states.SETTINGS then
        main_menu.draw()
        return
    elseif current_state == states.CREDITS then
        main_menu.draw()
        return
    elseif current_state == states.LOADING then
        loading_screen.draw()
        return
    elseif current_state == states.SPLASH then
        -- Draw splash screen (could be added later)
        love.graphics.clear(0.1, 0.1, 0.1, 1)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("DOGE ADVENTURES", 0, love.graphics.getHeight()/2 - 50, love.graphics.getWidth(), "center")
        return
    end
    
    
    -- Draw game world for playing states
    if current_state == states.PLAYING or current_state == states.PAUSED or current_state == states.GAME_OVER then
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

        love.graphics.pop()
        -- order is IMPORTANT HERE shader-> smoke -> water
        shader.pass()
        
        mydraw.mydraw() -- ui last
        
        -- Draw map editor overlay
        map_editor.draw()
        
        -- Draw pause overlay
        if current_state == states.PAUSED then
            love.graphics.setColor(0, 0, 0, 0.7)
            love.graphics.rectangle("fill", 0, 0, W, H)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.printf("PAUSED", 0, H/2 - 50, W, "center", 0, 2, 2)
            love.graphics.printf("Press ESC to resume", 0, H/2 + 20, W, "center")
        end
        
        -- Draw game over overlay
        if current_state == states.GAME_OVER then
            love.graphics.setColor(0.8, 0.1, 0.1, 0.6)
            love.graphics.rectangle("fill", 0, 0, W, H)
            
            love.graphics.setColor(1, 1, 1, 1)
            local font = love.graphics.getFont()
            love.graphics.printf("YOU DIED", 0, H/2 - 50, W, "center", 0, 2, 2)
            love.graphics.printf("Press R to restart or ESC for menu", 0, H/2 + 20, W, "center")
        end
    end

end

function love.update(dt)
    -- Always update game state system
    game_state.update(dt)
    
    local current_state = game_state.getCurrentState()
    local states = game_state.getStates()
    
    -- Handle state-specific updates
    if current_state == states.MAIN_MENU or 
       current_state == states.CHARACTER_SELECT or 
       current_state == states.MAP_SELECT or 
       current_state == states.SETTINGS or 
       current_state == states.CREDITS then
        main_menu.update(dt)
        return
    elseif current_state == states.LOADING then
        loading_screen.update(dt)
        return
    elseif current_state == states.SPLASH then
        -- Handle splash screen timer
        local splash_timer = game_state.getStateData("splash_timer")
        if splash_timer then
            splash_timer = splash_timer - dt
            game_state.setStateData("splash_timer", splash_timer)
            if splash_timer <= 0 then
                game_state.showMainMenu()
            end
        end
        return
    end
    

    -- Game world updates (playing, paused, game_over states)
    if current_state == states.PLAYING or current_state == states.GAME_OVER then
        world:update(dt)

        if current_state == states.PLAYING then
            player.update(dt)
            camera.update(dt, player)
        end
        
        -- Update the new map system
        map.update(dt)
        
        -- Update map editor and hot-reloader
        map_editor.update(dt)
        map_hotreloader.update(dt)

        water.update(dt)
        smoke.update(dt)
        fire.update(dt)
        particle_system.update(dt)

        grass.demo.update(dt)
        enemy.update(dt)
        portal.update(dt)
        
        -- Check for game over condition
        if player.health <= 0 and current_state == states.PLAYING then
            game_state.gameOver("Player defeated")
        end
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
    player.death_timer = nil  -- Clear death timer
    if player.body and not player.body:isDestroyed() then
        player.body:setLinearVelocity(0, 0)
    end
    
    -- Reset game variables
    var.player_score = 0
    
    -- Reset fire system
    fire.fireables = {}
    
    -- Reset enemy system
    enemy.reset()
    
    print("Game reset completed")
end

function love.mousepressed(x, y, button, istouch, presses)
    local current_state = game_state.getCurrentState()
    local states = game_state.getStates()
    
    -- Handle menu states
    if current_state == states.MAIN_MENU or 
       current_state == states.CHARACTER_SELECT or 
       current_state == states.MAP_SELECT or 
       current_state == states.SETTINGS or 
       current_state == states.CREDITS then
        main_menu.handle_mouse(x, y, button, "press")
        return
    end
    
    
    -- Handle gameplay input
    if current_state == states.PLAYING then
        -- Check if map editor should handle the input first
        if map_editor.is_enabled() then
            local handled = map_editor.handle_mouse(x, y, button, true)
            if handled then return end
        end
        
        -- Only handle gameplay clicks when actually in game
        -- Convert mouse position to world coordinates
        local world_x, world_y = camera.screenToWorld(x, y)
        local player_x, player_y = player.body:getX(), player.body:getY()

        local direction = vec2.new(world_x - player_x, world_y - player_y)
        local normalized_direction = vec2.norm(direction)
        
        if #fire.fireables < fire.count then
            table.insert(fire.fireables, { vec2.new(0, 0), normalized_direction, false })
        end
    end
end

local zoomToggle = false;

function love.keypressed(key)
    local current_state = game_state.getCurrentState()
    local states = game_state.getStates()
    
    -- Handle menu navigation
    if current_state == states.MAIN_MENU or 
       current_state == states.CHARACTER_SELECT or 
       current_state == states.MAP_SELECT or 
       current_state == states.SETTINGS or 
       current_state == states.CREDITS then
        main_menu.handle_input(key, "press")
        return
    end
    
    -- Handle game state controls
    if key == "escape" then
        if current_state == states.PLAYING then
            game_state.pauseGame()
        elseif current_state == states.PAUSED then
            game_state.resumeGame()
        elseif current_state == states.GAME_OVER then
            game_state.returnToMainMenu()
        end
        return
    elseif key == "r" and current_state == states.GAME_OVER then
        -- Restart game
        loading_screen.start_loading(
            character_manager.get_selected_character(),
            game_state.getStateData("selected_map") or "level1",
            function()
                resetGame()
            end
        )
        game_state.showLoading("Restarting...")
        return
    end
    
    -- Handle in-game controls
    if current_state == states.PLAYING then
        -- Check if map editor should handle the key first
        if map_editor.handle_key(key, true) then
            return
        end
        
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
        end
        
        -- Toggle map editor
        if key == "e" then
            map_editor.toggle()
        end
        
        -- Map switching keys for testing
        if key == "1" then
            loading_screen.start_loading(
                character_manager.get_selected_character(),
                "level1"
            )
            game_state.showLoading("Loading Level 1...")
        elseif key == "2" then
            loading_screen.start_loading(
                character_manager.get_selected_character(),
                "level2"
            )
            game_state.showLoading("Loading Level 2...")
        elseif key == "3" then
            loading_screen.start_loading(
                character_manager.get_selected_character(),
                "level3"
            )
            game_state.showLoading("Loading Level 3...")
        end
        
        -- Hot-reloader commands
        if key == "f5" then
            map_hotreloader.reload_all()
        elseif key == "f6" then
            map_hotreloader.auto_save_current_map()
        elseif key == "f7" then
            map_hotreloader.export_for_external_edit("json")
        elseif key == "f8" then
            map_hotreloader.create_dev_template("dev_test", "Development Test Map")
        end
        
        -- Debug info
        if key == "m" then
            local debug_info = map.getDebugInfo()
            print("Map Debug Info:")
            print("  Current map: " .. (debug_info.current_map or "none"))
            print("  Transition state: " .. debug_info.transition_state)
            print("  Cached maps: " .. debug_info.memory_usage.cached_maps)
            print("  Lua memory: " .. string.format("%.2f", debug_info.memory_usage.lua_memory) .. " KB")
            
            local hotreload_info = map_hotreloader.get_debug_info()
            print("Hot-reload Info:")
            print("  Enabled: " .. tostring(hotreload_info.enabled))
            print("  Watched files: " .. hotreload_info.watched_file_count)
            print("  Watch directory: " .. hotreload_info.watch_directory)
            
            local state_info = game_state.getDebugInfo()
            print("Game State Info:")
            print("  Current state: " .. game_state.getStateDisplayName(current_state))
            print("  Memory usage: " .. string.format("%.2f", state_info.memory_usage) .. " KB")
        end
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
