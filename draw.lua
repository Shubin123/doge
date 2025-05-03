draw = {}
local var = require("var")
local player = require("player")
local map = require("map")
function draw.mydraw()
    if State == "menu" then
        menu.draw(var.ScreenInfo)
        love.graphics.draw(var.cursorImage, love.mouse.getX(), love.mouse.getY(), 0, 0.05, 0.05)
        return
    end
    
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()
    local game_area_x = (W - var.game_width) / 2
    local game_area_y = var.header_height
    
    -- Draw header
    love.graphics.setColor(0.2, 0.2, 0.2)
    love.graphics.rectangle("fill", 0, 0, W, var.header_height)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Health: 100", 10, 10)
    love.graphics.print("Points: " .. var.player_score, W - 100, 10)
    
    -- Draw left panel (inventory)
    local left_panel_width = game_area_x
    if left_panel_width > 0 then
        love.graphics.setColor(0.3, 0.3, 0.3)
        love.graphics.rectangle("fill", 0, var.header_height, left_panel_width, H - var.header_height)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Inventory", 10, var.header_height + 10)
    end
    
    -- Draw right panel (map)
    local right_panel_x = game_area_x + var.game_width
    local right_panel_width = W - right_panel_x
    if right_panel_width > 0 then
        love.graphics.setColor(0.3, 0.3, 0.3)
        love.graphics.rectangle("fill", right_panel_x, var.header_height, right_panel_width, H - var.header_height)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Map", right_panel_x + 10, var.header_height + 10)
    end
    
    -- Draw game area
    love.graphics.setScissor(game_area_x, game_area_y, var.game_width, var.game_height)
    
    -- Draw map (only visible tiles)
    -- print(game_area_x,game_area_y)
    map.map:draw(game_area_x, game_area_y, 1)
    -- map.map2:draw(game_area_x, game_area_y, 1)
    
    -- map.map3:draw(game_area_x, game_area_y, 1)
    
    
    -- Draw coins
    for i = 1, var.num_coins do
        local px, py = coin_bods[i]:getX(),coin_bods[i]:getY()
        love.graphics.draw(image, game_area_x + px, game_area_y + py, 0, 1, 1, png_width / 2,  png_height / 2)
    end
    
    -- Draw enemies
    for i = 1, var.num_enemies do
        local px, py = var.enemies_bods[i]:getX(), var.enemies_bods[i]:getY()
        love.graphics.draw(enemy_image, game_area_x + px, game_area_y + py, 0, 1, 1, enemy_width / 2, enemy_height / 2)
    end
    
    -- Draw character
    -- local px, py = body:getX(), body:getY()
    -- local spriteNum = math.floor(player.animation.currentTime / player.animation.duration * #player.animation.quads) + 1
    -- print(animation.currentTime)
    -- love.graphics.draw(player.animation.spriteSheet, player.animation.quads[spriteNum], game_area_x + px, game_area_y + py, var.character_rotation, 1, 1, var.sprite_width / 2, var.sprite_height / 2)
    
    -- Reset scissor
    love.graphics.setScissor()
    
    -- Draw white borders
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", 0, 0, W, var.header_height)
    if left_panel_width > 0 then
        love.graphics.rectangle("line", 0, var.header_height, left_panel_width, H - var.header_height)
    end
    if right_panel_width > 0 then
        love.graphics.rectangle("line", right_panel_x, var.header_height, right_panel_width, H -var.header_height)
    end
    love.graphics.rectangle("line", game_area_x, game_area_y, var.game_width, var.game_height)
    
    -- Debug info
    love.graphics.print("State: " .. var.State, 10, 70)
end

return draw