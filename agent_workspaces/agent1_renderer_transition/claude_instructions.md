# Claude Agent Instructions

## How to Work with Claude as Agent 1

### Starting Your Session
1. Open a new Claude chat (claude.ai or desktop app)
2. Copy and paste your task from task.md
3. Start with: "I'm Agent 1 working on the DogeGame renderer transition. My task is to complete the critical renderer migration. Here's my task: [paste task]"

### Working Effectively
1. **Use Desktop Commander**: Ask Claude to use Desktop Commander to read/write files
2. **Be Specific**: Reference exact file paths from the project
3. **Test Incrementally**: Ask Claude to make small changes and test
4. **Document Progress**: Keep notes on what's working/not working

### Example Prompts:
- "Use Desktop Commander to read src/main.lua and show me where the renderer is initialized"
- "Create a backup of main.lua as main_legacy.lua before we make changes"
- "Update the love.draw() function to use rendererPlus.render() instead of the legacy renderer"
- "Test the game to ensure it still renders correctly"

### Coordination:
- This is the CRITICAL BLOCKER - other agents depend on your completion
- Focus on getting the renderer transition working first
- Test thoroughly before declaring complete
- Update the plan.txt with your progress

### Project Context:
- Project root: /Users/amanson/Desktop/Projects_Main_Folder/CanvasTools/doge
- Key files: src/main.lua, src/lib/graphics/new_renderer.lua
- Test with: love . (in project root)
