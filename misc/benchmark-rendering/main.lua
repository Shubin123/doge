-- =============================================================================
-- Benchmark: Draw List Performance
-- Tests table.sort + table.insert at various list sizes
-- Run: love ./misc/benchmark-rendering
-- =============================================================================

local results = {}

local function json_encode(tbl)
    if type(tbl) == "table" then
        local parts = {}
        if #tbl > 0 then
            for _, v in ipairs(tbl) do
                table.insert(parts, json_encode(v))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            for k, v in pairs(tbl) do
                table.insert(parts, string.format("%s:%s", json_encode(k), json_encode(v)))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    elseif type(tbl) == "string" then
        return string.format("%q", tbl)
    elseif type(tbl) == "number" then
        return string.format("%.6f", tbl)
    else
        return tostring(tbl)
    end
end

local function createDrawEntry()
    return {
        sort_y = math.random(0, 600),
        source_object_type = "benchmark",
        image_or_particles = nil,
        x = math.random(0, 800),
        y = math.random(0, 600),
        rotation = 0,
        scale_x = 1,
        scale_y = 1,
        offset_x = 0,
        offset_y = 0,
        color = {1, 1, 1, 1},
        blend_mode = {"alpha"},
        quad = nil,
    }
end

function love.load()
    love.window.setMode(800, 600)
    print("=== Draw List Performance Benchmark ===\n")

    local sizes = {50, 100, 200, 500, 1000}
    local iterations = 20 -- multiple passes for stable measurement

    for _, size in ipairs(sizes) do
        print("Testing draw list size: " .. size)

        -- Build test data
        local list = {}
        for i = 1, size do
            table.insert(list, createDrawEntry())
        end

        -- Benchmark: full populate cycle (clear + insert + sort)
        local populate_times = {}
        for _ = 1, iterations do
            local t1 = love.timer.getTime()

            -- Simulate populate: clear and rebuild
            local test_list = {}
            for i = 1, size do
                table.insert(test_list, createDrawEntry())
            end
            table.sort(test_list, function(a, b) return a.sort_y < b.sort_y end)

            -- Simulate render loop iteration
            for _, entry in ipairs(test_list) do
                local _ = entry.x + entry.y
            end

            local t2 = love.timer.getTime()
            table.insert(populate_times, (t2 - t1) * 1000)
        end

        -- Calculate stats
        table.sort(populate_times)
        local avg = 0
        for _, t in ipairs(populate_times) do avg = avg + t end
        avg = avg / #populate_times
        local p50 = populate_times[math.max(1, math.floor(#populate_times * 0.50))]
        local p99 = populate_times[math.max(1, math.floor(#populate_times * 0.99))]

        print(string.format("  Avg: %.3fms  P50: %.3fms  P99: %.3fms", avg, p50, p99))

        table.insert(results, {
            list_size = size,
            avg_ms = math.floor(avg * 1000) / 1000,
            p50_ms = math.floor(p50 * 1000) / 1000,
            p99_ms = math.floor(p99 * 1000) / 1000,
        })

        list = nil
        collectgarbage("collect")
    end

    -- Summary
    print("\n=== Results Summary ===")
    print(string.format("%-12s %10s %10s %10s", "List Size", "Avg(ms)", "P50(ms)", "P99(ms)"))
    print(string.rep("-", 45))
    for _, r in ipairs(results) do
        print(string.format("%-12d %10.3f %10.3f %10.3f", r.list_size, r.avg_ms, r.p50_ms, r.p99_ms))
    end

    local f = io.open("benchmark_rendering.json", "w")
    if f then
        f:write(json_encode(results))
        f:close()
        print("\nExported to benchmark_rendering.json")
    end

    print("Done.")
    love.event.quit()
end

function love.update(dt) end
function love.draw()
    love.graphics.setColor(0.1, 0.1, 0.2)
    love.graphics.rectangle("fill", 0, 0, 800, 600)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Draw List Benchmark Running...", 10, 10)
end
