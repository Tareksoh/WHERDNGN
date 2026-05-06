# Audit: `Bot.PickBid` Sun branch (Bot.lua:942, HEAD v0.7.2)

Re-grepped via `function Bot.PickBid(seat)` -> **line 942** (no drift).
Sun-relevant slice: 942-1213. Helper `aceCountAndMardoofa` -> 665.
`sunMinShape` -> 621. `sunStrength` -> 687.

## A+T mardoofa detection
**Wired, two-tier.** `aceCountAndMardoofa` (665-679) returns
`mardoofaCount` by intersecting per-suit `hasA[su]` and `hasT[su]`.
Used by:
- Pre-shape gate `sunMinShape` (621-637): single-Ace hand qualifies
  IF that Ace shares a suit with a T (true mardoofa, not raw Ace=2).
- Strength bonus (984): `min(mardoofaCount, CAP=2) * BONUS=5` -> max +10.
- Ashkal block A-4 (1090-1096): cancels Ashkal when bid-up=T and we
  hold matching A. **Explicit, not Ace-count proxy.**

## S-3 calibration (3+ Aces)
+15 (`K.BOT_SUN_3ACE_BONUS`, Constants:311) added unconditionally at 983.
Stacks with mardoofa bonus (max +10) and `sunStrength` raw (~25-45 for
3-Ace hands). Per inline comment (974-981): floor sun~=44 vs `thSun=44`
base -> "clears in ~70% of jitter outcomes." Hokm-default-bias is set
by the Hokm path having a *separate* threshold (`thHokmR1/R2`); the
Sun bonus does NOT directly suppress Hokm — both branches evaluate
independently in R1 (Sun checked first at 1147, Hokm at 1155-1169),
and R2 uses B-5 +5 margin (1204) when both viable.

## Sun-Mughataa (S-8, video #25)
**Distinct from raw Ace bonus.** S-3 keys on `aceCount>=3`; S-8 keys on
`mardoofaCount` (A+T pair). Same hand can collect both: 3 Aces + 1 A/T
pair = +15 (S-3) + 5 (S-8) = +20. Cap=2 prevents triple-pair piling.

## B-7 status (Bel-fear bias, our team >=100)
**Wired** at 1036-1041. Adds +8 to `thSun` when
`S.s.cumulative[R.TeamOf(seat)] >= K.SUN_BEL_CUMULATIVE_GATE` (=100,
Constants:325). Note polarity: comment claims "OTHER team can still
Bel us when WE >=100" — this matches Saudi rule E-1 (only team <100
qualifies for Bel; if ours >=100, opp may still be <100). Wiring is
correct. **Caveat:** bias applies *only* to `thSun`; Hokm thresholds
are untouched, so the seat may shunt to Hokm-on-flipped freely. Doc
implies that's intended (Sun specifically risks 2x-Bel = -26).

## Carré of Aces
**Earliest return, line 956:** `if aceCount >= 4 then return K.BID_SUN`.
Sits *above* prior-bid scan (959-964), Bel-fear (1036), Ashkal (1073),
all thresholds. Uses `aceCount` from the same helper (no separate
meld detector) — 4 Aces always present in `aceCount>=4`, no false
positives possible. **Mandatory-Sun semantics correctly enforced.**

## Verdict + 3 specific gaps

1. **B-7 only biases Sun, never Hokm.** When OUR team >=100, opp could
   also Bel a Hokm contract if opp <100 (multiplier on 16-raw is
   smaller, but still a hit). Doc rule is "Sun-Bel-gate" specifically,
   so this is likely intentional — but no comment confirms why Hokm
   path was excluded. Add a one-liner or wire symmetric +N to
   `thHokmR1/R2`.

2. **B-7 ignores OPP cumulative.** The +8 fires on OUR team total only,
   but the actual Bel-eligibility hinges on OPP being <100 (Saudi E-1).
   If both teams are >=100, Bel is impossible — the Sun bias is dead
   weight. Cheap fix: `myTotal >= GATE and oppTotal < GATE`.

3. **S-4 Carré-of-Aces does not consult `belote`.** A K+Q-of-trump
   hand that ALSO has 4 Aces will short-circuit to Sun at 956,
   forfeiting the +20 multiplier-immune Belote bonus the Hokm path
   would have captured. Saudi rule treats 4-Aces=400 as overriding,
   so this is correct *per doc* but worth a comment noting the
   400-vs-Bel-Hokm trade was considered.
