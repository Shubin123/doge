--[[
  The armor you can see: every piece is a small 3D model (MODELS, built from
  tubes, balls and boxes on the bones it follows), posed each frame on the
  skeleton of the frame the princess is showing (gfx/3d/princess/rig.lua, from
  tools/princess_rig) and turned the way she's facing.

  It's drawn with the sheets' own camera (55 degrees up, the axis at x 64.5)
  into a canvas the size of a sprite frame, a texel per texel, with a depth
  buffer: only when what's showing changes (armorModel.render, before the
  frame's other targets). characterAnimator draws that canvas straight over
  her with the character shader, so the scene's lights fall on it as on her.

  Her body goes into the depth buffer first (BODY) and draws nothing, so an
  arm in front of the chest plate shows the sprite's arm, and whatever's on
  the far side of her is hidden.

  A piece's bone, in texels: y up it (down an arm or leg is -y), z the way she
  faces, x her left. A model is stretched along its bone to reach the next
  joint.
]]
local rig = require("gfx.3d.princess.rig")

local armorModel = {}

local FRAME = 128
local CENTRE_X, CENTRE_Y = 64.5, 70.5 -- the turntable's axis in the frame
local ELEVATION = math.rad(55)

-- Bones: name, and how long a model built for it assumes it is
local BONES = {
    { "head", 1 }, { "torso", 26 },
    { "armL", 12 }, { "foreL", 13 }, { "armR", 12 }, { "foreR", 13 },
    { "thighL", 16 }, { "shinL", 16 }, { "footL", 1 },
    { "thighR", 16 }, { "shinR", 16 }, { "footR", 1 },
}
local BONE_INDEX = {}
for i, b in ipairs(BONES) do BONE_INDEX[b[1]] = i - 1 end

local JOINT = {}
for i, name in ipairs(rig.joints) do JOINT[name] = (i - 1) * 3 end

local FORMAT = {
    { "VertexPosition", "float", 3 },
    { "VertexNormal", "float", 3 },
    { "VertexBone", "float", 1 },
    { "VertexColor", "float", 4 },
}

local SHADER = [[
#define BONES 12
uniform vec3 bones[BONES * 4]; // each: its x, y and z axes and where it starts
uniform float yaw;
uniform float elevation;
uniform vec2 centre;
varying vec3 viewNormal;

#ifdef VERTEX
attribute vec3 VertexNormal;
attribute float VertexBone;
vec4 position(mat4 transform_projection, vec4 p) {
    int b = int(VertexBone + 0.5) * 4;
    vec3 w = bones[b + 3] + bones[b] * p.x + bones[b + 1] * p.y + bones[b + 2] * p.z;
    vec3 n0 = normalize(bones[b] * VertexNormal.x + bones[b + 1] * VertexNormal.y + bones[b + 2] * VertexNormal.z);
    float c = cos(yaw), s = sin(yaw);
    vec3 v = vec3(w.x * c + w.z * s, w.y, -w.x * s + w.z * c);
    vec3 n = vec3(n0.x * c + n0.z * s, n0.y, -n0.x * s + n0.z * c);
    float ce = cos(elevation), se = sin(elevation);
    float up = v.y * ce - v.z * se;
    float toward = v.y * se + v.z * ce;
    viewNormal = vec3(n.x, n.y * ce - n.z * se, n.y * se + n.z * ce);
    return transform_projection * vec4(centre.x + v.x, centre.y - up, toward * 0.1, 1.0);
}
#endif

#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    if (color.a < 0.25) return vec4(color.rgb, 1.0); // glows: not shaded
    vec3 n = normalize(viewNormal);
    vec3 key = normalize(vec3(-0.4, 0.8, 0.45));
    vec3 fill = normalize(vec3(0.7, 0.1, 0.4));
    float diffuse = max(dot(n, key), 0.0);
    float spec = pow(max(dot(reflect(-key, n), vec3(0.0, 0.0, 1.0)), 0.0), 18.0);
    float gloss = (color.a - 0.5) * 2.0;
    vec3 lit = color.rgb * (0.42 + 0.56 * diffuse + 0.16 * max(dot(n, fill), 0.0)) + (0.03 + 0.3 * gloss) * spec;
    return vec4(lit, 1.0);
}
#endif
]]

--------------------------------------------------------------------------------
-- Building a model
--------------------------------------------------------------------------------

local Model = {}
Model.__index = Model

local function newModel()
    return setmetatable({ verts = {}, boneId = 0, gloss = 0 }, Model)
end

function Model:bone(name)
    self.boneId = assert(BONE_INDEX[name], name)
    return self
end

function Model:vertex(p, n, color)
    local a = color.glow and 0 or 0.5 + self.gloss * 0.5
    local v = self.verts
    v[#v + 1] = { p[1], p[2], p[3], n[1], n[2], n[3], self.boneId, color[1], color[2], color[3], a }
end

function Model:tri(p1, n1, p2, n2, p3, n3, color)
    self:vertex(p1, n1, color)
    self:vertex(p2, n2, color)
    self:vertex(p3, n3, color)
end

local function normalize(x, y, z)
    local l = math.sqrt(x * x + y * y + z * z)
    if l < 1e-6 then return { 0, 1, 0 } end
    return { x / l, y / l, z / l }
end

--- A tube round the bone from y0 to y1, its elliptical section (rx, rz)
--- tapering from one end to the other. opts: x, z (off the bone), n (sides),
--- open (no ends)
function Model:tube(y0, y1, rx0, rz0, rx1, rz1, color, opts)
    opts = opts or {}
    local n, cx, cz = opts.n or 16, opts.x or 0, opts.z or 0
    local slope = ((rx0 + rz0) - (rx1 + rz1)) / 2 / (y1 - y0)
    for i = 0, n - 1 do
        local a0, a1 = i / n * math.pi * 2, (i + 1) / n * math.pi * 2
        local c0, s0, c1, s1 = math.cos(a0), math.sin(a0), math.cos(a1), math.sin(a1)
        local p00, p01 = { cx + rx0 * c0, y0, cz + rz0 * s0 }, { cx + rx0 * c1, y0, cz + rz0 * s1 }
        local p10, p11 = { cx + rx1 * c0, y1, cz + rz1 * s0 }, { cx + rx1 * c1, y1, cz + rz1 * s1 }
        local n0 = normalize(c0 / math.max(rx0, rx1, 0.1), slope, s0 / math.max(rz0, rz1, 0.1))
        local n1 = normalize(c1 / math.max(rx0, rx1, 0.1), slope, s1 / math.max(rz0, rz1, 0.1))
        self:tri(p00, n0, p10, n0, p11, n1, color)
        self:tri(p00, n0, p11, n1, p01, n1, color)
        if not opts.open then
            local down, up = { 0, -1, 0 }, { 0, 1, 0 }
            if y1 < y0 then down, up = up, down end
            self:tri({ cx, y0, cz }, down, p00, down, p01, down, color)
            self:tri({ cx, y1, cz }, up, p11, up, p10, up, color)
        end
    end
    return self
end

--- An ellipsoid at (x, y, z), or `half` of one: "top" or "bottom"
function Model:ball(x, y, z, rx, ry, rz, color, half, n)
    n = n or 14
    local rows = math.ceil(n / 2)
    local first, last = 0, rows - 1
    if half == "top" then last = math.ceil(rows / 2) - 1 end
    if half == "bottom" then first = math.ceil(rows / 2) end
    local function at(i, j)
        local t = i / rows * math.pi
        local a = j / n * math.pi * 2
        local nx, ny, nz = math.sin(t) * math.cos(a), math.cos(t), math.sin(t) * math.sin(a)
        return { x + rx * nx, y + ry * ny, z + rz * nz }, normalize(nx / rx, ny / ry, nz / rz)
    end
    for i = first, last do
        for j = 0, n - 1 do
            local p00, n00 = at(i, j)
            local p01, n01 = at(i, j + 1)
            local p10, n10 = at(i + 1, j)
            local p11, n11 = at(i + 1, j + 1)
            self:tri(p00, n00, p10, n10, p11, n11, color)
            self:tri(p00, n00, p11, n11, p01, n01, color)
        end
    end
    return self
end

local function rotated(x, y, z, pitch, yaw, roll)
    if roll and roll ~= 0 then
        local c, s = math.cos(roll), math.sin(roll)
        x, y = x * c - y * s, x * s + y * c
    end
    if pitch and pitch ~= 0 then
        local c, s = math.cos(pitch), math.sin(pitch)
        y, z = y * c - z * s, y * s + z * c
    end
    if yaw and yaw ~= 0 then
        local c, s = math.cos(yaw), math.sin(yaw)
        x, z = x * c + z * s, -x * s + z * c
    end
    return x, y, z
end

--- A box centred at (x, y, z), turned by pitch (about x), yaw (about y) and
--- roll (about z)
function Model:box(x, y, z, w, h, d, color, pitch, yaw, roll)
    local hw, hh, hd = w / 2, h / 2, d / 2
    local function p(px, py, pz)
        local rx, ry, rz = rotated(px, py, pz, pitch, yaw, roll)
        return { x + rx, y + ry, z + rz }
    end
    local function face(a, b, c, e, nx, ny, nz)
        local n = { rotated(nx, ny, nz, pitch, yaw, roll) }
        self:tri(a, n, b, n, c, n, color)
        self:tri(a, n, c, n, e, n, color)
    end
    face(p(hw, -hh, -hd), p(hw, hh, -hd), p(hw, hh, hd), p(hw, -hh, hd), 1, 0, 0)
    face(p(-hw, -hh, hd), p(-hw, hh, hd), p(-hw, hh, -hd), p(-hw, -hh, -hd), -1, 0, 0)
    face(p(-hw, hh, -hd), p(-hw, hh, hd), p(hw, hh, hd), p(hw, hh, -hd), 0, 1, 0)
    face(p(-hw, -hh, hd), p(-hw, -hh, -hd), p(hw, -hh, -hd), p(hw, -hh, hd), 0, -1, 0)
    face(p(-hw, -hh, hd), p(hw, -hh, hd), p(hw, hh, hd), p(-hw, hh, hd), 0, 0, 1)
    face(p(hw, -hh, -hd), p(-hw, -hh, -hd), p(-hw, hh, -hd), p(hw, hh, -hd), 0, 0, -1)
    return self
end

--- A ring round the bone at height y (a section of radius `thick`). opts: x,
--- z, rz (its depth, if it isn't round), n
function Model:ring(y, r, thick, color, opts)
    opts = opts or {}
    local n, m, cx, cz, rz = opts.n or 18, 6, opts.x or 0, opts.z or 0, opts.rz or r
    local function at(i, j)
        local a, b = i / n * math.pi * 2, j / m * math.pi * 2
        local ca, sa, cb, sb = math.cos(a), math.sin(a), math.cos(b), math.sin(b)
        return { cx + (r + thick * cb) * ca, y + thick * sb, cz + (rz + thick * cb) * sa }, normalize(cb * ca, sb, cb * sa)
    end
    for i = 0, n - 1 do
        for j = 0, m - 1 do
            local p00, n00 = at(i, j)
            local p01, n01 = at(i, j + 1)
            local p10, n10 = at(i + 1, j)
            local p11, n11 = at(i + 1, j + 1)
            self:tri(p00, n00, p10, n10, p11, n11, color)
            self:tri(p00, n00, p11, n11, p01, n01, color)
        end
    end
    return self
end

--- A round rod (or a spike, r1 = 0) between two points
function Model:rod(x0, y0, z0, x1, y1, z1, r0, r1, color, n)
    n = n or 8
    local ax = normalize(x1 - x0, y1 - y0, z1 - z0)
    local u = math.abs(ax[2]) > 0.9 and normalize(1, 0, 0) or normalize(ax[3], 0, -ax[1])
    local v = { ax[2] * u[3] - ax[3] * u[2], ax[3] * u[1] - ax[1] * u[3], ax[1] * u[2] - ax[2] * u[1] }
    local function around(a, px, py, pz, r)
        local c, s = math.cos(a), math.sin(a)
        local nx, ny, nz = u[1] * c + v[1] * s, u[2] * c + v[2] * s, u[3] * c + v[3] * s
        return { px + nx * r, py + ny * r, pz + nz * r }, { nx, ny, nz }
    end
    for i = 0, n - 1 do
        local a0, a1 = i / n * math.pi * 2, (i + 1) / n * math.pi * 2
        local b0, nb0 = around(a0, x0, y0, z0, r0)
        local b1, nb1 = around(a1, x0, y0, z0, r0)
        local t0 = around(a0, x1, y1, z1, r1)
        local t1 = around(a1, x1, y1, z1, r1)
        self:tri(b0, nb0, t0, nb0, t1, nb1, color)
        self:tri(b0, nb0, t1, nb1, b1, nb1, color)
        local back = { -ax[1], -ax[2], -ax[3] }
        self:tri({ x0, y0, z0 }, back, b0, back, b1, back, color)
        if r1 > 0 then self:tri({ x1, y1, z1 }, ax, t1, ax, t0, ax, color) end
    end
    return self
end

--- For each side (s = 1 her left, -1 her right): fn(s, "L" or "R")
function Model:sides(fn)
    fn(self, 1, "L")
    fn(self, -1, "R")
    return self
end

--------------------------------------------------------------------------------
-- The pieces. c is the set's colours: a main, b dark, d trim, e light
--------------------------------------------------------------------------------

local MODELS = {}

local function glow(color) return { color[1], color[2], color[3], glow = true } end

-- Head (hair and all come to about 11 from the middle of it)

MODELS.patched_hood = function(m, c)
    m:bone("head")
    m:ball(0, 1, -0.5, 11, 11.5, 11.5, c.a)
    m:ball(0, -1, 8, 5.4, 6, 3.8, { 0.05, 0.05, 0.07 })       -- the opening
    m:ring(-7, 8.8, 1.8, c.b)                                 -- gathered at the neck
    m:box(7.6, 5, 5, 4.5, 4.5, 1, c.e, 0.1, 0.8)              -- patches
    m:box(-7, 8, -4, 4.5, 3.5, 1, c.d, 0.4, -2.2)
end

MODELS.gardeners_sunhat = function(m, c)
    m:bone("head")
    m:tube(5, 6, 15.5, 15.5, 14.4, 14.4, c.a, { n = 22 })     -- the brim
    m:tube(6, 11, 10.2, 10.2, 9, 9, c.e, { open = true })
    m:ball(0, 11, 0, 9, 3.2, 9, c.e, "top")
    m:ring(6.6, 10, 0.7, c.d)                                 -- its ribbon
    m:box(9.2, 7, 5, 3, 3, 0.9, c.b, 0, 0.6)                  -- and bow
end

MODELS.gas_mask = function(m, c)
    m:bone("head")
    m:ball(0, 0.5, -0.5, 10.6, 11, 11, c.b)
    m:sides(function(self, s)
        self:ball(s * 4.4, 2.5, 9.2, 3.3, 3.3, 2, c.d)            -- eyepieces
        self:ball(s * 4.4, 2.5, 10.4, 2.4, 2.4, 1.4, glow(c.e))
        self:rod(s * 8.5, 0, 3, s * 11, -4, 7.5, 0.9, 0.9, c.a)   -- hoses
    end)
    m:rod(0, -3.5, 9.5, 0, -6, 15, 3.4, 3.4, c.a, 12)         -- the filter
    m:rod(0, -6, 15, 0, -6.8, 16.6, 3.9, 3.9, c.d, 12)
    m:ring(4, 10.6, 0.6, c.a)                                 -- strap
end

MODELS.great_helm = function(m, c)
    m:bone("head")
    m:tube(-9, 7, 10.2, 10.6, 10.6, 11, c.a, { open = true, n = 18 })
    m:ball(0, 7, 0, 10.6, 2.8, 11, c.a, "top", 18)
    m:box(0, 1.5, 10.8, 15, 1.3, 1, { 0.03, 0.03, 0.05 })     -- the sight
    m:box(0, 0, 11, 1.8, 17, 0.8, c.d)                        -- the cross
    m:box(0, 3, 11, 17, 1.4, 0.7, c.d)
    m:ring(-9, 10.3, 0.5, c.d, { rz = 10.7 })
    m:ring(6.9, 10.7, 0.5, c.d, { rz = 11.1 })
    for i = -2, 2 do
        m:box(i * 2.2 + 0.5, -4, 10.8, 0.9, 0.9, 0.7, { 0.04, 0.04, 0.06 }) -- breaths
    end
end

MODELS.holo_visor = function(m, c)
    m:bone("head")
    m:ball(0, 1.5, -1.5, 10.4, 7.5, 9.6, c.b, "top")
    m:ball(0, 1, -1.5, 10.2, 8, 9.4, c.b, "bottom")
    m:ball(0, 2.2, 5.6, 8.8, 2.6, 5, glow(c.e), nil, 14)      -- the holo, across the eyes
    m:ring(3, 10.2, 0.7, c.a)
    m:sides(function(self, s)
        self:box(s * 10.4, 3, 0, 1.8, 5, 4, c.a)
        self:rod(s * 10.4, 5, -1, s * 11.4, 11, -3, 0.6, 0, c.d)  -- aerials
    end)
end

MODELS.halo_circlet = function(m, c)
    m:bone("head")
    m:ring(5.5, 10.2, 0.8, c.e)
    m:ball(0, 6.2, 10.8, 1.6, 2, 1.1, c.d)                    -- the stone
    m:ring(15.5, 8.6, 0.7, { 1, 0.9, 0.55, glow = true }, { n = 22 }) -- the halo, above her
end

-- Shoulders

MODELS.quilted_mantle = function(m, c)
    m:bone("torso")
    m:tube(19, 27, 14, 11.4, 9, 7.6, c.a, { open = true })
    m:ring(19.2, 13.8, 0.7, c.b, { rz = 11.2 })
    m:ring(23, 11.6, 0.45, c.b, { rz = 9.4 })
    m:sides(function(self, s, l)
        self:bone("arm" .. l)
        self:ball(s * 0.8, -1, 0, 5.4, 5.6, 5.6, c.a)
        self:ring(-3.5, 5, 0.5, c.b)
        self:tube(-3, -13, 4.2, 4.2, 3.6, 3.6, c.e, { open = true, n = 10 })
        self:bone("fore" .. l)
        self:tube(1, -11, 3.6, 3.6, 3.2, 3.2, c.a, { open = true, n = 10 })
        self:ring(-11, 3.2, 0.6, c.d, { n = 10 })
        self:bone("torso")
    end)
end

MODELS.ivy_shawl = function(m, c)
    m:bone("torso")
    m:tube(18, 27, 14, 11.8, 9, 7.6, c.a, { open = true })
    local leaves = { { 13, 22, 7 }, { -12, 24, 6 }, { 6, 25, 9 }, { -6, 20, 11 }, { 11, 21, -7 }, { -11, 22, -7 }, { 0, 25, -9 },
        { 13, 19, 2 }, { -13, 19, 1 }, { 3, 19, 11.5 } }
    for i, l in ipairs(leaves) do
        m:box(l[1], l[2], l[3], 5, 0.9, 3.2, i % 2 == 0 and c.e or c.d, 0.5, i * 1.9, 0.5)
    end
    m:sides(function(self, s, l)
        self:bone("arm" .. l)
        self:ball(s * 0.8, -0.5, 0, 5, 5.2, 5.2, c.a)
        self:box(s * 3.8, -3, 2, 4, 0.7, 2.8, c.e, 0.3, s, 0.6)
        self:tube(-3, -13, 4, 4, 3.5, 3.5, c.a, { open = true, n = 10 })
        self:bone("fore" .. l)
        self:tube(1, -11, 3.5, 3.5, 3.1, 3.1, c.b, { open = true, n = 10 })
        for i = 0, 2 do
            self:box(s * 2.8, -2 - i * 4, 1.5 - i, 3.4, 0.7, 2.2, i == 1 and c.d or c.e, 0.4, i * 2 + s, 0.6)
        end
        self:bone("torso")
    end)
end

MODELS.tyre_pauldrons = function(m, c)
    m:sides(function(self, s, l)
        self:bone("arm" .. l)
        self:ring(1, 5.2, 2.4, c.b, { x = s * 1.2, n = 14 })
        self:ring(1, 2.6, 0.7, c.d, { x = s * 1.2, n = 10 })  -- the rim
        for i = 0, 9 do
            local a = i / 10 * math.pi * 2
            self:box(s * 1.2 + math.cos(a) * 7.5, 1, math.sin(a) * 7.5, 0.9, 2.1, 1.7, { 0.05, 0.05, 0.06 }, 0, -a) -- tread
        end
        self:tube(-2, -13, 4, 4, 3.5, 3.5, c.a, { open = true, n = 10 })
        self:bone("fore" .. l)
        self:tube(1, -11, 3.5, 3.5, 3.3, 3.3, c.b, { open = true, n = 10 })
        for i = 0, 2 do
            self:ring(-1.5 - i * 4, 3.5, 0.55, c.d, { n = 10 })  -- wire binding
        end
        self:bone("torso")
    end)
    m:bone("torso")
    m:box(0, 21, 9.5, 19, 2, 1, c.a, 0.2)                    -- straps across
    m:box(0, 21, -9.5, 19, 2, 1, c.a, -0.2)
end

MODELS.steel_pauldrons = function(m, c)
    m:sides(function(self, s, l)
        self:bone("arm" .. l)
        self:ball(s * 1, 0, 0, 6.2, 5.8, 6.4, c.a, "top")
        self:tube(0, -2.6, 6.4, 6.6, 6.6, 6.8, c.a, { x = s * 1, open = true })
        self:tube(-2.6, -5.2, 5.8, 6, 6.2, 6.4, c.a, { x = s * 1, open = true })
        self:ring(0, 6.4, 0.45, c.d, { x = s * 1, rz = 6.6 })
        self:rod(s * 1.5, 4.5, 0, s * 3.4, 10, 0, 1.3, 0, c.d, 8) -- spikes
        self:tube(-4, -13, 4.2, 4.2, 3.7, 3.7, c.a, { open = true, n = 12 })
        self:bone("fore" .. l)
        self:ball(0, 0, 0, 4.3, 4.3, 4.3, c.a, nil, 10)       -- the elbow
        self:ring(0, 4.2, 0.4, c.d, { n = 12 })
        self:tube(-2, -11, 4, 4, 3.7, 3.7, c.a, { open = true, n = 12 })
        self:ring(-11, 3.7, 0.5, c.d, { n = 12 })
        self:bone("torso")
    end)
    m:bone("torso")
    m:ring(26, 8, 0.8, c.d, { rz = 6.9 })                    -- gorget
end

MODELS.arc_epaulets = function(m, c)
    m:sides(function(self, s, l)
        self:bone("arm" .. l)
        self:box(s * 2.2, 2.5, 0, 9.5, 1.8, 10.5, c.b)
        self:box(s * 2.2, 3.7, 0, 8, 0.7, 9, c.a)
        for i = 0, 2 do
            self:box(s * (0.8 + i * 2.2), 4.3, 0, 0.8, 0.7, 9, glow(c.e))
        end
        for i = -2, 2 do
            self:rod(s * 7, 1.5, i * 2.1, s * 8.2, -4, i * 2.3, 0.4, 0.2, glow(c.d), 5) -- arcs hanging off it
        end
        self:tube(1, -13, 3.9, 3.9, 3.5, 3.5, c.a, { open = true, n = 10 })
        self:box(s * 3.9, -6, 0, 0.5, 12, 0.8, glow(c.e))
        self:bone("fore" .. l)
        self:tube(1, -11, 3.5, 3.5, 3.1, 3.1, c.a, { open = true, n = 10 })
        self:ring(-10.5, 3.2, 0.5, glow(c.d), { n = 10 })
        self:bone("torso")
    end)
end

MODELS.vestal_mantle = function(m, c)
    m:bone("torso")
    m:tube(13, 27, 15, 12.5, 9, 7.6, c.a, { open = true })
    m:ring(13.2, 14.8, 0.8, c.d, { rz = 12.3 })
    m:rod(0, 24, -9.5, 0, 2, -14, 6, 0.6, c.a, 8)            -- it comes to a point behind
    m:box(0, 24.5, 9.2, 2.4, 6, 0.9, c.d, -0.3)
    m:box(0, 25, 9.5, 6, 1.8, 0.9, c.d, -0.3)
    m:sides(function(self, s, l)
        self:bone("arm" .. l)
        self:ball(s * 0.8, 0, 0, 5, 4.4, 5.2, c.e, "top")
        self:ring(-0.2, 4.8, 0.5, c.d)
        self:tube(-1, -13, 4.4, 4.4, 4.2, 4.2, c.a, { open = true, n = 10 })
        self:bone("fore" .. l)
        self:tube(1, -11, 4.2, 4.2, 5.8, 5.8, c.a, { open = true, n = 12 }) -- wide at the wrist
        self:ring(-11, 5.8, 0.6, c.d, { n = 12 })
        self:bone("torso")
    end)
end

-- Chest

MODELS.padded_vest = function(m, c)
    m:bone("torso")
    local rows = { { 4, 9, 12.4, 10.2, 11.2, 9.4 }, { 9, 14, 11.2, 9.4, 11.4, 10.2 }, { 14, 19, 11.4, 10.2, 12.8, 12 },
        { 19, 24, 12.8, 12, 12.6, 11 }, { 24, 28, 12.6, 11, 9.4, 7.6 } }
    for i, r in ipairs(rows) do
        m:tube(r[1], r[2], r[3], r[4], r[5], r[6], i % 2 == 0 and c.e or c.a, { open = true })
        m:ring(r[2], (r[5] + 0.1), 0.5, c.b, { rz = r[6] + 0.1 })
    end
    for i = 0, 3 do
        m:ball(0, 7 + i * 6, 10.8 + (i == 2 and 1.2 or 0), 1, 1, 0.8, c.d, nil, 6)
    end
end

MODELS.bark_jerkin = function(m, c)
    m:bone("torso")
    m:tube(3, 15, 13, 10.5, 11.6, 9.6, c.b, { open = true })
    m:tube(15, 28, 12.2, 11.2, 9.6, 7.8, c.b, { open = true })
    m:ball(0, 20, 8, 11.4, 6.6, 4.6, c.b)
    -- bark, in overlapping plates
    for i = 0, 15 do
        local a = i / 16 * math.pi * 2 + (i % 2) * 0.2
        local h = 6 + (i % 4) * 5.4
        m:box(math.cos(a) * 12.4, h, math.sin(a) * 10.4 + (math.sin(a) > 0 and 0.9 or 0), 4.2, 8.5, 1.6,
            i % 3 == 0 and c.d or c.a, 0.15, -a + math.pi / 2, (i % 2 - 0.5) * 0.22)
    end
    m:ring(4, 12.7, 1.2, c.d, { rz = 10.2 })                 -- belt
end

MODELS.scrap_plate = function(m, c)
    m:bone("torso")
    m:tube(3, 28, 12.6, 10.4, 10, 8, c.b, { open = true })
    m:ball(0, 20, 8.2, 11.4, 6.8, 4.8, c.b)
    m:box(-5, 20.5, 12.2, 11, 12, 1.4, c.a, -0.3, -0.25, 0.14)  -- sheets of whatever came to hand
    m:box(6, 16, 11.8, 12, 9, 1.4, c.d, -0.2, 0.3, -0.2)
    m:box(0, 9, 11.2, 18, 7.5, 1.4, c.a, -0.05, 0, 0.1)
    m:box(0, 16, -9.9, 17, 18, 1.4, c.a, 0.08, 0, -0.05)
    m:sides(function(self, s)
        self:box(s * 12, 16, 0, 1.4, 16, 8, c.d, 0, 0, s * -0.1)
    end)
    for _, r in ipairs({ { -9.5, 24, 12.3 }, { -1, 24.5, 12.8 }, { -9, 16, 12.8 }, { -0.5, 15, 13 }, { 11, 19, 11 }, { 11, 12, 11.5 },
        { -8, 7, 11.9 }, { 8, 6.5, 11.9 } }) do
        m:ball(r[1], r[2], r[3], 0.9, 0.9, 0.7, c.e, nil, 6)  -- rivets
    end
    m:box(0, 19, 12.2, 26, 2, 1, { 0.1, 0.08, 0.06 }, -0.3, 0, 0.6) -- a strap
end

MODELS.knights_cuirass = function(m, c)
    m:bone("torso")
    m:tube(8, 15, 9.6, 8.2, 11, 10.2, c.a, { open = true, n = 20 })
    m:tube(15, 22, 11, 10.2, 11.4, 10.2, c.a, { open = true, n = 20 })
    m:tube(22, 27, 11.4, 10.2, 8.4, 6.8, c.a, { open = true, n = 20 })
    m:ball(0, 18, 6.6, 10.2, 6.6, 4.8, c.a, nil, 16)         -- the breast
    m:box(0, 15, 11.4, 1.1, 18, 0.8, c.e, -0.12)             -- the ridge
    m:ring(26.8, 8.5, 0.5, c.d, { rz = 6.9 })
    m:ring(8, 9.7, 0.5, c.d, { rz = 8.3 })
    for i = 0, 2 do                                          -- the skirt of lames
        local y = 7.5 - i * 3
        m:tube(y, y - 3.2, 10 + i * 0.8, 8.6 + i * 0.7, 10.8 + i * 0.8, 9.4 + i * 0.7, c.a, { open = true, n = 20 })
    end
end

MODELS.synth_jacket = function(m, c)
    m:bone("torso")
    m:tube(0, 15, 12.8, 10.6, 11.6, 9.6, c.a, { open = true, n = 18 })
    m:tube(15, 28, 12.4, 11.4, 9.6, 7.8, c.a, { open = true, n = 18 })
    m:ball(0, 20, 8.2, 11.4, 6.6, 4.6, c.a)
    m:tube(26, 32, 9.2, 7.6, 10.4, 9, c.b, { open = true })   -- the high collar
    m:box(0, 14, 12.2, 1, 27, 0.8, glow(c.d), -0.09)          -- the zip
    m:sides(function(self, s)
        self:box(s * 12.1, 13, 0.5, 0.8, 22, 1, glow(c.e))
        self:box(s * 6, 22, 11.9, 8, 1, 0.8, glow(c.e), -0.35)
        self:box(s * 4.5, 3, 11.2, 8, 5.5, 1, c.b)            -- pockets
    end)
end

MODELS.reliquary_robe = function(m, c)
    m:bone("torso")
    m:tube(-24, -2, 15.5, 13.5, 12, 10, c.a, { open = true, n = 20 })  -- down past her knees
    m:tube(-2, 14, 12, 10, 10.6, 8.8, c.a, { open = true, n = 20 })
    m:tube(14, 27.5, 11.4, 10.2, 9, 7.4, c.a, { open = true, n = 20 })
    m:ball(0, 20, 7.6, 10.4, 6.2, 4.4, c.a)
    m:ring(-23.8, 15.4, 0.6, c.d, { rz = 13.4 })
    m:ring(27.2, 9, 0.7, c.d, { rz = 7.4 })
    m:ring(0, 12, 0.7, c.d, { rz = 10 })                     -- a sash
    m:box(0, 15, 12.5, 2.6, 15, 1, c.d, -0.12)               -- the emblem
    m:box(0, 18, 12.6, 9.5, 2.6, 1, c.d, -0.2)
    m:box(0, -12, 12.4, 4, 22, 0.7, c.e, -0.16)              -- a panel down the front
end

-- Legs. The trunk's lower end is the pelvis, y 0

local function waist(m, color, trim)
    m:bone("torso")
    m:tube(-5, 4, 13.2, 10.8, 12, 10, color, { open = true })
    m:ring(4, 12, 0.9, trim, { rz = 10 })
end

MODELS.canvas_trousers = function(m, c)
    waist(m, c.a, c.d)
    m:sides(function(self, s, l)
        self:bone("thigh" .. l)
        self:tube(1, -17, 7.2, 8, 5, 5.2, c.a, { open = true })
        self:bone("shin" .. l)
        self:tube(1, -13, 5, 5.2, 4.4, 4.6, c.a, { open = true })
        self:ball(0, 0.5, 2.2, 3.8, 3.4, 3.2, c.e, nil, 8)     -- patched knees
        self:ring(-13, 4.6, 0.8, c.b)
    end)
end

MODELS.mossy_breeches = function(m, c)
    waist(m, c.a, c.d)
    m:sides(function(self, s, l)
        self:bone("thigh" .. l)
        self:tube(1, -13, 7.4, 8.2, 6.6, 6.8, c.a, { open = true })
        self:ring(-13, 6.7, 1.1, c.d)
        self:ball(s * 4, -5, 5.5, 3, 2, 2.4, c.e, nil, 8)     -- moss
        self:ball(s * -1, -9, 6.5, 2.4, 1.6, 2, c.e, nil, 8)
        self:ball(s * 5.5, -11, 0, 2.2, 1.8, 2.8, c.e, nil, 8)
        self:bone("shin" .. l)
        self:tube(-4, -13, 4.6, 4.8, 4.2, 4.4, c.b, { open = true })  -- stockings
        self:ring(-4, 4.6, 0.9, c.d)
    end)
end

MODELS.chain_chaps = function(m, c)
    waist(m, c.b, c.d)
    m:sides(function(self, s, l)
        self:bone("thigh" .. l)
        self:tube(1, -17, 7.2, 8, 5.2, 5.4, c.b, { open = true })
        for i = 0, 6 do
            self:ring(-1 - i * 2.4, 7 - i * 0.28, 0.75, i % 2 == 0 and c.e or c.a, { rz = 7.8 - i * 0.38, n = 14 })
        end
        self:bone("shin" .. l)
        self:tube(1, -13, 5.2, 5.4, 4.5, 4.7, c.a, { open = true })
        for i = 0, 4 do
            self:ring(-1 - i * 2.8, 5 - i * 0.14, 0.65, i % 2 == 0 and c.e or c.d, { n = 12 })
        end
    end)
end

MODELS.plate_greaves = function(m, c)
    m:sides(function(self, s, l)
        self:bone("thigh" .. l)
        self:tube(1, -16, 6.4, 7, 4.9, 5.2, c.a, { open = true, n = 18 })
        self:box(s * 0.4, -8, 6.1, 2, 13, 0.7, c.e, 0.08)
        self:bone("shin" .. l)
        self:ball(0, 0, 1.2, 4.9, 4.4, 4.7, c.a)              -- the knee
        self:ring(0, 4.5, 0.45, c.d, { z = 1.2, rz = 4.6, n = 12 })
        self:rod(0, 2, 5.4, 0, -2.5, 5.4, 0.9, 0, c.d, 6)
        self:tube(-1.5, -14, 5, 5.4, 4, 4.4, c.a, { open = true, n = 18 })
        self:box(0, -8, 5.1, 1.3, 11, 0.7, c.e)
    end)
end

MODELS.flex_leggings = function(m, c)
    waist(m, c.a, glow(c.e))
    m:sides(function(self, s, l)
        self:bone("thigh" .. l)
        self:tube(1, -17, 6.8, 7.6, 4.8, 5, c.a, { open = true })
        self:box(s * 6.4, -6, 0, 0.8, 16, 1.2, glow(c.e), 0, 0, s * 0.11)
        self:bone("shin" .. l)
        self:tube(1, -14, 4.8, 5, 3.8, 4.1, c.a, { open = true })
        self:box(s * 4.6, -6, 0, 0.8, 14, 1, glow(c.e), 0, 0, s * 0.06)
        self:ball(0, 0, 4, 3.6, 3, 1.6, c.b, nil, 8)
    end)
end

MODELS.pilgrims_wraps = function(m, c)
    waist(m, c.a, c.d)
    m:sides(function(self, s, l)
        self:bone("thigh" .. l)
        for i = 0, 5 do
            local y = 1 - i * 3
            self:tube(y, y - 3.4, 7.3 - i * 0.42, 8 - i * 0.5, 6.9 - i * 0.42, 7.5 - i * 0.5, i % 2 == 0 and c.a or c.e, { open = true })
        end
        self:bone("shin" .. l)
        for i = 0, 4 do
            local y = 1 - i * 3
            self:tube(y, y - 3.4, 5.1 - i * 0.2, 5.3 - i * 0.2, 4.9 - i * 0.2, 5.1 - i * 0.2, i % 2 == 0 and c.e or c.a, { open = true })
        end
        self:ring(-13.5, 4.3, 0.7, c.d)
        self:rod(s * 3.8, -14, -3, s * 6, -20, -4.5, 0.8, 0.1, c.e, 5) -- a loose end
    end)
end

-- Feet: y up the shin from the middle of the shoe, z to the toes

MODELS.worn_boots = function(m, c)
    m:sides(function(self, s, l)
        self:bone("foot" .. l)
        self:ball(0, -0.5, 1.5, 4.6, 3.8, 8, c.a)
        self:box(0, -3.2, 1.5, 7.6, 1.3, 14, c.b)
        self:tube(1, 9, 4.4, 4.8, 4.9, 5.2, c.a, { open = true, z = -1 })
        self:ring(9, 4.9, 0.9, c.d, { z = -1, rz = 5.2 })
        self:box(0, 2, 7.2, 3.2, 0.8, 3, c.d, 0.5)
    end)
end

MODELS.garden_clogs = function(m, c)
    m:sides(function(self, s, l)
        self:bone("foot" .. l)
        self:ball(0, 0, 2, 6, 4.4, 9.4, c.a)
        self:box(0, -3.4, 2, 9.6, 1.6, 16, c.b)
        self:ring(1.8, 3.7, 0.8, c.d, { z = -2.5, rz = 4.4 })
        self:tube(0, 4, 3.2, 3.8, 3.6, 4.1, { 0.05, 0.05, 0.06 }, { z = -2.5, open = true })
    end)
end

MODELS.road_boots = function(m, c)
    m:sides(function(self, s, l)
        self:bone("foot" .. l)
        self:ball(0, 0, 2.4, 5, 4.2, 9, c.a)
        self:ball(0, 0.5, 7.6, 4.2, 3.2, 3.8, c.e)            -- steel toe
        self:box(0, -3.4, 2, 9.2, 2.8, 16.5, c.b)             -- a tyre's worth of sole
        self:tube(1, 12, 4.6, 5, 5.2, 5.6, c.a, { open = true, z = -1.2 })
        for i = 0, 2 do
            self:ring(3.4 + i * 3.4, 5 + i * 0.16, 0.7, c.d, { z = -1.2, rz = 5.4 + i * 0.16 })
            self:box(s * 5, 3.4 + i * 3.4, -1.2, 1.2, 1.6, 2.4, c.e)
        end
    end)
end

MODELS.iron_sabatons = function(m, c)
    m:sides(function(self, s, l)
        self:bone("foot" .. l)
        self:box(0, -3, 2, 7.4, 1, 15, c.b)
        self:ball(0, -0.6, 2, 4.4, 3.4, 8.4, c.a)
        for i = 0, 3 do                                       -- plates down to the toe
            self:box(0, 1.2 - i * 0.55, -0.5 + i * 3, 8 - i * 0.9, 1, 1.1, c.e, 0.9)
        end
        self:rod(0, -0.8, 9.6, 0, -1.2, 13.5, 1.7, 0, c.a, 8) -- a point
        self:tube(1, 9, 4.6, 5, 5, 5.4, c.a, { open = true, z = -1.5 })
        self:ring(9, 5, 0.5, c.d, { z = -1.5, rz = 5.4 })
    end)
end

MODELS.mag_sneakers = function(m, c)
    m:sides(function(self, s, l)
        self:bone("foot" .. l)
        self:ball(0, 0, 1.6, 4.6, 3.6, 8.2, c.a)
        self:box(0, -2.4, 1.6, 8.6, 2, 15.5, glow(c.e))       -- the sole, lit
        self:box(0, -3.6, 1.6, 7.6, 0.6, 14.5, c.b)
        self:box(s * 4.4, 0.4, 0.5, 0.8, 3, 7, c.d, 0.3)      -- a stripe
        self:tube(1, 5.5, 4, 4.5, 4.6, 5, c.a, { open = true, z = -1 })
        self:ring(5.5, 4.6, 0.8, c.d, { z = -1, rz = 5 })
    end)
end

MODELS.ash_sandals = function(m, c)
    m:sides(function(self, s, l)
        self:bone("foot" .. l)
        self:box(0, -3.2, 1.6, 8.2, 1.4, 15.5, c.a)
        self:ring(-1.6, 4.2, 0.6, c.d, { z = 4.4, rz = 3.4, n = 12 })
        self:ring(-0.8, 4.2, 0.6, c.d, { z = -0.8, rz = 3.6, n = 12 })
        self:ring(3.6, 3.8, 0.6, c.d, { z = -1.2, rz = 4.2, n = 12 })
        self:ring(7, 3.8, 0.6, c.d, { z = -1.2, rz = 4.3, n = 12 })
        self:rod(s * 3.6, -1.2, 4.4, s * 3.6, 3.6, -1.2, 0.5, 0.5, c.d, 5)
    end)
end

-- Her, for the depth buffer: a little inside anything worn over her
local function BODY(m)
    m:bone("head")
    m:ball(0, 0, -1, 8.6, 9, 8.8, { 0, 0, 0 })
    m:bone("torso")
    m:tube(-6, 8, 11.5, 9, 9.6, 8, { 0, 0, 0 })
    m:tube(8, 18, 9.6, 8, 11, 9.6, { 0, 0, 0 })
    m:tube(18, 27, 11, 9.6, 7.6, 6.4, { 0, 0, 0 })
    m:sides(function(self, s, l)
        self:bone("arm" .. l)
        self:tube(1, -13, 3.4, 3.4, 2.8, 2.8, { 0, 0, 0 }, { n = 8 })
        self:bone("fore" .. l)
        self:tube(1, -14, 2.8, 2.8, 2.2, 2.2, { 0, 0, 0 }, { n = 8 })
        self:bone("thigh" .. l)
        self:tube(1, -16, 6, 6.4, 4, 4, { 0, 0, 0 }, { n = 10 })
        self:bone("shin" .. l)
        self:tube(1, -16, 4, 4, 2.6, 2.6, { 0, 0, 0 }, { n = 10 })
        self:bone("foot" .. l)
        self:ball(0, -0.6, 1.5, 3, 2.6, 6, { 0, 0, 0 }, nil, 8)
    end)
end

armorModel.MODELS = MODELS

--------------------------------------------------------------------------------
-- Drawing it
--------------------------------------------------------------------------------

local canvas, shader, bodyMesh
local armorMesh       -- what's worn, as one mesh (nil: nothing)
local shown           -- what the canvas has on it, as a string
local version = 0     -- goes up when what's worn changes
local boneData = {}   -- what goes to `bones`, one vec3 at a time

local function load()
    canvas = love.graphics.newCanvas(FRAME, FRAME)
    canvas:setFilter("nearest", "nearest")
    shader = love.graphics.newShader(SHADER)
    shader:send("elevation", ELEVATION)
    shader:send("centre", { CENTRE_X, CENTRE_Y })
    local m = newModel()
    BODY(m)
    bodyMesh = love.graphics.newMesh(FORMAT, m.verts, "triangles", "static")
    for i = 1, #BONES * 4 do boneData[i] = { 0, 0, 0 } end
end

--- What's worn: a list of { id =, colors =, gloss = } (armor.DEFS entries)
function armorModel.setWorn(pieces)
    local m = newModel()
    for _, def in ipairs(pieces) do
        m.gloss = def.gloss or 0
        assert(MODELS[def.id], "no model for " .. tostring(def.id))(m, def.colors)
    end
    if armorMesh then armorMesh:release() end
    armorMesh = #m.verts > 0 and love.graphics.newMesh(FORMAT, m.verts, "triangles", "static") or nil
    version = version + 1
end

local function unit(x, y, z)
    local l = math.sqrt(x * x + y * y + z * z)
    if l < 1e-5 then return 0, 1, 0, 0 end
    return x / l, y / l, z / l, l
end

-- Fill bone i's axes: y as given (from a joint to one further up it), z as
-- near `f` as can be square to it
local function setBone(i, ox, oy, oz, yx, yy, yz, f, stretch)
    local ly
    yx, yy, yz, ly = unit(yx, yy, yz)
    local d = f[1] * yx + f[2] * yy + f[3] * yz
    local zx, zy, zz, lz = unit(f[1] - yx * d, f[2] - yy * d, f[3] - yz * d)
    if lz < 0.15 then -- an arm pointing the way she faces: up will have to do
        d = f[4] * yx + f[5] * yy + f[6] * yz
        zx, zy, zz = unit(f[4] - yx * d, f[5] - yy * d, f[6] - yz * d)
    end
    local xx, xy, xz = yy * zz - yz * zy, yz * zx - yx * zz, yx * zy - yy * zx
    local s = stretch and ly / stretch or 1
    local b = boneData
    local k = i * 4
    b[k + 1][1], b[k + 1][2], b[k + 1][3] = xx, xy, xz
    b[k + 2][1], b[k + 2][2], b[k + 2][3] = yx * s, yy * s, yz * s
    b[k + 3][1], b[k + 3][2], b[k + 3][3] = zx, zy, zz
    b[k + 4][1], b[k + 4][2], b[k + 4][3] = ox, oy, oz
end

-- Pose the bones on one of the rig's frames
local function pose(p)
    local function j(name)
        local k = JOINT[name]
        return p[k + 1], p[k + 2], p[k + 3]
    end
    local nx, ny, nz = j("neck")
    local px, py, pz = j("pelvis")
    local ux, uy, uz = unit(nx - px, ny - py, nz - pz)
    local f = { 0, -uz, uy, ux, uy, uz } -- the way she faces, then up her spine

    local function chain(i, stretch, from, to)
        local ax, ay, az = j(from)
        local bx, by, bz = j(to)
        setBone(i, ax, ay, az, ax - bx, ay - by, az - bz, f, stretch)
    end

    local hx, hy, hz = j("head")
    setBone(BONE_INDEX.head, hx, hy, hz, hx - nx, hy - ny, hz - nz, f)
    setBone(BONE_INDEX.torso, px, py, pz, nx - px, ny - py, nz - pz, f, BONES[BONE_INDEX.torso + 1][2])

    for _, l in ipairs({ "L", "R" }) do
        chain(BONE_INDEX["arm" .. l], 12, "shoulder" .. l, "elbow" .. l)
        chain(BONE_INDEX["fore" .. l], 13, "elbow" .. l, "hand" .. l)
        chain(BONE_INDEX["thigh" .. l], 16, "hip" .. l, "knee" .. l)
        chain(BONE_INDEX["shin" .. l], 16, "knee" .. l, "ankle" .. l)
        local ax, ay, az = j("ankle" .. l)
        local kx, ky, kz = j("knee" .. l)
        local fx, fy, fz = j("foot" .. l)
        setBone(BONE_INDEX["foot" .. l], fx, fy, fz, kx - ax, ky - ay, kz - az, f)
    end
end

--- Draw what's worn for this frame of `animation`, seen from `direction`
--- (1..8), if that's not what's already there. Returns the canvas, or nil
--- with nothing worn. Sets its own state and leaves none behind.
function armorModel.render(animation, frame, direction)
    if not armorMesh then return nil end
    if not canvas then load() end
    local key = animation .. frame .. "/" .. direction .. "/" .. version
    if key == shown then return canvas end
    local frames = rig[animation]
    local p = frames and frames[math.min(frame, #frames)]
    if not p then return canvas end
    shown = key

    pose(p)
    shader:send("bones", unpack(boneData))
    shader:send("yaw", (direction - 1) * math.pi / 4)

    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setScissor()
    love.graphics.setCanvas({ canvas, depth = true })
    love.graphics.clear(0, 0, 0, 0, false, 1)
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setDepthMode("less", true)
    love.graphics.setShader(shader)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setColorMask(false, false, false, false)
    love.graphics.draw(bodyMesh)
    love.graphics.setColorMask(true, true, true, true)
    love.graphics.draw(armorMesh)
    love.graphics.pop()
    return canvas
end

return armorModel
