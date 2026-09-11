local indicators = {}

indicators.list = {}
indicators.nextId = 1

local function generateId()
    local id = indicators.nextId
    indicators.nextId = indicators.nextId + 1
    return id
end

function indicators.create(config)
    local indicator = {
        id = generateId(),
        x = config.x or 0,
        y = config.y or 0,
        text = config.text or "",
        color = config.color or {1, 1, 1, 1},
        font_size = config.font_size or 20,
        scale = config.scale or 1,
        velocity_x = config.velocity_x or 0,
        velocity_y = config.velocity_y or -50,
        acceleration_x = config.acceleration_x or 0,
        acceleration_y = config.acceleration_y or 20,
        friction = config.friction or 0.95,
        duration = config.duration or 2.0,
        fade_start = config.fade_start or 0.7,
        alpha = config.alpha or 1,
        start_time = love.timer.getTime(),
        type = config.type or "standard",
        special_effects = config.special_effects or {},
        outline = config.outline ~= false,
        outline_color = config.outline_color or {0, 0, 0, 1},
        font = config.font or "default",
        layer = config.layer or 5,
        spread_group = config.spread_group or nil,
        easing = config.easing or "cubic_ease_out",
        glow = config.glow or false,
        glow_size = config.glow_size or 3,
        bounce = config.bounce or false,
        bounce_height = config.bounce_height or 10,
        rotation = config.rotation or 0,
        rotation_speed = config.rotation_speed or 0,
        pulse = config.pulse or false,
        pulse_speed = config.pulse_speed or 2,
        pulse_magnitude = config.pulse_magnitude or 0.2
    }
    
    if indicator.spread_group then
        indicators.applySpread(indicator)
    end
    
    table.insert(indicators.list, indicator)
    return indicator.id
end

function indicators.applySpread(new_indicator)
    local spread_distance = 30
    local nearby_indicators = {}
    
    for _, indicator in ipairs(indicators.list) do
        if indicator.spread_group == new_indicator.spread_group then
            local distance = math.sqrt((indicator.x - new_indicator.x)^2 + (indicator.y - new_indicator.y)^2)
            if distance < 80 then
                table.insert(nearby_indicators, indicator)
            end
        end
    end
    
    if #nearby_indicators > 0 then
        local angle_step = (2 * math.pi) / 8
        local angle = angle_step * (#nearby_indicators % 8)
        
        new_indicator.x = new_indicator.x + math.cos(angle) * spread_distance
        new_indicator.y = new_indicator.y + math.sin(angle) * spread_distance
        
        local overlap_factor = math.min(#nearby_indicators / 5, 1)
        new_indicator.velocity_y = new_indicator.velocity_y * (1 + overlap_factor * 0.5)
        new_indicator.duration = new_indicator.duration * (1 + overlap_factor * 0.3)
    end
end

function indicators.createDamage(x, y, damage, is_critical, is_mega_critical)
    local color = {1, 0.4, 0.4, 1}
    local scale = 1
    local special_effects = {}
    
    if is_mega_critical then
        color = {0.8, 0.2, 1, 1}
        scale = 1.5
        special_effects = {"stars", "glow", "pulse"}
    elseif is_critical then
        if damage >= 25 then
            color = {1, 0.6, 0.2, 1}
        else
            color = {1, 1, 0.3, 1}
        end
        scale = 1.2
        special_effects = {"exclamation", "glow"}
    end
    
    return indicators.create({
        x = x,
        y = y,
        text = tostring(math.floor(damage)),
        color = color,
        scale = scale,
        velocity_y = -60,
        duration = 1.8,
        special_effects = special_effects,
        spread_group = "damage",
        type = "damage",
        glow = is_critical or is_mega_critical,
        pulse = is_mega_critical
    })
end

function indicators.createNoticed(x, y, text)
    text = text or "!"
    return indicators.create({
        x = x,
        y = y - 20,
        text = text,
        color = {1, 1, 0.2, 1},
        font_size = 24,
        scale = 1.2,
        velocity_y = -30,
        duration = 1.5,
        special_effects = {"exclamation", "bounce"},
        type = "noticed",
        bounce = true,
        pulse = true,
        pulse_speed = 4
    })
end

function indicators.createPickup(x, y, text, item_type)
    local color = {0.3, 1, 0.3, 1}
    local special_effects = {"glow"}
    
    if item_type == "coin" then
        color = {1, 1, 0.3, 1}
    elseif item_type == "health" then
        color = {1, 0.3, 0.3, 1}
    elseif item_type == "ammo" then
        color = {0.3, 0.3, 1, 1}
    end
    
    return indicators.create({
        x = x,
        y = y - 10,
        text = text,
        color = color,
        velocity_y = -40,
        duration = 2.0,
        special_effects = special_effects,
        type = "pickup",
        glow = true
    })
end

function indicators.createSplash(x, y)
    return indicators.create({
        x = x,
        y = y,
        text = "SPLASH!",
        color = {0.3, 1, 1, 1},
        font_size = 28,
        scale = 1.3,
        velocity_y = -50,
        duration = 2.2,
        special_effects = {"glow", "pulse"},
        type = "splash",
        glow = true,
        glow_size = 5
    })
end

function indicators.createCustom(x, y, text, style_name)
    local styles = {
        alert = {
            color = {1, 0.2, 0.2, 1},
            font_size = 32,
            special_effects = {"pulse", "glow"},
            duration = 3.0,
            pulse = true
        },
        success = {
            color = {0.2, 1, 0.2, 1},
            font_size = 24,
            special_effects = {"glow"},
            velocity_y = -35,
            duration = 2.5
        },
        warning = {
            color = {1, 1, 0.2, 1},
            font_size = 26,
            special_effects = {"bounce"},
            bounce = true,
            duration = 2.0
        },
        info = {
            color = {0.2, 0.7, 1, 1},
            font_size = 22,
            velocity_y = -45,
            duration = 2.2
        }
    }
    
    local style = styles[style_name] or styles.info
    local config = {
        x = x,
        y = y,
        text = text,
        type = "custom_" .. (style_name or "info")
    }
    
    for k, v in pairs(style) do
        config[k] = v
    end
    
    return indicators.create(config)
end

local function easeFunction(t, easing_type)
    if easing_type == "cubic_ease_out" then
        return 1 - (1 - t)^3
    elseif easing_type == "ease_out_back" then
        local c1 = 1.70158
        local c3 = c1 + 1
        return 1 + c3 * (t - 1)^3 + c1 * (t - 1)^2
    elseif easing_type == "bounce" then
        if t < 1/2.75 then
            return 7.5625 * t * t
        elseif t < 2/2.75 then
            t = t - 1.5/2.75
            return 7.5625 * t * t + 0.75
        elseif t < 2.5/2.75 then
            t = t - 2.25/2.75
            return 7.5625 * t * t + 0.9375
        else
            t = t - 2.625/2.75
            return 7.5625 * t * t + 0.984375
        end
    else
        return t
    end
end

function indicators.update(dt)
    local current_time = love.timer.getTime()
    
    for i = #indicators.list, 1, -1 do
        local indicator = indicators.list[i]
        local elapsed = current_time - indicator.start_time
        local progress = elapsed / indicator.duration
        
        if progress >= 1 then
            table.remove(indicators.list, i)
        else
            local eased_progress = easeFunction(progress, indicator.easing)
            
            indicator.velocity_x = indicator.velocity_x + indicator.acceleration_x * dt
            indicator.velocity_y = indicator.velocity_y + indicator.acceleration_y * dt
            indicator.velocity_x = indicator.velocity_x * indicator.friction
            indicator.velocity_y = indicator.velocity_y * indicator.friction
            
            indicator.x = indicator.x + indicator.velocity_x * dt
            indicator.y = indicator.y + indicator.velocity_y * dt
            
            if indicator.bounce and progress < 0.5 then
                local bounce_offset = math.sin(progress * math.pi * 4) * indicator.bounce_height * (1 - progress * 2)
                indicator.y = indicator.y + bounce_offset * dt * 60
            end
            
            if indicator.rotation_speed ~= 0 then
                indicator.rotation = indicator.rotation + indicator.rotation_speed * dt
            end
            
            if progress > indicator.fade_start then
                local fade_progress = (progress - indicator.fade_start) / (1 - indicator.fade_start)
                indicator.alpha = (1 - fade_progress) * indicator.color[4]
            else
                indicator.alpha = indicator.color[4]
            end
            
            if indicator.pulse then
                local pulse_factor = 1 + math.sin(elapsed * indicator.pulse_speed * math.pi) * indicator.pulse_magnitude
                indicator.current_scale = indicator.scale * pulse_factor
            else
                indicator.current_scale = indicator.scale
            end
        end
    end
end

function indicators.populate(dynamic_draw_list)
    if #indicators.list > 0 then
        print("Populating", #indicators.list, "indicators")
    end
    for _, indicator in ipairs(indicators.list) do
        table.insert(dynamic_draw_list, {
            sort_y = indicator.y + (indicator.layer * 100),
            type = "indicator",
            data = indicator,
            color = {1, 1, 1, 1},
            blend_mode = {"alpha"}
        })
    end
end

function indicators.draw(indicator_data)
    print("Drawing indicator:", indicator_data.text)
    local old_font = love.graphics.getFont()
    
    if indicator_data.font ~= "default" and indicator_data.font then
        love.graphics.setFont(indicator_data.font)
    end
    
    love.graphics.push()
    love.graphics.translate(indicator_data.x, indicator_data.y)
    
    if indicator_data.rotation ~= 0 then
        love.graphics.rotate(indicator_data.rotation)
    end
    
    love.graphics.scale(indicator_data.current_scale or indicator_data.scale)
    
    local text = indicator_data.text
    
    if indicator_data.special_effects then
        for _, effect in ipairs(indicator_data.special_effects) do
            if effect == "exclamation" then
                text = text .. "!"
            elseif effect == "stars" then
                text = "★ " .. text .. " ★"
            end
        end
    end
    
    if indicator_data.glow then
        for i = 1, indicator_data.glow_size do
            love.graphics.setColor(indicator_data.color[1], indicator_data.color[2], indicator_data.color[3], indicator_data.alpha * 0.3 / i)
            love.graphics.printf(text, -i, -i, 0, "center")
            love.graphics.printf(text, i, -i, 0, "center")
            love.graphics.printf(text, -i, i, 0, "center")
            love.graphics.printf(text, i, i, 0, "center")
        end
    end
    
    if indicator_data.outline then
        love.graphics.setColor(indicator_data.outline_color[1], indicator_data.outline_color[2], indicator_data.outline_color[3], indicator_data.alpha)
        love.graphics.printf(text, -1, -1, 0, "center")
        love.graphics.printf(text, 1, -1, 0, "center")
        love.graphics.printf(text, -1, 1, 0, "center")
        love.graphics.printf(text, 1, 1, 0, "center")
    end
    
    love.graphics.setColor(indicator_data.color[1], indicator_data.color[2], indicator_data.color[3], indicator_data.alpha)
    love.graphics.printf(text, 0, 0, 0, "center")
    
    love.graphics.pop()
    love.graphics.setFont(old_font)
end

function indicators.clear()
    indicators.list = {}
end

function indicators.removeById(id)
    for i, indicator in ipairs(indicators.list) do
        if indicator.id == id then
            table.remove(indicators.list, i)
            return true
        end
    end
    return false
end

function indicators.getCount()
    return #indicators.list
end

return indicators