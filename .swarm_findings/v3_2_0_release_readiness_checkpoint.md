# v3.2.0 Release-Readiness Checkpoint

Status: design / audit doc. No runtime code or test changes. Working
tree contains only this doc.

## 1. Current State

| Field | Value |
|---|---|
| `main` commit | `fa80322` — docs(batch9): normalize whitespace + correct harness counts (+30 / 1219) |
| `origin/main` | in sync at `fa80322` |
| Latest shipped CurseForge tag | **v3.1.14** (commit `c1c624f`) |
| Working tree | clean |
| Full harness | **1219 / 1219 pass** |
| Release tag created during cleanup wave | **none** |
| Bot.lua line count | **6 078 raw** (8 428 pre-cleanup → 6 078 now; −2 350, −28%) |
| Total addon Lua (raw) | **28 211 lines** across 19 files |

---

## 2. Cleanup Wave Summary (Batches 1-9)

| Batch | Commits | Outcome | Lines moved out of Bot.lua |
|---|---|---|---|
| 1 | `fde6aea` | Remove dead helpers + extract skip senders (`SendSkipDouble/Triple/Four/Gahwa`) into Net.lua helpers | 0 (Net.lua + tests only) |
| 2 | `c2e0a99` | Extract `broadcastWithRetry(frame, guardFn)` retry helper across 17 broadcast call sites | 0 (Net.lua refactor) |
| 3 | `eb66339` | Convert 4 source-pinned assertions to behavioral tests | 0 (tests only) |
| 4A | `e1282cf` | Skip/preempt retry coverage; critical two-branch `SendPreempt` guard for LocalPreempt vs host-bot ordering | 0 (Net.lua + tests) |
| 5A | `9ef3178` | Extract `UI/Themes.lua` (CARD_STYLES, FELT_THEMES, COL palette, theme helpers) | 0 (UI.lua refactor) |
| 5B | `1d9cdb2` | Extract `Bot/Tiers.lua` (5 tier predicates: IsAdvanced/IsM3lm/IsFzloky/IsSaudiMaster/IsBotSeat) | ~60 |
| 5C | `51c3be9` | Extract `Bot/PlayPrimitives.lua` (10 helpers + tahreebClassify) | ~330 |
| 6 | `f68ed1d` | Convert AJ.10-AJ.13 source pins to behavioral (PickSWA guards, PickAKA trick-1, Belote K+Q escape, Sun-no-rungs) | 0 (tests only) |
| 7 | `a49a0b6` | Convert AJ.14 (PickBid 2-Ace Sun bonus) + AJ.15 (PickOvercall void-trump bonus) to behavioral | 0 (tests only) |
| 8 | `c699812` | Extract `Bot/Bidding.lua` (15 helpers + Bot.PickBid + Bot.PickPreempt + Bot.PickOvercall + Bot.OpponentUrgency) | ~1 400 |
| 9 | `fd31215` | Extract `Bot/Escalation.lua` (3 helpers + 4 jitter consts + Bot.PickDouble/Triple/Four/Gahwa) | ~595 |
| **Total** | | | **~2 385 lines moved out** |

### Modules created during cleanup wave

| Module | Raw lines | Non-blank | Purpose |
|---|---|---|---|
| `UI/Themes.lua` | 261 | ~245 | Card/felt themes, COL palette, theme helpers |
| `Bot/Tiers.lua` | 81 | ~75 | Tier-detection predicates |
| `Bot/PlayPrimitives.lua` | 385 | ~372 | Card-ranking + legality + Tahreeb classifier |
| `Bot/Bidding.lua` | 1 534 | ~1 460 | Bid-strength math + PickBid/Preempt/Overcall |
| `Bot/Escalation.lua` | 682 | ~660 | 4-rung escalation chain + helpers |
| **Total NEW** | **2 943** | **~2 812** | |

### Bot.lua before/after

| Metric | Pre-cleanup | Post-Batch-9 | Δ |
|---|---|---|---|
| Raw lines | ~8 428 | 6 078 | −2 350 (−28%) |
| Non-blank lines | ~7 875 | ~5 460 (estimate) | −2 415 (−31%) |
| Functions defined | ~67 | ~33 | −34 |

Bot.lua's remaining contents are dominated by two functions: `pickLead` (~1 925 lines) and `pickFollow` (~2 385 lines), together ~71% of the file.

---

## 3. Test Health

### Full harness
- **1219 / 1219 pass** on merged main at `fa80322`.
- Three test runners (rules / state_bot / botmaster) all green.
- Sub-totals:
  - `tests/test_rules.lua`: 296 passed
  - `tests/test_state_bot.lua`: 900 passed
  - `tests/test_botmaster.lua`: 23 passed

### Standalone smokes (recommended for any release-prep dry-run)
| Smoke | Last result | Reason worth keeping |
|---|---|---|
| `tests/test_H1_pin_J9_trump.lua` | 11/0 | Source-patches Bot.lua in memory + pins J/9 trump inference |
| `tests/test_H7_sun_shortest_lead.lua` | 9/0 | Source-patches Bot.lua + carries the `\nlocal function pickLead` anchor — canary for any Bot.lua structural change |
| `tests/test_numworlds_scaling.lua` | 21/0 | BotMaster ISMCTS numWorlds scaling pin |
| `tests/test_v0.5_traced_game.lua` | 10/0 | Per-trick replay against pinned game tape |
| `tests/test_bel_decision_quality.lua` | 1000×3 sweep clean | Bel-decision F1 calibration (also covers the `math.random` arity shim fixed in commit `08473ce`) |

### Known flaky / expensive tests
- **None known flaky** in the current run. All five standalone smokes pass deterministically post-Batch 9.
- **Expensive**: `test_bel_decision_quality.lua` (1000-hand × 3-threshold sweep, ~6-10 seconds) — informational only, never blocks the harness.
- **Jitter-sensitive**: AC.6, AJ.12, AJ.14, AK.7 each install a `math.random` arity-aware shim. All four pass deterministically; the shim shape is consistent across them.

### Lupa availability assumption
The Python test runner (`tests/run.py`) uses `lupa` to host Lua 5.5 with Lua 5.1 compatibility. The codebase is **Lua 5.1 target** (WoW client). No CI-side `lupa` install is currently part of the release pipeline (BigWigsMods packager runs Lua-free); tests are dev-side only.

---

## 4. Source-Pin Health

### Current pin distribution in `tests/test_state_bot.lua`

Counted by `io.open(WHEREDNGN_TESTS_ROOT .. "/<file>"):read("*a")` call sites. Each call site typically guards a `do ... end` block with 1-4 assertions:

| Target file | Pin call sites |
|---|---|
| `Bot.lua` | **44** |
| `Net.lua` | **38** |
| `Bot/Bidding.lua` | **20** (newly retargeted in Batch 8) |
| `State.lua` | 14 |
| `BotMaster.lua` | 10 |
| `UI.lua` | 8 |
| `Bot/Escalation.lua` | **8** (newly retargeted in Batch 9) |
| `WHEREDNGN.toc` | 5 (Batch 5A/5B/5C/8/9 toc-order pins) |
| `Slash.lua` | 4 |
| `Bot/PlayPrimitives.lua` | 3 (Batch 5C/6 retargets) |
| `Rules.lua` | 2 |
| `Constants.lua` | 1 |
| `Sound.lua` | 1 |
| `WHEREDNGN.lua` | 1 |
| `UI/Themes.lua` | 1 (Batch 5A) |
| `Bot/Tiers.lua` | 1 (Batch 5B) |
| `docs/strategy/signals.md` | 1 (doc-validity pin) |
| `.pkgmeta` | 1 |
| **Total `io.open` call sites** | **163** |

Underlying `assertTrue`/`assertEq` calls inside those do-blocks total ~600-700 (rough estimate from grepping `assertTrue\|assertEq` near `botSrc:find`).

### Highest-value remaining source pins to convert (future batches)

| Pin | File | Why convert |
|---|---|---|
| **AH.3** (PickTriple floor cap) | Bot/Escalation.lua | Codex's Batch 7 standing note: AK.7 behavioral is "weak floor-cap coverage." A dedicated tight-load-bearing floor-cap fixture would retire the structural pin. |
| **AA.1a / AA.1b** (escalationStrength void/sideAce bonuses) | Bot/Escalation.lua | Reachable via PickDouble/Triple deviation between void-rich and void-free hands. Bonus magnitudes are tied to specific thresholds — calibratable but brittle. |
| **AI.4** (PickDouble bid-history inflection comment) | Bot/Escalation.lua | Pure comment-marker pin. Stays source-only as a discoverability anchor. |
| **AD.7a/b** (PickDouble eltrace diagnostic) | Bot/Escalation.lua | Diagnostic helper; stays source-only. |
| **AI.1 / AI.2 / AI.5** (pickFollow comment markers) | Bot.lua | Pure comment markers in pickLead/pickFollow — discoverability anchors. Stays source-only. |

### Pins that should stay source-only permanently

| Category | Examples | Why |
|---|---|---|
| Diagnostic helper presence | R.2 (PickBid btrace), AD.7a/b (PickDouble eltrace) | Debug-mode wiring; converting would require capturing print output. No behavior risk. |
| Comment / rationale markers | AB.2 / AD.3 (PickGahwa DEAD-2), AI.1 / AI.4 / AI.5 (agent-N markers), AH.7 (Sun-penalty neutralization rationale) | Protect documentation discoverability, not behavior. |
| Ordering assertions | Y.2b (Belote-escape before J-floor), X.2b, Z.2 | Test source-position relationships; behavioral equivalents would add complexity without reducing real risk. |
| Absence assertions | T.2c (old 18-cap removed), Z.5 (inline bidcard append replaced) | Protect against revert; cheap structural checks. |
| Wiring pins | AD.2 (bidderHoldsBidcard wired into trump-J inference), AB.4 (S.Apply* OnEscalation wiring) | Single-line wiring checks. |

---

## 5. Runtime / Packaging Risk Review

### WHEREDNGN.toc load order (current `main` state)

```
## Interface: 120005
## Title: Loot & Baloot
## Notes: 4-player Saudi Baloot card game over party addon channel.
## Author: Tareksoh
## Version: @project-version@
## X-Curse-Project-ID: 1529200
## SavedVariables: WHEREDNGNDB
## X-Category: Miscellaneous

# Foundational - no deps
Log.lua
Constants.lua
Sound.lua

# Pure logic
Cards.lua
Rules.lua

# Game runtime
State.lua
Bot/Tiers.lua
Bot/PlayPrimitives.lua
Bot/Bidding.lua
Bot/Escalation.lua
Bot.lua
BotMaster.lua
Net.lua

# UI
UI/Themes.lua
UI.lua
MinimapIcon.lua

# Entry
WHEREDNGN.lua
Slash.lua

# Easter egg (optional — delete file + this line to remove entirely)
Easter.lua
```

**Sanity checks:**
- ✓ All 5 newly extracted modules (UI/Themes, Bot/Tiers, Bot/PlayPrimitives, Bot/Bidding, Bot/Escalation) are listed in the `.toc`.
- ✓ Load order respects dependencies: Tiers → PlayPrimitives → Bidding → Escalation → Bot.lua. Tier predicates set first; primitives next; Bidding consumes nothing prior; Escalation consumes Bidding's sub-table; Bot.lua's pickLead/pickFollow consumes Primitives + Bidding-via-not-needed (Bidding re-bind was removed in Batch 9).
- ✓ UI/Themes.lua loads before UI.lua so UI.lua's locals-from-`U.Theme` resolve at load time.
- ✓ AJ.9c (Batch 5A) + AJ.9d (5B) + AJ.9e (5C) + AJ.9f (8) + AJ.9g (9) source pins assert load-order — failing any of these would surface in the harness on every CI run.

### Package metadata

`.pkgmeta` correctly excludes development artifacts:
- `.swarm_findings/` (cleanup design docs, audits, this checkpoint doc) — **NOT shipped**
- `tests/` — **NOT shipped**
- `docs/` — **NOT shipped**
- `tools/` — **NOT shipped**
- `cards/_src/`, `cards/_make_*.py`, `cards/_convert.py` — **NOT shipped** (Python build scripts)
- `sounds/_make_*.py` — **NOT shipped**
- `.swarm/`, `.swarm_plan.md`, `.claude-flow/` — **NOT shipped**
- `CLAUDE.md` — **NOT shipped**

`package-as: WHEREDNGN` matches the toc's `X-Curse-Project-ID: 1529200`.

### CurseForge package integrity check

BigWigsMods packager runs on tag push (`v*.*.*` tag → CurseForge auto-publish). The packager:
1. Reads `WHEREDNGN.toc`
2. Substitutes `@project-version@` with the git tag
3. Bundles every file referenced in the toc plus any non-ignored asset
4. Subdirectories (`Bot/`, `UI/`, `cards/`, `sounds/`) are auto-included

**Risk: any new Bot/*.lua or UI/*.lua file omitted from `.toc` would silently be missing from the CurseForge zip.** Mitigated by:
- All 5 newly extracted modules are listed in the toc.
- AJ.9c/d/e/f/g source pins inside `tests/test_state_bot.lua` would fail if a future change forgot to add a new file to the `.toc`.

### Packaging dry-run recommendation

Before tagging v3.2.0 (if cleared to ship), run the BigWigsMods CLI packager locally:

```text
.release/build.bat       # or whatever the dev's local equivalent is
```

Verify:
- `Bot/Tiers.lua`, `Bot/PlayPrimitives.lua`, `Bot/Bidding.lua`, `Bot/Escalation.lua`, `UI/Themes.lua` all appear in the output zip.
- `.swarm_findings/` is NOT in the zip.
- `tests/` is NOT in the zip.
- The Interface version `120005` matches the user's WoW client.

### No known packaging blockers

No CHANGELOG.md update would be needed for a cleanup-only release — but that's also a signal that **there is no user-visible change worth shipping**.

---

## 6. Remaining Code Hotspots

### Bot.lua (6 078 raw lines)

| Region | Lines | Why it's a hotspot |
|---|---|---|
| **`pickLead`** | ~1 039-2 962 (~1 925 lines) | Largest function in the addon. Highly state-coupled: reads `S.s.*`, `Bot._memory`, `Bot._partnerStyle`, contract, trick state, all the play primitives. Extracting it would require deep behavioral-test coverage first. |
| **`pickFollow`** | ~2 963-5 348 (~2 385 lines) | Even bigger than pickLead. Same state-coupling profile. Together pickLead + pickFollow = ~71% of Bot.lua. |
| **Memory ledger** (`Bot._memory` + `emptyMemory` + `Bot.ResetMemory` + `Bot.OnPlayObserved`) | ~100-200 (memory) + ~378-600 (OnPlayObserved + record helpers) | Cross-module: BotMaster.lua reads `B.Bot._memory` directly in 12+ places (sampleConsistentDeal + rolloutValue paths). Moving the table would either keep the cross-module read coupling (cosmetic extraction) or require a new API contract. **Genuine refactor, not cleanup.** |
| **Style ledger** (`Bot._partnerStyle` + `emptyStyle` + `Bot.ResetStyle` + `Bot.OnEscalation` + `Bot.OnRoundEnd` + `styleTrumpTempo`) | ~213-389 | Same coupling pattern as memory ledger. `Bot.OnEscalation` / `Bot.OnRoundEnd` are called from `State.lua`'s `ApplyDouble/Triple/Four/Gahwa/RoundEnd`. |
| **`Bot.PickAKA` + `Bot.PickAKANoise`** | 5 349-5 585 (~237 lines) | Public pickers; Net.lua dispatches via `B.Bot.PickAKA(...)`. Could co-locate with a future Bot/Signals.lua but no obvious benefit. |
| **`Bot.PickPlay` + `Bot.PickMelds`** | 5 586-5 763 (~178 lines) | Top-level play dispatcher; routes to pickLead/pickFollow/BotMaster.PickPlay. |
| **`Bot.PickKawesh` + `Bot.PickTakweesh`** | 5 764-5 891 (~127 lines) | Kawesh = hand-shape declaration; Takweesh = rule-violation observer. Both fire from Net.lua. |
| **`Bot.PickSWA` + `Bot.PickSWAResponse`** | 5 892-6 078 (~187 lines) | End-game claim window. |

### Net.lua (6 430 raw lines)

| Region | Why it's a hotspot |
|---|---|
| Wire-protocol handlers (`_OnBid`, `_OnPlay`, `_OnAKA`, `_OnDouble/Triple/Four/Gahwa`, `_OnSWAReq/Out/Reject`, `_OnPreempt`, `_OnOvercall`, `_OnTakweesh`, etc.) | Largest cluster. Each handler validates fields, dispatches to State.lua's ApplyX, runs MaybeRunBot. Decomposition would split by message family. |
| `broadcastWithRetry` (Batch 2 helper) + 17 retry call sites | Single helper; no further cleanup needed. |
| `MaybeRunBot` host bot dispatch + `runBot` retry timer | Drives every bot decision. Cross-coupled to Bot.* picker functions. |

### State.lua (2 570 raw lines)

- `S.s` global state table, phase transitions, ApplyX functions, SaveSession debounce.
- Less of a refactor target — state-machine code is cohesive.

### UI.lua (4 745 raw lines)

| Region | Why it's a hotspot |
|---|---|
| `buildMain` + frame builders | Giant frame constructor. Shared upvalues (`f`, `seatBadges`, `centerCards`, `tablePanel`, `lobbyPanel`, `cardBackEntries`) block clean extraction. |
| Renderers (`renderHand`, `renderCenterCards`, `renderBadges`, `renderScoreboard`, `renderBanner`, `renderNashrah`, takweesh review banner) | Each renderer closes over the shared upvalues. Extraction needs explicit `.frame` plumbing or a `U.Frames = {...}` boxed-table approach. |

### Batch 10+ candidates ranked by safety / value

| Rank | Candidate | Risk | Estimated payoff |
|---|---|---|---|
| 1 | **Source-pin-to-behavioral conversion** (AH.3 floor cap + 2-3 other high-value pins) | LOW | Lowers structural-pin debt; mirrors Batch 3/6/7 pattern. |
| 2 | **`Bot/SWA.lua`** extraction (`Bot.PickSWA` + `Bot.PickSWAResponse` + helpers) | LOW-MEDIUM | ~200 lines moved. Self-contained surface. No cross-module coupling. |
| 3 | **`Bot/Kawesh.lua`** + **`Bot/Takweesh.lua`** extractions | LOW | Each is ~60-130 lines. PickKawesh just calls `C.IsKaweshHand`; PickTakweesh has the TAKWEESH_RATE_BY_TRICK table + rate-decay logic. |
| 4 | **`Bot/AKA.lua`** extraction (`Bot.PickAKA` + `Bot.PickAKANoise`) | MEDIUM | ~237 lines. PickAKA is lead-only with multiple Tahreeb-classifier reads — coupled to Bot/PlayPrimitives.lua and Bot._partnerStyle. |
| 5 | **Net.lua handler split** | MEDIUM-HIGH | Largest Net.lua-side refactor; would split by message family into Net/Bid.lua, Net/Play.lua, Net/Escalation.lua. ~6 430 lines into ~5-7 files. |
| 6 | **UI.lua frame extraction** | HIGH | Shared upvalues block clean extraction. Needs design decision on `.frame` field plumbing vs `U.Frames` boxed-table. |
| 7 | **`Bot/Memory.lua` + `Bot/Style.lua`** | HIGH | Cross-module table reads from BotMaster make this a real refactor, not cleanup. Genuine API contract design. |
| 8 | **`pickLead` / `pickFollow` extraction** | VERY HIGH | The two elephants. Each is ~2 000+ lines. Out of scope without major preparatory behavioral-test investment. |

---

## 7. Release Recommendation

### Choice: **A — Ready for v3.2.0 packaging after one final full harness + packaging dry-run**, with a strong caveat.

The technical state is release-ready:
- All harness/smoke tests pass.
- Packaging metadata correctly excludes development artifacts.
- All new modules referenced in `.toc` and exercised by source pins.
- Load-order pins (AJ.9c through AJ.9g) catch any `.toc` regression.
- No known regressions or flakiness.

**However**: this entire cleanup wave is **internal refactoring with zero user-visible change**. The post-cleanup checkpoint doc (commit `256dd97`) explicitly noted that v3.2.0 should ship when a gameplay change / UI change / protocol bump / saved-variable migration / bundle change lands. None of those happened in Batches 1-9.

If you ship v3.2.0 right now, the CHANGELOG entry would honestly say:

> v3.2.0 — internal cleanup wave. Bot.lua decomposed into 5 new modules
> (Bot/Tiers.lua, Bot/PlayPrimitives.lua, Bot/Bidding.lua,
> Bot/Escalation.lua, UI/Themes.lua). 2,943 non-blank lines extracted.
> Zero gameplay change. Zero user-visible change. Test count grew
> 1,106 → 1,219.

Players who see "v3.1.14 → v3.2.0" in their CurseForge update will reasonably expect *something* — a bug fix, a new card style, a tier improvement. They'll get nothing. That's a credibility hit on the version bump.

### Reasoning

The honest answer is **A in technical readiness, hold on shipping until a user-visible change rolls up**. There are three paths:

**A.1 — Ship a "Refactor-only" v3.2.0 now.** Pros: clears the version-bump backlog; "fresh slate" for the next gameplay-change tag. Cons: weak release notes; players see no value.

**A.2 — Hold the cleanup until the next gameplay change lands, then ship as v3.2.0.** Pros: user-visible change justifies the version bump; cleanup is bundled "for free." Cons: cleanup sits unshipped indefinitely.

**A.3 — Skip v3.2.0 and bump straight to v3.2.1 for the first gameplay change.** Pros: avoids ever shipping "v3.2.0 cleanup-only"; cleanup retroactively explained as part of v3.2.1. Cons: skipping versions is mildly weird.

**Personal recommendation: A.2** — hold for the next genuine change. The cleanup is on `main`; players get it whenever the next release ships. No urgency to tag now.

If you want to ship anyway for cycle-hygiene reasons (e.g., long-running working directory, future change becomes risky because of stale cleanup-vs-feature interleaving), **A.1 is technically safe**.

### Exact next steps if shipping now (path A.1)

1. Run BigWigsMods packager locally (build dry-run).
2. Verify the resulting zip contains all 5 new modules and excludes `.swarm_findings/` + `tests/` + `docs/`.
3. Compose a CHANGELOG entry honestly framing this as internal cleanup.
4. Run full harness one final time: `python tests/run.py`.
5. Run all 5 standalone smokes.
6. If everything green, tag `v3.2.0` against `main` at the current commit.
7. Push the tag — BigWigsMods packager auto-publishes to CurseForge.

### Exact next steps if holding (path A.2 or A.3)

1. Continue cleanup with Batch 10 design pass OR pause cleanup entirely.
2. Wait for the next gameplay/UI/protocol/savedvar/bundle change to land on `main`.
3. When that change lands, bundle the cleanup wave with it under whichever version (v3.2.0 or v3.2.1) makes sense at that time.

---

## 8. Exact Next-Step Options

### Option 1 — Release-prep branch

Cut a `v3.2.0-release-prep` branch from `main`. On that branch:
- Add a CHANGELOG.md entry framing the release.
- Run packager dry-run; capture output.
- Run all 5 standalone smokes.
- Run a final full harness.
- Push for Codex review.
- On Codex approval, tag `v3.2.0` on `main` at the current commit (NOT the prep branch — the tag goes on the merged content).

**Pros:**
- Catches packaging issues before tagging.
- Gives Codex a final hold-or-ship review point.
- Documents the release in CHANGELOG.

**Cons:**
- Adds 1-2 extra commit cycles before tag.
- If we decide NOT to ship (path A.2/A.3), the prep work is wasted.

### Option 2 — Stabilization / test-only batch

Pick 3-4 high-value remaining source pins (e.g., AH.3 floor cap, AA.1a/b void/sideAce bonuses) and convert to behavioral. Same pattern as Batches 3, 6, 7. No runtime code change.

**Pros:**
- Reduces structural-pin debt before any further extraction.
- LOW risk (test-only changes).
- Sets up future Bot.lua extractions for easier mechanical retargeting.

**Cons:**
- Does NOT improve release-readiness on its own (the harness is already green).
- Doesn't justify a release tag.

### Option 3 — Batch 10 design pass

Continue cleanup with the next safest extraction. Top candidates from §6's ranking:
- **Bot/SWA.lua** (PickSWA + PickSWAResponse, ~200 lines, LOW-MEDIUM risk)
- **Bot/Kawesh.lua** + **Bot/Takweesh.lua** (small self-contained surfaces)
- **Bot/AKA.lua** (~237 lines, MEDIUM risk)

**Pros:**
- Continues the established `Bot/<Subsystem>.lua` pattern.
- Bot.lua continues to shrink.
- Each Batch 10 candidate is self-contained (no cross-module API contract design needed).

**Cons:**
- Diminishing returns: the post-cleanup checkpoint already noted Bot.lua reduction has plateaued at non-elephant slices.
- Does not justify a release tag.
- Increases distance between `main` and the last shipped tag (v3.1.14 → growing commit gap).

---

## Summary

| Item | Value |
|---|---|
| Design doc path | `.swarm_findings/v3_2_0_release_readiness_checkpoint.md` |
| Recommendation | **A (technically ready)** with strong caveat to **hold for next user-visible change** (paths A.2 or A.3). Tag only when CHANGELOG can honestly tell players what they get. |
| Key blockers | **None technical.** Soft blocker: zero user-visible change in Batches 1-9 makes a v3.2.0 release-note entry weak. |
| Working tree status | clean except `.swarm_findings/v3_2_0_release_readiness_checkpoint.md` (untracked) |

Stopping per the prompt. Awaiting next instruction.
