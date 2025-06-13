# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Running the Game
- **Development**: `'/Applications/love.app/Contents/MacOS/love' ./src`
- **Host Multiplayer**: `'/Applications/love.app/Contents/MacOS/love' ./src 1`
- **Join Multiplayer**: `'/Applications/love.app/Contents/MacOS/love' ./src 2 <ip_address>`
- **Build Distribution**: `./build.sh` (creates .love files and cross-platform packages)

### Development Tools
- **Hot Reload**: Game automatically restarts when files change (via `lurker.lua`)
- **Debug Console**: In-game command system accessible through `cmndX.lua`
- **Network Testing**: Built-in ENet multiplayer for LAN testing

## Architecture Overview

### Dual Rendering System
The game implements both legacy and modern rendering systems during transition:

- **Legacy Renderer** (`src/lib/graphics/renderer.lua`): Y-sorted dynamic draw list with multiplayer interpolation
- **New Renderer** (`src/lib/graphics/new_renderer.lua`): Asset management with queue-based rendering (background, world, ui, effects, post_process layers)

Key pattern: Always check which renderer a system uses before making changes.

### Modding System Architecture
The game is transitioning from hardcoded systems to a modular mod-based architecture:

- **Engine Core** (`src/engine/mod_system.lua`): Sandboxed mod execution with comprehensive API
- **Mod Structure**: Each mod in `mods/[mod_name]/` with `mod_info.json` + `main.lua`
- **API Access**: Mods get `api` object with renderer, physics, input, game, network, and utils subsystems

Example mod API usage:
```lua
function myMod.init(api)
    api.renderer.addParticleEffect("effect_name", x, y, "type", params)
    api.input.registerKeyHandler("f1", callback)
    api.network.sendToAll(data, "mod_id")
end
```

### Advanced Shader Pipeline
Multi-pass rendering system for real-time global illumination:

1. **Seed Pass**: Edge detection and UV coordinate generation
2. **Jump Flood Algorithm**: Distance field calculation using ping-pong buffers
3. **Global Illumination**: Ray-marched lighting with configurable sample count
4. **Post-Processing**: Bloom, water effects, and final composition

Key files: `src/shaders/`, `src/lib/graphics/shader.lua`, `src/systems/water.lua`

### Physics Integration
Uses Love2D physics with organized collision groups:
- Player: -1
- Enemies: -777  
- Bosses: -888
- Coins: 69

Collision handling is centralized in `main.lua:beginContact()` with system-specific delegation.

### Network Architecture
ENet-based multiplayer with:
- **State Synchronization**: Compressed JSON snapshots (`src/config/snapshot.lua`)
- **Entity Interpolation**: Smooth client-side prediction in renderer
- **Mod Sharing**: Real-time mod distribution when clients join hosts

## Key Configuration Systems

### Global Variables (`src/config/var.lua`)
Central configuration for screen dimensions, game boundaries, asset counts, and physics parameters.

### State Management (`src/config/snapshot.lua`)
Serialization system handling save/load and network synchronization. Critical for multiplayer functionality.

### Mod Configuration (`mod_info.json`)
```json
{
    "id": "mod_identifier",
    "permissions": ["renderer.add_effects", "physics.create_bodies"],
    "dependencies": [],
    "configuration": { /* mod settings */ }
}
```

## Legacy-to-Modern Migration Status

The codebase is actively migrating from monolithic to modular architecture:

**Still Legacy** (hardcoded in main systems): but require migrating!
- Enemy AI (`src/game/enemy.lua`, `src/game/boss.lua`)
- Weapon systems (`src/game/gun.lua`, `src/game/bullet.lua`)
- Map generation (`src/game/map.lua`)
- Particle effects (`src/systems/fire.lua`)

**Modern/Target State**: All game content should become mods, leaving only the engine core.

When working on game content, prefer creating/extending mods over modifying legacy hardcoded systems.

## Performance Considerations

### Rendering
- **Shader Sampling**: Lower sample counts (16-32) for real-time, higher (64+) for quality
- **Asset Preloading**: New renderer preloads textures; use `api.utils.loadTexture()` in mods
- **Draw Call Batching**: Group similar render operations within shader passes

### Physics
- **Collision Filtering**: Use appropriate collision groups to minimize unnecessary collision checks  
- **Object Pooling**: Reuse physics bodies and fixtures where possible

### Network
- **State Updates**: Only send changed state; leverage compression in snapshot system
- **Mod Sync**: Share mod scripts only, never assets (all assets are shared)

## Testing Multiplayer Mods
When testing mod functionality:
1. Start host with `love ./src 1`
2. Connect client with `love ./src 2 127.0.0.1`
3. Verify mod transfer and synchronization
4. Test that broken mods don't crash the engine

## Asset Management
- **Shared Assets**: All textures in `src/gfx/` are available to all mods
- **Mod Assets**: Place mod-specific assets in `mods/[mod_name]/assets/`
- **Shaders**: Custom shaders go in `mods/[mod_name]/shaders/`

## Debugging
- **Console Access**: Use in-game command system for runtime debugging
- **Mod Logging**: `api.utils.log(message, mod_id)` for mod-specific logging
- **Performance**: Monitor frame time and draw calls in debug mode

## Feature Implementation System Guidelines

### Feature Implementation Priority Rules
- IMMEDIATE EXECUTION: Launch parallel Tasks immediately upon feature requests
- NO CLARIFICATION: Skip asking what type of implementation unless absolutely critical
- PARALLEL BY DEFAULT: Always use 7-parallel-Task method for efficiency

### Parallel Feature Implementation Workflow
1. **Component**: Create main component file
2. **Styles**: Create component styles/CSS
3. **Tests**: Create test files  
4. **Types**: Create type definitions
5. **Hooks**: Create custom hooks/utilities
6. **Integration**: Update routing, imports, exports
7. **Remaining**: Update package.json, documentation, configuration files
8. **Review and Validation**: Coordinate integration, run tests, verify build, check for conflicts

### Context Optimization Rules
- Strip out all comments when reading code files for analysis
- Each task handles ONLY specified files or file types
- Task 7 combines small config/doc updates to prevent over-splitting

### Feature Implementation Guidelines
- **CRITICAL**: Make MINIMAL CHANGES to existing patterns and structures
- **CRITICAL**: Preserve existing naming conventions and file organization
- Follow project's established architecture and component patterns
- Use existing utility functions and avoid duplicating functionality