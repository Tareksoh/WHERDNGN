### B-68 — Exploiting human card-memory limitations: repeating suits humans have forgotten about

Identify human limitations in tracking all 32 played cards. Humans commonly forget whether a specific Ace has been played. Audit: the bot has perfect card memory via Bot._memory. Exploit: lead a suit where the human opponent has already played their only stopper (A or T), knowing they'll lose that trick even though they might "think" they can win it.

### B-69 — Human score miscount: playing as if score target is 152 when it is different

Audit whether the addon's configurable target (S.s.target) is clearly communicated to all human players. If humans are playing toward the wrong target, their urgency decisions are miscalibrated. The bot always uses S.s.target correctly. Identify whether this asymmetry is exploitable.

### B-71 — Dynamic Bel threshold lowering when opponent human Bel-tendency is known

Propose how the bot's BOT_BEL_TH and BOT_TRIPLE_TH should CHANGE when the _partnerStyle ledger shows an opponent human with bels >= 2 (habitual Beler). If the human always Bels, the bot-bidder should lower its Triple threshold — the human's Bel is less informative, so the bot needs a lower bar to accept the Triple challenge.

### B-72 — Detecting human "tell" via trump tempo: humans who lead trump in tricks 1–3

Identify the exploit path: if trumpEarly for a human seat is 2+ (they always lead trump aggressively early), the bot-defender should save high trumps for tricks 4–8 when the human has likely exhausted their trump supply. Audit whether this trump-timing model is implemented in pickFollow/pickLead defensive logic.

### B-73 — Human over-reliance on first-deal information (5 cards only)

Catalog the human cognitive bias of anchoring on the first 5-card deal and not fully adjusting when the second 3 cards arrive. Humans who make bidding decisions based on 5 cards and then play as if the 3 new cards "don't change things" are exploitable because they'll play predictably based on their first-deal assessment.
