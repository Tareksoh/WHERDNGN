# 35_swa_term_detailed — extracted

**Source:** https://www.youtube.com/watch?v=IMJIrhW4qOA
**Title:** شرح مصطلح سوا في البلوت بالتفصيل (SWA term detailed)
**Speaker:** Energy / انرجي
**Topic:** Definitive walkthrough of سوا (SWA) — preconditions, sub-types (يد / يدين), شرح (explain) requirement, card-count thresholds, permission flow, and تكويش (Takweesh / قيد) failure cases.

---

## 1. Decision rules

### Section 7 — Endgame / SWA (`Bot.PickSWA` Bot.lua:2120)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| You hold the largest remaining cards across all live suits AND lead is on your hand (or you can force lead via void) | Eligible to declare سوا (SWA يد) — throw cards face-up with "سوا". | Definition: SWA = "all remaining tricks are mine, no point playing one-by-one." | `Bot.PickSWA` Bot.lua:2120 — eligibility predicate must check (a) you own top-live in every suit you hold and (b) leadership is reachable. | Definite | 35 |
| Lead is NOT on your hand AND opponent leads a suit you HAVE | Wait your turn (or play your card immediately) — eligibility unchanged: you still own top-live cards. | "ما تستنى دورك ممكن عادي ترمي الورق". Order doesn't matter; ownership of top-live cards does. | `Bot.PickSWA` Bot.lua:2120. | Definite | 35 |
| Lead is NOT on your hand AND opponent leads a suit you DON'T hold | NOT eligible for SWA — can't avoid following with non-top card. | You can't guarantee winning that trick. | `Bot.PickSWA` Bot.lua:2120 must verify suit-coverage of all live leads. | Definite | 35 |
| Hokm contract; your hand is all-trump (every remaining card is a حكم) AND you own the top live trump | Eligible for سوا regardless of whose lead — anyone forced to follow your trump leads loses. | Trump dominates; lead-direction irrelevant. | `Bot.PickSWA` Bot.lua:2120 — special-case all-trump hand. | Definite | 35 |
| Hokm; you hold top-live trump + side-suit cards but only the trump matters (e.g. حكمين + a side T) | Eligible for سوا — top trumps win, side card rides the auto-claim. | Same logic; trump strength carries the claim. | `Bot.PickSWA` Bot.lua:2120. | Definite | 35 |
| Your remaining cards are NOT the literal A/T/K/Q (e.g. you hold بنت+ولد of a suit, partner has burned A and T) | Still eligible — "اكبر الورق" means largest LIVE, not absolute. Q+J wins if A+T are dead. | "مش شرط يكون الورق اللي عندك في اك وعشره". | `Bot.PickSWA` Bot.lua:2120 — must compute against live-card pool, not absolute rank. | Definite | 35 |
| You declare SWA, BUT an opponent holds same-suit cards where the smallest opponent card > your smallest card in that suit | MUST شرح (explain) the SWA — play cards one-at-a-time in correct order, NOT face-up dump. | If you dump out of order, opp legally captures with their higher small card → تكويش / قيد. Example: you hold ولد+8+7 of سبيت, opp has تسعه. Dump face-up = قيد because if you played 7 first opp's 9 wins it. Correct order: ولد then 8 then 7. | `Bot.PickSWA` Bot.lua:2120 — when opp same-suit-cards exist with a higher-than-yours-min card, force ordered-play mode. | Definite | 35 |
| You declare SWA and no opponent holds any card of any of your suits (clean board) | NO شرح needed — face-up dump legal. | Trivial monopoly. | `Bot.PickSWA` Bot.lua:2120 — "needs explanation" returns false when opp suit-coverage is empty. | Definite | 35 |
| You're considering سوا يدين (two-handed SWA — partner holds top, you hold 2nd-top) | MUST be 100% certain partner owns the absolute top of the relevant suit AND you own the strict 2nd-largest of THAT suit. | If you hold 8 of the suit instead of K, and partner plays A, opp's K eats your 8 → SWA fails → قيد. | `Bot.PickSWA` Bot.lua:2120 — two-handed branch must verify "I hold rank-2 and partner holds rank-1" per suit, not just "we hold top two". | Definite | 35 |
| سوا يدين in Sun; partner holds A of suit X, you hold K of suit X (i.e. you ARE rank-2) | Eligible for سوا يدين in suit X. MUST شرح. Order: play your K, partner plays A (or vice versa), then dump remaining. | You guarantee 1st-and-2nd trick of that suit. شرح required because mid-step opp could capture. | `Bot.PickSWA` Bot.lua:2120 two-handed Sun branch with ordered-play mode. | Definite | 35 |
| سوا يدين in Hokm; you propose two-handed claim | Partner MUST hold (a) at least one trump AND (b) be void/مقطوع in at least one of your held side-suits so they can ruff when you lead it. | Without a partner ruff path, two-handed Hokm SWA is unsound. | `Bot.PickSWA` Bot.lua:2120 Hokm two-handed branch — verify partner-trump-count ≥ 1 AND partner-void-in-some-suit-you-hold. | Definite | 35 |
| سوا يدين in Hokm; you lead a side suit, partner ruffs with trump, you own top trump elsewhere | Valid SWA path. شرح required. Example: lead سبيت → partner cuts with حكم → you reclaim lead → dump remaining trumps. | Partner-as-ruffer mechanism. | `Bot.PickSWA` Bot.lua:2120. | Definite | 35 |
| سوا يدين Hokm; partner cannot ruff (no trump or has matching side-suit cards i.e. مجاوب) | NOT eligible for partner-ruff route — but ELIGIBLE if partner has matching long suit (مجاوب) that lets you alternate side-suit leads. | Two valid مجاوب shapes: (a) partner has trump + voids; (b) partner is مجاوب in your side suit AND owns the top there. | `Bot.PickSWA` Bot.lua:2120. | Definite | 35 |
| ≤3 cards remaining in hand | SWA can be declared without permission — instant claim once eligibility shown. | Saudi convention; codebase already encodes via implicit `K.SWA_TIMEOUT_SEC`=5 path. | `Bot.PickSWA` Bot.lua:2120; matches existing `Net.HostResolveSWA`. | Definite | 35 + saudi-rules.md |
| Exactly 4 cards remaining; "this جلسة allows 4-card SWA" convention | Permission still required — must تستاذن (ask). Some جلسات auto-permit, others demand explicit ask. | "في جلسات يسمحون عادي تساوي اربع اوراق". Variable by table convention. | `Bot.PickSWA` Bot.lua:2120 + Net SWA_REQ — already gated on opponent ACK. | Definite | 35 |
| 5+ cards remaining (or any "early SWA" including from-the-deal full-8 SWA) | MUST تستاذن (ask permission). Cannot auto-declare. | "لازم تستاذن من باب الاحترام". | `Bot.PickSWA` Bot.lua:2120 → emit `K.MSG_SWA_REQ`, await ACK with `K.SWA_TIMEOUT_SEC`=5. | Definite | 35 |
| Opponent receives SWA permission request | Opponent MAY deny — even if SWA is provably valid. Denial reasons: hope claimer mistakes (forgets meld, plays dead) → opp scores قيد. | "ممكن هو يكون عارف انه انت عندك سوا … لكن هو ما يخليك تساوي ليش ممكن يقول خلينا نلعب". | `Bot.PickSWA` Bot.lua:2120 — bot-receiver should NOT auto-accept when bot-side denial is heuristically valuable; current code auto-accepts (per glossary). FUTURE: M3lm+ bots could deny if claimer's prior round had any meld/play errors. | Common | 35 |
| Bot is opponent receiving SWA-REQ; current code auto-accepts | Acceptable default behavior — no meta-game read in code. Can stay as-is for v0.5.x; SWA-deny logic is M3lm+ tier opportunity. | Honesty default; matches glossary note "Bots auto-accept opponent SWA requests". | `Net.HostResolveSWA` / `MaybeRunBot` SWA branch (Net.lua:~3535). | Definite | 35 + glossary.md |
| Hokm; opp side has حكم برا (trump still outside your+partner hands); claimer asks for SWA without شرح | Opps SHOULD قيد (call تكويش) — outside trump can ruff a side lead, breaking SWA. | "في حكم برا اللعب وهذا معه مقطوع" → opp ruffs your side lead, captures the trick. | Defender bot logic — heuristic: deny SWA-REQ when Hokm AND outside-trump-count ≥ 1 AND claimer's side-suit hand is non-empty. `(not yet wired)`. | Common | 35 |
| Hokm; outside trump exists BUT partner is مجاوب in claimer's suit (matching cards including top) | Claim is recoverable — مجاوب partner blocks the ruff path. SWA legal. | Partner's matching suit absorbs the lead before opp can ruff. | `Bot.PickSWA` Bot.lua:2120 Hokm-with-outside-trump branch — check مجاوب partner override. | Common | 35 |
| Hokm; you hold كاره (Carré of T or higher) + one extra side card; opp may have مثلوث (3-card holding incl. شايب) | Do NOT declare SWA — opp's شايب beats your side card after you lead off-trump. | Specific failure example: you hold A+T+Q + a لكه, opp has شايب+two-of-suit, you lead → opp شايب captures eventually. | `Bot.PickSWA` Bot.lua:2120 — "extra side card" SWA rejection when opp can hold مثلوث-with-K. | Common | 35 |
| You declared SWA WITHOUT شرح but situation actually required شرح | Opp is entitled to قيد (Takweesh penalty). | Burden of proof on claimer. | Net SWA flow + Takweesh handlers. Already wired via `K.MSG_TAKWEESH`. | Definite | 35 |
| 8-card SWA from initial deal (ultra-rare: 4 Aces + 4 Tens type) | تستاذن mandatory — no جلسة auto-permits 8-card SWA. Without permission, opp guaranteed قيد. | "ورق زي كذا مفجر مستحيل يمشونه فرصه لهم انهم يقيدوا عليك". | `Bot.PickSWA` Bot.lua:2120 — full-hand SWA path always emits SWA_REQ. | Definite | 35 |
| You hold the cards but opp is observably watching for any error (will not auto-accept early SWA) | If opp denies, fall back to ordered ordinary play; do NOT attempt face-up dump. | Once denied, try to play cleanly card-by-card; SWA is forfeited. | `Bot.PickSWA` Bot.lua:2120 fallback path on deny. | Definite | 35 |

---

## 2. New terms (none new — all reinforce existing)

| Arabic | Pronunciation | Meaning | Maps to |
|---|---|---|---|
| سوا يد | swa yad | "one-handed SWA" — single player owns all top-live cards. | Sub-type of `K.MSG_SWA`. |
| سوا يدين | swa yadeen | "two-handed SWA" — claim relies on partner holding the absolute top while you hold rank-2. | Sub-type of `K.MSG_SWA`; needs explicit partner-coordination check. |
| شرح السوا | sharḥ as-swa | "explaining SWA" — playing cards in proper order so ownership is verifiable, vs face-up dump. | Ordered-play mode inside `Bot.PickSWA` Bot.lua:2120. |
| قيد | qaid | The penalty applied when SWA is wrong / unauthorized. Synonym for Takweesh outcome. | Already noted as open question in glossary.md; this video confirms common usage. Tied to `K.MSG_TAKWEESH_OUT`. |
| مجاوب | mujaawib | "matching" — partner who has cards in the same side-suit as you, especially top card. Required for some سوا يدين in Hokm. | Partner-side-suit-coverage predicate in `Bot.PickSWA` Bot.lua:2120. |
| مقطوع | maqṭuuʕ | "cut / void in a suit". Required for partner-ruff في سوا يدين Hokm. | Partner-void-suit predicate. |
| مثلوث | mathlooth | "tripled" — 3-card same-suit holding, especially K+two-others. Common SWA-killer when claimer has only A+T+side. | Hand-shape recognition in opponent-modeling. |
| تستاذن | tasta'dhin | "asking permission" — required for 5+-card SWA and any early SWA. | `K.MSG_SWA_REQ` emit point. |
| جلسة | jalsa | "session / table" — house-rule unit. Different جلسات allow 3, 4, or strict-3-only SWA card thresholds. | Configurable threshold (currently fixed in `Bot.PickSWA` Bot.lua:2120 — could become a setting). |

---

## 3. Card examples / hand shapes

- **سوا يد (Sun) baseline:** 3 cards left, you hold A+T+K of one suit, lead is on your hand → throw face-up.
- **سوا يد with non-A top:** بنت + ولد + 8 of one suit while A and T are dead → still SWA. Ranks are LIVE-relative.
- **سوا يد two-suit:** Q (لال) + T of one suit + A of another → SWA if no opp holds higher live cards in either.
- **سوا يد three-suit:** شايب + لال + ولد + 8 (your 8 ≥ opp's smallest in that suit, but opp has تسعه): NOT clean SWA → MUST شرح by playing largest first (شايب → لال → ولد → 8 last).
- **شرح example:** Hand has ولد + 8 + 7 of سبيت; opp has 9 of سبيت. If you lay face-up, opp تسعه captures your 7 → قيد. Correct: lead ولد (eats opp 9), then 8 (uncontested), then 7.
- **سوا يدين Sun valid:** You hold K (شايب) of ديمن; partner holds A (الإكه) of ديمن (you've seen partner play other ديمن). شرح: play your K → partner plays A → both dump remaining; opp can never beat the pair.
- **سوا يدين Sun INVALID:** You hold 8 of ديمن instead of K; partner has A; opp could hold K → opp K eats your 8 after partner's A is gone. → قيد.
- **سوا يدين Hokm valid:** You hold top trump + side suit X; partner holds 1+ trump and is مقطوع in some suit Y you hold. Plan: lead Y → partner ruffs → you reclaim → dump trumps.
- **سوا يدين Hokm via مجاوب:** Partner has matching side-suit (e.g. ديمن) including the top. Plan: lead ديمن → partner overtakes with their higher ديمن → you reclaim with trump.
- **8-card from-deal SWA:** 4 A + 4 T = "400 project + 100 project + كبوت setup" — fantastically rare, MUST تستاذن.
- **SWA-killer (مثلوث trap) Hokm:** You hold كاره + 1 extra (e.g. A+T+Q+ a لكه), opp has شايب of لكه + 2 لكه's. After you exhaust top 3, your spare لكه walks into opp شايب → fail.
- **Hokm حكم برا killer:** Lead off-trump while opp has trump + is void in your suit → opp ruffs.

---

## 4. Probabilities (sub-100% certainty)

Speaker frames SWA as **certainty-or-bust** — there is no probabilistic "70% confident SWA" in this video. Either:
- All conditions verifiably hold → declare (after شرح-decision logic).
- ANY condition uncertain → don't declare; play normally.

The probabilistic content is on the **opponent (receiver) side**: when opp gets a SWA-REQ, they reason about *whether the claimer will execute correctly*, not about whether the claim is mathematically sound. Opp denies precisely when they think the claimer might:
- forget a meld (e.g. مشروع 100 / 400) and not announce it,
- play out of order under pressure,
- mis-show a Belote / sequence,

… in which case denying forces ordered play and gives opp a chance to تكويش on a procedural error. So the denial-rate is correlated with claimer's perceived skill.

This is M3lm+/Fzloky-tier opponent modeling: **bot-as-receiver could deny SWA based on `Bot._partnerStyle[claimer].errorRate`** (proposed new ledger key). Current code auto-accepts; that is fine for v0.5.x but is an explicit upgrade path.

---

## 5. Non-rule observations

**SWA preconditions** — hand-state must satisfy: (1) you (or you+partner in يدين mode) own the largest remaining card of every suit you hold; (2) for any suit you DON'T hold, lead must reach you before opp can lead it; (3) in Hokm two-handed mode, partner must have a trump+void or مجاوب path letting you reclaim lead. The example A+T+K is illustrative only — speaker repeatedly stresses "أكبر الورق في اللعب" means *largest among live cards*, so بنت+ولد+8 can be SWA if A and T are dead.

**Card-count thresholds** — Speaker presents three regimes:
- **≤3 cards:** instant SWA, no permission. Matches saudi-rules.md and `K.SWA_TIMEOUT_SEC=5` codebase.
- **4 cards:** جلسة-dependent. Many tables auto-permit; strict tables require تستاذن. Bot should default to تستاذن at 4 to be safe.
- **5+ cards (incl. full-8 from deal):** ALWAYS تستاذن. No table auto-permits 5+. The 8-card SWA gets a special anecdote — "صلوا على الشهداء" — speaker has never seen one in person.
- **2 cards:** also valid SWA يدين (one card each, partner holds top, you hold 2nd) — one of speaker's late examples uses 2 cards apiece.

**Probabilistic SWA** — Speaker does NOT introduce a sub-100% confidence threshold for declaring. SWA is binary: provable or not. The probabilistic layer is opp-side denial heuristics (does opp expect claimer to err?), not claimer-side. For the bot, this means `Bot.PickSWA` should remain a deterministic eligibility check, not a probability roll.

**Permission flow** — Always tied to card-count + جلسة convention. Asking is a politeness norm even when claim is bulletproof; failing to ask on a 5+-card SWA is itself grounds for قيد regardless of claim validity. Opp ALWAYS may deny; denial is not "bad sportsmanship" — it's a strategic choice opps make when they suspect claimer will mis-execute. Current bot auto-accept is acceptable; M3lm+ tier could deny based on claimer's `errorRate` ledger.

**Failure / Takweesh** — Three distinct failure modes, each gives opp قيد:
1. **Unsound claim:** claim was mathematically wrong (e.g. opp had a higher live card you missed). → قيد.
2. **Unexplained when شرح required:** claim sound but face-up-dumped without ordering, AND opp had a small-card capture path. → قيد.
3. **Skipped permission:** 5+-card SWA without تستاذن, or 4-card SWA at a strict جلسة. → قيد even if claim itself was clean.

The Hokm-specific failure trap is the مثلوث (opp holds شايب + 2 in the suit) and حكم برا (outside trump can ruff your side leads). These are the two patterns `Bot.PickSWA` should explicitly reject in Hokm two-handed mode.

---

## Code-mapping notes for `Bot.PickSWA` Bot.lua:2120

The current SWA picker likely needs the following branches (all should be verified against the actual Bot.lua:2120 implementation before wiring):

1. **Sub-type detector:** distinguish سوا يد (one-handed) vs سوا يدين (two-handed) via partner-card-ownership reasoning.
2. **Live-rank evaluator:** determine "largest" against live-card pool, not absolute rank.
3. **Outside-suit lead check:** if any suit you don't hold is leadable by opp, fail.
4. **Hokm two-handed verifier:** require (partner-trump-count ≥ 1 AND partner-void-in-some-suit-you-hold) OR (partner مجاوب in side suit with top).
5. **مثلوث / outside-trump (حكم برا) anti-patterns:** explicit rejection on these shapes.
6. **شرح vs face-up decision:** for any opp same-suit holding where opp's smallest > your smallest in that suit, force ordered-play mode.
7. **Card-count gate:** ≤3 → emit SWA directly; 4 → جلسة-conditional تستاذن; 5+ → mandatory تستاذن via SWA_REQ + `K.SWA_TIMEOUT_SEC=5`.
8. **Receiver auto-accept** (already wired): keep current behavior; flag as M3lm+ upgrade target for opponent-modeling-based denial.
