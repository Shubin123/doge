# Weapons Core Mod

A comprehensive weapons system that fully replaces the legacy gun.lua system with a modular, extensible architecture.

## Features

### Core Weapon System
- **Client-side aiming circle** around the player
- **Perpendicular gun barrel** that aims normal to the circle
- **Bullet spawning** from gun tip with proper offset calculations
- **Full network replication** for multiplayer support
- **Sophisticated visual effects** including muzzle flash, shell ejection, and gunpowder particles

### 5 Unique Weapons

1. **Pistol**
   - Semi-automatic, balanced damage
   - 12 round magazine
   - Brass shell ejection
   - Medium muzzle flash

2. **SMG (Submachine Gun)**
   - Full automatic, high fire rate
   - 30 round magazine
   - Small brass shells
   - Rapid muzzle flash

3. **Shotgun**
   - 8 pellet spread pattern
   - 6 shell capacity
   - Red plastic shell ejection
   - Large cone muzzle flash

4. **Assault Rifle**
   - Full automatic, accurate
   - 30 round magazine
   - Rifle brass shells
   - Controlled muzzle flash

5. **Rocket Launcher**
   - Explosive projectiles
   - 4 rocket capacity
   - No shell ejection
   - Massive muzzle flash and recoil

### Visual Effects

#### Muzzle Flash
- Sophisticated cone-shaped flash geometry
- Gradient rendering for realistic appearance
- Weapon-specific parameters (size, duration, color)
- Shader support for enhanced effects

#### Shell Ejection
- Physics-based shell casings
- Weapon-specific shell types and colors
- Realistic ejection velocity and spin
- Ground collision and bouncing

#### Particle Effects
- Gunpowder confetti particles
- Directional spread based on gun direction
- Multiple color variations
- Velocity and size randomization

### Recoil & Feedback
- Player knockback force
- Screen shake integration
- Weapon-specific recoil patterns
- Full auto handling

## Usage

### Switching Weapons
Press number keys 1-5 to switch between weapons:
- `1` - Pistol
- `2` - SMG
- `3` - Shotgun
- `4` - Assault Rifle
- `5` - Rocket Launcher

### Controls
- **Left Mouse Button** - Fire weapon
- **Hold for Full Auto** - SMG and Assault Rifle support continuous fire

## Integration

### Dependencies
- **projectiles_mod** - Handles projectile physics and collision
- **combat_effects_mod** - Provides visual effects system

### Network Support
The mod fully supports multiplayer with:
- Weapon state synchronization
- Shot replication to other players
- Visual effects synchronization
- PvP damage support

## Technical Details

### Aiming System
The aiming system continuously tracks mouse position and converts screen coordinates to world coordinates, accounting for camera zoom. The gun barrel is rendered perpendicular to the aiming direction on the circle around the player.

### Object Pooling
The system integrates with projectiles_mod's object pooling for efficient projectile management, reducing garbage collection and improving performance.

### Mod API Usage
The mod uses the standard mod API for:
- Renderer integration
- Physics body creation
- Input handling
- Network messaging
- Inter-mod communication

## Configuration

Weapon parameters can be customized by modifying the weapon template files in the `weapons/` directory. Each weapon file contains:
- Fire rate and damage values
- Visual properties (barrel length, thickness, colors)
- Effect parameters (muzzle flash, particles)
- Audio references
- Ammo and reload settings

## Migration from Legacy System

This mod completely replaces the legacy gun.lua system while preserving all advanced features:
- Enhanced muzzle flash rendering
- Sophisticated particle systems
- Shell ejection physics
- Network replication
- Full auto support

The migration is seamless - simply ensure the mod is loaded and the legacy gun.lua is no longer referenced.