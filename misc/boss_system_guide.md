# Boss System Usage Guide

## Overview
The boss system has been successfully implemented with the following features:
- Bear boss with 9000 HP
- Hop movement with squish/shake animation
- Ground pound area damage on landing
- Laser eye attack with charge-up time (mechanics work, visual pending)
- Red flash when damaged
- Particle effects for landing impact
- Health bar display
- Multiplayer replication support
- Console commands for testing

## Known Issues
- Laser beam visual effect is temporarily disabled (line rendering not supported in current renderer)
- The laser still deals damage, but you won't see the beam

## Console Commands

### Spawning a Boss
```
boss spawn [x] [y]
```
- If x and y are not provided, spawns at player's current position
- Returns the boss ID for reference

### Despawning Bosses
```
boss despawn <id>     # Despawn specific boss
boss despawn all      # Despawn all bosses
```

### List Active Bosses
```
boss list
```
Shows the count of active bosses

### Damage a Boss
```
boss damage <id> [amount]
```
- Default damage is 100 if amount not specified
- Boss will flash red when damaged

## Boss Mechanics

### Movement (Hopping)
- Boss squishes down and shakes before hopping
- Hops toward the nearest player
- Landing creates particle effect and area damage (200 radius, 25 damage)

### Laser Attack
- Boss charges laser for 2 seconds (threatening sprite)
- Fires laser for 1.5 seconds (shooting sprite)
- Laser cannot change direction once charging starts
- Deals 40 damage on hit

### Health System
- 9000 HP total
- Health bar displayed above boss
- Flashes red when taking damage
- Shows damage numbers (using enemy damage indicator system)

## Sprite States
The boss uses three different sprites:
1. **Default**: `bear_enemy_default_state.png`
2. **Threatening**: `bear_enemy_laser_threatening.png` (charging laser)
3. **Shooting**: `bear_enemy_laser_shooting.png` (firing laser)

## Multiplayer Support
- Boss data is synchronized via the snapshot system
- Only the host manages boss AI and physics
- Clients receive boss state updates for rendering

## Testing Workflow
1. Start the game
2. Open console with `` ` ``
3. Spawn a boss: `boss spawn`
4. Test damage: `boss damage 1 500`
5. Watch the boss behavior and attacks
6. Despawn when done: `boss despawn all`

## Integration Points
The boss system integrates with:
- Physics system (collision group -888)
- Damage system (compatible with player weapons)
- Particle system (landing effects)
- Rendering system (dynamic draw list)
- Network system (snapshot replication)
- Console system (debug commands)

## Future Enhancements
Possible improvements:
- Additional boss types
- More attack patterns
- Boss phases at different health thresholds
- Drop rewards on death
- Boss-specific sound effects
- Screen shake on ground pound
