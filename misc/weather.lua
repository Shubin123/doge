-- Weather function for LÖVE game engine using threading
-- Requires luasocket and json libraries

local weather = {}
weather.activeThreads = {}
weather.results = {}

-- Weather code mapping
local weather_codes = {
    [0] = "Clear sky",
    [1] = "Mainly clear", 
    [2] = "Partly cloudy",
    [3] = "Overcast",
    [45] = "Fog",
    [48] = "Depositing rime fog",
    [51] = "Light drizzle",
    [53] = "Moderate drizzle", 
    [55] = "Dense drizzle",
    [61] = "Slight rain",
    [63] = "Moderate rain",
    [65] = "Heavy rain",
    [71] = "Slight snow",
    [73] = "Moderate snow",
    [75] = "Heavy snow",
    [80] = "Slight rain showers",
    [81] = "Moderate rain showers",
    [82] = "Violent rain showers",
    [95] = "Thunderstorm"
}

-- Thread code as a string
local threadCode = [[
require "love.timer"
local http = require("socket.http")
local json = require("src.json")

local lat, lon, city, threadId = ...

-- Build URL
local url = "https://api.open-meteo.com/v1/forecast?latitude=" .. lat .. 
           "&longitude=" .. lon .. 
           "&current=temperature_2m,wind_speed_10m,relative_humidity_2m,weather_code" ..
           "&hourly=temperature_2m,relative_humidity_2m,wind_speed_10m&timezone=auto"

-- Make HTTP request
local response, status = http.request(url)

local result = {
    threadId = threadId,
    city = city,
    success = false,
    error = nil,
    data = nil
}

if status == 200 and response then
    local success, data = pcall(json.decode, response)
    if success and data and data.current then
        result.success = true
        result.data = data
    else
        result.error = "Invalid API response or JSON parsing failed"
    end
else
    result.error = "HTTP request failed (status: " .. tostring(status) .. ")"
end

-- Send result back to main thread
love.thread.getChannel("weather_results"):push(result)
]]

-- Create and start weather request thread
function weather.request(lat, lon, city, callback)
    lat = lat or 52.52
    lon = lon or 13.41
    city = city or "Berlin"
    
    -- Create unique thread ID
    local threadId = tostring(love.timer.getTime())
    
    -- Create thread
    local thread = love.thread.newThread(threadCode)
    
    -- Store thread and callback
    weather.activeThreads[threadId] = {
        thread = thread,
        callback = callback
    }
    
    -- Start thread with parameters
    thread:start(lat, lon, city, threadId)
    
    return threadId
end

-- Process weather data and display results
function weather.processResult(result)
    if not result.success then
        -- command.addOutput("Weather Error: " .. result.error, {1, 0.3, 0.3, 1})
        return
    end
    
    local data = result.data
    local temp = math.floor(data.current.temperature_2m + 0.5)
    local wind = math.floor(data.current.wind_speed_10m + 0.5)
    local humidity = data.current.relative_humidity_2m or "N/A"
    local condition = weather_codes[data.current.weather_code] or "Unknown"
    
    -- Display weather information
    command.addOutput("=== WEATHER: " .. result.city .. " ===", {0, 1, 1, 1})
    command.addOutput("🌡️  " .. temp .. "°C (" .. condition .. ")", {0.8, 1, 0.8, 1})
    command.addOutput("💧 " .. humidity .. "% | 💨 " .. wind .. " km/h", {0.8, 0.8, 1, 1})
    -- print(temp..condition..humidity..wind)
    -- Show next 6 hours forecast
    if data.hourly and data.hourly.temperature_2m then
        local next_temps = {}
        for i = 1, math.min(6, #data.hourly.temperature_2m) do
            table.insert(next_temps, math.floor(data.hourly.temperature_2m[i] + 0.5) .. "°")
        end
        -- command.addOutput("Next 6h: " .. table.concat(next_temps, " "), {0.7, 0.9, 1, 1})
    end
end

-- Update function - call this in your main update loop
og = love.update

function weather.update()
    local channel = love.thread.getChannel("weather_results")
    local result = channel:pop()
    
    while result do
        local threadData = weather.activeThreads[result.threadId]
        if threadData then
            -- Process the result
            if threadData.callback then
                threadData.callback(result)
            else
                weather.processResult(result)
            end
            
            -- Clean up thread
            threadData.thread:wait()
            weather.activeThreads[result.threadId] = nil
        end
        
        -- Check for more results
        result = channel:pop()
    end
end

function love.update(dt) og(dt); weather.update() end
-- function love.update(dt)
--     weather.update()
-- end

-- Main weather function that maintains the same interface as original
function weather.get(lat, lon, city, callback)
    -- Check if luasocket is available
    local http_available = pcall(require, "socket.http")
    -- if not http_available then
    --     require("command").addOutput("Weather Error: HTTP library not available", {1, 0.3, 0.3, 1})
    --     return
    -- end
    
    -- -- Check if json library is available
    -- local json_available = pcall(require, "json")
    -- if not json_available then
    --     require("command").addOutput("Weather Error: JSON library not available", {1, 0.3, 0.3, 1})
    --     return
    -- end
    
    -- Start the weather request
    weather.request(lat, lon, city, callback)
end

-- Convenience function with the same name as original
function weather_func(lat, lon, city)
    weather.get(lat, lon, city)
end

-- debug.debug()

return weather