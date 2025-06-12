# Love2D Documentation MCP Server

🎮 Quick access to Love2D documentation directly in Claude Code!

## Features

- **Search Love2D API** - Search for functions, modules, and concepts
- **Module Information** - Get detailed info about Love2D modules
- **Code Examples** - Access common Love2D patterns and examples
- **Offline Cache** - Documentation cached locally for fast access

## Installation

### Quick Install (from this directory)

```bash
./install.sh
```

### Manual Installation

1. Copy the server to the MCP servers directory:
```bash
mkdir -p ~/.claude-mcp-servers/love2d-docs
cp server.py ~/.claude-mcp-servers/love2d-docs/
chmod +x ~/.claude-mcp-servers/love2d-docs/server.py
```

2. Add to Claude Code with global scope:
```bash
claude mcp add --scope user love2d-docs python3 ~/.claude-mcp-servers/love2d-docs/server.py
```

3. Verify installation:
```bash
claude mcp list
```

## Usage

Start Claude Code anywhere and use these commands:

### Search Documentation
```
mcp__love2d-docs__search_love2d
  query: "love.graphics.draw"
```

### Get Module Info
```
mcp__love2d-docs__get_love2d_module
  module: "graphics"
```

### Get Example Code
```
mcp__love2d-docs__get_love2d_example
  topic: "basic_movement"
```

Available examples:
- `hello_world` - Basic Love2D program
- `basic_movement` - Keyboard-controlled movement
- `image_loading` - Loading and drawing images
- `mouse_interaction` - Mouse input handling
- `game_loop` - Complete game structure

### Refresh Cache
```
mcp__love2d-docs__refresh_love2d_cache
```

## How It Works

The server provides quick access to Love2D documentation by:
1. Caching common API documentation locally
2. Providing search functionality across functions and modules
3. Offering ready-to-use code examples
4. Integrating seamlessly with Claude Code

## Examples

### Example 1: Looking up a function
```
User: "How do I draw an image in Love2D?"
Claude: Let me look that up for you...
*uses mcp__love2d-docs__search_love2d with query "draw image"*
```

### Example 2: Getting module overview
```
User: "What can I do with love.physics?"
Claude: I'll get the physics module information...
*uses mcp__love2d-docs__get_love2d_module with module "physics"*
```

### Example 3: Getting starter code
```
User: "Show me a basic Love2D game structure"
Claude: Here's a complete game loop example...
*uses mcp__love2d-docs__get_love2d_example with topic "game_loop"*
```

## Troubleshooting

### MCP not showing up?
```bash
# Check if it's installed
claude mcp list

# Reinstall with global scope
claude mcp remove love2d-docs
claude mcp add --scope user love2d-docs python3 ~/.claude-mcp-servers/love2d-docs/server.py
```

### Python errors?
- Ensure Python 3.8+ is installed
- Check file permissions: `chmod +x server.py`

## License

MIT License - Use freely!

---

Made with ❤️ for the Love2D community