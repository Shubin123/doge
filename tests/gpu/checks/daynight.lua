--[[
  Day and night (systems/daynight.lua), in the running game:

      python3 tests/gpu/run.py --checks

  1. the clock runs: a day takes var.day_length seconds of game time;
  2. midnight is dark (the old night look's ambient 0.2), noon full daylight,
     dusk in between;
  3. a frame at noon is brighter than one at midnight;
  4. the shop keeps day hours.
]]
return function(h)
    player.god = true
    h.advance(5)

    daynight.setHour(10)
    h.advance(60)
    local expected = 10 + 60 * h.dt * 24 / var.day_length
    h.check("the clock runs a day per var.day_length", math.abs(daynight.hour - expected) < 1e-3,
        string.format("%.4f h, expected %.4f", daynight.hour, expected))

    daynight.setHour(0)
    h.advance(1)
    h.check("midnight is night", daynight.daylight() == 0 and math.abs(shadow.ambient - 0.2) < 1e-6,
        string.format("daylight %.2f, ambient %.2f", daynight.daylight(), shadow.ambient))
    daynight.setHour(12)
    h.advance(1)
    h.check("noon is full day", daynight.daylight() == 1 and math.abs(shadow.ambient - daynight.DAY_AMBIENT) < 1e-6,
        string.format("daylight %.2f, ambient %.2f", daynight.daylight(), shadow.ambient))
    local dusk = daynight.daylight(19)
    h.check("dusk is in between", dusk > 0 and dusk < 1, string.format("daylight at 19:00 %.2f", dusk))

    -- How bright a whole frame is, at a given hour (read from the canvas the
    -- frame is composed in before the CRT pass puts it on screen)
    local function brightness(hour)
        daynight.setHour(hour)
        h.advance(2)
        local data = crtShader:target():newImageData()
        local W, H = data:getDimensions()
        local sum, n = 0, 0
        for y = 0, H - 1, 8 do
            for x = 0, W - 1, 8 do
                local r, g, b = data:getPixel(x, y)
                sum, n = sum + 0.299 * r + 0.587 * g + 0.114 * b, n + 1
            end
        end
        return sum / n
    end
    local night, noon = brightness(0), brightness(12)
    h.check("a noon frame is brighter than a midnight one", noon > night * 1.2,
        string.format("mean brightness %.3f at midnight, %.3f at noon", night, noon))

    h.check("the shop keeps day hours",
        daynight.isOpen(12) and daynight.isOpen(7) and not daynight.isOpen(19) and not daynight.isOpen(2))
    daynight.setHour(var.day_start)
end
