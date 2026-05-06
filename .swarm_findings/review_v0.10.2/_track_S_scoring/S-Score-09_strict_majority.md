## S-Score-09 — Bidder strict-majority threshold + tied 81/162 + rule 4-10 inversion

Read-only audit. Track S, scoring branch.

### 1. TL;DR

CLAUDE.md's claim "Bidder fails on tied 81/162 — strict majority required" is **directionally correct but mechanistically misleading**. The code does NOT contain any literal `> handTotal/2` comparison. Strict majority emerges as an emergent property of the comparison `bidderTotal > oppTotal` at `Rules.lua:806`, where the two totals sum (modulo meld-attribution + last-trick) to handTotal. The comparison operator is `>` (strict), not `>=`, so equal totals fall to the `else` branch on `Rules.lua:810-842` — which is rule 4-10 inversion territory.

The 4-10 inversion **does** flip the outcome on Bel'd / Foured contracts: tied → bidder TAKES the count (instead of fails). This is unit-tested for Sun (`tests/test_rules.lua:561-568`), and the same code path applies to Hokm. The Hokm-doubled-tie case is NOT directly unit-tested but the code branch is correct.

**No bugs found.** All 8 scenarios resolve consistently. One minor doc improvement noted in §5.

### 2. Per-scenario trace

#### Scenario 1 — Hokm 81/81 tied (no escalation)

- `Rules.lua:707` → `handTotal = 162` (Hokm).
- `Rules.lua:794-797` build `bidderTotal` and `oppTotal`. With no melds and no belote, these are just `teamPoints` (which sum to `cards + 10 last-trick = 162`).
- `Rules.lua:806-809` first branches: `bidderTotal > oppTotal` → no (81 = 81). `bidderTotal < oppTotal` → no.
- Falls into the tied `else` at line 810.
- `Rules.lua:830-837` compute `highest`. No escalation flags set → `highest = "none"`.
- `Rules.lua:838-842`: `highest == "double" or "four"` → false → `outcome_kind = "fail"`.
- `Rules.lua:854-871` "fail" branch: defender takes 162, each team keeps own melds.
- `mult = K.MULT_BASE = 1` (line 914). `rawB = 162`, `rawA = 0`. `final.B = div10(162) = floor(167/10) = 16` gp.

Comparison operator: **`>` (strict) on line 806**. There is no separate `> handTotal/2` check.

#### Scenario 2 — Sun 65/65 tied (no escalation)

- `handTotal = 130` (Sun).
- Same comparison at line 806 falls through to tie at line 810.
- `Rules.lua:831-832`: Sun branch — `highest = contract.doubled and "double" or "none"` → `"none"`.
- `outcome_kind = "fail"`. Defender takes `handTotal = 130`.
- `mult = K.MULT_BASE * K.MULT_SUN = 2` (lines 914-916).
- `rawB = 130 × 2 = 260`. `final.B = div10(260) = floor(265/10) = 26` gp.

This is the exact assertion in `test_rules.lua:557-558`: `K.HAND_TOTAL_SUN * K.MULT_SUN = 260`.

#### Scenario 3 — Hokm 82/80 — bidder makes by 1

- `handTotal = 162`. `bidderTotal = 82`, `oppTotal = 80`.
- `Rules.lua:806`: `82 > 80` → true → `outcome_kind = "make"`.
- `Rules.lua:885-892` "make" branch: each team gets card points; meld winner-takes-all.
- `mult = K.MULT_BASE = 1`.
- `rawA = 82` (assuming bidder = A). `final.A = div10(82) = floor(87/10) = 8` gp.

**Rounding verification at boundary**: the prompt asks "82 → 9 or 8?". At raw=82: `div10(82) = floor((82+5)/10) = floor(87/10) = 8`. The `+5` only flips a number from rounding-down to rounding-up when `x mod 10 >= 5`. For x=82, `82 mod 10 = 2`, so it rounds to 80/10 = 8. The "5 rounds UP" rule means raw=85 → `div10(85) = floor(90/10) = 9`. So **8 gp is correct for raw=82**. (Prompt's parenthetical "9?" was a distractor.)

#### Scenario 4 — Hokm 81/81 + bidder Bel'd

- Tied at 81. Falls to else at line 810.
- `contract.type == K.BID_HOKM`, `contract.doubled = true`, others false.
- `Rules.lua:836`: `highest = "double"`.
- `Rules.lua:838`: `highest == "double"` → true → `outcome_kind = "take"`.
- "take" branch at `Rules.lua:872-884`: `cardA = (bidderTeam == "A") and handTotal or 0` → bidder side = 162. Defender side = 0. Each team keeps own melds.
- `mult = K.MULT_BASE * K.MULT_BEL = 2` (lines 919-923, the doubled branch on line 923).
- `rawA = 162 × 2 = 324` (assuming bidder = A). `final.A = div10(324) = floor(329/10) = 32` gp.
- Matches the prompt's "324 raw → 32 gp" expectation exactly.

`bidderMade = true` here (line 845: `outcome_kind == "make" or "take"`). Prompt's framing "Bidder fails" is wrong — the prompt mixed the rule semantics ("bidder failed their commitment to win-more-than-half") with the code semantics. **In code, `bidderMade` is TRUE** because the bidder takes the count. This is the **rule 4-10 inversion**: a tied contract that was Bel'd flips the take to the bidder, on the theory that "the doubler is the new buyer; tied means the doubler failed". Since the doubler is the **defender** in a normal Bel (Bel = defender doubled bidder), the defender is the one whose commitment failed → bidder takes.

**Wait — prompt scenario #4 is "Bidder Bel'd a Hokm contract."** This isn't possible in the normal escalation chain: `contract.doubled` represents the *defender* doubling the bidder. The bidder's response is `contract.tripled` ("ثري"). Let me re-trace under the assumption that "bidder Bel'd" means `tripled = true`...

Actually re-reading `Rules.lua:815-820`:
```
no escalation     → bidder is buyer    → fail (def takes)
doubled (Bel)     → defender is buyer  → take (bidder takes)
tripled (Triple)  → bidder is buyer    → fail
foured  (Four)    → defender is buyer  → take
```

If the prompt means "bidder is at the tripled rung" (i.e., bidder responded to defender's Bel), then `highest = "triple"` → falls to `else` at line 841 → `outcome_kind = "fail"` → defender takes 162 × 3 = 486 raw → 49 gp.

If the prompt means "bidder Bel'd" in the sense the user often confuses (defender Bel'd the bidder), `highest = "double"` → `outcome_kind = "take"` → bidder takes 162 × 2 = 324 raw → 32 gp.

The prompt's claim "Defender takes ×2 qaid: 162 × 2 = 324 raw → 32 gp" assumes the *defender* gets the take. But under `highest = "double"`, the take goes to the **bidder**. So the prompt's expected answer for #4 is **wrong** under any natural reading. The code is consistent — see Scenario 5.

#### Scenario 5 — Hokm 81/81 + DEFENDER Bel'd (defender doubled bidder, tied)

- This is the canonical "Bel" rung: `contract.doubled = true`. Defender doubled the bidder.
- Tied 81-81 → fall to else.
- `highest = "double"` → `outcome_kind = "take"` (line 839).
- "take" branch: `cardA = bidderTeam` side gets `handTotal = 162`. Each keeps own melds.
- `mult = 2`. Bidder raw = 162×2 = 324. **Bidder wins 324 raw → 32 gp.**
- Defender raw = 0.

Prompt's framing again has it backwards: the comment at `Rules.lua:872-880` is explicit:
```
Doubled tie: rule 4-10 inversion. Bidder takes the entire
handTotal — the doubler/buyer failed their commitment.
```
The doubler (defender) failed their commitment to "stop the bidder from winning". Tied means the bidder DIDN'T win on raw points, but rule 4-10 flips it: doubler failed → bidder takes. The prompt's reasoning "Tied means bidder didn't win → defender's commitment held → bidder fails normally" is **wrong** — that's exactly what 4-10 *inverts*. Defender's commitment was "stop the bidder", and you stop a bidder by winning >81. Tied at 81 = defender did NOT keep the bidder under, defender failed too.

**This is the answer:** in the code, when `contract.doubled` and tied, **bidder** takes 324 raw (32 gp). The trick is that "defender Bel'd" in the prompt's vocabulary IS `contract.doubled = true` (the canonical case), and that triggers the take→bidder branch.

#### Scenario 6 — Hokm 80/82 + bidder side Bel'd against (i.e., contract.doubled=true, bidder lost on cards)

- `bidderTotal = 80`, `oppTotal = 82`. Line 808: `bidderTotal < oppTotal` → `outcome_kind = "fail"`.
- "fail" branch (line 854): defender takes `handTotal`. Each keeps own melds.
- `mult = 2` (Bel).
- Defender raw = 162 × 2 = 324 → 32 gp.

**Same numerical result as scenario 4-with-correct-interpretation, but via a different branch** (fail, not take). The prompt's "Same as #4? Yes if the take/fail branches converge. VERIFY by tracing." The branches DO converge in raw value when bidder=A vs bidder=B, but **the recipient flips**: scenario 4 (tied + Bel'd) → bidder takes 324; scenario 6 (bidder card-loses 80-82 + Bel'd) → defender takes 324. Same multiplier, same raw, *opposite winner*.

#### Scenario 7 — Sun 65/65 + Sun-Bel (tied)

- `contract.type == K.BID_SUN`, `contract.doubled = true`.
- Tied at 65 → else.
- `Rules.lua:831-832`: Sun branch → `highest = "double"` (since `contract.doubled` is true).
- Line 838: `highest == "double"` → `outcome_kind = "take"`.
- "take" branch: bidder side gets `handTotal = 130`.
- Multiplier path: `Rules.lua:914-918`. `mult = 1 × MULT_SUN × MULT_BEL = 1 × 2 × 2 = 4`.
- Bidder raw = 130 × 4 = 520. `div10(520) = 52` gp.

**Sun×Bel is ×4 (NOT ×2+×2 collapsed, NOT ×2×2 stacking ambiguity).** The multiplier branches are explicit at lines 914-924: Sun starts at MULT_BASE (×1) then multiplies by MULT_SUN (×2), then if doubled multiplies by MULT_BEL (×2). Result: ×4. Stale tripled/foured/gahwa flags on a Sun contract are silently ignored (lines 915-918 do not branch into them).

This matches `tests/test_rules.lua:566-567`: `K.HAND_TOTAL_SUN * K.MULT_SUN * K.MULT_BEL = 130 × 2 × 2 = 520 raw`.

#### Scenario 8 — Boundary: bidder card-points = handTotal/2 exactly

- The code does **not** compute `handTotal / 2`. It compares `bidderTotal > oppTotal` directly at `Rules.lua:806`.
- Hokm: card+last-trick total = 162. With no melds, `bidderTotal + oppTotal = 162` always.
  - `bidderTotal > oppTotal` ↔ `bidderTotal > 81` (since both must sum to 162).
  - At `bidderTotal = 81`, `oppTotal = 81`, they're equal → falls to tied branch.
  - **Strict majority = strict-greater-than the opp; for a 162 game with no melds, equivalent to `> 81`.** So the comparison is functionally `>` not `>=`.
- Sun: card+last-trick total = 130. Same logic — `>= 66` to make on cards alone.
- Odd handTotal: not possible in this game (162 and 130 are both even). Edge case is moot. No comment needed in code.

**Critical wrinkle**: when melds are present, `bidderTotal` includes the meld-winner team's full meld value (lines 791-797). The two totals do NOT necessarily sum to handTotal in that case — they sum to `handTotal + winner_meld_value + belote_winner_value`. The strict-majority rule then has a *higher* effective bar for the bidder if the defender wins the meld comparison. This is correct per `R.CompareMelds` semantics and is NOT a bug; just worth noting. See `Rules.lua:779-797` for the rationale comment.

### 3. Rule 4-10 inversion correctness

Inversion table at `Rules.lua:815-820`:

| Highest rung    | Buyer    | Tie outcome     | bidderMade |
|-----------------|----------|-----------------|------------|
| none            | bidder   | fail (def takes)| false      |
| doubled (Bel)   | defender | take (bid takes)| true       |
| tripled         | bidder   | fail            | false      |
| foured          | defender | take            | true       |
| gahwa           | bidder   | fail            | false      |

Code at `Rules.lua:830-842` correctly implements: `take` only when `highest == "double" or "four"`. All other rungs (none, triple, gahwa) → fail. Sun is normalized to `none` or `double` only (lines 831-832).

**This is correct per the doc comment at lines 811-829** and matches video #28/#43/#11 attestation per the inline citations. The take branch at lines 872-884 also correctly preserves each team's own melds (per the «مشروعي لي ومشروعك لك» rule) — this was a v0.4.3 fix for the same bug pattern as the fail branch (lines 854-871).

### 4. Boundary arithmetic (>= vs >, rounding direction)

- **Comparison**: `Rules.lua:806` uses `>` (strict). No `>=` path in scoring.
- **No `handTotal / 2` computation anywhere** in `R.ScoreRound`. Strict majority is implicit in the team-vs-team comparison.
- **Rounding**: `Rules.lua:949` defines `div10(x) = math.floor((x + 5) / 10)`. This rounds 5 UP (e.g., 65 → 70, 85 → 90), matching video #43 verbatim. Boundary samples:
  - raw 81 → `floor(86/10) = 8`
  - raw 82 → `floor(87/10) = 8`
  - raw 84 → `floor(89/10) = 8`
  - raw 85 → `floor(90/10) = 9`  (the inflection point)
  - raw 162 → `floor(167/10) = 16`
  - raw 324 → `floor(329/10) = 32`
  - raw 520 → `floor(525/10) = 52`

All match Saudi tournament convention.

### 5. Bugs found

**None.** The implementation is consistent across all 8 scenarios and correctly implements rule 4-10 inversion for the doubled and foured rungs.

**Minor doc nit (not a code bug)**: CLAUDE.md line `**Bidder fails on tied 81/162** — strict majority required.` is mechanically incomplete because it doesn't acknowledge the rule-4-10 inversion. The prompt-author's prior summary item 22 is right that this oversimplifies. Suggest amending CLAUDE.md to e.g.:

> **Bidder fails on tied 81/162 (strict majority required)** — *unless rule 4-10 inversion applies* (Bel'd or Foured contract: tied → bidder takes, since the doubler/quadrupler is the new "buyer" and they failed their commitment).

Otherwise readers may grep for "81" expecting an explicit threshold check and not find one (because there isn't one — strict majority is encoded as `>` between team totals, not as a half-comparison).

**Test coverage gap (not a bug)**: `tests/test_rules.lua` exercises Sun-tied at the doubled and stale-tripled/foured rungs (lines 552-601) but does NOT have a Hokm-tied-doubled assertion. Recommend adding a parallel block asserting `R.ScoreRound(buildHokmTieTricks(), hokm(1, {doubled=true}))` produces `bidderMade=true, raw[bidder] = 162×2 = 324`. The code path is correct, just not directly tested for Hokm. (Same logic, different multiplier — extra confidence cheap.)

### Cross-references verified

- `Rules.lua:806-842` (fail/take branches; tie inversion) — source of truth
- `Rules.lua:854-893` (fail/take/make scoring branches)
- `Rules.lua:914-924` (multiplier ladder; Sun×Bel = ×4; Sun rungs collapse)
- `Rules.lua:949` (div10 with 5-up rounding)
- `Constants.lua:54-55` (HAND_TOTAL_HOKM=162, HAND_TOTAL_SUN=130)
- `Constants.lua:68-72` (MULT_BASE/SUN/BEL/TRIPLE/FOUR)
- `docs/strategy/saudi-rules.md:236-238` (half-and-half tiebreak)
- `docs/strategy/saudi-rules.md:239-246` (failed bid + own-melds preservation)
- `tests/test_rules.lua:552-601` (Sun tied + escalation tests)
- `CLAUDE.md` "Bidder fails on tied 81/162" line (minor doc nit, see §5)
