# REVIEW_v0.10.2.md — synthesis of the v0.10.2 multi-agent audit

**Codebase:** WHEREDNGN (Saudi Baloot WoW addon) — v0.10.2 live (commit `fe3f8fb`).
**Audit cycle:** ran across multiple sessions, dispatched ~95 specialist
agents across all 7 planned waves (Wave 5 retry after monthly-limit lift)
plus an independent synthesis-validation agent (115 reports total).
**Status:** 7 code fixes + 7 doc fixes + 1 regression test pin applied
in-tree (uncommitted) under the v0.10.3 marker. Independent validation
confirms all 5 originally-claimed fixes plus 2 additional fixes the
main fork applied concurrently. Last clean run: **364 / 364 tests pass.**
**This document indexes findings, applied fixes, deferred backlog, and
reverse-correction candidates against v0.10.0. See
`REVIEW_v0.10.2_validation.md` for the independent validation pass.**

---

## 1. Executive summary

| Track | Reports on disk | Coverage |
|---|---|---|
| A — Source extracts (verbatim Arabic) | **30 / 30** | All 8 PDFs + 22 video transcripts re-extracted |
| B — Code per-function audits | **42 / 30** (over-target) | Net.lua, State.lua, Bot.lua, BotMaster.lua, UI |
| C — Cross-reference / doc consistency | **7 / 5** (over-target) | CHANGELOG, saudi-rules, decision-trees, glossary, Phase-1↔Wave-3 diff |
| D — Red-team adversarial probes | **31 / 30** | escalation, signal abuse, wire malformed, ISMCTS poisoning, cross-round leaks |
| E — UX / wire / determinism | **3 / 30** | E-Det-01 (ISMCTS), E-Net-01 (timer/wire races), E-UI-01 (banner state machines) — retried after monthly-limit lift |
| F — Test coverage | **1 / 30** | F-Test-01 (coverage gaps) — surfaced wire-tag pin already applied |
| G — Logic coherence | **1 / 20** | G-Logic-01 (cross-rule coherence) — 7 areas audited, 2 new MED gaps surfaced |
| **Total** | **114 reports** | |

**Verdict on v0.10.2:** broadly correct, with two CRIT-class production
defects and a cluster of HIGH-severity heuristic mis-scopings that this
audit cycle either fixed or queued for v0.10.3.

---

## 2. Code fixes applied this cycle (in tree, uncommitted)

| # | Site | Severity | Synopsis | Sources |
|---|---|---|---|---|
| 1 | `Constants.lua:229` | **CRIT-1** | `K.MSG_OVERCALL_RESOLVE = "?"` collided with `K.MSG_RESYNC_REQ = "?"`. Net.lua dispatch puts the OVERCALL elseif at line 543 before RESYNC at line 620 — every `"?"` tag was misrouted, leaving `_OnResyncReq` unreachable. Resync was dead in production. Reassigned OVERCALL_RESOLVE to `"!"`. | prior summary, Net.lua dispatch trace |
| 2 | `Bot.lua:2943-2992` (Hokm Faranka) | **HIGH** | F-16 K-cover veto over-fired on Exception #4 (oppsVoidPath). Threat model (opp A-of-trump punishment) is structurally extinct when both opps are observed-void in trump. Scoped F-16 to skip when `oppsVoidPath` is true. | A-Src-29, D-RT-03 S-1 (Option A) |
| 3 | `Bot.lua:2143` (comment block starts ~2128) | **HIGH** | `bidderTeam` was undefined in scope → `R.TeamOf(s2) ~= nil` is always true → conservativeOpp loop accepted any seat, defeating the team-gate. Added `local bidderTeam = R.TeamOf(contract.bidder)` inside the existing `contract.bidder` non-nil guard. | B-Bot-08 |
| 4 | `Bot.lua:1714` (`pickLead`, comment block starts ~1705) | **HIGH** | `local isBidderTeam = (contract.type == K.BID_HOKM and …)` made the predicate FALSE for all Sun contracts. Killed sweep-pursuit-early (lines 1727+, citing `K.AL_KABOOT_SUN=220` ×2=440), defender-style reads (1984), and other Sun branches. Removed the type clause. | prior summary, C-Xref-05 |
| 5 | `BotMaster.lua:838` (comment block starts ~830) | **HIGH** | Saudi-Master outer driver passed 5 args to `R.IsLegalPlay`, omitting `akaCalled`. Real-state legal filtering ignored M4 AKA-receiver relief — bot's own legal set was AKA-blind. Added `S.s.akaCalled` as 6th arg. (Inner rollouts intentionally pass nil for sim-blind semantics.) | E-Det-01 #7, B-BotMaster-01 F1, D-RT-18 S1 |
| 6 | `Net.lua:4064-4082` | **HIGH** | Bot-fired SWA timeout callback bare-exited on `S.s.paused` without re-arming → SWA banner soft-locked if user paused during the 5-sec window. Added named `botSWAResolveFn` with pause-aware re-arm via Pause/Unpause hooks. Applied by main fork concurrent with this audit (validation agent verified the v0.10.3 marker is in-tree). | E-Net-01 (RT-13/RT-32) |
| 7 | `Bot.lua:2988-2993` (Hokm Faranka Exception #4 secondary trigger) | MED | Pre-fix: F-30b `oppsVoidPath` required both `Bot._memory[opp].void[trump]` flags set positively, missing the structurally-extinct case where the entire trump pool was exhausted. Added `S.HighestUnplayedRank(trump) == nil` as a parallel secondary trigger. Applied by main fork concurrent with this audit. | G-Logic-01 §1 |

Tests after each fix: **all green.** (Validation report confirms 364/364 pass at the time of last run; main fork may have additional pins.)

---

## 3. Doc fixes applied this cycle

| # | File | Synopsis |
|---|---|---|
| 1 | `docs/strategy/saudi-rules.md:55` | Carré-A in Sun melds-table entry: 200 → 400 (matched `K.MELD_CARRE_A_SUN = 400` set in v0.10.0 R5; the table self-contradicted Q3 prose). |
| 2 | `docs/strategy/saudi-rules.md:94-100` | SWA paragraph rewritten — v0.5.17 routes ALL SWA calls through the 5-sec permission window. Pre-v0.5.17 "≤3 instant" branch is gone in code; doc was stale. |
| 3 | `docs/strategy/saudi-rules.md:231-232` | Failed-bid scoring corrected — bidder team **keeps its own melds** per v0.4.3+ rule «مشروعي لي ومشروعك لك»; only the trick-point side flows to the winner. Doc previously said "bidder team gets 0". |
| 4 | `docs/strategy/saudi-rules.md` (multiple) | Stale `Rules.lua` line refs refreshed: `R.ScoreRound 504→694`, `R.IsLegalPlay 117-121→137-141 + 145-149→165-169`, `R.DetectMelds 240-244→273-287`. |
| 5 | `docs/strategy/decision-trees.md:123-138` | **Mathlooth K-tripled revert.** v0.10.0 R7 flipped this to "J-tripled (canonical)" citing wrong Sun rank A>T>J. Video #17 is unambiguous: "اول شيء عندك اكه بعدها عشره بعدها شايب" → Sun rank is **A > T > K > Q > J > 9 > 8 > 7**. Canonical Mathlooth is K (الشايب); J/Q variants are lower-probability. |
| 6 | `docs/strategy/glossary.md:333` | Mathlooth row reverted to K-tripled canonical with J/Q variants noted. |
| 7 | `docs/strategy/glossary.md:20,21,41` | Removed references to non-existent constants `K.MSG_HOKM`, `K.PHASE_HOKM`, `K.MULT_HOKM`, `K.MSG_SUN`, `K.PHASE_SUN`, `K.MSG_BEL`. Hokm/Sun share `K.MSG_BID = "B"` with type discriminator; Hokm uses `K.MULT_BASE = 1`; Bel uses `K.MSG_DOUBLE = "X"`. |

---

## 4. Recommended fixes — deferred (require synthesis-level decision)

### 4.1 Reverse-correction candidates against v0.10.0

C-Xref-07 (Phase 1 ↔ Wave 3 diff) flagged four v0.10.0 fixes as
either wrong-direction or unsupported by re-extracted source:

| ID | Site | Verdict | Status this cycle |
|---|---|---|---|
| **R7** Mathlooth flip | doc only | wrong-direction (A-Src-06) | **REVERTED** in docs (#5, #6 above) |
| **X3** F-16 import to Hokm | `Bot.lua:2964-2992` | over-tight (A-Src-29) | **SCOPED** to skip Exception #4 (#2 above). Whether to remove F-16 from Hokm entirely (A-Src-29's strictest reading) is a follow-up call. |
| **R6** trust-asymmetry polarity | `BotMaster.lua:473-500` | A-Src-02 reported reversal; **A-Src-30 contradicts A-Src-02 across 5 sources** | **DEFERRED** — A-Src-02 is the outlier; current code likely correct. |
| **R5** Carré-A Sun = 400 | `Constants.lua:95` | confirmed correct by A-Src-25 | **NO ACTION** (only the saudi-rules.md table was stale) |

### 4.2 Code-level fixes still recommended (not yet applied)

| Severity | Site | Issue | Source |
|---|---|---|---|
| **HIGH** | wire protocol | **Cross-version OVERCALL_RESOLVE soft-lock** introduced by v0.10.3 fix #1. v0.10.3 host sends `"!"` → v0.10.2 client has no `"!"` handler → message dropped. v0.10.2 host sends `"?"` → v0.10.3 client routes to `_OnResyncReq` (which bails as non-host) → message dropped. Both directions soft-lock at PHASE_OVERCALL on `taken=false` (the `taken=true` branch self-recovers via the follow-up MSG_CONTRACT). Mitigation options: (a) lobby-level version-mismatch warning using existing `S.s.peerVersions`; (b) dual-emit `"?"` + `"!"` from v0.10.3 hosts (one direction only); (c) accept hard-break and document. | E-Net-01.3-X |
| ~~**HIGH**~~ APPLIED | ~~`Net.lua:4059-4067`~~ | ~~Bot-fired SWA timeout callback bare-exits on `S.s.paused` without re-arming.~~ → **Moved to §2 fix #6.** Note: residual pause-guard gaps in `HostResolveSWA` + `_OnSWAResp accept` + `_OnAKA` are still open as MED follow-ups. | E-Net-01 |
| **HIGH** | UI layer | `S.s.swaDenied` struct populated by `Net.lua` but **never read by UI**. SWA caller has no deny feedback when opps deny permission. | E-UI-01-1 |
| **HIGH** | UI layer (preempt button) | `قبلك` button glyph hardcoded — unreadable in non-Arabic-font locales. Last remaining hardcoded Arabic glyph in v0.10.2 UI; pattern already fixed elsewhere. | E-UI-01-2 |
| **HIGH** | `Rules.lua:817-822` | Reverse Al-Kaboot defender-sweep is type-blind; awards 250/220 instead of the +88 raw + bidder-led-trick-1 gate. **Constant `K.AL_KABOOT_REVERSE` does not exist** (proposal in saudi-rules.md is unwired). | A-Src-18, B-State-05 F-01, C-Xref-04 #13 |
| **HIGH** | `Rules.lua:928` | Gahwa match-win type-blind | B-State-05 F-02 |
| **HIGH** | `State.lua:1167-1184` | `S.ApplyMeld` drops Hokm Carré-A (X5 inert in the apply path despite the v0.10.0 fix at the detect path) | prior summary |
| **HIGH** | `Bot.lua:484-507` | Touching-honors WRITE missing partner-still-winning gate | prior summary |
| **HIGH** | `Bot.lua:1640-1683` | Bargiya inner-discriminator axis: code uses event-count + cover-grade; per #14 + P1B R9 the correct axis is hand-shape (محشور / suits-touched-count proxy) | A-Src-30, prior summary |
| MED | `Net.lua:1148-1149` | `_OnOvercallResolve` empty-payload phase demote (CRIT-2 in original triage) | prior summary |
| ~~MED~~ APPLIED | ~~`Bot.lua:2943-2955` (F-30b)~~ | ~~Exception #4 oppsVoidPath check requires both `Bot._memory[opp].void[trump]` flags set positively — misses the structurally-extinct case~~ → **Moved to §2 fix #7.** | G-Logic-01 §1 |
| MED | UI / pickFollow Sun pos-4 | Sun-Mathlooth-K holder at pos-4 with K + low + low will smother K to partner's pile on trick 1, defeating trick-3 Mathlooth preservation. Add a "Mathlooth-suit smother gate" before the Section-4 rule-7 Takbeer branch. | G-Logic-01 §3 |
| MED | `Net.lua:2240, 2972` | M5 Belote cancel still player-level (not backported from v0.10.x M5 fix) | prior summary |
| MED | `Net.lua:2327-2331, 3064-3068` | H3 tied-target tiebreaker not backported | prior summary |
| MED | `Net.lua:2185-2190, 2930-2935` | R2 Sun mult collapse not backported to Takweesh / SWA-invalid | prior summary |
| MED | `State.lua:1238-1265` | M3 false-AKA host-only wipe | prior summary |
| **HIGH** ↑ | `State.lua:1966` | `S.GetLegalPlays` UI-dimming AKA-blind. **Promoted from MED to HIGH per validation review** — this is the UI cousin of fix #5 (BotMaster `akaCalled` propagation). 1-line patch, same shape as fix #5: pass `S.s.akaCalled` as the 6th arg to `R.IsLegalPlay`. | prior summary, validation review |
| MED | `Bot.lua:1829-1838` | Hokm Branch 3 leads non-trump boss-Ace before trump-pull | B-Bot-08 F3 |
| LOW ↓ | `Bot.lua:2964-2972` (rule-7) | Anti-rule "Q-led + J+8 rebut" is **structurally dead** post-v0.10.0 + sourceless. Safe to delete. **Demoted from MED to LOW per validation review** (sourceless + dead = zero-risk cleanup, not a behavioural fix). | A-Src-29 D-RT-03 S-5, validation review |
| MED | `Bot.lua` PickBid Aceless 5-trump path | **B-Bot-06 F-01/F-02:** L07 cascade fail at M3lm+ for Aceless 5-trump J+9 hands. Estimated cost ~5–7 game-points/match. Real EV leak. Queued for v0.10.4. | B-Bot-06 F-01/F-02, validation review |
| LOW | `Bot.lua:1336-1342` + `1366-1372` | Duplicate T-cardinality block in PickBid — dead-code redundancy. One-line cleanup. | validation review |
| LOW | `Bot.lua:3801-3806` | `Bot.PickKawesh` unconditional (no rate-gate) | B-Bot-10-5 |
| LOW | `Rules.lua:108-110` | Misleading comment about AKA-on-T trick lock collapsing to AKA-on-A | A-Src-07 HEADLINE |

### 4.2.1 Sun-bid frequency calibration (post-validation finding)

Independent validation surfaced that user-observed Master-bot Sun-bid rate
is ~1% (originally framed as "99% Hokm"). Master tier uses the same
`Bot.PickBid` as every advanced tier — this is not a Master-specific bug.

**Combinatoric analysis from validation agent:**
- `sunMinShape` filter (≥2 Aces OR 1-Ace+mardoofa) admits **~37%** of random hands.
- Dominant suppressor: **`sunStrength >= thSun = 50`**. Bare 2-Ace and 1-Ace+mardoofa hands score 18–35 — far below the 50-point gate.
- Formula prediction: ~3–4% Sun-bid rate per seat. User's 1% is **plausibly low but only ~3× off the formula**, not 100× as initial framing implied.
- 5-point Hokm asymmetry and Bel-fear `+8` nudge are minor contributors.
- 15–25% target is **NOT source-anchored** — `A-Src-23` / `source_K` don't quantify Saudi tournament Sun-bid frequency.

**Recommended fix shape (validation agent — not applied):**
- **Preferred:** raise `K.BOT_SUN_MARDOOFA_BONUS` from `5` → `10`. Targeted at the canonical Saudi Sun-Mughataa A+T pattern (`A-Src-23`).
- **Fallback:** lower `K.TH_SUN_BASE` from `50` → `44`.
- **Do NOT touch** `sunMinShape` (source-mandated S-1) or the 5-point margin (source-anchored).

Severity: MED — the gate is correctly tight but possibly mis-calibrated.

### 4.3 Doc backlog still recommended

| File | Issue | Source |
|---|---|---|
| `decision-trees.md` | 7 rows marked "(not yet wired)" that **are** wired in v0.5.10–v0.9.3 (Sections 1, 6, 7, 8). | C-Xref-05 #4 |
| `decision-trees.md` | Two phantom function names: `Bot.PickAshkal` (Ashkal is inline in `Bot.PickBid`); `pickFollow.deceptiveOverplay` (never implemented). | C-Xref-05 #5 |
| `decision-trees.md` | All Section 0 header line refs drifted +285 to +1135. | C-Xref-05 #6 |
| `glossary.md` | Missing entries: الثالث / Tamtheel / Bargiya / محشور / Six-factor framework / Phase boundaries (10 total). | C-Xref-06 Section A |
| `glossary.md` | v0.5.15 snapshot table line refs all off (drift up to +1135). Fzloky gloss is "unclear" but code has stable canonical "veteran / they leave you no scraps". | C-Xref-06 Section B B4–B6 |
| `glossary.md` | Stale grep recipes referencing nonexistent `Bot.PickAshkal`, undocumented `S.s.preemptEligible`, missing `tahreebClassify`, missing `N.HostResolveSWA`. | C-Xref-06 Section C |
| `saudi-rules.md` | Item 22: 81/162 tiebreak oversimplifies — rule 4-10 inversion flips it on Bel'd/Foured contracts. | C-Xref-04 #22 |
| `CHANGELOG.md` | 4 MED line-ref drifts (M4 #4, X5 #30, R6 #34, X3 #37) cite pre-fix line numbers. | C-Xref-03 |

---

## 5. Sourcing corrections vs Phase-1 (review_v0.10.0)

C-Xref-07 found **23 confirmed / 5 corrected / 2 extended / 0 diverged**
between Phase-1 source bundles and Wave-3 re-extracts. Material
corrections:

- **Phase 1 source_F → A-Src-06.** Mathlooth canonical is K-tripled (الشايب), not J-tripled. v0.10.0 R7's "romanization-error" framing was itself the error.
- **Phase 1 source_L L12 → A-Src-25.** Q-row companion list in the 100-2-card refutation table excluded `10` (above Q in Saudi rank order); correct row is `{J, 9, 8, 7}`.
- **Phase 1 source_C → A-Src-29.** F-26 worked example uses Q (البنت), not J (الولد) per S1 line 184.
- **Phase 1 source_C / Bot.lua:2964 → A-Src-29.** F-16 K-required anti-rule is purely a Sun anti-rule from #06; zero hits in #04 (Hokm). v0.10.0 X3 import to Hokm unsupported.
- **Phase 1 ASR transcripts.** "تنفيذ" in #12 was an ASR error → "تنفير" (Tanfeer); "الصلاه" in #07 SRT block #51 → "الصن" (the Sun).
- **A-Src-22 PDF 02.** pypdf RTL-flip artifact: Arabic-Indic numerals appear as their digit-reversed Latin equivalents (٢٥١→152). Confirmed against the spoken-video Phase-1 J corpus.

**Phase-1 vindication:** the bulk of the Phase-1 source corpus stands.
Major investments (cross-source xref tables, SWA semantics, bidding
mechanics, escalation chain) all corroborated.

---

## 6. ISMCTS pipeline determinism (E-Det-01 highlights)

The Saudi-Master tier "ISMCTS" is **flat Monte Carlo with
determinization sampling**, not full ISMCTS — no node table, no UCB1,
no tree selection. The per-card `scores[c]` is a flat sum of
`rolloutValue` deltas across N independent worlds.

Determinism profile per E-Det-01:

| Aspect | Verdict | Severity |
|---|---|---|
| Seed control across rollouts | NON-DETERMINISTIC by intentional design (global RNG) | LOW correctness, MED debuggability |
| Hand-sample uniformity | BIASED by design (constraint-respecting, not uniform) | OK |
| Voids respected (primary path) | DETERMINISTIC EXCLUSION; fallback path leaks | MED |
| AKA-revealed cards excluded from sample pool | **BROKEN** — not consulted at all | LOW-MED |
| Rollout count | FIXED tiered (100 / 60 / 30 by trick number) | LOW |
| Cross-contract picker consistency | UNIFORM `heuristicPick` for all seats; tier-blind in rollouts | OK |
| Pause/unpause mid-rollout | NO pause check; runs to completion | LOW-MED |
| `Bot._memory` round reset | DETERMINISTIC; per-game `_partnerStyle` carries (intentional) | OK |
| `akaCalled` propagation in outer driver | **BROKEN — FIXED THIS CYCLE** (#5 above) | HIGH |

---

## 7. Methodology notes for v0.10.3 reviewer

- **Source-of-truth precedence** (re-confirmed): PDFs > videos > docs > code (verbatim Arabic anchored). When two sources disagree, fall back to verbatim Arabic timestamp + video transcript line.
- **pypdf RTL-flip is an artifact of the toolchain** (A-Src-22 / A-Src-28). Do not trust raw numeric strings out of `pypdf` for Arabic-Indic numerals — cross-check against the spoken video corpus.
- **YouTube ASR error patterns** (A-Src-15, A-Src-30): "تنفيذ" appears for "تنفير" in #12; "الصلاه" appears for "الصن" in #07. When a single transcript line looks anomalous, check for ASR substitution before treating it as a source claim.
- **`R.IsLegalPlay` 6-arg signature.** The optional `akaCalled` is the M4 AKA-receiver relief gate. Real-state legal-filter call-sites (UI dimming at `S.GetLegalPlays`, BotMaster outer driver) MUST pass `S.s.akaCalled`. Inner rollouts intentionally pass nil.
- **Wire-tag sanity.** v0.10.3 reassigned `K.MSG_OVERCALL_RESOLVE` to `"!"`. New wire-tag additions should grep all `K.MSG_*` constant values to avoid byte-collisions; the dispatcher is `if/elseif tag == …` chained, so the FIRST matching branch wins.

---

## 8. Audit completeness ledger

| Wave | Plan | Done | Status |
|---|---|---|---|
| 1 — Red-team | 30 | 31 | ✓ COMPLETE |
| 2 — Code per-function | 30 | 42 | ✓ OVER-COMPLETE |
| 3 — Source extracts | 30 | 30 | ✓ COMPLETE |
| 4 — Doc consistency | 30 | 5 (+2 carry-over from prior) | PARTIAL — 5 high-value reports cover CHANGELOG, saudi-rules, decision-trees, glossary, Phase-1↔Wave-3. Remaining 23 not high-leverage given coverage. |
| 5 — UX / wire / determinism | 30 | 3 | RETRIED — E-Det-01, E-Net-01, E-UI-01 all landed after monthly-limit lift. Highest-leverage UX findings captured. |
| 6 — Test coverage | 30 | 1 | F-Test-01 surfaced regression-pin priorities; wire-tag pin applied in-tree. |
| 7 — Logic coherence | 20 | 1 | G-Logic-01 audited 7 cross-rule areas; 2 MED gaps surfaced (one already fixed by main fork). |
| Synthesis | 1 | 1 | ✓ THIS DOCUMENT |
| Validation | 1 | 1 | ✓ Independent review at `REVIEW_v0.10.2_validation.md` |

**Coverage assessment:** despite Wave 5–7 attrition, the audit cycle
landed on the highest-leverage findings. Code paths most likely to
harbour CRIT/HIGH issues (Net.lua message handlers, Rules.lua
legality, Bot.lua heuristic gates, ISMCTS sampling) all received
multiple agent passes. Test coverage and full UX flow audits are
deferrable to a separate cycle.

---

## 9. Suggested v0.10.3 release scope

**Definitely in scope** (already applied + tests pass):
1. Code fixes #1–#7 (CRIT wire-tag + 5 HIGH heuristic / scoping fixes + 1 MED F-30b secondary trigger)
2. Doc fixes #1–#7 (saudi-rules + decision-trees + glossary)
3. Test pin (wire-tag distinctness section R, R.1 + R.2)

**Suggested in scope** (low-risk follow-ups):
3. Delete dead rule-7 anti-trigger at `Bot.lua:2974-2993` (sourceless + structurally dead — A-Src-29 + D-RT-03 S-5)
4. Re-anchor decision-trees.md Section 0 line numbers (mechanical — drift up to +1135)
5. Add the 10 missing glossary entries flagged in C-Xref-06 Section A

**Defer to v0.10.4 or beyond** (require design call):
6. Reverse Al-Kaboot rewrite (`K.AL_KABOOT_REVERSE = 88`, bidder-led-trick-1 gate)
7. Bargiya inner-discriminator axis flip (event-count → hand-shape)
8. ISMCTS akaCalled-respecting sample pool (E-Det-01 #2c)
9. Backported MED-severity fixes (Net.lua M5 / H3 / R2; State.lua M3, GetLegalPlays AKA-blind)

---

## 10. References

All audit reports live under `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\`:

- `_track_A_sources/` — A-Src-01 through A-Src-30 (verbatim Arabic re-extracts)
- `_track_B_code/` — B-Net-* / B-State-* / B-Bot-* / B-BotMaster-* / B-UI-* (per-function audits)
- `_track_C_xref/` — C-Xref-01 through C-Xref-07 (cross-references and doc-drift)
- `_track_D_redteam/` — D-RT-01 through D-RT-32 + D-RedTeam-* (adversarial probes)
- `_track_E_ux/` — E-Det-01 (ISMCTS determinism — only Track-E report that landed)

Phase-1 source bundles preserved at:
`C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase1_sources\`

---

*End of REVIEW_v0.10.2.md*
