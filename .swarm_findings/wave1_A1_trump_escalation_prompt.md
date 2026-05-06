### A-16 — suitStrengthAsTrump point values vs. POINTS_TRUMP_HOKM table

Audit whether the scoring inside suitStrengthAsTrump (lines ~306-319) matches K.POINTS_TRUMP_HOKM exactly. J=20, 9=14, A=11, T=10 match. K=4, Q=3 match. But 8 and 7 are assigned strength=2 inside the function even though K.POINTS_TRUMP_HOKM shows them as 0. Clarify whether strength and point-value should diverge here (length proxy) or converge (bid on real point contribution).

### A-25 — IsTrump correctness in Sun contracts

Inspect C.IsTrump usage throughout pickLead and pickFollow. In Sun contracts there is no trump; verify that every `C.IsTrump(c, contract)` call correctly returns false for all cards in Sun, and that the trump-specific branches never fire in Sun contract context.

### A-49 — escalationStrength: sunStrength + trumpStrength for Hokm bidder

Audit escalationStrength (lines ~1191-1200) for the Hokm bidder. They get sunStrength (all-suits side cards) + full trumpStrength. This double-counts the J of trump — J appears in trumpStrength at +20 and in sunStrength at +2 (as J = 2 pts in plain suit scoring). The J bonus inflates Hokm-bidder escalation decisions by ~18.
