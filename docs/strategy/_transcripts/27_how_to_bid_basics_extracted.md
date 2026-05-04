# 27_how_to_bid_basics — extracted rules

**Source:** https://www.youtube.com/watch?v=88rTaIRGi1U
**Title (Arabic):** كيف تشتري في البلوت للمبتدئين | 6
**Title (English):** How to bid in Baloot — beginners ep 6
**Slug:** 27_how_to_bid_basics
**Topic:** Beginner bidding tutorial — bid options, auction flow, round 1 vs round 2 mechanics.

---

## 1. Summary

Pure bidding-mechanics tutorial. Speaker walks through the five
bid choices (صن / حكم اول / حكم ثاني / اشكل / بس), the deal/cut
flow, and how round 1 ("اول") differs from round 2 ("ثاني"). No
hand-feature heuristics (no "bid Hokm with J+9 of trump", no
"bid Sun with 3 Aces"). The video is a syntax/protocol primer,
not a strength-evaluation primer despite the topic-hint expectation.

The single decision rule extractable is the round-1 vs round-2
contract restriction (mechanical, already enforced by `Rules.lua`).

---

## 2. Vocabulary check

All terms map to existing entries in `glossary.md`. No new terms.

| Arabic (transcript) | Glossary entry | Code identifier |
|---|---|---|
| صن | sun | `K.BID_SUN` |
| حكم اول | Hokm round-1 (face-up turned suit) | `K.BID_HOKM` (round 1 branch) |
| حكم ثاني | Hokm round-2 (any suit other than the turned one) | `K.BID_HOKM` (round 2 branch) |
| اشكل / اشكال | ashkal | `K.BID_ASHKAL` |
| بس / ولا | pass (round 1 / round 2 wording) | `K.BID_PASS` |
| ولد | J (Walad) | per glossary family-trio |
| الورقه (the card) | the turned/face-up card from the cut | (game-state, no constant) |
| الموزع | dealer | seat metadata |

Speaker uses ولد ("the boy") for J in the only concrete example
("ولد وتسع سبيد" = J+9 of spades). Confirms `glossary.md`
family-trio convention. No new terminology introduced.

---

## 3. Decision rules

### Rule 27.1 — Round-1 vs Round-2 Hokm restriction (mechanical)

| Field | Value |
|---|---|
| **WHEN** | Bidder is choosing Hokm |
| **RULE** | Round 1 ("اول"): Hokm MUST equal the suit of the turned-up card ("الورقه في الارض"). Round 2 ("ثاني"): Hokm MUST be any of the three other suits — NOT the turned suit. |
| **WHY** | Mechanical Saudi auction structure. Round 1 = "buy the face-up trump"; round 2 = "name a different trump". |
| **MAPS-TO** | Already enforced by `Rules.lua` legality check; `Bot.PickBid` (Bot.lua:725) must respect this when proposing a Hokm bid. **Likely already wired** — flag for verification only. |
| **CONFIDENCE** | Definite (rule-of-game, not heuristic) |
| **SOURCES** | 27 |

### Rule 27.2 — Sun is suit-agnostic across rounds

| Field | Value |
|---|---|
| **WHEN** | Bidder considering Sun in either round |
| **RULE** | Sun does not depend on the turned card; available identically in round 1 and round 2. |
| **WHY** | Sun is no-trump — no suit named, so the turned card is irrelevant. Speaker contrasts this with Hokm's round-2 restriction. |
| **MAPS-TO** | `Bot.PickBid` Sun branch (Bot.lua:725) — round-counter independence already implicit. Verification only. |
| **CONFIDENCE** | Definite |
| **SOURCES** | 27 |

### Rule 27.3 — Ashkal eligibility = dealer + dealer's left seat only

| Field | Value |
|---|---|
| **WHEN** | A player considers calling Ashkal |
| **RULE** | Only the **dealer** and the seat to the **dealer's left** ("اللي على يسار الموزع") may call Ashkal. The other two seats cannot. |
| **WHY** | Ashkal is a partner-conversion bid — only the Hokm-bidder's partner may convert it to Sun. With turn-order RHO-of-dealer leading the auction, Ashkal callers are the bidder's partner candidates. |
| **MAPS-TO** | `Bot.PickBid` Ashkal branch (Bot.lua:725+) — should gate Ashkal eligibility on `seat == dealer or seat == LeftOf(dealer)`. **Verification needed**: confirm legality already excludes the other two seats. |
| **CONFIDENCE** | Definite |
| **SOURCES** | 27 |

### Rule 27.4 — Round-1 pass is "بس", round-2 pass is "ولا"

| Field | Value |
|---|---|
| **WHEN** | Voicing a pass |
| **RULE** | Round 1: say "بس" (bas, "enough/no"). Round 2: say "ولا" (wala, "no"). Same effect, different word per round. |
| **WHY** | Saudi auction etiquette — listeners infer round-context from the pass-word. |
| **MAPS-TO** | Cosmetic only (sound cue / chat string). Could optionally pick `K.MSG_PASS` variant by `S.s.bidRound`. Not decision-affecting. |
| **CONFIDENCE** | Definite |
| **SOURCES** | 27 |

### Rule 27.5 — Auction starts at RHO-of-dealer ("اليمين الموزع")

| Field | Value |
|---|---|
| **WHEN** | Auction opens (after deal) |
| **RULE** | First bidder is the seat to the **right** of the dealer ("اللي على يمين الموزع"). Bid pivots clockwise (right) from there. |
| **WHY** | Standard Saudi turn-order convention; speaker repeats this for both round 1 and round 2 starts. |
| **MAPS-TO** | Auction state machine in `Net.lua` / `State.lua` — already enforced. Verification only. |
| **CONFIDENCE** | Definite |
| **SOURCES** | 27 |

---

## 4. Hand-strength heuristics

**None present.** Topic hint anticipated rules like "bid Hokm with
J+9 of trump" or "bid Sun with ≥3 Aces" — speaker does NOT cover
these. The single concrete hand mentioned is "ولد وتسع سبيد"
(J+9 of spades) but only as an *example of when to wait for round
2 if the spade isn't the turned suit* — i.e., a mechanical
illustration of rule 27.1, not a strength threshold.

`Bot.PickBid` (Bot.lua:725) hand-strength thresholds (`K.BOT_*_TH`)
get **no new input** from this video. The "minimum hand to bid
Hokm" pattern remains **undefined by this source** — caller must
look to videos focused on hand evaluation (e.g. future
beginner-ep-7+ or tournament commentary) to populate that rule.

---

## 5. Open questions / contradictions

- **None with existing strategy docs.** All five rules are
  mechanical (round-structure / seat-eligibility / etiquette) and
  do not conflict with any existing entry in `decision-trees.md`.
- **Gap flagged:** beginner ep 6 (this video) is purely syntax;
  hand-evaluation heuristics likely live in a different episode of
  the same series. Caller should look for ep 7+ or a video titled
  around "متى تشتري" / "قوه اليد" for actual strength rules.
- **Verification action:** confirm `Bot.PickBid` already restricts
  Ashkal calls to dealer + dealer-left seats and Hokm round-2 bids
  to non-turned suits. If not, add the gates — rules 27.1 and 27.3
  are legality-level, not heuristic-level.
