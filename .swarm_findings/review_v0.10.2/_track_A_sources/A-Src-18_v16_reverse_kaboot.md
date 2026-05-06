# A-Src-18 — Video #16 Reverse Al-Kaboot (re-extraction)

**Source:** `docs/strategy/_transcripts/WgU68NXZEH4_16_reverse_kaboot.ar-orig.srt`
**Video ID:** `WgU68NXZEH4` (yt watch?v=WgU68NXZEH4)
**Title slug:** `16_reverse_kaboot`
**Re-extracted:** 2026-05-05 for v0.10.2 R3 — B-State-05 F1 (HIGH NEW) "Reverse Kaboot UNWIRED at Rules.lua:817-822" arbitration.
**File size:** ~234 SRT lines covering ~01:01 of the talk (very short clip — single-topic micro-explainer).
**Read mode:** Authority transcript only. Code referenced for comparison but not modified per task rules.

---

## Headline arbitrations resolved

| Finding | Authority verdict | Confidence |
|---|---|---|
| **B-State-05 F1** — Rules.lua:817-822 awards `K.AL_KABOOT_HOKM` / `K.AL_KABOOT_SUN` (250/220) to **whichever team sweeps**, with no check for Reverse-Kaboot. Authority demands a **separate +88 raw** bonus and a **bidder-led-trick-1 gate**. | **CONFIRMED.** Video #16 line 4 is unambiguous: «كبوت المقلوب نقاطه 88» — "Reverse Kaboot is **88** points." This is contrasted in the SAME sentence with «للكبوت العادي باربعين» — "regular Kaboot at **forty**" (the score-sheet pip representation of 250 raw Hokm / 220 raw Sun ÷ scaling). The current code's "blind sweep" branch at Rules.lua:817 (`if sweepTeam then …local bonus = AL_KABOOT_HOKM/SUN`) ignores both the **88-not-250** distinction AND the **bidder-led-trick-1** gate. A defender sweep against a bidder who *did* lead trick 1 is currently scored as 250/220 (a regular Kaboot bonus, ~3× too large) without honoring the Reverse-Kaboot variant. Worse, a defender sweep where the bidder did NOT lead trick 1 (which authority says should NOT be Reverse-Kaboot) is *also* awarded the 250/220 — a categorically different bug. **Both branches need rewiring.** | Very high |
| **Sun-only?** Q2 — does video #16 restrict Reverse-Kaboot to Sun? | **NOT restricted.** Speaker uses Sun ONLY in the worked example («هذه صن»), but never says Reverse-Kaboot is exclusive to Sun. The opening rule statement (line 4 «كبوت المقلوب نقاطه 88») is contract-agnostic. The bidder-led-trick-1 condition (lines 73-114) is also contract-agnostic. So: **video #16 alone supports Reverse-Kaboot as applying to BOTH Hokm and Sun**, with the Sun example being illustrative not exhaustive. | Medium-high (single source; example is Sun-only but the rule statement is not contract-gated) |
| **Bidder-trick-1 leader requirement (Phase 1 finding)** — does authority say "bidder TEAM" or "bidder personally"? | **Bidder PERSONALLY**, not bidder team. Phase 1's "bidder TEAM" reading is **WRONG**. Lines 93-104 say «المشتري نفسه يكون اللعب على يده» — *"the buyer **himself** has the lead in his hand"* — and «اللاعب اشترى لازم اللعب يكون على يده» — "the player who bought, the lead **must** be in his hand". The negative example at lines 113-114 («مثلا هذا الخصم اشترى وهذا لعب ما يعتبر») disqualifies the case where "this opponent bought but this [other] one led" — even though both are on the bidder TEAM. So Phase 1 needs revision: predicate is `firstLeaderOfRound == S.s.contract.bidder` (the bidder seat, not just bidder-team membership). | Very high — speaker explicit |
| **Ace-lead requirement** — does the bidder's trick-1 lead have to be the Ace? | **No firm requirement; the speaker endorses the looser view.** The strict view (lines 193-203 «بنت الشريعه») mentions Queen of Hearts as one named alternative, but the speaker rebuts: «اي ورقه غير الاكا لكن اهم شيء انه الخصم اللي راح يلعب اول واحد هو اللي يشتريها» — "any card other than the AKA, but the most important thing is that the opponent who plays first is the one who bought it." The speaker's chosen example (line 153) does have the bidder *playing* the AKA at trick 1, but as **the lead card** (not as the catching card). The speaker's normative position is: **lead card NOT need be Ace; what matters is bidder-leads-trick-1 + defenders-sweep.** | High for the looser reading; the strict-Ace-lead is mentioned as a minority view, not endorsed |

---

## Per-question verbatim findings

### Q1 — Reverse Kaboot bonus +88 raw — verbatim Arabic + timestamp

**SRT location:** subtitle #1, timestamp 00:00:00,000 → 00:00:03,110 (continuation cues #2/#3 at 00:00:03,110 → 00:00:05,390 and 00:00:05,400 → 00:00:07,730 carry the same line into the rest of the sentence).

**Verbatim Arabic of headline rule (≤15 words):**
> «كبوت المقلوب نقاطه 88 للكبوت العادي باربعين»

**English:** "Reverse Kaboot's points are 88; regular Kaboot is at forty."

**Full sentence (across cues #1-#5, ~25 words, for context only — single-cue-≤15-word excerpt above):**
«كبوت المقلوب نقاطه 88 للكبوت العادي باربعين وبعض الناس يعتبر الكبوت المقلوب كانه الكبوت العادي يعني باربعين»
"Reverse Kaboot is 88 points; regular Kaboot is at forty. Some people treat Reverse Kaboot as if it were a regular Kaboot — meaning at forty."

**Reading:**
- **Primary rule (speaker's preferred view): Reverse Kaboot = 88 raw.**
- Minority view (also acknowledged by the speaker): Reverse = same as regular Kaboot (250 Hokm / 220 Sun ↔ "40" pip).
- The speaker's position throughout the rest of the clip uses **88** as the canonical figure (line 184 «هذه الحاله ينحسب 88»).

**Score-sheet arithmetic note:** "40" in this dialect is the score-sheet PIP representation. Regular Hokm Kaboot 250 raw → 25 score-sheet pips by the addon's ÷10 convention; the speaker's "40" appears to be a different conversion convention (some house rules use ×4 = 40 sigil for Kaboot). The **important** authority claim is the **CONTRAST**: Reverse is structurally distinct in score AND lower than regular Kaboot. So whatever the addon's regular-Kaboot constant is, Reverse must be its own constant, NOT a reuse of `K.AL_KABOOT_HOKM`/`K.AL_KABOOT_SUN`.

**Confidence:** Very high — verbatim, line-1-of-the-clip, unambiguous.

---

### Q2 — Sun-only? — verbatim

**SRT location:** subtitle #31 (00:00:36,840 → 00:00:39,709) — the **example** uses Sun explicitly, but no rule-statement restricts Reverse-Kaboot to Sun.

**Verbatim Arabic of the Sun-mention (≤15 words):**
> «على يده واخذ الاكا هذه صن وقام الفنان ما»

**English:** "[the lead] is on his hand and he takes the AKA — this is **Sun** — and the player did not…"

**Reading:** The speaker is walking through a **specific example** in Sun. He says «هذه صن» ("this is Sun") to scope the example, NOT to claim Reverse-Kaboot is Sun-only. The opening rule statement at line 4 («كبوت المقلوب نقاطه 88») is contract-agnostic.

**Verdict:** Reverse-Kaboot is **NOT Sun-restricted** by video #16. Both Hokm and Sun should support a Reverse-Kaboot scoring branch. Single-source caveat: this should be cross-checked against any other transcript that discusses Reverse-Kaboot before final wiring.

**Confidence:** Medium-high — speaker scopes the *example* to Sun but does not gate the *rule* on contract type. Phase 1 gloss "applicable to both contracts pending corroboration" is the right call.

---

### Q3 — Bidder-trick-1 leader: bidder TEAM (Phase 1) vs bidder PERSONALLY?

**SRT locations:**
- Subtitle #11 (00:00:13,200 → 00:00:15,230) — defender-team requirement (different point, see Q3a below).
- Subtitle #13 (00:00:15,240 → 00:00:18,050) — bidder-side disambiguation begins.
- Subtitle #15 (00:00:18,060 → 00:00:20,510) — lead must be at "one of the two opponents."
- Subtitle #19 (00:00:22,320 → 00:00:25,130) — **"the buyer himself"** language.
- Subtitle #21 (00:00:25,140 → 00:00:27,170) — **"the player who bought, the lead must be in his hand."**
- Subtitle #23 (00:00:27,180 → 00:00:29,269) — negative example: bidder bought but partner led.

**Q3a — defender side ("you and your partner") — verbatim ≤15 words:**
> «انت لازم تجيب كبوت اما انت وخويك»

**English:** "You must produce a Kaboot — either you and your partner."
**SRT location:** subtitle #11 (00:00:13,200 → 00:00:15,230).
**Reading:** the SWEEPING side is the defender pair (you + partner). This is the team-level requirement — but it concerns the **defender** team, not the bidder. Phase 1's "bidder TEAM" framing conflated the two sides.

**Q3b — bidder side: "bidder PERSONALLY" — verbatim ≤15 words:**
> «المشتري نفسه يكون اللعب على يده اذا هذا»

**English:** "The buyer **himself** has the lead in his hand — so if this…"
**SRT location:** subtitle #19 (00:00:22,320 → 00:00:25,130).

**Q3c — reinforcement, ≤15 words:**
> «اللاعب اشترى لازم اللعب يكون على يده فلو»

**English:** "The player who bought — the lead **must** be in his hand, so if…"
**SRT location:** subtitle #21 (00:00:25,140 → 00:00:27,170).

**Q3d — the disqualifying counter-example, ≤15 words:**
> «مثلا هذا الخصم اشترى وهذا لعب ما يعتبر»

**English:** "For example, this opponent bought but this [other] one played — it does **not** count."
**SRT location:** subtitle #23 (00:00:27,180 → 00:00:29,269).
**Reading:** Even when both "this opponent" and "this other one" are on the bidder TEAM (i.e. partners of the bidder), if the *non-bidder* member of the bidder team led trick 1, the sweep does NOT qualify as Reverse-Kaboot.

**Verdict — corrects Phase 1:**
- **Phase 1 finding:** "Reverse-Kaboot trigger requires the bidder TEAM to lead trick 1." → **Wrong.**
- **Authority verdict:** "Reverse-Kaboot trigger requires the **BIDDER PERSONALLY** (the seat that won the auction) to lead trick 1." → **Right.**
- Predicate must be `firstLeaderOfRound == S.s.contract.bidder` (seat-level), NOT `firstLeaderTeam == bidderTeam`.

**Confidence:** Very high — speaker uses «نفسه» (himself), names the buyer specifically, and explicitly disqualifies bidder-team-but-not-bidder-personally with a worked counterexample.

---

### Q4 — Ace-lead requirement — verbatim

**SRT locations:**
- Subtitle #31 (00:00:36,840 → 00:00:39,709) — strict view: bidder leads with AKA in the example.
- Subtitle #41 (00:00:50,579 → 00:00:53,330) — minority "Queen of Hearts" view.
- Subtitle #43 (00:00:53,340 → 00:00:55,130) — speaker rebuts to looser view.

**Q4a — the example flow Ace-lead, verbatim ≤15 words:**
> «على يده واخذ الاكا هذه صن وقام الفنان ما»

**English:** "[The lead] is on his hand and he takes the AKA — this is Sun — and the player [partner] did not…"
**SRT location:** subtitle #31 (00:00:36,840 → 00:00:39,709).
**Reading:** In the WORKED example, the bidder takes (i.e. leads with) the AKA in Sun. But this is an *illustration*, not the rule.

**Q4b — minority "specific card" view, verbatim ≤15 words:**
> «وفي ناس يقول لا مش شرط الورقه تكون مثلا بنت»

**English:** "And there are people who say no — the card need not be, for example, the [Queen]…"
**SRT location:** subtitle #39 (00:00:47,399 → 00:00:50,569).

**Q4c — speaker's normative position, verbatim ≤15 words:**
> «اي ورقه غير الاكا لكن اهم شيء انه الخصم»

**English:** "Any card other than the AKA — but the most important thing is that the opponent…"
**SRT location:** subtitle #41 (00:00:50,579 → 00:00:53,330).

**Q4d — reinforcement, verbatim ≤15 words:**
> «اللي راح يلعب اول واحد هو اللي يشتريها»

**English:** "…who plays first is the one who buys it."
**SRT location:** subtitle #43 (00:00:53,340 → 00:00:55,130) → #45 (00:00:55,140 → 00:00:58,369).

**Verdict — Ace-lead is NOT a strict requirement:**
- The speaker presents three views: (1) any card OK, (2) any card except the AKA OK, (3) only specific cards (Queen of Hearts) OK.
- The speaker explicitly endorses view #2: «اي ورقه غير الاكا» — "any card other than the AKA."
- BUT the speaker's worked example (line 153) has the bidder LEAD with the AKA in Sun, which contradicts view #2 read literally. The most coherent reading: «غير الاكا» refers to the **defender's catching card** (what defenders use to overcatch the bidder's lead), NOT to the bidder's lead card. The lead-card requirement is just "bidder leads"; the catching-card requirement is "any card except the AKA — i.e. you don't have to use a specific card to catch."
- **For wiring:** the addon should NOT gate Reverse-Kaboot on the bidder's lead being the AKA. The gate is purely structural: bidder leads trick 1 + defenders win all 8 tricks.

**Confidence:** High for "no Ace-lead gate." Medium for the «غير الاكا» = catching-card reading (the speaker is somewhat ambiguous on whether he means lead-card or catching-card; the example points to catching-card).

---

### Q5 — Worked examples — quote

**SRT locations:** subtitle #29 (00:00:33,300 → 00:00:36,830) → #37 (00:00:44,460 → 00:00:47,389). Single connected example, ~10 seconds.

**Verbatim Arabic of the full example (≤30 words across cues — split into two ≤15-word excerpts):**

**Excerpt 1 (≤15 words):**
> «الخصم هذا كان اللعب على يده واخذ الاكا هذه صن وقام الفنان ما»
**SRT location:** subtitles #29-#31 (00:00:33,300 → 00:00:39,709).

**Excerpt 2 (≤15 words):**
> «لعب لك لعب اي شيء ثاني جاك انت او خويك وخلاص»
**SRT location:** subtitles #33-#35 (00:00:39,719 → 00:00:44,450).

**Closing (≤15 words):**
> «وانتوا قاعدين تاكل كل الاكلات وجبتوا كبوت عليهم فهذه الحاله ينحسب 88»
**SRT location:** subtitles #35-#37 (00:00:42,780 → 00:00:47,389).

**English (combined, paraphrase ≤30 words for clarity, NOT verbatim):**
"This opponent had the lead, took the AKA — this is Sun — and the player did not play [back] for you, played something else, Jack — you or your partner [took the trick] — and that's it; you keep eating every trick, you got a Kaboot on them, this case is counted as 88."

**Decoding the example:**
- Setup: **Sun** contract. The bidder is on the OPPOSING team. Bidder has the lead at trick 1.
- Trick 1: Bidder leads the AKA (top card in Sun). Bidder's partner ("الفنان") doesn't follow optimally — plays "anything else." A defender (you or your partner) takes with a Jack.
- Tricks 2-8: Defender team sweeps the rest.
- Score: **88** raw to the defender team as Reverse-Kaboot bonus.

**Critical detail for wiring:** the example shows that Reverse-Kaboot is structurally **about who LED trick 1**, not about who WON trick 1 specifically. In the example, bidder *led* the AKA but a defender *won* the trick (with a Jack overcutting the AKA in Sun, where Jack is highest in trump). The lead-vs-win distinction matters because the existing code (Rules.lua:817 `if sweepTeam then`) checks neither.

**Confidence:** Very high.

---

### Q6 — Trigger conditions

Compiled from across the clip (lines 4-203). All four conditions are required jointly:

| Predicate | Source line(s) | Verbatim anchor | Confidence |
|---|---|---|---|
| `defenderTeam.tricksWon == 8` | #11 (00:00:13,200 → 00:00:15,230) | «انت لازم تجيب كبوت اما انت وخويك» | Very high |
| `S.s.contract.bidder ∈ opponents` (relative to the sweeping team) | #13 (00:00:15,240 → 00:00:18,050) | «والمشتري لازم يكون الخصم» | Very high |
| `firstLeaderOfRound == S.s.contract.bidder` (**seat-level, NOT team-level**) | #19 (00:00:22,320 → 00:00:25,130) + #21 (00:00:25,140 → 00:00:27,170) | «المشتري نفسه يكون اللعب على يده» / «اللاعب اشترى لازم اللعب يكون على يده» | Very high |
| (REJECTED) `winnerCardOfTrick1 ≠ AKA` — minority view, NOT endorsed | #41 (00:00:50,579 → 00:00:53,330) | «اي ورقه غير الاكا لكن اهم شيء…» — speaker says the lead-position requirement supersedes the card-identity requirement | Speaker rebuts; do NOT gate |
| (NOT supported by this video) contract-type restriction (Hokm vs Sun) | — | the only contract-mention is the Sun *example*, not a rule | Treat as both contracts |

**Trigger summary for code:**
```
defenderSweep = (defenderTeam.tricksWon == 8)
bidderIsOpp = (S.s.contract.bidder is on the OPP team relative to defenderTeam)
bidderLedT1 = (firstLeaderOfRound == S.s.contract.bidder)  -- seat, not team
isReverseKaboot = defenderSweep AND bidderIsOpp AND bidderLedT1
```

`bidderIsOpp` is structurally implied by `defenderSweep` (the bidder team can't sweep AND be the defender team simultaneously), so the operative new gate is **`bidderLedT1`**.

**Confidence:** Very high for the three primary predicates; the Ace-lead and contract-type predicates are **NOT** gates per this video.

---

### Q7 — B-State-05 F1 confirm: source authority demands +88 raw vs current code's blind sweep branch

**Current code state (Rules.lua:817-822, READ ONLY — not modified):**
```lua
if sweepTeam then
    local bonus = (contract.type == K.BID_HOKM) and K.AL_KABOOT_HOKM or K.AL_KABOOT_SUN
    cardA = (sweepTeam == "A") and bonus or 0
    cardB = (sweepTeam == "B") and bonus or 0
    meldPoints.A = (sweepTeam == "A") and meldA or 0
    meldPoints.B = (sweepTeam == "B") and meldB or 0
```

**Constants (Constants.lua:114-115):**
- `K.AL_KABOOT_HOKM = 250`
- `K.AL_KABOOT_SUN  = 220`

**B-State-05 F1 verdict — CONFIRMED:**
- Authority says Reverse-Kaboot = **88 raw**, NOT 250 (Hokm) and NOT 220 (Sun).
- Current code awards **whichever-side-sweeps** the regular-Kaboot bonus (250/220), regardless of:
  1. Whether the sweeping side is the **bidder** team (regular Kaboot) or the **defender** team (Reverse-Kaboot).
  2. Whether the bidder personally led trick 1 (the gate that distinguishes Reverse-Kaboot from "just a defender sweep").

**Two distinct bugs in the current branch:**
- **Bug 1 — magnitude:** A defender sweep with bidder-led-trick-1 should award **+88 raw** to defenders. Current code awards **+250** (Hokm) or **+220** (Sun) — i.e. ~3× the authority figure.
- **Bug 2 — gate:** A defender sweep WITHOUT bidder-led-trick-1 should award **NO sweep bonus** (just a normal failed-bid scoring; defenders take handTotal as qaid). Current code still awards **+250/+220** — categorically wrong; this is not a Reverse-Kaboot scenario at all per authority, but the current code can't tell.

**Wiring requirement (for the eventual code change — NOT applied here):**
1. Add `K.AL_KABOOT_REVERSE = 88` to Constants.lua.
2. Track `S.s.firstLeaderSeat` (or equivalent) and persist trick-1 leader at trick-1 resolution.
3. Replace the blind `if sweepTeam then` with three distinct branches:
   - `sweepTeam == bidderTeam`: regular Kaboot — bonus = `K.AL_KABOOT_HOKM`/`K.AL_KABOOT_SUN`.
   - `sweepTeam == defenderTeam AND firstLeaderSeat == bidder`: Reverse-Kaboot — bonus = `K.AL_KABOOT_REVERSE` (88).
   - `sweepTeam == defenderTeam AND firstLeaderSeat ≠ bidder`: NOT a sweep-bonus event; fall through to the standard failed-bid branch (defenders take handTotal qaid; no extra sweep bonus).

**Confidence:** Very high. The +88 figure is verbatim line-1 of the clip. The bidder-led-trick-1 gate is reinforced four times across the clip with an explicit disqualifying counter-example.

---

### Q8 — Score-broadcast field — does the wire need a flag?

**Authority says nothing about wire-protocol** (this is a 1-minute oral rule explainer; no protocol commentary). Reasoning is pure architectural inference from authority + current code:

**Inference (NOT verbatim from video):**
- The host computes the round score in `R.ScoreRound` and broadcasts it. If the host's `R.ScoreRound` correctly distinguishes regular-Kaboot (250/220) vs Reverse-Kaboot (88) vs no-sweep, the wire can carry just the **score** (cardA/cardB) — clients don't need to re-derive the type.
- BUT — the existing code path in Rules.lua:817-822 awards the SAME bonus magnitude regardless of which team swept, which means the wire today carries a wrong number for Reverse-Kaboot rounds. Fixing the host to compute the right number is **necessary**; whether the wire ALSO needs an explicit `kabootKind` flag depends on whether clients want to display "Reverse Kaboot" labelling distinctly from "Kaboot."
- **Recommendation:** if the UI shows "Kaboot!" / "Reverse Kaboot!" banners, an explicit type flag on the score broadcast is helpful; if the UI only shows the numeric score, the host's correct computation is sufficient.

**Verdict for the question as asked:** The wire does **NOT inherently** need a new flag — the score number alone, computed correctly, suffices for legality and total-tracking. A `kabootKind` enum (`"none" | "regular" | "reverse"`) is **optional** and only justified by UI labelling needs.

**Authority-source caveat:** Video #16 contains zero protocol/wire/networking commentary. This Q8 answer is architectural inference, NOT a verbatim authority finding. Mark as **Low confidence — inferred, not authority-quoted**.

**Confidence:** Low (no authority anchor; pure architectural reasoning).

---

## Cross-reference to Phase 1 / existing extracted notes

The previously distilled note at `docs/strategy/_transcripts/16_reverse_kaboot_extracted.md` (re-read for this audit) gets two corrections from this Phase 2 re-extraction:

| Phase 1 claim | Phase 2 verdict |
|---|---|
| Trigger predicate `firstLeaderOfRound == S.s.contract.bidder` (already correct in the table at line 47) | **Confirmed.** The Phase 1 distilled note **does** correctly say "the bidder must be the trick-1 leader (and then loses every trick). Defenders sweep 'from under' the bidder's lead." — line 24 of the existing extracted MD. The "bidder TEAM" framing came from the question-prompt wording, not from the Phase 1 distillate. The distillate was right; the question framing was wrong. |
| Phase 1 disputed sub-condition: "winnerCardOfTrick1 != Ace" (line 49) | **Speaker actually endorses the looser view** — the distillate notes this at line 32 ("speaker endorses the looser view"). Confirmed: do NOT gate on Ace. |
| Constant proposal: `K.AL_KABOOT_REVERSE = 88` (Phase 1 line 75) | **Confirmed.** Authority says 88 raw. The "or, per the disputed view, = K.AL_KABOOT_HOKM/SUN" alternative IS attested in the speaker's account but is the minority view; default should be 88. |
| Single-source caveat (Phase 1 §5) | Still applicable. Recommend cross-checking against any future transcript that mentions "كبوت مقلوب" or "كبوت معكوس" before final wiring. |

---

## Confidence + sourcing notes

- **Single source:** Video #16 only. No cross-corroboration in this audit.
- **Length caveat:** the source is a 1-minute oral micro-explainer — small surface area, but speaker is precise and uses repetition (the bidder-personally requirement is reinforced 3× with a counter-example).
- **Open ambiguities** still requiring corroboration:
  1. **Score:** 88 (primary) vs equal-to-regular-Kaboot (minority). Speaker uses 88 throughout post-headline.
  2. **Hokm vs Sun applicability:** the single example uses Sun; the rule statement is contract-agnostic.
  3. **Bidder-lead-card identity:** the speaker's example has the bidder leading the AKA, but his normative statement says "any card other than the AKA" — likely refers to the catching card, not the lead card. Worth a follow-up transcript to disambiguate.
- **Per the task:** no code modified. This is a transcript-only re-extraction.

---

## Rule count: 4 authority-attested rules (1 score constant, 1 lead-position gate, 1 sweep-completeness gate, 1 contract-team-attribution rule). New constants required: 1 (`K.AL_KABOOT_REVERSE = 88`). Bug-confirmations: 2 (Bug 1 magnitude, Bug 2 gate-missing) at Rules.lua:817-822.
