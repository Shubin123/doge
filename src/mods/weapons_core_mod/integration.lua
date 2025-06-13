-- Integration script for connecting weapons_core_mod with projectiles_mod and combat_effects_mod
-- This handles cross-mod communication and coordination

local weaponsIntegration = {}

-- Update the weapons_core_mod to use projectiles_mod when firing
function weaponsIntegration.setupProjectileIntegration(weapons_mod, projectiles_mod, effects_mod)
    local original_spawnProjectile = weapons_mod.spawnProjectile
    
    -- Override spawnProjectile to use projectiles_mod
    weapons_mod.spawnProjectile = function(x, y, dx, dy, template)
        if projectiles_mod and projectiles_mod.public then
            -- Convert weapon template to projectile parameters
            local projectile_params = {
                damage = template.damage,
                speed = template.projectile_speed,
                lifetime = 5.0,
                knockback = template.knockback,
                owner = "player",
                weapon_id = template.id
            }
            
            -- Spawn projectile using projectiles_mod
            return projectiles_mod.public.spawnProjectile(
                template.projectile_type, x, y, dx, dy, projectile_params
            )
        else
            -- Fallback to original implementation
            return original_spawnProjectile(x, y, dx, dy, template)
        end
    end
    
    -- Update muzzle flash creation to use effects_mod
    local original_createMuzzleFlash = weapons_mod.createMuzzleFlash
    weapons_mod.createMuzzleFlash = function(x, y, dx, dy, size)
        if effects_mod and effects_mod.public then
            effects_mod.public.createMuzzleFlash(x, y, {x = dx, y = dy}, {
                size = size or 1.0,
                duration = 0.1
            })
        else
            return original_createMuzzleFlash(x, y, dx, dy, size)
        end
    end
    
    -- Update shell ejection to use effects_mod
    local original_ejectShell = weapons_mod.ejectShell
    weapons_mod.ejectShell = function(x, y, shell_type)
        if effects_mod and effects_mod.public then
            local weapon = weapons_mod.getCurrentWeapon()
            local direction = {x = 1, y = 0}  -- would get from current aim direction
            effects_mod.public.createShellEjection(x, y, direction, shell_type)
        else
            return original_ejectShell(x, y, shell_type)
        end
    end
end

-- Setup collision handling between projectiles and effects
function weaponsIntegration.setupCollisionIntegration(projectiles_mod, effects_mod)
    if not projectiles_mod or not effects_mod then return end
    
    local original_handleEnemyHit = projectiles_mod.handleEnemyHit
    projectiles_mod.handleEnemyHit = function(proj, enemy_body, x, y)
        -- Call original handler
        original_handleEnemyHit(proj, enemy_body, x, y)
        
        -- Add blood effect
        if effects_mod.public then
            effects_mod.public.createBloodSplatter(x, y, proj.direction, proj.params.damage / 10)
        end
    end
    
    local original_handleEnvironmentHit = projectiles_mod.handleEnvironmentHit
    projectiles_mod.handleEnvironmentHit = function(proj, x, y)
        -- Call original handler
        original_handleEnvironmentHit(proj, x, y)
        
        -- Add sparks effect
        if effects_mod.public then
            effects_mod.public.createSparks(x, y, proj.direction)
        end
    end
end

return weaponsIntegration