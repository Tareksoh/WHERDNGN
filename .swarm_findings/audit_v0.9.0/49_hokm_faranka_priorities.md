# Hokm Faranka exception interactions — v0.9.0 priority audit

HEAD = `9c32c50`. Block: `Bot.lua` 2635-2731 inside `pickFollow`.

## Decision tree (literal sequence)

```
1. M3lm + Hokm + leadSuit + #winners > 0  (gate, line 2635)
2. local farankaTriggered = false              (2637)
3. count trumps;  myTrumpCount == 2 → trigger  (Exception #2, 2640-2646)
4. if not triggered AND HighestUnplayedRank(trump)=="9" AND hold9
   → trigger                                   (Exception #3, 2658-2667)
5. if not triggered AND contract.bidder == seat AND both opps void
   → trigger                                   (Exception #4, 2670-2682)
6. if triggered AND opp-bidder led trump-Q AND hold J+8
   → un-trigger                                (Anti-rule, 2685-2703)
7. if triggered → return non-winner            (2705-2731)
```

Every if-fires-then-skip uses `not farankaTriggered`, so this is a
short-circuit OR with **stable order #2 → #3 → #4**, then a single
**post-veto** anti-rule.

## Scenario verdicts

**S1 (#2 + #3, J dead, you hold 9 + one other trump).** Both apply.
Branch #2 sets the flag at line 2646; branch #3's `not farankaTriggered`
guard short-circuits and never runs. **Bot Faranka's**. Result is the
same either way (both want Faranka), so behavior is correct, but only
#2 is exercised. No conflict.

**S2 (anti-rule pos-4 take-with-9 + #3).** The narrow "anti-rule" the
audit memo names ("opp Faranka'd, pos-4, only the 9, take with 9")
is **NOT WIRED** at v0.9.0 (per `22_section10_now.md` line 47). Only
the J+8 rebuttal anti-rule exists. So #3 fires unopposed and the bot
withholds the 9 — a **likely behavioral bug** when opp already
Faranka'd, but not a code-level conflict.

**S3 (#2 + opp is bidder).** Exception #2 has **no bidder-team check**
(line 2640-2646). #4's `contract.bidder == seat` guard skips it when
opp bid, but **#2 still fires**. The doc's "anti-rule: don't Faranka
when opp bid Hokm" is **NOT enforced** for #2. Bot will Faranka into
opp's contract on a 2-trump hand. Real conflict — #2 wins.

**S4 (#4 + #3).** #3 is checked first (line 2658), #4 second (2670).
If J is dead and you hold 9, #3 fires; #4 never runs. Order is
deterministic: **#3 wins**. Both want the same outcome (Faranka), so
no behavioral divergence, but logging would mis-attribute the trigger.

## Verification

- **Documented?** No. The if/elseif chain has no comment stating
  priority order or anti-rule veto semantics. Section 10 doc drift
  (HIGH) still flags all four as "(not yet wired)" — see memo 22.
- **Tests?** None. `Grep faranka` over `tests/` returns zero hits.
  Every trigger path and the J+8 rebuttal is regression-bare.

## Verdict

Order is deterministic (#2 > #3 > #4, then anti-rule J+8 veto), but
**two real gaps**: (a) #2 lacks an opp-bidder anti-rule, so the bot
Faranka's into enemy contracts on 2-trump hands; (b) the pos-4
take-with-9 anti-rule from the audit prompt is not coded, so #3
fires when it shouldn't. Add bidder-team guard on #2 and a
zero-test pin per branch.
