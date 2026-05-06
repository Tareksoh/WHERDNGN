### B-09 — Human bidding in team context: partner's prior bid and its honesty

Examine whether the bot correctly adjusts the reliability of partner's bid when the partner is a human vs. a bot. Human partners may under-bid (conservative culture), over-bid (show-off), or use private signals (e.g., always bid Hearts with a specific pattern). Audit whether the bot's partnerBidBonus is human-aware or assumes all partners are honest.

### B-10 — Human tendency to NEVER pass Sun once in lead (score near target)

Identify the human behavioral pattern of refusing to let opponents win the Sun multiplier when the opponent's team is near the win target. Humans near-losing often Bel reflexively against any Sun contract. Audit: the bot doesn't currently MODEL the human opponent's Bel tendency — it only decides whether to Bel itself.

### B-11 — Reading human Bel decisions: Bel on any 70+ or reflexive Bel?

Catalog Saudi Baloot human Bel tendencies: (a) always Bel if strong regardless of score, (b) only Bel when bidding team is near target (desperation Bel), (c) Bel as habit (players who Bel 80% of the time). Identify which pattern the bot's partnerStyle.bels counter approximates and whether the approximation is useful.

### B-12 — Human Triple tendency: bidders who always or never Triple

Examine Saudi Baloot Triple patterns. Some human bidders always accept a Bel with Triple (confidence culture); others always close by not Tripling (conservative). Identify how the bot's `_partnerStyle[seat].triples` counter should be used to predict a HUMAN opponent's next Triple decision.

### B-13 — Human Gahwa frequency: is Gahwa a cultural show-off move?

Audit whether human Saudi Baloot players call Gahwa at much higher rates than the bot's BOT_GAHWA_TH = 135 would suggest (cultural bravado vs. card-optimal). If humans call Gahwa on weak hands, the bot should treat an opponent Gahwa as a potential bluff and play accordingly.
