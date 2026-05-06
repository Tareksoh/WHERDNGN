# S-Score-07 — Failed-bid + Qaid + Takweesh + SWA-invalid scoring symmetry

**Agent:** S-Score-07
**Scope:** Verify symmetry of qaid (penalty) arithmetic across the three
code paths that award `handTotal × multiplier` to the non-offending team:
1. `R.ScoreRound` `outcome_kind == "fail"` (regular failed bid)
2. `Net.HostResolveTakweesh` (illegal-play penalty)
3. `Net.HostResolveSWA` `not valid` branch (invalid SWA claim)

Read-only audit. Code anchors verified against the v0.10.2 working tree
on disk at the time of this audit.

---

## 1. TL;DR

**Three pipelines exist, and they ARE NOT identical** — but the
divergence is **intentional and now well-documented**, not a bug. Two
"symmetry breaks" found in prior audits have already been resolved:

- **Sun ×2 multiplier** is correctly applied in **all three** paths
  (Rules.lua:914-924, Net.lua:2223-2228, Net.lua:2959-2964). The prior
  audit's hypothesized "R2 Sun-mult collapse not backported to
  Takweesh / SWA-invalid" gap is **NOT present in the current code**.
- **div10 rounding** is now uniform `(x+5)/10` (5 rounds UP) across all
  three paths (v0.5.21 fix; comments at Net.lua:2291-2296 and
  Net.lua:3012-3013 cite the alignment).

**The one INTENTIONAL asymmetry** that remains:

- **Regular failed bid** (`R.ScoreRound` fail/take branches): each team
  **keeps its own declared melds** (rule «مشروعي لي ومشروعك لك»,
  Rules.lua:854-871).
- **Takweesh-caught and SWA-invalid (Qaid context)**: the **offender's
  team forfeits** its own melds (the non-offender keeps theirs).
  v0.10.1 M1 fix per user-arbitrated reading of Source H H-36.12 + PDF
  02 K-04 ("the buyer's meld is forfeited"). Net.lua:2253-2256 and
  Net.lua:2980-2981 enforce this; v0.10.1 explicitly REVERSED prior
  symmetry for the Qaid context only.

The **fail branch in `R.ScoreRound` is NOT a Qaid context** per current
doctrine — it's a "buyer-fell-short" outcome that lets each team
salvage its own pre-declared melds. Qaid (Takweesh / SWA-invalid)
forfeits the offender's melds because the offender materially cheated
or made a bad-faith claim.

**No new bugs found. One pre-existing scope discussion (does the rule
4-10 "take" branch warrant Qaid-style forfeiture?) is flagged below
for the user as a doctrine question, not a bug.**

---

## 2. Per-scenario trace

### Scenario 1 — Regular failed Hokm

**Setup:** Hokm contract, bidder team total = 70, defender team total =
92. No escalation, no Sun.

**Path:** `Rules.lua:R.ScoreRound`.

**Trace:**

- `handTotal = 162` (line 707; HOKM branch).
- `bidderTotal = 70`, `oppTotal = 92` → `outcome_kind = "fail"` (line
  809).
- Line 854-871 fail branch:
  - `cardA = (oppTeam == "A") and handTotal or 0` — defender (say "A")
    gets 162; bidder ("B") gets 0.
  - `meldPoints.A = meldA`, `meldPoints.B = meldB` — **both teams keep
    their own melds**.
- `mult = K.MULT_BASE = 1` (no Sun, no escalation).
- `rawA = (162 + meldA) * 1`; `rawB = (0 + meldB) * 1`.
- `final.A = (rawA + 5) / 10`, `final.B = (rawB + 5) / 10`.

**Result:** defender raw = 162 → 16 gp from the qaid alone, plus
defender's own melds × 1. Bidder gets 0 trick points + their own
melds × 1. **Symmetric meld preservation.** ✓

This matches the user-corrected paragraph at saudi-rules.md:239-246
"each team KEEPS its own declared melds — only the trick-point side
flows to the winner." Bidder team Quarte=50 → +5 gp net of -16, so a
quarte-bidder loses only 11 gp instead of all 16 (pre-v0.4.3 RCA cited
in code comment Rules.lua:862-867).

---

### Scenario 2 — Regular failed Sun

**Setup:** Sun contract, bidder team 50, defender 80.

**Path:** `Rules.lua:R.ScoreRound`.

**Trace:**

- `handTotal = 130` (Sun raw, pre-multiplier; Constants.lua:55).
- `bidderTotal = 50`, `oppTotal = 80` → `outcome_kind = "fail"`.
- Fail branch: `cardA = 130` (assuming defender="A"), `cardB = 0`.
  Both melds preserved.
- `mult` ladder line 914-924:
  - `mult = K.MULT_BASE = 1`.
  - `if contract.type == K.BID_SUN then mult = mult * K.MULT_SUN end`
    → `mult = 2`.
  - No escalation flags → mult stays at 2.
- `rawA = (130 + meldA) * 2 = 260 + 2*meldA`.
- `rawB = (0 + meldB) * 2 = 2*meldB`.
- `final.A = (260 + 2*meldA + 5) / 10`. With meldA=0 → 26 gp. ✓

**Sun multiplier IS applied in the fail branch** because the `mult`
computation is at the END of `R.ScoreRound` (lines 914-924), AFTER the
outcome-kind dispatch sets `cardA`/`cardB`. The same `mult` then
multiplies `(cardA + meldA)` regardless of branch. **No Sun-collapse
bug in fail branch.** ✓

Test coverage: `tests/test_rules.lua:557` asserts
`res.raw.B == K.HAND_TOTAL_SUN * K.MULT_SUN` (= 260) for a failed Sun.

---

### Scenario 3 — Takweesh-caught

**Setup:** During play of a Sun contract, defender catches bidder
playing illegally.

**Path:** `Net.lua:N.HostResolveTakweesh` (lines 2165-2377).

**Trace:**

- Line 2193-2200: scan `S.s.tricks` and `S.s.trick.plays` for any
  `p.illegal` from the opposing team. `foundIllegal` set.
- Line 2213: `winnerTeam = foundIllegal and callerTeam or oppTeam` →
  caller's team wins.
- Line 2215: `handTotal = 130` (Sun).
- Line 2223-2228 mult ladder:
  ```lua
  local mult = K.MULT_BASE             -- 1
  if c.type == K.BID_SUN then mult = mult * K.MULT_SUN end   -- ×2
  if     c.gahwa   then mult = mult * K.MULT_FOUR
  elseif c.foured  then mult = mult * K.MULT_FOUR
  elseif c.tripled then mult = mult * K.MULT_TRIPLE
  elseif c.doubled then mult = mult * K.MULT_BEL end
  ```
  For un-escalated Sun: `mult = 1 * 2 = 2`.
- Line 2230-2233: `cardA = handTotal` for winner team, 0 for offender.
- Line 2254-2256: **OFFENDER MELDS FORFEITED** —
  `mpA = (offenderTeam == "A") and 0 or meldA`. Caller's (winner's)
  melds preserved; offender's zeroed.
- Line 2286-2287: `rawA = (cardA + mpA) * mult`. So winner raw =
  (130 + winner_meld) * 2 = 260 + 2*winner_meld.
- Line 2297: `addA = floor((rawA + 5) / 10)`. With winner_meld=0 → 26
  gp to defender. ✓

**Sun multiplier IS applied.** Prior audit summary suggesting a "Sun
mult collapse" gap is **NOT a current bug** — the code at line 2224
explicitly multiplies by `K.MULT_SUN` for Sun contracts.

**Asymmetry vs. fail branch:** offender's melds are FORFEITED
(zeroed), not preserved. Code comment Net.lua:2234-2253 cites
v0.10.1 M1 user-arbitration explicitly distinguishing Qaid
(Takweesh / SWA-invalid) from regular failed-contract (R.ScoreRound).

**Repro check** for the prompt's question "does the code instead
award only 130 (missing Sun mult)?": **NO**. The code awards
130 × 2 = 260 raw → 26 gp. The mult multiplication at line 2286
applies the Sun ×2 correctly.

---

### Scenario 4 — SWA-invalid

**Setup:** Caller's SWA hand fails `R.IsValidSWA` validation. Sun
contract.

**Path:** `Net.lua:N.HostResolveSWA` `not valid` branch (lines
2949-3016).

**Trace:**

- Line 2940-2945: `valid = R.IsValidSWA(...)` → false.
- Line 2949 enters the qaid penalty branch.
- Line 2955: `handTotal = 130` (Sun).
- Line 2959-2964 mult ladder: **identical to Takweesh** —
  ```lua
  local mult = K.MULT_BASE
  if c.type == K.BID_SUN then mult = mult * K.MULT_SUN end
  if     c.gahwa   then mult = mult * K.MULT_FOUR
  elseif c.foured  then mult = mult * K.MULT_FOUR
  elseif c.tripled then mult = mult * K.MULT_TRIPLE
  elseif c.doubled then mult = mult * K.MULT_BEL end
  ```
  For un-escalated Sun: `mult = 2`.
- Line 2967-2968: `cardA = (oppOfCaller == "A") and handTotal or 0`.
  Opponent (non-caller) gets the trick-points side.
- Line 2980-2981: **CALLER (offender) melds forfeited** —
  `mpA = (callerTeam == "A") and 0 or meldA`.
- Line 3008-3009: `rawA = (cardA + mpA) * mult`. Opponent raw =
  (130 + opp_meld) * 2 = 260 + 2*opp_meld.
- Line 3014: `addA = floor((rawA + 5) / 10)` → 26 gp to opponent.

**Sun multiplier IS applied.** Same as Takweesh. ✓

**Symmetry vs. Takweesh:** **identical arithmetic** — same
`handTotal`, same mult ladder, same div10, same offender-meld-zero
rule, same Belote-independent scan. Only differences:
- Takweesh checks for `p.illegal` markers in past tricks; SWA-invalid
  consults `R.IsValidSWA` minimax.
- Takweesh's `winnerTeam` flips on `foundIllegal`; SWA-invalid's
  winner is always `oppOfCaller` (no validity → caller is offender).

These are different *triggers* for the same Qaid penalty. Arithmetic
is symmetric. ✓

---

### Scenario 5 — Bidder Bel'd then "tied" → take branch (rule 4-10 inversion)

**Setup:** Bidder Bel'd (doubled) Hokm contract. Bidder team total =
defender team total (true tie). Bidder is the buyer (no escalation
beyond doubling = defender did the doubling = defender is buyer).

Wait, let me re-state per the comment at Rules.lua:815-820:
> ```
>   no escalation     → bidder is buyer    → fail (def takes)
>   doubled (Bel)     → defender is buyer  → take (bidder takes)
>   tripled (Triple)  → bidder is buyer    → fail
>   foured  (Four)    → defender is buyer  → take
> ```

The buyer is whoever made the LAST escalation decision. Defender
called Bel → defender is buyer → on tie, **defender failed** →
**bidder takes the count** ("take" branch).

**Path:** `Rules.lua:R.ScoreRound` "take" branch (lines 872-884).

**Trace:**

- `bidderTotal == oppTotal` → tie path entered (line 810).
- `contract.doubled = true`, no Sun → `highest = "double"` (line 836).
- Line 838-842: `if highest == "double" or highest == "four" then
  outcome_kind = "take"`. ✓
- Line 872-884 take branch:
  - `cardA = (bidderTeam == "A") and handTotal or 0` — bidder takes
    full count.
  - `meldPoints.A = meldA`, `meldPoints.B = meldB` — **both teams
    keep their own melds** (same as fail branch).
- `mult = K.MULT_BASE * K.MULT_BEL = 2` (Bel'd Hokm).
- `bidderMade = true` (line 845: `take` counts as made).
- `rawA = (162 + meldA) * 2` for bidder (assuming bidder = "A").
- bidder raw = 324 + 2*meldA. Defender raw = 0 + 2*meldB.
- `final.A = (324+5)/10 = 32 gp` to bidder; `final.B = (2*meldB+5)/10`.

**Symmetry vs. fail branch:** **same meld preservation rule** ("my
meld for me, your meld for you"). Just the trick-points side flips:
in fail, defender takes 162; in take, bidder takes 162. Both branches
share lines 854-884 architecture: only difference is `(oppTeam ==
"A")` vs `(bidderTeam == "A")` for `cardA/cardB` assignment.

The user note "rule 4-10 is 'Bel'd-and-tied → Bel-er fails'" is
consistent: defender doubled (became buyer), defender tied, defender
failed → bidder takes the count.

**Note:** the prompt's example "bidder Bel'd Hokm contract, defender
70 / bidder 92, but bidder Bel'd → defender takes" doesn't match
Saudi rule 4-10. Bidder is the original "buyer". If bidder Bel'd
themselves (which actually maps to the redoubling chain — `tripled`
flag, NOT `doubled`), and tied, then bidder is buyer-of-last-decision
and bidder fails. The `doubled` flag in this code is the
**defender's** Bel; Triple is the **bidder's** counter. See
escalation.md (cited in CLAUDE.md). Code comment Rules.lua:815-820
documents this clearly. The prompt may have conflated `doubled` with
"bidder doubled themselves"; that's actually `tripled`. Either way,
the take/fail dispatch is verified correct.

---

### Scenario 6 — Takweesh-caught with prior melds (Carré-A)

**Setup:** Bidder declared Carré-A (raw value = 100,
K.MELD_CARRE_ACES) at meld phase. Mid-play, defender catches bidder's
illegal play and calls Takweesh. Hokm contract, no escalation.

**Path:** `Net.lua:N.HostResolveTakweesh`.

**Trace** (assume bidder = team B, defender = team A; bidder is the
offender):

- `winnerTeam = "A"` (caller, defender).
- `offenderTeam = "B"` (bidder).
- `handTotal = 162`. `mult = 1`.
- `meldA = 0`, `meldB = 100` (bidder's Carré-A, before forfeiture).
- Line 2255-2256: **`mpB = (offenderTeam == "B") and 0 or meldB = 0`**
  — bidder's Carré-A is FORFEITED.
- `cardA = 162`, `cardB = 0`.
- `rawA = (162 + 0) * 1 = 162`. `rawB = (0 + 0) * 1 = 0`.
- `addA = (162+5)/10 = 16 gp` to defender. `addB = 0` to bidder.
- Net result: bidder **loses** their Carré-A meld AND owes 16 gp.

**This contradicts the prompt's expected behavior.** The prompt
claims (Scenario 6 setup): "Per «مشروعي لي ومشروعك لك», bidder
retains their Carré-A meld... bidder gets -16 gp (qaid) + 10 gp (own
meld) = net -6 gp." That expected behavior matches PRE-v0.10.1.

**v0.10.1 EXPLICITLY REVERSED this rule for the Qaid context.** Per
the user-arbitrated reading of Source H H-36.12 + PDF 02 K-04, the
offender forfeits their own melds in Qaid contexts (Takweesh,
SWA-invalid). Code comment Net.lua:2234-2253 documents:

> ```
> v0.10.0 review M1 — user-arbitrated reading (option A):
>   * Source H H-36.12: offender's melds are "zeroed/forfeited"
>   * PDF 02 K-04 (نظام التسجيل في البلوت): "the buyer's meld is
>     forfeited (kept by neither side, just lost)"
>   ...
> Per the user's M1 arbitration, the offender's team forfeits its
> own declared melds when found illegal (Qaid). The non-offender
> team (winner) keeps theirs and adds them × mult.
> ```

The Carré-A scenario therefore yields: bidder = -16 gp (qaid only,
no meld credit); defender = +16 gp + (defender_meld × mult ÷ 10).
Net for bidder: -16 gp; not -6 gp.

**This is a DOCTRINAL DECISION, not a bug.** But it means the
prompt's mental model (and the Scenario 6 expected output) is stale
relative to v0.10.1 code. Worth flagging to the user: is the v0.10.1
arbitration still in effect for v0.10.2, or should we revisit the
"stays with owner" reading?

---

### Scenario 7 — Symmetry table

| Scenario | Penalty mult applied? | Melds preserved? | Last-trick bonus included? |
|---|---|---|---|
| Regular fail (R.ScoreRound, fail branch) | YES — Sun ×2 + Bel/Triple/Four ladder (Rules.lua:914-924) | **BOTH teams keep own melds** (Rules.lua:870-871) | **Implicit** — `handTotal = 162 / 130` already includes +10 last-trick (Constants.lua:54-55 docs). Pure-qaid fail (defender raw = handTotal) inherits last-trick because handTotal bakes it in. |
| Take branch (4-10 inversion) | YES — same ladder (Rules.lua:914-924) | **BOTH teams keep own melds** (Rules.lua:883-884) | **Implicit** via handTotal, same as fail. |
| Make branch | YES — same ladder (Rules.lua:914-924) | **Meld-comparison winner takes ALL** (Rules.lua:891-892) | **Computed** — `teamPoints` from `R.TrickPoints` + `+K.LAST_TRICK_BONUS` at line 703. |
| Takweesh-caught (Net.HostResolveTakweesh) | YES — Sun ×2 + Bel/Triple/Four ladder (Net.lua:2223-2228) | **OFFENDER FORFEITS; non-offender keeps own** (Net.lua:2253-2256) | **Implicit** via `handTotal` constant. |
| Takweesh-not-caught (false claim) | YES — same ladder | **CALLER (offender) FORFEITS; opp keeps own** (Net.lua:2253-2256, with winnerTeam = oppTeam) | **Implicit** via handTotal. |
| SWA-invalid (Net.HostResolveSWA) | YES — Sun ×2 + Bel/Triple/Four ladder (Net.lua:2959-2964) | **CALLER (offender) FORFEITS; opp keeps own** (Net.lua:2980-2981) | **Implicit** via handTotal. |
| SWA-valid | YES — delegates to R.ScoreRound (Net.lua:3017+) | Per R.ScoreRound dispatch | per R.ScoreRound. |

**Symmetry breaks:**
1. **Meld preservation differs between R.ScoreRound fail/take vs.
   Net.lua Qaid paths** — INTENTIONAL per v0.10.1 user arbitration
   (R.ScoreRound = both keep, Qaid = offender forfeits).
2. **Belote handling**: R.ScoreRound (line 769-777) cancels belote on
   ANY ≥100 meld team-wide (M5 v0.9.0 fix). Net.lua's Takweesh and
   SWA-invalid (lines 2274-2283 / 2997-3006) cancel belote ONLY when
   the SAME `declaredBy == kWho` declared the ≥100 meld — **NOT
   team-wide**. **POTENTIAL BUG — see Bugs section.**
3. **All other arithmetic is symmetric** (mult ladder, handTotal
   selection, div10 rounding).

---

## 3. Sun-collapse-missing-in-Takweesh-and-SWA-invalid: VERIFIED NOT
PRESENT

The prompt cites a prior-audit-summary claim:

> "R2 Sun mult collapse not backported to Takweesh / SWA-invalid"

**This is NOT a current bug.** Verified by direct code inspection:

**Takweesh** (Net.lua:2223-2228):
```lua
local mult = K.MULT_BASE                              -- 1
if c.type == K.BID_SUN then mult = mult * K.MULT_SUN end   -- ×2 for Sun
if     c.gahwa   then mult = mult * K.MULT_FOUR
elseif c.foured  then mult = mult * K.MULT_FOUR
elseif c.tripled then mult = mult * K.MULT_TRIPLE
elseif c.doubled then mult = mult * K.MULT_BEL end
```

**SWA-invalid** (Net.lua:2959-2964): **byte-identical** to the above
block.

**R.ScoreRound** (Rules.lua:914-924): semantically identical except
that R.ScoreRound has the v0.10.0 R2 defensive normalization that
**ignores** `tripled/foured/gahwa` flags on Sun contracts (Sun has no
Triple/Four/Gahwa rungs per canonical Saudi rule). Code comment at
Rules.lua:904-913.

**Asymmetry:** Net.lua's Takweesh and SWA-invalid handlers do **NOT**
have the v0.10.0 R2 defensive Sun-rung normalization. If a stale
resync or hand-edited save sets `c.tripled = true` on a Sun contract,
the Takweesh path would compute `mult = 2 * 3 = 6` (wrong;
should be 2), and the SWA-invalid path would do the same.

**Severity:** LOW — defense in depth. The phase machine
(`State.ApplyDouble`) prevents Triple/Four/Gahwa from being set on
Sun in normal play. This is purely a defensive-coding mismatch.

**Concrete repro:** Sun contract; force `c.tripled = true` via debug
hook or hand-edited save; trigger Takweesh. Expected (per R.ScoreRound
v0.10.0 R2 fix): mult = 2 (Sun-only). Actual (Net.lua): mult = 6
(Sun × Triple). Penalty over-charges by ×3.

**This IS a small symmetry-break bug, but in the OPPOSITE direction
from the audit summary's hypothesis.** The hypothesized gap was "Sun
mult MISSING" — actual gap is "Sun-rung-collapse defensive
normalization MISSING in Net.lua paths".

---

## 4. Bugs found

### BUG-S07-1 — Belote-cancellation rule diverges between R.ScoreRound
and Net.lua Qaid paths

**Severity:** MEDIUM. User-visible scoring inconsistency in a
narrow but real edge case.

**Files:**
- Rules.lua:769-777 (correct: TEAM-level cancellation, v0.9.0 M5 fix)
- Net.lua:2274-2283 (Takweesh: per-player only)
- Net.lua:2997-3006 (SWA-invalid: per-player only)

**The divergence:**

Rules.lua (correct):
```lua
if belote and kWho then
    local list = (meldsByTeam and meldsByTeam[belote]) or {}
    for _, m in ipairs(list) do
        if (m.value or 0) >= 100 then
            belote = nil
            break
        end
    end
end
```
This iterates the entire belote-team's meld list. ANY ≥100 meld
declared by ANY player on that team cancels belote.

Net.lua Takweesh (Net.lua:2274-2283):
```lua
if kWho and qWho and kWho == qWho then
    belote = R.TeamOf(kWho)
    local list = (S.s.meldsByTeam and S.s.meldsByTeam[belote]) or {}
    for _, m in ipairs(list) do
        if m.declaredBy == kWho and (m.value or 0) >= 100 then
            belote = nil
            break
        end
    end
end
```
This requires `m.declaredBy == kWho` — only cancels if the SAME
PLAYER who holds K+Q also declared the ≥100 meld. Partner's
quarte does NOT cancel.

Net.lua SWA-invalid (Net.lua:2997-3006): **identical predicate to
Takweesh** — same per-player gate.

**Impact:** In a Hokm Takweesh / SWA-invalid resolution, if the
non-offender team's K+Q holder gets +20 belote AND the partner has a
declared quarte, Saudi rule says the quarte subsumes the belote (no
double-counting). Rules.lua applies this. Net.lua does NOT. The
non-offender ends up with +20 belote that should have been cancelled.

**Repro:**
- Hokm contract, trump = Spades.
- Caller declared Carré-Aces (100 raw, 10 gp post-mult-1).
- Caller's partner holds K♠+Q♠, plays both during the round (they're
  played, so belote is "earned").
- Bidder makes an illegal play; caller calls Takweesh, caught.
- Expected (Rules.lua / Saudi rule): non-offender team gets handTotal
  + their melds × mult; +20 belote is CANCELLED because team has
  a ≥100 meld (the Carré-Aces). Final = (162 + 100)*1 / 10 = 26 gp.
- Actual (Net.lua): non-offender team gets +20 belote on top because
  the K+Q holder ≠ the meld declarer. Final = ((162+100)*1 + 20)/10
  = 28 gp. **Over-credit by 2 gp.**

**Recommended fix:** backport the v0.9.0 M5 team-level cancellation
predicate to Net.lua:2278 and Net.lua:3001. Drop the `m.declaredBy ==
kWho` clause — keep only `(m.value or 0) >= 100`.

**Cross-ref:** v0.9.0 M5 audit log at audit_v0.7.1; the comment at
Rules.lua:763-768 explicitly cites the team-level fix and the
"silently failed when declaredBy was nil" failure mode.

---

### BUG-S07-2 — Sun-rung defensive normalization missing in Net.lua
Qaid paths

**Severity:** LOW. Defense in depth. Production-unreachable in normal
play because phase-machine guards prevent Triple/Four/Gahwa flags from
being set on Sun contracts.

**Files:**
- Rules.lua:914-924 (correct: ignores Triple/Four/Gahwa on Sun)
- Net.lua:2223-2228 (Takweesh: applies any active escalation flag)
- Net.lua:2959-2964 (SWA-invalid: applies any active escalation flag)

**The divergence:**

Rules.lua (correct, per v0.10.0 R2):
```lua
if contract.type == K.BID_SUN then
    mult = mult * K.MULT_SUN
    if contract.doubled then mult = mult * K.MULT_BEL end
    -- intentionally ignore tripled/foured/gahwa on Sun
else
    if     contract.gahwa   then mult = mult * K.MULT_FOUR
    ...
end
```

Net.lua (both paths):
```lua
if c.type == K.BID_SUN then mult = mult * K.MULT_SUN end
if     c.gahwa   then mult = mult * K.MULT_FOUR
elseif c.foured  then mult = mult * K.MULT_FOUR
elseif c.tripled then mult = mult * K.MULT_TRIPLE
elseif c.doubled then mult = mult * K.MULT_BEL end
```
This applies Triple/Four/Gahwa multipliers EVEN on Sun, contradicting
the canonical rule.

**Impact:** If a stale resync, hand-edited save, or future bug sets
`c.tripled = true` on a Sun contract, the Qaid penalty over-charges by
×1.5 to ×2 (Triple → ×3 vs ×2; Four → ×4 vs ×2). Match-decisive.

**Recommended fix:** apply the same Sun-rung-collapse pattern in both
Net.lua handlers:
```lua
local mult = K.MULT_BASE
if c.type == K.BID_SUN then
    mult = mult * K.MULT_SUN
    if c.doubled then mult = mult * K.MULT_BEL end
else
    if     c.gahwa   then mult = mult * K.MULT_FOUR
    elseif c.foured  then mult = mult * K.MULT_FOUR
    elseif c.tripled then mult = mult * K.MULT_TRIPLE
    elseif c.doubled then mult = mult * K.MULT_BEL end
end
```

**Cross-ref:** review_v0.10.0/reaudit_R2_*.md for the original
defensive-normalization fix in R.ScoreRound.

---

### Doctrinal note (NOT a bug, but flag for user)

The v0.10.1 M1 user-arbitration distinguishes between Qaid contexts
(offender forfeits melds) and regular failed-bid (each team keeps own
melds). The prompt's Scenario 6 expected output ("bidder retains
Carré-A meld") matches PRE-v0.10.1 behavior. The current code is
v0.10.1-compliant. Worth confirming with the user that the v0.10.1
arbitration is still authoritative for v0.10.2 — or whether the
prompt's mental model represents an as-yet-unraised reconsideration.

---

## Cross-references

- `Rules.lua:692-984` — full `R.ScoreRound`.
- `Rules.lua:823-893` — outcome dispatch (fail/take/make).
- `Rules.lua:914-924` — multiplier ladder with Sun-rung collapse.
- `Net.lua:2165-2377` — `N.HostResolveTakweesh`.
- `Net.lua:2891-3055` — `N.HostResolveSWA` (invalid + valid branches).
- `Constants.lua:54-55` — `HAND_TOTAL_HOKM=162`, `HAND_TOTAL_SUN=130`
  (last-trick +10 already baked in).
- `Constants.lua:68-72` — multiplier constants.
- `docs/strategy/saudi-rules.md:236-249` — failed-bid and multiplier
  doctrine.
- Prior findings:
  - `B-Net-03_takweesh_full.md` — Takweesh handler full audit.
  - `B-Net-04_swa_full.md` — SWA handler full audit.
  - `review_v0.10.0/_phase2_xref/xref_X1_penalty_multiplier.md` —
    cross-reference of penalty multiplier vs source rules.
  - `review_v0.10.0/reaudit_R2_*.md` — Sun-rung collapse fix in
    R.ScoreRound.
  - `audit_v0.7.1/45_takweesh_flow.md` — older takweesh-flow doc.
  - `audit_v0.9.0/26_rules_scoring.md` and
    `28_rules_aka_swa_takweesh.md` — broader scoring audits.
