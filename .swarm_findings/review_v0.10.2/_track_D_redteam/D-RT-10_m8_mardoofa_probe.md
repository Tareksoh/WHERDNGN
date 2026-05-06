# D-RT-10 — v0.10.2 M8 Sun bidder-team mardoofa probe lead — red-team probe

Track-D red-team probe of the M8 mandatory-mardoofa-Ace lead added in
v0.10.2 (`Bot.lua` `pickLead` lines 1806-1823, sourced from Pro-2 PDF
§2 / L08).

Files inspected (read-only):
- `C:\CLAUDE\WHEREDNGN\Bot.lua` lines 1703-1823 (`pickLead` head + M8
  branch) and 3261-3402 (`Bot.PickAKA`, `Bot.PickPlay`)
- `C:\CLAUDE\WHEREDNGN\State.lua` lines 100-118, 520-534, 947, 1443-1450
  (state reset / `ApplyAKA` / Hokm-only gate)
- `C:\CLAUDE\WHEREDNGN\Net.lua` lines 2341-2372 (`N.LocalAKA`),
  4085-4109 (`Bot.PickAKA` invocation site)
- `C:\CLAUDE\WHEREDNGN\Constants.lua` line 61 (`K.BID_SUN`)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\03b_secrets_pro_2.txt`
  lines 14-16 (L08 source text)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-Bot-04_pickLead_m8.md`
  (Track-B implementation review)
- `C:\CLAUDE\WHEREDNGN\tests\test_state_bot.lua` lines 1645-1677
  (J.2 pins)
- `C:\CLAUDE\WHEREDNGN\CHANGELOG.md` lines 50-59 (M8 entry)

The branch under probe (`Bot.lua` 1806-1823):

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

## Q1 — Pre-condition tightness: bidder vs partner vs defender (the "seat-1" framing)

### Scenario
The prompt's "seat-1 bidder" framing is misleading shorthand for the
trick-1 leader. Saudi Baloot trick-1 leader is `(s.dealer % 4) + 1`
(`Net.lua:2020`) — dealer's-left, NOT seat literal-1, NOT necessarily
the bidder. The real question: does M8 fire correctly across all
combinations of {leader-is-bidder, leader-is-partner, leader-is-opp}?

### Verdict
**No bug, but the gating is correctly looser than "Sun seat-1
bidder MUST lead" wording suggests.** M8's gate is
`myTeam == R.TeamOf(contract.bidder)` (line 1809), which is true for
**both** the bidder AND the bidder's partner. This matches Pro-2 §2's
explicit Arabic wording: "هذه اللعبة اجبارية عليه وعلى زميله"
("this play is obligatory on him AND on his partner",
`03b_secrets_pro_2.txt:15-16`).

If the actual trick-1 leader is an opponent, `pickLead` is called with
`seat = leader_seat`, `myTeam = R.TeamOf(leader_seat)` ≠
`R.TeamOf(contract.bidder)`, so the M8 gate fails and falls through
correctly. The branch handles all three cases without bug.

### Repro
Three table layouts (dealer at seat 4 → leader at seat 1; bidder
varies):
- **Bidder leads** (bidder=1): M8 fires for seat 1 (gate true). ✓
- **Partner leads** (bidder=3): M8 fires for seat 1 (partner of 3
  is 1; same team). ✓
- **Opp leads** (bidder=2): M8 does NOT fire for seat 1 (different
  team). Falls to Sun shortest-suit-low. ✓

### Recommendation
The CHANGELOG line 50 title "Sun seat-1 mardoofa probe lead" is
**misleading**. The Bot.lua comment at lines 1790-1805 is correct
("Sun bidder-team mardoofa probe lead on trick 1"). The CHANGELOG
header should read "Sun bidder-team trick-1 mardoofa probe lead"
to match the broader gate. Track-B review B-Bot-04 already flagged
this as M8-i3.

---

## Q2 — Backed-A+T detection: same-suit pairing

### Scenario
M8 must fire ONLY on A+T of the same suit (مردوفة بعشرة). Holding
A♠ + T♥ (across-suit) must NOT fire.

### Verdict
**Correct.** The pairing detection in lines 1810-1822 is per-suit
indexed:
- `hasA[su] = true` when an Ace of suit `su` is in legal
- `hasT[su] = true` when a Ten of suit `su` is in legal
- The return condition `hasA[su] and hasT[su] and aceCard[su]`
  requires BOTH flags true for the SAME `su`

Cross-suit holdings (A♠+T♥, A♣+T♦, etc.) do not satisfy the
per-suit-AND condition. The `aceCard[su]` capture is keyed by the
Ace's own suit, so the returned card is always the Ace of the
matched suit.

### Repro
- Hand `{ AS, TH, KH, QH, JH, 9H, 8H, 7C }`: A is ♠, T is ♥.
  `hasA["S"]=true, hasT["S"]=false → no match. hasA["H"]=false,
  hasT["H"]=true → no match.` Falls through. ✓
- Hand `{ AS, TS, ... }`: `hasA["S"]=true, hasT["S"]=true → returns
  AS.` ✓

No bug.

### Recommendation
None. Detection is correct.

---

## Q3 — Multi-mardoofa selection: stable choice but arbitrary order

### Scenario
Seat holds A♠+T♠ AND A♥+T♥ (e.g. `{ AS, TS, AH, TH, ... }`). Pro-2
§2 says "the Ace mardoofa-with-ten" (singular Ace) — does NOT
specify which suit when multiple mardoofas exist.

### Verdict
**Stable but arbitrary.** Iteration order is hardcoded
`{ "S", "H", "D", "C" }` in line 1818. Spades wins ties. Hearts
beats Diamonds beats Clubs. This is **deterministic** (not flaky)
but **unsourced** — Pro-2 §2 provides no tiebreaker.

A more defensible choice (defender perspective) would be:
1. **Longest-mardoofa-suit** — more length behind A+T means more
   information-gathering capacity (probe value scales with length).
2. **Highest-meld-bonus suit** — if seat also holds K+Q same suit,
   leading the A+T from that suit doubles the probe with a
   meld-protection signal.
3. **Suit where opp meld-call is likely** — leading the suit where
   opps may have melds gives faster discovery.

None of these are sourced from Pro-2 either. Hardcoded `{S,H,D,C}` is
defensible as "deterministic and source-silent — pick a stable
order."

### Repro
- Hand `{ AS, TS, AH, TH, KS, QS, JS, 9S }` (two mardoofas, ♠+♥;
  ♠ also has Bel meld K+Q): M8 returns **AS** (first match in
  `{S,H,D,C}` order). The K+Q meld in ♠ never enters the calculation.
- A test pin for this scenario does NOT exist (Track-B review B-Bot-04
  M8-i2 also flags this). A future refactor could silently flip the
  choice to AH and break no test.

### Recommendation
1. Add a code comment in the `for _, su in ipairs({"S","H","D","C"})`
   loop: `-- Pro-2 §2 doesn't specify multi-mardoofa tiebreaker;
   stable {S,H,D,C} order is deliberate.`
2. Add a test pin: hand with two A+T pairs, expect the first by
   suit-order.
3. **Strategic upgrade candidate** (out of M8 scope): refine to
   longest-suit-first if any Saudi-pro source supports it. None
   currently in `docs/strategy/` does.

---

## Q4 — Already-led suit: not a real issue (M8 only fires trick 1)

### Scenario
The prompt asks: "seat already led ♠ in trick 1, mardoofa was used.
Trick 2 — does M8 try to lead ♠ again from a depleted holding?"

### Verdict
**Cannot fire on trick 2 by construction.** Line 1807 gate:
`trickNum == 1`. The branch is unreachable for `trickNum > 1`.
`trickNum = #(S.s.tricks or {}) + 1` (line 1725); after trick 1
closes, `S.s.tricks` has length 1, so `trickNum = 2` and the gate
fails.

There is **no** "M8 round 2" carry-over. The probe lead happens once
per hand on trick 1, then the Sun fallthrough logic (Tahreeb,
Fzloky, B-97, B-77, singleton-low, shortest-suit-low) takes over
for tricks 2-8.

### Repro
Trick 2 with depleted ♠: `S.s.tricks = { <trick 1 record> }`. Then
`trickNum = 2`, M8 gate fails on `trickNum == 1`, falls through to
the existing Sun lead branches.

### Recommendation
None. The strict trick-1 gate is correct.

### Adjacent observation
The prompt's "round 1" framing in the spec is a bit of a misnomer.
"Round" in this codebase elsewhere refers to **BIDDING round**
(R1/R2 — see `Bot.lua:134, 152, 1223, 1230, 1779`), not trick 1.
Pro-2 §2 phrases it as "the player who is on the head of play"
(الذي على رأس اللعب), with no round qualifier — meaning trick 1
universally, regardless of bidding-round outcome. The code
correctly maps this to trick 1, not bidding-round 1.

---

## Q5 — Tier gate: Advanced+ correctly enforced

### Scenario
CHANGELOG: "Tier-gated at Advanced+." But Pro-2 is a *strategy* book
(pro-tier knowledge). Should the rule actually fire only at M3lm+
(masters) since Pro-2 §2 represents pro-level strategy, not
Advanced-level heuristic?

### Verdict
**Correctly gated, but the tier choice is debatable.** Line 1806
gate: `Bot.IsAdvanced()`. Per `Bot.lua:48-55`, this returns true
for Advanced + M3lm + Fzloky + Saudi Master tiers (strict-extension
hierarchy). Basic bots fall through.

The Advanced gate is consistent with related code:
- Sun shortest-suit lead (line 2371) is Advanced-gated.
- Tahreeb signal interpretation is M3lm-gated (line 1860).
- Fzloky signal is Fzloky-gated (line 1946).

So **Advanced has access to bidder-asymmetry plays already**
(B-77, B-82, B-97, etc. are Advanced-gated). M8 fits the same
tier. Gating it at M3lm+ would mean Advanced bots play the
"shortest-suit-low" trick-1 lead which Pro-2 explicitly says is
WRONG for the bidder team. So the Advanced gate is the **defensible**
choice (lift Advanced + above to source-correct play, leave Basic
as random-legal).

### Repro
- `WHEREDNGNDB.advancedBots = false`, all higher tiers off →
  `IsAdvanced() = false` → M8 skipped → falls through to shortest-
  suit-low (basic random + early-fallthroughs).
- `WHEREDNGNDB.advancedBots = true` → M8 fires.
- `WHEREDNGNDB.m3lmBots = true` → M8 also fires (because IsAdvanced
  returns true at any higher tier per the strict-extension model).

J.2 sanity at line 1675 protects the negative case (defender hand,
Advanced on, falls through to 7C). Positive case at 1666-1667
confirms bidder fires.

### Recommendation
None on the gate itself. But there is **no test pin** for the
"Advanced=false → M8 doesn't fire" case. Recommend adding:
- J.2.3 negative-tier: same bidder-side fixture, but with
  `advancedBots=false`. Expected: `7C` (shortest-suit-low),
  not `AH`.

---

## Q6 — AKA-call interaction: structurally impossible in Sun

### Scenario
Bot calls AKA (`s.akaCalled`) AND is Sun bidder seat-1 with backed
A+T. Does AKA short-circuit M8's mandatory probe lead, or do they
coexist?

### Verdict
**Cannot occur in Sun by design — both `Bot.PickAKA` and `N.LocalAKA`
are gated to `K.BID_HOKM` only:**

`Bot.lua:3263`:
```lua
if not S.s.contract or S.s.contract.type ~= K.BID_HOKM then return nil end
```

`Net.lua:2347`:
```lua
if not S.s.contract or S.s.contract.type ~= K.BID_HOKM then return end
```

Bots cannot auto-call AKA in Sun. Humans cannot manually call AKA
in Sun. `S.s.akaCalled` will always be `nil` for the entire duration
of a Sun contract.

So the M8 branch never has to coexist with `S.s.akaCalled` being
truthy in Sun.

(`S.ApplyAKA` itself has no contract gate, but the only callers
that reach it are `N.LocalAKA` and `N._OnAKA`, both gated upstream.
A buggy peer broadcasting MSG_AKA mid-Sun would technically apply
the banner client-side, but that's a Hokm-soft-protocol abuse
beyond M8 scope.)

### Repro
- Trick 1 of Sun, bidder-side leader, holds A+T mardoofa: M8 fires
  cleanly, no AKA banner ever appears.
- A hypothetical malformed `S.s.akaCalled = {seat=X, suit="H"}`
  injected before trick 1 of Sun: M8 still fires (its gates ignore
  `s.akaCalled`). The leaked AKA banner would not affect the M8
  return value because M8 reads only `legal` + contract + seat.

### Recommendation
None. The structural Hokm-only gate makes the interaction moot.
Worth a one-line comment in the M8 block: `-- Sun has no AKA path
(N.LocalAKA + Bot.PickAKA both Hokm-only), so akaCalled
interaction is structurally impossible here.` Pure documentation;
no code change.

---

## Q7 — Round 2 / subsequent hands: clean re-fire each hand

### Scenario
M8 phrased "round 1" probe — what about subsequent rounds in a
session?

### Verdict
**Each hand re-fires M8 cleanly.** Per `State.lua:107-110` and
`State.lua:520-534`, when a new hand begins:
- `s.tricks` resets to `{}` (so `trickNum == 1` is true again)
- `s.akaCalled = nil` (irrelevant for Sun anyway)
- `s.contract` is re-set with the new bidder

There is no per-bot persistence of "M8 already fired this session."
The branch is **purely state-derived** — `legal` is computed fresh
each call from `S.s.hostHands[seat]`.

So in a session where:
- Hand 1: bidder = seat 2 (Sun), seat 2 holds A+T mardoofa →
  M8 fires, leads Ace. ✓
- Hand 2: bidder = seat 3 (Hokm), …M8 doesn't fire (Hokm). ✓
- Hand 3: bidder = seat 1 (Sun), seat 1 holds A+T mardoofa →
  M8 fires again, leads Ace. ✓

### Repro
After a Sun hand completes (`S.ApplyRoundEnd` runs, then
`S.ApplyHand` resets `s.tricks` for the new round), call
`Bot.PickPlay` for the new bidder team's leader on trick 1 of the
new Sun contract. M8 returns the Ace.

### Recommendation
None. State semantics are clean. The "round 1" framing in the
M8 description should be read as "trick 1 of any Sun hand" and
that is what the code implements.

---

## Q8 — Cross-suit information leakage: strategic exploitability

### Scenario
M8's mandatory lead leaks information that opp can use to read bot's
hand. Specifically: a Sun bidder/partner leading A♠ on trick 1 tells
all observers "I (bidder team) hold A♠+T♠ together (مردوفة) in
this suit." Is this strategically sound or exploitable?

### Verdict
**Genuine exploitability concern, but Pro-2 §2 prescribes it
unconditionally and the M8 implementation faithfully follows the
source.** This is a strategy-source question, not a code bug.

### Information-leak analysis

**What M8 telegraphs to opps:**
1. "Bidder team has at least one A+T mardoofa." (Strong signal —
   Sun bids without mardoofa happen, but A+T-led trick-1 narrows
   the probability mass.)
2. "The mardoofa is in suit X." (Exact — suit of the led Ace is
   the mardoofa suit. T is hidden but inferred.)
3. "The bidder team probably has length in suit X." (Probabilistic
   — A+T usually accompanied by 1+ side cards in same suit, but not
   always.)
4. **Implicit anti-signal:** the bidder team's other suits are
   probably weaker than the led suit (else they'd have led from
   strength elsewhere). With M8, this anti-signal is somewhat
   degraded because the lead is forced — opps know it doesn't
   represent strategic choice.

**How an Advanced+ opp can exploit:**
- **Mughataa-aware play**: opps now know to defend the led suit
  aggressively — they will withhold their own A in the led suit to
  set up a later sweep, knowing the bidder's A+T will fall together.
  Once T hits the lead, opps know the bidder's A is now naked-low
  in that suit (no cover behind it).
- **Cross-suit inference**: opps can deduce "bidder team's other
  Aces (if any) are NOT mardoofa" — they can play the un-led suits
  more aggressively, knowing the bidder's Aces in those suits lack
  T-cover.
- **Meld counter-call timing**: a Sun bidder's mardoofa in ♠ tells
  opps that ♠ is where the bidder's strength concentrates; opps
  with K+Q meld in another suit can declare it more confidently
  knowing the bidder is unlikely to hold the matching A there.

**Mitigation considered but absent:**
- M8 does NOT consider whether opps are Advanced+ bots vs random
  humans. Against random humans, the leak is mostly unread (free
  info, harmless). Against Advanced+ opps, the leak is read and
  exploited.
- M8 does NOT decline to fire when bidder team is in
  high-information-cost positions (e.g., opp partnership has
  declared Bel/Triple/Four meaning every signal carries 2-4× the
  info value). Compare `Bot.PickAKA` line 3332 which *does*
  decline AKA under doubled contracts: `if S.s.contract.doubled
  then return nil end`.

### Asymmetry with PickAKA's doubled gate
`Bot.PickAKA` (line 3332, v0.10.2 L3) **does** suppress under
`S.s.contract.doubled` for exactly this reason: doubled rounds
amplify info-leak cost. **M8 has no analogous gate** — it fires
under Bel, Triple, Four, Gahwa equally. This is asymmetric:

| Signal | Doubled-contract gate | Source |
|---|---|---|
| AKA | Suppressed (line 3332) | xref_X2_aka.md B3, G18-10 |
| M8 mardoofa probe | Always fires | Pro-2 §2 (no qualifier) |

Pro-2 §2 has no doubled-context exception in the source text. So
M8's "always fires" matches the source. But the **principle**
(doubled = tighten signals) that motivated L3 also motivates
considering an L08-level tightening here.

### Verdict on exploitability
**Real concern, source-conformant, not a code bug.** M8 is
implementing Pro-2 §2 verbatim. The information-leak cost is real
and the rule is exploitable by skilled opps. Whether this is
"strategically sound" depends on whether Pro-2 §2's author knew
about the leakage and accepted it (probe value > leak cost) or
overlooked it. Track-B's M8-i4 already flags this as a
"single-source weakness."

### Repro
- Sun bidder-side, 4-bot table all `m3lmBots=true`. Bidder leads
  A♠ via M8. Trick 2: opps now have a refined model of bidder
  hand. Run a forward simulation comparing M8-on vs M8-off — does
  bidder team's expected score go up or down?
- This requires a calibration run (`tools/calibrate.py`) over many
  deals, not a single-fixture test.

### Recommendation
**Strategic-side, not code-side.**
1. **Calibrate**: run a 1000+ deal simulation, M8-on vs M8-off,
   measure bidder-team Sun-contract pass rate. If M8 reduces pass
   rate vs the shortest-suit-low fallthrough (because info leak
   cost > probe value), Pro-2 §2 may be a **bad** rule — escalate
   to user / source-arbitration.
2. **Consider a doubled-contract gate** (mirroring AKA L3): when
   `S.s.contract.doubled` is true, fall through to existing
   shortest-suit-low. Source-justification: same reasoning as L3
   (doubled = info-leak cost rises → tighten signals). NOT in
   Pro-2 §2 text but defensible by analogy.
3. **Gate by opp tier readability** (out of scope for M8 itself):
   if both opps are humans, M8 is safe (info wasted); if either
   opp is M3lm+, the leak is read. Hard to gate cleanly without
   leaking opp-tier info into bidder logic. Defer.
4. **Alternative — late-trick switch**: if opps have already seen
   the bidder's other strengths (round 2 of bidding revealed
   trump-supporter or similar), they already model the hand;
   then M8's incremental leak is small. The current code can't
   model this without state plumbing it doesn't have.

The simplest defensible action is **(2) — add a `doubled` gate**
mirroring AKA L3. But that requires a source-arbitration call
(does Pro-2 §2's "obligatory" override the doubled-context
tightening principle? or does the Saudi pro convention layer them?).
Until that arbitration happens, leave M8 as-is.

---

## Summary of new red-team findings beyond Track-B B-Bot-04

| ID | Severity | Question | Issue |
|---|---|---|---|
| **D-RT-10-r1** | Doc | Q1 | CHANGELOG title "Sun seat-1 mardoofa probe lead" is a misnomer — gate is bidder-team-leader (bidder OR partner whoever opens). Bot.lua comment is correct. |
| **D-RT-10-r2** | Test | Q3 | No test pin protects the multi-mardoofa `{S,H,D,C}` iteration order. (Already in Track-B M8-i2.) |
| **D-RT-10-r3** | Test | Q5 | No negative test for `Advanced=false → M8 doesn't fire` — only the positive (J.2 line 1666) and defender-seat fall-through (J.2 line 1675) are pinned. |
| **D-RT-10-r4** | Comment | Q6 | M8 block could note "Sun has no AKA" to forestall future-reader confusion. |
| **D-RT-10-r5** | Strategy | Q8 | M8 has NO doubled-contract gate, asymmetric with PickAKA L3 (line 3332). Information-leak cost rises under doubled; M8 should arguably suppress. Source-arbitration needed (Pro-2 §2 silent). |
| **D-RT-10-r6** | Calibration | Q8 | Without simulation data, M8's net EV (probe value − leak cost) is unverified. Recommend calibration A/B before relying on it. |

### Issues NOT found (questions answered cleanly)

| Question | Status |
|---|---|
| Q1 (pre-condition tightness) | Correct gating; bidder + partner; opp falls through. |
| Q2 (same-suit A+T detection) | Correct per-suit indexing. |
| Q3 (multi-mardoofa selection) | Stable + deterministic, but unsourced. Code is fine; test gap. |
| Q4 (already-led-suit on trick 2) | Cannot fire — strict `trickNum == 1` gate. |
| Q5 (tier gate) | Correctly Advanced+. |
| Q6 (AKA interaction) | Structurally impossible — both AKA paths are Hokm-only. |
| Q7 (round 2 / multi-hand) | Clean re-fire each hand; no cross-hand state. |
| Q8 (info-leak exploitability) | Real strategic concern, faithful to single source. |

---

## Verdict

**M8 is functionally correct and source-conformant.** The branch
gates correctly across bidder/partner/opp leader scenarios, detects
A+T pairs per-suit, fires only on trick 1, is gated to Advanced+,
and re-fires cleanly across hands.

**No code bugs found.** The five concerns are:
1. Documentation (CHANGELOG title misnomer — D-RT-10-r1).
2. Test gaps (multi-mardoofa, Advanced-off — D-RT-10-r2/r3).
3. Comment clarity (AKA structural impossibility — D-RT-10-r4).
4. **Strategic asymmetry** (M8 has no doubled-contract gate
   parallel to AKA L3 — D-RT-10-r5). This is the most substantive
   concern and warrants source-arbitration discussion.
5. **Calibration gap** (no A/B data on M8 net EV — D-RT-10-r6).

The question of whether M8 is *strategically* sound (Q8 information
leak vs probe value) is **outside code-review scope**. It's a
single-source rule from Pro-2 §2 with no doubled-contract qualifier
in the source text. The implementation matches the source verbatim;
whether the source is *right* is a calibration / pro-arbitration
question.

No code modified. No test changes recommended within M8 scope
beyond the two pin additions in D-RT-10-r2/r3.

---

## Confidence

**High** for verdicts on Q1-Q7:
- Read entire `pickLead` head + M8 branch (Bot.lua 1703-1823).
- Verified `Bot.PickAKA` (3261-3402) and `N.LocalAKA`
  (Net.lua 2341-2372) are Hokm-only.
- Verified state reset path (`State.lua` 100-118, 520-534)
  zeroes per-hand state including `s.akaCalled`.
- Verified J.2 test pins (`tests/test_state_bot.lua` 1645-1677).
- Cross-checked Track-B B-Bot-04 review for overlap.

**Medium** for Q8 strategic verdict:
- The information-leak analysis is sound but lacks calibration
  data. Without A/B simulation, "net positive vs negative EV"
  is unproven from code-review alone.
- Pro-2 §2's silence on doubled context is a verifiable fact
  (source text checked), but whether the Saudi pro convention
  layered an unstated qualifier is not knowable from the
  available source materials.

No code was modified.
