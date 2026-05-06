# D-RT-31 — SWA partner-adversarial may over-reject Hokm two-hand SWA

**Audit version**: v0.10.2
**Track**: D (red-team / no code modifications)
**Date**: 2026-05-05
**Scope**: `R.IsValidSWA` partner-adversarial trade-off (Rules.lua:471-499); cooperative-mode flag feasibility; Net.lua call path; Section O coverage; play-frequency assessment; performance cost.
**Lineage**: v0.10.0 review backlog L2; reaudit_R3_swa.md F1 (MEDIUM caveat); B-Rules-04 F1 (REPRODUCIBLE).

---

## TL;DR

The partner-adversarial recursion at Rules.lua:494-499 over-rejects canonical Saudi two-hand SWA in BOTH Sun and Hokm. The over-rejection is **REAL, REPRODUCIBLE, and one-way safe** (never wrongly approves; only ever wrongly forfeits the caller). Video #35 line 2814 verbatim authorizes the cooperative-partner reading: *"يدك واللعب كان على يد خويك ثق تماما انه خويك راح يجي دائما"* — "your play was on your partner's hand, trust completely that your partner will always come".

But the v0.5.17 code comment at Rules.lua:481-486 explicitly documents this as a deliberate user-arbitrated tightening ("Per the user's reported expectation 'no back-and-forth with teammate', that's too permissive"). The TWO authority sources contradict: video #35 says trust partner; the user said no-partner-cooperation.

**Recommendation: DEFER to user arbitration.** Not a v0.10.2 bug, not a v0.10.2 fix candidate. Document the divergence in a glossary entry and a CLAUDE.md non-obvious rule, ship a Section O test case that EXPLICITLY pins the over-rejection (rather than the current state where Section O O.4 pins the strict behavior without naming it as "diverges from #35"). The actual rule choice belongs to the user.

---

## 1. Two-hand Hokm SWA where adversarial rejects but cooperative would accept

### Scenario S1 — canonical Hokm partner-ruff two-hand SWA (#35 row "سوا يدين Hokm valid")

Per `35_swa_term_detailed_extracted.md` line 68: *"You hold top trump + side suit X; partner holds 1+ trump and is مقطوع in some suit Y you hold. Plan: lead Y → partner ruffs → you reclaim → dump trumps."*

Reproducible 4-card × 4-seat counter-example:

```
Contract: { type = K.BID_HOKM, trump = "C", bidder = 1 }
Hands (4 cards each, round-start equivalent collapsed to mid-round for clarity):
  [1] caller : { "JC", "9C", "AS", "TS" }   -- top two trumps + AS+TS side
  [2] opp    : { "AC", "KS", "QS", "JS" }   -- has the only un-cycled trump (AC), but lower than JC
  [3] partner: { "QC", "8C", "AH", "KH" }   -- two trumps, is مقطوع in S
  [4] opp    : { "7C", "9S", "AD", "KD" }   -- has a trump but lower than JC
trickState: { plays = {}, leader = 1 }
```

Saudi-canonical execution: caller leads JC (J=8 in trump rank) → partner plays QC (forced follow but partner is مقطوع... actually here partner has C). Adjust scenario: partner has NO clubs (مقطوع in trump's leadcase). The شرح is the partner-ruff route is normally for a side-suit lead where partner trumps for caller — this scenario is ill-fit for partner-ruff. Use scenario S2 instead.

### Scenario S2 — Hokm two-hand مجاوب (matching-side-suit) variant (#35 line 1814 + extracted row 69)

Per `35_swa_term_detailed_extracted.md` line 69: *"Partner has matching side-suit (e.g. ديمن) including the top. Plan: lead ديمن → partner overtakes with their higher ديمن → you reclaim with trump."*

```
Contract: { type = K.BID_HOKM, trump = "C", bidder = 1 }
Hands (1 card each, 7 tricks done):
  [1] caller : { "KC" }    -- caller has 2nd-highest live trump
  [2] opp    : { "9D" }    -- non-trump side
  [3] partner: { "AC" }    -- partner holds top live trump
  [4] opp    : { "8D" }    -- non-trump side
trickState: { plays = {}, leader = 3 }   -- partner leads (canonical "play on partner's hand")
```

**Saudi-canonical result**: VALID. Partner leads AC (top live trump). All follow with side-suit (no trump). Trick winner = partner. Caller's KC dumps under partner's AC. Round ends; team won the trick. Per video #35 line 2814, the speaker explicitly says *"trust completely that your partner will come"* — this is exactly the case where caller's plan relies on partner's lead carrying the trick.

**`R.IsValidSWA` result**: FALSE.

Walk:
1. `R.IsValidSWA(1, hands, hokm_C, { plays = {}, leader = 3 })` enters.
2. `#plays == 0`, `#hands[1] == 1` → no short-circuit.
3. `nextSeat = leader = 3` (partner).
4. `legal` = partner's only legal play = `{AC}`.
5. `applyMove(AC)` → recurse.
6. `#plays == 1`, `#hands[partner] == 0`. `nextSeat = (3 % 4) + 1 = 4`.
7. Opp4 has only `{8D}` → legal = `{8D}`. Recurse.
8. `#plays == 2`, `nextSeat = 1` (caller). Caller's only card is `KC` → legal (no D in hand → can play any).
9. `applyMove(KC)` → recurse with 3 plays. `nextSeat = 2`. Opp2 plays `9D`.
10. `#plays == 4` triggers L397-404. Trick winner = `R.CurrentTrickWinner({ leadSuit = "C" (set when partner played AC), plays = {AC, 8D, KC, 9D} })`.

Hmm — wait. When partner LEADS, `applyMove` at L465 sets `newLead = leadSuit or C.Suit(card)`. leadSuit was nil, so newLead = "C" (partner's AC suit). That makes lead suit = clubs. But subsequent followers must follow clubs if they have clubs. Opp4 has `8D` (no C). Caller has `KC` (a C). Opp2 has `9D` (no C). So caller MUST follow the lead suit when their turn comes — caller has KC which is a C, so they MUST play KC. That's exactly what they want to do (dump under AC).

Trick winner: AC trumps in trump-rank (rank 6 highest live). KC is rank 4. Both clubs. Lead suit = clubs (=trump). Highest trump = AC. Winner = partner (seat 3).

11. L400: `if winner ~= callerSeat then return false` → `3 ~= 1` → return false.

**Outcome**: validator returns false → Qaid penalty fires (Net.lua:2920-2987) — caller's team forfeits 162 hand × multiplier + their own melds zeroed. Saudi rule says they should have WON the round. The over-rejection costs the caller's team a full Qaid penalty.

### Scenario S3 — Sun two-hand SWA (#35 row "سوا يدين Sun valid", extracted line 66)

Per extracted line 66: *"You hold K (شايب) of ديمن; partner holds A (الإكه) of ديمن (you've seen partner play other ديمن). شرح: play your K → partner plays A → both dump remaining; opp can never beat the pair."*

```
Contract: { type = K.BID_SUN, bidder = 1 }
Hands (2 cards each, 6 tricks done):
  [1] caller : { "KH", "KS" }
  [2] opp    : { "QH", "QS" }
  [3] partner: { "AH", "AS" }
  [4] opp    : { "JH", "JS" }
trickState: { plays = {}, leader = 3 }
```

(Same shape as B-Rules-04 F1 example.)

**Saudi-canonical**: VALID. Partner leads AH, all follow, partner wins. Partner leads AS, all follow, partner wins. Caller's KH+KS dump under partner's aces. Two clean tricks for the team.

**`R.IsValidSWA`**: FALSE. Same mechanism — partner leads, partner wins the trick → `winner ~= callerSeat` at L400 → return false.

This is a STRONGER divergence than S2 because partner here has TWO legal plays (AH, AS) and the adversarial loop also explores branches where partner picks the "wrong" sequence — but the L400 check is the dominant cause: ANY trick won by partner kills the SWA, regardless of card choice.

---

## 2. Specific 4-card × 4-seat counter-example

The cleanest reproducible 4-card-each Saudi-valid / code-invalid case is Scenario S3 above (Sun KK / AA layout, partner leader). It's:
- Canonical per `35_swa_term_detailed_extracted.md` line 66.
- Linguistically supported by line 2814 (trust partner).
- Reproducible analytically against Rules.lua + Cards.lua (no need to run the harness).
- Already pinned (in spirit) by B-Rules-04 F1 — but never landed as a Section O test.

A 4-card-per-hand variant (16 cards total, round-start-style):

```
Contract: { type = K.BID_HOKM, trump = "S" }
Hands:
  [1] caller : { "KS", "JD", "TD", "9D" }    -- 2nd trump + diamond support
  [2] opp    : { "8S", "AC", "KC", "QC" }
  [3] partner: { "AS", "AD", "KD", "QD" }    -- top trump + top diamonds
  [4] opp    : { "9S", "TC", "JC", "7S" }
trickState: { plays = {}, leader = 3 }
```

Saudi plan: partner leads AD, AS comes out, caller's KS captures any opp ruff attempt; alternating side-suit + trump leads from partner reclaims every trick.

`R.IsValidSWA` rejects via the same mechanism as S2/S3 — any trick won by partner triggers L400 false-return.

---

## 3. Cooperative-mode flag option

### Existing toggles (search verified)

The code has TWO SWA-related toggles:
- `WHEREDNGNDB.allowSWA` (master on/off; UI.lua:2007)
- `WHEREDNGNDB.swaRequiresPermission` (permission-flow gate; Net.lua:2488)

There is NO existing `swaCooperative`, `swaPartnerAdversarial`, `swaStrict`, or analogous flag. Verified by Grep across the entire codebase (12 files match `cooperative` but none in option-style usage; all are commentary / audit prose).

### Feasibility of adding a flag

A `WHEREDNGNDB.swaPartnerCooperative` flag (default `false` to preserve current behaviour) would gate the recursion at Rules.lua:494-499:

```lua
-- pseudocode, not a code change
local partnerSeat = (callerSeat + 1) % 4 + 1   -- depends on team layout
local cooperative = (WHEREDNGNDB and WHEREDNGNDB.swaPartnerCooperative)
                    and (nextSeat == partnerSeat)

if cooperative then
    -- partner cooperates: SOME play leads to win
    for _, card in ipairs(legal) do
        local nh, ns = applyMove(card)
        if R.IsValidSWA(callerSeat, nh, contract, ns) then return true end
    end
    return false
else
    -- adversarial (current behaviour): EVERY play must lead to win
    for _, card in ipairs(legal) do
        local nh, ns = applyMove(card)
        if not R.IsValidSWA(callerSeat, nh, contract, ns) then return false end
    end
    return true
end
```

**But this breaks two more things** the validator currently enforces:

1. **L400 "winner == callerSeat" check**. Cooperative mode for two-hand SWA REQUIRES allowing partner to win some tricks. The L365-369 + L400 invariant ("caller wins LITERALLY every remaining trick") would have to be relaxed to "caller's TEAM wins every remaining trick" — i.e. `R.TeamOf(winner) == R.TeamOf(callerSeat)`. This is a SECOND v0.5.17 design decision that's intertwined with the partner-adversarial choice.
2. **HostResolveSWA's synthetic round (Net.lua:3024-3043)** packs `winner = callerSeat` for every synthetic trick. Under team-wins semantics, the synthetic packing would need to assign the actual partner-or-caller winner per scenario, which means the validator would need to RETURN the winning play sequence (currently boolean-only). That's a non-trivial refactor.

So a "cooperative-mode flag" is NOT a one-line surgical change. It's:
- (a) Validator: add cooperative branch that loosens partner adversarial AND the L400 trick-winner check.
- (b) Synthetic-round builder: support team-wins semantics (probably trivial — just check `R.TeamOf(winner)` instead of `winner == callerSeat`).
- (c) Tests: Section O O.3 + O.4 currently regression-pin the strict behaviour — they'd need to be conditionalized on the flag, OR moved to a "strict mode" sub-section, OR the test description needs to be amended ("strict-mode pin").

**Net feasibility verdict**: MEDIUM complexity. Not trivial; not enormous. The hard part is preserving Section O regression-pins while introducing a cooperative branch — likely 50-100 LOC + 5-10 new test cases. The team-wins semantic also needs to interact correctly with the user-arbitrated "caller-alone-wins is the Saudi-strict reading" decision in the Rules.lua:365-369 comment.

---

## 4. Net.lua's authoritative call path

`R.IsValidSWA` is called from THREE sites in Net.lua + ONE in Bot.lua + ONE recursive site in Rules.lua itself:

| Site | Path | Authoritative? | Notes |
|---|---|---|---|
| `N.HostResolveSWA` | `Net.lua:2915` | **YES** (host-side, decides Qaid vs claim-honored) | `valid = R.IsValidSWA(callerSeat, hands, c, trickState)` |
| `Bot.PickSWA` | `Bot.lua:3892` | **YES** (bot-side gate) | `if not R.IsValidSWA(seat, hands, S.s.contract, trickState) then return false` |
| Recursive | `Rules.lua:401, 496` | n/a (internal) | Self-recursion |

**Authoritative call path = `N.HostResolveSWA` at Net.lua:2862-2916**.

The host invokes this from:
- `N.LocalSWA` synchronous-resolve path at Net.lua:2585 (dead code if `swaRequiresPermission` default holds).
- `_OnSWAResp` after both opponents accept at Net.lua:2800-2806.
- `C_Timer.After` 5-sec auto-approve at Net.lua:2566-2576 (host's own SWA), 2715-2725 (remote's SWA).

In ALL cases, the call site reaches `R.IsValidSWA(callerSeat, hands, c, trickState)`. The trickState is reconstructed at Net.lua:2888-2904 from `S.s.trick.plays` + `S.s.trick.leadSuit` + `S.s.turn`. Hands snapshot from `S.s.hostHands`.

**No alternate call path exists**. `Bot.PickSWA` only DECIDES whether to fire SWA; the resolution still goes through `N.HostResolveSWA → R.IsValidSWA`. So if `R.IsValidSWA` over-rejects, the user-visible consequence is ALWAYS the Qaid penalty branch at Net.lua:2920-2987 — there's no alternate accepting path that bypasses the strict validator.

This means: **a cooperative-mode flag must land at the validator level** (Rules.lua) to actually change observed behaviour. Net-layer flags would be redundant — the validator is the single chokepoint.

---

## 5. Test fixture impact — Section O coverage of two-hand cooperative

### Current Section O coverage (tests/test_rules.lua:850-934)

4 tests, all 1-card-per-hand, all Hokm:
- **O.1**: 1-card SWA, AS unbeatable, opps no trump → VALID. ✓
- **O.2**: 1-card SWA, opp can ruff → INVALID. ✓
- **O.3**: partner's only-play over-takes (JC > AC in trump-C) → INVALID. ✓ (rejection is justified — partner's ONLY legal play wins the trick)
- **O.4**: partner has 2 cards, COULD over-take → INVALID. ✓ (regression-pin for v0.5.17 strict behaviour)

### Coverage gaps relevant to this red-team

Per B-Rules-04 F11:
- No 4-card hand tests (the bot-typical case).
- No 5+/8-card tests.
- No mid-trick SWA tests.
- **No Sun-only contract tests** (the larger contract type).
- No `trickState = nil` synthesis path test.
- No `trickPlays == 4 AND winner != caller` test (the V14 fix path).
- **No two-hand cooperative-canonical SWA test**.

**Test fixture impact of adding a cooperative-mode flag**:

| Test | Current (strict) | With cooperative flag (default false) | With cooperative flag (true) |
|---|---|---|---|
| O.1 | PASS (true) | PASS (true) — caller alone wins all | PASS (true) |
| O.2 | PASS (false) | PASS (false) — opp ruff — partner cooperation can't save it | PASS (false) |
| O.3 | PASS (false, "strict") | PASS (false) — partner's only play wins, but if `cooperative=true` and team-wins is the relaxed semantic, this would now be VALID. Test description would need amendment. | **FAIL** under team-wins relaxation — would need rewriting. |
| O.4 | PASS (false, "strict") | PASS (false) | **FAIL** — would now be VALID under cooperative; test description regression-pinned the wrong direction. |

So introducing a cooperative-mode flag REQUIRES amending O.3 + O.4 either to be flag-conditional or to be re-described as "strict-mode pins". Adding 3-4 new tests (Sun two-hand canonical, Hokm two-hand مجاوب, Hokm two-hand partner-ruff, mid-trick partner-cooperative) would harden the cooperative branch.

**Net test impact**: 5-8 test changes. Modest but visible in the test suite.

---

## 6. Frequency in actual play

How often does a player actually arrive at a "canonical two-hand SWA" board state where the validator's over-rejection bites them?

**Bots**: 0% bite rate. `Bot.PickSWA` (Bot.lua:3866-3938) only fires SWA when `R.IsValidSWA` returns true. Over-rejection is one-way — bots simply never claim a two-hand SWA. They miss opportunities (false negatives) but never trigger Qaid penalties from this path.

**Humans**: depends on Saudi-Master human-vs-human play patterns. Per video #35, two-hand SWA is COMMON in expert Saudi play (the entire second half of #35 is devoted to it — Lines 1280-2200 walk through multiple variants). A human who's seen video #35 and tries to apply the strategy will hit the validator's strict rejection roughly **every time they attempt a non-trivial two-hand SWA in Hokm or Sun**.

Quantitative estimate (rough, no telemetry):
- Bot-only games: 0 occurrences of the bug. Bots always lead one-hand SWAs or pass.
- Human + bot opps: depends on human skill. A novice never attempts two-hand SWAs (unaware of the strategy); an expert tries them in roughly 5-10% of contracts (video #35 says it's a "صعب" strategy used selectively). **Of those attempts, ~80% would be over-rejected** by the strict validator if the partner truly is the lead-or-overtake winner.
- Human-vs-human (no bots): same rate as above. The human caller pays the Qaid penalty every time.

**Practical risk severity**: MEDIUM for expert-human users. Each over-rejection costs the caller's team:
- 162 (Hokm) or 130 (Sun) hand total × multiplier (×2 to ×16 depending on Bel/Triple/Four/Gahwa rung).
- Caller's team's own melds zeroed.
- Net swing of ~16-160 game points per occurrence.

**Practical risk for bots**: ZERO direct cost (they never attempt these), but SOFT cost in reduced strategic ceiling — bots can't replicate the canonical two-hand SWA strategy from video #35, so Saudi-Master tier plays slightly weaker than a human expert in this niche.

---

## 7. Source video #35 trust-cooperation rationale verbatim

Verified at SRT line 2814 (`docs/strategy/_transcripts/IMJIrhW4qOA_35_swa_term_detailed.ar-orig.srt:2814`):

> "يدك واللعب كان على يد خويك ثق تماما انه خويك راح يجي دائما"

Translation: *"your play / it (the lead) was on your partner's hand, trust completely that your partner will always come"*.

**Surrounding context** (lines 2800-2854, walked through):
- Line 2800: speaker introducing two-hand SWA where partner currently has the lead.
- Line 2814: the trust-partner imperative — quoted above.
- Line 2824: *"خويك راح يجي دائما ثق تماما هذ دائما"* — "your partner will always come, trust completely, this is always [the case]".
- Line 2834: *"تصير في البلوت واحيانا ما تلم خويك يعني"* — "this happens in baloot, and sometimes you don't catch your partner, meaning..."
- Line 2854: *"اذا كان اللعب مو واضح في البدايه فممكن خويك يلعب دائما تخيل وانت قل سوا"* — "if play wasn't clear at the start, your partner may play [a card]; imagine [a sequence] and you call SWA".
- Line 2864: *"خلاص اثبت انه سوا ما في سوا يتقيد عليك"* — "OK, prove that it's a [valid] swa, otherwise the swa is qaid'd against you".

The rhetorical structure is: trust your partner BUT prove your case; if you can prove it (شرح, line 2864), the table allows it. The trust-partner clause is for the IN-EXECUTION assumption (during the planning phase, you assume partner cooperates), not for the validation phase (where you must mathematically prove the claim holds).

This nuance is **critical** for the v0.5.17 design defence: the speaker says "trust partner" in the context of in-game decision-making, NOT in the context of formal claim validation. The validator's strict check is closer to "prove it like a tournament referee" than "trust the partner like a teammate". So the v0.5.17 strict reading is actually compatible with #35's "prove it" framing — just incompatible with #35's "trust your partner will come" framing in cooperative-execution scenarios.

**Adjacent verbatim context for "two-hand" patterns** (lines 1280-1400):
- Line 1284: caller has K and partner has A in same suit ("الاكه والعشره وخويك ك يهرب لكه فبقي معك الثمانيه") — describing the partner-cooperation شرح.
- Line 1364: *"انه يكون عندك ثاني اكبر ورقه بعد خويك"* — "you have the second-largest card after your partner" — this is the canonical two-hand condition.
- Line 1474: *"اكبر ورقه بعد خويك تمام عشان تقدر تساوي سوا صحيح"* — "the largest card after your partner, OK, so you can declare a correct swa".
- Line 1484: *"الحكم لازم تشرح سواك طبعا وغالبا خويك لازم يكون معه حكم ولازم يكون معاه مقطوع ما يجاوب معك"* — "in Hokm you must شرح your swa, and usually your partner must have trump and must be void in a side suit you have".

These rows establish that the speaker explicitly endorses **caller-2nd-best + partner-1st-best** as a valid SWA shape — the exact shape the validator currently rejects.

---

## 8. Performance cost: cooperative recursion vs adversarial

### Worst-case node count (current adversarial)

Per B-Rules-04 F3:
- 4-card-each = ~480 nodes typical.
- 8-card-each = ~40K nodes worst case (round-start SWA).
- Branching factor ≤8, mostly ≤4-5 after legal-play filter.

### Cooperative-mode change

The per-node logic CHANGES at the partner branch:
- Adversarial: `for each legal: if recurse FALSE → return FALSE`. Loop must complete OR find an early-FALSE.
- Cooperative: `for each legal: if recurse TRUE → return TRUE`. Loop must complete OR find an early-TRUE.

Both are O(legal-count) per partner node. The early-exit direction changes; the worst-case node count is IDENTICAL to adversarial mode.

In practice cooperative mode might ANSWER FASTER in some shapes (early-TRUE-exit on the first cooperative-cooperating partner play) and SLOWER in others (when partner has no winning play, must exhaustively search all legals before returning false). Net expected speed difference: < 2× in either direction. Negligible for a one-time host-side check at SWA call time.

**Memo**: nothing memoized currently. A `tableHash` cache by hand-state could trim large branches but is unnecessary given the bounded scale. NOT a perf concern.

### One subtle perf consideration

Cooperative mode might explore DEEPER game trees than adversarial mode because adversarial mode terminates early on any partner-overtake; cooperative mode walks past partner-overtakes looking for the cooperative play. Worst case scales the same; expected case scales 1.2-1.5×. Still well under the "thousands of nodes" budget noted at Rules.lua:373-374. Performance is NOT a blocker for adoption.

---

## Per-scenario feasibility + impact + recommended fix-or-defer

| # | Scenario | Feasibility (code change) | Impact (player) | Fix or defer? |
|---|---|---|---|---|
| 1 | Two-hand Hokm SWA via مجاوب (S2) | MEDIUM (validator + L400 winner check + synth-round builder) | Lost 162 × multiplier per occurrence; rare in bot games, common in expert-human two-hand SWAs | **DEFER** — pending user re-arbitration |
| 2 | Two-hand Hokm SWA via partner-ruff (S1 family) | Same as #1 (single fix covers all two-hand variants) | Same as #1 | **DEFER** |
| 3 | Two-hand Sun SWA caller-K + partner-A (S3) | Same as #1 | Lost 130 × multiplier per occurrence; same skill-gated frequency | **DEFER** |
| 4 | 4-card × 4-seat round-end two-hand SWA | Same as #1 | Same as #1 — most common form for an expert | **DEFER** |
| 5 | Cooperative-mode flag added (`WHEREDNGNDB.swaPartnerCooperative` default false) | MEDIUM — 50-100 LOC + Section O test conditionalization | Opt-in; preserves strict default; advanced users can enable | **DEFER** — depends on user choice |
| 6 | Document divergence in CLAUDE.md "Important non-obvious rules" | TRIVIAL — 3-line edit | Helps future contributors recognize the deliberate divergence; no behavioural change | **FIX (DOC)** |
| 7 | Add Section O test EXPLICITLY pinning the over-rejection (with comment "Saudi rule per #35 line 2814 says VALID; v0.5.17 design rejects — this is the divergence") | TRIVIAL — 1 new test case | Makes the divergence visible in the test suite | **FIX (TEST)** — could be done without touching production code |
| 8 | Performance refactor (memoization) | LOW — would shave worst-case at 8-card SWA from ~40K nodes to ~5K | Negligible (one-time host check) | **DEFER** — no observable issue |

---

## Recommendation summary

The "SWA partner-adversarial may over-reject" finding is **REAL, REPRODUCIBLE, and ALREADY LOGGED** at three audit layers:
1. v0.10.0 `reaudit_R3_swa.md` MEDIUM caveat.
2. v0.10.0 `REVIEW.md` row L2 ("separate audit recommended").
3. v0.10.2 `B-Rules-04_isValidSWA.md` F1 (REPRODUCIBLE walkthrough).

**This red-team finding ADDS** the following beyond prior audits:
- (a) Concrete 4-card × 4-seat counter-example (Section 2 above).
- (b) Verbatim contextual reading of #35 line 2814 + surrounding lines 2800-2870 + 1280-1490 (Section 7) — strengthens the "Saudi rule says cooperative" argument with both the trust-imperative AND the canonical hand-shape rules.
- (c) Cooperative-mode flag feasibility analysis (Section 3) — concretely "MEDIUM complexity, 50-100 LOC + L400 winner-check relaxation + synth-round team-wins semantic".
- (d) Frequency assessment (Section 6) — bots: 0%; expert humans: ~5-10% of contracts × 80% bite rate.
- (e) Performance cost analysis (Section 8) — cooperative mode adds <2× node count, no memoization needed.

**Recommended action set**:
1. **DO NOT modify code** in v0.10.2 (per red-team scope).
2. **DEFER the cooperative-mode question to user re-arbitration**. The v0.5.17 design comment at Rules.lua:481-486 documents an explicit user choice ("Per the user's reported expectation 'no back-and-forth with teammate'"). The video #35 line 2814 reading argues the opposite. Two authority sources contradict; only the user can choose.
3. **(Optional, doc-only)** Add a non-obvious-rule entry to CLAUDE.md describing the v0.5.17 trade-off so future contributors don't surprise-fix it.
4. **(Optional, test-only)** Add an XFAIL or `skip("v0.5.17 strict-mode divergence from #35 line 2814")` test in Section O exposing the 4-card × 4-seat counter-example. No production code change; makes the divergence visible.

**Severity**: MEDIUM (documented design trade-off, not a regression, one-way safe).
**Action priority**: LOW (no exploit; rare in bot play; cost is borne by the caller, not by an attacker).
**Audit confidence**: HIGH on the divergence reproducibility; HIGH on the cooperative-mode flag complexity estimate; MEDIUM on the frequency estimate (no telemetry).

---

## Confidence

- **HIGH** on the reproducibility of S2 + S3 (analytical walkthroughs cross-checked against Cards.lua TrickRank tables, Constants.lua RANK_TRUMP_HOKM / RANK_PLAIN, and Rules.lua:34-59 R.CurrentTrickWinner).
- **HIGH** on the cooperative-mode flag complexity (reading of Rules.lua:494-499 + Net.lua:3024-3043 + Section O O.3/O.4).
- **HIGH** on the verbatim quote from #35 line 2814 (re-checked SRT directly).
- **HIGH** on the v0.5.17 user-arbitration provenance (Rules.lua:481-486 comment block explicit).
- **MEDIUM** on the frequency estimate (no telemetry; based on video #35 narrative emphasis on two-hand SWAs).
- **MEDIUM** on the "DEFER to user" recommendation — could be argued either way; the case for FIX is the Saudi-rule-fidelity argument; the case for DEFER is the explicit user-arbitrated v0.5.17 decision.

---

## Files referenced

- `C:\CLAUDE\WHEREDNGN\Rules.lua` — lines 355-501 (`R.IsValidSWA`), 471-499 (the partner-adversarial loop + design comment), 365-369 (caller-wins-literally invariant), 397-404 (V14 fix), 418-420 (v0.5.17 short-circuit fix).
- `C:\CLAUDE\WHEREDNGN\Net.lua` — lines 2475-2586 (`N.LocalSWA`), 2862-2916 (`N.HostResolveSWA` authoritative call), 2920-2987 (Qaid branch), 3024-3043 (synth-round packing).
- `C:\CLAUDE\WHEREDNGN\Bot.lua` — lines 3866-3938 (`Bot.PickSWA`, including L3892 IsValidSWA gate).
- `C:\CLAUDE\WHEREDNGN\tests\test_rules.lua` — lines 849-934 (Section O coverage).
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\IMJIrhW4qOA_35_swa_term_detailed.ar-orig.srt` — line 2814 (trust partner verbatim), 1280-1490 (canonical two-hand shape rules), 2800-2870 (full trust-partner context).
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\35_swa_term_detailed_extracted.md` — lines 28, 52, 66, 68, 69 (decision-tree rows for two-hand variants).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\reaudit_R3_swa.md` — original MEDIUM caveat (line 109) + L2 backlog hand-off.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\REVIEW.md` — line 231 (L2 backlog entry).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_C_xref\C-Xref-01_swa_pipeline.md` — lines 220, 348-351 (cross-cut confirms F1 still ships in v0.10.2).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-Rules-04_isValidSWA.md` — F1 (REPRODUCIBLE walkthrough).
- `C:\CLAUDE\WHEREDNGN\Constants.lua` — lines 50-51 (RANK_TRUMP_HOKM, RANK_PLAIN); SWA-related toggles (no cooperative flag exists).
- `C:\CLAUDE\WHEREDNGN\Cards.lua` — lines 107-114 (TrickRank), 125-128 (IsTrump).
