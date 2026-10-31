--[[
  Day and night: a 24-hour clock (daynight.hour) running on game time, so the
  black hole slows it too. One day takes var.day_length seconds; the game
  starts at var.day_start.

  Night is the game's old look: the lit shaders' ambient floor at 0.2, so
  only lights (the player's, the flashlight, lamps, glows) show anything.
  Day raises that floor to full (lighting.ambient, which every lit shader
  reads) and switches the final composite (shader.pass) from scene + GI to
  the scene's own colours under a sky tint, warm and orange at dawn and
  dusk. daynight.daylight() goes 0 (night) to 1 (day): up from 05:00 to
  07:00, down from 18:00 to 20:00.

  The shop (game/shop.lua) trades from 07:00 to 19:00: daynight.isOpen().
]]
local daynight = {}

daynight.hour = 8

local DAWN, DAY, DUSK, NIGHT = 5, 7, 18, 20 -- daylight rises DAWN..DAY, sets DUSK..NIGHT
local OPEN, CLOSE = 7, 19                     -- shop hours

local NOON_TINT = { 1.00, 0.98, 0.93 }
local GOLDEN_TINT = { 1.00, 0.70, 0.48 }

function daynight.load()
    daynight.hour = var.day_start or 8
end

function daynight.update(dt)
    daynight.hour = (daynight.hour + dt * 24 / (var.day_length or 480)) % 24
end

local function smooth(k)
    k = math.max(0, math.min(1, k))
    return k * k * (3 - 2 * k)
end

--- 0 at night, 1 by day, easing between at dawn and dusk.
function daynight.daylight(hour)
    local h = hour or daynight.hour
    if h < DAWN or h >= NIGHT then return 0 end
    if h < DAY then return smooth((h - DAWN) / (DAY - DAWN)) end
    if h < DUSK then return 1 end
    return 1 - smooth((h - DUSK) / (NIGHT - DUSK))
end

--- The sky's colour on everything: neutral at noon, golden near sunrise
--- (06:00) and sunset (19:00).
function daynight.tint(hour)
    local h = hour or daynight.hour
    local golden = math.max(0, 1 - math.abs(h - 6.2) / 1.8, 1 - math.abs(h - 18.8) / 1.8)
    golden = smooth(golden)
    return {
        NOON_TINT[1] + (GOLDEN_TINT[1] - NOON_TINT[1]) * golden,
        NOON_TINT[2] + (GOLDEN_TINT[2] - NOON_TINT[2]) * golden,
        NOON_TINT[3] + (GOLDEN_TINT[3] - NOON_TINT[3]) * golden,
    }
end

--- Whether the shop trades now.
function daynight.isOpen(hour)
    local h = hour or daynight.hour
    return h >= OPEN and h < CLOSE
end

function daynight.opensAt()
    return OPEN
end

--- "08:30"
function daynight.clockText(hour)
    local h = hour or daynight.hour
    local minutes = math.floor(h * 60) % (24 * 60)
    return string.format("%02d:%02d", math.floor(minutes / 60), minutes % 60)
end

--- Set the lighting for this hour. Before the lighting upload.
function daynight.apply()
    shadow.ambient = 0.20 + 0.80 * daynight.daylight()
end

function daynight.setHour(hour)
    daynight.hour = hour % 24
end

return daynight
