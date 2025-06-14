-- Test script for explosion_effects_mod
-- Can be run from the game console to test explosion functionality

local testExplosions = {}

-- Test basic explosion
function testExplosions.testBasic()
    local playerX, playerY = api.game.getPlayerPosition()
    if not playerX then
        print("No player position found")
        return
    end
    
    -- Create explosion 200 units in front of player
    local explosionAPI = api.game.getModAPI("explosion_effects")
    if explosionAPI then
        explosionAPI.createExplosion(playerX + 200, playerY, {
            radius = 150,
            damage = 100,
            owner = "player",
            team = "player"
        })
        print("Created basic explosion at", playerX + 200, playerY)
    else
        print("Explosion effects mod not loaded!")
    end
end

-- Test multiple explosions
function testExplosions.testMultiple()
    local playerX, playerY = api.game.getPlayerPosition()
    if not playerX then return end
    
    local explosionAPI = api.game.getModAPI("explosion_effects")
    if not explosionAPI then
        print("Explosion effects mod not loaded!")
        return
    end
    
    -- Create a chain of explosions
    for i = 1, 5 do
        local angle = (i / 5) * math.pi * 2
        local distance = 300
        local x = playerX + math.cos(angle) * distance
        local y = playerY + math.sin(angle) * distance
        
        -- Delay each explosion
        api.utils.delay(i * 0.2, function()
            explosionAPI.createExplosion(x, y, {
                radius = 100,
                damage = 50,
                owner = "player",
                team = "player",
                color = {1, 0.5 + i * 0.1, 0.2}
            })
        end)
    end
    
    print("Created chain explosion sequence")
end

-- Test different explosion colors and sizes
function testExplosions.testVariations()
    local playerX, playerY = api.game.getPlayerPosition()
    if not playerX then return end
    
    local explosionAPI = api.game.getModAPI("explosion_effects")
    if not explosionAPI then
        print("Explosion effects mod not loaded!")
        return
    end
    
    -- Small blue explosion
    explosionAPI.createExplosion(playerX - 200, playerY, {
        radius = 50,
        damage = 25,
        owner = "player",
        color = {0.3, 0.5, 1},
        smokeColor = {0.2, 0.3, 0.5}
    })
    
    -- Medium green explosion
    explosionAPI.createExplosion(playerX, playerY - 200, {
        radius = 100,
        damage = 50,
        owner = "player",
        color = {0.3, 1, 0.3},
        smokeColor = {0.2, 0.4, 0.2}
    })
    
    -- Large red explosion
    explosionAPI.createExplosion(playerX + 200, playerY, {
        radius = 200,
        damage = 150,
        owner = "player",
        color = {1, 0.2, 0.2},
        smokeColor = {0.4, 0.2, 0.2}
    })
    
    print("Created varied explosions")
end

-- Test rocket simulation
function testExplosions.testRocket()
    local playerX, playerY = api.game.getPlayerPosition()
    if not playerX then return end
    
    -- Fire a rocket using projectiles mod
    local projectilesAPI = api.game.getModAPI("projectiles_mod")
    if projectilesAPI and projectilesAPI.spawnProjectile then
        projectilesAPI.spawnProjectile("rocket", playerX, playerY, 1, 0, {
            owner_id = "player",
            team = "player",
            explosion_radius = 150,
            explosion_damage = 100
        })
        print("Fired test rocket")
    else
        print("Projectiles mod not available")
    end
end

-- Console commands
api.console.registerCommand("test_explosion", testExplosions.testBasic, "Test basic explosion")
api.console.registerCommand("test_explosion_chain", testExplosions.testMultiple, "Test explosion chain")
api.console.registerCommand("test_explosion_varied", testExplosions.testVariations, "Test explosion variations")
api.console.registerCommand("test_rocket", testExplosions.testRocket, "Test rocket with explosion")

return testExplosions