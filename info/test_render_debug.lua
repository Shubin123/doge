-- Test script to debug rendering issues
-- Run this to check if render queue is working

-- Access the renderer and check its state
local rendererPlus = require("lib.graphics.new_renderer")

print("\n=== RENDERER DEBUG TEST ===")

-- Check if renderer is initialized
print("Renderer debug mode:", rendererPlus.debug_mode)

-- Try to manually add something to the render queue
print("\nTesting render queue...")

-- Clear queue first
rendererPlus.clearQueue()

-- Add a test rectangle to world layer
rendererPlus.addToQueue("world", {
    type = "rectangle",
    mode = "fill",
    x = 200,
    y = 200,
    width = 50,
    height = 50,
    color = {1, 0, 0, 1},
    active = true,
    sort_y = 200
})

print("Added test rectangle to world queue")

-- Add a test circle
rendererPlus.addToQueue("world", {
    type = "circle",
    mode = "fill", 
    x = 300,
    y = 200,
    radius = 25,
    color = {0, 1, 0, 1},
    active = true,
    sort_y = 200
})

print("Added test circle to world queue")

-- Check if textures are loaded
print("\nChecking loaded textures...")
local texture_count = 0
if rendererPlus.assets then
    for name, texture in pairs(rendererPlus.assets.textures or {}) do
        texture_count = texture_count + 1
        if name == "doge" or name == "player_jump" then
            print("  Found key texture:", name)
        end
    end
end
print("Total textures loaded:", texture_count)

print("\n=== END DEBUG TEST ===\n")

return true