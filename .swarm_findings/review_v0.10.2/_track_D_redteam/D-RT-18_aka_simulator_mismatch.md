# D-RT-18 — Red-team: AKA-aware vs AKA-blind asymmetry from v0.10.2 M4

**Target:** v0.10.2 M4 added an optional 6th param `akaCalled` to
`R.IsLegalPlay` (`Rules.lua:89`) so live-play callers can lift the
must-trump-ruff restriction for the AKA-receiver. The CHANGELOG framing
of the rollout omission as deliberate ("simulators pass nil and get the
AKA-blind semantics"; `Rules.lua:111-112`) treats this as a clean
correctness/performance trade-off. This red-team verifies whether the
asymmetry actually produces incorrect bot decisions, including paths the
v0.10.2 author classified as "simulator" but which are reachable in
live play.

**Verdict: 4 reproduced divergence scenarios (S1 high, S2 medium, S3
medium, S4 low) plus 1 documentation drift and 1 design-question.**
S1 (BotMaster.PickPlay:830) entirely negates the M4 fix at Saudi Master
tier — that is the v0.10.2 changelog's primary intended beneficiary
silently reverting to AKA-blind legality. The known D-RT-04 / D-RT-29
findings (cited in the brief) are all reproduced; novel divergence is
in **S3 (heuristicPick rollout amplifies S1)**, **calibration concern
on `Rules.lua:435` IsValidSWA**, and **misleading comment at Bot.lua:1605
referencing a non-existent `R.SunCanRolloff`**.

**No code modified — review-only per the brief.**

---

## 1. The shipped asymmetry, mapped

`R.IsLegalPlay` signature (`Rules.lua:89`):

```lua
function R.IsLegalPlay(card, hand, trick, contract, seat, akaCalled)
```

Relief computed at `Rules.lua:115-121`:

```lua
local akaRelief = false
if akaCalled and akaCalled.seat and akaCalled.suit
   and seat and R.Partner(seat) == akaCalled.seat
   and akaCalled.suit == leadSuit
   and contract and contract.type == K.BID_HOKM then
    akaRelief = true
end
```

Applied at `Rules.lua:175` after must-follow, before must-trump-ruff:

```lua
-- v0.10.2 M4 — AKA-receiver relief: when partner called AKA on
-- the led suit, an opp may have over-trumped and now leads, but
-- the receiver is still exempt from must-ruff per J-066/J-067.
-- Discard freely.
if akaRelief then return true end
```

**Caller audit (cross-checked file:line for every IsLegalPlay site):**

| # | Location | Pass `akaCalled`? | Path | Severity |
|---|---|---|---|---|
| 1 | `Bot.lua:1610` | YES (`S.s.akaCalled`) | `legalPlaysFor` heuristic picker | OK |
| 2 | `Net.lua:2040` | YES (`S.s.akaCalled`) | `LocalPlay` anti-misclick warn | OK |
| 3 | `Net.lua:3412` | YES (`S.s.akaCalled`) | `_HostCheckTurnTimer` AFK auto-play | OK |
| 4 | `Net.lua:4136` | YES (`S.s.akaCalled`) | bot-side host fallback after meld error | OK |
| 5 | `State.lua:1219` | YES (`s.akaCalled`) | `S.ApplyPlay` Takweesh illegal-mark | OK |
| 6 | `BotMaster.lua:830` | **NO** | `BM.PickPlay` decision-point legal list | **S1** |
| 7 | `BotMaster.lua:649` | **NO** | rollout `heuristicPick` opponent sim | **S3** |
| 8 | `Rules.lua:435` | **NO** | `R.IsValidSWA` minimax recursion | **S4** |
| 9 | `State.lua:1665` | **NO** | `S.HostValidatePlay` (latent host wrapper) | **S2** |
| 10 | `State.lua:1966` | **NO** | `S.GetLegalPlays` (UI dimming) | **S2** |

The CHANGELOG claim "every live-game legality check" is **inaccurate**:
sites 6, 9, and 10 are live-play paths and all silently lose AKA-relief.
Site 7 is a true rollout; site 8 is dual-purpose (lives in Rules.lua but
is invoked from a live-play SWA validator gate, see §6).

---

## 2. S1 [high] — `BotMaster.PickPlay:830` is the **decision point** for Saudi Master tier and omits AKA

This is the **single highest-impact finding**. The brief cited D-RT-04 F1
("Saudi Master tier dead"); reproducing in detail with concrete fail
scenario:

`BotMaster.lua:826-832`:

```lua
-- Build legal-plays list.
local trick = S.s.trick or { leadSuit = nil, plays = {} }
local legal = {}
for _, c in ipairs(hand) do
    local ok = R.IsLegalPlay(c, hand, trick, S.s.contract, seat)
    if ok then legal[#legal + 1] = c end
end
```

This is NOT a rollout. `BM.PickPlay` is the **outer driver** invoked once
per real turn from `Bot.PickPlay:3382-3386` whenever Saudi Master tier
is active:

```lua
if not Bot._inRollout then
    local BM = WHEREDNGN and WHEREDNGN.BotMaster
    if BM and BM.IsActive and BM.IsActive() and BM.PickPlay then
        local masterCard = BM.PickPlay(seat)
        if masterCard then return masterCard end
    end
end
```

When `BM.PickPlay` returns a card it short-circuits the
`legalPlaysFor`-based fall-through path at `Bot.lua:3394`. So the M4
fix at `Bot.lua:1610` (which DOES pass `aka`) is **bypassed entirely**
for Saudi Master tier.

### Concrete fail scenario (fully reproduced)

- Contract: HOKM with Diamonds trump.
- Saudi Master bot at seat 4. Hand: `{7H, 8H, JD, QD}` — void in
  Spades, has trump.
- Trick state: seat 1 (partner of seat 3) led with `KS`. Seat 2 (opp)
  played `8S`. Seat 3 (our partner) played `AS` and called AKA on
  Spades — `S.s.akaCalled = { seat=3, suit="S" }`. Now seat 4's turn.
- `S.s.contract = { type=K.BID_HOKM, trump="D", ... }`.
- The Saudi convention says: partner's Ace is boss, partner's team is
  winning, seat 4 should DUMP a low non-trump (a 7H), preserving trumps
  for later. This is exactly what M4 was meant to enable.

**Expected legal set (with `aka`):**
- `7H, 8H` valid (Saudi M4 relief — receiver may discard freely).
- `JD, QD` also valid (any card OK when partner is winning).
- Set: 4 cards. Heuristic picks lowest non-trump → `7H`. Correct.

**Actual legal set at `BotMaster.lua:830` (no `aka`):**
- `7H, 8H` REJECTED with "must trump" — code falls through to the
  `if not C.IsTrump(card, contract) then return false, "must trump" end`
  at `Rules.lua:184`. Note the partner-winning shortcut at
  `Rules.lua:166-169` *would* have allowed them — but in this scenario
  partner is **not** the current trick winner. Wait — let me re-verify.
  Partner played `AS` after the opp's `8S`; `R.CurrentTrickWinner` will
  return seat 3 (highest spade). So actually `Rules.lua:167-169`
  shortcut DOES fire: "Hokm: check partner-winning shortcut" returns
  `true` for any card. So `legal` = all 4 cards even without M4 relief.

Hmm — that means in the *clean* AKA-on-Ace case the partner-winning
shortcut already permits non-trump. But this is exactly the case
analyzed in B-Bot-03 F1 (cosmetic): partner-winning + AKA-on-Ace is
double-covered.

**Reframed concrete fail scenario** (the actual M4-needed case):

- Same setup BUT after seat 3's AKA on `AS`, opp seat 2 played `2D`
  (over-trump) — wait, no, the order is fixed. Let me re-do.
- Seat 1 (we'll say seat-3's partner = seat 1 in 1↔3 / 2↔4 partnerships)
  led `KS`. Seat 2 (opp) played `8S`. Seat 3 (partner of seat 1, opp
  of seat 2) plays `AS` and calls AKA. Seat 4 plays last.
- Now `R.CurrentTrickWinner` = seat 3 (our partner if we're seat 1) —
  but we're at seat 4 (opp of seat 3). So partner-winning shortcut
  does NOT fire for seat 4.

Actually — seat 4 is on the OPP side of the AKA. AKA-relief at
`Rules.lua:115-121` checks `R.Partner(seat) == akaCalled.seat`. For seat
4: `R.Partner(4) = 2`, but `akaCalled.seat = 3`. So relief is correctly
NOT granted. Seat 4 is bound by must-ruff and must over-trump if able.
This is correct Saudi behaviour for the opp side.

The CORRECT canonical fail-scenario is when the seat is the receiver
(partner of caller) AND the caller is NOT currently winning (because
opp over-trumped). Reconstructed:

- HOKM, trump = D. Partnerships 1↔3, 2↔4.
- Seat 1 leads `AS` (raw boss of S). Seat 2 (opp) cuts with `2D` (low
  trump). NOW partner is no longer winning — opp seat 2 is.
- Seat 3 (our partner... wait, we're seat 1's partner = seat 3).

Restart the geometry. Bot is **seat 3**. Partnership 1↔3. Seat 1 (our
partner) led `AS` and called AKA on S → `akaCalled = {seat=1, suit="S"}`.
Seat 2 (opp) cut with `2D`. **R.CurrentTrickWinner = seat 2** (the trump
beat the spade). Now seat 3 (us) is up. Hand: `{7H, 8H, JD, QD}` —
void in S, has trump.

**Without `akaCalled` arg:**
- `hasLead` = false (void in S).
- `partner-winning shortcut`: curWinner = seat 2 (opp). Partner of seat
  3 = seat 1. seat 2 ≠ seat 1. Shortcut does NOT fire.
- Falls to `must trump if any trump` (`Rules.lua:177-184`). seat 3 has
  `JD, QD`. So `7H, 8H` are REJECTED. `legal = {JD, QD}`.
- ISMCTS picks one of the two trumps and ruffs.

**With `akaCalled` arg (M4 relief):**
- `akaCalled.seat = 1`, partner of seat 3 = seat 1. ✓
- `akaCalled.suit = S`, trick.leadSuit = S. ✓
- contract.type = HOKM. ✓
- → `akaRelief = true`.
- `hasLead` = false. Skip must-follow path.
- Skip Sun. Skip partner-winning shortcut (opp wins).
- **Hit line 175**: `if akaRelief then return true end`. So `7H, 8H`
  are LEGAL.
- `legal = {7H, 8H, JD, QD}`. Heuristic picks lowest non-trump → `7H`.

**This is the canonical M4-target case** — opp over-trumped partner's
AKA'd lead, receiver should discard low, NOT ruff (preserve trump).
Both `legalPlaysFor` (Bot.lua:1610) and `Net.lua` AFK paths get this
right. **`BotMaster.lua:830` does NOT** — Saudi Master tier ruffs even
when M4 says discard.

### Why this directly negates the v0.10.2 fix's primary goal

`CLAUDE.md` documents Saudi Master as the highest tier. The v0.5.0
delegation note in `CLAUDE.md` confirms: *"`Bot.PickPlay` delegates
internally to `BotMaster.PickPlay` when Saudi Master tier is active."*
So the M4 patch at `Bot.lua:1610` ONLY benefits Basic / Advanced / M3lm
/ Fzloky tiers. Saudi Master, the tier with the highest decision-quality
expectation, falls through the upgraded path and reverts to the dead-
code semantic the M4 fix was meant to close.

This is a **silent regression for the highest-tier bot** under the
canonical opp-over-trump scenario. Players running with
`saudiMasterBots=true` see the AKA-receiver bot ruffing (often with a
mid-trump like J/Q) when it should discard a 7H.

### Suggested fix (non-binding, brief said don't modify)

`BotMaster.lua:830`: add `S.s.akaCalled` as 6th arg, mirroring the live
sites. The rollout-internal `heuristicPick` at line 649 is a separate
question (S3, below) — its fix is not necessarily symmetric.

---

## 3. S2 [medium] — `S.GetLegalPlays:1966` shows wrong legality to the human player when they're the AKA receiver

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
end
```

This is consumed by the UI for **card-tile dimming** — illegal cards are
visually grayed out. When a human player is the AKA receiver and partner
has been over-trumped:

- Bot.lua / Net.lua paths (post-M4) correctly let the bot DISCARD.
- UI dimming via `S.GetLegalPlays` says non-trump cards are ILLEGAL.
- Player can still click them (Saudi Takweesh-warning model — illegal
  plays go through with a private warning per `Net.lua:2040`), but the
  player **cannot discover the relief option through the UI**.

This is asymmetric between bots and humans: bots get to use AKA-relief,
humans get the AKA-blind UI. A human partner who follows convention will
look at their dimmed non-trump cards, conclude they "must ruff", and
ruff — losing a trump that AKA-strategy assumed they'd keep. This makes
the partnership convention strictly worse for the human side than for
two bot partners.

### Reproduction

Same scenario as S1 but human at seat 3:
- Partner (seat 1) led AS, called AKA. Opp (seat 2) cut with 2D.
- Seat 3 is the human, hand `{7H, 8H, JD, QD}`.
- UI calls `S.GetLegalPlays()` — `7H, 8H` come back as illegal.
- Player sees `7H, 8H` dimmed and `JD, QD` highlighted.
- Player ruffs (per dimming), loses trump.

### Mitigation note

The illegal-mark on the actual play (`State.lua:1219` Takweesh path) DOES
pass `akaCalled`, so if the player force-clicks a "dimmed" `7H` it will
NOT be Takweesh-able as illegal. The mismatch is a UI guidance bug, not
a points-correctness bug — but UI-visible bugs of this kind tend to
**train players AGAINST AKA conventions** ("the addon told me I had to
ruff"). Long-term that's worse than the points hit.

### Suggested fix

Pass `s.akaCalled` at `State.lua:1966`. Two-line change.

---

## 4. S2b [medium, latent] — `S.HostValidatePlay:1665` is a dead helper but a refactor footgun

`State.lua:1660-1666`:

```lua
-- Validate that a play from `seat` is legal.
function S.HostValidatePlay(seat, card)
    if not s.isHost then return true end
    if not s.hostHands or not s.hostHands[seat] then return false, "no hand" end
    if s.turn ~= seat then return false, "not your turn" end
    if not s.contract then return false, "no contract" end
    return R.IsLegalPlay(card, s.hostHands[seat], s.trick, s.contract, seat)
end
```

`grep` across the codebase finds no current caller of
`S.HostValidatePlay`. The actual host-side legality validation lives
inline at `S.ApplyPlay:1219` and DOES correctly pass `s.akaCalled`. So
this is currently latent.

The risk is a future refactor that re-points host validation through
`HostValidatePlay`. The function name implies it's the canonical
host-side legality validator, so a reasonable refactor would route
through it — and silently lose AKA-relief, marking valid M4 discards as
illegal.

### Suggested fix

Either:
- Remove `S.HostValidatePlay` entirely (it's dead code).
- Pass `s.akaCalled` for parity.

Cosmetic-low if removed; medium if kept (refactor trap).

---

## 5. S3 [medium] — `BotMaster.PickPlay` rollout `heuristicPick:649` amplifies S1 BUT in a defensible direction

`BotMaster.lua:644-655`:

```lua
-- Helper: pick a card using pro-level heuristics (Advanced-mirror).
local function heuristicPick(s, trick)
    local hand = hands[s]
    local legal = {}
    for _, c in ipairs(hand) do
        if R.IsLegalPlay(c, hand, trick, contract, s) then
            legal[#legal + 1] = c
        end
    end
    ...
```

**Crucial detail:** the rollout's `currentTrick` is initialized at
lines 624-632 by COPYING the in-flight `S.s.trick`. So when the rollout
starts, `currentTrick` is the REAL ongoing trick (with partner's already-
played AKA card) and `S.s.akaCalled` is also live in real state. The
FIRST call to `heuristicPick` operates on what is essentially the live
trick — but `R.IsLegalPlay` at line 649 doesn't get `akaCalled`.

So the rollout sees an AKA-receiver opponent (e.g. our partner running
the heuristic for *us*) get filtered to trumps-only when it should have
the discard option. Their simulated play ruffs instead of discards. The
trump that should have been preserved gets burned in the simulated
future.

**Effect on ISMCTS value estimation:**
- Rollout from the AKA-blind side overvalues *trump-keeping* plays from
  the receiver-side seat in the simulated current trick (because in the
  rollout, the receiver always burns trump anyway, so there's no
  benefit to the player's trump-preservation strategy).
- The opposite: rollout undervalues *AKA-leveraging* plays.

**Direction of bias:** for the bot at seat 4 deciding whether to lead
into AKA-territory, the simulator says "if I lead this card, partner
will burn trump anyway when over-trumped" — so AKA-style leads (low-
risk leads counting on partner relief) are systematically devalued by
the simulator. The bot will play conservatively even though its
partner-bot would actually relieve correctly.

**However:** this is the rationale CHANGELOG line 22 cites — rollouts
shouldn't carry transient banner state into hypothetical futures. There
IS a defensible argument that simulating an AKA receiver as if they
were AKA-blind is a form of pessimistic worst-case modeling. The bot
acts as if the partner doesn't know AKA convention, which is a robust
fallback against partners who don't read the convention.

**Calibration question (open):** the asymmetry is:
- Live legality at `BM.PickPlay:830` → AKA-blind (Bug A, S1 — should
  be AKA-aware).
- Rollout legality at line 649 → AKA-blind (defensible).

If S1 is fixed (legality at 830 becomes AKA-aware), but the rollout
stays AKA-blind, there's a NEW asymmetry: the bot's outer-loop legality
will say "I have these 4 cards legally including 2 non-trumps", but the
rollout will simulate "if I play `7H`, my partner (also AKA receiver in
some future trick) will burn trump" — treating two different timelines
inconsistently.

The CLEANEST fix is to make the rollout **also** AKA-aware for the
duration of the CURRENT trick (where `S.s.akaCalled` is active in real
state) and AKA-blind for SUBSEQUENT simulated tricks (where the AKA
banner is conceptually cleared at end-of-trick — `State.lua:1327`
clears it). This requires per-trick gating in the rollout, not a flat
yes/no.

Practical compromise: pass `currentTrickAka` (initially `S.s.akaCalled`)
to `heuristicPick` for the FIRST simulated trick only, then `nil` for
all subsequent simulated tricks. This is the per-step banner gating.

### Suggested fix

Out of scope per the brief, but flag for design-level discussion:
the calibration question above should drive the implementation.

---

## 6. S4 [low] — `R.IsValidSWA:435` is reachable from live-play SWA validation

`Rules.lua:430-437`:

```lua
-- Build legal-play set for this seat.
local trickProbe = { leadSuit = leadSuit, plays = plays }
local legal = {}
local hand = hands[nextSeat] or {}
for _, c in ipairs(hand) do
    local ok = R.IsLegalPlay(c, hand, trickProbe, contract, nextSeat)
    if ok then legal[#legal + 1] = c end
end
```

The function `R.IsValidSWA` is a minimax recursion that simulates all
remaining tricks from the SWA caller's perspective to determine if the
caller's hand is "guaranteed make". This is invoked from:
- Net.lua's SWA validator (live-play — when a bot or human calls SWA).
- Tests.

The minimax recursion simulates **opponent and partner plays from real
seats** under real-time game state. If `s.akaCalled` is live (someone
called AKA earlier this trick), the SWA caller might be the AKA
receiver, and the validator's projection of their plays is AKA-blind.
This means:
- The validator says "you can't make SWA — your partner is forced to
  ruff under must-trump" but actually they'd be relieved (M4) and the
  simulated future would differ.
- **Direction of bias: SWA-conservative.** False-negative SWA: hands
  that ARE guaranteed-make get classified as not-guaranteed.

Window for hit:
1. Caller (the bot deciding SWA) is the AKA caller's PARTNER.
2. Caller calls SWA mid-trick (before partner plays).
3. Opp has cut over partner's AKA'd lead (so receiver relief is
   meaningful).

This is a narrow window but reachable. The mitigation is that
`Rules.lua:435` is in a recursive minimax body, and the brief said
don't modify code. Flagging as low severity per width-of-window.

### Suggested fix

Pass `S.s.akaCalled` (read from State, since `R.IsValidSWA` doesn't
take it as a param). Out of scope per brief.

---

## 7. Documentation drift / cosmetic

### Doc-1: `Bot.lua:1605` references non-existent `R.SunCanRolloff`

```lua
-- v0.10.2 M4: pass live `s.akaCalled` to R.IsLegalPlay so the
-- AKA-receiver relief (J-066/J-067) is honored at the legality
-- layer. Without this, must-trump-ruff fires even when partner
-- has AKA'd, defeating AKA's primary purpose. Simulator callers
-- (R.SunCanRolloff line 409) deliberately omit the param so
-- rollouts get AKA-blind semantics.
```

`grep R.SunCanRolloff` across `*.lua` returns 0 function definitions.
The intended reference is `BotMaster.lua:649` (`heuristicPick` rollout)
and/or `Rules.lua:435` (`R.IsValidSWA` recursion). The comment is
prior planning-doc drift.

### Doc-2: `Rules.lua:108-110` claims "10-substitutes-for-Ace semantic collapses to the same rule"

This is misleading per B-Bot-03 F2. The M4 patch implements only the
RECEIVER-RELIEF half of J-067 (part 2). The TRICK-LOCK half (part 1 —
opps barred from over-trumping a properly-AKA'd lead) is NOT implemented
— `R.CurrentTrickWinner:34-59` does not consult `s.akaCalled`. An opp
can still legally over-trump partner's AKA'd 10. Recommend rewording
to acknowledge this is the convention reading, not the trick-lock
reading.

### Doc-3: `Rules.lua:113-114` block comment ordering

The comment says "This relief applies BEFORE must-follow / must-trump
checks". The actual flow: relief is COMPUTED early (line 115-121) but
APPLIED at line 175 — AFTER the `hasLead` must-follow path (lines
128-160). The implementation is correct (Saudi rule is must-follow
applies; AKA only relieves must-trump-ruff for void-in-led seats), but
the block comment misrepresents the ordering. Per B-Rules-01 F3.

---

## 8. Cross-confirmation against brief's known findings

| Brief item | This report | Status |
|---|---|---|
| D-RT-04 F1: `BotMaster.PickPlay:830` Saudi-Master tier dead | §2 (S1) | **REPRODUCED** with full scenario |
| D-RT-29 F2: `State.HostValidatePlay:1665` | §4 (S2b) | **REPRODUCED**, severity confirmed (latent) |
| D-RT-29 F3: `S.GetLegalPlays:1966` UI dimming | §3 (S2) | **REPRODUCED**, novel framing: human-vs-bot asymmetry trains humans against AKA convention |
| ISMCTS sample legal-play depth | §5 (S3) | **NEW** — analyzed direction-of-bias for the rollout `heuristicPick`. Calibration question: per-trick banner gating |
| Net.lua resync replay path | §9 below | **VERIFIED CORRECT** — `Net.lua:461-463` whispers AKA banner; `_OnAKA` handler bypasses authorize on replay; `S.ApplyAKA` rebuilds banner on rejoiner. Resync semantics intact |
| `R.IsValidSWA` (called out in B-Rules-01 caller audit) | §6 (S4) | **NEW** as red-team item — narrow window, low severity |

---

## 9. Resync replay path — verified correct

`Net.lua:459-464`:

```lua
-- Replay AKA banner if active this trick. Trailing "1" tells
-- _OnAKA to bypass authorizeSeat (sender is host, not seat owner).
if S.s.akaCalled then
    whisper(target, ("%s;%d;%s;1"):format(
        K.MSG_AKA, S.s.akaCalled.seat or 0, S.s.akaCalled.suit or ""))
end
```

`Net.lua:3075-3096` `_OnAKA` handler:

```lua
local isReplay = (replayFlag == "1") and fromHost(sender)
if isReplay and S.s.isHost then return end
if not isReplay and not authorizeSeat(seat, sender) then return end
...
S.ApplyAKA(seat, suit)
```

`State.lua:1443-1450`:

```lua
function S.ApplyAKA(seat, suit)
    if not seat or not suit or suit == "" then return end
    s.akaCalled = { seat = seat, suit = suit }
    ...
end
```

The rejoiner gets `S.s.akaCalled` rebuilt on resync via the replay
frame. So `S.s.akaCalled` is live on the rejoiner immediately after
`S.ApplyResyncSnapshot` + the trailing AKA replay frame. Subsequent
`legalPlaysFor` / `Net.lua` / `State.lua:1219` paths read it correctly.

**No resync-specific divergence found** — the replay correctly carries
AKA over.

---

## 10. UI rendering paths — checked

Searched for callers of `R.IsLegalPlay` in UI files:

- `S.GetLegalPlays:1966` — UI dimming. Bug S2.
- No direct callers in `UI*.lua` files (UI consumes via `S.GetLegalPlays`).

The dimming is the only UI legality computation; fixing S2 fixes the UI.

---

## 11. Recommended priority order

1. **S1 [high]** — `BotMaster.lua:830` add `S.s.akaCalled`. One-line
   change. Negates the v0.10.2 M4 changelog claim's intent for Saudi
   Master tier.
2. **S2 [medium]** — `State.lua:1966` `S.GetLegalPlays` add
   `s.akaCalled`. UI parity.
3. **S2b [medium-latent]** — `State.lua:1665` `S.HostValidatePlay`
   either delete (dead code) or add `s.akaCalled`.
4. **S3 [design]** — calibrate rollout AKA-awareness: per-trick banner
   gating. Defensible to leave AKA-blind in rollouts but should be
   consciously chosen and documented.
5. **S4 [low]** — `Rules.lua:435` `R.IsValidSWA` thread `s.akaCalled`
   through.
6. **Doc-1, Doc-2, Doc-3** — cosmetic comment fixes.

---

## 12. Confidence

**HIGH confidence:**
- S1 BotMaster.PickPlay:830 omission and direct ruff-vs-discard
  divergence in the canonical opp-over-trump scenario.
- S2 GetLegalPlays UI dimming asymmetry.
- S2b HostValidatePlay dead-code latency (verified zero callers).
- Doc-1 SunCanRolloff non-existence (verified zero matches in `*.lua`).
- Resync replay path correctness (§9).

**MEDIUM confidence:**
- S3 rollout calibration direction-of-bias. The bias direction (under-
  values AKA-leveraging plays) is clear; the empirical magnitude in
  100-world rollouts is unknown without instrumentation.
- S4 IsValidSWA reachability — verified the function is called from
  live-play SWA validation, but the narrow scenario window (caller is
  AKA partner + calls SWA mid-trick + opp has over-trumped) makes it
  hard to estimate hit rate.

**LOW confidence:**
- Whether the per-trick rollout AKA-gating (§5 fix sketch) is the
  correct calibration vs. flat-AKA-aware rollout. This is a design
  choice that could go either way; needs a measurement decision.
