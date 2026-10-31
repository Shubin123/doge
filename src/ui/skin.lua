-- skin.lua
-- Shared Minecraft-style GUI pieces for the HUD and menus: a whole-number GUI
-- scale, stone buttons and drop-shadowed text. Sizes are GUI units; callers
-- draw under love.graphics.scale(u) so the pixel art stays crisp.

local skin = {}

-- Largest whole scale that fits a 320 x minHeight unit layout, like
-- Minecraft's "auto" GUI scale (minHeight 240).
function skin.guiScale(minHeight)
    local w, h = love.graphics.getDimensions()
    return math.max(1, math.min(math.floor(w / 320), math.floor(h / (minHeight or 240))))
end

-- One font pixel in units: the 16px pixel font then reads like Minecraft's
-- 8-unit text, at a whole number of screen pixels per font pixel.
function skin.textScale(u)
    return math.max(1, math.floor(u / 2)) / u
end

-- Text with Minecraft's drop shadow (the colour at a quarter brightness).
function skin.print(text, x, y, ts, color, alpha)
    alpha = alpha or 1
    love.graphics.setColor(color[1] * 0.25, color[2] * 0.25, color[3] * 0.25, alpha)
    love.graphics.print(text, x + ts, y + ts, 0, ts, ts)
    love.graphics.setColor(color[1], color[2], color[3], alpha)
    love.graphics.print(text, x, y, 0, ts, ts)
end

function skin.printCentered(text, cx, y, ts, color, alpha)
    skin.print(text, cx - love.graphics.getFont():getWidth(text) * ts / 2, y, ts, color, alpha)
end

skin.WHITE = { 0.88, 0.88, 0.88 }
skin.GRAY = { 0.63, 0.63, 0.63 }
skin.HOVER = { 1.00, 1.00, 0.63 }
skin.YELLOW = { 1.00, 1.00, 0.00 }

-- Button faces per state: { fill, highlight (top/left), shadow (bottom/right) }
local FACES = {
    idle = { { 0.44, 0.44, 0.44 }, { 0.66, 0.66, 0.66 }, { 0.30, 0.30, 0.30 } },
    hover = { { 0.49, 0.53, 0.75 }, { 0.70, 0.74, 0.95 }, { 0.34, 0.37, 0.56 } },
    disabled = { { 0.17, 0.17, 0.17 }, { 0.17, 0.17, 0.17 }, { 0.17, 0.17, 0.17 } },
}

local textures = {}

-- A stone button face, generated once per size and state.
local function buttonTexture(w, h, state)
    local key = w .. "x" .. h .. state
    if textures[key] then return textures[key] end

    local fill, light, dark = FACES[state][1], FACES[state][2], FACES[state][3]
    local rng = love.math.newRandomGenerator(7) -- same speckle every time
    local data = love.image.newImageData(w, h)
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local c
            if x == 0 or y == 0 or x == w - 1 or y == h - 1 then
                c = { 0, 0, 0 }
            elseif y == 1 or x == 1 then
                c = light
            elseif y >= h - 3 or x == w - 2 then
                c = dark
            else
                c = fill
            end
            local n = c == fill and (rng:random() - 0.5) * 0.06 or 0
            data:setPixel(x, y, c[1] + n, c[2] + n, c[3] + n, 1)
        end
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    textures[key] = image
    return image
end

-- A button at (x, y) in units. Height defaults to Minecraft's 20.
function skin.button(b, ts, hovered)
    local h = b.h or 20
    local state = not b.enabled and "disabled" or hovered and "hover" or "idle"
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(buttonTexture(b.w, h, state), b.x, b.y)

    local color = not b.enabled and skin.GRAY or hovered and skin.HOVER or skin.WHITE
    local font = love.graphics.getFont()
    skin.printCentered(b.label, b.x + b.w / 2, b.y + (h - font:getHeight() * ts) / 2, ts, color)
end

function skin.contains(b, ux, uy)
    return ux >= b.x and ux < b.x + b.w and uy >= b.y and uy < b.y + (b.h or 20)
end

return skin
