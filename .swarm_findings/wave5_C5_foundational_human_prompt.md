### B-14 — Human vs. bot bid-signal cross-contamination in partnerBidBonus

Inspect partnerBidBonus: it treats partner bids identically regardless of whether the partner is human or bot. A bot partner's Hokm bid is reliable (calibrated thresholds); a human partner's Hokm bid may be from any hand. Audit whether the bonus magnitudes (+20, +10, +15) are appropriate for human partners or only for bot partners.

### B-15 — Human declarer vs. defender role assignment: exploitation target

Identify the key asymmetry: human bidders tend to over-estimate their contract (bid on marginal hands), while human defenders under-estimate their stoppage potential (don't Bel when they should). Summarize whether the bot is currently designed to exploit this asymmetry in escalation decisions.

### B-16 — Human over-trumping in panic: spending J or 9 of trump on low-value tricks

Catalog the "panic ruff" pattern: a human is void in the lead suit and ruffs with J-of-trump on a trick worth only 3 points (K+Q+8+7). Audit whether the bot's current play logic can EXPLOIT this by leading low-value suits when the human opponent is inferred to be void, forcing them to waste their J.

### B-17 — Human under-ruffing: playing low trump when high trump is required

Identify whether human opponents under-ruff (play 7-of-trump when forced to ruff, even when they could over-trump the current winner). This is a common mistake in casual Saudi Baloot. Audit: does the bot play to exploit under-ruffing, or does its play logic assume opponents always ruff with the minimum sufficient trump?

### B-18 — Human third-hand-low mistake: not playing high in position 3

Catalog the human tendency to play low in position 3 (not committing the highest winner), which leaves the trick vulnerable to a 4th-seat overcut. Audit: the bot's position-3 heuristic is "third hand high." Does it exploit a human position-4 opponent's expected ability to cut, or does it always play high even when position-4 is a human known to hold weak trump?
