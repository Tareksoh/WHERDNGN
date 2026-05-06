# X3: Faranka exception priorities

**Inputs:** Source C (`source_C_faranka.md`, 39 rules, videos #04 + #06).
**Code:** `Bot.lua` `pickFollow` (line 2378+); only `pickFollow` has Faranka logic — `Rules.lua` has zero Faranka references (legality-only).
**HEAD:** post-v0.9.2 (#49 fix landed).
**Scope:** Hokm exceptions F-23 to F-30, Sun 5-factor F-09 to F-13, all anti-rules F-14 to F-39.

---

## Hokm exception map (F-24 to F-30 + anti-rules)

Code lives in one block: `Bot.lua` 2761-2868. Gate: `Bot.IsM3lm() and contract.type == K.BID_HOKM and contract.trump and trick.leadSuit and #winners > 0`. Inside block: short-circuit OR over three trigger predicates, then a single post-veto.

| Source rule | Code branch | Bidder-team gate | Order | Match |
|---|---|---|---|---|
| F-23 Hokm DEFAULT = NO Faranka | structural — block default is `farankaTriggered = false` (2763); only `if farankaTriggered then return non-winner` (2842) overrides natural `winners` selection | n/a | 0 | **MATCH** |
| F-24 Exception #1 — Type 3 (side-suit only) cabotage extending Kabout sweep | **NOT WIRED** | n/a | — | **MISS — deferred** (acknowledged in audit_v0.9.0/22 line 44 and CHANGELOG; partial pickLead trick-3 sweep-pursuit at ~Bot.lua:1581-1589 but not cross-wired to pickFollow Faranka) |
| F-25 "Other than that, NEVER Faranka" (Types 1/2 hard-stop default) | structural — same as F-23, block enters only when winners exist and triggers must opt-in | n/a | 0 | **MATCH** |
| F-26 Exception #2 in Source-C ordering (Type 1, J preservation, 9-with-RHO) | **NOT WIRED** as such | — | — | **MISS** — Source-C's "F-26 = J preservation when 9 is at right-opp" is **NOT** what the code calls "Exception #2". Code's "Exception #2" is `myTrumpCount == 2` (the *weak-trump-holding* rule = Source-C **F-27**). Naming collision documented below in "Bugs found". |
| F-27 Exception #3 — Weak Hokm holding (only 2 trumps) | `Bot.lua` 2773-2783 — counts trumps in hand, gates `myTrumpCount == 2 and onBidderTeam` | **YES** (added v0.9.2 #49: `onBidderTeam = R.TeamOf(contract.bidder) == R.TeamOf(seat)`) | 1 | **MATCH** (with naming caveat — code calls this "Exception #2"; comment 2743 reads "Exception #2: we hold ONLY 2 trumps total") |
| F-28 Exception #4 — Hold 9 + redundant 10/A (Type 1 mardoofa) | partially covered by F-29 wire (when J still alive AND 9 is held with redundancy, code does NOT trigger). Code's predicate `S.HighestUnplayedRank(trump) == "9"` is satisfied **only after** J is dead — see F-29 row | n/a (Source-C frames as bidder example but rule is hand-shape only) | — | **PARTIAL MISS** — Source-C's F-28 is "9 + redundant trump while J still live" (mardoofa preservation). Code only fires the 9-related branch when J is **already dead** (= F-29). The "9 + redundant + J still live" case is **not wired**. |
| F-29 Exception #5 — Faranka with the 9 once J of trump is gone (9 = top live trump) | `Bot.lua` 2795-2804 — `S.HighestUnplayedRank(contract.trump) == "9"` AND hand-scan for 9 of trump | **NO bidder-team gate** | 2 | **MATCH on predicate**, **MISMATCH on bidder gating** — see "Bugs found" |
| F-30 Hokm Type 2 — Bidder w/ A+K of side-suit, slight Faranka favourability when (a) covet Kabout OR (b) trumps exhausted | `Bot.lua` 2807-2819 — `contract.bidder == seat` AND both opps observed-void in trump (predicate (b)). Code calls this "Exception #4" | **YES** (`contract.bidder == seat` — strict bidder, not just bidder-team) | 3 | **PARTIAL MATCH** — predicate (b) "trumps exhausted" wired; predicate (a) "covet Kabout" NOT wired (no `partner-tricks-won >= 6` check exists; CHANGELOG marks Exception #1 deferred for the same reason). Also code requires bidder == self exactly; Source-C says bidder-team is sufficient. Also lacks A+K-of-side hand-shape precondition — code fires regardless of side-suit hand. |
| F-32 Anti-rule — Don't Faranka if Hokm bought by OPPONENTS | **partially wired** via #49 fix on Exception #2 (now bidder-team-only) and via `contract.bidder == seat` strict gate on Exception #4. **NOT wired on Exception #3 (J-dead 9 branch)** | partial | post-veto | **PARTIAL** — opp-bidder still triggers Faranka through the J-dead branch |
| F-33 Worst-case meta-rule (Hokm) | `Bot.lua` 2856-2864 — non-trump-non-winner preferred (preserves trump cover) | n/a | embedded | **MATCH** (defensive selection within Faranka pool) |
| F-34/F-35/F-36 — "100% lose both, take instead, even partner-out works" (motivational/structural) | structural — embodied by default-NO posture | n/a | — | **MATCH-by-design** |
| Section-10 anti-rule "J+8 vs opp-bidder Q-led" (decision-trees.md L252; not in Source C numbering — extra rule wired) | `Bot.lua` 2822-2840 — `lead.seat == contract.bidder` + `R.TeamOf(lead.seat) ~= R.TeamOf(seat)` + `lead.rank == "Q"` + hand has J + 8 → un-trigger | gates on opp-bidder explicitly | post-veto | **MATCH** |

---

## Sun Faranka 5-factor map

Code at `Bot.lua` 2465-2494. Single branch (no factor scoring) — fires when ALL the conditions match: Sun + lastSeat + partnerWinning + bidder-team + (suitCount==2) + (hasA) + (cover ∈ {T,K}). Returns the cover card. There is **no multi-factor weighted score** — it's a single AND-gated trigger, not a 5-factor accumulator.

| Factor | Code branch | Match |
|---|---|---|
| F-09 Factor #1 — Hold the K (الشايب) of led suit | `Bot.lua` 2478-2483 — `cover ∈ {T, K}` (T or K accepted as cover); A required separately at 2477 | **PARTIAL** — code accepts T or K as cover. Source C says K is the canonical highest factor; T is a weaker substitute. T-as-cover is broader than the literal rule. **Net: works in spirit but loosens the "must hold K" framing.** |
| F-10 Factor #2 — Partner is winning the trick | `Bot.lua` 2465 — `partnerWinning` required | **MATCH** |
| F-11 Factor #3 — Round heading toward Kabout | **NOT WIRED** — no `partner-tricks-won >= 6` check; no Kabout-trajectory inference | **MISS** |
| F-12 Factor #4 — Faranka would lose game-points to opp; conditional on opp = bidders | **NOT WIRED** — no running-score projection; no "opp is bidder" inversion. Code requires our team to be bidders (line 2467); the F-12 case (opp is bidder, defender Farankas) is **structurally excluded** | **MISS** (correct on F-13 anti-rule but blocks F-12's intended fire) |
| F-13 Factor #5 — Left-opp leads next AND your team are bidders (only fires when bidder-team) | partially via the bidder-team gate at 2467 | **PARTIAL** — gate matches the bidder-team requirement of F-13, but the "left-opp will lead next trick" predicate is not modeled. Code fires for ALL pos-4 partner-winning shapes when bidder-team, not specifically the left-opp-leads-next variant. |

**Source-C says Sun Faranka is DEFAULT YES; opposite of Hokm.** Code does NOT model this as a default-yes-with-anti-rules — it's a default-no-with-narrow-trigger. The code-side conservative posture is documented as "decision-trees Section 5 (Definite, video 06)" and was approved at v0.5.21. **Discrepancy: source says yes-by-default, code is no-by-default but fires on the canonical "A+T mardoofa pos-4" shape.**

---

## Anti-rules coverage

| Anti-rule | Code branch | Match |
|---|---|---|
| F-14 Last seat + opp winning → MUST take, do NOT Faranka (transcription corrected from literal Arabic) | structural — Sun branch (2465-2494) requires `partnerWinning`, so the opp-winning case never enters the duck branch and falls through to `winners` selection. Code reads the **corrected intent** correctly (NOT the literal Arabic). | **MATCH (corrected-intent)** |
| F-15 Hold top-2 live cards of suit → NEVER Faranka | NOT explicitly wired; `suitCount == 2` + `hasA` + `cover ∈ {T,K}` gate is acknowledged at comment 2451-2454 as a **proxy** for the canonical A+T mardoofa shape. The real "top-2 live" predicate (e.g., A+K when T is dead) is not computed. | **PROXY ONLY** — covers the canonical case but a true F-15 guard requires `S.HighestUnplayedRank` + a 2nd-highest tracker. Audit `05_section5_pos4_faranka.md` row 3 confirmed NOT-WIRED at v0.7.2; unchanged at v0.10.0 |
| F-16 Don't Faranka without K of suit | partially via `cover ∈ {T,K}` — fires when cover is T (no K), so anti-rule #16 is **VIOLATED** by the proxy. Source C says without K, Faranka favourability **drops** | **MISS** — code allows T-as-cover Faranka without K |
| F-17 Don't Faranka with ≥3 cards of suit | `Bot.lua` 2491 — `suitCount == 2` strict | **MATCH** (≥3 fails the `==2` gate) |
| F-18 Don't Faranka in Hokm in general (default-NO meta-rule) | structural — Hokm Faranka block defaults `farankaTriggered = false` and requires opt-in trigger | **MATCH** |
| F-32 Don't Faranka if Hokm bought by opponents | partially — Exception "#2"/F-27 now bidder-team-gated (v0.9.2 #49); Exception "#4"/F-30 strict bidder-self gated. **Exception "#3"/F-29 (J-dead 9-branch)**: NOT bidder-team-gated → opp-bidder still triggers. | **PARTIAL** — see "Bugs found" |
| F-39 Partner pulled trick + we hold top-2 live → never Faranka | structural — `partnerWinning` already required for the duck branch; the case "partner has the trick and we hold both top cards" is the canonical case the bot *does* duck. F-39 says **don't** duck. Code's bidder-team gate doesn't help here. **F-39 = sharper version of F-15**, both partial proxies. | **MISS** — same gap as F-15 |

---

## Bidder-team membership universal application — code-side audit

Source C's high-level finding (line 398 of source_C_faranka.md):

> **Pro-Faranka triggers should be gated on bidder-team membership; anti-Faranka rules apply to all seats.**

Code-side reality:

| Branch | Pro/Anti | Bidder-team gated? | Matches expected? |
|---|---|---|---|
| Sun A+cover duck (Bot.lua 2465-2494) | pro | YES (`R.TeamOf(seat) == R.TeamOf(contract.bidder)`) | **YES** |
| Hokm Exception "#2" (myTrumpCount==2) | pro | YES (since v0.9.2 #49) | **YES** |
| Hokm Exception "#3" (J-dead, hold 9) | pro | **NO** | **NO — bug** |
| Hokm Exception "#4" (bidder + opp trump exhausted) | pro | YES (strict `contract.bidder == seat`, not just team) | **YES — possibly over-tight** (Source C only requires bidder-team, code requires bidder-self) |
| Hokm anti-rule J+8 vs opp-bidder Q-led (post-veto) | anti | n/a — fires regardless | **YES** (anti-rules are universal) |
| Sun structural anti-rules (F-14 last-seat-opp-winning) | anti | n/a — falls through to winners | **YES** |

**Net:** the bidder-team gating is consistently applied to pro-Faranka triggers EXCEPT Exception "#3" (the J-dead 9-of-trump branch). The same #49 reasoning that motivated the bidder-team gate on Exception "#2" applies here verbatim.

---

## Bugs found / missing features

### Bug 1 (carryover from v0.9.2 #49) — Exception "#3" (J-dead 9-branch) lacks bidder-team gate
- **File:** `Bot.lua` 2795-2804
- **Symptom:** When opponents bought Hokm, the J of trump has been played, and the bot holds the 9 of trump, the bot will Faranka — actively helping the opponents' contract make. This is the same class of bug v0.9.2 #49 fixed for Exception "#2".
- **Source:** F-32 (Source C) — explicitly opp-bidder = NO Faranka.
- **Severity:** medium-high. Hand-shape (J dead, we hold 9) is uncommon but not rare in late-trick play.
- **Fix sketch:** add `and onBidderTeam` to the trigger condition at line 2803.

### Bug 2 — Naming collision between code's "Exception #N" and Source-C ordering
- **File:** `Bot.lua` 2738-2868 comments (and audit memos 22, 49)
- **Symptom:** Code's comment block says `Exception #2: we hold ONLY 2 trumps total` and `Exception #4: we are the bidder AND both opponents are observed void in trump`. But Source C orders these differently: F-26 = J-preservation (NOT WIRED), F-27 = weak-trump (= code's "Exception #2"), F-28 = 9-mardoofa-with-J-live (NOT WIRED), F-29 = 9-with-J-dead (= code's "Exception #3"), F-30 = bidder + A+K-of-side / trumps-exhausted (= code's "Exception #4"). 
- **Severity:** documentation-only, but causes audit memos to mis-cite. Audit memos (#10, #22, #34, #49) all reference code's numbering, not Source C's. Future readers comparing to Source C's F-numbers will confuse the rules.
- **Fix sketch:** rename code comments to `F-27`, `F-29`, `F-30` per Source C, OR add a cross-reference table at the top of the block.

### Bug 3 — F-30 hand-shape not enforced (A+K of side-suit)
- **File:** `Bot.lua` 2807-2819
- **Symptom:** Source C F-30 requires the bidder to hold A+K of a side-suit. Code only checks `contract.bidder == seat` AND `oppTrumpExhausted`. The A+K-of-side hand-shape is not part of the predicate, so the trigger fires whenever bidder + opp-void regardless of hand. **Net effect:** code fires F-30 more aggressively than Source C says.
- **Severity:** low — opp-trump-exhausted is rare and is itself a strong condition; the false-positive rate is small.

### Bug 4 — F-30 missing predicate (a) "covet Kabout"
- **File:** `Bot.lua` 2807-2819
- **Symptom:** Source C F-30 has two disjunctive predicates: (a) covet Kabout OR (b) trumps exhausted. Code wires only (b). The Kabout pursuit branch (F-24 / Exception #1) is also NOT WIRED, so neither predicate (a) on F-30 nor F-24 is functional.
- **Severity:** medium — rare in early/mid trick play, common in late hand.

### Bug 5 — F-15 / F-39 anti-rule "top-2 live cards = NEVER Faranka" is a proxy, not a true predicate
- **File:** `Bot.lua` 2465-2494
- **Symptom:** Code uses `suitCount == 2 + hasA + cover ∈ {T,K}` as a proxy for F-15 / F-39's "we hold the two highest live cards". Edge cases where the real top-2 are e.g. A + Q (after K and T are played) are missed. Audit memo `05_section5_pos4_faranka.md` row 3 acknowledged this at v0.7.2: "hard to detect cheaply".
- **Severity:** low-medium — true F-15 / F-39 case requires `S.HighestUnplayedRank` plus a "second-highest" tracker. Existing code can be retrofitted.

### Bug 6 — F-16 anti-rule violated by T-as-cover acceptance
- **File:** `Bot.lua` 2478
- **Symptom:** Source C F-16 says: "without K, Faranka favourability drops sharply." Code accepts T as cover with no K present (`cover ∈ {T, K}`). This means a hand like {A, T} of led suit (no K) will Faranka, contradicting F-16.
- **Severity:** medium — A+T mardoofa without K is a real and not-uncommon hand-shape.

### Missing features (deferred per CHANGELOG and prior audits)

- **F-24 Hokm Exception #1** (Kabout-pursuit Type-3 cabotage): NOT WIRED. Partial pickLead sweep-pursuit logic at Bot.lua:1581-1589 but no cross-wire to pickFollow.
- **F-26 Hokm Exception #2** (Source-C numbering — Type 1 J preservation when 9 is with right-opp): NOT WIRED. Requires seat-order-aware "9 location" reasoning.
- **F-28 Hokm Exception #4** (Source-C numbering — 9 + redundant trump WHILE J still live): NOT WIRED. Code only fires once J is dead (= F-29 branch).
- **F-31 Hokm Type 2 caveat** (partner may not have shape even if trumps with partner): NOT WIRED — no partner-shape inference.
- **Sun F-11 Factor #3** (Kabout-trajectory): NOT WIRED. Same blocker as F-24 (no `partner_tricks_won` ledger).
- **Sun F-12 Factor #4** (score-flip when opp = bidder): NOT WIRED. Requires running-score projection; conflicts with current bidder-team gate.
- **Sun F-13 Factor #5** (left-opp leads next): NOT WIRED. Bidder-team gate is a partial match; "left-opp leads next" predicate not modeled.
- **F-39 / F-15 true top-2-live predicate**: NOT WIRED — proxy only.
- **5-factor weighted scoring** (per Source C "نسبه تناسب وعلى حسب الظروف", F-37): NOT MODELED. Code uses single AND-gated trigger, not weighted score.
- **F-33 worst-case meta-rule** (Hokm minimax): partially honored via "prefer non-trump non-winner" within Faranka pool, but no explicit minimax evaluation.

---

## Confidence

**HIGH** for the rule-by-rule mapping above. Every code branch was read end-to-end at HEAD; every Source-C rule was checked against the block. The Bug 1 (Exception "#3" lacks bidder-team gate) is the highest-impact actionable finding and follows directly from the v0.9.2 #49 reasoning applied to the v0.8.5 branch.

**MEDIUM** for the naming-collision claim (Bug 2) — code's "Exception #2"/"#4" labels predate Source C's F-numbering. The cross-reference is correct based on rule predicates; the labels diverged through independent evolution of the strategy doc and Source C audit.

**LOW** for the F-30 A+K-of-side predicate gap (Bug 3) — Source C says hand-shape; code says bidder+opp-void. Either the hand-shape is implicit (you wouldn't withhold without A+K anyway because winners already give you A) or Source C lists it as one example of a broader "bidder + safe withhold" class. Worth flagging but not necessarily a bug.

**Test coverage:** zero. Audit memo `22_section10_now.md` (line 60-63) confirms `tests/run.py` has no Faranka tests; every trigger branch is regression-bare. **Recommend** at minimum a per-branch test pin before any further changes.

**Doc drift:** `docs/strategy/decision-trees.md` Section 10 (lines 246-254) had stale "(not yet wired)" markers as of audit 34 / 22; v0.10.0 review should re-verify those rows match current wired status.
