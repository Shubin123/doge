# Agent 3 Task: Enemy & Boss AI Mods

## Your Mission
Modularize all NPC entities (enemies and bosses) into a flexible mod system with AI behaviors and state machines.

## Step-by-Step Plan:

1. **Analyze Current Enemy Systems**
   - Study src/entities/enemy.lua - basic enemy AI and behavior
   - Study src/entities/boss.lua - complex bear boss mechanics
   - Understand projectile firing, movement patterns, health systems

2. **Design Mod Structure**
   Create core mods:
   - basic_enemies_mod: Standard enemy types
   - bear_boss_mod: Bear boss with lasers and ground pounds
   - ai_behaviors_mod: Reusable AI patterns

3. **Create Entity Template System**
   ```lua
   -- Example enemy template
   {
     id = "grunt_enemy",
     health = 50,
     speed = 100,
     ai_type = "patrol",
     attack_pattern = "burst_fire",
     drop_items = {"ammo", "health"},
     sprite = "enemy_grunt"
   }
   ```

4. **Implement AI State Machines**
   - Idle, patrol, chase, attack states
   - Transition conditions
   - Network sync for multiplayer
   - Use mod_system's state machine API

5. **Bear Boss Special Features**
   - Laser attack system
   - Ground pound mechanics
   - Phase transitions
   - Complex animation states

## Key Files to Reference:
- src/entities/enemy.lua
- src/entities/boss.lua
- src/engine/mod_system.lua (state machine API)
- mods/glowing_tree_mod/ (entity template example)

## Mod Structure Template:
```
mods/basic_enemies_mod/
├── mod_info.json
├── main.lua
├── enemies/
│   ├── grunt.lua
│   ├── soldier.lua
│   └── sniper.lua
└── ai/
    ├── patrol.lua
    ├── chase.lua
    └── attack.lua

mods/bear_boss_mod/
├── mod_info.json
├── main.lua
├── bear_boss.lua
├── attacks/
│   ├── laser.lua
│   └── ground_pound.lua
└── phases/
    ├── phase1.lua
    └── phase2.lua
```

## Success Criteria:
- All enemies behave identically to legacy version
- Boss fights work exactly as before
- AI responds properly to player actions
- Multiplayer enemy sync works
- Mods can be disabled without crashes

## Testing Checklist:
- [ ] Basic enemies spawn and patrol
- [ ] Enemy AI reacts to player
- [ ] Enemies fire projectiles correctly
- [ ] Bear boss all attacks work
- [ ] Boss phase transitions work
- [ ] Multiplayer enemy sync correct
- [ ] Performance maintained

## Special Considerations:
- Ensure enemy projectiles work with Agent 2's projectile system
- Coordinate entity ID system for network sync
- Test interaction with weapon damage from Agent 2's mods

Note: Can work in parallel with Agent 2, but coordinate on shared systems!
