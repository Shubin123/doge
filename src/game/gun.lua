-- Gun prototype
local Gun = {}
Gun.__index = Gun

function Gun.new(params)
    local gun = setmetatable({}, Gun)
    
    gun.fireRate = params.fireRate or 5 -- shots per second
    gun.projectileType = params.projectileType or "bullet" -- "bullet" or "rocket"
    gun.speed = params.speed or 500
    gun.spread = params.spread or 0 -- spread angle in radians
    gun.damage = params.damage or 1
    gun.ringRadius = params.ringRadius or 25
    gun.barrelLength = params.barrelLength or 20
    gun.barrelThickness = params.barrelThickness or 4
    gun.cooldown = 0
    gun.lastAimDirection = vec2.new(1, 0) -- default facing right
    
    -- Initialize block instance for gun sprite
    local block = require("game.block")
    gun.blockInstance = block.new("gfx/3d/portalGun.png", 128, 128, 2, 450, 1)
    
    -- Rocket-specific parameters
    gun.topSpeed = params.topSpeed or 300
    gun.accelTime = params.accelTime or 1.0
    gun.projectileRadius = params.projectileRadius or 5
    gun.projectileLifetime = params.projectileLifetime or 5
    gun.bulletsPerShot = params.bulletsPerShot or 1 -- for shotguns
    gun.shellType = params.shellType or nil  -- "pistol", "shotgun", "rifle", "smg", or nil for no shells
    gun.isFullAuto = params.isFullAuto or false  -- full auto firing mode
    
    -- Muzzle flash parameters
    gun.muzzleFlash = {
        duration = params.muzzleFlash and params.muzzleFlash.duration or 0.08,
        coneAngle = params.muzzleFlash and params.muzzleFlash.coneAngle or math.rad(35),
        coneLength = params.muzzleFlash and params.muzzleFlash.coneLength or 150,
        brightness = params.muzzleFlash and params.muzzleFlash.brightness or 1.0,
        color = params.muzzleFlash and params.muzzleFlash.color or {1, 0.9, 0.7}
    }
    
    -- Particle effect parameters (gunpowder confetti)
    gun.particles = {
        count = params.particles and params.particles.count or 8,
        colors = params.particles and params.particles.colors or {{1, 0.8, 0.3}, {1, 0.5, 0.2}, {0.8, 0.3, 0.1}},
        lifespan = params.particles and params.particles.lifespan or 0.3,
        speed = params.particles and params.particles.speed or {min = 120, max = 250},
        size = params.particles and params.particles.size or {min = 1, max = 3},
        spreadAngle = params.particles and params.particles.spreadAngle or math.rad(25)
    }
    
    -- Knockback parameters
    gun.knockback = {
        force = params.knockback and params.knockback.force or 50,
        shakeIntensity = params.knockback and params.knockback.shakeIntensity or 2,
        shakeDuration = params.knockback and params.knockback.shakeDuration or 0.1
    }
    
    return gun
end

function Gun:update(dt)
    -- Decrement cooldown
    if self.cooldown > 0 then
        self.cooldown = self.cooldown - dt
    end
    
    -- Update aiming direction based on mouse position
    self:updateAiming()
end

function Gun:updateAiming()
    -- Get current mouse position
    local mouseX, mouseY = love.mouse.getPosition()
    
    -- Convert screen coordinates to world coordinates
    local zoom = camera.getZoom()
    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()
    
    -- Calculate offset from screen center to mouse
    local dx = (mouseX - screenWidth/2) / zoom
    local dy = (mouseY - screenHeight/2) / zoom
    
    -- Get player world position
    local playerX, playerY = player.getPosition()
    
    -- Calculate world mouse position
    local worldMouseX = playerX + dx
    local worldMouseY = playerY + dy
    
    -- Calculate direction from player to mouse
    local dirX = worldMouseX - playerX
    local dirY = worldMouseY - playerY
    
    -- Check for zero vector to avoid NaN
    if dirX == 0 and dirY == 0 then
        return -- Keep previous direction
    end
    
    local dir = vec2.norm(vec2.new(dirX, dirY))
    
    -- Update aim direction
    self.lastAimDirection = dir
end

function Gun:shoot(mouseX, mouseY)
    if self.cooldown > 0 then
        return
    end
    
    -- Use current aiming direction (already updated in Gun:update)
    local dir = self.lastAimDirection
    
    -- Get player position
    local playerX, playerY = player.getPosition()
    local spawnPos = vec2.new(playerX, playerY) + dir * (self.ringRadius + 20)
    
    -- Calculate barrel tip position (where particles should spawn from)
    local barrelTipPos = spawnPos + dir * self.barrelLength
    
    -- Create muzzle flash effect with gun-specific parameters
    bullet.createMuzzleFlash(barrelTipPos, dir, {
        duration = self.muzzleFlash.duration,
        coneAngle = self.muzzleFlash.coneAngle,
        coneLength = self.muzzleFlash.coneLength,
        intensity = self.muzzleFlash.brightness,
        color = self.muzzleFlash.color
    })
    
    -- Create particle effects (gunpowder confetti) from barrel tip
    bullet.createParticleEffect(barrelTipPos, dir, self.particles)
    
    -- Apply knockback to player (opposite direction of shot)
    player.applyKnockback(-dir, self.knockback.force)
    
    -- Apply screen shake if camera module supports it
    if camera.shake then
        camera.shake(self.knockback.shakeIntensity, self.knockback.shakeDuration)
    end
    
    -- Create shell ejection for appropriate weapons
    if self.shellType then
        bullet.createShellEjection(spawnPos, dir, self.shellType)
    end
    
    
    -- Shoot based on projectile type
    if self.projectileType == "bullet" then
        -- Handle multiple bullets for shotguns
        for i = 1, self.bulletsPerShot do
            local spreadAngle = 0
            if self.bulletsPerShot > 1 then
                -- For shotguns, use random spread within the cone for realistic behavior
                local maxSpread = self.spread
                spreadAngle = (math.random() - 0.5) * maxSpread
            end
            
            -- Apply spread to direction
            local spreadDir = vec2.new(
                dir.x * math.cos(spreadAngle) - dir.y * math.sin(spreadAngle),
                dir.x * math.sin(spreadAngle) + dir.y * math.cos(spreadAngle)
            )
            
            -- Add slight speed variation for realism (±10%)
            local speedVariation = self.speed * (0.9 + math.random() * 0.2)
            
            bullet.new({
                pos = spawnPos,
                dir = spreadDir,
                speed = speedVariation,
                damage = self.damage,
                radius = self.projectileRadius,
                lifetime = self.projectileLifetime
            })
        end
    elseif self.projectileType == "rocket" then
        rocket.new({
            pos = spawnPos,
            dir = dir,
            topSpeed = self.topSpeed,
            accelTime = self.accelTime,
            damage = self.damage,
            radius = self.projectileRadius
        })
    end
    
    -- Reset cooldown
    self.cooldown = 1 / self.fireRate
end

function Gun:drawBarrel()
    local playerX, playerY = player.getPosition()
    
    -- Draw ring around player (semi-transparent)
    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.circle("line", playerX, playerY, self.ringRadius)
    
    -- Calculate barrel position on the ring (start from ring edge)
    local barrelStartX = playerX + self.lastAimDirection.x * self.ringRadius
    local barrelStartY = playerY + self.lastAimDirection.y * self.ringRadius
    
    -- Use the block instance to draw the gun sprite with rotation based on aiming direction
    if self.blockInstance then
        local vx = self.lastAimDirection.x
        local vy = self.lastAimDirection.y
        -- Adjust angle offset to align with aiming direction, compensating for the negated x-component in getSpriteForHeading
        self.blockInstance:addToDrawList(dynamic_draw_list, barrelStartX, barrelStartY, -vx, -vy, 160,60,60)
        dynamic_draw_list[#dynamic_draw_list].source_object_type = "gun"
    end
    
    love.graphics.setColor(1, 1, 1, 1)
end


-- Main GunTool module
local GunTool = {}
GunTool.currentGun = nil
GunTool.guns = {}
GunTool.currentWeaponIndex = 1
GunTool.mousePressed = false  -- track mouse state for full auto

function GunTool.load(world)
    -- Initialize bullet and rocket modules
    bullet.load(world)
    rocket.load(world)
    
    -- Create 5 weapon presets for number keys 1-5
    GunTool.guns[1] = Gun.new({  -- Pistol (1)
        fireRate = 4,
        projectileType = "bullet",
        speed = 700,
        spread = 0,
        damage = 1,
        ringRadius = 25,
        barrelLength = 18,
        barrelThickness = 3,
        projectileRadius = 3,
        projectileLifetime = 4,
        bulletsPerShot = 1,
        shellType = "pistol",
        muzzleFlash = {
            duration = 0.2,
            coneAngle = math.rad(20),
            coneLength = 120,
            brightness = 0.8,
            color = {1, 0.9, 0.7}
        },
        particles = {
            count = 5,
            colors = {{1, 0.8, 0.3}, {1, 0.6, 0.2}},
            lifespan = 0.25,
            speed = {min = 100, max = 180},
            size = {min = 1, max = 2},
            spreadAngle = math.rad(15)
        },
        knockback = {
            force = 35,  -- Visible pistol recoil
            shakeIntensity = 1.5,
            shakeDuration = 0.08
        }
    })
    
    GunTool.guns[2] = Gun.new({  -- SMG (2)
        fireRate = 8,
        projectileType = "bullet",
        speed = 500,
        spread = math.rad(5), -- 5 degree spread
        damage = 0.6,
        ringRadius = 22,
        barrelLength = 15,
        barrelThickness = 3,
        projectileRadius = 2,
        projectileLifetime = 3,
        bulletsPerShot = 1,
        shellType = "smg",
        muzzleFlash = {
            duration = 0.05,
            coneAngle = math.rad(18),
            coneLength = 100,
            brightness = 0.7,
            color = {1, 0.85, 0.6}
        },
        particles = {
            count = 4,
            colors = {{1, 0.7, 0.3}, {0.9, 0.5, 0.2}},
            lifespan = 0.2,
            speed = {min = 80, max = 150},
            size = {min = 0.8, max = 1.5},
            spreadAngle = math.rad(12)
        },
        knockback = {
            force = 20,  -- Light but visible SMG recoil
            shakeIntensity = 1.0,
            shakeDuration = 0.06
        }
    })
    
    GunTool.guns[3] = Gun.new({  -- Shotgun (3)
        fireRate = 1.2,
        projectileType = "bullet",
        speed = 650, -- Increased from 400 to 650 for faster, more realistic shotgun pellets
        spread = math.rad(35), -- 35 degree spread
        damage = 0.6, -- Reduced individual pellet damage since we have more pellets
        ringRadius = 25,
        barrelLength = 25,
        barrelThickness = 6,
        projectileRadius = 1.5, -- Slightly smaller pellets
        projectileLifetime = 2.0, -- Shorter lifetime - shotgun pellets lose velocity faster
        bulletsPerShot = 8, -- Increased from 6 to 8 pellets for more realistic spread
        shellType = "shotgun",
        muzzleFlash = {
            duration = 0.12,
            coneAngle = math.rad(45), -- Wide cone for shotgun
            coneLength = 180,
            brightness = 1.2,
            color = {1, 0.9, 0.5}
        },
        particles = {
            count = 15, -- More particles for shotgun
            colors = {{1, 0.8, 0.2}, {1, 0.6, 0.1}, {0.9, 0.4, 0.1}},
            lifespan = 0.4,
            speed = {min = 150, max = 300},
            size = {min = 1.5, max = 4},
            spreadAngle = math.rad(40)
        },
        knockback = {
            force = 85,  -- Strong shotgun kick
            shakeIntensity = 4.0,
            shakeDuration = 0.15
        }
    })
    
    GunTool.guns[4] = Gun.new({  -- Assault Rifle (4) - FULL AUTO
        fireRate = 12,  -- Higher fire rate for full auto
        projectileType = "bullet",
        speed = 800,
        spread = math.rad(3), -- Slightly more spread for realism
        damage = 1.0,  -- Slightly less damage to balance the high fire rate
        ringRadius = 28,
        barrelLength = 22,
        barrelThickness = 4,
        projectileRadius = 3,
        projectileLifetime = 5,
        bulletsPerShot = 1,
        shellType = "rifle",
        isFullAuto = true,  -- FULL AUTO MODE!
        muzzleFlash = {
            duration = 0.04,
            coneAngle = math.rad(15), -- Narrow cone for rifle
            coneLength = 160,
            brightness = 0.9,
            color = {1, 0.95, 0.8}
        },
        particles = {
            count = 6,
            colors = {{1, 0.9, 0.4}, {1, 0.7, 0.3}, {0.9, 0.5, 0.2}},
            lifespan = 0.3,
            speed = {min = 120, max = 220},
            size = {min = 1, max = 2.5},
            spreadAngle = math.rad(10)
        },
        knockback = {
            force = 42,  -- Moderate rifle recoil
            shakeIntensity = 2.0,
            shakeDuration = 0.08
        }
    })
    
    GunTool.guns[5] = Gun.new({  -- Rocket Launcher (5)
        fireRate = 0.7,
        projectileType = "rocket",
        speed = 300,  -- Increased initial speed
        spread = 0,
        damage = 8,
        ringRadius = 32,
        barrelLength = 35,
        barrelThickness = 10,
        topSpeed = 800,  -- Increased top speed
        accelTime = 0.6,  -- Faster acceleration (reduced time to reach top speed)
        projectileRadius = 10,
        bulletsPerShot = 1,
        -- No shellType - rockets don't eject shells
        muzzleFlash = {
            duration = 0.15,
            coneAngle = math.rad(25),
            coneLength = 220,
            brightness = 1.5, -- Very bright
            color = {1, 0.8, 0.3}
        },
        particles = {
            count = 20, -- Lots of particles for rocket
            colors = {{1, 0.9, 0.2}, {1, 0.6, 0.1}, {0.8, 0.3, 0.1}, {1, 0.4, 0.0}},
            lifespan = 0.6,
            speed = {min = 200, max = 400},
            size = {min = 2, max = 6},
            spreadAngle = math.rad(30)
        },
        knockback = {
            force = 120, -- Strong rocket launcher kick
            shakeIntensity = 5.0,
            shakeDuration = 0.2
        }
    })
    
    -- Set default gun (pistol)
    GunTool.currentGun = GunTool.guns[1]
    GunTool.currentWeaponIndex = 1
end

function GunTool.update(dt)
    if GunTool.currentGun then
        GunTool.currentGun:update(dt)
        
        -- Handle full auto firing
        if GunTool.mousePressed and GunTool.currentGun.isFullAuto then
            local mouseX, mouseY = love.mouse.getPosition()
            GunTool.currentGun:shoot(mouseX, mouseY)
        end
    end
    
    -- Update bullet and rocket modules
    bullet.update(dt)
    rocket.update(dt)
end

function GunTool.mousepressed(x, y, button)
    if button == 1 and GunTool.currentGun then -- left mouse button
        GunTool.mousePressed = true
        GunTool.currentGun:shoot(x, y)
    end
end

function GunTool.mousereleased(x, y, button)
    if button == 1 then -- left mouse button
        GunTool.mousePressed = false
    end
end

function GunTool.drawWorld()
    -- Draw barrel and ring
    if GunTool.currentGun then
        GunTool.currentGun:drawBarrel()
    end
    
    -- Draw all projectiles
    -- bullet.draw()
    bullet.populate()
    rocket.populate()
end

function GunTool.switchGun(weaponIndex)
    if GunTool.guns[weaponIndex] then
        GunTool.currentGun = GunTool.guns[weaponIndex]
        GunTool.currentWeaponIndex = weaponIndex
        print("Switched to weapon " .. weaponIndex)
    end
end

function GunTool.keypressed(key)
    -- Handle weapon switching with number keys 1-5
    local weaponNum = tonumber(key)
    if weaponNum and weaponNum >= 1 and weaponNum <= 5 then
        GunTool.switchGun(weaponNum)
    end
end

function GunTool.getCurrentGun()
    return GunTool.currentGun
end

function GunTool.collision(fixture_a, fixture_b, contact)

    bullet.collision(fixture_a, fixture_b, contact)
    rocket.collision(fixture_a, fixture_b, contact)
    -- local ud_a = fixture_a:getUserData()
    -- local ud_b = fixture_b:getUserData()

    -- -- It's good practice to check if user data exists
    -- if not ud_a or not ud_b then return end

    -- -- Check for rocket involvement first (using the specific 'topSpeed' check)
    -- if (type(ud_a) == 'table' and ud_a.topSpeed) or (type(ud_b) == 'table' and ud_b.topSpeed) then
    --     rocket.collision(fixture_a, fixture_b, contact)
    --     return -- Exit after handling to prevent double-processing
    -- end

    -- -- Then, check for bullet involvement (bullets have 'speed' but not 'topSpeed')
    -- if (type(ud_a) == 'table' and ud_a.speed and not ud_a.topSpeed) or 
    --    (type(ud_b) == 'table' and ud_b.speed and not ud_b.topSpeed) then
    --     bullet.collision(fixture_a, fixture_b, contact)
    --     return
    -- end
end

return GunTool
