# D-RT-24 — v0.10.2 M8 Sun bidder-team mardoofa probe lead — **OPPONENT-PERSPECTIVE** information-leak probe

Track-D red-team probe of v0.10.2 M8 (`Bot.lua` `pickLead` lines 1806-1823) from the **opponent's** perspective. Sister doc to D-RT-10 (which red-teamed M8 from the BIDDER's perspective: gating, pre-conditions, internal correctness). This file specifically asks: *"If I am the opponent at the table, how badly does M8 leak the Sun-bidder team's hand, and how do I exploit it?"*

Files inspected (read-only):
- `C:\CLAUDE\WHEREDNGN\Bot.lua` lines 40-55 (`Bot.IsAdvanced`), 110-130 (`emptyMemory`), 340-440 (`Bot.OnPlay` memory updates), 1520-1535 (`lowestByRank`), 1703-1823 (`pickLead` head + M8 branch), 2336-2400 (singleton-low + Sun shortest-suit-low fallthroughs), 3372-3402 (`Bot.PickPlay` master delegation)
- `C:\CLAUDE\WHEREDNGN\BotMaster.lua` lines 1-130 (sampler bias maps), 198-440 (`sampleConsistentDeal` — ISMCTS posterior conditioning)
- `C:\CLAUDE\WHEREDNGN\tests\test_state_bot.lua` lines 1645-1677 (J.2 M8 pins)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-10_m8_mardoofa_probe.md` (sister doc)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-Bot-04_pickLead_m8.md` (Track-B implementation review)

The branch under attack (`Bot.lua` 1806-1823):

```lua
if Bot.IsAdvanced() and contract.type == K.BID_SUN
   and trickNum == 1
   and contract.bidder
   and myTeam == R.TeamOf(contract.bidder) then
    local hasA = { S = false, H = false, D = false, C = false }
    local hasT = { S = false, H = false, D = false, C = false }
    local aceCard = { S = nil, H = nil, D = nil, C = nil }
    for _, c in ipairs(legal) do
        local r, su = C.Rank(c), C.Suit(c)
        if r == "A" then hasA[su] = true; aceCard[su] = c
        elseif r == "T" then hasT[su] = true end
    end
    for _, su in ipairs({ "S", "H", "D", "C" }) do
        if hasA[su] and hasT[su] and aceCard[su] then
            return aceCard[su]
        end
    end
end
```

---

## A1 — First-trick observability: an Advanced+ A-led on trick 1 of Sun is a near-perfect mardoofa tell

### Feasibility: HIGH

The opponent observation is trivial and requires no inference machinery:
- Trick 1 is publicly observable. Every seat sees the leader's card.
- Lead seat = `(s.dealer % 4) + 1` (`Net.lua:2020`) — known to all seats from the dealer.
- Bidder identity is public (announced at end of bidding).
- Opp can compute `R.TeamOf(leader) == R.TeamOf(bidder)` themselves.
- M8 itself is open-source (`Bot.lua` 1806-1823). Any opp human reading the addon source can predict it.

**Information leaked when the led card is an Ace from a bidder-team leader:**

| Observable | Inference confidence |
|---|---|
| Bidder team holds A♠+T♠ (if A♠ led) | **~95% in a "pure M8 fire"** — only 1 of 3 fall-through paths can also lead an Ace, and those have other-suit confounds (see A4) |
| Bidder team has length ≥ 2 in suit X | ~80% (mardoofa often + side cards) |
| Bidder team's other-suit Aces (if any) lack a T-cover | ~70% (otherwise M8 would have picked them under `{S,H,D,C}` tiebreaker; only the multi-mardoofa edge case violates this) |
| Bidder team voluntarily declined "shortest-suit-low" probe | 100% (definitionally) |

The first three rows are bidder-team-level inferences; the actual T♠ may sit in either the bidder's hand or the partner's hand. From an opp's perspective, "the bidder-team holds T♠" is locatable to the team (2 seats), not to a specific seat. That's still a 50% hit rate on a per-seat T♠ guess, vs. the no-information baseline of ~25% (unseen card distributed across 3 unknown seats — but Saudi pro inference of "bid → strong cards weighted to bidder team" already pushes baseline closer to 30-40%).

### EV impact: MEDIUM-HIGH against skilled opps

The leak is most damaging in three ways (see A2 for counter-strategy detail). Net-ish estimate, no calibration data: **−5 to −15 face-value points per Sun hand** against M3lm+ opps who actively read the lead. **−0 against random-legal Basic opp** (no inference layer). Sun's ×2 multiplier amplifies all of this.

### Recommendation

**Documentation only — no code change in M8 scope.** The opp-perspective leak is a structural consequence of the Pro-2 §2 mandate; M8 implements the source faithfully. The proper response is one of:
1. **Calibration A/B** — prove or disprove the net EV is positive over many deals (D-RT-10-r6 already flags this).
2. **Source-arbitration** — interpret Pro-2 §2 as not applying when bidder-team faces strong opp inference (no source text supports this carve-out, but the doubled-contract analogy from PickAKA L3 line 3332 is the closest precedent — see A8).
3. **Strategic suppression** — a future M8.1 could fall through to shortest-suit-low when both opps are M3lm+ tier (info leak read) but stay aggressive when both opps are Basic (info leak unread). This requires reading opp tier into bidder logic, which is a clean code-side change but a strategic-side decision.

---

## A2 — Counter-strategy: opp targets inferred T♠ for capture

### Feasibility: HIGH (against bot opps Advanced+); MEDIUM (against humans)

Once opp infers "T♠ sits with bidder team," the T♠ becomes a **high-value capture target** (Sun: T = 10 face value, +10 last-trick bonus if won on trick 8, ×2 from Sun multiplier = up to 40 effective points if T♠ falls on a captured trick).

**Concrete counter-play (Sun, no trump):**

1. **Opp withholds A♠** (if held) on trick 1 even when forced to follow suit. Opp knows: "bidder's A♠ is naked once T♠ falls; if I keep my A♠, I'm the boss in spades for trick 2+ once the bidder's T♠ is gone." Opp plays a low spade on trick 1, taking the loss to set up the trump.
2. **Opp leads spades back on tricks 2-3** when on lead, forcing bidder team to play T♠ (now naked-low, no cover behind it). Capture probability rises sharply: bidder-team's T♠ is sandwiched between opp's A♠ and opp's other spades.
3. **Opp's K♠/Q♠ become offensive tools** — without M8, K♠/Q♠ are pure defensive winners; with M8, they're trick-killers that can fish out the bidder's T♠.

### Code-side check: does the bot opp actually do this?

Looking at `Bot.OnPlay` (lines 340-440) — the only memory-update path:
- `mem.void[suit]` set on void inference (didn't follow suit).
- `mem.firstDiscard` recorded on first off-suit discard (Fzloky signal).
- `mem.played[card]` flagged.
- **No "trick-1 Ace-led-by-bidder-team → mardoofa-suit inferred" hook.**

Bot opps do NOT structurally update `_memory` to record "the bidder team has a mardoofa in suit X" after observing the M8 lead. The information is *technically* recoverable from `S.s.tricks[1].plays` later (an M3lm+ opp's pickFollow could re-derive it), but no current code path does so.

**Saudi Master ISMCTS sampler**: `sampleConsistentDeal` (`BotMaster.lua` 198-440) builds determinizations from:
- Bid card pin (`pinCard = S.s.bidCard`, line 220-228)
- Meld card pins (line 242-260)
- H-1 trump-J/9 pin to Hokm bidder (line 271-283)
- Pigeonhole trump pin (line 293-318)
- `desire` maps for bidder/defender/partner roles (`getStrongCards`, `getDefenderCards`, `getPartnerCards`)

**Crucial finding:** the sampler does NOT consume `S.s.tricks[1]` for posterior conditioning. There is no code path where "this seat led A♠ on trick 1 of Sun" updates the sampler's prior. The `desire` weights are bid-context-only, computed once per `sampleConsistentDeal` call; they reflect the bidder-side strong-card concentration but not the trick-1 lead observation.

### EV impact

- **Against human opp** (most realistic adversary): humans CAN read M8 if they know the addon's M8 rule. Saudi-pro humans likely already know the mardoofa-lead convention; M8 just makes the bot do it consistently. Net: HIGH leak against any opp who knows pro Saudi conventions, MEDIUM against casual humans, ZERO against random.
- **Against bot opp** (any tier): the bot does NOT exploit the leak via `_memory`. Saudi Master sampler ignores trick-1 observations beyond bid-card pinning. So a 4-bot table running M8 + Saudi-Master opps is the **safest** scenario — leak generated, leak unread. **This is a critical asymmetry**: M8 is most exploitable against humans, least exploitable against bot opps.

### Recommendation

**Two missing inference hooks (out of M8 scope but adjacent):**

1. **`Bot.OnPlay`** could add: if `trickNum == 1` AND `contract.type == K.BID_SUN` AND lead-card is an Ace AND lead-seat is on bidder team AND `Bot.IsAdvanced()` (mirror M8's tier gate) → set `mem.suspectedMardoofaSuit = leadSuit`. This makes the bot opp **symmetric-aware** of M8.
2. **`BotMaster.sampleConsistentDeal`** could pin the inferred T (mate of led A) to the bidder-team seats with a high `desire` weight. Concrete: if `mem.suspectedMardoofaSuit == "S"`, then `desire["TS"] = 50` for bidder-team seats. This pins T♠ to the bidder team in ~95% of sampled determinizations, accurately reflecting M8's leak.

Without these hooks, M8 systematically advantages bot opps (no exploit) and disadvantages human opps (full exploit). The asymmetry is **not** in the source text (Pro-2 §2) but is a code-architecture artifact.

**Severity: MEDIUM (Strategic).** The fix is one-sided: only opps need the inference; the bidder side already plays correctly. But it's beyond M8 scope and arguably belongs to a separate "opp inference symmetry" patch.

---

## A3 — Bot self-defense: zero randomization, zero 50/50 mixing

### Feasibility of detecting deterministic behavior: TRIVIAL

M8 is **fully deterministic**:
- `for _, su in ipairs({ "S", "H", "D", "C" })` is the same iteration every time.
- `aceCard[su]` is captured from the per-suit scan; no random tie-break.
- No `math.random()` call inside lines 1806-1823.
- No "skip M8 with 30% probability and lead shortest-suit-low instead" mixing.

**Result**: an opp who observes "this Saudi-Master bot, given hand H, leads A♠ on trick 1 of Sun" can predict, for any other hand H', exactly what M8 will do. Repeat-game observability is total.

### Why deterministic is a problem

In poker theory and signal-game theory, **deterministic strategies are exploitable**. A randomized mix (e.g. 70% lead mardoofa-Ace, 30% lead shortest-suit-low even with mardoofa available) would degrade opp inference confidence from ~95% to ~67%. The bidder-side EV cost of the 30% suboptimal play might be smaller than the EV cost of the 95% leak — but this requires calibration.

Pro-2 §2 says "MUST" / "obligatory" (إجبارية), which appears to forbid randomization at the source level. So the Saudi-pro convention is non-mixed by author intent. M8's determinism is source-faithful.

### Bot self-defense alternatives considered (none implemented)

| Defense | Bidder EV cost | Leak reduction | Source-justifiable? |
|---|---|---|---|
| 50/50 between mardoofa-Ace and shortest-suit-low | High (50% wrong) | High (drops to ~50% from ~95%) | No (Pro-2 §2 unconditional) |
| 90/10 mix (rare bluff) | Low | Modest (~85% from ~95%) | No (Pro-2 §2 unconditional) |
| Mix only when both opps are M3lm+ | Conditional | Conditional | Defensible (rule applies to "playing well", arguably not vs. random) |
| Doubled-contract suppression (mirror PickAKA L3) | High | Total (in doubled rounds) | Analogically defensible (D-RT-10-r5) |

None are coded. Saudi Master ISMCTS won't "discover" randomization by itself because M8 is encoded in the rollout policy (`pickLead`), not searched at the leaf — every rollout from `BotMaster.PickPlay` will deterministically land on the mardoofa-Ace lead.

### Recommendation

**Severity: LOW (single-source rule, faithfully implemented).** No code change. But worth a code comment in the M8 block: `-- Pro-2 §2 mandates deterministic mardoofa-Ace lead. No randomization despite information-leak cost — see D-RT-24 for opp-perspective analysis.`

---

## A4 — NOT-Sun-seat-1 bidder leads happen to be A: the **confound** that masks M8

### Feasibility: HIGH — there are TWO non-M8 paths in `pickLead` that ALSO lead an Ace in Sun

Reading the full Sun-leader fallthrough chain in `pickLead`:

| Branch | Line | Conditions | Could lead an Ace? |
|---|---|---|---|
| Sweep pursuit | 1709-1788 | trick 8 OR sweep-pursuit-early (trick 3-7, all prior tricks won) | trick 1: NO (gate `trickNum >= 3`) |
| **M8 mardoofa probe** | **1806-1823** | **bidder team, trick 1, Sun, has A+T mardoofa** | **YES — A of mardoofa suit** |
| Tahreeb pref | 1855-1944 | M3lm-only, partner Tahreeb signal | `lowestByRank(fromPref)` — could be Ace if shortest |
| Fzloky pref | 1946-1973 | Fzloky-only, partner first-discard signal | `lowestByRank(fromPref)` — could be Ace |
| Singleton-low | 2336-2369 | any singleton (no rank guard in Sun, only Hokm) | **YES — singleton A returns A via lowestByRank** |
| Sun shortest-suit-low | 2371-2400 | Advanced-only, Sun, fall-through | **YES — if shortest suit IS a singleton-A or has A as lowest, lowest is A** |
| Low from longest | 2402-2441 | non-empty nonTrumps | only if longest non-trump suit's lowest IS the Ace (rare) |

**Three distinct paths can lead an Ace from a bidder-team leader on trick 1 of Sun:**

1. **M8** — bidder has A+T same suit.
2. **Singleton-A** — bidder has a singleton A (any suit, no T behind). Returns the singleton A via `lowestByRank` (line 2365).
3. **Shortest-suit happens to be {A only}** — same as #2 but reached via the Sun shortest-suit branch (line 2389-2398).

Cases #2 and #3 OVERLAP: a singleton-A in any non-trump suit hits #2 first (line 2352 — `if #singletons > 0`). The Sun shortest-suit branch (line 2379) is reached only if the singleton branch fell through, which only happens if there's no singleton at all (`#singletons == 0`). So in practice the false-positive paths are:

- **Singleton-A (most common)**: any A-containing suit with exactly 1 card.
- **Multi-card suit lowest = A** (rare): impossible if the suit has any rank ≥ 7 (since A is highest), so this only fires on a degenerate suit count = 1 case (= singleton-A again).

**Wait** — `lowestByRank` is "lowest by `C.TrickRank`". TrickRank in Sun: A is HIGHEST (rank 8), 7 is LOWEST (rank 1). So `lowestByRank` of `{AS}` returns AS only because there's no choice. If the legal set is `{AS, 7S}`, `lowestByRank` returns 7S, not AS. So **the multi-card-suit branch never returns an Ace** — only singleton suits do.

This narrows the false-positive cases to **just one**: a bidder-team leader with a SINGLETON-A in any non-trump suit (Sun has no trump, so any suit). M8 returns its mardoofa-A first; if no mardoofa, the singleton branch returns the singleton-A.

### Confound severity for opp inference

When opp sees A♠ led by bidder-team leader, the opp can refine inference:

| Bidder hand shape | Probability of A♠ lead |
|---|---|
| A+T mardoofa in spades, no other constraint | ~100% (M8) |
| Singleton-A♠, no other singletons | ~100% (singleton branch) |
| Singleton-A♠ AND mardoofa in another suit (e.g. A♥+T♥) | M8 fires first → A♥ leads, NOT A♠. So singleton-A♠ alone fires only if no mardoofa exists. |
| Singleton-A♠ AND mardoofa in spades | Impossible — mardoofa requires A+T in spades, which is a 2-card suit, not singleton. |

So the confound is: A♠ lead can mean **either** "bidder has A♠+T♠ (M8 mardoofa)" **or** "bidder has bare A♠ singleton" (Sun, no other singletons, no mardoofa anywhere). These are **opposite** dispositions — M8 means bidder has length AND a T cover; singleton means bidder has zero length AND no cover.

### Opp counter-counter-strategy

A skilled opp must distinguish:
- **M8 hypothesis**: T♠ is in bidder team. Withhold A♠ (if held), bait the T♠.
- **Singleton hypothesis**: T♠ may be ANYWHERE (likely opp side). DON'T withhold A♠; play it on the led suit to win the trick now.

Distinguishing requires Bayesian updating:
- Prior P(mardoofa in some suit | bidder bid Sun) ~ 0.6 (Sun bids often correlate with mardoofa-pair presence — see `K.BOT_SUN_MARDOOFA_BONUS`).
- P(mardoofa in spades | mardoofa in some suit) ~ 0.4 (4 suits, ~uniform with slight {S,H,D,C} bias if multi-mardoofa).
- P(singleton-A♠ | bidder bid Sun) ~ 0.05 (singletons are rare in Sun bids — Sun bids typically need length).

Posterior given A♠ leads: P(M8 | A♠ led) >> P(singleton | A♠ led). Opp's best bet is the M8 hypothesis. The confound exists but is overwhelmed by the prior.

### Recommendation

**Severity: LOW (the confound is real but minor).** The leak is mostly intact; opp's posterior on T♠ being bidder-side is still ~85-90% even after accounting for the confound. M8's information cost is not significantly diluted by the singleton path.

If a future defender wants to **maximize confound**, they could:
- Add a "fake mardoofa probe" branch that occasionally leads a singleton-A in the same scenario where M8 would. But this is bidder-side strategy obfuscation, not M8 scope.

---

## A5 — Saudi-Master tier opp models bot M8 behavior; lower tiers don't

### Feasibility of bot exploit: ZERO at any current tier

Reading `BotMaster.lua` `sampleConsistentDeal` lines 198-440, plus `Bot.OnPlay` lines 340-440 — there is **NO** posterior-update hook anywhere in the codebase that:
- Reads `S.s.tricks[1].plays[1]` to detect a trick-1 Ace lead.
- Conditions sampling weights on "is this an M8 mardoofa probe?"
- Sets a `mem.mardoofaSuspected[seat]` flag.

The Saudi Master sampler weighting (lines 39-129) uses:
- `getStrongCards(contract)` — bid-context only.
- `getDefenderCards(contract)` — Hokm-only side-Ace clustering.
- `getPartnerCards(contract)` — bidder-partner trump bias + Sun-partner Ace bias.

None of these inspect actual played cards beyond `pinCard` (the bid card). The trick-1 mardoofa lead is **invisible** to the Saudi-Master sampler.

This means:
- Saudi Master opp does NOT sample T♠ to bidder team with elevated probability after seeing A♠ led.
- M3lm opp's `_partnerStyle` ledger does NOT track mardoofa observations.
- Fzloky opp's `firstDiscard` is for a different signal (off-suit lead, not on-suit lead).
- Advanced opp has no inference layer for trick-1 leads at all.

### Tier dispatch confirmation

`Bot.PickPlay` (line 3372-3402) routes Saudi Master → `BotMaster.PickPlay` (delegation), then heuristics. M3lm/Fzloky/Advanced all use the same `pickFollow` heuristics, with only `Bot.IsM3lm()` / `Bot.IsFzloky()` gating their respective signal-readers.

Lower tiers (Basic) don't even have an inference layer; they play random-legal.

### EV impact

Bot vs bot: M8 is a **cost without benefit**. The bidder-team bot incurs the leak; the opp bot does not exploit it. Net EV of M8 is therefore **bounded above by zero in all-bot tables**.

Bot vs human: depends on the human's awareness of the M8 rule and Saudi pro conventions. Sophisticated humans capture the leak; casual humans don't.

### Recommendation

**Severity: HIGH (Strategic + Calibration).** The current state of the addon is:
- Sun bidder bot: pays full leak cost (M8 lead).
- Sun opp bot: pays zero exploitation reward (no posterior update).
- Net: M8 is a strict negative-EV change in 4-bot tables.

This deserves either:
1. **Code-side fix** (out of M8 scope): add the inference hooks described in A2 so opp bots become symmetrically aware. Once opp bots can exploit the leak, the M8 EV trade-off becomes a real strategic question (probe value gained vs. capture cost given opp can read).
2. **Calibration**: run 4-bot tables, M8-on vs. M8-off, measure bidder-team Sun-pass rate. If M8-on shows lower pass rate (because leak isn't yet exploited but probe value also requires partner-side reading that may not exist either), escalate to source-arbitration on whether Pro-2 §2 should fire at the addon's current sophistication level.

---

## A6 — Multi-pair edge: A♠+T♠ AND A♥+T♥ — which gets led?

### Feasibility of inference: HIGH

Per `Bot.lua` line 1818: `for _, su in ipairs({ "S", "H", "D", "C" })`. The for-loop returns the FIRST suit with a matching A+T pair. Spades wins ties.

**Multi-mardoofa hand example**: bidder holds `{ AS, TS, KS, AH, TH, KH, JD, 8C }`. Two mardoofas (♠ and ♥). M8 returns AS.

### Opp inference refinement

If opp knows the M8 rule + the iteration order is `{S,H,D,C}`, then observing **A♠ led** allows opp to deduce:
- "Bidder has A♠+T♠." (M8 fires.)
- "Bidder MAY ALSO have A♥+T♥ (or other lower-priority mardoofa)." Opp can't distinguish single-mardoofa-in-spades from multi-mardoofa-with-spades-first.

But observing **A♥ led** allows opp to deduce:
- "Bidder has A♥+T♥."
- "Bidder does NOT have A♠+T♠." (Else spades would have won the tiebreaker.)

So **A♥/A♦/A♣ leads are MORE INFORMATIVE than A♠ leads**: they exclude all higher-priority mardoofas. A♣ lead is the most informative ("bidder has A♣+T♣ and no other mardoofa anywhere").

### Concrete leak quantification

| Lead observed | Mardoofas certain | Mardoofas excluded |
|---|---|---|
| A♠ | A♠+T♠ | (none) |
| A♥ | A♥+T♥ | A♠+T♠ |
| A♦ | A♦+T♦ | A♠+T♠, A♥+T♥ |
| A♣ | A♣+T♣ | A♠+T♠, A♥+T♥, A♦+T♦ |

A♣ lead leaks **four** facts to the opp (one positive, three negative) — strictly more than A♠ lead's one fact.

### EV impact

Opps targeting later-suit leads (A♥/A♦/A♣) extract more cross-suit information — they can play their own A♠/A♥/A♦ aggressively in unled suits, knowing the bidder lacks the matching T cover.

### Recommendation

**Severity: LOW-MEDIUM.** The leak amplification by suit order is a known consequence of deterministic tiebreakers. Two mitigations:
1. **Randomize the multi-mardoofa tiebreaker**: pick a random suit among the mardoofas (uniform). This loses the cross-suit elimination inference (opp can't deduce ♠ absent when ♥ leads, because the choice was random).
2. **Pick by a non-cross-eliminating heuristic**: e.g., longest-mardoofa-suit (length tells the opp something but doesn't eliminate other suits). Defensible — a "longer probe = more discovery" rationale.

Pro-2 §2 is silent on multi-mardoofa tiebreaker, so either is source-permissible. Track-B M8-i1 already flagged the hardcoded order as arbitrary; this finding strengthens the case for randomization specifically.

**This is the single best defender-side mitigation in M8 scope** — it preserves the rule (always lead a mardoofa-Ace) while reducing cross-suit leak. No bidder-side EV cost (the rule still fires), only opp-side EV reduction.

---

## A7 — Test pin existence: deterministic lead choice

### Feasibility of regression: MEDIUM

`tests/test_state_bot.lua` lines 1645-1677 (J.2):
- **Positive pin (line 1666-1667)**: bidder seat 2 with A♥+T♥ mardoofa → expects `AH` lead. PINNED.
- **Negative pin (line 1675-1676)**: defender seat 1 with A♥+T♥ → expects `7C` (shortest-suit-low). PINNED.

**NOT pinned:**
- **Multi-mardoofa**: no test asserts that `{ AS, TS, AH, TH, ... }` → `AS` (spades wins). A future refactor could silently flip to `AH` and break no test.
- **Partner-of-bidder leader**: no test asserts that `bidder=2, dealer=4 → leader=1, partner=4 leads`. A future refactor could break partner-side coverage silently.
- **Tier-off**: no test asserts that `Advanced=false` → falls through to 7C. Already noted in D-RT-10-r3.

### Adversarial test: opp-perspective regression

**No test exists** for the opp-perspective inference. Specifically:
- No test asserts that an opp bot, observing a trick-1 A♠ lead from a bidder, updates its `_memory` or sampler bias. (Because no such code exists.)
- No test asserts that the bidder's A♠ lead is observed correctly in `S.s.tricks[1].plays[1].card == "AS"` — though this is an indirect side effect of the play system, not a dedicated M8 leak test.

The lack of opp-perspective tests is consistent with the absence of opp-perspective inference logic. If A2's recommendation (add inference hooks) were implemented, new test pins would be needed for both sides.

### Recommendation

**Severity: MEDIUM (Test gap).** Recommend adding at minimum:
1. **Multi-mardoofa pin** (closes Track-B M8-i1 + D-RT-24-r4): assert deterministic `{S,H,D,C}` tiebreaker.
2. **Opp-observation pin** (if A2 hooks added): assert that an opp bot's `_memory` records the M8 mardoofa observation.

---

## A8 — Probe-lead vs partner reading: info wasted against human partner

### Feasibility: HIGH (asymmetry exists)

Pro-2 §2's mardoofa-Ace lead is described as a **probe** — the bidder leads "the backed slam" to:
1. Tell partner: "I have this mardoofa; coordinate."
2. Test opp: "Who else has length here? Force discovery."

The probe value is realized when:
- Partner reads it and adjusts (plays low in the led suit, preserves their own A's elsewhere).
- Opp reveals length via forced follow-suit play.

### Code-side: does the bot partner read M8?

Let me trace what happens on trick 1 after M8 fires:
- M8 leads A♠.
- Partner is on bidder team, follows lead suit.
- `pickFollow` is called for partner (bidder team).
- Partner has to play a spade (forced if any spade in hand).

**Is there an M8-aware partner-side branch?** Searching `Bot.lua` for "mardoofa" — only the bidding-side bonus (`K.BOT_SUN_MARDOOFA_BONUS`) and the M8 lead branch itself. No `pickFollow` branch reads "partner-just-led-mardoofa-Ace, I should preserve T♠ if I hold it."

So:
- **Bidder leads A♠** (M8 mandate, ~100% on bidder side).
- **Partner follows mechanically** — plays lowest spade, or whatever the existing `pickFollow` heuristics dictate. **No "preserve T♠" logic.**
- **Opp follows** — plays lowest spade or A♠ if held (existing `pickFollow` heuristics).

If the partner happens to hold T♠, the partner has no awareness that the bidder just signaled "I want you to know we have a mardoofa." The probe's coordination value is **wasted on the bot partner**.

### Symmetry with A2's opp-perspective gap

This is the same architectural gap as A2 but on the partner side. M8 leaks information to opps AND signals partner — both depend on a downstream inference layer that doesn't exist. The bidder's "probe" is an empty gesture in 4-bot tables: no one reads it.

The probe is realized only against:
- **Human partner** who knows the M8 rule and Saudi conventions: they read the signal, preserve T♠, coordinate.
- **Human opp** who knows: they exploit the leak.

Both readers must be human for M8 to have its intended dual nature (signal partner + probe opp). If only opp is human, M8 is a pure cost. If only partner is human, M8 is a pure benefit. If both are bots, M8 is a no-op (probe wasted, leak unread).

### EV impact: depends on table composition

| Table | Bidder-side EV of M8 |
|---|---|
| 4-bot (all Saudi Master) | **Negative or zero** (probe wasted, leak unread → maybe slight negative if singleton-A confound exists, else zero) |
| Bidder bot, partner bot, both opps human | **Strongly negative** (leak fully read, signal wasted) |
| Bidder bot, partner human, both opps bot | **Positive** (signal read by partner, leak unread by opps) |
| All human + 1 bot bidder | **Mixed** (depends on opp/partner skill ratio) |
| Bidder bot, partner bot, 1 opp human, 1 opp bot | **Slightly negative** (1/2 leak read, signal wasted) |

**No code path exists to detect or condition on table composition.** M8 fires uniformly. So the addon ships M8 with negative EV in the most common case (fully bot table, where the addon is most likely deployed for AFK/practice).

### Recommendation

**Severity: HIGH (Strategic, Calibration-dependent).**

The cleanest strategic-level fix would be:
1. **Add partner-side M8 awareness**: in `pickFollow`, when partner is on bidder team and trick 1 of Sun shows an Ace lead from partner-of-our-team and we hold the matching T, **preserve the T**. This realizes the probe's signal value on the bot partner side. **In M8 scope** in spirit, but technically a pickFollow change.
2. **Add opp-side M8 awareness** (A2): symmetric.
3. **Calibrate** before either of (1) or (2): is the bidder-team Sun-pass rate actually different M8-on vs M8-off? If not, M8 is a no-op and the strategic asymmetry is moot.

---

## Summary table — opponent-perspective findings

| ID | Severity | Question | Issue | Recommendation |
|---|---|---|---|---|
| **D-RT-24-r1** | Medium-High (Strategy) | A1 | Trick-1 A-lead by bidder-team leader leaks mardoofa suit to skilled opps with ~95% confidence after singleton-A confound is accounted for. Faithful to Pro-2 §2; cost is real. | Calibration A/B; doc note about leak. |
| **D-RT-24-r2** | Medium (Code-architecture) | A2, A5 | Bot opps do NOT structurally update `_memory` or ISMCTS sampler weights to exploit the leak. M8 advantages bot opps (they ignore the leak) but disadvantages human opps. Asymmetric. | Out-of-M8: add inference hook in `Bot.OnPlay` and pin in `BotMaster.sampleConsistentDeal`. |
| **D-RT-24-r3** | Low | A3 | M8 is fully deterministic, zero randomization. Pro-2 §2 mandates this; randomization not source-justifiable. | Doc comment; no code change. |
| **D-RT-24-r4** | Low-Medium (Strategy + Test) | A6 | Multi-mardoofa tiebreaker is deterministic `{S,H,D,C}` order. Later-suit leads (A♥/A♦/A♣) leak strictly MORE than A♠ (cross-suit elimination). | **Best in-scope mitigation:** randomize multi-mardoofa tiebreaker among matching suits. Source-permissible. |
| **D-RT-24-r5** | Medium (Test) | A7 | No test pin for multi-mardoofa tiebreaker, partner-of-bidder leader, tier-off, opp-perspective inference. | Add J.2.1/J.2.2/J.2.3 pins. |
| **D-RT-24-r6** | High (Strategy + Calibration) | A8 | M8's "probe" value is wasted on bot partner (no `pickFollow` mardoofa-aware branch). In 4-bot tables, M8 is a cost without benefit. | Calibrate first; if confirmed negative-EV, escalate to source-arbitration or add partner-side awareness. |
| **D-RT-24-r7** | Low | A4 | Singleton-A path is a (small) confound that dilutes opp inference from ~95% to ~85-90%. Real but minor. | None in M8 scope. |

### Issues NOT found (from prompt's checklist)

| Question from prompt | Status |
|---|---|
| 1. First-trick observability | Confirmed: high-leak (A1). |
| 2. Counter-strategy targeting T♠ | Confirmed: feasible, but bot opps don't exploit (A2). |
| 3. Bot self-defense (randomization, 50/50) | None implemented; deterministic by Pro-2 §2 mandate (A3). |
| 4. NOT-Sun-seat-1 bidder lead happens to be A — confound | Singleton-A path is the confound; minor (A4). |
| 5. Saudi-Master tier opp models bot M8 behavior | **No** — sampler doesn't condition on trick-1 observation (A5). |
| 6. Multi-pair edge (A♠+T♠ AND A♥+T♥) — which gets led? | Spades wins via `{S,H,D,C}` order; later suits leak more (A6). |
| 7. Test pin existence (deterministic lead choice) | Multi-mardoofa NOT pinned; partner-of-bidder NOT pinned; tier-off NOT pinned; opp-observation NOT pinned (A7). |
| 8. Probe-lead vs partner reading — info wasted against human partner | **More general**: probe wasted against bot partner; leak unread against bot opp. M8 is a no-op in 4-bot tables (A8). |

---

## Verdict

**M8 is correctly implemented (per D-RT-10's verdict) but creates a structural information-asymmetry problem.**

From the **opponent's perspective**:
1. The leak is real and high-confidence (~85-95% mardoofa-suit detection after confound) — A1.
2. Counter-strategy (target T capture) is straightforward against humans — A2.
3. Bot opps cannot exploit the leak because no inference layer reads trick-1 leads — A5. **This is the most surprising finding.**
4. Saudi-Master ISMCTS sampler ignores trick-1 observation entirely — A5.

The **net result**: M8 is most effective vs human partner + bot opp (probe + no-leak), and most harmful vs human opp + bot partner (leak read, signal wasted). In all-bot tables (the addon's primary deployment), M8 is **strategically inert at best, mildly negative at worst** (singleton-A confound aside, the leak is not realized as a cost because bot opps can't read it; the probe is not realized as a benefit because bot partners can't read it).

**No code modifications.**

**Strongest in-scope mitigation candidate**: D-RT-24-r4 (randomize multi-mardoofa tiebreaker among matching suits). This is source-permissible (Pro-2 §2 silent on tiebreaker), in-spirit M8 scope, reduces opp cross-suit leak, and has zero bidder-side EV cost.

**Strongest out-of-scope mitigation**: D-RT-24-r2 (add `_memory` mardoofa-suspect hook + ISMCTS T-pin). Restores symmetry between bidder-side leak generation and opp-side leak exploitation. Also in spirit completes D-RT-24-r6 (partner-side awareness), since the same memory hook can drive both `pickLead` (opp inference) and `pickFollow` (partner T-preservation).

**Strongest non-code action**: calibration A/B (D-RT-10-r6 already proposed). Without simulation data on the actual EV trade-off in mixed tables, all of the above are theoretical. M8 may be net-positive in expert play (where humans realize both sides) and net-negative in addon-default play (4 Saudi-Master bots).

---

## Confidence

**High** for verdicts on A1, A4, A5, A6, A7:
- Read full `pickLead` to confirm M8 is the only mardoofa-related lead path.
- Read `BotMaster.sampleConsistentDeal` lines 198-440 to confirm zero posterior conditioning on trick-1 leads.
- Read `Bot.OnPlay` lines 340-440 to confirm `_memory` records voids/firstDiscard but not mardoofa-suspect.
- Verified `lowestByRank` semantics on multi-card lists never return Ace unless single-card.
- Verified test pin gaps in `test_state_bot.lua` lines 1645-1677.

**Medium** for verdicts on A2, A3, A8 (strategic projections):
- Counter-strategy claims (A2) are derived from Saudi-pro card-game principles, not from a pinned Saudi source. The "withhold A♠" tactic is plausible but not verified against tournament videos.
- Determinism + non-randomization claim (A3) is high-confidence on the code side; the strategic claim that randomization would help is theory-side without simulation.
- Probe-vs-partner asymmetry (A8) is high-confidence on code (no partner-side mardoofa-aware branch exists) but the EV split across table compositions is calibration-dependent.

No code was modified.
