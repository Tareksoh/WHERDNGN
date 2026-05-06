### B-89 — Human partner bid suit exploitation: bot leading partner's bid suit back

Identify whether the bot should lead the human partner's bid trump suit back when holding 2–3 cards of it (standard partner-return play). The bot's current pickLead logic does not have an explicit "return partner's bid suit" heuristic. Audit: this is a high-value addition for human-bot coordination.

### B-90 — Human partner trust calibration: should the bot trust a human partner's discard?

Audit whether the bot should apply Fzloky firstDiscard inference differently for a human partner vs. a bot partner. A human's first discard may be entirely random (no convention awareness). Audit: if the bot is IsFzloky and the partner is human, applying the signal could mislead the bot's lead decisions. Propose a "signal confidence" discount for human partners.

### B-92 — Human partner under-bidding: partner passes both rounds on a 38-strength hand

Identify the human tendency to pass marginal hands out of overcautiousness. If the bot's partnerBidBonus applies -10 for a PASS partner, but the human partner actually held a 38-strength hand that passed conservatively, the bot over-penalizes its combined team strength. Audit: should human-partner passes be discounted to -5 instead of -10?

### B-93 — Human opponent Bel timing exploit: Beling late in the window signals hesitation

Audit the Bel phase timing. If a human opponent waits until near the K.TURN_TIMEOUT_SEC = 60 threshold to Bel, that hesitation may signal borderline strength. Identify whether the bot's Triple response (after human Bel) should be more aggressive when the human hesitated, since hesitation implies borderline hand.

### B-94 — Human partner's void inference leak: humans rarely disguise voids

Identify the human tendency to immediately discard visibly when void in a suit (no hesitation, obvious tell). In contrast, an expert player delays to conceal voids. Audit: since the bot already tracks void inference via OnPlayObserved, it gains this information regardless. But the bot should not EXPLOIT void information to mislead its human partner.
