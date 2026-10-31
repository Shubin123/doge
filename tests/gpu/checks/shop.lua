--[[
  The shop in the house (game/shop.lua), driven through the game's input:

      python3 tests/gpu/run.py --checks

  1. by day, E at the counter opens it; a number buys that item for XP;
  2. without the XP nothing is bought;
  3. it shuts at night: the open panel closes and E won't open it;
  4. inside, nothing hurts you; outside it does.
]]
return function(h)
    player.god = true
    h.advance(10)
    local house = map.houseInstances[1]
    local function stand(x, y)
        player.body:setPosition(x, y)
        player.body:setLinearVelocity(0, 0)
        camera.snap(player)
        h.advance(2) -- the house notices you're in
    end

    daynight.setHour(12)
    stand(house.x, house.y + 20)
    h.check("inside the house counts as indoors", var.indoors == true)
    love.keypressed("e")
    h.check("by day, E at the counter opens the shop", shop.open)

    player.health = player.maxHealth / 2
    var.player_score = 100
    love.keypressed("1")
    h.check("1 buys a bandage for 40 XP", var.player_score == 60 and player.health > player.maxHealth / 2,
        string.format("%d XP, health %d", var.player_score, player.health))

    var.player_score = 10
    local health = player.health
    love.keypressed("2")
    h.check("without the XP, nothing's bought", var.player_score == 10 and player.health == health)

    daynight.setHour(22)
    h.advance(2)
    h.check("at night the panel closes", not shop.open)
    love.keypressed("e")
    h.check("and E won't open it", not shop.open)

    player.god = false
    player.health = player.maxHealth
    player.hurt(200)
    h.check("inside, nothing hurts you", player.health == player.maxHealth)
    stand(house.x - 200, house.y + 20)
    player.hurt(200)
    h.check("outside, it does", player.health < player.maxHealth,
        string.format("health %d", player.health))
    player.health = player.maxHealth
    player.god = true
    daynight.setHour(var.day_start)
end
