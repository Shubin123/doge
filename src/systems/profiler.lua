-- Add this profiling code at the end of your enemy module (before return enemy)

-- Performance profiler setup
local profiler = {
    times = {},
    calls = {},
    start_times = {}
}

function profiler.start(name)
    profiler.start_times[name] = love.timer.getTime()
    profiler.calls[name] = (profiler.calls[name] or 0) + 1
end

function profiler.stop(name)
    if profiler.start_times[name] then
        local elapsed = love.timer.getTime() - profiler.start_times[name]
        profiler.times[name] = (profiler.times[name] or 0) + elapsed
        profiler.start_times[name] = nil
    end
end

function profiler.report()
    print("\n=== ENEMY MODULE PERFORMANCE REPORT ===")
    local sorted_functions = {}
    for name, total_time in pairs(profiler.times) do
        table.insert(sorted_functions, {
            name = name,
            total_time = total_time,
            calls = profiler.calls[name] or 0,
            avg_time = total_time / (profiler.calls[name] or 1)
        })
    end
    
    table.sort(sorted_functions, function(a, b) return a.total_time > b.total_time end)
    
    print(string.format("%-40s %10s %8s %12s", "Function", "Total(ms)", "Calls", "Avg(ms)"))
    print(string.rep("-", 75))
    
    for _, func in ipairs(sorted_functions) do
        print(string.format("%-40s %10.3f %8d %12.6f", 
            func.name, 
            func.total_time * 1000, 
            func.calls, 
            func.avg_time * 1000
        ))
    end
    print("=========================================\n")
end

-- Store original function pointers
local original_functions = {
    -- Enemy class methods
    Enemy_new = Enemy.new,
    Enemy_initBehaviourTree = Enemy.initBehaviourTree,
    Enemy_fireAtPlayer = Enemy.fireAtPlayer,
    Enemy_updateProjectiles = Enemy.updateProjectiles,
    Enemy_getDirectionToPlayer = Enemy.getDirectionToPlayer,
    Enemy_damageEnemy = Enemy.damageEnemy,
    Enemy_killEnemy = Enemy.killEnemy,
    Enemy_update = Enemy.update,
    
    -- Global enemy manager functions
    enemy_load = enemy.load,
    enemy_update = enemy.update,
    enemy_damageEnemy = enemy.damageEnemy,
    enemy_killEnemy = enemy.killEnemy,
    enemy_addEnemy = enemy.addEnemy,
    enemy_removeEnemy = enemy.removeEnemy,
    enemy_fireAtPlayer = enemy.fireAtPlayer,
    enemy_updateProjectiles = enemy.updateProjectiles,
    enemy_populate = enemy.populate
}

-- Override Enemy class methods with profiling
-- Enemy.new = function(...)
--     profiler.start('Enemy.new')
--     local result = original_functions.Enemy_new(...)
--     profiler.stop('Enemy.new')
--     return result
-- end

-- Enemy.initBehaviourTree = function(self)
--     profiler.start('Enemy:initBehaviourTree')
--     local result = original_functions.Enemy_initBehaviourTree(self)
--     profiler.stop('Enemy:initBehaviourTree')
--     return result
-- end

-- Enemy.fireAtPlayer = function(self)
--     profiler.start('Enemy:fireAtPlayer')
--     local result = original_functions.Enemy_fireAtPlayer(self)
--     profiler.stop('Enemy:fireAtPlayer')
--     return result
-- end

-- Enemy.updateProjectiles = function(self, dt)
--     profiler.start('Enemy:updateProjectiles')
--     local result = original_functions.Enemy_updateProjectiles(self, dt)
--     profiler.stop('Enemy:updateProjectiles')
--     return result
-- end

-- Enemy.getDirectionToPlayer = function(self, n)
--     profiler.start('Enemy:getDirectionToPlayer')
--     local result = original_functions.Enemy_getDirectionToPlayer(self, n)
--     profiler.stop('Enemy:getDirectionToPlayer')
--     return result
-- end

-- Enemy.damageEnemy = function(self, damage)
--     profiler.start('Enemy:damageEnemy')
--     local result = original_functions.Enemy_damageEnemy(self, damage)
--     profiler.stop('Enemy:damageEnemy')
--     return result
-- end

-- Enemy.killEnemy = function(self)
--     profiler.start('Enemy:killEnemy')
--     local result = original_functions.Enemy_killEnemy(self)
--     profiler.stop('Enemy:killEnemy')
--     return result
-- end

function Enemy:update(dt)
    profiler.start('Enemy:update')
    local result = original_functions.Enemy_update(self, dt)
    profiler.stop('Enemy:update')
    return result
end

-- Override global enemy manager functions with profiling
enemy.load = function()
    profiler.start('enemy.load')
    local result = original_functions.enemy_load()
    profiler.stop('enemy.load')
    return result
end

enemy.update = function(dt)
    profiler.start('enemy.update')
    local result = original_functions.enemy_update(dt)
    profiler.stop('enemy.update')
    return result
end

enemy.damageEnemy = function(enemy_index, damage)
    profiler.start('enemy.damageEnemy')
    local result = original_functions.enemy_damageEnemy(enemy_index, damage)
    profiler.stop('enemy.damageEnemy')
    return result
end

enemy.killEnemy = function(enemy_index)
    profiler.start('enemy.killEnemy')
    local result = original_functions.enemy_killEnemy(enemy_index)
    profiler.stop('enemy.killEnemy')
    return result
end

enemy.addEnemy = function(x, y)
    profiler.start('enemy.addEnemy')
    local result1, result2 = original_functions.enemy_addEnemy(x, y)
    profiler.stop('enemy.addEnemy')
    return result1, result2
end

enemy.removeEnemy = function(enemy_index)
    profiler.start('enemy.removeEnemy')
    local result = original_functions.enemy_removeEnemy(enemy_index)
    profiler.stop('enemy.removeEnemy')
    return result
end

enemy.fireAtPlayer = function(enemy_index, enemy_x, enemy_y, player_x, player_y)
    profiler.start('enemy.fireAtPlayer')
    local result = original_functions.enemy_fireAtPlayer(enemy_index, enemy_x, enemy_y, player_x, player_y)
    profiler.stop('enemy.fireAtPlayer')
    return result
end

enemy.updateProjectiles = function(dt)
    profiler.start('enemy.updateProjectiles')
    local result = original_functions.enemy_updateProjectiles(dt)
    profiler.stop('enemy.updateProjectiles')
    return result
end

enemy.populate = function()
    profiler.start('enemy.populate')
    local result = original_functions.enemy_populate()
    profiler.stop('enemy.populate')
    return result
end

-- Add profiler to enemy module for external access
enemy.profiler = profiler

-- Call profiler.report() in your main game loop or console to see results
-- Example: enemy.profiler.report()