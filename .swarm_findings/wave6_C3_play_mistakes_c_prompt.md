### B-29 — Human consistent trump-lead culture: "always pull trump first" players

Catalog the Saudi Baloot convention of always leading trump immediately as the bidder. Human bidders who follow this culture signal their plan early. Audit: when the bot DEFENDS against a human who always leads trump first, the bot should expect tricks 1–3 to be trump-led and can adjust its discarding strategy to dump losing side cards in those tricks.

### B-30 — Human first-trick meld silence: not declaring when opponent meld would be crushed

Identify the human strategist pattern of NOT declaring a meld (even an eligible one) when the opponent's already-declared meld outranks it. In Saudi Baloot, a lower-ranking meld is overridden by a higher one. Audit whether the bot's current PickMelds declares all melds regardless — and whether silence on a meld when opponents have a higher meld is ever correct strategy.

### B-32 — Human signal exploitation: bot should SEND false signals to human opponents

Identify whether the bot has any mechanism to MISLEAD human opponents via deceptive discards. Currently the bot sends honest Fzloky signals to its partner. Audit: should a Fzloky+ bot send a HIGH discard in a suit it's actually strong in (when opponent is watching) to lure a trump-lead from a human opponent?

### B-33 — Human AKA interpretation: do human players respect bot AKA signals?

Examine whether human players in practice honor an AKA signal from a bot partner (not over-trumping the signaled suit). If humans routinely ignore AKA, the bot's AKA signal has no partner-coordination value. Identify whether AKA should only be sent when ALL partners are bots, or whether it's still worth sending to human partners.

### B-34 — Human partner reading: bot should model human over-Trump tendencies from style ledger

Inspect the trumpEarly/trumpLate counters in _partnerStyle. These count bot plays, but if human plays are also observed via OnPlayObserved, the counters would capture human patterns too. Audit: are human plays passed to OnPlayObserved? If yes, the trumpEarly counter for a human "always leads trump" player should accumulate and be readable.
