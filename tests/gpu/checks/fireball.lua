--[[
  Fireballs cost no light (game/gun.lua's throwFireball), only a fireball
  from the ring round you:

      python3 tests/gpu/run.py --checks --only fireball

  1. a throw (the hotbar slot's or the right-click one) takes one from the
     ring and leaves the light bar as it was;
  2. with the bar empty she can still throw, and the slot isn't greyed out;
  3. with the ring empty, nothing's thrown.
]]
return function(h)
    player.god = true
    h.advance(5)
    local addAmmo = gun.addAmmo -- (dead enemies' light streaming in would refill the bar)
    gun.addAmmo = function() end
    local slot = gun.guns[8]
    local right = vec2.new(1, 0)
    local function ring(n)
        for _ = 1, n do
            if fire.getAvailableCount() >= n then return end
            fire.addFireball()
        end
    end

    ring(3)
    gun.ammo = gun.maxAmmo * 0.5
    local before, had = gun.ammo, fire.getAvailableCount()
    local thrown = gun.throwFireball(right)
    h.check("a throw takes a fireball from the ring", thrown and fire.getAvailableCount() == had - 1,
        string.format("%d -> %d", had, fire.getAvailableCount()))
    h.check("and no light", gun.ammo == before, string.format("%.1f -> %.1f", before, gun.ammo))

    gun.ammo = 0
    ring(2)
    h.check("with the bar empty the slot's still lit", gun.canFire(slot))
    thrown = gun.throwFireball(right)
    h.check("and she can still throw one", thrown and gun.ammo == 0)

    while fire.removeFireball() do end
    h.check("with the ring empty, nothing's thrown", not gun.throwFireball(right) and not gun.canFire(slot))

    gun.addAmmo = addAmmo
end
