### B-40 — Human first-card-of-hand tell: suit choice on trick 1 as distribution signal

Catalog what a human's very first lead reveals about their hand. In Saudi Baloot, expert defenders lead from a 3-card suit they want ruffed later; novices lead from their best suit. Identify whether the bot records human first-card-led information in _partnerStyle or memory and uses it in subsequent play.

### B-41 — Human escalation culture mismatch: Gulf players vs. non-Gulf players Bel frequency

Identify that Saudi Baloot human players from the Gulf region tend to Bel more aggressively (cultural norm) than players from other regions. Audit whether the bot's Bel-decision logic already accounts for this via the style ledger, or whether it requires a separate "region/culture" configuration parameter.

### B-42 — Human Sun defender over-pressure: leading trump against Sun contracts

Catalog the human error of leading trump against a Sun contract (where there IS no trump). In Sun, all cards are plain — there is no suit hierarchy. Audit: does the bot detect when a human makes a non-standard first lead in Sun (e.g., leading their Ace early vs. leading low from a weak suit) and adjust its play to exploit the opening?

### B-44 — Human "I have to save something" discard: minimum-rank discard under pressure

Identify the human discard pattern when they CAN'T win a trick: they typically discard the 7 or 8 of their most expendable suit. The bot does the same (lowestByRank). Audit: does the bot exploit situations where a human's LOW discard reveals suit exhaustion (only had the 7 in that suit) vs. a low discard from a long suit?

### B-45 — Human Kawesh under-use: humans in casual play often don't call Kawesh

Catalog whether human players in casual Saudi Baloot frequently miss their Kawesh (hand-annul) eligibility — they play bad hands when they should redeal. If humans commonly play Kawesh-eligible hands, the bot will face unusually weak opponents who take no tricks, potentially affecting trick-point distribution.
