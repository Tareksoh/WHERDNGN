# Audit: decision-trees.md Section 11 — Reads / partner-style inference

**Codebase:** v0.7.2
**Targets:** `Bot.lua` (`Bot._partnerStyle`, `Bot.OnPlayObserved`); `BotMaster.lua` `PickPlay` sampler (`sampleConsistentDeal`, `getPartnerCards`).

---

## Section 11 rule enumeration (8 rows)

| # | Rule (short) | MAPS-TO note | Status |
|---|---|---|---|
| 1 | Sun + opp K-or-higher loses → suit void | `OnPlayObserved` **wired v0.7.2** | WIRED — see verification below |
| 2 | Hokm trump high-dump → seat short on trump | `_partnerStyle.trumpHighDump` `(not yet wired)` | NOT-WIRED |
| 3 | Pigeonhole all-remaining-trumps pin | `BotMaster.PickPlay` sampler beyond J/9 `(not yet wired)` | WIRED v0.5.22 — doc tag stale |
| 4 | Partner is Sun bidder → highs/long suit | Sampler bias `(not yet wired)` | WIRED v0.6.1 — doc tag stale |
| 5 | Partner Tahreeb'd low → A/J elsewhere | `tahreebSuspect[suit]` `(not yet wired)` | NOT-WIRED |
| 6 | Touching-honors gate (partner not yet winning) | `winnerSeatSoFar` gate `(not yet wired)` | NOT-WIRED |
| 7 | Partner convention adherence | `conventionAdherence` `(not yet wired)` | NOT-WIRED |
| 8 | Bait detected against opp | `baitDetectedBy[seat]` `(not yet wired)` | NOT-WIRED |

## WIRED-CORRECT
- **Rule 3 (pigeonhole)** — `BotMaster.lua:285-318` correctly extends J/9 pin to **K/Q/T/A/8/7 of trump** when exactly one non-self seat is trump-eligible (i.e., others observed void). Loops `unseen` filtering by `C.Suit(u) == trump` and pins to the survivor. Confirmed extension beyond J/9.
- **Rule 4 (Sun-bidder partner)** — `BotMaster.lua:111-127` `getPartnerCards` returns `desire["A"+s]=8, desire["K"+s]=4` for all suits in Sun; consumed at line 366 via `isBidderPartner`. Captures concentrated highs; long-suit emerges from random fill.

## WIRED-WRONG
*(none — rule 1 wired correctly modulo over-broad predicate; see below)*

## NOT-WIRED
- Rules 2, 5, 6, 7, 8 — all `(not yet wired)`. None of `trumpHighDump`, `tahreebSuspect`, `conventionAdherence`, `baitDetectedBy` exist in `Bot.lua`. The `winnerSeatSoFar` gate (rule 6) is absent — touching-honors reads (if any) are ungated.

## v0.7.2 rule-1 verification (`Bot.lua:319-355`)

**Tasgheer logic correct.** The wire fires for `BID_SUN` + `cardSuit==leadSuit` + rank in `{K,T}` + at least one play in the trick out-ranks them. On match, sets `mem.void[leadSuit]=true`. Plain-rank `A>T>K>Q>J>9>8>7` confirmed in `K.RANK_PLAIN` via `Cards.lua:107-114` `TrickRank`.

**Three deviations from doc text — all defensible:**
1. Doc says "2nd-position when next-to-act"; code accepts ANY losing follow (positions 2-4). Broader, but Tasgheer applies to all losing-follow positions, so this is a sound generalization.
2. Doc lists "K or higher" + "T may be saved"; code includes T (rank larger than K). Comment acknowledges; only matters if A is in trick. Pragmatically harmless — a T that loses is beaten by A only, so void inference still holds for the {Q,J,9,8,7} set the rule cares about.
3. `wasIllegal` gating present (sound). Skips Q-and-below per doc's confidence bracket. ✓

## NOTES
- **MAPS-TO column stale for rules 3 & 4.** Both shipped (v0.5.22 / v0.6.1) but doc still says `(not yet wired)`. Re-anchor.
- Rule 1's "wired v0.7.2" tag is correct.
- Deferred rules 2 & 5 require new ledger keys — confirmed not present, infrastructure note in doc still valid.
