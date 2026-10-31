# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.


## Project Overview

This is a 2D action game built with LÖVE2D featuring real-time global illumination using Jump Flood Algorithm (JFA) and puddle water effects. The game includes combat mechanics, multiplayer support, and a built-in level editor.

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
# GPU regression suite: pixel-exact frames, render-pass counts and frame time
# vs. a baseline revision (exit 0 pass / 1 regression / 2 could not run).
# See tests/gpu/README.md.
python3 tests/gpu/run.py                  # vs. tests/gpu/BASELINE
python3 tests/gpu/run.py --baseline HEAD  # vs. the last commit
python3 tests/gpu/run.py --json           # machine-readable report
python3 tests/gpu/run.py --checks         # functional checks (enemy sprites, death light)

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
- `b` - Step bullet tracer / tesla bolt brightness down (`var.tracer_brightness`; wraps to full)
- `escape` - Toggle menu
- `space` - Start game (when integration system is active)

### Console Commands (`/` or `,` opens the console, `ui/command.lua`; Esc closes it)
- `editor.enable` / `editor.disable` - Toggle map editor
- `save` / `load` - Save/load game state
- `reload` - Reload game modules
- `blackhole [x] [y]` - Move the black hole (default: just ahead of you)
- `time [hour]` - Show or set the time of day

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
4. Post-processing (bloom, CRT filter) applied

Key shader files:
- `src/shaders/jfa_*.frag` - Jump Flood Algorithm passes
- `src/shaders/raymarching.frag` - Global illumination
- `systems/puddle.lua` - Puddle and pool water (wobbly ellipses on the ground)

### Integration System
The `game.integration` module coordinates all gameplay systems:
- Manages wave progression
- Handles currency and upgrades
- Spawns powerups
- Coordinates enemy deaths with rewards

When modifying gameplay, ensure integration.lua is updated to maintain system cohesion.

### Regions & Portal
- `game/regions.lua` lays out four regions (Wasteland, Castle, Neon City, Sanctum) procedurally from fixed seeds, 20000 px apart east of the home map: blended seamless ground (its own shader), edge walls + a physics fence, facade streets, props/lamps (lamps add transient lights), a pool (one big puddle), puddles and grass patches (`grass.public.addField`).
- Light by height (`SPRITE_SHADER` in regions.lua): region sprites carry their base row and flags in their vertex colour. Tall ones (facades, walls, towers, lamps, glowing signs, props over 96 px) write alpha 1 and block GI; low props write the ground's 0.4 so light passes; `flat` ones (grates, carpets, rubble) are drawn into the ground pass under whoever walks over them. Faces are lit from the ground point under each texel, not by lights behind their base.
- Light emitters: sprites with a `glow` entry in `gfx/regions/<id>.lua` (lamps, flames, neon, glowing glass) have their glowing texels in `<id>_glow.png`; those draw at full strength in the dark (and so feed GI their colour), and each emitter adds a transient point light from the ground under it, a coloured pool on the floor and a halo (`regions.drawGlows`, drawn after the sorted sprites). Fire flickers.
- Art: one atlas per region in `gfx/regions/<id>.png`, sprite rects + categories in `gfx/regions/<id>.lua`, ground textures in `<id>_floor.png`. Sprite pools per region are named in `regions.list`.
- `game/portal.lua`: standing in any region's portal opens the travel selector (Up/Down, Enter/E, 1-5, mouse, Esc); `regions.teleport` moves the player and `camera.snap` jumps the camera.

### Black Hole & Time
- `game/blackhole.lua` sits at (1400, 300) east of home (`blackhole [x] [y]` in the console moves it). Near it time slows: `love.update` multiplies `dt` by `blackhole.timeScale` right after networking, so everything after that line runs on slowed time (use `love.timer.getTime()` for real time). It pulls the player, enemies, globs and bullets, swallows what crosses the horizon, and `blackhole.applyLensing()` bends `scene_canvas` before GI. In multiplayer the host sends its position and the shared pace in the snapshot.

### Day & Night
- `systems/daynight.lua` keeps `daynight.hour` (game time, so the black hole slows it; `var.day_length` seconds a day, starting at `var.day_start`). `daynight.apply()` sets `shadow.ambient` (0.2 at night, the old look, up to 1 by day), which every lit shader reads, characters included; `shader.pass` hands `daynight.daylight()` and `daynight.tint()` to the composite, which by day shows the scene's own colours under the sky. The HUD's clock is in `hud.lua` (`drawClock`); the host's hour goes out in the snapshot and saves keep it. The GPU scenario pins midnight.

### Shop & Safe Zone
- `game/shop.lua`: the home map's house is the shop. Inside it (`var.indoors`) `player.isSafe()` is true and every damage path skips the player; its door is too narrow for enemies. A shopkeeper behind a counter sells for XP (`var.player_score`) by day only (`daynight.isOpen()`, 07:00-19:00); at night they sleep. E at the counter opens the panel (`shop.keypressed`, before the rest of the game's keys).

### Car
- `game/car.lua`: the parked car is drivable. Near it an arrow and "[E] Drive" show over it (`car.drawUI`); E gets in (`car.enter`: the player's body becomes the car's, wider, faster and coasting; `player.inCar` hides the princess and stops shooting and dodging), E again gets out beside it (`car.exit`). Host and single player only.

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
- All shaders expect specific canvas formats (rgba8, rg16f, r16f)

### Performance Considerations
- Global illumination sample count affects FPS (16-32 for gameplay, 64+ for screenshots)
- Dynamic draw list sorting happens every frame
- Enemy AI updates can be throttled for large enemy counts


### Your Desired understandings:
- dont bother running tests for work, let the user complete that and return if desired, to save tokens. ie: Avoid "Test that..." within planning.