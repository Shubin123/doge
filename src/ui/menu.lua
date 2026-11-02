-- menu.lua
-- Minecraft-style menus over the paused, blurred game: the title screen,
-- settings and save slots. Laid out in GUI units with ui/skin.lua, like the HUD.

local skin = require("ui.skin")

local menu = {}
menu.blur = false
menu.currentMenu = "main" -- "main", "settings", or "saves"

local VERSION = "Doge alpha 0.0.2"
local MIN_HEIGHT = 256 -- GUI units of height the save list needs
local ROW_HEIGHT = 24
local SPLASHES = { "Much light!", "Such ammo!", "Very tesla!", "Wow!", "So pixel!", "Many fireball!" }
local SPLASH_RADII = { 60, 120, 180, 240 } -- Settings > Rocket Splash choices, world px
local GI_QUALITIES = { "high", "medium", "low" } -- Settings > Lighting (shader.qualityPresets)
local TRACER_LEVELS = { 1.0, 0.7, 0.45, 0.25, 0 } -- Settings > Tracers, var.tracer_brightness
local FRAME_CAPS = { 0, 30, 60, 120, 144 } -- Settings > Frame Cap, var.fps_cap (0 none)
local LIGHT_COUNTS = { 64, 48, 32, 16 } -- Settings > Max Lights, var.max_lights
-- The Settings screen's tabs: { id, label }
local TABS = { { "video", "Video" }, { "graphics", "Graphics" }, { "effects", "Effects" } }
local settingsTab = "video"

local font
local ps
local splash

-- Save slots: the console's quicksave, then numbered slots (filled in menu.load)
local slots = {}
local slotInfo = {}   -- serial.getSaveInfo per slot, false when empty
local selected = 2    -- the first numbered slot
local confirming      -- "save" or "delete" while waiting for the second click
local armed           -- what confirming was when the current click came in
local status          -- result of the last save/load/delete

-- Settings > Resolution choices (var.window_width/height). The settings
-- themselves live in var and util/settings.lua keeps them in settings.json.
local RESOLUTIONS = {
    {width = 800, height = 600},
    {width = 1024, height = 768},
    {width = 1280, height = 720},
    {width = 1600, height = 900},
    {width = 1920, height = 1080},
    {width = 2560, height = 1440}
}

local function onOff(value)
    return value and "ON" or "OFF"
end

local function percent(value, max)
    return math.floor(math.max(0, value) / max * 100 + 0.5) .. "%"
end

-- The choice after `value` in `list`, wrapping; the first when it isn't there.
local function nextIn(list, value)
    for i, v in ipairs(list) do
        if v == value then return list[i % #list + 1] end
    end
    return list[1]
end

-- The RESOLUTIONS entry the window is set to; nil for a size that isn't one
local function currentResolution()
    for _, r in ipairs(RESOLUTIONS) do
        if r.width == var.window_width and r.height == var.window_height then return r end
    end
end

function menu.load(screenInfo)
    font = love.graphics.newFont("gfx/menu/Px437_IBM_VGA_8x16.ttf", 16)
    font:setFilter("nearest", "nearest")
    particle = love.graphics.newImage("gfx/doge.png")
    love.graphics.setFont(font)

    ps = love.graphics.newParticleSystem(particle, 1000)
    ps:setParticleLifetime(6, 12)
    ps:setEmissionRate(10)
    ps:setSizes(2)
    ps:setColors({0.5,0.5,0.5,0}, {0.5,0.5,0.5,0.5}, {0.5,0.5,0.5,0})
    ps:setSpeed(50, 100)
    ps:setDirection(math.pi / 2)
    ps:setSpread(0.4)
    ps:setEmissionArea("uniform", screenInfo.screen_width, 1)
    ps:setPosition(screenInfo.screen_width / 2, -50)
    ps:setEmitterLifetime(-1)
    ps:start()

    splash = SPLASHES[love.math.random(#SPLASHES)]
    slots = { { name = "Quicksave", file = serial.QUICKSAVE } }
    for i = 1, 5 do
        slots[#slots + 1] = { name = "Slot " .. i, file = "slot" .. i .. serial.EXTENSION }
    end
end

function menu.update(dt)
    if var.menu_particles then
        ps:update(dt)
    end
end

function menu.open()
    var.State = "menu"
    menu.currentMenu = "main"
    menu.blur = true
    blur.blur_enabled = true
end

function menu.close()
    var.State = "running"
    menu.blur = false
    blur.blur_enabled = false
end

-- Escape backs out of a sub-screen, otherwise opens or closes the menu.
function menu.escape()
    if var.State ~= "menu" then
        menu.open()
    elseif menu.currentMenu ~= "main" then
        menu.currentMenu = "main"
    else
        menu.close()
    end
end

local function refreshSlots()
    for i, slot in ipairs(slots) do
        slotInfo[i] = serial.getSaveInfo(slot.file) or false
    end
end

function menu.openSaves()
    menu.currentMenu = "saves"
    status = nil
    refreshSlots()
end

function menu.saveSelected()
    local slot = slots[selected]
    if slotInfo[selected] and armed ~= "save" then
        confirming = "save"
        return
    end
    local ok, message = serial.saveToFile(slot.file)
    status = ok and ("Saved to " .. slot.name) or message
    refreshSlots()
end

function menu.loadSelected()
    local ok, message = serial.loadFromFile(slots[selected].file)
    if ok then
        menu.close()
    else
        status = message
    end
end

function menu.deleteSelected()
    if armed ~= "delete" then
        confirming = "delete"
        return
    end
    serial.deleteSave(slots[selected].file)
    status = "Deleted " .. slots[selected].name
    refreshSlots()
end

-- Every button on the current screen, in GUI units.
local function layout(uw, uh)
    local cx = math.floor(uw / 2)
    local buttons = {}
    local function add(x, y, w, label, onClick, enabled)
        buttons[#buttons + 1] = { x = x, y = y, w = w, label = label, onClick = onClick, enabled = enabled ~= false }
    end

    if menu.currentMenu == "main" then
        local y = math.floor(uh / 4 + 48)
        add(cx - 100, y, 200, "Resume", menu.close)
        add(cx - 100, y + 24, 200, "New Game", function() return "running" end)
        add(cx - 100, y + 48, 200, "Saves", menu.openSaves)
        add(cx - 100, y + 84, 98, "Settings", function() menu.currentMenu = "settings" end)
        add(cx + 2, y + 84, 98, "Quit Game", function() return "exit" end)

    elseif menu.currentMenu == "settings" then
        local y = math.floor(uh / 6)
        local fancy = var.graphics_high -- the GI, CRT and shockwaves only run on Fancy
        for i, tab in ipairs(TABS) do -- (the open one greyed out)
            add(cx - 155 + (i - 1) * 105, y + 24, 100, tab[2], function() settingsTab = tab[1] end,
                settingsTab ~= tab[1])
        end
        -- The tab's settings, two to a row under the tabs
        local count = 0
        local function setting(label, onClick, enabled)
            add(count % 2 == 0 and cx - 155 or cx + 5, y + 52 + math.floor(count / 2) * 24, 150, label,
                onClick, enabled)
            count = count + 1
        end

        if settingsTab == "video" then
            setting("Resolution: " .. var.window_width .. "x" .. var.window_height, function()
                local r = nextIn(RESOLUTIONS, currentResolution())
                var.window_width, var.window_height = r.width, r.height
                menu.applyWindow()
            end)
            setting("Fullscreen: " .. onOff(var.screen_flags.fullscreen), function()
                var.screen_flags.fullscreen = not var.screen_flags.fullscreen
                menu.applyWindow()
            end)
            setting("V-Sync: " .. onOff(var.screen_flags.vsync), function()
                var.screen_flags.vsync = not var.screen_flags.vsync
                menu.applyWindow()
            end)
            setting("Frame Cap: " .. (var.fps_cap > 0 and var.fps_cap or "OFF"), function()
                var.fps_cap = nextIn(FRAME_CAPS, var.fps_cap)
            end, love.system.getOS() ~= "Web")
            setting("GUI Scale: " .. (var.gui_scale > 0 and var.gui_scale or "Auto"), function()
                -- 1 up to the largest the HUD fits, then back to Auto
                var.gui_scale = var.gui_scale + 1
                if var.gui_scale > skin.maxGuiScale() then var.gui_scale = 0 end
            end)
            setting("Show FPS: " .. onOff(profiler.overlay_visible), function()
                profiler.overlay_visible = not profiler.overlay_visible
                profiler.overlay_detail = 1
            end)

        elseif settingsTab == "graphics" then
            local preset = settings.preset()
            setting("Preset: " .. (preset and preset:gsub("^%l", string.upper) or "Custom"), function()
                settings.applyPreset(nextIn(settings.PRESET_ORDER, preset))
            end)
            setting("Graphics: " .. (fancy and "Fancy" or "Fast"), function()
                var.graphics_high = not var.graphics_high
            end)
            setting("Lighting: " .. (var.gi_quality:gsub("^%l", string.upper)), function()
                var.gi_quality = nextIn(GI_QUALITIES, var.gi_quality)
                shader.load() -- the preset sets the GI canvases' size and the shader's loops
            end, fancy)
            setting("Max Lights: " .. var.max_lights, function()
                var.max_lights = nextIn(LIGHT_COUNTS, var.max_lights)
            end)
            setting("Shadows: " .. onOff(var.light_shadows), function()
                var.light_shadows = not var.light_shadows
            end)
            setting("Normal Maps: " .. onOff(var.normal_maps), function()
                var.normal_maps = not var.normal_maps
            end)
            setting("Grass: " .. onOff(var.grass), function()
                var.grass = not var.grass
            end)
            setting("Puddles: " .. onOff(var.puddles), function()
                var.puddles = not var.puddles
            end)
            setting("Lamp Glows: " .. onOff(var.lamp_glows), function()
                var.lamp_glows = not var.lamp_glows
            end)

        else -- effects
            setting("CRT Filter: " .. onOff(var.crt_filter), function()
                var.crt_filter = not var.crt_filter
            end, fancy)
            setting("Bloom: " .. onOff(var.crt_bloom), function()
                crt.setBloom(not var.crt_bloom)
            end, fancy and var.crt_filter)
            setting("Shockwaves: " .. onOff(var.shockwaves), function()
                var.shockwaves = not var.shockwaves
            end, fancy)
            local tracers = var.tracer_brightness > 0 and percent(var.tracer_brightness, 1) or "OFF"
            setting("Tracers: " .. tracers, function()
                var.tracer_brightness = nextIn(TRACER_LEVELS, var.tracer_brightness)
            end)
            setting("Screen Shake: " .. onOff(var.screen_shake), function()
                var.screen_shake = not var.screen_shake
            end)
            setting("Particles: " .. onOff(var.menu_particles), function()
                var.menu_particles = not var.menu_particles
            end)
            setting("Rocket Splash: " .. var.rocket_splash_radius, function()
                var.rocket_splash_radius = nextIn(SPLASH_RADII, var.rocket_splash_radius)
            end)
        end
        add(cx - 100, y + 192, 200, "Done", function() menu.currentMenu = "main" end)

    elseif menu.currentMenu == "saves" then
        local filled = slotInfo[selected] and true or false
        add(cx - 154, uh - 52, 150, confirming == "save" and "Overwrite?" or "Save Here", menu.saveSelected)
        add(cx + 4, uh - 52, 150, "Load", menu.loadSelected, filled)
        add(cx - 154, uh - 28, 150, confirming == "delete" and "Really Delete?" or "Delete", menu.deleteSelected, filled)
        add(cx + 4, uh - 28, 150, "Back", function() menu.currentMenu = "main" end)
    end
    return buttons
end

--- The current screen's buttons in screen px ({x, y, w, h, label, enabled}),
--- for driving the menu from outside it (tests/gpu/checks/settings.lua).
function menu.buttons()
    local sw, sh = love.graphics.getDimensions()
    local u = skin.guiScale(MIN_HEIGHT)
    local list = {}
    for _, b in ipairs(layout(sw / u, sh / u)) do
        list[#list + 1] = { x = b.x * u, y = b.y * u, w = b.w * u, h = (b.h or 20) * u,
            label = b.label, enabled = b.enabled }
    end
    return list
end

local function slotRows(uw)
    local w = math.min(270, math.floor(uw) - 20)
    local x = math.floor((uw - w) / 2)
    local rows = {}
    for i = 1, #slots do
        rows[i] = { x = x, y = 32 + (i - 1) * ROW_HEIGHT, w = w, h = ROW_HEIGHT }
    end
    return rows
end

local function drawSaves(uw, uh, ts)
    skin.printCentered("Select Save", uw / 2, 12, ts, skin.WHITE)

    -- Darkened list area between separator lines, like Minecraft's world list
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", 0, 28, uw, uh - 96)
    love.graphics.setColor(0.25, 0.25, 0.25, 1)
    love.graphics.rectangle("fill", 0, 27, uw, 1)
    love.graphics.rectangle("fill", 0, uh - 68, uw, 1)
    love.graphics.setColor(0.55, 0.55, 0.55, 1)
    love.graphics.rectangle("fill", 0, 28, uw, 1)
    love.graphics.rectangle("fill", 0, uh - 67, uw, 1)

    for i, row in ipairs(slotRows(uw)) do
        if i == selected then
            love.graphics.setColor(0.5, 0.5, 0.5, 1)
            love.graphics.rectangle("fill", row.x, row.y, row.w, row.h)
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.rectangle("fill", row.x + 1, row.y + 1, row.w - 2, row.h - 2)
        end

        local info = slotInfo[i]
        skin.print(slots[i].name, row.x + 4, row.y + 3, ts, skin.WHITE)
        if info then
            local stamp = info.timestamp > 0 and os.date("%Y-%m-%d %H:%M", info.timestamp) or ""
            skin.print(stamp, row.x + row.w - 4 - font:getWidth(stamp) * ts, row.y + 3, ts, skin.GRAY)
            local details = "Score " .. info.score
            if info.health then details = details .. "  Health " .. percent(info.health, player.maxHealth) end
            if info.ammo then details = details .. "  Light " .. percent(info.ammo, gun.maxAmmo) end
            skin.print(details, row.x + 4, row.y + 13, ts, skin.GRAY)
        else
            skin.print("Empty", row.x + 4, row.y + 13, ts, skin.GRAY)
        end
    end

    if status then
        skin.printCentered(status, uw / 2, uh - 63, ts, skin.WHITE)
    end
end

local function drawTitle(uw, uh, u, ts)
    -- Logo: the font at 5 screen pixels per font pixel, extruded and two-tone
    local title = "DOGE"
    local ls = ts * 5
    local tw, th = font:getWidth(title) * ls, font:getHeight() * ls
    local x, y = math.floor((uw - tw) / 2), 30

    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.print(title, x + 6 * ts, y + 6 * ts, 0, ls, ls)
    love.graphics.setColor(0.42, 0.26, 0.06, 1)
    for d = 4, 1, -1 do
        love.graphics.print(title, x + d * ts, y + d * ts, 0, ls, ls)
    end
    love.graphics.setColor(1.0, 0.78, 0.24, 1)
    love.graphics.print(title, x, y, 0, ls, ls)
    love.graphics.setScissor(x * u, y * u, tw * u, th * 0.48 * u)
    love.graphics.setColor(1.0, 0.92, 0.58, 1)
    love.graphics.print(title, x, y, 0, ls, ls)
    love.graphics.setScissor()

    -- Splash: yellow, tilted, gently pulsing
    local pulse = (1.8 - math.abs(math.sin((love.timer.getTime() % 1) * math.pi * 2)) * 0.1) * ts
    love.graphics.push()
    love.graphics.translate(x + tw - 6, y + th * 0.8)
    love.graphics.rotate(-math.rad(20))
    skin.print(splash, -font:getWidth(splash) * pulse / 2, -font:getHeight() * pulse / 2, pulse, skin.YELLOW)
    love.graphics.pop()

    -- Clear of the corner, which the CRT's bulge mirrors back in
    skin.print(VERSION, 4, uh - 20, ts, skin.WHITE)
end

function menu.draw()
    local sw, sh = love.graphics.getDimensions()
    local u = skin.guiScale(MIN_HEIGHT)
    local ts = skin.textScale(u)
    local uw, uh = sw / u, sh / u
    local mx, my = crt.mouse()
    mx, my = mx / u, my / u

    love.graphics.push()
    love.graphics.origin()
    love.graphics.setColor(0.06, 0.06, 0.06, 0.55)
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    if var.menu_particles then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(ps)
    end

    love.graphics.scale(u)
    if menu.currentMenu == "main" then
        drawTitle(uw, uh, u, ts)
    elseif menu.currentMenu == "settings" then
        skin.printCentered("Settings", uw / 2, 15, ts, skin.WHITE)
    elseif menu.currentMenu == "saves" then
        drawSaves(uw, uh, ts)
    end
    for _, b in ipairs(layout(uw, uh)) do
        skin.button(b, ts, b.enabled and skin.contains(b, mx, my))
    end
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

function menu.drawUI()
    if var.State == "menu" then
        menu.draw()
        local mx, my = crt.mouse()
        love.graphics.draw(oldhand, mx, my, 0, 0.05, 0.05)
        return
    end

    hud.draw()
end

-- Returns "running" to start a new game, "exit" to quit, otherwise nil.
function menu.mousepressed(x, y, button, screenInfo)
    if button ~= 1 then return nil end

    local sw, sh = love.graphics.getDimensions()
    local u = skin.guiScale(MIN_HEIGHT)
    local ux, uy = x / u, y / u
    -- A confirm only holds for the very next click
    armed, confirming = confirming, nil

    if menu.currentMenu == "saves" then
        for i, row in ipairs(slotRows(sw / u)) do
            if skin.contains(row, ux, uy) then
                selected = i
                return nil
            end
        end
    end

    local onSettings = menu.currentMenu == "settings"
    for _, b in ipairs(layout(sw / u, sh / u)) do
        if b.enabled and skin.contains(b, ux, uy) then
            local result = b.onClick()
            if onSettings then
                settings.save() -- every change, straight away, to settings.json
            end
            return result
        end
    end
    return nil
end

-- Settings > Resolution / Fullscreen / V-Sync: the window in the mode they say
function menu.applyWindow()
    love.window.setMode(var.window_width, var.window_height, var.screen_flags)
    love.resize(love.graphics.getDimensions())
    print("Window: " .. var.window_width .. "x" .. var.window_height
        .. (var.screen_flags.fullscreen and ", fullscreen" or ""))
end

return menu
