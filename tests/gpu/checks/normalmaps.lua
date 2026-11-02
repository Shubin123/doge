--[[
  Every standing structure is shaded by a normal map (lib/graphics/normalmap.lua):

      python3 tests/gpu/run.py --checks --only normalmaps

  1. every region sprite that stands up (facades, walls, towers, lamps,
     props, landmarks: all but the flat ones underfoot) has relief in its
     region's normal map;
  2. so do the home map's arches, tree and house, and the car;
  3. and it shows: the same Neon City street lit with normal maps and
     without differs across its facades (Settings > Normal Maps).

  Leaves both frames in dist/gpu-test/checks-normalmaps/.
]]
return function(h)
    player.god = true
    h.advance(5)

    -- What share of a sprite's texels lean some way (not facing straight out)
    local function relief(data, x, y, w, ht)
        local art, leaning = 0, 0
        for py = y, y + ht - 1 do
            for px = x, x + w - 1 do
                local r, g, _, a = data:getPixel(px, py)
                if a > 0 then
                    art = art + 1
                    if math.abs(r - 0.5) + math.abs(g - 0.5) > 0.06 then leaning = leaning + 1 end
                end
            end
        end
        return art > 0 and leaning / art or 0, art
    end

    -- 1. Region sprites
    local sprites, flatOnes, worst, worstName, missing = 0, 0, 1, nil, {}
    for _, r in ipairs(regions.list) do
        if r.sprites then
            local data = r.normalImage:newImageData()
            for name, s in pairs(r.sprites) do
                if r.flatSet[name] then
                    flatOnes = flatOnes + 1
                else
                    sprites = sprites + 1
                    local x, y, w, ht = s.quad:getViewport()
                    local share, art = relief(data, x, y, w, ht)
                    if art == 0 or share < 0.1 then missing[#missing + 1] = r.id .. "/" .. name end
                    if share < worst then worst, worstName = share, r.id .. "/" .. name end
                end
            end
        end
    end
    h.check("every standing region sprite has a normal map with relief", #missing == 0 and sprites > 0,
        string.format("%d sprites (and %d flat ones underfoot); least relief %.0f%% (%s)%s", sprites, flatOnes,
            worst * 100, tostring(worstName), #missing > 0 and ("; none on " .. table.concat(missing, ", ")) or ""))

    -- 2. Home
    local function sheet(label, image, quads)
        local data = image:newImageData()
        local least = 1
        for _, q in ipairs(quads) do
            local x, y, w, ht = q:getViewport()
            local share, art = relief(data, x, y, w, ht)
            if art > 0 then least = math.min(least, share) end
        end
        h.check(label .. " have a normal map with relief", least >= 0.1, string.format("least relief %.0f%%", least * 100))
    end
    sheet("the arches", map.tiles3.normals, { map.tiles3.quads[1] })
    sheet("the tree", map.tiles4.normals, { map.tiles4.quads[1] })
    sheet("the house", map.tiles5.normals, { map.tiles5.quads[1] })
    sheet("the car's frames", car.normals, car.blockInstance.animation.quads)

    -- 3. It shows
    for _, e in ipairs(enemy.enemies) do
        if not e.dead then e:killEnemy() end
    end
    for _, r in ipairs(regions.list) do
        if r.id == "neon" then regions.teleport(r) end
    end
    player.body:setPosition(player.body:getX() + 600, player.body:getY() - 700) -- up a street of facades
    camera.snap(player)
    daynight.setHour(22)
    local function frame(on)
        var.normal_maps = on
        h.advance(3)
        return scene_canvas:newImageData()
    end
    local lit, flat = frame(true), frame(false)
    h.capture("street_flat")
    var.normal_maps = true
    h.advance(3)
    h.capture("street_normals")
    local w, ht = lit:getDimensions()
    local differ = 0
    for y = 0, ht - 1, 2 do
        for x = 0, w - 1, 2 do
            local r1, g1, b1 = lit:getPixel(x, y)
            local r2, g2, b2 = flat:getPixel(x, y)
            if math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2) > 0.05 then differ = differ + 1 end
        end
    end
    local share = differ / (math.ceil(w / 2) * math.ceil(ht / 2))
    h.check("and it shows on the facades", share > 0.02,
        string.format("%.1f%% of the street lit differently without them", share * 100))
end
