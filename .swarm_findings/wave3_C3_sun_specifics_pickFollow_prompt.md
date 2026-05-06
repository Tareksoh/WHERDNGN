### A-28 — AKQ stopper bonus +8 per suit

Audit the `+8` AKQ stopper bonus (line ~387). In Sun the A+K+Q of a suit guarantee 3 tricks from that suit. Verify whether +8 is proportionate to the 3-trick guarantee (roughly 11+4+3=18 points from those cards alone, already scored individually) — is this a double-count of the card values or a legitimate synergy bonus?

### A-29 — sunStrength used in ALL escalation decisions (Bel, Triple, Four, Gahwa)

Inspect escalationStrength (line ~1191): it calls sunStrength for BOTH Sun and Hokm contracts. In Hokm, sunStrength is a proxy for side-suit strength — but the J of trump (worth 20 in trump suit) is only worth 2 in sunStrength. Audit whether a Hokm-bidder with J+9+A of trump has their escalation strength systematically undervalued.

### A-35 — Sun first-trick smother: feedSafe gate excludes trump-led tricks only in Hokm

Inspect the feedSafe condition (lines ~937-942): `contract.type ~= K.BID_HOKM OR trick.leadSuit ~= contract.trump`. In Sun contracts this always evaluates to true (no trump condition), so smother fires freely. Audit whether Sun smother is always correct or whether some Sun tricks should not have A/T fed to partner's pile.

### A-36 — Position-2 sure-stopper detection in Hokm (lines ~981-997)

Audit the `trumpOut <= 1` condition for sure-stopper in position 2. This fires only when exactly 0 or 1 trump card remains outstanding — very late game. Check if this is too conservative; a position-2 hold of J of trump (highest possible winner) should always be a sure stopper regardless of trump count.

### A-37 — Position-2 A or T of lead suit as sure stopper (lines ~1003-1012)

Inspect the A/T lead-suit stopper extension (lines ~1003-1012). An Ace of the lead suit IS unbeatable in Sun; in Hokm it can be trumped. Verify: the code applies this equally in both Sun and Hokm contracts. In Hokm, an Ace of a non-trump lead suit is NOT a sure stopper if any opponent might ruff.
