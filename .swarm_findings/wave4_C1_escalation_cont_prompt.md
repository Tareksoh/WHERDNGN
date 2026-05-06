### A-48 — fzlokyAvoidSuit + longest-suit tie-break: "≥2 more cards" override

Inspect the avoid-suit fallback (lines ~867-880). The avoid suit wins only if it exceeds the best non-avoid suit by ≥2 cards. Audit: with avoid-suit=4 cards and best-non-avoid=2 cards, the difference is 2 — does `avoidN >= longestN + 2` use >= (fire) or > (not fire)? Check the boundary condition is intentional.

### A-52 — partnerEscalatedBonus for defender Bel: +5 for doubled, +8 for foured

Inspect partnerEscalatedBonus (lines ~496-533). A partner who has Beled adds +5 to our escalation strength; a partner who Foured adds +8. Audit: if the partner already declared Four, there is no further rung for the defender (Four is the last defender rung). A bot receiving +8 from partner's Four will see an inflated strength but has no Bel or Four to call — does this false-positive create a dead-code path?

### A-53 — Bel wantOpen decision: strength >= jth + 20

Audit the wantOpen logic in PickDouble (line ~1178: `wantOpen = strength >= jth + 20`). Since jth is already jittered, "strength >= jth + 20" is a moving target. Verify: on successive calls with the same hand, the jitter can flip wantOpen between true and false (the ±10 BEL_JITTER crosses the +20 buffer). Is this intentional (natural feel) or a consistency bug?

### A-54 — Gahwa terminal: wantOpen = false hardcoded (line ~1254)

Inspect PickGahwa (line ~1253-1254). It returns `(yes, false)` always. Audit: Gahwa is defined as terminal (match-win), so wantOpen = false is logically correct (no further rung). Verify that the caller in Net.lua consumes the second return value and does NOT accidentally read it as a meaningful signal.

### A-57 — matchPointUrgency cap: was ±8/±3, reduced to ±5/±2 in 13th-bot-audit

Inspect matchPointUrgency (lines ~468-487). The comment says magnitudes were "halved on the opp-near branches" but the code shows opp >= target-15: mod+5, and opp >= target-40: mod+2. The comment mentions was +8/+3. Verify the cap of `if mod > 10 then mod = 10 end` is still consistent with the halved magnitudes — if the actual branches only reach +5+3=8, the cap of 10 is never hit.
