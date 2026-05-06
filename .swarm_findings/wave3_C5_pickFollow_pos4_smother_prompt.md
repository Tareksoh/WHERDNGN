### A-43 — Sun-contract follow when can't beat: lowest rank vs. lowest point value

Audit pickFollow in Sun contracts when no winner exists. The bot plays `lowestByRank(legal)`. In Sun, trick rank is K.RANK_PLAIN where 7 < 8 < 9 < J < Q < K < T < A. Lowest-by-rank is 7 (0 points). Verify this is correct — in Sun you'd prefer to discard a 9 (0 pts, rank 3) over a J (2 pts, rank 4). Both are 0-point or low-point, but the optimal throw-in in Sun is often the J-of-off-suit (2 pts vs. 0 pts for 9/8/7).

### A-44 — Trick points threshold for "decent points, throw lowest-value loser" in pos-4

Audit the last-seat discard (lines ~1051-1068). The bot throws lowest non-trump loser regardless of how many points are at stake. There is no threshold gate for trick points — a trick with 30+ points on it (A+T+K) gets the same discard strategy as a trick with 0 points. Consider whether high-value tricks warrant a trump-ruff attempt from last seat even when the trick has been lost to the opponent.

### A-45 — pickFollow void inference cross-check: does the follow-logic USE Bot._memory?

Audit whether pickFollow ever reads Bot._memory for opponent void status. The lead heuristic (pickLead) uses `opponentsVoidInAll` (free-trick detection), but pickFollow does not appear to read void information. Verify: is there a scenario in follow-play where knowing opponent A is void in the lead suit should change the bot's strategy (e.g., not ruffing because partner can over-ruff for more points)?

### A-46 — Legal plays list: legalPlaysFor called in PickPlay before BotMaster.PickPlay

Inspect the BotMaster.PickPlay (line ~494) vs. Bot.PickPlay (line ~1110) dispatch. Bot.PickPlay builds its own legal list. BotMaster.PickPlay builds its own legal list independently. Verify: if both functions are called for a Saudi Master bot, the legal list is computed twice. Check for any divergence in R.IsLegalPlay inputs that could cause inconsistency.

### A-47 — pickLead singleton preference (step 2) before longest-suit preference (step 3)

Audit the lead priority: singletons are led before longest suit (lines ~841-847 before ~860). Verify this matches Saudi convention. A singleton K-of-offsuit in a Hokm contract is valuable as a ruff setup, but leading it immediately signals a ruff to opponents. Is singleton-before-longest-suit always correct, or should high singletons be held?
