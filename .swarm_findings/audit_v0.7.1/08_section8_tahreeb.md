# Section 8 Tahreeb (تهريب) — audit vs Bot.lua HEAD v0.7.2

**Decision-trees source:** `docs/strategy/decision-trees.md` lines 184-219.
**Rule count:** 13 (8 sender + 4 receiver + 1 three-discard variant).
**Recording:** `Bot.OnPlayObserved` Bot.lua:410-444 — `tahreebSent[suit]`
list, partner-was-winning gate via `R.CurrentTrickWinner` reconstruction.
**Classifier:** `tahreebClassify` Bot.lua:1331-1357 → `bargiya / want /
dontwant / hint / nil`.

## Sender side (8 rules, pickFollow Bot.lua:2231-2325)

| # | Rule | Status | Site |
|---|------|--------|------|
| S1 | Bargiya (A + cover, Sun) | **WIRED-CORRECT** | 2276-2289 |
| S2 | Bottom-up ascending (want, no Ace) | **NOT-WIRED** | — |
| S3 | Top-down descending (refuse) | NOT-WIRED (T-4 emits one larger card; no multi-discard sequencing) | — |
| S4 | 2-card suit dump LARGER first | **WIRED-CORRECT** with v0.5.11 K/T/A rank-cap gate | 2308-2324 |
| S5 | Don't Tahreeb your strong suit | **NOT-WIRED** (CHANGELOG explicitly defers) | — |
| S6 | Cutter-as-Tahreeb (ruff carries signal) | **NOT-WIRED** (deferred) | — |

## Receiver side (5 rules, pickLead Bot.lua:1461-1548)

| # | Rule | Status | Site |
|---|------|--------|------|
| R1 | First Tahreeb = hint, wait for second | **WIRED-CORRECT** — `hint` returns score 0; only `bargiya/want` lead to action | 1494-1496 |
| R2 | Two-event sequence ~90% confirms | **WIRED-CORRECT** | 1494-1505 |
| R3 | Bare-T return (singleton) | **NOT-WIRED** | — |
| R4 | T-mardoofa + Sun-bidder partner → side | **NOT-WIRED** (deferred) | — |
| R5 | T-mardoofa + non-Sun-bidder → T | **NOT-WIRED** (deferred) | — |
| R6 | T-tripled → low | **NOT-WIRED** (deferred) | — |
| R7 | High-card-return when no winner | **NOT-WIRED** | — |
| R8 | Small→big partner Tahreeb + we hold T → lead T | **NOT-WIRED** (R2 prefers low-from-pref-suit, see below) | — |
| R9 | Release control after partner re-supplies | **NOT-WIRED** | — |

## 3-discard variant (1 rule)

| TD1 | Strict ascending across 3 discards | **NOT-WIRED** (CHANGELOG defers) |

## Specific checks

1. **Bargiya 2-flavor distinction (invite vs defensive shed):** **NOT
   IMPLEMENTED.** `tahreebClassify` Bot.lua:1334-1339 explicitly comments
   "Per video #14 there are two semantic flavors … but for receiver-side
   action we treat both as lead-this-back". Documented deferral.

2. **Receiver phase-split (≤4 lead immediately vs ≥5 burn 1-2 first):**
   **NOT IMPLEMENTED.** Receiver always leads lowest in pref-suit
   (Bot.lua:1534-1547); no card-count gate. Note R8 conflict: when
   partner did small→big with T in our hand, rule says lead T; current
   code leads LOWEST in the pref-suit — wrong direction.

3. **"Biggest mistake in Baloot" (Section 4 rule 1B):** **WIRED v0.7.2**
   at Bot.lua:2327-2358. Sun + partner-winning + can't beat → second-lowest
   instead of absolute lowest. Section 8 R7 (high-card-return when no
   winner) is a stronger variant of the same principle and remains
   unwired.

## Coverage summary

- **WIRED-CORRECT:** 4 of 13 (S1, S4, R1, R2) — the v0.5.10 MVP +
  v0.5.11 cap.
- **NOT-WIRED:** 9 of 13 — all CHANGELOG-tagged as deferred (Common
  shape-specific rules, 3-discard variant, strong-suit avoidance,
  cutter-as-event, Bargiya flavor split, phase-split, R7 high-return,
  R8 T-supply override, R9 release-control).
- **WIRED-WRONG:** 0. R8 is partially-conflicting with R2 (lead-low
  default contradicts T-supply rule when both apply), but this is a
  gap, not a bug — R8 logic doesn't exist to override anything.

Section 8 is the largest in the doc but Bot.lua wires only the
high-confidence Definite scaffolding; ~70% of rules remain deferred.
