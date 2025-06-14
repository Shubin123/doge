-- Test script to verify all modules can be loaded correctly

local modules_to_test = {
    -- Math modules
    "lib.math.vec2",
    "lib.math.vec4",
    "lib.math.myMath",
    
    -- Graphics modules
    "lib.graphics.camera",
    "lib.graphics.draw",
    "lib.graphics.renderer",
    "lib.graphics.sprite",
    "lib.graphics.shader",
    "lib.graphics.effects",
    
    -- Utils
    "lib.utils.json",
    "lib.utils.lume",
    "lib.utils.lurker",
    "lib.utils.serial",
    
    -- Game modules
    "game.player",
    "game.enemy",
    "game.gun",
    "game.bullet",
    "game.rocket",
    "game.portal",
    "game.map",
    
    -- Systems
    "systems.water",
    "systems.grass",
    "systems.smoke",
    "systems.fire",
    "systems.blur",
    "systems.crt",
    "systems.light",
    
    -- UI
    "ui.menu",
    "ui.editor",
    "ui.command",
    "ui.cmndX",
    
    -- Network
    "network.multiplayer",
    
    -- Config
    "config.var",
    "config.snapshot",
}

print("Testing module loading...")
print(string.rep("-", 50))

local success_count = 0
local fail_count = 0

for _, module_name in ipairs(modules_to_test) do
    local status, result = pcall(require, module_name)
    if status then
        print("✅ " .. module_name)
        success_count = success_count + 1
    else
        print("❌ " .. module_name .. " - " .. tostring(result))
        fail_count = fail_count + 1
    end
end

print(string.rep("-", 50))
print(string.format("Results: %d succeeded, %d failed", success_count, fail_count))

if fail_count == 0 then
    print("\n🎉 All modules loaded successfully!")
else
    print("\n⚠️  Some modules failed to load. Check the errors above.")
end
