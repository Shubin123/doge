--[[
  Which way the player faces, and that what she wears stays on her
  (game/player.lua's getHeading, the princess's clips in
  game/characterAnimator.lua, game/armorModel.lua posing it on
  gfx/3d/princess/rig.lua):

      python3 tests/gpu/run.py --checks --only facing

  For each of the eight directions, with the keys held as you'd hold them:
  1. she turns that way (the sheet column: 1 toward the camera, then
     counter-clockwise on screen) and runs;
  2. let go (a diagonal's keys a few frames apart), she stops still facing
     that way, in her idle.
  Then, drawn into a canvas through the game's own instanced passes, bare and
  in the starter armor:
  3. the idle stands where the walk does (its feet on the walk's planted
     foot, its middle on the walk's);
  4. its armor turns with her: round the eight ways, the armor's width across
     her chest goes up and down with hers (armor posed a quarter turn off
     her, as it was on the shot's frames, is widest where she's narrowest);
  5. it isn't turned: her hair (how much of her back it covers, which side
     of her it hangs) is nearest her walk's that way or one either side.

  Leaves the drawn sprites in dist/gpu-test/checks-facing/facing.png: a row
  per direction, the run then the idle, each bare and then dressed with her
  bare outline over it in green.
]]
return function(h)
    local function check(name, ok, detail)
        h.check(name, ok, detail ~= nil and tostring(detail) or nil)
    end

    player.god = true
    while fire.getAvailableCount() > 0 do fire.removeFireball() end -- (they'd cover her)
    player.lightsOn = false
    enemy.clear() -- (and none still to come: they'd shove her about)
    enemy.spawnQueue = {}
    daynight.setHour(12) -- (so the picture shows what she's wearing)
    var.player_armor = true
    armor.load() -- the starter set on
    h.advance(5)

    -- The keys she's steered with
    local held = {}
    local isDown = love.keyboard.isDown
    love.keyboard.isDown = function(...)
        for i = 1, select("#", ...) do
            if held[select(i, ...)] then return true end
        end
        return false
    end

    local QUIET_X, QUIET_Y = -600, 1200
    local DIRS = { -- the keys for each direction, by sheet column
        { "s" }, { "s", "d" }, { "d" }, { "w", "d" }, { "w" }, { "w", "a" }, { "a" }, { "s", "a" },
    }
    local NAMES = { "down", "down-right", "right", "up-right", "up", "up-left", "left", "down-left" }

    local W, H = love.graphics.getPixelDimensions()
    local canvas = love.graphics.newCanvas(W, H)
    local BOX = 112 -- px each side of her, read back

    -- Just her: every other character hidden while she's drawn
    local hidden = {}
    for _, inst in ipairs(gun_enemies) do
        if inst ~= princess and inst.on then
            hidden[#hidden + 1] = inst
            inst.on = false
        end
    end

    -- Her, drawn as the game draws her (under camera.apply), bare or with what
    -- she wears over her; the box round her feet, as ImageData
    local function draw(dressed)
        characterAnimator.renderWorn()
        characterAnimator.populate()
        love.graphics.push("all")
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.origin()
        camera.apply()
        local fx, fy = love.graphics.transformPoint(princess.x, princess.y)
        if dressed then
            characterAnimator.drawSortedUpTo(math.huge)
        else
            characterAnimator.drawInstances(characterAnimator.shader)
        end
        love.graphics.pop()
        local x0, y0 = math.floor(fx - BOX / 2), math.floor(fy - BOX * 0.9)
        x0, y0 = math.max(0, math.min(W - BOX, x0)), math.max(0, math.min(H - BOX, y0))
        return canvas:newImageData(1, 1, x0, y0, BOX, BOX)
    end

    -- What's drawn of her: a mask, its top and feet (rows), its middle (mean
    -- x, y), and her hair below her head, down her back (from a fifth to a
    -- half of the way down her): how much of her it covers there and how far
    -- right of her middle there it is. Seen from behind it covers her back;
    -- from in front there's none; side-on, it hangs behind her.
    local function shape(img)
        local mask, n, sx, sy, top, feet = {}, 0, 0, 0, BOX, -1
        for y = 0, BOX - 1 do
            for x = 0, BOX - 1 do
                local _, _, _, a = img:getPixel(x, y)
                if a > 0.5 then
                    mask[y * BOX + x] = true
                    n, sx, sy, top, feet = n + 1, sx + x, sy + y, math.min(top, y), math.max(feet, y)
                end
            end
        end
        local s = { mask = mask, n = n, cx = n > 0 and sx / n or 0, cy = n > 0 and sy / n or 0, top = top, feet = feet }
        local m, mx, hn, hx = 0, 0, 0, 0
        for y = top + math.floor((feet - top) / 5), top + math.floor((feet - top) / 2) do
            for x = 0, BOX - 1 do
                if mask[y * BOX + x] then
                    local r, g, b = img:getPixel(x, y)
                    m, mx = m + 1, mx + x
                    -- (yellow: red and green alike, blue well under them; her skin's pink)
                    if r + g > 0.25 and g > r * 0.75 and g < r * 1.3 and b < g * 0.6 then hn, hx = hn + 1, hx + x end
                end
            end
        end
        s.hair = m > 0 and hn / m or 0
        s.hairX = hn > 0 and (hx / hn - mx / m) or 0
        return s
    end

    -- How she's dressed: the dressed drawing's width across her torso against
    -- her own (row by row, from a quarter to half way down her), and a
    -- picture of it with her bare outline over it in green
    local function dressing(dressed, body)
        local m = body.mask
        local picture = love.image.newImageData(BOX, BOX)
        picture:paste(dressed, 0, 0, 0, 0, BOX, BOX)
        for k in pairs(m) do
            if not (m[k - 1] and m[k + 1] and m[k - BOX] and m[k + BOX]) then
                picture:setPixel(k % BOX, math.floor(k / BOX), 0.1, 1, 0.2, 1)
            end
        end
        local tall = body.feet - body.top
        local bw, dw, rows = 0, 0, 0
        for y = body.top + math.floor(tall * 0.35), body.top + math.floor(tall * 0.55) do
            local b0, b1, d0, d1 = BOX, -1, BOX, -1
            for x = 0, BOX - 1 do
                if m[y * BOX + x] then b0, b1 = math.min(b0, x), math.max(b1, x) end
                local _, _, _, a = dressed:getPixel(x, y)
                if a > 0.5 then d0, d1 = math.min(d0, x), math.max(d1, x) end
            end
            if b1 >= b0 and d1 >= d0 then
                bw, dw, rows = bw + b1 - b0 + 1, dw + d1 - d0 + 1, rows + 1
            end
        end
        return { body = rows > 0 and bw / rows or 0, dressed = rows > 0 and dw / rows or 0 }, picture
    end


    local function release(keys)
        if #keys == 2 then -- a diagonal's keys don't come up together
            held[keys[1]] = nil
            h.advance(3)
        end
        held = {}
    end

    -- Her bare and dressed, measured, and the two pictures
    local function look()
        local bare, dressed = draw(false), draw(true)
        local body = shape(bare)
        local fit, picture = dressing(dressed, body)
        return { anim = princess.getCurrentAnimation(), body = body, fit = fit }, bare, picture
    end

    local runs, idles, sheet = {}, {}, {}
    local turned, stopped, idled = {}, {}, {}
    for d, keys in ipairs(DIRS) do
        player.body:setPosition(QUIET_X, QUIET_Y)
        player.body:setLinearVelocity(0, 0)
        camera.snap(player)
        h.advance(20)
        for _, k in ipairs(keys) do held[k] = true end
        h.advance(40)
        if princess.currentDirection ~= d then
            turned[#turned + 1] = NAMES[d] .. "->" .. tostring(princess.currentDirection)
        end
        local bare, picture
        runs[d], bare, picture = look()
        sheet[d] = { bare, picture }

        release(keys)
        h.advance(45)
        if princess.currentDirection ~= d then
            stopped[#stopped + 1] = NAMES[d] .. "->" .. tostring(princess.currentDirection)
        end
        idles[d], bare, picture = look()
        if idles[d].anim ~= "idle" then idled[#idled + 1] = NAMES[d] .. ":" .. tostring(idles[d].anim) end
        sheet[d][3], sheet[d][4] = bare, picture
    end

    -- Her walk, every frame each way (where it stands, and how it looks)
    local walks = {}
    for k = 1, 8 do
        princess.setAnimation("walk")
        princess.setDirection(k)
        walks[k] = {}
        for frame = 1, princess.frameCount() do
            princess.setFrame(frame)
            walks[k][frame] = shape(draw(false))
        end
    end
    princess.setAnimation("idle")

    -- 1, 2: the way she faces
    check("holding the keys turns her each way", #turned == 0, table.concat(turned, " "))
    local ran = 0
    for d = 1, 8 do if runs[d].anim == "run" then ran = ran + 1 end end
    check("and she runs", ran == 8, ran .. " of 8")
    check("letting go, she stops facing the same way", #stopped == 0, table.concat(stopped, " "))
    check("in her idle", #idled == 0, table.concat(idled, " "))

    -- The walk's averages each way: its middle, and its hair
    local mean = {}
    for k = 1, 8 do
        local m = { cx = 0, cy = 0, hair = 0, hairX = 0 }
        for _, s in ipairs(walks[k]) do
            for key in pairs(m) do m[key] = m[key] + s[key] / #walks[k] end
        end
        mean[k] = m
    end

    -- 3: where she stands
    local moved, worst = {}, 0
    for d = 1, 8 do
        local i = idles[d].body
        local dx, dy = i.cx - mean[d].cx, i.cy - mean[d].cy
        worst = math.max(worst, math.abs(dx), math.abs(dy))
        if math.abs(dx) > 4 or math.abs(dy) > 4 then
            moved[#moved + 1] = string.format("%s (%+.1f, %+.1f)", NAMES[d], dx, dy)
        end
    end
    check("the idle stands where the walk does", #moved == 0,
        string.format("worst %.1f px %s", worst, table.concat(moved, " ")))

    -- 4: what she wears fits her
    -- (how closely the armor's width across her chest follows hers, round the
    -- eight ways: 1 in step; armor turned a quarter off her is wide where
    -- she's narrow)
    local function follows(list)
        local n, mb, md = #list, 0, 0
        for _, f in ipairs(list) do mb, md = mb + f.body / n, md + f.dressed / n end
        local sbd, sbb, sdd = 0, 0, 0
        for _, f in ipairs(list) do
            local b, dd = f.body - mb, f.dressed - md
            sbd, sbb, sdd = sbd + b * dd, sbb + b * b, sdd + dd * dd
        end
        return sbb > 0 and sdd > 0 and sbd / math.sqrt(sbb * sdd) or 0
    end
    local lines, runFits, idleFits = {}, {}, {}
    for d = 1, 8 do
        local r, i = runs[d].fit, idles[d].fit
        runFits[d], idleFits[d] = r, i
        lines[#lines + 1] = string.format("%s run %.1f in %.1f, idle %.1f in %.1f", NAMES[d], r.body, r.dressed, i.body, i.dressed)
    end
    h.log("her width and dressed across her chest, run/idle: " .. table.concat(lines, "; "))
    local inRun, inIdle = follows(runFits), follows(idleFits)
    check("her armor turns with her in the idle, as in the run", inIdle >= 0.6,
        string.format("its width follows hers %.2f (the run %.2f)", inIdle, inRun))

    -- 5: the idle isn't turned: its hair (how much shows, and which side of
    -- her it's on) is nearest the walk's that way, or the way either side of
    -- it. Her idle is the settled end of her shot, her head turned a little
    -- to her left of her chest, so it's a little way between two of them.
    local wrong, rows = {}, {}
    for d = 1, 8 do
        local i = idles[d].body
        local best, nearest, row = 0, math.huge, {}
        for k = 1, 8 do
            local dist = math.abs(i.hair - mean[k].hair) * 20 + math.abs(i.hairX - mean[k].hairX)
            row[#row + 1] = string.format("%.1f", dist)
            if dist < nearest then best, nearest = k, dist end
        end
        rows[#rows + 1] = string.format("%s hair %.2f at %+.1f [%s]", NAMES[d], i.hair, i.hairX, table.concat(row, " "))
        local off = (best - d) % 8
        if off ~= 0 and off ~= 1 and off ~= 7 then wrong[#wrong + 1] = NAMES[d] .. "~" .. NAMES[best] end
    end
    local walked = {}
    for k = 1, 8 do walked[k] = string.format("%s %.2f at %+.1f", NAMES[k], mean[k].hair, mean[k].hairX) end
    h.log("the walk's hair: " .. table.concat(walked, "; "))
    h.log("the idle's hair, and how far from the walk's each way: " .. table.concat(rows, "; "))
    check("the idle faces the way she walked", #wrong == 0, table.concat(wrong, " "))

    -- The picture, three times the size
    local ZOOM = 3
    local out = love.image.newImageData(BOX * 4 * ZOOM, BOX * 8 * ZOOM)
    for d, row in ipairs(sheet) do
        for c = 1, 4 do
            local img = row[c]
            for y = 0, BOX - 1 do
                for x = 0, BOX - 1 do
                    local r, g, b, a = img:getPixel(x, y)
                    if a < 0.5 then r, g, b = 0.93, 0.93, 0.9 end
                    for j = 0, ZOOM - 1 do
                        for k = 0, ZOOM - 1 do
                            out:setPixel(((c - 1) * BOX + x) * ZOOM + k, ((d - 1) * BOX + y) * ZOOM + j, r, g, b, 1)
                        end
                    end
                end
            end
        end
    end
    local f = assert(io.open(h.cfg.out .. "/facing.png", "wb"))
    f:write(out:encode("png"):getString())
    f:close()

    for _, inst in ipairs(hidden) do inst.on = true end
    love.keyboard.isDown = isDown
end
