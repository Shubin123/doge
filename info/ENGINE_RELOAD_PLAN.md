# In-Engine Reload System Implementation Plan

## Overview
This document outlines the implementation plan for adding a true "in-engine" reload system that drops the game into a fresh session without quitting the Love2D process. This allows for hot-reloading mods, resetting game state, and capturing startup logs.

## Current State Analysis

### Existing Hot-Reload Mechanism
- Currently uses `love.event.push("quit", "restart")` to restart the entire Love2D process
- Works but loses console state and requires full process restart
- `lurker.lua` handles file watching for automatic reloads

### Mod System Architecture (from how2mod.md)
- Engine maintains absolute control over all subsystems
- Mods are pure data/logic providers with no direct system access
- All operations go through controlled APIs
- Perfect for hot-reloading since mods have no direct system dependencies

## Implementation Strategy

### Phase 1: Engine State Management

Create a centralized state manager that tracks all subsystems:

```lua
-- src/systems/engine_state.lua
local engineState = {
    states = {
        RUNNING = "running",
        RELOADING = "reloading", 
        VOID = "void",
        INITIALIZING = "initializing"
    },
    
    subsystems = {
        -- Track initialization order
        {name = "renderer", instance = nil, init = nil, cleanup = nil},
        {name = "physics", instance = nil, init = nil, cleanup = nil},
        {name = "audio", instance = nil, init = nil, cleanup = nil},
        {name = "network", instance = nil, init = nil, cleanup = nil},
        {name = "mods", instance = nil, init = nil, cleanup = nil}
    },
    
    gameState = {
        playerPosition = nil,
        currentMap = nil,
        modList = {}
    }
}
```

### Phase 2: Teardown Sequence

Implement proper cleanup in reverse initialization order:

1. **Save Critical State**
   - Player position and stats
   - Active mod list
   - Network connection info (if multiplayer)

2. **Mod System Teardown**
   ```lua
   function engineState.teardownMods()
       -- Call cleanup on all loaded mods
       for modId, mod in pairs(modSystem.loadedMods) do
           if mod.instance and mod.instance.cleanup then
               mod.instance.cleanup()
           end
       end
       -- Clear mod registries
       modSystem.loadedMods = {}
       modSystem.apis = {}
   end
   ```

3. **Physics World Cleanup**
   ```lua
   function engineState.teardownPhysics()
       -- Destroy all bodies
       for _, body in pairs(world:getBodies()) do
           body:destroy()
       end
       -- Destroy the world
       world:destroy()
       world = nil
   end
   ```

4. **Renderer Cleanup**
   ```lua
   function engineState.teardownRenderer()
       -- Clear all render queues
       rendererPlus.clearAll()
       -- Reset shader state
       shader.reset()
       -- Clear texture cache (optional)
   end
   ```

### Phase 3: Void State Implementation

While reloading, maintain minimal functionality:

```lua
function engineState.enterVoid()
    -- Clear everything except basic rendering
    engineState.currentState = engineState.states.VOID
    
    -- Keep player entity but remove from physics
    if player and player.body then
        player.voidPosition = {x = player.x, y = player.y}
        player.body:destroy()
        player.body = nil
    end
    
    -- Show loading UI
    local function drawVoid()
        love.graphics.clear(0.1, 0.1, 0.1)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Engine Reloading...", W/2 - 50, H/2)
        
        -- Allow player movement in void
        if player then
            love.graphics.circle("fill", player.voidPosition.x, player.voidPosition.y, 10)
        end
    end
    
    -- Minimal update for void movement
    local function updateVoid(dt)
        if player and love.keyboard.isDown("w", "a", "s", "d") then
            -- Basic WASD movement in void
        end
    end
end
```

### Phase 4: Reinitialization Sequence

Follow the base game sequence as specified:

1. **Asset Loading**
   ```lua
   function engineState.loadAssets()
       -- Reload textures
       rendererPlus.loadTextures()
       -- Reload sounds
       audioSystem.loadSounds()
       -- Verify integrity
       return assetManager.verifyAssets()
   end
   ```

2. **Rendering System**
   ```lua
   function engineState.initRenderer()
       -- Initialize queues
       rendererPlus.init()
       -- Load shaders
       shader.loadAll()
       -- Setup camera
       camera.reset()
   end
   ```

3. **Physics System**
   ```lua
   function engineState.initPhysics()
       -- Create new world
       world = love.physics.newWorld(0, 0)
       -- Register callbacks
       world:setCallbacks(beginContact, endContact, preSolve, postSolve)
       -- Rebuild collision categories
       setupCollisionCategories()
   end
   ```

4. **Mod System**
   ```lua
   function engineState.initMods()
       -- Scan mod directory
       modSystem.scanMods()
       -- Load mods in dependency order
       modSystem.loadAll()
       -- Verify all APIs registered
       modSystem.verifyAPIs()
   end
   ```

5. **Player Spawn**
   ```lua
   function engineState.spawnPlayer()
       -- Create player after mods loaded
       if player and player.voidPosition then
           -- Restore position from void
           player.spawn(player.voidPosition.x, player.voidPosition.y)
       else
           -- Default spawn
           player.spawn(W/2, H/2)
       end
   end
   ```

### Phase 5: Command Integration

Update cmndX.lua to add the new command:

```lua
elseif tokens[1] == "logs" and tokens[2] == "engineStart" then
    -- Set flag for auto-opening logs
    cmdn.engineReloadFlag = true
    -- Clear current buffer
    gameLogsBuffer = {}
    -- Initiate reload
    engineState.startReload()
    cmdn.addOutput("Initiating engine hot-reload...", outputColor)
```

### Phase 6: Network Coordination

For multiplayer compatibility:

```lua
function engineState.handleMultiplayerReload()
    if multiplayer.isHost() then
        -- Notify clients of pending reload
        multiplayer.broadcast({
            type = "engine_reload",
            timestamp = love.timer.getTime()
        })
        -- Wait for client acknowledgments
        engineState.waitForClients()
    elseif multiplayer.isClient() then
        -- Disconnect gracefully
        multiplayer.disconnect()
        -- Show reconnect UI after reload
        engineState.showReconnectUI = true
    end
end
```

## Integration Points

### Main.lua Modifications

```lua
-- Add to love.update
function love.update(dt)
    if engineState.isReloading() then
        engineState.updateReload(dt)
        return
    end
    -- Normal update logic
end

-- Add to love.draw  
function love.draw()
    if engineState.isReloading() then
        engineState.drawReload()
        return
    end
    -- Normal draw logic
end
```

### Memory Management

- Use weak tables for temporary references
- Explicitly nil out large objects during teardown
- Force garbage collection after teardown:
  ```lua
  collectgarbage("collect")
  collectgarbage("collect") -- Run twice to ensure cleanup
  ```

## Testing Strategy

1. **Basic Reload Test**
   - Run `logs engineStart`
   - Verify game reloads without crash
   - Check that startup logs appear

2. **State Preservation Test**
   - Set player position
   - Reload engine
   - Verify player spawns at saved position

3. **Mod Reload Test**
   - Load several mods
   - Make changes to a mod file
   - Reload and verify changes applied

4. **Multiplayer Test**
   - Start host and client
   - Host runs reload
   - Verify client handles disconnection gracefully

## Risks and Mitigations

### Risk 1: Memory Leaks
**Mitigation**: Implement thorough cleanup callbacks and use weak references

### Risk 2: Circular Dependencies
**Mitigation**: Use dependency injection pattern for subsystems

### Risk 3: Network Desync
**Mitigation**: Force full reconnection after reload

### Risk 4: Asset Corruption
**Mitigation**: Verify asset integrity before completing reload

## Implementation Order

1. Create engine_state.lua with basic structure (Day 1)
2. Implement teardown functions for each subsystem (Day 2)
3. Create void state with minimal functionality (Day 2)
4. Implement reinitialization sequence (Day 3)
5. Integrate with cmndX.lua commands (Day 3)
6. Add multiplayer coordination (Day 4)
7. Extensive testing and debugging (Day 4-5)

## Success Criteria

- [ ] Engine reloads without quitting Love2D process
- [ ] Console remains open and captures startup logs
- [ ] Player can move in void state during reload
- [ ] All mods reload correctly with changes applied
- [ ] Multiplayer handles reload gracefully
- [ ] No memory leaks after multiple reloads
- [ ] Reload completes in under 2 seconds

## Future Enhancements

1. **Partial Reloads**: Reload only specific subsystems
2. **Hot-Swap Mods**: Reload individual mods without full reset
3. **Reload Profiles**: Save/load different game configurations
4. **Reload Hooks**: Allow mods to register pre/post reload callbacks
5. **Progressive Loading**: Show detailed progress during reload