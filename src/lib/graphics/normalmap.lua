--[[
  Normal maps for upright things: which way each texel of a building, wall,
  lamp, tree, the house or the car faces, so lights pick out its relief (a
  lamp to the left of a wall lights the left side of every brick, ledges
  catch the sky, the far side of a trunk stays dark).

  Every sheet of standing art gets one at load (normalmap.of), baked on the
  GPU from the art itself: its outline is bevelled, so silhouettes round off
  over their last couple of texels, and its brightness is read as height at
  three scales: the whole shape, each texel against the ones round it
  (mortar, frames and seams sink in as grooves, and so do edges between
  colours), and recesses against the wall round them (windows, doorways and
  panels sink, ledges and pillars stand out). A hand-drawn one wins: put it
  beside the sheet as <name>_normal.png, laid out the same, and it's used
  instead.

  Encoding: rgb = n * 0.5 + 0.5 in the face's own frame, x to the right, y up
  the face, z out of it toward the viewer; alpha 0 where the art is empty.

  Lighting with them (normalmap.GLSL, in regions' sprite shader and the
  object shader in shadow.lua): an upright face stands on its ground line
  facing the viewer, so a light's direction in that frame is (across, up,
  out) = (dx, its height over the texel, dy). A normal changes a light's
  share compared with a flat face: flat stays as bright as it was, what
  faces the light gets more, what faces away less, and once the light is
  round behind what a texel faces it gets none (fading out as the light
  passes edge-on), so a light behind a face, or in line with its foot, only
  catches what's turned toward it. The ambient light comes from the sky,
  above, in front and a little to the left, so relief shows in the dark and
  by day too.
]]
local normalmap = {}

normalmap.GLSL = [[
    const float NORMAL_STRENGTH = 1.6;
    const float SKY_STRENGTH = 1.0;
    const float FACING = 0.1; // a light fades out this far either side of edge-on (cosine)
    const vec3 SKY = vec3(-0.30, 0.55, 0.78); // where the ambient light comes from

    // The texel's normal (lib/graphics/normalmap.lua); flat where there's no art
    vec3 faceNormal(Image normals, vec2 tc) {
        vec4 s = Texel(normals, tc);
        return s.a > 0.0 ? normalize(s.rgb * 2.0 - 1.0) : vec3(0.0, 0.0, 1.0);
    }

    // How much of a light the texel gets, compared with a flat face: toLight
    // runs from it to the light, (across, along the ground toward the
    // viewer, up). 1 for a flat face with the light well in front of it;
    // nothing once the light is round behind what the texel faces.
    float faceShade(vec3 n, vec3 toLight) {
        vec3 d = vec3(toLight.x, toLight.z, toLight.y);
        float len = length(d);
        if (len <= 0.0) return 1.0;
        d /= len;
        float facing = dot(n, d);
        return smoothstep(-FACING, FACING, facing)
             * max(0.0, 1.0 + NORMAL_STRENGTH * (facing - max(d.z, 0.0)));
    }

    // The same for the sky's ambient light
    float skyShade(vec3 n) {
        return max(0.0, 1.0 + SKY_STRENGTH * (dot(n, SKY) - SKY.z));
    }
]]

-- Heights, at three scales, from the art. Samples stay inside the sprite
-- (bounds), so nothing bleeds in from its neighbours on the sheet; every
-- brightness is weighted by alpha, so empty texels don't darken it.
--   red, green: the shape, 16-bit: the outline's bevel (alpha averaged over
--     5x5, so it ramps over the last two texels either side of the edge) and
--     brightness (3x3)
--   blue: texel-sized relief, 0.5 flat: the texel against its 3x3, less
--     where its colour differs from theirs more than its brightness does
--     (mortar, frames, seams and trim sink in as grooves)
--   alpha: recesses, 0.5 flat: the 3x3 against the 7x7 round it (windows,
--     doorways and panels sink, ledges and pillars stand out)
local HEIGHT_SHADER = [[
    const float EDGE = 0.6;   // how much of the shape is the bevel
    const float DETAIL = 0.4; // and how much the brightness
    const float GROOVE = 0.6; // colour edges, as grooves

    uniform vec2 texSize; // texels
    uniform vec4 bounds;  // the sprite's texels: x0, y0, x1, y1 (exclusive)

    vec4 at(Image tex, vec2 p) {
        return Texel(tex, (clamp(p, bounds.xy, bounds.zw - 1.0) + 0.5) / texSize);
    }

    float luma(vec3 c) {
        return dot(c, vec3(0.299, 0.587, 0.114));
    }

    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 screen_coords) {
        vec2 p = floor(tc * texSize);
        vec4 c0 = at(tex, p);
        float edge = 0.0;
        vec3 rgb3 = vec3(0.0);
        float w3 = 0.0, lum7 = 0.0, w7 = 0.0;
        for (int y = -3; y <= 3; y++) {
            for (int x = -3; x <= 3; x++) {
                vec4 c = at(tex, p + vec2(float(x), float(y)));
                if (abs(x) <= 2 && abs(y) <= 2) edge += c.a;
                if (abs(x) <= 1 && abs(y) <= 1) {
                    rgb3 += c.rgb * c.a;
                    w3 += c.a;
                }
                lum7 += luma(c.rgb) * c.a;
                w7 += c.a;
            }
        }
        edge /= 25.0;
        if (w3 > 0.0) rgb3 /= w3;
        if (w7 > 0.0) lum7 /= w7;
        float lum3 = luma(rgb3);
        float lum0 = luma(c0.rgb);

        float h = clamp(EDGE * edge + DETAIL * lum3 * c0.a, 0.0, 1.0);
        float h16 = floor(h * 65535.0 + 0.5);
        float hi = floor(h16 / 256.0);

        float shade = lum0 - lum3;
        float groove = max(0.0, length(c0.rgb - rgb3) - abs(shade));
        float fine = (shade - GROOVE * groove) * c0.a;
        float recess = (lum3 - lum7) * c0.a;
        return vec4(hi / 255.0, (h16 - hi * 256.0) / 255.0,
                    clamp(0.5 + fine, 0.0, 1.0), clamp(0.5 + recess, 0.0, 1.0));
    }
]]

-- Normals: the slope (Sobel) of each scale of height, steepened by its bump;
-- the two of the sprite's own relief by `detail` too
local NORMAL_SHADER = [[
    const float BUMP = 6.0;        // the shape
    const float FINE_BUMP = 3.0;   // texel-sized relief
    const float RECESS_BUMP = 7.0; // recesses

    uniform vec2 texSize;
    uniform vec4 bounds;
    uniform float detail;
    uniform Image art; // where it's empty

    // (shape, texel-sized relief, recess) at p
    vec3 height(Image tex, vec2 p) {
        vec4 c = Texel(tex, (clamp(p, bounds.xy, bounds.zw - 1.0) + 0.5) / texSize);
        return vec3((floor(c.r * 255.0 + 0.5) * 256.0 + floor(c.g * 255.0 + 0.5)) / 65535.0,
                    c.b - 0.5, c.a - 0.5);
    }

    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 screen_coords) {
        if (Texel(art, tc).a <= 0.0) return vec4(0.5, 0.5, 1.0, 0.0);
        vec2 p = floor(tc * texSize);
        vec3 tl = height(tex, p + vec2(-1.0, -1.0));
        vec3 t  = height(tex, p + vec2( 0.0, -1.0));
        vec3 tr = height(tex, p + vec2( 1.0, -1.0));
        vec3 l  = height(tex, p + vec2(-1.0,  0.0));
        vec3 r  = height(tex, p + vec2( 1.0,  0.0));
        vec3 bl = height(tex, p + vec2(-1.0,  1.0));
        vec3 b  = height(tex, p + vec2( 0.0,  1.0));
        vec3 br = height(tex, p + vec2( 1.0,  1.0));
        // the slope per texel of each; y runs down the sheet
        vec3 dx = ((tr + 2.0 * r + br) - (tl + 2.0 * l + bl)) / 8.0;
        vec3 dy = ((bl + 2.0 * b + br) - (tl + 2.0 * t + tr)) / 8.0;
        vec3 bump = vec3(BUMP, FINE_BUMP * detail, RECESS_BUMP * detail);
        float sx = dot(dx, bump);
        float sy = dot(dy, bump);
        // rising to the right faces left, rising down the sheet faces up
        vec3 n = normalize(vec3(-sx, sy, 1.0));
        return vec4(n * 0.5 + 0.5, 1.0);
    }
]]

local heightShader, normalShader

-- The rects of `quads` on an image w x h (the whole image without any)
local function rectsOf(quads, w, h)
    local rects = {}
    for _, q in ipairs(quads or {}) do
        local x, y, qw, qh = q:getViewport()
        local x0, y0 = math.max(0, x), math.max(0, y)
        local x1, y1 = math.min(w, x + qw), math.min(h, y + qh)
        if x1 > x0 and y1 > y0 then rects[#rects + 1] = { x0, y0, x1, y1, quad = q } end
    end
    if #rects == 0 then rects[1] = { 0, 0, w, h } end
    return rects
end

local function bake(image, quads, detail)
    if not heightShader then
        heightShader = love.graphics.newShader(HEIGHT_SHADER)
        normalShader = love.graphics.newShader(NORMAL_SHADER)
    end
    local w, h = image:getDimensions()
    local rects = rectsOf(quads, w, h)
    local settings = { format = "rgba8", dpiscale = 1 }
    local heights = love.graphics.newCanvas(w, h, settings)
    local normals = love.graphics.newCanvas(w, h, settings)
    local quad = love.graphics.newQuad(0, 0, w, h, w, h)

    -- Each sprite through `shader`, from `source` into `target`
    local function pass(shader, source, target)
        love.graphics.setCanvas(target)
        love.graphics.setShader(shader)
        shader:send("texSize", { w, h })
        for _, r in ipairs(rects) do
            shader:send("bounds", r)
            if shader == normalShader then
                shader:send("detail", type(detail) == "table" and (detail[r.quad] or 1) or detail or 1)
            end
            quad:setViewport(r[1], r[2], r[3] - r[1], r[4] - r[2], w, h)
            love.graphics.draw(source, quad, r[1], r[2])
        end
    end

    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setScissor()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setCanvas(heights)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setCanvas(normals)
    love.graphics.clear(0.5, 0.5, 1, 0)
    pass(heightShader, image, heights)
    normalShader:send("art", image)
    pass(normalShader, heights, normals)
    love.graphics.pop()
    heights:release()
    return normals
end

local made = setmetatable({}, { __mode = "k" })
local flat

--- A normal map that leaves everything lit as a flat face (one empty
--- texel: faceNormal reads it as facing the viewer), for Settings > Normal
--- Maps off.
function normalmap.flat()
    if not flat then
        local data = love.image.newImageData(1, 1)
        data:setPixel(0, 0, 0.5, 0.5, 1, 0)
        flat = love.graphics.newImage(data)
        flat:setFilter("nearest", "nearest")
    end
    return flat
end

--- The normal map for `image`, laid out like it: the file `path` names with
--- _normal before its extension, if there is one (drawn by hand), or else
--- baked from the art. `quads` (a list) are the sprites on it, each baked on
--- its own; without them the whole image is one. `detail` (default 1) scales
--- how much each one's own relief shows against its shape: a number for all,
--- or a table from quad to number. Once per image.
function normalmap.of(image, quads, path, detail)
    if made[image] then return made[image] end
    local own = path and path:gsub("%.%w+$", "_normal.png")
    local map
    if own and love.filesystem.getInfo(own, "file") then
        map = love.graphics.newImage(own)
    else
        map = bake(image, quads, detail)
    end
    map:setFilter("nearest", "nearest")
    made[image] = map
    return map
end

return normalmap
