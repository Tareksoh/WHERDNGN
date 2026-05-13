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
| Trick context | **Trump-led** must-follow trick: opp leads trump card; current winner is a trump above some of our holdings; legal set = our trump cards |
| Hand shape (positive) | `myTrumpCount == 2`, includes K of T (F-16 K-cover); the two trumps split into **one winner** (rank > current winner) + **one non-winner** (rank < current winner) |
| Hand shape (negative) | `myTrumpCount == 2` but **no K of trump** ⇒ F-16 vetoes; same one-winner / one-non-winner split |
| Memory | `playedCardsThisRound` includes the trump cards from this trick (e.g. `AD`, `QD`, `8D`); J of T explicitly NOT played ⇒ `S.HighestUnplayedRank("D") == "J"` ⇒ E3 inactive. `Bot._memory[opp].void.D` unset ⇒ E4 inactive (`oppsVoidPath = false`) |
| Upstream shadows | Trick 1 mardoofa probe (lead-side only — N/A here, we're following), F5-3 pos-3 Sun Takbeer (Sun-only), any pre-must-follow short-circuit |
| Downstream fallback when not firing | Non-Faranka path → highest-rank legal trump (the **winner**) |

**Wire discriminator (positive vs negative):**

- **E2 fires + F-16 satisfied (K in hand):** Faranka block returns
  a **non-winner trump** (the K covers the withheld trump). The
  winner stays in hand.
- **E2 trigger fires + F-16 vetoes (no K in hand):** Faranka is
  suppressed; natural play returns the **winner trump** to take
  the trick.

Because the legal set on a trump-led trick is the bot's trump
cards, and Faranka by definition returns a non-winner, the
winner-vs-non-winner split inside the legal set is the wire-clean
discriminator. The legal set is exactly two cards (`myTrumpCount
== 2`), so each test asserts a specific card string.

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
| **T-1.E2** | LOW-MED | YES (winner-trump vs non-winner-trump on a trump-led trick) | LOW | Same family as BH.2/BH.3. Trump-led must-follow with hand = exactly 2 trumps (one above and one below the current trick winner). Legal set = the 2 trumps. Faranka returns the non-winner; non-Faranka returns the winner. |
| **T-10** | MED | YES (T of pref suit vs lower in same suit) | LOW-MED | Needs partner-style ledger + flavor-classification path live. Existing F.3 pattern for `tahreebSent` is the template. Need to avoid trick-1 mardoofa and sweep-pursuit-early upstream gates (use trickNum=2). |
| **T-2** | MED-HIGH | YES but fragile | MED | Needs prior-tricks history + HighestUnplayedRank stub consistency + hand calibration. Three coupled state surfaces means more places for a fixture to drift. |

---

## 4. Proposed Batch Shape

**Smallest viable batch: T-1.E2 only.**

Rationale:
- Same fixture family as BH.2/BH.3 — Codex review surface is
  already calibrated to "Faranka exception positive/negative pair +
  source pin on the carve-out marker".
- Wire discriminator is unambiguous: **winner trump vs non-winner
  trump on a trump-led trick**. The Faranka block only returns a
  non-winner, so a legal set containing exactly one winner and one
  non-winner yields a clean wire test (`KD` vs `9D` in BI.1;
  `9D` vs `7D` in BI.2).
- F-16 interaction is locked from both sides: BI.1 holds K of
  trump (F-16 satisfied → Faranka fires → returns non-winner);
  BI.2 drops the K (F-16 vetoes → natural play → returns winner).
- No probabilistic surfaces, no partner-style ledger surgery, no
  prior-trick history construction. `playedCardsThisRound`
  seeding handles E3 avoidance without an explicit
  `HighestUnplayedRank` stub override.

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
- Current trick: seat 4 leads `AD`, seat 1 plays `QD`, seat 2
  plays `8D`; bot seat 3 acts last.
- `playedCardsThisRound` includes `AD`, `QD`, `8D`. **`JD` is NOT
  marked played** ⇒ `S.HighestUnplayedRank("D") == "J"` ⇒
  Exception #3 stays false.
- Opp void-trump memory unset ⇒ `oppsVoidPath = false` ⇒
  Exception #4 stays false.
- Led suit is trump `D`, so the Hokm must-follow rule restricts
  the legal set to the bot's `D` cards.
- Current trick winner is `AD` (Hokm trump rank 6).

**BI.1 fixture intent:**

- Bot hand: `{ "9D", "KD", "8C", "7C" }`.
- Legal = `{ "9D", "KD" }` (must-follow on trump-led).
- `9D` is a **winner** (Hokm trump rank 7 > AD rank 6).
- `KD` is a **non-winner** (Hokm trump rank 4 < AD rank 6).
- `myTrumpCount == 2` and `onBidderTeam == true` ⇒ Exception #2
  triggers.
- F-16 K-cover satisfied by `KD`.
- Faranka block returns the **non-winner** ⇒ `KD`.

**Expected assertion:** strictly assert returned card is `"KD"`.

**Counterfactual integrity:** if E2 or Faranka does not fire,
natural play returns `9D` (the legal winner). The assertion `==
"KD"` discriminates the Faranka path from any non-Faranka
fallback, including a regression where the F-16 K-cover veto
short-circuits incorrectly.

**Wire-discriminator integrity:** including `8C`/`7C` in the hand
(illegal under must-follow) ensures no off-path fallback can
accidentally return them. The wire-clean choice is between `9D`
(winner / natural) and `KD` (non-winner / Faranka).

**Pre-fix state:** would PASS post-fix as written (E2 has shipped
since v0.9.2). This is a **regression guard**, not a wire-proof
for a new fix.

---

### 5.2 BI.2 — Exception #2 negative (F-16 vetoes via no-K)

**Fixture intent:** identical shared setup as BI.1 (same trick:
seat 4 `AD`, seat 1 `QD`, seat 2 `8D`; current winner `AD`).

- Bot hand: `{ "9D", "7D", "8C", "7C" }`.
- Legal = `{ "9D", "7D" }`.
- `9D` is a **winner** (Hokm trump rank 7 > AD rank 6).
- `7D` is a **non-winner** (Hokm trump rank 1 < AD rank 6).
- `myTrumpCount == 2` and `onBidderTeam == true` ⇒ Exception #2
  trigger flag fires.
- F-16 K-cover veto: **no K of trump in hand** ⇒
  `farankaTriggered = false` after L4094-4102.
- Natural play returns the legal winner ⇒ `9D`.
- Counterfactual broken F-16 (Faranka allowed to fire without K)
  would return the non-winner `7D`.

**Expected assertion:** strictly assert returned card is `"9D"`.

**Wire role:** regression guard for the F-16 K-cover veto on E2.
A regression where F-16's K-check is removed or inverted would
return `7D` and the assertion would catch it.

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

1. **Fixture passes for the wrong branch.** If BI.1 returns `"KD"`
   but trace evidence shows non-Faranka path was used (e.g. E4's
   `oppsVoidPath` accidentally lit up, or E3's `exception3Path`
   tripped on a misseeded `HighestUnplayedRank`), the fixture is
   shadowed — re-audit memory/played seeding.
2. **F-16 veto unexpectedly fires in BI.1.** If
   `farankaTriggered` is set false by L4094-4102 despite `KD` in
   hand, the `C.IsTrump` stub or `contract.trump` value is wrong;
   re-audit fixture.
3. **Must-follow legal set is not `{9D, KD}` in BI.1 (or
   `{9D, 7D}` in BI.2).** If `Rules.IsLegalPlay` accepts `8C` or
   `7C`, the Hokm must-follow rule is not firing on the trump
   lead — re-audit fixture (likely a missing contract field or a
   stale led-suit value).
4. **BI.2 returns `"7D"` instead of `"9D"`.** That would indicate
   F-16 failed to veto Faranka — flag as a real regression rather
   than a fixture bug, since the F-16 K-cover veto is precisely
   what BI.2 is designed to guard. Stop and report.
5. **`S.HighestUnplayedRank("D") != "J"` despite `JD` not in
   `playedCardsThisRound`.** Indicates the harness stub computes
   from a different source than `playedCardsThisRound`. Re-audit
   the stub layer before adjusting the fixture.
6. **Existing BA/BB/BE/BF/BH/F.* tests regress.** Any pre-existing
   harness check breaks ⇒ stop and report.
7. **Runtime change becomes necessary.** This is a test-only
   batch. If a runtime edit appears required to make a test pass,
   stop and report — do NOT proceed.
8. **Source-pin substring missing.** If BI.4a/b/c substrings
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

The Codex amendment round resolved the previously open questions
around section naming (BI approved), BI.2 discriminator (trump-led
fixture with winner/non-winner split), BI.3 inclusion (skip),
HUR-stub coverage (no explicit stub needed when
`playedCardsThisRound` is seeded), and the `onBidderTeam` prologue
(clone BH.2). The only remaining flag is a downstream observation
that is **not** in scope for this batch:

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
