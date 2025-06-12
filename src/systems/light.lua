local light = {}

function light.load()
      -- Try to create the effects chain, with fallback if glow effect isn't available
      local success, result = pcall(function()
        return moonshine(moonshine.effects.glow).chain(moonshine.effects.fastgaussianblur).chain(moonshine.effects.godsray)
      end)
      
      if success then
        blueNeon = result
      else
        print("Warning: Could not load glow effect, trying alternative blur effect")
        local success3, result3 = pcall(function()
          return moonshine(moonshine.effects.fastgaussianblur).chain(moonshine.effects.godsray)
        end)
        if success3 then
          blueNeon = result3
        else
          print("Warning: fastgaussianblur not available, using gaussianblur")
          local success4, result4 = pcall(function()
            return moonshine(moonshine.effects.gaussianblur).chain(moonshine.effects.godsray)
          end)
          if success4 then
            blueNeon = result4
          else
            print("Warning: Creating minimal moonshine chain with godsray only")
            blueNeon = moonshine(moonshine.effects.godsray)
          end
        end
      end
  blueNeon.godsray.exposure = 1 --number between 0 and 1
  blueNeon.godsray.decay = 0.8 -- number between 0 and 1
  blueNeon.godsray.density = 0.05 -- number between 0 and 1
  blueNeon.godsray.weight = 0.9 -- number between 0 and 1
  blueNeon.godsray.light_x = 0.5 -- number
  blueNeon.godsray.light_y = 0.5 -- number
  blueNeon.godsray.samples = 30 -- number >= 1
  if blueNeon.glow then
    blueNeon.glow.min_luma = 0
    blueNeon.glow.strength = 5
  end

  local success2, result2 = pcall(function()
    return moonshine(moonshine.effects.glow).chain(moonshine.effects.fastgaussianblur).chain(moonshine.effects.godsray)
  end)
  
  if success2 then
    yellowNeon = result2
  else
    print("Warning: Could not load glow effect for yellowNeon, trying alternative blur")
    local success5, result5 = pcall(function()
      return moonshine(moonshine.effects.fastgaussianblur).chain(moonshine.effects.godsray)
    end)
    if success5 then
      yellowNeon = result5
    else
      print("Warning: fastgaussianblur not available for yellowNeon, using gaussianblur")
      local success6, result6 = pcall(function()
        return moonshine(moonshine.effects.gaussianblur).chain(moonshine.effects.godsray)
      end)
      if success6 then
        yellowNeon = result6
      else
        print("Warning: Creating minimal yellowNeon moonshine chain with godsray only")
        yellowNeon = moonshine(moonshine.effects.godsray)
      end
    end
  end
  yellowNeon.godsray.exposure = 1 --number between 0 and 1
  yellowNeon.godsray.decay = 0.8 -- number between 0 and 1
  yellowNeon.godsray.density = 1 -- number between 0 and 1
  yellowNeon.godsray.weight = 0.9 -- number between 0 and 1
  yellowNeon.godsray.light_x = 0.5 -- number
  yellowNeon.godsray.light_y = 0.5 -- number
  yellowNeon.godsray.samples = 30 -- number >= 1
  if yellowNeon.glow then
    yellowNeon.glow.min_luma = 3
    yellowNeon.glow.strength = 5
  end
  yellowNeon.fastgaussianblur.taps = 9
end



return light