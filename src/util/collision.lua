-- collision.lua - Centralized collision handling for the game with simplified responses
local collision = {}

-- Define collision groups for easy reference
collision.groups = {
    player = -1,
    projectile = -2,
    enemy = -777,
    coin = 69,
    map = 4,
    rocket = -3,
    -- Add other groups as needed
}

-- Table to store collision response functions
collision.responses = {}

-- Register a collision response between two types
function collision.registerResponse(typeA, typeB, responseFunc)
    local key = typeA .. "_" .. typeB
    local reverseKey = typeB .. "_" .. typeA
    collision.responses[key] = responseFunc
    collision.responses[reverseKey] = function(fixtureB, fixtureA, contact)
        return responseFunc(fixtureA, fixtureB, contact)
    end
end

-- Get the type of an object based on fixture or user data
function collision.getType(fixture)
    local groupIndex = fixture:getGroupIndex()
    if groupIndex == collision.groups.player then
        return "player"
    elseif groupIndex == collision.groups.projectile then
        return "projectile"
    elseif groupIndex == collision.groups.enemy then
        return "enemy"
    elseif groupIndex == collision.groups.coin then
        return "coin"
    elseif groupIndex == collision.groups.map then
        return "map"
    elseif groupIndex == collision.groups.rocket then
        return "rocket"
    end
    
    local userData = fixture:getUserData()
    if userData then
        if userData.type then
            return userData.type
        elseif userData.topSpeed then -- Specific check for rockets
            return "rocket"
        elseif userData.speed and not userData.topSpeed then -- Specific check for bullets
            return "bullet"
        end
    end
    
    return "unknown"
end

-- Handle collision between two fixtures
function collision.handle(fixtureA, fixtureB, contact)
    -- Only process collisions on host if multiplayer is enabled
    if var.multiplayer and var.multiplayer ~= 1 then
        return
    end
    
    local typeA = collision.getType(fixtureA)
    local typeB = collision.getType(fixtureB)
    
    local key = typeA .. "_" .. typeB
    local responseFunc = collision.responses[key]
    
    if responseFunc then
        return responseFunc(fixtureA, fixtureB, contact)
    end
end

-- Initialize default collision responses with simplified logic
function collision.init()
    -- Player vs Enemy: Damage player and destroy enemy
    collision.registerResponse("player", "enemy", function(fixtureA, fixtureB, contact)
        if player then
            player.health = player.health - 1
            local x, y = fixtureA:getBody():getPosition()
            if blood and blood.onEnemyDamage then
                blood.onEnemyDamage(x, y, 1)
            end
            local enemyBody = fixtureB:getBody()
            for i = 1, #enemies_bods do
                if enemies_bods[i] == enemyBody then
                    table.remove(enemies_bods, i)
                    enemyBody:destroy()
                    break
                end
            end
        end
    end)
    
    -- Player vs Coin: Collect coin and update score
    collision.registerResponse("player", "coin", function(fixtureA, fixtureB, contact)
        if player then
            local coinBody = fixtureB:getBody()
            for i = 1, #coin_bods do
                if coin_bods[i] == coinBody then
                    var.player_score = var.player_score + 1
                    var.num_coins = var.num_coins - 1
                    table.remove(coin_bods, i)
                    coinBody:destroy()
                    if fire and fire.addFireball then
                        fire.addFireball()
                    end
                    break
                end
            end
        end
    end)
    
    -- Projectile vs Enemy: Damage enemy and destroy projectile (specific to bullets)
    collision.registerResponse("projectile", "enemy", function(fixtureA, fixtureB, contact)
        local userData = fixtureA:getUserData()
        if userData then
            local enemyBody = fixtureB:getBody()
            local x, y = enemyBody:getPosition()
            if blood and blood.onEnemyDamage then
                blood.onEnemyDamage(x, y, 1, {x=1, y=1})
            end
            for i = 1, #enemies_bods do
                if enemies_bods[i] and enemies_bods[i] == enemyBody then
                    if enemy and enemy.damageEnemy then
                        local damage_amount = math.random(8, 15)
                        enemy.damageEnemy(i, damage_amount)
                        local bullet_force = 40
                        local knockback_x = userData.dir and userData.dir.x * bullet_force or math.random() * bullet_force
                        local knockback_y = userData.dir and userData.dir.y * bullet_force or math.random() * bullet_force
                        enemyBody:applyLinearImpulse(knockback_x, knockback_y)
                    end
                    break
                end
            end
            if bullet and bullet.toReturn and userData.speed and not userData.topSpeed then
                table.insert(bullet.toReturn, userData)
            end
        end
    end)
    
    -- Rocket vs Enemy: Area damage with explosion and destroy rocket
    collision.registerResponse("rocket", "enemy", function(fixtureA, fixtureB, contact)
        local userData = fixtureA:getUserData()
        if userData and not userData.destroyed then
            userData.destroyed = true
            local rocketBody = fixtureA:getBody()
            local x, y = rocketBody:getPosition()
            if enemies_bods then
                local splash_enemies = {}
                for i, eb in ipairs(enemies_bods) do
                    if eb then
                        local ex, ey = eb:getPosition()
                        local distance = ((ex - x)^2 + (ey - y)^2)^0.5
                        local damageRadius = userData.radius * 5
                        if distance <= damageRadius then
                            local damageFactor = 1 - (distance / damageRadius)
                            damageFactor = damageFactor * damageFactor
                            local baseDamage = 45
                            local actualDamage = math.floor(baseDamage * damageFactor)
                            if actualDamage < 5 and distance <= damageRadius * 0.8 then
                                actualDamage = 5
                            end
                            if blood and blood.onEnemyDamage and actualDamage > 0 then
                                local direction = {x = (ex - x) / (distance + 0.1), y = (ey - y) / (distance + 0.1)}
                                blood.onEnemyDamage(ex, ey, actualDamage, direction)
                            end
                            if enemy and enemy.damageEnemy and actualDamage > 0 then
                                enemy.damageEnemy(i, actualDamage)
                                local knockback_direction = {x = (ex - x) / (distance + 0.1), y = (ey - y) / (distance + 0.1)}
                                local distance_factor = math.max(0.2, 1 - (distance / damageRadius))
                                local final_force = 150 * distance_factor
                                if distance <= userData.radius then
                                    final_force = final_force * 1.5
                                end
                                local knockback_x = knockback_direction.x * final_force
                                local knockback_y = knockback_direction.y * final_force
                                eb:applyLinearImpulse(knockback_x, knockback_y)
                                table.insert(splash_enemies, {
                                    index = i,
                                    x = ex,
                                    y = ey,
                                    distance = distance,
                                    damage = actualDamage,
                                    is_direct_hit = distance <= userData.radius,
                                    knockback_force = final_force
                                })
                            end
                        end
                    end
                end
                if #splash_enemies > 1 and enemy and enemy.damage_indicators then
                    table.insert(enemy.damage_indicators, {
                        x = x,
                        y = y - 30,
                        damage = "SPLASH!",
                        time = 0,
                        duration = 1.5,
                        velocity_y = -60,
                        velocity_x = 0,
                        alpha = 1,
                        scale = 1.5,
                        bounce_factor = 0.95,
                        nearby_count = 0,
                        is_splash_indicator = true
                    })
                end
            end
            if rocket and rocket.toDestroy then
                table.insert(rocket.toDestroy, userData)
            end
        end
    end)
    
    -- Projectile vs Player: Damage player and destroy projectile (specific to bullets)
    collision.registerResponse("projectile", "player", function(fixtureA, fixtureB, contact)
        local userData = fixtureA:getUserData()
        if userData then
            local playerBody = fixtureB:getBody()
            local hit_client = false
            for k, body in pairs(player.online.bodies) do
                if body == playerBody then
                    player.online.health[k] = player.online.health[k] - 1
                    hit_client = true
                    local px, py = body:getPosition()
                    if blood and blood.onEnemyDamage then
                        blood.onEnemyDamage(px, py, 1)
                    end
                end
            end
            if not hit_client then
                player.health = player.health - 1
                local px, py = playerBody:getPosition()
                if blood and blood.onEnemyDamage then
                    blood.onEnemyDamage(px, py, 1)
                end
            end
            if bullet and bullet.toReturn and userData.speed and not userData.topSpeed then
                table.insert(bullet.toReturn, userData)
            end
        end
    end)
    
    -- Rocket vs Player: Area damage with explosion and destroy rocket
    collision.registerResponse("rocket", "player", function(fixtureA, fixtureB, contact)
        local userData = fixtureA:getUserData()
        if userData and not userData.destroyed then
            userData.destroyed = true
            local rocketBody = fixtureA:getBody()
            local playerBody = fixtureB:getBody()
            local x, y = rocketBody:getPosition()
            local px, py = playerBody:getPosition()
            local distance = ((px - x)^2 + (py - y)^2)^0.5
            local damageRadius = userData.radius * 5
            if distance <= damageRadius then
                local damageFactor = 1 - (distance / damageRadius)
                damageFactor = damageFactor * damageFactor
                local baseDamage = 45
                local actualDamage = math.floor(baseDamage * damageFactor)
                if actualDamage < 5 and distance <= damageRadius * 0.8 then
                    actualDamage = 5
                end
                local hit_client = false
                for k, body in pairs(player.online.bodies) do
                    if body == playerBody then
                        player.online.health[k] = player.online.health[k] - actualDamage
                        hit_client = true
                        if blood and blood.onEnemyDamage then
                            blood.onEnemyDamage(px, py, actualDamage)
                        end
                    end
                end
                if not hit_client then
                    player.health = player.health - actualDamage
                    if blood and blood.onEnemyDamage then
                        blood.onEnemyDamage(px, py, actualDamage)
                    end
                end
            end
            if rocket and rocket.toDestroy then
                table.insert(rocket.toDestroy, userData)
            end
        end
    end)
    
    -- Map vs Player: Apply impulse and toggle indoors state
    collision.registerResponse("map", "player", function(fixtureA, fixtureB, contact)
        local playerBody = fixtureB:getBody()
        local nx, ny = contact:getNormal()
        local hit = {x = nx * 200, y = ny * 200}
        playerBody:applyLinearImpulse(hit.x, hit.y)
        var.indoors = not var.indoors
    end)
    
    -- Map vs Projectile: Apply impulse and destroy projectile (specific to bullets)
    collision.registerResponse("map", "projectile", function(fixtureA, fixtureB, contact)
        local otherBody = fixtureB:getBody()
        local nx, ny = contact:getNormal()
        local hit = {x = nx * 200, y = ny * 200}
        otherBody:applyLinearImpulse(hit.x, hit.y)
        local userData = fixtureB:getUserData()
        if userData and bullet and bullet.toReturn and userData.speed and not userData.topSpeed then
            table.insert(bullet.toReturn, userData)
        end
    end)
    
    -- Map vs Rocket: Apply impulse, trigger explosion, and destroy rocket
    collision.registerResponse("map", "rocket", function(fixtureA, fixtureB, contact)
        local otherBody = fixtureB:getBody()
        local nx, ny = contact:getNormal()
        local hit = {x = nx * 200, y = ny * 200}
        otherBody:applyLinearImpulse(hit.x, hit.y)
        local userData = fixtureB:getUserData()
        if userData and not userData.destroyed then
            userData.destroyed = true
            local x, y = otherBody:getPosition()
            if enemies_bods then
                local splash_enemies = {}
                for i, eb in ipairs(enemies_bods) do
                    if eb then
                        local ex, ey = eb:getPosition()
                        local distance = ((ex - x)^2 + (ey - y)^2)^0.5
                        local damageRadius = userData.radius * 5
                        if distance <= damageRadius then
                            local damageFactor = 1 - (distance / damageRadius)
                            damageFactor = damageFactor * damageFactor
                            local baseDamage = 45
                            local actualDamage = math.floor(baseDamage * damageFactor)
                            if actualDamage < 5 and distance <= damageRadius * 0.8 then
                                actualDamage = 5
                            end
                            if blood and blood.onEnemyDamage and actualDamage > 0 then
                                local direction = {x = (ex - x) / (distance + 0.1), y = (ey - y) / (distance + 0.1)}
                                blood.onEnemyDamage(ex, ey, actualDamage, direction)
                            end
                            if enemy and enemy.damageEnemy and actualDamage > 0 then
                                enemy.damageEnemy(i, actualDamage)
                                local knockback_direction = {x = (ex - x) / (distance + 0.1), y = (ey - y) / (distance + 0.1)}
                                local distance_factor = math.max(0.2, 1 - (distance / damageRadius))
                                local final_force = 150 * distance_factor
                                if distance <= userData.radius then
                                    final_force = final_force * 1.5
                                end
                                local knockback_x = knockback_direction.x * final_force
                                local knockback_y = knockback_direction.y * final_force
                                eb:applyLinearImpulse(knockback_x, knockback_y)
                                table.insert(splash_enemies, {
                                    index = i,
                                    x = ex,
                                    y = ey,
                                    distance = distance,
                                    damage = actualDamage,
                                    is_direct_hit = distance <= userData.radius,
                                    knockback_force = final_force
                                })
                            end
                        end
                    end
                end
                if #splash_enemies > 1 and enemy and enemy.damage_indicators then
                    table.insert(enemy.damage_indicators, {
                        x = x,
                        y = y - 30,
                        damage = "SPLASH!",
                        time = 0,
                        duration = 1.5,
                        velocity_y = -60,
                        velocity_x = 0,
                        alpha = 1,
                        scale = 1.5,
                        bounce_factor = 0.95,
                        nearby_count = 0,
                        is_splash_indicator = true
                    })
                end
            end
            -- Check for player damage
            if player and player.body then
                local px, py = player.body:getPosition()
                local distance = ((px - x)^2 + (py - y)^2)^0.5
                local damageRadius = userData.radius * 5
                if distance <= damageRadius then
                    local damageFactor = 1 - (distance / damageRadius)
                    damageFactor = damageFactor * damageFactor
                    local baseDamage = 45
                    local actualDamage = math.floor(baseDamage * damageFactor)
                    if actualDamage < 5 and distance <= damageRadius * 0.8 then
                        actualDamage = 5
                    end
                    local hit_client = false
                    for k, body in pairs(player.online.bodies) do
                        if body == player.body then
                            player.online.health[k] = player.online.health[k] - actualDamage
                            hit_client = true
                            if blood and blood.onEnemyDamage then
                                blood.onEnemyDamage(px, py, actualDamage)
                            end
                        end
                    end
                    if not hit_client then
                        player.health = player.health - actualDamage
                        if blood and blood.onEnemyDamage then
                            blood.onEnemyDamage(px, py, actualDamage)
                        end
                    end
                end
            end
            if rocket and rocket.toDestroy then
                table.insert(rocket.toDestroy, userData)
            end
        end
    end)
    
    -- Map vs Enemy: Apply impulse
    collision.registerResponse("map", "enemy", function(fixtureA, fixtureB, contact)
        local enemyBody = fixtureB:getBody()
        local nx, ny = contact:getNormal()
        local hit = {x = nx * 200, y = ny * 200}
        enemyBody:applyLinearImpulse(hit.x, hit.y)
    end)
end

return collision
