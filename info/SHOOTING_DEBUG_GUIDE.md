# Shooting Debug Guide

## Issue Summary
The weapons system shows visual elements (weapon barrel, aiming ring) and allows weapon switching, but shooting doesn't work - no projectiles spawn, no shell ejections appear, and enemies can't be damaged.

## Debug Features Added

### 1. Comprehensive Logging
Added detailed debug logging throughout the shooting flow:
- Mouse click detection
- Weapon cooldown checks
- Projectile spawn attempts
- Inter-mod communication
- Effect creation (muzzle flash, shells, particles)

### 2. Debug Key Bindings
- **F key**: Force a shooting test (bypasses mouse input to test shooting logic)
- **G key**: Test direct projectile spawning (tests mod communication)
- **1-5 keys**: Switch between weapons (existing functionality)

### 3. How to Test

1. **Run the game with debug output**:
   ```bash
   ./test_shooting.sh
   ```
   Or manually:
   ```bash
   '/Applications/love.app/Contents/MacOS/love' ./src
   ```

2. **In-game testing sequence**:
   - Press any number key (1-5) to equip a weapon
   - Click the left mouse button and watch console for "[DEBUG] Mouse press handler triggered"
   - Press F key and watch for "[DEBUG] F key pressed - forcing shoot test"
   - Press G key and watch for projectile spawn test results

3. **Expected debug output flow**:
   ```
   [DEBUG] Mouse press handler triggered - button: 1
   [DEBUG] handleShoot called - button: 1, x: [pos], y: [pos]
   [DEBUG] Weapon: [weapon_name], cooldown: 0
   [DEBUG] Attempting to spawn projectile - type: bullet, pos: [x],[y]
   [DEBUG] spawnProjectile called
   [DEBUG] Found projectiles_mod via api.mods
   [DEBUG] Using public.spawnProjectile
   [DEBUG] Projectile spawned successfully
   [DEBUG] createShellEjection called - type: [shell_type]
   ```

## Potential Issues to Check

1. **Mod Loading Order**: Check if projectiles_mod is loaded before weapons_core_mod
2. **API Access**: The mod system's inter-mod communication might not be working
3. **Physics Bodies**: Projectiles might be spawning but not visible/collidable
4. **Renderer Queue**: Effects might be created but not rendered

## Debug Output Analysis

When you run the game with debugging enabled, look for:

1. **Missing handlers**: If mouse clicks don't trigger debug logs
2. **API failures**: "projectiles_mod not found" or "spawnProjectile function not found"
3. **Silent failures**: Functions called but no result/error
4. **Mod loading issues**: Check the mod list during initialization

## Next Steps

Based on the debug output, we can:
1. Fix inter-mod communication if that's the issue
2. Ensure proper mod loading order
3. Check if projectiles are being created but not rendered
4. Verify collision detection is working

Run the tests and share the console output to diagnose the exact failure point!