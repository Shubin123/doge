math.randomseed(os.time())

local menu = require("menu")
local mymath = require("mymath")
local effects = require("effects")
-- globals
screen_height = 600
screen_width = 600
screen_flags = {
    ["resizable"] = true
}

character_rotation = 0
prev_x = 0
prev_y = 0
linear_score = 0
player_score = 0
num_coins = 10
coin_bods = {}
num_enemies = 0
enemies_bods = {}

sprite_height = 10
sprite_width = 10

map_display_h = 2560
map_display_w = 2560
map_offset_x = 320
map_offset_y = 320
tile_w = 32
tile_h = 32


ScreenInfo = {
    screen_height = 600,
    screen_width = 600,
    screen_flags = {
        ["resizable"] = true
    }
}
points = {}

State = "menu"
cursorImage = love.graphics.newImage("gfx/menu/old_hand.png")



function love.load()
    love.mouse.setVisible(false)
    
    
    -- window -- 
    success = love.window.setMode(screen_width, screen_height, screen_flags)

    -- physics --

    world = love.physics.newWorld(0, 0)
    world:setCallbacks(beginContact, endContact, preSolve, postSolve)

    fence_body = love.physics.newBody(world, 0, 0, "static")
    fence_shape = love.physics.newChainShape(true, -100, -100, screen_width, -100, screen_width, screen_height, -100,
        screen_height)
    fence_fixture = love.physics.newFixture(fence_body, fence_shape)

    body = love.physics.newBody(world, love.mouse.getX(), love.mouse.getY(), "dynamic")
    shape = love.physics.newRectangleShape(20, 20) -- collision is non-sense rn
    fixture = love.physics.newFixture(body, shape)
    -- joint = love.physics.newMouseJoint(body, love.mouse.getPosition())

    coin_shape = love.physics.newCircleShape(18)
    createCoins(num_coins)

    enemy_shape = love.physics.newCircleShape(100)
    createEnemies(num_enemies)
    -- graphics --
    character = love.graphics.newImage("gfx/doge.png")
    image = love.graphics.newImage("gfx/coin.png")
    enemy_image = love.graphics.newImage("gfx/enemy.png")

    character_width, character_height = character:getDimensions()
    png_width, png_height = image:getDimensions()
    enemy_width, enemy_height = enemy_image:getDimensions()

    animation = newAnimation(love.graphics.newImage("gfx/WarriorSpriteSheet/Warrior_Sheet-Effect.png"), 69, 44, 1, 30)
    -- animation = newAnimation(love.graphics.newImage("gfx/SoldierSpriteSheets/Soldier_Attack01.png"), sprite_width, sprite_height, 1, 6)
    tile = newTiles(love.graphics.newImage("gfx/TileSet/TX Tileset Grass.png"), tile_w, tile_h)
    map = createMap(tile, map_display_w, map_display_w)
    for i = 1, 10 do
        map:setTile(i, 5, 2)  -- Place tile #2 in a horizontal line
    end

end

function love.draw()
    if State == "menu" then
    menu.draw(ScreenInfo)
    love.graphics.draw(cursorImage, love.mouse.getX(), love.mouse.getY(), 0, 0.05, 0.05)
    return
    end 
    map:draw(256, 256)  -- Draw the map at position (50,50)

    -- physics updates --
    local vx, vy = body:getLinearVelocity()
    local x, y = body:getPosition()
    linear_score = round(vx ^ 2 + vy ^ 2, -4) / 10000

    -- Calculate the correct heading angle based on velocity direction
    local heading = 0
    if linear_score > 1 then
        heading = math.atan2(y - prev_y, x - prev_x)
        prev_x = x
        prev_y = y
    end

    -- Smoothly interpolate between current rotation and target heading
    -- character_rotation = quad_in_out(character_rotation, heading, 0.8) -- broken in signed axis 
    if math.abs(heading) > 0 then
        character_rotation = heading
    end

    -- draw updates --
    love.graphics.print("fps: " .. love.timer.getFPS(), 0, 0)
    love.graphics.print("linear_score: " .. linear_score, 0, 10)
    love.graphics.print("heading: " .. round(heading, 2), 0, 20)
    love.graphics.print("rotation: " .. round(character_rotation, 2), 0, 30)
    love.graphics.print("score: " .. player_score, screen_width / 2, 40)

    -- love.graphics.draw(character, -- image
    -- body:getX(), -- x position
    -- body:getY(), -- y position
    -- character_rotation, -- rotation
    -- 1, 1, -- scale x, scale y
    -- character_width / 2, character_height / 2 -- origin offset (center of image)
    -- )

    for i = 1, num_coins do
        love.graphics.draw(image, coin_bods[i]:getX(), coin_bods[i]:getY(), 0, 1, 1, png_width / 2, png_height / 2)
    end
   

    for i = 1,num_enemies do
        love.graphics.draw(enemy_image, enemies_bods[i]:getX(),enemies_bods[i]:getY(), 0, 1, 1, enemy_width / 2, enemy_height / 2)
    end

    local spriteNum = math.floor(animation.currentTime / animation.duration * #animation.quads) + 1
    print(mymath.sign(character_rotation))
    love.graphics.draw(animation.spriteSheet, animation.quads[spriteNum], body:getX()  , body:getY(),character_rotation, 1,1, sprite_width/2, sprite_height/2)


end

function love.update(dt)
    if State == "menu" then
        menu.draw(ScreenInfo)
        return
        end 

    -- love.graphics.draw(love.graphics.newImage("gfx/apple.png"))
    -- joint:setTarget(love.mouse.getPosition()) -- if mobile use love.touch.getPosition() -- can be an array with multiple touch points id = love.touch.getTouches()
    world:update(dt)

    animation.currentTime = animation.currentTime + dt
    if animation.currentTime >= animation.duration then
        animation.currentTime = animation.currentTime - animation.duration
    end
    if love.mouse.isDown(1) then
		print("mouse down")
        local x, y = love.mouse.getPosition()
        effects.newHitMarker(x,y)
	end	
end

function love.resize(w, h)
    -- Update global dimensions
    screen_width = w
    screen_height = h
    ScreenInfo.screen_width = w
    ScreenInfo.screen_height = h

    -- Destroy the old fence fixture
    fence_fixture:destroy()

    -- Create a new fence with updated dimensions
    fence_shape = love.physics.newChainShape(true, -100, -100, screen_width, -100, screen_width, screen_height, -100,screen_height)
    fence_fixture = love.physics.newFixture(fence_body, fence_shape)
    fence_fixture:setUserData("fence")
end


function love.mousepressed(x, y, button, istouch, presses)
    if State == "menu" then
        local nextStateAction = menu.mousepressed(x, y, button, ScreenInfo) 
        if nextStateAction == "loading" then
            State = "loading" 
        elseif nextStateAction == "exit" then
            love.event.quit() 
        end
    elseif State == "game" then
        
    end
end


function round(x, n)
    n = math.pow(10, n or 0)
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
    t = math.max(0, math.min(1, t)) -- Clamp t between 0 and 1
    if t <= 0.5 then
        return lerp(a, b, 2 * t * t)
    else
        t = t - 1
        return lerp(a, b, 1 - 2 * t * t)
    end
end

function createCoins(n)
    for _ = 1, n do
        local _bod = love.physics.newBody(world, math.random(0, screen_width), math.random(0, screen_height), "dynamic")
        table.insert(coin_bods, 1, _bod)
        _fixture = love.physics.newFixture(_bod, coin_shape)
        _fixture:setGroupIndex(69)
        
    end

end

function createEnemies(n)
    for _ = 1, n do
        local _bod = love.physics.newBody(world, math.random(0, screen_width), math.random(0, screen_height), "dynamic")
        table.insert(enemies_bods, 1, _bod)
        _fixture = love.physics.newFixture(_bod, enemy_shape)
        _fixture:setGroupIndex(777)

    end

end

function beginContact(fixture_a, fixture_b, contact)
    local body_a = fixture_a:getBody()
    local body_b = fixture_b:getBody()
    if (fixture_a:getGroupIndex() == 69 or fixture_b:getGroupIndex() == 69) then
        local ball_body = 0
        if (body_a == body) then 
            ball_body = body_b
        elseif (body_b == body) then
            ball_body = body_b
        else return
        end

        for i = 1, num_coins do
            if coin_bods[i] == ball_body then
                print("Deleting ball at index", i)
                table.remove(coin_bods, i)
                num_coins = num_coins - 1
                player_score = player_score + 1
                
                break

            end
        end
    end
end

function newAnimation(image, width, height, duration, numFrames)
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

function newTiles(tilesetImage, tileWidth, tileHeight)
    local tiles = {}
    tiles.tilesetImage = tilesetImage
    tiles.tileWidth = tileWidth
    tiles.tileHeight = tileHeight
    tiles.quads = {}
    
    -- Calculate the number of tiles in the tileset
    local tilesWide = math.floor(tilesetImage:getWidth() / tileWidth)
    local tilesHigh = math.floor(tilesetImage:getHeight() / tileHeight)
    
    -- Create quads for each tile in the tileset
    local tileCount = 0
    for y = 0, tilesetImage:getHeight() - tileHeight, tileHeight do
        for x = 0, tilesetImage:getWidth() - tileWidth, tileWidth do
            tileCount = tileCount + 1
            tiles.quads[tileCount] = love.graphics.newQuad(
                x, y, tileWidth, tileHeight, tilesetImage:getDimensions()
            )
        end
    end
    
    return tiles
end

function createMap(tiles, mapWidth, mapHeight, tileData)
    local map = {}
    map.tiles = tiles
    map.width = mapWidth
    map.height = mapHeight
    
    -- If tileData is provided, use it; otherwise create an empty map
    map.tileData = tileData or {}
    
    -- If tileData wasn't provided, initialize with zeros (empty tiles)
    if not tileData then
        for y = 1, mapHeight do
            map.tileData[y] = {}
            for x = 1, mapWidth do
                map.tileData[y][x] = 0 -- 0 typically represents empty space or a default tile
            end
        end
    end
    
    -- Function to draw the map
    map.draw = function(self, x, y, scale)
        x = x or 0
        y = y or 0
        scale = scale or 1
        
        for row = 1, self.height do
            for col = 1, self.width do
                local tileId = self.tileData[row][col]
                if tileId > 0 and self.tiles.quads[tileId] then
                    love.graphics.draw(
                        self.tiles.tilesetImage,
                        self.tiles.quads[tileId],
                        x + (col-1) * self.tiles.tileWidth * scale,
                        y + (row-1) * self.tiles.tileHeight * scale,
                        0,
                        scale,
                        scale
                    )
                end
            end
        end
    end
    
    -- Function to set a tile at a specific position
    map.setTile = function(self, x, y, tileId)
        if x >= 1 and x <= self.width and y >= 1 and y <= self.height then
            self.tileData[y][x] = tileId
        end
    end
    
    -- Function to get a tile at a specific position
    map.getTile = function(self, x, y)
        if x >= 1 and x <= self.width and y >= 1 and y <= self.height then
            return self.tileData[y][x]
        end
        return 0 -- Return 0 (empty) for out-of-bounds coordinates
    end
    
    return map
end

function draw_map()
    for y=1, map_display_h do
       for x=1, map_display_w do                                                         
          love.graphics.draw( 
             tile[map[y+map_y][x+map_x]], 
             (x*tile_w)+map_offset_x, 
             (y*tile_h)+map_offset_y )
       end
    end
 end
 
 
