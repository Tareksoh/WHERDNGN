# Extraction — 29_dont_takweesh

**URL:** https://www.youtube.com/watch?v=ePJkUJu8kfg
**Title:** لا تكوِّش في البلوت 🤝 (Don't Takweesh in Baloot)
**Length:** 19 lines (short companion to video #34, Takweesh basics)
**Topic:** Anti-trigger discipline — when NOT to override partner's bid by takweeshing.

---

## Terminology disambiguation (read first)

The Arabic verb **تكويش** in this video means **"override your
partner's bid by declaring your own contract on top of it"** —
a 3rd/4th-position bid maneuver where you preempt your partner's
already-purchased contract because you hold strong cards (ورق
تكويش, "takweesh-worthy paper").

**This is NOT the same usage as `K.MSG_TAKWEESH`** (the
illegal-play call that resolves to Kasho pre-bid or Qaid
post-bid). Same Arabic root (كوش), different game phase, totally
different mechanic.

| Sense | Phase | Mechanic | Code |
|---|---|---|---|
| **Takweesh-A** (this video) | Bidding | Override partner's bid with your own stronger hand | Not currently modeled — closest existing site is `Bot.PickAshkal` (Bot.lua:725+), which is the Sun-conversion variant |
| **Takweesh-B** (videos #30/#36) | Pre-bid (Kasho) or Post-bid (Qaid) | Call illegal-play penalty | `K.MSG_TAKWEESH`, `K.MSG_TAKWEESH_OUT` |

This extraction documents Takweesh-A. The Saudi term resolves by
phase context: takweesh during bidding = override-partner; takweesh
during play = penalty-call.

> **Glossary follow-up needed:** the existing glossary entry for
> تكويش (line 95) only documents the penalty-call sense. A second
> row for the bid-override sense should be added before this rule
> is wired into `Bot.PickBid` / `Bot.PickAshkal`.

---

## Section 1 — Decision rules

### Section 1: Bidding (`Bot.PickBid` Bot.lua:725, `Bot.PickAshkal`)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Partner already bought a Hokm or Sun contract; you hold "takweesh-worthy" strong cards (ورق تكويش) | **DEFAULT: do NOT takweesh.** Let partner play their contract. | Partner doesn't know you hold the strong cards; they bid based on their own hand. Overriding usually destroys (a) partner's planned contract and (b) any "project" (مشروع) partner had from trick 1 — partner's strong Hokm or strong Sun-supply gets sabotaged. Worst-case if you DON'T takweesh: partner fails and the team eats the loss — and **no one will blame you because partner doesn't know you had the cards**. Worst-case if you DO takweesh: partner blames you for breaking their contract and any project they had. | `Bot.PickBid` (Bot.lua:725) and `Bot.PickAshkal` — needs a partner-already-bid gate. **Anti-trigger override:** even when own-hand strength alone passes the bid threshold, suppress own-bid if partner is the current contract holder, unless the single exception below fires. **Not yet wired.** | Definite | 29 |
| Partner bought **Sun** AND was visibly **hesitant** (متردد) AND it is **early in bidding** | **EXCEPTION: takweesh is acceptable.** Partner's hesitation + early-Sun = ambiguous strength signal; partner could have bid Sun on almost anything, so overriding is less destructive. | Hesitation = no concrete project to disrupt; early Sun = you're not stepping on a fully-formed plan. Only condition where the override doesn't burn partner's mشروع. | `Bot.PickBid` / `Bot.PickAshkal` exception branch. **Hesitation is observable in code only via timing or pass-then-bid hedging — Saudi-online tells like long-pause-before-bid are not currently signal-tracked.** Lacking a hesitation telemetry channel, this exception is effectively unwireable for bots; mark `(not yet wired)` with note. | Sometimes | 29 |
| You'd otherwise takweesh (partner has bid, you have strength), but partner already shows signs of a "project" (e.g. Hokm-bidder partner hand-rhythm, partner clearly committed) | **HARD anti-trigger: do NOT takweesh.** Trust partner's project; assume your hand will support it ("راح يسوقك"). | Partner's strength + your strength = combined contract is strong. Overriding cancels the synergy. Saudi conviction: "خليك واثق في ورق السياق اللي راح يجيك ولا تخرب على خويك" — be confident in the cards that will come to you in context, don't sabotage your partner. | `Bot.PickBid` partner-confidence branch — when team-mate is bidder, weight own-hand strength as **partner-supply**, not as override-justification. **Not yet wired.** | Common | 29 |

---

## Section 2 — New terms / glossary additions

| Arabic | Romanization | Meaning | Notes |
|---|---|---|---|
| **تكويش (bid-override sense)** | takweesh | Overriding your partner's bid by declaring your own contract on top — 3rd/4th-position preemption when you hold strong cards. | **Distinct from the penalty-call sense** in glossary line 95. Same root, different phase. Closest existing code site: `Bot.PickAshkal` (which is the Sun-conversion subset; full takweesh allows any contract conversion). Glossary needs a second row for this sense. |
| **ورق تكويش** | waraq takweesh | "Takweesh-worthy paper" — a hand strong enough to justify overriding partner. | Predicate-style identifier; in code terms this corresponds to `escalationStrength(seat, hand, contract)`-style scoring above some threshold (`K.BOT_TAKWEESH_TH`, not currently defined). |
| **مشروع** | mashrooʕ | "Project" — partner's plan/setup from trick 1, e.g. a strong Hokm hand with a planned ruff sequence or a strong Sun-supply structure. | Used to describe the partnership's emergent plan that takweesh would destroy. Conceptual; no direct code identifier yet. The closest analogue in code is the implicit Al-Kaboot pursuit flag (`pickLead`/`pickFollow` Kaboot-pursuit). |
| **يسوقك** | yisawwiqak | "Will drive/lead you" — i.e. partner's strong hand will pull along your supplementary cards productively. | Idiom for "your cards will fit partner's plan." |
| **متردد** | mutaraddid | "Hesitant" — descriptive of a partner who bid Sun without conviction. | The single observable signal that flips the takweesh anti-trigger to acceptable. Online play makes this hard to detect; offline play it's the pause-before-bidding tell. |

**Glossary update needed:** add `takweesh-bid` (override-partner sense) row distinct from existing `takweesh-penalty` row at line 95.

---

## Section 3 — Contradictions / cross-video

No direct contradictions with existing decision-trees.md or saudi-rules.md content. **Note** that this video's takweesh sense is the bid-override use, not the penalty-call use covered by videos #30 (Kasho/Qaid distinction) and #36 (Takweesh trigger discipline). Both senses coexist; do not collapse them.

**Possible related material in `Bot.PickAshkal`:** Ashkal is the documented 3rd/4th-position bid that converts partner's Hokm into a Sun. That is one *form* of takweesh-bid (the Hokm→Sun conversion). The general takweesh-bid in this video is broader — overriding any contract with your own strength. Confirm scope when adding the second glossary row.

---

## Section 4 — Non-rule observations

- The video is framed as a **partnership trust** lesson: when in doubt, trust your partner's read of their own cards. The blame asymmetry ("if you don't takweesh and partner fails, no one blames you; if you do takweesh and partner had a project, you get blamed") is a social-game heuristic, not a math heuristic.
- The single positive trigger ("hesitant partner + early Sun") is the inverse of the trust frame — when partner shows weak commitment, the trust default no longer applies.
- The video treats Hokm-takweesh as **strictly worse** than Sun-takweesh: the Hokm-bidder is more likely to have a concrete project from trick 1, so overriding their Hokm is the most destructive case. Sun-bidder partners are more likely to be hedging.
- This is a *short companion* to video #34 (Takweesh basics, the positive case for when TO takweesh). Together they form an inclusion/exclusion pair: #34 = triggers, #29 = anti-triggers. Cross-link when #34 is extracted.

---

## Section 5 — Quality notes

- **Length:** 19 lines, single-speaker monologue, no examples, no card-level analysis. Pure principle-statement.
- **Confidence justification:** the central anti-trigger ("don't takweesh on partner's Hokm/Sun by default") is stated emphatically and is the entire content of the video; rated **Definite** despite single-source because it's emphatic and structural (frames the whole partnership convention). The exception (hesitant + early Sun) is rated **Sometimes** — single-source, narrow, and operationally hard to detect.
- **Caption quality:** clean Arabic, no obvious ASR errors. The phrase ورق تكويش ("takweesh-worthy paper") and ورق السياق ("contextual paper" / "the cards that will come to you") are both legible.
- **Disambiguation flag:** transcript extractors should NOT collapse the two senses of تكويش. The phase context (bidding vs play) is the disambiguator. The existing glossary row at line 95 covers only the penalty-call sense; this extraction documents the bid-override sense and flags the need for a second glossary row.
- **Card-name slang:** none used. No K/Q/J/A reference; the transcript stays at the "ورق قوي / ورق تكويش" abstraction level (strong cards / takweesh-worthy cards), so the شايب=K, بنت=Q, ولد=J convention isn't exercised here.
- **Reference to `K.MSG_TAKWEESH`:** the existing constant covers the penalty-call sense from videos #30/#36. This video's mechanic is unrelated to `K.MSG_TAKWEESH`; it would need a new constant family if wired (e.g. `K.MSG_TAKWEESH_BID` / `Bot.PickTakweeshOverride`). Currently the closest wired analogue is `Bot.PickAshkal` for the Hokm→Sun-conversion subset only.
