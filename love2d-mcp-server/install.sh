#!/bin/bash

# Love2D Documentation MCP Server Installation Script
# This script installs the Love2D documentation lookup MCP server for Claude Code

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
SERVER_NAME="love2d-docs"
SERVER_DIR="$HOME/.claude-mcp-servers/love2d-docs"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${GREEN}🎮 Love2D Documentation MCP Server Installer${NC}"
echo "================================================"

# Check if Claude CLI is installed
if ! command -v claude &> /dev/null; then
    echo -e "${RED}❌ Error: Claude CLI not found!${NC}"
    echo "Please install Claude Code CLI first:"
    echo "npm install -g @anthropic-ai/claude-code"
    exit 1
fi

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Error: Python 3 not found!${NC}"
    echo "Please install Python 3.8 or higher"
    exit 1
fi

# Create server directory
echo -e "${YELLOW}📁 Creating server directory...${NC}"
mkdir -p "$SERVER_DIR"

# Copy server file
echo -e "${YELLOW}📝 Copying server files...${NC}"
cp "$CURRENT_DIR/server.py" "$SERVER_DIR/"
chmod +x "$SERVER_DIR/server.py"

# Remove any existing MCP configuration for this server
echo -e "${YELLOW}🔧 Removing any existing configuration...${NC}"
claude mcp remove "$SERVER_NAME" 2>/dev/null || true

# Add the server to Claude with user scope (global access)
echo -e "${YELLOW}🔧 Adding server to Claude Code (global scope)...${NC}"
claude mcp add --scope user "$SERVER_NAME" python3 "$SERVER_DIR/server.py"

# Verify installation
echo -e "${YELLOW}✓ Verifying installation...${NC}"
if claude mcp list | grep -q "$SERVER_NAME"; then
    echo -e "${GREEN}✅ Love2D Documentation MCP Server installed successfully!${NC}"
    echo ""
    echo -e "${GREEN}🎮 Available commands in Claude Code:${NC}"
    echo "  • mcp__${SERVER_NAME}__search_love2d"
    echo "    Search Love2D documentation"
    echo ""
    echo "  • mcp__${SERVER_NAME}__get_love2d_module"
    echo "    Get info about a specific module"
    echo ""
    echo "  • mcp__${SERVER_NAME}__get_love2d_example"
    echo "    Get example code for common patterns"
    echo ""
    echo "  • mcp__${SERVER_NAME}__refresh_love2d_cache"
    echo "    Refresh the documentation cache"
    echo ""
    echo -e "${YELLOW}💡 Example usage:${NC}"
    echo "  claude"
    echo "  mcp__love2d-docs__search_love2d"
    echo "    query: \"love.graphics.draw\""
    echo ""
    echo -e "${YELLOW}📍 Server location:${NC} $SERVER_DIR"
else
    echo -e "${RED}❌ Installation may have failed. Please check the output above.${NC}"
    exit 1
fi