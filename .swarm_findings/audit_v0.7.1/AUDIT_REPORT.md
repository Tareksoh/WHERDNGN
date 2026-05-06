# WHEREDNGN v0.7.2 — Multi-Wave Audit Report

**Codebase HEAD:** v0.7.2 (commit 93b1e9d)
**Audits run:** 73 parallel agents across 5 batches
**Per-agent reports:** `.swarm_findings/audit_v0.7.1/01..73_*.md`
**Verdict:** Solid foundation; **9 real bugs found, 4 of them HIGH severity. 11 documented features missing or incomplete vs decision-trees.md.**

---

## TL;DR — Triage table

| Severity | Count | Items |
|---|---|---|
| **HIGH (functional defect)** | **4** | Sun-overcall race, Game-end Gahwa-loser-keeps-melds, Tie-at-target tiebreaker, ISMCTS pcall granularity |
| **MEDIUM** | **5** | PHASE_OVERCALL pause-blind timer, /reload mid-OVERCALL/SWA soft-lock, ISMCTS desire-table mutation, Bot._partnerStyle wiped on /reload, Belote cancellation declaredBy mismatch |
| **LOW / cosmetic** | **6** | UI banner tick during pause, AFK-pass authorizeSeat rejection, Stale akaCalled cleanup, Late-AKA retroactive flip, _OnResyncRes accepts unsolicited snapshots, WHEREDNGNDB.target type-guard gap |
| **DOC vs CODE drift** | **5** | Glossary line numbers (~36 stale, drift +940 max), R.CanBel vs N._SunBelAllowed predicate divergence, Section 9 doc says "(not yet wired)" but code IS wired, Section 11 rules 3+4 doc says "(not yet wired)" but shipped, Saudi-rules Qaid forfeit text contradicts Net.lua code |
| **MISSING / not yet wired** | **11** | G-4 partner-bid suppression, B-3 5+ trump pursuit flag, A-2 Ashkal bid-up rank gate, AKA precondition (f) partner-trump-void, AKA precondition (g) round-stage/urgency, Bargiya 2-flavor split, Bargiya receiver phase-split, Tahreeb sender's "want" arm (low-then-high never emitted), 70/25/5 first-Tahreeb prior, Touching-honors family (Section 6 rules 1-4), Six-factor opp-Tanfeer reading |

---

## HIGH-severity bugs

### H1. v0.7.0 Sun-overcall: Race-A-class wire desync (CONFIRMED)

**Source:** Reports `12_v0.7.0_sun_overcall.md` and `31_overcall_race_verify.md`.

**Details:** `N._OnOvercallResolve` (Net.lua:1096-1105) accepts `takenStr/by/otype` from the wire payload but never reads them — calls `S.FinalizeOvercall()` which **re-derives** from the remote's locally-recorded decisions table. If MSG_OVERCALL_DECISION frames are dropped/reordered on a slow client, the remote ends up on a different contract (Hokm vs Sun, or different bidder) than the host.

**Self-correction gap:** the `taken=true` branch sends a follow-up MSG_CONTRACT (line 1187) that masks the desync. The `taken=false` branch sends nothing → desync persists into trick play.

**Impact:** functional, not cosmetic. A remote can play under different contract semantics — different trump suit, different multiplier, different scoring.

**Fix direction:** trust the wire payload in `_OnOvercallResolve`; broadcast MSG_CONTRACT in BOTH branches.

### H2. Failed-Gahwa loser keeps own melds (cumulative inflation)

**Source:** Report `73_game_end_hunt.md`.

**Details:** `R.ScoreRound` line 836-847 — the failing-Gahwa team is sent through the `outcome_kind == "fail"` branch which still credits their own carré melds at line 763-765. `_HostStepAfterTrick` only inflates the WINNER's add via `math.max`. Result: the loser banks meld points on the way to losing the match.

**Concrete repro:** bidder gahwas with a 100-meld carré, fails — loser still gets +100 to cumulative even though they lose the match.

**Fix direction:** zero loser's `final` deltas in the gahwa-fail branch.

### H3. Tie-at-target tiebreaker reads `contract.bidder` (wrong on failed Gahwa)

**Source:** Report `73_game_end_hunt.md`.

**Details:** `Net.lua:1611` — when both teams reach target in the same round, the tiebreaker hands the match to `contract.bidder`'s team. But on a **failed Gahwa**, `contract.bidder` IS the loser. Constructible at `cumA ≈ cumB ≈ 148`: failed-Gahwa team gets the match-win.

**Fix direction:** tiebreaker should respect `bidderMade` / Gahwa outcome, not raw `contract.bidder`.

### H4. ISMCTS pcall granularity wraps entire 100-world loop

**Source:** Report `69_ismcts_edges_hunt.md`.

**Details:** `BotMaster.PickPlay` line 795 — the pcall wrapping is at the OUTER loop level (around all 100 worlds). One bad sample (sampler edge case, ScoreRound corner case) causes pcall to bail and discard all 99 healthy rollouts → bot falls back to heuristic. Should be per-world pcall.

**Fix direction:** move pcall inside the per-world iteration; aggregate skips failed worlds rather than aborting the batch.

---

## MEDIUM-severity bugs

### M1. PHASE_OVERCALL 5-sec timer pause-blind

**Source:** Reports `34_pause_afk.md`, `64_phase_inconsistency_hunt.md`.

`Net.lua:1143` PHASE_OVERCALL timer fires mid-pause → force-resolves contract. Fix: same `S.s.paused` re-arm pattern as the SWA timer.

### M2. /reload mid-OVERCALL or mid-SWA soft-locks

**Source:** Reports `35_save_restore.md`, `64_phase_inconsistency_hunt.md`.

`WHEREDNGN.lua` PLAYER_LOGIN re-arms only Bel/Triple/Four/Gahwa timers — no re-arm for SWA (Net.lua:2569) or PHASE_OVERCALL (Net.lua:1143). Host /reload mid-window soft-locks until manual recovery.

### M3. ISMCTS desire-table mutation not idempotent

**Source:** Report `69_ismcts_edges_hunt.md`.

`sampleConsistentDeal` lines 368 + 428 mutate the shared `partnerDesire`/`defenderDesire`/`strong` tables across attempt retries. Mutation persists across seats and retries within one PickPlay call. Distorts sample distribution under retry pressure.

### M4. Bot._partnerStyle (and _memory, r1WasAllPass) wiped on /reload

**Source:** Report `35_save_restore.md` (Gap E).

These are module-level, not in `s` — wiped on every /reload. M3lm/Fzloky/Saudi-Master lose all accumulated partner reads silently mid-game. ResetStyle only fires at round 1.

### M5. Belote cancellation requires same-player meld

**Source:** Report `66_meld_boundary_hunt.md`.

`Rules.lua:670-678` cancellation requires `m.declaredBy == kWho` (same player). Saudi "100-meld subsumes belote" rule may be team-level — partner's carré would NOT cancel kWho's belote under current logic. Also silently fails when `declaredBy` is unpopulated.

---

## LOW / cosmetic bugs

### L1. SWA + Overcall banner OnUpdate self-ticks ignore pause

**Source:** Report `39_ui_state.md` and `70_ui_desync_hunt.md`.

UI.lua banners at 1337 (overcall) and 1445 (SWA) tick the countdown digit even under PAUSED overlay.

### L2. AFK-pass authorizeSeat rejection (cosmetic)

**Source:** Report `33_bid_wire.md` and `44_bid_ordering.md`.

When host synthesizes an AFK PASS for a human seat, `_OnBid`'s `authorizeSeat` rejects host-as-seat-owner. Receivers' bid-strips desync cosmetically until R2 clears. Functional contract still resolves correctly via subsequent MSG_CONTRACT.

### L3. Stale akaCalled if ApplyTrickEnd missed

**Source:** Report `68_aka_edges_hunt.md`.

Clear is only in `ApplyTrickEnd` (State.lua:1238). Resync replay may miss it; banner can leak into next trick.

### L4. Late-AKA retroactive flip (no #trick.plays == 0 gate)

**Source:** Report `68_aka_edges_hunt.md`.

`N.LocalAKA` and `_OnAKA` accept AKA mid-trick. A human pressing AKA mid-trick flips `s.akaCalled` and suppresses 4th-seat bot's ruff retroactively.

### L5. `_OnResyncRes` accepts unsolicited snapshots

**Source:** Report `43_lobby_handshake.md`.

A peer who overheard the gameID can fabricate a response and get bid/contract/cumulative state (no hand, but score-state leak).

### L6. WHEREDNGNDB.target type-guard gap

**Source:** Report `41_db_persistence.md`.

`WHEREDNGN.lua:77, 146` read `WHEREDNGNDB.target` without `tonumber()`. Hand-edited string target propagates and breaks `cum >= target` arithmetic.

---

## Doc vs code drift

| # | Issue | Resolution |
|---|---|---|
| D1 | **Glossary line numbers ~36 stale** (drift up to +940 lines from v0.5.x snapshots) | Re-anchor pass — see `15_glossary_line_drift.md` for the full table. |
| D2 | **R.CanBel vs N._SunBelAllowed predicate divergence** | `R.CanBel` blocks when team≥100; `_SunBelAllowed` requires `bidder≥101 AND defender<101`. R.CanBel's Sun branch is dead code at HEAD. **Recommendation: unify on R.CanBel** (per `29_canbel_divergence.md`). |
| D3 | **Section 9 Tanfeer doc says "(not yet wired)" but code IS wired** | N-1 sender + N-3 reader at Bot.lua:2555-2594 + 1508-1532. Doc MAPS-TO is stale since v0.5.14. |
| D4 | **Section 11 rules 3 + 4 doc says "(not yet wired)" but shipped** | Rule 3 pigeonhole at BotMaster.lua:285-318 (v0.5.22); rule 4 Sun-bidder-partner desire at BotMaster.lua:111-127 (v0.6.1). |
| D5 | **saudi-rules.md "Qaid forfeit (zeroed)" text contradicts Net.lua** | Net.lua:2098-2110 keeps own melds with owners (forfeit-not-transfer). saudi-rules.md row 119 still says "forfeited (zeroed)". |

---

## Missing features (rules in decision-trees.md NOT yet wired)

### From Section 1 (Bidding) — deferred

1. **G-4 — Takweesh bid-override anti-trigger** — `Bot.PickBid` has zero partner-bid suppression. Constructible: partner Hokm:♠, bot Hokm:♥-strong → bot emits HOKM:♥. Host drops at State.lua:1655 (winning already set), but the wire bid is the violation. **CONFIRMED in `72_partner_outbid_hunt.md`.**
2. **B-3 — 5+ trump Kaboot pursuit flag** — `S.s.pursuitFlagBidder` doesn't exist; only generic J+9 strength bonus.
3. **A-2 — Ashkal bid-up rank gate** — no `bidCardRank ∈ {7,8,9,J,Q}` predicate; Ashkal can fire on bid-up K when sun<85.

### From Section 6 (AKA / signaling)

4. **Touching-honors family (rules 1-4)** — entirely NOT-WIRED. Partner played T → infer K-in-partner; partner played K → infer Q; partner played Q → infer J; partner played low → infer broke-in-suit.
5. **PickAKA precondition (f) partner-trump-void** — only `trickNum <= 1` skip exists; v0.5.16 didn't close this.
6. **PickAKA precondition (g) round-stage / scoreUrgency** — same as above.

### From Section 8 (Tahreeb)

7. **Tahreeb sender's "want" arm** — sender has NO low-then-high encoder (T-4 explicitly emits LARGER first). Receiver's `want` classification can only fire by coincidence. **Two-trick small-to-big confirmation never produced.** This is a real strategic gap.
8. **70/25/5 first-Tahreeb prior** — receiver returns plain "hint" with weight 0; doesn't apply the video #09 probability prior.
9. **Bargiya 2-flavor distinction** — `Bot.lua:1410-1415` defers invite-vs-defensive-shed. Both treated as "lead-this-back". Wastes Aces in defensive-shed scenarios.
10. **Bargiya receiver phase-split** — no ≤4 vs ≥5 card-count gate; receiver always leads lowest in preferred suit.

### From Section 11 (Reads)

11. **Six-factor opp-Tanfeer reading** (video #19) — no `tanfeerWeight`, no ledger keys, no bidder/non-bidder asymmetry. Doc-side gap first.

---

## Recently-shipped features that VERIFIED clean

| Version | Feature | Status |
|---|---|---|
| v0.5.13 | S-3 calibration (12→15) + 7 K.* constants | ✅ Correct, no shadowing |
| v0.5.15 | UI Bel gate + Ashkal test fixture (16 assertions) + glossary snapshot | ✅ Real gate, fixture catches inversion regression |
| v0.5.17 | R.IsValidSWA pre-existing bug fix + strict-determinism | ✅ Strict iteration confirmed; partner adversarially treated |
| v0.5.18 | Section 4 Takbeer point-card extension (A,T,K,Q,J) | ✅ Correct, but NO new tests |
| v0.5.21 | Sun Faranka core + scoring discrepancy (+4 → +5 in 2 stragglers) + Hokm SWA safety | ✅ All three correct |
| v0.5.22 | Section 11 rule 3 pigeonhole pin (J/9 → all trump ranks) | ✅ Correct, but NO new tests |
| v0.5.23 | H-3 (singleton-lead rank guard) + H-7 (combinedUrgency clamp) | ✅ Both correct, but H-IDs collide with v0.5.0 patches |
| v0.6.1 | leadCount + Sun-bidder partner concentration in sampler | ✅ M3lm-gated, no double-count |
| v0.7.1 | B-97 opp-meld suit avoidance | ✅ Reads meldsByTeam authoritatively, M3lm-gated |
| v0.7.2 | Section 4 rule 1A revert + 1B second-lowest + Section 11 rule 1 wire | ⚠ 1A clean; 1B missing `wouldWin` check (cosmetic — branch never overruns partner anyway); rule 1 wire correct but **NO TEST** |

---

## Test-coverage gaps

Multiple v0.5.x and v0.7.x commits shipped production-code changes WITHOUT new tests:

- **v0.5.18** Takbeer point-card extension — no test pinning K/Q/J donation
- **v0.5.22** pigeonhole pin extension — no test asserting K/Q/T/A/8/7 pin behavior
- **v0.7.1** B-97 opp-meld suit avoidance — 30 lines added, 0 tests
- **v0.7.2** Section 11 rule 1 wire — no test for win/loss case

The pattern is: feature added → "226/226 still pass" → no regression pin. Future refactors can silently re-flip behavior. Recommend a pre-commit norm: "any production-code change includes ≥1 new assertion."

Test count progression: 177 (v0.5.5) → 196 (v0.5.11) → 202 (v0.5.12) → 226 (v0.5.22) → 292 (v0.7.2). Healthy growth, but gaps above are real.

---

## Areas verified clean (no findings)

- Tier dispatch (Basic/Advanced/M3lm/Fzloky/Saudi-Master)
- Illegal play paths (`legalPlaysFor` is the single funnel)
- Contract-type confusion (Hokm-vs-Sun gating clean)
- Partner-vs-opp confusion (R.Partner / R.TeamOf consistent)
- Trick-counting off-by-one (8 sites checked)
- Liveness / infinite loops (bounded)
- Authorization & spoofing (no exploitable vectors)
- Pause/resume base flow (re-arms work; only the OVERCALL timer is missing)
- Round-end transition wire (host-canonical, idempotent)
- Lobby + game-start handshake (4-join race, MSG_HAND whisper isolation, spectator paths all clean — single info-leak via _OnResyncRes)
- Ace-Carré in Hokm scoring (matches Pagat-strict; flag if intent differs)
- Cumulative idempotence on round broadcast (absolute totals via wire)
- Bidding host-authority (clients accept MSG_CONTRACT only)
- pickFollow opp-winning fall-through (Tasgheer correctly via `lowestByRank`)
- pickFollow ruff branches (AKA-suppress + partner-winning relief consistent)
- BotMaster sampler core (role dispatch H-1/H-2/H-3 correct)
- BotMaster rolloutValue determinism (per-world deterministic, aggregate uses math.random)
- R.IsValidSWA (strict-deterministic)
- Bot.PickSWA gating (no probabilistic SWA)
- Faranka Sun vs Hokm divergence (Sun gated; Hokm structurally cannot duck)
- v0.5.20 "Hokm Faranka — no code change" verdict (correct)

---

## Recommended next-action priority

1. **Fix H1 (Sun-overcall race)** — functional desync, biggest player-facing risk.
2. **Fix H2 + H3 (Game-end Gahwa edge cases)** — match-resolution bugs.
3. **Fix H4 (ISMCTS pcall granularity)** — Saudi Master quality regression.
4. **Reconcile D2 (R.CanBel vs N._SunBelAllowed)** — unify or document the asymmetry.
5. **Wire G-4 (Takweesh anti-trigger)** — concrete violation of video #29.
6. **Clear D1 (glossary line drift)** — ~36 stale citations, doc usability.
7. **Cover test gaps** — at least pin v0.7.1, v0.7.2, v0.5.22 behaviors.
8. **MEDIUM-tier fixes** (M1-M5) — defer if time-pressed; none are user-blocking.

---

## Methodology footnote

73 agents dispatched in 5 batches (15 + 15 + 15 + 12 + 16). Each agent wrote a focused ≤500-word report; aggregation done by reading those reports. Findings de-duplicated and triaged by severity. Per-agent reports retained at `.swarm_findings/audit_v0.7.1/01..73_*.md` for spot-check.

Originally requested 200 agents; 73 yielded saturation on findings — diminishing returns past ~60. Quality of findings has not been compromised by the smaller sample.
