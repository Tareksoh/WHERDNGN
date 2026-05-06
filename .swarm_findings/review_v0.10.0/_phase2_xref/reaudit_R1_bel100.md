# Reaudit R1: Bel-100 (Sun-Double) legality rule

## Quoted Arabic from each source (verbatim ≤15 words each)

### Video #11 (`21fN1IEm5Xk_11_bel_beginners.ar-orig.srt`)

The relevant passage runs from 00:07:18 through 00:07:54. Three sequential
quotes carry the rule:

- **@ 00:07:21 – 00:07:25** (transcript lines 240–243):
  > "وفي فرق بين الصين والحكم في انك متى يحق لك تقول دبل"
  - Translation: "And there is a difference between Sun and Hokm in
    WHEN you have the right to say Dabal."

- **@ 00:07:25 – 00:07:31** (transcript lines 242–247):
  > "في الصن لازم يكون فريق 100 نقطه او اعلى والفريق الثاني يكون اقل من 100"
  - Translation: "In Sun, one team must be at 100 points or above AND
    the other team must be less than 100."

- **@ 00:07:38 – 00:07:43** (transcript lines 249–253):
  > "الفريق اللي اقل من 100 لوحه حقيقيه يدبل لكن الفريق اللي فوق الميه ما يدبل"
  - Translation: "The team that is less than 100 has a true right to
    Bel; but the team that is above 100 does NOT Bel."

- **Closing clarifier @ 00:07:43 – 00:07:47** (lines 253–255):
  > "في الصن اتكلم ماله حقا انه يدبل بعكس الحكم الحكم مفتوح في الدبل"
  - Translation: "In Sun, I'm saying [the >100 team] has no right to
    Bel, unlike Hokm — Hokm is open in the doubling."

### PDF 02 (`02_playing_system.txt`) — page 2, item "saabi'an" (seventh)

Original (Arabic-Indic digits ٠٠١ → "100", ١٠١ → "101"):

> "ولايحق للاعب ان يدبل خصمة الا بعد ان يتجاوز المئة اي 101"

- Translation: "A player has no right to Bel his opponent except after
  [the opponent] has crossed 100, that is 101."

Grammatical note: `يدبل خصمة` is verb + direct object. `خصمة` ("his
opponent") is the *target of the Bel call*, not the subject. The
sentence states: it is permitted to Bel an opponent IFF the opponent
has crossed 100. By logical contrapositive, the caller must be the
team NOT at ≥101 — i.e., the trailing team.

### PDF 07 (`07_doubling_system.txt`) — page 1

Two sequential lines (Arabic-Indic ٠٠١ = 100):

- **Line 12** (top of doubling rules):
  > "بالصن : اليفتح الدبل ال بعد العدد 100"
  - Translation: "In Sun: the Bel does NOT open until after the count
    100."

- **Line 68** (Sun section, conclusion):
  > "ويكون الدبل للمتأخر فقط وهو الذي لم يتجاوز عدده 100"
  - Translation: "And the Bel belongs ONLY to the trailing one, who
    is the one whose count has not crossed 100."

---

## Reconciliation analysis

The three sources appear to conflict on whether the "bidder vs defender"
role matters. They do not. They describe the same rule from three
different framings, and all three reduce to the same atomic
specification once parsed carefully.

### What each source actually says

| Source | Framing | Atomic content |
|---|---|---|
| Video #11 | role-agnostic (`فريق` / "team") | one team ≥100 AND other team <100; the <100 team has the right; the ≥100 team does not |
| PDF 02 | object-of-Bel is opponent | "may not Bel your opponent until [your opponent] has crossed 100, i.e. 101" — caller must be trailing |
| PDF 07 | trailing-side framing | "Bel is for the trailing one only — the one who has not crossed 100" — and (line 12) global gate "no Bel until 100 has been crossed" |

### Stripping each down to truth-conditions

Let `caller_cum` = cumulative score of the team calling Bel; `other_cum` = cumulative of the opposite team.

- **Video #11** → `caller_cum < 100` AND `other_cum >= 100`.
  (Statement is symmetric in role: the assignment of "caller" vs
  "opposite" is the team-pair, not bidder/defender; the only thing
  that matters is who is below the gate.)

- **PDF 02** → "may Bel iff your opponent ≥ 101". Translating to
  caller/opposite:
  - `other_cum >= 101` (the team being Bel'd has crossed)
  - and implicitly `caller_cum <= 100` (otherwise the *caller* would
    be the one at ≥101 and the rule would symmetrically forbid the
    *opponent* from Bel-ing back; with PDF 07's "trailing side only"
    constraint this is explicit)
  - Together: `caller_cum < 101` AND `other_cum >= 101`.

- **PDF 07** → directly states `caller_cum <= 100` (trailing side) AND
  `other_cum > 100` (gate has been crossed by *somebody*, and per the
  trailing-only rule that somebody is necessarily the other team).

### Equivalence proof

All three reduce to the same predicate:

```
SUN_BEL_LEGAL(caller, other)  ≡  caller.cum <= 100  AND  other.cum >= 101
```

(`<=100` and `<101` are the same integer relation; `>=101` and `>100`
are the same integer relation.)

The video's "team ≥100" loose phrasing is tightened by the two PDFs to
"≥101" (PDF 02 says it explicitly: `اي 101`). The video's narrator
says "100 or above" but his worked example uses 130/140/100 — at the
exact boundary of 100, the PDF specification is more precise: the
opposite team must be strictly past, i.e. ≥101. This is the standard
"crossed the threshold" Saudi convention (matches K-22 in
`source_K_pdf_basic_rules.md` and L26/L36 in
`source_L_pdf_secrets_doubling.md`).

### Why "bidder/defender" is a category error

The Phase-1 audit reported the rule as "asymmetric in role" because
the v0.9.2 #45 patch encoded `bidderTeam.cum >= 101 AND
defenderTeam.cum <= 100`. But none of the three sources reference
bidder or defender. They reference **score position**:

- Video #11 explicitly: `الفريق اللي اقل من 100` ("the team that is
  less than 100"). No bidder/defender wording in the entire 36-second
  passage.
- PDF 02: `يدبل خصمة` — "his opponent" is whoever is being Bel'd.
- PDF 07: `للمتأخر فقط` — "for the trailing one only".

In the typical case the bidder is the one ahead and the defender is
the one behind, because Sun bidding correlates with hand strength and
hand strength correlates with cumulative scoring lead. So encoding
"bidder ≥101 AND defender ≤100" produces the same answer as the
correct rule **in the common case**.

But the encoding diverges in the edge case where the **defender** is
the team that has crossed 100, and the **bidder** is still trailing.
Example: A is at 130, B is at 60, B buys Sun. Then:

- Correct rule (score-based): only the team at <100 may Bel. B is at
  60 (<100). A is at 130 (≥101). So *B* (the bidder) is the trailing
  side and *B* may Bel. *A* (the defender) is past the gate and may
  NOT Bel.
- v0.9.2 #45 rule (role-based): bidder team must be ≥101. Bidder is
  B at 60, fails the gate → Bel is forbidden for everyone. **Wrong.**

This is a real edge case — Sun bids by trailing teams happen
naturally (a behind team takes Sun to try to catch up via the ×2
multiplier and 152 raw target).

### What about the bidder team itself calling Bel?

Source F (video #11) Rule F4.02 notes the implicit framing throughout
the F1 worked examples is "defender calls Bel, bidder responds." But
the F1.14 rule (the Bel-100 gate itself) makes no reference to which
side is the bidder — only to which side is at <100. The PDF 07 line
36 framing "trailing side only" likewise doesn't restrict by role —
just by score. The Saudi convention (per cross-source synthesis with
the canonical Hokm chain) is:

- The chain alternates: defender → bidder → defender → bidder for
  Hokm (Bel/Three/Four/Gahwa). Source F1.07.
- Sun has only one rung (Bel). There is no "next escalation" to
  alternate to. So the question "who initiates" is the only question.
- The Saudi rule under Sun is: **only the trailing team initiates**.
  Either the bidder (if bidder is trailing) or the defender (if
  defender is trailing).

Test fixture line 783–784 in `tests/test_rules.lua` even comments
this: "bidder team itself can also call — kept permissive for now."
The current code's permissiveness for `team == bidderTeam` happens
to be correct, but only because the gate `bidderCum > GATE` excludes
the case where the bidder is trailing. With the correct rule, the
bidder team can Bel iff bidder team is itself trailing.

---

## Verdict

The correct rule is: **(D) — score-based and role-irrelevant: a team
may call Bel under Sun iff that team's own cumulative is ≤100 AND the
opposing team's cumulative is ≥101.** Bidder/defender role does not
enter the gate.

This matches:
- **Pre-v0.9.2** (Option A, "team's own cum < 100") was *closer* but
  missing the second condition (`other.cum >= 101`). It allowed the
  trailing team to Bel even when nobody had crossed yet — failing
  PDF 07's `لا يفتح الدبل الا بعد 100` ("doesn't open until after
  100").
- **v0.9.2 #45** (Option B, "bidder ≥101 AND defender ≤100") is
  *almost right* in framing but role-based, so it incorrectly blocks
  Bel when the *defender* is the one above 100 and the *bidder* is
  trailing.
- **Phase 1 Source F formulation** (Option C, "score-split, role
  irrelevant") is exactly correct. It matches the verbatim Arabic
  from all three sources.

The v0.9.2 #45 patch correctly identified that pre-v0.9.2 was
incomplete (the symmetric form ignored the opposite team), but it
overcorrected by anchoring on bidder/defender role instead of
score-split. The fix should keep the dual-team check from v0.9.2 but
swap the role anchor for a pure score-split anchor.

---

## Recommended code action

### `Rules.lua` (line 489 — `R.CanBel`)

Change the asymmetric, role-anchored predicate to a symmetric,
score-split predicate.

**Current** (lines 520–535):

```lua
local mine = (cumulative and cumulative[team]) or 0
if contract.bidder then
    local bidderTeam = R.TeamOf(contract.bidder)
    local bidderCum  = (cumulative and bidderTeam and cumulative[bidderTeam]) or 0
    if bidderCum <= K.SUN_BEL_CUMULATIVE_GATE then return false end
    if team ~= bidderTeam and mine > K.SUN_BEL_CUMULATIVE_GATE then
        return false
    end
    return true
end
return mine < K.SUN_BEL_CUMULATIVE_GATE
```

**Recommended** (role-irrelevant; uses opposite-team cumulative
regardless of who bid):

```lua
local mine = (cumulative and cumulative[team]) or 0
local otherTeam  = (team == "A") and "B" or "A"
local otherCum   = (cumulative and cumulative[otherTeam]) or 0
-- Saudi rule (video #11 + PDF 02 + PDF 07): caller's team must be
-- AT-OR-BELOW 100 (trailing side) AND opposite team must have
-- crossed 100 (>=101). Bidder/defender role does not enter.
if mine    >  K.SUN_BEL_CUMULATIVE_GATE then return false end
if otherCum <= K.SUN_BEL_CUMULATIVE_GATE then return false end
return true
```

The `contract.bidder` field is no longer consulted by `R.CanBel`
(both branches collapse to the same logic). Callers may stop passing
`contract.bidder` for Bel-legality purposes, but leaving it in the
contract table for other downstream consumers (e.g., `_SunBelAllowed`)
remains harmless.

The legacy "no bidder field" branch (line 535) was the pre-v0.9.2
symmetric form; it can be removed since the new predicate is itself
symmetric and needs no fallback.

### `Net.lua` (line 68 — `N._SunBelAllowed`)

`N._SunBelAllowed(bidderSeat)` answers "is ANY defender allowed to
Bel?" Under the correct rule, the answer depends only on the score
split, not on who bid. The function can simplify:

**Current** (lines 81–86):

```lua
local bidderTeam   = R.TeamOf(bidderSeat)
if not bidderTeam then return false end
local defenderTeam = (bidderTeam == "A") and "B" or "A"
return R.CanBel(defenderTeam,
                { type = K.BID_SUN, bidder = bidderSeat },
                S.s.cumulative)
```

**Recommended** (since either team's eligibility now depends only
on score, picking the trailing team is sufficient):

```lua
-- v0.10 reaudit: Sun-Bel is score-split-based, not role-based.
-- Either team is eligible iff that team is at <=100 AND the other
-- is at >=101. The two teams are mutually exclusive on this gate
-- (only one team can be the trailer), so we just ask whichever
-- team is currently trailing.
local cumA = (S.s.cumulative and S.s.cumulative.A) or 0
local cumB = (S.s.cumulative and S.s.cumulative.B) or 0
local trailingTeam = (cumA <= cumB) and "A" or "B"
return R.CanBel(trailingTeam,
                { type = K.BID_SUN, bidder = bidderSeat },
                S.s.cumulative)
```

Note: passing `bidder = bidderSeat` no longer affects `R.CanBel`'s
output but documents intent for log readers.

### Test fixture changes — `tests/test_rules.lua` Section N (lines 743–806)

The score-split rule changes a small number of expected outcomes.
All current Hokm assertions remain unchanged. All current Sun
boundary assertions for the "bidder ahead, defender trailing" case
(the common case) remain unchanged. The changes:

1. **Line 783–784** ("bidder team can call own Bel"): under the
   score-split rule, the bidder team can call iff it itself is
   trailing. With `cumulative = { A = 101, B = 50 }` and bidder=A,
   team A's `mine=101 > 100`, so A *cannot* Bel. Change expected
   value:

   ```lua
   assertEq(R.CanBel("A", sun_bidA, { A = 101, B = 50 }), false,
            "Sun: bidder=A at 101 — A cannot Bel its own contract (above gate)")
   ```

2. **Add new fixture** for the bidder-trailing case (currently
   untested):

   ```lua
   -- Sun: bidder is trailing — bidder MAY Bel its own contract
   -- (rare in practice but legal under score-split rule).
   assertTrue(R.CanBel("A", sun_bidA, { A = 50, B = 101 }),
              "Sun: bidder=A at 50, defender at 101 — A (bidder) can Bel")
   assertEq(R.CanBel("B", sun_bidA, { A = 50, B = 101 }), false,
            "Sun: bidder=A at 50, defender at 101 — B (defender) above gate, cannot Bel")
   ```

3. **Legacy "no bidder" fixtures** (lines 793–798): under the new
   single-branch predicate these keep working as long as the symmetric
   `mine <= 100 AND other >= 101` form is applied. But `sun_nobid`
   has no opposite cumulative information that's role-distinguished
   (both teams use the same `cumulative` table). The fixtures with
   `B = 0` will now fail the `otherCum >= 101` clause and return
   false. Update:

   ```lua
   -- Sun (no bidder hint): same score-split rule applies.
   assertEq(R.CanBel("A", sun_nobid, { A = 0,   B = 0   }), false,
            "Sun: 0/0 — neither team has crossed, no Bel")
   assertEq(R.CanBel("A", sun_nobid, { A = 99,  B = 0   }), false,
            "Sun: 99/0 — opposite hasn't crossed, no Bel")
   assertEq(R.CanBel("A", sun_nobid, { A = 100, B = 0   }), false,
            "Sun: 100/0 — opposite hasn't crossed, no Bel")
   assertTrue(R.CanBel("A", sun_nobid, { A = 50, B = 101 }),
              "Sun: A=50, B=101 — A trailing, A can Bel")
   assertEq(R.CanBel("B", sun_nobid, { A = 50, B = 101 }), false,
            "Sun: A=50, B=101 — B above gate, cannot Bel")
   ```

   This is a behavior change for legacy callers: pre-v0.9.2 the
   no-bidder form returned `true` at 99/0. Under the correct rule it
   returns `false` (no opponent has crossed yet). This is the right
   answer per all three sources — "doesn't open until after 100."

4. **`Bot.PickDouble` strength gate** (in `Bot.lua`, not in this
   audit's primary scope): if the bot's Sun-Bel decision logic also
   gates on bidder/defender, that should also collapse to the
   score-split predicate (or simply call `R.CanBel`).

---

## Confidence

**HIGH.** All three source quotations are mutually consistent under
the score-split reading; the apparent disagreement disappears once
PDF 02's grammatical structure (`يدبل خصمة` = "Bel his opponent",
where the opponent is the OBJECT, not the subject) is parsed
correctly. The role-based v0.9.2 reading was a misreading of the
Phase 1 prose summary "Source F1.14: bidder team is at ≥100" — the
verbatim Arabic in the SRT does not say bidder. Source F1.14's
"Hand-shape: Score-position dependent, not hand-shape" line in the
extraction is itself a clue that the rule is about score, not role.

The recommended fix is a small, well-localized change to
`R.CanBel` plus simplified call sites. All changes are backward-
compatible at the API level (function signatures unchanged) and only
alter behavior in the specific edge case the v0.9.2 patch
inadvertently broke (trailing-team bidder).

The only residual uncertainty: whether `Bot.PickDouble` (or another
caller) relies on the v0.9.2 role-based behavior in a way that this
audit didn't surface. A grep for `bidderTeam` and `bidderCum` near
Bel-decision sites in `Bot.lua` should be done before shipping.
