-- Health & Damage Indicators Mod - Main Entry Point
-- This mod provides health bars and floating damage indicators

local healthDamageMod = {}

-- Mod state
local health_bars = {}
local damage_indicators = {}
local heal_indicators = {}
local indicator_counter = 0
local mod_config = {}

-- Visual configuration
local INDICATOR_CONFIG = {
    -- Damage indicators
    damage = {
        base_color = {1, 0.8, 0.2, 1},       -- Yellow for normal damage
        critical_color = {1, 0.2, 0.2, 1},   -- Red for critical damage
        font_size = 16,
        critical_threshold = 25,
        float_speed = 30,
        fade_speed = 2.0,
        duration = 1.5,
        offset_variation = 15
    },
    
    -- Heal indicators
    heal = {
        color = {0.2, 1, 0.4, 1},            -- Green for healing
        font_size = 14,
        float_speed = 25,
        fade_speed = 1.5,
        duration = 1.2,
        offset_variation = 10
    },
    
    -- Health bars
    health_bar = {
        width = 40,
        height = 6,
        background_color = {0.2, 0.2, 0.2, 0.8},
        health_color = {0.2, 0.8, 0.2, 0.9},
        low_health_color = {0.8, 0.2, 0.2, 0.9},
        critical_health_color = {1, 0.1, 0.1, 1},
        border_color = {0.1, 0.1, 0.1, 1},
        offset_y = -30,
        duration = 3.0,
        low_health_threshold = 0.3,
        critical_health_threshold = 0.15
    }
}

-- Initialize the mod
function healthDamageMod.init(api)
    print("[HEALTH_DAMAGE_MOD] Initializing Health & Damage Indicators v1.0.0")
    
    -- Store API reference
    healthDamageMod.api = api
    
    -- Load configuration
    mod_config = {
        health_bar_duration = 3.0,
        damage_indicator_duration = 1.5,
        floating_speed = 30,
        enable_critical_colors = true,
        enable_animations = true
    }
    
    print("[HEALTH_DAMAGE_MOD] Initialization complete!")
end

-- Show health bar for an entity
function healthDamageMod.showHealthBar(entity_id, x, y, current_health, max_health, entity_type)
    entity_type = entity_type or "enemy"
    
    -- Remove existing health bar for this entity
    for i = #health_bars, 1, -1 do
        if health_bars[i].entity_id == entity_id then
            table.remove(health_bars, i)
        end
    end
    
    local health_bar = {
        entity_id = entity_id,
        x = x,
        y = y,
        current_health = current_health,
        max_health = max_health,
        entity_type = entity_type,
        duration = mod_config.health_bar_duration,
        timer = mod_config.health_bar_duration,
        active = true,
        flash_timer = 0,
        last_health = current_health
    }
    
    table.insert(health_bars, health_bar)
    return health_bar
end

-- Update health bar for an entity
function healthDamageMod.updateHealthBar(entity_id, current_health, max_health, x, y)
    for _, health_bar in ipairs(health_bars) do
        if health_bar.entity_id == entity_id and health_bar.active then
            -- Check if health changed (for flash effect)
            if current_health < health_bar.current_health then
                health_bar.flash_timer = 0.2
            end
            
            health_bar.current_health = current_health
            health_bar.max_health = max_health
            health_bar.x = x or health_bar.x
            health_bar.y = y or health_bar.y
            health_bar.timer = mod_config.health_bar_duration -- Reset timer
            return true
        end
    end
    return false
end

-- Hide health bar for an entity
function healthDamageMod.hideHealthBar(entity_id)
    for i = #health_bars, 1, -1 do
        if health_bars[i].entity_id == entity_id then
            table.remove(health_bars, i)
        end
    end
end

-- Show damage indicator
function healthDamageMod.showDamageIndicator(x, y, damage, is_critical)
    is_critical = is_critical or (damage >= INDICATOR_CONFIG.damage.critical_threshold)
    indicator_counter = indicator_counter + 1
    
    local config = INDICATOR_CONFIG.damage
    local color = is_critical and config.critical_color or config.base_color
    
    local indicator = {
        id = indicator_counter,
        x = x + math.random(-config.offset_variation, config.offset_variation),
        y = y,
        start_y = y,
        damage = damage,
        text = tostring(math.floor(damage)),
        color = {color[1], color[2], color[3], color[4]},
        timer = config.duration,
        duration = config.duration,
        is_critical = is_critical,
        scale = is_critical and 1.2 or 1.0,
        active = true
    }
    
    table.insert(damage_indicators, indicator)
    return indicator
end

-- Show heal indicator
function healthDamageMod.showHealIndicator(x, y, heal_amount)
    indicator_counter = indicator_counter + 1
    
    local config = INDICATOR_CONFIG.heal
    
    local indicator = {
        id = indicator_counter,
        x = x + math.random(-config.offset_variation, config.offset_variation),
        y = y,
        start_y = y,
        heal = heal_amount,
        text = "+" .. tostring(math.floor(heal_amount)),
        color = {config.color[1], config.color[2], config.color[3], config.color[4]},
        timer = config.duration,
        duration = config.duration,
        scale = 1.0,
        active = true
    }
    
    table.insert(heal_indicators, indicator)
    return indicator
end

-- Update all indicators
function healthDamageMod.update(dt)
    local current_time = healthDamageMod.api.utils.getTime()
    
    -- Update health bars
    for i = #health_bars, 1, -1 do
        local health_bar = health_bars[i]
        
        if health_bar.active then
            health_bar.timer = health_bar.timer - dt
            health_bar.flash_timer = math.max(0, health_bar.flash_timer - dt)
            
            if health_bar.timer <= 0 then
                table.remove(health_bars, i)
            else
                healthDamageMod.renderHealthBar(health_bar)
            end
        else
            table.remove(health_bars, i)
        end
    end
    
    -- Update damage indicators
    for i = #damage_indicators, 1, -1 do
        local indicator = damage_indicators[i]
        
        if indicator.active then
            indicator.timer = indicator.timer - dt
            indicator.y = indicator.y - INDICATOR_CONFIG.damage.float_speed * dt
            
            -- Fade out
            local fade_progress = 1 - (indicator.timer / indicator.duration)
            indicator.color[4] = 1 - fade_progress
            
            -- Scale animation for critical hits
            if indicator.is_critical and indicator.timer > indicator.duration * 0.8 then
                local scale_progress = (indicator.duration - indicator.timer) / (indicator.duration * 0.2)
                indicator.scale = 1.2 + math.sin(scale_progress * math.pi) * 0.3
            end
            
            if indicator.timer <= 0 then
                table.remove(damage_indicators, i)
            else
                healthDamageMod.renderDamageIndicator(indicator)
            end
        else
            table.remove(damage_indicators, i)
        end
    end
    
    -- Update heal indicators
    for i = #heal_indicators, 1, -1 do
        local indicator = heal_indicators[i]
        
        if indicator.active then
            indicator.timer = indicator.timer - dt
            indicator.y = indicator.y - INDICATOR_CONFIG.heal.float_speed * dt
            
            -- Fade out
            local fade_progress = 1 - (indicator.timer / indicator.duration)
            indicator.color[4] = 1 - fade_progress
            
            if indicator.timer <= 0 then
                table.remove(heal_indicators, i)
            else
                healthDamageMod.renderHealIndicator(indicator)
            end
        else
            table.remove(heal_indicators, i)
        end
    end
end

-- Render health bar
function healthDamageMod.renderHealthBar(health_bar)
    local api = healthDamageMod.api
    local config = INDICATOR_CONFIG.health_bar
    
    local health_percent = health_bar.current_health / health_bar.max_health
    local bar_x = health_bar.x - config.width / 2
    local bar_y = health_bar.y + config.offset_y
    
    -- Determine health bar color based on health percentage
    local health_color = config.health_color
    if health_percent <= config.critical_health_threshold then
        health_color = config.critical_health_color
    elseif health_percent <= config.low_health_threshold then
        health_color = config.low_health_color
    end
    
    -- Flash effect when damaged
    if health_bar.flash_timer > 0 then
        local flash_intensity = health_bar.flash_timer / 0.2
        health_color = {
            health_color[1] + (1 - health_color[1]) * flash_intensity,
            health_color[2] * (1 - flash_intensity * 0.8),
            health_color[3] * (1 - flash_intensity * 0.8),
            health_color[4]
        }
    end
    
    -- Background border
    api.renderer.addToQueue("ui", {
        type = "rectangle",
        mode = "fill",
        x = bar_x - 1,
        y = bar_y - 1,
        width = config.width + 2,
        height = config.height + 2,
        sort_y = 10000,
        active = true,
        color = config.border_color
    })
    
    -- Background
    api.renderer.addToQueue("ui", {
        type = "rectangle",
        mode = "fill",
        x = bar_x,
        y = bar_y,
        width = config.width,
        height = config.height,
        sort_y = 10001,
        active = true,
        color = config.background_color
    })
    
    -- Health fill
    if health_percent > 0 then
        api.renderer.addToQueue("ui", {
            type = "rectangle",
            mode = "fill",
            x = bar_x + 1,
            y = bar_y + 1,
            width = (config.width - 2) * health_percent,
            height = config.height - 2,
            sort_y = 10002,
            active = true,
            color = health_color
        })
    end
    
    -- Health text for bosses
    if health_bar.entity_type == "boss" then
        api.renderer.addToQueue("ui", {
            type = "text",
            text = math.floor(health_bar.current_health) .. "/" .. math.floor(health_bar.max_health),
            x = health_bar.x,
            y = bar_y - 12,
            font = "default",
            sort_y = 10003,
            active = true,
            color = {1, 1, 1, 1},
            align = "center"
        })
    end
end

-- Render damage indicator
function healthDamageMod.renderDamageIndicator(indicator)
    local api = healthDamageMod.api
    
    api.renderer.addToQueue("ui", {
        type = "text",
        text = indicator.text,
        x = indicator.x,
        y = indicator.y,
        font = "default",
        sort_y = 10005,
        active = true,
        color = indicator.color,
        scale = indicator.scale,
        align = "center"
    })
    
    -- Critical hit effect - add glow
    if indicator.is_critical and indicator.color[4] > 0.5 then
        for dx = -1, 1 do
            for dy = -1, 1 do
                if dx ~= 0 or dy ~= 0 then
                    api.renderer.addToQueue("ui", {
                        type = "text",
                        text = indicator.text,
                        x = indicator.x + dx,
                        y = indicator.y + dy,
                        font = "default",
                        sort_y = 10004,
                        active = true,
                        color = {0, 0, 0, indicator.color[4] * 0.8},
                        scale = indicator.scale,
                        align = "center"
                    })
                end
            end
        end
    end
end

-- Render heal indicator
function healthDamageMod.renderHealIndicator(indicator)
    local api = healthDamageMod.api
    
    api.renderer.addToQueue("ui", {
        type = "text",
        text = indicator.text,
        x = indicator.x,
        y = indicator.y,
        font = "default",
        sort_y = 10005,
        active = true,
        color = indicator.color,
        scale = indicator.scale,
        align = "center"
    })
end

-- Handle entity damage (called by other mods)
function healthDamageMod.onEntityDamage(entity_id, x, y, damage, current_health, max_health, entity_type)
    -- Show damage indicator
    local is_critical = damage >= INDICATOR_CONFIG.damage.critical_threshold
    healthDamageMod.showDamageIndicator(x, y - 10, damage, is_critical)
    
    -- Show or update health bar
    if not healthDamageMod.updateHealthBar(entity_id, current_health, max_health, x, y) then
        healthDamageMod.showHealthBar(entity_id, x, y, current_health, max_health, entity_type)
    end
end

-- Handle entity healing (called by other mods)
function healthDamageMod.onEntityHeal(entity_id, x, y, heal_amount, current_health, max_health, entity_type)
    -- Show heal indicator
    healthDamageMod.showHealIndicator(x, y - 10, heal_amount)
    
    -- Update health bar
    if not healthDamageMod.updateHealthBar(entity_id, current_health, max_health, x, y) then
        healthDamageMod.showHealthBar(entity_id, x, y, current_health, max_health, entity_type)
    end
end

-- Get statistics
function healthDamageMod.getStats()
    return {
        active_health_bars = #health_bars,
        active_damage_indicators = #damage_indicators,
        active_heal_indicators = #heal_indicators,
        total_indicators_created = indicator_counter
    }
end

-- Cleanup
function healthDamageMod.cleanup()
    health_bars = {}
    damage_indicators = {}
    heal_indicators = {}
    indicator_counter = 0
    print("[HEALTH_DAMAGE_MOD] Cleanup complete")
end

-- Mod interface - exports for other mods
healthDamageMod.exports = {
    showHealthBar = healthDamageMod.showHealthBar,
    showDamageIndicator = healthDamageMod.showDamageIndicator,
    showHealIndicator = healthDamageMod.showHealIndicator,
    hideHealthBar = healthDamageMod.hideHealthBar,
    updateHealthBar = healthDamageMod.updateHealthBar,
    onEntityDamage = healthDamageMod.onEntityDamage,
    onEntityHeal = healthDamageMod.onEntityHeal,
    getStats = healthDamageMod.getStats
}

return healthDamageMod