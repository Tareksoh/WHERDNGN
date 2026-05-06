# D-RT-12 — Bait-Ledger Forced-J + Round-Scope Fix Red-Team

**Track:** D (Red-Team) | **Target:** v0.9.2 #46 | **Status:** EXPLOITS PERSIST

## Scope

The v0.9.2 patch made two changes against the v0.8.2 bait-ledger
exploit:

1. **Round-scope** the ledger via `Bot.ResetMemory` (Bot.lua:164-166):
   `style.baitedSuit = { S = 0, H = 0, D = 0, C = 0 }` reset each
   round.
2. **Forced-J approximation** at write site (Bot.lua:546-559): only
   flag bait if `mem.played` already contains a lower-rank
   same-suit card played by THIS seat earlier in the round.

This red-team revisits the original four exploit vectors plus
new ones the fix introduces.

---

## Code under review

### Write site (Bot.lua:523-562)

```
if not wasIllegal and contract and #trickPlays >= 2
   and C.Rank(card) == "J" and style.baitedSuit then
    local prePlays = {}
    for i = 1, #trickPlays - 1 do prePlays[i] = trickPlays[i] end
    if #prePlays >= 1 then
        local prevTrick = { plays = prePlays, leadSuit = leadSuit }
        local prevWinner = R.CurrentTrickWinner(prevTrick, contract)
        if prevWinner == R.Partner(seat) then
            local lowerSeen = false
            local plain = K.RANK_PLAIN
            local jr = plain["J"] or 0
            if mem and mem.played then
                for _, low in ipairs({ "7", "8", "9" }) do
                    if mem.played[low .. cardSuit] then
                        lowerSeen = true; break
                    end
                end
            end
            if lowerSeen then
                style.baitedSuit[cardSuit] =
                    (style.baitedSuit[cardSuit] or 0) + 1
            end
        end
    end
end
```

### `mem.played` population site (Bot.lua:333-335)

```
local mem = Bot._memory[seat]
if not mem then return end
mem.played[card] = true
```

### Round-scope reset (Bot.lua:164-166)

```
if style.baitedSuit then
    style.baitedSuit = { S = 0, H = 0, D = 0, C = 0 }
end
```

### Read site (Bot.lua:2012-2028, formerly 1796-1812)

```
if Bot.IsM3lm() and Bot._partnerStyle then
    for s2 = 1, 4 do
        if R.TeamOf(s2) ~= R.TeamOf(seat) then
            local m = Bot._partnerStyle[s2]
            if m and m.baitedSuit then
                for suit, count in pairs(m.baitedSuit) do
                    if count >= 1 and not fzlokyAvoidSuit
                       and suit ~= (contract.trump or "") then
                        fzlokyAvoidSuit = suit
                        break
                    end
                end
                ...
```

---

## Findings

### F1 — Forced-J gate is unsound: 4-card-suit forced J still flags. **HIGH (HIGH conf.)**

The `lowerSeen` heuristic is the inverse of what was needed.
The audit (line 21-25) explicitly asked for "could opp have played
a non-J Spade and chose not to" — i.e. opp had **another legal
card in this suit AT TIME-OF-PLAY**. The patch instead asks "did
this opp play a lower of this suit at any earlier point in the
round". These are different questions and the gap is exploitable.

**Concrete repro (per RT brief item #2):**

- Trick 1: opp at seat 2 plays 7♠ losing to bot partner's bare-A.
  `mem.played["7S"] = true` for seat 2.
- Tricks 2-4: opp distributes other suits.
- Trick 5: opp plays J♠ under bot partner's winning state.
  Suppose 7♠ was opp's only ♠ besides {J♠, plus three more ♠
  visible elsewhere}. The J was forced (only ♠ left in hand).
- Forced-J check sees `mem.played["7S"] == true` for THIS seat
  → `lowerSeen = true` → `baitedSuit[S]++`.

The J was structurally forced (only ♠ remaining), yet the
heuristic flags it as bait. **The original exploit class —
flagging forced J-plays as deceptive — is NOT eliminated; it is
narrowed to "opp who already played a lower in suit earlier and
now plays their forced final J".** Round-distribution is common.

The audit's own recommendation #2 said:
> Forced-J gate. At write site, require
> `#legalCardsInSuit(seat, leadSuit, observedDiscards) >= 2`
> before incrementing.

This is a count of CURRENTLY-LEGAL cards (size of suit-bucket
in opp's hand). The implementation instead checks PAST plays,
which is necessary-but-not-sufficient — an opp can have played
lower in suit earlier AND have only the J left now. False
positive persists.

### F2 — Adversarial seeding (deliberate exploit). **HIGH (HIGH conf.)**

Per RT brief item #6: an adversary can deliberately play 7,8,9
of the same suit in the early tricks to seed `mem.played`, then
play J in a later trick under partner-winning. The heuristic
fires on the FIRST `lowerSeen` hit (any of 7/8/9), so seeding
ANY ONE low card is sufficient.

The cost to the exploiter is small (low cards lose tricks
anyway). The benefit is identical to the v0.8.2-era exploit:
once the bait flag fires once, the bot's `pickLead` avoids the
suit. Round-scope limits the damage to the current round (down
from "rest of game" pre-v0.9.2), but **the exploit is still
profitable within a single round** — the opp denies the bot a
high-EV lead in their long suit by paying ≤1 J + ≤1 low card.

The fix's intent (per the audit at line 26: "the opp could have
played a non-J Spade and chose not to") is exactly what the
adversary now CAUSES the heuristic to believe. The fix
*encourages* the seeding pattern by making it the trigger.

### F3 — Defensive false positive on natural play patterns. **MED (HIGH conf.)**

In normal play, opps frequently:
1. Play 7/8/9 of a suit when partner is winning (correct
   tasgheer convention — play smallest under partner-winning)
2. Later play J of same suit when forced or when trying to
   establish a lower honor

This is normal, non-deceptive play. The forced-J gate flags it
regardless. Late-trick J-plays in a previously-played-low suit
are **common** (opp has been bleeding the suit), so the FP rate
inside a round is non-trivial. The original audit estimated 30%
baseline FP on the unguarded predicate; the v0.9.2 gate prunes
*some* of those (forced-J on virgin suits) but ADDS a new FP
class (player who tasgheered correctly earlier, J forced or
near-forced later).

Net FP rate inside a single round: estimated **20-25%** of
J-trigger fires (down from ~30%, but adversarial seeding
recovers most of the gap).

### F4 — `mem.played` cross-population is correct. **(LOW concern, HIGH conf.)**

Bot.lua:332-335 unambiguously populates `mem.played[card] = true`
for the SEAT whose play was observed (`Bot._memory[seat]`).
Every observed play populates the per-seat `played` table,
regardless of seat identity (bot, partner, opp). RT brief item
#1 ("does mem.played ever bypass population?") is answered: no.
The line-335 write is unconditional and runs before the wasIllegal
short-circuit (the wasIllegal check guards downstream void/discard
inferences only).

Edge case: if `Bot.OnPlayObserved` is bypassed for a play (e.g.
network drop, missing dispatch), `mem.played` is incomplete.
That's a general correctness concern, not specific to bait
detection. **Not exploitable in normal flow.**

### F5 — Round-scope reset correctly blocks cross-round amplification. **(NIL exploit, HIGH conf.)**

Bot.lua:164-166 wipes `style.baitedSuit` in `Bot.ResetMemory`.
`Bot.ResetMemory` is called via Net.lua:1764 / Net.lua:1800 at
the start of every round. **Cross-round amplification IS
eliminated** as advertised. RT brief item #3 (cross-round
persistence) is sound on the within-game side.

### F6 — Game-end → game-start gap. **LOW (HIGH conf.)**

`Bot.ResetStyle` is called from Net.lua:1804-1805 ONLY when
`roundNum == 1` (game-start). Between the LAST round of game N
and round 1 of game N+1:

- Round N's last round-end does NOT call `ResetStyle` (only
  `ResetMemory`, but the v0.9.2 fix wipes `baitedSuit` in
  `ResetMemory`, so we're fine).
- Round N+1 trick 1 fires before any new bait flag is set, but
  any old flag is already cleared by the round-N last
  `ResetMemory` call.

**Verdict: no leak.** The `ResetMemory`-driven wipe at every
round-start (including round 1 of the next game) is the
operative reset for `baitedSuit`. `ResetStyle`'s game-scope
reset is a safety net for the OTHER counters
(bels/triples/fours/aceLate/etc.) that are intentionally
per-game.

### F7 — `/reload` mid-round persistence is correct. **(LOW concern, HIGH conf.)**

State.lua:272 saves `partnerStyle = B.Bot._partnerStyle`
including the round-scoped `baitedSuit` field. State.lua:364-365
rehydrates on `RestoreSession`. Per RT brief item #3, on a
mid-round /reload the bait flag survives — which is the correct
behavior under v0.9.2 (still the same round). At round-end the
new `ResetMemory` wipes it.

### F8 — Single-round EV cost from one false-positive. **MED (MED conf.)**

Per RT brief item #5: a single FP fires `baitedSuit[X] = 1`. At
the read site (Bot.lua:2012-2028) `count >= 1` is the threshold,
so one fire = one round of `fzlokyAvoidSuit = X`. The bot's
`pickLead` then refuses to lead suit X for the rest of the
round. In a Hokm round where suit X is the bot's strongest
non-trump asset (Ace + boss-cards), the avoid hint costs:

- Lost lead-tempo (Ace not cashed at optimal moment) — typically
  10-30 raw points if the suit chains 3+ tricks.
- Forced lead of weaker suit, often handing the trick to
  opponents.

EV cost per fire: estimated **15-25 raw points** in the average
case, more if the suit is the only path to bare-A cashing.
Inside a round of nominal 162 raw points this is **~10-15%
swing** — material.

### F9 — `lowerSeen` includes the seat's own pre-J plays this trick. **LOW (HIGH conf.)**

If the trick chain is the SAME trick (e.g. trick has 4 plays and
seat played a low ♠ as their first, and J♠ would only happen if
they played twice — which can't happen in one trick). So this
specific subcase doesn't manifest. Calling out for completeness.

### F10 — `jr` variable computed but unused. **(NIL exploit, COSMETIC)**

Bot.lua:548 computes `local jr = plain["J"] or 0` but never
references `jr` after. Likely a remnant of an earlier
implementation that compared rank values. Dead code. Not an
exploit, but worth removing for clarity.

---

## Confidence summary

| ID | Issue | Severity | Confidence |
|----|-------|----------|------------|
| F1 | Forced-J gate semantically incorrect | HIGH | HIGH |
| F2 | Adversarial seeding still profitable | HIGH | HIGH |
| F3 | Natural-play FP rate ~20-25% | MED | HIGH |
| F4 | mem.played population sound | — | HIGH |
| F5 | Cross-round amplification fixed | — | HIGH |
| F6 | Game-boundary persistence no leak | — | HIGH |
| F7 | /reload persistence correct | — | HIGH |
| F8 | Single FP costs 15-25 raw pts | MED | MED |
| F9 | Same-trick double-play impossible | — | HIGH |
| F10 | Dead `jr` variable | COSMETIC | HIGH |

---

## Recommendations

### R1 — Replace forced-J approximation with hand-size check (HIGH priority).

The audit's original recommendation #2 was correct. The proper
gate is **"how many cards of this suit could this seat possibly
hold right now"**, computed from:
- Total cards of this suit in the deck (8).
- MINUS cards visible everywhere this round (current trick +
  completed tricks + this seat's own discards).

If the residual count attributable to THIS seat ≥ 2 (J + at
least one other), then bait inference is allowed; if ≤ 1, the
J was forced. This requires a deck-tracker pass at write time.
Cost: O(8) per fire, negligible.

If the deck-tracker is too heavy, an intermediate gate is:
**count ♠ played by ALL FOUR seats this round**. If total ♠
played < 7, opp could plausibly hold another ♠ besides J (8 - 7
= 1 remaining, J could be it but might not be). If ≥ 7, J was
forced. This is much cheaper and handles the common case where
the suit has been thoroughly played.

### R2 — Require `count >= 2` at read site to gate adversarial seeding (MED priority).

The current `count >= 1` threshold (Bot.lua:2018) means a single
fire (intentional or accidental) toggles full-round suit avoid.
Raising to `count >= 2` requires the adversary to deceptive-J
TWICE in the same round to trigger — meaningfully harder to
fabricate without paying real EV cost. Genuine baiters often
DO repeat, so coverage of true positives stays acceptable.

### R3 — Remove dead `jr` local (cosmetic).

Bot.lua:548 — drop the line.

### R4 — Add audit log line (LOW priority).

When `baitedSuit[X]` increments, log
`(round, trickNum, seat, suit, count)` to a debug ring buffer.
Lets future audits trace which fires were FP after the round
ends.

---

## Verdict

The v0.9.2 #46 patch achieves the **larger** of its two goals
(round-scoping eliminates cross-round amplification, the largest
strategic damage class). The **smaller** goal (forced-J
approximation) is implemented in a way that does not actually
solve the original audit's stated problem — it narrows the FP
class but introduces a new one and remains adversarially
exploitable in a single round.

Estimated residual exploit value to a skilled opp: **15-25 raw
points per round** by deliberate seeding of one low-card play
followed by a forced J-play in the same suit. Down from ~30+ raw
points per game pre-v0.9.2, but still material.

Recommend R1 (deck-tracker forced-J gate) for v0.10.x.
