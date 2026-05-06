### B-95 — Human score-position signaling via bid aggressiveness

Catalog whether human Saudi Baloot players signal their cumulative score pressure through bid aggressiveness. A team down by 60+ tends to bid more Sun contracts (higher multiplier). Audit: the bot's scoreUrgency reads S.s.cumulative and adjusts thresholds. But for OPPONENT bidders, the bot doesn't currently read opponent score pressure and predict opponent bid aggressiveness.

### B-96 — Human "show the Ace" culture: Aces are always played early in Saudi Baloot

Examine the Saudi cultural norm of playing Aces early in a round (before they can be trumped). If human opponents follow this norm, the bot should expect Aces from opponents in tricks 1–3 and plan its trump use accordingly — hold trump for tricks 4+ when Ace threats have been exhausted.

### B-97 — Human post-meld play pattern: humans who declared a sequence lead from it

Identify human post-meld leading pattern: a human who declared a Tierce (3-sequence) in a suit often leads from that suit in early tricks to establish trick count. Audit: does the bot read a human's declared meld as a lead-intention signal and prepare the void/cover response?

### B-98 — Human endgame A-of-trump retention: waiting for the last trick

Identify human tendency to hold the A-of-trump as a guaranteed last-trick capture (for the 10-point last-trick bonus). Audit: in Hokm, A-of-trump is the second-highest trump (below J and 9). If the opponent holds A-of-trump and the bot has exhausted J+9 through trump pulls, the human WILL win the last trick. Does the Saudi Master rollout model this correctly?

### B-99 — Human hesitation on Kawesh call: some humans don't know they're eligible

Identify that human players unfamiliar with Kawesh rules frequently play Kawesh-eligible hands. If the bot detects an opponent played all 7/8/9 cards in tricks 1–3 (and never won), it can infer the opponent had a Kawesh hand and didn't call it. This means the current round's full 8 tricks with no opponent Aces — the bot's team should capture all trick points.
