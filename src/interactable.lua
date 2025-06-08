local interactable = {}

-- Interactable types and their properties
interactable.types = {
    portal = {
        sprite = "portal.png",
        interaction_radius = 40,
        activation_key = "e",
        effect = "portal_activate"
    },
    npc = {
        sprite = "npc.png",
        interaction_radius = 50,
        activation_key = "e", 
        effect = "dialogue"
    }
}

-- Active interactables in the world
interactable.instances = {}

function interactable.load()
    -- Load sprites for interactables
    interactable.sprites = {}
    for type_name, type_data in pairs(interactable.types) do
        if love.filesystem.getInfo("gfx/" .. type_data.sprite) then
            interactable.sprites[type_name] = love.graphics.newImage("gfx/" .. type_data.sprite)
        end
    end
end

function interactable.spawn(type, x, y, properties, context)
    local type_data = interactable.types[type]
    if not type_data then
        type = "npc"
        type_data = interactable.types.npc
    end
    
    local instance = {
        type = type,
        x = x,
        y = y,
        properties = properties or {},
        active = true,
        interaction_radius = type_data.interaction_radius,
        can_interact = false,
        animation_time = 0
    }
    
    table.insert(interactable.instances, instance)
    return instance
end

function interactable.update(dt)
    for _, instance in ipairs(interactable.instances) do
        if instance.active then
            instance.animation_time = instance.animation_time + dt
            
            -- Check if player is in interaction range
            instance.can_interact = false
            if player and player.body then
                local px, py = player.body:getPosition()
                local dx = px - instance.x
                local dy = py - instance.y
                local distance = math.sqrt(dx * dx + dy * dy)
                
                if distance <= instance.interaction_radius then
                    instance.can_interact = true
                    
                    -- Check for activation key press
                    local type_data = interactable.types[instance.type]
                    if love.keyboard.isDown(type_data.activation_key) then
                        interactable.activate(instance)
                    end
                end
            end
        end
    end
end

function interactable.activate(instance)
    local type_data = interactable.types[instance.type]
    
    -- Handle different interactable types
    if instance.type == "portal" then
        -- Portal activation logic
        if instance.properties.destination then
            -- Change map or teleport player
            if map_manager and map_manager.loadMap then
                map_manager.loadMap(instance.properties.destination)
            end
        end
    elseif instance.type == "npc" then
        -- NPC dialogue or shop logic
        if instance.properties.dialogue then
            -- Show dialogue system
            print("NPC says: " .. (instance.properties.dialogue or "Hello!"))
        end
    end
    
    -- Create activation effect
    if particle_system and type_data.effect then
        if type_data.effect == "portal_activate" then
            particle_system.createEffect(particle_system.EFFECT_TYPES.ENERGY, instance.x, instance.y, {
                particle_count = 20,
                colors = {{0.5, 0, 1, 1}, {0.8, 0.3, 1, 0.8}, {0.3, 0, 0.8, 0.3}}
            })
        elseif type_data.effect == "dialogue" then
            particle_system.createEffect(particle_system.EFFECT_TYPES.SPARKS, instance.x, instance.y - 30, {
                particle_count = 5,
                colors = {{1, 1, 1, 1}, {0.8, 0.8, 1, 0.5}}
            })
        end
    end
end

function interactable.populate()
    -- Add interactables to dynamic draw list
    for _, instance in ipairs(interactable.instances) do
        if instance.active then
            local sprite = interactable.sprites[instance.type]
            if sprite then
                local glow_alpha = instance.can_interact and (0.8 + 0.2 * math.sin(instance.animation_time * 6)) or 1.0
                
                local draw_item = {
                    sort_y = instance.y,
                    image_or_particles = sprite,
                    quad = nil,
                    x = instance.x,
                    y = instance.y,
                    rotation = 0,
                    scale_x = 0.8,
                    scale_y = 0.8,
                    offset_x = sprite:getWidth() / 2,
                    offset_y = sprite:getHeight() / 2,
                    color = {1, 1, 1, glow_alpha},
                    blend_mode = {"alpha", "premultiplied"},
                    source_object_type = "interactable"
                }
                
                table.insert(dynamic_draw_list, draw_item)
                
                -- Add interaction prompt
                if instance.can_interact then
                    local prompt_text = "Press E to interact"
                    local font = love.graphics.getFont()
                    local text_width = font:getWidth(prompt_text)
                    
                    -- Add text prompt above the interactable
                    local text_draw_item = {
                        sort_y = instance.y - 50,
                        text = prompt_text,
                        x = instance.x - text_width / 2,
                        y = instance.y - 60,
                        color = {1, 1, 1, glow_alpha},
                        font = font,
                        source_object_type = "ui_text"
                    }
                    
                    table.insert(dynamic_draw_list, text_draw_item)
                end
            end
        end
    end
end

function interactable.reset()
    interactable.instances = {}
end

return interactable