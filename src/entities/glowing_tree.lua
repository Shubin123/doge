local glowingTree = {}

-- Tree configuration
local trees = {}
local tree_count = 0

-- Shader and effect configuration
local tree_shader = nil
local glow_effect_active = true
local wind_strength = 1.0
local magic_intensity = 0.8

-- Tree properties
local TREE_TYPES = {
    MYSTICAL = {
        glow_color = {0.2, 0.8, 0.4, 1.0},
        magic_particles = "leaves_sheet",
        base_scale = 1.2,
        sway_amplitude = 0.15,
        pulse_speed = 2.0
    },
    ANCIENT = {
        glow_color = {0.8, 0.6, 0.2, 1.0},
        magic_particles = "holy_light",
        base_scale = 1.5,
        sway_amplitude = 0.1,
        pulse_speed = 1.5
    },
    ENCHANTED = {
        glow_color = {0.6, 0.2, 0.9, 1.0},
        magic_particles = "electric_aura",
        base_scale = 1.0,
        sway_amplitude = 0.2,
        pulse_speed = 3.0
    }
}

-- Initialize glowing tree system
function glowingTree.init(new_renderer)
    if not new_renderer then
        print("[GLOWING_TREE] Error: New renderer not provided!")
        return false
    end
    
    -- Store reference to new renderer
    glowingTree.renderer = new_renderer
    
    -- Create tree shader
    tree_shader = glowingTree.renderer.loadShader("glowing_tree", nil, "src/shaders/glowing_tree.frag")
    
    if not tree_shader then
        print("[GLOWING_TREE] Warning: Could not load tree shader, using fallback rendering")
    end
    
    print("[GLOWING_TREE] Glowing tree system initialized!")
    return true
end

-- Create a new glowing tree
function glowingTree.createTree(x, y, tree_type, health)
    tree_type = tree_type or "MYSTICAL"
    health = health or 100
    
    if not TREE_TYPES[tree_type] then
        print("[GLOWING_TREE] Warning: Unknown tree type " .. tree_type .. ", using MYSTICAL")
        tree_type = "MYSTICAL"
    end
    
    local tree_config = TREE_TYPES[tree_type]
    
    local tree = {
        id = tree_count + 1,
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
        
        -- Effects
        glow_intensity = 1.0,
        magic_particle_timer = 0,
        last_magic_spawn = 0,
        
        -- Animation properties
        base_scale = tree_config.base_scale,
        current_sway = 0,
        current_pulse = 1.0,
        
        -- Interaction
        can_interact = true,
        interaction_radius = 80,
        
        -- Physics (if needed)
        collision_radius = 25
    }
    
    tree_count = tree_count + 1
    table.insert(trees, tree)
    
    print("[GLOWING_TREE] Created " .. tree_type .. " tree at (" .. x .. ", " .. y .. ")")
    return tree
end

-- Update all trees
function glowingTree.update(dt)
    local current_time = love.timer.getTime()
    
    for i, tree in ipairs(trees) do
        if tree.active then
            -- Update animation timers
            tree.sway_time = tree.sway_time + dt
            tree.pulse_time = tree.pulse_time + dt * tree.config.pulse_speed
            tree.magic_time = tree.magic_time + dt
            
            -- Calculate sway effect (wind)
            tree.current_sway = math.sin(tree.sway_time * 2.0) * tree.config.sway_amplitude * wind_strength
            tree.rotation = tree.current_sway
            
            -- Calculate pulse effect (magical energy)
            tree.current_pulse = 1.0 + (math.sin(tree.pulse_time) * 0.1)
            tree.scale = tree.base_scale * tree.current_pulse
            
            -- Update glow intensity based on health
            tree.glow_intensity = (tree.health / tree.max_health) * magic_intensity
            
            -- Spawn magic particles
            tree.magic_particle_timer = tree.magic_particle_timer + dt
            if tree.magic_particle_timer > 0.5 and glowingTree.renderer then
                glowingTree.spawnMagicParticles(tree)
                tree.magic_particle_timer = 0
            end
            
            -- Add tree to render queue
            glowingTree.queueTreeForRendering(tree)
        end
    end
end

-- Spawn magical particles around tree
function glowingTree.spawnMagicParticles(tree)
    if not glowingTree.renderer then return end
    
    -- Create floating magical particles
    local particle_count = math.random(2, 5)
    
    for i = 1, particle_count do
        local offset_x = (math.random() - 0.5) * 60
        local offset_y = (math.random() - 0.5) * 80
        
        local particle_x = tree.x + offset_x
        local particle_y = tree.y + offset_y
        
        -- Add particle effect using new renderer
        glowingTree.renderer.addParticleEffect(
            "tree_magic_" .. tree.id .. "_" .. i,
            particle_x,
            particle_y,
            "magic_sparkle",
            {
                lifetime = 2.0 + math.random() * 1.5,
                color = tree.config.glow_color,
                velocity = {
                    x = (math.random() - 0.5) * 20,
                    y = -10 - math.random() * 20
                },
                fade_speed = 0.8
            }
        )
    end
    
    -- Add ambient light effect
    glowingTree.renderer.addLight(
        tree.x,
        tree.y - 20,
        40 + math.sin(tree.magic_time * 2) * 10,
        tree.config.glow_color,
        tree.glow_intensity * 0.6
    )
end

-- Queue tree for rendering with shader effects
function glowingTree.queueTreeForRendering(tree)
    if not glowingTree.renderer then return end
    
    -- Calculate sort position for depth sorting
    local sort_y = tree.y + 50
    
    -- Primary tree sprite
    local tree_texture = "tileset_plant" -- Using available plant texture
    
    if tree_shader and glow_effect_active then
        -- Render with shader effects
        glowingTree.renderer.addToQueue("world", {
            type = "shader_sprite",
            texture_name = tree_texture,
            shader = tree_shader,
            x = tree.x,
            y = tree.y,
            rotation = tree.rotation,
            scale_x = tree.scale,
            scale_y = tree.scale,
            sort_y = sort_y,
            active = true,
            color = {1, 1, 1, 1},
            blend_mode = {"alpha"},
            
            -- Shader parameters
            shader_params = {
                time = tree.magic_time,
                glow_color = tree.config.glow_color,
                glow_intensity = tree.glow_intensity,
                wind_strength = wind_strength,
                sway_amplitude = tree.config.sway_amplitude,
                pulse_speed = tree.config.pulse_speed,
                health_factor = tree.health / tree.max_health
            }
        })
    else
        -- Fallback rendering without shader
        glowingTree.renderer.addToQueue("world", {
            type = "sprite",
            texture_name = tree_texture,
            x = tree.x,
            y = tree.y,
            rotation = tree.rotation,
            scale_x = tree.scale,
            scale_y = tree.scale,
            sort_y = sort_y,
            active = true,
            color = tree.config.glow_color,
            blend_mode = {"alpha"}
        })
    end
    
    -- Add magical glow overlay
    glowingTree.renderer.addToQueue("effects", {
        type = "circle",
        mode = "fill",
        x = tree.x,
        y = tree.y,
        radius = 30 + math.sin(tree.pulse_time) * 5,
        sort_y = sort_y - 1,
        active = true,
        color = {
            tree.config.glow_color[1],
            tree.config.glow_color[2],
            tree.config.glow_color[3],
            tree.glow_intensity * 0.3
        },
        blend_mode = {"add"}
    })
    
    -- Health indicator (if damaged)
    if tree.health < tree.max_health then
        local health_percent = tree.health / tree.max_health
        local bar_width = 40
        local bar_height = 6
        local bar_y = tree.y - 60
        
        -- Health bar background
        glowingTree.renderer.addToQueue("ui", {
            type = "rectangle",
            mode = "fill",
            x = tree.x - bar_width/2,
            y = bar_y,
            width = bar_width,
            height = bar_height,
            sort_y = bar_y,
            active = true,
            color = {0.2, 0.2, 0.2, 0.8},
            blend_mode = {"alpha"}
        })
        
        -- Health bar fill
        glowingTree.renderer.addToQueue("ui", {
            type = "rectangle",
            mode = "fill",
            x = tree.x - bar_width/2 + 1,
            y = bar_y + 1,
            width = (bar_width - 2) * health_percent,
            height = bar_height - 2,
            sort_y = bar_y + 1,
            active = true,
            color = health_percent > 0.5 and {0.2, 0.8, 0.4, 0.9} or {0.8, 0.4, 0.2, 0.9},
            blend_mode = {"alpha"}
        })
    end
end

-- Tree interaction system
function glowingTree.checkInteraction(player_x, player_y)
    for _, tree in ipairs(trees) do
        if tree.active and tree.can_interact then
            local distance = math.sqrt((player_x - tree.x)^2 + (player_y - tree.y)^2)
            
            if distance <= tree.interaction_radius then
                return tree
            end
        end
    end
    return nil
end

function glowingTree.interactWithTree(tree, player)
    if not tree or not tree.active then return false end
    
    -- Heal player with magical energy
    if player and player.health then
        local heal_amount = 10 + math.random(5)
        player.health = math.min(player.max_health or 100, player.health + heal_amount)
        
        -- Create healing effect
        if glowingTree.renderer then
            glowingTree.renderer.addParticleEffect(
                "tree_heal_" .. love.timer.getTime(),
                tree.x,
                tree.y - 30,
                "healing_sparkle",
                {
                    lifetime = 1.5,
                    color = {0.2, 1, 0.4, 1},
                    count = 10
                }
            )
        end
        
        -- Reduce tree energy slightly
        tree.health = math.max(1, tree.health - 5)
        
        print("[GLOWING_TREE] Tree healed player for " .. heal_amount .. " HP!")
        return true
    end
    
    return false
end

-- Damage tree
function glowingTree.damageTree(tree, damage)
    if not tree or not tree.active then return false end
    
    tree.health = math.max(0, tree.health - damage)
    
    if tree.health <= 0 then
        glowingTree.destroyTree(tree)
        return true
    end
    
    -- Create damage effect
    if glowingTree.renderer then
        glowingTree.renderer.addParticleEffect(
            "tree_damage_" .. love.timer.getTime(),
            tree.x,
            tree.y,
            "damage_sparks",
            {
                lifetime = 1.0,
                color = {1, 0.2, 0.2, 1},
                count = 5
            }
        )
    end
    
    return false
end

-- Destroy tree with effects
function glowingTree.destroyTree(tree)
    if not tree then return end
    
    -- Create destruction effect
    if glowingTree.renderer then
        glowingTree.renderer.addParticleEffect(
            "tree_destruction_" .. tree.id,
            tree.x,
            tree.y,
            "explosion",
            {
                lifetime = 2.0,
                color = tree.config.glow_color,
                count = 15
            }
        )
    end
    
    tree.active = false
    print("[GLOWING_TREE] " .. tree.type .. " tree destroyed!")
end

-- Spawn trees in area
function glowingTree.spawnTreesInArea(center_x, center_y, radius, count, tree_types)
    tree_types = tree_types or {"MYSTICAL", "ANCIENT", "ENCHANTED"}
    
    local spawned = 0
    local attempts = 0
    local max_attempts = count * 3
    
    while spawned < count and attempts < max_attempts do
        attempts = attempts + 1
        
        -- Random position within radius
        local angle = math.random() * math.pi * 2
        local distance = math.random() * radius
        
        local spawn_x = center_x + math.cos(angle) * distance
        local spawn_y = center_y + math.sin(angle) * distance
        
        -- Check for minimum distance between trees
        local too_close = false
        for _, existing_tree in ipairs(trees) do
            if existing_tree.active then
                local dist = math.sqrt((spawn_x - existing_tree.x)^2 + (spawn_y - existing_tree.y)^2)
                if dist < 60 then
                    too_close = true
                    break
                end
            end
        end
        
        if not too_close then
            local tree_type = tree_types[math.random(#tree_types)]
            local health = 80 + math.random(40)
            
            glowingTree.createTree(spawn_x, spawn_y, tree_type, health)
            spawned = spawned + 1
        end
    end
    
    print("[GLOWING_TREE] Spawned " .. spawned .. " trees in area")
    return spawned
end

-- Environmental controls
function glowingTree.setWindStrength(strength)
    wind_strength = math.max(0, math.min(2.0, strength))
end

function glowingTree.setMagicIntensity(intensity)
    magic_intensity = math.max(0, math.min(1.5, intensity))
end

function glowingTree.toggleGlowEffect()
    glow_effect_active = not glow_effect_active
    print("[GLOWING_TREE] Glow effects " .. (glow_effect_active and "enabled" or "disabled"))
end

-- Debug and utility functions
function glowingTree.getTreeCount()
    local active_count = 0
    for _, tree in ipairs(trees) do
        if tree.active then
            active_count = active_count + 1
        end
    end
    return active_count
end

function glowingTree.getNearestTree(x, y)
    local nearest = nil
    local min_distance = math.huge
    
    for _, tree in ipairs(trees) do
        if tree.active then
            local distance = math.sqrt((x - tree.x)^2 + (y - tree.y)^2)
            if distance < min_distance then
                min_distance = distance
                nearest = tree
            end
        end
    end
    
    return nearest, min_distance
end

function glowingTree.cleanup()
    trees = {}
    tree_count = 0
    tree_shader = nil
    print("[GLOWING_TREE] Cleanup complete")
end

-- Example usage function
function glowingTree.createDemoScene(center_x, center_y)
    -- Create a magical grove
    glowingTree.createTree(center_x, center_y, "ANCIENT", 120)
    glowingTree.createTree(center_x - 80, center_y + 60, "MYSTICAL", 100)
    glowingTree.createTree(center_x + 70, center_y - 40, "ENCHANTED", 90)
    glowingTree.createTree(center_x + 50, center_y + 80, "MYSTICAL", 85)
    
    print("[GLOWING_TREE] Demo magical grove created!")
end

return glowingTree