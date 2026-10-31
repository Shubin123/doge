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
    -- love.window.setMode (fullscreen and resolution changes) doesn't always
    -- deliver love.resize, which would leave the screen-sized canvases at the
    -- old size and the picture covering only part of the window.
    local sw, sh = love.graphics.getDimensions()
    if scene_canvas and (scene_canvas:getWidth() ~= sw or scene_canvas:getHeight() ~= sh) then
        love.resize(sw, sh)
    end

    if var.graphics_high then
        shader.prepass()
    end

    love.graphics.push() -- camera space: everything moves with the player

    camera.apply()

    -- Map and sorted sprites are lit in screen space by the Lighting object shader.
    love.graphics.setShader(shadow.getShader(false))
    love.graphics.setColor(1, 1, 1, 0.4)
    map.map:draw(-10000, 100, 1)
    regions.drawGround()

    love.graphics.setColor(1, 1, 1, 1)
    puddle.draw() -- on the ground, under everything that wades through
    

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
    characterAnimator.draw() -- uploads instances + death light; sprites draw in the sorted pass below
    
    

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
    regions.drawGlows() -- halos round lamps, flames and neon


    



    love.graphics.pop() -- back to screen space

    -- Screen-space passes. Order matters: lights -> shockwave -> GI -> water -> CRT.
    -- GI composites into the CRT's capture canvas; water and the HUD draw on
    -- top of it there, and the CRT pass then puts all of it on screen.
    if var.graphics_high then
        light.draw()
        explosion.applyShockwave() -- distort scene_canvas before GI processes it
        shader.pass(crtShader:target())
        water.pass()
    end
    -- sampleScreen.pass() samples gi_canvas into a 1x1 canvas that nothing
    -- reads back yet (see sampleScreen.lua). Run per frame it only cost a
    -- render-target switch mid-frame, which on tile-based GPUs (Apple silicon,
    -- mobile) forces the whole screen to be stored and reloaded for the UI.
    -- Call it again once its result is actually used.

    menu.drawUI() -- ui last, under the CRT like the rest of the picture
    portal.drawUI() -- travel selector and the flash of a jump

    if var.graphics_high then
        crtShader:present()
    end

    -- Dev overlays stay crisp, on top of the CRT
    profiler.drawOverlay()
    command.draw()  -- Draw console on top
    cmdn.draw()     -- Draw improved console on top
    -- editor.debugDraw()
    
end

--
return draw