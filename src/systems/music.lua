-- music.lua
-- Manages pitch variation patterns for different sound sources in the game.
-- Provides user-definable musical patterns for specific sounds like coins.

local music = {}

-- Define musical scales for pitch variation
-- Each scale is a table of pitch multipliers relative to a base note (1.0)
music.scales = {
  c_major = {1.0, 1.122, 1.26, 1.335, 1.5, 1.682, 1.888}, -- C major (C, D, E, F, G, A, B)

  a_minor = {1.0, 1.122, 1.189, 1.335, 1.5, 1.587, 1.782}, -- A minor (A, B, C, D, E, F, G)

  c_minor = {1.0, 1.122, 1.189, 1.335, 1.414, 1.587, 1.682}, -- C natural minor (C, D, D#, F, F#, G#, A#)

  d_sharp_dim = {1.0, 1.189, 1.414, 1.682, 1.782, 2.0}, -- D# diminished scale

  pentatonic_major = {1.0, 1.122, 1.26, 1.5, 1.682}, -- Pentatonic major (C, D, E, G, A)

  pentatonic_minor = {1.0, 1.189, 1.335, 1.5, 1.782}, -- Pentatonic minor (C, D#, F, G, A#)

  blues = {1.0, 1.189, 1.26, 1.335, 1.5, 1.782}, -- Blues scale (C, D#, E, F, G, A#)

  harmonic_minor = {1.0, 1.122, 1.189, 1.335, 1.5, 1.587, 1.888}, -- Harmonic minor (A, B, C, D, E, F, G#)

  lydian = {1.0, 1.122, 1.26, 1.414, 1.5, 1.682, 1.888}, -- Lydian mode (C, D, E, F#, G, A, B)

  mixolydian = {1.0, 1.122, 1.26, 1.335, 1.5, 1.682, 1.782}, -- Mixolydian mode (C, D, E, F, G, A, A#)

  whole_tone = {1.0, 1.122, 1.26, 1.414, 1.587, 1.782}, -- Whole tone scale

  chromatic = {1.0, 1.059, 1.122, 1.189, 1.26, 1.335, 1.414, 1.5, 1.587, 1.682, 1.782, 1.888}, -- 12-tone chromatic scale
}
music.sequences = {
  -- Heroic rise and fall
  heroic_ascend = {1, 3, 5, 6, 5, 3, 1},

  -- Jumping melody with tension and release
  bounce_back = {1, 4, 2, 5, 3, 6, 4, 7, 5, 1},

  -- Victory fanfare vibe
  fanfare = {1, 5, 3, 6, 4, 7, 5, 1},

  -- Arpeggiated happiness
  happy_arp = {1, 3, 5, 8, 5, 3, 1},

  -- Quick loop, great for idle or menu music
  menu_loop = {1, 2, 3, 5, 3, 2},

  -- Platformer run loop
  runner = {1, 3, 2, 4, 3, 5, 4, 6, 5, 7},

  -- Bit-style melody: tight, repeating
  chiptune_hop = {1, 3, 4, 3, 5, 4, 6, 5, 7, 6, 1},

  -- Trickster bounce
  zigzag = {1, 4, 2, 5, 3, 6, 2, 5, 1},

  -- Turbo loop for boss intros or high-speed sections
  turbo_spin = {1, 5, 3, 7, 2, 6, 4, 1},

  -- Mischievous dance
  imp_dance = {3, 1, 4, 2, 5, 3, 6, 4, 7, 5},

  -- Bonus level tune
  bonus_jingle = {1, 3, 5, 7, 6, 4, 2, 1},
  rapid_fire_extended = {
  1, 1, 2, 2, 3, 2, 4, 3,
  5, 5, 4, 4, 3, 2, 1, 1
},
}



-- Default pitch variation patterns for different sound sources
-- Each pattern references a scale and a sequence of indices to play from that scale
music.patterns = {
  coin = {
    scale = "lydian",
    sequence = music.sequences.chiptune_hop, -- A simple up-and-down pattern in the scale
    currentIndex = 1
  },
  gun1 = {
    scale = nil, -- No scale, use random variation if needed
    variation = 0.1 -- Random pitch variation range +/- 10%
  },
  gun2 = {
    scale = nil,
    variation = 0.05 -- Random pitch variation range +/- 5%
  },
  gun3 = {
    scale = "c_minor",
    sequence = {1, 3, 5, 7, 5, 3, 1},
    currentIndex = 1
  },
  gun4 = {
    scale = "lydian",
    sequence = music.sequences.rapid_fire_extended,
    currentIndex = 1
  },
  explosion = {
    scale = nil,
    variation = 0.2 -- Random pitch variation range +/- 20%
  },
  fire = {
    scale = nil,
    variation = 0.1 -- Random pitch variation range +/- 10%
  }
}

-- Function to get the next pitch for a sound source based on its pattern
function music.getNextPitch(soundType)
  local pattern = music.patterns[soundType]
  if not pattern then
    return 1.0 -- Default pitch if no pattern defined
  end

  if pattern.scale then
    -- Use scale-based pattern
    local scale = music.scales[pattern.scale]
    if not scale then
      return 1.0 -- Default if scale not found
    end
    local pitchIndex = pattern.sequence[pattern.currentIndex]
    local pitch = scale[pitchIndex]
    -- Move to the next index in the sequence
    pattern.currentIndex = (pattern.currentIndex % #pattern.sequence) + 1
    return pitch
  elseif pattern.variation then
    -- Use random variation
    return 1.0 + (love.math.random() * 2 * pattern.variation) - pattern.variation
  end

  return 1.0 -- Default pitch
end

-- Function to set a custom scale for a sound type
function music.setScale(soundType, scaleName)
  if music.patterns[soundType] and music.scales[scaleName] then
    music.patterns[soundType].scale = scaleName
  end
end

-- Function to set a custom sequence for a sound type
function music.setSequence(soundType, sequence)
  if music.patterns[soundType] then
    music.patterns[soundType].sequence = sequence
    music.patterns[soundType].currentIndex = 1
  end
end

return music
