# D-RT-09 — Sun escalation bypass red-team

**Target:** v0.10.0 R2 defensive Sun normalization. R2 collapsed
`R.ScoreRound` Sun-multiplier path so any combination of
`tripled/foured/gahwa` on a Sun contract yields `MULT_SUN * MULT_BEL`
(×4), and added `if contract.type == K.BID_SUN then return false, false`
guards at the top of `Bot.PickTriple` (Bot.lua:3589), `Bot.PickFour`
(Bot.lua:3622), `Bot.PickGahwa` (Bot.lua:3674). Inversion logic in
`Rules.lua:799-806` likewise normalizes Sun's "highest rung" to
`doubled?"double":"none"`.

**Question:** can any code path still set `tripled/foured/gahwa = true`
on a Sun contract, OR exhibit asymmetric behavior (different observable
results across clients, or between scoring/UI/AFK/snapshot)?

**Methodology:** read every `S.ApplyTriple/Four/Gahwa` caller, every
serialization boundary (snapshot, SavedVariables session restore), every
"multiplier chain" copy outside `R.ScoreRound`, every UI consumer of
the flags. Cross-checked phase guards at line-level.

---

## Scenario 1 — Wire-frame attack: malicious peer sends MSG_TRIPLE during Sun

**Verdict: DEFENDED.**

After Sun + Bel, `S.ApplyDouble` jumps phase straight to `PHASE_PLAY`
(State.lua:1085-1088):

```lua
if s.contract.type == K.BID_SUN then
    s.phase = K.PHASE_PLAY
    return
end
```

`N._OnTriple` (Net.lua:919) and `N._OnFour` (Net.lua:935) and
`N._OnGahwa` (Net.lua:952) all gate on phase:

```lua
if S.s.phase ~= K.PHASE_TRIPLE then return end
```

A peer who sends `MSG_TRIPLE` during Sun never satisfies the phase
predicate (Sun never enters `PHASE_TRIPLE`). The handler returns before
calling `S.ApplyTriple`. Same for Four/Gahwa.

Idempotence sub-guard (`if S.s.contract.tripled then return end`) is
reached only after the phase guard, so it does not weaken the defense.

`authorizeSeat` (Net.lua:661) further requires the message be signed by
the bidder's actual owner (or the host for a bot seat). A non-bidder
peer cannot bypass this.

**Net wire path defended. No bypass.**

---

## Scenario 2 — SavedVariables hand-edit: contract.tripled = true on Sun

**Verdict: PARTIAL — scoring path normalized; UI display, secondary
multiplier chains, and the SVars upgrader are NOT.**

### 2a. Scoring (Rules.lua R.ScoreRound) — DEFENDED.

The R2 patch at Rules.lua:884-893 silently ignores `tripled/foured/gahwa`
when `contract.type == K.BID_SUN`:

```lua
if contract.type == K.BID_SUN then
    mult = mult * K.MULT_SUN
    if contract.doubled then mult = mult * K.MULT_BEL end
    -- intentionally ignore tripled/foured/gahwa on Sun
else
    if     contract.gahwa   then mult = mult * K.MULT_FOUR
    ...
end
```

A hand-edited `WHEREDNGNDB.session.state.contract = {type=K.BID_SUN,
doubled=true, tripled=true, foured=true, gahwa=true}` after restore
scores at ×4 (Sun×Bel), not ×6/×8/match-win. Test C in
test_rules.lua:585-601 covers this.

**However** — `R.ScoreRound` is not the only multiplier chain in the
codebase. See `Net.HostResolveTakweesh` and the invalid-SWA branch:

### 2b. Net.lua HostResolveTakweesh multiplier chain — UNDEFENDED.

Net.lua:2185-2190 (Takweesh penalty path):

```lua
local mult = K.MULT_BASE
if c.type == K.BID_SUN then mult = mult * K.MULT_SUN end
if     c.gahwa   then mult = mult * K.MULT_FOUR
elseif c.foured  then mult = mult * K.MULT_FOUR
elseif c.tripled then mult = mult * K.MULT_TRIPLE
elseif c.doubled then mult = mult * K.MULT_BEL end
```

This is the **pre-R2** pattern — the Sun branch and the rung branch
compound. With a stale Sun contract carrying `tripled=true` (no
foured, no gahwa), the chain charges Sun × Triple = ×6 where the
canonical scorer would charge Sun × Bel = ×4 (or ×2 with no Bel). With
`gahwa=true`, it charges Sun × Four = ×8. The Takweesh penalty diverges
from R.ScoreRound's collapse.

### 2c. Net.lua HostResolveSWA invalid-SWA branch — UNDEFENDED.

Net.lua:2930-2935 — identical pattern to 2b. Same hole.

### 2d. UI banner display — UNDEFENDED.

UI.lua:3140-3144 (round-end banner):

```lua
local typeStr = (S.s.contract and S.s.contract.type == K.BID_SUN) and "Sun" or "Hokm"
local mods = { typeStr }
if S.s.contract and S.s.contract.doubled then mods[#mods + 1] = "Bel" end
if S.s.contract and S.s.contract.tripled then mods[#mods + 1] = "Triple" end
if S.s.contract and S.s.contract.foured then mods[#mods + 1] = "Four" end
if S.s.contract and S.s.contract.gahwa then mods[#mods + 1] = "Gahwa (match-win)" end
```

UI.lua:3322-3326 (running-contract banner) — identical pattern.

A Sun contract with stale `tripled=true, foured=true, gahwa=true` flags
displays as `Sun · Bel · Triple · Four · Gahwa (match-win) · ×4`. The
×4 multiplier is correctly normalized (R2 Rules path), but the textual
mod list contradicts it — the user sees "Gahwa (match-win)" alongside
×4. **This is observable asymmetry between the scorer and the UI.**

A defensive normalization at UI.lua:3140 (`local sun = c.type ==
K.BID_SUN`; skip Triple/Four/Gahwa when sun) would cost three lines.

### 2e. RestoreSession overlay — UNDEFENDED.

State.lua:313-314:

```lua
for k in pairs(s) do s[k] = nil end
for k, v in pairs(sess.state) do s[k] = v end
```

Wholesale overlay. The v0.2.0 upgrader at State.lua:323-330 strips the
deprecated `redoubled` field and back-fills `belOpen/tripleOpen/fourOpen`
defaults — but does **not** strip `tripled/foured/gahwa` for Sun
contracts. A hand-edited or version-skewed session can carry those
flags through restore unchanged, then they propagate to UI (2d) and
to Takweesh/SWA penalty paths (2b/2c).

---

## Scenario 3 — Resync mid-escalation: client A sees doubled, client B sees tripled

**Verdict: PARTIAL — single-source authority defends scoring; snapshot
ingestion accepts the wire bytes verbatim with no Sun-flag check.**

### 3a. Snapshot serialization (Net.lua:354-383) — UNDEFENDED.

`packSnapshot` writes `c.tripled and "1" or "0"` etc. unconditionally
regardless of `c.type`. If a buggy host has somehow set tripled=true on
a Sun contract (Scenario 2's restore path, an ApplyTriple call from a
test harness, etc.), the snapshot encodes that flag and ships it to
the rejoiner.

### 3b. Snapshot deserialization (State.lua:434-445) — UNDEFENDED.

```lua
s.contract = {
    type       = ctype,
    ...
    doubled    = f[10] == "1",
    tripled    = f[11] == "1",
    foured     = f[12] == "1",
    gahwa      = f[13] == "1",
    tripleOpen = f[14] == "1",
    fourOpen   = f[15] == "1",
}
```

The receiver applies all four flags verbatim — no `if ctype ==
K.BID_SUN then strip tripled/foured/gahwa` filter. Rejoiner ends up
with the same stale flags as the sender.

### 3c. Resolution at scoring time — DEFENDED.

Despite 3a/3b leaving stale flags in `s.contract`, the canonical
`R.ScoreRound` collapses them to Sun×Bel. **The two clients arrive at
the same scoring result.**

### 3d. Resolution at UI time — UNDEFENDED.

But: the two clients display the contract banner with stale rung
labels (Scenario 2d) — both clients diverge identically from what
R.ScoreRound actually computed. So resync convergence holds at the
scoring layer (good); the asymmetry is between scorer and UI on each
client (bad), not between clients.

### 3e. Phase-state convergence — DEFENDED.

`ApplyResyncSnapshot` reads `f[2]` (phase) verbatim — State.lua:425.
A rejoiner that arrives between Sun's ApplyDouble and HostFinishDeal
sees `phase = K.PHASE_PLAY` (the short-circuit at State.lua:1085-1087
already advanced phase). Net.lua:919/935/952 phase predicates remain
untriggerable post-resync because the snapshot phase is PLAY.

**Net network-layer convergence holds for scoring. UI layer asymmetry
persists.**

---

## Scenario 4 — PHASE_DOUBLE → PHASE_PLAY (Sun) bypass scenarios

**Verdict: DEFENDED.**

Quad-redundant gates each force Sun-Bel → PHASE_PLAY:

1. `S.ApplyDouble` (State.lua:1085-1088): `if s.contract.type ==
   K.BID_SUN then s.phase = K.PHASE_PLAY; return end`. The early
   return means `s.phase = K.PHASE_TRIPLE` (line 1094) is unreachable
   for Sun.

2. `Bot.PickDouble` (Bot.lua:3538): `if contract.type == K.BID_SUN
   then return true, false end`. Bot bidder always picks `wantOpen =
   false` for Sun, so even if the chain mistakenly tried to advance,
   the bot won't request it.

3. `N.LocalDouble` (Net.lua:1858-1866): the human-Bel UI path forces
   `open = false` if `S.s.contract.type == K.BID_SUN`, then calls
   `HostFinishDeal` directly without scheduling a TRIPLE-window
   `MaybeRunBot`.

4. `N._OnDouble` (Net.lua:898-911) wire receiver: `local wasSun =
   S.s.contract.type == K.BID_SUN ... if wasSun or not open then
   N.HostFinishDeal()`. Sun never reaches `MaybeRunBot()` for the
   Triple decision.

A peer that asserts `open=true` on `MSG_DOUBLE` for a Sun contract is
overruled at gate 4 — host calls `HostFinishDeal` regardless. The
sender's local state already had `s.contract.belOpen = (open ~= false)`
recorded but `s.phase = K.PHASE_PLAY` (gate 1 short-circuit), so the
sender never schedules a Triple action either.

**Quad-redundant defense. No bypass found.**

---

## Scenario 5 — Inversion logic with stale Sun flags

**Verdict: DEFENDED.**

Rules.lua:799-806 (the tied-bidder inversion buyer logic):

```lua
local highest
if contract.type == K.BID_SUN then
    highest = contract.doubled and "double" or "none"
elseif contract.gahwa   then highest = "gahwa"
elseif contract.foured  then highest = "four"
elseif contract.tripled then highest = "triple"
elseif contract.doubled then highest = "double"
else                         highest = "none" end
```

The R2 patch explicitly normalizes Sun's "highest rung" using only the
`doubled` flag. Stale `tripled/foured/gahwa` flags on a Sun contract
are bypassed in the buyer-determination branch.

Concretely: a tied 65/65 Sun-Bel contract with stale `tripled=true`
that would (pre-R2) have set `highest = "triple"` and routed to
`outcome_kind = "fail"` (defenders take). Post-R2: `highest = "double"`,
routes to `outcome_kind = "take"` (4-10 inversion → bidder takes). The
existing test at test_rules.lua:584-591 asserts this behavior (`Sun
stale-tripled: collapses to Sun×Bel; tie → bidder takes`).

**Single-point defense, but tightly bound to the multiplier patch.**

---

## Scenario 6 — Concurrent multi-rung wire frames

**Verdict: DEFENDED.**

If a peer sends MSG_TRIPLE + MSG_FOUR + MSG_GAHWA in rapid succession
during a Sun contract:

- All three handlers gate on phase (PHASE_TRIPLE/FOUR/GAHWA).
- Sun never enters those phases (Scenario 4).
- All three short-circuit on the phase predicate. None reach
  `S.ApplyTriple/Four/Gahwa`.

If a peer (post-Bel) sends MSG_TRIPLE during a Hokm contract that just
finished Bel, only the bidder seat survives the seat-authority check
(Net.lua:921). MSG_FOUR/MSG_GAHWA from defenders fire only after their
respective phase gates flip — sequential by construction.

If two peers both fire MSG_TRIPLE simultaneously (e.g. a test harness
race):

- First message: phase=TRIPLE, tripled=nil → applies, sets tripled=true,
  phase becomes PHASE_FOUR.
- Second message: tripled=true (idempotence guard at Net.lua:918) →
  return.

Net.lua:918 idempotence guard catches double-apply.

**No concurrent bypass.**

---

## Scenario 7 — Bot tier dispatch (BotMaster simulation correctness)

**Verdict: DEFENDED.**

`BotMaster.PickPlay` is the ISMCTS sampler, called only during PLAY
(card-decision) — never for escalation. Per CLAUDE.md, "Do NOT add a
second explicit `BotMaster.PickPlay` call" — it's invoked through
`Bot.PickPlay` only.

`Bot.PickTriple/Four/Gahwa` are NOT delegated to BotMaster. They live
entirely in Bot.lua, and their R2 Sun guards (Bot.lua:3589, 3622, 3674)
return `(false, false)` when `contract.type == K.BID_SUN`. BotMaster
never reaches escalation logic.

BotMaster's `rolloutValue` calls `R.ScoreRound` (BotMaster.lua:793)
to evaluate a candidate play; this inherits the R2 Sun-collapse, so
ISMCTS rollouts also score Sun×Bel-only correctly even on a contract
with stale flags.

`BotMaster.lua:702-710` (Sun-specific ducking heuristic) keys on
`contract.type == K.BID_SUN` for play-level decisions, not on the
escalation flags. No coupling to tripled/foured/gahwa.

**No tier-dispatch hole.**

---

## Summary

| # | Scenario | Verdict | Where |
|---|---|---|---|
| 1 | Wire-frame MSG_TRIPLE during Sun | DEFENDED | phase gate Net.lua:919 + ApplyDouble short-circuit State.lua:1085 |
| 2a | Hand-edited SVars → R.ScoreRound | DEFENDED | Rules.lua:884-893 R2 normalization |
| 2b | Hand-edited SVars → HostResolveTakweesh | **UNDEFENDED** | Net.lua:2185-2190 Sun-multiplier compound |
| 2c | Hand-edited SVars → HostResolveSWA invalid | **UNDEFENDED** | Net.lua:2930-2935 (same pattern) |
| 2d | Hand-edited SVars → UI banner | **UNDEFENDED** | UI.lua:3140-3144, 3322-3326 |
| 2e | RestoreSession overlay does not strip Sun-incompatible rungs | **UNDEFENDED** | State.lua:313-330 (only `redoubled` is stripped) |
| 3a | Snapshot serializes stale flags | UNDEFENDED-but-symptom | Net.lua:354-383 |
| 3b | Snapshot deserializes stale flags | UNDEFENDED-but-symptom | State.lua:434-445 |
| 3c | Resync scoring convergence | DEFENDED | both clients funnel through R.ScoreRound |
| 3d | Resync UI asymmetry | partial (downstream of 2d) | both clients display the same wrong text |
| 3e | Phase-state convergence | DEFENDED | snapshot phase is authoritative |
| 4 | PHASE_DOUBLE → PHASE_PLAY bypass | DEFENDED | quad-redundant gates |
| 5 | Inversion logic with stale Sun flags | DEFENDED | Rules.lua:799-806 R2 normalization |
| 6 | Concurrent multi-rung wire frames | DEFENDED | phase gates + idempotence |
| 7 | Bot tier dispatch / BotMaster correctness | DEFENDED | escalation pickers in Bot.lua only; rolloutValue uses R.ScoreRound |

**Live behavior today:** there is no in-tree code path that sets
`tripled/foured/gahwa = true` on a Sun contract. The phase machine
prevents `S.ApplyTriple/Four/Gahwa` from being reached. Tests in
test_asymmetric_metrics/test_baseline_metrics/test_multiseed_metrics
hand-set those flags on `contract` objects (e.g.
test_rules.lua:585) but those tests construct contracts directly,
not via `S.Apply*`. The **only** in-the-wild path that gets stale
Sun-rung flags into a live `S.s.contract` is hand-edited SavedVariables
restored via `S.RestoreSession` — the upgrader at State.lua:323-330
covers `redoubled` from the v0.2.0 chain rewrite but does not project
the v0.10.0 R2 Sun-only-Bel invariant onto restored contracts.

**Four concrete defense gaps remain** (defense-in-depth, not live
exploits):

1. **Net.lua:2185-2190 (HostResolveTakweesh)** — duplicate the R2 mult
   pattern: when `c.type == K.BID_SUN`, ignore Triple/Four/Gahwa.
2. **Net.lua:2930-2935 (HostResolveSWA invalid-SWA)** — same patch.
3. **State.lua:323-330 (RestoreSession Sun upgrader)** — when restoring
   a Sun contract, strip `tripled/foured/gahwa` (mirrors the existing
   `redoubled` strip) before any consumer sees the state.
4. **UI.lua:3140-3144 + 3322-3326** — skip mod-list entries for
   `tripled/foured/gahwa` when `c.type == K.BID_SUN`.

Each is a one-or-two-line addition, no behavior change on canonical
inputs (no live path produces a Sun contract with those flags). All
four gaps share the same root cause: R2 placed normalization in
`R.ScoreRound` (canonical scorer) but did not project the same
invariant onto the OTHER consumers of contract-flag state — secondary
multiplier chains (Net Takweesh/SWA-invalid), UI string composition,
and SavedVariables restore.

**Asymmetric behavior risk: LOW (live), MEDIUM (defense-in-depth).**
The scoring layer is convergent across clients. The UI layer is
locally divergent only when stale flags are present, and all clients
diverge identically. The Takweesh/SWA-invalid penalty paths produce a
score discrepancy with R.ScoreRound's collapse only when stale flags
are present AND a Takweesh/invalid-SWA fires — narrow joint condition.

**Confidence: HIGH** that no live-game exploit exists in v0.10.0 R2.
**Confidence: HIGH** that the four enumerated gaps are real
defense-in-depth holes that match exactly the same pattern R2 already
patched in `R.ScoreRound` and `Bot.PickTriple/Four/Gahwa`.
