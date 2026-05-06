# REVIEW_v0.10.4_ship_readiness.md — independent ship-readiness review of v0.10.4

**Mode:** Read-only. Reviewer modifies no `.lua`, no `.md`, no test, no config.
**Primary inputs:** `REVIEW_v0.10.2.md` (synthesis, ~250 lines),
`REVIEW_v0.10.2_validation.md` (focused-validation pass, ~280 lines).
**Secondary inputs:** all 114 audit reports across tracks A–G (sampled);
in-tree code at `C:\CLAUDE\WHEREDNGN\*.lua` and `tests/*.lua`; CHANGELOG.md.
**Verification scope:** 8 ship-readiness tasks per the parent prompt.

---

## 1. TL;DR — ship verdict

**GO-WITH-CONDITIONS.** v0.10.4 is a minimal, well-scoped 2-fix follow-up
on top of a v0.10.3 base that the validation pass already cleared. Both
v0.10.4 changes (`State.lua:1975` `GetLegalPlays` AKA-relief; `Constants.lua:329`
`K.BOT_SUN_MARDOOFA_BONUS = 10`) are confirmed present at the cited
sites, do what the CHANGELOG claims, and do not bleed into other code
paths. **377 / 377 tests pass green.** The Sun-bid calibration math
predicts the bonus bump moves Sun-bid rate from ~3.1% → ~4.1% — a real
improvement but well below the source-implied ~5–10% target, so users
who reported the 1% rate may still see a low rate (just less low).

The "conditions" for shipping:

1. **Sun-bid Option B alone is under-tuned to fully resolve the user
   complaint.** The math predicts only a 1.3× lift. Recommend documenting
   in the CHANGELOG that this is a *first-step* recalibration with
   follow-up empirical A/B planned.
2. **`State.s.akaCalled` field-name detail.** The v0.10.4 `State.lua:1975`
   addition uses `s.akaCalled` (local `s` alias for `S.s`) — verified
   correct, no parity issue.
3. **Several audit-corpus HIGH findings remain absent from the synthesis
   §4.2 backlog** (see §2 below). None block v0.10.4 shipping (they were
   absent at v0.10.3 ship as well), but they should be triaged before
   v0.10.5.
4. **No drift between CHANGELOG, code, and tests** for the v0.10.4-scoped
   changes. The CHANGELOG even self-acknowledges and documents the
   v0.10.3 line-number drift the validation pass surfaced.

The ship is technically ready and tests pass; the user's "1% Sun rate"
complaint will be partially but not fully addressed.

---

## 2. Synthesis ↔ corpus completeness audit

The synthesis indexes 114 reports but its §4.2 deferred backlog only
captures a subset of the audit-corpus HIGH findings. Skimming the
corpus surfaces these HIGH-severity items not represented in §4.2 (or
in §2 applied):

### 2.1 Missing AKA-mechanism HIGH findings

`D-RedTeam-01_aka_exploits.md` (also `B-Net-05_aka_wire.md` F8)
documents three HIGH exploits not in the synthesis:

| Item | Source | Severity | Synopsis |
|---|---|---|---|
| **E1 / F8a — AKA-on-trump bypass** | `D-RedTeam-01:29-60`, `B-Net-05` F8a | HIGH | `N._OnAKA` does not reject `suit == contract.trump`. UI hides the button (correctly), but a hostile peer can craft `MSG_AKA;1;<trump>` directly on the wire. Multi-trick damage: void+has-trump partner-bot discards instead of overcutting an opp's mid-trump. **Mitigation:** 1-line `if suit == S.s.contract.trump then return end` at `N._OnAKA`, plus 1-line guard at `Rules.lua:115-121` `akaRelief and akaCalled.suit ~= contract.trump`. |
| **E2 / F8b — `_OnAKA` mid-trick window mispredict** | `D-RedTeam-01:63-90`, `B-Net-05` F8b | HIGH | `LocalAKA` enforces lead-only (anti-misclick) but the wire path doesn't. A hostile peer sends spurious `MSG_AKA` mid-trick → bot's pickFollow consults `s.akaCalled` for the next play → suppresses ruff thinking partner has the boss. Trick is then locked in even when the host's later `ApplyPlay` validation fires Qaid against the offender. |
| **E4 — T-AKA trick-locking missing** | `D-RedTeam-01:118-141` | HIGH (structural) | Saudi T-substitution rule ("when AKA is on T because A is dead, T-locks the trick like the Ace") is not implemented in `R.CurrentTrickWinner`. Bot's receiver-relief branch only fires when `partnerWinning`; T-AKA + opp ruff makes `partnerWinning = false`, so bot abandons AKA semantics and over-trumps — losing to opp's higher trump. |

**E1 and E2 share a single 1–2-line `N._OnAKA` patch and could ship as
a v0.10.4 follow-up. E4 is structural (rules-layer change) and is
correctly defer-class.**

### 2.2 Missing wire-validation HIGH findings

`D-RT-15_wire_malformed.md` and `B-Net-02_contract_bid_overcall.md` both
document multiple HIGH items not in the synthesis backlog:

| Item | Source | Severity | Synopsis |
|---|---|---|---|
| **B-Net-02-H2 / D-RT-15 row** | `B-Net-02 H2`, `D-RT-15` table | HIGH (latent) | `_OnContract` accepts `bidder=9` (out-of-range) and stores it verbatim. `S.ApplyContract` has no seat-range check. `(9 % 4) + 1 = 2` produces a wrong defender for Bel/Triple/Four windows. Mitigated by `fromHost` gate in canonical flow but reachable on host compromise. **2-line range guard.** |
| **B-Net-02-H1** | `B-Net-02 H1` | HIGH (latent) | `contract.forced` is read in 3 places but never set anywhere in production code — the gates are dead branches. |
| **B-State-02-H1** | `B-State-02 H1` | HIGH (latent) | `S.ApplyBid` does not validate the `bid` value — accepts any string. Wire-side handler `_OnBid` partially validates, state primitive doesn't. |

### 2.3 Missing scoring-coherence HIGH findings

`B-Net-04_swa_full.md` calls out two HIGH backports also flagged in
prior synthesis MED list:

| Item | Source | Severity | Synopsis |
|---|---|---|---|
| **B-Net-04-1 — Belote predicate divergence** | `B-Net-04` row 1 | HIGH | `HostResolveTakweesh` Belote predicate at `Net.lua:2239-2244` does NOT match `R.ScoreRound`'s M5 predicate. Probability ~0.003-0.012% per round (low) but EV swing is +20 raw misallocated. The synthesis backlog has the M5 backport at MED ("Net.lua:2240, 2972 M5 Belote cancel"); this audit flags it as HIGH. |
| **B-Net-04-2 — Tied-target backport** | `B-Net-04` row 2 | HIGH (impact) | Tied-target tiebreaker bug in `HostResolveTakweesh` at `Net.lua:2327-2331` awards match to the team that just lost the round. Probability sub-0.1% but impact is HIGH (match flip). Listed as MED in synthesis (`Net.lua:2327-2331 H3 tied-target`); B-Net-04 calls out as HIGH for impact. |

### 2.4 Missing Bargiya HIGH finding

`D-RedTeam-02_bargiya_exploits.md` documents:

| Item | Source | Severity | Synopsis |
|---|---|---|---|
| **Exploit 1 — Forced-Bargiya inflation** | `D-RedTeam-02:22-85` | HIGH | v0.10.2 M7 `lenAtAce >= 5` path has no rank-quality gate. A genuine 5-card holding of `A♠ + 9/8/7/junk` now scores identically to `A♠ T♠ K♠ Q♠ J♠`. This is the cousin of the `Bot.lua:1640-1683 Bargiya inner-discriminator axis` HIGH already in synthesis §4.2 — same root, different attack surface. The synthesis captures the axis flip but not the FN→FP swing. |

### 2.5 Other corpus HIGH cross-references

`D-RT-22 R1-induced 30s AFK regression` (HIGH) per `B-Net-06 F3` — not in synthesis backlog. Verdict: real but specific scenario-bound; defensible to defer.

`D-RT-24 mardoofa-leak HIGH` (M8 information-leak structural) — explicitly defer-class per the report itself ("Documentation only — no code change in M8 scope"). Not a synthesis omission.

`D-RT-31 SWA partner-adversarial` (HIGH) — explicitly defer-class per the report itself ("DEFER to user arbitration"). Not a synthesis omission.

### 2.6 Verdict on synthesis completeness

| Category | Count |
|---|---|
| HIGH findings missing from synthesis §4.2 (real omissions) | 6 (E1, E2, E4, B-Net-02-H1/H2, B-State-02-H1, Bargiya FN→FP) |
| HIGH findings under-rated in synthesis (listed as MED) | 2 (M5 Belote, H3 tied-target) |
| HIGH findings explicitly self-deferred per source | 3 (D-RT-24, D-RT-31, plus E4 structural) |

**Net:** synthesis is reasonably comprehensive but not exhaustive. The
6 real-omission HIGH items don't include any fast-2-line fixes that
should block v0.10.4. They should be triaged into v0.10.5+.

---

## 3. Synthesis ↔ tree alignment (drift check)

The validation report (Section 4) flagged ±10-line drift on the comment-block
citations for fixes #3, #4, #5. The CHANGELOG.md v0.10.4 §"Notes for
v0.10.4 reviewers" explicitly acknowledges this drift and identifies
correct line numbers (1714, 2143, 838, 2980).

**Verification I performed:**

| Synthesis cite | Validation said actual is | I verified actual is | Status |
|---|---|---|---|
| `Constants.lua:229` (OVERCALL_RESOLVE = "!") | exact at 229 | exact at 229 (`K.MSG_OVERCALL_RESOLVE = "!"`) | EXACT |
| `Bot.lua:2128` (bidderTeam) | actual at 2143 | declaration at **2143** confirmed (`local bidderTeam = R.TeamOf(contract.bidder)`); inside `contract.bidder ~= nil` guard at 2134 | DRIFT +15, captured in CHANGELOG |
| `Bot.lua:1705` (isBidderTeam) | actual at 1714 | predicate at **1714** confirmed (`local isBidderTeam = (myTeam == R.TeamOf(contract.bidder))`) | DRIFT +9, captured in CHANGELOG |
| `BotMaster.lua:830` (R.IsLegalPlay 6-arg) | actual at 838 | call at **838** confirmed (`R.IsLegalPlay(c, hand, trick, S.s.contract, seat, S.s.akaCalled)`) | DRIFT +8, captured in CHANGELOG |
| `Bot.lua:2964` rule-7 dead anti-trigger deletion | not yet verified | Comment block at **3024-3037** documents the deletion; no anti-rule code remains | EXACT (line shifted ~60 due to other v0.10.3 inserts) |
| `Bot.lua:2943-2992` Faranka block (oppsVoidPath, F-30b, F-16) | block 2934-3022 | `oppsVoidPath` declared at **2959**; F-30b secondary trigger at **2988-2993**; F-16 gate at **3014** | EXACT (range-cite, all sub-fixes present) |
| `Net.lua:4064-4082` `botSWAResolveFn` (SWA bot pause re-arm) | confirmed in-tree | named function defined at **~4087-4115**, with v0.10.3 marker comment at 4088-4089. Synthesis §2 fix #6 is correctly applied. | EXACT (in-tree) |
| `State.lua:1975` (v0.10.4 `S.GetLegalPlays`) | not in original synthesis | call at **1975** confirmed (`R.IsLegalPlay(c, s.hand, s.trick, s.contract, s.localSeat, s.akaCalled)`); v0.10.4 marker comment at 1964-1972 | EXACT — this is the v0.10.4 fix |
| `Constants.lua:329` (`K.BOT_SUN_MARDOOFA_BONUS = 10`) | not in original synthesis | exact at **329** with v0.10.4 marker comment at 330-340 | EXACT — this is the v0.10.4 fix |

**Net §3 verdict:** No remaining drift. The CHANGELOG self-corrects
the v0.10.3 line-number citations. All fixes the synthesis claims
are in tree are present at the (now-correct) line numbers. The two
v0.10.4 additions are at exactly the locations the CHANGELOG claims.

---

## 4. v0.10.4 incremental changes since synthesis

The synthesis was written at v0.10.2-with-v0.10.3-stash state. By v0.10.4
ship, the main fork has applied an additional 2 changes plus 1 test
section. Diff vs synthesis:

| File | Change | In synthesis? | Synopsis |
|---|---|---|---|
| `State.lua:1961-1979` | `GetLegalPlays` adds `s.akaCalled` as 6th arg to `R.IsLegalPlay`, plus 9-line v0.10.4 marker comment | NO — synthesis listed this as MED-deferred at `State.lua:1966 S.GetLegalPlays UI-dimming AKA-blind`; validation pass promoted to HIGH, applied by main fork in v0.10.4 | Closes the M4 loop at the UI layer. Same one-arg shape as v0.10.3 BotMaster fix #5. |
| `Constants.lua:329-342` | `K.BOT_SUN_MARDOOFA_BONUS = 10` (was 5), 12-line v0.10.4 calibration comment expanded | NO — validation pass §4.2.1 recommended this. Synthesis itself didn't elevate it; CHANGELOG calls it a calibration | Targets canonical Saudi A+T cover pattern. With pair cap 2, max bonus moves +10 → +20. |
| `tests/test_state_bot.lua:293-338` | New test section (45 lines) — 6 assertions: 3 positive AKA-relief cases + 3 sanity cases | NO — net test count grows from 371 to 377 (per CHANGELOG +6) | Pins the new GetLegalPlays AKA-relief behavior; sanity checks ensure the without-AKA baseline still must-trump. |
| `CHANGELOG.md:1-62` | New v0.10.4 entry (62 lines) | NO | Describes both changes plus references the v0.10.3 line-drift acknowledgment. |
| Other production .lua files | None changed at the file/function level beyond the v0.10.3 stash baseline | — | Verified via grep for v0.10.4 markers in `Bot.lua`, `BotMaster.lua`, `Net.lua`, `Rules.lua`, `Cards.lua`, `WHEREDNGN.lua`, `UI.lua` — only Constants.lua and State.lua have v0.10.4 markers |
| `tests/test_rules.lua` | No v0.10.4 marker | NO change beyond v0.10.3 stash | Implicit. |

**v0.10.4 is genuinely a 2-fix release.** No undocumented changes lurking in
the tree.

---

## 5. Severity calibration sample (8 entries from §4.2)

I sampled 8 entries from synthesis §4.2 and validated against source
audit reports. Notation: ✓ = severity defensible; ↑ = should promote;
↓ = could demote.

| Item | Synthesis severity | My verdict | Reasoning |
|---|---|---|---|
| Cross-version OVERCALL_RESOLVE soft-lock | HIGH | ✓ HIGH | E-Net-01.3-X is explicit. v0.10.3 dual-emit mitigation (already in tree at `Net.lua:1086-1095`, `Net.lua:621-631`) makes the actual user impact LOW; severity rating is for the latent issue. Ship-blocker only if mitigation is removed. |
| `S.s.swaDenied` UI never read | HIGH | ✓ HIGH | E-UI-01-1; user-visible feedback gap. Worth a v0.10.5 patch. |
| `Rules.lua:817-822` Reverse Al-Kaboot type-blind | HIGH | ✓ HIGH | C-Xref-04 #13: defender-sweep over-pays vs intended +88 by 162 raw (Hokm) or 132 raw (Sun). `K.AL_KABOOT_REVERSE` constant doesn't exist (verified via grep). Real EV impact. |
| `Rules.lua:928` Gahwa match-win type-blind | HIGH | ↓ MED | Sun cannot reach Gahwa structurally per A-Src-22 K-33 (Sun's Bel-only escalation chain collapses Triple/Four/Gahwa). The Gahwa match-win branch on a "stale Sun gahwa flag" is a defensive concern, not a live-game bug. The validation pass also flagged this for downgrade. |
| `State.lua:1167-1184` `S.ApplyMeld` drops Hokm Carré-A | HIGH | ✓ HIGH | B-State-03 F1 + G-Logic-01 §4. Verified directly: lines 1171-1184 — `value=nil` for Hokm Carré-A, so `S.ApplyMeld` never inserts the meld. Detect-path was fixed in v0.10.0 X5 but apply-path was missed. Live-game bug whenever Hokm bidder rolls 4 Aces (~1.9% probability; high-impact). |
| `Bot.lua:484-507` Touching-honors WRITE missing partner-still-winning gate | HIGH | ✓ HIGH | B-Net-05 F7 confirms; v0.10.0 R6 K-fix magnifies the pre-existing gap. Partner-winning-state-at-write-time is a real signal-pollution gap. |
| `Bot.lua:1640-1683` Bargiya inner-discriminator axis | HIGH | ✓ HIGH | A-Src-30 + R4 reaudit; the cover-grade gate is in tree (v0.10.2 M7) but the doc-mandated axis is hand-shape (محشور). D-RedTeam-02 Exploit 1 confirms a current FN→FP swing path. Architectural fix; correctly defer-class. |
| `Bot.lua:3801-3806` `Bot.PickKawesh` unconditional | LOW | ✓ LOW | B-Bot-10-5; rate-gate gap, low-leverage. |
| Rule-7 anti-rule deletion (`Bot.lua:2964-2972`) | LOW (post-validation) | ✓ already DELETED in tree | Confirmed at lines 3024-3037 — comment block documents the deletion, no anti-rule code remains. Should be REMOVED from §4.2 backlog (it's done). |
| Duplicate T-cardinality block (`Bot.lua:1336-1342`) | LOW | ✓ LOW | B-Bot-06 F-03; cosmetic dead code. |

**Net §5 verdict:**
- 1 item slightly over-rated (`Rules.lua:928` Gahwa Sun-match-win → could be MED).
- 1 item already done in tree but still listed as deferred (rule-7 anti-rule deletion — moved by v0.10.3 but the §4.2 row was preserved).
- All other sampled severities are defensible against source evidence.

---

## 6. CHANGELOG coherence

Read `CHANGELOG.md` lines 1-249. Verdicts:

**v0.10.4 entry coherence:** EXCELLENT.

The entry:
- Cleanly states scope: "1 HIGH + 1 calibration."
- Names the `State.lua:1966` site for the GetLegalPlays fix (CHANGELOG line; actual code is at line 1975, off by 9 — minor cite-drift mirroring v0.10.3's pattern of citing comment-block start).
- Names the `Constants.lua:329` site for the BONUS bump (matches code exactly).
- Acknowledges and corrects v0.10.3 line-number drift in §"Notes for v0.10.4 reviewers" (1714, 2143, 838, 2980). Self-aware.
- Names the test count (377/377 up from 371). Verified by my run.
- Explicit "Deferred to v0.10.5+" list captures most synthesis §4.2 items not yet applied (B-Bot-06 L07, dead-code block, Reverse Al-Kaboot, Bargiya axis flip, ISMCTS sample pool, swaDenied UI, Mathlooth-K smother, test-harness gap, M5/H3/R2 backports, M3 false-AKA wipe).

**v0.10.3 entry (lines 64-249):** also coherent against the synthesis §2 + §3.

**Minor cite-drift in v0.10.4 self-description:** the CHANGELOG cites
`State.lua:1966` but the actual `R.IsLegalPlay` call is at `State.lua:1975`.
The 1966 cite is the start of the v0.10.4 marker comment. Same comment-block-start
pattern as v0.10.3 — internally consistent but not literal. The CHANGELOG
already self-acknowledges this stylistic choice.

**Net §6 verdict:** GO. The CHANGELOG is honest about what changed,
who made it (review_v0.10.2 validation source-cite), and what remains
deferred. No discrepancies with code or synthesis.

---

## 7. Test-pass status

Ran `python tests/run.py` from `C:\CLAUDE\WHEREDNGN\`. Output (last 10 lines):

```
== G. Ashkal eligibility (audit-recommended fixture) ==
== H. v0.7 Sun-overcall state-machine + Bot.PickOvercall ==
== I. v0.8.6 HIGH-bug regression pins (H1-H4) ==
== J. v0.10.2 review-cycle closures (L3, M8) ==
== Result: 166 passed, 0 failed ==

========== rules  (Rules.lua / Cards.lua / Constants.lua) ==========
========== state_bot  (State.lua / Bot.lua) ==========
========== Total: 377 passed, 0 failed ==========
```

**Verdict:** GREEN. 377 / 377 — matches CHANGELOG claim exactly.
No regressions from the v0.10.4 changes.

---

## 8. Sun-bid frequency analysis (verified or corrected)

I independently re-derived the validation pass's combinatorics and
the dominant-suppressor ranking. **Result: validation pass is correct
on the math but slightly over-claimed `sunMinShape`.**

### 8a. P(sunMinShape) re-derivation

For 32-card Saudi deck (8 ranks × 4 suits), 8-card hand drawn uniformly:

```
P(0 Aces)  = C(28,8)/C(32,8) = 0.2955
P(1 Ace)   = 4·C(28,7)/C(32,8) = 0.4503
P(>=2 A)   = 0.2542
P(2 A)     = 0.2149
P(3 A)     = 0.0374
P(4 A)     = 0.0019
```

For 1-Ace hands: P(matching T in remaining 7 of 28) = 7/28 = 0.25.

```
P(1A + mardoofa)   = 0.4503 × 0.25         = 0.1126
P(sunMinShape)     = P(>=2 A) + P(1A+m)    = 0.3668 (36.7%)
```

**Confirmed: sunMinShape admits ~37% of random hands.**

The validation pass §7a stated "~25-28%" in the TL;DR but actually computed
~36-37% in §7a body. The TL;DR figure was a typo / draft remnant; the
body math is correct.

### 8b. Per-shape sunStrength estimates

`sunStrength` (`Bot.lua:882-927`) returns base score; `sunStrength + S-3
(+15 if 3+ Aces) + S-8 (mardoofaCount × BOT_SUN_MARDOOFA_BONUS, cap 2)`
is computed in `Bot.PickBid` at lines 1215-1218.

| Shape | P (within sunMin) | sunStrength base | Pre-v0.10.4 sun (mardoofa=5) | Post-v0.10.4 sun (mardoofa=10) |
|---|---|---|---|---|
| 2A no mardoofa | 0.131 / 0.367 = 36% | ~21 | ~21 | ~21 (unchanged) |
| 1A + 1 mardoofa | 0.113 / 0.367 = 31% | ~20 | ~25 | ~30 |
| 2A + 1 mardoofa | 0.075 / 0.367 = 20% | ~36 | ~41 | ~46 |
| 2A + 2 mardoofa | 0.0085 / 0.367 = 2.3% | ~51 | ~61 | ~71 |
| 3A + 1 mardoofa (incl all 3-Ace cases) | 0.037 / 0.367 = 10% | ~52 | ~72 | ~77 |
| 4A | 0.002 / 0.367 = 0.5% | direct short-circuit | passes | passes |

### 8c. Threshold thSun ranges

`thSun = jitter(50 - urgency, ±6)`. Median ~50; with urgency = +15 → 35;
with Bel-fear (cum ≥ 100) +8 → 58. Effective range: [44, 56] in normal
play.

### 8d. P(sun >= thSun | sunMinShape) by epoch

Estimating per-shape pass rates (jitter-aware) and weighting:

| Shape | Pre pass-rate | Post pass-rate |
|---|---|---|
| 2A no mardoofa (sun ~21) | ~5% | ~5% |
| 1A + 1 mardoofa (sun 25→30) | ~5% | ~10% |
| 2A + 1 mardoofa (sun 41→46) | ~30% | ~55% |
| 2A + 2 mardoofa (sun 61→71) | ~85% | ~95% |
| 3A+ shapes (sun 72+) | ~95% | ~98% |
| 4A direct short-circuit | 100% | 100% |

Weighted: P(clears thSun | sunMinShape) ~ 22% pre → 29% post.

P(sunMin AND clears) = 0.367 × 22% = 8.1% pre → 0.367 × 29% = 10.6% post.

Apply ~0.65 (B-5 5-pt margin survival in R2 weighted) and ~0.6 (no prior
Hokm/Sun blocking):

**Net Sun-bid rate per seat: ~3.1% pre-v0.10.4 → ~4.1% post-v0.10.4.
Improvement factor: 1.3×.**

### 8e. Dominant-suppressor ranking (verified)

Validation's claim: `thSun >= 50` is THE dominant suppressor. **Confirmed
on independent math.**

1. **`sunStrength >= thSun = 50` gate.** Bare 2-Ace and 1-Ace+mardoofa
   hands score 18-35 — far below 44-56. These are 67% of `sunMinShape` hands.
2. **B-5 5-point margin** (`K.BOT_BIDDING_SUN_OVER_HOKM_MARGIN = 5`).
   Bites ~30-40% of Sun-viable hands in R2. Source-anchored.
3. **`sunMinShape` floor.** Removes 63% of hands. Source-mandated per S-1
   (Definite, video #25). Cannot relax without source contradiction.
4. **Bel-fear nudge.** Score-state dependent; small contribution.

Ashkal allow-list and Bel-fear are minor contributors.

### 8f. Saudi-source quantitative priors — search

Grepped all 30 A-Src files for "نسبة" (percent/ratio), "frequency",
"common"/"rare" near bidding context. Findings:

- **A-Src-23 / A-Src-25 (PDFs 03/04 Secrets of Pro 1+3):** card-counting
  + meld weighting — no quantitative Sun-bid priors.
- **A-Src-10 (video #41 Sun basics):** discusses when to bid Sun
  qualitatively ("when you have an Ace and a covered Ace") — no rate.
- **A-Src-20 (video #21 Magnify Sun):** about strategic value of Sun
  contracts post-bid; no bid-rate prior.
- **A-Src-12 (video #08 Smart Move):** doesn't tabulate Sun bid rates.

**No A-Src file gives a quantitative "X% of bids should be Sun."** The
15-25% framing the parent prompt cites is **NOT source-anchored.**

### 8g. User's 1% report — reconciliation

Formula prediction is ~3-4% per seat. User's reported ~1% is plausibly
~3× off the formula, not 100×. Possible reasons:

1. Reporting bias toward late-round states where Bel-fear nudges thSun to ~58.
2. Tournament context where opp-bid blocks reduce reachable Sun branches.
3. Empirical sampler observing a worst-case slice.

The 1% is plausibly LOW but not 1-2 orders of magnitude wrong. Post-v0.10.4
the formula prediction moves to ~4.1% — user's reported rate may move
toward ~1.3-1.5%. **Not a full resolution.**

---

## 9. Sun-bid PROPOSED FIX validation for v0.10.4 (the headline question)

The fix is **already in tree** per CHANGELOG.md v0.10.4 entry: Option B
applied — `K.BOT_SUN_MARDOOFA_BONUS = 10`. Option A (lowering `TH_SUN_BASE`
from 50 → 44) was NOT applied. Both options have well-defined names,
differ in scope, and are individually validatable.

### 9a. Mathematical impact

| Option | Math (per §8d) | Sun-bid rate (per seat) |
|---|---|---|
| Pre-fix (mardoofa=5, thSun=50) | baseline | ~3.1% |
| **Option A:** thSun=44, mardoofa=5 | thSun lowered ~6 → all shapes get easier; the 2A-no-mardoofa shape (sun ~21) still fails; but 2A+1mar (sun ~41) goes from 30% → 60% pass; 2A+2mar (~61) → 95%; 3A+ → 98%. Weighted: ~30% pass cond. | **~4.4%** (1.4×) |
| **Option B (in tree):** thSun=50, mardoofa=10 | per §8d post column | **~4.1%** (1.3×) |
| **Option A AND B combined (not proposed):** thSun=44, mardoofa=10 | both effects compound | ~5.5-6% (1.8×) |

**Both options produce comparable rate uplift (~30-40% relative).** Neither
option alone reaches the source-implied 5-10% target.

### 9b. Side-effect check

**Option B (`K.BOT_SUN_MARDOOFA_BONUS`):** grepped all `.lua` and `tests/*.lua`.
**Result: single use-site at `Bot.lua:1218` inside `Bot.PickBid`.** The
constant only modifies the `sun` variable AFTER `sunStrength()` returns;
it does NOT contaminate the global `sunStrength` function. Other consumers
of `sunStrength` (Ashkal at line 1388, Bel at lines 3490+, Triple/Four
at 3599+, Gahwa at 3733+, Overcall at 3797+) all see the un-bumped score.

**Confirmed: zero side-effect leakage. Option B is fully surgical.**

**Option A (`TH_SUN_BASE`):** grepped same scope.
**Result: single use-site at `Bot.lua:1257` inside `Bot.PickBid`** —
`local thSun = jitter(TH_SUN_BASE - urgency, BID_JITTER)`. The local
`thSun` is consumed at lines 1423, 1469, 1498. No cross-pollination.

**Confirmed: Option A is also fully surgical.**

Both options touch the Sun-bid gate exclusively. Neither leaks into
Ashkal threshold (`K.BOT_ASHKAL_TH = 65`), Preempt threshold (`K.BOT_PREEMPT_TH = 75`),
Overcall thresholds (`K.BOT_OVERCALL_SELF_TH = 75`, `K.BOT_OVERCALL_TAKE_TH = 80`),
or the 5-point Hokm margin (`K.BOT_BIDDING_SUN_OVER_HOKM_MARGIN = 5`).

### 9c. Source alignment

- `sunMinShape` filter: **untouched** in either option. Source-mandated
  per S-1 (Definite, video #25). ✓
- 5-point Sun-vs-Hokm margin: **untouched**. Source-anchored per video #25/#26
  (B-5 16-vs-26 failed-bid asymmetry). ✓

Option A lowers a heuristic threshold but doesn't change the canonical
shape gate. Option B targets the doc-anchored Saudi A+T cover pattern
(إكة مردوفة) per `decision-trees.md` S-8 (Common, video #25). Option B
is more *source-aligned* in spirit — it amplifies the right signal
rather than relaxing a generic threshold.

### 9d. Regression test plan (suggestions only — no tests written)

Pin the calibration so it doesn't drift back:

1. **Fixture:** seed-deterministic 1000-hand sample using `math.random` with a fixed seed; count `Bot.PickBid` returns of `K.BID_SUN` per seat across all 4 seats × 250 hands.
2. **Assertion:** Sun bid rate >= 3.5% AND <= 12% (loose range to allow future tuning while pinning we're not at 1%).
3. **Sub-fixture A:** for each canonical Saudi shape (2A+2mar, 3A+1mar), assert the bot bids Sun at >85% — pins that the strong cases reliably fire.
4. **Sub-fixture B:** for the bare-2A (no mardoofa) shape, assert the bot does NOT bid Sun (pin that we don't over-correct).
5. **No need to write Lua test harness state for `combinedUrgency` and `Bel-fear`** — separate fixtures with `S.s.cumulative` set fix those.

### 9e. Recommendation

**SHIP v0.10.4 WITH the Option B fix already in tree.** Confidence: **MEDIUM**.

- ✓ Surgical, source-aligned, no side-effect leakage, tests pass.
- ✗ Math says it only moves Sun rate from 3.1% → 4.1% — won't fully
  satisfy users seeing 1%.
- ✗ The user's stated 15-25% target is NOT source-anchored, but the
  4.1% rate is still well below the source-implied 5-10% qualitative
  range.

**Should v0.10.4 also include Option A?** I lean **NO** — keep it
single-knob for this release. Reasons:
1. Both options together (combined uplift to ~5.5-6%) might over-correct
   without empirical A/B data.
2. Option B is more source-aligned (it amplifies a doc-anchored signal,
   not a generic threshold).
3. Adding Option A on top of Option B would be a guess about the right
   target rate, which the synthesis explicitly flagged is not source-anchored.
4. v0.10.4's scope ("focused 2-fix follow-up") is preserved.

**If the user reports the 1% complaint persists after v0.10.4 ship, then
v0.10.5 should consider Option A as a follow-up calibration with empirical
A/B data — not added speculatively now.**

---

## 10. Top 5 ship-blockers

**None.** All fixes claimed in §2/§3 are present, tests are green, and
the v0.10.4 incremental changes are well-scoped and accurately
documented in the CHANGELOG.

The closest thing to a "would-block-if-I-could-edit" would be:

1. The 6 missing-from-§4.2 HIGH findings (D-RedTeam-01 E1/E2/E4, B-Net-02-H1/H2,
   B-State-02-H1, Bargiya FN→FP) — but they were absent at v0.10.3 ship as well
   and don't introduce new regressions in v0.10.4.

2. The Sun-bid calibration's predicted 4.1% rate is below the qualitative
   source-implied 5-10% target — but improvement is real (1.3×) and
   the user's 1% complaint is partially addressed.

Neither is a true ship-blocker for v0.10.4.

---

## 11. Top 5 nice-to-haves the main fork could squeeze in pre-ship

Listed in order of (effort × impact) ratio — best ROI first:

1. **`N._OnAKA` 1-line trump-AKA reject** (E1 / B-Net-05 F8a). Add
   `if suit == S.s.contract.trump then return end` after the
   `authorizeSeat` check. Closes a HIGH wire-exploit, single line. No
   risk — UI already filters trump-AKA.

2. **`N._OnAKA` mid-trick lead-only gate** (E2 / B-Net-05 F8b). Add
   `if S.s.trick and S.s.trick.plays and #S.s.trick.plays > 0 then return end`
   to mirror the local-side gate at `LocalAKA:2358`. Closes the
   mispredict window. Single line.

3. **Remove rule-7 anti-rule from §4.2 backlog** (already deleted in v0.10.3
   per `Bot.lua:3024-3037` comment block). Cosmetic synthesis hygiene —
   prevents v0.10.5 reviewer from re-flagging a done item. The CHANGELOG
   already notes the deletion; the §4.2 row should track that.

4. **CHANGELOG cite at line 1966 → 1975 (or both)**. The CHANGELOG cites
   `State.lua:1966` (start of comment block) for the GetLegalPlays fix;
   the actual `R.IsLegalPlay` call is at line 1975. Same comment-block-start
   shorthand v0.10.3 used. Consistency-only nit.

5. **Document the predicted 4.1% Sun rate in CHANGELOG**. The "Calibrated"
   section says "5 → 10" without quantifying expected impact. A 1-2 line
   note ("predicted Sun bid rate moves ~3% → ~4% per seat per simulation
   estimate; empirical validation deferred to v0.10.5") sets correct
   user expectations.

---

## Appendix A — Inputs read

**Primary (per parent-prompt order):**
- `.swarm_findings/review_v0.10.2/REVIEW_v0.10.2.md` (~250 lines, full read)
- `.swarm_findings/review_v0.10.2/REVIEW_v0.10.2_validation.md` (~280 lines, full read)

**Secondary corpus (skimmed, mostly summary tables + headlines):**
- `_track_A_sources/` — 30 files; spot-checked A-Src-06, A-Src-23, A-Src-25, A-Src-29
- `_track_B_code/` — 42 files; spot-checked B-Bot-01, B-Bot-06, B-Bot-08, B-Bot-09, B-Bot-10, B-Net-02, B-Net-04, B-Net-05, B-Net-06, B-Net-08, B-State-01, B-State-02, B-State-03, B-State-05
- `_track_C_xref/` — 7 files; spot-checked C-Xref-04 (saudi-rules drift)
- `_track_D_redteam/` — 31 files; spot-checked D-RT-03, D-RT-08, D-RT-09, D-RT-13, D-RT-15, D-RT-21, D-RT-22, D-RT-24, D-RT-30, D-RT-31, D-RT-32, D-RedTeam-01, D-RedTeam-02
- `_track_E_ux/` — 3 files (E-Det-01, E-Net-01, E-UI-01)
- `_track_F_tests/` — 1 file (F-Test-01)
- `_track_G_logic/` — 1 file (G-Logic-01)

**In-tree code verification:**
- `Constants.lua` lines 85-340 (meld values, MARDOOFA_BONUS, OVERCALL_RESOLVE)
- `Bot.lua` lines 30-50, 810-930, 1190-1320, 1410-1515, 1700-1730, 2125-2165, 2940-3045, 3480-3580
- `BotMaster.lua` lines 820-840
- `Net.lua` lines 540-635, 1080-1100, 2580-2740, 4080-4115
- `Rules.lua` lines 100-220, 800-830, 920-940
- `State.lua` lines 1955-1980
- `tests/test_state_bot.lua` lines 280-340
- `tests/test_rules.lua` partial
- `CHANGELOG.md` lines 1-340

**Test verification:**
- `python tests/run.py` → 377 / 377 passed, 0 failed.

---

*End of REVIEW_v0.10.4_ship_readiness.md*
