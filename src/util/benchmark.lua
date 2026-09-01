-- =============================================================================
-- Benchmark Framework for DOGE Game
-- Usage: benchmark.scene("test", setup, teardown).run("test", 5)
-- =============================================================================

local benchmark = {
    scenes = {},
    results = {},
}

-- =============================================================================
-- Scene Definition
-- =============================================================================

-- Define a benchmark scene
-- setup(entities_count) -> nil
-- teardown() -> nil
function benchmark.scene(name, setup, teardown)
    benchmark.scenes[name] = {
        setup = setup or function() end,
        teardown = teardown or function() end,
    }
    return benchmark
end

-- =============================================================================
-- Benchmark Runner
-- =============================================================================

-- Time a single function call
function benchmark.measure(fn, ...)
    local start = love.timer.getTime()
    fn(...)
    return love.timer.getTime() - start
end

-- Run a scene for specified duration, collecting stats
function benchmark.run(sceneName, duration, callback)
    local scene = benchmark.scenes[sceneName]
    if not scene then
        print("Benchmark: unknown scene '" .. sceneName .. "'")
        return nil
    end

    duration = duration or 5

    print("\n=== Benchmark: " .. sceneName .. " (duration: " .. duration .. "s) ===")

    -- Setup
    collectgarbage("collect")
    local mem_before = collectgarbage("count")
    scene.setup()
    local mem_after = collectgarbage("count")
    print(string.format("  Setup memory: %.1f KB (+%.1f KB)",
        mem_after, mem_after - mem_before))

    -- Warmup frames
    local warmup = 60
    for i = 1, warmup do
        love.timer.sleep(0.001)
    end

    -- Measure
    local start_time = love.timer.getTime()
    local frame_count = 0
    local frame_times = {}
    local last_time = start_time

    while love.timer.getTime() - start_time < duration do
        local now = love.timer.getTime()
        local dt = now - last_time
        last_time = now
        frame_count = frame_count + 1

        -- Simulate a game update (entities self-update via scene)
        -- Scene-specific update happens naturally if entities are in the global world

        table.insert(frame_times, dt)

        -- Small sleep to simulate vsync-like pacing
        -- love.timer.sleep(0.001)
    end

    local elapsed = love.timer.getTime() - start_time
    local fps = frame_count / elapsed
    local avg_frame = 0
    for _, t in ipairs(frame_times) do avg_frame = avg_frame + t end
    avg_frame = avg_frame / math.max(1, #frame_times)

    -- Calculate percentiles
    table.sort(frame_times)
    local p50 = frame_times[math.floor(#frame_times * 0.50)] or 0
    local p99 = frame_times[math.floor(#frame_times * 0.99)] or 0

    local result = {
        scene = sceneName,
        duration = elapsed,
        frames = frame_count,
        fps = fps,
        avg_frame_ms = avg_frame * 1000,
        p50_frame_ms = p50 * 1000,
        p99_frame_ms = p99 * 1000,
        memory_kb = mem_after,
        memory_delta_kb = mem_after - mem_before,
    }

    print(string.format("  Frames: %d  FPS: %.1f  Avg frame: %.2fms  P50: %.2fms  P99: %.2fms",
        frame_count, fps, avg_frame * 1000, p50 * 1000, p99 * 1000))

    -- Teardown
    scene.teardown()

    -- Store result
    benchmark.results[sceneName] = result

    if callback then
        callback(result)
    end

    return result
end

-- =============================================================================
-- Comparison Runner
-- =============================================================================

function benchmark.compare(sceneNames, duration)
    print("\n=== Benchmark Comparison ===")
    print(string.format("%-25s %8s %10s %10s %10s",
        "Scene", "FPS", "Avg(ms)", "P50(ms)", "P99(ms)"))
    print(string.rep("-", 70))

    local results = {}
    for _, name in ipairs(sceneNames) do
        local r = benchmark.run(name, duration)
        if r then
            table.insert(results, r)
            print(string.format("%-25s %8.1f %10.2f %10.2f %10.2f",
                name, r.fps, r.avg_frame_ms, r.p50_frame_ms, r.p99_frame_ms))
        end
    end
    return results
end

-- =============================================================================
-- Entity Spawn Helpers
-- =============================================================================

-- Spawn N simple entities (physics bodies) for testing
-- Only works if world exists; otherwise creates lightweight dummy table entities
function benchmark.spawnEntities(count)
    local entities = {}
    if world and type(world) == "userdata" then
        -- Use real physics world
        for i = 1, count do
            local body = love.physics.newBody(world, math.random(0, 800), math.random(0, 600), "dynamic")
            local shape = love.physics.newCircleShape(15)
            local fix = love.physics.newFixture(body, shape)
            fix:setGroupIndex(-900 + i) -- unique group to avoid collisions between test entities
            table.insert(entities, { body = body, fixture = fix, t = 0 })
        end
    else
        -- Dummy entities without physics (for isolated benchmark tests)
        for i = 1, count do
            table.insert(entities, {
                x = math.random(0, 800),
                y = math.random(0, 600),
                vx = math.random(-100, 100) * 0.1,
                vy = math.random(-100, 100) * 0.1,
                t = 0,
                health = 100,
            })
        end
    end
    return entities
end

-- Update dummy entities (simple simulation)
function benchmark.updateEntities(entities, dt)
    for _, e in ipairs(entities) do
        e.t = e.t + dt
        if e.body then
            -- Physics entity — already handled by world:update()
        else
            -- Dummy entity — simple bounce
            e.x = e.x + e.vx * dt
            e.y = e.y + e.vy * dt
            if e.x < 0 or e.x > 800 then e.vx = -e.vx end
            if e.y < 0 or e.y > 600 then e.vy = -e.vy end

            -- Simulate some CPU work
            local dx = e.x - 400
            local dy = e.y - 300
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < 200 then
                e.health = e.health - dt * 10
            end
        end
    end
end

-- =============================================================================
-- Draw List Benchmark Helpers
-- =============================================================================

-- Create a benchmark draw list with N entries
function benchmark.createDrawList(count)
    local list = {}
    for i = 1, count do
        table.insert(list, {
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
            color = { 1, 1, 1, 1 },
            blend_mode = { "alpha" },
            quad = nil,
            draw_type = "text",
            text = "benchmark_" .. i,
        })
    end
    return list
end

-- =============================================================================
-- Results Export
-- =============================================================================

function benchmark.exportResults(filename)
    if not json then
        print("Benchmark: json module not available, skipping export")
        return ""
    end
    local export = {}
    for name, r in pairs(benchmark.results) do
        table.insert(export, r)
    end
    local json_str = json.encode(export)
    if filename then
        local f = io.open(filename, "w")
        if f then
            f:write(json_str)
            f:close()
            print("Benchmark results saved to: " .. filename)
        end
    end
    return json_str
end

return benchmark
