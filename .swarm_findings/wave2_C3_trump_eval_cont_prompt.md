### A-14 — Preempt threshold BOT_PREEMPT_TH = 75 calibration

Audit the PickPreempt threshold (line ~1261). At 75, a seat needs Sun-strong hand plus either the bid Ace (+12) or a Sun-bidding partner (+8). Check whether this threshold is reachable in practice (70% of preempt-eligible positions) vs. too restrictive (bot never exercises preempt right, giving humans a free Sun steal).

### A-15 — Bid position ordering in Ashkal gate (lines ~594-603)

Inspect the `bidPos` calculation from dealer position. Verify the seat ordering logic `(d%4)+1, ((d+1)%4)+1, ((d+2)%4)+1, d` is correct for Saudi Baloot turn order (dealer bids last). Check whether bidPos=3 and bidPos=4 are the correct seats that can call Ashkal under Saudi rules.

### A-17 — Length bonus: (count-2) * 5 calibration

Inspect the `math.max(0, count - 2) * 5` length bonus (line ~320). With 5 trump cards, this adds +15 on top of card point values. Verify this doesn't overweight pure length (7-8-9-Q-K of trump has length=5 but only 7 card-points; the +15 length bonus may over-lift mediocre length).

### A-18 — J+9 synergy bonus: +10 basic vs. +18 advanced

Audit whether the +18 Advanced J+9 bonus (line ~323) correctly reflects the Saudi tournament valuation of J+9 as the two highest trump cards (combined 34 points out of 62 trump-suit total). Consider: does the synergy bonus double-count cards already individually scored (J=+20, 9=+14)?

### A-19 — No-J penalty: multiplier 0.4 vs. disqualification

Inspect the `strength * 0.4` penalty for no-J hands (lines ~324-330). At 0.4x, a hand with A+T+9+K+Q in trump (raw ~62) becomes ~25, well below any threshold. This effectively prohibits bidding trump suits with no J in Advanced mode. Audit whether Saudi expert players ever bid trump with no J (e.g., A+9+T of 5-card suit), which would make 0.4 too aggressive.
