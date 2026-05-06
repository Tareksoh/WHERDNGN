# Section 2 (Escalation) — code audit @ v0.7.2 (93b1e9d)

Decision-trees.md Section 2 has 7 rules. Anchors verified live:
`Bot.PickDouble` Bot.lua:2714, `PickTriple` 2846, `PickFour` 2877,
`PickGahwa` 2922 — doc header still says 2403/2534/2564/2608 (**stale**).

## WIRED-CORRECT
- **R2 (Hokm Bel always allowed)** — `R.CanBel` Rules.lua:491-493 returns `true` for non-Sun. `Bot.PickDouble` 2725 falls through.
- **R4 (call-window gating)** — escalation runs only inside `PHASE_DOUBLE`/`TRIPLE`/`FOUR`/`GAHWA`; phase-driven, no mid-trick path.

## WIRED-WRONG
- **R1 (Sun Bel forbidden when own team >= 100)** — DUAL ENFORCEMENT WITH MISMATCHED PREDICATES.
  - `R.CanBel(team, contract, cum)` Rules.lua:489-498 blocks when `cum[team] >= K.SUN_BEL_CUMULATIVE_GATE` (100). Symmetric, caller-only.
  - `N._SunBelAllowed(bidderSeat)` Net.lua:68-76 requires `cumBidder >= 101 AND cumDefender < 101`. Asymmetric, only opens window when bidder is ahead AND defender behind.
  - These are NOT defense-in-depth — they check different things. `R.CanBel` would let A=99/B=120 defender (B) Bel a Sun bid by A; `_SunBelAllowed` would NOT (B is the defender but already past 100). Conversely if A=80 bids Sun and B=50 → `R.CanBel(B)` = true; `_SunBelAllowed` = false (bidder hasn't crossed 100). The host skips PHASE_DOUBLE entirely (Net.lua:1518, 1020, 1193, 957) before any seat ever calls `R.CanBel`. So `R.CanBel` is effectively dead code in the Sun path: the gate Section 2 documents (rule R1) is the LOOSER `R.CanBel` semantics; the gate ACTUALLY enforced is the STRICTER `_SunBelAllowed`. Doc text "only the team <100 may Bel" matches `R.CanBel` only.

## NOT-WIRED
- **R3 (Round-1 Bel restriction)** — TBD per doc; no `bidRound`/`roundNumber` check in any escalation picker.
- **R5 (Trick-3 Kaboot-pursuit trigger)** — "partial wire"; PickDouble/Triple/Four/Gahwa do not consult trick state.
- **R6 (Sabotage own sweep when MULT_BEL × hand_total > AL_KABOOT_SUN)** — no score-aware sweep abandonment in any picker.
- **R7 (Qaid-bait defender maneuver)** — defensive-note only; no code.

## CODE-WITHOUT-DOC
- **Score-urgency threshold modulation** (`combinedUrgency` capped ±15, floored at `K.BOT_*_TH - 16`) Bot.lua:2777, 2801, 2855, 2887, 2918, 2936 — no Section 2 anchor.
- **Style-ledger threshold drops** (defensive-Sun bidder +8, habitual Beler -8, gahwaFailed -5/-8, triples -5) Bot.lua:2787-2793, 2863-2873, 2896-2911 — M3lm-tier reads with no doc rule.
- **wantOpen heuristic** (open if strength >= jth+20) Bot.lua:2809, 2842 — implementation detail, undocumented.
- **PickGahwa terminal arity fix** Bot.lua:2933-2938 — undocumented but harmless.

## NOTES
- Highest-leverage fix: reconcile R1 doc text vs `_SunBelAllowed` (host enforcement is stricter than what the doc and `R.CanBel` describe).
- Refresh Section 2 line refs (2403→2714, 2534→2846, 2564→2877, 2608→2922).
- Tests/test_rules.lua N exercises only `R.CanBel`; `_SunBelAllowed` has no direct unit-test coverage of the 99/0 vs 100/0 asymmetry vs bidder side.
