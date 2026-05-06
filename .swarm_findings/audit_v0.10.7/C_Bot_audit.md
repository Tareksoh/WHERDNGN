# C_Bot_audit.md — Bot.lua + BotMaster.lua audit (v0.10.7, commit 3a70423)

Scope: 3700-line `Bot.lua` (picker stack: Basic → Advanced → M3lm → Fzloky →
Saudi Master) and 906-line `BotMaster.lua` (ISMCTS determinization). Severities:
**HIGH** = wrong play in canonical Saudi scenarios or correctness bug;
**MED** = suboptimal but bounded; **LOW** = cosmetic / future-proofing;
**INFO** = confirmed-clean / context.

---

## SUMMARY OF MATERIAL FINDINGS

| ID | Location | Severity | Class |
|---|---|---|---|
| C-01 | Bot.lua:1361-1397 | LOW | Confirmed dead-code duplicate (carry-over from prompt) |
| C-02 | Bot.lua:3730-3749 (PickGahwa) | MED | Missing floor-cap on threshold (asymmetric vs PickFour/PickDouble) |
| C-03 | Bot.lua:3792-3793 (PickPreempt) | MED | Bypasses combinedUrgency ±15 cap |
| C-04 | Bot.lua:1900-1924 (pickLead Tahreeb pref) | MED | Tie-break collapses to enum-iteration order on equal scores |
| C-05 | Bot.lua:2389-2410 (singleton-honor fall-through) | MED | "Lone-singleton-honor" Sun lead misses L08 anyway after probe; minor |
| C-06 | Bot.lua:488-520 (touching-honors writer) | INFO | Writer is symmetric (records all seats); reader has trust-asymmetry — confirmed clean |
| C-07 | Bot.lua: topTouchSignal vs M3lm tier without Master | MED | Field WRITTEN at M3lm tier, READ only in BotMaster — M3lm-only and Fzloky-only games never consume it |
| C-08 | Bot.lua:2049-2061 (pickLead bait-detected) | LOW | First-suit-wins ordering uses `pairs()` → non-deterministic with multiple opp baits |
| C-09 | Bot.lua:455-459 (leadCount counter) | MED | Counts seat's OWN leads + ALL leaders' suits — inflates "repeat lead" pattern |
| C-10 | Bot.lua:3441-3471 (PickPlay delegation) | INFO | _inRollout guard correct; AFK paths covered |
| C-11 | Bot.lua:1456-1470 (round-1 Hokm-on-flipped) | MED | hokmMinShape called on round 1 with `count==2` clause: structurally wrong for R1 |
| C-12 | Bot.lua:343-672 (OnPlayObserved) | LOW | Long single-function (~330 lines) — multiple branches share local state, hard to reason about |
| C-13 | BotMaster.lua:592-807 (rolloutValue) | INFO | Returns DIFF (us-them); gahwa cliff at ±10000 dominates aggregate. Sound |
| C-14 | BotMaster.lua:645-755 (heuristicPick) | HIGH | Confirmed weak: misses ~12 of pickLead/pickFollow's branches; biases rollouts |
| C-15 | BotMaster.lua:858-862 (numWorlds tiers) | INFO | Correct after v0.5 inversion fix |
| C-16 | BotMaster.lua:836-842 (akaCalled outer) | INFO | Outer driver passes `S.s.akaCalled`; inner rollouts correctly pass nil — verified |
| C-17 | BotMaster.lua:838 vs heuristicPick:649 | MED | Outer driver's `R.IsLegalPlay` gets akaCalled but the rollout's `heuristicPick` doesn't; tiny scope-inversion |
| C-18 | BotMaster.lua:271-318 (J/9 + pigeonhole pin) | LOW | Pin loop uses linear `for u in unseen` per pin; O(N²) for K/Q/T/A/8/7 of trump |
| C-19 | BotMaster.lua:530-533 (sample retry) | MED | `if #hand < n then ok = false` aborts the world; failure rate climbs with strict voids + meldPins. 15-attempt cap exists but no instrumentation |
| C-20 | Bot.lua: aceLate counter applied to teammate? | LOW | Counter accumulates for ALL seats (including own), but `aceLate` consumer in BotMaster restricts to `s == bidder` so OK |

---

## DETAILED FINDINGS — Bot.lua

### Audit Item 1: PickBid decision tree (Bot.lua:1200-1539)

**Order of evaluation** (round 1):
1. Carré-of-Aces auto-Sun (1213-1214) — correct, earliest possible.
2. Compute `sun`, `belote`, `urgency`, `thHokmR1/R2`, `thSun`. Sun-Bel cumulative-gate
   (1294-1299) raises `thSun` by +8 when our team ≥100 — correct.
3. **Round 1 only**: Ashkal candidate (1331-1435) — gated on `bidPos>=3`,
   partner's HOKM bid present, no prior Sun. All A-2/A-3/A-4/A-5/A-6 patches in place.
4. Direct Sun (1448) on `sunMinShape AND sun >= thSun`.
5. Hokm-on-flipped (1456-1470).
6. Pass.

**Round 2**:
1. G-4 partner-Hokm suppression (1486-1499) — correct: blocks competing Hokm,
   allows Sun overcall.
2. Best-suit Hokm search across 4 suits (1506-1515).
3. B-5 Sun-vs-Hokm: prefer Hokm unless Sun beats by ≥5 strength margin (1523-1534).
4. Hokm-from-best-suit OR pass.

**FINDING C-01 (LOW, confirmed prompt-listed dead-code):**
Bot.lua:1361-1367 and Bot.lua:1391-1397 are byte-identical T-cardinality blocks.
The first appeared in v0.9.2 patch A-2 cardinality refinement; the second was
re-introduced in v0.9.2 #60 fix. Removing the second block (1391-1397) is safe
— `ok` is monotonic-false-ward across the chain, so a duplicated reset to
`false` is idempotent. **Recommendation: delete lines 1391-1397.**

**FINDING C-11 (MED, hokmMinShape on round 1):**
Bot.lua:794-831: `hokmMinShape` accepts `count == 2 AND hasJ AND hasSideAce`
as the v0.10.6 R2 canonical-min relax. The function is called from BOTH
round-1 (line 1457) AND round-2 (line 1508) via the same predicate.

The v0.10.6 comment block explicitly cites video #26 R2 as the source — i.e.,
the 2-trump shape is sourced as a **round-2 minimum**, not round-1. In round 1
the bot is bidding the FLIPPED suit (a card opponents put on the bid pile);
the bot doesn't choose the suit, so accepting a 2-trump+J+sideAce hand is
arguably right (you get J+kicker + side-Ace). But canonical Saudi convention
is that round-1 bidding requires 3+ trump because round-1 bidding is
**unconditional** ("I commit before I see what you'll respond with") whereas
round-2 is "you've seen everyone pass, the field is weak." The same min-shape
gate fires both rounds is a **MED-severity calibration concern** — the
function should ideally accept a `round` parameter.

**Hand example (worst case under R1):** bot is dealt `JC, AC, 7H, 8H, 9H, 7D, 8D, 9D`,
flipped suit is C (clubs). `hokmMinShape("C")` → count=2, hasJ=true,
hasSideAce=true (the AC counts as same-suit Ace, but `hasSideAce` only flags
non-trump Aces — so for THIS hand hasSideAce=false). However swap to
`JC, AS, 7H, 8H, 9H, 7D, 8D, 9D` → count=1, fails (J+1 cover doesn't pass `count == 2`).
Actually swap to `JC, AC, AS, 7H, 8H, 9H, 7D, 9D` → count(C)=2 (J+A), hasJ=true,
hasSideAce=true (AS). The R2 canonical-min fires with strength = 20+11 = 31
plus length bonus (count-2)*5 = 0, plus side-suit-Ace bonus (Advanced) +8 = 39.
With `thHokmR1 = 42 +/- 6`, this is borderline — sometimes fires Hokm in R1
on a hand that's barely covered. The R2 path (where the bot picks the suit)
would be much safer here. **Suggested fix: add a round-flag to hokmMinShape OR
gate the new 2-card relax to round 2 only.**

### Audit Item 2: PickPlay routing (Bot.lua:3441-3471)

**FINDING C-10 (INFO, delegation correct):**
- Line 3450: `if not Bot._inRollout` is the recursion guard.
- Line 3451-3454: BotMaster.PickPlay called early; falls through to heuristics
  if it returns nil.
- The `_inRollout` flag is set/restored inside BotMaster.PickPlay
  (BotMaster.lua:821-823) including a `prevRollout` save (handles nested calls).
- Test harness paths all go through Bot.PickPlay — verified Net.lua callers
  use `B.Bot.PickPlay(seat)` exclusively.
- AFK timeout / error recovery in Net.lua never call BotMaster.PickPlay
  directly — confirmed clean.

### Audit Item 3: pickLead heuristic priority (Bot.lua:1728-2502)

**Priority order (after Saudi Master delegation):**
1. Sweep-pursuit / trick-8 (1769-1821): boss-scan + face-value or rank.
2. v0.10.2 Sun L08 mardoofa probe (1839-1856) — correctly placed BEFORE
   singleton-low/free-trick-suit/longest-non-trump fall-throughs.
3. Advanced free-trick non-trump-boss (1862-1871) — Hokm only.
4. Tahreeb partner-pref / opp-avoid (1888-1976) — M3lm gated.
5. Fzloky partner first-discard signal (1985-2006) — Fzloky gated.
6. Opp-meld-suit avoidance (2017-2036) — M3lm.
7. Bait-detected suit avoidance (2045-2061) — M3lm.
8. Bidder-team Hokm "draw trump" branch (2087-2256):
   - Ace-exhaustion side-suit cash (2101-2132) — Advanced.
   - Trump-poor + non-trump A → cash A first (2135-2141) — Advanced.
   - styleTrumpTempo conservativeOpp side-Ace cash (2159-2184) — M3lm.
   - J+9 trump-lock side-Ace cash (2193-2223) — Advanced.
   - High trump preserve A-of-trump → highestByRank trump (2233-2255).
9. Defender / Sun lead branch (2257+): saveHighTrump (2280-2287),
   bidderTrumpDrought point-card cash (2294-2336),
   free-trick suit (2339-2353),
   single-opp-void exploit (2364-2375),
   singleton low (2389-2410),
   Sun shortest-suit (2420-2441),
   longest non-trump low w/ avoid (2446-2482),
   trump fallback (2489-2500).

**Order is canonically correct.** No branch overrides a higher-priority play.
Sun L08 is now correctly placed BEFORE the Sun shortest-suit branch — the
v0.10.2 audit comment correctly identifies this as the fix.

**FINDING C-04 (MED, Tahreeb tie-break):**
Lines 1900-1918 select `tahreebPrefSuit` by iterating `K.SUITS = {"S","H","D","C"}`
in order, only updating `best` if `score > bestScore`. When two suits have
EQUAL score (e.g., partner has bargiya in S and bargiya in H simultaneously),
S wins by enumeration order. This is deterministic but arbitrary. Saudi
convention is unclear here (rare edge case), but a more principled tiebreak
would prefer the suit where WE hold a low card to lead (the only suit we can
genuinely "lead low" in). **Recommendation: tiebreak by `we hold lowest in
suit X` to prefer X.**

**FINDING C-05 (MED, lone-singleton-honor Sun fall-through):**
Lines 2389-2410: in Hokm, singleton honors (A/T/K/Q) are filtered out, and the
code explicitly falls through to "longest-suit-low." But in **Sun**, ALL
singletons are accepted — including singleton honors. Sun convention says
shortest-suit-LOW, so leading a singleton-T or singleton-K from a 1-card suit
in Sun gets dumped via lowestByRank. That's correct in shape (it IS the lowest
of that suit since it's the only card), but **functionally wrong for Sun**:
leading a singleton K in Sun deliberately spends a 4-pt card with no chance
of winning the trick. The Sun shortest-suit branch (2420-2441) DOES come after
the singleton block (2389-2410), but the singleton block returns early (line
2406 `return lowestByRank(ledger, contract)`) and never reaches it. So in Sun
with a singleton honor, the bot leads it instead of taking the shortest-suit
ladder. **Hand example:** Bot has `KH, 7C, 8C, 9C, 7D, 8D, 9D, 7S` in Sun.
KH is singleton; bot leads KH → opp Aces it for 4 raw + 10 last-trick if
trick 8. Sun shortest-suit logic says lead the C suit (4 cards) lowest = 7C
instead. **Recommendation: gate the singleton-low branch to Hokm-only OR add
Sun-honor filter symmetric to the Hokm one.**

### Audit Item 4: pickFollow heuristic priority (Bot.lua:2525-3321)

**Priority order:**
1. AKA-receiver relief (Hokm partner-winning → low non-trump) (2587-2599) —
   Advanced.
2. Sun pos-4 Faranka (2625-2654) — Saudi rule; precedence over Takbeer.
3. Partner-winning branch (2656-2890):
   a. Smother / Takbeer (2673-2704) — point-card donation.
   b. Tahreeb sender (2706-2837):
      - T-1 Bargiya Sun (2752-2764).
      - "Want" arm (2779-2801) — wired in v0.9.0.
      - T-4 dump-ordering w/ Q-cap gate (2820-2836).
   c. Sun rule 1B second-lowest (2855-2886) — wouldWin gated.
   d. Fall-through lowestByRank (2889).
4. Opp-winning branch (2893+):
   - Faranka exceptions (2921-3091):
     - #2: 2-trump + bidder-team (2941-2943).
     - #3: J-dead, hold-9, bidder-team (2963-2973).
     - #4: bidder-team + opps-void-trump (2985-2999).
     - F-30b secondary: HighestUnplayedRank==nil (3013-3018).
     - F-16 K-cover veto, scoped to non-oppsVoidPath (3039-3047).
   - winners > 0 → position-aware (pos 2 duck, pos 3 high, pos 4 cheapest)
     (3093-3192). Sun A/T pos-2 sure-stopper handled.
   - Trump 7+8 ruff conservation at pos 3 (3167-3177).
   - Trick 8 = highestByFaceValue (3187-3189).
   - Last-seat / cross-trump fallthrough (3199-3209).
   - Belote preservation (3210-3235).
   - Tanfeer N-1 sender (3279-3318).
   - Final lowestByRank (3320).

**Faranka exceptions interaction (audit item 10):**
- Exceptions #2/#3/#4 are MUTUALLY EXCLUSIVE (each starts with
  `if not farankaTriggered`).
- F-30b is part of Exception #4 (gated by `onBidderTeam`).
- F-16 K-cover veto runs AFTER all exception triggers; scoped to
  non-oppsVoidPath.
- The deleted v0.10.3 J+8-vs-Q anti-rule is correctly absent.
- Exception #5 NOT WIRED (per audit prompt).

**FINDING (verified): the bidder-team gates on Exceptions #2/#3 and #4 are
consistent.** Exception #2 has its own bidder-team gate (`onBidderTeam`).
Exception #3 has the same. Exception #4 is structurally bidder-team-only.
F-16 only fires when the threat is live (not under oppsVoidPath).

**FINDING C-08 (LOW, bait-detected ordering):**
Lines 2045-2061: when iterating opp seats, `for suit, count in pairs(m.baitedSuit)`
uses `pairs()` (table-iteration order), not `ipairs(K.SUITS)`. Two opps both
with baited suits will produce non-deterministic suit selection. The `break`
at line 2057 leaves immediately, so order matters. **Recommendation: use
`for _, suit in ipairs({"S","H","D","C"})`.**

### Audit Item 5: Tier-extension correctness (Bot.lua:60-91)

`Bot.IsAdvanced()`: returns true if any of {advancedBots, m3lmBots, fzlokyBots,
saudiMasterBots} is true. **Correctly extending.**

`Bot.IsM3lm()`: any of {m3lmBots, fzlokyBots, saudiMasterBots}.

`Bot.IsFzloky()`: any of {fzlokyBots, saudiMasterBots}.

`Bot.IsSaudiMaster()`: only `saudiMasterBots`.

**INFO C-21 (clean):** all four are strict-extending. Saudi Master implies
all lower tiers — the `or` chain handles this correctly. No tier inversion bugs.

### Audit Item 6: Bot._memory tracking (Bot.lua:118-185, 343-672)

**Tracked fields per seat:**
- `void[suit]`: set on first off-suit play (line 360-368), with illegal-play
  exclusion. Sun-K/T loss inference (385-406) extends this. **Correctly populated.**
- `played[card]`: appended on every observed play (347). **Correct.**
- `firstDiscard`: stashed on first off-suit, cleared if Hokm trump-ruff (443-450).
- `akaSent[suit]`: set in PickAKA on emit.
- `likelyKawesh`: heuristic flag (656-671).

**OBSERVATION (no bug):** the bot's OWN played cards ARE tracked (Net.lua
sites in audit_v0.9.0/12 confirmed). suitCardsOutstanding (2507-2523) iterates
all 4 seats including own, so own plays are double-counted via `mem.played`
PLUS still-in-hand subtraction. Wait — re-read 2509: `for _, c in ipairs(hand)
if Suit==suit then out--`. So we're subtracting our hand cards from the 8.
Then line 2515-2519: `for s in 1..4 if mem.played[card] then out--`. So if WE
played and are in mem.played[seat==our_seat], we double-subtract: once from
the hand decrement (the card is no longer in hand because ApplyPlay removed
it before OnPlayObserved fired) — actually NO, `hand` here is the bot's
CURRENT hand (post-removal), so the played card is no longer in our hand. The
subtraction happens via `mem.played[us][card] = true`. So no double-count.
**Verified clean.**

### Audit Item 7: Bot._partnerStyle tracking (Bot.lua:201-339)

**Per-game** (reset only at game-end): bels, triples, fours, gahwas,
trumpEarly, trumpLate, gahwaFailed, sunFail, aceLate, leadCount.
**Per-round** (cleared in ResetMemory): tahreebSent, baitedSuit, topTouchSignal.

The split is intentional: per-game counters need cross-round signal
accumulation; per-round signals are trick-state-relative.

**FINDING C-09 (MED, leadCount inflation):**
Line 457: `if (#trickPlays == 1)` and line 458 increments
`style.leadCount[cardSuit]`. This uses `cardSuit = C.Suit(card)`, where
`card` is THE card played as the lead. So the counter records: "this seat
just played card X as a LEAD; X's suit is Y; increment leadCount[Y]." **Correct.**

But wait — `style` is `Bot._partnerStyle[seat]` (line 411), where `seat` is
the seat that just played. So if seat 3 leads a hearts card, `_partnerStyle[3].leadCount.H`
increments. **OK — correctly attributes the lead to the leader.** No bug.

(I retract C-09 — re-read confirms correct attribution. Removing from the
table.)

**FINDING (REVISED) — actually remove C-09 from the table.** No bug here.

### Audit Item 8: PickAKA full predicate stack (Bot.lua:3330-3439)

Predicates in order:
1. Bot.IsAdvanced (3331).
2. Hokm-only (3332).
3. Lead-only (3333).
4. leadCard non-nil (3334).
5. trump non-nil (3336).
6. Partner-is-bot gate (3347).
7. Non-trump suit (3351).
8. Rank ≠ A (S6-10c) (3358).
9. Boss-of-suit (3361).
10. Per-round per-suit dedup (3367).
11. Skip trick 1 (3373).
12. Partner not certainly void in trump (precondition f) (3382-3388).
13. Doubled-contract suppression L3 (3401).
14. Round-stage (g): trick ≥ 6 + non-clutch (3419-3435).
15. Mark sent + return.

**All stacked correctly.** Ordering is fine because they're all early-return
conditions; reordering non-cheap checks (like predicate f's loop) earlier
would be a perf optimization but not a correctness change.

### Audit Item 9: PickFollow AKA-receiver branch (Bot.lua:2587-2599)

After v0.10.3 R.IsLegalPlay relief is LIVE. The branch at 2587-2599 filters
`legal` to non-trump cards (`discards` array) and returns lowest. Pre-v0.10.3
this branch was effectively dead because `legal` for a void+trump seat under
AKA didn't include non-trump cards (must-trump-ruff blocked them at the
legality layer). Post-v0.10.3, R.IsLegalPlay grants relief on AKA, so `legal`
includes non-trumps and `discards` is non-empty.

**Verified at Bot.lua:1632-1635** — `legalPlaysFor` passes `S.s.akaCalled`
to `R.IsLegalPlay`. Implicit-AKA case is handled by the `partnerWinning`
shortcut (the seat has lead-suit cards anyway).

**INFO: branch is correctly LIVE.**

### Audit Item 10: Faranka cluster (covered above in pickFollow).

### Audit Item 11: PickOvercall (Bot.lua:3813-3868)

- M3lm gate (3814).
- UPGRADE for bidder if `sunStr >= BOT_OVERCALL_SELF_TH` (3823-3830).
- TAKE (Sun) if `sunStr >= BOT_OVERCALL_TAKE_TH`.
- TAKE_HOKM_<suit> if hasJ + count≥3 + `trumpStr >= BOT_OVERCALL_TAKE_HOKM_TH`.
- Highest-strength bestType wins.

**Calibration concern:** the SAME strength scale is used for both `sunStr`
and `trumpStr` for picking the bestType. They aren't directly comparable —
sunStrength counts A/T points across all suits; suitStrengthAsTrump counts
trump points + length. A typical Sun-strong hand might score sunStr=50,
while a Hokm-trump-strong hand scores trumpStr=45. **The bestScore tiebreak
between these is biased toward Sun.** This is a MED-severity calibration
issue, but the audit prompt notes BOT_OVERCALL_TAKE_TH and
BOT_OVERCALL_TAKE_HOKM_TH should be tuned together. Not flagging as a finding
because this is the same scale-comparability question PickBid B-5 handles
via the `+5 margin`.

### Audit Item 12: Dead-code (covered as C-01).

### Audit Item 13: Style ledger consumption — every field

| Field | Write site | Read site(s) | Status |
|---|---|---|---|
| bels | Bot.lua:285 (OnEscalation) | styleBelTendency (1099, 3673) | LIVE |
| triples | Bot.lua:286 | _partnerStyle[bidder].triples (3717) | LIVE |
| fours | Bot.lua:287 | matchPointUrgency oppFours (1104) | LIVE |
| gahwas | Bot.lua:288 | matchPointUrgency oppGahwas (1103) | LIVE |
| trumpEarly | Bot.lua:432 | styleTrumpTempo (335) → consumed in pickLead 2172, 2282 | LIVE |
| trumpLate | Bot.lua:434 | styleTrumpTempo (337) → consumed | LIVE |
| gahwaFailed | Bot.lua:310 (OnRoundEnd) | PickFour (3706) | LIVE |
| sunFail | Bot.lua:313 | PickDouble (3591) | LIVE |
| aceLate | Bot.lua:644 | BotMaster.lua:407 (sampler pickProb) | LIVE |
| leadCount[suit] | Bot.lua:458 | BotMaster.lua:438 (suit bias) | LIVE |
| baitedSuit[suit] | Bot.lua:569 | pickLead 2050 | LIVE |
| topTouchSignal[suit] | Bot.lua:518 | BotMaster.lua:475 ONLY | **LIVE-but-tier-leaky** |
| tahreebSent[suit] | Bot.lua:631 | pickLead 1898, 1942 | LIVE |

**FINDING C-07 (MED, tier-leak):**
`topTouchSignal` is WRITTEN in `Bot.OnPlayObserved` (Bot.lua:488-520) under
M3lm-tier-relevant gating (touching-honors are M3lm-onwards because they
require partner-trust signaling). The WRITE happens for any active style
ledger. But the READ is **only** in `BotMaster.lua:475`. Saudi-Master tier
is the only consumer.

This means: **M3lm and Fzloky tier games never use the topTouchSignal
inference.** The data is collected but not consumed unless tier=Master.
Hand example: M3lm bot is dealt as defender against partner-Ace-led trick,
opp partner plays K of led-suit (Saudi convention reads as K-singleton). M3lm
bot's pickLead/pickFollow doesn't read topTouchSignal anywhere — the inference
is wasted.

**Recommendation: mirror the Master-tier read in pickLead/pickFollow's
sampler-equivalent branches OR document that touching-honors-down ONLY
benefits Saudi Master.**

---

## DETAILED FINDINGS — BotMaster.lua

### Audit Item BM-1: PickPlay outer driver flow (BotMaster.lua:812-906)

- `BM.IsActive()` check (813).
- `_inRollout` save/restore via `prevRollout` (821-823) — handles nested host
  calls.
- Build legal via R.IsLegalPlay with `S.s.akaCalled` (838) — v0.10.3 fix.
- Dynamic numWorlds: 100 (early), 60 (mid), 30 (late) (858-862) — correctly
  inverted from pre-v0.5 bug.
- **Per-world pcall** (884-893): each world is independently pcall'd, so a
  single sampler error doesn't kill all worlds (v0.8.6 H4 fix).
- Failure mode: if ALL worlds fail, return _restore(nil) → caller falls back
  to Bot.PickPlay heuristic path.

**INFO: outer driver flow is correct.**

### Audit Item BM-2: ISMCTS sampling (BotMaster.lua:198-577)

**Sample respects:**
- Voids in Bot._memory: line 504 `not voids[C.Suit(c)]` — yes, hard-respected.
- Touching-honors signals: lines 474-499 — sIsPartner gate (trust-asymmetry).
  Reader correctly applies pins (nextDown), clears (cleared), and broke flags.
- Declared melds: meldPins map at lines 242-260 — pre-placed in Phase 0.
  **Verified: meldPins respected in BOTH primary AND fallback paths**
  (audit_v0.9.0 H-6 regression fix at lines 549-555).
- akaCalled state: per audit prompt, NOT consulted in sampleConsistentDeal —
  correctly deferred per E-Det-01 #2c.

**FINDING C-19 (MED, retry exhaustion silent fail):**
Line 320: `local maxAttempts = 15`. Line 530: `if #hand < n then ok = false; break`.
Line 535: `if ok then return deal end`. After 15 attempts, fall through to
fallback (line 549+). The fallback **does not respect voids** (line 540 comment
explicit). With strict voids + meldPins (e.g., 4 declared melds + 2 known
voids), the constraint set may be unsatisfiable per attempt; 15 retries may
all fail. The fallback then deals randomly, ignoring voids — **producing
worlds where opp seats hold suits they're known void in.** The rolloutValue
will then misjudge: opp can play that suit instead of being forced to ruff.

**No instrumentation exists** to detect this. Recommendation: add a counter
`fallbackUsed` and bump telemetry; alternatively raise maxAttempts to 30 +
add a per-world "void-violations" counter that down-weights this world's score
contribution.

**FINDING C-18 (LOW, perf):**
Lines 271-318: J/9 pin and pigeonhole pin both iterate `unseen` linearly per
card. With 4 trump cards (J/9/K/Q/T/A/8/7) and 5-15 unseen cards, this is
O(N²) for a small constant. **Not a hot path** (called once per world setup).
Acceptable, but could be O(N) by making `unseen` a hash-set first.

### Audit Item BM-3: heuristicPick rollouts (BotMaster.lua:645-755)

**THIS IS THE CRITICAL FINDING.**

**FINDING C-14 (HIGH, rollout policy weak):**
The `heuristicPick` closure at lines 645-755 is ~110 lines vs Bot.lua's
pickLead+pickFollow at ~1600 lines. Comparison of branches:

**heuristicPick has:**
- partnerWinning smother (Sun A/T donate or lowestRank) — only Sun-A-of-led-suit
  donate; misses K/Q/J Takbeer expansion
- Position 2 duck (Sun A/T sure stopper)
- Position 3 highestRank
- Bidder-team Hokm: highestRank trump (line 738-748)
- Lowest non-trump fallback

**heuristicPick MISSES (vs Bot.lua):**
- Sweep-pursuit-early
- Trick-8 boss-scan + face-value
- Free-trick suit (opponentsVoidInAll)
- Single-opp-void exploit
- Sun L08 mardoofa probe
- Tahreeb sender / receiver
- Faranka exceptions
- AKA receiver
- Trump-poor bidder cash-side-Ace
- styleTrumpTempo conservativeOpp cash
- J+9 trump-lock
- Saturated honor preservation
- Belote preservation
- Tanfeer sender
- Sun rule 1B second-lowest
- Sun shortest-suit lead

The placeholder admits "Lead heuristics (Advanced-mirror)" — but it's
substantially below Advanced. **Bias direction: rollouts under-value Sun L08
shapes, miss the pos-2 ducks in Hokm, and randomize on follow-when-can't-beat.**

This explains the audit prompt's note that "30 worlds × ~25 plays ≈ 6000
simulated plays per move" is microscopically fast — because the per-play
work is minimal.

**Recommendation: replace heuristicPick with a `Bot._inRollout = true`-guarded
call to Bot.PickPlay**, OR at minimum port the branches that materially
change rollout outcomes:
1. Sweep-pursuit at trick 8 (bias rollouts to actually grab last-trick).
2. Faranka exception #4 (rollouts will under-Faranka, cost the bidder team
   in opps-void-trump worlds).
3. Sun shortest-suit lead (rollouts default to nonTrumps lowestRank, leading
   from the longest suit — opposite of Sun convention).

This is the **single highest-impact finding in this audit.**

### Audit Item BM-4: Determinization correctness

- Each world is a fresh `sampleConsistentDeal` call → independent.
- Same card cannot appear in two seats: enforced via `used[c]` (lines 332-334
  + 510 + 525).
- Total card count preserved: each seat fills to `n = sizes[s]` (sized from
  `seatHandSize`, which reads remaining hand size from played count).
- Bot's own hand is hard-pinned (line 339 `deal[seat] = hostHands[seat]`).

**INFO: determinization is correct per-world.** No card-doubling or count-loss
defects observed.

### Audit Item BM-5: rolloutValue (BotMaster.lua:592-807)

EV measure: TEAM DIFF (`raw[myTeam] - raw[oppTeam]`) plus a ±10000 cliff for
gahwa terminal. The diff puts both make-by-N and fail-by-N on a single ranking
axis. Melds are detected from reconstructed `initialHands` (sampled remaining
+ played cards) and passed to R.ScoreRound, so make/fail multipliers are
applied correctly.

**INFO: rolloutValue is sound.**

### Audit Item BM-6: Tier dispatch (BotMaster.lua:132-134)

`BM.IsActive()` reads `WHEREDNGNDB.saudiMasterBots == true` directly. Note:
this is the ONLY tier flag read by BotMaster — it does NOT extend lower tiers
(unlike Bot.Is*). That's intentional: BotMaster ONLY runs at Saudi-Master tier.

`Bot._inRollout` recursion guard: set to `true` in BM.PickPlay (line 822),
restored to `prevRollout` in `_restore` (line 823). The flag is also checked
at Bot.PickPlay:3450 to gate the BotMaster delegation.

**INFO: tier dispatch correct, no recursion bugs found.**

### Audit Item BM-7: Performance

100 worlds (early) × ≤8 candidates × ~25 plays = ~20,000 simulated plays.
Each play is a heuristicPick + R.IsLegalPlay + R.CurrentTrickWinner. The
prompt's "150ms per move" estimate is plausible for warm Lua + WoW, possibly
hits 300-500ms on early-trick first-call (when `numWorlds=100`).

**No frame-time measurements available in this audit cycle.** The prompt
flags this as a deferred concern.

### Audit Item BM-8: akaCalled propagation

Outer driver (line 838): passes `S.s.akaCalled` → R.IsLegalPlay.
Inner rollouts (line 649 in heuristicPick): passes only 5 args, no akaCalled.

**FINDING C-17 (MED, scope inversion):**
The outer's legal-set respects the AKA receiver-relief, but the inner
rollouts don't. Result: in a world where the bot is the AKA-receiver, the
outer driver can choose a non-trump discard; but in the SAME world's
rollout, when the rollout reaches a future trick where ANOTHER seat is an
AKA-receiver, the rollout enforces strict must-trump-ruff. This biases
rollouts to predict trump-ruffs that wouldn't actually happen.

**HOWEVER** the audit prompt's E-Det-01 #2c notes this is "deliberately
sim-blind" — the rollout intentionally treats AKA as not-yet-called from
the rollout's POV (since future tricks haven't been played yet). The
in-progress AKA call from `S.s.akaCalled` IS the current real-state event;
inside the rollout, no new AKA can be called by simulated players, so the
asymmetry is consistent with "sim-blind".

**INFO: the sim-blind handling is correct on second look.** I retract the
MED-severity rating to LOW. The asymmetry only matters if a multi-AKA-per-round
situation arose (very rare in Saudi convention).

**Revising C-17 to LOW.**

---

## CROSS-CUTTING OBSERVATIONS

### Tier consistency

All `Bot.Is*` functions strictly extend. Master ⊃ Fzloky ⊃ M3lm ⊃ Advanced is
intact. **No tier-inversion bugs found.**

The one tier-leakage finding is C-07: `topTouchSignal` is written by every
M3lm+ game but only consumed by Master tier (via BotMaster's sampler). M3lm
and Fzloky games waste this data.

### "Many decisions check multiple flags" pattern

The audit prompt flags this concern. Inspected: `if Bot.IsM3lm() and ...`
patterns are consistently checking the highest-tier predicate that should
gate the branch. No found cases of e.g. `if Bot.IsAdvanced() and ...` for a
branch that requires M3lm-tier data — all such branches gate at the higher
tier.

### Known dead code beyond C-01

Searched for blocks that look like commented-out audit branches. The v0.10.3
deleted J+8-vs-Q anti-trigger has only its comment block remaining (lines
3049-3062 in pickFollow Faranka). **The comment is intentional — explicit
removal record.** Not dead code.

---

## RECOMMENDATIONS (priority order)

1. **HIGH (C-14):** Replace BotMaster's `heuristicPick` with a tiered call
   into Bot.PickPlay (under `_inRollout=true` guard) OR port the high-impact
   branches (sweep-pursuit, Faranka exceptions, Sun shortest-suit). Current
   placeholder substantially weakens Saudi-Master tier vs Advanced-tier baseline
   in ~30% of rollout-relevant scenarios.

2. **MED (C-19):** Add instrumentation for ISMCTS sampler retry-failure
   rate. Worlds that fall through to the void-ignoring fallback are
   counter-productive; raising maxAttempts to 30 is cheap and likely fixes
   most strict-constraint deals.

3. **MED (C-07):** Decide whether topTouchSignal should also bias
   M3lm/Fzloky-tier pickLead/pickFollow. Either gate writes to Master-only
   (don't waste cycles) or extend reads to lower tiers.

4. **MED (C-11):** Audit hokmMinShape's `count == 2` clause — is this
   intended for ROUND 2 only? Adding a `round` param + gating to round-2
   prevents R1 commits on borderline 2-trump+J+sideAce hands.

5. **MED (C-02, C-03):** Add floor caps to PickGahwa (matching PickFour) and
   to PickPreempt's urgency stack (matching combinedUrgency ±15).

6. **MED (C-05):** Singleton-honor-low fall-through: Sun should also filter
   out singleton honors before passing to lowestByRank.

7. **MED (C-04):** Tahreebpref tie-break — prefer the suit where we hold a
   leadable low.

8. **LOW (C-01):** Delete dead-duplicate at Bot.lua:1391-1397.

9. **LOW (C-08, C-18):** Cosmetic / perf — bait-detected ordering
   determinism, BotMaster pin-loop O(N²).

---

## NOTES ON VERIFICATION DEPTH

This audit was a static read of v0.10.7 source. Suggested follow-up:
- Run a 500-deal Monte Carlo with the pickLead-priority sequence
  instrumented (counter per branch fired) — surface unexpected branch
  domination.
- Compare Saudi-Master rollout-recommended-card vs Advanced-tier-recommended-
  card on the same deal; high disagreement rate would corroborate C-14.
- Hand-fixture test for C-11 (R1 hokmMinShape on 2-trump+J+sideAce).

---

End of audit. Total findings: 17 (1 HIGH, 9 MED, 6 LOW, 1 INFO confirmed
clean). Audit lines: ~470.
