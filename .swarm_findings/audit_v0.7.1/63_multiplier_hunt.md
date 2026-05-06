# 63 — Multiplier Hunt (Rules.lua, R.ScoreRound)

## Verdict
**Mostly clean.** Multiplier path at lines 798-822 is correct. One genuine
question (Al-Kaboot multiplier-immunity) and one cosmetic ambiguity. No
double-application bug found.

## Findings

### 1. Sun + Bel = ×4 — CORRECT but semantically collides with Four
Lines 798-803 compose: `mult = 1 * MULT_SUN(2) * MULT_BEL(2) = 4`.
This equals `Sun + Four` (2×4=8 actually) and `Hokm + Four` (1×4=4).
So Sun-Bel and Hokm-Four both yield ×4 — different rungs, identical
effective multiplier. Not a bug per spec, but worth a comment
clarifying the Sun-stacks rationale.

### 2. Sun + Triple/Four/Gahwa — UNREACHABLE (correctly gated)
`State.lua:1039-1042` (`S.ApplyDouble`) hard-routes Sun+Bel directly
to `PHASE_PLAY`, skipping `PHASE_TRIPLE`. So `contract.tripled`/
`foured`/`gahwa` are never set when `contract.type == K.BID_SUN`.
The `Rules.lua` mult formula (line 800-803) is therefore safe even
though it would compute Sun+Four = ×8 if reached. **Defense-in-depth
gap:** `Net.lua:_OnTriple/_OnFour/_OnGahwa` (lines 891, 907, 924)
do NOT check `contract.type ~= BID_SUN`. State gating is the only
barrier. Recommend adding the type check as a redundant guard.

### 3. Belote +20 — CORRECTLY multiplier-immune
Lines 818-822: `rawA = rawA + K.MELD_BELOTE` AFTER `rawA = (...) * mult`.
Comment on lines 808-816 explicitly notes the rule. The audit-fix
comment (line 812-816) explains why `meldPoints` is NOT mutated —
prevents downstream double-counting. **Clean.**

### 4. Al-Kaboot in Bel'd Hokm — POTENTIAL BUG
Lines 742-747: `cardA = K.AL_KABOOT_HOKM (250)` on sweep.
Line 805: `rawA = (250 + meldPoints.A) * mult`.
With Bel: 250 × 2 = 500 raw → 50 game points.
With Four: 250 × 4 = 1000 raw → 100 gp.
**Verify against Saudi convention** — if Al-Kaboot bonus is intended
multiplier-immune (like Belote), this is a bug. Spec in this prompt
says "Gahwa: match-win, no point multiplier" but doesn't pin Kaboot.
`docs/strategy/saudi-rules.md` should be checked. If sweeper intent
is "winner takes raw 250/220 game points regardless", then current
code over-multiplies on Bel'd sweeps.

### 5. Carré of Aces in Sun — CORRECT
`Constants.lua:95`: `MELD_CARRE_A_SUN = 200`. Detected at line 241
only when `isSun`. Then `meldPoints * mult = 200 * 2 = 400 raw` →
40 game points. Matches "Four Hundred" (الأربع مئة) name.

### 6. Reverse Al-Kaboot — NOT IMPLEMENTED
No reference to "reverse" sweep handling. If added, it must route
through the same `cardA/cardB * mult` line (805-806) to inherit
escalation correctly, OR be added post-multiplier like Belote.
Decision required upstream.

## Files
- `C:/CLAUDE/WHEREDNGN/Rules.lua` (lines 691-695, 742-747, 798-822)
- `C:/CLAUDE/WHEREDNGN/State.lua` (line 1039-1042 — Sun escalation gate)
- `C:/CLAUDE/WHEREDNGN/Net.lua` (lines 888-929 — missing redundant type guard)
- `C:/CLAUDE/WHEREDNGN/Constants.lua` (lines 68-72, 94-95, 103, 110-111)
