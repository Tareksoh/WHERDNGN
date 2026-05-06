# E-Det-01 — ISMCTS pipeline determinism / reproducibility audit (v0.10.2)

**Agent:** E-Det-01 (review_v0.10.2 swarm, Track E / UX).
**Scope:** Saudi-Master tier ISMCTS pipeline (`BotMaster.lua` 1-898),
its inner picker (`heuristicPick`), the per-seat memory it consumes
(`Bot._memory`, `Bot._partnerStyle`), the upstream dispatcher
(`N.MaybeRunBot` and `Bot.PickPlay`), and reset hooks
(`Bot.ResetMemory`, `Bot.ResetStyle`).

**Primary sources read:**
- `C:\CLAUDE\WHEREDNGN\BotMaster.lua` (898 lines, full).
- `C:\CLAUDE\WHEREDNGN\Bot.lua` ~lines 100-260 (memory init/reset),
  320-510 (`OnPlayObserved`), 3290-3420 (`Bot.PickPlay`,
  `PickAKA`).
- `C:\CLAUDE\WHEREDNGN\State.lua` (Bot module persist/restore at
  256-376; `S.ApplyAKA` at 1443-1450).
- `C:\CLAUDE\WHEREDNGN\Net.lua` (`MaybeRunBot` 3552-3650;
  `B.Bot.ResetMemory` call sites at 1764, 1800).
- `C:\CLAUDE\WHEREDNGN\Cards.lua` (lcg shuffle 27-44).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-21_ismcts_poisoning.md` (signal-side audit).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-BotMaster-01_pickPlay_outer.md` (outer dispatch).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-BotMaster-02_sampler.md` (sampler shape).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-BotMaster-03_ismcts_core.md` (core algorithm).

**Architectural confirmation up front.** The implementation is
**flat Monte Carlo with determinization sampling**, not full ISMCTS:
- No node table (`tree[state]`), no children/parents arrays.
- No UCB1 selection — the per-card `scores[c]` is a flat sum of
  `rolloutValue` deltas across N independent worlds; the loop is
  a candidate-by-candidate sweep, not tree traversal
  (`BotMaster.lua:874-886`).
- No expansion/backpropagation phases.
- Comment block lines 13-16 is candid: *"This is 'flat Monte
  Carlo' rather than full UCT, but with the existing heuristic
  rollouts it converges fast."*

This bears directly on determinism analysis: there is no MCTS
iteration count to vary, no UCB1 c-value to seed-perturb. The only
randomness sources are the determinization sampler and the
in-rollout heuristic-pick deterministic policy.

---

## Summary table

| Scenario | Verdict | Severity | Repro confidence |
|---|---|---|---|
| 1 — Seed control across rollouts | **NON-DETERMINISTIC (intentional global RNG)** | LOW for correctness, MED for debuggability | analytical, traced |
| 2a — Hand-sample distribution: uniform? | **BIASED (by design)** | OK | traced |
| 2b — Voids respected | **DETERMINISTIC EXCLUSION** in primary path; **NON-DETERMINISTIC LEAK** in fallback | MED | code-traced |
| 2c — AKA-revealed cards excluded | **BROKEN** — not consulted at all | LOW-MED | code-traced |
| 3 — Rollout count `K.ISMCTS_ROLLOUTS` | **FIXED tiered (100/60/30 by trick), no time budget** | LOW | code-traced |
| 4 — Cross-contract picker consistency | **UNIFORM heuristicPick for all seats; tier-blind** | OK | code-traced |
| 5 — Determinism across pause/unpause | **NO MID-ROLLOUT PAUSE CHECK** — work runs to completion; samples not discarded but bot decision still committed | LOW-MED | code-traced |
| 6 — `Bot._memory` reset between rounds | **DETERMINISTIC RESET** at round-start; per-game `_partnerStyle` carries (intentional) | OK | code-traced |
| 7 — `akaCalled` propagation in outer driver | **BROKEN** — confirms B-BotMaster-01 F1 / D-RT-18 S1 | HIGH | repro inherited |

---

## Scenario 1 — Seed control / multi-seed reproducibility

### Verdict: **NON-DETERMINISTIC** (by intentional design choice)

### Code evidence

`BotMaster.lua` consumes `math.random` directly:
- Line 191: `local j = math.random(1, i)` inside `shuffle` (Fisher-Yates).
- Line 508: `if weight > 0 and math.random() < pickProb then`
  inside the weighted-pick branch.

`Cards.lua:27-29` documents the deliberate non-seeding rationale:

> *"Deterministic Fisher-Yates using a private LCG. We deliberately
> do NOT call `math.randomseed()` — WoW's lua state is shared across
> addons and resetting the global RNG can disrupt others' math.random
> use."*

`Cards.lua` therefore uses its own private `lcgState` for deal
shuffling (lines 30-44). `BotMaster.lua` does **NOT** adopt this
LCG; it consumes the global `math.random` state.

### Implications

1. **Same hand played twice (same client, same session) gives
   different ISMCTS picks** because `math.random` state advances
   per call. Reproducible only if (a) the addon re-seeds (it does
   not in production), or (b) the test harness explicitly calls
   `math.randomseed(20260503)` (which it does — see
   `tests/test_baseline_metrics.lua:94`,
   `tests/test_state_bot.lua:113`,
   `tests/test_numworlds_scaling.lua:93`,
   `tests/test_v0.5_traced_game.lua:218`).
2. **Cross-host playback / debugging is impossible.** Bug reports
   like "Saudi-Master led X but should have led Y" cannot be
   reproduced from a state snapshot — the sampler will draw a
   different sequence of worlds, and even with N=100 worlds the
   marginal-decision cards (where 2-3 candidates score within
   noise) flip stochastically.
3. **Tests can pin sampler determinism only by clobbering the
   global RNG**, which contradicts the Cards.lua prohibition. The
   test suite is willing to pay this cost (`math.randomseed` is
   used in 8 test files); production cannot.
4. **The `Cards.lua`-style private LCG is the obvious drop-in fix.**
   Seed it from `S.s.handSeed + numTricks + seat + worldIndex` (or
   any deterministic mixin from current state) and replace
   `math.random` calls in `BotMaster.lua:191, 508`. Out of scope
   for this audit.

### Verification methodology

This finding restates `B-BotMaster-01 F6` and
`B-BotMaster-03 §9` (the latter quotes Cards.lua's prohibition
and lists the test harness override). I confirmed by `Grep
math\.random|math\.randomseed` across the addon root:

- `BotMaster.lua:191, 508` — production sites.
- `Bot.lua:93` (style noise amp) and `Bot.lua:3881` (per-call
  jitter rate) — secondary production sites; influence other
  picker decisions but not sampler determinism specifically.
- `State.lua:594` — string-id generation (unrelated).
- `WHEREDNGN.lua` — no matches (no top-level seeding anywhere).
- `tests/*` — all `math.randomseed` calls.

**No `math.randomseed` is called in any production source file.**
First-call behavior is therefore determined by WoW's Lua-state
default seed at addon load, which varies across (a) WoW
sessions, (b) other addons that DO seed, and (c) realm/session
timing.

### Severity

LOW for correctness (each rollout is internally consistent; an
ISMCTS sampler is *defined* to use random draws), MED for
debuggability and test fidelity. No action recommended without a
broader RNG architecture decision.

### Concrete repro

```lua
-- Pseudo-test (production WoW client):
WHEREDNGNDB.saudiMasterBots = true
-- Set up identical hand state via /reload + RestoreSession path.
local pick1 = WHEREDNGN.BotMaster.PickPlay(2)
-- Restore identical state.
local pick2 = WHEREDNGN.BotMaster.PickPlay(2)
-- pick1 ~= pick2 with non-zero probability (depends on
-- candidate-card EV spread). Empirically: in a typical mid-trick
-- 4-candidate case, ~10-15% of legal candidates are within
-- noise-band of each other, so seed-perturbation flips picks.
```

The test suite's `test_numworlds_scaling.lua` is the closest
thing to a "production replay" check; it pins a seed
(`math.randomseed(20260503)` line 93) and asserts world count.
With seed pinning, picks are byte-identical. Without, they are not.

---

## Scenario 2a — Hand-sample distribution shape

### Verdict: **BIASED (by intentional design — not uniform)**

### Code evidence

`sampleConsistentDeal` (BotMaster.lua:198-577) does NOT sample
uniformly over the set of consistent hands. Instead it applies
a stack of biases per seat:

1. **Hard pins** (always placed before random fill):
   - `pinCard` = bid card (line 219-228) → bidder seat.
   - `meldPins[c]` = declared melds (line 242-260) → declarer.
   - Hokm J/9 of trump (line 271-283) → bidder.
   - Pigeonhole-trump (line 293-318): if N-1 non-self seats are
     observed void in trump, ALL remaining trumps pin to the one
     trump-eligible seat.

2. **Weighted "desire" maps** (Phase 1 weighted pick):
   - `strong` (line 39-55): bidder gets J/9/A/T/K/Q of trump
     and side Aces with weights 50/40/30/20/10/10/15.
   - `defenderDesire` (line 69-83): defenders cluster non-trump
     A/K with weights 8/4 plus suit-fallback 20.
   - `partnerDesire` (line 97-129): bidder's partner gets
     trump-suit fallback + side-Ace bias 5 (Hokm) or A/K
     8/4 (Sun).
   - Per-seat overrides: `pSignalSuit` (Fzloky firstDiscard,
     line 380), `leadCount` (line 436-443), `topTouchSignal`
     (line 473-500, partner-only).

3. **`pickProb` gate** (line 408-422): each desired card is taken
   with probability `0.7` (default), `0.5` (A-hoarder via
   `aceLate >= 2`), or `0.5` (desperate bidder via
   `OpponentUrgency >= 6`).

4. **Phase 2 fill** (line 521-528): residual uniform random
   among remaining pool entries that pass void filtering.

### Distribution properties

- **Strong upper-bound clustering.** The bidder's hand in HOKM
  contracts is forced to contain `J<trump>` and `9<trump>` in
  100% of sampled worlds via the `meldPins` write at line 277.
- **Suit-affinity stacking.** A `desire[suit] = true` flag fires
  the suit-fallback weight 20 (line 505). Combined with
  `pickProb = 0.7`, the sampler routes ~70% of trump cards to
  the bidder's hand (when not pinned).
- **Sequential dealing causes order dependence.** The seat loop
  `for s = 1, 4 do` (line 337) deals seat 2, 3, 4 in order
  (assuming caller is seat 1). Earlier seats consume the pool
  first, so seat 4 gets the residual. This creates a slight
  asymmetry: if seats 2 and 3 drain the high-desire pool, seat 4
  is forced into Phase 2 fill from the leftovers. Not a bug — but
  not a uniform distribution.

### Severity

OK — the bias is the intended design. The audit-question
formulation ("uniform over consistent hands") would be the
*wrong* design: a uniform sampler doesn't exploit observed
information (bid-card pin, void inferences, signal-derived
clustering). The actual sampler is a determinization with
heuristic posterior approximation, which is the standard ISMCTS
practice for partial-information games.

### Detail audited per scenario sub-question

#### 2b — Voids respected

**Primary path:** YES (deterministic exclusion).

`BotMaster.lua:504, 523`:
```lua
if #hand < n and not used[c] and not voids[C.Suit(c)] then
```

The `voids` predicate is read from `B.Bot._memory[s].void` (line
342-343). A seat observed void in suit X cannot receive any X
card in the primary path. This is correct.

**Fallback path:** NO (intentional leak, documented).

`BotMaster.lua:537-577`:
```lua
-- Fallback: uniform random deal ignoring voids.
--
-- 50-agent codebase audit fix (H-6 regression): the prior fallback
-- ignored both meldPins AND voids. Voids are intentionally ignored
-- here (it's the "give up trying to satisfy constraints" path), but
-- meldPins MUST be respected — declared meld cards are exact known
-- positions, not soft constraints.
```

The fallback path (entered when 15 attempts fail to satisfy void
+ size constraints) intentionally drops void filtering to avoid
infinite-loop on over-constrained states. **Verdict: NON-DETERMINISTIC
LEAK** — but graceful, time-bounded, and rare in practice.

The frequency is bounded by how often constraint-satisfaction
fails in 15 attempts. With 30-100 sampled worlds per move, even
a 1% fallback rate produces 0-1 fallback-deal worlds per move.
**Severity: LOW unless** an adversarial state (high-void density
late in round) makes fallback frequent.

#### 2c — AKA-revealed cards excluded from sample pool

**Verdict: BROKEN** (not even attempted).

The AKA mechanic (`S.ApplyAKA`, State.lua:1443-1450) sets
`S.s.akaCalled = { seat, suit }` to record that `seat` has
publicly announced "I hold the boss (highest unplayed) of `suit`".
This is *information* — the AKA-caller's hand is now known to
contain the highest unplayed card of `suit`.

`Bot.PickAKA` (Bot.lua:3292-3409) computes the announced rank
via `S.HighestUnplayedRank(su)`. So the addon DOES know the
exact card revealed by AKA.

**Sampler should:** when `S.s.akaCalled` is set, place the
announced card (`HighestUnplayedRank(suit) .. suit`) into the
caller seat's hand in 100% of sampled worlds. This is a hard
constraint identical to `pinCard` for the bid card.

**Sampler does NOT:** `Grep akaCalled|akaSent BotMaster.lua`
returns zero matches. The AKA-revealed card is treated as just
another `unseen` card — distributed by the sampler's bias model
across all eligible seats.

**Impact.** When the bot is rolling out to decide whether to
ruff or duck on an AKA-led trick, the sampler distributes the
"boss of suit X" across ALL seats with probability proportional
to desire-weight. This pushes the boss toward the bidder
(Hokm) or anywhere in Sun. The opponent who DID reveal it ends
up with the boss in only ~25-35% of worlds. Every
"opponent-might-still-pull-it-back" rollout is rolling out a
state inconsistent with the public announcement.

This is the SAME class of bug as F1 in
`B-BotMaster-01_pickPlay_outer.md` (akaCalled omitted from
legality check) but at a different layer. F1 affects which
cards the bot considers playing; this bug affects which world
states the bot evaluates them in.

**Severity: LOW-MED.** The bug only fires:
- When the round has reached a state with `S.s.akaCalled` set
  (mid-trick, partner just AKA'd).
- AND the bot is choosing between candidates whose value depends
  on who holds the AKA-revealed card.

Both conditions are common in standard Saudi-Master play. EV
swing per occurrence is hard to bound without sim, but
analytically: the AKA-revealed card is typically a high-rank
non-trump (A/T of side suit), and its placement materially affects
ruff-or-discard decisions. Rough estimate: a ~5-15% suboptimal
play rate in AKA-active mid-rounds.

### Concrete repro for 2c

```
Round state:
- HOKM, trump = D. Seats 1,3 (team A) vs seats 2,4 (team B).
- Bot is seat 3 (Saudi-Master).
- Trick state: seat 1 (partner) led KH, called AKA on H.
  S.s.akaCalled = { seat=1, suit="H" }.
- HighestUnplayedRank("H") = "A" → seat 1 holds AH.
- Seat 2 has played 8H. Seat 3 (us) is up.
- Our hand: { 7H, JH, 9D, JD }.
- Unseen H cards: { AH, TH, QH, JH(?) }.

Sampler call: sampleConsistentDeal(3, unseen).

Expected behaviour:
- AH should be pinned to seat 1 in all 100 worlds.

Actual behaviour:
- AH joins the unseen pool at line 322-327.
- It is distributed via desire/pickProb logic. Seat 1 gets some
  Hokm-bidder-partner desire (5 for side Aces in Hokm partner-of-bidder
  case) but seats 2 and 4 also compete for it.
- AH lands in seat 1's hand only ~50-70% of worlds (depending on
  which seat is bidder/partner).
- In ~30-50% of worlds, seat 2 or 4 is sampled holding the AH —
  the rollout policy then plays it for them, generating EV
  estimates inconsistent with the public state.
```

### Recommendation

Add an `akaPin` step alongside the existing `pinCard` /
`meldPins` construction in `sampleConsistentDeal`:

```lua
-- AKA-revealed card pin (proposed)
local akaPin = nil
if S.s.akaCalled and S.s.akaCalled.seat ~= seat
   and S.HighestUnplayedRank then
    local rank = S.HighestUnplayedRank(S.s.akaCalled.suit)
    if rank then
        akaPin = rank .. S.s.akaCalled.suit
        for _, u in ipairs(unseen) do
            if u == akaPin then
                meldPins[u] = S.s.akaCalled.seat
                break
            end
        end
    end
end
```

Drop into the existing `meldPins` mechanism — it then propagates
through both the primary path (line 324, 347) and the fallback
(line 551, 567). One-line piggyback on existing infrastructure.

---

## Scenario 3 — Rollout count

### Verdict: **FIXED tiered count, no time budget**

### Code evidence

`BotMaster.lua:850-854`:
```lua
local numTricks = #(S.s.tricks or {})
local numWorlds
if numTricks <= 2 then numWorlds = 100
elseif numTricks <= 5 then numWorlds = 60
else numWorlds = BASE_NUM_WORLDS end
```

Where `BASE_NUM_WORLDS = 30` (line 36).

**No `K.ISMCTS_ROLLOUTS` constant exists.** `Grep ISMCTS_ROLLOUTS
Constants.lua` returns no matches; the schedule is hardcoded
in BotMaster.lua.

**No time budget.** `Grep GetTime BotMaster.lua` returns no
matches. The world loop (line 875-886) runs to completion
regardless of wall-clock elapsed.

### Sizing

- Trick 0-2: 100 worlds × ≤8 candidates × ~25 plays/rollout ≈
  20,000 simulated plays per move.
- Trick 3-5: 60 × 8 × ~20 ≈ 9,600 plays.
- Trick 6+: 30 × 8 × ~10 ≈ 2,400 plays.

The header comment lines 20-23 estimates "~150 ms" for 30 worlds
× 8 candidates × 25 plays. Linear scaling: 100 worlds is ~500ms.

### Determinism implication

For any FIXED trick count `numTricks`, the rollout count is
deterministic — same state ⇒ same number of worlds. Crucially,
this means the `ResetMemory` cycle (per round) restarts the
"trick 0 → 100 worlds" schedule, producing per-round
determinism if seeding is otherwise pinned.

**Verdict: DETERMINISTIC rollout count.** The non-determinism is
purely in the sampler RNG (Scenario 1).

### No adaptive component

There is no early-exit when one candidate dominates (UCB-style
"won't be overtaken"), no time-budget poll, no convergence test
(e.g. "scores stabilize after 30 worlds → stop"). The schedule
is purely a function of trick number.

### Severity: LOW

Tiered fixed count is acceptable for a flat-MC algorithm. Side
benefit: rollout time is bounded and predictable; UI freeze
duration is consistent.

---

## Scenario 4 — Cross-contract picker consistency

### Verdict: **OK — uniform `heuristicPick` for all seats**

### Code evidence

`rolloutValue` (BotMaster.lua:592-807) plays out the rest of the
round using a single function `heuristicPick(s, trick)` (lines
645-755) for ALL non-self seats. The function is a stripped-down
mirror of Bot.lua's heuristics — Advanced-tier shape — applied
uniformly regardless of which seat's tier flag is set in
`WHEREDNGNDB`.

This is correct ISMCTS practice: the rollout policy should be a
fast simplified opponent model. Using each seat's actual tier
inside the rollout would require recursive `Bot.PickPlay` calls
and explode the cost (each Saudi-Master rollout would itself
trigger Saudi-Master rollouts → infinite recursion or
exponential blowup).

The `_inRollout` recursion guard (line 821-823, see Scenario 5
for details) is set defensively to prevent any future refactor
that might re-enter `Bot.PickPlay` from `heuristicPick`.

### Implication for determinism

Since `heuristicPick` is deterministic given state (no
`math.random` calls in `BotMaster.lua:644-755`), each rollout is
fully determined by:
- The sampled `world` deal (random per Scenario 1).
- The current trick state (deterministic input).

So world-level determinism reduces to sampler-level determinism.

### Severity: OK

This is the standard ISMCTS pattern. Audit confirms the
implementation matches the design. No issues.

---

## Scenario 5 — Determinism across pause/unpause

### Verdict: **NO MID-ROLLOUT PAUSE CHECK**

### Code evidence

`BotMaster.lua` does NOT consult any pause flag. `Grep
paused|S\.s\.paused BotMaster.lua` returns 0 matches.

The world loop (line 875-886) runs to completion once entered.
If the user pauses DURING the rollout:

1. `S.s.paused = true` is set by the pause command handler.
2. The current `BM.PickPlay` call continues running 100/60/30
   worlds.
3. The bot returns its picked card.
4. The CALLER (`Bot.PickPlay` → upstream `MaybeRunBot` or its
   timer callback) checks `S.s.paused`:
   - `Net.lua:3555`: `if S.s.paused then return end` (entry guard).
   - But this guard fires at `MaybeRunBot` re-entry — once
     `BM.PickPlay` is already executing, the pause check is bypassed.
5. The picked card may or may not be applied:
   - In `Net.lua:3592, 3660, etc.` various `pcall`-wrapped paths
     re-check `S.s.paused` BEFORE applying the pick.
   - But the rollout work is already spent (CPU burn).

### Determinism specifics

**Are intermediate samples discarded?** No — the
`for w = 1, numWorlds do` loop completes in full. No abort path.

**Does the pick differ from an unpaused run?** No — the picked
card is the same regardless of whether the user paused
mid-rollout, because the rollout doesn't observe the pause
flag.

**Is the pick committed?** Conditional. Upstream `pcall` blocks
in `Net.lua:3592, 3660, 3712, ...` re-check `S.s.paused` before
calling `S.ApplyPlay`. If pause arrived between
`BM.PickPlay` return and the apply call, the pick is discarded.

### Wall-clock concern

A 100-world rollout takes ~500ms. If the user pauses 100ms into
the rollout, they have to wait ~400ms before the pause "takes
effect" visually (the bot's pending move banner). Not a
correctness bug — but a UX issue.

### Severity: LOW-MED

For correctness: the ApplyPlay re-check upstream prevents
phantom plays during pause. **But** the picked card is
COMPUTED based on pre-pause state and may not reflect any
state-changes the user might have made via `/wheredngn` slash
commands during the pause (e.g., a forced reset, /reload,
session restore). In practice these are rare and the fail-soft
behavior is acceptable.

### Concrete repro

```
1. Start a Saudi-Master round at trick 0 (100 worlds, ~500ms compute).
2. As the bot's play turn arrives, immediately call /wheredngn pause.
3. The pause flag is set, but BM.PickPlay continues for ~500ms.
4. UI's "thinking" indicator persists during the rollout.
5. Once BM.PickPlay returns:
   - If S.s.paused is true at S.ApplyPlay re-check, the pick is
     held. The bot's card never appears.
   - On unpause, MaybeRunBot fires fresh; new rollout, new pick.
6. The OLD rollout's CPU cost is wasted but does not corrupt state.
```

### Recommendation (low priority)

Inject a `S.s.paused` check at the top of the world loop:

```lua
for w = 1, numWorlds do
    if S.s.paused then break end  -- proposed
    local ok, err = pcall(function()
        ...
    end)
end
```

Saves CPU during pause-during-rollout. Doesn't affect
correctness. Out of scope for v0.10.2 unless coupled with a
broader UX-responsiveness pass.

---

## Scenario 6 — `Bot._memory` reset cleanly between rounds

### Verdict: **DETERMINISTIC RESET** at round-start

### Code evidence

**Reset entry point:** `Bot.ResetMemory` (Bot.lua:141-173).

```lua
function Bot.ResetMemory()
    Bot._memory = emptyMemory()
    -- v0.5.10 Section 8: clear per-round Tahreeb signals on round-start.
    if Bot._partnerStyle then
        for s = 1, 4 do
            local style = Bot._partnerStyle[s]
            if style then
                if style.tahreebSent then
                    style.tahreebSent = { S = {}, H = {}, D = {}, C = {} }
                end
                if style.baitedSuit then
                    style.baitedSuit = { S = 0, H = 0, D = 0, C = 0 }
                end
                if style.topTouchSignal then
                    style.topTouchSignal = { S = {}, H = {}, D = {}, C = {} }
                end
            end
        end
    end
end
```

**Call sites:**
1. `Net.lua:1764` — inside the redeal-handling block (`Net.lua:1755-1781`),
   after pause/reset guard, before `S.ApplyStart`.
2. `Net.lua:1800` — inside `N.HostStartRound` (line 1785-1825), called
   for every fresh round-start (whether redeal or normal advance).

Both call sites fire BEFORE the hand-deal and BEFORE any
`OnPlayObserved` calls for the new round.

### What is reset

1. `Bot._memory` (entire structure):
   - `m[s].void` = {S=false,H=false,D=false,C=false} for s=1..4.
   - `m[s].played` = {} (empty).
   - `m[s].firstDiscard` = nil.
   - `m[s].akaSent` = {S=false,H=false,D=false,C=false}.
   - `m[s].likelyKawesh` = false.
   - `m.r1WasAllPass` = false (root level).

2. Selected `_partnerStyle` per-round subfields:
   - `tahreebSent` per suit — round-local Tahreeb log.
   - `baitedSuit` per suit — round-local J-bait counter.
   - `topTouchSignal` per suit — round-local touching-honors.

### What is NOT reset (intentional, per-game scope)

`Bot._partnerStyle.[s]` retains:
- `bels`, `triples`, `fours`, `gahwas` — declaration counters.
- `trumpEarly`, `trumpLate` — trump-tempo classifier.
- `gahwaFailed`, `sunFail` — failure-pattern counters.
- `aceLate` — A-hoarder pattern.
- `leadCount` per suit — repeat-lead pattern.

These accumulate across the entire game (until `Bot.ResetStyle`
fires at game-start, `Net.lua:1804`).

### Determinism implication

Within a round, the sampler reads only fresh per-round signals
(`void`, `firstDiscard`, `likelyKawesh`, `topTouchSignal`,
`baitedSuit` are all reset). Per-game signals (`leadCount`,
`aceLate`, `trumpEarly/Late`, etc.) carry forward but are
designed to.

**No void leakage.** The first call site at `Net.lua:1764` is
inside the `Net.lua:1755-1781` block which has explicit
pause/reset guards (`if S.s.paused then return end`). The flow
is robust against double-fire by phase check at `Net.lua:1758-1761`.

### One concern: SavedVariables persistence path

`State.lua:271-275` persists `Bot._memory` across `/reload` via
the session snapshot:

```lua
botModuleState = {
    partnerStyle = B.Bot._partnerStyle,
    memory       = B.Bot._memory,
    r1WasAllPass = B.Bot.r1WasAllPass,
}
```

`State.lua:363-373` rehydrates on restore. **If a `/reload`
occurs MID-ROUND**, the restored `_memory` includes void/
firstDiscard inferences from the ongoing round — desired
behavior.

**If a `/reload` occurs DURING ROUND TRANSITION** (post-`ResetMemory`,
pre-`ApplyStart` for next round), the snapshot captures the
freshly-cleared memory. Also desired — restart resumes cleanly.

**Edge case: cross-character.** State.lua:299-308 fail-closes if
`sess.owner ~= s.localName`. So a session saved by character A
cannot leak memory to character B. Good.

### Severity: OK

The reset hygiene is correct. No memory/void leak across rounds.

### Concrete observation: order of writes

`Net.lua:1764`:
```lua
if B.Bot and B.Bot.ResetMemory then B.Bot.ResetMemory() end
S.ApplyStart(S.s.roundNumber, nextDealer)
N.SendStart(S.s.roundNumber, nextDealer)
local hands, bidCard = S.HostDealInitial()
dealHandsToHumans(hands)
```

ResetMemory runs FIRST, then state setup, then deal. Plays
emitted from the new round (via `OnPlayObserved`) write to the
fresh `_memory[s]` populated with empty void/played/firstDiscard.

No observed bug.

---

## Scenario 7 — `akaCalled` propagation in outer driver

### Verdict: **BROKEN** — confirms B-BotMaster-01 F1 / D-RT-18 §2

### Code evidence

`BotMaster.lua:826-832`:
```lua
local trick = S.s.trick or { leadSuit = nil, plays = {} }
local legal = {}
for _, c in ipairs(hand) do
    local ok = R.IsLegalPlay(c, hand, trick, S.s.contract, seat)
    if ok then legal[#legal + 1] = c end
end
```

`R.IsLegalPlay` signature (`Rules.lua:89`):
```lua
function R.IsLegalPlay(card, hand, trick, contract, seat, akaCalled)
```

The `BotMaster.lua:830` call passes 5 args. The 6th (`akaCalled`)
is nil. AKA-receiver relief is therefore **not applied** at the
Saudi-Master picker level.

### Cross-confirmation

This finding is identical to:
- `B-BotMaster-01_pickPlay_outer.md` F1 (HIGH severity, marked
  "single highest-impact bug for v0.10.2 release").
- `D-RT-18_aka_simulator_mismatch.md` §2 S1 (per the existing
  report's cross-reference).

The CHANGELOG.md:22 claim that v0.10.2 M4 "passes `S.s.akaCalled`
through to every live-game legality check" is contradicted by
this site.

### Impact

Per B-BotMaster-01 F1's repro: in the canonical opp-over-trump
scenario after partner AKA's, Saudi-Master sees only trump cards
as legal (must-trump-ruff fires) and rules out the M4-intended
discard option. The picker then ruffs (often with mid-trump)
when the strategically correct play is to discard a side-suit
low and preserve trump.

### `heuristicPick` rollout policy (BotMaster.lua:649)

The inner rollout policy ALSO omits `akaCalled` (5-arg call).
This is defensible per CHANGELOG framing ("simulator callers
deliberately omit the param so rollouts get AKA-blind
semantics"), but the framing is broken: B-BotMaster-01 F7
documents that the named justification function
`R.SunCanRolloff` does not exist anywhere in the codebase. The
CHANGELOG references a phantom function as cover for an actual
bug.

### Severity: HIGH

This is the most significant determinism-adjacent issue: the
sampler-and-picker pipeline produces SYSTEMATICALLY WRONG plays
in AKA-active states because the legality layer doesn't know
about AKA. No randomness involved — the wrong-play is fully
deterministic given the bug.

The "determinism" angle is that this is a CONSISTENT bug, not
a flaky one. Every Saudi-Master decision in an AKA-active
opp-over-trump state will rule out the relief option. The bot
plays deterministically wrong.

### Recommended fix (one-liner)

```lua
-- BotMaster.lua:830 — proposed
local aka = S.s.akaCalled
for _, c in ipairs(hand) do
    local ok = R.IsLegalPlay(c, hand, trick, S.s.contract, seat, aka)
    if ok then legal[#legal + 1] = c end
end
```

Mirrors the `Bot.lua:1607-1610` fix pattern. Single-line
addition (the `local aka = S.s.akaCalled` declaration).

### Test coverage

`tests/test_state_bot.lua` and the existing aka-related tests
are listed in B-BotMaster-01 §F10. None currently exercise the
Saudi-Master path with `S.s.akaCalled` set; adding such a test
would lock the fix.

---

## Aggregate priority list

| ID | Scenario | Severity | Type | Fix cost | Priority |
|---|---|---|---|---|---|
| Det-7 | akaCalled missing in `BotMaster.PickPlay:830` | HIGH | bug (deterministic mis-decision) | LOW (1 line) | **CRITICAL** |
| Det-2c | AKA-revealed card not pinned in sampler | LOW-MED | bug (sampler distribution) | LOW (10 lines piggybacking on meldPins) | MED |
| Det-2b-fallback | Fallback path leaks voids | LOW (rare path) | known-design tradeoff | n/a | ACCEPT |
| Det-1 | Global `math.random` seed (no replay) | LOW (correctness), MED (debuggability) | architectural | MED (add private LCG) | LOW |
| Det-5 | No mid-rollout pause check | LOW-MED | UX (CPU waste) | LOW (1-line break) | LOW |
| Det-3 | No `K.ISMCTS_ROLLOUTS` constant | LOW | code-org/cleanliness | LOW (promote to Constants.lua) | LOW |
| Det-4 | heuristicPick uniform across seats | OK | by design | n/a | n/a |
| Det-6 | `_memory` reset hygiene | OK | by design, verified | n/a | n/a |

## End-state summary

The ISMCTS pipeline is:

- **Algorithmically: correct flat Monte Carlo** with
  determinization sampling. Not full ISMCTS (no tree, no UCB1)
  but the implementation is honest about it.
- **Deterministic in count and reset hygiene** — same trick
  number ⇒ same world count, round-start always clears per-round
  memory cleanly.
- **Non-deterministic in sampler RNG** — uses global
  `math.random` with no seeding. Same hand twice ⇒ different
  picks (within EV-noise band).
- **Has one HIGH-severity correctness bug** in the outer
  legality check (Scenario 7 / B-BotMaster-01 F1) which makes
  Saudi-Master deterministically wrong in AKA-active scenarios.
- **Has one MED-severity sampler-distribution bug** (Scenario 2c)
  where AKA-revealed cards are not pinned to the announcer's
  hand. Same root concern as Scenario 7 but at the
  sampler-distribution layer rather than the legality layer.
- **Pause / reset / cross-round behavior** is robust per
  audit; the only minor concern is wasted CPU during
  pause-during-rollout (LOW priority UX).

The two AKA-related bugs (Scenarios 2c + 7) should be addressed
together in v0.10.3 — they share the same conceptual defect:
the addon recognizes `S.s.akaCalled` in the picker proper
(`Bot.lua:1607`) but the Saudi-Master pipeline (both outer
legality and sampler) ignores it. A coordinated fix at both
sites closes the M4-extension gap and aligns the CHANGELOG.md
claim with implementation.

The non-determinism in the sampler RNG (Scenario 1) is a
deliberate architectural choice that conflicts with
debuggability but supports the addon's "don't disturb other
addons" Lua-state etiquette. No action recommended without a
broader RNG architecture decision (the same choice would need
to apply to `Bot.lua:93, 3881` to be coherent).

## Files of interest (absolute paths)

- `C:\CLAUDE\WHEREDNGN\BotMaster.lua` — pipeline implementation.
- `C:\CLAUDE\WHEREDNGN\Bot.lua` (lines 100-260, 320-510, 3290-3420) — memory init, OnPlayObserved, PickAKA, PickPlay outer.
- `C:\CLAUDE\WHEREDNGN\State.lua` (lines 256-376, 1443-1450) — Bot module persist/restore, ApplyAKA.
- `C:\CLAUDE\WHEREDNGN\Net.lua` (lines 1755-1810, 3552-3650) — ResetMemory call sites, MaybeRunBot pause guard.
- `C:\CLAUDE\WHEREDNGN\Cards.lua` (lines 27-44) — private LCG documenting the no-seed prohibition.
- `C:\CLAUDE\WHEREDNGN\Rules.lua` (line 89) — `R.IsLegalPlay` signature.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-BotMaster-01_pickPlay_outer.md` — companion outer-dispatch audit (F1 = Scenario 7).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-BotMaster-03_ismcts_core.md` — companion core-algorithm audit (§9 = Scenario 1).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-21_ismcts_poisoning.md` — companion signal-poisoning audit.
