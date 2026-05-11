# v3.2.0 Post-Cleanup Checkpoint

Pause point after the v3.2.0 cleanup/decomposition wave. No new
extraction batch from this doc — design/audit checkpoint only.

---

## 1. Current State

| Field | Value |
|---|---|
| `main` commit | `3b333eb` — docs: add v3.2.0 post-cleanup checkpoint |
| Previous polish commit | `6ae91e1` — H7 stale-comment refresh |
| Previous cleanup commit | `51c3be9` — Batch 5C |
| Last shipped CurseForge tag | **v3.1.14** (commit `c1c624f`) |
| Working tree | clean |
| Full harness | **1150 / 1150 pass** |
| Branch list | `main` + two historical experimental branches (`sprint-a-experimental`, `v0.5.1-experimental`) |
| Merged cleanup branches | all deleted (Batch 3, 4A, 5A, 5B, 5C local + remote) |
| Release tag for this work | none — cleanup-only, no gameplay change |

---

## 2. Cleanup Stack Summary

| Batch | Commit | Files touched | Purpose |
|---|---|---|---|
| 1 | `fde6aea` | `Net.lua`, `tests/test_state_bot.lua` | Remove dead helpers; extract skip senders (`SendSkipDouble`, `SendSkipTriple`, `SendSkipFour`, `SendSkipGahwa`) |
| 2 | `c2e0a99` | `Net.lua`, `tests/test_state_bot.lua` | Extract `broadcastWithRetry(frame, guardFn)` helper used by 17 broadcast call sites |
| 3 | `eb66339` | `tests/test_state_bot.lua` | Convert 4 source-pinned assertions to behavioral tests |
| 4A | `e1282cf` | `Net.lua`, `tests/test_state_bot.lua` | Skip/preempt retry coverage; critical two-branch `SendPreempt` guard for LocalPreempt vs host bot orderings |
| 5A | `9ef3178` | `UI/Themes.lua` (new), `UI.lua`, `WHEREDNGN.toc`, `tests/test_state_bot.lua` | Extract `UI/Themes.lua`: `CARD_STYLES`, `FELT_THEMES`, `COL` palette, theme helpers; ~180 lines moved out of UI.lua |
| 5B | `1d9cdb2` | `Bot/Tiers.lua` (new), `Bot.lua`, `WHEREDNGN.toc`, 11 test loaders, `tests/test_state_bot.lua` | Extract `Bot/Tiers.lua`: 5 tier predicates (`IsAdvanced` / `IsM3lm` / `IsFzloky` / `IsSaudiMaster` / `IsBotSeat`); ~60 lines moved out of Bot.lua |
| 5C | `51c3be9` | `Bot/PlayPrimitives.lua` (new), `Bot.lua`, `WHEREDNGN.toc`, 11 test loaders, `tests/test_state_bot.lua`, `tests/test_H7_*.lua` (anchor update) | Extract `Bot/PlayPrimitives.lua`: 10 play helpers (`pickRandomTied`, `lowestByRank`, `highestByRank`, `highestByFaceValue`, `holdsBeloteThusFar`, `highestTrump`, `legalPlaysFor`, `wouldWin`, `tahreebClassify`, `applyClosedTrumpLeadGate`); ~333 lines moved out of Bot.lua |
| Tooling | `08473ce` | `tests/test_bel_decision_quality.lua` | Fix `math.random` shim arity dispatch so the standalone bel-quality runner handles 0-arg / 1-arg / 2-arg call sites under Lupa |
| Comment polish | `6ae91e1` | `tests/test_H7_sun_shortest_lead.lua` | Refresh stale "after lowestByRank" wording to match the post-5C "before pickLead" anchor |

Plus design/inventory docs for batches 2, 3, 4, 5, 5B, 5C committed to
`main` in their own `docs:` commits (not listed individually here).

---

## 3. Module Map After Cleanup

Current line counts (Lua files). Counts are **non-blank lines** —
empty rows skipped, comment-only rows included. Raw `wc -l` totals
roughly 4% higher across the board if reproduced; the non-blank
metric is the one Codex normalizes against batch-to-batch.

| File | Lines | Role |
|---|---|---|
| `Bot.lua` | **7 875** | Heuristic AI: `PickBid` + lead/follow + escalation + AKA/SWA/Takweesh/Kawesh + preempt + memory recorder + style ledger + jitter + hand-strength math |
| `Net.lua` | **6 205** | Addon-channel protocol: bid / play / contract / escalation / preempt / overcall / takweesh / SWA / outcome / review / resync; `broadcastWithRetry`; AFK routing |
| `UI.lua` | **4 534** | All frames: main window, lobby panel, table panel, action panel, seat badges, center cards, banner, score/contract/round/gameID labels, scale controls, sound mute, peek-last-trick, theme setters |
| `State.lua` | **2 464** | `S.s` global state table; phase transitions; per-trick / per-round bookkeeping; SaveSession debounce; ApplyResyncSnapshot; IsSeatBot |
| `Rules.lua` | **1 265** | Legality + scoring: `IsLegalPlay`, `CurrentTrickWinner`, `ScoreRound`, meld detection, partner/seat helpers |
| `BotMaster.lua` | **1 157** | Saudi-Master tier: ISMCTS sampler, rollout playout, partner-style hints, opp-urgency dispatcher |
| `Slash.lua` | **732** | `/baloot` subcommands; debug surface |
| `Constants.lua` | **706** | `K.*` constants; `K.SAUDI_NAMES`; bid-strength thresholds |
| `WHEREDNGN.lua` | **706** | Event loop entry; PARTY_LEADER_CHANGED handling; addon-message dispatcher; tab nav |
| `Bot/PlayPrimitives.lua` | **372** | (NEW in 5C) Play helpers under `B.Bot.Primitives` |
| `UI/Themes.lua` | **247** | (NEW in 5A) Card/felt themes + `COL` palette + theme helpers under `U.Theme` |
| `Cards.lua` | **196** | Card id / suit / rank / trick-rank / point-value primitives |
| `Easter.lua` | **139** | Optional easter egg; deletable |
| `MinimapIcon.lua` | **112** | LibDBIcon glue |
| `Sound.lua` | **85** | Cue scheduler + arming |
| `Bot/Tiers.lua` | **75** | (NEW in 5B) Tier predicates under `B.Bot.*` |
| `Log.lua` | **48** | `B.Log.Debug` / `B.Log.Info` / etc. |
| **Total addon Lua lines** | **26 918** | |

### What remains in `Bot.lua` (7 875 lines)

(The `~xxxx-yyyy` ranges below are raw source-line addresses — what
your editor shows when navigating Bot.lua — not non-blank counts.
The section heading uses non-blank lines for batch-to-batch
comparison; the internal address ranges use raw lines so you can
jump directly to a function.)

Top region (lines 1-128): module setup, tuning constants, tier
breadcrumb (5B), play-primitive re-binding header (5C), `jitter`,
`shuffledSuits`.

Mid region:
- ~129-450: card-memory ledger (`Bot._memory`) + reset + record/replay
  (`OnPlayObserved`)
- ~450-770: partner-style ledger (`Bot._partnerStyle`) + reset/escalation
  observers + Tahreeb signal recorders
- ~770-1700: hand-strength math (`OpponentUrgency` + sunStrength +
  hokmMinShape + bid candidate evaluation)
- ~1700-2275: `Bot.PickBid` (~575 lines) — the bid decider
- ~2280-2287: `-- Play` section header + breadcrumb (post-5C)

Bottom region:
- ~2288-4350: `pickLead` (~2060 lines) — leader heuristics
- ~4350-6790: `pickFollow` (~2440 lines) — follower heuristics
- ~6790-7185: `PickAKA` + `PickAKANoise` + `PickPlay` dispatch
- ~7185-7745: `PickMelds`
- ~7745-7945: `PickDouble`/`PickTriple`/`PickFour`/`PickGahwa` (escalation)
- ~7945-8070: `PickPreempt`/`PickOvercall`/`PickKawesh`/`PickTakweesh`/`PickSWA`/`PickSWAResponse`

### What remains in `UI.lua` (4 534 lines)

- Module setup + theme re-binding header (5A) (~50 lines)
- Helpers: `seatAtPos`, `posOfSeat`, `setBackdrop`, `makeCardFace`,
  `setCardSlot`, `makeCardBack`, `makeText`, `makeButton`,
  `setLobbyTooltip`, Arabic-font probe (`arabicAvailable`),
  `SaudiName`, `fadeBanner`, `shortName`
- `buildMain` — the giant frame builder
- `buildTable` / `buildLobby` / `buildActionPanel`
- Renderers: `renderHand`, `renderCenterCards`, `renderBadges`,
  `renderScoreboard`, `renderBanner`, `renderNashrah`, takweesh
  review banner
- Animations: `pulseTurn`, `fadeBanner`
- Setters: `SetCardStyle`, `SetFeltTheme`, `SetTheme`,
  `GetCardStyles`, etc.

### What remains in `Net.lua` (6 205 lines)

- Module setup + `broadcastWithRetry` helper (Batch 2)
- Send* helpers for every protocol message (17 retry sites + 1 inline
  retry in `_HostResolveOvercall` deferred)
- `OnAddonMessage` dispatcher + per-tag handlers
- AFK auto-pass / auto-preempt-pass routers
- `MaybeRunBot` host bot dispatch + `runBot` retry timer

### What remains in `State.lua` (2 464 lines)

- `S.s` table init + `Reset`
- Phase transitions
- `HostDealInitial`
- `ApplyTrickEnd` / `ApplyResyncSnapshot`
- `GetLegalPlays`
- `MeldVerdict`
- `PreemptEligibleSeats`
- `IsSeatBot` / `LobbyFull`
- SaveSession debounce frame
- Sound cue arming hooks

---

## 4. Test And Source-Pin Health

| Suite | Count |
|---|---|
| `tests/test_rules.lua` | (part of the 1150) |
| `tests/test_state_bot.lua` | 798 of the 1150 |
| `tests/test_botmaster.lua` | 23 of the 1150 |
| **Combined** | **1150 / 1150 pass** |

Per `python tests/run.py` and standalone reruns of all five lupa-
runnable smokes after Batch 5C:

| Standalone smoke | Result |
|---|---|
| `tests/test_H1_pin_J9_trump.lua` | 11 passed |
| `tests/test_H7_sun_shortest_lead.lua` | 9 passed (anchor swap clean) |
| `tests/test_numworlds_scaling.lua` | 21 passed |
| `tests/test_v0.5_traced_game.lua` | 10 passed |
| `tests/test_bel_decision_quality.lua` | full 1000×3 sweep clean |

These five smokes are worth keeping in the Codex review workflow
because:
- `test_H1` + `test_H7` source-patch `Bot.lua` in memory before
  loading → they're the canaries for accidental Bot.lua structural
  changes (anchors, function ordering).
- `test_numworlds_scaling` patches `BotMaster.lua` numWorlds
  scaling → canary for BotMaster sampler structure.
- `test_v0.5_traced_game` is the per-trick replay against a pinned
  game tape → canary for any picker behavior drift.
- `test_bel_decision_quality` runs the 1000-hand sweep → canary for
  the Bel-decision heuristic (and for the math.random shim fixed in
  `08473ce`).

### Remaining source-pin clusters (test_state_bot.lua)

Approximate counts of literal source-pin asserts:

| Helper | Count | Risk if file owner changes |
|---|---|---|
| `botSrc:find(...)` | **110** | High — most pinned strings live inside Bot.lua pickLead / pickFollow / PickBid / PickPreempt internals |
| `uiSrc:find(...)` | **27** | Low — most have already been retargeted through 5A (e.g. AJ.9a/b/c) |
| `netSrc:find(...)` | **64** | Medium — pins inside the broadcastWithRetry call sites + SendPreempt guards; retained for migration coverage from Batch 4A |
| `stateSrc:find(...)` | **25** | Low — pins inside ApplyResyncSnapshot / phase guards |
| `primSrc:find(...)` | **7** | (NEW in 5C) AN.1a/b + AN.8a/b/c on Bot/PlayPrimitives.lua; AJ.9e adds 30+ more under the same source |

Pins moved in 5A/5B/5C:
- **5A**: AJ.9a/b (deck name renames) now scan `UI.lua + UI/Themes.lua` concatenated; new AJ.9c asserts `.toc` order.
- **5B**: New AJ.9d block (8 asserts) scans `Bot/Tiers.lua` for the 5 tier definitions + `.toc` order.
- **5C**: New AJ.9e block (33 asserts) scans `Bot/PlayPrimitives.lua` for 10 local function defs, 10 `Primitives.X = ...` exports, 3 `.toc` order pins, 10 Bot.lua re-binding header asserts. AN.1a/b and AN.8a/b/c retargeted from Bot.lua to Bot/PlayPrimitives.lua (Codex's correction).

### Remaining source-pin hot-spots that block future refactors

These would break if their owning Bot.lua section moved without
updating the pin:
- Section AA-AK in test_state_bot.lua: ~134 `botSrc:find` calls
  concentrated on `Bot.PickBid` internals, hokmMinShape, sunStrength,
  withBidcard, `local function pickLead`, `local function pickFollow`,
  TAKWEESH_RATE_BY_TRICK, `if not hand or #hand == 0` (PickSWA guard),
  `function Bot.PickSWAResponse`, `function Bot.PickAKA` — i.e., every
  major picker entry point.
- AO/AP/AQ sections also pin UI.lua segments (banner / review /
  nashrahPanel renderers).

Any future Bot.lua picker extraction must update these pins (the AJ.9e
pattern from 5C is the template).

---

## 5. Remaining Risk Register

### 5.1 Deferred network/state retry areas (from Batch 4 design)

| Area | Status | Risk |
|---|---|---|
| Batch 4B — Skip/preempt rung retries with new state | Deferred | MEDIUM — needs new idempotence keys per-rung |
| Batch 4C — Outcome / review broadcast retries | Deferred | MEDIUM — needs new `s.outcomeAck` field (state addition) |
| Batch 4D — Preempt window-open frame retry | Deferred | LOW-MEDIUM — needs a host-side "open" frame separate from the existing `SendPreempt` |

These all require state-schema additions, not just helper extraction —
hence deferred from the cleanup pass.

### 5.2 Bot memory/style ledger extraction (`Bot/Memory.lua`)

**Risk: HIGH.** Reasons:
- `Bot._memory`, `Bot._partnerStyle`, `Bot._inRollout` are read by
  `BotMaster.lua` directly (4+ reads of `B.Bot._memory[...]` in the
  sampleConsistentDeal + rolloutValue paths).
- Extraction would either keep the cross-module table-read coupling
  (in which case the extraction is purely cosmetic) or require a new
  API contract (e.g. `B.Bot.Memory.Get(seat)`) — which is a real
  refactor, not a cleanup.
- 200+ writers to these tables across pickLead / pickFollow /
  PickPlay / OnPlayObserved.

**Prerequisite tests:** behavioral tests covering BotMaster sampler
behavior under varied memory states (currently exercised via
test_botmaster.lua but at low fidelity).

### 5.3 Bot escalation extraction (`Bot/Escalation.lua`)

**Risk: MEDIUM.** Functions: `PickDouble`, `PickTriple`, `PickFour`,
`PickGahwa`, `PickPreempt`, `PickOvercall`, `PickKawesh`,
`PickTakweesh`. ~600 lines total, lines ~7409-8160.

Reasons:
- Tightly coupled to round-state (contract, doubled/tripled/foured/
  gahwa flags, `s.preemptEligible`, `s.takweeshActive`, etc.).
- Many cross-call sites: `PickFour` reads `PickTriple` decision
  signals via state, and the preempt path reads contract booleans
  set by Net.lua. Direct call coupling is minimal but state-read
  coupling is heavy.
- Source pins: AA-AK sections pin every escalation function's name
  and several internal markers (TAKWEESH_RATE_BY_TRICK, kawesh shape
  pins, etc.). At least ~25-30 pins would need retargeting.

**Prerequisite tests:** behavioral coverage of escalation under
×2/×3/×4/Gahwa contract states. Currently covered by AA-AK but
those are heavily source-pinned — Batch 3-style conversion to
behavioral would be a useful prep step.

### 5.4 Bot bidding extraction (`Bot/Bidding.lua`)

**Risk: MEDIUM.** Functions: `OpponentUrgency`, `PickBid`, plus the
internal helpers `sunStrength`, `hokmMinShape`, `withBidcard`,
beloteBypassQualifies, all bid-candidate evaluation closures. ~1300
lines, ~lines 1565-2275.

Reasons:
- Self-contained logically (no cross-module callers except
  `Net.MaybeRunBot` calls `Bot.PickBid`).
- Heavy internal helper closures: `sunStrength`, `hokmMinShape`,
  `withBidcard` are all `local function` and called only from
  `PickBid`. They'd all move together.
- Reads `Bot._memory` for opp-urgency math (cross-coupling).
- ~15-20 source pins in AA, AB, AC, AG sections pin `Bot.PickBid`,
  `hokmMinShape`, `sunStrength`, `withBidcard`, and constants like
  `TH_HOKM_R1_BASE` — all retargetable but the pin update is wider
  than 5B/5C.

**Prerequisite tests:** behavioral tests covering PickBid output for
canonical hand fixtures across all 4 tiers. Currently exercised
heavily but source-pinned; consider a Batch 3-style conversion of
the hokmMinShape / sunStrength pins before extraction.

### 5.5 UI renderer extraction

**Risk: HIGH.** Reasons:
- Shared upvalues `f`, `seatBadges`, `centerCards`, `statusText`,
  `lobbyPanel`, `tablePanel`, `cardBackEntries` close over every
  renderer. Extraction needs either (a) explicit `.frame` field
  plumbing, or (b) module-table boxing of all shared frames.
- WoW-API density: 73 `SetScript`, 38 `CreateFrame`, 10 `SetTexture`
  — taint propagation risk if any closure swap touches a hot path.
- 27 `uiSrc:find` pins concentrated on banner / nashrahPanel /
  takweesh review renderers.

**Prerequisite work:** Decide between the `.frame` plumbing
approach vs the `U.Frames = {...}` boxed-table approach before any
extraction. Either way it's a real refactor, not a cleanup.

### 5.6 Tool/test quirks (known)

- The `math.random` shim in `test_bel_decision_quality.lua` was
  fixed in `08473ce`. The same arity-dispatch shim shape may be
  needed in any future test that freezes `math.random` while
  exercising Bot.lua code that calls 0-arg / 1-arg forms.
- Lupa-vs-Lua line-ending: all Lua files have CRLF on this
  Windows checkout; `git config core.autocrlf` handles the
  in-repo conversion. New file creations need explicit `\r\n` or
  rely on git's filter — current pattern works.
- `tests/test_H7_sun_shortest_lead.lua` source-patches Bot.lua. Its
  anchor (`\nlocal function pickLead`) is now the canary for
  pickLead's presence at file-scope; deferring pickLead extraction
  indefinitely keeps the anchor stable.

---

## 6. Recommended Next Work

**Do NOT immediately implement Batch 5D.** First write a design pass
for whichever extraction is chosen next — same pattern as 5A/5B/5C.

### Ranked design-pass candidates

| Rank | Candidate | Expected risk | Prerequisite tests | Notes |
|---|---|---|---|---|
| 1 | **Source-pin-to-behavioral conversion (Batch 3-style prep)** | LOW | none | Pick 3-6 high-value pins from AA-AK (e.g. `botSrc:find("function Bot%.PickBid")`, `hokmMinShape`, `sunStrength`, `TAKWEESH_RATE_BY_TRICK`) and convert each to a behavioral assert. Reduces the pin debt that blocks every other extraction below. Mirrors Batch 3 exactly. |
| 2 | **`Bot/Bidding.lua`** (`PickBid` + helpers) | MEDIUM | behavioral coverage of canonical hand fixtures already exists; minor source-pin debt to retire first (#1) | Self-contained surface; one external caller (`Net.MaybeRunBot`). Internal helpers all close together. Wider source-pin update than 5B/5C but mechanical. |
| 3 | **`Bot/Escalation.lua`** (Pick{Double,Triple,Four,Gahwa,Preempt,Overcall,Kawesh,Takweesh}) | MEDIUM-HIGH | behavioral coverage of ×2/×3/×4/Gahwa contracts already exists; source-pin debt for TAKWEESH_RATE_BY_TRICK + kawesh-shape pins should be converted first (#1) | Tightly state-coupled but no cross-module API changes needed (all already on `Bot.*` public surface). |
| 4 | **`Bot/Memory.lua`** (memory + style ledgers) | HIGH | needs new BotMaster API contract design; behavioral tests for sampler under varied memory states would help | Genuine refactor, not cleanup — defer until BotMaster sampler redesign is on the table. |
| 5 | **UI renderer extraction** | HIGH | needs prior decision on `.frame` plumbing vs `U.Frames` boxing | Real refactor; taint risk. Defer until UI work is the priority (e.g. mobile-friendly resize, screen-share-friendly layout, or color-blind palette pass). |
| 6 | **Net.lua / State.lua decomposition** | HIGH | needs protocol/state redesign (4B/4C/4D direction) | Defer; not a clean cleanup target. |

**My recommendation: do Rank 1 next.** A Batch 3-style source-pin
conversion of 3-6 high-value pins is the lowest-risk way to reduce
the friction that Bot/Bidding.lua and Bot/Escalation.lua extractions
will face. It also leaves an obvious off-ramp: if a behavioral
conversion turns up unexpected coupling, the rest of the cleanup
agenda can pause without committing to an extraction.

### Why not immediate 5D?

5A through 5C established the `<Module>/<Subsystem>.lua` extraction
pattern and moved 694 non-blank lines (UI/Themes 247 + Bot/Tiers 75
+ Bot/PlayPrimitives 372) out of the two elephants. The remaining
elephants (`Bot.lua` 7 875, `Net.lua` 6 205, `UI.lua` 4 534) all
contain state-coupled logic where the next reduction step needs a
deliberate design choice (e.g., does `Bot/Bidding.lua` re-bind via
UI.lua-style locals header or expose only on `Bot.PickBid` and let
`_memory` reads stay opaque?). That's a design-pass question, not an
"execute the next batch" question.

---

## 7. Release Guidance

**No release tag for v3.2.0 yet.** Justification:

- The cleanup batches (1, 2, 3, 4A, 5A, 5B, 5C) are all internal
  refactors and test hardening. No gameplay change. No new bot
  behavior. No new protocol message. No new UI element. No new
  saved variable. No bug fix that a player would notice.
- v3.1.14 remains the last shipped CurseForge release (Codex delta
  review for SWA + escalation retries + the BALOOT button).
- BigWigsMods packager runs on tag push to CurseForge project ID
  1529200 (per `WHEREDNGN.toc`'s `X-Curse-Project-ID`). Tagging
  v3.2.0 now would publish an identical-feeling addon with a bumped
  version string — confusing for users.

### What would justify v3.2.0?

Any of the following would constitute a user-visible reason to ship:

1. **Gameplay change** — e.g., closing an audited deferral (4B/4C/4D
   retry paths), a new escalation heuristic, a new bot tier, or a
   Saudi-rule correctness fix surfaced by ongoing video review.
2. **UI change** — a new card-style addition, a new felt theme,
   colorblind palette refinements, a new banner mode, scoreboard
   redesign, Arabic-glyph rendering fix, etc.
3. **Protocol bump** — any new addon-channel message that affects
   resync compatibility, or a new state field that requires
   `ApplyResyncSnapshot` migration.
4. **Saved-variable migration** — a new opt-in default, a renamed
   field, or a settings panel addition.
5. **Bundle change** — a new asset (sound, card-back texture, font)
   that ships with the .toc.

Until one of (1)-(5) lands, the version stays at v3.1.14 on
CurseForge and "v3.2.0" remains the internal designation for the
cleanup wave that produced this checkpoint.

---

## Stopping point

Working tree clean. Awaiting Codex review of this checkpoint and the
next instruction (most likely a design-pass prompt for either
"Batch 6 source-pin-to-behavioral prep" or "Batch 5D Bot/Bidding.lua
design pass").
