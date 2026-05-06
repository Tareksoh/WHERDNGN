# 73 — Gahwa game-end / cumulative jump hunt (v0.7.2)

Scope: `R.ScoreRound` (Rules.lua:836-847), `_HostStepAfterTrick` jump
(Net.lua:1584-1619), `S.ApplyRoundEnd`, `S.ApplyGameEnd`, takweesh /
SWA paths.

---

## SEV-HIGH 1 — Failed Gahwa: opponent jumps to target, but failing team's `final.A/B` carries through

**Location:** `Rules.lua:836-847` and `Net.lua:1593-1602`.

`R.ScoreRound` returns `gahwaWinner = oppTeam` on a failed Gahwa, but
the `final.A/B` table that drove pre-Gahwa scoring is NOT zeroed. The
post-call code in `_HostStepAfterTrick`:

```
addA, addB = res.final.A, res.final.B
if res.gahwaWonGame and res.gahwaWinner then
    if res.gahwaWinner == "A" then addA = math.max(addA, target - cumA)
    else                          addB = math.max(addB, target - cumB)
end
```

Only the WINNER's add gets inflated. The LOSER (failing bidder) still
receives whatever `final.A/B` they got from the normal `outcome_kind=="fail"`
branch — including any carré melds the failing team holds (per the
"each team keeps melds on fail" rule at Rules.lua:763-765). On a
Sun-×8 (Gahwa) round this can be hundreds of game-points to the loser.

Saudi Gahwa convention: the losing team gets ZERO. Match goes
match-winning team → target outright; loser stays at pre-round
cumulative. Current code lets the loser bank meld credit on the way
to losing the match. Visible in the score banner; doesn't change WHO
wins the match (winner already at target) but the displayed scores
mislead.

**Fix:** force `addA=0, addB=0` for the losing side before the
`math.max(target-cum,…)` jump. Or zero `res.final` for the loser
inside `R.ScoreRound` when `gahwaWonGame`.

---

## SEV-HIGH 2 — Tie-at-target tiebreaker reads stale `S.s.contract.bidder` after Gahwa

**Location:** `Net.lua:1610-1615`.

Tie at target (`totA==totB`) tiebreaker reads `S.s.contract.bidder`.
On a Gahwa-failed round where the OPPONENT team is jumped to target,
`contract.bidder` is the LOSING team's seat — Saudi convention says
the WINNING (jumped) team takes the match, but tiebreaker logic
hands it to the bidder team. Concrete repro: Hokm bidder=seat 1,
Bel'd-Triple-Foured-Gahwa'd, fails. cumA=0, cumB=0, target=152.
addA=final.A (some carré melds, say 4), addB=jumped to 152. After
apply: totA=4, totB=152 — no tie, fine. But: cumA=148, cumB=148,
Gahwa fails: addA = something carré, addB = max(carré, 4) = 4. totA
≈ 152, totB = 152. Tie. Tiebreaker awards to bidderTeam=A — but A
just FAILED Gahwa! Match wrongly awarded to losing team.

Combined with HIGH-1: zero loser's add eliminates this. Without
that fix, the tiebreaker should read `gahwaWinner` first.

---

## SEV-MED 3 — Score overflow / Carré-A in Sun ×4: works, but cumulative is unbounded

Sun-Gahwa with Aces-carré: raw = (130+200)×8 = 2640, div10=264, single
round adds 264 cumulative gp. Target 152. Game-end fires (`>=`), winner
is correct. NO bug. But `S.s.cumulative` and `WHEREDNGNDB.history` rows
record runaway numbers — fine numerically, may break UI layouts that
assume ≤ 200ish.

---

## SEV-LOW 4 — Negative cumulative

`R.ScoreRound` outputs are always ≥0 (`teamPoints`, `meldPoints`,
`raw*` all summed from non-negative components; `div10((x+5)/10)` of
0 = 0). `_HostStepAfterTrick` only ADDS. Cannot go negative. Verified
safe.

---

## SEV-MED 5 — /reload at exact game-end: `WHEREDNGNDB.session` race

`S.SaveSession` (State.lua:252) clears `WHEREDNGNDB.session` when
`phase==PHASE_GAME_END`. `S.ApplyGameEnd` sets that phase. BUT
`SaveSession` only fires on **PLAYER_LOGOUT**, not on
`ApplyGameEnd`. Window: ApplyGameEnd → user closes WoW client
HARD (force-quit) → next login `RestoreSession` sees stale GAME_END
session, restores phase=GAME_END. Mostly benign (UI shows winner
banner). TTL=3600s gates it eventually. **Acceptable but documented.**

A worse race: /reload (which DOES fire LOGOUT) BETWEEN the host's
`S.ApplyRoundEnd` and `S.ApplyGameEnd` (lines Net.lua:1603-1616).
These are synchronous so no race in practice; Lua single-threaded.

---

## SEV-HIGH 6 — Bel/Triple/Four/Gahwa wire post-game-end

All escalation handlers gate on `phase==PHASE_PLAY` (Net.lua:1979,
1989, 2035 etc.) — but the GAHWA call path in `LocalGahwa` /
`_OnGahwa` is in `PHASE_GAHWA`, not PLAY. After `ApplyGameEnd` the
phase becomes `PHASE_GAME_END`, so subsequent escalation messages
SHOULD be dropped. Hokm-only path verified.

But: the takweesh path at Net.lua:2183 sends MSG_ROUND BEFORE the
game-end check at line 2216. Receivers `_OnRound` apply cumulative,
then receive MSG_GAMEEND. No issue — sequential. **No bug found
here**, but the SWA path at Net.lua:2929 is identical pattern;
consider asserting host-side that no outstanding escalation timer
fires after `ApplyGameEnd`.

---

## Summary table

| # | Severity | Issue |
|---|---|---|
| 1 | HIGH | Failed-Gahwa loser banks `final.A/B` melds while opponent jumps |
| 2 | HIGH | Tie-at-target tiebreaker awards bidderTeam even when they failed Gahwa |
| 3 | MED  | Sun-×8 single-round overflow possible (numerically OK; UI risk) |
| 4 | LOW  | Negative cumulative impossible — verified safe |
| 5 | MED  | /reload after force-quit at GAME_END — TTL-gated, acceptable |
| 6 | LOW  | No post-end wire issue found; phase gates correct |

**Suggested patch (Rules.lua):**
```lua
if contract.gahwa then
    if bidderMade then gahwaWinner = bidderTeam
    else               gahwaWinner = oppTeam end
    gahwaWonGame = true
    -- Loser receives zero this round.
    local loser = (gahwaWinner == "A") and "B" or "A"
    final[loser] = 0; raw[loser] = 0
    meldPoints[loser] = 0
end
```
