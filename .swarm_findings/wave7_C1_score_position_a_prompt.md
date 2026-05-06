### B-46 — Near-win pressure: human behavior changes when their team is 10 points from target

Identify human behavioral shifts near the win condition. Humans near winning tend to become conservative (pass contracts they'd normally bid, avoid Beling). Audit: does the bot's scoreUrgency mechanism cause it to UNDER-BID in conservative mode when the human near-win situation calls for AGGRESSIVE disruption?

### B-47 — Near-loss desperation: humans in deficit often Gahwa recklessly

Catalog human Gahwa desperation patterns: teams trailing by 80+ points often risk Gahwa on sub-optimal hands. Audit: if the bot detects a human opponent team at cumulative >= target-30, should it LOWER its own Bel/Four thresholds to take advantage of the human's likely reckless escalation?

### B-48 — Human score-blind bidding: ignoring match position in bid decisions

Identify whether human Saudi Baloot players frequently ignore their cumulative score when bidding (bid on the strength of the hand alone, not position). If humans do this, the bot's matchPointUrgency modifiers create an exploitable asymmetry — the bot plays position-aware while the human does not.

### B-49 — Human target-score awareness: do humans know the target is 152 or play to a custom target?

Inspect K.s.target usage. The addon supports configurable targets. Human players in informal games often play to 150 or 200. Audit: if the human doesn't know the configured target, their near-win behavior changes unpredictably. Check whether the bot should announce the current target prominently in the UI to prevent human confusion.

### B-50 — Human comeback mechanic: does losing team try harder or give up?

Catalog whether Saudi Baloot human teams that are far behind (80+ points deficit) play statistically better or worse. Some teams play more carefully when losing; others panic-bid. Audit whether the bot's urgency modifiers correctly model the most common human response to being far behind.
