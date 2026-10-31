--[[
  Enemy sprites and their death light, checked inside the real game:

      python3 tests/gpu/run.py --checks

  1. live sprites follow their bodies -- every frame, on screen and off,
     through zoom changes, screen shake and far from the world origin;
  2. a dying enemy's death light (the glow pass) covers exactly its sprite,
     and the sprite sits on the body -- both rendered through the game's own
     instanced passes and camera transform;
  3. every kill, on screen or off, fades where it died and is then released;
  4. in a full frame, the death light shows up where the enemy died.
]]
return function(h)
    local W, H = love.graphics.getPixelDimensions()
    local canvas = love.graphics.newCanvas(W, H)
    local frameCopy = love.graphics.newCanvas(W, H)

    ---------------------------------------------------------------- helpers --
    local function spriteOf(e)
        return gun_enemies[e.fixture:getUserData() + 2]
    end

    local function liveEnemies()
        local list = {}
        for i, e in ipairs(enemy.enemies) do
            if not e.dead and e.fixture and e.body and not e.body:isDestroyed() then
                list[#list + 1] = { i = i, e = e, sprite = spriteOf(e) }
            end
        end
        return list
    end

    -- Where camera.apply() puts a world point on screen.
    local function project(x, y)
        local z = camera.zoom
        local tx = math.floor((camera.x + camera.shake_offset_x) / z)
        local ty = math.floor((camera.y + camera.shake_offset_y) / z)
        return (x + tx) * z, (y + ty) * z
    end

    -- Checks 1 and 1b run after every frame of the script.
    local follow = { frames = 0, sprites = 0, worst = 0, bad = 0 }
    local seen = { sprites = 0, bad = 0 }
    local function checkFollow()
        follow.frames = follow.frames + 1
        for _, L in ipairs(liveEnemies()) do
            local bx, by = L.e.body:getPosition()
            local s = L.sprite
            local err = s and math.max(math.abs(s.x - bx), math.abs(s.y - by)) or math.huge
            follow.sprites = follow.sprites + 1
            follow.worst = math.max(follow.worst, err)
            if err > 1e-3 then
                follow.bad = follow.bad + 1
                follow.example = follow.example or string.format(
                    "frame %d, enemy %d: sprite (%.1f, %.1f), body (%.1f, %.1f)",
                    follow.frames, L.i, s and s.x or 0, s and s.y or 0, bx, by)
            end
            -- An enemy on screen must count as on screen (its sprite is then
            -- turned to face the player, and recoloured, every frame).
            local sx, sy = project(bx, by)
            if s and sx >= 0 and sx <= W and sy >= 0 and sy <= H then
                seen.sprites = seen.sprites + 1
                if not s.active then
                    seen.bad = seen.bad + 1
                    seen.example = seen.example or string.format(
                        "frame %d, enemy %d at screen (%.0f, %.0f) treated as off-screen",
                        follow.frames, L.i, sx, sy)
                end
            end
        end
    end

    local function advance(n)
        for _ = 1, n do
            h.advance(1)
            checkFollow()
        end
    end

    -- Render one instanced pass exactly as the game does (world space, under
    -- camera.apply) and measure what landed in a window around (cx, cy).
    local function measure(shader, cx, cy, half)
        love.graphics.push("all")
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.origin()
        camera.apply()
        characterAnimator.drawInstances(shader)
        love.graphics.pop()

        local m = { n = 0 }
        local x0, y0 = math.max(0, math.floor(cx - half)), math.max(0, math.floor(cy - half))
        local x1, y1 = math.min(W, math.floor(cx + half)), math.min(H, math.floor(cy + half))
        if x1 <= x0 or y1 <= y0 then return m end
        local img = canvas:newImageData(1, 1, x0, y0, x1 - x0, y1 - y0)
        local sw, sx, sy = 0, 0, 0
        local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
        for y = 0, y1 - y0 - 1 do
            for x = 0, x1 - x0 - 1 do
                local _, _, _, a = img:getPixel(x, y)
                if a > 0.05 then
                    local px, py = x0 + x + 0.5, y0 + y + 0.5
                    m.n = m.n + 1
                    sw, sx, sy = sw + a, sx + px * a, sy + py * a
                    minx, miny = math.min(minx, px), math.min(miny, py)
                    maxx, maxy = math.max(maxx, px), math.max(maxy, py)
                end
            end
        end
        if m.n > 0 then
            m.cx, m.cy = sx / sw, sy / sw
            m.minx, m.miny, m.maxx, m.maxy = minx, miny, maxx, maxy
        end
        return m
    end

    -- Hide every instance but `target` (and its outline) for a measurement.
    local function isolate(target)
        local saved = {}
        for _, inst in ipairs(gun_enemies) do
            if inst ~= target then
                saved[inst] = inst.on
                inst.on = false
            end
        end
        local color = target.color
        target.color = { 0, 0, 0, 0 }
        characterAnimator.populate()
        return function()
            for inst, on in pairs(saved) do inst.on = on end
            target.color = color
            characterAnimator.populate()
        end
    end

    -- The live enemy nearest the screen centre whose sprite is fully on screen;
    -- with none in view, the nearest one is brought next to the player.
    local function onScreenEnemy()
        local best, bd
        for _, L in ipairs(liveEnemies()) do
            local sx, sy = project(L.e.body:getPosition())
            local margin = 70 * camera.zoom
            if sx > margin and sx < W - margin and sy > margin + 50 and sy < H - margin then
                local d = (sx - W / 2) ^ 2 + (sy - H / 2) ^ 2
                if not bd or d < bd then best, bd = L, d end
            end
        end
        if best then return best end
        local px, py = player.body:getPosition()
        for _, L in ipairs(liveEnemies()) do
            local ex, ey = L.e.body:getPosition()
            local d = (ex - px) ^ 2 + (ey - py) ^ 2
            if not bd or d < bd then best, bd = L, d end
        end
        if best then
            best.e.body:setPosition(px + 50, py + 25)
            best.e.body:setLinearVelocity(0, 0)
            advance(2)
            if best.e.dead then return nil end
        end
        return best
    end

    --------------------------------------------------- check 2: kill cases --
    local cases = {}
    local function killCase(label)
        local L = onScreenEnemy()
        if not L then
            cases[#cases + 1] = label .. ": no enemy on screen"
            return
        end
        local dx, dy = L.e.body:getPosition()
        enemy.damageEnemy(L.i - 1, 1e6)
        advance(3)

        local s, why = L.sprite, nil
        if not (s.on and s.opacity and s.opacity > 0 and s.opacity < 1) then
            why = "not fading (opacity " .. tostring(s.opacity) .. ")"
        elseif math.abs(s.x - dx) > 1e-3 or math.abs(s.y - dy) > 1e-3 then
            why = "sprite left its death position"
        else
            local px, py = project(dx, dy)
            local restore = isolate(s)
            local half = 150 * camera.zoom
            local main = measure(characterAnimator.shader, px, py, half)
            local glow = measure(characterAnimator.shaderWithTransforms, px, py, half)
            restore()
            if main.n < 20 then
                why = "sprite not drawn near its body"
            elseif glow.n < 20 then
                why = "no death light near the body"
            elseif math.abs(main.cx - glow.cx) > 0.25 or math.abs(main.cy - glow.cy) > 0.25 then
                why = string.format("death light off the sprite by (%.2f, %.2f) px",
                    glow.cx - main.cx, glow.cy - main.cy)
            else
                local tx = (main.maxx - main.minx) * 0.25 + 2
                local ty = (main.maxy - main.miny) * 0.25 + 2
                if px < main.minx - tx or px > main.maxx + tx or py < main.miny - ty or py > main.maxy + ty then
                    why = string.format("sprite (%.0f-%.0f, %.0f-%.0f) is not on its body (%.1f, %.1f)",
                        main.minx, main.maxx, main.miny, main.maxy, px, py)
                end
            end
        end
        if why then cases[#cases + 1] = label .. ": " .. why end
        cases.total = (cases.total or 0) + 1
    end

    local function settleZoom(z)
        camera.setZoom(z)
        for _ = 1, 240 do
            advance(1)
            if math.abs(camera.zoom - z) < 1e-3 then break end
        end
    end

    ------------------------------------------------------------- the script --
    advance(90) -- every enemy spawned

    for _, z in ipairs({ 1, 2.2, 0.6 }) do
        settleZoom(z)
        killCase("near origin, zoom " .. z)
    end
    camera.shake(10, 2)
    advance(2)
    killCase("near origin, shaking")

    -- Far from the world origin, where the camera offset is large: bring the
    -- player (and a dozen enemies) to (2400, 1700) and let the camera catch up.
    settleZoom(1)
    player.body:setPosition(2400, 1700)
    player.body:setLinearVelocity(0, 0)
    local moved = 0
    for _, L in ipairs(liveEnemies()) do
        if moved < 12 then
            local a = moved / 12 * math.pi * 2
            L.e.body:setPosition(2400 + math.cos(a) * 160, 1700 + math.sin(a) * 120)
            moved = moved + 1
        end
    end
    advance(240)
    for _, z in ipairs({ 1, 2.2, 0.6 }) do
        settleZoom(z)
        killCase("far from origin, zoom " .. z)
    end
    camera.shake(10, 2)
    advance(2)
    killCase("far from origin, shaking")
    settleZoom(1)

    ------------------------------------- check 4: death light in a full frame --
    local function sceneImage()
        love.draw()
        love.graphics.push("all")
        love.graphics.setCanvas(frameCopy)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.origin()
        love.graphics.setShader()
        love.graphics.setBlendMode("replace", "premultiplied")
        love.graphics.draw(scene_canvas)
        love.graphics.pop()
        return frameCopy:newImageData()
    end
    local fullFrame
    do
        local L = onScreenEnemy()
        if not L then
            fullFrame = "no enemy on screen"
        else
            local dx, dy = L.e.body:getPosition()
            enemy.damageEnemy(L.i - 1, 1e6)
            advance(3)
            local px, py = project(dx, dy)
            -- Same frame without the death light: a fully opaque sprite is
            -- drawn as before but leaves the glow pass.
            local with = sceneImage()
            local opacity = L.sprite.opacity
            L.sprite.opacity = 1
            local without = sceneImage()
            L.sprite.opacity = opacity
            -- The glow chain's god rays stretch the light away from the screen
            -- centre, so its brightest pixel need not be on the enemy; but a
            -- light that is really there is about as strong at the enemy as
            -- anywhere, and a misplaced one leaves next to nothing there.
            local reach = 48 * camera.zoom
            local total, peak, near = 0, 0, 0
            for y = 0, H - 1 do
                for x = 0, W - 1 do
                    local r1, g1, b1 = with:getPixel(x, y)
                    local r2, g2, b2 = without:getPixel(x, y)
                    local d = math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2)
                    total = total + d
                    peak = math.max(peak, d)
                    if math.abs(x - px) <= reach and math.abs(y - py) <= reach then near = math.max(near, d) end
                end
            end
            if total < 50 then
                fullFrame = string.format("the death light adds almost nothing to the frame (%.1f)", total)
            elseif near < 0.5 * peak then
                fullFrame = string.format("death light is %.0f%% as strong at the enemy (%.0f, %.0f) as at its peak",
                    near / peak * 100, px, py)
            end
            fullFrame = fullFrame or true
        end
    end

    ---------------------------------------------- check 3: every kill fades --
    local fadeFrames = math.ceil(enemy.DEATH_FADE_TIME * 60)
    local tracked, killFailures, offscreenKills = {}, {}, 0
    local function failKill(t, why)
        if not t.failed then
            t.failed = true
            killFailures[#killFailures + 1] = string.format("enemy %d: %s", t.i, why)
        end
    end
    local remaining = liveEnemies()
    local batch = 0
    while #remaining > 0 or batch == 0 do
        batch = batch + 1
        for k = 1, math.min(10, #remaining) do
            local L = remaining[k]
            local x, y = L.e.body:getPosition()
            local sx, sy = project(x, y)
            local offscreen = sx < 0 or sx > W or sy < 0 or sy > H
            if offscreen then offscreenKills = offscreenKills + 1 end
            tracked[#tracked + 1] = { i = L.i, sprite = L.sprite, x = x, y = y, age = 0 }
            enemy.damageEnemy(L.i - 1, 1e6)
        end
        for _ = 1, 5 do
            advance(1)
            for _, t in ipairs(tracked) do
                t.age = t.age + 1
                local s = t.sprite
                if t.age >= 2 and t.age <= fadeFrames - 2 then
                    if not (s.on and s.currentSpriteIndex and s.opacity and s.opacity > 0 and s.opacity < 1) then
                        failKill(t, "not fading at frame " .. t.age)
                    elseif math.abs(s.x - t.x) > 1e-3 or math.abs(s.y - t.y) > 1e-3 then
                        failKill(t, string.format("fading at (%.0f, %.0f), died at (%.0f, %.0f)", s.x, s.y, t.x, t.y))
                    end
                elseif t.age >= fadeFrames + 3 and not t.done then
                    t.done = true
                    if not enemy.enemies[t.i].released then
                        failKill(t, "not released after fading")
                    elseif s.on or s.currentSpriteIndex then
                        failKill(t, "sprite still drawn after release")
                    end
                end
            end
        end
        remaining = liveEnemies()
    end
    advance(fadeFrames + 10)
    for _, t in ipairs(tracked) do
        if not t.done then
            t.done = true
            if not enemy.enemies[t.i].released then failKill(t, "not released after fading") end
        end
    end

    ---------------------------------------------------------------- results --
    h.check("live sprites follow their bodies", follow.bad == 0, string.format(
        "%d sprite-frames over %d frames, worst %.3g px%s", follow.sprites, follow.frames, follow.worst,
        follow.example and ("; " .. follow.example) or ""))
    h.check("on-screen enemies are treated as on screen", seen.bad == 0, string.format(
        "%d on-screen sprite-frames%s", seen.sprites, seen.example and ("; " .. seen.example) or ""))
    h.check("death light covers the dying sprite, on its body", #cases == 0, string.format(
        "%d kill cases%s", cases.total or 0, #cases > 0 and ("; " .. table.concat(cases, "; ")) or ""))
    h.check("every kill fades in place, then is released", #killFailures == 0, string.format(
        "%d kills (%d off screen)%s", #tracked, offscreenKills,
        #killFailures > 0 and ("; " .. table.concat(killFailures, "; ", 1, math.min(5, #killFailures))) or ""))
    h.check("death light shows in the full frame where the enemy died", fullFrame == true,
        fullFrame ~= true and fullFrame or nil)
end
