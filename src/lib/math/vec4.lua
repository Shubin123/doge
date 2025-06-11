-- vec4 metatable:
local vec4 = {}

-- vec4.__index = vec4

-- vec4 constructor:
function vec4.new(x, y, z, w)
  local v = {x = x or 0, y = y or 0, z = z or 0, w = w or 0}
  setmetatable(v, vec4)
  return v
end

-- vec4 addition:
function vec4.__add(a, b)
  return vec4.new(a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w)
end

-- vec4 subtraction:
function vec4.__sub(a, b)
  return vec4.new(a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w)
end

-- multiplication of a vec4 by a scalar:
function vec4.__mul(a, b)
  if type(a) == "number" then
    return vec4.new(b.x * a, b.y * a, b.z * a, b.w * a)
  elseif type(b) == "number" then
    return vec4.new(a.x * b, a.y * b, a.z * b, a.w * b)
  else
    error("Can only multiply vector by scalar.")
  end
end

-- dividing a vec4 by a scalar:
function vec4.__div(a, b)
   if type(b) == "number" then
      return vec4.new(a.x / b, a.y / b, a.z / b, a.w / b)
   else
      error("Invalid argument types for vector division.")
   end
end

-- vec4 equivalence comparison:
function vec4.__eq(a, b)
	return a.x == b.x and a.y == b.y and a.z == b.z and a.w == b.w
end

-- vec4 not equivalence comparison:
function vec4.__ne(a, b)
	return not vec4.__eq(a, b)
end

-- unary negation operator:
function vec4.__unm(a)
	return vec4.new(-a.x, -a.y, -a.z, -a.w)
end

-- vec4 < comparison:
function vec4.__lt(a, b)
	 return a.x < b.x and a.y < b.y and a.z < b.z and a.w < b.w
end

-- vec4 <= comparison:
function vec4.__le(a, b)
	 return a.x <= b.x and a.y <= b.y and a.z <= b.z and a.w <= b.w
end

-- vec4 value string output:
function vec4.__tostring(v)
	 return "(" .. v.x .. ", " .. v.y .. ", " .. v.z .. ", " .. v.w .. ")"
end

return vec4