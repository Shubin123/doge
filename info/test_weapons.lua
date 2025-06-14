-- Test script to debug weapon visibility
print("\n=== Testing Weapon System ===")

-- Check mod system
if modSystem and modSystem.getLoadedMod then
    print("ModSystem available")
    
    -- Check weapons mod
    local weaponsMod = modSystem.getLoadedMod("weapons_core_mod")
    if weaponsMod then
        print("Weapons mod loaded!")
        print("  - Enabled:", weaponsMod.enabled)
        print("  - Has instance:", weaponsMod.instance ~= nil)
        
        if weaponsMod.instance then
            print("  - Has update:", type(weaponsMod.instance.update))
            print("  - Has draw:", type(weaponsMod.instance.draw))
            print("  - Has exports:", weaponsMod.instance.exports ~= nil)
            
            if weaponsMod.instance.exports then
                print("\nExported functions:")
                for k, v in pairs(weaponsMod.instance.exports) do
                    print("  - " .. k .. ":", type(v))
                end
                
                -- Try to get current weapon
                if weaponsMod.instance.exports.getCurrentWeapon then
                    local weapon = weaponsMod.instance.exports.getCurrentWeapon()
                    if weapon then
                        print("\nCurrent weapon:", weapon.id or "unknown")
                        print("  - Template:", weapon.template and weapon.template.name or "none")
                    else
                        print("\nNo weapon equipped")
                    end
                end
            end
        end
    else
        print("Weapons mod NOT loaded!")
    end
    
    -- Check player mod
    local playerMod = modSystem.getLoadedMod("player_core_mod")
    if playerMod and playerMod.instance and playerMod.instance.exports then
        print("\nPlayer mod loaded")
        if playerMod.instance.exports.getPosition then
            local x, y = playerMod.instance.exports.getPosition()
            print("Player position:", x, y)
        end
    end
    
    -- Check if mod update is being called
    print("\nChecking mod update hooks...")
    if modSystem.updateMods then
        print("updateMods function exists")
    else
        print("updateMods function MISSING!")
    end
else
    print("ModSystem not available!")
end

print("=== End Test ===\n")