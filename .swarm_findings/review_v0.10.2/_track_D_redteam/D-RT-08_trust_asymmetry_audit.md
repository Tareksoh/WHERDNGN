# D-RT-08 — Trust-asymmetry audit across all signal-reading sites in BotMaster

## Scope and method

Per video #05 @ 03:17–03:22 (canonical citation in
`reaudit_R6_touching_honors.md`):

> "طبعا انت ما تقيد على خويك لكن هذا خصم ممكن يقيد عليه"
> ("Of course you don't [deceive] your partner, but this one is an
> opponent — he can [deceive].")

Trust-asymmetry rule: **trust partner signals at face value;
discount/avoid opponent signals.** v0.10.0 R6 introduced the
gate at the topTouchSignal reader (`sIsPartner`-only). Every
OTHER signal site in `BotMaster.sampleConsistentDeal` should now
be audited against the same standard.

Sites enumerated (READ in `BotMaster.lua:200-550`):

1. `firstDiscard` → partner-only desire injection (line 211–212, 380)
2. `likelyKawesh` → desire-clear (line 400–404)
3. `aceLate` → pickProb damping (line 405–409)
4. `leadCount` → suit-bias additive (line 436–443)
5. `topTouchSignal` → desire pin / clear / broke (line 473–500)
6. `void` → hard exclusion (line 342–343, 504, etc.)
7. Per-bidder strong/defender/partner-of-bidder desire maps
   (these are bid-derived not behavioural, so out-of-scope for
   trust-asymmetry).

Plus the WRITE-side rollback for `firstDiscard` trump-ruff fix
(Bot.lua:431-438), per-task instruction.

`tahreebSent` and `baitedSuit` are NOT read by BotMaster — they
are read only by `Bot.lua` `pickLead` (lines 1860–1928,
3210–3278). Audit covers them at their actual READ site.

---

## Per-site verdicts

### 1. `firstDiscard` (Fzloky signal-suit bias)

**READ — `BotMaster.lua:210–212, 380`**

```lua
local partner = R.Partner(seat)
local pMem = B.Bot._memory and B.Bot._memory[partner]
local pSignalSuit = pMem and pMem.firstDiscard and pMem.firstDiscard.suit
...
if s == partner and pSignalSuit then desire[pSignalSuit] = 1 end
```

**Verdict: CORRECT — partner-only by construction.**

The reader explicitly indexes `B.Bot._memory[partner]` (where
`partner = R.Partner(seat)`) and only writes the desire bump on
the line `if s == partner and pSignalSuit then`. Opp seats are
never consulted for `firstDiscard` and never receive a desire
bump from any seat's discard. Trust-asymmetry holds.

**Vulnerability check (specific #4 — opp deliberately plays a
suit-7 first to inject `firstDiscard=7-low`):** The opp's own
`firstDiscard` IS recorded in `B.Bot._memory[oppSeat]` by
`Bot.OnPlayObserved` (Bot.lua:353-355), but BotMaster never reads
it. The picker's Fzloky branch (`Bot.lua:1962–1963`) also gates
on `Bot.IsBotSeat(p)` AND `p == R.Partner(seat)`, so opp's
`firstDiscard` is never consulted there either. **No exploit
path through the BotMaster sampler.** Confirmed safe.

---

### 2. `likelyKawesh` (low-card-only inference)

**READ — `BotMaster.lua:400-404`**

```lua
local mem = B.Bot._memory and B.Bot._memory[s]
local sIsOpponent = R.TeamOf(s) ~= R.TeamOf(seat)
if mem and mem.likelyKawesh and sIsOpponent then
    desire = {}
end
```

**Verdict: CORRECT — opp-only, but with safe semantics.**

The gate is `sIsOpponent` (opp-only), not partner-only. This is
the *inverse* of the topTouchSignal pattern but still
trust-asymmetric in the right direction:

* **What it does for opps:** clears strong-card desire (so the
  sampler doesn't pin J/9/A to a low-card hand). This is
  *defensive* — it removes a positive bias rather than adding
  one. It assumes the opp's own play history is honest evidence
  about THEIR hand shape (rank 7/8/9 plays in tricks 1-3),
  which is a structural fact, not a partner-trust signal.
* **Why partner is excluded:** the comment at lines 396-399
  states partners playing only 7/8/9 may be conserving cards
  (Fzloky low-discard) rather than truly broke. So
  partner-Kawesh is unsafe to act on.

**Vulnerability check:** Could an opp deliberately play 7/8/9
in tricks 1-3 to trigger `desire = {}` for themselves and trick
the bot into NOT pinning their J/9 of trump? Possibly — but the
RESULT would be the bot SAMPLES with the opp's J/9 distributed
across all 3 non-self seats uniformly instead of biased TO that
seat. This is a `wider-uncertainty` outcome, not a `wrong-pin`
outcome — and meld-pins / H-1 trump pins still hard-pin the
bidder's J/9 by the contract-level path. The exploit value is
limited; the worst outcome is rollout-noise increase, not
mis-routing. **Acceptable.**

---

### 3. `aceLate` (A-hoarder pickProb damping)

**READ — `BotMaster.lua:405-409`**

```lua
local style = B.Bot._partnerStyle and B.Bot._partnerStyle[s]
local pickProb = 0.7
if style and style.aceLate and style.aceLate >= 2 then
    pickProb = 0.5  -- A-hoarder: less reliable strong-bias
end
```

**Verdict: GAP — ungated; symmetric across partner/opp.**

The condition does NOT include `sIsPartner` or `sIsOpponent` —
it fires for ALL non-self seats including the bot's own
partner. The effect is to lower `pickProb` from 0.7 to 0.5,
broadening the sampled distribution.

**Trust-asymmetry analysis:** This site is a NEUTRAL-DAMPING
read, not a positive-bias read. Lowering `pickProb` weakens the
strong-card pinning across ALL seats with `aceLate >= 2`. An opp
deliberately playing late Aces just makes the bot's sampler
LESS confident that opp holds strong cards — equivalently, more
exploratory. This is the *defensive* direction of bias, not the
*aggressive* direction.

**Specific exploit path:** Could an opp deliberately defer Ace
plays past trick 5 to inflate their `aceLate` count, then have
the bot under-pin their Aces in rollouts? Yes — but the result
is the sampler scatters their Aces across other seats,
broadening uncertainty. The bot's rollout policy is then less
likely to assume opp holds Aces — which means the bot might
LEAD an opp Ace's suit hoping to win, when in fact opp will
trick-take it. This IS an exploitation path, though weaker
than a positive-pin exploit. **Mark: minor gap, acceptable
because the damping direction is defensively-conservative.**

The reader correctly mirrors the WRITE site, which is also
ungated (Bot.lua:629-634 fires for any seat playing late A's).

---

### 4. `leadCount` (repeat-lead suit bias)

**READ — `BotMaster.lua:436-443`**

```lua
if style and style.leadCount and sIsOpponent
   and not (mem and mem.likelyKawesh) then
    for suit, count in pairs(style.leadCount) do
        if count >= 3 and not desire[suit] then
            desire[suit] = 1
        end
    end
end
```

**Verdict: CORRECT — opp-only ENABLE, but with caveats.**

The reader is gated on `sIsOpponent` (opp-only), and the
COMMENT at line 432-435 explains why: "we don't need to
second-guess teammate hand shape (we already have stronger
signals via firstDiscard / Tahreeb)." So partner is correctly
excluded.

**However — this is opp-only POSITIVE bias.** Setting
`desire[suit] = 1` activates the suit-fallback path (weight 20
per card) for that opp seat, biasing the sampler to PUT MORE of
that suit IN their hand. Per the trust-asymmetry rule, opp
positive-bias should be discounted, not applied at face value.

**Specific vulnerability #5 — opp leads bait suits to inflate
`leadCount`:** YES, this is a real exploit path.

Concrete attack scenario (Hokm, opp seat 2):
1. Game-level: opp seat 2 leads suit C three times across
   rounds 1-3 (any tricks).
2. `style.leadCount.C = 3` is now active. The READ site at
   `BotMaster.lua:436-443` will set `desire["C"] = 1` for opp
   seat 2 every time the sampler runs.
3. Sampler now over-clusters Clubs into seat 2's hand. In
   rollouts, the bot estimates opp seat 2 holds long Clubs.
4. The bot's `pickLead` heuristics (M3lm tier, Bot.lua) AVOID
   leading suits where opps are believed long (over-trump risk).
   So bot avoids leading Clubs.
5. Reality: opp seat 2 DOESN'T hold long Clubs anymore —
   they're saving a strong Club holding for a coup. The bot
   never leads Clubs, so opp's long Clubs never get drawn out.

The exploit requires multi-round signal injection (3 leads
across the game), so it's a **slow burn** rather than
single-round, but it IS exploitable.

**Mitigation already partially in place:** The condition
`not (mem and mem.likelyKawesh)` provides a partial escape —
if the opp is also playing low cards, the bias is suppressed.
But a sophisticated opp can avoid the Kawesh trigger (play A's
late mixed with low) and still exploit the leadCount path.

**Severity: MEDIUM — game-level signal injection is slow but
real. v0.9.2 #46 fix (round-scoping `baitedSuit` and
`topTouchSignal`) did NOT extend to `leadCount` because
leadCount is intentionally per-game (the comment at Bot.lua:209
says "across the GAME, not the round — _partnerStyle is
per-game"). Consider whether `leadCount` should be moved to
per-round scope OR have its READ site rate-limit the signal
beyond `count >= 3`.**

---

### 5. `topTouchSignal` (touching-honors-down)

**READ — `BotMaster.lua:473–500`**

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

**Verdict: CORRECT — `sIsPartner`-only gate (v0.10.0 R6 fix).**

Trust-asymmetry rule applied. The comment block at lines
451-470 documents the rule citation (video #05 @ 03:17-03:22)
and the rationale: opps could weaponize the mis-pin via
deceptive K-plays. Skip applying for self (`s == seat` —
already excluded from the outer `s ~= seat` loop) and for opp
seats. Confirmed.

**However:** the WRITE site at `Bot.lua:476–508` is STILL
symmetric — it records observations for any seat whose leader
was their partner, including opp-as-follower contexts. The
ledger therefore CONTAINS opp-side observations; only the READ
site filters them. This is the documented design (per the
v0.10.0 R6 fix comment at Bot.lua:466-470: "writer remains
symmetric (records observation for any seat); the READER
(BotMaster.lua) applies the team-gate so opponent inferences
don't weaponize against the bot").

This is fine for the BotMaster sampler. **But the same ledger
might be consulted by other readers in the future** — any new
reader would need to re-apply the trust-asymmetry gate. No
current bug; flagging as a forward-compatibility concern.

---

### 6. `void` inference (hard exclusion)

**READ — `BotMaster.lua:342-343, 504`**

```lua
local voids = (B.Bot._memory and B.Bot._memory[s]
               and B.Bot._memory[s].void) or {}
...
if #hand < n and not used[c] and not voids[C.Suit(c)] then
```

**Verdict: CORRECT — symmetric application is correct here.**

Void inference is structural fact: a seat that didn't follow
suit IS void in that suit (modulo illegal-play guard at
Bot.lua:344-345). No deception possible — even an opp playing
deceptively MUST commit to being-void if they don't follow suit
(rules-enforced). So symmetric read is safe and correct.

**Caveat: trump-ruff void is correct, intentional discard
(Tasgheer signal) void is correct.** Both inputs to `void` are
hard truths regardless of seat team.

---

### 7. WRITE-side: `firstDiscard` trump-ruff rollback

**WRITE — `Bot.lua:431-438`**

```lua
if not wasIllegal and leadSuit and cardSuit ~= leadSuit
   and contract and contract.type == K.BID_HOKM
   and contract.trump and cardSuit == cardSuit and cardSuit == contract.trump
   and mem.firstDiscard
   and mem.firstDiscard.suit == cardSuit
   and mem.firstDiscard.rank == C.Rank(card) then
    mem.firstDiscard = nil
end
```

(Quote slightly compressed for the dual-cardSuit check; verbatim
at Bot.lua:431-437.)

**Verdict: CORRECT — fires for BOTH partner and opp seats.**

The rollback acts on `mem = Bot._memory[seat]` (line 333) where
`seat` is the just-played seat, regardless of team. The rollback
condition is purely structural:

* off-suit play (`cardSuit ~= leadSuit`)
* Hokm contract with trump set
* the played card IS trump (`cardSuit == contract.trump`)
* and the just-stored `firstDiscard` matches the just-played
  card

Per the requested check (item #7): **does the rollback fire for
BOTH partner and opp seats correctly?** YES. There is no team
gate. Both partner and opp seats correctly have their
`firstDiscard` reverted when the off-suit was a trump ruff.

This is symmetric and correct — a forced trump ruff is not a
preference signal regardless of team. The trust-asymmetry
applies at READ (BotMaster.lua:212 partner-only), not at WRITE.

**Confirmed: rollback applies symmetrically; no gap.**

---

## Summary table

| Signal | READ site | Gate | Trust-asymmetric? | Exploit path |
|---|---|---|---|---|
| `firstDiscard` | BotMaster:212, 380 | partner-only (`s == partner`) | YES | none — opp's not read |
| `likelyKawesh` | BotMaster:400-404 | opp-only (`sIsOpponent`) | YES (defensive) | minor: opp triggers desire-clear → wider sampler noise (acceptable) |
| `aceLate` | BotMaster:405-409 | UNGATED | NO (but defensive damping) | minor: opp inflates count → bot under-pins Aces (acceptable, defensive direction) |
| `leadCount` | BotMaster:436-443 | opp-only (`sIsOpponent`) | INVERTED (opp-only POSITIVE bias) | **MEDIUM: opp leads bait suits 3+ times across game → bot over-clusters that suit to opp → bot avoids leading it** |
| `topTouchSignal` | BotMaster:473-500 | partner-only (`sIsPartner`) | YES (v0.10.0 R6) | none — opp not consulted |
| `void` | BotMaster:342-343, 504 | UNGATED | symmetric | none — structural truth |
| `firstDiscard` rollback | Bot.lua:431-438 | UNGATED (write-side) | symmetric | none — structural truth |
| `tahreebSent` | (Bot.lua:1860-1928, NOT in BotMaster) | partner via `IsBotSeat(p)`; opp via `IsBotSeat(s) AND TeamOf(s) ~= TeamOf(seat)` | YES (`bargiya_hint` correctly added to opp-avoid in v0.9.3 #58) | none in BotMaster |
| `baitedSuit` | (Bot.lua pickLead, NOT in BotMaster) | per-suit count (read by pickLead, not by sampler) | n/a here | n/a in BotMaster (forced-J gate at WRITE per v0.9.2 #46) |

---

## Findings ranked by severity

### Finding D-RT-08-A (MEDIUM) — `leadCount` opp-only positive bias is exploitable

**Site:** `BotMaster.lua:436-443`.

**Issue:** The `leadCount` reader is opp-only AND adds POSITIVE
bias (`desire[suit] = 1`) for opps with `count >= 3`. This
inverts the trust-asymmetry rule: opp signals should be
discounted/ignored, not weighted-up.

**Quote:**

```lua
if style and style.leadCount and sIsOpponent
   and not (mem and mem.likelyKawesh) then
    for suit, count in pairs(style.leadCount) do
        if count >= 3 and not desire[suit] then
            desire[suit] = 1
        end
    end
end
```

**Specific exploit (instruction #5):** Opp seat deliberately
leads suit X 3 times across the game's first 2-3 rounds.
`style.leadCount.X` reaches 3. Sampler now over-clusters X into
opp's hand. Bot's pickLead avoids leading X (over-trump risk),
so opp's actual long-X holding (concealed via not-leading-it
once primed) never gets drawn out. Slow-burn exploit (multi-
round), but real.

**Mitigation options (audit, no code change):**
- Move `leadCount` to per-round scope (matches v0.9.2 #46
  pattern for `baitedSuit` and `topTouchSignal`). Requires also
  adjusting the threshold (`count >= 3` won't trigger inside one
  round of 8 tricks for non-trump leads).
- Raise the activation threshold (`count >= 5`?) to require
  much more signal.
- Remove the opp-only branch entirely and rely on void
  inference for opp hand-shape signal.

### Finding D-RT-08-B (LOW) — `aceLate` ungated read

**Site:** `BotMaster.lua:405-409`.

**Issue:** `aceLate >= 2` damping fires for ALL non-self seats
including the partner. Damping direction is defensive
(broadens uncertainty), so the trust-asymmetry violation is
weaker than D-RT-08-A's positive-bias case. But strict
adherence to the trust rule would gate this on `sIsOpponent`
only (or partner-only, depending on the desired direction).

**Quote:**

```lua
if style and style.aceLate and style.aceLate >= 2 then
    pickProb = 0.5  -- A-hoarder: less reliable strong-bias
end
```

**Recommendation:** No urgent fix needed; defensive direction
makes this acceptable. Document the asymmetry direction
(damping fires for both teams; positive-bias would NOT be
acceptable to fire for both).

### Finding D-RT-08-C (LOW, forward-compat) — topTouchSignal WRITE asymmetry

**Site:** `Bot.lua:476-508` (write), `BotMaster.lua:473-500`
(read with v0.10.0 R6 gate).

**Issue:** WRITE site records opp-side observations into the
ledger; only the READ site filters them. Any future reader of
`style.topTouchSignal` MUST replicate the `sIsPartner` gate or
risk re-introducing the v0.10.0 R6 vulnerability.

**Quote (write site, lacks team-gate):**

```lua
if not wasIllegal and contract and trickPlays
   and #trickPlays >= 2 and style.topTouchSignal then
    local lead = trickPlays[1]
    local theirRank = C.Rank(card)
    local touchContext = false
    if lead.seat == R.Partner(seat)
       and C.Suit(lead.card) == cardSuit
       and C.Rank(lead.card) == "A" then
        touchContext = true
    elseif S.s.akaCalled and S.s.akaCalled.seat == R.Partner(seat)
           and S.s.akaCalled.suit == cardSuit then
        touchContext = true
    end
    if touchContext then
        ...
        style.topTouchSignal[cardSuit] = entry
    end
end
```

The `touchContext` requires the LEADER to be the FOLLOWER's
partner — but does not require the FOLLOWER to be the bot's
partner. So opp-as-follower observations (where opp's own
partner led an Ace) get recorded into
`Bot._partnerStyle[oppSeat].topTouchSignal`.

**Recommendation:** No urgent fix; current single-reader
already gates correctly. Add a comment or invariant note that
the ledger contains untrusted opp-context entries and any
future reader must apply trust-asymmetry. The existing comment
at Bot.lua:466-470 partially does this; consider strengthening
it with an explicit "DO NOT add a new reader without
sIsPartner gate".

### Finding D-RT-08-D (CONFIRM) — `firstDiscard` rollback (v0.5.6) fires symmetrically

**Site:** `Bot.lua:431-438`.

**Verdict:** Confirmed correct. Rollback fires for any seat
when off-suit play was Hokm trump-ruff. Both partner and opp
seats have their poisoned `firstDiscard` correctly nulled.

The rollback's symmetry is correct because:
* The rollback acts on a structural fact (forced trump ruff),
  not a deception-prone signal.
* The READ site for `firstDiscard` is partner-only
  (BotMaster.lua:212), so opp-side `firstDiscard` is never
  consumed by BotMaster regardless of rollback.
* If a future reader DID consume opp's `firstDiscard`, the
  symmetric rollback ensures opp can't poison their own
  signal via trump-ruff. Defensively sound.

### Finding D-RT-08-E (CONFIRM) — `tahreebSent` reader at Bot.lua:1860-1928 is correctly trust-asymmetric

**Site:** `Bot.lua:1860-1928` (NOT in BotMaster).

**Verdict:** Partner side uses `Bot.IsBotSeat(p)` gate plus
score weighting (`bargiya=3, want=2, bargiya_hint=1`). Opp side
uses `R.TeamOf(s) ~= R.TeamOf(seat)` gate AND treats opp
positive signals (`bargiya`/`want`/`bargiya_hint`) as
**avoid-suits** (deny-tempo defense). Conflict resolution at
line 1926-1928 drops partner pref if opp avoid claims same
suit.

**Specific exploit check (#4 — opp injects firstDiscard 7-low
to misroute):** `tahreebSent` is recorded via Bot.lua:578-623,
gated on `prevWinner == R.Partner(seat)` — i.e., the SENDER's
partner must have been winning the trick. Opp can't inject a
fake tahreeb signal into their own ledger by playing a 7
arbitrarily — they'd need their own partner to be winning the
trick first. This precondition makes injection harder but not
impossible (an opp pair can coordinate). However, the READ
site treats opp-positive as bot-avoid (deny-tempo), so the
injection's effect is to make the bot AVOID the suit — which
matches the REAL Saudi defense pattern even if the signal was
an opp coordination. **Net: opp can shift bot's lead choice
but only in the defensive direction. Acceptable.**

---

## Closing notes

The v0.10.0 R6 fix established a precedent (`sIsPartner` gate
at READ for partner-only signals). Of the BotMaster sampler's
six signal-reading sites:

* **3 sites** (`firstDiscard`, `topTouchSignal`, plus the void
  hard-exclusion which is symmetric-but-truth-based) correctly
  apply trust-asymmetry.
* **2 sites** (`likelyKawesh`, `leadCount`) are gated on
  `sIsOpponent` rather than `sIsPartner` — the inverse direction.
  This is correct for `likelyKawesh` (defensive desire-clear),
  but **wrong-direction for `leadCount`** (positive opp bias →
  D-RT-08-A).
* **1 site** (`aceLate`) is ungated. Defensive direction makes
  it acceptable but not strictly trust-asymmetric.

**Single primary action item: D-RT-08-A** — re-evaluate
`leadCount` reader semantics. Either move it to per-round
scope, raise the activation threshold significantly, or remove
the opp-only positive bias entirely. Game-level signal
injection across 3 leads is a real (if slow) exploit path
inconsistent with the trust-asymmetry rule the rest of the
codebase enforces post-v0.10.0.

---

## File references

* `C:\CLAUDE\WHEREDNGN\BotMaster.lua` lines 200-550 (sampler core).
* `C:\CLAUDE\WHEREDNGN\Bot.lua` lines 100-700 (write sites for all signals).
* `C:\CLAUDE\WHEREDNGN\Bot.lua` lines 1860-1928 (tahreeb pickLead reader, out of BotMaster scope but verified).
* `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\reaudit_R6_touching_honors.md` (trust-asymmetry source citation, video #05 @ 03:17-03:22).
* `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\reaudit_R4_bargiya_tahreeb.md` (Bargiya/Tahreeb taxonomy and classifier audit).
