--[[
  The Settings screen's tabs and the graphics settings behind them
  (ui/menu.lua, util/settings.lua):

      python3 tests/gpu/run.py --checks --only settings

  1. each tab's buttons fit on screen without overlapping, and clicking a
     tab opens it;
  2. Preset cycles Low / Medium / High and sets every Graphics setting to it,
     and changing one of them shows Custom;
  3. a frame renders with every new setting off (and on again), and Max
     Lights caps the lights shaded;
  4. the new settings round-trip through settings.json;
  5. the frame cap sleeps out the rest of a short frame and not a long one.

  Leaves a screenshot of each tab and of a Low and a High frame in
  dist/gpu-test/checks-settings/.
]]
return function(h)
    player.god = true
    h.advance(5)

    local function find(label)
        for _, b in ipairs(menu.buttons()) do
            if b.label:find(label, 1, true) == 1 then return b end
        end
    end
    local function click(label)
        local b = find(label)
        if not b then return false end
        menu.mousepressed(b.x + b.w / 2, b.y + b.h / 2, 1, var.ScreenInfo)
        return true
    end
    local function labels()
        local t = {}
        for _, b in ipairs(menu.buttons()) do t[#t + 1] = b.label end
        return table.concat(t, " | ")
    end

    menu.open()
    h.check("Settings opens from the title screen", click("Settings") and menu.currentMenu == "settings")

    local sw, sh = love.graphics.getDimensions()
    for _, tab in ipairs({ "Video", "Graphics", "Effects" }) do
        h.check(tab .. " tab opens", click(tab) and find(tab) and not find(tab).enabled, labels())
        local list, fits, apart = menu.buttons(), true, true
        for i, a in ipairs(list) do
            if a.x < 0 or a.y < 0 or a.x + a.w > sw or a.y + a.h > sh then fits = false end
            for j = i + 1, #list do
                local b = list[j]
                if a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h then
                    apart = false
                end
            end
        end
        h.check(tab .. ": every button on screen, none overlapping", fits and apart, labels())
        h.capture("settings-" .. tab:lower())
    end

    click("Graphics")
    h.check("defaults are the High preset", settings.preset() == "high", labels())
    local giWidth = shader.gi_w
    click("Preset")
    h.check("Preset: High -> Low", settings.preset() == "low" and find("Preset: Low") ~= nil, labels())
    local low = true
    for key, value in pairs(settings.PRESETS.low) do
        if var[key] ~= value then low = false end
    end
    h.check("Low sets every Graphics setting", low)
    h.check("and the GI canvases follow its quality", shader.gi_w < giWidth,
        string.format("%d px wide, %d before", shader.gi_w, giWidth))
    click("Preset")
    h.check("Low -> Medium", settings.preset() == "medium")
    click("Normal Maps")
    h.check("changing one shows Custom", settings.preset() == nil and find("Preset: Custom") ~= nil, labels())
    click("Preset")
    click("Preset")
    click("Preset")
    h.check("and Preset cycles back round to High", settings.preset() == "high", labels())

    -- Frames with every new setting off, then on
    menu.close()
    for i = 1, 6 do enemy.addEnemy(player.body:getX() + 40 * i, player.body:getY() + 60) end
    for _, r in ipairs(regions.list) do
        if r.id == "neon" then regions.teleport(r) end -- lamps, neon, puddles, facades
    end
    player.lightsOn = true
    h.advance(3)
    local lightsHigh = shadow.shown
    h.capture("frame-high")

    settings.applyPreset("low")
    var.max_lights = 4
    var.shockwaves = false
    explosion.create(player.body:getX() + 80, player.body:getY(), explosion.TYPES.ROCKET)
    local ok, err = pcall(h.advance, 3)
    h.check("a frame renders with them all off", ok, err)
    h.check("Max Lights caps the lights shaded", shadow.shown <= 4,
        string.format("%d lights (%d at 64)", shadow.shown, lightsHigh))
    h.capture("frame-low")

    settings.applyPreset("high")
    var.shockwaves = true
    explosion.create(player.body:getX() + 80, player.body:getY(), explosion.TYPES.ROCKET)
    ok, err = pcall(h.advance, 3)
    h.check("and with them all on again", ok, err)

    -- settings.json
    var.fps_cap, var.gui_scale, var.max_lights = 60, 1, 32
    var.light_shadows, var.normal_maps, var.puddles, var.lamp_glows, var.shockwaves = false, false, false, false, false
    settings.save()
    var.fps_cap, var.gui_scale, var.max_lights = 0, 0, 64
    var.light_shadows, var.normal_maps, var.puddles, var.lamp_glows, var.shockwaves = true, true, true, true, true
    settings.load()
    h.check("the new settings come back from settings.json",
        var.fps_cap == 60 and var.gui_scale == 1 and var.max_lights == 32 and not var.light_shadows
        and not var.normal_maps and not var.puddles and not var.lamp_glows and not var.shockwaves)
    love.filesystem.remove(settings.FILE)
    h.check("GUI Scale 1 draws the HUD at 1", require("ui.skin").guiScale() == 1)
    var.fps_cap, var.gui_scale = 0, 0
    settings.applyPreset("high")
    var.shockwaves = true

    -- The frame cap, on a clock it controls
    local getTime, sleep = love.timer.getTime, love.timer.sleep
    local now, slept = 100, 0
    love.timer.getTime = function() return now end
    love.timer.sleep = function(s) slept = slept + s; now = now + s end
    var.fps_cap = 60
    draw.limitFrame() -- starts the count
    slept = 0
    now = now + 0.005
    draw.limitFrame()
    local short = slept
    slept = 0
    now = now + 0.040
    draw.limitFrame()
    local long = slept
    var.fps_cap = 0
    love.timer.getTime, love.timer.sleep = getTime, sleep
    h.check("Frame Cap 60 sleeps out a 5 ms frame", math.abs(short - (1 / 60 - 0.005)) < 1e-6,
        string.format("slept %.2f ms", short * 1000))
    h.check("and not a 40 ms one", long == 0, string.format("slept %.2f ms", long * 1000))
end
