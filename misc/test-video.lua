-- videos download they dont play yet...
-- Video URL - change this to any video URL
VIDEO_URL = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4'

ffi = require("ffi")
curl = ffi.load("curl")

gameState = {
    video = nil,
    videoSource = nil,
    isDownloading = false,
    errorMessage = nil,
    downloadComplete = false,
    isPaused = false
}

_VIDEO_PATH = 'downloaded_video.mp4'
WINDOW_WIDTH = 800
WINDOW_HEIGHT = 600

-- Define curl structures and functions
ffi.cdef[[
    typedef void CURL;
    typedef int CURLcode;
    typedef int CURLoption;
    
    typedef struct {
        char *memory;
        size_t size;
    } MemoryStruct;
    
    typedef size_t (*curl_write_callback)(char *ptr, size_t size, size_t nmemb, void *userdata);
    
    CURL *curl_easy_init(void);
    CURLcode curl_easy_setopt(CURL *curl, CURLoption option, ...);
    CURLcode curl_easy_perform(CURL *curl);
    void curl_easy_cleanup(CURL *curl);
    CURLcode curl_easy_getinfo(CURL *curl, int info, ...);
    char *curl_easy_strerror(CURLcode errornum);
    
    void *malloc(size_t size);
    void *realloc(void *ptr, size_t size);
    void free(void *ptr);
    void *memcpy(void *dest, const void *src, size_t n);
]]

-- cURL constants
local CURLOPT_URL = 10002
local CURLOPT_WRITEFUNCTION = 20011
local CURLOPT_WRITEDATA = 10001
local CURLOPT_USERAGENT = 10018
local CURLOPT_FOLLOWLOCATION = 52
local CURLOPT_MAXREDIRS = 68
local CURLOPT_REFERER = 10016
local CURLOPT_SSL_VERIFYPEER = 64
local CURLOPT_SSL_VERIFYHOST = 81
local CURLOPT_TIMEOUT = 120  -- Increased timeout for video downloads
local CURLOPT_CONNECTTIMEOUT = 30
local CURLOPT_PROGRESSFUNCTION = 20056
local CURLOPT_PROGRESSDATA = 10057
local CURLOPT_NOPROGRESS = 43

local CURLINFO_RESPONSE_CODE = 2097154
local CURLE_OK = 0

-- Progress tracking
local downloadProgress = {
    totalBytes = 0,
    downloadedBytes = 0,
    percentage = 0
}

-- Memory structure for storing downloaded data
local MemoryStruct = ffi.metatype("MemoryStruct", {})

-- Write callback function
local function WriteMemoryCallback(contents, size, nmemb, userp)
    local realsize = size * nmemb
    local mem = ffi.cast("MemoryStruct*", userp)
    
    local ptr = ffi.C.realloc(mem.memory, mem.size + realsize + 1)
    if ptr == nil then
        print("Not enough memory (realloc returned NULL)")
        return 0
    end
    
    mem.memory = ffi.cast("char*", ptr)
    ffi.C.memcpy(mem.memory + mem.size, contents, realsize)
    mem.size = mem.size + realsize
    mem.memory[mem.size] = 0
    
    return realsize
end

-- Progress callback function
local function ProgressCallback(userp, dltotal, dlnow, ultotal, ulnow)
    if dltotal > 0 then
        downloadProgress.totalBytes = tonumber(dltotal)
        downloadProgress.downloadedBytes = tonumber(dlnow)
        downloadProgress.percentage = (dlnow / dltotal) * 100
        
        if downloadProgress.percentage % 10 < 1 then  -- Print every 10%
            print(string.format("Download progress: %.1f%% (%d/%d bytes)", 
                downloadProgress.percentage, downloadProgress.downloadedBytes, downloadProgress.totalBytes))
        end
    end
    return 0
end

-- Convert Lua callbacks to C callbacks
local write_callback = ffi.cast("curl_write_callback", WriteMemoryCallback)
local progress_callback = ffi.cast("int(*)(void*, double, double, double, double)", ProgressCallback)

function downloadVideo()
    local url = VIDEO_URL
    
    gameState.isDownloading = true
    gameState.errorMessage = nil
    downloadProgress.totalBytes = 0
    downloadProgress.downloadedBytes = 0
    downloadProgress.percentage = 0
    
    -- Initialize curl
    local curl_handle = curl.curl_easy_init()
    if curl_handle == nil then
        gameState.isDownloading = false
        gameState.errorMessage = 'Failed to initialize curl'
        return
    end
    
    -- Initialize memory struct
    local chunk = ffi.new("MemoryStruct")
    chunk.memory = ffi.cast("char*", ffi.C.malloc(1))
    chunk.size = 0
    
    print('Downloading video from: ' .. url)
    
    -- Set curl options
    curl.curl_easy_setopt(curl_handle, CURLOPT_URL, url)
    curl.curl_easy_setopt(curl_handle, CURLOPT_WRITEFUNCTION, write_callback)
    curl.curl_easy_setopt(curl_handle, CURLOPT_WRITEDATA, chunk)
    curl.curl_easy_setopt(curl_handle, CURLOPT_USERAGENT, 
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/113.0.0.0 Safari/537.36")
    curl.curl_easy_setopt(curl_handle, CURLOPT_FOLLOWLOCATION, 1)
    curl.curl_easy_setopt(curl_handle, CURLOPT_MAXREDIRS, 5)
    curl.curl_easy_setopt(curl_handle, CURLOPT_REFERER, "https://www.google.com/")
    curl.curl_easy_setopt(curl_handle, CURLOPT_SSL_VERIFYPEER, 1)
    curl.curl_easy_setopt(curl_handle, CURLOPT_SSL_VERIFYHOST, 2)
    curl.curl_easy_setopt(curl_handle, CURLOPT_TIMEOUT, 120)  -- 2 minutes for video
    curl.curl_easy_setopt(curl_handle, CURLOPT_CONNECTTIMEOUT, 30)
    curl.curl_easy_setopt(curl_handle, CURLOPT_NOPROGRESS, 0)  -- Enable progress
    curl.curl_easy_setopt(curl_handle, CURLOPT_PROGRESSFUNCTION, progress_callback)
    
    -- Perform the request
    local res = curl.curl_easy_perform(curl_handle)
    
    if res ~= CURLE_OK then
        local error_str = ffi.string(curl.curl_easy_strerror(res))
        print('curl_easy_perform() failed: ' .. error_str)
        gameState.isDownloading = false
        gameState.errorMessage = 'Download failed: ' .. error_str
        
        -- Cleanup
        ffi.C.free(chunk.memory)
        curl.curl_easy_cleanup(curl_handle)
        return
    end
    
    -- Get response code
    local response_code = ffi.new("long[1]")
    curl.curl_easy_getinfo(curl_handle, CURLINFO_RESPONSE_CODE, response_code)
    
    print('HTTP Status: ' .. tonumber(response_code[0]))
    
    if tonumber(response_code[0]) == 200 then
        if chunk.size > 0 then
            -- Convert the downloaded data to a Lua string
            local video_data = ffi.string(chunk.memory, chunk.size)
            -- print('Downloaded ' .. chunk.size .. ' bytes')
            
            -- Write to file
            local success = love.filesystem.write(_VIDEO_PATH, video_data)
            if success then
                gameState.isDownloading = false
                gameState.downloadComplete = true
                loadVideo()
            else
                gameState.isDownloading = false
                gameState.errorMessage = 'Failed to write video file'
            end
        else
            gameState.isDownloading = false
            gameState.errorMessage = 'Downloaded file is empty'
        end
    else
        gameState.isDownloading = false
        gameState.errorMessage = 'HTTP request failed (Status: ' .. tonumber(response_code[0]) .. ')'
    end
    
    -- Cleanup
    ffi.C.free(chunk.memory)
    curl.curl_easy_cleanup(curl_handle)
end

function loadVideo()
    local success, result = pcall(love.graphics.newVideoStream, _VIDEO_PATH)
    if success and result then
        gameState.videoSource = result
        gameState.video = love.graphics.newVideo(gameState.videoSource)
        gameState.errorMessage = nil
        gameState.isPaused = false
        print('Video loaded successfully!')
        print('Video dimensions: ' .. gameState.video:getWidth() .. 'x' .. gameState.video:getHeight())
        print('Video duration: ' .. string.format("%.2f", gameState.videoSource:getDuration()) .. ' seconds')
        
        -- Start playing the video
        gameState.video:play()
    else
        gameState.errorMessage = 'Failed to load video file: ' .. tostring(result)
        print('Error loading video:', result)
    end
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "d" and not gameState.isDownloading then
        downloadVideo()
    elseif key == "space" and gameState.video then
        -- Toggle play/pause
        if gameState.video:isPlaying() then
            gameState.video:pause()
            gameState.isPaused = true
        else
            gameState.video:play()
            gameState.isPaused = false
        end
    elseif key == "r" and gameState.video then
        -- Restart video
        gameState.video:rewind()
        gameState.video:play()
        gameState.isPaused = false
    end
end

function love.draw()
    love.graphics.setBackgroundColor(0.1, 0.1, 0.1)
    
    -- Draw video if available
    if gameState.video then
        local videoWidth = gameState.video:getWidth()
        local videoHeight = gameState.video:getHeight()
        local scaleX = WINDOW_WIDTH / videoWidth
        local scaleY = WINDOW_HEIGHT / videoHeight
        local scale = math.min(scaleX, scaleY)
        local drawWidth = videoWidth * scale
        local drawHeight = videoHeight * scale
        local drawX = (WINDOW_WIDTH - drawWidth) / 2
        local drawY = (WINDOW_HEIGHT - drawHeight) / 2
        
        love.graphics.draw(gameState.video, drawX, drawY, 0, scale, scale)
        
        -- Draw video controls overlay
        if gameState.isPaused then
            love.graphics.setColor(1, 1, 1, 0.8)
            love.graphics.rectangle("fill", drawX + drawWidth/2 - 30, drawY + drawHeight/2 - 30, 60, 60)
            love.graphics.setColor(0, 0, 0)
            -- Draw play triangle
            love.graphics.polygon("fill", 
                drawX + drawWidth/2 - 10, drawY + drawHeight/2 - 15,
                drawX + drawWidth/2 - 10, drawY + drawHeight/2 + 15,
                drawX + drawWidth/2 + 15, drawY + drawHeight/2)
            love.graphics.setColor(1, 1, 1)
        end
    end
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(love.graphics.getFont())
    local yOffset = 10
    
    -- Status messages
    if gameState.isDownloading then
        love.graphics.print('Downloading video...', 10, yOffset)
        yOffset = yOffset + 25
        if downloadProgress.totalBytes > 0 then
            local progressText = string.format("Progress: %.1f%% (%.1f MB / %.1f MB)", 
                downloadProgress.percentage, 
                downloadProgress.downloadedBytes / 1024 / 1024,
                downloadProgress.totalBytes / 1024 / 1024)
            love.graphics.print(progressText, 10, yOffset)
            yOffset = yOffset + 25
            
            -- Progress bar
            local barWidth = 300
            local barHeight = 20
            love.graphics.setColor(0.3, 0.3, 0.3)
            love.graphics.rectangle("fill", 10, yOffset, barWidth, barHeight)
            love.graphics.setColor(0.2, 0.8, 0.2)
            love.graphics.rectangle("fill", 10, yOffset, (downloadProgress.percentage / 100) * barWidth, barHeight)
            love.graphics.setColor(1, 1, 1)
            yOffset = yOffset + 30
        end
    elseif gameState.downloadComplete and not gameState.video then
        love.graphics.print('Download complete. Loading video...', 10, yOffset)
        yOffset = yOffset + 25
    elseif gameState.video then
        local status = gameState.isPaused and "PAUSED" or "PLAYING"
        love.graphics.print('Video loaded successfully! Status: ' .. status, 10, yOffset)
        yOffset = yOffset + 25
    end
    
    -- Error messages
    if gameState.errorMessage then
        love.graphics.setColor(1, 0.5, 0.5)
        love.graphics.print('Error: ' .. gameState.errorMessage, 10, yOffset)
        yOffset = yOffset + 25
        love.graphics.setColor(1, 1, 1)
    end
    
    -- Controls
    if not gameState.isDownloading then
        love.graphics.print('Controls:', 10, yOffset + 20)
        love.graphics.print('D - Download new video', 10, yOffset + 40)
        if gameState.video then
            love.graphics.print('SPACE - Play/Pause', 10, yOffset + 60)
            love.graphics.print('R - Restart video', 10, yOffset + 80)
            love.graphics.print('ESC - Quit', 10, yOffset + 100)
        else
            love.graphics.print('ESC - Quit', 10, yOffset + 60)
        end
    end
    
    -- Video info
    if gameState.video and gameState.videoSource then
        local currentTime = gameState.videoSource:tell()
        local totalTime = gameState.videoSource:getDuration()
        local timeInfo = string.format('Time: %.1f / %.1f seconds', currentTime, totalTime)
        local videoInfo = string.format('Video: %dx%d', gameState.video:getWidth(), gameState.video:getHeight())
        
        love.graphics.print(timeInfo, 10, WINDOW_HEIGHT - 70)
        love.graphics.print(videoInfo, 10, WINDOW_HEIGHT - 50)
    end
    
    love.graphics.print('URL: ' .. VIDEO_URL, 10, WINDOW_HEIGHT - 30)
end

function love.update(dt)
    -- Update video if playing
    if gameState.video and not gameState.isPaused then
        gameState.video:refresh()
    end
end

-- Start initial download
downloadVideo()