  1. Added modSystem.update(dt) to the game update loop - This was the critical
  missing piece that prevented all mods from updating their state.
  2. Fixed the rendering pipeline - Reordered the draw sequence so mods populate the
  render queue before it's processed.
  3. Added isKeyDown to the mod API - This allows mods to check if keys are currently
   held down.
  4. Added modSystem.keyreleased function - This prevents the crash when keys are
  released.
  5. Updated player movement to use continuous input - The player mod now checks for
  held keys every frame and applies forces accordingly.