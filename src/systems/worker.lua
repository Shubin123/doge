-- worker.lua
-- Worker thread for collision checking in LÖVE

-- Function to process collision data
local function processCollision(fixtureDataA, fixtureDataB, contactData)
    local result = {
        handled = false,
        action = "none"
    }
    
    -- Example: Simple collision response (this should be expanded based on game logic)
    if fixtureDataA.groupIndex == -1 and fixtureDataB.groupIndex == -777 then
        -- Player vs Enemy collision
        result.handled = true
        result.action = "player_hit_enemy"
    elseif fixtureDataA.groupIndex == -2 and fixtureDataB.groupIndex == -777 then
        -- Bullet vs Enemy collision
        result.handled = true
        result.action = "bullet_hit_enemy"
    end
    
    return result
end

-- Main worker loop
while true do
    -- Wait for data from the main thread
    local dataBatch = love.thread.getChannel("collision_data"):demand()
    
    if dataBatch then
        -- Process each collision event in the batch
        for _, event in ipairs(dataBatch) do
            local fixtureDataA = event.data.fixtureA
            local fixtureDataB = event.data.fixtureB
            local contactData = event.data.contact
            
            -- Process collision
            local result = processCollision(fixtureDataA, fixtureDataB, contactData)
            
            -- Attach original fixtures and contact for callback in main thread
            result.fixture_a = event.fixture_a
            result.fixture_b = event.fixture_b
            result.contact = event.contact
            
            -- Send result back to main thread
            love.thread.getChannel("collision_result"):push(result)
        end
    end
end
