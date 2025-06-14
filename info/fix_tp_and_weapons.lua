-- Fix script for tp command and weapons visibility

-- First, let's fix the getPlayerById function
function getPlayerById(id)
    -- For now, just return local player data if id is "local" or nil
    if not id or id == "local" then
        if modSystem and modSystem.getPlayerData then
            return modSystem.getPlayerData()
        end
    end
    
    -- TODO: Implement multiplayer player lookup
    return nil
end

-- Ensure global is set
_G.getPlayerById = getPlayerById

print("Fix applied: getPlayerById function created")

-- Check if weapons mod is loaded
if modSystem then
    local api = modSystem.createModAPI("fix_script")
    if api and api.mods and api.mods.weapons_core_mod then
        print("Weapons mod is loaded!")
        
        -- Try to get current weapon
        if api.mods.weapons_core_mod.exports then
            print("Weapons mod has exports")
        else
            print("Weapons mod missing exports")
        end
    else
        print("Weapons mod not found in API")
    end
end