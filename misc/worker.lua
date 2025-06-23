-- main.lua
-- function love.load()
--     -- Define a global function in main thread
    
    
--     -- Print main thread function address
--     -- print("Main thread - globalTestFunction address:", globalTestFunction)
--     -- print("Main thread - globalTestFunction type:", type(globalTestFunction))
    
--     -- Create worker thread code as a string (inline)

    
--     -- Create thread from string

-- end
for k, v in pairs(_G) do
        print(k,v)
    end       
    thread = love.thread.newThread(
    [[
    for k, v in pairs(_G) do
        print(k,v)
    end       
    ]]
    )
    
    -- Start the thread
    print("Starting worker thread...")
    thread:start()

oldupdate = love.update
function love.update(dt)
    oldupdate(dt)
    -- Check if thread is still running
    if thread and not thread:isRunning() then
        local error = thread:getError()
        if error then
            print("Thread error:", error)
        else
            print("Thread completed successfully")
        end
        thread = nil -- Clean up
    end
end

olddraw = love.draw
function love.draw()
    olddraw()
    love.graphics.print("Check console for thread global access test results", 10, 10)
    if thread and thread:isRunning() then
        love.graphics.print("Thread is running...", 10, 30)
    else
        love.graphics.print("Thread finished", 10, 30)
    end
end

oldContact = beginContact
function beginContact(fixture_a, fixture_b, contact)
    -- oldContact(fixture_a, fixture_b, contact)
    -- map.collision(fixture_a, fixture_b, contact)
end