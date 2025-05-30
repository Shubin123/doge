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


    player.load(world)
    enemy.load()


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

    water.setWaterArea(320, 238, 165, 67)
    smoke.setsmokeArea(320, 138, 165, 67)
end

local W = love.graphics.getWidth()
local H = love.graphics.getHeight()
local game_area_x = (W - var.game_width) / 2
local game_area_y = var.header_height

-- Dynamic draw list for Y-sorting
dynamic_draw_list = {}

-- Sorting function for Y-axis rendering
local function sortByRenderY(drawable_a, drawable_b)
    return drawable_a.sort_y < drawable_b.sort_y
end
flipQuads = true
-- Function to populate dynamic draw list
local function populateDynamicDrawList()
    -- Clear the list
    --     if not table.unpack then
    --     table.unpack = unpack
    -- end

    dynamic_draw_list = { unpack(map_a, 1, #map_a) }
    rebuildArray(dynamic_draw_list, map_b)

    -- Player drawable
    local px, py = player.body:getX(), player.body:getY()
    local spriteNum = math.floor(player.animation.currentTime / (player.animation.duration) * #player.animation.quads) + 1
    local sort_y = py + (100 * player.scale)
    
    
    table.insert(dynamic_draw_list, {
        sort_y = sort_y + 45,
        image_or_particles = player.animation.spriteSheet,
        quad = player.animation.quads[(spriteNum + 5)%5 + 6] or var.nullquad,
        x = px,
        y = py,
        rotation = var.character_rotation,
        scale_x = player.scale,
        scale_y = player.scale,
        offset_x = 35,
        offset_y = 50,
        color = { 1, 1, 1, 1 },
        blend_mode = { "alpha" },
        source_object_type = "player"
    })
    
    -- Enemies drawables
    for i = 1, #enemies_bods do
        local ex, ey = enemies_bods[i]:getX(), enemies_bods[i]:getY()
        local enemy_sort_y = ey + (enemy_image:getHeight() * 0.1) / 2

        table.insert(dynamic_draw_list, {
            sort_y = enemy_sort_y + 100,
            image_or_particles = enemy_image,
            quad = nil,
            x = ex,
            y = ey,
            rotation = 0,
            scale_x = 0.1,
            scale_y = 0.1,
            offset_x = enemy_image:getWidth() / 2,
            offset_y = enemy_image:getHeight() / 2,
            color = { 1, 1, 1, 1 },
            blend_mode = { "alpha" },
            source_object_type = "enemy"
        })
    end

    -- Coins drawables
    for i = 1, #coin_bods do
        local cx, cy = coin_bods[i]:getX(), coin_bods[i]:getY()
        local coin_sort_y = cy + (coin_image:getHeight() * 0.5) / 2

        table.insert(dynamic_draw_list, {
            sort_y = coin_sort_y + 100,
            image_or_particles = coin_image,
            quad = nil,
            x = cx,
            y = cy,
            rotation = 0,
            scale_x = 0.5,
            scale_y = 0.5,
            offset_x = coin_image:getWidth() / 2,
            offset_y = coin_image:getHeight() / 2,
            color = { 1, 1, 1, 1 },
            blend_mode = { "alpha" },
            source_object_type = "coin"
        })
    end

    -- Fire effects drawables
    fire.populate()
    enemy.populate()
end
 

-- Function to render sorted draw list
local function renderSortedDrawList()
    -- Store current graphics state
    local current_color = { love.graphics.getColor() }
    local current_blend_mode = love.graphics.getBlendMode()

    local last_color = { 1, 1, 1, 1 }
    local last_blend_mode = { "alpha" }

    for _, drawable in ipairs(dynamic_draw_list) do
        -- Set color if different from last
        if drawable.color[1] ~= last_color[1] or drawable.color[2] ~= last_color[2] or
            drawable.color[3] ~= last_color[3] or drawable.color[4] ~= last_color[4] then
            love.graphics.setColor(drawable.color[1], drawable.color[2], drawable.color[3], drawable.color[4])
            last_color = drawable.color
        end

        -- Set blend mode if different from last
        if drawable.blend_mode[1] ~= last_blend_mode[1] or
            (drawable.blend_mode[2] and drawable.blend_mode[2] ~= last_blend_mode[2]) then
            if drawable.blend_mode[2] then
                love.graphics.setBlendMode(drawable.blend_mode[1], drawable.blend_mode[2])
            else
                love.graphics.setBlendMode(drawable.blend_mode[1])
            end
            last_blend_mode = drawable.blend_mode
        end

        -- Draw the drawable
        if drawable.quad then
            love.graphics.draw(
                drawable.image_or_particles,
                drawable.quad,
                drawable.x,
                drawable.y,
                drawable.rotation or 0,
                drawable.scale_x or 1,
                drawable.scale_y or 1,
                drawable.offset_x or 0,
                drawable.offset_y or 0
            )
        else
            love.graphics.draw(
                drawable.image_or_particles,
                drawable.x,
                drawable.y,
                drawable.rotation or 0,
                drawable.scale_x or 1,
                drawable.scale_y or 1,
                drawable.offset_x or 0,
                drawable.offset_y or 0
            )
        end
    end

    -- Restore original graphics state
    love.graphics.setColor(current_color[1], current_color[2], current_color[3], current_color[4])
    love.graphics.setBlendMode(current_blend_mode)
end

function rebuildArray(arr, innerElements)
    -- table.insert(dynamic_draw_list,map_b[1])
    -- table.insert(dynamic_draw_list,map_b[2])
    -- table.insert(dynamic_draw_list,map_b[3])
    for i = 1, #innerElements do
        table.insert(arr, innerElements[i])
    end
end

function addMapToDynamicDrawList(mapData, map_x, map_y, map_scale, base_sort_y)
    map_x = map_x or 0
    map_y = map_y or 0
    map_scale = map_scale or 1

    local max_tiles_x = math.ceil(var.game_width / (mapData.tiles.tileWidth * map_scale))
    local max_tiles_y = math.ceil(var.game_height / (mapData.tiles.tileHeight * map_scale))

    local dynamic_draw_lists = {}

    for row = 1, max_tiles_y do
        for col = 1, max_tiles_x do
            local tileId = mapData.tileData[row] and mapData.tileData[row][col]
            if tileId and tileId > 0 and mapData.tiles.quads[tileId] then
                local tile_x = map_x + (col - 1) * mapData.tiles.tileWidth * map_scale
                local tile_y = map_y + (row - 1) * mapData.tiles.tileHeight * map_scale
                local tile_sort_y = base_sort_y + tile_y -- Use tile's Y position for sorting

                table.insert(dynamic_draw_lists, {
                    sort_y = tile_sort_y,
                    image_or_particles = mapData.tiles.tilesetImage,
                    quad = mapData.tiles.quads[tileId],
                    x = tile_x,
                    y = tile_y,
                    rotation = 0,
                    scale_x = map_scale,
                    scale_y = map_scale,
                    offset_x = 0,
                    offset_y = 0,
                    color = { 1, 1, 1, 1 },
                    blend_mode = { "alpha" },
                    source_object_type = "map_tile"
                })
            end
        end
    end

    return dynamic_draw_lists
end

function love.draw()
    if var.State == "menu" then
        menu.draw()
        return
    end
    love.graphics.push()
    shader.prepass()


    camera.apply()

    love.graphics.setColor(1, 1, 1, 0.35)
    map.map:draw(game_area_x, game_area_y, 1)
    love.graphics.setColor(1, 1, 1, 1)



    -- Populate and sort dynamic draw list if neccessary
    populateDynamicDrawList()
    table.sort(dynamic_draw_list, sortByRenderY)

    -- Render sorted entities
    renderSortedDrawList()

    grass.demo.draw()
    -- map.map3:draw(100, game_area_y, 1)
    -- map.map3:draw(100, game_area_y, 1)
    -- map.map4:draw(100, game_area_y, 0.8)

    -- else
    --     map.map3:draw(100, game_area_y, 1)
    --     map.map4:draw(100, game_area_y, 0.8)
    --     player.draw()

    -- end



    love.graphics.pop()
    -- order is IMPORTANT HERE shader-> smoke -> water

    shader.pass()
    smoke.pass()
    water.pass()
    
    mydraw.mydraw() -- ui last
end

function love.update(dt)
    if var.State == "menu" then
        menu.update(dt)
        -- return
    elseif State == "running" then
        var.State = "game"
    end

    world:update(dt)

    -- if State == "game" then
    player.update(dt)
    camera.update_framerate_independent(dt, player)
    -- end

    water.update(dt)
    smoke.update(dt)
    fire.update(dt)

    grass.demo.update(dt)
    enemy.update(dt)
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
    if key == "space" then
        if not zoomToggle then
            camera.setZoom(2)
            
        else
            camera.setZoom(1)
        end

        zoomToggle = not zoomToggle
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
