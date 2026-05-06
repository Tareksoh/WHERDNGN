### A-79 — styleTrumpTempo and styleBelTendency: computed but never consumed

Audit `styleTrumpTempo` and `styleBelTendency` (lines ~181-196). Both are `local function` and neither appears to be called by any upstream logic. Verify they are indeed dead code, confirm via grep on the file. Check whether they were intended as inputs to M3lm play decisions but were never wired up — this is the "partnerStyle ledger READ but not USED" scenario.

### A-80 — partnerBidBonus: reads S.s.bids[partner] which may be nil in R2

Inspect partnerBidBonus (lines ~411-427). It reads `S.s.bids[partner]`. In round 2, a partner who bid in round 1 may have their bid stored differently. Verify: does S.s.bids[partner] contain the FINAL bid (the one that won) or the last bid made? In round 1, multiple bids can happen — the contract is finalized by Net.lua after all four bids are in. Check whether the bids table reflects the contract trump suit correctly.

### A-81 — Bot._memory nil guard in all accessors

Audit every usage of `Bot._memory[seat]` that is not preceded by a `Bot._memory or Bot.ResetMemory()` guard. OnPlayObserved has the guard (line ~201). pickLead uses `opponentsVoidInAll` which reads `Bot._memory` with a nil-return guard (line ~274). Identify any access paths where `Bot._memory` is nil and an unguarded read would crash.

### A-84 — OnPlayObserved call scope: host-only, all 4 seats

Audit whether OnPlayObserved is called for ALL four seats' plays (including human players and opponents) or only for bot seats. The comment says "Driven from Net.lua's MaybeRunBot" but MaybeRunBot only runs for bot turns. Verify: does Net.lua call OnPlayObserved for human plays too? If not, the memory is incomplete.

### A-85 — Void inference for trump-ruff: rollback added in latest audit

Inspect the trump-ruff rollback in OnPlayObserved (lines ~262-269). The Fzloky firstDiscard reverts if the off-suit play was a trump ruff in Hokm. But the void inference (`mem.void[leadSuit] = true`) is NOT rolled back — a seat that ruffs with trump IS void in the lead suit. Verify this is correct: void inference stands, firstDiscard is reverted.
