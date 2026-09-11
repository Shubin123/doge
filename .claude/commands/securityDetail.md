# Security System Documentation

This document provides detailed information about the game's security architecture for console command execution and P2P multiplayer permissions, extending the core principles from the original overview.

## Overview

The security system uses a **sandbox-by-execution** approach rather than removing globals from the game environment. This ensures game systems function normally while securing user-executed console commands.

## Architecture

### Two-Layer Security System

1. **Execution Sandbox** (`src/security/sandbox.lua`)
   - Validates and restricts console-executed code only
   - Game systems remain unaffected
   - Uses restricted execution environments

2. **P2P Permission System** (`src/security/p2p_permissions.lua`)
   - Manages user permissions in multiplayer
   - Host-controlled permission granting
   - Network-synchronized permission state

## Security Implementation

### Sandbox Security (sandbox.lua)

**Key Principle**: Security through execution-time restriction, NOT global removal.

#### Initialization Phases:
- `sandbox.initBasic()` - Called during game load, does nothing invasive
- `sandbox.init()` - Called when console first opens, sets up validation
- **CRITICAL**: No globals are ever removed from the main game environment

#### Code Validation:
```lua
-- Dangerous patterns blocked in console code:
local dangerous_patterns = {
    "io%.open", "io%.read", "io%.write", "io%.popen",
    "os%.execute", "os%.exit", "os%.remove", "os%.rename", 
    "loadfile", "dofile",
    "debug%.getupvalue", "debug%.setupvalue",
    "package%.loadlib"
}

-- Suspicious patterns flagged:
local suspicious_patterns = {
    "while%s+true",           -- Infinite loops
    "for%s+.-%s+do%s*$",     -- Potential infinite loops
    "getmetatable", "setmetatable", -- Metatable manipulation
    "rawget", "rawset"        -- Raw access bypassing metamethods
}
```

#### Execution Environment:
- Each console command runs in a `createRestrictedEnvironment()`
- Environment populated based on user's permission level
- Safe implementations of `load()` and `print()` provided

### P2P Permission System (p2p_permissions.lua)

**Key Principle**: Host controls all permission changes, automatic network sync.

#### Permission Levels:
1. **Guest (1)**: Read-only access, basic functions
2. **Player (2)**: Normal gameplay (teleport, save/load) - Default for joining players
3. **Admin (3)**: Map editing, advanced functions  
4. **Developer (4)**: Full access - Default for host

#### Host Authority:
```lua
-- Only host can change permissions
function p2p_permissions.setPlayerPermission(target_player_id, level, requesting_player_id)
    if requesting_player_id ~= host_player_id then
        return false, "Only the host can change permissions"
    end
    -- ...
end
```

#### Network Synchronization:
- Permission changes automatically broadcast to all players
- Host transfer on disconnect (highest permission player becomes new host)
- Message types: `"permission_change"`, `"host_transfer"`

## Console Integration (cmndX.lua)

### Security Activation:
```lua
-- Security initializes when console first opens
function cmdn.toggle()
    if isActive then
        ensureSandboxInitialized()  -- Full security active
        -- ...
    end
end
```

### Command Execution:
```lua
-- All console commands go through security validation
local valid, errors = sandbox.validateCode(cmd)
if not valid then
    -- Show security errors
end

local success, result = sandbox.executeCode(cmd, permission_level)
```

### Permission Commands:
- `perms.list` - Show all player permissions (any user)
- `perms.me` - Show your permission level (any user) 
- `perms.grant ID LEVEL` - Grant permission (host only)
- `security.level` - Show current permission level
- `security.setlevel N` - Set local permission level

## Whitelisted Functions by Permission Level

### Guest (Level 1):
```lua
"print", "tostring", "tonumber", "type", "pairs", "ipairs",
"math.floor", "math.ceil", "math.abs", "math.min", "math.max",
"string.len", "string.sub", "string.find", "string.match",
"player.body:getPosition", "player.body:getX", "player.body:getY",
"var.game_width", "var.game_height", "love.graphics.getWidth", "love.graphics.getHeight"
```

### Player (Level 2) - Adds:
```lua
"player.body:setPosition", "player.body:setX", "player.body:setY",
"serial.quickSave", "serial.quickLoad",
"camera.setPosition", "camera.getPosition",
"math", "string", "table.insert", "table.remove", "table.sort"
```

### Admin (Level 3) - Adds:
```lua
"map.createArches", "map.createTree", "map.clearDynamicObjects",
"editor.setEnabled", "editor.getMode", "editor.isEnabled",
"border.create", "border.destroy", "border.resize",
"enemy.spawn", "gun.reload"
```

### Developer (Level 4) - Adds:
```lua
"love", "world", "_G"  -- Full access (use with caution)
```

## Development Guidelines

### Adding New Secure Functions:

1. **Add to appropriate permission level**:
   ```lua
   -- In sandbox.lua WHITELIST
   [SECURITY_CONFIG.PERMISSION_LEVELS.PLAYER] = {
       -- existing functions...
       "your_new_function",
   }
   ```

2. **Test at different permission levels**:
   ```lua
   -- In console
   security.setlevel 2
   your_new_function()  -- Should work at Player level
   
   security.setlevel 1  
   your_new_function()  -- Should be blocked at Guest level
   ```

### Adding New Dangerous Patterns:

```lua
-- In sandbox.lua dangerous_patterns
local dangerous_patterns = {
    -- existing patterns...
    "your_dangerous_pattern",
}
```

### **CRITICAL WARNING**: Game System Integration

**DO NOT** modify the sandbox to remove globals during game initialization. This will break:
- Moonshine graphics effects (`require`, `load` functions needed)
- Module loading system
- Game state initialization
- Physics world setup

**Safe approach**: Only restrict console-executed code through execution environments.

## Security Considerations

### What This System Prevents:
- ✅ File system access from console commands
- ✅ OS command execution from console
- ✅ Malicious code loading via console
- ✅ Unauthorized permission escalation in multiplayer
- ✅ Memory/metatable manipulation from console
- ✅ Infinite loops and resource exhaustion

### What This System Allows:
- ✅ Game systems to function normally (require, load, debug, etc.)
- ✅ Legitimate game functions based on permission level
- ✅ Host control over multiplayer permissions
- ✅ Safe console debugging and gameplay modification

### Potential Attack Vectors:
- **Metatable bypass**: Blocked by pattern detection
- **Global environment pollution**: Prevented by restricted execution environment
- **Permission spoofing**: Prevented by host authority and network validation
- **Resource exhaustion**: Limited by execution time limits and code length restrictions

## Troubleshooting

### "Cannot modify global environment" Error:
- This should NOT occur with current implementation
- If it does, check that `sandbox.init()` is not removing globals
- Verify two-phase initialization is working correctly

### "Forbidden function" Errors:
- Check if the function is in the dangerous_patterns list
- Verify user has appropriate permission level
- Consider if function should be whitelisted for that permission level

### Moonshine/Graphics Errors:
- Ensure game systems can access `require`, `load`, etc.
- Security should only restrict console-executed code
- Game initialization should be unaffected by security system
- Use cascading fallbacks for missing effects

### Permission Sync Issues:
- Check network connectivity
- Verify host hasn't disconnected (triggers host transfer)
- Ensure all players have same game version

## Testing Procedures

### Security Testing:
```lua
-- Test permission boundaries
security.setlevel 1
io.open("/etc/passwd")        -- Should be blocked
player.body:getPosition()     -- Should work

security.setlevel 2
player.body:setPosition(0,0)  -- Should work
map.createArches(100,100)     -- Should be blocked

security.setlevel 3
map.createArches(100,100)     -- Should work
```

### P2P Testing:
1. Start game as host (auto Developer level)
2. Have second player join (auto Player level)
3. Test permission granting from host console
4. Verify network synchronization
5. Test host transfer on disconnect

## Future Enhancements

### Potential Additions:
1. **Code signing** for trusted scripts
2. **Resource monitoring** (memory, CPU usage)
3. **Audit logging** of permission changes and command execution
4. **Time-based permissions** (temporary admin access)
5. **Role-based permissions** (specific function sets)

### Performance Optimizations:
1. **Caching** of validated code patterns
2. **Lazy loading** of permission validation
3. **Batch permission** updates for multiple players

---

**Remember**: The security system should be **invisible to game systems** and **protective for console users**. Any changes that affect game initialization or module loading should be carefully reviewed.