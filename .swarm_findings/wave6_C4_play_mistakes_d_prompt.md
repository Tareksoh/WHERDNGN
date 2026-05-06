### B-35 — Exploiting human predictable second-seat ducking

Catalog the human second-seat low pattern. Most human players automatically play low in position 2 even with A in hand. Audit: the bot should recognize a human at position 2 who consistently ducks and plan to WIN the trick at position 3 (rather than assuming position 2 might have a stopper). This requires tracking per-seat human duck frequency in _partnerStyle.

### B-36 — Human tendency to lead partner's bid suit back

Identify whether human Saudi Baloot players reliably return their partner's bid suit (the trump suit chosen by their partner's Hokm bid) on the first available non-trump lead. If yes, the bot at position 4 (last to play in the trick) can anticipate a partner-suit return and play accordingly.

### B-37 — Human "honor-trap" lead: leading K hoping to capture A from opponent

Catalog the human honor-trap pattern: leading K of a side suit to "flush out" the A from an opponent (hoping opponent plays A to win, wasting it). Audit whether the bot's follow-play logic plays the A when a K is led (it would, since A is a winner), and whether this means humans successfully trap bot Aces regularly.

### B-38 — Human "denial" discard: throwing A of a side suit defensively to avoid being forced

Identify the human pattern of discarding a side-suit Ace in a non-trump trick to deny opponents a forced trick in that suit later. Bot logic would smother an A onto partner's trick (score points) but never discard A wastefully. Audit: if a human opponent discards an A prematurely, the bot's suitCardsOutstanding for that suit is now affected — verify the memory update.

### B-39 — Human wantOpen leaks: human body language / hesitation on escalation decisions

Examine the escalation chain timing. Humans who hesitate before Beling signal a borderline hand. Humans who Bel immediately (< 5 seconds) are confident. Audit: does the addon capture or store human response timing anywhere (e.g., turn timestamps)? If not, this is an unimplemented exploitation opportunity.
