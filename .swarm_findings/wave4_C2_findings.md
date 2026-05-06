# Wave 4 C2 — ISMCTS Core Audit Findings

Auditor: code-review swarm agent (wave 4, batch C2)
Version: WHEREDNGN v0.4.4
Files examined: BotMaster.lua, Bot.lua, Rules.lua, Net.lua

---

## A-58 — OnEscalation legacy fallback: kind not in {double,triple,four,gahwa} → m.bels++

**VERDICT: PASS (no active defect)**

**File:line:** `Bot.lua:162-171`

**Evidence:**
Every call site in Net.lua passes a string literal:

- `Net.lua:818` — `OnEscalation(seat, "double")`
- `Net.lua:841` — `OnEscalation(seat, "triple")`
- `Net.lua:858` — `OnEscalation(seat, "four")`
- `Net.lua:873` — `OnEscalation(seat, "gahwa")`

`OnEscalation` is not exported or used from any other file; there is no indirect caller path. All four strings match the `if/elseif` branches in `Bot.lua:166-170`. The `else` fallback on line 170 (`m.bels = m.bels + 1`) is therefore unreachable in production.

**Recommendation:** The else branch is dead code that misled the audit. Add a `-- unreachable: all callers pass canonical strings` comment, or replace the else with an explicit error log (`-- else: assert(false, "unknown kind: "..tostring(kind))`) to surface any future caller regression. No logic change required.

---

## A-59 — BASE_NUM_WORLDS = 30 convergence at 8-candidate decision points

**VERDICT: WARNING**

**File:line:** `BotMaster.lua:36` (constant), `BotMaster.lua:514-517` (scaling block)

**Evidence:**
`BASE_NUM_WORLDS = 30` applies to tricks 0–3 (early game). At the first lead of the hand there are up to 8 legal cards (`#legal` could be 8 for any unrestricted leading position). With 30 worlds × 8 candidates, each candidate receives only ~3.75 evaluations per world on average. However the actual distribution is worse: `rolloutValue` is called once per candidate per world (`for _, card in ipairs(legal) do scores[card] = scores[card] + rolloutValue(...)`) — so the per-candidate sample count is exactly `numWorlds = 30`, not 30 divided by 8. Each card gets 30 independent rollout estimates regardless of the candidate set size.

So the concern in the prompt is **partially mitigated**: the sampling count per candidate is `numWorlds` (not `numWorlds / candidates`). However, 30 samples is still low statistical confidence for distinguishing candidates that differ by small expected point margins at trick 0, because rollout variance is highest early in the hand (all opponent cards are unknown, world samples are maximally diverse). The comment at `BotMaster.lua:15-17` ("30 worlds is enough to pick reliably between candidates") is an empirical assertion with no CI bound cited.

**Concrete risk:** Two candidates with true expected-value difference of ~5 raw points (common in close leads) will routinely swap rank order under 30-world sampling. The variance of `rolloutValue` spans approximately the full hand-total range (~162 pts) per sample, giving standard error of order `162/sqrt(30)` ≈ 30 points — larger than the signal being discriminated.

**Recommendation (warning, not critical):** Raise `BASE_NUM_WORLDS` to at least 50 (ideally 60 to match the trick-4 floor) for tricks 0–3 where variance is highest. Alternatively, invert the scaling direction (see A-60). The performance budget noted in the file header scales linearly — 50 worlds at ~150 ms → ~250 ms, still sub-perceptible.

---

## A-60 — Dynamic world scaling thresholds (numTricks >= 6 → 100, >= 4 → 60)

**VERDICT: WARNING**

**File:line:** `BotMaster.lua:514-517`

```
if numTricks >= 6 then numWorlds = 100
elseif numTricks >= 4 then numWorlds = 60 end
```

**Evidence:**
The scaling is monotone-increasing with trick number: 30 worlds at tricks 0–3, 60 at tricks 4–5, 100 at tricks 6–7. This is the **inverse of the uncertainty profile** of the game:

- Tricks 0–3: all opponent cards are unknown. Each world sample draws from the full unseen universe (up to ~24 cards across 3 seats). Rollout variance is maximal. This is when more worlds most improve decision quality.
- Tricks 6–7: most cards are played; each seat has 1–2 cards remaining. The number of candidate distributions is tiny. Even 10 worlds would enumerate most valid deals near-exhaustively. 100 worlds here is wasteful — many worlds will produce identical or near-identical deals.

At trick 7, `seatHandSize` returns 1 for each seat. With 3 opponents each holding exactly 1 unknown card (from `unseen` of size ≤ 3), there are at most 6 distinct permutations. Running 100 worlds samples this distribution with 16× redundancy.

**Secondary effect:** The elevated world count at late tricks is where `sampleConsistentDeal` has the highest `maxAttempts=15` failure rate risk (void constraints + meldPins on a tiny unseen pool may conflict). Retrying 15 times × 100 worlds at trick 6+ adds overhead that does nothing useful.

**Recommendation (warning):** Invert the scaling: `if numTricks <= 3 then numWorlds = 60 elseif numTricks <= 5 then numWorlds = 45 else numWorlds = 30 end`. This concentrates sampling budget where variance is highest. If late-game precision is specifically valued for tie-breaking (the design rationale not documented in the file), add an explicit comment justifying the current inversion.

---

## A-61 — buildUnseen: in-progress trick plays are excluded from unseen

**VERDICT: PASS (no defect)**

**File:line:** `BotMaster.lua:65-92`

**Evidence:**
`buildUnseen` marks seen:
1. Our own hand (`S.s.hostHands[seat]`) — lines 68-70
2. Completed tricks (`S.s.tricks`) — lines 72-76
3. In-progress trick (`S.s.trick.plays`) — lines 78-81

When it is our turn at position 2 in the current trick, position-1's card has already been added to `S.s.trick.plays` by `S.ApplyPlay`. It is therefore in the in-progress trick and marked seen (excluded from unseen). No double-exclusion: each card appears in exactly one location — either `S.s.tricks` (completed) or `S.s.trick.plays` (in-progress), never both. The completed-trick loop and the in-progress loop are disjoint by construction (a trick moves from `s.trick` to `s.tricks` atomically in `S.ApplyTrick`).

`seatHandSize` applies the same two-part scan (completed tricks + in-progress) at lines 101-111, so the hand-size estimate for the position-1 seat correctly subtracts their played card. No asymmetry between `buildUnseen` and `seatHandSize`.

**Recommendation:** No change required. Add a brief comment noting the completed/in-progress disjoint invariant to protect against future modifications to `ApplyTrick` that might break this assumption.

---

## A-63 — meldPins: meld cards from declared melds pinned to declaring seat

**VERDICT: WARNING**

**File:line:** `BotMaster.lua:160-178` (meldPins build), `BotMaster.lua:251-274` (fallback deal path)

**Evidence — main path (correct):**
The `meldPins` loop at lines 162-178 iterates `S.s.meldsByTeam`, and for each meld card tests membership in `unseen` via an inner linear scan (`for _, u in ipairs(unseen) do if u == c then ... end`). Since `unseen` already excludes played cards (via `buildUnseen`), only unplayed meld cards are pinned. A Tierce with 1 card already played will pin only the remaining 2 — correct.

The main deal path (lines 197-248) correctly separates pinned cards from the shuffle pool (line 184: `if c ~= pinCard and not meldPins[c]`) and pre-places them per seat (lines 207-209).

**Evidence — fallback path (defect):**
The fallback deal at lines 251-274 fires when all 15 `sampleConsistentDeal` attempts fail (void+size constraints unsatisfiable). This path **ignores `meldPins` entirely**:

- Line 253-255 builds the fallback pool excluding only `pinCard` (the bid card), not `meldPins` cards.
- Lines 263-270 allocate cards sequentially, with no pre-placement of meld-pinned cards to their declaring seats.
- `meldPins` is a local variable of `sampleConsistentDeal`; the fallback block is inside the same function and has access to it, but does not use it.

Result: when the fallback fires, declared meld cards can be redistributed to any seat. A Hearts Tierce (7H-8H-9H) declared by seat 2 could end up in seat 3's or seat 4's sampled hand. Rollouts using this world treat seat 2 as not holding those cards, producing systematically wrong expected values for plays that depend on knowing where the Tierce lives.

The fallback is gated by 15 failed attempts, so it fires rarely (typically only when voids + meld pins make the deal geometrically infeasible). But it is not impossible — late-game hands with multiple declared melds and tight void constraints can exhaust attempts.

**Recommendation (warning):** In the fallback path, replicate the meldPins pre-placement logic:
1. Build the fallback pool excluding both `pinCard` and all `meldPins` keys.
2. Pre-place meld-pinned cards to their respective seats before filling from the pool.
If after pre-placement a seat's required count is already satisfied (meld cards alone fill their `n`), skip further allocation for that seat. This mirrors the logic in the main path and is straightforward to add.

---

## Additional Finding: Stale Comment in rolloutValue

**VERDICT: INFO**

**File:line:** `BotMaster.lua:283-285`

The comment block reads: "We DON'T re-run R.ScoreRound to keep this fast; just sum trick points per team. Melds + belote are accounted for separately at the calling layer."

The actual code at line 475 calls `R.ScoreRound(simTricks, contract, meldsByTeam)` and uses `result.raw[myTeam]`. This directly contradicts the comment. `R.ScoreRound` is a full scoring computation including melds, belote, multipliers, and the make/fail cliff — not a simple point sum.

**Recommendation:** Update the comment to accurately describe the implementation. This is a documentation defect only; the implementation is correct (and in fact more accurate than what the comment describes).

---

## Summary Table

| Angle | Verdict  | Severity | File:Line                     |
|-------|----------|----------|-------------------------------|
| A-58  | PASS     | —        | Bot.lua:162-171 / Net.lua:818,841,858,873 |
| A-59  | WARNING  | medium   | BotMaster.lua:36, 514-517     |
| A-60  | WARNING  | medium   | BotMaster.lua:514-517         |
| A-61  | PASS     | —        | BotMaster.lua:65-92, 97-112   |
| A-63  | WARNING  | medium   | BotMaster.lua:160-178, 251-274|
| extra | INFO     | low      | BotMaster.lua:283-285         |
