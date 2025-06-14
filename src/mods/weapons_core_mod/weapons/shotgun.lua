-- Shotgun weapon template
return {
    name = "Shotgun",
    description = "Devastating close-range weapon",
    icon = "shotgun_icon",
    
    -- Combat stats
    fire_rate = 0.83,   -- 1.2 shots per second
    damage = {min = 4, max = 6},  -- per pellet
    spread = 0.61,      -- 35 degrees
    
    -- Projectile properties
    projectile_type = "bullet",
    projectile_speed = 650,
    projectile_count = 8,  -- 8 pellets
    penetration = 0,
    
    -- Physics
    knockback = 85,
    recoil = 45,
    
    -- Visual properties
    barrel_length = 25,
    barrel_thickness = 6,
    ring_radius = 25,
    barrel_color = {0.2, 0.2, 0.2, 1},
    
    -- Effects
    muzzle_flash = {
        enabled = true,
        size = 1.2,
        duration = 0.12,
        color = {1, 0.9, 0.5, 1},
        cone_angle = 0.79,  -- 45 degrees wide cone
        cone_length = 180
    },
    
    shell_ejection = {
        enabled = true,
        type = "shotgun",
        velocity = {x = -120, y = -180},
        spin = 8
    },
    
    -- Audio
    sounds = {
        fire = "shotgun_fire",
        reload = "shotgun_reload",
        empty = "shotgun_empty",
        pump = "shotgun_pump"
    },
    
    -- Ammo
    magazine_size = 6,
    reload_time = 3.0,  -- reload one shell at a time
    infinite_ammo = false,
    
    -- Requirements
    unlock_level = 5,
    cost = 800
}