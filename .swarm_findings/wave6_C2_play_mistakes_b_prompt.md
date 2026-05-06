### B-24 — Human meld over-declaration: declaring weak sequences hoping to intimidate

Examine human meld behavior: do humans in Saudi Baloot declare EVERY eligible meld regardless of its strategic value (signaling the hand), vs. expert bots that declare all melds per PickMelds? Identify whether the current bot's unconditional meld declaration is exploitable by informed humans who now know the bot's exact sequence holdings.

### B-25 — Human takweesh under-use: humans often miss illegal plays

Identify that human players in casual games frequently miss opponent illegal plays (revoke) because they're focused on their own hand. Audit: the bot's PickTakweesh fires with 60% probability on trick 1. Does the 60% rate correctly model human detection vs. bot detection, or should the HUMAN takweesh rate (in tracks where humans can also call) be lower?

### B-26 — Human endgame SWA: overconfident SWA claims with 2–3 risky tricks remaining

Catalog the human tendency to claim SWA (سوا, "I win every remaining trick") prematurely — declaring before trump is fully exhausted. Audit: does the bot have any mechanism to respond to an opponent SWA by playing sub-optimally on purpose (trying to win a trick before the SWA resolves)?

### B-27 — Human point-counting errors: undervaluing 10 of trump in Hokm (J=20, 9=14, but T=10 often forgotten)

Identify whether human Saudi Baloot players frequently undervalue the 10-of-trump in trick-point terms (10 points, same as non-trump 10). If humans trade away their T-of-trump cheaply, the bot should exploit by forcing trump-T discards through non-trump suit pressure.

### B-28 — Human bid-round timing tells: slow human = marginal hand

Examine whether the turn timeout mechanic (K.TURN_TIMEOUT_SEC = 60) creates exploitable tells. A human who takes 40+ seconds to bid is often on a borderline hand (counting cards). Audit: does the bot have access to elapsed time on a human's turn, and could this be used to adjust threshold confidence in the human's bid?
