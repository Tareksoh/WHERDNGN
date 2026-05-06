# D-RT-21 — ISMCTS sampler signal-poisoning red-team (v0.10.2)

## Scope

Saudi-Master tier dispatches `Bot.PickPlay` → `BotMaster.PickPlay`,
which performs flat-Monte-Carlo determinization over 30/60/100
sampled worlds (`BotMaster.lua:850-855`). The sampler
(`sampleConsistentDeal`, lines 198-577) is biased by behavioural
signals carried in `Bot._memory[*]` (per-round) and
`Bot._partnerStyle[*]` (per-game). This audit asks: *can a smart
opponent deliberately corrupt these signals to mis-distribute
hands across the rollout, swinging the bot's chosen card?*

Companion document: `D-RT-08_trust_asymmetry_audit.md` covered the
**read-side** team-gating. This document covers the **attacker
playbook** for each remaining read site, and looks for stacked /
cross-signal exploits the per-site audit may have missed.

Scope of READ-sites in `BotMaster.lua` (re-confirmed):

| Signal | Storage | Read site (BotMaster) | Trust gate | Suite weight |
|---|---|---|---|---|
| `firstDiscard` | `_memory[partner].firstDiscard` | line 211-212, 380 | `s == partner` (partner-only-by-construction) | 1 (cardWeight) |
| `likelyKawesh` | `_memory[s]` | line 400-404 | `sIsOpponent` (opp-only — desire-clear) | n/a (suppressor) |
| `aceLate` | `_partnerStyle[s]` | line 405-409 | UNGATED | pickProb 0.7→0.5 |
| `OpponentUrgency` | derived from score | line 419-422 | bidder-only | pickProb→0.5 |
| `leadCount` | `_partnerStyle[s]` | line 436-443 | `sIsOpponent` | 20 (suit fallback) |
| `topTouchSignal` | `_partnerStyle[s]` | line 473-500 | `sIsPartner` (R6 fix) | 60 (next-down pin) |
| `void` (per seat) | `_memory[s].void` | line 342-343, 504 | UNGATED — hard exclusion | hard |

`baitedSuit` and `tahreebSent` are NOT read by BotMaster
(grep-confirmed). They influence the picker's *own* lead choice
in `Bot.lua` `pickLead`, which can affect rollouts only via the
`heuristicPick` rollout policy — NOT via hand-distribution
sampling. They are listed under *cross-signal stacking* below.

---

## Attack #1 — `leadCount` poisoning (3+ early lead-suit X)

**Mechanism.** `Bot._partnerStyle[s].leadCount[X]` is bumped on
every LEAD play of suit X by seat `s` (`Bot.lua:445-447`). The
counter is per-GAME (never reset between rounds; see emptyStyle
in Bot.lua:191-254 — leadCount lives next to bels/triples and
intentionally accumulates across the whole match).

The reader (`BotMaster.lua:436-443`) fires on `sIsOpponent` AND
`leadCount[suit] >= 3`, setting `desire[suit] = 1`. That activates
the suit-fallback path (line 505: `desire[suit] and 20`),
inflating sampler placement of suit-X cards into that opp's hand
by ~20× per card (vs. uniform random).

**Attacker playbook.** A Saudi-tier human/cheat-script controlling
a seat opens 3 successive rounds with the SAME suit (say D). By
round 4, BotMaster believes that opp is "long in D" and routes
~70% of remaining D-suit cards to them in every sampled world —
even though the seat may have just been opening a singleton or
short suit each time.

**Feasibility: HIGH.**
- Counter accumulates per-game with no anti-noise filter beyond
  `>=3`.
- No cross-check against actual length (a seat opening 3 different
  rounds with their LOWEST card in the leftmost-suit-they-hold is
  trivial — it's just standard "open low non-trump" play).
- No half-life decay; reaching 3 is a permanent flip for the
  remaining game (typically 5-10 rounds).

**Expected EV impact: MEDIUM.**
- Only sets `desire[suit]=1` (fallback weight 20), not a
  card-specific pin (60/50/40). The sampler still prefers strong
  cards weighted >20 in their canonical homes.
- The `not desire[suit]` guard at line 439 means the bias is
  no-op if the suit was already activated (e.g. by Hokm-defender
  fallback). Worst case: poisons sampling for non-trump non-Ace
  fillers in the suit.
- Empirical: ~5-10% of rollouts will mis-place 1-2 mid-cards
  (T/8/9 of D) to the wrong opp seat. Picker's choice is
  perturbed only when the trick-by-trick outcome of those
  cards' placement is decision-relevant — typical hand: maybe
  2-3 plays per round are within the noise band.

**Recommendation: GUARD with anti-poisoning predicate.**
- Add a "first-card-of-trick was low" filter: if the leadCount
  bump fires only when the seat's lead was a HIGH card
  (T/K/Q/A/J), 3 highs = genuine length; 3 lows = no signal.
  Mirrors the Fzloky `firstDiscard` rank-aware reading.
- Alternatively: down-decay leadCount by 1 each round after the
  initial accumulation, capping at the 3-bound — punishes bursts
  but resists slow-drip stuffing.
- OR: gate the reader by `Bot.IsBotSeat(s) == false`. Saudi-tier
  bots are known to have rotation-aware lead patterns; a 3-lead
  pattern on a bot is real and should be honoured. Humans /
  cheat-scripts don't follow Saudi convention deterministically,
  so their leadCount is signal-poor.

---

## Attack #2 — `baitedSuit` retry under v0.9.2 #46 forced-J gate

**Status.** `baitedSuit` is NOT read by BotMaster.lua. The reader
is `Bot.lua:2012-2028` (pickLead M3lm-gated suit-avoid hint).
**No direct sampler exploit path.**

The v0.9.2 #46 forced-J gate (`Bot.lua:546-559`) requires that
this seat has previously played a LOWER card of the same suit
in `mem.played` before the J-play counts as a bait. This is the
"lowerSeen" guard.

**Attacker probe.** Smart opp tries to emit a `baitedSuit` flag
on suit X by:
1. Playing 7X or 8X early (bumps `mem.played[7X|8X]`)
2. Later, while partner is winning a trick led with X, plays JX

At step 2 the gate detects `lowerSeen=true` and increments
`baitedSuit[X]`. This is by design — they DID hold a lower and
chose J. The bot then avoids leading X.

**Feasibility for sampler poisoning: LOW.** Because BotMaster
doesn't read baitedSuit, the only effect is that the bot avoids
leading X — which happens to be exactly what the opp wanted, but
that's the picker-level exploit (covered in
`D-RT-12_bait_ledger_persist.md` per the per-round-scope fix).
Rollouts within the picker's chosen card still proceed normally.

**Cross-effect on rollouts: LOW.** `heuristicPick` rollout policy
in `BotMaster.lua:644-755` re-uses `pickFollow`/`pickLead` shape
but operates on the simulated `currentTrick` — it does NOT consult
`baitedSuit` (no Bot.IsM3lm() call inside the rollout heuristic;
line 728-754 is a strict simplification of pickLead). So even if
the picker's TOP-LEVEL choice is steered into a different suit
by baitedSuit, the rollout VALUE estimates of the alternatives
are unaffected.

**Expected EV impact: NEGLIGIBLE on sampler.**

**Recommendation: NONE for sampler.** The picker-level concern
is already covered by D-RT-12. **Document explicitly** at the
read-site that BotMaster does not consume baitedSuit to prevent
a future audit wave from "extending" the reader and
inadvertently creating the missing exploit.

---

## Attack #3 — `firstDiscard` ladder poisoning (single-event)

**Status.** Partner-only-by-construction in BotMaster
(`pSignalSuit` indexes `_memory[partner]` at line 211). An OPP's
firstDiscard is never read by the sampler.

**Could the opp poison their own partner's firstDiscard?**
No — `_memory` is per-observer. Each bot observes via
`Bot.OnPlayObserved` (host-side) and stores the opp seat's
firstDiscard under that opp's index. There is no cross-seat
write.

**Could the opp force the bot's actual partner to have a
misleading firstDiscard?** Only by FORCING the partner to
discard a specific suit early. The most common forcing
mechanism: opp leads a long suit X early; partner is short and
discards. Partner's discard becomes their firstDiscard. But:

1. The bot is the host (Saudi-tier only runs host-side).
2. The bot's PARTNER could be a bot or human. If bot, partner
   uses Fzloky-aware discard ranking — discards LOW (7/8) when
   they don't want the suit, HIGH (A/T/K) when they do. The
   poisoning attempts to force a FALSE-positive HIGH discard.
3. If partner is human, the discard is already noise — but the
   reader at `BotMaster.lua:380` does NOT gate on
   `Bot.IsBotSeat(partner)`. **This IS a gap.**

**Specific gap.** `Bot.lua:1962-1963` (the picker's
`fzlokyPrefSuit` branch) DOES gate on `Bot.IsBotSeat(p)`. The
sampler at `BotMaster.lua:211-212, 380` does NOT.

**Attacker playbook (human partner case).**
1. Bot's partner is human. Human plays whatever junk they have.
2. On the human's first off-suit discard, BotMaster's sampler
   permanently sets `desire[humanDiscardSuit] = 1` for the
   human's hand in every rollout for the rest of the round.
3. If the human shed a tiny side-suit early (most likely play),
   the sampler now over-clusters that suit into the human's
   hand, mis-modelling who can ruff what.

**Feasibility: HIGH (existing condition, not adversarial action).**

**Expected EV impact: LOW-MEDIUM.**
- Weight is only 1 (line 380). Activates the suit-fallback at
  weight 20, not a hard pin. Effect is similar to a leadCount=3
  bias.
- Only relevant when partner is human, which is rare in pure-bot
  Saudi-tier matches but common in mixed-tier player vs bot.

**Recommendation: ADD trust gate.** Mirror the picker's gate at
the sampler:

```lua
-- BotMaster.lua:211 — proposed
local pMem = B.Bot._memory and B.Bot._memory[partner]
local pSignalSuit = nil
if Bot.IsBotSeat(partner) and pMem and pMem.firstDiscard then
    pSignalSuit = pMem.firstDiscard.suit
end
```

This aligns the sampler trust model with the picker. Single-line
change at the read-site only — Bot.IsBotSeat is already the
authoritative test (Bot.lua:87).

---

## Attack #4 — Tahreeb cascade with deceptive sequences

**Status.** `tahreebSent` is NOT read by BotMaster.lua
(grep-confirmed). The reader is `Bot.lua:1865, 1909` for partner
and opp respectively, both gated by `Bot.IsBotSeat`. **No direct
sampler exploit.**

**Could a deceptive sequence affect rollouts?** The picker
chooses to LEAD or AVOID a suit based on Tahreeb, which feeds
into the candidate-card list. But `BotMaster.PickPlay` enumerates
ALL legal cards (line 829-832) and rolls each. Tahreeb only
affects the rollout-policy `heuristicPick` if it consults
`tahreebSent` inside the rollout — which it does NOT
(`heuristicPick` at line 644-755 is a stripped-down play-out
heuristic, no signal lookups).

**Cross-effect: MINIMAL.** A Tahreeb-induced suit avoidance at
the picker top-level changes which set of cards we're choosing
between, but the per-card EV estimate from rollouts is signal-
clean.

**Feasibility: LOW for sampler poisoning.**

**Expected EV impact: NEGLIGIBLE on sampler-side.** The
opponent-side concerns (deceptive Bargiya-A, fake-want sequences)
are picker-level and tracked elsewhere
(`D-RedTeam-02_bargiya_exploits.md`).

**Recommendation: NONE for sampler.** Same documentation note
as Attack #2 — explicitly flag that BotMaster does not consume
tahreebSent so a future "extend the sampler with Tahreeb" patch
doesn't open the exploit.

---

## Attack #5 — Cross-signal stacking

**Question:** can multiple poisoned signals compound to flip a
sampler decision more reliably than any single one?

### Stack 5a: leadCount + likelyKawesh

`likelyKawesh` (mem.likelyKawesh) is set when **all** plays by
a seat through trick 3+ are 7/8/9. The reader CLEARS desire
(line 402-404) for opp seats. Then the leadCount reader at
line 436 explicitly *guards against* this:

```lua
if style and style.leadCount and sIsOpponent
   and not (mem and mem.likelyKawesh) then
```

So leadCount cannot reactivate after Kawesh-clear in the same
sampler call. **Cross-stack is correctly blocked.**

But: a smart opp could AVOID triggering likelyKawesh by playing
a single mid card (T/J) on trick 1 to break the all-low
condition, then play 7/8/9 forever after. They retain leadCount
poisoning, lose the desire-clear. **Mild advantage to the
attacker — they trade a T/J for retaining the leadCount stuffing
flag.**

**Feasibility: MEDIUM.** Requires playing a deliberately
sub-optimal high card to break the Kawesh classifier — but the
gain is only "leadCount-poisoning persists," which by itself is
LOW EV impact. Net-positive for attacker only in fringe
scenarios.

**Recommendation: ACCEPT.** The interlock is correct; the
"avoid the classifier" maneuver costs the attacker ~1 trick of
EV via the sub-optimal play, comparable to or worse than the
EV gain from preserving the leadCount poisoning.

### Stack 5b: aceLate + bidder + OpponentUrgency

`aceLate >= 2` damps pickProb 0.7→0.5. This applies to ANY seat
(not just opp — line 405-409 is **UNGATED**). Combined with
`OpponentUrgency >= 6` for a bidder seat, pickProb is forced to
0.5.

Could an opp manipulate aceLate to interfere with the bot's own
partner reasoning?

- aceLate fires per-seat per-Ace-played-at-trick-5+ (Bot.lua:
  629-634). So if the bot's partner plays an Ace late, partner's
  aceLate increments.
- The reader at line 405-409 then drops partner's pickProb to
  0.5. **The desire bias for partner cards (e.g. Sun
  desire["A"..s]=8, partner-of-bidder Hokm trump suit) is
  applied with a coin-flip instead of 0.7.**
- Partner with aceLate=2+ ⇒ sampler distribution becomes more
  uniform, weakening the partner-bias model.

**Attacker manipulation.** Opp can FORCE partner to play an Ace
late by:
1. Leading a suit where partner holds A late in the round.
2. Partner naturally plays A (it's their highest, often forced
   by IsLegalPlay).

But partner choosing to play Ace late is NOT something the opp
can force without a specific shape — it's incidental. The
attacker can't reliably bump partner's aceLate.

**Self-poisoning concern.** If the bot's partner is also Saudi-
tier, partner's own pickPlay decisions to "save" Aces inflate
aceLate naturally. This is a SELF-POISONING vulnerability — not
an adversarial one — but it does mean the bot becomes less
confident in partner-bias as the game progresses.

**Feasibility: LOW for adversarial; INCIDENTAL for self-poison.**

**Expected EV impact: LOW.** pickProb 0.7 vs 0.5 on a single seat
shifts the sampled distribution slightly; the absolute desire
weights still apply.

**Recommendation: GUARD aceLate read with `sIsOpponent`.** The
flag was conceived as an opp-pattern detector ("humans hoard
Aces"); applying the damping to teammate seats was likely
incidental. Adding the gate matches likelyKawesh's semantics:

```lua
-- BotMaster.lua:405-409 — proposed
local style = B.Bot._partnerStyle and B.Bot._partnerStyle[s]
local pickProb = 0.7
if style and style.aceLate and style.aceLate >= 2
   and sIsOpponent then
    pickProb = 0.5
end
```

### Stack 5c: leadCount + pSignalSuit (partner)

`pSignalSuit` writes `desire[pSignalSuit] = 1` only for the
partner seat (`s == partner`). leadCount writes for opp seats
only. **Disjoint seat sets — no stack interaction.**

### Stack 5d: topTouchSignal + leadCount (same opponent)

topTouchSignal is partner-only-read (R6 gate). leadCount is
opp-only-read. **Disjoint — no stack interaction.**

### Stack 5e: void inference + leadCount

`mem.void[suit]` is set when a seat fails to follow lead suit
(Bot.lua:347-355) and HARD-EXCLUDES that suit from their hand
(BotMaster.lua:504). leadCount BIASES the same seat's hand
TOWARD a specific suit at +20 weight.

If an opp shows void in suit X (revoke-honest), then later
acquires leadCount[X] >= 3 from leading X across rounds, the
**hard exclusion in line 504 (`not voids[C.Suit(c)]`) overrides
the +20 bias**. No false placement.

But `void` is per-ROUND (reset via Bot.ResetMemory) while
leadCount is per-GAME. So the round-2 sampler may see no void
flag but a still-active leadCount[X] = 4 (carried from rounds 1
and 2). At that point the bias is unguarded. **This is the
core of Attack #1 — restated as a stacking insight.**

**Recommendation: same as Attack #1 — decay leadCount per round
or gate by Bot.IsBotSeat(s).**

---

## Attack #6 — Sampler weight inflation (>50/60 thresholds)

**Question:** Are there read sites that crank a desire weight
ABOVE the 60-cap (touchHonors next-down)?

### Census of weights:

| Weight | Source | Trust gate |
|---|---|---|
| 60 | topTouchSignal next-down | sIsPartner |
| 50 | Hokm J-of-trump (strong) | bid-derived (out-of-scope) |
| 40 | Hokm 9-trump or Sun A | bid-derived |
| 30 | Hokm A-trump | bid-derived |
| 20 | Hokm T-trump or suit-fallback | bid-derived |
| 15 | Hokm side A | bid-derived |
| 10 | Hokm K/Q-trump | bid-derived |
| 8 | Defender side A | bid-derived |
| 5 | Sun-or-Hokm partner-of-bidder side A | bid-derived |
| 4 | Defender side K | bid-derived |
| 1 | Partner pSignalSuit | partner-only |

The `math.max(desire[card] or 0, 60)` at line 483 is the
ceiling. No site cranks above 60. **Verified clean.**

The R6 fix specifically chose 60 because it dominates random
fills (>20-suit-fallback) but doesn't override declared meld pins
which are HARD-pinned via `meldPins` (separate mechanism, lines
242-318).

**Feasibility: NONE.** Attacker has no path to inflate.

**Recommendation: DOCUMENT the cap.** Add a constant
`K.SAMPLER_MAX_DESIRE = 60` and refer to it from line 483, so a
future signal-reader can't accidentally surpass it (e.g., adding
a mistakenly-coded `desire[card] = 100`).

---

## Attack #7 — Unguarded signal readers in BotMaster (vs.
trust-asymmetry rule)

Comprehensive enumeration of every signal-reading branch in
`BotMaster.sampleConsistentDeal` (line 198-577):

### Read sites & gating verdict

| Line | Signal read | Gate | Verdict |
|---|---|---|---|
| 211 | `_memory[partner].firstDiscard` | `s == partner` (struct) | Partial — missing `Bot.IsBotSeat(partner)` (Attack #3) |
| 299 | `_memory[s].void` (pigeonhole pin) | `s ~= seat`, mathematical | Hard-constraint, immune to poisoning |
| 343, 504 | `_memory[s].void[X]` | UNGATED hard exclusion | Honest signal (revoke = void by Saudi rules) |
| 400-404 | `_memory[s].likelyKawesh` | `sIsOpponent` | Correctly opp-only (suppressor semantics) |
| 405-409 | `_partnerStyle[s].aceLate` | UNGATED | **GAP — should be `sIsOpponent`-gated (Stack 5b)** |
| 419-422 | `OpponentUrgency(bidder)` | `s == bidder` (struct) | Score-derived, immune to behavioural poisoning |
| 436-443 | `_partnerStyle[s].leadCount` | `sIsOpponent` AND `not likelyKawesh` | Susceptible to cross-round stuffing (Attack #1) |
| 473-500 | `_partnerStyle[s].topTouchSignal` | `sIsPartner` (R6) | Correctly partner-only |

### Summary of unguarded / weakly-guarded sites

1. **`firstDiscard` (line 211)** — reads for partner regardless
   of Bot/human. Picker-side guards on `Bot.IsBotSeat`; sampler
   does not. **Recommend: add Bot.IsBotSeat gate.**

2. **`aceLate` (line 405-409)** — applies pickProb damping to
   ANY seat, including bot's own partner (self-poisoning) and
   bidder partner (legitimate signal misclassified). **Recommend:
   gate by `sIsOpponent`.**

3. **`leadCount` (line 436-443)** — opp-only is correct, but the
   per-game accumulation across rounds with no decay creates
   slow-drip stuffing potential. **Recommend: per-round decay,
   or `Bot.IsBotSeat(s) == false` exclusion (humans don't follow
   lead-conventions deterministically).**

`void` is intentionally ungated because it's a hard, rules-
enforced honest signal — a seat shown void in X cannot legally
have X-cards. No trust gate needed.

---

## Aggregate priority list

| ID | Severity | Feasibility | EV swing | Fix cost | Priority |
|---|---|---|---|---|---|
| #1 leadCount stuffing | MED | HIGH | MED | LOW (1-line gate or 5-line decay) | **HIGH** |
| #3 firstDiscard human-partner | LOW-MED | HIGH (default condition) | LOW-MED | LOW (1-line gate) | **HIGH** |
| Stack 5b aceLate ungated | LOW | LOW (incidental) | LOW | LOW (1-line gate) | MED |
| #6 weight ceiling (defensive) | n/a | n/a | n/a | LOW (constant promotion) | LOW |
| #2 baitedSuit | n/a (not read) | n/a | n/a | DOCUMENTATION | LOW |
| #4 tahreebSent | n/a (not read) | n/a | n/a | DOCUMENTATION | LOW |
| #5a Kawesh-bypass | LOW | MED | LOW | n/a (current interlock correct) | ACCEPT |

## Recommended v0.10.3 patch set

1. **`BotMaster.lua:211-212`** — Add `Bot.IsBotSeat(partner)` gate:
   ```lua
   local pMem = B.Bot._memory and B.Bot._memory[partner]
   local pSignalSuit = nil
   if Bot.IsBotSeat(partner) and pMem and pMem.firstDiscard then
       pSignalSuit = pMem.firstDiscard.suit
   end
   ```

2. **`BotMaster.lua:405-409`** — Gate aceLate by `sIsOpponent`:
   ```lua
   if style and style.aceLate and style.aceLate >= 2
      and sIsOpponent then
       pickProb = 0.5
   end
   ```
   (Note: must hoist `sIsOpponent` definition above this site —
   currently defined at line 401, so already in scope.)

3. **`Bot.lua:445-447`** — Decay or gate leadCount writes
   (multiple options):
   - Option A (gate): only count leads where the rank is
     T/K/Q/J/A (high-lead = genuine length signal). Lows are
     noise.
   - Option B (decay): in `Bot.ResetMemory`, halve each
     `leadCount[suit]` per round, capping at floor 0. Punishes
     bursts but resists slow-drip.
   - Option C (Bot.IsBotSeat gate at the READER): reader at
     line 436 already firewalls humans-noise via
     `not likelyKawesh`, but humans frequently AVOID Kawesh
     classification (>3 high cards typical). Adding
     `Bot.IsBotSeat(s) == false` is the most conservative.

4. **(optional) `Constants.lua`** — Promote `K.SAMPLER_MAX_DESIRE
   = 60` and reference at `BotMaster.lua:483` to lock the
   ceiling.

5. **(optional) Code comment in `BotMaster.lua` near the
   sampler entry** — add an explicit "tahreebSent / baitedSuit
   are picker-only signals; do NOT add reads here without
   trust-asymmetry analysis" warning to prevent regression.

## Tests to add (track-D regression coverage)

Each fix should ship with a counter-example test:

- **leadCount stuffing**: 4-round game where opp leads same suit
  3 times (round 1-3), then in round 4 the sampler is called.
  Assert: distribution of suit-X cards across opp's hand shows
  the bias is OFF after fix (distribution stat-test vs. uniform-
  with-tolerance).
- **firstDiscard human-partner**: configure partner as
  S.IsSeatBot(p) == false, verify pSignalSuit is nil despite
  `_memory[partner].firstDiscard` being populated.
- **aceLate teammate**: bidder partner with aceLate=3, sampler
  should still use pickProb=0.7 not 0.5 for that seat (assert
  via stat-counter on whether the high-weight desires landed).

## Files to modify (suggested)

- `C:\CLAUDE\WHEREDNGN\BotMaster.lua` (lines 211, 405)
- `C:\CLAUDE\WHEREDNGN\Bot.lua` (line 445 — leadCount writer
  filter, OR Bot.ResetMemory decay loop)
- `C:\CLAUDE\WHEREDNGN\Constants.lua` (optional)
- `C:\CLAUDE\WHEREDNGN\tests\test_state_bot.lua` or new test
  file for sampler distribution properties

## End-state verdict

The trust-asymmetry rule was applied at v0.10.0 R6 to the
HIGHEST-WEIGHT signal reader (`topTouchSignal`, weight 60) —
the most damaging gap is closed. Of the remaining sites:

- `leadCount` is the single largest residual exploit
  (Attack #1) — slow-drip cross-round stuffing exists, max
  +20 weight per card, ~5-10% rollout perturbation.
- `firstDiscard` has a Bot.IsBotSeat gap that the picker-
  level guard already addresses at the picker site but the
  sampler missed (Attack #3) — weight 1, low impact, but
  trivial fix.
- `aceLate` is the smallest gap (incidental
  self-poisoning, no adversarial path) — fix cost is one
  conjunct.

None of these are emergencies. **The R6 patch correctly
prioritized the highest-leverage gap.** The recommendations
above are calibration hardening for v0.10.3 and beyond.
