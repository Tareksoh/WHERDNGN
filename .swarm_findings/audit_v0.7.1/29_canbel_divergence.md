# 29 — `R.CanBel` vs `N._SunBelAllowed` divergence

HEAD = v0.7.2. Confirms Section 2 escalation finding (file 02).

## Predicate divergence

**`R.CanBel(team, contract, cumulative)` — Rules.lua:489-498**

```
if contract.type ~= K.BID_SUN then return true end
local mine = (cumulative and cumulative[team]) or 0
return mine < K.SUN_BEL_CUMULATIVE_GATE   -- 100
```

Symmetric, caller-only. Blocks when *caller's team >= 100*. Does
not look at the opposing team. Doc-text matches: only the team
<100 may Bel.

**`N._SunBelAllowed(bidderSeat)` — Net.lua:68-76**

```
return cumBidder >= 101 and cumDefender < 101
```

Asymmetric, two-sided. Bidder-team must have crossed 101 AND the
defender-team must still be below 101. If both teams are <101, OR
both are >=101, Sun-Bel is silently skipped — even though the
defender's team is below 100 in the first case (which `R.CanBel`
would explicitly allow).

Header comment cites a 14th-audit Arabic source ("ولايحق للاعب ان
يدبل خصمة الا بعد ان يتجاوز المئة") — narrower than the
glossary/decision-trees text and stricter than `R.CanBel`.

## Caller flow

After `S.ApplyContract`, host runs `_HostStepBid` (Net.lua:1528)
and on Sun calls `_SunBelAllowed`. If false → `HostFinishDeal()`
returns immediately, **PHASE_DOUBLE never opens**. Same gate fires
in `_FinalizePreempt` (1020), `_OnPreempt` (957), `_HostResolveOvercall`
(1193), `LocalPreempt` (1849), preempt-bot decision (3677).

By the time PHASE_DOUBLE is live, `_SunBelAllowed(bidder)` is
already true → `cumBidder >= 101` AND `cumDefender < 101`. The
caller of `R.CanBel` is the defender (Bel = defender's rung), so
caller-team cumulative is `cumDefender < 101 < 100`-or-`>= 100`-but-not-101.
**Bot.PickDouble:2725 and Net.LocalDouble:1759 always see
cumulative < 100** for the defender → `R.CanBel`'s Sun branch
returns true unconditionally. Dead code at HEAD.

(`R.CanBel`'s tests in tests/test_rules.lua:759-776 cover the
predicate in isolation; they pass, but the live flow can never
reach the failing branches.)

## Video #11 canonical

Decision-trees.md Section 2 (line 82) and glossary "Bel (×2)
legality gate" (line 70) both phrase the rule as: *"if one team
is at >=100 and the other below 100, the team below 100 may Bel."*
This is symmetric — phrased from the **defender's** perspective
and only requires *one* team past the threshold (the leader),
not specifically the bidder. `R.CanBel` matches this text.
`_SunBelAllowed` is stricter: it ignores the case where the
**defender** crossed 101 but the **bidder** hasn't (defender-led
Sun mid-game) — in that case the defender shouldn't Bel
*themselves*, which `R.CanBel` correctly blocks but `_SunBelAllowed`
also blocks (window never opens). The divergence is the
**bidder-led, defender-still-behind** case where bidder is at
e.g. 80 and defender is at 50: `R.CanBel` allows defender to Bel;
`_SunBelAllowed` skips Bel entirely. Video #11 wording is
ambiguous on whether the threshold-crosser must be bidder, but
the doc text in this repo (decision-trees + glossary) is
**symmetric** and matches `R.CanBel`.

## Recommendation

**Unify toward `R.CanBel`'s symmetric predicate**, but keep the
two-sided "skip PHASE_DOUBLE" optimization:

1. Replace `_SunBelAllowed`'s body with: `cumDefender < 100 and
   (cumBidder >= 100 or cumDefender >= 100)` — i.e. open the
   window iff *either* team has crossed and the defender is still
   eligible. Or simpler: `R.CanBel(R.TeamOf(defender), contract,
   S.s.cumulative)` — inline-call from Net.lua so there is one
   predicate, not two.
2. Document that `R.CanBel`'s Sun branch is the canonical gate;
   `_SunBelAllowed` becomes a thin "defender-can-Bel?" wrapper.
3. Either delete `_SunBelAllowed` or rename it `_SunBelDefenderEligible`
   to make its asymmetry self-documenting.
4. If video #11 actually requires the bidder to be the
   threshold-crosser, then update `R.CanBel` AND the doc text to
   match — currently the doc says one thing and `_SunBelAllowed`
   does another. Pick one and align everything.

Lowest-risk first move: inline `R.CanBel` in `_SunBelAllowed` so
the runtime gate matches the documented rule, then add a unit
test covering bidder@80/defender@50 → Bel allowed (currently
silently skipped).
