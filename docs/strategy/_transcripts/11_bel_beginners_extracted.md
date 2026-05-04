# Extracted from 11_bel_beginners
**Video:** شرح الدبل في البلوت للمبتدئين | 11 |
**URL:** https://www.youtube.com/watch?v=21fN1IEm5Xk

## 1. Decision rules

### Section 2 — Escalation (`Bot.PickDouble` 1787, `PickTriple` 1908, `PickFour` 1938, `PickGahwa` 1982)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | NOTES |
|---|---|---|---|---|---|
| Bidding just resolved (Hokm or Sun); you are on the **defender** team; the bidder team has not yet revealed/picked-up cards | Bel (بل / الدبل) window is open — defender may call Bel to ×2. | Final score multiplied by 2 — only stake-raising opportunity for defenders before play starts. | `Bot.PickDouble` (Bot.lua:1787); `K.MULT_BEL`=2; `K.BOT_BEL_TH`=60. | Definite | Speaker: "هذا الفريق ممكن يقول دبل" — defender-only window. |
| Bel window timing — any defender-team player has already **revealed/picked-up their cards** (كشف الورق) | **Bel is FORBIDDEN** — window closed. | House-rule: revealing cards locks out Bel calls. Strictest variant: any of the 4 players revealing cards locks it; common variant: only defender-team reveal locks it. | `Bot.PickDouble` Bot.lua:1787 — gate check `(not yet wired)`. Needs new state flag `S.s.cardsRevealedBy[seat]`. | Common | Speaker: "اذا كشفت الورق خلاص وما قلت دبل ممنوع تدبل." Variant noted. |
| Bel window timing — typical session timeout | ~5 seconds to declare Bel after bid lands. | Standard pace-of-play in physical sessions. | UI / Net.lua escalation-window timer; bot picker should fire within window. | Common | Speaker: "ممكن عندكم خمسه ثواني على حسب الجلسات." |
| Bel x2 / Four / Gahwa — chain ordering after Hokm | Strictly alternating: defender Bel → bidder team **Bel x2 (×3)** → defender **Four (×4)** → bidder team **Gahwa (152 = match-win)**. Chain in Hokm only (Sun is shorter). | Each rung is voluntary; opposite team's window after each. | `Bot.PickTriple` 1908 / `PickFour` 1938 / `PickGahwa` 1982. Already encoded. | Definite | Confirms saudi-rules.md chain. Speaker: "اللي راح يفوز في هذه السكه راح يفوز في الجيم كامل." Saudi term for ×3 here = "ثري" (English loan). |
| You bid **Hokm** and opponents called Bel (or Bel was followed by Bel x2 / Four — i.e. any **even** rung is the active multiplier: ×2 or ×4) | Play in **closed mode** (مقفول) — **no trump-leading** allowed except as last card in hand. | Bel/Four imposes "closed" Hokm by default in many sessions: nobody may open with a trump unless they have only trump cards left. | New `pickLead` Bot.lua:953 trump-lead gate, conditional on `S.s.contract.multiplier ∈ {2, 4}` AND `S.s.contract.bidType == K.BID_HOKM` AND session-house-rule flag `(not yet wired)`. | Common | Speaker: "الاعداد الزوجيه الدبل تضرب في اثنين والفور في اربعه... اللعب راح يكون مقفول... ما يربع بحكم." This is a **rules / legality** delta — flag for Rules.lua review, not just bot heuristic. House-rule variant: some sessions play "open" instead. |
| Hokm at ×3 (Bel x2 / "ثري") or unmultiplied or Gahwa | Play **open** (مفتوح) — normal trump-lead rules. | Odd-multiplier rungs do NOT impose the closed-trump restriction. | `pickLead` Bot.lua:953 — default branch. | Common | Speaker: "الثري... قهوه هذا لعب مفتوح." |
| Bel (or higher) is active in **Hokm**; mid-round, a player asks "ايش الحكم؟" (what's trump?) and another player answers (names the trump) | The answering player commits a **qaid** (penalty) — house rule. | Some sessions enforce silent-trump under Bel; speaking the trump's name penalizes the speaker. | Out-of-scope for bot picker (player-only chat behavior). Document in `saudi-rules.md` under "house rules". | Sometimes | Speaker: "تقيد عليك في بعض الجلسات." Variant rule. |
| Bel/Four called on the very first round of the match (score still 0–0) | Some sessions FORBID this — anti-griefing rule against deliberately torpedoing fresh games. | Prevents a sore-loser from one-shot-killing the match via Gahwa straight after the opening bid. | `Bot.PickDouble` / `PickGahwa` — house-rule gate `(not yet wired)`. Bot should default to NOT calling Bel/Gahwa on round 1 of fresh match. | Sometimes | Speaker: "بعض الجلسات تمنع هذا الشيء." Beginner-friendly default. |
| You are on a team with score **≥ 100** raw and the contract is **Sun** | **Bel is FORBIDDEN** — your team cannot Bel a Sun bid. | Saudi anti-runaway rule: a team already at ≥100 may not double the Sun stake. Lower-scoring team retains the right. | `Bot.PickDouble` Bot.lua:1787 — gate on `S.s.contract.bidType == K.BID_SUN AND R.TeamScore(myTeam) >= 100` `(not yet wired)`. | Definite | Key constraint. Speaker: "في الصن لازم يكون فريق 100 نقطه او اعلى والفريق الثاني يكون اقل من 100 نقطه... الفريق اللي اقل من 100 لوحه حقيقيه يدبل لكن الفريق اللي فوق الميه ما يدبل في الصن." |
| You are on a team with score **< 100** and your opponents are **≥ 100**; contract is **Sun** | You **may** Bel — your right is preserved (the score-asymmetry guard only blocks the leading team). | Sun-Bel is a comeback tool; only the leading team is blocked. | Same gate as above — inversion of the condition. | Definite | Same source. |
| Both teams **< 100** OR both **≥ 100**; contract is **Sun** | Speaker does not specify clearly. **Treat as: only the < 100 team may Bel.** Default safe interpretation. | Speaker frames the rule as "lower-than-100 team Bels"; symmetric cases left unspoken. | `Bot.PickDouble` Sun gate — conservative interpretation `(not yet wired)`. | Sometimes | Open question — flag for follow-up source. |
| Contract is **Hokm** at any team-score state | **No score asymmetry rule** — Bel is open regardless of either team's score. | Speaker explicit: Hokm Bel rights are independent of score, unlike Sun. | `Bot.PickDouble` Hokm branch — no score gate. | Definite | Speaker: "بعكس الحكم. الحكم مفتوح في الدبل سواء كنت اعلى من 100 او اقل." |
| Contract is **Sun**; Bel was called | **Stake caps at ×2 by default in Sun** — many sessions disallow Bel x2 / Four / Gahwa on Sun. Some sessions allow them. | Sun is already ×2 from contract multiplier; further escalation is variant-dependent. | `Bot.PickTriple` / `PickFour` / `PickGahwa` Sun-branch gate `(not yet wired)`. Default: skip when contract is Sun. | Common | Speaker: "الصن ما في قهوه وفي بعض الجلسات ما يلعبون [الفور/الثري]... يخلون بس خلاص دبل يعني تظرف اثنين فقط." |

## 2. New terms encountered

| Arabic | Pronunciation | Meaning | Notes |
|---|---|---|---|
| **الدبل** | *ad-dabl* | "The double" — Bel (×2 escalation rung). | English loan-word "double". Speaker uses الدبل throughout; canonical Saudi name in our docs is **بل (Bel)**. Add to glossary as alias for `K.MSG_BEL`. |
| **ثري** | *thari* (English "three") | Bel x2 / ×3 escalation. | English loan-word "three". Note: glossary.md currently states "Saudi players don't say ثري for this rung" — **this video contradicts that note.** Speaker uses ثري explicitly. Glossary should be updated: ثري IS used colloquially, alongside "الدبل الدبل" (double-the-double). |
| **فور** | *for* (English "four") | Four / ×4 escalation. | English loan-word, confirms saudi-rules.md. Also: "الدبل الدبل" used as synonym for Four. |
| **القهوه** | *al-gahwa* | Gahwa / coffee / match-win. | Already in glossary. Speaker confirms: "النتيجه 152 اللي راح يفوز في هذه السكه راح يفوز في الجيم كامل" — Gahwa = full-match win, treat as 152 points. |
| **الصكه** | *as-sakkah* | "The round / hand". | Synonym for *trick-set / round*. Likely related to existing dialect words for hand. Add to glossary idioms. |
| **الجلسه** | *al-jalsah* | "The session" — i.e. a played-game-instance with its own house rules. | Speaker repeatedly says "على حسب الجلسه" = "depends on the session/table". Captures that house rules vary table-to-table. |
| **اللعب مقفول / مفتوح** | *al-laʕb maqfool / maftooh* | "Closed play / open play" — refers to whether trump-leading is restricted. | Closed (مقفول) = no trump-lead under ×2/×4 in Hokm; open (مفتوح) = normal. Add as gameplay-mode constants. |
| **يربع بحكم** | *yirabbaʕ bi-hokm* | "To lead with trump (the H of trump)". | Already partially in glossary as "ربع/يربع" = lead. Confirms verb form. |
| **يقد** | *yiqid* | "To follow / to play in turn". | Speaker: "يقد عليه ما يربع بحكم" = "plays after them, doesn't trump-lead". Add to glossary. |
| **تقيد عليك** | *tiqaayyad ʕalayk* | "Penalty applied against you" (a qaid). | Confirms qaid terminology already flagged in glossary "open questions". |
| **تخرب اللعب** | *tikharrib al-laʕb* | "Spoiling the game" — anti-griefing context. | Used to justify the round-1 Bel/Gahwa ban. |

## 3. Contradictions

| Topic | Source A (existing docs) | Source B (this video #11) | Resolution |
|---|---|---|---|
| Saudi name for ×3 rung (Bel x2) | glossary.md: "Saudi players don't say ثري for this rung" | This video: speaker says **ثري** explicitly multiple times ("بعد الدبل يجي 3 او الدبل برضو يسمى عادي لكن انت عشان تفرق سميها 3"). | **Update glossary.md** — ثري IS in colloquial use as a disambiguation tool. Also "الدبل الدبل" used. Both are legitimate Saudi terms. |
| Sun escalation chain | saudi-rules.md describes full chain Bel→Bel x2→Four→Gahwa as Saudi-canonical | This video: in Sun, "بس خلاص دبل... ما في قهوه وفي بعض الجلسات ما يلعبون [الثري/الفور]" — chain often **caps at Bel** in Sun. | Both correct; saudi-rules.md describes the Hokm chain. Add a Sun-specific note: chain typically caps at ×2 in Sun, with variant allowing the full chain. |
| Closed-trump under Bel/Four | Not currently documented in saudi-rules.md or decision-trees.md | This video: under ×2/×4 in Hokm, **no trump-leading allowed unless trump-only-in-hand** | New rule — add to saudi-rules.md (legality / Rules.lua delta) and decision-trees.md Section 2/3. |

## 4. Non-rule observations

**When does the speaker recommend Bel vs Pass?**

The video is a **rules-explainer**, not a strategy video. The speaker does NOT discuss hand-strength thresholds for calling Bel. He explains *what Bel is*, *who can call it*, *when the window opens/closes*, and *the score asymmetry rule for Sun*. There is **no threshold** mentioned — no "Bel if you have X points / Y trumps / Z high cards". The bot's existing `K.BOT_BEL_TH=60` threshold is **not corroborated or contradicted** by this video.

**How does context (score, bidder identity) affect the decision?**

- **Bidder identity:** Speaker is unambiguous — only the **defender team** can call Bel. The bidder team responds with Bel x2 if Bel is called against them. Strict alternation.
- **Score (Sun-specific):** The ≥100 / <100 score asymmetry is a **rule constraint**, not a heuristic — a team at ≥100 *cannot legally* Bel a Sun bid. This is a legality rule that Rules.lua should enforce (currently appears unmodeled).
- **Score (Hokm):** No score-based gating; Bel always available within window.
- **Round-of-match:** Some sessions disallow Bel/Gahwa on round 1 (anti-grief). Bot default should respect this for beginner-friendly play.

**Strength threshold:** The video does NOT establish one. Speaker treats Bel as a tactical lever rather than a strength-gated decision. Decision-trees.md Section 2 still needs threshold rules from a different (more strategic) video.

**Tone of video:** Beginner-explainer. Speaker celebrates 1k subscribers, hopes for 10k. This is a *rules-of-the-game* tutorial — invaluable for filling the legality / window-rules gaps but does not provide hand-evaluation heuristics.

## 5. Quality notes

- **Transcript quality:** Auto-generated Arabic captions; minor word-form drift but content clear throughout.
- **Confidence signals strong:** Speaker is methodical (numbered explanation: type → name → trigger → variation), gives explicit *or* clauses for house variants, says "على حسب الجلسه" repeatedly to flag local variation. High trust.
- **Single-source caveat:** This is the FIRST video to source Section 2 — most rules above are necessarily `Sometimes` to `Common`. Definite ratings reserved for items with explicit rule structure (the Sun ≥100 score guard, the alternation, Hokm no-score-asymmetry).
- **Missing:** No hand-strength thresholds. No discussion of when Bel succeeds/fails statistically. No commentary on counter-Bel x2 strategy. Need a strategic Bel video next.
- **Missing:** No discussion of Bel x2 / Four / Gahwa **strength thresholds** beyond restating "doubles the prior multiplier".
- **Code-mapping confidence:** All `MAPS-TO` references confirmed against glossary line-anchors (Bot.lua:1787, 1908, 1938, 1982). The new closed-trump gate, score-asymmetry gate, and round-1 gate are all marked `(not yet wired)` — explicit code work.
- **Potential `Rules.lua` work needed:**
  1. Score-asymmetry guard for Sun-Bel (legality).
  2. Closed-trump-lead under even-multiplier Hokm (legality if house-rule enforced).
  3. Cards-revealed lockout for Bel (legality).
  These are not bot heuristics — they are legal-play constraints. Recommend separate review.
