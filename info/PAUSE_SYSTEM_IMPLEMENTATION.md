# Pause System Implementation

## Overview
A comprehensive pause system has been implemented for the Doge game engine with full multiplayer support. The system provides different pause modes for hosts, clients, and synchronization operations.

## Features Implemented

### 1. Host Pause
- Host can pause the entire game for all connected players
- Sends pause command to all clients via network
- Shows notification to all players about the pause
- Prevents all gameplay updates while paused
- Host can unpause for everyone

### 2. Client Pause
- Clients can pause their local rendering only
- Does not affect other players or the host
- Stores game state for potential resync when unpausing
- Shows local pause notification
- Only affects the client's view

### 3. Sync Pause
- System-initiated pause for synchronization operations
- Used during player join/leave events
- Cannot be manually unpaused by users
- Automatically unpauses when sync is complete
- Has timeout protection (5 seconds)

### 4. Integration Features
- **ESC Key**: Toggles pause in game, opens pause menu
- **Menu Integration**: Pause menu shows Resume instead of Start
- **Notification System**: Uses ui_notifications_mod for pause messages
- **Mod System**: Notifies all mods about pause/resume events
- **Network Protocol**: Compressed JSON messages for pause commands
- **Visual Overlay**: Semi-transparent overlay with pause information

## Implementation Details

### Files Modified

1. **`src/systems/pause.lua`** (NEW)
   - Core pause system implementation
   - Handles all pause states and transitions
   - Network message handling
   - Overlay rendering

2. **`src/main.lua`**
   - Added pause system initialization
   - Integrated pause into update loop
   - Added ESC key handling for pause
   - Skip physics/game updates when paused
   - Draw pause overlay

3. **`src/ui/menu.lua`**
   - Added pause menu mode
   - Shows Resume button instead of Start
   - Exit to Menu option when paused
   - Handles pause menu transitions

4. **`src/network/multiplayer.lua`**
   - Added pause command message handling
   - Routes pause messages to handlers

5. **`src/engine/mod_system.lua`**
   - Added `notifyPause()` function
   - Added `getGlobalAPI()` for notifications access
   - Mods can implement `onPause()` and `onResume()` handlers

6. **`src/mods/ui_notifications_mod/main.lua`**
   - Added exports for external access
   - Pause system uses these for notifications

## Usage

### For Players
- Press **ESC** during gameplay to pause
- In pause menu:
  - **Resume Game**: Continue playing
  - **Settings**: Access game settings
  - **Saves**: Save/Load game
  - **Exit to Menu**: Return to main menu

### For Developers

#### Check Pause State
```lua
if pause.isPaused() then
    -- Game is paused
end

if pause.isGameplayPaused() then
    -- Skip physics/AI updates
end
```

#### Programmatic Pause
```lua
-- Pause for synchronization
pause.syncPause("Syncing new player...")

-- Unpause after sync
pause.syncUnpause()
```

#### Mod Integration
```lua
-- In your mod's main.lua
function myMod.onPause()
    -- Handle pause (e.g., pause animations)
end

function myMod.onResume()
    -- Handle resume (e.g., resume animations)
end
```

## Network Protocol

### Pause Messages
```json
{
    "type": "pause_command",
    "command": "pause" | "unpause" | "sync_pause" | "sync_unpause",
    "reason": "Pause reason text"
}
```

Messages are compressed with zlib before transmission.

## Testing

A test script is provided at `src/test_pause.lua`:
```lua
local test = require("test_pause")
test.test() -- Run pause system tests
```

## Future Enhancements

1. **Pause Options**
   - Allow host to force unpause for stuck clients
   - Client request pause (host approval)
   - Pause timeout configuration

2. **Advanced Sync**
   - Automatic pause during heavy lag
   - Pause during mod downloads
   - State rollback on desync

3. **UI Improvements**
   - Pause menu animations
   - Player list showing pause status
   - Countdown timer for unpause

## Troubleshooting

### Pause Not Working
1. Ensure pause system is initialized in `main.lua`
2. Check if multiplayer is properly connected
3. Verify ui_notifications_mod is loaded

### Network Issues
1. Check network message compression
2. Verify message handlers are registered
3. Look for errors in console output

### Mod Conflicts
1. Ensure mods don't override ESC key
2. Check mod pause handlers for errors
3. Verify mod system initialization order