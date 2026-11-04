--[[
  The minimap in the top left corner, north up with you in the middle: what
  stands round you (the world's static collision: region buildings, walls,
  towers, lamps and props, the house, arches, trees, shop counters), over a
  region's street plan (regions.lua's r.plan) or the courtyard's grass, and
  the portals, the car and enemies on it.

  It's drawn a texel per minimap pixel into a small canvas at the start of
  the frame (minimap.render, from draw.mydraw: switching to it later, in
  the middle of the frame, would make tile-based GPUs store and reload the
  screen) and scaled up with the rest of the HUD (minimap.draw).
  var.minimap (Settings > Video) turns it off, and var.minimap_size sets how
  big it is: on Auto, a share of the screen's height.
]]
local skin = require("ui.skin")

local minimap = {}

-- Settings > Minimap Size (var.minimap_size): Auto, then a side in GUI units
minimap.SIZES = { 0, 32, 44, 56, 72 }
minimap.SIZE_NAMES = { [0] = "Auto", [32] = "Small", [44] = "Medium", [56] = "Large", [72] = "Huge" }
local AUTO = 0.15              -- Auto: this much of the screen's height
local MIN_SIZE, MAX_SIZE = 32, 96
local SCALE = 20               -- world px per pixel
-- the courtyard's ground (game/courtyard.lua)
local COURTYARD_X0, COURTYARD_Y0, COURTYARD_X1, COURTYARD_Y1 = -2000, -2000, 3760, 2800

local VOID = { 0.05, 0.05, 0.07, 1 }
local GRASS = { 0.14, 0.24, 0.12, 1 }
local STRUCTURE = { 0.80, 0.76, 0.67, 1 }
local GLASS = { 0.45, 0.66, 0.82, 1 }
local PORTAL = { 0.72, 0.42, 1.00, 1 }
local SEALED = { 0.85, 0.22, 0.20, 1 }
local CAR = { 1.00, 0.84, 0.20, 1 }
local ENEMY = { 1.00, 0.25, 0.22, 1 }
local PLAYER = { 1, 1, 1, 1 }

local canvas
local seen = {} -- chains reported once per child edge: drawn once a frame

--- Its side in GUI units (pixels): Settings > Minimap Size, or on Auto a
--- share of the screen's height (in units, so it follows the GUI scale's
--- whole steps and the height between them alike).
function minimap.size()
    local chosen = var.minimap_size or 0
    if chosen > 0 then return chosen end
    local h = love.graphics.getHeight() / skin.guiScale()
    return math.max(MIN_SIZE, math.min(MAX_SIZE, 2 * math.floor(h * AUTO / 2)))
end

--- Whether it's showing this frame.
function minimap.shown()
    return var.minimap and var.State ~= "menu" and player and player.body and true or false
end
local shown = minimap.shown

-- One static fixture, in world px under the minimap's transform. Small ones
-- (a lamp post, a bollard) still get a pixel.
local function drawFixture(f)
    if f:isSensor() or f:getBody():getType() ~= "static" then return true end
    local body, shape = f:getBody(), f:getShape()
    local kind = shape:getType()
    local ud = f:getUserData()
    love.graphics.setColor(type(ud) == "table" and ud.item and ud.item.glass and GLASS or STRUCTURE)
    if kind == "chain" or kind == "edge" then
        if seen[f] then return true end
        seen[f] = true
        for i = 1, kind == "chain" and shape:getChildCount() or 1 do
            local edge = kind == "chain" and shape:getChildEdge(i) or shape
            love.graphics.line(body:getWorldPoints(edge:getPoints()))
        end
        return true
    end
    local ax, ay, bx, by = f:getBoundingBox()
    if bx - ax < 2 * SCALE or by - ay < 2 * SCALE then
        local cx, cy = (ax + bx) / 2, (ay + by) / 2
        local w, h = math.max(bx - ax, SCALE), math.max(by - ay, SCALE)
        love.graphics.rectangle("fill", cx - w / 2, cy - h / 2, w, h)
    elseif kind == "circle" then
        local x, y = body:getWorldPoint(shape:getPoint())
        love.graphics.circle("fill", x, y, shape:getRadius())
    else
        love.graphics.polygon("fill", body:getWorldPoints(shape:getPoints()))
    end
    return true
end

--- Draw the minimap into its canvas, before anything else this frame.
function minimap.render()
    if not shown() then return end
    local size = minimap.size()
    if not canvas or canvas:getWidth() ~= size then
        canvas = love.graphics.newCanvas(size, size)
        canvas:setFilter("nearest", "nearest")
    end
    local half = size / 2
    -- the map moves a whole pixel at a time, so its edges don't shimmer
    local px, py = player.body:getPosition()
    local left, top = math.floor(px / SCALE) - half, math.floor(py / SCALE) - half
    local x0, y0 = left * SCALE, top * SCALE
    local x1, y1 = x0 + size * SCALE, y0 + size * SCALE

    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.origin()
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
    love.graphics.setLineStyle("rough")
    love.graphics.clear(unpack(VOID))

    -- The ground, then what stands on it, in world px
    love.graphics.scale(1 / SCALE)
    love.graphics.translate(-x0, -y0)
    love.graphics.setLineWidth(SCALE)
    if COURTYARD_X0 < x1 and COURTYARD_X1 > x0 and COURTYARD_Y0 < y1 and COURTYARD_Y1 > y0 then
        love.graphics.setColor(GRASS)
        love.graphics.rectangle("fill", COURTYARD_X0, COURTYARD_Y0,
            COURTYARD_X1 - COURTYARD_X0, COURTYARD_Y1 - COURTYARD_Y0)
    end
    love.graphics.setColor(1, 1, 1, 1)
    for _, r in ipairs(regions.list) do
        local plan = r.plan
        if plan then
            local w, h = plan.image:getDimensions()
            if plan.x < x1 and plan.x + w * plan.cell > x0 and plan.y < y1 and plan.y + h * plan.cell > y0 then
                love.graphics.draw(plan.image, plan.x, plan.y, 0, plan.cell, plan.cell)
            end
        end
    end
    for k in pairs(seen) do seen[k] = nil end
    world:queryBoundingBox(x0, y0, x1, y1, drawFixture)

    -- Markers, in minimap pixels; the car's kept on the edge when it's off it
    love.graphics.origin()
    local function at(x, y)
        return math.floor(x / SCALE) - left, math.floor(y / SCALE) - top
    end
    for _, r in ipairs(regions.list) do
        local p = r.portal
        if p then
            local mx, my = at(p.x + 17, p.y + 40)
            love.graphics.setColor(r == regions.list[1] and not bosses.isGateOpen() and SEALED or PORTAL)
            love.graphics.rectangle("fill", mx - 1, my - 1, 3, 3)
        end
    end
    love.graphics.setColor(ENEMY)
    for _, e in ipairs(enemy and enemy.enemies or {}) do
        if not e.dead and e.body and not e.body:isDestroyed() then
            local mx, my = at(e.body:getPosition())
            love.graphics.rectangle("fill", mx, my, 1, 1)
        end
    end
    love.graphics.setColor(CAR)
    for _, c in ipairs(car.cars or {}) do
        if c.body and c ~= car.driving then
            local mx, my = at(c.body:getPosition())
            mx = math.max(0, math.min(size - 2, mx))
            my = math.max(0, math.min(size - 2, my))
            love.graphics.rectangle("fill", mx, my, 2, 2)
        end
    end

    -- You, an arrow the way the flashlight points
    local hx, hy = gun.currentVel.x, gun.currentVel.y
    local cx, cy = half + 0.5, half + 0.5
    love.graphics.setColor(PLAYER)
    love.graphics.polygon("fill",
        cx + hx * 3.5, cy + hy * 3.5,
        cx - hx * 2.5 - hy * 2.5, cy - hy * 2.5 + hx * 2.5,
        cx - hx * 2.5 + hy * 2.5, cy - hy * 2.5 - hx * 2.5)
    love.graphics.pop()
end

--- The minimap with its top left at (x, y) in GUI units (under the HUD's
--- scale; ui/hud.lua frames it).
function minimap.draw(x, y)
    if not (shown() and canvas) then return end
    love.graphics.setColor(1, 1, 1, 0.92)
    love.graphics.draw(canvas, x, y)
end

return minimap
