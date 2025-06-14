-- Starter Map
-- A simple map for getting started with the game

-- Set world boundary (smaller for starter map)
workspace.setBoundary(150, 100, 300, 300)

-- Fill with grass
workspace.fillArea(1, 1, 30, 30, "grass")

-- Place a few trees for decoration
workspace.createTree(200, 150)
workspace.createTree(400, 150)
workspace.createTree(200, 350)
workspace.createTree(400, 350)

-- Add one arch in the center
workspace.createArch(300, 250)

-- Set player spawn
workspace.setPlayerSpawn(300, 250)

-- Just one enemy spawn for beginners
workspace.addEnemySpawn(200, 150, "basic")

print("Starter map loaded - a simple arena to begin your adventure!")