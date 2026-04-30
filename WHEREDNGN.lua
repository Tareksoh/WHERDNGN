-- Addon entry. Owns the WoW event lifecycle:
--   ADDON_LOADED          - savedvars init
--   PLAYER_LOGIN          - register addon prefix, capture local name
--   CHAT_MSG_ADDON        - route to Net.HandleMessage
--   GROUP_ROSTER_UPDATE   - cleanup if a seated player leaves the party
--
-- Combat lockdown isn't a concern here: WHEREDNGN uses no protected frames
-- or secure templates. The window can open and accept clicks during combat.

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
local K = B.K
local L = B.Log

local DEFAULTS = {
    debug    = false,
    target   = 152,            -- game-end cumulative target
    framePos = nil,
}

local function ensureDB()
    WHEREDNGNDB = WHEREDNGNDB or {}
    for k, v in pairs(DEFAULTS) do
        if WHEREDNGNDB[k] == nil then WHEREDNGNDB[k] = v end
    end
end

local function init()
    ensureDB()
    B.State.s.target = WHEREDNGNDB.target or 152
    B.State.SetLocalName(GetUnitName("player", true))
    L.Info("init", "local name: %s", tostring(B.State.s.localName))
end

-- After the world finishes loading we may discover we were in a game
-- before the /reload (gameID persisted in WHEREDNGNDB). Broadcast a
-- resync request; the host (if still in the party with the same game)
-- will whisper back a state snapshot + our hand.
local function maybeRequestResync()
    if not WHEREDNGNDB then return end
    local id = WHEREDNGNDB.lastGameID
    if not id or id == "" then return end
    if not IsInGroup() then return end
    if B.State.s.phase ~= K.PHASE_IDLE then return end
    L.Info("resync", "requesting state for game %s", id)
    if B.Net and B.Net.SendResyncReq then
        B.Net.SendResyncReq(id)
    end
end

-- ---------------------------------------------------------------------

local f = CreateFrame("Frame", "WHEREDNGNCore")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("GROUP_ROSTER_UPDATE")

f:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4, arg5)
    if event == "ADDON_LOADED" and arg1 == "WHEREDNGN" then
        ensureDB()
        return
    end
    if event == "PLAYER_LOGIN" then
        init()
        local ok = C_ChatInfo.RegisterAddonMessagePrefix(K.PREFIX)
        if not ok then
            L.Warn("init", "failed to register addon prefix %s", K.PREFIX)
        end
        if B.MinimapIcon and B.MinimapIcon.Show then B.MinimapIcon.Show() end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        -- Re-set even if non-nil — realm info may not have been ready
        -- at PLAYER_LOGIN, leaving the name without its realm suffix.
        B.State.SetLocalName(GetUnitName("player", true))
        -- One-shot resync attempt after world load. Delayed slightly so
        -- the addon prefix registration and party state have settled.
        C_Timer.After(2.0, maybeRequestResync)
        return
    end
    if event == "CHAT_MSG_ADDON" then
        -- args: prefix, message, channel, sender
        B.Net.HandleMessage(arg1, arg2, arg3, arg4)
        return
    end
    if event == "GROUP_ROSTER_UPDATE" then
        -- If we were in a lobby/game and a seated HUMAN player has dropped
        -- from the party, kick that seat. Bots are local-only (no party
        -- presence) so we skip them — otherwise any roster change would
        -- empty all bot seats since their names never match real units.
        if not B.State.s.isHost then return end
        if B.State.s.phase == K.PHASE_IDLE then return end
        for seat = 2, 4 do
            local info = B.State.s.seats[seat]
            if info and info.name and not info.isBot then
                local short = info.name:match("^([^%-]+)") or info.name
                local found = false
                for i = 1, 4 do
                    local u = "party" .. i
                    if UnitExists(u) and UnitName(u) == short then found = true; break end
                end
                if not found then
                    L.Warn("roster", "seat %d (%s) left the group", seat, short)
                    B.State.HostKickSeat(seat)
                    if B.UI then B.UI.Refresh() end
                    if B.Net then B.Net.SendLobby(B.State.s.seats, B.State.s.gameID) end
                end
            end
        end
        return
    end
end)
