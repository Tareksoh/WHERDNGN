### B-56 — Human repeat-lead pattern: humans who always return to the same suit

Identify whether certain human players habitually return to their opening lead suit (first-trick suit preference that persists). Audit whether the trumpEarly/trumpLate counters or the firstDiscard memory captures this tendency, and if not, what lightweight counter would encode "human prefers suit X."

### B-57 — Human anti-bot exploitation: humans who deliberately play unpredictably against bots

Catalog whether experienced Saudi Baloot players notice bot patterns and deliberately vary their play. E.g., a human who knows bots lead trump early might hold the K-of-trump specifically to be played on the bot's forced J lead. Audit: does the Saudi Master tier's ISMCTS sampling generate enough variety in its own play to be harder to predict?

### B-59 — Bot exploiting human "always Bel against Sun" reflex

Identify the human pattern of reflexively Beling against any Sun contract. If the bot knows a specific human opponent always Bels Sun, the bot's bidder team should raise the Gahwa threshold (more likely to Triple and win the escalation chain) when that human is a defender. Audit whether the style ledger's `bels` counter captures this.

### B-60 — Human partner-signal blindness: not reading bot AKA or Fzloky signals

Catalog whether human partners in Saudi Baloot practice (or cultural expectation) include explicit partner signaling. The bot sends AKA signals to all partners; Fzloky signals are implicit (first-discard). If human partners don't recognize these signals, the bot is sending signals into a void. Audit: should the bot suppress expensive signals when the partner is human?

### B-61 — Human "defensive" Sun: using Sun to block opponent Hokm when holding no Hokm-quality hand

Identify the human tactic of bidding Sun purely defensively (to deny the opponent a Hokm contract) when their own Sun is marginal (50–55 score). If humans do this frequently, the bot should raise its Bel threshold slightly for opponent Sun contracts (human is more likely to fail a defensive Sun than a genuine Sun).
