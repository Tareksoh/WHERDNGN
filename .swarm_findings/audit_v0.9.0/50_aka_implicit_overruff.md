# 50 — Implicit AKA + over-ruff scenario (v0.9.0)

## Scenario

Hokm contract. Partner leads bare A of Spades (suit X, non-trump).
Opp-1 follows. Opp-2 ruffs with J of trump → opp-2 now holds the
trick. Bot is 4th seat, void in Spades, holds trump.

**Question:** does the implicit-AKA suppress branch erroneously
fire and discard, or does the bot correctly over-trump?

## Verdict: HANDLED CORRECTLY

The implicit-AKA branch in `Bot.lua` `pickFollow` (lines
2305-2316) sets `implicitAKA = true` only if **every** clause
matches, and the suppress gate (lines 2317-2329) requires
`partnerWinning` as a precondition — `partnerWinning` is
`true` iff `R.CurrentTrickWinner(trick, contract)` returns
`R.Partner(seat)` (line 2270). Once opp-2 over-trumps, `curWinner`
is opp-2, so `partnerWinning == false` and the `if Bot.IsAdvanced()
... and partnerWinning and (explicitAKA or implicitAKA)` gate
fails. No discard. Falls through to normal pickFollow.

## Per-question audit

1. **`pickFollow`** — line 2270 `partnerWinning = curWinner and
   R.Partner(seat) == curWinner`. After opp-2's J of trump,
   `R.CurrentTrickWinner` returns opp-2 (lines 40-58 of
   `Rules.lua` — when any trump is played, only trumps are
   eligible for "highest"). `partnerWinning` is false. AKA
   suppress short-circuits.

2. **`Bot.PickPlay`** — delegates through `legalPlaysFor` →
   `pickFollow`. With Spades void and partner-not-winning, the
   `winners` list is built via `wouldWin` (line 1474),
   simulating play + `CurrentTrickWinner`. Only trumps > J
   produce wins. Bot picks from those (or under-trumps if no
   over-cut exists). 4th-seat path: line 2802+ "Highest winner
   so the 4th seat can't easily overcut" — but with `pos == 4`
   no further opponent plays, so highest trump-winner is taken.

3. **`R.IsLegalPlay`** — lines 145-158: when can't follow, it
   re-checks `R.CurrentTrickWinner`; partner-winning shortcut
   fails (opp-2 winning), `hasTrump=true` fires, `must trump`
   error rejects any non-trump. Then must-overcut check (lines
   173-183) forces a trump > J if available.

4. **Implicit-AKA gate** — gates on `partnerWinning` (line 2318)
   AND lead-was-bare-Ace (lines 2305-2315). Both required. Pure
   "lead suit was bare Ace" alone does NOT suppress. Correct.

## Conclusion

Defense is robust. No bug found. The `partnerWinning` precondition
on line 2318 is the load-bearing guard — removing it would
introduce the suppress-after-over-ruff bug, but it is currently
present and tested via `R.CurrentTrickWinner`'s correct
trump-played semantics.
