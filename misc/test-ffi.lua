

-- local ffi = require 'ffi'

-- -- ffi.cdef 'void exit(int)'
-- ffi.cdef[[
-- void exit(int);
-- int MessageBoxA(void *w, const char *txt, const char *cap, int type); 
-- void Sleep(int ms);
-- int poll(struct pollfd *fds, unsigned long nfds, int timeout);

-- ]]


-- -- function love.draw()
-- -- 	love.graphics.print("Press a key", 50, 50)
-- -- end


-- -- function love.keypressed()
-- -- 	-- ffi.C.exit(666)
-- --     -- ffi.C.MessageBoxA(nil, "Hello world!", "Test", 0) -- windows/wine only

-- -- 	-- ffi.C.exit(666)
-- -- end



-- local sleep
-- if ffi.os == "Windows" then
--   function sleep(s)
--     ffi.C.Sleep(s*1000)
--   end
-- else
--   function sleep(s)
--     ffi.C.poll(nil, 0, s*1000)
--   end
-- end

-- for i=1,160 do
--   io.write("."); io.flush()
--   sleep(0.01)
-- end
-- io.write("\n")



-- local ffi = require("ffi")

-- ffi.cdef[[
-- typedef unsigned long pthread_t;
-- typedef union {
--   char __size[56];
--   long int __align;
-- } pthread_attr_t;

-- typedef void* (*start_routine)(void*);
-- int pthread_create(pthread_t *thread, const pthread_attr_t *attr, start_routine start, void *arg);
-- int pthread_join(pthread_t thread, void **retval);
-- void* malloc(size_t size);
-- void free(void *ptr);
-- unsigned int sleep(unsigned int seconds);
-- ]]

-- local C = ffi.C

-- -- Create malloc'd int to pass to thread
-- local function alloc_id(value)
--     local p = ffi.cast("int*", C.malloc(4))
--     p[0] = value
--     return p
-- end

-- -- Wrap thread function safely
-- local function make_thread(func)
--     return ffi.cast("start_routine", function(arg)
--         local id = ffi.cast("int*", arg)[0]
--         for i = 1, 3 do
--             io.write("Thread ", id, ": ", i, "\n")
--             C.sleep(1)
--         end
--         return nil
--     end)
-- end

-- local t1 = ffi.new("pthread_t[1]")
-- local t2 = ffi.new("pthread_t[1]")
-- local id1 = alloc_id(1)
-- local id2 = alloc_id(2)

-- local cb1 = make_thread()
-- local cb2 = make_thread()

-- C.pthread_create(t1, nil, cb1, id1)
-- C.pthread_create(t2, nil, cb2, id2)

-- C.pthread_join(t1[0], nil)
-- C.pthread_join(t2[0], nil)

-- cb1:free()
-- cb2:free()
-- C.free(id1)
-- C.free(id2)



-- local ffi = require("ffi")
-- ffi.cdef[[
-- unsigned long compressBound(unsigned long sourceLen);
-- int compress2(uint8_t *dest, unsigned long *destLen,
-- 	      const uint8_t *source, unsigned long sourceLen, int level);
-- int uncompress(uint8_t *dest, unsigned long *destLen,
-- 	       const uint8_t *source, unsigned long sourceLen);
-- ]]
-- local zlib = ffi.load(ffi.os == "Windows" and "zlib1" or "z")

-- local function compress(txt)
--   local n = zlib.compressBound(#txt)
--   local buf = ffi.new("uint8_t[?]", n)
--   local buflen = ffi.new("unsigned long[1]", n)
--   local res = zlib.compress2(buf, buflen, txt, #txt, 9)
--   assert(res == 0)
--   return ffi.string(buf, buflen[0])
-- end

-- local function uncompress(comp, n)
--   local buf = ffi.new("uint8_t[?]", n)
--   local buflen = ffi.new("unsigned long[1]", n)
--   local res = zlib.uncompress(buf, buflen, comp, #comp)
--   assert(res == 0)
--   return ffi.string(buf, buflen[0])
-- end




-- Simple test code.
-- local txt = string.rep("abcd", 10000)


-- print("Uncompressed size: ", #txt)


-- local c = compress(txt)
-- print("ffi Compressed size: ", #c)
-- local txt2 = uncompress(c, #txt)
-- assert(txt2 == txt) -- test uncompressed is same as pre-compressed (test is in single thread)
-- print("original is smaller by: ".. (#txt/#c)*100 .."%")


-- local lc = love.data.compress("string", "zlib", txt, 9)
-- local lc2 = love.data.compress("string", "zlib", txt, 9)
-- -- print("love compression size: ", #lc)
-- local txt3 = love.data.decompress("string", "zlib",lc)
-- assert(txt3 == txt)
-- assert(lc == c)

-- turns out love's builtin is faster in most circumstances so no need.





local threadCode = [[
-- Receive values sent via thread:start
local min, max = ...

for i = min, max do
    -- The Channel is used to handle communication between our main thread and
    -- this thread. On each iteration of the loop will push a message to it which
    -- we can then pop / receive in the main thread.
    love.thread.getChannel( 'info' ):push( i )
end
]]

local thread -- Our thread object.
local timer = 0  -- A timer used to animate our circle.

function love.load()
    thread = love.thread.newThread( threadCode )
    thread:start( 99, 1000 )
end

function love.update( dt )
    timer = timer + dt
end

function love.draw()
    -- Get the info channel and pop the next message from it.
    local info = love.thread.getChannel( 'info' ):pop()
    if info then
        love.graphics.print( info, 10, 10 )
    end

    -- We smoothly animate a circle to show that the thread isn't blocking our main thread.
    love.graphics.circle( 'line', 100 + math.sin( timer ) * 20, 100 + math.cos( timer ) * 20, 20 )
end