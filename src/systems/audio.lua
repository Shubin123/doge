-- audio.lua
-- Spatial SFX engine for the game.
--
-- Design goals (realism):
--   * Sounds are positioned in the world. Distance attenuates volume, horizontal
--     offset pans left/right, and distance/indoors muffles high frequencies.
--   * OpenAL only spatialises MONO sources, but all of our assets ship as stereo,
--     so each asset is down-mixed to mono once at load time. This is what makes
--     panning + distance falloff actually audible.
--   * Per-shot pitch/volume humanisation so repeated fire never sounds robotic.
--   * Voice limiting + an actual cleanup pass so finished sources don't leak.
--   * Master / per-category volume so the menu (or a future options screen) can
--     mix the game without touching every call site.

local audio = {}
local music = require("systems.music")

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

local AUDIO_DIR = "/audio/"

-- Per-sound definitions. `file` is relative to AUDIO_DIR. `volume` is the
-- emission gain before category/master mixing. `category` selects the volume
-- bus and the default attenuation profile. Optional `ref`/`max`/`rolloff`
-- override the category's spatial falloff.
local soundConfig = {
    gun1      = { file = "gun1_trimmed.mp3",      category = "weapon",    volume = 0.85 },
    gun2      = { file = "gun3_trimmed.mp3",      category = "weapon",    volume = 0.80 },
    gun3      = { file = "gun1_trimmed.mp3",      category = "weapon",    volume = 0.85 },
    gun4      = { file = "gun3_trimmed2.mp3",     category = "weapon",    volume = 0.75 },
    explosion = { file = "explosion_trimmed.mp3", category = "explosion", volume = 1.00 },
    fire      = { file = "fire.mp3",              category = "weapon",    volume = 0.70 },
    coin      = { file = "coin.mp3",              category = "pickup",    volume = 0.55 },
}

-- Attenuation profiles per category. Distances are in physics/world units
-- (same space as player/enemy bodies). `inverseclamped` gain:
--   gain = ref / (ref + rolloff * (clamp(d, ref, max) - ref))
local categoryProfile = {
    weapon    = { ref = 240, max = 2600, rolloff = 0.9 },
    explosion = { ref = 420, max = 4200, rolloff = 0.8 },
    pickup    = { ref = 200, max = 1500, rolloff = 1.0 },
    default   = { ref = 240, max = 2600, rolloff = 0.9 },
}

-- Volume buses. Final gain = base * category * master (* 0 when muted).
audio.volumes = {
    master    = 1.0,
    weapon    = 0.9,
    explosion = 1.0,
    pickup    = 1.0,
}
audio.muted = false

-- Humanisation + polyphony limits.
local VOLUME_JITTER   = 0.08  -- +/- per-trigger volume wobble
local MAX_VOICES_TYPE = 6     -- concurrent clones of a single sound
local MAX_VOICES_TOTAL = 28   -- concurrent clones across everything

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local sounds      = {}  -- soundType -> { source, mono(bool), category }
local lastPlayTime = {} -- soundType -> last trigger time (rate limiting)
local active      = {}  -- array of { src, type, t } currently-playing clones

local listenerX, listenerY = 0, 0

-- ---------------------------------------------------------------------------
-- Loading
-- ---------------------------------------------------------------------------

-- Down-mix a stereo SoundData to a fresh mono SoundData so OpenAL will
-- spatialise it. Returns nil on any failure so the caller can fall back to the
-- original (un-spatialised) stereo source.
local function toMono(soundData)
    local ok, mono = pcall(function()
        if soundData:getChannelCount() == 1 then
            return soundData
        end
        local frames = soundData:getSampleCount()
        local rate   = soundData:getSampleRate()
        local bits   = soundData:getBitDepth()
        local out    = love.sound.newSoundData(frames, rate, bits, 1)
        for i = 0, frames - 1 do
            out:setSample(i, (soundData:getSample(i, 1) + soundData:getSample(i, 2)) * 0.5)
        end
        return out
    end)
    if ok then return mono end
    return nil
end

local function loadOne(soundType, cfg)
    local path = AUDIO_DIR .. cfg.file
    -- Decode to SoundData first so we can down-mix to mono for spatialisation.
    local okData, data = pcall(love.sound.newSoundData, path)
    local source, isMono
    if okData and data then
        local mono = toMono(data)
        if mono then
            source = love.audio.newSource(mono, "static")
            isMono = true
        else
            source = love.audio.newSource(data, "static")
            isMono = false
        end
    else
        -- Last-ditch: stream straight from the file (no spatialisation).
        local okSrc, src = pcall(love.audio.newSource, path, "static")
        if not okSrc then
            print(("[audio] failed to load %s (%s)"):format(soundType, tostring(src)))
            return
        end
        source, isMono = src, false
    end

    sounds[soundType] = { source = source, mono = isMono, category = cfg.category }
    lastPlayTime[soundType] = 0
end

function audio.loadSounds()
    -- 2D arcade game: disable Doppler so positional motion never bends pitch.
    pcall(love.audio.setDistanceModel, "inverseclamped")
    pcall(love.audio.setDopplerScale, 0)

    sounds, lastPlayTime, active = {}, {}, {}
    for soundType, cfg in pairs(soundConfig) do
        loadOne(soundType, cfg)
    end
end

-- ---------------------------------------------------------------------------
-- Listener + per-frame maintenance
-- ---------------------------------------------------------------------------

-- Place the "ears" in the world. Call every frame with the player position.
function audio.setListener(x, y)
    listenerX, listenerY = x or 0, y or 0
    pcall(love.audio.setPosition, listenerX, listenerY, 0)
end

-- Prune finished clones so sources don't accumulate. Call from love.update.
function audio.update(dt)
    local kept = {}
    for i = 1, #active do
        local entry = active[i]
        if entry.src:isPlaying() then
            kept[#kept + 1] = entry
        end
    end
    active = kept
end

-- ---------------------------------------------------------------------------
-- Voice management
-- ---------------------------------------------------------------------------

local function reapForType(soundType)
    -- Stop the oldest clone of this type if we're at the per-type ceiling.
    local count, oldestIdx, oldestT = 0, nil, math.huge
    for i = 1, #active do
        if active[i].type == soundType then
            count = count + 1
            if active[i].t < oldestT then
                oldestT, oldestIdx = active[i].t, i
            end
        end
    end
    if count >= MAX_VOICES_TYPE and oldestIdx then
        active[oldestIdx].src:stop()
        table.remove(active, oldestIdx)
    end
    -- Global ceiling: drop the single oldest voice if we're over budget.
    if #active >= MAX_VOICES_TOTAL then
        local gi, gt = nil, math.huge
        for i = 1, #active do
            if active[i].t < gt then gt, gi = active[i].t, i end
        end
        if gi then
            active[gi].src:stop()
            table.remove(active, gi)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Playback
-- ---------------------------------------------------------------------------

local function categoryGain(category)
    local c = audio.volumes[category]
    return (c == nil) and 1.0 or c
end

local function profileFor(soundType, category)
    local cfg = soundConfig[soundType]
    local base = categoryProfile[category] or categoryProfile.default
    return {
        ref     = (cfg and cfg.ref)     or base.ref,
        max     = (cfg and cfg.max)     or base.max,
        rolloff = (cfg and cfg.rolloff) or base.rolloff,
    }
end

-- Muffle distant / indoor sounds with a low-pass filter for realism.
local function applyMuffle(src, dist, prof)
    local r = 0
    if prof and prof.max > prof.ref then
        r = (dist - prof.ref) / (prof.max - prof.ref)
        if r < 0 then r = 0 elseif r > 1 then r = 1 end
    end
    local highgain = 1.0 - 0.7 * r
    if var and var.indoors then
        highgain = highgain * 0.6  -- muffled when the listener is inside
    end
    if highgain < 0.985 then
        pcall(src.setFilter, src, { type = "lowpass", volume = 1.0, highgain = highgain })
    else
        pcall(src.setFilter, src, false)
    end
end

-- Core trigger. opts:
--   x, y        world position (positional sounds)
--   positional  true -> spatialise at (x,y); false -> centred 2D
--   offset      minimum seconds between triggers of this type (rate limit)
--   volume      caller volume multiplier (defaults to 1)
local function trigger(soundType, opts)
    local entry = sounds[soundType]
    if not entry then return nil end

    local now = love.timer.getTime()
    local offset = opts.offset or 0.1
    if now - (lastPlayTime[soundType] or 0) < offset then
        return nil
    end

    reapForType(soundType)

    local src = entry.source:clone()

    -- Pitch: musical pattern / humanised variation from music.lua.
    src:setPitch(music.getNextPitch(soundType))

    -- Volume: base * caller * category * master, with a touch of jitter.
    local cfg     = soundConfig[soundType]
    local baseVol = (cfg and cfg.volume) or 1.0
    local jitter  = 1.0 + (love.math.random() * 2 - 1) * VOLUME_JITTER
    local gain    = baseVol * (opts.volume or 1.0)
                    * categoryGain(entry.category) * audio.volumes.master
                    * jitter
    if audio.muted then gain = 0 end
    if gain < 0 then gain = 0 end

    if opts.positional and entry.mono then
        local x, y = opts.x or listenerX, opts.y or listenerY
        local prof = profileFor(soundType, entry.category)
        src:setRelative(false)
        src:setPosition(x, y, 0)
        pcall(src.setAttenuationDistances, src, prof.ref, prof.max)
        pcall(src.setRolloff, src, prof.rolloff)
        local dx, dy = x - listenerX, y - listenerY
        applyMuffle(src, math.sqrt(dx * dx + dy * dy), prof)
        src:setVolume(gain)
    elseif opts.positional then
        -- Stereo fallback: no panning, approximate distance attenuation by hand.
        local x, y = opts.x or listenerX, opts.y or listenerY
        local prof = profileFor(soundType, entry.category)
        local dx, dy = x - listenerX, y - listenerY
        local d = math.sqrt(dx * dx + dy * dy)
        if d < prof.ref then d = prof.ref elseif d > prof.max then d = prof.max end
        local atten = prof.ref / (prof.ref + prof.rolloff * (d - prof.ref))
        src:setVolume(gain * atten)
    else
        -- Centred 2D (e.g. the player's own gun): glued to the listener.
        src:setRelative(true)
        src:setPosition(0, 0, 0)
        src:setVolume(gain)
    end

    src:play()
    active[#active + 1] = { src = src, type = soundType, t = now }
    lastPlayTime[soundType] = now
    return src
end

-- Backwards-compatible: centred, non-positional playback.
-- audio.playSound(type, offset, volume)
function audio.playSound(soundType, offset, volume)
    return trigger(soundType, { positional = false, offset = offset, volume = volume })
end

-- Positional playback at a world coordinate.
-- audio.playSoundAt(type, x, y, offset, volume)
function audio.playSoundAt(soundType, x, y, offset, volume)
    return trigger(soundType, { positional = true, x = x, y = y, offset = offset, volume = volume })
end

-- ---------------------------------------------------------------------------
-- Mixer controls
-- ---------------------------------------------------------------------------

function audio.setMasterVolume(v)
    audio.volumes.master = math.max(0, math.min(1, v or 1))
end

function audio.setCategoryVolume(category, v)
    audio.volumes[category] = math.max(0, math.min(1, v or 1))
end

function audio.setMuted(m)
    audio.muted = m and true or false
end

-- Immediately silence every active voice (e.g. when entering the menu).
function audio.stopAll()
    for i = 1, #active do
        pcall(active[i].src.stop, active[i].src)
    end
    active = {}
end

return audio
