Enemy = {}
Enemy.__index = Enemy

function Enemy.new(world, x, y, max_health, scale, fire_cooldown, detection_range, projectile_speed, index)
    local self = setmetatable({}, Enemy)
    self.body = love.physics.newBody(world, x, y, "dynamic")
    -- love.physics.newFixture(self.body, love.physics.newCircleShape(20)):setDensity(2.0):setGroupIndex(777)

    self.fixture = love.physics.newFixture(self.body, love.physics.newCircleShape(20))
    self.fixture:setGroupIndex(777)
    self.fixture:setDensity(2.0)
    self.fixture:setUserData(index)
    -- self.body:resetMassData()
    -- self.body:setLinearDamping(3.0)
    -- self.body:setAngularDamping(5.0)

    self.health = 1
    self.max_health = self.health
    self.scale = scale or 0.6
    self.fire_cooldown = fire_cooldown or
        2.0 --ideally get the number of frames for shooting animation dynamically to determine this
    self.detection_range = detection_range or 300
    self.projectile_speed = projectile_speed or 400
    self.last_fire_time = 0
    self.t = 0
    self.projectiles = {}
    self.projectile_bodies = {}
    self.damage_indicators = {}
    self.damaged = false
    self.max_projectiles = 30
    -- self.visibilityRange = 100

    self:initBehaviourTree()

    return self
end

function Enemy:initBehaviourTree()
    self.btree = BehaviourTree:new({
        tree = BehaviourTree.Sequence:new({
            nodes = {
                BehaviourTree.Task:new({
                    name = "check_player_range",
                    run = function(task, enemy)
                        if not player or not player.body then
                            task:fail()
                            return
                        end
                        local ex, ey = enemy.body:getPosition()
                        local px, py = player.body:getPosition()
                        local dx = px - ex
                        local dy = py - ey
                        local distance = math.sqrt(dx * dx + dy * dy)
                        if distance <= enemy.detection_range then
                            enemy.target = { x = px, y = py, distance = distance, dx = dx, dy = dy }
                            task:success()
                        else
                            enemy.target = nil
                            task:fail()
                        end
                    end
                }),
                BehaviourTree.Task:new({
                    name = "fire_at_player",
                    run = function(task, enemy)
                        if enemy.t - enemy.last_fire_time >= enemy.fire_cooldown + math.random() then
                            
                            -- local a = gun_enemies[enemy.fixture:getUserData() + 2]
                            -- a.setAnimation("shoot")

                            enemy:fireAtPlayer()
                            enemy.last_fire_time = enemy.t
                            task:success()
                        else
                            task:fail()
                        end
                    end
                }),
                BehaviourTree.Task:new({
                    -- name = "move_toward_player",
                    -- run = function(task, enemy)
                    --     local ex, ey = enemy.body:getPosition()
                    --     local dx = enemy.target.dx
                    --     local dy = enemy.target.dy
                    --     local distance = enemy.target.distance
                    --     local ideal_distance = 100

                    --     local a = gun_enemies[enemy.fixture:getUserData() + 2]
                            

                    --     if distance > ideal_distance + 50 then
                    --         local move_force = 500 * math.random(1, 5)
                    --         enemy.body:applyForce((dx / distance) * move_force, (dy / distance) * move_force)
                    --         a.setAnimation("walk")
                    --     elseif distance < ideal_distance - 50 then
                    --         local move_force = 200 * math.random(1, 5)
                    --         enemy.body:applyForce(-dx / distance * move_force, -dy / distance * move_force)
                    --         -- a.setAnimation("run")

                    --     elseif distance < 10 then
                    --         local move_force = 2000 * math.random(1, 5)
                    --         enemy.body:applyForce(dx / distance * move_force, dy / distance * move_force)
                    --         -- a.setAnimation("punch")

                    --     end
                    --     task:success()
                    -- end
                })
            }
        })
    })
    self.btree:setObject(self)
end

function Enemy:fireAtPlayer()
    local ex, ey = self.body:getPosition()
    if not self.target then return end
    local dx = self.target.dx
    local dy = self.target.dy
    local distance = self.target.distance
    if distance == 0 then return end

    local dir_x = dx / distance
    local dir_y = dy / distance

    local projectile = {
        vec2.new(ex, ey),
        vec2.new(dir_x * self.projectile_speed, dir_y * self.projectile_speed),
        true,
        self,
        self.t + 5.0
    }

    local proj_body = love.physics.newBody(world, ex, ey, "dynamic")
    local proj_fixture = love.physics.newFixture(proj_body, love.physics.newCircleShape(15))
    proj_fixture:setGroupIndex(778)
    proj_fixture:setUserData(#self.projectiles)

    table.insert(self.projectiles, projectile)
    table.insert(self.projectile_bodies, proj_body)
end

function Enemy:updateProjectiles(dt)
    for i = #self.projectiles, 1, -1 do
        local proj = self.projectiles[i]
        pcall(function()
        if self.t > proj[5] then
            if self.projectile_bodies[i] then
                -- self.projectile_bodies[i]:destroy()
                -- table.remove(self.projectile_bodies, i)
            end
            table.remove(self.projectiles, i)
        else
            proj[1] = proj[1] + proj[2] * dt
            if self.projectile_bodies[i] then
                self.projectile_bodies[i]:setPosition(proj[1].x, proj[1].y)
            end
        end
        end)
    end
end

function Enemy:getDirectionToPlayer(n)
    -- if (not self) then return false end
    -- Validate n
    if not n or type(n) ~= "number" or n < 1 then
        n = 8 -- Default to 8 directions
    end
    n = math.floor(n)

    -- Get positions
    local ex, ey = self.body:getPosition()
    local px, py = player.body:getPosition()

    -- Calculate vector to player
    local dx = px - ex
    local dy = py - ey

    -- Check if positions are too close
    if math.abs(dx) < 0.01 and math.abs(dy) < 0.01 then
        return nil -- Player is at enemy's position
    end

    -- Calculate angle in radians
    local angle = math.atan2(dx, dy) -- dx first in this case i dunno

    -- Apply transform (e.g., rotation offset in radians or function)
    -- if transform then
    --     if type(transform) == "number" then
    --         angle = angle + transform
    --     elseif type(transform) == "function" then
    --         angle = transform(angle, dx, dy)
    --     end
    -- end

    -- Convert to degrees and normalize to [0, 360)
    local angle_deg = math.deg(angle)
    if angle_deg < 0 then
        angle_deg = angle_deg + 360
    end

    -- Map to one of n directions
    local sector_size = 360 / n
    local direction = math.floor((angle_deg + sector_size / 2) / sector_size) % n + 1

    return direction
end

function Enemy:damageEnemy(damage)
    self.health = self.health - damage
    -- self.damaged = true

    -- local ex, ey = self.body:getPosition()
    -- local nearby_count = 0
    -- for _, ind in ipairs(self.damage_indicators) do
    --     local dist = math.sqrt((ind.x - ex) ^ 2 + (ind.y - ey) ^ 2)
    --     if dist < 50 then
    --         nearby_count = nearby_count + 1
    --     end
    -- end

    -- local angle = (nearby_count * 45) % 360
    -- local spread_radius = math.min(15 + nearby_count * 3, 35)
    -- local spread_x = math.cos(math.rad(angle)) * spread_radius
    -- local spread_y = math.sin(math.rad(angle)) * spread_radius * 0.5
    -- local base_duration = 1.0
    -- local duration_multiplier = math.max(0.3, 1.0 - (nearby_count * 0.1))
    -- local final_duration = base_duration * duration_multiplier

    -- table.insert(self.damage_indicators, {
    --     x = ex + spread_x,
    --     y = ey - 10 + spread_y,
    --     damage = damage,
    --     time = 0,
    --     duration = final_duration,
    --     velocity_y = -80 - (nearby_count * 5),
    --     velocity_x = math.random(-10, 10) + spread_x * 0.3,
    --     alpha = 1,
    --     scale = 1.2,
    --     bounce_factor = 0.95,
    --     nearby_count = nearby_count
    -- })

    if self.health <= 0 then
        if self.fixture then
            -- print(self.fixture:getUserData())
            gun_enemies[self.fixture:getUserData() + 1].on = false
            -- table.remove(enemy.enemies, self.fixture:getUserData() + 1)
            self:killEnemy()
        end
    end
end

function Enemy:killEnemy()
    self.body:destroy()
    self.fixture:destroy()
    self.fixture = nil
    self.dead = true
end

function Enemy:update(dt)
    if self.dead then return end
    self.t = self.t + dt
    self.btree:run()
    self:updateProjectiles(dt)
    if self.target then
        local x, y = self.body:getPosition()
        self.body:setPosition(x + (self.target.dx) * dt * 0.3, y + (self.target.dy) * dt * 0.3)
    end
    -- for i = #self.damage_indicators, 1, -1 do
    --     local indicator = self.damage_indicators[i]
    --     indicator.time = indicator.time + dt
    --     local progress = indicator.time / indicator.duration
    --     local ease_out = 1 - math.pow(1 - progress, 3)

    --     indicator.y = indicator.y + indicator.velocity_y * dt * indicator.bounce_factor
    --     indicator.x = indicator.x + indicator.velocity_x * dt
    --     indicator.velocity_y = indicator.velocity_y * 0.98
    --     indicator.velocity_x = indicator.velocity_x * 0.95

    --     local fade_start = indicator.nearby_count > 3 and 0.5 or 0.7
    --     if progress > fade_start then
    --         local fade_progress = (progress - fade_start) / (1.0 - fade_start)
    --         indicator.alpha = 1 - math.pow(fade_progress, 1.5)
    --     else
    --         indicator.alpha = 1
    --     end

    --     indicator.scale = 1.2 - (ease_out * 0.4)

        -- for j, other in ipairs(self.damage_indicators) do
        --     if i ~= j and other.time < other.duration then
        --         local dx = indicator.x - other.x
        --         local dy = indicator.y - other.y
        --         local dist = math.sqrt(dx * dx + dy * dy)
        --         if dist < 20 and dist > 0 then
        --             local separation_force = (20 - dist) / 20 * 15
        --             local norm_x = dx / dist
        --             local norm_y = dy / dist
        --             indicator.velocity_x = indicator.velocity_x + norm_x * separation_force * dt
        --             indicator.velocity_y = indicator.velocity_y + norm_y * separation_force * dt
        --         end
        --     end
        -- end

        -- if indicator.time >= indicator.duration then
        --     table.remove(self.damage_indicators, i)
        -- end
    -- end
end

-- Global enemy manager
local enemy = {
    enemies = {},
    particleSystem = nil,
    scale = 0.6,
    t = 0,
    max_projectiles_per_enemy = 30,
    fire_cooldown = 1,
    detection_range = 300,
    projectile_speed = 400,
    max_health = 20,
    health = {},
    damage_indicators = {},
    enemy_damaged = {},
    last_fire_times = {},
    projectiles = {},
    projectile_bodies = {}
}

function enemy.load()
    local fire_image = love.graphics.newImage("gfx/firelowres.png")
    local Quads = sprite:constructsprite(fire_image, 8, 8)
    enemy.particleSystem = love.graphics.newParticleSystem(fire_image, 200)
    enemy.particleSystem:setParticleLifetime(0.8, 1.5)
    enemy.particleSystem:setEmissionRate(12)
    enemy.particleSystem:setSizeVariation(0.8)
    enemy.particleSystem:setDirection(1.5 * 3.14)
    enemy.particleSystem:setSpeed(10, 30)
    enemy.particleSystem:setLinearDamping(0.2)
    enemy.particleSystem:setSpin(-0.5, 0.5)
    enemy.particleSystem:setColors(255, 100, 50, 255, 255, 50, 0, 0.1)
    if Quads then
        enemy.particleSystem:setQuads(Quads)
    end
    enemy.particleSystem:setRotation(0, 2 * 3.14)
    enemy.particleSystem:setOffset(sprite:getTileSize())
    enemy.particleSystem:setInsertMode('bottom')

    for i = 1, var.num_enemies do
        enemy.addEnemy(math.random(100, var.screen_width), math.random(100, var.screen_height))
    end
end

function enemy.update(dt)
    enemy.t = enemy.t + dt
    enemy.particleSystem:update(dt)

    for i = #enemy.enemies, 1, -1 do
        local e = enemy.enemies[i]
        e:update(dt)
        if e.health <= 0 then
            -- table.remove(enemy.enemies, i)
            enemy.last_fire_times[i] = nil
            enemy.health[i] = nil
            enemy.enemy_damaged[i] = nil
        end
    end
end

function enemy.damageEnemy(enemy_index, damage)
    -- print(enemy_index,"getting damaged")

    local e = enemy.enemies[enemy_index + 1]
    -- print(enemy.enemies[enemy_index])
    if e then
        e:damageEnemy(damage)
        enemy.health[enemy_index] = e.health
        enemy.enemy_damaged[enemy_index] = e.damaged
    end
end

function enemy.killEnemy(enemy_index)
    local e = enemy.enemies[enemy_index]
    if e then
        e:killEnemy()
    end
end

function enemy.addEnemy(x, y)
    local index = #enemy.enemies
    local e = Enemy.new(world, x, y, enemy.max_health, enemy.scale, enemy.fire_cooldown,
        enemy.detection_range, enemy.projectile_speed, index)
    table.insert(enemy.enemies, e)

    enemy.last_fire_times[index] = enemy.t - enemy.fire_cooldown
    enemy.health[index] = e.health
    enemy.enemy_damaged[index] = false


    return index, e.body
end

function enemy.removeEnemy(enemy_index)
    local e = enemy.enemies[enemy_index]
    if e then
        e:killEnemy()
    end
end

function enemy.fireAtPlayer(enemy_index, enemy_x, enemy_y, player_x, player_y)
    local e = enemy.enemies[enemy_index]
    if e then
        e.target = {
            x = player_x,
            y = player_y,
            distance = math.sqrt((player_x - enemy_x) ^ 2 + (player_y - enemy_y) ^ 2),
            dx = player_x - enemy_x,
            dy = player_y - enemy_y
        }
        e:fireAtPlayer()
    end
end

function enemy.updateProjectiles(dt)
    for _, e in ipairs(enemy.enemies) do
        e:updateProjectiles(dt)
    end
end

channelPreserve = { 1, 0, 1 } -- its counter intuitive but you need to preserve the too channels that will get one color cycle, if you preserve 1 channel you get 2 color cycle
-- function enemy.populate()
--     -- print(#enemy.enemies)
--     for _, e in ipairs(enemy.enemies) do

--         for _, proj in ipairs(e.projectiles) do
--             table.insert(dynamic_draw_list, {
--                 sort_y = proj[1].y + 140,
--                 image_or_particles = enemy.particleSystem,
--                 quad = nil,
--                 x = proj[1].x,
--                 y = proj[1].y,
--                 rotation = 0,
--                 scale_x = 1,
--                 scale_y = 1,
--                 offset_x = 0,
--                 offset_y = 0,
--                 color = { 1, 0.4, 0.2, 1 },
--                 blend_mode = { "lighten", "premultiplied" },
--                 source_object_type = "fire_effect"
--             })
--         end

--         -- for _, indicator in ipairs(e.damage_indicators) do
--         --     local damage = indicator.damage
--         --     local base_color, is_critical, is_mega_critical, is_splash = { 0.8, 0.2, 0.2 }, false, false,
--         --         indicator.is_splash_indicator
--         --     if is_splash then
--         --         base_color = { 0.2, 0.8, 1 }
--         --         is_critical = true
--         --     elseif type(damage) == "string" then
--         --         base_color = { 0.2, 0.8, 1 }
--         --         is_critical = true
--         --     elseif damage >= 35 then
--         --         base_color = { 1, 0.2, 1 }
--         --         is_mega_critical = true
--         --         is_critical = true
--         --     elseif damage >= 25 then
--         --         base_color = { 1, 0.5, 0.1 }
--         --         is_critical = true
--         --     elseif damage >= 18 then
--         --         base_color = { 1, 0.9, 0.2 }
--         --         is_critical = true
--         --     elseif damage >= 12 then
--         --         base_color = { 1, 0.3, 0.1 }
--         --     elseif damage >= 8 then
--         --         base_color = { 1, 0.15, 0.15 }
--         --     end

--         --     local saturation_boost = math.min(1.3, 1.0 + (indicator.nearby_count * 0.05))
--         --     local final_color = {
--         --         math.min(1, base_color[1] * saturation_boost),
--         --         math.min(1, base_color[2] * saturation_boost),
--         --         math.min(1, base_color[3] * saturation_boost)
--         --     }

--         --     local y_offset = -200 - (indicator.nearby_count * 2)
--         --     local final_scale = indicator.scale
--         --     local display_text
--         --     if is_splash then
--         --         final_scale = final_scale * 1.6
--         --         display_text = indicator.damage
--         --     elseif type(damage) == "string" then
--         --         final_scale = final_scale * 1.3
--         --         display_text = damage
--         --     else
--         --         local text_prefix = is_mega_critical and "★-" or is_critical and "!-" or "-"
--         --         final_scale = is_mega_critical and final_scale * 1.4 or is_critical and final_scale * 1.2 or final_scale
--         --         display_text = text_prefix .. damage
--         --     end

--         --     table.insert(dynamic_draw_list, {
--         --         sort_y = indicator.y + y_offset,
--         --         text = display_text,
--         --         x = indicator.x,
--         --         y = indicator.y,
--         --         font = gameFont,
--         --         color = { final_color[1], final_color[2], final_color[3], indicator.alpha },
--         --         scale = final_scale,
--         --         outline_color = { 0, 0, 0, indicator.alpha * (is_critical and 1.0 or 0.9) },
--         --         is_critical = is_critical,
--         --         is_mega_critical = is_mega_critical,
--         --         nearby_count = indicator.nearby_count,
--         --         blend_mode = { "alpha" },
--         --         source_object_type = "damage_indicator"
--         --     })

--         --     if is_mega_critical or is_splash then
--         --         table.insert(dynamic_draw_list, {
--         --             sort_y = indicator.y + y_offset - 1,
--         --             text = display_text,
--         --             x = indicator.x,
--         --             y = indicator.y,
--         --             font = gameFont,
--         --             color = is_splash and { 0.5, 1, 1, indicator.alpha * 0.4 } or { 1, 1, 1, indicator.alpha * 0.3 },
--         --             scale = final_scale * 1.1,
--         --             outline_color = { 0, 0, 0, 0 },
--         --             blend_mode = { "add" },
--         --             source_object_type = "damage_indicator"
--         --         })
--         --     end
--         -- end

--         -- if e.damaged and e.health > 0 then
--         --     local ex, ey = e.body:getPosition()
--         --     local health_percent = e.health / e.max_health
--         --     table.insert(dynamic_draw_list, {
--         --         sort_y = ey - 50,
--         --         rectangle = { x = ex - 25, y = ey - 35, width = 50, height = 6 },
--         --         color = { 0.2, 0.2, 0.2, 0.8 },
--         --         blend_mode = { "alpha" },
--         --         source_object_type = "health_bar_bg"
--         --     })
--         --     table.insert(dynamic_draw_list, {
--         --         sort_y = ey - 49,
--         --         rectangle = { x = ex - 24, y = ey - 34, width = 48 * health_percent, height = 4 },
--         --         color = health_percent > 0.3 and { 0.2, 0.8, 0.2, 0.9 } or { 0.8, 0.2, 0.2, 0.9 },
--         --         blend_mode = { "alpha" },
--         --         source_object_type = "health_bar_fill"
--         --     })
--         -- end

--         -- local ex, ey = e.body:getPosition()
--         -- local enemy_color = { 1, 1, 1, 1 }
--         -- if e.health then
--         --     local health_percent = e.health / e.max_health
--         --     if health_percent <= 0.3 then
--         --         local red_intensity = 1 - (health_percent / 0.3) * 0.3
--         --         enemy_color = { 1, 1 - red_intensity, 1 - red_intensity, 1 }
--         --     end
--         -- end

--         -- table.insert(dynamic_draw_list, {
--         --     sort_y = ey + (enemy_image and enemy_image:getHeight() * 0.1 / 2 or 0) + 100,
--         --     image_or_particles = enemy_image,
--         --     x = ex,
--         --     y = ey,
--         --     rotation = 0,
--         --     scale_x = 1,
--         --     scale_y = 1,
--         --     offset_x = enemy_image and enemy_image:getWidth() / 2 or 0,
--         --     offset_y = enemy_image and enemy_image:getHeight() / 2 or 0,
--         --     color = enemy_color,
--         --     blend_mode = { "alpha" },
--         --     source_object_type = "enemy"
--         -- })

--         local enemyInstance = gun_enemies[math.min(_ + 1,#enemy.enemies + 1)] -- the drawn instances

--         -- local princessInstance = princess[_]
--         -- enemyInstance.x, enemyInstance.y = ex, ey
--         enemyInstance.x, enemyInstance.y = e.body:getPosition()
--         -- princessInstance.x,princessInstance.y = ex+10,ey+10
--         -- print(player.velocity_x)
--         -- print(e:getDirectionToPlayer())
--         enemyInstance.setDirection(e:getDirectionToPlayer() or 1)
--         -- enemyInstance.setState(math.random(1,5))
--         -- characterAnimator.shader:send("outlineWidth", 1*math.sin(fire.t))

--         -- enemyInstance.color = {math.cos(fire.t*2 + _)*channelPreserve[1],math.cos(fire.t*2 + _)*channelPreserve[2],math.cos(fire.t*2 + _)*channelPreserve[3],math.sin(fire.t*2 + _)}
--     end
-- end


function enemy.populate()
    -- Clear or reset gun_enemies positions for dead enemies
    for i = 1, #gun_enemies do
        gun_enemies[i].active = false -- Mark as inactive initially
    end

    -- Map living enemies to gun_enemies based on their stored index
    for _, e in ipairs(enemy.enemies) do
        if e.fixture then
            if e.fixture:getUserData() then
                local enemy_index = e.fixture:getUserData()


                -- Ensure we don't go out of bounds
                if enemy_index and enemy_index >= 0 and enemy_index < #gun_enemies then
                    -- Lua arrays start at 1 (+ player is all stuffed into one array rn)
                    local enemyInstance = gun_enemies[enemy_index + 1]
                    if enemyInstance then
                        enemyInstance.active = true
                        enemyInstance.x, enemyInstance.y = e.body:getPosition()
                        enemyInstance.setDirection(e:getDirectionToPlayer() or 1)
                        enemyInstance.color = { math.cos(fire.t * 2 + _) * channelPreserve[1], math.cos(fire.t * 2 + _) *
                        channelPreserve[2], math.cos(fire.t * 2 + _) * channelPreserve[3], math.sin(fire.t * 2 + _) }
                    end
                end
            end
        end

        -- Handle projectiles (unchanged)
        for _, proj in ipairs(e.projectiles) do
            table.insert(dynamic_draw_list, {
                sort_y = proj[1].y + 140,
                image_or_particles = enemy.particleSystem,
                quad = nil,
                x = proj[1].x,
                y = proj[1].y,
                rotation = 0,
                scale_x = 1,
                scale_y = 1,
                offset_x = 0,
                offset_y = 0,
                color = { 1, 0.4, 0.2, 1 },
                blend_mode = { "lighten", "premultiplied" },
                source_object_type = "fire_effect"
            })
        end
    end
end

return enemy
