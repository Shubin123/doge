local theme = {}

-- Color definitions
local colors = {
    -- Background colors
    background = {0.05, 0.05, 0.15, 1},
    
    -- Primary colors
    accent = {0.3, 0.7, 1.0, 1},
    text = {1, 1, 1, 1},
    
    -- Button colors
    button = {0.2, 0.2, 0.4, 0.8},
    button_hover = {0.3, 0.3, 0.6, 0.9},
    
    -- Text variations
    text_faded = {1, 1, 1, 0.8},
    text_subtle = {1, 1, 1, 0.6},
    text_dim = {1, 1, 1, 0.5},
    text_very_dim = {1, 1, 1, 0.3},
    
    -- Accent variations
    accent_faded = {0.3, 0.7, 1.0, 0.9},
    
    -- List and card colors
    list_selection = {0.3, 0.3, 0.6, 0.7},
    card = {0.15, 0.15, 0.3, 0.8},
    card_hover = {0.25, 0.25, 0.5, 0.9},
    
    -- Shadow and overlay
    shadow = {0, 0, 0, 0.5},
    transition_overlay = {0, 0, 0, 1}
}

-- Font definitions and loading
local fonts = {}
local font_sizes = {
    title = 48,
    subtitle = 20,
    button = 18,
    small = 14
}

-- Metrics and spacing
local metrics = {
    -- Animation settings
    title_bounce_speed = 2.0,
    particle_count = 100,
    background_scroll_speed = 20,
    
    -- Layout metrics
    button_height = 40,
    button_spacing = 50,
    button_padding = 40,
    button_border_radius = 5,
    button_border_width = 2,
    
    -- Character selection grid
    char_per_row = 3,
    char_size = 120,
    char_spacing = 150,
    char_row_spacing = 180,
    char_card_radius = 10,
    char_portrait_scale = 0.8,
    char_placeholder_size = 80,
    char_placeholder_radius = 5,
    
    -- Map selection grid
    map_per_row = 2,
    map_size = 200,
    map_spacing = 250,
    map_row_spacing = 220,
    map_card_radius = 15,
    map_preview_margin = 20,
    map_preview_height_ratio = 0.6,
    map_preview_radius = 5,
    map_selection_border_width = 3,
    map_selection_border_offset = 5,
    
    -- Background elements
    background_circles_count = 20,
    background_rectangles_count = 15,
    background_circle_min_radius = 10,
    background_circle_max_radius = 50,
    background_rect_min_size = 20,
    background_rect_max_size = 80,
    background_min_speed = 10,
    background_max_speed = 40,
    background_circle_opacity_min = 0.05,
    background_circle_opacity_max = 0.15,
    background_rect_opacity_min = 0.03,
    background_rect_opacity_max = 0.1,
    background_wrap_margin = 100,
    
    -- Particle system
    particle_lifetime_min = 3,
    particle_lifetime_max = 8,
    particle_emission_rate = 15,
    particle_size_min = 0.1,
    particle_size_max = 0.3,
    particle_speed_min = 30,
    particle_speed_max = 80,
    particle_direction = -math.pi/2, -- Upward
    particle_spread = math.pi/3,
    particle_spin_min = -2,
    particle_spin_max = 2,
    particle_y_offset = 50,
    
    -- Screen positions
    title_y_base = 100,
    title_bounce_amplitude = 5,
    subtitle_y_offset = 60,
    version_y_offset = 90,
    main_buttons_y = 250,
    other_buttons_y = 200,
    back_button_y_offset = 80,
    char_info_y_offset = 120,
    char_stats_y_offset = 35,
    
    -- Transition
    transition_speed = 3
}

-- Initialize fonts
function theme.initialize()
    local font_path = "gfx/menu/PixelGameFont.ttf"
    
    -- Check if font file exists, fallback to default if not
    if love.filesystem.getInfo(font_path) then
        fonts.title = love.graphics.newFont(font_path, font_sizes.title)
        fonts.subtitle = love.graphics.newFont(font_path, font_sizes.subtitle)
        fonts.button = love.graphics.newFont(font_path, font_sizes.button)
        fonts.small = love.graphics.newFont(font_path, font_sizes.small)
    else
        -- Fallback to default font
        fonts.title = love.graphics.newFont(font_sizes.title)
        fonts.subtitle = love.graphics.newFont(font_sizes.subtitle)
        fonts.button = love.graphics.newFont(font_sizes.button)
        fonts.small = love.graphics.newFont(font_sizes.small)
    end
    
    -- Add font aliases for UI compatibility
    fonts.list = fonts.button
    fonts.icon = fonts.button
    fonts.card_title = fonts.subtitle
    fonts.card_description = fonts.small
    
    print("Theme initialized with fonts")
end

-- Color accessor
function theme.getColor(color_name)
    local color = colors[color_name]
    if not color then
        print("Warning: Color '" .. color_name .. "' not found, using white")
        return {1, 1, 1, 1}
    end
    return color
end

-- Font accessor
function theme.getFont(font_name)
    local font = fonts[font_name]
    if not font then
        print("Warning: Font '" .. font_name .. "' not found, using default")
        return love.graphics.getFont()
    end
    return font
end

-- Metric accessor
function theme.getMetric(metric_name)
    local metric = metrics[metric_name]
    if metric == nil then
        print("Warning: Metric '" .. metric_name .. "' not found, using 0")
        return 0
    end
    return metric
end

-- Convenience functions for common color operations
function theme.setColor(color_name, alpha)
    local color = theme.getColor(color_name)
    if alpha then
        love.graphics.setColor(color[1], color[2], color[3], alpha)
    else
        love.graphics.setColor(color)
    end
end

-- Get color with custom alpha
function theme.getColorWithAlpha(color_name, alpha)
    local color = theme.getColor(color_name)
    return {color[1], color[2], color[3], alpha}
end

-- Background element color generators
function theme.generateBackgroundCircleColor()
    return {
        math.random(50, 100) / 100,
        math.random(60, 100) / 100,
        math.random(80, 100) / 100
    }
end

function theme.generateBackgroundRectColor()
    return {
        math.random(40, 80) / 100,
        math.random(50, 90) / 100,
        math.random(70, 100) / 100
    }
end

-- Particle system colors
function theme.getParticleColors()
    return {
        {1, 1, 1, 0}, -- Start transparent
        {0.7, 0.8, 1, 0.3}, -- Fade in
        {0.5, 0.6, 0.8, 0.1}, -- Fade out
        {1, 1, 1, 0} -- End transparent
    }
end

-- Get all available color names (for debugging)
function theme.getColorNames()
    local names = {}
    for name, _ in pairs(colors) do
        table.insert(names, name)
    end
    return names
end

-- Get all available font names (for debugging)
function theme.getFontNames()
    local names = {}
    for name, _ in pairs(fonts) do
        table.insert(names, name)
    end
    return names
end

-- Get all available metric names (for debugging)
function theme.getMetricNames()
    local names = {}
    for name, _ in pairs(metrics) do
        table.insert(names, name)
    end
    return names
end

-- Expose tables for UI module
theme.fonts = fonts
theme.colors = colors
theme.metrics = metrics

return theme
