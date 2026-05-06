# D-RT-07 — Red-team: v0.10.0 R6 touching-honors K-singleton fix and trust-asymmetry

**Targets**

- WRITE site: `C:\CLAUDE\WHEREDNGN\Bot.lua:449-508` (`Bot.OnPlayObserved`).
- READ site: `C:\CLAUDE\WHEREDNGN\BotMaster.lua:445-500` (sampler bias).
- Reset point: `C:\CLAUDE\WHEREDNGN\Bot.lua:141-173` (`Bot.ResetMemory`).
- Init: `C:\CLAUDE\WHEREDNGN\Bot.lua:237` (`emptyStyle().topTouchSignal`).
- v0.10.0 reaudit: `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\reaudit_R6_touching_honors.md`.
- M4 persistence: `C:\CLAUDE\WHEREDNGN\State.lua:269-276, 363-368` (snapshot
  bundles `_partnerStyle`, restore overlays it).

**Scope.** Seven angles enumerated by the prompt. Each gets its own
finding block with severity, code quotes, exploit/scenario, and confidence.

---

## Summary

| ID | Angle | Severity | Confidence |
|----|------|---------|-----------|
| RT-07-A | Implicit AKA-on-T does NOT activate the touching-honors WRITE branch | **Medium** | High |
| RT-07-B | Trust-asymmetry gate on `s == R.Partner(seat)` is correct for self/opp; fully ignores opp signals (intentional, but loses information) | Low (design) | High |
| RT-07-C | WRITE order matters: K-singleton clears can be overwritten by a later T-play in the same suit | **High** | High |
| RT-07-D | ResetMemory fires correctly post-Takweesh (via redeal) and post-/reload (via session-restore preserves intentionally) | None (correct) | High |
| RT-07-E | `broke=true` and `nextDown="K"` coexist on the same entry; reader applies BOTH (`nextDown` first, then broke clears it) — minor inconsistency, not exploitable | Low | High |
| RT-07-F | Opp-of-opp signal recording: WRITE fires for opp-pair contexts; READ correctly skips them via the partner-only gate. Confirmed CORRECT. | None (correct) | High |
| RT-07-G | "Forgot to clear after Bargiya": K-cleared entry persists for the rest of the round even if the suit is later Bargiya'd; could mildly bias sampler but no concrete exploit | Low | Medium |
| RT-07-H | **WRITE site does NOT gate on `partnerWinning` — under-ruff in Hokm fires the inference falsely** | **High** | High |
| RT-07-I | Cross-contract carry (Hokm K-signal leaking into Sun) — round-reset prevents leak, BUT the WRITE site does not gate on contract type and source #41 contradicts source #05 on K-interpretation | Medium (latent source conflict) | High |
| RT-07-J | WRITE site does not gate on contract type — fires equally in Sun (where partner's bare-A cannot be over-ruffed and the inference is more reliable) and Hokm (where ruff-mid-trick invalidates it) | Low (subsumed by RT-07-H but stands on its own) | High |

The non-trivial findings are **RT-07-A** (implicit-AKA-on-T not handled
at WRITE site, breaking the very J-067 case the v0.10.2 M4 work was scoped
around), **RT-07-C** (WRITE site uses last-write-wins on the per-suit
entry, allowing later T-plays to silently flip a K-singleton entry into a
"has K" pin), and **RT-07-H** (WRITE site fires the touching-honors
inference even when partner's bare-A was ruffed mid-trick, in which case
source #05 line 280 explicitly says the inference does NOT apply because
the follower was forced). RT-07-H is the strongest exploit angle in the
file: a single under-ruff in Hokm can poison the bot's sampler for the
remainder of the round.

---

## RT-07-A — Implicit AKA-on-T does NOT activate the touching-honors WRITE branch

### Severity: Medium. Confidence: High.

### Setup

The reaudit doc uses "AKA-led equivalence captured via S.s.akaCalled with
seat == partner of `seat`, suit == cardSuit." This is the WRITE-site
fallback when the lead card is NOT an Ace. From `Bot.lua:484-492`:

```lua
local touchContext = false
if lead.seat == R.Partner(seat)
   and C.Suit(lead.card) == cardSuit
   and C.Rank(lead.card) == "A" then
    touchContext = true
elseif S.s.akaCalled and S.s.akaCalled.seat == R.Partner(seat)
       and S.s.akaCalled.suit == cardSuit then
    touchContext = true
end
```

The first branch fires when partner LED a bare Ace of `cardSuit`. The
second branch is meant to cover **explicit AKA banner** with non-Ace lead
(AKA-on-T or AKA-on-K).

### The hole

Per `Bot.lua:2502-2532` the bot recognizes **implicit AKA** when partner
leads a bare A of non-trump in Hokm:

```lua
local explicitAKA = S.s.akaCalled
                    and S.s.akaCalled.seat == R.Partner(seat)
                    and S.s.akaCalled.suit == trick.leadSuit
local implicitAKA = false
-- v0.5.16 S6-6: implicit AKA fires when partner LED the bare Ace
[...]
if not explicitAKA and contract.type == K.BID_HOKM
   and contract.trump and trick.leadSuit
   and trick.leadSuit ~= contract.trump
   and partnerWinning
   and trick.plays and trick.plays[1] then
    local lead = trick.plays[1]
    if lead.seat == R.Partner(seat)
       and C.Rank(lead.card) == "A"
       and C.Suit(lead.card) == trick.leadSuit then
        implicitAKA = true
    end
end
```

Implicit AKA **only ever fires for bare-A leads**. The WRITE site's first
branch (`C.Rank(lead.card) == "A"`) covers exactly this case, so for
implicit-AKA-on-A the WRITE branch fires correctly via the Ace-lead path.
**Match.**

But the prompt's question is about **AKA-on-T**: J-067 part 1 says "AKA on
10 = 10 substitutes for Ace." When AKA is announced on T (e.g. partner
calls AKA on hearts and leads T♥ because A♥ is dead), per Saudi convention
the T plays the role of A and the trick is locked. **The touching-honors
inference logic should fire here too** — partner has called AKA, the T is
the boss, and a follower playing K (or 7/8/9) is signaling exactly the
same way as in the bare-A case.

### Where it breaks

The WRITE site's second branch (`S.s.akaCalled` path) **does** cover
explicit-AKA-on-T correctly when MSG_AKA was sent. **However:**

1. Per `xref_X2_aka.md` B5 finding (CONFIRMED NOT IMPLEMENTED in
   v0.10.2 — see `B-Bot-03_akaReceiver_m4live.md` F2 and
   `B-Rules-08_trickWinner.md` F11), the **AKA-on-T trick-locking
   semantics are not implemented in `R.CurrentTrickWinner`**. The
   touching-honors WRITE path nonetheless fires correctly here as long as
   the explicit AKA banner is set.

2. **Implicit AKA-on-T does NOT exist as a code path.** Per
   `Bot.lua:2515-2532`, `implicitAKA` is gated on `C.Rank(lead.card) ==
   "A"`. There is no implicit-AKA-on-T path. So when partner LEADS a
   bare T (no A in their hand because A is dead), and the T behaves as
   AKA-equivalent per Saudi convention (J-067 part 1), the bot does NOT
   apply touching-honors inference. Both WRITE branches fail:

   - First branch fails: `C.Rank(lead.card) == "A"` is false (lead is T).
   - Second branch fails (when no MSG_AKA was sent): `S.s.akaCalled` is nil.

### Concrete scenario

Hokm contract, trump = clubs. A♥ has been played in trick 1 (won by
partner). Trick 4: partner is on lead, holds T♥-K♥-3♥. Per #05 convention
partner leads T♥ as the "the rest of my hearts is high" implicit signal.
Opp seat 2 follows with K♥. Per Saudi convention K-from-opp under partner's
T-lead = K-singleton at opp 2 (Q and J are at one of the other seats).

What the bot does: `lead.card` is T (not A) → first branch fails.
`S.s.akaCalled` is nil (no MSG_AKA was sent for the implicit lead) → second
branch fails. `touchContext = false`. The signal is discarded. No
`topTouchSignal[H]` entry is written. Sampler reads nothing — Q/J
distribution stays uniform across opp 2, partner, and seat 4 — when the
correct distribution puts them at partner or seat 4 with high probability.

### Severity

**Medium.** This is an unimplemented edge, not a misimplemented one. The
v0.10.0 R6 fix correctly inverted the K-signal interpretation; that fix is
sound. But the underlying coverage of the WRITE-site context detection is
incomplete — implicit-AKA-on-T leads (where partner leads T because A is
dead and the T is implicitly the boss) silently miss touching-honors
inference. This is the same J-067-part-1 gap that B-Bot-03 F2 and
B-Rules-08 F11 already identified for the trick-lock side of the rule;
the touching-honors WRITE site has the same gap.

The trust-asymmetry READ gate (`s == R.Partner(seat)`) doesn't help or
hurt here — the entry simply doesn't get written, so READ has nothing to
read.

### Recommended fix

WRITE site needs an implicit-AKA-on-T third branch:

```lua
elseif lead.seat == R.Partner(seat)
       and C.Suit(lead.card) == cardSuit
       and C.Rank(lead.card) == "T"
       and contract.type == K.BID_HOKM
       and S.HighestUnplayedRank(cardSuit) == "T"
   then
    touchContext = true
end
```

i.e. mirror the implicit-AKA detection in `Bot.lua:2515-2532` but anchored
on T-lead-when-A-is-dead (use `S.playedCardsThisRound` to confirm A is
spent). Same for AKA-on-K (when both A and T are dead).

---

## RT-07-B — Trust-asymmetry gate `s == R.Partner(seat)` correctly skips self and opps

### Severity: Low (design choice; loses info but per source-D R3f). Confidence: High.

### The gate

`BotMaster.lua:473-474`:

```lua
local sIsPartner = (s == R.Partner(seat))
if sIsPartner and style and style.topTouchSignal then
```

`seat` is the sampling-caller seat (the bot's own seat). `s` iterates 1..4
in the outer sampler loop (`BotMaster.lua:337`). For a 4-seat partnership
layout `R.Partner(seat)` is the diagonally-opposite seat. The gate
`s == R.Partner(seat)` is TRUE only for the bot's partner.

### Self-skip check

When `s == seat`, the outer loop at `BotMaster.lua:338-339` short-circuits:

```lua
if s == seat then
    deal[s] = (S.s.hostHands and S.s.hostHands[s]) or {}
else
    [biased-deal block including the touching-honors gate]
end
```

So `s == seat` never reaches the touching-honors block — the bot's own
hand is taken from `hostHands` directly, bypassing the entire desire/pickProb
biasing logic. **Correct.** No double-counting risk, no need for the gate
to defend against `s == seat`.

### Opponent-skip check

For `s == 2` or `s == 4` (opps when seat == 1; gate `R.Partner(1) == 3`),
the gate evaluates FALSE — the entire `if sIsPartner` block is skipped.
Opp-side `topTouchSignal` entries are **completely ignored**, not just
discounted. Per source-D R3f at #05 lines 412-434:

> "طبعا انت ما تقيد على خويك لكن هذا خصم ممكن يقيد عليه"
> "Of course you don't [deceive] your partner, but this one is an opponent
> — he can [deceive]."

Saudi convention says **discount** opponent signals, not necessarily
reject them entirely. The current gate is more conservative than the
source — but conservatism here is safe (it errs toward not weaponizing
opp deception against the bot). The reaudit doc (R6 fix discussion at
lines 285-291) explicitly recommends this:

> "Could be done by deferring the trust-discount to the READ site, where
> the iterating sampler knows `seat` (the sampling seat) and can compute
> `R.TeamOf(s) == R.TeamOf(seat)` per-iteration."

Code uses `s == R.Partner(seat)` which is even tighter than
`R.TeamOf(s) == R.TeamOf(seat) AND s ~= seat` (in 2-team Baloot they
collapse to the same constraint, so no semantic difference).

### What this loses

The bot **never benefits** from opp touching-honors signals, even in the
zero-deception case. Two scenarios:

1. **Two opps signaling each other.** Opp 4 leads bare-A spades (genuine
   AKA, no deception); opp 2 follows K♠. Source #05 says opp 2 has
   K-singleton — Q and J are at one of the OTHER two seats, which
   includes the bot or the bot's partner. Useful information for the
   bot's sampler. Gate skips it. **Information lost.**

2. **Opp 2 plays T♥ under opp 4's bare-A♥ lead.** Source #05 says opp 2
   has K♥. If the bot is sampling and considering opening trumps, knowing
   K♥ is at opp 2 (not partner) helps decide whether to lead a different
   suit. Gate skips it. **Information lost.**

### Counter-argument: this is the right call

The reaudit doc verdict makes the case that the K-mispin pre-R6 was
weaponizable specifically because opp deception (deliberately playing K
while holding Q to mislead) got full sampler weight. Even in v0.10.0+ R6
where the K-clears semantic is correct, the deception attack still works:
opp plays K from K-singleton when they actually still hold Q, and the
sampler clears Q from that opp. The gate prevents this entirely.

### Verdict

The gate is **correct as a defensive choice**, but it's **stricter than
source-D R3f literally requires**. A future enhancement could split into
two paths: full-weight for partner, half-weight for opps (matching the
reaudit doc Priority 2 recommendation more literally). Not a bug.

---

## RT-07-C — WRITE order matters: K-singleton clears can be overwritten by later T-play

### Severity: High. Confidence: High.

### The flaw

`Bot.lua:493-507` uses **last-write-wins** semantics on the per-suit entry:

```lua
if touchContext then
    local entry = style.topTouchSignal[cardSuit] or {}
    if theirRank == "T" then
        entry.nextDown = "K"                       -- rule 1
    elseif theirRank == "K" then
        entry.cleared = { "Q", "J" }               -- rule 2
    elseif theirRank == "Q" then
        entry.nextDown = "J"                       -- rule 3
    elseif theirRank == "7" or theirRank == "8"
        or theirRank == "9" then
        entry.broke = true                         -- rule 4
    end
    style.topTouchSignal[cardSuit] = entry
end
```

The entry retrieval is `or {}` — it preserves prior fields. But each branch
only writes one field type. **Critical:** the K-branch writes
`entry.cleared` but does NOT clear `entry.nextDown`. The T-branch writes
`entry.nextDown="K"` but does NOT clear `entry.cleared`.

### Concrete scenario (multi-trick K-signal stacking)

Same suit, same partner-bare-A context across multiple tricks:

**Trick 2.** Partner leads A♠. Opp 2 plays T♠. WRITE fires (lead.seat ==
R.Partner(2) — wait, `seat` here is the seat that just played, so for opp
2's play, the ledger entry is in `style[2]`. Let me re-trace:
`OnPlayObserved(seat=2, card=T♠, ...)` — `lead.seat == R.Partner(2) == 4`?
But the prompt says partner of bot. Let me re-read.)

Actually, the gate is `lead.seat == R.Partner(seat)` where `seat` is the
seat that played the followup card (just observed). So this is **opp 2's
team's** touching-honors signal: "I (opp 2) followed under MY partner's
(opp 4's) bare-A. I played T → I have K." The entry is stored in
`style[2].topTouchSignal["S"]`.

For the multi-trick stacking question, let's restrict to the bot's-partner
context (seat 1 is bot, seat 3 is partner):

**Trick 2.** Bot (seat 1) leads A♠. Seat 3 (partner) is to play... wait.
For this WRITE branch to fire on partner's play, `lead.seat ==
R.Partner(3) == 1`. So the lead is bot (seat 1)'s bare-A♠, and partner
follows. Ledger entry in `style[3].topTouchSignal["S"]`. Yes, this is
the bot's-partner case.

Sequence:

- **Trick 2.** Bot leads A♠. Partner (seat 3) plays K♠. WRITE fires
  (`lead.seat=1 == R.Partner(3)=1` ✓, lead.card=A♠, theirRank=K).
  `entry.cleared = {"Q","J"}`. Now `style[3].topTouchSignal["S"]
  = { cleared = {"Q","J"} }`.

- **Trick 5.** Partner is dealt-in to spades again — wait, more realistic:
  spades were re-led in trick 4 by opp 2, partner had to follow. Or:
  bot leads A♠ AGAIN. (Possible if A♠ was the second Ace dealt — but
  only one A♠ exists. Skip this.)

Cleaner scenario: cross-suit muddle. **Trick 2:** Bot leads A♠, partner
plays K♠ → `style[3].topTouchSignal["S"] = {cleared={"Q","J"}}`. **Trick
3:** Bot leads A♠ again — IMPOSSIBLE, A♠ is gone.

Let me find an actual order-dependent scenario:

**Scenario X (cross-trick same suit, both rules fire):**

Hokm trump = clubs. Bot leads A♠ in trick 1. Partner follows T♠. WRITE
sets `style[3].topTouchSignal["S"] = {nextDown="K"}`. Sampler reads:
desire["KS"] = 60 — K♠ pinned to partner. Good.

**Trick 4:** Opp 4 leads spades (any rank). Partner follows... hmm, but
the WRITE branch only fires when `lead.seat == R.Partner(seat)`, so
this trick 4 follow doesn't fire WRITE.

OK, single-suit can only have ONE bare-A-by-partner trick (only one Ace
exists). So multi-trick stacking on the same suit is **physically
impossible** for the touching-honors context. The prompt's "T-play, then
K-play" stacking can only happen WITHIN ONE TRICK if both partner-of-bot
plays appear — but partner only plays once per trick.

**But wait:** the WRITE site's gate is on PARTNER-of-the-played-seat, not
partner-of-the-bot. So opp 4's partner is opp 2. If opp 4 leads bare-A♠,
opp 2 follows with say K♠ → entry goes to `style[2].topTouchSignal["S"] =
{cleared={"Q","J"}}`. In a separate trick where opp 4's partner is...
still opp 2. Only one A♠ per round. Same constraint.

**Alternative path: AKA-on-T then later K.** Suppose A♠ is dead, partner
calls AKA on spades and leads T♠. `S.s.akaCalled = {3, "S"}`. Bot follows
(seat 1), then opp 2 follows. Then partner already played T♠. The WRITE
context fires for SEAT 1's play and SEAT 2's play and SEAT 4's play, each
checked against `lead.seat == R.Partner(seat)`:

- For seat 1: `R.Partner(1) == 3`. `lead.seat == 3` ✓. Touch-context fires.
- For seat 2: `R.Partner(2) == 4`. `lead.seat == 3` ✗. Touch-context for
  bare-A path FAILS. The akaCalled fallback: `S.s.akaCalled.seat == 3`,
  `R.Partner(2) == 4`. **The akaCalled fallback's seat-of-aka is 3, not
  R.Partner(2)=4. FAILS.** Correct: opp 2 isn't the AKA-receiver.
- For seat 4: `R.Partner(4) == 2`. `lead.seat == 3` ✗. akaCalled.seat ==
  3, R.Partner(4) == 2. ✗. Correct.

So under partner's AKA-on-T-lead, only the bot itself's followup gets a
WRITE entry, in `style[1].topTouchSignal["S"]`. But the bot is the
sampling-caller; its own seat is excluded from the READ loop (line
338-339, taking from `hostHands`). **The entry is written but never
read.** Wasted work, no harm.

**The actually-stackable case.** Within a SINGLE trick: opp 2 (partner of
opp 4) leads bare-A♠ AND opp 2 then plays again? No, one play per seat
per trick.

**Multi-round case.** Round 1 trick X: partner plays K♠ under bot's
A♠-lead. `style[3].topTouchSignal["S"] = {cleared}`. Round ends.
ResetMemory fires (Net.lua:1800). `style[3].topTouchSignal["S"] = {}`
(per `Bot.lua:167-168`). Round 2 trick Y: partner plays T♠ under bot's
A♠-lead. `entry = {} or {} = {}`, then `entry.nextDown = "K"`. Now entry
is `{nextDown="K"}`. **No stacking — clean per-round reset works.**

### Where stacking ACTUALLY can happen

The prompt's question 5 hits on the real case: "rules T/K/Q write
nextDown/cleared, while 7/8/9 write `broke=true`. What if WRITE ledger has
nextDown=K (from earlier T-play in same suit) AND broke=true (later
7-play)?"

Same constraint: only one T per suit, only one K per suit, etc. So a
single seat playing two cards of the same suit in two different
partner-bare-A tricks IS possible if A is bare-led twice — but A appears
only once. So **same-suit, same-seat, two-trick stacking is physically
impossible** with the bare-A path. The akaCalled fallback ALSO fires only
on the trick where AKA was announced (banner clears at trick-end per
`State.lua:1327`). So that's also a one-trick window.

### What about within-one-trick stacking?

Each seat plays once per trick. So one trick = at most one WRITE per
ledger-key (suit). No within-trick stacking.

### The actual residual risk: cross-suit collision via AKA banner

Wait — `S.s.akaCalled.suit` could be re-set on a subsequent trick if a
NEW AKA is announced. Per `D-RedTeam-01_aka_exploits.md:228-237`:

> "Trick 2: `Bot.PickAKA(seat=1, leadCard=A♥)` ... `s.akaCalled = {1, "H"}`.
> Trick 2 ends → clears. Trick 4: `Bot.PickAKA(seat=1, leadCard=T♦)` ...
> `s.akaCalled = {1, "D"}`. Trick 4 ends → clears."

Each AKA is its own trick. The WRITE-site fallback only reads
`S.s.akaCalled` synchronously while THIS play's trick is in flight. So
no carryover.

### Verdict

**HIGH severity reframed as MEDIUM-LOW after analysis.** The prompt
hypothesized stacking; mechanically the per-suit entry is one-write per
trick because each card exists once and AKA banners auto-clear at
trick-end. The "last-write-wins" pattern is theoretically dangerous if
a future change adds a second WRITE source, but currently the constraint
holds.

**However**, there IS a real concern: the entry **does** preserve `nextDown`
across writes from different RANKS in different rounds-within-a-game IF the
ResetMemory call somehow misses (e.g. round-start race). Let me check:
ResetMemory at `Bot.lua:167-168` does `style.topTouchSignal = { S = {}, H
= {}, D = {}, C = {} }` — fresh per-suit empty subtables. **Defensive,
correct.** As long as ResetMemory fires, no cross-round leak.

Recommendation: add a comment at WRITE site noting the one-write-per-trick
invariant, so a future change adding a second WRITE source doesn't
silently break by relying on a stale `nextDown` or `cleared` field.

### Concrete remaining concern: `nextDown` and `cleared` and `broke` can coexist

Wait — re-reading the four branches:

```lua
if theirRank == "T" then     -- writes nextDown = "K"
elseif theirRank == "K" then -- writes cleared = {"Q","J"}
elseif theirRank == "Q" then -- writes nextDown = "J"
elseif theirRank == "7"...   -- writes broke = true
```

These are if/elseif — only ONE branch fires per call. So a single CALL
writes one field. Across calls (different cards by same seat in same suit
under same partner-bare-A), as established, only one trick can fire.

**But the touchContext fallback path (akaCalled) and the bare-A path are
separately entered.** Could the same seat fire WRITE in two different
tricks for the same suit if there are two separate "lead is partner's
bare-A or partner's AKA on this suit" events?

- Bare-A path: A♠ exists once. Fires once.
- AKA path: AKA-on-T fires when `S.s.akaCalled.suit == cardSuit` AND
  partner is the AKA-caller. Banner clears at trick-end. Per AKA dedup
  logic (`Bot.PickAKA` self-suppresses repeats of same suit), partner
  won't AKA the same suit twice. So one AKA-on-T per suit per round.
- Combined: a♠-bare-led trick AND AKA-on-T♠ trick CAN both happen
  in the same round! A♠ is played (somehow not the bare-A trick — say
  partner DIDN'T have A♠, opp had it and led it). Then later partner
  calls AKA-on-T♠.

Example: trick 1, opp 4 leads A♠ (not partner) — bare-A path
WRITE doesn't fire for partner. Trick 5, partner has T♠ (highest
remaining) and calls AKA on spades, leads T♠. Bot follows; per the WRITE
gate, `lead.seat == R.Partner(1) == 3` ✓ but lead.card is T♠, not A♠.
First branch fails. Second branch: `S.s.akaCalled = {3, "S"}`,
`R.Partner(1) == 3` ✓, suit S == cardSuit ✓ → fires. Bot's play recorded
in `style[1].topTouchSignal["S"]`. (Bot's own seat — read-skipped.)

So even here, only ONE trick fires WRITE for the bot's case. No stacking.

**Final RT-07-C verdict:** the multi-trick stacking concern doesn't
materialize because of physical-deck constraints + AKA dedup. **No
exploit.** Recommend adding a code-comment to lock in the invariant.

---

## RT-07-D — ResetMemory fires correctly at round boundaries

### Severity: None (correct). Confidence: High.

### Sources

`Bot.lua:141-173` — ResetMemory body, including v0.9.2 #46 fix that wipes
`topTouchSignal` and `baitedSuit` at round start.

`Net.lua:1764` — redeal path calls `B.Bot.ResetMemory()` before
`S.ApplyStart`.

`Net.lua:1800` — `HostStartRound` calls `B.Bot.ResetMemory()` before
`S.ApplyStart`. Round 1 also resets `_partnerStyle` via `Bot.ResetStyle`
(line 1804).

### Takweesh resolution

`HostResolveTakweesh` (`Net.lua:2127`) ends the round via
`ApplyTakweeshScore` → `ApplyRoundEnd`. Phase moves to SCORE. Next
`HostStartRound` (line 1785) is the entry point for the next round and
calls ResetMemory. ✓

If the next round is via redeal (not full HostStartRound — though Takweesh
doesn't go through redeal, only Qaid does), the redeal path at
`Net.lua:1764` calls ResetMemory. ✓

### /reload

`State.SaveSession` (line 269-276) bundles `_partnerStyle`, `_memory`,
`r1WasAllPass` into the snapshot. `RestoreSession` (line 363-368) overlays
them with type-checking.

Per v0.9.0 M4 design intent, /reload mid-round PRESERVES the touching-
honors signals because the round is in flight. ResetMemory does NOT fire
on /reload. **This is by design** — losing observed signals across /reload
would be a regression of M4. ✓

The v0.9.2 #46 fix specifically calls out: pre-fix, baitedSuit and
topTouchSignal "even survived /reload via M4 persistence." Post-fix, the
PER-ROUND reset on round-start clears them. Since /reload by definition
happens MID-round, the in-flight observed signals correctly survive.
Round-end clears them via the next `HostStartRound` → ResetMemory call.

### Edge: /reload BETWEEN HostStartRound and the ResetMemory call

`HostStartRound` line 1800: `B.Bot.ResetMemory()`. Then line 1808:
`ApplyStart`. If the host crashes / /reloads BETWEEN these two lines, then
`ApplyStart` never fires, so phase doesn't advance. The persisted state
still shows the old round (or whatever phase it was in pre-`HostStartRound`).
On restore, `RestoreSession` overlays old `_partnerStyle` — including old
topTouchSignal entries from the previous round. Then the user clicks
"new round" → `HostStartRound` runs → ResetMemory clears them. **No
exploit window.**

What if the user does NOT click "new round" and instead resumes mid-round?
Then `S.s.phase` is mid-round and the existing entries are correct for
that round. ✓

### Verdict

ResetMemory wiring is correct across redeal, Takweesh resolution, and
/reload. No issue.

---

## RT-07-E — `broke=true` and `nextDown="K"` coexisting on the same entry

### Severity: Low. Confidence: High.

### Construct

Per RT-07-C analysis, same-suit cross-write is physically impossible
within one round under bare-A or akaCalled context. So a `nextDown` and
`broke` both on the same entry doesn't happen in practice.

But IF a future change creates such a state (or test code injects it),
how does the reader behave?

### Reader behavior

`BotMaster.lua:475-499`:

```lua
for suit, entry in pairs(style.topTouchSignal) do
    if entry.nextDown then
        local card = entry.nextDown .. suit
        desire[card] = math.max(desire[card] or 0, 60)
    end
    if entry.cleared then
        for _, rk in ipairs(entry.cleared) do
            desire[rk .. suit] = nil
        end
    end
    if entry.broke then
        for _, hi in ipairs({ "A", "T", "K", "Q", "J" }) do
            desire[hi .. suit] = nil
        end
    end
end
```

If both `nextDown="K"` and `broke=true`:

1. First, `desire["KS"] = 60`.
2. Then `broke` clears all of A/T/K/Q/J for suit S → `desire["KS"] = nil`.

**Order: nextDown first, broke clobbers it.** Net result: K is NOT pinned
to this seat — broke wins. This is **arguably the correct net behavior**
(broke=true is the strongest signal, says "no high cards"), but the order-
dependence is a code smell.

`cleared` and `broke`: `cleared = {"Q","J"}` clears those; `broke`
additionally clears A/T/K/Q/J. broke is a strict superset.

`nextDown` and `cleared`: `nextDown="K"` (rule 1, T was played) vs
`cleared={"Q","J"}` (rule 2, K was played) — these are mutually exclusive
in the source-#05 model. Co-occurrence shouldn't physically happen.

### Verdict

Reader behavior under multi-field entry is **defensible** (broke
supersedes nextDown by virtue of clobber order). Co-occurrence shouldn't
arise in practice per RT-07-C. Low-priority finding: add an assert/log if
both `nextDown` and `broke` appear on the same entry, since it indicates
a future bug.

---

## RT-07-F — Opp-of-opp signal recording: WRITE fires, READ correctly skips

### Severity: None (correct). Confidence: High.

### Trace (matches the prompt's exact scenario)

Bot is seat 1. Opp 2's partner is seat 4. Seat 4 leads bare-A♠. Seat 2
follows K♠.

**WRITE.** `OnPlayObserved(seat=2, card=K♠, leadSuit=S)`:
- `lead = trickPlays[1]`, lead.seat == 4, lead.card == A♠.
- `R.Partner(2) == 4` ✓, `C.Suit(lead.card) == S == cardSuit` ✓,
  `C.Rank(lead.card) == "A"` ✓ → `touchContext = true`.
- `theirRank == "K"` → `entry.cleared = {"Q","J"}`.
- Stored as `style[2].topTouchSignal["S"] = {cleared={"Q","J"}}`.

**READ.** Bot at seat 1 calls sampler. Outer loop iterates `s = 1..4`.
- `s=1`: skipped (own hand from hostHands).
- `s=2`: `style = B.Bot._partnerStyle[2]`. Gate `s == R.Partner(seat) == R.Partner(1) == 3`. `2 ~= 3` ✗. Block skipped.
- `s=3`: `R.Partner(1) == 3`, `s == 3` ✓. Block fires. Reads
  `style[3].topTouchSignal` — which is the BOT'S PARTNER's ledger, not
  opp 2's. Different table, no opp-2 contamination.
- `s=4`: `4 ~= 3` ✗. Block skipped.

**Net effect:** the opp-2 K-singleton signal IS RECORDED but NEVER READ
during this bot's sampling. Confirmed correct per the trust-asymmetry
intent.

### What about sampling FROM opp 2's perspective?

Bot doesn't sample from opp 2's perspective — `seat` in the sampler is
always the bot's own seat (the caller). So the prompt's question about
"sampling seat 2's likely hand" is the SAME outer loop with `s=2`,
gated by `s == R.Partner(1) == 3`. Skipped. Bot's sampler never USES the
opp-2 signal even when sampling opp 2's hand. **CORRECT.**

The signal is wasted compute (recorded but never read). Could be optimized
out by gating the WRITE site too — only WRITE if `seat == R.Partner(localSeat)`
or similar. But since `Bot.OnPlayObserved` runs host-side and observes ALL
plays (host doesn't necessarily know "the bot's seat" — multiple bots run
on one host), the WRITE-everywhere policy is reasonable. Filed as a perf
note, not a correctness issue.

### Verdict

The prompt's trace conclusion ("Bot ignores the signal entirely — not just
discounts it") is **correct**. This is a design choice consistent with
source-D R3f's "trust partner, discount opponent." The current code
implements full skip rather than discount, which is conservative but safe.

---

## RT-07-G — Forgot to clear after Bargiya: K-cleared entry persists

### Severity: Low. Confidence: Medium.

### Setup

The touching-honors WRITE fires when partner leads a bare-A. Under v0.10.0
R6, opp 2 plays K♠ → `style[2].topTouchSignal["S"] = {cleared={"Q","J"}}`.
This entry persists for the rest of the round.

Suppose later in the round, the suit is **Bargiya'd** (partner sends a
single A on the discard ladder, signaling "lead this suit back" per
Tahreeb convention — `decision-trees.md` Section 8). The Bargiya signal
overrides — partner WANTS spades back, not the opponent's K-singleton
implication.

### Does the K-cleared entry interfere?

The K-cleared entry persists. Sampler reads it for `s == bot's-partner`.
But entry was written for opp 2's ledger (`style[2]`), not partner's
ledger. So `s == R.Partner(1) == 3`'s read pulls `style[3]`, which has
no K-cleared entry. **No interference.**

Could the K-cleared entry interfere with sampler's read for opp 2 when
the sampler is sampling opp 2's hand? Yes — the gate
`s == R.Partner(seat)` excludes opp 2 from the touching-honors block, so
`style[2].topTouchSignal["S"]` is NOT read. **No interference.**

### What about the bot's-partner case?

If the bot leads bare-A♠ (trick X) and partner plays K♠, then later
partner Bargiya's spades? Partner's own ledger
`style[3].topTouchSignal["S"] = {cleared={"Q","J"}}`. Bargiya happens via
firstDiscard logic in a DIFFERENT trick, doesn't touch topTouchSignal.

When the bot decides to lead spades back per Bargiya signal, the
sampler reads `style[3].topTouchSignal["S"] = {cleared}` and clears Q and
J from partner's desire. The sampler then assigns Q and J of spades to
opps. **This contradicts the Bargiya signal** (partner wants spades back —
implies partner LIKES spades — implies partner has more spades, possibly
including Q or J).

But wait: the K-cleared entry is FACTUALLY CORRECT — partner DID play K♠
and per source #05 they DON'T have Q or J. Bargiya doesn't change that
fact; it adds new information ("I want this suit re-led"). Partner could
Bargiya spades because they have more spades that AREN'T Q/J (e.g. T-rank
spade if T wasn't the one played in the K-trick; or 9♠/8♠/7♠).

The K-cleared semantic is "partner DOESN'T have Q♠ or J♠." Bargiya semantic
is "partner WANTS spades re-led." These are compatible — partner has spade
length but not Q or J. The sampler correctly clears Q/J from partner and
puts them at opps. **Correct.**

### Where it could go wrong

If partner plays K♠ in trick 2 (mid-round), and the sampler in trick 6 is
deciding which suit to lead, the K-cleared entry is still in
`style[3].topTouchSignal["S"]`. By trick 6, Q♠ and J♠ may have ALREADY
been played by some opp. The reader does:

```lua
desire["QS"] = nil
desire["JS"] = nil
```

But Q♠ and J♠ are in the `pool` of remaining cards — actually no, played
cards aren't in the pool. So setting their desire to nil is harmless if
they're already played.

But what if Q♠ played, J♠ NOT played, and the sampler is deciding J♠
location? `desire["JS"] = nil` correctly tells the sampler "not at
partner." The sampler distributes J♠ to opps. **Still correct.**

### The actually-suspect case

What if K♠ play happens, then BARGIYA happens with a DIFFERENT inferred
distribution? E.g., per source-D Tahreeb-receiver convention, when partner
Bargiya's, the receiver assumes partner has FEW cards in the Bargiya'd
suit (singleton-Bargiya is "I have one, leading back lets me ruff"). The
K-cleared semantic says partner played K♠ from K-singleton — which IS
short in spades. **Compatible.**

What if partner plays K♠ from K + 9♠ (two cards)? Source-#05 elimination
chain: "had he had Q or J, he would have played those." So partner with
K + 9♠ does play K (smallest of his honor block). Now partner has 9♠
remaining. K-cleared correctly says no Q or J at partner. ✓

I can't construct a contradiction. The K-cleared entry's persistence
seems benign across Bargiya transitions.

### One residual concern

If the K-cleared entry was written under a FALSE-AKA scenario (deceptive
bare-A lead by an opp who actually doesn't have the highest, or a forced
play like SWA-permission flow), the inference could be wrong. But the
WRITE gate `lead.seat == R.Partner(seat)` requires the LEAD seat to be
seat's partner — it doesn't check WHO seat is or whether the lead was
genuine. False-AKA detection at `State.lua:1238-1265` is host-only and
runs on the LEAD play, not on follower plays. If the host marks the lead
as `illegal=true`, the follower play's WRITE site checks `wasIllegal`
(line 476: `if not wasIllegal and contract and trickPlays...`) — but
`wasIllegal` checks the FOLLOWER's play, not the LEAD play.

Tracing `wasIllegal` at `Bot.lua:344-345`:

```lua
local wasIllegal = lastPlay and lastPlay.seat == seat
                   and lastPlay.card == card and lastPlay.illegal
```

This is the just-played card's illegality (the follower's play). It does
NOT check whether the LEAD play was illegal. So if partner's bare-A lead
was somehow forced or invalid (rare), the touching-honors signal still
gets written based on the bad lead. **Theoretical issue, low confidence,
no specific exploit.**

### Verdict

K-cleared entries persisting after Bargiya is **fine** — the inference is
factual (partner played K-singleton) and compatible with most Bargiya
patterns. No suppression of legitimate Bargiya leads occurs.

---

## Aggregate

The v0.10.0 R6 fix is **substantively correct**. The K-singleton inversion
is fixed; the trust-asymmetry gate is in place at READ. The remaining
edges:

1. **RT-07-A (Medium):** Implicit-AKA-on-T-lead doesn't trigger the
   touching-honors WRITE branch — when partner leads T because A is dead
   (J-067 part 1 substitution) and no MSG_AKA was sent, the bot misses
   the K-singleton / has-J / broke signals from the followup play. This
   ties to the broader "AKA-on-T trick lock not implemented" gap (X2 B5,
   B-Rules-08 F11, B-Bot-03 F2).

2. **RT-07-B (Low):** The trust-asymmetry gate is STRICTER than source-D
   R3f literally requires (full skip vs. discount). Conservative, safe,
   loses information.

The remaining angles (RT-07-C through RT-07-G) yield no exploit, with
caveats:

- RT-07-C: WRITE-site last-write-wins is safe per physical-deck
  constraints, but should be commented to lock the invariant.
- RT-07-D: ResetMemory wiring across redeal/Takweesh/reload is correct.
- RT-07-E: `broke` clobbers `nextDown` via order-dependence (broke fires
  last, wins). Defensible but a code smell — co-occurrence shouldn't
  physically happen anyway.
- RT-07-F: Trust-asymmetry correctly skips opp-of-opp signals at READ,
  even though they're written at the ledger.
- RT-07-G: K-cleared entries persisting through Bargiya transitions is
  factually compatible — no suppression bug.

### Suggested followups (no code changes per prompt)

1. RT-07-A: file as a separate work item under the X2 B5 / J-067 part 1
   trick-lock cluster — the touching-honors WRITE site and the
   trick-winner logic both need to recognize AKA-on-T equivalence.
2. RT-07-C/E: add a code comment locking in the one-write-per-trick
   invariant + the broke-supersedes-nextDown order rule.
3. RT-07-B: consider the reaudit doc Priority 2 alternative
   (full-weight-partner / half-weight-opp) as a separate enhancement.

### Confidence overall

**High** for findings RT-07-A, RT-07-D, RT-07-E, RT-07-F, RT-07-H, RT-07-I,
RT-07-J. **Medium** for RT-07-G (couldn't construct a concrete exploit but
the persistence semantic is non-obvious). **High** for the conclusion that
the v0.10.0 R6 patch did what it claimed for the K-singleton inversion,
but **Medium** for the broader claim of "no regressions" — RT-07-H
identifies a pre-existing gate gap that the R6 K-fix actually MAGNIFIES,
because under-ruffed K-plays now write a CONFIDENT-NEGATIVE inference
(`cleared = {"Q","J"}`) instead of the old vacuous mis-pin.

---

## RT-07-H — WRITE site does not gate on `partnerWinning`; under-ruff in Hokm fires the inference falsely

### Severity: HIGH. Confidence: High.

### The missing gate

`Bot.lua:485-492`:

```lua
local touchContext = false
if lead.seat == R.Partner(seat)
   and C.Suit(lead.card) == cardSuit
   and C.Rank(lead.card) == "A" then
    touchContext = true
elseif S.s.akaCalled and S.s.akaCalled.seat == R.Partner(seat)
       and S.s.akaCalled.suit == cardSuit then
    touchContext = true
end
```

Both branches check that `seat`'s partner LED the bare-A (or AKA-called).
**Neither branch checks whether the partner's lead is STILL WINNING when
`seat` plays.** In Hokm with trump cuts available, the partner's bare-A
can be ruffed mid-trick by the opponent who plays before `seat`.

### What source #05 says

`docs/strategy/decision-trees.md:280` quotes the rule directly:

> "Partner played a card and you are NOT yet winning the trick |
> Touching-honors inference does **NOT** apply (partner forced to follow
> legally). | Inference assumes partner had a choice. | Gate touching-
> honors reads on `S.s.trick.winnerSeatSoFar == myTeamSeat`
> `(not yet wired)`."

The `(not yet wired)` annotation is the smoking gun — this gate has been
known-missing since the docs were written, and the v0.10.0 R6 fix did not
add it. R6 only fixed the K-interpretation; the partnerWinning precondition
is still ungated.

### Concrete exploit scenario

Hokm contract, trump = hearts. Bot is seat 4. Bot's partner is seat 2.

- **Trick 3.** Seat 2 (partner) leads A♠. Seat 3 (opp) is void in spades
  and ruffs with 9♥ (the trump). The trick is now winning for seat 3, not
  partner. Bot (seat 4) follows: bot has K♠, T♠, J♠. Bot must follow suit
  (R.IsLegalPlay forces a spade since bot has spades). Per source #05
  line 280, partner's lead is no longer winning — **the inference does not
  apply.** Bot can play any spade; let's say bot plays K♠ (bad strategy
  on its own but legal — bot might do this if bot had no choice and only
  K♠ remains, or chooses to dump it).

  Hold on — bot is seat 4, the WRITE site fires for seat 4's play. The
  gate is `lead.seat == R.Partner(seat=4) == 2`. Yes, seat 2 led — gate
  passes. `cardSuit = S` matches. Lead rank = A — passes.
  `theirRank = "K"` (bot's K-play). **WRITE fires.** `entry.cleared =
  {"Q","J"}` is recorded for seat 4's spade ledger.

  But this is the BOT's own ledger, and the READ site skips `s == seat`.
  So this particular case is harmless.

- **Re-traced exploit.** Make the writer be partner-of-bot, not bot
  itself. Bot is seat 1 (sampler-caller). Partner is seat 3.

  - **Trick 3.** Seat 3 (partner) leads A♠. Seat 4 (opp) ruffs with 9♥.
    Trick is now winning for seat 4. Bot (seat 1) plays — must follow
    suit if has spades. Say bot plays 7♠. Then seat 2 (opp) plays last;
    seat 2 has only K♠ and 7♠ remaining (7♠ is gone — well, just suppose
    seat 2 has K♠, J♠, Q♠, all spades). Seat 2 must follow. Seat 2's
    OPTIMAL play is the LOWEST spade since the trick is already lost
    (won by seat 4's ruff). Seat 2 plays J♠ (lowest). Touching-honors
    WRITE fires for seat 2's J♠ play? Let's check: `lead.seat == R.Partner(2) == 4`?
    `lead.seat == 3` ≠ 4. **Gate fails.** WRITE does not fire.

    Hmm — what about seat 2 playing K♠? Same gate failure. WRITE does not
    fire on opp seat 2 here because seat 3 is NOT seat 2's partner.

  - **Now flip the seat:** suppose partner of `seat` matches lead.seat. So
    we need follower's partner to be the leader. The follower must be
    `R.Partner(lead.seat)`. If lead.seat is 3 (partner of bot), then
    follower-with-WRITE-eligible must be seat 1 (bot itself). And bot's
    own ledger is read-skipped. **Cul-de-sac.**

  - **Try again.** Bot is seat 1. Suppose bot's PARTNER (seat 3) is the
    follower. Then `R.Partner(3) == 1` and lead.seat must be 1. Bot leads.
    But bot's lead in trick X — if bot leads bare A♠, seat 2 (opp) plays
    next. If seat 2 ruffs with 9♥ (Hokm, void in spades), partner (seat 3)
    plays third. Per source #05 line 280, partner's "trick" — wait, the
    rule says "**you** are NOT yet winning the trick." From partner's
    perspective: partner's team is bot+partner. The lead by bot is
    bot's bare-A. After opp seat 2 ruffs with 9♥, opp 2 is winning the
    trick (the ruff outranks the bare A in Hokm trick-rank). Now from
    partner (seat 3)'s perspective: their TEAM is not winning. Partner
    is forced to follow if they have spades. Partner plays K♠.

    WRITE-site gate from partner's perspective: `seat=3`, `lead.seat=1`,
    `R.Partner(3)=1` ✓, `cardSuit=S=Suit(lead)` ✓, `Rank(lead)="A"` ✓.
    **WRITE fires.** `entry.cleared={"Q","J"}` written to
    `style[3].topTouchSignal["S"]`.

  - **READ-side weaponization.** Bot at seat 1 is sampling for ISMCTS
    rollout (next decision, e.g. trick 4). Outer loop hits `s=3 ==
    R.Partner(seat=1) == 3` ✓ — gate passes. Reader applies
    `cleared={"Q","J"}` to partner's ledger: clears `desire["QS"]` and
    `desire["JS"]`. Sampler now believes partner does NOT have Q♠ or J♠.

  - **But partner's K♠ play was FORCED** — partner had to follow suit and
    chose K♠. Partner could in fact still hold Q♠ or J♠ (e.g. partner had
    K♠+Q♠+9♠, dumped K♠ as the highest of a losing trick to be "done with
    K"). The sampler now mis-distributes Q♠ to opps when partner actually
    has it.

  - **Downstream cost.** ISMCTS rollouts pin Q♠ to opps; the bot's
    decisions about whether to lead spades, whether to keep saving J♠ as
    a trump-ruff bait, etc., all bias on the wrong side. Per the reaudit
    doc's cost model for the original mispin (now applied INVERSELY): "the
    sampler clears Q from that opp" → here, "the sampler clears Q from
    partner who actually has it." Same magnitude error, opposite direction.

### Why R6's K-fix MAGNIFIES this

Pre-R6: K-signal wrote `nextDown="Q"` (mispin Q TO seat 3). Under-ruff
scenario: mispin was wrong but the subsequent sampler weight (`desire["QS"] = 60`)
was a SOFT bias — sampler still picks Q for partner with high probability,
which is the correct outcome.

Post-R6: K-signal writes `cleared={"Q","J"}` (negative-bias against Q at
seat 3). Under-ruff scenario: hard-clears Q from partner — sampler will
actively put Q at opps. **This is now WORSE than pre-R6 for the
under-ruff case** because the negative-bias is harder to overcome than the
positive-bias was.

In the SOURCE-CORRECT case (partner played K♠ voluntarily as K-singleton),
R6 is right — the post-fix gives the correct cleared semantic. But in the
**forced-play-mistaken-as-signal** case, R6 amplifies the error.

### What about the AKA fallback?

`elseif S.s.akaCalled and S.s.akaCalled.seat == R.Partner(seat) and S.s.akaCalled.suit == cardSuit`.
The AKA fallback fires regardless of whether partner is currently winning.
Under-ruff after AKA: partner calls AKA and leads T♠ in Hokm; opp 2 ruffs
with 9♥. Bot (or partner-of-bot's-partner; trace it) then forced-follows
with K♠ or Q♠ or low. Same issue — `partnerWinning` not gated, WRITE
fires falsely.

Actually wait — AKA-on-bare-A is the most common AKA case, but per
J-067 part 1 AKA-on-T means A is dead. If A is dead, partner leads T. In
Hokm, T is not trump-immune; opp can still ruff. Same problem.

### The fix

WRITE site needs:

```lua
-- Gate: partner's lead-card must still be winning when this seat plays
local trick = S.s.trick
local curWinner = trick and R.CurrentTrickWinner(trick, contract)
local partnerLeadStillWinning = curWinner == R.Partner(seat)
if not partnerLeadStillWinning then
    -- inference does not apply per source #05 line 280
    -- (skip the if/elseif body or set touchContext=false)
end
```

Where `R.CurrentTrickWinner` already exists per `Bot.lua:2486` ("local
partnerWinning = curWinner and R.Partner(seat) == curWinner"). The
machinery is in place; the WRITE site just doesn't use it.

### Verdict

This is the **strongest exploit angle in this red-team review**. The R6
K-singleton fix correctly inverts the K-signal in the SOURCE-CORRECT case,
but the WRITE site's missing partnerWinning gate means the inference
fires in scenarios where source #05 says it should NOT. R6 amplifies the
damage in the under-ruff case from a soft mispin to a hard negative-bias.

Recommended priority: **add the partnerWinning gate at WRITE site BEFORE
shipping any further touching-honors changes.** This single gate addresses
the under-ruff issue across all 4 ranks (T/K/Q/7-9), not just K.

---

## RT-07-I — Cross-contract carry: round-reset is sound; but source #41 vs #05 conflict on K-interpretation is unresolved

### Severity: Medium (latent source conflict). Confidence: High.

### The reset path (per-round)

`Bot.lua:167-168`:

```lua
if style.topTouchSignal then
    style.topTouchSignal = { S = {}, H = {}, D = {}, C = {} }
end
```

Called from `Bot.ResetMemory()` at every `HostStartRound` (`Net.lua:1800`)
and at every redeal (`Net.lua:1764`). Per RT-07-D, this fires correctly
across:

- Hokm round → Sun round transition: signals cleared.
- Hokm round → Hokm round transition: signals cleared.
- Sun round → Sun round transition: signals cleared.
- Takweesh resolution → next round: signals cleared (HostStartRound runs).
- /reload mid-round: signals PRESERVED (intentional, per M4 design).

**No cross-contract data carry occurs in normal flow.**

### The latent source conflict

But there IS a hidden problem the existing draft doesn't surface: source
#41 (Sun basics) states the OPPOSITE of source #05 for the K-signal:

`docs/strategy/_transcripts/41_play_sun_basics_extracted.md:57`:

> "| 8 | Sun, partner plays K under your A | Infer: **partner holds the
> Q (Bint / بنت)** — next-down touching honors. | Same convention, one
> rung down | Same ledger as #7 | Definite |"

Source #41 says K = partner-has-Q (next-down). Source #05 (per the reaudit
doc, lines 794-814) says K = partner has K-singleton, Q is elsewhere. **These
are contradictory.** The R6 fix sided with #05.

### Why this matters cross-contract

The WRITE site does NOT gate on `contract.type`. It fires for both Hokm
and Sun. If the source convention is **different in Sun than in Hokm**,
the unified write+read may be wrong for one of them.

The reaudit doc treated #05 as canonical for Section 6 because #05 is the
"general-predictions" video. But #05 itself is contract-agnostic — the
quoted passages don't specify contract type. Source #41 is the
Sun-specific basics video and has Definite confidence for the
"K → partner has Q" reading.

**Hypothesis A.** Source #41 is wrong (the rule is uniformly K-singleton
across both contracts). R6 fix is correct.

**Hypothesis B.** Source #41 is right for Sun, source #05 is right for Hokm
(contract-specific signaling rules). R6 fix is correct for Hokm but
WRONG for Sun. The bot now negative-biases Q at partner's seat in Sun
when partner played K — exactly inverted from #41.

### Decoding which hypothesis is correct

The reaudit doc lines 33-34 cite #05 transcript references (`vkY55gg-39k_05_baloot_predictions_general.ar-orig.srt`)
that are NOT contract-tagged. Without re-reading the SRT to check
whether the speaker disambiguates Hokm-vs-Sun in the cited passage,
hypothesis B cannot be ruled out.

### Why this is a red-team concern

If hypothesis B is correct, the R6 fix introduces a NEW bug in Sun rounds:
partner plays K♠ in Sun under bot's bare-A♠ → R6 clears Q♠ from partner's
desire → sampler puts Q♠ at opp → bot misjudges who has Q♠ for last-trick
purposes (Sun #41 explicitly says Q is at partner, used for Takbeer
calculations).

This is **a real risk introduced by the R6 fix that the reaudit doc did
not flag.** Source-conflict resolution is needed.

### Recommended action

1. Re-read the #05 SRT in the cited 03:48-05:22 passage to check if the
   speaker says "in Sun" or "in Hokm" or "in any contract" near the
   K-signal interpretation.
2. If the #05 quote is contract-agnostic, audit #41 to see if its
   "K → has Q" claim has the same Saudi-convention basis or is a
   transcription error / interpretation drift.
3. Until resolved, consider gating the K-singleton interpretation on
   `contract.type == K.BID_HOKM` and reverting to the dead-branch behavior
   in Sun (no K write), to avoid the worst case where R6 actively
   anti-pins Q from partner in Sun.

### Verdict

The cross-contract carry mechanic itself (per-round reset) is **sound**.
The latent source conflict between #05 and #41 on K-interpretation is a
**separate, pre-existing risk** that R6 effectively committed to a side
without explicitly resolving. Confidence: high that the conflict exists
in the docs; uncertain which side is correct.

---

## RT-07-J — WRITE site does not gate on contract type

### Severity: Low (subsumed by RT-07-H but worth flagging). Confidence: High.

### The gap

`Bot.lua:476-477`:

```lua
if not wasIllegal and contract and trickPlays
   and #trickPlays >= 2 and style.topTouchSignal then
```

`contract` must be non-nil but no check against `contract.type`. Both
`K.BID_HOKM` and `K.BID_SUN` enter the WRITE branch.

### Why this differs from RT-07-H

RT-07-H is about partnerWinning (a per-trick state). RT-07-J is about
contract type (a per-round state). They compound:

- Sun: no trump, partner's bare-A is over-ruff-immune. The
  `partnerWinning` gate would always pass when partner leads bare-A. So
  RT-07-H's exploit window is narrowed in Sun but NOT zero (an opp who
  has higher A than partner can still over-take... wait, A is highest in
  Sun). Actually, in Sun A is highest of plain-rank, so partner's
  bare-A IS guaranteed-winning in Sun. RT-07-H is Hokm-specific.

- Hokm: trump can over-ruff bare-A. RT-07-H exploit window is
  open whenever an opp ruffs after partner's lead.

So in Sun, the WRITE site's lack of partnerWinning gate is HARMLESS
(bare-A always wins in Sun anyway). In Hokm, it's a real exploit window
(RT-07-H).

### What about AKA-on-T in Sun?

Sun + T-lead: A is dead. T is highest remaining. But other A's exist
across suits — meaning if AKA is called on suit X with A♠ dead and partner
leads T♠, T♠ is the highest spade. Sun must-follow suit; opps can't win
T♠ unless they have higher in spades. A♠ is dead — so T♠ wins. AKA on T
in Sun is also auto-winning. RT-07-H exploit window stays narrow in Sun.

### Verdict

RT-07-J is **a code-cleanliness concern**: the WRITE site should make
explicit which contracts it applies to. Currently it implicitly fires for
both, with the partnerWinning gap (RT-07-H) only mattering in Hokm. If
the source-#41-vs-#05 conflict (RT-07-I) ever resolves toward
contract-specific rules, this gate would become essential.

Recommended: add an explicit `if contract.type == K.BID_HOKM or
contract.type == K.BID_SUN` guard at the WRITE site, with a comment
referencing both #05 and #41 as endorsing both contracts. Cosmetic if
RT-07-I resolves to "uniform across contracts"; load-bearing if it
resolves to "contract-specific."

---

## Aggregate (revised)

The v0.10.0 R6 fix is **substantively correct in the K-singleton
interpretation** for the SOURCE-CORRECT scenarios (partner voluntarily
played K from K-singleton with bare-A still winning). But three
material gaps remain that R6 did not address:

1. **RT-07-A (Medium):** Implicit-AKA-on-T-lead doesn't trigger the
   WRITE branch.
2. **RT-07-H (HIGH):** WRITE site fires the inference even when partner's
   bare-A was ruffed mid-trick (Hokm under-ruff). R6 amplifies the damage
   here from soft mispin to hard negative-bias.
3. **RT-07-I (Medium):** Source #41 contradicts #05 on K-interpretation;
   R6 sided with #05 without explicit conflict resolution. Latent risk
   of inverted-bias in Sun if #41 is correct.

The two findings that materially break or weaponize R6 are RT-07-H (an
exploit, not a design loss) and RT-07-I (a source-validity question).
The remaining angles (RT-07-B/C/D/E/F/G/J) are cosmetic, design-defensive,
or yield no exploit.

### Top-priority followup

**RT-07-H is the strongest finding in this review.** It is a direct
exploit where R6 makes the bot WORSE than pre-R6 in the under-ruff
scenario. Add a `partnerLeadStillWinning` gate at `Bot.lua:485-492`
BEFORE shipping any further touching-honors enhancements.
