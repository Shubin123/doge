local collectible = {}

-- Collectible types and their properties
collectible.types = {
    coin = {
        sprite = "coin.png",
        value = 10,
        pickup_radius = 30,
        effect = "coin_pickup"
    },
    apple = {
        sprite = "apple.png", 
        health_restore = 20,
        pickup_radius = 25,
        effect = "health_pickup"
    }
}

-- Active collectibles in the world
collectible.instances = {}

function collectible.load()
    -- Load sprites for collectibles
    collectible.sprites = {}
    for type_name, type_data in pairs(collectible.types) do
        if love.filesystem.getInfo("gfx/" .. type_data.sprite) then
            collectible.sprites[type_name] = love.graphics.newImage("gfx/" .. type_data.sprite)
        end
    end
end

function collectible.spawn(type, x, y, properties, context)
    local type_data = collectible.types[type]
    if not type_data then
        type = "coin"
        type_data = collectible.types.coin
    end
    
    local instance = {
        type = type,
        x = x,
        y = y,
        properties = properties or {},
        active = true,
        pickup_radius = type_data.pickup_radius,
        animation_time = 0
    }
    
    table.insert(collectible.instances, instance)
    return instance
end

function collectible.update(dt)
    for i = #collectible.instances, 1, -1 do
        local instance = collectible.instances[i]
        if instance.active then
            instance.animation_time = instance.animation_time + dt
            
            -- Check for player pickup
            if player and player.body then
                local px, py = player.body:getPosition()
                local dx = px - instance.x
                local dy = py - instance.y
                local distance = math.sqrt(dx * dx + dy * dy)
                
                if distance <= instance.pickup_radius then
                    collectible.pickup(i)
                end
            end
        end
    end
end

function collectible.pickup(index)
    local instance = collectible.instances[index]
    if not instance or not instance.active then return end
    
    local type_data = collectible.types[instance.type]
    
    -- Apply effects to player
    if instance.type == "coin" and player then
        -- Add coins/score
        if player.coins then
            player.coins = player.coins + type_data.value
        end
    elseif instance.type == "apple" and player then
        -- Restore health
        if player.health and type_data.health_restore then
            player.health = math.min(player.max_health or 100, player.health + type_data.health_restore)
        end
    end
    
    -- Create pickup effect
    if particle_system and type_data.effect then
        if type_data.effect == "coin_pickup" then
            particle_system.createEffect(particle_system.EFFECT_TYPES.SPARKS, instance.x, instance.y, {
                particle_count = 8,
                colors = {{1, 1, 0, 1}, {1, 0.8, 0, 0.8}, {0.8, 0.6, 0, 0.3}}
            })
        elseif type_data.effect == "health_pickup" then
            particle_system.createEffect(particle_system.EFFECT_TYPES.ENERGY, instance.x, instance.y, {
                particle_count = 10,
                colors = {{0, 1, 0, 1}, {0.5, 1, 0.5, 0.8}, {0.3, 0.8, 0.3, 0.3}}
            })
        end
    end
    
    -- Remove the collectible
    table.remove(collectible.instances, index)
end

function collectible.populate()
    -- Add collectibles to dynamic draw list
    for _, instance in ipairs(collectible.instances) do
        if instance.active then
            local sprite = collectible.sprites[instance.type]
            if sprite then
                local bobbing_offset = math.sin(instance.animation_time * 4) * 3
                
                local draw_item = {
                    sort_y = instance.y,
                    image_or_particles = sprite,
                    quad = nil,
                    x = instance.x,
                    y = instance.y + bobbing_offset,
                    rotation = instance.animation_time * 0.5,
                    scale_x = 0.5,
                    scale_y = 0.5,
                    offset_x = sprite:getWidth() / 2,
                    offset_y = sprite:getHeight() / 2,
                    color = {1, 1, 1, 1},
                    blend_mode = {"alpha", "premultiplied"},
                    source_object_type = "collectible"
                }
                
                table.insert(dynamic_draw_list, draw_item)
            end
        end
    end
end

function collectible.reset()
    collectible.instances = {}
end

return collectible