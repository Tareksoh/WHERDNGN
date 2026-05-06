### A-03 — Sun threshold TH_SUN_BASE = 50 vs. actual Sun win probability

Audit whether sunStrength = 50 corresponds to a statistically winning Sun contract (>50% trick-point capture across random opponent distributions). Cross-check against K.HAND_TOTAL_SUN = 130 and the ×2 multiplier — a borderline Sun that makes by 1 trick-point is punishingly costly if wrong.

### A-06 — sideSuitAceBonus cap at 3 aces × 8 = 24 points

Audit whether a +24 ace bonus (3 aces, max) correctly reflects Saudi Baloot tournament practice where outside aces are frequently trumped out. Check: is the cap of 3 right, or should the 4th ace (in a potential trump suit) also contribute a partial bonus?

### A-08 — Ashkal threshold BOT_ASHKAL_TH = 65 vs. Sun threshold 50

Audit the gap between K.BOT_ASHKAL_TH (65) and TH_SUN_BASE (50). Ashkal transfers Sun to partner; if partner's Sun is marginal (50–64), Ashkal is dangerous. Inspect whether the bot can Ashkal when it would have bid Sun itself (sun >= 65 implies sun >= 50 too) and whether that constitutes a double-commit on a medium hand.

### A-09 — Ashkal J-of-flipped-suit gate (lines ~613-621)

Inspect the `hasJflip or sCnt > 2` veto on Ashkal. Verify: holding J of the flipped suit is correctly identified as "don't Ashkal" (partner's bid may be marginal without our J). Check whether sCnt > 2 is the right count threshold — having 3 cards of the flipped suit with no J does NOT necessarily mean partner's bid is bluff.

### A-10 — partnerBidBonus values: +20 matching trump, +10 other Hokm, +15 Sun

Audit whether the bonus magnitudes (lines ~401-427) correctly encode signal strength. A partner Hokm in the same suit adds +20 — but this creates a double-count scenario: the bot already scored its own trump strength; adding +20 for confirmation overcounts synergy by applying it to the threshold adjustment rather than the hand score.
