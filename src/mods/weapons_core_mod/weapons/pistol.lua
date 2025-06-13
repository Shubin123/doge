-- Pistol weapon template
return {
    name = "Pistol",
    description = "Standard semi-automatic pistol",
    icon = "pistol_icon",
    
    -- Combat stats
    fire_rate = 0.3,
    damage = {min = 8, max = 12},
    spread = 0.02,
    
    -- Projectile properties
    projectile_type = "bullet",
    projectile_speed = 800,
    projectile_count = 1,
    penetration = 0,
    
    -- Physics
    knockback = 50,
    recoil = 15,
    
    -- Visual properties
    barrel_length = 20,
    barrel_thickness = 3,
    ring_radius = 25,
    barrel_color = {0.3, 0.3, 0.3, 1},
    
    -- Effects
    muzzle_flash = {
        enabled = true,
        size = 0.8,
        duration = 0.1,
        color = {1, 0.9, 0.7, 1}
    },
    
    shell_ejection = {
        enabled = true,
        type = "small",
        velocity = {x = -100, y = -150},
        spin = 10
    },
    
    -- Audio
    sounds = {
        fire = "pistol_fire",
        reload = "pistol_reload",
        empty = "pistol_empty"
    },
    
    -- Ammo
    magazine_size = 12,
    reload_time = 1.5,
    infinite_ammo = false,
    
    -- Requirements
    unlock_level = 0,
    cost = 0
}