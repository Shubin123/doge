local renderer = {}
-- Dynamic draw list for Y-sorting
dynamic_draw_list = {}

-- Networked game state (managed by server, synced to clients)
renderer.networked_state = {
    players = {},      -- { player_id = { x, y, animation_frame, scale, rotation, ... } }
    enemies = {},      -- { enemy_id = { x, y, active, ... } }
    coins = {},        -- { coin_id = { x, y, active, ... } }
    fire_effects = {}, -- { effect_id = { x, y, active, ... } }
    bullets = {},
    rockets = {}
    -- Add other networked objects as needed
}

-- Local player state (for smooth interpolation/prediction)
renderer.local_player_state = {
    x = 0,
    y = 0,
    animation_frame = 1,
    scale = 1,
    rotation = 0
}

-- Sorting function for Y-axis rendering
function renderer.sortByRenderY(drawable_a, drawable_b)
    return drawable_a.sort_y < drawable_b.sort_y
end

flipQuads = true

-- Set networked player data (called by multiplayer system)
function renderer.setNetworkedPlayers(players_data)
    renderer.networked_state.players = players_data or {}
end

-- Set networked enemy data (called by multiplayer system)
function renderer.setNetworkedEnemies(enemies_data)
    renderer.networked_state.enemies = enemies_data or {}
end

-- Set networked coin data (called by multiplayer system)
function renderer.setNetworkedCoins(coins_data)
    renderer.networked_state.coins = coins_data or {}
end

-- Set networked fire effects data (called by multiplayer system)
function renderer.setNetworkedFireEffects(fire_data)
    renderer.networked_state.fire_effects = fire_data or {}
end

function renderer.setNetworkedBullets(bullet_data)
    renderer.networked_state.bullets = bullet_data or {}
end

function renderer.setNetworkedRockets(rocket_data)
    renderer.networked_state.rockets = rocket_data or {}
end

-- Update local player state (for host/single player)
function renderer.updateLocalPlayerFromPhysics()
    if player and player.body then
        local px, py = player.body:getX(), player.body:getY()
        renderer.local_player_state = {
            x = px,
            y = py,
            animation_frame = math.floor(player.animation.currentTime / (player.animation.duration) *
            #player.animation.quads) + 1,
            scale = player.scale,
            rotation = var.character_rotation or 0,
            active = true
        }
    end
end

-- Get local player state for network transmission
function renderer.getLocalPlayerState()
    return renderer.local_player_state
end

-- Function to populate dynamic draw list (multiplayer version)
function renderer.populateDynamicDrawListNetworked()
    -- Clear the list
    dynamic_draw_list = { unpack(map_a, 1, #map_a) }
    rebuildArray(dynamic_draw_list, map_b)

    -- Draw networked players

    for player_id, player_data in pairs(renderer.networked_state.players) do
        if player_data.active then
            local sort_y = player_data.y + (100 * player_data.scale)

            table.insert(dynamic_draw_list, {
                sort_y = sort_y + 45,
                image_or_particles = player.animation.spriteSheet, -- Assume same spritesheet for all players (!!! need offesets here for dynamic characters 100% gonna forget lol)
                quad = player.animation.quads[((player_data.animation_frame + 5) % 5) + 6] or var.nullquad,
                x = player_data.x,
                y = player_data.y,
                rotation = player_data.rotation,
                scale_x = player_data.scale,
                scale_y = player_data.scale,
                offset_x = 35,
                offset_y = 50,
                color = { 1, 1, 1, 1 },
                blend_mode = { "alpha" },
                source_object_type = "networked_player",
                player_id = player_id
            })
        end
    end

    -- draw the selfs
    local ls = renderer.local_player_state.y + (100 * player.scale)
    table.insert(dynamic_draw_list, {
        sort_y             = ls + 45,
        image_or_particles = player.animation.spriteSheet,
        quad               = player.animation.quads[((renderer.local_player_state.animation_frame + 5) % 5) + 6] or
        var.nullquad,
        x                  = renderer.local_player_state.x,
        y                  = renderer.local_player_state.y,
        rotation           = 0,
        scale_x            = renderer.local_player_state.scale,
        scale_y            = renderer.local_player_state.scale,
        offset_x           = 35,
        offset_y           = 50,
        color              = { 1, 1, 1, 1 },
        blend_mode         = { "alpha" },
        source_object_type = "networked_player",
        player_id          = 69
    })



    -- Portal shader drawable (positioned at specific location)
    table.insert(dynamic_draw_list, {
        sort_y = 370, -- Adjust depth as needed
        shader = portal.SHADERS["portal"],
        shader_params = portal.params,
        x = 236,
        y = 190,
        width = 35,
        height = 50,
        color = { 1, 1, 1, 1 },
        blend_mode = { "alpha" },
        source_object_type = "portal_shader"
    })

    -- Draw networked enemies
    for enemy_id, enemy_data in pairs(renderer.networked_state.enemies) do
        if enemy_data.active then
            local enemy_sort_y = enemy_data.y + (enemy_image:getHeight() * 0.1) / 2

            table.insert(dynamic_draw_list, {
                sort_y = enemy_sort_y + 100,
                image_or_particles = enemy_image,
                quad = nil,
                x = enemy_data.x,
                y = enemy_data.y,
                rotation = 0,
                scale_x = 0.1,
                scale_y = 0.1,
                offset_x = enemy_image:getWidth() / 2,
                offset_y = enemy_image:getHeight() / 2,
                color = { 1, 1, 1, 1 },
                blend_mode = { "alpha" },
                source_object_type = "networked_enemy",
                enemy_id = enemy_id
            })
        end
    end

    -- Draw networked coins
    for coin_id, coin_data in pairs(renderer.networked_state.coins) do
        if coin_data.active then
            local coin_sort_y = coin_data.y + (coin_image:getHeight() * 0.5) / 2

            table.insert(dynamic_draw_list, {
                sort_y = coin_sort_y + 100,
                image_or_particles = coin_image,
                quad = nil,
                x = coin_data.x,
                y = coin_data.y,
                rotation = 0,
                scale_x = 0.5,
                scale_y = 0.5,
                offset_x = coin_image:getWidth() / 2,
                offset_y = coin_image:getHeight() / 2,
                color = { 1, 1, 1, 1 },
                blend_mode = { "alpha" },
                source_object_type = "networked_coin",
                coin_id = coin_id
            })
        end
    end

    -- Draw networked fire effects
    for effect_id, fire_data in pairs(renderer.networked_state.fire_effects) do
        -- print(fire_data.active)
        -- for k,v in pairs(fire_data) do print(k,v) end
        -- print(#renderer.networked_state.fire_effects)


        -- print(fire_data.x)
        -- You'll need to adapt this based on your fire effect structure
        table.insert(dynamic_draw_list, {
            sort_y = fire_data.y + 100, -- this offset is dynamically transformed by the player whose firing not going to be correct once players positions not the same
            image_or_particles = fire.particleSystem,
            quad = nil,
            x = fire_data.x,
            y = fire_data.y,
            rotation = 0,
            scale_x = fire.scale,
            scale_y = fire.scale,
            offset_x = 250, --200 in motion its different
            offset_y = 50,  --45
            -- color = {0.13, 0.37, 1, 1}, -- make opponents a different color
            color = { 1, 1, 1, 1 },
            blend_mode = { "lighten", "premultiplied" },
            source_object_type = "fire_effect"
        })
        -- end
        
        if (fire_data.id) then
            local id =  tostring(fire_data.id)
            if (var.multiplayer == 1) and fire_data.active then -- on host if fire is active (fired state) enable collision for it
                -- print(fire_data.active)
                if (fire.online_fireables[id]) then
                    fire.online_fireables[id]:setPosition(fire_data.x - 200, fire_data.y - 45)
                else
                    fire.online_fireables[id] = love.physics.newBody(world, fire_data.x - 200, fire_data.y - 45, "dynamic")
                    local _fixture = love.physics.newFixture(fire.online_fireables[id], love.physics.newCircleShape(20))
                    _fixture:setGroupIndex(-1)
                end
            end
        end
    end

    -- Draw networked bullets
    for bullet_id, bullet_data in pairs(renderer.networked_state.bullets) do
        if bullet_data.active then
            table.insert(dynamic_draw_list, {
                sort_y = bullet_data.y + 140,
                draw_type = "bullet_point",
                x = bullet_data.x,
                y = bullet_data.y,
                radius = 2,
                color = { 1, 1, 1, 1 },
                blend_mode = { "alpha" },
                source_object_type = "networked_bullet"
            })
        end
    end

    -- Draw networked rockets
    for rocket_id, rocket_data in pairs(renderer.networked_state.rockets) do
        if rocket_data.active then
            table.insert(dynamic_draw_list, {
                draw_type = "rocket_body",
                sort_y = rocket_data.y + 140,
                x = rocket_data.x, y = rocket_data.y,
                angle = 0, -- Should be calculated based on velocity
                radius = 5,
                color = {0.7, 0.7, 0.7, 1},
                blend_mode = {"alpha"},
                source_object_type = "networked_rocket"
            })
        end
    end

    fire.populate()
    bullet.populate()
    rocket.populate()
    -- enemy.populate()
end

-- Original function for local/single player (keeps physics body access)
function renderer.populateDynamicDrawList()
    -- Clear the list
    dynamic_draw_list = { unpack(map_a, 1, #map_a) }
    rebuildArray(dynamic_draw_list, map_b)

    -- Player drawable (from physics body)
    local px, py = player.body:getX(), player.body:getY()
    local spriteNum = math.floor(player.animation.currentTime / (player.animation.duration) * #player.animation.quads) +
    1
    local sort_y = py + (100 * player.scale)

    table.insert(dynamic_draw_list, {
        sort_y = sort_y + 45,
        image_or_particles = player.animation.spriteSheet,
        quad = player.animation.quads[(spriteNum + 5) % 5 + 6] or var.nullquad,
        x = px,
        y = py,
        rotation = var.character_rotation,
        scale_x = player.scale,
        scale_y = player.scale,
        offset_x = 35,
        offset_y = 50,
        color = { 1, 1, 1, 1 },
        blend_mode = { "alpha" },
        source_object_type = "player"
    })

    -- Portal shader drawable (positioned at specific location)
    table.insert(dynamic_draw_list, {
        sort_y = 315, -- Adjust depth as needed
        shader = portal.SHADERS["portal"],
        shader_params = portal.params,
        x = 290,
        y = 150,
        width = 35,
        height = 50,
        color = { 1, 1, 1, 1 },
        blend_mode = { "alpha" },
        source_object_type = "portal_shader"
    })

    -- Enemies drawables (from physics bodies)
    for i = 1, #enemies_bods do
        local ex, ey = enemies_bods[i]:getX(), enemies_bods[i]:getY()
        local enemy_sort_y = ey + (enemy_image:getHeight() * 0.1) / 2

        table.insert(dynamic_draw_list, {
            sort_y = enemy_sort_y + 100,
            image_or_particles = enemy_image,
            quad = nil,
            x = ex,
            y = ey,
            rotation = 0,
            scale_x = 0.1,
            scale_y = 0.1,
            offset_x = enemy_image:getWidth() / 2,
            offset_y = enemy_image:getHeight() / 2,
            color = { 1, 1, 1, 1 },
            blend_mode = { "alpha" },
            source_object_type = "enemy"
        })
    end

    -- Coins drawables (from physics bodies)
    for i = 1, #coin_bods do
        local cx, cy = coin_bods[i]:getX(), coin_bods[i]:getY()
        local coin_sort_y = cy + (coin_image:getHeight() * 0.5) / 2

        table.insert(dynamic_draw_list, {
            sort_y = coin_sort_y + 100,
            image_or_particles = coin_image,
            quad = nil,
            x = cx,
            y = cy,
            rotation = 0,
            scale_x = 0.5,
            scale_y = 0.5,
            offset_x = coin_image:getWidth() / 2,
            offset_y = coin_image:getHeight() / 2,
            color = { 1, 1, 1, 1 },
            blend_mode = { "alpha" },
            source_object_type = "coin"
        })
    end

    -- Fire effects drawables
    fire.populate()
    enemy.populate()
end

function renderer.populateDynamicDrawListNETHOST()
    -- Enemies drawables (from physics bodies)
    for i = 1, #enemies_bods do
        local ex, ey = enemies_bods[i]:getX(), enemies_bods[i]:getY()
        local enemy_sort_y = ey + (enemy_image:getHeight() * 0.1) / 2

        table.insert(dynamic_draw_list, {
            sort_y = enemy_sort_y + 100,
            image_or_particles = enemy_image,
            quad = nil,
            x = ex,
            y = ey,
            rotation = 0,
            scale_x = 0.1,
            scale_y = 0.1,
            offset_x = enemy_image:getWidth() / 2,
            offset_y = enemy_image:getHeight() / 2,
            color = { 1, 1, 1, 1 },
            blend_mode = { "alpha" },
            source_object_type = "enemy"
        })
    end

    -- Coins drawables (from physics bodies)
    for i = 1, #coin_bods do
        local cx, cy = coin_bods[i]:getX(), coin_bods[i]:getY()
        local coin_sort_y = cy + (coin_image:getHeight() * 0.5) / 2

        table.insert(dynamic_draw_list, {
            sort_y = coin_sort_y + 100,
            image_or_particles = coin_image,
            quad = nil,
            x = cx,
            y = cy,
            rotation = 0,
            scale_x = 0.5,
            scale_y = 0.5,
            offset_x = coin_image:getWidth() / 2,
            offset_y = coin_image:getHeight() / 2,
            color = { 1, 1, 1, 1 },
            blend_mode = { "alpha" },
            source_object_type = "coin"
        })
    end


    enemy.populate()
end

function renderer.renderSortedDrawList()
    -- Store current graphics state
    local current_color = { love.graphics.getColor() }
    local current_blend_mode = love.graphics.getBlendMode()
    local current_shader = love.graphics.getShader()
    local current_line_width = love.graphics.getLineWidth()

    local last_color = { 1, 1, 1, 1 }
    local last_blend_mode = { "alpha" }
    local last_line_width = 1

    for _, drawable in ipairs(dynamic_draw_list) do
        -- Set color if different from last
        if drawable.color and (drawable.color[1] ~= last_color[1] or drawable.color[2] ~= last_color[2] or
            drawable.color[3] ~= last_color[3] or drawable.color[4] ~= last_color[4]) then
            love.graphics.setColor(drawable.color[1], drawable.color[2], drawable.color[3], drawable.color[4])
            last_color = drawable.color
        end

        -- Set blend mode if different from last
        if drawable.blend_mode and (drawable.blend_mode[1] ~= last_blend_mode[1] or
            (drawable.blend_mode[2] and drawable.blend_mode[2] ~= last_blend_mode[2])) then
            if drawable.blend_mode[2] then
                love.graphics.setBlendMode(drawable.blend_mode[1], drawable.blend_mode[2])
            else
                love.graphics.setBlendMode(drawable.blend_mode[1])
            end
            last_blend_mode = drawable.blend_mode
        end

        -- Set line width if different from last
        if drawable.line_width and drawable.line_width ~= last_line_width then
            love.graphics.setLineWidth(drawable.line_width)
            last_line_width = drawable.line_width
        end

        -- Handle different draw types
        if drawable.draw_type then
            -- Bullet-specific draw types
            if drawable.draw_type == "muzzle_flash_core" then
                love.graphics.circle("fill", drawable.x, drawable.y, drawable.size)
                
            elseif drawable.draw_type == "muzzle_flash_glow" then
                love.graphics.circle("fill", drawable.x, drawable.y, drawable.size)
                
            elseif drawable.draw_type == "muzzle_flash_direction" then
                love.graphics.line(drawable.x1, drawable.y1, drawable.x2, drawable.y2)
                
            elseif drawable.draw_type == "shell_casing" then
                love.graphics.push()
                love.graphics.translate(drawable.x, drawable.y)
                love.graphics.rotate(drawable.rotation)
                love.graphics.rectangle("fill", -drawable.width/2, -drawable.height/2, 
                                      drawable.width, drawable.height)
                love.graphics.pop()
                
            elseif drawable.draw_type == "shell_casing_highlight" then
                love.graphics.push()
                love.graphics.translate(drawable.x, drawable.y)
                love.graphics.rotate(drawable.rotation)
                love.graphics.rectangle("line", -drawable.width/2, -drawable.height/2, 
                                      drawable.width, drawable.height)
                love.graphics.pop()
                
            elseif drawable.draw_type == "bullet_trail" then
                love.graphics.line(drawable.x1, drawable.y1, drawable.x2, drawable.y2)
                
            elseif drawable.draw_type == "bullet_tracer_glow" then
                love.graphics.line(drawable.x1, drawable.y1, drawable.x2, drawable.y2)
                
            elseif drawable.draw_type == "bullet_tracer_core" then
                love.graphics.line(drawable.x1, drawable.y1, drawable.x2, drawable.y2)
                
            elseif drawable.draw_type == "bullet_point" then
                love.graphics.circle("fill", drawable.x, drawable.y, drawable.radius)
            
            -- Rocket-specific draw types
            elseif drawable.draw_type == "rocket_exhaust" then
                -- Hot exhaust core
                love.graphics.setColor(1, 1, 0.8, drawable.alpha * 0.8)
                love.graphics.circle("fill", drawable.x, drawable.y, drawable.size * 0.5)
                -- Cooler exhaust glow
                love.graphics.setColor(1, 0.6, 0.2, drawable.alpha * 0.4)
                love.graphics.circle("fill", drawable.x, drawable.y, drawable.size)
                -- Smoke trail
                love.graphics.setColor(0.5, 0.5, 0.5, drawable.alpha * 0.3)
                love.graphics.circle("fill", drawable.x, drawable.y, drawable.size * 1.5)

            elseif drawable.draw_type == "rocket_thrust" then
                -- Main thrust flame
                love.graphics.setColor(1, 1, 0.9, 0.8)
                love.graphics.setLineWidth(drawable.radius * 0.8)
                love.graphics.line(drawable.x1, drawable.y1, drawable.x2, drawable.y2)
                -- Outer thrust glow
                love.graphics.setColor(1, 0.5, 0.1, 0.6)
                love.graphics.setLineWidth(drawable.radius * 1.4)
                love.graphics.line(drawable.x1, drawable.y1, drawable.x2, drawable.y2)

            elseif drawable.draw_type == "rocket_body" then
                love.graphics.push()
                love.graphics.translate(drawable.x, drawable.y)
                love.graphics.rotate(drawable.angle)
                -- Main rocket body
                love.graphics.setColor(0.7, 0.7, 0.7, 1)
                love.graphics.rectangle("fill", -drawable.radius*0.6, -drawable.radius*0.3, drawable.radius*1.2, drawable.radius*0.6)
                -- Rocket nose cone
                love.graphics.setColor(0.9, 0.9, 0.9, 1)
                love.graphics.polygon("fill",
                    drawable.radius*0.6, 0,
                    drawable.radius*0.3, -drawable.radius*0.2,
                    drawable.radius*0.3, drawable.radius*0.2
                )
                -- Fins
                love.graphics.setColor(0.5, 0.5, 0.5, 1)
                love.graphics.polygon("fill",
                    -drawable.radius*0.6, -drawable.radius*0.3,
                    -drawable.radius*0.8, -drawable.radius*0.5,
                    -drawable.radius*0.5, -drawable.radius*0.5
                )
                love.graphics.polygon("fill",
                    -drawable.radius*0.6, drawable.radius*0.3,
                    -drawable.radius*0.8, drawable.radius*0.5,
                    -drawable.radius*0.5, drawable.radius*0.5
                )
                love.graphics.pop()

            elseif drawable.draw_type == "rocket_explosion" then
                -- Draw expanding shockwave
                if drawable.shockwaveRadius then
                    love.graphics.setColor(1, 1, 0.8, drawable.alpha * 0.3)
                    love.graphics.setLineWidth(8)
                    love.graphics.circle("line", drawable.x, drawable.y, drawable.shockwaveRadius)
                end
                -- Draw main explosion blast
                love.graphics.setColor(1, 1, 0.9, drawable.alpha * 0.9)
                love.graphics.circle("fill", drawable.x, drawable.y, drawable.radius * 0.6)
                -- Draw outer explosion
                love.graphics.setColor(1, 0.6, 0.1, drawable.alpha * 0.7)
                love.graphics.circle("fill", drawable.x, drawable.y, drawable.radius)
                -- Draw explosion glow
                love.graphics.setColor(0.8, 0.3, 0.1, drawable.alpha * 0.4)
                love.graphics.circle("fill", drawable.x, drawable.y, drawable.radius * 1.5)
                -- Add some debris particles
                for i = 1, 8 do
                    local angle = (i / 8) * math.pi * 2
                    local debrisX = drawable.x + math.cos(angle) * drawable.radius * 0.8
                    local debrisY = drawable.y + math.sin(angle) * drawable.radius * 0.8
                    love.graphics.setColor(0.6, 0.4, 0.2, drawable.alpha * 0.8)
                    love.graphics.circle("fill", debrisX, debrisY, 2)
                end
            end
        -- Handle shader drawing
        elseif drawable.shader then
            -- Set shader and parameters
            love.graphics.setShader(drawable.shader)
            if drawable.shader_params and drawable.source_object_type == "portal_shader" then
                drawable.shader:send("time", drawable.shader_params.time)
                drawable.shader:send("spin_time", drawable.shader_params.spin_time)
                drawable.shader:send("colour_1", drawable.shader_params.colour_1)
                drawable.shader:send("colour_2", drawable.shader_params.colour_2)
                drawable.shader:send("colour_3", drawable.shader_params.colour_3)
                drawable.shader:send("contrast", drawable.shader_params.contrast)
                drawable.shader:send("spin_amount", drawable.shader_params.spin_amount)
            end

            -- Draw shader rectangle
            love.graphics.rectangle("fill", drawable.x, drawable.y, drawable.width, drawable.height)

            -- Reset shader
            love.graphics.setShader()

        -- Handle regular image drawing
        elseif drawable.image_or_particles then
            if drawable.quad then
                love.graphics.draw(
                    drawable.image_or_particles,
                    drawable.quad,
                    drawable.x,
                    drawable.y,
                    drawable.rotation or 0,
                    drawable.scale_x or 1,
                    drawable.scale_y or 1,
                    drawable.offset_x or 0,
                    drawable.offset_y or 0
                )
            else
                love.graphics.draw(
                    drawable.image_or_particles,
                    drawable.x,
                    drawable.y,
                    drawable.rotation or 0,
                    drawable.scale_x or 1,
                    drawable.scale_y or 1,
                    drawable.offset_x or 0,
                    drawable.offset_y or 0
                )
            end
        end
    end

    -- Restore original graphics state
    love.graphics.setColor(current_color[1], current_color[2], current_color[3], current_color[4])
    love.graphics.setBlendMode(current_blend_mode)
    love.graphics.setShader(current_shader)
    love.graphics.setLineWidth(current_line_width)
end

function rebuildArray(arr, innerElements)
    for i = 1, #innerElements do
        table.insert(arr, innerElements[i])
    end
end



return renderer
