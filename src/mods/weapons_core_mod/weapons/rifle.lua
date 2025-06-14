-- Assault Rifle weapon template
return {
    name = "Assault Rifle",
    description = "Versatile full-auto assault rifle",
    icon = "rifle_icon",
    
    -- Combat stats
    fire_rate = 0.083,  -- 12 shots per second
    damage = {min = 9, max = 11},
    spread = 0.052,     -- 3 degrees
    
    -- Projectile properties
    projectile_type = "bullet",
    projectile_speed = 800,
    projectile_count = 1,
    penetration = 1,    -- can hit through 1 enemy
    
    -- Physics
    knockback = 42,
    recoil = 20,
    
    -- Visual properties
    barrel_length = 22,
    barrel_thickness = 4,
    ring_radius = 28,
    barrel_color = {0.15, 0.15, 0.15, 1},
    
    -- Effects
    muzzle_flash = {
        enabled = true,
        size = 0.9,
        duration = 0.04,
        color = {1, 0.95, 0.8, 1},
        cone_angle = 0.26,  -- 15 degrees narrow cone
        cone_length = 160
    },
    
    shell_ejection = {
        enabled = true,
        type = "rifle",
        velocity = {x = -110, y = -160},
        spin = 11
    },
    
    -- Audio
    sounds = {
        fire = "rifle_fire",
        reload = "rifle_reload",
        empty = "rifle_empty"
    },
    
    -- Ammo
    magazine_size = 30,
    reload_time = 2.5,
    infinite_ammo = false,
    is_full_auto = true,
    
    -- Requirements
    unlock_level = 8,
    cost = 1200
}