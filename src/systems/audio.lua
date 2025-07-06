local audio = {}

-- will hold the currently playing sources
local sources = {}

-- sound sources
local sounds = {

}

-- last play time for each sound type to manage fire rate syncing
local lastPlayTime

-- active sounds with their start and expected stop times
local activeSounds = {}

-- load sounds
function audio.loadSounds()
    sounds.gun1 = love.audio.newSource("/audio/gun1_trimmed.mp3", "static")
    sounds.gun3 = love.audio.newSource("/audio/gun1_trimmed.mp3", "static")
    sounds.gun2 = love.audio.newSource("/audio/gun3_trimmed.mp3", "static")
    sounds.gun4 = love.audio.newSource("/audio/gun3_trimmed2.mp3", "static")
    sounds.explosion = love.audio.newSource("/audio/explosion_trimmed.mp3", "static")
    sounds.fire = love.audio.newSource("/audio/fire.mp3", "static")
    sounds.coin = love.audio.newSource("/audio/coin.mp3", "static")
    
    -- Dynamically initialize lastPlayTime for all loaded sounds
    lastPlayTime = {}
    for soundType, _ in pairs(sounds) do
        lastPlayTime[soundType] = 0
    end
end

-- check for sources that finished playing and remove them
-- add to love.update
function love.audio.update()
    local remove = {}
    for _, s in pairs(sources) do
        if not s:isPlaying() then
            remove[#remove + 1] = s
        end
    end

    for i, s in ipairs(remove) do
        sources[s] = nil
    end
end

-- overwrite love.audio.play to create and register source if needed
local play = love.audio.play
function love.audio.play(what, how, loop)
    local src = what
    if type(what) ~= "userdata" or not what:typeOf("Source") then
        src = love.audio.newSource(what, how)
        src:setLooping(loop or false)
    end

    play(src)
    sources[src] = src
    return src
end

-- stops a source
local stop = love.audio.stop
function love.audio.stop(src)
    if not src then return end
    stop(src)
    sources[src] = nil
end

-- play a sound with an offset to sync with fire rate or other timing
function audio.playSound(soundType, offset, volume)
    local currentTime = love.timer.getTime()
    if currentTime - lastPlayTime[soundType] >= (offset or 0.1) then
        local sound = sounds[soundType]
        if sound then
            local src = sound:clone() --no clone will be played sequentially slow idk
            sources[src] = src
            -- Apply pitch and volume variations
            local pitchVariation = 0.9 + math.random() * 1.2  -- Random pitch between 90% and 110%
            src:setPitch(pitchVariation)
            
            -- Estimate duration (LÖVE doesn't provide direct duration access for static sources)
            -- Using approximate durations for each sound type (adjust based on actual audio files)
            -- local duration = 0.5 -- default duration
            -- if soundType == "gun1" then duration = 0.3
            -- elseif soundType == "gun2" then duration = 0.0002
            -- elseif soundType == "gun3" then duration = 0.4
            -- elseif soundType == "fire" then duration = 1.0
            -- elseif soundType == "coin" then duration = 0.3
            -- end
            -- activeSounds[src] = { startTime = currentTime, expectedStopTime = currentTime + duration }

            -- local volumeVariation = 0.8 + math.random() * 0.4 -- Random volume between 80% and 120%
            src:setVolume(volume or 1)
            love.audio.play(src)
            lastPlayTime[soundType] = currentTime
            return src
        end
    end
    return nil
end

return audio
