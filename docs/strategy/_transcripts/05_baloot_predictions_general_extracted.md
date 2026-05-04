# Extracted from 05_baloot_predictions_general
**Video:** التوقعات في البلوت بشكل عام | 8
**URL:** https://www.youtube.com/watch?v=vkY55gg-39k

> Episode 8 of a series; assumes prior episodes (#1–#7) on basic
> play, "expectation of حل/التكبير/التصغير", etc. The whole video is
> a flat tutorial on **how to deduce missing card locations from a
> single observed trick** — first in Sun, then in Hokm. The reasoning
> patterns are mostly **off-trump-suit reads** (suit-A Sun) plus a
> short **trump-count exhaustion** segment for Hokm. The narrator
> repeats one drill: "8 cards in a suit; given what you've seen, where
> are the rest?"

---

## 1. Decision rules

### Section 11 — Reads / partner-style inference (M3lm+ tier)

All rules below assume **Saudi Baloot** terminology. Cards in code:
J=Walad (الولد), 9=Tessah, A=Aas (الأكَه/Ace), T=Ashra (العشرة/Ten),
K=Shayeb (الشايب/King), Q=Bint (البنت/Queen), 8/7=low. The narrator
uses "ولد" for J of any suit, "اكَه" for the Ace led on trick-1.

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | NOTES |
|---|---|---|---|---|---|
| Sun. Trick 1: I lead an Ace (الأكَه) of suit X. Opponent O1 follows with a low card (e.g. 7), partner with T (Ten/العشرة), opponent O2 with Walad (J). | **Ten is OUT** — locate remaining high cards (Shayeb, Bint, 9, 8) among the three other seats by exclusion. | After A+T+J shown, the remaining high cards in suit X must be split between the two opponents and partner; tracking which is now mandatory. | `Bot._memory[seat].played[card]` (Bot.lua:271) writes are already done; **read site** is `pickLead`/`pickFollow` outranked-card calc (not yet wired for explicit "where is the T" tracking). | Definite | Drill repeated 4× in transcript with role swaps. |
| Sun. Opponent O1 (next-to-act) plays the **King (Shayeb/الشايب)** under partner's Ten (or any higher card). | Infer: O1 has **NO card lower than King in suit X**, except possibly the J(Walad)/Q(Bint). RULE in transcript: "if he had a smaller one he would have played it." | Saudi convention: under a higher card you've already lost to, dump your second-highest, never your lowest — losing-side discard discipline (this is the **inverse-laddering** read). | `pickFollow` discard policy + reverse inference in `BotMaster.PickPlay` sampler when constraining O1's hand; (read not yet wired). | Common | Narrator gives ~95%/90% confidence numbers — "this opp 95% has no smaller; that opp 90%". |
| Sun. Opponent O1 plays the **Bint (Q)** while higher cards in suit X are still missing. | Infer: O1 has **NO card lower than Q in suit X** (no J, 9, 8, 7). They held Q + possibly Shayeb + possibly Ten only. | Same losing-side dump-highest convention applied at the Q rung. | Sampler hand-reconstruction; (not yet wired as explicit constraint). | Common | Mentioned briefly during walkthrough of "if he played Bint…". |
| Sun. Opponent O1 plays a **Ten (T/العشرة)** in 2nd position when partner has not yet played. | Slight downgrade of confidence vs the "next-to-act" case: O1 is acting in **non-final position** with a high card, which is *occasionally* a deception/holdup play, **but**: still treat as ~90% indicating no card lower in suit X. | Explicit narrator hedge — "the last-to-act might play T even with a smaller, to grab the trick or set up a recall, but mostly it's the same read." | `Bot.OnPlayObserved` could fork on (#trickPlays at observation time); position-2 vs position-4 confidence weights. | Sometimes | Narrator says "I'll explain that case in a separate clip." Not yet ledger-tracked. |
| Sun. Partner plays the **Ten (T/العشرة)** while my Ace held the trick. | Infer: partner is **almost certainly with the Shayeb (K)** of that suit. | "Pass partner the next-card-down" Saudi convention: when not blocked, partner signals top-of-touching-honors — they wouldn't play T unless the Shayeb is also theirs (they'd play next-down instead). Generalized: partner's played-card implies **the touching-higher-rank card** is in partner's hand. | Existing Tahreeb/AKA framework (signals.md); strengthens `pickFollow` partner-supply assumption. New ledger key suggestion: `Bot._partnerStyle[partner].toptouchSignal` increment. | Definite | Stated as "أصول البلوت" (rule of thumb) — "if partner played T, K must be with partner." |
| Sun. Partner plays the **Shayeb (K)** under my Ace. | Infer: partner has **the Bint (Q)** (next-down-touching). | Same touching-honors signaling as above, one rung down. | Same as above. | Definite | Direct quote. |
| Sun. Partner plays the **Bint (Q)** under my Ace. | Infer: partner has **the Walad (J)** of that suit (next-down). | Same touching-honors convention. | Same. | Definite | Symmetric continuation. |
| Sun. Partner plays the lowest card they could (e.g. 7 or 8) under my winning lead. | Infer: partner is **broke in that suit's high cards** — the high cards (T, K, Q, J) are split between the two opponents. NEVER assume the unseen high is partner's. | Inverse of the "touching honors" signal — playing low signals nothing higher. | `pickLead` "is partner safe to lead into" gate; sampler should not allocate suit-X high cards to partner if partner played low. | Common | Drill: with O1=J, O2=8, partner=low → partner has neither T nor K in suit X. |
| Sun. Suit X seen 4 times (1 trick fully played, all of mine + the trick's 3 opps). I hold {9,8} of suit X. Remaining unseen: {T, K, Q}. | **Default split: assign each of the three remaining high cards to a different one of the three other seats** (one card each). Override only when partner-touching-honor signal contradicts. | Probabilistic baseline — 3 cards into 3 hands is most-likely-uniform; override on signal evidence. | ISMCTS sampler default-uniform allocation (BotMaster sampler hand pin logic). Aligns with H-1 J/9-pin discipline but extended to suit-X off-trump. | Common | Narrator: "best to give one card to each, unless evidence says otherwise." |
| Sun. After a trick where O1 played a 7 and O2 played an 8 of suit X, with several mid-rank cards still unseen. | Among (O1, O2): **the seat that played the LOWER card (here O1) is more likely to hold MORE cards in suit X** (the longer/stronger holding). | Players holding length-and-strength dump their lowest first; the higher-of-two-low plays signals shorter-or-touching. | Sampler weighting: bias unseen-suit-X count toward seat that played lower. (Not yet wired; could become a per-suit "lengthSignal" counter.) | Common | Stated as a probability prior, not a hard rule. |
| Sun. Partner played a low card (e.g. 8) with NO Aces in trick history (no `أبناط` — no high cards yet shown), and I hold the Ace. | Slight upward correction: partner **may still have the Ten (T)** (intentional hold-back, "smuggling" / تهريب) — small probability bump from ~0% to ~10%. As partner's played card gets lower (e.g. 7), this probability increases further. | Tahreeb / under-leading: partner can hold T but play low if they want me to keep tempo. Without partner playing a highish card, no certainty about T's location. | Tahreeb section in `signals.md` and decision-trees.md Section 8 (Tahreeb). Partner-style ledger could expand with `tahreebSuspect[suit]` increment when partner plays rank-7/8 and suit's high cards are still out. | Sometimes | Narrator gives explicit numeric hedge: "0% or 1% goes up to maybe 10%". |
| Sun. Trick-1 lead is **AKA (إكَهْ)** — i.e. the Ace called as AKA. If next-to-act partner plays the Ten (T/العشرة) in response. | Infer: that partner has the **King (الشايب)** of that suit. | AKA-call response signaling — same touching-honors logic but elevated by the AKA semantics (signaling is mandatory, not optional). | `Bot.PickAKA` (Bot.lua:1686) + `pickFollow` AKA-receiver convention (signals.md). Confirms the Saudi AKA-receiver protocol: partner plays-through-touching-honors. | Common | One-line summary in transcript: "if AKA was led and partner played T, partner has K." |
| Hokm. Trick 1: I lead trump (e.g. **Walad/J of trump**). O1 follows with 8 of trump. | Infer about O1: probably **HAS NO trump LOWER than 8** (i.e., does not hold the 7 of trump, since they'd have played the 7 instead) **AND** likely **DOES hold something HIGHER than 8** (else they'd have nothing). | Hokm losing-side dump-lowest convention: under a winning trump lead, you spend your **lowest** trump, not your second-lowest. **Inverse of the Sun rule** — Sun off-suit dumps are highest-of-losers; Hokm trump dumps are lowest-of-losers. | `pickFollow` Hokm-trump-follow branch; sampler reads trump distribution. Already partially captured by `Bot._memory[seat].void[trump]` writes when seat doesn't follow. New constraint: **on follow, the played rank is a lower bound on what they don't hold below**. | Definite | Saudi rule explicitly stated: "if O1 had the 7 he'd have played the 7." |
| Hokm. Partner cuts my (own) lead with **Shayeb (K) of trump** (when 9 of trump + Ten of trump still unseen). | Infer: partner does **NOT hold the 9 of trump**, and **NOT hold the Ten of trump** at the time of cut. (Touching-honors-down convention still applies; partner would have played the highest of touching honors that suffices.) | Partner uses minimum-sufficient over-trump; cutting at K when 9/T were available means they lacked 9/T. | Sampler trump-allocation: when partner cuts at K, mark partner's trump-9 and trump-T as **unlikely** (stronger than `void`, weaker than absent). | Common | Narrator: "if he had T, he would have played it [as the cut]." |
| Hokm. Trump count: 4 trumps already shown across visible plays. I hold 1 trump. | Compute: **3 trumps remaining** in the hidden hands of O1, O2, partner. Default: split 1-1-1, but adjust based on each seat's visible play tendencies (see next row). | Trump-counting is fundamental in Hokm; narrator says "this is critical to track 8 cards of trump constantly." | Existing `Bot._memory[seat].void[trump]` (Bot.lua:282-292) plus a **new counter** for trumps-played-by-seat. The sampler's J/9-pin logic (H-1) is a special case of this. | Definite | Repeated emphasis. |
| Hokm. Trump count: 5 trumps shown, 3 remaining in hidden hands. I hold 0 of those. Partner has 0 (they were void on a prior trump trick). | All **3 remaining trumps are in the same opponent's hand** (mathematically forced). | Pigeonhole. The narrator works through a 5-shown / 3-remaining example explicitly. | Sampler: when constraints force all remaining trump to one seat, hand-pin them (extension of H-1 pinning beyond just J/9). | Definite | Explicit worked example. |
| Hokm. Opponent plays a high trump (e.g. T) in 2nd position into my Walad (J) lead. | Slight downgrade vs Sun: this opp likely has **fewer trumps remaining** (just spent a high one that wasn't forced). Decreases trump-count belief for that seat. | "If they had more trumps, they'd dump their lowest, not their highest." Saudi inverse-of-Sun convention again. | Sampler weighting: seat that plays a **higher-than-required** trump is short on trump. New ledger key suggestion: `Bot._partnerStyle[seat].trumpHighDump` to count over-spends. | Common | Narrator contrasts this with the dump-lowest case. |
| Any contract. Partner plays a card and I am NOT yet winning the trick (i.e. an opponent played higher before partner). | Inverse of touching-honors: partner is now **forced** to discard, so their played card carries **no signal** about touching-higher cards. Treat as informationless beyond suit-following. | Touching-honors signaling assumes partner had a choice to support a winning lead. If we're losing, partner is just following legally. | `pickFollow` partner-supply branch: gate the touching-honors inference on `S.s.trick.winnerSeatSoFar == myTeamSeat`. (Logic likely already implicit but should be made explicit.) | Definite | Narrator caveat: "this only applies when YOU are taking the trick" (i.e., the winning side). |
| Any contract. A seat (incl. partner) plays the **smallest unseen card** of its suit. | Read: that seat is **likely SHORT** in the suit; bias the sampler toward fewer cards-in-suit for them. (Inverse of Sun length-signal: low-as-followup signals length, low-as-no-choice signals shortness.) | Distinction from earlier rule: in a trick where the seat ALREADY had higher cards available (legal alternatives), playing the smallest is the conservation move = length. Where they had no higher available, smallest is just default = shortness. | Sampler suit-length priors based on play history. Combine with existing `void[suit]` boolean. | Sometimes | Implicit; teased rather than stated; flagged for completion. |

---

## 2. New terms encountered

| Arabic | Transliteration | Translation / Meaning | Notes for glossary |
|---|---|---|---|
| التوقع | tawaqqu' | "Prediction" / "expectation" — used as the umbrella term for inferring opponent/partner card locations | Add to glossary as a strategy concept; the whole video series category. |
| التكبير والتصغير | takbeer wa-tasgheer | "Magnification and miniaturization" — narrator's prior episode title; refers to **playing-up vs playing-down** discipline (when to spend a high card vs save it). Adjacent concept to the inverse-of-Sun rule above. | Probable synonym (or precursor) to the dump-highest / dump-lowest convention. Worth tagging. |
| الأكَه | al-akah / al-akeh | The **Ace led on trick 1** (or under AKA semantics). Same Arabic root as `K.MSG_AKA`. Narrator uses it interchangeably with "Ace led" rather than the `إكَهْ` signal exclusively. | Already in glossary as AKA. Confirm: "AKA call" and "leading the Ace" overlap colloquially. |
| الشركه (الشريف?) | shareek? sharif? | Heard once in the Hokm section: "تسعه الشركه" — likely a colloquial slip for "9 of trump" (الحكم) rather than a separate term. Audio-typo candidate. | NOT a real new term; flag transcript noise. |
| أبناط | abnat | Used negatively: "ما في أبناط" — "no high cards [yet visible]". Literally "no Aces/face-cards have been spent yet." | Add to glossary: short-form expression for "the high cards in this suit are still unseen." Used in tahreeb-detection reasoning. |
| مشروع شراء / مشروع خمسين | mashroo' shira'a / mashroo' khamsin | "Project of buying" / "project of fifty" — refers to a **POTENTIAL meld** (a sequence/Tierce/Quarte). Narrator uses it as: "if the seat had T-9-8 they'd have a project for 50 (Quarte)." Used as a counterfactual to constrain hand allocations. | Add to glossary: code mapping `K.MELD_SEQ4` (=50) when narrator says "مشروع خمسين"; "مشروع شراء" is the generic concept. Useful for Fzloky meld-aware reads. |
| كاصول البلوت | ka-asool al-baloot | "As [a matter of] Baloot's foundations / fundamentals" — phrase the narrator uses to mark a non-mechanical convention (touching-honors signaling). | Style marker only; not a glossary term per se. |

---

## 3. Contradictions

None directly contradicting prior transcripts within this file alone.

**Cross-file flag (for the master contradictions log):**

- The Hokm "dump LOWEST trump" rule for losing-side follow contradicts the Sun "dump HIGHEST off-suit" rule for losing-side follow. This is **not** an internal contradiction — it's the explicit rule. Worth a row in `decision-trees.md` Section 4 to cement: **off-suit losers dump high; trump losers dump low.** Confirm with Saudi source.
- The "partner plays T → has K" inference (Sun touching-honors) is *one rung down* from how it is described in `signals.md` for AKA receiver convention, but it generalizes the AKA convention to the non-AKA Sun trick-1-Ace lead. This is not a contradiction; it's a **generalization**.

---

## 4. Non-rule observations

- The narrator opens by saying this is **episode 8** in a series and prerequisites include "method of play" and the **takbeer/tasgheer** episode. The "predictions" topic is treated as the natural next-step after one knows when to play big vs small.
- The whole pedagogical structure is a *single drill repeated*: 8 cards in a suit; 4 of yours + 1 trick observed = 5 known; 3 remaining; place them. He repeats this drill in:
  1. Sun, with leader's Ace held.
  2. Sun, with mid-rank (Ten, King, Queen) plays as the inference seed.
  3. Hokm, with trump-suit pile reasoning.
- Final line: "you have to **practice** — play a lot, you'll get this wrong at first, then it'll become bedi'i (instinctive)." Encoded learning advice — supports the **`Bot._partnerStyle` ledger accumulating across games**, not just one round.
- Final caveat: "your partner has to also be a `lo3eb` (decent player) for these reads to work — predictions presume good convention adherence on both sides." This suggests **per-partner trust calibration** as an unwired feature; `Bot._partnerStyle[partner].conventionAdherence` could downgrade rule confidence when partner has historically violated touching-honors.

---

## 5. Quality notes

- Audio is clean; transcript is auto-generated Arabic with a few typos (e.g. `هتفك`, `سبيد` as a stand-in for the suit at hand). Treated as readable.
- Narrator does not name a specific suit consistently; "السبيد / السميت" is used as a generic stand-in for "this suit" rather than specifically Spades. Reads accordingly.
- No explicit timestamps; rules are extracted in the order the narrator presents them. The Sun section is roughly the first 60-65% of the transcript; the Hokm section is the rest.
- **Confidence summary:** of 18 rules extracted, 5 are `Definite`, 9 are `Common`, 4 are `Sometimes`. The Sun → Hokm asymmetry (highest-vs-lowest dump) is the most load-bearing, single-shot insight from this video.
- The transcript ends abruptly with a "thanks for watching" — no episode-9 teaser is given.
