#!/bin/bash
# Love2D MCP Server - Quick Installation Commands
# Run these commands in your terminal to install the Love2D documentation MCP server

echo "Love2D MCP Server - Quick Installation Guide"
echo "============================================"
echo ""
echo "Since Claude CLI is not installed, here are the manual steps:"
echo ""
echo "1. First, install Claude Code CLI (if not already installed):"
echo "   npm install -g @anthropic-ai/claude-code"
echo ""
echo "2. Create the MCP server directory:"
echo "   mkdir -p ~/.claude-mcp-servers/love2d-docs"
echo ""
echo "3. Copy the server file to the MCP directory:"
echo "   cp $(pwd)/server.py ~/.claude-mcp-servers/love2d-docs/"
echo "   chmod +x ~/.claude-mcp-servers/love2d-docs/server.py"
echo ""
echo "4. Add the server to Claude Code with global scope:"
echo "   claude mcp add --scope user love2d-docs python3 ~/.claude-mcp-servers/love2d-docs/server.py"
echo ""
echo "5. Verify installation:"
echo "   claude mcp list"
echo ""
echo "6. Start using in Claude Code:"
echo "   claude"
echo ""
echo "Then you can use commands like:"
echo "   mcp__love2d-docs__search_love2d"
echo "     query: \"love.graphics.draw\""
echo ""

# Also copy the server file now if possible
if [ -f "server.py" ]; then
    echo "Preparing server file for manual installation..."
    mkdir -p ~/.claude-mcp-servers/love2d-docs
    cp server.py ~/.claude-mcp-servers/love2d-docs/
    chmod +x ~/.claude-mcp-servers/love2d-docs/server.py
    echo "✅ Server file copied to: ~/.claude-mcp-servers/love2d-docs/server.py"
    echo ""
    echo "Now you just need to:"
    echo "1. Install Claude CLI: npm install -g @anthropic-ai/claude-code"
    echo "2. Run: claude mcp add --scope user love2d-docs python3 ~/.claude-mcp-servers/love2d-docs/server.py"
fi