### A-98 — fzlokyPrefSuit and fzlokyAvoidSuit both nil path in pickLead

Audit the Fzloky nil-signal path in pickLead. When both fzlokyPrefSuit and fzlokyAvoidSuit are nil (partner hasn't discarded yet, or signal rank was Q/J), the code falls through to the normal lead logic. Verify there is no accidental early return or state mutation from the Fzloky block that affects later logic.

### A-100 — Bot.Reset / Bot.Init: is there a top-level initialization function?

Audit whether there exists a Bot.Reset or Bot.Init function that correctly invokes both ResetMemory and ResetStyle at game start. Verify the call chain: new game → ResetStyle; new round → ResetMemory. If Bot.Reset calls both, confirm Net.lua calls it at the right game lifecycle event and not just round events (which would wipe cross-round style learning).

### B-01 — Human Hokm bid honesty: do humans bid Hokm with J+9 strictly, or bluff on long suits?

Catalog whether Saudi Baloot human players reliably hold J+9 of trump when bidding Hokm, or commonly bid on A+9+T (no J) or pure-length (5+ cards, no honors). Determine what minimum hand the bot should ASSUME a human Hokm bidder holds vs. the range that includes bluffs.

### B-02 — Human Sun bid honesty: over-optimistic Sun bidders

Audit whether humans frequently overcall Sun on marginal hands (sun score 45–55) in hope of the ×2 multiplier, particularly when the score is close. If so, the bot's defender decision should Bel against more Sun contracts than against equivalent Hokm contracts, knowing the Sun bidder is more likely on a marginal hand.

### B-03 — Human Ashkal usage: is it always honest (partner's J), or positional bluff?

Inspect how human players use Ashkal. In Saudi Baloot culture, Ashkal typically signals "my partner bid Hokm but I hold Sun-strong — flip the suit." Audit whether the bot correctly treats an Ashkal caller as confirming partner's J in the original suit AND the Ashkal caller holding strong side cards.
