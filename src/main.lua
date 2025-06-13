--[[
===============================================================================
DOGE GAME ENGINE - BASE GAME
===============================================================================

This is the core base game engine that provides fundamental systems and 
infrastructure. All gameplay features (enemies, bosses, weapons, maps, etc.) 
have been migrated to the mod system for better organization and extensibility.

MIGRATION STATUS:
✅ MIGRATED TO MOD SYSTEM:
- Map system (map_system mod)
- Enemy behavior (basic_enemies_mod, ai_behaviors_mod)  
- Boss encounters (bear_boss_mod)
- Weapons & combat (weapons_core_mod, projectiles_mod, combat_effects_mod)
- Health & damage (health_damage_mod)
- Blood effects (blood_effects_mod)

✅ MIGRATED TO NEW RENDERER:
- Legacy renderer replaced with rendererPlus
- All drawing operations now go through new render queue system
- Asset management centralized in new renderer

🔧 CORE ENGINE COMPONENTS (SANDBOX):
- Physics world & collision detection system
- Shader management & graphics pipeline
- Camera system & transformations
- Renderer queue & drawing operations
- Console & command systems (command, cmdn)
- Visual effect systems (fire, water, smoke, blur, etc.)
- Menu system & UI framework
- Multiplayer networking & synchronization
- Audio systems & sound management
- Input handling & event distribution
- Hot reload & development tools

SANDBOX PHILOSOPHY:
The engine is an empty sandbox until mods are loaded. Mods provide ONLY:
- Data structures (entity definitions, sprites, sounds)
- Game logic instructions (via API calls)
- Event handlers (collision responses, input reactions)

The engine maintains COMPLETE CONTROL over:
- All rendering operations (no direct love.graphics calls in mods)
- All physics operations (no direct Box2D manipulation in mods)
- All shader operations (mods queue shader requests)
- All networking (mods send data, engine handles transmission)

ARCHITECTURE:
- main.lua: Empty sandbox + core systems authority
- mod_system.lua: Data-driven mod loading & API enforcement
- new_renderer.lua: Centralized rendering with queue processing
- mods/: Pure data & logic providers (no direct engine access)

===============================================================================
--]]

-- Base Game Engine - Core systems only
-- All gameplay features (enemies, bosses, weapons, maps) are now handled by the mod system

-- Base game engine components
menu = require("ui.menu")                      -- Core UI system
mymath = require("lib.math.myMath")           -- Math utilities
effects = require("lib.graphics.effects")     -- Graphics effects
var = require("config.var")                   -- Game configuration
-- player = require("game.player")               -- MIGRATED TO player_core_mod
mydraw = require("lib.graphics.draw")         -- Drawing utilities
shader = require("lib.graphics.shader")       -- Shader system
water = require("systems.water")              -- Water effects
grass = require("systems.grass")              -- Grass system
smoke = require("systems.smoke")              -- Smoke effects
sprite = require('lib.graphics.sprite')       -- Sprite utilities
fire = require("systems.fire")                -- Fire effects
gun = require("game.gun")                     -- Core gun system
camera = require("lib.graphics.camera")       -- Camera system
vec2 = require("lib.math.vec2")              -- Vector math
vec4 = require("lib.math.vec4")              -- Vector math
portal = require("game.portal")               -- Portal system
crt = require("systems.crt")                  -- CRT effects
rendererPlus = require("lib.graphics.new_renderer") -- New renderer system
modSystem = require("engine.mod_system")      -- Mod loading system
snapshot = require("config.snapshot")         -- Game state snapshots
blur = require ("systems.blur")               -- Blur effects
serial = require("lib.utils.serial")          -- Serialization
editor = require("ui.editor")                 -- Level editor
multiplayer = require("network.multiplayer")  -- Multiplayer system
bullet = require("game.bullet")               -- Bullet system
rocket = require("game.rocket")               -- Rocket system
moonshine = require("lib.graphics.moonshine") -- Moonshine effects
light = require("systems.light")              -- Lighting system
blood = require("systems.blood")              -- Blood effects
wind = require("lib.graphics.wind")           -- Wind effects

command = require("ui.command")                 -- Console system
cmdn = require("ui.cmndX")                     -- Enhanced console
-- Hot reloader utilities
local lurker = require("lib.utils.lurker")    -- Hot reload system
json = require("lib.utils.json")               -- JSON utilities

-- Core game variables
world = 0
t = 0  -- Timer for network updates
local fence_body, fence_shape, fence_fixture
local coin_shape, enemy_shape
coin_image, coin_quad, coin_sprite = 0, 0, 0
png_width, png_height, enemy_width, enemy_height = 0, 0, 0, 0

W = love.graphics.getWidth()
H = love.graphics.getHeight()
game_area_x = (W - var.game_width) / 2
game_area_y = var.header_height

-- Physics callbacks (defined early for use in love.load)
function beginContact(fixture_a, fixture_b, contact)
    -- player.collision(fixture_a, fixture_b, contact)  -- MIGRATED TO player_core_mod
    fire.collision(fixture_a, fixture_b, contact)
    
    -- Forward collision to mod system for handling
    modSystem.handleCollision(fixture_a, fixture_b, contact)
end

function endContact(a, b, contact)
end

function preSolve(a, b, contact)
end

function postSolve(a, b, contact, normalimpulse, tangentimpulse)
end


function love.load()
    -- Default Window Settings
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()
    local game_area_x = (W - var.game_width) / 2
    local game_area_y = var.header_height

    -- Initialize new renderer
    rendererPlus.init()
 
    statsFont = love.graphics.newFont("gfx/menu/Px437_IBM_VGA_8x16.ttf", 16)
    gameFont = love.graphics.newFont("gfx/menu/Px437_IBM_VGA_8x16.ttf", 16)

    -- Initialize the menu system
    menu.load(var.ScreenInfo)

    -- Physics setup - core game component
    world = love.physics.newWorld(0, 0)
    world:setCallbacks(beginContact, endContact, preSolve, postSolve)

    -- Game boundary fence - core game component  
    fence_body = love.physics.newBody(world, 0, 0, "static")
    fence_shape = love.physics.newChainShape(true, 200, 50, var.game_width + 200, 50, var.game_width + 200,
        var.game_height + 50, 200,
        var.game_height + 50)
    fence_fixture = love.physics.newFixture(fence_body, fence_shape)

    -- Initialize core systems
    multiplayer.load()
    -- player.load(world)  -- MIGRATED TO player_core_mod
    command.load()
    cmdn.load()

    
    -- Initialize visual effect systems
    fire.load()
    shader.load()
    water.load()
    smoke.load()
    portal.load()
    crt.load()
    blur.load()
    blood.load()

    -- Initialize mod system with engine components
    local engine_systems = {
        renderer = rendererPlus,
        physics = world,
        multiplayer = multiplayer
    }
    modSystem.init(engine_systems)
    
    -- Load core system mods first
    modSystem.loadMod("player_core_mod")      -- Core player system (MIGRATED)
    modSystem.loadMod("map_system")
    
    -- Load combat mods
    modSystem.loadMod("weapons_core_mod")
    modSystem.loadMod("projectiles_mod")
    modSystem.loadMod("combat_effects_mod")
    
    -- Load enemy and boss mods
    modSystem.loadMod("health_damage_mod")
    modSystem.loadMod("damage_indicators_mod")
    modSystem.loadMod("blood_effects_mod")
    modSystem.loadMod("ai_behaviors_mod")
    modSystem.loadMod("basic_enemies_mod")
    modSystem.loadMod("bear_boss_mod")
end



function love.draw()
    if var.State == "menu" then
        menu.draw()
        return
    end

    if var.graphics_high then
        shader.prepass()
    end
    
    love.graphics.push() -- Apply camera transforms
    camera.apply()

    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.setColor(1, 1, 1, 1)

    -- Clear render queues for new frame
    rendererPlus.clearQueue()
    
    -- Update core systems
    blood.populate()
    
    -- Update and render mod system
    modSystem.update(love.timer.getDelta())
    
    -- Render everything with new renderer
    rendererPlus.render(love.timer.getDelta())
    
    -- Draw mod system UI elements on top
    modSystem.draw()

    love.graphics.pop() -- Return to base world space

    -- Apply post-processing effects
    if var.graphics_high then
        shader.pass()
        smoke.pass()
        water.pass()
        crtShader.endCapture()
        blur.pass()
    end

    -- Draw UI elements last
    mydraw.mydraw()
    command.draw()
    cmdn.draw()
end

local t = 0
function love.update(dt)
    if var.State == "menu" then
        menu.update(dt)
        if not var.multiplayer then 
            return 
        end
    elseif var.State == "running" then
        var.State = "game"
    end
    
    -- Update physics world
    world:update(dt)
    
    -- Update multiplayer if enabled
    if var.multiplayer then
        mp:update()
        multiplayer.sendMovementMessage()
    end
    
    -- Update core systems
    -- player.update(dt)  -- MIGRATED TO player_core_mod
    -- Get player data from mod system for camera
    local player_data = modSystem.getPlayerData()
    if player_data then
        camera.update(dt, player_data)
    end
    water.update(dt)
    smoke.update(dt)
    fire.update(dt)
    grass.public.update(dt)
    portal.update(dt)
    blur.update(dt)
    command.update(dt)
    cmdn.update(dt)
    blood.update(dt)
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
            love.event.push("quit", "restart")
        elseif nextStateAction == "exit" then
            love.event.quit()
        end
        return
    end

    if command.mousepressed(x, y, button) then
        return
    end
    
    -- Forward mouse input to mod system
    modSystem.mousepressed(x, y, button)
    
    local center_x = love.graphics.getWidth() / 2
    local center_y = love.graphics.getHeight() / 2

    local direction = vec2.new(x - center_x, y - center_y)
    local normalized_direction = vec2.norm(direction)
    
    -- Check if we have fireballs available in the ring
    if fire.getAvailableCount() > 0 then
        local fireball_pos = fire_instances[#fire_instances].pos
        
        table.insert(fire.fireables, { 
            vec2.new(fireball_pos.x, fireball_pos.y), 
            normalized_direction, 
            false 
        })
        
        fire.removeFireball()
    end

    lurker.scan()
end

function love.textinput(text)
    command.textinput(text)
    cmdn.textinput(text)
end

lurker.preswap = function(file)
    love.event.push("quit", "restart")
end

local zoomToggle = false

function love.keypressed(key)
    if key == "z" then
        if not zoomToggle then
            camera.setZoom(2)
        else
            camera.setZoom(1)
        end
        zoomToggle = not zoomToggle
    end

    if key == "escape" then
        var.State = (var.State == "menu") and "running" or "menu" 
        menu.blur = not menu.blur
        blur.blur_enabled = not blur.blur_enabled
    end
    
    -- Forward input to systems
    modSystem.keypressed(key)
    command.keypressed(key)
    cmdn.keypressed(key)
end


function love.mousereleased(x, y, button, istouch, presses)
    modSystem.mousereleased(x, y, button)
    cmdn.mousereleased(x, y, button)
end

function love.mousemoved(x, y, dx, dy, istouch)
    cmdn.mousemoved(x, y, dx, dy)
end

function love.keyreleased(key)
    command.keyreleased(key)
    cmdn.keyreleased(key)
end

function love.wheelmoved(x, y)
    command.wheelmoved(x, y)
    cmdn.wheelmoved(x, y)
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
