# L4 + L6 fix verification — v0.9.0 (commit 9c32c50)

## L4: Late-AKA retroactive flip — VERIFIED (with caveat)

**Site:** `Net.lua:2323` `N.LocalAKA(suit)`

Early-return chain (lines 2337-2342):

```lua
if S.s.trick and S.s.trick.plays and #S.s.trick.plays > 0 then
    return
end
if S.s.turn ~= S.s.localSeat or S.s.turnKind ~= "play" then
    return
end
```

This matches the CHANGELOG promise: rejects when (a) the trick
already has plays (i.e., we are NOT about to lead), or (b) it
isn't the local seat's turn, or (c) it's a turn for something
other than `"play"` (e.g., meld, double, gahwa). All three
conditions cause an early `return` before `S.ApplyAKA` and
`N.SendAKA` fire — so `s.akaCalled` stays untouched and the
4th-seat bot's ruff decision is no longer retroactively
suppressed.

### L4 edge — `_OnAKA` handler: NOT GATED

**Site:** `Net.lua:3046` `N._OnAKA(sender, seat, suit, replayFlag)`

`_OnAKA` does NOT mirror the new turn/lead-state gates. It only
checks: phase==PHASE_PLAY, contract is HOKM, seat sender
authorization, and replay-flag legitimacy (host-only).

**Practical impact:** mostly fine — a well-behaved peer's
`SendAKA` only fires from the gated `LocalAKA`, so wire traffic
is already filtered at source. But a malicious / patched peer
could emit `MSG_AKA` mid-trick on its own seat and the receiver
would still apply it. Cosmetic-only (AKA doesn't change
legality), and the existing `authorizeSeat(seat, sender)` check
limits damage to spoofing one's own seat. Worth a future hardening
note but not a v0.9.0 regression.

## L6: WHEREDNGNDB.target tonumber-coerce — VERIFIED

**Site 1:** `WHEREDNGN.lua:81` (init) — `tonumber(WHEREDNGNDB.target) or 152`
**Site 2:** `WHEREDNGN.lua:152` (PLAYER_LOGIN post-RestoreSession)
— `tonumber(WHEREDNGNDB.target) or B.State.s.target or 152`

Both call sites coerce. If `tonumber` returns nil
(uncoerceable string like `"abc"`), site 1 falls through to
`152` (numeric default). Site 2 falls through to the prior
`B.State.s.target` (already numeric from RestoreSession or
init), then to `152`. Both fallback chains terminate at a
hard-coded numeric `152`, so `cum >= target` arithmetic
downstream is safe.

## Verdict

- **L4: PASS** (LocalAKA correctly gated; `_OnAKA` receiver-side
  hardening optional, low severity)
- **L6: PASS** (both read sites coerced, both fall back to
  numeric 152)
