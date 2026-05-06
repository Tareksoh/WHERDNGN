### B-04 — Human R1 bidding order: position bias (seat 4 = dealer, bids last)

Examine Saudi Baloot human tendencies by bidding seat position. The dealer (seat 4) bids last and has the best information. Audit: do humans in seat 4 bid more aggressively (they know all others passed), and how should the bot calibrate its read of a seat-4 Hokm bid vs. a seat-1 Hokm bid?

### B-05 — Human "lock in the Hokm" over-bidding: bidding R2 on marginal hands to avoid Ashkal

Identify whether human players in competitive Saudi Baloot overbid R2 Hokm on slightly substandard hands (strength 30–38) to avoid giving opponents an Ashkal opportunity. If humans do this, the bot should read R2 Hokm bids with a wider uncertainty band than R1 bids.

### B-06 — Human pass patterns: double-pass as weakness signal

Analyze what a human double-pass (pass in both R1 and R2) communicates to the bot. In Saudi Baloot, a forced Sun contract from all-pass is expected. Identify whether humans strategically pass strong hands hoping to force the opponent into an unfavorable contract — a "trap pass."

### B-07 — Human partner Ashkal as combined strength indicator

Audit how the bot currently uses the Ashkal bid from partner. If an Ashkal-bidding partner is always strong (Sun 65+), the bot in the Saudi Master tier should play more aggressively — leading trumped suits earlier, taking tempo risks — since partner confirmed side-suit solidity.

### B-08 — Preempt (الثالث) usage: does the bot exploit a human's failure to preempt?

Identify whether the bot currently detects that a human DECLINED to preempt a Sun-on-Ace bid. Per current PickPreempt logic, a pass on preempt opportunity signals weakness (sun < 75 for that seat). Check if this declination is recorded and used anywhere in the bot's subsequent play or escalation decisions.
