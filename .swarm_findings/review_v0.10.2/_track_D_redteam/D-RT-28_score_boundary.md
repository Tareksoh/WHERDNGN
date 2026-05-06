# D-RT-28: Score boundary detection + game-end edge cases

**Target:** target-score boundary (default 152), end-of-game logic
in the three round-end paths, and simultaneous reach-target by both
teams. Default 152 lives at `WHEREDNGN.lua:17`. The three paths all
end with `if totA >= S.s.target or totB >= S.s.target then ... S.ApplyGameEnd(winner) end`.

**Files inspected:**

- `C:\CLAUDE\WHEREDNGN\WHEREDNGN.lua` 17, 75-89, 141-154
  (DEFAULTS, init, RestoreSession target re-read)
- `C:\CLAUDE\WHEREDNGN\State.lua` 63-75 (reset target),
  338, 1463-1585 (`S.ApplyRoundEnd` + telemetry write),
  1597-1607 (`S.ApplyGameEnd` idempotency)
- `C:\CLAUDE\WHEREDNGN\Net.lua` 271-294 (`SendRound`/`SendGameEnd`),
  567-581 (MSG_ROUND/MSG_GAMEEND wire decode),
  1503-1515 (`_OnRound`/`_OnGameEnd` host-only),
  1649-1719 (`_HostStepAfterTrick` — normal path, gahwa override,
  tiebreaker),
  2253-2339 (Takweesh path — div10, totA/totB, tiebreaker),
  2990-3072 (Invalid-SWA path — synth tricks, totA/totB,
  tiebreaker)
- `C:\CLAUDE\WHEREDNGN\Slash.lua` 271-288 (`/baloot target N` —
  rejects `n < 21`)
- `C:\CLAUDE\WHEREDNGN\Constants.lua` 54, 68-70, 91-115
  (HAND_TOTAL_*, MULT_*, MELD_*, AL_KABOOT_*)
- `C:\CLAUDE\WHEREDNGN\Rules.lua` 277, 864-953 (mult resolution,
  div10, gahwaWonGame branch)
- `C:\CLAUDE\WHEREDNGN\Bot.lua` 986-1064 (`scoreUrgency`,
  `matchPointUrgency` — readers of `s.target`)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\audit_v0.9.0\10_l4_l6_fixes.md`
  (L6 type-guard verification)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-14_savedvars_attack.md`
  (ATK-3 / ATK-4 — savedvars target attack surface)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_C_xref\C-Xref-02_score_pipeline.md`
  (F2 — Takweesh / Invalid-SWA tiebreaker divergence)

**Method:** trace `s.target` from DB read → reset → all three
end-of-round sites; map the comparison operator (`>=` vs `>`)
across normal / Takweesh / Invalid-SWA paths; cross-check the
tiebreaker rules against the v0.8.6 H3 guarantee; quantify each
boundary scenario for feasibility on canonical Saudi tournament
play.

---

## Three round-end paths converge on identical boundary check

All three game-end branches use the exact same predicate
`totA >= S.s.target or totB >= S.s.target`:

1. **Normal round-end** — `Net.lua:1683` (`_HostStepAfterTrick`,
   8 tricks resolved through `R.ScoreRound`)
2. **Takweesh / Qaid penalty** — `Net.lua:2324` (mid-trick
   illegal-play catch, runs custom div10 then game-end check)
3. **Invalid-SWA penalty** — `Net.lua:3062` (caller failed an
   SWA claim; opponents synth the remaining tricks against
   them)

Boundary operator is `>=`, target match exactly = win — see
**Scenario 6** below.

The three paths' tiebreaker rules **DIFFER** (already documented
as C-Xref-02 F2). The normal path got the v0.8.6 H3 fix that
respects `bidderMade`; the Takweesh + Invalid-SWA paths still
naively award the tie to the bidder team. See **Scenario 1**.

`S.ApplyGameEnd` itself is idempotent (`State.lua:1597-1607`):
re-applying with the same winner is a no-op, so duplicate
broadcasts (host self-loopback + remote `_OnGameEnd`) cannot
double-fire `K.SND_BALOOT` or flip the winner.

---

## Scenario 1: Both teams reach target same round — who wins?

### Feasibility: HIGH on Hokm, LOWER on Sun

A single round in Hokm distributes raw `162 × mult` between teams
(plus belote +20 raw on the holder's team). Pre-multiplier max
delta is small enough that "both teams cross 152 from below" is
common in tight games — e.g. cumulative entering round = 145/148,
round delta = (12, 8) → 157/156. Both >= 152.

In Sun (`mult = 2`), `260 × mult / 10` distributions and Carré-A
melds (`400 raw / 10 = 80 gp`) make per-round swings larger, but
the same boundary-cross applies — and v0.10.0 raised
`MELD_CARRE_A_SUN` from 200 to 400 raw (boosting Sun-Carré-A from
40 gp to 80 gp), making single-round swings larger and slightly
increasing the both-cross frequency.

Gahwa's `res.gahwaWonGame` override (`Net.lua:1669-1678`) writes
the loser's delta to **0** in v0.8.6 H2. With the loser at 0
delta, the loser's cumulative cannot rise — so a Gahwa cannot
trigger a both-cross unless the loser was ALREADY past target
before the round. The loser-at-0 invariant prevents the v0.8.6 H2
race that the comment block at 1659-1668 describes.

### Three resolutions of the tiebreaker `totA == totB`

#### A. Normal-path tiebreaker — `Net.lua:1693-1709`

```lua
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
...
```

Three branches in priority order: gahwaWinner > bidderMade-
inverted > defensive `winner = "A"`. The bidderMade inversion
correctly handles the failed-bidder case.

#### B. Takweesh tiebreaker — `Net.lua:2327-2331`

```lua
if totA == totB and S.s.contract and S.s.contract.bidder then
    winner = R.TeamOf(S.s.contract.bidder)
elseif totA > totB then winner = "A"
...
```

Awards the tie to **bidder team unconditionally**. But Takweesh
ALWAYS hands the round to the OPPOSITE team of the offender (per
the Qaid penalty branch at `Net.lua:2216`). When the offender is
on the bidder team (the most common case — bidder over-bids and
plays illegally trying to make), this awards the GAME to the team
that just lost the round — the same v0.8.6 H3 anti-pattern.

When the offender is on the defender team, the Takweesh tiebreak
correctly awards to the bidder team. So this is wrong half the
time.

#### C. Invalid-SWA tiebreaker — `Net.lua:3064-3068`

```lua
if totA == totB and S.s.contract and S.s.contract.bidder then
    winner = R.TeamOf(S.s.contract.bidder)
elseif totA > totB then winner = "A"
...
```

Same shape as Takweesh. An invalid SWA call is by definition
made by the caller's team failing — so awarding the tie to the
bidder team conflicts when the caller is on the bidder team and
the synth play has the contract failing.

### Verdict

**FOUND BUG (re-confirms C-Xref-02 F2):** Takweesh and Invalid-
SWA tiebreaker paths are pre-v0.8.6 H3 and disagree with the
round outcome ~50% of the time. Probability is small (both teams
exactly at target after a Qaid/SWA — sub-0.1% per
C-Xref-02:363) but when it triggers, it awards the match to the
team that just lost the round. **Severity LOW** because of
probability, **HIGH** when triggered. Fix: backport the v0.8.6 H3
multi-criteria block from `Net.lua:1693-1709` to both 2327-2331
and 3064-3068.

### Recommendation

Replace the bare `R.TeamOf(S.s.contract.bidder)` shortcut in both
Qaid and Invalid-SWA paths with the same priority chain used at
1693-1709. For Takweesh: the offender's team always loses; for
Invalid-SWA: the caller's team always loses. Both are deterministic
from the caller side, so the fix can be even simpler than the
normal-path bidderMade-inversion.

---

## Scenario 2: Negative target (post-L6 type-guard but no range-check)

### Feasibility: HAND-EDIT ONLY

The slash setter at `Slash.lua:278-282` rejects any `n < 21`. But
all three reader sites only `tonumber`-coerce — none range-check:

- `WHEREDNGN.lua:81`: `B.State.s.target = tonumber(WHEREDNGNDB.target) or 152`
- `WHEREDNGN.lua:152-154`: `tonumber(WHEREDNGNDB.target) or B.State.s.target or 152`
- `State.lua:75`: `s.target = (DB and tonumber(DB.target)) or 152`

`tonumber("-50")` returns `-50` — passes through all three.

### Effect

Every `cumulative.A >= -50` is true once `cumulative.A >= 0`.
Cumulative starts at `{ A = 0, B = 0 }` per `State.lua:63`. The
zero-comparison (`0 >= -50`) is true even before round 1 starts;
the first round-end fires the game-end branch with whichever team
had a higher delta winning, OR (if both deltas are zero — all-
pass redeal path) it falls into Scenario 1's tiebreaker.

### Verdict

**REPRO CONFIRMED (D-RT-14 ATK-4 partial reconfirmation).** A
hand-edited `WHEREDNGNDB.target = -1` causes the very first
scoring round-end to game-end, regardless of actual scores. The
RestoreSession path is similarly vulnerable.

### Recommendation

Add `n >= 21 and n` clamps at the three reader sites:

```
local t = tonumber(WHEREDNGNDB.target)
B.State.s.target = (t and t >= 21 and t) or 152
```

Mirrors the slash-setter's `< 21` floor and converges all reader
sites on the same input invariant.

---

## Scenario 3: Zero target — game ends round 0?

### Feasibility: HAND-EDIT ONLY (slash rejects)

`tonumber("0") = 0` passes through all three reader sites. With
`s.target = 0`:

- `cumulative.A = 0, cumulative.B = 0` from reset (`State.lua:63`)
- Boundary check `totA >= 0 or totB >= 0` — TRUE before any round
  is played, but the check ONLY fires from inside the three
  round-end branches; you have to play at least one round for
  the predicate to be evaluated.

So the game won't end at PLAYER_LOGIN. It ends on the first
round's resolve, regardless of score.

### Tiebreaker on totA == totB == 0 (all-pass cycle)

If a redeal path were ever to land at the boundary check with
`addA = 0, addB = 0` and prior `cumulative = 0/0`, the normal
path falls through to the defensive `winner = "A"` (1705).
However, redeal paths skip the `_HostStepAfterTrick` boundary
check entirely (`N._HostRedeal`, `Net.lua:1721`), so this is
unreachable from the all-pass path.

### Verdict

**REPRO CONFIRMED (D-RT-14 ATK-4):** Game ends round 1 with
whichever team had the larger delta (or "A" defensively on
exact-tie). Same root cause as Scenario 2 — readers don't
range-check.

### Recommendation

Same fix as Scenario 2; the `n >= 21` floor closes both 0 and
negative cases simultaneously.

---

## Scenario 4: Target above 1000 — bot calibration with high targets

### Feasibility: SUPPORTED BY SLASH (n >= 21 only)

`/baloot target 9999` is accepted by `Slash.lua:271-288` (no upper
bound). Persists to DB and propagates to `s.target` on every
reset.

### Game-end pipeline correctness

The boundary check `totA >= 9999 or totB >= 9999` is sound — it
just takes more rounds. Saudi convention is sub-180 targets, but
no integer overflow is reachable: cumulative is incremented by
`div10(rawA)` per round, capped at `div10(K.AL_KABOOT_HOKM_4 = ?)`
~ 100 gp per round absolute max. To hit `2^31` the user would
need ~2*10^7 rounds — not a real concern.

### Bot calibration

`Bot.scoreUrgency` (`Bot.lua:986-999`) and
`matchPointUrgency` (`Bot.lua:1055-1064`) read `s.target` and use
hard-coded offsets:

```
if me  >= target - 25 then  -- "near win"
if opp >= target - 25 then  -- "desperate"
if opp >= target - 15 then mod = mod + 5  -- match-point
```

The offsets `-25` and `-15` are **gp-absolute**, not target-
relative. With `target = 9999`, `target - 25 = 9974` — bot only
shifts to clinch behavior in the last ~25 gp of a 9999-point
match. Before that, the bot plays `scoreUrgency = 0` (neutral)
for ~99% of the match. Bot calibration data was sampled at
target=152, so its offset-25 represents ~16% of target. At
target=9999, that's 0.25% — bots play the entire game without
adapting.

Symmetric problem at low targets: `target = 25` (>= 21 minimum,
permitted) gives `target - 25 = 0` — every cumulative satisfies
the "near win" branch from round 1.

### Verdict

**LOW-RISK BOT-DEGRADATION:** No game-end boundary bug. The bot
heuristics use absolute offsets that misbehave at non-default
targets. Out-of-canonical for Saudi play but a configurable
target lets users hit it.

### Recommendation

If supporting non-default targets is a goal, scale the offsets:

```
local nearWinGap   = math.max(15, math.floor(target * 0.15))
local matchPointGap = math.max(10, math.floor(target * 0.10))
```

Target=152: nearWinGap=22 (close to current 25), target=200: 30,
target=100: 15 (raises the floor). Otherwise document target as
"experimental at non-default values" and keep the current
constants.

---

## Scenario 5: Target change mid-game via /baloot

### Feasibility: SUPPORTED, RACE WINDOW

`/baloot target N` (`Slash.lua:271-288`) writes BOTH
`WHEREDNGNDB.target = n` AND `B.State.s.target = n`. Effective
immediately on the local machine. Does NOT broadcast.

In a multi-player game:

- Host sets `target = 100` mid-game; cumulative is 95/80; host's
  next `_HostStepAfterTrick` resolves a +10 round on team A; host
  fires game-end with winner=A.
- Remote clients running pre-change `s.target = 152` receive
  `MSG_ROUND` and apply the score (95+10, 80) — they DON'T fire
  game-end on their own (the boundary check is host-only at
  1683/2324/3062). They wait for `MSG_GAMEEND` from the host.
- Host then sends `MSG_GAMEEND` (`Net.lua:292-294`) — receivers
  call `S.ApplyGameEnd` (`Net.lua:1510-1515`) and accept the
  result.

So the host's authoritative target wins. No desync from the wire,
because boundary detection is host-only and game-end is broadcast
explicitly.

### Race window: target lowered mid-round

If the host is at `phase = K.PHASE_PLAY` and types
`/baloot target 50` while cumulative is 80/85, the next call to
`_HostStepAfterTrick` (after trick 8) will see `s.target = 50`
and game-end fires immediately — even though when the round
started, target was 152. Players had no warning. The hostmate
display still showed the 152 target until the new MSG_ROUND
arrived (no MSG_TARGET broadcast exists).

Resync (`Net.lua:382-389`) DOES include target in field 29 of
MSG_RESYNC_RES (added in Audit Tier 4 / B-69), so a /reload mid-
game pulls the host's current target. But active live clients
get no update until the next round-end implicitly tells them
through MSG_GAMEEND.

### Verdict

**LOW-RISK BUT SURPRISING:** No state desync (host is
authoritative). Players get a sudden game-end with no warning
because target is invisible mid-game until MSG_RESYNC.

### Recommendation

Add a `MSG_TARGET` broadcast on `/baloot target N` change while
not in PHASE_IDLE/PHASE_LOBBY, OR (simpler) refuse target changes
mid-game in the slash dispatcher:

```
if S.s.phase ~= K.PHASE_IDLE and S.s.phase ~= K.PHASE_GAME_END then
    say("can't change target mid-game; finish or /baloot reset first")
    return
end
```

---

## Scenario 6: Target match exactly — `>=` or `>`?

### Feasibility: TRIVIAL

All three boundary sites use `>=`:

- `Net.lua:1683`: `if totA >= S.s.target or totB >= S.s.target then`
- `Net.lua:2324`: `if totA >= S.s.target or totB >= S.s.target then`
- `Net.lua:3062`: `if totA >= S.s.target or totB >= S.s.target then`

A team landing at exactly 152 wins. Per Saudi convention this is
correct — the goal is to **reach** the target, not strictly
exceed.

### Subtle interaction with Gahwa override

The Gahwa branch at `Net.lua:1670-1677`:

```lua
addA = math.max(addA, target - (S.s.cumulative.A or 0))
```

forces `totA = cumulative.A + addA >= target`. With `math.max`,
if the natural delta would exceed the target gap (e.g.
cumulative=140, addA=20 → totA=160 > 152), the natural `addA`
wins. If natural delta is smaller (cumulative=140, addA=5 →
clamped to addA=12 → totA=152), it lands exactly on target. So
Gahwa always reaches at least the target — never overshoots
artificially, never undershoots.

### Verdict

**CORRECT.** `>=` semantics align with Saudi convention. No bug.

### Recommendation

No change.

---

## Scenario 7: Sun ÷5 with v0.10.0 K.MELD_CARRE_A_SUN=400 boundary issues

### Feasibility: NEW IN v0.10.0

v0.10.0 raised `K.MELD_CARRE_A_SUN` from 200 raw to 400 raw,
doubling Carré-A's contribution in a Sun contract. Per
`Constants.lua:95-106`, the pipeline is `meldRaw × Sun×2 / 10`
(div10 with the +5 round-up); 400 × 2 / 10 = 80 gp.

### Boundary impact

A Sun contract with Carré-A and a successful bidder can swing
~80+ gp in a single round. Combined with hand-total 130 gp Sun
(× 2 = 260 raw), a single Sun-with-Carré-A round can yield 80 +
26 = 106 gp to one team — over half the target in one round.

This raises both-team-cross probability (Scenario 1) and means a
single Sun round commonly walks across the target. Boundary check
is unaffected (`>=` is the same), but the tiebreaker exposure
(both teams ≥ 152) increases.

### Concrete mid-game example

Cumulative entering round = 60/85; bidder=A bids Sun, declares
Carré-A, makes contract; per-round raw delta to A might be:
((card_A=80) + 400 meld) × 2 + 20 belote = 980 raw → 98 gp.
Defender team raw: 50 × 2 = 100 raw → 10 gp. Round-end:
158/95. A wins by 158 ≥ 152.

If A enters at 65 and B at 100, same round: A=153, B=110. No
both-cross.

If A enters at 110 and B at 60: addA=98, totA=208; addB=10,
totB=70. A wins by ≥152, no tie.

Both-cross config requires both teams already near target AND a
multi-rounded delta — with Sun's mult-2 plus Carré-A, that's
plausible.

### Verdict

**SCORING CORRECT, EXPOSURE INCREASED.** v0.10.0 R5's 200→400
fix doesn't create a boundary bug — it increases the rate at
which Scenario 1's tiebreaker is exercised. Combined with the
Takweesh / Invalid-SWA tiebreaker bugs (Scenario 1), the
practical likelihood of a bad tiebreaker rises slightly.

### Recommendation

No direct fix for this scenario. Instead, prioritize the
Scenario 1 fix to the tiebreaker paths in `Net.lua:2327-2331`
and `3064-3068`, since v0.10.0 raises the rate at which
Carré-A-Sun can put both teams across boundary in one round.

---

## Scenario 8: Round-end multi-target — host's MSG_ROUND deterministic across hosts?

### Feasibility: ALWAYS HOST-AUTHORITATIVE

There is exactly one host per game (`S.s.isHost`). All three
end-of-round paths fire from `_HostStepAfterTrick` /
`HostResolveTakweesh` / `HostResolveSWA` — host-only entry
points. Boundary check evaluates ONLY on host (the receiver-side
`_OnRound` at `Net.lua:1503-1508` skips its own host
loopback at 1506 and only `S.ApplyRoundEnd`s — it does NOT
re-evaluate the boundary).

`MSG_GAMEEND` is sent by host (`Net.lua:1711, 2333, 3070`),
received by clients via `_OnGameEnd` at `Net.lua:1510-1515`,
which ALSO skips host self-loopback and only `S.ApplyGameEnd`s
the winner. Receivers cannot disagree with the host's verdict.

### Host migration — no support

There is no host-migration code path in `Net.lua`. If the host
disconnects mid-round, the game is in `S.s.isHost = false` for
all remaining clients; boundary checks never fire from those
clients; the game soft-locks at the host's pre-disconnect state.
This is a known design limitation, not a boundary bug.

### Determinism across multiple games / multiple hosts

If the user plays multiple games in sequence, each game has its
own host. Targets persist via `WHEREDNGNDB.target`; teamNames
persist; cumulative resets to 0/0 in `State.lua:63`. Each game-
end is host-authoritative.

### Verdict

**NO MULTI-HOST RACE.** Single host = single source of truth on
the boundary check. Receivers never independently fire game-end
or override the host's winner.

### Recommendation

No change. If host migration is ever added, the boundary check
must move to the new host's `MaybeRunBot`/round-resolve cycle
with the most recent cumulative — but until then, the architecture
is correct by construction.

---

## Cross-reference summary

| # | Scenario | Verdict | Severity | Fix scope |
|---|----------|---------|----------|-----------|
| 1 | Both teams reach target same round | **BUG** in Takweesh + Invalid-SWA tiebreaker (re-confirms C-Xref-02 F2) | LOW prob, HIGH impact when fired | Net.lua:2327-2331, 3064-3068 — backport v0.8.6 H3 logic |
| 2 | Negative target | **BUG** (re-confirms D-RT-14 ATK-4) | LOW (hand-edit only) | WHEREDNGN.lua:81/152, State.lua:75 — add `n >= 21` clamp |
| 3 | Zero target | **BUG** (re-confirms D-RT-14 ATK-4) | LOW (hand-edit only) | Same fix as #2 |
| 4 | Target > 1000 | **BOT-DEGRADATION** (no game-end bug) | LOW (out-of-canonical use) | Bot.lua:986-1064 — scale offsets, OR document |
| 5 | Target change mid-game | **UX hazard** (no desync) | LOW | Slash.lua:271-288 — refuse mid-game OR add MSG_TARGET broadcast |
| 6 | Target match exactly | **CORRECT** | — | — |
| 7 | v0.10.0 Carré-A-Sun = 400 raw | **SCORING OK**, exposure of #1 raised | — | See #1 |
| 8 | Multi-host MSG_ROUND determinism | **CORRECT** (single host) | — | — |

## Highest-priority follow-up

**Scenario 1's Takweesh / Invalid-SWA tiebreaker bug** is already
catalogued at C-Xref-02 F2 with severity LOW. v0.10.0 R5's
Carré-A-Sun raise to 400 raw (Scenario 7) increases the rate at
which the Scenario 1 race is exercised — large per-round Sun
deltas put more rounds across the boundary in single-round
two-team-cross config. The fix is mechanical: copy
`Net.lua:1693-1709`'s priority chain to the two Qaid/SWA
tiebreaker call sites.

**D-RT-14 ATK-4** (negative / zero target) is also re-confirmed.
The slash-setter floor (`Slash.lua:279`) bypasses on hand-edit
because all three reader sites only `tonumber`-coerce. Adding
the same `n >= 21` floor to readers closes the gap.

No new bugs found beyond those flagged in C-Xref-02 and D-RT-14.
This pass adds quantitative evidence of the both-cross probability
under v0.10.0's Sun-Carré-A change and identifies the bot-
calibration constants (`-25`, `-15`) as absolute-gp values that
implicitly assume target ~152.
