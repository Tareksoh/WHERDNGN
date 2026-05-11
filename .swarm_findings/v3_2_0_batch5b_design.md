# v3.2.0 Cleanup Batch 5B — Design / Inventory Pass

Status: design pass only. No runtime code changed. No tests changed.
Working tree limited to this doc.

Base: `main` at `9ef3178` (Batch 5A — `UI/Themes.lua` extracted).
Cleanup batches 1, 2, 3, 4A, 5A merged. v3.1.14 remains the last
shipped CurseForge tag. No release tag for this cleanup work.

Goal: evaluate the safest next Bot-side decomposition slice after
`UI/Themes.lua`. Candidates per the prompt:

- `Bot/Tiers.lua` — 5 tier-detection functions
- `Bot/PlayPrimitives.lua` — 10 hand-shape helper functions

---

## 1. Candidate inventory

### 1A. Tier functions (`Bot.lua` lines 62-121, ~60 lines incl. comments)

| Function | Line | Signature | Public? | Dependencies |
|---|---|---|---|---|
| `Bot.IsAdvanced` | 70-77 | `()` → boolean | yes (set on `B.Bot`) | `WHEREDNGNDB` |
| `Bot.IsM3lm` | 82-87 | `()` → boolean | yes | `WHEREDNGNDB` |
| `Bot.IsFzloky` | 93-97 | `()` → boolean | yes | `WHEREDNGNDB` |
| `Bot.IsSaudiMaster` | 108-110 | `()` → boolean | yes | `WHEREDNGNDB` |
| `Bot.IsBotSeat` | 118-121 | `(seat)` → boolean | yes | `S.IsSeatBot` |

All five are declared as `function Bot.X()` — meaning they're set on
the shared `B.Bot` table at file-load time. **No file-locals in
Bot.lua close over them**: every call site uses the `Bot.X()` prefix.

Comments attached:
- Lines 62-69: header explaining the advanced-bots feature flag and
  the tier-extension contract ("All higher tiers strictly extend
  Advanced"). 8 lines.
- Lines 79-81: M3lm tier rationale. 3 lines.
- Lines 89-92: Fzloky tier rationale. 4 lines.
- Lines 99-107: 9-line audit-trail block explaining why
  `Bot.IsSaudiMaster` is intentionally retained with no current carve-
  out (Tier API symmetry).
- Lines 112-117: 6 lines explaining `Bot.IsBotSeat` as the audit
  Tier-3 proxy for `S.IsSeatBot`.

### 1B. Play-primitive helpers (`Bot.lua` lines 2312-2644, ~330 lines)

| Function | Line | Signature | Public? | Dependencies |
|---|---|---|---|---|
| `pickRandomTied` | 2318-2321 | `(tiedSet)` → card | `local` | `math.random` |
| `lowestByRank` | 2323-2334 | `(cards, contract)` → card | `local` | `C.TrickRank`, `pickRandomTied` |
| `highestByRank` | 2336-2347 | `(cards, contract)` → card | `local` | `C.TrickRank`, `pickRandomTied` |
| `highestByFaceValue` | 2355-2374 | `(cards, contract)` → card | `local` | `C.PointValue`, `C.TrickRank`, `pickRandomTied` |
| `holdsBeloteThusFar` | 2381-2395 | `(hand, contract)` → boolean | `local` | `C.Suit`, `C.Rank`, `K.BID_HOKM` |
| `highestTrump` | 2397-2406 | `(cards, contract)` → card | `local` | `C.IsTrump`, `C.TrickRank` |
| `legalPlaysFor` | 2408-2422 | `(hand, trick, contract, seat)` → cards | `local` | `R.IsLegalPlay`, `S.s.akaCalled` |
| `wouldWin` | 2425-2431 | `(card, trick, contract, seat)` → boolean | `local` | `R.CurrentTrickWinner` |
| `tahreebClassify` | 2446-2605 | `(signals)` → string\|nil | `local` | `K.RANK_PLAIN` |
| `applyClosedTrumpLeadGate` | 2619-2644 | `(legal, contract)` → cards | `local` | `K.BID_HOKM`, `C.IsTrump` |

All ten are `local function` in Bot.lua — **not** part of the public
`Bot.*` table. Every caller is an in-file closure over the local
binding. Moving them out requires Bot.lua to re-import each name as a
file-local (UI/Themes.lua pattern), so the existing call sites resolve
unchanged.

Heavy comment blocks attached:
- Lines 2310-2317: 8-line header for the tie-break randomization
  rationale (audit unpredictability HIGH-1).
- Lines 2349-2354 + 2376-2380: 5 + 4 lines of audit-trail comments
  for `highestByFaceValue` and `holdsBeloteThusFar`.
- Lines 2433-2445: 13-line header for `tahreebClassify` — return-
  value taxonomy + source-video references.
- Lines 2448-2475 + 2477-2521 + 2522-2604: ~150 lines of inline audit
  comments inside `tahreebClassify` covering v1.1.1 M2 forced-discard
  filtering, v0.9.0 Bargiya 2-flavor split, v3.0.2/v3.0.3 single-card
  fixes, v3.0.6 sender-intent gate. Mechanically heavy block.
- Lines 2607-2618: 12-line header for `applyClosedTrumpLeadGate`
  citing video #11 and the bot-only carve-out rationale.

### 1C. Coupling between the two blocks

Tier functions and play primitives are in completely separate Bot.lua
regions (62-121 vs 2312-2644). They do not call each other:
- Tiers only read `WHEREDNGNDB` and call `S.IsSeatBot`.
- Primitives only call `C.*`, `R.*`, `K.*`, `S.s.akaCalled`, and
  `pickRandomTied` (an internal local).

Bot.lua's `pickLead` (line 2646) is the first consumer of
`applyClosedTrumpLeadGate` — line 2649 directly inside the function
body. The lead/follow blocks below also call `lowestByRank`,
`highestByRank`, `highestByFaceValue`, `holdsBeloteThusFar`,
`highestTrump`, `legalPlaysFor`, `wouldWin`, `tahreebClassify`, and
`pickRandomTied` heavily. Moving primitives is a runtime change only
in the sense of file-locality — every existing call site continues to
resolve through the same identifier.

---

## 2. Cross-module coupling

### 2A. External callers of tier functions

```
Bot.lua          50+ call sites (Bot.IsAdvanced / IsM3lm / IsFzloky /
                 IsSaudiMaster / IsBotSeat — gates inside picker logic)
BotMaster.lua    0 direct calls — touches B.Bot._memory and
                 B.Bot._partnerStyle but no tier predicates
Net.lua          0
State.lua        0
UI.lua           1 comment only ("Bot.IsAdvanced / IsM3lm read them")
WHEREDNGN.lua    1 comment only
Slash.lua        0
```

**Verdict:** Tier functions are consumed ONLY inside Bot.lua. Zero
real cross-module callers. UI.lua and WHEREDNGN.lua mention them only
in explanatory comments next to the WHEREDNGNDB flag writes — not
calls.

### 2B. External callers of play primitives

```
Bot.lua          200+ call sites (pickLead, pickFollow, PickAKA,
                 PickPlay, PickMelds, PickDouble, escalation deciders,
                 PickPreempt, PickOvercall, PickKawesh, PickTakweesh,
                 PickSWA, PickSWAResponse — heuristic backbone)
BotMaster.lua    0 — uses its own internal helpers
Net.lua          0
State.lua        0
UI.lua           0
WHEREDNGN.lua    0
Slash.lua        0
```

**Verdict:** Play primitives are consumed ONLY inside Bot.lua. Zero
real cross-module callers. They are also all `local function` so
they're not even exported.

### 2C. BotMaster.lua coupling

BotMaster.lua reads:
- `B.Bot._memory` (sample-deal, partner-style hints)
- `B.Bot._partnerStyle` (M3lm style ledger)
- `B.Bot.OpponentUrgency` (advanced-tier urgency dispatcher)
- `B.Bot.PickPlay` (the ISMCTS delegation target)

None of these are tier functions or play primitives. Both Bot/Tiers
and Bot/PlayPrimitives extractions leave BotMaster.lua completely
untouched.

### 2D. `Bot._memory` / `Bot._partnerStyle` / `Bot._inRollout` impact

Neither extraction touches these. The memory/style ledgers are read
by the tier-gated branches (`if Bot.IsM3lm() and Bot._memory ...`)
but the read sites stay inside Bot.lua even if the predicates move
out. The ledger tables themselves are defined further down Bot.lua
(memory at line 159, partner-style around line 232 and again deeper)
— well outside both extraction zones.

---

## 3. Source-pin and test impact

### 3A. Existing source pins (read directly via `botSrc:find(...)`)

`tests/test_state_bot.lua` does 114 `botSrc:find(...)` calls.
Inspected with patterns matching the candidate names:

| Pattern category | Count touching candidates |
|---|---|
| `botSrc:find('function Bot%.Is*')` | **0** |
| `botSrc:find('local function pickRandomTied/lowestByRank/...')` | **0** |
| `botSrc:find('Bot.legalPlaysFor')` (text in comments only) | 1 (line 298 — comment) |

Conclusion: **`tests/test_state_bot.lua` does NOT pin any of the 15
candidate function names at the source level.** All references to
`Bot.IsAdvanced`, `Bot.IsBotSeat`, etc. inside test_state_bot.lua are
behavioral (real calls in test bodies, mostly setting up
`WHEREDNGNDB` flags) or comments — never literal source patterns.

### 3B. Source pin in `tests/test_H7_sun_shortest_lead.lua` (HARD COUPLING)

```lua
-- Anchor: the blank line immediately before `local function highestByRank`
local ANCHOR_HELPER = "\nlocal function highestByRank"
```

This test patches `Bot.lua` source in memory before loading it. It
pins the literal text `"\nlocal function highestByRank"` as an
anchor point. If `highestByRank` moves out of `Bot.lua` into a new
file, this anchor stops matching and the test fails the assert at
line 127.

Additionally, the patched code injected by this test calls
`lowestByRank` (5 times: lines 172, 180, 181, 189, 191) and that
identifier MUST be resolvable inside `pickLead`'s closure scope —
because the H7 hunk inserts code lexically inside `pickLead`.

**Implication for Option B / C:** Moving `highestByRank` requires:
1. Updating the H7 anchor to a new stable line still present in
   Bot.lua (e.g. `\nlocal function pickLead`).
2. Either keeping `lowestByRank` as a Bot.lua-scoped local re-bound
   from `B.Bot.Primitives` (UI/Themes.lua pattern), OR rewriting the
   H7 hunk to call `B.Bot.Primitives.lowestByRank` directly.
3. Option (2a) is mechanical — Bot.lua adds a 10-line `local
   lowestByRank = Primitives.lowestByRank` block near the top.

### 3C. Behavioral test coverage

**Tier functions:**
- Indirectly exercised by every M3lm-tier test (test_state_bot.lua
  sections AA, AB, AC, AD, AE, AF, AG, AH, AJ.6/.7, AK, AL all flip
  `WHEREDNGNDB.m3lmBots` to gate behavior).
- `test_baseline_metrics.lua` runs the full tier matrix via
  `setTier(name)` + `applyTierFlags(...)`.
- Behavioral coverage is overwhelming. No new tests needed to
  protect Tiers extraction.

**Play primitives:**
- All ten are heavily exercised by AA-AK in test_state_bot.lua —
  every "trick-X picks Y card" test that mentions `lowestByRank`,
  `highestByRank`, `highestByFaceValue` (40+ comment references)
  exercises the underlying primitive through the picker.
- `test_v0.5_traced_game.lua` test D has a specific behavioral
  assertion that `highestByFaceValue` correctly picks AD over TD on
  trick-8 pos-4.
- `test_H1_pin_J9_trump.lua` exercises `tahreebClassify` through
  signal-aware J-of-trump pinning.
- Behavioral coverage is excellent. No new tests needed; the move
  is mechanical and the existing behavioral suite would catch any
  regression.

### 3D. Test loader requirements

`Bot.lua` is loaded directly via `load("Bot.lua")` (or the equivalent
local helper) in 11 test files:

1. `tests/test_state_bot.lua` (state_bot harness)
2. `tests/test_botmaster.lua` (botmaster harness)
3. `tests/test_multiseed_metrics.lua`
4. `tests/test_asymmetric_metrics.lua`
5. `tests/test_baseline_metrics.lua`
6. `tests/probe_defender_strength.lua`
7. `tests/test_bel_decision_quality.lua`
8. `tests/test_v0.5_traced_game.lua`
9. `tests/test_H1_pin_J9_trump.lua`
10. `tests/test_numworlds_scaling.lua` (uses `loadAddon` helper)
11. `tests/test_H7_sun_shortest_lead.lua` (uses `loadFile` helper +
    source-patches before loading)

If a new `Bot/Tiers.lua` or `Bot/PlayPrimitives.lua` file is
introduced, every one of these test files must load the new file
BEFORE `Bot.lua` — otherwise Bot.lua's reads of `B.Bot.IsAdvanced`
(or `B.Bot.Primitives.lowestByRank`) at file-load time return nil
and the harness blows up.

This is 11 mechanical one-liner edits. None of them are runtime
behavior changes — they mirror the same `.toc` reorder we'd apply.

### 3E. New source pins recommended

Per the AJ.9c pattern from Batch 5A, on extraction we should add:

- A `.toc` order pin: assert `Bot/Tiers.lua` appears before `Bot.lua`
  in `WHEREDNGN.toc`.
- A presence pin: assert `Bot/Tiers.lua` contains the moved function
  definitions (mirror of AJ.9a/b scanning concatenated UI sources).

For PlayPrimitives the same pattern would apply, plus an explicit
`test_H7` anchor update.

---

## 4. Implementation design options

### Option A — Extract `Bot/Tiers.lua` only

**Scope:**
- Move 5 functions + ~30 lines of header/audit comments from
  Bot.lua:62-121 into `Bot/Tiers.lua`.
- Functions are already public on `B.Bot`, so the new file sets them
  on the shared table; Bot.lua callers (`Bot.IsAdvanced()`, etc.)
  resolve through the same `local Bot = B.Bot` reference unchanged.
- **No re-binding header needed in Bot.lua** — the symbols simply
  arrive on the table before Bot.lua's chunk runs.
- Add `Bot/Tiers.lua` to `WHEREDNGN.toc` between `State.lua` and
  `Bot.lua` (Tiers depends on `S.IsSeatBot`).
- Update 11 test files to `load("Bot/Tiers.lua")` after State.lua
  and before Bot.lua.
- Add `tests/test_state_bot.lua` source pins:
  - `.toc` order pin (Bot/Tiers.lua < Bot.lua)
  - Bot/Tiers.lua presence pin (contains the 5 function defs)

**Risk:** **VERY LOW**.
- Zero existing source pins on the moved names.
- Zero cross-module callers (BotMaster, Net, State, UI, Slash all
  uncoupled).
- Zero closure capture concerns (functions are already `function
  Bot.X` not `local function`).
- Tier functions are pure (WHEREDNGNDB flag reads + one S call).
- Strong behavioral coverage via every tier-gated test.

**Diff size:** small — one new file (~70 lines incl. comments + module
header), one Bot.lua deletion (~60 lines), one toc line, 11 mechanical
test-loader edits, 2 new source pins (~15 lines). Total ~150 lines
changed / 60 lines deleted.

**Review complexity:** **LOW**. The diff is mechanically grep-able:
"are the 5 functions identical? does Bot.lua just delete them? does
each test gain exactly one new load() line?".

### Option B — Extract `Bot/PlayPrimitives.lua` only

**Scope:**
- Move 10 functions + ~200 lines of header/audit comments from
  Bot.lua:2308-2644 into `Bot/PlayPrimitives.lua`.
- Functions are `local function` in Bot.lua — extraction requires:
  - Set them on `B.Bot.Primitives = {...}` in the new file
  - In Bot.lua, add a UI/Themes.lua-style 10-line `local lowestByRank
    = B.Bot.Primitives.lowestByRank` re-binding block at the top so
    existing local-scope call sites resolve unchanged.
- Add `Bot/PlayPrimitives.lua` to `WHEREDNGN.toc` between `State.lua`
  and `Bot.lua`.
- Update 11 test files to `load("Bot/PlayPrimitives.lua")`.
- **Update `tests/test_H7_sun_shortest_lead.lua` anchor** from
  `"\nlocal function highestByRank"` to a stable anchor that still
  exists in Bot.lua (e.g. `"\nlocal function pickLead"` — pickLead
  immediately follows applyClosedTrumpLeadGate in the same region).
- Add source pins mirroring Option A.

**Risk:** **MEDIUM**.
- One existing hard source pin (`test_H7` anchor) must be updated in
  the same diff.
- ~200 lines of audit comment inside `tahreebClassify` move with the
  function — must preserve verbatim (Codex's Batch 5A guardrail).
- Bot.lua gains a 10-line re-binding header (UI.lua pattern) — same
  shape as Batch 5A, no new risk type.
- 200+ closure-capture call sites inside Bot.lua resolve through the
  re-bound locals; trivially verified by grep ("are all old names
  still present as locals at the top?").

**Diff size:** medium — one new file (~360 lines), Bot.lua deletion
(~330 lines) + 10-line re-binding header gain, one toc line, 11 test
loader edits, 1 test_H7 anchor update, 2-3 new source pins.

**Review complexity:** **MEDIUM**. The re-binding block needs each
line audited against the moved function list, and the test_H7 anchor
update needs verifying the new anchor is stable.

### Option C — Extract both in one batch

Combine Option A + Option B in a single PR. Same risks individually
sum: tier functions are independent of play primitives so no
interaction effects.

**Diff size:** large — Bot.lua deletes 60 + 330 = 390 lines, gains a
~10-line re-binding header. Two new files. 11 test loader edits each
gain 2 new lines. Test_H7 anchor update. ~3 new source pins.

**Review complexity:** **MEDIUM-HIGH**. The combined diff is wider
than either part alone, and Codex's prompt explicitly prefers "the
smallest slice that proves Bot-side .toc extraction cleanly."

### Option D — Preparatory test/source-pin batch first

Land NO function moves yet. Just:
- Add a new test section `AR.*` with placeholder source-pins that
  expect functions to live in Bot.lua TODAY (matches current state).
- The pins become forward-compatible: when the move happens in a
  later batch, only the pin pattern (file path) needs updating.

**Risk:** **NEGLIGIBLE** but adds no concrete progress.

**Diff size:** tiny — only test additions.

**Review complexity:** **LOW**. But this is busywork compared to
Option A which is already very safe.

---

## 5. Recommended Batch 5B implementation scope

**Recommendation: Option A — extract `Bot/Tiers.lua` only.**

Reasons:
1. **Zero source-pin damage.** No existing test grep matches any of
   the 5 tier function names.
2. **Zero cross-module callers.** BotMaster/Net/State/UI/Slash all
   touch nothing tier-related.
3. **No re-binding header needed in Bot.lua.** Tier functions are
   already on the public `B.Bot.*` surface — they just disappear
   from Bot.lua's chunk and arrive on the shared table earlier in
   load order. Cleaner than Batch 5A's UI/Themes.lua move (which did
   need a re-binding block in UI.lua).
4. **Smallest slice that proves the Bot-side .toc extraction
   pattern.** Once this lands, future batches (PlayPrimitives,
   memory/style ledgers, escalation deciders) can rely on the
   established pattern: `Bot/<Name>.lua` between State.lua and Bot.lua
   in the .toc, mirrored in every test loader.
5. **Strong behavioral coverage.** Every tier-gated test exercises
   the predicates indirectly; no new tests are needed to protect the
   move.
6. **Test loader edits are mechanical.** 11 one-line additions, same
   shape across all 11 files.
7. **Diff size is small enough for comfortable Codex review.**

**Defer Option B (PlayPrimitives)** to Batch 5C or later. Reasons:
- Test_H7 anchor coupling adds an extra moving piece in the same diff
  (anchor update + .toc + 11 test loaders + Bot.lua re-binding + new
  source pins). Each step is mechanical, but their combination raises
  review surface.
- The 10-line re-binding header in Bot.lua mirrors Batch 5A but is
  larger (10 locals vs UI.lua's 11). Worth landing AFTER Option A
  proves the simpler pattern.
- 200 lines of audit comments inside `tahreebClassify` must move
  verbatim — preserving them under Codex review is straightforward but
  slower to verify than the tier extraction.

**Defer Option C (combined)** — explicitly contraindicated by the
prompt's "prefer the smallest slice."

**Skip Option D (prep batch)** — Option A is already very safe and
delivers concrete progress.

---

## 6. Explicit deferrals

Out of Batch 5B regardless of which option is chosen:

- **`pickLead` extraction** (Bot.lua:2646-4492, ~1850 lines). Deep
  rule-state branching with rollout-time coupling. Requires its own
  design pass.
- **`pickFollow` extraction** (Bot.lua:4570-6955, ~2390 lines). Same
  as pickLead.
- **`Bot.PickBid` extraction** (Bot.lua:1718-2317, ~600 lines).
  Internal urgency math entangled with hand-strength helpers above
  the candidate band.
- **Memory / style ledgers** (`Bot._memory`, `Bot._partnerStyle`,
  `Bot._inRollout`). Cross-module coupling with BotMaster (direct
  table reads) — needs new API contract design before extraction.
- **Escalation deciders** (`Bot.PickDouble/Triple/Four/Gahwa`,
  Bot.lua:7409-7942). Tightly coupled to round-state and the
  preempt window; defer to escalation-specific batch.
- **BotMaster sampler changes** (`sampleConsistentDeal`,
  `rolloutValue`). Out of scope; protocol/sampler redesign would be
  its own batch.

For Option A specifically:
- No PlayPrimitives move yet — defer to Batch 5C.
- No update to the `S.IsSeatBot` API even though `Bot.IsBotSeat` is a
  thin proxy. Keep both for tier-API symmetry per the existing
  audit-trail comment at Bot.lua:99-107.

---

## Summary

| Aspect | Verdict |
|---|---|
| Smallest safe slice | Option A — `Bot/Tiers.lua` only |
| Source-pin damage | 0 |
| Cross-module impact | 0 (Tiers only consumed in Bot.lua) |
| Bot.lua re-binding needed | No (tiers are already on `B.Bot.*`) |
| Behavioral test coverage | Strong (every tier-gated test) |
| Test loader edits | 11 mechanical one-liners |
| New source pins | 2 (toc order + Bot/Tiers presence) |
| Review complexity | Low |
| Diff size | ~150 lines added / ~60 lines deleted |

Awaiting Codex review of this design doc before implementation. Stop
after the design doc per the prompt's hard rule.
