# T-4 Sun pos-4 5-factor Faranka — design / inventory pass

**Status:** design pass only. No runtime edits, no test edits, no
branch, no tag, no release. Uncommitted on `main`.

**Provenance:**

- Final HIGH-pickplay audit candidate from v3.2.1, deferred
  repeatedly through v3.2.4 / v3.2.5 design rounds on the
  rationale that the 5-factor framework is "probabilistic /
  EV-sensitive, similar to the F2 deception branch."
- Current state: `main = origin/main = 200a73a`. Harness baseline
  `1276 / 0` after BH/BI/BJ/BK landed.
- Latest shipped tag: `v3.2.3`.
- This doc inventories T-4 — the **Sun pos-4 Faranka 5-factor
  framework** at `Bot.lua:3155-3364` — and resolves whether the
  branch is implementable, source-pin-only, or defer-indefinite.

**Hard constraints (this pass):**

- Design only. **No edits to `Bot.lua`**, tests, `.toc`,
  `.pkgmeta`, `.github/`, packaging, or CHANGELOG.
- No branch, no tag, no release.
- Preserve `sprint-a-experimental` and `v0.5.1-experimental`.
- Leave `.swarm_findings/v3_2_0_botlua_comment_audit.md` untouched
  and untracked.
- This document stays **uncommitted** until Codex review approves.

---

## 1. Source Walkthrough

All line numbers verified against current `main` HEAD `200a73a`.

### 1.1 The full T-4 branch (Bot.lua:3155-3364)

The branch divides naturally into three layers:

1. **Outer gate (L3179-3181, no tier required):**

   ```lua
   if contract.type == K.BID_SUN and lastSeat and partnerWinning
      and trick.leadSuit
      and R.TeamOf(seat) == R.TeamOf(contract.bidder) then
   ```

   Sun contract + we're 4th seat + partner currently winning +
   we're on the bidder team. **No `Bot.IsM3lm()` or
   `Bot.IsAdvanced()` requirement** — the branch is reachable by
   Advanced-tier bots in `pickFollow` (Basic-tier uses random
   legal play and never enters `pickFollow`).

2. **Hand-shape predicate (L3187-3232):**

   ```lua
   for _, c in ipairs(legal) do
       if C.Suit(c) == lead then
           suitCount = suitCount + 1
           if C.Rank(c) == "A" then hasA = true
           elseif r == "T" or r == "K" then
               local cr = C.TrickRank(c, contract)
               if cr > coverRank then cover = c; coverRank = cr end
           end
       end
   end
   ...
   -- v1.4.0 (Concern 5 audit fix — Faranka anti-trigger row 167):
   local holdsTopTwoUnplayed = false
   if hasA and cover and S.s.playedCardsThisRound then
       local plainOrder = { "A", "T", "K", "Q", "J", "9", "8", "7" }
       local firstUnplayed, secondUnplayed = nil, nil
       for _, r in ipairs(plainOrder) do
           if not S.s.playedCardsThisRound[r .. lead] then
               if not firstUnplayed then firstUnplayed = r
               else secondUnplayed = r; break end
           end
       end
       if secondUnplayed and C.Rank(cover) == secondUnplayed then
           holdsTopTwoUnplayed = true
       end
   end
   ...
   if hasA and cover and suitCount == 2 and not holdsTopTwoUnplayed then
   ```

   Inner-block entry requires `hasA + cover (T or K) + suitCount
   == 2 + NOT holdsTopTwoUnplayed`. If any condition fails, the
   branch falls through to the **smother** block at L3366+
   (which returns the highest point card via Takbeer — typically
   `A` when the hand has A in led suit).

3. **5-factor inner block (L3233-3363):**

   ```lua
   -- v1.5.0 (audit follow-up — Faranka 5-factor framework).
   local captureRate = 0.50
   if cover and C.Rank(cover) == "J" then           -- F1
       captureRate = captureRate - 0.10
   end
   -- F2: partner-takes implicit (outer gate)
   if sweepActive then                               -- F3
       captureRate = captureRate - 0.10
   end
   if oppCum >= target - 26 then                     -- F4
       captureRate = captureRate - 0.10
   end
   if contract.bidder == lhoSeat and trickN == 1 then -- F5
       captureRate = captureRate - 0.10
   end
   -- Weak-partner inversion: captureRate += 0.40
   -- Opp-bidder + Kaboot threat anti-trigger: captureRate = 1.0
   ...
   -- v1.6.0 CS-01 borderline wobble (M3lm-gated):
   if Bot.IsM3lm and Bot.IsM3lm()
      and captureRate >= 0.40 and captureRate <= 0.60 then
       captureRate = captureRate + (math.random() * 0.20 - 0.10)
   end
   -- Clamp [0.05, 0.95]
   if captureRate < 0.05 then captureRate = 0.05 end
   if captureRate > 0.95 then captureRate = 0.95 end
   if Bot.IsM3lm and Bot.IsM3lm() and math.random() < captureRate then
       -- Capture: return A
       for _, c in ipairs(legal) do
           if C.Suit(c) == lead and C.Rank(c) == "A" then
               return c
           end
       end
   end
   return cover
   ```

   **Critical observation:** both the wobble (L3345) and the
   capture-vs-Faranka roll (L3352) are **`Bot.IsM3lm()`-gated**.
   For Advanced bots that are NOT M3lm, the inner block enters,
   computes `captureRate` (unused), skips both random gates, and
   falls through to `return cover` at L3362.

### 1.2 Nearby priority chain (upstream)

Searching upstream of L3155 inside `pickFollow`, the branches
that fire BEFORE the T-4 outer gate are:

| Location | Branch | Gates |
|---|---|---|
| L3066-3076 | Implicit AKA detection | Hokm + partner led bare-A in non-trump |
| L3100-3110 | partnerAkaSuit ledger write | partnerAKA flag live |
| L3111-3153 | AKA-receiver Takbeer/discard | Hokm + AKA live |

**None of these apply in Sun.** The T-4 branch at L3155 is the
**first Sun-relevant return** in pickFollow. There is no upstream
shadow.

### 1.3 Nearby priority chain (downstream fallbacks)

| Location | Branch | Returned card when T-4 falls through |
|---|---|---|
| L3366-3531 | Smother (Section 4 rule 7 Takbeer) | `pointCards[1]` — highest point card in led suit. For A-in-hand: returns `A`. |
| L3534-3700 | Tahreeb sender | Only fires when `voidInLed == true` (not applicable to T-4's suitCount≥1 fixture) |
| L3739-3788 | F5-3 pos-3 Sun Takbeer/Tasgheer (relocated v3.2.3) | Only fires at pos-3, not pos-4 |
| L3790-3848 | Rule 1B second-lowest re-entry | Only fires when we can't beat partner's lead (no winners in legal) |

The dominant fallback is **smother (Takbeer)** which returns the
highest point card.

### 1.4 Markers in the T-4 region

All verified single-line at `main` HEAD `200a73a`:

- **L3155:** `v0.5.21 Section 5 Sun pos-4 Faranka (Definite,
  video 06)` — origin marker.
- **L3201:** `v1.4.0 (Concern 5 audit fix — Faranka anti-trigger
  row 167)` — anchors the `holdsTopTwoUnplayed` carve-out.
- **L3233:** `v1.5.0 (audit follow-up — Faranka 5-factor
  framework)` — anchors the captureRate calculation.
- **L3332:** `v1.6.0 CS-01 (audit v1.5.3 swarm — predictability
  fix)` — anchors the borderline wobble.

---

## 2. Preconditions to Reach T-4

| Predicate | Requirement |
|---|---|
| Tier | At least Advanced (Basic uses random legal play, never enters pickFollow). M3lm only required to enter the random branches at L3345 and L3352. |
| Contract | `K.BID_SUN`. Hokm doesn't fire this branch. |
| Seat position in trick | `lastSeat == true` (we are pos-4, the last to act). |
| Trick winner | `partnerWinning == true` (partner is currently winning the trick). |
| Team | `R.TeamOf(seat) == R.TeamOf(contract.bidder)` (bidder-team only). |
| Lead suit | `trick.leadSuit` is set. |
| Hand shape | At least one A of led suit, at least one cover (T or K) of led suit, exactly 2 led-suit cards in legal. |
| Anti-trigger row 167 | `holdsTopTwoUnplayed` must be **false** to enter the 5-factor inner block. Either A + T cover (since 2nd unplayed is K-or-below — sometimes false), OR A + K cover but T NOT played (so 2nd unplayed is T not K). |

Reaching the 5-factor framework requires M3lm. Reaching the outer
gate's `return cover` deterministic path requires only Advanced.

---

## 3. Probabilistic-Gate Stubbing Analysis

### 3.1 The two random sites

Both random calls are at L3347 (wobble) and L3352 (capture roll).
Both are `Bot.IsM3lm()`-gated.

### 3.2 What stubbing achieves

The harness has a well-precedented arity-aware `math.random` shim
(e.g., AC.6 / AJ.12 / BE.1 / BF.9 / KH.* at `test_state_bot.lua:
3631 / 5716 / 5787 / 9533 / 9589`):

```lua
local origRandom = math.random
math.random = function(a, b)
    if a == nil then return 0.5 end  -- arity 0
    if b == nil then return a end     -- arity 1
    return 0                          -- arity 2
end
```

For T-4 specifically:

- **Stub `math.random() = 0.99`** (arity 0):
  - Wobble at L3347 (if it fires): `captureRate + (0.99*0.20 -
    0.10) = captureRate + 0.098` (deterministic upward shift).
  - Capture roll at L3352: `0.99 < captureRate`. With captureRate
    clamped to `[0.05, 0.95]`, `0.99 < 0.95` is false → **always
    Faranka**, returns `cover`.

- **Stub `math.random() = 0.0`** (arity 0):
  - Wobble: `captureRate + (0.0*0.20 - 0.10) = captureRate -
    0.10` (deterministic downward shift).
  - Capture roll: `0.0 < captureRate`. Always true → **always
    Capture**, returns `A`.

### 3.3 Is stubbing misleading?

**Mostly no, but with one caveat.**

- Stubbing `math.random()` to a constant is a well-established
  pattern in the harness; precedent exists at multiple sites.
- The test's docstring needs to explicitly state "with stubbed
  `math.random()=X`, the bot deterministically takes branch Y" —
  the test verifies that GIVEN a specific random value, the
  branch dispatch is correct. It does NOT verify the
  distribution of outcomes (that's the v1.5.0 / v1.6.0 design
  intent, which is by definition probabilistic).
- The capture path's wire-discriminator IS problematic: T-4
  capture returns `A`, but smother fallback also returns `A`.
  So a stubbed `math.random()=0.0` test cannot wire-distinguish
  the capture branch from the smother fallback. **The capture
  branch is wire-ambiguous regardless of stubbing.**

### 3.4 Cleanest deterministic discriminators

Two paths give clean wire-clean outcomes WITHOUT or WITH
math.random stubs:

| Path | Stub needed? | Returned card | Wire-clean? |
|---|---|---|---|
| Outer-gate + Advanced (NOT M3lm) → inner block enters but M3lm-gated random skipped → return cover | NO | `cover` (e.g. K) | YES (K vs smother's A) |
| Outer-gate + M3lm + stub=0.99 → Faranka branch returns cover | YES (arity-0 → 0.99) | `cover` | YES |
| Anti-trigger row 167 (holdsTopTwoUnplayed=true) → falls to smother | NO | `A` | YES (A vs Faranka's cover) |
| M3lm + stub=0.0 → Capture branch returns A | YES | `A` | NO (same as smother fallback) |

---

## 4. Positive Wire-Proof

### 4.1 BL.1 — outer-gate fires + Advanced (non-M3lm) → return cover

**Approach:** use Advanced (not M3lm) to deterministically land
in `return cover` at L3362 without stubbing math.random. This is
the simplest fixture and exercises the outer gate + hand-shape
predicate + anti-trigger row 167 (false) directly.

**Fixture sketch:**

- Sun contract (`type = K.BID_SUN`), bidder seat 1.
- Bot seat 3, same team A.
- `WHEREDNGNDB = { advancedBots = true }` (NOT m3lm).
- Trick: seat 4 leads `8H`, seat 1 plays `KH`, seat 2 plays
  `7H`; bot seat 3 acts last. Current winner is `KH` (seat 1 =
  partner) → `partnerWinning == true`.
- Bot hand at seat 3: `{ "AH", "TH", "8C", "7D" }`. Legal under
  Sun must-follow H: `{ "AH", "TH" }`. `suitCount = 2`, `hasA =
  true`, `cover = TH` (T is preferred over K via `coverRank`
  comparison since both could be present; here only T).
- `playedCardsThisRound = { ["8H"] = true, KH = true, ["7H"] =
  true }`. Top-2 unplayed in H = `{A, T}`. `cover = TH` and
  `secondUnplayed = "T"` → `holdsTopTwoUnplayed = TRUE`. **Wrong
  fixture — would fall through to smother.**

Iteration: to avoid `holdsTopTwoUnplayed`, we need either (a) T
NOT in hand (cover = K) and T also NOT played (so secondUnplayed
= "T"; cover K ≠ T → false), OR (b) T in hand + the suit's K
unplayed AND not held by bot (secondUnplayed = K, cover T ≠ K
→ false).

**Revised fixture:** hand `{ "AH", "KH", "8C", "7D" }` with `TH`
**NOT** in `playedCardsThisRound`. Top-2 unplayed: walk plainOrder
`{A, T, K, Q, J, 9, 8, 7}`. A is unplayed (in hand) →
firstUnplayed = A. Next: T unplayed (not in hand, not in
playedCardsThisRound) → secondUnplayed = T. Cover = K ≠ T →
`holdsTopTwoUnplayed = false`. ✓

But wait — if T is unplayed and NOT in any hand seeded, we'd be
implying it's in someone else's hand. The fixture needs to
**explicitly seed `playedCardsThisRound`** with the trick cards
that have been played BUT leave T off the played list. That's
fine — T can be in another seat's residual hand.

**Final BL.1 fixture:**

- Sun contract, bidder seat 1, bot seat 3, Advanced (not M3lm).
- Trick: `8H`, `JH`, `9H` (seat 4 lead, seat 1 plays JH partner-
  wins, seat 2 plays 9H). Choose JH as partner's play so partner
  is winning (JH > 9H > 8H in RANK_PLAIN; partner-team A).
- `playedCardsThisRound = { ["8H"] = true, JH = true, ["9H"] =
  true }`.
- Bot hand at seat 3: `{ "AH", "KH", "8C", "7D" }`. Legal: `{
  AH, KH }`. suitCount = 2, hasA = true, cover = KH.
- Top-2 unplayed: walk `{A, T, K, Q, J, 9, 8, 7}`. A unplayed →
  first. T unplayed (not in played, not in legal) → second. KH
  unplayed but cover=K ≠ secondUnplayed=T → `holdsTopTwoUnplayed
  = false`. ✓
- Inner block enters. captureRate computed (irrelevant — Advanced
  not M3lm). Both M3lm gates skip. Falls to `return cover` → KH.

**Expected assertion:** `card == "KH"`.

**Counterfactual:** if outer gate doesn't fire (e.g., not
partnerWinning, not Sun, not pos-4, not bidder-team), or if
hand-shape predicate fails (no A, no cover, suitCount ≠ 2),
falls to smother → returns AH. The KH vs AH wire-discriminator
proves the T-4 branch fired.

**Framing note (Codex review correction):** in the proposed
fixture, the bot's cover `KH` actually **beats** partner's
played `JH` in Sun (RANK_PLAIN trick-rank: K=6 > J=4 > 9=3 > 8=2).
This means when the test passes and the bot returns `KH`, the
bot wins the current trick — partner does NOT keep the trick.
That is **not the canonical v0.5.21 / video #06 strategic
outcome** the runtime comment at `Bot.lua:3159` describes
("Duck with the COVER, let partner take this trick"). The Saudi
strategic intent assumes the cover is rank-strictly LOWER than
what's already on the table; our fixture violates that
intent by construction so the wire-discriminator stays clean.

The test therefore wire-proves **branch priority and the
v1.4.0 anti-trigger row 167 carve-out**, not "partner remains
the current trick winner after our play." Test docstrings MUST
reflect this — do NOT describe BL.1 as "duck under JH" or
"partner keeps the trick." Describe it as "T-4 branch returns
the cover, preserving A in hand; smother / row 167 fallback
returns A."

### 4.2 Source-pin candidates

- **L3155:** `v0%.5%.21 Section 5 Sun pos%-4 Faranka` — anchors
  the outer gate's origin. Most-specific to T-4's structural
  anchor.
- **L3201:** `v1%.4%.0 %(Concern 5 audit fix` — anchors the
  v1.4.0 anti-trigger row 167 carve-out. Specifically tied to
  BL.2's behavior.
- **L3233:** `v1%.5%.0 %(audit follow%-up` — anchors the v1.5.0
  5-factor framework. Verifies the inner block's audit anchor
  remains.

I propose **two pins** for the slice (BL.3a + BL.3b on L3155 +
L3201) — both single-line, both directly relevant to BL.1 + BL.2.

---

## 5. Negative Wire-Proof

### 5.1 BL.2 — anti-trigger row 167 (holdsTopTwoUnplayed=true) → smother

**Fixture sketch:** same as BL.1 but seed `TH` into
`playedCardsThisRound`:

- `playedCardsThisRound = { ["8H"] = true, JH = true, ["9H"] =
  true, TH = true }`.

**Trace:**

- Outer gate fires (same as BL.1).
- hand-shape predicate: hasA, cover = KH, suitCount = 2.
- `holdsTopTwoUnplayed` walk: A unplayed → first. T IS in
  played → skip. K unplayed → second. Cover = K = secondUnplayed
  → **`holdsTopTwoUnplayed = TRUE`**.
- Inner block bypassed.
- Falls to smother at L3366+. pointCards = `{AH, KH}` → sorted
  descending by TrickRank → `[1] = AH`. Returns AH.

**Expected assertion:** `card == "AH"`.

**Wire role:** locks the v1.4.0 anti-trigger row 167 carve-out.
A regression where `holdsTopTwoUnplayed` detection is removed or
inverted would return KH instead of AH.

---

## 6. Existing Coverage

Grep for "Sun pos-4 Faranka" / "captureRate" / "5-factor" in
`tests/test_state_bot.lua` returns **zero** existing tests
covering the T-4 branch. Confirmation:

- **CC** (v3.2.1 F4) covers Hokm Exception #3 Faranka — different
  branch.
- **BH.2/3** (v3.2.5) cover Hokm Faranka Exception #4 — different
  branch.
- **BI.1/2** (v3.2.5) cover Hokm Faranka Exception #2 + F-16 —
  different branch.

The Sun pos-4 outer gate at L3179 is **completely uncovered** by
the existing harness.

---

## 7. Risk Assessment

| Option | Feasibility | Risk | Notes |
|---|---|---|---|
| **A. Deterministic test-only coverage (BL.1 + BL.2 + 2 source pins)** | YES | LOW | Outer gate + anti-trigger row 167 are both deterministic without math.random stubs (use Advanced, not M3lm). Clean wire-discriminator (KH vs AH). |
| **B. Probabilistic test-only coverage with math.random stub** | YES | MED | Adds M3lm-tier fixtures with stub=0.99 (Faranka) and stub=0.0 (Capture). Capture-branch fixture is wire-ambiguous (returns same A as smother). Only the Faranka stub fixture adds new wire-clean coverage beyond what BL.1 already provides. |
| **C. Source-pin only** | YES | LOW | Pin the three v0.5.21 / v1.4.0 / v1.5.0 markers. Validates source markers but doesn't exercise the runtime gates. |
| **D. Defer indefinitely** | n/a | n/a | Was the prior recommendation; no longer warranted given §4 + §5 demonstrate clean deterministic wire-proofs for the most audit-relevant gates (outer gate + row 167). |

Option A is the recommended path. Option B's incremental value
over A is limited because the M3lm random path's only
wire-clean outcome (Faranka returns cover) is **identical** to
A's outcome — adding a stubbed-M3lm fixture would duplicate the
KH assertion without adding coverage. The Capture branch
(returns A) is wire-ambiguous regardless.

---

## 8. Proposed Smallest Test-Only Slice

**Section:** `BL. v3.2.5 HIGH-pickplay regression coverage (T-4
Sun pos-4 Faranka)` — alphabetical continuation after BK.

### 8.1 BL.1 — Outer gate + Advanced fires Faranka (returns cover)

- Sun contract, trump nil, bidder seat 1.
- Bot seat 3, same team A.
- `WHEREDNGNDB = { advancedBots = true }` (NOT m3lm — keeps the
  random branches off).
- Trick: `{ leadSuit = "H", plays = { {seat=4, card="8H"},
  {seat=1, card="JH"}, {seat=2, card="9H"} } }`. Current winner
  is JH (seat 1 = partner). `partnerWinning = true`.
- `playedCardsThisRound = { ["8H"]=true, JH=true, ["9H"]=true }`.
- Hand at seat 3: `{ "AH", "KH", "8C", "7D" }`. Legal under
  must-follow H: `{ AH, KH }`.
- Trace: outer gate passes; hasA + cover=KH + suitCount=2 +
  !holdsTopTwoUnplayed (T unplayed but cover=K≠T). Inner block
  enters but both M3lm gates skip (not M3lm). Falls to `return
  cover` = `KH`.

**Expected assertion:** `card == "KH"`.

**Framing constraint (Codex review):** the test docstring and
inline comments MUST describe BL.1 as wire-proving **branch
priority** ("T-4 returns the cover, preserving A in hand") and
**anti-trigger row 167 polarity** (not-firing in BL.1, firing
in BL.2). They MUST NOT describe BL.1 as "ducking under JH" or
"partner keeps the trick" — the bot's `KH` (RANK_PLAIN 6) in
fact beats partner's `JH` (RANK_PLAIN 4), so the trick goes to
us not partner. The canonical Saudi v0.5.21 / video #06 "duck
+ let partner take" strategic intent assumes cover-strictly-
lower-than-table; our fixture violates that intent to keep the
wire-discriminator clean. The test is correct as a regression
guard but does not exemplify the rule's gameplay archetype.

### 8.2 BL.2 — Anti-trigger row 167 (holdsTopTwoUnplayed) → smother

- Same fixture as BL.1 EXCEPT `playedCardsThisRound` adds `TH`:
  `{ ["8H"]=true, JH=true, ["9H"]=true, TH=true }`.
- Trace: outer gate passes; hand-shape passes. But
  `holdsTopTwoUnplayed = TRUE` (T played, so secondUnplayed = K
  matches cover). Inner block bypassed. Smother returns highest
  point card = AH.

**Expected assertion:** `card == "AH"`.

### 8.3 BL.3 — Source pins (2 sub-asserts)

- **BL.3a:** `botSrc:find("v0%.5%.21 Section 5 Sun pos%-4
  Faranka")` — anchors outer gate origin at L3155.
- **BL.3b:** `botSrc:find("v1%.4%.0 %(Concern 5 audit fix")` —
  anchors anti-trigger row 167 at L3201. Single-line up to
  "fix" (before the em-dash) for pattern safety.

### 8.4 Expected harness delta

| Item | Checks |
|---|---|
| BL.1 (positive outer gate + Advanced → KH) | 1 behavioural |
| BL.2 (anti-trigger row 167 → AH) | 1 behavioural |
| BL.3a + BL.3b (source pins) | 2 source-pin |
| **Subtotal** | **4** |

New harness total: `1276 + 4 = 1280 / 0`.

### 8.5 Stop conditions

1. **BL.1 returns `"AH"` instead of `"KH"`.** Outer gate didn't
   fire (check Sun/lastSeat/partnerWinning/bidder-team), OR
   hand-shape predicate failed (suitCount or hasA), OR
   holdsTopTwoUnplayed misfired. Re-audit fixture seeding.
2. **BL.1 returns `"8C"` or `"7D"`.** Indicates legal-set
   regression — must-follow on H is failing. Audit
   `R.IsLegalPlay`.
3. **BL.2 returns `"KH"` instead of `"AH"`.** Indicates
   `holdsTopTwoUnplayed` detection failed — `playedCardsThisRound`
   seeding for `TH` is wrong, or the row 167 check is
   regressed. Stop and report as a possible runtime regression.
4. **Source-pin substrings missing.** Verify against current
   `Bot.lua` HEAD before adjusting; do NOT silently weaken the
   pin.
5. **Existing BA-BK tests regress.** Stop and report.
6. **Runtime change becomes necessary.** Test-only batch. If a
   runtime edit appears required, stop and report.

---

## 9. Close-Out / Defer Path

Not applicable — Option A (test-only coverage) is feasible per
§4/§5/§7. The historical "probabilistic / EV-sensitive" defer
rationale was correct for the 5-factor framework's INTERNAL
behavior, but missed that the **outer gate** and **anti-trigger
row 167** are both deterministic and wire-clean. Those are
where the canonical regressions live.

---

## 10. Recommendation

**Proceed with test-only coverage. Option A.**

Implement section BL with 4 checks (2 behavioural + 2 source-pin)
in `tests/test_state_bot.lua` only. Expected harness delta
`1276 / 0 → 1280 / 0`.

Deferrals tracked for later:

- **M3lm + math.random stub variants** of BL.1 (Faranka
  branch via the 5-factor random path). DEFER — they duplicate
  BL.1's KH assertion without adding coverage.
- **M3lm Capture branch wire-proof.** DEFER indefinitely — the
  Capture branch returns A which is wire-ambiguous with the
  smother fallback. No clean wire-discriminator exists.
- **Individual 5-factor isolations (F1-F5).** DEFER indefinitely
  — the captureRate clamp at [0.05, 0.95] + the borderline
  wobble + the random roll make individual factor effects
  wire-invisible at the returned-card level. Testing them would
  require capturing the internal `captureRate` value, which the
  runtime doesn't expose.
- **Weak-partner inversion (+0.40) and opp-bidder Kaboot
  anti-trigger (captureRate=1.0).** DEFER indefinitely — same
  rationale; the clamp + random roll make their effects
  wire-invisible.

---

## 11. Open Questions for Codex Review

1. **Section naming.** BK was the last v3.2.5 section. BL is the
   natural continuation. **Recommend BL.**

2. **Tier choice for BL.1.** I propose Advanced (not M3lm) to
   avoid the math.random stub. Codex may prefer M3lm + stub=0.99
   for "more realistic Saudi pro tier" coverage. The wire-
   discriminator outcome is identical (returns KH). **Recommend
   Advanced** for fixture minimalism; flag M3lm-stub variant as
   a future BL+ slice if Codex wants explicit M3lm coverage.

3. **Source-pin choice.** I propose two pins (L3155 + L3201).
   Codex may prefer one pin (most-specific = L3201, the row 167
   marker) or three (add L3233 5-factor framework). **Recommend
   two pins** — direct match to BL.1 (outer gate) + BL.2
   (row 167).

4. **Anti-trigger row 167 specifically chosen for BL.2.** The
   v1.4.0 row 167 carve-out was the most-recent runtime fix in
   this region (a real bug correction). Other carve-outs (F5
   LHO=bidder, F4 score-aware) require additional state plumbing
   for a clean wire-proof. **Recommend row 167** as the negative
   wire-target — it's the highest-leverage anti-trigger.

5. **BL.1 hand `{AH, KH, 8C, 7D}` choice.** I picked KH cover
   (not TH) to keep `holdsTopTwoUnplayed = false` in BL.1's
   played set. A TH-cover variant would require a different
   `playedCardsThisRound` setup (e.g., seed KH but not TH). The
   KH-cover form is cleaner. **Recommend KH cover.**

6. **lhoSeat (F5 factor) and other captureRate inputs.** None of
   the factor calculations are reached in BL.1 because Advanced
   is not M3lm. If we switched BL.1 to M3lm + stub, the lhoSeat
   = bot.seat3 + 1 = 4 and contract.bidder = 1 ≠ 4, so F5 is
   inactive in our fixture — captureRate stays at 0.50 baseline.
   Documented for future Codex audit of factor isolation.

---

## 12. Confirmation

- No tracked files changed by this design pass.
- This document is created uncommitted; Codex review precedes
  any commit.
- No edits to `Bot.lua`, runtime files, `tests/`, `.toc`,
  `.pkgmeta`, `.github/`, CHANGELOG.
- No branch created, no tag created, no release initiated.
- `sprint-a-experimental` and `v0.5.1-experimental` preserved.
- `.swarm_findings/v3_2_0_botlua_comment_audit.md` untouched
  and untracked.
