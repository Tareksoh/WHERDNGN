# Section 5 (Pos-4 Faranka) audit — v0.7.2

**Scope:** decision-trees.md L132-145 vs `Bot.lua` `pickFollow` pos-4 branch (Bot.lua:2126-2179).
**HEAD:** v0.7.2.

## Rule-by-rule status

| # | Rule (Definite unless noted) | Bot.lua | Status |
|---|---|---|---|
| 1 | Faranka — duck with cover when partner winning + we hold A + cover | 2150-2178 | **WIRED-CORRECT** (suitCount==2 + hasA + cover gate; precedes Takbeer smother per comment 2142-2148) |
| 2 | Faranka to preserve partner's Al-Kaboot run (≥6 tricks won) | — | **NOT-WIRED** (no `tricksWon[partner]` check) |
| 3 | Anti-Faranka: holding two highest UNPLAYED of led suit | — | **NOT-WIRED** (acknowledged at 2136-2138 as "hard to detect cheaply"; suitCount==2 is a proxy, not a true two-highest-unplayed test) |
| 4 | Anti-Faranka: ≥3 cards of suit | 2176 (`suitCount == 2`) | **WIRED-CORRECT** (≥3 fails the `==2` gate) |
| 5 | Anti-Faranka: only A, no J/cover (Common) | 2155-2168 | **WIRED-CORRECT** (no cover → cover==nil → fail) |
| 6 | Anti-Faranka: T (no A), A known at LHO (Common) | — | **NOT-WIRED** (requires LHO suit-tracking from observed plays) |
| 7 | Boost: high card sits with RHO (Definite, factor 5) | — | **NOT-WIRED** (no RHO-low-played boost) |
| 8 | LHO-led + LHO is bidder, fresh hand: Faranka anyway (Sometimes) | — | **NOT-WIRED** |
| 9 | LHO-led + opps are bidders → defender, do NOT Faranka (Common) | 2152 (`R.TeamOf(seat) == R.TeamOf(contract.bidder)`) | **WIRED-CORRECT** (bidder-team-only gate) |

## 5-factor framework
- J+A in hand → not enforced (cover is T or K, not specifically J).
- Partner taking → wired (`partnerWinning`).
- Al-Kaboot in progress → NOT wired.
- Score-flip → NOT wired.
- LHO bidder leading fresh hand → NOT wired.

## Anti-triggers (Hokm-trump deferral to video #04)
Branch is gated `contract.type == K.BID_SUN` (Bot.lua:2150) — Hokm correctly excluded; deferral honored.

## v0.5.21 scoring fix
**APPLIED CORRECTLY.** `Net.HostResolveTakweesh` (2139-2140) and `Net.HostResolveSWA` (2843-2844) both use `math.floor((raw + 5) / 10)`, matching `R.ScoreRound`. No `(x + 4) / 10` remains in active code (only in a Rules.lua:810 comment as historical reference).

## Verdict
v0.5.21 ships the Definite core (rules 1, 4, 5, 9) and tier-gates correctly. 5 of 9 rules NOT-WIRED — mostly Sometimes-confidence or requiring untracked state (Al-Kaboot count, LHO suit knowledge, score-flip projection). Scoring fix verified clean.
