# 17 — Section 2 Escalation re-audit @ HEAD v0.9.0

Re-grep results vs decision-trees.md Section 2 header line 78.

## Line-anchor drift in Section 2 header

Doc says: `PickDouble 2403, PickTriple 2534, PickFour 2564, PickGahwa 2608`.
Live: `PickDouble 3068, PickTriple 3215, PickFour 3246, PickGahwa 3291`.
Drift +597..+683 lines. **D1 line-anchor pass NOT done.** Same for
inline references "Bot.lua:1787" for CanBel (CanBel actually at
`Rules.lua:489`) and "Bot.lua:953" / "Bot.lua:1457" for pickLead /
pickFollow (live: `pickLead 1521`, `pickFollow 2257`).

## Per-rule status

| Doc rule | Live status | Evidence |
|---|---|---|
| **Sun ≥100 → Bel forbidden** (Definite) | **WIRED** | `Bot.PickDouble` Bot.lua:3098-3107 calls `R.CanBel(R.TeamOf(seat), contract, S.s.cumulative)`. Wire-side gate `Net.lua:859-867` rejects illegal Bel + sends MSG_SKIP_DBL. |
| **Hokm any score → Bel allowed** (Definite) | **WIRED** | `R.CanBel` Rules.lua:491-493 returns true for non-Sun unconditionally. |
| **Round-1 Bel restricted** (Sometimes / TBD) | **NOT WIRED** | No `round`/`firstRound`/anti-grief predicate anywhere in Bot.PickDouble or Net._OnDouble. As doc says "follow-up video to confirm exact mechanism", still TBD. |
| **Cards-revealed → Bel window closed** (Common) | **WIRED via phase** | `Net._OnDouble` Net.lua:858 hard-gates `S.s.phase ~= K.PHASE_DOUBLE`. ApplyDouble (State.lua:1060) transitions to PHASE_PLAY immediately on close (lines 1071,1076,1094,1112). Once first card plays, phase is PLAY and PickDouble is unreachable. |
| **Trick-3 Kaboot pursuit** (Common, partial) | **WIRED** | `pickLead` Bot.lua:1543-1554: `if trickNum >= 3 and trickNum <= 7 and isBidderTeam ... mySwept == trickNum-1 → sweepPursuitEarly`. Triggers boss-lead branch from trick 3. The "Kaboot-feasible shape" precondition (J+9 trump + cover + void/singleton + partner-supply) is NOT checked — current trigger is purely mySwept == trickNum-1. **Coarser than doc.** |
| **تخريب الكبوت — Sun bidder Bel-multiplier > Kaboot sabotage** (Sometimes) | **NOT WIRED** | No `K.MULT_BEL × hand_total > K.AL_KABOOT_SUN` comparison anywhere in pickFollow. Doc itself flags `(not yet wired)`. |
| **Defender Qaid-bait (تقيد عليه)** (Sometimes) | **NOT WIRED, by design** | No `qaidBait`/`misQaid` predicate. Doc says "bot likely should NOT do this without dedicated heuristic." Status unchanged. |

## D2 R.CanBel vs N._SunBelAllowed

**STILL DIVERGENT.** `R.CanBel` Rules.lua:489-498 = `mine < 100`
(symmetric, single-team). `N._SunBelAllowed` Net.lua:68-76 still
requires `cumBidder >= 101 AND cumDefender < 101` (asymmetric,
both-team). PickDouble (Bot.lua:3105) and `_OnDouble`'s
post-receive guard (Net.lua:859) use `R.CanBel`; the four legacy
sites Net.lua:977,1040,1251,1588,1936,3791 still call
`_SunBelAllowed`. CHANGELOG "partial D2" reflects: doc D2 not
ticked off; only `_OnDouble` migrated. Audit_v0.7.1 finding 29
recommendation (unify on R.CanBel) **NOT applied.**

## Summary

5/7 Section 2 rules wired; 2 unwired (sabotage, qaid-bait) plus
TBD round-1. R.CanBel correctness gate complete on Bel-call path;
divergence with `_SunBelAllowed` cosmetic but not closed.
