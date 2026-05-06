# Audit 24: Deck/Deal Mechanics vs saudi-rules.md (HEAD v0.9.0)

## 1. Constants — deck size: PASS

`Constants.lua:11-13`:
- `K.SUITS = {"S","H","D","C"}` (4 suits)
- `K.RANKS = {"7","8","9","T","J","Q","K","A"}` (8 ranks)
- 4 × 8 = **32 cards**, matching saudi-rules.md "32 cards (7 through Ace × 4 suits)".
- `K.RANK_INDEX` / `K.SUIT_INDEX` mirror them consistently.

`Cards.lua:17-25` `M.NewDeck()` iterates `K.SUITS × K.RANKS`, producing exactly 32 unique cards.

## 2. Deal logic — 8/player: PASS

Two-phase deal (Saudi cut + 5/3 split) in `State.lua`:
- `S.HostDealInitial` (1522-1532): shuffles via Park-Miller LCG seeded by `GetTime()`, deals **5** to each of 4 seats, takes 1 face-up `bidCard`, stashes 11-card remainder.
- `S.HostDealRest` (1535-1567): bidder receives `bidCard` + 2 (= 3); other 3 seats receive 3 each. Final per-seat: **5+3 = 8 cards**, total 32 = 4×8 distributed exactly.
- All-pass branch (`Net.lua:1560-1567` `_HostRedeal`): redeals from scratch.

No off-by-one or leakage between seats observed. `DealCount` mutates the deck (`table.remove(deck)` from end), so each card lands in exactly one hand.

## 3. MSG_HAND wire — host-only secret: PASS

`Net.lua:116-131`:
- `N.SendHand(target, cards)` calls `whisper()` (`SendAddonMessage` channel `"WHISPER"`, line 50) — **never** `PARTY` broadcast.
- `dealHandsToHumans` iterates non-bot non-self seats and whispers each their own hand only.
- Host's own hand applied directly via `S.ApplyHand` (`Net.lua:1743, 1786`) — never crosses the wire.
- `State.lua:48-49`: `s.hand` is local; `s.hostHands` is host-private (gated `s.isHost` in `HostFinishDeal` etc.).
- Resync re-whispers `MSG_HAND` to the **target only** (`Net.lua:362-372`).

Verdict: hands are whisper-secure. Other clients cannot eavesdrop.

## 4. R.IsKaweshHand — 5×{7,8,9}: PASS

`Cards.lua:170-177`: returns false if `#hand < 5` (audit fix M-1, prevents mid-deal false positive); iterates and rejects on any rank ≠ 7/8/9.
- Operates on the **first-five-dealt** hand (PHASE_DEAL1), correctly per saudi-rules.md.
- `K.MSG_KAWESH = "a"` wires the call (Constants.lua:185).

Edge case: function silently allows `#hand > 5` (e.g. post-deal2 8-card hand) to also pass if all 7/8/9 — no PHASE guard inside the function. Callers gate on PHASE_DEAL1, so safe in current call sites, but fragile if reused.

## 5. Dealer rotation — host-canonical: PASS

`Net.lua:1758-1769` `HostStartRound`: `dealer = (S.s.dealer % 4) + 1` (CCW seat advance), then `S.ApplyStart(roundNum, dealer)` + `N.SendStart(roundNumber, dealer)` — broadcast as `MSG_START` payload field 2 (`Net.lua:108-109`).
- Clients adopt via `S.ApplyStart` (line 743) and resync field 3 (`State.lua:411`).
- Redeal path same: `_HostRedeal` advances `S.s.dealer = nextDealer` and broadcasts (`Net.lua:1736-1739`).

No client computes dealer locally; **host is canonical**, broadcast via MSG_START / resync.

## Summary

All five checks PASS. Implementation matches saudi-rules.md deck/deal section. Minor robustness note on IsKaweshHand >5-card edge (not a bug today).
