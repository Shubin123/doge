-- Glowing Tree Mod - Main Entry Point
-- This mod adds magical glowing trees to the game world

local glowingTreeMod = {}

-- Mod state
local trees = {}
local tree_count = 0
local mod_config = {}
local tree_shader = nil

-- Tree types configuration
local TREE_TYPES = {
    MYSTICAL = {
        glow_color = {0.2, 0.8, 0.4, 1.0},
        magic_particles = "leaves_sheet",
        base_scale = 1.2,
        sway_amplitude = 0.15,
        pulse_speed = 2.0,
        healing_power = 15
    },
    ANCIENT = {
        glow_color = {0.8, 0.6, 0.2, 1.0},
        magic_particles = "holy_light",
        base_scale = 1.5,
        sway_amplitude = 0.1,
        pulse_speed = 1.5,
        healing_power = 25
    },
    ENCHANTED = {
        glow_color = {0.6, 0.2, 0.9, 1.0},
        magic_particles = "electric_aura",
        base_scale = 1.0,
        sway_amplitude = 0.2,
        pulse_speed = 3.0,
        healing_power = 10
    }
}

-- Initialize the mod
function glowingTreeMod.init(api)
    print("Initializing Glowing Tree Mod v1.0.0")
    
    -- Store API reference
    glowingTreeMod.api = api
    
    -- Load configuration from mod_info
    mod_config = {
        max_trees = 50,
        enable_healing = true,
        enable_particles = true,
        enable_networking = true
    }
    
    -- Load tree shader
    tree_shader = api.renderer.loadShader("glowing_tree_mod_shader", nil, "mods/glowing_tree_mod/shaders/glowing_tree.frag")
    if not tree_shader then
        print("[GLOWING_TREE_MOD] Warning: Could not load tree shader")
    end
    
    -- Register input handlers
    api.input.registerKeyHandler("e", glowingTreeMod.handleInteraction)
    api.input.registerKeyHandler("t", glowingTreeMod.spawnTreeAtPlayer)
    
    -- Register network handler
    if mod_config.enable_networking then
        api.network.registerMessageHandler("glowing_tree_mod", glowingTreeMod.handleNetworkMessage)
    end
    
    -- Spawn initial trees
    glowingTreeMod.spawnInitialTrees()
    
    print("[GLOWING_TREE_MOD] Initialization complete! Press 'T' to spawn trees, 'E' to interact")
end

-- Spawn initial trees in the world
function glowingTreeMod.spawnInitialTrees()
    local spawn_positions = {
        {x = 300, y = 200, type = "MYSTICAL"},
        {x = 500, y = 150, type = "ANCIENT"},
        {x = 400, y = 350, type = "ENCHANTED"},
        {x = 250, y = 300, type = "MYSTICAL"},
        {x = 550, y = 250, type = "ENCHANTED"}
    }
    
    for _, pos in ipairs(spawn_positions) do
        glowingTreeMod.createTree(pos.x, pos.y, pos.type, 80 + math.random(40))
    end
    
    print("[GLOWING_TREE_MOD] Spawned " .. #spawn_positions .. " initial trees")
end

-- Create a new tree
function glowingTreeMod.createTree(x, y, tree_type, health)
    if #trees >= mod_config.max_trees then
        print("[GLOWING_TREE_MOD] Maximum tree limit reached")
        return nil
    end
    
    tree_type = tree_type or "MYSTICAL"
    health = health or 100
    
    local tree_config = TREE_TYPES[tree_type]
    if not tree_config then
        print("[GLOWING_TREE_MOD] Unknown tree type: " .. tree_type)
        return nil
    end
    
    tree_count = tree_count + 1
    
    local tree = {
        id = tree_count,
        x = x,
        y = y,
        type = tree_type,
        config = tree_config,
        health = health,
        max_health = health,
        scale = tree_config.base_scale,
        rotation = 0,
        sway_time = 0,
        pulse_time = 0,
        magic_time = 0,
        active = true,
        glow_intensity = 1.0,
        magic_particle_timer = 0,
        interaction_radius = 80,
        last_heal_time = 0
    }
    
    table.insert(trees, tree)
    
    -- Sync with network if enabled
    if mod_config.enable_networking then
        glowingTreeMod.syncTreeCreation(tree)
    end
    
    return tree
end

-- Update all trees
function glowingTreeMod.update(dt)
    local current_time = glowingTreeMod.api.utils.getTime()
    
    for i = #trees, 1, -1 do
        local tree = trees[i]
        if tree.active then
            -- Update animation timers
            tree.sway_time = tree.sway_time + dt
            tree.pulse_time = tree.pulse_time + dt * tree.config.pulse_speed
            tree.magic_time = tree.magic_time + dt
            
            -- Calculate effects
            tree.rotation = math.sin(tree.sway_time * 2.0) * tree.config.sway_amplitude
            tree.scale = tree.config.base_scale * (1.0 + math.sin(tree.pulse_time) * 0.1)
            tree.glow_intensity = (tree.health / tree.max_health) * 0.8
            
            -- Spawn particles
            if mod_config.enable_particles then
                tree.magic_particle_timer = tree.magic_particle_timer + dt
                if tree.magic_particle_timer > 0.5 then
                    glowingTreeMod.spawnMagicParticles(tree)
                    tree.magic_particle_timer = 0
                end
            end
            
            -- Add tree to render queue
            glowingTreeMod.renderTree(tree)
        else
            table.remove(trees, i)
        end
    end
end

-- Render a tree
function glowingTreeMod.renderTree(tree)
    local api = glowingTreeMod.api
    
    -- Main tree sprite with shader
    if tree_shader then
        api.renderer.addToQueue("world", {
            type = "shader_sprite",
            texture_name = "tileset_plant",
            shader = tree_shader,
            x = tree.x,
            y = tree.y,
            rotation = tree.rotation,
            scale_x = tree.scale,
            scale_y = tree.scale,
            sort_y = tree.y + 50,
            active = true,
            color = {1, 1, 1, 1},
            shader_params = {
                time = tree.magic_time,
                glow_color = tree.config.glow_color,
                glow_intensity = tree.glow_intensity,
                health_factor = tree.health / tree.max_health
            }
        })
    else
        -- Fallback rendering
        api.renderer.addToQueue("world", {
            type = "sprite",
            texture_name = "tileset_plant",
            x = tree.x,
            y = tree.y,
            rotation = tree.rotation,
            scale_x = tree.scale,
            scale_y = tree.scale,
            sort_y = tree.y + 50,
            active = true,
            color = tree.config.glow_color
        })
    end
    
    -- Magical aura
    api.renderer.addToQueue("effects", {
        type = "circle",
        mode = "fill",
        x = tree.x,
        y = tree.y,
        radius = 25 + math.sin(tree.pulse_time) * 5,
        sort_y = tree.y + 49,
        active = true,
        color = {
            tree.config.glow_color[1],
            tree.config.glow_color[2],
            tree.config.glow_color[3],
            tree.glow_intensity * 0.2
        },
        blend_mode = {"add"}
    })
    
    -- Health bar if damaged
    if tree.health < tree.max_health then
        local health_percent = tree.health / tree.max_health
        local bar_width = 30
        local bar_height = 4
        local bar_y = tree.y - 40
        
        -- Background
        api.renderer.addToQueue("ui", {
            type = "rectangle",
            mode = "fill",
            x = tree.x - bar_width/2,
            y = bar_y,
            width = bar_width,
            height = bar_height,
            sort_y = 10000,
            active = true,
            color = {0.2, 0.2, 0.2, 0.8}
        })
        
        -- Health fill
        api.renderer.addToQueue("ui", {
            type = "rectangle",
            mode = "fill",
            x = tree.x - bar_width/2 + 1,
            y = bar_y + 1,
            width = (bar_width - 2) * health_percent,
            height = bar_height - 2,
            sort_y = 10001,
            active = true,
            color = health_percent > 0.5 and {0.2, 0.8, 0.4, 0.9} or {0.8, 0.4, 0.2, 0.9}
        })
    end
end

-- Spawn magical particles
function glowingTreeMod.spawnMagicParticles(tree)
    local api = glowingTreeMod.api
    
    -- Create floating particles
    for i = 1, math.random(2, 4) do
        local offset_x = (math.random() - 0.5) * 50
        local offset_y = (math.random() - 0.5) * 60
        
        api.renderer.addParticleEffect(
            "tree_magic_" .. tree.id .. "_" .. i,
            tree.x + offset_x,
            tree.y + offset_y,
            "magic_sparkle",
            {
                lifetime = 1.5 + math.random() * 1.0,
                color = tree.config.glow_color
            }
        )
    end
    
    -- Add ambient light
    api.renderer.addLight(
        tree.x,
        tree.y - 10,
        30 + math.sin(tree.magic_time * 2) * 8,
        tree.config.glow_color,
        tree.glow_intensity * 0.4
    )
end

-- Handle player interaction
function glowingTreeMod.handleInteraction(key)
    if key ~= "e" then return end
    
    local api = glowingTreeMod.api
    local player_x, player_y = api.game.getPlayerPosition()
    
    -- Find nearby tree
    local nearby_tree = nil
    local min_distance = math.huge
    
    for _, tree in ipairs(trees) do
        if tree.active then
            local distance = math.sqrt((player_x - tree.x)^2 + (player_y - tree.y)^2)
            if distance <= tree.interaction_radius and distance < min_distance then
                min_distance = distance
                nearby_tree = tree
            end
        end
    end
    
    if nearby_tree then
        glowingTreeMod.interactWithTree(nearby_tree)
    end
end

-- Interact with a specific tree
function glowingTreeMod.interactWithTree(tree)
    if not tree.active or not mod_config.enable_healing then return end
    
    local api = glowingTreeMod.api
    local current_time = api.utils.getTime()
    
    -- Cooldown check
    if current_time - tree.last_heal_time < 3.0 then
        print("[GLOWING_TREE_MOD] Tree is still recovering energy...")
        return
    end
    
    -- Heal player
    local player_health = api.game.getPlayerHealth()
    local heal_amount = tree.config.healing_power + math.random(5)
    
    api.game.setPlayerHealth(player_health + heal_amount)
    tree.last_heal_time = current_time
    
    -- Create healing effect
    api.renderer.addParticleEffect(
        "tree_heal_" .. tree.id,
        tree.x,
        tree.y - 20,
        "healing_sparkle",
        {
            lifetime = 2.0,
            color = {0.2, 1, 0.4, 1},
            count = 8
        }
    )
    
    -- Reduce tree energy slightly
    tree.health = math.max(10, tree.health - 3)
    
    print("[GLOWING_TREE_MOD] " .. tree.type .. " tree healed you for " .. heal_amount .. " HP!")
    
    -- Sync with network
    if mod_config.enable_networking then
        glowingTreeMod.syncTreeHealing(tree, heal_amount)
    end
end

-- Spawn tree at player location
function glowingTreeMod.spawnTreeAtPlayer(key)
    if key ~= "t" then return end
    
    local api = glowingTreeMod.api
    local player_x, player_y = api.game.getPlayerPosition()
    
    local tree_types = {"MYSTICAL", "ANCIENT", "ENCHANTED"}
    local random_type = tree_types[math.random(#tree_types)]
    
    local tree = glowingTreeMod.createTree(player_x + 30, player_y, random_type, 80 + math.random(40))
    if tree then
        print("[GLOWING_TREE_MOD] Spawned " .. random_type .. " tree at your location!")
    end
end

-- Network synchronization
function glowingTreeMod.syncTreeCreation(tree)
    local api = glowingTreeMod.api
    api.network.sendToAll({
        action = "create_tree",
        tree_data = {
            id = tree.id,
            x = tree.x,
            y = tree.y,
            type = tree.type,
            health = tree.health
        }
    }, "glowing_tree_mod")
end

function glowingTreeMod.syncTreeHealing(tree, heal_amount)
    local api = glowingTreeMod.api
    api.network.sendToAll({
        action = "tree_healing",
        tree_id = tree.id,
        heal_amount = heal_amount,
        new_health = tree.health
    }, "glowing_tree_mod")
end

-- Handle network messages
function glowingTreeMod.handleNetworkMessage(data)
    if data.action == "create_tree" then
        local tree_data = data.tree_data
        glowingTreeMod.createTree(tree_data.x, tree_data.y, tree_data.type, tree_data.health)
    elseif data.action == "tree_healing" then
        -- Find tree and update its health
        for _, tree in ipairs(trees) do
            if tree.id == data.tree_id then
                tree.health = data.new_health
                break
            end
        end
    end
end

-- Get mod statistics
function glowingTreeMod.getStats()
    local stats = {
        total_trees = #trees,
        active_trees = 0,
        trees_by_type = {}
    }
    
    for _, tree in ipairs(trees) do
        if tree.active then
            stats.active_trees = stats.active_trees + 1
            stats.trees_by_type[tree.type] = (stats.trees_by_type[tree.type] or 0) + 1
        end
    end
    
    return stats
end

-- Cleanup
function glowingTreeMod.cleanup()
    trees = {}
    tree_count = 0
    print("[GLOWING_TREE_MOD] Cleanup complete")
end

-- Mod interface - what the mod system expects
return glowingTreeMod