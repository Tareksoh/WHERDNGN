# 26 — Saudi rules scoring audit (v0.9.0)

Cross-check of `docs/strategy/saudi-rules.md` claims vs live
`Constants.lua` + `Rules.lua R.ScoreRound` (HEAD v0.9.0).

## 1. Card values — PASS

`Constants.lua:42-47`:
- `K.POINTS_TRUMP_HOKM = {7=0, 8=0, 9=14, T=10, J=20, Q=3, K=4, A=11}` → sum 62. Matches doc.
- `K.POINTS_PLAIN = {7=0, 8=0, 9=0, T=10, J=2, Q=3, K=4, A=11}` → sum 30/suit. Matches doc.

## 2. Hand totals — PASS

`Constants.lua:53-55`:
- `K.LAST_TRICK_BONUS = 10`
- `K.HAND_TOTAL_HOKM = 162` (152 + 10)
- `K.HAND_TOTAL_SUN = 130` (120 + 10, pre-multiplier)
Sun ×2 mult brings effective Sun to 260, matches doc.

## 3. Multiplier composition — PASS

`Rules.lua:803-808` builds `mult` as `MULT_BASE × (Sun?2:1) × esc`,
where `esc ∈ {Bel=2, Triple=3, Four=4, Gahwa=4}`. Sun stacks; only
the highest escalation tier applies (chained `if/elseif`). Matches
canonical Saudi escalation chain.

## 4. Belote post-multiplier add — PASS

`Rules.lua:810-827`: cardPts and meldPts multiplied first
(`raw = (card + meld) * mult`); Belote +20 added AFTER. Multiplier-
immune as documented. Comment at 813-822 explicitly cites the rule
and warns against mutating meldPoints.

## 5. Strict-majority tiebreak — PASS

`Rules.lua:712-742`: `bidderTotal > oppTotal` makes; `<` fails;
`==` goes to "fail" when no escalation (line 739-741: `else
outcome_kind = "fail"`). On 162 Hokm, bidder needs >=82 to make,
exactly half (81) fails. Matches doc rule "bidder fails on tied
81/162." Also handles Bel/Four "tie inversion" (rule 4-10) as
"take" (lines 737-738).

## 6. div10 5-rounds-UP — PASS

`Rules.lua:833`: `div10(x) = math.floor((x + 5) / 10)`. Sample:
- 65 → floor(70/10) = 7 (rounds UP). PASS.
- 64 → floor(69/10) = 6. PASS.
- 67 → floor(72/10) = 7. PASS.

Comment cites video #43 fix; saudi-rules.md Q4 (line 156) is now
stale and should be updated — the doc's Q4 still says "possible
mismatch" but code is correct per v0.5.6 fix.

## 7. Bidder-fail captures all — PASS

`Rules.lua:753-770`: opp team gets full `handTotal`; each team
keeps own melds (per "مشروعي لي"). Belote still routes via post-
multiplier add.

## 8. Al-Kaboot multiplier — KNOWN BEHAVIOR (PASS)

Sweep branch (`Rules.lua:747-752`): sets cardA/cardB = AL_KABOOT
bonus (250 Hokm / 220 Sun raw). Bonus IS multiplied at line 810
(`(cardA + meldPoints.A) * mult`). Earlier audit
(63_multiplier_hunt.md) flagged this. Per Saudi convention this
is correct — AL_KABOOT_SUN=220 is calibrated *expecting* the Sun
×2 (220×2/10 = 44 gp, matching pagat's 44-gp Sun sweep). On Bel'd
Hokm sweep: 250×2/10 = 50 gp = correct doubled sweep value. The
220 vs 250 asymmetry is precisely the calibration that makes the
multiplier path produce canonical values. **Not a bug.**

## Summary

All 7 doc-vs-code claims match. saudi-rules.md Q4 docs note
(line 156) is stale and should be updated to reflect v0.5.6 fix.
