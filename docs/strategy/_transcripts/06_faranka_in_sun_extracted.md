# Extracted from 06_faranka_in_sun
**Video:** كيف تتفرنك في الصن
**URL:** https://www.youtube.com/watch?v=lbIAJF5Eo28

> **Note on framing:** despite the title, this video is the *conceptual* Faranka video — it defines the term, lists the three forms (Hokm-only, Hokm-with-side-suits, Sun/no-trump), enumerates the five "should I Faranka?" factors, and walks 8+ examples. It pivots heavily to the Sun-applicable form because that is where Faranka is genuinely recommended. The closing line — "we'll cover Faranka-in-Hokm in the next video" — confirms this video is paired with #4 as the Sun-side companion. Hokm-specific examples here are largely warnings ("don't Faranka in Hokm except for X").

---

## 1. Decision rules

### Section 10 — Faranka (فرنكة)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | NOTES |
|---|---|---|---|---|---|
| You are last-to-play (pos-4); partner already winning the trick with a high card (e.g. partner played J/Q-of-suit, RHO discarded low) and you hold both A and the next-highest of the led suit (e.g. A + 10, or A + K) | Faranka — duck with the smaller of your two high cards (play 10 / K), letting partner take this trick; you pick up the next trick with the A | Captures two tricks instead of one; you "fish" the opponent's 10 on the second round | `pickFollow` pos-4 branch (Bot.lua:1457) — new sub-rule | Definite | Core canonical example: "خويك لعب الولد، خصم لعب 8، أنت معك A+10، تفرنك → العب 10، ثم بعدين العب A وتاكل العشرة في الجولة الثانية" |
| Sun contract; partner is on track to sweep all 8 tricks (Al-Kaboot in progress, partner has won ≥6); your A would block partner's run if played now | Faranka — duck under partner's high card so partner keeps the lead and completes Al-Kaboot | Al-Kaboot bonus (220 raw in Sun, ×2 = 440) dominates the single-trick value | `pickLead`/`pickFollow` Al-Kaboot pursuit (Bot.lua:953 trick-8 branch + pos-4 follow) | Definite | "ثاني فائدة … انك تجيب كبوت" — explicit second listed benefit |
| Pos-4 in Sun; you hold 10 (no A); the A is known to be at LHO (the player who plays *first* in the next trick) | Do NOT Faranka — take this trick with the 10 | The 10 will not survive — LHO will lead and pull or capture it | `pickFollow` pos-4 (Bot.lua:1457) | Common | "الافضل انك ما تتفرنك … خوفك يجي عليك كبوت" pattern |
| Sun; you are pos-4 and considering Faranka; the high card you'd "release to" sits with RHO (the player who plays *before* you, just played a low card e.g. 8) | Strongest Faranka spot — duck. RHO probably holds the missing 10; partner will recapture in the next round | Three cards already on table = max information; risk is bounded | `pickFollow` pos-4 (Bot.lua:1457) | Definite | "اذا كانت عند هذا اللاعب … اعلى نسبة فرنكة" — factor 5 in the "5 factors" list |
| Sun; partner played first this trick with a high card (J/A) and trick is already going to partner | Faranka is *less attractive* — only Faranka if you also see clear Al-Kaboot pursuit | With partner leading, you have less info on the missing 10's location | `pickFollow` (Bot.lua:1457) | Common | Mid-list factor 2: when partner leads vs. when partner is in pos-3 |
| Sun; LHO led the suit (you are pos-4); LHO is on the bidding team; round is at trick 1 of a fresh hand | Faranka — even though pos-4-after-LHO-lead normally suggests grabbing the trick, the bidder leading first means they probably hold the 10 | Bidder-team-leader-of-fresh-hand is presumed to hold suit strength | `pickFollow` pos-4 (Bot.lua:1457), with bidder-team check | Sometimes | Factor 5 exception: "اذا كان راح يلعب اول واحد في الحله الجديده … معه قوه وبرضو تتوقع انه يكون معه العشره" |
| Sun; LHO led; opponents are the bidders (your team is defender) | Do NOT Faranka — take the trick to deny opponents Al-Kaboot | Defending against Al-Kaboot dominates over the +10 you might fish | `pickFollow` pos-4 defender branch (Bot.lua:1457) | Common | "حتقل نسبة الفرنك حتحاول تاكل الحلة عشان تضمن ما يجيك كبوت من الخصم" |
| You hold the *two highest* unplayed cards of the led suit (e.g. A and J after K already played) — regardless of position | NEVER Faranka — play normally to capture both tricks | If you duck, opponent's smaller high card may still take the trick because partner has nothing better | `pickFollow` (Bot.lua:1457) | Definite | "دائما اذا عندك اكبر ورقتين موجودة في اللعب لا تتفرنك ابدا سواء كنت اخر لاعب او ما كنت اخر لاعب" |
| You hold ≥3 cards of the suit in question (e.g. A, K, Q in same suit) | Do NOT Faranka — play A normally; the 10 is more likely to drop on first round because suit is concentrated in your hand | With ≤5 of the suit distributed across 3 other hands, doubleton-or-shorter 10s drop early | `pickFollow` pos-4 anti-Faranka guard (Bot.lua:1457) | Definite | "ما تترنك اذا عندك اكثر من ورقتين … العشره راح تنزل من اول حله" |
| You do NOT hold the J / second-highest of the suit (you only have A, smaller cards next) | Generally do NOT Faranka — without J as the recapture vehicle, ducking gives up control | "ما تترنك اذا ما عندك الشايب" | `pickFollow` (Bot.lua:1457) | Common | First "don't" listed: "اذا ما عندك الشايب حتبدا تخاف شويه" |
| You expect this Faranka, if successful, to *flip the game* against opponents (i.e. tracking shows opponents losing the round outright) | Faranka — extra +10 from the fished 10 lands on the team that will already lose the round | Score-the-loss-on-them logic | `pickFollow` (Bot.lua:1457), depends on score-tracking | Sometimes | Factor 4: "اذا الفرنكه هذه راح تخسر الجيم على خصمك" |
| Hokm contract; you are NOT on a side-suit (you are dealing with a trump trick) | Generally do NOT Faranka — explicit caution. Faranka in Hokm is reserved for the side-suits-only sub-form covered in video #4 | Trump tricks have over-trumping obligations and tighter must-follow rules | `pickFollow` Hokm trump branch (Bot.lua:1457) | Definite | Closing line: "لا تتفرنك في الحكم الا اذا طمعت في كبوت فقط" |

---

## 2. New terms encountered

| Arabic | Pronunciation | Meaning here | Glossary status |
|---|---|---|---|
| تجاهل | tajaahul | "ignoring" — speaker's own gloss for what Faranka mechanically *is*: deliberately not playing your highest card when you legally could | Add to glossary as plain-English definition of Faranka |
| نسبة الفرنكة | nisbat al-faranka | "Faranka percentage / probability" — the speaker's heuristic for *how strongly* the situation favors Faranka, summed from the 5 factors | Conceptual; do not add as a row but useful as code-comment |
| شايب | shayb | The Jack (J) — Saudi colloquial for "old man / patriarch", consistent with elsewhere | Already implied in `K.RANK_TRUMP_HOKM`; document in glossary card-name table |
| إكَه | ikkah / ikka | The Ace (A) — Saudi colloquial. NOT to be confused with إكَهْ (AKA, the partner-signal). Spelling differs but transcripts often elide the silent ـه | Already in glossary as a *signal* — add separate row clarifying the *card* meaning vs. the AKA signal name |
| شريف / الشريف | sharif | Also seen as "الشري" / "الشريحة" — the suit being played in the example (likely the suit-of-the-trick, possibly Hearts given common usage). Speaker is loose with this label. | Treat as colloquial, not a code term |
| تفرنك | tafarnak | Verbal-noun form of Faranka ("to perform a Faranka"). Same as الفرنكة | Glossary already has الفرنكة; note variant |

---

## 3. Contradictions

| WHEN (shared) | This video says | Other source(s) | Resolution |
|---|---|---|---|
| Faranka in Hokm | Speaker repeatedly says "don't Faranka in Hokm" except for kabout-pursuit, deferring full Hokm coverage to next video | Video #4 (Faranka in Hokm) presumably gives the full set of Hokm-side-suit cases | No contradiction — this video defers to #4 by design. Use #4 for Hokm-specific rules. |
| Pos-4 + LHO led + you hold A+10 | This video: "if LHO led, Faranka percentage *decreases* (you're not last after a partner-led trick)" — but also says "exception when LHO is bidder-team leading first trick of new hand" | None yet | The exception is genuine, not a contradiction. Encode both: a base "down-weight" plus the bidder-team override. |

---

## 4. Non-rule observations

**Faranka in Sun (فرنكة في الصن)** — Faranka is the technique of *deliberately ducking* when you legally could play your highest card of the suit, in order to hand the current trick to a teammate (or to a still-unrevealed high card) so that you keep your top card available to capture a *later* trick — typically winning two tricks and/or fishing out the opponent's 10. In Sun (no-trump, ×2 multiplier), Faranka is broadly *recommended* whenever the configuration allows, because (a) without trumps, a captured Ace/Jack reliably wins later, (b) the ×2 multiplier amplifies the +10 from a fished ten, and (c) the no-trump setting maximizes the relevance of the third benefit, Al-Kaboot pursuit (220 raw × 2 = 440 in Sun).

**Trigger conditions** — the speaker's "5 factors that *increase* Faranka percentage" (any combination — additive, no single one mandatory):
1. You hold the J of the led suit *together with* the A (J+A both in hand).
2. Partner is the player who will *take* the trick (partner is currently winning, having played first or third).
3. The current line of play is heading toward Al-Kaboot — successful Faranka maintains partner's sweep.
4. Score tracking shows Faranka-success will flip the round-loss onto the opponents.
5. The player to your **left** (LHO, who leads the *next* trick) is the *bidder* and is leading the first trick of a fresh hand (proxy for "LHO holds the missing 10").

**Anti-trigger conditions** ("don't Faranka") summarized: no J (just A + smaller); ≥3 cards of the suit in your own hand (suit is concentrated, 10 drops naturally); you hold the *two* highest unplayed (always capture); opponents are bidders and threaten Al-Kaboot against you (defend, don't experiment); Hokm contract on a trump trick (deferred to video #4).

**Difference from Faranka in Hokm** — In Sun the technique is *strategy-positive* (default "yes, Faranka when factors line up"), because:
- No trump means a held A truly recaptures any later round of the same suit; in Hokm, an opponent void in the side-suit can ruff and your saved A becomes worthless.
- The ×2 multiplier doubles the +10 you fish (effectively +20 in scored points) AND doubles every recaptured trick, so the EV of the duck goes up.
- Al-Kaboot (220 raw in Sun, ×2 = 440) is a much larger prize than in Hokm (250 raw, ×1 = 250), so the third benefit (preserving partner's sweep) is roughly twice as valuable.
- Thus the speaker's overall framing inverts: in Sun the default lean is "Faranka when factors align"; in Hokm the default lean is "don't Faranka — except in the narrow side-suit case (video #4) or when chasing kabout."

The *mechanic* (deliberately playing a smaller high card, holding back your top card) is the **same** in both contracts. What changes is the strategic prior. So the glossary entry for Faranka should describe one mechanic with two sub-doctrines rather than treating Faranka-in-Sun and Faranka-in-Hokm as different plays.

**Three forms (تقسيم)** — the speaker enumerates three structural forms of Faranka:
1. **Trump-only Faranka** in Hokm (covered video #4).
2. **Trump-with-side-suit Faranka** in Hokm (the three non-trump suits) — covered video #4.
3. **No-trump Faranka in Sun** — same as form #2 mechanically because in Sun no card is trump; this is the focus of the present video.

This is a useful structural decomposition for code: the *Sun branch* of `pickFollow` reuses the same predicates as the *Hokm side-suit branch*, with the additional Sun-specific triggers (×2 EV, Al-Kaboot prize bigger).

**Three benefits of Faranka (the "why")** explicitly enumerated by the speaker, in order: (a) win two tricks instead of one; (b) preserve partner's Al-Kaboot run; (c) *fish* the opponent's 10. All three are amplified in Sun.

---

## 5. Quality notes

- **Transcript quality:** moderate. Auto-generated Arabic, frequent transcription errors (الشريط / الشريف / الشريحة all clearly mean *"the led suit"*; تكويش/تفرنك slips; الايكا for العكا). Consonant-stem reasoning is reliable; precise card identities in some examples are ambiguous.
- **Card naming consistency:** the speaker uses شايب=J, إكَه=A, بنت=Q, ولد=K, ثمانية=8, سبعة=7. The "10" is left as العشرة. These match standard Saudi Baloot colloquial. No surprises.
- **Coverage gap:** the video promises but defers full Hokm coverage to video #4. Cross-reference video #4 extraction for trump-Faranka rules.
- **Confidence calibration:** the 5-factor framework is presented confidently and clearly with worked examples; rated Definite/Common. The "LHO-bidder-leading-fresh-hand" override is presented as a single example and is rated Sometimes pending corroboration.
- **Rules-vs-conventions:** all observations are *play-decision* heuristics (no rule-correctness claims). Nothing in this transcript contradicts `Rules.lua`.
- **Term to add to glossary:** the *card* meaning of إكَه (Ace) is distinct from the *signal* meaning of إكَهْ (AKA partner-call). Glossary should disambiguate; current single row mixes both.
