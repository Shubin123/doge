--[[
  Weapon model turntables: renders low-poly 3D weapon models into held-model
  sprite sheets for game/block.lua (gun.lua's GunTool.drawHeldModel), the
  same kind of sheet as gfx/3d/lauchergun.dds and gfx/3d/gun.dds:

    128x128 frames, 16 per row, 2048x3712, one frame per aim heading,
    transparent background, model pivot at frame pixel (60, 60).

  Frame k shows the model pointing exactly where block:getSpriteForHeading
  (default angleOffset) sends an aim that selects frame k, so the models
  need no per-model offset. Models lie on the ground plane and are seen from
  a fixed camera ELEVATION degrees above it, lit by a fixed key light.

  Usage (writes <name>.png per model; build.sh then DXT5-encodes them):

    love tools/weapon_models <out-dir> [model ...]

  Models are built from boxes and cylinders below, in frame pixels: +x is
  the muzzle, +y up, z across.
]]

local ffi = require("ffi")

local FRAME, COLS, SHEET_W, SHEET_H = 128, 16, 2048, 3712
local FRAMES = 455 -- 450 are used by block.new; the rest pad the last row
local PIVOT_X, PIVOT_Y = 60, 60 -- gun.lua draws frames offset by (60, 60)
local ELEVATION = math.rad(55)

-- Colours
local METAL = { 0.30, 0.31, 0.35 }
local DARK = { 0.17, 0.18, 0.21 }
local LIGHT = { 0.55, 0.57, 0.62 }
local BLACK = { 0.09, 0.09, 0.10 }
local NAVY = { 0.16, 0.19, 0.33 }
local WOOD = { 0.52, 0.31, 0.15 }
local DARK_WOOD = { 0.36, 0.20, 0.10 }
local PALE_WOOD = { 0.80, 0.64, 0.40 }
local ORANGE = { 1.00, 0.50, 0.08 }
local STRING = { 0.92, 0.90, 0.82 }
local RED = { 0.85, 0.15, 0.10 }
local WHITE = { 0.95, 0.95, 0.95 }
local GLOW_GREEN = { 0.60, 1.00, 0.15, glow = true } -- unlit accent

---------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------

local Builder = {}
Builder.__index = Builder

local function newBuilder()
    return setmetatable({ verts = {} }, Builder)
end

-- Rotate (x, y, z) by rz about Z (tilts +x up) then ry about Y (+x toward -z).
local function rotate(x, y, z, rz, ry)
    local cz, sz = math.cos(rz or 0), math.sin(rz or 0)
    x, y = x * cz - y * sz, x * sz + y * cz
    local cy, sy = math.cos(ry or 0), math.sin(ry or 0)
    return x * cy + z * sy, y, -x * sy + z * cy
end

function Builder:tri(a, b, c, n, color)
    local alpha = color.glow and 0 or 1 -- alpha 0 marks unlit faces
    for _, p in ipairs({ a, b, c }) do
        table.insert(self.verts, { p[1], p[2], p[3], n[1], n[2], n[3], color[1], color[2], color[3], alpha })
    end
end

function Builder:quad(a, b, c, d, n, color)
    self:tri(a, b, c, n, color)
    self:tri(a, c, d, n, color)
end

-- Box centred at (x, y, z), size (w, h, d), rotated by rz then ry about its centre.
function Builder:box(x, y, z, w, h, d, color, rz, ry)
    local hw, hh, hd = w / 2, h / 2, d / 2
    local function p(px, py, pz)
        local rx, rY, rZ = rotate(px, py, pz, rz, ry)
        return { x + rx, y + rY, z + rZ }
    end
    local function n(nx, ny, nz) return { rotate(nx, ny, nz, rz, ry) } end
    self:quad(p(hw, -hh, -hd), p(hw, hh, -hd), p(hw, hh, hd), p(hw, -hh, hd), n(1, 0, 0), color)
    self:quad(p(-hw, -hh, hd), p(-hw, hh, hd), p(-hw, hh, -hd), p(-hw, -hh, -hd), n(-1, 0, 0), color)
    self:quad(p(-hw, hh, -hd), p(-hw, hh, hd), p(hw, hh, hd), p(hw, hh, -hd), n(0, 1, 0), color)
    self:quad(p(-hw, -hh, hd), p(-hw, -hh, -hd), p(hw, -hh, -hd), p(hw, -hh, hd), n(0, -1, 0), color)
    self:quad(p(-hw, -hh, hd), p(hw, -hh, hd), p(hw, hh, hd), p(-hw, hh, hd), n(0, 0, 1), color)
    self:quad(p(hw, -hh, -hd), p(-hw, -hh, -hd), p(-hw, hh, -hd), p(hw, hh, -hd), n(0, 0, -1), color)
end

-- Cylinder (or cone, r1 = 0) along +x from x0 to x1, centred on (y, z).
function Builder:cylinder(x0, x1, y, z, r0, r1, color, segments)
    segments = segments or 10
    local slope = (r0 - r1) / (x1 - x0)
    for i = 0, segments - 1 do
        local a0, a1 = i / segments * math.pi * 2, (i + 1) / segments * math.pi * 2
        local c0, s0, c1, s1 = math.cos(a0), math.sin(a0), math.cos(a1), math.sin(a1)
        local am = (a0 + a1) / 2
        local len = math.sqrt(1 + slope * slope)
        local n = { slope / len, math.cos(am) / len, math.sin(am) / len }
        self:quad({ x0, y + r0 * c0, z + r0 * s0 }, { x1, y + r1 * c0, z + r1 * s0 },
            { x1, y + r1 * c1, z + r1 * s1 }, { x0, y + r0 * c1, z + r0 * s1 }, n, color)
        self:tri({ x0, y, z }, { x0, y + r0 * c1, z + r0 * s1 }, { x0, y + r0 * c0, z + r0 * s0 }, { -1, 0, 0 }, color)
        if r1 > 0 then
            self:tri({ x1, y, z }, { x1, y + r1 * c0, z + r1 * s0 }, { x1, y + r1 * c1, z + r1 * s1 }, { 1, 0, 0 }, color)
        end
    end
end

-- A thin rod between two points in the ground plane (y fixed).
function Builder:rod(x0, z0, x1, z1, y, h, d, color)
    local dx, dz = x1 - x0, z1 - z0
    self:box((x0 + x1) / 2, y, (z0 + z1) / 2, math.sqrt(dx * dx + dz * dz) + 0.4, h, d, color, 0,
        math.atan2(-dz, dx))
end

---------------------------------------------------------------------------
-- Models (frame pixels, +x muzzle, +y up, z across; pivot at the origin)
---------------------------------------------------------------------------

local MODELS = {}

MODELS.pistol = function(b)
    b:box(2, 9, 0, 36, 8, 7, METAL)                  -- slide
    b:box(2, 13.5, 0, 33, 1, 3, LIGHT)               -- top rib
    b:box(0, 3.5, 0, 30, 5, 6, DARK)                 -- frame
    b:cylinder(20, 24, 9, 0, 1.8, 1.8, BLACK)        -- muzzle
    b:box(-12, -6, 0, 9, 18, 6.5, WOOD, -0.25)       -- grip
    b:box(-12.2, -6, 0, 6, 15, 7, DARK_WOOD, -0.25)  -- grip panel
    b:box(-1, -1.5, 0, 8, 1.5, 2, DARK)              -- trigger guard
    b:box(3, 0.5, 0, 1.5, 4, 2, DARK)
    b:box(-1.5, 0, 0, 1.2, 3, 1.5, BLACK)            -- trigger
    b:box(-14, 13.8, 0, 2, 1.6, 4, BLACK)            -- sights
    b:box(18, 13.6, 0, 1.5, 1.2, 1.5, BLACK)
end

MODELS.smg = function(b)
    b:box(0, 6, 0, 40, 11, 9, METAL)                 -- receiver
    b:box(0, 12.2, 0, 34, 1.5, 4, DARK)              -- top rail
    b:box(0, 6.5, 4.6, 34, 2, 0.4, GLOW_GREEN)       -- acid green stripes
    b:box(0, 6.5, -4.6, 34, 2, 0.4, GLOW_GREEN)
    b:cylinder(20, 28, 7, 0, 3.2, 3.2, DARK)         -- shroud
    b:cylinder(28, 34, 7, 0, 1.8, 1.8, BLACK)        -- barrel
    b:box(8, -10, 0, 6, 22, 5, NAVY, 0.12)           -- magazine
    b:box(-10, -7, 0, 7, 15, 6, DARK, -0.25)         -- grip
    b:box(-28, 9, 3, 18, 1.6, 1.6, DARK)             -- wire stock
    b:box(-28, 9, -3, 18, 1.6, 1.6, DARK)
    b:box(-28, 1.5, 0, 18, 1.6, 1.6, DARK)
    b:box(-37.5, 5, 0, 2.5, 11, 7, BLACK)            -- butt plate
end

MODELS.shotgun = function(b)
    b:cylinder(-6, 48, 8, 0, 2.8, 2.8, METAL)        -- barrel
    b:cylinder(-6, 40, 2.5, 0, 2.4, 2.4, DARK)       -- magazine tube
    b:box(46.5, 11.2, 0, 1.5, 1.2, 1.2, LIGHT)       -- bead sight
    b:box(22, 2.5, 0, 18, 6.5, 7.5, ORANGE)          -- pump
    b:box(19, 2.5, 0, 1, 6.8, 7.8, DARK)             -- pump grooves
    b:box(25, 2.5, 0, 1, 6.8, 7.8, DARK)
    b:box(-13, 5.5, 0, 16, 11, 8, METAL)             -- receiver
    b:box(-12, -1.5, 0, 8, 1.5, 2.5, DARK)           -- trigger guard
    b:box(-25, 4, 0, 10, 7, 6.5, WOOD, -0.1)         -- stock wrist
    b:box(-38, 1.5, 0, 20, 12, 7, WOOD, -0.12)       -- stock
    b:box(-48, 0.3, 0, 2, 12.5, 7.4, BLACK, -0.12)   -- butt pad
end

MODELS.bow = function(b)
    -- Drawn bow: limbs arc across the aim, string pulled back to the nock.
    local SPAN, BEND, NOCK = 46, 12, -28
    local segments = 14
    local function limb(t)
        local x = 6 - BEND * t * t
        local tip = math.max(0, math.abs(t) - 0.85) / 0.15
        return x + 4 * tip * tip - 10, SPAN * t -- slight recurve at the tips
    end
    for i = 0, segments - 1 do
        local t0, t1 = -1 + 2 * i / segments, -1 + 2 * (i + 1) / segments
        local x0, z0 = limb(t0)
        local x1, z1 = limb(t1)
        local thick = 3.4 - 1.6 * math.abs((t0 + t1) / 2)
        b:rod(x0, z0, x1, z1, 0, 4, thick, (i % 2 == 0) and WOOD or DARK_WOOD)
    end
    b:box(-4, 0, 0, 4.5, 5.4, 10, NAVY)               -- grip wrap
    local tx, tz = limb(1)
    b:rod(tx, SPAN, NOCK, 0, 0.5, 0.8, 0.8, STRING)  -- string, pulled back
    b:rod(tx, -SPAN, NOCK, 0, 0.5, 0.8, 0.8, STRING)
    b:cylinder(NOCK, 22, 0.5, 0, 0.9, 0.9, PALE_WOOD, 6) -- arrow shaft
    b:cylinder(22, 30, 0.5, 0, 2.2, 0, LIGHT, 6)     -- arrowhead
    b:box(NOCK + 6, 2.3, 0, 8, 2.6, 0.4, WHITE)      -- fletching
    b:box(NOCK + 6, 0.5, 1.8, 8, 0.4, 2.6, RED)
    b:box(NOCK + 6, 0.5, -1.8, 8, 0.4, 2.6, RED)
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

local FORMAT = {
    { "VertexPosition", "float", 3 },
    { "VertexNormal", "float", 3 },
    { "VertexColor", "float", 4 },
}

local SHADER = [[
uniform float yaw;
uniform float elevation;
uniform vec2 pivot;
varying vec3 viewNormal;

#ifdef VERTEX
attribute vec3 VertexNormal;
vec4 position(mat4 transform_projection, vec4 p) {
    float c = cos(yaw), s = sin(yaw);
    vec3 w = vec3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
    vec3 n = vec3(VertexNormal.x * c + VertexNormal.z * s, VertexNormal.y,
                  -VertexNormal.x * s + VertexNormal.z * c);
    float ce = cos(elevation), se = sin(elevation);
    float up = w.y * ce - w.z * se;          // screen up
    float toward = w.y * se + w.z * ce;      // toward the camera
    viewNormal = vec3(n.x, n.y * ce - n.z * se, n.y * se + n.z * ce);
    // Pixel coords through LOVE's own projection (it handles the canvas
    // flip); its ortho z range is [-10, 10] with larger z nearer.
    return transform_projection * vec4(pivot.x + w.x, pivot.y - up, toward * 0.1, 1.0);
}
#endif

#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    if (color.a < 0.5) return vec4(color.rgb, 1.0); // unlit accent
    vec3 n = normalize(viewNormal);
    vec3 key = normalize(vec3(-0.4, 0.8, 0.45));
    vec3 fill = normalize(vec3(0.7, 0.1, 0.4));
    float diffuse = max(dot(n, key), 0.0);
    float spec = pow(max(dot(reflect(-key, n), vec3(0.0, 0.0, 1.0)), 0.0), 16.0);
    vec3 lit = color.rgb * (0.38 + 0.75 * diffuse + 0.22 * max(dot(n, fill), 0.0)) + 0.22 * spec;
    return vec4(lit, 1.0);
}
#endif
]]

-- Screen heading block:getSpriteForHeading maps to 0-based frame k (centre of
-- its 1-degree bin), as the yaw that points the model's +x along it.
local function frameYaw(k)
    local theta = k >= 156 and k - 155.5 or k + 244.5
    theta = math.rad(theta % 360)
    local vx, vy = -math.cos(theta), math.sin(theta) -- aim on screen, y down
    return math.atan2(-vy / math.sin(ELEVATION), vx)
end

local function renderSheet(name, shader, msaaCanvas, resolveCanvas)
    local b = newBuilder()
    MODELS[name](b)
    local mesh = love.graphics.newMesh(FORMAT, b.verts, "triangles", "static")
    local sheet = love.image.newImageData(SHEET_W, SHEET_H)

    shader:send("elevation", ELEVATION)
    shader:send("pivot", { PIVOT_X, PIVOT_Y })
    for k = 0, FRAMES - 1 do
        shader:send("yaw", frameYaw(k))
        love.graphics.setCanvas({ msaaCanvas, depth = true })
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setDepthMode("less", true)
        love.graphics.setBlendMode("replace", "premultiplied")
        love.graphics.setShader(shader)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(mesh)
        love.graphics.setShader()
        love.graphics.setDepthMode()

        -- Resolve the multisampled frame, then read it back
        love.graphics.setCanvas(resolveCanvas)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.draw(msaaCanvas)
        love.graphics.setCanvas()
        sheet:paste(resolveCanvas:newImageData(), (k % COLS) * FRAME, math.floor(k / COLS) * FRAME, 0, 0, FRAME, FRAME)
    end
    love.graphics.setBlendMode("alpha")
    return sheet
end

-- Edge samples resolve to premultiplied colour; the game draws straight alpha.
local function unpremultiply(img)
    local px = ffi.cast("uint8_t*", img:getPointer())
    for i = 0, img:getWidth() * img:getHeight() - 1 do
        local a = px[i * 4 + 3]
        if a > 0 and a < 255 then
            for c = 0, 2 do
                px[i * 4 + c] = math.min(255, math.floor(px[i * 4 + c] * 255 / a + 0.5))
            end
        end
    end
end

-- Bleed edge colour into transparent padding so DXT5's shared per-block
-- colours don't darken sprite edges (tools/atlas_lib.dilate_alpha_padding).
local function dilate(img, iterations)
    local w, h = img:getDimensions()
    local px = ffi.cast("uint8_t*", img:getPointer())
    local n = w * h
    local rgb = ffi.new("float[?]", n * 3)
    local known, nextKnown = ffi.new("uint8_t[?]", n), ffi.new("uint8_t[?]", n)
    for i = 0, n - 1 do
        rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2] = px[i * 4], px[i * 4 + 1], px[i * 4 + 2]
        known[i] = px[i * 4 + 3] > 0 and 1 or 0
    end
    for _ = 1, iterations do
        ffi.copy(nextKnown, known, n)
        for y = 0, h - 1 do
            for x = 0, w - 1 do
                local i = y * w + x
                if known[i] == 0 then
                    local sr, sg, sb, c = 0, 0, 0, 0
                    for dy = -1, 1 do
                        local yy = y + dy
                        if yy >= 0 and yy < h then
                            for dx = -1, 1 do
                                local xx = x + dx
                                if (dx ~= 0 or dy ~= 0) and xx >= 0 and xx < w and known[yy * w + xx] == 1 then
                                    local j = (yy * w + xx) * 3
                                    sr, sg, sb, c = sr + rgb[j], sg + rgb[j + 1], sb + rgb[j + 2], c + 1
                                end
                            end
                        end
                    end
                    if c > 0 then
                        rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2] = sr / c, sg / c, sb / c
                        nextKnown[i] = 1
                    end
                end
            end
        end
        known, nextKnown = nextKnown, known
    end
    for i = 0, n - 1 do
        for c = 0, 2 do
            px[i * 4 + c] = math.floor(math.max(0, math.min(255, rgb[i * 3 + c])))
        end
    end
end

function love.load(args)
    local outDir = assert(args[1], "usage: love tools/weapon_models <out-dir> [model ...]")
    local names = {}
    for i = 2, #args do names[#names + 1] = args[i] end
    if #names == 0 then names = { "pistol", "smg", "shotgun", "bow" } end

    local msaa = math.min(8, love.graphics.getSystemLimits().canvasmsaa)
    local msaaCanvas = love.graphics.newCanvas(FRAME, FRAME, { msaa = msaa })
    local resolveCanvas = love.graphics.newCanvas(FRAME, FRAME)
    local shader = love.graphics.newShader(SHADER)

    for _, name in ipairs(names) do
        assert(MODELS[name], "unknown model " .. name)
        local sheet = renderSheet(name, shader, msaaCanvas, resolveCanvas)
        unpremultiply(sheet)
        dilate(sheet, 4)
        local path = outDir .. "/" .. name .. ".png"
        local f = assert(io.open(path, "wb"))
        f:write(sheet:encode("png"):getString())
        f:close()
        print("wrote " .. path)
    end
    love.event.quit()
end
