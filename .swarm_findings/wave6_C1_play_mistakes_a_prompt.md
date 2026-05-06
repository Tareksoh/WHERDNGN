### B-19 — Human smother error: not dumping A/T on partner's winning tricks

Identify whether human players commonly fail to feed A/T (smother) onto partner's winning tricks — they hold high cards instead of scoring with them now. Audit: the bot's smother logic is aggressive (feeds from trick 4+ or when lastSeat). Does the bot exploit humans who fail to smother by planning multi-trick sequences that isolate those held A/T cards?

### B-20 — Human Sun card ordering: leads from shortest suit first (correct) or longest (common mistake)

Examine human Sun lead patterns. Expert Saudi play leads the shortest suit in Sun (fewest cards = most likely opponents can't follow and must discard high). Novice humans lead from longest suit habitually. Audit: does the bot read a human's first Sun lead to infer whether they are expert or novice, and adjust defensive strategy?

### B-21 — Human singleton lead tell: leading a singleton immediately in trick 1 signals a ruff setup

Catalog the human tell: a player who leads a singleton in trick 1 is setting up a ruff. The bot's current logic also leads singletons, so it may produce false signals. Identify how the bot can detect human singleton leads specifically (low-value card, early lead, specific rank) and prepare to cancel the ruff.

### B-22 — Human high-lead tell in Hokm: leading A tells opponents you're void of J+9 in that suit

Audit the human tendency to lead their side-suit Ace early in Hokm defense. This tells the table "I don't have J or 9 of trump to pull, so I'm cashing aces." Identify: does the bot update any memory or inference when an OPPONENT leads an Ace? If not, is there a mechanism to infer "opponent is probably trump-weak"?

### B-23 — Human cross-trump mistake: Beling on trump strength but void in a key side suit

Catalog the human mistake of Beling (×2) with strong trump but a void in one side suit, making the contract easy for the bidder to make by leading that void suit for free tricks. Audit: does the bot currently model opponent void suits and adjust its lead strategy when leading against a human who Beled?
