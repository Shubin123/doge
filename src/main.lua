math.randomseed(os.time())

local area_manager = require("area_manager")

menu = require("menu")
mymath = require("myMath")
effects = require("effects")
var = require("var")
local map = require("map")
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
    print("LOVE.LOAD STARTING")
    print("var.State at start:", var.State or "nil")
    
    -- love.mouse.setVisible(false)

    -- Window setup
    print("Setting window mode:", var.screen_width, var.screen_height)
    success = love.window.setMode(var.screen_width, var.screen_height, var.screen_flags)
    print("Window setup success:", success)

    -- Load fonts
    print("Loading fonts...")
    statsFont = love.graphics.newFont("gfx/menu/PixelGameFont.ttf", 16)
    gameFont = love.graphics.newFont("gfx/menu/PixelGameFont.ttf", 16)
    
    -- Load graphics that were moved from var.lua
    print("Loading cursor and nullquad...")
    var.cursorImage = love.graphics.newImage("gfx/menu/old_hand.png")
    var.nullquad = love.graphics.newQuad(0, 0, 0, 0, 0, 0)

    -- Initialize the menu
    menu.load(var.ScreenInfo)

    -- Physics setup is now handled by area_manager

    -- fence_body = love.physics.newBody(nil, 0, 0, "static") -- Body created without a world initially
    -- fence_shape = love.physics.newChainShape(true, 200, 50, var.game_width + 200, 50, var.game_width + 200,
    --     var.game_height + 50, 200,
    --     var.game_height + 50)
    -- fence_fixture = love.physics.newFixture(fence_body, fence_shape)

    -- createArches() -- Arches also need to be handled per area if they are physical objects

    -- Load map and player
    map.load()
    -- map_a and map_b are now handled by area_manager and renderer

    -- Initial area load
    area_manager.loadArea("overworld")
    if player and player.body then
        print("Main.lua love.load: Player body type after load: " .. player.body:getType())
    else
        print("Main.lua love.load: Player or player.body not available after area_manager.loadArea")
    end

    enemy.load() -- Enemy loading might need to be per area as well

    -- Coins and enemies
    -- Coins and enemies are now created within area load functions
    -- coin_shape = love.physics.newCircleShape(5)
    -- createCoins(var.num_coins)

    -- enemy_shape = love.physics.newCircleShape(10)
    -- createEnemies(var.num_enemies)

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
local game_area_x = (W - var.game_width) / 2
local game_area_y = var.header_height



function love.draw()
    print("LOVE.DRAW CALLED - State:", var.State or "nil")
    
    if var.State == "menu" then
        print("Drawing menu")
        menu.draw()
        return
    end
    
    print("Drawing game - bypassing shaders")
    
    -- Minimal test without camera or push/pop
    love.graphics.setColor(1, 0, 0, 1) -- Red
    love.graphics.rectangle("fill", 100, 100, 200, 200)
    
    love.graphics.setColor(1, 1, 1, 1) -- White
    love.graphics.print("BASIC TEST - NO CAMERA", 10, 10)
    love.graphics.print("State: " .. tostring(var.State), 10, 30)
    
    print("Basic shapes drawn")

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
        table.insert(fire.fireables, { vec2.new(0, 0), normalized_direction, false })
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
    print("beginContact CALLED: Fixture A Group: " .. tostring(fixture_a:getGroupIndex()) .. ", Fixture B Group: " .. tostring(fixture_b:getGroupIndex())) -- DEBUG
    player.collision(fixture_a,fixture_b,contact) -- Make sure player's collision logic is called
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

-- Function to check if the player is touching a portal
function checkPortalCollision()
  if not player or not player.body then return end -- Guard against player not being loaded
  local player_x, player_y = player.getPosition()
  local current_area = area_manager.getCurrentArea()

  -- print("checkPortalCollision: Player at (" .. string.format("%.2f", player_x) .. ", " .. string.format("%.2f", player_y) .. ")") -- Optional: very verbose

  if current_area and current_area.transition_points then
    -- print("checkPortalCollision: Current area: " .. current_area.area_id .. " has " .. #current_area.transition_points .. " transition point(s).")
    for i, portal_data in ipairs(current_area.transition_points) do
      local portal_x, portal_y = portal_data.x, portal_data.y
      local distance = math.sqrt((player_x - portal_x)^2 + (player_y - portal_y)^2)
      
      -- More detailed logging for each portal check, can be commented out if too verbose
      -- print("checkPortalCollision: Checking portal " .. i .. " at (" .. portal_x .. ", " .. portal_y .. ") to " .. portal_data.target_area_id .. ". Distance: " .. string.format("%.2f", distance))

      -- Check if the player is within a certain range of the portal
      if distance < 20 then -- Increased threshold slightly for easier activation
        print("checkPortalCollision: Player is NEAR portal " .. i .. " to " .. portal_data.target_area_id .. "! Distance: " .. string.format("%.2f", distance) .. ". Triggering transition.")
        area_manager.transitionArea(portal_data.target_area_id, portal_data.target_x, portal_data.target_y)
        break -- Exit the loop after transitioning
      end
    end
  else
    if not current_area then
      print("checkPortalCollision: No current_area defined.")
    elseif not current_area.transition_points or #current_area.transition_points == 0 then
      -- print("checkPortalCollision: Current area " .. (current_area.area_id or "UNKNOWN") .. " has no transition points.") -- Optional: can be verbose
    end
  end
end

-- Call checkPortalCollision in the love.update function
function love.update(dt)
  if var.State == "menu" then
    menu.update(dt)
    -- return
  elseif State == "running" then
    var.State = "game"
  end

  -- Update the current area's physics world
  local current_area = area_manager.getCurrentArea()
  -- print("Main.lua love.update: dt = " .. tostring(dt)) -- Commented out for less verbose logging

  if current_area and current_area.physics_world then
      -- if player and player.body then -- Commented out block for less verbose logging
          -- local pre_px, pre_py = player.getPosition()
          -- print("Main.lua love.update: Player pos BEFORE world:update(): " .. pre_px .. ", " .. pre_py .. " (World: " .. tostring(current_area.physics_world) .. ")")
      -- end

      current_area.physics_world:update(dt)

      -- if player and player.body then -- Commented out block for less verbose logging
          -- local post_px, post_py = player.getPosition()
          -- print("Main.lua love.update: Player pos AFTER world:update(): " .. post_px .. ", " .. post_py)
      -- end
  else
      if not current_area then
          print("Main.lua love.update: No current_area.") -- This is important, keep it
      elseif not current_area.physics_world then
          print("Main.lua love.update: current_area has no physics_world: " .. current_area.area_id) -- This is important, keep it
      end
  end

  -- if State == "game" then
  player.update(dt) -- player.update logs are already commented out
  camera.update_framerate_independent(dt, player)
  -- end

  water.update(dt)
  smoke.update(dt)
  fire.update(dt)
  
  -- crtShader:setTime(love.timer.getTime())
  -- crtShader:setMousePos(love.mouse.getX(), love.mouse.getY())

  grass.demo.update(dt)
  enemy.update(dt)
  portal.update(dt)

  checkPortalCollision() -- Add this line to call the function
end
