--[[
  Normal maps for upright things: which way each texel of a building, wall,
  lamp, tree, the house or the car faces, so lights pick out its relief (a
  lamp to the left of a wall lights the left side of every brick, ledges
  catch the sky, the far side of a trunk stays dark).

  Every sheet of standing art gets one at load (normalmap.of), baked on the
  GPU from the art itself: its outline is bevelled, so silhouettes round off
  over their last couple of texels, and its brightness is read as height, so
  dark mortar, window recesses and seams sink in. A hand-drawn one wins: put
  it beside the sheet as <name>_normal.png, laid out the same, and it's used
  instead.

  Encoding: rgb = n * 0.5 + 0.5 in the face's own frame, x to the right, y up
  the face, z out of it toward the viewer; alpha 0 where the art is empty.

  Lighting with them (normalmap.GLSL, in regions' sprite shader and the
  object shader in shadow.lua): an upright face stands on its ground line
  facing the viewer, so a light's direction in that frame is (across, up,
  out) = (dx, its height over the texel, |dy|). A light behind a face lights
  it as one in front would, as faces always have been. A normal only changes
  a light's share compared with a flat face: flat stays as bright as it was,
  what faces the light gets more, what faces away less. The ambient light
  comes from the sky, above, in front and a little to the left, so relief
  shows in the dark and by day too.
]]
local normalmap = {}

normalmap.GLSL = [[
    const float NORMAL_STRENGTH = 1.6;
    const float SKY_STRENGTH = 1.0;
    const vec3 SKY = vec3(-0.30, 0.55, 0.78); // where the ambient light comes from

    // The texel's normal (lib/graphics/normalmap.lua); flat where there's no art
    vec3 faceNormal(Image normals, vec2 tc) {
        vec4 s = Texel(normals, tc);
        return s.a > 0.0 ? normalize(s.rgb * 2.0 - 1.0) : vec3(0.0, 0.0, 1.0);
    }

    // How much of a light the texel gets, compared with a flat face: toLight
    // runs from it to the light, (across, along the ground toward the
    // viewer, up). 1 for a flat face, wherever the light is.
    float faceShade(vec3 n, vec3 toLight) {
        vec3 d = vec3(toLight.x, toLight.z, abs(toLight.y));
        float len = length(d);
        if (len <= 0.0) return 1.0;
        d /= len;
        return max(0.0, 1.0 + NORMAL_STRENGTH * (dot(n, d) - d.z));
    }

    // The same for the sky's ambient light
    float skyShade(vec3 n) {
        return max(0.0, 1.0 + SKY_STRENGTH * (dot(n, SKY) - SKY.z));
    }
]]

-- Height: the outline's bevel (alpha averaged over 5x5, so it ramps over the
-- last two texels either side of the edge) and brightness (3x3, weighted by
-- alpha so empty texels don't darken it), packed 16-bit into red and green.
-- Samples stay inside the sprite (bounds), so nothing bleeds in from its
-- neighbours on the sheet.
local HEIGHT_SHADER = [[
    const float EDGE = 0.6;   // how much of the height is the bevel
    const float DETAIL = 0.4; // and how much the brightness

    uniform vec2 texSize; // texels
    uniform vec4 bounds;  // the sprite's texels: x0, y0, x1, y1 (exclusive)

    vec4 at(Image tex, vec2 p) {
        return Texel(tex, (clamp(p, bounds.xy, bounds.zw - 1.0) + 0.5) / texSize);
    }

    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 screen_coords) {
        vec2 p = floor(tc * texSize);
        float edge = 0.0;
        for (int y = -2; y <= 2; y++) {
            for (int x = -2; x <= 2; x++) {
                edge += at(tex, p + vec2(float(x), float(y))).a;
            }
        }
        edge /= 25.0;
        float lum = 0.0;
        float weight = 0.0;
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                vec4 c = at(tex, p + vec2(float(x), float(y)));
                lum += dot(c.rgb, vec3(0.299, 0.587, 0.114)) * c.a;
                weight += c.a;
            }
        }
        if (weight > 0.0) lum /= weight;
        float h = clamp(EDGE * edge + DETAIL * lum * at(tex, p).a, 0.0, 1.0);
        float h16 = floor(h * 65535.0 + 0.5);
        float hi = floor(h16 / 256.0);
        return vec4(hi / 255.0, (h16 - hi * 256.0) / 255.0, 0.0, 1.0);
    }
]]

-- Normals: the height's slope (Sobel), steepened by BUMP
local NORMAL_SHADER = [[
    const float BUMP = 6.0;

    uniform vec2 texSize;
    uniform vec4 bounds;
    uniform Image art; // where it's empty

    float height(Image tex, vec2 p) {
        vec4 c = Texel(tex, (clamp(p, bounds.xy, bounds.zw - 1.0) + 0.5) / texSize);
        return (floor(c.r * 255.0 + 0.5) * 256.0 + floor(c.g * 255.0 + 0.5)) / 65535.0;
    }

    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 screen_coords) {
        if (Texel(art, tc).a <= 0.0) return vec4(0.5, 0.5, 1.0, 0.0);
        vec2 p = floor(tc * texSize);
        float tl = height(tex, p + vec2(-1.0, -1.0));
        float t  = height(tex, p + vec2( 0.0, -1.0));
        float tr = height(tex, p + vec2( 1.0, -1.0));
        float l  = height(tex, p + vec2(-1.0,  0.0));
        float r  = height(tex, p + vec2( 1.0,  0.0));
        float bl = height(tex, p + vec2(-1.0,  1.0));
        float b  = height(tex, p + vec2( 0.0,  1.0));
        float br = height(tex, p + vec2( 1.0,  1.0));
        // the slope per texel; y runs down the sheet
        float dx = ((tr + 2.0 * r + br) - (tl + 2.0 * l + bl)) / 8.0;
        float dy = ((bl + 2.0 * b + br) - (tl + 2.0 * t + tr)) / 8.0;
        // rising to the right faces left, rising down the sheet faces up
        vec3 n = normalize(vec3(-dx * BUMP, dy * BUMP, 1.0));
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
        if x1 > x0 and y1 > y0 then rects[#rects + 1] = { x0, y0, x1, y1 } end
    end
    if #rects == 0 then rects[1] = { 0, 0, w, h } end
    return rects
end

local function bake(image, quads)
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
--- its own; without them the whole image is one. Once per image.
function normalmap.of(image, quads, path)
    if made[image] then return made[image] end
    local own = path and path:gsub("%.%w+$", "_normal.png")
    local map
    if own and love.filesystem.getInfo(own, "file") then
        map = love.graphics.newImage(own)
    else
        map = bake(image, quads)
    end
    map:setFilter("nearest", "nearest")
    made[image] = map
    return map
end

return normalmap
