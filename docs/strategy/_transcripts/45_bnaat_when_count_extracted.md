# 45_bnaat_when_count — extracted notes

**Source:** YouTube video — "أبناط البلوت | كيف و متى تحسب الأبناط
بالبلوت..؟ وليش تسبب مشاكل..؟"
**URL:** https://www.youtube.com/watch?v=Qtetnrxz2qY
**Channel:** زات | ZAT (same as video #43)
**Slug:** 45_bnaat_when_count
**Duration:** 10:41
**Topic:** When and how to count *bnaat* (raw card-points), and what
to do when the round is tied. Beginner-targeted; complements
video #43 (`-QrykaZdosE_43_score_calculation`).

---

## 1. Decision rules (extracted)

| # | WHEN | RULE | MAPS-TO |
|---|---|---|---|
| 1 | Round ends, NO indication of a tie | Count ONLY the non-bidder team's pile (faster, fewer mistakes) | Convention is *human-side*; `R.ScoreRound` adds both piles deterministically — no code change. |
| 2 | Round ends, scoresheet shows 8-8 (Hokm) or 13-13 (Sun) | This is the *suggestive* tie threshold. Now count BOTH teams' bnaat to confirm. | `R.ScoreRound` always sums both; suggestion is a HUMAN-counting shortcut. |
| 3 | Hokm contract, `bidder` raw bnaat **=** opp raw bnaat (81-81) | **Record SPLIT 8-8** (each team gets 8 nuqat). **NOT bidder-fail.** | **⚠ DISCREPANCY with current `R.ScoreRound` and `saudi-rules.md`** — code treats 81-81 as *bidder fails*, defenders take 16. See § 4. |
| 4 | Hokm, bidder bnaat **>** opp bnaat (e.g. 82-80, 100-62) | **Record SPLIT (proportional nuqat)** — each team scores their own bnaat ÷ 10. | Matches `R.ScoreRound` "make" branch. ✓ |
| 5 | Hokm, bidder bnaat **<** opp bnaat (e.g. 80-82, 62-100) | **Bidder FAILS** — non-bidder takes 16 nuqat (full handTotal Hokm ÷ 10) + own melds. Bidder gets 0. | Matches `R.ScoreRound` "fail" branch. ✓ |
| 6 | Sun contract, NO 50-or-higher meld on either team | Sun bnaat are *always* tied at 65-65 by structural identity (130/2). DON'T count both — just record split 13-13 unless a meld changes the picture. | Heuristic for human-counting. `R.ScoreRound` doesn't need this — it always adds both. |
| 7 | Sun contract, EITHER team has a 50+ meld | The "always-tied" property breaks. NOW count both teams' bnaat to see who actually won. | Same as Hokm: meld asymmetry shifts the totals. |
| 8 | Sun, bidder + meld total **>** opp + meld total | **SPLIT** (each team scores own ÷ 5) | Matches code's "make" branch. ✓ |
| 9 | Sun, bidder + meld total **=** opp + meld total | **Record SPLIT** (each gets half) | **⚠ Same DISCREPANCY** — code treats Sun 65-65 with meld parity as fail. See § 4. |
| 10 | Sun, bidder + meld total **<** opp + meld total | **Bidder FAILS** — non-bidder takes 26 nuqat + own melds | Matches code's "fail" branch. ✓ |

---

## 2. Hand-total / card-value cross-check

| Constant | Transcript value | Code | Match |
|---|---|---|---|
| HAND_TOTAL_HOKM | 162 (= 152 + 10) | `K.HAND_TOTAL_HOKM = 162` | ✓ |
| HAND_TOTAL_SUN | 130 (= 120 + 10) | `K.HAND_TOTAL_SUN = 130` | ✓ |
| LAST_TRICK_BONUS | 10 (الأرض) | `K.LAST_TRICK_BONUS = 10` | ✓ |
| Plain A | 11 | `K.POINTS_PLAIN.A = 11` | ✓ |
| Plain T | 10 | `K.POINTS_PLAIN.T = 10` | ✓ |
| Plain K | 4 | `K.POINTS_PLAIN.K = 4` | ✓ |
| Plain Q | 3 | `K.POINTS_PLAIN.Q = 3` | ✓ |
| Plain J | 2 | `K.POINTS_PLAIN.J = 2` | ✓ |
| 9/8/7 (plain) | 0 | `K.POINTS_PLAIN[…] = 0` | ✓ |
| Hokm trump J | 20 | `K.POINTS_TRUMP_HOKM.J = 20` | ✓ |
| Hokm trump 9 | 14 | `K.POINTS_TRUMP_HOKM[9] = 14` | ✓ |
| Sira (Tierce) | 20 raw | `K.MELD_SEQ3 = 20` | ✓ |
| 50 meld (Quarte) | 50 raw | `K.MELD_SEQ4 = 50` | ✓ |
| 100 meld (Quinte / Carré non-A) | 100 raw | `K.MELD_SEQ5 = 100`, `K.MELD_CARRE_OTHER = 100` | ✓ |
| 400 meld (Carré-A in Sun) | 400 raw → 80 nuqat | Stored as 200 raw — see note | ⚠ |

**Note on 400-meld:** The video says "أربعمية باربعمية" = "the 400 meld is worth 400 bnaat". Constants.lua stores `K.MELD_CARRE_A_SUN = 200` because the Sun ×2 multiplier is applied at scoring time (200 × 2 = 400 effective ≈ 80 nuqat). This is a representation choice, not a value error. Final scoring is correct. ✓

---

## 3. Multiplier / nuqat-conversion check

Speaker explicitly:
- **Hokm:** raw bnaat ÷ 10 = nuqat (162/10 = 16.2 → 16; 162-81 = 81 → 8)
- **Sun:** raw bnaat ÷ 5 = nuqat (130/5 = 26; 65 → 13)

Code: `R.ScoreRound` applies `cardMult = K.MULT_SUN = 2` for Sun, then `(raw + 5) / 10` round-half-up. Mathematically equivalent to ÷5 on Sun raw.

**Rounding rule** (also confirmed against video #43):
- `(x + 5) / 10` with floor = "1-4 round down, 5-9 round up"
- 67 → 7, 64 → 6, 65 → 7, 55 → 6, 51 → 5
- Matches video #43's explicit examples ✓

---

## 4. ⚠⚠ MAJOR DISCREPANCY: tie semantics

This video **explicitly** states:

| Bidder bnaat | Opp bnaat | Video says | Current code (`R.ScoreRound`) | saudi-rules.md |
|---|---|---|---|---|
| 81 | 81 (Hokm) | **8-8 SPLIT** | bidder FAILS → 0 vs 16 | bidder fails (strict-majority) |
| 65 + meld | 65 (Sun, equal totals) | **SPLIT** | bidder FAILS → 0 vs 26 | bidder fails |
| 80 | 82 (Hokm) | bidder FAILS → 0 vs 16 | bidder FAILS → 0 vs 16 ✓ | bidder fails ✓ |
| 82 | 80 (Hokm) | 8-8 SPLIT (each scores own) | "make" → both keep own ✓ | make ✓ |

**The contention point:** what happens at an EXACT total tie?

- **Video #2:** SPLIT — both teams keep their own scoring (8 vs 8)
- **`R.ScoreRound`:** bidder FAILS — defenders take 16 (full handTotal)
- **`saudi-rules.md`:** bidder fails (strict-majority required)

This is a **regional house-rule variation** (الجلسة). Both
interpretations exist in real Saudi play:

1. **Strict-majority** (current code, saudi-rules.md, sourced from
   PDF + multiple videos): bidder *must* strictly exceed half. Tied
   half-and-half = bidder failed his commitment. More punitive.
2. **Half-and-half-split** (this video #2 + at-table convention in
   some sessions): bidder didn't *fail*; they just didn't *win*.
   Each team keeps what they earned. More lenient.

**Recommended action:**
- DO NOT auto-change `R.ScoreRound` based on this single video.
- Surface to user as an arbitration question.
- If user adopts the "split-on-tie" rule, code change is surgical:
  Rules.lua:1087-1090 — change `outcome_kind = "fail"` in the tie
  branch to `"make"` (both keep own cards). The `"take"` branch for
  defender-escalated chains stays as-is per rule 4-10.

Note: video #43 (also already extracted) **does NOT explicitly cover
the tied-81 case** — it says "bidder > opp = make / bidder < opp =
fail" but skips the exact-tie. So video #43 doesn't pick a side. Video
#2 (this transcript) is the FIRST source we have explicitly stating
"split on tie."

---

## 5. Failed-bid magnitude — confirmed

Speaker (lines 156-158): "If bidder = 80 and opp = 82, that's a
loss. Score 16 to non-bidder team."

This matches `R.ScoreRound` fail branch ✓ and `saudi-rules.md` ✓.

---

## 6. Multiplier interaction with melds — implicit

Speaker treats melds as additive to bnaat *before* the ÷10 (Hokm)
or ÷5 (Sun) conversion:
- "61 cards + 2 siras (40) = 101 bnaat" → 10 nuqat
- "62 cards + 40 melds = 102 bnaat" → 10 nuqat (rounded down)

Code applies `cardMult` to cards and `meldMult` to melds separately.
For Hokm bare (no Bel), `cardMult = meldMult = 1`, so the math is
identical: `(cards + melds + 5) / 10`. ✓

For Sun, `cardMult = meldMult = 2`. The video doesn't show melds
under multiplier escalation (Bel'd/Tripled), so no cross-check
on those edge cases here.

---

## 7. SWA / Al-Kaboot / Belote — NOT discussed

Speaker focuses purely on the bnaat-counting mechanic. No mention
of:
- SWA (سوا) — claim-the-rest mechanic
- Al-Kaboot — sweep bonus
- Belote (K+Q of trump) — independent bonus
- Reverse Al-Kaboot

These remain canon-set per saudi-rules.md and existing videos #15,
#16, etc.

---

## 8. Open questions / arbitration items

1. **TIE semantics in Hokm** (81-81): SPLIT (this video) vs FAIL
   (current code + PDF + saudi-rules.md). USER ARBITRATION REQUIRED.
2. **TIE semantics in Sun** (65-65 with meld parity): same. USER
   ARBITRATION REQUIRED.
3. **Strict-majority vs split-on-tie** is the **only substantive
   discrepancy** — all other math (card values, hand totals,
   multipliers, rounding, fail magnitude) is confirmed consistent
   with the code.

---

## 9. Source-of-truth log

- This is video **#45** by our existing numbering (videos #01-44
  already catalogued; this is a new addition).
- Same speaker as video #43 (channel: ZAT). Speaker promotes the
  Baloot VIP app and mentions a 50%-discount code in the
  description.
- Speaker explicitly addresses *the tie case* — which video #43
  did not. So this is the most direct source on the strict-majority
  vs split-on-tie question we have.
