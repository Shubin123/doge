-- Glowing Tree Demo
-- Example usage of the new glowing tree entity system with the new renderer

local rendererPlus = require("src.lib.graphics.new_renderer")
local glowingTree = require("src.entities.glowing_tree")

local demo = {}

-- Demo state
local camera_x, camera_y = 0, 0
local player_x, player_y = 400, 300
local demo_initialized = false

-- Demo controls
local controls = {
    wind_strength = 1.0,
    magic_intensity = 0.8,
    show_debug = false
}

-- Initialize the demo
function demo.init()
    print("[TREE_DEMO] Initializing glowing tree demo...")
    
    -- Initialize new renderer
    rendererPlus.init()
    
    -- Initialize glowing tree system
    if not glowingTree.init(rendererPlus) then
        print("[TREE_DEMO] Failed to initialize glowing tree system!")
        return false
    end
    
    -- Create demo scene
    demo.createScene()
    
    demo_initialized = true
    print("[TREE_DEMO] Demo initialized successfully!")
    return true
end

-- Create the demo scene
function demo.createScene()
    print("[TREE_DEMO] Creating magical forest scene...")
    
    -- Create a magical grove in the center
    glowingTree.createDemoScene(400, 300)
    
    -- Add more trees around the area
    glowingTree.spawnTreesInArea(400, 300, 200, 8, {"MYSTICAL", "ANCIENT", "ENCHANTED"})
    
    -- Create some scattered trees
    glowingTree.createTree(100, 150, "ENCHANTED", 60)
    glowingTree.createTree(700, 200, "ANCIENT", 110)
    glowingTree.createTree(200, 450, "MYSTICAL", 85)
    glowingTree.createTree(600, 500, "ENCHANTED", 95)
    
    print("[TREE_DEMO] Created magical forest with " .. glowingTree.getTreeCount() .. " trees")
end

-- Update demo
function demo.update(dt)
    if not demo_initialized then return end
    
    -- Handle input
    demo.handleInput(dt)
    
    -- Update camera to follow player
    camera_x = player_x - love.graphics.getWidth() / 2
    camera_y = player_y - love.graphics.getHeight() / 2
    
    -- Update glowing trees
    glowingTree.update(dt)
    
    -- Check for tree interactions
    local nearby_tree = glowingTree.checkInteraction(player_x, player_y)
    if nearby_tree and love.keyboard.isDown("e") then
        -- Simulate player object for healing
        local player = { health = 80, max_health = 100 }
        glowingTree.interactWithTree(nearby_tree, player)
    end
    
    -- Clear and populate render queue
    rendererPlus.clearQueue()
    
    -- Add background
    rendererPlus.addToQueue("background", {
        type = "rectangle",
        mode = "fill",
        x = -1000, y = -1000,
        width = 2000, height = 2000,
        sort_y = -1000,
        active = true,
        color = {0.05, 0.1, 0.15, 1},
        blend_mode = {"alpha"}
    })
    
    -- Add simple player representation
    rendererPlus.addToQueue("world", {
        type = "circle",
        mode = "fill",
        x = player_x, y = player_y,
        radius = 10,
        sort_y = player_y,
        active = true,
        color = {0.8, 0.8, 1, 1},
        blend_mode = {"alpha"}
    })
    
    -- Add interaction indicator
    if nearby_tree then
        rendererPlus.addToQueue("ui", {
            type = "text",
            text = "Press E to interact with magical tree",
            x = 10, y = love.graphics.getHeight() - 30,
            sort_y = 10000,
            active = true,
            color = {1, 1, 1, 1},
            font = love.graphics.getFont()
        })
    end
    
    -- Add debug info
    if controls.show_debug then
        demo.addDebugInfo()
    end
end

-- Handle user input
function demo.handleInput(dt)
    local speed = 200
    
    -- Player movement
    if love.keyboard.isDown("w", "up") then
        player_y = player_y - speed * dt
    end
    if love.keyboard.isDown("s", "down") then
        player_y = player_y + speed * dt
    end
    if love.keyboard.isDown("a", "left") then
        player_x = player_x - speed * dt
    end
    if love.keyboard.isDown("d", "right") then
        player_x = player_x + speed * dt
    end
end

-- Handle key presses
function demo.keypressed(key)
    if key == "1" then
        -- Increase wind strength
        controls.wind_strength = math.min(2.0, controls.wind_strength + 0.2)
        glowingTree.setWindStrength(controls.wind_strength)
        print("[TREE_DEMO] Wind strength: " .. string.format("%.1f", controls.wind_strength))
        
    elseif key == "2" then
        -- Decrease wind strength
        controls.wind_strength = math.max(0.0, controls.wind_strength - 0.2)
        glowingTree.setWindStrength(controls.wind_strength)
        print("[TREE_DEMO] Wind strength: " .. string.format("%.1f", controls.wind_strength))
        
    elseif key == "3" then
        -- Increase magic intensity
        controls.magic_intensity = math.min(1.5, controls.magic_intensity + 0.1)
        glowingTree.setMagicIntensity(controls.magic_intensity)
        print("[TREE_DEMO] Magic intensity: " .. string.format("%.1f", controls.magic_intensity))
        
    elseif key == "4" then
        -- Decrease magic intensity
        controls.magic_intensity = math.max(0.0, controls.magic_intensity - 0.1)
        glowingTree.setMagicIntensity(controls.magic_intensity)
        print("[TREE_DEMO] Magic intensity: " .. string.format("%.1f", controls.magic_intensity))
        
    elseif key == "g" then
        -- Toggle glow effects
        glowingTree.toggleGlowEffect()
        
    elseif key == "r" then
        -- Respawn trees
        glowingTree.cleanup()
        demo.createScene()
        print("[TREE_DEMO] Respawned magical forest!")
        
    elseif key == "t" then
        -- Add random tree at player position
        local tree_types = {"MYSTICAL", "ANCIENT", "ENCHANTED"}
        local random_type = tree_types[math.random(#tree_types)]
        glowingTree.createTree(player_x, player_y, random_type, 80 + math.random(40))
        print("[TREE_DEMO] Spawned " .. random_type .. " tree at player position")
        
    elseif key == "f3" then
        -- Toggle debug info
        controls.show_debug = not controls.show_debug
        rendererPlus.debug_mode = controls.show_debug
        
    elseif key == "escape" then
        -- Exit demo
        love.event.quit()
    end
end

-- Add debug information to render queue
function demo.addDebugInfo()
    local debug_lines = {
        "=== GLOWING TREE DEMO DEBUG ===",
        "Trees: " .. glowingTree.getTreeCount(),
        "Player: (" .. math.floor(player_x) .. ", " .. math.floor(player_y) .. ")",
        "Wind: " .. string.format("%.1f", controls.wind_strength),
        "Magic: " .. string.format("%.1f", controls.magic_intensity),
        "",
        "Controls:",
        "WASD/Arrows - Move player",
        "E - Interact with tree",
        "1/2 - Wind strength +/-",
        "3/4 - Magic intensity +/-",
        "G - Toggle glow effects",
        "R - Respawn forest",
        "T - Spawn tree at player",
        "F3 - Toggle debug",
        "ESC - Exit"
    }
    
    for i, line in ipairs(debug_lines) do
        rendererPlus.addToQueue("ui", {
            type = "text",
            text = line,
            x = love.graphics.getWidth() - 300,
            y = 10 + (i - 1) * 16,
            sort_y = 10000 + i,
            active = true,
            color = {1, 1, 0, 1},
            font = love.graphics.getFont()
        })
    end
end

-- Render the demo
function demo.draw()
    if not demo_initialized then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("Initializing glowing tree demo...", 10, 10)
        return
    end
    
    -- Apply camera transform
    love.graphics.push()
    love.graphics.translate(-camera_x, -camera_y)
    
    -- Render using new renderer
    rendererPlus.render(love.timer.getDelta())
    
    love.graphics.pop()
    
    -- UI overlay (not affected by camera)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.print("Magical Forest Demo - F3 for controls", 10, 10)
end

-- Cleanup
function demo.cleanup()
    if glowingTree then
        glowingTree.cleanup()
    end
    if rendererPlus then
        rendererPlus.cleanup()
    end
    print("[TREE_DEMO] Demo cleanup complete")
end

-- Love2D callbacks for standalone demo
function love.load()
    love.window.setTitle("Glowing Tree Entity Demo")
    demo.init()
end

function love.update(dt)
    demo.update(dt)
end

function love.draw()
    demo.draw()
end

function love.keypressed(key)
    demo.keypressed(key)
end

function love.quit()
    demo.cleanup()
end

return demo