# v3.2.5 → v3.2.6 Batch B Design — Deferred HIGH-pickplay candidates

**Status:** design pass only. No runtime edits, no test edits, no
branch, no tag, no release. Uncommitted on `main`.

**Provenance:**

- Builds on `.swarm_findings/v3_2_4_high_pickplay_coverage_design.md`
  (the v3.2.5 BH-section parent design).
- v3.2.5 (commits `c5c8fba` design + `6a4cfd2` impl + `21d7340`
  polish) shipped Batch A: T-4 sender + T-1.E4 positive + negative
  + source pins → harness baseline `1264 / 0`.
- This doc inventories the **deferred** Batch B candidates from the
  v3.2.4 design:
  - **T-1.E2**: Hokm Faranka Exception #2 positive path (`pickFollow`,
    2-trumps + bidder-team + K-cover live).
  - **T-10**: Tahreeb-return T-supply count >= 3 "want" branch
    (`pickLead`).
  - **T-2**: sweep-pursuit-early Kaboot lead (`pickLead`).
- T-4 (Sun pos-4 5-factor Faranka) remains DEFER-indefinite per
  v3.2.4 §3 — not re-evaluated here.

**Hard constraints (this batch):**

- Test-only. **No edits to `Bot.lua`**, runtime files, `.toc`,
  `.pkgmeta`, `.github/`, packaging, or CHANGELOG.
- Preserve `sprint-a-experimental` and `v0.5.1-experimental`.
- Leave `.swarm_findings/v3_2_0_botlua_comment_audit.md` untouched
  and untracked.
- This document stays **uncommitted** until Codex review approves
  scope and ID assignment.

---

## 1. Source Inventory

All line numbers verified against current `main` (head `21d7340`).

### 1.1 T-1.E2 — Hokm Faranka Exception #2 (positive, `pickFollow`)

**Branch:** Faranka exceptions block inside `pickFollow` / Hokm
must-follow handling.

**Trigger condition (Bot.lua:3971-3981):**

```lua
local myTrumpCount = 0
for _, c in ipairs(hand) do
    if C.IsTrump(c, contract) then
        myTrumpCount = myTrumpCount + 1
    end
end
local onBidderTeam = (contract.bidder
                      and R.TeamOf(contract.bidder) == R.TeamOf(seat))
if myTrumpCount == 2 and onBidderTeam then
    farankaTriggered = true
end
```

**F-16 K-cover veto interaction (Bot.lua:4094-4102):**

```lua
if farankaTriggered and not oppsVoidPath and not exception3Path then
    local hasKtrump = false
    for _, c in ipairs(hand) do
        if C.IsTrump(c, contract) and C.Rank(c) == "K" then
            hasKtrump = true; break
        end
    end
    if not hasKtrump then farankaTriggered = false end
end
```

For Exception #2:
- `oppsVoidPath = false`, `exception3Path = false` (by construction).
- Therefore **K of trump MUST be in hand** or Faranka is vetoed.

**Existing markers near the branch (verified on current `main`):**

- `v0.10.0 X3 anti-rule F-16` at L4063 (inside the F-16 K-cover
  veto block).
- `v0.10.3 audit (A-Src-29 + D-RT-03 S-1, HIGH)` at L4071 (the
  E4 carve-out comment).
- `v3.2.1 F4` at L4082 (the E3 carve-out anchor).

The bidder-team gate at L3977-3981 has no unique substring marker
of its own beyond the trivial code text; BI.4 source pins target
the F-16 block markers above, which directly surround the
Exception #2 / F-16 interaction this slice protects.

**Existing tests touching this region (closest siblings):**

- **BH.2/BH.3** (v3.2.5): Exception #4 positive/negative with
  `oppsVoidPath` discriminator. Same family, different exception
  path.
- **BH.4** (v3.2.5): source-pin block on `v0.11.18-final U-2`,
  `oppsVoidPath`, `v0.10.3 F-30b`.
- No BH-class test currently exercises `myTrumpCount == 2` +
  `onBidderTeam` + F-16 K-cover live (the Exception #2 happy
  path).

---

### 1.2 T-10 — Tahreeb-return T-supply count >= 3 "want" (`pickLead`)

**Branch:** receiver-side response after partner emitted a
confirmed `want` (ascending small→big) Tahreeb signal.

**Setup gate (Bot.lua:1291-1323):**

```lua
if Bot.IsM3lm() and Bot._partnerStyle then
    local p = R.Partner(seat)
    if Bot.IsBotSeat(p) then
        local pStyle = Bot._partnerStyle[p]
        local signals = pStyle and pStyle.tahreebSent
        if signals then
            local best, bestScore, bestFlavor = nil, 0, nil
            for _, su in ipairs(shuffledSuits()) do
                if su ~= contract.trump then
                    local cls = tahreebClassify(signals[su])
                    local score = (cls == "bargiya" and 3)
                               or (cls == "want" and 2)
                               or (cls == "bargiya_hint" and 1)
                               or (cls == "want_hint" and 1)
                               or 0
                    if score > bestScore then
                        best, bestScore, bestFlavor = su, score, cls
                    end
                    ...
                end
            end
            ...
```

**T-supply branch (Bot.lua:1761-1788):**

```lua
if hasT and count == 1 then
    -- Bare-T: lead immediately.
    return tCard
elseif hasT and count == 2 then
    -- Doubled-T: branch on partner-is-Sun-bidder.
    local partner = R.Partner(seat)
    local partnerIsSunBidder = (contract and contract.bidder == partner
                                and contract.type == K.BID_SUN)
    if partnerIsSunBidder then
        return lowestByRank(nonTpref, contract)
    else
        return tCard
    end
elseif hasT and tahreebPrefFlavor == "want" then
    -- v1.1.0 (audit partner-coord H1): Tahreeb-receiver
    -- T-supply for count >= 3. Pre-fix this branch fell
    -- through to `lowestByRank` whenever count >= 3, even
    -- when partner emitted a CONFIRMED `want` (small→big)
    -- Tahreeb signal — which video #10 calls "100%
    -- reliable" («نسبه نجاحه كبيره اللي هي 100%»). The
    -- small-to-big sender is signalling no-T; receiver
    -- with T MUST lead it back to partner regardless of
    -- the count of cover. Restricted to "want" flavor
    -- (the canonical small→big confirmed signal); other
    -- Tahreeb flavors keep the legacy low-lead behavior.
    return tCard
```

**Existing markers near the branch:**

- `v1.1.0 (audit partner-coord H1)` at L1777 — explicit anchor.
- `v0.9.0 Bargiya 2-flavor weights` at L1304 (scoring table).
- `tahreebPrefFlavor` is the wire identifier; appears multiple
  times above and below the branch.

**Existing tests touching this region:**

- **F.3** (test_state_bot.lua:1228) uses
  `Bot._partnerStyle[3].tahreebSent.H = { "7", "9" }` — proves
  the want-classification path lights up.
- **BH.1** (v3.2.5) exercises the **sender** side ("want, no
  Ace/no T") around Bot.lua:3676-3701; it does NOT exercise the
  **receiver** side at L1776-1788.
- No BH-class test currently exercises the count-≥3 receiver
  T-supply branch with "want" flavor.

---

### 1.3 T-2 — sweep-pursuit-early Kaboot lead (`pickLead`)

**Branch:** early sweep-pursuit before trick 8.

**Setup (Bot.lua:1073-1088):**

```lua
local sweepPursuitEarly = false
if trickNum >= 3 and trickNum <= 7 then
    local mySwept = 0
    for _, t in ipairs(S.s.tricks or {}) do
        if R.TeamOf(t.winner) == myTeam then
            mySwept = mySwept + 1
        end
    end
    sweepPursuitEarly = (mySwept == trickNum - 1)
```

**Feasibility gate (Bot.lua:1104-1136):**

```lua
    if sweepPursuitEarly and Bot.IsM3lm() and S.HighestUnplayedRank
       and contract.trump then
        local remainingNeeded = 8 - trickNum + 1
        local feasibleWinners = 0
        for _, c in ipairs(legal) do
            local r = C.Rank(c)
            local su = C.Suit(c)
            if su == contract.trump then
                if r == "J" or r == "9" or r == "A" then
                    feasibleWinners = feasibleWinners + 1
                elseif S.HighestUnplayedRank(contract.trump) == r then
                    feasibleWinners = feasibleWinners + 1
                end
            else
                if S.HighestUnplayedRank(su) == r then
                    feasibleWinners = feasibleWinners + 1
                end
            end
        end
        if feasibleWinners < remainingNeeded then
            sweepPursuitEarly = false
        end
    end
end
```

**Fire (Bot.lua:1138-1190):** sweep-pursuit fires by leading
`highestByFaceValue(safeBosses, contract)` when bosses exist, else
`highestByRank(legal, contract)` (when `sweepPursuit == true`,
which is only on trick 8 after full sweep), else
`highestByFaceValue(legal, contract)`.

**Existing markers near the branch:**

- `v1.0.3 (Cluster 4 defender sweep-pursuit)` at L1074.
- `v1.0.3 (U-7) Kaboot-feasibility hand-shape gate` at L1089.
- `Kaboot pursuit feasibility check` at L1095 (also as Saudi-doc
  text cross-reference).

**Existing tests touching this region:**

- No BH-class or BF/BE-class test currently exercises
  `sweepPursuitEarly == true` after the v1.0.3 U-7 feasibility
  gate.
- Some H-series standalone tests exercise the trick-8 sweep
  endpoint but not the early-pursuit branch.

---

## 2. Behavioural Surface

### 2.1 T-1.E2 surface

| Dimension | Required state |
|---|---|
| Contract | Hokm, any trump suit `T` |
| Seat | On bidder team (bidder = our seat OR `R.Partner(our seat)`) |
| Tier | M3lm+ (the Faranka exceptions block is M3lm-gated upstream) |
| Trick context | **Side-suit-led** must-follow trick (e.g. led suit `H` ≠ trump `D`): opp leads a non-trump card; we have led-suit cards in hand ⇒ legal set = our led-suit cards |
| Hand shape (positive) | Hand contains **2 trumps** (counted by `myTrumpCount` over hand, not legal) AND ≥2 led-suit cards split into **one winner** + **one non-winner**; K of trump is in hand for F-16 K-cover |
| Hand shape (negative) | Same hand shape but **no K of trump** ⇒ F-16 vetoes |
| Memory | `playedCardsThisRound` includes the cards from this trick (`8H`, `QH`, `KH`); `JD` explicitly NOT played ⇒ `S.HighestUnplayedRank("D") == "J"` ⇒ E3 inactive. `Bot._memory[opp].void.D` unset ⇒ E4 inactive (`oppsVoidPath = false`) |
| Upstream shadows | Trick 1 mardoofa probe (Sun-only + lead-side), F5-3 pos-3 Sun Takbeer (Sun-only), AKA-receiver relief (requires AKA on led suit — not set), pickFollow pos-4 single-legal short-circuit (gated by `#legal == 1`, avoided by 2+ led-suit cards in hand) |
| Downstream fallback when not firing | Non-Faranka pos-4 natural play → highest-rank winner among `winners` (the legal led-suit winner, e.g. `AH`) |

**Wire discriminator (positive vs negative):**

- **E2 fires + F-16 satisfied (K in hand):** Faranka block prefers
  non-trump non-winners (`nonTrumpLosers`) over trump non-winners
  to keep trump in reserve, then returns `lowestByRank` of that
  pool. With one led-suit winner and one led-suit non-winner in
  legal, the **led-suit non-winner** is what comes out (e.g. `7H`).
- **E2 trigger fires + F-16 vetoes (no K in hand):** Faranka is
  suppressed; natural pos-4 play returns the **led-suit winner**
  (e.g. `AH`) to take the trick.

**Why side-suit-led, not trump-led:** the Saudi/Belote must-overcut
rule at `Rules.lua:175-196` makes a trump-led non-winner trump
illegal whenever the hand contains a higher trump. So a trump-led
fixture with `{winner-trump, non-winner-trump}` in hand collapses
`legal` to just the winner-trump, short-circuiting Bot.PickPlay
at `Bot.lua:5714` (`if #legal == 1 then return legal[1] end`)
before pickFollow's Faranka block is ever entered. The
side-suit-led fixture sidesteps this by putting the winner /
non-winner split inside the led-suit legal set (where must-overcut
doesn't apply), while the trump count needed by E2 lives in the
**hand** (counted by the `myTrumpCount` loop iterating `hand`, not
`legal`, at `Bot.lua:3971-3975`).

**Cross-check vs BH.2:** BH.2's hand `{AH, 7H, JD, 8C}` has
`myTrumpCount == 1` (one `JD`) ⇒ E2 doesn't trigger; E4 fires
instead via both-opps-void seeding. BI.1's hand `{AH, 7H, KD, 9D}`
swaps the trump shape to `myTrumpCount == 2` (KD+9D) ⇒ E2
triggers, and we leave opp memory unset so E4 stays false. Both
fixtures return `7H` on the wire, but for different exception
reasons — the test isolation comes from the memory seeding
difference, not the wire card.

### 2.2 T-10 surface

| Dimension | Required state |
|---|---|
| Contract | Hokm or Sun; trump suit `T` |
| Seat | Any; bot must be M3lm+ |
| Tier | M3lm+ (gate at L1291) |
| Partner | `Bot.IsBotSeat(p)` ⇒ partner must be a bot seat (current implementation gates on this) |
| Memory | `Bot._partnerStyle[p].tahreebSent[S] = { "7", "9", ... }` ascending; classifies as `want`; `S ≠ contract.trump` |
| Hand shape | Contains T of suit `S` and `count(S) >= 3` (the post-doubled-T branch) |
| Trick context | We are leading; trick 1 mardoofa probe must NOT shadow (so either non-bidder team, or no A+T mardoofa) |
| Upstream shadows | (a) trick-1 mardoofa probe (Sun bidder-team opener), (b) bare-T branch (`count == 1`), (c) doubled-T branch (`count == 2`), (d) sweep-pursuit-early (would fire only if we've swept) |
| Downstream fallback when not firing | `lowestByRank(nonTpref, contract)` — would return some non-T card; specifically NOT T of S |

**Wire discriminator:** the branch returns `tCard` (T of preferred
suit). The fallback (`lowestByRank(nonTpref)`) returns some lower
non-T card in the same suit. Test must assert `T<S>` (e.g. `"TH"`).

### 2.3 T-2 surface

| Dimension | Required state |
|---|---|
| Contract | Hokm or Sun (both work; Hokm has additional trump-exhausted side-channel) |
| Tier | M3lm+ (the feasibility gate at L1104 only runs when M3lm) |
| Trick context | `trickNum ∈ [3, 7]`; ALL prior tricks won by our team (`mySwept == trickNum - 1`); we are leading the current trick |
| State | `S.s.tricks` populated with `trickNum-1` entries, each with `winner` such that `R.TeamOf(winner) == myTeam` |
| Hand shape | `feasibleWinners >= 8 - trickNum + 1`: sum of (trump J/9/A in legal hand) + (other trumps where `HighestUnplayedRank(trump) == r`) + (side-suit bosses) |
| Memory | `S.HighestUnplayedRank(suit)` reflects "played" set consistent with the prior trick history; trump pool must have J/9/A available (or already played) such that our hand cards correctly score |
| Upstream shadows | Trick 1 mardoofa probe (`trickNum == 1`, blocked by gate), F5-3 pos-3 Sun Takbeer (would need pos-3 + Sun bidder partner), trick-8 sweep (`trickNum == 8`, blocked by gate) |
| Downstream fallback when not firing | The v0.5.19 default lead behavior — typically low-suit lead from `pickLead` legacy path |

**Wire discriminator:** the branch returns
`highestByFaceValue(safeBosses, contract)` when bosses exist. The
fallback path returns a low-rank card. Test must construct a hand
where the highest-face-value boss is uniquely identifiable AND the
legacy fallback would return a different card.

**Complexity multiplier:** the fixture needs:
1. `S.s.tricks` populated with N prior tricks, each with a valid
   winner-seat from our team.
2. `S.HighestUnplayedRank` stub that returns ranks consistent with
   the prior-trick history (no card we hold + no card a prior trick
   used can be "highest unplayed").
3. Hand calibrated so `feasibleWinners >= remainingNeeded`.

This is **substantially more state-construction work** than BH.1
through BH.4 required.

---

## 3. Fixture Feasibility Ranking

| Candidate | Complexity | Wire-clean? | Risk | Notes |
|---|---|---|---|---|
| **T-1.E2** | LOW-MED | YES (led-suit winner vs led-suit non-winner on a side-suit-led trick) | LOW | Same fixture family as BH.2/BH.3. Side-suit-led must-follow: legal set = our led-suit cards (one winner + one non-winner). Hand also carries 2 trumps off-legal so `myTrumpCount == 2` triggers E2 via hand-iteration. Faranka returns the led-suit non-winner; non-Faranka returns the led-suit winner. |
| **T-10** | MED | YES (T of pref suit vs lower in same suit) | LOW-MED | Needs partner-style ledger + flavor-classification path live. Existing F.3 pattern for `tahreebSent` is the template. Need to avoid trick-1 mardoofa and sweep-pursuit-early upstream gates (use trickNum=2). |
| **T-2** | MED-HIGH | YES but fragile | MED | Needs prior-tricks history + HighestUnplayedRank stub consistency + hand calibration. Three coupled state surfaces means more places for a fixture to drift. |

---

## 4. Proposed Batch Shape

**Smallest viable batch: T-1.E2 only.**

Rationale:
- Same fixture family as BH.2/BH.3 — Codex review surface is
  already calibrated to "Faranka exception positive/negative pair +
  source pin on the carve-out marker".
- Wire discriminator is unambiguous: **led-suit winner vs led-suit
  non-winner inside the side-suit-led legal set**. The Faranka
  block prefers `nonTrumpLosers`, so a legal set of one led-suit
  winner + one led-suit non-winner yields a clean wire test (`7H`
  for Faranka vs `AH` for natural play).
- F-16 interaction is locked from both sides: BI.1 holds K of
  trump in hand (F-16 satisfied → Faranka fires → returns
  `7H`); BI.2 drops the K (F-16 vetoes → natural play returns
  `AH`).
- No probabilistic surfaces, no partner-style ledger surgery, no
  prior-trick history construction. `playedCardsThisRound`
  seeding handles E3 avoidance without an explicit
  `HighestUnplayedRank` stub override.
- The side-suit-led fixture also avoids the trump-led
  must-overcut trap (see §2.1) that would otherwise collapse the
  legal set to a single card and short-circuit `Bot.PickPlay`
  before pickFollow runs.

**Optional B2 candidate: T-10.** Feasible if Codex wants to push
through both in one slice. Test pattern is well-precedented
(F.3 sets up `tahreebSent.H = { "7", "9" }`) and the upstream gates
are avoidable with `trickNum = 2`. Adds ~3 new harness checks (1
behavioural + optional 2 source pins).

**T-2: DEFER to a later batch.** The prior-tricks-history fixture
surface is meaningfully heavier than what BH currently exercises;
the harness has no precedent for `S.s.tricks` population in a
sweep-pursuit context. Recommend a dedicated design pass for T-2
that:
1. Reviews how F.3 or BH.4 might already populate `S.s.tricks`.
2. Confirms the `HighestUnplayedRank` stub used in BH.2/BH.3 covers
   the per-suit query for sweep-pursuit feasibility.
3. Decides whether to combine T-2 with the T-1.E3 (9-boss
   Exception #3) positive path, which has similar HUR-stub
   dependencies.

---

## 5. Test Plan

### 5.1 BI.1 — Exception #2 positive (F-16 satisfied)

**Section ID proposal:** new section **BI** (after BH). Approved.

**Shared fixture setup (used by BI.1 and BI.2):**

- Hokm contract, trump `D`.
- Bidder seat 1, bot seat 3 on bidder team, bot is M3lm+.
- Current trick: seat 4 leads `8H`, seat 1 plays `QH`, seat 2
  plays `KH`; bot seat 3 acts last.
- `playedCardsThisRound` includes `8H`, `QH`, `KH`. **`JD` is NOT
  marked played** ⇒ `S.HighestUnplayedRank("D") == "J"` ⇒
  Exception #3 stays false; the F-30b secondary trigger (HUR==nil)
  also stays false.
- Opp void-trump memory **unset** (no `Bot._memory[s].void.D`
  assignment for any opp seat) ⇒ `oppsVoidPath = false` ⇒
  Exception #4 stays false.
- Led suit is `H` (side suit ≠ trump), and the bot's hand
  includes ≥2 H cards, so the Hokm must-follow rule restricts the
  legal set to the bot's H cards (NOT trumps).
- Current trick winner is `KH` (highest H card played so far).

**BI.1 fixture intent:**

- Bot hand: `{ "AH", "7H", "KD", "9D" }`.
- Legal = `{ "AH", "7H" }` (must-follow on H; trumps stay
  off-legal but in hand).
- `AH` is a **winner** in led suit H (`AH > KH` in RANK_PLAIN).
- `7H` is a **non-winner** (`7H < KH`).
- `myTrumpCount == 2` (counts `KD` + `9D` in hand). `onBidderTeam
  == true` (seat 3 partners with bidder seat 1). ⇒ Exception #2
  triggers (`Bot.lua:3979-3981`).
- F-16 K-cover satisfied: `KD` is K of trump in hand. F-16 at
  `Bot.lua:4094-4102` runs but doesn't veto.
- Faranka block at `Bot.lua:4119-4143` enters: `winners = {AH}`,
  `nonWinners = {7H}`, `nonTrumpLosers = {7H}`. Returns
  `lowestByRank({7H}) = 7H`.

**Expected assertion:** strictly assert returned card is `"7H"`.

**Counterfactual integrity:** if E2 or Faranka does not fire,
natural pos-4 play returns `AH` (the legal winner). The strict
assertion `card == "7H"` discriminates the Faranka path from any
non-Faranka fallback, including a regression where the F-16
K-cover veto short-circuits incorrectly.

**Wire-discriminator integrity:** including `KD`/`9D` in the hand
(off-legal but counted) ensures `myTrumpCount == 2` while
contributing nothing to legal. The wire-clean choice is between
`AH` (winner / natural) and `7H` (non-winner / Faranka). If the
test returns `KD`, `9D`, or any non-led-suit card, that signals a
must-follow regression — stop and report rather than treating it
as a Faranka bug.

**Pre-fix state:** would PASS post-fix as written (E2 has shipped
since v0.9.2). This is a **regression guard**, not a wire-proof
for a new fix.

---

### 5.2 BI.2 — Exception #2 negative (F-16 vetoes via no-K)

**Fixture intent:** identical shared setup as BI.1 (same trick:
seat 4 `8H`, seat 1 `QH`, seat 2 `KH`; current winner `KH`).

- Bot hand: `{ "AH", "7H", "9D", "7D" }`.
- Legal = `{ "AH", "7H" }` (must-follow H, same as BI.1).
- `AH` is the led-suit **winner**.
- `7H` is the led-suit **non-winner**.
- `myTrumpCount == 2` (`9D` + `7D` in hand). `onBidderTeam ==
  true` ⇒ Exception #2 trigger flag fires.
- F-16 K-cover veto: **no K of trump in hand** ⇒
  `farankaTriggered = false` after `Bot.lua:4094-4102`.
- Natural pos-4 play returns the legal winner ⇒ `AH`.
- Counterfactual broken F-16 (Faranka allowed to fire without K)
  would return the non-winner `7H`.

**Expected assertion:** strictly assert returned card is `"AH"`.

**Wire role:** regression guard for the F-16 K-cover veto on E2.
A regression where F-16's K-check is removed or inverted would
return `7H` and the assertion would catch it.

---

### 5.3 BI.3 — SKIP

A separate `myTrumpCount == 1` negative was considered. Per Codex
review, BI.3 is **skipped** for this batch. BI.1 + BI.2 are
sufficient to lock the E2 positive path and the F-16 K-cover veto
on E2 — the two wire-clean assertions that this slice exists to
guard.

---

### 5.4 BI.4 — Source pin (existing markers only)

Test-only — do NOT add markers to `Bot.lua`.

Known markers to pin:

- **BI.4a:** `v0.10.0 X3 anti-rule F-16` (or sub-string
  `"X3 anti-rule"`) — appears at L4063 within the F-16 K-cover
  veto block.
- **BI.4b:** `v0.10.3 audit (A-Src-29` — appears at L4071 in the
  same block (the E4 carve-out comment).
- **BI.4c:** `v3.2.1 F4` — appears at L4082 (the E3 carve-out
  anchor).

These three pins together prove the F-16 veto block keeps its
historical anchors. If any substring is wrong on inspection, stop
and re-pin to an alternate existing marker — do NOT add a new
marker to `Bot.lua`.

---

### 5.5 Expected harness delta

| Item | Checks |
|---|---|
| BI.1 (positive E2) | 1 behavioural |
| BI.2 (negative no-K F-16) | 1 behavioural |
| BI.4a / BI.4b / BI.4c | 3 source-pin |
| **Subtotal** | **5** |

New harness total: `1264 + 5 = 1269 / 0`.

If Codex approves T-10 as B2 in the same slice, add:

| Item | Checks |
|---|---|
| BI.5 (T-10 positive: T-supply count≥3 want) | 1 behavioural |
| BI.6a / BI.6b (T-10 source pins on `v1.1.0 (audit partner-coord H1)` + `tahreebPrefFlavor`) | 2 source-pin |
| **Combined subtotal** | **8** |

Combined harness total: `1264 + 8 = 1272 / 0`.

Recommended slice: **T-1.E2 only** ⇒ `1269 / 0`.

---

## 6. Stop Conditions

Stop and report (do NOT silently work around) if any of these
happen during implementation:

1. **Fixture passes for the wrong branch.** If BI.1 returns
   `"7H"` but trace evidence shows non-Faranka path was used
   (e.g. E4's `oppsVoidPath` accidentally lit up via stale memory
   seeding, or E3's `exception3Path` tripped on a misseeded
   `HighestUnplayedRank`), the fixture is shadowed. Re-audit
   memory / played seeding and confirm only E2 lights up
   `farankaTriggered`.
2. **F-16 veto unexpectedly fires in BI.1.** If
   `farankaTriggered` is set back to false at
   `Bot.lua:4094-4102` despite `KD` in hand, the `C.IsTrump` stub
   or `contract.trump` value is wrong; re-audit fixture.
3. **Must-follow legal set is not `{AH, 7H}`.** If
   `R.IsLegalPlay` accepts a `D` card or `Bot.PickPlay` returns a
   trump, the Hokm must-follow rule is not firing on the H-led
   trick — re-audit fixture (likely a missing contract field, a
   stale led-suit value, or `S.s.akaCalled` left dirty from a
   prior test).
4. **BI.2 returns `"7H"` instead of `"AH"`.** That would
   indicate F-16 failed to veto Faranka — flag as a real
   regression rather than a fixture bug, since the F-16 K-cover
   veto is precisely what BI.2 is designed to guard. Stop and
   report.
5. **BI.1 or BI.2 returns a trump card (`KD`, `9D`, `7D`).**
   That signals a must-follow regression at the legality layer;
   the side-suit-led legal set should not contain any trumps when
   the bot has H cards. Stop and audit `Rules.lua` legality flow
   before adjusting the fixture.
6. **`S.HighestUnplayedRank("D") != "J"` despite `JD` not in
   `playedCardsThisRound`.** Indicates the HUR stub computes
   from a different source than `playedCardsThisRound`. Re-audit
   the stub layer before adjusting the fixture.
7. **Existing BA/BB/BE/BF/BH/F.* tests regress.** Any pre-existing
   harness check breaks ⇒ stop and report.
8. **Runtime change becomes necessary.** This is a test-only
   batch. If a runtime edit appears required to make a test pass,
   stop and report — do NOT proceed.
9. **Source-pin substring missing.** If BI.4a/b/c substrings
   don't appear in current `Bot.lua`, stop and re-audit existing
   markers — do NOT edit `Bot.lua` to add the marker.

---

## 7. Recommendation

**Proceed with smallest-batch implementation (test-only): T-1.E2.**

Scope:
- New BI section in `tests/test_state_bot.lua`.
- 3 tests: BI.1 (positive), BI.2 (no-K F-16 negative), BI.4 (source
  pin × 3 sub-asserts).
- Expected harness delta: `1264 / 0` → `1269 / 0`.

Deferrals tracked for later design passes:
- **T-10**: feasible MED-risk fixture; design as a standalone slice
  with its own positive + negative pair (e.g. "want" vs "dontwant"
  flavor classification).
- **T-2**: design pass needed on prior-tricks-history fixture
  approach; consider combining with T-1.E3 (9-boss Exception #3
  positive) for a single HUR-stub-heavy slice.
- **T-4**: remains DEFER-indefinite per v3.2.4 §3 — probabilistic
  surface, no clean wire discriminator.

---

## 8. Open Questions for Codex Review

The Codex amendment rounds resolved the previously open questions
around section naming (BI approved), BI.3 inclusion (skip),
HUR-stub coverage (no explicit stub needed when
`playedCardsThisRound` is seeded), and the `onBidderTeam` prologue
(clone BH.2). The trump-led fixture proposed in the first Codex
amendment was empirically shown to be structurally unreachable
(see §2.1 "Why side-suit-led, not trump-led" and the v3.2.5
batch-B implementation stop report), and Codex re-approved the
side-suit-led BH.2-family fixtures documented in §5.1 / §5.2.

The only remaining flag is a downstream observation that is
**not** in scope for this batch:

1. **T-10 partner-bot gate (Bot.lua:1294):** the receiver-side
   logic gates on `Bot.IsBotSeat(p)`. The v1.4.5 sender-side
   release removed the equivalent gate (the sender side now
   treats any partner symmetrically). Is this asymmetry
   intentional, or is it a stale parallel that the future T-10
   design pass should flag for a possible runtime fix? Logged
   here for the T-10 design slice when it lands. **Not in scope
   for this batch — no action expected during BI implementation.**

---

## 9. Confirmation

- No tracked files changed by this design pass.
- This document is created uncommitted; Codex review precedes any
  commit.
- No edits to `Bot.lua`, runtime files, `tests/`, `.toc`,
  `.pkgmeta`, `.github/`, CHANGELOG.
- No branch created, no tag created, no release initiated.
- `sprint-a-experimental` and `v0.5.1-experimental` preserved.
- `.swarm_findings/v3_2_0_botlua_comment_audit.md` untouched and
  untracked.
