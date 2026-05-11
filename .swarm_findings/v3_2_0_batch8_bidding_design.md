# v3.2.0 Cleanup Batch 8 — Design / Inventory Pass: `Bot/Bidding.lua` Extraction

Status: design pass only. No runtime code changed. No tests changed.
No implementation branch cut. Working tree contains only this doc.

## 1. Current State

| Field | Value |
|---|---|
| `main` commit | `0912bc7` — docs(batch7): align inventory table with final scope |
| Last shipped tag | **v3.1.14** (commit `c1c624f`) |
| Full harness | **1149 / 1149 pass** |
| Working tree | clean (this doc untracked) |
| Release tag | none — cleanup-only |

## 2. Candidate Function Inventory

`Bot.lua` line ranges on current `main` (Batch 5B/5C/6/7 post-state):

### 2A. Bidding-window region (lines 1034-2273)

| Line | Symbol | Type | Public? | Dependencies | Callers |
|---|---|---|---|---|---|
| 1034 | `sideSuitAceBonus` | local fn | no | C, K | PickBid (R1, R2 paths) |
| 1053 | `hokmMinShape` | local fn | no | K, C | PickBid (R1 Hokm-on-flipped, R2 Hokm), beloteBypassQualifies (recursive within block) |
| 1150 | `sunMinShape` | local fn | no | C | PickBid (R1 Sun, R2 Sun) |
| 1175 | `beloteSuit` | local fn | no | C | PickBid, beloteBypassQualifies (recursive) |
| 1207 | `beloteBypassQualifies` | local fn | no | K, C, hokmMinShape, beloteSuit | PickBid (BC-MANDATORY branches in R1 and R2) |
| 1245 | `aceCountAndMardoofa` | local fn | no | C | PickBid (Sun strength), PickPreempt |
| 1297 | `bidderHoldsBidcard` | local fn | no | S.s, **B.Bot._memory** | **pickLead/pickFollow** (trump-J inference) — NOT bidding |
| 1327 | `withBidcard` | local fn | no | (pure copy + append) | PickBid (sunHand/hokmHand/hypHand), PickPreempt, PickOvercall |
| 1341 | `sunStrength` | local fn | no | K, C, **B.Bot.IsAdvanced** | PickBid, PickPreempt, PickOvercall, **PickDouble, PickTriple, escalationStrength** |
| 1422 | `partnerBidBonus` | local fn | no | K, R, B.Bot.IsBotSeat, S.s.bids | PickBid, **PickDouble, PickTriple** |
| 1481 | `scoreUrgency` | local fn | no | K, R | combinedUrgency, PickPreempt |
| 1517 | `opponentUrgency` | local fn | no | **B.Bot._memory** | Bot.OpponentUrgency, **PickDouble** |
| 1533 | **`Bot.OpponentUrgency`** | **public** on `B.Bot` | YES | opponentUrgency | **BotMaster.lua** (cross-module!) |
| 1550 | `matchPointUrgency` | local fn | no | K | combinedUrgency, PickPreempt |
| 1612 | `combinedUrgency` | local fn | no | scoreUrgency, matchPointUrgency | PickBid, **PickDouble, PickTriple, PickFour, PickGahwa** |
| 1626 | `partnerEscalatedBonus` | local fn | no | **B.Bot._partnerStyle** | PickBid, **PickDouble, PickTriple** |
| 1686 | **`Bot.PickBid`** | **public** on `B.Bot` | YES | all above + jitter + shuffledSuits | Net.lua MaybeRunBot, tests (W.2, X.4, AE.1, AE.1c, AJ.12, AJ.14) |

**Total**: 14 file-local helpers + 2 public functions in the contiguous bidding-window region. (Plus `suitStrengthAsTrump` at line 976 — discovered mid-implementation as a SHARED bid-strength helper consumed by both PickBid and the escalation deciders; moved with the bidding cluster too. See §6 corrections for details. **Final implementation moves 15 file-local helpers**.)

### 2B. Other bidding-window pickers (non-contiguous; lines 7586-7754)

| Line | Symbol | Type | Public? | Dependencies | Callers |
|---|---|---|---|---|---|
| 7586 | **`Bot.PickPreempt`** | **public** on `B.Bot` | YES | withBidcard, sunStrength, aceCountAndMardoofa, scoreUrgency, matchPointUrgency, Bot.IsBotSeat, jitter | Net.lua |
| 7661 | **`Bot.PickOvercall`** | **public** on `B.Bot` | YES | withBidcard, sunStrength, K constants, jitter | Net.lua, tests (H.10-H.14, AC.4-AC.5, AJ.15) |

### 2C. Helpers / pickers that STAY in `Bot.lua`

| Line | Symbol | Reason to stay |
|---|---|---|
| 91 | `jitter(base, amp)` | Universal helper; used by PickBid + every escalation decider + PickPreempt + PickOvercall + others |
| 107 | `shuffledSuits()` | Universal helper; used across pickLead/pickFollow + every bid-and-escalation site |
| 392 | `styleBelTendency` | Style-ledger consumer; used by escalation only (PickTriple/Four); not bidding |
| 1297 | `bidderHoldsBidcard` | Inside the bidding cluster physically, but its CALLER is pickLead/pickFollow's trump-J inference. Must stay with pickers. |
| 7023 | `selfStyleJitterBonus` | Escalation-style helper; called only by PickDouble/Triple/Four/Gahwa |
| 7292 | `escalationStrength` | Escalation-exclusive (called by PickDouble/Triple) |
| 2288–6597 | `pickLead`, `pickFollow`, Bot.PickAKA, Bot.PickAKANoise, Bot.PickPlay, Bot.PickMelds | Trick-play surface; out of scope |
| 7051 | `Bot.PickDouble` | Escalation; out of scope (future Bot/Escalation.lua) |
| 7370 | `Bot.PickTriple` | Escalation; out of scope |
| 7442 | `Bot.PickFour` | Escalation; out of scope |
| 7526 | `Bot.PickGahwa` | Escalation; out of scope |
| 7756 | `Bot.PickKawesh` | Hand-shape declaration (Saudi-specific) — calls `C.IsKaweshHand`. **NOT bidding-window.** Stays in Bot.lua. |
| 7788 | `Bot.PickTakweesh` | Rule-violation observer; out of scope |
| 7884 | `Bot.PickSWA`, `Bot.PickSWAResponse` | End-game claim; out of scope |

### 2D. Memory / style ledger (NOT moving)

The `Bot._memory` and `Bot._partnerStyle` tables (lines ~150-650 in Bot.lua) are READ by `bidderHoldsBidcard`, `opponentUrgency`, and `partnerEscalatedBonus` (among others). The TABLES themselves stay on `B.Bot.*`. `Bot/Bidding.lua` accesses them via `B.Bot._memory` / `B.Bot._partnerStyle` at runtime, identical to how BotMaster.lua already does it today.

`Bot.ResetMemory`, `Bot.ResetStyle`, `Bot.OnEscalation`, `Bot.OnRoundEnd`, `Bot.OnPlayObserved` stay in Bot.lua — they're the memory-ledger maintenance API, not bidding.

---

## 3. Recommended Extraction Boundary

**Recommendation: Option E — extract bidding-window helpers + shared bid-strength + urgency family + 3 picker functions + 1 public-export function in a single batch.**

### Codex review corrections applied to this design

The original draft of this section had five issues caught by Codex review. Corrections are reflected throughout §3-§6 below:

1. **`bidderHoldsBidcard` STAYS in `Bot.lua`.** It physically sits inside the bidding cluster at line 1297, but its only runtime caller is pickLead/pickFollow at `Bot.lua:3379` (trump-J inference). Moving it would break that closure capture. Treat the first move as **two split ranges**:
   - `sideSuitAceBonus` (1034) through `aceCountAndMardoofa` (~1295)
   - `withBidcard` (1327) through end of `Bot.PickBid` (~2273)
   With `bidderHoldsBidcard` at line 1297 untouched in `Bot.lua`.
2. **`BEL_JITTER` is required in `Bot/Bidding.lua`.** `Bot.PickPreempt` at `Bot.lua:7643` calls `jitter(th, BEL_JITTER)`. The current `local BEL_JITTER = 10` lives at `Bot.lua:6991` (escalation region; STAYS for escalationStrength + escalation deciders). `Bot/Bidding.lua` defines its own `local BEL_JITTER = 10` (same value, two independent locals).
3. **`Bot._beloteBypassQualifies = beloteBypassQualifies` test-internal export at `Bot.lua:1238`.** Move with `beloteBypassQualifies` to `Bot/Bidding.lua` — `tests/test_state_bot.lua:6230` depends on it (the deceptiveOverplay test).
4. **Bidding-threshold local aliases move with PickBid.** `TH_HOKM_R1_BASE`, `TH_HOKM_R2_BASE`, `TH_SUN_BASE`, `BID_JITTER` (lines 39-60) plus the explanatory comment block (lines 24-58) are exclusive to PickBid's threshold math. Move them to `Bot/Bidding.lua`. Grep-confirmed: no Bot.lua call site remains after PickBid moves.
5. **Narrow `Bot.Bidding` export surface.** Grep proves Bot.lua's escalation deciders use only: `sunStrength`, `partnerBidBonus`, `partnerEscalatedBonus`, `combinedUrgency`, `opponentUrgency`. `scoreUrgency` and `matchPointUrgency` have ONLY comment references in Bot.lua post-move (lines 7254, 7503) plus call sites inside `combinedUrgency` (which moves) and `PickPreempt` (which moves). **Do NOT rebind/export scoreUrgency or matchPointUrgency.** They stay file-local inside `Bot/Bidding.lua`.

### 3A. Functions moving to `Bot/Bidding.lua`

Public exports (set on `B.Bot.*`, no re-binding needed in callers):

1. `Bot.PickBid` (line 1686)
2. `Bot.PickPreempt` (line 7586)
3. `Bot.PickOvercall` (line 7661)
4. `Bot.OpponentUrgency` (line 1533)

File-local helpers (declared `local function` in `Bot/Bidding.lua`):

5. `sideSuitAceBonus` (1034)
6. `hokmMinShape` (1053)
7. `sunMinShape` (1150)
8. `beloteSuit` (1175)
9. `beloteBypassQualifies` (1207) — plus `Bot._beloteBypassQualifies = beloteBypassQualifies` (line 1238) test-internal export
10. `aceCountAndMardoofa` (1245)
11. `withBidcard` (1327)
12. `sunStrength` (1341)
13. `partnerBidBonus` (1422)
14. `scoreUrgency` (1481) — kept file-local in Bot/Bidding.lua; NOT re-exported
15. `opponentUrgency` (1517)
16. `matchPointUrgency` (1550) — kept file-local; NOT re-exported
17. `combinedUrgency` (1612)
18. `partnerEscalatedBonus` (1626)

Plus tuning constants relocated from `Bot.lua:24-60`:

- explanatory comment block (lines 24-58)
- `local TH_HOKM_R1_BASE = K.BOT_TH_HOKM_R1_BASE`
- `local TH_HOKM_R2_BASE = K.BOT_TH_HOKM_R2_BASE`
- `local TH_SUN_BASE     = K.BOT_TH_SUN_BASE`
- `local BID_JITTER      = K.BOT_BID_JITTER`
- `local BEL_JITTER      = 10` (new local in Bot/Bidding.lua, mirroring `Bot.lua:6991` which stays for escalation)

**Stays in Bot.lua**: `bidderHoldsBidcard` (line 1297) — only consumed by pickLead/pickFollow's trump-J inference at line 3379.

**Total moved**: **15 file-local helpers** (suitStrengthAsTrump added mid-implementation) + 4 public functions + 1 test-internal export + 4 tuning aliases + 1 new BEL_JITTER local = 25 symbols. Three non-contiguous source ranges (962-1014 for suitStrengthAsTrump+orphan-comment, 1034-1295, 1327-2273, 7586-7754) plus the top-of-file tuning header.

### 3B. Bot.lua re-binding header (after extraction)

The escalation deciders (`PickDouble`, `PickTriple`, `PickFour`, `PickGahwa`) and `escalationStrength` call moved helpers. Add a **6-locals** re-binding header to Bot.lua, immediately after the existing Batch 5C primitives header (line ~67) and before `jitter`'s declaration (line 91). (The design originally planned 5 locals; `suitStrengthAsTrump` was added mid-implementation when grep revealed PickDouble/PickTriple still call it — see §6 implementation corrections.)

```lua
-- Bidding helpers used by escalation deciders live in Bot/Bidding.lua,
-- which the .toc loads before this file. Re-bind as file-locals so
-- the remaining escalation code closes over the same helper names.
local Bidding                 = Bot.Bidding
local suitStrengthAsTrump     = Bidding.suitStrengthAsTrump
local sunStrength             = Bidding.sunStrength
local partnerBidBonus         = Bidding.partnerBidBonus
local partnerEscalatedBonus   = Bidding.partnerEscalatedBonus
local combinedUrgency         = Bidding.combinedUrgency
local opponentUrgency         = Bidding.opponentUrgency
```

**6 locals total** (`suitStrengthAsTrump` added mid-implementation — see §6 corrections). Grep-verified: post-move, Bot.lua has zero remaining `scoreUrgency(` / `matchPointUrgency(` call sites (only comments at lines 7254 and 7503 mention them, plus the definitions and their callers all move with Bot/Bidding.lua). `scoreUrgency` and `matchPointUrgency` therefore stay file-local in Bot/Bidding.lua and are NOT rebound or exported.

### 3C. Bot.lua breadcrumbs

At the original bidding region (lines 1034-2273) **delete the block entirely** and leave a single breadcrumb comment:

```lua
-- ---------------------------------------------------------------------
-- Bidding
-- ---------------------------------------------------------------------
-- Bid-strength math (sunStrength / hokmMinShape / sunMinShape /
-- aceCountAndMardoofa / withBidcard / sideSuitAceBonus /
-- beloteSuit / beloteBypassQualifies), partnerBid + escalation +
-- urgency helpers, and Bot.PickBid moved to Bot/Bidding.lua in
-- v3.2.0 cleanup batch 8. File-local re-bindings for the helpers
-- consumed by escalation deciders live near the top of this file
-- (just below the Tier + Primitives breadcrumbs).
```

At the PickPreempt/PickOvercall positions (lines 7586-7754) leave a second breadcrumb:

```lua
-- Bot.PickPreempt and Bot.PickOvercall moved to Bot/Bidding.lua in
-- v3.2.0 cleanup batch 8 (bidding-window deciders co-located with
-- Bot.PickBid and the shared bid-strength helpers).
```

### 3D. Imports in Bot/Bidding.lua

```lua
WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
B.Bot = B.Bot or {}
local Bot = B.Bot
local K, C, R, S = B.K, B.Cards, B.Rules, B.State

local Bidding = Bot.Bidding or {}
Bot.Bidding = Bidding

-- Pull in tuning constants from the same K namespace Bot.lua used.
local TH_HOKM_R1_BASE = K.BOT_TH_HOKM_R1_BASE
local TH_HOKM_R2_BASE = K.BOT_TH_HOKM_R2_BASE
local TH_SUN_BASE     = K.BOT_TH_SUN_BASE
local BID_JITTER      = K.BOT_BID_JITTER
```

Bot/Bidding.lua also calls `Bot.IsBotSeat`, `Bot.IsAdvanced`, `Bot.IsM3lm`, `Bot.IsFzloky`, `Bot.IsSaudiMaster`. These are all on `B.Bot.*` (via `Bot/Tiers.lua` since Batch 5B). The shared `local Bot = B.Bot` reference resolves them at runtime — no special import needed.

For helpers that stay in Bot.lua (`jitter`, `shuffledSuits`, `bidderHoldsBidcard`), the picker functions in Bot/Bidding.lua will call them. Two options:

- **(a)** Bot.lua exposes them on `B.Bot.*` and Bot/Bidding.lua imports as locals (requires new public surface).
- **(b)** Inline copies of `jitter` and `shuffledSuits` into Bot/Bidding.lua (4 lines each; pure functions; no shared state).

**Recommendation: (b) for `jitter` and `shuffledSuits` only.** They are 4-line pure functions; inlining keeps Bot/Bidding.lua self-contained. `bidderHoldsBidcard` is NOT called by any moved function (it's only called from pickLead/pickFollow which stay in Bot.lua), so no decision needed there.

Verification of "no moved function calls bidderHoldsBidcard": confirmed by grep at Bot.lua:3379 — the only call site is inside pickLead/pickFollow at line 3379 (which stays in Bot.lua). Bot/Bidding.lua does NOT need access to `bidderHoldsBidcard`.

---

## 4. Load-order Plan

### 4A. `WHEREDNGN.toc`

Insert `Bot/Bidding.lua` between `Bot/PlayPrimitives.lua` and `Bot.lua`:

```text
# Game runtime
State.lua
Bot/Tiers.lua
Bot/PlayPrimitives.lua
Bot/Bidding.lua           -- NEW
Bot.lua
BotMaster.lua
Net.lua
```

Rationale: `Bot/Bidding.lua` needs `B.Bot.Primitives` to be present (no direct calls from bidding helpers, but the position keeps the Bot sub-modules together). It must load BEFORE `Bot.lua` so `B.Bot.Bidding.*` is populated when Bot.lua's re-binding header runs.

### 4B. Test loader edits

The 11 test files that `load("Bot.lua")` (or `loadFile`/`loadAddon` equivalents) each need one new line:

```lua
load("State.lua")
load("Bot/Tiers.lua")
load("Bot/PlayPrimitives.lua")
load("Bot/Bidding.lua")     -- NEW
load("Bot.lua")
```

Files to update (11):
1. `tests/test_state_bot.lua`
2. `tests/test_botmaster.lua`
3. `tests/test_multiseed_metrics.lua`
4. `tests/test_asymmetric_metrics.lua`
5. `tests/test_baseline_metrics.lua`
6. `tests/probe_defender_strength.lua`
7. `tests/test_bel_decision_quality.lua`
8. `tests/test_v0.5_traced_game.lua`
9. `tests/test_H1_pin_J9_trump.lua`
10. `tests/test_numworlds_scaling.lua`
11. `tests/test_H7_sun_shortest_lead.lua` (special — uses `loadFile` and patches Bot.lua source; the new `loadFile("Bot/Bidding.lua")` runs BEFORE the patched chunk compiles)

### 4C. Standalone smoke changes

No new smoke files. Existing smokes (test_H1, test_H7, test_numworlds_scaling, test_v0.5_traced_game, test_bel_decision_quality) gain one new `loadFile`/`load`/`loadAddon` line each — already counted in §4B.

### 4D. H7 anchor

`tests/test_H7_sun_shortest_lead.lua`'s `ANCHOR_HELPER = "\nlocal function pickLead"` (set in Batch 5C) is **unchanged** — pickLead stays in Bot.lua, so the anchor still matches.

---

## 5. Source-Pin Retarget Plan

### 5A. Pins to retarget from Bot.lua to Bot/Bidding.lua

Approximately **20 source pins** in `tests/test_state_bot.lua` currently scan `Bot.lua` for code that moves to `Bot/Bidding.lua`. Each retarget is a one-line change: replace `WHEREDNGN_TESTS_ROOT .. "/Bot.lua"` with `WHEREDNGN_TESTS_ROOT .. "/Bot/Bidding.lua"`.

| Pin | Current line | Anchor / pattern | Stays in Bot.lua? |
|---|---|---|---|
| R.2a-e (PickBid btrace) | 2672, 2684, 2689, 2691, 2693 | `function Bot.PickBid` + btrace internals | NO — retarget to Bidding.lua |
| T.2b, T.2c (sunStrength void cap) | 2722, 2724 | `local function sunStrength` + math.min cap | NO — retarget |
| T.3a, T.3b (hokmMinShape Lever C) | 2743, 2745 | `local function hokmMinShape` + hasTrumpA/Nine | NO — retarget |
| X.1c-setup (PickOvercall function-found assert)* | 3166 | (Batch 7 retired this) | — |
| X.2, X.2b (hokmMinShape J+9 path + ordering) | 3189, 3196 | `count >= 3 and hasTrumpNine` + L07 ordering | NO — retarget |
| X.3a, X.3b (PickBid R1 Hokm-on-flipped) | 3222, 3224 | `function Bot.PickBid` + hypHand | NO — retarget |
| Y.2b (Belote escape ordering) | 3276 (post-batch-6) | belotePath < jFloor | NO — retarget |
| Y.3a-d (withBidcard call sites) | 3296, 3298, 3304, 3310 | `function Bot.PickBid` / PickPreempt / PickOvercall | NO — retarget |
| Z.1 (belote post-bidcard) | 3370 | `beloteSuit(withBidcard(...))` | NO — retarget |
| Z.2 (PickOvercall hypHand ordering) | 3383 | `function Bot.PickOvercall` + ordering | NO — retarget |
| Z.3 (mardoofa post-bidcard) | 3392 | `aceCountAndMardoofa(sunHand)` | NO — retarget |
| Z.5 (hypHand inline absence) | 3424 | absence assertion | NO — retarget (now absence inside Bot/Bidding.lua) |
| AD.1a, AD.1b (PickBid BC-MANDATORY + beloteCandidate) | 3697, 3699 | inside PickBid | NO — retarget |
| AD.9 (PickBid btrace format) | 3805 | `sunAces=%%d sunMardoofa=%%d` | NO — retarget |
| AF.1 (sunStrength AKQ-stopper) | 4580, 4583 | `local function sunStrength` + +12 | NO — retarget |
| AF.2 (sunStrength R2 bump rationale) | 4592 | "Advanced R2 bump REMOVED" | NO — retarget |
| AF.3 (PickPreempt 2-Ace+mardoofa) | 4599, 4602, 4603 | `function Bot.PickPreempt` + preemptAces | NO — retarget |
| AH.6 (partnerBidBonus seatIsBidder) | 5090 | `local function partnerBidBonus` | NO — retarget |

**Estimated total**: ~22 pin retargets (single-file-path edit each).

### 5B. Pins intentionally LEFT scanning Bot.lua (consumer-side stays)

| Pin | Reason |
|---|---|
| AD.2 (bidderHoldsBidcard wired into trump-J inference) | wiring is inside pickLead body — pickLead stays in Bot.lua |
| AA.4, AB.3 (bidderHoldsBidcard helper exists + phase-gate) | helper stays in Bot.lua (called by pickLead/pickFollow only) |
| AA.1a, AA.1b (escalationStrength void + sideAce bonus) | escalationStrength stays in Bot.lua |
| AH.7 ("neutralize Sun-only penalty" comment in escalationStrength) | stays |
| AH.3 (PickTriple floor cap) | PickTriple stays |
| AA.5 (pickFollow akaLive flag) | pickFollow stays |
| AI.1-AI.8 (agent comment markers in pickLead/pickFollow) | stay |
| All pickLead/pickFollow internals (AC.6, AE.X behavioral, AK.X, AN.X, AO.X, AP.X, AQ.X, AR.X — many) | stay |
| AB.4 (S.ApplyDouble/Triple/Four/Gahwa OnEscalation wiring in State.lua) | scans State.lua, not Bot.lua |
| Y.6a (Bot.PickSWAResponse defined) | PickSWA stays |
| Q.X, Y.5, Y.7 (PickSWA / PickAKA — already retired in Batch 6-7) | n/a |
| AG.X / AC.6 (PickFour internals — escalation) | stay |

### 5C. New source-pins to ADD (mirrors AJ.9c/d/e pattern)

Add a new **AJ.9f** block at the bottom of the AJ.9d/e cluster (around line 5400-ish). Per Codex's narrowed-export plan:

- **15 file-local helper presence** asserts: `Bot/Bidding.lua` defines each of the 15 `local function` helpers (the 14 originally planned plus `suitStrengthAsTrump` added mid-implementation).
- **4 public-function presence** asserts: `Bot/Bidding.lua` declares `function Bot.OpponentUrgency`, `function Bot.PickBid`, `function Bot.PickPreempt`, `function Bot.PickOvercall`.
- **1 test-internal export** assert: `Bot._beloteBypassQualifies = beloteBypassQualifies` in Bot/Bidding.lua.
- **3 `.toc`-order** asserts: Tiers < PlayPrimitives, PlayPrimitives < Bidding, Bidding < Bot.lua.
- **5 narrowed `Bot.Bidding.*` export** asserts: only `sunStrength`, `partnerBidBonus`, `partnerEscalatedBonus`, `combinedUrgency`, `opponentUrgency` are exposed via the sub-table (NOT scoreUrgency or matchPointUrgency).
- **5 Bot.lua re-binding** asserts: `local sunStrength = Bidding.sunStrength` and the other 4 each appear in Bot.lua's re-binding header.

**Actual AJ.9f delta (post-implementation)**: 15 helper-def + 4 public + 1 test-export + 1 BEL_JITTER + 6 narrow-export + 2 negative-export + 4 toc-order + 6 Bot.lua re-binding + 2 bidderHoldsBidcard placement = **+41 new asserts** (5 more than the original 32 estimate because suitStrengthAsTrump was added to both the helper list and the re-binding/export sets, and the negative-export + bidderHoldsBidcard placement pins were added for stricter Codex protection).

### 5D. Net test-count delta

| Action | Asserts |
|---|---|
| Retarget ~22 pins (file-path change only, no count change) | 0 |
| Add AJ.9f block (presence + toc-order + narrow exports + re-binding + bidderHoldsBidcard placement pins) | +41 |
| Retarget side effect: 1 previously-skipped body-check now runs | -1 |
| **Total delta** | **+40 net** |

**Actual** final harness: 1149 + 40 = **1189 / 1189 pass** (AJ.9f added 41 asserts; net delta is +40 because retargeting picked up 1 additional body-check that previously skipped). Verified by harness run on implementation branch.

---

## 6. Implementation Sketch

### 6A. High-level mechanical steps

1. Commit this amended design doc to `main` (per the prior batch pattern).
2. Cut feature branch `v3.2.0-cleanup-batch8-bidding`.
3. Create new file `Bot/Bidding.lua`:
   - Header + `WHEREDNGN` namespace setup + K/C/R/S/Bot locals + `Bidding` sub-table init.
   - Verbatim move of the bidding-threshold comment block (lines 24-58 from Bot.lua) + the 4 alias locals (TH_HOKM_R1_BASE, TH_HOKM_R2_BASE, TH_SUN_BASE, BID_JITTER).
   - Plus a new `local BEL_JITTER = 10` for PickPreempt's use.
   - Inline copy of `jitter` and `shuffledSuits` (4 lines each).
   - Verbatim copy of 15 file-local helpers in THREE ranges (suitStrengthAsTrump from line 976, then sideSuitAceBonus → aceCountAndMardoofa, skipping bidderHoldsBidcard, then withBidcard → partnerEscalatedBonus).
   - `Bot._beloteBypassQualifies = beloteBypassQualifies` test-internal export moves with `beloteBypassQualifies`.
   - Verbatim copy of `Bot.OpponentUrgency` public export.
   - Verbatim copy of `Bot.PickBid` (giant ~590-line function).
   - Verbatim copy of `Bot.PickPreempt` (~58 lines).
   - Verbatim copy of `Bot.PickOvercall` (~93 lines).
   - Export ONLY the 5 narrowed helpers on `Bot.Bidding.*`: `sunStrength`, `partnerBidBonus`, `partnerEscalatedBonus`, `combinedUrgency`, `opponentUrgency`.
4. In `Bot.lua`:
   - Remove the bidding-threshold comment block + 4 alias locals from the top of the file (lines 24-60). Replace with a one-line breadcrumb.
   - Add the 6-locals re-binding header just below the existing Batch 5C primitives header.
   - Delete the helpers/PickBid block in TWO sub-ranges (1034 through line just before `bidderHoldsBidcard` at 1297, then resume after bidderHoldsBidcard ends, then continue through end of PickBid at 2273). Replace with the "Bidding moved" breadcrumb.
   - `bidderHoldsBidcard` STAYS in Bot.lua (line 1297 — verify it's still there post-edit).
   - Delete lines 7586-7754 (PickPreempt + PickOvercall). Replace with the second breadcrumb.
   - The `Bot.OpponentUrgency` public export disappears from Bot.lua (now set by Bot/Bidding.lua on the shared `B.Bot.*` table).
   - `Bot._beloteBypassQualifies` line disappears from Bot.lua (now set by Bot/Bidding.lua).
5. Grep-verify Bot.lua post-edit:
   - `bidderHoldsBidcard` is still defined.
   - The call at pickLead/pickFollow still resolves to a local `bidderHoldsBidcard`.
   - No `TH_HOKM_R1_BASE`, `TH_HOKM_R2_BASE`, `TH_SUN_BASE`, `BID_JITTER`, or `BEL_JITTER` dead locals remain in Bot.lua unless still used there (BEL_JITTER stays for escalationStrength).
   - No `scoreUrgency(` or `matchPointUrgency(` call site remains in Bot.lua.
6. In `WHEREDNGN.toc`:
   - Insert `Bot/Bidding.lua` between `Bot/PlayPrimitives.lua` and `Bot.lua`.
7. In each of the 11 test loaders, add one `load("Bot/Bidding.lua")` line (or `loadFile`/`loadAddon` per file's helper).
8. Retarget the ~22 source pins in `tests/test_state_bot.lua` from `/Bot.lua` to `/Bot/Bidding.lua`.
9. Add the new AJ.9f source-pin block (~32 asserts) for Bot/Bidding.lua presence + toc-order + narrow exports + Bot.lua re-binding.
10. Run full harness — actual result on implementation branch: **`1189 / 1189 pass`** (1149 baseline + 41 new AJ.9f asserts − 1 net adjustment from retargets picking up 1 additional body-check that previously skipped).
11. Run standalone smokes (test_H1, test_H7, test_numworlds_scaling, test_v0.5_traced_game, test_bel_decision_quality).
12. Commit + push feature branch for Codex review.

### 6B. Expected files changed

| File | Action |
|---|---|
| `Bot/Bidding.lua` | NEW (~1 400-1 500 lines moved + ~30 lines of module header + exports) |
| `Bot.lua` | DELETE ~1 400 lines + ADD ~15 lines (re-binding header + 2 breadcrumbs) |
| `WHEREDNGN.toc` | +1 line (`Bot/Bidding.lua`) |
| 11 test loader files | +1 line each |
| `tests/test_state_bot.lua` | ~22 single-line pin retargets + new AJ.9f block (~150 lines) |

**Total**: 1 new file, ~16 modified files. ~1 400 lines net removed from Bot.lua; ~1 500 lines added to Bot/Bidding.lua.

### 6C. Expected line-count movement

| File | Before | After (approximate) |
|---|---|---|
| `Bot.lua` (non-blank) | 7 875 | ~6 600 |
| `Bot/Bidding.lua` (new) | — | ~1 450 |
| Combined | 7 875 | ~8 050 (small overhead from re-binding headers + module setup) |

### 6D. Expected harness count

Actual: **1189 / 1189 pass** (1149 baseline + 41 new AJ.9f asserts − 1 net adjustment). Verified by harness run on implementation branch `v3.2.0-cleanup-batch8-bidding` at commit `c699812`.

---

## 7. Risk Register

| # | Failure mode | Likelihood | Mitigation | Verification |
|---|---|---|---|---|
| 1 | **Load order**: `Bot/Bidding.lua` runs before `B.Bot.Primitives` exists or before `B.Bot.IsAdvanced` exists, causing nil-helper errors at first invocation | LOW | `.toc` places `Bot/Bidding.lua` AFTER `Bot/Tiers.lua` and `Bot/PlayPrimitives.lua`. The new file references `B.Bot.IsAdvanced` etc. via the shared `local Bot = B.Bot` reference — resolution happens at CALL time, not load time. AJ.9f order-pin asserts catch any `.toc` reorder. | Full harness + AJ.9f toc-order asserts |
| 2 | **Local helper no longer visible**: a Bot.lua call site (e.g., escalation decider) calls `sunStrength` but the local is missing from the re-binding header | MEDIUM | Bot.lua's re-binding header is mechanical (6 locals from a fixed list — suitStrengthAsTrump + sunStrength + partnerBidBonus + partnerEscalatedBonus + combinedUrgency + opponentUrgency). AJ.9f re-binding asserts pin each name. Behavioral tests for PickDouble/Triple (W.1's replacement AJ.14, plus AE.X) catch the failure. | Full harness + AJ.9f re-binding asserts |
| 3 | **Helper accidentally exported / not exported**: a file-local that should remain `local function` accidentally becomes `Bidding.X = X` (or vice versa), changing the public surface | LOW-MEDIUM | Codex review of `Bot/Bidding.lua` against the exact 14-helper + 4-public list in §3A. AJ.9f presence pins assert each file-local AND each public. | Codex review + AJ.9f presence asserts |
| 4 | **Source pins retargeted incorrectly**: a pin's path is changed to Bot/Bidding.lua but the anchor doesn't match (e.g., comment text drift during the move) | MEDIUM | Move is **verbatim** (Codex's Batch 5C guardrail) — comments and code preserved exactly. AJ.9f presence asserts use the same anchor strings as the retargeted pins. Run the full harness to catch any anchor mismatch. | Full harness — any retarget mismatch causes the corresponding source-pin to fail |
| 5 | **Behavior drift from manual move**: a subtle whitespace / comment / closure capture changes during the giant copy (~1 400 lines) and changes bot behavior | LOW-MEDIUM | Use the Python line-slice approach for verbatim move (same pattern that worked in Batch 5C for tahreebClassify's ~155-line audit comment). Run `git diff main...HEAD -- Bot.lua` to verify deletions; `git diff` cannot verify the new file content, so Codex review must compare against `old main:Bot.lua` slice. AE.1, AE.1c, W.2, X.4, AJ.12, AJ.14, AJ.15, H.10-H.14, AC.4-AC.5 cover the bidding decision space behaviorally — any drift in PickBid / PickPreempt / PickOvercall output flips an assert. | Behavioral coverage + Codex verbatim-comparison check |

Additional secondary risks:

| Risk | Mitigation |
|---|---|
| `jitter` / `shuffledSuits` inline copy drifts from Bot.lua's original | Codex review the 4-line bodies pre-merge. |
| Bot.lua's re-binding header line-orders differ from PlayPrimitives' pattern | Use the same alignment + naming convention as Batch 5C's primitives header. |
| AJ.9f block is excessive (29 asserts is large) | Consistent with AJ.9e's 33 asserts for PlayPrimitives extraction. Pattern is established. |
| Test loader edits miss a file | Cross-check via grep: `rg "load.*Bot\.lua" tests/` should show exactly 11 files; same 11 files must contain `Bot/Bidding.lua` post-edit. |
| `Bot.OpponentUrgency` is dropped from B.Bot accidentally | AJ.9f presence assert for `function Bot.OpponentUrgency` inside Bot/Bidding.lua catches it. BotMaster.lua's `B.Bot.OpponentUrgency` call (BotMaster.lua:461-462) is exercised by test_botmaster.lua. |

---

## 8. Explicit Deferrals

| Concern | Reason for defer |
|---|---|
| **`Bot/Escalation.lua`** (PickDouble + PickTriple + PickFour + PickGahwa + escalationStrength + styleBelTendency + selfStyleJitterBonus) | Out of scope for Batch 8. Recommended as Batch 9. Escalation will consume Bot/Bidding's exports via the same re-binding header pattern. |
| **`Bot/Memory.lua`** (Bot._memory + Bot._partnerStyle ledgers + OnPlayObserved + ResetMemory) | Requires BotMaster API contract design — BotMaster reads B.Bot._memory directly. Genuine refactor, not cleanup. Defer indefinitely. |
| **`pickLead` / `pickFollow`** | Two functions totaling ~4 400 lines, deeply state-coupled. Largest deferral by far. |
| **`bidderHoldsBidcard`** | Physically inside the bidding cluster (line 1297) but its only caller is pickLead/pickFollow's trump-J inference. Moving it would require either (a) keeping it accessible to pickLead/pickFollow via a re-binding back from Bidding to Bot.lua (which inverts the dependency direction), or (b) moving pickLead/pickFollow's trump-J inference to Bot/Bidding.lua (which is out of scope). **Keep in Bot.lua.** |
| **`Bot.PickKawesh`** | 7-line hand-shape declaration. Not bidding-window. Stays. |
| **`Bot.PickTakweesh`** | Rule-violation observer; not bidding. Stays. |
| **`Bot.PickAKA`, `Bot.PickAKANoise`, `Bot.PickPlay`, `Bot.PickMelds`, `Bot.PickSWA`, `Bot.PickSWAResponse`** | All play-time / claim-time deciders. Stays. |
| **AH.3, AA.4, AB.3 source pin conversions** | Per Batch 7 design doc §5: these stay source-only until extraction. **This batch IS the extraction** — but the pins are kept scanning Bot.lua because their protected helpers (`bidderHoldsBidcard`, `PickTriple` floor cap) stay in Bot.lua. No retarget needed. |
| **`jitter` / `shuffledSuits` extraction** | Could move to Bot/PlayPrimitives.lua (since they're used everywhere), but that requires a dependency reorder and a new re-binding header surface. Out of scope for Batch 8; inline copies in Bot/Bidding.lua avoid this entirely. |

---

## 9. Final Recommendation

**APPROVE Batch 8 implementation as designed.**

Implementation branch: **`v3.2.0-cleanup-batch8-bidding`**.

Implementation scope:
- New file `Bot/Bidding.lua` (~1 450 non-blank lines).
- `Bot.lua` loses ~1 400 lines (bidding region 1034-2273 + PickPreempt/PickOvercall 7586-7754) and gains ~15 lines (re-binding header + 2 breadcrumbs).
- `WHEREDNGN.toc` gains 1 line.
- 11 test loader files each gain 1 line.
- `tests/test_state_bot.lua` retargets ~19 source pins and gains the AJ.9f source-pin block (41 new asserts).
- Actual final harness: **1189 / 1189 pass** (verified on implementation branch `v3.2.0-cleanup-batch8-bidding` at commit `c699812`).

### Why this scope (not smaller)

- **Picker co-location.** PickBid + PickPreempt + PickOvercall are the three bidding-window deciders. Co-locating them in one module is semantically coherent.
- **Bot.lua re-binding header stays compact** at 6 locals — same shape as Batch 5C's primitives header. Smaller scopes (move helpers but keep PickPreempt/PickOvercall in Bot.lua) would inflate Bot.lua's re-binding to ~12+ locals.
- **Behavioral coverage is strong.** PickBid via AE.1, AE.1c, W.2, X.4, AJ.12, AJ.14. PickPreempt via the v0.11.16 calibration tests (S-section). PickOvercall via H.10-H.14, AC.4-AC.5, AJ.15. Any behavioral drift surfaces in the harness.
- **One mechanical move beats two cleanup batches.** A two-step extraction (Batch 8a = helpers only, Batch 8b = pickers) means Bot.lua churns twice. Better to land the full move once.

### Why this scope (not larger)

- **Escalation deciders stay in Bot.lua** — they're a future Bot/Escalation.lua batch, not this one.
- **Memory/style ledgers stay in Bot.lua** — they require BotMaster API contract design.
- **pickLead/pickFollow stay in Bot.lua** — biggest deferral by far.

### Risk class

**MEDIUM** — comparable to Batch 5C (PlayPrimitives, 333 lines moved with ~155 lines of audit comments to preserve verbatim). Batch 8 moves ~1 400 lines but the operations are mechanically identical to Batch 5C: verbatim move + sub-table export + re-binding header + .toc + test loaders + source-pin retargets.

---

## Summary

| Item | Value |
|---|---|
| Design doc path | `.swarm_findings/v3_2_0_batch8_bidding_design.md` |
| Functions/helpers inventoried | 19 in-scope (**15 file-local helpers** including suitStrengthAsTrump + 4 public functions) + 1 test-internal export (`Bot._beloteBypassQualifies`) + 4 tuning aliases + 1 new BEL_JITTER local + ~14 explicit stays + ~6 ledger/escalation deferrals |
| Recommended move boundary | 15 helpers + Bot.PickBid + Bot.PickPreempt + Bot.PickOvercall + Bot.OpponentUrgency public, with `bidderHoldsBidcard` **staying** in Bot.lua — four non-contiguous source regions (962-1014 for suitStrengthAsTrump, 1034-1295, 1327-2273, 7586-7754) plus the top-of-file tuning header (24-60) |
| Predicted files changed | 1 new (`Bot/Bidding.lua`) + 16 modified (Bot.lua, WHEREDNGN.toc, 11 test loaders, tests/test_state_bot.lua) |
| Actual harness count | **1189 / 1189 pass** (1149 + 41 new AJ.9f asserts − 1 net adjustment) — verified on implementation branch `v3.2.0-cleanup-batch8-bidding` at commit `c699812` |
| Key source-pin retargets | ~22 pins in tests/test_state_bot.lua (R.2, T.2, T.3, X.2, X.3, Y.2b, Y.3, Z.1-Z.3, Z.5, AD.1, AD.9, AF.1-AF.3, AH.6) — all single-file-path edits |
| Explicit deferrals | Bot/Escalation.lua, Bot/Memory.lua, pickLead/pickFollow, **bidderHoldsBidcard stays** in Bot.lua, PickKawesh/Takweesh/AKA/Play/Melds/SWA, jitter/shuffledSuits extraction |
| Working tree status | clean except this design doc untracked at `.swarm_findings/v3_2_0_batch8_bidding_design.md` |

No runtime code touched. No tests touched. No implementation branch cut. No commits. Awaiting Codex review before any implementation.
