-- =============================================================================
-- Benchmark: Collision & Physics Throughput
-- Tests Box2D world step time vs body count
-- Run: love ./misc/benchmark-collision
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

function love.load()
    love.window.setMode(800, 600)
    love.physics.setMeter(64)
    print("=== Collision & Physics Throughput Benchmark ===\n")

    local counts = {10, 50, 100, 200, 500}
    local iterations = 30 -- measurements per count

    for _, count in ipairs(counts) do
        print("Testing " .. count .. " bodies...")

        local step_times = {}

        for _ = 1, iterations do
            -- Fresh world each iteration
            local w = love.physics.newWorld(0, 0, true)
            local bodies = {}

            for i = 1, count do
                local body = love.physics.newBody(w,
                    math.random(0, 800),
                    math.random(0, 600),
                    "dynamic")
                local shape = love.physics.newCircleShape(15)
                local fix = love.physics.newFixture(body, shape)
                fix:setGroupIndex(-900 + i % 32767)
                body:setLinearVelocity(math.random(-100, 100), math.random(-100, 100))
                table.insert(bodies, body)
            end

            -- Measure world step
            local t1 = love.timer.getTime()
            w:update(1 / 60)
            local t2 = love.timer.getTime()
            table.insert(step_times, (t2 - t1) * 1000)

            -- Measure position read throughput
            local read_times = {}
            for _ = 1, 3 do
                local rt1 = love.timer.getTime()
                for _, body in ipairs(bodies) do
                    local x, y = body:getPosition()
                    local vx, vy = body:getLinearVelocity()
                    local _ = x + y + vx + vy
                end
                local rt2 = love.timer.getTime()
                table.insert(read_times, (rt2 - rt1) * 1000)
            end
            local avg_read = 0
            for _, t in ipairs(read_times) do avg_read = avg_read + t end
            avg_read = avg_read / #read_times

            -- Cleanup
            for _, body in ipairs(bodies) do body:destroy() end
            bodies = nil
            w = nil
            collectgarbage("collect")
        end

        -- Stats
        table.sort(step_times)
        local avg_step = 0
        for _, t in ipairs(step_times) do avg_step = avg_step + t end
        avg_step = avg_step / #step_times
        local p50_step = step_times[math.max(1, math.floor(#step_times * 0.50))]
        local p99_step = step_times[math.max(1, math.floor(#step_times * 0.99))]

        print(string.format("  World step: Avg %.3fms  P50 %.3fms  P99 %.3fms",
            avg_step, p50_step, p99_step))

        table.insert(results, {
            body_count = count,
            world_step_avg_ms = math.floor(avg_step * 1000) / 1000,
            world_step_p50_ms = math.floor(p50_step * 1000) / 1000,
            world_step_p99_ms = math.floor(p99_step * 1000) / 1000,
        })
    end

    -- Summary
    print("\n=== Results Summary ===")
    print(string.format("%-10s %12s %12s %12s", "Bodies", "Avg(ms)", "P50(ms)", "P99(ms)"))
    print(string.rep("-", 50))
    for _, r in ipairs(results) do
        print(string.format("%-10d %12.3f %12.3f %12.3f",
            r.body_count, r.world_step_avg_ms, r.world_step_p50_ms, r.world_step_p99_ms))
    end

    local f = io.open("benchmark_collision.json", "w")
    if f then
        f:write(json_encode(results))
        f:close()
        print("\nExported to benchmark_collision.json")
    end

    print("Done.")
    love.event.quit()
end

function love.update(dt) end
function love.draw()
    love.graphics.setColor(0.1, 0.1, 0.2)
    love.graphics.rectangle("fill", 0, 0, 800, 600)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Collision Benchmark Running...", 10, 10)
end
