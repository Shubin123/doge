-- =============================================================================
-- Performance Profiler for DOGE Game
-- Features: hierarchical timing, on-screen overlay, function wrapping, FPS tracking
-- =============================================================================

local profiler = {
    -- Timing data
    times = {},         -- {name = total_seconds}
    calls = {},         -- {name = call_count}
    start_times = {},   -- {name = start_time} (stack of starts for nested calls)
    frame_times = {},   -- per-frame timing history for overlay

    -- Frame tracking
    frame_count = 0,
    last_report_frame = 0,
    report_interval = 120,  -- report to console every N frames

    -- State
    enabled = true,
    overlay_visible = false,
    overlay_detail = 1, -- 1=simple, 2=full breakdown

    -- Counters
    draw_calls = 0,
    physics_bodies = 0,
    draw_list_size = 0,

    -- FPS tracking
    fps_history = {},
    fps_update_timer = 0,
    current_fps = 0,
    min_fps = math.huge,
    max_fps = 0,

    -- Frame time tracking
    frame_start_time = 0,
    frame_time_history = {},
    current_frame_time = 0,
    min_frame_time = math.huge,
    max_frame_time = 0,

    -- GC tracking
    last_gc_count = 0,
    gc_pressure = 0,
}

-- =============================================================================
-- Core Profiling API
-- =============================================================================

function profiler.start(name)
    if not profiler.enabled then return end
    if not profiler.start_times[name] then
        profiler.start_times[name] = {}
    end
    table.insert(profiler.start_times[name], love.timer.getTime())
    profiler.calls[name] = (profiler.calls[name] or 0) + 1
end

function profiler.stop(name)
    if not profiler.enabled then return end
    local stack = profiler.start_times[name]
    if stack and #stack > 0 then
        local start_time = table.remove(stack)
        local elapsed = love.timer.getTime() - start_time
        profiler.times[name] = (profiler.times[name] or 0) + elapsed
    end
end

function profiler.reset()
    profiler.times = {}
    profiler.calls = {}
    profiler.start_times = {}
    profiler.frame_times = {}
    profiler.frame_count = 0
    profiler.draw_calls = 0
    profiler.physics_bodies = 0
    profiler.draw_list_size = 0
    profiler.min_fps = math.huge
    profiler.max_fps = 0
    profiler.min_frame_time = math.huge
    profiler.max_frame_time = 0
    profiler.gc_pressure = 0
end

function profiler.enable()
    profiler.enabled = true
end

function profiler.disable()
    profiler.enabled = false
end

-- =============================================================================
-- Frame Update (call once per frame from love.update)
-- =============================================================================

function profiler.frameUpdate(dt)
    if not profiler.enabled then return end

    profiler.frame_count = profiler.frame_count + 1
    profiler.current_frame_time = dt

    -- Track FPS
    profiler.fps_update_timer = profiler.fps_update_timer + dt
    if profiler.fps_update_timer >= 1.0 then
        profiler.current_fps = profiler.frame_count / profiler.fps_update_timer
        table.insert(profiler.fps_history, profiler.current_fps)
        if #profiler.fps_history > 60 then
            table.remove(profiler.fps_history, 1)
        end
        if profiler.current_fps < profiler.min_fps then
            profiler.min_fps = profiler.current_fps
        end
        if profiler.current_fps > profiler.max_fps then
            profiler.max_fps = profiler.current_fps
        end
        profiler.frame_count = 0
        profiler.fps_update_timer = 0
    end

    -- Track frame time
    table.insert(profiler.frame_time_history, dt * 1000)
    if #profiler.frame_time_history > 120 then
        table.remove(profiler.frame_time_history, 1)
    end
    if dt < profiler.min_frame_time then profiler.min_frame_time = dt end
    if dt > profiler.max_frame_time then profiler.max_frame_time = dt end

    -- Track GC pressure
    local current_gc = collectgarbage("count")
    if profiler.last_gc_count > 0 then
        profiler.gc_pressure = current_gc - profiler.last_gc_count
    end
    profiler.last_gc_count = current_gc

    -- Periodic console report
    if profiler.frame_count > 0 and profiler.frame_count % profiler.report_interval == 0 then
        -- silent; use overlay or explicit report() for output
    end
end

-- =============================================================================
-- Function Wrapping Helpers
-- =============================================================================

-- Wrap a single function on a module table
-- Usage: profiler.wrap(enemy, "update")
function profiler.wrap(module, funcName, label)
    label = label or (tostring(module) .. "." .. funcName)
    local original = module[funcName]
    if not original or type(original) ~= "function" then
        return false
    end
    module[funcName] = function(...)
        profiler.start(label)
        local results = {original(...)}
        profiler.stop(label)
        return unpack(results)
    end
    return true
end

-- Wrap a method on an instance (self-style, e.g. Enemy.update)
-- Usage: profiler.wrapMethod(Enemy, "update")
function profiler.wrapMethod(classTable, methodName, label)
    label = label or (methodName)
    local original = classTable[methodName]
    if not original or type(original) ~= "function" then
        return false
    end
    classTable[methodName] = function(self, ...)
        profiler.start(label)
        local results = {original(self, ...)}
        profiler.stop(label)
        return unpack(results)
    end
    return true
end

-- Wrap all listed functions on a module
function profiler.wrapAll(module, funcNames, prefix)
    prefix = prefix or ""
    for _, name in ipairs(funcNames) do
        local label = prefix .. name
        profiler.wrap(module, name, label)
    end
end

-- =============================================================================
-- On-Screen Overlay
-- =============================================================================

local function avg(t)
    if #t == 0 then return 0 end
    local sum = 0
    for _, v in ipairs(t) do sum = sum + v end
    return sum / #t
end

function profiler.drawOverlay()
    if not profiler.overlay_visible then return end

    love.graphics.push()
    love.graphics.reset()  -- reset to screen coords (bypass camera)

    local w = love.graphics.getWidth()
    local h = love.graphics.getHeight()
    local line_h = 14
    local x = 10
    local y = 10

    -- Semi-transparent background
    love.graphics.setColor(0, 0, 0, 0.6)
    if profiler.overlay_detail == 1 then
        love.graphics.rectangle("fill", x - 4, y - 4, 200, 80)
    else
        love.graphics.rectangle("fill", x - 4, y - 4, 320, h - 20)
    end

    -- FPS display with color coding
    local fps = profiler.current_fps
    local fpsColor = {0.2, 1, 0.2}  -- green >= 60
    if fps < 30 then
        fpsColor = {1, 0.2, 0.2}    -- red < 30
    elseif fps < 60 then
        fpsColor = {1, 0.8, 0.2}    -- yellow 30-60
    end

    love.graphics.setColor(fpsColor[1], fpsColor[2], fpsColor[3], 1)
    love.graphics.setFont(statsFont)
    love.graphics.print(string.format("FPS: %.0f  Frame: %.2fms  Mem: %.1fMB",
        fps,
        profiler.current_frame_time * 1000,
        collectgarbage("count") / 1024),
        x, y)

    if profiler.overlay_detail >= 2 then
        y = y + line_h + 2
        love.graphics.setColor(0.7, 0.7, 0.7, 1)
        love.graphics.print(string.format("Min FPS: %.0f  Max FPS: %.0f  GC: %+.1fKB",
            profiler.min_fps == math.huge and 0 or profiler.min_fps,
            profiler.max_fps,
            profiler.gc_pressure),
            x, y)

        y = y + line_h
        love.graphics.print(string.format("Draw List: %d  Bodies: %d  Objs: %d",
            profiler.draw_list_size,
            profiler.physics_bodies,
            profiler.draw_calls),
            x, y)

        -- Top 10 functions by time
        y = y + line_h + 4
        love.graphics.setColor(1, 1, 0.5, 1)
        love.graphics.print("Top functions (total ms):", x, y)

        local sorted = {}
        for name, total in pairs(profiler.times) do
            table.insert(sorted, {name = name, total = total})
        end
        table.sort(sorted, function(a, b) return a.total > b.total end)

        for i = 1, math.min(10, #sorted) do
            y = y + line_h
            local pct = 0
            if profiler.frame_count > 0 then
                pct = (sorted[i].total / (profiler.frame_count * (profiler.current_frame_time or 0.016))) * 100
            end
            local c = profiler.calls[sorted[i].name] or 0
            love.graphics.setColor(0.6, 0.8, 1, 1)
            love.graphics.print(string.format("  %s: %.2fms (%d calls, %.0f%%)",
                sorted[i].name:sub(1, 35),
                sorted[i].total * 1000,
                c,
                pct),
                x, y)
        end
    end

    love.graphics.pop()
end

-- =============================================================================
-- Report Generation
-- =============================================================================

function profiler.report(min_time_ms, toFile)
    min_time_ms = min_time_ms or 0
    local lines = {}

    table.insert(lines, "\n=== PERFORMANCE PROFILER REPORT ===")
    table.insert(lines, string.format("FPS: %.1f (min %.1f, max %.1f)",
        profiler.current_fps,
        profiler.min_fps == math.huge and 0 or profiler.min_fps,
        profiler.max_fps))
    table.insert(lines, string.format("Frame time: %.2fms", profiler.current_frame_time * 1000))
    table.insert(lines, string.format("Memory: %.1f MB", collectgarbage("count") / 1024))
    table.insert(lines, string.format("Draw list: %d entries", profiler.draw_list_size))
    table.insert(lines, "")

    local sorted = {}
    local total_time = 0
    for name, func_time in pairs(profiler.times) do
        if (func_time * 1000) >= min_time_ms then
            table.insert(sorted, {
                name = name,
                total_time = func_time,
                calls = profiler.calls[name] or 0,
                avg_time = func_time / math.max(1, profiler.calls[name] or 1)
            })
            total_time = total_time + func_time
        end
    end

    table.sort(sorted, function(a, b) return a.total_time > b.total_time end)

    table.insert(lines, string.format("%-45s %10s %8s %12s %8s",
        "Function", "Total(ms)", "Calls", "Avg(ms)", "% Time"))
    table.insert(lines, string.rep("-", 90))

    for _, func in ipairs(sorted) do
        local pct = total_time > 0 and (func.total_time / total_time * 100) or 0
        table.insert(lines, string.format("%-45s %10.3f %8d %12.6f %7.1f%%",
            func.name:sub(1, 44),
            func.total_time * 1000,
            func.calls,
            func.avg_time * 1000,
            pct))
    end

    table.insert(lines, string.format("\nTotal profiled: %.3f ms across %d functions",
        total_time * 1000, #sorted))
    table.insert(lines, "=========================================\n")

    local report = table.concat(lines, "\n")

    if toFile then
        local f = io.open(toFile, "w")
        if f then
            f:write(report)
            f:close()
            print("Profiler report saved to: " .. toFile)
        end
    end

    print(report)
    return report
end

-- Export to JSON
function profiler.exportJSON(filename)
    local data = {
        fps = {
            current = profiler.current_fps,
            min = profiler.min_fps == math.huge and 0 or profiler.min_fps,
            max = profiler.max_fps,
        },
        frame_time_ms = profiler.current_frame_time * 1000,
        memory_mb = collectgarbage("count") / 1024,
        draw_list_size = profiler.draw_list_size,
        functions = {}
    }

    for name, total in pairs(profiler.times) do
        table.insert(data.functions, {
            name = name,
            total_ms = total * 1000,
            calls = profiler.calls[name] or 0,
            avg_ms = (total / math.max(1, profiler.calls[name] or 1)) * 1000
        })
    end

    table.sort(data.functions, function(a, b) return a.total_ms > b.total_ms end)

    local json_str = json.encode(data)
    if filename then
        local f = io.open(filename, "w")
        if f then
            f:write(json_str)
            f:close()
            print("Profiler JSON saved to: " .. filename)
        end
    end
    return json_str
end

return profiler
