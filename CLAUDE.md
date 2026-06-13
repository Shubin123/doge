# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.


## Project Overview

This is a 2D action game built with LÖVE2D featuring real-time global illumination using Jump Flood Algorithm (JFA) and advanced water shader effects. The game includes combat mechanics, multiplayer support, and a built-in level editor.

## Essential Commands

### Running and Building
```bash
# Run the game in development mode (with hot-reload)
./run.sh

# Build distributable packages (.love file and .app for macOS)
./build.sh

# Extract .love file from executable
./unpack.sh game.exe
```

### Testing
```bash
# Test new game systems integration
'/Applications/love.app/Contents/MacOS/love' ./src/test_improvements.lua

# Test module loading and structure
'/Applications/love.app/Contents/MacOS/love' ./src/test_structure.lua
```

### In-Game Debug Keys
- `F1` - Add 1000 currency
- `F2` - Skip to next wave
- `F3` - Spawn random enemy
- `F4` - Spawn powerup
- `z` - Toggle 2x zoom
- `escape` - Toggle menu
- `space` - Start game (when integration system is active)

### Console Commands (accessible via cmndX)
- `editor.enable` / `editor.disable` - Toggle map editor
- `save` / `load` - Save/load game state
- `reload` - Reload game modules

## Architecture Overview

### Module System
The codebase follows a modular architecture with clear separation of concerns:
- **Entry Point**: `src/main.lua` contains game loop and integrates all systems
- **Global State**: Most modules are loaded as globals in main.lua (e.g., `player`, `enemy`, `gun`)
- **Physics**: Uses LÖVE2D's Box2D integration with `world` as global physics world
- **Rendering**: Custom renderer with dynamic draw list sorting by Y-coordinate

### Shader Pipeline
Multi-pass rendering system for advanced visual effects:
1. Scene renders to canvas
2. JFA generates distance fields using ping-pong buffers
3. Ray marching calculates global illumination
4. Water effects apply distortion and reflection
5. Post-processing (bloom, CRT filter) applied

Key shader files:
- `src/shaders/jfa_*.frag` - Jump Flood Algorithm passes
- `src/shaders/raymarching.frag` - Global illumination
- `src/shaders/water.frag` - Water distortion effects

### Integration System
The `game.integration` module coordinates all gameplay systems:
- Manages wave progression
- Handles currency and upgrades
- Spawns powerups
- Coordinates enemy deaths with rewards

When modifying gameplay, ensure integration.lua is updated to maintain system cohesion.

### Global Variables
Key globals defined in main.lua:
- `world` - Physics world
- `enemies_bods` - Enemy physics bodies array
- `dynamic_draw_list` - Rendering order list
- `var` - Configuration variables from config/var.lua

### State Management
- Game states: "menu", "running", "game"
- Check state with `var.State`
- Integration system activates when `var.State ~= "menu"`

### System Responsibilities
**IMPORTANT**: Maintain clear separation of concerns between systems:
- **fire.lua**: Only handles fireball visual effects and fire damage - NO knockback
- **gun.lua/bullet systems**: Handle all projectile knockback and impact physics
- **enemy.lua**: Manages enemy-specific knockback responses and health
- **integration.lua**: Coordinates cross-system interactions

When adding features, ensure they're implemented in the correct system to avoid nil value errors and architectural conflicts.

## Development Notes

### Hot Reload
Lurker automatically reloads changed Lua files. On file change, the game restarts via `love.event.push("quit", "restart")`.

### Adding New Features
1. Create module in appropriate directory (`game/`, `systems/`, `ui/`)
2. Require in main.lua as global or local
3. Add initialization in `love.load()`
4. Add update calls in `love.update(dt)`
5. Add rendering in `love.draw()` respecting draw order
6. Update integration.lua if feature affects gameplay

### Shader Development
- Shaders auto-reload on file change
- Use `shader.prepass()` and `shader.pass()` for global illumination
- Water effects require `water.setCameraTransform()` before rendering
- All shaders expect specific canvas formats (rgba8, rg16f, r16f)

### Performance Considerations
- Global illumination sample count affects FPS (16-32 for gameplay, 64+ for screenshots)
- Dynamic draw list sorting happens every frame
- Water areas should be limited to visible regions
- Enemy AI updates can be throttled for large enemy counts


### Your Desired understandings:
- dont bother running tests for work, let the user complete that and return if desired, to save tokens. ie: Avoid "Test that..." within planning.