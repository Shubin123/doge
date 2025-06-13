# DogeGame Mods System Log

This document provides a comprehensive overview of all mods in the DogeGame system, their intended usage, internal commands/functions, and inter-mod communication capabilities.

## Mod Overview

The DogeGame modding system supports 9 core mods that provide various gameplay features from AI behaviors to visual effects. All mods are sandboxed and communicate through a unified API system.

---

## 1. AI Behaviors Mod (`ai_behaviors_mod`)

**Purpose**: Provides reusable AI behavior patterns and state machines for enemy and NPC entities.

### Exports (Functions other mods can call):
- `createAIBehavior(entity, behavior_type, options)` - Creates AI behavior for an entity
- `updateAIBehavior(ai_instance, target, dt)` - Updates AI behavior logic
- `createStateMachine(entity, template_name, custom_states)` - Creates state machine
- `transitionState(state_machine, new_state, force)` - Transitions between states
- `removeAI(entity)` - Removes AI from entity
- `getStats()` - Returns AI statistics

### Behavior Patterns:
- **aggressive**: Always pursues target aggressively
- **tactical**: Uses tactical movement and positioning (advance/retreat/strafe)
- **cautious**: Maintains safe distance from threats
- **patrol**: Moves between predefined waypoints
- **guard**: Protects a specific location or entity

### Commands:
- `/ai_debug [on|off]` - Toggle AI debug visualization

### Inter-mod Usage:
- **Called by**: `basic_enemies_mod`, `bear_boss_mod` for AI behaviors
- **Dependencies**: None

---

## 2. Basic Enemies Mod (`basic_enemies_mod`)

**Purpose**: Adds standard enemy types with AI behaviors, projectile attacks, and health systems.

### Exports (Functions other mods can call):
- `createEnemy(x, y, enemy_type)` - Creates new enemy
- `damageEnemy(enemy_id, damage, from_player, attacker_x, attacker_y)` - Damages enemy
- `getStats()` - Returns enemy statistics

### Enemy Types:
- **grunt**: Health 50, aggressive AI, fire rate 2.0s, detection range 300
- **soldier**: Health 100, tactical AI, fire rate 1.5s, detection range 400  
- **sniper**: Health 75, cautious AI, fire rate 3.0s, detection range 600

### Commands:
- `/spawn_enemy [type] [x] [y]` - Spawn enemy at location
- `/enemy_stats` - Show enemy statistics

### Inter-mod Usage:
- **Uses**: `ai_behaviors_mod.createAIBehavior()` for AI
- **Uses**: `health_damage_mod.onEntityDamage()` for damage indicators
- **Uses**: `blood_effects_mod.onEntityDamage()` for blood effects

---

## 3. Bear Boss Mod (`bear_boss_mod`)

**Purpose**: Adds challenging Bear Boss with laser attacks, ground pounds, and multiple combat phases.

### Exports (Functions other mods can call):
- `createBoss(x, y, health)` - Creates bear boss
- `damageBoss(boss_id, damage, from_player, attacker_x, attacker_y)` - Damages boss
- `getStats()` - Returns boss statistics

### Boss States:
- **idle**: Default waiting state
- **preparing_hop**: Preparing ground pound attack
- **hopping**: Executing ground pound
- **landing**: Landing with shockwave damage
- **charging_laser**: Building up laser attack
- **firing_laser**: Active laser beam attack
- **headless**: Enraged phase at 20% health

### Boss Attacks:
- **Ground Pound**: 50 damage, 100 radius, creates shockwave particles
- **Laser Attack**: 30 damage, tracking beam, dual-eye lasers
- **Phase Transitions**: Headless mode at 20% health, rage mode at 50%

### Commands:
- `/spawn_boss [x] [y]` - Spawn bear boss
- `/boss_stats` - Show boss statistics

### Inter-mod Usage:
- **Uses**: `ai_behaviors_mod.createAIBehavior()` for tactical AI
- **Uses**: `health_damage_mod.onEntityDamage()` for health bars
- **Uses**: `blood_effects_mod.onEntityDamage()` for death effects

---

## 4. Blood Effects Mod (`blood_effects_mod`)

**Purpose**: Provides realistic blood splatter effects, pools, and particle systems for combat damage.

### Exports (Functions other mods can call):
- `createBloodSplatter(x, y, damage, direction_x, direction_y)` - Creates blood splatter
- `createBloodPool(x, y, damage)` - Creates blood pool
- `createBloodParticles(x, y, damage, direction_x, direction_y)` - Creates blood particles
- `clearBlood()` - Removes all blood effects
- `setBloodIntensity(intensity)` - Sets blood effect intensity (0-2.0)
- `onEntityDamage(entity_id, x, y, damage, attacker_x, attacker_y)` - Called on damage
- `onEntityDeath(entity_id, x, y, max_health)` - Called on death

### Effect Types:
- **Splatters**: 3-8 random splatters, fade over 20s, color changes from fresh to old
- **Pools**: Form from 20+ damage, grow dynamically, last 30s
- **Particles**: 5-15 particles with physics, create splatters on landing

### Commands:
- `/blood_test [intensity]` - Test blood effects at cursor
- `/clear_blood` - Clear all blood effects

### Inter-mod Usage:
- **Called by**: `basic_enemies_mod`, `bear_boss_mod`, `combat_effects_mod` for damage effects
- **Dependencies**: None

---

## 5. Combat Effects Mod (`combat_effects_mod`)

**Purpose**: Visual effects system for combat including muzzle flashes, explosions, shell casings, and impact effects.

### Exports (Functions other mods can call):
- `createMuzzleFlash(x, y, direction, params)` - Creates muzzle flash effect
- `createExplosion(x, y, radius, params)` - Creates explosion with particles
- `createShellEjection(x, y, direction, shell_type, params)` - Ejects shell casing
- `createBloodSplatter(x, y, direction, intensity, params)` - Blood effect
- `createSparks(x, y, direction, params)` - Creates spark particles

### Effect Types:
- **Muzzle Flash**: 0.1s duration, cone-shaped, color customizable
- **Explosions**: Configurable particle count, shockwave radius, duration 0.8s
- **Shell Casings**: Physics-based ejection, bouncing, multiple shell types (small/rifle/shotgun)
- **Sparks**: Impact sparks for metal/environment hits

### Commands:
- `/spawn_effect [effect_type] [x] [y]` - Spawn visual effect
- `/clear_effects` - Clear all effects

### Inter-mod Usage:
- **Called by**: `weapons_core_mod`, `projectiles_mod` for weapon effects
- **Optional Dependencies**: `weapons_core_mod`, `projectiles_mod`

---

## 6. Glowing Tree Mod (`glowing_tree_mod`)

**Purpose**: Adds magical glowing trees with particle effects, healing abilities, and shader-based visuals.

### Exports (Functions other mods can call):
- `createTree(x, y, tree_type, health)` - Creates glowing tree
- `getStats()` - Returns tree statistics

### Tree Types:
- **MYSTICAL**: Green glow, 15 healing power, medium sway
- **ANCIENT**: Golden glow, 25 healing power, large scale, slow pulse
- **ENCHANTED**: Purple glow, 10 healing power, fast pulse, high sway

### Interaction:
- **Healing**: Press 'E' near trees for health restoration (3s cooldown)
- **Visual Effects**: Continuous magical particles, dynamic lighting
- **Health System**: Trees lose energy when healing players

### Commands:
- `/spawn_tree [type] [health]` - Spawn tree at player location
- `/tree_stats` - Show tree statistics

### Key Bindings:
- **T**: Spawn random tree at player location
- **E**: Interact with nearby tree for healing

### Inter-mod Usage:
- **Standalone**: No dependencies, purely environmental feature

---

## 7. Health & Damage Indicators Mod (`health_damage_mod`)

**Purpose**: Provides health bars and floating damage number indicators for entities in combat.

### Exports (Functions other mods can call):
- `showHealthBar(entity_id, x, y, current_health, max_health, entity_type)` - Shows health bar
- `showDamageIndicator(x, y, damage, is_critical)` - Shows floating damage number
- `showHealIndicator(x, y, heal_amount)` - Shows healing number
- `hideHealthBar(entity_id)` - Hides health bar
- `updateHealthBar(entity_id, current_health, max_health, x, y)` - Updates health
- `onEntityDamage(entity_id, x, y, damage, current_health, max_health, entity_type)` - Damage hook
- `onEntityHeal(entity_id, x, y, heal_amount, current_health, max_health, entity_type)` - Heal hook

### Indicator Features:
- **Damage Numbers**: Float upward, fade out, critical hits (25+ damage) in red with scaling
- **Heal Numbers**: Green floating numbers with '+' prefix
- **Health Bars**: Color-coded (green > yellow > red), flash on damage, 3s duration
- **Boss Health**: Extended bars with numeric health display

### Commands:
- `/damage_test [damage_amount]` - Test damage indicator at cursor

### Inter-mod Usage:
- **Called by**: `basic_enemies_mod`, `bear_boss_mod`, `glowing_tree_mod` for health/damage display
- **Dependencies**: None

---

## 8. Projectiles Mod (`projectiles_mod`)

**Purpose**: Modular projectile system providing bullets, rockets, and explosive projectiles with physics simulation.

### Exports (Functions other mods can call):
- `spawnProjectile(template_id, x, y, dx, dy, params)` - Spawns projectile
- `registerProjectile(id, template)` - Registers new projectile type
- `getActiveProjectiles()` - Returns active projectiles list
- `handleCollision(projectile_fixture, other_fixture, contact)` - Handles collisions

### Built-in Projectile Types:
- **bullet**: Standard bullet, 800 speed, 10 damage, 5s lifetime
- **tracer**: Fast tracer round, 1000 speed, 12 damage, bright trail
- **rocket**: Explosive rocket, 500 speed, 100 damage, 100 explosion radius
- **plasma**: Energy bolt, 600 speed, 25 damage, energy decay over time

### Physics Features:
- **Collision Detection**: Different collision groups for projectiles, rockets, explosions
- **Damage System**: Handles player, enemy, boss, and environment collisions
- **Visual Trails**: Configurable particle trails, exhaust for rockets
- **Explosion System**: Area damage with particle effects

### Commands:
- `/spawn_projectile [type] [x] [y] [dx] [dy]` - Spawn projectile
- `/clear_projectiles` - Clear all projectiles

### Inter-mod Usage:
- **Called by**: `weapons_core_mod` for weapon projectiles
- **Optional Dependencies**: `weapons_core_mod`, `combat_effects_mod`

---

## 9. Weapons Core Mod (`weapons_core_mod`)

**Purpose**: Core weapon system providing modular weapons framework with custom weapons, projectile spawning, and combat mechanics.

### Exports (Functions other mods can call):
- `registerWeapon(id, template)` - Registers new weapon type
- `getWeaponTemplate(id)` - Returns weapon template
- `getCurrentWeapon()` - Returns currently equipped weapon

### Built-in Weapons:
- **Pistol**: 0.3s fire rate, 10 damage, low spread, small shells
- **SMG**: 0.1s fire rate, 8 damage, medium spread, 30 round magazine
- **Shotgun**: 0.8s fire rate, 6 damage x8 pellets, high spread, shotgun shells
- **Assault Rifle**: 0.15s fire rate, 12 damage, medium spread, 30 rounds
- **Rocket Launcher**: 1.5s fire rate, 100 damage, explosions, no shells

### Weapon Features:
- **Fire Rate Control**: Cooldown system prevents spam
- **Spread System**: Configurable accuracy for different weapons
- **Ammo System**: Magazine-based reloading for some weapons
- **Visual Effects**: Muzzle flashes, shell ejection, aiming rings

### Key Bindings:
- **1-5**: Switch between weapons (pistol, SMG, shotgun, assault rifle, rocket launcher)
- **Mouse 1**: Fire current weapon

### Commands:
- `/give_weapon [weapon_id]` - Give weapon to player
- `/list_weapons` - List all available weapons

### Inter-mod Usage:
- **Uses**: `projectiles_mod.spawnProjectile()` for firing projectiles
- **Uses**: `combat_effects_mod.createMuzzleFlash()` for muzzle effects
- **Optional Dependencies**: `projectiles_mod`, `combat_effects_mod`

---

## Inter-Mod Communication Examples

### Damage Chain Example:
1. `weapons_core_mod` fires projectile → `projectiles_mod.spawnProjectile()`
2. Projectile hits enemy → `basic_enemies_mod.damageEnemy()`
3. Enemy takes damage → `health_damage_mod.onEntityDamage()` (shows health bar + damage number)
4. Blood effects → `blood_effects_mod.onEntityDamage()` (creates splatter + particles)

### Boss Fight Example:
1. `bear_boss_mod` creates boss → `ai_behaviors_mod.createAIBehavior()` (tactical AI)
2. Boss attacks player → `health_damage_mod.showDamageIndicator()` (floating damage)
3. Player damages boss → `health_damage_mod.showHealthBar()` + `blood_effects_mod.onEntityDamage()`
4. Boss dies → `blood_effects_mod.onEntityDeath()` (dramatic death effects)

### Healing Example:
1. Player interacts with tree → `glowing_tree_mod.interactWithTree()`
2. Tree heals player → `health_damage_mod.showHealIndicator()` (green +HP number)
3. Tree creates particle effects → renderer API directly

---

## Mod Development Guidelines

When creating new mods, follow these patterns:

1. **Export Functions**: Use `exports` table for inter-mod communication
2. **Call Other Mods**: Use `api.mods.other_mod_name.exports.functionName()`
3. **Optional Dependencies**: Check if mod exists before calling: `if api.mods.blood_effects_mod then`
4. **Event Hooks**: Use standard hooks like `onEntityDamage`, `onEntityDeath`, `onEntityHeal`
5. **Network Sync**: Use `api.network.sendToAll()` for multiplayer synchronization
6. **Cleanup**: Always destroy physics bodies and clear state in `cleanup()` function

---

## Standardized mod_info.json Format

**CRITICAL**: All mods must follow this exact format for compatibility:

```json
{
    "id": "mod_identifier",
    "name": "Display Name",
    "version": "1.0.0",
    "author": "Author Name",
    "description": "Brief description",
    "engine_version": "1.0.0",
    "dependencies": [],
    "optional_dependencies": [],
    "assets": [],
    "shaders": [],
    "permissions": [],
    "configuration": {},
    "hooks": {},
    "exports": [],
    "commands": [],
    "collision_groups": {},
    "weapon_templates": [],
    "projectile_types": [],
    "effect_types": []
}
```

### Field Requirements:
- **All fields must be present** even if empty (use `[]` for arrays, `{}` for objects)
- **id** must match directory name exactly
- **dependencies** lists required mods that must load first
- **optional_dependencies** lists mods that enhance functionality if present
- **exports** lists function names other mods can call
- **collision_groups** maps collision names to numeric IDs
- **weapon_templates, projectile_types, effect_types** are specialized arrays for specific mod types

This standardization ensures:
- Consistent mod loading and dependency resolution
- Proper inter-mod communication
- Future compatibility with engine updates
- Easy integration of new mod features

This system allows for highly modular gameplay where mods can work independently or enhance each other when combined.