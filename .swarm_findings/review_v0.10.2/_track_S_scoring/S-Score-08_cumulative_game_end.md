# S-Score-08 — Cumulative score + game-end target detection

## 1. TL;DR

- **Game target = 152** game points, configurable via `/baloot target <N>` (≥21).
  Default lives in `WHEREDNGN.lua:17`, `State.lua:75`, `WHEREDNGN.lua:81`.
  No `K.GAME_TARGET` constant — the value is a hard-coded literal `152`
  in **6 places**. Should be a `K.*` constant for grep-discoverability.
- **Cumulative tracking** is sound. `S.s.cumulative.{A,B}` is updated
  in exactly one place: `S.ApplyRoundEnd` (State.lua:1463-1465) which
  receives `(addA, addB, totA, totB, ...)` from the host's
  `_HostStepAfterTrick`. Non-host receives via `_OnRound` → same call.
  Round delta is round-end via `R.ScoreRound` (game-points, not raw).
- **Game-end detection** fires from THREE host paths, all with
  `if totA >= S.s.target or totB >= S.s.target`. Tiebreak rule
  diverges across the three paths (see §6 — Bug 2).
- **Gahwa match-win override**: confirmed at Net.lua:1707-1716 —
  forces winner cumulative to target and zeros loser delta (v0.8.6 H2
  fix). `Rules.lua:957-968` flags `gahwaWonGame` regardless of
  `bidderMade`, with `gahwaWinner = bidderTeam` if made else `oppTeam`.
- **`Rules.lua:957-968` Gahwa match-win is type-blind.** The branch
  fires on `if contract.gahwa then` with no `contract.type ~= K.BID_SUN`
  guard. Sun cannot reach `PHASE_GAHWA` structurally so this is a
  defensive (HIGH→MED, per ship-readiness audit) concern. The line
  number cited as `Rules.lua:928` in the prior summary is approximate;
  the actual `if contract.gahwa then` is at **Rules.lua:959** post-v0.10.0.
- **Sun-Bel cumulative gate** correctly reads `S.s.cumulative[team]`
  via `R.CanBel` (Rules.lua:586-590) and `N._SunBelAllowed`
  (Net.lua:68-83). Symmetric, role-irrelevant per v0.10.0 R1 fix.
- **No "automatic new game"**. After PHASE_GAME_END, only `S.Reset()`
  zeroes cumulative — invoked via `/baloot reset` or UI Reset popup.

---

## 2. Game target value + source

### Constant location

| Source | Path | Line | Value |
|---|---|---|---|
| Default DB | `WHEREDNGN.lua` | 17 | `target = 152` |
| State init | `State.lua` | 75 | `s.target = (DB and tonumber(DB.target)) or 152` |
| DB hydration | `WHEREDNGN.lua` | 81 | `B.State.s.target = tonumber(WHEREDNGNDB.target) or 152` |
| Slash setter | `Slash.lua` | 271-287 | `/baloot target <N>` (rejects N < 21) |
| Resync target | `Net.lua` | 379-382 | encoded as field 29 of MSG_RESYNC_RES |
| Telemetry | `State.lua` | 1576 | `target = s.target or 152` (history row) |
| Bot urgency | `Bot.lua` | 991, 1029, 1060, 3402 | `local target = (S.s.target or 152)` |

**No `K.GAME_TARGET` constant.** All callers default-to-152 with the
`(S.s.target or 152)` idiom. This is fragile — a `K.GAME_TARGET = 152`
constant would centralize and document the canonical value.

### Cross-ref with saudi-rules.md

`saudi-rules.md` does NOT explicitly state the cumulative-target value.
It documents only:
- `HAND_TOTAL_HOKM = 162` (152 cards + 10 last trick) — saudi-rules.md:39
- "Half-and-half tiebreak" — within-round 81/162 rule (saudi-rules.md:236-238)

`glossary.md:159` lists `Match target | 152 raw | S.s.target` — but
**this label is misleading**. `S.s.cumulative` accumulates `final = div10(raw)`
(game points = raw/10), not raw. So 152 game points ≈ 1520 raw — about
9-10 normal Hokm rounds (handTotal = 162 raw = 16 gp). The glossary's
"raw" qualifier should be removed.

### Verdict

Default 152 is plausible (consistent with Saudi convention of
"first to 152"). No transcript verbatim confirms the target value
(videos #28 + #43 cover round-level scoring, not match length). The
constant being user-tunable to ≥21 means custom games at any target
work. **No game-target value bug found.**

---

## 3. Cumulative tracking trace

### Update path (host)

1. Round ends in `_HostStepAfterTrick` (Net.lua:1687-1751).
2. Host calls `S.HostScoreRoundResult()` → `R.ScoreRound` → returns
   `result.final.{A,B}` (game points, post-`div10`).
3. Net.lua:1717-1719:
   ```lua
   local totA = S.s.cumulative.A + addA
   local totB = S.s.cumulative.B + addB
   S.ApplyRoundEnd(addA, addB, totA, totB, res.sweep, res.bidderMade)
   ```
4. `S.ApplyRoundEnd` (State.lua:1463-1465):
   ```lua
   s.cumulative.A = totA
   s.cumulative.B = totB
   ```

### Update path (non-host)

1. Host broadcasts MSG_ROUND with `(addA, addB, totA, totB, sweep, bidderMade)`.
2. Wire decoded in `N.HandleMessage` → `N._OnRound` (Net.lua:1541-1546).
3. `_OnRound` → `S.ApplyRoundEnd(addA, addB, totA, totB, sweep, bidderMade)`.

The wire carries `totA/totB` directly so non-hosts trust host's sum.
This avoids drift from missed/replayed packets but means a malicious
host could report any total — irrelevant for friend games but a
red-team consideration noted in track-D.

### Reset paths

- `S.Reset()` (State.lua:542 alias of `reset` at line 33+) initializes
  `s.cumulative = { A = 0, B = 0 }` (line 63).
- Reset is called from:
  - `/baloot reset` slash command
  - UI "Reset" button (UI.lua:512)
  - `Net.lua:720` (lobby new-game branch via `S.ApplyLobby` decision)
  - resync hint cleanup
- `S.HostStartRound` (Net.lua:1823) does **NOT** reset cumulative —
  rounds within a game accumulate. Confirmed at line 1838-1844 (only
  bot-memory and bot-style reset; no cumulative touch).

### Verdict

Cumulative tracking is **CORRECT**. Single update site, single reset
site, well-bounded.

---

## 4. Game-end detection trace

### THREE distinct host call sites — each with its own tiebreak

#### Site A — Normal round end (Net.lua:1721-1750)

```lua
if totA >= S.s.target or totB >= S.s.target then
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
    S.ApplyGameEnd(winner)
    N.SendGameEnd(winner)
end
```

This is the **canonical, post-v0.8.6 H3 fix tiebreak**: respects
Gahwa winner first, then `bidderMade` (so a failing bidder doesn't
get awarded a tie they didn't earn).

#### Site B — Takweesh penalty (Net.lua:2362-2372)

```lua
if totA >= S.s.target or totB >= S.s.target then
    local winner
    if totA == totB and S.s.contract and S.s.contract.bidder then
        winner = R.TeamOf(S.s.contract.bidder)   -- ⚠ raw bidder team
    elseif totA > totB then winner = "A"
    elseif totB > totA then winner = "B"
    else                    winner = "A" end
    S.ApplyGameEnd(winner)
    N.SendGameEnd(winner)
end
```

**No bidderMade adjustment.** A Takweesh that pushes both teams to
the target with `totA == totB` would award the match to the bidder
team — even though Takweesh always penalizes the offender (by
definition the penalty makes the **non-offending** team the winner
of the round).

#### Site C — SWA invalid penalty (Net.lua:3091-3100)

```lua
if totA >= S.s.target or totB >= S.s.target then
    local winner
    if totA == totB and S.s.contract and S.s.contract.bidder then
        winner = R.TeamOf(S.s.contract.bidder)   -- ⚠ raw bidder team
    elseif totA > totB then winner = "A"
    elseif totB > totA then winner = "B"
    else                    winner = "A" end
    S.ApplyGameEnd(winner)
    N.SendGameEnd(winner)
end
```

Same divergence as Site B. SWA penalty paths can leave bidder team
as the loser of the round but the winner of a match-tied game-end.

### S.ApplyGameEnd

```lua
function S.ApplyGameEnd(winnerTeam)
    if s.phase == K.PHASE_GAME_END and s.winner == winnerTeam then
        return  -- idempotent
    end
    s.phase = K.PHASE_GAME_END
    s.winner = winnerTeam
end
```

State change is minimal — phase + winner. No automatic reset; the
host (or any client) must `/baloot reset` to start over.

### Non-host

`N._OnGameEnd` (Net.lua:1548-1553) replays `S.ApplyGameEnd(winner)`
on receipt of MSG_GAMEEND. Note: non-host does **not** independently
detect game-end from `_OnRound`'s totals — it trusts the host's
explicit MSG_GAMEEND. This is correct (host is authoritative) but
means a host that crashes between `_OnRound` and `_OnGameEnd` leaves
clients in PHASE_SCORE forever. Resync would recover via the
`s.target` field (29) in MSG_RESYNC_RES.

---

## 5. Gahwa match-win correctness (Rules.lua:928 type-blind verification)

### The actual line numbers

The prior summary cited `Rules.lua:928`. Post-v0.10.0 line numbering
makes that line `local rawA = (cardA + meldPoints.A) * mult`. The
**actual Gahwa match-win branch is Rules.lua:957-968**:

```lua
local gahwaWonGame = false
local gahwaWinner
if contract.gahwa then
    if bidderMade then
        gahwaWinner = bidderTeam
    else
        gahwaWinner = oppTeam
    end
    gahwaWonGame = true
end
```

### Type-blindness verified

There is **no** `contract.type ~= K.BID_SUN` filter. The multiplier
path at Rules.lua:914-924 correctly collapses Sun-tripled/foured/gahwa
to Sun-Bel-max (v0.10.0 R2 fix), but the match-win branch does NOT
mirror that gate.

### Reachability

- **Live wire pipeline**: Sun cannot reach PHASE_GAHWA. State machine
  jumps Sun directly to PHASE_PLAY after PHASE_DOUBLE
  (`State.ApplyDouble` per the comment at Rules.lua:874-876).
- **Stale state vector**: hand-edited `WHEREDNGNDB.session` with
  `contract = { type = K.BID_SUN, gahwa = true }`, or a forged wire
  frame (MSG_FOUR;1 → MSG_GAHWA;<bidder>) on a desynced peer.
- **Impact on hit**: round ends with `gahwaWonGame = true`,
  `_HostStepAfterTrick` (Net.lua:1707-1716) forces winner cumulative
  to target, zeros loser delta, declares match over. Recovery requires
  fresh game.

### Bidder make/fail correctness

Per Rules.lua:962-966:
- `bidderMade == true` → `gahwaWinner = bidderTeam` (bidder team wins match) ✓
- `bidderMade == false` → `gahwaWinner = oppTeam` (defenders win match) ✓

This part is **correct** for all `bidderMade` outcomes, including
the doubled-tie inversion (Rules.lua:838-842 sets `outcome_kind =
"take"` → `bidderMade = true` for `highest in {double, four}`; or
"fail" otherwise). For a Gahwa contract the `highest` is "gahwa", so
inversion routes to "fail" — bidder failure → defenders win match.
This matches the canonical Saudi rule.

### Failed-Gahwa double-impact (B-State-05 F-07)

A side-finding noted in the prior B-track audits: when a Gahwa fails,
the per-round `cardA/cardB` path (Rules.lua:854-871) ALSO runs the
qaid penalty (`handTotal × MULT_FOUR` to defenders). Both consumers
fire — the per-round delta + the match-win flag. The Net.lua override
at 1707-1716 zeros the loser's delta, so the doubled impact is
neutralized in practice. **No live bug**, but the comment at
Rules.lua:820-824 acknowledges the path is reachable from SWA/Takweesh
penalty contexts that don't trigger the override.

---

## 6. Tiebreak rules

### Within-round (saudi-rules.md "Half-and-half")

**81 of 162 ties → bidder fails.** Encoded at Rules.lua:790-842 via
`outcome_kind` decision. ✓ Confirmed correct.

### Cumulative-tied at game-end (across rounds)

**No explicit Saudi rule found.** saudi-rules.md scoring-quirks
covers only the 81/162 within-round case. Code's behavior:

| Path | Tiebreak | Notes |
|---|---|---|
| Site A (normal) | Gahwa-winner > bidder-made-side > defensive "A" | v0.8.6 H3 fix — canonical |
| Site B (Takweesh) | Raw bidder team | Pre-v0.8.6 logic — divergent |
| Site C (SWA) | Raw bidder team | Pre-v0.8.6 logic — divergent |

This **divergence** is Bug #2 below.

### Big-round overshoot

Per Net.lua:1717-1719, `totA = cumulative.A + addA`. There is **no
clamp**. If pre-round cumulative is 30 and a Sun + Bel + Carré-A +
Al-Kaboot round nets 124+ gp, `totA = 154` — and `totA >= S.s.target`
fires game-end with the actual overshoot value. Display shows the
real total (154), not 152. **Correct behavior** — no bug.

### Both teams cross same round

If both `totA >= 152` and `totB >= 152` simultaneously and
`totA ~= totB`, the higher value wins (lines 1745-1747). On exact
tie, the canonical Site A path uses the v0.8.6 H3 logic. The two
penalty paths fall back to raw-bidder-team — which can be incorrect
(see Bug #2).

---

## 7. Bugs found

### Bug #1 — `Rules.lua:957-968` Gahwa match-win is type-blind (HIGH→MED, defensive)

- **Site**: `Rules.lua:959` `if contract.gahwa then`
- **Description**: No `contract.type ~= K.BID_SUN` guard. A stale
  Sun contract carrying `gahwa = true` (via SVars edit, replay frame,
  or future bug) would trigger an unintended match-win.
- **Severity**: MED. Live wire pipeline cannot reach this — Sun
  contracts skip PHASE_GAHWA per State.ApplyDouble. Downgraded from
  HIGH per `REVIEW_v0.10.4_ship_readiness.md:178`.
- **Fix**: One-liner at Rules.lua:959
  ```lua
  if contract.gahwa and contract.type ~= K.BID_SUN then
  ```
  OR mirror at `S.ApplyGahwa` (State.lua:1140-1147) by guarding on
  `s.contract.type == K.BID_HOKM` before setting `s.contract.gahwa = true`.
  The Rules.lua site is more authoritative (covers all R.ScoreRound callers).

### Bug #2 — Tiebreak divergence between normal end and penalty paths (MED)

- **Sites**: `Net.lua:2365-2369` (Takweesh) + `Net.lua:3093-3097` (SWA)
- **Description**: Penalty paths use the pre-v0.8.6 raw-bidder-team
  tiebreak logic. The canonical Site A at 1731-1747 was upgraded to
  respect `bidderMade` and `gahwaWonGame`. Penalty paths were not.
- **Impact**: A Takweesh or invalid-SWA that brings cumulative to a
  perfect tie at the target awards the match to the bidder team —
  even though Takweesh/invalid-SWA always penalize a specific side
  (the offender). The bidder might be the offender.
- **Severity**: MED. Reachability is narrow (requires both teams to
  land at exact target in the same round, AND the round must end via
  Takweesh or invalid SWA). But the failure mode is **wrong winner**
  — the match outcome contradicts the round's intent.
- **Fix**: Mirror Site A's logic. Both penalty paths should consult
  `bidderMade` (which they have access to via `contractMade` in SWA
  case; Takweesh case needs to derive it from the offender — Takweesh
  always means **the offender's team is the loser**, so `winner =
  (offenderTeam == "A") and "B" or "A"` on tie).

### Bug #3 — Glossary mislabels match-target units (LOW, doc only)

- **Site**: `docs/strategy/glossary.md:159`
  ```
  | Match target | 152 raw | S.s.target |
  ```
- **Description**: The "raw" qualifier is wrong. `cumulative` is
  populated from `result.final = div10(raw)` (game points). 152 is
  game points; the equivalent raw value would be ~1520.
- **Severity**: LOW. Doc-only, but it could mislead a future reader
  reasoning about score conversions.
- **Fix**: Change to `| Match target | 152 game points | S.s.target |`.

### Bug #4 — No `K.GAME_TARGET` constant (LOW, code-hygiene)

- **Sites**: 6 locations hardcode `or 152` defaults instead of
  reading a `K.GAME_TARGET` constant (Bot.lua:991, 1029, 1060, 3402;
  State.lua:75, 1576; WHEREDNGN.lua:17, 81; Slash.lua:27).
- **Description**: A canonical `K.GAME_TARGET = 152` would let any
  reader grep for the value and serve as the documented Saudi
  default. The existing pattern `(S.s.target or 152)` couples the
  default to every caller — dangerous if a future caller forgets the
  fallback and crashes on a fresh state where `s.target` is nil.
- **Severity**: LOW. No live bug; defensive code-hygiene.
- **Fix**: `K.GAME_TARGET = 152` in Constants.lua, replace literal
  `152` fallbacks with `K.GAME_TARGET`. Slash.lua message becomes
  `"... cumulative target (default " .. K.GAME_TARGET .. ")"`.

### Non-bug (verified): Sun-Bel cumulative gate

- `R.CanBel` (Rules.lua:586-590) reads `cumulative[team]` and
  compares against `K.SUN_BEL_CUMULATIVE_GATE = 100`.
- `N._SunBelAllowed` (Net.lua:68-83) computes the trailing team and
  delegates to `R.CanBel`.
- Both predicates correctly handle the strict-split rule:
  `mine ≤ 100 AND otherCum > 100`.
- **No bug.** Per v0.10.0 R1 fix, role-irrelevant predicate verified.

### Non-bug (verified): Big-round overshoot

- Cumulative is summed without clamp; game-end fires when ANY team
  crosses target. Display shows actual total (e.g., 156 vs 152).
- **No bug.** Saudi rule: overshoot is acceptable; the team that
  reaches target first wins outright unless tied.

---

## Cross-reference summary

| Item | File | Line(s) |
|---|---|---|
| `s.target` default 152 | `WHEREDNGN.lua` | 17, 81 |
| `s.target` reset preserve | `State.lua` | 75, 715-722 |
| `s.cumulative` init | `State.lua` | 63, 338, 450-452 |
| `S.ApplyRoundEnd` | `State.lua` | 1463-1585 |
| `S.ApplyGameEnd` | `State.lua` | 1597-1607 |
| Site A game-end | `Net.lua` | 1721-1750 |
| Site B (Takweesh) | `Net.lua` | 2362-2372 |
| Site C (SWA) | `Net.lua` | 3091-3100 |
| Gahwa override | `Net.lua` | 1707-1716 |
| `R.ScoreRound` Gahwa branch | `Rules.lua` | 957-968 (was "928" pre-v0.10.0) |
| `S.ApplyGahwa` | `State.lua` | 1140-1147 |
| `R.CanBel` Sun gate | `Rules.lua` | 554-592 |
| `N._SunBelAllowed` | `Net.lua` | 68-83 |
| `K.SUN_BEL_CUMULATIVE_GATE = 100` | `Constants.lua` | 352 |
| `_OnRound` (non-host) | `Net.lua` | 1541-1546 |
| `_OnGameEnd` (non-host) | `Net.lua` | 1548-1553 |
| Slash `target` setter | `Slash.lua` | 271-287 |

## Related findings

- `B-Net-06_escalation_chain.md` — F10 covers same Gahwa type-blind issue
- `B-Rules-02_scoreRound.md` — F-03 covers same Gahwa branch defensive gap
- `B-State-05_scoreRound_full.md` — F-02 + F-07 (failed-Gahwa double-impact)
- `D-RT-30_gahwa_attacks.md` — Scenario 2 wire-attack reachability
- `D-RT-09_sun_escalation_bypass.md` — Sun + stale escalation-flag vector
- `C-Xref-04_saudi_rules_drift.md` — Rules.lua:920-937 cross-canon check
- `REVIEW_v0.10.4_ship_readiness.md:178` — Gahwa-Sun severity downgrade
