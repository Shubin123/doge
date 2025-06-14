-- SMG weapon template
return {
    name = "SMG",
    description = "High rate of fire submachine gun",
    icon = "smg_icon",
    
    -- Combat stats
    fire_rate = 0.125,  -- 8 shots per second
    damage = {min = 5, max = 7},
    spread = 0.087,     -- 5 degrees
    
    -- Projectile properties
    projectile_type = "bullet",
    projectile_speed = 500,
    projectile_count = 1,
    penetration = 0,
    
    -- Physics
    knockback = 20,
    recoil = 8,
    
    -- Visual properties
    barrel_length = 15,
    barrel_thickness = 3,
    ring_radius = 22,
    barrel_color = {0.25, 0.25, 0.25, 1},
    
    -- Effects
    muzzle_flash = {
        enabled = true,
        size = 0.7,
        duration = 0.05,
        color = {1, 0.85, 0.6, 1}
    },
    
    shell_ejection = {
        enabled = true,
        type = "smg",
        velocity = {x = -80, y = -120},
        spin = 12
    },
    
    -- Audio
    sounds = {
        fire = "smg_fire",
        reload = "smg_reload",
        empty = "smg_empty"
    },
    
    -- Ammo
    magazine_size = 30,
    reload_time = 2.0,
    infinite_ammo = false,
    is_full_auto = true,
    
    -- Requirements
    unlock_level = 3,
    cost = 500
}