# Audit: decision-trees.md Section 9 — Tanfeer (تنفير)

**Codebase:** v0.7.2
**Targets:** `Bot.lua` `pickFollow` Tanfeer sender (2531-2594), `pickLead` opp-signal reader (1508-1526)
**Doc line refs:** rows say `pickFollow` Bot.lua:1457 and `pickLead` Bot.lua:953 — both **stale** (actual: 2063 / 1359).

---

## Section 9 rule enumeration

| # | WHEN | RULE | MAPS-TO (doc) |
|---|---|---|---|
| 9.1 (N-1) | Opp 100% taken trick; you discard / ruff | Discard the suit you DO want partner to return (positive signal, inverse of Tahreeb) | `pickFollow` Bot.lua:1457 opp-winning discard branch `(not yet wired)` |
| 9.2 (N-2) | Trick-winner uncertain | **Default to Tahreeb semantics, NOT Tanfeer** | `pickFollow` discard fallback `(not yet wired)` |
| 9.3 (N-3) | Opp does small→big tahreeb-style discard on you | Treat suit as suit-to-AVOID; do NOT lead it | `pickLead` Bot.lua:953 opp-read branch `(not yet wired)` |

Doc tags **all three** as `(not yet wired)`. v0.5.14 changelog says they shipped — doc MAPS-TO column is stale.

---

## WIRED-CORRECT

- **9.1 (N-1 Tanfeer sender)** — Bot.lua:2555-2594. Gated `Bot.IsM3lm() and Bot.IsBotSeat(R.Partner(seat))`, requires `voidInLed`, scans non-trump suits for (hasHigh A/T) + (≥1 low to spare), discards lowest-of-low to suit-signal without burning the high. Inverse-Tahreeb semantics correct.
- **9.3 (N-3 opp-reader)** — Bot.lua:1508-1526 plus conflict resolution 1530-1532. Iterates opp seats, classifies their `tahreebSent` signals via `tahreebClassify`, marks `bargiya|want` suits into `tahreebAvoidSet`. Conflict rule: opp-avoid dominates partner-pref when both point at same suit (1530-1532). Matches doc.

## WIRED-WRONG

*(none)*

## NOT-WIRED

- **9.2 (N-2 uncertain-winner → Tahreeb default)** — explicitly documented at Bot.lua:2541-2550 as a *choice not to wire*. Code branches binary on `partnerWinning` (R.CurrentTrickWinner output); ambiguous cases fall through to `lowestByRank` with no encoding. Comment argues this approximates Tahreeb-default (lowest = positive Tahreeb). **Asymmetry NOT explicitly enforced** — bot treats every non-partnerWinning trick as opp-winning and may fire Tanfeer in genuinely uncertain states. Acceptable per author's note but not a true implementation of N-2.

## SIX-FACTOR OPP-TANFEER (video #19)

**Not wired.** No `tanfeerWeight(seat,suit)`, no per-seat tanfeer ledger keys (`tanfeerSeen|tanfeerAbsent|tanfeerSwitchedTo`), no bidder-vs-non-bidder weight asymmetry (0.7/1.3). Receiver path (1508-1526) treats opp signals as binary avoid via `tahreebClassify` — no timing/rank/count/both-opps/switch/bidder factors. Doc Section 11 does not yet have these rows; framework lives only in `_transcripts/19_discover_via_tahreeb_extracted.md` and `bot-personalities.md` line 179. Gap is doc-side first.

## NOTES

- Stale line refs: doc says 1457/953; actual 2063/1359. Re-anchor.
- v0.5.14 wired N-1 + N-3; doc MAPS-TO column never updated.
