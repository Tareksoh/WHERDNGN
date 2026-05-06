# Wave 3 C1 Findings — Trump Strength Specifics
**Codebase:** WHEREDNGN v0.4.4  
**Scope:** Bot.lua `suitStrengthAsTrump`, `sideSuitAceBonus`, related bidding + play logic  
**Date:** 2026-05-03

---

## A-11 — Round-1 Sun before Hokm priority (line ~583)

**VERDICT: WARNING**

**File:line:** `Bot.lua:583`

**Evidence:**  
Round-1 bidding evaluates Sun first (`if sun >= thSun then return K.BID_SUN end`) and only falls through to Hokm if Sun threshold is not met. This means a hand that qualifies for BOTH Sun and Hokm will always choose Sun in round 1. The thresholds are independently jittered (`thSun = jitter(TH_SUN_BASE - urgency, 6)` vs `thHokmR1 = jitter(r1Base - urgency, 6)`), but there is no head-to-head score comparison — Sun wins automatically if its threshold passes, regardless of whether Hokm would score higher.

In Saudi Baloot convention, Sun (x2 base multiplier before escalation) is indeed the stronger contract, so defaulting to Sun when it qualifies is directionally correct. However, the issue is subtle: a hand with `sun=51` (exactly meeting `thSun=50`) and an overwhelming trump suit scoring 75 as Hokm will still bid Sun. Sun is not always the better play — a lopsided hand with a dominant trump suit may be safer as Hokm (one strong suit to pull trump) than as Sun (which requires coverage across all four suits). The code has no escape valve here. Unlike round 2, which compares `sun > bestScore` at line 649, round 1 has no such comparison: Sun just wins unconditionally once the threshold passes.

**Recommendation:** Add a head-to-head comparison in round 1 analogous to round 2. Compute `bestScore` for the flipped suit, and only bid Sun if `sun > bestScore`. If `bestScore > sun` (dominant trump), prefer Hokm. This aligns round-1 logic with round-2 logic and corrects over-bidding Sun on unbalanced hands.

---

## A-12 — Round-2 Sun vs. best Hokm comparison (line ~649)

**VERDICT: INFO**

**File:line:** `Bot.lua:649`

**Evidence:**  
The dual condition `sun >= thSun and sun > bestScore` (line 649) is sound on its face. A hand bids Sun only when:
1. Its sun score clears the absolute threshold, AND
2. Sun score strictly exceeds the best possible Hokm score.

The edge case flagged in the prompt — `sun=52` vs `bestHokm=53` prefers Hokm — is correct behavior: Hokm is stronger here on raw card power even though its multiplier is lower. The multiplier (x2 for Sun) is an external scoring rule, not a hand-strength metric. The bot evaluates whether the hand is *capable* of executing the contract; the external multiplier incentive is irrelevant to that judgment. If the intent were to bias toward Sun because it pays more, that would require a `sun > bestScore * multiplierDiscount` adjustment — but that would make the bot chase multipliers over win probability, which is generally wrong.

The tie-break (`sun > bestScore` not `>=`) means a tie goes to Hokm, which is correct: Hokm is easier to execute (one trump suit to manage vs. all suits in Sun).

No code change recommended. This is working as intended.

---

## A-13 — Kawesh detection: bots unconditionally call on 5+ low cards

**VERDICT: WARNING**

**File:line:** `Bot.lua:1302-1308`, `Cards.lua:164-171`

**Evidence:**  
`Bot.PickKawesh` returns `true` unconditionally whenever `C.IsKaweshHand(hand)` is satisfied (all cards are 7/8/9 ranks). There is no score-position awareness. Contrast this with other bot escalation decisions (`Bot.PickBel`, `Bot.PickTriple`, `Bot.PickFour`, `Bot.PickGahwa`) which all incorporate `scoreUrgency + matchPointUrgency` adjustments at lines 1171, 1223, 1235, 1252 respectively.

The audit prompt correctly identifies the risk: if the bot's team is near the scoring target (e.g., needs 1 more point to win), a Kawesh redeal hands opponents a fresh deal that could give them a strong bidding hand, resetting the score position. The unconditional call ignores this entirely.

Additionally, `C.IsKaweshHand` (Cards.lua:168) requires that ALL cards in hand be 7/8/9. This is very restrictive — a true Kawesh hand. The bot logic at line 1306 delegates the eligibility check entirely to `C.IsKaweshHand` without any guard on `hand` length (though `#hand == 0` is checked in `IsKaweshHand` itself, so nil-safety is covered). Eligibility looks correct.

The strategic flaw is the unconditional redeal near a win. The comment at line 1299 explains the rationale ("the hand has no honors, no length, no scoring potential — redeal is strictly better"), but this ignores asymmetric score-position value: for a near-winning team, the variance from a redeal (opponent could get a powerhouse contract) can be worse than playing a bad hand and conceding a single round loss.

**Recommendation:** Add a score-position guard. If the bot's team is within 1-2 points of the match target (detectable via `S.s.scores` or similar), suppress Kawesh. A near-win team should not voluntarily redeal. Consider using a simple `if matchPointUrgency(R.TeamOf(seat)) > threshold then return false end` guard before the `IsKaweshHand` check.

---

## A-20 — Trump counting in pickLead: trumpCount < 4 triggers ace-cash first (line ~793)

**VERDICT: WARNING**

**File:line:** `Bot.lua:791-799`

**Evidence:**  
The Advanced-mode branch at line 793 reads:
```
if Bot.IsAdvanced() and trumpCount < 4 then
    for _, c in ipairs(legal) do
        if C.Rank(c) == "A" and not C.IsTrump(c, contract) then
            return c
        end
    end
end
```
The threshold `< 4` means that with exactly 4 trump, the bot skips ace-cashing and proceeds to the normal high-trump lead. The audit prompt asks whether this threshold should be 3 instead of 4.

The key consideration: in Saudi Hokm, J and 9 are the two power trumps. A hand with exactly 4 trump including J+9 is genuinely strong — those two combined are worth 34 raw points (20+14) plus the J+9 synergy bonus (18 in Advanced), meaning the trump suit is very likely to win 3-4 tricks outright. For such a hand, pulling trump immediately is correct because opponents cannot profitably ruff your side suits once trump are cleared.

However, a hand with exactly 4 trump that does NOT include J or 9 (e.g., A-T-K-Q of trump) is weaker. The `suitStrengthAsTrump` Advanced penalty (line 324-329) applies a 0.4 multiplier for "no J, no 9+A pair, count < 5" — such a hand would likely not have won the bid in the first place.

But the boundary case is real: exactly 4 trump with J but no 9 (or 9 but no J). The J+9 synergy path is closed, but the hand is moderate. In this case, ace-cashing first is defensible. The `< 4` threshold is slightly aggressive — it causes a bidder with exactly 4 trump to immediately pull trump even when trump is moderate (J-only or 9-only, no synergy). Changing to `<= 3` (i.e., only ace-cash with 3 or fewer) would restrict the ace-first path to genuinely trump-poor hands.

**Recommendation:** Change threshold to `trumpCount <= 3`. With exactly 4 trump, the bidder should pull trump rather than giving opponents a free trick window. With 3 or fewer trump, ace-cashing makes sense since the bidder cannot realistically clear trump before opponents ruff. This is a minor calibration fix but directionally correct.

---

## A-21 — opponentsVoidInAll check in pickLead (lines ~823-837)

**VERDICT: INFO (minor reliability concern, not a bug)**

**File:line:** `Bot.lua:272-282`, `Bot.lua:200-270`, `Bot.lua:824-837`

**Evidence:**  
`opponentsVoidInAll(seat, suit)` at line 272 returns true only when BOTH opponents (all non-teammate seats) have `mem.void[suit] == true`. The void is set in `OnPlayObserved` at line 218 only when: (a) a legal play was observed, (b) the card played was off-suit from the lead, and (c) the play was not flagged `.illegal` (the illegal-play guard added in the 13th-bot-audit, line 207-214 correctly prevents void poisoning from illegal plays).

The reliability concern is that void inference is purely observational — it only fires after a seat has actually failed to follow suit. In early rounds (tricks 1-4), most seats will not yet have demonstrated a void, so `opponentsVoidInAll` will return false for essentially all suits in the early game. This means the free-trick branch is inactive until both opponents have each separately failed to follow in the same suit, which typically requires at least 2 tricks where that suit was led.

This is actually conservative and correct: the bot will not falsely infer a free trick. The risk is false-negatives (missing real free tricks) not false-positives (phantom free tricks). The audit prompt asks about "phantom free-trick leads" — there is no evidence this can occur. The `wasIllegal` guard closes the one path that could have introduced a phantom void.

The only edge case: if `Bot._memory` is nil (e.g., called before `Bot.ResetMemory()`), the function returns `false` at line 273, which is safe.

No code change recommended. The void inference is reliable within its conservative bounds.

---

## Summary Table

| Angle | Severity | Verdict |
|-------|----------|---------|
| A-11 Round-1 Sun unconditional over Hokm | WARNING | Sun wins without score comparison; unbalanced hands may over-bid Sun |
| A-12 Round-2 sun > bestScore tie-break | INFO | Logic is correct; multiplier is not a hand-strength metric |
| A-13 Kawesh unconditional redeal | WARNING | Near-win score position not considered; opponent redeals can be costly |
| A-20 trumpCount < 4 ace-cash threshold | WARNING | Off-by-one; exactly 4 trump should pull immediately, not ace-cash |
| A-21 opponentsVoidInAll reliability | INFO | Conservative false-negative bias; no phantom void risk |
