-- collision.lua - Centralized collision handling for the game with simplified responses
local collision = {}

-- Define collision groups for easy reference
collision.groups = {
    player = -1,
    projectile = -2,
    enemy = -777, -- negative: enemies don't collide with each other
    enemyBullet = -6, -- enemies' bullets (bullet.hostileGroupIndex); sensors that never touch each other
    coin = 69,
    map = 4,
    rocket = -3,
    -- houseTrigger = -4, -- cant check leaving the collider =(
    tesla = -5, -- tesla coil bolt endpoints (sensors); negative: they never touch each other
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
    elseif groupIndex == collision.groups.enemyBullet then
        return "enemyBullet"
    elseif groupIndex == collision.groups.tesla then
        return "tesla"
        -- elseif groupIndex == collision.groups.houseTrigger then
        --     return "houseTrigger"
    end

    local userData = fixture:getUserData()
    if userData then
        if userData.type then
            return userData.type
        elseif userData.topSpeed then                        -- Specific check for rockets
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

-- Rocket blast at (x, y): damages and knocks back every live enemy the blast
-- reaches (var.rocket_splash_radius, measured to the enemy's edge). Damage
-- falls off with distance squared but never below 5, so anything caught in
-- the blast is hit hard.
local function rocketSplash(userData, x, y)
    local splashRadius = var.rocket_splash_radius
    local hits = 0
    for _, e in ipairs(enemy.enemies) do
        if not e.dead and e.body and not e.body:isDestroyed() then
            local ex, ey = e.body:getPosition()
            local distance = ((ex - x) ^ 2 + (ey - y) ^ 2) ^ 0.5
            local reach = math.max(0, distance - e.fixture:getShape():getRadius())
            if reach <= splashRadius then
                local falloff = 1 - reach / splashRadius
                local actualDamage = math.max(5, math.floor(45 * falloff * falloff))
                local direction = { x = (ex - x) / (distance + 0.1), y = (ey - y) / (distance + 0.1) }
                -- Knockback before damage: a kill destroys the body
                local force = 150 * math.max(0.2, falloff)
                if reach <= userData.radius then
                    force = force * 1.5
                end
                e.body:applyLinearImpulse(direction.x * force, direction.y * force)
                -- (scorched on the side toward the blast)
                local r = e.fixture:getShape():getRadius()
                enemy.damageEnemy(e.fixture:getUserData(), actualDamage,
                    ex - direction.x * r, ey - direction.y * r, "scorch")
                hits = hits + 1
            end
        end
    end
    -- and what stands nearby (game/destruction.lua), and any boss it reaches
    destruction.blast(x, y, splashRadius, destruction.BLAST)
    bosses.blast(x, y, splashRadius, 45)
    if hits > 1 and enemy.damage_indicators then
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

-- Where a contact touches, or for a sensor's (it has no points) where its body is
local function contactPoint(contact, body)
    local x, y = contact:getPositions()
    if x then return x, y end
    return body:getPosition()
end

-- A shot hit a wall: if it's a structure's (a region's building, the arch)
-- it takes the hit (game/destruction.lua). A bullet, an enemy's (hostile),
-- or a fireball.
local function shotStructure(wall, shot, contact, hostile)
    local inst = shot:getUserData()
    local body = shot:getBody()
    local x, y = contactPoint(contact, body)
    local dx, dy
    if type(inst) == "table" and inst.dir then
        dx, dy = inst.dir.x, inst.dir.y
    else
        dx, dy = body:getLinearVelocity()
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0 then dx, dy = dx / len, dy / len else dx, dy = 0, -1 end
    end
    if type(inst) == "table" and inst[1] == "fireball" then
        destruction.hitFixture(wall, x, y, dx, dy, destruction.FIRE, "fire")
    elseif hostile then
        destruction.hitFixture(wall, x, y, dx, dy, destruction.HOSTILE)
    else
        local damage = type(inst) == "table" and inst.damage or 1
        destruction.hitFixture(wall, x, y, dx, dy, damage * destruction.BULLET)
    end
end

-- Initialize default collision responses with simplified logic
function collision.init()
    -- Player vs Enemy: Damage player and destroy enemy
    collision.registerResponse("player", "enemy", function(fixtureA, fixtureB, contact)
        if player and not player.isSafe() then
            if not player.god then player.health = player.health - 1 end
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
                    -- Get coin data to calculate score based on size
                    local coinUserData = fixtureB:getUserData()
                    local coinValue = 1
                    if coinUserData and coinUserData.value then
                        coinValue = coinUserData.value
                    end
                    var.player_score = var.player_score + coinValue
                    var.num_coins = var.num_coins - 1
                    local coinX, coinY = coinBody:getPosition()
                    table.remove(coin_bods, i)
                    coinBody:destroy()
                    if fire and fire.addFireball then
                        fire.addFireball()
                    end
                    audio.playSoundAt("coin", coinX, coinY, 0.1)
                    break
                end
            end
        end
    end)

    -- Coin vs Coin: Agar-like absorption mechanic
    collision.registerResponse("coin", "coin", function(fixtureA, fixtureB, contact)
        local bodyA = fixtureA:getBody()
        local bodyB = fixtureB:getBody()
        local userDataA = fixtureA:getUserData() or {}
        local userDataB = fixtureB:getUserData() or {}

        -- Initialize coin data if not present
        if not userDataA.value then userDataA.value = 1 end
        if not userDataB.value then userDataB.value = 1 end
        if not userDataA.size then userDataA.size = 0.5 end
        if not userDataB.size then userDataB.size = 0.5 end

        -- Determine which coin absorbs which (larger absorbs smaller, or first one if equal)
        local absorber, absorbed
        local absorberFixture, absorbedFixture
        local absorberData, absorbedData

        if userDataA.size > userDataB.size then
            absorber = bodyA
            absorbed = bodyB
            absorberFixture = fixtureA
            absorbedFixture = fixtureB
            absorberData = userDataA
            absorbedData = userDataB
        elseif userDataB.size > userDataA.size then
            absorber = bodyB
            absorbed = bodyA
            absorberFixture = fixtureB
            absorbedFixture = fixtureA
            absorberData = userDataB
            absorbedData = userDataA
        else
            -- Equal size - first coin (A) absorbs second coin (B)
            absorber = bodyA
            absorbed = bodyB
            absorberFixture = fixtureA
            absorbedFixture = fixtureB
            absorberData = userDataA
            absorbedData = userDataB
        end

        -- Calculate new properties for absorbing coin
        local growthFactor = 0.1 -- How much the coin grows per absorption
        local newSize = absorberData.size + (absorbedData.size * growthFactor)
        local newValue = absorberData.value + absorbedData.value

        -- Update absorber coin properties
        absorberData.size = newSize
        absorberData.value = newValue
        absorberFixture:setUserData(absorberData)

        -- Scale the absorber coin's visual size (if you have a scaling system)
        -- local scaleFactor = 1.0002
        -- if absorberData.originalRadius then
        --     -- If you track original radius, scale the fixture
        --     local newRadius = absorberData.originalRadius * scaleFactor
        --     -- Note: You'd need to recreate the fixture with new radius in your coin system
        --     -- This is a placeholder for that functionality
        -- end

        -- Add visual/audio feedback
        -- if audio then
        --     local pitch = math.min(1 + (newSize * 0.1), 2) -- Higher pitch for bigger coins
        --     audio.playSound("coin", 0.05, pitch)
        -- end

        local ax, ay = absorber:getPosition()
        local bx, by = absorbed:getPosition()

        -- Remove absorbed coin
        for i = 1, #coin_bods do
            if coin_bods[i] == absorbed then
                table.remove(coin_bods, i)
                absorbed:destroy()
                var.num_coins = var.num_coins - 1
                break
            end

            -- if coin_bods[i] == absorber then

            -- local new_size = coin_bods[i]:getUserData().size + 0.1
            -- coin_bods[i]:setUserData(new_size).size

            -- end
        end

        -- Apply slight attraction force to absorber towards absorbed coin position
        local direction = { x = (bx - ax) * 0.1, y = (by - ay) * 0.1 }
        absorber:applyLinearImpulse(direction.x, direction.y)
    end)

    -- Projectile vs Enemy: Damage enemy and destroy projectile (specific to bullets)
    collision.registerResponse("projectile", "enemy", function(fixtureA, fixtureB, contact)
        local groupA = fixtureA:getGroupIndex()
        local groupB = fixtureB:getGroupIndex()

        local projectileFixture, enemyFixture

        if groupA == collision.groups.projectile and groupB == collision.groups.enemy then
            projectileFixture, enemyFixture = fixtureA, fixtureB
        elseif groupA == collision.groups.enemy and groupB == collision.groups.projectile then
            projectileFixture, enemyFixture = fixtureB, fixtureA
        else
            -- Not the expected collision groups
            -- return
        end

        -- Pull userdata
        local bulletData = projectileFixture:getUserData()
        local enemyIndex = enemyFixture:getUserData()
        -- print(enemyIndex)
        if not bulletData or not enemyIndex then
            return -- safety
        end

        -- Apply effects
        local enemyBody = enemyFixture:getBody()

        -- A bullet does its weapon's damage (game/gun.lua) and leaves a hole
        -- where it struck; a fireball its own, and a scorch
        local x, y = contactPoint(contact, projectileFixture:getBody())
        if bulletData[1] ~= "fireball" then
            enemy.damageEnemy(enemyIndex, bulletData.damage or 1, x, y, "hole")
        else
            enemy.damageEnemy(enemyIndex, bulletData[2] or 10, x, y, "scorch")
        end
        -- Knockback (optional)
        if bulletData.dir then
            local bullet_force = 40
            enemyBody:applyLinearImpulse(
                bulletData.dir.x * bullet_force,
                bulletData.dir.y * bullet_force
            )
        end

        -- Bullet pooling return
        if bullet and bullet.toReturn and bulletData.speed and not bulletData.topSpeed then
            table.insert(bullet.toReturn, bulletData)
        end
    end)


    -- Projectile vs Boss (game/bosses.lua): a bullet does its weapon's
    -- damage and is spent, a fireball its own
    collision.registerResponse("projectile", "boss", function(fixtureA, fixtureB, contact)
        local data = fixtureA:getUserData()
        local part = fixtureB:getUserData()
        if type(data) ~= "table" or data.spent then return end
        local x, y = contactPoint(contact, fixtureA:getBody())
        if data[1] == "fireball" then
            bosses.hit(part, data[2] or 10, x, y, "scorch")
        else
            bosses.hit(part, data.damage or 1, x, y, "hole")
            if bullet and bullet.toReturn and data.speed and not data.topSpeed then
                data.spent = true
                table.insert(bullet.toReturn, data)
            end
        end
    end)

    -- Rocket vs Boss: it goes off there (the splash hurts the boss)
    collision.registerResponse("rocket", "boss", function(fixtureA, fixtureB, contact)
        local userData = fixtureA:getUserData()
        if userData and not userData.destroyed then
            userData.destroyed = true
            local x, y = fixtureA:getBody():getPosition()
            audio.playSoundAt("explosion", x, y, 0.1, 0.5)
            explosion.create(x, y, explosion.TYPES.ROCKET)
            rocketSplash(userData, x, y)
        end
    end)

    -- Rocket vs Enemy: Area damage with explosion and destroy rocket
    collision.registerResponse("rocket", "enemy", function(fixtureA, fixtureB, contact)
        local userData = fixtureA:getUserData()

        if userData and not userData.destroyed then
            userData.destroyed = true
            local rocketBody = fixtureA:getBody()
            local x, y = rocketBody:getPosition()

            audio.playSoundAt("explosion", x, y, 0.1, 0.5)
            explosion.create(x, y, explosion.TYPES.ROCKET)
            rocketSplash(userData, x, y)
        end
    end)

    -- Projectile vs Player: Damage player and destroy projectile (specific to bullets)
    -- collision.registerResponse("projectile", "player", function(fixtureA, fixtureB, contact)
    --     print("enemy bullet hit player")
    --     local userData = fixtureA:getUserData()
    --     if userData then
    --         local playerBody = fixtureB:getBody()
    --         local hit_client = false
    --         for k, body in pairs(player.online.bodies) do
    --             if body == playerBody then
    --                 player.online.health[k] = player.online.health[k] - 1
    --                 hit_client = true
    --                 local px, py = body:getPosition()
    --             end
    --         end
    --         if not hit_client then
    --             player.health = player.health - 1
    --             local px, py = playerBody:getPosition()
    --         end
    --         if bullet and bullet.toReturn and userData.speed and not userData.topSpeed then
    --             table.insert(bullet.toReturn, userData)
    --         end
    --     end
    -- end)

    -- Rocket vs Player: Area damage with explosion and destroy rocket
    -- collision.registerResponse("rocket", "player", function(fixtureA, fixtureB, contact)
    --     local userData = fixtureA:getUserData()
    --     if userData and not userData.destroyed then
    --         userData.destroyed = true
    --         local rocketBody = fixtureA:getBody()
    --         local playerBody = fixtureB:getBody()
    --         local x, y = rocketBody:getPosition()
    --         local px, py = playerBody:getPosition()
    --         local distance = ((px - x)^2 + (py - y)^2)^0.5
    --         local damageRadius = userData.radius * 5
    --         if distance <= damageRadius then
    --             local damageFactor = 1 - (distance / damageRadius)
    --             damageFactor = damageFactor * damageFactor
    --             local baseDamage = 45
    --             local actualDamage = math.floor(baseDamage * damageFactor)
    --             if actualDamage < 5 and distance <= damageRadius * 0.8 then
    --                 actualDamage = 5
    --             end
    --             local hit_client = false
    --             for k, body in pairs(player.online.bodies) do
    --                 if body == playerBody then
    --                     player.online.health[k] = player.online.health[k] - actualDamage
    --                     hit_client = true
    --                 end
    --             end
    --             if not hit_client then
    --                 player.health = player.health - actualDamage
    --             end
    --         end
    --         if rocket and rocket.toDestroy then
    --             table.insert(rocket.toDestroy, userData)
    --         end
    --     end
    -- end)

    -- Map vs Player: Apply impulse only
    collision.registerResponse("map", "player", function(fixtureA, fixtureB, contact)
        local playerBody = fixtureB:getBody()
        local nx, ny = contact:getNormal()
        local hit = { x = nx * 200, y = ny * 200 }
        playerBody:applyLinearImpulse(hit.x, hit.y)
    end)

    -- -- House Trigger vs Player: Toggle indoors state without collision
    -- collision.registerResponse("houseTrigger", "player", function(fixtureA, fixtureB, contact)
    --     var.indoors = not var.indoors
    -- end)

    -- collision.registerResponse("map", "projectile", function(fixtureA, fixtureB, contact)
    --     local otherBody = fixtureB:getBody()
    --     local nx, ny = contact:getNormal()
    --     local hit = { x = nx * 200, y = ny * 200 }
    --     -- otherBody:applyLinearImpulse(hit.x*10000, hit.y)
    --     -- local userData = fixtureB:getUserData()
    --     -- if userData and bullet and bullet.toReturn and userData.speed and not userData.topSpeed then
    --     --     table.insert(bullet.toReturn, userData)
    --     -- end
    -- end)

    -- Enemy bullet vs Player: hurt the player once, then the bullet is spent
    -- (back to the pool after the physics step)
    collision.registerResponse("enemyBullet", "player", function(fixtureA, fixtureB, contact)
        local inst = fixtureA:getUserData()
        if not inst or inst.spent then return end
        inst.spent = true
        table.insert(bullet.toReturn, inst)
        if fixtureB:getBody() == player.body then
            player.hurt(inst.damage, inst.dir)
            enemyWeapons.burst(inst, inst.body:getPosition()) -- (a rocket's, a fireball's)
        end
    end)

    -- Enemy bullet vs Map: walls and houses stop it (and the arch)
    local function enemyBulletStopped(fixtureA, fixtureB, contact)
        local inst = fixtureA:getUserData()
        if not inst or inst.spent then return end
        inst.spent = true
        table.insert(bullet.toReturn, inst)
        shotStructure(fixtureB, fixtureA, contact, true)
        enemyWeapons.burst(inst, inst.body:getPosition())
    end
    collision.registerResponse("enemyBullet", "map", enemyBulletStopped)
    collision.registerResponse("enemyBullet", "arch", enemyBulletStopped)

    -- Map vs Projectile: Apply impulse and destroy projectile (specific to bullets)
    local function projectileStopped(fixtureA, fixtureB, contact)
        local otherBody = fixtureB:getBody()
        local nx, ny = contact:getNormal()
        local hit = { x = nx * 200, y = ny * 200 }
        otherBody:applyLinearImpulse(hit.x, hit.y)
        local userData = fixtureB:getUserData()
        if userData and userData.spent then return end -- (touching two walls at once: one hit)
        if userData and bullet and bullet.toReturn and userData.speed and not userData.topSpeed then
            userData.spent = true
            table.insert(bullet.toReturn, userData)
        end
        shotStructure(fixtureA, fixtureB, contact, false)
    end
    collision.registerResponse("map", "projectile", projectileStopped)
    collision.registerResponse("arch", "projectile", projectileStopped)

    -- Map vs Rocket: Apply impulse, trigger explosion, and destroy rocket
    local function rocketStopped(fixtureA, fixtureB, contact)
        local otherBody = fixtureB:getBody()
        local nx, ny = contact:getNormal()
        local x, y = contact:getPositions()
        local hit = { x = nx * 200, y = ny * 200 }
        otherBody:applyLinearImpulse(hit.x, hit.y)
        local userData = fixtureB:getUserData()
        if userData and not userData.destroyed then
            audio.playSoundAt("explosion", x, y, 0.1, 0.5)
            explosion.create(x, y, explosion.TYPES.ROCKET)

            userData.destroyed = true
            local x, y = otherBody:getPosition()
            rocketSplash(userData, x, y)
            -- Check for player damage
            -- if player and player.body then
            --     local px, py = player.body:getPosition()
            --     local distance = ((px - x)^2 + (py - y)^2)^0.5
            --     local damageRadius = userData.radius * 5
            --     if distance <= damageRadius then
            --         local damageFactor = 1 - (distance / damageRadius)
            --         damageFactor = damageFactor * damageFactor
            --         local baseDamage = 45
            --         local actualDamage = math.floor(baseDamage * damageFactor)
            --         if actualDamage < 5 and distance <= damageRadius * 0.8 then
            --             actualDamage = 5
            --         end
            --         local hit_client = false
            --         for k, body in pairs(player.online.bodies) do
            --             if body == player.body then
            --                 player.online.health[k] = player.online.health[k] - actualDamage
            --                 hit_client = true
            --             end
            --         end
            --         if not hit_client then
            --             player.health = player.health - actualDamage
            --         end
            --     end
            -- end
        end
    end
    collision.registerResponse("map", "rocket", rocketStopped)
    collision.registerResponse("arch", "rocket", rocketStopped)

    -- Map vs Enemy: Apply impulse
    collision.registerResponse("map", "enemy", function(fixtureA, fixtureB, contact)
        local enemyBody = fixtureB:getBody()
        local nx, ny = contact:getNormal()
        local hit = { x = nx * 200, y = ny * 200 }
        enemyBody:applyLinearImpulse(hit.x, hit.y)
    end)
end

return collision
