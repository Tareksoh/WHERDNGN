# 42_play_hokm_basics — extracted rules

**Source:** QlZUX-ZEgHw_42_play_hokm_basics.ar-orig.txt
**Title:** طريقة لعب الحكم في البلوت للمبتدئين | 9 (How to play Hokm — beginners ep 9)
**URL:** https://www.youtube.com/watch?v=QlZUX-ZEgHw

This is the **Hokm-play companion** to the speaker's Sun-basics episode (video 41, referenced in the opening — "نصيحه شوف مقطع طريقه لعب الصن وبعدين تعال شوف هذا المقطع"). The author frames Hokm as "Sun + 3 extra laws" and walks beginners through each. The three laws he names are:

1. **التكبير بالحكم (Takbeer bil-Hokm)** — when the led suit is trump, you must over-raise above the highest trump on the table if able.
2. **الدق بالحكم (ad-Daqq bil-Hokm)** — when void in led non-trump suit, you must ruff with trump.
3. **الدق والتكبير بالحكم في نفس اللحظه** — combined obligation: when void in led non-trump suit AND a teammate or opponent has already ruffed below you, you must over-ruff with a higher trump.

All three are existing `Rules.lua` legality enforcements (`R.IsLegalPlay` already encodes must-follow / must-ruff / must-over-ruff). The video adds operational nuance — **two relief conditions** that legally release you from the must-ruff obligation — plus the **Belote-announcement timing** convention. Most rules here are corroborative restatements of existing Section 4 / Section 6 entries; the AKA implicit-relief and Belote-timing rules are the new additions worth flagging.

---

## Distilled rules

### R1. Hokm Takbeer — over-raise when partner-led trump and you hold a higher trump
- **WHEN:** Hokm contract; you are pos-2 / pos-3 / pos-4; the led card is trump (e.g., الثمانيه trump led); you hold a higher trump than what's on the table; **the current trick winner is an OPPONENT** (or no teammate has yet beaten the led card).
- **RULE:** You **MUST** play a trump strictly higher than the highest opponent trump on the table. "لازم تكبر بالحكم لازم تطلع فوق الثمانيه". Playing a lower trump (even a legal one) when you hold a higher one is **قيد** (Qaid penalty).
- **WHY:** Hokm legality is "must-over-trump", not just "must-follow". Failing to over-raise when capable is one of the explicit Qaid triggers (per video #36).
- **MAPS-TO:** `pickFollow` Bot.lua:1457 — already enforced by `R.IsLegalPlay` filtering. The rule is rule-correctness, not heuristic; bot already gets only legal cards.
- **CONFIDENCE:** Definite (corroborates Section 4 implicit must-over-cut; matches `saudi-rules.md` "Must over-trump" line).

### R2. Hokm Takbeer — relief when **partner is winning the trick**
- **WHEN:** R1 setup, but the current highest trump on the table belongs to **your partner** (e.g., partner played الشايب of trump and you hold التسعه — the higher trump).
- **RULE:** You are **NOT obligated** to over-raise above partner. "لو خويك لا ما تكبر عليه مش مضطر تكبر عليه". Play any legal trump — typically a small trump to preserve the higher one.
- **WHY:** Saudi convention: Takbeer is *adversarial* — only over-raise when the trump-winner-so-far is an opponent. Over-raising your own partner is wasteful Tasgheer-violation.
- **MAPS-TO:** `pickFollow` Bot.lua:1457 — must-over-trump gate must check `S.s.trick.winnerSeatSoFar` team. Currently `R.IsLegalPlay` may force over-trump even on partner-winning; **needs verification**. If the rule predicate over-trumps regardless of trick-winner, that's a rule-correctness bug.
- **CONFIDENCE:** Definite (explicit speaker carve-out, matches Section 4 row "trick-winner is CERTAIN partner → Takbeer").

### R3. Hokm Daqq (ruff) — must trump when void in led non-trump suit
- **WHEN:** Hokm; non-trump suit X is led; you are void in X; you hold at least one trump.
- **RULE:** You **MUST** play trump (ruff). Playing a non-trump discard while holding trump = **قيد عليك** (Qaid). "اذا ما عندك ورقه الارض تمام مجبر تدق بالحكم".
- **WHY:** Standard Saudi must-ruff legality.
- **MAPS-TO:** `pickFollow` Bot.lua:1457 — already enforced by `R.IsLegalPlay`.
- **CONFIDENCE:** Definite.

### R4. Hokm Daqq relief #1 — partner has called **AKA** (إكَه)
- **WHEN:** R3 setup, BUT your partner has played the highest unplayed card of led suit X **AND** announced "إكَه" (AKA) on it. The trick is now treated as "closed" (مقفوله) on partner's behalf.
- **RULE:** You are **NOT obligated** to ruff. You may legally discard any non-trump (preferred — preserves trump), or ruff if strategically desired. "اذا اككت الشريه هذه نعتبر انها خلاص في الحله مقفوله ... مش مجبر تقطع بالحكم".
- **WHY:** AKA explicitly transfers trick-winning certainty to partner — the must-ruff obligation evaporates because the trick is no longer at risk. The caller's "next-highest unplayed" claim makes their card functionally equivalent to the suit's Ace.
- **CRITICAL DISTINCTION:** Speaker is emphatic that **AKA must be VERBALLY announced**. If partner plays the highest card silently (no AKA call), the must-ruff obligation **stays in force** — discarding without ruff = Qaid. "في حاله انه ما اكك على العشره سواء نسي ولا لخبط ... انت هنا مجبر تقطع بحكم لو ما قطعت قد".
- **MAPS-TO:** `pickFollow` Bot.lua:1457 + `Bot.PickAKA` Bot.lua:1686 — receiver-side AKA-relief flag. State in `S.s.akaCalled`. **Already partially wired (H-5 from v0.5.1)** — H-5 suppresses forced-ruff when `S.s.akaCalled` is set. This rule **corroborates H-5**; no new code needed for the explicit-AKA path. The implicit-AKA case (per video #18, bare Ace lead) is a separate refinement.
- **CONFIDENCE:** Definite. Matches Section 6 row 5 (AKA receiver convention).

### R5. Hokm Daqq relief #2 — **partner is already winning** the trick (pos-4 cover-by-partner)
- **WHEN:** R3 setup; you are pos-4 (last to play); the trick has already been ruffed or won by **your partner** with a card that no remaining player can beat (you can verify because all 3 prior cards are visible).
- **RULE:** You are **NOT obligated** to ruff. Discard any non-trump card (preferred — saves trump). "اذا خويك ما كان الحله مش مضطر تقطع بالحكم".
- **WHY:** Saudi pos-4 cover convention: ruffing "for nothing" when partner already has the trick wastes a trump that could be a future winner. The must-ruff legality doesn't apply when the trick is no longer contested.
- **PARTIAL CARVE-OUT:** Speaker hedges — "ممكن تلعب التسعه ... مين ياكل خويك تمام لو لعبت الحكم انت اللي راح تاكل بالحكم". You CAN ruff even higher than partner (e.g., to "claim" the trick yourself for re-lead control), but it's not legally required, and the speaker treats it as a tempo-control choice, not a strict rule.
- **MAPS-TO:** `pickFollow` Bot.lua:1457 — pos-4-with-partner-winning relief gate. Currently the must-ruff predicate is in `R.IsLegalPlay`; **need to verify** whether it already excludes partner-winning pos-4 from the ruff requirement. If it doesn't, that's a rule-correctness item. The HEURISTIC (prefer-discard-over-ruff when already-won) belongs in `pickFollow` — `(not yet wired)`.
- **CONFIDENCE:** Definite. New rule worth adding to Section 4.

### R6. Hokm Daqq + Takbeer — combined when an opponent has already ruffed
- **WHEN:** Hokm; non-trump suit X led; **opponent** ruffed (e.g., pos-2 was void in X, played a low trump like ثمانيه trump); you are pos-3 or pos-4, also void in X, and you hold a trump higher than the opponent's ruff.
- **RULE:** You **MUST** ruff AND over-raise simultaneously. If you hold any trump higher than the opponent's, you must play it. "لازم تدق وتكبر في نفس اللحظه ... هذا لعب ثمانيه لازم تكبر فوق الثمانيه اذا لازم تلعب الشايب".
- **WHY:** This is the combined application of R1 (over-raise) and R3 (must-ruff). A low ruff under your higher available trump = Qaid.
- **MAPS-TO:** `pickFollow` Bot.lua:1457 — already enforced by `R.IsLegalPlay`'s combined must-ruff + must-over-cut predicates.
- **CONFIDENCE:** Definite. Speaker calls this the "third law of Hokm".

### R7. Daqq + Takbeer relief — applies when **opponent's** ruff is uncovered
- **WHEN:** R6 variant — opp ruffed but you are void in trump too (only have a non-trump).
- **RULE:** Free to discard. Speaker confirms: "ما عندك دائما صح يعني تقطع بحكم" — no trump = no ruff requirement.
- **MAPS-TO:** Existing legality. No new wiring.
- **CONFIDENCE:** Definite.

### R8. Daqq + Takbeer relief — applies when only your trump is **lower** than opponent's ruff
- **WHEN:** R6 variant; opponent ruffed with a high trump (e.g., الاكه trump); your only trumps are smaller (e.g., الشايب and الثمانيه — both below الاكه).
- **RULE:** **NOT obligated** to ruff. The must-over-cut predicate has no satisfying card, so the must-ruff falls back to a permissive option. You may discard any card. "هنا مش مجبر تلعب حكم ليش لانه ما عندك اعتلاء فوق الاكه ما تقدر تعتدي".
- **HEURISTIC PREFERENCE:** Speaker recommends **discarding rather than ruffing low** in this case — preserve the trump for a future attack. "خلي الحكم عندك الافضل".
- **MAPS-TO:** Legality already handled (R8 is the negative space of R6). Heuristic preference for `pickFollow` Bot.lua:1457 — if must-over-cut fails, prefer non-trump discard over a low under-ruff. **Not yet wired** as an explicit preference.
- **CONFIDENCE:** Definite (legality); Common (heuristic preference).

### R9. Belote (بلوت) announcement timing in Hokm — must follow الشايب, not precede it
- **WHEN:** Hokm; you hold both الشايب (K) and البنت (Q) of trump (a Belote-eligible holding); you are about to play one of them on a trick.
- **RULE:** Play the card silently first; **announce بلوت only after playing the second of the K-Q pair**. "ما يقول مثلا بلوت بعدين يلعب البنت ... خلاص يلعب البنت ويسكت متى يذكر البلوت بعد ما يلعب الشايب".
- **STRICT:** Announcing Belote *before* playing the Q is a procedural error (a form of pre-Bel reveal — see Bel cards-revealed lockout in saudi-rules.md). The convention sequence is: play K (silent) → play Q (silent) OR announce بلوت simultaneously → meld scored.
- **WHY:** Saudi convention preserves the Bel-window's information seal. Announcing before play would broadcast the holding before the trick context is set.
- **MAPS-TO:** Belote announcement timing is in `Bot.PickMelds` / `holdsBeloteThusFar` (referenced in glossary.md). Need to confirm announcement fires AFTER the second card play, not before. **Verification item.**
- **CONFIDENCE:** Common. Single-source but procedurally explicit.

### R10. AKA must be called **AT THE MOMENT** of leading the highest unplayed card
- **WHEN:** Hokm; non-trump suit X; you are leading; you hold the highest unplayed card of X (e.g., العشره of a side suit when الاكه is already gone).
- **RULE:** Announce "إكَه" (AKA) AT the same moment you play the card. **Late-call is invalid.** "في حاله انه ما اكك على العشره سواء نسي ولا لخبط ... هذا الاسم مثلا لخبط وقال على العشره ... هذي قيد عليه برضو".
- **WHY:** Late AKA-call retroactively reshapes the must-ruff obligation. Saudi rule: if a partner ruffed because they thought AKA wasn't called, the late call invalidates the legal frame and is a Qaid against the late-caller.
- **MAPS-TO:** `Bot.PickAKA` Bot.lua:1686 — the call must be wired to fire on the SAME `OnPlayObserved` event as the card play, not the next tick. **Verify timing in Net.lua dispatch.**
- **CONFIDENCE:** Definite. New rule worth flagging for `Bot.PickAKA` invariant.

---

## Non-rule observations

**The video's mental model — "Hokm = Sun + 3 laws":** The speaker frames Hokm as Sun-rules-plus-three-laws. This framing matches the code structure: `Bot.lua` `pickLead` and `pickFollow` share most logic between Sun and Hokm, with contract-conditioned branches at specific decision points (`contract.bidType == K.BID_HOKM` checks). The "3 laws" map cleanly to three predicate sets in `R.IsLegalPlay`:
- **Takbeer (R1)** = `mustOverTrump` predicate
- **Daqq (R3)** = `mustRuff` predicate (when void in led suit, contract is Hokm)
- **Daqq+Takbeer (R6)** = the conjunction — must-ruff AND must-over-cut

All three are already legality-enforced; the video confirms they are *learned* by Saudi players the same way: as discrete laws layered onto Sun-base rules.

**Trump rank order primer:** The speaker walks through "ولد تسعه بعدين اكه" (J → 9 → A) when teaching ordering — the standard Hokm trump order. This is the same `K.RANK_TRUMP_HOKM` ordering used in code (J=8, 9=7, A=6, T=5, K=4, Q=3, 8=2, 7=1).

**The example deal — "I dealt all 8 trumps + 1 each":** As a teaching device, the speaker gives every player **all 8 trumps** and one extra side card. This is pedagogically useful because it forces the must-ruff and over-raise scenarios to fire on every trick. Real deals concentrate trump differently; the rules apply identically but trigger less often.

**Relief conditions for must-ruff are unionized:** R4 (AKA called) and R5 (partner already winning) are **two distinct relief conditions** for the must-ruff predicate. Either suffices on its own. The AKA case is information-explicit (verbal announcement); the partner-winning case is positional (visible from cards-on-table). A third relief — "no higher trump available" (R8) — is not really a relief but the negative space of must-over-cut.

**No mention of Faranka / Tahreeb / Tanfeer:** This beginner video deliberately skips signaling conventions. It's pure rule-mechanics — the speaker explicitly defers strategy to other videos.

---

## New terms

| Term | Meaning | Note |
|---|---|---|
| **التكبير بالحكم (Takbeer bil-Hokm)** | "Magnification with trump" — the must-over-raise rule when the led suit is trump and you hold a higher trump. The trump-suit application of the general Takbeer convention. | **Already in glossary** under "Takbeer / Tasgheer (التكبير / التصغير)". This video corroborates the Hokm-trump variant. |
| **الدق بالحكم (ad-Daqq bil-Hokm)** | "Cutting/ruffing with trump" — must-ruff rule when void in led non-trump suit. | **Already in glossary** as "دق / يدق (daqq / yidiqq)" with note "Cut = trump a side suit. Trump-ruff in code terms." |
| **الدق والتكبير في نفس اللحظه** | "Daqq and Takbeer at the same moment" — combined must-ruff + must-over-cut when an opponent has already ruffed below you. | New phrasing for the *combination* of the two existing rules. Not a separate term — it's R3 ∧ R1. |
| **مقفوله (muqfala)** | "Closed" (referring to a trick after AKA is called — the trick is now sealed for partner). Also previously seen in glossary's "Bel (×2) legality gate" referring to "مقفول" under even-multiplier Hokm. | Same root, two different uses: Bel-window-closed vs. AKA-trick-closed. |
| **اربع / ربع بالحكم (arbaʕ / rabbaʕ bil-Hokm)** | "Lead with trump" — verb form for "led [a] trump card". Speaker uses "ربع بالولد" = "led the J of trump", "ربع بالثمانيه" = "led the 8 of trump". | **Already in glossary** as "ربع / يربع (rabbaʕ / yirabbaʕ)". This video confirms usage. |
| **بدون اللعب / مش مجبر** | "Not obligated to play [trump]" — speaker's phrasing for the Daqq relief conditions (R4, R5). | Conventional negation; not a term per se. |

**No genuinely new terms** — every term in the transcript is already in the glossary. This is expected for a beginner-level rule-walkthrough video; novel strategy terminology shows up in higher-level commentary (Tahreeb, Faranka, Bargiya, etc.).

---

## Decision-trees.md update notes

Section 4 (mid-trick play, `pickFollow` Bot.lua:1457) needs **two new rows** that are not currently captured:

1. **Hokm pos-4, partner already winning the trick (visible from table), you are void in led suit** → **NOT obligated to ruff; prefer discard to preserve trump.** Definite. (R5.)
   - This is distinct from existing Section 6 "AKA receiver convention" — R5 fires on positional certainty (4th card visible), not on AKA announcement. Currently `(not yet wired)` as an explicit `pickFollow` heuristic — and possibly missing from `R.IsLegalPlay` if that predicate forces ruff regardless of partner-winning.

2. **Hokm void in led suit, opponent ruffed with a trump higher than ANY trump in your hand** → **NOT obligated to ruff (must-over-cut has no satisfying card); prefer discard over a futile under-ruff.** Definite legality; Common heuristic. (R8.)
   - Legality already handled. The HEURISTIC preference (discard non-trump rather than burn a low trump) needs an explicit branch in `pickFollow` Bot.lua:1457.

Section 6 (AKA / signaling, `Bot.PickAKA` Bot.lua:1686):

3. **AKA announcement timing invariant: call must fire AT THE MOMENT of card play, not before or after.** Late-AKA = Qaid. (R10.) **Verification item** — review `Bot.PickAKA` and `Net.lua` dispatch path to confirm the announcement is bound to the same `OnPlayObserved` event as the card itself. If timing is decoupled, that's a rule-correctness bug.

Section 12 (Belote — does not yet exist; if a "melds" or "announcements" section is added):

4. **Belote announcement must follow the second card of the K-Q pair, not precede it.** (R9.) **Verification item** — `Bot.PickMelds` and `holdsBeloteThusFar` should announce on the play of the second of the pair, not on observation of the holding.

Glossary update: no new term entries needed; all glossary terms are already present. **Optional addition:** brief cross-reference under "Takbeer / Tasgheer" pointing to this video as a beginner-rule corroborator.

---

## Code-correctness items (flagged for follow-up)

- [ ] Verify `R.IsLegalPlay` must-ruff predicate excludes the **partner-winning pos-4** case (R5). If the predicate forces ruff even when partner has the trick locked, that's a rule-correctness bug.
- [ ] Verify `R.IsLegalPlay` must-over-cut predicate is a precondition (only fires when a trump beating the highest opp trump exists) — not a blanket force. R8 should fall through to discard. Likely already correct, but worth a regression check.
- [ ] Verify `Bot.PickAKA` announcement is event-coincident with the card play (R10).
- [ ] Verify `Bot.PickMelds` Belote announcement fires after the second K/Q play, not on holding-detection (R9).
- [ ] Add `pickFollow` Bot.lua:1457 heuristic: **prefer discard over low under-ruff** when must-over-cut has no satisfying card and partner is not winning. (R8 heuristic.)
- [ ] Add `pickFollow` Bot.lua:1457 heuristic: **prefer discard over ruff** when partner has already won the trick at pos-4. (R5 heuristic.)
