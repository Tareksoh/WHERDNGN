# B-State-09 — Cumulative score management + telemetry pipeline

Scope: `State.lua` cumulative.A/B mutation paths, v0.9.6 v=2 telemetry
schema, `/baloot history` slash dump, hand-edit safety, per-character
vs per-account, score-boundary detection, negative-target cascade.

Files audited:
- `C:\CLAUDE\WHEREDNGN\State.lua`
- `C:\CLAUDE\WHEREDNGN\Slash.lua`
- `C:\CLAUDE\WHEREDNGN\Net.lua` (caller side; `_HostStepAfterTrick`,
  `_OnRound`, Takweesh, SWA)
- `C:\CLAUDE\WHEREDNGN\WHEREDNGN.lua` (`init` / restore-session
  target coercion)
- `C:\CLAUDE\WHEREDNGN\WHEREDNGN.toc`
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\audit_v0.9.0\47_telemetry_growth.md`

Conventions:
- Severity tiers: **CRIT** (game-state corruption / crash), **HIGH**
  (silent data loss / wrong analysis output / silent miscount),
  **MED** (degraded UX or confusing output, non-fatal), **LOW**
  (cosmetic / docs).
- "Repro" = exact step sequence reproducing the bug from a freshly
  loaded WoW client unless otherwise noted.

---

## Summary table

| ID  | Severity | Title |
|-----|----------|-------|
| 1   | PASS     | `s.cumulative.A/B` mutation: single canonical write site |
| 2   | PASS     | Per-round addA/addB → cum addition (totA/totB derivation) |
| 3   | LOW      | v=2 schema field for `forced` is undocumented in the comment block |
| 4   | HIGH     | v=2 forward-compat: dump still treats v=1 rows correctly **except** the schema-version filter is absent — analyzer must bear the entire burden |
| 5   | PASS     | v0.9.2 #47 type-guard at append + dump (both sites covered) |
| 6   | MED      | `/baloot history off` then `on` — no persistence test, but value is round-tripped through SavedVariables (PASS for the addon, but `historyEnabled = false` survives reload) |
| 7   | MED      | Hand-edit safety on `WHEREDNGNDB.history` — guards present, but `historyEnabled` itself is NOT type-guarded (a hand-edit `historyEnabled = "no"` would still gate to capture-on, since `"no" ~= false` is truthy) |
| 8   | HIGH     | Per-character vs per-account: still un-fixed since v0.9.0 #47. v=2 added `bidderIsBot` / `seatNBot` but **no `character` / `realm` field** — multi-character rows still interleave |
| 9   | MED      | Score-boundary detection: `>= s.target` short-circuits before the tiebreaker considers Gahwa winner correctly in **`_HostHandleTakweesh`** (Net.lua:2324–2334). Takweesh path uses bidder-team-on-tie, ignoring `bidderMade` — same bug `H3` already fixed in `_HostStepAfterTrick`. |
| 10  | HIGH     | Negative-target cascade: slash command rejects `< 21`, but **`s.target` is mutable from the wire** (Resync field 29) **without any range check** — a malicious or version-skewed host can push `s.target` to anything (negative, zero, huge), triggering an instant game-end on receivers (D-RT-14 ATK-4) |
| 11  | MED      | `s.target` re-assigned by `Net.SendResyncRes`/`ApplyResyncSnapshot` even when host omits — only positive override (`> 0`); negative payloads survive `tonumber` and the gate fails-open |
| 12  | LOW      | Dump line uses `r.bidderMade or -1` — the `or -1` short-circuit is wrong for `bidderMade=0` (false). Lua treats numeric 0 as truthy, so the printed `made=` field is stable, but the comment claiming `(bidderMade == false) and 0` should probably surface `0` for failed contracts — verify it does. (Sub-finding: harmless, format string %d still gets 0.) |
| 13  | MED      | Dump output lacks the v=2 fields entirely (`bidderIsBot`, `seat[N]Bot`, `forced`) — only v=1 fields are formatted. Calibration users running `/baloot history N` see no indication of which rows are bot-bidder. |
| 14  | LOW      | Cap-trim cost: `while #h > 200 do table.remove(h, 1) end` — covered in audit_v0.9.0 #47 PASS. No regression. |
| 15  | LOW      | `s.cumulative` table-init guarded at all known restore paths (`reset`, `RestoreSession`, `ApplyResyncSnapshot`). Verified PASS. |
| 16  | MED      | `S.ApplyRoundEnd` runs on host AND every client (no isHost gate); telemetry capture is **per-client × per-round**, so a 4-human game produces 4 rows for the same round — interleaved by the per-account SV. Compounds Finding 8. |

---

## 1. PASS — `s.cumulative` mutation paths

`s.cumulative.A` / `s.cumulative.B` are written in exactly two
locations:

```lua
-- State.lua:1463-1465 (S.ApplyRoundEnd)
function S.ApplyRoundEnd(addA, addB, totA, totB, sweep, bidderMade)
    s.cumulative.A = totA
    s.cumulative.B = totB
```

```lua
-- State.lua:450-452 (S.ApplyResyncSnapshot)
s.cumulative = s.cumulative or { A = 0, B = 0 }
s.cumulative.A = tonumber(f[16]) or 0
s.cumulative.B = tonumber(f[17]) or 0
```

Both are absolute assignments (`= totA`), not `+=` accumulators —
the addition is done **caller-side** in Net.lua before the call:

```lua
-- Net.lua:1679-1681 (_HostStepAfterTrick)
local totA = S.s.cumulative.A + addA
local totB = S.s.cumulative.B + addB
S.ApplyRoundEnd(addA, addB, totA, totB, res.sweep, res.bidderMade)
```

```lua
-- Net.lua:2261-2264 (Takweesh)
local totA = S.s.cumulative.A + addA
local totB = S.s.cumulative.B + addB
S.ApplyRoundEnd(addA, addB, totA, totB)
```

```lua
-- Net.lua:3045-3046 (SWA out)
local totA = (S.s.cumulative.A or 0) + addA
local totB = (S.s.cumulative.B or 0) + addB
```

Note the **inconsistent nil-guard**: only the SWA path uses
`(... or 0) + addA`. The other two trust `s.cumulative.A` is non-nil,
which is true post-init but would crash if `s.cumulative` were
somehow stripped to `nil` between rounds. Defensible — the
`reset()` and `RestoreSession()` paths both guarantee the table —
but the inconsistency is a code-smell.

**Verdict:** PASS. Single source of truth for the absolute write,
addition consistently externalized. No double-add risk.

---

## 2. PASS — Per-round addA/addB → totA/totB → cumulative

The flow on host is:

1. `R.ScoreRound` returns `{final = {A=N, B=M}, sweep, bidderMade,
   gahwaWonGame, gahwaWinner}`.
2. `_HostStepAfterTrick` extracts `addA, addB = res.final.A, res.final.B`.
3. Gahwa override (Net.lua:1669-1678) replaces `addA`/`addB` with
   `target - cumulative` to push the winner to game-end and zeroes
   the loser's add (v0.8.6 H2 fix).
4. `totA = cumulative.A + addA`; same for B.
5. `S.ApplyRoundEnd(addA, addB, totA, totB, ...)` writes
   `cumulative.A = totA` (absolute) and broadcasts via
   `N.SendRound(addA, addB, totA, totB, ...)`.
6. Each client's `_OnRound` calls `S.ApplyRoundEnd(...)` with the
   host-supplied totals — so client cumulatives are *replaced*, not
   recomputed. No drift possible.

**Verdict:** PASS. The "host adds, clients overwrite" pattern is
correct and resync-safe.

---

## 3. LOW — v=2 schema doc gap: `forced` undocumented

`State.lua:1534-1542` is the v0.9.6 enrichment block:

```lua
-- v0.9.6 telemetry enrichment (audit_v0.9.0/41_v083_telemetry.md):
--  • schemaVersion `v=2` — forward-compat for the calibrator
--  • per-seat isBot snapshot — calibration NEEDS to separate
--    "the BOT is mis-bidding" vs "the HUMAN is mis-bidding";
--    otherwise the bidder-fail-rate signal is uninterpretable.
--  • bidderIsBot — convenience derivation, same info but
--    pre-resolved for analyzer.
-- v=1 rows (pre-v0.9.6) lack these fields; the analyzer handles
-- both schemas via field-presence checks.
```

But the row literal also includes `forced = s.contract.forced and 1
or 0` (State.lua:1566) — this field isn't called out as a v=2
addition. Was it present in v=1? The comment block doesn't say,
so an external calibration script using "field presence" to
distinguish schemas may misclassify rows.

**Severity:** LOW — analytic correctness only. No runtime impact.

**Repro:** read the comment block, look for `forced` — absent.

---

## 4. HIGH — Forward-compat: no schema-version filter at dump or analyzer site

`State.lua` only ever appends rows with `v = 2`. Pre-v0.9.6 rows
(`v == nil` or `v == 1`) are still on disk for any user who
upgraded mid-stream. The dump path:

```lua
-- Slash.lua:248-264
for i = startIdx, total do
    local r = h[i]
    if type(r) == "table" then
        print(("  r%-3d  %-4s  trump=%-1s bidder=%d  Δ=%+d/%+d  ..."):format(
            r.roundNumber or 0, r.type or "?",
            r.trump or "-", r.bidder or 0,
            r.addA or 0, r.addB or 0,
            ...))
    end
end
```

The dump uses **only v=1 fields** with `or` defaults. v=2 rows
print fine because all v=1 fields are still emitted. But:

1. The dump does NOT show `bidderIsBot`, `seat[N]Bot`, or
   `forced` — making the v=2 enrichment **invisible to the user**
   running the slash command.
2. There's no schema-version label in the print line, so a user
   debugging "why are old rows weird?" can't tell v=1 from v=2.
3. **No upgrade path / no scrub.** A user with 200 rows of v=1
   on disk gets a permanent FIFO mix until 200 v=2 rows have
   accumulated (i.e., 200 round-ends across all characters on
   that account).

Forward-compat **at-read** is fine because `or` defaults paper
over missing fields. Forward-compat **at-analyzer** is the actual
gap, but the comment claims the analyzer "handles both schemas
via field-presence checks" — there's no analyzer in this repo,
so this can't be verified. Trust-but-document.

**Severity:** HIGH — silent quality degradation for calibration
users; the headline reason for the v0.9.6 enrichment was to
separate bot-bidder from human-bidder rows, and the dump itself
does not show that separation.

**Repro:**
1. `/baloot history off`, hand-edit `WHEREDNGNDB.history` to
   inject one v=1 row + one v=2 row.
2. `/baloot history on`, `/baloot history 5`.
3. Observe: both rows print identically; no `v=` label, no
   bidderIsBot column.

**Quote (the gap):**
```lua
-- v=1 rows (pre-v0.9.6) lack these fields; the analyzer handles
-- both schemas via field-presence checks.
```
…but neither the `Slash.lua` dump nor any in-repo analyzer
demonstrates the field-presence handling.

---

## 5. PASS — v0.9.2 #47 type-guard at append + dump

Both sites have the `type(...) ~= "table"` guard now:

```lua
-- State.lua:1530-1533 (append)
if type(WHEREDNGNDB.history) ~= "table" then
    WHEREDNGNDB.history = {}
end
local h = WHEREDNGNDB.history
```

```lua
-- Slash.lua:237-238 (dump)
local h = WHEREDNGNDB.history
if type(h) ~= "table" then h = {} end
```

```lua
-- Slash.lua:253-264 (per-row guard in dump loop)
if type(r) == "table" then
    print(...)
end
```

All three guards mirror the audit_v0.9.0/47 recommendation:
- Top-level type-guard at both append and dump
- Per-row guard in the dump loop (skips non-table rows silently)

**Verdict:** PASS. Hand-edited `history = "junk"`, `history = 5`,
or `history = {"oops"}` cannot crash either path.

---

## 6. MED — `historyEnabled` value not range-checked

```lua
-- State.lua:1522 (gate)
if WHEREDNGNDB and WHEREDNGNDB.historyEnabled ~= false and s.contract then
```

```lua
-- Slash.lua:224-231
elseif histArg == "off" then
    WHEREDNGNDB.historyEnabled = false
    say("history capture OFF (existing rows preserved)")
    return
elseif histArg == "on" then
    WHEREDNGNDB.historyEnabled = true
    say("history capture ON")
    return
```

The `~= false` gate is **explicit-equality**. So the only value
that disables capture is the literal Lua `false`. Any other type
(`"off"`, `0`, `nil`, `{}`, `"no"`, table, etc.) is **truthy** for
this gate's purpose. Hand-edit `historyEnabled = "off"` →
capture stays ON.

This is partially intentional (`historyEnabled = nil` defaults to
ON), but a user reading the docs and writing `historyEnabled =
"no"` in their SV file would silently keep capturing.

**Severity:** MED — hand-edit safety only; no crash, no privacy
issue, just unexpected non-disable on a typo'd hand edit.

**Repro:** `WHEREDNGNDB.historyEnabled = 0` → capture stays on.

**Quote:**
```lua
if WHEREDNGNDB and WHEREDNGNDB.historyEnabled ~= false and s.contract then
```

---

## 7. MED — Hand-edit safety: `historyEnabled` not type-guarded; `WHEREDNGNDB.target` only at init paths

`WHEREDNGNDB.target` IS coerced through `tonumber(...) or 152` at
both PLAYER_LOGIN init and post-RestoreSession (WHEREDNGN.lua:81,
152). PASS. But:

- `WHEREDNGNDB.historyEnabled` — only checked via `~= false`. No
  `type() == "boolean"` enforcement (Finding 6).
- `WHEREDNGNDB.history` — type-guarded at append + dump (Finding 5).
- `s.target` itself — the slash command rejects `< 21`
  (Slash.lua:279-281), but **the resync wire path bypasses this**
  (Finding 10).

The pattern is **inconsistent**: top-level (`WHEREDNGNDB`),
`history`, and `target` are all type/range guarded at their
canonical entry points, but `historyEnabled` is the odd one out.

**Severity:** MED — hand-edit only.

---

## 8. HIGH — Per-character vs per-account telemetry: STILL UNFIXED

The v0.9.6 v=2 schema added bot/human seat flags but **did not
address the per-account interleave** flagged in audit_v0.9.0/47:

```toc
## SavedVariables: WHEREDNGNDB
```

(`WHEREDNGN.toc:7`) — per-account, not per-character. Any
character on the same account writes into the same
`WHEREDNGNDB.history` table. The v=2 row schema (State.lua:1550-
1578) has no `character`, `realm`, or `accountID` field:

```lua
local row = {
    v            = 2,
    roundNumber  = s.roundNumber or 0,
    ts           = (GetTime and GetTime()) or 0,
    type         = s.contract.type,
    trump        = s.contract.trump,
    bidder       = bidder,
    bidderIsBot  = bidderIsBot,
    seat1Bot     = seatIsBot[1],
    seat2Bot     = seatIsBot[2],
    seat3Bot     = seatIsBot[3],
    seat4Bot     = seatIsBot[4],
    ...
    localSeat    = s.localSeat or 0,
}
```

`localSeat` is the only "who am I" field, but it's just an int 1–4
relative to the current game's seat assignment. Two different
games on two different characters can both have `localSeat=2` —
the rows are **indistinguishable** without a character / realm
field. The audit_v0.9.0/47 finding stated:

> Recommend either `r.character = UnitName("player")` per row OR
> document the per-account interleave.

Neither has been done. The v=2 enrichment specifically calls out
"calibration NEEDS to separate bot-bidder from human-bidder rows"
— but if rows from two different characters interleave, even
that separation is ambiguous (which character was the
human-bidder?).

**Severity:** HIGH — silently degrades calibration validity for
any multi-character user. The fix is trivial (one line:
`character = UnitName("player") or "?"`).

**Repro:**
1. Log into character A, play 1 round → 1 row appended.
2. /reload, log into character B, play 1 round → 1 row appended
   alongside.
3. `/baloot history 5` — both rows print, no character label.

**Quote:**
```lua
-- State.lua:1550-1578 — schema v=2 row literal
-- (no character / realm / accountID field)
```

Compounded by Finding 16: every CLIENT in a 4-human game also
appends, so **N rows per round per game** if multiple humans use
the addon. With per-account SV, that's an N×M interleave.

---

## 9. MED — Score-boundary detection: tiebreaker bug in Takweesh path

`_HostStepAfterTrick` (Net.lua:1683-1711) has the **v0.8.6 H3 fix**
that respects `gahwaWinner` and `bidderMade` for the tiebreaker.
But the **Takweesh** path (Net.lua:2324-2334) still has the OLD
buggy logic:

```lua
-- Net.lua:2324-2334 (Takweesh tiebreaker)
if totA >= S.s.target or totB >= S.s.target then
    -- Same Saudi tie-rule as the normal-round path above.
    local winner
    if totA == totB and S.s.contract and S.s.contract.bidder then
        winner = R.TeamOf(S.s.contract.bidder)        -- BUG
    elseif totA > totB then winner = "A"
    elseif totB > totA then winner = "B"
    else                    winner = "A" end
    S.ApplyGameEnd(winner)
    N.SendGameEnd(winner)
end
```

Versus the fixed _HostStepAfterTrick at Net.lua:1683-1711:

```lua
local winner
if totA == totB then
    if res.gahwaWonGame and res.gahwaWinner then
        winner = res.gahwaWinner
    elseif S.s.contract and S.s.contract.bidder then
        local bidderTeam = R.TeamOf(S.s.contract.bidder)
        if res.bidderMade then
            winner = bidderTeam       -- bidder made → they win tie
        else
            winner = (bidderTeam == "A") and "B" or "A"
                                      -- bidder failed → opp won round
        end
    else
        winner = "A"                  -- defensive fallback
    end
elseif totA > totB then winner = "A"
elseif totB > totA then winner = "B"
else                    winner = "A" end
```

The Takweesh path:
- Awards the tie to the **bidder team** unconditionally, even
  when the Takweesh penalty was *because the bidder team did
  something illegal* — the same H3 bug as before fix.
- Does NOT consider `gahwaWonGame` (granted, Gahwa+Takweesh is
  unlikely, but R.ScoreRound's `fail` path can still produce a
  Gahwa-flagged round, which Takweesh never inspects).
- Does NOT consider `bidderMade` from a prior result (Takweesh
  bypasses ScoreRound entirely — defensible).

The SWA-out tiebreaker (Net.lua:3062-3071) has the **same bug**:

```lua
-- Net.lua:3062-3071 (SWA-out tiebreaker)
if totA >= S.s.target or totB >= S.s.target then
    local winner
    if totA == totB and S.s.contract and S.s.contract.bidder then
        winner = R.TeamOf(S.s.contract.bidder)        -- BUG (same H3)
    elseif totA > totB then winner = "A"
    elseif totB > totA then winner = "B"
    else                    winner = "A" end
    S.ApplyGameEnd(winner)
    N.SendGameEnd(winner)
end
```

For SWA, this is more dangerous: an INVALID SWA call flips the
"contract resolution" — bidder may be the *loser* of the round,
yet still win the match on a tie because `R.TeamOf(s.contract.
bidder)` is read raw.

**Severity:** MED — both bugs only fire on an exact-tie at the
target, which is rare. But identical to the v0.8.6 H3 setup that
was previously fixed in one path and missed in two others.

**Repro (Takweesh):**
1. Set up `cumulative = {A=147, B=147}`, target=152.
2. Bidder is on team A, calls a contract.
3. Defender team B calls Takweesh and is wrong → penalty pushes
   `addA=5, addB=0` → `totA=152, totB=147`. (No tie.)
4. Reverse: bidder is on team B but team A's player commits the
   illegal; Takweesh penalty produces a tie at 152/152. Tiebreaker
   awards team B (the bidder team) even if B's contract was
   the one being blown up.

**Repro (SWA-out):**
Set up `cumulative = {A=120, B=120}`, target=152.
Bidder on team A makes invalid SWA → penalty produces
`addA=0, addB=32` → `totA=120, totB=152`. Now reverse: tie at
152/152 — code awards bidder team A even though bidder failed.

**Quote (the bug, both copies):**
```lua
if totA == totB and S.s.contract and S.s.contract.bidder then
    winner = R.TeamOf(S.s.contract.bidder)
```

Recommendation: lift the H3 tiebreaker logic into a shared helper
called from all three sites.

---

## 10. HIGH — Negative-target cascade via wire (D-RT-14 ATK-4)

`Slash.lua:271-288` rejects targets `< 21` at the user-input
boundary:

```lua
local tNum = msg:match("^target%s+(%d+)$")
if tNum then
    local n = tonumber(tNum) or 0
    if n < 21 then
        say("target must be at least 21 (Saudi sub-game minimum)")
        return
    end
    WHEREDNGNDB = WHEREDNGNDB or {}
    WHEREDNGNDB.target = n
    B.State.s.target = n
```

But the wire path in `S.ApplyResyncSnapshot` accepts ANY positive
target without an upper bound:

```lua
-- State.lua:502-507
-- Audit Tier 4 (B-69): decode match target if present (field 29).
-- Pre-v0.4.5 hosts omit this field; preserve the existing s.target
-- on those replies. Required by Audit Tier 4 (B-69).
local targetField = tonumber(f[29])
if targetField and targetField > 0 then
    s.target = targetField
end
```

Note the inconsistency:
1. **No lower bound** — the slash gate is `< 21`; the wire gate
   is `> 0`. So a wire target of `1` is accepted (instant game-
   end after any non-empty round).
2. **No upper bound** — a wire target of `999999` is accepted,
   leaving the receiver effectively unable to reach game-end.
3. **Negative target survives** — `tonumber("-5")` returns `-5`;
   the `> 0` gate filters it. PASS for negatives. But:
4. **Zero is rejected by `> 0`**, but the slash command rejects
   `< 21`, so the two gates disagree on `[1, 20]`.

D-RT-14 ATK-4: a malicious or version-skewed host sends a wire
snapshot with `target=1`. Receivers update `s.target = 1`. Any
non-empty round triggers `cumulative.A >= 1` → instant game-end.
The host can dictate the game outcome on any seat that resyncs.

For receivers, this propagates to `WHEREDNGNDB.target` ONLY if
the user *runs `/baloot target N`* later — so the wire-set
`s.target` is in-memory only. But it's still authoritative
during the active game on that client, and the game-end check
runs on receiver-side too (UI.lua:2054 — though that's a UI
gate, not authoritative).

**Severity:** HIGH — D-RT-14 ATK-4 was specifically about
"no range-check on target reads". The slash command got the
fix; the wire path did not.

**Repro:**
1. Modified host sends `MSG_RESYNC_RES` with field 29 = `"5"`.
2. Receiver: `s.target = 5` (`5 > 0` passes).
3. Next round-end: `cumulative.A` exceeds 5 trivially → UI shows
   game-end, "Next Round" button gates off.

**Quote:**
```lua
-- State.lua:505-507
local targetField = tonumber(f[29])
if targetField and targetField > 0 then
    s.target = targetField
end
```

Recommendation: mirror the slash-command gate:
```lua
if targetField and targetField >= 21 and targetField <= 1000 then
    s.target = targetField
end
```

---

## 11. MED — Resync target gate is fail-OPEN, not fail-CLOSED

Related to Finding 10 but distinct: the wire gate is
`if targetField and targetField > 0`. If the host omits field 29
(pre-v0.4.5), `targetField` is `nil`, the if-branch is skipped,
and `s.target` is **preserved** on the receiver. PASS for the
"old host" case.

But if the host sends `target = "abc"` (corrupted / version-
skewed serializer), `tonumber("abc")` returns `nil`, the gate
skips, `s.target` is preserved. PASS.

If the host sends `target = "0"`, `tonumber` returns 0, gate is
`> 0`, false, skip. `s.target` preserved. PASS.

If the host sends `target = "-1"`, `tonumber` returns -1, gate
`> 0`, false, skip. `s.target` preserved. PASS.

If the host sends `target = "2"`, `tonumber` returns 2, gate
`> 0`, true, **`s.target = 2`**. FAIL (Finding 10).

So the gate is correct for nil/non-numeric/zero/negative inputs
but wrong for low-positive inputs. It's "fail-open for low-
positive numbers", not fully fail-closed.

**Severity:** MED. Same root as Finding 10, called out
separately for clarity.

---

## 12. LOW — Dump format `r.bidderMade or -1` short-circuit

```lua
-- Slash.lua:261
r.bidderMade or -1,
```

The append site (State.lua:1574-1575) writes:
```lua
bidderMade = (bidderMade == true) and 1
             or (bidderMade == false) and 0 or -1,
```

So `r.bidderMade` is always one of `1` (made), `0` (failed), `-1`
(unknown / nil at append-time). All three are numbers. Lua's
`or` only short-circuits on `nil`/`false`, so `r.bidderMade or
-1` returns `r.bidderMade` for all three values. Format string
`%d` gets a valid int.

**Verdict:** PASS — the formatter works. But the `or -1` adds
visual noise that suggests a defensive fallback that is in fact
already encoded at the append site.

**Severity:** LOW (cosmetic).

---

## 13. MED — Dump output omits v=2 fields (`bidderIsBot`, `seatNBot`, `forced`)

```lua
-- Slash.lua:254-263 — dump format string
print(("  r%-3d  %-4s  trump=%-1s bidder=%d  Δ=%+d/%+d  cum=%d/%d  bel=%d trp=%d for=%d gah=%d  swp=%s  made=%d  br%d  bidc=%s"):format(
    r.roundNumber or 0, r.type or "?",
    r.trump or "-", r.bidder or 0,
    r.addA or 0, r.addB or 0,
    r.totA or 0, r.totB or 0,
    r.doubled or 0, r.tripled or 0, r.foured or 0, r.gahwa or 0,
    (r.sweep ~= "" and r.sweep) or "-",
    r.bidderMade or -1,
    r.bidRound or 0,
    r.bidCard or "-"))
```

The v=2 fields added by State.lua:1543-1567 are NOT in the format
string:
- `bidderIsBot`
- `seat1Bot`, `seat2Bot`, `seat3Bot`, `seat4Bot`
- `forced`

The headline reason for v0.9.6 was to make calibration distinguish
bot-bidder from human-bidder. The slash command — the user-
facing telemetry surface — does not show this distinction. A
user running `/baloot history 20` to triage scoring sees the
same lines as v0.9.5.

**Severity:** MED — defeats much of the v0.9.6 enrichment for
the in-game user. External calibration scripts that read
`WHEREDNGNDB.history` directly are unaffected.

**Repro:**
1. Play one round with all 4 seats as humans → row has
   `bidderIsBot=0`, `seatNBot=0`.
2. Play one round with all 3 non-host seats as bots → row has
   `bidderIsBot=0` or `1` depending on bidder, seat flags
   non-zero.
3. `/baloot history 5` — both rows print identically.

**Quote (no v=2 fields in print):**
```lua
print(("  r%-3d  %-4s  trump=%-1s bidder=%d  Δ=%+d/%+d  ..."):format(
    r.roundNumber or 0, r.type or "?",
    r.trump or "-", r.bidder or 0,
    ...))
```

---

## 14. PASS — Cap-trim cost

Already audited in v0.9.0 #47: append-then-trim with
`while #h > 200 do table.remove(h, 1) end` is O(n) per shift but
n is bounded. No regression.

---

## 15. PASS — `s.cumulative` table-init defensive

Three init/restore paths all guarantee `s.cumulative = { A = 0,
B = 0 }`:

```lua
-- State.lua:63 (reset)
s.cumulative  = { A = 0, B = 0 }

-- State.lua:338 (RestoreSession)
s.cumulative   = s.cumulative   or { A = 0, B = 0 }

-- State.lua:450 (ApplyResyncSnapshot)
s.cumulative = s.cumulative or { A = 0, B = 0 }
```

No path leaves `s.cumulative` as nil. The `+` arithmetic at
Net.lua:1679-1680 and 2261-2262 is safe.

---

## 16. MED — Per-client telemetry duplication

`S.ApplyRoundEnd` runs unconditionally on every connected client
(via `_OnRound` at Net.lua:1503-1508):

```lua
function N._OnRound(sender, addA, addB, totA, totB, sweep, bidderMade)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    S.ApplyRoundEnd(addA, addB, totA, totB, sweep, bidderMade)
end
```

`ApplyRoundEnd` then runs the telemetry-append block
(State.lua:1522-1584) **without an `isHost` gate**. So in a
4-human game, every round produces 4 separate rows in 4 separate
`WHEREDNGNDB` files — one per client. Each row has the same
contract / scores / cum-totals, just a different `localSeat`.

For a single-player-with-bots game (the common case), this is
fine — only the host writes a row. But for multi-character users
on the same account (Finding 8), or for a future federated /
shared-account telemetry dump, the per-client per-round
duplication compounds the per-account interleave.

The append site's comment says:
```lua
-- One row per round per client. Captures contract shape, ...
```

So this is **documented behavior** — the audit lists it for
completeness; it's not a bug.

**Severity:** MED — clarity / docs only; intentional design.

---

## Cross-cutting concerns

### A. Inconsistent nil-guard pattern on `s.cumulative`

- Net.lua:1679–1680 (HostStep): `s.cumulative.A + addA` — no `or 0`.
- Net.lua:2261–2262 (Takweesh): same pattern.
- Net.lua:3045–3046 (SWA): `(s.cumulative.A or 0) + addA` — has `or 0`.

Either style is correct given the init guarantees of Finding 15,
but the inconsistency invites future refactor bugs.

### B. Tiebreaker logic duplicated 3 times, fixed in only 1

Findings 9 + the v0.8.6 H3 history make a strong case for
extracting the `> target` tiebreaker into one helper:
- `_HostStepAfterTrick` (FIXED v0.8.6 H3)
- `_HostHandleTakweesh` (BUGGED, missing fix)
- `_HostHandleSWAOut` (BUGGED, missing fix)

### C. Range-check inconsistency on `target`

| Source | Lower | Upper | Fail-mode |
|--------|-------|-------|-----------|
| `/baloot target N` | >= 21 | none | reject |
| WHEREDNGN.lua init | tonumber, default 152 | none | default-fallback |
| Resync wire | > 0 | none | accept |

Recommendation: unify on `>= 21 && <= 1000`, applied at every
external entry point.

---

## Verdict

The cumulative score management itself is structurally sound
(Findings 1, 2, 15 PASS) and the v0.9.2 #47 type-guards on the
history table are complete (Finding 5 PASS).

The **v0.9.6 enrichment is incomplete**: schema v=2 added bot
flags but (a) the slash dump doesn't display them (Finding 13),
(b) per-character interleave is still un-fixed (Finding 8),
(c) `forced` field is silently part of v=2 without doc (Finding 3).

The **target/boundary surface is the highest-risk area**:
- Wire path bypasses the range-check (Finding 10 — D-RT-14 ATK-4)
- Tiebreaker bug duplicated 3× and only fixed once (Finding 9)

**Recommended next-tag work** (priority order):
1. Mirror the slash `>= 21` gate into `S.ApplyResyncSnapshot`
   (Finding 10).
2. Extract tiebreaker helper, call from all 3 `>= target` sites
   (Finding 9).
3. Add `r.character = UnitName("player")` to the row literal
   (Finding 8).
4. Extend the slash dump format with v=2 fields, or add a
   schema-aware `--full` mode (Finding 13).
5. Add type-guard for `WHEREDNGNDB.historyEnabled` to enforce
   boolean (Finding 6/7).
