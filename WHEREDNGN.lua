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
    -- Advanced bots: enables the human-style heuristics described in
    -- Bot.lua (partner-bid awareness, score-position adjustments, AKA
    -- self-call, position-aware following, J-of-trump gating, etc.).
    -- Off by default so existing behaviour is preserved on upgrade;
    -- turn on per-host via /baloot advanced or the lobby checkbox.
    advancedBots = false,
    -- M3lm (معلم — "master") tier. Pro-level heuristics layered on
    -- top of Advanced: partner / opponent play-style ledger across
    -- the full game, match-point urgency for finer score-position
    -- calls, and coordinated escalation that ramps faster when
    -- partner has already escalated. Off by default; turn on per-
    -- host via /baloot m3lm or the lobby checkbox. Strictly extends
    -- Advanced — checking M3lm activates both layers.
    m3lmBots = false,
    -- Fzloky (فظلوكي — "veteran / they leave you no scraps"). Signal-
    -- aware tier on top of M3lm. Reads partner's first-discard as a
    -- suit-preference signal and biases lead choice accordingly.
    -- Strictly extends M3lm (which strictly extends Advanced).
    fzlokyBots = false,
    -- Saudi Master tier (top): determinization-sampling MCTS-flavoured
    -- decision engine. At each play, samples plausible opponent hands
    -- and picks the card with the best aggregate outcome across
    -- worlds. Strictly extends Fzloky / M3lm / Advanced.
    saudiMasterBots = false,
    -- SWA (سوا) "claim-the-rest" mechanic. Confirmed Saudi-table
    -- convention even though English-language references (Pagat,
    -- Saudi Federation gameplay refs) don't document it — Arabic
    -- video sources cover the full rule shape. Default ON; toggle
    -- via /baloot swa.
    allowSWA = true,
    -- Permission gate: per Saudi convention, calling SWA with ≥4
    -- cards remaining is "polite to ask" and "in many house rules
    -- strictly required" — opponents can decline. Calls with ≤3
    -- cards are instant (no permission). Toggle via /baloot swaperm
    -- if your group always allows without asking.
    swaRequiresPermission = true,
    -- Triple-on-Ace pre-emption (الثالث): when a round-2 Sun bid lands
    -- on an Ace bid card, earlier eligible seats may "claim before you"
    -- and take the contract themselves. Per "الثالث" doc — canonical
    -- Saudi rule. ON by default. Disable for groups that prefer the
    -- simpler "first non-pass wins" Sun resolution.
    preemptOnAce = true,
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
    -- Persisted team labels (host-only setting, applied account-wide).
    if WHEREDNGNDB.teamNames then
        B.State.ApplyTeamNames(WHEREDNGNDB.teamNames.A,
                               WHEREDNGNDB.teamNames.B)
    end
    B.State.SetLocalName(GetUnitName("player", true))
    L.Info("init", "local name: %s", tostring(B.State.s.localName))
end

-- After the world finishes loading we may discover we were in a game
-- before the /reload (gameID persisted in WHEREDNGNDB). Broadcast a
-- resync request; the host (if still in the party with the same game)
-- will whisper back an authoritative state snapshot + our hand.
--
-- Note: we DO send the request even if RestoreSession already brought
-- us back into a non-IDLE phase. The local snapshot may be stale by
-- several turns — the host's authoritative reply will overwrite our
-- view with the live state.
local function maybeRequestResync()
    if not WHEREDNGNDB then return end
    local id = WHEREDNGNDB.lastGameID
    if not id or id == "" then return end
    if not IsInGroup() then return end
    -- The host of a solo-bot game (no other party members) won't have
    -- anyone to receive the request — skip there too. (Remote hosts
    -- include the local player in the same party, so IsInGroup passes.)
    if B.State.s.isHost then return end
    L.Info("resync", "requesting state for game %s", id)
    if B.Net and B.Net.SendResyncReq then
        B.Net.SendResyncReq(id)
    end
end

-- ---------------------------------------------------------------------

local f = CreateFrame("Frame", "WHEREDNGNCore")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_LOGOUT")
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
        -- Restore an in-progress session that was persisted on the
        -- previous /reload or logout. If no session is present (or it's
        -- too old / from a finished game) RestoreSession returns false
        -- and we keep the fresh IDLE state init() left us in.
        if B.State.RestoreSession and B.State.RestoreSession() then
            L.Info("init", "session restored from save (phase=%s)",
                tostring(B.State.s.phase))
            -- Re-derive localName in case the realm suffix changed.
            B.State.SetLocalName(GetUnitName("player", true))
            -- The saved snapshot includes whatever target was active at
            -- save time, which clobbers any /baloot target change made
            -- between sessions. Re-read from the per-account DB so the
            -- newer setting wins.
            B.State.s.target = WHEREDNGNDB.target or B.State.s.target or 152
            -- Host needs to resume bot scheduling and re-broadcast the
            -- lobby so reconnected peers see the same seat list.
            if B.State.s.isHost then
                if B.Net and B.Net.SendLobby then
                    B.Net.SendLobby(B.State.s.seats, B.State.s.gameID)
                end
                if B.Net and B.Net.MaybeRunBot then B.Net.MaybeRunBot() end
                -- Audit fix: re-arm AFK protection for human seats.
                -- MaybeRunBot covers bot seats but never arms a turn
                -- timer; without this re-arm, a player who /reloads
                -- while it's their turn loses AFK auto-action and
                -- the table waits forever. Mirror the pause/resume
                -- code in N.LocalPause: if there's an active human
                -- turn, start a fresh AFK timer; if there's an
                -- active escalation window with a human eligible,
                -- start the corresponding bel-style timer.
                local s = B.State.s
                if B.Net and s.turn and s.turnKind and s.seats[s.turn]
                   and not s.seats[s.turn].isBot then
                    if (s.turnKind == "bid" or s.turnKind == "play")
                       and B.Net.StartTurnTimer then
                        B.Net.StartTurnTimer(s.turn, s.turnKind)
                    end
                end
                if B.Net and s.contract and s.phase and B.Net.StartBelTimer then
                    -- Bel / Triple / Four / Gahwa eligibility maps to a
                    -- single seat each; if it's a human, arm a timer.
                    local bidder = s.contract.bidder
                    local defSeat = bidder and ((bidder % 4) + 1) or nil
                    if s.phase == K.PHASE_DOUBLE and defSeat
                       and s.seats[defSeat] and not s.seats[defSeat].isBot then
                        B.Net.StartBelTimer(defSeat, "double")
                    elseif s.phase == K.PHASE_TRIPLE and bidder
                       and s.seats[bidder] and not s.seats[bidder].isBot then
                        B.Net.StartBelTimer(bidder, "triple")
                    elseif s.phase == K.PHASE_FOUR and defSeat
                       and s.seats[defSeat] and not s.seats[defSeat].isBot then
                        B.Net.StartBelTimer(defSeat, "four")
                    elseif s.phase == K.PHASE_GAHWA and bidder
                       and s.seats[bidder] and not s.seats[bidder].isBot then
                        B.Net.StartBelTimer(bidder, "gahwa")
                    end
                end
            end
            if B.UI and B.UI.Refresh then B.UI.Refresh() end
        end
        return
    end
    if event == "PLAYER_LOGOUT" then
        -- WoW persists SavedVariables right after this fires (also
        -- triggered by /reload). Snapshot the current state so the
        -- next session can pick up where we left off.
        if B.State and B.State.SaveSession then B.State.SaveSession() end
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
        -- Refresh the lobby UI's party sidebar regardless of host
        -- status — the list of party members shifts when anyone joins
        -- or leaves the WoW group, even when no game is active yet.
        if B.UI and B.UI.Refresh then B.UI.Refresh() end
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
