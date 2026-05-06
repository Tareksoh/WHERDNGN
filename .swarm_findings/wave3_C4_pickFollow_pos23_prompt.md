### A-38 — Position-3 highest winner logic vs. overcut risk

Audit position-3 "third hand high" (line ~1045). The bot plays highestByRank(winners). In Hokm with multiple trump options, the bot might play 9-of-trump as the highest winner when A-of-trump would be wasteful (opponent at position 4 might hold only the 7-of-trump). Check whether there's a "play just enough to win" optimization missing here.

### A-39 — Position-4 cheapest winner (last seat, lowest of winners)

Inspect position-4 behavior in pickFollow. The bot plays lowestByRank(winners) at position 4. Audit: in Hokm with both non-trump and trump winners, lowestByRank picks the cheapest winner — this may choose a 7-of-trump (0 points, trick-rank 1) when A-of-side-suit (11 points, trick-rank 8) would also win. Check the TrickRank comparison across contract boundaries.

### A-40 — partnerWinning path: lowestByRank vs. smother logic gate

Inspect the smother gate in pickFollow (lines ~937-956). The `#highInSuit >= 2 or completed >= 3 or lastSeat` condition gates high-card dumping. Audit the `completed >= 3` branch: this means from trick 4 onwards the bot starts dumping high cards on partner's tricks. In early game (tricks 3–4) with only one A and one T in the lead suit, smothering the T (10 pts) on trick 4 is reasonable but smothering the A (11 pts) at trick 3 is aggressive.

### A-41 — Discard from short non-trump when can't win and not last seat (lines ~1057-1068)

Audit the `not lastSeat AND Hokm AND trump present` loser discard (lines ~1057-1067). The bot discards lowest non-trump. Verify: if the bot holds only trumps (no non-trump to discard), it falls through to `lowestByRank(legal)` which would throw the lowest trump. Is under-ruffing (playing below the current trump winner) the correct play here, or should the bot be preserving trump entirely?

### A-42 — pickFollow winner selection: wouldWin via full trick simulation

Inspect the `wouldWin` helper (lines ~712-718). It constructs a scratch trick with the candidate card appended, then calls R.CurrentTrickWinner. Verify this is called with the correct `trick` state — specifically, check whether `trick.leadSuit` is correctly populated when position-1 plays an off-suit trump (would the scratch trick have leadSuit = trump or leadSuit = original lead?).
