--[[
  Suck light: when an enemy dies, its light leaves the body as a handful of
  glowing motes that burst outward, then are pulled into the player, spiralling
  in and warming from the enemy's colour to the player's; each one flares at the
  player as it is absorbed.

  Every mote and flare is one instance of shaders/suck_light.glsl, all drawn
  in a single call. Each mote also lights the ground it passes through the
  lighting shader (shadow.lua), and its solid core makes the GI pass treat it
  as a light source. Brightness follows var.tracer_brightness.

  enemy.lua calls suckLight.spawn on a death; main.lua updates it before the
  lighting upload, and draw.lua draws it in world space after the bullets.
]]
local suckLight = {}

suckLight.MOTES_PER_DEATH = 7
suckLight.ENEMY_COLOR = { 0.7, 0.25, 1.0 }  -- the light as it leaves the enemy...
suckLight.PLAYER_COLOR = { 1.0, 0.85, 0.5 } -- ...and as it reaches the player
suckLight.RADIUS = 15                       -- glow reach of a mote, world px
suckLight.LIGHT = 0.5                       -- point light per mote (the player's key light is 1.0)
suckLight.TRAIL = 14                        -- trail samples behind each mote
suckLight.FLARE_TIME = 0.35                 -- seconds a flare at the player lasts

suckLight.t = 0
local motes, flares = {}, {}
local rows, rowPool = {}, {}

local FORMAT = {
    {"InstSeg", "float", 4},    -- tail.xy, head.xy
    {"InstColor", "float", 4},  -- rgb, intensity
    {"InstParams", "float", 2}, -- radius, phase
}

local function grow(count)
    suckLight.capacity = math.max(count, suckLight.capacity * 2)
    suckLight.instances = love.graphics.newMesh(FORMAT, suckLight.capacity, nil, "stream")
    for _, attribute in ipairs(FORMAT) do
        suckLight.mesh:attachAttribute(attribute[1], suckLight.instances, "perinstance")
    end
end

function suckLight.load()
    motes, flares = {}, {}
    suckLight.shader = love.graphics.newShader(love.filesystem.read("shaders/suck_light.glsl"))
    suckLight.mesh = love.graphics.newMesh({{"VertexPosition", "float", 2}},
        {{0, -1}, {1, -1}, {1, 1}, {0, 1}}, "fan", "static")
    suckLight.capacity = 0
    grow(64)
end

--- Release a dead enemy's light at (x, y).
function suckLight.spawn(x, y)
    local n = suckLight.MOTES_PER_DEATH
    for i = 1, n do
        local a = (i / n + math.random() * 0.15) * math.pi * 2
        local burst = 140 + math.random() * 100
        motes[#motes + 1] = {
            x = x, y = y,
            vx = math.cos(a) * burst, vy = math.sin(a) * burst,
            age = 0,
            phase = a * 3,
            spin = (i % 2 == 0) and 1 or -1, -- half spiral in each way
            trail = {},
        }
    end
end

local function mix(a, b, t)
    return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

function suckLight.update(dt)
    if #motes == 0 and #flares == 0 then return end
    suckLight.t = suckLight.t + dt
    local px, py = player.body:getPosition()
    local brightness = math.min(1, var.tracer_brightness or 1)

    for i = #motes, 1, -1 do
        local m = motes[i]
        m.age = m.age + dt
        local dx, dy = px - m.x, py - m.y
        local d = math.sqrt(dx * dx + dy * dy) + 1e-6
        m.start = m.start or d

        -- The pull ramps up with age: a moment of drifting outward, then
        -- sucked in hard. The sideways swirl (fading out) makes them spiral.
        local pull = 700 + 7000 * m.age * m.age
        local swirl = 320 * m.spin * math.max(0, 1 - 1.5 * m.age)
        m.vx = m.vx + (dx / d * pull - dy / d * swirl) * dt
        m.vy = m.vy + (dy / d * pull + dx / d * swirl) * dt
        local drag = math.exp(-2.5 * dt)
        m.vx, m.vy = m.vx * drag, m.vy * drag

        -- Newest trail sample first; reuse the sample that falls off the end.
        local sample = #m.trail >= suckLight.TRAIL and table.remove(m.trail) or {}
        sample[1], sample[2] = m.x, m.y
        table.insert(m.trail, 1, sample)

        local step = math.sqrt(m.vx * m.vx + m.vy * m.vy) * dt
        if d <= math.max(14, step) or m.age > 4 then
            table.remove(motes, i)
            flares[#flares + 1] = { age = 0 }
        else
            m.x, m.y = m.x + m.vx * dt, m.y + m.vy * dt
            m.progress = math.max(0, math.min(1, 1 - d / m.start))
            shadow.addTransientLight(m.x, m.y, suckLight.LIGHT * brightness, 90)
        end
    end

    for i = #flares, 1, -1 do
        local f = flares[i]
        f.age = f.age + dt
        if f.age >= suckLight.FLARE_TIME then table.remove(flares, i) end
    end
end

local function row(i)
    local r = rowPool[i]
    if not r then
        r = {}
        rowPool[i] = r
    end
    rows[i] = r
    return r
end

--- Draw every mote and flare (world space, under camera.apply).
function suckLight.draw()
    local brightness = var.tracer_brightness or 1
    local n = #motes + #flares
    if n == 0 or brightness <= 0 then return end
    if n > suckLight.capacity then grow(n) end

    for i, m in ipairs(motes) do
        local tail = m.trail[#m.trail]
        local r = row(i)
        r[1], r[2] = tail and tail[1] or m.x, tail and tail[2] or m.y
        r[3], r[4] = m.x, m.y
        r[5], r[6], r[7] = mix(suckLight.ENEMY_COLOR, suckLight.PLAYER_COLOR, m.progress or 0)
        r[8] = math.min(1, m.age / 0.1) -- fade in as it leaves the body
        r[9], r[10] = suckLight.RADIUS, m.phase
    end
    local px, py = player.body:getPosition()
    for j, f in ipairs(flares) do
        local k = f.age / suckLight.FLARE_TIME
        local r = row(#motes + j)
        r[1], r[2], r[3], r[4] = px, py, px, py
        r[5], r[6], r[7] = suckLight.PLAYER_COLOR[1], suckLight.PLAYER_COLOR[2], suckLight.PLAYER_COLOR[3]
        r[8] = (1 - k) * 0.9
        r[9], r[10] = 14 + 36 * k, j
    end
    for i = n + 1, #rows do rows[i] = nil end
    suckLight.instances:setVertices(rows)

    local cr, cg, cb, ca = love.graphics.getColor()
    local blend, alphamode = love.graphics.getBlendMode()
    local shader = love.graphics.getShader()
    suckLight.shader:send("time", suckLight.t)
    suckLight.shader:send("brightness", math.min(1, brightness))
    love.graphics.setBlendMode("add", "premultiplied")
    love.graphics.setShader(suckLight.shader)
    love.graphics.drawInstanced(suckLight.mesh, n)
    love.graphics.setColor(cr, cg, cb, ca)
    love.graphics.setBlendMode(blend, alphamode)
    love.graphics.setShader(shader)
end

return suckLight
