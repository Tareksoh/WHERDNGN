# B-Rules-05: `R.CanBel` — Sun Bel-100 legality gate (post-v0.10.0 R1)

**Scope:** verify the v0.10.0 R1 rewrite of `R.CanBel` (score-split,
role-irrelevant) is correctly aligned across `Rules.lua`, `Net.lua`,
and `Bot.lua`, and that every boundary case matches the Saudi rule
distilled in `reaudit_R1_bel100.md`.

**Files inspected:**

- `C:\CLAUDE\WHEREDNGN\Rules.lua` lines 509–561 (`R.CanBel`)
- `C:\CLAUDE\WHEREDNGN\Net.lua` lines 57–83 (`N._SunBelAllowed`),
  860–913 (`N._OnDouble`), 1843–1871 (`N.LocalDouble`)
- `C:\CLAUDE\WHEREDNGN\Bot.lua` lines 3431–3543 (`Bot.PickDouble`)
- `C:\CLAUDE\WHEREDNGN\tests\test_rules.lua` lines 767–847 (Section N)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\reaudit_R1_bel100.md`
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\21fN1IEm5Xk_11_bel_beginners.ar-orig.srt`
  (timecodes 00:07:18–00:07:54; SRT caption blocks 239–263; the
  prompt's "lines 240–260" reference is to caption-block numbers
  per the R1 reaudit's convention, not raw file lines)
- `C:\CLAUDE\WHEREDNGN\Constants.lua` line 329
  (`K.SUN_BEL_CUMULATIVE_GATE = 100`)

---

## Findings

### F1 — Predicate alignment across the three call-sites: **CLEAN**

All three sites consult the same `R.CanBel(team, contract, cumulative)`
predicate. There is no re-divergence (no parallel role-anchored copy
left over from v0.9.2 #45):

| Site                  | How it consults `R.CanBel`                                          |
|-----------------------|---------------------------------------------------------------------|
| `Bot.PickDouble`      | `R.CanBel(R.TeamOf(seat), contract, S.s.cumulative)` (Bot.lua:3442) |
| `Net._OnDouble`       | `R.CanBel(R.TeamOf(seat), S.s.contract, S.s.cumulative)` (Net.lua:887) |
| `Net.LocalDouble`     | `R.CanBel(R.TeamOf(S.s.localSeat), S.s.contract, S.s.cumulative)` (Net.lua:1854) |
| `Net._SunBelAllowed`  | computes trailing team, then `R.CanBel(trailingTeam, ...)` (Net.lua:79–82) |

`Net._SunBelAllowed` is the "is anyone allowed?" probe (used to decide
whether to skip the Bel phase entirely). Picking the trailing team is
correct because the gate is mutually exclusive: `mine ≤ 100 AND
other ≥ 101` can be satisfied by at most one team. Documentation in
the Net.lua comment block (lines 70–76) explicitly notes this.

### F2 — Hokm path: **CORRECT (always-true)**

`Rules.lua:525-527`: early-return `true` when `contract.type ~=
K.BID_SUN`. Verified in tests at `test_rules.lua:789-793` (Hokm at
0/0, 99/0, 100/0, 200/0 all return true). Matches video #11 closing
clarifier @ 00:07:43-47: "Hokm is open in the doubling, whether you
are above or below 100" (`الحكم مفتوح في الدبل سواء كنت اعلى من 100
او اقل`).

### F3 — Boundary cases: **ALL FOUR MATCH SAUDI RULE**

The implementation is `mine > GATE → false; otherCum <= GATE →
false; else true`, with `GATE = 100`. Walk through:

| Caller cum | Opposite cum | `mine > 100` | `otherCum <= 100` | Result | Saudi-rule expected |
|------------|--------------|--------------|--------------------|--------|---------------------|
| 100        | 101          | F            | F                  | TRUE   | YES (caller≤100, opp≥101) |
| 99         | 100          | F            | T                  | FALSE  | NO  (gate not crossed) |
| 50         | 200          | F            | F                  | TRUE   | YES |
| 200        | 50           | T            | (short-circuit)    | FALSE  | NO  |

Tests in Section N pin all four:

- Line 803-804 (caller=100, opp=101): `assertTrue` — passes.
- Line 799-800 (caller=0, opp=100): `assertEq false` — passes.
  This pins "opposite must be **strictly** ≥ 101", not just ≥ 100,
  matching PDF 02's `اي 101`.
- Line 815-816 (caller=A=50, opp=B=101): `assertTrue` — passes,
  even when the trailing caller is the **bidder team** (the v0.9.2 #45
  edge case).
- Line 810-811 (caller=A=101, opp=B=50): `assertEq false` — passes,
  bidder team above gate may not Bel its own contract.

### F4 — Tied 100/100: **TREATED AS LOCKED-OUT (correct)**

`R.CanBel("A", sun, { A=100, B=100 })` evaluates: `100 > 100` false;
`100 <= 100` true → returns false. Both teams are locked out.

This is consistent with the Saudi rule: nobody has crossed 100, so
the gate has not opened (PDF 07 line 12: `لايفتح الدبل ال بعد العدد
100` — "Bel does not open until after the count 100"). Tied 100/100
is the boundary — neither team is past 100, so neither team can call.
Section N does not have an explicit 100/100 fixture, but lines 799–800
(caller=100, opp=0 → false) plus line 805–806 (caller=A=101, opp=B=101
→ false because B itself >100) jointly cover the "neither side trails"
shape. **Recommend** adding a literal 100/100 case to make the boundary
self-documenting; current coverage proves it by inference.

### F5 — Bidder-trailing edge case (R1 fix): **VERIFIED in `R.CanBel`,
but a structural divergence exists at the wire**

The R1 reaudit's worked example: A=130, B=60, **B bids Sun**. Per
the score-split rule, B (the bidder team, trailing) may Bel.
`R.CanBel("B", sun_bidB, { A=130, B=60 })` → `60 > 100` false, `130 <= 100`
false → **true**. Correct, and pinned by Section N line 821-822
(`R.CanBel("A", sun_bidB, { A=0, B=101 })` → true).

**However**, `Net._OnDouble` and `Net.LocalDouble` both gate
authority on `seat == (S.s.contract.bidder % 4) + 1` — i.e., only
the **single seat to the bidder's right**. This is always a defender
seat. Worked example with bidder = seat 2 (team B), trailing:

- `eligibleSeat = (2 % 4) + 1 = 3` → seat 3 is on team A.
- Team A is at 130 (≥ 101) → `R.CanBel("A", ...)` returns false.
- Team B (the bidder team, trailing, would-pass `R.CanBel`)
  cannot send a Bel at all because no team-B seat satisfies
  `seat == eligibleSeat`.

Consequence: the rule predicate (`R.CanBel`) admits the bidder-
trailing case, but the wire never lets it surface. Effective behavior
matches v0.9.2 (bidder team blocked) in this specific seat-routing
sense even though the predicate has been corrected.

This is **not** a regression introduced by v0.10.0 R1 — the
`(bidder % 4) + 1` restriction predates the score-split rewrite — but
it is a quiet semantic mismatch between the unit-test surface (which
asserts `R.CanBel` correctness in isolation) and the live integration
path. Neither the R1 reaudit nor the v0.10.0 changelog calls this
out; it is an undocumented divergence.

Severity: **MEDIUM**. The case is rare in practice (Sun bids by
a trailing team are uncommon) but real, and is exactly the case the
R1 fix was advertised as enabling.

### F6 — Round-1 anti-grief (Phase1-F F1.16): **NOT IMPLEMENTED, NOT DOCUMENTED**

Per Phase1-F finding F1.16 + video #11 lines 1296-1320 (00:07:52-08:03)
this is OPTIONAL session house-rule (`بعض الجلسات ما تسمح في بدايه
اللعب` — "some sessions don't allow [Bel] at the start of play"). The
narrator explicitly hedges with `ممكن` ("might"). No implementation is
required, but the absence is also not documented as an intentional
omission. `R.CanBel`'s comment block does not mention it; CLAUDE.md
does not list it under "Important non-obvious rules"; CHANGELOG v0.10.0
R1 entry does not address it. **Recommend** a one-line note in
`R.CanBel`'s docstring acknowledging that Phase1-F F1.16 is an OPTIONAL
session rule deliberately left unenforced.

### F7 — Cards-revealed lockout (Phase1-F F1.04 + F1.05): **NOT IMPLEMENTED**

The Saudi rule (video #11 00:01:33-02:01) is a hard timing-window
ceiling: once any player has revealed their cards, no Bel may be
declared. `R.CanBel` has no temporal/state argument to enforce this;
no UI gate observed in `UI.lua` 1768+ that tracks reveal state vs Bel
window; no `belPending` field carries a "first-reveal seen" flag.

The current implementation relies entirely on the addon's
phase-machine: `S.s.phase == K.PHASE_DOUBLE` is the formal Bel
window, and the host advances out of it on timeout or skip-double.
This effectively substitutes "phase machine timeout" for the Saudi
"first-reveal cutoff" — close enough in the addon's UX but not the
literal rule.

Severity: **LOW** for the addon (phase-timer fills the role); **MEDIUM**
as a documentation gap (the substitution is undocumented).

### F8 — Maqfūl under even-multiplier Hokm (Phase1-F F1.08, F1.09): **NOT IMPLEMENTED**

Per F1.08 + F1.09: under Hokm, EVEN multipliers (×2 = Bel, ×4 = Four)
put play in `مقفول` ("closed") mode where leading trump is forbidden
unless the leader holds only trump. Searched `R.IsLegalPlay`
(Rules.lua:89–217), `Bot.PickPlay`, `BotMaster.PickPlay`, all of
`UI.lua`: zero references to `maqful`, `leadTrump`, `cantLeadTrump`,
`evenMultiplier`, or any equivalent gate. Bots may freely lead trump
under ×2/×4 Hokm; UI does not mark such leads illegal.

Severity: **MEDIUM-HIGH** as a rule gap — F1.08/F1.09 are HIGH-confidence
Saudi-canonical rules per Phase1-F (not house-rule). Likely a separate
finding from this audit's primary scope (Bel-100 gate); flagging here
because the code/docs/test silence is total. **Strongly recommend** a
dedicated track-B finding (e.g., `B-Rules-XX_maqful.md`).

### F9 — `nil`-safety: **CORRECT**

Walked through each nil case:

- `cumulative = nil` → `mine = 0`, `otherCum = 0`; `0 > 100` false,
  `0 <= 100` true → returns false. Defensive ✓.
- `cumulative = { A = nil, B = nil }` → identical to nil-table case ✓.
- `contract = nil` → early return false (line 524) ✓. Pinned at
  test_rules.lua:846.
- `team = nil` → early return false (line 524) ✓. Pinned at
  test_rules.lua:844-845.
- `team = "A"`, `cumulative = { A = nil, B = 200 }` → `mine = 0`,
  `otherCum = 200`; returns true ✓.
- `team = "C"` (invalid): `cumulative["C"]` → nil → 0; `otherTeam =
  "B"` (since `team ~= "A"`); falls through to score check. No crash;
  result is meaningless but bounded. Acceptable.

### F10 — `contract.bidder` vestigial reference: **CONFIRMED CLEAN**

`R.CanBel` body (lines 555-560) does not reference `contract.bidder`.
Comment at lines 552-554 explicitly states: "*`contract.bidder` is no
longer consulted here (kept in the contract table for log-readability
and other consumers, but harmless to omit)*". `contract.bidder` IS
still consulted by sibling Rules-layer functions:

- `R.CanOvercall` (Rules.lua:577)
- `R.ResolveOvercall` (Rules.lua:615)
- `R.ScoreRound` (Rules.lua:677)

These uses are unrelated to Bel-100 and are correct in their own
context. Aside from those, `contract.bidder` has 97 occurrences across
12 files (BotMaster, Bot, UI, State, Net, multiple test fixtures) —
not vestigial; kept because many downstream consumers need it.
**No dangling reference exists in `R.CanBel` itself.**

### F11 — Test fixture coverage (Section N, lines 767-847): **STRONG**

Section N covers:
- Hokm always-true (5 fixtures: 0/0, 99/0, 100/0, 200/0, B at 100).
- Sun gate-not-yet-crossed (5 fixtures across `sun_bidA` and
  `sun_nobid`: 0/0, A=100/B=0, both legacy and new-shape).
- Sun common case bidder-ahead (lines 801-806).
- Sun edge case: bidder team ABOVE gate cannot Bel own contract (810-811).
- Sun edge case: BIDDER-TRAILING — bidder team CAN Bel (815-818).
  This is the v0.10.0 R1 fix's headline case.
- Sun mirror with `bidder=B` (821-824).
- Legacy `sun_nobid` shape (no bidder field) — same score-split rule
  applies (830-839).
- Defensive nil-handling (842-846).

Gaps:
- No literal 100/100 tied-cumulative fixture (covered by inference; see
  F4).
- No fixture for `cumulative.B = nil` partial-table.
- No integration-level test verifying that the wire-side
  `Net._OnDouble` + `(bidder%4)+1` seat restriction interacts cleanly
  with a bidder-trailing Sun (the F5 divergence). This is exactly the
  case the rule allows but the wire blocks.

---

## Verdict

**The R.CanBel function itself is CORRECT and aligned across all three
in-scope call-sites (`Rules`, `Net._SunBelAllowed`, `Bot.PickDouble`).**
The score-split predicate matches the verbatim Saudi rule from video
#11, PDF 02, and PDF 07 — the three sources reduce unanimously to
`caller.cum ≤ 100 AND opposite.cum ≥ 101` once parsed. All four
boundary cases listed in the prompt evaluate correctly. The vestigial
`contract.bidder` reference has been correctly removed from the body
of `R.CanBel` (verified at lines 555–560), and downstream consumers
who need `contract.bidder` for unrelated purposes are unaffected.

**Three caveats sit on top of the otherwise-clean fix:**

1. **(F5, MEDIUM)** The wire-side authority gate
   `seat == (S.s.contract.bidder % 4) + 1` in `Net._OnDouble` and
   `Net.LocalDouble` restricts Bel to a single defender seat. In the
   bidder-trailing edge case (the v0.10.0 R1 headline scenario),
   `R.CanBel` correctly returns true for the bidder team but no
   team-bidder seat satisfies the wire eligibility. The unit test
   does not exercise this integration path, so the fix's stated
   benefit ("trailing bidder may Bel") does not actually surface in
   live play. This is a quiet, undocumented mismatch between
   predicate and wire.

2. **(F6, F7, LOW-MEDIUM doc gap)** Round-1 anti-grief and
   cards-revealed lockout (Phase1-F F1.04, F1.05, F1.16) are
   not implemented. F1.04/F1.05 are partly absorbed by the addon's
   phase-machine; F1.16 is explicitly OPTIONAL session house-rule.
   None of this is documented as intentional omission in
   `R.CanBel`'s comment block, the v0.10.0 R1 changelog entry, or
   `CLAUDE.md`. **Recommend** a one-paragraph "intentionally not
   enforced" note next to `R.CanBel`.

3. **(F8, MEDIUM-HIGH but out of scope)** Maqfūl mode (F1.08, F1.09)
   — even-multiplier Hokm bans leading trump — is entirely absent.
   This is a HIGH-confidence Saudi-canonical rule, not a house-rule.
   Out of this audit's primary scope but flagged for a dedicated
   track-B finding.

For the v0.10.2 review's question "is `R.CanBel` correct after the R1
fix?" the answer is **YES, with caveats**: the predicate is right, the
test pins are right, the cross-site delegation is clean. The only
follow-up work that touches `R.CanBel`'s correctness is closing the F5
wire-vs-predicate divergence (or documenting it as deliberate).

## Confidence

**HIGH** for the correctness of `R.CanBel` and its callers' delegation
(F1–F4, F9, F10). The implementation is small, has a single integer
predicate, is exercised by 19 explicit test assertions in Section N,
and the test suite passes 362/362.

**HIGH** for the F5 wire/predicate divergence finding (verified by
walking through `(bidder % 4) + 1` arithmetic for both bidder=1 and
bidder=2 cases, against R.TeamOf and the test fixtures).

**HIGH** for the F6–F8 missing-feature observations (verified by
exhaustive grep for `maqful`, `revealed`, `lockout`, `firstReveal`,
`leadTrump`, `evenMultiplier`, etc., across all `*.lua` files; zero
matches in production code).

**MEDIUM** on whether F5 is a true bug or an intentional simplification
(the addon may simply have decided "bidder team Bel'ing own contract
is rare and unsupported" without writing it down). Resolving that
requires user/maintainer input.
