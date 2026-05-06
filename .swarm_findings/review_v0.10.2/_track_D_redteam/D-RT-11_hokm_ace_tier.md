# D-RT-11 — Red-team: v0.10.0 X4/L07 Hokm-needs-Ace tier-gated rule

**Target:** `Bot.lua:782-806` `hokmMinShape`, M3lm+ Ace gate added in v0.10.0.
**Verdict:** **2 confirmed bugs (S2-medium), 1 calibration concern, 1 design wrinkle.**
**No code modified — review-only.**

---

## 1. The change in question

`Bot.lua:798-805`:

```lua
if not hasJ then return false end          -- B-4 absolute floor
-- v0.10.0 L07 tier-gated requirement: any Ace in hand.
if Bot.IsM3lm and Bot.IsM3lm() and not hasAnyAce then
    return false
end
if count >= 4 then return true end         -- B-2 self-sufficient
if count == 3 and hasSideAce then return true end  -- B-1 minimum
return false
```

The L07 (Pro-2 PDF) Ace requirement is now enforced for **all** count
branches at M3lm+ tier. Pre-v0.10.0 the `count >= 4` branch passed
without ANY Ace check — half-implemented L07 (per `xref_X4_pro2_deal.md`
MF-1).

The Pro-2 PDF rationale (line 10-12 of `03b_secrets_pro_2.txt`): the
Ace is **defensive** — it gives the Hokm bidder a way to fight back
when the opp tries to flip into Sun, run Kaboot, or claim 4-Hundred
(Carré-A). Without an Ace, the Hokm bid is "naked": opp has at most
the cost of failing to call Sun/Kaboot/4-Hundred and gets a free
windfall when they DO have the shape.

---

## 2. Issue 1 — `hasAnyAce` correctly includes A-of-trump (CHECK PASSED)

**Question 6 from prompt:** "edge case — A-of-trump only … does the
loop correctly include A-of-trump in `hasAnyAce`?"

**Answer:** Yes. From `Bot.lua:787-797`:

```lua
for _, c in ipairs(hand) do
    local r, su = C.Rank(c), C.Suit(c)
    if su == suit then
        count = count + 1
        if r == "J" then hasJ = true end
        if r == "A" then hasAnyAce = true end   -- A-of-trump → hasAnyAce
    elseif r == "A" then
        hasSideAce = true
        hasAnyAce  = true                       -- side Ace → both flags
    end
end
```

The `hasAnyAce` flag is set under both branches (trump-suit Ace AND
side-suit Ace). A bot holding `J + A + 3 lower trumps` (4 trumps,
the trump-A counts) passes the v0.10.0 gate. **Loop is correct.**

Note: `hasSideAce` is only set on the side-suit branch. This is
correct — `hasSideAce` is used by the `count == 3` B-1 branch, which
intentionally requires an OUTSIDE Ace (the trump-A's role is
supplied by trump-count, the side-A is the off-trump trick power).

---

## 3. Issue 2 — Tier dispatch is correct (CHECK PASSED)

**Question 1 from prompt:** "Verify what `Bot.IsM3lm` returns for
Fzloky and Saudi-Master tiers (should also be true)."

**Answer:** Confirmed correct. From `Bot.lua:60-65`:

```lua
function Bot.IsM3lm()
    return WHEREDNGNDB
       and (WHEREDNGNDB.m3lmBots == true
            or WHEREDNGNDB.fzlokyBots == true
            or WHEREDNGNDB.saudiMasterBots == true)
end
```

The L07 gate correctly fires for M3lm, Fzloky, AND Saudi Master.
This matches the documented "strictly extends" hierarchy in
`CLAUDE.md`.

`Bot.IsAdvanced()` (line 48-55) similarly cascades. Basic tier
(no DB flag set) bypasses the gate — preserved permissive behavior.

---

## 4. Issue 3 (S2-medium) — strong-but-Aceless trump hands force pass

**Question 2/5 from prompt:** "if M3lm bot has J + 4 trumps + 0 Aces,
hokmMinShape returns false. … 5+ trump hand with no Aces is
mathematically very strong (sweep potential). Forcing pass leaves
opp to take contract on weaker hand. EV-negative scenario likely."

**Status:** **Confirmed S2-medium.** This is a real EV-negative
scenario for the M3lm+ tier.

### The hand class

Consider an M3lm bot holding (trump = Hearts):
- J♥, 9♥, T♥, K♥, 8♥ — five trumps including **both** top trumps
  (J = rank 8, 9 = rank 7) and the K-Q-cover (T = rank 6, K = rank
  4 partial). 4-card sequence-meld (J-9-T plus a trump = +20 raw)
  plus possible Belote-of-trump pair if Q is out.
- 7♣, 8♣, 9♦ — 3 garbage off-trump cards, **no Aces anywhere**.

Trump strength as raw values: J(20) + 9(14) + T(10) + K(4) + 8(0)
= ~48 trump points + meld + Belote chance. This is solidly above
`thHokmR2` (~30-38 jittered). In Saudi pro convention this hand
SHOULD bid Hokm — even Pro-2's L07 author would concede that 5
trumps including J+9 is rare enough that the Sun-overcall fear is
muted (opp would need 3 Aces + cover to make Sun work, which is
~1.5% of deals).

### What v0.10.0 does

`hokmMinShape` returns `false` because `hasAnyAce == false`. The
bot returns `K.BID_PASS`.

### What happens next

**Round 2 fall-through analysis** (Bot.lua:1481-1513):

1. The `for suit in K.SUITS` loop (line 1482) calls `hokmMinShape`
   for every suit. ALL fail the Ace gate. `bestSuit = nil`.
2. Line 1498: `sunMinShape(hand)` — needs ≥2 Aces or A+T mardoofa.
   This bot has zero Aces. Returns false.
3. Line 1510: `bestSuit and bestScore >= thHokmR2` — `bestSuit` is
   nil. Skipped.
4. Line 1513: `return K.BID_PASS`.

**The bot passes everything.** A weaker opp picks up the contract
on a marginal hand. Bot's strong-hand EV is forfeited.

### EV cost estimate

For a 5-trump hand without Aces (rough deal probability ~3-4% per
hand the bot sees), the opp now bids Hokm on weaker shape (typical
~30-35% expected hold). Old behavior: bot bids Hokm at strength
~48-55, ~75-80% expected hold = ~+45 expected raw. New behavior:
opp bids on ~30-35% hold, bot defends without Aces (~poor defensive
shape, no over-trick power) = ~-15 expected raw. Net swing per
fired event: ~60 raw points = ~6 game points × ~3% deal frequency
= ~0.18 game points per deal lost on average.

Over a 152-point match (~30-40 deals), this is ~5-7 game-point
deficit vs the v0.5.8 baseline. **Empirically detectable in
headless tournament.**

### Recommended fix (NOT applied per prompt)

Soften the gate: drop the Ace requirement when trump count is
"sweep-strong" (5+ AND J + 9), since Pro-2 L07's stated rationales
(Sun-overcall, Kaboot, 4-Hundred fear) are mathematically unlikely
when bot already holds 5 trumps + top-2.

```lua
-- v0.10.x: L07 gate softened for sweep-strong trump shape.
-- Pro-2 L07 fears (Sun-overcall, Kaboot, 4-Hundred) require opp
-- to have 3 Aces + cover or 4-Aces (Carré-A) — both extremely
-- rare when bot already has 5 trumps including J+9. Skip the
-- Ace gate for sweep-strong hands.
local has9 = false
for _, c in ipairs(hand) do
    if C.Rank(c) == "9" and C.Suit(c) == suit then has9 = true; break end
end
local sweepStrong = (count >= 5 and hasJ and has9)
if Bot.IsM3lm and Bot.IsM3lm() and not hasAnyAce and not sweepStrong then
    return false
end
```

Alternatively: tier-gate at Saudi-Master only (most conservative
pro tier), leaving M3lm/Fzloky on the looser pre-v0.10.0 rule.

---

## 5. Issue 4 (S2-medium) — partner-bid suppression interaction

**Question 3 from prompt:** "Sun fallback: when bot can't bid Hokm
due to Ace requirement, does it fall through to Sun bid attempt?"

**Status:** **Confirmed degenerate fall-through.** The interaction
of L07 with G-4 partner-bid suppression breaks the partner-support
path.

### G-4 partner-bid suppression

`Bot.lua:1461-1474`:

```lua
do
    local g4_partner = R.Partner(seat)
    local g4_partnerBid = S.s.bids and S.s.bids[g4_partner]
    local g4_partnerBidHokm = g4_partnerBid
        and g4_partnerBid:sub(1, #K.BID_HOKM) == K.BID_HOKM
    if g4_partnerBidHokm then
        -- Partner committed Hokm. Allow Sun overcall (different
        -- contract type, not a "competing Hokm" violation).
        if sunMinShape(hand) and sun >= thSun then
            return K.BID_SUN
        end
        return K.BID_PASS
    end
end
```

This block runs in round 2. If partner bid Hokm in R1, bot is
allowed only Sun-overcall or pass. **G-4 is unaffected by L07 — it
gates on partner's bid, not on bot's hand.**

### Round-1 Hokm-on-flipped path

`Bot.lua:1431-1445`:

```lua
if not anyHokm and not anySun and bidCardSuit then
    if hokmMinShape(hand, bidCardSuit) then
        ...
        if strength >= thHokmR1 then
            return K.BID_HOKM .. ":" .. bidCardSuit
        end
    end
end
return K.BID_PASS
```

R1 falls straight to PASS if `hokmMinShape` rejects. **No Sun
fallback in R1 because direct-Sun was already attempted at line
1423** (`if sunMinShape(hand) and sun >= thSun then return K.BID_SUN`).

So if the bot has 0 Aces AND 5+ trumps, in R1:
- Sun direct check: `sunMinShape` requires ≥2 Aces or A+T mardoofa.
  Zero Aces → fails. No Sun.
- Hokm-on-flipped: L07 blocks it. No Hokm.
- **R1 result: PASS.**

In R2 (assuming partner didn't bid Hokm):
- Best-suit loop: every suit blocked by L07. `bestSuit = nil`.
- Sun check: still 0 Aces. `sunMinShape` fails.
- **R2 result: PASS.**

**The bot passes both rounds with a 5-trump strong-hand.** This is
the EV-negative cascade from Issue 3.

### Hokm-flipped-suit only with side-Ace (count==3 + side-Ace)

**Question 3 sub-case:** A bot holding J + 2 lower trumps + 1
side-Ace satisfies `count == 3 and hasSideAce` → returns true at
line 804. `hasAnyAce` is also true (line 795 sets it on the side-A
branch). So the L07 gate at line 800 PASSES. **No regression for
the count==3 path** — it was already enforcing a side-Ace, and the
new `hasAnyAce` check is a strict superset of `hasSideAce`.

This is consistent: the original v0.5.8 B-1 minimum required
side-Ace; v0.10.0 just extended that requirement to the count>=4
self-sufficient branch.

---

## 6. Issue 5 (S3-low) — calibration drift in headless tournament

**Question 4 from prompt:** "how often does this rule fire in
headless tournament? Could the M3lm+ tier now BID LESS often,
making it under-perform vs Basic/Advanced?"

### How often does an Aceless bidder occur

A 32-card deck has 4 Aces. An 8-card hand has expected ~1.0 Aces
(8 × 4/32). The probability of holding **zero Aces** in 8 cards is
C(28,8) / C(32,8) = ~30.5%. Of those, the subset that ALSO has
hokmMinShape-eligible trump (J + count ≥ 4 in some suit, OR
J + count == 3 + side-Ace which is impossible if no Ace) is
substantially smaller. Rough estimate:

- Pre-v0.10.0: of all hands satisfying B-2 (count>=4 + hasJ),
  ~30% had zero Aces and would now be blocked. That's the
  measurable bid-suppression rate.
- Hands with B-1 (count==3 + hasJ + hasSideAce) are unaffected
  (they already had an Ace).

### Calibration risk

If the tournament harness measures M3lm+ vs Advanced/Basic head-to-
head, and M3lm+ is now passing on hands Advanced would bid, the
**M3lm+ tier could under-perform Advanced on Hokm-bid frequency
metric**, IF the Aceless count>=4 hands have positive Hokm-bid EV
(which Issue 3 argues they do for the strongest cases).

**Test recommendation (NOT applied per prompt):** run a 100-deal
headless tourney comparison of v0.10.0 M3lm+ vs v0.9.x M3lm+ on
identical seeds, measure delta in:
- Hokm bids per match
- Sun bids per match (should be unchanged)
- Match wins per 10-match block
- Average margin per match

If M3lm+ regresses on (a) bid frequency or (c) wins, the L07 gate
is too aggressive.

### Mitigation in code

Currently no mitigation — the `count >= 4` branch is unconditionally
gated by `hasAnyAce` at M3lm+. Pre-v0.10.0 it was unconditionally
permissive. Neither extreme is calibrated; a tier-aware
intermediate (e.g. only Saudi-Master enforces, M3lm/Fzloky stay
permissive at count>=5 with J+9) would let the tier hierarchy
preserve "strictly extends" semantics while not losing the strong
trump hands.

---

## 7. Issue 6 — design wrinkle: Pro-2 L07's ACTUAL Saudi text

`03b_secrets_pro_2.txt` line 10:
> "اذا اراد ان يحكم اللاعب فلابد من وجود اكه لديه"

Translation: "If a player wants to call Hokm, he MUST have an Ace."

Then lines 11-12 list the rationales:
- "خوفا من إجبار الخصم على الصن او من الكبوت او من الاربع ميه"
  — fear of opp forcing Sun, Kaboot, or 4-Hundred (Carré-A).
- "خوفا من ظن زميلك بأن لديك اكه ف بموجبها يشكل او يشتري صن"
  — fear partner ASSUMES you have an Ace and Ashkals or Sun-buys
  on that assumption.

**The second rationale is partner-coordination.** The current
`xref_X4_pro2_deal.md` Phase-1 source-H verdict is "STRATEGY (not a
hard rule)" — but the partner-assumption rationale is actually
weaker than the Sun-overcall rationale. Many real Saudi tables
treat L07 as a soft convention, not a hard veto.

The v0.10.0 implementation is a **hard veto** — `return false` from
`hokmMinShape`. This converts a soft convention into a hard rule.

For a tier-gated implementation that respects the convention's
soft nature: weight the Hokm strength score down by some bonus
when no Ace, rather than veto. Example:

```lua
-- Penalize Aceless Hokm hands at M3lm+ tier instead of vetoing.
if Bot.IsM3lm() and not hasAnyAce then
    strength = strength - K.BOT_PICKBID_NO_ACE_PENALTY  -- e.g. 12
end
```

That would let the strongest 5-trump-no-Ace hands STILL bid
(strength survives the penalty), while weaker 4-trump-no-Ace
hands fall below threshold and pass. **This is the
strategy-as-soft-bias approach** that Saudi pro tables actually
use, and it preserves the calibration of the bidding threshold
constants.

This is a design recommendation, not a bug — the current hard veto
is consistent with how other strategy gates in `hokmMinShape`
work (e.g. B-4 absolute-floor "no J → no Hokm"). But B-4 is a
HARD Saudi rule (per decision-trees.md Definite). L07 is a SOFT
convention. Implementing them at the same severity level is a
documentation-vs-implementation mismatch.

---

## 8. Summary of findings

| ID | Severity | Issue | Location |
|---|---|---|---|
| **D-RT-11.1** | INFO | A-of-trump correctly counted in `hasAnyAce` | `Bot.lua:792-795` |
| **D-RT-11.2** | INFO | Tier dispatch (`Bot.IsM3lm`) correctly cascades to Fzloky/Saudi-Master | `Bot.lua:60-65, 800` |
| **D-RT-11.3** | **S2-medium** | 5+ trump no-Ace hands forced to PASS — strong sweep-shape EV-negative | `Bot.lua:800-803` |
| **D-RT-11.4** | **S2-medium** | R1+R2 cascade: no Sun fallback when L07 blocks Hokm AND no ≥2 Aces (sunMinShape false) | `Bot.lua:1423, 1431-1445, 1481-1513` |
| **D-RT-11.5** | S3-low | Possible bid-frequency regression vs Advanced (calibration drift) — needs headless test | tournament harness |
| **D-RT-11.6** | DESIGN | Hard veto for soft Saudi convention — penalty-based bias may be more faithful | `Bot.lua:800-802` |

### No legality bugs

L07 is strategy, not a Saudi rule. Nothing in v0.10.0's
implementation is illegal — the question is purely calibration
quality (do M3lm+ bots win more or less than Advanced after this
change).

### No regression in count==3 branch

The count==3 branch was already enforcing `hasSideAce`. The new
`hasAnyAce` gate is a strict superset (any Ace, including
trump-A). No hand that satisfied count==3+hasSideAce loses
eligibility under the new rule.

### Recommended actions (NOT applied per prompt)

1. **Run headless tournament A/B** on 100-200 deal seeds comparing
   v0.10.0 M3lm+ vs v0.9.x M3lm+ Hokm-bid frequency and match
   margin.
2. **Consider sweep-strong escape clause**: skip L07 gate when
   `count >= 5 AND hasJ AND has9` (sweep potential too strong to
   honor the defensive convention).
3. **Consider penalty-based bias instead of hard veto**: subtract
   K.BOT_PICKBID_NO_ACE_PENALTY (e.g. 12) from `strength` instead
   of returning false. Lets the strength threshold do the work.
4. **Consider Saudi-Master-only enforcement**: tier-gate at
   `Bot.IsSaudiMaster()` rather than `Bot.IsM3lm()` so M3lm/Fzloky
   stay on the proven v0.9.x calibration while only the most-
   conservative tier picks up the Pro-2 strategy convention.

### Test gap

No unit test was added in v0.10.0 for the count>=4-no-Ace path.
A tournament-level test would catch the calibration drift; a unit
test ensuring `hokmMinShape({"J♥","T♥","9♥","K♥","8♥",...}, "♥")`
returns false at M3lm+ is also missing — the new gate's effect on
strong-trump hands is untested.
