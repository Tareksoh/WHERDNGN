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
--
-- Re-audit W19 fix: the previous "string == voice, number == SFX"
-- heuristic was wrong — most of our SFX are bundled .ogg paths
-- (SND_TURN_PING, SND_CARD_PLAY, SND_BALOOT, ...) which are strings
-- but are SHORT effects, not 0.6s voice lines. Routing them all
-- through the 0.80s VOICE gate suppressed BALOOT fanfares and rapid
-- card plays. Look up the interval per known voice cue instead;
-- fall back to SFX_INTERVAL for everything else.
local lastFire = {}
local SFX_INTERVAL   = 0.10
local VOICE_INTERVAL = 0.80
local VOICE_PATHS = nil  -- lazily built from K.SND_VOICE_*

local function intervalFor(soundId)
    if type(soundId) ~= "string" then return SFX_INTERVAL end
    if not VOICE_PATHS then
        VOICE_PATHS = {}
        local K = B.K
        if K then
            -- Every K.SND_VOICE_* is a voice line; everything else
            -- (SND_TURN_PING, SND_CARD_PLAY, SND_CARD_SWISH,
            --  SND_CONTRACT, SND_TRICK_WON, SND_BALOOT) is SFX.
            for k, v in pairs(K) do
                if type(k) == "string" and k:sub(1, 10) == "SND_VOICE_"
                   and type(v) == "string" then
                    VOICE_PATHS[v] = true
                end
            end
        end
    end
    if VOICE_PATHS[soundId] then return VOICE_INTERVAL end
    return SFX_INTERVAL
end

function M.Cue(soundId)
    if not soundId or not enabled() then return end
    local now = GetTime and GetTime() or 0
    local last = lastFire[soundId] or 0
    local minInterval = intervalFor(soundId)
    if now - last < minInterval then return end
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
