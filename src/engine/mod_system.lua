-- Mod System - Core engine for loading and managing game modifications
-- This separates the game engine from game content, allowing dynamic mod loading and sharing

-- may need to add registerKeyReleaseHandler

local modSystem = {}

-- Core mod system state
local loaded_mods = {}
local mod_registry = {}
-- Removed: mod_api is now created per-mod with proper mod_id scoping
local mod_hooks = {
    key_handlers = {},
    mouse_handlers = {},
    network_handlers = {}
}
local mod_network_pending = {}

-- Mod system configuration
local MOD_DIRECTORY = "mods/"
local CORE_ENGINE_MODULES = {
    "new_renderer",
    "physics_engine", 
    "input_system",
    "network_system",
    "audio_system",
    "ui_system"
}

-- Mod structure definition
local MOD_STRUCTURE = {
    required_files = {
        "mod_info.json",  -- Metadata, dependencies, version
        "main.lua"        -- Entry point
    },
    optional_files = {
        "assets/",        -- Textures, sounds, etc.
        "shaders/",       -- Custom shaders
        "scripts/",       -- Additional Lua files
        "physics.lua",    -- Physics components
        "network.lua",    -- Network sync code
        "ui.lua"          -- UI components
    }
}

-- Entity templates and lifecycle management
local entity_templates = {}
local active_entities = {}
local entity_counter = 0

-- State machine support
local state_machines = {}

-- Mod API - What mods can access from the engine
function modSystem.createModAPI(engine_systems, mod_id)
    return {
        -- Enhanced rendering system with new_renderer integration
        renderer = {
            addToQueue = engine_systems.renderer.addToQueue,
            createParticleSystem = engine_systems.renderer.createParticleSystem,
            loadShader = engine_systems.renderer.loadShader,
            addLight = engine_systems.renderer.addLight,
            addParticleEffect = engine_systems.renderer.addParticleEffect,
            drawSprite = engine_systems.renderer.drawSprite,
            clearQueue = engine_systems.renderer.clearQueue,
            render = engine_systems.renderer.render,
            toggleDebug = engine_systems.renderer.toggleDebug,
            -- Quad creation for texture atlas management
            createQuad = function(x, y, width, height, sw, sh)
                -- Safe wrapper for Love2D's newQuad
                local success, quad = pcall(love.graphics.newQuad, x, y, width, height, sw, sh)
                if success then
                    return quad
                else
                    print("[MOD_SYSTEM] Failed to create quad")
                    return nil
                end
            end,
            -- Asset management
            getTexture = function(name)
                return engine_systems.renderer.assets and engine_systems.renderer.assets.textures[name]
            end,
            preloadTexture = function(name, path)
                if engine_systems.renderer.assets then
                    local success, texture = pcall(love.graphics.newImage, path)
                    if success then
                        engine_systems.renderer.assets.textures[name] = texture
                        return texture
                    end
                end
                return nil
            end,
            -- Shader system integration
            shader = {
                load = function(shader_name, vertex_path, fragment_path)
                    -- Load custom shader for mod
                    local mod_shader_path = MOD_DIRECTORY .. mod_id .. "/shaders/"
                    local vertex_code = nil
                    local fragment_code = nil
                    
                    if vertex_path then
                        local full_vertex_path = mod_shader_path .. vertex_path
                        if love.filesystem.getInfo(full_vertex_path) then
                            vertex_code = love.filesystem.read(full_vertex_path)
                        end
                    end
                    
                    if fragment_path then
                        local full_fragment_path = mod_shader_path .. fragment_path
                        if love.filesystem.getInfo(full_fragment_path) then
                            fragment_code = love.filesystem.read(full_fragment_path)
                        end
                    end
                    
                    if vertex_code or fragment_code then
                        local success, shader = pcall(love.graphics.newShader, vertex_code, fragment_code)
                        if success then
                            if engine_systems.renderer.assets then
                                engine_systems.renderer.assets.shaders[shader_name] = shader
                            end
                            return shader
                        else
                            print("[MOD_SYSTEM] Failed to load shader: " .. shader_name .. " (mod: " .. mod_id .. ")")
                        end
                    end
                    return nil
                end,
                setUniform = function(shader_name, uniform_name, value)
                    local shader = engine_systems.renderer.assets and engine_systems.renderer.assets.shaders[shader_name]
                    if shader and shader:hasUniform(uniform_name) then
                        shader:send(uniform_name, value)
                        return true
                    end
                    return false
                end,
                get = function(shader_name)
                    return engine_systems.renderer.assets and engine_systems.renderer.assets.shaders[shader_name]
                end
            }
        },
        
        -- Enhanced physics system with abstraction layer
        physics = {
            createBody = function(x, y, body_type, group_index, density, friction)
                local world = engine_systems.physics or world
                if not world then
                    print("[MOD_SYSTEM] Warning: Physics world not available")
                    return nil
                end
                
                local body = love.physics.newBody(world, x, y, body_type or "dynamic")
                return body
            end,
            createCircleShape = function(radius)
                return love.physics.newCircleShape(radius)
            end,
            createRectangleShape = function(width, height)
                return love.physics.newRectangleShape(width, height)
            end,
            createChainShape = function(loop, ...)
                return love.physics.newChainShape(loop, ...)
            end,
            createFixture = function(body, shape, group_index, density, friction)
                local fixture = love.physics.newFixture(body, shape)
                if group_index then fixture:setGroupIndex(group_index) end
                if density then fixture:setDensity(density) end
                if friction then fixture:setFriction(friction) end
                body:resetMassData()
                return fixture
            end,
            getWorld = function()
                return engine_systems.physics or world
            end,
            -- Collision groups
            COLLISION_GROUPS = {
                PLAYER = -1,
                ENEMY = -777,
                BOSS = -888,
                COIN = 69,
                MOD_ENTITY = -999
            }
        },
        
        -- Input system
        input = {
            registerKeyHandler = function(key, callback)
                mod_hooks.key_handlers = mod_hooks.key_handlers or {}
                mod_hooks.key_handlers[key] = mod_hooks.key_handlers[key] or {}
                table.insert(mod_hooks.key_handlers[key], callback)
            end,
            registerMouseHandler = function(button, callback)
                mod_hooks.mouse_handlers = mod_hooks.mouse_handlers or {}
                table.insert(mod_hooks.mouse_handlers, {
                    button = button,
                    callback = callback,
                    on_press = true,
                    on_release = false
                })
            end,
            registerMousePressHandler = function(button, callback)
                mod_hooks.mouse_handlers = mod_hooks.mouse_handlers or {}
                table.insert(mod_hooks.mouse_handlers, {
                    button = button,
                    callback = callback,
                    on_press = true,
                    on_release = false
                })
            end,
            registerMouseReleaseHandler = function(button, callback)
                mod_hooks.mouse_handlers = mod_hooks.mouse_handlers or {}
                table.insert(mod_hooks.mouse_handlers, {
                    button = button,
                    callback = callback,
                    on_press = false,
                    on_release = true
                })
            end,
            getMousePosition = function()
                if love.mouse then
                    return love.mouse.getPosition()
                end
                return 0, 0
            end,
            getScreenCenter = function()
                if love.graphics then
                    return love.graphics.getWidth() / 2, love.graphics.getHeight() / 2
                end
                return 400, 300  -- fallback
            end,
            isKeyDown = function(key)
                if love.keyboard then
                    return love.keyboard.isDown(key)
                end
                return false
            end
        },
        
        -- Game state access
        game = {
            getPlayerPosition = function()
                -- Try to get from player_core_mod first
                local player_mod = loaded_mods["player_core_mod"]
                if player_mod and player_mod.instance and player_mod.instance.exports then
                    return player_mod.instance.exports.getPosition()
                end
                
                -- Fallback to legacy player if still available
                if player and player.body then
                    return player.body:getX(), player.body:getY()
                end
                return 0, 0
            end,
            getPlayerHealth = function()
                -- Try to get from player_core_mod first
                local player_mod = loaded_mods["player_core_mod"]
                if player_mod and player_mod.instance and player_mod.instance.exports then
                    local health, max_health = player_mod.instance.exports.getHealth()
                    return health
                end
                
                -- Fallback to legacy player
                return player and player.health or 100
            end,
            setPlayerHealth = function(health)
                -- Try to set via player_core_mod first
                local player_mod = loaded_mods["player_core_mod"]
                if player_mod and player_mod.instance and player_mod.instance.exports then
                    player_mod.instance.exports.damagePlayer(player_mod.instance.exports.getHealth() - health, "api_call")
                    return
                end
                
                -- Fallback to legacy player
                if player then
                    player.health = math.max(0, math.min(player.max_health or 100, health))
                end
            end,
            getWorld = function()
                return world
            end,
            getMultiplayerMode = function()
                -- Return the multiplayer mode (1 = host, 2+ = client, nil = single player)
                return var.multiplayer
            end,
            getPlayerData = function()
                -- Get comprehensive player data for systems like camera
                local player_mod = loaded_mods["player_core_mod"]
                if player_mod and player_mod.instance and player_mod.instance.exports then
                    local x, y = player_mod.instance.exports.getPosition()
                    local health, max_health = player_mod.instance.exports.getHealth()
                    return {
                        body = {
                            getX = function() return x end,
                            getY = function() return y end
                        },
                        health = health,
                        max_health = max_health,
                        x = x,
                        y = y
                    }
                end
                
                -- Fallback to legacy player
                return player
            end
        },
        
        -- Network system
        network = {
            sendToAll = function(data, mod_id)
                if var.multiplayer then
                    local mod_message = {
                        type = "mod_data",
                        mod_id = mod_id,
                        data = data
                    }
                    -- Send through existing multiplayer system
                    multiplayer.sendCustomMessage(mod_message)
                end
            end,
            registerMessageHandler = function(mod_id, callback)
                mod_hooks.network_handlers = mod_hooks.network_handlers or {}
                mod_hooks.network_handlers[mod_id] = callback
            end,
            getLocalClientId = function()
                -- Return the local client ID based on multiplayer mode
                if var.multiplayer then
                    return "client_" .. var.multiplayer
                end
                return nil
            end,
            isMultiplayer = function()
                -- Check if game is in multiplayer mode
                return var.multiplayer ~= nil and var.multiplayer > 0
            end
        },
        
        -- Entity management system
        entities = {
            create = function(template_name, x, y, properties)
                return modSystem.createEntity(template_name, x, y, properties)
            end,
            destroy = function(entity_id)
                return modSystem.destroyEntity(entity_id)
            end,
            get = function(entity_id)
                return active_entities[entity_id]
            end,
            getAll = function()
                return active_entities
            end,
            getByType = function(entity_type)
                local results = {}
                for id, entity in pairs(active_entities) do
                    if entity.type == entity_type then
                        table.insert(results, entity)
                    end
                end
                return results
            end,
            registerTemplate = function(template_name, template_data)
                entity_templates[template_name] = template_data
            end
        },
        
        -- State machine system
        statemachine = {
            create = function(initial_state, states)
                return modSystem.createStateMachine(initial_state, states)
            end,
            transition = function(sm_id, new_state)
                return modSystem.transitionState(sm_id, new_state)
            end,
            getCurrentState = function(sm_id)
                return state_machines[sm_id] and state_machines[sm_id].current_state
            end
        },
        
        -- Inter-mod communication
        mod_system = {
            getMod = function(mod_id)
                return loaded_mods[mod_id]
            end,
            isModLoaded = function(mod_id)
                return loaded_mods[mod_id] ~= nil
            end,
            getLoadedMods = function()
                local mod_list = {}
                for mod_id, _ in pairs(loaded_mods) do
                    table.insert(mod_list, mod_id)
                end
                return mod_list
            end
        },
        
        -- Direct access to loaded mods (easier API)
        mods = setmetatable({}, {
            __index = function(t, key)
                local mod = loaded_mods[key]
                if mod and mod.instance then
                    return mod.instance
                end
                return nil
            end
        }),
        
        -- Utility functions
        utils = {
            log = function(message, mod_id)
                print("[MOD:" .. (mod_id or "UNKNOWN") .. "] " .. message)
            end,
            getAssetPath = function(mod_id, asset_name)
                return MOD_DIRECTORY .. mod_id .. "/assets/" .. asset_name
            end,
            loadTexture = function(texture_name, path)
                -- If path is not provided, assume it's a shared texture
                if not path then
                    path = "gfx/" .. texture_name
                else
                    -- Support both relative paths (from mod) and shared paths (from src)
                    if path:sub(1, 3) == "../" then
                        -- Shared texture from src directory
                        path = path:sub(4)  -- Remove "../"
                    else
                        -- Mod-specific texture
                        local mod_id_from_path = path:match("^([^/]+)/")
                        if not mod_id_from_path then
                            -- Use the current mod's assets directory
                            path = MOD_DIRECTORY .. mod_id .. "/assets/" .. path
                        end
                    end
                end
                
                local success, texture = pcall(love.graphics.newImage, path)
                if success then
                    -- Store in renderer assets for future use
                    if engine_systems.renderer and engine_systems.renderer.assets then
                        engine_systems.renderer.assets.textures[texture_name] = texture
                    end
                    return texture
                else
                    print("[MOD_SYSTEM] Failed to load texture: " .. path)
                    return nil
                end
            end,
            getTime = function()
                return love.timer.getTime()
            end,
            getDelta = function()
                return love.timer.getDelta()
            end,
            math = {
                distance = function(x1, y1, x2, y2)
                    return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
                end,
                lerp = function(a, b, t)
                    return a + (b - a) * t
                end,
                clamp = function(value, min, max)
                    return math.max(min, math.min(max, value))
                end
            }
        },
        
        -- Mod System API (for inter-mod communication)
        mod_system = {
            getMod = function(target_mod_id)
                return loaded_mods[target_mod_id]
            end,
            
            isModLoaded = function(target_mod_id)
                return loaded_mods[target_mod_id] ~= nil
            end
        },

        -- Audio API
        audio = {
            playSound = function(filename, options)
                options = options or {}
                local source
                
                -- First try mod-specific path
                local modPath = "mods/" .. mod_id .. "/assets/" .. filename
                if love.filesystem.getInfo(modPath) then
                    source = love.audio.newSource(modPath, "static")
                else
                    -- Try shared assets
                    local sharedPath = "src/sfx/" .. filename
                    if love.filesystem.getInfo(sharedPath) then
                        source = love.audio.newSource(sharedPath, "static")
                    else
                        print("[Audio] Warning: Sound not found: " .. filename)
                        return nil
                    end
                end
                
                if source then
                    source:setVolume(options.volume or 1.0)
                    source:setPitch(options.pitch or 1.0)
                    source:setLooping(options.loop or false)
                    
                    if options.position then
                        source:setPosition(options.position.x, options.position.y, 0)
                    end
                    
                    love.audio.play(source)
                    return source
                end
            end,
            
            stopSound = function(source)
                if source then
                    love.audio.stop(source)
                end
            end,
            
            setVolume = function(volume)
                love.audio.setVolume(volume)
            end,
            
            playMusic = function(filename, options)
                options = options or {}
                local source
                
                -- First try mod-specific path
                local modPath = "mods/" .. mod_id .. "/assets/" .. filename
                if love.filesystem.getInfo(modPath) then
                    source = love.audio.newSource(modPath, "stream")
                else
                    -- Try shared assets
                    local sharedPath = "src/music/" .. filename
                    if love.filesystem.getInfo(sharedPath) then
                        source = love.audio.newSource(sharedPath, "stream")
                    else
                        print("[Audio] Warning: Music not found: " .. filename)
                        return nil
                    end
                end
                
                if source then
                    source:setVolume(options.volume or 0.7)
                    source:setLooping(options.loop ~= false) -- Default to true for music
                    love.audio.play(source)
                    return source
                end
            end
        }
    }
end

-- Initialize the mod system
function modSystem.init(engine_systems)
    print("[MOD_SYSTEM] Initializing mod system...")
    
    -- Store engine systems for per-mod API creation
    modSystem.engine_systems = engine_systems
    
    -- Initialize mod hooks
    mod_hooks = {
        key_handlers = {},
        mouse_handlers = {},
        network_handlers = {},
        update_callbacks = {},
        draw_callbacks = {}
    }
    
    -- Create mods directory if it doesn't exist
    if not love.filesystem.getInfo(MOD_DIRECTORY) then
        love.filesystem.createDirectory(MOD_DIRECTORY)
        print("[MOD_SYSTEM] Created mods directory: " .. MOD_DIRECTORY)
    end
    
    -- Load all available mods
    modSystem.discoverMods()
    
    print("[MOD_SYSTEM] Mod system initialized!")
end

-- Discover and catalog available mods
function modSystem.discoverMods()
    local mods_found = 0
    
    local items = love.filesystem.getDirectoryItems(MOD_DIRECTORY)
    for _, item in ipairs(items) do
        local mod_path = MOD_DIRECTORY .. item
        local mod_info_path = mod_path .. "/mod_info.json"
        
        if love.filesystem.getInfo(mod_info_path) then
            local success, mod_info = modSystem.loadModInfo(mod_info_path)
            if success then
                mod_registry[item] = {
                    id = item,
                    path = mod_path,
                    info = mod_info,
                    loaded = false,
                    enabled = false
                }
                mods_found = mods_found + 1
                print("[MOD_SYSTEM] Discovered mod: " .. item .. " v" .. mod_info.version)
            end
        end
    end
    
    print("[MOD_SYSTEM] Found " .. mods_found .. " mods")
end

-- Load mod info from JSON
function modSystem.loadModInfo(info_path)
    local contents = love.filesystem.read(info_path)
    if not contents then
        return false, "Could not read mod info file"
    end
    
    local success, mod_info = pcall(json.decode, contents)
    if not success then
        return false, "Invalid JSON in mod info file"
    end
    
    -- Validate required fields
    local required_fields = {"id", "name", "version", "author", "description"}
    for _, field in ipairs(required_fields) do
        if not mod_info[field] then
            return false, "Missing required field: " .. field
        end
    end
    
    return true, mod_info
end

-- Load a specific mod
function modSystem.loadMod(mod_id)
    local mod_entry = mod_registry[mod_id]
    if not mod_entry then
        print("[MOD_SYSTEM] Mod not found: " .. mod_id)
        return false
    end
    
    if mod_entry.loaded then
        print("[MOD_SYSTEM] Mod already loaded: " .. mod_id)
        return true
    end
    
    print("[MOD_SYSTEM] Loading mod: " .. mod_id)
    
    -- Check dependencies
    if mod_entry.info.dependencies then
        for _, dep_id in ipairs(mod_entry.info.dependencies) do
            if not loaded_mods[dep_id] then
                print("[MOD_SYSTEM] Loading dependency: " .. dep_id)
                if not modSystem.loadMod(dep_id) then
                    print("[MOD_SYSTEM] Failed to load dependency: " .. dep_id)
                    return false
                end
            end
        end
    end
    
    -- Load the main mod file
    local main_path = mod_entry.path .. "/main.lua"
    if not love.filesystem.getInfo(main_path) then
        print("[MOD_SYSTEM] Main file not found: " .. main_path)
        return false
    end
    
    -- Create per-mod API instance with proper mod_id scoping
    local mod_specific_api = modSystem.createModAPI(modSystem.engine_systems, mod_id)
    
    -- Create sandboxed environment for the mod
    local mod_env = modSystem.createModEnvironment(mod_id, mod_specific_api)
    
    -- Load and execute the mod
    local mod_code = love.filesystem.read(main_path)
    local mod_func, load_error = load(mod_code, mod_id, "t", mod_env)
    
    if not mod_func then
        print("[MOD_SYSTEM] Failed to compile mod: " .. load_error)
        return false
    end
    
    local success, mod_instance = pcall(mod_func)
    if not success then
        print("[MOD_SYSTEM] Failed to execute mod: " .. mod_instance)
        return false
    end
    
    -- Initialize the mod with its specific API
    if mod_instance and mod_instance.init then
        local init_success, init_error = pcall(mod_instance.init, mod_specific_api)
        if not init_success then
            print("[MOD_SYSTEM] Failed to initialize mod: " .. init_error)
            return false
        end
    end
    
    -- Register the mod
    loaded_mods[mod_id] = {
        instance = mod_instance,
        info = mod_entry.info,
        env = mod_env,
        enabled = true
    }
    
    mod_entry.loaded = true
    mod_entry.enabled = true
    
    print("[MOD_SYSTEM] Successfully loaded mod: " .. mod_id)
    return true
end

-- Create sandboxed environment for mod execution
function modSystem.createModEnvironment(mod_id, api)
    local env = {
        -- Lua standard library (restricted)
        pairs = pairs,
        ipairs = ipairs,
        next = next,
        type = type,
        tostring = tostring,
        tonumber = tonumber,
        math = math,
        string = string,
        table = table,
        
        -- Mod API access
        api = api,
        
        -- Mod info
        MOD_ID = mod_id,
        
        -- Safe print function
        print = function(...)
            print("[MOD:" .. mod_id .. "]", ...)
        end
    }
    
    return env
end

-- Unload a mod
function modSystem.unloadMod(mod_id)
    local mod = loaded_mods[mod_id]
    if not mod then
        print("[MOD_SYSTEM] Mod not loaded: " .. mod_id)
        return false
    end
    
    -- Call mod cleanup if available
    if mod.instance and mod.instance.cleanup then
        pcall(mod.instance.cleanup)
    end
    
    -- Remove from loaded mods
    loaded_mods[mod_id] = nil
    
    -- Update registry
    if mod_registry[mod_id] then
        mod_registry[mod_id].loaded = false
        mod_registry[mod_id].enabled = false
    end
    
    print("[MOD_SYSTEM] Unloaded mod: " .. mod_id)
    return true
end

-- Update all loaded mods
function modSystem.update(dt)
    -- Update entity management systems first
    modSystem.updateEntitySystems(dt)
    
    for mod_id, mod in pairs(loaded_mods) do
        if mod.enabled and mod.instance and mod.instance.update then
            local success, error_msg = pcall(mod.instance.update, dt)
            if not success then
                print("[MOD_SYSTEM] Error in mod update (" .. mod_id .. "): " .. error_msg)
            end
        end
    end
    
    -- Process update callbacks
    for _, callback in ipairs(mod_hooks.update_callbacks) do
        pcall(callback, dt)
    end
end

-- Draw all loaded mods
function modSystem.draw()
    for mod_id, mod in pairs(loaded_mods) do
        if mod.enabled and mod.instance and mod.instance.draw then
            local success, error_msg = pcall(mod.instance.draw)
            if not success then
                print("[MOD_SYSTEM] Error in mod draw (" .. mod_id .. "): " .. error_msg)
            end
        end
    end
    
    -- Process draw callbacks
    for _, callback in ipairs(mod_hooks.draw_callbacks) do
        pcall(callback)
    end
end

-- Handle mouse press events
function modSystem.mousepressed(x, y, button)
    -- Process mouse handlers
    for _, handler in ipairs(mod_hooks.mouse_handlers) do
        if handler.button == button and handler.on_press then
            pcall(handler.callback, x, y, button)
        end
    end
end

-- Handle mouse release events
function modSystem.mousereleased(x, y, button)
    -- Process mouse handlers
    for _, handler in ipairs(mod_hooks.mouse_handlers) do
        if handler.button == button and handler.on_release then
            pcall(handler.callback, x, y, button)
        end
    end
end

-- Handle collision events
function modSystem.handleCollision(fixture_a, fixture_b, contact)
    -- Get user data from fixtures to determine what collided
    local data_a = fixture_a:getUserData()
    local data_b = fixture_b:getUserData()
    
    -- Forward collision to relevant mods
    for mod_id, mod in pairs(loaded_mods) do
        if mod.enabled and mod.instance and mod.instance.handleCollision then
            local success, error_msg = pcall(mod.instance.handleCollision, fixture_a, fixture_b, contact)
            if not success then
                print("[MOD_SYSTEM] Error in mod collision handler (" .. mod_id .. "): " .. error_msg)
            end
        end
        
        -- Also check for collision handlers in exports
        if mod.enabled and mod.instance and mod.instance.exports and mod.instance.exports.handleCollision then
            local success, error_msg = pcall(mod.instance.exports.handleCollision, fixture_a, fixture_b, contact)
            if not success then
                print("[MOD_SYSTEM] Error in mod collision export (" .. mod_id .. "): " .. error_msg)
            end
        end
    end
end

-- Handle input events
function modSystem.keypressed(key)
    if mod_hooks.key_handlers[key] then
        for _, callback in ipairs(mod_hooks.key_handlers[key]) do
            pcall(callback, key)
        end
    end
end

function modSystem.keyreleased(key)
    -- Currently no mods use key release, but it's here for completeness
end

-- Notify all mods about pause state changes
function modSystem.notifyPause(isPaused)
    for mod_id, mod in pairs(loaded_mods) do
        if mod.enabled and mod.instance then
            -- Check for onPause/onResume handlers
            if isPaused and mod.instance.onPause then
                local success, error_msg = pcall(mod.instance.onPause)
                if not success then
                    print("[MOD_SYSTEM] Error in mod onPause (" .. mod_id .. "): " .. error_msg)
                end
            elseif not isPaused and mod.instance.onResume then
                local success, error_msg = pcall(mod.instance.onResume)
                if not success then
                    print("[MOD_SYSTEM] Error in mod onResume (" .. mod_id .. "): " .. error_msg)
                end
            end
        end
    end
end

-- Network message handling
function modSystem.handleNetworkMessage(message)
    if message.type == "mod_data" and message.mod_id then
        local handler = mod_hooks.network_handlers[message.mod_id]
        if handler then
            pcall(handler, message.data)
        end
    elseif message.type == "mod_share_request" then
        modSystem.handleModShareRequest(message)
    elseif message.type == "mod_share_data" then
        modSystem.handleModShareData(message)
    elseif message.type == "complex_mod_share" then
        modSystem.handleComplexModShare(message)
    elseif message.type == "entity_sync" then
        modSystem.handleEntitySync(message)
    end
end

-- Enhanced mod sharing for complex mods
function modSystem.shareComplexMod(mod_id, target_player)
    local mod = loaded_mods[mod_id]
    if not mod then return false end
    
    -- Prepare comprehensive mod data
    local mod_data = {
        type = "complex_mod_share",
        mod_id = mod_id,
        mod_info = mod.info,
        entity_templates = entity_templates,
        active_entities = {}, -- Only send entity states, not the full objects
        from_player = multiplayer and multiplayer.getLocalPlayerId() or "host"
    }
    
    -- Serialize entity states for network transmission
    for entity_id, entity in pairs(active_entities) do
        if entity.network_sync ~= false then -- Allow entities to opt out of sync
            mod_data.active_entities[entity_id] = {
                id = entity_id,
                type = entity.type,
                x = entity.x,
                y = entity.y,
                active = entity.active,
                properties = entity.properties
            }
        end
    end
    
    if multiplayer then
        multiplayer.sendToPlayer(target_player, mod_data)
    end
    
    return true
end

-- Handle complex mod sharing
function modSystem.handleComplexModShare(message)
    if message.type ~= "complex_mod_share" then return end
    
    -- Merge entity templates
    for template_name, template_data in pairs(message.entity_templates or {}) do
        entity_templates[template_name] = template_data
    end
    
    -- Recreate entities
    for entity_id, entity_data in pairs(message.active_entities or {}) do
        if not active_entities[entity_id] then
            modSystem.createEntity(entity_data.type, entity_data.x, entity_data.y, entity_data.properties)
        end
    end
end

-- Entity synchronization for multiplayer
function modSystem.syncEntities()
    if not var.multiplayer then return end
    
    local sync_data = {
        type = "entity_sync",
        entities = {}
    }
    
    for entity_id, entity in pairs(active_entities) do
        if entity.network_sync ~= false then
            sync_data.entities[entity_id] = {
                x = entity.x,
                y = entity.y,
                active = entity.active,
                properties = entity.properties
            }
        end
    end
    
    if multiplayer then
        multiplayer.sendToAll(sync_data)
    end
end

-- Handle entity synchronization
function modSystem.handleEntitySync(message)
    if message.type ~= "entity_sync" then return end
    
    for entity_id, entity_data in pairs(message.entities or {}) do
        local entity = active_entities[entity_id]
        if entity then
            entity.x = entity_data.x
            entity.y = entity_data.y
            entity.active = entity_data.active
            if entity_data.properties then
                for key, value in pairs(entity_data.properties) do
                    entity.properties[key] = value
                end
            end
        end
    end
end

-- Mod sharing system
function modSystem.shareModWithPlayer(mod_id, player_id)
    local mod = loaded_mods[mod_id]
    if not mod then
        print("[MOD_SYSTEM] Cannot share unloaded mod: " .. mod_id)
        return false
    end
    
    -- Prepare mod data for sharing
    local share_data = {
        type = "mod_share_request",
        mod_id = mod_id,
        mod_info = mod.info,
        from_player = multiplayer.getLocalPlayerId(),
        to_player = player_id
    }
    
    multiplayer.sendToPlayer(player_id, share_data)
    print("[MOD_SYSTEM] Sent mod share request: " .. mod_id)
end

function modSystem.handleModShareRequest(message)
    -- Show UI prompt to accept/reject mod
    local accept = modSystem.promptModAcceptance(message.mod_info)
    
    if accept then
        -- Request mod data
        local response = {
            type = "mod_share_accept",
            mod_id = message.mod_id,
            from_player = multiplayer.getLocalPlayerId(),
            to_player = message.from_player
        }
        multiplayer.sendToPlayer(message.from_player, response)
    end
end

-- Get global API access (for notifications)
function modSystem.getGlobalAPI()
    -- Check if UI notifications mod is loaded
    local notifications_mod = loaded_mods["ui_notifications_mod"]
    if notifications_mod and notifications_mod.instance and notifications_mod.instance.exports then
        return {
            notifications = notifications_mod.instance.exports
        }
    end
    return {}
end

-- Get list of loaded mods
function modSystem.getLoadedMods()
    local result = {}
    for mod_id, mod in pairs(loaded_mods) do
        table.insert(result, {
            id = mod_id,
            name = mod.info.name,
            version = mod.info.version,
            author = mod.info.author,
            enabled = mod.enabled
        })
    end
    return result
end

-- Get list of available mods
function modSystem.getAvailableMods()
    local result = {}
    for mod_id, mod_entry in pairs(mod_registry) do
        table.insert(result, {
            id = mod_id,
            name = mod_entry.info.name,
            version = mod_entry.info.version,
            author = mod_entry.info.author,
            loaded = mod_entry.loaded,
            enabled = mod_entry.enabled
        })
    end
    return result
end

-- Enable/disable a loaded mod
function modSystem.toggleMod(mod_id, enabled)
    local mod = loaded_mods[mod_id]
    if mod then
        mod.enabled = enabled
        if mod_registry[mod_id] then
            mod_registry[mod_id].enabled = enabled
        end
        print("[MOD_SYSTEM] Mod " .. mod_id .. " " .. (enabled and "enabled" or "disabled"))
        return true
    end
    return false
end

-- Entity Management System
function modSystem.createEntity(template_name, x, y, properties)
    local template = entity_templates[template_name]
    if not template then
        print("[MOD_SYSTEM] Unknown entity template: " .. tostring(template_name))
        return nil
    end
    
    entity_counter = entity_counter + 1
    local entity_id = "entity_" .. entity_counter
    
    local entity = {
        id = entity_id,
        type = template_name,
        x = x or 0,
        y = y or 0,
        active = true,
        created_time = love.timer.getTime(),
        properties = properties or {},
        body = nil,
        fixtures = {},
        components = {}
    }
    
    -- Apply template properties
    for key, value in pairs(template) do
        if key ~= "components" then
            entity[key] = value
        end
    end
    
    -- Initialize components
    if template.components then
        for component_name, component_data in pairs(template.components) do
            entity.components[component_name] = {
                data = component_data,
                active = true
            }
        end
    end
    
    -- Create physics body if specified
    if template.physics then
        local world_ref = world
        if world_ref then
            entity.body = love.physics.newBody(world_ref, x, y, template.physics.type or "dynamic")
            
            if template.physics.shapes then
                for _, shape_def in ipairs(template.physics.shapes) do
                    local shape = nil
                    if shape_def.type == "circle" then
                        shape = love.physics.newCircleShape(shape_def.radius)
                    elseif shape_def.type == "rectangle" then
                        shape = love.physics.newRectangleShape(shape_def.width, shape_def.height)
                    end
                    
                    if shape then
                        local fixture = love.physics.newFixture(entity.body, shape)
                        if shape_def.group_index then
                            fixture:setGroupIndex(shape_def.group_index)
                        end
                        table.insert(entity.fixtures, fixture)
                    end
                end
            end
        end
    end
    
    active_entities[entity_id] = entity
    return entity
end

function modSystem.destroyEntity(entity_id)
    local entity = active_entities[entity_id]
    if not entity then return false end
    
    -- Cleanup physics
    if entity.body then
        entity.body:destroy()
    end
    
    active_entities[entity_id] = nil
    return true
end

-- State Machine System
function modSystem.createStateMachine(initial_state, states)
    local sm_id = "sm_" .. (love.timer.getTime() * 1000) .. "_" .. math.random(1000)
    
    local state_machine = {
        id = sm_id,
        current_state = initial_state,
        states = states or {},
        data = {},
        transition_time = 0
    }
    
    state_machines[sm_id] = state_machine
    return sm_id
end

function modSystem.transitionState(sm_id, new_state)
    local sm = state_machines[sm_id]
    if not sm then return false end
    
    local current_state_def = sm.states[sm.current_state]
    local new_state_def = sm.states[new_state]
    
    if not new_state_def then
        print("[MOD_SYSTEM] Invalid state transition: " .. tostring(new_state))
        return false
    end
    
    -- Call exit handler for current state
    if current_state_def and current_state_def.on_exit then
        pcall(current_state_def.on_exit, sm.data)
    end
    
    -- Transition
    sm.current_state = new_state
    sm.transition_time = love.timer.getTime()
    
    -- Call enter handler for new state
    if new_state_def.on_enter then
        pcall(new_state_def.on_enter, sm.data)
    end
    
    return true
end

-- Update entity systems
function modSystem.updateEntitySystems(dt)
    -- Update all active entities
    for entity_id, entity in pairs(active_entities) do
        if entity.active then
            -- Update physics position
            if entity.body then
                entity.x, entity.y = entity.body:getPosition()
            end
            
            -- Update components
            for component_name, component in pairs(entity.components) do
                if component.active and component.update then
                    pcall(component.update, component.data, dt)
                end
            end
        end
    end
    
    -- Update state machines
    for sm_id, sm in pairs(state_machines) do
        local current_state_def = sm.states[sm.current_state]
        if current_state_def and current_state_def.on_update then
            pcall(current_state_def.on_update, sm.data, dt)
        end
    end
end

-- Global API access for core systems (like camera)
function modSystem.getPlayerData()
    local player_mod = loaded_mods["player_core_mod"]
    if player_mod and player_mod.instance and player_mod.instance.exports then
        local x, y = player_mod.instance.exports.getPosition()
        local health, max_health = player_mod.instance.exports.getHealth()
        return {
            body = {
                getX = function() return x end,
                getY = function() return y end
            },
            health = health,
            max_health = max_health,
            x = x,
            y = y
        }
    end
    
    -- Fallback to legacy player if available
    if player then
        return player
    end
    
    return nil
end

-- Cleanup
function modSystem.cleanup()
    for mod_id, _ in pairs(loaded_mods) do
        modSystem.unloadMod(mod_id)
    end
    
    -- Cleanup entity systems
    for entity_id, entity in pairs(active_entities) do
        if entity.body then
            entity.body:destroy()
        end
    end
    
    loaded_mods = {}
    mod_registry = {}
    mod_hooks = {}
    entity_templates = {}
    active_entities = {}
    state_machines = {}
    entity_counter = 0
    
    print("[MOD_SYSTEM] Cleanup complete")
end

-- Mod validation for security
function modSystem.validateMod(mod_path)
    -- Check for malicious patterns in mod files
    local main_content = love.filesystem.read(mod_path .. "/main.lua")
    if not main_content then
        return false, "Cannot read main.lua"
    end
    
    -- Blacklisted patterns
    local blacklist = {
        "love%.filesystem%.write",
        "love%.filesystem%.remove",
        "io%.",
        "os%.",
        "require%s*%(",
        "dofile",
        "loadfile"
    }
    
    for _, pattern in ipairs(blacklist) do
        if main_content:match(pattern) then
            return false, "Potentially unsafe code detected: " .. pattern
        end
    end
    
    return true
end

-- Get current player position (for camera, collision checks, etc.)
function modSystem.getPlayerPosition()
    local player_mod = loaded_mods["player_core_mod"]
    if player_mod and player_mod.instance and player_mod.instance.exports then
        return player_mod.instance.exports.getPosition()
    end
    
    -- Fallback to legacy player if still available
    if player and player.body then
        return player.body:getX(), player.body:getY()
    end
    return 0, 0
end

-- Get current player health (for UI display)
function modSystem.getPlayerHealth()
    local player_mod = loaded_mods["player_core_mod"]
    if player_mod and player_mod.instance and player_mod.instance.exports then
        local health, max_health = player_mod.instance.exports.getHealth()
        return health
    end
    
    -- Fallback to legacy player if still available
    if player and player.health then
        return player.health
    end
    return 100
end

-- Get a loaded mod by ID
function modSystem.getLoadedMod(mod_id)
    return loaded_mods[mod_id]
end

-- Check if a mod is loaded
function modSystem.isModLoaded(mod_id)
    return loaded_mods[mod_id] ~= nil
end

return modSystem