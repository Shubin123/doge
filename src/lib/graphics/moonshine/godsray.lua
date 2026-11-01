--[[
The MIT License (MIT)

Original code: Copyright (c) 2015 Josef Patoprsty
Port to moonshine: Copyright (c) 2017 Matthias Richter <vrld@vrld.org>

Based on work by: ioxu

https://www.love2d.org/forums/viewtopic.php?f=4&t=3733&start=120#p71099

Based on work by: Fabien Sanglard

http://fabiensanglard.net/lightScattering/index.php

Based on work from:

[Mitchell]: Kenny Mitchell "Volumetric Light Scattering as a Post-Process" GPU Gems 3 (2005).
[Mitchell2]: Jason Mitchell "Light Shaft Rendering" ShadersX3 (2004).

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]--

return function(moonshine)
  local shader = love.graphics.newShader[[
    extern number exposure;
    extern number decay;
    extern number density;
    extern number weight;
    extern vec2 light_position;
    extern number samples;

    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 px) {
      color = Texel(tex, uv);

      vec2 offset = (uv - light_position) * density / samples;
      number illumination = decay;
      vec4 c = vec4(.0, .0, .0, 1.0);

      for (int i = 0; i < 30; ++i) {
        uv -= offset;
        c += Texel(tex, uv) * illumination * weight;
        illumination *= decay;
      }

      return vec4(c.rgb * exposure + color.rgb, color.a);
    }]]


  local setters, light_position = {}
  local sent = {} -- what the shader was sent, for reach

  for _,k in ipairs{"exposure", "decay", "density", "weight"} do
    setters[k] = function(v)
      sent[k] = math.min(1, math.max(0, tonumber(v) or 0))
      shader:send(k, sent[k])
    end
  end

  setters.light_position = function(v)
    light_position = {unpack(v)}
    shader:send("light_position", v)
  end

  setters.light_x = function(v)
    assert(type(v) == "number", "Invalid value for `light_x'")
    setters.light_position{v, light_position[2]}
  end

  setters.light_y = function(v)
    assert(type(v) == "number", "Invalid value for `light_y'")
    setters.light_position{light_position[1], v}
  end

  setters.samples = function(v)
    sent.samples = math.max(1,tonumber(v) or 1)
    shader:send("samples", sent.samples)
  end

  -- Pixel p is its own colour plus 30 samples at p + t (light - p), t = i *
  -- density / samples, so it can only light up where one of them lands in r:
  -- in r scaled about the light by 1 / (1 - t). At t = 1 every pixel samples
  -- the light itself (the whole canvas, if r holds it); past t = 1 samples
  -- leave the canvas and clamp to its edge (the whole canvas).
  local reach = function(r, w, h)
    local lx, ly = light_position[1] * w, light_position[2] * h
    if lx < 0 or lx > w or ly < 0 or ly > h then return {0, 0, w, h} end
    local x0, y0, x1, y1 = r[1] - 2, r[2] - 2, r[3] + 2, r[4] + 2
    local bx0, by0, bx1, by1 = x0, y0, x1, y1
    local near = 1e-3 * (w + h) + 2 -- how far from the light t ~ 1 lands
    for i = 1, 30 do
      local t = i * sent.density / sent.samples
      if t > 1 + 1e-3 then return {0, 0, w, h} end
      if math.abs(1 - t) <= 1e-3 then
        if lx >= x0 - near and lx <= x1 + near and ly >= y0 - near and ly <= y1 + near then
          return {0, 0, w, h}
        end
      else
        local k = 1 / (1 - t)
        local ax, bx = lx + (x0 - lx) * k, lx + (x1 - lx) * k
        local ay, by = ly + (y0 - ly) * k, ly + (y1 - ly) * k
        bx0, bx1 = math.min(bx0, ax, bx), math.max(bx1, ax, bx)
        by0, by1 = math.min(by0, ay, by), math.max(by1, ay, by)
      end
    end
    return {bx0 - 2, by0 - 2, bx1 + 2, by1 + 2}
  end

  local defaults = {
    exposure = 0.25,
    decay = 0.95,
    density = 0.15,
    weight = 0.5,
    light_position = {0.5,0.5},
    samples = 70
  }

  return moonshine.Effect{
    name = "godsray",
    shader = shader,
    reach = reach,
    setters = setters,
    defaults = defaults
  }
end
