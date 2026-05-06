# B-Net-06 — Escalation chain wire handlers (deep audit)

**Scope.** Wire & state surface for the Saudi escalation chain (Bel → Triple → Four → Gahwa) plus the v0.10.0 R1/R2 reaudit consequences. Cross-checks `R.CanBel`, `N._SunBelAllowed`, `N._OnDouble/_OnTriple/_OnFour/_OnGahwa`, `N.LocalDouble/LocalTriple/LocalFour/LocalGahwa`, `S.ApplyDouble/ApplyTriple/ApplyFour/ApplyGahwa`, `Bot.PickDouble/PickTriple/PickFour/PickGahwa`, the `_OnOvercallResolve` payload-empty path, and the SVars/Takweesh/SWA/UI defense-in-depth surfaces.

**Mode.** Read-only. No code modified.

**Files inspected.**

- `C:\CLAUDE\WHEREDNGN\Net.lua` — lines 60-200, 480-600, 800-1150, 1521-1612, 1843-2024, 2150-2300, 2900-2990, 3290-3800
- `C:\CLAUDE\WHEREDNGN\Rules.lua` — lines 480-561, 880-953
- `C:\CLAUDE\WHEREDNGN\State.lua` — lines 300-374, 1025-1147
- `C:\CLAUDE\WHEREDNGN\Bot.lua` — lines 3431-3680
- `C:\CLAUDE\WHEREDNGN\UI.lua` — lines 1750-1830, 3130-3160, 3315-3340
- `C:\CLAUDE\WHEREDNGN\Constants.lua` — lines 54-72, 329
- `.swarm_findings\review_v0.10.0\_phase2_xref\reaudit_R1_bel100.md`
- `.swarm_findings\review_v0.10.0\_phase2_xref\reaudit_R2_sun_escalation.md`

---

## Findings summary

| # | Tag | Severity | One-line |
|---|---|---|---|
| F1 | R1 score-split | OK | `R.CanBel` correctly implements caller≤100 ∧ opposite≥101; the three predicates are aligned. |
| F2 | D-RT-05 | LOW | Bidder-trailing case is admissible by `R.CanBel`/`Bot.PickDouble` but **unreachable via wire**: `_OnDouble` and `LocalDouble` hard-gate on the defender seat. Behavioral parity bug only inside Sun bidder-trailing edge. |
| F3 | D-RT-22 (R1 AFK regression) | HIGH | Pre-emption finalize path closes the round when `_SunBelAllowed` returns false, even when the score-split predicate would let the **bidder team itself** Bel — but `_OnDouble`/UI gate on defender seat anyway, so "trailing bidder may Bel" is structurally unreachable. The 30s AFK regression scenario (cumA=50 cumB=130, A bids Sun) leaves zero-action paths and silently completes the deal — Bel button never renders for any seat. |
| F4 | R2 Sun escalation collapse | OK | `S.ApplyDouble` short-circuits Sun→PHASE_PLAY at line 1085-1087 regardless of `open`. Wire pipeline is correct. |
| F5 | D-RT-09a (Takweesh penalty mult) | LOW | `Net.lua:2185-2190` honors `c.tripled / c.foured / c.gahwa` on Sun without filtering by `c.type`. Live-pipeline-unreachable on Sun (per F4) but encodes the invariant violation R2 was supposed to close. |
| F6 | D-RT-09b (SWA-invalid penalty mult) | LOW | `Net.lua:2930-2935` mirror — same blind multiplier ladder on the invalid-SWA Qaid path. |
| F7 | D-RT-09c (SVars upgrader) | LOW | `S.ApplyResyncSnapshot` and `S.RestoreSession` re-hydrate `tripled/foured/gahwa` on Sun contracts without normalization (State.lua:323-330, 440-442). A pre-v0.10 saved-session OR a pre-R2 host snapshot can resurrect a Sun-with-Triple contract on a v0.10.2 client. |
| F8 | D-RT-09d (UI banner) | LOW | UI score banner (UI.lua:3142-3144) and contract banner (UI.lua:3324-3326) print "Triple/Four/Gahwa" labels for any contract carrying those flags, including Sun. Display-only, but contradicts canonical truncation. |
| F9 | _OnTriple/_OnFour/_OnGahwa phase-guard | OK | Each handler hard-gates on `S.s.phase == K.PHASE_*`. Sun never enters those phases, so the handlers no-op. |
| F10 | D-RT-30 Gahwa Scenario 2 | MED | `_OnGahwa` lacks an explicit `contract.type ~= K.BID_SUN` guard (Net.lua:948-960). The match-win branch at `Rules.lua:928` is **type-blind**: `if contract.gahwa then ... gahwaWonGame = true`. Any Sun contract whose `gahwa` flag gets set (via SVars upgrader, malicious peer, or test fixture replay) jumps to match-win on score. |
| F11 | Cross-network escalation race | LOW | Concurrent MSG_DOUBLE/TRIPLE/FOUR can't desync because each handler idempotency-checks (`s.contract.doubled` / `tripled` / `foured` already-set early-return) and phase-guards. The seat-eligibility checks add a third filter. |
| F12 | CRIT-2 (D-RT-15) `_OnOvercallResolve` empty payload | MED | If host sends an empty / malformed MSG_OVERCALL_RESOLVE, the receiver unconditionally sets `S.s.phase = K.PHASE_DOUBLE` (Net.lua:1148-1149) regardless of prior phase. This demotes a fully-decided contract back to the pre-Bel state. |
| F13 | wantOpen propagation | OK | `LocalDouble` forces `open=false` on Sun (Net.lua:1861). `Bot.PickDouble` returns `wantOpen=false` for Sun (Bot.lua:3538). `_OnDouble` derives `wasSun` and routes to HostFinishDeal regardless of open. Triple-loop unreachable on Sun. |

Severity legend: `OK` = correct as-is, `LOW` = defense-in-depth gap (no live exploit), `MED` = recoverable desync surface, `HIGH` = user-visible regression.

---

## F1 — R1 score-split rule in `R.CanBel` (caller≤100 AND opposite≥101)

**Severity: OK (verified correct).**

`Rules.lua:523-561` `R.CanBel`:

```lua
function R.CanBel(team, contract, cumulative)
    if not contract or not team then return false end
    if contract.type ~= K.BID_SUN then
        return true                         -- Hokm: always allowed
    end
    -- ...
    local mine     = (cumulative and cumulative[team]) or 0
    local otherTeam = (team == "A") and "B" or "A"
    local otherCum  = (cumulative and cumulative[otherTeam]) or 0
    if mine     >  K.SUN_BEL_CUMULATIVE_GATE then return false end
    if otherCum <= K.SUN_BEL_CUMULATIVE_GATE then return false end
    return true
end
```

`Constants.lua:329`: `K.SUN_BEL_CUMULATIVE_GATE = 100`.

Truth-table aligns exactly with the R1 verdict (`caller_cum ≤ 100 ∧ other_cum ≥ 101`). Bidder/defender role does not enter — the `contract.bidder` field is no longer consulted, only the `contract.type` discriminator (Hokm vs Sun).

Three-predicate cross-check:

| Predicate | File:line | Uses | Verdict |
|---|---|---|---|
| `R.CanBel` (authority) | Rules.lua:523 | score-split via `team` param | OK |
| `N._SunBelAllowed` (UI gate helper) | Net.lua:68-83 | derives trailing team, calls `R.CanBel(trailing, …)` | OK |
| `Bot.PickDouble` | Bot.lua:3442 | `R.CanBel(R.TeamOf(seat), …)` | OK |
| `Net._OnDouble` | Net.lua:886-887 | `R.CanBel(R.TeamOf(seat), …)` | OK |
| `Net.LocalDouble` | Net.lua:1853-1854 | `R.CanBel(R.TeamOf(localSeat), …)` | OK |
| UI Bel button | UI.lua:1771-1773 | `R.CanBel(R.TeamOf(localSeat), …)` | OK |

All five non-authority sites pass `R.TeamOf(seat)` (or trailing-team, in `_SunBelAllowed`'s case) and converge on the same truth-conditions. The R1 fix landed cleanly.

**Confidence:** HIGH.

---

## F2 — D-RT-05: bidder-trailing case admitted but unreachable (wire-vs-predicate divergence)

**Severity: LOW.**

`R.CanBel` is now role-irrelevant: it returns `true` for the **bidder team** when the bidder team is itself trailing (e.g., A=50, B=130, A bids Sun → A is the trailing side and per Saudi rule may Bel). `Bot.PickDouble` would also return `true` in this configuration (PickDouble calls `R.CanBel(R.TeamOf(seat), …)` and only the score-split is consulted).

**But the wire/UI surface gates on the defender seat:**

`Net.lua:867` (`_OnDouble`):

```lua
local eligibleSeat = (S.s.contract.bidder % 4) + 1
if seat ~= eligibleSeat then return end
```

`Net.lua:1848` (`LocalDouble`):

```lua
if S.s.localSeat ~= (b % 4) + 1 then return end
```

`UI.lua:1758-1759` (Bel button):

```lua
local nextSeat = b and ((b % 4) + 1) or nil
if nextSeat == S.s.localSeat then ... end
```

Consequence: the bidder seat (or the bidder's partner) **never sees a Bel button**, never has a wire path that admits their Bel, and `Bot.PickDouble` is only invoked from `MaybeRunBot`'s `PHASE_DOUBLE` branch with `belSeat = (S.s.contract.bidder % 4) + 1` (Net.lua:3582) — i.e., always the **defender** seat after the bidder.

So the role-irrelevant predicate inside `R.CanBel` describes a legality the UI/wire stack cannot exercise. The bidder-trailing case is **legal under the rule but unreachable in practice**. This is a behavioural-parity gap rather than a bug: nobody can submit an illegal Bel, but the "bidder team may Bel its own trailing Sun" case (R1 reaudit's example: A=50, B=130, A bids Sun, A wants to Bel) is silently dropped.

**Reproduction:**

1. Cumulative `{ A = 50, B = 130 }`.
2. Seat 1 (team A) bids Sun. R2 phase, no overcall window applicable.
3. `_HostStepBid` enters PHASE_DOUBLE branch and gates via `_SunBelAllowed(seat 1)`.
4. `_SunBelAllowed` (Net.lua:77-79) computes `trailingTeam = (cumA <= cumB) and "A" or "B"` → "A" (50 ≤ 130). Calls `R.CanBel("A", sun_bidder=1, cum)` → returns true.
5. So `_SunBelAllowed` returns true and `_HostStepBid` falls through to `MaybeRunBot()`.
6. `MaybeRunBot` enters PHASE_DOUBLE branch. `belSeat = (1 % 4) + 1 = 2` (team B's seat 2).
7. `Bot.PickDouble(2)`. Inside: `R.CanBel(R.TeamOf(2)="B", contract, cum)`. Returns `false` (B has crossed: `mine=130 > 100`).
8. PickDouble returns `(false, false)` → `MSG_SKIP_DBL` broadcast → `HostFinishDeal()`.

Result: nobody Beled. The R1 rule says A should have been allowed to Bel its own contract (since A=50 ≤ 100 and B=130 ≥ 101). But the wire never asks A — only seat 2 is dispatched.

**Why "LOW":** the test fixture in `reaudit_R1_bel100.md` (assertion at lines 313-321) is an `R.CanBel` unit test that does verify the rule symmetrically. The wire pipeline doesn't expose the symmetry. From a **rules-correctness-of-callable-paths** viewpoint, no illegal Bel can occur. From a **rules-completeness viewpoint**, the bidder team's trailing-Bel right is unrealizable.

**Two interpretations of intent:**

- (a) The `R.CanBel` symmetry was a defensive expression: keep the predicate score-split and let the wire decide who is allowed to call it. Wire correctly limits to defender. Bidder-team-trailing-Sun-Bel is a paper edge case that doesn't deserve a UI rung.
- (b) R1 reaudit's verdict ("score-split, role-irrelevant") was intended to admit both teams. The wire layer was supposed to follow but was not updated.

Under interpretation (a) F2 is by design. Under (b) it's a HIGH bug — but I rate it LOW because (1) the source materials are role-agnostic but the videos all describe the **defender** initiating Bel; (2) the "bidder Bel its own contract" case is not exemplified in any canonical Saudi source I've seen referenced; (3) the v0.10.0 R1 patch comment in `R.CanBel` explicitly says "passing bidder = bidderSeat no longer affects R.CanBel's output but documents intent" — i.e., intent of (a).

**Confidence:** HIGH on the wire-divergence finding; MEDIUM on which interpretation is correct.

---

## F3 — D-RT-22: R1-induced 30s AFK regression (cumA=50, cumB=130, A bids Sun)

**Severity: HIGH.**

Walkthrough using the prompt's stated state (cumA=50, cumB=130, A bids Sun):

1. `_HostStepBid` reaches the `action == "contract"` branch.
2. `payload.bidder = 1` (A), `payload.type = K.BID_SUN`.
3. `S.ApplyContract(1, BID_SUN, …)` runs. `s.phase = K.PHASE_DOUBLE` (State.lua:1055). `S.s.belPending = { 2, 4 }` (the "defenders").
4. `_HostStepBid` next checks the Sun-Bel-skip: `if not N._SunBelAllowed(payload.bidder) then S.s.belPending = nil; N.HostFinishDeal(); return end` (Net.lua:1593-1599).
5. `_SunBelAllowed(1)`: trailing team = "A" (50 ≤ 130). Calls `R.CanBel("A", contract, cum)`.
6. **A is at 50**, B is at 130 → `mine=50 ≤ 100` ✓ AND `otherCum=130 > 100` ✓ → `R.CanBel` returns **true**.
7. `_SunBelAllowed` returns true. `_HostStepBid` does NOT skip — it falls through to `N.MaybeRunBot()`.
8. `MaybeRunBot` enters PHASE_DOUBLE branch. `belSeat = (1 % 4) + 1 = 2` (team B).
9. Seat 2 is human (per the regression scenario). Branch: `N.StartBelTimer(belSeat=2, "double")` — armed for `K.TURN_TIMEOUT_SEC = 60`s. (Net.lua:3645)
10. UI on seat 2's client: `S.s.localSeat = 2`. Bel button gate at UI.lua:1771-1773: `R.CanBel(R.TeamOf(2)="B", contract, cum)` → **B at 130**, `mine=130 > 100` → returns `false`.
11. UI renders `"|cff999999Bel forbidden (Sun >=100)|r"` non-actionable label + a "Skip" button (UI.lua:1774-1777).
12. Seat 2 player either clicks Skip (manual) OR the 60s AFK timer fires (`_HostBelTimeout` → `MSG_SKIP_DBL` → `HostFinishDeal`).
13. The deal completes; contract A's-Sun proceeds without Bel.

So **the prompt's stated behavior** ("button never renders") is **not literally true** — the UI does render: it shows the "Bel forbidden" tooltip and a Skip button.

**However**, the regression _is_ real in two senses:

(a) Pre-v0.10 (when `_SunBelAllowed` was role-anchored at `bidderTeam.cum >= 101`), this exact configuration failed at step 6: bidder-team-A is at 50, the role-based predicate computed `bidderCum=50 ≤ 100` → returned `false` → `_SunBelAllowed` returned `false` → `HostFinishDeal()` ran immediately at step 7 with no AFK window. The deal completed in milliseconds.

(b) Post-v0.10 R1 fix: `_SunBelAllowed` now returns `true` (per F2 analysis), so `_HostStepBid` stops short-circuiting. The contract enters PHASE_DOUBLE, the Bel timer arms for the **defender seat** (seat 2, team B), but the defender team's Bel is **forbidden** by the score-split rule (B is at 130). The defender's UI explicitly says "Bel forbidden". So either:
- the human at seat 2 clicks "Skip" promptly → no functional regression, just an extra UI step that didn't exist pre-R1; or
- the human is AFK or inattentive → the 60-second AFK timer must elapse before `HostFinishDeal` runs, **adding up to 60 seconds of dead time** to the deal. That's the user-visible regression.

Net behavioral change: pre-v0.10 the deal advanced to PLAY immediately on Sun-bid in this configuration (because the role-anchored gate said "no team can Bel"); post-R1 the deal pauses for ≤60s waiting for a human who can never click Bel.

**The unreachable-Bel-by-bidder side of F2 directly produces this dead time.** A complete fix would require **either**:
- `_HostStepBid`'s Sun-Bel-skip to also detect "no eligible seat can actually click Bel" (e.g., add a check: if `_SunBelAllowed(bidder)` is true but `R.CanBel(R.TeamOf(belSeat), …)` is false, also skip — but this is exactly the asymmetric-role logic R1 deliberately removed); OR
- the UI/wire to admit bidder-team Bel when the bidder is trailing (per F2 interpretation b), which would route the Bel button to seat 1 (A) in this scenario.

Currently neither path exists. The 30s-AFK case is real.

**Reproduction (direct).**

```
cumulative = { A = 50, B = 130 }
seat 1 (A) bids Sun.
seat 2 (B) is human.
expect: PHASE_DOUBLE entered; UI for seat 2 shows "Bel forbidden" + Skip;
        no Bel button renders for any seat;
        if seat 2 doesn't click Skip, 60s AFK timer must elapse
        before HostFinishDeal runs.
actual: same.
```

The prompt's "30s AFK" magnitude appears to be off-by-half: `K.TURN_TIMEOUT_SEC = 60`, with the local pre-warn at warnAt=50 (Net.lua:3325-3326). The regression magnitude is up to ~60s of dead time, not 30.

**Confidence:** HIGH on the regression existence and mechanism. MEDIUM on the prompt's "button never renders" wording — it does render, just as a non-actionable label.

---

## F4 — v0.10.0 R2 Sun escalation collapse (`S.ApplyDouble` jumps Sun→PHASE_PLAY)

**Severity: OK (verified correct).**

`State.lua:1075-1097`:

```lua
function S.ApplyDouble(seat, open)
    if not s.contract then return end
    s.contract.doubled = true
    s.contract.belOpen = (open ~= false)
    s.belPending = nil
    s.turn = nil
    s.turnKind = nil
    -- Sun rule (Saudi): "في الصن لايوجد الثري والفور والقهوة" — Sun
    -- has only Bel; no Triple/Four/Gahwa. Sun + Bel goes straight to
    -- PLAY regardless of open/closed (no rung to advance to).
    if s.contract.type == K.BID_SUN then
        s.phase = K.PHASE_PLAY
        return
    end
    -- Closed: chain ends; no Triple window.
    if not s.contract.belOpen then
        s.phase = K.PHASE_PLAY
        return
    end
    s.phase = K.PHASE_TRIPLE
    if B.Net and B.Net.StartLocalWarn then B.Net.StartLocalWarn("triple") end
end
```

Sun-Bel always lands in PHASE_PLAY. `_OnTriple/_OnFour/_OnGahwa` cannot fire (their phase guards require PHASE_TRIPLE/FOUR/GAHWA). `LocalTriple/Four/Gahwa` cannot fire (same phase guards). The phase-machine truncation is canonical.

The R2 reaudit's matching defense-in-depth recommendations are **partially landed**:

- ✅ `Bot.PickTriple` returns `false, false` on `contract.type == K.BID_SUN` (Bot.lua:3589).
- ✅ `Bot.PickFour` returns `false, false` on Sun (Bot.lua:3622).
- ✅ `Bot.PickGahwa` returns `false, false` on Sun (Bot.lua:3674).
- ✅ `R.ScoreRound` (`Rules.lua:884-893`) splits on `contract.type == K.BID_SUN`: only doubled contributes to the Sun multiplier, `tripled/foured/gahwa` are silently ignored.
- ❌ `LocalDouble` forces `open=false` on Sun (Net.lua:1861) — present but no defense-in-depth `_OnDouble` block on Sun-foured combinations.

**Confidence:** HIGH on truncation correctness.

---

## F5 — D-RT-09a: Takweesh penalty multiplier (`Net.lua:2185-2190`)

**Severity: LOW (defense-in-depth gap; not live-reachable on Sun via wire).**

`Net.lua:2185-2190` (`HostResolveTakweesh`):

```lua
local mult = K.MULT_BASE
if c.type == K.BID_SUN then mult = mult * K.MULT_SUN end
if     c.gahwa   then mult = mult * K.MULT_FOUR
elseif c.foured  then mult = mult * K.MULT_FOUR
elseif c.tripled then mult = mult * K.MULT_TRIPLE
elseif c.doubled then mult = mult * K.MULT_BEL end
```

Note: `mult * K.MULT_FOUR` is `*4`, but the multiplier semantics here treat Gahwa as ×4 for early-termination penalties (per the comment at Net.lua:2178-2184). So the line `if c.gahwa ... mult = mult * K.MULT_FOUR` means "Gahwa-as-Triple-equivalent for Qaid penalty" — a deliberate choice for the **bare 26 Sun / 16 Hokm penalty when the round didn't play out**.

The defense-in-depth gap: **the multiplier ladder is `c.type`-blind for Sun**. If a Sun contract somehow carried `tripled=true` (e.g., via the SVars upgrader, F7), the Takweesh penalty for a Sun-with-Triple round would compute `mult = K.MULT_BASE * K.MULT_SUN * K.MULT_TRIPLE = 1 * 2 * 3 = 6`, which contradicts the R2 invariant ("Sun can only carry Bel"). The R2 reaudit's recommended `R.ScoreRound` fix (lines 884-893 of Rules.lua) was applied at the regular round-end path but **NOT at this Takweesh penalty path**.

**Reproduction (synthetic).**

```lua
S.s.contract = {
  type = K.BID_SUN,
  bidder = 1,
  doubled = true, tripled = true,  -- malformed
  gahwa = false, foured = false,
}
-- Takweesh fires; HostResolveTakweesh runs.
-- handTotal = 130 (HAND_TOTAL_SUN)
-- mult = 1 * 2 (Sun) * 3 (tripled) = 6
-- expected per R2 invariant: mult = 2 (Sun) * 2 (Bel) = 4
```

This is unreachable through the wire today (R.ScoreRound is correct, S.ApplyDouble truncates Sun, and there's no path that sets `c.tripled=true` on a Sun contract). It becomes reachable via F7's SVars upgrader gap.

**Confidence:** HIGH on the gap; reachability depends on F7.

---

## F6 — D-RT-09b: SWA-invalid Qaid penalty multiplier (`Net.lua:2930-2935`)

**Severity: LOW (mirrors F5).**

`Net.lua:2926-2935` (in the `if not valid` branch of `_HostResolveSWA`):

```lua
local handTotal = (c.type == K.BID_SUN) and K.HAND_TOTAL_SUN or K.HAND_TOTAL_HOKM
-- v0.2.0+ multiplier ladder. Gahwa is treated as ×4 here (same
-- as Four) because the match-win semantic only applies to a
-- fully-played-out round; an invalid SWA is a per-round penalty.
local mult = K.MULT_BASE
if c.type == K.BID_SUN then mult = mult * K.MULT_SUN end
if     c.gahwa   then mult = mult * K.MULT_FOUR
elseif c.foured  then mult = mult * K.MULT_FOUR
elseif c.tripled then mult = mult * K.MULT_TRIPLE
elseif c.doubled then mult = mult * K.MULT_BEL end
```

Identical structure to F5. Same defense-in-depth gap. Same lack of `c.type == K.BID_SUN` filter on the tripled/foured/gahwa branches.

**Confidence:** HIGH on the gap structure.

---

## F7 — D-RT-09c: SVars upgrader leaks Sun escalation flags (`State.lua:323-330`, `:440-442`)

**Severity: LOW-MED (path of least resistance for resurrecting a malformed contract).**

Two surfaces:

(1) `S.RestoreSession` (State.lua:310-330):

```lua
for k in pairs(s) do s[k] = nil end
for k, v in pairs(sess.state) do s[k] = v end
-- v0.2.0 upgrader: ...
if s.contract then
    s.contract.redoubled = nil
    s.contract.belOpen    = s.contract.belOpen    or false
    s.contract.tripleOpen = s.contract.tripleOpen or false
    s.contract.fourOpen   = s.contract.fourOpen   or false
end
```

The upgrader normalizes the obsolete `redoubled` field and back-fills missing `*Open` flags, but **does not touch `tripled`, `foured`, or `gahwa`** on Sun contracts. A pre-R2 saved session that recorded a malformed Sun contract with `tripled=true` (possible if a v0.10.0 R2 patch hadn't yet landed when the host saved the session) restores into a v0.10.2 client untouched.

(2) `S.ApplyResyncSnapshot` (State.lua:436-442 — relevant decode):

```lua
tripled    = f[11] == "1",
foured     = f[12] == "1",
gahwa      = f[13] == "1",
```

Wire layout fields 11/12/13 carry `tripled/foured/gahwa` flags. There is **no Sun-type filter here**: a host running a buggy or malicious build that broadcasts `c;…|sun|…|0|1|0|0|…` (Sun+Triple) would resurrect the flags on the receiving client.

**Reproduction.**

1. Host on legacy build saves session with `s.contract = { type = "S", tripled = true, … }` (no enforcement of R2 truncation).
2. Client loads session. `RestoreSession` does not strip `tripled`. Client now has Sun-with-Triple in memory.
3. Client takes any code path that consults `c.tripled` without `c.type` filtering — F5 (Takweesh), F6 (invalid SWA), F8 (UI banner), F10 (Gahwa match-win) — and computes wrong values.

**Confidence:** HIGH on the gap; reachability requires either savegame skew or hostile peer.

---

## F8 — D-RT-09d: UI banner shows escalation labels for Sun (`UI.lua:3142-3144`, `:3324-3326`)

**Severity: LOW (display-only).**

`UI.lua:3138-3144` (score-end banner):

```lua
local typeStr = (S.s.contract and S.s.contract.type == K.BID_SUN) and "Sun" or "Hokm"
local mods = { typeStr }
if S.s.contract and S.s.contract.doubled then mods[#mods + 1] = "Bel" end
if S.s.contract and S.s.contract.tripled then mods[#mods + 1] = "Triple" end
if S.s.contract and S.s.contract.foured then mods[#mods + 1] = "Four" end
if S.s.contract and S.s.contract.gahwa then mods[#mods + 1] = "Gahwa (match-win)" end
```

`UI.lua:3322-3326` (contract banner):

```lua
local mods = {}
if c.doubled    then mods[#mods + 1] = "Bel (x2)"        end
if c.tripled    then mods[#mods + 1] = "Triple (x3)"     end
if c.foured     then mods[#mods + 1] = "Four (x4)"       end
if c.gahwa      then mods[#mods + 1] = "Gahwa (match)"   end
```

Neither block filters on `c.type`. A malformed Sun contract carrying `tripled=true` (per F7) would display "Sun  ·  Bel  ·  Triple" in the banner. The actual scoring multiplier (correctly ×4 from `R.ScoreRound`) would not match the displayed "Triple (x3)" suffix, producing user-visible inconsistency.

**Confidence:** HIGH; trivially reproducible if F7 is exploited.

---

## F9 — `_OnTriple/_OnFour/_OnGahwa` phase-guard sequence

**Severity: OK.**

Each handler's gate sequence (Net.lua:915-960):

`_OnTriple` — lines 915-929:
1. `fromSelf` skip.
2. seat presence check.
3. idempotence: `S.s.contract.tripled` already set → return.
4. phase-guard: `S.s.phase ~= K.PHASE_TRIPLE` → return.
5. seat-eligibility: `seat ~= S.s.contract.bidder` → return.
6. authorizeSeat: sender must own the seat (or host for bot).
7. apply + dispatch.

`_OnFour` — lines 931-946: same shape, with `eligibleSeat = (bidder % 4) + 1` for the defender check.

`_OnGahwa` — lines 948-960: same shape, with `seat ~= S.s.contract.bidder` for the bidder check.

All five gates fire **before** any state mutation. Sun never enters PHASE_TRIPLE/FOUR/GAHWA (per F4 truncation) so these handlers no-op on Sun contracts. The phase-guard is the canonical defense.

**Confidence:** HIGH.

---

## F10 — D-RT-30: Gahwa Scenario 2, `_OnGahwa` lacks Sun gate, `Rules.lua:928` type-blind

**Severity: MED.**

`Net.lua:948-960` `_OnGahwa`:

```lua
function N._OnGahwa(sender, seat)
    if fromSelf(sender) then return end
    if not seat then return end
    if not S.s.contract or S.s.contract.gahwa then return end
    if S.s.phase ~= K.PHASE_GAHWA then return end
    -- Gahwa is the BIDDER's terminal (match-win) escalation.
    if seat ~= S.s.contract.bidder then return end
    if not authorizeSeat(seat, sender) then return end
    S.ApplyGahwa(seat)
    if B.Bot and B.Bot.OnEscalation then B.Bot.OnEscalation(seat, "gahwa") end
    -- Terminal: no further window. Move into PLAY.
    if S.s.isHost then N.HostFinishDeal() end
end
```

No `contract.type ~= K.BID_SUN` filter. The phase-guard at `S.s.phase ~= K.PHASE_GAHWA` is sufficient for the live wire pipeline (Sun never reaches PHASE_GAHWA per F4). But `S.ApplyGahwa` (State.lua:1140-1147) sets `s.contract.gahwa = true` unconditionally:

```lua
function S.ApplyGahwa(seat)
    if not s.contract then return end
    s.contract.gahwa = true
    s.turn = nil
    s.turnKind = nil
    if B.Sound and B.Sound.Cue then B.Sound.Cue(K.SND_VOICE_GAHWA) end
end
```

If a Sun contract somehow carried `gahwa=true` (via F7 SVars upgrader, or via a future bug that sets it directly), the match-win branch at `Rules.lua:928` fires:

```lua
if contract.gahwa then
    if bidderMade then
        gahwaWinner = bidderTeam
    else
        gahwaWinner = oppTeam
    end
    gahwaWonGame = true
end
```

`gahwaWinner` is computed purely from `bidderTeam` and `bidderMade`. There's **no `contract.type`** check before the assignment. The host's `_HostStepAfterTrick` (Net.lua:1669-1678) then forces the cumulative to `target` for the winner and **declares the entire match decided** based on a malformed contract.

**Severity rationale (MED rather than LOW):** Unlike F5/F6/F8 which produce wrong scoring or wrong display, F10 produces an **end-of-match-by-misconfiguration**. A single malformed contract → entire game ends. Recovery is a fresh game.

**Reproduction (synthetic).**

```lua
S.s.contract = {
  type    = K.BID_SUN,
  bidder  = 1,
  doubled = true,
  gahwa   = true,  -- malformed, R2 violation
}
S.s.cumulative = { A = 100, B = 100 }
-- Round plays out. R.ScoreRound runs.
-- contract.gahwa is true → gahwaWonGame = true, gahwaWinner = bidderTeam.
-- _HostStepAfterTrick forces cumulative.A = target (152).
-- Match ends. Game-over banner fires.
```

Defense-in-depth fix would be either an explicit `type ~= K.BID_SUN` guard in `_OnGahwa` (cheap one-liner, mirrors F5/F6 recommended fix) **OR** at the match-win branch in `Rules.lua:928`:

```lua
if contract.gahwa and contract.type ~= K.BID_SUN then
    -- existing logic
end
```

Either suffices. The Rules.lua site is the more authoritative gate because it covers all callers of R.ScoreRound (host, replay, test fixtures); the Net.lua site only covers the wire path.

**Confidence:** HIGH on the gap; reachability low under normal wire flow.

---

## F11 — Cross-network escalation race (concurrent MSG_DOUBLE/TRIPLE/FOUR)

**Severity: LOW (no live race observed).**

Three layers protect against concurrent escalation broadcasts:

(1) **Idempotence at `_On*` handlers.** Each handler early-returns if the corresponding flag is already set:
- `_OnDouble`: `if not S.s.contract or S.s.contract.doubled then return end`
- `_OnTriple`: `if not S.s.contract or S.s.contract.tripled then return end`
- `_OnFour`: `if not S.s.contract or S.s.contract.foured then return end`
- `_OnGahwa`: `if not S.s.contract or S.s.contract.gahwa then return end`

(2) **Phase-guard.** Each handler requires the matching phase. Sequential phases (DOUBLE → TRIPLE → FOUR → GAHWA) mean a stale rung message arriving after the chain advanced is silently dropped.

(3) **Seat eligibility.** Each rung gates on a specific seat (defender for Bel/Four, bidder for Triple/Gahwa). A second seat attempting the same rung gets dropped at the seat-check.

**Possible race scenarios analyzed:**

- *Two clients call Bel simultaneously*: only the actual `(bidder % 4) + 1` seat passes the seat check. Other client's MSG_DOUBLE drops at `seat ~= eligibleSeat`. No race.
- *Defender Bel arrives after bidder Triple*: defender's MSG_DOUBLE arrives, but by then `S.s.phase = PHASE_TRIPLE` (or PLAY if open=false closed it), so `_OnDouble` drops at the phase-guard. The Triple stands. Idempotence prevents duplicate state mutation.
- *Out-of-order delivery*: WoW's addon channel is FIFO per-sender. Cross-sender ordering isn't guaranteed but each message is independently authorized, so the reordering can only drop a stale message, not corrupt state.

**Edge case found, not exploitable:** If a malicious peer broadcasts MSG_GAHWA before the bidder broadcasts it, `_OnGahwa` will reject the seat-mismatch (seat ≠ bidder). Even if the peer spoofs the bidder seat, `authorizeSeat` rejects (sender is the peer, not the bidder's character name). No exploit.

**Confidence:** HIGH on no live race.

---

## F12 — CRIT-2 (D-RT-15): `_OnOvercallResolve` empty payload demotes phase to PHASE_DOUBLE

**Severity: MED.**

`Net.lua:1123-1151`:

```lua
function N._OnOvercallResolve(sender, takenStr, by, otype)
    if fromSelf(sender) then return end
    if not fromHost(sender) then return end
    if S.s.isHost then return end
    -- ...
    -- The wire payload (takenStr/by/otype) is informational — kept in
    -- the function signature for forward-compat / debug logging — but
    -- not consulted for state mutation. The host is server-of-truth
    -- via MSG_CONTRACT.
    S.s.overcall = nil
    S.s.phase = K.PHASE_DOUBLE
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end
```

The handler unconditionally sets `S.s.phase = K.PHASE_DOUBLE` when receiving any MSG_OVERCALL_RESOLVE from the host, regardless of:
- whether `S.s.overcall` was actually populated;
- whether the phase was actually `PHASE_OVERCALL`;
- whether the host is just sending a resync replay vs a fresh resolve;
- the payload contents (which are explicitly ignored per the comment).

**Reproduction scenarios:**

(1) **Resync replay race.** A late-joiner during PHASE_OVERCALL receives `_OnResyncRes` first (which writes `S.s.overcall = {...}` and `phase = K.PHASE_OVERCALL` — though by inspection the snapshot doesn't populate s.overcall, and Net.lua:426-435 explicitly whispers MSG_OVERCALL_OPEN to bring the rejoiner into the window). If the host's main-channel MSG_OVERCALL_RESOLVE arrives **after** the rejoiner's snapshot but the rejoiner had already advanced to PHASE_PLAY via separate broadcasts (e.g., MSG_CONTRACT + MSG_DEAL play), then `_OnOvercallResolve` would demote phase from PLAY back to DOUBLE. **Consequence: the local UI would show the Bel button again on a contract that's already in PLAY**.

(2) **Empty/malformed payload.** A buggy host that sends `MSG_OVERCALL_RESOLVE;;0;` (no fields) hits `_OnOvercallResolve` with `takenStr=nil, by=nil, otype=nil`. The `fromHost` and `not S.s.isHost` gates pass. The handler still sets `phase = PHASE_DOUBLE`. The same demotion happens.

(3) **Scenario where contract was upgraded.** Host's overcall taken=true flow: host sends MSG_OVERCALL_RESOLVE then MSG_CONTRACT then MSG_DOUBLE-or-skip. Network reorders to: MSG_CONTRACT, MSG_DOUBLE-or-skip, then late MSG_OVERCALL_RESOLVE arrives. By then the receiver has applied the new contract and is in PHASE_PLAY (or PHASE_DOUBLE). The late MSG_OVERCALL_RESOLVE forces phase back to PHASE_DOUBLE — wiping any progress.

**Recovery:** the host's authoritative MSG_CONTRACT and subsequent MSG_DOUBLE/SKIP_DBL frames will eventually re-advance the phase. But during the demoted window, the receiver's UI is in the wrong state and any local action (e.g., a Bel click) might fire on stale contract data.

**The comment explicitly acknowledges this design ("trust the wire ... if the contract changed, the host's follow-up MSG_CONTRACT canonically sets the new contract")** but the implementation is overly aggressive: it should at minimum check that `S.s.phase == K.PHASE_OVERCALL` before demoting. A defensive guard:

```lua
if S.s.phase ~= K.PHASE_OVERCALL then return end
S.s.overcall = nil
S.s.phase = K.PHASE_DOUBLE
```

would close the demotion-loop without breaking the canonical taken=true / taken=false paths.

**Confidence:** HIGH on the unconditional demotion; MEDIUM on whether reordering actually produces the regression in production WoW (party-channel reordering across senders is rare since one sender = host, but theoretical).

---

## F13 — wantOpen propagation (PickDouble's `wantOpen=false` for Sun, etc.)

**Severity: OK.**

Three propagation surfaces:

(1) `Bot.PickDouble` (Bot.lua:3537-3542):

```lua
-- Sun: open is moot (no Triple rung).
if contract.type == K.BID_SUN then return true, false end
-- Open if we have a comfortable buffer (would survive a Triple
-- counter); else close to lock in the ×2.
local wantOpen = strength >= jth + 20
return true, wantOpen
```

Sun → `(yes, false)`. The bot dispatcher in MaybeRunBot (Net.lua:3597-3611) reads this:

```lua
local bel, wantOpen = B.Bot.PickDouble(belSeat)
if bel then
    local isSun = S.s.contract and S.s.contract.type == K.BID_SUN
    local effOpen = (not isSun) and wantOpen
    S.ApplyDouble(belSeat, effOpen)
    applied = true
    N.SendDouble(belSeat, effOpen)
    if isSun or not effOpen then
        N.HostFinishDeal()
    else
        N.MaybeRunBot()
    end
```

`effOpen` is forced `false` on Sun regardless of PickDouble's return. Belt-and-suspenders.

(2) `LocalDouble` (Net.lua:1858-1862):

```lua
if open == nil then open = true end
-- In Sun, open/closed is moot — there's no Triple rung. Force
-- closed so the chain doesn't pretend to advance.
if S.s.contract.type == K.BID_SUN then open = false end
S.ApplyDouble(S.s.localSeat, open)
N.SendDouble(S.s.localSeat, open)
if S.s.isHost then
    if S.s.contract.type == K.BID_SUN or not open then
        N.HostFinishDeal()
    else
        N.MaybeRunBot()
    end
end
```

Sun → forces `open=false`. The HostFinishDeal branch fires unconditionally on Sun.

(3) `_OnDouble` (Net.lua:897-912):

```lua
local open = (openField == nil) or (openField ~= "0")
local wasSun = S.s.contract.type == K.BID_SUN
S.ApplyDouble(seat, open)
-- ...
if S.s.isHost then
    if wasSun or not open then
        N.HostFinishDeal()
    else
        N.MaybeRunBot()
    end
end
```

`wasSun` captures pre-apply Sun status. If wasSun, regardless of openField on the wire, HostFinishDeal fires. Belt-and-suspenders.

All three sites converge on "Sun-Bel ⟹ skip Triple rung". Wire bug surface is minimal.

**One micro-observation:** in `_OnDouble`, the local check is `wasSun = S.s.contract.type == K.BID_SUN` *before* `S.ApplyDouble`. In `LocalDouble`, the check is `S.s.contract.type == K.BID_SUN` *both before and after* the apply. `S.ApplyDouble` doesn't mutate `contract.type`, so this is a no-op cosmetic difference, not a bug.

**Confidence:** HIGH.

---

## Cross-cutting observations

**1. The `R.CanBel` predicate is canonical and the three call-sites converge.** F1 confirms R1 landed. F2/F3 reveal that the canonical predicate is **wider than the wire pipeline can exercise** — which is fine for safety (no illegal Bels) but produces an AFK-window regression (F3) when the predicate is more permissive than the seat-eligibility rules.

**2. R2's defense-in-depth recommendations are partially landed.** Bot pickers ✓, R.ScoreRound ✓. But the **Takweesh** (F5), **invalid-SWA** (F6), **UI banner** (F8), **SVars upgrader** (F7), and **Gahwa match-win** (F10) sites still honor escalation flags on Sun contracts. These four-plus sites are the back doors the R2 audit flagged but the patches did not cover.

**3. Phase-guard is the canonical truncation gate for the wire pipeline.** All five `_On*` handlers and `LocalDouble/Triple/Four/Gahwa` early-return on phase mismatch. The phase machine is the load-bearing component, not the bot pickers or the R.CanBel predicate.

**4. `_OnOvercallResolve` is the most concerning surface in this audit.** F12 is the only finding where a host-broadcast frame can demote phase under any prior phase, with no idempotence/phase-guard protection. The existing comment defends "trust the wire", but the cure (`if S.s.phase ~= K.PHASE_OVERCALL then return end`) is one line and would close the demotion loop without breaking the design.

**5. The R1 score-split rule, F2, and F3 form a coherent triad.** The rule is symmetric in the source materials (per the reaudit), but the wire pipeline is asymmetric (defender-only Bel button). The mismatch is harmless on legality (no illegal moves possible) but produces user-visible dead time when the bidder is trailing in Sun. The cleanest fix would be either (a) restrict `R.CanBel` to defender-only on Sun (matching the wire), or (b) add a Bel button for the bidder seat when the bidder is the trailing side.

---

## Recommended (non-binding) action plan

1. **HIGH-priority**: F3 (D-RT-22) AFK regression. Either tighten `_HostStepBid`'s Sun-Bel-skip to early-exit when `_SunBelAllowed=true` but `R.CanBel(R.TeamOf(belSeat),...)=false`, OR open the Bel UI to the bidder seat when bidder team is trailing.

2. **MED-priority**: F12 (`_OnOvercallResolve`) — add a phase-guard before the demotion. F10 (`_OnGahwa`) — add a `contract.type ~= K.BID_SUN` defense-in-depth guard, OR move the guard into `Rules.lua:928` for full coverage.

3. **LOW-priority**: F5/F6/F7/F8. R2 defense-in-depth gaps. None live-reachable today, but they encode the invariant violation R2 was designed to close. The same one-liner pattern (filter `c.tripled/foured/gahwa` on `c.type ~= K.BID_SUN`) closes all four.

4. **No action needed**: F1, F4, F9, F11, F13.
