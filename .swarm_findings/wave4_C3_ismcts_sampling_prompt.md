### A-64 — pinCard: bid card pinned to the bidder

Inspect bid-card pinning (lines ~138-147). If `S.s.bidCard` exists and is not yet played, it's pinned to the bidder's hand. Verify: in round 2, the bidder picks up the bid card — it should be in their S.s.hostHands[bidder] already. The pin would be redundant (the card is already known to be in the bidder's hand). Check whether the pin creates a duplicate assignment in Phase 2 fill.

### A-65 — sampleConsistentDeal fallback: uniform random ignoring voids

Audit the fallback deal (lines ~252-273). If 15 attempts fail to find a void-consistent deal, it falls back to random. This occurs when voids are very constraining (e.g., seat 2 is void in S+H+D but only 3 cards remain to distribute). Verify the fallback doesn't poison the rollout with impossible hand distributions — a single corrupted world in 30 can swing the score by ~10%.

### A-67 — Partner signal suit biasing: desire[pSignalSuit] = 1 (line ~213)

Audit the partner signal biasing (line ~213). Weight = 1 triggers the `desire[c] or (desire[C.Suit(c)] and 20)` logic (line ~219), but `desire[pSignalSuit] = 1` sets the SUIT key, not a card key — the `desire[c]` lookup returns nil and the `desire[C.Suit(c)] and 20` path fires (returning 20). Verify the weight calculation is intentional: 70% chance to take ANY card of the signaled suit.

### A-68 — rolloutValue: initialHands includes already-played cards

Inspect rolloutValue (lines ~289-489). initialHands includes sampled remaining cards PLUS all previously played cards (lines ~294-308). This is for meld detection only. Verify: R.DetectMelds uses the initial full hand to detect melds. Is it correct to use the full starting hand for meld detection mid-rollout, given melds are declared in trick 1 only?

### A-69 — rolloutValue: heuristicPick lead branch defaults to "highest non-trump, else lowest"

Inspect heuristicPick lead (lines ~426-436). The bidder-team lead plays the highest trump. Non-bidder plays lowest non-trump. This is a very rough approximation of Bot.lua's multi-step pickLead. Audit: the rollout heuristic misses AKA signals, void detection, singleton leads, and Fzloky suit preferences. Quantify the gap: does a crude rollout systematically under-value certain card choices?
