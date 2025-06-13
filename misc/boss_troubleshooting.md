# Boss System Troubleshooting Guide

## Issue: Boss not spawning with crash

The crash you encountered was due to several issues that have now been fixed:

1. **Missing comment markers**: A comment in the boss.populate function was missing the `--` prefix, causing a syntax error
2. **Incorrect source_object_type**: The boss health bars were using custom types not handled by the renderer
3. **Line rendering not supported**: The laser visual effect used a line drawing method not implemented in the renderer

## Fixes Applied:

1. Fixed the comment syntax in boss.populate()
2. Changed health bar source_object_types to use the existing handlers:
   - `boss_health_bg` → `health_bar_bg`
   - `boss_health_fill` → `health_bar_fill`
3. Temporarily disabled laser beam visuals (the damage still works)
4. Fixed boss name text to use the damage_indicator handler

## Testing Steps:

1. Restart the game for the changes to take effect
2. Open console with `` ` ``
3. Run: `boss spawn 400 400`
4. Check the console output for debug messages:
   - "boss.load() called"
   - "Boss sprites loaded successfully"
   - "Attempting to spawn boss at 400 400 with ID 1"
   - "Boss spawned at 400 400 with ID 1"

## If Still Not Working:

1. Check if boss module is loaded:
   ```lua
   boss
   ```
   Should return a table, not nil

2. Check boss count:
   ```lua
   boss.bosses
   ```
   Should show the boss instances

3. Try spawning at player position:
   ```lua
   boss spawn
   ```

4. Check for any error messages in the console output

## Next Steps:

Once the boss is spawning correctly, you can:
- Test the hopping movement (boss should hop toward you)
- Test the ground pound damage (stand close when it lands)
- Shoot the boss to see damage numbers and health bar
- Wait for the laser charge animation (threatening sprite)

The laser beam visual can be added later by implementing line drawing support in the renderer or using a different visual approach (like a stretched sprite).
