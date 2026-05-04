# 39 — Cut & Deal Basics (Extracted)

**Source:** كيف تقص وتوزع في البلوت للمبتدئين | 3 | (Cut & deal basics)
**URL:** https://www.youtube.com/watch?v=JjAORlFvyEI
**Slug:** 39_cut_deal_basics
**Topic:** Procedural — pre-bid table mechanics for cutting (القص) and dealing (التوزيع).

> **WHEREDNGN scope note:** dealing is automated server-side
> (`Net.lua` host shuffles + distributes). Most rules below
> describe physical-table conventions and have **no code mapping**.
> They are recorded for completeness and to flag any procedural
> rule that *does* surface (e.g., who deals next round, the buyer's
> bottom-card receipt pattern).

---

## 1. Overview

The video is the third in a beginner series. Topic: who cuts, how
to cut (القص), and how to deal (التوزيع) in physical Saudi Baloot.
Author explicitly says watch videos #1 and #2 first for context.

Sequence covered:

1. Who deals first (first session vs subsequent sessions).
2. Asking the left-hand seat to cut (لازم تسال اللي على يسارك).
3. Forms (أشكال) the cut may take — six listed.
4. Forfeiting the cut ("روح").
5. The deal pattern: 3-3-2 counter-clockwise + bottom card flipped
   for the bid-target indicator.
6. After someone buys (شال صن أو حكم), the buyer's deal-out
   pattern: buyer takes the flipped card + 2, others get 3 each
   for a final hand of 8.

---

## 2. Decision rules extracted

| # | Rule | Trigger / phase | Action | Source line(s) |
|---|---|---|---|---|
| R1 | **First-ever session: dealer is arbitrary.** Pick by lot (قرعه) or any agreed method. | Pre-bid, very first deal of a sitting | Any seat may take the deck | 11–12 |
| R2 | **Subsequent sessions: the losing team deals first.** "النازل هو اللي يوزع" — the team that just dropped (lost the previous match) deals. The losers are called "the new team / the going-down team" (الفريق الجديد / النازل). | Pre-bid, after a completed match | Loser-side seat takes the dealer role | 13–17 |
| R3 | **Dealer MUST ask the left-hand seat to cut** before dealing. The seat to the dealer's left is the cutter. | Pre-bid, immediately before deal | Dealer says "قص" to left-seat | 19–22 |
| R4 | **The cut has multiple legal forms (أشكال).** Cutter chooses one of: (a) lift a chunk and place it in the middle; (b) take the bottom card and flip it; (c) split the deck and recombine; (d) "shuffle-once / khabsah" — one-time mix, sometimes capped at three (ثلاثه); (e) take the bottom 2 or 3 cards; (f) hand 2 or 3 bottom cards to a teammate (يعطيها خويه). | During cut | Cutter performs any one form | 23–37 |
| R5 | **Cut MUST come from the bottom only.** Taking from the top is forbidden ("ممنوع ياخذ من فوق بس من تحت"). | During cut | Block top-take cuts | 35 |
| R6 | **Cutter may decline the cut by saying "روح" (go ahead) or tapping the deck.** No cut performed; dealer proceeds. | During cut | Cut waived | 39–40 |
| R7 | **If dealer forgets to ask and starts dealing, cut is forfeited.** The cutter's complaint after dealing began ("من وين ما سالتني") is too late — "خلاص سعيد التوزيع" (the deal is already underway). Equivalent rule: silence after deal-start = consent. | Pre-bid → mid-deal transition | Deal stands, no redeal | 42–44 |
| R8 | **Deal direction: counter-clockwise, starting from dealer's RIGHT** ("عكس عقارب الساعه من اليمين"). The right-hand seat has priority (الأولويه في الشرع / الأفضليه). | During deal | Distribution order: right → across → left → dealer | 46–48 |
| R9 | **Standard deal pattern: 3-3-2** — three cards each on the first pass, three cards each on the second pass, two cards each on the third pass. Last card of pass-3 is flipped face-up as the bid-target indicator. | During deal | 8 cards per seat, last card visible | 49–54 |
| R10 | **Variant deal pattern: 2-3-3 (or 3-2-3)** — also accepted at some tables ("بعدين ثلاثه ثلاثه" → "اثنين اثنين زي كذا يعكسها يعني بعدين ثلاثه"). Some sittings forbid the variant; others allow it. House rule. | During deal | Pass counts may swap; total still 8 each | 55–59 |
| R11 | **The flipped bottom card is mandatory** ("ورقه مكشوفه لازم ضروري") — every deal must end with one face-up card visible on the deck. This is what bidders evaluate / buy on. | During deal | Last dealt card placed face-up | 53, 71 |
| R12 | **No peeking** — looking at any other seat's cards (partner OR opponent) during the deal is forbidden ("ممنوع تشوف ورقه اللي ضدك ولا خويك"). | During / after deal | Each seat sees only own hand | 61–63 |
| R13 | **5-card prebid sub-hand:** before any seat may "buy" (declare a bid), each must hold exactly 5 cards. The bid window opens after the 5-card sub-deal. *(This implies bidding-table format where 5 are dealt first, bid resolved, then 3 more dealt — distinct from R9. Speaker switches mid-explanation; both formats may co-exist regionally.)* | Pre-bid | 5 cards visible to each seat at decision time | 63–66 |
| R14 | **If cutter cut "from the bottom-N", the deal starts from the seat AFTER the cutter** — not from dealer's right. Counter-clockwise continues from there. | During deal (post-bottom-cut) | Skip the cutter's normal first card, start one seat further | 67–70, 72–77 |
| R15 | **Buyer's draw pattern (post-bid):** the seat that bought the bid (Hokm or Sun) takes the flipped face-up card PLUS 2 from the deck (total 3); every other seat takes 3 from the deck. Final hand: 8 cards each. | Post-bid, before play | Buyer: flipped + 2; others: 3 | 79–87 |

---

## 3. New terms encountered

| Arabic | Pronunciation | Meaning | Already in glossary? | Recommended action |
|---|---|---|---|---|
| القص | al-qass | "the cut" — pre-deal mixing/splitting operation | NO | Add row to glossary "Other strategy idioms" — phase term, no code mapping (server auto-shuffles) |
| التوزيع | at-tawzeeʕ | "the deal" — distributing cards to seats | NO | Add row — phase term, maps loosely to host-side `Net.HostDeal` (no per-rule mapping) |
| النازل | an-naazil | "the going-down (team)" — losing team of previous match, dealer of next | NO | Add row — meta-game role term |
| خبص / خبصها / خبيصه | khabbas / khabsah | "to mix / one-time shuffle" (cut variant) | NO | Add row — cut sub-form |
| لخبط | lakhbat | "to mess up" — colloquial for shuffle | NO | Add row — synonym for خبص |
| روح | rooḥ | "go (ahead)" — verbal cut-decline | NO | Add row — cut-waiver token |
| الأولويه / الأفضليه (في الشرع) | al-awlawiyyah / al-afḍaliyyah (fish-sharʕ) | "priority / precedence (by convention)" — refers to dealer's right-hand seat receiving cards first | NO | Add row — dealer-rotation idiom |
| ورقه مكشوفه | waraqah makshoofah | "face-up card" — the bid-target indicator left visible after the deal | NO | Add row — refers to host-side concept; in WHEREDNGN this is the `S.s.flippedCard` / bid-indicator field |
| شال (صن / حكم) | shaal (sun / hokm) | "(he) lifted / picked up (Sun / Hokm)" — colloquial verb for "bought the bid" / "took the contract" | partial — bidding doc uses "win the bid" | Add row — variant verb for bid-acceptance |

**Total new terms: 9.**

---

## 4. Procedural-rule discrepancies vs `saudi-rules.md` / code

> WHEREDNGN auto-deals server-side, so most of these flag for
> *informational* completeness only. None require code changes.

| # | Rule from video | WHEREDNGN status | Discrepancy? | Action |
|---|---|---|---|---|
| D1 | R1 — first-session dealer chosen by lot | Server picks dealer arbitrarily (host-side seed) | **No discrepancy** — both are equivalent at the table abstraction level | None |
| D2 | R2 — losing team deals next match | Need to verify: does `Net.lua` rotate the dealer to the loser team after a match-end? Or does it just rotate counter-clockwise irrespective of result? | **POTENTIAL DISCREPANCY** — flag for `Net.HostStartRound` audit | Investigate `Net.lua` dealer-selection on round/match end. If it just rotates, the loser-deals rule is missing |
| D3 | R3, R4, R5, R6, R7 — physical cut mechanics (six forms, bottom-only, "روح" decline, forfeit-on-skip) | Server auto-shuffles using RNG; no human cut | **No discrepancy** — RNG shuffle subsumes cut entirely. Kasho (`saudi-rules.md` §penalty) procedurally handles mis-cut errors at physical tables; not relevant server-side | None |
| D4 | R8 — counter-clockwise from dealer's right | Existing convention: server deals counter-clockwise. Confirm the starting seat is dealer's right (not dealer-then-clockwise) | **Likely match, verify** | Quick audit of `Net.HostDeal` to confirm starting seat |
| D5 | R9, R10 — 3-3-2 (or 2-3-3) deal pattern | Server deals 8 cards per seat in a single batch (presumably) | **No discrepancy** — final hand is identical (8 each); the pass-pattern is purely cosmetic at physical tables | None |
| D6 | R11 — flipped face-up bid-target card | Server has a `flippedCard` / bid-indicator concept (used during bidding to color the seat's UI). Verify it's exposed to all 4 seats (visible) | **Likely match, verify** | Confirm bid indicator UI shows flipped card to all seats |
| D7 | R12 — no peeking | Network model never broadcasts opponent hands; trivially enforced | **No discrepancy** | None |
| D8 | R13 — 5-card pre-bid sub-hand (bidding format) | WHEREDNGN deals all 8 first, then opens bid window. **The video's 5-then-3 format is a different bidding ritual.** | **DISCREPANCY** — but the speaker's own description is internally inconsistent (he says "5 cards before buying" then describes 8-card deal complete before play). Likely a regional/older variant not used in code | Document but do not change code; full-8-then-bid is the modern Saudi norm and matches `Rules.lua` |
| D9 | R14 — bottom-cut shifts deal start one seat | Irrelevant server-side (no cut) | **No discrepancy** | None |
| D10 | R15 — buyer takes flipped card + 2 + others get 3 | If WHEREDNGN deals all 8 in one shot pre-bid, then post-bid there's no second-deal phase. The buyer simply has 8 cards. | **Format mismatch** — server collapses R9+R15 into a single deal. Functionally equivalent (8 cards per seat). Flagged because the flipped card's role differs: in physical play it physically migrates to the buyer's hand; in WHEREDNGN it's the bid-color indicator that doesn't need to physically move | Confirm UX: if server dealt the flipped card to a seat already, buying behavior is implicit |

**Highest-priority audit:** **D2** (does the loser team deal next
match?). This is the only rule with player-facing consequence that
might not be implemented. Quick `Net.lua` audit recommended.

**Second priority:** **D6** (verify `flippedCard` is visible to all
4 seats during bid window — relevant UX, not legality).

---

## 5. Code-mapping summary

This video produces **zero new code rules** for `Bot.lua` /
`Rules.lua` — all content is procedural pre-bid mechanics.
Server-side auto-dealing handles everything legally relevant.

**Glossary additions** (9 terms in §3) are the only doc change
recommended from this transcript.

**Audit items for `Net.lua` (not changes — just verifications):**

1. **Dealer rotation on match end** — does it follow the
   "loser team deals next" rule? (D2)
2. **Counter-clockwise deal start seat** — is it dealer's right?
   (D4)
3. **Flipped bid-indicator visibility** — exposed to all 4 seats?
   (D6)

If all three audits pass, this transcript is fully informational
and no code work is required.

---

**Sources:** transcript lines 1–91, this video only.
**Cross-refs:** none (first procedural-only video extracted).
