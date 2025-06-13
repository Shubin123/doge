# Mystical Glowing Trees Mod

A magical enhancement mod for DogeGame that adds enchanted trees with healing abilities, particle effects, and shader-based visual magic.

## Features

### 🌳 **Three Tree Types**
- **Mystical** (Green): Fast healing, high energy
- **Ancient** (Gold): Powerful healing, wise presence  
- **Enchanted** (Purple): Quick pulses, magical essence

### ✨ **Magical Effects**
- Real-time shader-based glow effects
- Floating particle sparkles
- Pulsing magical auras
- Wind-driven swaying animation
- Health-based visual changes

### 🎮 **Gameplay Features**
- **Healing System**: Trees restore player health when interacted with
- **Cooldown Mechanics**: Trees need time to recharge between uses
- **Interactive Elements**: Press 'E' near trees to heal
- **Dynamic Spawning**: Press 'T' to spawn new trees at your location

### 🌐 **Multiplayer Support**
- Tree states sync across all clients
- Healing effects visible to all players
- Mod sharing system for easy distribution
- Real-time tree creation/destruction sync

## Installation

1. Place the `glowing_tree_mod` folder in your `mods/` directory
2. Start the game - the mod will auto-load
3. Trees will spawn automatically in the world

## Controls

- **E** - Interact with nearby glowing tree (heal)
- **T** - Spawn a random tree at your location

## Technical Details

### Mod Structure
```
glowing_tree_mod/
├── mod_info.json      # Mod metadata and configuration
├── main.lua           # Core mod logic
├── shaders/
│   └── glowing_tree.frag  # Tree shader effects
├── assets/            # (Future: custom textures)
└── README.md          # This file
```

### Configuration Options
- `max_trees_per_world`: Maximum trees allowed (default: 50)
- `enable_healing`: Enable/disable healing functionality
- `enable_particles`: Enable/disable particle effects
- `enable_networking`: Enable/disable multiplayer sync

### API Usage
This mod demonstrates the DogeGame Mod API:
- **Renderer API**: Custom shaders, particle effects, lighting
- **Physics API**: Collision detection, world interaction
- **Network API**: Multiplayer synchronization
- **Input API**: Key binding and event handling

## Permissions Required
- `renderer.add_effects` - For particle and lighting effects
- `physics.create_bodies` - For tree collision detection
- `input.key_handlers` - For E/T key bindings
- `network.sync_entities` - For multiplayer synchronization

## Commands
- `/spawn_tree [type] [health]` - Spawn specific tree type
- `/tree_stats` - Display tree statistics

## Compatibility
- Engine Version: 1.0.0+
- Multiplayer: Full support
- Dependencies: None
- Conflicts: None known

## Development Notes

This mod serves as a reference implementation for the DogeGame modding system, demonstrating:

1. **Sandboxed Execution**: Safe mod loading with restricted API access
2. **Asset Management**: Loading custom shaders and textures
3. **Network Synchronization**: Real-time state sharing
4. **Event Handling**: Input processing and game hooks
5. **Performance Optimization**: Efficient rendering and updates

## Future Enhancements

- Custom tree textures
- Sound effects for interactions
- Tree growth mechanics
- Seasonal changes
- Advanced particle systems
- Tree farming mechanics

## License

This mod is part of the DogeGame engine and is provided as an example of the modding system capabilities.

---

*Created by DogeGame Developers as a demonstration of the modular game engine system.*