### B-70 — Human cultural convention: Saudi Baloot "Bel is a compliment to the bidder" norm

Catalog the Saudi Baloot cultural norm where Beling is considered a respectful acknowledgment of the bidder's strength — some humans Bel as social convention even on marginal hands. If a human Bels on every contract regardless of hand, the style ledger's `bels` counter will saturate and lose predictive value. Audit whether a Bel-saturation detection (bels > 3) should suppress the partnerStyle usage for that seat.

### B-74 — Human over-ruffing tell: ruffing when partner is already winning

Catalog the human mistake of ruffing a trick where their own partner is currently winning. This "partner-ruff" error gives the trick to the wrong team. Audit: does Bot._memory record cases where a human opponent RUFFED a trick their own partner was winning? If so, this flags the human as error-prone and the bot should adjust its play to make those ruffing scenarios more frequent.

### B-75 — Human tendency to lead highest card in suit (vs. bot's lead lowest)

Examine the contrast: the bot leads the LOWEST card from its longest non-trump suit (preserving high cards). Many human Saudi Baloot players do the opposite — they lead their HIGHEST card to "test" if opponents can beat it. Audit whether the bot can detect this pattern from a human's opening leads and use it to infer the human's complete suit structure.

### B-76 — Human reaction to losing multiple tricks: "tilt" behavior

Identify whether humans who lose 4+ consecutive tricks change their play style (more reckless leading, attempting come-back Gahwa). The style ledger does not currently model "consecutive loss" behavior. Audit whether a cumulative loss indicator (last N tricks won by opponent) would be valuable.

### B-77 — Exploiting human over-commitment to one suit

Identify the human bias of committing to a single suit throughout the round (leading it repeatedly even after opponents are void). Audit: if the bot's void memory shows a human opponent has no H and keeps leading H anyway (error), the bot should ruff efficiently and build point totals rather than ducking.
