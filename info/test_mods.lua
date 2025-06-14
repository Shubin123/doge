-- Test script to verify mod structure and loading
-- Run with: lua test_mods.lua

print("Testing Combat Mods Structure...")

-- Test mod info files
local function testModInfo(mod_name)
    local file = io.open("mods/" .. mod_name .. "/mod_info.json", "r")
    if file then
        local content = file:read("*all")
        file:close()
        print("✓ " .. mod_name .. " mod_info.json exists")
        
        -- Basic JSON validation
        if content:match('"id"') and content:match('"name"') then
            print("✓ " .. mod_name .. " mod_info.json has required fields")
        else
            print("✗ " .. mod_name .. " mod_info.json missing required fields")
        end
    else
        print("✗ " .. mod_name .. " mod_info.json not found")
    end
end

-- Test main.lua files
local function testMainLua(mod_name)
    local file = io.open("mods/" .. mod_name .. "/main.lua", "r")
    if file then
        local content = file:read("*all")
        file:close()
        print("✓ " .. mod_name .. " main.lua exists")
        
        -- Check for init function
        if content:match("function.*init") then
            print("✓ " .. mod_name .. " has init function")
        else
            print("✗ " .. mod_name .. " missing init function")
        end
    else
        print("✗ " .. mod_name .. " main.lua not found")
    end
end

-- Test each mod
local mods = {"weapons_core_mod", "projectiles_mod", "combat_effects_mod"}

for _, mod in ipairs(mods) do
    print("\n--- Testing " .. mod .. " ---")
    testModInfo(mod)
    testMainLua(mod)
end

print("\n--- Structure Test Complete ---")
print("If all items show ✓, the mods should load correctly.")