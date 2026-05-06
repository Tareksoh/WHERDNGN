# v0.9.0 — Telemetry growth audit (`WHEREDNGNDB.history`)

Code: `State.lua:1452-1495`, `Slash.lua:213-259`, `WHEREDNGN.toc:7`,
`WHEREDNGN.lua:63-72`.

## 1. Cap behaviour — FIFO drop-oldest. PASS.

```
h[#h + 1] = row
while #h > 200 do table.remove(h, 1) end
```

Append-then-trim. `table.remove(h, 1)` shifts indices each iteration
(O(n)), but n is bounded so re-trim cost is fixed. NOT
stop-at-limit — newest row always wins. Loop guards against any
prior over-cap state from hand-edits.

## 2. Per-row size — ~250 B Lua-serialized.

17 fields, mostly small ints + 1–4 char strings (`type`, `trump`,
`bidCard`, `sweep`). Estimate: keys (avg 9 chars) + values + Lua
table overhead (~24 B/entry) ≈ 250 bytes serialized. **200 rows
≈ 50 KB.** Negligible vs the WoW 8 MiB SavedVariables cap.

## 3. Total `WHEREDNGNDB` size impact — small.

Other keys: `target` (number), `framePos` (4 numbers), 4 bot-tier
booleans, `allowSWA`, `swaRequiresPermission`, `preemptOnAce`,
`teamNames` (2 short strings), `lastGameID` (string), and
`session` (full game snapshot — hands, tricks, melds, contract,
bot module state). The `session` snap is the biggest single
contributor: an 8-trick mid-round state with 4 hands ≈ 5–15 KB.
History at full 200 rows (~50 KB) is **roughly 3–10× the session
snap, but still 2 orders of magnitude under the slow-load (~1 MB)
threshold**.

## 4. WoW SV limits — well clear.

8 MiB hard cap, ~1 MB slow-load threshold. Total addon footprint
at steady state: well under 100 KB. No risk.

## 5. Telemetry-disable persistence — PASS.

`/baloot history off` sets `WHEREDNGNDB.historyEnabled = false`;
`Slash.lua:226` says "(existing rows preserved)". Round-end gate
(`State.lua:1464`) is `historyEnabled ~= false` — disabling stops
new appends, leaves rows. Manual wipe via `/baloot history clear`
sets `WHEREDNGNDB.history = {}`. **No retroactive scrub on
opt-out** (matches privacy expectation but worth noting).

## 6. Per-character vs per-account — FAIL (minor).

`.toc` declares `## SavedVariables: WHEREDNGNDB`, NOT
`SavedVariablesPerCharacter`. Telemetry is **per-account**: rows
from all characters on the realm-set interleave into one table.
Row schema has no `character` / `realm` field. Cross-character
calibration cannot disambiguate. Bidder seat index is local to
that game session only. Recommend either `r.character =
UnitName("player")` per row OR document the per-account
interleave.

## 7. Hand-edit safety — PARTIAL.

Top-level `WHEREDNGNDB` is type-guarded (`WHEREDNGN.lua:69` —
resets to `{}` if not table). **But `WHEREDNGNDB.history` itself
is not type-checked**: `State.lua:1465` does
`WHEREDNGNDB.history = WHEREDNGNDB.history or {}` (only nil-init,
not type-init). If a user hand-edits to `history = "junk"` or
`history = 5`, `#h` and `h[#h+1] = row` will error at round-end.
`Slash.lua:233` has the same gap (`WHEREDNGNDB.history or {}`).
Slash dump at `Slash.lua:244-254` indexes row fields without nil
guards on individual entries — a hand-injected row missing
fields prints `0`/`-` defaults (safe by coercion `or 0`), but a
non-table row (e.g. `history = {"oops"}`) would crash on `r.type`
indexing.

**Recommend:** add
`if type(WHEREDNGNDB.history) ~= "table" then WHEREDNGNDB.history = {} end`
at both append and dump sites, and `if type(r) ~= "table" then
... end` skip in the dump loop. Mirrors the audit-blessed pattern
already at `State.lua:74` / `WHEREDNGN.lua:69`.
