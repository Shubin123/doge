return {
  ["spritesPerRow"] = 16,
  ["totalSprites"] = 200,
  ["textureWidth"] = 2048,
  ["uniformHeight"] = 128,
  ["framesPerImageList"] = {    
    [1] = 200,
  },
  ["imageFiles"] = {
    [1] = "gfx/3d/steve/walk lowres.png", 
  },
  ["uniformWidth"] = 128,
  ["directionsPerImageList"] = {
    [1] = 8,
  },
  ["textureHeight"] = 2048,
  characterDefinitions = { -- single quad (1), 3d object rotated direction stored in single column (2), animated/ (animated-multi-spritesheet) (3).
        ["steve"] = {
            animations = {
                ["walk"] = 25,      -- gfx/3d/steve/walk lowres.png
            },
            defaultAnimation = "walk"
        }
    }
}