-- Test script for pause system
-- Run this after the game loads to test pause functionality

local function testPauseSystem()
    print("\n=== PAUSE SYSTEM TEST ===")
    
    -- Test 1: Check if pause system is initialized
    if pause then
        print("✓ Pause system loaded")
    else
        print("✗ Pause system not found!")
        return
    end
    
    -- Test 2: Check pause state
    print("Current pause state:", pause.getState())
    print("Is paused:", pause.isPaused())
    print("Is gameplay paused:", pause.isGameplayPaused())
    
    -- Test 3: Test pause toggle
    print("\nTesting pause toggle...")
    local originalState = pause.getState()
    pause.toggle()
    print("After toggle - State:", pause.getState())
    print("Pause reason:", pause.getReason())
    
    -- Test 4: Test unpause
    print("\nTesting unpause...")
    pause.toggle()
    print("After second toggle - State:", pause.getState())
    
    -- Test 5: Test sync pause
    print("\nTesting sync pause...")
    pause.syncPause("Testing synchronization")
    print("Sync pause state:", pause.getState())
    print("Can unpause:", not pause.isPaused() or pause.getState() ~= "sync_pause")
    
    -- Unpause after sync test
    pause.syncUnpause()
    print("After sync unpause - State:", pause.getState())
    
    print("\n=== PAUSE SYSTEM TEST COMPLETE ===\n")
end

-- Export test function
return {
    test = testPauseSystem
}