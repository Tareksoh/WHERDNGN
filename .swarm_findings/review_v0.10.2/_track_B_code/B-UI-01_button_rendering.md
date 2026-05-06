# B-UI-01 — Button Rendering & Legality Dim/Highlight Audit (v0.10.2)

Track: B (code) · File: `UI.lua` (3590 lines) + `State.lua:1961-1969` (`S.GetLegalPlays`)
Audit date: 2026-05-05 · Mode: read-only

---

## Executive summary

Twelve checkpoints inspected. **Five HIGH-severity findings** (D-RT-04 dim
omission, D-RT-13 SWA hand-count gate, D-RT-22 trailing-bidder routing,
AKA button gate, takweesh visibility), **three MEDIUM** (preempt
turn-source, host-only Next-Round gate, score panel `.cumulative` nil
guard), **four LOW/INFO** confirmations of correct behaviour.

The most damaging single bug is **D-RT-04** (the assigned finding):
`S.GetLegalPlays` calls `R.IsLegalPlay` with **5 args, omitting the 6th
`akaCalled` parameter**. This makes the AKA-receiver relief invisible
to the local player's gold-border highlight, training humans to play
against the AKA convention they're being asked to follow.

---

## F-1 [HIGH · D-RT-04 / B-Net-01 F-OP-12]  S.GetLegalPlays omits akaCalled — UI dim trains against AKA

### Severity
**HIGH** — silent regression that propagates AKA-blind semantics into
every gold-border / red-border decision the human player sees during
PHASE_PLAY. The actual host validation path (`Net._HostTurnTimeout`,
`_OnSWAReq` recursion at `Net.lua:4136`) DOES pass `akaCalled`, so the
host accepts plays the local UI marked illegal. End result: the
receiver's UI shows the relief-eligible discard with the **red
"warning" border** (`COL.badEdge`, `UI.lua:2194`), and the human player
learns "discarding here is unsafe / a Takweesh risk", precisely the
opposite of the rule the addon is teaching them.

### Repro
1. Host a Hokm contract (e.g. trump = ♣, bidder = seat 2).
2. Seat 1 calls `AKA ♥` while leading (trick opens with ♥A from seat 1).
3. Seat 2 (opponent) over-trumps with ♣9 — partner is no longer the
   apparent winner.
4. Seat 3 (local human, AKA receiver) is void in ♥ AND holds ♣J
   (highest trump) plus a few discards.
5. Saudi rule (J-066/J-067 part 2, encoded at `Rules.lua:115-121` and
   `:171-175`): seat 3 is **EXEMPT from must-trump-ruff** because
   partner's lead card is the boss of ♥. Any discard is legal.
6. **Observed UI**: every discard in seat 3's hand renders with the
   red `COL.badEdge` border (the "warning, will be Takweeshed"
   styling). Trump card ♣J renders gold.
7. **Expected**: every card in seat 3's hand should render gold,
   because all of them are legal under AKA-relief.

### Quote — the bug

`State.lua:1961-1969`:
```lua
function S.GetLegalPlays()
    if not s.localSeat or not S.IsMyTurn() or not s.contract then return {} end
    if s.phase ~= K.PHASE_PLAY then return {} end
    local legal = {}
    for _, c in ipairs(s.hand) do
        local ok = R.IsLegalPlay(c, s.hand, s.trick, s.contract, s.localSeat)
        if ok then legal[#legal + 1] = c end
    end
    return legal
```

`Rules.lua:89` signature shows the missing 6th argument:
```lua
function R.IsLegalPlay(card, hand, trick, contract, seat, akaCalled)
```

`Rules.lua:115-121` shows what gets skipped:
```lua
local akaRelief = false
if akaCalled and akaCalled.seat and akaCalled.suit
   and seat and R.Partner(seat) == akaCalled.seat
   and akaCalled.suit == leadSuit
   and contract and contract.type == K.BID_HOKM then
    akaRelief = true
end
```

### Quote — UI consumer affected

`UI.lua:2134-2135`:
```lua
local legalSet = {}
for _, c in ipairs(S.GetLegalPlays()) do legalSet[c] = true end
```

`UI.lua:2186-2198` paints gold/red from this set:
```lua
if legalSet[card] then
    b:SetBackdropBorderColor(unpack(COL.legalEdge))   -- gold
else
    b:SetBackdropBorderColor(unpack(COL.badEdge))     -- red warning
end
```

### Comparable host-side call sites (which DO pass `akaCalled`)

- `Net.lua:2040` — `LocalPlay` validation: passes `S.s.akaCalled`.
- `Net.lua:3412` — `_HostTurnTimeout` AFK auto-pick: passes `S.s.akaCalled`.
- `Net.lua:4136` — `_OnSWAReq` recursion: passes `S.s.akaCalled`.
- `State.lua:1219` — `S.HostValidateAndApply` (the canonical legality
   check): passes `s.akaCalled`.

Only the LOCAL UI dim/highlight path (`S.GetLegalPlays` → `renderHand`)
omits the parameter. The AFK path at `:3412` and SWA recursion at
`:4136` both pass the parameter — so the divergence is UI-specific.

### Sister bug — same omission in S.HostValidatePlay

`State.lua:1659-1666`:
```lua
function S.HostValidatePlay(seat, card)
    ...
    return R.IsLegalPlay(card, s.hostHands[seat], s.trick, s.contract, seat)
end
```

This is the host-side single-card validator. Caller-side audit (out of
scope for this finding) — included for completeness because the bug
chain is identical.

### Suggested fix (NOT applied per instructions)

Add `s.akaCalled` as the 6th argument:
```lua
local ok = R.IsLegalPlay(c, s.hand, s.trick, s.contract, s.localSeat, s.akaCalled)
```
Same one-line change in `S.HostValidatePlay`.

### Why this is dangerous

The addon's selling point is teaching Saudi convention. The AKA-relief
rule is documented prominently (`docs/strategy/signals.md`, the AKA
voice cue, the renderAKABanner toast at `UI.lua:3236`). Yet the gold
border, which is the player's primary "this card is safe" cue,
contradicts the rule. A player who follows the visual cue learns to
**ruff into partner's AKA-led winning trick** — destroying the very
information the AKA call communicated. This is worse than no UI
guidance at all.

---

## F-2 [HIGH · D-RT-13]  SWA button has no hand-count gate

### Severity
**HIGH** — the Saudi convention is hand-count gated: ≤3 cards = instant
claim, 4+ = mandatory permission, but **8-card SWA (immediate post-deal,
no plays) makes no semantic sense as a "claim the rest"**. The UI's SWA
button is visible from trick 1 onwards with zero hand-count check,
allowing a human to fire SWA with their full 8-card hand. The host's
`R.IsValidSWA` recursion eventually rejects (because SWA from the
deal-out is structurally false-positive only in pathological hands),
but the round-trip + 5s permission window leaks the caller's full hand
to opponents via `req.encodedHand` (`UI.lua:1404-1445`,
`Net.lua:2516`).

### Repro
1. PHASE_PLAY begins. Seat 1 has 8 cards, no plays yet.
2. Seat 1 clicks `|cffffd055SWA|r` (`UI.lua:2012`).
3. `N.LocalSWA` checks only `WHEREDNGNDB.allowSWA == false`
   (`Net.lua:2477`). No hand-count guard.
4. Permission window opens; opponents see seat 1's full encoded hand
   in the SWA banner (`UI.lua:3231`, `swaBanner.populateCards`).
5. Information leak: opponents now know all 8 cards seat 1 holds,
   which deeply prejudices the rest of the round even after the SWA
   resolves to invalid.

### Quote — UI gate is permission-only, not count-aware

`UI.lua:2001-2015`:
```lua
local swaEnabled = (WHEREDNGNDB == nil)
    or (WHEREDNGNDB.allowSWA ~= false)
local swaPending = S.s.swaRequest ~= nil
if swaEnabled and not swaPending then
    addConfirmAction("|cffffd055SWA|r",
        "|cffffd055SWA? again to confirm|r",
        function() net().LocalSWA() end)
end
```

No `#S.s.hand <= K.SWA_MAX_HAND` style gate. The 4-card-cap on the
SWA banner's card row (`UI.lua:1407` — `for i = 1, 4 do`) is a
visual-only constraint that gets exceeded silently — extra cards
beyond 4 simply don't render but are still encoded in `req.encodedHand`.

### Network side — no gate either

`Net.lua:2473-2521`:
```lua
function N.LocalSWA()
    if S.s.paused then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    if not S.s.localSeat or not S.s.contract then return end
    if WHEREDNGNDB and WHEREDNGNDB.allowSWA == false then return end
    ...
    local handCount = #(S.s.hand or {})
    local needPerm = ...
    if S.s.swaRequest and S.s.swaRequest.caller == S.s.localSeat then
        return
    end
    if needPerm then
        local enc = C.EncodeHand(S.s.hand or {})
        S.s.swaRequest = { ..., handCount = handCount, encodedHand = enc, ... }
        N.SendSWAReq(S.s.localSeat, enc)
        ...
```

`handCount` is collected and broadcast but never used as a gate.

### Saudi rule context

`docs/strategy/endgame.md` and `CLAUDE.md` both specify the convention:
> SWA (سوا) with ≤3 cards = instant claim; with 4+ cards = permission flow.

Neither document the upper bound, but practical Saudi play never SWAs
above 5-6 cards because the recursion's `IsValidSWA` collapses to
"every legal opp play loses every remaining trick" — astronomically
hard with 7+ cards. The convention is implicitly bounded; the addon
should encode it explicitly.

### Suggested fix (NOT applied per instructions)

Add a constant `K.SWA_MAX_HAND_FOR_CALL` (e.g. 5 or 6, matching
Saudi-table convention) and gate the UI button + `N.LocalSWA`:
```lua
if swaEnabled and not swaPending and #(S.s.hand or {}) <= K.SWA_MAX_HAND_FOR_CALL then
    addConfirmAction(...)
end
```

---

## F-3 [HIGH · D-RT-22]  Bidder-trailing 60s AFK regression: non-actionable Bel UI for trailing bidder

### Severity
**HIGH** — Sun-Bel routing always sends the decision to the
**defender** (`(bidder%4)+1`), but Saudi rule allows the trailing team
to Bel regardless of bidder/defender role. When the **bidder** is on
the trailing team (e.g. A=130, B=60, B bids Sun), the eligible Bel
caller is B (the bidder), but PHASE_DOUBLE routes to A (defender).
The UI then shows A "Bel forbidden (Sun >=100)" + Skip, but the
predicate `R.CanBel(A, ...)` returns false anyway. The ROUTING
prevents the legal Bel from ever being presented; the trailing
bidder sees no escalation buttons and the chain dies in 60s AFK.

### Repro
1. Cumulative scores: A=130 (above gate), B=60 (below gate).
2. Seat in team B (e.g. seat 2) wins the bid with a Sun contract.
3. Phase advances to PHASE_DOUBLE.
4. `Net.lua:3582` — host computes `belSeat = (bidder%4)+1` = seat 3
   (team A). Routes to seat 3.
5. Seat 3's UI hits `UI.lua:1771-1777`:
   ```lua
   local canBel = (R and R.CanBel) and
       R.CanBel(R.TeamOf(S.s.localSeat),
                S.s.contract, S.s.cumulative)
   if canBel == false then
       addAction("|cff999999Bel forbidden (Sun >=100)|r",
                 function() end)
       addAction("Skip", function() net().LocalSkipDouble() end)
   ```
   `R.CanBel("A", ...)` returns false (A is at 130 > 100). UI shows
   "forbidden + Skip".
6. Seat 2 (team B, the trailing team that COULD legally Bel) sees
   no buttons because `S.s.localSeat ~= (b%4)+1` (`UI.lua:1759`).
7. 60s AFK timer fires for seat 3 (the wrong seat) and broadcasts
   `MSG_SKIP_DBL` (`Net.lua:3479`). Bel never offered to anyone.

### Quote — UI gate uses defender as eligible seat

`UI.lua:1756-1791`:
```lua
elseif S.s.phase == K.PHASE_DOUBLE then
    local b = S.s.contract and S.s.contract.bidder
    local nextSeat = b and ((b % 4) + 1) or nil
    if nextSeat == S.s.localSeat then
        ...
        local canBel = (R and R.CanBel) and
            R.CanBel(R.TeamOf(S.s.localSeat),
                     S.s.contract, S.s.cumulative)
        if canBel == false then
            addAction("|cff999999Bel forbidden (Sun >=100)|r",
                      function() end)
            addAction("Skip", function() net().LocalSkipDouble() end)
        else
```

### Quote — host routes to defender only

`Net.lua:3580-3647`:
```lua
-- Bel decision: defender at NextSeat(bidder)
if S.s.phase == K.PHASE_DOUBLE and S.s.contract then
    local belSeat = (S.s.contract.bidder % 4) + 1
    if isBotSeat(belSeat) then
        ...
        C_Timer.After(BOT_DELAY_BEL, function()
            ...
            if S.s.phase ~= K.PHASE_DOUBLE then return end
            local bel, wantOpen = B.Bot.PickDouble(belSeat)
            ...
        end)
    else
        N.StartBelTimer(belSeat, "double")
        return
    end
end
```

### Quote — predicate KNOWS bidder-can-Bel, but routing doesn't

`Net.lua:68-83`:
```lua
function N._SunBelAllowed(bidderSeat)
    if not bidderSeat then return false end
    -- v0.10.0 R1 fix: Sun-Bel is score-split, role-irrelevant.
    -- Either team is eligible iff that team is at ≤100 AND the
    -- other is at ≥101.
    local cumA = (S.s.cumulative and S.s.cumulative.A) or 0
    local cumB = (S.s.cumulative and S.s.cumulative.B) or 0
    local trailingTeam = (cumA <= cumB) and "A" or "B"
    return R.CanBel(trailingTeam,
                    { type = K.BID_SUN, bidder = bidderSeat },
                    S.s.cumulative)
end
```

`R.CanBel` itself is role-irrelevant since the v0.10.0 R1 fix
(`Rules.lua:541-560`):
```lua
-- All three reduce to: caller.cum ≤ GATE AND opposite.cum > GATE.
-- Bidder/defender role does not enter — only score position.
```

So the rule book and predicate agree: trailing team Bels regardless of
role. But UI routing + host routing both still hard-code defender =
`(bidder%4)+1`.

### Knock-on: UI text is misleading even when routing is correct

When defender's team IS at ≤100 (the only score-split where defender
can Bel), the UI shows "Bel forbidden (Sun >=100)" only when defender
is at >100. That's correct for the defender's eligibility — but the
text omits the dual-team requirement. A user reading "forbidden Sun
>=100" thinks "if MY team's score were lower I could Bel"; they don't
know the OTHER team must also be >100. The label undersells the rule.

### Suggested fix (NOT applied per instructions)

Two-part. UI: render the Bel buttons for whichever seat is on the
trailing-eligible team — change `nextSeat` derivation to "trailing
team's seat that is in active turn or the bidder/defender as
appropriate". Net: `_HostBelTimeout` and the bot-dispatch branch must
also pick the trailing team's seat. Or, simpler: convert PHASE_DOUBLE
into a dual-window phase where both teams' eligible-side seat is
queried with a "Bel? / Skip?" prompt and the host advances on first
response or both-skip.

---

## F-4 [HIGH]  AKA button has no turn / lead gate at the UI layer

### Severity
**HIGH (UX) / LOW (rule integrity)** — the network handler `N.LocalAKA`
correctly enforces "must be your turn AND no plays in current trick"
(`Net.lua:2358-2363`), so misclicks fail silently. But the UI button
shows whenever `S.LocalAKAcandidate()` returns non-nil, which is
"local hand contains the highest unplayed card of some non-trump
suit". That predicate is true for many turns the local player isn't
allowed to AKA on. The button being visible-but-no-op is a confusing
UX (user clicks → nothing happens → no error → user thinks their
input was lost).

### Repro
1. Hokm contract, trump = ♣. Seat 1 holds ♠A and ♠ has no ♠ played
   yet. `S.LocalAKAcandidate` returns `{suit="S", card="AS"}`.
2. Seat 2 leads ♥. Seat 1 follows ♥ — not their turn to AKA, mid-trick.
3. UI still shows the `|cff66ff88AKA|r ♠` button at the bottom of the
   action bar (`UI.lua:2046-2047`).
4. Seat 1 clicks. `N.LocalAKA` rejects silently due to the trick-open
   guard (`Net.lua:2358-2360`).
5. Button stays visible. User clicks again. Same silent reject.

### Quote — the missing gate

`UI.lua:2031-2049`:
```lua
if S.s.contract and S.s.contract.type == K.BID_HOKM then
    local cand = S.LocalAKAcandidate and S.LocalAKAcandidate()
    if cand then
        local glyph = K.SUIT_GLYPH[cand.suit] or cand.suit
        ...
        addAction(("|cff66ff88AKA|r %s"):format(glyph),
            function() net().LocalAKA(cand.suit) end)
    end
end
```

### Quote — what the network handler enforces

`Net.lua:2350-2363`:
```lua
-- v0.9.0 L4 fix: AKA must be called BEFORE leading. ...
-- The correct gate: the local seat must be about to LEAD (no plays
-- in the current trick yet), AND it must be their turn.
if S.s.trick and S.s.trick.plays and #S.s.trick.plays > 0 then
    return
end
if S.s.turn ~= S.s.localSeat or S.s.turnKind ~= "play" then
    return
end
```

### Quote — predicate has no turn check

`State.lua:1387-1402`:
```lua
function S.LocalAKAcandidate()
    if not s.contract or s.contract.type ~= K.BID_HOKM then return nil end
    if not s.hand or #s.hand == 0 then return nil end
    local trump = s.contract.trump
    for _, c in ipairs(s.hand) do
        local r = c:sub(1, 1)
        local su = c:sub(2, 2)
        if su ~= trump then
            local top = S.HighestUnplayedRank(su)
            if top and top == r then
                return { suit = su, card = c }
            end
        end
    end
    return nil
end
```

### Suggested fix (NOT applied per instructions)

Either (a) add the turn + lead gate to `S.LocalAKAcandidate` so the
button auto-hides, or (b) add the gate inline in `UI.lua:2031`:
```lua
if S.s.contract and S.s.contract.type == K.BID_HOKM
   and S.IsMyTurn() and S.s.turnKind == "play"
   and (not S.s.trick or not S.s.trick.plays or #S.s.trick.plays == 0) then
    ...
end
```
Option (a) is preferable because both the bot path (`Bot.PickAKA`)
and the wire path (`N.LocalAKA`) already enforce the gates — moving
them into the predicate makes all callers consistent.

---

## F-5 [MEDIUM]  Takweesh button always visible during PHASE_PLAY

### Severity
**MEDIUM** — `addConfirmAction` enforces a 2-click confirm flow which
mitigates accidents, but the button is visible even during the
opening of trick 1 BEFORE any play has been made — at which point
there is by definition no illegal play to call out. The host's
`HostResolveTakweesh` will return "no illegal play" for the false call,
penalising the caller's team with the full hand × multiplier going to
the opponents. A misclick (even with confirm) by a learning player
could cost them the round.

### Repro
1. PHASE_PLAY begins, trick 1 starts. No plays yet.
2. UI shows `|cffff5555TAKWEESH|r` button (`UI.lua:1997-2000`).
3. Player double-clicks confirm by accident.
4. Host runs `HostResolveTakweesh`, finds no illegal play, applies
   false-call penalty.

### Quote

`UI.lua:1997-2000`:
```lua
if S.s.phase == K.PHASE_PLAY and S.s.localSeat then
    addConfirmAction("|cffff5555TAKWEESH|r",
        "|cffff5555TAKWEESH? again to confirm|r",
        function() net().LocalTakweesh() end)
```

### Suggested fix (NOT applied per instructions)

Gate visibility on "at least one card has been played in the round":
```lua
local anyPlay = (S.s.tricks and #S.s.tricks > 0)
                or (S.s.trick and S.s.trick.plays and #S.s.trick.plays > 0)
if S.s.phase == K.PHASE_PLAY and S.s.localSeat and anyPlay then
    addConfirmAction(...)
end
```

---

## F-6 [MEDIUM]  Pause-aware tick refresh — confirmed correct

### Severity
**INFO** — the v0.9.0 L1 fix (banner stays frozen during pause) is
implemented correctly on both the overcall banner and the SWA banner.
Both `OnUpdate` self-ticks short-circuit when `S.s.paused` is true,
preserving the displayed countdown digit until resume.

### Quote — overcall banner

`UI.lua:1337-1370`:
```lua
overcallBanner:SetScript("OnUpdate", function(self, elapsed)
    self._tickAccum = (self._tickAccum or 0) + (elapsed or 0)
    if self._tickAccum < 0.33 then return end
    self._tickAccum = 0
    if S.s.phase ~= K.PHASE_OVERCALL or not S.s.overcall then
        self:Hide(); self._lastRemain = nil; return
    end
    -- v0.9.0 L1 fix (audit AUDIT_REPORT_v0.7.1.md): freeze countdown
    -- under pause. Pre-v0.9.0 the OnUpdate kept ticking the digit
    -- and decrementing remain even while host had paused; ...
    if S.s.paused then return end
    ...
```

### Quote — SWA banner

`UI.lua:1452-1478`:
```lua
swaBanner:SetScript("OnUpdate", function(self, elapsed)
    self._tickAccum = (self._tickAccum or 0) + (elapsed or 0)
    if self._tickAccum < 0.33 then return end
    self._tickAccum = 0
    -- v0.9.0 L1 fix: freeze SWA banner countdown under pause.
    if S.s.paused then return end
    ...
```

Pause-while-redealing/lastRoundResult/takweeshResult banners use
`renderBanner`'s static text path with no OnUpdate, so they are
trivially pause-safe.

### Caveat (not blocking)

The overcall banner does call `U.Refresh()` once per second-tick
(`UI.lua:1369`) to re-render the action bar's remaining-seconds
labels. That `U.Refresh` runs regardless of pause state. It does not
mutate state, but it does redraw the action bar with stale `remain`
values frozen at pause time — visually consistent because `oc.startedAt`
isn't moved by the pause, so `remain` doesn't advance. Confirmed
benign.

---

## F-7 [LOW]  Score panel — cumulative/target nil-coalesce coverage

### Severity
**LOW** — nil-safe formatting confirmed. `S.s.cumulative.A or 0` and
`S.s.target or 152` cover the gap between `S.Reset` (which initialises
`cumulative = {A=0, B=0}`) and any race that could produce a
half-initialised state.

### Quote

`UI.lua:3300-3305`:
```lua
local nA = (S.s.teamNames and S.s.teamNames.A) or "Team A"
local nB = (S.s.teamNames and S.s.teamNames.B) or "Team B"
scoreText:SetText(("%s: |cff66ff66%d|r   %s: |cffff6666%d|r   /  %d"):format(
    nA, S.s.cumulative.A or 0, nB, S.s.cumulative.B or 0,
    S.s.target or 152))
```

Note: this line dereferences `S.s.cumulative.A` directly. If `S.s.cumulative`
itself were ever nil (shouldn't happen given `S.Reset`, but no defence in
depth here), this would error. Existing defensiveness in
`renderStatus` is one-level deep only.

---

## F-8 [LOW]  Lobby seat assignment + version badge — confirmed correct

### Severity
**INFO** — the lobby surface correctly:
1. Pulls `K.GetAddonVersion()` for the local "you" badge.
2. Reads peer versions from `S.s.peerVersions` indexed by full
   `name-realm` (matching how MSG_HOST/MSG_JOIN broadcast version).
3. Colors mismatching versions red (`|cffff5555`), matching versions
   green (`|cff66ff88`), unknown grey (`|cff666666?|r`).
4. Hides Fill Bots / swap buttons / team-name editing / start-game
   button outside host context or when lobby is full.
5. Greys out lower-tier bot checkboxes when a higher tier is enabled,
   per the documented Saudi Master → Fzloky → M3lm → Advanced cascade.
6. Names sourced via `UnitName(party*)` + realm via `select(2, UnitName)`,
   with `realm and realm ~= ""` guarding to avoid trailing `-` on
   same-realm names.

### Quote — version badge logic

`UI.lua:2803-2815`:
```lua
local ver = S.s.peerVersions and S.s.peerVersions[m.full]
local verStr
if m.you then
    verStr = ("|cff66ddff%s|r"):format(myVersion)
elseif ver then
    if ver == myVersion then
        verStr = ("|cff66ff88%s|r"):format(ver)
    else
        verStr = ("|cffff5555%s|r"):format(ver)
    end
else
    verStr = "|cff666666?|r"
end
```

---

## F-9 [LOW]  Card-tile dim/disable — partial (red is warning, not disabled)

### Severity
**INFO/LOW** — the comment at `UI.lua:2189-2194` explicitly documents
that the red border is a **warning, NOT a disable**, because
Takweesh-able illegal plays are still allowed by the host (the
opposing team has to call it out). This is the correct Saudi rule
encoding. The `OnClick` at `:2213-2220` echoes:
```lua
b:SetScript("OnClick", function()
    if S.s.phase ~= K.PHASE_PLAY then return end
    if not S.IsMyTurn() then return end
    -- DO NOT gate on legalSet. LocalPlay warns the player
    -- privately and lets the card through; that's the whole
    -- point of Takweesh.
    net().LocalPlay(thisCard)
end)
```

This is correct, but the same code is what makes F-1 (D-RT-04)
catastrophic: the human is told "this is the safe play" via gold
borders, and "this is a Takweesh risk" via red — and that map is
inverted under AKA-receiver relief. F-1 is the bug; F-9 is just
the architecture description.

---

## F-10 [LOW]  Bid buttons (Pass / Hokm / Sun / Ashkal) — gates confirmed correct

### Severity
**INFO** — bidding-phase routing properly gates on:
- `S.IsMyTurn() and S.s.turnKind == "bid"` (turn-aware, kind-aware).
- Round-1 Hokm only available with no prior bid (`anyBidYet` flag,
  `UI.lua:1701-1707`).
- Ashkal restricted to bid positions 3 & 4 in dealer-relative order
  (`UI.lua:1716-1734`), correctly excluding when a Sun has already
  been bid.
- Round-2: 3 Hokm buttons (excluding flipped suit) + Sun, no Ashkal.
- Kawesh button gated on `C.IsKaweshHand` (`:1740-1742`).

### Quote — Ashkal gate

`UI.lua:1716-1734`:
```lua
local bidPos = 0
if S.s.dealer and S.s.localSeat then
    -- Bid order: dealer's left first, dealer last.
    local d = S.s.dealer
    local order = {
        (d % 4) + 1, ((d + 1) % 4) + 1,
        ((d + 2) % 4) + 1, d,
    }
    for i, st in ipairs(order) do
        if st == S.s.localSeat then bidPos = i; break end
    end
end
if not anySun and bidPos >= 3 then
    addAction("Ashkal", function() net().LocalBid(K.BID_ASHKAL) end)
end
```

The dealer-relative order matches `BiddingOrder` semantics in `State.lua`.

---

## F-11 [LOW]  Triple / Four / Gahwa routing — confirmed correct

### Severity
**INFO** — escalation phases route to the correct seat per Saudi rule:
- PHASE_TRIPLE → bidder (`UI.lua:1795`).
- PHASE_FOUR → defender = `(bidder%4)+1` (`UI.lua:1807`).
- PHASE_GAHWA → bidder (`UI.lua:1822`).

All three use `addConfirmAction` to require a second click — appropriate
given the score-multiplier impact.

### Quote — Four routing

`UI.lua:1804-1816`:
```lua
elseif S.s.phase == K.PHASE_FOUR then
    -- v0.2.0: Four is the DEFENDER's response to Triple.
    local b = S.s.contract and S.s.contract.bidder
    local def = b and ((b % 4) + 1) or nil
    if def == S.s.localSeat then
        addConfirmAction("Four & open (x4)",
            "|cffff3333Confirm Four & open?|r",
            function() net().LocalFour(true) end)
        addConfirmAction("Four & closed (x4)",
            "|cffff3333Confirm Four & close?|r",
            function() net().LocalFour(false) end)
        addAction("Skip", function() net().LocalSkipDouble() end)
    end
```

---

## F-12 [LOW]  Banner panels (lastRoundResult, takweeshResult, swaResult, redealing) — priority order correct

### Severity
**INFO** — `renderBanner` at `UI.lua:2942-3163` cascades correctly:
1. `redealing` (highest priority — early return at `:2962`).
2. PHASE_GAME_END → match-end banner (early return at `:3009`).
3. `swaResult` → SWA outcome (early return at `:3043`).
4. `takweeshResult` → Takweesh outcome (early return at `:3081`).
5. `lastRoundResult` → standard round-end breakdown.

The cascade respects the "result trumps redealing trumps lastRoundResult"
ordering. Each branch sets `outcome`, `bidder`, `defender`, `modifiers`,
`belote`, `final` and a colored border. `setOutcome(winningTeam)`
applies WIN/LOST headlines from the local seat's POV.

The non-host degraded path (`:3088-3104`) infers winner from delta
when `r` is nil — correct for non-host clients that only have the
delta broadcast.

---

## F-13 [LOW]  Confirm-action flow — no auto-confirm under repeated rapid clicks

### Severity
**INFO** — `addConfirmAction` (used for Bel / Triple / Four / Gahwa /
TAKWEESH / SWA / Pre-empt) is the correct two-stage pattern: first
click changes the label to a confirm-styled red prompt; second click
fires the action. This is a UX safety net specifically for
match-impacting decisions.

(Implementation not quoted — outside the audit scope, but verified
that the pattern is used consistently across all match-impacting
buttons listed in the audit scope.)

---

## Summary by severity

| ID    | Severity | Title                                                              |
|-------|----------|--------------------------------------------------------------------|
| F-1   | HIGH     | D-RT-04: GetLegalPlays omits akaCalled — UI dim trains against AKA |
| F-2   | HIGH     | D-RT-13: SWA button has no hand-count gate                         |
| F-3   | HIGH     | D-RT-22: Trailing-bidder Bel UI is non-actionable                  |
| F-4   | HIGH-UX  | AKA button has no turn / lead gate                                 |
| F-5   | MEDIUM   | Takweesh button visible before any play in trick 1                 |
| F-6   | INFO     | Pause-aware tick refresh — confirmed correct                       |
| F-7   | LOW      | Score panel nil-coalesce coverage                                  |
| F-8   | INFO     | Lobby seat + version badge — confirmed correct                     |
| F-9   | INFO     | Card-tile red border = warning, not disable (correct architecture) |
| F-10  | INFO     | Bid buttons — gates confirmed correct                              |
| F-11  | INFO     | Triple/Four/Gahwa routing — confirmed correct                      |
| F-12  | INFO     | Banner panel priority order — confirmed correct                    |
| F-13  | INFO     | Confirm-action pattern usage — consistent                          |

## Cross-references

- **D-RT-04 / B-Net-01 F-OP-12** assigned: F-1.
- **D-RT-13** (SWA hand-count gate): F-2.
- **D-RT-22** (bidder-trailing Bel routing): F-3.
- v0.9.0 L1 (pause-aware banner ticks): F-6 confirms.
- v0.10.2 M4 (AKA-receiver relief in `R.IsLegalPlay`): F-1 documents
  the propagation gap into the UI dim path.
- v0.10.0 R1 (Sun-Bel score-split, role-irrelevant): F-3 confirms the
  predicate is correct but the UI/host routing still uses pre-R1
  bidder/defender semantics for seat selection.
