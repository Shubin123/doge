local block = require("game.block")

-- Gun prototype
local Gun = {}
Gun.__index = Gun

function Gun.new(params)
    local gun = setmetatable({}, Gun)

    gun.fireRate = params.fireRate or 5                    -- shots per second
    gun.projectileType = params.projectileType or "bullet" -- "bullet" or "rocket"
    gun.speed = params.speed or 500
    gun.spread = params.spread or 0                        -- spread angle in radians
    gun.damage = params.damage or 1
    gun.ringRadius = params.ringRadius or 25
    gun.barrelLength = params.barrelLength or 20
    gun.barrelThickness = params.barrelThickness or 4
    gun.cooldown = 0
    gun.lastAimDirection = vec2.new(1, 0) -- default facing right

    gun.blockInstance = params.model -- held model (shared, see GunTool.load)

    -- Rocket-specific parameters
    gun.topSpeed = params.topSpeed or 300
    gun.accelTime = params.accelTime or 1.0
    gun.projectileRadius = params.projectileRadius or 5
    gun.projectileLifetime = params.projectileLifetime or 5
    gun.bulletsPerShot = params.bulletsPerShot or 1 -- for shotguns
    gun.shellType = params.shellType or nil         -- "pistol", "shotgun", "rifle", "smg", or nil for no shells
    gun.isFullAuto = params.isFullAuto or false     -- full auto firing mode
    gun.ammoCost = params.ammoCost or 1             -- universal ammo spent per shot
    gun.tracer = params.tracer                      -- neon tracer colours (bullet.NEON layout); nil = default

    -- Muzzle flash parameters
    gun.muzzleFlash = {
        duration = params.muzzleFlash and params.muzzleFlash.duration or 0.08,
        coneAngle = params.muzzleFlash and params.muzzleFlash.coneAngle or math.rad(35),
        coneLength = params.muzzleFlash and params.muzzleFlash.coneLength or 150,
        brightness = params.muzzleFlash and params.muzzleFlash.brightness or 1.0,
        color = params.muzzleFlash and params.muzzleFlash.color or { 1, 0.9, 0.7 }
    }

    -- Particle effect parameters (gunpowder confetti)
    gun.particles = {
        count = params.particles and params.particles.count or 8,
        colors = params.particles and params.particles.colors or { { 1, 0.8, 0.3 }, { 1, 0.5, 0.2 }, { 0.8, 0.3, 0.1 } },
        lifespan = params.particles and params.particles.lifespan or 0.3,
        speed = params.particles and params.particles.speed or { min = 120, max = 250 },
        size = params.particles and params.particles.size or { min = 1, max = 3 },
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
    -- self:updateAiming()
end


function Gun:shoot(mouseX, mouseY)
    if self.cooldown > 0 then
        return
    end
    if not gun.useAmmo(self.ammoCost) then
        return
    end

    -- Along the aim as of now, the one the gun is drawn with this frame
    -- (a shot comes before GunTool.update has refreshed it)
    gun:updateAiming()
    local dir = self.lastAimDirection
    dir.x, dir.y = gun.lastAimDirection.x, gun.lastAimDirection.y

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

    -- Play gun sound based on weapon type with offset synced to fire rate
    local soundType = "gun1"    -- default to pistol sound
    if gun.currentWeaponIndex == 2 then
        soundType = "gun2"      -- SMG and Assault Rifle
    elseif gun.currentWeaponIndex == 3 then
        soundType = "gun3"      -- SMG and Assault Rifle
    elseif gun.currentWeaponIndex == 4 then
        soundType = "gun4"      -- Shotgun
    elseif gun.currentWeaponIndex == 5 then
        soundType = "fire"      -- Rocket Launcher uses fire sound
    elseif gun.currentWeaponIndex == 6 then
        -- soundType = "teslaCoil" -- Rocket Launcher uses fire sound
        return -- early return cause no bullet stuff
    elseif gun.currentWeaponIndex == 7 then
        return -- early return cause no bullet stuff
    elseif gun.currentWeaponIndex == 9 then
        soundType = "fire"      -- Black Hole Gun
    end

    audio.playSound(soundType, 1 / self.fireRate)

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
                lifetime = self.projectileLifetime,
                neon = self.tracer
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
    elseif self.projectileType == "blackhole" then
        blackholeGun.new({
            from = vec2.new(playerX, playerY),
            dir = dir,
            muzzle = self.ringRadius + 20,
            range = gun.aimDistance -- opens where you aimed
        })
    end

    -- Reset cooldown
    self.cooldown = 1 / self.fireRate
end

-- Main GunTool module
local GunTool = {}
GunTool.currentGun = nil
GunTool.guns = {}
GunTool.currentWeaponIndex = 1
GunTool.mousePressed = false -- track mouse state for full auto
GunTool.lastAimDirection = {}
GunTool.currentVel = {}
GunTool.lastAimDirection.x, GunTool.lastAimDirection.y = 0, 0
GunTool.currentVel.x, GunTool.currentVel.y = 1, 0 -- the flashlight's way, turning toward heading
-- The way you're going, or the cursor's while you stand still: the
-- flashlight points along it (systems/light.lua). (lastAimDirection is the
-- cursor's, for the weapons.)
GunTool.heading = { x = 1, y = 0 }
local HEADING_SPEED = 50 -- px/s: moving slower than this, you've stopped
local HEADING_TURN = 6.3 -- how quickly the flashlight turns to a new heading (1/s)
GunTool.aimDistance = 0 -- world px from the player to the cursor
GunTool.totalGuns = 0
GunTool.maxAmmo = 100
GunTool.ammo = GunTool.maxAmmo -- universal ammo shared by every weapon: the player's light (the HUD's light bar)
GunTool.ammoDeniedAt = -math.huge -- when a weapon last wanted more light than there was (the HUD flashes the bar)

-- Spend universal ammo; false (and nothing spent) when there isn't enough.
function GunTool.useAmmo(cost)
    if GunTool.ammo < cost then
        GunTool.ammoDeniedAt = love.timer.getTime()
        return false
    end
    GunTool.ammo = GunTool.ammo - cost
    return true
end

-- Drain for continuous weapons: takes up to `amount`, so the last scrap goes
-- too. False once there's nothing left.
function GunTool.drainAmmo(amount)
    if GunTool.ammo <= 0 then
        GunTool.ammoDeniedAt = love.timer.getTime()
        return false
    end
    GunTool.ammo = math.max(0, GunTool.ammo - amount)
    return true
end

-- Refill universal ammo; suckLight calls this as dead enemies' light reaches the player.
function GunTool.addAmmo(amount)
    GunTool.ammo = math.min(GunTool.maxAmmo, GunTool.ammo + amount)
end

-- Whether a hotbar entry can be used right now (one costing 0 needs no light).
function GunTool.canFire(weapon)
    if weapon.getCount and weapon:getCount() <= 0 then
        return false
    end
    if weapon.ammoCost == 0 then return true end
    return GunTool.ammo > 0 and GunTool.ammo >= (weapon.ammoCost or 0)
end

-- Fireballs as a hotbar item. The stack is fire.lua's ring of orbiting
-- fireballs (it regrows over time), and that's all a throw costs: no light.
local fireballItem = { ammoCost = 0 }

-- Throw a fireball from the ring along `dir` (unit vec2).
-- Used by the hotbar slot and the right-click quick throw.
function GunTool.throwFireball(dir)
    if player.inCar or fire.getAvailableCount() == 0 then
        return false
    end
    return fire.throw(dir)
end

function fireballItem:update(dt)
end

function fireballItem:drawBarrel()
end

function fireballItem:shoot()
    GunTool.throwFireball(GunTool.lastAimDirection)
end

function fireballItem:getCount()
    return fire.getAvailableCount()
end

function GunTool:updateAiming()
    -- Get current mouse position (on the picture under the CRT bulge)
    local mouseX, mouseY = crt.mouse()

    -- Convert screen coordinates to world coordinates
    local zoom = camera.getZoom()
    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()

    -- Calculate offset from screen center to mouse
    local dx = (mouseX - screenWidth / 2) / zoom
    local dy = (mouseY - screenHeight / 2) / zoom

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
    GunTool.aimDistance = math.sqrt(dirX * dirX + dirY * dirY)

    -- Update aim direction
    -- self.lastAimDirection = dir
    GunTool.lastAimDirection  = dir
end

-- Draw a weapon's ring and held model (weapon.blockInstance) around the
-- player, facing the aim. Also used by weapons outside this file (tesla coil).
function GunTool.drawHeldModel(weapon)
    local ringRadius = weapon.ringRadius or 25
    local playerX, playerY = player.getPosition()
    local aim = GunTool.lastAimDirection

    -- Draw ring around player (semi-transparent)
    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.circle("line", playerX, playerY, ringRadius)

    -- The model sits on the ring edge; its sprite frame follows the aim
    local model = weapon.blockInstance
    if model then
        model:addToDrawList(dynamic_draw_list, playerX + aim.x * ringRadius, playerY + aim.y * ringRadius,
            aim.x, aim.y, 160, model.lineX, model.lineY)
        dynamic_draw_list[#dynamic_draw_list].source_object_type = "gun"
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function Gun:drawBarrel()
    GunTool.drawHeldModel(self)
end

-- A held weapon model: a 128px turntable sheet in the 16-wide block layout,
-- DXT5-compressed. (lineX, lineY) is the frame texel its barrel's line runs
-- through at every heading, which is drawn on the shot's line. `turntable`
-- is for sheets that don't turn a degree a frame (block:turntableFrame).
local function loadModel(path, lineX, lineY, turntable)
    local model = block.new(path, 128, 128, 2, 464, 1)
    model.lineX, model.lineY = lineX, lineY
    model.turntable = turntable
    return model
end

function GunTool.load(world)
    -- Initialize bullet and rocket modules
    bullet.load(world)
    rocket.load(world)
    blackholeGun.load()

    -- Held models, one per weapon. pistol/smg/shotgun/bow/tesla are rendered
    -- by tools/weapon_models (a degree a frame, the pivot at 60, 60, the
    -- barrel above it by its height).
    local pistolModel = loadModel("gfx/3d/pistol.dds", 60, 55)
    local smgModel = loadModel("gfx/3d/smg.dds", 60, 56)
    local shotgunModel = loadModel("gfx/3d/shotgun.dds", 60, 55.5)
    local bowModel = loadModel("gfx/3d/bow.dds", 60, 60)
    local teslaModel = loadModel("gfx/3d/tesla.dds", 60, 56)
    -- The older sheets hold still for a few rows, then turn about 0.86
    -- degrees a frame, each its own way round.
    local launcherModel = loadModel("gfx/3d/lauchergun.dds", 64, 50, { first = 38, frames = 419, facing = 270 })
    local rifleModel = loadModel("gfx/3d/gun.dds", 64, 58, { first = 34, frames = 420, facing = 90 })
    local portalModel = loadModel("gfx/3d/portalGun.dds", 64, 65, { first = 31, frames = 419, facing = 90 })

    -- Create 5 weapon presets for number keys 1-5
    GunTool.guns[1] = Gun.new({ -- Pistol (1)
        model = pistolModel,
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
            color = { 1, 0.9, 0.7 }
        },
        particles = {
            count = 5,
            colors = { { 1, 0.8, 0.3 }, { 1, 0.6, 0.2 } },
            lifespan = 0.25,
            speed = { min = 100, max = 180 },
            size = { min = 1, max = 2 },
            spreadAngle = math.rad(15)
        },
        knockback = {
            force = 35, -- Visible pistol recoil
            shakeIntensity = 1.5,
            shakeDuration = 0.08
        }
    })

    GunTool.guns[2] = Gun.new({ -- SMG (2)
        model = smgModel,
        tracer = { core = { 0.6, 1.0, 0.15 }, halo = { 0.0, 0.95, 0.55 }, radius = 10 }, -- acid green
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
            color = { 1, 0.85, 0.6 }
        },
        particles = {
            count = 4,
            colors = { { 1, 0.7, 0.3 }, { 0.9, 0.5, 0.2 } },
            lifespan = 0.2,
            speed = { min = 80, max = 150 },
            size = { min = 0.8, max = 1.5 },
            spreadAngle = math.rad(12)
        },
        knockback = {
            force = 20, -- Light but visible SMG recoil
            shakeIntensity = 1.0,
            shakeDuration = 0.06
        }
    })

    GunTool.guns[3] = Gun.new({ -- Shotgun (3)
        model = shotgunModel,
        tracer = { core = { 1.0, 0.5, 0.08 }, halo = { 1.0, 0.08, 0.35 }, radius = 9 }, -- molten orange
        fireRate = 1.2,
        projectileType = "bullet",
        speed = 650,           -- Increased from 400 to 650 for faster, more realistic shotgun pellets
        spread = math.rad(35), -- 35 degree spread
        damage = 0.6,          -- Reduced individual pellet damage since we have more pellets
        ringRadius = 25,
        barrelLength = 25,
        barrelThickness = 6,
        projectileRadius = 1.5,   -- Slightly smaller pellets
        projectileLifetime = 2.0, -- Shorter lifetime - shotgun pellets lose velocity faster
        bulletsPerShot = 8,       -- Increased from 6 to 8 pellets for more realistic spread
        ammoCost = 3,
        shellType = "shotgun",
        muzzleFlash = {
            duration = 0.12,
            coneAngle = math.rad(45), -- Wide cone for shotgun
            coneLength = 180,
            brightness = 1.2,
            color = { 1, 0.9, 0.5 }
        },
        particles = {
            count = 15, -- More particles for shotgun
            colors = { { 1, 0.8, 0.2 }, { 1, 0.6, 0.1 }, { 0.9, 0.4, 0.1 } },
            lifespan = 0.4,
            speed = { min = 150, max = 300 },
            size = { min = 1.5, max = 4 },
            spreadAngle = math.rad(40)
        },
        knockback = {
            force = 85, -- Strong shotgun kick
            shakeIntensity = 4.0,
            shakeDuration = 0.15
        }
    })

    GunTool.guns[4] = Gun.new({ -- Assault Rifle (4) - FULL AUTO
        model = rifleModel,
        tracer = { core = { 0.4, 0.8, 1.0 }, halo = { 0.55, 0.15, 1.0 }, radius = 13 }, -- ice blue / violet
        fireRate = 12,          -- Higher fire rate for full auto
        projectileType = "bullet",
        speed = 800,
        spread = math.rad(3), -- Slightly more spread for realism
        damage = 1.0,         -- Slightly less damage to balance the high fire rate
        ringRadius = 28,
        barrelLength = 22,
        barrelThickness = 4,
        projectileRadius = 3,
        projectileLifetime = 5,
        bulletsPerShot = 1,
        shellType = "rifle",
        isFullAuto = true, -- FULL AUTO MODE!
        muzzleFlash = {
            duration = 0.04,
            coneAngle = math.rad(15), -- Narrow cone for rifle
            coneLength = 160,
            brightness = 0.9,
            color = { 1, 0.95, 0.8 }
        },
        particles = {
            count = 6,
            colors = { { 1, 0.9, 0.4 }, { 1, 0.7, 0.3 }, { 0.9, 0.5, 0.2 } },
            lifespan = 0.3,
            speed = { min = 120, max = 220 },
            size = { min = 1, max = 2.5 },
            spreadAngle = math.rad(10)
        },
        knockback = {
            force = 42, -- Moderate rifle recoil
            shakeIntensity = 2.0,
            shakeDuration = 0.08
        }
    })

    GunTool.guns[5] = Gun.new({ -- Rocket Launcher (5)
        model = launcherModel,
        fireRate = 0.7,
        projectileType = "rocket",
        speed = 300, -- Increased initial speed
        spread = 0,
        damage = 8,
        ringRadius = 32,
        barrelLength = 35,
        barrelThickness = 10,
        topSpeed = 800,  -- Increased top speed
        accelTime = 0.6, -- Faster acceleration (reduced time to reach top speed)
        projectileRadius = 10,
        bulletsPerShot = 1,
        ammoCost = 10,
        -- No shellType - rockets don't eject shells
        muzzleFlash = {
            duration = 0.15,
            coneAngle = math.rad(25),
            coneLength = 220,
            brightness = 1.5, -- Very bright
            color = { 1, 0.8, 0.3 }
        },
        particles = {
            count = 20, -- Lots of particles for rocket
            colors = { { 1, 0.9, 0.2 }, { 1, 0.6, 0.1 }, { 0.8, 0.3, 0.1 }, { 1, 0.4, 0.0 } },
            lifespan = 0.6,
            speed = { min = 200, max = 400 },
            size = { min = 2, max = 6 },
            spreadAngle = math.rad(30)
        },
        knockback = {
            force = 120, -- Strong rocket launcher kick
            shakeIntensity = 5.0,
            shakeDuration = 0.2
        }
    })
    GunTool.guns[6] = teslaCoil
    teslaCoil.blockInstance = teslaModel
    GunTool.guns[7] = arrows
    arrows.blockInstance = bowModel
    GunTool.guns[8] = fireballItem

    GunTool.guns[9] = Gun.new({ -- Black Hole Gun (9): shots open small black holes (blackholeGun.lua)
        model = portalModel,
        fireRate = 0.8,
        projectileType = "blackhole",
        ringRadius = 28,
        barrelLength = 8, -- the flash where the shot leaves, just past the muzzle
        ammoCost = 15,
        muzzleFlash = {
            duration = 0.18,
            coneAngle = math.rad(30),
            coneLength = 140,
            brightness = 1.0,
            color = { 0.55, 0.40, 1.0 }
        },
        particles = {
            count = 14,
            colors = { { 0.45, 0.22, 1.0 }, { 0.75, 0.85, 1.0 }, { 0.2, 0.1, 0.5 } },
            lifespan = 0.45,
            speed = { min = 60, max = 160 },
            size = { min = 1, max = 3 },
            spreadAngle = math.rad(50)
        },
        knockback = {
            force = 60,
            shakeIntensity = 2.5,
            shakeDuration = 0.15
        }
    })
    -- teslaCoil.updateAiming = GunTool.guns[5]:updateAiming()


    GunTool.totalGuns = #GunTool.guns
    -- Set default gun (pistol)
    GunTool.currentGun = GunTool.guns[1]
    GunTool.currentWeaponIndex = 1
    GunTool.ammo = GunTool.maxAmmo
end

function GunTool.update(dt)
    if GunTool.currentGun then
        GunTool.currentGun:update(dt)

        -- Handle full auto firing
        if GunTool.mousePressed and GunTool.currentGun.isFullAuto then
            local mouseX, mouseY = crt.mouse()
            GunTool.currentGun:shoot(mouseX, mouseY)
        end
        -- GunTool.currentGun
    end


    -- The heading follows you while you move, and the cursor while you
    -- stand still
    local playerVX, playerVY = player.body:getLinearVelocity()
    local playerSpeed = math.sqrt(playerVX * playerVX + playerVY * playerVY)
    local cursor = GunTool.lastAimDirection
    if playerSpeed > HEADING_SPEED then
        GunTool.heading.x, GunTool.heading.y = playerVX / playerSpeed, playerVY / playerSpeed
    elseif cursor.x ~= 0 or cursor.y ~= 0 then
        GunTool.heading.x, GunTool.heading.y = cursor.x, cursor.y
    end

    -- The flashlight turns toward it by its angle, so doubling back turns
    -- it round (easing between unit vectors stuck at exactly 180 degrees)
    local have = math.atan2(GunTool.currentVel.y, GunTool.currentVel.x)
    local turn = (math.atan2(GunTool.heading.y, GunTool.heading.x) - have + math.pi) % (2 * math.pi) - math.pi
    have = have + turn * (1 - math.exp(-HEADING_TURN * dt))
    GunTool.currentVel.x, GunTool.currentVel.y = math.cos(have), math.sin(have)
    GunTool:updateAiming()
    -- Update bullet and rocket modules, and the black hole gun's holes
    bullet.update(dt)
    rocket.update(dt)
    blackholeGun.update(dt)
end

function GunTool.mousepressed(x, y, button)
    if player.inCar then return end -- no shooting from the car
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
    -- Draw barrel and ring (not while you're in the car)
    if GunTool.currentGun and not player.inCar then
        GunTool.currentGun:drawBarrel()
    end

    -- Draw all projectiles
    -- bullet.draw()
    bullet.populate()
    rocket.populate()
    blackholeGun.populate()
end

function GunTool.switchGun(weaponIndex)
    if GunTool.guns[weaponIndex] then
        if GunTool.currentGun == teslaCoil and GunTool.guns[weaponIndex] ~= teslaCoil then
            teslaCoil.stop() -- its arcs would hang there, no longer updated
        end
        GunTool.currentGun = GunTool.guns[weaponIndex]
        GunTool.currentWeaponIndex = weaponIndex
        print("Switched to weapon " .. weaponIndex)
    end
end

function GunTool.keypressed(key)
    local weaponNum = tonumber(key)
    if weaponNum and weaponNum >= 1 and weaponNum <=  GunTool.totalGuns then
        GunTool.switchGun(weaponNum)
    end
end

-- Scroll through the hotbar like Minecraft: wheel down moves right, wrapping.
function GunTool.wheelmoved(x, y)
    if y == 0 then return end
    local step = y > 0 and -1 or 1
    GunTool.switchGun((GunTool.currentWeaponIndex - 1 + step) % GunTool.totalGuns + 1)
end

function GunTool.getCurrentGun()
    return GunTool.currentGun
end

-- function GunTool.collision(fixture_a, fixture_b, contact)

--     rocket.collision(fixture_a, fixture_b, contact)
--     bullet.collision(fixture_a, fixture_b, contact)

--     -- local ud_a = fixture_a:getUserData()
--     -- local ud_b = fixture_b:getUserData()

--     -- -- It's good practice to check if user data exists
--     -- if not ud_a or not ud_b then return end

--     -- -- Check for rocket involvement first (using the specific 'topSpeed' check)
--     -- if (type(ud_a) == 'table' and ud_a.topSpeed) or (type(ud_b) == 'table' and ud_b.topSpeed) then
--     --     rocket.collision(fixture_a, fixture_b, contact)
--     --     return -- Exit after handling to prevent double-processing
--     -- end

--     -- -- Then, check for bullet involvement (bullets have 'speed' but not 'topSpeed')
--     -- if (type(ud_a) == 'table' and ud_a.speed and not ud_a.topSpeed) or
--     --    (type(ud_b) == 'table' and ud_b.speed and not ud_b.topSpeed) then
--     --     bullet.collision(fixture_a, fixture_b, contact)
--     --     return
--     -- end
-- end

return GunTool
