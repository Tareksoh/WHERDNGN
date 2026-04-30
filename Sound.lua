-- Tiny sound dispatcher. Wraps PlaySoundFile so the rest of the addon
-- doesn't pepper itself with platform-specific calls and so a future
-- settings panel can toggle audio with a single flag.
--
-- Sound IDs themselves live in Constants.lua (K.SND_*).
-- All cues route through "Master" channel so they respect the WoW
-- master-sound slider, not the music-only or dialog-only sliders.

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
B.Sound = B.Sound or {}
local M = B.Sound

-- Returns true if sound is enabled in this session. Default = on.
local function enabled()
    if not WHEREDNGNDB then return true end
    if WHEREDNGNDB.sound == false then return false end
    return true
end

-- Throttle identical cues so a flurry of rapid trick-end sounds (or
-- a debug double-fire) doesn't stack into one harsh blast.
local lastFire = {}
local MIN_INTERVAL = 0.10  -- 100ms is below the threshold of human hearing as separate events

function M.Cue(soundId)
    if not soundId or not enabled() then return end
    local now = GetTime and GetTime() or 0
    local last = lastFire[soundId] or 0
    if now - last < MIN_INTERVAL then return end
    lastFire[soundId] = now
    -- Numeric IDs in WoW's UI sound space are SoundKit IDs and must go
    -- through PlaySound, NOT PlaySoundFile (which expects a path or a
    -- FileDataID and will fail silently for SoundKit IDs). Strings
    -- (paths to .ogg/.mp3) are routed to PlaySoundFile when available.
    if type(soundId) == "number" then
        if PlaySound then
            pcall(PlaySound, soundId, "Master")
        end
    else
        if PlaySoundFile then
            pcall(PlaySoundFile, soundId, "Master")
        end
    end
end
