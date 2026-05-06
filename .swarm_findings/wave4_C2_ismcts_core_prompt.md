### A-58 — OnEscalation legacy fallback: kind not in {double,triple,four,gahwa} → m.bels++

Audit OnEscalation (lines ~162-172). The else branch (`m.bels = m.bels + 1`) handles unknown rung kinds by incrementing bel count. Verify all callers in Net.lua pass exactly one of the four canonical strings. If any caller passes "bel" (not "double"), "x2", or any other variant, the else branch fires and corrupts the Bel counter.

### A-59 — BASE_NUM_WORLDS = 30 convergence at 8-candidate decision points

Audit whether 30 worlds is sufficient for ISMCTS convergence when there are 7–8 legal cards (e.g., first lead of the hand with full 8-card hand). With 30 worlds × 8 candidates, each candidate gets ~3.75 evaluations per world — insufficient statistical confidence. The dynamic scaling (60 at trick 4, 100 at trick 6) only helps late game.

### A-60 — Dynamic world scaling thresholds (numTricks >= 6 → 100, >= 4 → 60)

Inspect the numTricks scaling in BM.PickPlay (lines ~514-517). Scaling UP to 100 at trick 6 means the last 2–3 tricks get 3.3× more worlds. Audit whether scaling should be inverted (more worlds early when uncertainty is highest, fewer when hands are almost empty) or whether late-game precision is genuinely more valuable.

### A-61 — buildUnseen: in-progress trick plays are excluded from unseen

Audit buildUnseen (lines ~65-92). Cards in `S.s.trick.plays` are marked seen. Verify: when it's our turn at position 2 in the trick, the position-1 card is in the trick and excluded from unseen. But position-1's card was already in their hand — the function would have counted the right unseen set. Verify no double-exclusion of the current-trick cards.

### A-63 — meldPins: meld cards from declared melds pinned to declaring seat

Inspect the meldPins build (lines ~160-177). Cards from declared melds that are still unplayed are pinned to their declarer. Audit: a Tierce (3-card sequence) pins those 3 cards. Verify: if the declarer has already played some of those cards, only unplayed ones should be pinned. Check the inner loop's `unseen` membership test is correct.
