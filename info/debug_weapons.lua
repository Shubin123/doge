-- Debug script to check weapons mod loading
print("\n=== Debugging Weapons Mod ===")

-- First check if the mod files exist
local mod_path = "mods/weapons_core_mod/"
local main_exists = love.filesystem.getInfo(mod_path .. "main.lua")
local info_exists = love.filesystem.getInfo(mod_path .. "mod_info.json")

print("Mod files check:")
print("  - main.lua exists:", main_exists ~= nil)
print("  - mod_info.json exists:", info_exists ~= nil)

-- Check if mod is in registry
if modSystem then
    print("\nChecking mod registry...")
    
    -- Try to manually trigger a mod load
    if modSystem.loadMod then
        print("Attempting to load weapons_core_mod...")
        local success = modSystem.loadMod("weapons_core_mod")
        print("Load result:", success)
    end
    
    -- Check loaded mods
    if modSystem.getLoadedMod then
        local weaponsMod = modSystem.getLoadedMod("weapons_core_mod")
        if weaponsMod then
            print("\nWeapons mod is loaded!")
            print("Details:", weaponsMod)
        else
            print("\nWeapons mod NOT in loaded_mods")
        end
    end
end

print("=== End Debug ===\n")