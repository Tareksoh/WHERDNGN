# Wave 5 C5 — Foundational Human Bid Reading + First Play-Mistake Taxonomy

**Auditor:** Pathfinder C5 — Research-only pass
**Codebase version:** v0.4.4
**Date:** 2026-05-03
**Source angles:** wave5_C5_foundational_human_prompt.md (angles B-14 through B-18)

---

## B-14 — Human vs. bot bid-signal cross-contamination in partnerBidBonus

**IS-EXPLOITED:** NO

### Evidence

`partnerBidBonus` is defined at Bot.lua:410–427. It reads `S.s.bids[partner]` and
returns fixed bonuses based on bid type:

```
partner HOKM matching our trump  → +20
partner HOKM other suit          → +10
partner SUN                      → +15
partner ASHKAL                   → +15
partner PASS (both rounds)       → -10
no info / unknown                →  0
```

No check on `S.s.seats[partner].isBot` exists anywhere in this function or in its
callers (`Bot.PickDouble` at line 1169, `escalationStrength` at line 1198). The
function is also used by the escalation chain: `PickTriple`, `PickFour`, `PickGahwa`
all go through `escalationStrength` which in turn calls `partnerBidBonus`.

The `isBotSeat` helper is defined at Net.lua:2874 and is used in MaybeRunBot dispatch
but is never imported or called inside Bot.lua.

### The Problem

A bot-partner's Hokm bid is calibrated: it means `J + kicker` (Round 1) or
`bestScore >= thHokmR2` (Round 2), both against `TH_HOKM_R1_BASE=42` /
`TH_HOKM_R2_BASE=36` (Bot.lua:35–36). The +20 bonus is correctly sized for this.

A human partner's Hokm bid may come from any hand — a casual player will bid
on a 3-card suit with only K/Q, or on pattern memory, or to "call dibs." The +20
bonus applied identically to a human's Hokm bid inflates the bot's apparent
combined-team strength by up to 20 points (one full Bel threshold step) with no
evidence it is warranted.

Similarly, the -10 PASS penalty is calibrated to a bot's calibrated pass (genuinely
weak hand). A human may pass round 1 simply because they do not understand
the Ashkal convention or missed their window; the -10 defensively biases the bot
away from escalation against weak-looking opposition when the human actually held
a strong hand but passed for situational reasons.

### Fix Proposal

Add an `isHumanPartner(seat)` helper in Bot.lua that reads
`S.s.seats[R.Partner(seat)].isBot`. In `partnerBidBonus`, gate the full bonus
magnitudes on bot partners:

- Human-partner Hokm same trump: reduce from +20 to +8 (reflects uncertain
  signal reliability).
- Human-partner Hokm other suit: reduce from +10 to +5.
- Human-partner SUN or ASHKAL: keep +15 (Sun is structurally harder to
  mis-declare; over-bidding Sun is rarer in practice).
- Human-partner PASS: reduce penalty from -10 to -4 (less confident a pass
  means a genuinely bad hand).

The same isHumanPartner guard should be threaded through `escalationStrength`
so PickDouble / PickTriple / PickFour / PickGahwa also benefit.

---

## B-15 — Human declarer vs. defender role assignment: exploitation target

**IS-EXPLOITED:** NO

### Evidence

No code path in Bot.lua checks whether the contract's declarer is human or bot
before making Bel / Triple / Four / Gahwa decisions. `PickDouble` (line 1153)
computes a scalar strength and compares to a jittered `BOT_BEL_TH` with urgency
adjustments. `partnerEscalatedBonus` (line 496) looks at the contract's escalation
flags but not at the human/bot status of the bidder.

The existing design comments (Bot.lua:14–15) document the intended asymmetry
("bid on real strength... Bel/Triple/Four/Gahwa escalation is gated on strength
thresholds") but there is no mention of human-bidder over-estimation or
human-defender under-Bel tendencies anywhere in Bot.lua or BotMaster.lua.

The `_partnerStyle` ledger (Bot.lua:137–196) accumulates per-seat bel/triple/four
counts but never reads `S.s.seats[seat].isBot` to bifurcate style models between
human and bot seats. `styleBelTendency` (line 181) is unused by any picker
(confirmed by the "reserved for future M3lm-Plus heuristics" comment at line 178).

### The Problem

The bot treats a human bidder's contract as equally reliable as a bot bidder's.
In practice, human bidders over-commit (bid on marginal hands) meaning the
defender bot should Bel at a *lower* threshold against a known-human declarer —
the contract is statistically more likely to fail. Conversely, against a bot bidder
the bot can trust the bidder threshold is calibrated and a Bel is riskier.

The mirror failure: the bot's PickDouble fires based purely on own-hand strength.
It does not inflate the Bel incentive when the opponent declarer is human.

### Fix Proposal

In `PickDouble` and `escalationStrength`, check if `contract.bidder` refers to a
human seat. If so, apply a threshold reduction of 5–8 points for Bel decisions
(lower bar to Bel against human declarers) and a corresponding strength bonus for
Triple decisions when the bot itself is the bidder (human defenders under-Bel, so
the contract failure probability is lower). Specifically:

- Bel threshold: `th = K.BOT_BEL_TH - 6` when `not isBotSeat(contract.bidder)`.
- Triple threshold: `th = K.BOT_TRIPLE_TH + 4` when defenders are human (less
  likely to escalate back).

This requires passing the `isBotSeat` predicate into Bot.lua or making it a Bot
module function that reads `S.s.seats`.

---

## B-16 — Human over-trumping in panic: J/9 waste on low-value tricks

**IS-EXPLOITED:** PARTIALLY

### Evidence

The void-based free-trick logic exists at Bot.lua:824–837 (pickLead, heuristic #1):

```lua
for _, c in ipairs(nonTrumps) do
    if opponentsVoidInAll(seat, C.Suit(c)) then
        -- leads highest in that suit (free trick)
```

`opponentsVoidInAll` at line 272 checks all opponent seats uniformly regardless of
whether the opponent is human or bot.

The strategy "lead a suit where the opponent is known void, forcing them to ruff"
is implemented and fires when BOTH opponents are confirmed void in a suit. The
free-trick is captured by leading the *highest* card.

However, the exploitable sub-case asked about by B-16 — deliberately leading a
*low-value* suit into a *single* void opponent to bait their high trump (J/9) —
is NOT present. The `opponentsVoidInAll` function requires BOTH opposing seats to
be void. If only one of the two opponents is void (the human), the free-trick
branch does not fire. The bot does not compute: "if this specific opponent is void,
I can burn their J with a low-value lead."

### Partial Credit

The void memory tracking (`Bot._memory[opp].void`) is general-purpose and does
record human opponents' voids correctly through `Bot.OnPlayObserved` (line 200).
The infrastructure for the exploit is present; the decision logic to act on a
single-seat void for trump-waste induction is absent.

### Fix Proposal

Add a targeted sub-heuristic in `pickLead` (Advanced/M3lm tier) for the
single-void trap:

After heuristic #1 (both void), before heuristic #2 (singletons), check:
"Does exactly one opponent appear void in a suit, and is that opponent inferred
to hold high trump (no prior J/9 observed in `Bot._memory[opp].played`)?"
If yes and the suit has low card value (trick is worth ≤5 points with 7/8/Q cards),
lead lowest in that suit to force a panic ruff. Gating on M3lm tier is appropriate
since this is opponent-model-dependent.

---

## B-17 — Human under-ruffing: playing 7-of-trump when over-ruff is possible

**IS-EXPLOITED:** NO

### Evidence

In `pickFollow` (line 915), when an opponent is winning and the bot has available
trump winners, the code path at line 1027–1045 handles position 3 (third-hand-high).
At line 1034–1044, when only trump winners exist in Hokm:

```lua
if #trumpWinners > 0 and #trumpWinners == #winners then
    return lowestByRank(trumpWinners, contract)
end
```

This conserves high trump by ruffiing with the lowest available trump winner — a
correct general heuristic. However, the bot's decision here is based solely on
its *own* hand: it picks the minimum sufficient ruff to win. It does not adjust
based on whether the *fourth seat opponent* is known to under-ruff (play 7 when
they could over-ruff).

Specifically, in position 3, if the bot knows or could infer that the fourth-seat
opponent is human and likely to play the 7-of-trump (under-ruff) rather than
over-ruff, the bot could ruff with a *higher* card than strictly necessary to
"over-ruff the anticipated under-ruffer," thereby removing an opponent's high
trump that the opponent would sacrifice anyway in a panic. This logic is completely
absent.

The `_partnerStyle` ledger (line 136) has `bels/triples/fours/gahwas/trumpEarly/
trumpLate` counters but no per-seat "ruff quality" tracking (whether a seat tends
to ruff with minimum vs. over-ruff).

### Fix Proposal

In `pickFollow` at position 3, before falling through to `lowestByRank(trumpWinners)`,
add a M3lm-gated check: if the fourth seat is a *known human* (not `isBotSeat`),
and the number of unplayed high trump (J, 9) belonging to opponents is non-zero
per `Bot._memory`, use a trump one step higher than the minimum winner. The goal
is not to over-commit — if the bot's minimum winner is already J or 9, stay with
minimum. This only fires when the bot has e.g. [9, Q, K] available and the
minimum winner is Q: use K instead to remove the opponent's 9 if they would only
have played 7. Gate this tightly (M3lm or SaudiMaster tier only).

---

## B-18 — Human third-hand-low: not committing highest winner in position 3

**IS-EXPLOITED:** PARTIALLY

### Evidence

The bot's own position-3 heuristic IS correctly implemented: `pickFollow` at
line 1027:

```lua
elseif pos == 3 then
    -- Highest winner so the 4th seat can't easily overcut.
    ...
    return highestByRank(winners, contract)
```

So the bot plays third-hand-high on its own position-3 turns.

The question is whether the bot *exploits* a human's expected position-3-low
mistake when the bot is in position 4. In position 4, the bot uses
`lowestByRank(winners, contract)` (the default / pos 4 cheapest-winner path at
line 1049). This is correct given that the human in position 3 should have played
high — against a bot-perfect position 3 player, cheapest winner in position 4 is
optimal.

But B-18's point is the inverse: when the bot knows position-3 is a *human* who
will likely play *low* (leaving the trick vulnerable), the bot in position 4 can
afford a cheaper winner *and that position-3 human committed a low card instead of
high*. This scenario is not modeled anywhere.

Partial credit: the existing lowestByRank(winners) at pos 4 happens to be correct
behavior for exploiting a human pos-3 under-commit (the bot uses the cheapest
card to win since the human left the trick cheaper to take). However, there is no
detection of the converse risk: when the *bot* is in position 3 facing a human
in position 4, the current "always play highestByRank(winners)" heuristic is blind
to whether the human position-4 player is known to hold weak trump. The comment
at line 974 says "Commit a card that survives the 4th seat's likely overcut" but
this is based purely on structural position, not on the actual trump strength of
the human opponent in seat 4.

### Fix Proposal

Two sub-fixes:

1. **Bot at pos 3, human at pos 4:** In the pos==3 branch (line 1027), add an
   Advanced-gated check: if the fourth seat is a *known human* (`not isBotSeat`)
   AND `Bot._memory[pos4seat].played` shows no high trump has been played by that
   seat yet, assume they *might* over-ruff — keep the current `highestByRank`
   behavior. But if memory shows the human has already dumped their J or 9 of trump
   in a prior trick, downgrade to the next-highest winner that still beats the
   current trick winner. This avoids wasting the J/9 unnecessarily.

2. **Bot at pos 4, human at pos 3 who under-committed:** No structural fix needed
   (the `lowestByRank(winners)` path at pos 4 is already optimal). However, add a
   comment documenting this human-exploitation as intentional and correct, so
   future audit passes do not flag it as a missing optimization.

---

## Summary Table

| Angle | IS-EXPLOITED | Primary file:line |
|-------|-------------|-------------------|
| B-14 — partnerBidBonus human/bot cross-contamination | NO | Bot.lua:410–427 |
| B-15 — Human declarer/defender role exploitation | NO | Bot.lua:1153–1179; 1191–1199 |
| B-16 — Human panic-ruff J/9 waste induction | PARTIALLY | Bot.lua:272–282; 824–837 |
| B-17 — Human under-ruffing not modeled or exploited | NO | Bot.lua:1034–1044 |
| B-18 — Human third-hand-low: pos-3/4 exploitation | PARTIALLY | Bot.lua:1027–1049 |

---

## Cross-Cutting Gap: No `isBotSeat` predicate in Bot.lua

All five angles are blocked by the same root absence: Bot.lua has no access to
the seat-type query used in Net.lua (`isBotSeat` at Net.lua:2874) and does not
read `S.s.seats[seat].isBot` anywhere. Introducing a single helper function
`Bot.IsBotSeat(seat)` that reads `S.s.seats[seat] and S.s.seats[seat].isBot` would
unblock all five proposed fixes. This should be the foundational change before any
of the per-angle exploitations are implemented.

---

*Report generated by Pathfinder C5. No code was modified.*
