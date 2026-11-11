--[[
  The Castle's Castellan (game/castellan.lua) and the Sanctum's Choir
  (game/choir.lua), fought through every move with a full frame drawn each
  step, then drawn again as a client draws them from the snapshot:

      python3 tests/gpu/run.py --checks --only bosses

  The Castellan:
  1. she waits on guard while you're far, and wakes when you come near;
  2. her combo, her thrown crescent and her dash (crouch, dash, lunge) each
     happen, and each hurts you;
  3. a player's bullet reaches her;
  4. hurt faster than she mends, she reels, and takes 1.6x while she does;
  5. at 70% her guard comes: swordsmen close in and cut, the archer keeps
     back and shoots; one killed leaves a gem, fades and goes; at 40% more
     come, and under half health she's angry;
  6. a client draws her and her guard from the snapshot (through JSON);
  7. brought down, her guard falls with her, she goes, the Castle is beaten
     and none of her parts are left to shoot at.
  The Choir:
  8. it waits while you're far, and wakes when you come near;
  9. every member's every move runs to its end: the Seraph's hymn and gaze,
     the Ophan's halo, well and ward, the Cherub's charge and spit. The
     shooting ones shoot, the charge hurts you, the well pulls you to its
     heart and burns you there, the warded one takes a quarter, and the
     ward's beam is drawn (it once crashed the frame);
  10. a player's bullet reaches a member;
  11. one brought down falls, you're told it will rise, and it rises again
      with 40%;
  12. a client draws it from the snapshot (through JSON): the fallen one,
      the ward's beam and all;
  13. all three down together silence it: it goes, and the Sanctum is
      beaten.

  Leaves frames of each in dist/gpu-test/checks-bosses/.
]]
local json = require("util/json")

return function(h)
    player.god = true
    h.advance(10)
    enemy.restore({ slots = {} })
    local W, H = h.cfg.width, h.cfg.height

    -- Somewhere with room to fight: nothing standing within r of (x, y)
    local function clear(x, y, r)
        local blocked = false
        world:queryBoundingBox(x - r, y - r, x + r, y + r, function(f)
            if f:isSensor() or f:getBody():getType() ~= "static" then return true end
            for sx = x - r, x + r, 24 do
                for sy = y - r, y + r, 24 do
                    if f:testPoint(sx, sy) then
                        blocked = true
                        return false
                    end
                end
            end
            return true
        end)
        return not blocked
    end
    local bx, by
    for _, p in ipairs({ { -800, 1400 }, { -1300, 1900 }, { 600, 2200 }, { -1400, -1300 }, { 2800, 2200 } }) do
        if clear(p[1], p[2], 420) then
            bx, by = p[1], p[2]
            break
        end
    end
    h.check("there's clear ground to fight on", bx ~= nil)
    if not bx then return end

    local function stand(x, y)
        player.body:setPosition(x, y)
        player.body:setLinearVelocity(0, 0)
        camera.snap(player)
    end
    local function waitFor(cond, frames)
        for _ = 1, frames or 300 do
            if cond() then return true end
            h.advance(1)
        end
        return cond()
    end
    local function contains(list, x)
        for _, v in ipairs(list) do
            if v == x then return true end
        end
        return false
    end
    local function dist(x1, y1, x2, y2)
        return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
    end

    -- What hurt you (god mode still calls player.hurt, which then does
    -- nothing), and what was being fought when it did
    local hurts, hurtWho = {}, nil
    local realHurt = player.hurt
    player.hurt = function(amount, dir, kind)
        hurts[#hurts + 1] = { amount = amount, kind = kind, by = hurtWho and hurtWho() }
        return realHurt(amount, dir, kind)
    end
    local function hurtBy(by, kind)
        for _, r in ipairs(hurts) do
            if (by == nil or r.by == by) and (kind == nil or r.kind == kind) then return true end
        end
        return false
    end
    -- Hostile shots, gems dropped, and what you're told
    local shots, drops, said = 0, 0, {}
    local newBullet = bullet.new
    bullet.new = function(params)
        if params.hostile then shots = shots + 1 end
        return newBullet(params)
    end
    local drop = xp.drop
    xp.drop = function(...)
        drops = drops + 1
        return drop(...)
    end
    local notify = inventory.notify
    inventory.notify = function(text, ...)
        said[#said + 1] = tostring(text)
        return notify(text, ...)
    end

    -- A player's bullet from (x, y) at (tx, ty)
    local function fire(x, y, tx, ty)
        return bullet.new({ pos = vec2.new(x, y), dir = vec2.new(tx - x, ty - y), speed = 900, lifetime = 1,
            damage = 4 })
    end

    -- What a client draws of M from the host's snapshot, sent as JSON: the
    -- pieces it puts in the draw list, drawn into a canvas round (x, y).
    -- Returns how many pieces, how many pixels they covered, and any error.
    local function clientDraw(M, x, y)
        local data = json.decode(json.encode(M.getNetworkData()))
        local was = var.multiplayer
        var.multiplayer = 2
        local list = dynamic_draw_list
        local n0 = #list
        local ok, err = pcall(function()
            M.applyNetworkData(data)
            M.update(1 / 60)
            M.populate()
        end)
        local pieces = {}
        for i = n0 + 1, #list do pieces[#pieces + 1] = list[i] end
        for i = #list, n0 + 1, -1 do list[i] = nil end
        var.multiplayer = was
        if not ok then return 0, 0, err end
        table.sort(pieces, function(p, q) return p.sort_y < q.sort_y end)
        local canvas = love.graphics.newCanvas(W, H)
        love.graphics.push("all")
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.origin()
        love.graphics.translate(W / 2 - x, H / 2 - y)
        ok, err = pcall(function()
            for _, d in ipairs(pieces) do M.drawPiece(d) end
        end)
        love.graphics.pop()
        if not ok then return #pieces, 0, err end
        local covered = 0
        canvas:newImageData():mapPixel(function(_, _, r, g, b, a)
            if a > 0 then covered = covered + 1 end
            return r, g, b, a
        end)
        return #pieces, covered
    end

    ----------------------------------------------------------------------------
    -- The Castellan
    ----------------------------------------------------------------------------
    local a = castellan.spawnAt(bx - 150, by, "castle")
    hurtWho = function() return a.state end
    stand(bx + 1100, by)
    h.advance(20)
    h.check("castellan: she waits on guard while you're far", a.state == "wait", a.state)
    stand(bx + 150, by)
    h.advance(10)
    h.check("castellan: she wakes when you come near", a.state ~= "wait", a.state)

    -- Every move: her and you stood apart, close (her combo) or further (her
    -- crescent, her dash), each time she's between moves
    local seen, shot = {}, {}
    local gaps = { 60, 380, 300, 60, 420 }
    local k, since = 0, math.huge
    for _ = 1, 3600 do
        seen[a.state] = true
        if seen.combo and seen.throw and seen.crouch and seen.dash and seen.lunge then break end
        since = since + 1
        if (a.state == "advance" or a.state == "rest") and since > 75 then
            k, since = k % #gaps + 1, 0
            a.body:setPosition(bx - gaps[k] / 2, by)
            a.body:setLinearVelocity(0, 0)
            stand(bx + gaps[k] / 2, by)
        end
        if a.state == "crouch" and a.t > 0.3 and not shot.crouch then
            shot.crouch = true
            h.capture("castellan_dash_line")
        elseif #a.waves > 0 and not shot.waves then
            shot.waves = true
            h.capture("castellan_crescent")
        else
            h.advance(1)
        end
    end
    for _, s in ipairs({ "combo", "throw", "crouch", "dash", "lunge" }) do
        h.check("castellan: her " .. s .. " happens", seen[s])
    end
    h.check("castellan: her combo hurts you", hurtBy("combo", "blow"))
    h.check("castellan: her dash hurts you", hurtBy("dash", "blow"))
    h.check("castellan: her crescent hurts you", hurtBy(nil, "energy"))

    local function between()
        return waitFor(function() return a.state == "advance" or a.state == "rest" end, 300)
    end

    -- A bullet, from the side, at her middle
    between()
    a.body:setPosition(bx, by)
    a.body:setLinearVelocity(0, 0)
    stand(bx + 300, by)
    h.advance(1)
    local before = a.health
    fire(a.x + 140, a.y - 42, a.x, a.y - 42)
    h.advance(12)
    h.check("castellan: a player's bullet reaches her", a.health < before,
        string.format("health %.0f -> %.0f", before, a.health))

    -- Reeling
    between()
    bosses.hit(a.part, 40, a.x, a.y - 40)
    h.advance(2)
    h.check("castellan: hurt faster than she mends, she reels", a.state == "reel", a.state)
    before = a.health
    bosses.hit(a.part, 10, a.x, a.y - 40)
    h.check("castellan: reeling, she takes 1.6x", math.abs(before - a.health - 16) < 1e-6,
        string.format("10 took %.1f", before - a.health))

    -- Her guard
    waitFor(function() return a.state ~= "reel" end)
    h.advance(1) -- (her weak spot is set as each step starts)
    bosses.hit(a.part, a.health - a.max_health * 0.69, a.x, a.y - 40)
    waitFor(function() return #a.guards > 0 end, 400)
    local swords, bows = 0, 0
    for _, g in ipairs(a.guards) do
        if g.kind == "sword" then swords = swords + 1 else bows = bows + 1 end
    end
    h.check("castellan: at 70% her guard comes", swords == 2 and bows == 1,
        string.format("%d swords, %d bows", swords, bows))

    -- (each guard's attack has to end too: one once stuck in its first, its
    -- animation overwritten with standing idle the step it began)
    local gseen, shots0, last = {}, shots, {}
    local attacks = { cut = true, chop = true, shoot = true }
    stand(a.x + 120, a.y)
    for i = 1, 1200 do
        for _, g in ipairs(a.guards) do
            gseen[g.kind .. " " .. g.state] = true
            if attacks[last[g]] and g.state == "come" then gseen[g.kind .. " again"] = true end
            last[g] = g.state
        end
        if gseen["sword again"] and gseen["bow again"] and shots > shots0 then break end
        if i % 90 == 0 then
            local px, py = player.body:getPosition()
            stand(px, py)
        end
        if gseen["bow shoot"] and not shot.guard then
            shot.guard = true
            h.capture("castellan_guard")
        else
            h.advance(1)
        end
    end
    local states = {}
    for key in pairs(gseen) do states[#states + 1] = key end
    table.sort(states)
    states = "seen: " .. table.concat(states, ", ")
    h.check("castellan: her swordsmen close in and cut, and go again",
        (gseen["sword cut"] or gseen["sword chop"]) and gseen["sword again"], states)
    h.check("castellan: her archer keeps back and shoots, and goes again",
        gseen["bow shoot"] and shots > shots0 and gseen["bow again"], (shots - shots0) .. " arrows; " .. states)

    local g = a.guards[1]
    local drops0 = drops
    bosses.hit(g.part, 100, g.x, g.y - 20)
    h.advance(2)
    h.check("castellan: a guard can be killed, and leaves a gem", g.dying and drops > drops0)
    waitFor(function() return not contains(a.guards, g) end, 300)
    h.check("castellan: a dead guard fades and goes", not contains(a.guards, g) and g.body == nil)

    local n = #a.guards
    waitFor(function() return a.state ~= "reel" end)
    h.advance(1) -- (her weak spot is set as each step starts)
    bosses.hit(a.part, a.health - a.max_health * 0.39, a.x, a.y - 40)
    waitFor(function() return #a.guards > n end, 400)
    h.check("castellan: at 40% more of her guard comes", #a.guards > n, n .. " -> " .. #a.guards)
    h.advance(1)
    h.check("castellan: under half health she's angry", a.angry == true)
    stand(a.x + 100, a.y)
    h.advance(20)
    h.capture("castellan_angry")

    -- As a client sees her
    local pieces, covered, err = clientDraw(castellan, a.x, a.y - 40)
    local net = castellan.net[1]
    h.check("castellan: a client draws her and her guard from the snapshot",
        not err and net and #net.guards == #a.guards and pieces >= 2 + #a.guards and covered > 1000,
        err or string.format("%d pieces, %d px", pieces, covered))
    castellan.applyNetworkData({})

    -- Brought down
    local guards = {}
    for i, o in ipairs(a.guards) do guards[i] = o end
    bosses.hit(a.part, 10000, a.x, a.y - 40)
    h.advance(2)
    local fell = true
    for _, o in ipairs(guards) do fell = fell and o.dying == true end
    h.check("castellan: brought down, her guard falls with her", a.dying ~= nil and fell)
    h.capture("castellan_down")
    waitFor(function() return a.gone end, 400)
    h.check("castellan: she goes, and the Castle is beaten",
        a.gone and #castellan.live == 0 and bosses.beaten.castle == true)
    local left = 0
    for _, p in ipairs(bosses.parts) do
        if p.boss == a or contains(guards, p.boss) then left = left + 1 end
    end
    h.check("castellan: none of her parts are left to shoot at", left == 0, left .. " left")

    ----------------------------------------------------------------------------
    -- The Choir
    ----------------------------------------------------------------------------
    local c = choir.spawnAt(bx, by, "sanctum")
    local m = {}
    for _, o in ipairs(c.members) do m[o.def.id] = o end
    stand(bx + 1100, by)
    h.advance(20)
    h.check("choir: it waits while you're far", c.state == "wait", c.state)
    stand(bx, by + 150)
    h.advance(10)
    h.check("choir: it wakes when you come near", c.state == "awake", c.state)

    -- One move at a time: the rest hold theirs
    local current
    hurtWho = function() return current end
    local function hush()
        for _, o in ipairs(c.members) do o.ready = math.huge end
    end
    local function force(o, move, snapWhen, snapName)
        waitFor(function()
            for _, p in ipairs(c.members) do
                if p.move then return false end
            end
            return true
        end, 400)
        hush()
        o.move, o.mt, o.fired, o.phase = move, 0, 0, nil
        current = o.def.id .. " " .. move
        local shots0 = shots
        for _ = 1, 480 do
            if o.move ~= move then break end
            if snapWhen and snapWhen() then
                snapWhen = nil
                h.capture(snapName)
            else
                h.advance(1)
            end
        end
        h.check("choir: the " .. current .. " runs to its end", o.move ~= move)
        current = nil
        hush()
        return shots - shots0
    end

    hush()
    local fired = force(m.seraph, "hymn", function() return m.seraph.mt > 1 end, "choir_hymn")
    h.check("choir: the seraph's hymn shoots", fired > 0, fired .. " shots")
    fired = force(m.seraph, "gaze")
    h.check("choir: the seraph's gaze shoots", fired > 0, fired .. " shots")
    fired = force(m.ophan, "halo")
    h.check("choir: the ophan's halo shoots", fired > 0, fired .. " shots")
    fired = force(m.cherub, "spit")
    h.check("choir: the cherub's spit shoots", fired > 0, fired .. " shots")
    force(m.cherub, "charge", function() return m.cherub.phase == "tell" and m.cherub.mt > 0.4 end,
        "choir_charge_line")
    h.check("choir: the cherub's charge hurts you", hurtBy("cherub charge", "blow"))

    stand(bx, by + 150)
    h.advance(1)
    force(m.ophan, "well")
    local w = c.wells[1]
    h.check("choir: the ophan's well opens under you", w ~= nil)
    if w then
        waitFor(function() return w.t > 1 end)
        h.capture("choir_well")
        stand(w.x + 120, w.y)
        h.advance(20)
        local px, py = player.body:getPosition()
        local d = dist(px, py, w.x, w.y)
        h.check("choir: the well pulls you to its heart", d < 110, string.format("120 px -> %.0f", d))
        current = "well heart"
        for _ = 1, 40 do
            stand(w.x, w.y)
            h.advance(1)
        end
        h.check("choir: at its heart the well burns you", hurtBy("well heart", "energy"))
        current = nil
    end

    stand(bx, by + 150)
    m.seraph.health = m.seraph.health - 30 -- (the most hurt: the one it wards)
    force(m.ophan, "ward")
    h.advance(1)
    local ward = c.ward
    h.check("choir: the ophan wards the most hurt of the others",
        ward ~= nil and ward.from == m.ophan and ward.target == m.seraph)
    if ward then
        h.capture("choir_ward")
        before = m.seraph.health
        bosses.hit(m.seraph.part, 20, m.seraph.x, m.seraph.y)
        h.check("choir: the warded one takes a quarter", math.abs(before - m.seraph.health - 5) < 1e-6,
            string.format("20 took %.1f", before - m.seraph.health))
    end

    -- A bullet at a member, from close by
    local s = m.cherub
    before = s.health
    fire(s.x + 80, s.y - s.z, s.x, s.y - s.z)
    h.advance(8)
    h.check("choir: a player's bullet reaches a member", s.health < before,
        string.format("health %.0f -> %.0f", before, s.health))

    -- The rite: one down falls, and rises again
    local said0 = #said
    bosses.hit(s.part, 10000, s.x, s.y)
    h.advance(2)
    h.check("choir: one brought down falls", s.fallen == true and s.part == nil)
    local told = false
    for i = said0 + 1, #said do told = told or said[i]:find("will rise again") ~= nil end
    h.check("choir: you're told it will rise again", told, said[#said])
    h.advance(10)
    h.capture("choir_fallen")
    waitFor(function() return not s.fallen end, 60 * 14)
    h.check("choir: it rises again with 40%", not s.fallen and s.health == math.floor(s.max_health * 0.4),
        string.format("%s, health %.0f", s.fallen and "still down" or "up", s.health))
    hush()

    -- As a client sees it: one down, the ward's beam up
    bosses.hit(s.part, 10000, s.x, s.y)
    h.advance(2)
    force(m.ophan, "ward")
    h.advance(1)
    h.check("choir: the ward is up for the client to draw", c.ward ~= nil)
    pieces, covered, err = clientDraw(choir, bx, by)
    h.check("choir: a client draws it from the snapshot",
        not err and choir.net and choir.net.ward ~= nil and pieces == 5 and covered > 1000,
        err or string.format("%d pieces, %d px", pieces, covered))
    choir.applyNetworkData(nil)

    -- All three down together
    for _, o in ipairs(c.members) do
        if not o.fallen then bosses.hit(o.part, 10000, o.x, o.y) end
    end
    h.advance(2)
    h.check("choir: all three down together silence it", c.silenced ~= nil)
    h.capture("choir_silenced")
    waitFor(function() return c.gone end, 300)
    h.check("choir: it goes, and the Sanctum is beaten",
        c.gone and choir.live == nil and bosses.beaten.sanctum == true)
    left = 0
    for _, p in ipairs(bosses.parts) do
        if contains(c.members, p.boss) then left = left + 1 end
    end
    h.check("choir: none of its parts are left to shoot at", left == 0, left .. " left")

    player.hurt, bullet.new, xp.drop, inventory.notify = realHurt, newBullet, drop, notify
end
