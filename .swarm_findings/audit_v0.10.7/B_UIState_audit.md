# WHEREDNGN v0.10.7 Audit — UI.lua + State.lua

Commit: 3a70423 (v0.10.7).
Files audited:
- `C:\CLAUDE\WHEREDNGN\UI.lua` — 3,619 lines
- `C:\CLAUDE\WHEREDNGN\State.lua` — 2,189 lines

Severity tags: **HIGH** (correctness), **MED** (latent bug or subtle UX),
**LOW** (cleanup / micro-opt), **INFO** (verified-good or observation).

---

## State.lua

### S-1 [HIGH] `s.sweepTrackAnnounced` survives `ApplyResyncSnapshot` and may bleed across rounds for rejoiners
File: `State.lua`, lines 390–542 (`ApplyResyncSnapshot`) vs 794–796 (`ApplyStart`)
and 121 (`reset()`).

`reset()` and `ApplyStart` clear `s.sweepTrackAnnounced`. `RestoreSession`
also wipes (it does `for k in pairs(s) do s[k] = nil end` at line 315
before overlaying). But `ApplyResyncSnapshot` does **not** clear this
field — its explicit-clear list (lines 521–536) covers `akaCalled`,
`lastTrick`, `takweeshResult`, `swaResult`, `swaRequest`, `swaDenied`,
`redealing`, `pendingPreemptContract`, `preemptEligible`,
`lastRoundResult`, `lastRoundDelta` but skips `sweepTrackAnnounced`.

Scenario: client played round N where their team swept tricks 1–3
(flag set true), they got disconnected/leave-rejoin, the host sends
a fresh snapshot. The flag persists. If the new round (N+1) has a
3-trick sweep, the cue is suppressed on this client only — the rest
of the table hears it. Asymmetric audio bug.

Fix: add `s.sweepTrackAnnounced = nil` to the explicit-clear block
around lines 526–536, alongside the other per-trick / per-round
banner state. Also worth adding to the `TRANSIENT_FIELDS` list — the
v0.10.7 comment at line 120–121 implies "per-round one-shot" but
only `reset()` and `ApplyStart` clear it currently; if the host
/reloads in mid-round-N with the flag true, RestoreSession reapplies
the saved snapshot, which is fine because it was already true from
the previous trick-3 fire. So TRANSIENT marking is optional. The
ApplyResyncSnapshot gap is the real bug.

---

### S-2 [HIGH] `S.HighestUnplayedRank` returns nil when the suit is fully played, but ApplyTrickEnd's "obvious win" detection (b) treats nil as "trump pool empty" without distinguishing absent-trump-suit vs all-trump-played
File: `State.lua`, lines 1455–1490 (the v0.10.7 `SND_LAST_TRICK_WIN`
block in `ApplyTrickEnd`).

Code path lines 1486–1488:
```
elseif cardSuit ~= trump
   and not S.HighestUnplayedRank(trump) then
    obvious = true   -- Hokm: trump pool empty
end
```

`HighestUnplayedRank` returns nil if all 8 cards of that suit have
been played — but it ALSO returns nil at lines 1530 when `suit ==
""` or nil. In Hokm, `s.contract.trump` is always a real suit
("S"/"H"/"D"/"C"), so the first guard isn't hit. But there's a
subtler interaction: if no trump has been played AT ALL during the
round (rare but possible — e.g. trick 1 was non-trump, all 4 seats
followed suit), `HighestUnplayedRank(trump)` returns "J" (the boss),
not nil. So the cue won't fire prematurely. This branch is correct.

Re-reading more carefully: the cue fires "obvious=true" only when
`HighestUnplayedRank(trump)` is nil, meaning every trump rank has
been played. That's 8 plays of trump in a round of 32 plays. In a
typical round trumps come out in maybe 6–8 plays so this case
fires near the end of the round, which matches the cue's intent
("last trick win"). **No bug — verified-correct on review.** Demote
to INFO.

[Re-tagged INFO after second pass.]

---

### S-3 [MED] `S.ApplyPlay` trump-cut detection does not fire on the host's own SendPlay loopback — but DOES fire on host's local play via `N.LocalPlay → S.ApplyPlay`
File: `State.lua`, lines 1309–1334 (v0.10.7 `SND_TRUMP_CUT` block).

The audit prompt asks: "Verify: it doesn't fire on the host's own
SendPlay loopback (host bypasses _OnPlay's loopback). Verify the
trump-cut sound fires on ALL clients including host."

Tracing:
- Host clicks a trump card → `N.LocalPlay` (Net.lua:2086) → `S.ApplyPlay`
  directly (line 2111) → trump-cut block fires for the host.
- `N.LocalPlay` then calls `N.SendPlay` (line 2116).
- That broadcast loops back to the host's `_OnPlay` (Net.lua:1414),
  which is gated by `if fromSelf(sender) then return end`.
- Therefore `S.ApplyPlay` fires exactly once per host's own play (via
  LocalPlay), and the trump-cut cue fires once on the host. **Verified.**

For non-host clients:
- Host's broadcast → `_OnPlay` → `S.ApplyPlay` → trump-cut block fires.
- Their own play: `N.LocalPlay` → `S.ApplyPlay` (local) + `SendPlay`.
  Their own SendPlay loops back to themselves, gated by fromSelf.
  ApplyPlay runs once locally. Cue fires once.

**Verified-correct.** All clients hear the cue exactly once per
trump-cut event.

---

### S-4 [HIGH] Rapid trump cut on multiple subsequent trumps should only cue once per trick — verified, but the gate is on `trumpsBefore == 0` of the in-flight trick, which counts plays BEFORE the current one
File: `State.lua`, lines 1325–1334.

Loop:
```
for i, p in ipairs(s.trick.plays) do
    if i < #s.trick.plays and B.Cards.IsTrump(p.card, s.contract) then
        trumpsBefore = trumpsBefore + 1
    end
end
if trumpsBefore == 0 then
    B.Sound.Cue(K.SND_TRUMP_CUT)
end
```

Note that the current play has already been inserted into
`s.trick.plays` at line 1289, so `#s.trick.plays` includes it. The
loop iterates 1..n, skipping i==n (the current play). It counts
prior trumps. Single-trump-played-so-far → 0 prior trumps → cue
fires. Two trumps → second one sees 1 prior trump → no cue.

**Behavior verified-correct.** This handles the "pos-3 trumps after
pos-2 cut" case the comment at line 1318 calls out.

---

### S-5 [MED] `S.ApplyMeld` Hokm-Carré-A fix at lines 1180–1198 is correct, but Sun-Carré-A path has no fallback for missing `s.contract`
File: `State.lua`, lines 1180–1202.

```
if top == "A" then
    if s.contract and s.contract.type == K.BID_SUN then
        value = K.MELD_CARRE_A_SUN
    elseif s.contract and s.contract.type == K.BID_HOKM then
        value = K.MELD_CARRE_OTHER
    end
else
    value = K.MELD_CARRE_OTHER
end
-- 9 carrés (and 8/7) drop through with value=nil → not scored
if not value then return end
```

If `s.contract` is nil (very rare — meld arrives between contract
clear and contract apply, e.g., during PHASE_PREEMPT?), the Carré-A
path silently drops the meld with `value=nil → return`. `s.tricks`
length-1 gate at line 1159 already filters most of these, but a
mid-flight meld declaration during PHASE_PREEMPT would have
`s.contract = nil` (set at S.ApplyPreempt:2113) and could hit this
path. Trick-1 hasn't been played yet so the early gate doesn't
catch it.

In practice this is unreachable: meld declarations happen in
PHASE_DEAL3/PHASE_PLAY (per `S.GetMeldsForLocal:2143`), and
PHASE_PREEMPT clears `s.contract` only briefly before
`S.ApplyContract` reinstates it. But if the wire message order is
{MELD, CONTRACT} during a resync replay (host-controlled order
guarantees CONTRACT before MELD, but defensive: the validator
shouldn't depend on order), the meld would be silently dropped.

Suggestion: at line 1196, on `s.contract == nil`, default to
`K.MELD_CARRE_OTHER` (treating Carré-A as 100 raw — the safe lower
bound) rather than dropping. Low-impact in practice.

---

### S-6 [MED] `S.SaveSession` does NOT mark `swaRequest` as transient — comment says correct, but on a NON-host /reload the `swaRequest` bleeds and shows ghost Accept/Deny buttons
File: `State.lua`, lines 227–232.

Comment says swaRequest is intentionally NOT transient so the host
can continue collating votes. But this comment ignores the symmetric
case: a NON-host opponent who has to vote /reloads. Their saved
state has `swaRequest` non-nil. RestoreSession brings it back. They
see the Accept/Deny buttons (UI.lua:2026–2036). They click Accept.
`N.LocalSWAResp` fires.

But the host's `swaRequest` was likely already cleared (host's
HostResolveSWA or auto-approve fired during the rejoiner's downtime).
The host's `_OnSWAResp` will see `if not req` early-return at line
2680. The vote silently drops; the rejoining client has no feedback
that their click was a no-op.

Mitigation: ApplyStart line 818 wipes swaRequest at next round, so
this bug only manifests if the rejoiner /reloads, returns mid-same-
round during the auto-approve window expiry, and the host has
already moved on. Edge case, but the comment's reasoning at
lines 227–232 only justifies the HOST-/reload case, not the client
case.

Suggestion: when restoring, if the local seat is NOT the host AND
NOT the caller, drop swaRequest after a short post-restore delay
(e.g. 1.0s) if no fresh MSG_SWA_REQ has arrived. Not urgent.

---

### S-7 [LOW] `s.hostHands` is not explicitly cleared after `S.ApplyRoundEnd` — only at next `ApplyStart`
File: `State.lua`, lines 49 (init), 773 (ApplyStart), 1828
(HostDealInitial).

Between `ApplyRoundEnd` (line 1625) and the next `ApplyStart`,
`s.hostHands` lingers as `[seat]={}` arrays (since `ApplyPlay` at
line 1342–1344 removed each played card). The data is a
host-secret 0-card-each map at this point — not exploitable, but
violates the "secret state cleared at round end" intuition. If a
host /reloads in PHASE_SCORE, RestoreSession is short-circuited by
`s.phase == K.PHASE_SCORE` at line 254, so `hostHands` doesn't
persist to disk. So no SavedVariables leak. Pure cleanup hygiene.

---

### S-8 [HIGH] `RestoreSession`'s cross-character guard is correct (fail-closed at line 309), but `s.localName` may be nil on first-call depending on event order
File: `State.lua`, lines 291–311.

Comment block at 298–311 explicitly notes this concern and the
v0.9.2 #54 fail-closed fix correctly returns false when either side
is nil. The mitigation in `WHEREDNGN.lua:140` is to call
`B.State.SetLocalName(GetUnitName("player", true))` BEFORE
`RestoreSession`. Verified at WHEREDNGN.lua:87 (init) which runs
inside PLAYER_LOGIN before line 141 (RestoreSession). **Verified-good.**

---

### S-9 [MED] `S.ApplyTurn` meld-display hold logic at lines 866–881 fires only on `prevTurn ~= seat`, but doesn't fire on the seat's first turn-start when `prevTurn` is nil
File: `State.lua`, lines 866–881.

```
if kind == "play" and #(s.tricks or {}) == 1
   and prevTurn ~= seat
   and S.SeatHasDeclaredMelds and S.SeatHasDeclaredMelds(seat) then
```

`prevTurn ~= seat` correctly handles "the same seat plays again
later", but on the FIRST call after a phase transition, `prevTurn`
is whatever the previous `ApplyTurn` set it to — which could be the
same seat IF a duplicate ApplyTurn fires (e.g. the dispatcher
re-issues ApplyTurn for the same seat to refresh kind from "bid" to
"play"). In that case the `prevTurn ~= seat` guard would suppress
the meld reveal.

Re-reading: ApplyTurn for trick 2 always changes seat (the prior
trick winner ≠ the next-turn seat unless the same seat won AND
leads, which is normal). So this is unlikely. But if a duplicate
"refresh ApplyTurn" pattern emerges, the guard is brittle. Worth
the comment but not a current bug.

---

### S-10 [INFO] Sound module guard pattern (`if B.Sound and B.Sound.Cue`) is uniformly applied across State.lua
File: `State.lua` — 18 cue sites, all guarded.

Verified all 18 occurrences (grep results lines 825, 884, 908, 1072,
1112, 1130, 1151, 1307, 1320, 1380, 1391, 1425, 1611, 1644, 1666,
1702, 2064, 2116) follow the `if B.Sound and B.Sound.Cue` pattern
or the inline `if B.Sound and B.Sound.Cue then B.Sound.Cue(...)
end` form. Tests can no-op Sound by leaving B.Sound = nil.
**Verified-good.**

---

### S-11 [HIGH] `S.ApplyRoundEnd`'s sound priority cluster at lines 1665–1710 has a subtle "tied-deltas-no-stinger" gap
File: `State.lua`, lines 1702–1710.

```
local winnerTeam
if (addA or 0) > (addB or 0) then winnerTeam = "A"
elseif (addB or 0) > (addA or 0) then winnerTeam = "B" end
if winnerTeam and R.TeamOf(s.localSeat) ~= winnerTeam then
    B.Sound.Cue(K.SND_LOST_ROUND)
end
```

The comment at lines 1696–1697 says: "Tied deltas (rare; e.g.
all-pass redeal path) get no stinger." But all-pass redeal isn't
routed through `ApplyRoundEnd` — it's handled by the redeal flow
which doesn't call `R.ScoreRound`. So when WOULD addA == addB land
here? Only on a structural Takweesh tie or invalid SWA where both
sides come out at zero delta — an edge case that may or may not
exist. If it does, the silent loss-stinger gap is benign.

**Verified-acceptable.** Comment is misleading (all-pass redeal
isn't the example) but behavior is fine.

---

### S-12 [HIGH] `S.RestoreSession`'s rebuild of `playedCardsThisRound` at lines 343–355 includes the in-flight trick — verified-correct
File: `State.lua`, lines 343–355.

```
s.playedCardsThisRound = {}
for _, tr in ipairs(s.tricks or {}) do
    for _, p in ipairs(tr.plays or {}) do
        s.playedCardsThisRound[p.card] = true
    end
end
if s.trick and s.trick.plays then
    for _, p in ipairs(s.trick.plays) do
        s.playedCardsThisRound[p.card] = true
    end
end
```

This correctly rebuilds from completed tricks AND the in-flight
trick. The same code is duplicated at line 1297–1298 in ApplyPlay
(adds the just-played card) and the host re-broadcasts on resync
so the wire-side rebuild also works. **Verified-good.**

---

### S-13 [MED] `S.ApplyContract`'s idempotence guard at lines 1031–1043 protects escalation flags from being clobbered, but `s.belPending` is REWRITTEN on every duplicate call
File: `State.lua`, lines 1067–1069.

```
s.belPending = {}
local oppA = bidder == 1 or bidder == 3
if oppA then s.belPending = { 2, 4 } else s.belPending = { 1, 3 } end
```

If `S.ApplyContract` is called twice for the same contract, the
idempotence guard at line 1039–1043 returns early — so `s.belPending`
is only written on the first call. **Verified-good.**

But: the Sun overcall path at lines 1004–1011 mutates `s.contract`
in-place (changing bidder/type), then re-derives belPending. After
that, if a second `ApplyContract` arrived (network duplicate before
the overcall window resolution), the idempotence guard would see
the post-mutation contract values and might match or mismatch the
broadcast — depending on whether the broadcast carried pre- or
post-overcall fields. Need to double-check Net.lua's
HostFinishOvercall sends a fresh MSG_CONTRACT or just continues the
flow. (Out of audit scope; flagged for cross-check.)

---

### S-14 [INFO] `S.ApplyTrickEnd`'s LAST_TRICK_WIN cue is local-seat-only — correctly gated
File: `State.lua`, lines 1425.

`if B.Sound and B.Sound.Cue and s.localSeat and winner == s.localSeat`
ensures the cue only fires for the local player who won the trick.
Conservative on non-host clients (boss-of-suit checks use
`s.playedCardsThisRound`, which all clients maintain).
**Verified-good.**

---

## UI.lua

### U-1 [HIGH] `actionPanel` has no explicit show/hide — relies on `clearActions` to hide pooled buttons, which works, but the panel itself is anchored to handRow:TOP and is visible during PHASE_SCORE/PHASE_GAME_END
File: `UI.lua`, lines 1552–1554, 2058–2074.

The `Next Round` and `New Game` buttons appear via `addAction` for
host during PHASE_SCORE / PHASE_GAME_END (lines 2058–2074). For
non-host players in those phases, no buttons render — but the empty
actionPanel is still there (28px tall above handRow). Since handRow
is hidden during SCORE/GAME_END (per `Refresh:3374`), the empty
actionPanel sits in dead space. Not visible to user, just dead
geometry. **Pure cleanup, no impact.**

---

### U-2 [HIGH] Hand rendering's legal-set computation at line 2142 uses `S.GetLegalPlays()` which DOES pass `s.akaCalled` — verified
File: `UI.lua`, lines 2141–2142, vs `State.lua:2185`.

```
local legalSet = {}
for _, c in ipairs(S.GetLegalPlays()) do legalSet[c] = true end
```

`S.GetLegalPlays` (State.lua:2171–2189) passes `s.akaCalled` as the
6th arg to `R.IsLegalPlay`. **Verified — v0.10.4 fix applied.**

There is exactly ONE hand-rendering path in UI.lua (`renderHand` at
2133), so no other path bypasses the akaCalled fix. **Verified-good.**

---

### U-3 [MED] `renderHand` does not gate on `S.s.localPlayedThisTrick` for click handler — relies on `LocalPlay`'s gate
File: `UI.lua`, lines 2220–2227.

```
b:SetScript("OnClick", function()
    if S.s.phase ~= K.PHASE_PLAY then return end
    if not S.IsMyTurn() then return end
    -- DO NOT gate on legalSet. ...
    net().LocalPlay(thisCard)
end)
```

Click handler doesn't check `s.localPlayedThisTrick`. `LocalPlay`
(Net.lua:2095) does. So a rapid double-click triggers two
LocalPlay calls; the second early-returns at line 2095. Verified
behavior is safe — the second click is silently dropped, no double
play. **Verified-good.**

But there's a UX subtlety: between the click and the AppT.urn echo
back from the host, the card stays in the hand visually. A user
might click a SECOND, DIFFERENT card thinking the first didn't
register. That second click also hits the `s.localPlayedThisTrick`
gate and is dropped. But the user has no visual feedback for the
drop — the second card just sits there.

Suggestion: in renderHand's OnClick, set the local "I clicked
something" flag to grey-out the entire hand row visually until
ApplyPlay echoes back. Low priority.

---

### U-4 [HIGH] Bid button click handlers don't gate on `S.s.localPlayedThisTrick` (irrelevant — bid phase has no concept of "played this trick"), but they DO gate on `S.IsMyTurn()` and `S.s.turnKind == "bid"` via the outer phase check
File: `UI.lua`, lines 1683–1755.

The phase-correctness gate at line 1683 (`PHASE_DEAL1` or
`PHASE_DEAL2BID`) plus the inner `S.IsMyTurn() and S.s.turnKind ==
"bid"` check at line 1684 properly gate bid actions. The actual
buttons are created inside this gate, so they only EXIST when the
gate passes. **Verified-good.**

But the button click handlers themselves (e.g., line 1690
`function() net().LocalBid(K.BID_PASS) end`) don't re-check the
gate at click time. Between render-time and click-time, phase
might have changed (network event mid-render → mid-click). The
network handler `N.LocalBid` (Net.lua:1882) does its own gate,
which catches this case. **Verified-acceptable.**

---

### U-5 [HIGH] Escalation buttons (Bel/Triple/Four/Gahwa) DO use `addConfirmAction` with double-click confirmation
File: `UI.lua`, lines 1781–1827.

All 4 escalation buttons use `addConfirmAction`, which arms a 2-sec
window for the second click. Single misclick is harmless — UI
re-renders to clear the armed state. **Verified-good.**

---

### U-6 [MED] `addAction` button pool's confirm-arm reset at lines 1658–1659 is correctly applied — but pooled `armedTk` Cancel/clear runs on every render, which means a user mid-confirm-flicker gets disarmed by an unrelated U.Refresh
File: `UI.lua`, lines 1656–1660.

```
-- Reset any leftover confirm-arm state from a previous render so a
-- pooled button doesn't carry "armed" state into a new phase.
if b.armedTk then b.armedTk:Cancel(); b.armedTk = nil end
b.armed = false
```

Every time `addAction` (or `addConfirmAction`) is called, it
disarms the button. If the user clicks "Bel & open" once (now armed
showing "|cffff7755Confirm Bel & open?|r"), then a network event
triggers `U.Refresh` (e.g., a paused/resume mirror, a peer's lobby
update), `renderActions` runs `clearActions` then re-`addAction`s
the same button — armed state lost. The user clicks the second
time expecting confirmation, but the button is back to "Bel & open"
and arms again. The user must click TWICE more to actually fire.

Mitigation: most U.Refresh triggers during PHASE_DOUBLE are intentional
state changes that should disarm anyway (a network arrival of the
contract or a defender's bel resolution). But cosmetic refreshes
(team-name edit, theme switch) shouldn't disarm. Worth investigating
for users who hit it.

---

### U-7 [HIGH] `addAction` for the SWA "Decline" / Accept-Deny buttons does NOT use confirm-arm — single-click commits
File: `UI.lua`, lines 2032–2036.

```
addAction("|cff66ff88Accept SWA|r",
    function() net().LocalSWAResp(true) end)
addAction("|cffff5544Deny SWA|r",
    function() net().LocalSWAResp(false) end)
```

These should be safe enough — Accept is reversible (the host
collates votes; one accept doesn't end the round), and Deny just
stops the auto-approve countdown. But during a tense moment, a
misclick on Deny costs the team ~30 points. Compare to Takweesh
(line 2005), which DOES use confirm. Worth adding confirm to Deny
specifically: a false Deny is a bigger penalty than an accidental
Accept.

Suggested: change line 2034 to `addConfirmAction("|cffff5544Deny
SWA|r", "|cffff5544Confirm DENY?|r", function() ... end)`.

---

### U-8 [MED] AKA button at line 2053 uses `addAction` (single-click commit) — AKA is a strategic call with informational consequences, but a misclick is recoverable since the partner just "doesn't over-trump" until trick end
File: `UI.lua`, lines 2046–2055.

A misfired AKA tells the partner not to ruff this trick. If the
caller's claim is wrong (false AKA), they get a Qaid penalty per
v0.10.2 M3 (Takweesh-eligible). The single-click commit is
defensible — AKA is a soft signal, mistakes are expensive but
recoverable.

But the BUTTON only appears when the caller actually holds the
boss (per `S.LocalAKAcandidate()` filter). So a misclick fires a
LEGITIMATE AKA, which is fine; the only "mis" is calling AKA when
the user didn't intend to signal. UX-wise this means the user has
voluntarily clicked a button they don't want pressed — that's on
them.

**Verified-acceptable.** No change needed.

---

### U-9 [HIGH] `renderHand` does NOT visually disable the hand during opponent turns — cards are still hover-animated even when not the local player's turn
File: `UI.lua`, lines 2208–2219, 2191.

```
local isPlayable = (S.s.phase == K.PHASE_PLAY and S.IsMyTurn())
if isPlayable then
    if legalSet[card] then
        b:SetBackdropBorderColor(unpack(COL.legalEdge))
    else
        b:SetBackdropBorderColor(unpack(COL.badEdge))
    end
else
    b:SetBackdropBorderColor(unpack(COL.cardEdge))
end

local thisI, thisCard = i, card
b:SetScript("OnEnter", function(self)
    if isPlayable then
        ...
    end
end)
```

Hover-lift only on isPlayable; click handler at 2220 ALSO gates on
phase + isMyTurn. **Verified-good** — no opp-turn click leak.

---

### U-10 [HIGH] Theme system (`U.SetFeltTheme`) re-tints the captured frames at lines 3549–3579, but DOES NOT re-tint:
File: `UI.lua`, lines 3527–3582.

The function walks:
- seatBadges (line 3561–3564) — correct
- localBar (line 3566) — correct
- partyPanel (line 3567) — correct
- lobbyPanel.seatRows (line 3572–3574) — correct
- main frame outer rim (line 3579) — correct
- centerPad (line 3539–3543) — correct

NOT walked / re-tinted:
- `f.contractBg` (UI.lua:604–610) — uses hardcoded `{ 0.06, 0.10,
  0.07, 0.92 }` (not COL-derived), so theme-independent. OK.
- `pauseOverlay` (UI.lua:1269–1273) — hardcoded `{ 0, 0, 0, 0.55 }`.
  Theme-independent. OK.
- `akaBanner`, `overcallBanner`, `swaBanner`, `banner` — all use
  hardcoded colors at construction. Theme-independent. OK.

So all unwalked frames are intentionally theme-independent.
**Verified-complete.**

---

### U-11 [MED] `U.Show` at lines 3426–3467 force-reapplies `SetFeltTheme(activeFeltThemeName())` ONLY on `justBuilt = true` — subsequent shows skip this
File: `UI.lua`, lines 3451–3453.

```
if justBuilt and U.SetFeltTheme then
    U.SetFeltTheme(activeFeltThemeName())
end
```

This is the v0.10.4 fix for theme application after fresh frame
construction. It runs once, on first show. Subsequent shows
(toggle off and back on) don't re-trigger. That's fine because
the COL globals haven't been mutated between hides — frames retain
their tints.

But: if the user runs `U.SetCardStyle("burgundy")` while the frame
is hidden, then `U.Show()` while burgundy felt is also active,
`SetCardStyle` calls `applyThemeColors()` (line 3490) which mutates
COL. The next `U.Show` skips the SetFeltTheme reapplication
because `justBuilt` is now false. The frames built during a
previous burgundy session retain burgundy, so this is fine.

But edge case: SavedVariables hand-edited mid-session. Probably
not a concern. **Verified-acceptable.**

---

### U-12 [HIGH] `U.SetCardStyle` rebinds card-back textures and tints, BUT the hand cards (in `handPool`) are rebound only via `U.Refresh` → `renderHand`'s `SetTexture(path)` per card (line 2173–2179) — verified
File: `UI.lua`, lines 3486–3523, vs 2173–2179.

`SetCardStyle` calls `U.Refresh()` at line 3511. `Refresh` calls
`renderHand` (line 3377), which re-resolves `cardTexturePath(card)`
for each card. **Verified-good.**

---

### U-13 [HIGH] `centerCards` (the trick-area card slots) are rebuilt by `renderCenter` calling `setCardSlot` per slot — verified theme-aware
File: `UI.lua`, lines 2571–2645, vs 311–327.

`setCardSlot` calls `cardTexturePath(card)`, which honors the active
style. **Verified-good.**

---

### U-14 [MED] AKA banner and SWA banner inside `centerPad` at construction use `setBackdrop` with hardcoded RGBA (not COL-derived) — confirmed theme-independent. But the AKA banner uses `COL.legalEdge` for its border — verified mutated correctly across themes
File: `UI.lua`, lines 1295–1316.

`COL.legalEdge` is theme-INDEPENDENT (not in `applyThemeColors`).
It's hardcoded gold at line 153. So the AKA banner's gold border
is consistent across themes. **Verified-good.**

---

### U-15 [MED] Refresh triggers — comprehensive map
File: `UI.lua` and downstream.

Every U.Refresh trigger:
1. `S.ApplyRedealAnnouncement` (State.lua:156) — explicit refresh
   in C_Timer auto-clear.
2. Lobby actions (HostSwapSeats, HostAddBots) → `U.Refresh()`
   (UI.lua:727, 799).
3. Theme cycle buttons → `U.Refresh()` after `SetCardStyle` /
   `SetFeltTheme`.
4. Pause toggle (Net.LocalPause) — refresh via Net.lua's mirror.
5. Most state mutations rely on Net.lua dispatch handlers calling
   `B.UI.Refresh()`. Specifically:
   - `_OnLobby`, `_OnStart`, `_OnTurn`, `_OnBid`, `_OnContract`,
     `_OnPlay`, `_OnTrickEnd`, `_OnRoundEnd`, `_OnAKA` etc. all
     invoke `B.UI.Refresh()` at the end.

State mutations that DON'T trigger U.Refresh:
- `S.ApplyTeamNames` (State.lua:165–177) — caller responsibility.
  UI.lua's lobby-edit OnEnterPressed (line 660) calls U.Refresh
  after. Wire side `_OnTeams` in Net.lua needs verification (out
  of scope but worth flagging).
- `S.ApplyResyncSnapshot` (State.lua:390) — caller responsibility.
  Verify Net.lua's `_OnResyncRes` calls U.Refresh post-snapshot.
- `S.ApplyHand` (State.lua:830) — silent. UI's `renderHand`
  re-runs on next Refresh.

**Risk area:** if a state mutation doesn't propagate a refresh,
the UI shows stale info. The v0.10.6 round-end-stuck symptom
was exactly this. Worth a spot-check on Net.lua dispatch
handlers as a separate audit.

---

### U-16 [LOW] Reset button at lines 522–526 triggers a StaticPopup confirm — good UX, verified
File: `UI.lua`, lines 493–535.

The Blizzard StaticPopup is correctly used. **Verified-good.**

---

### U-17 [HIGH] `peekLastTrick` at lines 2652–2673 has phase gate at 2663–2665 (`PHASE_PLAY` or `PHASE_DEAL3` only) — verified, no leak into SCORE
File: `UI.lua`, lines 2652–2673.

Comment at 2658–2662 explains the phase gate fix. **Verified-good.**

---

### U-18 [MED] `renderActions` PHASE_SCORE/GAME_END "Next Round" / "New Game" gate on `S.s.isHost` only — but a spectator host (no localSeat but `isHost == true`) is filtered by the global guard at line 1682
File: `UI.lua`, lines 1682, 2058–2074.

Line 1682: `if not S.s.localSeat then return end` — early-returns
the entire `renderActions`. So a spectator host (theoretical edge
case) wouldn't see the Next Round button. But: a host always
occupies seat 1 (per `HostBeginLobby:617` `s.localSeat = 1`), so
this case shouldn't arise. **Verified-defensive.**

---

### U-19 [MED] Bid label rendering for opponents (line 2344 `bidLabelForSeat`) correctly uses Latin transliteration ("wla") for Pass — no Arabic glyph rendering issues
File: `UI.lua`, lines 2344–2373.

Comment at 2352–2358 explains the bundled-font Arabic glyph
limitation. **Verified-good.**

---

### U-20 [HIGH] Qablak Latin label fix at line 1959 is in place — verified
File: `UI.lua`, line 1959.

`addConfirmAction("|cff66ddffQablak (Pre-empt)|r", ...)`.

Comment at lines 1944–1952 explains the v0.10.3 fix. **Verified-good.**

Other Arabic-glyph audit:
- AKA button (line 2053): "AKA" Latin — fixed.
- Qablak button (line 1959): "Qablak" Latin — v0.10.3 fix.
- Bid label "wla" / "Pass" (line 2359): Latin — fixed.
- Bot tier checkboxes "M3lm" / "Fzloky" (lines 856, 866): Latin
  transliterations.

**No other hardcoded Arabic glyphs in button labels.** The actual
Arabic word إكَهْ appears only in the audio cue (which renders
correctly because audio doesn't use the bundled fonts).

---

### U-21 [LOW] Hand button hover-lift OnLeave at lines 2215–2219 always re-anchors at y=0, even if the button was never raised
File: `UI.lua`, lines 2215–2219.

```
b:SetScript("OnLeave", function(self)
    self:ClearAllPoints()
    self:SetPoint("CENTER", tablePanel.handRow, "CENTER",
        startX + (thisI - 1) * (btnW + 6), 0)
end)
```

Always-anchor is harmless but wasteful — re-anchors a frame that
was already at the correct anchor. **Pure micro-opt.**

---

### U-22 [MED] `renderHand` does not pool/reuse the hand-card buttons across `clearHand` calls cleanly — `clearHand` only `Hide()`s pooled buttons but doesn't release click scripts before reassignment in `renderHand`
File: `UI.lua`, lines 2120–2131, 2207–2227.

`clearHand` (2120) does:
```
b:SetScript("OnClick", nil)
b:SetScript("OnEnter", nil)
b:SetScript("OnLeave", nil)
```

`renderHand` then re-assigns. So pooling is correct — the same
8 button frames are reused across rounds. No frame-creation
churn. **Verified-good.**

---

### U-23 [MED] Action button pool has no upper bound — pooled Buttons accumulate via `addAction` if a phase happens to add more buttons than seen before
File: `UI.lua`, lines 1604, 1644–1648.

`actionPool` and `actionUsed` track. `addAction` does
`actionUsed = actionUsed + 1; b = actionPool[actionUsed]; if not b
then b = makeButton(...) end`. So new buttons are created on
demand and live in the pool indefinitely. Across phases, the
pool grows to the maximum actions ever seen. In practice this is
~6 buttons (overcall non-bidder: TAKE, TAKE_HOKM, WAIVE, plus
TAKWEESH, SWA, AKA). **Verified-bounded.**

But: SWA banner's `cardSlots` (line 1406) creates 4 once and
reuses. Hand buttons (`handPool`) cap at 8 (max hand). All
pooled. **No leak.**

---

### U-24 [LOW] Center-trick animation (`animateLand` at 2530–2569) uses `C_Timer.NewTicker` with no cancel-on-hide path
File: `UI.lua`, lines 2530–2569.

If `U.Hide` runs mid-animation, the ticker keeps poking the hidden
frame's anchor (no error, just CPU). Self-cancels at line 2562.
Acceptable. **Pure micro-opt.**

---

### U-25 [HIGH] `U.PulseTurn` (lines 3401–3424) tracks `_pulseTicker` and cancels stale ones — verified
File: `UI.lua`, lines 3400–3423.

Comment at 3395–3399 explains the v0.9 audit fix. The ticker is
cancelled on re-arm. **Verified-good.**

---

### U-26 [MED] Score display at `renderStatus` (line 3304–3349) uses team names from `S.s.teamNames` with fallback to "Team A" / "Team B"
File: `UI.lua`, lines 3304–3349.

Fallback correctly handles missing or empty custom names. **Verified-good.**

---

### U-27 [HIGH] Banner rendering for round-end is correctly differentiated:
- Sweep (Al-Kaboot): line 3123 yellow border
- Made: line 3134 green border
- Failed: line 3130 red border
- SWA-valid: line 3035 green
- SWA-invalid: line 3042 red
- Takweesh-caught: line 3071 red
- Takweesh-false: line 3080 red
- Redeal: line 2962 (priority over score states)

Verified all branches present and use distinct color codes.
**Verified-good.**

---

### U-28 [LOW] `renderBanner` at line 2949 has fall-through to "Hide" at 2972–2974 if phase is neither SCORE nor GAME_END nor redealing — correct phase guarding
File: `UI.lua`, lines 2972–2974.

**Verified-good.**

---

### U-29 [MED] `renderSeats` for spectators (no localSeat) uses team-A/team-B coloring fallback — verified at line 2399–2403
File: `UI.lua`, lines 2375–2473.

Spectator branch at 2462–2474 handles: hide localBar, show
specInfo with seat 1's name + count. **Verified-good.**

---

### U-30 [HIGH] Pause overlay's Resume button is bumped to FULLSCREEN_DIALOG strata so host can click it — verified at line 1289
File: `UI.lua`, lines 1265–1289.

Comment at 1282–1289 explains the strata bump. **Verified-good.**

---

### U-31 [MED] Click handlers for the bid panel buttons capture `S.s.bidCard` at render time as `flippedSuit` (line 1691). If the bid card changes between render and click (e.g., a redeal landed), the captured `flippedSuit` is stale
File: `UI.lua`, lines 1691, 1704–1707.

```
local flippedSuit = S.s.bidCard and C.Suit(S.s.bidCard) or nil
if S.s.phase == K.PHASE_DEAL1 then
    ...
    if flippedSuit and not anyBidYet then
        addAction("Hokm "..K.SUIT_GLYPH[flippedSuit], function()
            net().LocalBid(K.BID_HOKM..":"..flippedSuit)
        end)
    end
```

The closure captures `flippedSuit` at render time. If a rare
network reorder causes `S.s.bidCard` to mutate after render but
before click, the click sends a Hokm bid with the WRONG suit.
The host's `_OnBid` would parse the bid and insert it with the
old suit, which doesn't match the new bid card.

In practice, network mutations of `s.bidCard` mid-bid are very
rare (only happens in a redeal flow which clears phase to DEAL1
and re-shows the bid card; render fires immediately after).
**Defensive but no current bug.**

Suggestion: in the click closure, re-read `S.s.bidCard` and call
`C.Suit` fresh, instead of capturing `flippedSuit` at render.
Mild correctness/clarity improvement.

---

### U-32 [HIGH] Overcall TAKE_HOKM buttons compute the best Hokm trump at click-time via `bestHokmTake()` (lines 1880–1909) — verified, dynamic
File: `UI.lua`, lines 1879–1919.

`bestHokmTake` is called inside the OnClick closure (line 1910 is
at render time; the closure body at 1916–1918 calls it again? Let me
re-read):

```
local takeHokmSuit = bestHokmTake()
if takeHokmSuit then
    addAction(
        ("|cffffaa55Take as Hokm %s|r"):format(...) .. rTag,
        function()
            net().LocalOvercall("TAKE_HOKM_" .. takeHokmSuit)
        end)
end
```

Actually `takeHokmSuit` is captured at render time (line 1910).
The OnClick uses the captured value. Same staleness risk as U-31 —
if the local hand changed between render and click (very unlikely
during the 5s overcall window), the captured suit might be wrong.

In practice the local hand is stable during the overcall window
(no plays happen, no bids change). **Verified-acceptable.**

---

### U-33 [MED] Banner rendering for `S.s.takweeshResult` and `S.s.swaResult` runs in PHASE_SCORE — but `s.takweeshResult` is also set in PHASE_PLAY paths (when a Takweesh fires mid-trick). Does the banner render during PLAY?
File: `UI.lua`, lines 2972–2974, 3024.

```
if S.s.phase ~= K.PHASE_SCORE and S.s.phase ~= K.PHASE_GAME_END then
    banner:Hide(); return
end
```

So the round-end banner is hidden outside SCORE/GAME_END. A
mid-PLAY Takweesh sets `takweeshResult` AND ends the round
(transitions to PHASE_SCORE) at the same time. By the time
`renderBanner` reads, `phase == PHASE_SCORE`. **Verified-correct.**

---

### U-34 [LOW] `renderLobby` at line 2685–2699 iterates seats unconditionally, marking empty ones — no out-of-bounds risk since lobbyPanel.seatTexts has exactly 4 entries
File: `UI.lua`, lines 2685–2699.

**Verified-good.**

---

### U-35 [MED] Theme cycle button OnClick at lines 904–915 wraps around the list — correct cycling, no off-by-one
File: `UI.lua`, lines 904–915.

```
local idx = 1
for i, t in ipairs(list) do if t.id == active then idx = i end end
local nextEntry = list[(idx % #list) + 1]
```

Standard wraparound. **Verified-good.**

---

## Cross-cutting findings

### X-1 [HIGH] State→UI refresh dependency is implicit; only documented by Net.lua dispatch handler conventions, not enforced
Files: throughout.

The pattern is "every state mutation that affects UI must be
followed by `B.UI.Refresh()` from the Net.lua dispatch site".
This is fragile — adding a new `S.Apply*` function and forgetting
the refresh is silent. The v0.10.6 round-end-stuck bug (per audit
brief) was exactly this.

Suggestion: refactor toward a state-mutation hook pattern (every
`S.Apply*` invokes a single dispatch fn that calls all registered
listeners, including `B.UI.Refresh`). High-value but high-effort
refactor. Track separately.

---

### X-2 [MED] Sound module guard pattern is uniform but verbose — 18 occurrences in State.lua duplicate the `if B.Sound and B.Sound.Cue` check
Files: State.lua (18 sites).

Consider a `local function cue(snd) if B.Sound and B.Sound.Cue
then B.Sound.Cue(snd) end end` helper at the top of State.lua.
Tests still no-op when B.Sound is nil. **Pure cleanup.**

---

### X-3 [HIGH] v0.10.7 sound cue placements verified
Cues added in v0.10.7:
- `SND_TRUMP_CUT`: ApplyPlay line 1320–1334. ✓
- `SND_SWEEP_TRACK`: ApplyTrickEnd line 1391–1401. ✓
- `SND_LAST_TRICK_WIN`: ApplyTrickEnd line 1425–1497. ✓
- `SND_HOKM_LOST`, `SND_KABOOT`, `SND_KABOOT_AGAINST`,
  `SND_LOST_ROUND`: ApplyRoundEnd lines 1644–1710. ✓
- `s.sweepTrackAnnounced` lifecycle: clear in `reset()` (121),
  `ApplyStart` (796). ✗ NOT cleared in `ApplyResyncSnapshot`
  (S-1 above).

**One identified gap (S-1).**

---

## Summary of action items

| ID  | Severity | Location | Issue |
|-----|----------|----------|-------|
| S-1 | HIGH     | State.lua:521–536 | Add `s.sweepTrackAnnounced = nil` to ApplyResyncSnapshot wipe block |
| S-5 | MED      | State.lua:1196 | Carré-A null-contract path silently drops meld; default to MELD_CARRE_OTHER |
| S-6 | MED      | State.lua:227 | Non-host /reload during SWA vote leaves ghost buttons |
| S-13| MED      | State.lua:1067 | (defensive) `belPending` recomputation post-overcall — verify Net.lua's HostFinishOvercall doesn't broadcast a 2nd MSG_CONTRACT |
| U-3 | MED      | UI.lua:2220 | Hand click misclick visual feedback gap |
| U-6 | MED      | UI.lua:1656 | Confirm-arm state lost on cosmetic Refresh |
| U-7 | HIGH     | UI.lua:2034 | "Deny SWA" button should use addConfirmAction |
| U-31| MED      | UI.lua:1691 | Captured `flippedSuit` stale across redeal |
| X-1 | HIGH     | (cross-file) | State→UI refresh dependency is implicit, fragile |
| X-2 | MED      | State.lua | 18 Sound guards — refactor to `cue()` helper |

All other findings are INFO / verified-good (the v0.10.4 / v0.10.6 /
v0.10.7 fixes are correctly applied and intact).
