-- Test script for weapons_core_mod
-- This verifies all weapons are properly loaded and functional

local weaponsTest = {}

function weaponsTest.runTests(api, weaponsMod)
    print("[WEAPONS_TEST] Starting weapon system tests...")
    
    local tests_passed = 0
    local tests_failed = 0
    
    -- Test 1: Check all weapons are registered
    print("[TEST] Checking weapon registration...")
    local expected_weapons = {"pistol", "smg", "shotgun", "assault_rifle", "rocket_launcher"}
    for _, weapon_id in ipairs(expected_weapons) do
        local template = weaponsMod.public.getWeaponTemplate(weapon_id)
        if template then
            print("  ✓ " .. weapon_id .. " loaded successfully")
            tests_passed = tests_passed + 1
        else
            print("  ✗ " .. weapon_id .. " failed to load")
            tests_failed = tests_failed + 1
        end
    end
    
    -- Test 2: Check current weapon
    print("\n[TEST] Checking current weapon...")
    local current = weaponsMod.public.getCurrentWeapon()
    if current then
        print("  ✓ Current weapon: " .. current.template.name)
        tests_passed = tests_passed + 1
    else
        print("  ✗ No current weapon equipped")
        tests_failed = tests_failed + 1
    end
    
    -- Test 3: Check weapon switching
    print("\n[TEST] Testing weapon switching...")
    for i, weapon_id in ipairs(expected_weapons) do
        weaponsMod.switchWeapon(weapon_id)
        local current = weaponsMod.public.getCurrentWeapon()
        if current and current.id == weapon_id then
            print("  ✓ Successfully switched to " .. weapon_id)
            tests_passed = tests_passed + 1
        else
            print("  ✗ Failed to switch to " .. weapon_id)
            tests_failed = tests_failed + 1
        end
    end
    
    -- Test 4: Check projectiles_mod integration
    print("\n[TEST] Checking projectiles_mod integration...")
    local projectiles_mod = api.mod_system.getMod("projectiles_mod")
    if projectiles_mod then
        print("  ✓ projectiles_mod is loaded")
        tests_passed = tests_passed + 1
        
        if projectiles_mod.public and projectiles_mod.public.spawnProjectile then
            print("  ✓ projectiles_mod.spawnProjectile is available")
            tests_passed = tests_passed + 1
        else
            print("  ✗ projectiles_mod.spawnProjectile not found")
            tests_failed = tests_failed + 1
        end
    else
        print("  ✗ projectiles_mod not loaded")
        tests_failed = tests_failed + 1
    end
    
    -- Test 5: Check combat_effects_mod integration
    print("\n[TEST] Checking combat_effects_mod integration...")
    local effects_mod = api.mod_system.getMod("combat_effects_mod")
    if effects_mod then
        print("  ✓ combat_effects_mod is loaded")
        tests_passed = tests_passed + 1
        
        if effects_mod.public then
            local effects_available = true
            local required_effects = {
                "createMuzzleFlash",
                "createParticleEffect",
                "createShellEjection"
            }
            
            for _, effect_name in ipairs(required_effects) do
                if effects_mod.public[effect_name] then
                    print("  ✓ " .. effect_name .. " is available")
                    tests_passed = tests_passed + 1
                else
                    print("  ✗ " .. effect_name .. " not found")
                    tests_failed = tests_failed + 1
                    effects_available = false
                end
            end
        else
            print("  ✗ combat_effects_mod.public not available")
            tests_failed = tests_failed + 1
        end
    else
        print("  ✗ combat_effects_mod not loaded")
        tests_failed = tests_failed + 1
    end
    
    -- Test 6: Verify weapon properties
    print("\n[TEST] Verifying weapon properties...")
    for _, weapon_id in ipairs(expected_weapons) do
        local template = weaponsMod.public.getWeaponTemplate(weapon_id)
        if template then
            local required_props = {
                "name", "fire_rate", "damage", "projectile_type",
                "projectile_speed", "ring_radius", "barrel_length"
            }
            
            local all_props_found = true
            for _, prop in ipairs(required_props) do
                if not template[prop] then
                    print("  ✗ " .. weapon_id .. " missing property: " .. prop)
                    tests_failed = tests_failed + 1
                    all_props_found = false
                end
            end
            
            if all_props_found then
                print("  ✓ " .. weapon_id .. " has all required properties")
                tests_passed = tests_passed + 1
            end
        end
    end
    
    -- Test results
    print("\n[WEAPONS_TEST] Test Results:")
    print("  Tests passed: " .. tests_passed)
    print("  Tests failed: " .. tests_failed)
    print("  Total tests: " .. (tests_passed + tests_failed))
    
    if tests_failed == 0 then
        print("\n✓ All weapon system tests passed!")
    else
        print("\n✗ Some tests failed. Check the output above for details.")
    end
    
    return tests_passed, tests_failed
end

-- Export test runner
weaponsTest.public = {
    runTests = weaponsTest.runTests
}

return weaponsTest