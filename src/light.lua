local light = {}

function light.load()
      blueNeon = moonshine(moonshine.effects.glow).chain(moonshine.effects.fastgaussianblur).chain(moonshine.effects.godsray)
  blueNeon.godsray.exposure = 1 --number between 0 and 1
  blueNeon.godsray.decay = 0.8 -- number between 0 and 1
  blueNeon.godsray.density = 0.05 -- number between 0 and 1
  blueNeon.godsray.weight = 0.9 -- number between 0 and 1
  blueNeon.godsray.light_x = 0.5 -- number
  blueNeon.godsray.light_y = 0.5 -- number
  blueNeon.godsray.samples = 30 -- number >= 1
  blueNeon.glow.min_luma = 0
  blueNeon.glow.strength = 5

  yellowNeon = moonshine(moonshine.effects.glow).chain(moonshine.effects.fastgaussianblur).chain(moonshine.effects.godsray)
  yellowNeon.godsray.exposure = 0.2 --number between 0 and 1
  yellowNeon.godsray.decay = 0.8 -- number between 0 and 1
  yellowNeon.godsray.density = 0.05 -- number between 0 and 1
  yellowNeon.godsray.weight = 0.9 -- number between 0 and 1
  yellowNeon.godsray.light_x = 0.5 -- number
  yellowNeon.godsray.light_y = 0.5 -- number
  yellowNeon.godsray.samples = 30 -- number >= 1
  yellowNeon.glow.min_luma = 0
  yellowNeon.glow.strength = 5
  yellowNeon.fastgaussianblur.taps = 9
end



return light