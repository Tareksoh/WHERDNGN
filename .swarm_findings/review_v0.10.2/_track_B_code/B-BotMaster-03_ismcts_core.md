# B-BotMaster-03 — ISMCTS search core deep audit (BotMaster.lua)

**Target:** `C:\CLAUDE\WHEREDNGN\BotMaster.lua` (898 LOC).
**Scope:** ISMCTS search implementation — outer driver `BM.PickPlay`,
per-world rollout `rolloutValue`, rollout policy `heuristicPick`,
world-count scaling, time/memory/budget enforcement, error path.
**Mode:** Read-only. No code modified.

---

## Executive summary

`BM.PickPlay` is **flat Monte Carlo with determinization sampling** —
not a true UCT/ISMCTS tree (no node table, no UCB1 selection, no
backup, no expansion). Every move is evaluated by averaging
rollout values across `numWorlds` (30/60/100) sampled determinizations.
Per-world, every legal candidate card runs ONE rollout, scored by
`R.ScoreRound` team-diff.

**Findings:** 12 (1 high, 4 medium, 3 low, 4 informational).

| ID | Severity | Title |
|---|---|---|
| F1 | **HIGH** | Outer driver legality at line 830 omits `S.s.akaCalled` — Saudi Master tier silently AKA-blind (mirrors D-RT-18 S1, D-RT-04 F1) |
| F2 | MEDIUM | Rollout `heuristicPick` at line 649 omits AKA — defensible per CHANGELOG but inconsistent with F1 (D-RT-18 S3) |
| F3 | MEDIUM | `math.random` in `shuffle`/biased pick is non-deterministic across hosts; replays/resyncs cannot reproduce sampler decisions |
| F4 | MEDIUM | No time-budget enforcement — only documented "~150 ms" expectation. End-game `numWorlds=100` × 8 candidates × 25 plays = 20 000 sim plays unconditionally |
| F5 | MEDIUM | Rollout re-detects melds from SAMPLED hands via `R.DetectMelds` rather than using `S.s.meldsByTeam`. Over-counts opp melds when sampler invents sequences/carrés never actually held |
| F6 | LOW | No tree / node table → no learning across candidates. Pure flat MC. Comments accurately state "flat Monte Carlo" but the file is named "ISMCTS" |
| F7 | LOW | `for _, t in ipairs(S.s.tricks or {}) do simTricks[#simTricks + 1] = t end` shallow-references real trick objects; `R.ScoreRound` is read-only so safe today, but a refactor that mutates simTricks would corrupt live state |
| F8 | LOW | Per-world pcall granularity hides `err` — only `rolloutErrors` count is kept. No log of which world failed or why |
| F9 | INFO | Action space (legal cards) computed ONCE in outer driver (line 826-832); same legal list applies across all 100 worlds. Correct for ISMCTS-flat |
| F10 | INFO | Per-world rollout depth = full-game (`while #simTricks < 8`), not trick-end. Defensible — Saudi rounds are short (8 tricks) |
| F11 | INFO | "Memory bounds": no node table; only `scores[card]` (≤8 entries) + `world[s]` deals (≤32 cards × 4) + `simTricks` (≤8 tricks). Bounded |
| F12 | INFO | Backup propagation: simple sum over worlds. No averaging visible (`scores[card] = scores[card] + rolloutValue`). Argmax over sums = argmax over averages, so ranking is correct |

---

## Audit dimension by dimension

### 1. Determinization sample count (number of worlds)

`BotMaster.lua:850-854`:

```lua
local numTricks = #(S.s.tricks or {})
local numWorlds
if numTricks <= 2 then numWorlds = 100
elseif numTricks <= 5 then numWorlds = 60
else numWorlds = BASE_NUM_WORLDS end
```

`BASE_NUM_WORLDS = 30` (line 36).

- Trick 0-2: 100 worlds.
- Trick 3-5: 60 worlds.
- Trick 6+: 30 worlds.

**Rationale (header comment 840-849):** scale UP for early tricks
(maximum uncertainty), DOWN as round nears determinism.

**Verdict: SOUND.** This matches standard ISMCTS practice. Pre-existing
fix (the file's comment notes "previous code was inverted"). No issue.

---

### 2. Per-world rollout depth (full game vs trick-end)

`BotMaster.lua:758-780`:

```lua
while #simTricks < 8 do
    if #currentTrick.plays == 4 then
        local winner = R.CurrentTrickWinner(currentTrick, contract)
        ...
    else
        ...
    end
end
```

Each rollout simulates **to round end** (8 tricks total, including
already-completed tricks loaded into `simTricks` at line 622).

**Verdict: SOUND.** Saudi rounds are 8 tricks; full-depth rollout is
appropriate. Cost is bounded (≤8 tricks × 4 plays per rollout =
≤32 simulated plays per candidate × ≤8 candidates × 100 worlds =
~25 600 plays per move at peak). Matches the "~6000 plays" estimate
in the header comment for the typical mid-game case.

---

### 3. UCB1 selection or simpler greedy?

**No UCB1.** No node table, no visit counts, no exploration term.

`BotMaster.lua:874-897`:

```lua
local rolloutErrors = 0
for w = 1, numWorlds do
    local ok, err = pcall(function()
        local world = sampleConsistentDeal(seat, unseen)
        if world then
            for _, card in ipairs(legal) do
                scores[card] = scores[card]
                              + rolloutValue(seat, card, world, S.s.contract)
            end
        end
    end)
    ...
end
...
local best, bestScore = legal[1], -math.huge
for _, c in ipairs(legal) do
    if scores[c] > bestScore then best, bestScore = c, scores[c] end
end
```

Each candidate gets `numWorlds` rollouts (one per sampled world),
score is summed, argmax wins. **Pure flat Monte Carlo.**

**Verdict: F6 (informational).** The file header (line 1, 13)
acknowledges this: *"This is 'flat Monte Carlo' rather than full UCT,
but with the existing heuristic rollouts it converges fast: 30
worlds is enough."* The naming "ISMCTS-flavoured" in the comment is
load-bearing — it's not a tree search. No defect; document for
expectations.

---

### 4. Backup propagation

`BotMaster.lua:880-882`:

```lua
scores[card] = scores[card]
              + rolloutValue(seat, card, world, S.s.contract)
```

Simple SUM across worlds. No discounting, no virtual-loss, no
averaging division. Argmax over sums == argmax over (sum / N) when N
is constant per candidate, so the ranking is correct.

**Verdict: F12 (informational).** Correct ranking. Per-candidate sums
are NOT directly interpretable as "expected diff per world" without
dividing by `numWorlds - rolloutErrors`, but the only consumer is
the argmax, which doesn't care about scale.

**Subtle:** if a candidate sometimes errors out for some worlds (its
inner pcall fires) and another candidate doesn't, the surviving
candidate gets MORE non-zero contributions. Look at the pcall
structure carefully:

```lua
for w = 1, numWorlds do
    local ok, err = pcall(function()
        local world = sampleConsistentDeal(seat, unseen)
        if world then
            for _, card in ipairs(legal) do
                scores[card] = scores[card]
                              + rolloutValue(seat, card, world, S.s.contract)
            end
        end
    end)
    if not ok then rolloutErrors = rolloutErrors + 1 end
end
```

The pcall wraps the **entire candidate sweep for one world**. If
candidate #3's rollout throws, it aborts the sweep — candidates
#1 and #2 already added their values, but candidates #4, #5, … get
NOTHING for that world. So an error mid-sweep silently biases
ranking AGAINST cards listed earlier in `legal` (they get the
"failure" world's signal; later cards get nothing for that world).

**Magnitude:** small in practice (per-world failures are rare per
the v0.8.6 H4 historical fix), but mathematically the asymmetry
exists. Worth flagging for closer log-instrumentation if anyone
ever cares. **Catalog as part of F8.**

---

### 5. Action space (legal cards) computation per node

`BotMaster.lua:826-832`:

```lua
-- Build legal-plays list.
local trick = S.s.trick or { leadSuit = nil, plays = {} }
local legal = {}
for _, c in ipairs(hand) do
    local ok = R.IsLegalPlay(c, hand, trick, S.s.contract, seat)
    if ok then legal[#legal + 1] = c end
end
if #legal == 0 then return _restore(nil) end
if #legal == 1 then return _restore(legal[1]) end
```

- Computed ONCE (the legal-set for the bot's actual current move).
- Re-used across all `numWorlds` worlds.

**Correctness.** The bot's own legal moves don't depend on opponent
hands, so a single computation suffices. Standard ISMCTS practice —
the determinization affects rollout values, not the bot's own
action space at the root. **F9 (informational).**

**However:** the legality call here is the **F1** site:

```lua
local ok = R.IsLegalPlay(c, hand, trick, S.s.contract, seat)
```

— omits 6th param `akaCalled`. See F1 below.

---

### 6. heuristicPick at line 649 omits akaCalled (F2)

**Restated from prompt:** D-RT-18 S3, B-BM-01.

`BotMaster.lua:644-655`:

```lua
-- Helper: pick a card using pro-level heuristics (Advanced-mirror).
local function heuristicPick(s, trick)
    local hand = hands[s]
    local legal = {}
    for _, c in ipairs(hand) do
        if R.IsLegalPlay(c, hand, trick, contract, s) then
            legal[#legal + 1] = c
        end
    end
    if #legal == 0 then return nil end
    if #legal == 1 then return legal[1] end
    ...
```

The 6th arg `akaCalled` is omitted on the `R.IsLegalPlay` call.
Per `Rules.lua:89, 111-121`:

```lua
function R.IsLegalPlay(card, hand, trick, contract, seat, akaCalled)
...
local akaRelief = false
if akaCalled and akaCalled.seat and akaCalled.suit
   and seat and R.Partner(seat) == akaCalled.seat
   and akaCalled.suit == leadSuit
   and contract and contract.type == K.BID_HOKM then
    akaRelief = true
end
```

Without the param, `akaRelief` is always `false` in the rollout.
M4 receiver-relief dies: a void+trump receiver in the simulated
trick will be **filtered to trumps-only** when in real play they
could discard a low non-trump.

**Direction-of-bias (per D-RT-18 S3):**
- Rollout simulates partner-receiver burning trump under opp
  over-trump.
- Bot under-values AKA-leveraging plays (low-risk leads relying
  on partner relief).
- Bot over-conservatively avoids AKA-style strategy.

**CHANGELOG framing (CHANGELOG.md:22):** *"Simulator callers …
deliberately omit the param so rollouts get AKA-blind semantics
(transient banner state shouldn't propagate into hypothetical
futures)."* — defensible argument that simulating an AKA-blind
partner is robust against partners who don't read the convention.

**However**, F2 is INTERNALLY CONSISTENT only if F1 also stays
AKA-blind (current state). If F1 is fixed (driver becomes
AKA-aware) but rollout stays blind, the bot's outer-loop
legality says "I have these 4 cards including 2 non-trumps"
while the rollout simulates partner burning trump — two timelines
treated inconsistently.

**Severity: MEDIUM (calibration issue).** Per D-RT-18 S3 the
correct fix sketch is *per-trick gating*: pass `S.s.akaCalled` to
`heuristicPick` for the FIRST simulated trick (where the live
banner is still active per `State.lua:1327` clear), then `nil` for
subsequent simulated tricks.

---

### 7. Outer driver legality at line 830 (F1) — D-RT-04 F2 ramification

**Restated from prompt:** D-RT-04 F2 mentions "ISMCTS rollouts
AKA-blind undercount opp legal moves" — but the more critical
point is the OUTER DRIVER omission at line 830, which makes the
bot's own legal-card list AKA-blind. F1 is the bot's own legality;
F2 (above) is the rollout opp simulation.

`BotMaster.lua:830`:

```lua
local ok = R.IsLegalPlay(c, hand, trick, S.s.contract, seat)
```

**This is NOT a rollout** — it's the live decision-point for the
Saudi Master bot. When the bot is the AKA-receiver and partner has
been over-trumped by an opp:

- Without `akaCalled`: legal-list contains only trumps (must-ruff
  fires). Bot ruffs.
- With `akaCalled`: legal-list contains discards too. Bot discards
  low non-trump, preserves trump.

Per D-RT-18 §2 (full reproduction trace):

> Restart the geometry. Bot is **seat 3**. Partnership 1↔3. Seat 1
> (our partner) led `AS` and called AKA on S → `akaCalled =
> {seat=1, suit="S"}`. Seat 2 (opp) cut with `2D`. **R.CurrentTrickWinner
> = seat 2** (the trump beat the spade). Now seat 3 (us) is up.
> Hand: `{7H, 8H, JD, QD}` — void in S, has trump.
>
> **Without `akaCalled` arg:** … `legal = {JD, QD}`. ISMCTS picks
> one of the two trumps and ruffs.
>
> **With `akaCalled` arg (M4 relief):** … `legal = {7H, 8H, JD,
> QD}`. Heuristic picks lowest non-trump → `7H`.

This is the canonical M4-target case — opp over-trumped partner's
AKA'd lead, receiver should discard low, NOT ruff. The CHANGELOG
v0.10.2 M4 entry claims "every live-game legality check" was
updated; **`BotMaster.lua:830` is a live-game site that was
missed**.

**Severity: HIGH.** Saudi Master tier (the highest tier) silently
reverts to AKA-blind legality, **negating the v0.10.2 M4 fix's
primary intended beneficiary**.

**Cross-reference:** D-RT-18 S1, D-RT-04 F1, B-BM-01 (per prompt).

---

### 8. Time budget enforcement

`BotMaster.lua:18-23` (header comment):

```
--   • Performance budget: ~30 worlds × ≤8 candidates × ~25 cheap
--     play decisions ≈ 6000 simulated plays per move. Lua trick-
--     resolution is microsecond-scale; total move time ~150 ms,
--     perceptually instant.
```

This is **descriptive, not enforced**. No `debugprofilestop` /
`GetTime` / deadline check anywhere in `BotMaster.lua`.

End-game peak with `numWorlds=100`: 100 × 8 × 25 ≈ 20 000 sim
plays. With `numTricks ≤ 2` (early tricks), the early-game `numWorlds`
of 100 fires when the determinization sample space is largest, the
heuristic is most expensive (full 8-trick rollout depth), AND the
bot is most likely to be picking among ≥6 candidates. Real-world
peak measurement absent.

**Verdict: F4 (medium).** No mitigation if a future change
(e.g., increase to 200 worlds, or richer rollout policy) blows the
~150 ms budget. The host's `Net.lua` `MaybeRunBot` outer pcall
catches errors but doesn't enforce deadlines, so a slow rollout
just freezes WoW for the full computation. WoW's main-thread script
budget is ~16 ms/frame (60 fps); 150 ms = 9 dropped frames. Today
acceptable; tomorrow brittle.

---

### 9. Seed source — math.random determinism

`BotMaster.lua:188-194`:

```lua
-- Random shuffle in-place.
local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
end
```

Plus line 508:

```lua
if weight > 0 and math.random() < pickProb then
```

Both use the **global `math.random` state**, which `Cards.lua:27-29`
explicitly does NOT seed:

> *"NOT call math.randomseed() — WoW's lua state is shared across
> addons and resetting the global RNG can disrupt others'
> math.random use."*

Implications:
- **Non-deterministic across hosts.** Each host runs its own
  `math.random` state seeded by WoW's process state. Different
  hosts make different sampler choices.
- **Replays/resyncs cannot reproduce decisions.** Useful for
  Net.lua's resync replay only because the OUTPUT (the picked card)
  is on the wire — the sampler isn't replayed remotely.
- **Tests use `math.randomseed(20260503)` etc.** to get reproducible
  rollouts (`tests/test_baseline_metrics.lua:94`). Production has
  no equivalent.

`Cards.lua` uses a **deterministic LCG** (`lcgSeed` + `lcgNext`,
lines 30-44) for deck shuffling — explicitly so deals are
reproducible across hosts via shared seed (the host broadcasts the
seed in the deal frame). `BotMaster.lua` does not adopt this LCG
for sampler shuffles.

**Verdict: F3 (medium).** The non-determinism doesn't cause
correctness bugs (any sample is internally consistent), but:
- Cross-host playback / debugging of bot decisions is impossible.
- Tests can pin sampler seed only by clobbering `math.random`
  globally (which contradicts Cards.lua's prohibition).
- A determinism-quality regression would silently hide in
  per-game flake.

A drop-in fix would be to use the existing `B.Cards`-style LCG
(or a fresh per-call LCG seeded from `S.s.handSeed + numTricks +
seat`) for `BotMaster.shuffle` and biased-pick. Out of scope per
brief.

---

### 10. Memory bounds — node table growth

**No node table.** No `tree[state]` map, no `children[node]` arrays.

Per-call allocations (rolloutValue):
- `initialHands[s]` — 4 arrays of ≤8 cards each = 32 entries.
- `hands[s]` — ditto, ≤32.
- `simTricks` — ≤8 trick objects (mostly references to
  `S.s.tricks[]` plus 0-8 fresh ones for the simulated suffix).
- `currentTrick.plays` — ≤4 entries.
- `legal` array per `heuristicPick` call — ≤8 entries.

Per-driver allocations (BM.PickPlay):
- `unseen` — ≤24 cards.
- `scores[card]` — ≤8 entries.
- `world[s]` — 4 arrays of ≤8 cards.

**Worst-case heap pressure per move:** ~100 small tables, all GC'd
at function exit. **F11 (informational).** Bounded; no leak risk.

A large-N change (>>100 worlds) would multiply per-move allocation
linearly but not super-linearly — Lua GC is fine with this. No
defect.

---

### 11. Score evaluation at terminal — uses R.ScoreRound or simplified?

`BotMaster.lua:782-806`:

```lua
-- Accurate round scoring including melds and make/fail cliffs.
local meldsByTeam = { A = {}, B = {} }
for s = 1, 4 do
    local team = R.TeamOf(s)
    local m = R.DetectMelds(initialHands[s], contract)
    for _, meld in ipairs(m) do
        meld.declaredBy = s
        table.insert(meldsByTeam[team], meld)
    end
end

local result = R.ScoreRound(simTricks, contract, meldsByTeam)
local oppTeam = (myTeam == "A") and "B" or "A"
local diff = (result.raw[myTeam] or 0) - (result.raw[oppTeam] or 0)
if result.gahwaWonGame and result.gahwaWinner then
    if result.gahwaWinner == myTeam then diff = diff + 10000
    else diff = diff - 10000 end
end
return diff
```

Uses `R.ScoreRound` — the full real scoring function. Header comment
at lines 586-588 contradicts this:

```
--   • We DON'T re-run R.ScoreRound to keep this fast; just sum
--     trick points per team. Melds + belote are accounted for
--     separately at the calling layer.
```

— but this is **stale**. The "26th-audit fix" comment at lines
794-805 confirms the refactor:

> *"return TEAM DIFF (us - them) rather than just our raw points.
> This puts both candidate-A 'we make by 5' (+162) and candidate-B
> 'we fail by 2' (-162) onto a single ranking axis where the
> contract-outcome cliff dominates raw-point fluctuation."*

So a stale comment vs. real behaviour. Cosmetic.

**The substantive issue is F5: meld re-detection.** `R.DetectMelds`
returns ALL POSSIBLE melds in the FULL 8-card hand (Rules.lua:220-251).
The rollout calls it on `initialHands[s]` = the SAMPLED + already-played
combined cards.

For the bot's own seat: this is the real hand (all 8 cards). Detect
returns the actual melds the bot could have declared.

**For other seats (sampled):** the cards are partially RANDOM. So the
rollout INVENTS melds (sequences, carrés) for opps and partner that
they may never actually have held. The real hand might have lacked the
9 of D needed for a Hearts 7-8-9-T-J seq5, but the sampler placed it
there → `R.DetectMelds` reports a 100-meld for that seat.

**The real game's melds are in `S.s.meldsByTeam`** (declared at trick
1). The rollout IGNORES this and fabricates melds from sampled hands.

**Effect on value estimation:**
- For Hokm contracts, opp melds count toward the bidder's "fail"
  threshold via `R.CompareMelds` (Rules.lua:760). Inflated opp melds
  → bidder more likely to "fail" in the rollout → value estimate
  pessimistic for bidder, optimistic for defenders.
- A bidder bot evaluating its own move SEES its opp's sampled meld
  count, which is biased upward.
- Bidder bots will play more conservatively than reality justifies.

**Mitigation in real code:** the sampler tries to pin declared meld
cards (lines 244-260) — `meldPins[c] = m.declaredBy`. So if seat 3
declared "Hearts Tierce 7-8-9", those 3 cards stay with seat 3 across
sampled worlds. **But** undeclared melds that NEVERTHELESS exist
mathematically (e.g., the bot's opp has T+J+Q of S in the unsampled
universe, and the sampler distributes those 3 cards to that opp by
chance) WILL be detected by `R.DetectMelds` and counted as if
declared.

**Severity: F5 (medium).** Subtle but persistent. Defensible as
"average over sample" but biases estimate of opp meld value
upward. Real fix: pass `S.s.meldsByTeam` into `R.ScoreRound` directly,
skipping the per-world re-detection. (The header comment at 586-588
hints this was the original design; somewhere the refactor lost the
skip-meld-detection branch.)

---

### 12. Error path — what if all rollouts fail / time out?

`BotMaster.lua:874-891`:

```lua
local rolloutErrors = 0
for w = 1, numWorlds do
    local ok, err = pcall(function()
        local world = sampleConsistentDeal(seat, unseen)
        if world then
            for _, card in ipairs(legal) do
                scores[card] = scores[card]
                              + rolloutValue(seat, card, world, S.s.contract)
            end
        end
    end)
    if not ok then rolloutErrors = rolloutErrors + 1 end
end
-- If literally every world errored (suggests a deterministic bug
-- not a sampling edge), fall back to heuristics with restored flag.
if rolloutErrors == numWorlds then
    return _restore(nil)
end
```

**Per-world pcall** (v0.8.6 H4 fix per the inline comment). One bad
world doesn't poison all 100. Aggregate ranking continues with the
healthy worlds.

**If every world errors:** return nil → caller (Bot.PickPlay at
3382-3386) falls through to heuristics. Correct safety path.

**Time-out:** there is none. A slow rollout just freezes WoW for
its duration. See F4.

**The captured `err` is DROPPED** — only the count is kept, not
which world failed or why. This makes diagnosing rollout bugs hard.
Pre-v0.8.6 (per comment) the err was bubbled up via a single outer
pcall; the current per-world granularity loses that diagnostic.

**Verdict: F8 (low).** Defensible (avoids log spam in a hot path)
but a `Log.Debug(err)` would help future debugging without
impacting normal operation.

---

### 13. Driver flow — recursion guard, restore semantics

`BotMaster.lua:812-823`:

```lua
function BM.PickPlay(seat)
    if not BM.IsActive() then return nil end
    if not S.s.contract then return nil end
    -- v0.5 C-1 recursion guard: ...
    local prevRollout = B.Bot._inRollout
    B.Bot._inRollout = true
    local function _restore(v) B.Bot._inRollout = prevRollout; return v end
    local hand = S.s.hostHands and S.s.hostHands[seat]
    if not hand or #hand == 0 then return _restore(nil) end
```

**Recursion guard:** `_inRollout` is set true so any nested
`Bot.PickPlay` call (via heuristicPick, etc.) bypasses the
delegation at `Bot.lua:3381-3386` and falls into heuristic mode.
Save/restore (`prevRollout`) supports nested host calls (rare but
defensive). Mirrors Bot.lua's contract for `_inRollout`.

**Note:** `heuristicPick` at line 645-755 is a LOCAL CLOSURE in
`rolloutValue`, NOT a call to `Bot.PickPlay`. The recursion guard
is currently redundant (defensive), but the flag IS read by other
code paths (e.g., Bot.lua's `legalPlaysFor` may consult it). Worth
preserving.

**Restore semantics on error.** `pcall` at line 876 catches errors
inside the world loop; `_restore` is called on the normal return
path at line 897. **Q: what if an error throws BETWEEN line 836
(buildUnseen) and line 875 (the pcall loop)?** Then `_inRollout`
stays `true` and Saudi Master ISMCTS is silently disabled until
process exit (the v0.5.3 BUG fix path the comment 856-863 describes).

**Looking at lines 836-873:** `buildUnseen(seat)` could throw on
malformed `S.s.tricks`. Pre-loop variable assignments (`scores`,
`numWorlds`, etc.) are safe — pure-table ops. The inner pcall
covers from line 876 onward.

**Verdict: small surface for the leak — `buildUnseen` throws on
malformed state.** Low probability but not impossible. Could
extend the pcall to cover buildUnseen too, OR wrap the whole
function body in pcall. Cosmetic-low.

---

## Cross-references with prompt's known findings

| Prompt item | This audit | Status |
|---|---|---|
| Item 6: heuristicPick at line 649 omits akaCalled — D-RT-18 / B-BM-01 | F2 | **REPRODUCED**; defensible per CHANGELOG; calibration question if F1 fixed |
| Item 7: D-RT-04 F2 — ISMCTS rollouts AKA-blind undercount opp legal moves | F2 (rollout) + F1 (driver) | **REPRODUCED**; both sites flagged — F1 is the more critical site (live decision, not simulation) |

---

## Recommended priority order (non-binding, brief said don't modify)

1. **F1 [HIGH]** — `BotMaster.lua:830` add `S.s.akaCalled`. One-arg fix. Negates the v0.10.2 M4 changelog claim's intent for Saudi Master tier.
2. **F4 [MED]** — Add `debugprofilestop`-based deadline check in the world loop. Bail at 150 ms with whatever scores are accumulated.
3. **F5 [MED]** — Pass `S.s.meldsByTeam` to `R.ScoreRound`; skip per-world meld re-detection (or only re-detect on the SAMPLED 5 cards from deal-2, since deal-1 melds are already declared).
4. **F2 [MED]** — Calibrate per-trick AKA gating in `heuristicPick`: live banner for first simulated trick, blind for subsequent.
5. **F3 [MED]** — Adopt `Cards.lua` LCG for sampler shuffles. Seeded from `S.s.handSeed XOR seat XOR numTricks`.
6. **F7 [LOW]** — Defensive copy of `S.s.tricks` entries in `simTricks`; or document the read-only contract.
7. **F8 [LOW]** — Log first rollout `err` per move (Log.Debug, rate-limited).

---

## Confidence

**HIGH confidence:**
- F1 — reproduced via D-RT-18 §2 trace. The bot ruffs when M4 says discard.
- F2 direction-of-bias.
- F3 use of global math.random.
- F4 absence of deadline check.
- F6 flat-MC-not-UCT.
- F9, F10, F11 structural facts.
- F12 sum-vs-average ranking equivalence.

**MEDIUM confidence:**
- F5 — meld re-detection bias direction (toward over-counting opp melds) is clear; magnitude depends on how often the sampler invents a 3+ sequence the real hand lacked. No empirical measurement attached.
- F7 — `simTricks` shallow-references real ticks; safe today but refactor-fragile. Hard to estimate how often a future contributor would mutate.

**LOW confidence:**
- Whether F2 should be fixed at all, or whether the AKA-blind rollout is the conscious design choice. Calibration question per D-RT-18 S3.

---

## Quoted code snippets (load-bearing)

**F1 — outer driver legality (line 826-832):**

```lua
-- Build legal-plays list.
local trick = S.s.trick or { leadSuit = nil, plays = {} }
local legal = {}
for _, c in ipairs(hand) do
    local ok = R.IsLegalPlay(c, hand, trick, S.s.contract, seat)
    if ok then legal[#legal + 1] = c end
end
```

**F2 — rollout heuristicPick legality (line 644-655):**

```lua
-- Helper: pick a card using pro-level heuristics (Advanced-mirror).
local function heuristicPick(s, trick)
    local hand = hands[s]
    local legal = {}
    for _, c in ipairs(hand) do
        if R.IsLegalPlay(c, hand, trick, contract, s) then
            legal[#legal + 1] = c
        end
    end
    if #legal == 0 then return nil end
    if #legal == 1 then return legal[1] end
```

**F3 — math.random shuffle (line 188-194):**

```lua
-- Random shuffle in-place.
local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
end
```

**F5 — meld re-detection (line 782-791):**

```lua
-- Accurate round scoring including melds and make/fail cliffs.
local meldsByTeam = { A = {}, B = {} }
for s = 1, 4 do
    local team = R.TeamOf(s)
    local m = R.DetectMelds(initialHands[s], contract)
    for _, meld in ipairs(m) do
        meld.declaredBy = s
        table.insert(meldsByTeam[team], meld)
    end
end
```

**F12 — backup propagation (line 879-882):**

```lua
for _, card in ipairs(legal) do
    scores[card] = scores[card]
                  + rolloutValue(seat, card, world, S.s.contract)
end
```

---

## Appendix — file-level structural map (BotMaster.lua)

| Lines | Section |
|---|---|
| 1-27 | Header / design notes |
| 29-36 | Module setup, BASE_NUM_WORLDS = 30 |
| 39-129 | Helpers: getStrongCards, getDefenderCards, getPartnerCards |
| 131-134 | BM.IsActive |
| 136-166 | buildUnseen — full deck minus seen |
| 168-186 | seatHandSize |
| 188-194 | shuffle (math.random — F3) |
| 196-577 | sampleConsistentDeal — biased determinization |
| 580-807 | rolloutValue — full-game rollout, returns team-diff |
|   …592-642 | rollout setup (initialHands, hands, simTricks) |
|   …644-755 | heuristicPick — rollout policy (F2 at 649) |
|   …757-780 | sim loop (8-trick rollout) |
|   …782-806 | meld re-detection + R.ScoreRound (F5) |
| 809-898 | BM.PickPlay — outer driver |
|   …812-823 | recursion guard |
|   …826-832 | legal-plays computation (F1) |
|   …836-854 | unseen, scores, dynamic numWorlds |
|   …874-891 | per-world pcall loop, error path (F8) |
|   …893-897 | argmax over scores |

---

*End of audit.*
