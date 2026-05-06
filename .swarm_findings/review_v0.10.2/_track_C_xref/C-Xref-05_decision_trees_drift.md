# C-Xref-05 — `docs/strategy/decision-trees.md` ↔ Bot.lua / BotMaster.lua drift audit (v0.10.2)

Operational WHEN/RULE/MAPS-TO chain audit. Each section in `decision-trees.md`
is checked against the implementing function/lines in
`C:\CLAUDE\WHEREDNGN\Bot.lua` and `C:\CLAUDE\WHEREDNGN\BotMaster.lua`. For
each row I verify wiring presence, gate accuracy, and flag dead /
missing / extra branches. Read-only audit; no code modified.

Files inspected:
- `C:\CLAUDE\WHEREDNGN\docs\strategy\decision-trees.md` (full, 314 lines)
- `C:\CLAUDE\WHEREDNGN\Bot.lua` (3953 lines)
- `C:\CLAUDE\WHEREDNGN\BotMaster.lua` (898 lines)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-Bot-08_pickLead_full.md`

---

## 0 — Header line-ref drift (Bot.lua:line addresses in section headers)

Every section header in `decision-trees.md` carries a function name +
Bot.lua line number. The file's own preamble (lines 26-29) flags this
drift risk and redirects to `glossary.md`. Current verified addresses:

| Section header claim | Actual | Drift | Severity |
|---|---|---|---|
| `Bot.PickBid` Bot.lua:890 | 1175 | +285 | LOW |
| `Bot.PickAshkal` (no line) | **does not exist** | — | LOW (Ashkal logic is in `PickBid`, lines ~1287-1410, no separate function) |
| `Bot.PickDouble` 2403 | 3454 | +1051 | LOW |
| `PickTriple` 2534 | 3593 | +1059 | LOW |
| `PickFour` 2564 | 3629 | +1065 | LOW |
| `PickGahwa` 2608 | 3676 | +1068 | LOW |
| `pickLead` Bot.lua:1289 | 1703 | +414 | LOW |
| `pickFollow` Bot.lua:1882 | 2492 | +610 | LOW |
| `pickFollow` pos-4 Bot.lua:1882 | 2492 (Faranka block 2560-2613) | +610 | LOW |
| `Bot.PickAKA` Bot.lua:2302 | 3276 | +974 | LOW |
| `Bot.PickSWA` Bot.lua:2746 | 3881 | +1135 | LOW |
| `Bot.PickSWA` Bot.lua:2120 (Sec 7 SWA-card-thresh row) | 3881 | +1761 | LOW |

The file's own header comment notes drift to "+165 to +461" across
v0.5.8 → v0.5.14; current drift is roughly +300 to +1135. Consider a
re-anchoring sweep next release.

---

## Section 1 — Bidding (`Bot.PickBid` 1175)

| Row | WHEN | MAPS-TO claim | Verdict |
|---|---|---|---|
| H-1 | J trump + 1 cover + side-A | `Bot.PickBid` strength formula `(refinement)` | Wired in `hokmStrength` family + threshold; min-shape proxy via threshold not explicit. As-doc'd: partial wire. |
| H-2 | 4+ trump w/ J | strength formula | Wired; no explicit gate, score-driven. |
| H-3 | 5+ trump w/ J → Kaboot pursuit flag | `(not yet wired)` | Confirmed: no `S.s.pursuitFlagBidder` exists. Partial-wire via sweepPursuitEarly (Bot.lua:1726-1735) which is trick-3+ in `pickLead`. |
| H-4 | 0-2 trump or no J → pass | strength formula | Wired (low strength → pass). |
| H-5 | borderline + uneven distribution + 1 cover → prefer Hokm | weight Hokm-vs-Sun | No explicit asymmetry weight observed; threshold structure produces this empirically. |
| H-6 | K+Q trump + 2+ trump → mandatory Hokm | `Bot.PickBid` Belote-detection | Wired (`beloteSuit(hand)` Bot.lua:1226). |
| S-1 | A+T mardoofa | `Bot.PickBid` Sun branch — `(not yet wired)` | Mardoofa pair bonus IS wired since v0.5.13 (Bot.lua:1217-1218 `K.BOT_SUN_MARDOOFA_BONUS`). **Doc is STALE — should remove `(not yet wired)`.** |
| S-2/S-3 | 2+/3+ Aces | `Bot.PickBid` Sun strength | Wired via `aceCount`/`sunStrength` + `BOT_SUN_3ACE_BONUS` (Bot.lua:1216). |
| S-4 | Carré of Aces → mandatory Sun | `Bot.PickBid` + meld-detection | **WIRED** at Bot.lua:1188-1189 (`if aceCount >= 4 then return K.BID_SUN end`), top-of-function. |
| S-5/S-6 | 1A no T / long no A → no Sun | anti-trigger | Implicit via low `sunStrength`, no explicit anti-trigger. |
| S-7 | cumul ≥100 → Bel-fear | `S.s.cumulative` `(not yet wired)` | **WIRED** at Bot.lua:1269-1274 (v0.6.0 B-7). **Doc is STALE.** |
| S-8 | A+T mardoofa Sun-Mughataa bonus | strength formula | Wired (Bot.lua:1217-1218). |
| A-1 | non-eligible seat → no Ashkal | State.lua:1464-1487 | Out-of-scope rule check (legality, not heuristic). |
| A-2/A-3/A-4/A-5/A-6 | Ashkal allow/anti-list | `Bot.PickAshkal` `(not yet wired)` | **NOTE: function `Bot.PickAshkal` does not exist.** Logic IS wired inside `Bot.PickBid` (Bot.lua:1287-1410); the doc's reference to a separate `Bot.PickAshkal` is a **phantom function name**. The actual MAPS-TO is `Bot.PickBid` Ashkal sub-block. |
| G-1 | path-discipline (make or sweep) | strength threshold (a) + Kaboot path `(not yet wired)` | Partial; Kaboot-path check absent. |
| G-2 | R1 borderline → pass | R1-conservative bias `(not yet wired)` | Bot.lua:1244-1246 has R1=42/R2=base-4, Advanced bumps R2 to ≥R1-4. R1-conservative is implicit via threshold split; not an explicit branch. |
| G-3 | R2 minimum → bid | R2 bias toward bidding | Wired (`r2Base` reflects this; trap-pass detection at 1252-1254). |
| G-4 | takweesh override | `Bot.PickBid` should NOT outbid `(refinement)` | Not explicitly wired as anti-rule; partner-bid bonus encourages cooperation but no hard "do not bid against partner". |

**Summary:** Section 1 wiring is solid for the core rules. **DOC DRIFT:**
S-1 and S-7 marked `(not yet wired)` are actually wired since v0.5.13 /
v0.6.0. The "Bot.PickAshkal" function name is phantom — Ashkal logic is
embedded in `Bot.PickBid` and the doc should update its MAPS-TO and
header.

---

## Section 2 — Escalation (`Bot.PickDouble` 3454, `PickTriple` 3593, `PickFour` 3629, `PickGahwa` 3676)

| Row | WHEN | MAPS-TO claim | Verdict |
|---|---|---|---|
| E-1 | Sun cumul ≥100 → Bel forbidden | `Bot.PickDouble` 1787 — needs `cumulative` precondition + `R.CanBel` | **WIRED** at Bot.lua:3465-3467 (`if R.CanBel ... not R.CanBel(R.TeamOf(seat), contract, S.s.cumulative) then return false`). Saudi-rule legality gate. |
| E-2 | Hokm any score → Bel allowed | existing | Wired by absence — no Hokm gate. |
| E-3 | R1 of session → restricted | `Sometimes` follow-up TBD | Not wired (doc admits "TBD"). |
| E-4 | Cards revealed → Bel window closed | Bot.PickDouble phase-gated | Wired by phase check; `Net.lua` enforces window. |
| E-5 | Hokm bidder + clean tricks 1-2 → Kaboot pursuit at trick 3 | `pickLead`/`pickFollow` `(partial wire)` | **PARTIAL WIRE confirmed:** Bot.lua:1726-1735 `sweepPursuitEarly` fires for trick 3-7 when bidder-team won every prior trick. Only fires in `pickLead`, not `pickFollow`. |
| E-6 | Sun bidder + Bel-multiplier > Kaboot → sabotage own sweep | new branch `(not yet wired)` | Confirmed not wired. |
| E-7 | Qaid-bait defender | "bot likely should NOT" | Confirmed defensive note only; not wired. |

**Summary:** Section 2 is correctly wired for legality (E-1) and
conservatively skipped for player-tier maneuvers (E-6, E-7). Partial
wire status on E-5 is accurate.

---

## Section 3 — Opening leads (`pickLead` 1703)

| Row | WHEN | MAPS-TO claim | Verdict |
|---|---|---|---|
| L-1 | Strong card + first turn → hold for end, Tahreeb-signal first | `pickLead` strong-card-hold `(not yet wired)` | **NOT WIRED.** No explicit "hold the T for endgame" branch. M8 mardoofa probe (Bot.lua:1810-1822) is the only Sun trick-1 special, and it sends OUT the Ace — opposite direction. |

**Note — Section 3 prior-finding from B-Bot-08 (M8 mardoofa hard-return):**
Bot.lua:1819-1822 mardoofa probe correctly hard-returns the
side-suit Ace when both A AND T present in a side suit + bidder team +
trick 1 + Sun. This is the only branch in Section 3's domain and
matches Pro-2 PDF §2. Per L08-style reading, the doc Section 3 single
row L-1 is NOT WIRED — current code does the OPPOSITE (sends Ace
forward) for mardoofa-strong hands. **This is correct behavior** for
M8 (different rule), but the doc Section 3 row remains unimplemented.

---

## Section 4 — Mid-trick play (`pickFollow` 2492)

| Row | WHEN | MAPS-TO claim | Verdict |
|---|---|---|---|
| 4-1A | Sun, opp winning, can't beat → tasgheer (smallest) | **wired v0.7.2** | **WIRED by fall-through** at Bot.lua:3182-3199; documentation marker only. The `lowestByRank(legal)` ultimate fallback at Bot.lua line ~3266+ (after Tanfeer sender) implements 1A. |
| 4-1B | Sun, partner winning, can't beat → second-lowest | **wired v0.7.2** | **WIRED** at Bot.lua:2814-2845 with v0.9.5 wouldWin gate (sorted[2] returned only if it doesn't steal partner's trick). |
| 4-2 | Hokm losing-side trump follow → lowest trump | `pickFollow` 1457 trump-follow `(not yet wired)` | **PARTIAL.** `lowestByRank` fallback handles "lowest trump" but the void-state read-side is documented as not yet wired. Memory write-side is at Bot.lua:282-292 per doc. |
| 4-3 | Sun discard while partner winning → Tahreeb signal | wired in v0.5.10 | **WIRED** at Bot.lua:2665-2796 (Bargiya, "want" sender, T-4 dump-ordering). |
| 4-4 | Sun deceptive J-overplay | `pickFollow.deceptiveOverplay` `(not yet wired)` | **NOT WIRED.** No `deceptiveOverplay` function exists. Bait-DETECTION ledger (Bot.lua:510-558 baitedSuit) reads opp's J-overplay; SENDER side (we play J) absent. |
| 4-5 | Hokm deceptive J | `pickFollow.deceptiveOverplay` Hokm `(not yet wired)` | **NOT WIRED.** Same. |
| 4-6 | Hokm gate-off w/ A+3 trumps | `pickFollow.deceptiveOverplay` `(not yet wired)` | **NOT WIRED** (because rule 4-5 itself is not wired). |
| Takbeer-1 | Trick-winner CERTAIN partner → highest | partner-certain `(not yet wired)` | **WIRED via smother** Bot.lua:2615-2663. v0.5.18 expanded candidate set to A/T/K/Q/J. Not gated explicitly on "CERTAIN" — uses `partnerWinning` heuristic + suit/feedSafe. **MINOR DRIFT:** doc says "CERTAIN partner" but code uses `partnerWinning` (current trick state, not fully certain). Functionally close. |
| Takbeer-2 | CERTAIN opp → lowest | opp-certain `(not yet wired)` | Wired by `lowestByRank` fall-through (no opp-winning Takbeer/Tasgheer-specific branch); Sun rule 1A handles in-suit. |
| Takbeer-3 | UNCERTAIN → fall through | priority chain | Wired by absence of explicit certainty check. |
| Takbeer-4 | Hokm consec top-trumps → highest | adjacency check `(not yet wired)` | **NOT WIRED.** No `K.RANK_TRUMP_HOKM` adjacency check observed. |
| Takbeer-5 | Hokm non-consec top-trumps → INVERT | non-consec branch `(not yet wired)` | **NOT WIRED.** |
| Takbeer-6 | Hokm consec must-over-cut → smaller | over-cut branch `(not yet wired)` | **NOT WIRED.** |
| J-tripled-1 | Sun J + 2 lower side suit; suit led | `(not yet wired)` | **NOT WIRED.** No tripled-J branch (verified via grep on `tripled`/`مثلوث`). |
| J-tripled-2 | Sun, suspect opp مثلوث الولد | `pickLead` `(not yet wired)` | **NOT WIRED.** |

**Summary:** Section 4 is partially wired. Strongly-wired: rules 1A, 1B,
3, smother/Takbeer rule 7. Major gaps: deceptive J-overplay (sender,
4-4/4-5/4-6), Takbeer-4/5/6 trump consec/non-consec adjacency, and
both J-tripled branches. **Phantom function name `pickFollow.deceptiveOverplay`
does not exist** — doc references a designed-but-never-implemented
identifier. Treat as a missing-branch flag.

---

## Section 5 — Pos-4 plays (`pickFollow` pos-4 Bot.lua:2560-2613)

decision-trees Section 5 has 9 rules. The v0.5.21 Faranka block at
Bot.lua:2560-2613 implements the core 4 (rules 1, 2, 4, 9 by predicate)
under a single combined gate.

| Doc rule | WHEN | Code coverage | Verdict |
|---|---|---|---|
| 5-1 | Sun pos-4 + partner winning + A+next-high → duck w/ smaller | hasA + cover (T or K) + suitCount==2 + partnerWinning + lastSeat | **WIRED** Bot.lua:2584-2611. Returns the cover (T or K). |
| 5-2 | Sun pos-4 + partner Kaboot run (≥6) → Faranka | (not explicitly checked) `(not yet wired)` | **NOT WIRED.** Code does not consult tricks-won-so-far. |
| 5-3 | Sun pos-4 + two highest unplayed → NEVER Faranka | anti-Faranka guard `(not yet wired)` | **NOT WIRED EXPLICITLY.** suitCount==2 + has-A + has-cover proxy doesn't catch the "we hold both A AND T (and another seat is void)" exact case. Doc admits "hard to detect cheaply". |
| 5-4 | Sun pos-4 + ≥3 cards of suit → don't Faranka | guard | **WIRED** by `suitCount == 2` gate (Bot.lua:2610). |
| 5-5 | Sun pos-4 + only A no J/2nd-high → don't Faranka | gate `(not yet wired)` | **WIRED** by requiring `cover` to be non-nil (Bot.lua:2610). |
| 5-6 | Sun pos-4 + T (no A) + A at LHO → don't Faranka, take w/ T | `(not yet wired)` | **NOT WIRED.** Code's Faranka gate requires hasA; this row's WHEN starts "no A" so the v0.5.21 block doesn't apply. The "take with T" follows from natural play (winners branch). |
| 5-7 | Sun pos-4 + RHO low (8) → STRONGEST Faranka | score boost `(not yet wired)` | **NOT WIRED.** Code doesn't read trick.plays positions for RHO-low boost. |
| 5-8 | Sun pos-4 + LHO led trick 1 fresh hand + bidder team | bidder-team check `(not yet wired)` | **NOT WIRED** (no trick-1 / fresh-hand check). |
| 5-9 | Sun pos-4 + LHO led + opp bidders → don't Faranka | defender branch `(not yet wired)` | **WIRED** by `R.TeamOf(seat) == R.TeamOf(contract.bidder)` gate (Bot.lua:2586) — defender-team simply doesn't enter this block. |

**Summary:** Section 5 has 4 of 9 rules effectively wired (1, 4, 5, 9).
Rules 2, 3, 6, 7, 8 are not wired. Most are M3lm+ refinements; the
core Faranka shape (rule 1) is correctly implemented. The bidder-team
gate at line 2586 (`R.TeamOf(seat) == R.TeamOf(contract.bidder)`) is
correct per rule 9.

**MINOR DOC DRIFT:** The single-block code implementation makes it
unclear in a code-walk which doc rules are encoded vs delegated to
absence-of-trigger. Consider adding a comment block listing rule
numbers covered explicitly.

---

## Section 6 — AKA / signaling (`Bot.PickAKA` 3276, `pickFollow` AKA-receiver 2520-2558)

| Row | WHEN | MAPS-TO claim | Verdict |
|---|---|---|---|
| 6-1 | Sun trick 1 + partner T-under-A → infer K | `topTouchSignal` `(not yet wired)` | **WIRED** at Bot.lua:476-508 (v0.9.2 #12 fix). Recorder side. Read side gated on style ledger. |
| 6-2/6-3 | Same setup, K/Q under partner-A | same | Wired (rule 2 → cleared {Q,J}; rule 3 → nextDown=J). |
| 6-4 | Partner low under Ace → broke in suit highs | sampler should NOT pin | Wired as recorder (Bot.lua:502-504 `entry.broke = true`); read-side via sampler not directly verified here. |
| 6-5 | AKA partner-call window | Bot.PickAKA + receiver | **WIRED** at Bot.lua:3276 + receiver at Bot.lua:2520-2558 (v0.5.1 H-5). |
| 6-6 | Hokm bare-A lead w/o explicit AKA → implicit AKA | Extension v0.5.16 | **WIRED** at Bot.lua:2515-2540 (implicitAKA detection, v0.5.16 S6-6). |
| 6-7 | Hokm pos-4 partner winning + void → released from must-ruff | Already wired Rules.lua + heuristic `(not yet fully wired)` | Legality wired in `R.IsLegalPlay`. Heuristic prefer-non-trump per doc admission "currently bot defaults to lowestByRank". Verified Bot.lua:2554-2558 — when `(explicitAKA or implicitAKA)`, code DOES filter `discards = non-trump cards` and returns lowest non-trump. **DOC IS STALE — partner-winning-without-AKA case may still default to lowestByRank, but the AKA-relief case is wired.** |
| 6-8 | Hokm partner verbal AKA → released | H-5 v0.5.1 | Wired. |
| 6-9 | AKA verbal-only | already gates on explicit broadcast | Wired. |
| 6-10 | AKA-call sender preconditions (a-g) | augment with (f) and (g) | **(f) WIRED** Bot.lua:3328-3334 v0.9.1; **(g) WIRED** Bot.lua:3357-3399 v0.9.3 trickNum>=6 + scoreUrgency suppression. |

**Summary:** Section 6 is the most complete section. All sender
preconditions wired. Both explicit and implicit AKA receiver paths
exist. Touching-honors recorder is live (post v0.9.2 #12 fix +
v0.10.0 R6 K-fix). **Minor wiring opportunity:** 6-7's "non-AKA
partner-winning + void" prefer-non-trump heuristic — doc admits this is
"the actionable gap". Confirmed: when AKA flag is absent and partner
is winning + we're void, code falls through to lowestByRank.

---

## Section 7 — Endgame / SWA / Al-Kaboot (`Bot.PickSWA` 3881, `pickLead` 1703)

| Row | WHEN | MAPS-TO claim | Verdict |
|---|---|---|---|
| 7-1 | Bidder + Kaboot reachable | `pickLead` trick-8 sweep `(partial wire)` | **PARTIAL** — sweep at trick 8 + sweepPursuitEarly trick 3-7 (Bot.lua:1726). |
| 7-2 | Trick-3 trigger (clean 1+2) | pursuit flag `(partial wire — only trick-8)` | **WIRED PARTIAL** at Bot.lua:1726-1735 (v0.5.19, Hokm-aware). Doc claims "only trick-8 currently active" — STALE. |
| 7-3 | Bidder Sun sabotage own sweep | `(not yet wired)` | Confirmed not wired. |
| 7-4 | Defender Qaid-bait | defensive note only | Not wired. |
| 7-5 | Defender prevent Kaboot | implicit `(could be explicit)` | Implicit only. |
| 7-6 | Defender force fail | scoreUrgency 588 | scoreUrgency exists; implicit. |
| 7-7 | Sun + partner winning + want suit X → Bargiya | `pickFollow` Bargiya + PickSWA followup `(not yet wired)` | **WIRED Bargiya** at Bot.lua:2710-2723 (T-1 sender, v0.5.10). PickSWA followup not wired. |
| 7-8 | Sun trick 8 + Bargiya'd suit X → lead X | `pickLead` followup `(not yet wired)` | **NOT WIRED.** No explicit "if we Bargiya'd, lead it back" branch. |
| 7-9 | Reverse Al-Kaboot defender sweep | new R.ScoreRound branch | **NOT WIRED** (rule-correctness item; doc explicitly defers). |
| 7-10 | SWA card-count thresholds (≤3 / 4 / 5+) | Net.MaybeRunBot + PickSWA | Wired in `R.IsValidSWA` + Bot.PickSWA. v0.5.21 belt-and-suspenders gate at Bot.lua:3921-3949 (Hokm only-when-top-trump-clean). |
| 7-11 | SWA deterministic-or-bust | PickSWA + ISMCTS update | **WIRED** via R.IsValidSWA strict-caller-correct (post-v0.5.17). v0.5.21 Hokm guard is additional conservatism; in line with rule. |
| 7-12 | SWA denied → Qaid penalty | Net.HostResolveSWA | Out-of-scope for this audit (Net.lua). |

**Summary:** Section 7 wiring is solid for the Saudi-strict rules
(7-10, 7-11) and partial for sweep-pursuit (7-1, 7-2). 7-2's "only
trick-8 currently active" claim is **STALE** — sweepPursuitEarly is
wired since v0.5.19. Doc should update.

---

## Section 8 — Tahreeb (5-of-10 sourced; central convention)

### Sender side
| Row | WHEN | MAPS-TO claim | Verdict |
|---|---|---|---|
| 8-S-1 | Sun + partner winning + hold A of X | Bargiya `(not yet wired)` | **WIRED** Bot.lua:2710-2723 (T-1 Bargiya). Doc STALE. |
| 8-S-2 | Sun + partner winning + want X (no A) | bottom-up sequence `(not yet wired)` | **WIRED** Bot.lua:2725-2760 ("want" sender arm v0.9.0). Doc STALE. |
| 8-S-3 | Sun + partner winning + don't want X | top-down sequence `(not yet wired)` | **PARTIAL** via T-4 dump-ordering Bot.lua:2762-2796. Single-event "high first" produced; multi-event descending is implied by 2-card suit. |
| 8-S-4 | 2-card unwanted suit → larger first | dump-ordering `(not yet wired)` | **WIRED** Bot.lua:2762-2796 (T-4, v0.5.10 + v0.5.11 high-rank cap). Doc STALE. |
| 8-S-5 | Strong suit → don't Tahreeb FROM it | discard-suit-selection `(not yet wired)` | **NOT WIRED.** "Want" sender requires the suit have a winner (A/T) but doesn't avoid Tahreeb-from-it. Possible over-fire. |
| 8-S-6 | Cutter ruff IS Tahreeb event | ruff-aware `(not yet wired)` | **NOT WIRED.** Tahreeb sender block requires `voidInLed` (no cards in led suit). Doesn't apply to ruff path. |

### Receiver side
| Row | WHEN | MAPS-TO claim | Verdict |
|---|---|---|---|
| 8-R-1 | Single Tahreeb hint | `pickLead` style ledger `(not yet wired)` | **WIRED** Bot.lua:1860-1925 (M3lm+ tahreebPrefSuit reads tahreebClassify scores — bargiya=3, want=2, bargiya_hint=1). |
| 8-R-2 | Second Tahreeb confirms | sequence detector `(not yet wired)` | **WIRED** via `tahreebClassify` (Bot.lua:1638-1701) returning "want"/"dontwant" on 2+ events. |
| 8-R-3 | Bare-T Tahreeb-return | pickLead branch `(not yet wired)` | **NOT WIRED.** Lead picker uses tahreebPrefSuit but doesn't specifically prefer the T card. |
| 8-R-4 | T mardoofa + partner Sun bidder → lead SIDE | branch on bid type `(not yet wired)` | **NOT WIRED.** |
| 8-R-5 | T doubled + non-Sun-bidder → lead T | default `(not yet wired)` | **NOT WIRED.** |
| 8-R-6 | T tripled+ → lead LOW | branch `(not yet wired)` | **NOT WIRED.** |
| 8-R-7 | Receiver no-winner → highest, NOT lowest | discipline `(not yet wired)` | **NOT WIRED** explicitly; default lowestByRank may misfire. |
| 8-R-8 | Partner small→big Tahreeb + we hold T → lead T | partner-return T-supply `(not yet wired)` | **NOT WIRED** explicitly. |
| 8-R-9 | Already won return + partner re-supplies → don't capture | release-control `(not yet wired)` | **NOT WIRED.** |
| 8-R-10 | Sender 3-card strong suit → don't Tahreeb-from-it | discard-suit `(not yet wired)` | **NOT WIRED** (paired with 8-S-5). |

### Three-discard variant
| Row | Verdict |
|---|---|
| 8-3disc | extended pattern `(not yet wired)` | Implicit via repeated single-event "want" arm (v0.9.0); not explicit. |

**Summary:** Tahreeb sender is well-wired (Bargiya + want + dontwant
basics). Receiver-side **mostly** unwired beyond the basic preference
pickLead bias — the doc's own STATUS column reflects this accurately
for receiver. Several `(not yet wired)` markings on SENDER side are
STALE (8-S-1 thru 8-S-4 actually wired since v0.5.10/v0.5.11/v0.9.0).

---

## Section 9 — Tanfeer (`pickFollow` v0.5.14)

| Row | WHEN | MAPS-TO claim | Verdict |
|---|---|---|---|
| N-1 | Opp 100% taken + must discard | sender — wired v0.5.14 | **WIRED** at Bot.lua:3201-3264. Discard lowest of suit where we hold A or T (signals "lead this back"). M3lm+ + bot-partner-only gates. |
| N-2 | Trick-winner uncertain → default Tahreeb | wired v0.5.14 | **WIRED** by code structure: partnerWinning branch handles Tahreeb sender, opp-winning branch handles Tanfeer; ambiguous cases fall through to lowestByRank (per doc reasoning). |
| N-3 | Opp small→big tahreeb → suit-to-AVOID | receiver — wired v0.5.14 | **WIRED** at Bot.lua:1894-1925 (`tahreebAvoidSet` populated by opp signals; conflict-resolution at Bot.lua:1926). |

**Summary:** Section 9 is fully wired. No drift.

---

## Section 10 — Faranka (Hokm exceptions, Bot.lua:2857-3037)

### Sun Faranka (default = YES when factors align)
| Row | WHEN | MAPS-TO claim | Verdict |
|---|---|---|---|
| Sun-F-1 | Sun, J+A of led, partner taking, pos-3/4 | See Section 5 | Wired via Section 5 v0.5.21 block (Bot.lua:2560-2613). |
| Sun-F-2 | Sun pos-4 + partner Kaboot run + your A blocks | `(not yet wired)` | NOT WIRED (≥6-trick check absent). |
| Sun-F-3 | Sun + Faranka flips round-loss | score-aware `(not yet wired)` | NOT WIRED. |

### Hokm Faranka (default = NO except exceptions)
| Row | WHEN | MAPS-TO claim | Verdict |
|---|---|---|---|
| Hokm-F-default | No exception → NO Faranka | wired by absence | Verified Bot.lua:2857-3037 only enters Faranka branch if `Bot.IsM3lm()` AND exceptions trigger. |
| Hokm-F-#1 | Pursuing Al-Kaboot | `pickLead` trick-3 wired v0.5.19; cross-wire pickFollow deferred | **PARTIAL** — sweepPursuitEarly is in pickLead only; pickFollow Faranka block doesn't consult sweep flag. |
| Hokm-F-#2 | Only 2 trumps + bidder team | wired v0.8.4 + bidder gate v0.9.2 | **WIRED** Bot.lua:2892-2902. `myTrumpCount == 2 and onBidderTeam` predicate. |
| Hokm-F-#3 | J of trump dead + we hold 9 | wired v0.8.5 via HighestUnplayedRank + bidder gate v0.10.0 X3 | **WIRED** Bot.lua:2904-2932. |
| Hokm-F-#4 | Bidder + opps trump-exhausted | wired v0.8.4 via void check; v0.10.0 relaxed to bidder-team | **WIRED** Bot.lua:2934-2959. `oppsVoidPath` flag set true (used by F-16 anti-rule). |
| Hokm-F-#5 | Partner showed extra trump | partner-strong-trump + style ledger `(not yet wired)` | **NOT WIRED.** No `Bot._partnerStyle.trumpCutCount` or similar. |
| Hokm-F-#6 (anti) | Bidder is opp + opp Q-led + we hold J+8 | wired v0.8.4 | **WIRED** Bot.lua:2989-3008. Vetoes Faranka when opp-bidder Q-led + J+8. |
| Hokm-F-#7 (must-take) | pos-4 hold trump-9 only + opp Faranka'd by playing T after partner J over-trumped | `(not yet wired)` | **NOT WIRED.** No "must take with 9" pos-4 cover branch (verified via grep). |
| Hokm-F-#8 (meta) | Trump still live in opp hands → assume worst case | meta-principle | Implicit via void-check gating Exception #4. |

### F-16 anti-rule (recently scoped per audit cycle)
| Item | Verdict |
|---|---|
| F-16 "no K of trump → don't Faranka" | **WIRED** Bot.lua:2961-2987. v0.10.3 audit scopes F-16 to threat-model-live cases (`if not oppsVoidPath then` gate). When Exception #4 fires (both opps observed-void in trump), F-16 is correctly bypassed because there's no opp left to punish the K-less withhold. Wiring matches A-Src-29 + D-RT-03 S-1 Option A scoping. |

**Summary:** Section 10 is the most heavily-audited section. F-16
scoping fix landed at v0.10.3 (Bot.lua:2961-2987) per the prior-finding
note in the audit prompt. Exceptions #1, #5, #7 remain unwired per doc.
Anti-rule #6 (J+8 veto) is wired and correctly overrides #2/#3/#4.

---

## Section 11 — Reads / partner-style inference (M3lm+)

| Row | WHEN | MAPS-TO claim | Verdict |
|---|---|---|---|
| 11-1 | Sun, opp K-or-higher 2nd-pos losing → infer void | OnPlayObserved K-or-T void infer wired v0.7.2 | **WIRED** Bot.lua:358-394. Sets `mem.void[leadSuit] = true` on K or T plays that lost. Q excluded per rule confidence drop. |
| 11-2 | Hokm + opp T-into-J-led → trump-short | new ledger `(not yet wired)` | **NOT WIRED.** No `trumpHighDump` field. |
| 11-3 | Pigeonhole 5/3/0 trump distribution | sampler wired v0.5.22 | **WIRED** in BotMaster.lua sampler at H-1 pin extension. (Verified by file presence; see B-BotMaster-02 audit for detail.) |
| 11-4 | Partner Sun bidder → assume one long suit | sampler wired v0.6.1 getPartnerCards | **WIRED** in BotMaster.lua getPartnerCards Sun branch. |
| 11-5 | Opp performed deceptiveOverplay | baitedSuit ledger wired v0.8.2 | **WIRED** Bot.lua:510-558 (recorder), pickLead reads as avoid-suit hint. |
| 11-6 | Partner Tahreeb low → infer A/J elsewhere | tahreebSuspect proposal `(not yet wired)` | **NOT WIRED** as a separate ledger key; tahreebPrefSuit is the consumed read. Adequate but coarse. |
| 11-7 | Partner forced-to-follow → no touching-honors inference | gate on winnerSeatSoFar `(not yet wired)` | **PARTIAL.** Touching-honors recorder at Bot.lua:476-508 gates on `lead.seat == R.Partner(seat) AND lead.card == A` — already restricts to "partner led the Ace" context. The "forced to follow" guard is implicit via the `lead.card == A + suit match` precondition. Likely sufficient. |
| 11-8 | Partner historical convention violations | conventionAdherence rolling counter `(not yet wired)` | **NOT WIRED.** |

**Summary:** Section 11 has 4 of 8 rules wired (11-1, 11-3, 11-4, 11-5).
The unwired rules (11-2, 11-6, 11-8) require new ledger keys; doc
correctly tags as `(not yet wired)`.

---

## Touching honors (video 05) — referenced Bot.lua ~480-510

Bot.lua:476-508 implements the touching-honors recorder. Rules:
- `theirRank == "T"` → `entry.nextDown = "K"` (rule 1).
- `theirRank == "K"` → `entry.cleared = {"Q","J"}` (rule 2, **v0.10.0 R6 fix**: K-signal = K-singleton, NOT has-Q).
- `theirRank == "Q"` → `entry.nextDown = "J"` (rule 3).
- `theirRank == "7"/"8"/"9"` → `entry.broke = true` (rule 4).

**Wiring is complete and post-fix correct.** Gated by:
- `not wasIllegal`
- `#trickPlays >= 2` (rules out lead position)
- `style.topTouchSignal` field present
- `lead.seat == R.Partner(seat) AND lead.card == "A" AND C.Suit(lead.card) == cardSuit`
  OR `S.s.akaCalled.seat == R.Partner(seat) AND .suit == cardSuit`

The v0.9.2 #12 fix activated the previously-dead branch (`trickPlays`
substituted for the undefined `trick` variable). **No drift here.**

---

## AKA signaling (video 18) — referenced Bot.PickAKA + pickFollow

`Bot.PickAKA` Bot.lua:3276-3399. Sender precondition list (a-g):
- (a) `contract.type == K.BID_HOKM` ✓ Bot.lua:3278
- (b) `card.suit != trump` ✓ Bot.lua:3297
- (c) `card.rank != "A"` ✓ Bot.lua:3304
- (d) Highest UNPLAYED of suit ✓ Bot.lua:3307
- (e) Leading + zero plays so far ✓ Bot.lua:3279
- (f) NOT (partner certainly void in trump) ✓ **WIRED v0.9.1** Bot.lua:3328-3334
- (g) Round_stage / scoreUrgency ✓ **WIRED v0.9.3** Bot.lua:3357-3399

Plus tier (Advanced+) Bot.lua:3277, bot-partner-only Bot.lua:3293,
trickNum >= 2 Bot.lua:3318-3319, doubled-contract suppress
Bot.lua:3355.

**All sender preconditions wired.** Receiver path Bot.lua:2520-2558
handles both explicit (`S.s.akaCalled`) and implicit (bare-Ace lead)
AKA. **No drift here.**

---

## M3lm/Fzloky tier dispatch (CLAUDE.md tier table)

`Bot.IsAdvanced()` Bot.lua:48-55 — strictly extending: Advanced ⊇ M3lm
⊇ Fzloky ⊇ SaudiMaster.
`Bot.IsM3lm()` Bot.lua:60-65, `Bot.IsFzloky()` Bot.lua:71-75,
`Bot.IsSaudiMaster()` Bot.lua:77-79.

`Bot.PickPlay()` Bot.lua:3387-3417 — delegates to `BotMaster.PickPlay`
when `BM.IsActive()` returns true and `not Bot._inRollout`. **Single
canonical entry per CLAUDE.md v0.5.0 fix.**

`BotMaster.IsActive()` BotMaster.lua:133 — `WHEREDNGNDB.saudiMasterBots == true`.
`BotMaster.PickPlay()` BotMaster.lua:812 — ISMCTS dispatch.

**Tier dispatch wiring is correct and matches CLAUDE.md.**

---

## Prior findings — verification status

| Finding | Status |
|---|---|
| Bot.lua:1822 (M8 mardoofa hard-return per L08) | **CONFIRMED CORRECT.** Bot.lua:1819-1822 `if hasA[su] and hasT[su] and aceCard[su] then return aceCard[su] end`. M8 fires Sun + bidder team + trick 1 + A+T pair side suit; sends side Ace. Per Pro-2 PDF §2 reading. |
| Bot.lua:2130 (`bidderTeam` undefined — HIGH from B-Bot-08) | **FIXED v0.10.3.** Bot.lua:2128-2135 now defines `local bidderTeam = R.TeamOf(contract.bidder)` before the loop. The B-Bot-08 F1 finding is resolved. |
| Bot.lua:1705-1706 (`isBidderTeam` Hokm-only typo — Sun sweep dead) | **CONFIRMED PRESENT.** `local isBidderTeam = (contract.type == K.BID_HOKM and myTeam == R.TeamOf(contract.bidder))`. Sun sweep-pursuit at Bot.lua:1727 (`if trickNum >= 3 ... and isBidderTeam`) is therefore dead under Sun. **NOT YET FIXED.** Per Section 7 / 7-2 (which wants "Sun = 2× A+T pairs + extra A; Hokm = ..." both contracts), Sun bidder sweep pursuit is silently disabled. **HIGH severity for Section 7 / 7-2 wiring.** |
| Bot.lua:1829-1838 (Hokm Branch 3 leads non-trump boss-Ace before trump-pull) | **CONFIRMED PRESENT.** Per B-Bot-08 F3, the branch fires for ALL Hokm seats (not just defenders) on trick 1, leading the highest-unplayed in any non-trump suit. For a bidder this can mean leading A♠ before pulling trump — opp ruff vulnerability. **PRE-EXISTING BEHAVIOR;** not flagged in decision-trees.md but a strategic gap. |
| Bot.lua:3801-3806 (Bot.PickKawesh unconditional per B-Bot-10-5) | **CONFIRMED.** Bot.PickKawesh at Bot.lua:3816-3822 has no tier gate — fires for ALL bots regardless of `Bot.IsAdvanced()` / `IsM3lm()` etc. Calls `C.IsKaweshHand(hand)` which is rule-based. Per B-Bot-10-5, this means even basic-tier bots auto-claim Kawesh on qualifying hands. Decision-trees.md has no Kawesh row; this is implicit. |

---

## Summary of drift

### Doc rows STALE (`(not yet wired)` but actually wired)

| Section | Row | Actual wiring location |
|---|---|---|
| 1 | S-1 (mardoofa Sun bonus) | Bot.lua:1217-1218 |
| 1 | S-7 (cumul ≥100 Bel-fear) | Bot.lua:1269-1274 |
| 6 | 6-7 (released-from-must-ruff heuristic, AKA case) | Bot.lua:2554-2558 |
| 7 | 7-2 (trick-3 trigger says "only trick-8 currently active") | Bot.lua:1726-1735 since v0.5.19 |
| 8-S-1 | Bargiya | Bot.lua:2710-2723 |
| 8-S-2 | "want" sender | Bot.lua:2725-2760 |
| 8-S-4 | T-4 dump-ordering | Bot.lua:2762-2796 |

### Phantom function names referenced in MAPS-TO

| Doc | Reality |
|---|---|
| `Bot.PickAshkal` | Does not exist; logic is in `Bot.PickBid` (Bot.lua:1287-1410) |
| `pickFollow.deceptiveOverplay` | Does not exist; doc-design name only (rules 4-4, 4-5, 4-6 unwired) |

### Section header line refs all stale

Drift +285 to +1135 across all section headers (Section 0). Re-anchor
sweep recommended.

### Operational gaps confirmed unwired

- Section 3 L-1 (strong-card-hold): NOT WIRED (any tier).
- Section 4 Takbeer-4/5/6 (Hokm consec / non-consec / over-cut): NOT WIRED.
- Section 4 J-tripled (both rules): NOT WIRED.
- Section 4 deceptiveOverplay (4-4, 4-5, 4-6): NOT WIRED.
- Section 5 rules 2/3/6/7/8: NOT WIRED.
- Section 7-3 (sabotage own sweep), 7-4 (Qaid-bait), 7-8 (Bargiya followup), 7-9 (Reverse Al-Kaboot): NOT WIRED.
- Section 8 receiver: 8-R-3 thru 8-R-9 mostly unwired beyond basic pref read.
- Section 10 Hokm-F #1, #5, #7: NOT WIRED (F-16 scoping fix landed for #4).
- Section 11 rules 11-2, 11-6, 11-8: NOT WIRED.

### Cross-cutting concerns flagged

1. **Bot.lua:1705-1706 `isBidderTeam` Hokm-only** — Sun bidder
   sweep-pursuit (Section 7-2) is silently dead under Sun. **HIGH for
   Section 7 / 7-2 wiring claim.** Doc shouldn't claim partial-wire
   for Sun until this is fixed (or the gate broadened).

2. **Bot.lua:1829-1838 Hokm Branch 3 highest-unplayed-non-trump fires
   for bidders too** — leads side-suit Ace on trick 1 before trump
   pull. Strategic gap, not a doc-mapping issue, but worth flagging
   in Section 3 / pickLead audit follow-up.

3. **Phantom function names** — Section 4 `pickFollow.deceptiveOverplay`
   and Section 1 `Bot.PickAshkal` should either be removed from
   MAPS-TO columns or noted as design-stage identifiers.

4. **Bot.PickKawesh tier-ungated** (per B-Bot-10-5) — meld auto-claim
   fires for all tiers; decision-trees.md doesn't cover Kawesh. If
   Kawesh strategy becomes a topic, add a section.

### No extra branches in code without doc coverage

I did not find code branches firing strategy heuristics that have NO
corresponding row in decision-trees.md. The doc set is the superset of
operational rules; the code is a subset implementing them.

---

## Verdict

decision-trees.md is healthy and operational. The biggest concerns
are:
1. Stale `(not yet wired)` markings in Sections 1, 6, 7, 8 sender side
   (7 rows total).
2. Section 0 header line refs drifted +285 to +1135; re-anchor recommended.
3. Two phantom function names (`Bot.PickAshkal`, `pickFollow.deceptiveOverplay`).
4. Bot.lua:1705-1706 `isBidderTeam` typo silently disables Sun sweep
   pursuit for Section 7-2; this **invalidates the doc's "partial
   wire" claim** for the Sun half of that rule. HIGH for the Sun
   contract path of Section 7-2.

The rest of the operational chain holds: Sections 2 (escalation), 9
(Tanfeer), 10 (Hokm Faranka with F-16 scoping), 11 (reads) are wired
faithful to doc. Section 6 (AKA) is the most complete section in the
file. Section 5 (pos-4 Faranka) has 4 of 9 rules effectively wired and
correctly gates bidder-team-only.
