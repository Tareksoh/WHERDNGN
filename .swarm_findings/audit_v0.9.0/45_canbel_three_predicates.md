# #45 — Three Bel-gate predicates: R.CanBel relaxed vs `_SunBelAllowed`

## Verdict: UX BUG — narrow desync race, narrow timing window

The relaxed `R.CanBel` (Rules.lua:489 — symmetric `mine<100`) disagrees
with `_SunBelAllowed` (Net.lua:68 — asymmetric `bidder>=101 AND
defender<101`) per video #11.

## Scenarios

### Scenario A — both teams ≥100 (e.g., bidder=120 / defender=110)
- `R.CanBel(defender, sun, ...)` → `110<100` = false → button hidden,
  bot won't try, LocalDouble defends in depth.
- `_SunBelAllowed(120)` → `120>=101 AND 110<101` = false → host skips
  PHASE_DOUBLE.
- All three predicates align on FALSE. **No bug.**

### Scenario B — both teams <100 (e.g., bidder=80 / defender=50)
- `R.CanBel(defender, sun, ...)` → `50<100` = TRUE → button enabled.
- `_SunBelAllowed(80)` → `80>=101 AND 50<101` = false → host's
  `_HostStepBid` (Net.lua:1586-93) calls `HostFinishDeal()` after
  `S.ApplyContract` (which already set `phase=PHASE_DOUBLE` at
  State.lua:1040).
- **Race window**: between MSG_CONTRACT arrival on the defender client
  (sets phase=PHASE_DOUBLE locally) and MSG_ROUND arrival from
  `HostFinishDeal`, the defender's UI shows an enabled Bel button.
  Click within that window:
  1. `LocalDouble` (Net.lua:1836) — `R.CanBel` returns true, no
     early return.
  2. `S.ApplyDouble` mutates LOCAL `contract.doubled=true`.
  3. `N.SendDouble` broadcasts MSG_DOUBLE.
  4. Host's `_OnDouble` (Net.lua:850) — phase already advanced past
     PHASE_DOUBLE (deal finished), so guard at line 858
     `if S.s.phase ~= K.PHASE_DOUBLE then return end` silently drops it.
  5. Defender's local state has `doubled=true`; host scored the round
     un-doubled. MSG_ROUND from host then snaps the client back into
     lockstep (resets contract).

## Verifications
1. **Reproducible**: yes, on bidder<100/defender<100 Sun contracts —
   any first-Sun-of-the-game scenario.
2. **Host error/rejection back?**: NO. Host silently drops the
   MSG_DOUBLE (phase guard). Recovery is implicit via the MSG_ROUND
   that `HostFinishDeal` already broadcast.
3. **Stuck UI?**: brief flash of `doubled=true` (e.g., score panel
   may flicker `×2` for a frame), then MSG_ROUND clears the contract
   for the next deal. Not "stuck" past one network RTT, but the
   defender saw their click *succeed locally then vanish*.
4. **Fix**: align predicates per video #11. Replace `R.CanBel`'s
   symmetric `mine<100` with the asymmetric form — defender team
   must be `<101` AND bidder team must be `>=101`. This requires
   `R.CanBel` to know the bidder team (currently it only takes the
   "team" doing the Bel). Cleanest: have `R.CanBel(defenderTeam,
   contract, cumulative)` consult `contract.bidder` to derive
   bidder-team and gate symmetrically with `_SunBelAllowed`. Then
   UI button + Bot.PickDouble + LocalDouble + `_OnDouble` all
   converge — and the dual-low race vanishes because the button
   never appears.

## Impact
Low severity (one frame of misleading `×2`), high frequency (every
first-Sun of every match). Worth fixing in v0.9.x.
