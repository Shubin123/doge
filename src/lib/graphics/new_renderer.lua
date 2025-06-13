local rendererPlus = {}

rendererPlus.debug_mode = true

-- Asset Management System
local assets = {
    textures = {},
    shaders = {},
    particle_systems = {},
    fonts = {}
}

-- Effect System
local effects = {
    particles = {},
    shaders = {},
    lights = {},
    post_processing = {}
}

-- Render Queue System
local render_queue = {
    background = {},
    world = {},
    ui = {},
    effects = {},
    post_process = {}
}

-- Performance Tracking
local performance = {
    frame_time = 0,
    draw_calls = 0,
    vertices_drawn = 0,
    last_gc = 0
}

-- Asset Preloading System
function rendererPlus.preloadAssets()
    local missing_textures = {}
    -- Define all assets to preload from gfx folder
    local asset_paths = {
        -- Character sprites
        ["player_idle"] = "src/gfx/testCharacter/idle.png",
        ["player_walk"] = "src/gfx/testCharacter/walk.png",
        ["player_run"] = "src/gfx/testCharacter/run.png",
        ["player_jump"] = "src/gfx/testCharacter/jump.png",
        ["player_combat"] = "src/gfx/testCharacter/combat_idle.png",
        ["player_slash"] = "src/gfx/testCharacter/slash.png",
        ["player_shoot"] = "src/gfx/testCharacter/shoot.png",
        ["player_hurt"] = "src/gfx/testCharacter/hurt.png",
        
        -- Enemy sprites
        ["Jerome_Enemy"] = "src/gfx/enemy.png",
        
        -- bear: boss sprites
        ["bear_boss_default"] = "src/gfx/EnemiesSpriteSheets/BearBoss/bear_enemy_default_state.png",
        ["bear_boss_threatening"] = "src/gfx/EnemiesSpriteSheets/BearBoss/bear_enemy_laser_threatening.png",
        ["bear_boss_shooting"] = "src/gfx/EnemiesSpriteSheets/BearBoss/bear_enemy_laser_shooting.png",
        ["bear_boss_headless"] = "src/gfx/EnemiesSpriteSheets/BearBoss/bear_boss_headless.png",
        ["bear_boss_backside"] = "src/gfx/EnemiesSpriteSheets/BearBoss/bear_boss_backside.pxo.png",
        ["bear_dust"] = "src/gfx/EnemiesSpriteSheets/BearBoss/bear_dust_landing.png",
        
        -- Soldier sprites
        ["soldier_base"] = "src/gfx/SoldierSpriteSheets/Soldier.png",
        ["soldier_idle"] = "src/gfx/SoldierSpriteSheets/Soldier_Idle.png",
        ["soldier_walk"] = "src/gfx/SoldierSpriteSheets/Soldier_Walk.png",
        ["soldier_attack1"] = "src/gfx/SoldierSpriteSheets/Soldier_Attack01.png",
        ["soldier_attack2"] = "src/gfx/SoldierSpriteSheets/Soldier_Attack02.png",
        ["soldier_attack3"] = "src/gfx/SoldierSpriteSheets/Soldier_Attack03.png",
        ["soldier_death"] = "src/gfx/SoldierSpriteSheets/Soldier_Death.png",
        ["soldier_hit"] = "src/gfx/SoldierSpriteSheets/Soldier_Hit.png",
        
        -- Warrior sprites
        ["warrior_effect"] = "src/gfx/WarriorSpriteSheet/Warrior_Sheet-Effect.png",
        ["warrior_no_effect"] = "src/gfx/WarriorSpriteSheet/Warrior_SheetnoEffect.png",
        
        -- Dancing girl sprites
        ["dance_balance"] = "src/gfx/DancingGirlSheets/balancing.png",
        ["dance_hips"] = "src/gfx/DancingGirlSheets/hips.png",
        ["dance_skip"] = "src/gfx/DancingGirlSheets/skip.png",
        ["dance_slide"] = "src/gfx/DancingGirlSheets/slide.png",
        ["dance_snap"] = "src/gfx/DancingGirlSheets/snap.png",
        
        -- Items
        ["coin"] = "src/gfx/coin.png",
        ["apple"] = "src/gfx/apple.png",
        ["doge"] = "src/gfx/doge.png",
        
        -- Environment
        ["color_blocks"] = "src/gfx/Color_Blocks.png",
        ["noise"] = "src/gfx/noise.png",
        ["npc"] = "src/gfx/npc.png",
        ["old_hero"] = "src/gfx/oldHero.png",
        
        -- Tilesets
        ["tileset_grass"] = "src/gfx/TileSet/TX Tileset Grass.png",
        ["tileset_stone"] = "src/gfx/TileSet/TX Tileset Stone Ground.png",
        ["tileset_wall"] = "src/gfx/TileSet/TX Tileset Wall.png",
        ["tileset_plant"] = "src/gfx/TileSet/TX Plant.png",
        ["tileset_player"] = "src/gfx/TileSet/TX Player.png",
        ["tileset_props"] = "src/gfx/TileSet/TX Props.png",
        ["tileset_shadow"] = "src/gfx/TileSet/TX Shadow.png",
        ["tileset_shadow_plant"] = "src/gfx/TileSet/TX Shadow Plant.png",
        ["tileset_struct"] = "src/gfx/TileSet/TX Struct.png",
        
        -- Fire effects
        ["fireball"] = "src/gfx/fireball.png",
        ["fire_low"] = "src/gfx/firelowres.png",
        ["burning_loop"] = "src/gfx/burning_loop_1.png",
        
        -- UI
        ["hitmarker"] = "src/gfx/menu/hitmarker_1.png",
        ["old_hand"] = "src/gfx/menu/old_hand.png",
        
        -- FX Spritesheets
        ["blood_splat"] = "src/gfx/fx/Spritesheets/Blood Splat.png",
        ["electric_sheet"] = "src/gfx/fx/Spritesheets/Eletric A-Sheet.png",
        ["electric_aura"] = "src/gfx/fx/Spritesheets/Eletric Aura.png",
        ["fire_sparks"] = "src/gfx/fx/Spritesheets/Fire+Sparks-Sheet.png",
        ["flamethrower"] = "src/gfx/fx/Spritesheets/Flamethrower-Sheet.png",
        ["gravity_sheet"] = "src/gfx/fx/Spritesheets/Gravity-Sheet.png",
        ["holy_light"] = "src/gfx/fx/Spritesheets/Holy Light Aura.png",
        ["leaves_sheet"] = "src/gfx/fx/Spritesheets/Leaves-Sheet.png",
        ["poison_cloud"] = "src/gfx/fx/Spritesheets/Poison Cloud-Sheet.png",
        ["regen"] = "src/gfx/fx/Spritesheets/Regen.png",
        ["rocket_fire"] = "src/gfx/fx/Spritesheets/Rocket Fire 2-Sheet.png",
        ["sakuras"] = "src/gfx/fx/Spritesheets/Sakuras.png",
        ["smoke_sheet"] = "src/gfx/fx/Spritesheets/Smoke-Sheet.png",
        ["smoke2_sheet"] = "src/gfx/fx/Spritesheets/Smoke2-Sheet.png",
        ["spark1_sheet"] = "src/gfx/fx/Spritesheets/Spark1-Sheet.png",
        ["sparks_sheet"] = "src/gfx/fx/Spritesheets/Sparks-Sheet.png",
        ["splatter_sheet"] = "src/gfx/fx/Spritesheets/Splatter-Sheet.png",
        ["water_vortex"] = "src/gfx/fx/Spritesheets/Water Vortex Splash-Sheet.png",
        ["laser_particles"] = "src/gfx/EnemiesSpriteSheets/BearBoss/laser_charging_particles.png"
    }
    
    local function normalize(path)
        return path:gsub("^src/", "")
    end

    -- Load all textures
    for name, path in pairs(asset_paths) do
        local loadPath = normalize(path)
        local success, texture = pcall(love.graphics.newImage, loadPath)
        if success then
            assets.textures[name] = texture
            print("[rendererPlus] Loaded texture: " .. name .. " from " .. loadPath)
        else
            table.insert(missing_textures, name)
            print("[rendererPlus] Failed to load texture: " .. name .. " from " .. loadPath)
        end
    end
    if #missing_textures > 0 then
        print("[rendererPlus] Missing textures summary:")
        for _, name in ipairs(missing_textures) do
            print(" - " .. name)
        end
    end
    -- Load fonts
    local font_paths = {
        ["game_font"] = "src/gfx/menu/stats_font.ttf",
        ["pixel_font"] = "src/gfx/menu/PixelGameFont.ttf",
        ["vga_font"] = "src/gfx/menu/Px437_IBM_VGA_8x16.ttf"
    }
    
    for name, path in pairs(font_paths) do
        local success, font = pcall(love.graphics.newFont, path, 16)
        if success then
            assets.fonts[name] = font
            print("[rendererPlus] Loaded font: " .. name)
        else
            print("[rendererPlus] Failed to load font: " .. name)
        end
    end
    
    print("[rendererPlus] Asset preloading complete!")
end

-- Particle System Manager
function rendererPlus.createParticleSystem(texture_name, buffer_size)
    local texture = assets.textures[texture_name]
    if not texture then
        print("[rendererPlus] Warning: Texture not found for particle system: " .. texture_name)
        return nil
    end
    
    local ps = love.graphics.newParticleSystem(texture, buffer_size or 100)
    return ps
end

-- Shader Management
function rendererPlus.loadShader(name, vertex_path, fragment_path)
    local success, shader = pcall(love.graphics.newShader, vertex_path, fragment_path)
    if success then
        assets.shaders[name] = shader
        print("[rendererPlus] shader --> " .. name .. " loaded")
        return shader
    else
        print("[rendererPlus] Failed to load shader: " .. name)
        return nil
    end
end

-- Render Queue Management
function rendererPlus.clearQueue()
    render_queue.background = {}
    render_queue.world = {}
    render_queue.ui = {}
    render_queue.effects = {}
    render_queue.post_process = {}
end

function rendererPlus.addToQueue(layer, draw_data)
    if not render_queue[layer] then
        print("[rendererPlus] Warning: Invalid render layer: " .. tostring(layer))
        return
    end
    if not draw_data or type(draw_data) ~= "table" then
        print("[rendererPlus] Warning: Invalid draw data provided to addToQueue --> note: draw_data or type(draw_data) ~= 'table'")
        return
    end
    table.insert(render_queue[layer], draw_data)
end

-- Enhanced Drawing Functions
function rendererPlus.drawSprite(sprite_name, x, y, rotation, scale_x, scale_y, offset_x, offset_y)
    local texture = assets.textures[sprite_name]
    if not texture then
        -- Debug placeholder for missing texture
        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.rectangle("fill", x or 0, y or 0, 16, 16)
        love.graphics.setColor(1, 1, 1, 1)
        print("[rendererPlus] Debug placeholder: Missing texture '" .. tostring(sprite_name) .. "'")
        return
    end
    
    love.graphics.draw(
        texture,
        x, y,
        rotation or 0,
        scale_x or 1, scale_y or 1,
        offset_x or 0, offset_y or 0
    )
end

function rendererPlus.drawSpriteWithQuad(sprite_name, quad, x, y, rotation, scale_x, scale_y, offset_x, offset_y, color)
    local texture = assets.textures[sprite_name]
    if not texture then
        -- Debug placeholder for missing texture with quad
        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.rectangle("fill", x or 0, y or 0, quad and quad:getViewport() or 16, 16)
        love.graphics.setColor(1, 1, 1, 1)
        print("[rendererPlus] Debug placeholder quad: Missing texture '" .. tostring(sprite_name) .. "'")
        return
    end
    
    love.graphics.draw(
        texture, quad,
        x, y,
        rotation or 0,
        scale_x or 1, scale_y or 1,
        offset_x or 0, offset_y or 0
    )
end

-- Effect System
function rendererPlus.addParticleEffect(name, x, y, effect_type, params)
    local effect = {
        name = name,
        x = x,
        y = y,
        type = effect_type,
        params = params or {},
        created_time = love.timer.getTime(),
        active = true
    }
    
    table.insert(effects.particles, effect)
    return effect
end

function rendererPlus.addShaderEffect(name, shader_name, x, y, width, height, params)
    local shader = assets.shaders[shader_name]
    if not shader then
        print("[rendererPlus] Warning: Shader not found: " .. tostring(shader_name))
        return nil
    end
    
    local effect = {
        name = name,
        shader = shader,
        x = x,
        y = y,
        width = width,
        height = height,
        params = params or {},
        created_time = love.timer.getTime(),
        active = true
    }
    
    table.insert(effects.shaders, effect)
    return effect
end

-- Lighting System
function rendererPlus.addLight(x, y, radius, color, intensity)
    local light = {
        x = x,
        y = y,
        radius = radius,
        color = color or {1, 1, 1, 1},
        intensity = intensity or 1.0,
        active = true
    }
    
    table.insert(effects.lights, light)
    return light
end

-- Performance Monitoring
function rendererPlus.updatePerformance(dt)
    performance.frame_time = dt
    
    -- Garbage collection monitoring
    if love.timer.getTime() - performance.last_gc > 1.0 then
        local gc_before = collectgarbage("count")
        collectgarbage("collect")
        local gc_after = collectgarbage("count")
        performance.last_gc = love.timer.getTime()
        
        if gc_before - gc_after > 100 then
            print("[rendererPlus] GC collected: " .. string.format("%.2f", gc_before - gc_after) .. " KB")
        end
    end
end

-- Main Render Function
function rendererPlus.render(dt)
    local start_time = love.timer.getTime()
    
    -- Update performance tracking
    rendererPlus.updatePerformance(dt)
    
    -- Clear counters
    performance.draw_calls = 0
    performance.vertices_drawn = 0
    
    -- Store graphics state
    local original_color = {love.graphics.getColor()}
    local original_blend = love.graphics.getBlendMode()
    local original_shader = love.graphics.getShader()
    
    -- Render background layer
    for _, draw_data in ipairs(render_queue.background) do
        rendererPlus.processDrawData(draw_data)
    end
    
    -- Render world layer (sorted by depth)
    table.sort(render_queue.world, function(a, b)
        return (a.sort_y or a.y or 0) < (b.sort_y or b.y or 0)
    end)
    
    -- Debug: Log world queue size occasionally
    if math.random() < 0.01 then -- 1% chance each frame
        print("[rendererPlus] World queue size: " .. #render_queue.world)
    end
    
    for _, draw_data in ipairs(render_queue.world) do
        rendererPlus.processDrawData(draw_data)
    end
    
    -- Render effects
    rendererPlus.renderEffects(dt)
    
    -- Render UI layer
    for _, draw_data in ipairs(render_queue.ui) do
        rendererPlus.processDrawData(draw_data)
    end
    
    -- Post-processing effects
    for _, draw_data in ipairs(render_queue.post_process) do
        rendererPlus.processDrawData(draw_data)
    end
    
    -- Restore graphics state
    love.graphics.setColor(original_color)
    love.graphics.setBlendMode(original_blend)
    love.graphics.setShader(original_shader)
    
    -- Debug info
    if rendererPlus.debug_mode then
        rendererPlus.drawDebugInfo()
    end
end

function rendererPlus.processDrawData(draw_data)
    if not draw_data.active then return end
    
    -- Set color if specified
    if draw_data.color then
        love.graphics.setColor(draw_data.color)
    end
    
    -- Set blend mode if specified
    if draw_data.blend_mode then
        if draw_data.blend_mode[2] then
            love.graphics.setBlendMode(draw_data.blend_mode[1], draw_data.blend_mode[2])
        else
            love.graphics.setBlendMode(draw_data.blend_mode[1])
        end
    end
    
    -- Set shader if specified
    if draw_data.shader then
        love.graphics.setShader(draw_data.shader)
        -- Send shader parameters if available
        if draw_data.shader_params then
            for param_name, param_value in pairs(draw_data.shader_params) do
                if draw_data.shader:hasUniform(param_name) then
                    draw_data.shader:send(param_name, param_value)
                end
            end
        end
    end
    
    -- Handle different draw types
    if draw_data.type == "sprite" then
        rendererPlus.drawSprite(
            draw_data.texture_name,
            draw_data.x, draw_data.y,
            draw_data.rotation,
            draw_data.scale_x, draw_data.scale_y,
            draw_data.offset_x, draw_data.offset_y
        )
    elseif draw_data.type == "sprite_quad" then
        rendererPlus.drawSpriteWithQuad(
            draw_data.texture_name, draw_data.quad,
            draw_data.x, draw_data.y,
            draw_data.rotation,
            draw_data.scale_x, draw_data.scale_y,
            draw_data.offset_x, draw_data.offset_y
        )
    elseif draw_data.type == "particle_system" then
        if draw_data.particle_system then
            love.graphics.draw(draw_data.particle_system, draw_data.x, draw_data.y)
        end
    elseif draw_data.type == "shader_rect" then
        if draw_data.shader then
            love.graphics.setShader(draw_data.shader)
            love.graphics.rectangle("fill", draw_data.x, draw_data.y, draw_data.width, draw_data.height)
            love.graphics.setShader()
        end
    elseif draw_data.type == "shader_sprite" then
        if draw_data.shader then
            love.graphics.setShader(draw_data.shader)
            rendererPlus.drawSprite(
                draw_data.texture_name,
                draw_data.x, draw_data.y,
                draw_data.rotation,
                draw_data.scale_x, draw_data.scale_y,
                draw_data.offset_x, draw_data.offset_y
            )
            love.graphics.setShader()
        end
    elseif draw_data.type == "text" then
        local current_font = love.graphics.getFont()
        if draw_data.font then
            love.graphics.setFont(draw_data.font)
        end
        love.graphics.print(draw_data.text, draw_data.x, draw_data.y, draw_data.rotation, draw_data.scale, draw_data.scale)
        if draw_data.font then
            love.graphics.setFont(current_font)
        end
    elseif draw_data.type == "line" then
        if draw_data.width then
            love.graphics.setLineWidth(draw_data.width)
        end
        love.graphics.line(draw_data.points)
        if draw_data.width then
            love.graphics.setLineWidth(1)
        end
    elseif draw_data.type == "circle" then
        love.graphics.circle(draw_data.mode or "fill", draw_data.x, draw_data.y, draw_data.radius)
    elseif draw_data.type == "rectangle" then
        love.graphics.rectangle(draw_data.mode or "fill", draw_data.x, draw_data.y, draw_data.width, draw_data.height)
    elseif draw_data.type == "bullet_tracer" then
        -- Draw bullet tracer effect
        if draw_data.bullet_data then
            local bullet = draw_data.bullet_data
            local x, y = bullet.body:getPosition()
            
            -- Draw tracer line from previous position to current
            if bullet.prev_pos then
                love.graphics.setLineWidth(3)
                love.graphics.setColor(1, 1, 0.8, 0.8)  -- Yellow tracer
                love.graphics.line(bullet.prev_pos.x, bullet.prev_pos.y, x, y)
                
                -- Add glow effect
                love.graphics.setLineWidth(6)
                love.graphics.setColor(1, 1, 0.5, 0.3)
                love.graphics.line(bullet.prev_pos.x, bullet.prev_pos.y, x, y)
                love.graphics.setLineWidth(1)
            end
            
            -- Draw bullet point
            love.graphics.setColor(1, 1, 0.9, 1)
            love.graphics.circle("fill", x, y, 3)
        end
    elseif draw_data.type == "muzzle_flash" then
        -- Draw muzzle flash effect
        if draw_data.flash_data then
            local flash = draw_data.flash_data
            local alpha = flash.life / flash.max_life
            
            love.graphics.setBlendMode("add")
            love.graphics.setColor(flash.color[1], flash.color[2], flash.color[3], alpha * flash.intensity)
            love.graphics.circle("fill", flash.pos.x, flash.pos.y, flash.size * alpha)
            love.graphics.setBlendMode("alpha")
        end
    elseif draw_data.type == "gunpowder_particle" then
        -- Draw gunpowder particle
        if draw_data.particle_data then
            local particle = draw_data.particle_data
            local alpha = particle.life / particle.max_life
            
            love.graphics.push()
            love.graphics.translate(particle.pos.x, particle.pos.y)
            love.graphics.rotate(particle.rotation)
            
            love.graphics.setColor(particle.color[1], particle.color[2], particle.color[3], alpha)
            love.graphics.rectangle("fill", -particle.size/2, -particle.size/4, particle.size, particle.size/2)
            
            love.graphics.pop()
        end
    elseif draw_data.type == "shell_casing" then
        -- Draw shell casing
        if draw_data.shell_data then
            local shell = draw_data.shell_data
            local alpha = math.min(1, shell.life / shell.max_life)
            
            love.graphics.push()
            love.graphics.translate(shell.pos.x, shell.pos.y)
            love.graphics.rotate(shell.rotation)
            
            love.graphics.setColor(shell.color[1], shell.color[2], shell.color[3], alpha)
            love.graphics.rectangle("fill", -shell.size.width/2, -shell.size.height/2, 
                                  shell.size.width, shell.size.height)
            
            love.graphics.pop()
        end
    elseif draw_data.draw_func then
        -- Support for custom draw functions (for legacy compatibility)
        draw_data.draw_func()
    end
    
    performance.draw_calls = performance.draw_calls + 1
    
    -- Reset shader if it was set
    if draw_data.shader then
        love.graphics.setShader()
    end
end

function rendererPlus.renderEffects(dt)
    -- Update and render particle effects
    for i = #effects.particles, 1, -1 do
        local effect = effects.particles[i]
        if effect.active then
            -- Update effect
            local age = love.timer.getTime() - effect.created_time
            if age > (effect.params.lifetime or 5.0) then
                effect.active = false
                table.remove(effects.particles, i)
            else
                -- Render particle effect based on type
                rendererPlus.renderParticleEffect(effect, dt)
            end
        else
            table.remove(effects.particles, i)
        end
    end
    
    -- Render shader effects
    for i = #effects.shaders, 1, -1 do
        local effect = effects.shaders[i]
        if effect.active then
            local age = love.timer.getTime() - effect.created_time
            if age > (effect.params.lifetime or 5.0) then
                effect.active = false
                table.remove(effects.shaders, i)
            else
                love.graphics.setShader(effect.shader)
                love.graphics.rectangle("fill", effect.x, effect.y, effect.width, effect.height)
                love.graphics.setShader()
            end
        else
            table.remove(effects.shaders, i)
        end
    end
    
    -- Render lights
    for _, light in ipairs(effects.lights) do
        if light.active then
            love.graphics.setColor(light.color[1], light.color[2], light.color[3], light.intensity)
            love.graphics.setBlendMode("add")
            love.graphics.circle("fill", light.x, light.y, light.radius)
            love.graphics.setBlendMode("alpha")
        end
    end
end

function rendererPlus.renderParticleEffect(effect, dt)
    -- Placeholder for different particle effect types
    if effect.type == "explosion" then
        -- Render explosion particles
    elseif effect.type == "smoke" then
        -- Render smoke particles
    elseif effect.type == "fire" then
        -- Render fire particles
    elseif effect.type == "sparks" then
        -- Render spark particles
    end
end

-- Debug and Utility Functions

function rendererPlus.toggleDebug()
    rendererPlus.debug_mode = not rendererPlus.debug_mode
end

function rendererPlus.drawDebugInfo()
    love.graphics.setColor(1, 1, 0, 1)
    local debug_text = string.format(
        "NEW RENDERER DEBUG\nFPS: %.1f\nDraw Calls: %d\nFrame Time: %.3fms\nTextures Loaded: %d\nShaders Loaded: %d\nActive Particles: %d\nActive Lights: %d",
        love.timer.getFPS(),
        performance.draw_calls,
        performance.frame_time * 1000,
        #assets.textures,
        #assets.shaders,
        #effects.particles,
        #effects.lights
    )
    love.graphics.print(debug_text, 10, 10)
end

-- Cleanup function
function rendererPlus.cleanup()
    -- Clear all queues
    rendererPlus.clearQueue()
    
    -- Clear effects
    effects.particles = {}
    effects.shaders = {}
    effects.lights = {}
    
    -- Clear assets (textures will be garbage collected)
    assets.textures = {}
    assets.shaders = {}
    assets.particle_systems = {}
    assets.fonts = {}
    
    print("[rendererPlus] Cleanup complete")
end

-- Initialize the renderer
function rendererPlus.init()
    print("\n[rendererPlus] \n\nInitializing rendererPlus system...")
    if rendererPlus.debug_mode then print(" \n * rendererPlus.debug_mode is enabled\n") end
    rendererPlus.preloadAssets()
    print("[rendererPlus] Ready for advanced effects and high-performance rendering!")
end

return rendererPlus