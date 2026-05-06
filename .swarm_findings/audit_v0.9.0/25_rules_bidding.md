# Audit 25 — Bidding rules vs live code (HEAD v0.9.0+)

Cross-checked saudi-rules.md Bidding § against State.lua's
`S.HostAdvanceBidding` (1592), `S.ApplyContract` (1010),
`S.BeginOvercall`/`FinalizeOvercall` (931, 971),
`S.PreemptEligibleSeats` (1784); Net.lua `_OnBid` (809),
`_OnContract` (825), `_HostStepBid` (1494),
`_HostBeginOvercallWindow` (1130). Scope: bid types only.

## Rule-by-rule verdict

### 1. Bid types HOKM/SUN/ASHKAL/PASS — PASS
State.lua:1614-1715 exhaustively switches on the four
`K.BID_*` tokens; no default fallthrough.

### 2. Sun overcalls Hokm — PASS, both rounds
R1: 1617-1635 admits SUN even when `winning` is HOKM; HOKM branch
at 1686 gates on `not winning` so HOKM never displaces SUN. R2
mirror at 1698-1712. The walk consumes all 4 seats before
finalizing (`count >= 4`, line 1722), so a later-seat Sun cleanly
overcalls an earlier-seat Hokm.

### 3. Sun-over-Sun does NOT reassign — PASS
R1: `priorDirectSun` guard at 1627-1630 keeps earlier `winning`.
`viaAshkal` flag preserves the carve-out that direct Sun CAN
displace an Ashkal-derived Sun. R2 same shape at 1699-1705 (no
viaAshkal — Ashkal is R1-only).

### 4. R2 Hokm cannot reuse R1's flipped suit — PASS
1707-1711: `flippedSuit = C.Suit(s.bidCard)`; if R2 Hokm's
`trump == flippedSuit`, silently dropped (no `winning` mutation).

### 5. Ashkal seat eligibility = bidPosition >= 3 — PASS
1662-1666: `bidPosition < 3` silently dropped. With order array
`{dealer+1, dealer+2, dealer+3, dealer}`, positions 3+4 are
dealer-LEFT + dealer, matching the v0.5.7 post-audit interpretation
cited in saudi-rules.md and CLAUDE.md context. Inline comment at
1639-1661 correctly justifies the mapping against UI.lua's
NextSeat=right convention. Prior-direct-Sun gate at 1670-1676 also
enforced.

### 6. "First non-pass wins" only for HOKM-vs-HOKM — PASS
HOKM branches gate on `not winning` (1686, 1706) — first HOKM
locks out later HOKMs. Sun/Ashkal branches don't use this gate
(can override earlier HOKM). All-pass redeal trigger at 1727.

### 7. `_OnBid`/`_OnContract` idempotence — PASS
`_OnBid` gates on phase (813), turn (815), `bids[seat] != nil`
(817), and `authorizeSeat` (819) — duplicates short-circuit.
`_OnContract` delegates to `S.ApplyContract` which guards
bidder+type+trump triple-equality at 1019-1024, preserving already-
applied escalation flags.

### 8. Pre-emption (Triple-on-Ace) — PASS
Net.lua:1505-1547: gates on `enablePreempt`, `bidRound == 2`,
`type == K.BID_SUN`, `bidRank == "A"`, non-empty eligible list.
`PreemptEligibleSeats` (State.lua:1784-1809) excludes buyer's
partner and seats after buyer in turn-order; PASS retains pre-
emption right (1802-1805). Waive flow finalizes via empty list
(1827-1829). Eligible-seat CSV broadcast at Net.lua:1533.

### 9. Sun-overcall window v0.7/v0.8 — PASS
`_HostBeginOvercallWindow` (Net.lua:1130) invoked AFTER
SendContract but BEFORE Sun-Bel-skip (1558-1560). Gates on
`type == K.BID_HOKM`, `not contract.forced`. v0.8 cross-trump
`TAKE_HOKM_<S|H|D|C>` validated at State.lua:951-957.
`S.FinalizeOvercall` (982-1003) rewrites contract type/trump/
bidder and re-derives `belPending` on takes. Resolve re-broadcasts
MSG_CONTRACT and re-checks Sun-Bel-skip (Net.lua:1224-1235).
Pause-aware timer rearm at 1168-1184.

## Findings: zero defects in scope.

All 9 bid-rule invariants enforced. The Ashkal bidPosition mapping
is settled — comment at State.lua:1639-1661 documents the rationale.
