# pickLead / pickFollow Audit (v3.2.1 design pass)

**Repo:** `C:\CLAUDE\WHEREDNGN`
**Main / origin main:** `99299b8` (post-v3.2.0 ship)
**Last shipped tag:** `v3.2.0`
**Scope:** read-only audit. No runtime / test / TOC / .pkgmeta edits.

---

## TL;DR

Five parallel audits of `pickLead` (Bot.lua:1039-2885) and `pickFollow`
(Bot.lua:2963-5348) — together 70% of Bot.lua post-v3.2.0 restructure
— surface **37 findings** spanning unreachable branches, stale-comment
drift, duplicated heuristics that bypass the v1.1.0 unpredictability
fix, doc-vs-code play discrepancies, and untested Saudi-canonical
branches.

The single most important finding: **L-2 — blind Ace leads in 4
sibling bidder-team branches** ignore observed opponent voids. Every
Hokm game where an opp has shown a side-suit void will, in mid-game,
trigger one of these 4 paths and feed the opp a free 11-point ruff.
A void-aware fix already exists at Bot.lua:1244-1257 (v3.1.2 Q4) but
was applied to one site only.

Second: **L-1 / U-1 (cross-confirmed by 2 independent agents)** — the
entire ~142-line v1.4.4 "pos-3 Sun hold-back" branch (Bot.lua:4422-
4564) is **unreachable code**. Its `pos2Lower` predicate implies
`partnerWinning`, but the branch sits below a `if partnerWinning then
return` at Bot.lua:3309. Saudi-pro «تخليه يمسك» play never executes.

Third: **U-2** — the `underContractPressure` bypass for Sun T-deferral
(Bot.lua:2563-2582) has a trick-count gate inversion that makes the
bypass non-functional. Sun bidder-team bots failing fast at tricks 1-3
keep deferring the T-boss instead of taking, the opposite of what the
v1.4.8 fix narrative intended.

**Recommended v3.2.1 batch shape:** 4-5 targeted fixes (L-2, U-2,
L-1/U-1, L-9, optionally D-1/D-2) plus 5 new behavioral tests for the
HIGH-coverage gaps that protect those fixes. Estimated diff: ~200-300
lines, all on `Bot.lua` runtime + `tests/test_state_bot.lua`. CHANGELOG
framing flips from v3.2.0's "no behaviour change" to v3.2.1's
"corrects 4 documented bot mistakes; reduces blind-ruff loss in Hokm
and dead-branch loss in Sun".

---

## Method

5 independent agents, each scoped to one angle. All read-only. Each
agent capped at 8-12 findings to keep the synthesis reviewable. Two
findings (L-1, U-1) were independently surfaced by Audit A (unreachable)
and Audit D (logic errors) from different starting points — strong
cross-confirmation.

| Audit | Angle | Findings | HIGH |
|---|---|---|---|
| A | Unreachable branches | 3 | 1 |
| B | Stale comments vs behaviour | 6 | 2 |
| C | Duplicated heuristics | 8 | 3 |
| D | Logic errors vs `docs/strategy/` | 10 | 2 |
| E | Test coverage gaps | 10 | 5 |
| **Total** | | **37** | **13** |

Cross-confirmation:

- **L-1 ≡ U-1**: pos-3 Sun hold-back branch dead. (Logic-error angle
  found "doc-canonical play never fires"; unreachable angle found the
  predicate `pos2Lower` unsatisfiable under the enclosing scope.)
- **L-1 → T-5**: Audit E flagged "no test for pos-3 K-doubled bait" —
  Audits A and D explain *why* nobody wrote that test: the branch
  cannot fire, so it can't be exercised.
- **L-4 → T-7**: Audit D flagged "Hokm deceptive-overplay forbids the
  canonical J-trump sacrifice" — Audit E flagged "deceptiveOverplay
  has no tests". Both point at Bot.lua:4811-4898.

---

## §1 Findings ranked by gameplay impact

### CRITICAL (regular EV loss every game)

#### **F1 — L-2: Blind A-leads ignore opp voids (4 sites)**

- **Lines:** Bot.lua:2038-2044, 2080-2086, 2167-2171, 2354-2364
- **Bug:** Each bidder-team / bidder-self A-cash arm iterates `legal`
  and returns the first non-trump Ace, with NO `anyOpponentVoidIn`
  check.
- **Doc / prior fix:** Bot.lua:1244-1257 (v3.1.2 Q4 Fix #1) already
  implements the void-aware guard via `opponentsVoidInAll(seat, su)`
  for the "highest unplayed" path. The 4 sibling A-cash branches were
  not patched in v3.1.2.
- **Impact:** Every Hokm game where an opp has shown a side-suit void
  (very common from earlier ruff or void-discard), the bidder will,
  in trump-poor or conservativeOpp / J+9-lock / bidder-drought
  branches, cash the A blindly. Opp ruffs with low trump and wins.
  Mean EV loss per occurrence: ~11 face-value + tempo + cascading
  trump-pull derail.
- **Repro:** Hokm-S bidder seat 4 holds J♠+9♠+8♠+A♥+K♥. Opp seat 3
  ruffed a heart trick earlier (`Bot._memory[3].void[H]=true`).
  Trick 4 lead, bidder enters `trumpCount<4` branch (line 2038),
  returns A♥. Seat 3 ruffs with low trump.

### HIGH (frequent EV loss, dead doc-canonical play, or
predictability tells)

#### **F2 — L-1 / U-1: pos-3 Sun hold-back is unreachable (cross-confirmed)**

- **Lines:** Bot.lua:4422-4564 (the entire v1.4.4 «تخليه يمسك» branch)
- **Bug:** `pos2Lower = (not pos2InLead) or (p2tr < p1tr)` implies
  partner is currently winning. The branch sits inside `if #winners
  > 0 then` (line 4099), reached only after `if partnerWinning then
  return` at Bot.lua:3309 has fallen through. The conjunction
  `partnerWinning=true ∧ partnerWinning=false` is unsatisfiable.
- **Doc:** opening-leads.md "Deviation 1 — Hold back when partner is
  the boss" (Sometimes, video #20). decision-trees.md §11 row 297.
- **Impact:** Documented Saudi-pro "psychological-bait K-save" play
  never executes. ~142 lines of code, including a Saudi-Master 40%
  fire-rate, all dead. pos-3 always takes with K via fallthrough.
- **Repro:** Sun M3lm at pos-3, partner leads 9♥, opp 8♥, hand
  {K♥, 7♥, A♦, ...}. Expected: 7♥. Observed: K♥.

#### **F3 — U-2: `underContractPressure` bypass dead (gate inversion)**

- **Lines:** Bot.lua:2563-2582
- **Bug:** `underContractPressure` computed only when `trickCount >= 4`
  (line 2564). `roundEndDeferActive` gated by `trickCount <= 3` (line
  2581). Mutually exclusive. When `trickCount <= 3`,
  `underContractPressure` stays `false` from line 2563 default; the
  `and not underContractPressure` term is vacuously true.
- **Doc:** v1.4.8 audit-HIGH-2 narrative: "take the T-boss now —
  contract failure is the bigger risk than burning the round-end T."
- **Impact:** Sun bidder-team bot at tricks 1-3 with `raw <
  baseTarget - 30` (heavy score deficit, no partner-win yet) keeps
  deferring T-boss instead of grabbing. Direct play change in
  bidder-failing-fast Sun scenarios.
- **Fix shape:** Hoist the `underContractPressure` computation out of
  the `trickCount >= 4` gate (it's needed for the `<=3` bypass).

#### **F4 — L-9: F-16 K-cover veto wrongly suppresses Hokm Faranka Exception #3**

- **Lines:** Bot.lua:3969-3977
- **Bug:** F-16 anti-rule requires K-of-trump cover; vetoes Faranka
  if absent. Correct for Exception #2 (only 2 trumps, posture-weak).
  WRONG for Exception #3 — when J of trump is already dead and our
  9-of-trump IS the new boss, "K-cover" is meaningless because no
  higher trump remains in the round.
- **Doc:** decision-trees.md §10 row 278 (Common, video #04): "Hokm
  exception #3: J of trump already played/dead, your 9 is now top
  live trump → Faranka allowed."
- **Impact:** Hokm bidder-team bots holding 9-of-trump as new boss
  but no K-of-trump skip the canonical withhold and waste the
  9-as-boss on a routine cover.

#### **F5 — D-1: 4 inline `highestByRank`-shaped loops bypass tie randomization**

- **Lines:** Bot.lua:2026-2033, 2616-2626, 4409-4419, 4477-4488
- **Bug:** Each loop uses strict `>` and breaks ties by hand-iteration
  order. The canonical `Primitives.highestByRank` (PlayPrimitives.lua:
  63-74) randomizes ties — that's the v1.1.0 HIGH-1 unpredictability
  fix.
- **Impact:** A careful human observer reading the bot's tie-break
  choices over multiple rounds can infer the bot's internal hand
  iteration order — the exact tell v1.1.0 retired in the primitive.
  Affects ~5-10% of mid-game plays where rank-ties occur in legal.
- **Fix:** Each of the 4 loops can call `highestByRank` over a
  pre-filtered list. Pattern repeated, low risk per site.

#### **F6 — D-2: BotMaster forced-ruff override bypasses tie randomization**

- **Lines:** BotMaster.lua:1191-1203
- **Bug:** Same class as D-1, in the Saudi-Master tier ISMCTS path.
  When forced-ruff legal is all trump with rank ties, picks first
  iteration order; pickFollow's parallel branch (Bot.lua:3796-3807)
  goes through `lowestByRank` with randomized ties.
- **Impact:** Saudi Master tier silently diverges from M3lm/Fzloky on
  tie-break behaviour. Same predictability concern as F5 but
  specifically at the highest tier.

#### **F7 — D-7: `tahreebClassify` caller suit-iteration drift**

- **Lines:** Bot.lua:1290 (uses `shuffledSuits()`), Bot.lua:4848 /
  4998 / 5039 (use fixed `{"S","H","D","C"}`)
- **Bug:** 3 of 4 callers of the same per-suit Tahreeb-classifier
  scaffolding use deterministic suit order. Currently benign because
  the 3 sites use the result as boolean. Fragile pattern: a future
  change that returns the matched suit instead of a flag instantly
  becomes a spades-first tell.
- **Doc:** v1.1.0 audit unpredictability HIGH-1 explicitly retired
  fixed-order iteration in classifiers.

#### **F8 — Test coverage gaps in Saudi-canonical "Definite" branches**

Five HIGH-risk gaps from Audit E without behavioural tests:

| Tag | Branch | Doc ref | Impact |
|---|---|---|---|
| T-1 | Hokm Faranka exceptions #2/#3/#4 (Bot.lua:3842-4021) | decision-trees.md §10 (Definite, video 04) | Only way bot duck-trumps; gate flip strands tricks |
| T-2 | Sweep-pursuit-early Kaboot lead (Bot.lua:1081-1190) | decision-trees.md §7 (Common, video 15) | Kaboot bonus 250 raw / 440 effective in Sun |
| T-4 | Sun pos-4 Faranka 5-factor (Bot.lua:3098-3307) | decision-trees.md §5 (Definite, video 06) | One regressed factor flips ~10% of pos-4 Sun |
| T-6 | Tahreeb sender "want, no Ace" bottom-up (Bot.lua:3604-3644) | decision-trees.md §8 (Definite, video 01/09/10) | 2nd-most-cited Tahreeb form, partnership signal |
| T-10 | Tahreeb-return T-supply count≥3 want (Bot.lua:1769-1781) | decision-trees.md §8 (Definite, video 10) | "100% reliable" per video; source-pin only |

### MED (subtle EV loss, niche shapes)

| Tag | Lines | Subject |
|---|---|---|
| L-3 | Bot.lua:5173-5212 | Tanfeer N-1 sender fires at pos-2 (uncertain winner) instead of falling back to Tahreeb default per decision-trees.md §9 row 256 ("تهريب اقوى من تنفير") |
| L-4 | Bot.lua:4822-4831 | Hokm deceptive-overplay's blanket J/9-trump exclusion forbids the canonical row 116 «الولد» J-sacrifice play |
| L-5 | Bot.lua:5103-5147 | Mathlooth K-tripled trickle placed in opp-winning fork only; partner-led case can donate K via smother before trick 3 |
| L-6 | Bot.lua:2535-2630 | Sun "establishing" lead fires for T-boss after A is gone; loses T to opp's K-cover (mathlooth) |
| D-3 | BotMaster.lua:1033-1037 | `buildLegalSet` duplicates `legalPlaysFor`; AKA-receiver relief edits won't reach Saudi-Master tier |
| D-6 | Bot.lua:3127, 4477 | "Highest cover" loop pattern with strict `>` ties (same class as D-1) |
| S-3 | Bot.lua:2768-2772 | `forceOwnInitiative` consumer cites Bot.lua:3632-3634 and 3655 — both wrong line refs, actively misleads maintainer chasing the flag's writer↔reader contract |
| S-6 | Bot.lua:4844-4846 | "Other 3 callers (Bot.lua:2696, 2775, 5317, 5358) correctly use tahreebClassify(...)" — none of those 4 lines call tahreebClassify; also "3 callers" then lists 4 |
| T-3 | Bot.lua:4266-4348 | pos-2 deception v1.6.0 anti-triggers untested (trump-suit gate, A/J exclusion, pos-3/4 known-void) |
| T-7 | Bot.lua:4811-4898 | `deceptiveOverplay` no tests — overlaps L-4 |
| T-8 | Bot.lua:4899-4924 | `opponentBargiyaSuit` consumer no behavioural |

### LOW (cosmetic, dead-arm with no impact, or already-deferred)

| Tag | Lines | Subject |
|---|---|---|
| U-3 | Bot.lua:4571-4572 | `if #winners == 0` arm inside `if #winners > 0` enclosing scope — defensive but unreachable; no play change |
| L-7 | Bot.lua:3552-3601 | Sun T-1 Bargiya sender picks first-matching suit; should prefer strongest-cover suit |
| L-8 | Bot.lua:2183-2198 | A-trump preservation gate `tricks < 5` — late-trick preservation also wanted, but rare hand shape |
| L-10 | Bot.lua:5103-5124 | Mathlooth trickle correctly gates `tricks ≤ 2` but no explicit trick-3 K-cash bias |
| D-4 | Bot.lua:1978, 3863 | Trump-count loops (intentional input difference: `legal` vs `hand`) |
| D-5 | Bot.lua:3821, PlayPrimitives:363 | Non-trump filter pattern; cosmetic |
| D-8 | Bot.lua:4337, 4399, 4544 | Chained nil-safe `Bot._memory[opp].void[lead]` reads; cosmetic |
| S-1 | Bot.lua:1859-1861 | topTouchSignal READ-side cites wrong write-site line |
| S-2 | Bot.lua:2207-2209 | pickFollow trump-winners cross-ref points at unrelated helper body |
| S-4 | Bot.lua:2862-2864 | Belote sub-filter cites stale L1453 (was post-Batch-extraction) |
| S-5 | Bot.lua:3617-3618 | Tahreeb receiver decoder cites unrelated Sun-drought tracker line |
| T-9 | (not implemented) | Mathlooth K-tripled leader-side exploit — doc-flagged `(not yet wired)` |

---

## §2 Proposed v3.2.1 fix batch (smallest safe shape)

### §2.1 Scope

**Tier-1 (CRITICAL + HIGH only, no test debt):**

| # | Fix | Lines touched | Risk |
|---|---|---|---|
| A | F1 / L-2: add `anyOpponentVoidIn` guard to 4 A-cash sites | Bot.lua:2038, 2080, 2167, 2354 (1 condition each) | LOW — pattern proven at L1244 |
| B | F3 / U-2: hoist `underContractPressure` computation outside the `trickCount >= 4` gate | Bot.lua:2563-2580 (5-line refactor of computation order) | LOW — restores documented behaviour |
| C | F4 / L-9: F-16 carve-out — skip K-cover veto on Exception #3 (J-dead) | Bot.lua:3969-3977 (1 condition) | LOW — narrows over-restriction |
| D | F2 / L-1+U-1: dead-branch decision | Bot.lua:4422-4564 | See §2.2 |

**Tier-2 (predictability fixes — class-grouped):**

| # | Fix | Lines touched | Risk |
|---|---|---|---|
| E | F5 / D-1: replace 4 inline highestByRank-shaped loops with primitive calls | Bot.lua:2026, 2616, 4409, 4477 | MED — semantic-preserving but each site is a real edit |
| F | F6 / D-2: route BotMaster forced-ruff override through `lowestByRank` | BotMaster.lua:1191 | MED — Saudi-Master tier change |

**Tier-3 (test debt):** add 5 behavioural tests for HIGH gaps T-1,
T-2, T-4, T-6, T-10 (§ Audit E proposed assertion shapes). Each test
is ~20-30 lines in `tests/test_state_bot.lua` AY/AZ-style sections.

### §2.2 The L-1/U-1 decision

Three options:

- **(D-a) Delete the dead 142 lines.** Loses the Saudi-pro convention
  but is the safest v3.2.1 change. Doc comment added to point at
  future-wire.
- **(D-b) Move the hold-back ABOVE the `if partnerWinning then return`
  at Bot.lua:3309** so it fires when partner is currently winning
  (which `pos2Lower` implies). Restores the «تخليه يمسك» play. Requires
  careful gate verification; medium risk.
- **(D-c) Keep dead, just add a `-- DEAD: see v3_2_1_pickplay_audit.md
  F2` comment.** Lowest risk; preserves narrative continuity.

**Recommendation for v3.2.1:** option **(D-c)** — flag in comment,
defer (D-b) to v3.3.0 where a focused gameplay-fix branch can
behaviourally test the move. Option (D-a) loses code that we may
still want; option (D-b) is the right fix but requires its own audit.

### §2.3 Out of scope for v3.2.1

The following are deferred:

- All LOW findings (U-3, L-7, L-8, L-10, D-4/5/8, S-1/2/4/5, T-9).
- MED logic findings L-3, L-4, L-5, L-6 — each is a behaviour change
  warranting its own audit + test pair. Grouping them risks the kind
  of "many small changes" batch that's hard to bisect.
- All MED stale-comment findings unless they touch a Tier-1 fix.
- The full L-1/U-1 reactivation (D-b) — separate audit needed.

### §2.4 Safety plan

Mirroring the v3.2.0 Codex-reviewed batch pattern:

1. **Branch:** `pickplay-fixes-v3.2.1` off `99299b8`.
2. **Per-fix commit:** one commit per Tier-1 fix (A, B, C, D-c) + one
   per Tier-2 fix (E, F) + one for the 5 new Tier-3 tests.
3. **Each commit must pass** `python tests/run.py` 1219+/0 (the 5 new
   tests bump the count). No fix may degrade an existing assertion.
4. **CHANGELOG framing** v3.2.1 — bug-fix release, list F1-F8 by
   doc-section, NOT by audit ID. User-facing description is "fixes 4
   documented bot mistakes" not "Codex audit closure".
5. **No protocol change, no saved-variable migration.** Existing
   v3.2.0 installs upgrade silently.
6. **Open Codex review BEFORE tag.** If Codex approves all 6 fixes
   + 5 tests, tag `v3.2.1`.

Estimated effort: 1-2 working sessions for the diff, 1 session for
Codex review, ~3 days total elapsed.

---

## §3 Cross-audit map

| Audit | F1 | F2 | F3 | F4 | F5 | F6 | F7 | F8 |
|---|---|---|---|---|---|---|---|---|
| A — Unreachable | — | U-1 | U-2 | — | — | — | — | — |
| B — Stale comments | — | — | — | — | — | — | — | — |
| C — Duplicates | — | — | — | — | D-1 | D-2 | D-7 | — |
| D — Logic errors | L-2 | L-1 | — | L-9 | — | — | — | — |
| E — Test gaps | — | T-5* | — | T-1 | — | — | — | T-1,T-2,T-4,T-6,T-10 |

`*` T-5 was "no test for pos-3 K-doubled bait" — explained by L-1/U-1
(branch is unreachable, hence untestable).

The agents found the same `forceOwnInitiative` issue (S-3) and
`tahreebClassify caller-list` issue (S-6) — both HIGH severity in the
stale-comment angle — independently. These are documentation-only
issues; not in the Tier-1 fix list but worth fixing alongside any
edit that touches Bot.lua:2768 or Bot.lua:4844 to avoid stranding a
maintainer.

---

## §4 Reference — exact lines for verification

For each Tier-1 fix, the lines a Codex reviewer needs to read:

**F1 / L-2 (blind A-leads):**
- Bot.lua:1244-1257 — existing void-aware pattern (use as template)
- Bot.lua:2038-2044, 2080-2086, 2167-2171, 2354-2364 — 4 sites
- Helper: Bot.lua:936-967 `anyOpponentVoidIn` (already exists)
- Helper: Bot.lua:918-934 `opponentsVoidInAll` (alternative,
  stricter)

**F3 / U-2 (underContractPressure dead bypass):**
- Bot.lua:2557-2585 — the full block including the gate
- Note: `partnerWonAny` (line 2560) is computed before the gate and
  used correctly; only `underContractPressure` is mis-gated

**F4 / L-9 (F-16 vs Exception #3):**
- Bot.lua:3842-4021 — full Faranka-exceptions block
- Bot.lua:3969-3977 — F-16 anti-rule site
- Cross-ref: decision-trees.md §10 (Exception #2 vs Exception #3)

**F2 / L-1+U-1 (pos-3 Sun hold-back):**
- Bot.lua:3309 — the `if partnerWinning then return` blocker
- Bot.lua:4099 — the `if #winners > 0 then` enclosing scope
- Bot.lua:4422-4564 — the dead 142-line v1.4.4 branch
- Bot.lua:4467-4473 — the `pos2Lower` predicate definition

**F5 / D-1 (highestByRank tie randomization):**
- PlayPrimitives.lua:63-74 — canonical `highestByRank` with
  randomized ties
- Bot.lua:2026-2033, 2616-2626, 4409-4419, 4477-4488 — 4 inline
  copies with strict `>`

**F6 / D-2 (BotMaster forced-ruff tie):**
- BotMaster.lua:1191-1203 — the override loop
- Bot.lua:3796-3807 — pickFollow's parallel path (uses
  `lowestByRank`)

---

## Final report (per prompt)

- **Doc path:** `.swarm_findings/v3_2_1_pickplay_audit.md`
- **Audits run:** 5 parallel (unreachable, stale comments,
  duplicates, logic errors, test gaps); 37 findings total, 13 HIGH+,
  2 cross-confirmed by two independent agents (L-1/U-1 and
  L-4/T-7)
- **Cross-audit verification:** L-2 (Bot.lua:2038) and U-2
  (Bot.lua:2563) re-read against current source and confirmed real
- **Critical finding:** F1 / L-2 — 4 sibling bidder-team A-cash
  branches lack the `anyOpponentVoidIn` guard that v3.1.2 Q4 Fix #1
  applied to one site; every Hokm game with an observed void
  triggers a blind A-into-ruff
- **Proposed v3.2.1 fix batch:** 4 Tier-1 fixes (F1, F3, F4, F2 as
  D-c comment-only flag) + 2 Tier-2 fixes (F5, F6) + 5 new
  behavioural tests for HIGH gaps T-1, T-2, T-4, T-6, T-10. Estimated
  diff ~200-300 lines.
- **No runtime / test / .toc / .pkgmeta edits in this audit pass.**
- **Working tree status:** clean on `main` at `99299b8`; no commits
  on this audit; only this design doc written, alongside the
  pre-existing untracked `.swarm_findings/v3_2_0_botlua_comment_audit.md`
  from the prior audit task.
