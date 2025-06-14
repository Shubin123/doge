-- Test script to check teleport functionality
print("Testing teleport command...")

-- Test the player proxy
if player then
    print("Player proxy exists")
    if player.body then
        print("Player body exists")
        print("Player position:", player.body:getX(), player.body:getY())
        
        -- Try teleporting
        player.body:setPosition(400, 300)
        print("Teleported to 400, 300")
    else
        print("Player body is nil")
    end
else
    print("Player proxy is nil")
end

-- Test modSystem
if modSystem then
    print("\nModSystem exists")
    local playerData = modSystem.getPlayerData()
    if playerData then
        print("Got player data:", playerData.x, playerData.y)
    else
        print("Player data is nil")
    end
else
    print("ModSystem is nil")
end