### A-87 — Trump tempo counter fires only on trick.plays count == 1 (leads only)

Audit the trump tempo counter (lines ~246-255). It checks `#trickPlays == 1` AFTER ApplyPlay, meaning the current play IS the first play of the trick (lead). Verify: `S.s.trick.plays` at this point — does it include the just-applied play (making count 1 for a lead) or not? If ApplyPlay hasn't pushed to trick.plays yet, count=0 for a lead, and the condition fails.

### A-88 — wasIllegal check: lastPlay match by seat AND card

Inspect wasIllegal detection (lines ~211-214). It finds the last play in the current trick and checks `lastPlay.seat == seat AND lastPlay.card == card`. Verify: this is called DURING OnPlayObserved (after a play was observed). The "last play" should be the just-played card. But what if two bots play in rapid succession and the host processes them out of order? Race condition check.

### A-91 — PickBid R1/R2 phase gate: Bot doesn't check S.s.phase

Audit PickBid (lines ~540-656). It reads `S.s.bidRound` (1 or 2) but never checks `S.s.phase`. If called during PHASE_PLAY erroneously, it would evaluate bids against live hands and possibly return a non-PASS value. Verify Net.lua's phase gating prevents PickBid from being called outside PHASE_DEAL1 and PHASE_DEAL2BID.

### A-92 — PickPlay dispatching: Saudi Master → Fzloky → M3lm → Advanced → Basic fallback chain

Audit the full PickPlay dispatch chain in Net.lua's MaybeRunBot. Verify: BM.PickPlay → Bot.PickPlay (with all tier flags active simultaneously) follows the intended precedence. Check whether multiple tiers can be active simultaneously (IsM3lm() returns true if IsFzloky() is true, etc.) and whether the dispatch ever double-evaluates.

### A-99 — BotMaster heuristicPick: "bidder team leads high trump" uses placeholder comment

Inspect heuristicPick lead in BotMaster (lines ~426-435, comment: "placeholder: lead high trump"). This is a simplified version of the real pickLead. Audit whether the placeholder is deliberately simple (performance tradeoff) or an incomplete implementation. Specifically: it picks the highest-ranked legal card with IsTrump=true, but doesn't check whether the bidder has already cleared trump and should be cashing side aces.
