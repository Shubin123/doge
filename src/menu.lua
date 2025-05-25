local menu = {}

local font
local ps
local startButton = { y = 250, text = "[ Start Game ]" }
local exitButton = { y = 300, text = "[ Exit ]" }



-- Helper function to calculate button bounds
local function getButtonBounds(buttonInfo, screenInfo)
    local bounds = {}
    bounds.height = font:getHeight()
    bounds.width = font:getWidth(buttonInfo.text)
    bounds.x = (screenInfo.screen_width - bounds.width) / 2
    bounds.y = buttonInfo.y
    return bounds
end

-- Load assets and initialize particle system
function menu.load(screenInfo)
    -- Load the custom font
    font = love.graphics.newFont("gfx/menu/PixelGameFont.ttf", 16)
    particle = love.graphics.newImage("gfx/doge.png")
    love.graphics.setFont(font)
    
    -- Create and configure the particle system for a Star Wars-like starfield
    ps = love.graphics.newParticleSystem(particle, 1000)
    ps:setParticleLifetime(6, 12)  -- Particles live long enough to cross the screen
    ps:setEmissionRate(20)         -- Emit 20 particles per second for a denser field
    ps:setSizes(2)                 -- Small size for star-like dots
    ps:setColors({0.5,0.5,0.5,0}, {0.5,0.5,0.5,0.5}, {0.5,0.5,0.5,0})  -- Fade in and out for a twinkling effect
    ps:setSpeed(50, 100)           -- Varying speeds for depth
    ps:setDirection(math.pi / 2)   -- Move downwards (π/2 radians = 90 degrees)
    ps:setSpread(0.4)              -- Slight spread for natural variation
    ps:setEmissionArea("uniform", screenInfo.screen_width, 1)  -- Emit across the top
    ps:setPosition(screenInfo.screen_width / 2, -50)  -- Emitter positioned above screen
    ps:setEmitterLifetime(-1)      -- Emit continuously
    ps:start()                     -- Start the particle system
end

-- Update the particle system
function menu.update(dt)
    ps:update(dt)
end

-- Draw the menu with particle background
function menu.draw()
    
    -- Draw the particle system as the background
    love.graphics.draw(ps)
    
    -- Set color for text to ensure visibility
    love.graphics.setColor(1, 1, 1, 1)
    
    -- Draw menu text and buttons
    love.graphics.printf("Doge.", 0, 90, var.screen_width/2, "center",0 , 2, 2)
    love.graphics.printf("Game Version = beta beta alpha 0.0.0.0.2", 0, 125, var.screen_width/0.8, "center", 0, 0.8, 0.8)
    love.graphics.printf(startButton.text, 0, startButton.y, var.screen_width, "center")
    love.graphics.printf(exitButton.text, 0, exitButton.y, var.screen_width, "center")
end

-- Handle mouse presses
function menu.mousepressed(x, y, button, screenInfo)
    local startBounds = getButtonBounds(startButton, screenInfo)
    local exitBounds = getButtonBounds(exitButton, screenInfo)
    
    if button == 1 then
        if x >= startBounds.x and x <= startBounds.x + startBounds.width and
           y >= startBounds.y and y <= startBounds.y + startBounds.height then
            print("Menu Module: Start clicked")
            return "loading"
        end
        if x >= exitBounds.x and x <= exitBounds.x + exitBounds.width and
           y >= exitBounds.y and y <= exitBounds.y + exitBounds.height then
            print("Menu Module: Exit clicked")
            return "exit"
        end
    end
    return nil
end

return menu