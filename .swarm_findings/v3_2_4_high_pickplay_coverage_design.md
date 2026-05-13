# v3.2.4 design pass — HIGH-risk untested Saudi-canonical branches

**Repo:** `C:\CLAUDE\WHEREDNGN`
**Main / origin-main:** `261b4be`
**Latest tag:** `v3.2.3`
**Baseline harness:** 1,258 / 0
**Scope:** read-only design + test-only batch recommendation. No
runtime changes proposed.

---

## §0 Executive recommendation (TL;DR)

**Proceed with Batch A: 2 test-only fixtures covering T-6 and T-1
Exception #4 only.** Defer T-2, T-4, T-10, and T-1 Exception #2 to
later batches with their own design pre-work.

| Candidate | Audit ID | Feasibility | Batch decision |
|---|---|---|---|
| Tahreeb "want, no Ace" sender (`pickFollow` Sun) | **T-6** | LOW | **Batch A** |
| Hokm Faranka Exception #4 — both-opps-void path (`pickFollow`) | **T-1.E4** | LOW-MED | **Batch A** |
| Tahreeb-return T-supply count≥3 (`pickLead`) | T-10 | MEDIUM | Defer to Batch B / v3.2.5 |
| Hokm Faranka Exception #2 — 2-trumps + K-cover (`pickFollow`) | T-1.E2 | MEDIUM | Defer to Batch B / v3.2.5 |
| Sweep-pursuit-early Kaboot lead (`pickLead`) | T-2 | MEDIUM | Defer to Batch B / v3.2.5 |
| Sun pos-4 Faranka 5-factor (`pickFollow`) | T-4 | MEDIUM-HIGH | Defer indefinitely or build EV simulator first |

Expected Batch A delta: **1,258 → 1,264** (+6 new harness checks
across 3 behavioural test blocks + 1 source-pin block):
**3 behavioural checks** (BH.1 T-6 fires; BH.2 Exception #4 fires;
BH.3 negative-paired Exception #4 fall-through) + **3 source-pin
sub-asserts** (BH.4a/b/c on existing in-source markers).

All tests are **regression guards on already-correct runtime** —
no pre-runtime failures expected. Pure coverage backfill.

---

## §1 T-ID reconciliation

Codex's prompt referenced "T-1 / T-2 / T-4 / T-6 / T-10" with
specific subjects. Reconciling against the v3.2.1 audit doc's
canonical T-IDs:

| Codex prompt label | Subject | Audit T-ID |
|---|---|---|
| "T-1 sweep-pursuit-early / Kaboot pursuit" | sweep-pursuit-early lead | **audit T-2** |
| "T-2 Sun pos-4 five-factor Faranka" | Sun pos-4 captureRate | **audit T-4** |
| "T-4 Tahreeb 'want, no Ace' sender" | Sun void-in-led want-arm | **audit T-6** |
| "T-6 Tahreeb-return T-supply" | pickLead T-supply for want-flavor | **audit T-10** |
| "T-10 remaining HIGH Definite branch" | Hokm Faranka exceptions | **audit T-1** |

This doc uses the **audit's canonical T-IDs** (T-1, T-2, T-4, T-6,
T-10) throughout to avoid double-naming. Section §2 below summarises
each by audit ID with cross-reference to Codex's prompt label.

---

## §2 Source inventory (post-v3.2.3 line numbers)

### §2.1 T-1 — Hokm Faranka exceptions #2/#3/#4

- **File / lines:** `Bot.lua:3950-4124` (was `3842-4021` pre-v3.2.3;
  +~108 lines after F5-3 relocation + comment block insertion at
  L3738)
- **Function:** `pickFollow`, opp-winning region (after the
  partnerWinning early-return)
- **Summary:** M3lm bidder-team-only carve-outs that allow trump
  Faranka (withhold top trump to ambush) under three narrow
  conditions:
  - **Exception #2** (L3979-3981): `myTrumpCount == 2 and onBidderTeam`
  - **Exception #3** (L4001-4015): J of trump dead AND we hold 9-of-trump (new top live trump); also sets `exception3Path = true`
  - **Exception #4** (L4026-4060): both opps observed-void in trump
- **F-16 K-cover veto** (L4061-4087): if `farankaTriggered` and not
  `oppsVoidPath` and not `exception3Path`, requires K-of-trump in
  hand or sets `farankaTriggered = false`
- **Returns:** lowestByRank from non-trump losers (or all non-winners
  if no non-trump losers exist), L4106
- **Existing pins:**
  - CC.1 (v3.2.1 F4) — Exception #3 + no K of trump → F-16 carve-out → Faranka fires (PINS Exception #3 path only)
  - CC.2 (v3.2.1 F4) — Exception #2 with no K of trump → F-16 vetoes → no Faranka (PINS the negative path of Exception #2)
  - CC.3 (v3.2.1 F4) — source-pin block for F4 marker + exception3Path flag + audit L-9 ref
- **Untested portions:**
  - **Exception #2 POSITIVE path** (2 trumps + bidder-team + K of trump in hand → F-16 passes → Faranka fires)
  - **Exception #4 POSITIVE path** (both opps void in trump → `oppsVoidPath = true` → F-16 carve-out → Faranka fires)
  - **F-30b secondary trigger** (HighestUnplayedRank(trump) == nil at L4045-4060) — structural trump-exhaustion path

### §2.2 T-2 — Sweep-pursuit-early Kaboot lead

- **File / lines:** `Bot.lua:1073-1190` (unchanged — pickLead is above
  the F5-3 insertion point so line numbers didn't shift)
- **Function:** `pickLead`
- **Summary:** M3lm+ trick-3-7 lead branch. When our team has won
  every prior trick AND we hold enough remaining-trick winners
  (trump J/9/A + side-suit bosses) to plausibly complete the sweep,
  lead aggressively to maximise Al-Kaboot.
- **Gates:**
  - `trickNum >= 3 and trickNum <= 7`
  - `mySwept == trickNum - 1` (won every prior trick)
  - `sweepPursuitEarly and Bot.IsM3lm() and S.HighestUnplayedRank and contract.trump` (M3lm-gated, Hokm-only, has trump for feasibility math)
  - `feasibleWinners >= remainingNeeded` (where `remainingNeeded = 8 - trickNum + 1`)
- **Returns:** `highestByFaceValue(safeBosses)` if any safe boss
  exists; else `highestByRank(legal)` for sweepPursuit=true (trick 8
  only); else `highestByFaceValue(legal)`
- **Existing pins:** none (the only mention is a comment in another
  test's prose at `tests/test_state_bot.lua:2192`)
- **Saudi reference:** decision-trees.md §7 row "Kaboot pursuit
  feasibility check" (Definite, video 15). `K.AL_KABOOT_HOKM = 250`
  raw / `K.AL_KABOOT_SUN = 220` raw × Sun ×2 multiplier = 440 effective.

### §2.3 T-4 — Sun pos-4 Faranka 5-factor framework

- **File / lines:** `Bot.lua:3233-3413` (was `3098-3307` pre-v3.2.3;
  +~135 lines after F5-3 relocation at L3739)
- **Function:** `pickFollow`, pre-partnerWinning region
- **Summary:** Sun pos-4 bidder-team Faranka with a probabilistic
  captureRate computed from 5 factors. The bot decides whether to
  capture with A or duck with cover (T/K).
- **Gates:**
  - `contract.type == K.BID_SUN and lastSeat and partnerWinning`
  - `R.TeamOf(seat) == R.TeamOf(contract.bidder)` (bidder team)
  - `hasA and cover and suitCount == 2 and not holdsTopTwoUnplayed`
    (anti-trigger row 167 v1.4.0)
- **5-factor captureRate** (L3259-3329):
  - F1: cover is J → −0.10
  - F3: sweepActive (all prior tricks ours) → −0.10
  - F4: opp near clinch (`oppCum >= target - 26`) → −0.10
  - F5: LHO is bidder + trick 1 → −0.10
  - Plus weakHandSignal inversion → +0.40
  - Plus opp-bidder Kaboot anti-trigger → captureRate = 1.0
  - Plus v1.6.0 CS-01 borderline-state wobble (±0.10 random within
    [0.40, 0.60])
- **Returns:**
  - If `math.random() < captureRate` (M3lm): A of led suit (capture)
  - Otherwise: `cover` (T or K of led — duck/Faranka)
- **Existing pins:** none
- **Saudi reference:** decision-trees.md §5 (Definite, video 06)

### §2.4 T-6 — Tahreeb "want, no Ace" sender

- **File / lines:** `Bot.lua:3676-3701`
- **Function:** `pickFollow`, Tahreeb sender block inside
  partnerWinning
- **Summary:** Sun-only sub-arm of the Tahreeb sender. When partner is
  winning, we're void in led, and we hold a 3+-card non-trump side
  suit with no A AND no T, discard the LOWEST from that suit. The
  receiver decodes ascending sequence as "want this suit, partner has
  cards but no A/T."
- **Gates:**
  - Outer Tahreeb: `Bot.IsM3lm() and voidInLed`
  - Inner Sun gate: `contract.type == K.BID_SUN`
  - Per-suit loop: `#cards >= 3 and not hasA and not hasT`
- **Returns:** `lowestByRank(lows, contract)` where `lows = cards in
  that no-honor suit`
- **Existing pins:** none directly. v3.2.1 audit's T-6 entry confirmed
  "no behavioural for the SENDER arm at line 3604-3644" (line ref now
  shifted to L3676-3701 post-v3.2.3).
- **Saudi reference:** decision-trees.md §8 (Definite, videos 01,
  09, 10). "2nd-most-cited Tahreeb form."

### §2.5 T-10 — Tahreeb-return T-supply for "want" flavor count≥3

- **File / lines:** `Bot.lua:1776-1788`
- **Function:** `pickLead`, M3lm partner-pref Tahreeb-return arm
- **Summary:** When partner emitted a confirmed `want` Tahreeb signal
  (small→big) in suit X, and we hold T of X, AND `count >= 3` of X
  in hand, lead the T-supply (T of X) — partner is signalling no-T,
  so receiver with T MUST lead it back.
- **Gates:**
  - In a broader Tahreeb-pref arm: `tahreebPref` set by partner's
    style ledger
  - Inner: `hasT and tahreebPrefFlavor == "want"` at L1776
- **Returns:** `tCard` (T of pref suit)
- **Existing pins:** Y.8 in audit's terminology (source-pin only,
  per v3.2.1 audit). `tahreebSent` field used in existing AS/AT
  tests for OTHER scenarios (`tests/test_state_bot.lua:1228, 1906`)
  but T-10's specific T-supply branch isn't pinned.
- **Saudi reference:** decision-trees.md §8 row 239 (Definite,
  video 10) — "100% reliable" per speaker
  («نسبه نجاحه كبيره اللي هي 100%»).

---

## §3 Behavioural surface

For each candidate, the state-space required to reach the branch.

### §3.1 T-6 (Tahreeb want-no-Ace sender) — simplest fixture

| Aspect | Required state |
|---|---|
| Game state | Sun trick in progress; partner currently winning; we void in led suit |
| Seat / position | Bot at any seat where partner has played a card before us; partnerWinning=true (curWinner == R.Partner(seat)) |
| Contract | Sun, any bidder |
| Hand shape | Void in led suit; at least one non-trump side suit with `#cards >= 3` AND no Ace AND no Ten |
| Memory / style | None needed |
| Upstream shadows | Smother (`feedSafe + pointCards in led`) — won't fire because we're void in led → empty pointCards. T-1 Bargiya sub-arm — fires only if any suit has an A; T-6 fixture has no A in the candidate suit (and ideally no A anywhere to avoid triggering Bargiya in a different suit). |
| Downstream fallback | If T-6 doesn't fire, T-4 doubleton arm runs; then F5-3 (v3.2.3) for pos-3 partner-certain; then Rule 1B; then fallback `lowestByRank(legal)`. The fallback would return the lowestByRank of ALL legal — likely the same card T-6 wants to return! So pre-fix wire-proof is possible only if the fixture has another suit whose lowest is even lower than the candidate suit's lowest. |

**Fixture caveat:** the `lowestByRank` fallback may return the same
card T-6 returns when the candidate suit has the absolute lowest
card in legal. To make T-6's fire observable, the fixture needs
another non-led suit that contains a card with even lower TrickRank
than the candidate suit's low, so that fallback would pick from the
other suit while T-6 specifically picks from the candidate.

Sun TrickRanks: 7=1, 8=2, 9=3, J=4, Q=5, K=6, T=7, A=8.

Concrete fixture:
- Hand: `{KH, 9H, 8H, 7H, 8D, 7D}` (void in S [lead], H is 4-card no-A no-T, but K is in H — wait, K is a non-A non-T card; T-6 doesn't check for K specifically, only "no A and no T")
- Actually K is allowed in T-6's "no A no T" suit. Re-check: gate is `not hasA and not hasT`. K=6 is allowed; only A and T are excluded.
- Hand H = {KH, 9H, 8H, 7H}: hasA=false, hasT=false → T-6 fires. Returns lowestByRank({KH, 9H, 8H, 7H}) = 7H.
- Fallback would return lowestByRank({KH, 9H, 8H, 7H, 8D, 7D}) = 7D (D has 7D which ties with 7H at rank 1; tied set → randomized). So the assertion needs to either pin 7H specifically (with a math.random stub) or pick a fixture where the fallback lowest differs from T-6's lowest.

Better fixture: hand = `{KH, 9H, 8H, 7D}` (3-card H no-A no-T + 1-card D).
- T-6 picks lowest of H = 7H wait, no 7H here. The candidate suit is H = {KH, 9H, 8H}. Lowest = 8H (rank 2).
- Fallback `lowestByRank(legal)` = lowest of {KH, 9H, 8H, 7D} = 7D (rank 1).
- T-6 fires → 8H; fallback would pick 7D. DIFFERENT. T-6 is observable.

This works.

### §3.2 T-1 Exception #4 (both opps void in trump)

| Aspect | Required state |
|---|---|
| Game state | Hokm trick in progress; opp winning; we have at least one winner (forces enclosing `#winners > 0`); bidder-team |
| Seat / position | Any seat on bidder team |
| Contract | Hokm, with us on bidder team |
| Hand shape | Has at least one trump (the winner / candidate to withhold) + at least one non-trump loser (Faranka returns the non-trump loser) |
| Memory | `Bot._memory[opp1].void[trump] = true` AND `Bot._memory[opp2].void[trump] = true` (both opps observed void) |
| Upstream shadows | partnerWinning block returns first — must ensure partner is NOT winning. Sun pos-4 Faranka — Hokm context skips it. Smother in partnerWinning — won't fire (opp winning). All pre-partnerWinning branches skip on opp-winning. |
| Downstream fallback | If Exception #4 doesn't fire, `farankaTriggered=false` → falls through to opp-winning natural play (highestByRank winners typically, or trump-pull logic) → returns the winner (e.g., the J-of-trump if that's our winner). |

Exception #4 returns a non-trump LOSER. Without the exception, the
bot plays the highest winner (the led-suit winning A in the
fixture below). **Two distinguishable outputs** → positive /
negative wire-discriminator feasible.

> **v0.3 amendment (post-Codex review):** the v0.2 draft used a
> void-in-led hand `{JD, 8C, 7C}` and asserted 7C as the return.
> That violates Hokm must-trump (`Rules.IsLegalPlay`): a seat void
> in led suit with trump in hand MUST ruff, so 8C and 7C are
> illegal plays. Codex's corrected fixture uses a must-follow
> hand that includes a led-suit loser, so the Faranka block can
> return a legal non-trump loser.

Concrete fixture (Hokm-legal):
- Hokm trump=D, bidder seat 1, bot seat 3 (team A with bidder), M3lm.
- Trick in progress: opp seat 4 leads `8H`; partner seat 1 plays
  `QH`; opp seat 2 plays `KH` (currently winning, since K > Q > 8
  in led suit H with no trump played). Bot at seat 3 is pos-4
  (lastSeat=true).
- Hand: `{AH, 7H, JD, 8C}`. Must-follow H (we hold H cards), so
  legal = `{AH, 7H}`.
- winners (would beat KH in led suit): AH wins (A=8 > K=6 in
  RANK_PLAIN). 7H doesn't beat KH. winners = `{AH}`. #winners > 0 ✓
- Exception #2: `myTrumpCount = 1` (only JD, but JD is NOT in
  legal). The Faranka block counts trumps in `hand`, not `legal`,
  so myTrumpCount=1, not 2 → Exception #2 doesn't fire.
- Exception #3: `HighestUnplayedRank(D)` — JD is in our hand and
  unplayed → J is highest in TRUMP_HOKM_ORDER (`{J, 9, A, T, K,
  Q, 8, 7}`) → returns "J". ≠ "9" → Exception #3 doesn't fire.
- Exception #4: set `Bot._memory[2].void.D = true` AND
  `Bot._memory[4].void.D = true` → `oppTrumpExhausted = true` →
  `farankaTriggered = true; oppsVoidPath = true`.
- F-16 veto: `farankaTriggered and not oppsVoidPath and not
  exception3Path` = `true and false and false` = false → veto
  skipped.
- Faranka block fires:
  - nonWinners = legal − winners = `{AH, 7H} − {AH}` = `{7H}`
  - nonTrumpLosers = filter non-trump from nonWinners. 7H suit=H,
    trump=D → 7H is non-trump → `nonTrumpLosers = {7H}`.
  - pool = nonTrumpLosers
  - returns `lowestByRank({7H}, contract)` = `7H`.
- **Returns `7H`.**

Negative variant (only one opp void):
- Same fixture but `Bot._memory[2].void.D = nil` (only seat 4
  void). `oppTrumpExhausted` = false. Exception #4 doesn't fire.
- F-30b secondary: `HighestUnplayedRank(D) == nil`? No, J still
  unplayed → doesn't fire either.
- `farankaTriggered = false` → Faranka block falls through.
- Natural opp-winning response: with legal `{AH, 7H}` and
  winners `{AH}`, the bot at pos-4 plays `highestByRank(winners)`
  (the Takbeer / over-cut behaviour) → **returns `AH`**.

Pre-fix vs post-fix: this branch is ALREADY LIVE in current code
(unchanged since v0.10.3). Both states return 7H on the positive
fixture and AH on the negative fixture. **Tests are regression
guards.** The 7H ↔ AH wire-discriminator proves Exception #4 is
the specific path firing on the positive fixture; without it,
the natural fallback returns AH.

### §3.3 T-10 (Tahreeb-return T-supply for "want" flavor count≥3)

| Aspect | Required state |
|---|---|
| Game state | At lead position (pickLead context); some prior tricks must have established partner's Tahreeb signal |
| Seat / position | Any seat at lead |
| Contract | Sun (Tahreeb T-supply is Sun-only per code comment) |
| Hand shape | Has T of partner's signalled suit; count of that suit `>= 3` |
| Memory / style | `Bot._partnerStyle[partner].tahreebSent[suit]` populated with an ascending sequence (e.g., `{"7", "9"}`) so `tahreebClassify` returns `"want"` |
| Upstream shadows | Tons of pickLead branches before this one (trick-8 logic, sweep-pursuit-early, etc.). Must avoid: trickNum=8 (uses different branch), sweep-pursuit conditions, AKA-continuation, Bargiya receiver, etc. |
| Downstream fallback | If count < 3, branch falls through to `lowestByRank(fromPref)`. If hasT but flavor != "want", falls to other Tahreeb sub-arm. If no tahreebPref at all, branch never enters. |

Concrete fixture:
- Sun bidder seat 1, bot seat 3 (partner of seat 1). M3lm.
- `Bot._partnerStyle[1].tahreebSent.H = {"7", "9"}` — partner emitted ascending {7H, 9H} → tahreebClassify = "want" for H.
- Hand: `{TH, KH, QH, 9D, 8D, 7C, 8C, 7S}` — has T of H, count(H) = 3 (TH + KH + QH).
- `tahreebPrefFlavor` will be "want" for H.
- Branch fires → returns tCard = TH.

Without the v1.1.0 H1 fix (which IS in current code), the count >= 3 case would fall through to lowestByRank → 7H (if present) or other low. With the fix in place, returns TH.

Pre-fix vs post-fix: BOTH return TH on current code. Regression guard.

For observability, the fixture needs to avoid all upstream branches that might fire before this Tahreeb-return arm. That's the MEDIUM complexity — many upstream gates to set up correctly.

### §3.4 T-1 Exception #2 (2 trumps + bidder-team + K of trump)

| Aspect | Required state |
|---|---|
| Game state | Hokm opp-winning trick; we're bidder-team; we have a winner |
| Seat / position | Bidder team seat |
| Contract | Hokm |
| Hand shape | Exactly 2 trumps total in hand; one is K of trump; at least one non-trump loser; at least one trump that wins the trick |
| Memory | Not strictly required, but must NOT have both-opps-void-in-trump (else Exception #4 fires first) |
| Upstream shadows | Same as Exception #4 fixture, but specifically tuned to firing Exception #2 without Exception #3 or #4 |
| Downstream fallback | Falls to normal opp-winning play; bot plays winning trump |

CC.2 already pins the K-LESS negative case. T-1 Exception #2 needs
the POSITIVE case: 2 trumps + bidder-team + K-of-trump-in-hand →
F-16 passes → Faranka fires.

Fixture: Hokm trump=D, bot seat 3 (bidder team via seat 1). Hand
includes KD + 9D (or similar 2 trumps with one K). Tricks/memory
state arranged so Exception #2 fires (myTrumpCount=2 + onBidderTeam).
Exception #3 doesn't fire (HighestUnplayedRank(D) != "9", e.g., J
still live). Exception #4 doesn't fire (opps not both void).

### §3.5 T-2 (sweep-pursuit-early Kaboot lead)

Most complex setup: need 2+ prior completed tricks all won by our
team, M3lm, contract.trump set, hand with feasibleWinners >=
remainingNeeded. Pos: at lead, so `S.s.trick.plays = {}`.

### §3.6 T-4 (Sun pos-4 5-factor Faranka)

Probabilistic via `math.random` — fixture needs stub. Three layers
of factors interact; testing requires careful stub strategy similar
to v3.2.4 F2 design's §5.2 (deterministic 0.0/0.99 stubs sufficient
for fire/no-fire pinning; bounded statistical for rate is
discouraged).

---

## §4 Fixture feasibility ranking

| Candidate | Feasibility | Rationale |
|---|---|---|
| **T-6 want-no-Ace sender** | **LOW** | Single fixture setup; void-in-led + 3-card no-A no-T suit. No math.random. No prior-tricks setup needed. The only complication: fallback's lowestByRank would return the same low card from the candidate suit unless the fixture includes another suit with a lower card. Mitigation: add a 1-card 7D side suit, so fallback returns 7D vs T-6's 8H. |
| **T-1 Exception #4 (both-opps-void)** | **LOW-MED** | Memory setup for both opps void in trump. Otherwise deterministic. Same fixture family as CC.1/CC.2. Pos-4 lastSeat preferred to avoid pre-block branches. |
| **T-10 T-supply count≥3 want** | **MED** | Need to construct partner-style `tahreebSent` ledger entries; need to avoid many upstream pickLead branches. Existing AS-section tests set `tahreebSent` similarly so fixture pattern is established, but the specific T-supply arm has more upstream gates than (e.g.) the simpler Tahreeb-pref. |
| **T-1 Exception #2 (2 trumps + K)** | **MED** | Same family as Exception #4 but requires careful hand-shape (exactly 2 trumps, one is K, no Exception #3 / #4 triggers). Negative test (Exception #4 doesn't fire) requires either not setting void-memory OR setting only one opp. |
| **T-2 sweep-pursuit-early** | **MED** | 2-3 prior tricks must be populated with our-team winners; trump pool memory; hand shape calibrated for `feasibleWinners >= remainingNeeded`. Lots of upstream pickLead gates to avoid (trick-8 first, etc.). |
| **T-4 5-factor Faranka** | **MED-HIGH** | Probabilistic — needs math.random stub. Five interacting factors. Borderline-state wobble adds another math.random call. Plus the same EV concern as F2: deterministic stubs prove fire/no-fire but not long-run rate or EV. The v3.2.4 F2 doc's §5.2 stance applies. |

---

## §5 Proposed batch shape

### §5.1 Batch A (RECOMMENDED) — 2 fixtures

Add only the two **LOW / LOW-MED** candidates:

- **T-6** (Tahreeb want-no-Ace sender)
- **T-1 Exception #4** (both opps void in trump)

Both are Saudi-canonical "Definite" branches, both have deterministic
runtime (no math.random), both have clear distinguishability between
"branch fires" vs "fallback fires."

### §5.2 Batch B (LARGER) — adds 3 more fixtures

Adds the MEDIUM candidates: T-10, T-1.E2, T-2. Each requires more
fixture state-setup but is still feasible without math.random stubs.

Recommend Batch B as a v3.2.5 follow-up rather than rolling into
v3.2.4 — keeps the review surface manageable and respects the
"smallest reviewable batch" pattern that the v3.2.1-v3.2.3 sequence
established.

### §5.3 T-4 (5-factor Faranka) — defer indefinitely

Same reasoning as F2 (v3.2.4 design): probabilistic gate needs
deception-EV / long-run-rate framework that doesn't currently
exist. Add only if a Saudi-Master sim is built first.

---

## §6 Test plan — section BH

If Batch A proceeds, section **BH** is appended after BG (F2 deferral,
which is just a marker) — actually after the existing BF section
since BG is reserved by the F2 design doc but never implemented.
Tentatively the next free section letter is BH.

### §6.1 BH.1 — T-6 Tahreeb "want, no Ace" sender (regression guard)

**Fixture:**
- Sun, bidder seat 1, bot seat 3 (team A, partner of seat 1), M3lm
- Trick in progress: pos-1 partner seat 1 led `KS` (mid card in S);
  pos-2 opp seat 2 played `7S` (loser). Partner is currently
  winning (`R.CurrentTrickWinner` returns seat 1 since KS > 7S in
  led suit S, no trump played in Sun).
- Bot at pos-3 (seat 3), partner is seat 1
- Bot void in S (no must-follow → all hand cards legal as discards)
- Hand: `{KH, 9H, 8H, 7D}` — 3-card H no-A no-T (eligible for the
  "want, no A/T" arm) + 1-card D (forces fallback to pick 7D if T-6
  doesn't fire)

**Expected:**
- Smother: pointCards (Suit==S) = empty → falls through
- Tahreeb outer gate: `Bot.IsM3lm() and voidInLed` = true ✓
- T-1 Bargiya sub-arm: Sun + iterates suits for A → no A in hand → doesn't return
- **"Want, no A/no T" sub-arm fires**: iterates suits with #cards >= 3 → H matches (3 cards, no A, no T); returns `lowestByRank({KH, 9H, 8H})` = `8H` (rank 2, lowest of the H suit)

**Assert (strict):** `card == "8H"`. **Do not weaken to
`card ~= "7D"`** — the negative form would pass for many other
cards that aren't 7D (KH, 9H, 8C, ...) and wouldn't actually prove
that the per-suit Tahreeb want-arm fired. The strict positive
assertion is the only form that proves T-6's specific per-suit
scope (lowest in candidate suit) rather than fallback's
all-legal lowest.

**Wire vs regression:** This is a **regression guard** — current code already returns 8H. If T-6 ever regresses (gate flip or rank-floor change), this test catches it. Pre-fix and post-fix both pass.

**Why 8H not 7D:** The Tahreeb "want, no A/no T" sub-arm picks the lowest from the candidate SUIT, not from all legal. So even though 7D is lower than 8H, T-6's per-suit scope returns 8H. If T-6 didn't fire, fallback's `lowestByRank(legal)` would return 7D. The 8H vs 7D distinction proves T-6 fired specifically — but only when the assertion is the strict positive `card == "8H"`, not a negative `card ~= "7D"`.

### §6.2 BH.2 — T-1 Exception #4 (both opps void in trump)

> **v0.3 amendment (post-Codex review):** the v0.2 BH.2 fixture
> used a void-in-led hand `{JD, 8C, 7C}` and asserted `7C`. Under
> Hokm must-trump (`Rules.IsLegalPlay`), a seat void in led with
> trump in hand MUST ruff — so 8C and 7C are illegal plays and
> the assertion was unreachable. The corrected fixture uses a
> must-follow hand with a led-suit loser; the Faranka block then
> returns that loser legally.

**Fixture (Hokm-legal, must-follow):**
- Hokm trump=D, bidder seat 1, bot seat 3 (team A with bidder), M3lm
- Trick in progress: opp seat 4 leads `8H`; partner seat 1 plays `QH`; opp seat 2 plays `KH` (currently winning, since KH > QH > 8H in led suit H with no trump played). Bot at pos-4 (seat 3, lastSeat=true).
- `Bot._memory[2].void.D = true` (opp seat 2 void in trump D)
- `Bot._memory[4].void.D = true` (opp seat 4 void in trump D)
- Bot hand `{AH, 7H, JD, 8C}` — H cards in hand → must-follow H → legal `{AH, 7H}`. AH is the winner (beats KH in led suit); 7H is the legal non-trump loser; JD and 8C are illegal (not led suit, must-follow disallows discards).

**Expected:**
- AKA gate: lead is `8H` (not Ace), skip
- partnerWinning block: KH wins (opp seat 2), partner is seat 1, partner played QH (not the current winner) → partnerWinning=false → skip block
- winners (`wouldWin` for each legal card): AH beats KH (A=8 > K=6 in RANK_PLAIN) → wouldWin=true; 7H doesn't beat KH (7=1 < 6) → wouldWin=false. winners = `{AH}`
- Exception #2: myTrumpCount in hand = 1 (only JD) → ≠ 2 → skip
- Exception #3: `HighestUnplayedRank(D)` walks TRUMP_HOKM_ORDER `{J,9,A,T,K,Q,8,7}`; JD is in our hand (unplayed) → returns "J" → ≠ "9" → skip
- **Exception #4**: iterate opps (seats 2 and 4). Both have `void.D = true` → `oppTrumpExhausted = true` → `farankaTriggered = true; oppsVoidPath = true`
- F-16 veto: `farankaTriggered and not oppsVoidPath and not exception3Path` = `true and false and false` = false → veto skipped
- Faranka block fires: nonWinners = legal − winners = `{AH, 7H} − {AH}` = `{7H}`; 7H is non-trump (suit=H, trump=D) → nonTrumpLosers = `{7H}`; pool = nonTrumpLosers; returns `lowestByRank({7H}, contract)` = **`7H`**.

**Assert (strict):** `card == "7H"`.

**Wire vs regression:** Regression guard (current code already
returns 7H on this Hokm-legal fixture). The 7H ↔ AH pair (BH.2
positive returns the loser 7H; BH.3 negative returns the winner
AH) is the wire-discriminator that proves Exception #4 fired in
BH.2.

### §6.3 BH.3 — T-1 Exception #4 NEGATIVE (only one opp void)

**Fixture:** same as BH.2 but `Bot._memory[2].void.D = nil` (opp 2
NOT void; only opp 4 void).

**Expected:**
- `oppTrumpExhausted` = false (loop hits seat 2's missing `void.D`
  → breaks → exhausted=false)
- Exception #4 doesn't fire
- F-30b secondary trigger: `HighestUnplayedRank(D) == nil`? No, JD
  is in our hand and unplayed → returns "J" → not nil → doesn't
  fire
- `farankaTriggered` stays false → Faranka block doesn't return
- Falls through to natural opp-winning play. At pos-4 (lastSeat)
  with `winners = {AH}` and legal = `{AH, 7H}`, the bot returns
  `highestByRank(winners)` = **`AH`** (the Takbeer / over-cut
  behaviour for partner-pile feed).

**Assert (strict):** `card == "AH"`.

This negative-paired-with-BH.2 proves that Exception #4 is what
causes BH.2's `7H` return; without both-opps-void, the bot plays
the led-suit winner `AH` instead. **Positive/negative wire-
discriminator: both-opps-void returns loser `7H`; one-opp-void
returns winner `AH`.**

### §6.4 BH.4 — Source-pin for v3.2.4 BH section markers

**Three sub-asserts on EXISTING in-source markers** — this is a
test-only batch; **no new runtime markers are added or required**.
The pins simply lock in the structural anchors that the behavioural
tests rely on, so a future runtime cleanup that accidentally removes
one of these comments / flag names triggers a harness failure
instead of silently breaking BH.1 / BH.2 / BH.3.

Each pin targets a substring that has been in `Bot.lua` since well
before v3.2.4 (see the per-pin comment markers below):

```lua
local botSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Bot.lua"):read("*a")
-- BH.4a: T-6 sub-arm marker (already in code from v0.11.18-final U-2)
assertTrue(botSrc:find("v0%.11%.18%-final U%-2") ~= nil,
    "BH.4a (T-6): Sun-only gate marker for want-no-Ace sender")
-- BH.4b: Exception #4 flag (already in code from v0.10.3 audit)
assertTrue(botSrc:find("oppsVoidPath") ~= nil,
    "BH.4b (T-1 Exception #4): oppsVoidPath flag exists")
-- BH.4c: F-30b structural trump-exhausted secondary trigger
--        (already in code from v0.10.3 F-30b fix)
assertTrue(botSrc:find("v0%.10%.3 F%-30b") ~= nil,
    "BH.4c (T-1): F-30b secondary trigger marker present")
```

**Implementation constraint:** the Batch A runtime is `Bot.lua` at
`c96f120` (v3.2.3 + the v3.2.4 F2 deferral design doc — runtime
identical to v3.2.3). The implementation branch for this batch
MUST NOT modify `Bot.lua` to add new comments or flags solely
to satisfy BH.4. If any of BH.4a/b/c fails pre-implementation,
that means the in-source marker isn't there in current code — in
which case the pin's target substring is wrong and BH.4 must be
re-scoped to a different substring that genuinely already exists,
NOT solved by adding a new marker.

This is acceptable for a test-only coverage batch precisely because
the runtime is locked. For a future test+runtime batch, source-pins
on new markers would be appropriate (e.g., v3.2.1 F1's BA.5,
v3.2.2 BE.3, v3.2.3 BF.8).

### §6.5 Test count + harness delta

| Test | Type | Pre-fix outcome | Post-fix outcome |
|---|---|---|---|
| BH.1 | behavioural regression guard | PASS (returns 8H) | PASS (returns 8H) |
| BH.2 | behavioural regression guard | PASS (returns 7H) | PASS (returns 7H) |
| BH.3 | behavioural negative paired-test | PASS (returns AH) | PASS (returns AH) |
| BH.4 | source-pin (3 sub-asserts) | PASS (markers already exist) | PASS |

Total: **BH.1 + BH.2 + BH.3 + BH.4a/b/c = 6 new harness checks**
(3 behavioural assertion checks + 3 source-pin sub-asserts).
Expected harness: **1,258 → 1,264**.

---

## §7 Stop conditions

If Batch A proceeds, the implementation must STOP and re-design if:

1. **BH.1 fixture passes for the wrong reason.** Specifically: if
   the bot returns 8H but Tahreeb's T-6 sub-arm DIDN'T fire (e.g.,
   smother fired and returned 8H for some other reason), the test
   is structurally invalid. Add a source-pin or trace assertion to
   verify T-6 was the source.
2. **BH.2 fixture's Exception #4 is shadowed by Exception #2 or
   Exception #3 fire.** If myTrumpCount accidentally = 2, Exception
   #2 fires first → `oppsVoidPath` stays false → F-16 vetoes (no
   K-of-trump in fixture). The fixture must keep myTrumpCount = 1.
3. **BH.3 (negative test) returns `7H` instead of `AH`.** Means
   Exception #4 fired despite the one-opp-void setup (e.g.,
   `Bot._memory[2].void.D` wasn't properly cleared), OR the
   natural opp-winning fallback isn't returning the expected
   `highestByRank(winners)` for some other reason. Stop and
   trace.
4. **Existing BF / BE / BA-BD / CC tests regress.** Any pre-existing
   v3.2.x test that breaks indicates the test fixtures interfere
   with shared state (e.g., `Bot._memory` not properly reset between
   tests).
5. **Any runtime file (Bot.lua, BotMaster.lua, etc.) is modified.**
   Batch A is test-only. If the fixture exposes a real bug requiring
   a runtime fix, that's a SEPARATE batch design pass — stop and
   re-scope.
6. **Source-pin BH.4 fails on a substring that's been in Bot.lua
   for multiple versions.** Means the audit's identification of
   that marker was wrong; verify against current Bot.lua before
   adjusting the pin.

---

## §8 Recommendation

**Proceed with Batch A** — test-only, 2 fixtures (T-6 + T-1
Exception #4) + 1 negative-paired test (BH.3) + 1 source-pin block
(BH.4).

Rationale:

1. Both T-6 and T-1.E4 are Saudi-canonical "Definite" branches per
   `decision-trees.md` §8 / §10 (video #04 / #06 / #10 / #09 / #01
   sources).
2. Both are deterministic (no math.random) → fixtures are clean
   and stable.
3. The pair BH.2 + BH.3 forms a positive/negative wire-discriminator
   for Exception #4 — strongest available evidence that the branch
   fires for the expected reason.
4. Harness delta is modest (+6 checks; 1,258 → 1,264).
5. Test-only batch keeps the runtime baseline locked at v3.2.3 (no
   gameplay changes between v3.2.3 and the implicit-v3.2.5 ship,
   should this be released).

### §8.1 Deferred / risks

1. **T-2, T-4, T-10, T-1 Exception #2 deferred to later batches.**
   Each is feasible but the fixtures add MEDIUM complexity per
   candidate. A v3.2.5 batch (test-only follow-up) could pick them
   up.
2. **T-4 indefinitely deferred** pending a deception-EV simulator
   (same family of concerns as F2 deferral).
3. **BH.1 fallback collision risk.** The Tahreeb sub-arm picks the
   lowest from its candidate SUIT, not all legal. Concrete fixture
   needs the lowest in legal to be in a DIFFERENT suit than the
   Tahreeb candidate to make the assertion observably distinct from
   fallback's lowestByRank. The §6.1 fixture uses 7D vs 8H to
   achieve this.
4. **BH.2 vs Exception #2 / Exception #3 confusion.** Hand-shape
   calibration must keep myTrumpCount=1 (not 2) and HighestUnplayedRank
   (trump)≠"9". If a future trump-played fixture rearrangement
   accidentally makes HighestUnplayedRank=="9", Exception #3 would
   fire and shadow Exception #4 with the same general outcome
   (Faranka fires) but a different code path. The negative test
   BH.3 with one opp void confirms Exception #4 is the specific
   path.
5. **Source-pin BH.4 targets EXISTING markers**, not new runtime
   additions. If a future runtime cleanup removes one of those
   markers, BH.4 would fail — but that's the desired behaviour
   (catches doc-rot).
6. **No CHANGELOG entry will be needed** for a test-only Batch A
   if Codex ships it — same pattern as test-only follow-up batches
   in prior versions, which don't generally warrant a user-facing
   release note.

---

## §9 Constraint compliance

- ✅ Design pass only.
- ✅ No edits to `Bot.lua`, tests, `.toc`, `.pkgmeta`, workflow,
  CHANGELOG, packaging.
- ✅ No tag.
- ✅ No release.
- ✅ No branch creation / deletion.
- ✅ Experimental branches (`sprint-a-experimental`,
  `v0.5.1-experimental`) untouched.
- ✅ `.swarm_findings/v3_2_0_botlua_comment_audit.md` untouched.

Stop here for Codex review. Doc remains uncommitted unless
explicitly asked to commit after review.
