# BIDDING_CALIBRATION_v0.10.5.md — bot-bidding source-canonical trace

**Mode:** Read-only. Probe agent did not modify any `.lua`, `.md`, test, or
config. All numbers below are derived from a Python re-implementation of
`Bot.lua:706-740` (`suitStrengthAsTrump`) and `Bot.lua:882-927` (`sunStrength`)
with the bonus pipeline at `Bot.lua:1215-1218` and the gates at `Bot.lua:1423`,
`Bot.lua:1441`, `Bot.lua:1498-1510`. Verified against current code at
v0.10.5 head.

---

## 1. TL;DR — verdict

**The lever for v0.10.5 is HOKM-side, not Sun-side.** The Sun bonus bump in
v0.10.4 was on the right axis but the bigger shortfall is `hokmMinShape`
hard-coding `count >= 3 trumps` at `Bot.lua:803-804`, which **rejects the
Saudi canonical-minimum Hokm hand pattern** described in video #26 R2
("**ولد of trump + ONE other trump cover (مردوفة) + ONE side إكة**" — only
**2 trumps** plus one side Ace). That single predicate excludes ~19% of
hands per Monte-Carlo (200k trials) — and per the source video it's the
single most-emphasized "minimum confident bid" in the entire Hokm corpus.

Concrete simulated effect of relaxing the predicate to `(count >= 3 with side A)
OR (count == 2 with J of trump AND side A)` (Lever C below):

| Lever | Sun bid % | Hokm bid % | Pass % | Net bid % |
|---|---|---|---|---|
| **CURRENT v0.10.4** | 16.76% | 68.62% | 17.92% | 82.08% |
| **Lever C: relax hokmMinShape only** | 16.76% | **79.95%** | **7.65%** | **92.35%** |
| Lever B alone (TH_SUN 50→44) | 28.47% | 62.94% | 14.75% | 85.25% |
| Lever D (B+C combined) | 28.47% | 73.26% | 6.14% | 93.86% |

A single line change to `hokmMinShape` lifts net bid rate +10pp. Sun
threshold tweaks help but are second-order — and Sun-side carries the
26-vs-16 raw failure asymmetry per video #26 R28, so being aggressive on
Sun is the more dangerous direction. **Recommend Lever C as the sole
v0.10.5 change**, with Lever A (`TH_SUN 50→47`) as an optional small
secondary bump.

---

## 2. Threshold identifier table (Task 1)

The probe brief asked whether thresholds are in `Constants.lua`. Answer:
**partially**. The two big ones (`TH_SUN_BASE`, `TH_HOKM_R1_BASE`,
`TH_HOKM_R2_BASE`) are **local-scope variables in `Bot.lua` lines 35-37**,
NOT in `Constants.lua`. Everything else is in `Constants.lua:332-389`.

| Identifier | Location | Current | Purpose |
|---|---|---|---|
| `TH_HOKM_R1_BASE` | `Bot.lua:35` (local) | 42 | Round-1 (bid card flipped) Hokm strength threshold |
| `TH_HOKM_R2_BASE` | `Bot.lua:36` (local) | 36 | Round-2 (free pick) Hokm strength threshold |
| `TH_SUN_BASE` | `Bot.lua:37` (local) | 50 | Sun strength threshold (both rounds) |
| `BID_JITTER` | `Bot.lua:38` (local) | 6 | ±6 randomization on each threshold per call |
| `K.BOT_BEL_TH` | `Constants.lua:332` | 60 | Defender Bel threshold |
| `K.BOT_TRIPLE_TH` | `Constants.lua:336` | 90 | Bidder Triple threshold |
| `K.BOT_FOUR_TH` | `Constants.lua:337` | 110 | Defender Four threshold |
| `K.BOT_GAHWA_TH` | `Constants.lua:338` | 135 | Bidder Gahwa (match-win) threshold |
| `K.BOT_ASHKAL_TH` | `Constants.lua:339` | 65 | Ashkal call threshold (sun-strength) |
| `K.BOT_PREEMPT_TH` | `Constants.lua:340` | 75 | Triple-on-Ace pre-emption threshold |
| `K.BOT_SUN_3ACE_BONUS` | `Constants.lua:345` | 15 | +bonus to sun-strength when ≥3 Aces (S-3) |
| `K.BOT_SUN_MARDOOFA_BONUS` | `Constants.lua:348` | **10** (was 5 pre-v0.10.4) | +per-mardoofa-pair sun-strength bonus (S-8) |
| `K.BOT_SUN_MARDOOFA_PAIR_CAP` | `Constants.lua:360` | 2 | Cap on mardoofa-pair count |
| `K.BOT_BIDDING_SUN_OVER_HOKM_MARGIN` | `Constants.lua:362` | 5 | Round 2: Sun must beat Hokm by ≥ this (B-5) |
| `K.BOT_ASHKAL_DIRECT_SUN_PIVOT` | `Constants.lua:363` | 85 | Sun ≥ this → skip Ashkal, bid direct Sun (A-6) |
| `K.BOT_PICKBID_BELOTE_BONUS` | `Constants.lua:364` | 20 (`= K.MELD_BELOTE`) | +20 if bidding the Belote (K+Q) suit |
| `K.SUN_BEL_CUMULATIVE_GATE` | `Constants.lua:371` | 100 | Sun-Bel risk threshold; +8 to thSun if our cumulative ≥ 100 |
| `K.BOT_OVERCALL_SELF_TH` | `Constants.lua:381` | 75 | Bidder Hokm→Sun upgrade threshold |
| `K.BOT_OVERCALL_TAKE_TH` | `Constants.lua:382` | 80 | Non-bidder take-as-Sun threshold |
| `K.BOT_OVERCALL_TAKE_HOKM_TH` | `Constants.lua:389` | 80 | Cross-trump take-as-Hokm threshold |

**Why the bidding thresholds are local-scope, not constant-scope** (relevant
for the main fork): per the file-1 commentary at `Bot.lua:24-37`, these were
historically iterated several times in tuning rounds without test infrastructure
that needed external tuning. Promoting them to `K.*` is mechanical (`local TH_X
= 50` → `K.BOT_TH_SUN_BASE = 50` + reference) but is its own change. Section 8
recommends doing this as part of v0.10.5 since we'll be touching these values.

---

## 3. Strength function point allocations (Task 2)

### 3.1 `sunStrength(hand)` — `Bot.lua:882-927`

**Per-card points (always applied):**

| Rank | Points |
|---|---|
| A | 11 |
| T | 10 |
| K | 4 |
| Q | 3 |
| J | 2 |
| 9 / 8 / 7 | 0 |

**Per-suit length walk bonus (post 13th-bot-audit):**
- If `count[suit] >= 5` AND (hasA OR hasK in that suit): `+6 * (count - 4)`.
- AKQ stopper: if `hasA AND hasK AND hasQ` in same suit: `+8`.

**Advanced-tier penalty (Bot.IsAdvanced()):**
- `-10` per suit where `count < 2` OR no honor (A/T/K). Capped at `-18`
  total (was `-25` pre-Gemini softening).

**S-3 / S-8 bonuses applied AT CALL SITE in `Bot.PickBid` (Bot.lua:1215-1218):**
- `if aceCount >= 3: sun += K.BOT_SUN_3ACE_BONUS (=15)`
- `sun += min(mardoofaCount, 2) * K.BOT_SUN_MARDOOFA_BONUS (=10 post-v0.10.4)`

These are **outside** `sunStrength` itself.

### 3.2 `suitStrengthAsTrump(hand, suit)` — `Bot.lua:706-740`

**Per-card points (suit-of-trump only):**

| Rank | Points |
|---|---|
| J | 20 |
| 9 | 14 |
| A | 11 |
| T | 10 |
| K | 4 |
| Q | 3 |
| 8 / 7 | 2 each (13th-bot-audit fix) |

**Length:** `+5 * max(0, count - 2)`.

**J+9 synergy:** if hasJ AND has9: `+18` (Advanced) or `+10` (Basic).

**Advanced-tier weakness damp:** if NOT hasJ AND `count < 5` AND NOT (has9 AND
hasA): `strength = math.floor(strength * 0.4)`.

**`sideSuitAceBonus`** (Bot.lua:745-754): `+8` per side (non-trump) Ace,
capped at 3. Advanced-only.

**Belote bonus**: `+K.BOT_PICKBID_BELOTE_BONUS (=20)` if the Belote suit
matches the would-be trump (`Bot.lua:1438-1440`, `Bot.lua:1487`).

---

## 4. 10-pattern trace — the centerpiece (Tasks 3 + 4)

All values computed with `Bot.IsAdvanced()=True` (M3lm tier — production
default for "advanced bots" in WoW), no urgency, mid-jitter (effective
threshold band shown).

Effective threshold bands (no urgency): `thSun ∈ [44, 56]`, `thHokmR1 ∈ [36, 48]`,
`thHokmR2 ∈ [30, 42]`, `thAshkal ∈ [59, 71]`.

### 4.1 Sun-side patterns

| ID | Hand | sunStrength_raw | bonuses | sun (final) | sunMinShape | Source verdict | Code verdict | **Gap** |
|---|---|---|---|---|---|---|---|---|
| **S-A** | A♠T♠ K♥ 9♦ 7♣8♣ Q♦ J♥ | 12 | +10 (1 mardoofa) | **22** | True | R10 — bid (مجازف) | **PASS** (gap 28) | Score way below TH=50; structure OK |
| **S-B** | A♠T♠ A♥T♥ Q♦ J♣ 7♣8♣ | 29 | +20 (2 mardoofas) | **49** | True | R11 — confident bid | **MARGINAL** (clears TH=50 in ~38% jitter outcomes) | Right at the threshold |
| **S-C** | K♠Q♠J♠T♠ 9♥8♥7♥ 7♦ | 1 | +0 | **1** | **False** | R6 — bid Sun without A (meld override) | **PASS-MINSHAPE** | Min-shape predicate doesn't accept meld-only |
| **S-D** | A♠ A♥ A♦ T♣ Q♦ J♥ 9♥ 7♣ | 38 | +15 (3 Aces) | **53** | True | R12 — mandatory bid | **BIDS** (clears in ~69% jitter outcomes) | Working as expected |
| **S-E** | A♠ 7♠ 8♠ 9♠ 7♥8♥9♥ 7♦ | -7 | +0 | **-7** | **False** | R9 — PASS | **PASS-MINSHAPE** | Correctly rejected |

### 4.2 Hokm-side patterns (trump = ♠)

| ID | Hand | suitStrAsTrump(S) | +sideA | +bel | hokm full | hokmMinShape | Source verdict | Code verdict | **Gap** |
|---|---|---|---|---|---|---|---|---|---|
| **H-A** | J♠ 9♠ 8♠ A♥ A♦ Q♦ J♣ 7♥ | 59 (count=3) | +16 | +0 | **75** | True | R10 — bid Hokm | **BIDS R1** | Clears with margin |
| **H-B** | J♠ 8♠ A♥ Q♦ J♣ 9♥ 7♣ 8♦ | 22 (count=2) | +8 | +0 | **30** | **False** | R2 — **CANONICAL MINIMUM** bid | **PASS-MINSHAPE** | `count==2` rejected by `Bot.lua:803-804` |
| **H-C** | 9♠ 7♠ A♥ A♦ Q♦ J♣ 8♥ 9♥ | 6 (count=2) | +16 | +0 | **22** | **False** | R5 — borderline (depends on score) | **PASS-MINSHAPE** | Reasonable: source itself flags as borderline |
| **H-D** | K♠Q♠J♠T♠ 8♥ 7♥ 9♣ 8♣ | 47 (count=4) | +0 | +20 | **67** | **False** (M3lm) / **True** (Advanced) | R7 — exception bid | **PASS-MINSHAPE under M3lm** (no Ace anywhere); BIDS under Advanced/Basic | M3lm L07 patch over-rejects |
| **H-E** | 7♠ 8♠ Q♦ J♣ 9♥ 7♣ 7♥ 8♦ | 1 (count=2) | +0 | +0 | **1** | False | R3 — PASS | **PASS-MINSHAPE** | Correctly rejected |

### 4.3 Calibration mismatches (highlighted)

Source says BID, code says PASS:
- **S-A** (R10 mojazef minimum): score gap of 28 — **structural under-rewarding of A+T mardoofa pattern**.
- **S-C** (R6 sequence-100 + no Ace): not bid because `sunMinShape` requires ≥1 Ace OR mardoofa. Source is explicit this is exception territory.
- **H-B** (R2 CANONICAL): `count==2` predicate rejection. **This is the single biggest issue.**
- **H-D** (R7 sirra-malaki): M3lm L07 "must-have-Ace" patch rejects this when the hand has KQJT trump meld but no Ace. Source explicitly calls this out as the "rare exception" — Advanced/Basic accept it correctly.

Source says PASS, code says BID: **none observed**. Threshold is not too LOW.

---

## 5. Calibration gaps identified (Task 5)

### 5.1 Sun side

Of the 4 "should bid" Sun patterns (S-A, S-B, S-C, S-D):

| Pattern | Source verdict | Current outcome | Gap | Fix-by-threshold? |
|---|---|---|---|---|
| **S-A** | R10 bid | sun=22 vs TH=50 | **28 pts** | NO — gap too large; bonus or formula must change |
| **S-B** | R11 bid | sun=49 vs TH=50 | **1 pt**  | YES — TH=44-47 fixes this |
| **S-C** | R6 bid (meld no A) | sun=1, sunMinShape=False | (predicate) | NO — needs sunMinShape to accept meld-100 sequence |
| **S-D** | R12 bid | sun=53 vs TH=50 | OK | already firing in 69% of jitter outcomes |

**Sun-side conclusion:** Threshold drop alone DOES NOT fix S-A (the gap is
too large). `K.BOT_SUN_MARDOOFA_BONUS` would need to go from 10 → 30+ to
clear S-A — that's an aggressive bonus that risks false-positives on
non-canonical mardoofa hands. The S-A "مجازف" verdict is described in
video #25 as risky-but-acceptable, not mandatory — so failing to bid S-A is
defensible.

For S-B (the "confident" R11 hand), `TH_SUN 50→47` lifts clear-rate from
~38% → ~75% jitter outcomes — a real improvement. **Lever A (TH_SUN 50→47)
is justified, but smaller-impact than the Hokm fix.**

### 5.2 Hokm side

Of the 4 "should bid" Hokm patterns (H-A, H-B, H-C, H-D):

| Pattern | Source verdict | Current outcome | Gap |
|---|---|---|---|
| **H-A** | R10 bid | full=75 ≥ R1=42 | OK — bids R1 |
| **H-B** | R2 **CANONICAL MIN** | shape=False (count=2) | **predicate** — `count >= 3` over-strict |
| **H-C** | R5 borderline | shape=False (count=2, no J) | partially OK — code is reasonable; source even says "depends on score" |
| **H-D** | R7 exception | shape=False under M3lm (no Ace) | **predicate** — L07 patch over-strict for sirra-malaki |

**Hokm-side conclusion (the big lever):** the gap is **not a threshold gap**;
it's the `hokmMinShape` predicate at `Bot.lua:782-806` rejecting two
source-canonical patterns:

1. **H-B / R2 canonical minimum** — `count == 2 AND hasJ AND hasSideAce` is
   currently rejected. Source video #26 R2 is the single most-emphasized
   "minimum confident Hokm bid" in the corpus: *"أقل شي عشان تشتري الحكم
   يكون عندك الولد، وقطعة مثلا مردوفة معاه، ومعاك إكا وحدها"* —
   "minimum to buy Hokm: the J [of trump], one other trump piece (mardoofa)
   with it, and ONE Ace on the side."

2. **H-D / R7 sirra-malaki exception** — the M3lm L07 "must-have-Ace" check
   (`Bot.lua:800-802`) over-rejects 4-card trump-meld hands that the source
   explicitly carves out as a Hokm-bid path *without* the standard J/9
   trump-anchor constraints. The source-doc rule R7 says: *"إذا كان عندك
   مشروع، والمشروع يكون في الحكم… بعض الناس يشتري حكم شرية"* — "if you
   have a meld and the meld is in the [would-be] trump suit, some people
   buy Hokm just on that sequence."

Per Monte-Carlo (200k random 8-card hands): **~19% of hands match the R2
canonical minimum but are currently rejected**. That's a structural
~19pp deficit on the "bot bids Hokm" measure that no threshold tweak can
recover.

### 5.3 PASS-side false-bidding check

S-E and H-E are both correctly rejected (PASS-MINSHAPE). **The threshold is
NOT too low** — direction-of-error is one-sided over-conservative, not
both-ways-noisy. This eliminates the "drop everything aggressively" risk;
a targeted predicate relaxation does not introduce false bids.

---

## 6. Side-effect check (Task 6)

Per `grep -rn` against the candidate constants/locals:

### 6.1 `TH_SUN_BASE`, `TH_HOKM_R1_BASE`, `TH_HOKM_R2_BASE`

These are **local to `Bot.lua`** (declared `Bot.lua:35-37`). Exhaustive use
sites within `Bot.lua` only:

- `TH_HOKM_R1_BASE`: `Bot.lua:1244` (`r1Base = TH_HOKM_R1_BASE`).
- `TH_HOKM_R2_BASE`: `Bot.lua:1245` (`r2Base = TH_HOKM_R2_BASE`).
- `TH_SUN_BASE`: `Bot.lua:1257` (single use site).
- Derived `thSun`, `thHokmR1`, `thHokmR2` are read at lines `1272`, `1423`,
  `1441`, `1469`, `1498`, `1499`, `1510`. All within `Bot.PickBid`.

**Zero leakage** to escalation, overcall, AKA, or play picker logic. Tweaking
any of these three is bid-only.

### 6.2 `K.BOT_SUN_MARDOOFA_BONUS`

Single use site confirmed: `Bot.lua:1218`. No other reads anywhere in the
addon (`tests/test_state_bot.lua` reads it only for value-assertion). Safe.

### 6.3 `K.BOT_ASHKAL_TH`, `K.BOT_PREEMPT_TH`

Each used only in `Bot.lua:1407` and `Bot.lua:3769` respectively. No
cross-site dependencies. Not a candidate change for v0.10.5.

### 6.4 `hokmMinShape` (function-level)

Defined at `Bot.lua:782-806`. Called at:
- `Bot.lua:1432` (round-1 Hokm-on-flipped path).
- `Bot.lua:1483` (round-2 best-suit search).

Two call sites only, both in `Bot.PickBid`. Relaxing the predicate has
**zero leakage** to play picker, escalation, AKA, or any other logic. Safe.

### 6.5 Cross-tier check

The M3lm "must have any Ace" branch (`Bot.lua:800-802`) is gated on
`Bot.IsM3lm()`. So Lever C affects only the M3lm+ tiers; Basic/Advanced
already accept H-D under the L07-less path. If we want H-D to bid under
M3lm too, the gating needs adjustment (proposed in §8).

---

## 7. Combinatoric frequency estimates (Task 7)

From 200k random 8-card hands (deck: 32 cards, ranks 7-A × 4 suits):

| Predicate | Match rate |
|---|---|
| `sunMinShape` (≥2 Aces OR mardoofa) | **36.47%** |
| `sunMinShape AND sun ≥ 50` (current TH) | **4.03%** |
| `sunMinShape AND sun ≥ 47` (Lever A) | **5.39%** |
| `sunMinShape AND sun ≥ 44` (Lever B) | **7.02%** |
| `hokmMinShape` (any suit, M3lm) | **27.67%** |
| `hokmMinShape AND ≥ TH_R1` | **24.56%** |
| `hokmMinShape AND ≥ TH_R2` | **27.67%** (predicate is the gate) |
| **R2 canonical minimum** (J of trump + count==2 + side Ace) | **19.23%** ← currently REJECTED |

**Per-bot bid frequency simulation** (50k 4-bot rounds, no urgency):

| Variant | Sun bid % | Hokm bid % | Pass % |
|---|---|---|---|
| **CURRENT v0.10.4** | 16.76% (4.21% per bot) | 68.62% | 17.92% |
| Lever A (TH_SUN 50→47) | 22.11% (5.5% per bot) | 66.01% | 16.44% |
| Lever B (TH_SUN 50→44) | 28.47% | 62.94% | 14.75% |
| **Lever C (R2 relax)** | 16.76% | **79.95%** | **7.65%** |
| Lever D (B+C) | 28.47% | 73.26% | 6.14% |
| Lever E (A+C) | 22.11% | 76.86% | 6.97% |

**Telemetry interpretation.** The user's 5/20 = 25% bot bid rate is much
lower than the 82% predicted here — likely because the user's 60% auction
win rate captures most rounds before bots get a chance to bid. The 5 bot
bids likely represent rounds where the user passed; conditioned on
"user passed," the bot-bid base rate matches our simulation.

The **0% bot-fail rate** in telemetry (no bot lost a contract) is
consistent with the over-conservative conclusion: bots only bid hands
where they're virtually guaranteed to make. Relaxing `hokmMinShape` per
Lever C would introduce some borderline-Hokm hands; we'd expect a small,
healthy non-zero fail rate (~5-10%) post-fix as bots take canonical-minimum
hands that occasionally lose.

---

## 8. Recommended v0.10.5 levers (ranked)

### 8.1 Primary — Lever C: relax `hokmMinShape` to accept R2 canonical minimum

**Change at `Bot.lua:803-805`** (the predicate body inside `hokmMinShape`):

```lua
-- before:
if count >= 4 then return true end
if count == 3 and hasSideAce then return true end
return false

-- after (proposed):
if count >= 4 then return true end
if count == 3 and hasSideAce then return true end
if count == 2 and hasSideAce then return true end  -- R2 canonical minimum (video #26)
return false
```

**Rationale:** the only addition is `count == 2 + hasJ + hasSideAce` — the
exact pattern from video #26 R2. The existing `not hasJ → return false`
guard at `Bot.lua:798` already enforces "must have J of trump" (R1's
strongest-cards rule). This is a 1-line predicate relaxation that exactly
matches the source canonical minimum.

**Risk:** Some `count==2` Hokm bids will fail (borderline hands). But:
- Failed Hokm = 16 raw vs failed Sun = 26 raw (R28 / video #26).
- The 0% bot-fail rate signal in telemetry indicates the bot is leaving
  expected-positive bids on the table. A 5-10% post-fix fail rate is
  healthy and source-aligned.

**Expected impact:** Net bid rate 82% → 92.35%. Sun bid rate unchanged.
Hokm bid rate 68.6% → 79.95% (+11.3pp, **largest possible single-lever
lift**).

**Side-effect surface:** zero. Function called only from `Bot.PickBid` lines
1432 and 1483.

### 8.2 Optional secondary — Lever A: drop `TH_SUN_BASE` 50 → 47

**Change at `Bot.lua:37`:**

```lua
-- before:
local TH_SUN_BASE     = 50

-- after:
local TH_SUN_BASE     = 47
```

**Rationale:** moves S-B (R11 confident hand) from "marginal 38% jitter clear"
to "75% jitter clear" — small but real. Doesn't help S-A (gap too large).

**Risk:** the v0.10.4 Mardoofa bonus bump 5→10 already moved Sun-bid rate
3.1% → 4.0% per the prior validation pass; this would push it to ~5.4%.
Combined with Lever C (which doesn't touch Sun) the user-side complaint
narrows further.

**Expected impact:** Sun bid rate 16.8% → 22.1%. Hokm bid rate dips
slightly (1.3pp) due to Sun overcalling more often.

**Skip if:** main fork wants minimal-surface change. Lever C alone is
sufficient to materially address the under-bidding telemetry.

### 8.3 NOT recommended — Lever R7 (sirra-malaki Hokm under M3lm)

H-D is rejected under M3lm because of the v0.10.0 L07 "must have any Ace"
patch. Adding an exception (`OR (count >= 4 AND has K-Q-J-T meld in trump)`)
would re-enable it. **But:** Pro-2 PDF L07 calls this defensive against
Sun-overcall and Carré-A — there's a real reason the M3lm tier wants the
Ace check. Touching it requires re-evaluating the L07 trade-off in
isolation. **Defer to a separate audit pass, not v0.10.5.**

### 8.4 NOT recommended — additional `K.BOT_SUN_MARDOOFA_BONUS` bump

Bumping 10 → 15 or higher to clear S-A is tempting but:
- Source says S-A is "مجازف" (risky), not mandatory.
- The bonus already accumulates linearly; over-rewarding mardoofa tilts
  the bot toward Sun-bidding hands the source would not.
- Lever C (Hokm-side) addresses the bigger calibration gap with smaller
  surface change.

### 8.5 NOT recommended — promoting locals to `K.*`

`TH_SUN_BASE`, `TH_HOKM_R1_BASE`, `TH_HOKM_R2_BASE` should eventually be
in `Constants.lua` for consistency with the rest of the bot tunables, but
this is a refactor, not a calibration. **Defer.** If the main fork wants
to bundle, the names should be `K.BOT_TH_SUN_BASE`,
`K.BOT_TH_HOKM_R1_BASE`, `K.BOT_TH_HOKM_R2_BASE` (matches existing
`K.BOT_*_TH` naming).

---

## 9. Single-line "main fork prompt"

> **In `Bot.lua` `hokmMinShape` (line 803-805), add a `count == 2 and hasSideAce` clause to accept the canonical-minimum Hokm shape from video #26 R2 (J of trump + 1 cover trump + 1 side Ace), ranked above any threshold tweak — this is the single source-aligned lever for the over-conservative bot-bidding telemetry; optionally also drop `TH_SUN_BASE` 50 → 47 at `Bot.lua:37` for a secondary +5pp Sun bid lift.**
