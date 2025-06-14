-- Test Arena Map
-- Example map showing how to create a custom map using the Map System API

-- Set the world boundary (fence)
-- Parameters: left, top, width, height
workspace.setBoundary(100, 100, 500, 400)

-- Fill the ground with grass tiles
workspace.fillArea(1, 1, 50, 40, "grass")

-- Create some walls around the edges
for i = 1, 20 do
    -- Top wall
    workspace.createWall(100 + i * 25, 100, 25, 10)
    -- Bottom wall  
    workspace.createWall(100 + i * 25, 490, 25, 10)
    -- Left wall
    workspace.createWall(100, 100 + i * 20, 10, 20)
    -- Right wall
    workspace.createWall(590, 100 + i * 20, 10, 20)
end

-- Add some arches for decoration
workspace.createArch(250, 250)
workspace.createArch(450, 250)
workspace.createArch(250, 350)
workspace.createArch(450, 350)

-- Add trees for cover
workspace.createTree(300, 200)
workspace.createTree(400, 200)
workspace.createTree(300, 400)
workspace.createTree(400, 400)
workspace.createTree(200, 300)
workspace.createTree(500, 300)

-- Set player spawn point
workspace.setPlayerSpawn(350, 300)

-- Add some enemy spawn points
workspace.addEnemySpawn(150, 150, "basic")
workspace.addEnemySpawn(550, 150, "basic")
workspace.addEnemySpawn(150, 450, "basic")
workspace.addEnemySpawn(550, 450, "basic")

-- Create some decorative tiles
for i = 1, 10 do
    local x = utils.random(5, 45)
    local y = utils.random(5, 35)
    workspace.placeTile(x, y, utils.random(201, 250)) -- Stone tiles
end

print("Test Arena map loaded!")
print("- Boundary set to 500x400")
print("- Walls around edges")
print("- 4 arches and 6 trees placed")
print("- Player spawn at center")
print("- 4 enemy spawn points at corners")