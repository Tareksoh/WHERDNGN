# A-2 Ashkal bid-up rank gate — singleton-T verification (v0.9.1)

## Location
`Bot.lua:1183-1274` — Ashkal logic is **inlined inside `Bot.PickBid`'s round-1 block** (no standalone `Bot.PickAshkal` function). The bid-up rank gate is split across four discrete `ok = false` sieves at lines 1212, 1223, 1230-1236, 1243.

## Doc spec (decision-trees.md A-2, video #31)
Allow-list (positive): `{7, 8, 9, J, Q, singleton-T-without-A}`.
Anti-triggers: bid-up = A, bid-up = K, bid-up = T-with-own-A.

## Per-rank verification

| Rank | Code path | Eligible? | Matches doc? |
|---|---|---|---|
| 7 | passes all four sieves | yes | yes |
| 8 | passes all four sieves | yes | yes |
| 9 | passes all four sieves | yes | yes |
| J | passes all four sieves | yes | yes |
| Q | passes all four sieves | yes | yes |
| K | line 1223 `bidCardRank=="K"` → `ok=false` | no | yes (v0.9.1 fix) |
| A | line 1212 `bidCardRank=="A"` → `ok=false` | no | yes |
| T (own A in suit) | line 1230-1236 loop hits → `ok=false` | no | yes |
| **T (no own A, doubleton)** | **all sieves pass** | **YES** | **NO — gap** |
| T (no own A, singleton) | all sieves pass | yes | yes |

## The gap (Q4/Q5/Q6)

**Q4 — singleton-T, no own-A:** Ashkal **allowed** (correct).
**Q5 — doubleton-T, no own-A:** Ashkal **allowed** (incorrect — doc says only **singleton-T** qualifies).
**Q6 — earlier audit confirmed:** the v0.9.1 fix added the K block but did **not** add a T-cardinality check. Doubleton/tripleton T (without own A) still slips through.

### Code evidence
Lines 1230-1236:
```lua
if ok and bidCardRank == "T" and bidCardSuit then
    for _, c in ipairs(hand) do
        if C.Rank(c) == "A" and C.Suit(c) == bidCardSuit then
            ok = false; break
        end
    end
end
```
Loop only checks for **own-A in bid-up suit**. Never counts how many Ts we hold across all suits.

A `Grep` across `Bot.lua` for `singleton`, `tCount`, `countT` returns no Ashkal-related matches; the singleton-T gate is genuinely absent.

## Impact assessment
- **Severity: minor** (audit 16 already flagged it).
- **Frequency:** rare. Bid-up = T is itself uncommon, and most T-holding hands also hold the same-suit A (already blocked by A-4). Doubleton-T-without-own-A is a narrow shape.
- **Behavior:** mardoofa preservation logic (A-4) is intact. The gap allows Ashkal in cases where doc would prefer Hokm cover, but no immediate hand-loss vector — partner is already in Hokm and we're flipping to Sun on a weak T-cover hand.

## Suggested fix
Insert before line 1230 or augment that block:
```lua
if ok and bidCardRank == "T" then
    local tCount = 0
    for _, c in ipairs(hand) do
        if C.Rank(c) == "T" then tCount = tCount + 1 end
    end
    if tCount > 1 then ok = false end
end
```
Combined with the existing 1230-1236 own-A check, this enforces the full doc spec: T accepted **only when singleton AND no own-A**.

## Cross-ref
Audit `16_section1_now.md:14` notes this gap with identical framing.
