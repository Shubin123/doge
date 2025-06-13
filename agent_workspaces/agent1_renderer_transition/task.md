# Agent 1 Task: Complete Renderer Transition

## CRITICAL BLOCKER TO RESOLVE
The new renderer (new_renderer.lua) is fully implemented but not active in the main draw loop. The game still uses legacy renderer.lua.

## Your Primary Task
Update src/main.lua to use the new renderer system (rendererPlus) instead of the legacy renderer.

## Step-by-Step Plan:

1. **Analyze Current State**
   - Review src/main.lua and identify where renderer.renderSortedDrawList() is called
   - Check how the legacy renderer integrates with the game loop
   - Understand the new_renderer.lua API (rendererPlus.render())

2. **Create Transition Strategy**
   - Back up current main.lua as main_legacy.lua
   - Identify all places where legacy renderer is used
   - Map legacy renderer calls to new renderer equivalents

3. **Implement Renderer Switch**
   - Update love.draw() to use rendererPlus.render()
   - Ensure all game systems queue their draw calls properly
   - Test that the game looks identical after transition

4. **Verify Integration Points**
   - Check that all entities use the new rendering queue
   - Ensure UI elements render properly
   - Validate that effects and particles work

5. **Test Multiplayer Compatibility**
   - Ensure renderer changes don't break network sync
   - Test with multiple clients

## Key Files to Work With:
- src/main.lua (primary target)
- src/lib/graphics/new_renderer.lua (new system)
- src/lib/graphics/renderer.lua (legacy to replace)
- src/engine/mod_system.lua (ensure mod compatibility)

## Success Criteria:
- Game looks EXACTLY the same as before
- Performance is maintained or improved
- All visual features work (particles, effects, UI)
- Multiplayer still functions correctly
- Mods can use the new renderer API

## Testing Checklist:
- [ ] Single player loads and renders correctly
- [ ] All entities appear as expected
- [ ] UI elements render properly
- [ ] Effects and particles work
- [ ] Multiplayer clients see the same visuals
- [ ] Example mod (glowing_tree_mod) still works

Remember: This is the CRITICAL BLOCKER preventing other agents from proceeding with modularization!
