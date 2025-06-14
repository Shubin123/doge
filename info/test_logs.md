# Testing the Log Viewing System

## How to Test

1. Start the game with `./run.sh 1`
2. Press the comma `,` key to open the console
3. Type `help` to see the new log commands
4. Try the following commands:

### Basic Log Commands
- `logs` - Shows the last 50 logs 
- `logs 20` - Shows the last 20 logs
- `logs count` - Shows total logs in buffer

### Filtered Log Commands
- `logs 30 MOD_SYSTEM` - Shows logs containing "MOD_SYSTEM"
- `logs 20 rendererPlus` - Shows renderer logs
- `logs 50 Error` - Shows error logs
- `logs 25 PLAYER_CORE_MOD` - Shows player mod logs

### Log Management
- `logs filter MOD_SYSTEM` - Sets persistent filter
- `logs filter` - Clears filter
- `logs clear` - Clears log buffer

## Expected Output

The logs should be color-coded:
- **Blue**: MOD_SYSTEM logs
- **Green**: MOD: specific mod logs  
- **Cyan**: rendererPlus logs
- **Red**: Error/Warning/Failed messages
- **Yellow**: GC collected messages
- **White**: Default logs

## Features Implemented

✅ **Log Capture**: All print() statements are intercepted and stored
✅ **Time Stamps**: Each log entry includes a timestamp
✅ **Filtering**: Search logs by keyword/pattern
✅ **Color Coding**: Different log types have different colors
✅ **Command Integration**: Works with existing console system
✅ **Buffer Management**: Automatically limits buffer size (1000 entries)
✅ **Real-time**: Captures logs as they happen during gameplay

## Usage Examples

```
> logs 20
=== GAME LOGS ===
[12:04:23] [MOD_SYSTEM] Initializing mod system...
[12:04:23] [MOD_SYSTEM] Discovered mod: player_core_mod v1.0.0
[12:04:23] [rendererPlus] GC collected: 484.84 KB
...

> logs 10 rendererPlus
=== GAME LOGS (filtered: 'rendererPlus') ===
[12:04:23] [rendererPlus] Loaded texture: player_idle from gfx/testCharacter/idle.png
[12:04:23] [rendererPlus] Asset preloading complete!
...

> logs filter Error
Log filter set to: 'Error' (3 matches)

> logs 50
=== GAME LOGS (filtered: 'Error') ===
[12:04:23] [rendererPlus] Failed to load font: game_font
[12:04:23] [MOD_SYSTEM] Failed to initialize mod: [string "map_system"]:901
...
```

This system allows real-time monitoring of all game systems during development and debugging!
