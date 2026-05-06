# B-Rules-02: `R.ScoreRound` review (v0.10.2, post-X5/R5/R2 collapse)

## Scope verified

- `R.ScoreRound` body: `Rules.lua:661-953`. The function comment block at `Rules.lua:647-660` plus the implementation through return at `Rules.lua:939-952`.
- Sub-pieces walked: trick-points + last-trick-bonus aggregation (`665-674`), Belote attribution (`692-709`), sweep override (`712-723`), Belote cancellation (`738-746`), threshold/outcome decision (`748-812`), scoring-branch dispatch (`816-862`), multipliers (`864-893`), Belote +20 raw post-mult (`898-912`), `div10` (`914-918`), Gahwa match-win flag (`920-937`).
- Cross-referenced: `Constants.lua:42-115` (point tables, hand totals, multipliers, kaboot, melds), `R.SumMeldValue` (`Rules.lua:503-507`), `R.CompareMelds` (`Rules.lua:343-353`), `R.DetectMelds` (`Rules.lua:220-290`).
- Sources: video #43 transcript `docs/strategy/_transcripts/-QrykaZdosE_43_score_calculation.ar-orig.srt` (rounding direction at lines 411-440, Hokm 162/Sun 130 hand totals at lines 481-491 and 360-368, divisor difference Hokm/10 vs Sun/5 at lines 539-547, fail/take/make outcome split at lines 363-376 and 533-548); PDF `02_playing_system.txt` lines 76-141 (Sun-no-Triple/Four/Gahwa, Belote-cancelled-by-100-meld-only); PDF `07_doubling_system.txt` lines 7-66 (Hokm 4-rung Bel/Triple/Four/Gahwa, Sun-only-Bel after >100, Belote not-doubled).
- Tests audited: Section G (lines 420-471), H (476-498), I (503-601), J (606-686), K (691-724), L (729-742), M (747-765).

---

## Summary verdict

**`R.ScoreRound` is largely correct post-v0.10.0 R2/R5/X5 cascade.** The make/fail/take/sweep dispatch matches the canonical Saudi rules (PDF 02 + PDF 07 + video #43). The Sun-multiplier collapse to ×Bel max (R2), Carré-A in Hokm = 100 (X5), Carré-A in Sun = 400 raw direct (R5), and the team-level Belote cancellation (M5) are all correctly wired in this function and produce the expected raw → game-point pipeline.

**However**, several issues remain:
- The function's docstring (lines 647-660) is missing FOUR fields actually returned (`sweep`, `belote`, `gahwaWonGame`, `gahwaWinner`, `raw`). Doc drift. (F-06)
- Belote sweep-override-then-cancellation order can resurrect a previously-cancelled belote on sweep (F-01).
- Reverse-Kaboot is documented (decision-trees.md, glossary.md, saudi-rules.md, video #16) but **not wired** in `R.ScoreRound` — defenders sweeping against bidder-led-trick-1 should award +88 raw to defenders. (F-02)
- Defensive normalization is asymmetric: the multiplier path collapses stale Sun-Triple/Four/Gahwa flags (line 884-887, R2 fix) but the Gahwa match-win branch (line 928-937) does not — a stale `gahwa=true` flag on a Sun contract still triggers `gahwaWonGame=true`. (F-03)
- `R.TeamOf(nil)` silently returns "B" (Rules.lua:25-28), so `R.ScoreRound` with `contract.bidder=nil` mis-attributes to team B without warning. No defensive guard at line 677. (F-04)
- Sweep-bonus-only-for-Hokm-or-Sun: the `sweepTeam` branch unconditionally awards `K.AL_KABOOT_HOKM` for non-Sun and `K.AL_KABOOT_SUN` for Sun (line 818). No condition checks for stale `gahwa` or other modifiers. Largely fine, noted for completeness. (F-09)
- Test coverage gaps: Section G has no direct strict-majority 81/81 tied-Hokm pin (covered only via Sun ties at section I); Section J has no test for sweep-resurrects-cancelled-belote (F-01 scenario); no integration tests in any section pass a non-trivial meld `{value=400}` through `ScoreRound` to validate Sun Carré-A scoring end-to-end (R5 verification gap); Section L doesn't pin the Sun-stale-gahwa case. (F-07)

The core scoring math is correct in the canonical paths; defects are at the edges (sweep+belote interaction, doc drift, defensive normalization, missing reverse-kaboot).

---

## Findings

### F-01 — Sweep override + Belote cancellation order can resurrect a previously-cancelled belote (MEDIUM severity)

**File:** `Rules.lua:721-746`.

**Issue:** The current sequence is:
1. Detect K+Q of trump in same hand → `belote = R.TeamOf(kWho)`.
2. Sweep override: `if sweepTeam and belote and belote ~= sweepTeam then belote = sweepTeam` — moves +20 to the sweeper.
3. Cancellation: walk `meldsByTeam[belote]` and zero `belote` if any meld value ≥ 100.

The cancellation check runs on the **belote-target** team's melds (post-sweep-override). But Saudi convention per PDF 02 line 140 ("ويلغى اذا كان معه مشروع المئة فقط") states the +20 is cancelled when the K+Q **holder** also has a 100-meld — it's a property of the original Belote declaration, not contingent on which team eventually receives the +20.

Concrete scenario:
- Hokm-H. Seat 2 (team B) holds KH+QH and a 5-card heart sequence (seq5 = 100). Per Saudi: B's belote is cancelled at meld declaration, so +20 doesn't exist for the round.
- Team A sweeps all 8 tricks.
- Code: belote = "B" (step 1), then sweep-override → belote = "A" (step 2), then cancellation walks `meldsByTeam.A` (step 3). If A has no 100-meld, belote stands → A gets 250 + 20 = 270 raw.
- Per Saudi (cancellation-is-permanent reading): there is no +20 to award. A gets only 250 raw.

The comment at `Rules.lua:725-737` explicitly defends the current order with "sweeper discards loser's melds" — but that's the meld-points scoring rule (line 821-822), not the Belote rule. The Belote +20 is independent of meld-points winner-takes-all per `Rules.lua:898-912` ("Pagat: 'Baloot always 2 points unaffected'"). So whether the loser's melds get scored is moot — the question is whether the +20 ever existed at all.

**Source:** PDF 02 line 140 ("the Belote is cancelled if accompanied by the 100-meld only"); video transcripts have no direct sweep+cancelled-belote example, so this falls into "interpretation" rather than "stated rule". Both readings are defensible, but the current code's reading is non-canonical: most Saudi sources phrase Belote cancellation as a property of the original declaration, not the post-redirect target.

**Recommendation:** Move the cancellation check BEFORE the sweep override. Or, more conservatively, run cancellation against the **original** K+Q-holder's team melds (cache `originalBeloteTeam = R.TeamOf(kWho)` before the sweep override), not against the post-override team. Either way, document the chosen interpretation prominently. Add a Section J test that exercises this case: `Hokm Hearts, seat 1 (A) holds KH+QH+seq5-hearts, B sweeps`. Expected raw.B = 250 (no +20).

**Confidence:** MEDIUM. The Saudi sources do not explicitly cover the sweep+cancelled-belote intersection. The current code's behavior is a defensible interpretation, but inconsistent with the most natural reading of "the belote is cancelled" as a permanent state. User-impact is small (rare configuration), but score off by 2 game-points per hit.

---

### F-02 — Reverse-Kaboot not wired (LOW severity, KNOWN)

**File:** `Rules.lua:711-723` (sweep branch detects sweepTeam but does not differentiate bidder-side vs defender-side sweep).

**Issue:** Per video #16 (`16_reverse_kaboot_extracted.md` lines 12-23, 55-62), `decision-trees.md` line 187, `glossary.md` line 97, and `saudi-rules.md` lines 105-109, when **defenders sweep all 8 tricks AND the bidder led trick 1** (which is the gating condition per video #16 lines 9-12), defenders earn an additional +88 raw bonus distinct from the regular Al-Kaboot value.

The current sweep branch (line 818) awards `K.AL_KABOOT_HOKM=250` or `K.AL_KABOOT_SUN=220` to the sweeping team without checking who the bidder was or who led trick 1. So a defender-sweep against the bidder lands at the same 250/220 value as a bidder-sweep, missing the Reverse-Kaboot differential.

**Source:** All references documented as `(not yet wired)` in `glossary.md` and `decision-trees.md`. Video #16 explicitly notes the 88-vs-equivalent dispute (lines 12-14: "كبوت المقلوب نقاطه 88 للكبوت العادي باربعين وبعض الناس يعتبر الكبوت المقلوب كانه الكبوت العادي" — "Reverse Kaboot is 88; regular Kaboot is at 40; some treat Reverse as the same as a regular Kaboot"). Single-source from video #16; corroboration was deferred pending more transcripts.

**Recommendation:** Either (a) wire it under a proposed `K.AL_KABOOT_REVERSE = 88` constant with the gating predicate `defenderSweep && firstLeader == bidder`, or (b) add an explicit comment near the sweep branch acknowledging the absence and the single-source-pending-corroboration status. Note: the function currently has no tracking of trick-1 leader (would need to read `tricks[1].plays[1].seat`). If wired, also update `K` constants and add Section H tests.

**Confidence:** HIGH that the feature is unwired. MEDIUM on whether to wire it now — single-source with internal disputes about value.

---

### F-03 — Asymmetric defensive normalization for Sun + stale escalation flags (MEDIUM severity)

**File:** `Rules.lua:884-893` (multiplier — collapses) vs `Rules.lua:920-937` (Gahwa match-win — does not collapse).

**Issue:** The R2 fix (v0.10.0) defensively collapses stale Sun-Triple/Four/Gahwa multiplier flags to Sun×Bel maximum at the multiplier site. The comment block at lines 873-882 explicitly motivates this with "stale resync, hand-edited save, etc."

But the Gahwa match-win branch at lines 920-937 fires unconditionally on `if contract.gahwa then`. If a Sun contract somehow has `gahwa = true` set (the same stale-state vector R2 protects against), the Gahwa branch will set `gahwaWonGame = true` and pick a `gahwaWinner` based on `bidderMade`. Per PDF 02 line 81 + PDF 07 line 60, **Sun has no Gahwa rung** — this should not fire.

The R2 fix's tie-inversion path also collapses `gahwa→none` for Sun contracts at line 800-801 ("highest = contract.doubled and 'double' or 'none'"). So tie inversion is safe. The MULTIPLIER path is safe. Only the gahwaWonGame branch is exposed.

Net consequence: a Sun-with-stale-gahwa-flag contract triggers a match-win branch that should not exist for Sun.

**Source:** PDF 02 line 78-81 ("ففي الصن اليوجد الثري والفور والقهوة"); PDF 07 line 57-60 ("نظام الدبل بالصن... دبل فقط"). The R2 fix in v0.10.0 codifies this defensively elsewhere; the Gahwa branch is the missing site.

**Recommendation:** Wrap line 928 in `if contract.type == K.BID_HOKM and contract.gahwa then`. Or, normalize at function entry: `local gahwa = contract.gahwa and contract.type == K.BID_HOKM`. The phase machine (`State.ApplyDouble`) already prevents this state in normal play, so this is purely defensive — but it parallels the R2 multiplier collapse at line 884.

**Confidence:** HIGH on the gap. MEDIUM on the impact (depends on how reachable the stale state is in practice; R2's existence acknowledges it's reachable).

---

### F-04 — `R.TeamOf(nil)` silently returns "B"; `R.ScoreRound` has no nil-bidder guard (LOW severity, defensive)

**File:** `Rules.lua:25-28` (`R.TeamOf` definition); `Rules.lua:677` (the call site in `R.ScoreRound`).

**Issue:** `R.TeamOf` is defined as `if seat == 1 or seat == 3 then return "A" end; return "B"` — the fallthrough branch returns "B" for ANY non-{1,3} input including nil, false, "", and unexpected seats like 5. `R.ScoreRound` calls `R.TeamOf(contract.bidder)` at line 677 without checking. If `contract.bidder` is nil (or some other invalid value), `bidderTeam = "B"` silently — and `oppTeam = "A"` — and the entire scoring proceeds as if team B were the bidder.

This isn't a logic bug per se if all callers always provide `contract.bidder`. Greppable callers (`State.lua:1924`, `Net.lua:3038`, `BotMaster.lua:793`) appear to pass real contracts. But silent misclassification on a nil-edge is undesirable, especially since some adjacent code (`R.CanBel` line 552-577) handles nil bidder explicitly.

**Source:** Defensive observation. No source of truth requires this guard; the R5/X5 audit trail focused on meld values, not bidder nil-handling.

**Recommendation:** Either (a) guard at function entry: `if not contract or not contract.bidder then return nil end` (or similar early-out), or (b) make `R.TeamOf` strict: `if seat == 1 or seat == 3 then return "A" elseif seat == 2 or seat == 4 then return "B" else return nil end`. Option (b) propagates: many call sites compare `R.TeamOf(seat) == "A"` which would silently become false, but a nil return is at least visible. Option (a) is the smaller blast radius.

Same observation applies to `meldsByTeam = nil` at line 680-681 (no `meldsByTeam and meldsByTeam.A or {}` defense, contrast with line 739 which does have the defense).

**Confidence:** HIGH on the nil-handling asymmetry. LOW on real-world impact (no caller is known to pass nil bidder).

---

### F-05 — Bidder-team-trick-1-leader not tracked in result struct (LOW severity, blocker for F-02)

**File:** `Rules.lua:939-952` (return struct).

**Issue:** The Reverse-Kaboot gating predicate (F-02) requires knowing who led trick 1. The result struct does not export this. The function has access to `tricks[1].plays[1].seat` but doesn't compute or expose `firstLeader`. If F-02 is wired, this becomes load-bearing.

Adjacent: `lastTrickTeam` is exposed but `firstTrickTeam`/`firstLeader` is not. Symmetric asymmetry.

**Recommendation:** Add `firstLeader = (tricks[1] and tricks[1].plays and tricks[1].plays[1] and tricks[1].plays[1].seat) or nil` to the return struct, making it available for caller logic and the eventual Reverse-Kaboot wiring.

**Confidence:** MEDIUM. Only matters if F-02 is wired or other callers want first-leader info.

---

### F-06 — Function docstring (lines 647-660) missing five returned fields (LOW severity, doc-drift)

**File:** `Rules.lua:647-660` vs `Rules.lua:939-952`.

**Issue:** The docstring promises the return struct contains `teamPoints`, `meldPoints`, `lastTrickTeam`, `bidderTeam`, `bidderMade`, `multiplier`, `final`. The actual return ALSO includes `sweep`, `belote`, `gahwaWonGame`, `gahwaWinner`, `raw`. Five undocumented fields. Several callers consume them (e.g., `Net.lua` reads `result.gahwaWonGame` per `Rules.lua:920-925` comment, `result.belote`, `result.raw`).

The docstring also says `final = { A = N, B = N }` "after multipliers + contract pen" which is confusing — final is `div10(raw)`, not "after multipliers"; multipliers are baked into `raw` already.

**Source:** Direct comparison. No external source.

**Recommendation:** Update the docstring to enumerate all 12 returned fields with one-line descriptions matching their actual semantics. Specifically:
- `sweep = "A"|"B"|nil` — which team swept (Al-Kaboot), nil if no sweep.
- `belote = "A"|"B"|nil` — which team gets the +20 bonus after sweep-override + cancellation.
- `gahwaWonGame = bool` — true if a Gahwa branch was triggered (Hokm only, per F-03 once fixed).
- `gahwaWinner = "A"|"B"|nil` — which team wins the entire match via Gahwa.
- `raw = { A = N, B = N }` — pre-div10 totals (cardA + meldPoints) × mult + belote bonus.
- `final = { A = N, B = N }` — `div10(raw)`, the game-points awarded.

**Confidence:** HIGH.

---

### F-07 — Test coverage gaps in Sections G/H/I/J/K/L (LOW-to-MEDIUM severity)

**File:** `tests/test_rules.lua`.

**Issue:** Per task scope, audited Sections G–L coverage:

**Section G (make/fail) — lines 420-471:**
- Covered: alternating-winner make path, B-takes-7 fail path.
- **Gap:** No direct strict-majority pin at the Hokm 81/81 boundary (the canonical Saudi tie that hits line 779-811). The Sun-tie tests in Section I exercise the same code path with smaller magnitudes (10/10 with last-trick), so the strict-majority logic IS covered, but a Hokm 81/81 explicit pin would be more readable and matches the task's "tied 81/162" phrasing.

**Section H (sweeps) — lines 476-498:**
- Covered: Hokm sweep raw=250, Sun sweep raw=440 (post-mult), Sun final=44.
- **Gap:** No test for Reverse-Kaboot (F-02 — but rule is unwired, so the gap is downstream). No test for sweep+belote-cancellation interaction (F-01).

**Section I (tie inversion across the 4-rung ladder) — lines 503-601:**
- Covered: tie-no-escalation→fail, tie-Bel→take, Sun-stale-tripled→Sun×Bel-take, Sun-stale-foured→Sun×Bel-take.
- **Gap:** No explicit test for `Hokm + tripled` tie → fail (covered by comment block at line 786-788 but no test pin). No explicit test for `Hokm + foured` tie → take. No explicit test for `Hokm + gahwa` tie → fail (mentioned in comment as edge-case-only-via-Takweesh-path, untested).

**Section J (Belote attribution + cancellation) — lines 606-686:**
- Covered: attribution, sweep-override (B sweeps with A holding K+Q), holder's-own-100-meld cancels, partner's-100-meld cancels (M5).
- **Gap:** No test for sweep-resurrects-cancelled-belote (F-01). No test for the X5 cascade specifically — i.e., Hokm Carré-A in same hand as K+Q-trump → cancellation should fire because Carré-A in Hokm is now 100. The current cancellation tests use `value=100` directly, which exercises the cancellation predicate but not the X5 → Belote-cascade integration.

**Section K (multipliers) — lines 691-724:**
- Covered: Sun, Hokm+Bel, Hokm+Triple, Hokm+Four, Sun×Bel, Sun×stale-Four-collapse.
- **Gap:** No test for Hokm+Gahwa multiplier (×4 baseline per line 889 — comment says "mult kept at ×4 for any per-round computation").

**Section L (Gahwa match-win) — lines 729-742:**
- Covered: Hokm+Gahwa made (bidder wins), Hokm+Gahwa failed (defenders win).
- **Gap:** No test for stale Sun+gahwa flag should NOT trigger gahwaWonGame=true (F-03). No test for Gahwa over a non-sweep tied path (the SWA/Takweesh fallthrough mentioned at line 791-793).

**Recommendation:** Add 7-10 pins covering the gaps above. Highest priority: F-01-related sweep+belote test (catches a real interpretation bug); F-03-related Sun-stale-gahwa test; F-06-related test verifying all returned fields are populated correctly (pin against doc drift).

**Confidence:** HIGH — verified by direct read of all six sections.

---

### F-08 — `meldsByTeam = nil` defensive handling inconsistent (LOW severity, defensive)

**File:** `Rules.lua:680-681` (no `or {}` guard) vs `Rules.lua:739` (does have `or {}` guard).

**Issue:** Line 680 calls `R.SumMeldValue(meldsByTeam.A)`. `R.SumMeldValue` defends against nil (`for _, m in ipairs(list or {})`), but the access `meldsByTeam.A` itself crashes if `meldsByTeam` is nil. Line 760 (`R.CompareMelds(meldsByTeam.A, meldsByTeam.B, contract)`) has the same pattern. Compare to line 739 where the cancellation block does `(meldsByTeam and meldsByTeam[belote]) or {}` defensively.

**Source:** Direct read; no external source.

**Recommendation:** Add `meldsByTeam = meldsByTeam or { A = {}, B = {} }` at function entry, OR consistently apply the defense at every access. All known callers pass a valid `meldsByTeam` (`State.lua:1924` / `Net.lua:3038` / `BotMaster.lua:793`), so this is purely defensive — but the inconsistency is a code-smell and worth normalizing.

**Confidence:** HIGH on the inconsistency. LOW on real-world impact.

---

### F-09 — Sun multiplier formula and Carré-A pipeline correctly produce video #43's expected values (NO severity, positive verification)

**File:** `Rules.lua:884-893` (mult), `Rules.lua:895-896` (rawA/B), `Rules.lua:898-912` (belote +20 post-mult), `Rules.lua:918` (`div10`).

**Verification:** Working through the v0.10.0 R5 promise that `K.MELD_CARRE_A_SUN = 400` raw direct produces 80 nq under Sun:
- meldA = 400 (single meld of Carré-A).
- mult = 2 (Sun) for un-doubled Sun.
- rawA = (cardA + 400) × 2; with cardA = 0 (hypothetical), rawA = 800.
- div10 = (800 + 5)/10 = 80. ✓ matches video #38 line 27-31 ("الأربع مئة" / Four Hundred = 80 nq).

For Sun + Bel: mult = 4. rawA = (cardA + 400) × 4 = 1600. div10 = 160. Per video #43 the Sun divisor is 5; raw 400 × Bel × 2 = 1600 / 10 = 160 nq. Consistent (since code's Sun-mult-bake-in × div10 ≡ /5).

For Hokm + Carré-A (X5 fix, MELD_CARRE_OTHER = 100): mult = 1 (no Bel). rawA = 100. div10 = 11 (rounds up from 105). Per Saudi convention: 100/10 = 10 nq. **Anomaly:** `div10(100) = floor((100+5)/10) = floor(10.5) = 10`. ✓ correct, my arithmetic above was wrong (100 → 10, not 11). Re-verifying: `(100+5)/10 = 10.5`, `math.floor(10.5) = 10`. Yes, 10 nq. ✓ matches Saudi expectation.

The R2/R5/X5 cascade pipeline is mathematically correct end-to-end.

**Source:** Video #43 lines 411-440 (rounding direction); video #38 lines 27-31 (Four Hundred = 80 nq); Constants.lua:88 ("4 of A: 10 / 80 = Hokm 100, Sun 400"); inline comment at Rules.lua:898-912 ("Always +2 game points to that team" for Belote).

**Confidence:** HIGH.

---

### F-10 — Belote +20 added to the bidder-threshold check (line 758-766): correct per Saudi convention but unstated in PDF (NO severity, positive verification)

**File:** `Rules.lua:758-766`.

**Verification:** The threshold computation `bidderTotal = teamPoints[bidderTeam] + (effMeld + belote)` includes the +20 Belote raw value when belote is awarded to bidder's team. PDF 02 line 128-141 says Belote is "to indirectly support Hokm" (لدعم الحكم), implying it counts toward the bidder's count. PDF 07 line 22 separately says Belote is multiplier-immune ("ماعدا البلوت اليدبل").

The two rules are independent: (1) +20 is added to the bidder's strict-majority count for the make/fail decision; (2) +20 is NOT scaled by the multiplier in final scoring. The code correctly implements both: line 758-766 adds raw +20 to threshold; lines 898-912 adds +20 raw AFTER the mult application.

**Confidence:** HIGH on (2). MEDIUM on (1) — PDF wording is suggestive but not explicit; tournament play conventionally credits Belote toward bidder threshold.

---

## Verdict

**NEEDS-ATTENTION (with most issues being defensive / doc-drift / coverage).**

The core scoring math (multipliers, melds, sweep, threshold, tie inversion across the 4-rung ladder, Belote attribution + cancellation, div10 rounding) is correct in canonical paths post-v0.10.0 R2/R5/X5/M5 fixes. The Carré-A in Sun = 400 raw direct pipeline produces 80 nq as expected; Carré-A in Hokm = 100 cancels Belote per the X5 cascade.

Issues, in priority order:
- **F-01 (medium):** Sweep override + Belote cancellation order can resurrect a previously-cancelled belote on sweep. Interpretation-dependent but the most natural reading of Saudi sources says cancelled-belote-stays-cancelled.
- **F-03 (medium):** Sun + stale `gahwa` flag triggers `gahwaWonGame=true` despite R2's defensive collapse elsewhere. Asymmetric.
- **F-06 (low/doc):** Function docstring missing five returned fields (`sweep`, `belote`, `gahwaWonGame`, `gahwaWinner`, `raw`).
- **F-07 (low/coverage):** Multiple coverage gaps in Sections G/H/I/J/K/L; highest-value missing pin is the F-01 scenario.
- **F-02 (low/known):** Reverse-Kaboot not wired (`(not yet wired)` per docs). Single-source from video #16; corroboration deferred.
- **F-04 / F-08 (low/defensive):** `R.TeamOf(nil) → "B"` silent misclassification; `meldsByTeam = nil` would crash before line 739's defense kicks in. No known caller hits these paths.
- **F-05 (low):** `firstLeader` not exposed in result struct; only matters if F-02 is wired.

Positive verifications: F-09 (R5/X5/M5 pipeline produces video-#43-expected values), F-10 (Belote threshold + multiplier-immunity correctly split).

## Confidence

- HIGH: F-02, F-03, F-04, F-05, F-06, F-07, F-08, F-09, F-10.
- MEDIUM: F-01 (Saudi sources don't explicitly cover the sweep+cancelled-belote intersection; current code's reading is defensible but non-canonical).
