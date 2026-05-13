# v3.2.3 design pass — pos-3 Sun unreachable branches relocation

**Repo:** `C:\CLAUDE\WHEREDNGN`
**Main / origin-main / v3.2.2 tag:** all at `e146ca1`
**Scope:** read-only design pass. No runtime, test, TOC, or
packaging edits.

---

## §0 Executive recommendation

**PROCEED with relocation of F5-3 ONLY in a v3.2.3 batch. DEFER F2
hold-back to a separate later batch.**

Both dead branches share the same root cause (sit below an
unconditional `partnerWinning` return), but they have very
different complexity profiles:

| Branch | Complexity | Test profile | Conflicts with smother |
|---|---|---|---|
| **F5-3** (Takbeer donate non-A/T, audit-doc) | deterministic, narrow gates, "pure-addition" semantics per its own v1.4.1 comment | 8 behavioural + 4 source-pin sub-asserts = 12 new harness checks | **Resolvable by ordering** (place AFTER smother AND AFTER Tahreeb sender, BEFORE Rule 1B → smother stays canonical for led-suit point cards; Tahreeb's signal beats F5-3's pure point-feed on overlap; F5-3 covers the residual cases). **Also closes the v3.2.2-deferred F5/D-1 tie-randomization site** at F5-3 — making the branch reachable means the relocated implementation must use a `donate` pool + `highestByRank` rather than a strict-`>` ranking loop, BF.9 wire-proofs this. |
| **F2** (pos-3 «تخليه يمسك» hold-back, deception) | probabilistic 30%/40% fire-rate, broader gates, deception-intent vs canonical-Takbeer | needs deterministic `math.random` stub fixture + tied-suit setup that doesn't trigger smother / Tahreeb sender first; multi-iteration parity check | **Intercepts smother** when conditions match — F2 wants to NOT donate K, smother would donate K; F2 must fire BEFORE smother → broader gameplay change |

F5-3 fits the established v3.2.2 BE-tests pattern (deterministic
math.random stub OR no RNG needed at all — F5-3 has no RNG path).
F2 needs its own test-framework design pass for probabilistic
deception, which is structurally different.

**Recommended next batch:** v3.2.3 relocates F5-3 only.
**Deferred to v3.2.4+:** F2 hold-back reactivation, after a
focused audit designs the deception-play test approach.

---

## §1 pickFollow structure map (as of v3.2.2 / `e146ca1`)

```
pickFollow(legal, hand, trick, contract, seat)  -- L2963
├── implicitAKA detection                       -- L3009-3019
├── AKA-receiver relief                         -- L3107-3148
├── Sun pos-4 Faranka (separate block)          -- L3175-3360
│   gate: Sun + lastSeat + partnerWinning + bidder-team + ...
│   exits: cover (T/K) OR A based on 5-factor captureRate
│
├── ─── if partnerWinning then  ──────────────  -- L3366
│   ├── 1. Smother (Takbeer)                    -- L3367-3532
│   │   gate: feedSafe + has point cards in led + various
│   │   feedSafe = (not Hokm OR leadSuit ~= trump)
│   │   return: highest point card in led (A/T/K/Q/J sorted)
│   │
│   ├── 2. Tahreeb sender                       -- L3534-3737
│   │   gate: M3lm + void-in-led (Sun for T-1; non-trump for T-4)
│   │   return: T-1 Bargiya (A of cover suit) OR T-4 dump-larger
│   │
│   ├── 3. Rule 1B (biggest mistake)            -- L3739-3798
│   │   gate: must-follow + second-lowest doesn't win partner's trick
│   │   return: second-lowest in led suit
│   │
│   ├── 4. v3.1.9 trump-led-fragile-lock         -- L3800-3867
│   │   gate: Advanced + Hokm + trump-led + partner-led + opp may over-cut
│   │   return: minimum-sufficient lock trump
│   │
│   ├── 5. Hokm non-trump preference            -- L3874-3884
│   │   gate: Hokm + we have non-trump in legal
│   │   return: lowestByRank(nonTrumpLegal)
│   │
│   └── 6. Fallback                             -- L3886
│       return lowestByRank(legal)
├── ─── end (partnerWinning block ends)  ──────  -- L3887
│
├── -- Opponent winning: try to beat them. --   -- L3889
├── winners = { c : wouldWin(c, ...) }          -- L3890-3893
├── Hokm Faranka exceptions (M3lm, video #04)   -- L3895-4091
├── Defender J/9 trump-burn protection          -- L4093-4131
├── ... (many more opp-winning branches)        -- L4133+
│
│   *** DEAD BRANCHES (sit here, can't fire):
│   ├── F5-3 Takbeer donate non-A/T (pos-3)     -- L4464-4491
│   │   gate: M3lm + Sun + partnerWinning + #winners==0 + pos-3 + pos4Void
│   │   ▲ unsatisfiable: partnerWinning=true ⊥ enclosing scope's
│   │     guarantee that partnerWinning=false
│   │
│   └── F2 pos-3 «تخليه يمسك» hold-back         -- L4528-4649
│       gate: M3lm + Sun + pos-3 + partner-led-mid + pos2-lower
│             + K + low + indep-strength + midRound + nonClutch
│             + pos4Void + math.random() < {0.30 M3lm, 0.40 SM}
│       ▲ pos2Lower ⇒ partnerWinning, same unsatisfiability
```

**Key invariant:** every `partnerWinning=true` decision returns
inside the L3366-3887 block. The opp-winning region (L3889+)
sees `partnerWinning=false` unconditionally. Any branch with an
inner `partnerWinning` check in that region is dead.

---

## §2 F2 hold-back full preconditions (Bot.lua:4528-4649)

Trigger conditions (must ALL be true):

| # | Condition | Source | Comment |
|---|---|---|---|
| C1 | `Bot.IsM3lm()` (M3lm or higher) | L4530 | Tier gate; Saudi-Master fires harder |
| C2 | `contract.type == K.BID_SUN` | L4531 | Sun only — Hokm pos-3 has different conventions |
| C3 | `trick.leadSuit and trick.plays and #trick.plays >= 2` | L4532 | We're pos-3 (2 prior plays) or pos-4 |
| C4 | `pos == 3` | implied by enclosing `elseif pos == 3` at L4439 |
| C5 | `#winners > 0` | L4533 | Required by enclosing `if #winners > 0` at L4169 |
| C6 | `partnerLed` (pos1.seat == R.Partner(seat)) | L4547 | Partner led the trick |
| C7 | `partnerLedMid` (pos1 rank ∈ {8, 9, J, Q}) | L4549-50 | Partner led mid, not boss/low |
| C8 | `pos2Lower` (pos2 played lower OR off-suit Sun-loses) | L4553-58 | Implies partner currently winning |
| C9 | `hasK and lowCard` (K of lead + at least one of 7/8/9 of lead in hand) | L4561-74 | Hand-shape requirement |
| C10 | `hasIndependentStrength` (≥1 non-led-suit A or a 3+-card non-trump suit) | L4575-97 | Not betting the round on this K |
| C11 | `midRound` (trick 2-5) | L4598-4600 | Mid-round window |
| C12 | `nonClutch` (both teams below target-26) | L4601-09 | Score not in clutch range |
| C13 | `pos4CannotBeat` (Bot._memory[pos4].void[lead] == true) | L4628-34 | Strict pos-4 void in led |
| C14 | `math.random() < fireRate` (0.30 M3lm / 0.40 Saudi Master) | L4636-45 | Probabilistic |

Return: `lowCard` (highest of our 7/8/9 in led suit — the duck card).

**Reachability blocker (C8 implies partnerWinning):** if `pos2Lower=true`, partner is currently winning. Enclosing scope already returned from `if partnerWinning then ... return lowestByRank(legal) end` at L3886, so this branch is unreachable.

---

## §3 F5-3 Takbeer donate non-A/T full preconditions (Bot.lua:4464-4491)

Trigger conditions (must ALL be true):

| # | Condition | Source | Comment |
|---|---|---|---|
| D1 | `Bot.IsM3lm()` | L4464 | Tier gate |
| D2 | `contract.type == K.BID_SUN` | L4465 | Sun only |
| D3 | `partnerWinning` | L4466 | Partner currently winning (UNSATISFIABLE in current location) |
| D4 | `#winners == 0` | L4466 | We have NO cards that would win the trick (in opp-winning context) |
| D5 | `pos == 3` | implied by enclosing `elseif pos == 3` at L4439 |
| D6 | `trick.leadSuit and Bot._memory` | L4467 | Bookkeeping prerequisites |
| D7 | `pos4Void` (Bot._memory[pos4].void[lead] == true) | L4468-72 | Strict pos-4 void in led |

Return: `donate` = highest non-A/T card in legal (preserves A/T for future tricks).

**Reachability blocker (D3 ⊥ enclosing scope):** as with F2, the enclosing `#winners > 0` block at L4169 is reached only after partnerWinning early-return; `partnerWinning=true` is then impossible.

---

## §4 Relocation analysis

### §4.1 F5-3 relocation (recommended for v3.2.3)

**Target location:** inside `if partnerWinning then` block,
**AFTER smother (~L3532), AFTER Tahreeb sender (~L3737), BEFORE
Rule 1B (~L3739)**.

The original v0.1 draft of this doc had a self-inconsistency: §4.1
said "AFTER smother, BEFORE Tahreeb" while §4.2 walked through
the Tahreeb shadowing logic and recommended the opposite (AFTER
Tahreeb, BEFORE Rule 1B). The v0.2 amendment (post-Codex review)
resolves this in favour of the §4.2 placement: F5-3 goes
**between Tahreeb's end (~L3737) and Rule 1B's start (~L3739)**.

Proposed shape (NOT applied; documented for review):

```lua
-- L3367-3532 Smother / Takbeer    — unchanged
-- L3534-3737 Tahreeb sender       — unchanged
-- ↓ NEW: F5-3 insertion point at ~L3738 ↓
-- L3739-3798 Rule 1B (biggest mistake) — unchanged

-- v3.2.3 F5-3 (audit doc) — relocated from old dead block at
-- L4464-4491 (which is REMOVED in the same commit). Takbeer /
-- Tasgheer certainty gate: when pos-3 Sun + pos-4 known void in
-- led, donate highest non-A/T to partner's certain trick
-- (preserve own A/T for future tricks).
--
-- Placement rationale: AFTER smother + AFTER Tahreeb. Smother's
-- highest-point-of-led donate stays canonical; Tahreeb's signal-
-- encoding takes precedence over a pure point-feed; F5-3 fires
-- only when both upstream branches fell through (typically when
-- we have neither A/T/K/Q/J of led in hand nor a Tahreeb-eligible
-- discard shape).
--
-- The original `#winners == 0` gate was semantically tied to the
-- opp-winning context where this branch used to live. The
-- equivalent in partnerWinning context is "the donate candidate
-- does not win the trick for our seat" — i.e., we filter the
-- candidate pool with `not wouldWin(c, trick, contract, seat)`
-- so we cannot accidentally steal partner's current trick with
-- a same-suit K/Q/J after smother fell through.
--
-- v3.2.2 F5/D-1 audit context: F5-3 was identified as one of
-- the four tie-randomization sites that bypass the v1.1.0
-- HIGH-1 unpredictability fix; it was deferred from v3.2.2
-- ONLY because the branch was unreachable at the time. By
-- relocating into the live partnerWinning block here, we MUST
-- also fix the tie-break — building a `donate` pool and
-- routing through Primitives.highestByRank picks ties at
-- random rather than by hand-iteration order. Do NOT use a
-- strict `donateRank` / `cr > donateRank` first-encountered
-- ranking loop; that would re-introduce the leak v3.2.2 closed
-- at the side-Ace exhaustion site.
if Bot.IsM3lm and Bot.IsM3lm()
   and contract.type == K.BID_SUN
   and (#trick.plays + 1) == 3
   and trick.leadSuit and Bot._memory then
    local pos4Seat = (seat % 4) + 1
    local pos4Mem = Bot._memory[pos4Seat]
    local pos4Void = pos4Mem and pos4Mem.void
                     and pos4Mem.void[trick.leadSuit]
    if pos4Void then
        local donate = {}
        for _, c in ipairs(legal) do
            local r = C.Rank(c)
            if r ~= "A" and r ~= "T"
               and not wouldWin(c, trick, contract, seat) then
                donate[#donate + 1] = c
            end
        end
        if #donate > 0 then
            return highestByRank(donate, contract)
        end
    end
end
```

### §4.2 Ordering rationale: AFTER smother, AFTER Tahreeb, BEFORE Rule 1B

**Why AFTER smother:**

Smother's existing scope (L3367-3532) iterates `pointCards = {A, T, K, Q, J of led suit}` and returns the highest. F5-3's policy explicitly says: "Skip if we're a STRONG suit holder ourselves (don't burn our own future winners). Heuristic: skip the donate if our highest card is A or T."

Two interpretations of how F5-3 should interact with smother:

**Interpretation A (post-Codex-leaning; safer):** F5-3 is a
*supplement* to smother — fires when smother has no point card
in led suit to donate. The "pure addition to previously-default-
low behavior" wording in F5-3's original v1.4.1 comment supports
this. Place AFTER smother. Smother's A/T-donate stays canonical
when applicable. F5-3 only fills the **void-in-led** gap (no
point card in led, donate highest non-A/T from elsewhere).

**Interpretation B (more aggressive):** F5-3 is an *override* of
smother — when pos-3 + pos4-void, prefer K over A even when both
are in led suit. The "skip if our highest is A or T" carve-out
in F5-3's comment supports this. Place BEFORE smother.

For v3.2.3 we **recommend Interpretation A**:

- Smaller behavior change footprint
- Lines up with the "pure-addition" wording of the original v1.4.1 comment
- Avoids cases where smother's A-donate becomes K-donate (a real gameplay change with broader review surface)
- Easier deterministic test: F5-3 fires when smother's `pointCards` is empty (e.g., we're void in led, partner's pile gets a K from a different suit)
- Interpretation B is recorded here as a future-audit candidate if Interpretation A turns out to underfire in real play

**Why AFTER Tahreeb sender:**

> **v0.2 amendment (post-Codex review):** The v0.1 draft of this
> doc claimed Tahreeb's gate required `partner is a bot`. That
> was **stale**. Bot.lua:3566-3583 documents v1.4.5's explicit
> removal of the bot-partner-only gate (Codex audit finding:
> "Strong human players do read Saudi signals. Ignoring human-
> readable signaling leaves EV on table."). The current Tahreeb
> gate at L3584 is simply `Bot.IsM3lm() and voidInLed`. F5-3 and
> Tahreeb can therefore overlap regardless of whether the
> partner is a bot or a human.

Current Tahreeb gates (Bot.lua:3584): `Bot.IsM3lm() and voidInLed`.
T-1 Bargiya sub-arm adds `contract.type == K.BID_SUN`; T-4 dump-
ordering applies in both contract types. Neither sub-arm gates on
partner-bot.

F5-3 gates: `Sun + M3lm + pos-3 + pos4Void + trick.leadSuit + Bot._memory`.

Overlap scenario (both could fire):

- Sun + M3lm + pos-3 (we're at pos-3, so NOT pos-4)
- We're void in led (satisfies Tahreeb's `voidInLed`)
- Pos-4 void in led (F5-3's `pos4Void`)
- Partner-bot is **irrelevant** to either gate.

In this overlap, Tahreeb wants to encode a *signal* (T-1 Bargiya A or T-4 dump-larger of a 2-card non-trump doubleton); F5-3 wants to donate highest non-A/T. Tahreeb's signal carries more *information*; F5-3's donate is purely *point-feeding*.

**Resolution:** Tahreeb is the more specialized convention; its
signals beat point-feeding when both apply. Tahreeb fires first
on overlap; F5-3 fires only when Tahreeb's gates don't match
(e.g., we're NOT void in led, or we hold neither a side-suit A
with cover for T-1 nor a 2-card non-trump doubleton for T-4).

**Concrete order (final, approved by Codex):**

1. Smother (Takbeer) — most general
2. **Tahreeb sender** — signal encoding (most specialized; fires
   regardless of whether partner is a bot or human, per v1.4.5)
3. **F5-3 (new placement)** — pos4-void partner-certain donate
   non-A/T (general fallback when Tahreeb's void/shape gates
   don't match)
4. Rule 1B (biggest mistake)
5. v3.1.9 trump-led-fragile-lock
6. Hokm non-trump prefer
7. Fallback

Insert F5-3 between Tahreeb's end (~L3737) and Rule 1B's start
(~L3739).

### §4.3 F2 hold-back relocation (deferred to v3.2.4+)

F2's relocation is more disruptive:

1. **Probabilistic fire** (30%/40%). Tests need a deterministic `math.random` stub *and* a multi-iteration parity check to prove the probability gate works correctly. The v3.2.2 BE-tests pattern handles deterministic single-shot wiring; it doesn't yet have a clean idiom for "1000 iterations, assert 28–33% fire rate." Adding that idiom is a separate test-framework design.
2. **Intercepts smother on K-donate.** F2 wants to NOT donate K, smother would. F2 must fire BEFORE smother. That's a real gameplay change — many Sun pos-3 partnerWinning hands hold K and would previously donate K via smother, now duck low 30-40% of the time. Need to measure EV impact.
3. **Returns LOW (a duck)** — reads as Rule 1B's "biggest mistake" signal pattern. Need to verify partner-side reads aren't corrupted.
4. **Independent-strength check** (C10) and **non-clutch** (C12) gates assume score-aware play. These haven't been exercised before in tests; need fixture audits.

Deferring F2 keeps v3.2.3 small. Re-audit F2 in a dedicated batch with the deception-play test framework designed alongside it.

---

## §5 Behavioral test plan (for v3.2.3 F5-3 only)

All tests use the established BE-style fixture pattern (advanced/M3lm flags, freshState, hostHands, Bot._memory, deterministic when needed).

### BF.1 — F5-3 reachability + correct card

> **v0.3 amendment (post-Codex review):** the v0.2 fixture
> ("single 3-card non-trump suit with no Ace/no T") would have
> triggered Tahreeb's live **"want, no Ace/no T" sender arm**
> (Bot.lua:3676-3701: `#cards >= 3 and not hasA and not hasT
> → return lowestByRank(cards)`) BEFORE F5-3. Codex's
> recommendation: include a **T** in the candidate suit so that
> sub-arm's `not hasT` guard fails, and keep #cards = 3 so the
> T-4 doubleton arm also doesn't fire. Result shape: one
> non-led suit with **K, T, Q** (or equivalent).

**Fixture (revised):**

- Sun contract, bidder seat 1 (team A). Partner = seat 3 — wait,
  in this fixture we want the bot to be at pos-3 with partner
  having LED. So the bot is at seat 3, partner is seat 1
  (R.Partner(3) = 1). Bidder = seat 1 places partner on
  team A; bot on team A (R.TeamOf(3) = A). Defenders are seat 2
  and seat 4 (team B).
- Trick rotation with leader = seat 1: pos-1 = seat 1
  (partner), pos-2 = seat 2 (opp), pos-3 = seat 3 (bot, us),
  pos-4 = seat 4 (opp).
- Partner's lead is a mid-rank card in S (say `9S`); opp pos-2
  played a lower card (say `7S`). Partner is currently winning
  the trick.
- `Bot._memory[4].void.S = true` (pos-4 = seat 4 observed void
  in led suit S).
- M3lm enabled (`WHEREDNGNDB.advancedBots = true`,
  `WHEREDNGNDB.m3lmBots = true`).
- Bot is **void in S** (so legal becomes the non-led discards).
- Bot's hand: **`{KH, TH, QH}`** — exactly 3 cards in a single
  non-led non-trump suit (hearts). Includes T → kills Tahreeb's
  "want, no Ace/no T" arm. Excludes A → kills T-1 Bargiya.
  #cards = 3 → kills T-4 doubleton arm.

**Trace:**

| Step | Outcome |
|---|---|
| Sun pos-4 Faranka (L3175) | skipped — `lastSeat` is false (we're pos-3) |
| Smother (L3367+) | `pointCards` filtered by `Suit(c) == S` → empty (we're void in S) → falls through |
| Tahreeb sender (L3534+) | `voidInLed = true`, `Bot.IsM3lm()` ok. T-1 Bargiya: bySuit.H = {KH, TH, QH}, no A → doesn't return. "Want, no A/no T" (L3676): bySuit.H has `hasT = true` → fails `not hasA and not hasT` guard → doesn't return. T-4 doubleton (L3720): bySuit.H has `#cards = 3 ≠ 2` → doesn't return. Falls through. |
| F5-3 (new at ~L3738) | All gates pass: Sun + M3lm + pos-3 + leadSuit + Bot._memory + `pos4Void = Bot._memory[4].void.S = true`. Build `donate` pool from legal: `KH` (rank K, not A/T, not wouldWin — KH from H can't beat partner's 9S in Sun) → eligible. `TH` (rank T) → A/T filter rejects. `QH` (rank Q, not A/T, not wouldWin) → eligible. `donate = {KH, QH}`. `highestByRank(donate, contract)` finds max TrickRank = K (6); tied set = `{KH}` (only one K in donate); `pickRandomTied({KH})` short-circuits at `#tiedSet == 1` and returns `KH`. **No math.random call needed** for the single-element tied set. Returns **KH**. |

**Assert:** `card == "KH"`. This is the **wire-proof for F5-3
reachability**: pre-relocation the bot returns whatever the
fallback computes (likely `lowestByRank({KH, TH, QH}) = QH`
because RANK_PLAIN["Q"] = 5, RANK_PLAIN["K"] = 6, RANK_PLAIN["T"]
= 7 — wait let me recheck: AKA_ORDER = {"A","T","K","Q","J","9",
"8","7"}; TrickRank for non-trump = 9 - index of rank in
AKA_ORDER. So `A=8, T=7, K=6, Q=5, J=4, 9=3, 8=2, 7=1`. The
"lowest" of {KH=6, TH=7, QH=5} is QH=5).

So pre-relocation: bot returns QH (fallback's `lowestByRank`).
Post-relocation: bot returns KH (F5-3's highest non-A/T not-
wouldWin). **DIFFERENT** → BF.1 is a valid wire-proof.

### BF.2 — F5-3 fires regardless of partner being a bot or a human

> **v0.3 amendment (post-Codex review):** Same fixture-design
> issue as BF.1 — the v0.2 "3-card non-trump suit with no Ace"
> shape leaked into Tahreeb's "want, no A/no T" arm. Use the
> K/T/Q shape here too.

**Fixture context:** Per v1.4.5 (Bot.lua:3566-3583), Tahreeb does
NOT gate on partner-bot. So a "partner is human" fixture alone
won't skip Tahreeb. To prove F5-3 doesn't require partner-bot,
the fixture must AVOID Tahreeb's actual return paths regardless
of partner type.

**Fixture:** identical to BF.1 (Sun + M3lm + pos-3 + partner-led-
9S + opp pos-2 7S + bot void in S + Bot._memory[4].void.S = true
+ hand `{KH, TH, QH}`), with the additional toggle:

- `S.s.seats[1].isBot = false` (partner at seat 1 is human).

**Expected:** Identical trace to BF.1. Tahreeb's outer
`Bot.IsM3lm() and voidInLed` gate still passes (no partner-bot
filter), and all three sub-arms still fail their internal
guards. F5-3 still fires.

**Assert:** `card == "KH"`. Confirms (a) F5-3 doesn't require
partner-bot, AND (b) the fixture-design correctly avoids
Tahreeb's return paths — the actual non-overlap proof.

### BF.3 — Tahreeb wins the overlap (signal not stolen by F5-3)

**Fixture:** Sun pos-3, M3lm, void in led, pos-4 known void in
led — overlap shape for both Tahreeb and F5-3. Hand holds a
**side-suit A with cover** (≥2 cards in that suit, e.g.,
A♥ + 9♥) — satisfying Tahreeb's T-1 Bargiya sub-arm. Pos-4 (e.g.,
seat 4) has `Bot._memory[4].void[lead] = true`.

**Expected:** Tahreeb's T-1 Bargiya fires first, returns A of the
side-suit (the Bargiya invite signal). F5-3 never reached.

**Assert:** `card == "AH"` (the Bargiya A). Confirms that placing
F5-3 AFTER Tahreeb correctly preserves Tahreeb's specialized
signal even when F5-3's gates also match. **This test must pass
both pre-relocation and post-relocation** — Tahreeb already runs
before F5-3 in both states, so this is a regression-guard, not a
wire-proof.

### BF.4 — F5-3 does NOT override smother (Interpretation A invariant)

> **v0.4 amendment (post-Codex review):** v0.3 of this fixture
> just said "bot HAS A of led + some other cards" — but
> smother's `gateOk = (#pointCards >= 2) or (completed >= 3) or
> lastSeat` would fall through at pos-3 with `#pointCards = 1`
> and `completed = 0`, leaving F5-3 to fire instead and
> potentially picking K (highest non-A/T). The fixture must
> explicitly satisfy smother's `gateOk`. Picked gate: **two
> led-suit point cards** (so `#pointCards >= 2`).

**Fixture:** Sun, bidder seat 1 (team A), bot seat 3 (team A,
partner of seat 1). M3lm. Trick in progress: pos-1 = partner
seat 1 led `9S` (mid), pos-2 = opp seat 2 played `7S`. Partner
currently winning. `Bot._memory[4].void.S = true` (pos-4 void
in S — irrelevant here because smother fires first, but matches
the rest of the BF.* fixture family for consistency). `S.s.tricks
= {}` (completed = 0). Bot at pos-3, NOT lastSeat.

Hand: **`{AS, KS, 8H}`** — must-follow `S` → legal `{AS, KS}`.
Both are smother point cards (A and K) → `#pointCards = 2` →
smother's `gateOk = (2 >= 2) = true` regardless of `completed`
or `lastSeat`. Smother sorts pointCards descending by TrickRank
and returns `pointCards[1] = AS` (RANK_PLAIN["A"] = 8 > "K" = 6).

**Trace:**

| Step | Outcome |
|---|---|
| Smother | `pointCards = {AS, KS}`, `#pointCards = 2`, `gateOk = true` → returns **`AS`** (sorted descending, `[1]`). |
| F5-3 | **never reached** — smother returned. |

**Assert:** `card == "AS"`. Confirms F5-3 doesn't intercept
smother's A-donate when smother actually fires. Both pre-
relocation and post-relocation produce the same result (smother
runs before F5-3 in both states).

If a future cleanup ever puts F5-3 BEFORE smother (Interpretation
B from §4.2), this assertion would FAIL — F5-3's filter would
reject AS (`r == "A"`) AND keep KS (non-A/T, doesn't wouldWin
against partner's 9S — `K=6 > 9=3`, wait that DOES wouldWin) →
F5-3 rejects KS too, returns nothing, smother gets to fire
anyway. Hmm — even under Interpretation B, BF.4 would still
return AS in this fixture because F5-3's filter rejects both A
(rank filter) and K (wouldWin). So BF.4 is robust against
ordering swaps in this specific shape.

A stronger Interpretation-A pin would use a hand where F5-3
WOULD return a non-A non-T card if it ran first (e.g., `AS, QS,
8H` — Q rank 5 < J=4... wait Q=5 > 9=3 so QS would-wouldWin too;
need a card lower than partner's 9). With partner's lead at
`9S` (rank 3), only ranks `7` or `8` of S would not-wouldWin. So
hand `{AS, 7S}` makes pointCards = {AS}, #pointCards = 1 →
smother's gateOk fails at pos-3 with completed=0 → smother
falls through; F5-3 filter rejects A → pool = {7S} (rank 1 <
partner's 3, not wouldWin) → returns 7S. **That's the
Interpretation-B-divergent case**, but it's also a case where
smother already wasn't going to fire under Interpretation A.

For BF.4's intent (smother fires AND F5-3 doesn't override),
keeping the `{AS, KS, 8H}` two-pointCard fixture is the right
move. It's tight enough to prove the invariant.

### BF.5 — F5-3 does NOT fire when pos-4 not known void

**Fixture:** same as BF.1 but Bot._memory[4].void[X] = nil (pos-4 void unknown).

**Expected:** F5-3's pos4Void check fails → falls through. Rule 1B might fire (if must-follow), or fallback lowestByRank.

**Assert:** card != K (or specifically, card is whatever the fallback returns). The point is to pin "pos4Void required" — not over-firing.

### BF.6 — F5-3 does NOT fire when not pos-3

**Fixture:** same as BF.1 but #trick.plays == 1 (pos-2) or 3 (pos-4 — though pos-4 Sun Faranka would catch first; use a non-pos-4 setup).

**Expected:** F5-3's `pos == 3` check fails → fall through.

**Assert:** card != K via F5-3 path. Pins the pos-3 gate.

### BF.7 — F5-3 not-wouldWin filter regression guard

> **v0.3 amendment (post-Codex review):** v0.2 of this doc
> classified BF.7 as a "wire-proof for the not-wouldWin filter."
> Codex correctly flagged that this is wrong: pre-relocation,
> F5-3 is dead, so the bot never returns a wouldWin candidate
> *anyway* (Rule 1B has its own not-wouldWin gate; fallback
> `lowestByRank` picks the lowest which by definition doesn't
> beat partner). BF.7's "card ~= wouldWin-candidate" assertion
> therefore passes BOTH states trivially when framed as a
> negation. **BF.7 is reclassified as a post-implementation
> regression guard** for the filter; its job is to pin that
> the relocated F5-3 candidate loop excludes wouldWin
> candidates *as a piece of code that exists*, not to fail
> pre-fix.

> **v0.3 amendment, tightening per Codex §3:** the v0.2 fixture
> wasn't tight enough to even prove F5-3 was reached at all —
> same-suit K/Q/J are smother pointCards, so smother might
> intercept before F5-3 sees the would-steal candidate. The
> revised fixture forces smother to fall through (`#pointCards
> < 2`, completed < 3, pos-3 not lastSeat) so F5-3 is genuinely
> entered.

**Fixture (revised):**

- Sun, bidder seat 1 (team A), bot seat 3 (team A, partner of
  seat 1). M3lm.
- Trick in progress: pos-1 = partner seat 1 led **`JS`**
  (mid card), pos-2 = opp seat 2 played **`7S`**. Partner is
  currently winning (J = rank 4, 7 = rank 1).
- `Bot._memory[4].void.S = true` (pos-4 = seat 4 known void).
- `S.s.tricks = {}` (completed = 0 < 3 — kills smother's
  `completed >= 3` sub-gate).
- Bot at seat 3, pos-3, NOT lastSeat — kills smother's
  `lastSeat` sub-gate.
- Bot's hand: **`{KS, 9S, 8S, 7H}`** — must-follow S → legal
  = `{KS, 9S, 8S}`. KS is in led suit and is a smother
  pointCard. 9S and 8S are non-pointCards. `#pointCards =
  1 < 2` — kills smother's `#pointCards >= 2` sub-gate. So
  smother's combined `gateOk = (#pointCards >= 2) or
  (completed >= 3) or (lastSeat)` = false → smother falls
  through without returning.

**Expected:**

| Step | Outcome |
|---|---|
| Smother | `pointCards = {KS}`, but `gateOk = false` → no return |
| Tahreeb sender | `voidInLed = false` (we have S cards) → outer gate fails → skip |
| Rule 1B (L3739+) | `rule1bApplies = true` (Sun). `follow = {KS, 9S, 8S}`, sorted ascending by TrickRank → `[8S=2, 9S=3, KS=6]`. `sorted[2] = 9S`. `wouldWin(9S)`: 9 (rank 3) < partner's J (rank 4) → does NOT win → Rule 1B returns **9S** *(pre-relocation)*. |
| F5-3 with not-wouldWin filter | Loop legal: KS rank K (not A/T), `wouldWin(KS) = true` (6 > 4) → filter rejects. 9S rank 9 (not A/T), wouldWin = false → eligible, TrickRank 3 → donate = 9S. 8S rank 8 (not A/T), wouldWin = false, TrickRank 2 < 3 → no update. Returns **9S** *(post-relocation, same value)*. |

**Pre-relocation behaviour:** Rule 1B fires first (F5-3 is dead),
returns 9S.

**Post-relocation behaviour:** F5-3 fires (its gates pass before
Rule 1B's), returns 9S after rejecting the wouldWin candidate KS.

**Both states return 9S** — same card. So **BF.7 PASSES BOTH
PRE- AND POST-RELOCATION** as a card-level assertion.

**Assert (regression-guard form):**
- `card == "9S"` (the not-wouldWin loser)
- `card ~= "KS"` (would-be steal candidate is NOT returned)

These together pin that:
- Whichever branch fires (pre-fix Rule 1B or post-fix F5-3), the
  result is the same non-stealing 9S.
- Post-relocation, the relocated F5-3 candidate loop's filter
  must reject KS. If the filter is ever removed in a future
  refactor, F5-3 would return KS (highest non-A/T without
  filter), failing this assertion.

**Why this isn't a wire-proof:** the test cannot, by card-level
observation alone, distinguish "Rule 1B fired and returned 9S
because F5-3 was dead" from "F5-3 fired and returned 9S because
the filter excluded KS." Both pathways produce the same observable
card. The accompanying source-pin in BF.8c (the `not wouldWin(c,
trick, contract, seat)` substring) provides the structural
proof that the filter exists in the new location; BF.7 provides
the behavioural proof that the filter's *effect* is to never
return a wouldWin candidate.

### BF.8 — Source-pin for v3.2.3 F5-3 marker + dead-block removal

```lua
local botSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Bot.lua"):read("*a")
assertTrue(botSrc:find("v3%.2%.3 F5%-3") ~= nil, "BF.8a: F5-3 marker")
assertTrue(botSrc:find("audit doc") ~= nil
    or botSrc:find("relocated from") ~= nil, "BF.8b: relocation noted")
-- The not-wouldWin filter must be present at the relocated F5-3 site.
assertTrue(botSrc:find("not wouldWin%(c, trick, contract, seat%)") ~= nil,
    "BF.8c: not-wouldWin filter present in relocated F5-3")
-- Critically: the OLD dead block at L4464-4491 must be REMOVED to
-- avoid two copies of the same logic. Pin that the dead block's
-- distinctive comment ("v1.4.1 (Concern 4 — Takbeer/Tasgheer
-- certainty gate") no longer appears anywhere.
assertTrue(botSrc:find("v1%.4%.1 %(Concern 4 — Takbeer/Tasgheer") == nil,
    "BF.8d: old dead block at L4464-4491 was removed (no duplicate copies)")
```

### BF.9 — F5-3 tie-randomization wired (closes v3.2.2-deferred F5 site)

> **v0.4 amendment (Codex fourth review):** F5-3 was originally
> identified by the v3.2.1 audit as a v3.2.2 tie-randomization
> candidate (F5/D-1: "4 inline highestByRank-shaped loops
> bypass tie randomization"). v3.2.2 deferred F5-3 specifically
> because the branch was unreachable. Relocating it into the
> live partnerWinning block here makes it reachable — so the
> relocation must ALSO close the tie-randomization gap, or the
> relocated branch would re-introduce a v1.1.0-class hand-order
> leak in newly-live code. BF.9 is the wire-proof that the
> relocated F5-3 uses `highestByRank(donate, contract)` (and
> hence `Primitives.pickRandomTied`) rather than a strict
> first-encountered loop.

**Fixture:** Sun, bidder seat 1 (team A), bot seat 3 (team A,
partner of seat 1). M3lm. Trick in progress: pos-1 = partner
seat 1 led `9S` (mid), pos-2 = opp seat 2 played `7S`. Partner
currently winning. `Bot._memory[4].void.S = true`. Bot at pos-3,
NOT lastSeat. Bot is **void in S** (must-follow doesn't apply →
all hand cards are legal discards).

Bot's hand: **`{KH, QH, KC, QC}`** — two K-high doubletons in
different non-led suits. The shape passes through Tahreeb
without returning:

- T-1 Bargiya: no A in any suit → doesn't fire.
- "Want, no Ace/no T" arm: every non-led suit has `#cards = 2`,
  not `>= 3` → doesn't fire.
- T-4 dump-ordering: each non-led suit is a 2-card doubleton,
  but `hi` is `K` in both → `hiRank == "K"` → T-4's high-value
  carve-out skips both suits (`if hiRank ~= "K" and hiRank ~=
  "T" and hiRank ~= "A"` — K-high doubletons fall through per
  v0.5.11's preservation gate at `Bot.lua:3730`).

F5-3 then fires. Building the `donate` pool from `legal = {KH,
QH, KC, QC}`:

- `KH`: not A/T, `wouldWin(KH)` = false in Sun (different suit
  from led `S`; non-led cards cannot match `leadSuit == "S"` in
  `R.CurrentTrickWinner`'s eligibility check) → eligible.
- `QH`: not A/T, not wouldWin → eligible.
- `KC`: not A/T, not wouldWin → eligible.
- `QC`: not A/T, not wouldWin → eligible.

`donate = {KH, QH, KC, QC}` (in hand iteration order).

`highestByRank(donate, contract)`:

- Pass 1 — find best rank: TrickRanks `K=6, Q=5, K=6, Q=5`.
  `bestR = 6`.
- Pass 2 — collect ties: `tied = {KH, KC}` (in iteration order
  through `donate`).
- `pickRandomTied(tied)` calls `math.random(#tied) =
  math.random(2)`. With the stub returning `2`, `tied[2] = KC`.

**Stub `math.random` deterministically** using the arity-aware
shim pattern already proven in AJ.12 / BE.1 / BE.2:

```lua
local origRandom = math.random
math.random = function(a, b)
    if a == 2 and b == nil then return 2 end
    if a == nil then return origRandom() end
    if b == nil then return origRandom(a) end
    return origRandom(a, b)
end
-- ... PickPlay call ...
math.random = origRandom
```

**Expected outcomes across implementation states:**

| State | Behaviour | Returned card |
|---|---|---|
| Pre-relocation (F5-3 dead) | Bot falls through to fallback `lowestByRank({KH, QH, KC, QC})`. Lowest TrickRank = `Q = 5`, tied set in iteration order = `{QH, QC}`. `pickRandomTied` with stub=2 → `tied[2] = QC`. | **QC** |
| Post-relocation with manual `donateRank` strict ranking (the BUG case Codex flagged) | First K encountered wins: KH (rank 6) > -1 → `donate = KH`. Subsequent K (KC, rank 6) NOT > 6 → skipped. Returns the first K by hand-iteration order. | **KH** |
| Post-relocation with `highestByRank(donate, contract)` (correct) | Builds donate pool, calls `highestByRank` which uses `pickRandomTied` over tied set `{KH, KC}`. Stub=2 → `KC`. | **KC** |

**Assert:** `card == "KC"`. This three-way distinction makes
BF.9 a strict wire-proof:

- Pre-relocation → returns QC → BF.9 FAILS.
- Post-relocation with the wrong (strict-ranking) implementation
  → returns KH → BF.9 FAILS.
- Post-relocation with the correct (highestByRank) implementation
  → returns KC → BF.9 PASSES.

Closes the v3.2.2-deferred tie-randomization gap at F5-3 as part
of making the branch reachable.

### Test count summary

| Test | Type | Role | Pre-relocation outcome | Post-relocation outcome |
|---|---|---|---|---|
| BF.1 | behavioural | **wire-proof** — F5-3 fires + correct card | FAIL (returns QH via fallback) | PASS (returns KH via F5-3) |
| BF.2 | behavioural | **wire-proof** — F5-3 fires regardless of partner-type | FAIL (returns QH via fallback) | PASS (returns KH via F5-3) |
| BF.3 | behavioural | regression — Tahreeb T-1 still wins overlap | PASS (Tahreeb already fires) | PASS (Tahreeb still first) |
| BF.4 | behavioural | regression (Interpretation A) — F5-3 doesn't override smother A-donate | PASS (smother already fires) | PASS (smother still first) |
| BF.5 | behavioural | regression — F5-3 doesn't fire without pos-4 void | PASS (F5-3 dead) | PASS (gate stops it) |
| BF.6 | behavioural | regression — F5-3 doesn't fire at non-pos-3 | PASS (F5-3 dead) | PASS (gate stops it) |
| BF.7 | behavioural | **regression-guard for filter** — bot doesn't return wouldWin candidate | PASS (Rule 1B returns 9S) | PASS (F5-3 returns 9S after filter) |
| BF.8 | source-pin (4 sub-asserts: 8a marker / 8b relocation-noted / 8c not-wouldWin filter substring / 8d dead-block-removed) | structural proof | **FAIL on all four** (8a/b/c: new markers not yet inserted; 8d: old dead block still present, so the `== nil` assertion fails) | PASS all 4 |
| BF.9 | behavioural | **wire-proof** — F5-3 tie-randomization (closes v3.2.2-deferred F5/D-1 site) | FAIL (returns `QC` via fallback `lowestByRank` with stub) | PASS (returns `KC` via `highestByRank` + `pickRandomTied` with stub=2) |

Total: **8 behavioural assertions + 4 source-pin sub-asserts = 12 new harness checks**.

Expected pre-relocation harness state when only the tests have
landed (no runtime edits): **exactly 7 failing checks** — BF.1,
BF.2, BF.9, BF.8a, BF.8b, BF.8c, BF.8d.

- BF.1 + BF.2 fail because F5-3 is still dead → bot returns `QH`
  via fallback instead of the expected `KH` via F5-3.
- BF.9 fails because F5-3 is still dead → bot falls through to
  fallback `lowestByRank` → with stub=2 returns `QC` (second
  tied low), not the expected `KC` (second tied high via
  `highestByRank` over the donate pool).
- BF.8a + BF.8b + BF.8c fail because the new v3.2.3 F5-3 markers
  / audit-ref / `not wouldWin` filter substring have not yet
  been inserted at the relocated position.
- BF.8d fails because the **old dead block at L4464-4491 is
  still present**; its source-pin asserts the distinctive
  substring `v1.4.1 (Concern 4 — Takbeer/Tasgheer` no longer
  appears (`botSrc:find(...) == nil`), which is false until the
  removal step.

Other five checks (BF.3, BF.4, BF.5, BF.6, BF.7) **PASS** pre-
relocation by design — they assert behaviours that exist whether
or not F5-3 is relocated (smother priority, Tahreeb overlap,
pos-4-void required, pos-3 required, no-steal regression).

Expected harness delta after both tests AND runtime fix land:
**1,245 → 1,257** (+12 BF.* checks all passing).

---

## §6 Risk register

| Risk | Likelihood | Severity | Mitigation |
|---|---|---|---|
| **F5-3 over-fires** (donates non-A/T in cases the original v1.4.1 author didn't intend, because the `#winners == 0` gate provided implicit narrowing in opp-winning context that's lost on relocation) | MED | MED — real gameplay change | BF.4 (pos4Void required) and BF.5 (pos-3 required) pin the explicit gates. If review identifies more cases needing narrowing, add a recomputed-in-partnerWinning equivalent of the `#winners == 0` semantic (e.g., "no card in our hand beats partner's current play"). |
| **Interpretation A vs B** ambiguity — original author may have wanted Interpretation B (override smother) and v3.2.3 ships Interpretation A | MED | LOW — both are documented Saudi-canonical plays; Interpretation A is the more conservative donation policy | Document both interpretations in the design doc + CHANGELOG entry. Codex reviews the choice. If Interpretation B becomes preferred, swap order in a follow-up. |
| **Tahreeb sender shadowing** — placing F5-3 between Tahreeb and Rule 1B (recommended) means F5-3 only fires when Tahreeb's `voidInLed + (T-1 shape or T-4 shape)` gates don't match. (Per v1.4.5, Tahreeb does NOT gate on partner-bot — it fires for both bots and competent humans.) | LOW | LOW | By design. Tahreeb's signal beats F5-3's donate when both apply. F5-3 covers cases where (a) we have led-suit cards and aren't void, or (b) we're void in led but hold neither a Bargiya-eligible A+cover nor a 2-card non-trump doubleton. |
| **F5-3 stealing partner's trick** (a non-A/T candidate in led suit could be a K/Q/J that wouldWin against partner's mid-card lead) | MED if filter absent | HIGH — converts a partner-winning trick to a self-steal, losing partnership EV | The relocated F5-3 candidate loop adds `not wouldWin(c, trick, contract, seat)` to the per-card filter (Codex amendment requirement §3). BF.7 pins this — a pre-amendment naive implementation would fail BF.7. |
| **F5-3 re-introducing v1.1.0 hand-order leak** by reactivating dead code without fixing the tie-randomization site that v3.2.2 deferred only because of unreachability | HIGH if not addressed | MED — predictability tell across rounds where ties occur, the exact pattern v1.1.0 retired | The relocated F5-3 uses a `donate` pool + `Primitives.highestByRank(donate, contract)` call rather than a strict-`>` `donateRank` loop. BF.9 is the wire-proof (three-way distinction: pre-relocation returns QC; post-relocation with strict ranking returns KH; post-relocation with the correct shape returns KC). Stop condition #10 forbids the strict-ranking shape during implementation review. Closes the v3.2.2-deferred F5/D-1 site at F5-3 as part of making it reachable. |
| **Dead-block removal at L4464-4491** is mandatory to avoid having TWO copies of the same logic (one unreachable, one live). Failing to remove leaves a future maintainer confused about which is canonical. | LOW (caught by source-pin) | MED if missed | BF.8d source-pin asserts the old block's distinctive comment (`v1.4.1 (Concern 4 — Takbeer/Tasgheer`) is gone via `botSrc:find(...) == nil`. |
| **F2 hold-back stays dead** through v3.2.3 ship. A user-facing reviewer might ask "why isn't the deception play live?" | LOW | LOW | CHANGELOG and design doc explicitly note F2 is deferred to a focused deception-play audit. |
| **The pos-3 partner-winning fixture is intricate** (seat 3 in a Sun trick with partner at seat 1 leading, pos-2 opp with a low card so partner wins, pos-4 opp known void via memory). Fixture bugs may cause silent test-pass / test-fail for wrong reasons. | MED | LOW | Each BF test pins ONE specific behavior. If BF.4/BF.5 negative tests pass with the same card as BF.1's positive (i.e., the gates aren't actually firing), the fixture is wrong — implementation stops. |

---

## §7 Stop conditions for implementation

The implementation branch must STOP and re-design (not silently
proceed) if any of:

1. **BF.1 or BF.2 passes before runtime relocation.** Both are
   wire-proofs — they assert `card == "KH"` while pre-relocation
   the bot returns `QH` via the `lowestByRank` fallback. If
   either passes pre-fix, the fixture is wrong (e.g., the
   `pos4Void` value is being read elsewhere, or the fixture is
   accidentally reaching F5-3's would-be code somehow).
2. **BF.4 fails post-relocation.** Smother's A-donate must still
   work — Interpretation A invariant. (Was numbered BF.3 in v0.2
   of this doc before BF.3 became the Tahreeb-overlap regression
   test in the post-Codex amendment.)
3. **BF.3 fails in either state.** Tahreeb T-1 Bargiya wins the
   overlap in BOTH pre- and post-relocation states (Tahreeb
   already runs before F5-3's location either way). A failure
   indicates a fixture bug or a broader Tahreeb regression.
4. **Tahreeb sender behaviour regresses against existing tests.**
   Any AS.* / AQ.* / AJ.* test that exercises Tahreeb fixtures
   must continue to pass — the relocation insertion point is
   AFTER Tahreeb's end (~L3737), so Tahreeb itself is unchanged.
5. **Harness count drops below 1,245** at any point.
6. **The old L4464-4491 block isn't removed** as part of the
   relocation. Two copies of the logic is a maintenance disaster
   waiting for the next refactor. BF.8d source-pins removal.
7. **F2 hold-back is touched.** This batch is F5-3 only. If
   review notices F2 should also be relocated, that's a separate
   v3.2.4+ batch with its own design pass.
8. **BF.7 fails post-relocation.** BF.7 is a regression-guard
   (not a wire-proof — see §5's BF.7 description and the v0.3
   amendment). It asserts the bot returns `9S` (not the would-
   steal candidate `KS`) in both pre- and post-fix states. A
   post-relocation failure indicates either the not-wouldWin
   filter is missing/broken OR the relocated F5-3 candidate
   loop's pool construction is off.
   > **Codex amendment §2:** removed the v0.2 stop condition
   > "BF.7 passes pre-relocation = failure" — that was a mis-
   > classification. Pre-fix, BF.7 passes because Rule 1B's own
   > not-wouldWin gate returns 9S anyway. The card-level
   > assertion alone can't distinguish "F5-3 fired with filter"
   > from "F5-3 was dead → Rule 1B fired"; the source-pin
   > BF.8c provides the structural distinction.
9. **The relocated F5-3 omits the `not wouldWin(c, trick,
   contract, seat)` filter.** Without it, F5-3 can steal
   partner's current trick when a non-A/T candidate is a same-
   suit K/Q/J. Codex amendment §3 requires the filter. BF.8c
   source-pins the substring.
10. **The relocated F5-3 uses a manual `donateRank` / `cr >
   donateRank` strict ranking loop** instead of building a
   `donate` pool and routing through
   `highestByRank(donate, contract)`. The old strict-rank
   pattern is exactly what v3.2.2 F5/D-1 retired at the side-
   Ace exhaustion site; re-introducing it in newly-live code
   would re-open the v1.1.0 hand-order leak. Codex amendment §1
   (v0.4) requires the pool + highestByRank shape.
11. **BF.9 passes pre-runtime** OR **BF.9 fails post-runtime.**
   BF.9 is the wire-proof for the tie-randomization shape (not
   just the regression-guard structure of BF.7). If BF.9 passes
   without the relocation, the fixture isn't actually exercising
   F5-3. If BF.9 fails after the runtime fix, either the
   `highestByRank` routing isn't in place OR the donate pool's
   ordering doesn't match the expected `{KH, QH, KC, QC}` →
   `{KH, KC}` tied set.

---

## §8 Recommended branch + commit shape

| Step | Action |
|---|---|
| 1 | Commit this design doc on `main`: `docs: add v3.2.3 pos-3 Sun relocation design` |
| 2 | Branch `pos3-sun-relocation-v3.2.3` off `main` |
| 3 | Tests first: write BF.1–BF.9 in section BF of `tests/test_state_bot.lua`. Pre-runtime-edit expected: BF.1 + BF.2 + BF.9 + BF.8a-d FAIL (**7 fails**); BF.3 + BF.4 + BF.5 + BF.6 + BF.7 PASS. Confirm exactly 7 fails, not more. |
| 4 | Runtime: REMOVE the dead L4464-4491 block. ADD the relocated F5-3 between Tahreeb sender end (~L3737) and Rule 1B start (~L3739). **Required shape:** a `donate` pool collected by `for _, c in ipairs(legal)` with `r ~= "A" and r ~= "T" and not wouldWin(c, trick, contract, seat)`, then `if #donate > 0 then return highestByRank(donate, contract) end`. Do NOT use a manual `donateRank` / `cr > donateRank` strict ranking loop — that would re-introduce the v1.1.0 hand-order leak BF.9 explicitly catches. |
| 5 | Run harness — expected 1,257 / 0 (+12 BF.* checks) |
| 6 | Standalone smokes — expected 11 / 9 / 0 |
| 7 | Commit: `fix(Bot.lua): relocate F5-3 pos-3 Sun Takbeer donate above Rule 1B` (commit message should also mention closing v3.2.2-deferred F5/D-1 tie-randomization at this site) |
| 8 | Stop for Codex review |

Expected files changed:
- `Bot.lua` (delete ~28-line dead block at L4464-4491; insert ~25-line relocated block at ~L3738)
- `tests/test_state_bot.lua` (append BF section, ~150 lines)

NO changes to: `BotMaster.lua`, `WHEREDNGN.toc`, `.pkgmeta`, workflows, `Net.lua`, `State.lua`, `Rules.lua`, `Cards.lua`, `UI*`, etc.

---

## §9 Codex-resolved decisions

> **v0.2 amendment (post-Codex review):** the v0.1 doc closed
> with four open questions for review. Codex resolved all four
> as follows; the doc now reflects the resolved answers as the
> approved design.

1. **Interpretation A vs B for F5-3 →** **Interpretation A
   approved.** F5-3 supplements smother; it does NOT override
   smother's A/T/K/Q/J donation. The relocated F5-3 fires only
   when smother fell through (typically: no point cards in led
   suit, or feedSafe gate failed).
2. **F2 deferral timing →** **F2 remains deferred to v3.2.4+.**
   The deception-play test framework will be designed in a
   focused later audit. v3.2.3 ships F5-3 only.
3. **Tahreeb shadowing →** **F5-3 does NOT require partner-bot.**
   The v0.1 doc's premise that Tahreeb gates on partner-bot was
   stale (v1.4.5 removed that gate). Both Tahreeb and F5-3 fire
   regardless of whether partner is a bot or a human. Tahreeb
   takes precedence on overlap via placement order (Tahreeb
   first, F5-3 second).
4. **`#winners == 0` semantic →** **Replace with an explicit
   `not wouldWin(c, trick, contract, seat)` candidate filter in
   the relocated F5-3 loop.** This preserves the original
   "highest loser / donate to partner's pile" intent and
   prevents F5-3 from stealing partner's current trick when a
   non-A/T candidate is a same-suit K/Q/J. BF.7 is the
   **post-implementation regression-guard** for this filter
   (not a wire-proof — per the v0.3 amendment, the same card
   `9S` is returned in both pre- and post-relocation states,
   because Rule 1B has its own not-wouldWin gate; BF.8c's
   source-pin of the literal substring provides the structural
   proof that the filter exists in the new location).

All four resolutions are now woven into §4.1's proposed code
snippet, §4.2's ordering rationale, §5's test plan (especially
BF.3 and BF.7), §6's risk register, and §7's stop conditions.

> **v0.4 amendment — fifth resolved decision (Codex fourth
> review):**
>
> 5. **Tie-randomization in the relocated F5-3 →** **MUST use
>    a `donate` pool + `Primitives.highestByRank(donate,
>    contract)` call, NOT a strict `donateRank` / `cr >
>    donateRank` loop.** F5-3 was one of the v3.2.2 F5/D-1
>    audit's enumerated tie-randomization sites; v3.2.2
>    deferred it ONLY because the branch was unreachable. By
>    relocating into the live partnerWinning block, the branch
>    becomes reachable, so the tie-randomization fix must
>    accompany the relocation — otherwise the v1.1.0 hand-order
>    leak re-opens in newly-live code. BF.9 is the wire-proof
>    (three-way distinction: pre-relocation returns QC,
>    post-relocation with strict ranking returns KH,
>    post-relocation with `highestByRank` returns KC — the
>    expected card). Stop condition #10 additionally forbids
>    the strict-ranking shape during implementation review.

Stop here for further Codex review on the amended doc. No code
written. No branch created. No tag.
