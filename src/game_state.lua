local game_state = {}

-- Game states
local states = {
    SPLASH = "splash",           -- Initial splash screen
    MAIN_MENU = "main_menu",     -- Main title screen
    CHARACTER_SELECT = "character_select", -- Character selection
    MAP_SELECT = "map_select",   -- Map/level selection  
    LOADING = "loading",         -- Loading screen
    PLAYING = "playing",         -- In-game
    PAUSED = "paused",           -- Game paused
    GAME_OVER = "game_over",     -- Death/game over
    SETTINGS = "settings",       -- Settings menu
    CREDITS = "credits"          -- Credits screen
}

-- Current state tracking
local current_state = states.SPLASH
local previous_state = nil
local state_data = {}
local transition_data = {}

-- State change callbacks
local state_callbacks = {}

-- Initialize state manager
function game_state.initialize()
    current_state = states.SPLASH
    state_data = {}
    transition_data = {
        active = false,
        type = "fade",
        progress = 0,
        duration = 0.5,
        callback = nil
    }
    
    print("Game State Manager initialized")
end

-- Get all available states
function game_state.getStates()
    return states
end

-- Get current state
function game_state.getCurrentState()
    return current_state
end

-- Get previous state
function game_state.getPreviousState()
    return previous_state
end

-- Check if in specific state
function game_state.isState(state)
    return current_state == state
end

-- Set state data
function game_state.setStateData(key, value)
    state_data[key] = value
end

-- Get state data
function game_state.getStateData(key)
    return state_data[key]
end

-- Register state change callback
function game_state.onStateChange(callback)
    table.insert(state_callbacks, callback)
end

-- Change state with optional transition
function game_state.changeState(new_state, transition_type, duration, callback)
    if new_state == current_state then return end
    
    transition_type = transition_type or "instant"
    duration = duration or 0.5
    
    print("State change: " .. current_state .. " -> " .. new_state)
    
    if transition_type == "instant" then
        game_state.immediateStateChange(new_state)
        if callback then callback() end
    else
        game_state.startTransition(new_state, transition_type, duration, callback)
    end
end

-- Immediate state change without transition
function game_state.immediateStateChange(new_state)
    previous_state = current_state
    current_state = new_state
    
    -- Notify callbacks
    for _, callback in ipairs(state_callbacks) do
        callback(current_state, previous_state)
    end
    
    -- Clean up state-specific data
    game_state.cleanupStateData()
end

-- Start transition between states
function game_state.startTransition(new_state, transition_type, duration, callback)
    transition_data.active = true
    transition_data.type = transition_type
    transition_data.progress = 0
    transition_data.duration = duration
    transition_data.target_state = new_state
    transition_data.callback = callback
end

-- Update transitions
function game_state.update(dt)
    if not transition_data.active then return end
    
    transition_data.progress = transition_data.progress + dt / transition_data.duration
    
    if transition_data.progress >= 1.0 then
        -- Complete transition
        transition_data.progress = 1.0
        transition_data.active = false
        
        -- Change to target state
        game_state.immediateStateChange(transition_data.target_state)
        
        -- Call completion callback
        if transition_data.callback then
            transition_data.callback()
        end
    end
end

-- Get transition data for rendering
function game_state.getTransitionData()
    return transition_data
end

-- Check if transition is active
function game_state.isTransitioning()
    return transition_data.active
end

-- Clean up state-specific data when leaving state
function game_state.cleanupStateData()
    -- Clean up based on previous state
    if previous_state == states.LOADING then
        state_data.loading_progress = nil
        state_data.loading_text = nil
    elseif previous_state == states.CHARACTER_SELECT then
        -- Keep selected character data
    elseif previous_state == states.MAP_SELECT then
        -- Keep selected map data
    end
end

-- Specific state management functions

-- Splash screen
function game_state.showSplash(duration)
    duration = duration or 3.0
    game_state.changeState(states.SPLASH)
    state_data.splash_timer = duration
end

-- Main menu
function game_state.showMainMenu()
    game_state.changeState(states.MAIN_MENU, "fade", 0.5)
end

-- Character selection
function game_state.showCharacterSelect()
    game_state.changeState(states.CHARACTER_SELECT, "slide", 0.3)
    state_data.selected_character = state_data.selected_character or "default"
end

-- Map selection
function game_state.showMapSelect()
    game_state.changeState(states.MAP_SELECT, "slide", 0.3)
    state_data.selected_map = state_data.selected_map or "level1"
end

-- Loading screen
function game_state.showLoading(loading_text)
    game_state.changeState(states.LOADING, "fade", 0.2)
    state_data.loading_progress = 0
    state_data.loading_text = loading_text or "Loading..."
end

-- Update loading progress
function game_state.setLoadingProgress(progress, text)
    state_data.loading_progress = math.max(0, math.min(1, progress))
    if text then
        state_data.loading_text = text
    end
end

-- Start game
function game_state.startGame()
    game_state.changeState(states.PLAYING, "fade", 0.5)
end

-- Pause game
function game_state.pauseGame()
    if current_state == states.PLAYING then
        game_state.changeState(states.PAUSED, "instant")
    end
end

-- Resume game
function game_state.resumeGame()
    if current_state == states.PAUSED then
        game_state.changeState(states.PLAYING, "instant")
    end
end

-- Game over
function game_state.gameOver(reason)
    game_state.changeState(states.GAME_OVER, "fade", 0.8)
    state_data.game_over_reason = reason or "Game Over"
    state_data.game_over_timer = 3.0
end

-- Settings menu
function game_state.showSettings()
    game_state.changeState(states.SETTINGS, "slide", 0.3)
end

-- Credits
function game_state.showCredits()
    game_state.changeState(states.CREDITS, "slide", 0.5)
end

-- Return to main menu
function game_state.returnToMainMenu()
    game_state.changeState(states.MAIN_MENU, "fade", 0.5)
    -- Clear game-specific data
    state_data.selected_character = nil
    state_data.selected_map = nil
    state_data.game_over_reason = nil
end

-- Quit game
function game_state.quitGame()
    love.event.quit()
end

-- Debug information
function game_state.getDebugInfo()
    return {
        current_state = current_state,
        previous_state = previous_state,
        transitioning = transition_data.active,
        transition_progress = transition_data.progress,
        state_data_keys = {},
        memory_usage = collectgarbage("count")
    }
end

-- Get state display name
function game_state.getStateDisplayName(state)
    local display_names = {
        [states.SPLASH] = "Splash Screen",
        [states.MAIN_MENU] = "Main Menu",
        [states.CHARACTER_SELECT] = "Character Selection",
        [states.MAP_SELECT] = "Map Selection",
        [states.LOADING] = "Loading",
        [states.PLAYING] = "Playing",
        [states.PAUSED] = "Paused",
        [states.GAME_OVER] = "Game Over",
        [states.SETTINGS] = "Settings",
        [states.CREDITS] = "Credits"
    }
    return display_names[state] or state
end

return game_state