# Audit v0.9.0 — decision-trees.md Section 8 (Tahreeb)

**HEAD:** v0.9.0 (9c32c50). SoT: `Bot.lua` sender 2425–2556, classifier 1484–1519,
receiver 1623–1717.

## Sender (line 188–197)

| Rule | Status | Evidence |
|---|---|---|
| Bargiya — Sun, A-of-X with cover | **WIRED-CORRECT** | 2470–2483, BID_SUN gate, `#cards>=2`, returns A. |
| Want / ascending (no Ace) | **WIRED-CORRECT** (v0.9.0) | 2485–2520. ≥3 cards w/ A or T, returns lowest non-winner. Cross-check of file 13 confirmed; ordering vs T-4 / Bargiya correct. |
| Don't-want / descending multi-card | **NOT-WIRED** as full sequence; T-4 only handles the 2-card subset. |
| 2-card-suit dump LARGER first (T-4) | **WIRED-CORRECT** | 2522–2555 with v0.5.11 K/T/A floor. |
| Don't-Tahreeb-strong-suit (opposite-color/shape) | **NOT-WIRED**. No suit-pair ledger; iterates {S,H,D,C}. |
| Cutter ruff = Tahreeb event | **NOT-WIRED**. Ruff branch makes no Tahreeb-aware suit choice. |
| Sender strong-suit X w/ only 3 left → don't Tahreeb FROM X | **NOT-WIRED**. No hand-shape veto. |

## Receiver (line 203–212)

| Rule | Status | Evidence |
|---|---|---|
| 70/25/5 first-Tahreeb prior across 3 suits | **NOT-WIRED**. Single non-A → `"hint"` (1503), scored 0 (1665). No prob spread. |
| 2-event ascending → lead inferred suit | **WIRED-CORRECT**. `"want"` (1516), score 2, lead-low at 1703–1717. |
| Bare-T singleton → lead T | **NOT-WIRED**. Receiver calls `lowestByRank` (1715); no singleton-T promotion. |
| T-doubled, partner Sun-bidder → SIDE | **NOT-WIRED**. No `bidType==BID_SUN && bidder==partner` branch. |
| T-doubled, non-Sun-partner → lead T | **NOT-WIRED**. Same low-default. |
| T-tripled → lead LOW | **WIRED-COINCIDENTALLY** via `lowestByRank`, not deliberate count branch. |
| Bargiya 2-flavor (`bargiya` vs `bargiya_hint`) | **WIRED-CORRECT** (v0.9.0). 1497–1502; weights 3/2/1 at 1662–1665. File 14 confirmed; test pin still absent. |
| High-card-return / no absolute lowest (receiver) | **NOT-WIRED** as Tahreeb-specific. The v0.7.2 Section 4 rule 1B at 2558–2589 (Sun, second-lowest) is sender-side, partial overlap only. |
| Phase split (≤4 vs ≥5 cards) | **NOT-WIRED**. No card-count / trick-number gate around receiver. |

## Three-discard variant (line 218)

| Rule | Status |
|---|---|
| 3-card cross-trick small→big→bigger | **NOT-WIRED**. Want-arm emits only ONE lowest non-winner; subsequent discards fall to T-4 / `lowestByRank` and ascend coincidentally. No prior-emission ledger enforces strict ascent. |

## Section 4 rule 1B pin

`Bot.lua:2558–2589` (v0.7.2, Sun-only, second-lowest fall-through) survives v0.9.0 unchanged. This is sender re-entry preservation, NOT the Section-8 receiver "don't play absolute lowest" rule (line 209) — that one remains NOT-WIRED.

## Summary

WIRED-CORRECT: 5 (Bargiya sender, Want sender, T-4 doubleton, Bargiya 2-flavor classifier, want-receiver lead-low). NOT-WIRED: 9. WIRED-COINCIDENTALLY: 1 (T-tripled). The two flagship v0.9.0 wires (want-arm, Bargiya 2-flavor) cross-check clean. Section 8 still has the largest gap surface in the doc.
