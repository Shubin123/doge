# Claude Agent Instructions

## How to Work with Claude as Agent 2

### Starting Your Session
1. Open a new Claude chat (claude.ai or desktop app)
2. Copy and paste your task from task.md
3. Start with: "I'm Agent 2 working on DogeGame combat system modularization. My task is to convert weapons, bullets, and combat effects into mods. Here's my task: [paste task]"

### Working Effectively
1. **Use Desktop Commander**: Essential for reading/writing mod files
2. **Study Examples**: Reference the glowing_tree_mod for mod structure
3. **Plan First**: Design your mod architecture before coding
4. **Test Each Component**: Verify weapons work before moving to projectiles

### Example Prompts:
- "Use Desktop Commander to analyze src/entities/gun.lua and understand the weapon system"
- "Create the weapons_core_mod directory structure in mods/"
- "Convert the pistol weapon from gun.lua into a modular weapon template"
- "Implement the projectile system using the mod_system physics API"
- "Add muzzle flash effects that work with the new renderer"

### Coordination:
- You can work in parallel with Agent 3
- Coordinate on projectile systems (enemies use them too)
- Wait for Agent 1's renderer transition for final testing
- Share your entity ID scheme with Agent 3

### Project Context:
- Project root: /Users/amanson/Desktop/Projects_Main_Folder/CanvasTools/doge
- Study files: src/entities/gun.lua, bullet.lua, rocket.lua
- Mod location: mods/weapons_core_mod/, mods/projectiles_mod/
- Test with: love . (after enabling your mods)

### Mod Development Tips:
- Start with mod_info.json configuration
- Use the mod_system API for all game interactions
- Ensure network compatibility for multiplayer
- Keep original behavior intact
