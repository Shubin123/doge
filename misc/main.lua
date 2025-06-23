-- main.lua
function love.load()
    -- Define a global function in main thread
    globalTestFunction = function()
        return "Hello from global function"
    end
    
    -- Print main thread function address
    print("Main thread - globalTestFunction address:", globalTestFunction)
    print("Main thread - globalTestFunction type:", type(globalTestFunction))
    
    -- Create worker thread code as a string (inline)
    local workerCode = [[
        -- Worker thread code
        print("Worker thread started")
        print("Worker thread - globalTestFunction:", globalTestFunction)
        print("Worker thread - globalTestFunction type:", type(globalTestFunction))
        
        if globalTestFunction then
            print("Worker thread - Function address:", globalTestFunction)
            -- Try to call it
            local success, result = pcall(globalTestFunction)
            if success then
                print("Worker thread - Function call result:", result)
            else
                print("Worker thread - Function call failed:", result)
            end
        else
            print("Worker thread - globalTestFunction is nil")
        end
        
        -- Check if we can access _G
        print("Worker thread - _G available:", _G ~= nil)
        
        -- Try to access some other globals
        print("Worker thread - print function:", print)
        print("Worker thread - type function:", type)
        
        -- Try to access love module
        print("Worker thread - love module:", love)
        if love then
            print("Worker thread - love.thread:", love.thread)
        end
        
        print("Worker thread finished")
    ]]
    
    -- Create thread from string
    thread = love.thread.newThread(workerCode)
    
    -- Start the thread
    print("Starting worker thread...")
    thread:start()
end

function love.update(dt)
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

function love.draw()
    love.graphics.print("Check console for thread global access test results", 10, 10)
    if thread and thread:isRunning() then
        love.graphics.print("Thread is running...", 10, 30)
    else
        love.graphics.print("Thread finished", 10, 30)
    end
end