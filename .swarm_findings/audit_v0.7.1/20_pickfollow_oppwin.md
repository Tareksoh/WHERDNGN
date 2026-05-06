# pickFollow opp-winning fall-through audit (v0.7.2)

Scope: `Bot.lua:2063-2597` `pickFollow`. Branch entered when `winners == {}`
(can't beat the current winner) and `partnerWinning == false`.

## 1. Doc-only marker at lines 2512-2529 — VERIFIED COMMENT-ONLY

Lines 2511-2529 are pure `--` comment text. No `if`, `return`, function
call, or assignment. Adjacent control flow:
- Line 2510: `end` closes the Belote-preservation block.
- Line 2530: blank line.
- Line 2531: `-- v0.5.14 Section 9 N-1 sender (Tanfeer)` (next executable
  block at 2555).

Confirmed: marker has zero behavioral effect. v0.5.11's `highestByRank`
branch is fully removed.

## 2. Control flow reaches `lowestByRank(legal)` for opp-winning Sun

Trace for Sun + opp-winning + can't beat:
1. `winners == {}` so 2369 `if #winners > 0` is false — skipped.
2. 2475 Hokm-only branch (`contract.type == K.BID_HOKM`) — skipped for Sun.
3. 2499 Belote-preservation — `holdsBeloteThusFar` returns false in Sun
   (gate at 1263: `contract.type ~= K.BID_HOKM` → false) — skipped.
4. 2555 Tanfeer — fires only if `voidInLed` AND wanted-suit-with-spare-low
   exists. Off-suit follow (where opp wins because we played off-suit) is
   the `voidInLed` case; if no qualifying suit, falls through.
5. 2596: `return lowestByRank(legal, contract)`. CORRECT for Tasgheer.

## 3. Hokm trump-follow (dump LOWEST trump, video #05)

NO explicit branch. Path: led=trump, we have trump (must-follow), opp
played higher trump → `winners == {}` → 2475 Hokm discardable filter
selects only NON-trump. `legal` is all-trump (forced trump-follow), so
`discardable == {}` — branch skipped. Falls through Belote (2499), Tanfeer
(`voidInLed` is false because we have trump = the led suit), and lands at
2596 `lowestByRank(legal)` = lowest trump. CORRECT — same fall-through as
Sun, no separate branch needed.

## 4. Tasgheer scope

Comment at 2515 cites video #05 for Sun off-suit. Hokm trump-follow
rationale per CLAUDE.md is conservation (saving J/9 of trump for ruffs),
not the symmetric-information Tasgheer signal. Code treats them
identically via shared fall-through; this is correct in outcome but the
doc-marker comment only references Sun. Minor doc gap, no behavior issue.

## 5. K-of-trump edge case

If only legal card is K of trump, `lowestByRank` returns K — unavoidable
(legality wins). Belote-preservation block at 2499-2510 filters K/Q only
when `#withoutBelote > 0`; if K is the ONLY legal card, `withoutBelote` is
empty and block falls through (line 2491 explicit comment confirms intent).
No Belote-preservation override forces an illegal play. SAFE.

## Verdict

All four fall-through paths (Sun-can't-beat, Hokm-trump-follow-can't-beat,
Belote-only-legal, Tanfeer-no-match) correctly converge on
`lowestByRank(legal)` at 2596. v0.7.2 revert is clean.
