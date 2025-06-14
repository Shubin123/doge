# PvP Damage Test Results

## Setup
- Host running on localhost:6750 (instance 1)
- Client connected to 127.0.0.1:6750 (instance 2)

## Issues Found and Fixed:

1. **Projectiles Mod Issues:**
   - Was using non-existent `api.game.getPlayerHealth()` and `api.game.setPlayerHealth()`
   - Fixed to use `api.mods.player_core_mod.exports.damagePlayer()` instead
   - Added proper collision detection for player vs player damage
   - Added owner_id tracking to prevent self-damage

2. **Weapons Core Mod Issues:**
   - Was not passing owner_id when spawning projectiles
   - Fixed to include `owner_id = "player"` in projectile parameters

3. **Damage Indicators Mod Issues:**
   - Was using non-existent `api.network.onReceive()` method
   - Fixed to use `api.network.registerMessageHandler()`
   - Was using non-existent `api.utils.math.distance()` function
   - Fixed to use manual distance calculation
   - Was using `math.rad()` which doesn't exist
   - Fixed to use manual radian conversion

## Testing Instructions:
1. Start host: `./run.sh 1`
2. Start client: `./run.sh 2 127.0.0.1`
3. Use WASD keys to move players
4. Click mouse to shoot
5. Number keys 1-5 to switch weapons
6. Verify that:
   - Players can damage each other
   - Damage indicators appear
   - Health bars update
   - Knockback works

## Expected Behavior:
- When one player shoots another, damage should be applied
- Damage indicators should appear showing the damage amount
- Player health should decrease
- Knockback should push the hit player away