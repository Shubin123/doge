-- Direct test of weapons mod in-game
-- Put this in the game's console or run it

if modSystem and modSystem.getLoadedMod then
    local weaponsMod = modSystem.getLoadedMod("weapons_core_mod")
    if weaponsMod then
        print("Weapons mod found!")
        if weaponsMod.instance then
            print("Has instance")
            -- Try switching to pistol
            if weaponsMod.instance.switchWeapon then
                weaponsMod.instance.switchWeapon("pistol")
                print("Switched to pistol")
            end
            -- Force a render
            if weaponsMod.instance.renderWeapon then
                weaponsMod.instance.renderWeapon()
                print("Called renderWeapon")
            end
        end
    else
        print("Weapons mod not found - trying to load it")
        if modSystem.loadMod then
            local success = modSystem.loadMod("weapons_core_mod")
            print("Load result:", success)
        end
    end
end