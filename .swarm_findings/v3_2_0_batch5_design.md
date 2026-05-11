# v3.2.0 Cleanup Batch 5 — UI / Bot Decomposition Design Pass

**Status**: design only, no code changes. Output for Codex review
before implementation.

**Branch baseline**: `main` at `e1282cf` (post-Batch 4A). Working
tree clean. Tests at 1106/1106 pass. Last shipped tag: `v3.1.14`.

**Goal**: inventory the four large source files and propose a safe
decomposition plan WITHOUT changing runtime behavior. Identify the
single safest first slice for Batch 5A (or recommend a preparatory
test batch if no safe move exists yet).

## 1. Current module inventory

### 1.1 File sizes (Lua, by line count)

| File | Lines | Functions (exports + locals) | Notes |
|---|---|---|---|
| `Bot.lua` | **8,428** | 67 | Largest. Bidding + play decision tree. `pickLead` is **1,847 lines**, `pickFollow` is **2,386 lines** |
| `Net.lua` | 6,430 | 152 | Network wire + AFK timers + state machine glue. Many small functions; cohesive but long |
| `UI.lua` | **4,941** | 59 (mostly local) | Frame creation, render pipeline, theming, banners, action buttons. Public API is small (`U.Refresh`, `U.Show/Hide/Toggle/IsShown`, theme setters) |
| `State.lua` | 2,570 | 62 | `S.s` global state + `S.Apply*` mutations + helpers. Public-API surface is wide (resync depends on Apply functions) |
| `Rules.lua` | 1,335 | — | Pure rule engine. Already small enough |
| `BotMaster.lua` | 1,207 | 10 | ISMCTS rollouts + sampler. Sampler `sampleConsistentDeal` is ~490 lines; `rolloutValue` is ~300 lines |
| `Slash.lua` | 775 | — | Dispatcher for `/baloot`. Cohesive |
| `Constants.lua` | 750 | — | All constants. Already structured |
| `WHEREDNGN.lua` | 724 | — | Entry + event handlers |
| `Cards.lua` | 221 | — | Pure card utilities. Small |
| `Easter.lua` | 154 | — | Optional, deletable |
| `MinimapIcon.lua` | 131 | — | Cohesive |
| `Sound.lua` | 91 | — | Cohesive |
| `Log.lua` | 57 | — | Cohesive |

**Total**: ~28,000 Lua lines across 14 files. The 4 largest files
(Bot, Net, UI, State) account for **80%** of the codebase.

### 1.2 Major responsibility clusters

**Bot.lua** clusters (from top to bottom):
- **Tier flags** (lines ~30-50): `IsAdvanced/IsM3lm/IsFzloky/IsSaudiMaster/IsBotSeat`
- **Memory + style ledgers** (~150-440): `_memory` (per-seat play observation), `_partnerStyle` (per-seat behavioral ledger), `ResetMemory`, `ResetStyle`, `OnEscalation`, `OnRoundEnd`, `OnPlayObserved`
- **Hand-strength helpers** (~440-880): `suitStrengthAsTrump`, `sideSuitAceBonus`, `hokmMinShape`, `sunMinShape`, `beloteSuit`, `aceCountAndMardoofa`, `meldKnownHeld`, `bidderHoldsBidcard`, `withBidcard`, `sunStrength`
- **Urgency + partner-bid math** (~880-1200): `partnerBidBonus`, `scoreUrgency`, `opponentUrgency`, `matchPointUrgency`, `combinedUrgency`, `partnerEscalatedBonus`
- **`Bot.PickBid`** (~1718-2317, ~600 lines)
- **Play-pick primitives** (~2320-2645): `pickRandomTied`, `lowestByRank`, `highestByRank`, `highestByFaceValue`, `holdsBeloteThusFar`, `highestTrump`, `legalPlaysFor`, `wouldWin`, `tahreebClassify`, `applyClosedTrumpLeadGate`
- **`pickLead`** (lines 2646-4492, **1847 lines**) — opening-leads decision tree, Saudi-rule branches, Tahreeb sender, partner-coord, Bargiya, Faranka, etc.
- **`pickFollow`** (lines 4570-6955, **2386 lines**) — partnerWinning, opp-winning, smother/Takbeer, AKA-receiver, Faranka, Belote preservation, urgency-aware swing, deceptive-overplay, etc.
- **`Bot.PickAKA` / PickAKANoise / PickPlay** (~6955-7100): entry points that dispatch into pickLead/pickFollow
- **`Bot.PickMelds` + `selfStyleJitterBonus`** (~7100-7700)
- **`Bot.PickDouble/Triple/Four/Gahwa`** (~7700-8000): escalation deciders, share `escalationStrength` helper
- **`Bot.PickPreempt/PickOvercall/PickKawesh/PickTakweesh/PickSWA/PickSWAResponse`** (~8000-8428): less-frequent picks

**UI.lua** clusters:
- **Theme data tables** (lines 69-156): `CARD_STYLES`, `FELT_THEMES`, `B._cardStyles`, `B._feltThemes`, `COL` — **pure data, no WoW API**
- **Theme helpers** (~157-260): `activeCardStyleName`, `activeFeltThemeName`, `applyThemeColors`, `seatAtPos`, `posOfSeat` — almost-pure (a few WoW-API touches in `applyThemeColors`)
- **Frame primitives** (~260-510): `setBackdrop`, `cardTexturePath`, `makeCardFace`, `setCardSlot`, `makeCardBack`, `makeText`, `makeButton`, `fadeBanner` — heavily WoW-API
- **Layout builders** (~510-1500): `buildMain`, `buildLobby`, `buildMeldStrip`, `buildSeatBadge`, `buildCenterSlot`, `buildTable` — WoW-API + theme reads
- **Action buttons** (~1500-2200): `bindConfirm`, `clearActions`, `addAction`, `addConfirmAction`, `renderActions`
- **Hand rendering** (~2200-2900): `makeHandButton`, `clearHand`, `renderHand`
- **Seat / center / banners / NASHRAH** (~2900-4500): `renderSeats`, `renderCenter`, `animateLand`, `renderBanner`, `renderOvercallBanner`, `renderTakweeshReviewBanner`, `renderSWABanner`, `renderAKABanner`, `renderPeekButton`, `renderPauseControls`, `renderNashrahPanel`, `renderStatus`
- **Style/theme apply pipeline** (~4500-4660): `styleListFrom`, theme switch handlers
- **Public API** (4663+): `U.Refresh`, `U.PulseTurn`, `U.Show/Hide/Toggle/IsShown`, `U.SetCardStyle/SetFeltTheme/SetTheme`, `U.GetCardStyles/GetFeltThemes/GetActiveCardStyle/GetActiveFeltTheme/GetThemes/GetActiveTheme`

### 1.3 Module-table exports / coupling

**Public exports** (called from outside the file):

| Module | Public exports | Cross-module callers |
|---|---|---|
| `B.Bot.*` | 22 functions (`PickBid/Play/AKA/Melds/Double/Triple/Four/Gahwa/Preempt/Overcall/Kawesh/Takweesh/SWA/SWAResponse`, `OnPlayObserved`, `OnEscalation`, `OnRoundEnd`, `ResetMemory`, `ResetStyle`, `OpponentUrgency`, `Is*`, `IsBotSeat`, `PickAKANoise`) | Net.lua (most), BotMaster.lua (PickPlay + OpponentUrgency), State.lua (OnEscalation + OnRoundEnd) |
| `B.Bot._memory`, `B.Bot._partnerStyle`, `B.Bot._inRollout` | Internal state, BUT read from BotMaster.lua + tests | **Coupling hazard** — moving these into a sub-module breaks BotMaster's direct field access |
| `B.UI.*` | `SaudiName`, `ArabicAvailable`, `GetMuteBtn`, `FadeBanner`, `Refresh`, `PulseTurn`, `Show/Hide/Toggle/IsShown`, `SetCardStyle/FeltTheme/Theme`, `GetCardStyles/FeltThemes/ActiveCardStyle/ActiveFeltTheme/Themes/ActiveTheme` | Net.lua (Refresh — extremely heavy), Slash.lua (Show/Hide/Toggle), Easter.lua, WHEREDNGN.lua |
| `B._cardStyles`, `B._feltThemes` | Read from Slash.lua lobby option list |
| `B.Net.*` | Many; cross-called from State.lua, UI.lua (Net.Local*), Slash.lua, WHEREDNGN.lua |
| `B.State.*` (`S.*`) | Wide public API; State.Apply* is the canonical mutation surface |

**Internal-only Bot.lua functions** (good candidates for extraction
because no cross-module call site exists):
- All `local function` declarations: hand-strength helpers, urgency
  math, play-pick primitives, `pickLead`, `pickFollow`, etc.
- These can be moved into a sub-module IF a clean module boundary
  preserves shared upvalues (`Bot._memory`, `Bot._partnerStyle`,
  `K`, `C`, `R`, `S` locals).

### 1.4 Load order (`WHEREDNGN.toc`)

```
1. Log.lua             — no deps
2. Constants.lua       — no deps
3. Sound.lua           — depends on K
4. Cards.lua           — pure
5. Rules.lua           — depends on C
6. State.lua           — depends on K, C, R
7. Bot.lua             — depends on K, C, R, S
8. BotMaster.lua       — depends on K, C, R, S, B.Bot
9. Net.lua             — depends on everything above
10. UI.lua             — depends on K, C, R, S; B.Net referenced LAZILY via net() helper
11. MinimapIcon.lua
12. WHEREDNGN.lua      — entry
13. Slash.lua          — dispatcher
14. Easter.lua         — optional
```

**Load-order constraints for decomposition**:
- Any new file extracted from Bot.lua must load BEFORE BotMaster.lua
  (which reads `B.Bot._memory` / `B.Bot._partnerStyle` directly).
- Any new file extracted from UI.lua must load BEFORE the file it
  feeds into OR be careful about lazy resolution. UI.lua's
  `net()` lazy pattern shows how to defer Net access.
- Tests (`tests/test_state_bot.lua`) load files explicitly via
  `load("Bot.lua")` / etc. Any new file must also be added to the
  test loader.

## 2. Bot decomposition candidates

Candidate slices ranked by extraction safety:

| # | Slice | Lines | Target file | Difficulty | Dependencies | Test risk | Recommendation |
|---|---|---|---|---|---|---|---|
| 1 | **Tier flags** (`IsAdvanced/IsM3lm/IsFzloky/IsSaudiMaster/IsBotSeat`) | ~20 | `Bot/Tiers.lua` | Trivial | `K`, `WHEREDNGNDB` | Low — no source pins | Yes, easy first move |
| 2 | **Play-pick primitives** (`lowestByRank`, `highestByRank`, `highestByFaceValue`, `holdsBeloteThusFar`, `highestTrump`, `legalPlaysFor`, `wouldWin`, `tahreebClassify`) | ~330 | `Bot/PlayPrimitives.lua` | Easy | `K`, `C`, `R`, `S` | LOW — all local-functions, no source pins target them | **Strong candidate** — pure helpers, no global state |
| 3 | **Hand-strength helpers** (`suitStrengthAsTrump`, `sideSuitAceBonus`, `hokmMinShape`, `sunMinShape`, `beloteSuit`, `aceCountAndMardoofa`, `bidderHoldsBidcard`, `sunStrength`) | ~440 | `Bot/HandStrength.lua` | Easy-MED | `K`, `C`, `S` | MED — pins exist on some (AD.2 wires `bidderHoldsBidcard`; AH.7 wires `sunStrength`/`escalationStrength`) | Possible Batch 5B candidate |
| 4 | **Memory + style ledgers** (`_memory`, `_partnerStyle`, `ResetMemory`, `ResetStyle`, `OnEscalation`, `OnRoundEnd`, `OnPlayObserved`, `styleBelTendency`, `styleTrumpTempo`) | ~290 | `Bot/Memory.lua` | MED-HIGH | Coupling to BotMaster (reads `_memory`/`_partnerStyle` directly). Moving the storage fields without updating BotMaster.lua would break C-14 delegation | HIGH | **Defer** — needs BotMaster co-change |
| 5 | **`Bot.PickBid`** | ~600 | `Bot/PickBid.lua` | HIGH | Many cross-suit calls into hand-strength helpers + urgency. Would need to extract those first | HIGH — Section C, T, AA, AC, AD have multiple source pins inside PickBid body | **Defer** |
| 6 | **`pickLead`** | **1,847** | `Bot/PickLead.lua` | VERY HIGH | All play-pick primitives + memory ledgers + urgency. Source pins everywhere (AI, AK, AN sections target specific branches by source-string match) | VERY HIGH | **Defer indefinitely** — needs aggressive source-pin retirement first |
| 7 | **`pickFollow`** | **2,386** | `Bot/PickFollow.lua` | VERY HIGH | Same as pickLead. Even more pins | VERY HIGH | **Defer indefinitely** |
| 8 | **Escalation deciders** (`PickDouble/Triple/Four/Gahwa/Preempt/Overcall`, `selfStyleJitterBonus`, `escalationStrength`) | ~480 | `Bot/Escalation.lua` | MED | Cross-uses `Bot._partnerStyle`, hand-strength helpers, urgency. Source pins in AC, AD, AE, AH | MED-HIGH | **Defer to Batch 5C/5D** |
| 9 | **Less-frequent picks** (`PickKawesh/PickTakweesh/PickSWA/PickSWAResponse`, `PickAKA/PickAKANoise`) | ~430 | `Bot/PickAuxiliary.lua` | MED | Hand-strength + Rules | MED | Possible after primitives + strength extracted |

## 3. UI decomposition candidates

UI.lua has cleaner module boundaries because its public API is small
(`U.Refresh`, `U.Show/Hide/Toggle/IsShown`, theme setters). But the
internal-render pipeline is deeply entangled with WoW frame state
(`f`, `seatBadges`, `centerCards` upvalues that every renderer
mutates).

| # | Slice | Lines | Target file | Difficulty | Dependencies | WoW-API/taint risk | Recommendation |
|---|---|---|---|---|---|---|---|
| 1 | **Theme data tables** (`CARD_STYLES`, `FELT_THEMES`, `COL` initial values) | ~95 | `UI/Themes.lua` | Trivial | None (pure data) | None | **Strong candidate** — pure tables, already exposed as `B._cardStyles`/`B._feltThemes` |
| 2 | **Theme helpers** (`activeCardStyleName`, `activeFeltThemeName`, `applyThemeColors`, `cardStyleData`, `feltThemeData`, `cardTexturePath`) | ~80 | `UI/Themes.lua` | Easy | `K`, `WHEREDNGNDB`, theme tables | Low — `SetTexture`-style WoW calls only fire if frames exist | Combine with #1 into single `UI/Themes.lua` |
| 3 | **Frame primitives** (`makeCardFace`, `setCardSlot`, `makeCardBack`, `makeText`, `makeButton`, `setBackdrop`, `fadeBanner`) | ~250 | `UI/FramePrimitives.lua` | MED | Heavy WoW-API (`CreateFrame`, `SetScript`) | MED — taint-sensitive in combat; primitives must not register secure events | Possible Batch 5B |
| 4 | **Hand renderer** (`makeHandButton`, `clearHand`, `renderHand`) | ~450 | `UI/HandRender.lua` | MED-HIGH | Shared `f.handFrame` upvalue, `S.s.hand`, click-handlers that route through `N.LocalPlay` | HIGH — moving requires either exposing the upvalue or passing it explicitly | **Defer** |
| 5 | **Seat rendering** (`renderSeats`, `bidLabelForSeat`, `cardCountForSeat`, `meldStripVisibleFor`, `buildSeatBadge`) | ~700 | `UI/SeatRender.lua` | HIGH | Same upvalue coupling | HIGH | **Defer** |
| 6 | **Banner renderers** (`renderBanner`, `renderOvercallBanner`, `renderTakweeshReviewBanner`, `renderSWABanner`, `renderAKABanner`) | ~600 | `UI/Banners.lua` | HIGH | `f.banner` upvalue, `B.UI.FadeBanner`, state reads | HIGH | **Defer** |
| 7 | **NASHRAH panel** (`renderNashrahPanel`) | ~150 | `UI/Nashrah.lua` | MED-HIGH | `f.nashrahPanel`, `WHEREDNGNDB.history`, scroll frame | MED | Possible later |
| 8 | **Action buttons** (`clearActions`, `addAction`, `addConfirmAction`, `renderActions`, `bindConfirm`) | ~700 | `UI/Actions.lua` | HIGH | `f.actionsFrame` upvalue, `N.Local*` call sites for every Saudi action | HIGH | **Defer** |

**Load-order hazard**: UI.lua establishes the main frame upvalue
(`f`) and many sibling upvalues (`seatBadges`, `centerCards`,
`statusText`, `lobbyPanel`, `tablePanel`). Every render function
mutates this shared state through upvalue closure. **Extracting any
renderer into a separate file requires either**:
- (a) Making the frame state explicit (pass `f` as a parameter — invasive)
- (b) Exposing the frame state as a module-level table (`B.UI._f` etc.) — increases surface area
- (c) Splitting via a "context" object passed at module init

All three are non-trivial. UI.lua decomposition is significantly
harder than Bot.lua decomposition because of the upvalue mesh.

## 4. Test impact

### 4.1 Source-pin coupling counts

`tests/test_state_bot.lua`:
- **botSrc:find** / equivalent: 134 source-loader assertions
- **uiSrc:find**: 37
- **netSrc:find**: many (Batch 4A added more; still ~50-100)
- **stateSrc:find**: many

The `botSrc:find` pins are concentrated in sections AA-AK (audit
fixes v0.11.x-v1.0.x) and target specific code patterns inside
`pickLead`/`pickFollow`/`Bot.PickBid`/`escalationStrength`. Moving
those functions to a new file would break the file-source-pin
mechanism (`io.open(WHEREDNGN_TESTS_ROOT .. "/Bot.lua")` would
not contain the moved patterns).

The `uiSrc:find` pins target:
- `K.RANK_INDEX[rank]` / `K.SUIT_INDEX[suit]` lookups inside NASHRAH
- Action-button labels (`addAction("Sun")` / `SaudiName("SUN")`)
- The dead-code retirement assertions (`meldsDescForSeat == nil`,
  `meldTextVisible == nil`, etc.)

### 4.2 Behavioral tests that protect a move

- **AZ section** (Batches 2-4A) — captured-broadcast / fired-timer
  pattern. Covers Net-side wire-retry behavior; doesn't constrain
  Bot/UI structure.
- **B, C, D sections** in `test_state_bot.lua` — Bot.PickPlay
  legality, Bot.PickBid sanity, headless tournament. These test
  decision OUTPUTS, not source structure, so they survive a
  successful refactor.
- **F section in `test_botmaster.lua`** (Batch 3 AD.4a) — BotMaster
  single-card-shortcut diagnostic. Tests state observation.

### 4.3 New tests needed before any migration

For Bot.lua slice extraction (any slice), need stronger behavioral
coverage of the slice's public outputs FIRST. Example: before
extracting hand-strength helpers, add behavioral tests for
`Bot.PickBid` return values at the threshold boundaries that the
helpers compute. The PickBid tests in Section C exist but rely on
many source pins for the internal helpers; converting those is
already Batch 3's pattern but only 5 pins were converted there.

For UI.lua slice extraction, need behavioral coverage of the
render pipeline's effects (e.g., button state after `U.Refresh`,
banner visibility after `_OnTakweeshReview`). The test harness
currently doesn't load UI.lua because of WoW-frame mocking
complexity. Adding behavioral UI test infrastructure is itself a
sizable batch.

## 5. Recommended Batch 5A implementation scope

### Recommendation: extract pure UI theme tables → `UI/Themes.lua`

**Specifically**: move `CARD_STYLES`, `FELT_THEMES`, and the small
helpers `activeCardStyleName` / `activeFeltThemeName` /
`cardStyleData` / `feltThemeData` / `cardTexturePath` /
`applyThemeColors` into a new file `UI/Themes.lua` that loads
BEFORE `UI.lua` in the .toc.

**Why this is the safest first slice**:

1. **Pure data tables** — CARD_STYLES and FELT_THEMES are nested
   tables of color RGBA + texture path strings. Zero behavioral
   coupling.
2. **Already exposed as `B._cardStyles` / `B._feltThemes`** — the
   exfiltration shape exists; the new file can write to the same
   table names without any caller migration.
3. **Theme helpers are almost-pure** — `activeCardStyleName` reads
   `WHEREDNGNDB.cardStyle`, returns a string; `applyThemeColors`
   mutates the `COL` table which is the only side effect. Both
   are deterministic.
4. **Minimal cross-module callers** — Slash.lua reads
   `B._cardStyles`/`B._feltThemes` for the lobby option list;
   `U.Get*` getters wrap them. After extraction these readers
   continue to work unchanged because the table names stay the
   same.
5. **Existing source pins**: only AJ.9 ("`4 Colors` + `Ba8ala SET`
   name renames") would need its uiSrc context to also scan
   `UI/Themes.lua` — trivial pin adjustment.
6. **No WoW-API risk on load** — the new file contains data + pure
   helpers; the heavy frame primitives stay in UI.lua.
7. **Test harness compatibility**: `tests/test_state_bot.lua`
   doesn't load UI.lua at all. The new `UI/Themes.lua` would not
   need to be loaded by the test harness either.

**Concrete migration shape**:

```lua
-- New file: UI/Themes.lua (loaded BEFORE UI.lua in .toc)

WHEREDNGN = WHEREDNGN or {}
local B = WHEREDNGN
B.UI = B.UI or {}
local K = B.K

local CARD_STYLES = { ... }   -- moved verbatim
local FELT_THEMES = { ... }   -- moved verbatim

B._cardStyles = CARD_STYLES
B._feltThemes = FELT_THEMES

-- Theme-active-key helpers (moved from UI.lua)
local function activeCardStyleName() ... end
local function activeFeltThemeName() ... end

-- Expose for UI.lua to consume (replace its local declarations)
B.UI._activeCardStyleName = activeCardStyleName
B.UI._activeFeltThemeName = activeFeltThemeName
B.UI._cardStyleData = function() return CARD_STYLES[activeCardStyleName()] end
B.UI._feltThemeData = function() return FELT_THEMES[activeFeltThemeName()] end
```

**Then in `UI.lua`**: replace the 5 inline locals with thin wrappers
that consult `B.UI._*`. No render-pipeline changes.

**Lines of code change estimate**:
- New `UI/Themes.lua`: ~180 lines (95 lines of data + ~80 lines of
  helpers + comments)
- `UI.lua` reduction: ~180 lines
- `.toc` insert: 1 line
- Tests: 0-1 source-pin update (AJ.9 may need to scan two files)

**Net effect**: behavior preserved, no public API change, UI.lua
drops to ~4,760 lines.

### Alternative Batch 5A: extract `Bot/Tiers.lua` (smaller, even safer)

If Codex prefers an even more conservative first move: extract
just the 5 tier-flag functions (`Bot.IsAdvanced/IsM3lm/IsFzloky/
IsSaudiMaster/IsBotSeat`). Only ~20 lines, no source pins, no
behavioral coupling. Doesn't materially shrink Bot.lua but proves
the extraction pattern with zero risk.

**Recommendation between the two**: prefer **UI Themes** because
it (a) actually shrinks the file by a meaningful amount (~180
lines), (b) demonstrates the .toc load-order pattern, and (c) the
data tables are objectively the cleanest extraction target in the
entire codebase.

### Tests required before Batch 5A merge

- Run full harness — should remain 1106/1106 green.
- Add 1-2 thin source-pin updates if AJ.9 ("4 Colors / Ba8ala SET
  name renames") needs cross-file scan.
- No new behavioral tests needed — theme data is render-side and
  not exercised by the test harness.

## 6. Explicit deferrals

The following are too risky for Batch 5A:

1. **`pickLead` / `pickFollow` extraction** — too many source pins,
   too much shared state (`Bot._memory`, `Bot._partnerStyle`).
   Requires a multi-batch source-pin retirement campaign first
   (continuation of Batch 3's pattern).
2. **`Bot._memory` / `Bot._partnerStyle` move** — BotMaster.lua
   reads these directly. Moving requires coordinated edits in
   BotMaster + extraction-target file + tests.
3. **`Bot.PickBid` extraction** — multiple source pins target
   internal branches. Needs pin-conversion first.
4. **Any UI renderer extraction** (`renderSeats`, `renderBanner`,
   `renderHand`, `renderActions`, etc.) — entangled with frame
   upvalues (`f`, `seatBadges`, `centerCards`). Decomposition
   requires either invasive frame-state-as-parameter refactor OR a
   shared context-object pattern.
5. **Net.lua decomposition** — out of scope per audit plan
   (Batch 5 is "UI and Bot decomposition"; Net.lua decomposition
   would be a separate batch family). Also the file is more
   cohesive than its line count suggests — every function is part
   of one of: send helpers, receive handlers, state-machine
   advance, or local-action UI bridge.
6. **State.lua decomposition** — wide public API consumed by every
   other file; high cross-module coupling risk.

Recommended ordering after Batch 5A:
- **5B**: Bot tier flags + Bot play-pick primitives → `Bot/Tiers.lua` + `Bot/PlayPrimitives.lua`
- **5C**: Bot hand-strength helpers → `Bot/HandStrength.lua` (requires retiring some Section C/AD source pins first)
- **5D**: UI frame primitives → `UI/FramePrimitives.lua` (requires deciding on frame-state pattern)
- **5E+**: hold until Codex review or user signal

## Summary

- **Inventoried**: 14 Lua files (~28k lines). Top 4 (Bot/Net/UI/State)
  are 80% of the code. The behemoths are `pickLead` (1.8k lines)
  and `pickFollow` (2.4k lines), both inside `Bot.lua`.
- **Recommended Batch 5A**: extract `UI/Themes.lua` (~180 lines
  moved from UI.lua → new file). Zero behavioral coupling, zero
  source-pin damage, demonstrates the .toc load-order pattern, and
  produces a meaningful first slice.
- **Confirmed**: no runtime code changed in this design pass. Only
  one new design doc on disk (this file, untracked).
- **Branch / main state**: clean. `main` at `e1282cf`. No new
  branches created.

Awaiting Codex review of the design doc and a sign-off on the
Batch 5A scope (UI/Themes extraction) before implementation.
