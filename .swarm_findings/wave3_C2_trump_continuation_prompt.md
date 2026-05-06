### A-22 — suitCardsOutstanding calculation for trump-exhaustion detection

Audit the `suitCardsOutstanding` function (lines ~897-913). It counts own hand + all played cards in memory. Verify: (a) it correctly includes in-progress trick plays (not just completed tricks), (b) it handles the case where the bot is playing and its own candidate card has not yet been played — the function reads hands as-is, not after the candidate card is removed.

### A-23 — highestTrump selection in bidder lead (line ~800)

Inspect the bidder's trump lead: `highestTrump(legal, contract)` plays the absolute highest trump. Audit whether this is correct at all trump counts — playing J of trump immediately is textbook J+9 extraction, but playing the J when holding J+9+A+T+K+Q of trump wastes the J-overforce on minor cards; 9 as first lead would be more efficient.

### A-24 — Trump ruff conservation in pos-3 follow (lines ~1034-1044)

Inspect the `lowestByRank(trumpWinners, contract)` path for position-3 trump-only winners (lines ~1041-1043). Verify: when trumpWinners includes J (rank 8), the lowest trump winner could still be J if it's the only trump. Check whether there's a preference to use Q/K of trump for ruffing and save J for lead forcing.

### A-26 — sunStrength: distribution penalty cap lowered 25→18

Audit the penalty cap softening (line ~395: `math.min(penalty, 18)`). With 4 weak suits each contributing -10, a fully lopsided hand is only penalized -18 (not -40). Verify this correctly models the Saudi "a void suit kills your Sun" principle — should the cap be per-void rather than global?

### A-27 — Long-suit walk bonus: count >= 5 AND (hasA or hasK)

Inspect the `+6 per card beyond 4` walk bonus (lines ~382-386). A 6-card suit with Ace adds +12. Audit: in Saudi Baloot with 8 cards per suit, 6-card suits are rare (deal deals only 8 cards total). Verify the bonus fires on realistic hands; a player holding 6+ cards of one suit has a 1-card or shorter side suit almost certainly.
