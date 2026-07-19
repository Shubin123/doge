draw = {}
oldhand = love.graphics.newImage("gfx/menu/old_hand.png")
function draw.mydraw()
    
    -- if var.State == "menu" then
    --     menu.draw()
    --     blur.enable()
    --     --     return
    -- end


    if var.graphics_high then
        shader.prepass()
    end

    love.graphics.push() --push all camera transforms (move everything when player moves)

    
    camera.apply()
    -- if (shadowblock) then
    love.graphics.setShader(shadow.getShader(false))
    -- end
    love.graphics.setColor(1,1,1, 0.4)
    -- Draw map with blood effects
    -- if blood and blood.drawBackground then
    --     -- blood.drawBackground(map.map, game_area_x, game_area_y)
    -- else

    -- end
    
    map.map:draw(-10000, 100, 1)

    love.graphics.setColor(1, 1, 1, 1)
    

    -- Populate and sort dynamic draw list if neccessary
    
    grass.public.draw()
    if var.multiplayer then
        renderer.populateDynamicDrawListNetworked()

        if var.multiplayer == 1 then
            renderer.populateDynamicDrawListNETHOST()
        end
    else
        renderer.populateDynamicDrawList()
    end
    
    bullet.populate()
    explosion.populate()
    rocket.populate()
    blood.populate()
    -- teslaCoil.draw()
    teslaCoil.populate()
    arrows.populate()
    car.populate()
    -- gun_enemy.populate(10,10)
    -- flying_enemy.populate()
    -- princess.populate(player.body:getX() - 50,player.body:getY() - 50, 1, 0)
    princess.x ,princess.y = player.body:getX(),player.body:getY()
    -- fighter.populate(player.body:getX() - 30,player.body:getY() - 50, 1, 0)
    characterAnimator.draw()
    
    

    if var.graphics_high then
        light.populate()
    end

    gun.drawWorld()
    -- characterAnimator.populate(200,200,1,0)

    table.sort(dynamic_draw_list, renderer.sortByRenderY)
    -- Render sorted entities

    
    -- if (shadowblock) then
    love.graphics.setShader(shadow.getShader(true))
    -- end

    renderer.renderSortedDrawList()


    



    love.graphics.pop() -- pop back into base world space
    -- order is IMPORTANT HERE shader-> smoke -> water

    -- explosion.draw()



    if var.graphics_high then
        light.draw()
        explosion.applyShockwave() -- distort scene_canvas before GI processes it
        shader.pass()
        -- smoke.pass()
        water.pass()
        crtShader.endCapture()

        -- blur.pass()
    end
    sampleScreen.pass()

    profiler.drawOverlay()

    menu.drawUI() -- ui last
    command.draw()  -- Draw console on top
    cmdn.draw()     -- Draw improved console on top
    -- editor.debugDraw()
    
end

--
return draw