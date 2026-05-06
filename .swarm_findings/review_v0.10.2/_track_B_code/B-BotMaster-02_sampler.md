# B-BotMaster-02 — `BotMaster.sampleConsistentDeal` deep audit

**Scope:** `C:\CLAUDE\WHEREDNGN\BotMaster.lua` lines 196-577
(`sampleConsistentDeal` only). Audit cross-references
`D-RT-08_trust_asymmetry_audit.md` and `D-RT-21_ismcts_poisoning.md`.

**Method:** Walk the function top-to-bottom. For each constraint
or signal-reading branch, record what it does, whether it
honours the trust-asymmetry rule (video #05 @ 03:17-03:22),
and whether any cross-signal interaction lets an opp poison
the rollout distribution.

---

## Function shape (orientation)

```lua
local function sampleConsistentDeal(seat, unseen)
    -- 1. Bid-derived desire maps (strong / defenderDesire /
    --    partnerDesire / pSignalSuit).
    -- 2. Per-seat `sizes[s]` — remaining hand sizes.
    -- 3. Pin construction: pinCard (bid card) + meldPins
    --    (declared melds + Hokm J/9 + pigeonhole-trump).
    -- 4. Up to 15 attempts of:
    --    a. Build a shuffled `pool` from unseen \ pins.
    --    b. For each non-self seat, build hand via:
    --       * Pre-place pinCard + own meldPins.
    --       * Phase 1: weighted desire-pick from pool
    --         (pickProb gate, void filter).
    --       * Phase 2: residual void-respecting random fill.
    --    c. If any seat couldn't fill its slots → retry.
    -- 5. Fallback: random deal honouring meldPins/pinCard but
    --    NOT voids (last-resort).
end
```

The audit walks each numbered subsystem.

---

## F1 — Per-seat hand sampling (excludes played, excludes voids, respects melds)

**Severity:** OK (correct).

**Repro:** Read lines 320-535. Hands are constructed only over
`pool` derived from `unseen` (which excludes `seen` from the
caller — already-played cards). Voids are honoured at line 504
in Phase 1 and at line 523 in Phase 2 via
`not voids[C.Suit(c)]`. Declared melds are pre-placed at line
347-349 from `meldPins` so the declarer's hand is seeded with
the meld cards before random fill. Attempt loop (`maxAttempts =
15`) re-rolls if any seat fails to fill `n` cards.

**Quote:**

```lua
local pool = {}
for _, c in ipairs(unseen) do
    if c ~= pinCard and not meldPins[c] then
        pool[#pool + 1] = c
    end
end
shuffle(pool)
...
-- Phase 1: Biased pick from pool.
for _, c in ipairs(pool) do
    if #hand < n and not used[c] and not voids[C.Suit(c)] then
        local weight = desire[c] or (desire[C.Suit(c)] and 20) or 0
        if weight > 0 and math.random() < pickProb then
            hand[#hand + 1] = c
            used[c] = true
        else
            remainingInPool[#remainingInPool + 1] = c
        end
    else
        remainingInPool[#remainingInPool + 1] = c
    end
end
pool = remainingInPool

-- Phase 2: Fill remaining slots for this seat.
local leftovers = {}
for _, c in ipairs(pool) do
    if #hand < n and not used[c] and not voids[C.Suit(c)] then
        hand[#hand + 1] = c
        used[c] = true
    else
        leftovers[#leftovers + 1] = c
    end
end
if #hand < n then ok = false; break end
```

**Verdict:** Correct exclusion semantics in the primary path.

---

## F2 — Bid-card pin (sampler must put bid card in bidder's hand)

**Severity:** OK (correct).

**Repro:** Lines 219-228. If contract has a `bidCard` and the
bidder is not the calling seat, `pinSeat = bidder, pinCard =
S.s.bidCard`. The bidCard is excluded from the `pool` at line
324 and pre-placed in the bidder's hand at line 345. The
`used[]` map is seeded with `pinCard` at line 333 so no other
seat can pick it.

**Quote:**

```lua
local pinSeat, pinCard = nil, nil
if contract and bidder and bidder ~= seat and S.s.bidCard then
    for _, c in ipairs(unseen) do
        if c == S.s.bidCard then
            pinSeat = bidder
            pinCard = S.s.bidCard
            break
        end
    end
end
...
if s == pinSeat and pinCard then hand[#hand + 1] = pinCard end
```

**Edge:** if the bidCard has already been played, it's not in
`unseen` and the loop at 221 won't match — `pinCard` stays
nil. Correct: a played card doesn't need pinning.

**Verdict:** Correct.

---

## F3 — Meld pin (declared melds force cards into team's pile)

**Severity:** OK (correct).

**Repro:** Lines 230-260 build the `meldPins` map from
`S.s.meldsByTeam`. Each card in a declared meld with a known
`m.declaredBy` is mapped `card -> declarerSeat`, *only if* that
card is still in the unseen pool (skipped if already played or
in the bot's own hand). Lines 271-318 add Hokm-specific pins:
J and 9 of trump pin to bidder (H-1 fix), and pigeonhole-trump
pins all unseen trumps to the single trump-eligible non-self
seat when only one such seat exists. The fallback path
(549-575) also respects meldPins (the v0.9.0 H-6 regression
fix).

**Quote (meld map construction):**

```lua
local meldPins = {}
if S.s.meldsByTeam then
    for _, team in ipairs({ "A", "B" }) do
        for _, m in ipairs(S.s.meldsByTeam[team] or {}) do
            if m.declaredBy and m.declaredBy ~= seat
               and m.cards then
                for _, c in ipairs(m.cards) do
                    -- Only pin if still in unseen pool (not played).
                    for _, u in ipairs(unseen) do
                        if u == c then
                            meldPins[c] = m.declaredBy
                            break
                        end
                    end
                end
            end
        end
    end
end
```

**Quote (per-seat application):**

```lua
-- Pre-place this seat's declared meld cards.
for c, declarerSeat in pairs(meldPins) do
    if declarerSeat == s then hand[#hand + 1] = c end
end
```

**Quote (fallback path includes meld pins):**

```lua
-- Fallback: uniform random deal ignoring voids.
local pool = {}
for _, c in ipairs(unseen) do
    if c ~= pinCard and not meldPins[c] then
        pool[#pool + 1] = c
    end
end
...
if s == pinSeat and pinCard then hand[#hand + 1] = pinCard end
-- Pre-place this seat's declared meld cards.
for c, declarerSeat in pairs(meldPins) do
    if declarerSeat == s then hand[#hand + 1] = c end
end
```

**Verdict:** Correct in both primary and fallback paths.

---

## F4 — Fzloky `firstDiscard` signal-suit bias (lines 211, 380)

**Severity:** LOW-MEDIUM gap (D-RT-21 Attack #3).

**Repro:** The sampler reads partner's `firstDiscard.suit` at
line 212 and writes `desire[pSignalSuit] = 1` at line 380 when
the seat being filled is the bot's partner (`s == partner`).
The team-gate `s == partner` is correct (partner-only by
construction), but **there is no `Bot.IsBotSeat(partner)`
gate** — if the partner is a HUMAN, their incidental low-junk
discard ends up biasing the sampler as if it were a Fzloky
signal.

The picker-side reader at `Bot.lua:1962-1963` (the
`fzlokyPrefSuit` branch) DOES gate on `Bot.IsBotSeat(p)`. The
sampler-side reader does not. Asymmetric trust between picker
and sampler for the same signal.

**Quote:**

```lua
-- BotMaster.lua:210-212
local partner = R.Partner(seat)
local pMem = B.Bot._memory and B.Bot._memory[partner]
local pSignalSuit = pMem and pMem.firstDiscard and pMem.firstDiscard.suit
...
-- BotMaster.lua:380 (inside per-seat loop, gated by `s == partner`)
if s == partner and pSignalSuit then desire[pSignalSuit] = 1 end
```

**Exploit path.** Mixed-tier game with bot's partner as a human:
1. Human plays whatever junk they have on their first off-suit
   discard. (Most likely: tiny side-suit shed early.)
2. From that play onward, BotMaster sampler permanently sets
   `desire[humanDiscardSuit] = 1` for the partner's hand in
   every rollout for the rest of the round.
3. Sampler over-clusters that suit into the human's hand,
   mis-modelling who can ruff what.

The same exploit applies if a human partner is adversarial /
manipulative, but the more common case is incidental signal
noise from non-bot teammates.

**Weight: 1 (activates the suit-fallback path at weight 20 per
card).** Effect comparable to a leadCount=3 bias. Not a hard
pin.

**Verdict:** GAP. Fix is a 1-line gate per D-RT-21
recommendation #1.

---

## F5 — `void` hard exclusion (lines 343, 504)

**Severity:** OK (correct, intentionally symmetric).

**Repro:** `voids` is read from `B.Bot._memory[s].void` at line
342-343 for each non-self seat. The check `not
voids[C.Suit(c)]` is enforced in BOTH Phase 1 (line 504) and
Phase 2 (line 523) of hand-fill. Cards of a suit the seat is
known void in cannot be placed there.

The void signal is structurally honest: by Saudi rules a seat
that fails to follow lead suit IS void in that suit (modulo
the v0.5.6 trump-ruff `firstDiscard` rollback — handled
elsewhere). No deception possible. Symmetric application
(partner AND opp) is correct.

**Quote:**

```lua
-- BotMaster.lua:342-343 (per-seat preamble)
local voids = (B.Bot._memory and B.Bot._memory[s]
               and B.Bot._memory[s].void) or {}
...
-- BotMaster.lua:504 (Phase 1)
if #hand < n and not used[c] and not voids[C.Suit(c)] then
...
-- BotMaster.lua:523 (Phase 2)
if #hand < n and not used[c] and not voids[C.Suit(c)] then
```

**Caveat:** the FALLBACK path (lines 549-575) intentionally
ignores voids — it's the "give up on constraints" path. The
v0.9.0 H-6 fix correctly preserves meldPins in fallback but
voids are documented-known-skipped.

**Verdict:** Correct. Hard-truth signal, ungated read is by
design.

---

## F6 — `likelyKawesh` suppressor gate (lines 400-404)

**Severity:** OK (correct; defensive direction).

**Repro:** The reader is gated on `sIsOpponent` (opp-only),
which is the inverse direction of the topTouchSignal pattern
but still trust-asymmetric: the action is to CLEAR the desire
map (defensive — removes positive bias rather than adding
one) for opps observed playing only 7/8/9 in tricks 1-3. The
50-agent audit fix at lines 393-399 explicitly excluded
PARTNER from this clear because a teammate playing low may be
conserving (Fzloky low-discard) rather than truly broke.

**Quote:**

```lua
local mem = B.Bot._memory and B.Bot._memory[s]
local sIsOpponent = R.TeamOf(s) ~= R.TeamOf(seat)
if mem and mem.likelyKawesh and sIsOpponent then
    desire = {}
end
```

**Vulnerability check.** Could an opp deliberately trigger
`likelyKawesh` to flip their own `desire` to `{}` and
under-pin J/9 of trump in their hand? Yes — but the result is
*wider sampling uncertainty*, not a wrong-pin (the bidder's
J/9 are still hard-pinned via the H-1 / pigeonhole pins at
line 271-318, regardless of this clear). Outcome bound is
"rollout noise increase," not "mis-routing." Acceptable.

**Verdict:** Correct. Defensive desire-clear is the right
direction.

---

## F7 — `aceLate` UNGATED at lines 405-409 (D-RT-21 Stack 5b)

**Severity:** LOW gap (incidental self-poisoning, no clear
adversarial path; defensive damping direction makes this less
urgent than F4 / F9).

**Repro:** The reader applies `pickProb = 0.5` damping for any
seat with `style.aceLate >= 2`, **regardless of whether the
seat is partner or opponent**. This is inconsistent with the
trust-asymmetry rule established at v0.10.0 R6, and creates a
self-poisoning vulnerability: when the bot's own partner plays
Aces late (legitimate Saudi-tier behaviour — saving Aces is a
documented strategy), partner's `aceLate` increments, then the
sampler weakens its partner-bias model for that seat.

**Quote:**

```lua
local style = B.Bot._partnerStyle and B.Bot._partnerStyle[s]
local pickProb = 0.7
if style and style.aceLate and style.aceLate >= 2 then
    pickProb = 0.5  -- A-hoarder: less reliable strong-bias
end
```

**Asymmetry direction.** The damping direction is *defensive*
(broadens the sampled distribution), so the trust-violation
severity is weaker than a positive-bias case (where opp could
inflate desire). Specifically:

* For an OPP, inflating `aceLate` causes the sampler to be less
  confident the opp holds Aces → bot might LEAD an opp Ace's
  suit thinking opp is short → opp wins. Mild adversarial
  benefit.
* For PARTNER, partner's natural late-Ace play (no manipulation
  needed) damps the bidder's-partner trump-count bias and the
  Sun A-pinning bias. Self-poisoning.

**Specific exploit (instruction #7):** No clear adversarial
exploit — the WRITER fires for any seat playing late Aces,
regardless of team. To "force" partner aceLate, an opp would
need to lead a suit where partner happens to hold A and play
it late, which the opp can't reliably engineer (they'd need
to know partner's hand shape).

But the GAP is real: D-RT-21 recommends gating on
`sIsOpponent`. The conjunct is already-defined at line 401
(it's in scope here) — a 1-line addition would close the gap.

**Verdict:** GAP. Fix per D-RT-21 #2: add `and sIsOpponent`
conjunct.

---

## F8 — OpponentUrgency bidder-only damping (lines 419-422)

**Severity:** OK (correct, score-derived).

**Repro:** When the seat being filled IS the contract bidder,
and `B.Bot.OpponentUrgency(bidder) >= 6`, pickProb is forced
down to `min(pickProb, 0.5)`. The intuition (B-95): a desperate
bidder on a team far behind us may have bid weaker than
threshold (Hail-Mary pattern); damp the strong-card bias to
widen the sampled distribution.

The gate is structurally `s == bidder` — there's no
behavioural-signal dependency, so no poisoning path. The
`OpponentUrgency` value derives purely from score state.

**Quote:**

```lua
if s == bidder and B.Bot.OpponentUrgency
   and B.Bot.OpponentUrgency(bidder) >= 6 then
    pickProb = math.min(pickProb, 0.5)
end
```

**Verdict:** Correct. Score-derived signal, no behavioural
poisoning surface.

---

## F9 — `leadCount` slow-drip stuffing (lines 436-443) — D-RT-21 Attack #1

**Severity:** MEDIUM gap (highest-priority sampler issue per
D-RT-21).

**Repro:** The reader fires for opp seats (`sIsOpponent`)
where `style.leadCount[suit] >= 3`, and writes `desire[suit] =
1`. This activates the suit-fallback path (line 505 `desire[
C.Suit(c)] and 20`), inflating the placement of suit-X cards
into that opp's hand by ~20× per card vs. uniform random.

**Quote:**

```lua
-- BotMaster.lua:436-443
if style and style.leadCount and sIsOpponent
   and not (mem and mem.likelyKawesh) then
    for suit, count in pairs(style.leadCount) do
        if count >= 3 and not desire[suit] then
            desire[suit] = 1
        end
    end
end
```

**Critical write-side fact:** `_partnerStyle` is **per-game**
(comment in `Bot.lua:209`: "across the GAME, not the round").
The `leadCount` counter ACCUMULATES across rounds with NO
DECAY. Once a seat has led suit X three times during a game,
the bias persists for the remainder of the match (typically
5-10 rounds).

**Exploit path.** Concrete attack scenario (Hokm, opp seat 2):
1. Game-level: opp seat 2 leads suit C three times across
   rounds 1-3 (as the opener of any trick). This is trivial —
   "open low non-trump" is standard play, so an attacker can
   do it without any sub-optimal sacrifice.
2. `style.leadCount.C = 3` is now active.
3. From round 4 onward, the sampler sets `desire["C"] = 1`
   for opp seat 2 every call. ~70% of sampled worlds
   over-cluster Clubs into seat 2's hand.
4. Bot's `pickLead` heuristics (M3lm tier, Bot.lua) AVOID
   leading suits where opps are believed long (over-trump
   risk). So bot avoids leading Clubs.
5. Reality: opp seat 2 may not hold long Clubs anymore —
   they're saving a strong Club holding for a coup. The bot
   never leads Clubs, so opp's long Clubs never get drawn
   out.

**Feasibility: HIGH.** No anti-noise filter beyond `>= 3`.
No half-life decay. No high-vs-low rank check (an opp leading
their LOWEST card three times still bumps the counter). No
`Bot.IsBotSeat(s) == false` filter — humans / cheat-scripts
who don't follow Saudi convention deterministically still
poison.

**Mitigation already partially present:** `not (mem and
mem.likelyKawesh)` provides a partial escape — if the opp is
also playing low cards, the bias is suppressed. But a
sophisticated opp can avoid the Kawesh trigger (play a single
T/J early to break the all-low condition, then 7/8/9 forever
after — D-RT-21 Stack 5a). They retain `leadCount`
poisoning, lose the desire-clear.

**Cross-stack with void (D-RT-21 Stack 5e):** `void` is
per-ROUND (reset each round) while `leadCount` is per-GAME.
Round 2 onward, the sampler may see no void flag but a
still-active leadCount stuffing bias. Hard exclusion of void
defends against false placement only when a void is
currently observed; it doesn't help the next round.

**Verdict:** GAP. Per D-RT-21 #3: gate by `Bot.IsBotSeat(s)
== false`, OR add per-round decay, OR raise activation
threshold significantly. Slow-drip exploit is real.

---

## F10 — `firstDiscard` human-partner pollution (instruction #10)

**Severity:** LOW-MEDIUM (same finding as F4; restated for
trust-asymmetry framing).

**Repro:** As noted in F4, the sampler reads
`B.Bot._memory[partner].firstDiscard` without a
`Bot.IsBotSeat(partner)` gate. Picker-side guards on
`Bot.IsBotSeat(p)` at `Bot.lua:1962-1963`; sampler does not.

**Asymmetric trust.** The picker has correctly identified that
a non-bot partner does not honour Fzloky discard conventions,
so the picker's `fzlokyPrefSuit` branch is gated. The sampler
does not gate, so it consumes the same untrusted input.

This is the cleanest 1-line fix in the audit. Per D-RT-21 #1:

```lua
-- BotMaster.lua:211-212 — proposed
local pMem = B.Bot._memory and B.Bot._memory[partner]
local pSignalSuit = nil
if Bot.IsBotSeat(partner) and pMem and pMem.firstDiscard then
    pSignalSuit = pMem.firstDiscard.suit
end
```

**Quote (current):**

```lua
local partner = R.Partner(seat)
local pMem = B.Bot._memory and B.Bot._memory[partner]
local pSignalSuit = pMem and pMem.firstDiscard and pMem.firstDiscard.suit
```

**Verdict:** GAP. Fix cost ≈ 3 lines.

---

## F11 — R6 `topTouchSignal` `sIsPartner` gate (lines 473-500)

**Severity:** OK (correct, v0.10.0 R6 fix).

**Repro:** The reader at line 473-500 is gated on
`sIsPartner` (`s == R.Partner(seat)`). For a partner seat
with `topTouchSignal[suit]`:

* `entry.nextDown` → `desire[card] = math.max(desire[card] or
  0, 60)`. HARD-pin via 60 weight (max sampler weight in the
  function — see F12).
* `entry.cleared` → `desire[rk .. suit] = nil`. Negative-bias.
* `entry.broke` → clear high desires for that suit. Negative-
  bias.

The R6 fix correctly aligns this reader with the trust-
asymmetry rule (video #05 @ 03:17-03:22): trust partner
signals at face value, discount opponent signals. The
reader's docblock at lines 451-470 cites the rule.

**Quote:**

```lua
local sIsPartner = (s == R.Partner(seat))
if sIsPartner and style and style.topTouchSignal then
    for suit, entry in pairs(style.topTouchSignal) do
        if entry.nextDown then
            local card = entry.nextDown .. suit
            desire[card] = math.max(desire[card] or 0, 60)
        end
        if entry.cleared then
            for _, rk in ipairs(entry.cleared) do
                desire[rk .. suit] = nil
            end
        end
        if entry.broke then
            for _, hi in ipairs({ "A", "T", "K", "Q", "J" }) do
                desire[hi .. suit] = nil
            end
        end
    end
end
```

**Verdict:** Correct (post-R6). Documented forward-compat
concern (per D-RT-08-C): the WRITE site at `Bot.lua:476-508`
is still symmetric — it records opp-context observations into
the ledger; only the READ site filters them. Any future
reader of `style.topTouchSignal` MUST replicate the
`sIsPartner` gate or risk re-introducing the v0.10.0 R6
vulnerability. Not a current bug.

---

## F12 — Sampler weight inflation (60-cap via math.max at line 483)

**Severity:** OK (cap is the maximum across the function).

**Repro:** The `math.max(desire[card] or 0, 60)` at line 483
is the highest desire weight assignment in
`sampleConsistentDeal`. D-RT-21 Attack #6 enumerates every
weight site:

| Weight | Source | Trust gate |
|---|---|---|
| 60 | topTouchSignal next-down | sIsPartner |
| 50 | Hokm J-of-trump (strong, getStrongCards) | bid-derived |
| 40 | Hokm 9-trump or Sun A | bid-derived |
| 30 | Hokm A-trump | bid-derived |
| 20 | Hokm T-trump or suit-fallback (line 505) | bid-derived |
| 15 | Hokm side A | bid-derived |
| 10 | Hokm K/Q-trump | bid-derived |
| 8 | Defender side A | bid-derived |
| 5 | Sun-or-Hokm partner-of-bidder side A | bid-derived |
| 4 | Defender side K | bid-derived |
| 1 | Partner pSignalSuit | partner-only |

No site cranks above 60. The `math.max` ensures that even if
a `cleared`/`broke`/`nextDown` interaction tried to lower it,
the 60 floor wins — matching the R6 design choice (60
dominates random fills via 20-suit-fallback but doesn't
override declared meld pins, which use the separate
`meldPins` HARD mechanism).

**Quote:**

```lua
desire[card] = math.max(desire[card] or 0, 60)
```

**Verdict:** Correct. Verified ceiling, no inflation path.
D-RT-21 #6 recommends promoting the 60 to a named constant
`K.SAMPLER_MAX_DESIRE` to lock the ceiling against future
regressions; this is a defensive recommendation, not a
current bug.

---

## F13 — Sampler termination, rejection sampling, fallback to random

**Severity:** OK (terminates; fallback documented).

**Repro:** The primary loop has `maxAttempts = 15` (line
320). On each attempt, if any non-self seat fails to reach
its target hand size `n` (line 530 `if #hand < n then ok =
false; break end`), the attempt is abandoned and the next
attempt re-shuffles the pool. If all 15 attempts fail, the
function falls through to the random-fallback path at
line 549.

**Quote (primary loop / rejection):**

```lua
local maxAttempts = 15
for attempt = 1, maxAttempts do
    local pool = {}
    ...
    shuffle(pool)
    local deal = {}
    local ok = true
    ...
    for s = 1, 4 do
        ...
        if #hand < n then ok = false; break end
        deal[s] = hand
        pool = leftovers
    end
    if ok then return deal end
end
```

**Quote (fallback path):**

```lua
-- Fallback: uniform random deal ignoring voids.
local pool = {}
for _, c in ipairs(unseen) do
    if c ~= pinCard and not meldPins[c] then
        pool[#pool + 1] = c
    end
end
shuffle(pool)
local deal = {}
local idx = 1
for s = 1, 4 do
    if s == seat then
        deal[s] = (S.s.hostHands and S.s.hostHands[s]) or {}
    else
        local n = seatHandSize(s)
        local hand = {}
        if s == pinSeat and pinCard then hand[#hand + 1] = pinCard end
        for c, declarerSeat in pairs(meldPins) do
            if declarerSeat == s then hand[#hand + 1] = c end
        end
        while #hand < n and idx <= #pool do
            hand[#hand + 1] = pool[idx]
            idx = idx + 1
        end
        deal[s] = hand
    end
end
return deal
```

**Termination guarantees:**

* Primary loop is bounded by `maxAttempts = 15` and a
  finite-cardinality pool (≤ 24 unseen cards). Worst-case
  work per attempt is O(24 × 3 seats) ≈ 72 inner ops.
* Fallback path is O(#pool × 3 seats) with no rejection /
  retry. Always terminates.
* Both paths return a valid `deal` table (one entry per
  seat, including own hand from `S.s.hostHands[seat]` at
  line 339 / 560).

**Note on fallback:** The fallback explicitly DOES NOT
respect voids (per the documented "give up on constraints"
contract). The v0.9.0 H-6 regression fix correctly
preserves `meldPins` AND `pinCard` (lines 564, 566-568), so
declared meld cards and the bid card cannot be misplaced.

**Edge case:** If `#hand < n` after fallback's `while` loop
(pool exhausted before slot fill), the seat returns a
short hand. This shouldn't happen if `unseen` cardinality
matches `Σ sizes[s]`, but no defensive check. In practice,
the caller (`PickPlay`) builds `unseen` from played-cards
exclusion, so cardinality should match. Not a current bug,
but the absence of a final-size assertion is a low-priority
robustness concern.

**Verdict:** Correct termination. Fallback's void-skip is
documented and intentional.

---

## Findings table

| ID  | Severity     | Site                  | Issue                                                               |
|-----|--------------|-----------------------|---------------------------------------------------------------------|
| F1  | OK           | 320-535               | Per-seat sampling correct (excludes played, voids, melds)           |
| F2  | OK           | 219-228, 333, 345     | Bid-card pin correct                                                |
| F3  | OK           | 230-318, 549-575      | Meld pins correct in primary AND fallback                           |
| F4  | LOW-MEDIUM   | 211-212, 380          | `firstDiscard` no `Bot.IsBotSeat(partner)` gate                     |
| F5  | OK           | 342-343, 504, 523     | Void hard-exclusion correct (structurally honest signal)            |
| F6  | OK           | 400-404               | `likelyKawesh` opp-only desire-clear correct (defensive)            |
| F7  | LOW          | 405-409               | `aceLate` UNGATED — should be `sIsOpponent`-gated                   |
| F8  | OK           | 419-422               | OpponentUrgency bidder-only correct (score-derived)                 |
| F9  | **MEDIUM**   | 436-443               | `leadCount` slow-drip stuffing — per-game counter, no decay         |
| F10 | LOW-MEDIUM   | 211-212, 380          | (Same as F4, framed as trust-asymmetry violation)                   |
| F11 | OK           | 473-500               | R6 `topTouchSignal` `sIsPartner` gate correct (post v0.10.0)        |
| F12 | OK           | 483 + weight census   | 60-cap is the maximum; no inflation paths                           |
| F13 | OK           | 320, 530, 549-575     | Termination bounded; fallback documented                            |

---

## Per-finding severity quick-reference

* **MEDIUM (1):** F9 — `leadCount` per-game stuffing. Real
  multi-round exploit; weight 20 per card; ~5-10% rollout
  perturbation per D-RT-21 estimates. Highest-priority
  sampler issue.
* **LOW-MEDIUM (2):** F4, F10 (same site). `firstDiscard`
  human-partner pollution. Trivial 1-line fix; not adversarial
  but real signal-noise pollution in mixed-tier games.
* **LOW (1):** F7 — `aceLate` ungated. Self-poisoning concern;
  no clear adversarial path; defensive-direction damping.
* **OK (8):** F1, F2, F3, F5, F6, F8, F11, F12, F13.

The R6 fix correctly closed the highest-leverage gap
(`topTouchSignal` weight 60). All remaining sampler issues
are calibration-tier, not correctness-tier. None are
correctness-blocking for v0.10.2.

---

## File references

* `C:\CLAUDE\WHEREDNGN\BotMaster.lua` lines 196-577
  (`sampleConsistentDeal`).
* `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-08_trust_asymmetry_audit.md`
  (companion read-side trust-asymmetry audit).
* `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-21_ismcts_poisoning.md`
  (companion attacker-playbook audit; MEDIUM #1, LOW-MED #3,
  LOW Stack-5b correspond to F9, F4/F10, F7 in this audit).
* `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\reaudit_R6_touching_honors.md`
  (R6 trust-asymmetry citation, video #05 @ 03:17-03:22).
