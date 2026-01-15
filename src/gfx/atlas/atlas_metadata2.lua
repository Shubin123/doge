return {
 totalSprites = 4227,
 framesPerImageList = {
  [1] = 91,
  [2] = 92,
  [3] = 90,
  [4] = 92,
  [5] = 92,
  [6] = 91,
  [7] = 91,
  [8] = 1,
  [9] = 1,
  [10] = 1,
  [11] = 1,
  [12] = 112,
  [13] = 128,
  [14] = 256,
  [15] = 128,
  [16] = 120,
  [17] = 112,
  [18] = 112,
  [19] = 144,
  [20] = 88,
  [21] = 120,
  [22] = 112,
  [23] = 112,
  [24] = 744,
  [25] = 200,
  [26] = 240,
  [27] = 480,
  [28] = 232,
  [29] = 120,
  [30] = 8,
  [31] = 8,
  [32] = 8,
 },
 spritesPerRow = 128,
 directionsPerImageList = {
  [1] = 1,
  [2] = 1,
  [3] = 1,
  [4] = 1,
  [5] = 1,
  [6] = 1,
  [7] = 1,
  [8] = 1,
  [9] = 1,
  [10] = 1,
  [11] = 1,
  [12] = 8,
  [13] = 8,
  [14] = 8,
  [15] = 8,
  [16] = 8,
  [17] = 8,
  [18] = 8,
  [19] = 8,
  [20] = 8,
  [21] = 8,
  [22] = 8,
  [23] = 8,
  [24] = 8,
  [25] = 8,
  [26] = 8,
  [27] = 8,
  [28] = 8,
  [29] = 8,
  [30] = 8,
  [31] = 8,
  [32] = 8,
 },
 imageFiles = {
  [1] = "gfx/3d/sdr2/gun.png",
  [2] = "gfx/3d/sdr2/lauchergun.png",
  [3] = "gfx/3d/sdr2/portalGun.png",
  [4] = "gfx/3d/sdr2/car copy.png",
  [5] = "gfx/3d/sdr2/bike copy.png",
  [6] = "gfx/3d/sdr2/apple_2.png",
  [7] = "gfx/3d/sdr2/commodore64.png",
  [8] = "gfx/TileSet/tree1.png",
  [9] = "gfx/TileSet/arch.png",
  [10] = "gfx/TileSet/coin128.png",
  [11] = "gfx/TileSet/house128.png",
  [12] = "gfx/watchmanOfDoom_lowres/walk.png",
  [13] = "gfx/watchmanOfDoom_lowres/shoot_pistol.png",
  [14] = "gfx/watchmanOfDoom_lowres/death.png",
  [15] = "gfx/watchmanOfDoom_lowres/punch.png",
  [16] = "gfx/watchmanOfDoom_lowres/cast.png",
  [17] = "gfx/watchmanOfDoom_lowres/idle.png",
  [18] = "gfx/watchmanOfDoom_lowres/jump.png",
  [19] = "gfx/3d/princess/walk copy.png",
  [20] = "gfx/3d/princess/run copy.png",
  [21] = "gfx/3d/princess/shoot copy.png",
  [22] = "gfx/3d/princess/jump copy.png",
  [23] = "gfx/3d/princess/roll3.png",
  [24] = "gfx/3d/animated2.png",
  [25] = "gfx/3d/steve/walk lowres.png",
  [26] = "gfx/3d/mech/mech_walklowlowres.png",
  [27] = "gfx/3d/mech/attack_lowres.png",
  [28] = "gfx/3d/mech/dying_lowres.png",
  [29] = "gfx/3d/mech/shoot_lowres.png",
  [30] = "table/resized_table_top.png",
  [31] = "table/resized_table_side.png",
  [32] = "table/resized_table_bottom.png",
 },

  characterDefinitions = { -- single quad (1), 3d object rotated direction stored in single column (2), animated/ (animated-multi-spritesheet) (3).

        ["watchman"] = {
            animations = {
                ["walk"] = 12,  -- gfx/watchmanOfDoom_lowres/walk.png
                ["shoot"] = 13, -- gfx/watchmanOfDoom_lowres/shoot_pistol.png
                ["death"] = 14, -- gfx/watchmanOfDoom_lowres/death.png
                ["punch"] = 15, -- gfx/watchmanOfDoom_lowres/punch.png
                ["cast"] = 16,  -- gfx/watchmanOfDoom_lowres/cast.png
                ["idle"] = 17,  -- gfx/watchmanOfDoom_lowres/idle.png
                ["jump"] = 18,  -- gfx/watchmanOfDoom_lowres/jump.png
            },
            defaultAnimation = "idle"
        },
        ["princess"] = {
            animations = {
                ["walk"] = 19,  -- gfx/3d/princess/walk copy.png
                ["run"] = 20,   -- gfx/3d/princess/run copy.png
                ["shoot"] = 21, -- gfx/3d/princess/shoot copy.png
                ["jump"] = 22,  -- gfx/3d/princess/jump copy.png
                ["roll"] = 23,  -- gfx/3d/princess/roll3.png
            },
            defaultAnimation = "walk"
        },
        ["steve"] = {
            animations = {
                ["walk"] = 25, -- gfx/3d/steve/walk lowres.png
            },
            defaultAnimation = "walk"
        },
        ["mech"] = {
            animations = {
                ["walk"] = 26,   -- gfx/3d/mech/mech_walklowlowres.png
                ["attack"] = 27, -- gfx/3d/mech/attack_lowres.png
                ["death"] = 28,  -- gfx/3d/mech/dying_lowres.png
                ["shoot"] = 29,  -- gfx/3d/mech/shoot_lowres.png
            },
            defaultAnimation = "walk"
        },
        -- Single-sprite objects (weapons, items, etc.)
        ["gun"] = {
            animations = {
                ["default"] = 1, -- gfx/3d/singleDimensionRotate/gun.png
            },
            defaultAnimation = "default"
        },
        ["launcher"] = {
            animations = {
                ["default"] = 2, -- gfx/3d/singleDimensionRotate/lauchergun.png
            },
            defaultAnimation = "default"
        },
        ["portal_gun"] = {
            animations = {
                ["default"] = 3, -- gfx/3d/singleDimensionRotate/portalGun.png
            },
            defaultAnimation = "default"
        },
        ["car"] = {
            animations = {
                ["default"] = 4, -- gfx/3d/singleDimensionRotate/car copy.png
            },
            defaultAnimation = "default"
        },
        ["bike"] = {
            animations = {
                ["default"] = 5, -- gfx/3d/singleDimensionRotate/bike copy.png
            },
            defaultAnimation = "default"
        },
        ["apple"] = {
            animations = {
                ["default"] = 6, -- gfx/3d/singleDimensionRotate/apple_2.png
            },
            defaultAnimation = "default"
        },
        ["commodore64"] = {
            animations = {
                ["default"] = 7, -- gfx/3d/singleDimensionRotate/commodore64.png
            },
            defaultAnimation = "default"
        },
        -- Static environment objects
        ["tree"] = {
            animations = {
                ["default"] = 8, -- gfx/TileSet/tree1.png
            },
            defaultAnimation = "default"
        },
        ["arch"] = {
            animations = {
                ["default"] = 9, -- gfx/TileSet/arch.png
            },
            defaultAnimation = "default"
        },
        ["coin"] = {
            animations = {
                ["default"] = 10, -- gfx/TileSet/coin128.png
            },
            defaultAnimation = "default"
        },
        ["house"] = {
            animations = {
                ["default"] = 11, -- gfx/TileSet/house128.png
            },
            defaultAnimation = "default"
        },
        -- Special animated object
        ["animated_special"] = {
            animations = {
                ["default"] = 24, -- gfx/3d/animated2.png
            },
            defaultAnimation = "default"
        },
         ["table"] = {
            animations = {
                ["top"] = 30, -- gfx/3d/animated2.png
                ["side"] = 31, -- gfx/3d/animated2.png
                ["bottom"] = 32, -- gfx/3d/animated2.png
            },
            defaultAnimation = "side"
        }

    },
 textureWidth = 16384,
 textureHeight = 16384,
 uniformHeight = 128,
 uniformWidth = 128,
}