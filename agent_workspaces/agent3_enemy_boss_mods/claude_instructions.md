# Claude Agent Instructions

## How to Work with Claude as Agent 3

### Starting Your Session
1. Open a new Claude chat (claude.ai or desktop app)
2. Copy and paste your task from task.md
3. Start with: "I'm Agent 3 working on DogeGame enemy and boss AI modularization. My task is to convert enemies and the bear boss into mods. Here's my task: [paste task]"

### Working Effectively
1. **Use Desktop Commander**: Critical for file manipulation
2. **Understand AI Systems**: Study state machines in enemy.lua
3. **Complex Boss Logic**: The bear boss has multiple attack phases
4. **Network Sync**: Ensure enemy positions sync in multiplayer

### Example Prompts:
- "Use Desktop Commander to read src/entities/enemy.lua and analyze the AI patterns"
- "Create the basic_enemies_mod structure with enemy templates"
- "Implement the patrol AI behavior using the mod_system state machine API"
- "Convert the bear boss laser attack into a modular attack pattern"
- "Set up enemy spawning system that works with the mod loader"

### Coordination:
- Work in parallel with Agent 2
- Enemies use projectiles - coordinate with Agent 2's projectile system  
- Share entity ID conventions for network sync
- Wait for Agent 1's renderer completion for visual testing

### Project Context:
- Project root: /Users/amanson/Desktop/Projects_Main_Folder/CanvasTools/doge
- Study files: src/entities/enemy.lua, boss.lua
- Mod locations: mods/basic_enemies_mod/, mods/bear_boss_mod/
- Test with: love . (spawn enemies/boss to test)

### AI Development Tips:
- Use mod_system's state machine API
- Create reusable AI behaviors
- Test each enemy type individually
- Ensure boss phases transition correctly
- Maintain original difficulty/behavior

### Bear Boss Special Notes:
- Complex multi-phase fight
- Laser attacks with warning indicators
- Ground pound with shockwaves
- Health-based phase transitions
