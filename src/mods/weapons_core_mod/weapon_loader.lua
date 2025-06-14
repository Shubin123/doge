-- Weapon Loader - Loads weapon templates from files
local weaponLoader = {}

-- Load all weapon templates from the weapons directory
function weaponLoader.loadWeapons(mod_id)
    local weapons = {}
    
    -- List of weapon files to load
    local weapon_files = {
        "pistol",
        "smg",
        "shotgun",
        "rifle",
        "rocket_launcher"
    }
    
    -- Load each weapon template
    for _, weapon_name in ipairs(weapon_files) do
        local path = "mods/" .. mod_id .. "/weapons/" .. weapon_name .. ".lua"
        local chunk = love.filesystem.load(path)
        
        if chunk then
            local success, weapon_template = pcall(chunk)
            if success and weapon_template then
                weapons[weapon_name] = weapon_template
                print("[WEAPON_LOADER] Loaded weapon: " .. weapon_name)
            else
                print("[WEAPON_LOADER] Failed to load weapon: " .. weapon_name)
            end
        else
            print("[WEAPON_LOADER] Weapon file not found: " .. path)
        end
    end
    
    return weapons
end

-- Process weapon template to merge with defaults
function weaponLoader.processWeaponTemplate(template, defaults)
    local weapon = {}
    
    -- Start with defaults
    for k, v in pairs(defaults) do
        weapon[k] = v
    end
    
    -- Override with template values
    for k, v in pairs(template) do
        if type(v) == "table" and type(defaults[k]) == "table" then
            -- Deep merge for tables
            weapon[k] = {}
            for subk, subv in pairs(defaults[k]) do
                weapon[k][subk] = subv
            end
            for subk, subv in pairs(v) do
                weapon[k][subk] = subv
            end
        else
            weapon[k] = v
        end
    end
    
    return weapon
end

return weaponLoader