### A-11 — Round-1 Sun before Hokm priority (line ~583)

Inspect the precedence: Sun is evaluated before Hokm in round 1 (line ~583 returns K.BID_SUN if sun >= thSun). Verify this matches Saudi convention — in most Saudi Baloot traditions, Hokm and Sun are independent options and the bot should pick the stronger contract, not default to Sun-first. Check if a hand that qualifies for BOTH should always prefer Sun.

### A-12 — Round-2 Sun vs. best Hokm comparison (line ~649: sun > bestScore)

Audit the `sun >= thSun AND sun > bestScore` dual condition (line ~649). This means a hand with Sun=52 and best Hokm=51 bids Sun, while Sun=52 and bestHokm=53 bids Hokm. Verify whether this tie-breaking logic correctly models the Saudi multiplier incentive (Sun = ×2 base vs. Hokm = ×1 base before escalation).

### A-13 — Kawesh detection: bots unconditionally call on 5+ low cards

Inspect Bot.PickKawesh (line ~1302). The current logic is "if eligible, call unconditionally." Audit: is there any strategic reason to NOT call Kawesh? (e.g., score position where the team is near the target and opponent redeals could give them a better contract). The unconditional redeal may hurt near-win scenarios.

### A-20 — Trump counting in pickLead: trumpCount < 4 triggers ace-cash first

Inspect the `trumpCount < 4` branch (line ~793) that cashes a non-trump Ace before pulling trump. Audit: should the threshold be 3 instead of 4? With exactly 4 trump including J+9, a bidder should pull trump immediately. With 3 or fewer, ace-cash-first is correct.

### A-21 — opponentsVoidInAll check in pickLead (lines ~823-837)

Audit the free-trick detection: this fires when BOTH opponents are void in a non-trump suit. Inspect whether the void inference in OnPlayObserved is reliable enough to trigger this correctly, or whether early-round void inference errors cause phantom free-trick leads.
