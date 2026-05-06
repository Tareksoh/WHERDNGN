# v0.8.3 — Live-game telemetry export — audit

Commit: `3c64f77` (Tue May 5 2026). Adds `S.ApplyRoundEnd` write into
`WHEREDNGNDB.history` and `/baloot history` slash commands.

## What / where / when

- **What:** one row per round (17 fields): `roundNumber`, `ts`,
  `type` (HOKM/SUN), `trump`, `bidder`, `doubled`, `tripled`,
  `foured`, `gahwa`, `forced`, `bidRound`, `bidCard`, `addA`,
  `addB`, `totA`, `totB`, `sweep`, `bidderMade`, `target`,
  `localSeat`.
- **Where:** `WHEREDNGNDB.history` (SavedVariables, persists
  across sessions). Capped at 200 rows; oldest dropped when full.
- **When:** end of `S.ApplyRoundEnd` (State.lua:1402+), after
  `B.Bot.OnRoundEnd`. Each client logs independently.

## Verifications

1. **Privacy — pass.** No player names. `bidder`/`localSeat` are
   integer seat indices (1–4). No hand contents (no `s.hands`,
   `s.cards`, no card lists). `ts` is `GetTime()` — relative
   session uptime in seconds, not wall-clock; cannot identify
   when the player played in real time. `bidCard` is the bid
   level/card (e.g. "9", "Bel"), not a hand card.
2. **Storage — pass.** SavedVariables only (`WHEREDNGNDB`, persists
   to `WTF/.../SavedVariables/WHEREDNGN.lua`). No file-system
   writes outside the WoW addon sandbox; no network export.
3. **Performance — negligible.** One table append + bounded
   `table.remove(h, 1)` only when len>200. Round-end is already
   non-hot-path (once per round, not per trick). No per-trick
   overhead.
4. **Schema versioning — FAIL.** Row has no `schemaVersion` /
   `version` field. Forward-compat for the calibration scripts
   relies on field presence checks, not a version bump. Adding
   a field on read-time is fine; renaming/removing a field would
   silently break older rows. Recommend adding `v = 1` per row
   or `WHEREDNGNDB.historySchema = 1` at the table level.
5. **Opt-in/opt-out — partial.** Default ON
   (`historyEnabled ~= false`). Opt-out via
   `/baloot history off` or `WHEREDNGNDB.historyEnabled = false`.
   No first-run prompt or notice — existing players see the
   table grow silently. No retroactive scrub on opt-out
   (existing rows preserved per the slash-command message).
6. **Bot vs human — FAIL.** No `isBot` flag per row. The bidder
   could be a bot or a human; the row records seat index only.
   Calibration that wants "human bidder vs bot bidder"
   distributions cannot disambiguate without cross-referencing
   the seat to a roster snapshot, which is not captured.
7. **Tests — none specific.** Commit message claims "319/319
   regression pass"; CHANGELOG notes the test harness stubs
   `WHEREDNGNDB`. Grep for `history|telemetry` in `tests/*.lua`
   returns one unrelated hit (bid history). No test asserts
   row contents, the 200-row cap, or the opt-out path.

## Recommended for v0.9.0

- Add `schemaVersion` / `v` field (forward-compat).
- Add `bidderIsBot` / `seatIsBot[1..4]` snapshot.
- Add a unit test for the 200-row cap and the opt-out gate.
- Consider a one-time chat notice on first telemetry write
  pointing at `/baloot history off`.
