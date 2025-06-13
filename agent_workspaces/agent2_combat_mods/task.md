# Agent 2 Task: Combat & Projectile Mods

## Your Mission
Convert all hardcoded combat systems (weapons, bullets, explosions) into modular components that can be loaded as mods.

## Step-by-Step Plan:

1. **Analyze Current Combat Systems**
   - Study src/entities/gun.lua - weapon systems
   - Study src/entities/bullet.lua - projectile behavior
   - Study src/entities/rocket.lua - explosive projectiles
   - Understand how these interact with physics and rendering

2. **Design Mod Structure**
   Create three core mods:
   - weapons_core_mod: Base weapon functionality
   - projectiles_mod: Bullet and projectile systems
   - combat_effects_mod: Muzzle flash, explosions, hit effects

3. **Create Weapon Template System**
   ```lua
   -- Example weapon template
   {
     id = "pistol",
     damage = 10,
     firerate = 0.3,
     muzzle_flash = true,
     projectile_type = "bullet",
     sound = "pistol_fire"
   }
   ```

4. **Implement Projectile Physics**
   - Use mod_system physics API
   - Add tracer rendering effects
   - Implement collision detection
   - Network synchronization for multiplayer

5. **Migrate Each Component**
   - Start with gun.lua → weapons_core_mod
   - Then bullet.lua → projectiles_mod
   - Finally effects → combat_effects_mod

## Key Files to Reference:
- src/entities/gun.lua
- src/entities/bullet.lua
- src/entities/rocket.lua
- src/engine/mod_system.lua (for mod API)
- mods/glowing_tree_mod/ (example mod structure)

## Mod Structure Template:
```
mods/weapons_core_mod/
├── mod_info.json
├── main.lua
├── weapons/
│   ├── pistol.lua
│   ├── rifle.lua
│   └── shotgun.lua
└── effects/
    └── muzzle_flash.lua
```

## Success Criteria:
- All weapon functionality works through mods
- Game combat feels identical to legacy version
- Multiplayer weapon sync works properly
- Individual weapon mods can be disabled without crashes
- Performance maintained

## Testing Checklist:
- [ ] All weapons fire correctly
- [ ] Projectiles have proper physics
- [ ] Hit detection works
- [ ] Visual effects render properly
- [ ] Multiplayer combat syncs correctly
- [ ] Mod can be disabled cleanly

Note: Wait for Agent 1 to complete renderer transition before final testing!
