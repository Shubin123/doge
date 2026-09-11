  This will guide you on how maps are handled in this game and how to craft new ones! :

  Map System Overview

  The map is currently semi-hardcoded with a tileset-based
  system and dynamic object placement:

  1. Base Tile Map (Randomly Generated)

  - Uses tileset images from gfx/TileSet/ directory
  - In map.load() (src/game/map.lua:575-584), tiles are
  randomly placed:
  for x = 1, 70 do
      for y = 1, 50 do
          map.map:setTile(x, y, math.random(1,200))
      end
  end

  2. Dynamic Objects (Arches & Trees)

  - Arches: Stone archways that act as obstacles
  - Trees: Decorative elements with collision
  - These can be placed/moved/deleted using the built-in
  editor

  3. Map Editor

  The game has a built-in level editor accessible via
  console:
  - Enable: Type editor.enable in cmndX console
  - Disable: Type editor.disable in cmndX console
  - Editor modes:
    - 1: Select/move/delete objects (right-click to delete)
    - 2: Create arches
    - 3: Create trees

  4. Save/Load System

  The map system includes serialization functions:
  - map.createSaveData(): Captures current map state
  - map.restore(map_data): Restores saved map
  - This allows saving custom-designed levels

  5. Advanced Features (Partially Implemented)

  The code includes infrastructure for:
  - Chunk-based loading for large maps
  - Multiple layers (ground, decoration, collision, overlay)
  - Component-based objects with physics integration

  However, the actual game currently uses the simpler tile +
   dynamic objects approach rather than the full chunk
  system.

  

  To create custom maps, you would:
  1. Enable the editor with editor.enable
  2. Place arches and trees using modes 2 & 3
  3. Use the save system to persist your design
  4. Or modify the hardcoded tile generation in map.load()

Map Boundary System:

  The game uses LÖVE2D's Box2D physics engine for collision detection.
  The boundaries are created as invisible physics bodies that act like
  walls.

  Boundary Setup (main.lua:81-85):
  fence_body = love.physics.newBody(world, 0, 0, "static")
  fence_shape = love.physics.newChainShape(true, 200, 50, var.game_width
  + 200, 50, var.game_width + 200,
      var.game_height + 50, 200, var.game_height + 50)
  fence_fixture = love.physics.newFixture(fence_body, fence_shape)

  This creates a rectangular boundary around the game area:
  - Top edge: From (200, 50) to (game_width + 200, 50)
  - Right edge: From (game_width + 200, 50) to (game_width + 200,
  game_height + 50)
  - Bottom edge: From (game_width + 200, game_height + 50) to (200,
  game_height + 50)
  - Left edge: From (200, game_height + 50) back to (200, 50)

  How It Works:
  1. Physics World: world = love.physics.newWorld(0, 0) creates a physics
   world with no gravity
  2. Static Body: The fence is a "static" body - it doesn't move but
  blocks other objects
  3. Chain Shape: Creates connected line segments forming a closed
  rectangle
  4. Automatic Collision: Players, enemies, and bullets automatically
  collide with this invisible fence

  Key Points:
  - Invisible: The fence has no visual representation - it's pure
  collision
  - Automatic: Box2D handles all collision detection and response
  - Offset: The fence starts at (200, 50) instead of (0, 0), creating a
  border around the game area
  - Player/Enemy Bodies: Must also be physics bodies to interact with the
   fence

-- Thats all, thanks for reading. Return to previous task. --return 

