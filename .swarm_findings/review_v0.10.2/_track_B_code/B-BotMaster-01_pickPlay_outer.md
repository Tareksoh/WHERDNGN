# B-BotMaster-01 — Audit of `BotMaster.PickPlay` outer dispatch + tier delegation

**Target:** `BotMaster.lua:812-898` (`BM.PickPlay`), with cross-checks
into `Bot.lua:3372-3402` (`Bot.PickPlay` outer entry), `Bot.lua:1600-1614`
(`legalPlaysFor` heuristic helper), and `BotMaster.lua:644-755`
(`heuristicPick` rollout policy inside `rolloutValue`).

**Brief audit-scope items 1-10 covered.** Severity classifications
align with the v0.10.2 review track-D findings. Confidence column
reflects whether a concrete fail-case was reproduced or only
analytical.

**No code modified — review-only.**

---

## Summary table

| # | Finding | Severity | Confidence |
|---|---|---|---|
| F1 | `BotMaster.PickPlay:830` omits `akaCalled` — Saudi-Master decision-point reverts to AKA-blind legality, negating v0.10.2 M4 for the highest tier | **HIGH** | reproduced |
| F2 | Outer `R.IsLegalPlay` call is 5-arg (no `akaCalled`) vs the 6-arg correct form used in `Bot.lua:1610` and the three Net.lua sites | **HIGH** | mechanical (same as F1) |
| F3 | Tier dispatch chain is correctly single-pathed through `Bot.PickPlay` (per CLAUDE.md v0.5.0 fix); no double-rollout regression | OK | confirmed |
| F4 | ISMCTS top-level invocation is gated by `BM.IsActive()` + `_inRollout` recursion guard — recursion-safe | OK | confirmed |
| F5 | Number-of-worlds dynamic scaling (100 / 60 / 30) is sane; no wall-clock budget enforced | LOW | analytical |
| F6 | Determinism — no explicit seed control; `math.random` used in shuffle (line 191) and weighted sampling (line 508) | LOW | analytical |
| F7 | Phantom `R.SunCanRolloff` reference at `Bot.lua:1605` and `CHANGELOG.md:22` — function does not exist | INFO | confirmed |
| F8 | CLAUDE.md v0.5.0 single-delegation rule honored; the recursion guard (`_inRollout`) is set/restored even though `heuristicPick` is currently a local closure | OK | confirmed |
| F9 | Sun contracts go through the same `BM.PickPlay` outer path; no Sun-specific dispatch divergence at the outer level (Sun-specific handling is only inside `heuristicPick` lead branch) | OK | confirmed |
| F10 | Edge cases: 1-card hand fast-pathed correctly; AKA-active handled wrongly (per F1); paused-state not checked at `BM.PickPlay` entry | LOW | partly reproduced |

---

## F1 [HIGH] — `BotMaster.PickPlay:830` omits `akaCalled`, negating v0.10.2 M4 at Saudi-Master tier

### Where

`BotMaster.lua:826-832`:

```lua
-- Build legal-plays list.
local trick = S.s.trick or { leadSuit = nil, plays = {} }
local legal = {}
for _, c in ipairs(hand) do
    local ok = R.IsLegalPlay(c, hand, trick, S.s.contract, seat)
    if ok then legal[#legal + 1] = c end
end
```

Compare `Bot.lua:1600-1614` (`legalPlaysFor` for tiers Basic/Advanced/M3lm/Fzloky):

```lua
local function legalPlaysFor(hand, trick, contract, seat)
    -- v0.10.2 M4: pass live `s.akaCalled` to R.IsLegalPlay so the
    -- AKA-receiver relief (J-066/J-067) is honored at the legality
    -- layer.
    local aka = S and S.s and S.s.akaCalled or nil
    local out = {}
    for _, c in ipairs(hand) do
        local ok = R.IsLegalPlay(c, hand, trick, contract, seat, aka)
        if ok then out[#out + 1] = c end
    end
    return out
end
```

The Saudi-Master path drops the 6th argument.

### Why it matters — dispatch chain

`Bot.lua:3381-3387`:

```lua
if not Bot._inRollout then
    local BM = WHEREDNGN and WHEREDNGN.BotMaster
    if BM and BM.IsActive and BM.IsActive() and BM.PickPlay then
        local masterCard = BM.PickPlay(seat)
        if masterCard then return masterCard end
    end
end
```

When `WHEREDNGNDB.saudiMasterBots == true`, control reaches
`BM.PickPlay` BEFORE `legalPlaysFor` is ever consulted. If `BM.PickPlay`
returns a non-nil card it is returned immediately and the M4-fixed
`legalPlaysFor` path at line 3394 is **never reached**.

### Repro

Canonical opp-over-trump scenario (the one M4 was added to handle):

- HOKM, trump = D. Partnerships 1↔3, 2↔4.
- Bot at **seat 3** with `WHEREDNGNDB.saudiMasterBots = true`.
- Hand seat 3: `{7H, 8H, JD, QD}` (void in Spades, has trump).
- Trick state: seat 1 (our partner) led `AS` and called AKA on Spades
  → `S.s.akaCalled = { seat=1, suit="S" }`. Seat 2 (opp) cut with
  `2D` (lowest trump). Seat 3 is up.
- `R.CurrentTrickWinner(trick, contract) = 2` (the trump beat the
  spade), so the `partner-winning shortcut` at `Rules.lua:166-169`
  does NOT fire.

**Expected (M4 with `akaCalled` passed):**

- `R.Partner(3) = 1`; `akaCalled.seat = 1`; `akaCalled.suit = "S" =
  trick.leadSuit`; contract is HOKM. → `akaRelief = true` at
  `Rules.lua:115-121`.
- At `Rules.lua:175`: `if akaRelief then return true end` → all 4
  cards legal.
- `legal = {7H, 8H, JD, QD}` → ISMCTS rolls out, picks the card
  preserving trump (typically a 7H or 8H discard).

**Actual at `BotMaster.lua:830` (no `akaCalled`):**

- `akaRelief` flag is `false` (param is nil).
- `hasLead = false` (void in S). Skip must-follow.
- Skip Sun. Skip partner-winning shortcut (opp wins).
- Falls to must-trump-ruff (`Rules.lua:177-184`): seat 3 has trump
  `{JD, QD}`. The check `if not C.IsTrump(card, contract) then
  return false, "must trump" end` rejects `7H, 8H`.
- `legal = {JD, QD}` only — ISMCTS only picks between two trumps.
- Saudi-Master ruffs (often with mid-trump JD/QD when discard is
  the strategically correct play under Saudi convention).

### Severity rationale

This is the **single highest-impact bug for the v0.10.2 release**:
the M4 fix's primary justification in CHANGELOG.md is "match canonical
Saudi pro conventions for AKA mechanics", but the tier most
prominently advertised as Saudi-pro-strength (`saudiMasterBots`) is
the only tier that does NOT receive the fix. The outer-dispatch
asymmetry produces a silent regression visible only when a player
runs Saudi-Master AND the canonical opp-over-trump-after-AKA
scenario occurs.

Aligns with D-RT-18 §2 (S1) and the brief's reference to D-RT-04 F1.

---

## F2 [HIGH] — `R.IsLegalPlay` 5-arg call vs 6-arg form

This is the mechanical observation underlying F1. Listing separately
because the audit-scope brief asked specifically about arity.

`R.IsLegalPlay` signature (`Rules.lua:89`):

```lua
function R.IsLegalPlay(card, hand, trick, contract, seat, akaCalled)
```

Caller-arity audit across the codebase (cross-confirmed against
D-RT-18 §1 table):

| Caller | Arity | AKA-aware? |
|---|---|---|
| `Bot.lua:1610` (`legalPlaysFor`) | 6 | yes |
| `Net.lua:2040` (`LocalPlay` warn) | 6 | yes |
| `Net.lua:3412` (`_HostCheckTurnTimer`) | 6 | yes |
| `Net.lua:4136` (host-side meld fallback) | 6 | yes |
| `State.lua:1219` (`S.ApplyPlay` Takweesh) | 6 | yes |
| `BotMaster.lua:830` (`BM.PickPlay`) | **5** | **no** ← bug |
| `BotMaster.lua:649` (`heuristicPick` rollout) | 5 | no (defensible per CHANGELOG framing) |
| `Rules.lua:435` (`R.IsValidSWA` minimax) | 5 | no (separate finding, see B-Rules-04) |
| `State.lua:1665` (`S.HostValidatePlay` dead) | 5 | no (latent — D-RT-18 §4) |
| `State.lua:1966` (`S.GetLegalPlays` UI) | 5 | no (UI dimming bug, D-RT-18 §3) |

The CHANGELOG line 22 claim that `legalPlaysFor` "passes
`S.s.akaCalled` through to every live-game legality check" is
**false** — `BotMaster.lua:830` is a live-game legality check that
omits the param. This is a documentation accuracy issue layered on
top of the code bug.

---

## F3 [OK] — Tier dispatch chain correctly single-pathed

CLAUDE.md v0.5.0 fix specifies: *"`Bot.PickPlay` delegates internally
to `BotMaster.PickPlay` when Saudi Master tier is active. **Do NOT
add a second explicit `BotMaster.PickPlay` call** at any caller site
— that causes double-rollout. The single canonical entry is
`Bot.PickPlay`."*

Verified by `Grep` for `BM.PickPlay` and `BotMaster.PickPlay` in
`Net.lua`, `Bot.lua`, `State.lua`:

- `Bot.lua:3384` — the single canonical delegation.
- `BotMaster.lua:812` — the function definition itself.

No other caller invokes `BM.PickPlay` directly. CLAUDE.md rule
honored. No double-rollout.

`Bot.lua:3373-3380` comment confirms the reasoning: pre-v0.5 only
`Net.lua`'s `MaybeRunBot` reached the sampler, so AFK timeout
recovery / direct callers ran heuristics even with
`saudiMasterBots=true` — observed as M3lm and Saudi Master producing
byte-identical metrics in 100-round tests. The current single
delegation point repairs that.

---

## F4 [OK] — ISMCTS top-level invocation is recursion-safe

`BotMaster.lua:821-823`:

```lua
local prevRollout = B.Bot._inRollout
B.Bot._inRollout = true
local function _restore(v) B.Bot._inRollout = prevRollout; return v end
```

The `_inRollout` guard is **save/restored** (not just set/cleared),
so a hypothetical nested host call (e.g. AFK auto-play firing while
a rollout is in flight) would not flip the guard prematurely.

`Bot.lua:3381` reads the guard:

```lua
if not Bot._inRollout then
```

Recursion-prevention contract: any future refactor that routes
`heuristicPick`'s rollout play through `Bot.PickPlay` (instead of
the local closure) will be intercepted by this gate and fall through
to `legalPlaysFor` heuristics — which is the correct rollout policy.

Defensive `pcall` per-world (line 876) plus the
`rolloutErrors == numWorlds` fail-soft (line 889) and the per-world
granularity from v0.8.6 H4 (line 865) ensure that a single bad
world cannot leave `_inRollout = true` permanently. Good defensive
discipline.

---

## F5 [LOW] — World-count scaling is sane; no wall-clock budget

`BotMaster.lua:850-854`:

```lua
local numTricks = #(S.s.tricks or {})
local numWorlds
if numTricks <= 2 then numWorlds = 100
elseif numTricks <= 5 then numWorlds = 60
else numWorlds = BASE_NUM_WORLDS end
```

`BASE_NUM_WORLDS = 30` (line 36).

Comment block at lines 840-849 correctly identifies the prior
inversion (100 worlds at end-game, 30 at start) as a bug and inverts
the schedule. Trick-0 to trick-2: 100 worlds (high uncertainty);
trick-3 to trick-5: 60 worlds; trick-6+: 30 worlds.

**Concern (LOW):** there is no wall-clock budget. The header comment
estimates "~150 ms" total move time for 30 worlds × 8 candidates ×
25 plays. At trick 0 with 100 worlds × 8 candidates the upper bound
is closer to ~500ms × scenario complexity. WoW frames at 60 Hz =
16.7ms per frame. A 500ms `BM.PickPlay` call freezes the client for
~30 frames.

Potential mitigation (not requested by brief): `GetTime()` poll
inside the world loop to early-exit if we exceed e.g. 400 ms. But
the addon currently dispatches `MaybeRunBot` from `Net.lua` outside
the render path so the freeze may be tolerable. Flagging as
analytical only.

---

## F6 [LOW] — Determinism / random seed handling

`grep math.random` in `BotMaster.lua`:

- Line 191: shuffle (`math.random(1, i)`) inside `buildUnseen` /
  pool construction.
- Line 508: weighted sampler (`math.random() < pickProb`) inside
  `sampleConsistentDeal`.

There is **no `math.randomseed` call** anywhere in `BotMaster.lua`.
WoW's Lua state initializes the RNG with a default seed at addon
load — first-call behavior is therefore deterministic across
sessions until the first `math.random` consumes seed entropy.

**Implication:** identical game state → identical world samples.
This is fine for the rollout's correctness (each rollout is its
own evaluation), but means the per-game RNG sequence isn't
explicitly entropy-seeded. For reproducible bug reports this is
actually a **feature** — same input, same output. For perceived
non-deterministic bot behavior across sessions it's a **non-issue**
because game state diverges quickly via player input.

No action recommended; flagging because the brief asked.

---

## F7 [INFO] — Phantom `R.SunCanRolloff` reference

`Bot.lua:1601-1606` block comment:

```lua
-- v0.10.2 M4: pass live `s.akaCalled` to R.IsLegalPlay so the
-- AKA-receiver relief (J-066/J-067) is honored at the legality
-- layer. Without this, must-trump-ruff fires even when partner
-- has AKA'd, defeating AKA's primary purpose. Simulator callers
-- (R.SunCanRolloff line 409) deliberately omit the param so
-- rollouts get AKA-blind semantics.
```

`CHANGELOG.md:22`:

> Simulator callers (`R.SunCanRolloff`) deliberately omit the param
> so rollouts get AKA-blind semantics

`grep -r SunCanRolloff` across the repo: **0 function definitions**.
Only references are the comment, the CHANGELOG entry, and the
existing track-D findings that flag it.

The intended reference is presumably `BotMaster.lua:649`
(`heuristicPick` rollout) and/or `Rules.lua:435` (`R.IsValidSWA`
minimax). Both are simulator paths that omit `akaCalled`.

**Severity:** info / cosmetic. Does not affect any code path. But:
the CHANGELOG name-checks a non-existent function as the
justification for omitting the M4 param in rollouts — anyone trying
to verify the CHANGELOG claim by `grep` will fail.

Aligns with D-RT-18 §7 Doc-1 and B-Rules-01 F7.

---

## F8 [OK] — CLAUDE.md v0.5.0 fix honored

**Single delegation entry through `Bot.PickPlay`:** verified by F3.

**Recursion guard hygiene:** `BotMaster.lua:815-823` comment:

```lua
-- v0.5 C-1 recursion guard: Bot.PickPlay now delegates to us when
-- Saudi Master is active. heuristicPick is currently a local
-- closure and doesn't call Bot.PickPlay, but we set the flag
-- defensively so any future refactor that routes rollout play
-- selection through Bot.PickPlay won't recursively re-enter ISMCTS.
-- Save/restore (not just clear) in case nested host calls ever happen.
```

The defensive save/restore pattern is correct. The comment is
accurate: `heuristicPick` (lines 644-755) does NOT call
`Bot.PickPlay`; it's a self-contained closure. The guard is purely
defensive against future refactors — appropriate.

---

## F9 [OK] — Sun contract dispatch parity

`BM.PickPlay` does not branch on `contract.type` at the outer
dispatch level. Both HOKM and SUN contracts flow through:

1. Same legal-play list construction (line 826-832 — SAME bug F1
   applies to Sun, but AKA only fires for HOKM at `Rules.lua:117-118`
   `contract and contract.type == K.BID_HOKM`, so Sun is incidentally
   immune to the F1 bug).
2. Same world-count schedule.
3. Same rollout per-world loop.

Sun-specific behavior emerges only inside `heuristicPick` (e.g.
line 704: `if contract.type == K.BID_SUN then ... unbeatable check`
for second-hand-low ducking). That's appropriate — Sun-specific
heuristics belong in the rollout policy, not the outer dispatch.

**One latent observation:** because `Rules.lua:117-118` gates AKA-
relief to HOKM only, the F1 bug at `BotMaster.lua:830` happens to
be Sun-immune. But this is incidental: if a future Saudi-rules
update adds AKA-relief for Sun (no current basis in source-L), F1
would suddenly affect Sun too. Documenting for completeness.

---

## F10 [LOW] — Edge cases

### 10.1 — 1-card hand: correctly fast-pathed

`BotMaster.lua:825`: `if not hand or #hand == 0 then return _restore(nil) end`

`BotMaster.lua:834`: `if #legal == 1 then return _restore(legal[1]) end`

Two short-circuits. The `#legal == 1` case correctly bypasses the
sampler — saving ~150 ms when there's no decision to make. The
`_restore(nil)` on empty hand correctly resets `_inRollout`.

Note: if `#legal == 0` (e.g. all cards filtered illegal due to F1
when Saudi-Master sees a stripped legal set for an AKA-receiver),
the function returns `nil` and `Bot.PickPlay` falls through to the
M4-aware `legalPlaysFor` at line 3394. This is **accidental fail-
soft for F1**: in scenarios where all of a void-receiver's cards
are non-trump, the F1 bug produces empty `legal` (no trump to
satisfy must-ruff), `BM.PickPlay` returns nil, and the heuristic
path picks correctly via `legalPlaysFor`. But in the canonical F1
repro (seat 3 with `{7H, 8H, JD, QD}`), `legal = {JD, QD}` — non-
empty — so this fail-soft does NOT save the day.

### 10.2 — AKA-active: handled wrongly per F1

Already covered above. The repro in F1 IS the AKA-active edge
case.

### 10.3 — Paused state: not checked at entry

`BM.PickPlay` does not consult any `S.s.paused` / `K.PHASE_PAUSED`
flag. It checks:

- Line 813: `if not BM.IsActive() then return nil end`
- Line 814: `if not S.s.contract then return nil end`
- Line 824-825: hand non-empty
- Line 833: `legal` non-empty

`grep paused` in `BotMaster.lua` returns no matches. Search the
broader codebase:

```
> Grep "paused|isPaused|S\.s\.paused" Bot.lua
```

Not run as part of this audit (out of brief's strict scope), but
the absence of any phase/paused gate at `BM.PickPlay` entry means
that if the host is paused but `MaybeRunBot` somehow triggers
(e.g., via a delayed event), `BM.PickPlay` would still execute
~150ms of rollout work and return a card.

The upstream gate is in `Net.lua:MaybeRunBot` (which D-RT-18 didn't
re-audit but B-Net-09 covers). If the upstream gate is robust,
`BM.PickPlay`'s lack of a redundant check is fine. If a future
refactor moves dispatch logic, this becomes a defensive-gap.

**Severity LOW:** dependent on upstream `Net.lua` correctness.

---

## Cross-references

- **D-RT-18 (§2 S1):** the canonical write-up of F1; this audit
  confirms the repro and adds the dispatch-chain analysis (F3-F4)
  the brief asked for.
- **B-Rules-01 F7:** independently flagged the SunCanRolloff
  phantom reference (F7 here).
- **CLAUDE.md (Bot tier dispatch table):** the v0.5.0 single-
  delegation rule (F3, F8).
- **Brief's audit-scope items 1-10:** all addressed; mapping is
  F1=item-1, F2=item-2, F3=item-3, F4=item-4, F5=item-5, F6=item-6,
  F7=item-7, F8=item-8, F9=item-9, F10=item-10.

## Confidence

**HIGH confidence:**
- F1 / F2 mechanical bug + concrete fail repro (matches D-RT-18 S1).
- F3 single-delegation rule honored (verified by grep across all
  callers).
- F7 phantom reference (verified zero matches in `*.lua`).
- F8 recursion guard hygiene.
- F9 Sun is incidentally immune to F1 (verified at
  `Rules.lua:117-118` HOKM gate).
- F10.1 1-card fast-path.

**MEDIUM confidence:**
- F4 recursion safety — verified at the static-call level; not
  exhaustively tested with concurrent `MaybeRunBot` re-entries.
- F5 wall-clock concern — analytical, no instrumentation run.

**LOW confidence:**
- F6 RNG seeding — dependent on WoW's Lua-state default behavior
  which I haven't verified empirically for this addon.
- F10.3 paused-state — not cross-checked against `Net.lua`
  upstream gate; flagged as LOW pending that audit.
