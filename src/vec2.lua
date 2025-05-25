 -- vec2 metatable:
local vec2 = {}
vec2.__index = vec2

-- vec2 constructor:
function vec2.new(x, y)
  local v = {x = x or 0, y = y or 0}
  setmetatable(v, vec2)
  return v
end

-- vec2 addition:
function vec2.__add(a, b)
  return vec2.new(a.x + b.x, a.y + b.y)
end

-- vec2 subtraction:
function vec2.__sub(a, b)
  return vec2.new(a.x - b.x, a.y - b.y)
end

-- multiplication of a vec2 by a scalar:
function vec2.__mul(a, b)
  if type(a) == "number" then
    return vec2.new(b.x * a, b.y * a)
  elseif type(b) == "number" then
    return vec2.new(a.x * b, a.y * b)
  else
    error("Can only multiply vec2 by scalar.")
  end
end

-- dividing a vec2 by a scalar:
function vec2.__div(a, b)
   if type(b) == "number" then
      return vec2.new(a.x / b, a.y / b)
   else
      error("Invalid argument types for vec2 division.")
   end
end

-- vec2 equivalence comparison:
function vec2.__eq(a, b)
	return a.x == b.x and a.y == b.y
end

-- vec2 not equivalence comparison:
function vec2.__ne(a, b)
	return not vec2.__eq(a, b)
end

-- unary negation operator:
function vec2.__unm(a)
	return vec2.new(-a.x, -a.y)
end

-- vec2 < comparison:
function vec2.__lt(a, b)
	 return a.x < b.x and a.y < b.y
end

-- vec2 <= comparison:
function vec2.__le(a, b)
	 return a.x <= b.x and a.y <= b.y
end

-- vec2 value string output:
function vec2.__tostring(v)
	 return "(" .. v.x .. ", " .. v.y .. ")"
end
return vec2