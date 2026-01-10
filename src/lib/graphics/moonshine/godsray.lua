return function(moonshine)
  local shader = love.graphics.newShader[[
    extern number exposure;
    extern number decay;
    extern number density;
    extern number weight;
    extern vec2 light_position;
    extern number samples;
    extern bool invert;

    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 px) {
      color = Texel(tex, uv);

      vec2 offset = invert ? (light_position - uv) * density / samples : (uv - light_position) * density / samples;
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

  for _,k in ipairs{"exposure", "decay", "density", "weight"} do
    setters[k] = function(v)
      shader:send(k, math.min(1, math.max(0, tonumber(v) or 0)))
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
    shader:send("samples", math.max(1,tonumber(v) or 1))
  end

  setters.invert = function(v)
    shader:send("invert", v and true or false)
  end

  local defaults = {
    exposure = 0.25,
    decay = 0.95,
    density = 0.15,
    weight = 0.5,
    light_position = {0.5,0.5},
    samples = 70,
    invert = false
  }

  return moonshine.Effect{
    name = "godsray",
    shader = shader,
    setters = setters,
    defaults = defaults
  }
end