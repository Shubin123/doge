local config = {
    base_x = 400,
    base_y = 300,
    coil_height = 10,
    spark_count = 10,
    spark_range = 10,
    bolt_segments = 10,
    bolt_deviation = 50,
    animation_speed = 1,
    colors = {
        spark = {1, 1, 1}
    }
}

local state = {
    bolts = {},
    time = 0
}

-- Generate a Collatz sequence
local function collatz(n)
    local seq = {}
    while n ~= 1 do
        table.insert(seq, n)
        if n % 2 == 0 then n = n / 2 else n = 3 * n + 1 end
    end
    table.insert(seq, 1)
    return seq
end

-- Create jagged bolt segments
local function generateBolt(x1, y1, x2, y2, collatz_val)
    local segments = {}
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)

    for i = 0, config.bolt_segments do
        local t = i / config.bolt_segments
        local base_x = x1 + dx * t
        local base_y = y1 + dy * t

        local dev_factor = (1 - math.abs(t - 0.5) * 2) -- stronger in the middle
        local angle = math.pi * 2 * ((collatz_val % 360) / 360)
        local offset_x = math.cos(angle + i) * config.bolt_deviation * dev_factor * (math.random() - 0.5)
        local offset_y = math.sin(angle + i) * config.bolt_deviation * dev_factor * (math.random() - 0.5)

        table.insert(segments, {x = base_x + offset_x, y = base_y + offset_y})
    end

    return segments
end

-- Bresenham line plot
local function drawPixelLine(x0, y0, x1, y1, pixel_size)
    pixel_size = pixel_size or 2 -- Default size of 2 pixels

    x0 = math.floor(x0 + 0.5)
    y0 = math.floor(y0 + 0.5)
    x1 = math.floor(x1 + 0.5)
    y1 = math.floor(y1 + 0.5)

    local dx = math.abs(x1 - x0)
    local dy = -math.abs(y1 - y0)
    local sx = x0 < x1 and 1 or -1
    local sy = y0 < y1 and 1 or -1
    local err = dx + dy

    while true do
        -- Draw a square "pixel"
        love.graphics.rectangle("fill", x0 - pixel_size / 2, y0 - pixel_size / 2, pixel_size, pixel_size)

        if x0 == x1 and y0 == y1 then break end
        local e2 = 2 * err
        if e2 >= dy then err = err + dy; x0 = x0 + sx end
        if e2 <= dx then err = err + dx; y0 = y0 + sy end
    end
end

local t = 0
-- Draw bolts
local function drawBolts()
    love.graphics.setColor(config.colors.spark[1], config.colors.spark[2], config.colors.spark[3])
    love.graphics.setPointSize(1)
    t = t + 0.1
    for _, bolt in ipairs(state.bolts) do
        for i = 1, #bolt - 1 do
            drawPixelLine(bolt[i].x, bolt[i].y, bolt[i + 1].x, bolt[i + 1].y, (math.sin(t) + 2)*2)
        end
    end
end

-- Create new bolts
local function fireAt(x, y)
    state.bolts = {}
    local sx, sy = config.base_x, config.base_y - config.coil_height

    for i = 1, config.spark_count do
        local start_num = 3 + i * 2
        local seq = collatz(start_num)
        local seq_pos = (i % #seq) + 1
        local val = seq[seq_pos]

        local angle = (val % 360) * (math.pi / 180)
        local dist = config.spark_range + (val % 10)
        local tx = x + math.cos(angle) * dist
        local ty = y + math.sin(angle) * dist

        local bolt = generateBolt(sx, sy, tx, ty, val)
        table.insert(state.bolts, bolt)
    end
end

-- LÖVE callbacks
function love.load()
    love.window.setTitle("Pixelated Tesla Coil")
    love.graphics.setBackgroundColor(0, 0, 0)
    love.graphics.setDefaultFilter("nearest", "nearest")
    math.randomseed(os.time())
end

function love.update(dt)
    state.time = state.time + dt
    fireAt(love.mouse.getPosition())
end

function love.draw()
    drawBolts()

    -- Draw the coil base
    love.graphics.setColor(0.5, 1, 1)
    love.graphics.rectangle("fill", config.base_x - 3, config.base_y - config.coil_height, 6, config.coil_height)

    love.graphics.setColor(1, 1, 0.2)
    love.graphics.print("Click to fire pixel arc", 10, 10)
end

function love.mousepressed(x, y, button)
    if button == 1 then
        fireAt(x, y)
    end
end
