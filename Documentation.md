# This is a manually written document outlining the functionality of the game engine

# Core Engine components: Not accessible to users (to be exposed in the future)
-- The LocalPlayer
-- The Camera
-- The Shaders
-- The Preloaded Assets
-- The UI
-- The Renderer
-- The Physics/collisions engine
-- The notification system
-- The AudioAPI


# This game engine gives users special apis in order to create custom games!
-- Maps
-- Mods (such as weapons)
-- Mobs and Enemies

# Below is documentation on how to use the custom API to create custom content:

# Mods:
# Maps: Automatically handles rendering, collisions and multiplayer thanks to the engine api!
**This game uses the engine's built-in "map_system" in order to handle custom maps.**
**You can create a map by creating a `_.lua` file within `map_system/maps`. Here is where you should name the map with the file name.**
**To create a map you must use the built-in functions:**

---
### `workspace` Functions --> These functions provide a direct way to create and manipulate map elements.

* **Set the world boundary**: workspace.setBoundary(left, top, width, height)

* **Fill an area with a specific tile type**: workspace.fillArea(start_x, start_y, end_x, end_y, "tile_type")

* **Create a single wall**: workspace.createWall(x_pos, y_pos, width, height)

* **Place a tree**: workspace.createTree(x_pos, y_pos)

* **Place a arch**: workspace.createArch(x_pos, y_pos)

* **Set the player's spawn point**: workspace.setPlayerSpawn(x_pos, y_pos)

* **Add a spawn point for an enemy**: workspace.addEnemySpawn(x_pos, y_pos, "enemy_type")

* **Place a single tile by its ID**: workspace.placeTile(x_pos, y_pos, tile_id)

---
### `Instance.new()` Creation

This method allows for creating objects with named properties, offering an alternative way to build maps.

* **Create a wall instance**: Instance.new("Wall", {x = x_pos, y = y_pos, width = value, height = value})

* **Create a tree instance**: Instance.new("Tree", {x = x_pos, y = y_pos})

* **Create an arch instance**: Instance.new("Arch", {x = x_pos, y = y_pos})

* **Create a player spawn instance**: Instance.new("PlayerSpawn", {x = x_pos, y = y_pos})

* **Create an enemy spawn instance**: Instance.new("EnemySpawn", {x = x_pos, y = y_pos, enemyType = "enemy_type"})

* **Create a tile instance**: Instance.new("Tile", {x = x_pos, y = y_pos, tileType = "tile_type"})

---

### Utility Functions -->
* **Generate a random number**: utils.random(min_value, max_value)