# v3.2.0 Cleanup Batch 9 — Design / Inventory Pass: `Bot/Escalation.lua` Extraction

Status: design pass only. No runtime code changed. No tests changed.
No implementation branch cut. Working tree contains only this doc.

## 1. Current State

| Field | Value |
|---|---|
| `main` commit | `df4fd6c` — docs(batch8): fix remaining stale counts in design doc |
| Last shipped tag | **v3.1.14** (commit `c1c624f`) |
| Full harness | **1189 / 1189 pass** |
| Working tree | clean (this doc untracked) |
| Release tag | none — cleanup-only |

## 2. Function Inventory

`Bot.lua` line ranges on current `main` (post-Batch-8):

### 2A. Escalation cluster (contiguous, lines 5752-6346)

| Line | Symbol | Type | Dependencies | Callers |
|---|---|---|---|---|
| 5752-5757 | `BEL_JITTER = 10` | local const + 6-line comment header | none | `Bot.PickDouble` (line 6029) |
| 5758-5767 | `TRIPLE_JITTER`, `FOUR_JITTER`, `GAHWA_JITTER` | local consts + 7-line comment | none | `Bot.PickTriple` (6195), `Bot.PickFour` (6280-ish), `Bot.PickGahwa` (6333) |
| 5769-5811 | `selfStyleJitterBonus(seat, kind)` | local fn (~22 lines + 20-line comment) | `Bot.IsFzloky`, `Bot._partnerStyle`, `math.random` | PickDouble (6029), PickTriple (6195), PickFour (6279), PickGahwa (6335) |
| 5817-6047 | **`Bot.PickDouble(seat)`** | public on `B.Bot` (~231 lines) | `sunStrength` (Bidding), `partnerBidBonus` (Bidding), `partnerEscalatedBonus` (Bidding), `combinedUrgency` (Bidding), `opponentUrgency` (Bidding), `suitStrengthAsTrump` (Bidding), `jitter`, `BEL_JITTER`, `selfStyleJitterBonus`, `Bot.IsAdvanced`, `Bot.IsBotSeat`, `Bot._partnerStyle`, `S.s.contract`, `S.s.hostHands`, K/C/R constants | Net.lua MaybeRunBot (line 5734) |
| 6058-6134 | `escalationStrength(seat, hand, contract)` | local fn (~77 lines) | `sunStrength` (Bidding), `suitStrengthAsTrump` (Bidding), `partnerBidBonus` (Bidding), `partnerEscalatedBonus` (Bidding), `Bot.IsAdvanced`, `shuffledSuits`, K/C/R | PickTriple (6162), PickFour (6235), PickGahwa (6316) |
| 6136-6206 | **`Bot.PickTriple(seat)`** | public on `B.Bot` (~71 lines) | `escalationStrength`, `combinedUrgency`, `opponentUrgency` (Bidding), `styleBelTendency`, `jitter`, `TRIPLE_JITTER`, `selfStyleJitterBonus`, K | Net.lua (line 5824) |
| 6208-6290 | **`Bot.PickFour(seat)`** | public on `B.Bot` (~83 lines) | `escalationStrength`, `combinedUrgency` (Bidding), `jitter`, `FOUR_JITTER`, `selfStyleJitterBonus`, `Bot._partnerStyle`, K | Net.lua (line 5878) |
| 6292-6346 | **`Bot.PickGahwa(seat)`** | public on `B.Bot` (~55 lines) | `escalationStrength`, `combinedUrgency` (Bidding), `jitter`, `GAHWA_JITTER`, `selfStyleJitterBonus`, K, R | Net.lua (line 5931) |

**Total contiguous escalation region: 595 lines** (5752-6346).

### 2B. Non-contiguous escalation helper

| Line | Symbol | Type | Dependencies | Callers |
|---|---|---|---|---|
| 374-380 | `styleBelTendency(seat)` | local fn (~7 lines) | `Bot._partnerStyle` | **only PickTriple line 6176** |

`styleBelTendency` sits inside the style-ledger region (lines 332-389) immediately above `styleTrumpTempo` (lines 382-389). Its only call site is `Bot.PickTriple`. Adjacent function `styleTrumpTempo` is called from `pickLead`/`pickFollow` and stays in Bot.lua.

**Comment-handling caveat for this non-contiguous move (Codex review note):** the shared comment block at Bot.lua lines 367-376 ("Convenience derived metrics... Currently unused by the picker code; reserved for future M3lm-Plus heuristics...") is **stale and wrong** — both helpers ARE used by picker code (`styleBelTendency` by PickTriple, `styleTrumpTempo` by pickLead/pickFollow). When splitting the two helpers across files, do NOT carry the stale shared comment into Bot/Escalation.lua. Replace with:
- In **Bot/Escalation.lua** above `styleBelTendency`: a concise truthful comment naming PickTriple as its only caller.
- In **Bot.lua** above `styleTrumpTempo` (now alone): refresh the shared comment so it does not claim the metric is unused — name pickLead/pickFollow as the callers.

### 2C. Style-ledger code that STAYS in Bot.lua

| Line | Symbol | Reason to stay |
|---|---|---|
| 222 | `emptyStyle()` | Initializer for `Bot._partnerStyle`; called by `Bot.ResetStyle`, `Bot.OnEscalation`, `Bot.OnRoundEnd` |
| 331-341 | **`Bot.OnEscalation(seat, kind)`** | Style-ledger updater called from State.lua's `ApplyDouble`/`ApplyTriple`/`ApplyFour`/`ApplyGahwa` (AB.4 wiring). Public on `B.Bot.*`. Not a picker — updates `_partnerStyle[seat].bels/triples/fours/gahwas`. |
| 353-365 | **`Bot.OnRoundEnd(contract, bidderMade)`** | Style-ledger updater called from `S.ApplyRoundEnd`. Records `gahwaFailed` + `sunFail`. |
| 382-389 | `styleTrumpTempo(seat)` | Called from `pickLead`/`pickFollow` (lines 2061, 2090, 2295, 2296). **Not escalation.** |
| 951-960 | `anyOpponentVoidIn(seat, suit)` | Called from `pickLead` (line 2431). Play helper. |
| 984-1004 | `meldKnownHeld(seat)` | Called from `pickLead`/`pickFollow` (lines 2150, 4123, 4132). Play helper. |
| 1009-1029 | `bidderHoldsBidcard(seat, card)` | Called from `pickLead`/`pickFollow` (line 2165). Confirmed-stay since Batch 8. |

### 2D. Memory/style ledger tables — STAY on `B.Bot.*`

The `Bot._partnerStyle` and `Bot._memory` tables themselves live on `B.Bot.*` (Bot.lua lines 116/210). `Bot/Escalation.lua` reads them at runtime as `B.Bot._partnerStyle[seat]` — same pattern that BotMaster.lua and Bot/Bidding.lua already use. **No move; no new export surface.**

### 2E. Public exports affected

| Public symbol | Currently | Post-batch-9 |
|---|---|---|
| `Bot.PickDouble` | `function Bot.PickDouble` in Bot.lua | moves to Bot/Escalation.lua; still public on `B.Bot.*` |
| `Bot.PickTriple` | same | moves |
| `Bot.PickFour` | same | moves |
| `Bot.PickGahwa` | same | moves |
| `Bot.OnEscalation` | Bot.lua line 331 | **STAYS** |
| `Bot.OnRoundEnd` | Bot.lua line 353 | **STAYS** |

`Net.lua` calls `B.Bot.PickDouble` / `B.Bot.PickTriple` / `B.Bot.PickFour` / `B.Bot.PickGahwa` through the shared table — no Net.lua edits needed. Same pattern as Bot/Bidding.lua's `Bot.PickBid` / `Bot.PickPreempt` / `Bot.PickOvercall`.

### 2F. Cross-module dependency map

`Bot/Escalation.lua` will need:

| Source | Symbols imported | Mechanism |
|---|---|---|
| `Bot/Bidding.lua` (sub-table) | `sunStrength`, `partnerBidBonus`, `partnerEscalatedBonus`, `combinedUrgency`, `opponentUrgency`, `suitStrengthAsTrump` | `local x = Bot.Bidding.x` re-binding header (6 locals) |
| `Bot/Tiers.lua` (B.Bot.*) | `Bot.IsAdvanced`, `Bot.IsBotSeat`, `Bot.IsFzloky` | called via `local Bot = B.Bot` at runtime |
| `Bot.lua` | `Bot._partnerStyle` table | called via `B.Bot._partnerStyle` at runtime |
| `K` / `C` / `R` / `S` | constants + Cards + Rules + State.s | standard `local K, C, R, S = B.K, B.Cards, B.Rules, B.State` |
| inline copies | `jitter(base, amp)`, `shuffledSuits()` | 4-line pure functions (mirrors Bot/Bidding.lua pattern; avoids new public export) |

**Bot/Escalation.lua does NOT need** access to `bidderHoldsBidcard`, `meldKnownHeld`, `anyOpponentVoidIn`, `styleTrumpTempo`, or any pickLead/pickFollow helper — confirmed by grep over the escalation cluster.

---

## 3. Extraction Boundary Options

### Option A — Move only the 4 pickers (PickDouble/Triple/Four/Gahwa)

**Keep in Bot.lua**: `escalationStrength`, `selfStyleJitterBonus`, `styleBelTendency`, BEL_JITTER/TRIPLE_JITTER/FOUR_JITTER/GAHWA_JITTER constants.

**Bot/Escalation.lua needs**: re-imports for **7 escalation helpers** from Bot.lua (escalationStrength, selfStyleJitterBonus, styleBelTendency, 4 jitter consts) PLUS **6 Bidding helpers** PLUS inline `jitter` + `shuffledSuits` PLUS `Bot.*` tier predicates.

**Bot.lua needs**: expose those 7 escalation helpers on `B.Bot.Escalation.*` (new sub-table) OR on top-level `B.Bot.*` (new public surface). The latter pollutes the public API; the former requires Bot.lua to define a Bot.Escalation table BEFORE Bot/Escalation.lua loads — circular-ish since Bot/Escalation.lua loads BEFORE Bot.lua.

**Verdict: NOT recommended.** Creates a confusing dependency where Bot/Escalation.lua re-imports from Bot.lua even though Bot.lua loads later. Would require an awkward "initial stub" pattern.

**Risk class: MEDIUM-HIGH.** Lines moved: ~600. Public surface added: 7. Failure modes: load-order traps, naming collisions, weak abstraction (the file owns pickers but not their helpers).

### Option B — Move escalationStrength + 4 pickers

**Keep in Bot.lua**: `selfStyleJitterBonus`, `styleBelTendency`, 4 jitter constants.

**Bot/Escalation.lua needs**: re-imports for `selfStyleJitterBonus`, `styleBelTendency`, BEL_JITTER, TRIPLE_JITTER, FOUR_JITTER, GAHWA_JITTER (6 from Bot.lua) PLUS 6 Bidding helpers PLUS inline `jitter` + `shuffledSuits` PLUS `Bot.*` tier predicates.

**Bot.lua needs**: same problem as Option A — new sub-table or public surface for 6 helpers.

**Verdict: still problematic.** Smaller surface than A (6 vs 7) but same circular-load shape.

**Risk class: MEDIUM-HIGH.** Lines moved: ~675. Public surface added: 6.

### Option C — Move the full escalation cluster

**Move to Bot/Escalation.lua**:
- 4 jitter constants (BEL_JITTER, TRIPLE_JITTER, FOUR_JITTER, GAHWA_JITTER)
- `selfStyleJitterBonus`
- `styleBelTendency` (non-contiguous; from line 374)
- `escalationStrength`
- `Bot.PickDouble`, `Bot.PickTriple`, `Bot.PickFour`, `Bot.PickGahwa`

**Keep in Bot.lua**:
- `Bot.OnEscalation`, `Bot.OnRoundEnd`, `emptyStyle` (style-ledger maintenance, called from State.lua)
- `styleTrumpTempo` (play helper)
- `Bot._partnerStyle`, `Bot._memory` tables (on shared `B.Bot.*`)

**Bot/Escalation.lua needs**:
- 6 Bidding helpers re-imported via `local x = Bot.Bidding.x` (same pattern as Bot.lua's existing 6-locals re-binding — which Bot.lua **no longer needs** post-batch-9)
- `Bot.IsAdvanced`, `Bot.IsBotSeat`, `Bot.IsFzloky` via shared `local Bot = B.Bot`
- `Bot._partnerStyle` via `B.Bot._partnerStyle` at runtime
- Inline `jitter` + `shuffledSuits` (4-line pure functions)

**Bot.lua needs**: nothing — the existing 6-locals re-binding header (added in Batch 8 to feed escalation deciders) becomes **unused** and can be deleted entirely. Net: Bot.lua **loses** ~700 lines AND ~12 lines of re-binding header (no replacement needed).

**Verdict: RECOMMENDED.** All escalation code lives in one file. Bot.lua's re-binding surface SHRINKS (Bidding re-binding goes away). No new public sub-table, no circular load.

**Risk class: MEDIUM.** Lines moved: ~700 (595 contiguous + ~12 styleBelTendency at line 374 with its comment header). Source-pin retargets: 8.

### Recommendation: **Option C**

Same pattern as Batch 5B/5C/8 — co-locate the entire concern. Each picker is already public on `B.Bot.*` (set via `function Bot.X(...)` in the new module), so Net.lua's call sites resolve through the shared table unchanged.

---

## 4. Load-order Plan

### 4A. `WHEREDNGN.toc`

Insert `Bot/Escalation.lua` between `Bot/Bidding.lua` and `Bot.lua`:

```text
# Game runtime
State.lua
Bot/Tiers.lua
Bot/PlayPrimitives.lua
Bot/Bidding.lua
Bot/Escalation.lua        -- NEW
Bot.lua
BotMaster.lua
Net.lua
```

Rationale:
- Bot/Escalation.lua imports from `Bot.Bidding.*` → must load AFTER `Bot/Bidding.lua`.
- Bot/Escalation.lua sets `Bot.PickDouble`, etc. on `B.Bot.*` → must load BEFORE `Bot.lua` (so the breadcrumb in Bot.lua sees the moved code is already on the table; though strictly the picker assignments could happen in either order since Net.lua reads them at call time).
- Bot.lua's `_partnerStyle` and `_memory` table inits happen at Bot.lua load time, AFTER Bot/Escalation.lua. **This is safe**: escalation pickers only access these tables at RUNTIME (inside the picker function bodies), not at load time. Same pattern as BotMaster.lua's runtime reads of `B.Bot._memory`.

### 4B. Test loader edits

The 11 test files that `load("Bot.lua")` each need one new line:

```lua
load("Bot/Tiers.lua")
load("Bot/PlayPrimitives.lua")
load("Bot/Bidding.lua")
load("Bot/Escalation.lua")    -- NEW
load("Bot.lua")
```

Files (same 11 as Batches 5B, 5C, 8):
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
11. `tests/test_H7_sun_shortest_lead.lua` (special — patches Bot.lua source; new `loadFile("Bot/Escalation.lua")` runs BEFORE the patched chunk compiles)

### 4C. H7 anchor

`tests/test_H7_sun_shortest_lead.lua`'s `ANCHOR_HELPER = "\nlocal function pickLead"` (set in Batch 5C) is **unchanged** — pickLead stays in Bot.lua.

### 4D. Bot.lua re-binding header removal

The current 6-locals Bidding re-binding header at the top of Bot.lua (added in Batch 8, lines ~60-70):

```lua
local Bidding                 = Bot.Bidding
local suitStrengthAsTrump     = Bidding.suitStrengthAsTrump
local sunStrength             = Bidding.sunStrength
local partnerBidBonus         = Bidding.partnerBidBonus
local partnerEscalatedBonus   = Bidding.partnerEscalatedBonus
local combinedUrgency         = Bidding.combinedUrgency
local opponentUrgency         = Bidding.opponentUrgency
```

becomes **unused** post-Batch-9 because all consumers (escalation deciders) move to Bot/Escalation.lua. **Delete the header entirely** (and the breadcrumb comment) and replace with a 2-line "moved to Bot/Escalation.lua" note.

---

## 5. Source-Pin Impact

### 5A. Pins to retarget from Bot.lua to Bot/Escalation.lua

| Pin | Line | Pattern | Why retarget |
|---|---|---|---|
| **AA.1a / AA.1b** | 3401-3410 | `local function escalationStrength` + body (`voidCount * 5`, `sideAces - 1`) | escalationStrength moves |
| **AB.2** | 3473 | `function Bot.PickGahwa` body for `DEAD-2` rationale | PickGahwa moves |
| **AD.3** | 3694 | `function Bot.PickGahwa` (duplicate DEAD-2) | PickGahwa moves |
| **AD.7a / AD.7b** | 3739-3745 | `function Bot.PickDouble` body for `local function eltrace` + `"PickDouble eval: strength="` | PickDouble moves |
| **AH.3** | 5039 | `function Bot.PickTriple` body for floor cap `th < K.BOT_TRIPLE_TH - 16` | PickTriple moves |
| **AH.7** | 5078 | `local function escalationStrength` body for `"neutralize Sun-only penalty"` | escalationStrength moves |
| **AI.4** | 5120 | `v1.0.4 (agent #4): bid-history inflection` comment marker inside PickDouble | PickDouble moves |

**Estimated retargets: 8 pin assertions in 7 do-blocks** (single file-path edit each: `/Bot.lua` → `/Bot/Escalation.lua`).

### 5B. Pins that stay scanning Bot.lua

| Pin | Reason |
|---|---|
| AB.4a-e | scans State.lua + Net.lua (not Bot.lua) for `B.Bot.OnEscalation` wiring |
| AE.3 | behavioral PickPlay smoke for bidderHoldsBidcard (stays in Bot.lua) |
| AE.4 | behavioral OnEscalation via S.ApplyDouble/Triple/Four/Gahwa (OnEscalation stays) |
| AI.2 | smother gate in pickFollow (stays) |
| AI.5 | Bargiya phase-split in pickLead (stays) |
| AC.6 | PickFour +5 bonus — **already behavioral** (Batch 3 conversion); calls `Bot.PickFour(2)` via public API, doesn't pin source. Stays unchanged. |
| AD.2 | `bidderHoldsBidcard` wiring in pickLead/pickFollow body |
| AG.1 | meldKnownHeld helper pin (stays in Bot.lua) |
| AG.5-AG.7 | pickLead/pickFollow body internals |
| AJ.13 | behavioral Sun-no-rungs invariant — calls all 4 pickers via public API; doesn't pin source. Stays. |
| AK.7 | behavioral PickTriple floor cap — calls `Bot.PickTriple(2)`; doesn't pin source. Stays. |
| AH.6 | scans Bot/Bidding.lua (post-Batch-8) for partnerBidBonus seatIsBidder. Stays. |

### 5C. Pins that should stay source-only (no behavioral conversion needed)

| Pin | Reason |
|---|---|
| AA.1a (voidCount), AA.1b (sideAces) | Internal bonus math; behavioral conversion would need PickDouble/Triple fixtures isolating the void-vs-non-void delta. MEDIUM complexity. Defer to a future Batch 10 prep batch if needed. |
| AB.2 / AD.3 (DEAD-2 comment) | Rationale comment; comment-only pin, no behavioral equivalent. |
| AD.7a / AD.7b (eltrace) | Debug-mode wiring; no behavioral test. |
| AH.3 (PickTriple floor cap) | Behavioral AK.7 already covers the floor cap path; AH.3 is the structural pin. Codex's Batch 7 decision was "keep AH.3 source-only until a stronger behavioral fixture lands." That decision still holds — retarget but don't retire. |
| AH.7 (sunStrength Sun neutralization) | Rationale comment about void-penalty inversion. |
| AI.4 (agent #4 bid-history inflection) | Comment marker for discoverability. |

### 5D. New AJ.9g source-pin block

Mirroring the AJ.9c/d/e/f pattern. Asserts:

- 1 file-local helper presence: `local function selfStyleJitterBonus`
- 1 file-local helper presence: `local function styleBelTendency`
- 1 file-local helper presence: `local function escalationStrength`
- 4 public functions: `function Bot.PickDouble/PickTriple/PickFour/PickGahwa`
- 4 jitter consts: `local BEL_JITTER = 10`, `local TRIPLE_JITTER = 12`, `local FOUR_JITTER = 15`, `local GAHWA_JITTER = 18`
- 4 .toc-order asserts: Tiers < PlayPrimitives, PlayPrimitives < Bidding, Bidding < Escalation, Escalation < Bot.lua
- 2 negative-export asserts: Bot/Escalation.lua does NOT introduce a new `B.Bot.Escalation` sub-table OR a re-binding header on Bot.lua's side (because none is needed)
- 1 assert: Bot.lua's old Bidding re-binding header is REMOVED (since escalation no longer needs it)

**Actual AJ.9g delta (post-implementation)**: 3 helper-def + 4 picker-pub + 4 jitter-const + 6 Bidding-import + 5 toc-order + 2 negative-subtable + 5 Bot.lua state (no-rebind, styleTrumpTempo + OnEscalation + OnRoundEnd stay, no-bidding-header) + 3 escalation-helper-moved + 4 picker-moved + 1 styleTrumpTempo-not-in-esc = **45 new AJ.9g asserts**. Plus the retirement of the 6 AJ.9f-bind asserts (the Batch 8 Bidding re-binding header is now gone from Bot.lua) — net **+30 asserts** to the harness.

### 5E. Net test-count delta

| Action | Asserts |
|---|---|
| Retarget 8 pins (file-path change, no count change) | 0 |
| Add AJ.9g block (final implementation surface) | +45 |
| Retire 6 AJ.9f-bind asserts (Bot.lua's Batch 8 Bidding header removed) | -6 |
| Retarget side effects (no count change, file-path only) | -9 (body asserts inside if-fnStart that previously skipped now run on new file — net) |
| **Total delta** | **+30** |

Actual final harness: 1189 + 30 = **1219 / 1219 pass**. Verified on implementation branch `v3.2.0-cleanup-batch9-escalation` at commit `fd31215`.

---

## 6. Behavioral Coverage

### 6A. Existing behavioral tests covering escalation pickers

| Test | What it asserts | Survives extraction? |
|---|---|---|
| **AC.6** (line 3614) | `Bot.PickFour(2)` fires on jitter-frozen +5-bonus fixture (strength=80, jth=80) | YES (calls public API) |
| **AE.4** (line 3994) | `S.ApplyDouble/Triple/Four/Gahwa` increment `Bot._partnerStyle.bels/triples/fours/gahwas` via `Bot.OnEscalation` | YES (OnEscalation stays) |
| **AJ.13** (line 5620) | All 4 escalation deciders return `false` under a Sun contract (Sun-no-rungs invariant) | YES (calls public API) |
| **AK.7** (line 6162) | `Bot.PickTriple(2)` returns `false` on a deliberately weak Hokm bidder hand under threshold-drop pressure (FLOOR-3 behavioral) | YES (calls public API, jitter-frozen) |

These cover Bel/Triple/Four/Gahwa positive-fire and negative-fire paths via public-API calls. Cross-file moves don't break any of them.

### 6B. Behavioral gaps to consider (optional, NOT blockers for Batch 9)

| Gap | Risk | Recommendation |
|---|---|---|
| **AH.3 floor cap structural pin** (PickTriple) — AK.7 behavioral exists but is a "general weak hand fails" test, not a tight load-bearing check on the floor cap | LOW-MEDIUM | Codex's Batch 7 verdict: keep AH.3 source-only. Retarget AH.3 to Bot/Escalation.lua mechanically in Batch 9; do NOT attempt behavioral conversion in the same batch. |
| **AA.1a/b void/sideAce bonuses in escalationStrength** — structural pins on `voidCount * 5` and `sideAces - 1` | LOW | Pre-existing structural pins. Retarget mechanically. Behavioral conversion would need PickDouble + PickTriple fixtures isolating void-vs-non-void deltas (calibratable, but out of scope for Batch 9). |
| **Bot.PickDouble bid-history inflection** (AI.4) — protects the partner-preempt/overcall path that biases `th` | LOW | Comment-marker pin; retarget to Bot/Escalation.lua. |
| **No behavioral test for `selfStyleJitterBonus`** | LOW | Helper is purely internal. Indirectly covered by AC.6 / AK.7 / AJ.13 since those drive the picker fire/no-fire decision through the same jitter math. |
| **No behavioral test for `styleBelTendency`** | LOW | Helper has 1 caller (PickTriple). Indirectly covered by AK.7 (PickTriple no-fire under threshold pressure). |

**Verdict**: behavioral coverage is sufficient for Batch 9. No new tests required before extraction. AJ.9g asserts the structural shape; the existing AC.6/AE.4/AJ.13/AK.7 cover behavior.

### 6C. Jitter-sensitive tests (require `math.random` shim)

| Test | Shim shape | Survives move? |
|---|---|---|
| AC.6 | `math.random` override returns 0 for unspecified `(a, b)` | YES (calls Bot.PickFour public API; helpers use the same shim path) |
| AK.7 | Jitter-frozen fixture with weak hand below jth_min | YES (same as AC.6) |
| AJ.13 | No jitter sensitivity (Sun early-return BEFORE jitter sampled) | YES |
| AE.4 | No jitter (state-table update test) | YES |

All existing jitter-sensitive escalation tests survive cross-file moves because they call public-API functions through `B.Bot.*`.

---

## 7. Risk Register

| # | Failure mode | Likelihood | Mitigation | Verification |
|---|---|---|---|---|
| 1 | **`Bot._partnerStyle` not initialized** when escalation picker fires (load-order: Bot/Escalation.lua sees `Bot._partnerStyle = nil` from Bot.lua's `Bot._partnerStyle = nil` initializer that runs LATER) | LOW | Escalation pickers already nil-guard the table read: `if not Bot._partnerStyle then return 0 end` in selfStyleJitterBonus; `if not Bot._partnerStyle then Bot._partnerStyle = emptyStyle() end` in OnEscalation/OnRoundEnd. Reads happen at call time, not load time. | Full harness + AE.4 + behavioral PickDouble/Triple/Four/Gahwa tests |
| 2 | **`Bot.Bidding` sub-table not present** when Bot/Escalation.lua's re-binding header runs (load-order: .toc places Bidding before Escalation) | LOW | .toc explicitly orders `Bot/Bidding.lua` BEFORE `Bot/Escalation.lua`. AJ.9g toc-order assert catches any reorder. | AJ.9g toc-order asserts |
| 3 | **Saved-variable tier gates fail** at picker load time (`Bot.IsFzloky` returns nil because WHEREDNGNDB not yet populated) | LOW | Tier predicates are called at picker INVOCATION time, not at load time. `Bot.IsFzloky()` resolves through the shared `B.Bot` table reference set by Bot/Tiers.lua. | AE.4 + AC.6 + AK.7 |
| 4 | **jitter / shuffledSuits inline copy drift** from Bot.lua's originals | LOW | 4-line pure functions; Codex review verifies verbatim copy. Same pattern that worked in Bot/Bidding.lua. | Codex diff review + AC.6 jitter-frozen test |
| 5 | **Source pin retargeted incorrectly** (path changed but anchor doesn't match because comment text drifted during move) | MEDIUM | Verbatim move (Codex's Batch 5C/5B/8 guardrail). AJ.9g presence asserts mirror the retargeted pin anchors. Full harness catches any mismatch. | Full harness + Codex verbatim-comparison check |
| 6 | **Behavior drift from manual move** of ~700 lines (jitter expression evaluation order, closure capture of file-locals, etc.) | LOW-MEDIUM | Verbatim move via Python line-slice (same pattern that worked in Batch 8 for ~1400 lines of bidding). Behavioral coverage via AC.6 / AE.4 / AJ.13 / AK.7 + full harness. | Behavioral test results + Codex review |
| 7 | **Bot.lua re-binding header deletion leaves dangling references** if any post-Batch-8 helper inside Bot.lua still uses `sunStrength` / `partnerBidBonus` / etc. | MEDIUM | Grep BEFORE deletion: confirm zero non-escalation call sites for the 6 re-bound helpers. The 6 helpers were grep-verified in Batch 8 to only be consumed by escalation deciders + 2 comments at lines 6040/6289. After escalation moves, those comments may need updating too. | Grep + full harness |
| 8 | **Duplicate `BEL_JITTER` confusion**: Bot.lua's `local BEL_JITTER = 10` at line 5757 moves; Bot/Bidding.lua already has its own `local BEL_JITTER = 10` for PickPreempt. Bot/Escalation.lua absorbs the third copy. | LOW | Three independent locals in three files; same value. Codex review verifies each is intentional. | AJ.9g `local BEL_JITTER = 10` presence assert in Bot/Escalation.lua; grep confirms absence in Bot.lua |
| 9 | **styleBelTendency non-contiguous move** (line 374) — slicing skip-block has to thread around the keep-in-Bot.lua `styleTrumpTempo` at line 382 | LOW | Use Python line-slice for the small 7-line block + comment header. Verify boundaries by reading lines 370-389 before/after move. | Codex diff review + AJ.9g presence assert in Bot/Escalation.lua |

---

## 8. Recommended Batch 9 Implementation Scope

### 8A. Exact file list to change

| File | Action | Lines |
|---|---|---|
| `Bot/Escalation.lua` | **NEW** | ~750 raw (700 moved + ~50 module header + re-binding + exports) |
| `Bot.lua` | DELETE ~700 lines (escalation cluster + styleBelTendency) + DELETE ~13 lines (Bidding re-binding header from Batch 8, now unused) + ADD ~6 lines (two breadcrumbs at original locations) | net -707 lines |
| `WHEREDNGN.toc` | +1 line (`Bot/Escalation.lua`) | +1 |
| 11 test loader files | +1 line each | +11 |
| `tests/test_state_bot.lua` | 8 source-pin retargets + new AJ.9g block (~80 lines) | +85 |

**Total**: 1 new + 14 modified files.

### 8B. Approximate line-count movement

| File | Before (non-blank) | After (non-blank, est.) |
|---|---|---|
| `Bot.lua` | ~5,193 (post-Batch-8) | ~4,500 (-693) |
| `Bot/Escalation.lua` | — | ~660 |

Combined: ~700 lines move out of Bot.lua; ~12 lines of re-binding header in Bot.lua also disappear.

### 8C. Tests added in implementation batch

- AJ.9g source-pin block (45 asserts): file presence + toc-order + jitter constants + public picker definitions + Bidding helper imports + Bot.lua negative checks + style-ledger stay-asserts.
- No new behavioral tests needed — AC.6 / AE.4 / AJ.13 / AK.7 already cover behavior.

### 8D. Estimated harness count delta

**+30** (1189 → 1219). Actual implementation: AJ.9g block added 45 asserts; AJ.9f-bind retirement removed 6 asserts; retarget side-effects net to -9; total +30.

### 8E. Explicit deferrals

| Concern | Reason for defer |
|---|---|
| **`Bot.OnEscalation` / `Bot.OnRoundEnd` move** | Style-ledger updaters; called by State.lua's `ApplyDouble`/etc. Co-locating with the style ledger (lines 116-365 in Bot.lua) is cleaner. Not escalation-picker logic. **Stays in Bot.lua.** |
| **`emptyStyle` move** | Same reason. Style-ledger init. **Stays.** |
| **`styleTrumpTempo` move** | Used by pickLead/pickFollow (not escalation). **Stays.** |
| **AH.3 floor-cap behavioral strengthening** | Codex's Batch 7 verdict: existing AK.7 is weak; needs a dedicated load-bearing floor-cap fixture. Out of scope for Batch 9; retarget pin mechanically only. |
| **AA.1a/b behavioral conversion** | Internal escalationStrength bonus math; conversion would need PickDouble/PickTriple isolating void-vs-non-void deltas. Defer to optional Batch 10 prep. |
| **`jitter` / `shuffledSuits` extraction** | Used by every picker (escalation, bidding, play). Could move to Bot/PlayPrimitives.lua or a new Bot/Utils.lua. Out of scope for Batch 9; inline copies in Bot/Escalation.lua mirror the Bot/Bidding.lua pattern. |
| **Bot.lua memory/style ledger extraction** (Bot/Memory.lua) | Cross-module coupling with BotMaster.lua and Bot.OnEscalation/OnRoundEnd. Genuine refactor, not cleanup. Defer indefinitely (per the post-cleanup checkpoint). |
| **pickLead / pickFollow extraction** | Largest deferral by far (~4,400 lines). Out of scope. |

### 8F. Implementation guardrails for the later prompt

- **No runtime behavior changes** — verbatim move only.
- Use Python line-slice for the large `5752-6346` block + small `374-380` styleBelTendency block (mirrors Batch 8's surgery pattern).
- After deletion, **grep-verify** Bot.lua:
  - `bidderHoldsBidcard`, `meldKnownHeld`, `anyOpponentVoidIn`, `styleTrumpTempo`, `Bot.OnEscalation`, `Bot.OnRoundEnd`, `emptyStyle` all still defined.
  - No `escalationStrength`, `selfStyleJitterBonus`, `styleBelTendency`, BEL_JITTER, TRIPLE_JITTER, FOUR_JITTER, GAHWA_JITTER definitions remain.
  - No `Bot.PickDouble/PickTriple/PickFour/PickGahwa` function definitions remain.
  - The old 6-locals Bidding re-binding header (Bot.lua lines ~60-70) is deleted (no remaining consumers).
- After file write, **grep-verify** Bot/Escalation.lua:
  - All 7 file-local symbols present (3 helpers — `styleBelTendency`, `selfStyleJitterBonus`, `escalationStrength` — plus 4 jitter consts) AND the 4 public pickers as `function Bot.PickDouble/PickTriple/PickFour/PickGahwa(...)`. Total = 11 moved symbols. (Inline copies of `jitter` + `shuffledSuits` are utility duplicates, NOT counted as moved symbols.)
  - 6-locals re-binding header from Bot.Bidding present (suitStrengthAsTrump, sunStrength, partnerBidBonus, partnerEscalatedBonus, combinedUrgency, opponentUrgency).
  - Inline `jitter` and `shuffledSuits` present.
- Run full harness; actual result on implementation branch: **1219 / 1219 pass**.
- Run all 5 standalone smokes (H1, H7, numworlds, traced, bel-quality).
- Feature branch: `v3.2.0-cleanup-batch9-escalation`.
- Commit + push, **do not merge**.

---

## 9. Final Recommendation

**APPROVE Option C extraction as Batch 9 implementation.**

Implementation branch: **`v3.2.0-cleanup-batch9-escalation`**.

Headline numbers:
- **7 file-local moved symbols/consts** (`styleBelTendency`, `selfStyleJitterBonus`, `escalationStrength`, `BEL_JITTER`, `TRIPLE_JITTER`, `FOUR_JITTER`, `GAHWA_JITTER`) **plus 4 public picker functions** (`Bot.PickDouble`, `Bot.PickTriple`, `Bot.PickFour`, `Bot.PickGahwa`) = **11 moved symbols total**. Inline copies of `jitter` + `shuffledSuits` are utility duplicates (mirroring Batch 8's Bot/Bidding.lua pattern), NOT counted as moved symbols.
- ~700 lines moved from Bot.lua to Bot/Escalation.lua.
- Bot.lua additionally **sheds** the 6-locals Bidding re-binding header from Batch 8 (no longer needed).
- 11 test loaders + 7 source-pin retargets (do-blocks; 8 individual assertions inside) + new AJ.9g block (45 asserts) + AJ.9f-bind retirement (-6 asserts).
- Actual harness: **1219 / 1219 pass** (1189 + 30 net).
- Risk class: **MEDIUM**.
- Cleanly establishes the `Bot/<Subsystem>.lua` pattern for any future extraction (Memory, pickLead/pickFollow further down the road).

### Why this scope (not smaller)

- Option C is the only option that avoids creating a new public sub-table (`B.Bot.Escalation.*`) or polluting `B.Bot.*` with internal helpers. Cleaner pattern.
- All 4 escalation pickers + escalationStrength + selfStyleJitterBonus + 4 jitter constants form a tight semantic cluster.
- Bot.lua's residual content (memory/style ledgers + OnEscalation/OnRoundEnd + pickLead/pickFollow + play deciders) is cleanly separated from escalation post-move.

### Why this scope (not larger)

- `Bot.OnEscalation` / `Bot.OnRoundEnd` stay — they're style-ledger maintenance called from State.lua, not picker logic.
- `Bot._partnerStyle` / `Bot._memory` stay — they're shared with pickLead/pickFollow/BotMaster.
- pickLead/pickFollow stay — too large, out of scope.

---

## Summary

| Item | Value |
|---|---|
| Design doc path | `.swarm_findings/v3_2_0_batch9_escalation_design.md` |
| Recommended option | **Option C — full escalation cluster** (8 helpers/consts + 4 pickers) |
| Functions to move | 4 jitter consts (BEL/TRIPLE/FOUR/GAHWA_JITTER), selfStyleJitterBonus, styleBelTendency, escalationStrength, Bot.PickDouble/PickTriple/PickFour/PickGahwa |
| Functions to stay | Bot.OnEscalation, Bot.OnRoundEnd, emptyStyle, styleTrumpTempo, bidderHoldsBidcard, meldKnownHeld, anyOpponentVoidIn, jitter, shuffledSuits, Bot._partnerStyle, Bot._memory |
| Source-pin inventory | 8 retargets (AA.1a/b, AB.2, AD.3, AD.7a/b, AH.3, AH.7, AI.4) — single file-path edit each; ~5 stay scanning Bot.lua (escalation-adjacent body checks); behavioral tests AC.6/AE.4/AJ.13/AK.7 unchanged |
| Test gaps | None blocking. Existing AC.6/AE.4/AJ.13/AK.7 cover behavior. AH.3 floor-cap structural pin stays source-only (Codex's Batch 7 verdict). |
| Expected implementation risk | **MEDIUM** (comparable to Batch 8 but simpler: fewer moving parts, no public sub-table, Bot.lua re-binding header shrinks instead of growing) |
| Actual harness | **1219 / 1219 pass** (1189 + 45 AJ.9g asserts − 6 AJ.9f-bind retirements − 9 retarget side-effects = +30 net) — verified on implementation branch `v3.2.0-cleanup-batch9-escalation` at commit `fd31215` |
| Predicted files changed | 1 new (`Bot/Escalation.lua`) + 14 modified (Bot.lua, WHEREDNGN.toc, 11 test loaders, tests/test_state_bot.lua) |
| Working tree status | clean except this design doc untracked at `.swarm_findings/v3_2_0_batch9_escalation_design.md` |

No runtime code touched. No tests touched. No implementation branch cut. No commits. Awaiting Codex review before any implementation.
