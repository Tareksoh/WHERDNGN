# T-10 Tahreeb-return T-supply branch — design / inventory pass

**Status:** design pass only. No runtime edits, no test edits, no
branch, no tag, no release. Uncommitted on `main`.

**Provenance:**

- Builds on `.swarm_findings/v3_2_5_high_pickplay_batch_b_design.md`
  (the v3.2.5 Batch-B parent design that flagged T-10 as the next
  candidate after BI).
- Current state: `main = origin/main = 9e4e10a`. Harness baseline
  `1269 / 0` after BI merge.
- Latest shipped tag: `v3.2.3` (no v3.2.4/v3.2.5 release tag).
- This doc inventories T-10 — the receiver-side Tahreeb-return
  T-supply branch for `count >= 3` and `"want"` flavor — and
  resolves the open question from the BI design doc §8.1 about
  the partner-bot gate at `Bot.lua:1294`.

**Hard constraints (this pass):**

- Design only. **No edits to `Bot.lua`**, tests, `.toc`,
  `.pkgmeta`, `.github/`, packaging, or CHANGELOG.
- No branch, no tag, no release.
- Preserve `sprint-a-experimental` and `v0.5.1-experimental`.
- Leave `.swarm_findings/v3_2_0_botlua_comment_audit.md` untouched
  and untracked.
- This document stays **uncommitted** until Codex review approves.

---

## 1. Source Inventory

All line numbers verified against current `main` HEAD `9e4e10a`.

### 1.1 T-10 branch — `pickLead` Tahreeb-receiver T-supply

**Branch (`Bot.lua:1776-1788`):**

```lua
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

Sits inside the Tahreeb-return decision tree at
`Bot.lua:1727-1795` (the `if tahreebPrefSuit then` block). The
branch only enters this `elseif` after the upstream cases:

- **L1761:** `hasT and count == 1` → bare-T leads immediately.
- **L1764:** `hasT and count == 2` → doubled-T branches on
  partner-is-Sun-bidder (cover vs T).
- **L1776:** `hasT and tahreebPrefFlavor == "want"` ← **T-10**.
- **L1789:** else → legacy `lowestByRank(fromPref, contract)`.

So T-10 is the **count >= 3 + has-T + want-flavor** slot.

### 1.2 Upstream gate — partner-pref scoring (`Bot.lua:1267-1323`)

```lua
-- v0.5.10 Section 8 Tahreeb receiver + v0.5.14 Section 9 N-3
-- receiver. M3lm+ tier reads BOTH partner's and opponents'
-- recorded Tahreeb signals:
-- ...
--   • Partner positive (want/bargiya) → prefer leading that suit.
--   • Partner negative (dontwant)     → avoid leading that suit.
--   • Opp positive    (want/bargiya) → avoid (deny opp tempo).
--   • Opp negative    (dontwant)     → ignored (low value).
-- Bargiya (Ace-discard) = strongest single-event invite; "want" =
-- 2-event ascending. Conflict resolution: if partner-pref-suit is
-- ALSO in opp-avoid set, drop the partner pref (defending against
-- opp's signal dominates partner-help). Only honor when the
-- relevant seat is a bot (signals from humans are noise per the
-- Fzloky reasoning below).
-- Sources: decision-trees.md Section 8 (Definite, videos 01,
-- 02, 09, 10) + Section 9 N-3 (Common, video 10).
local tahreebPrefSuit = nil
local tahreebPrefFlavor = nil  -- v1.0.4 (agent #5): track flavor
...
if Bot.IsM3lm() and Bot._partnerStyle then
    -- Partner-side signals: positive = pref, negative = avoid.
    local p = R.Partner(seat)
    if Bot.IsBotSeat(p) then        -- ← THE GATE
        local pStyle = Bot._partnerStyle[p]
        local signals = pStyle and pStyle.tahreebSent
        ...
```

The `Bot.IsBotSeat(p)` gate at **L1294** is what determines
whether partner-side Tahreeb signals contribute to
`tahreebPrefSuit` / `tahreebPrefFlavor` at all. If partner is
human, the entire score loop is skipped and `tahreebPrefSuit`
stays nil → T-10 branch unreachable.

### 1.3 Architectural mirrors of the bot-only-read pattern

The receiver-side bot-only gate appears in **four** consumer
sites, all with the same rationale:

| Site | Line | Purpose |
|---|---|---|
| Partner-side Tahreeb pref-suit scoring | `Bot.lua:1294` | T-10's upstream gate |
| Opp-side Tahreeb avoid-set scoring | `Bot.lua:1472` | tanfeer / opp-deny logic |
| Fzloky partner-first-discard pref | `Bot.lua:1827` | `IsBotSeat(p)` gate on signal-aware lead pref |
| pickFollow discardable filter | `Bot.lua:5099` | "don't dump partner's tahreebSuit T/A" |

All four cite the same audit rationale (see §2.3 below). This is
not a local quirk at one call site — it is a system-wide
architectural pattern.

### 1.4 Sender-side parallel — v1.4.5 audit (`Bot.lua:3566-3583`)

```lua
-- v1.4.5 (multi-perspective audit, Codex finding): removed
-- the bot-partner-only gate. Pre-fix: `Bot.IsBotSeat(R.Partner
-- (seat))` constrained Tahreeb sender to fire only when partner
-- was a bot, treating human partners as "noise". Per Codex
-- audit:
--
-- > "Strong human players do read Saudi signals. Ignoring
-- > human-readable signaling leaves EV on table."
--
-- Saudi convention is a partnership language; competent human
-- partners (the kind who know to expect Tahreeb signaling)
-- understand and parse the convention. Sending the signal
-- helps them whether they're bot or human. M3lm+ tier gating
-- preserved (basic/advanced bots don't emit; the convention
-- is sophisticated). Receiver-side reads of human signals are
-- still appropriately discounted (humans may not strictly
-- follow the convention) — that asymmetry is correct per
-- audit guidance.
```

**This is the smoking gun for the asymmetry being intentional.**
The v1.4.5 audit explicitly considered the sender vs receiver
case, removed the gate on the sender side, and explicitly
preserved it on the receiver side with stated rationale.

### 1.5 Existing tests touching this region

- **F.3** (`test_state_bot.lua:1180-1239`): primes
  `Bot._partnerStyle[2].tahreebSent.H = { "7", "9" }` (opp-side
  ascending → "want") + an optional partner mirror. Asserts
  pickLead returns *a* valid card; does NOT strictly assert
  which card. **Does not exercise T-10's T-supply return.**
- **J.4 / J.4 sanity** (`test_state_bot.lua:1859-1923`): tests
  partner pref-suit selection via `lenAtAce` weight comparison.
  Asserts `C.Suit(card)`, not the rank. **Does not assert the
  T-supply return.**
- **v3.0.2** (`test_state_bot.lua:1925-1972`): single-K discard
  → "dontwant" avoid-set. Asserts suit avoided. **Not T-10.**
- **v3.0.3 GAP-01** (`test_state_bot.lua:1974-2023`): single-low
  → "want_hint". Asserts suit chosen. **Not T-10.**

**Gap:** no harness check asserts `card == T<pref suit>` when the
T-supply count-≥3-want branch should fire. The bare-T (count==1)
and doubled-T (count==2) sub-branches are also untested at the
strict-card-assertion level. T-10 specifically is what this
inventory targets.

---

## 2. Behavioural Surface

### 2.1 What makes T-10 fire?

Required conditions, in order:

1. `Bot.IsM3lm()` (upstream gate at L1291).
2. `Bot._partnerStyle` exists (initialised by `Bot.ResetMemory`
   or `Bot.OnPlayObserved`).
3. `Bot.IsBotSeat(R.Partner(seat))` returns true (L1294 gate).
4. Some non-trump suit `S` has
   `tahreebClassify(Bot._partnerStyle[partner].tahreebSent[S])
   == "want"` (or a stronger signal — but scoring ties below
   are dominated by "want" weight 2 unless `bargiya`/`first_led`
   intervenes).
5. Conflict-resolution doesn't drop the pref:
   `tahreebAvoidSet[S] = nil` (no opp "dontwant" on the same
   suit).
6. After full pref-suit scoring + the v3.1.2 color-inversion /
   first-led / cross-suit boosts at L1324-1424, `tahreebPrefSuit
   == S` AND `tahreebPrefFlavor == "want"`.
7. The `if tahreebPrefSuit then` block at L1727 is entered.
8. `fromPref` (legal cards in `S`, non-trump) has `count >= 3`
   AND `hasT == true` (T of `S` in legal hand).
9. We've passed the count==1 and count==2 sub-branches at
   L1761/L1764 (so explicitly `count >= 3`).

Result: `return tCard` at L1788. `tCard` is bound at L1753 when
the loop at L1748-1758 encounters the T of pref suit.

### 2.2 What is the fallback if T-10 doesn't fire?

If conditions 1-8 are met but condition 9's flavor check fails
(`tahreebPrefFlavor ~= "want"`), execution falls to L1789's
`else`: `return lowestByRank(fromPref, contract)`. For
non-trump-led non-trump cards in Hokm or any cards in Sun, this
uses `RANK_PLAIN` (7=1, 8=2, 9=3, J=4, Q=5, K=6, T=7, A=8) → the
T (rank 7) is NOT the lowest, so the fallback returns a
**different card** from T-10's return.

This gives a clean wire discriminator: `T<S>` (T-10 fires) vs
`lowestByRank(fromPref)` (T-10 doesn't fire) for the same hand
shape.

### 2.3 Partner-bot gate: bug, ambiguous, or intentional?

**Verdict: intentional, documented, and cross-validated by
Codex audit guidance.**

Evidence:

1. **Inline doc comment at L1278-1279** explicitly states:
   *"Only honor when the relevant seat is a bot (signals from
   humans are noise per the Fzloky reasoning below)."*

2. **Fzloky H-12 audit rationale at L1804-1810** (the "Fzloky
   reasoning" the partner-pref block references):
   *"Fzloky is a BOT-vs-BOT convention signal. A bot's first
   off-suit discard is a deliberate suit-preference
   communication; a HUMAN's first off-suit discard is just
   whatever card they shed (often a high card to dump weakness,
   often random). Reading a human's discard as a 'lead this
   suit' signal misdirects the bot's lead priority for the rest
   of the round."*

3. **v1.4.5 audit at L3580-3583** explicitly endorses the
   sender/receiver asymmetry:
   *"Receiver-side reads of human signals are still
   appropriately discounted (humans may not strictly follow the
   convention) — that asymmetry is correct per audit guidance."*

4. **Cross-site consistency** (§1.3): the same pattern appears
   at four receiver-side call sites
   (L1294/L1472/L1827/L5099). A stale parallel would have been
   inconsistent.

5. **Contrast with AKA at L5461-5472**: PickAKA explicitly
   REMOVED its own `IsBotSeat` gate per audit H-2 with rationale
   *"AKA is a canonical Saudi VOCAL signal that even a human
   teammate can read once they see the banner."* AKA is a vocal
   banner (machine-emitted, human-readable); Tahreeb is
   discard-based (not banner-emitted, humans don't reliably emit
   the convention). The contrast is what makes the receiver-
   side Tahreeb gate correct.

The asymmetry the v3.2.5 Batch-B design doc flagged as a
possibly-stale parallel is in fact the explicitly-endorsed
half of the v1.4.5 design.

---

## 3. Classification

**Per the prompt's A/B/C/D options:**

- ❌ A (test-only coverage backfill, no behavior bug)
- ❌ B (real bug; partner-bot asymmetry should be fixed)
- ❌ C (ambiguous; needs more evidence)
- ❌ D (defer)

→ **A. Test-only coverage backfill, no behavior bug.**

The asymmetry is intentional and audit-endorsed; T-10's
behavioural surface is testable; there is no runtime gap to
close. The action is to add regression coverage for both the
T-supply return path AND the architectural asymmetry markers
(via source pins), so a future runtime cleanup that accidentally
unifies or removes either side fires the harness.

---

## 4. Fixture Feasibility Ranking

| Item | Complexity | Wire-clean? | Risk | Notes |
|---|---|---|---|---|
| **T-10 positive (T-supply count=3 + want)** | LOW | YES (`TH` vs `8H` discriminator in Hokm-non-trump RANK_PLAIN) | LOW | Same fixture family as F.3 / J.4. Partner-bot ledger setup is well-precedented. `tahreebSent.H = {"7", "9"}` classifies to "want" with weight 2, beats default 0. |
| **T-10 negative (count=3 + flavor ≠ want)** | LOW | YES (`8H` vs `TH`) | LOW | Same fixture, swap signal to e.g. `bargiya_hint` (single `"A"` without `lenAtAce`) → weight 1 → still picks H but with flavor `"bargiya_hint"` → falls to legacy `lowestByRank` at L1792. |
| **Human-partner architectural test** | LOW-MED | Behavioral test fragile (fallback path depends on many heuristics) | MED | Better expressed as a **source pin** on the L1278-1279 marker. A behavioral test would only assert "not TH", which is a weak negative. Source pin is the stronger guard. |
| **v1.4.5 sender/receiver asymmetry pin** | LOW | Source-pin only | LOW | Lock the v1.4.5 audit comment at L3580-3583. Removing it would suggest someone is reverting the audit-endorsed asymmetry without a fresh audit. |

---

## 5. Proposed Smallest Next Batch

**Smallest viable test-only slice: BJ.1 + BJ.2 + BJ.3 + BJ.4.**

Section ID proposal: **BJ** (after BI, alphabetical continuation
of the v3.2.5 coverage thread).

### 5.1 BJ.1 — T-10 positive (count=3 + want flavor)

Fixture:

- Hokm contract, trump `S` (so H is non-trump).
- Bidder seat 4 (any non-3-team-A seat works; choosing seat 4
  keeps bot seat 3 on a non-bidder team so the trick-1 mardoofa
  probe — Sun-only anyway — is doubly N/A).
- Bot at seat 3, partner = seat 1.
- M3lm enabled (`WHEREDNGNDB.m3lmBots = true`).
- All seats marked `isBot = true` (gates `Bot.IsBotSeat(1)` →
  true).
- `Bot._partnerStyle[1].tahreebSent.H = { "7", "9" }` ⇒
  `tahreebClassify` returns `"want"`, score 2, beats default.
- Other `tahreebSent` entries empty.
- Lead context: `S.s.trick = { leadSuit = nil, plays = {} }`,
  `S.s.tricks = {}` (trick 1; safe because Hokm has no trick-1
  mardoofa block and sweep-pursuit needs trickNum>=3).
- Hand: `{ "TH", "9H", "8H", "JD" }`. Note `9H` does NOT match
  the signal record `{"7","9"}` — the signal record only tracks
  ranks partner DISCARDED, not what they hold; reusing rank 9 in
  the bot's own hand is fine.
- `count = 3` (TH, 9H, 8H in pref suit H), `hasT = true`.

Trace:

- T-10 fires at L1776-1788: `tCard = TH`, returns `TH`.

**Expected assertion:** strictly `card == "TH"`.

**Counterfactual integrity:** if T-10 doesn't fire, legacy
`lowestByRank(fromPref, contract)` at L1792 returns `8H` (rank 2
< rank 3 < rank 7 in Hokm-non-trump RANK_PLAIN). The `TH` vs
`8H` discriminator is the wire-proof.

### 5.2 BJ.2 — T-10 negative (count=3 + flavor ≠ want)

Fixture: same as BJ.1, but swap the signal so the flavor is
**not** `"want"`:

- `Bot._partnerStyle[1].tahreebSent.H = { "A" }` (single Ace
  without `lenAtAce` field). `tahreebClassify` returns
  `"bargiya_hint"`, score 1. Still selects H as
  `tahreebPrefSuit` (best score wins), but
  `tahreebPrefFlavor == "bargiya_hint"`.
- Same hand `{ "TH", "9H", "8H", "JD" }`.

Trace:

- Upstream block selects H, flavor `"bargiya_hint"`.
- Enters `if tahreebPrefSuit then` at L1727.
- `count = 3`, `hasT = true`.
- count==1 → false. count==2 → false. T-10 want check → false.
- Falls to L1789 else → `lowestByRank({TH, 9H, 8H}, contract)
  = 8H`.

**Expected assertion:** strictly `card == "8H"`.

**Wire role:** locks the `tahreebPrefFlavor == "want"` flavor
restriction (the v1.1.0 H1 fix's explicit guard).

### 5.3 BJ.3 — Source pin on receiver-side bot-only doc marker

**Amendment (Codex review round 2):** the original proposed
substring `"Only honor when the relevant seat is a bot"` crosses
a wrapped comment-line boundary in Bot.lua (the `"Only honor
when the"` text ends on L1277 and `"relevant seat is a bot"`
begins on L1278), so a single-line `botSrc:find` against the
raw newline-terminated source content would fail. Replace with
a single-line anchor that lives entirely on L1278:

```lua
assertTrue(botSrc:find("relevant seat is a bot") ~= nil,
    "BJ.3a: receiver-side Tahreeb bot-only-honor doc marker present")
```

Verified single-line presence at `Bot.lua:1278`:

```
1278:    -- relevant seat is a bot (signals from humans are noise per the
```

Locks the L1278-1279 doc comment. If a cleanup removes this
phrase, the L1294 gate's rationale is no longer in-source —
re-audit is required.

### 5.4 BJ.4 — Source pin on v1.4.5 sender/receiver asymmetry note

**Amendment (Codex review round 2):** the original proposed
substring `"Receiver%-side reads of human signals are still"`
crosses the L3580→L3581 wrap (`"still"` lives on L3581 inside
the next comment line). Replace with a single-line anchor that
lives entirely on L3580:

```lua
assertTrue(botSrc:find("Receiver%-side reads of human signals are") ~= nil,
    "BJ.4a: v1.4.5 sender/receiver asymmetry doc marker present")
```

Verified single-line presence at `Bot.lua:3580`:

```
3580:        -- is sophisticated). Receiver-side reads of human signals are
```

A clean alternative anchor on L3582 — `"asymmetry is correct
per"` — is also available if Codex prefers an explicit
asymmetry-endorsement phrase. Either is acceptable; recommend
the L3580 anchor because it directly names the "receiver-side
reads of human signals" semantic that BJ.3's L1278 pin already
addresses on the read side, giving us a clear paired
sender/receiver evidence chain.

Locks the L3580-3583 v1.4.5 audit comment. If a future change
removes the sender-side comment block (e.g. as part of a
"simplify Tahreeb sender" refactor), the asymmetry endorsement
disappears from the code — re-audit required.

Optional third pin (not recommended for this slice but worth
flagging for Codex):

```lua
-- Possible BJ.4b: lock the v1.4.5 "Codex finding" attribution
assertTrue(botSrc:find("v1%.4%.5 %(multi%-perspective audit") ~= nil, ...)
```

I recommend **NOT** adding BJ.4b — over-pinning increases the
fragility of doc-rewording without adding behavioural protection.
The single content-bearing phrase pin in BJ.4 is sufficient.

### 5.5 Expected harness delta

| Item | Checks |
|---|---|
| BJ.1 (positive T-supply want) | 1 behavioural |
| BJ.2 (negative flavor ≠ want) | 1 behavioural |
| BJ.3 (receiver-side bot-only doc pin) | 1 source-pin |
| BJ.4 (v1.4.5 asymmetry doc pin) | 1 source-pin |
| **Subtotal** | **4** |

New harness total: `1269 + 4 = 1273 / 0`.

---

## 6. Stop Conditions

Stop and report (do NOT silently work around) if any of these
happen during implementation:

1. **BJ.1 returns `"8H"` instead of `"TH"`.** Trace:
   `tahreebPrefSuit` was nil (partner-bot gate failed?
   `tahreebClassify` returned something other than `"want"`?),
   or count != 3. Re-audit the partner-style ledger seeding.
2. **BJ.1 returns `"9H"`.** That would suggest `tCard` was
   bound to the wrong card by the loop at L1748-1758. Should
   not happen if the hand uniquely contains `TH` — but if it
   does, audit `C.Rank` / `C.Suit` returning unexpected values.
3. **BJ.2 returns `"TH"`.** That would indicate T-10 fired
   even though `tahreebPrefFlavor != "want"` — a regression of
   the v1.1.0 H1 flavor restriction. Stop and report as a real
   runtime regression candidate.
4. **BJ.2 returns `"9H"` or `"AH"` (if AH were in hand).**
   Indicates `lowestByRank` is mis-ordering RANK_PLAIN. Re-audit
   stub layer.
5. **Source-pin substrings missing.** If BJ.3 (`"relevant seat
   is a bot"`) or BJ.4 (`"Receiver%-side reads of human signals
   are"`) substrings don't match current `Bot.lua`, the markers
   may have been reworded — pick alternate phrases AFTER
   auditing that the asymmetry rationale is still present in
   spirit; do NOT silently weaken the pin. Both anchors are
   single-line as of `Bot.lua` HEAD `9e4e10a` (verified
   `Bot.lua:1278` and `Bot.lua:3580`). Round-1 anchors that
   crossed wrapped comment-line boundaries (`"Only honor when
   the relevant seat is a bot"` and `"Receiver%-side reads of
   human signals are still"`) were rejected for this reason
   during Codex review round 2.
6. **Existing F.3 / J.4 / v3.0.2 / v3.0.3 / AE.4 / BA-BI / F.*
   tests regress.** Any pre-existing harness check breaks ⇒
   stop and report.
7. **Runtime change becomes necessary.** This is a test-only
   batch. If a runtime edit appears required, stop and report —
   do NOT proceed (especially: do NOT "fix" the L1294 gate; it
   is intentional per §2.3).
8. **trick-1 mardoofa or sweep-pursuit-early appears to fire.**
   The fixture uses Hokm + trickNum=1 + non-bidder-team to keep
   both shadows off, but if either branch is reachable
   under these conditions, re-audit the upstream guard chain.

---

## 7. Recommendation

**Proceed with smallest-batch test-only implementation: BJ.**

Scope:
- New BJ section in `tests/test_state_bot.lua`.
- 4 checks: BJ.1 (positive), BJ.2 (negative flavor), BJ.3 +
  BJ.4 (source pins on the architectural-asymmetry markers).
- Expected harness delta: `1269 / 0` → `1273 / 0`.
- No runtime change. No CHANGELOG. No tag.

Deferrals tracked for later design passes:

- **T-2 (sweep-pursuit-early Kaboot lead)** — still deferred
  pending dedicated design pass per BI doc §4.
- **T-10 bare-T (count=1) and doubled-T (count=2) branches** —
  also currently untested at strict-card-assertion level. NOT
  in this slice's scope but worth flagging as a follow-up.
  Hand-shape variants of BJ.1 could cover them in a future BK
  slice. Not urgent because T-10's most-likely-broken case is
  the count>=3 branch (the fix site itself).

---

## 8. Open Questions for Codex Review

1. **Section naming.** BI is the v3.2.5 Batch-B section. BJ is
   the natural next letter; alternative would be re-opening BI
   with `BI.5/BI.6/BI.7/BI.8`. Recommend BJ for clean batch
   boundary in `git log`.

2. **BJ.4's source-pin choice (resolved round 2).** The
   round-1 candidate (`"Receiver%-side reads of human signals
   are still"`) crossed a wrapped comment-line boundary and
   would have failed. Codex review approved the single-line
   anchor `"Receiver%-side reads of human signals are"` on
   `Bot.lua:3580`. The `"asymmetry is correct per"` alternative
   on `Bot.lua:3582` remains available if a future Codex round
   prefers the explicit asymmetry-endorsement phrasing.

3. **BJ.2's signal choice.** I propose `{ "A" }` (single Ace
   without `lenAtAce`) → `"bargiya_hint"`. Alternative choices
   are `{ "K" }` (`"dontwant"` — but that's the avoid-set
   path, would zero `tahreebPrefSuit`) or `{ "7", lenAtFirstDiscard
   = 3 }` (`"want_hint"`, score 1). The `bargiya_hint` choice
   is the cleanest: it still selects H as pref suit (so the
   `if tahreebPrefSuit then` block at L1727 enters), but the
   flavor is not `"want"`, so T-10 specifically doesn't fire.

4. **T-10 bare-T / doubled-T coverage.** Out of this slice's
   scope but the design doc flags them for a possible follow-up
   BK slice. Codex preference: ship BJ standalone, or batch BJ
   + BK together? My recommendation: BJ standalone, defer BK
   until BJ lands and review surface is clean.

5. **Asymmetry endorsement at the suite level.** Should the BJ
   section header include a docblock noting that the
   sender/receiver gate asymmetry is intentional and
   audit-endorsed? My recommendation: yes, mirror the v3.2.5
   BH/BI section header style with a 5-10 line docblock
   referencing this design doc and the v1.4.5 audit. Will add
   in the implementation prompt unless Codex prefers a shorter
   header.

---

## 9. Confirmation

- No tracked files changed by this design pass.
- This document is created uncommitted; Codex review precedes
  any commit.
- No edits to `Bot.lua`, runtime files, `tests/`, `.toc`,
  `.pkgmeta`, `.github/`, CHANGELOG.
- No branch created, no tag created, no release initiated.
- `sprint-a-experimental` and `v0.5.1-experimental` preserved.
- `.swarm_findings/v3_2_0_botlua_comment_audit.md` untouched
  and untracked.
