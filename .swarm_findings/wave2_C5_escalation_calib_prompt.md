### A-50 — Bel threshold K.BOT_BEL_TH = 70 and its gap to Triple TH = 90

Audit whether the 20-point gap between Bel (70) and Triple (90) thresholds correctly models the "Bel opens, Triple requires stronger hand" sequence. Verify: a defender with strength=75 opens Bel (wantOpen=false), blocking Triple. Check whether `wantOpen = strength >= jth + 20` means a defender needs 70+20=90 strength to open — exactly equal to the Triple threshold, so only defender-strong hands can open a chain the bidder can match.

### A-51 — Four threshold K.BOT_FOUR_TH = 110 and Gahwa TH = 135

Audit the Four (110) and Gahwa (135) thresholds. At 135 for Gahwa, the bidder needs near-perfect strength. Verify: what is the maximum achievable escalationStrength for a realistic deal? If the max is, say, 180, Gahwa fires 26% of the time it's eligible. If the max is 140, it almost never fires. Enumerate realistic upper bounds.

### A-55 — Escalation during play vs. pre-play phase gating

Audit whether the escalation pickers (PickDouble, PickTriple, PickFour, PickGahwa) are correctly gated to the PHASE_DOUBLE / PHASE_TRIPLE / PHASE_FOUR / PHASE_GAHWA phases respectively. If called out of phase (e.g., PickDouble during PHASE_PLAY), what do they return? Verify no phase guard exists in the functions themselves — responsibility falls entirely on Net.lua's dispatcher.

### A-56 — Score urgency stacking cap: scoreUrgency + matchPointUrgency limit

Audit the combined urgency output: scoreUrgency returns max +12, matchPointUrgency returns max +10 (after the cap in matchPointUrgency). Combined max = 22. Applied to BOT_BEL_TH=70: effective threshold drops to 48 in desperate mode. Verify whether a threshold of 48 for Bel is sane (any hand strong enough to hold any cards qualifies) and whether the cap in matchPointUrgency is correctly placed.
