### A-93 — scoreUrgency: S.s.target default = 152 in Hokm context

Inspect scoreUrgency (line ~448: `local target = (S.s.target or 152)`). K.HAND_TOTAL_HOKM = 162, but the game target (win condition) is likely a cumulative point total across rounds. Verify S.s.target is populated by State.lua and represents the correct match-win threshold (not the per-round trick-point total).

### A-94 — R.Partner, R.TeamOf correctness: seats 1+3 = team A, 2+4 = team B

Verify the partner and team assignments (Rules.lua lines ~16-28). Seats 1 and 3 are team A, seats 2 and 4 are team B. Audit whether all five bot tiers use R.Partner and R.TeamOf consistently, with no hardcoded seat+2 patterns that would fail at seat 3 (3+2=5, not 1).

### A-95 — PickMelds: first-trick gate (#tricks >= 1 returns empty)

Audit PickMelds (lines ~1130-1140). Returns {} if any trick has been completed. Verify: a bot that is the FIRST to play in trick 1 has #tricks == 0 and CAN declare melds. A bot that plays LAST in trick 1 also has #tricks == 0 (trick not yet completed). But after trick 1 closes, #tricks becomes 1 and the gate blocks. Confirm all bot seats get a meld window.

### A-96 — PickTakweesh: rate decay by trick number (TAKWEESH_RATE_BY_TRICK)

Audit Bot.PickTakweesh (lines ~1324-1352). The rate drops from 60% at trick 0 to 5% at trick 7. Verify: `local completed = #(S.s.tricks or {})` gives the number of COMPLETED tricks before the current play. At completed=0 (trick 1 in progress), rate=0.60. Check: once the bot finds an illegal play and decides NOT to call Takweesh (math.random fails), does it ever recheck that same illegal play in a later trick? Or does it forget?

### A-97 — sunStrength invoked for Hokm-contract PickDouble/Triple/Four/Gahwa

Audit escalationStrength in Hokm context. For a pure Hokm hand (J+9+A of trump, mostly low side cards), sunStrength might score 20–30. Adding 0.5 * trumpStrength might bring it to 45–65. BOT_BEL_TH = 70. Verify whether Hokm defenders with strong trump but weak side suits can ever reach the Bel threshold under the current formula, or whether they are systematically blocked from Beling strong Hokm contracts.
