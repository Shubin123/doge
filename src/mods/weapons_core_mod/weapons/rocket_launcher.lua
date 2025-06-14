-- Rocket Launcher weapon template
return {
    name = "Rocket Launcher",
    description = "Heavy explosive weapon",
    icon = "rocket_launcher_icon",
    
    -- Combat stats
    fire_rate = 1.43,   -- 0.7 shots per second
    damage = {min = 80, max = 100},
    spread = 0,         -- no spread, rockets fly straight
    
    -- Projectile properties
    projectile_type = "rocket",
    projectile_speed = 300,     -- initial speed
    projectile_count = 1,
    penetration = 0,
    
    -- Rocket-specific properties
    rocket_properties = {
        top_speed = 800,        -- rockets accelerate
        acceleration = 500,     -- speed increase per second
        accel_time = 0.6,      -- time to reach top speed
        explosion_radius = 100,
        explosion_damage = 50,  -- splash damage
        trail_enabled = true,
        exhaust_particles = true
    },
    
    -- Physics
    knockback = 120,    -- massive recoil
    recoil = 60,
    
    -- Visual properties
    barrel_length = 35,
    barrel_thickness = 10,
    ring_radius = 32,
    barrel_color = {0.4, 0.15, 0.1, 1},
    
    -- Effects
    muzzle_flash = {
        enabled = true,
        size = 1.5,
        duration = 0.15,
        color = {1, 0.8, 0.3, 1},
        cone_angle = 0.44,  -- 25 degrees
        cone_length = 220
    },
    
    shell_ejection = {
        enabled = false,    -- rockets don't eject shells
    },
    
    -- Audio
    sounds = {
        fire = "rocket_fire",
        reload = "rocket_reload",
        empty = "rocket_empty",
        explosion = "explosion"
    },
    
    -- Ammo
    magazine_size = 4,
    reload_time = 4.0,
    infinite_ammo = false,
    
    -- Requirements
    unlock_level = 12,
    cost = 2500
}