### B-78 — Human Kawesh-eligible hand detection by bot: pre-redeal strategy

Audit the scenario: the bot detects via memory that a human opponent's first 5 cards show all low (played 7/8/9 in initial tricks and never won). Identify whether the bot can infer "this human has/had a Kawesh-eligible hand but didn't call it" — meaning the human may have 5+ low cards and the bot can play aggressively knowing the opponent has no winners.

### B-79 — Human bid-card reading: humans react to the visible bid card

Identify the human cognitive bias toward the face-up bid card in Saudi Baloot. A bid card of Ace-of-Hearts makes human players evaluate their Hearts suit more heavily. Audit: does the bot have any "bid card reaction" heuristic that models human over-weighting of the visible Ace? This could be used to predict a human's bidding and play.

### B-80 — Human bluff-pass: passing a strong hand to see if opponents commit

Catalog the human "trap pass" in R1: a player with a 60+ strength hand passes R1 to see if opponents bid, then potentially R2 Hokm or Sun. Audit: does the bot's PickBid lower its R2 threshold when R1 was all-pass (everyone might have trapped), or does it apply the same thresholds regardless of R1 bid history?

### B-81 — Human post-Takweesh play change: caught humans play more carefully afterward

Identify behavioral shift: a human who has been caught for an illegal play (Takweesh) tends to play more carefully for the next 2–3 tricks (fear of another call). Audit: the bot's Takweesh rate DECAYS per trick (TAKWEESH_RATE_BY_TRICK). Consider whether the rate should also DECREASE if the bot already called Takweesh this round (the human is now on guard).

### B-82 — Human Hokm bidder "trump drought" tell: delayed first trump lead

Identify the human tell when the Hokm bidder delays leading trump (goes 3+ tricks without pulling trump). This usually indicates a trump-poor hand (fewer than 4 trump). Audit: the bot's trumpEarly counter for the human bidder would be low (trumpEarly=0 through first 4 tricks). Identify whether the bot uses this to infer the human bidder is trump-poor and exploits by ruffing more freely.
