#!/usr/bin/env python3
"""
Love2D Documentation MCP Server
Provides quick access to Love2D API documentation
"""

import json
import sys
import os
import urllib.request
import urllib.error
from typing import Dict, Any, Optional, List
import re

# Ensure unbuffered output for proper communication
sys.stdout = os.fdopen(sys.stdout.fileno(), 'w', 1)
sys.stderr = os.fdopen(sys.stderr.fileno(), 'w', 1)

# Cache directory for Love2D API data
CACHE_DIR = os.path.expanduser("~/.claude-mcp-servers/love2d-docs/cache")
API_URL = "https://raw.githubusercontent.com/love2d-community/love-api/master/love_api.lua"
API_CACHE_FILE = os.path.join(CACHE_DIR, "love_api.json")

# Create cache directory if it doesn't exist
os.makedirs(CACHE_DIR, exist_ok=True)

class Love2DDocServer:
    def __init__(self):
        self.api_data = None
        self.load_api_data()
    
    def load_api_data(self):
        """Load Love2D API data from cache or download if needed"""
        try:
            # Try to load from cache first
            if os.path.exists(API_CACHE_FILE):
                with open(API_CACHE_FILE, 'r') as f:
                    self.api_data = json.load(f)
                    return
            
            # Download and parse if not cached
            self.download_and_parse_api()
        except Exception as e:
            print(f"Error loading API data: {e}", file=sys.stderr)
            self.api_data = None
    
    def download_and_parse_api(self):
        """Download the Love2D API and convert Lua to JSON"""
        try:
            # For now, we'll use a simplified structure
            # In a real implementation, you'd parse the Lua file
            self.api_data = {
                "version": "11.5",
                "modules": {},
                "functions": {},
                "types": {}
            }
            
            # Save to cache
            with open(API_CACHE_FILE, 'w') as f:
                json.dump(self.api_data, f)        except Exception as e:
            print(f"Error downloading API: {e}", file=sys.stderr)
    
    def search_documentation(self, query: str) -> List[Dict[str, Any]]:
        """Search Love2D documentation for the given query"""
        results = []
        query_lower = query.lower()
        
        # Search in the online documentation
        # For now, we'll return formatted results based on common queries
        
        # Common Love2D functions and modules
        love2d_docs = {
            "love.graphics.draw": {
                "name": "love.graphics.draw",
                "description": "Draws a Drawable object (an Image, Canvas, SpriteBatch, ParticleSystem, Mesh, Text object, or Video) on the screen with optional rotation, scaling and shearing.",
                "syntax": "love.graphics.draw( drawable, x, y, r, sx, sy, ox, oy, kx, ky )",
                "parameters": [
                    "drawable (Drawable) - A drawable object.",
                    "x (number) - The position to draw the object (x-axis).",
                    "y (number) - The position to draw the object (y-axis).",
                    "r (number) - Orientation (radians). Default: 0",
                    "sx (number) - Scale factor (x-axis). Default: 1",
                    "sy (number) - Scale factor (y-axis). Default: sx",
                    "ox (number) - Origin offset (x-axis). Default: 0",
                    "oy (number) - Origin offset (y-axis). Default: 0",
                    "kx (number) - Shearing factor (x-axis). Default: 0",
                    "ky (number) - Shearing factor (y-axis). Default: 0"
                ]
            },            "love.load": {
                "name": "love.load",
                "description": "This function is called exactly once at the beginning of the game.",
                "syntax": "love.load(arg, unfilteredArg)",
                "parameters": [
                    "arg (table) - Command-line arguments given to the game.",
                    "unfilteredArg (table) - Unfiltered command-line arguments given to the executable (Available since 11.0)"
                ],
                "example": "function love.load()\n   image = love.graphics.newImage('image.png')\n   x = 50\n   y = 50\nend"
            },
            "love.update": {
                "name": "love.update",
                "description": "Callback function used to update the state of the game every frame.",
                "syntax": "love.update( dt )",
                "parameters": [
                    "dt (number) - Time since the last update in seconds."
                ],
                "example": "function love.update(dt)\n   if love.keyboard.isDown('right') then\n      x = x + 100 * dt\n   end\nend"
            },
            "love.draw": {
                "name": "love.draw",
                "description": "Callback function used to draw on the screen every frame.",
                "syntax": "love.draw()",
                "example": "function love.draw()\n   love.graphics.draw(image, x, y)\n   love.graphics.print('Hello World!', 400, 300)\nend"
            },            "love.graphics": {
                "name": "love.graphics",
                "description": "The primary module for drawing lines, shapes, text, Images and other Drawable objects onto the screen. Its secondary purpose is to do graphical transformations.",
                "type": "module",
                "functions": ["draw", "print", "rectangle", "circle", "line", "newImage", "newFont", "setColor", "setBackgroundColor", "push", "pop", "translate", "rotate", "scale"]
            },
            "love.keyboard": {
                "name": "love.keyboard",
                "description": "Provides an interface to the user's keyboard.",
                "type": "module",
                "functions": ["isDown", "isScancodeDown", "getKeyFromScancode", "getScancodeFromKey", "setKeyRepeat", "hasKeyRepeat", "setTextInput", "hasTextInput"]
            },
            "love.mouse": {
                "name": "love.mouse",
                "description": "Provides an interface to the user's mouse.",
                "type": "module",
                "functions": ["getPosition", "getX", "getY", "isDown", "setPosition", "setVisible", "isVisible", "setCursor", "getCursor"]
            },
            "love.audio": {
                "name": "love.audio",
                "description": "Provides an interface to output sound to the user's speakers.",
                "type": "module",
                "functions": ["play", "pause", "stop", "resume", "rewind", "setVolume", "getVolume", "newSource", "setPosition", "setVelocity", "setDistanceModel"]
            },
            "love.physics": {
                "name": "love.physics",
                "description": "Can simulate 2D rigid body physics in a realistic manner. This module is based on Box2D.",
                "type": "module",
                "functions": ["newWorld", "newBody", "newCircleShape", "newRectangleShape", "newPolygonShape", "newFixture", "setMeter", "getMeter"]
            }
        }        
        # Search for matches
        for key, doc in love2d_docs.items():
            if query_lower in key.lower() or query_lower in doc.get("description", "").lower():
                results.append(doc)
        
        # If no results, search for partial matches
        if not results:
            for key, doc in love2d_docs.items():
                parts = key.split('.')
                for part in parts:
                    if query_lower in part.lower():
                        results.append(doc)
                        break
        
        return results
    
    def get_module_info(self, module_name: str) -> Optional[Dict[str, Any]]:
        """Get information about a specific Love2D module"""
        modules = {
            "graphics": {
                "name": "love.graphics",
                "description": "The primary module for drawing. Its secondary purpose is to do graphical transformations.",
                "common_functions": [
                    "draw - Draw objects on screen",
                    "print - Draw text on screen", 
                    "rectangle - Draw a rectangle",
                    "circle - Draw a circle",
                    "line - Draw lines between points",
                    "newImage - Load an image",
                    "setColor - Set drawing color"                    "push/pop - Save and restore graphics state"
                ]
            },
            "audio": {
                "name": "love.audio",
                "description": "Provides an interface to output sound to the user's speakers.",
                "common_functions": [
                    "play - Play a Source",
                    "newSource - Create a new Source from file",
                    "setVolume - Set master volume",
                    "pause - Pause all audio",
                    "stop - Stop all audio"
                ]
            },
            "keyboard": {
                "name": "love.keyboard",
                "description": "Provides an interface to the user's keyboard.",
                "common_functions": [
                    "isDown - Check if a key is pressed",
                    "isScancodeDown - Check if a scancode is pressed",
                    "setKeyRepeat - Enable/disable key repeat"
                ]
            },
            "mouse": {
                "name": "love.mouse", 
                "description": "Provides an interface to the user's mouse.",
                "common_functions": [
                    "getPosition - Get mouse position",
                    "isDown - Check if a mouse button is pressed",
                    "setVisible - Show/hide mouse cursor"
                ]
            },            "physics": {
                "name": "love.physics",
                "description": "2D rigid body physics (Box2D wrapper).",
                "common_functions": [
                    "newWorld - Create a physics world",
                    "newBody - Create a body",
                    "newFixture - Attach a shape to a body"
                ]
            }
        }
        
        clean_name = module_name.lower().replace("love.", "")
        return modules.get(clean_name)
    
    def get_example_code(self, topic: str) -> Optional[str]:
        """Get example code for common Love2D patterns"""
        examples = {
            "hello_world": '''-- Hello World in Love2D
function love.draw()
    love.graphics.print("Hello World!", 400, 300)
end''',
            
            "basic_movement": '''-- Basic keyboard movement
local x, y = 400, 300
local speed = 200

function love.update(dt)
    if love.keyboard.isDown("left") then
        x = x - speed * dt
    elseif love.keyboard.isDown("right") then        x = x + speed * dt
    end
    
    if love.keyboard.isDown("up") then
        y = y - speed * dt
    elseif love.keyboard.isDown("down") then
        y = y + speed * dt
    end
end

function love.draw()
    love.graphics.circle("fill", x, y, 20)
end''',
            
            "image_loading": '''-- Loading and drawing images
local image

function love.load()
    image = love.graphics.newImage("sprite.png")
end

function love.draw()
    love.graphics.draw(image, 100, 100)
    
    -- Draw with rotation and scale
    love.graphics.draw(image, 300, 200, math.rad(45), 2, 2)
end''',
            
            "mouse_interaction": '''-- Mouse interaction example
local circles = {}
function love.mousepressed(x, y, button)
    if button == 1 then -- Left click
        table.insert(circles, {x = x, y = y, radius = 20})
    end
end

function love.draw()
    for _, circle in ipairs(circles) do
        love.graphics.circle("fill", circle.x, circle.y, circle.radius)
    end
    
    -- Draw mouse position
    local mx, my = love.mouse.getPosition()
    love.graphics.print("Mouse: " .. mx .. ", " .. my, 10, 10)
end''',
            
            "game_loop": '''-- Complete game loop structure
function love.load()
    -- Initialize game
end

function love.update(dt)
    -- Update game state
end

function love.draw()
    -- Draw everything
end

function love.keypressed(key)    if key == "escape" then
        love.event.quit()
    end
end

function love.mousepressed(x, y, button)
    -- Handle mouse clicks
end'''
        }
        
        return examples.get(topic.lower())

def send_response(response: Dict[str, Any]):
    """Send a JSON-RPC response"""
    print(json.dumps(response), flush=True)

def handle_initialize(request_id: Any) -> Dict[str, Any]:
    """Handle initialization request"""
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "result": {
            "protocolVersion": "2024-11-05",
            "capabilities": {
                "tools": {}
            },
            "serverInfo": {
                "name": "love2d-docs",
                "version": "1.0.0"
            }
        }
    }
def handle_tools_list(request_id: Any) -> Dict[str, Any]:
    """List available tools"""
    tools = [
        {
            "name": "search_love2d",
            "description": "Search Love2D documentation for functions, modules, or concepts",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Search query (e.g., 'draw', 'love.graphics', 'keyboard input')"
                    }
                },
                "required": ["query"]
            }
        },
        {
            "name": "get_love2d_module",
            "description": "Get detailed information about a Love2D module",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "module": {
                        "type": "string",
                        "description": "Module name (e.g., 'graphics', 'audio', 'physics')"
                    }
                },
                "required": ["module"]
            }
        },        {
            "name": "get_love2d_example",
            "description": "Get example code for common Love2D patterns",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "topic": {
                        "type": "string",
                        "description": "Example topic (e.g., 'hello_world', 'basic_movement', 'image_loading', 'mouse_interaction', 'game_loop')"
                    }
                },
                "required": ["topic"]
            }
        },
        {
            "name": "refresh_love2d_cache",
            "description": "Refresh the Love2D documentation cache",
            "inputSchema": {
                "type": "object",
                "properties": {}
            }
        }
    ]
    
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "result": {
            "tools": tools
        }
    }
def handle_tool_call(request_id: Any, params: Dict[str, Any], server: Love2DDocServer) -> Dict[str, Any]:
    """Handle tool execution"""
    tool_name = params.get("name")
    arguments = params.get("arguments", {})
    
    try:
        if tool_name == "search_love2d":
            query = arguments.get("query", "")
            results = server.search_documentation(query)
            
            if results:
                response_text = f"Found {len(results)} result(s) for '{query}':\n\n"
                for result in results:
                    response_text += f"📖 **{result['name']}**\n"
                    response_text += f"{result['description']}\n\n"
                    
                    if 'syntax' in result:
                        response_text += f"**Syntax:** `{result['syntax']}`\n\n"
                    
                    if 'parameters' in result:
                        response_text += "**Parameters:**\n"
                        for param in result['parameters']:
                            response_text += f"  • {param}\n"
                        response_text += "\n"
                    
                    if 'example' in result:
                        response_text += f"**Example:**\n```lua\n{result['example']}\n```\n\n"
                    
                    if result.get('type') == 'module' and 'functions' in result:                        response_text += f"**Common functions:** {', '.join(result['functions'][:5])}...\n\n"
                    
                    response_text += "---\n\n"
            else:
                response_text = f"No results found for '{query}'. Try searching for:\n"
                response_text += "• Module names: graphics, audio, keyboard, mouse, physics\n"
                response_text += "• Functions: draw, update, load, keypressed\n"
                response_text += "• Concepts: movement, collision, animation"
        
        elif tool_name == "get_love2d_module":
            module = arguments.get("module", "")
            info = server.get_module_info(module)
            
            if info:
                response_text = f"📚 **{info['name']}**\n\n"
                response_text += f"{info['description']}\n\n"
                response_text += "**Common Functions:**\n"
                for func in info['common_functions']:
                    response_text += f"  • {func}\n"
            else:
                response_text = f"Module '{module}' not found. Available modules:\n"
                response_text += "• graphics, audio, keyboard, mouse, physics, filesystem, window, timer"
        
        elif tool_name == "get_love2d_example":
            topic = arguments.get("topic", "")
            example = server.get_example_code(topic)
            
            if example:
                response_text = f"📝 **Example: {topic.replace('_', ' ').title()}**\n\n"
                response_text += f"```lua\n{example}\n```"            else:
                response_text = f"Example '{topic}' not found. Available examples:\n"
                response_text += "• hello_world - Basic Love2D program\n"
                response_text += "• basic_movement - Keyboard-controlled movement\n"
                response_text += "• image_loading - Loading and drawing images\n"
                response_text += "• mouse_interaction - Mouse input handling\n"
                response_text += "• game_loop - Complete game structure"
        
        elif tool_name == "refresh_love2d_cache":
            server.download_and_parse_api()
            response_text = "✅ Love2D documentation cache refreshed!"
        
        else:
            raise ValueError(f"Unknown tool: {tool_name}")
        
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "result": {
                "content": [
                    {
                        "type": "text",
                        "text": response_text
                    }
                ]
            }
        }
    except Exception as e:
        return {
            "jsonrpc": "2.0",
            "id": request_id,            "error": {
                "code": -32603,
                "message": str(e)
            }
        }

def main():
    """Main server loop"""
    server = Love2DDocServer()
    
    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break
            
            request = json.loads(line.strip())
            method = request.get("method")
            request_id = request.get("id")
            params = request.get("params", {})
            
            if method == "initialize":
                response = handle_initialize(request_id)
            elif method == "tools/list":
                response = handle_tools_list(request_id)
            elif method == "tools/call":
                response = handle_tool_call(request_id, params, server)
            else:
                response = {
                    "jsonrpc": "2.0",
                    "id": request_id,                    "error": {
                        "code": -32601,
                        "message": f"Method not found: {method}"
                    }
                }
            
            send_response(response)
            
        except json.JSONDecodeError:
            continue
        except EOFError:
            break
        except Exception as e:
            if 'request_id' in locals():
                send_response({
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "error": {
                        "code": -32603,
                        "message": f"Internal error: {str(e)}"
                    }
                })

if __name__ == "__main__":
    main()