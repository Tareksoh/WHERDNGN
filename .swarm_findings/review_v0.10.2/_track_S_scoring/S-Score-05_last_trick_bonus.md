# S-Score-05: Last-Trick +10 single-application invariant (v0.10.2)

## 1. TL;DR

**`K.LAST_TRICK_BONUS = 10` is correctly single-applied** at `Rules.lua:703` to the trick-WINNER team (not bidder), inside the per-trick aggregation loop. Multiplier-aware: it flows through `cardA/cardB` in the make path and gets ×mult at line 926. Al-Kaboot replaces it cleanly: the sweep branch overwrites `cardA/cardB` with `K.AL_KABOOT_HOKM=250` / `K.AL_KABOOT_SUN=220` and discards the accumulated `teamPoints` (so the +10 is NOT double-counted on top of 250/220). Belote +20 is correctly applied AFTER the multiplier (line 939-943), so the +10 (inside mult) and +20 (outside) don't cross-contaminate.

**One real defect** worth flagging in this scope: when `tricks[8].winner == nil` (e.g., a partial broadcast or hand-edited save), `R.TeamOf(nil)` returns `"B"` silently (Rules.lua:25-28), so the +10 gets attributed to team B regardless of who actually won — the same F-04 silent-misclassification issue from `B-Rules-02_scoreRound.md` but applied to the LAST_TRICK winner not the bidder. No known caller currently passes nil winner past `S.ApplyTrickEnd` (which guards 4-play trick at line 1306-1310), but the attribution code has zero defensive guard.

The fail and take branches DON'T use the running `teamPoints` for the bidder/loser side — they hand the entire `K.HAND_TOTAL_HOKM=162` (or `K.HAND_TOTAL_SUN=130`) to the winner, and 162/130 already INCLUDES the +10 by design (constants explicitly comment "152 cards + 10 last trick"). So the +10 is implicit in fail/take outcomes, not separately added — no ownership confusion in those paths.

Verdict: **CORRECT in all canonical paths.** The S.ApplyTrick path (state side-effect) does NOT touch the bonus — the bonus enters ONLY at scoring time inside `R.ScoreRound`. No double-counting. No ownership confusion in the canonical scenarios.

---

## 2. Per-scenario trace

### Scenario 1 — Bidder wins trick 8

**Trace path:** `Rules.lua:692-705` (per-trick aggregation loop).

```lua
for i, t in ipairs(tricks) do
    local team = R.TeamOf(t.winner)         -- line 697: TRICK-WINNER team
    local pts = R.TrickPoints(t, contract)
    teamPoints[team] = teamPoints[team] + pts
    trickCount[team] = trickCount[team] + 1
    if i == #tricks then
        lastTrickTeam = team
        teamPoints[team] = teamPoints[team] + K.LAST_TRICK_BONUS  -- line 703
    end
end
```

`team` at line 697 is computed from `t.winner` (the SEAT that won the trick), so the +10 at line 703 routes to `R.TeamOf(t.winner)` — the trick-winner team. **No reference to `contract.bidder` in this loop.** Bidder team is computed AFTER (line 708) and used only for threshold/branch dispatch, not for last-trick attribution.

Concrete: bidder = seat 1 (team A), trick 8 winner = seat 1, then `team = "A"`, `teamPoints.A += 10`. Then in `make` branch (line 889) `cardA = teamPoints.A` carries the +10. ✓ goes to bidder team because they ALSO happened to be the trick-8 winner, not because they're the bidder.

### Scenario 2 — Defender wins trick 8

Same trace. trick 8 winner = seat 2 (team B), bidder = seat 1 (team A). Line 697 → `team = "B"`. Line 703 → `teamPoints.B += 10`. Make branch → `cardB = teamPoints.B` includes +10. ✓ defender-team correctly gets the bonus.

**Critical question — is there any code path where +10 always goes to bidder?** I traced `Rules.lua:692-984` looking for `K.LAST_TRICK_BONUS` and `lastTrickTeam` references:
- Line 703: ONLY add-site. Indexed by `R.TeamOf(t.winner)`, NOT `bidderTeam`.
- Line 695, 702: variable assignment to `lastTrickTeam` for the result struct only — read-only after.
- Line 973: returned in result struct as `lastTrickTeam` — informational, not consumed by scoring math.

Confirmed: **no ownership-confusion bug.** The +10 is unconditionally routed to `R.TeamOf(trickWinner)`, never to `R.TeamOf(bidder)`.

The only attribution risk is the F-04-flavor edge: `R.TeamOf(nil)` → "B" silently. See section 5 / Bug B-1.

### Scenario 3 — Last-trick + multiplier (Bel'd Hokm)

Bidder wins trick 8 in a Bel'd Hokm round (×2). Trace:
1. Per-trick loop: `teamPoints[bidderTeam] += 10` (line 703).
2. Make branch (line 889): `cardA, cardB = teamPoints.A, teamPoints.B` — `cardA` includes the +10.
3. Multiplier (line 914-924): `mult = K.MULT_BASE * K.MULT_BEL = 2`.
4. `rawA = (cardA + meldPoints.A) * mult` — line 926. The +10 (already in cardA) is multiplied. Effective: `+10 * 2 = +20 raw` contribution from last-trick.

**Arithmetic ordering: +10 is added BEFORE multiplication**, exactly as expected. Line 926 is the multiplication site; line 703 (the add) precedes it.

**Belote +20 stays OUTSIDE multiplier:** lines 939-943 add `K.MELD_BELOTE = 20` AFTER `rawA = (cardA + meldPoints.A) * mult`, so belote does not pick up the ×2 — it's a flat +20 raw.

This matches the canonical Saudi rule: "Belote multiplier-immune, last-trick is part of card-points and gets ×mult."

### Scenario 4 — Last-trick + Sun-collapse (Sun ×2)

Same trace, but `contract.type == K.BID_SUN`:
1. Line 703: `teamPoints[bidderTeam] += 10` (still happens, Sun or not).
2. Make branch: `cardA = teamPoints.A` includes +10.
3. Multiplier (line 915-918): `mult = 1 * K.MULT_SUN = 2`. (No `doubled` ⇒ no ×Bel stack.)
4. `rawA = (cardA + meldPoints.A) * 2`. Last-trick contribution: `10 * 2 = 20 raw`.

Hand-total sanity check: `K.HAND_TOTAL_SUN = 130 = 120 + 10` (per Constants.lua:55). 120 cards + 10 last-trick. So if bidder takes all card-points (120) + the last-trick bonus (10), `teamPoints.A = 130`. Then `rawA = 130 * 2 = 260`. div10 → 26 game points. ✓ matches video #43's "Sun divisor 5" interpretation: 260/10 = 26 ≡ 130/5 = 26.

### Scenario 5 — Al-Kaboot replaces normal scoring

**Trace path:** `Rules.lua:742-745` (sweep detection), `Rules.lua:847-853` (sweep branch in scoring dispatch).

```lua
local sweepTeam
if trickCount.A == 8 then sweepTeam = "A"
elseif trickCount.B == 8 then sweepTeam = "B" end
...
if sweepTeam then
    local bonus = (contract.type == K.BID_HOKM) and K.AL_KABOOT_HOKM or K.AL_KABOOT_SUN
    cardA = (sweepTeam == "A") and bonus or 0       -- line 850
    cardB = (sweepTeam == "B") and bonus or 0       -- line 851
    meldPoints.A = (sweepTeam == "A") and meldA or 0
    meldPoints.B = (sweepTeam == "B") and meldB or 0
elseif outcome_kind == "fail" then
    ...
```

**Critical observation:** lines 850-851 OVERWRITE `cardA, cardB` with the al-kaboot constant. The accumulated `teamPoints.A/B` (which contains the per-trick aggregation INCLUDING the +10 last-trick bonus added at line 703) is **DISCARDED** in this branch — it's never read in the sweep path.

So:
- The +10 was added to `teamPoints[sweepTeam]` at line 703, yes.
- But `cardA, cardB` are overwritten with `K.AL_KABOOT_HOKM=250` (or 220 for Sun) at line 850-851.
- `rawA = (cardA + meldPoints.A) * mult` (line 926) uses the OVERWRITTEN cardA.
- The +10 is NOT separately added on top of 250/220.

The bonus values 250/220 are CHOSEN to reflect the canonical Pagat al-kaboot magnitudes (Hokm 25 game points, Sun 44 game points — Pagat references in Constants.lua:111-115). The +10 last-trick is NOT independently visible in those values; it's subsumed into the al-kaboot constant.

This is correct per CLAUDE.md and the Pagat reading: "Al-Kaboot replaces normal scoring." There is no double-application of the +10.

### Scenario 6 — Last-trick + Belote-immune

Bidder wins trick 8 + holds Belote (K+Q of trump in same hand) in a Bel'd Hokm round (×2):
1. Line 703: `teamPoints[bidderTeam] += 10`.
2. Belote detection (lines 723-740): `belote = R.TeamOf(kWho)` → bidder's team (assuming K+Q are with the bidder).
3. Make branch (line 889): `cardA = teamPoints.A` includes +10.
4. Multiplier (line 914-924): `mult = 2` (Bel'd Hokm).
5. `rawA = (cardA + meldPoints.A) * mult` (line 926): the +10 is multiplied → `10 * 2 = 20 raw` contribution.
6. Belote +20 (lines 939-943): `rawA = rawA + K.MELD_BELOTE` — added AFTER mult. So +20 raw flat, NOT scaled.

**Cross-contamination check:**
- The +10 is in `cardA` BEFORE line 926 mult-application.
- The +20 (belote) is added to `rawA` AFTER line 926 mult-application.
- They never co-mingle: `+10` is multiplied, `+20` is not.

The orderings are correctly preserved: `rawA = (cardA + meldPoints.A) * mult + (belote == "A" ? 20 : 0)`.

### Scenario 7 — Tied last-trick / nil winner edge case

In real Saudi play, trick 8 cannot tie — there are 4 plays per trick and exactly one wins by `R.TrickWinner`. But defensively, what if `tricks[8].winner == nil`?

**Defense at the entry point:** `S.ApplyTrickEnd` (State.lua:1300-1310) explicitly rejects partial tricks (#plays != 4) and sets `s.trick.winner = winner` directly (line 1311) using the host-resolved winner. So in production, `tricks[i].winner` should never be nil if the trick is in `s.tricks`.

**No defensive guard at the scoring site:** `Rules.lua:697`: `local team = R.TeamOf(t.winner)`. If `t.winner == nil`, then `R.TeamOf(nil) → "B"` (Rules.lua:25-28: `if seat == 1 or seat == 3 then return "A" end; return "B"`). So:
- The +10 silently routes to team B.
- `lastTrickTeam = "B"` is exposed in the result struct.
- All trickCount, all per-trick-points routing for tricks with nil winners go to B.

If trick 8's winner is nil but tricks 1-7 are valid, the +10 goes to B and team B's `lastTrickTeam` field shows B. **No warning, no error, silent misattribution.**

This is an instance of F-04 from B-Rules-02 applied to the trick-winner attribution side (F-04 was about bidder seat → bidder team; here it's trick-winner seat → trick-winner team). Same `R.TeamOf(nil) → "B"` underlying root cause.

In practice, this is a defensive concern only: `S.ApplyTrickEnd` won't insert an invalid trick. But hand-edited saves, replay/resync edge cases, or future caller bugs could feed `R.ScoreRound` a `tricks[]` with a nil winner.

---

## 3. The "+10 ownership" question

**Is the +10 ever wrongly attributed to the bidder when defender won?** No.

Direct verification:
- The ONLY add-site is `Rules.lua:703`.
- The team selector is `team = R.TeamOf(t.winner)` (line 697), where `t` is the trick from `tricks[]` and `t.winner` is the SEAT of the trick winner.
- `bidderTeam` is computed at line 708 (`R.TeamOf(contract.bidder)`) AFTER the per-trick loop and is used only for the threshold check (line 794-797), the make/take/fail branch dispatch (line 845, 854, 872, 885), and the gahwa branch (line 957-968).

There is NO code path in `R.ScoreRound` where the +10 is added to `teamPoints[bidderTeam]` instead of `teamPoints[trickWinnerTeam]`.

**Edge case:** if `t.winner` is nil, ownership defaults to B silently. Bug B-1 below.

---

## 4. Al-Kaboot interaction

**Is the +10 baked into K.AL_KABOOT_HOKM=250 / K.AL_KABOOT_SUN=220?** Effectively yes, but indirectly:
- The sweep branch (line 848-853) overwrites `cardA, cardB` with the kaboot constant.
- The accumulated `teamPoints[sweepTeam]` (which DID receive the +10 at line 703) is discarded in this branch — `cardA = bonus`, not `cardA = teamPoints.A`.
- So the +10 contributes nothing to the final sweep raw.

Whether the value 250/220 conceptually "includes" the +10 is a question of Pagat-magnitude semantics, not code semantics. The code-level guarantee is: **the +10 is added once to `teamPoints` but discarded in the sweep branch, never compounded onto 250/220.**

**No bug.** This is correct behavior. The user-facing "you swept for 25 game points (Hokm)" matches Saudi convention without any need to add or subtract the +10 separately.

---

## 5. Bugs found

### Bug B-1 — `R.TeamOf(nil)` silent misattribution at last-trick site (LOW severity, defensive)

**Location:** `Rules.lua:697` (the `team = R.TeamOf(t.winner)` call inside the per-trick loop). Underlying root cause: `Rules.lua:25-28` (`R.TeamOf` returns "B" for any non-{1,3} seat, including nil).

**Issue:** If `tricks[i].winner` is nil for any i (most concerning: i=8), the +10 (line 703) and the entire trick's points (line 699) are silently attributed to team B. `lastTrickTeam = "B"` is reported in the result struct. No warning, no error.

**Reachability:** `S.ApplyTrickEnd` (State.lua:1300-1310) rejects partial tricks and stamps `s.trick.winner = winner` from the host-resolved winner. Production callers (`State.lua:1924`, `Net.lua:3038`, `BotMaster.lua:793`) all feed `R.ScoreRound` from `s.tricks` via `S.ApplyTrickEnd`. So in normal play, this path is not exercised.

But: hand-edited saves, replay/resync edge cases (a tricks[] reconstruction missing a winner), or future caller bugs could exercise it. The same defensive concern as F-04 in `B-Rules-02_scoreRound.md`, just applied to trick-winner attribution rather than bidder attribution.

**Recommendation:** Either (a) make `R.TeamOf` strict (return nil for unrecognized seats), or (b) add a defensive guard at line 697: `if not t.winner then -- log and skip end`. Option (b) has smaller blast radius. Or (c) align with B-Rules-02 F-04 — fix once, both attribution sites benefit.

**Confidence:** HIGH on the gap. LOW on production reachability.

### Bug B-2 — Last-trick bonus is not awarded if `tricks[]` has fewer than 8 entries (THEORETICAL, defensive)

**Location:** `Rules.lua:701` (`if i == #tricks then ...`).

**Issue:** The +10 is added when `i == #tricks` (last entry of `tricks[]`), not specifically when `i == 8`. If tricks[] is malformed (e.g., 7 entries due to truncated state), the +10 still fires but on trick 7's winner, not trick 8's. This is a misnomer at best, an attribution defect at worst. The function does not validate that `#tricks == 8`.

**Reachability:** Production callers always pass exactly 8 tricks (round-end is the only caller path), so this is not exercised in canonical play. But invalid-SWA or takweesh-resolve paths might call `R.ScoreRound` with a partial trick list — let me check.

Searching `R.ScoreRound` callers:
- `State.lua:1924` (CalcRoundResult-style call)
- `Net.lua:3038` (HostStepAfterTrick / round-end resolution)
- `BotMaster.lua:793` (ISMCTS rollout simulation)

In ISMCTS rollout (BotMaster.lua), the simulation always plays out to 8 tricks before calling ScoreRound. Net.lua only calls after MSG_TRICK has fired 8 times. So `#tricks` should be 8 in all real paths.

**Recommendation:** Document this implicit invariant ("R.ScoreRound assumes #tricks == 8"). Optionally add an `assert(#tricks == 8)` or early-return for safety. Not a blocking issue.

**Confidence:** HIGH on the implicit assumption. LOW on real-world impact.

### Non-bug — sweep + last-trick double-counting (verified absent)

I specifically checked: in the sweep branch, can the +10 at line 703 reach the final raw on top of 250/220? **No.** Line 850-851 overwrites `cardA, cardB` with the kaboot bonus, and the accumulated `teamPoints` (with the +10) is never read again in that branch. `meldPoints.A/B` are also overwritten on lines 852-853 to be winner-takes-all. Lines 926 (rawA = (cardA + meldPoints.A) * mult) uses the overwritten values. The +10 is NOT compounded onto the kaboot. ✓

### Non-bug — multiplier ordering (verified correct)

Last-trick +10 is INSIDE `cardA, cardB` (because line 889 sets `cardA = teamPoints.A` which includes the +10), so it gets `× mult` at line 926. Belote +20 is OUTSIDE the multiplier — added at lines 939-943 AFTER line 926. No cross-contamination. ✓

### Non-bug — fail/take branches and the +10

Both fail (line 854-871) and take (line 872-884) branches OVERWRITE `cardA, cardB` with `handTotal` (=K.HAND_TOTAL_HOKM 162 or K.HAND_TOTAL_SUN 130). The constants explicitly include the +10 (Constants.lua:54-55: "152 cards + 10 last trick"). The accumulated `teamPoints` (which DID receive the +10 at line 703) is discarded — same pattern as the sweep branch. No double-counting. ✓

---

## File references

- `C:\CLAUDE\WHEREDNGN\Constants.lua:53` — `K.LAST_TRICK_BONUS = 10`
- `C:\CLAUDE\WHEREDNGN\Constants.lua:54-55` — `K.HAND_TOTAL_HOKM=162` and `K.HAND_TOTAL_SUN=130` already include the +10.
- `C:\CLAUDE\WHEREDNGN\Constants.lua:114-115` — `K.AL_KABOOT_HOKM=250`, `K.AL_KABOOT_SUN=220`.
- `C:\CLAUDE\WHEREDNGN\Rules.lua:25-28` — `R.TeamOf` (silent nil → "B" defect site, F-04 root cause).
- `C:\CLAUDE\WHEREDNGN\Rules.lua:67-73` — `R.TrickPoints` (no last-trick logic — single-application confirmed).
- `C:\CLAUDE\WHEREDNGN\Rules.lua:692-705` — per-trick aggregation loop. Line 697 selects trick-winner team. Line 703 adds +10 (THE only add-site).
- `C:\CLAUDE\WHEREDNGN\Rules.lua:742-745` — sweep detection.
- `C:\CLAUDE\WHEREDNGN\Rules.lua:847-853` — sweep branch overwrites cardA/cardB with kaboot constant; accumulated teamPoints discarded.
- `C:\CLAUDE\WHEREDNGN\Rules.lua:854-871` — fail branch overwrites cardA/cardB with handTotal.
- `C:\CLAUDE\WHEREDNGN\Rules.lua:872-884` — take branch overwrites cardA/cardB with handTotal.
- `C:\CLAUDE\WHEREDNGN\Rules.lua:885-893` — make branch: cardA/cardB = teamPoints (the +10 carries through).
- `C:\CLAUDE\WHEREDNGN\Rules.lua:926` — `rawA = (cardA + meldPoints.A) * mult`. Last-trick gets multiplied here.
- `C:\CLAUDE\WHEREDNGN\Rules.lua:939-943` — Belote +20 added AFTER multiplier (multiplier-immune).
- `C:\CLAUDE\WHEREDNGN\Rules.lua:973` — `lastTrickTeam` exposed in result struct (informational, not consumed by scoring math).
- `C:\CLAUDE\WHEREDNGN\State.lua:1300-1310` — `S.ApplyTrickEnd` rejects partial tricks; insulates `t.winner` against nil.
- `C:\CLAUDE\WHEREDNGN\State.lua:1439` — `S.SWAClaimedTotal` references `K.LAST_TRICK_BONUS` for SWA-claim arithmetic (independent of round scoring; not a double-count site).
- `C:\CLAUDE\WHEREDNGN\tests\test_rules.lua:505-549` — `buildTieTricks` test fixture: explicitly constructs 10/10 tied scenario via "trick 8: B wins, all-zero cards → B gets +10 last-trick bonus" — this pin codifies the trick-WINNER-team attribution.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-Rules-02_scoreRound.md` — F-04 (R.TeamOf nil silent misclassification) parallel finding for the bidder side.

---

## Final verdict

**Last-trick +10 mechanic is CORRECT.** Single-application: yes. Multiplier-aware: yes (×mult applies). Routes to TRICK-WINNER team (not bidder): yes. Survives Al-Kaboot: no — correctly replaced by 250/220 sweep constants. Belote and last-trick orderings don't cross-contaminate: confirmed.

The only concern in scope is the F-04-flavor `R.TeamOf(nil) → "B"` silent attribution defect (Bug B-1), inherited from the same root cause as B-Rules-02 F-04 but applied to the trick-winner side. Defensive only — no known production caller exercises it.

No urgent fix required. If F-04 is fixed in B-Rules-02 (make `R.TeamOf` strict), Bug B-1 falls out for free.
