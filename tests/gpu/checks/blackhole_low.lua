--[[
  The black hole on low graphics (game/blackhole.lua's stand-in):

      python3 tests/gpu/run.py --checks --only blackhole_low

  Its look is a screen-space pass over the scene, which only runs on high
  graphics; on low there was nothing to see where it sits (the black hole
  gun's holes had a stand-in, it hadn't). Now:

  1. on low graphics it shows: a black shadow ringed by its warm disk;
  2. its bands turn;
  3. on high graphics the stand-in is left out (the pass draws it);
  4. on low graphics slow time still turns the frame cold at the edges;
  5. the black hole gun's holes keep their stand-in.

  Leaves both looks in dist/gpu-test/checks-blackhole_low/.
]]
return function(h)
    player.god = true
    h.advance(10)
    for _, e in ipairs(enemy.enemies) do
        if not e.dead then e:killEnemy() end
    end
    local W, H = h.cfg.width, h.cfg.height

    local px, py = 3000, 300
    local function place(x, y)
        player.body:setPosition(x, y)
        player.body:setLinearVelocity(0, 0)
        camera.snap(player)
    end

    -- A captured frame's pixels (the harness writes them out raw)
    local function frame(name)
        h.capture(name)
        local f = assert(io.open(h.cfg.out .. "/" .. name .. ".rgba", "rb"))
        local data = f:read("*a")
        f:close()
        return function(x, y)
            local i = (math.floor(y) * W + math.floor(x)) * 4 + 1
            local r, g, b = data:byte(i, i + 2)
            return (r or 0) / 255, (g or 0) / 255, (b or 0) / 255
        end
    end
    local function onScreen()
        return camera.pos.x + blackhole.x * camera.zoom, camera.pos.y + blackhole.y * camera.zoom
    end
    -- Over the box round (cx, cy): how many pixels differ between two
    -- frames, the darkest at its middle, and how many are warm and bright
    local function look(a, b, cx, cy, r)
        local changed, warm = 0, 0
        for y = cy - r, cy + r, 2 do
            for x = cx - r, cx + r, 2 do
                if x >= 0 and y >= 0 and x < W and y < H then
                    local r1, g1, b1 = a(x, y)
                    local r2, g2, b2 = b(x, y)
                    if math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2) > 0.15 then changed = changed + 1 end
                    if r1 > 0.6 and r1 > b1 + 0.15 then warm = warm + 1 end
                end
            end
        end
        local mid = 0
        for y = cy - 6, cy + 6, 3 do
            for x = cx - 6, cx + 6, 3 do
                local r1, g1, b1 = a(x, y)
                mid = math.max(mid, r1 + g1 + b1)
            end
        end
        return changed, mid / 3, warm
    end

    -- 1. Low graphics: it shows (over the scene without it)
    daynight.setHour(15)
    settings.applyPreset("low")
    place(px, py)
    blackhole.moveTo(px + 300, py) -- in view, far enough off that time runs on
    h.advance(20)
    local cx, cy = onScreen()
    local with = frame("low_with")
    blackhole.moveTo(px + 30000, py)
    h.advance(2)
    local without = frame("low_without")
    local changed, mid, warm = look(with, without, cx, cy, 130)
    h.check("on low graphics the black hole shows", changed > 600 and mid < 0.12 and warm > 40,
        string.format("%d px of it changed, its middle %.2f bright, %d px warm", changed, mid, warm))

    -- 2. It turns
    blackhole.moveTo(px + 300, py)
    h.advance(2)
    local a = frame("low_turning_a")
    h.advance(20)
    local b = frame("low_turning_b")
    local turned = look(a, b, cx, cy, 130)
    h.check("and its bands turn", turned > 20, string.format("%d px changed in a third of a second", turned))

    -- 3. High graphics: the lensing pass draws it, so no stand-in
    settings.applyPreset("high")
    h.advance(2)
    local standIns = 0
    for _, d in ipairs(dynamic_draw_list) do
        if d.draw_type == "blackhole" then standIns = standIns + 1 end
    end
    h.check("on high graphics the stand-in is left out", standIns == 0, standIns .. " in the draw list")
    h.capture("high")

    -- 4. Slow time on low: colder and darker at the edges (the corners, well
    -- away from the hole)
    settings.applyPreset("low")
    local function corners(f)
        local r, g, b, n = 0, 0, 0, 0
        for _, c in ipairs({ { 20, 20 }, { W - 20, 20 }, { 20, H - 120 }, { W - 20, H - 120 } }) do
            for oy = -8, 8, 4 do
                for ox = -8, 8, 4 do
                    local cr, cg, cb = f(c[1] + ox, c[2] + oy)
                    r, g, b, n = r + cr, g + cg, b + cb, n + 1
                end
            end
        end
        return r / n, g / n, b / n
    end
    blackhole.moveTo(px + 30000, py)
    place(px, py)
    h.advance(60)
    local nr, ng, nb = corners(frame("low_time_normal"))
    blackhole.moveTo(px + 150, py)
    h.advance(90)
    local slowed = blackhole.timeScale
    local sr, sg, sb = corners(frame("low_time_slow"))
    h.check("on low graphics slow time still turns the frame cold", slowed < 0.6 and sr < nr * 0.85 and sb / math.max(sr, 0.01) > nb / math.max(nr, 0.01),
        string.format("time at %.2f; corners red %.2f -> %.2f, blue/red %.2f -> %.2f", slowed, nr, sr,
            nb / math.max(nr, 0.01), sb / math.max(sr, 0.01)))

    -- 5. The gun's holes keep theirs
    blackhole.moveTo(px + 30000, py)
    place(px, py)
    h.advance(30)
    blackholeGun.new({ from = vec2.new(px, py), dir = vec2.new(1, 0), muzzle = 20, range = 200 })
    h.advance(30)
    local gunStandIns = 0
    for _, d in ipairs(dynamic_draw_list) do
        if d.draw_type == "blackholeGun" then gunStandIns = gunStandIns + 1 end
    end
    h.check("the black hole gun's holes keep their stand-in", gunStandIns == 1, gunStandIns .. " in the draw list")

    settings.applyPreset("high")
    daynight.setHour(var.day_start)
end
