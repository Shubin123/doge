--
-- lurker
--
-- Copyright (c) 2018 rxi
--
-- This library is free software; you can redistribute it and/or modify it
-- under the terms of the MIT license. See LICENSE for details.
--

-- Minimal lume functions embedded to remove dependency
local function each(tbl, fn)
  if type(tbl) == "table" then
    for i, v in ipairs(tbl) do
      fn(v, i)
    end
  end
  return tbl
end

local function map(tbl, fn)
  local result = {}
  if type(tbl) == "table" then
    for i, v in ipairs(tbl) do
      result[i] = fn(v, i)
    end
  end
  return result
end

local function filter(tbl, fn)
  local result = {}
  if type(tbl) == "table" then
    for i, v in ipairs(tbl) do
      if fn(v, i) then
        table.insert(result, v)
      end
    end
  end
  return result
end

local function concat(...)
  local result = {}
  for i = 1, select("#", ...) do
    local tbl = select(i, ...)
    if type(tbl) == "table" then
      for j = 1, #tbl do
        table.insert(result, tbl[j])
      end
    end
  end
  return result
end

local function format(str, vars)
  if not vars then return str end
  return (str:gsub("{(%d+)}", function(i)
    return tostring(vars[tonumber(i)])
  end))
end

local function trim(str, chars)
  if not str then return "" end
  chars = chars or "%s"
  return str:match("^[" .. chars .. "]*(.-)[" .. chars .. "]*$")
end

local function color(hex, base)
  base = base or 1
  hex = hex:gsub("#", "")
  local r = tonumber(hex:sub(1, 2), 16) / 255
  local g = tonumber(hex:sub(3, 4), 16) / 255
  local b = tonumber(hex:sub(5, 6), 16) / 255
  if base == 256 then
    return {r, g, b}
  end
  return r, g, b
end

local function smooth(a, b, t)
  t = math.max(0, math.min(1, t))
  return a + (b - a) * t * t * (3 - 2 * t)
end

local function pingpong(t)
  return 1 - math.abs(1 - (t % 2))
end

local function time(fn, ...)
  local start = love.timer.getTime()
  local ok, result = pcall(fn, ...)
  local elapsed = love.timer.getTime() - start
  return elapsed, ok, result
end

local function hotswap(modname)
  local oldglobal = _G
  local updated = {}
  local function update(old, new)
    if type(old) ~= "table" then return new end
    if updated[old] then return old end
    updated[old] = true
    for k, v in pairs(new) do
      if type(v) == "table" then
        old[k] = update(old[k], v)
      else
        old[k] = v
      end
    end
    return old
  end
  local err = nil
  local function onerror(e)
    err = e
  end
  local oldmod = package.loaded[modname]
  package.loaded[modname] = nil
  local ok, newmod = xpcall(require, onerror, modname)
  if not ok then
    package.loaded[modname] = oldmod
    return nil, err
  end
  if type(oldmod) == "table" then
    update(oldmod, newmod)
    package.loaded[modname] = oldmod
  end
  return oldmod
end

local lurker = { _version = "1.0.1" }


local dir = love.filesystem.enumerate or love.filesystem.getDirectoryItems
local time = love.timer.getTime or os.time

local function isdir(path)
    local info = love.filesystem.getInfo(path)
    return info.type == "directory"
end

local function lastmodified(path)
    local info = love.filesystem.getInfo(path, "file")
    return info.modtime
end

local lovecallbacknames = {
  "update",
  "load",
  "draw",
  "mousepressed",
  "mousereleased",
  "keypressed",
  "keyreleased",
  "focus",
  "quit",
}


function lurker.init()
  lurker.print("Initing lurker")
  lurker.path = "."
  lurker.preswap = function() end
  lurker.postswap = function() end
  lurker.interval = .5
  lurker.protected = true
  lurker.quiet = false
  lurker.lastscan = 0
  lurker.lasterrorfile = nil
  lurker.files = {}
  lurker.funcwrappers = {}
  lurker.lovefuncs = {}
  lurker.state = "init"
  each(lurker.getchanged(), lurker.resetfile)
  return lurker
end


function lurker.print(...)
  print("[lurker] " .. format(...))
end


function lurker.listdir(path, recursive, skipdotfiles)
  path = (path == ".") and "" or path
  local function fullpath(x) return path .. "/" .. x end
  local t = {}
  for _, f in pairs(map(dir(path), fullpath)) do
    if not skipdotfiles or not f:match("/%.[^/]*$") then
      if recursive and isdir(f) then
        t = concat(t, lurker.listdir(f, true, true))
      else
        table.insert(t, trim(f, "/"))
      end
    end
  end
  return t
end


function lurker.initwrappers()
  for _, v in pairs(lovecallbacknames) do
    lurker.funcwrappers[v] = function(...)
      local args = {...}
      xpcall(function()
        return lurker.lovefuncs[v] and lurker.lovefuncs[v](unpack(args))
      end, lurker.onerror)
    end
    lurker.lovefuncs[v] = love[v]
  end
  lurker.updatewrappers()
end


function lurker.updatewrappers()
  for _, v in pairs(lovecallbacknames) do
    if love[v] ~= lurker.funcwrappers[v] then
      lurker.lovefuncs[v] = love[v]
      love[v] = lurker.funcwrappers[v]
    end
  end
end


function lurker.onerror(e, nostacktrace)
  lurker.print("An error occurred; switching to error state")
  lurker.state = "error"

  -- Release mouse
  local setgrab = love.mouse.setGrab or love.mouse.setGrabbed
  setgrab(false)

  -- Set up callbacks
  for _, v in pairs(lovecallbacknames) do
    love[v] = function() end
  end

  love.update = lurker.update

  love.keypressed = function(k)
    if k == "escape" then
      lurker.print("Exiting...")
      love.event.quit()
    end
  end

  local stacktrace = nostacktrace and "" or
                     trim((debug.traceback("", 2):gsub("\t", "")))
  local msg = format("{1}\n\n{2}", {e, stacktrace})
  local colors = {
    { color("#1e1e2c", 256) },
    { color("#f0a3a3", 256) },
    { color("#92b5b0", 256) },
    { color("#66666a", 256) },
    { color("#cdcdcd", 256) },
  }
  love.graphics.reset()
  love.graphics.setFont(love.graphics.newFont(12))

  love.draw = function()
    local pad = 25
    local width = love.graphics.getWidth()

    local function drawhr(pos, color1, color2)
      local animpos = smooth(pad, width - pad - 8, pingpong(time()))
      if color1 then love.graphics.setColor(color1) end
      love.graphics.rectangle("fill", pad, pos, width - pad*2, 1)
      if color2 then love.graphics.setColor(color2) end
      love.graphics.rectangle("fill", animpos, pos, 8, 1)
    end

    local function drawtext(str, x, y, color, limit)
      love.graphics.setColor(color)
      love.graphics[limit and "printf" or "print"](str, x, y, limit)
    end

    love.graphics.setBackgroundColor(colors[1])
    love.graphics.clear()

    drawtext("An error has occurred", pad, pad, colors[2])
    drawtext("lurker", width - love.graphics.getFont():getWidth("lurker") -
             pad, pad, colors[4])
    drawhr(pad + 32, colors[4], colors[5])
    drawtext("If you fix the problem and update the file the program will " ..
             "resume", pad, pad + 46, colors[3])
    drawhr(pad + 72, colors[4], colors[5])
    drawtext(msg, pad, pad + 90, colors[5], width - pad * 2)

    love.graphics.reset()
  end
end


function lurker.exitinitstate()
  lurker.state = "normal"
  if lurker.protected then
    lurker.initwrappers()
  end
end


function lurker.exiterrorstate()
  lurker.state = "normal"
  for _, v in pairs(lovecallbacknames) do
    love[v] = lurker.funcwrappers[v]
  end
end


function lurker.update()
  if lurker.state == "init" then
    lurker.exitinitstate()
  end
  local diff = time() - lurker.lastscan
  if diff > lurker.interval then
    lurker.lastscan = lurker.lastscan + diff
    local changed = lurker.scan()
    if #changed > 0 and lurker.lasterrorfile then
      local f = lurker.lasterrorfile
      lurker.lasterrorfile = nil
      lurker.hotswapfile(f)
    end
  end
end


function lurker.getchanged()
  local function fn(f)
    return f:match("%.lua$") and lurker.files[f] ~= lastmodified(f)
  end
  return filter(lurker.listdir(lurker.path, true, true), fn)
end


function lurker.modname(f)
  return (f:gsub("%.lua$", ""):gsub("[/\\]", "."))
end


function lurker.resetfile(f)
  lurker.files[f] = lastmodified(f)
end


function lurker.hotswapfile(f)
  lurker.print("Hotswapping '{1}'...", {f})
  if lurker.state == "error" then
    lurker.exiterrorstate()
  end
  if lurker.preswap(f) then
    lurker.print("Hotswap of '{1}' aborted by preswap", {f})
    lurker.resetfile(f)
    return
  end
  local modname = lurker.modname(f)
  local t, ok, err = time(hotswap, modname)
  if ok then
    lurker.print("Swapped '{1}' in {2} secs", {f, t})
  else
    lurker.print("Failed to swap '{1}' : {2}", {f, err})
    if not lurker.quiet and lurker.protected then
      lurker.lasterrorfile = f
      lurker.onerror(err, true)
      lurker.resetfile(f)
      return
    end
  end
  lurker.resetfile(f)
  lurker.postswap(f)
  if lurker.protected then
    lurker.updatewrappers()
  end
end


function lurker.scan()
  if lurker.state == "init" then
    lurker.exitinitstate()
  end
  local changed = lurker.getchanged()
  each(changed, lurker.hotswapfile)
  return changed
end


return lurker.init()
