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
    -- v2.1.0 (audit v1.6.1 PJ-40 MED): persistent lifetime stats.
    -- Pre-fix the addon had no engagement loop — every game's
    -- numbers vanished when the game ended. Now WHEREDNGNDB.stats
    -- accumulates across sessions: games played/won/lost (as a team
    -- member), contracts taken/made/failed (as the bidder), biggest
    -- single-game point swing seen. Mutated by HostFinishDeal /
    -- HostEndGame / ApplyGameEnd; surfaced via /baloot stats.
    --
    -- Schema is forward-compatible: new fields default to 0 in
    -- ensureDB; missing fields don't crash readers.
    stats = {
        gamesPlayed   = 0,    -- total finished games (incl. losses)
        gamesWon      = 0,    -- finished games where local team won
        contractsTaken = 0,   -- times local seat was the bidder
        contractsMade  = 0,   -- bidder + made the contract
        biggestSwing   = 0,   -- biggest single-game cumulative delta
    },
}

local function ensureDB()
    -- 7th-audit fix: defensive type guard. SavedVariables files can be
    -- hand-edited or corrupted (e.g., a manual save where the user
    -- replaced the table with `WHEREDNGNDB = "bad"`). Indexing a non-
    -- table here would crash addon load; reset to {} when the saved
    -- value is unusable.
    if type(WHEREDNGNDB) ~= "table" then WHEREDNGNDB = {} end
    for k, v in pairs(DEFAULTS) do
        if WHEREDNGNDB[k] == nil then WHEREDNGNDB[k] = v end
    end
    -- v2.1.0 PJ-40: stats subtable forward-compat. If saved DB is
    -- from a pre-v2.1.0 install, stats will be nil; if from a
    -- partial install (some keys present, others added later),
    -- defaults fill in. Defensive against type corruption too.
    if type(WHEREDNGNDB.stats) ~= "table" then WHEREDNGNDB.stats = {} end
    for k, v in pairs(DEFAULTS.stats) do
        if WHEREDNGNDB.stats[k] == nil then WHEREDNGNDB.stats[k] = v end
    end
end

local function init()
    ensureDB()
    -- v0.9.0 L6 fix (audit AUDIT_REPORT_v0.7.1.md): tonumber-coerce
    -- WHEREDNGNDB.target so a hand-edited string value doesn't break
    -- `cum >= target` arithmetic downstream. Default 152 if absent
    -- or non-numeric.
    B.State.s.target = tonumber(WHEREDNGNDB.target) or 152
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
        -- v2.1.0 (audit v1.6.1 PJ-04 MED): register a Blizz interface-
        -- options category so the addon shows up in the Esc → Options
        -- → AddOns tree. Pre-fix the addon was discoverable only via
        -- the minimap icon or /baloot — players who reach for the
        -- standard Esc → Options path saw nothing. The panel is
        -- minimal (clicking it opens the WHEREDNGN window) since the
        -- real settings are in /baloot subcommands; the registration
        -- is purely for findability.
        -- v3.0 (audit v1.6.1 PJ-04 follow-up + PJ-52 MED): real
        -- Settings panel with checkboxes for every persistent
        -- WHEREDNGNDB toggle. Pre-v3.0 the panel was a description-
        -- only stub that pointed at slash commands. Now players can
        -- toggle bot tier, rules, sound, etc. without leaving the
        -- options menu.
        local function buildSettingsPanel()
            local panel = CreateFrame("Frame")
            panel.name = "Loot & Baloot (WHEREDNGN)"

            local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
            title:SetPoint("TOPLEFT", 16, -16)
            title:SetText("Loot & Baloot — Saudi Baloot")

            local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
            desc:SetWidth(560)
            desc:SetJustifyH("LEFT")
            desc:SetText("All toggles below mirror /baloot subcommands. "
                .. "Click the minimap icon to open the game window. "
                .. "Type |cffffffff/baloot help|r in chat for the full "
                .. "command list.")

            local openBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
            openBtn:SetSize(180, 24)
            openBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -10)
            openBtn:SetText("Open WHEREDNGN window")
            openBtn:SetScript("OnClick", function()
                if B.UI and B.UI.Toggle then B.UI.Toggle() end
            end)

            -- Helper to create a labeled checkbox bound to a
            -- WHEREDNGNDB key. Cascading effect: clicking M3lm checks
            -- Advanced too (visual feedback that strict-extension is
            -- happening; the actual logic is in Bot.IsAdvanced /
            -- IsM3lm which already check parents).
            local lastCb
            local function makeCheck(key, label, tooltip, anchor)
                local cb = CreateFrame("CheckButton", nil, panel,
                                       "InterfaceOptionsCheckButtonTemplate")
                if anchor then
                    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 2)
                else
                    cb:SetPoint("TOPLEFT", openBtn, "BOTTOMLEFT", 0, -16)
                end
                cb.Text:SetText(label)
                cb:SetScript("OnShow", function(self)
                    self:SetChecked(WHEREDNGNDB and WHEREDNGNDB[key])
                end)
                cb:SetScript("OnClick", function(self)
                    WHEREDNGNDB = WHEREDNGNDB or {}
                    WHEREDNGNDB[key] = self:GetChecked() and true or false
                end)
                if tooltip then
                    cb:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:AddLine(label, 1, 1, 1)
                        GameTooltip:AddLine(tooltip, 0.85, 0.85, 0.85, true)
                        GameTooltip:Show()
                    end)
                    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
                end
                return cb
            end

            -- Section: bot tiers
            local sec1 = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            sec1:SetPoint("TOPLEFT", openBtn, "BOTTOMLEFT", 0, -16)
            sec1:SetText("|cffffd055Bot tiers|r (cumulative — higher tiers extend lower)")
            local advCb = makeCheck("advancedBots", "Advanced bots",
                "Human-style heuristics: partner-bid reads, position-aware play. "
                .. "Tier 2/5.",
                sec1)
            advCb:SetPoint("TOPLEFT", sec1, "BOTTOMLEFT", 0, -2)
            local m3lmCb  = makeCheck("m3lmBots", "M3lm (master)",
                "Pro tier: opponent style ledger, match-point urgency. "
                .. "Tier 3/5. Strictly extends Advanced.", advCb)
            local fzlokyCb = makeCheck("fzlokyBots", "Fzloky (signal-aware)",
                "Reads partner's discard signals to bias lead choice. "
                .. "Tier 4/5. Strictly extends M3lm.", m3lmCb)
            makeCheck("saudiMasterBots", "Saudi Master (ISMCTS)",
                "Top tier: monte-carlo opponent-hand sampling, ~150ms/move. "
                .. "Tier 5/5. Strictly extends Fzloky.", fzlokyCb)

            -- Section: Saudi rules
            local sec2 = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            sec2:SetPoint("TOPLEFT", title, "TOPLEFT", 320, -90)
            sec2:SetText("|cffffd055Saudi rule toggles|r")
            local swaCb = makeCheck("allowSWA", "SWA (claim-the-rest)",
                "Saudi-table sociable rule: caller asserts they win every "
                .. "remaining trick. Off = strict tournament mode.", sec2)
            swaCb:SetPoint("TOPLEFT", sec2, "BOTTOMLEFT", 0, -2)
            local swaPermCb = makeCheck("swaRequiresPermission",
                "SWA permission for 4+ cards",
                "Saudi default: 4+ card SWA needs opps' permission. "
                .. "Off = house rule of all-SWA-instant.", swaCb)
            makeCheck("preemptOnAce", "Triple-on-Ace pre-emption",
                "Round-2 Sun on Ace bid card lets earlier seats claim. "
                .. "Saudi rule. Off = simpler 'first non-pass wins'.",
                swaPermCb)

            -- Section: misc
            local sec3 = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            sec3:SetPoint("TOPLEFT", sec2, "TOPLEFT", 0, -160)
            sec3:SetText("|cffffd055Misc|r")
            local soundCb = makeCheck("sound", "Sound enabled",
                "Master toggle for card play SFX, voice cues, fanfares. "
                .. "Same effect as the lobby-window checkbox.", sec3)
            soundCb:SetPoint("TOPLEFT", sec3, "BOTTOMLEFT", 0, -2)
            makeCheck("debug", "Debug logging",
                "Verbose log output. /baloot log dumps the buffer.",
                soundCb)

            local footer = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 16)
            footer:SetText("|cff999999Numeric settings (game target, "
                .. "cards/felt theme): see /baloot help. "
                .. "Lifetime stats: /baloot stats.|r")

            return panel
        end

        if Settings and Settings.RegisterCanvasLayoutCategory then
            local panel = buildSettingsPanel()
            local cat = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
            Settings.RegisterAddOnCategory(cat)
        elseif InterfaceOptions_AddCategory then
            -- Legacy (pre-10.0) compatibility shim with same checkbox layout.
            local panel = buildSettingsPanel()
            InterfaceOptions_AddCategory(panel)
        end
        -- v1.7.0 (audit v1.6.1 PJ-01): one-shot welcome on first launch.
        -- Pre-fix the addon was completely silent on first install — new
        -- users had to discover `/baloot` or the minimap icon by guess.
        -- Welcome prints once, then sets WHEREDNGNDB.welcomed = true so
        -- it never repeats. Mentions the minimap icon and `/baloot help`
        -- as the two discovery surfaces.
        -- v3.0.1 (audit v3.0.0 HIGH#1): wire the v1.8.0 MP-21 host-
        -- alive heartbeat watchdog into a real consumer. Pre-v3.0.1
        -- N.IsHostLikelyGone() existed but no caller — heartbeat
        -- detection was structurally undelivered. Now: a 10s ticker
        -- checks when we're a non-host in an active game; on first
        -- detection of host-gone, print a chat warning. Self-clears
        -- the warned flag once the host comes back (heartbeat
        -- resumes).
        if C_Timer and C_Timer.NewTicker then
            local warned = false
            C_Timer.NewTicker(10, function()
                if not B.Net or not B.Net.IsHostLikelyGone then return end
                if B.State.s.isHost then warned = false; return end
                if B.State.s.phase == K.PHASE_IDLE
                   or B.State.s.phase == K.PHASE_LOBBY then
                    warned = false; return
                end
                local gone = B.Net.IsHostLikelyGone()
                if gone and not warned then
                    warned = true
                    print("|cffff5544[WHEREDNGN]|r |cffffd055Host appears "
                        .. "to be gone|r — no heartbeat for "
                        .. "45+ seconds. The game may be stalled. "
                        .. "Try /baloot reset to return to idle.")
                elseif not gone then
                    warned = false   -- reset once heartbeat resumes
                end
            end)
        end
        if not WHEREDNGNDB.welcomed then
            print("|cff66ddff[WHEREDNGN]|r Welcome to Loot & Baloot — "
                .. "Saudi Baloot for WoW. Click the |cffffffffminimap icon|r "
                .. "to host or join a game. Type |cffffffff/baloot help|r "
                .. "for commands or |cffffffff/baloot rules|r for a Saudi-rules "
                .. "cheat-sheet.")
            WHEREDNGNDB.welcomed = true
        end
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
            -- v0.9.0 L6 fix: tonumber-coerce to defend against
            -- hand-edited string targets in SavedVariables.
            B.State.s.target = tonumber(WHEREDNGNDB.target)
                               or B.State.s.target
                               or 152
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
                -- v0.11.0 D1 fix (audit_v0.10.7 A_Net_audit.md HIGH):
                -- PHASE_PREEMPT was missing from the AFK re-arm chain
                -- above. /reload during a Triple-on-Ace pre-emption
                -- window with a human eligible seat soft-locked: the
                -- BelTimer (kind="preempt_pass") didn't survive the
                -- /reload and no recovery path re-armed it. Same shape
                -- as the v0.10.6 redeal-stuck bug pattern. Pre-empt
                -- has a LIST of eligible seats (S.s.preemptEligible);
                -- arm for the first human in the list (only one timer
                -- can be in flight; if that seat passes, the host
                -- advances and remaining bots fire via MaybeRunBot).
                if B.Net and s.phase == K.PHASE_PREEMPT
                   and s.preemptEligible and B.Net.StartBelTimer then
                    for _, pseat in ipairs(s.preemptEligible) do
                        if s.seats[pseat] and not s.seats[pseat].isBot then
                            B.Net.StartBelTimer(pseat, "preempt_pass")
                            break
                        end
                    end
                end
                -- 6th-audit fix: re-fire _HostStepPlay if a 4-play
                -- trick was stuck mid-resolution at /reload time.
                -- _HostStepPlay's 2.2s C_Timer doesn't survive a
                -- /reload, so a host who reloaded with a complete
                -- trick on the table would never resolve it — the
                -- table soft-locks waiting for a 5th play that never
                -- comes. Schedule a delayed step to give the rest of
                -- the restore (network/UI) time to settle first.
                if s.phase == K.PHASE_PLAY and s.trick
                   and s.trick.plays and #s.trick.plays >= 4
                   and B.Net and B.Net._HostStepPlay then
                    C_Timer.After(0.5, function()
                        if not B.State.s.isHost then return end
                        if B.State.s.phase ~= K.PHASE_PLAY then return end
                        if B.State.s.paused then return end
                        if not B.State.s.trick then return end
                        if #B.State.s.trick.plays < 4 then return end
                        B.Net._HostStepPlay()
                    end)
                end
                -- v0.10.6 user-reported bug fix: re-arm an in-flight
                -- redeal that was stuck across a /reload. If the user
                -- paused during the 3s redeal banner and then
                -- /reloaded, the timer is gone and `s.redealing` is
                -- still set with no recovery path. Schedule a fresh
                -- 3s window so the banner lands again, then deal.
                -- Skip if the user is still paused — LocalPause's
                -- resume path will pick it up. Same shape as the
                -- _HostStepPlay re-fire above.
                if s.redealing and B.Net and B.Net._HostExecuteRedeal
                   and (s.phase == K.PHASE_DEAL2BID or s.phase == K.PHASE_DEAL1)
                   and not s.paused then
                    local nextDealer = s.redealing.nextDealer
                    if nextDealer then
                        B._redealGen = (B._redealGen or 0) + 1
                        local thisGen = B._redealGen
                        C_Timer.After(3.0, function()
                            if thisGen ~= B._redealGen then return end
                            if not B.State.s.isHost then return end
                            if B.State.s.paused then return end
                            B.Net._HostExecuteRedeal(nextDealer)
                        end)
                    end
                end
            end
            -- Re-audit fix V13: also re-arm the LOCAL T-10s pre-warn
            -- (audio ping + UI pulse) on every client. StartLocalWarn
            -- self-gates on whether the LOCAL seat is the one waiting,
            -- so calling it on every client is safe — only the
            -- relevant client actually arms a timer. Covers both the
            -- normal turn and the escalation windows.
            if B.Net and B.Net.StartLocalWarn then
                local s = B.State.s
                if s.turnKind == "bid" or s.turnKind == "play" then
                    B.Net.StartLocalWarn(s.turnKind)
                elseif s.phase == K.PHASE_DOUBLE then
                    B.Net.StartLocalWarn("bel")
                elseif s.phase == K.PHASE_TRIPLE then
                    B.Net.StartLocalWarn("triple")
                elseif s.phase == K.PHASE_FOUR then
                    B.Net.StartLocalWarn("four")
                elseif s.phase == K.PHASE_GAHWA then
                    B.Net.StartLocalWarn("gahwa")
                elseif s.phase == K.PHASE_PREEMPT then
                    -- Re-audit W6 fix: also pre-warn pre-empters on
                    -- /reload. StartLocalWarn self-gates on the
                    -- local seat being eligible, so calling on every
                    -- client is safe — only eligible local seats arm.
                    B.Net.StartLocalWarn("preempt")
                elseif s.phase == K.PHASE_OVERCALL then
                    -- v0.9.0 M2 fix: also re-arm pre-warn for v0.7.0
                    -- Sun-overcall window. Same self-gating semantics
                    -- as the others.
                    B.Net.StartLocalWarn("overcall")
                end
            end
            -- v0.9.0 M2 fix (audit AUDIT_REPORT_v0.7.1.md): host re-arm
            -- of mid-window timers. Pre-v0.9.0, /reload mid-PHASE_OVERCALL
            -- or mid-SWA-permission soft-locked the host until manual
            -- recovery — only Bel/Triple/Four/Gahwa AFK timers were
            -- re-armed via StartTurnTimer above.
            if B.State.s.isHost and B.Net then
                if B.State.s.phase == K.PHASE_OVERCALL
                   and B.State.s.overcall then
                    -- Reset window startedAt to now so the countdown
                    -- restarts cleanly; arm a fresh resolve timer.
                    B.State.s.overcall.startedAt = (GetTime and GetTime()) or 0
                    if C_Timer and C_Timer.After then
                        C_Timer.After(K.OVERCALL_TIMEOUT_SEC, function()
                            if not B.State.s.isHost then return end
                            if B.State.s.phase ~= K.PHASE_OVERCALL then return end
                            if B.State.s.paused then return end
                            B.Net._HostResolveOvercall()
                        end)
                    end
                end
                if B.State.s.swaRequest and B.State.s.swaRequest.caller
                   and B.State.s.phase == K.PHASE_PLAY then
                    -- Reset SWA request ts and arm a fresh auto-resolve
                    -- timer. The 5s clock restarts so opponents see a
                    -- full window post-reload.
                    local req = B.State.s.swaRequest
                    req.ts = (GetTime and GetTime()) or req.ts
                    if C_Timer and C_Timer.After then
                        C_Timer.After(K.SWA_TIMEOUT_SEC or 5, function()
                            if not B.State.s.isHost then return end
                            if not B.State.s.swaRequest then return end
                            if B.State.s.swaRequest.caller ~= req.caller then return end
                            if B.State.s.phase ~= K.PHASE_PLAY then return end
                            if B.State.s.paused then return end
                            local hand = (req.encodedHand
                                          and B.Cards.DecodeHand(req.encodedHand))
                                         or {}
                            local caller = req.caller
                            B.State.s.swaRequest = nil
                            B.Net.HostResolveSWA(caller, hand)
                        end)
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
        -- 50-agent codebase audit fix (M-2): nil-guard B.Net for
        -- consistency with every other module reference in this file.
        -- If Net.lua failed to load (e.g., partial install or version
        -- skew), an unguarded call would raise on every incoming
        -- addon message — flooding error popups.
        if B.Net and B.Net.HandleMessage then
            B.Net.HandleMessage(arg1, arg2, arg3, arg4)
        end
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
                -- v2.1.0 (audit v1.6.1 MP-53 MED): match seated names
                -- via S.NormalizeName so cross-realm party-N units
                -- (which arrive as bare "Name" without realm suffix)
                -- correctly compare against seat records that may
                -- carry "Name-Realm". Pre-fix the strict shortName
                -- match could miss a still-present cross-realm peer
                -- whose UnitName format differed from the seat record.
                local short = info.name:match("^([^%-]+)") or info.name
                local seatedNorm = (B.State.NormalizeName
                                    and B.State.NormalizeName(info.name))
                                    or info.name
                local found = false
                for i = 1, 4 do
                    local u = "party" .. i
                    if UnitExists(u) then
                        local uname = UnitName(u)
                        if uname == short then
                            found = true; break
                        end
                        -- Defense-in-depth: also compare normalized
                        -- forms in case UnitName returns a suffixed
                        -- variant on cross-realm clients.
                        if uname and B.State.NormalizeName then
                            local unameNorm = B.State.NormalizeName(uname)
                            if unameNorm == seatedNorm then
                                found = true; break
                            end
                        end
                    end
                end
                if not found then
                    L.Warn("roster", "seat %d (%s) left the group", seat, short)
                    -- v1.8.0 (audit v1.6.1 MP-01 CRITICAL): when a
                    -- seated human drops mid-game, replace them with a
                    -- bot so the round can continue. Pre-fix
                    -- HostKickSeat just dropped the seat to nil — the
                    -- next time the dispatcher hit that seat's turn, it
                    -- would freeze permanently (no human to AFK-timer,
                    -- no bot to dispatch). Replacing with a bot keeps
                    -- the round playable; the bot inherits the
                    -- in-flight state (hand if dealt, bid if cast).
                    -- Lobby/pre-deal disconnect = kick (bot fill via
                    -- the existing /baloot bots flow); mid-round
                    -- disconnect = bot replace.
                    if B.State.s.phase == K.PHASE_LOBBY then
                        B.State.HostKickSeat(seat)
                    else
                        -- Mid-round: replace with bot, preserve the
                        -- isBot flag so MaybeRunBot picks it up. Hand
                        -- and bid state already live in S.s.hostHands
                        -- and S.s.bids keyed by seat — they survive
                        -- the seat-record swap.
                        local placeholder = "Bot" .. seat
                        B.State.s.seats[seat] = {
                            name = placeholder, isBot = true,
                        }
                        L.Info("roster",
                            "seat %d replaced by bot (%s dropped mid-round)",
                            seat, short)
                        -- v2.2.0 (audit v1.6.1 MP-33 LOW): cancel the
                        -- host's AFK turn timer if the dropped seat
                        -- was the active turn. Pre-fix a stale 60s
                        -- AFK timer kept counting against the seat
                        -- after the bot took over — would fire and
                        -- attempt auto-action on a now-bot seat,
                        -- creating a brief race against MaybeRunBot's
                        -- own dispatch. Cancel here; the new bot's
                        -- dispatch arms a fresh timer if needed.
                        if B.State.s.turn == seat
                           and B.Net and B.Net.CancelTurnTimer then
                            B.Net.CancelTurnTimer()
                        end
                        -- v2.0.0 (audit v1.6.1 MP-02/03/04 HIGH): if
                        -- the drop happened DURING an escalation
                        -- window / overcall window / SWA permission
                        -- window, the dropped player owed a vote
                        -- that will never come. Soft-locks the round.
                        -- Now: synthesize the missing vote
                        -- immediately based on phase. The
                        -- newly-installed bot at this seat would
                        -- have made these decisions per the existing
                        -- Bot.PickDouble / Bot.PickOvercall paths;
                        -- we re-invoke them to get a clean answer.
                        local phase = B.State.s.phase
                        if phase == K.PHASE_DOUBLE
                           or phase == K.PHASE_TRIPLE
                           or phase == K.PHASE_FOUR
                           or phase == K.PHASE_GAHWA then
                            -- Rerun the bot dispatcher to pick up the
                            -- dropped seat's escalation decision.
                            -- MaybeRunBot's belPending walk handles
                            -- the now-bot seat correctly.
                            if B.Net and B.Net.MaybeRunBot then
                                B.Net.MaybeRunBot()
                            end
                        elseif phase == K.PHASE_OVERCALL then
                            -- Synthesize a default WAIVE for the
                            -- dropped seat. The overcall window's
                            -- AllDecided check unblocks once we
                            -- record the missing vote.
                            if B.State.RecordOvercallDecision
                               and B.State.s.overcall then
                                B.State.RecordOvercallDecision(seat, "WAIVE")
                                if B.Net and B.Net._OvercallAllDecided
                                   and B.Net._OvercallAllDecided() then
                                    if B.Net._HostResolveOvercall then
                                        B.Net._HostResolveOvercall()
                                    end
                                end
                            end
                        elseif B.State.s.swaRequest
                               and B.State.s.swaRequest.responses
                               and B.State.s.swaRequest.caller ~= seat then
                            -- Mid-SWA-permission drop: synthesize an
                            -- ACCEPT for the dropped seat (lenient
                            -- default — the loss falls on the caller
                            -- if they're wrong, so accepting is the
                            -- low-risk answer for the AFK voter).
                            B.State.s.swaRequest.responses[seat] = true
                        end
                        -- Kick MaybeRunBot in case it's the dropped
                        -- seat's turn right now.
                        if B.Net and B.Net.MaybeRunBot then
                            B.Net.MaybeRunBot()
                        end
                    end
                    if B.UI then B.UI.Refresh() end
                    if B.Net then B.Net.SendLobby(B.State.s.seats, B.State.s.gameID) end
                end
            end
        end
        return
    end
end)
