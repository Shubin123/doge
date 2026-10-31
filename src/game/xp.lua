--[[
  XP globs: what used to be coins. They lie about the map (coin_bods, one
  physics body each, group collision.groups.coin), bob and pulse lime to
  yellow, glow in the dark, and drift to the player once they're close.
  Walking into one adds its value to var.player_score, which fills the HUD's
  XP bar (see collision.lua's player/coin response). Globs that touch merge,
  the bigger one growing and carrying both values.
]]
local xp = {}

local MAGNET_RANGE = 96  -- px: globs this close drift to the player
local MAGNET_SPEED = 260 -- px/s at the player, slower further out
local GLOB_PX = 16       -- texture size; a fresh glob (size 0.5) draws at this

-- Minecraft-style pulse between these two
local LIME = { 0.55, 1.00, 0.20 }
local YELLOW = { 1.00, 0.95, 0.30 }

local globImage, haloImage, haloBatch
local pulled = setmetatable({}, { __mode = "k" }) -- bodies the player is drawing in

-- A round pixel-art glob in greys (tinted by the pulse colour), lit from the
-- top left, with a bright highlight and a dark rim.
local function newGlobImage()
    local n = GLOB_PX
    local data = love.image.newImageData(n, n)
    local c = (n - 1) / 2
    for y = 0, n - 1 do
        for x = 0, n - 1 do
            local dx, dy = (x - c) / (n / 2), (y - c) / (n / 2)
            local d = math.sqrt(dx * dx + dy * dy)
            if d <= 0.95 then
                local nz = math.sqrt(math.max(0, 1 - d * d))
                local shade = math.max(0, (-dx * 0.5 - dy * 0.6 + nz * 0.65))
                local v = 0.45 + 0.5 * shade
                if d > 0.78 then
                    v = v * 0.55 -- rim
                end
                local hx, hy = dx + 0.32, dy + 0.36
                if hx * hx + hy * hy < 0.05 then
                    v = 1 -- highlight: the pulse colour at full strength
                end
                data:setPixel(x, y, v, v, v * 0.9, 1)
            end
        end
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    return image
end

-- A soft spot, its strength in rgb and alpha 0: drawn with ("add",
-- "premultiplied") it brightens what's under it and leaves the scene's alpha
-- (what the GI pass reads as walls) alone.
local function newHaloImage()
    local n = 32
    local data = love.image.newImageData(n, n)
    for y = 0, n - 1 do
        for x = 0, n - 1 do
            local d = math.min(1, math.sqrt((x + 0.5 - n / 2) ^ 2 + (y + 0.5 - n / 2) ^ 2) / (n / 2))
            local f = (1 - d) ^ 2
            data:setPixel(x, y, f, f, f, 0)
        end
    end
    return love.graphics.newImage(data)
end

function xp.load()
    globImage = newGlobImage()
    haloImage = newHaloImage()
    haloBatch = love.graphics.newSpriteBatch(haloImage, 512, "stream")
    xp.time = 0
end

-- A glob's pulse colour and bob for its phase
local function look(phase)
    local k = 0.5 + 0.5 * math.sin(xp.time * 4 + phase)
    return LIME[1] + (YELLOW[1] - LIME[1]) * k,
        LIME[2] + (YELLOW[2] - LIME[2]) * k,
        LIME[3] + (YELLOW[3] - LIME[3]) * k,
        math.floor(math.sin(xp.time * 3 + phase * 1.7) * 1.5 + 0.5)
end

-- Every glob drifts toward the player once it's in range, faster the closer
-- it gets, so it slides in and is picked up. While it flies in it's a sensor:
-- it still gets picked up on contact, but doesn't shove the player (or
-- anything in the way).
function xp.update(dt)
    xp.time = xp.time + dt
    if not (player and player.body) then return end
    local px, py = player.body:getPosition()
    for i = 1, #coin_bods do
        local body = coin_bods[i]
        local x, y = body:getPosition()
        local dx, dy = px - x, py - y
        if math.abs(dx) < MAGNET_RANGE and math.abs(dy) < MAGNET_RANGE then
            local d = math.sqrt(dx * dx + dy * dy)
            if d < MAGNET_RANGE and d > 1 then
                local speed = MAGNET_SPEED * (1 - d / MAGNET_RANGE * 0.7)
                body:setLinearVelocity(dx / d * speed, dy / d * speed)
                if not pulled[body] then
                    body:getFixtures()[1]:setSensor(true)
                    pulled[body] = true
                end
            end
        elseif pulled[body] then
            body:setLinearVelocity(0, 0) -- you got away: it settles where it is
            body:getFixtures()[1]:setSensor(false)
            pulled[body] = nil
        end
    end
end

-- Draw-list entry for a glob at (x, y); `size` 0.5 is a fresh one, merged
-- globs are bigger. `phase` staggers the pulse and bob between globs.
local function addGlob(x, y, size, phase, kind)
    local r, g, b, bob = look(phase)
    local scale = size * 2
    dynamic_draw_list[#dynamic_draw_list + 1] = {
        sort_y = y + 100,
        image_or_particles = globImage,
        x = x,
        y = y + bob,
        rotation = 0,
        scale_x = scale,
        scale_y = scale,
        offset_x = GLOB_PX / 2,
        offset_y = GLOB_PX / 2,
        color = { r, g, b, 1 },
        blend_mode = { "alpha" },
        source_object_type = kind
    }
end

--- Add the globs (this host's physics bodies) to the dynamic draw list.
function xp.populate()
    for i = 1, #coin_bods do
        local body = coin_bods[i]
        local x, y = body:getPosition()
        local data = body:getFixtures()[1]:getUserData()
        addGlob(x, y, data and data.size or 0.5, (x * 0.37 + y * 0.11) % 6.283, "xp_glob")
    end
end

--- Host: every glob for the snapshot, flat to keep it small:
--- { x1, y1, size1 * 100, x2, ... } in whole px.
function xp.getNetworkData()
    local flat = {}
    for i = 1, #coin_bods do
        local body = coin_bods[i]
        local x, y = body:getPosition()
        local data = body:getFixtures()[1]:getUserData()
        local n = #flat
        flat[n + 1] = math.floor(x + 0.5)
        flat[n + 2] = math.floor(y + 0.5)
        flat[n + 3] = math.floor((data and data.size or 0.5) * 100 + 0.5)
    end
    return flat
end

--- Client: add the host's globs (xp.getNetworkData) to the draw list.
function xp.populateNetworked(flat)
    for i = 1, #flat - 2, 3 do
        local x, y = flat[i], flat[i + 1]
        addGlob(x, y, flat[i + 2] / 100, (x * 0.37 + y * 0.11) % 6.283, "networked_xp_glob")
    end
end

--- A glow round each glob on screen, over the sorted sprites (under the
--- camera transform), so they shine in the dark.
function xp.drawGlow()
    if #coin_bods == 0 then return end
    local x0, y0, x1, y1 = regions.view(40)
    haloBatch:clear()
    for i = 1, #coin_bods do
        local body = coin_bods[i]
        local x, y = body:getPosition()
        if x > x0 and x < x1 and y > y0 and y < y1 then
            local data = body:getFixtures()[1]:getUserData()
            local radius = (data and data.size or 0.5) * 36
            local r, g, b = look((x * 0.37 + y * 0.11) % 6.283)
            local k = 0.35 * daynight.glow()
            haloBatch:setColor(r * k, g * k, b * k, 1)
            haloBatch:add(x - radius, y - radius, 0, radius * 2 / 32, radius * 2 / 32)
            if haloBatch:getCount() >= haloBatch:getBufferSize() then break end
        end
    end
    if haloBatch:getCount() == 0 then return end
    local shader = love.graphics.getShader()
    local mode, alphaMode = love.graphics.getBlendMode()
    love.graphics.setShader()
    love.graphics.setBlendMode("add", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(haloBatch)
    love.graphics.setBlendMode(mode, alphaMode)
    love.graphics.setShader(shader)
end

return xp
