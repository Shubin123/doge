draw = {}
oldhand = love.graphics.newImage("gfx/menu/old_hand.png")

-- Render graph (high graphics):
--   prepass (clear scene_canvas)
--   -> world pass under camera transform:
--        forward-lit map + sorted sprites (shadow/Lighting object shader),
--        instanced characters (characterAnimator's own lit shader)
--   -> screen-space passes: neon/god-rays (light), explosion shockwave distortion,
--      JFA global illumination (shader.pass), water, CRT capture
--   -> UI / console on top
function draw.mydraw()
    if var.graphics_high then
        shader.prepass()
    end

    love.graphics.push() -- camera space: everything moves with the player

    camera.apply()

    -- Map and sorted sprites are lit in screen space by the Lighting object shader.
    love.graphics.setShader(shadow.getShader(false))
    love.graphics.setColor(1, 1, 1, 0.4)
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
    teslaCoil.populate()
    arrows.populate()
    car.populate()
    princess.x, princess.y = player.body:getX(), player.body:getY()
    characterAnimator.draw() -- instanced, binds its own lit shader
    
    

    if var.graphics_high then
        light.populate()
    end

    gun.drawWorld()

    -- Depth-sort by Y, then draw all dynamic entities under the object shader.
    table.sort(dynamic_draw_list, renderer.sortByRenderY)

    
    love.graphics.setShader(shadow.getShader(true))
    renderer.renderSortedDrawList()

    bullet.draw() -- instanced neon tracers, glowing over the sorted sprites
    suckLight.draw() -- dead enemies' light streaming into the player


    



    love.graphics.pop() -- back to screen space

    -- Screen-space passes. Order matters: lights -> shockwave -> GI -> water -> CRT.
    if var.graphics_high then
        light.draw()
        explosion.applyShockwave() -- distort scene_canvas before GI processes it
        shader.pass()
        water.pass()
        crtShader.endCapture()
    end
    -- sampleScreen.pass() samples gi_canvas into a 1x1 canvas that nothing
    -- reads back yet (see sampleScreen.lua). Run per frame it only cost a
    -- render-target switch mid-frame, which on tile-based GPUs (Apple silicon,
    -- mobile) forces the whole screen to be stored and reloaded for the UI.
    -- Call it again once its result is actually used.

    profiler.drawOverlay()

    menu.drawUI() -- ui last
    command.draw()  -- Draw console on top
    cmdn.draw()     -- Draw improved console on top
    -- editor.debugDraw()
    
end

--
return draw