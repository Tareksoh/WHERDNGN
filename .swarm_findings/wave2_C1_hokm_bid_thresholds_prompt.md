### A-01 — Hokm R1 threshold sensitivity (TH_HOKM_R1_BASE = 42)

Audit whether 42 is correctly calibrated for the Saudi Baloot point economy (J=20, 9=14, A=11). Enumerate all hand configurations that score exactly 38–46 and determine which ones a human expert would bid vs. pass; check for systematic over- or under-bidding near the cliff.

### A-02 — Hokm R2 threshold gap vs. R1 (r2Base = 38 in Advanced)

Inspect the `math.max(r2Base, r1Base - 4)` clamp (line ~572). Verify whether Advanced R2 threshold (38) sits in the correct relationship to R1 (42): R2 allows suit-choice which should raise the bar, not lower it. Confirm the 4-point gap survives all urgency stacking scenarios.

### A-04 — BID_JITTER = 6 effect on threshold cliff sharpness

Audit the ±6 per-call jitter on all three thresholds. Check whether the jitter range (12-point window) is wide enough to prevent the "two bots always match bids on similar hands" pattern but not so wide that strong hands occasionally pass at 42-6=36. Identify edge cases where jitter flips a clear bid into a pass.

### A-05 — J-step-function 0.4 dampener for no-J hands in Advanced

Inspect the `strength * 0.4` penalty (line ~329) for hands with no J, no 9+A, and fewer than 5 cards. Verify this doesn't over-penalize 4-card suits with A+T+K (which are playable Hokm hands) and doesn't create a cliff where a 4-card A9 hand scores lower than a 3-card J hand.

### A-07 — Advanced R2 threshold stricter-than-R1 invariant under extreme urgency

Audit what happens when scoreUrgency + matchPointUrgency = 17 (max theoretical stack) is applied to both R1 and R2 thresholds. Verify the `math.max` clamp (line ~572) still keeps R2 ≥ R1-4 in desperate scenarios, or whether urgency stacking breaks the invariant.
