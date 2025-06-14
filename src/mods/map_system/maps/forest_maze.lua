-- Forest Maze Map
-- A more complex example showing Instance.new() style creation

-- Set a larger boundary for our maze
workspace.setBoundary(50, 50, 700, 600)

-- Fill with grass
workspace.fillArea(1, 1, 60, 50, "grass")

-- Create maze walls using Instance.new
local wallThickness = 32
local wallHeight = 64

-- Outer walls
for i = 0, 20 do
    Instance.new("Wall", {
        x = 50 + i * 32,
        y = 50,
        width = wallThickness,
        height = wallHeight
    })
    Instance.new("Wall", {
        x = 50 + i * 32,
        y = 650 - wallHeight,
        width = wallThickness,
        height = wallHeight
    })
end

for i = 0, 18 do
    Instance.new("Wall", {
        x = 50,
        y = 50 + i * 32,
        width = wallHeight,
        height = wallThickness
    })
    Instance.new("Wall", {
        x = 750 - wallHeight,
        y = 50 + i * 32,
        width = wallHeight,
        height = wallThickness
    })
end

-- Create internal maze structure
local mazeWalls = {
    {200, 150, 200, 32},  -- horizontal walls
    {200, 250, 150, 32},
    {400, 200, 32, 200},  -- vertical walls
    {300, 350, 32, 150},
    {500, 100, 32, 300},
    {150, 400, 300, 32},
    {600, 300, 100, 32}
}

for _, wall in ipairs(mazeWalls) do
    Instance.new("Wall", {
        x = wall[1],
        y = wall[2],
        width = wall[3],
        height = wall[4]
    })
end

-- Create a forest of trees
for i = 1, 30 do
    local x = utils.random(100, 700)
    local y = utils.random(100, 600)
    Instance.new("Tree", {x = x, y = y})
end

-- Place arches at key intersections
Instance.new("Arch", {x = 250, y = 200})
Instance.new("Arch", {x = 450, y = 300})
Instance.new("Arch", {x = 350, y = 450})

-- Set spawn points
Instance.new("PlayerSpawn", {x = 100, y = 100})

-- Enemy spawns scattered throughout
Instance.new("EnemySpawn", {x = 600, y = 500, enemyType = "basic"})
Instance.new("EnemySpawn", {x = 300, y = 300, enemyType = "fast"})
Instance.new("EnemySpawn", {x = 500, y = 200, enemyType = "basic"})
Instance.new("EnemySpawn", {x = 200, y = 500, enemyType = "heavy"})

-- Add some stone paths
for i = 1, 20 do
    local x = utils.random(5, 55)
    local y = utils.random(5, 45)
    Instance.new("Tile", {
        x = x,
        y = y,
        tileType = "stone"
    })
end

print("Forest Maze loaded!")
print("Navigate through the maze and avoid enemies!")
print("Features: Maze walls, forest cover, multiple enemy types")