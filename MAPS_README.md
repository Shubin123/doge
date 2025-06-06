# Advanced Map System Documentation

## Overview

The map loading system has been completely redesigned with the following features:

- **Streaming & Caching**: Asynchronous loading with LRU cache management
- **Hot-Reload**: Real-time map editing with automatic file watching
- **In-Game Editor**: Full-featured map editor with undo/redo
- **Multiple Formats**: JSON, Binary, and Lua export formats
- **Spatial Optimization**: Efficient rendering with spatial indexing

## Key Components

### 1. Map Loader (`map_loader.lua`)
- Asynchronous map loading with coroutines
- Asset caching with LRU eviction
- Chunk-based loading for large maps
- Memory management and optimization

### 2. Map Manager (`map_manager.lua`)
- High-level map switching and management
- Entity spawning and cleanup
- World bounds management
- State management during transitions

### 3. Map Serializer (`map_serializer.lua`)
- Save/load maps in multiple formats
- Binary compression using RLE
- Lua code generation for embedding
- Template creation utilities

### 4. Map Editor (`map_editor.lua`)
- Real-time in-game editing
- Multiple tools: tile painting, entity placement, selection
- Undo/redo system with history
- Brush sizing and flood fill
- Grid overlay and visual feedback

### 5. Map Hot-Reloader (`map_hotreloader.lua`)
- File system watching
- Automatic reload on file changes
- External editor support
- Development templates
- Backup creation

## Usage

### Basic Controls

**Map Switching:**
- `1` - Switch to Level 1
- `2` - Switch to Level 2  
- `3` - Switch to Level 3

**Map Editor:**
- `E` - Toggle map editor mode
- `T` - Tile editing mode
- `R` - Entity editing mode
- `Tab` - Switch tool mode (paint/erase/fill/pick)
- `1-9` - Select tile ID
- `Q/E` - Decrease/increase brush size
- `G` - Toggle grid overlay
- `Ctrl+S` - Quick save map
- `Ctrl+Z` - Undo
- `Ctrl+Y` - Redo

**Hot-Reload:**
- `F5` - Reload all watched maps
- `F6` - Auto-save current map
- `F7` - Export for external editing (JSON)
- `F8` - Create development template

**Debug:**
- `M` - Show debug information

### Creating New Maps

#### Method 1: In-Game Editor
```lua
-- Create new map programmatically
map_editor.create_new_map("my_map", "My Custom Map", 50, 50)

-- Switch to it and start editing
map.switchToMap("my_map")
-- Press 'E' to enable editor mode
```

#### Method 2: Development Template
```lua
-- Press F8 to create a dev template
-- Edit the generated .map file externally
-- Automatically reloads when saved
```

#### Method 3: Code
```lua
local map_loader = require("map_loader")

map_loader.register_map({
    id = "custom_level",
    name = "Custom Level",
    tileset_path = "gfx/TileSet/TX Tileset Grass.png",
    tile_width = 16,
    tile_height = 16,
    map_width = 60,
    map_height = 40,
    world_x = 0,
    world_y = 0,
    player_spawn = {x = 100, y = 100},
    enemies = {
        {x = 200, y = 200, type = "basic"}
    },
    collectibles = {
        {x = 150, y = 150, type = "coin"}
    }
})
```

### Map File Formats

#### Binary Format (.map)
- Optimized for performance
- RLE compression for tile data
- Metadata in JSON header
- Fastest loading time

#### JSON Format
- Human-readable
- Easy external editing
- Good for version control
- Larger file size

#### Lua Format
- Embeddable in code
- Version control friendly
- No runtime file I/O needed

### External Editing Workflow

1. Press `F7` to export current map as JSON
2. Edit the exported file in your preferred editor
3. Save the file - it automatically reloads in-game
4. See changes immediately without restarting

### Performance Features

- **Streaming**: Large maps load progressively
- **Caching**: Recently used maps stay in memory
- **Spatial Indexing**: Only visible tiles are rendered
- **Chunk Loading**: Maps are loaded in 32x32 tile chunks
- **LOD**: Distant objects can be culled

### File Structure

```
maps/
├── quicksave_01.map          # Quick save slot 1
├── level1_external.json     # External editing export
├── dev_test_dev.map         # Development template
└── my_custom_map.map        # Custom saved map
```

### Integration with Existing Systems

The new map system maintains compatibility with the existing codebase through a legacy compatibility layer in `map.lua`. Old functions still work but internally use the new system.

**Legacy Functions (still work):**
- `map.load()`
- `map.spawnMapEntities()`
- `map.getCurrentMap()`

**New Functions:**
- `map.switchToMap(id, callback)`
- `map.getTileAtWorldPos(x, y)`
- `map.setTileAtWorldPos(x, y, tile_id)`
- `map.getDebugInfo()`

### Tips for Development

1. **Use F8** to quickly create test maps
2. **Press F6** regularly to auto-save your work
3. **Use the grid (G)** for precise tile placement
4. **External editing** is great for large-scale changes
5. **Hot-reload** makes iteration incredibly fast
6. **Undo/redo (Ctrl+Z/Y)** for safe experimentation

### Troubleshooting

**Maps not loading:**
- Check console for error messages
- Verify tileset paths are correct
- Ensure map dimensions are valid

**Hot-reload not working:**
- Check if files are in the `maps/` directory
- Verify file permissions
- Look for parsing errors in console

**Performance issues:**
- Reduce map size or use streaming
- Check spatial indexing is enabled
- Monitor memory usage with `M` key

**Editor not responding:**
- Ensure editor mode is enabled (`E` key)
- Check if camera is within map bounds
- Verify tool mode is correct (`Tab` to cycle)

## Advanced Features

### Custom Tile Generation
Maps can use procedural generation or custom algorithms for tile placement. The system supports both static and dynamic tile data.

### Entity System Integration
The map system automatically spawns and manages entities defined in map data, integrating seamlessly with the physics system.

### Multi-layered Maps
Support for multiple tile layers and rendering priorities through the sort_y system.

### Memory Management
Automatic cache eviction and memory monitoring ensure stable performance even with many large maps.