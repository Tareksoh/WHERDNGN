# B-State-06 — Round-end / Game-end transitions deep audit

**Track:** B — Code
**Version:** v0.10.2 review
**Targets:**
- `C:\CLAUDE\WHEREDNGN\State.lua`
  `S.ApplyRoundEnd` (1463-1585), `S.ApplyGameEnd` (1597-1607),
  `S.ApplyStart` (752-823), reset (~63-126), TRANSIENT_FIELDS
  (~210-247)
- `C:\CLAUDE\WHEREDNGN\Net.lua`
  `_HostStepAfterTrick` normal end (1649-1719),
  `HostResolveTakweesh` end (2127-2339),
  `HostResolveSWA` invalid-end (2920-3072),
  MSG_ROUND/MSG_GAMEEND wire (271-294, 1503-1515).
- `C:\CLAUDE\WHEREDNGN\Slash.lua` `/baloot target` (271-288).
- `C:\CLAUDE\WHEREDNGN\WHEREDNGN.lua` target init/restore
  (75-89, 141-154).

**Cross-refs:**
- D-RT-28 (score boundary), D-RT-27 (reset / redeal),
  D-RT-20 (Belote cancel edges), D-RT-14 (savedvars attack),
  D-RT-17 (resync edges).
- C-Xref-02 (score pipeline F2 tiebreaker divergence).
- B-N3-2 / B-Net-04 (Takweesh / SWA full-flow).
- B-Net-08 H4 (mid-Takweesh /reload PHASE_SCORE re-broadcast).
- audit_v0.9.0/10_l4_l6_fixes.md (L6 type-guard).
- audit_v0.7.1 H2/H3 (Gahwa override + tiebreak).

---

## Summary

| ID | Severity | Finding |
|---|---|---|
| B-State-06.F1 | **HIGH** (low prob, high impact when fired) | v0.8.6 H3 multi-criteria tiebreaker NOT backported to Takweesh path (`Net.lua:2327-2331`) — awards game to the team that just lost the round when the offender is on the bidder team. |
| B-State-06.F2 | **HIGH** (low prob, high impact when fired) | v0.8.6 H3 multi-criteria tiebreaker NOT backported to Invalid-SWA path (`Net.lua:3064-3068`) — same shape as F1. |
| B-State-06.F3 | LOW (hand-edit) | `s.target` reader sites only `tonumber()`-coerce; no range check. `target = 0` ends game on round 1 with whichever team has the higher delta (or "A" defensively on exact-tie). `target = -50` ends round 1 trivially. |
| B-State-06.F4 | INFO | M1 Qaid-forfeit scan reads unmodified `s.meldsByTeam`; offender's would-be-forfeit `>=100` meld still triggers Belote cancel for opponents. Defensible (Interp-1, "the meld existed"), but undocumented. Same for SWA-invalid path. |
| B-State-06.F5 | **HIGH** (rare, soft-lock when fired) | Mid-Takweesh / Mid-SWA host /reload race: between `S.ApplyRoundEnd` and the `N.SendRound` broadcast, host persists `phase=PHASE_SCORE` but no MSG_ROUND went out. PLAYER_LOGIN re-arm has NO branch for PHASE_SCORE. Soft-lock — clients sit in PHASE_PLAY indefinitely. (Re-confirms B-Net-08 H4 / D-RT-17.) |
| B-State-06.F6 | INFO (PARTIAL) | `lastRoundResult`, `swaRequest`, `pendingPreemptContract`/`preemptEligible` survive `ApplyStart` for round R+1. Score-summary panel could surface a stale R-1 result mid-R. Phase guards prevent scoring desync, but defense-in-depth gap. |
| B-State-06.F7 | OK (CORRECT) | `S.ApplyGameEnd` is idempotent (`State.lua:1602-1604`): re-applying same winner is a no-op, preventing fanfare double-fire on host loopback + remote `_OnGameEnd`. |
| B-State-06.F8 | OK (CORRECT) | Both teams reach target same round → normal path correctly applies v0.8.6 H3 priority chain (`gahwaWinner > bidderMade-inverted > defensive "A"`). Gahwa override at `Net.lua:1669-1678` zeroes loser's delta (v0.8.6 H2), preventing the most common both-cross race. |
| B-State-06.F9 | OK (CORRECT) | Game-end detection uses `>=` at all three sites (`Net.lua:1683, 2324, 3062`); per Saudi convention, exactly target = win. No off-by-one. |
| B-State-06.F10 | OK | Cumulative score updates: `s.cumulative.A = totA` / `s.cumulative.B = totB` written exactly once per round inside `S.ApplyRoundEnd` (`State.lua:1464-1465`). All three end-paths route through this. No double-add reachable. |

---

## F1 — H3 NOT backported to Takweesh tiebreaker (HIGH when fired)

**Site:** `Net.lua:2324-2334`.

**Severity:** LOW probability (both teams exactly at target after a Qaid resolution — sub-0.1% per C-Xref-02), but HIGH impact when fired (awards game to the team that just lost the round).

### Repro (deterministic)

1. Hokm contract, bidder seat 1 (team A). Cumulative entering = `{A=148, B=148}`, target = 152.
2. Mid-trick illegal play by seat 1 (offender on bidder team).
3. Opponent (any seat on team B, e.g. seat 2) calls Takweesh and is verified.
4. Per `Net.lua:2216`, Qaid resolution awards `winnerTeam = "B"` (offender's opposite team).
5. Hand-total 16 raw = 2 nq goes to team B; offender's melds zeroed; some Belote +20 raw flow could push both teams over.
6. If the Qaid math lands `addA = 4, addB = 4` (rare but possible with belote/contract-fail residual on offender side), `totA = 152, totB = 152`.
7. Tie at target → `Net.lua:2327` fires.

### Code (verbatim)

```lua
2324    if totA >= S.s.target or totB >= S.s.target then
2325        -- Same Saudi tie-rule as the normal-round path above.
2326        local winner
2327        if totA == totB and S.s.contract and S.s.contract.bidder then
2328            winner = R.TeamOf(S.s.contract.bidder)
2329        elseif totA > totB then winner = "A"
2330        elseif totB > totA then winner = "B"
2331        else                    winner = "A" end
2332        S.ApplyGameEnd(winner)
2333        N.SendGameEnd(winner)
2334    end
```

The `R.TeamOf(S.s.contract.bidder)` shortcut **awards the tie to the bidder team unconditionally**. But Takweesh always hands the round to the OPPOSITE team of the offender. When the offender is on the bidder team (the most common Qaid case — bidder over-bids and plays illegally trying to make), this awards the GAME to the team that just lost the round — exactly the v0.8.6 H3 anti-pattern.

When the offender is on the defender team, the Takweesh tiebreak correctly awards to the bidder team. So this path is **wrong half the time**.

### Recommended fix shape

Replace with the v0.8.6 H3 priority chain from `Net.lua:1693-1709`. Even simpler for Takweesh: the offender's team always loses, so `winner = (offenderTeam == "A") and "B" or "A"` is deterministic without needing the bidderMade flag.

---

## F2 — H3 NOT backported to Invalid-SWA tiebreaker (HIGH when fired)

**Site:** `Net.lua:3062-3071`.

**Severity:** Same as F1 — LOW probability, HIGH impact when fired.

### Repro (deterministic)

1. Hokm contract, bidder seat 1 (team A). Cumulative entering = `{A=140, B=148}`, target = 152.
2. Mid-trick SWA call by seat 1 (caller on bidder team).
3. Opposition synthesizes remaining tricks against caller per `Net.lua:3038`. Caller's hand fails the SWA claim → `valid = false`, `contractMade = false`.
4. If the synth math swings exactly enough to land `totA = 152, totB = 152`, the tiebreaker fires.

### Code (verbatim)

```lua
3062    if totA >= S.s.target or totB >= S.s.target then
3063        local winner
3064        if totA == totB and S.s.contract and S.s.contract.bidder then
3065            winner = R.TeamOf(S.s.contract.bidder)
3066        elseif totA > totB then winner = "A"
3067        elseif totB > totA then winner = "B"
3068        else                    winner = "A" end
3069        S.ApplyGameEnd(winner)
3070        N.SendGameEnd(winner)
3071    end
```

Same anti-pattern. An invalid SWA is by definition the caller's team failing, but `R.TeamOf(S.s.contract.bidder)` still awards the tie to the bidder. When caller and bidder are on the same team (common — bidder declared and bid SWA on a borderline hand), the failing team wins the game on tie. Conflicts with the round outcome.

### Recommended fix shape

Same as F1 — backport `Net.lua:1693-1709` priority chain. For Invalid-SWA the deterministic shortcut is `winner = (callerTeam == "A") and "B" or "A"`.

---

## F3 — Target type-guard but no range-check; target=0 / target<0 path

**Sites:**
- `WHEREDNGN.lua:81` — `B.State.s.target = tonumber(WHEREDNGNDB.target) or 152`
- `WHEREDNGN.lua:152-154` — `tonumber(WHEREDNGNDB.target) or B.State.s.target or 152`
- `State.lua:75` — `s.target = (DB and tonumber(DB.target)) or 152`

**Slash floor (`Slash.lua:278-282`):**
```lua
local n = tonumber(tNum) or 0
if n < 21 then
    say("target must be at least 21 (Saudi sub-game minimum)")
    return
end
```

**Severity:** LOW (hand-edit only — slash setter rejects).

### Repro

1. Edit `WoW/_retail_/WTF/Account/.../SavedVariables/WHEREDNGN.lua` — set `WHEREDNGNDB.target = 0` (or `-50`).
2. /reload. PLAYER_LOGIN runs `init()` → `tonumber("0") = 0`, passes through.
3. State reset on `/baloot reset` re-reads via `State.lua:75` — same coercion, same passthrough.
4. Start a game. First round resolves; cumulative starts at `{A=0, B=0}`. After any score delta, `cumulative.A >= 0` (or `cumulative.B >= 0`) is trivially true.
5. `Net.lua:1683` `if totA >= S.s.target or totB >= S.s.target then ... S.ApplyGameEnd(winner) end` fires.
6. With `target = -50`, the boundary is satisfied even before any delta — but the check only runs from inside the round-end branches, so the game ends at the FIRST round resolve, not before round 1.

### Code (verbatim)

```lua
WHEREDNGN.lua:81
B.State.s.target = tonumber(WHEREDNGNDB.target) or 152

WHEREDNGN.lua:152-154
B.State.s.target = tonumber(WHEREDNGNDB.target)
                   or B.State.s.target
                   or 152

State.lua:75
s.target      = (DB and tonumber(DB.target)) or 152
```

The slash-setter rejects `n < 21` but reader sites only `tonumber()`-coerce. `tonumber("-50") = -50` — passes through.

### Effect at game-end

- `target = -50`: every cumulative >= 0 → game ends round 1 with team that has higher delta (or "A" defensively on exact-tie via `Net.lua:1709`).
- `target = 0`: same — game ends round 1.
- All-pass path skips the boundary check entirely (no `_HostStepAfterTrick` runs through trick 8 on a redeal — see `_HostRedeal` at `Net.lua:1721`).

### Recommended fix shape

Add `n >= 21` clamp at the three reader sites:
```lua
local t = tonumber(WHEREDNGNDB.target)
B.State.s.target = (t and t >= 21 and t) or 152
```
Mirrors `Slash.lua:279`.

---

## F4 — M1 Qaid forfeit ↔ Belote cancel uses unmodified meldsByTeam (INFO)

**Site:** `Net.lua:2238-2245` (Takweesh), `Net.lua:2956-2978` (SWA-invalid).

**Severity:** INFO (defensible behavior, but undocumented intent).

### Trace

`Net.lua:2192-2245`:

```lua
2192    local meldA = R.SumMeldValue(S.s.meldsByTeam.A)
2193    local meldB = R.SumMeldValue(S.s.meldsByTeam.B)
...
2216    local offenderTeam = (winnerTeam == "A") and "B" or "A"
2217    local mpA = (offenderTeam == "A") and 0 or meldA
2218    local mpB = (offenderTeam == "B") and 0 or meldB
...
2223    local belote
2224    if c.type == K.BID_HOKM and c.trump then
...
2238        local list = (S.s.meldsByTeam and S.s.meldsByTeam[belote]) or {}
2239        for _, m in ipairs(list) do
2240            if m.declaredBy == kWho and (m.value or 0) >= 100 then
2241                belote = nil
2242                break
2243            end
2244        end
2245    end
```

`mpA / mpB` are the SCORING values (zeroed for offender via `mp* = 0`). The Belote cancel scan at line 2238 reads `S.s.meldsByTeam[belote]` directly — the **unmodified state list, which still contains the offender's declared melds.** So if the offender was the K+Q-trump holder AND had a `>=100` meld declared, Belote is cancelled even though the underlying meld is forfeited from scoring.

### Two ways to read this

- **Interp-1 (current):** "the meld existed at the table" — its presence subsumes the +20 even though offender cannot score it. Conservative reading; aligns with "Qaid is severe."
- **Interp-2:** "the meld was forfeited, treat as undeclared" — offender keeps +20 because there's no scoring `>=100` meld on their side anymore.

PDF 02 K-04 and Source H-36.12 describe the **scoring** treatment. They do not address the Belote-cancel hypothetical. No source crosses the two.

D-RT-20 already flagged this. The note here is that the round-end transition itself is unaffected — this is a Belote-rule semantic question, not a transition-correctness question. The cancel happens BEFORE `S.ApplyRoundEnd` is called and feeds into addA/addB.

**However**, see B-State-06.F1 — D-RT-20 also identified that the Belote scan in BOTH Takweesh and SWA-invalid paths uses the pre-v0.9.0 player-gated predicate (`m.declaredBy == kWho`), missing partner's `>=100` meld. That is a separate, more impactful bug than the F4 forfeit-ordering question, but it lives in the same Belote scans.

---

## F5 — Mid-Takweesh / Mid-SWA /reload race: PHASE_SCORE without re-broadcast (HIGH, rare)

**Sites:**
- `Net.lua:2264-2291` (Takweesh resolution: ApplyRoundEnd → SendRound window)
- `Net.lua:3058-3060` (SWA-invalid resolution: ApplyRoundEnd → SendSWAOut window)

**Severity:** HIGH when fired (soft-lock), low probability (microsecond race window).

### Repro

1. Host is in PHASE_PLAY. Mid-trick illegal play caught.
2. `HostResolveTakweesh` runs:
   - Line 2264: `S.ApplyRoundEnd(addA, addB, totA, totB)` — sets `phase = PHASE_SCORE`, updates `cumulative`.
   - Line 2273: `S.s.lastRoundResult = nil`.
   - Line 2274: `S.s.trick = nil`.
   - Lines 2276-2290: set `S.s.takweeshResult`.
   - Line 2291: `N.SendRound(addA, addB, totA, totB)`.
3. Host /reloads sometime BETWEEN line 2264 and line 2291. PLAYER_LOGOUT fires:
   - SaveSession runs. `phase` is PHASE_SCORE — does NOT match the IDLE/LOBBY/GAME_END skip set, so SaveSession proceeds.
   - `takweeshResult` IS transient (TRANSIENT_FIELDS line 212) → DROPPED.
   - `cumulative` (post-round) saved.
4. PLAYER_LOGIN: RestoreSession brings phase=PHASE_SCORE back. Re-arm block (`WHEREDNGN.lua:155-217`) covers PHASE_OVERCALL/DOUBLE/TRIPLE/FOUR/GAHWA/PREEMPT and stuck-PHASE_PLAY edge. **NO branch for PHASE_SCORE.**
5. Other clients still sit in PHASE_PLAY (no MSG_ROUND broadcast). Host shows score panel; clients show stuck table.

### Code (verbatim — Takweesh window)

```lua
2264    S.ApplyRoundEnd(addA, addB, totA, totB)
2265    -- Takweesh bypasses the normal scoring path, so lastRoundResult and
...
2273    S.s.lastRoundResult = nil
2274    S.s.trick = nil
...
2291    N.SendRound(addA, addB, totA, totB)
```

### Code (verbatim — SWA-invalid window)

```lua
3048    S.s.swaResult = {
3049        caller = callerSeat, valid = valid,
3050        contractMade = contractMade,
3051        sweep = sweepTeam,
3052    }
3053    S.s.lastRoundResult = nil
3054    S.s.trick = nil
...
3058    S.ApplyRoundEnd(addA, addB, totA, totB, sweepTeam, contractMade)
3059    N.SendSWAOut(callerSeat, valid, addA, addB, totA, totB,
3060                 sweepTeam, contractMade)
```

### Additional UI-degradation overlay (Takweesh)

`takweeshResult` is in TRANSIENT_FIELDS, so SaveSession drops it. After PLAYER_LOGIN restore, host's score panel falls back to the GENERIC "round done" banner instead of the Takweesh-detail (caller / offender / card / reason). Looks like an unrelated round-end to the host until they realize MSG_ROUND never broadcast and clients are frozen. Same shape on SWA-invalid: `swaResult` is transient, dropped on /reload.

### Recommended fix shape

Per D-RT-17 §5 / B-Net-08 H4: add a host PLAYER_LOGIN branch that detects `phase == PHASE_SCORE && s.lastRoundDelta` and re-broadcasts MSG_ROUND from `s.lastRoundDelta + s.cumulative` (both are saved across /reload — `lastRoundDelta` is set in `S.ApplyRoundEnd:1467` and is NOT in TRANSIENT_FIELDS). Or move SendRound earlier to shrink the race window.

The normal path is also exposed — `_HostStepAfterTrick` at `Net.lua:1681` (`S.ApplyRoundEnd`) → `Net.lua:1682` (`N.SendRound`) has the same shape, but the gap is just one statement (literally microseconds).

---

## F6 — Per-round transient fields not all cleared at round-end (PARTIAL)

**Site:** `S.ApplyStart` at `State.lua:752-823`.

**Severity:** INFO (defended downstream by phase guards; no scoring desync).

### Findings (per D-RT-27)

| Field | ApplyStart clears? | Defense | Verdict |
|---|---|---|---|
| `swaRequest` | Yes (line 813) | Phase guards in `_OnSWAReq`/`_OnSWAResp` | OK |
| `swaDenied` | Yes (line 814) | Wall-clock C_Timer + transient | OK |
| `lastRoundResult` | NO | Overwritten by next round's `S.ApplyRoundResult`; or nilled by Takweesh/SWA pre-set | PARTIAL — score-summary panel surfaces R-1 mid-R until R+1's resolution |
| `pendingPreemptContract` | NO | `K.PHASE_PREEMPT` phase guard in `_FinalizePreempt` | PARTIAL — defense-in-depth gap |
| `preemptEligible` | NO | Same as above | PARTIAL |
| `takweeshResult` | Yes (line 806) | — | OK |
| `swaResult` | Yes (line 807) | — | OK |
| `peekedThisRound` | Yes (line 780, false) | — | OK |
| `lastTrick` | Yes (line 785, nil) | — | OK |
| `akaCalled` | Yes (line 795) | Cleared at trick-end too | OK |
| `meldHoldUntil` | Yes (line 800, `{}`) | — | OK |
| `playedCardsThisRound` | Yes (line 791, `{}`) | — | OK |

### Code (verbatim — ApplyStart's current clear set)

```lua
803    s.redealing    = nil
804    -- Last hand's takweesh / SWA banners cleared at next round.
805    s.takweeshResult = nil
806    s.swaResult      = nil
...
813    s.swaRequest     = nil
814    s.swaDenied      = nil
```

No mention of `pendingPreemptContract`, `preemptEligible`, or `lastRoundResult`.

### Reachability

- `lastRoundResult`: a player who opens the score-summary panel between round-end and next-round `ApplyRoundResult` sees the previous round's banner. Cosmetic — no scoring path reads it.
- `pendingPreemptContract` / `preemptEligible`: protected by `s.phase == K.PHASE_PREEMPT` guards in finalization paths. Safe today, but fragile: any code path that branches on these without checking phase is exposed.

---

## F7 — `S.ApplyGameEnd` idempotent (CORRECT)

**Site:** `State.lua:1597-1607`.

**Severity:** OK.

### Code (verbatim)

```lua
1597    function S.ApplyGameEnd(winnerTeam)
1598        -- Idempotent re-apply: if we're already in GAME_END with the
1599        -- same winner, skip — prevents the BALOOT-fanfare cue from
1600        -- double-firing on a duplicate broadcast (host loopback +
1601        -- _OnGameEnd from another client).
1602        if s.phase == K.PHASE_GAME_END and s.winner == winnerTeam then
1603            return
1604        end
1605        s.phase = K.PHASE_GAME_END
1606        s.winner = winnerTeam
1607        return
1608    end
```

### Verdict

Idempotency check correctly prevents fanfare double-fire on duplicate broadcasts. In particular:
- Host fires `S.ApplyGameEnd` locally (line 1710/2332/3069) THEN `N.SendGameEnd` (line 1711/2333/3070).
- The MSG_GAMEEND wire is broadcast to ALL party members; `_OnGameEnd` (line 1510-1515) skips host self-loopback (`fromSelf(sender) return`), so loopback doesn't reach `ApplyGameEnd`.
- But on a remote (non-host), the path is `_OnGameEnd → S.ApplyGameEnd`. Idempotency primarily protects against host's PLAYER_LOGIN re-arm or rebroadcast race.

### Edge: `winnerTeam` mismatch

If the host has somehow already applied with winner="A" and a later message arrives with winner="B" (e.g. from a retransmit through a stale /reload window), the idempotent check `s.winner == winnerTeam` is FALSE, so `winnerTeam = "B"` would overwrite. But `_OnGameEnd` only accepts from `fromHost(sender)` — so this requires a malicious or buggy host. Acceptable.

### Edge: Game-end fanfare lives in `ApplyRoundEnd`, not `ApplyGameEnd`

The BALOOT fanfare actually fires in `S.ApplyRoundEnd` at lines 1482-1485 (gated on sweep/bidderMade), not in `ApplyGameEnd`. So the idempotency comment block at 1599-1601 is mildly misleading — but the practical defense holds because round-end and game-end are separate.

---

## F8 — Both teams reach target same round (CORRECT for normal path)

**Site:** `Net.lua:1683-1712`.

**Severity:** OK on normal path; see F1/F2 for Takweesh/SWA divergence.

### Code (verbatim — normal path tiebreaker)

```lua
1683    if totA >= S.s.target or totB >= S.s.target then
...
1692        local winner
1693        if totA == totB then
1694            if res.gahwaWonGame and res.gahwaWinner then
1695                winner = res.gahwaWinner
1696            elseif S.s.contract and S.s.contract.bidder then
1697                local bidderTeam = R.TeamOf(S.s.contract.bidder)
1698                if res.bidderMade then
1699                    winner = bidderTeam       -- bidder made → they win tie
1700                else
1701                    winner = (bidderTeam == "A") and "B" or "A"
1702                                              -- bidder failed → opp won round
1703                end
1704            else
1705                winner = "A"                  -- defensive fallback
1706            end
1707        elseif totA > totB then winner = "A"
1708        elseif totB > totA then winner = "B"
1709        else                    winner = "A" end
1710        S.ApplyGameEnd(winner)
1711        N.SendGameEnd(winner)
1712    end
```

### Three-tier priority chain (verified)

1. `gahwaWonGame and gahwaWinner` → use Gahwa winner.
2. `bidderMade == true` → bidder team wins tie.
3. `bidderMade == false` → opp team (bidder failed → opp won round, opp wins tie).
4. Defensive fallback: `winner = "A"`.
5. Non-tie: standard `>` comparison; if all equal (impossible after `==` branch), `winner = "A"`.

### Gahwa override interaction (also CORRECT)

`Net.lua:1669-1678`:

```lua
1669    if res.gahwaWonGame and res.gahwaWinner then
1670        local target = S.s.target or 152
1671        if res.gahwaWinner == "A" then
1672            addA = math.max(addA, target - (S.s.cumulative.A or 0))
1673            addB = 0  -- v0.8.6 H2: zero loser's delta
1674        else
1675            addB = math.max(addB, target - (S.s.cumulative.B or 0))
1676            addA = 0  -- v0.8.6 H2: zero loser's delta
1677        end
1678    end
```

Gahwa branch zeroes the loser's delta and forces the winner's `tot* >= target`. This prevents the v0.8.6 H2 race where a Gahwa with leftover loser-meld deltas could land both teams at target. With loser at 0 delta, the loser's cumulative cannot rise — so a Gahwa cannot trigger a both-cross unless the loser was ALREADY past target before the round (which would have ended the previous round).

### Verdict

Normal-path tiebreaker is the canonical reference for F1/F2 — backport this same priority chain.

---

## F9 — Game-end detection uses `>=` (CORRECT)

**Sites:**
- `Net.lua:1683` (normal): `if totA >= S.s.target or totB >= S.s.target then`
- `Net.lua:2324` (Takweesh): `if totA >= S.s.target or totB >= S.s.target then`
- `Net.lua:3062` (SWA-invalid): `if totA >= S.s.target or totB >= S.s.target then`

### Verdict

`>=` semantics align with Saudi convention — the goal is to **reach** the target, not strictly exceed. A team landing at exactly 152 wins. No off-by-one; identical predicate at all three end-paths.

---

## F10 — Cumulative score updates (CORRECT)

**Site:** `State.lua:1463-1465` (sole writer in `S.ApplyRoundEnd`).

### Code (verbatim)

```lua
1463    function S.ApplyRoundEnd(addA, addB, totA, totB, sweep, bidderMade)
1464        s.cumulative.A = totA
1465        s.cumulative.B = totB
```

### Verdict

`s.cumulative` is overwritten exactly once per round — `totA` and `totB` are the pre-computed sum from the host. All three end-paths route through `S.ApplyRoundEnd`:
- Normal: `Net.lua:1681` → `S.ApplyRoundEnd(addA, addB, totA, totB, res.sweep, res.bidderMade)`.
- Takweesh: `Net.lua:2264` → `S.ApplyRoundEnd(addA, addB, totA, totB)` (no sweep/bidderMade — Takweesh doesn't fire fanfare).
- SWA-invalid: `Net.lua:3058` → `S.ApplyRoundEnd(addA, addB, totA, totB, sweepTeam, contractMade)`.

Receivers (non-host) call `S.ApplyRoundEnd` from `_OnRound` at `Net.lua:1503-1508`. `_OnRound` skips host self-loopback and rejects messages not from the host — so non-hosts apply once per MSG_ROUND, hosts apply once locally. No double-add.

`addA + addB` is computed by `R.ScoreRound` (or the Takweesh / SWA divergent paths) BEFORE call; the function signature explicitly takes pre-computed totals to avoid host/client divergence.

---

## Highest-priority follow-ups

1. **F1 + F2 (HIGH when fired):** Backport `Net.lua:1693-1709` priority chain to `Net.lua:2327-2331` and `Net.lua:3064-3068`. Probability sub-0.1% per round, but per-round EV swing on hit is "wrong team wins the GAME." This is the most direct correctness regression in the round-end transitions.

2. **F5 (HIGH when fired):** Add PLAYER_LOGIN branch for `phase == PHASE_SCORE` in `WHEREDNGN.lua:155-217` to re-broadcast MSG_ROUND from `s.lastRoundDelta`. Microsecond race window means this rarely fires, but when it does, the game soft-locks until a `/baloot reset`.

3. **F3 (LOW, hand-edit):** Add `n >= 21` clamp at the three target reader sites in `WHEREDNGN.lua:81`, `WHEREDNGN.lua:152-154`, `State.lua:75`. Mirrors slash setter's floor.

4. **F4 + B-N3-2 follow-on (Belote scans in Takweesh/SWA still pre-v0.9.0):** D-RT-20 finding #8 — apply the v0.9.0 M5 team-scoped predicate to `Net.lua:2240` and `Net.lua:2972`. Drops the `m.declaredBy == kWho` clause. Higher impact than F4's forfeit-ordering question.

5. **F6 (defense-in-depth):** Add `s.lastRoundResult = nil`, `s.pendingPreemptContract = nil`, `s.preemptEligible = nil` to `S.ApplyStart`'s explicit clear set at `State.lua:803-814`.

---

## Files referenced

- `C:\CLAUDE\WHEREDNGN\State.lua`
  (60-126 reset, 137-158 RedealAnnouncement, 250-287 SaveSession,
  752-823 ApplyStart, 1463-1585 ApplyRoundEnd, 1597-1607 ApplyGameEnd,
  1921-1926 HostScoreRoundResult)
- `C:\CLAUDE\WHEREDNGN\Net.lua`
  (260-294 Send senders, 1503-1515 _OnRound/_OnGameEnd,
  1649-1719 _HostStepAfterTrick, 2127-2339 HostResolveTakweesh,
  2920-3072 HostResolveSWA invalid branch)
- `C:\CLAUDE\WHEREDNGN\Slash.lua` 271-288 (`/baloot target N`)
- `C:\CLAUDE\WHEREDNGN\WHEREDNGN.lua` 75-89 init, 141-170 PLAYER_LOGIN
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\audit_v0.9.0\10_l4_l6_fixes.md`
  (L6 type-guard verification)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-28_score_boundary.md`
  (full enumeration of boundary scenarios; F1/F2 confirmed there too)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-27_reset_redeal.md`
  (per-field transient clear table; F5/F6 sourced)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-20_belote_cancel_edges.md`
  (F4 ordering; sub-bug Net.lua predicate divergence)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_C_xref\C-Xref-02_score_pipeline.md`
  (F2 cross-ref of tiebreaker divergence)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-Net-08_resync_replay.md`
  (H4 mid-Takweesh /reload re-broadcast)
