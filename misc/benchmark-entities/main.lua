-- =============================================================================
-- Benchmark: Entity Count Scaling
-- Tests FPS with 10, 50, 100, 200, 500 simulated entities
-- Run: love ./misc/benchmark-entities
-- =============================================================================

local results = {}

-- Minimal JSON encoder (avoids requiring src/util/json.lua)
local function json_encode(tbl)
    if type(tbl) == "table" then
        local parts = {}
        local is_array = #tbl > 0
        if is_array then
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

local function spawnEntities(count)
    local entities = {}
    for i = 1, count do
        table.insert(entities, {
            x = math.random(0, 800),
            y = math.random(0, 600),
            vx = math.random(-100, 100) * 0.01,
            vy = math.random(-100, 100) * 0.01,
            health = math.random(50, 100),
            t = 0,
        })
    end
    return entities
end

local function updateEntities(entities, dt)
    for _, e in ipairs(entities) do
        e.t = e.t + dt
        e.x = e.x + e.vx * dt
        e.y = e.y + e.vy * dt
        if e.x < 0 or e.x > 800 then e.vx = -e.vx end
        if e.y < 0 or e.y > 600 then e.vy = -e.vy end

        -- Simulate enemy-like CPU work: distance check + behaviour
        local dx = e.x - 400
        local dy = e.y - 300
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < 200 then
            -- "near player" — do extra work
            e.health = e.health - dt * 5
            -- Simulate projectile update (Box2D body-like ops)
            for _ = 1, 3 do
                local px = math.sin(e.t * 3) * 50
                local py = math.cos(e.t * 3) * 50
                local pd = math.sqrt(px * px + py * py)
            end
        end
    end
end

function love.load()
    love.window.setMode(800, 600)
    print("=== Entity Count Scaling Benchmark ===\n")

    local counts = {10, 50, 100, 200, 500}
    local test_duration = 3 -- seconds per test

    for _, count in ipairs(counts) do
        print("Testing " .. count .. " entities...")
        collectgarbage("collect")

        local entities = spawnEntities(count)

        -- Warm up
        for _ = 1, 30 do
            updateEntities(entities, 1/60)
        end

        -- Measure
        local frames = 0
        local elapsed = 0
        local frame_times = {}
        local step = 1/60

        while elapsed < test_duration do
            local t1 = love.timer.getTime()
            updateEntities(entities, step)
            local t2 = love.timer.getTime()
            local dt = t2 - t1
            elapsed = elapsed + dt
            frames = frames + 1
            table.insert(frame_times, dt)
        end

        local fps = frames / elapsed
        local avg = 0
        for _, f in ipairs(frame_times) do avg = avg + f end
        avg = avg / #frame_times

        table.sort(frame_times)
        local p50 = frame_times[math.max(1, math.floor(#frame_times * 0.50))]
        local p99 = frame_times[math.max(1, math.floor(#frame_times * 0.99))]

        local mem = collectgarbage("count")

        print(string.format("  FPS: %.1f  Avg: %.2fms  P50: %.2fms  P99: %.2fms  Mem: %.0fKB",
            fps, avg * 1000, p50 * 1000, p99 * 1000, mem))

        table.insert(results, {
            entity_count = count,
            fps = math.floor(fps * 10) / 10,
            avg_frame_ms = math.floor(avg * 100000) / 100,
            p50_frame_ms = math.floor(p50 * 100000) / 100,
            p99_frame_ms = math.floor(p99 * 100000) / 100,
            memory_kb = math.floor(mem),
        })

        entities = nil
        collectgarbage("collect")
    end

    -- Summary
    print("\n=== Results Summary ===")
    print(string.format("%-12s %8s %10s %10s %10s", "Entities", "FPS", "Avg(ms)", "P50(ms)", "P99(ms)"))
    print(string.rep("-", 55))
    for _, r in ipairs(results) do
        print(string.format("%-12d %8.1f %10.2f %10.2f %10.2f",
            r.entity_count, r.fps, r.avg_frame_ms, r.p50_frame_ms, r.p99_frame_ms))
    end

    -- Export
    local f = io.open("benchmark_entities.json", "w")
    if f then
        f:write(json_encode(results))
        f:close()
        print("\nExported to benchmark_entities.json")
    end

    print("Done.")
    love.event.quit()
end

function love.update(dt) end
function love.draw()
    love.graphics.setColor(0.1, 0.1, 0.2)
    love.graphics.rectangle("fill", 0, 0, 800, 600)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Entity Count Benchmark Running...", 10, 10)
end
