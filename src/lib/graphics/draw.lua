draw = {}
oldhand = love.graphics.newImage("gfx/menu/old_hand.png")

-- Render graph (high graphics):
--   prepass (clear scene_canvas)
--   -> world pass under camera transform:
--        forward-lit map + sorted sprites (shadow/Lighting object shader),
--        instanced characters (characterAnimator's own lit shader)
--   -> screen-space passes: neon/god-rays (light), explosion shockwave distortion,
--      JFA global illumination (shader.pass), CRT capture
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
    local lit = shadow.getShader(false)
    love.graphics.setShader(lit)
    -- (the courtyard's grass a touch greener than its sheet's olive)
    love.graphics.setColor(0.84, 1, 0.74, 0.4)
    shadow.drawTiled(lit, function(y0, y1)
        map.map:draw(-11800, 100, 1, y0, y1) -- its first tile at -2000, -2000
    end)
    love.graphics.setColor(1, 1, 1, 0.4)
    regions.drawGround()
    destruction.drawRubble() -- what's been knocked down, lying with the ground

    love.graphics.setColor(1, 1, 1, 1)
    puddle.draw() -- on the ground, under everything that wades through
    shop.drawFloor() -- the shop's floor while you're inside
    

    -- Populate and sort dynamic draw list if neccessary
    
    if var.grass then
        grass.public.draw()
    end
    light.drawBeam() -- the flashlight lighting the floor in front of you
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
    teslaCoil.populate()
    arrows.populate()
    car.populate()
    destruction.populate() -- shards falling off what's been shot
    inventory.populate() -- items on the ground
    blackhole.populate() -- low graphics: a stand-in for its lensing pass
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
    destruction.drawEffects() -- dust from what's hit and what falls

    bullet.draw() -- instanced neon tracers, glowing over the sorted sprites
    enemyWeapons.draw() -- enemies' laser beams and tesla bolts
    trinkets.draw() -- the Mirror Ward round you, the moth, rings of fire
    xp.drawGlow() -- XP globs shining in the dark
    inventory.drawGlow() -- and items on the ground
    suckLight.draw() -- dead enemies' light streaming into the player
    regions.drawGlows() -- halos round lamps, flames and neon


    



    love.graphics.pop() -- back to screen space

    -- Screen-space passes. Order matters: lights -> shockwave -> GI -> CRT.
    -- GI composites into the CRT's capture canvas; the scene and the HUD draw
    -- on top of it there, and the CRT pass then puts all of it on screen.
    if var.graphics_high then
        light.draw()
        explosion.applyShockwave() -- distort scene_canvas before GI processes it
        blackhole.applyLensing() -- the black hole bends it too, and glows into the GI
        blackholeGun.applyLensing() -- and so do the black hole gun's
        -- (straight onto the screen with the CRT filter off)
        shader.pass(crt.enabled() and crtShader:target() or nil)
        -- The scene again over the composite: part of the night look, which
        -- daylight fades out (the composite shows the scene itself by day)
        love.graphics.setColor(1, 1, 1, 1 - daynight.daylight())
        love.graphics.draw(scene_canvas)
        love.graphics.setColor(1, 1, 1, 1)
    else
        blackhole.drawSlowTint() -- slow time, without the lensing pass
    end
    -- sampleScreen.pass() samples gi_canvas into a 1x1 canvas that nothing
    -- reads back yet (see sampleScreen.lua). Run per frame it only cost a
    -- render-target switch mid-frame, which on tile-based GPUs (Apple silicon,
    -- mobile) forces the whole screen to be stored and reloaded for the UI.
    -- Call it again once its result is actually used.

    menu.drawUI() -- ui last, under the CRT like the rest of the picture
    portal.drawUI() -- travel selector and the flash of a jump
    shop.drawUI() -- the shop's prompt and trade panel
    inventory.drawUI() -- the bag, and what was just picked up or used
    car.drawUI() -- the arrow and prompt for getting in the car

    if crt.enabled() then
        crtShader:present()
    end

    -- Dev overlays stay crisp, on top of the CRT
    profiler.drawOverlay()
    command.draw()  -- Draw console on top
    -- editor.debugDraw()

    draw.limitFrame()
end

-- Settings > Frame Cap: wait out the rest of the frame's share of a second.
-- Each frame is due a period after the last was; one that ran late starts the
-- count again from now rather than hurrying the next few to catch up. (The
-- browser paces frames itself.)
local nextFrame = 0
function draw.limitFrame()
    local cap = var.fps_cap or 0
    local now = love.timer.getTime()
    if cap <= 0 or love.system.getOS() == "Web" then
        nextFrame = now
        return
    end
    nextFrame = nextFrame + 1 / cap
    if nextFrame <= now then
        nextFrame = now
    else
        love.timer.sleep(nextFrame - now)
    end
end

--
return draw