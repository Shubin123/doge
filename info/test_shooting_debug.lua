-- Quick test to debug shooting issues
print("=== SHOOTING DEBUG TEST ===")

-- Test 1: Check if projectiles mod is accessible
local projectiles_mod = require("mods.projectiles_mod.main")
print("Projectiles mod loaded:", projectiles_mod ~= nil)

if projectiles_mod then
    print("Projectiles mod functions:")
    for k, v in pairs(projectiles_mod) do
        if type(v) == "function" then
            print("  - " .. k)
        elseif k == "public" and type(v) == "table" then
            print("  - public API:")
            for pk, pv in pairs(v) do
                if type(pv) == "function" then
                    print("    - " .. pk)
                end
            end
        end
    end
end

-- Test 2: Check weapons mod
local weapons_mod = require("mods.weapons_core_mod.main")
print("\nWeapons mod loaded:", weapons_mod ~= nil)

if weapons_mod then
    print("Weapons mod functions:")
    for k, v in pairs(weapons_mod) do
        if type(v) == "function" then
            print("  - " .. k)
        end
    end
end

print("\n=== END DEBUG TEST ===")