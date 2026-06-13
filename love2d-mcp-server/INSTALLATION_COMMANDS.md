# Love2D MCP Server Installation Commands

## ✅ What has been done:
- Created the Love2D documentation MCP server (`server.py`)
- Created installation scripts (`install.sh` and `quickstart.sh`)
- Copied the server to `~/.claude-mcp-servers/love2d-docs/server.py`
- Made all files executable

## 📋 Commands to complete installation:

### Step 1: Install Claude CLI (if not already installed)
```bash
npm install -g @anthropic-ai/claude-code
```

### Step 2: Add the Love2D MCP server to Claude
```bash
claude mcp add --scope user love2d-docs python3 ~/.claude-mcp-servers/love2d-docs/server.py
```

### Step 3: Verify installation
```bash
claude mcp list
```

You should see `love2d-docs` in the list of MCP servers.

## 🎮 Using the Love2D MCP Server

Start Claude Code from any directory:
```bash
claude
```

Then use these commands:

### Search Love2D documentation:
```
mcp__love2d-docs__search_love2d
  query: "love.graphics.draw"
```

### Get module information:
```
mcp__love2d-docs__get_love2d_module
  module: "graphics"
```

### Get example code:
```
mcp__love2d-docs__get_love2d_example
  topic: "hello_world"
```

Available example topics:
- `hello_world` - Basic Love2D program
- `basic_movement` - Keyboard-controlled movement
- `image_loading` - Loading and drawing images
- `mouse_interaction` - Mouse input handling
- `game_loop` - Complete game structure

### Refresh documentation cache:
```
mcp__love2d-docs__refresh_love2d_cache
```

## 📁 File Locations

- **MCP Server**: `~/.claude-mcp-servers/love2d-docs/server.py`
- **Cache Directory**: `~/.claude-mcp-servers/love2d-docs/cache/`
- **Source Files**: Current directory (`love2d-mcp-server/`)

## 🔧 Troubleshooting

If the MCP server doesn't appear:
1. Make sure Claude CLI is installed: `which claude`
2. Check the MCP list: `claude mcp list`
3. Remove and re-add if needed:
   ```bash
   claude mcp remove love2d-docs
   claude mcp add --scope user love2d-docs python3 ~/.claude-mcp-servers/love2d-docs/server.py
   ```

## 🚀 Next Steps

1. Complete the installation by running the commands above
2. Try searching for Love2D functions you commonly use
3. The server can be extended to parse the full Love2D API from the love-api repository

Enjoy quick Love2D documentation access in Claude Code! 🎮