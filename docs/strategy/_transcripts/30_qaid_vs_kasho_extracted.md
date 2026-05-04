# 30 — Qaid (قيد) vs Kasho (كاشو): two penalty types

**Source:** https://www.youtube.com/watch?v=up4s4WtUEO0
**Title:** الفرق بين القيد والكاشو في البلوت 🤚🏼
**Slug:** `30_qaid_vs_kasho`
**Length:** 24 lines (~1 minute).
**Topic:** Definitional — what distinguishes the two penalty calls
in Saudi Baloot. **Critical for `Rules.lua` correctness** if Kasho
is treated as separate from Qaid (Takweesh).

---

## 1. Glossary additions / fixes

| Arabic | Pronunciation | Meaning | Synonyms in transcript |
|---|---|---|---|
| **قيد** | **Qaid** (lit. "registration / record") | Heavy penalty applied **after** the bid (المشترى) for an in-play rule violation. Awards points + projects (مشاريع/melds) to the non-offending team. | تجييد (taj-yeed, verbal noun), تسجيل (tasjeel), تسجيله, "عجب ولا ما عجب" (informal) |
| **كاشو** | **Kasho** (lit. "exposure / show") | Light penalty applied **before** the bid for a dealing/setup violation. **No points awarded**, just a redeal. | كوشه (Kosha), تكويش (Takweesh — verbal form), جاد والكوشه |

**Reconciliation with existing glossary:**

- The "Open questions" entry **`Qaid (قيد)`** ("penalty applied
  on caught illegal play (Takweesh outcome)") is **partially
  wrong** — Qaid and Takweesh/Kasho are *separate* penalty types
  with different triggers and different point consequences, not
  outcome stages of the same call.
- The existing **`تكويش (Takweesh)`** entry in Special-plays
  table — described as "call illegal-play penalty (qaid)" — is
  also **wrong by conflation**. Takweesh is the **verbal form
  of Kasho**, the *light* pre-bid penalty, NOT the call that
  results in Qaid.
- **Action:** rename / split the entries. Qaid and Kasho are
  sibling penalties.

**Family of names** the speaker lists as roughly synonymous (ALL
referring to the *broader penalty system*, not a specific one):
الجاد والكوشه / التجييد والتكويش / التسجيل والكاشو / التسجيله /
"عجب ولا ما عجب" — these are regional / generational variants of
the same Qaid+Kasho pair.

---

## 2. Penalty definitions

### Qaid (قيد) — heavy penalty

| Aspect | Value |
|---|---|
| **Trigger** | Rule-violation **during play** (after the bid). Speaker says "مخالفه قانون نظام اللعب سواء متعمد او غير متعمد" — intentional or not. |
| **When** | After **المشترى** (the bid winning / contract being struck). |
| **Points awarded to non-offender** | **Sun**: 26 points (full hand value, presumably 26 = 13 base × 2 multiplier — note: differs from existing `K.HAND_TOTAL_SUN`=130; possibly speaker uses a 13-point sub-scale or a normalized scale). **Hokm**: 16 points. |
| **Melds (مشاريع)** | Awarded to the non-offender if they hold any. |
| **Opponent's melds** | "في جلسات تاخذها وفي جلسات ما تاخذها" — *house-rule dependent*. If the violation occurred **before المشترى**, opponent's melds count (16 points scenario per speaker). |
| **Deal rotation** | If a Qaid happens during dealing (the rare pre-bid Qaid case), **deal moves to the next player**. |

### Kasho (كاشو) — light penalty

| Aspect | Value |
|---|---|
| **Trigger** | Violation **before** the bid (dealing-phase / setup error). Cheating cases (الغش) → **always Qaid, never Kasho**. |
| **When** | Pre-bid (قبل المشترى). |
| **Points awarded** | **None**. "ما تاخذ نقطه ولا مشروع." |
| **Deal rotation** | The **same dealer re-deals** (player who dealt re-deals). *If Kasho is called after المشترى — speaker notes some traditions move deal to next player, others keep same dealer.* |

---

## 3. Decision rules

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Rule violation in trick-play, post-bid | Apply **Qaid** — Sun: award 26 (or 130 raw, scale TBD) full hand to non-offender; Hokm: award 16 (or 162 raw) full hand to non-offender. Plus their melds. | Heavy penalty for in-play infractions. | `R.ScoreRound` Qaid-applied branch `(not yet wired — current `Rules.lua` has no Qaid case)`. | Definite | 30 |
| Rule violation pre-bid (dealing error, exposed card, miscount) | Apply **Kasho** — no points, **same dealer redeals**. | Light penalty for setup error; treat as do-over. | Net.lua dealing-phase Kasho handler `(not yet wired)`. | Definite | 30 |
| Cheating (الغش) detected, any phase | **Qaid only** — never Kasho regardless of timing. | Speaker explicit: "في حالات الغش تقيد ما تكوش". | `R.ScoreRound` cheating-branch `(not yet wired)`. | Definite | 30 |
| Qaid during dealing phase (pre-bid Qaid edge case) | Award full Hokm-scale 16 points to non-offender; deal **moves to next player**. | Speaker: "اذا كان جيت قبل المشترى يصير 16 نقطه" + "اذا صار جيت التوزيع ينتقل للاعب اللي بعد". | `Net.lua` dealing-Qaid branch `(not yet wired)`. | Common | 30 |
| Kasho post-bid (rare; speaker notes house variation) | Either same dealer redeals OR deal moves to next player — **house rule**. Default to same-dealer-redeals matching Saudi-tournament convention. | Speaker: "في ناس يقول لا نفس اللاعب يوزع مره ثانيه". | `Net.lua` Kasho-post-bid branch `(not yet wired)`. | Sometimes | 30 |

---

## 4. Open questions / ambiguities

1. **The "26" and "16" point values** in Sun and Hokm Qaid awards
   don't match the existing `K.HAND_TOTAL_SUN`=130 or
   `K.HAND_TOTAL_HOKM`=162 raw values. Likely the speaker is
   citing a normalized / table-scoring scale (16 hokm + 16 sun
   game-target?) rather than raw trick points. Need a second
   source to confirm whether Qaid awards full *raw* hand total
   or a normalized "16/26 game-points" outcome.
2. **Takweesh vs Kasho phonology.** The transcript uses both forms
   (تكويش and كاشو) within the same penalty family. Treat as the
   same call — Takweesh is the verbal-noun form ("the act of
   Kasho-ing"), Kasho is the noun.
3. **House-rule note** on post-bid Kasho redeal direction. Bot
   should default to `same-dealer redeals` for consistency with
   the dominant Saudi convention.
4. **`Rules.lua` currently has no Qaid OR Kasho case.** The
   `K.MSG_TAKWEESH` constant and Net.lua handler exist but
   resolve via a manually-driven UI flow, not via `R.ScoreRound`.
   This video clarifies that the in-code "Takweesh" is more
   accurately the **Kasho** (light) variant; **Qaid** is a
   separate post-bid scoring event currently unmodeled.

---

## 5. Source-quote evidence

> Lines 7-14 (paraphrased, under 15 words quoted): the "first
> distinction is **<<<Qaid scores points>>>** while
> Takweesh/Kasho does not". Sun = 26, Hokm = 16, plus melds.

> Lines 17-23 (paraphrased): cheating → Qaid only; Kasho is
> typically pre-bid; if Qaid happens during deal, deal rotates;
> if Kasho post-bid, dealer behavior is house-variable.

---

## 1-line summary

**Qaid = heavy post-bid scoring penalty (full hand + melds to the
non-offender); Kasho = light pre-bid redeal penalty (no points,
same dealer redeals).** Cheating always triggers Qaid, never Kasho.
