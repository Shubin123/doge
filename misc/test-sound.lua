-- main.lua
function love.load()
    -- Create a positional audio source
    audioFile = love.audio.newSource("monotest (1).mp3", "static")
    
    -- Check if the source is mono before setting position
    if audioFile:getChannelCount() == 1 then
        -- Set the source to use positional audio (only works with mono sources)
        audioFile:setPosition(100, 200, 0) -- x, y, z coordinates
    else
        print("Warning: Audio file is not mono. Positional audio disabled.")
        print("Channels detected: " .. audioFile:getChannelCount())
        -- For stereo files, you can still play them but without positional effects
    end
    
    -- Optional: Set volume rolloff for distance-based volume (only for mono)
    if audioFile:getChannelCount() == 1 then
        audioFile:setAttenuationDistances(50, 200) -- reference distance, max distance
        audioFile:setRolloff(1.0) -- rolloff factor (how quickly volume decreases)
    end
    
    -- Set listener position (usually the player/camera position)
    love.audio.setPosition(0, 0, 0)
    
    -- Optional: Set listener orientation
    love.audio.setOrientation(0, 0, -1, 0, 1, 0) -- forward vector, up vector
    print(love.audio.getDistanceModel( ))
    -- Player position for demonstration
    playerX, playerY = 0, 0
    
    -- Sound source position
    soundX, soundY = 100, 200
    
    -- Start playing the sound
    audioFile:setLooping(true)
    audioFile:play()
end

function love.update(dt)
    -- Update listener position based on player movement
    love.audio.setPosition(playerX, playerY, 0)
    
    -- Example: Move player with arrow keys
    if love.keyboard.isDown("left") then
        playerX = playerX - 100 * dt
    elseif love.keyboard.isDown("right") then
        playerX = playerX + 100 * dt
    end
    
    if love.keyboard.isDown("up") then
        playerY = playerY - 100 * dt
    elseif love.keyboard.isDown("down") then
        playerY = playerY + 100 * dt
    end
end

function love.draw()
    -- Draw player
    love.graphics.setColor(0, 1, 0) -- green
    love.graphics.circle("fill", playerX, playerY, 10)
    
    -- Draw sound source
    love.graphics.setColor(1, 0, 0) -- red
    love.graphics.circle("fill", soundX, soundY, 15)
    
    -- Reset color
    love.graphics.setColor(1, 1, 1)
    
    -- Display instructions
    love.graphics.print("Use arrow keys to move. Notice how the sound changes with distance!", 10, 10)
    love.graphics.print("Player position: " .. math.floor(playerX) .. ", " .. math.floor(playerY), 10, 30)
end

-- Alternative approach: Create multiple positioned sources with error checking
function createPositionalSource(x, y, soundFile)
    local source = love.audio.newSource(soundFile, "static")
    
    -- Only apply positional audio if the source is mono
    if source:getChannelCount() == 1 then
        source:setPosition(x, y, 0)
        source:setAttenuationDistances(30, 150)
        source:setRolloff(1.5)
        print("Created positional source at: " .. x .. ", " .. y)
    else
        print("Warning: " .. soundFile .. " is not mono. Playing as regular audio.")
    end
    
    return source
end

-- To convert stereo to mono in code (creates a new mono source):
function createMonoSource(stereoFile)
    -- This is a workaround - load the file and create a mono version
    local stereoSource = love.audio.newSource(stereoFile, "static")
    
    if stereoSource:getChannelCount() == 1 then
        return stereoSource -- Already mono
    else
        -- For stereo files, you'll need to use external tools to convert to mono
        -- or use separate mono audio files for positional audio
        print("File is stereo. Use audio editing software to convert to mono for positional audio.")
        return stereoSource -- Return as-is, but won't support positional audio
    end
end

-- Example usage:
-- local ambientSource = createPositionalSource(300, 400, "ambient.ogg")
-- ambientSource:setLooping(true)
-- ambientSource:play()