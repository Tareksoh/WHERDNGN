# Video #25 (متى تشتري صن) — re-verification at HEAD v0.9.0

Source transcript: `docs/strategy/_transcripts/25_when_bid_sun_extracted.md`. Code: `Bot.lua` PickBid at 1071, helpers 712/756/778, PickDouble at 3094.

## 1. A+T mardoofa minimum (R1, R10) — WIRED-CORRECT

`sunMinShape` (Bot.lua:712-728) is the literal encoding: returns true if `aceCount >= 2` OR (`aceCount == 1` AND there exists a suit with both `hasA[su]` and `hasT[su]`). Gated at 1287 (R1 direct Sun), 1333 (G-4 partner-Hokm Sun overcall), 1362 (R2 Sun-vs-Hokm). Bare 1-Ace junk hand (R9) is correctly blocked: aceCount=1 with no T cover returns false. R6/R7/R8 meld-override path NOT wired — `sunMinShape` does not consult any meld-from-deal predicate. Minor doc-vs-code gap (extraction notes "meld-detect path" wishfully).

## 2. S-3 +15 for 3+ Aces — WIRED, intent matches

`K.BOT_SUN_3ACE_BONUS = 15` (Constants.lua:311) applied at Bot.lua:1112: `if aceCount >= 3 then sun = sun + K.BOT_SUN_3ACE_BONUS end`. Speaker's "ما يبقى لها كلام" (R12) translates to "almost always Sun." +15 puts the floor near sun≈44 vs `TH_SUN_BASE` ≈ 50, clearing thSun reliably (~70% per Wave-2 calibration note in Constants.lua:311-313). 4-Ace hand (R14) short-circuits even earlier: aceCount>=4 returns BID_SUN unconditionally at 1085, before any threshold logic — matches R14's "مستحيل تخسر."

## 3. B-7 Bel-fear bias — WIRED but ASYMMETRIC

Bot.lua:1165-1170 adds `+8` to thSun when `myTotal >= K.SUN_BEL_CUMULATIVE_GATE (=100)`. **Confirmed gap**: only consults OUR cumulative, ignores opp cumulative. Speaker's R19 ("you 120, opp 90 — AVOID Sun unless very strong") is the textbook trigger: opp at 90 is the actor that can Bel us (per E-1: only team <100 may Bel). Code fires correctly here (myTotal=120≥100). But R18 ("you 100+, opp <30") should NOT trigger fear — Bel-then-52 still leaves opp far below 152. Code fires anyway (myTotal=100≥100). The bias is over-eager when opp is below ~50, under-eager nuance when myTotal=99 with opp=99 (neither team can Bel us by E-1, no fear needed; correctly silent here). Consider gating: `myTotal >= 100 AND opp >= ~70` to align with R18 vs R19 distinction.

## 4. Sun-Mughataa A+T pair distinct bonus — WIRED

`K.BOT_SUN_MARDOOFA_BONUS = 5` per pair, capped at 2 pairs (`K.BOT_SUN_MARDOOFA_PAIR_CAP`), Constants.lua:314-315. Applied at Bot.lua:1113-1114. `aceCountAndMardoofa` (756-770) counts only suits where `hasA[su] AND hasT[su]`. Two A's in different suits with no T-cover → mardoofaCount=0, bonus=0. Two A+T pairs (R11 إكة مردوفة + عشرة مردوفة) → +10. So a "covered" Sun-strong A+T does receive a structural premium over 2 separate Aces (which only get raw sunStrength = 22, no pair bonus). R29-R31 (declaring Sun BLIND before seeing cards) correctly has no separate code path — extraction note R29 confirms "no separate code path needed."

## Summary

3/4 verified clean. B-7 has a real but minor calibration gap: it's a 1-sided gate where speaker's framing is 2-sided (myTotal≥100 AND opp catching up). Score-state nuance R17 (140-vs-140 endgame) is handled by `combinedUrgency` at 1125 separately, not by B-7.
