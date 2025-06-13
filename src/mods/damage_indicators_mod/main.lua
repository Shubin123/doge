-- Advanced Damage Indicators Mod
-- Provides floating damage numbers with color-coding and multiplayer synchronization

local damageIndicatorsMod = {}

-- Mod state
local indicators = {}
local indicator_id_counter = 0
local mod_config = {}
local api = nil

-- Color configurations for different damage types
local DAMAGE_COLORS = {
    normal = {1, 0.9, 0.2, 1},      -- Yellow
    critical = {1, 0.2, 0.2, 1},    -- Red
    poison = {0.6, 1, 0.2, 1},      -- Green-yellow
    fire = {1, 0.5, 0.1, 1},        -- Orange
    ice = {0.5, 0.8, 1, 1},         -- Light blue
    electric = {0.8, 0.6, 1, 1},    -- Purple
    dark = {0.5, 0.2, 0.8, 1},      -- Dark purple
    holy = {1, 1, 0.8, 1},          -- Light yellow
    physical = {0.9, 0.9, 0.9, 1}   -- White
}

local HEAL_COLORS = {
    normal = {0.2, 1, 0.4, 1},      -- Green
    regen = {0.4, 1, 0.6, 1},       -- Light green
    lifesteal = {0.8, 0.2, 0.4, 1}, -- Red-ish
    shield = {0.4, 0.6, 1, 1}       -- Blue
}

-- Initialize the mod
function damageIndicatorsMod.init(mod_api)
    api = mod_api
    api.utils.log("Initializing Advanced Damage Indicators v2.0.0", "damage_indicators_mod")
    
    -- Load configuration
    mod_config = {
        damage_indicator_duration = 1.5,
        heal_indicator_duration = 1.2,
        floating_speed = 50,
        spread_radius = 20,
        enable_critical_effects = true,
        critical_threshold = 25,
        font_size = 16,
        enable_multiplayer_sync = true,
        max_indicators_per_entity = 5
    }
    
    -- Register network handlers
    if api.network and mod_config.enable_multiplayer_sync then
        api.network.registerMessageHandler("damage_indicators_mod", function(data)
            if data.action == "damage_indicator_spawn" then
                damageIndicatorsMod.spawnIndicatorFromNetwork(data)
            elseif data.action == "heal_indicator_spawn" then
                damageIndicatorsMod.spawnHealFromNetwork(data)
            end
        end)
    end
    
    api.utils.log("Advanced Damage Indicators initialized!", "damage_indicators_mod")
end

-- Create a damage indicator
function damageIndicatorsMod.showDamageIndicator(x, y, damage, damage_type, is_critical, source_id)
    damage_type = damage_type or "normal"
    is_critical = is_critical or (damage >= mod_config.critical_threshold)
    
    -- Count existing indicators at this position
    local nearby_count = 0
    for _, ind in ipairs(indicators) do
        local dist = math.sqrt((ind.x - x)^2 + (ind.y - y)^2)
        if ind.active and dist < 50 then
            nearby_count = nearby_count + 1
        end
    end
    
    -- Limit indicators per position
    if nearby_count >= mod_config.max_indicators_per_entity then
        -- Remove oldest indicator at this position
        for i, ind in ipairs(indicators) do
            local dist = math.sqrt((ind.x - x)^2 + (ind.y - y)^2)
        if ind.active and dist < 50 then
                ind.active = false
                break
            end
        end
    end
    
    -- Calculate spread for better visibility
    local angle = (nearby_count * 72) % 360
    local rad_angle = angle * math.pi / 180
    local spread_x = math.cos(rad_angle) * mod_config.spread_radius
    local spread_y = math.sin(rad_angle) * mod_config.spread_radius * 0.5
    
    indicator_id_counter = indicator_id_counter + 1
    
    local color = DAMAGE_COLORS[damage_type] or DAMAGE_COLORS.normal
    local indicator = {
        id = indicator_id_counter,
        x = x + spread_x + math.random(-5, 5),
        y = y + spread_y - 20,
        start_x = x + spread_x,
        start_y = y + spread_y - 20,
        damage = damage,
        text = "-" .. tostring(math.floor(damage)),
        damage_type = damage_type,
        is_critical = is_critical,
        color = {color[1], color[2], color[3], color[4]},
        timer = 0,
        duration = mod_config.damage_indicator_duration,
        scale = is_critical and 1.5 or 1.0,
        velocity_x = spread_x * 0.2 + math.random(-10, 10),
        velocity_y = -mod_config.floating_speed,
        active = true,
        source_id = source_id
    }
    
    table.insert(indicators, indicator)
    
    -- Sync to network if multiplayer
    if mod_config.enable_multiplayer_sync and api.network and api.network.sendToAll then
        api.network.sendToAll({
            action = "damage_indicator_spawn",
            x = x,
            y = y,
            damage = damage,
            damage_type = damage_type,
            is_critical = is_critical,
            source_id = source_id
        }, "damage_indicators_mod")
    end
    
    return indicator
end

-- Create a heal indicator
function damageIndicatorsMod.showHealIndicator(x, y, heal_amount, heal_type, source_id)
    heal_type = heal_type or "normal"
    
    indicator_id_counter = indicator_id_counter + 1
    
    local color = HEAL_COLORS[heal_type] or HEAL_COLORS.normal
    local indicator = {
        id = indicator_id_counter,
        x = x + math.random(-10, 10),
        y = y - 20,
        start_x = x,
        start_y = y - 20,
        heal = heal_amount,
        text = "+" .. tostring(math.floor(heal_amount)),
        heal_type = heal_type,
        is_heal = true,
        color = {color[1], color[2], color[3], color[4]},
        timer = 0,
        duration = mod_config.heal_indicator_duration,
        scale = 1.0,
        velocity_x = math.random(-5, 5),
        velocity_y = -mod_config.floating_speed * 0.8,
        active = true,
        source_id = source_id
    }
    
    table.insert(indicators, indicator)
    
    -- Sync to network if multiplayer
    if mod_config.enable_multiplayer_sync and api.network and api.network.sendToAll then
        api.network.sendToAll({
            action = "heal_indicator_spawn",
            x = x,
            y = y,
            heal_amount = heal_amount,
            heal_type = heal_type,
            source_id = source_id
        }, "damage_indicators_mod")
    end
    
    return indicator
end

-- Show custom indicator with custom text and color
function damageIndicatorsMod.showCustomIndicator(x, y, text, color, duration)
    indicator_id_counter = indicator_id_counter + 1
    
    local indicator = {
        id = indicator_id_counter,
        x = x,
        y = y,
        start_x = x,
        start_y = y,
        text = text,
        custom = true,
        color = color or {1, 1, 1, 1},
        timer = 0,
        duration = duration or 1.5,
        scale = 1.0,
        velocity_x = 0,
        velocity_y = -30,
        active = true
    }
    
    table.insert(indicators, indicator)
    return indicator
end

-- Update all indicators
function damageIndicatorsMod.update(dt)
    for i = #indicators, 1, -1 do
        local indicator = indicators[i]
        
        if indicator.active then
            indicator.timer = indicator.timer + dt
            
            -- Update position
            indicator.x = indicator.x + indicator.velocity_x * dt
            indicator.y = indicator.y + indicator.velocity_y * dt
            
            -- Slow down horizontal movement
            indicator.velocity_x = indicator.velocity_x * (1 - dt * 2)
            
            -- Calculate progress
            local progress = indicator.timer / indicator.duration
            
            -- Fade out
            indicator.color[4] = 1 - progress
            
            -- Scale animation for critical hits
            if indicator.is_critical and mod_config.enable_critical_effects then
                if progress < 0.2 then
                    -- Pop-in effect
                    local scale_progress = progress / 0.2
                    indicator.scale = 1.5 + math.sin(scale_progress * math.pi) * 0.5
                else
                    -- Shrink down
                    indicator.scale = 1.5 * (1 - (progress - 0.2) * 0.3)
                end
            end
            
            -- Remove if expired
            if indicator.timer >= indicator.duration then
                table.remove(indicators, i)
            else
                -- Render the indicator
                damageIndicatorsMod.renderIndicator(indicator)
            end
        else
            table.remove(indicators, i)
        end
    end
end

-- Render an indicator
function damageIndicatorsMod.renderIndicator(indicator)
    local font_size = mod_config.font_size * indicator.scale
    
    -- Add shadow/outline for better visibility
    if indicator.is_critical or indicator.custom then
        -- Draw outline
        for dx = -1, 1 do
            for dy = -1, 1 do
                if dx ~= 0 or dy ~= 0 then
                    api.renderer.addToQueue("ui", {
                        type = "text",
                        text = indicator.text,
                        x = indicator.x + dx,
                        y = indicator.y + dy,
                        color = {0, 0, 0, indicator.color[4] * 0.8},
                        scale = indicator.scale,
                        font_size = font_size,
                        align = "center",
                        sort_y = 10000,
                        active = true
                    })
                end
            end
        end
    end
    
    -- Draw main text
    api.renderer.addToQueue("ui", {
        type = "text",
        text = indicator.text,
        x = indicator.x,
        y = indicator.y,
        color = indicator.color,
        scale = indicator.scale,
        font_size = font_size,
        align = "center",
        sort_y = 10001,
        active = true
    })
    
    -- Critical hit effects
    if indicator.is_critical and mod_config.enable_critical_effects and indicator.color[4] > 0.5 then
        -- Add glow effect
        api.renderer.addToQueue("effects", {
            type = "circle",
            mode = "fill",
            x = indicator.x,
            y = indicator.y,
            radius = 10 * indicator.scale * indicator.color[4],
            color = {indicator.color[1], indicator.color[2], indicator.color[3], indicator.color[4] * 0.2},
            sort_y = 9999,
            active = true
        })
    end
end

-- Network spawn handlers
function damageIndicatorsMod.spawnIndicatorFromNetwork(data)
    -- Don't spawn if we're the source (skip local ID check for now)
    -- TODO: Add proper network ID check when API supports it
    
    damageIndicatorsMod.showDamageIndicator(
        data.x, data.y, data.damage, 
        data.damage_type, data.is_critical, 
        data.source_id
    )
end

function damageIndicatorsMod.spawnHealFromNetwork(data)
    -- Don't spawn if we're the source (skip local ID check for now)
    -- TODO: Add proper network ID check when API supports it
    
    damageIndicatorsMod.showHealIndicator(
        data.x, data.y, data.heal_amount,
        data.heal_type, data.source_id
    )
end

-- Hook handlers
function damageIndicatorsMod.onEntityDamage(entity_id, x, y, damage, damage_type, attacker_id)
    damageIndicatorsMod.showDamageIndicator(x, y, damage, damage_type, false, attacker_id)
end

function damageIndicatorsMod.onEntityHeal(entity_id, x, y, heal_amount, heal_type, source_id)
    damageIndicatorsMod.showHealIndicator(x, y, heal_amount, heal_type, source_id)
end

function damageIndicatorsMod.onPlayerDamage(player_id, x, y, damage, damage_type, attacker_id)
    -- Show red damage for player
    local color = DAMAGE_COLORS.critical
    damageIndicatorsMod.showDamageIndicator(x, y, damage, "critical", true, attacker_id)
end

function damageIndicatorsMod.onPlayerHeal(player_id, x, y, heal_amount, heal_type, source_id)
    damageIndicatorsMod.showHealIndicator(x, y, heal_amount, heal_type, source_id)
end

-- Clear all indicators
function damageIndicatorsMod.clearIndicators()
    indicators = {}
    indicator_id_counter = 0
end

-- Set custom damage color for a type
function damageIndicatorsMod.setDamageColor(damage_type, color)
    DAMAGE_COLORS[damage_type] = color
end

-- Set custom heal color for a type
function damageIndicatorsMod.setHealColor(heal_type, color)
    HEAL_COLORS[heal_type] = color
end

-- Get statistics
function damageIndicatorsMod.getStats()
    return {
        active_indicators = #indicators,
        total_spawned = indicator_id_counter
    }
end

-- Cleanup
function damageIndicatorsMod.cleanup()
    indicators = {}
    indicator_id_counter = 0
    api.utils.log("Advanced Damage Indicators cleaned up", "damage_indicators_mod")
end

-- Mod exports
damageIndicatorsMod.exports = {
    showDamageIndicator = damageIndicatorsMod.showDamageIndicator,
    showHealIndicator = damageIndicatorsMod.showHealIndicator,
    showCustomIndicator = damageIndicatorsMod.showCustomIndicator,
    clearIndicators = damageIndicatorsMod.clearIndicators,
    setDamageColor = damageIndicatorsMod.setDamageColor,
    setHealColor = damageIndicatorsMod.setHealColor,
    onEntityDamage = damageIndicatorsMod.onEntityDamage,
    onEntityHeal = damageIndicatorsMod.onEntityHeal,
    onPlayerDamage = damageIndicatorsMod.onPlayerDamage,
    onPlayerHeal = damageIndicatorsMod.onPlayerHeal,
    getStats = damageIndicatorsMod.getStats
}

return damageIndicatorsMod