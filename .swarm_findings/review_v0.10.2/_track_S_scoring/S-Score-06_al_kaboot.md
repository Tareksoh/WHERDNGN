# S-Score-06 — Al-Kaboot scoring (bidder/defender sweeps all 8)

**Scope:** Verify Al-Kaboot (الكبوت) scoring across 7 scenarios. Read-only audit of `Rules.lua:692-984` `R.ScoreRound`, `Constants.lua:111-115`.

**Code anchors after v0.10.2 line shift:**
- Sweep detection: `Rules.lua:742-745`
- Sweep belote override: `Rules.lua:752-754`
- Sweep replacement of cardA/cardB + meld attribution: `Rules.lua:847-853`
- Multiplier collapse for Sun: `Rules.lua:914-918`
- Multiplier composition for Hokm: `Rules.lua:919-923`
- Multiplier-immune Belote +20 add-on: `Rules.lua:929-943`
- div10 with "5 rounds UP": `Rules.lua:949`

---

## 1. TL;DR

| # | Scenario | Result | Severity |
|---|---|---|---|
| 1 | Hokm Al-Kaboot (bidder sweep) | **CORRECT.** 250 raw → 25 gp. Loser melds zeroed; sweeper's melds preserved. Belote follows sweep winner. | OK |
| 2 | Sun Al-Kaboot | **CORRECT.** 220 × Sun×2 = 440 raw → 44 gp. Sun ×2 multiplier composes correctly with sweep bonus. | OK |
| 3 | Hokm Al-Kaboot + Bel | **CORRECT.** 250 × 2 = 500 raw → 50 gp. | OK |
| 4 | Hokm Al-Kaboot + Bel + Triple + Four | **CORRECT** (×4 final). 250 × 4 = 1000 raw → 100 gp. Cumulative-target overshoot is a separate concern (see §5). | OK arithmetic; **MEDIUM** game-flow concern |
| 5 | Sun Al-Kaboot + Carré-A | **CORRECT.** Sweeper's melds ARE preserved through the sweep replacement. 220+400 melds = 620 × 2 = 1240 raw → 124 gp. | OK |
| 6 | **Reverse Al-Kaboot — type-blind bug** | **HIGH BUG CONFIRMED.** Defender sweep awards 250/220 as if bidder swept. Per Saudi rule (video #16): should be +88 raw with bidder-led-trick-1 gate. `K.AL_KABOOT_REVERSE` does not exist. | **HIGH** |
| 7 | Sweep + AKA banner clearing | **CORRECT.** AKA banner cleared per-trick at `State.lua:1327`; round-end inherits clean state. | OK |

**Headline finding:** Bug 6 is a HIGH-severity over-pay of 250-250-220-220 raw to defenders depending on contract: Hokm Reverse over-pays by ~162 raw (250 vs 88) = ~16 gp/round; Sun Reverse over-pays even more dramatically (220×2=440 raw vs 88) = ~35 gp/round. Cumulative score errors of this magnitude can flip game outcomes at target = 152 gp.

---

## 2. Per-scenario trace

### Scenario 1 — Hokm Al-Kaboot, bidder sweep

**Setup:** Hokm contract (`type = K.BID_HOKM`, undoubled), bidder team A wins all 8 tricks. No bonus melds.

**Trace:**
1. `Rules.lua:696-705`: trick loop accumulates `trickCount.A = 8`, `trickCount.B = 0`. `teamPoints.A = 162` (152 hand + 10 last-trick). `bidderTeam = "A"`, `oppTeam = "B"`.
2. `Rules.lua:743-745`: `sweepTeam = "A"`.
3. `Rules.lua:752-754`: belote override — if K+Q-of-trump holder was on team B, force `belote = "A"`. Saudi sweep convention.
4. `Rules.lua:847-853`: `bonus = K.AL_KABOOT_HOKM = 250`. `cardA = 250`, `cardB = 0`. `meldPoints.A = meldA` (sweeper keeps own melds), `meldPoints.B = 0` (loser melds **zeroed**).
5. `Rules.lua:914-924`: undoubled Hokm ⇒ `mult = K.MULT_BASE = 1`.
6. `Rules.lua:926-927`: `rawA = (250 + 0) × 1 = 250`, `rawB = 0`.
7. `Rules.lua:939-943`: belote +20 (multiplier-immune) → `rawA = 270` if K+Q held by A or routed via sweep override. Without belote, `rawA = 250`.
8. `Rules.lua:949` (div10 round-up): `final.A = (250 + 5) ÷ 10 = 25` gp. `final.B = 0`.

**Verification:** test_rules.lua:478-489 pins this exactly.

**Sweep replacement vs Belote / melds:**
- Sweeper's own melds are preserved (`meldA` flows into `meldPoints.A`).
- Loser's melds are **zeroed** at line 853 (`meldPoints.B = 0`).
- Belote is **routed to sweeper** at lines 752-754, then added as +20 raw post-multiplier at 939-943. Per CLAUDE.md "Saudi convention: the sweeping team takes EVERYTHING, including the +20 belote bonus."

**Verdict:** CORRECT. Sweep replacement preserves sweeper's melds; loser's melds and belote correctly transferred per Saudi sweep convention.

---

### Scenario 2 — Sun Al-Kaboot

**Setup:** Sun contract (`type = K.BID_SUN`, undoubled). Bidder team B sweeps.

**Trace:**
1. `Rules.lua:744-745`: `sweepTeam = "B"`.
2. `Rules.lua:847-849`: `bonus = K.AL_KABOOT_SUN = 220` (Sun branch hit because `contract.type == K.BID_HOKM` is false). `cardB = 220`.
3. **Sun multiplier collapse check (`Rules.lua:914-918`):**
   ```lua
   if contract.type == K.BID_SUN then
       mult = mult * K.MULT_SUN          -- × 2
       if contract.doubled then mult = mult * K.MULT_BEL end
       -- intentionally ignore tripled/foured/gahwa on Sun
   end
   ```
   For undoubled Sun, `mult = 1 × 2 = 2`. The "intentionally ignore tripled/foured/gahwa" comment refers ONLY to escalation-rung flags, NOT to `MULT_SUN` itself. The Sun ×2 is applied unconditionally on Sun contracts.
4. `Rules.lua:926-927`: `rawB = (220 + 0) × 2 = 440`.
5. `Rules.lua:949`: `final.B = (440 + 5) ÷ 10 = 44` gp.

**Verification:** test_rules.lua:491-498 pins `raw.B = K.AL_KABOOT_SUN * K.MULT_SUN = 440` and `final.B = 44`.

**Verdict:** CORRECT. The Sun ×2 multiplier composes properly with sweep-bonus 220 ⇒ 440 raw ⇒ 44 gp. The "ignore tripled/foured/gahwa" guard does NOT collapse the Sun ×2 itself — it only filters out illegal escalation rungs that should never appear on Sun.

---

### Scenario 3 — Hokm Al-Kaboot + Bel ×2

**Setup:** Hokm Bel'd (`contract.doubled = true`). Bidder sweeps.

**Trace:**
1. Sweep detection / replacement same as Scenario 1: `cardA = 250`, `cardB = 0`, melds zeroed for loser.
2. `Rules.lua:919-923` (Hokm escalation):
   ```lua
   if     contract.gahwa   then mult = mult * K.MULT_FOUR
   elseif contract.foured  then mult = mult * K.MULT_FOUR
   elseif contract.tripled then mult = mult * K.MULT_TRIPLE
   elseif contract.doubled then mult = mult * K.MULT_BEL end   -- × 2
   ```
   Bel only ⇒ `mult = 1 × 2 = 2`.
3. `rawA = (250 + 0) × 2 = 500`. `rawB = 0`.
4. `final.A = (500 + 5) ÷ 10 = 50` gp.

**Verdict:** CORRECT. Multiplier composes cleanly with sweep bonus.

---

### Scenario 4 — Hokm Al-Kaboot + Bel + Triple + Four (max escalation)

**Setup:** Hokm with `doubled = true, tripled = true, foured = true` (escalation chain Bel→Triple→Four). Bidder sweeps.

**Trace:**
1. `Rules.lua:919-923`: the `elseif` chain is **highest-rung-wins**, not multiplicative. With `foured = true`: `mult = 1 × K.MULT_FOUR = 4`.
2. `rawA = (250 + 0) × 4 = 1000`. `rawB = 0`.
3. `final.A = (1000 + 5) ÷ 10 = 100` gp.

**Verification:** Comment at `Rules.lua:895-903` explicitly states "Only one escalation multiplier applies — they replace each other rather than compound."

**Cumulative scoring at target=152:**
- `Constants.lua` defines target threshold (not inspected here, but per CLAUDE.md and per game convention, ~152 gp).
- A 100 gp Al-Kaboot×Four round is ~66% of target in a single round.
- Two such rounds (or one + 53 gp normal scoring) win the match.
- **No code-level bug** — the arithmetic is correct, and `Net.lua HostStepAfterTrick` should detect target crossing on cumulative score post-round.

**Game-flow concern (MEDIUM, not a bug):** The +100 gp swing is intentional in Saudi rules (escalation × Kaboot is the maximum reward); this is doctrinally correct. However, if any caller assumed "max gp per round ≈ 26" (regular hand×Bel), they may have UI/banner truncation issues. **Not in scope for this audit but worth flagging to S-Score-XX UI track.**

**Verdict:** CORRECT arithmetic. Cumulative handling is the caller's responsibility.

---

### Scenario 5 — Sun Al-Kaboot + Carré-A

**Setup:** Sun, bidder sweeps, sweeper declared four Aces (Carré-A = 400 raw, per `Constants.lua` `K.MELD_CARRE_A`-equivalent; v0.10.0 review confirmed 400 raw direct).

**Trace:**
1. Sweep detection: `sweepTeam = bidderTeam`. Suppose A.
2. `Rules.lua:847-853`:
   - `cardA = 220` (Sun bonus).
   - `meldPoints.A = meldA = 400` (sweeper's Carré-A — **PRESERVED**, not zeroed).
   - `meldPoints.B = 0`.
3. `Rules.lua:914-918`: `mult = 1 × 2 = 2` (Sun, undoubled).
4. `Rules.lua:926-927`: `rawA = (220 + 400) × 2 = 1240`. `rawB = 0`.
5. `Rules.lua:949`: `final.A = (1240 + 5) ÷ 10 = 124` gp.

**Critical sub-question — does sweep replacement preserve melds?**

YES. The replacement at `Rules.lua:847-853` writes to `cardA/cardB` and assigns `meldPoints` per-team. The sweeper's melds (line 852: `meldPoints.A = (sweepTeam == "A") and meldA or 0`) are explicitly retained. Then line 926 sums them: `rawA = (cardA + meldPoints.A) * mult`.

The sweep does NOT discard the sweeper's own melds — only the loser's. This matches the comment at `Rules.lua:747-754`: "the sweeping team takes EVERYTHING."

**Verdict:** CORRECT. Sweeper keeps own melds; mult applies to (sweep-bonus + meld) sum.

---

### Scenario 6 — Reverse Al-Kaboot (type-blind bug)

**Bug:** `Rules.lua:742-745` and `847-853` make NO distinction between bidder-sweep and defender-sweep. Any team that wins all 8 tricks gets the 250/220 bonus.

**Trace (concrete repro, post-v0.10.2 line numbers):**
1. Hokm-S contract, `bidder = seat 1` (team A). Seat 1 leads trick 1.
2. Defender team B wins all 8 tricks (Reverse Al-Kaboot scenario per video #16).
3. `Rules.lua:744-745`: `trickCount.B == 8` ⇒ `sweepTeam = "B"`.
4. `Rules.lua:847-853`: `bonus = K.AL_KABOOT_HOKM = 250`. `cardB = 250`. `meldPoints.B = meldB`.
5. `Rules.lua:914-924`: undoubled Hokm ⇒ `mult = 1`.
6. `Rules.lua:926-927`: `rawB = (250 + meldB) × 1 = 250 + meldB`.
7. `final.B = (250 + 5) ÷ 10 = 25` gp.

**Per Saudi rule (video #16, A-Src-18):** should be `rawB = 88` (NOT 250), AND only if bidder (seat 1) led trick 1.

**Magnitude of error:**
- Hokm: 250 raw vs 88 raw ⇒ over-pays defender by 162 raw = ~16 gp per Reverse-Kaboot round.
- Sun: 220 × 2 = 440 raw vs 88 raw ⇒ over-pays by 352 raw = ~35 gp per round.
- Both flavors are HIGH-magnitude per-round errors at a 152-gp target.

**Missing guard rail #2 — bidder-led-trick-1 gate:**
Even the value-correct interpretation requires `tricks[1].plays[1].seat == contract.bidder`. Code does not access trick-1 leader anywhere in the sweep block. If a defender leads trick 1 and somehow sweeps (rare but legal e.g. on round 1 of new Saudi-rule-where-defender-leads-after-pass), it should NOT count as Reverse Kaboot per video #16 line 9-12.

**`K.AL_KABOOT_REVERSE` constant existence check:**
Confirmed via grep: zero hits in `Constants.lua` or `Rules.lua`. Constant is referenced only in:
- CHANGELOG.md (proposal entries)
- docs/strategy/saudi-rules.md, decision-trees.md, glossary.md, endgame.md (documented as proposal)
- prior swarm findings (B-State-05, C-Xref-04, etc.)

**Recommended fix (gating predicate from B-State-05 F-01):**

```lua
-- After sweep detection at Rules.lua:744-745:
local sweepIsBidder = (sweepTeam == bidderTeam)
local sweepIsReverse = sweepTeam and not sweepIsBidder
local firstLeaderIsBidder = tricks[1] and tricks[1].plays
                            and tricks[1].plays[1]
                            and tricks[1].plays[1].seat == contract.bidder

-- At Rules.lua:849 sweep-bonus selection:
if sweepIsBidder then
    bonus = (contract.type == K.BID_HOKM) and K.AL_KABOOT_HOKM or K.AL_KABOOT_SUN
elseif sweepIsReverse and firstLeaderIsBidder then
    bonus = K.AL_KABOOT_REVERSE                     -- new constant = 88
else
    -- defender-sweep without trick-1 leader gate: NOT Reverse-Kaboot.
    -- Score as ordinary failed-bid round (defender takes handTotal).
    sweepTeam = nil   -- fall through to `outcome_kind` branches
end
```

Plus add `K.AL_KABOOT_REVERSE = 88` to Constants.lua.

**Verdict:** **HIGH BUG CONFIRMED.** Type-blind sweep awards bidder-bonus to defender. Two missing pieces: value (88 vs 250/220) and gate (firstLeaderIsBidder).

**Cross-references:**
- A-Src-18 (`_track_A_sources/A-Src-18_v16_reverse_kaboot.md`) — primary source authority
- B-State-05 F-01 (`_track_B_code/B-State-05_scoreRound_full.md` lines 28-71) — code-level bug repro
- C-Xref-04 #13 (`_track_C_xref/C-Xref-04_saudi_rules_drift.md` line 374) — drift catalog
- REVIEW_v0.10.2.md line 88 — listed as HIGH in the master review
- saudi-rules.md:113-117 — single-source-pending-corroboration entry

---

### Scenario 7 — Sweep + AKA banner clearing

**Setup:** Bidder team Al-Kaboot's a round during which AKA was called.

**Trace:**
1. AKA sets `S.s.akaCalled = { seat, suit }` at `State.lua:1446`.
2. AKA banner is rendered from `S.s.akaCalled` in `UI.lua:3244-3246`.
3. **Per-trick clear at `State.lua:1325-1327`:**
   ```lua
   s.trick = { leadSuit = nil, plays = {} }
   -- AKA banner only persists for the trick it was called on; clear it
   -- so the next trick starts visually clean.
   s.akaCalled = nil
   ```
4. After trick 8 (round end), this same per-trick clear fires regardless of sweep.
5. Additional safety nets: `State.lua:524` (resync clear), `State.lua:795` (round-start clear), `State.lua:1257` & `1263` (illegal-AKA invalidation).

**AKA does not influence scoring**: it's a partner signal. R.ScoreRound never reads `S.s.akaCalled` — it only consumes `tricks`, `contract`, `meldsByTeam`. So sweep+AKA produces the same final scores as plain sweep.

**Verdict:** CORRECT. AKA banner is cleared at trick 8 end (the same code path as any other trick). No interaction with scoring.

---

## 3. Reverse-Kaboot type-blind bug — concrete repro + recommended fix

**Repro at table:**
- Bidder: seat 1, team A. Contract: Hokm-S undoubled. Seat 1 leads trick 1.
- Run a hand where defenders capture every trick. Common in Saudi practice when the bidder grossly mis-evaluated their hand and partner is also weak (an underbid by overcalled rules).
- Expected (per video #16): defender team gets +88 raw (8.8 gp rounded to 9) ON TOP OF the failed-bid handTotal recovery. With trick-1 leader being bidder, the gate is satisfied.
- Actual (current code): defender team gets +250 raw (25 gp). **Over-pay of 162 raw = ~16 gp per occurrence.**

**Sun variant:** if Sun-S, error is even larger. 220×2 = 440 raw vs 88 raw ⇒ over-pay of 352 raw = ~35 gp.

**Fix sketch (pseudocode, builds on B-State-05 recommendation):**

```lua
-- Constants.lua: add line ~115
K.AL_KABOOT_REVERSE = 88

-- Rules.lua: replace the sweep block at 742-745 with:
local sweepTeam, sweepKind
if trickCount.A == 8 then sweepTeam = "A"
elseif trickCount.B == 8 then sweepTeam = "B" end

if sweepTeam then
    if sweepTeam == bidderTeam then
        sweepKind = "bidder"   -- regular Al-Kaboot
    else
        -- Defender sweep — Reverse Al-Kaboot gate
        local firstSeat = tricks[1] and tricks[1].plays
                          and tricks[1].plays[1] and tricks[1].plays[1].seat
        if firstSeat == contract.bidder then
            sweepKind = "reverse"
        else
            sweepKind = nil
            sweepTeam = nil    -- not a recognized sweep; fall through
        end
    end
end

-- Rules.lua: replace the sweep-replacement block at 847-853 with:
if sweepTeam then
    local bonus
    if sweepKind == "bidder" then
        bonus = (contract.type == K.BID_HOKM) and K.AL_KABOOT_HOKM or K.AL_KABOOT_SUN
    else  -- "reverse"
        bonus = K.AL_KABOOT_REVERSE
    end
    cardA = (sweepTeam == "A") and bonus or 0
    cardB = (sweepTeam == "B") and bonus or 0
    meldPoints.A = (sweepTeam == "A") and meldA or 0
    meldPoints.B = (sweepTeam == "B") and meldB or 0
end
```

**Test coverage to add (Section H of test_rules.lua):**

1. Defender sweep + bidder-led-trick-1 + Hokm ⇒ `final.{defender} = 9` (88÷10 round-up).
2. Defender sweep + bidder-led-trick-1 + Sun ⇒ `final.{defender} = 18` (88×2÷10 = 17.6 → 18 with round-up).
3. Defender sweep + DEFENDER-led-trick-1 ⇒ no Reverse-Kaboot bonus, fall through to ordinary fail (`cardX = handTotal = 152` for Hokm).
4. Constant existence pin: `assertTrue(K.AL_KABOOT_REVERSE)` and `assertEq(K.AL_KABOOT_REVERSE, 88)`.

---

## 4. Sweep-vs-meld composition correctness

**Question:** When sweep replaces normal scoring, are melds (Belote, sequences, carrés) handled correctly?

| Concern | Code site | Behavior |
|---|---|---|
| Sweeper's own melds preserved? | `Rules.lua:852-853` | YES. `meldPoints.A = (sweepTeam == "A") and meldA or 0` — sweeper keeps own meld total. |
| Loser's melds zeroed? | `Rules.lua:852-853` | YES. The `or 0` branch zeroes loser's meld. |
| Belote routed to sweeper? | `Rules.lua:752-754` | YES. Override forces `belote = sweepTeam` regardless of K+Q-of-trump holder. |
| Belote-100 cancellation still applies after sweep override? | `Rules.lua:769-777` | YES. Cancellation runs AFTER the sweep override, so a 100-meld held by the sweeping team correctly cancels their belote. |
| Multiplier applied to (sweep-bonus + meld)? | `Rules.lua:926-927` | YES. `rawA = (cardA + meldPoints.A) * mult` — both sweep bonus and melds get multiplied. |
| Belote +20 stays multiplier-immune? | `Rules.lua:929-943` | YES. `rawA = rawA + K.MELD_BELOTE` is added AFTER multiplication. |

**Tricky composition case verified — Sun Al-Kaboot + Carré-A:**
- `cardA = 220` (sweep), `meldPoints.A = 400` (Carré-A).
- `rawA = (220 + 400) × 2 = 1240`. (Sun-multiplier scales BOTH sweep bonus AND meld value.)
- `final.A = 124` gp.

Test coverage gap: test_rules.lua Section H tests sweep without melds (`{ A = {}, B = {} }`). No test for sweep-with-melds composition. **Recommend adding a test pinning the 124-gp Sun + Carré-A scenario.**

---

## 5. Bugs found

### BUG-1 — Reverse Al-Kaboot type-blind (HIGH)

**Location:** `Rules.lua:742-745` (sweep detection) + `Rules.lua:847-853` (sweep replacement).

**Description:** Defender-sweep awards 250 (Hokm) / 220×2 (Sun) raw — same as bidder-sweep. Per Saudi rule (video #16), should be +88 raw, gated on `tricks[1].plays[1].seat == contract.bidder`. The constant `K.AL_KABOOT_REVERSE` does not exist in the codebase.

**Magnitude:** ~16 gp/round (Hokm) or ~35 gp/round (Sun) over-pay to defenders. At target ~152 gp, this can flip game outcomes.

**Recommendation:** Wire the fix per §3, add `K.AL_KABOOT_REVERSE = 88`, add 4 test cases.

**Severity:** HIGH (per A-Src-18, B-State-05 F-01, C-Xref-04 #13, REVIEW_v0.10.2.md line 88, REVIEW_v0.10.4_ship_readiness.md line 177).

**Status:** UNWIRED, KNOWN, DEFERRED across at least v0.7.1 → v0.10.2 (per `audit_v0.7.1/07_section7_endgame.md` row 9, `audit_v0.9.0/20_section7_now.md` row 2, REVIEW_v0.10.4 ship-readiness still flagged HIGH).

---

### NON-BUG-1 — Sun ×2 not collapsed by "ignore tripled/foured/gahwa" (verified clean)

**Concern raised in goal:** Could the v0.10.0 R2 collapse at `Rules.lua:914-918` accidentally ignore the Sun ×2 itself?

**Verdict:** NO. The collapse only branches inside the `contract.type == K.BID_SUN` block AFTER `mult = mult * K.MULT_SUN` is applied at line 916. The "ignore" is for tripled/foured/gahwa flags only — line 918 is a comment, not a `mult /= 2` operation. Sun ×2 always applies on Sun contracts.

---

### NON-BUG-2 — Sweep + AKA banner persistence (verified clean)

**Concern raised in goal:** Is the AKA banner correctly cleared on round-end after a sweep?

**Verdict:** YES. Per-trick clear at `State.lua:1327` fires after every trick including trick 8. Backup clears at resync (`524`), round-start (`795`), and illegal-AKA invalidation (`1257`, `1263`). Sweep does not change this code path — `R.ScoreRound` doesn't touch `S.s.akaCalled`.

---

### NON-BUG-3 — Cumulative scoring with ×4 sweep (verified clean, design concern noted)

**Concern raised in goal:** Does cumulative scoring handle a +100 gp swing in one round?

**Verdict:** Arithmetic is correct (`final.A = 100`). The per-round delta is computed correctly by `R.ScoreRound`. Cumulative-target-crossing is the caller's job (`Net.lua HostStepAfterTrick`), not `R.ScoreRound`. Out of scope for S-Score-06.

**Design note (FYI, MEDIUM priority for separate review):** A 100 gp single-round swing is intentionally Saudi-correct (Bel→Triple→Four × Kaboot is the maximum payout). UI banners and game-end branches should accommodate this. Not a bug.

---

## Summary

- **6 of 7 scenarios pass.** Sweep replacement at `Rules.lua:847-853` correctly preserves sweeper's melds, zeroes loser's melds, routes belote to sweeper, and composes cleanly with all multiplier flavors (Sun ×2, Bel, Triple, Four).
- **1 scenario reveals a HIGH bug:** Reverse Al-Kaboot is type-blind. Defender sweep overpays by 162-352 raw depending on contract. `K.AL_KABOOT_REVERSE = 88` constant + `firstLeaderIsBidder` gate are both missing. Status unchanged across multiple audit cycles (v0.7.1 → v0.10.2).
- **Test coverage gap:** Section H of test_rules.lua covers sweep without melds. Add Sun + Carré-A sweep test (final = 124) and Reverse-Kaboot tests (post-fix).
- **AKA banner clearing on sweep round-end:** verified clean via per-trick clear at `State.lua:1327`.
