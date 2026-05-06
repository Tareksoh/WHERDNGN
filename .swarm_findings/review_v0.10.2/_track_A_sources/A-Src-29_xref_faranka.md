# A-Src-29 — Cross-source reconciliation of Faranka rules (Track-A xref)

**Mode:** Read-only cross-source reconciliation. **No code modifications performed.**
**Reviewer agent:** Track-A xref / Faranka authority arbitrator.
**Output role:** Definitive Faranka authority table for downstream tracks (B/C/D/RT) to consult.

---

## Sources consulted (7)

| ID | Path | Type | Coverage |
|---|---|---|---|
| **S1** | `docs/strategy/_transcripts/h1eEwSezzic_04_faranka_in_hokm.ar-orig.srt` | Primary transcript | Hokm Faranka, 6:29 runtime |
| **S2** | `docs/strategy/_transcripts/lbIAJF5Eo28_06_faranka_in_sun.ar-orig.srt` | Primary transcript | Sun Faranka, 13:37 runtime |
| **S3** | `.swarm_findings/_pdf_extracted/02_playing_system.txt` | PDF extract | Playing system / bidding rules — **no Faranka content** |
| **S4** | `.swarm_findings/_pdf_extracted/06_third.txt` | PDF extract | "Third" bid rule — **no Faranka content** |
| **S5** | `.swarm_findings/review_v0.10.2/_track_A_sources/A-Src-01_v04_faranka_hokm.md` | v0.10.2 re-extract (Hokm) | Video #04 only, single-track-A |
| **S6** | `.swarm_findings/review_v0.10.2/_track_A_sources/A-Src-03_v06_sun_faranka.md` | v0.10.2 re-extract (Sun) | Video #06 only, single-track-A |
| **S7** | `.swarm_findings/review_v0.10.0/_phase1_sources/source_C_faranka.md` | v0.10.0 phase1 source | Merged 04+06, 39 rules extracted |

**Verbatim verification:** S1 (lines 184, 193) and S2 (lines 1594, 2314, 2964) re-grepped to confirm S5/S6/S7's verbatim quotations are accurate.

---

## TL;DR — definitive verdicts on the 10 questions

| Q# | Question | Verdict | Authority |
|---|---|---|---|
| **Q1** | F-16 K-trump-cover in #04? | **NOT in #04** — pure #06 anti-rule | S1 zero hits + S5 confirm + S6 native source |
| **Q2** | F-30b risk-free path: does F-16 still apply? | **NO** — threat model extinct under `oppTrumpExhausted` | S1 + S5 + S7 all silent on F-16-in-Hokm |
| **Q3** | Bidder-team vs bidder-only for Hokm Exception #4? | **Bidder-team** (S5's V04-Q9 generalisation supports S7's reading) | S1 v04 lines 1024-1029 = "خويك"; S5 V04-Q9; S7 line 263 |
| **Q4** | F-14 transcription slip in #06? | **CONFIRMED in #06** (S2 line 1594 verbatim); **NOT in #04** | S2 + S6 + S7 unanimous; S5 confirms #04 silent |
| **Q5** | Sun Faranka 5-factor weighted vs AND-gated? | **WEIGHTED** — unanimous | S6 + S7 unanimous; speaker uses "نسبه" (probability) ~10x |
| **Q6** | Default-yes Sun vs Default-no Hokm verbatim? | **Default-NO Hokm: stated outright** (S1 + S2). **Default-YES Sun: NOT stated outright** — inferred from absence + 5-factor framework | S1 line 9, S2 line 2964; S6 Q2 |
| **Q7** | Anti-rule rule 7 (Q-led + J+8)? | **NOT in #04, NOT in #06** — addon-internal heuristic with no source basis | S5 explicit, S6 silent, S7 silent, S1+S2 grep negative |
| **Q8** | F-26 worked example: J or Q? | **Q (البنت)** — S5's correction is verified | S1 line 184 verbatim "راح يلعب البنت" |
| **Q9** | Bot.lua:2740-2900 branches and source authority? | See §Q9 table — 6 branches, 1 source-aligned, 4 over-tight, 1 unsupported | S1+S2+S5+S6+S7 cross-checked |
| **Q10** | PDF rules NOT in videos? | **None** — PDFs (02, 06) contain ZERO Faranka content. They are about bidding/playing system + the "third" bid | S3, S4 verified |

---

## Q1 — F-16 K-required anti-rule: is it in #04?

### Source verdicts

| Source | Verdict | Evidence |
|---|---|---|
| **S1 (#04 transcript)** | **NOT present.** Zero occurrences of "ما تفرنك اذا ما عندك الشاي" or any K-of-trump cover requirement. | grep on "الشاي" (truncated K reference) returns **0 hits in #04**; "الشايب" (full K) appears 45x but always as a card identity in worked examples, never as a Faranka prerequisite. |
| **S2 (#06 transcript)** | **PRESENT** at 11:46-11:48 (S2 line 2534 area). | "ما تفرنك اذا ما عندك الشاي" — "Don't Faranka if you don't have the K" — explicit Sun anti-rule. |
| **S5 (A-Src-01)** | "**Not in video 04.** F-16 originates from video 06 Sun-Faranka anti-rules." | S5 §Q2 + §Q-D-RT-03 unambiguous. |
| **S6 (A-Src-03)** | "**Anti-rule #1 — Don't Faranka if you DON'T hold the K**" verified at 11:46-11:48. Sun-only. | S6 §Q3 Anti-rule #1, "Definite" confidence. |
| **S7 (source_C)** | F-16 listed in **Sun-Faranka anti-rules** section (line 174). Source_C does NOT advocate Hokm application — that was a v0.10.0 X3 inference. | S7 line 174 "Hand-shape preconditions: You lack K of the suit being Faranka'd. Phase scope: All Sun-Faranka." |
| **S3, S4 (PDFs)** | No Faranka content. | — |

### Reconciliation

**Verdict: F-16 is a Sun-only anti-rule, native to video #06. Its presence in `Bot.lua:2964-2972` (Hokm Faranka path) is a v0.10.0 X3 code-side inference with no source mandate from any of S1, S5, S6, S7.**

**No source contradicts** — all 7 sources agree F-16 is from #06. The disagreement is between the **code** (`Bot.lua:2964-2972` applies F-16 universally in Hokm) and the **source corpus** (which never states it for Hokm).

---

## Q2 — F-30b risk-free path: does ANY source say F-16 still applies?

### Source verdicts

| Source | Verdict |
|---|---|
| **S1 (#04 transcript)** | **NO.** F-30 statement at 00:05:00 mentions K (الشايب) but as a **side-suit K** ("you have A and K of side"). The accompanying condition is "trumps exhausted" (خلصت الاحكام من ايادي اللاعبين, S1 line 924) — the precondition that makes F-16's K-trump-cover threat model extinct. F-16 is never invoked. |
| **S2 (#06 transcript)** | **NO.** F-16's native context is Sun-Faranka where the threat is "opp holds A-of-led-suit and punishes preserved K". This threat presupposes the led suit has live cards in opps' hands. Under F-30b's `oppTrumpExhausted == true`, the suit at risk is trump, and opps are *void* in trump — the threat is structurally absent. |
| **S5 (A-Src-01)** | **NO.** §Q-D-RT-03 explicit: "**when F-30b's predicate fires (`oppTrumpExhausted == true`, both opps observed trump-void), the threat model that motivates F-16 is impossible by construction. The opps cannot ruff with trump A because they have no trump.**" Recommends **Option (A): scope F-16 to Triggers #2/#3 only**. |
| **S6 (A-Src-03)** | **NOT applicable** — A-Src-03 is Sun-Faranka focused; doesn't directly address Hokm F-30b path. But its Anti-rule #1 ("no K = no Faranka") is presented as a **Sun rule**, not a universal one. |
| **S7 (source_C)** | **Silent.** F-16 is listed in Sun-Faranka anti-rules section (line 174). F-30 is in Hokm exceptions section (line 291). source_C does not *propose* applying F-16 to F-30b — that was a v0.10.0 X3 cross-cutting inference. |
| **S3, S4** | No Faranka content. |

### Reconciliation

**Verdict: NO source says F-16 applies under F-30b's `oppTrumpExhausted` precondition. The code's universal F-16 veto at `Bot.lua:2964-2972` is over-restrictive on the F-30b path.**

S5 makes the strongest case: D-RT-03 S-1 is **source-aligned**. The recommended fix is Option (A) — scope F-16 to Exception #2 (weak 2-trump) and Exception #3 (J-dead 9-only), skip on Exception #4 (F-30b).

---

## Q3 — Bidder-team vs bidder-only for Hokm Exception #4

### Source verdicts

| Source | Verdict | Evidence |
|---|---|---|
| **S1 (#04 transcript)** | **Mixed.** The *favourable-trigger sentence* (V04-Q8 @ 05:00) is bidder-only: "وده انت كنت مشتري حكم". The *generalisation passage* (V04-Q9 @ 05:23-05:33) is bidder-team or wider: "**سواء انت مشتري او خويك او حتى لو الخصم**" = "**whether you are the buyer, or your partner, or even if the opponent [bought]**". | S1 lines 904, 1024-1029. |
| **S5 (A-Src-01)** | **Bidder-team (medium-high confidence).** §Q4: "Code's `contract.bidder == seat` is over-tight by one seat (excludes bidder's partner). Source-supported predicate: `R.TeamOf(contract.bidder) == R.TeamOf(seat)`." Cites V04-Q9 generalisation + team-level strategic frame (Kabout extension is a team plan). | S5 §Q4 explicit. |
| **S6 (A-Src-03)** | **Not directly addressed for Hokm Exception #4** (out of scope for #06 video). For Sun Factor #5 the analogous gate is bidder-team: S2 line ~6:10 "وانتوا كنتوا مشترين سواء انت كنت مشتري او خوية كان مشتري" = "you were the bidders — either you bought or your partner bought". | S6 Q5-E2. |
| **S7 (source_C)** | **Original verdict: bidder-team** (line 263, 298). "Speaker example is bidder ('اشتريت حكم'), but the rule (weak trump holding) seems applicable to any seat with weak trump." For F-30 (line 298): "Explicitly bidder-only ('انت كنت مشتري حكم')." source_C's F-30 reading was tighter than its F-27 reading. | S7 lines 263, 298. |
| **S3, S4** | No Faranka content. |

### Reconciliation

**Verdict: Bidder-team is the correct predicate.**

- S7's F-30 reading ("explicitly bidder-only") was *quote-correct* but *strategy-incomplete* — it missed S1's V04-Q9 generalisation (which S5 surfaces).
- S5's V04-Q9 finding and S6's analogous Sun Factor #5 ("انت كنت مشتري او خوية كان مشتري") together justify bidder-team.
- S1 line 1024-1029 verbatim "خويك" (your partner) parallel to "you" supports team-level reading.
- The code's `contract.bidder == seat` predicate at `Bot.lua:2898-2899` (gate for Exception #2) and at `Bot.lua:2943` (gate for Exception #4) was relaxed in v0.10.0 X3 to `R.TeamOf(contract.bidder) == R.TeamOf(seat)`. **This change is source-aligned.**

**No contradictions among S1, S5, S7, S6.** S7's "explicitly bidder-only" framing is superseded by S5's broader V04-Q9 finding.

---

## Q4 — F-14 transcription slip

### Source verdicts

| Source | Verdict | Evidence |
|---|---|---|
| **S1 (#04 transcript)** | **NOT in #04.** Grep on "اخر لاعب" (last player) returns 0 hits in #04. S5 confirms. | grep negative; S5 §Q1 explicit. |
| **S2 (#06 transcript)** | **PRESENT in #06** at 06:45-06:52: "اذا كنت اخر لاعب انت لازم تتفرنك" (S2 line 1594). Worked example at 07:02-07:09 (S2 line 1674) explicitly shows the OPPOSITE outcome (must take with A, not Faranka). | S2 lines 1594, 1674. |
| **S5 (A-Src-01)** | **Confirms NOT in #04.** "F-14 originates from video 06. Video 04 has no occurrence of 'اخر لاعب' (last player). Verified via grep." | S5 §Q1. |
| **S6 (A-Src-03)** | **CONFIRMED in #06** at 06:45-07:09. Same Arabic slip ("لازم تتفرنك" where context demands "ما تتفرنك"). Worked example contradicts literal Arabic. Restated cleanly later at 11:14-11:21 ("جاته وهذا ما كان الحله الدور عندك يا تاكل") confirming intent. | S6 §Q4 (Q4-E1, Q4-E2, Q4-E3). |
| **S7 (source_C)** | **CONFIRMED.** Line 159: "اذا كنت اخر لاعب انت لازم تتفرنك" with explicit NOTE: "appears to be a transcription/speech artifact... intended rule is: DO NOT Faranka, take the trick with your A. **[FOCUS — possible code/lexicon trap if a reader takes the literal Arabic.]**" | S7 lines 159-164. |
| **S3, S4** | No Faranka content. |

### Reconciliation

**Verdict: F-14 transcription slip is REAL and confined to #06.**

All sources agree:
1. The slip is in #06 only (not #04).
2. The literal Arabic says "must Faranka" but the worked example shows "must take".
3. The intended rule is "must TAKE (not Faranka) when last seat + opp leading".
4. Restated cleanly later in #06 without the slip.

**The code correctly does NOT implement the slip's literal reading** (S6 §6 LOW). No action needed; this is a "near miss" the code avoided.

**No source contradictions.**

---

## Q5 — Sun Faranka 5-factor: weighted vs AND-gated

### Source verdicts

| Source | Verdict | Evidence |
|---|---|---|
| **S2 (#06 transcript)** | **WEIGHTED.** Speaker uses "نسبه" (probability/ratio) ~10x throughout. Phrasing: "حتزيد نسبه الفرنكه" ("Faranka probability rises"), "تزيد افضليه" ("favourability rises"), "نسبه تناسب وعلى حسب الظروف" ("proportional ratio according to circumstances"). | S2 line 154 "نسبه" multi-occurrence; S6 Q1 evidence Q1-E1 through Q1-E5. |
| **S6 (A-Src-03)** | **WEIGHTED, situational, additive.** "No quantitative weights or thresholds were found in video #06. The speaker explicitly uses qualitative 'نسبه' / 'افضل' / 'حتزيد' language throughout." Code's single AND-gate at `Bot.lua:2584-2612` does NOT match the source. | S6 §Q1 verdict. |
| **S7 (source_C)** | **WEIGHTED.** "Sun-Faranka decisions are proportional / situational... 5 factors are inputs to that probability" (F-37 @ line 347-352). Open ambiguity #5 (line 394): "Speaker enumerates them in priority order but does NOT give numeric weights." | S7 lines 347-352, 394. |
| **S1, S3, S4, S5** | Not applicable — these cover Hokm Faranka, not Sun's 5-factor framework. |

### Reconciliation

**Verdict: WEIGHTED, unanimous across all relevant sources (S2, S6, S7).**

- All 5 factors in #06 are presented as **probability raisers**, not gates to pass.
- No numeric weights given — qualitative ranking only.
- Code's single AND-gate at `Bot.lua:2584-2612` is fidelity-incomplete (per S6 §Q6).

**No contradictions.**

---

## Q6 — Default-YES Sun vs Default-NO Hokm: verbatim from each source

### Source verdicts

| Source | Default-NO Hokm verbatim | Default-YES Sun verbatim |
|---|---|---|
| **S1 (#04 transcript)** | **STATED OUTRIGHT.** 00:00:09: "اغلب لاعبين البلوت راح يقول لك لا تدفنك في الحكم" + "بشكل عام الافضل لا تترن في الحكم لكن فيها تفصيل" (line 9-16 of cue). Reiterated at 06:25: "دائما في الحكم حاول قدر المستطاع لا تتفر". | N/A (Hokm-focused video). |
| **S2 (#06 transcript)** | **STATED at end** (transition to #04): 13:27-13:32 "لا تتفرنك في الحكم الا اذا طمعت في كبوت فقط" (S2 line 2964) — "Don't Faranka in Hokm except if you covet a Kabout, only". | **NOT stated outright.** Sun-Faranka introduced as a question both ways: 00:00:12 "ليش اتفرنك متى اتفرنك متى ما اتفرنك" — "why Faranka, when do you Faranka, when do you NOT Faranka" (S2 line 28-30 area). |
| **S5 (A-Src-01)** | **STATED** at V04-Q1 (00:00:09): "بشكل عام الافضل لا تترن في الحكم". Source-confidence: Definite. | N/A. |
| **S6 (A-Src-03)** | "**NOT stated as 'default yes'.** Sun-Faranka is presented as a SITUATIONAL probability, not a default." Sun-default-yes is *inferred* from (a) absence of default-no statement, (b) 5-factor "raise the probability" framework, (c) explicit anti-rules for narrow Sun cases. | §Q2 verdict. |
| **S7 (source_C)** | F-23 (line 234): "Hokm DEFAULT = NO Faranka. Always. The exceptions below are narrow." | F-37 (line 347): "Faranka decisions are proportional / situational — there is no hard rule, only a probability that rises and falls with hand context." source_C does NOT label Sun as "DEFAULT YES" verbatim. |
| **S3, S4** | No Faranka content. |

### Reconciliation

**Verdict (asymmetric):**
- **Default-NO Hokm: VERBATIM IN ALL VIDEO SOURCES.** Stated outright in #04 (S1 line 9-16) and reiterated as the wrap-up of #06 (S2 line 2964). Confidence: Definite.
- **Default-YES Sun: NOT VERBATIM.** No source contains a sentence "the default in Sun is to Faranka". The "DEFAULT YES" framing is a coding heuristic *inferred* from:
  1. Absence of a "default no Sun" sentence.
  2. The 5-factor "probability raisers" framework presupposing a non-zero baseline.
  3. Explicit anti-rules for narrow Sun cases (which would be redundant under default-no).

**No contradictions, but a precision asymmetry:** Hokm's default-no has a verbatim source quote; Sun's default-yes is a reasonable inference. S6 makes this distinction explicitly.

---

## Q7 — Anti-rule rule 7 (Q-led trump + we hold J+8 rebut)

### Source verdicts

| Source | Verdict | Evidence |
|---|---|---|
| **S1 (#04 transcript)** | **NOT in #04.** No rule mentions "opp leads Q of trump" combined with "we hold J+8" rebut. S5 §Q6: "**Searched the v04 transcript exhaustively; the J+8 rebut pattern does not appear.**" The only Q-of-trump mention in #04 is in the F-26 worked example where opp plays Q in response to partner's cut — opposite seat-structure. | S1 grep negative on this pattern; S5 §Q6 explicit. |
| **S2 (#06 transcript)** | **NOT in #06.** No anti-rule of this form appears in S6's enumeration of #06 anti-rules (Anti-rules #1 through #5 + bonus). | S6 §Q3 lists 5 anti-rules + 1 bonus; rule 7 is not among them. |
| **S5 (A-Src-01)** | "**Not in video 04.** This rule appears to be either (a) extrapolation from video 06 Sun-Faranka factor weighting, or (b) addon-internal heuristic with no source basis." Marks as "**single-track-A unsupported**". | S5 §Q6. |
| **S6 (A-Src-03)** | **NOT in #06** (not addressed; not in anti-rule enumeration). | S6 §Q3 silent on this pattern. |
| **S7 (source_C)** | **NOT in source_C.** No rule of this form in F-09 through F-39 (the 39 extracted rules). | S7 lines 110-369; rule 7 not present. |
| **S3, S4** | No Faranka content. |

### Reconciliation

**Verdict: Rule 7 is UNSUPPORTED by ANY source.**

It is either:
- **(a) addon-internal heuristic** (most likely) — engineered into the code as a defensive belt-and-suspenders without source basis, possibly as a v0.10.0 X3 cross-cutting inference.
- **(b) imported from a non-Faranka video** out of scope here.
- **(c) artifact** of a now-superseded design.

**The code's `Bot.lua:2974-2993` anti-trigger has no source mandate.** D-RT-03 S-5's NIT verdict ("structurally dead post-v0.10.0, harmless belt-and-suspenders") is consistent with this finding. **Recommendation: deprecate or label as `addon-internal`.**

---

## Q8 — F-26 worked example: J or Q?

### Source verdicts

| Source | Verdict | Evidence |
|---|---|---|
| **S1 (#04 transcript)** | **Q (البنت).** S1 line 184 verbatim: "ما راح يلعب التسعه راح يلعب البنت" — "won't play the 9, will play the Q". Followed by line 214: "حتى تاكل حتلعب الولد وحتاخذ التسعه" — "for [partner] to eat, [partner] will play the J and you'll take the 9". | S1 lines 184, 214 verbatim. |
| **S5 (A-Src-01)** | **Q.** §V04-Q3 explicit correction: "**This is a Q (البنت), not a J (الولد)** — the v0.10.0 extraction labelled the seat-before-you's card as 'J' which is incorrect for this passage; it's 'Q'." | S5 §V04-Q3, §Contradictions table row 4. |
| **S7 (source_C)** | **J (incorrect labelling).** Line 256: "you bought Hokm, partner cuts with 7-of-trump → opp likely will play J not 9". | S7 line 256. |
| **S2, S6, S3, S4** | Not applicable (different videos / no Faranka content). |

### Reconciliation

**Verdict: Q is correct. S5's correction is verified against S1 verbatim.**

S7's labelling is incorrect for this specific passage. **The rule's predicate is unaffected** — the rule is "9 must be with the right-opp" (player before you), regardless of whether the right-opp's *worked-example card* is Q or J. Only the worked-example labelling needs correction.

**Track-C action:** update `source_C_faranka.md` line 256 to "opp likely will play **Q** not 9".

---

## Q9 — Bot.lua:2740-2900 implementation alignment

The Hokm Faranka exception block lives at `Bot.lua:2857-3022` (the "Section 10 Hokm Faranka exceptions" block). Read the full block and aligned each branch to its source authority.

### Branch-by-branch authority table

| Bot.lua line range | Branch | Source rule | Source authority | Alignment |
|---|---|---|---|---|
| 2880-2902 | Exception #2 (myTrumpCount==2 + bidder-team) | F-27 | S1 V04-Q4 (00:02:24-30); S5 §Q5; S7 F-27 | **PARTIAL.** Source's predicate is hand-shape (=2 trumps), not seat-gated. v0.9.2 #49 added bidder-team gate to prevent "Faranka into opp's contract" — defensible per S5 §Q5 ("the rule is hand-shape-only; team gate is engineering safety, not source-mandated"). Code is **stricter than source**, defensible. |
| 2904-2932 | Exception #3 J-dead (S.HighestUnplayedRank("S")=="9" + hold9 + bidder-team) | F-29 | S1 V04-Q6 (00:03:19); S5 §Q3; S7 F-29 | **MEDIUM.** Source language is "**من اول**" (prior trick, completed). Code's `S.HighestUnplayedRank` returns "9" iff JS is in `playedCardsThisRound` — does NOT distinguish prior-trick vs same-trick. **Per S5 §Q3, source favours `#(s.tricks or {}) > 0` guard**. v0.10.0 X3 added bidder-team gate (defensible safety per S7's bidder-team predicate suggestion). |
| 2934-2955 | Exception #4 F-30b (oppTrumpExhausted via Bot._memory void) + bidder-team | F-30 + meta-inference | S1 V04-Q8 (00:05:00) bidder-only; S1 V04-Q9 (00:05:23-33) generalises; S5 §Q4; S7 F-30 line 298 | **GOOD.** v0.10.0 X3 relaxed `contract.bidder == seat` to `R.TeamOf(contract.bidder) == R.TeamOf(seat)` — source-aligned per S5 §Q4 (V04-Q9 generalisation supports bidder-team). The `oppTrumpExhausted` precondition matches S1's "خلصت الاحكام من ايادي اللاعبين" (S1 line 924). |
| 2957-2972 | Anti-rule F-16 K-of-trump cover | F-16 | S2 11:46-11:48 (Sun-only); S5 §Q2; S6 Anti-rule #1; S7 F-16 line 174 | **OVER-TIGHT (BUG).** F-16 is a Sun-Faranka anti-rule. **No source mandates it for Hokm.** v0.10.0 X3's universal Hokm application is unsupported. Per S5 §Q-D-RT-03: scope F-16 to Triggers #2/#3 only; **skip on F-30b** (where threat model is extinct under `oppTrumpExhausted`). D-RT-03 S-1 = correct. |
| 2974-2993 | Anti-rule rule 7 (opp-bidder Q-trump-led + we hold J+8) | (none) | **No source.** S1, S2, S5, S6, S7 all silent. | **UNSUPPORTED.** Pure addon-internal heuristic. Per Q7 above, deprecate or label `addon-internal`. D-RT-03 S-5 NIT = correct. |
| 2995-3021 | Faranka card-selection (non-winners pool, prefer non-trump) | F-28 family + F-25 hard-stop logic | S1 V04-Q5 + V04-Q11 | **GOOD.** Mechanical implementation of the "play a non-winner, preserve trump cover" logic. Source-aligned. |

### Implementation summary

| Branch | Source-aligned? | Severity if mismatched |
|---|---|---|
| Exception #2 | Stricter than source (engineering safety) | LOW (defensible) |
| Exception #3 (J-dead detection) | Loose on prior-trick vs same-trick | MEDIUM (per S5 §Q3) |
| Exception #4 (F-30b bidder-team + opp-void) | YES, post-v0.10.0 X3 | — |
| Anti-rule F-16 (universal Hokm) | NO (over-tight) | **HIGH** — over-restricts Exception #4 |
| Rule 7 anti-trigger | NO (no source) | LOW (dead code post-v0.10.0) |
| Card selection | YES | — |

### Code-source ranking

1. **HIGH severity:** F-16 universal Hokm application at `Bot.lua:2964-2972` over-restricts F-30b. Recommended fix per D-RT-03 S-1 + S5 §Q2: scope F-16 to Triggers #2/#3 only.
2. **MEDIUM severity:** F-29 J-dead detection at `Bot.lua:2922-2932` doesn't distinguish prior-trick from same-trick. Recommended fix per S5 §Q3: add `#(s.tricks or {}) > 0` guard.
3. **LOW severity:** Exception #2 bidder-team gate is stricter than source (hand-shape rule), but defensible as engineering safety.
4. **LOW severity:** Rule 7 anti-trigger at `Bot.lua:2974-2993` is unsupported by source. Per D-RT-03 S-5 NIT, harmless dead code post-v0.10.0; can be deprecated.

---

## Q10 — Rules in PDFs 02 and 06 NOT in videos 04 and 06

### Verdict: **NONE.**

PDFs 02 (`02_playing_system.txt`) and 06 (`06_third.txt`) contain **ZERO Faranka content**:

- **PDF 02 ("نظام لعبة البلوت الأساسي" / "Basic Baloot Playing System")** is about: bidding to 251, the 3rd-bid permission, the bidder's right to refuse extra cards, the bel/triple/four/qahwa escalation rules, the projects (sirri/khamseen/100/four-100), the bel definition. **No Faranka rules.**

- **PDF 06 ("الكة لها ثاااالث" / "The A has a Third")** is about: the "3rd bid" right being limited to player 1 and player 2; only when the face-up is an Ace; only for Sun (not Hokm). **No Faranka rules.**

**Conclusion:** PDFs 02 and 06 add nothing to the Faranka rule corpus. The video corpus (S1 + S2) and its derivatives (S5, S6, S7) are the complete authority.

---

## Cross-source contradictions

### Direct contradictions

**ZERO contradictions** between S1, S2, S5, S6, S7 on any rule.

### Quote-correct-but-strategy-incomplete (S7 vs S5)

| Issue | S7 (v0.10.0) | S5/S6 (v0.10.2 re-extract) | Reconciliation |
|---|---|---|---|
| F-30 bidder-team scope | "Explicitly bidder-only" (line 298) | Bidder-only at favourable-trigger; bidder-team after V04-Q9 generalisation | S5 supersedes — S7 missed V04-Q9 |
| F-26 worked example card | "opp likely will play J" (line 256) | Q (البنت), per S1 line 184 verbatim | S5 supersedes — S7 mis-labelled |
| F-29 prior-trick semantics | Quotes "اذا الولد لعب من اول" but doesn't emphasise prior-trick | Explicit prior-trick reading required | S5 sharpens |

### Code-vs-source disagreements

| Issue | Code state | Source corpus | Verdict |
|---|---|---|---|
| F-16 universal Hokm application | Applied at Bot.lua:2964-2972 | Sun-only (S5, S6, S7) | **CODE WRONG** — over-tight on F-30b |
| F-30b bidder-only (pre-v0.10.0) | Pre-v0.10.0: `contract.bidder == seat` | Bidder-team per S5 V04-Q9 | **CODE WAS WRONG** — fixed in v0.10.0 X3 |
| Rule 7 anti-trigger | Implemented at Bot.lua:2974-2993 | No source | **CODE UNSUPPORTED** but harmless |
| F-29 J-dead detection | `S.HighestUnplayedRank` only | Source requires prior trick | **CODE LOOSE** — defensible on frequency |
| Sun 5-factor weighted | Single AND-gate at Bot.lua:2584-2612 | Weighted (S2, S6, S7 unanimous) | **CODE FIDELITY-INCOMPLETE** — captures Factor #1+#2 only |

---

## Definitive Faranka authority table

The single source of truth for downstream tracks. Each rule cites primary source (transcript line/timestamp) and re-extract source (S5/S6) and v0.10.0 source (S7).

### Hokm Faranka rules

| Rule | Domain | Speaker quote (≤15 w) | Primary source | Re-extract | v0.10.0 source | Authority verdict | Code location |
|---|---|---|---|---|---|---|---|
| F-23 default-NO Hokm | Hokm | "بشكل عام الافضل لا تترن في الحكم" | S1 @ 00:00:09 | S5 V04-Q1 | S7 F-23 | **Definite, universal** | Bot.lua default behavior (no Faranka unless exception fires) |
| F-24 Type-3 cabotage | Hokm Type 3 | "تخسرها على الخصم في النوع الثالث فقط" | S1 @ 00:01:20 | S5 V04-Q2 | S7 F-24 | **Definite, bidder-team** | Deferred per Bot.lua:2871 ("sweep-track detection deferred") |
| F-25 hard-stop Types 1/2 | Hokm Types 1, 2 | "اما غير كذا ما انصحك ابدا" | S1 @ 00:01:30 | S5 V04-Q2 | S7 F-25 | **Definite, universal** | Bot.lua default + winners[] preference |
| F-26 J-preservation (right-opp holds 9) | Hokm Type 1 | "والتسعه لازم تكون للاعب اللي قبلك" | S1 @ 00:02:04 | S5 V04-Q3 (Q correction) | S7 F-26 | **Definite, hand-shape; example=bidder; worked-example card = Q** | Not implemented (deferred) |
| F-27 weak 2-trump | Hokm | "ممكن تتفرنك اذا كان عندك حكمين فقط" | S1 @ 00:02:24 | S5 V04-Q4 | S7 F-27 | **Definite, hand-shape; code's bidder-team gate is engineering safety** | Bot.lua:2880-2902 (Exception #2) |
| F-28 9-mardoofa | Hokm Type 1 | "افترض انه عندي التسعه والتسعه مردوفه" | S1 @ 00:02:38 | S5 V04-Q5 | S7 F-28 | **Sometimes, hand-shape** | Not implemented (deferred) |
| F-29 J-dead → 9-Faranka | Hokm Type 1 | "اذا الولد لعب من اول" | S1 @ 00:03:19 | S5 V04-Q6 (prior-trick required) | S7 F-29 | **Definite, prior-trick semantics** | Bot.lua:2904-2932 (Exception #3) — needs prior-trick guard per S5 |
| F-30 A+K of side, Kabout extension | Hokm Type 2 | "وده انت كنت مشتري حكم وعندك ريكا وعندك الشايب" | S1 @ 00:05:00 | S5 V04-Q8 (literal: bidder-only) + V04-Q9 (generalisation: bidder-team) | S7 F-30 line 298 (mis-read as bidder-only) | **Definite, bidder-team** (post-S5 reconciliation) | Bot.lua:2934-2955 (Exception #4) — v0.10.0 X3 fix correct |
| F-31 Partner-not-shape caveat | Hokm Type 2 | "احيانا حتى لو حكم عند خويك" | S1 @ 00:05:11 | — | S7 F-31 | **Common, caveat** | Implicit in worst-case planning |
| F-32 opp-bidder = NO Faranka | Hokm Type 2 | "ما انصحك تتفرلك ابدا بالذات اذا الخصم مشتري حكم" | S1 @ 00:04:11 | S5 V04-Q7 | S7 F-32 line 312 | **Definite, opp-bidder veto** | Bot.lua bidder-team gate inverts this correctly |
| F-33 worst-case meta | Hokm | "حط اسوا الاحتمالات دائما" | S1 @ 00:05:43 | S5 V04-Q10 | S7 F-33 | **Definite, meta** | Implicit in default-NO posture |
| F-34 100% loss on Hokm-Faranka | Hokm | "بعكس لو متفرغت راح الحلين هذه 100%" | S1 @ 00:05:59 | S5 V04-Q11 | S7 F-34 | **Definite** | Justifies F-23 default-NO |
| F-35 take = 2 tricks guaranteed | Hokm | "تضمن حلتين بعكس لوكت ممكن تروح عليك" | S1 @ 00:06:08 | S5 V04-Q11b | S7 F-35 | **Definite** | Bot.lua winners[] preference |
| F-36 partner-trump fallback | Hokm | "حتى لو اخوي تجاوب راح تاكل" | S1 @ 00:06:08 | S5 V04-Q12 | S7 F-36 | **Common** | Strategic context |
| F-23 reiteration | Hokm | "دائما في الحكم حاول قدر المستطاع لا تتفر" | S1 @ 00:06:25 | S5 V04-Q13 | (in S7 F-23) | **Definite, closes video** | — |
| **rule 7 (Q-trump-led + J+8 rebut)** | — | (none) | — | — | — | **UNSUPPORTED** — addon-internal | Bot.lua:2974-2993 — deprecate or label |

### Sun Faranka rules

| Rule | Type | Speaker quote (≤15 w) | Primary source | Re-extract | v0.10.0 source | Authority verdict | Code location |
|---|---|---|---|---|---|---|---|
| F-01 definition | Definitional | "الفرنكه التجاهل ... اكبر ورقه موجوده عندك" | S2 @ 00:21-1:00 | — | S7 F-01 | **Definite** | Implicit in pickFollow architecture |
| F-02 trick must NOT come back | Definitional | "الحله ما تكون عندك" | S2 @ 00:32-35 | — | S7 F-02 | **Definite** | Implicit |
| F-03 two domains | Definitional | "نوعين اما فرنكه في الصن او فرنه في الحكم" | S2 @ 1:00-1:05 | — | S7 F-03 | **Definite** | `contract.type` switch |
| F-04 three Hokm sub-types | Taxonomy | "ثلاثه اقسام ... اوراق الحكم فقط ..." | S2 @ 2:01-2:21 | — | S7 F-04 | **Definite** | Type 3 reuses Sun logic per S7 ambiguity #4 |
| F-05 three positional shapes | Taxonomy | "اول شكل اذا هذا لعب في البدايه" | S2 @ 3:20-3:40 | — | S7 F-05 | **Definite** | Implicit in seat-position checks |
| F-06 use #1 eat 2+ tricks | Use | "اول شيء انك تاكل اكثر من حله" | S2 @ 2:25-2:50 | — | S7 F-06 | **Definite** | Strategic motivation |
| F-07 use #2 Kabout | Use | "تجيب كبوت" | S2 @ 2:50-3:06 | — | S7 F-07 | **Definite** | Strategic motivation |
| F-08 use #3 hunt the 10 | Use | "تصيد العشره" | S2 @ 3:06-3:20 | — | S7 F-08 | **Definite** | Strategic motivation |
| F-09 Factor #1: hold K | Sun Factor | "اول شيء اذا كان عندك الشايب يعني شايب مع عكه" | S2 @ 5:21-5:29 | S6 F1 | S7 F-09 | **Definite, universal** | Bot.lua:2584-2612 partial (requires A+cover) |
| F-10 Factor #2: partner winning | Sun Factor | "اذا خويك كان حل" | S2 @ 5:29-5:36 | S6 F2 | S7 F-10 | **Definite, universal** | Bot.lua:2584 partnerWinning gate |
| F-11 Factor #3: heading to Kabout | Sun Factor | "اذا اللعب كان رايح كبوت" | S2 @ 5:36-5:45 | S6 F3 | S7 F-11 | **Definite, universal** | **Not implemented** |
| F-12 Factor #4: Faranka loses opp's Game-points | Sun Factor | "اذا الفرنكه راح تخسر الجيم على خصمك" | S2 @ 5:45-5:59 | S6 F4 | S7 F-12 | **Definite, opp-bidder gate** | **Not implemented** (code's bidder-team gate would actively reject this case) |
| F-13 Factor #5: left-opp leads next + own-bidder | Sun Factor | "اذا اللاعب اللي يسارك اللعب اول واحد" | S2 @ 5:59-6:30 | S6 F5 | S7 F-13 | **Definite, bidder-team + round-boundary** | **Not implemented** |
| **F-14 last-seat slip** | Anti (slip) | "اذا كنت اخر لاعب انت لازم تتفرنك" | S2 @ 6:45-7:09 | S6 §Q4 | S7 F-14 | **Transcription artifact** — intended: must take, not Faranka | Code correctly does not implement the slip |
| F-15 top-2 live → never Faranka | Anti | "اكبر ورقتين موجوده في اللعب لا تترنك ابدا" | S2 @ 9:30-9:54 | S6 A3 | S7 F-15 | **Definite, hard-stop** | Indirect via cover gate |
| **F-16 no K of suit → no Faranka** | Anti (Sun) | "ما تفرنك اذا ما عندك الشاي" | S2 @ 11:43-11:58 | S6 A1 | S7 F-16 line 174 | **Definite, Sun-only** — NOT for Hokm | Bot.lua:2964-2972 over-applies to Hokm — **HIGH SEVERITY BUG** |
| F-17 ≥3 cards → no Faranka | Anti | "ما تترنك اذا عندك اكثر من ورقتين" | S2 @ 11:58-12:53 | S6 A2 | S7 F-17 | **Definite, hand-shape gate** | Bot.lua:2584 suitCount==2 |
| F-18 Hokm anti-rule (general) | Anti | "لا تتفرنك في الحكم الا اذا طمعت في كبوت" | S2 @ 13:27-13:34 | S6 A5 | S7 F-18 | **Definite, default** | Bot.lua: `contract.type == K.BID_SUN` gate |
| F-19/20/21/22 positional weights | Sun Position | (multiple short quotes) | S2 @ 3:35-4:46 | — | S7 F-19/20/21/22 | **Definite, weighted** | Implicit in 5-factor framework |
| F-37 ratio-thinking | Meta | "نسبه تناسب وعلى حسب الظروف" | S2 @ 5:01-5:08 | S6 Q1-E3 | S7 F-37 | **Definite, meta** | **Not implemented** (single AND-gate vs weighted) |
| F-38 "play simple safety" | Sun | "العب لك امسك بسيطه سلاما" | S2 @ 11:23-11:34 | — | S7 F-38 | **Common** | Strategic motivation |
| F-39 protect partner (top-2 live) | Anti | "هذه الحاله لازم تلعب لك" | S2 @ 9:30-9:54 | S6 bonus anti-rule | S7 F-39 | **Definite, hard-stop** | Implicit via F-15 |

---

## Open ambiguities (post-reconciliation)

1. **F-27 strict-equality vs ≤2 trumps:** Speaker says "حكمين فقط" (literally "two trumps only") — strict equality. But intent is "weak trumps justify the risk", which extends to 1 trump. Code uses `myTrumpCount == 2` (strict). **Source-faithful but pragmatically tight.** Defensible.

2. **F-29 prior-trick vs same-trick:** Source language is unambiguously prior-trick ("من اول"). Code's `S.HighestUnplayedRank` does not distinguish. Per S5 §Q3, source supports `#(s.tricks or {}) > 0` guard. **Code is loose.**

3. **F-30b "trumps exhausted" detection:** Source says "خلصت الاحكام من ايادي اللاعبين" (from players' hands generally). Code tests `oppTrumpExhausted` (only opp-team voids). Asymmetric — what about partner being void? Not addressed by source.

4. **Sun 5-factor weights:** No numeric weights anywhere in source corpus. Calibration must come from simulation or external sources.

5. **F-32 opp-bidder = no Faranka — universal or Type-1/2 only?** S7 ambiguity #6 flagged this; source corpus does not resolve.

---

## Recommendations to downstream tracks

### Track-B (code fixes)
1. **HIGH:** `Bot.lua:2964-2972` — scope F-16 to Triggers #2/#3 only; skip on Trigger #4 (F-30b). Per Q1, Q2, Q9. D-RT-03 S-1 Option (A) is source-aligned.
2. **MEDIUM:** `Bot.lua:2922-2932` — add `#(s.tricks or {}) > 0` guard for F-29 J-dead detection. Per Q9 + S5 §Q3.
3. **LOW:** `Bot.lua:2974-2993` — deprecate or label `addon-internal` (rule 7 unsupported by source). Per Q7. D-RT-03 S-5 NIT.
4. **ARCHITECTURAL:** `Bot.lua:2584-2612` Sun Faranka — refactor toward weighted accumulator (5 factors + 5 anti-rules). Per Q5, Q9 + S6 §Q6.

### Track-C (xref / docs)
1. Update `source_C_faranka.md` line 256: F-26 worked-example card is **Q (البنت)**, not J. Per Q8.
2. Update `source_C_faranka.md` line 298: F-30 bidder-team scope (not strictly bidder-only). Per Q3 + S5 §Q4.
3. Update `source_C_faranka.md` line 174: clarify F-16 is **Sun-only** — explicitly NOT a Hokm-Faranka anti-rule. Per Q1.

### Track-D / RT
1. **D-RT-03 S-1 verdict (F-16 over-fires on F-30b):** **CONFIRMED.** Source-aligned fix is Option (A) — scope F-16 to Triggers #2/#3.
2. **D-RT-03 S-2 verdict (F-29 same-trick edge):** **PARTIALLY CONFIRMED.** Source language favours prior-trick guard; "DEFER" verdict is defensible on frequency but source-stricter.
3. **D-RT-03 S-5 verdict (rule 7 dead-code):** **CONFIRMED.** No source mandate; harmless dead code; can be deprecated.

### Track-A (followup)
1. No further re-extraction needed for Faranka — S1, S2, S5, S6, S7 corpus is complete.
2. PDF 02 and 06 confirmed as containing zero Faranka content (Q10).

---

## Summary

| Question | Definitive answer | Confidence |
|---|---|---|
| Q1 — F-16 in #04? | NO | DEFINITE |
| Q2 — F-16 under F-30b? | NO | DEFINITE |
| Q3 — Bidder-team for Exception #4? | YES (bidder-team) | HIGH |
| Q4 — F-14 slip in #06? | YES; NOT in #04 | DEFINITE |
| Q5 — Sun 5-factor weighted? | YES | UNANIMOUS |
| Q6 — Default-NO Hokm verbatim, default-YES Sun NOT verbatim | YES (asymmetric) | DEFINITE |
| Q7 — Rule 7 anti-rule? | NOT IN ANY SOURCE | DEFINITE |
| Q8 — F-26 worked-example: Q | YES (Q, not J) | DEFINITE (S1 verbatim) |
| Q9 — Bot.lua alignment? | 1 over-tight (F-16), 1 loose (F-29), 1 unsupported (rule 7), 3 aligned | HIGH |
| Q10 — PDF rules not in videos? | NONE (PDFs have no Faranka content) | DEFINITE |

**Net: ZERO direct contradictions across S1, S2, S5, S6, S7.** All disagreements reduce to:
- (a) S7 missed S1 V04-Q9 generalisation → S5 supersedes (Q3)
- (b) S7 mis-labelled F-26 worked-example card → S5 supersedes (Q8)
- (c) Code's v0.10.0 X3 over-applied F-16 universally in Hokm → source corpus uniformly supports Sun-only (Q1, Q2, Q9)
- (d) Code's `Bot.lua:2974-2993` rule 7 is sourceless engineering belt-and-suspenders (Q7, Q9)

The reconciled authority is unambiguous and the source corpus is internally consistent.
