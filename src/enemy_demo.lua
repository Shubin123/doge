-- Enemy System Demo and Usage Examples
-- This file demonstrates the enhanced enemy system features

local enemy_demo = {}

-- Example: Spawn different enemy types
function enemy_demo.spawnTestEnemies()
    -- Spawn a grunt enemy
    local grunt_id = enemy.addEnemy(400, 300, "grunt")
    
    -- Spawn a warrior enemy
    local warrior_id = enemy.addEnemy(500, 300, "warrior")
    
    -- Spawn an elite enemy
    local elite_id = enemy.addEnemy(600, 300, "elite")
    
    print("Spawned enemies:")
    print("Grunt ID:", grunt_id)
    print("Warrior ID:", warrior_id)
    print("Elite ID:", elite_id)
end

-- Example: Create an enemy wave encounter
function enemy_demo.spawnWave1()
    local wave_data = {
        {x = 300, y = 200, type = "grunt"},
        {x = 320, y = 220, type = "grunt"},
        {x = 340, y = 200, type = "grunt"},
        {x = 360, y = 180, type = "warrior"},
        {x = 400, y = 200, type = "elite"}
    }
    
    enemy.spawnWave(wave_data)
    print("Spawned Wave 1: Mixed enemy types")
end

-- Example: Create an elite boss encounter
function enemy_demo.spawnBossWave()
    local wave_data = {
        {x = 400, y = 300, type = "elite"},  -- Boss in center
        {x = 350, y = 280, type = "warrior"}, -- Guards
        {x = 450, y = 280, type = "warrior"},
        {x = 320, y = 320, type = "grunt"},   -- Minions
        {x = 380, y = 340, type = "grunt"},
        {x = 420, y = 340, type = "grunt"},
        {x = 480, y = 320, type = "grunt"}
    }
    
    enemy.spawnWave(wave_data)
    print("Spawned Boss Wave: Elite with guards and minions")
end

-- Example: Demonstrate enemy abilities
function enemy_demo.testEnemyAbilities()
    if #enemies_bods > 0 then
        local enemy_id = 1
        
        -- Test stunning an enemy
        enemy.stunEnemy(enemy_id, 2.0) -- Stun for 2 seconds
        print("Stunned enemy", enemy_id, "for 2 seconds")
        
        -- Test healing an enemy (after a delay)
        love.timer.sleep(1)
        enemy.healEnemy(enemy_id, 2)
        print("Healed enemy", enemy_id, "for 2 health")
        
        -- Test damage
        love.timer.sleep(1)
        local killed = enemy.damageEnemy(enemy_id, 3, player.body:getPosition())
        if killed then
            print("Enemy", enemy_id, "was killed!")
        else
            print("Enemy", enemy_id, "took 3 damage")
        end
    end
end

-- Example: Get enemy statistics
function enemy_demo.printEnemyStats()
    print("=== Enemy Statistics ===")
    print("Total enemies:", #enemies_bods)
    print("Grunts:", enemy.getEnemyCountByType("grunt"))
    print("Warriors:", enemy.getEnemyCountByType("warrior"))
    print("Elites:", enemy.getEnemyCountByType("elite"))
    
    -- Print individual enemy states
    for i, instance in pairs(enemy.instances) do
        if instance then
            print(string.format("Enemy %d: %s - Health: %d/%d - State: %s", 
                i, instance.type, instance.health, instance.max_health, instance.state))
        end
    end
end

-- Example: Enhanced visual effects demo with dynamic particles
function enemy_demo.testVisualEffects()
    if player and player.body then
        local px, py = player.body:getPosition()
        
        -- Test different hit effects
        effects.newEnhancedHitMarker(px + 50, py, 5, false) -- Normal hit
        effects.newEnhancedHitMarker(px - 50, py, 8, true)  -- Critical hit
        
        -- Test dynamic particle effects
        if particle_system then
            -- Explosion effects
            particle_system.explosion(px, py + 50, 1.0, "fire")
            particle_system.explosion(px + 80, py + 50, 1.5, "ice")
            particle_system.explosion(px - 80, py + 50, 2.0, "poison")
            
            -- Elemental effects
            particle_system.createEffect(particle_system.EFFECT_TYPES.ELECTRIC, px, py + 100, {
                particle_count = 30
            })
            particle_system.createEffect(particle_system.EFFECT_TYPES.MAGIC, px + 50, py + 100, {
                particle_count = 25
            })
            particle_system.createEffect(particle_system.EFFECT_TYPES.ENERGY, px - 50, py + 100, {
                particle_count = 35
            })
            
            -- Environmental effects
            particle_system.createEffect(particle_system.EFFECT_TYPES.SMOKE, px, py - 50, {
                particle_count = 20
            })
            particle_system.createEffect(particle_system.EFFECT_TYPES.SPARKS, px + 30, py - 50, {
                particle_count = 25
            })
        end
        
        -- Test screen shake
        effects.addScreenShake(15, 0.5)
        
        print("Triggered dynamic particle effects demo")
    end
end

-- Example: Dynamic particle aura demo
function enemy_demo.testShaderEffects()
    if player and player.body and particle_system then
        local px, py = player.body:getPosition()
        
        -- Create different types of auras around the player
        particle_system.aura(px - 100, py, "fire", 2.0)     -- Fire aura
        particle_system.aura(px + 100, py, "electric", 1.5) -- Electric aura
        particle_system.aura(px, py - 100, "energy", 1.8)   -- Energy aura
        
        -- Enhance existing enemy auras
        for i, instance in pairs(enemy.instances) do
            if instance then
                instance.aura_intensity = 2.0 -- Boost aura visibility
                
                -- Remove old aura and create new enhanced one
                if enemy.aura_effects[i] then
                    enemy.aura_effects[i] = nil
                end
                
                local theme = enemy.effect_themes[instance.type] or enemy.effect_themes.grunt
                local ex, ey = enemies_bods[i]:getPosition()
                enemy.aura_effects[i] = particle_system.aura(ex, ey, theme.aura, 2.0)
            end
        end
        
        print("Created dynamic particle auras")
    end
end

-- Keybindings for testing (call these from main update or keypressed)
function enemy_demo.handleInput(key)
    if key == "1" then
        enemy_demo.spawnTestEnemies()
    elseif key == "2" then
        enemy_demo.spawnWave1()
    elseif key == "3" then
        enemy_demo.spawnBossWave()
    elseif key == "4" then
        enemy_demo.testEnemyAbilities()
    elseif key == "5" then
        enemy_demo.printEnemyStats()
    elseif key == "6" then
        enemy_demo.testVisualEffects()
    elseif key == "7" then
        enemy_demo.testShaderEffects()
    elseif key == "8" then
        -- Clear all enemies
        for i = #enemies_bods, 1, -1 do
            enemy.removeEnemy(i)
        end
        enemy.reset()
        print("Cleared all enemies")
    end
end

-- Print controls
function enemy_demo.printControls()
    print("=== Enemy System Demo Controls ===")
    print("1 - Spawn test enemies (one of each type)")
    print("2 - Spawn Wave 1 (mixed encounter)")
    print("3 - Spawn Boss Wave (elite with guards)")
    print("4 - Test enemy abilities (stun, heal, damage)")
    print("5 - Print enemy statistics")
    print("6 - Test visual effects")
    print("7 - Test shader effects")
    print("8 - Clear all enemies")
    print("====================================")
end

-- Auto-demo function for showcasing
function enemy_demo.runAutoDemo(dt)
    local demo_time = love.timer.getTime()
    local phase = math.floor(demo_time / 10) % 4 -- 10 second phases
    
    if phase == 0 and math.floor(demo_time) % 10 == 0 then
        enemy_demo.spawnWave1()
    elseif phase == 1 and math.floor(demo_time) % 10 == 0 then
        enemy_demo.testVisualEffects()
    elseif phase == 2 and math.floor(demo_time) % 10 == 0 then
        enemy_demo.spawnBossWave()
    elseif phase == 3 and math.floor(demo_time) % 10 == 0 then
        enemy_demo.testShaderEffects()
    end
end

return enemy_demo