# v3.2.0 Cleanup Batch 5C — Design / Inventory Pass

Status: design pass only. No runtime code changed. No tests changed.
Working tree limited to this doc.

Base: `main` at `08473ce` (Batch 5B + bel-quality shim fix).
Cleanup batches 1, 2, 3, 4A, 5A, 5B all merged. v3.1.14 remains the
last shipped CurseForge tag. No release tag for this cleanup work.

Goal: extract the 10 play-primitive helpers from `Bot.lua` into a
new `Bot/PlayPrimitives.lua` module — the deferred Option B from the
Batch 5B design pass.

The Batch 5B design doc covered most of the inventory work; this
doc focuses on the implementation-shape decisions that need to be
nailed down before code is touched.

---

## 1. Current state in Bot.lua (post-Batch 5B line numbers)

| Function | Line | Comment-header lines | Body lines |
|---|---|---|---|
| `pickRandomTied` | 2264 | 2258-2263 (6) | 2264-2267 (4) |
| `lowestByRank` | 2269 | — | 2269-2280 (12) |
| `highestByRank` | 2282 | — | 2282-2293 (12) |
| `highestByFaceValue` | 2301 | 2295-2300 (6) | 2301-2320 (20) |
| `holdsBeloteThusFar` | 2327 | 2322-2326 (5) | 2327-2341 (15) |
| `highestTrump` | 2343 | — | 2343-2352 (10) |
| `legalPlaysFor` | 2354 | — | 2354-2368 (15) |
| `wouldWin` | 2371 | 2370 (1) | 2371-2377 (7) |
| `tahreebClassify` | 2392 | 2379-2391 (13) | 2392-2551 (160) |
| `applyClosedTrumpLeadGate` | 2565 | 2553-2564 (12) | 2565-2590 (26) |

Total moved block: **lines 2254-2590 (~337 lines including the
"-- Play" section header and inter-function blank lines)**.

The "-- Play" section header at lines 2254-2256 (3 lines) covers the
entire region but the next thing after the primitives block is
`pickLead` (line 2592) which is also under "-- Play". The section
header should stay in Bot.lua so pickLead/pickFollow still live
visually under it. The primitives header content can move to
PlayPrimitives.lua's own file-level doc comment.

Heavy comment block to preserve verbatim: `tahreebClassify`'s
v1.1.1 / v0.9.0 / v3.0.2 / v3.0.3 / v3.0.6 audit-trail comments
(~155 lines of in-body comments). Codex's Batch 5A guardrail
("Preserve all comments attached to the moved theme data unless they
become actively misleading after the move") applies here.

Function reference counts inside Bot.lua (the 10 names combined):
**102 references**, including definitions. Excluding the 10
definition lines, that's ~92 call sites — virtually all inside
pickLead, pickFollow, PickAKA, PickPlay, PickMelds, PickDouble,
PickPreempt, PickOvercall, PickTakweesh, PickSWA, and the escalation
deciders.

---

## 2. Cross-module coupling (re-verified)

```
Bot.lua          92 call sites of the 10 functions (definitions
                 excluded). Every consumer is inside Bot.lua.
BotMaster.lua    0 direct calls. Reads B.Bot._memory and
                 B.Bot._partnerStyle but no play primitives.
Net.lua          0
State.lua        0
UI.lua           1 comment reference ("legalPlaysFor + BotMaster outer")
WHEREDNGN.lua    0
Slash.lua        0
```

Conclusion: zero real cross-module callers. The UI.lua mention is
inside a comment block discussing rules legality and is not a call.

---

## 3. Source-pin and test impact

### 3A. `tests/test_state_bot.lua` source pins (`botSrc:find(...)`)

The Batch 5B design doc verified that test_state_bot.lua has **zero**
`botSrc:find(...)` pins matching any of the 10 primitive names. All
references to `lowestByRank` / `highestByRank` / etc. are either
behavioral test bodies or in-comment explanations of what the bot
should do. None are literal-string source pins.

### 3B. `tests/test_H7_sun_shortest_lead.lua` — HARD source coupling

This test source-patches `Bot.lua` in memory and pins:

```lua
local ANCHOR_HELPER = "\nlocal function highestByRank"
```

at line 118. If `highestByRank` moves into Bot/PlayPrimitives.lua,
the anchor disappears from Bot.lua's source string and the assert at
line 134 fires:

```
H-7 test: cardsOfSuit anchor not found — Bot.lua structure has changed
```

**The H7 hunks need two pieces to keep working post-extraction:**

1. **Hunk 1 anchor update.** The anchor's job is to place
   `cardsOfSuit` at file-scope, before pickLead, in a position where
   it's visible to pickLead's body via Bot.lua's chunk closure. A
   stable replacement anchor is:

   ```lua
   local ANCHOR_HELPER = "\nlocal function pickLead"
   ```

   `pickLead` is the very next function definition after
   `applyClosedTrumpLeadGate` (currently line 2592), so injecting
   `cardsOfSuit` immediately before `pickLead` places it at the same
   file-scope position as before, just with the now-extracted
   primitives gone from between. pickLead is deferred indefinitely
   from extraction (Batch 5B design doc, Section 6) so this anchor is
   stable across foreseeable batches.

2. **`lowestByRank` resolution inside the patched Sun-branch.**
   Hunk 2 injects a Sun-lead branch INSIDE pickLead's body that
   calls `lowestByRank` and `cardsOfSuit` directly. With the
   primitives extracted, `lowestByRank` must still resolve as a
   file-local in Bot.lua. The re-binding header (see Section 4
   below) handles this — Bot.lua binds `local lowestByRank =
   Primitives.lowestByRank` at the top of the file, in the same
   chunk closure that pickLead and the patched code execute under.

The Hunk 2 anchor (`"\n    -- Defenders / bidder's partner / Sun
lead: don't burn high cards.\n"`) is inside pickLead's body and is
not affected by primitive extraction. It remains as-is.

### 3C. Behavioral coverage

All 10 primitives are exercised by the existing AA-AS sections in
test_state_bot.lua via the picker functions that call them
(pickLead, pickFollow, etc.). The Batch 5B design doc inventoried
this in detail: 40+ comment references in test bodies, specific
behavioral assertions for `highestByFaceValue` in
`test_v0.5_traced_game.lua` test D, `tahreebClassify` exercised
through `test_H1_pin_J9_trump.lua`. No new behavioral tests are
needed; the move is mechanical and the existing suite covers it.

### 3D. Test loader edits

Same 11 files as Batch 5B (each loads Bot.lua directly via
`load("Bot.lua")` or equivalent). Each needs one additional
`load("Bot/PlayPrimitives.lua")` line, placed between
`load("Bot/Tiers.lua")` and `load("Bot.lua")`:

```lua
load("State.lua")
load("Bot/Tiers.lua")
load("Bot/PlayPrimitives.lua")   -- NEW
load("Bot.lua")
```

The test_H7 special case (uses `loadFile` and patches Bot.lua
manually): add `loadFile("Bot/PlayPrimitives.lua")` after the
existing `loadFile("Bot/Tiers.lua")`, before the patched Bot.lua
chunk compiles.

### 3E. New source pins (mirrors AJ.9c / AJ.9d pattern)

Add an AJ.9e section in test_state_bot.lua asserting:
- `Bot/PlayPrimitives.lua` exists and defines each of the 10
  functions (or, more conservatively, exports each of the 10 keys on
  `B.Bot.Primitives`).
- `WHEREDNGN.toc` lists `Bot/PlayPrimitives.lua` AFTER `Bot/Tiers.lua`
  and BEFORE `Bot.lua`.

---

## 4. Implementation shape

### 4A. New file: `Bot/PlayPrimitives.lua`

UI/Themes.lua-style export pattern, scoped under `B.Bot.Primitives`:

```lua
-- WHEREDNGN Bot/PlayPrimitives.lua
--
-- Play-primitive helpers extracted from Bot.lua in v3.2.0 cleanup
-- batch 5C. ...

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
B.Bot = B.Bot or {}
local Bot = B.Bot
local K, C, R, S = B.K, B.Cards, B.Rules, B.State

local Primitives = Bot.Primitives or {}
Bot.Primitives = Primitives

-- ... moved functions, declared as local function X ...

Primitives.pickRandomTied         = pickRandomTied
Primitives.lowestByRank           = lowestByRank
Primitives.highestByRank          = highestByRank
Primitives.highestByFaceValue     = highestByFaceValue
Primitives.holdsBeloteThusFar     = holdsBeloteThusFar
Primitives.highestTrump           = highestTrump
Primitives.legalPlaysFor          = legalPlaysFor
Primitives.wouldWin               = wouldWin
Primitives.tahreebClassify        = tahreebClassify
Primitives.applyClosedTrumpLeadGate = applyClosedTrumpLeadGate
```

The functions stay `local function` inside the new file so they can
call each other (`lowestByRank` calls `pickRandomTied`, etc.) via
the file-local closure — no need for any function to call through
`Primitives.foo` since the locals are all in scope.

**`Bot.Primitives` namespace choice rationale:** mirrors `U.Theme`
from Batch 5A. Keeps the public B.Bot.* surface small — only the
table is publicly visible, not 10 new top-level names. If a future
batch ever needs cross-module access (BotMaster sampler eventually
calling `B.Bot.Primitives.legalPlaysFor` directly), the namespace
makes the import discoverable.

### 4B. Bot.lua changes

Replace the deleted lines 2258-2590 block with a small breadcrumb
comment (kept where the primitives were). At the **top of Bot.lua**,
just below the existing tier-extraction breadcrumb (currently lines
62-67 post-Batch-5B), add the re-binding header:

```lua
-- Play primitives (pickRandomTied / lowestByRank / highestByRank /
-- highestByFaceValue / holdsBeloteThusFar / highestTrump /
-- legalPlaysFor / wouldWin / tahreebClassify /
-- applyClosedTrumpLeadGate) live in Bot/PlayPrimitives.lua, which
-- the .toc loads before this file. Bind each as a file-local so
-- every existing call site below (pickLead / pickFollow / PickPlay /
-- PickAKA / escalation deciders / etc.) resolves unchanged.
local Primitives          = Bot.Primitives
local pickRandomTied      = Primitives.pickRandomTied
local lowestByRank        = Primitives.lowestByRank
local highestByRank       = Primitives.highestByRank
local highestByFaceValue  = Primitives.highestByFaceValue
local holdsBeloteThusFar  = Primitives.holdsBeloteThusFar
local highestTrump        = Primitives.highestTrump
local legalPlaysFor       = Primitives.legalPlaysFor
local wouldWin            = Primitives.wouldWin
local tahreebClassify     = Primitives.tahreebClassify
local applyClosedTrumpLeadGate = Primitives.applyClosedTrumpLeadGate
```

This is 14 lines (header + 11 locals). It must be placed early
enough that pickLead and friends close over the bound locals, but
late enough that `K`, `C`, `R`, `S` already exist (they do — the
`local K, C, R, S = B.K, B.Cards, B.Rules, B.State` line at Bot.lua
line 22 is the very first thing inside the chunk).

A natural placement: immediately after the existing tier breadcrumb
(line 67) and before the `jitter` helper (line 69 post-5B). That
keeps both breadcrumb + re-binding header co-located at the top, in
the same shape as Batch 5B's tier comment.

At the original primitives location (lines 2254-2590), keep the
`-- Play` section header (so pickLead/pickFollow still visually live
under it) and add a brief breadcrumb comment in place of the deleted
functions:

```lua
-- ---------------------------------------------------------------------
-- Play
-- ---------------------------------------------------------------------

-- Play-primitive helpers (pickRandomTied / lowestByRank / etc.)
-- moved to Bot/PlayPrimitives.lua in v3.2.0 cleanup batch 5C. Their
-- file-local re-bindings live near the top of this file.

local function pickLead(legal, contract, seat)
    ...
```

### 4C. WHEREDNGN.toc

```text
# Game runtime
State.lua
Bot/Tiers.lua
Bot/PlayPrimitives.lua    -- NEW
Bot.lua
BotMaster.lua
Net.lua
```

Loads after Tiers (Tiers has no dependency on Primitives, but the
explicit ordering keeps the Bot/*.lua submodules together
conceptually) and before Bot.lua.

### 4D. test_H7 anchor update

Single one-line change to `tests/test_H7_sun_shortest_lead.lua`:

```diff
- -- Anchor: the blank line immediately before `local function highestByRank`
- local ANCHOR_HELPER = "\nlocal function highestByRank"
+ -- Anchor: the blank line immediately before `local function pickLead`
+ -- (highestByRank moved to Bot/PlayPrimitives.lua in v3.2.0 batch 5C;
+ -- pickLead remains as the next stable file-local symbol).
+ local ANCHOR_HELPER = "\nlocal function pickLead"
```

The patched code's references to `lowestByRank` resolve via Bot.lua's
re-binding header. cardsOfSuit, now injected before pickLead, is in
the same file-local scope as the re-bound `lowestByRank`, so the
Sun-branch in pickLead's body sees both.

---

## 5. Risk + diff + review-complexity assessment

| Aspect | Verdict |
|---|---|
| Scope match to "smallest slice" | Yes — single extraction, mirrors 5A/5B shape |
| Source-pin damage | 1 update needed (test_H7 anchor) |
| Cross-module impact | 0 (zero external callers) |
| Bot.lua re-binding header needed | Yes (~14 lines, UI/Themes pattern) |
| Behavioral test coverage | Strong (40+ existing test references) |
| New behavioral tests required | None |
| Test loader edits | 11 mechanical one-liners |
| New source pins | ~13 lines (10 presence + 3 .toc-order) |
| Comment preservation surface | ~155 lines inside tahreebClassify must move verbatim |
| Diff size | ~370 added (new file + locals header + breadcrumb + tests) / ~333 deleted (Bot.lua primitives block) |
| Review complexity | MEDIUM — re-binding header alignment, tahreebClassify comment verbatim, test_H7 anchor swap, 11 loader edits |

**Risk class:** MEDIUM (vs Batch 5B's VERY LOW, vs Batch 5A's LOW).

Failure modes specific to this batch:
- **Re-binding header mis-order:** if any of the 11 locals is bound
  AFTER a function definition that calls it, the function captures a
  nil upvalue. Mitigated by placing all 11 bindings at the top of
  Bot.lua before any function definition that uses them — same shape
  as Batch 5A's UI.lua header.
- **tahreebClassify comment drift:** ~155 lines of in-body audit
  comments must move verbatim. Mitigated by file-level comparison
  during review (git diff old block vs new file).
- **test_H7 hunk-1 misalignment:** if the new anchor lands in a
  position where cardsOfSuit ends up at the wrong scope (e.g.
  inside a function body), the Sun-branch fails to resolve
  cardsOfSuit. Mitigated by anchoring on `\nlocal function pickLead`
  — the leading newline puts cardsOfSuit at file-scope right before
  pickLead's `local function` declaration.

---

## 6. Recommended Batch 5C implementation scope

**Extract all 10 play primitives in a single batch.** Reasons:

1. Tightly co-located (Bot.lua lines 2254-2590, contiguous block).
2. Inter-dependencies stay inside the new file (`lowestByRank` calls
   `pickRandomTied`, `highestByRank` calls `pickRandomTied`,
   `highestByFaceValue` calls `pickRandomTied`). Splitting would
   force one of them to use `Primitives.pickRandomTied` (less clean)
   or move pickRandomTied first as its own batch (more churn).
3. One re-binding header in Bot.lua covers all 10 — splitting would
   need multiple headers.
4. One test_H7 anchor update covers all of them.
5. Codex's Batch 5B prompt allowed splitting tier vs primitive but
   didn't suggest splitting primitives further. The 10 are
   homogeneous helpers.

**Defer to later batches:**

- `pickLead` / `pickFollow` extraction. Same deferral as Batch 5B.
- `Bot.PickBid` extraction. Same.
- Memory / style ledger move. Needs BotMaster API contract design.
- Escalation deciders (`PickDouble/Triple/Four/Gahwa`). Same.
- BotMaster sampler changes. Out of scope.

---

## 7. Summary

| Aspect | Value |
|---|---|
| Functions moved | 10 |
| Bot.lua lines deleted | ~333 (primitives block 2254-2590, minus retained header) |
| Bot.lua lines added | ~14 (locals header) + ~3 (breadcrumb at old location) |
| New file size | ~360 lines (Bot/PlayPrimitives.lua) |
| Cross-module callers affected | 0 |
| Source pins to update | 1 (test_H7 ANCHOR_HELPER) |
| New source pins | ~13 lines in AJ.9e |
| Test loader edits | 11 files × 1 line |
| Behavioral tests already covering the move | All AA-AS (test_state_bot.lua), test_v0.5_traced_game.lua D, test_H1_pin_J9_trump.lua |
| Behavioral tests needing addition | 0 |
| Risk class | MEDIUM |
| Review complexity | MEDIUM |

Awaiting Codex review of this design doc before implementation.
Stop after the design doc per the prompt's standard workflow.
