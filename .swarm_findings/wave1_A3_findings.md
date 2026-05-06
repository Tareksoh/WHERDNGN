# Wave 1 – Cluster A3 – Findings: Memory & State Integrity (Group 1)

Auditor: swarm agent A3-memory-state-1
Codebase: C:/CLAUDE/WHEREDNGN v0.4.4
Scope file: wave1_A3_memory_state_1_prompt.md (5 angles)

---

## A-79 — styleTrumpTempo and styleBelTendency: computed but never consumed

**VERDICT: BUG-CONFIRMED (dead code)**

**Citations:**
- `Bot.lua:181-196` — `local function styleBelTendency(seat)` and `local function styleTrumpTempo(seat)` definitions
- `Bot.lua:126-172` — `Bot._partnerStyle` / `Bot.OnEscalation` maintain the counters those functions read
- No call site found anywhere in `Bot.lua` or `Net.lua` or any other file in the project

**Evidence:**
Both `styleBelTendency` and `styleTrumpTempo` are declared as `local function` inside `Bot.lua`. A grep across the entire codebase (`Bot.lua`, `Net.lua`, `BotMaster.lua`, `Rules.lua`, `State.lua`) reveals zero call sites beyond the definitions themselves. The comment block at `Bot.lua:177-180` explicitly acknowledges this: "Currently unused by the picker code; reserved for future M3lm-Plus heuristics." The `Bot._partnerStyle` ledger that feeds these functions IS actively maintained — `OnEscalation` increments `bels`, `triples`, `fours`, `gahwas` per-rung, and `OnPlayObserved` increments `trumpEarly`/`trumpLate` — so the write side is live. However, no decision branch in `PickDouble`, `PickTriple`, `PickFour`, `PickGahwa`, `pickLead`, or `pickFollow` ever calls either function. The style data is collected for free but the intended M3lm-tier behavioral output (bias trump-counting against partners known to leak early, escalation calibration for Bel-prone seats) never fires. This is dead code constituting silent waste of maintained state.

**Fix recommendation:**
No behavioral change is needed immediately. Add a `-- TODO(M3lm-Plus): wire styleBelTendency / styleTrumpTempo` comment at the call sites in `pickLead` and `escalationStrength` where the influence would logically plug in. If the feature is not planned, remove both functions and the associated comment block at lines 177-196 to reduce maintenance surface. Do NOT remove the ledger maintenance in `OnEscalation` / `OnPlayObserved` — that would be a separate bigger refactor.

---

## A-80 — partnerBidBonus: reads S.s.bids[partner] which may be nil in R2

**VERDICT: NOT-CONFIRMED (nil is handled correctly, but semantic accuracy is a warning)**

**Citations:**
- `Bot.lua:410-427` — `partnerBidBonus` definition
- `Bot.lua:414-415` — `local b = S.s.bids[partner]; if not b then return 0 end`
- `State.lua:1503-1504` — `s.bids = {}` at `S.HostBeginRound2()` — bids table is reset to empty at round 2
- `State.lua:830-838` — `S.ApplyBid` sets `s.bids[seat] = bid` for each bid cast

**Evidence:**
`partnerBidBonus` is called from `PickDouble`, `PickTriple`, `PickFour`, `PickGahwa`, and `escalationStrength`. All of these are invoked after the deal contract is finalized — meaning after bidding is complete for both rounds. By that time `S.s.bids` is a populated table and the partner's bid is present (or genuinely nil if they passed, handled by the `if not b then return 0 end` guard at line 415). There is no crash path. The table-reset at `State.lua:1504` (`s.bids = {}`) happens at `HostBeginRound2()`, before any round-2 bids are cast, so when escalation decisions are made the table already reflects the winning round's bids. The comment "reads FINAL bid" vs "last bid made" is also fine: `ApplyBid` is idempotent (line 837, same-bid dedup) and the contract is only resolved after all four seats have bid, so the table holds the complete winning-round bid state. One semantic caveat: if a bot is making an escalation decision in round 2 before partner has bid in round 2, partner's entry will be nil and the function correctly returns 0. This is the intended neutral-default behavior, not a bug.

**Fix recommendation:**
No code change required. The nil guard at line 415 is correct and sufficient. Add a brief inline comment to clarify that `s.bids` reflects the current bidding round only (reset per round), to prevent future confusion about which round's bids are being read during a mid-round escalation decision that fires before all four round-2 bids are in.

---

## A-81 — Bot._memory nil guard in all accessors

**VERDICT: BUG-CONFIRMED (two unguarded ApplyPlay paths bypass OnPlayObserved entirely)**

**Citations:**
- `Net.lua:1065-1066` — `_OnPlay` calls `OnPlayObserved` after `ApplyPlay` (guarded)
- `Net.lua:1609-1610` — `N.LocalPlay` calls `OnPlayObserved` after `ApplyPlay` (guarded)
- `Net.lua:3360-3362` — Bot play path in `MaybeRunBot` calls `ApplyPlay` then `N.SendPlay` but does NOT call `OnPlayObserved`
- `Net.lua:2775-2777` — AFK timeout path (`_HostTurnTimeout`) calls `ApplyPlay` but does NOT call `OnPlayObserved`
- `Net.lua:3394-3396` — Bot error-recovery fallback inside MaybeRunBot calls `ApplyPlay` but does NOT call `OnPlayObserved`
- `Bot.lua:201` — `OnPlayObserved` has the entry guard `if not Bot._memory then Bot.ResetMemory() end`

**Evidence:**
`Bot._memory` itself is never nil-dereferenced at the point of access because `OnPlayObserved` initializes it on first call (line 201). However, the deeper bug is that `OnPlayObserved` is never reached for three code paths: (1) the bot play dispatch in `MaybeRunBot` (lines 3360-3362) calls `S.ApplyPlay` then `N.SendPlay` then `N._HostStepPlay` — no `OnPlayObserved` call; (2) the AFK timeout path `_HostTurnTimeout` (lines 2775-2777) takes the same shortcut; (3) the bot error-recovery fallback (lines 3394-3396) repeats the omission. Only `_OnPlay` (the handler for REMOTE plays received over the network) and `N.LocalPlay` (the local human player's card commit) call `OnPlayObserved`. This means bot plays and human AFK-auto-plays are invisible to `Bot._memory`: void inference, `firstDiscard` signals, and `trumpEarly`/`trumpLate` style counters are never updated for cards played by bots or timed-out humans on the host side. In a 4-bot game every single play is dark to the memory system, making the entire Fzloky void-inference and signal logic a no-op. Note: `_OnPlay`'s loop-back path (the sender is the host itself, handled by the `fromSelf` guard returning early at line 1034) confirms that bot plays do NOT feed back through `_OnPlay` — so there is no indirect path that compensates.

**Fix recommendation:**
After each `S.ApplyPlay(seat, card)` in the three missing paths — the bot play timer (around line 3360), the AFK timeout handler (around line 2775), and the bot error-recovery fallback (around line 3394) — add the same two-line pattern already used in `_OnPlay` and `LocalPlay`: capture `leadBefore = S.s.trick and S.s.trick.leadSuit or nil` BEFORE `ApplyPlay`, then call `if B.Bot and B.Bot.OnPlayObserved then B.Bot.OnPlayObserved(seat, card, leadBefore) end` after it. The `leadBefore` capture must be before `ApplyPlay` because `ApplyPlay` advances `trick.leadSuit` for the card just played.

---

## A-84 — OnPlayObserved call scope: host-only, all 4 seats

**VERDICT: BUG-CONFIRMED (same root cause as A-81; bot and AFK plays are excluded)**

**Citations:**
- `Bot.lua:1` comment: "All decisions are pure functions of the host's view of state… Driven from Net.lua's MaybeRunBot when it's a bot's turn."
- `Net.lua:1065-1066` — `OnPlayObserved` is called in `_OnPlay` (remote plays only)
- `Net.lua:1609-1610` — `OnPlayObserved` is called in `N.LocalPlay` (local human plays only)
- `Net.lua:3360-3362` — Bot plays via `MaybeRunBot` omit the call
- `Net.lua:2775-2777` — AFK auto-play omits the call

**Evidence:**
`_OnPlay` handles MSG_PLAY messages received from the addon channel. The `fromSelf` guard at line 1034 (`if fromSelf(sender) then return end`) means that when the HOST (who runs the bots) plays a card — either as a bot or as the local human seat — the message loops back but `_OnPlay` exits immediately. For the local human, `N.LocalPlay` (line 1607-1613) compensates with a direct `OnPlayObserved` call. For bots, there is NO compensating call. Bot plays go through `MaybeRunBot`'s timer callback which calls `S.ApplyPlay` + `N.SendPlay` + `N._HostStepPlay` only. `N.SendPlay` broadcasts the card to peers; peers receive and process it via their own `_OnPlay`, but the HOST never calls `OnPlayObserved` for that card. The result is that `Bot._memory` is only populated for cards played by REMOTE human players (received via `_OnPlay`) and the LOCAL human player (via `LocalPlay`). All bot seat plays and all AFK-timeout auto-plays are silently omitted. In a 4-bot game the memory remains at its `emptyMemory()` state for the entire round.

**Fix recommendation:**
Identical to A-81. The fix is at the play-dispatch level, not inside `OnPlayObserved`. The three missing call sites in `MaybeRunBot` (bot play), `_HostTurnTimeout` (AFK play), and `MaybeRunBot`'s error recovery path each need `leadBefore` capture before `ApplyPlay` and the `OnPlayObserved` call after.

---

## A-85 — Void inference rollback: firstDiscard reverted but void inference stands

**VERDICT: NOT-CONFIRMED (behavior is correct by design)**

**Citations:**
- `Bot.lua:217-225` — void inference: `mem.void[leadSuit] = true` when off-suit card is played legally
- `Bot.lua:262-269` — trump-ruff rollback: `mem.firstDiscard = nil` when the off-suit play was a trump ruff
- No rollback of `mem.void[leadSuit]` in either block

**Evidence:**
The rollback block at lines 262-269 triggers when: (a) the play was not illegal, (b) there was a lead suit, (c) the played card was off-suit, (d) the contract is Hokm, (e) the played card is trump (i.e., it was a ruff). In this scenario, `mem.void[leadSuit]` was set to `true` at line 218 before the rollback block is reached, and it is NOT reset. This is intentional and correct: a seat that ruffs with trump IS genuinely void in the lead suit — that is the precondition for the ruff being legal (per Saudi Hokm rules, a player who can follow suit must do so; a trump ruff is only legal when void in the lead suit). Therefore `mem.void[leadSuit] = true` is an accurate inference that should stand. What the rollback correctly undoes is `mem.firstDiscard`, which was set to the ruff card's rank and suit. A trump ruff is a forced/opportunistic play rather than a "suit preference signal" in the Fzloky model (the seat had no choice of WHICH off-suit card to play — they had to play trump). Setting `firstDiscard` to the trump card would poison the Fzloky signal logic (e.g., a high trump ruff would spuriously look like a "lead hearts" signal). The asymmetric treatment — void inference stands, firstDiscard is reverted — is the correct and consistent behavior. The comment at lines 257-269 documents this reasoning explicitly.

**Fix recommendation:**
No code change required. The current behavior is correct. For clarity, add a one-line comment at the void-inference site (around line 218) noting that the inference is NOT rolled back by the trump-ruff case below, to make the intentional asymmetry explicit at the point of the void write rather than only at the rollback block.

---

## Summary Table

| Angle | Verdict | Severity |
|-------|---------|----------|
| A-79 (styleTrumpTempo / styleBelTendency dead code) | BUG-CONFIRMED | info |
| A-80 (partnerBidBonus nil in R2) | NOT-CONFIRMED | — |
| A-81 (Bot._memory nil guard / unguarded ApplyPlay paths) | BUG-CONFIRMED | critical |
| A-84 (OnPlayObserved scope: bot plays missing) | BUG-CONFIRMED | critical |
| A-85 (void inference rollback asymmetry) | NOT-CONFIRMED | — |

**Critical bugs A-81 and A-84 are the same root cause**: `OnPlayObserved` is missing from the bot play dispatch in `MaybeRunBot` (Net.lua ~3360), the AFK timeout path `_HostTurnTimeout` (Net.lua ~2775), and the bot error-recovery fallback (Net.lua ~3394). In practice this means all card-memory features (void inference, Fzloky suit-preference signals, M3lm trump-tempo tracking) are silently inert for bot plays and AFK auto-plays.
