# Wave 3 — C3 Findings: Sun Strength Specifics + pickFollow Opening

Reviewer: code-review specialist (Wave 3, C3)
Codebase: C:/CLAUDE/WHEREDNGN — v0.4.4
Date: 2026-05-03

---

## A-28 — AKQ stopper bonus +8 per suit

**VERDICT: WARNING**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:387`

**Evidence:**

`sunStrength` scores each card individually first:
- A = 11, K = 4, Q = 3 → combined individual total = 18

Then at line 387:
```lua
if hasA[su] and hasK[su] and hasQ[su] then s = s + 8 end
```

The audit question is whether this is a double-count. It is NOT a double-count of card values — the individual card scores are not "trick values," they are HCP proxies. The +8 is a synergy bonus on top: AKQ together guarantee 3 tricks regardless of distribution, which is a structural property that a bare HCP sum does not capture.

However, the sizing is debatable. Three guaranteed tricks in Sun at 3+3+3 trick-point ceiling = 9 points maximum additional yield above what the cards already contribute in expected value. But the individual scores already embed partial trick expectations (A=11, K≈3.5, Q≈2 expected), so the synergy bonus of +8 is plausible but slightly generous. No strict double-count exists, but the magnitude is untested against threshold calibration.

**Recommendation:** The logic is defensible. Add a code comment explaining the +8 represents a 3-trick structural guarantee (not a card-value addition) to aid future reviewers. Consider verifying empirically that AKQ-held Sun bids don't over-trigger escalation given the inflated sunStrength feeding into escalation thresholds at lines 1192 and 1264.

---

## A-29 — sunStrength used in ALL escalation decisions (Bel, Triple, Four, Gahwa)

**VERDICT: WARNING**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:1191-1201`

**Evidence:**

`escalationStrength` (line 1191) unconditionally calls `sunStrength(hand)` as the base. For Hokm contracts, a trump adjustment is added at line 1193–1194:

```lua
if contract.type == K.BID_HOKM and contract.trump then
    strength = strength + suitStrengthAsTrump(hand, contract.trump)
end
```

`suitStrengthAsTrump` correctly scores J of trump at +20 (line 306). However, `sunStrength` also scores J at +2 (line 375, as a standard Jack). The J of trump is therefore counted TWICE: once at +2 in `sunStrength`, and once at +20 inside `suitStrengthAsTrump`. Net contribution = 22. A pure trump-based hand evaluation would give J = 20 only.

Scenario: Hokm hand with J+9+A of trump (no other honors, weak side suits).

- sunStrength base: J=2, 9=0 (not scored), A=11 → s=13; advanced penalty fires (lopsided hand) → s = 13 - 18 = -5 (floored at whatever math.min(penalty,18) allows)
- suitStrengthAsTrump for trump: J=20, 9=14, A=11 + J9 synergy bonus (+18 advanced) = 63 + count bonus
- escalationStrength total ≈ -5 + 63 = 58

The J double-count (+2 in sun, +20 in trump) inflates the figure by +2 beyond true value. The more significant issue is the advanced lopsided-hand penalty in `sunStrength` (-10 per suit with <2 cards or no honor, capped at -18). A Hokm hand that is trump-rich but side-suit-lean legitimately gets penalized in `sunStrength`, potentially netting negative before the trump bonus is added. The penalty is partially correct for Sun but over-penalizes pure trump hands in Hokm escalation decisions.

The audit prompt hypothesizes "systematic undervaluation" of a J+9+A Hokm hand. The J double-count in the other direction (+2 over-value) partially counteracts, but the advanced lopsided penalty can drive the net down significantly.

**Recommendation (WARNING):** The double-count of J (+2 in sunStrength + +20 in suitStrengthAsTrump) is a minor inflation, not undervaluation. The more actionable issue is that `sunStrength`'s lopsided-hand penalty (`math.min(penalty, 18)`) applies even in Hokm escalation contexts, where a side-suit void is expected and desirable. Consider skipping the lopsided penalty in `escalationStrength` when `contract.type == K.BID_HOKM` (it is a Sun-specific heuristic). This is a real calibration gap.

---

## A-35 — Sun first-trick smother: feedSafe gate

**VERDICT: INFO**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:937-941`

**Evidence:**

```lua
local feedSafe = trick.leadSuit and (
    contract.type ~= K.BID_HOKM
    or trick.leadSuit ~= contract.trump
)
```

For Sun (`contract.type == K.BID_SUN`), the condition simplifies to `trick.leadSuit ~= nil`, which is always true mid-trick. The comment at line 933–936 confirms this is intentional: the Hokm-only trump-led exclusion was specifically extended to Sun in a prior fix, so smother fires freely on any suit when partner is winning in Sun.

The audit question is whether there are Sun tricks where feeding A/T is wrong. In Sun, there is no trump, and A/T are always the top point cards. Feeding them to a partner who is already winning cannot hurt — the trick goes to the team regardless, and the A/T points go into the team pile. The only scenario where this could be suboptimal is if the A/T could be used to win a LATER trick that is currently in danger. However, the smother branch only fires when `partnerWinning == true`, and it applies the "second A/T in suit" gate (line 951: `#highInSuit >= 2`) outside the first 3 tricks, which preserves at least one high card for depth.

The smother correctly fires unconditionally for Sun because in Sun there is no ruffing risk, and giving away a point card for free when the trick is already won is never suboptimal. No bug.

**Recommendation:** No code change needed. The behavior is correct and the comment at line 933–936 documents the rationale. Add a one-line note confirming Sun is intentionally ungated for future reviewers.

---

## A-36 — Position-2 sure-stopper detection: trumpOut <= 1

**VERDICT: WARNING**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:981-993`

**Evidence:**

```lua
if contract.type == K.BID_HOKM and contract.trump then
    local trumpOut = suitCardsOutstanding(hand, contract.trump)
    if trumpOut <= 1 then
        -- Use the highest trump winner as "sure".
        for _, c in ipairs(winners) do
            if C.IsTrump(c, contract)
               and (not sureStopper or ...) then
                sureStopper = c
            end
        end
    end
end
```

The `trumpOut <= 1` guard means trump-based sure-stopper detection fires only when 0 or 1 trump cards are outstanding (very late game, typically tricks 7+). The audit prompt asks: shouldn't the J of trump always be a sure stopper, regardless of trump count?

The J of trump is the highest-ranked card in Hokm. By definition, no card can beat it. Therefore, a position-2 hold of J of trump is always a sure stopper: the J wins unconditionally regardless of `trumpOut`.

The current code misses this case. If `trumpOut = 4` (early-mid game) and the bot holds J of trump as a winner at position 2, the code will NOT classify it as `sureStopper`, and the bot will duck — losing the J's point value (20 pts) and the trick.

The subsequent fix at lines 1003-1012 (A/T lead-suit stopper) partially mitigates for non-trump suits, but it does NOT rescue the J-of-trump case when the led suit is a side suit and the J of trump is a cross-ruff winner in `winners`.

**Recommendation (WARNING):** Before the `trumpOut <= 1` block, add a check: if any card in `winners` is J of trump, classify it as `sureStopper` unconditionally. The J of trump is the absolute highest card in Hokm and is never beatable. The `trumpOut` gate is appropriate for lesser trump cards (9, A-of-trump, etc.) but not for the J.

```lua
-- J of trump is unbeatable regardless of outstanding trump count.
for _, c in ipairs(winners) do
    if C.IsTrump(c, contract) and C.Rank(c) == "J" then
        sureStopper = c; break
    end
end
```

---

## A-37 — Position-2 A or T of lead suit as sure stopper in Hokm

**VERDICT: CRITICAL**

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:1003-1012`

**Evidence:**

```lua
if not sureStopper and trick.leadSuit then
    for _, c in ipairs(winners) do
        local r = C.Rank(c)
        if C.Suit(c) == trick.leadSuit
           and (r == "A" or r == "T") then
            sureStopper = c
            break
        end
    end
end
```

This block runs unconditionally for ALL contract types (no `BID_SUN` or `BID_HOKM` guard). The comment at line 995–1001 explicitly targets Sun ("in Sun, an Ace of the led suit is unbeatable"), but the code applies equally to Hokm.

In Hokm, an Ace of a non-trump suit is NOT a sure stopper if any opponent has no cards of that suit and therefore can ruff it. The Ace is only safe if the lead suit is exhausted across opponents — which the bot cannot know for certain at position 2.

The T (10) of the lead suit is even less safe: in Hokm, T is the second-highest point card but ranks below J of trump and any trump card. At position 2, committing a T of a side suit when an opponent might ruff it sacrifices 10 points.

Concretely: In a Hokm hand, if opponents lead Spades, the bot holds A of Spades and an opponent (seat 3 or 4) is void in Spades, the A will be trumped. The current code will classify the A as `sureStopper = c` and play it immediately — losing 11 points to an opponent's trump.

This is a contract-type discrimination failure. The A/T-as-sure-stopper logic is correct for Sun (no trump), incorrect for Hokm side suits.

**Recommendation (CRITICAL):** Gate the A/T lead-suit sure-stopper block to Sun contracts only:

```lua
if not sureStopper and trick.leadSuit
   and contract.type == K.BID_SUN then
    for _, c in ipairs(winners) do
        local r = C.Rank(c)
        if C.Suit(c) == trick.leadSuit
           and (r == "A" or r == "T") then
            sureStopper = c
            break
        end
    end
end
```

For Hokm, A of the lead suit at position 2 should only be played if the suit is demonstrably safe (e.g., trumpOut == 0 or the suit has been established). Without that information, the correct position-2 play in Hokm is to duck a non-trump A and let partner potentially cover — the current fix inverts this principle for Hokm.

---

## Summary Table

| ID   | Severity | Line(s)     | Issue                                                          |
|------|----------|-------------|----------------------------------------------------------------|
| A-28 | warning  | 387         | +8 AKQ synergy bonus is not a strict double-count but needs comment + threshold calibration check |
| A-29 | warning  | 1191-1194   | sunStrength lopsided-hand penalty mis-fires in Hokm escalation; J minor double-count is also present |
| A-35 | info     | 937-941     | Sun smother gate is intentionally unconditional — correct behavior, no bug |
| A-36 | warning  | 981-993     | J of trump not recognized as unconditional sure stopper at pos-2; `trumpOut <= 1` is too conservative |
| A-37 | critical | 1003-1012   | A/T lead-suit sure-stopper applies to Hokm where non-trump Aces CAN be trumped — must be gated to Sun only |
