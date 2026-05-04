# 43_score_calculation — extracted notes

**Source:** YouTube video #10 — "حساب النقاط في البلوت للمبتدئين"
**URL:** https://www.youtube.com/watch?v=-QrykaZdosE
**Slug:** 43_score_calculation
**Topic:** Tutorial on Saudi Baloot scoring — how raw card-points
(*ابناط* / *bnaat*) convert to score-sheet points (*نقاط* / *nuqat*),
tie-break behaviour, and meld-conversion in each contract type.

---

## 1. Decision rules (extracted)

The video is **scoring tutorial**, not strategy — there are no
play-decision rules of the WHEN/RULE/MAPS-TO form. The "rules"
below are *scoring-resolution* rules used by `R.ScoreRound`, not
bot-action rules.

| # | WHEN | RULE | MAPS-TO |
|---|---|---|---|
| 1 | Round ends, calculating which team scored what | Always count the **non-bidder team's pile** (الفريق اللي ما اشترى) — generally has fewer cards, faster to add | `R.ScoreRound` already counts both piles deterministically; no code change needed. Convention is *human-side*, not bot-side. |
| 2 | Sun contract, raw bnaat tally complete | Convert raw → nuqat by **÷ 5** | Equivalent to `K.MULT_SUN = 2` applied at point-conversion stage (Sun raw 130 ÷ 5 = 26 nuqat; Hokm raw 162 ÷ 10 ≈ 16 nuqat → Sun's effective per-raw-point yield is 2× Hokm). Already encoded. |
| 3 | Hokm contract, raw bnaat tally complete | Convert raw → nuqat by **÷ 10**, rounded | Already encoded via `K.MULT_HOKM = 1` semantics. |
| 4 | Hokm raw points produce non-integer nuqat (e.g. 162 → 16.2) | **Truncate / round to nearest integer**; speaker uses 16 for 162 | `R.ScoreRound` already rounds; no change needed. |
| 5 | Defender team's raw bnaat are NOT a clean multiple of 10 (Hokm) or 5 (Sun) — speaker example: 67 raw bnaat | **Round to nearest 10**: 1-4 round down, 5-9 round up. (e.g. 67 → 70, 64 → 60, 65 → 70, 55 → 60) | Bot does not apply this rounding — `R.ScoreRound` works in raw points, then converts. **Confirm `R.ScoreRound` matches this rounding convention** or document the divergence. |
| 6 | Defender raw nuqat **>** bidder raw nuqat | Bidder **fails**; defenders take the **full** contract value (26 Sun / 16 Hokm) **plus their melds**; bidder gets 0 | `R.ScoreRound` `bidderFails` branch — encoded. |
| 7 | Defender raw nuqat **<** bidder raw nuqat | **Split** — each side keeps what they scored (plus melds) | Encoded. |
| 8 | Defender raw nuqat **=** bidder raw nuqat (the tie) | **Not explicitly addressed in this video.** Speaker shows "more than half = bidder wins, less than half = bidder loses" but skips the exact-tie case. | `saudi-rules.md` says 81/162 = bidder fails (strict-majority rule). **This video does not contradict that — but does not confirm it either.** Treat saudi-rules.md as authoritative. |
| 9 | Meld scoring in Sun | Divide meld bnaat by 5: Sira (20) → 4; 50 → 10; 100 → 20; 400 (four Aces) → 80 nuqat; Belote = 20 raw → 4 nuqat | Already encoded. |
| 10 | Meld scoring in Hokm | Divide meld bnaat by 10: Sira (20) → 2; 50 → 5; 100 → 10; Belote = 20 raw → 2 nuqat | Already encoded. |
| 11 | Hokm contracts and the **400** (four-Aces meld) | **Disallowed in Hokm — 400 is Sun-only** ("في الحكم ما في 400") | Matches `K.MELD_CARRE_A_SUN` being Sun-gated. Confirmed. |

**Net change for code:** zero rules to wire. This is a tutorial
that confirms what `R.ScoreRound` and `Constants.lua` already do.

---

## 2. New terms encountered

| Arabic | Likely meaning | Glossary action |
|---|---|---|
| **ابناط / بنط** (bnaat / bant) | Raw card-points (the un-converted face-value sum) | **Add to glossary.** Currently the docs use "raw points" — the Arabic term is *bant* (singular) / *bnaat* (plural). Speaker contrasts with **نقاط** (nuqat = scoresheet points). |
| **نقاط** (nuqat) | Scoresheet points (after raw-to-nuqat conversion) | **Add to glossary.** Already used in many places; flagging the term explicitly disambiguates from raw bnaat. |
| **النشره** (al-nashra) | The score-sheet / score-tracking surface (paper or app) | New term; minor. Add as a note. |
| **حلَّة الأرض / الأرض / الأخيري / آخر حلَّة** | Multiple synonyms for **the last trick** (which carries the +10 bonus) | Glossary already has *al-akheeri* and *al-arḍ*. Confirms existing entries. |
| **اشترى / المشتري** (ishtara / al-mushtari) | "bought / the buyer" = bid-winner / bidder | Common idiom; worth adding as gloss. |
| **اللي ما اشترى** (illi ma ishtara) | "the one who didn't buy" = defenders | Common idiom; worth adding. |
| **سرة / السيرة** (sira) | The 20-bnaat 3-card sequence (Tierce — Sira) | Already in glossary as `K.MELD_SEQ3` (= 20). |

---

## 3. Non-rule observations (the heart of this extraction)

### 3a. Card-value cross-check vs `Constants.lua`

Speaker enumerates values explicitly. All match the glossary.

| Card | Sun (transcript) | `Rules.lua`/`saudi-rules.md` | Match |
|---|---|---|---|
| A (Ekka) | 11 | 11 | ✓ |
| T (Kaala) | 10 | 10 | ✓ |
| K (Shayib) | 4 | 4 | ✓ |
| Q (Bint) | 3 | 3 | ✓ |
| J (Walad) | 2 | 2 | ✓ |
| 9 / 8 / 7 | 0 | 0 | ✓ |

| Card (trump in Hokm) | Hokm trump (transcript) | Glossary value | Match |
|---|---|---|---|
| J of trump (Walad al-Hokm) | 20 | 20 | ✓ |
| 9 of trump | 14 | 14 | ✓ |
| Off-trump J (any non-trump suit) | 2 | 2 | ✓ |
| Off-trump 9 | 0 | 0 | ✓ |

**No card-value discrepancies.**

### 3b. Hand-total cross-check

| Constant | Transcript value | Code (`K.*`) | Match |
|---|---|---|---|
| HAND_TOTAL_SUN | 130 (= 120 + 10 last-trick) | `K.HAND_TOTAL_SUN = 130` | ✓ |
| HAND_TOTAL_HOKM | 162 (= 152 + 10 last-trick) | `K.HAND_TOTAL_HOKM = 162` | ✓ |
| LAST_TRICK_BONUS | 10 (الأرض / الأخيري) | `K.LAST_TRICK_BONUS = 10` | ✓ |

Speaker walks through the arithmetic explicitly:
- **Sun 130:** 10 (last) + 11 (A) + 4×4 (4 Aces … wait, he means 4 suits) + 4×10 (Tens) + 4×4 (Kings) + 4×3 (Queens) + 4×2 (Jacks) = 10 + 44 + 40 + 16 + 12 + 8 = 130. ✓
- **Hokm 162:** 10 (last) + 20 (J trump) + 3×2 (other Js) + 14 (9 trump) + 0×3 (other 9s) + 4×11 (Aces) + 4×10 (Tens) + 4×4 (Kings) + 4×3 (Queens) = 10 + 20 + 6 + 14 + 44 + 40 + 16 + 12 = 162. ✓

**No hand-total discrepancies.**

### 3c. Multiplier interpretation — IMPORTANT NUANCE

The video presents the Sun ×2 effect via a **conversion divisor**
rather than an explicit "×2 multiplier":

- **Sun:** raw bnaat ÷ **5** = nuqat (130 ÷ 5 = 26)
- **Hokm:** raw bnaat ÷ **10** = nuqat (162 ÷ 10 = 16, rounded down from 16.2)

The ratio of these conversions (10/5 = 2) IS the Sun-over-Hokm
multiplier. So `K.MULT_SUN = 2` and the divide-by-5-vs-10
description in this video are **mathematically equivalent**, just
presented at a different stage of the calculation.

**No discrepancy** — but `saudi-rules.md` line 41-43 phrases this
as "Sun round total = 130 … then ×2 multiplier applied = 260
effective". That phrasing is correct *as effective magnitude vs
Hokm*, but a reader could mistake it for "Sun raw doubles to 260
bnaat", which it does not. **Suggestion:** add a one-liner to
`saudi-rules.md` clarifying that the ×2 is realized through the
÷5-vs-÷10 nuqat conversion, not by literally doubling the raw
bnaat. (Optional clean-up; not a bug.)

### 3d. Half-and-half tiebreak — confirmed in spirit, not exact-tie

Speaker's framing (timestamps ~177-200 in the transcript):
- "If non-bidder team's nuqat are **higher** than bidder's →
  loss for bidder, defenders take all 26 (Sun) / 16 (Hokm)."
- "If non-bidder team's nuqat are **lower** than bidder's →
  split."

He gives examples (14 vs 12, 12 vs 14, 16 vs 14) but **does not
narrate an exact-tie example** (e.g. 13 vs 13). This is consistent
with `saudi-rules.md`'s rule that *bidder needs strictly more than
half* (so the tie-side falls to the defenders), but the video does
not pose the question, so it neither confirms nor denies. **Treat
existing `R.ScoreRound` semantics as authoritative.**

### 3e. Rounding rule — POSSIBLE divergence from code

Speaker explicitly describes a **round-to-nearest-10** rule for
defender raw bnaat:
- "If raw is 1-4, round down; if 5-9, round up."
- Examples: 67 → 70, 64 → 60, 65 → 70, 55 → 60, 51 → 50.

This rounding happens **on the raw side, before division**. The
purpose is so that the resulting nuqat is a clean integer.

**Question for `R.ScoreRound`:** does it apply this Saudi-style
banker's-rounding-to-nearest-10 on the raw bnaat *before* dividing
by 10 (Hokm) or 5 (Sun)? Or does it just compute `floor(raw / 10)`
or `floor(raw / 5)`? These give different answers, e.g.:
- Raw 67 Hokm: video method → 70 → 7 nuqat. `floor(67/10)` = 6. Off-by-one.
- Raw 64 Hokm: video → 60 → 6. `floor(64/10)` = 6. Match.
- Raw 65 Hokm: video → 70 → 7. `floor(65/10)` = 6. Off-by-one.
- Raw 14 Sun: video → 15 ??? wait, for Sun the rounding granularity is unclear from transcript — speaker uses 14 nuqat as a finalised count (14 already an integer). For Sun he never demonstrates rounding because his examples are 40/70 raw bnaat which are clean ÷5.

**FLAG:** speaker does NOT walk through Sun rounding granularity
(does Sun raw round to nearest 5 instead of nearest 10?). The
description of "1-4 down, 5-9 up" is illustrated only with Hokm
examples (raw bnaat 51-67). Sun rounding rule is **left
unspecified by this video**.

**Action:** verify `R.ScoreRound` rounding behaviour against this
rule. If `R.ScoreRound` does plain `floor(raw / divisor)`, it
under-counts the defender pile by 1 nuqat in roughly half of all
non-clean cases. This is potentially significant in close rounds
where the bidder is sitting on a +1 nuqat margin. **Treat as
follow-up work** — do not silently change `R.ScoreRound` based
on one video; corroborate with `saudi-rules.md` author or another
scoring video before patching.

### 3f. Multipliers and Bel — NOT discussed in this video

The video is targeted at **beginners** and **explicitly tells
viewers to play without bnaat** (= without the multiplier
escalations) until they're comfortable. So Bel / Bel x2 / Four /
Gahwa multipliers are **not addressed at all** here.

`K.MULT_BEL = 2`, `K.MULT_TRIPLE = 3`, `K.MULT_FOUR = 4` and
`K.AL_KABOOT_HOKM = 250` / `K.AL_KABOOT_SUN = 220` therefore
**cannot be cross-checked from this video**. Use videos #11
(Bel-legality) and #16 (Reverse Kaboot) for those.

### 3g. Al-Kaboot / sweep — NOT discussed

Speaker doesn't mention Al-Kaboot. Cannot confirm
`K.AL_KABOOT_HOKM = 250` or `K.AL_KABOOT_SUN = 220` from this
transcript.

### 3h. "Failed contract → 0 to bidder, full to defenders"

Speaker is explicit (timestamps ~186-189): "if defenders' nuqat
exceed bidder's, defenders take all 26 (Sun) / all 16 (Hokm)
plus their melds; bidder takes 0."

Confirms `R.ScoreRound`'s `bidderFails` branch. ✓

### 3i. "Calculate one pile, infer the other"

Speaker: "Total Hokm = 16 nuqat. If defenders have 7 nuqat, bidder
has 9 nuqat (16 - 7)." This subtraction-from-total method is
mentioned as the typical human-counting workflow.

**Code-relevant:** `R.ScoreRound` actually adds both piles
independently (bidder + defenders should sum to round total,
modulo melds). This is correct because the human "subtraction
shortcut" is just an algebraic identity, not a rule. No action.

### 3j. "Score during play vs after-the-fact"

Speaker (~125-128): some players tally as the round progresses.
Speaker recommends counting only at end-of-round to avoid
distraction errors. **Player-side advice; no code implication.**

---

## 4. Open questions / follow-ups

1. **Sun rounding granularity** — does Sun round-to-nearest-5 or
   round-to-nearest-10? Video doesn't say. `R.ScoreRound`
   behaviour should be verified.
2. **Exact-tie nuqat** (e.g. 13 vs 13 in Hokm) — video doesn't
   pose. Trust `saudi-rules.md` (bidder fails on tie).
3. **Where does the rounding apply to Sun bnaat?** If raw Sun is
   42 → Sun nuqat = 42/5 = 8.4. Video implies 8 (truncate). But
   round-to-nearest would give 8.4 → 8 (down) vs 42→45→9. Need
   confirmation from another Sun scoring example.

---

## 5. Source-of-truth log

- **Video #10** is the *only* Saudi tutorial we've extracted that
  walks through the *raw-to-nuqat conversion mechanic in arithmetic
  detail*. Earlier transcripts (videos #1-9) referenced "16 / 26
  scoring" but didn't explain *why* — this video supplies the
  divide-by-5/10 rule.
- Speaker is the same author as videos #01-09 (per the
  introduction wording — "this is the last fundamentals video";
  consistent style, same channel).
- **No information here contradicts `saudi-rules.md` or
  `Constants.lua`.** All hand totals, card values, and meld
  values check out.
