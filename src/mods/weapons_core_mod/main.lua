-- Weapons Core Mod - Main Entry Point
-- Provides sophisticated weapon system with advanced aiming, effects, and realism features
-- Migrated from legacy gun.lua with all advanced features preserved

local weaponsCoremod = {}

-- Mod state
local loaded_weapons = {}
local current_weapon = nil
local weapon_templates = {}
local mod_config = {}
local weapon_cooldowns = {}
local last_aim_direction = {x = 1, y = 0}  -- Track aiming direction for weapon rendering
local debug_mode = false  -- Start in normal mode
local mouse_pressed = false  -- Track mouse state for full auto
local mod_time = 0  -- Internal time tracking

-- API reference
local api = nil

-- Advanced aiming and camera integration
local camera_zoom = 1.0
local screen_center = {x = 0, y = 0}

-- Core weapon parameters (enhanced from legacy system)
local WEAPON_DEFAULTS = {
    fire_rate = 0.5,
    damage = 10,
    spread = 0,
    projectile_type = "bullet",
    projectile_speed = 1000,
    projectile_count = 1,
    ring_radius = 25,
    barrel_length = 20,
    barrel_thickness = 4,
    reload_time = 0,
    magazine_size = -1,  -- -1 = infinite
    current_ammo = -1,
    is_full_auto = false,
    shell_type = nil,  -- "pistol", "shotgun", "rifle", "smg", or nil
    
    -- Advanced muzzle flash parameters
    muzzle_flash = {
        duration = 0.08,
        cone_angle = 0.61,  -- ~35 degrees in radians
        cone_length = 150,
        brightness = 1.0,
        color = {1, 0.9, 0.7}
    },
    
    -- Particle effect parameters (gunpowder confetti)
    particles = {
        count = 8,
        colors = {{1, 0.8, 0.3}, {1, 0.5, 0.2}, {0.8, 0.3, 0.1}},
        lifespan = 0.3,
        speed = {min = 120, max = 250},
        size = {min = 1, max = 3},
        spread_angle = 0.44  -- ~25 degrees in radians
    },
    
    -- Knockback and screen shake parameters
    knockback = {
        force = 50,
        shake_intensity = 2,
        shake_duration = 0.1
    }
}

-- Initialize the mod
function weaponsCoremod.init(mod_api)
    print("[WEAPONS_CORE_MOD] Initializing Weapons Core System v1.0.0")
    
    api = mod_api
    
    -- Load configuration
    mod_config = {
        enable_weapon_switching = true,
        enable_custom_weapons = true,
        enable_networking = true,
        default_weapon = "pistol"
    }
    
    -- Register built-in weapon templates
    weaponsCoremod.registerBuiltinWeapons()
    
    -- Register input handlers
    api.input.registerKeyHandler("1", function() weaponsCoremod.switchWeapon("pistol") end)
    api.input.registerKeyHandler("2", function() weaponsCoremod.switchWeapon("smg") end)
    api.input.registerKeyHandler("3", function() weaponsCoremod.switchWeapon("shotgun") end)
    api.input.registerKeyHandler("4", function() weaponsCoremod.switchWeapon("assault_rifle") end)
    api.input.registerKeyHandler("5", function() weaponsCoremod.switchWeapon("rocket_launcher") end)
    
    -- Register mouse handlers for shooting
    api.input.registerMouseHandler(1, weaponsCoremod.handleShoot)
    
    -- Register mouse press/release handlers for full auto
    if api.input.registerMousePressHandler then
        api.input.registerMousePressHandler(1, function(x, y) 
            mouse_pressed = true 
            weaponsCoremod.handleShoot(x, y, 1)
        end)
        api.input.registerMouseReleaseHandler(1, function(x, y) 
            mouse_pressed = false 
        end)
    end
    
    -- Register network handler
    if mod_config.enable_networking then
        api.network.registerMessageHandler("weapons_core_mod", weaponsCoremod.handleNetworkMessage)
    end
    
    -- Equip default weapon
    weaponsCoremod.equipWeapon(mod_config.default_weapon)
    
    print("[WEAPONS_CORE_MOD] Initialization complete! Use number keys 1-5 to switch weapons")
end

-- Register built-in weapon templates (enhanced from legacy system)
function weaponsCoremod.registerBuiltinWeapons()
    -- Pistol - Based on legacy gun preset
    weaponsCoremod.registerWeapon("pistol", {
        name = "Pistol",
        fire_rate = 0.25,  -- 4 shots per second
        damage = 1,
        spread = 0,
        projectile_type = "bullet",
        projectile_speed = 700,
        ring_radius = 25,
        barrel_length = 18,
        barrel_thickness = 3,
        projectile_radius = 3,
        projectile_lifetime = 4,
        projectile_count = 1,
        shell_type = "pistol",
        muzzle_flash = {
            duration = 0.2,
            cone_angle = 0.35,  -- 20 degrees
            cone_length = 120,
            brightness = 0.8,
            color = {1, 0.9, 0.7}
        },
        particles = {
            count = 5,
            colors = {{1, 0.8, 0.3}, {1, 0.6, 0.2}},
            lifespan = 0.25,
            speed = {min = 100, max = 180},
            size = {min = 1, max = 2},
            spread_angle = 0.26  -- 15 degrees
        },
        knockback = {
            force = 35,
            shake_intensity = 1.5,
            shake_duration = 0.08
        }
    })
    
    -- SMG - Based on legacy gun preset
    weaponsCoremod.registerWeapon("smg", {
        name = "SMG",
        fire_rate = 0.125,  -- 8 shots per second
        damage = 0.6,
        spread = 0.087,  -- 5 degrees
        projectile_type = "bullet",
        projectile_speed = 500,
        ring_radius = 22,
        barrel_length = 15,
        barrel_thickness = 3,
        projectile_radius = 2,
        projectile_lifetime = 3,
        projectile_count = 1,
        shell_type = "smg",
        is_full_auto = true,  -- Full auto firing
        muzzle_flash = {
            duration = 0.05,
            cone_angle = 0.31,  -- 18 degrees
            cone_length = 100,
            brightness = 0.7,
            color = {1, 0.85, 0.6}
        },
        particles = {
            count = 4,
            colors = {{1, 0.7, 0.3}, {0.9, 0.5, 0.2}},
            lifespan = 0.2,
            speed = {min = 80, max = 150},
            size = {min = 0.8, max = 1.5},
            spread_angle = 0.21  -- 12 degrees
        },
        knockback = {
            force = 20,
            shake_intensity = 1.0,
            shake_duration = 0.06
        }
    })
    
    -- Shotgun - Based on legacy gun preset
    weaponsCoremod.registerWeapon("shotgun", {
        name = "Shotgun",
        fire_rate = 0.83,  -- 1.2 shots per second
        damage = 0.6,
        spread = 0.61,  -- 35 degrees
        projectile_type = "bullet",
        projectile_speed = 650,
        ring_radius = 25,
        barrel_length = 25,
        barrel_thickness = 6,
        projectile_radius = 1.5,
        projectile_lifetime = 2.0,
        projectile_count = 8,
        shell_type = "shotgun",
        muzzle_flash = {
            duration = 0.12,
            cone_angle = 0.79,  -- 45 degrees wide cone
            cone_length = 180,
            brightness = 1.2,
            color = {1, 0.9, 0.5}
        },
        particles = {
            count = 15,
            colors = {{1, 0.8, 0.2}, {1, 0.6, 0.1}, {0.9, 0.4, 0.1}},
            lifespan = 0.4,
            speed = {min = 150, max = 300},
            size = {min = 1.5, max = 4},
            spread_angle = 0.70  -- 40 degrees
        },
        knockback = {
            force = 85,
            shake_intensity = 4.0,
            shake_duration = 0.15
        }
    })
    
    -- Assault Rifle - Based on legacy gun preset with full auto
    weaponsCoremod.registerWeapon("assault_rifle", {
        name = "Assault Rifle",
        fire_rate = 0.083,  -- 12 shots per second
        damage = 1.0,
        spread = 0.052,  -- 3 degrees
        projectile_type = "bullet",
        projectile_speed = 800,
        ring_radius = 28,
        barrel_length = 22,
        barrel_thickness = 4,
        projectile_radius = 3,
        projectile_lifetime = 5,
        projectile_count = 1,
        shell_type = "rifle",
        is_full_auto = true,  -- Full auto mode
        muzzle_flash = {
            duration = 0.04,
            cone_angle = 0.26,  -- 15 degrees narrow cone
            cone_length = 160,
            brightness = 0.9,
            color = {1, 0.95, 0.8}
        },
        particles = {
            count = 6,
            colors = {{1, 0.9, 0.4}, {1, 0.7, 0.3}, {0.9, 0.5, 0.2}},
            lifespan = 0.3,
            speed = {min = 120, max = 220},
            size = {min = 1, max = 2.5},
            spread_angle = 0.17  -- 10 degrees
        },
        knockback = {
            force = 42,
            shake_intensity = 2.0,
            shake_duration = 0.08
        }
    })
    
    -- Rocket Launcher - Based on legacy gun preset
    weaponsCoremod.registerWeapon("rocket_launcher", {
        name = "Rocket Launcher",
        fire_rate = 1.43,  -- 0.7 shots per second
        damage = 8,
        spread = 0,
        projectile_type = "rocket",
        projectile_speed = 300,
        ring_radius = 32,
        barrel_length = 35,
        barrel_thickness = 10,
        projectile_radius = 10,
        top_speed = 800,  -- Rocket acceleration
        accel_time = 0.6,
        projectile_count = 1,
        shell_type = nil,  -- No shell ejection for rockets
        muzzle_flash = {
            duration = 0.15,
            cone_angle = 0.44,  -- 25 degrees
            cone_length = 220,
            brightness = 1.5,
            color = {1, 0.8, 0.3}
        },
        particles = {
            count = 20,
            colors = {{1, 0.9, 0.2}, {1, 0.6, 0.1}, {0.8, 0.3, 0.1}, {1, 0.4, 0.0}},
            lifespan = 0.6,
            speed = {min = 200, max = 400},
            size = {min = 2, max = 6},
            spread_angle = 0.52  -- 30 degrees
        },
        knockback = {
            force = 120,
            shake_intensity = 5.0,
            shake_duration = 0.2
        },
        explosion_radius = 100
    })
end

-- Register a weapon template
function weaponsCoremod.registerWeapon(id, template)
    -- Merge with defaults
    local weapon = {}
    for k, v in pairs(WEAPON_DEFAULTS) do
        weapon[k] = v
    end
    for k, v in pairs(template) do
        weapon[k] = v
    end
    
    weapon.id = id
    weapon_templates[id] = weapon
    
    api.utils.log("Registered weapon: " .. id, "weapons_core_mod")
end

-- Switch to a weapon
function weaponsCoremod.switchWeapon(weapon_id)
    if not mod_config.enable_weapon_switching then
        return
    end
    
    if weapon_templates[weapon_id] then
        weaponsCoremod.equipWeapon(weapon_id)
        
        -- Sync weapon switch in multiplayer
        if mod_config.enable_networking then
            api.network.sendToAll({
                action = "weapon_switch",
                weapon_id = weapon_id
            }, "weapons_core_mod")
        end
    else
        api.utils.log("Unknown weapon: " .. weapon_id, "weapons_core_mod")
    end
end

-- Equip a weapon
function weaponsCoremod.equipWeapon(weapon_id)
    local template = weapon_templates[weapon_id]
    if not template then
        return
    end
    
    current_weapon = {
        id = weapon_id,
        template = template,
        ammo = template.magazine_size > 0 and template.magazine_size or -1,
        reload_timer = 0
    }
    
    weapon_cooldowns[weapon_id] = weapon_cooldowns[weapon_id] or 0
    
    api.utils.log("Equipped weapon: " .. template.name, "weapons_core_mod")
end

-- Handle shooting (enhanced from legacy system)
function weaponsCoremod.handleShoot(x, y, button)
    if button ~= 1 or not current_weapon then
        return
    end
    
    local template = current_weapon.template
    local cooldown = weapon_cooldowns[current_weapon.id] or 0
    
    -- Check cooldown
    if cooldown > 0 then
        return
    end
    
    -- Check ammo
    if current_weapon.ammo == 0 then
        -- Need to reload
        return
    end
    
    -- Get player position
    local px, py = api.game.getPlayerPosition()
    
    -- Use current aiming direction (already updated in Gun:update)
    local dx = last_aim_direction.x
    local dy = last_aim_direction.y
    
    -- Calculate spawn position on ring around player
    local spawn_x = px + dx * template.ring_radius
    local spawn_y = py + dy * template.ring_radius
    
    -- Calculate barrel tip position (where particles should spawn from)
    local barrel_tip_x = spawn_x + dx * template.barrel_length
    local barrel_tip_y = spawn_y + dy * template.barrel_length
    
    -- Create muzzle flash effect with gun-specific parameters
    weaponsCoremod.createMuzzleFlash(barrel_tip_x, barrel_tip_y, dx, dy, template.muzzle_flash)
    
    -- Create particle effects (gunpowder confetti) from barrel tip
    weaponsCoremod.createParticleEffect(barrel_tip_x, barrel_tip_y, dx, dy, template.particles)
    
    -- Apply knockback to player (opposite direction of shot)
    weaponsCoremod.applyPlayerKnockback(-dx, -dy, template.knockback.force)
    
    -- Apply screen shake if camera module supports it
    weaponsCoremod.applyScreenShake(template.knockback.shake_intensity, template.knockback.shake_duration)
    
    -- Create shell ejection for appropriate weapons
    if template.shell_type then
        weaponsCoremod.createShellEjection(spawn_x, spawn_y, dx, dy, template.shell_type)
    end
    
    -- Fire projectiles with sophisticated spread and speed variation
    for i = 1, template.projectile_count do
        local spread_angle = 0
        if template.projectile_count > 1 then
            -- For shotguns, use random spread within the cone for realistic behavior
            local max_spread = template.spread
            spread_angle = (math.random() - 0.5) * max_spread
        end
        
        -- Apply spread to direction
        local cos_a = math.cos(spread_angle)
        local sin_a = math.sin(spread_angle)
        local proj_dx = dx * cos_a - dy * sin_a
        local proj_dy = dx * sin_a + dy * cos_a
        
        -- Add slight speed variation for realism (±10%)
        local speed_variation = template.projectile_speed * (0.9 + math.random() * 0.2)
        
        -- Get client ID for multiplayer identification
        local client_id = nil
        if api.network and api.network.getLocalClientId then
            client_id = api.network.getLocalClientId()
        elseif api.game and api.game.getMultiplayerMode then
            local mp_mode = api.game.getMultiplayerMode()
            if mp_mode then
                client_id = "client_" .. mp_mode
            end
        end
        
        -- Enhanced projectile parameters
        local projectile_params = {
            speed = speed_variation,
            damage = template.damage,
            radius = template.projectile_radius or 3,
            lifetime = template.projectile_lifetime or 5.0,
            owner = "player",
            owner_id = "player",  -- Add owner_id for PvP damage filtering
            owner_client_id = client_id,  -- Add client ID for multiplayer PvP
            weapon_id = current_weapon.id,
            trail_enabled = true,
            trail_color = {1, 1, 0.8, 0.8}
        }
        
        -- Spawn projectile from spawn position (ring edge)
        local projectile = weaponsCoremod.spawnProjectile(spawn_x, spawn_y, proj_dx, proj_dy, template, projectile_params)
        if not projectile then
            api.utils.log("Failed to spawn projectile", "weapons_core_mod")
        end
    end
    
    -- Set cooldown
    weapon_cooldowns[current_weapon.id] = template.fire_rate
    
    -- Use ammo
    if current_weapon.ammo > 0 then
        current_weapon.ammo = current_weapon.ammo - 1
    end
    
    -- Sync shot in multiplayer
    if mod_config.enable_networking then
        api.network.sendToAll({
            action = "weapon_fired",
            weapon_id = current_weapon.id,
            x = spawn_x,
            y = spawn_y,
            dx = dx,
            dy = dy,
            barrel_tip_x = barrel_tip_x,
            barrel_tip_y = barrel_tip_y
        }, "weapons_core_mod")
    end
end

-- Spawn a projectile using projectiles_mod (enhanced)
function weaponsCoremod.spawnProjectile(x, y, dx, dy, template, projectile_params)
    -- Get projectiles mod from mod system using api
    local projectiles_mod = api.mod_system and api.mod_system.getMod and api.mod_system.getMod("projectiles_mod")
    if projectiles_mod and projectiles_mod.instance and projectiles_mod.instance.public and projectiles_mod.instance.public.spawnProjectile then
        return projectiles_mod.instance.public.spawnProjectile(template.projectile_type, x, y, dx, dy, projectile_params)
    else
        api.utils.log("Projectiles mod not available", "weapons_core_mod")
        return nil
    end
end

-- Create sophisticated muzzle flash effect (from legacy system)
function weaponsCoremod.createMuzzleFlash(x, y, dx, dy, params)
    -- Get combat effects mod from mod system
    local effects_mod = api.mod_system and api.mod_system.getMod and api.mod_system.getMod("combat_effects_mod")
    if effects_mod and effects_mod.instance and effects_mod.instance.public and effects_mod.instance.public.createMuzzleFlash then
        effects_mod.instance.public.createMuzzleFlash(x, y, {x = dx, y = dy}, {
            duration = params.duration,
            cone_angle = params.cone_angle,
            cone_length = params.cone_length,
            intensity = params.brightness,
            color = params.color
        })
    else
        -- Fallback to direct renderer call with enhanced parameters
        api.renderer.addParticleEffect("muzzle_flash", x, y, "flash", {
            direction = {dx, dy},
            duration = params.duration,
            cone_angle = params.cone_angle,
            cone_length = params.cone_length,
            intensity = params.brightness,
            color = params.color
        })
    end
end

-- Create sophisticated particle effect (gunpowder confetti from legacy system)
function weaponsCoremod.createParticleEffect(x, y, dx, dy, params)
    -- Get combat effects mod from mod system
    local effects_mod = api.mod_system and api.mod_system.getMod and api.mod_system.getMod("combat_effects_mod")
    if effects_mod and effects_mod.instance and effects_mod.instance.public and effects_mod.instance.public.createParticleEffect then
        effects_mod.instance.public.createParticleEffect(x, y, {x = dx, y = dy}, params)
    else
        -- Fallback to direct renderer call
        api.renderer.addParticleEffect("gunpowder_particles", x, y, "particles", {
            direction = {dx, dy},
            count = params.count,
            colors = params.colors,
            lifespan = params.lifespan,
            speed = params.speed,
            size = params.size,
            spread_angle = params.spread_angle
        })
    end
end

-- Apply player knockback (from legacy system)
function weaponsCoremod.applyPlayerKnockback(dx, dy, force)
    -- Try to get player physics integration
    if api.game.applyPlayerKnockback then
        api.game.applyPlayerKnockback(dx, dy, force)
    else
        -- Fallback - log for debugging
        api.utils.log("Player knockback: " .. force .. " in direction (" .. dx .. ", " .. dy .. ")", "weapons_core_mod")
    end
end

-- Apply screen shake (from legacy system)
function weaponsCoremod.applyScreenShake(intensity, duration)
    -- Try to get camera shake integration
    if api.game.applyCameraShake then
        api.game.applyCameraShake(intensity, duration)
    elseif api.camera and api.camera.shake then
        api.camera.shake(intensity, duration)
    else
        -- Fallback - log for debugging
        api.utils.log("Screen shake: " .. intensity .. " for " .. duration .. "s", "weapons_core_mod")
    end
end

-- Create shell ejection effect (from legacy system)
function weaponsCoremod.createShellEjection(x, y, dx, dy, shell_type)
    -- Get combat effects mod from mod system
    local effects_mod = api.mod_system and api.mod_system.getMod and api.mod_system.getMod("combat_effects_mod")
    if effects_mod and effects_mod.instance and effects_mod.instance.public and effects_mod.instance.public.createShellEjection then
        effects_mod.instance.public.createShellEjection(x, y, {x = dx, y = dy}, shell_type)
    else
        -- Fallback to direct renderer call
        api.renderer.addParticleEffect("shell_ejection", x, y, "shell", {
            direction = {dx, dy},
            shell_type = shell_type
        })
    end
end

-- Update function
function weaponsCoremod.update(dt)
    mod_time = mod_time + dt
    
    -- Update weapon cooldowns
    for weapon_id, cooldown in pairs(weapon_cooldowns) do
        if cooldown > 0 then
            weapon_cooldowns[weapon_id] = math.max(0, cooldown - dt)
        end
    end
    
    -- Update reload timer
    if current_weapon and current_weapon.reload_timer > 0 then
        current_weapon.reload_timer = current_weapon.reload_timer - dt
        if current_weapon.reload_timer <= 0 then
            -- Reload complete
            current_weapon.ammo = current_weapon.template.magazine_size
            api.utils.log("Reload complete", "weapons_core_mod")
        end
    end
    
    -- Update screen center for camera integration
    if api.input.getScreenDimensions then
        local width, height = api.input.getScreenDimensions()
        screen_center.x = width / 2
        screen_center.y = height / 2
    end
    
    -- Update camera zoom if available
    if api.game.getCameraZoom then
        camera_zoom = api.game.getCameraZoom()
    end
    
    -- Update aiming direction continuously
    weaponsCoremod.updateAiming()
    
    -- Handle full auto firing
    if mouse_pressed and current_weapon and current_weapon.template.is_full_auto then
        local mx, my = api.input.getMousePosition()
        weaponsCoremod.handleShoot(mx, my, 1)
    end
    
    -- Render current weapon if equipped
    if current_weapon then
        weaponsCoremod.renderWeapon()
    end
end

-- Draw function (for UI elements)
function weaponsCoremod.draw()
    if not current_weapon then
        return
    end
    
    -- Add weapon info to UI layer
    local y = 20
    api.renderer.addToQueue("ui", {
        type = "text",
        text = "Weapon: " .. current_weapon.template.name,
        x = 10, y = y,
        color = {1, 1, 1, 1}
    })
    
    if current_weapon.ammo >= 0 then
        y = y + 20
        api.renderer.addToQueue("ui", {
            type = "text",
            text = "Ammo: " .. current_weapon.ammo .. "/" .. current_weapon.template.magazine_size,
            x = 10, y = y,
            color = {1, 1, 1, 1}
        })
    end
    
    -- Note: Crosshair/aiming ring not implemented yet - needs mouse position from input system
end

-- Update aiming direction continuously (enhanced from legacy system)
function weaponsCoremod.updateAiming()
    -- Get current mouse position
    local mx, my = api.input.getMousePosition()
    
    -- Get screen dimensions
    local screen_width, screen_height = 800, 600  -- defaults
    if api.input.getScreenDimensions then
        screen_width, screen_height = api.input.getScreenDimensions()
    end
    
    -- Convert screen coordinates to world coordinates (legacy camera system)
    local zoom = camera_zoom
    
    -- Calculate offset from screen center to mouse
    local dx = (mx - screen_width/2) / zoom
    local dy = (my - screen_height/2) / zoom
    
    -- Get player world position
    local px, py = api.game.getPlayerPosition()
    
    -- Calculate world mouse position
    local world_mouse_x = px + dx
    local world_mouse_y = py + dy
    
    -- Calculate direction from player to mouse
    local dir_x = world_mouse_x - px
    local dir_y = world_mouse_y - py
    
    -- Check for zero vector to avoid NaN
    if dir_x == 0 and dir_y == 0 then
        return -- Keep previous direction
    end
    
    local length = math.sqrt(dir_x * dir_x + dir_y * dir_y)
    if length > 0 then
        dir_x = dir_x / length
        dir_y = dir_y / length
    else
        dir_x, dir_y = 1, 0  -- default direction
    end
    
    -- Store aiming direction for weapon rendering
    last_aim_direction.x = dir_x
    last_aim_direction.y = dir_y
end

-- Render current weapon (barrel and aiming ring)
function weaponsCoremod.renderWeapon()
    if not current_weapon then return end
    
    local template = current_weapon.template
    local px, py = api.game.getPlayerPosition()
    
    -- Use stored aiming direction
    local dx = last_aim_direction.x
    local dy = last_aim_direction.y
    
    -- Debug: Log that weapon is being rendered
    -- api.utils.log("Rendering weapon: " .. template.name .. " at " .. px .. "," .. py, "weapons_core_mod")
    
    -- Draw aiming ring around player
    local ring_radius = template.ring_radius or 25
    local ring_color = debug_mode and {1, 0, 0, 1} or {1, 1, 1, 0.3}  -- Red in debug, white semi-transparent normally
    local ring_size = debug_mode and 50 or ring_radius  -- Bigger in debug mode
    
    api.renderer.addToQueue("world", {
        type = "circle",
        x = px,
        y = py,
        radius = ring_size,
        color = ring_color,
        mode = "line",
        active = true
    })
    
    -- Calculate barrel position on the ring
    local actual_ring_radius = template.ring_radius or 25
    local barrel_start_x = px + dx * actual_ring_radius
    local barrel_start_y = py + dy * actual_ring_radius
    
    -- Calculate barrel end position
    local barrel_length = template.barrel_length or 20
    local barrel_end_x = barrel_start_x + dx * barrel_length
    local barrel_end_y = barrel_start_y + dy * barrel_length
    
    -- Draw barrel as a thick line
    local barrel_color = debug_mode and {0, 1, 0, 1} or {0.6, 0.6, 0.6, 1}  -- Green in debug, gray normally
    local barrel_width = debug_mode and 10 or (template.barrel_thickness or 4)  -- Thicker in debug mode
    
    api.renderer.addToQueue("world", {
        type = "line",
        points = {barrel_start_x, barrel_start_y, barrel_end_x, barrel_end_y},
        color = barrel_color,
        width = barrel_width,
        active = true
    })
    
    -- Draw barrel base connection circle
    api.renderer.addToQueue("world", {
        type = "circle",
        x = barrel_start_x,
        y = barrel_start_y,
        radius = (template.barrel_thickness or 4) / 2,
        color = {0.8, 0.8, 0.8, 1},
        mode = "fill",
        active = true
    })
end

-- Toggle debug mode for weapon rendering
function weaponsCoremod.toggleDebug()
    debug_mode = not debug_mode
    local mode_text = debug_mode and "enabled" or "disabled"
    api.utils.log("Weapon debug mode " .. mode_text, "weapons_core_mod")
    return debug_mode
end

-- Network message handler
function weaponsCoremod.handleNetworkMessage(data)
    if data.action == "weapon_switch" then
        -- Another player switched weapons
        -- TODO: Track other players' weapons
    elseif data.action == "weapon_fired" then
        -- Another player fired their weapon
        -- Create effects at their position
        if data.weapon_id and weapon_templates[data.weapon_id] then
            local template = weapon_templates[data.weapon_id]
            if template.muzzle_flash then
                weaponsCoremod.createMuzzleFlash(data.x, data.y, data.dx, data.dy, template.muzzle_flash_size)
            end
        end
    end
end

-- Export public API
weaponsCoremod.public = {
    registerWeapon = weaponsCoremod.registerWeapon,
    getWeaponTemplate = function(id) return weapon_templates[id] end,
    getCurrentWeapon = function() return current_weapon end,
    toggleDebug = weaponsCoremod.toggleDebug
}

return weaponsCoremod