# 52 — telemetry data exposure on /reload (v0.9.0 HEAD adversarial)

Targets: State.lua:1452-1495 (write site), Slash.lua:213-259 (dump),
Net.lua MSG_* table (wire), Bot.lua:106-240 (style/memory),
State.lua:250-359 (Save/RestoreSession).

## 1. /reload mid-round — in-flight row?

There is NO "in-flight" row to lose. Rows are appended only inside
`S.ApplyRoundEnd` (State.lua:1464), AFTER the round resolves. /reload
fires PLAYER_LOGOUT → `S.SaveSession` (WHEREDNGN.lua:302). The
`WHEREDNGNDB.history` table is in SavedVariables and persists
independently — nothing buffers in `s` between rounds. /reload
mid-trick legitimately discards the unfinished round; on host-resync
the round may complete post-reload and the row gets appended then.
**No loss, no double-write.**

## 2. Hand-edit attack — defensive type-checks on load

**GAP (LOW).** `WHEREDNGN.lua` guards top-level `WHEREDNGNDB` is a
table, but per-row schema is unvalidated:

- Append site (State.lua:1465): `WHEREDNGNDB.history = WHEREDNGNDB.history or {}`
  is nil-init only. Inject `WHEREDNGNDB.history = "junk"` (string) or `5`
  (number) and the next round-end errors at `h[#h + 1] = row` (`#` on
  non-table) and the cap loop `while #h > 200`.
- Dump site (Slash.lua:233-254): same `or {}` pattern, then
  `string.format("%-3d", r.roundNumber or 0)` etc. Inject a row with
  `bidder = {}` (table) or `roundNumber = "x"` and `%d` formatter
  raises. `WHEREDNGNDB.history = {"oops"}` (string element) crashes
  on `r.type` indexing.

Recommended pattern (mirrors the audit-blessed guard at State.lua:74):
`if type(WHEREDNGNDB.history) ~= "table" then WHEREDNGNDB.history = {} end`
at both sites; per-row `type(r) == "table"` skip in the dump loop.

## 3. Telemetry-disable race (`/baloot history off`)

Slash.lua:225 sets `WHEREDNGNDB.historyEnabled = false`
synchronously. Round-end gate (State.lua:1464) is
`historyEnabled ~= false`. WoW Lua is single-threaded; toggle
takes effect on the next `S.ApplyRoundEnd`. **No race window.**
Existing rows preserved (intentional, per slash message); no
retroactive scrub on opt-out.

## 4. Network exposure (MSG_*)

Audited every K.MSG_* in Net.lua (Net.lua:85-456). No MSG_HISTORY,
no MSG_TELEMETRY. Round-end wire (`SendRound`, Net.lua:282) carries
`addA;addB;totA;totB;sweep;made` — same fields any peer recomputes
locally. **Telemetry never leaves the local SavedVariables.**

## 5. Bot._partnerStyle persistence (M4)

State.lua:269-276 bundles `partnerStyle / memory / r1WasAllPass`
into the per-character session snapshot. `partnerStyle` is integer
counters per seat (bels/triples/fours/gahwas, leadCount,
gahwaFailed, sunFail, aceLate, baitedSuit, topTouchSignal,
tahreebSent). `_memory.played` carries played-card identifiers
(public observable info, per-round wipe). Cross-character restore
is rejected by the owner guard (State.lua:298). **Not
telemetry-adjacent in a privacy sense — counters and public plays.**

## Summary

- (1) No in-flight row — atomic append at round-end
- (2) **GAP LOW: no per-row / per-table type-check on load**
- (3) /baloot history off: synchronous, no race
- (4) Net: zero telemetry on the wire
- (5) _partnerStyle: counters only; _memory.played is public
