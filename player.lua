local player = {}
local var = require("var")

function newAnimation(image, width, height, duration, numFrames)
    local animation = {}
    animation.spriteSheet = image
    animation.quads = {}
    
    local totalPossibleFrames = math.floor(image:getWidth() / width) * math.floor(image:getHeight() / height)
    local framesToUse = numFrames or totalPossibleFrames
    framesToUse = math.min(framesToUse, totalPossibleFrames)
    
    local frameCount = 0
    for y = 0, image:getHeight() - height, height do
        for x = 0, image:getWidth() - width, width do
            table.insert(animation.quads, love.graphics.newQuad(x, y, width, height, image:getDimensions()))
            frameCount = frameCount + 1
            if frameCount >= framesToUse then
                break
            end
        end
        if frameCount >= framesToUse then
            break
        end
    end
    
    animation.duration = duration or 1
    animation.currentTime = 0
    return animation
end

function player.load(world)
    player.body = love.physics.newBody(world, var.game_width / 2, var.game_height / 2, "dynamic")
    player.shape = love.physics.newRectangleShape(20, 20)
    player.fixture = love.physics.newFixture(player.body, player.shape)
    player.character = love.graphics.newImage("gfx/doge.png")
    player.width, player.height = player.character:getDimensions()
    player.animation = newAnimation(love.graphics.newImage("gfx/WarriorSpriteSheet/Warrior_Sheet-Effect.png"), 69, 44, 1, 30)
end

function player.update(dt)
    local speed = 200
    local vx, vy = player.body:getLinearVelocity()
    if love.keyboard.isDown("a") then
        player.body:setLinearVelocity(-speed, vy)
    elseif love.keyboard.isDown("d") then
        player.body:setLinearVelocity(speed, vy)
    else
        player.body:setLinearVelocity(0, vy)
    end
    if love.keyboard.isDown("w") then
        player.body:setLinearVelocity(vx, -speed)
    elseif love.keyboard.isDown("s") then
        player.body:setLinearVelocity(vx, speed)
    else
        player.body:setLinearVelocity(vx, 0)
    end
    player.animation.currentTime = player.animation.currentTime + dt
    if player.animation.currentTime >= player.animation.duration then
        player.animation.currentTime = player.animation.currentTime - player.animation.duration
    end
end

function player.getPosition()
    return player.body:getX(), player.body:getY()
end

function player.getAnimation()
    return player.animation
end

return player