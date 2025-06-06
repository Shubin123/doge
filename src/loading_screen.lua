local loading_screen = {}
local game_state = require("game_state")
local map_manager = require("map_manager")
local character_manager = require("character_manager")

-- Loading configuration
local loading_config = {
    background_color = {0.1, 0.1, 0.2, 1},
    progress_bar_color = {0.3, 0.7, 1.0, 1},
    progress_bg_color = {0.2, 0.2, 0.4, 0.8},
    text_color = {1, 1, 1, 1},
    
    -- Animation settings
    spinner_speed = 3.0,
    progress_smooth_speed = 5.0,
    tip_change_interval = 3.0
}

-- Loading state
local loading_state = {
    progress = 0,
    smooth_progress = 0,
    current_task = "Initializing...",
    animation_time = 0,
    tip_timer = 0,
    current_tip_index = 1,
    
    -- Loading tasks
    tasks = {},
    current_task_index = 1,
    completed_tasks = 0,
    total_tasks = 0,
    
    -- Selected character and map
    selected_character = nil,
    selected_map = nil,
    
    -- Callbacks
    completion_callback = nil
}

-- Loading tips
local loading_tips = {
    "Use WASD to move your character around the world",
    "Press Space to dodge enemy attacks",
    "Click to shoot fireballs at enemies",
    "Collect coins to increase your score", 
    "Each character has unique abilities and stats",
    "Press 'E' to toggle the map editor",
    "Press 'M' to view debug information",
    "Use 1-3 keys to switch between maps",
    "Different maps have different challenges",
    "Experiment with different characters to find your favorite",
    "The game world uses physics-based movement",
    "Watch out for enemy patterns and behaviors"
}

-- Fonts
local fonts = {}

-- Initialize loading screen
function loading_screen.initialize()
    -- Load fonts
    fonts.title = love.graphics.newFont("gfx/menu/PixelGameFont.ttf", 32)
    fonts.text = love.graphics.newFont("gfx/menu/PixelGameFont.ttf", 18)
    fonts.small = love.graphics.newFont("gfx/menu/PixelGameFont.ttf", 14)
    
    print("Loading screen initialized")
end

-- Start loading with specific character and map
function loading_screen.start_loading(character_id, map_id, completion_callback)
    loading_state.selected_character = character_id
    loading_state.selected_map = map_id
    loading_state.completion_callback = completion_callback
    
    -- Reset loading state
    loading_state.progress = 0
    loading_state.smooth_progress = 0
    loading_state.animation_time = 0
    loading_state.tip_timer = 0
    loading_state.current_tip_index = math.random(1, #loading_tips)
    loading_state.current_task_index = 1
    loading_state.completed_tasks = 0
    loading_state.completed = false
    
    -- Define loading tasks
    loading_state.tasks = {
        {
            name = "Loading character data...",
            duration = 0.5,
            action = function()
                local character = character_manager.load_character(character_id)
                if not character then
                    print("Failed to load character: " .. (character_id or "unknown"))
                    return false
                end
                return true
            end
        },
        {
            name = "Preparing game world...",
            duration = 0.8,
            action = function()
                -- Initialize physics world if needed
                return true
            end
        },
        {
            name = "Loading map: " .. (map_id or "default"),
            duration = 1.2,
            action = function()
                local map_to_load = map_id or "level1"
                print("Attempting to load map: " .. map_to_load)
                
                -- Try to load the map synchronously using map loader
                local map_loader = require("map_loader")
                local loaded_map = map_loader.load_map_sync(map_to_load)
                
                if loaded_map then
                    print("Map loaded successfully: " .. map_to_load)
                    return true
                else
                    print("Failed to load map: " .. map_to_load)
                    return false
                end
            end
        },
        {
            name = "Spawning entities...",
            duration = 0.6,
            action = function()
                -- Entities are spawned automatically by map_manager
                return true
            end
        },
        {
            name = "Initializing systems...",
            duration = 0.4,
            action = function()
                -- Initialize any additional game systems
                return true
            end
        },
        {
            name = "Finalizing...",
            duration = 0.3,
            action = function()
                -- Final setup
                return true
            end
        }
    }
    
    loading_state.total_tasks = #loading_state.tasks
    loading_state.current_task = loading_state.tasks[1].name
    
    print("Started loading - Character: " .. character_id .. ", Map: " .. (map_id or "default"))
end

-- Update loading screen
function loading_screen.update(dt)
    loading_state.animation_time = loading_state.animation_time + dt
    loading_state.tip_timer = loading_state.tip_timer + dt
    
    -- Change tip periodically
    if loading_state.tip_timer >= loading_config.tip_change_interval then
        loading_state.tip_timer = 0
        loading_state.current_tip_index = (loading_state.current_tip_index % #loading_tips) + 1
    end
    
    -- Update smooth progress
    local target_progress = loading_state.progress
    loading_state.smooth_progress = loading_state.smooth_progress + 
        (target_progress - loading_state.smooth_progress) * loading_config.progress_smooth_speed * dt
    
    -- Process loading tasks
    if loading_state.current_task_index <= loading_state.total_tasks then
        local current_task = loading_state.tasks[loading_state.current_task_index]
        
        -- Simulate task duration or execute actual task
        if current_task.timer == nil then
            current_task.timer = 0
            loading_state.current_task = current_task.name
        end
        
        current_task.timer = current_task.timer + dt
        
        -- Update progress within current task
        local task_progress = math.min(1, current_task.timer / current_task.duration)
        local base_progress = (loading_state.current_task_index - 1) / loading_state.total_tasks
        local task_contribution = task_progress / loading_state.total_tasks
        loading_state.progress = base_progress + task_contribution
        
        -- Complete task when timer expires
        if current_task.timer >= current_task.duration then
            -- Execute task action
            local success = true
            if current_task.action then
                success = current_task.action()
            end
            
            if success then
                loading_state.completed_tasks = loading_state.completed_tasks + 1
                loading_state.current_task_index = loading_state.current_task_index + 1
                
                if loading_state.current_task_index <= loading_state.total_tasks then
                    loading_state.current_task = loading_state.tasks[loading_state.current_task_index].name
                end
            else
                -- Handle task failure
                print("Loading task failed: " .. current_task.name)
                loading_state.current_task = "Error loading map - Check console"
                loading_state.progress = 0.5 -- Stop at ~50% to show the error
                return -- Stop processing tasks
            end
        end
    else
        -- All tasks completed
        loading_state.progress = 1
        
        -- Complete immediately when all tasks are done, don't wait for smooth progress
        loading_screen.complete_loading()
    end
end

-- Complete loading and transition to game
function loading_screen.complete_loading()
    -- Prevent multiple calls
    if loading_state.completed then return end
    loading_state.completed = true
    
    print("Loading completed successfully")
    
    -- Create player instance
    if player and player.body then
        -- Clean up existing player
        if not player.body:isDestroyed() then
            player.body:destroy()
        end
    end
    
    -- Get spawn position from selected map
    local current_map = map_manager.get_current_map()
    local spawn_x = 400
    local spawn_y = 300
    
    if current_map and current_map.definition.player_spawn then
        spawn_x = current_map.definition.player_spawn.x
        spawn_y = current_map.definition.player_spawn.y
    end
    
    -- Create new player instance with selected character
    if world then
        local player_instance = character_manager.create_player_instance(
            world, 
            loading_state.selected_character, 
            spawn_x, 
            spawn_y
        )
        
        if player_instance then
            -- Update global player object
            player.body = player_instance.body
            player.shape = player_instance.shape
            player.fixture = player_instance.fixture
            player.scale = player_instance.scale
            player.health = player_instance.health
            
            -- Use the new character system
            player.set_character_data(player_instance.character)
            
            -- Properly set up animation with new system
            local idle_animation = player_instance.character.animations.idle_down or 
                                 player_instance.character.animations.idle
            if idle_animation then
                player.animation = idle_animation
                if idle_animation.currentTime ~= nil then
                    idle_animation.currentTime = 0
                end
                if idle_animation.current_time ~= nil then
                    idle_animation.current_time = 0
                end
            else
                print("Warning: No idle animation found for character")
            end
            
            print("Player spawned as: " .. player_instance.character.definition.name)
        end
    end
    
    -- Update camera bounds for new map
    if camera and current_map then
        local map_def = current_map.definition
        local map_width = map_def.map_width * map_def.tile_width
        local map_height = map_def.map_height * map_def.tile_height
        camera.setMapBounds(map_def.world_x, map_def.world_y, map_width, map_height)
        camera.map_bounds.enabled = true
        
        -- Center camera on player
        if player and player.body then
            camera.x, camera.y = player.body:getPosition()
        end
    end
    
    -- Call completion callback
    if loading_state.completion_callback then
        loading_state.completion_callback()
    end
    
    -- Transition to game state
    game_state.startGame()
end

-- Draw loading screen
function loading_screen.draw()
    local screen_width = love.graphics.getWidth()
    local screen_height = love.graphics.getHeight()
    
    -- Clear background
    love.graphics.clear(loading_config.background_color)
    
    -- Draw animated background
    loading_screen.draw_background()
    
    -- Draw title
    love.graphics.setFont(fonts.title)
    love.graphics.setColor(loading_config.text_color)
    local title = "Loading Adventure"
    local title_width = fonts.title:getWidth(title)
    love.graphics.print(title, screen_width/2 - title_width/2, 100)
    
    -- Draw character and map info
    love.graphics.setFont(fonts.text)
    if loading_state.selected_character then
        local char_def = character_manager.get_character_definition(loading_state.selected_character)
        if char_def then
            local char_text = "Character: " .. char_def.name
            local char_width = fonts.text:getWidth(char_text)
            love.graphics.print(char_text, screen_width/2 - char_width/2, 150)
        end
    end
    
    if loading_state.selected_map then
        local map_text = "Map: " .. loading_state.selected_map
        local map_width = fonts.text:getWidth(map_text)
        love.graphics.print(map_text, screen_width/2 - map_width/2, 180)
    end
    
    -- Draw progress bar
    loading_screen.draw_progress_bar()
    
    -- Draw current task
    love.graphics.setFont(fonts.text)
    love.graphics.setColor(loading_config.text_color[1], loading_config.text_color[2], loading_config.text_color[3], 0.8)
    local task_width = fonts.text:getWidth(loading_state.current_task)
    love.graphics.print(loading_state.current_task, screen_width/2 - task_width/2, screen_height/2 + 80)
    
    -- Draw loading tip
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(loading_config.text_color[1], loading_config.text_color[2], loading_config.text_color[3], 0.6)
    local tip = "Tip: " .. loading_tips[loading_state.current_tip_index]
    local tip_width = fonts.small:getWidth(tip)
    love.graphics.printf(tip, screen_width/2 - 200, screen_height - 100, 400, "center")
    
    -- Draw spinner
    loading_screen.draw_spinner()
    
    -- Reset color
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw animated background
function loading_screen.draw_background()
    local screen_width = love.graphics.getWidth()
    local screen_height = love.graphics.getHeight()
    
    -- Draw moving particles
    for i = 1, 20 do
        local x = (i * 50 + loading_state.animation_time * 30) % (screen_width + 100) - 50
        local y = 50 + math.sin(loading_state.animation_time + i) * 20
        local alpha = 0.1 + math.sin(loading_state.animation_time * 2 + i) * 0.05
        
        love.graphics.setColor(0.3, 0.5, 0.8, alpha)
        love.graphics.circle("fill", x, y, 3)
    end
    
    -- Draw floating geometric shapes
    for i = 1, 8 do
        local x = 100 + (i * 80) + math.sin(loading_state.animation_time * 0.5 + i) * 50
        local y = screen_height - 100 + math.cos(loading_state.animation_time * 0.3 + i) * 30
        local rotation = loading_state.animation_time * 0.5 + i
        local alpha = 0.05 + math.sin(loading_state.animation_time + i) * 0.03
        
        love.graphics.setColor(0.4, 0.6, 1.0, alpha)
        love.graphics.push()
        love.graphics.translate(x, y)
        love.graphics.rotate(rotation)
        love.graphics.rectangle("fill", -10, -10, 20, 20)
        love.graphics.pop()
    end
end

-- Draw progress bar
function loading_screen.draw_progress_bar()
    local screen_width = love.graphics.getWidth()
    local screen_height = love.graphics.getHeight()
    
    local bar_width = 400
    local bar_height = 20
    local bar_x = screen_width/2 - bar_width/2
    local bar_y = screen_height/2 + 20
    
    -- Progress bar background
    love.graphics.setColor(loading_config.progress_bg_color)
    love.graphics.rectangle("fill", bar_x, bar_y, bar_width, bar_height, 5)
    
    -- Progress bar fill
    love.graphics.setColor(loading_config.progress_bar_color)
    local fill_width = bar_width * loading_state.smooth_progress
    love.graphics.rectangle("fill", bar_x, bar_y, fill_width, bar_height, 5)
    
    -- Progress bar border
    love.graphics.setColor(loading_config.text_color[1], loading_config.text_color[2], loading_config.text_color[3], 0.5)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", bar_x, bar_y, bar_width, bar_height, 5)
    
    -- Progress percentage
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(loading_config.text_color)
    local percent = math.floor(loading_state.smooth_progress * 100)
    local percent_text = percent .. "%"
    local percent_width = fonts.small:getWidth(percent_text)
    love.graphics.print(percent_text, screen_width/2 - percent_width/2, bar_y + bar_height + 10)
end

-- Draw loading spinner
function loading_screen.draw_spinner()
    local screen_width = love.graphics.getWidth()
    local screen_height = love.graphics.getHeight()
    
    local spinner_x = screen_width - 80
    local spinner_y = screen_height - 80
    local spinner_radius = 15
    
    love.graphics.setColor(loading_config.progress_bar_color)
    love.graphics.setLineWidth(3)
    
    -- Draw spinning circle
    local rotation = loading_state.animation_time * loading_config.spinner_speed
    love.graphics.push()
    love.graphics.translate(spinner_x, spinner_y)
    love.graphics.rotate(rotation)
    
    -- Draw arc
    love.graphics.arc("line", "open", 0, 0, spinner_radius, 0, math.pi * 1.5)
    
    love.graphics.pop()
end

-- Set loading progress manually (for external control)
function loading_screen.set_progress(progress, task_text)
    loading_state.progress = math.max(0, math.min(1, progress))
    if task_text then
        loading_state.current_task = task_text
    end
end

-- Add custom loading task
function loading_screen.add_task(name, duration, action)
    table.insert(loading_state.tasks, {
        name = name,
        duration = duration,
        action = action
    })
    loading_state.total_tasks = #loading_state.tasks
end

-- Check if loading is complete
function loading_screen.is_complete()
    return loading_state.progress >= 1 and loading_state.smooth_progress >= 0.98
end

-- Get loading progress
function loading_screen.get_progress()
    return {
        progress = loading_state.progress,
        smooth_progress = loading_state.smooth_progress,
        current_task = loading_state.current_task,
        completed_tasks = loading_state.completed_tasks,
        total_tasks = loading_state.total_tasks
    }
end

return loading_screen