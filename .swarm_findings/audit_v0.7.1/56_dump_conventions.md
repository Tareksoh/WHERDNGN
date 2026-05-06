# 56 — Dump-convention consistency audit (Sections 4 / 8 / 9)

**HEAD:** v0.7.2 (Bot.lua) — `pickFollow` at 2164-2698.
**Scope:** verify Takbeer / Tasgheer / Tahreeb / Tanfeer chain.

## Q1. Priority chain in `pickFollow` (partner-winning branch)

Documented order: Smother(Takbeer A>T) > 1B second-lowest > Bargiya > Tahreeb sender > default.

**Actual order in code (`if partnerWinning then` at 2282):**

1. AKA suppress (2213-2225) — earlier, outside partnerWinning.
2. Sun pos-4 Faranka (2251-2280) — earlier, outside partnerWinning.
3. **Smother / Takbeer** (2299-2330) — feedSafe + descending point-card sort.
4. **Tahreeb sender** (2358-2426) — voidInLed-only (Bargiya T-1 + dump-larger T-4).
5. **Section 4 rule 1B second-lowest** (2444-2459) — Sun + ≥2 in-suit.
6. **Default `lowestByRank(legal)`** (2462).

**ISSUE:** Tahreeb sender (T-1 Bargiya) is BEFORE rule 1B in code, but spec orders 1B before Bargiya. Practical conflict is small because Tahreeb fires only on `voidInLed`, while 1B fires only with ≥2 in-suit follows — mutually exclusive. So the swap is harmless given disjoint gates, but the comment in 2428-2443 wrongly implies smother-then-1B with no Tahreeb in between.

## Q2. Smother check — partner-winning AND point cards?

**Bot.lua 2295-2299, 2312-2319.** Gates `partnerWinning` (line 2282), `feedSafe` (excludes Hokm trump-led), then collects A/T/K/Q/J of `trick.leadSuit` only. v0.5.18 expanded set from {A,T} to {A,T,K,Q,J}. Sort descending → `[1]` = highest. CORRECT.

**Gate 2324:** `#pointCards >= 2 OR completed >= 3 OR lastSeat`. Audit-14 noted single-A masking: at trick 1 with {A,9,8}, `#pointCards=1`, gate fails, falls to 1B → A retained. CONFIRMED still present at v0.7.2.

## Q3. Rule 1B `wouldWin` check — MISSING

**CONFIRMED MISSING** (Bot.lua 2444-2459). The branch sorts ALL in-suit follows ascending and returns `sorted[2]` regardless of whether any card could beat partner. Spec says "can't beat" but partnerWinning never tries to beat partner, so the omission is functionally inert (we never overrun partner anyway). Comment at 2428-2443 says "we can't beat their lead" — misleading because no check exists. Cosmetic.

## Q4. Tahreeb sender vs Smother — encoding conflict?

**Disjoint by gate.** Smother requires `trick.leadSuit` IN-SUIT cards; Tahreeb sender requires `voidInLed`. Cannot both fire same call.

Within Tahreeb: T-4 dump-larger encodes "don't want THIS suit" via larger-first; smother (when in-suit available) donates HIGHEST. Both use HIGH cards but in opposite semantics — only legible because gate disjoint. The v0.5.11 K/T/A doubleton-cap (2419) prevents T-4 from burning K/T/A — preserves the ambiguity-safe path.

T-1 Bargiya (2378-2390) discards Ace-of-side-suit Sun-only when ≥2 cards present. NO conflict with smother (different suit). Bargiya's "low-then-high" follow-up is a future-trick read, not a same-trick conflict.

## Q5. Tanfeer (Section 9) integration

**Bot.lua 2632-2695,** opp-winning fall-through after winners-branch fails. Gates: M3lm + bot-partner + `voidInLed`. Iterates S/H/D/C, skipping trump in Hokm; for each suit with high (A/T) + ≥1 low, returns lowest non-A non-T → suit signal without burning high. Falls through to `lowestByRank` if no wanted suit matches.

**CLEAN integration.** Sits between Belote-preservation (2600) and final `lowestByRank` (2697); no overlap with Tahreeb (different branch — `partnerWinning` false).

**N-2 default:** comment at 2641-2651 acknowledges ambiguous-winner cases naturally fall to `lowestByRank` (Tahreeb-default semantics) — correct per spec.

## Summary issues

1. Comment in 1B branch (2428-2443) says "smother failed" but Tahreeb sender runs between them; description misleading.
2. Smother `≥2` gate masks single A/T retention at early tricks when 1B also fires (audit-14 finding stands).
3. 1B has no `wouldWin` check — inert because partnerWinning never overruns; cosmetic.
