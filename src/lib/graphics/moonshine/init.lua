--[[
The MIT License (MIT)

Copyright (c) 2017 Matthias Richter

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




local BASE = ...

local moonshine = {}

-- Clipped chains. Given the rect its input can be non-zero in, an effect's
-- `reach` returns the rect its passes are scissored to: all it can light, and
-- anything its own later passes read that the full pass wouldn't leave at
-- zero. Each pass's canvas is still cleared whole before the scissor goes on
-- (clear obeys it), and the chain presents only the last rect, so every pixel
-- comes out as the unclipped chain's would.
moonshine.clip = nil -- {x, y, w, h} of the pass being drawn, nil = all of it

-- Clear the bound canvas, then scissor the draws that follow to the clip
moonshine.clear = function()
  local c = moonshine.clip
  if c then love.graphics.setScissor() end
  love.graphics.clear()
  if c then love.graphics.setScissor(c[1], c[2], c[3], c[4]) end
end

-- {x0, y0, x1, y1} grown by m pixels each way
moonshine.grow = function(r, m)
  return {r[1] - m, r[2] - m, r[3] + m, r[4] + m}
end

-- The scissor {x, y, w, h} covering r inside a w x h canvas (never empty, so
-- it is always valid; a pass with nothing to draw is zero anyway)
local function scissor(r, w, h)
  local x0, y0 = math.max(0, math.floor(r[1])), math.max(0, math.floor(r[2]))
  local x1, y1 = math.min(w, math.ceil(r[3])), math.min(h, math.ceil(r[4]))
  if x1 <= x0 or y1 <= y0 then return {0, 0, 1, 1} end
  return {x0, y0, x1 - x0, y1 - y0}
end

moonshine.draw_shader = function(buffer, shader)
  local front, back = buffer()
  love.graphics.setCanvas(front)
  moonshine.clear()
  if shader ~= love.graphics.getShader() then
    love.graphics.setShader(shader)
  end
  love.graphics.draw(back)
end

moonshine.chain = function(w,h,effect)
  -- called as moonshine.chain(effect)'
  if h == nil then
    effect, w,h = w, love.window.getMode()
  end
  assert(effect ~= nil, "No effect")
-- print(w,h)
  local front, back = love.graphics.newCanvas(w,h), love.graphics.newCanvas(w,h)
  local buffer = function()
    back, front = front, back
    return front, back
  end

  local disabled = {} -- set of disabled effects
  local chain = {}
  chain.resize = function(w, h)
    front, back = love.graphics.newCanvas(w,h), love.graphics.newCanvas(w,h)
    return chain
  end

  -- `bounds` {x0, y0, x1, y1}: the screen rect func draws inside, if known.
  -- Every pass, and the result, is then clipped to where it can reach.
  chain.draw = function(func, bounds)
    -- save state
    local canvas = love.graphics.getCanvas()
    local shader = love.graphics.getShader()
    local fg_r, fg_g, fg_b, fg_a = love.graphics.getColor()
    local sx, sy, sw, sh = love.graphics.getScissor()

    -- draw scene to front buffer
    love.graphics.setCanvas((buffer())) -- parens are needed: take only front buffer
    love.graphics.clear(love.graphics.getBackgroundColor())
    func()

    -- save more state
    local blendmode = love.graphics.getBlendMode()

    -- process all shaders
    love.graphics.setColor(fg_r, fg_g, fg_b, fg_a)
    -- love.graphics.setBlendMode("lighten", "premultiplied")
    local cw, ch = front:getDimensions()
    local reach = bounds
    for _,e in ipairs(chain) do
      if not disabled[e.name] then
        local draw = e.draw or moonshine.draw_shader
        reach = reach and e.reach and e.reach(reach, cw, ch)
        moonshine.clip = reach and scissor(reach, cw, ch)
        if not reach then love.graphics.setScissor(sx, sy, sw, sh) end
        draw(buffer, e.shader)
      end
    end
    moonshine.clip = nil

    -- present result
    love.graphics.setShader()
    love.graphics.setCanvas(scene_canvas)
    if reach then
      local c = scissor(reach, cw, ch)
      love.graphics.setScissor(c[1], c[2], c[3], c[4])
    else
      love.graphics.setScissor(sx, sy, sw, sh)
    end
    love.graphics.draw(front,0,0)
    love.graphics.setScissor(sx, sy, sw, sh)

    -- restore state
    -- print(blendmode)
    if (blendmode == "lighten") then
      love.graphics.setBlendMode("lighten","premultiplied")
    else
      love.graphics.setBlendMode(blendmode)
    end
    
    love.graphics.setShader(shader)
  end

  chain.next = function(e)
    if type(e) == "function" then
      e = e()
    end
    assert(e.name, "Invalid effect: must provide `name'.")
    assert(e.shader or e.draw, "Invalid effect: must provide `shader' or `draw'.")
    table.insert(chain, e)
    return chain
  end
  chain.chain = chain.next

  chain.disable = function(name, ...)
    if name then
      disabled[name] = name
      return chain.disable(...)
    end
  end

  chain.enable = function(name, ...)
    if name then
      disabled[name] = nil
      return chain.enable(...)
    end
  end

  setmetatable(chain, {
    __call = function(_, ...) return chain.draw(...) end,
    __index = function(_,k)
      for _, e in ipairs(chain) do
        if e.name == k then return e end
      end
      error(("Effect `%s' not in chain"):format(k), 2)
    end,
    __newindex = function(_, k, v)
      if k == "parameters" or k == "params" or k == "settings" then
        for e,par in pairs(v) do
          for k,v in pairs(par) do
            chain[e][k] = v
          end
        end
      else
        rawset(chain, k, v)
      end
    end
  })

  return chain.next(effect)
end

moonshine.Effect = function(e)
  -- set defaults
  for k,v in pairs(e.defaults or {}) do
    assert(e.setters[k], ("No setter for parameter `%s'"):format(k))(v, k)
    e.setters[k](v,k)
  end

  -- expose setters
  return setmetatable(e, {
    __newindex = function(self,k,v)
      assert(self.setters[k], ("Unknown property: `%s.%s'"):format(e.name, k))
      self.setters[k](v, k)
    end})
end

-- autoloading effects
moonshine.effects = setmetatable({}, {__index = function(self, key)
  local ok, effect = pcall(require, BASE .. "." .. key)
  if not ok then
    error("No such effect: "..key, 2)
  end

  -- expose moonshine to effect
  local con = function(...) return effect(moonshine, ...) end

  -- cache effect constructor
  self[key] = con
  return con
end})

return setmetatable(moonshine, {__call = function(_, ...) return moonshine.chain(...) end})
