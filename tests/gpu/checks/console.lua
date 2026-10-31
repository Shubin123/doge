--[[
  The console (ui/command.lua), driven through the game's own input
  callbacks:

      python3 tests/gpu/run.py --checks

  1. "/" and "," open it, and the key that opened it isn't typed;
  2. once it's open "/" and "," type like any other key, so Lua runs as typed;
  3. while it's open, game keys ("z" zoom, Escape's menu) don't fire;
  4. console commands still run (tp);
  5. Escape closes it, and the menu stays shut.
]]
return function(h)
    local function press(key, text)
        love.keypressed(key)
        if text then love.textinput(text) end
    end
    local function typeText(s)
        for c in s:gmatch(".") do press(c == " " and "space" or c, c) end
    end

    h.advance(5)

    press("/", "/")
    h.check("/ opens it", command.isOpen())
    local zoom = camera.zoom
    typeText("console_check = select('#', 'z', 2) / 2")
    press("return")
    h.advance(1)
    h.check("/ and , type once open, the line runs as Lua", console_check == 1,
        "console_check = " .. tostring(console_check))
    h.check("z doesn't zoom while typing", camera.zoom == zoom)

    typeText("tp 123 456")
    press("return")
    local x, y = player.body:getPosition()
    h.check("tp moves the player", math.abs(x - 123) < 1e-3 and math.abs(y - 456) < 1e-3,
        string.format("player at %.1f, %.1f", x, y))

    local state = var.State
    press("escape")
    h.check("Escape closes it", not command.isOpen())
    h.check("Escape doesn't also open the menu", var.State == state, tostring(var.State))

    press(",", ",")
    h.check(", opens it", command.isOpen())
    press("escape")
    h.advance(2)
end
