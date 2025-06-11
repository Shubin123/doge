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
    rockets = {},
    command_blocks = {}
}

-- Local player state (for smooth interpolation/prediction)
renderer.local_player_state = {
    x = 0, y = 0, animation_frame = 1, scale = 1, rotation = 0
}

flipQuads = true

-- Sorting function for Y-axis rendering
function renderer.sortByRenderY(drawable_a, drawable_b)
    return drawable_a.sort_y < drawable_b.sort_y
end

-- Network data setters
function renderer.setNetworkedPlayers(players_data)
    renderer.networked_state.players = players_data or {}
end

function renderer.setNetworkedEnemies(enemies_data)
    renderer.networked_state.enemies = enemies_data or {}
end

function renderer.setNetworkedCoins(coins_data)
    renderer.networked_state.coins = coins_data or {}
end

function renderer.setNetworkedFireEffects(fire_data)
    renderer.networked_state.fire_effects = fire_data or {}
end

function renderer.setNetworkedBullets(bullet_data)
    renderer.networked_state.bullets = bullet_data or {}
end

function renderer.setNetworkedRockets(rocket_data)
    renderer.networked_state.rockets = rocket_data or {}
end

function renderer.setNetworkedCommandBlocks(command_block_data)
    renderer.networked_state.command_blocks = command_block_data or {}
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

-- Core drawing functions
local function initDrawList()
    dynamic_draw_list = { unpack(map_a, 1, #map_a) }
    rebuildArray(dynamic_draw_list, map_b)
end

local function addPlayer(x, y, animation_frame, scale, rotation, player_id)
    local sort_y = y + (100 * scale)
    table.insert(dynamic_draw_list, {
        sort_y = sort_y + 45,
        image_or_particles = player.animation.spriteSheet,
        quad = player.animation.quads[((animation_frame + 5) % 5) + 6] or var.nullquad,
        x = x,
        y = y,
        rotation = rotation or 0,
        scale_x = scale,
        scale_y = scale,
        offset_x = 35,
        offset_y = 50,
        color = { 1, 1, 1, 1 },
        blend_mode = { "alpha" },
        source_object_type = "networked_player",
        player_id = player_id
    })
end

local function addPortal(x, y, sort_y)
    table.insert(dynamic_draw_list, {
        sort_y = sort_y,
        shader = portal.SHADERS["portal"],
        shader_params = portal.params,
        x = x,
        y = y,
        width = 35,
        height = 50,
        color = { 1, 1, 1, 1 },
        blend_mode = { "alpha" },
        source_object_type = "portal_shader"
    })
end

local function addLightEffect(light_shader, x, y, width, height, sort_y, color, light_type)
    table.insert(dynamic_draw_list, {
        sort_y = sort_y,
        light_shader = light_shader,
        x = x,
        y = y,
        width = width,
        height = height,
        color = color or { 1, 1, 1, 1 },
        blend_mode = { "add" },
        source_object_type = "light_effect",
        light_type = light_type
    })
end

local function addEnemiesFromBodies()
    for i = 1, #enemies_bods do
        local ex, ey = enemies_bods[i]:getX(), enemies_bods[i]:getY()
        table.insert(dynamic_draw_list, {
            sort_y = ey + (enemy_image:getHeight() * 0.1) / 2 + 100,
            image_or_particles = enemy_image,
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
end

local function addCoinsFromBodies()
    for i = 1, #coin_bods do
        local cx, cy = coin_bods[i]:getX(), coin_bods[i]:getY()
        table.insert(dynamic_draw_list, {
            sort_y = cy + (coin_image:getHeight() * 0.5) / 2 + 100,
            image_or_particles = coin_image,
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
end

local function addNetworkedEntities()
    -- Networked players
    for player_id, player_data in pairs(renderer.networked_state.players) do
        if player_data.active then
            addPlayer(player_data.x, player_data.y, player_data.animation_frame,
                player_data.scale, player_data.rotation, player_id)
        end
    end

    -- Networked enemies
    for _, enemy_data in pairs(renderer.networked_state.enemies) do
        if enemy_data.active then
            table.insert(dynamic_draw_list, {
                sort_y = enemy_data.y + (enemy_image:getHeight() * 0.1) / 2 + 100,
                image_or_particles = enemy_image,
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
                enemy_id = enemy_data.enemy_id
            })
        end
    end

    -- Networked coins
    for _, coin_data in pairs(renderer.networked_state.coins) do
        if coin_data.active then
            table.insert(dynamic_draw_list, {
                sort_y = coin_data.y + (coin_image:getHeight() * 0.5) / 2 + 100,
                image_or_particles = coin_image,
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
                coin_id = coin_data.coin_id
            })
        end
    end

    -- Networked fire effects
    for _, fire_data in pairs(renderer.networked_state.fire_effects) do
        table.insert(dynamic_draw_list, {
            sort_y = fire_data.y + 100,
            image_or_particles = fire.particleSystem,
            x = fire_data.x,
            y = fire_data.y,
            rotation = 0,
            scale_x = fire.scale,
            scale_y = fire.scale,
            offset_x = 250,
            offset_y = 50,
            color = { 1, 1, 1, 1 },
            blend_mode = { "lighten", "premultiplied" },
            source_object_type = "fire_effect"
        })

        -- Handle fire collision physics
        if fire_data.id and var.multiplayer == 1 and fire_data.active then
            local id = tostring(fire_data.id)
            if fire.online_fireables[id] then
                fire.online_fireables[id]:setPosition(fire_data.x - 200, fire_data.y - 45)
            else
                fire.online_fireables[id] = love.physics.newBody(world, fire_data.x - 200, fire_data.y - 45, "dynamic")
                local _fixture = love.physics.newFixture(fire.online_fireables[id], love.physics.newCircleShape(20))
                _fixture:setGroupIndex(-1)
            end
        end
    end

    -- Networked bullets
    for _, bullet_data in pairs(renderer.networked_state.bullets) do
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

    -- Networked rockets
    for _, rocket_data in pairs(renderer.networked_state.rockets) do
        if rocket_data.active then
            table.insert(dynamic_draw_list, {
                draw_type = "rocket_body",
                sort_y = rocket_data.y + 140,
                x = rocket_data.x,
                y = rocket_data.y,
                angle = 0,
                radius = 5,
                color = { 0.7, 0.7, 0.7, 1 },
                blend_mode = { "alpha" },
                source_object_type = "networked_rocket"
            })
        end
    end

    -- Networked command blocks
    for _, command_block_data in pairs(renderer.networked_state.command_blocks) do
        if command_block_data.active then
            table.insert(dynamic_draw_list, {
                sort_y = command_block_data.y + command_block_data.h + 100,
                image_or_particles = command_block_img,
                x = command_block_data.x,
                y = command_block_data.y,
                rotation = 0,
                scale_x = 1,
                scale_y = 1,
                offset_x = command_block_data.w / 2,
                offset_y = command_block_data.h / 2,
                color = { 1, 1, 1, 1 },
                blend_mode = { "alpha" },
                source_object_type = "networked_command_block",
                command = command_block_data.cmd
            })
        end
    end
end

-- Public populate functions (maintain existing interface)
function renderer.populateDynamicDrawListNetworked()
    initDrawList()
    addNetworkedEntities()

    -- Add local player
    addPlayer(renderer.local_player_state.x, renderer.local_player_state.y,
        renderer.local_player_state.animation_frame, renderer.local_player_state.scale,
        0, 69)

    addPortal(236, 190, 370)

    -- Add player light effect (using camera transforms)
    -- if blueNeon and player and player.body then
    --     local px, py = player.body:getX(), player.body:getY()
    --     addLightEffect(blueNeon, px, py, 100, 3, py + 45, { 0.17, 0.46, 1, 1 }, "player_neon")
    -- end

    fire.populate()
    -- bullet.populate()
    -- rocket.populate()
    -- light.populate()
    command.populate()
end

function renderer.populateDynamicDrawList()
    initDrawList()

    -- Local player from physics
    local px, py = player.body:getX(), player.body:getY()
    local spriteNum = math.floor(player.animation.currentTime / (player.animation.duration) * #player.animation.quads) +
    1
    addPlayer(px, py, spriteNum, player.scale, var.character_rotation, nil)

    addPortal(290, 150, 315)

    -- -- Add player light effect
    -- if blueNeon then
    --     addLightEffect(blueNeon,-camera.pos.x, -camera.pos.y, 100, 3, 10000, { 0.1, 0.46, 1, 1 }, "player_neon")
    -- end

    addEnemiesFromBodies()
    addCoinsFromBodies()

    fire.populate()
    enemy.populate()
    -- light.populate()
    command.populate()
end

function renderer.populateDynamicDrawListNETHOST()
    addEnemiesFromBodies()
    addCoinsFromBodies()
    enemy.populate()
end

-- function renderer.renderSortedDrawList()
--     -- Store current graphics state
--     local current_state = {
--         color = { love.graphics.getColor() },
--         blend_mode = love.graphics.getBlendMode(),
--         shader = love.graphics.getShader(),
--         line_width = love.graphics.getLineWidth()
--     }

--     local last_state = {
--         color = { 1, 1, 1, 1 },
--         blend_mode = { "alpha" },
--         line_width = 1
--     }

--     for _, drawable in ipairs(dynamic_draw_list) do
--         -- Optimize state changes
--         if drawable.color and not areColorsEqual(drawable.color, last_state.color) then
--             love.graphics.setColor(unpack(drawable.color))
--             last_state.color = drawable.color
--         end

--         if drawable.blend_mode and not areBlendModesEqual(drawable.blend_mode, last_state.blend_mode) then
--             love.graphics.setBlendMode(unpack(drawable.blend_mode))
--             last_state.blend_mode = drawable.blend_mode
--         end

--         if drawable.line_width and drawable.line_width ~= last_state.line_width then
--             love.graphics.setLineWidth(drawable.line_width)
--             last_state.line_width = drawable.line_width
--         end

--         -- Render based on type
--         if drawable.draw_type then
--             renderDrawType(drawable)
--         -- elseif drawable.light_shader then
--         --     renderLightEffect(drawable)
--         elseif drawable.shader then
--             renderShader(drawable)
--         elseif drawable.image_or_particles then
--             renderImage(drawable)
--         end
--     end

--     -- Restore state
--     love.graphics.setColor(unpack(current_state.color))
--     love.graphics.setBlendMode(current_state.blend_mode)
--     love.graphics.setShader(current_state.shader)
--     love.graphics.setLineWidth(current_state.line_width)
-- end

function renderer.renderSortedDrawList()
    -- Store current graphics state
    local current_color = { love.graphics.getColor() }
    local current_blend_mode = love.graphics.getBlendMode()
    local current_shader = love.graphics.getShader()

    local last_color = { 1, 1, 1, 1 }
    local last_blend_mode = { "alpha" }

    for _, drawable in ipairs(dynamic_draw_list) do
        -- Set color if different from last
        if drawable.color[1] ~= last_color[1] or drawable.color[2] ~= last_color[2] or
            drawable.color[3] ~= last_color[3] or drawable.color[4] ~= last_color[4] then
            love.graphics.setColor(drawable.color[1], drawable.color[2], drawable.color[3], drawable.color[4])
            last_color = drawable.color
        end

        -- Set blend mode if different from last
        if drawable.blend_mode[1] ~= last_blend_mode[1] or
            (drawable.blend_mode[2] and drawable.blend_mode[2] ~= last_blend_mode[2]) then
            if drawable.blend_mode[2] then
                love.graphics.setBlendMode(drawable.blend_mode[1], drawable.blend_mode[2])
            else
                love.graphics.setBlendMode(drawable.blend_mode[1])
            end
            last_blend_mode = drawable.blend_mode
        end

        -- Handle shader drawing
        if drawable.shader then
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

        -- Handle bullet effects drawing
        elseif drawable.source_object_type == "muzzle_flash" then
                   
        local current_color = { love.graphics.getColor() } 
        local current_blend_mode = love.graphics.getBlendMode()
        local current_shader = love.graphics.getShader()
            bullet.drawSingleMuzzleFlash(drawable.flash_data)
            
        love.graphics.setColor(current_color[1], current_color[2], current_color[3], current_color[4])
        love.graphics.setBlendMode(current_blend_mode)
        love.graphics.setShader(current_shader)

        elseif drawable.source_object_type == "gunpowder_particle" then
        
        local current_color = { love.graphics.getColor() }
        local current_blend_mode = love.graphics.getBlendMode()
        local current_shader = love.graphics.getShader()

            bullet.drawSingleParticle(drawable.particle_data)

        love.graphics.setColor(current_color[1], current_color[2], current_color[3], current_color[4])
        love.graphics.setBlendMode(current_blend_mode)
        love.graphics.setShader(current_shader)


        elseif drawable.source_object_type == "shell_casing" then
            
      local current_color = { love.graphics.getColor() }
        local current_blend_mode = love.graphics.getBlendMode()
        local current_shader = love.graphics.getShader()


            bullet.drawSingleShell(drawable.shell_data)
            -- love.graphics.setShader(current_shader)

                    love.graphics.setColor(current_color[1], current_color[2], current_color[3], current_color[4])
        love.graphics.setBlendMode(current_blend_mode)
        love.graphics.setShader(current_shader)
        elseif drawable.source_object_type == "bullet_tracer" then
            bullet.drawSingleTracer(drawable.bullet_data, drawable.x, drawable.y, drawable.distance)
            

            
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



        --  if drawable.draw_type then
        --     renderDrawType(drawable)
        -- -- elseif drawable.light_shader then
        -- --     renderLightEffect(drawable)
        -- elseif drawable.shader then
        --     renderShader(drawable)
        -- elseif drawable.image_or_particles then
        --     renderImage(drawable)
        -- end
    end


    

    -- Restore original graphics state
    love.graphics.setColor(current_color[1], current_color[2], current_color[3], current_color[4])
    love.graphics.setBlendMode(current_blend_mode)
    love.graphics.setShader(current_shader)
end


-- Helper functions for rendering
function areColorsEqual(c1, c2)
    return c1[1] == c2[1] and c1[2] == c2[2] and c1[3] == c2[3] and c1[4] == c2[4]
end

function areBlendModesEqual(b1, b2)
    return b1[1] == b2[1] and (b1[2] or nil) == (b2[2] or nil)
end

function renderDrawType(drawable)
    local d = drawable
    if d.draw_type == "muzzle_flash_core" or d.draw_type == "muzzle_flash_glow" then
        love.graphics.circle("fill", d.x, d.y, d.size)
    elseif d.draw_type == "muzzle_flash_direction" or d.draw_type == "bullet_trail" or
        d.draw_type == "bullet_tracer_glow" or d.draw_type == "bullet_tracer_core" then
        love.graphics.line(d.x1, d.y1, d.x2, d.y2)
    elseif d.draw_type == "shell_casing" then
        love.graphics.push()
        love.graphics.translate(d.x, d.y)
        love.graphics.rotate(d.rotation)
        love.graphics.rectangle("fill", -d.width / 2, -d.height / 2, d.width, d.height)
        love.graphics.pop()
    elseif d.draw_type == "shell_casing_highlight" then
        love.graphics.push()
        love.graphics.translate(d.x, d.y)
        love.graphics.rotate(d.rotation)
        love.graphics.rectangle("line", -d.width / 2, -d.height / 2, d.width, d.height)
        love.graphics.pop()
    elseif d.draw_type == "bullet_point" then
        love.graphics.circle("fill", d.x, d.y, d.radius)
    elseif d.draw_type == "rocket_exhaust" then
        renderRocketExhaust(d)
    elseif d.draw_type == "rocket_thrust" then
        renderRocketThrust(d)
    elseif d.draw_type == "rocket_body" then
        renderRocketBody(d)
    elseif d.draw_type == "rocket_explosion" then
        renderRocketExplosion(d)
    elseif d.draw_type == "text" then
        love.graphics.print(d.text, d.x, d.y)
    end
end

function renderRocketExhaust(d)
    love.graphics.setColor(1, 1, 0.8, d.alpha * 0.8)
    love.graphics.circle("fill", d.x, d.y, d.size * 0.5)
    love.graphics.setColor(1, 0.6, 0.2, d.alpha * 0.4)
    love.graphics.circle("fill", d.x, d.y, d.size)
    love.graphics.setColor(0.5, 0.5, 0.5, d.alpha * 0.3)
    love.graphics.circle("fill", d.x, d.y, d.size * 1.5)
end

function renderRocketThrust(d)
    love.graphics.setColor(1, 1, 0.9, 0.8)
    love.graphics.setLineWidth(d.radius * 0.8)
    love.graphics.line(d.x1, d.y1, d.x2, d.y2)
    love.graphics.setColor(1, 0.5, 0.1, 0.6)
    love.graphics.setLineWidth(d.radius * 1.4)
    love.graphics.line(d.x1, d.y1, d.x2, d.y2)
end

function renderRocketBody(d)
    love.graphics.push()
    love.graphics.translate(d.x, d.y)
    love.graphics.rotate(d.angle)

    -- Main body
    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    love.graphics.rectangle("fill", -d.radius * 0.6, -d.radius * 0.3, d.radius * 1.2, d.radius * 0.6)

    -- Nose cone
    love.graphics.setColor(0.9, 0.9, 0.9, 1)
    love.graphics.polygon("fill", d.radius * 0.6, 0, d.radius * 0.3, -d.radius * 0.2, d.radius * 0.3, d.radius * 0.2)

    -- Fins
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.polygon("fill", -d.radius * 0.6, -d.radius * 0.3, -d.radius * 0.8, -d.radius * 0.5, -d.radius * 0.5,
        -d.radius * 0.5)
    love.graphics.polygon("fill", -d.radius * 0.6, d.radius * 0.3, -d.radius * 0.8, d.radius * 0.5, -d.radius * 0.5,
        d.radius * 0.5)

    love.graphics.pop()
end

function renderRocketExplosion(d)
    if d.shockwaveRadius then
        love.graphics.setColor(1, 1, 0.8, d.alpha * 0.3)
        love.graphics.setLineWidth(8)
        love.graphics.circle("line", d.x, d.y, d.shockwaveRadius)
    end

    love.graphics.setColor(1, 1, 0.9, d.alpha * 0.9)
    love.graphics.circle("fill", d.x, d.y, d.radius * 0.6)
    love.graphics.setColor(1, 0.6, 0.1, d.alpha * 0.7)
    love.graphics.circle("fill", d.x, d.y, d.radius)
    love.graphics.setColor(0.8, 0.3, 0.1, d.alpha * 0.4)
    love.graphics.circle("fill", d.x, d.y, d.radius * 1.5)

    -- Debris particles
    for i = 1, 8 do
        local angle = (i / 8) * math.pi * 2
        local debrisX = d.x + math.cos(angle) * d.radius * 0.8
        local debrisY = d.y + math.sin(angle) * d.radius * 0.8
        love.graphics.setColor(0.6, 0.4, 0.2, d.alpha * 0.8)
        love.graphics.circle("fill", debrisX, debrisY, 2)
    end
end

function renderLightEffect(drawable)
    if drawable.light_shader then
        -- Pop the camera transform to draw in screen space
        love.graphics.pop()
        -- Convert world coordinates to screen coordinates
        local screen_x, screen_y = camera.worldToScreen(drawable.x, drawable.y)
        -- Set godsray light position if present
        if drawable.light_shader.godsray then
            local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
            local uv_x = screen_x / sw
            local uv_y = screen_y / sh
            drawable.light_shader.godsray.light_x = math.max(0, math.min(1, uv_x))
            drawable.light_shader.godsray.light_y = math.max(0, math.min(1, uv_y))
        end
        drawable.light_shader(function()
            love.graphics.setColor((drawable.color and unpack(drawable.color)) or 1,1,1,1)
            love.graphics.rectangle("fill", screen_x, screen_y, drawable.width, drawable.height, 5, 5, 20)
            love.graphics.setColor(1,1,1,1)
        end)
        -- Re-apply the camera transform for subsequent drawables
        love.graphics.push()
        camera.apply()
    end
end

function renderShader(drawable)
    love.graphics.setShader(drawable.shader)
    if drawable.shader_params and drawable.source_object_type == "portal_shader" then
        local p = drawable.shader_params
        drawable.shader:send("time", p.time)
        drawable.shader:send("spin_time", p.spin_time)
        drawable.shader:send("colour_1", p.colour_1)
        drawable.shader:send("colour_2", p.colour_2)
        drawable.shader:send("colour_3", p.colour_3)
        drawable.shader:send("contrast", p.contrast)
        drawable.shader:send("spin_amount", p.spin_amount)
    end
    love.graphics.rectangle("fill", drawable.x, drawable.y, drawable.width, drawable.height)
    love.graphics.setShader()
end

function renderImage(drawable)
    if drawable.quad then
        love.graphics.draw(drawable.image_or_particles, drawable.quad, drawable.x, drawable.y,
            drawable.rotation or 0, drawable.scale_x or 1, drawable.scale_y or 1,
            drawable.offset_x or 0, drawable.offset_y or 0)
    else
        love.graphics.draw(drawable.image_or_particles, drawable.x, drawable.y,
            drawable.rotation or 0, drawable.scale_x or 1, drawable.scale_y or 1,
            drawable.offset_x or 0, drawable.offset_y or 0)
    end
end

function rebuildArray(arr, innerElements)
    for i = 1, #innerElements do
        table.insert(arr, innerElements[i])
    end
end

return renderer