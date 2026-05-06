### A-30 — PickDouble trump strength blend: sunStrength + trumpStr * 0.5

Inspect PickDouble (lines ~1158-1163). Defender's strength = sunStrength + 0.5 * trumpStrength. Verify the 0.5 blend ratio: why 50% of trump-as-trump rather than 100%? A defender with J+9 of trump has 34 trump card-points but only gets 0.5 * 34 = 17 added to sunStrength for Bel decision — potentially undervaluing a strong defensive trump holding.

### A-31 — Sun penalty: honors vs. distribution (penalty += 10 if count < 2 OR no honors)

Audit the OR condition in the distribution penalty (line ~393, implicit in loop). A suit with 2 cards but no honors (count >= 2, honors = false) still gets -10. Verify: a doubleton 7-8 of a suit is a genuine weakness in Sun, but should a doubleton Q-J of the same suit also be penalized? (It has honors but only 2 cards — risky in Sun.)

### A-32 — sunStrength in PickBid round 1: evaluated BEFORE suitStrengthAsTrump

Inspect PickBid round 1 (lines ~554-636). sunStrength is computed first, and if `sun >= thSun`, the function returns K.BID_SUN immediately without evaluating Hokm options. Audit: for a hand with sun=52 and one suit with a trump strength of 70, the bot bids Sun and leaves a potentially stronger Hokm contract on the table.

### A-33 — Ashkal Sun strength requirement (BOT_ASHKAL_TH = 65 in K, but actual threshold uses jitter)

Inspect the Ashkal threshold in PickBid (line ~623: `K.BOT_ASHKAL_TH or 65`). The K. constant is 65 but the jitter is ±6, meaning actual range is 59–71. Verify K.BOT_ASHKAL_TH vs. TH_SUN_BASE consistency — Ashkal should require stronger Sun than a direct bid (partner takes the contract, not the bot), suggesting a higher base than 65.

### A-34 — sunStrength for Preempt decisions vs. PREEMPT threshold 75

Audit PickPreempt (line ~1262): uses sunStrength + Ace bonus + partner bonus. At threshold 75, verify whether the function ever fires in practice when the bid card IS the Ace of a long suit (the prime preempt scenario). The +12 ace-of-bid-suit bonus is supposed to be the trigger.
