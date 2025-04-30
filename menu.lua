local Menu = {}

local startButton = { y=250, text = "[ Start Game ]" }
local exitButton = { y=300, text = "[ Exit ]" }

local function getButtonBounds(buttonInfo, screenInfo)
    local bounds = {}
    local font = love.graphics.getFont()
    bounds.height = font:getHeight()
    bounds.width = font:getWidth(buttonInfo.text)
    bounds.x = (screenInfo.screen_width - bounds.width) / 2
    bounds.y = buttonInfo.y 
    return bounds
end

function Menu.update(dt)

end

function Menu.draw(screenInfo)

    local startBounds = getButtonBounds(startButton, screenInfo)
    local exitBounds = getButtonBounds(exitButton, screenInfo)

    love.graphics.printf("What is the name of this game?", 0, 100, screenInfo.screen_width, "center")
    love.graphics.printf("Game Version = beta beta alpha 1.0.0.0.0", 0, 110, screenInfo.screen_width, "center")

    love.graphics.printf(startButton.text, 0, startBounds.y, screenInfo.screen_width, "center")
    love.graphics.printf(exitButton.text, 0, exitBounds.y, screenInfo.screen_width, "center")
end

function Menu.mousepressed(x, y, button, screenInfo)

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

return Menu 