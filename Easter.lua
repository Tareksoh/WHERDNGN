-- Easter.lua — hidden Easter egg trigger for specific player names.
--
-- ============================================================
-- TO REMOVE THIS FEATURE COMPLETELY:
--   1. Delete this file (Easter.lua)
--   2. Remove the line `Easter.lua` from WHEREDNGN.toc
--   That's it. No other file references this module — the hook
--   into N.LocalSkipDouble is wrapped from INSIDE this file at
--   load time, so deleting the file fully removes the behavior.
--
-- TO TEMPORARILY DISABLE WITHOUT DELETING:
--   Set EASTER_ENABLED below to false. Re-enable by setting true.
--
-- TO ADD/REMOVE TARGETED PLAYERS:
--   Edit the TARGETS list below.
--
-- TO REPLACE THE PHOTO OR SOUND:
--   Drop your files into Interface\AddOns\WHEREDNGN\media\
--   then update the PHOTO and SOUND constants below.
-- ============================================================

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
B.Easter = B.Easter or {}
local M = B.Easter

-- ----- Configuration -----------------------------------------

local EASTER_ENABLED = true

-- Targeted character names (case-sensitive, no realm).
-- The egg fires only when one of these characters is the LOCAL
-- player AND they pass during an escalation skip window.
local TARGETS = {
    "Papayaga",
    "Mants",
    "Lamo",
    "Scralet",
    "Wakkata",
    "Baalah",
}

-- Shared photo + sound used for all targets.
-- Drop your files at:
--   <addon>\media\easter.jpg    (photo)
--   <addon>\media\easter.mp3    (sound)
-- NOTE: WoW retail SetTexture officially supports .tga and .blp.
-- .jpg works on most modern clients but is not guaranteed; if the
-- photo fails to display, convert easter.jpg → easter.tga and
-- update PHOTO below.
local PHOTO = "Interface\\AddOns\\WHEREDNGN\\media\\easter.jpg"
local SOUND = "Interface\\AddOns\\WHEREDNGN\\media\\easter.mp3"

local TRIGGER_CHANCE = 0.10           -- 10% per escalation-skip pass
local PHOTO_DURATION_SECONDS = 5.0    -- adjust to match your sound length

-- ----- Public API --------------------------------------------

-- Returns true if the egg fired. Looks up `playerName` in TARGETS,
-- rolls 10%, and on success shows the photo + plays the sound.
function M.MaybeFire(playerName)
    if not EASTER_ENABLED then return false end
    if not playerName or playerName == "" then return false end
    local match = false
    for _, t in ipairs(TARGETS) do
        if t == playerName then match = true; break end
    end
    if not match then return false end
    if math.random() >= TRIGGER_CHANCE then return false end

    -- Sound
    if SOUND and PlaySoundFile then
        PlaySoundFile(SOUND, "Master")
    end
    -- Photo
    if PHOTO then M._showPhoto(PHOTO, PHOTO_DURATION_SECONDS) end
    return true
end

-- ----- Internal: full-screen photo overlay -------------------

function M._showPhoto(path, duration)
    if not CreateFrame or not UIParent then return end  -- non-WoW guard
    local f = M._overlay
    if not f then
        f = CreateFrame("Frame", "WHEREDNGN_EasterOverlay", UIParent)
        f:SetAllPoints(UIParent)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)  -- block click-through while overlay is up
        f.tex = f:CreateTexture(nil, "ARTWORK")
        f.tex:SetAllPoints(f)
        -- Click anywhere to dismiss early
        f:SetScript("OnMouseDown", function(self) self:Hide() end)
        M._overlay = f
    end
    f.tex:SetTexture(path)
    f:Show()
    if C_Timer and C_Timer.After then
        C_Timer.After(duration or PHOTO_DURATION_SECONDS, function()
            if f and f.Hide and f:IsShown() then f:Hide() end
        end)
    end
end

-- ----- Hook installation -------------------------------------
-- Wrap B.Net.LocalSkipDouble from inside Easter.lua. This handler
-- covers ALL four escalation-skip phases (PHASE_DOUBLE / TRIPLE /
-- FOUR / GAHWA). The hook lives entirely in this file — removing
-- the file unwraps the behavior automatically. Done on a deferred
-- timer so Net.lua is guaranteed to be loaded first regardless of
-- .toc ordering.

function M._installHook()
    if M._hookInstalled then return end
    if not B.Net or not B.Net.LocalSkipDouble then return end
    local orig = B.Net.LocalSkipDouble
    B.Net.LocalSkipDouble = function(...)
        local result = orig(...)
        local name = UnitName and UnitName("player") or nil
        M.MaybeFire(name)
        return result
    end
    M._hookInstalled = true
end

if C_Timer and C_Timer.After then
    C_Timer.After(0.5, M._installHook)
else
    -- Non-WoW context (tests). Caller can install manually if needed.
end
