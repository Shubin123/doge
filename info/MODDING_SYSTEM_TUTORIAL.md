# DogeGame Modding System Tutorial

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Getting Started](#getting-started)
4. [Creating Your First Mod](#creating-your-first-mod)
5. [Mod API Reference](#mod-api-reference)
6. [Advanced Features](#advanced-features)
7. [Complex Mod Patterns](#complex-mod-patterns)
8. [Multi-Agent Migration Examples](#multi-agent-migration-examples)
9. [Multiplayer & Networking](#multiplayer--networking)
10. [Performance Optimization](#performance-optimization)
11. [Best Practices](#best-practices)
12. [Security Guidelines](#security-guidelines)
13. [Troubleshooting](#troubleshooting)

---

## Overview

The DogeGame Modding System separates the core game engine from content, enabling dynamic loading and sharing of custom game elements. This system allows developers to create mods for entities, maps, enemies, bosses, and other game features while maintaining engine stability and security.

The system allows for impressive mod combinations - for example, when a
  player shoots an enemy, it triggers a chain across weapons → projectiles
  → enemies → health indicators → blood effects, all coordinated through
  the mod API.

  - AI Behaviors Mod provides reusable AI patterns (aggressive, tactical,
  cautious, patrol, guard)
  - Combat System spans multiple mods (weapons_core_mod → projectiles_mod →
   combat_effects_mod)
  - Visual Effects handled by specialized mods (blood_effects_mod,
  health_damage_mod)
  - Content Mods like bear_boss_mod and glowing_tree_mod showcase complex
  entity systems
  - Inter-mod Communication through standardized exports and hooks
  (onEntityDamage, onEntityDeath, etc.)
  ... and many more! check out the mod lists!

### Key Benefits
- **Separation of Concerns**: Engine vs Content isolation
- **Dynamic Loading**: Hot-swappable mod system
- **Multiplayer Support**: Real-time mod sharing between players
- **Security**: Sandboxed execution with permission system
- **Performance**: Optimized asset management and rendering and physics collisions. 

---

## Architecture

### Core Components

```
DogeGame/
├── src/
│   ├── engine/
│   │   └── mod_system.lua          # Core mod framework
│   ├── lib/graphics/
│   │   └── new_renderer.lua        # Advanced rendering system
│   └── main.lua                    # Game entry point
└── mods/
    └── [mod_name]/                 # Individual mod directories
        ├── mod_info.json           # Mod metadata
        ├── main.lua               # Mod entry point
        ├── shaders/               # Custom shaders
        ├── assets/                # Textures, sounds
        └── scripts/               # Additional Lua files
```

### System Flow

1. **Engine Initialization**: Core systems (renderer, physics, networking) start
2. **Mod Discovery**: System scans `mods/` directory for valid mods
3. **Mod Loading**: Dependencies resolved, sandboxed execution environments created
4. **Runtime Integration**: Mods register hooks, handlers, and content
5. **Network Synchronization**: Mod states shared across multiplayer sessions

---

## Getting Started

### Prerequisites

Ensure your DogeGame installation includes:
- `src/engine/mod_system.lua` - Core mod framework
- `src/lib/graphics/new_renderer.lua` - Advanced renderer
- Updated `main.lua` with mod system integration

### Verifying Installation

1. Start the game
2. Check console for: `[MOD_SYSTEM] Mod system initialized!`
3. Verify mods directory: `mods/` should exist

---

## Creating Your First Mod

### Step 1: Create Mod Directory

```bash
mkdir mods/my_first_mod
cd mods/my_first_mod
```

### Step 2: Create mod_info.json

**IMPORTANT**: All mod_info.json files must follow this standardized format to ensure compatibility across all mods in the system:

```json
{
    "id": "my_first_mod",
    "name": "My First Mod",
    "version": "1.0.0",
    "author": "Your Name",
    "description": "A simple example mod for learning",
    "engine_version": "1.0.0",
    "dependencies": [],
    "optional_dependencies": [],
    "assets": [],
    "shaders": [],
    "permissions": [
        "renderer.add_effects",
        "input.key_handlers",
        "game.player_access"
    ],
    "configuration": {
        "enable_debug": true
    },
    "hooks": {},
    "exports": [],
    "commands": [],
    "collision_groups": {},
    "weapon_templates": [],
    "projectile_types": [],
    "effect_types": []
}
```

#### Required Field Descriptions:

- **id**: Unique identifier for your mod (must match directory name)
- **name**: Human-readable display name
- **version**: Semantic version (e.g., "1.0.0")
- **author**: Creator or team name
- **description**: Brief explanation of mod functionality
- **engine_version**: Compatible engine version
- **dependencies**: Array of required mods that must load first
- **optional_dependencies**: Array of mods that enhance functionality if present
- **assets**: Array of asset file paths relative to mod directory
- **shaders**: Array of shader file paths relative to mod directory
- **permissions**: Array of API permissions the mod requires
- **configuration**: Object containing mod-specific settings
- **hooks**: Object mapping game events to mod functions
- **exports**: Array of function names other mods can call
- **commands**: Array of chat/console commands the mod provides
- **collision_groups**: Object mapping collision group names to IDs
- **weapon_templates**: Array of weapon template names (for weapon mods)
- **projectile_types**: Array of projectile type names (for projectile mods)
- **effect_types**: Array of effect type names (for visual effect mods)

**Note**: Even if you don't use certain fields (like shaders or weapon_templates), include them as empty arrays/objects to maintain consistency across all mods.

### Step 3: Create main.lua

```lua
-- My First Mod - Main Entry Point
local myFirstMod = {}

-- Mod state
local mod_enabled = true
local debug_mode = true

-- Initialize the mod
function myFirstMod.init(api)
    print("Hello from My First Mod!")
    
    -- Store API reference
    myFirstMod.api = api
    
    -- Register key handler
    api.input.registerKeyHandler("f1", function(key)
        myFirstMod.toggleFeature()
    end)
    
    -- Create initial content
    myFirstMod.createWelcomeEffect()
end

-- Create a welcome particle effect
function myFirstMod.createWelcomeEffect()
    local api = myFirstMod.api
    local player_x, player_y = api.game.getPlayerPosition()
    
    api.renderer.addParticleEffect(
        "welcome_effect",
        player_x, player_y - 30,
        "celebration",
        {
            lifetime = 3.0,
            color = {1, 1, 0, 1},
            count = 10
        }
    )
    
    api.utils.log("Welcome effect created!", "my_first_mod")
end

-- Toggle mod feature
function myFirstMod.toggleFeature()
    mod_enabled = not mod_enabled
    local status = mod_enabled and "enabled" or "disabled"
    print("[MY_FIRST_MOD] Feature " .. status)
end

-- Update function (called every frame)
function myFirstMod.update(dt)
    if not mod_enabled then return end
    
    -- Add your update logic here
end

-- Draw function (called every frame)
function myFirstMod.draw()
    if not mod_enabled then return end
    
    -- Add your rendering logic here
end

-- Cleanup function
function myFirstMod.cleanup()
    print("[MY_FIRST_MOD] Cleanup complete")
end

-- Return mod interface
return myFirstMod
```

### Step 4: Test Your Mod

1. Start the game
2. Check console for: `[MOD_SYSTEM] Loading mod: my_first_mod`
3. Press F1 to toggle the mod feature
4. You should see welcome particles at player spawn

### Step 5: Document Your Mod

After successfully creating and testing your mod, it's important to document it in the comprehensive mod log for future reference and to help other developers understand how your mod integrates with the system.

1. Open `DOGE_MODS_LOG.md` in the root directory
2. Add a new section for your mod following this template:

```markdown
## [Your Mod Number]. [Your Mod Name] (`your_mod_id`)

**Purpose**: [Brief description of what your mod does]

### Exports (Functions other mods can call):
- `functionName(params)` - Description of what this function does
- `anotherFunction(params)` - Another exported function

### Features:
- **Feature 1**: Description
- **Feature 2**: Description

### Commands:
- `/your_command [args]` - Description

### Inter-mod Usage:
- **Uses**: `other_mod.functionName()` for specific functionality
- **Called by**: List of mods that use your exports
- **Dependencies**: List required mods
```

3. Document all exported functions that other mods can call
4. List any commands your mod provides
5. Describe how your mod interacts with other mods
6. Include usage examples where helpful

This documentation step ensures that:
- Other developers can understand your mod's capabilities
- Integration patterns are preserved for future development
- The mod ecosystem remains maintainable and extensible
- New modders can learn from existing implementations

---

## Mod API Reference

### Renderer API

```lua
-- Add objects to render queue
api.renderer.addToQueue(layer, draw_data)

-- Create particle effects
api.renderer.addParticleEffect(name, x, y, effect_type, params)

-- Create particle systems
api.renderer.createParticleSystem(texture_name, buffer_size)

-- Load custom shaders
api.renderer.loadShader(name, vertex_path, fragment_path)

-- Add dynamic lighting
api.renderer.addLight(x, y, radius, color, intensity)

-- Draw sprites
api.renderer.drawSprite(sprite_name, x, y, rotation, scale_x, scale_y, offset_x, offset_y)
```

### Physics API

```lua
-- Create physics bodies
api.physics.createBody(world, x, y, type)

-- Create shapes
api.physics.createShape(radius) -- Circle
api.physics.createShape(width, height) -- Rectangle

-- Create fixtures
api.physics.createFixture(body, shape)
```

### Input API

```lua
-- Register key handlers
api.input.registerKeyHandler(key, callback)

-- Register mouse handlers  
api.input.registerMouseHandler(button, callback)
```

### Game State API

```lua
-- Get player information
local x, y = api.game.getPlayerPosition()
local health = api.game.getPlayerHealth()

-- Modify player state
api.game.setPlayerHealth(new_health)

-- Access physics world
local world = api.game.getWorld()
```

### Network API

```lua
-- Send data to all players
api.network.sendToAll(data, mod_id)

-- Register network message handler
api.network.registerMessageHandler(mod_id, callback)
```

### Utility API

```lua
-- Logging
api.utils.log(message, mod_id)

-- Asset management
local path = api.utils.getAssetPath(mod_id, asset_name)
local texture = api.utils.loadTexture(mod_id, texture_name)
```

---

## Advanced Features

### Custom Shaders

Create `shaders/my_shader.frag`:

```glsl
varying vec4 VaryingTexCoord;
varying vec4 VaryingColor;

uniform sampler2D MainTexture;
uniform float time;
uniform vec3 glow_color;

void main() {
    vec2 uv = VaryingTexCoord.xy;
    vec4 color = texture2D(MainTexture, uv);
    
    // Add glow effect
    float glow = sin(time * 3.0) * 0.5 + 0.5;
    color.rgb += glow_color * glow * 0.3;
    
    gl_FragColor = color;
}
```

Load in mod:
```lua
local shader = api.renderer.loadShader("my_shader", nil, "mods/my_mod/shaders/my_shader.frag")
```

### Entity Systems

Create complex entities with state management:

```lua
local EntityManager = {}
EntityManager.entities = {}

function EntityManager.createEntity(type, x, y)
    local entity = {
        id = #EntityManager.entities + 1,
        type = type,
        x = x, y = y,
        active = true,
        components = {}
    }
    
    table.insert(EntityManager.entities, entity)
    return entity
end

function EntityManager.update(dt)
    for _, entity in ipairs(EntityManager.entities) do
        if entity.active and entity.update then
            entity:update(dt)
        end
    end
end
```

### Configuration Systems

Use mod_info.json configuration:

```lua
function myMod.init(api)
    -- Access configuration from mod_info.json
    local config = myMod.getConfig()
    
    if config.enable_debug then
        api.utils.log("Debug mode enabled", "my_mod")
    end
end

function myMod.getConfig()
    -- Configuration is automatically loaded from mod_info.json
    return {
        enable_debug = true,
        max_entities = 100,
        particle_density = 0.8
    }
end
```

---

## Multiplayer & Networking

### Basic Networking

```lua
-- Send mod data to all players
function myMod.syncEntityCreation(entity)
    api.network.sendToAll({
        action = "create_entity",
        entity_data = {
            id = entity.id,
            type = entity.type,
            x = entity.x,
            y = entity.y
        }
    }, "my_mod")
end

-- Handle incoming network messages
function myMod.handleNetworkMessage(data)
    if data.action == "create_entity" then
        local entity_data = data.entity_data
        myMod.createEntity(entity_data.type, entity_data.x, entity_data.y)
    end
end

-- Register network handler
function myMod.init(api)
    api.network.registerMessageHandler("my_mod", myMod.handleNetworkMessage)
end
```

### Mod Sharing

The mod system automatically handles sharing between players:

1. **Host loads mod** → System detects new mod
2. **Clients get prompt** → "Accept mod from host?"
3. **Upon acceptance** → Mod files transferred
4. **Auto-loading** → Mod initializes on client
5. **State sync** → Real-time synchronization begins

---

## Best Practices

### Performance Optimization

```lua
-- Cache API references
local renderer = api.renderer
local utils = api.utils

-- Limit update frequency for expensive operations
local update_timer = 0
function myMod.update(dt)
    update_timer = update_timer + dt
    
    if update_timer > 0.1 then -- Update every 100ms
        myMod.expensiveOperation()
        update_timer = 0
    end
end

-- Use object pooling for frequent creations
local particle_pool = {}
function myMod.getParticle()
    return table.remove(particle_pool) or myMod.createNewParticle()
end
```

### Error Handling

```lua
function myMod.safeOperation()
    local success, result = pcall(function()
        -- Your potentially error-prone code
        return myMod.riskyFunction()
    end)
    
    if not success then
        api.utils.log("Error in operation: " .. result, "my_mod")
        return nil
    end
    
    return result
end
```

### Memory Management

```lua
function myMod.cleanup()
    -- Clear large data structures
    myMod.entities = {}
    myMod.particle_systems = {}
    
    -- Remove event handlers
    myMod.clearEventHandlers()
    
    api.utils.log("Cleanup complete", "my_mod")
end
```

---

## Security Guidelines

### Restricted Operations

The mod system prevents access to:
- File system writes outside mod directory
- Operating system commands
- Network operations outside game protocol
- Memory manipulation
- Unsafe Lua functions (io, os, require, etc.)

### Safe Patterns

```lua
-- ✅ Safe: Using mod API
local texture = api.utils.loadTexture("my_mod", "sprite.png")

-- ❌ Unsafe: Direct file access
-- local texture = love.graphics.newImage("../system/secrets.txt")

-- ✅ Safe: Using provided logging
api.utils.log("Debug message", "my_mod")

-- ❌ Unsafe: System operations
-- os.execute("rm -rf /")
```

### Validation

The mod system automatically validates:
- File access permissions
- API usage patterns
- Network message formats
- Resource usage limits

---

## Troubleshooting

### Common Issues

**Mod Not Loading**
```
[MOD_SYSTEM] Failed to load mod: my_mod
```
- Check `mod_info.json` syntax
- Verify all required fields present
- Ensure `main.lua` exists and returns a table

**Shader Compilation Errors**
```
[NEW_RENDERER] Failed to load shader: my_shader
```
- Check shader syntax
- Verify uniform variable names
- Test shader with minimal fragment code

**Network Sync Issues**
```
[MOD_SYSTEM] Network handler not found: my_mod
```
- Ensure network handler registered in `init()`
- Check mod_id matches in network calls
- Verify multiplayer mode enabled

### Debug Mode

Enable detailed logging:

```lua
-- In mod_info.json
"configuration": {
    "enable_debug": true,
    "log_level": "verbose"
}

-- In main.lua
function myMod.debugLog(message)
    if myMod.config.enable_debug then
        api.utils.log("[DEBUG] " .. message, "my_mod")
    end
end
```

### Performance Profiling

```lua
local profiler = {}

function profiler.start(name)
    profiler[name] = love.timer.getTime()
end

function profiler.stop(name)
    if profiler[name] then
        local elapsed = love.timer.getTime() - profiler[name]
        api.utils.log(name .. " took " .. (elapsed * 1000) .. "ms", "profiler")
    end
end

-- Usage
profiler.start("entity_update")
myMod.updateEntities(dt)
profiler.stop("entity_update")
```

---

## Example: Complete Entity Mod

Here's a complete example of a more complex mod that adds custom enemies:

### mod_info.json
```json
{
    "id": "custom_enemies_mod",
    "name": "Custom Enemy Pack",
    "version": "1.0.0", 
    "author": "Mod Developer",
    "description": "Adds flying enemies with custom AI and particle effects",
    "permissions": [
        "renderer.add_effects",
        "physics.create_bodies",
        "input.key_handlers",
        "network.sync_entities",
        "game.player_access"
    ],
    "configuration": {
        "max_enemies": 20,
        "spawn_rate": 5.0,
        "enable_ai": true
    }
}
```

### main.lua
```lua
local customEnemiesMod = {}

-- Enemy configuration
local ENEMY_TYPES = {
    FLYER = {
        sprite = "enemy_flyer",
        health = 50,
        speed = 100,
        ai_type = "follow_player"
    },
    GUARDIAN = {
        sprite = "enemy_guardian", 
        health = 120,
        speed = 50,
        ai_type = "patrol_area"
    }
}

-- Mod state
local enemies = {}
local spawn_timer = 0
local enemy_count = 0

-- Initialize mod
function customEnemiesMod.init(api)
    customEnemiesMod.api = api
    
    -- Register input handlers
    api.input.registerKeyHandler("f2", customEnemiesMod.spawnRandomEnemy)
    
    -- Register network handler
    api.network.registerMessageHandler("custom_enemies_mod", customEnemiesMod.handleNetworkMessage)
    
    api.utils.log("Custom Enemies Mod loaded!", "custom_enemies_mod")
end

-- Create enemy
function customEnemiesMod.createEnemy(x, y, enemy_type)
    local config = ENEMY_TYPES[enemy_type]
    if not config then return nil end
    
    enemy_count = enemy_count + 1
    
    local enemy = {
        id = enemy_count,
        x = x, y = y,
        type = enemy_type,
        config = config,
        health = config.health,
        max_health = config.health,
        velocity_x = 0,
        velocity_y = 0,
        active = true,
        ai_state = "idle",
        ai_timer = 0
    }
    
    -- Create physics body
    local world = customEnemiesMod.api.game.getWorld()
    enemy.body = customEnemiesMod.api.physics.createBody(world, x, y, "dynamic")
    enemy.shape = customEnemiesMod.api.physics.createShape(15) -- Circle radius
    enemy.fixture = customEnemiesMod.api.physics.createFixture(enemy.body, enemy.shape)
    
    table.insert(enemies, enemy)
    
    -- Sync with network
    customEnemiesMod.syncEnemyCreation(enemy)
    
    return enemy
end

-- Update enemies
function customEnemiesMod.update(dt)
    local api = customEnemiesMod.api
    
    -- Spawn timer
    spawn_timer = spawn_timer + dt
    if spawn_timer > 5.0 and #enemies < 20 then
        local player_x, player_y = api.game.getPlayerPosition()
        local spawn_x = player_x + (math.random() - 0.5) * 400
        local spawn_y = player_y + (math.random() - 0.5) * 400
        
        customEnemiesMod.createEnemy(spawn_x, spawn_y, "FLYER")
        spawn_timer = 0
    end
    
    -- Update each enemy
    for i = #enemies, 1, -1 do
        local enemy = enemies[i]
        if enemy.active then
            customEnemiesMod.updateEnemy(enemy, dt)
            customEnemiesMod.renderEnemy(enemy)
        else
            table.remove(enemies, i)
        end
    end
end

-- Update individual enemy
function customEnemiesMod.updateEnemy(enemy, dt)
    local api = customEnemiesMod.api
    
    -- AI update
    if enemy.config.ai_type == "follow_player" then
        local player_x, player_y = api.game.getPlayerPosition()
        local dx = player_x - enemy.x
        local dy = player_y - enemy.y
        local distance = math.sqrt(dx*dx + dy*dy)
        
        if distance > 50 then
            enemy.velocity_x = (dx / distance) * enemy.config.speed
            enemy.velocity_y = (dy / distance) * enemy.config.speed
        else
            enemy.velocity_x = 0
            enemy.velocity_y = 0
        end
    end
    
    -- Update position
    enemy.x = enemy.x + enemy.velocity_x * dt
    enemy.y = enemy.y + enemy.velocity_y * dt
    
    -- Update physics body
    if enemy.body then
        enemy.body:setPosition(enemy.x, enemy.y)
    end
end

-- Render enemy
function customEnemiesMod.renderEnemy(enemy)
    local api = customEnemiesMod.api
    
    -- Main enemy sprite
    api.renderer.addToQueue("world", {
        type = "sprite",
        texture_name = "enemy_01", -- Use existing game asset
        x = enemy.x,
        y = enemy.y,
        scale_x = 0.8,
        scale_y = 0.8,
        sort_y = enemy.y + 10,
        active = true,
        color = {1, 0.8, 0.8, 1}
    })
    
    -- Health bar
    if enemy.health < enemy.max_health then
        local health_percent = enemy.health / enemy.max_health
        local bar_width = 30
        
        api.renderer.addToQueue("ui", {
            type = "rectangle",
            mode = "fill",
            x = enemy.x - bar_width/2,
            y = enemy.y - 30,
            width = bar_width * health_percent,
            height = 4,
            sort_y = 10000,
            active = true,
            color = {1, 0, 0, 0.8}
        })
    end
end

-- Input handlers
function customEnemiesMod.spawnRandomEnemy(key)
    local api = customEnemiesMod.api
    local player_x, player_y = api.game.getPlayerPosition()
    
    local types = {"FLYER", "GUARDIAN"}
    local random_type = types[math.random(#types)]
    
    customEnemiesMod.createEnemy(player_x + 50, player_y, random_type)
    api.utils.log("Spawned " .. random_type .. " enemy", "custom_enemies_mod")
end

-- Network synchronization
function customEnemiesMod.syncEnemyCreation(enemy)
    customEnemiesMod.api.network.sendToAll({
        action = "create_enemy",
        enemy_data = {
            id = enemy.id,
            x = enemy.x,
            y = enemy.y,
            type = enemy.type
        }
    }, "custom_enemies_mod")
end

function customEnemiesMod.handleNetworkMessage(data)
    if data.action == "create_enemy" then
        local enemy_data = data.enemy_data
        customEnemiesMod.createEnemy(enemy_data.x, enemy_data.y, enemy_data.type)
    end
end

-- Cleanup
function customEnemiesMod.cleanup()
    for _, enemy in ipairs(enemies) do
        if enemy.body then
            enemy.body:destroy()
        end
    end
    enemies = {}
    customEnemiesMod.api.utils.log("Cleanup complete", "custom_enemies_mod")
end

return customEnemiesMod
```

This example demonstrates:
- Complex entity management
- Physics integration
- AI systems
- Network synchronization
- Resource cleanup
- Input handling
- Custom rendering

---

## Conclusion

The DogeGame Modding System provides a powerful, secure, and flexible framework for extending game functionality. By following this tutorial, developers can create rich, interactive content while maintaining compatibility with the core engine and multiplayer systems.

### Next Steps

1. **Study the Example**: Examine `mods/glowing_tree_mod/` for a complete implementation
2. **Start Simple**: Create basic mods before attempting complex systems
3. **Test Multiplayer**: Verify mod synchronization works correctly
4. **Optimize Performance**: Profile and optimize mod code for smooth gameplay
5. **Share with Community**: Publish mods for other players to enjoy

### Contributing

To contribute to the modding system:
1. Test mods extensively in both single-player and multiplayer, proper replication and rendering is critical.
2. Report bugs and performance issues
3. Suggest new API features
4. Create documentation improvements
5. Share example mods with the community

---

## Complex Mod Patterns

### State Machine Systems

Advanced mods often require complex state management. Here's a robust state machine pattern:

```lua
-- Advanced State Machine for AI Entities
local StateMachine = {}
StateMachine.__index = StateMachine

function StateMachine.new(initial_state)
    local sm = {
        current_state = initial_state,
        states = {},
        transitions = {},
        state_data = {},
        timers = {}
    }
    setmetatable(sm, StateMachine)
    return sm
end

function StateMachine:addState(name, enter_func, update_func, exit_func)
    self.states[name] = {
        enter = enter_func,
        update = update_func,
        exit = exit_func
    }
end

function StateMachine:addTransition(from_state, to_state, condition_func)
    if not self.transitions[from_state] then
        self.transitions[from_state] = {}
    end
    table.insert(self.transitions[from_state], {
        to = to_state,
        condition = condition_func
    })
end

function StateMachine:update(dt, entity, api)
    -- Update current state
    local state = self.states[self.current_state]
    if state and state.update then
        state.update(dt, entity, self.state_data, api)
    end
    
    -- Check transitions
    local transitions = self.transitions[self.current_state]
    if transitions then
        for _, transition in ipairs(transitions) do
            if transition.condition(entity, self.state_data, api) then
                self:changeState(transition.to, entity, api)
                return
            end
        end
    end
end

function StateMachine:changeState(new_state, entity, api)
    if self.current_state == new_state then return end
    
    -- Exit current state
    local current = self.states[self.current_state]
    if current and current.exit then
        current.exit(entity, self.state_data, api)
    end
    
    -- Enter new state
    self.current_state = new_state
    local new = self.states[new_state]
    if new and new.enter then
        new.enter(entity, self.state_data, api)
    end
end
```

### Component Entity System

For complex mods with many interactive entities:

```lua
-- Component System for Modular Entity Management
local ComponentSystem = {}
ComponentSystem.entities = {}
ComponentSystem.systems = {}

function ComponentSystem.createEntity(entity_id)
    local entity = {
        id = entity_id or ("entity_" .. tostring(#ComponentSystem.entities + 1)),
        components = {},
        active = true
    }
    ComponentSystem.entities[entity.id] = entity
    return entity
end

function ComponentSystem.addComponent(entity_id, component_name, data)
    local entity = ComponentSystem.entities[entity_id]
    if entity then
        entity.components[component_name] = data or {}
        return true
    end
    return false
end

function ComponentSystem.registerSystem(name, required_components, update_func)
    ComponentSystem.systems[name] = {
        components = required_components,
        update = update_func
    }
end

function ComponentSystem.updateSystems(dt, api)
    for system_name, system in pairs(ComponentSystem.systems) do
        for entity_id, entity in pairs(ComponentSystem.entities) do
            if entity.active then
                local has_all_components = true
                for _, component_name in ipairs(system.components) do
                    if not entity.components[component_name] then
                        has_all_components = false
                        break
                    end
                end
                
                if has_all_components then
                    system.update(dt, entity, api)
                end
            end
        end
    end
end
```

---

## Multi-Agent Migration Examples

### Agent 2 Example: Weapons System Migration

Converting legacy weapon systems to the mod framework:

```lua
-- mods/weapons_core_mod/main.lua
local weaponsMod = {}

local WEAPON_TEMPLATES = {
    pistol = {
        name = "Pistol",
        damage = 25,
        fire_rate = 0.3,
        projectile_type = "bullet",
        muzzle_flash = "small_flash"
    },
    rifle = {
        name = "Assault Rifle", 
        damage = 35,
        fire_rate = 0.12,
        projectile_type = "bullet",
        muzzle_flash = "medium_flash"
    }
}

function weaponsMod.init(api)
    weaponsMod.api = api
    api.input.registerMouseHandler("l", weaponsMod.shoot)
    api.network.registerMessageHandler("weapons_core_mod", weaponsMod.handleNetworkMessage)
    api.utils.log("Weapons Core Mod loaded!", "weapons_core_mod")
end

function weaponsMod.shoot()
    local player_x, player_y = weaponsMod.api.game.getPlayerPosition()
    local mouse_x, mouse_y = weaponsMod.api.input.getMousePosition()
    
    -- Calculate direction and create projectile
    local dx = mouse_x - player_x
    local dy = mouse_y - player_y
    local distance = math.sqrt(dx*dx + dy*dy)
    
    if distance > 0 then
        local dir_x = dx / distance
        local dir_y = dy / distance
        weaponsMod.createProjectile(player_x, player_y, dir_x, dir_y)
    end
end

return weaponsMod
```

### Agent 3 Example: Enemy AI Migration

Converting enemy systems to use advanced AI patterns:

```lua
-- mods/basic_enemies_mod/main.lua
local enemiesMod = {}

local ENEMY_TEMPLATES = {
    basic_grunt = {
        sprite = "enemy_01",
        health = 75,
        speed = 80,
        ai_type = "aggressive"
    }
}

function enemiesMod.init(api)
    enemiesMod.api = api
    enemiesMod.setupAI()
    api.utils.log("Basic Enemies Mod loaded!", "basic_enemies_mod")
end

function enemiesMod.setupAI()
    -- Create state machine for enemy AI
    enemiesMod.ai_template = StateMachine.new("idle")
    
    enemiesMod.ai_template:addState("idle", nil, function(dt, enemy, data, api)
        -- Patrol behavior
    end, nil)
    
    enemiesMod.ai_template:addState("chase", nil, function(dt, enemy, data, api)
        -- Chase player behavior
    end, nil)
    
    enemiesMod.ai_template:addTransition("idle", "chase", function(enemy, data, api)
        local player_x, player_y = api.game.getPlayerPosition()
        local distance = math.sqrt((player_x - enemy.x)^2 + (player_y - enemy.y)^2)
        return distance < enemy.template.aggro_range
    end)
end

return enemiesMod
```

---

## Performance Optimization

### Object Pooling Patterns

For performance-critical mods like projectiles:

```lua
-- Object Pool Implementation
local ObjectPool = {}
ObjectPool.__index = ObjectPool

function ObjectPool.new(create_func, reset_func, initial_size)
    local pool = {
        create_func = create_func,
        reset_func = reset_func,
        available = {},
        in_use = {}
    }
    setmetatable(pool, ObjectPool)
    
    -- Pre-populate pool
    for i = 1, initial_size or 10 do
        table.insert(pool.available, create_func())
    end
    
    return pool
end

function ObjectPool:acquire()
    local obj = table.remove(self.available)
    if not obj then
        obj = self.create_func()
    end
    table.insert(self.in_use, obj)
    return obj
end

function ObjectPool:release(obj)
    for i, pooled_obj in ipairs(self.in_use) do
        if pooled_obj == obj then
            table.remove(self.in_use, i)
            if self.reset_func then
                self.reset_func(obj)
            end
            table.insert(self.available, obj)
            return true
        end
    end
    return false
end

-- Usage for projectiles
local projectile_pool = ObjectPool.new(
    function() -- create
        return {x = 0, y = 0, velocity_x = 0, velocity_y = 0, active = false}
    end,
    function(projectile) -- reset
        projectile.x = 0
        projectile.y = 0
        projectile.active = false
    end,
    50 -- initial size
)
```

### Spatial Optimization

For collision detection and entity management:

```lua
-- Spatial Grid for Performance
local SpatialGrid = {}
SpatialGrid.__index = SpatialGrid

function SpatialGrid.new(cell_size)
    local grid = {
        cell_size = cell_size or 64,
        cells = {},
        objects = {}
    }
    setmetatable(grid, SpatialGrid)
    return grid
end

function SpatialGrid:addObject(obj, x, y)
    local cell_x = math.floor(x / self.cell_size)
    local cell_y = math.floor(y / self.cell_size)
    local key = cell_x .. "," .. cell_y
    
    if not self.cells[key] then
        self.cells[key] = {}
    end
    
    table.insert(self.cells[key], obj)
    self.objects[obj] = {key = key, x = x, y = y}
end

function SpatialGrid:getNearbyObjects(x, y, radius)
    local nearby = {}
    local min_cell = math.floor((x - radius) / self.cell_size)
    local max_cell = math.floor((x + radius) / self.cell_size)
    
    for cell_x = min_cell, max_cell do
        for cell_y = min_cell, max_cell do
            local key = cell_x .. "," .. cell_y
            local cell = self.cells[key]
            
            if cell then
                for _, obj in ipairs(cell) do
                    local obj_data = self.objects[obj]
                    if obj_data then
                        local distance = math.sqrt((x - obj_data.x)^2 + (y - obj_data.y)^2)
                        if distance <= radius then
                            table.insert(nearby, obj)
                        end
                    end
                end
            end
        end
    end
    
    return nearby
end
```

---

Examples of improper approaches: 

The key
  insight is that the new renderer handles ALL graphics state management including 
  setColor calls. Mods should only add data to the render queue and let the renderer
  handle the actual drawing.
The problem is that I'm trying to manually call love.graphics.setColor() in the mods,
  but that's the old legacy approach. The new renderer should handle all color settings
  through the queue data.
  ow I understand the structure. The combat_effects_mod has an update function
   that manages all the particle systems, and then it should add the active particles to
   the renderer queue during the update cycle instead of in separate draw functions. --> a mod was made to handle combat effects!


Let me check if the new renderer is actually using the correct rendering types. The
  issue might be that I'm using renderer queue types that don't exist:

I have successfully migrated the map system from legacy hardcoded code to the new mod system. Here's a summary of
  what was accomplished:



*This tutorial was created to accompany the DogeGame Modding System implementation. For technical support, refer to the game's documentation or community forums.*