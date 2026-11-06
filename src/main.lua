-- math.randomseed(os.time())

menu = require("ui.menu")
hud = require("ui.hud")
mymath = require("lib.math.myMath")
effects = require("lib.graphics.effects")
map = require("game.map")
audio = require("systems.audio")
player = require("game.player")
mydraw = require("lib.graphics.draw")
shader = require("lib.graphics.shader")
grass = require("systems.grass")
smoke = require("systems.smoke")
sprite = require('lib.graphics.sprite')
fire = require("systems.fire")
gun = require("game.gun")
camera = require("lib.graphics.camera")
vec2 = require("lib.math.vec2")
vec4 = require("lib.math.vec4")
enemy = require("game.enemy")
boss = require("game.boss") -- the bear: the gate's guardian, and the Castle's
robotArm = require("game.robotArm") -- Neon City's boss
bosses = require("game.bosses") -- the gate, the lairs, and how weapons reach bosses
portal = require("game.portal")
regions = require("game.regions")
destruction = require("game.destruction") -- structures shot to pieces and knocked down
crt = require("systems.crt")
puddle = require("systems.puddle")
renderer = require("lib.graphics.renderer")
snapshot = require("network.snapshot")
blur = require("systems.blur")
serial = require("util.serial")
settings = require("util.settings") -- Settings screen choices, in settings.json (never in a save)
editor = require("ui.editor")
multiplayer = require("network.multiplayer")
bullet = require("game.bullet")
rocket = require("game.rocket")
moonshine = require("lib.graphics.moonshine")
light = require("systems.light")
wind = require("lib.graphics.wind")
car = require("game.car")
xp = require("game.xp") -- XP globs (the coin_bods)
blackhole = require("game.blackhole")
daynight = require("systems.daynight")
shop = require("game.shop")
inventory = require("game.inventory") -- the bag, and items lying about
trinkets = require("game.trinkets") -- what you wear, paying for what it does in light
collision = require("util.collision")
explosion = require("systems.explosion")
suckLight = require("systems.suckLight")
characterAnimator = require("game.characterAnimator")
override = require("util.override")
shadow = require("lib.graphics.shadow")
teslaCoil = require("game.teslaCoil") -- gun submodule (load and update within gun.lua)
arrows = require("game.arrows") -- gun submodule (load and update within gun.lua)
blackholeGun = require("game.blackholeGun") -- the black hole gun's shots (load and update within gun.lua)
enemyWeapons = require("game.enemyWeapons") -- enemies' lasers, bolts, rockets and black holes (run by enemy.lua)
BehaviourTree = require("lib.behaviourTrees")
sampleScreen = require("lib.graphics.sampleScreen")
command = require("ui.command") -- the console; no admin seperatation for multiplayer yet! (kinda bad ngl vm escape -> rce -> ooops)
-- hotreloader / helpers
local lurker = require("util.lurker")
-- profiler = require("systems.profiler")
json = require("util.json")
profiler = require("systems.profiler")
benchmark = require("util.benchmark")


-- Game variables
world = 0
t = 0 -- Timer for network updates
local fence_body, fence_shape, fence_fixture
coin_bods = {} -- XP globs (game/xp.lua)
enemies_bods = {}
local coin_shape, enemy_shape
png_width, png_height, enemy_width, enemy_height = 0, 0, 0, 0
enemy_image = 0

-- Game area dimensions, updated on load and resize
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
-- dbg= require('mobdebug')

function love.load()
    preLoadDraw()
    -- The Settings screen's choices, before the window opens and anything
    -- reading them loads
    settings.load()


    -- love.draw = preLoadDraw
    -- love.mouse.setVisible(false)

    -- Window setup
    -- In the browser a resizable SDL window resizes itself to the canvas's CSS
    -- size, which the page derives from the canvas size. At a fractional
    -- devicePixelRatio (e.g. 1.8 from zoom/display scaling) each round trip
    -- rounds down, and the canvas collapses to 1x1: the game runs but shows
    -- nothing.
    if love.system.getOS() == "Web" then
        var.screen_flags.resizable = false
    end
    success = love.window.setMode(var.screen_width, var.screen_height, var.screen_flags)
    -- Dynamically set game area to match screen size initially
    var.game_width = var.screen_width
    var.game_height = var.screen_height - var.header_height
    W = var.screen_width
    H = var.screen_height
    game_area_x = (W - var.game_width) / 2
    game_area_y = var.header_height

    -- Load fonts
    statsFont = love.graphics.newFont("gfx/menu/Px437_IBM_VGA_8x16.ttf", 16)
    gameFont = love.graphics.newFont("gfx/menu/Px437_IBM_VGA_8x16.ttf", 16)

    -- Initialize the menu
    menu.load(var.ScreenInfo)
    hud.load()

    -- Physics setup
    world = love.physics.newWorld(0, 0)
    world:setCallbacks(beginContact, endContact, preSolve, postSolve)
    -- Allow sleeping for distant bodies (huge perf win at 1000+ bodies)
    world:setSleepingAllowed(true)


    -- fence_body = love.physics.newBody(world, 0, 0, "static")
    -- fence_shape = love.physics.newChainShape(true, 200, 50, var.game_width + 200, 50, var.game_width + 200,
    --     var.game_height + 50, 200,
    --     var.game_height + 50)
    -- fence_fixture = love.physics.newFixture(fence_body, fence_shape)
    -- fence_fixture:setGroupIndex(4)

    map.createArches(300, 200)
    map.createTree(400, 100)
    map.createHouse(500, 300)
    -- map.createTreeWithWind(500,100)
    -- if player.body:getX() > 200 or player.body:getX() < 170  or  player.body:getY()  > 190  or player.body:nthY()  < 140 then

    -- Load map and player
    map.load()
    map_a = map.addMapToDynamicDrawList(map.arches, 0, 0, 1, 200) -- since the editor can modify this live this needs to be called again when redrawn at different position
    map_b = map.addMapToDynamicDrawList(map.tree, 0, 0, 0.8, 240)
    map.houseInstances[1].color = { 1, 1, 1, 0.2 }
    -- print(map.houseInstances)
    -- for index, value in pairs(map.houseInstances) do
    --     print(index,value)
    -- end
    map_c = map.addMapToDynamicDrawList(map.house, 0, 0, 0.8, 100)

    -- for key, value in pairs(map.house.color) do
    --     print(key,value)
    -- end
    characterAnimator.load()

    -- The sprite atlas (gfx/atlas/atla.dds.zlib + atlas_metadata3.lua) is no
    -- longer built by hand-editing this file, running the game once, then
    -- separately compiling/running bc-encoder and misc/compress.lua.
    -- It's now one command:
    --
    --   python3 tools/pack_atlas.py --config configs/production_atlas.json \
    --       --gfx-root src --out-atlas src/gfx/atlas/atla.dds.zlib \
    --       --out-metadata src/gfx/atlas/atlas_metadata3.lua
    --
    -- New 3D animations: docs/PIPELINE.md (Blender, tools/render_sprites.py).
    -- See tools/README.md for the config format (sources + characterDefinitions,
    -- both by path — no more hand-kept-in-sync sprite indices) and
    -- tests/ for the pipeline's own test suite. The old
    -- characterAnimator.createAndSaveAtlas(...) escape hatch below still
    -- works for one-off in-editor experiments; it just isn't how the
    -- shipping atlas gets built any more.
    gun_enemies = characterAnimator.loadFromAtlas("gfx/atlas/atla.dds.zlib", "gfx/atlas/atlas_metadata3.lua", true)
    -- the last few are other players' (renderer.updateInterpolation): hidden until someone joins
    for slot = 1, var.max_remote_players do
        gun_enemies[var.num_enemies + 1 + slot].on = false
    end

    -- princess = characterAnimator.init({"gfx/3d/princess/walk copy.png","gfx/3d/princess/run copy.png","gfx/3d/princess/shoot copy.png","gfx/3d/princess/jump copy.png","gfx/3d/princess/roll2.png"},128,128)


    multiplayer.load()
    player.load(world)
    enemy.load()
    boss.load()
    robotArm.load()

    gun.load(world)
    bullet.load(world)
    rocket.load(world)

    sampleScreen.load()
    -- sampleScreen.sample() --load coroutine for sample
    sample = nil
    imageData = nil
    
    command.load()
    
    -- XP globs and enemies

    -- physics

    -- print(shape_sizes)
    if not var.multiplayer or var.multiplayer == 1 then
        coin_shape = love.physics.newCircleShape(5)
        createCoins(var.num_coins)

        -- enemy_shape = love.physics.newCircleShape(10)
        -- createEnemies(var.num_enemies)
    end

    xp.load()

    -- enemy_image = love.graphics.newImage("gfx/enemy.png")
    -- enemy_width, enemy_height = enemy_image:getDimensions()


    editor.load(world, map)


    -- Shaders
    grass.public.load()
    -- wind.load()

    -- grass:setGrassArea(320, 398, 165, 37, 2000)
    fire.load()

    shader.load()
    puddle.load()
    -- smoke.load()
    portal.load()
    destruction.load()
    regions.load() -- after the world, grass and puddles it lays out into
    crt.load()
    blur.load()
    light.load()
    explosion.load()
    suckLight.load()
    car.load(world)
    blackhole.load()
    daynight.load()
    shop.load()
    inventory.load()
    trinkets.load()
    collision.init()
    audio.loadSounds()

    shadow.load()

    smoke.setsmokeArea(320, 138, 165, 67)

    -- Carry on from the newest save, everything it restores loaded by now
    -- (not as a client: it shows the host's game)
    if not var.multiplayer or var.multiplayer == 1 then
        serial.loadMostRecent()
    end
    if var.smoke_test then player.god = true end

    love.draw = mydraw.mydraw
end

local t = 0
local frameCounter = 0
local paused

function love.update(dt) --assume online cannot pause right now. debugger still works

    profiler.frameUpdate(dt)

    -- if t > (math.sin(fire.t) +1)*50*dt then --this slows down physics updates. before testing this consider consistency of frametimes lag spikes etc...
    map.houseInstances[1].color = { 1, 1, 1, var.indoors and 0 or 1 }

    map_c = map.addMapToDynamicDrawList(map.house, 0, 0, 0.8, 100)

    -- print(player.body:getLinearVelocity())

    -- print(math.floor(math.abs((math.sin(fire.t)*7)) + 1))

    if var.multiplayer then
        mp:update()
        multiplayer.sendMovementMessage(dt)
    end

    editor.update(dt)

    if var.State == "menu" then
        menu.update(dt)
        -- if not var.multiplayer then
        if not paused then
            paused = love.audio.pause() -- change this to stop other audio play menu
        end

        return
    else
        if paused then
            for _, v in pairs(paused) do
                love.audio.play(v)
                paused = nil
            end
        end
        -- love.audio.setVolume(1)
    end

    -- The black hole sets the pace: everything from here on runs on its time
    -- (the network above keeps real time)
    blackhole.update(dt)
    dt = dt * blackhole.timeScale
    daynight.update(dt)
    shop.update(dt)

    characterAnimator.update(dt)
    -- teslaCoil.fireAt(love.mouse.getPosition())
    -- teslaCoil.fireAt(player.body:getX() + gun.lastAimDirection.x*100, player.body:getY() + gun.lastAimDirection.y*100)
    -- teslaCoil.update(dt)


    -- t = t + dt
    -- if t > 0.5 then
    -- print(dt)
    world:update(dt)
    -- t = 0
    -- end

    player.update(dt)
    car.update(dt)

    -- Spatial audio: keep the listener on the player, reap finished voices.
    audio.setListener(player.getPosition())
    audio.update(dt)

    -- Update player interpolation for smooth multiplayer movement
    if var.multiplayer then
        renderer.updateInterpolation(dt)
    end

    -- camera.update(dt, player)
    puddle.update(dt)
    -- smoke.update(dt)
    fire.update(dt)
    if var.grass then
        grass.public.update(dt)
    end
    portal.update(dt)
    regions.update(dt) -- before the lighting upload: its lamps add lights
    destruction.update(dt) -- after the physics step: what was knocked down in it comes down
    -- blur.update(dt)
    explosion.update(dt)
    command.update(dt)
    map.updateHouses(dt)


    if var.multiplayer == 1 or not var.multiplayer then
        enemy.update(dt)
        boss.update(dt)
        bosses.update(dt) -- out of their lairs while you're in their region
    else
        enemy.updateNetworked(dt) -- the host runs them; draw where it says
    end
    robotArm.update(dt) -- (the host's think; everyone's solve, and light the street)

    gun.update(dt)
    xp.update(dt)
    inventory.update(dt) -- items on the ground sliding into the bag
    trinkets.update(dt) -- before the lighting upload: the moth, rings of fire
    suckLight.update(dt) -- before the lighting upload: its motes add lights
    light.update(dt) -- before the lighting upload: the flashlight's beam
    blackhole.addLights() -- its disk's glow on the ground
    shop.addLights() -- the shopkeeper's lantern
    daynight.apply() -- the hour's ambient light, before the lighting upload
    shadow.updateBothShaders(dt)
    -- bullet.update(dt)
    -- rocket.update(dt)

    -- wind.update(dt)

    -- t = 0
    -- end

    -- world:update(dt)
    -- player.update(dt)
    camera.update(dt, player)

    -- t = t + 1


     t = t + dt
    frameCounter = frameCounter + 1
    if t >= 1 then
        local fps = frameCounter / t
        love.window.setTitle(string.format("fps: %.1f | ents: %d | list: %d | mem: %.0fMB",
            fps, #enemy.enemies, #dynamic_draw_list, collectgarbage("count") / 1024))
        frameCounter = 0
        t = 0
        -- imageData = sampleScreen.canvas:newImageData()
        
        -- print(sample)
        -- if sample and coroutine.status(sample) ~= "dead" then
        --     coroutine.resume(sample)
        -- -- print(s,e)
        -- else
        --     sampleScreen.sample() --load coroutine for sample
        -- end
    end

end

-- Settings changed outside the Settings screen ("b", the FPS keys) are
-- kept too; a restart (New Game, hot reload) comes through here as well
function love.quit()
    settings.saveIfChanged()
end

function love.resize(w, h)
    var.screen_width = w
    var.screen_height = h
    var.ScreenInfo.screen_width = w
    var.ScreenInfo.screen_height = h
    -- Update game area dimensions on resize to match screen size
    W = w
    H = h
    var.game_width = w
    var.game_height = h - var.header_height
    game_area_x = (W - var.game_width) / 2
    game_area_y = var.header_height
    shader.load()
    light.load()
end

function love.mousepressed(x, y, button, istouch, presses)
    -- The console draws on top of the CRT, so it takes screen coordinates
    -- teslaCoil.start()
    if command.mousepressed(x, y, button) then
        return
    end
    -- Everything else is drawn under the CRT bulge: click what's shown there
    x, y = crt.toImage(x, y)

    if var.State == "menu" then
        local nextStateAction = menu.mousepressed(x, y, button, var.ScreenInfo)

        if nextStateAction == "running" then
            var.State = "running"
            -- player.health = 100
            --reset game here
            serial.startFresh() -- not straight back into the newest save
            love.event.push("quit", "restart")
        elseif nextStateAction == "exit" then
            love.event.quit()
        end
        return -- Don't process game input when in menu
    end

    if shop.mousepressed(x, y, button) then
        return -- bought something, or clicked on the trade panel
    end
    if inventory.mousepressed(x, y, button) then
        return -- used or dropped something, or clicked on the bag
    end
    if command.clickBlock(x, y, button) then
        return -- command block was clicked
    end
    if portal.mousepressed(x, y, button) then
        return -- picked a destination in the travel selector
    end
    -- Delegate to gun system for shooting (only when not in menu)
    gun.mousepressed(x, y, button)

    local center_x = love.graphics.getWidth() / 2 -- or player's screen position
    local center_y = love.graphics.getHeight() / 2

    local direction = vec2.new(x - center_x, y - center_y)
    local normalized_direction = vec2.norm(direction)

    -- Right click quick-throws a fireball without selecting its hotbar slot
    if button == 2 then
        gun.throwFireball(normalized_direction)
    end

    editor.mousepressed(x, y, button)

    -- lurker.scan()
end

function love.textinput(text)
    command.textinput(text)
end

lurker.preswap = function(file)
    -- var.num_coins=0
    -- love.load()
    love.event.push("quit", "restart")
end

local zoomToggle = false;
function love.keypressed(key)
    if command.keypressed(key) then
        return -- the console is open (or "/" or "," just opened it)
    end
    if shop.keypressed(key) then
        return -- E at the counter, or the trade panel's keys
    end
    if inventory.keypressed(key) then
        return -- I / Tab, H, or the open bag's keys
    end
    if car.keypressed(key) then
        return -- E: into the car or out of it
    end
    if portal.keypressed(key) then
        return -- the travel selector took it (Esc closes it, not the menu)
    end
    if key == "f1" then
        profiler.overlay_visible = not profiler.overlay_visible
        if profiler.overlay_visible then
            profiler.overlay_detail = (profiler.overlay_detail % 2) + 1
        end
    end
    if key == "f2" then
        profiler.reset()
        profiler.overlay_visible = true
        profiler.overlay_detail = 2
        print("Benchmark mode: FPS/reset, observe overlay for 5 seconds")
    end
    if key == "f3" then
        profiler.report()
    end
    if key == "z" then
        if not zoomToggle then
            camera.setZoom(2)
            -- gun_enemy.setState(1)

            -- player.body:applyForce(1000,0)
            -- hit.markHit("player", 1.0, 50) -- Strong distortion for 0.5 seconds
        else
            camera.setZoom(1)

            -- gun_enemy.setState(2)
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
        menu.escape()

        -- blur.set_radius(0.00001)
    end

    if key == "f" then
        player.lightsOn = not player.lightsOn
    end

    -- Testing hook: step the bullet tracer brightness down, wrapping back to
    -- full. Later this follows the player's light level instead.
    if key == "b" then
        local levels = { 1.0, 0.7, 0.45, 0.25, 0.1 }
        local next_level = levels[1]
        for i, level in ipairs(levels) do
            if var.tracer_brightness > level + 1e-6 then break end
            next_level = levels[i + 1] or levels[1]
        end
        var.tracer_brightness = next_level
        print(string.format("Tracer brightness %.2f", var.tracer_brightness))
    end

    -- Browser shell controls send this same key event, so the mute state is
    -- owned by the game rather than by an unreliable Web Audio wrapper.
    if key == "m" then
        audio.setMuted(not audio.muted)
        print("Audio " .. (audio.muted and "muted" or "unmuted"))
    end

    editor.keypressed(key)
    gun.keypressed(key)
end

function love.mousereleased(x, y, button, istouch, presses)
    command.mousereleased(x, y, button)

    if var.State ~= "menu" then
        gun.mousereleased(x, y, button)
    end
end

function love.mousemoved(x, y, dx, dy, istouch)
    command.mousemoved(x, y, dx, dy) -- dragging the console window
end

function love.keyreleased(key)
    command.keyreleased(key)
end

function love.wheelmoved(x, y)
    if command.wheelmoved(x, y) then
        return -- scrolled the console
    end
    if shop.open then
        return -- the wheel stays on your weapon while trading
    end
    if var.State ~= "menu" then
        if not portal.wheelmoved(x, y) then
            gun.wheelmoved(x, y)
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

function createCoin(x, y)
    coin_shape = coin_shape or love.physics.newCircleShape(5)
    local _bod = love.physics.newBody(world, x, y, "dynamic")
    table.insert(coin_bods, 1, _bod)
    local _fixture = love.physics.newFixture(_bod, coin_shape)
    _fixture:setGroupIndex(69)
    return _bod, _fixture
end

function createCoins(n)
    for _ = 1, n do
        createCoin(math.random(200, var.game_width + 200), math.random(50, var.game_height + 50))
    end
end

-- function createEnemies(n)
--     for _ = 1, n do
--         local _bod = love.physics.newBody(world, math.random(200, var.game_width + 200),
--             math.random(50, var.game_height + 50),
--             "dynamic")
--         table.insert(enemies_bods, 1, _bod)
--         _fixture = love.physics.newFixture(_bod, enemy_shape)
--         _fixture:setGroupIndex(-777)

--         -- Set enemy mass and physics properties for proper knockback
--         _fixture:setDensity(2.0)    -- Give enemies substantial mass
--         _bod:resetMassData()        -- Apply the density changes
--         _bod:setLinearDamping(3.0)  -- Add damping so they don't slide forever
--         _bod:setAngularDamping(5.0) -- Prevent excessive spinning
--     end
-- end

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
    collision.handle(fixture_a, fixture_b, contact)
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
