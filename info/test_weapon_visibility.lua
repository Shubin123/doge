-- Test script to check weapon visibility
print("\n=== Testing Weapon Visibility ===")

-- Check if modSystem exists
if modSystem then
    print("ModSystem exists")
    
    -- Create API
    local api = modSystem.createModAPI("test_script")
    if api then
        print("API created")
        
        -- Check if weapons mod is loaded
        if api.mods and api.mods.weapons_core_mod then
            print("Weapons mod found in API")
            
            -- Check exports
            if api.mods.weapons_core_mod.exports then
                print("Weapons mod has exports:")
                for k, v in pairs(api.mods.weapons_core_mod.exports) do
                    print("  - " .. k)
                end
                
                -- Try to get current weapon
                if api.mods.weapons_core_mod.exports.getCurrentWeapon then
                    local weapon = api.mods.weapons_core_mod.exports.getCurrentWeapon()
                    if weapon then
                        print("Current weapon: " .. tostring(weapon.id or "unknown"))
                    else
                        print("No current weapon equipped")
                    end
                end
            else
                print("Weapons mod has no exports")
            end
        else
            print("Weapons mod not found in API")
        end
        
        -- Check if player mod is loaded
        if api.mods and api.mods.player_core_mod then
            print("\nPlayer mod found")
            if api.mods.player_core_mod.exports and api.mods.player_core_mod.exports.getPosition then
                local x, y = api.mods.player_core_mod.exports.getPosition()
                print("Player position: " .. x .. ", " .. y)
            end
        end
    else
        print("Failed to create API")
    end
else
    print("ModSystem not found")
end

print("=== End Test ===\n")