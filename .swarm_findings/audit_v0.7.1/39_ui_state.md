# Audit 39: UI State Consistency (UI.lua, v0.7.2 HEAD)

Scope: U.Refresh, per-banner OnUpdate self-ticks, action gating, hand
display, and behaviour under pause / spectator.

## 1. Bel button gate (R.CanBel) — LIVE but not "grayed"

`UI.lua:1761-1767` (PHASE_DOUBLE branch).

```lua
local canBel = (R and R.CanBel) and
    R.CanBel(R.TeamOf(S.s.localSeat), S.s.contract, S.s.cumulative)
if canBel == false then
    addAction("|cff999999Bel forbidden (Sun >=100)|r", function() end)
    addAction("Skip", function() net().LocalSkipDouble() end)
else
    -- Bel / Bel & open / Bel & closed
end
```

Gate is wired to `R.CanBel` and works. Caveat: when forbidden, the
button is not actually disabled via `SetEnabled(false)` — it's a
clickable button with a grey-coded label and a no-op handler. Visually
"grayed" via colour escape only; still focusable / clickable. Minor —
the no-op handler prevents any side effect, but a true `SetEnabled` or
disabled-button visual would be more honest. Not a regression vs the
v0.5.15 spec (which only required the gate, not visual disable).

## 2. SWA banner card preview — VISIBLE during 5-sec window

`UI.lua:1399-1437` (slot construction + populateCards) and
`UI.lua:3216-3222` / `UI.lua:1467-1472` (re-decode guard).

Cards populate from `req.encodedHand` via `C.DecodeHand`, with
`_lastEnc` cache to avoid 3 Hz redecodes. Both the Refresh path and
the OnUpdate self-tick honour `_lastEnc`. Cards are shown.

## 3. Sun-overcall UI (v0.7.0 phase 3) — CORRECTLY hides/shows

Banner `UI.lua:1322-1365`: OnUpdate hides itself on
`S.s.phase ~= K.PHASE_OVERCALL or not S.s.overcall`. `renderOvercallBanner`
(`UI.lua:3171-3182`) only `:Show()`s during PHASE_OVERCALL. Action
buttons in `UI.lua:1818-1932` only render in PHASE_OVERCALL with
per-seat `alreadyDecided` lock-out and a per-tick countdown label
forced via `U.Refresh()` from inside the OnUpdate (`UI.lua:1358-1362`).
Behaviour is consistent across show / decided / hide.

## 4. AKA banner — CORRECTLY clears after trick

`renderAKABanner` (`UI.lua:3226-3247`) hides on `not S.s.akaCalled`
or phase != PHASE_PLAY. `State.ApplyTrickEnd` clears
`s.akaCalled = nil` at `State.lua:1238`. Banner is gone next Refresh.

## 5. Pause overlay vs banner OnUpdate — BUG (UI-only drift)

The pause overlay (`UI.lua:3279`) is shown when `S.s.paused`. However:

- SWA banner OnUpdate (`UI.lua:1445-1473`) does NOT consult
  `S.s.paused`. It keeps decrementing `remain = ceil(windowSec - (now - req.ts))`
  while the game is paused, so the visible countdown ticks down to 0
  during pause. If the host's authoritative auto-approve timer is
  pause-aware, the banner shows a wrong countdown. If it's NOT
  pause-aware, the auto-approve fires while UI shows "PAUSED".
- Overcall banner OnUpdate (`UI.lua:1337-1364`) has the same defect.

Recommended: gate both OnUpdates on `if S.s.paused then return end`
(or freeze remain at last value). Pre-existing — not introduced in
v0.7.x — but worth flagging.

## 6. Spectator suppression — CORRECT

`renderActions` early-returns on `if not S.s.localSeat then return end`
at `UI.lua:1672` (M-4 fix from the 50-agent audit). Spectators get
zero action buttons. Other localSeat-gated paths
(`UI.lua:1832, 1954, 2027`) are now redundant but defensive.

The handRow renders spectator-info instead of cards
(`UI.lua:1525-1528`). No "play card" surface for spectators.

## Summary

- v0.7.2 UI is internally consistent for AKA / SWA / overcall
  show-hide and spectator gating.
- One real bug: SWA + overcall banner self-ticks ignore
  `S.s.paused`. Countdowns visibly drift while game is paused.
- One cosmetic gap: forbidden Bel button uses grey colour escape
  rather than `SetEnabled(false)` — clickable no-op.
