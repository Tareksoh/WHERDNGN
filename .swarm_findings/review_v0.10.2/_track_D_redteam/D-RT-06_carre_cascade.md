# D-RT-06 — Carré-A in Hokm cascade red-team

**Audit version**: v0.10.2 (red-teaming v0.10.0 X5 fix)
**Track**: D (red-team)
**Scope**: confirm v0.10.0 X5 cascade is closed; surface new emit-related problems.

**Files inspected**
- `C:\CLAUDE\WHEREDNGN\Rules.lua` (R.DetectMelds 220-289, meldRank 301-331,
  R.CompareMelds 343-353, R.SumMeldValue 503-507, R.ScoreRound 661-953)
- `C:\CLAUDE\WHEREDNGN\Net.lua` (HostResolveTakweesh 2127-2300,
  HostResolveSWA 2862-3046, bot meld auto-emit 3433-3441 / 4076-4083,
  N.LocalDeclareMeld 2374-2383, replay-rejoin meld 403-410)
- `C:\CLAUDE\WHEREDNGN\State.lua` (S.ApplyMeld 1149-1189,
  S.GetMeldsForLocal 1930-1959)
- `C:\CLAUDE\WHEREDNGN\Bot.lua` (Bot.PickMelds 3408-3418)
- `C:\CLAUDE\WHEREDNGN\Constants.lua` (K.MELD_* 91-115, K.CARRE_RANKS 109)
- `C:\CLAUDE\WHEREDNGN\tests\test_rules.lua` (Carré tests 344-388;
  belote-cancel tests 658-686)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\xref_X5_meld_coverage.md`
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\reaudit_R5_carre_a_sun.md`
- `C:\CLAUDE\WHEREDNGN\CHANGELOG.md` 161-184 (v0.10.0 X5 + R5 entries)

---

## Executive summary

**Two HIGH-severity bugs survived the v0.10.0 X5 fix.** Both stem from the
same pattern: X5 only patched `R.DetectMelds`, but the meld value-derivation
logic is **duplicated** in `S.ApplyMeld` (wire-side handler) AND the
belote-cancellation predicate is **duplicated** in two Net.lua early-
termination scoring paths. Each duplicate kept its pre-fix shape.

The `R.DetectMelds` Carré-A emission is now correct, but downstream:

1. **`S.ApplyMeld` still drops Hokm Carré-A** (State.lua:1173-1177). Every
   wire-arrived meld declaration goes through this path. Both human-UI and
   bot-auto-declared Hokm Carré-A get silently zero-valued and the meld is
   never inserted into `s.meldsByTeam`. The X5 fix is functionally
   inert in any networked / multi-seat / bot-emitted scenario.

2. **Net.lua's takweesh + invalid-SWA belote-cancel paths still use
   `m.declaredBy == kWho`** (player-level, Net.lua:2240 and Net.lua:2972).
   The v0.9.0 M5 fix changed this in `R.ScoreRound` only. The same predicate
   in two other scoring sites kept its pre-M5 shape. Carré-A in Hokm now
   emits → Holder-A's belote SHOULD now be cancelled in early-termination
   paths, but only is in the regular round-end path.

These are independent of each other; either by itself silently mis-scores
a real Saudi-rule-relevant scenario.

Plus three smaller items below (one is in the changelog as already-flagged
but bears noting; two are non-issues that I document for completeness).

---

## Issue 1 — `S.ApplyMeld` value-derivation drops Hokm Carré-A (HIGH)

**Location**: `C:\CLAUDE\WHEREDNGN\State.lua` lines 1167-1184:

```lua
-- Mirror R.DetectMelds value derivation. Constants only define
-- MELD_CARRE_OTHER (T/Q/K/J — all 100 raw) and MELD_CARRE_A_SUN
-- (Aces in Sun only — 200 raw). 9/8/7 carrés don't score.
local value
if kind == "seq3" then value = K.MELD_SEQ3
elseif kind == "seq4" then value = K.MELD_SEQ4
elseif kind == "seq5" then value = K.MELD_SEQ5
elseif kind == "carre" then
    if K.CARRE_RANKS[top] then
        if top == "A" then
            if s.contract and s.contract.type == K.BID_SUN then
                value = K.MELD_CARRE_A_SUN     -- "Four Hundred", Sun only
            end
            -- Hokm 4-Aces: doesn't score (per Pagat-strict)
        else
            value = K.MELD_CARRE_OTHER          -- T, K, Q, J → 100 raw
        end
    end
    -- 9 carrés (and 8/7) drop through with value=nil → not scored
end
if not value then return end
```

The comment "Mirror R.DetectMelds value derivation" was true at the time
the code was written, but `R.DetectMelds` was patched in v0.10.0 X5 and
the comment block at Constants.lua:94 was updated to "T, K, Q, J (any
contract type) **AND Carré-A in Hokm**". `S.ApplyMeld` did NOT get the
mirror update — the inline `-- Hokm 4-Aces: doesn't score (per Pagat-
strict)` comment is still active and `value` stays `nil`, causing
`if not value then return end` to silently drop the meld.

**Caller graph for `S.ApplyMeld` (every meld declaration funnels here)**:

| Call site | What it covers |
|---|---|
| `Net.lua:1372` `N._OnMeld` | every wire-side meld arrival (multiplayer humans, partner-side bots from peer hosts) |
| `Net.lua:2377` `N.LocalDeclareMeld` | local human clicking "declare" in the UI |
| `Net.lua:3436` AFK auto-declare loop | AFK'd human gets bot-picked melds applied |
| `Net.lua:4079` `MaybeRunBot` bot dispatch | host-side bot's auto-declared melds |
| `Net.lua:407` (replay) | rejoiner state replay (recipient calls `_OnMeld` → `ApplyMeld`) |

**Every** path that puts a meld into `S.s.meldsByTeam` goes through
`S.ApplyMeld`. So even though `Bot.PickMelds` correctly returns a Hokm
Carré-A meld (it just calls `R.DetectMelds`), the host's call at line
4079 `S.ApplyMeld(seat, m.kind, m.suit, m.top, ...)` drops the value
to nil and the entry is never inserted.

**Net result**: in v0.10.0/v0.10.1 the X5 fix delivers ZERO of its
claimed cascade impact in real gameplay. The state container ends every
round with no Hokm-Carré-A entry in `meldsByTeam`. Nothing in
`R.ScoreRound`'s belote-cancellation, strict-majority, or `CompareMelds`
paths can see a meld that wasn't inserted.

**The X5 changelog entry's claimed cascade** ("broke bidder strict-
majority threshold check, R.CompareMelds winner-takes-all path, AND the
Belote-cancellation v0.9.0 M5 path") is, in practice, **still broken**
because the meld never reaches `meldsByTeam`. The regression test at
`test_rules.lua:365-380` passes because it calls `R.DetectMelds` directly,
bypassing the wire path. There is no `S.ApplyMeld` test for Hokm Carré-A.

**Confidence: HIGH.** Direct code trace; mirror-comment + dead-code
inline comment; no other code path constructs `meldsByTeam` entries.

**Recommended fix** (NOT applied — audit only):
```lua
elseif kind == "carre" then
    if K.CARRE_RANKS[top] then
        if top == "A" and s.contract and s.contract.type == K.BID_SUN then
            value = K.MELD_CARRE_A_SUN          -- "Four Hundred", Sun only
        else
            value = K.MELD_CARRE_OTHER          -- T/K/Q/J + Hokm-A (X5)
        end
    end
end
```

---

## Issue 2 — Net.lua belote-cancel still uses player-level predicate (HIGH)

**v0.9.0 M5** (per CHANGELOG.md:773-779 and `audit_v0.9.0/08_m5_belote_team.md`)
changed `R.ScoreRound`'s belote-cancellation from "the K+Q holder personally
declared the ≥100 meld" to "anyone on the K+Q holder's TEAM declared a
≥100 meld". This is correctly implemented at `Rules.lua:738-746`:

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

But `Net.lua` has TWO sibling sites that weren't updated:

**Site A — `HostResolveTakweesh`** (`Net.lua:2236-2245`):
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

**Site B — `HostResolveSWA` invalid-SWA branch** (`Net.lua:2968-2976`):
```lua
if kWho and qWho and kWho == qWho then
    beloteOwner = R.TeamOf(kWho)
    local list = (S.s.meldsByTeam and S.s.meldsByTeam[beloteOwner]) or {}
    for _, m in ipairs(list) do
        if m.declaredBy == kWho and (m.value or 0) >= 100 then
            beloteOwner = nil
            break
        end
    end
end
```

Both still gate on `m.declaredBy == kWho`. Two cascade misses:

(a) **Pre-X5 cascade missed**: in a takweesh / invalid-SWA scenario where
    K+Q-of-trump-holder's PARTNER declared a ≥100 meld, Belote should
    cancel but still scores +20 on these paths (the original v0.7.1 audit
    AUDIT_REPORT.md MEDIUM finding, never applied to Net.lua).

(b) **X5-NEW cascade**: now that Hokm Carré-A emits, a player holding
    K+Q-of-trump AND all 4 Aces (rare but legal — 6 specific cards in
    13) gets a Carré-A worth 100, and their Belote should cancel.
    `R.ScoreRound` does cancel; `HostResolveTakweesh` and
    `HostResolveSWA-invalid` do NOT (because `m.declaredBy == kWho`
    matches in this self-declared case... wait, no, it would match here
    too — declaredBy IS the K+Q holder).

Re-examining (b): if the K+Q holder ALSO holds the carré (same player),
`m.declaredBy == kWho` is true and the cancellation does fire. So the
X5 cascade specifically covers the case where the carré-holder IS the
K+Q-trump holder. In that narrow case, the Net.lua paths still cancel.

But the **partner-declared** case (a) was the v0.9.0 M5 motivation — and
those two Net.lua sites silently fall through when a partner provides
the ≥100 meld. The X5 cascade is unrelated to (a) but the cascade's
underlying rule cleanup (TEAM-level) is still incomplete.

**X5-cascade-specific edge in (b)**: even when the K+Q-of-trump holder
ALSO holds Carré-A (same hand), if the meld was somehow declared via a
codepath that didn't preserve `declaredBy = kWho` (e.g. a replay-rejoin
that lost the seat fingerprint, or a host bot-pick that mutated the
meld struct after `Bot.PickMelds` returned), the player-level predicate
would silently fail. This is a fragility argument, not a confirmed bug
— but it IS exactly the v0.7.1 motivation for fixing this in the first
place.

**Confidence: HIGH** that the predicate is wrong (it's literally the
pre-v0.9.0 shape). **MEDIUM** that this matters in practice for X5
specifically — most invocations have `kWho == declaredBy` because the
4-A holder also has K+Q-of-trump, and the cancellation fires. The
broader (a) bug (partner's ≥100 meld) is the actual high-impact path.

**Recommended fix**: collapse both Net.lua sites to `R.ScoreRound`'s
team-level predicate (drop `m.declaredBy == kWho` check):
```lua
for _, m in ipairs(list) do
    if (m.value or 0) >= 100 then
        belote = nil ; break
    end
end
```

Or — more durable — extract a single `R.BeloteCancelled(meldsByTeam,
team)` helper used by all three call sites so the next rule tweak only
edits one location.

---

## Issue 3 — Bot.PickMelds Hokm-A: declares correctly, but value drops at host

**Location**: `C:\CLAUDE\WHEREDNGN\Bot.lua` lines 3408-3418:

```lua
function Bot.PickMelds(seat)
    local hand = S.s.hostHands and S.s.hostHands[seat]
    if not hand then return {} end
    if (#(S.s.tricks or {})) >= 1 then return {} end
    return R.DetectMelds(hand, S.s.contract)
end
```

`Bot.PickMelds` is fully fixed by the X5 patch (it just delegates to
`R.DetectMelds`). The Hokm Carré-A meld will now appear in the returned
list with `kind="carre", top="A", value=K.MELD_CARRE_OTHER`.

**But** the consuming loop in `MaybeRunBot` (Net.lua:4076-4083) and
the AFK auto-declare loop (Net.lua:3433-3441) both call:
```lua
S.ApplyMeld(seat, m.kind, m.suit, m.top, C.EncodeHand(m.cards or {}))
```

These pass `m.kind, m.suit, m.top` — NOT `m.value`. `S.ApplyMeld` then
re-derives the value from `(kind, top, contract.type)` and (per Issue 1)
drops Hokm-A. So Bot.PickMelds emits the meld correctly, the loop
forwards it, but the storage layer eats it.

**Pre-v0.10.0 reliance check**: did anything assume Bot wouldn't emit
Hokm-A? Searching… `Bot.PickDouble` and friends scan `meldsByTeam` for
strength estimation. Pre-v0.10.0 Hokm-A never reached `meldsByTeam`, so
there was nothing to scan. Post-v0.10.0 still nothing to scan (Issue 1).
Once Issue 1 is fixed, `Bot.PickDouble`'s strength assessment will see
the new Hokm-A 100-meld and might tip the bel/triple/four threshold.
That's likely a desirable bot improvement, not a bug — flag for tuning
review only.

**Confidence: HIGH** that Bot.PickMelds is correct. The bot-side hole
is downstream at `S.ApplyMeld` (Issue 1).

---

## Issue 4 — `R.CompareMelds` Hokm-Carré-A interaction (NON-ISSUE)

**Question raised**: in Hokm contracts where both teams have a 100-meld
AND one team's Carré-A is now counted, does the comparison flip vs
pre-v0.10.0?

**Answer**: yes — and this is **the desired behavior per the X5 fix**.
The `meldRank` function at `Rules.lua:301-331` correctly handles the
new meld:

```lua
if m.kind == "carre" then
    local rankBonus = 0
    if m.top and contract then
        local probeSuit = (contract.type == K.BID_HOKM
                           and contract.trump) or "S"
        local rk = (B.Cards and B.Cards.TrickRank
                   and B.Cards.TrickRank(m.top .. probeSuit, contract))
                   or (K.RANK_INDEX[m.top] or 0)
        rankBonus = rk * 0.01
    end
    return 1000 + (m.value or 0) + rankBonus
end
```

For Hokm-Carré-A vs Hokm-Carré-K (both value=100): rankBonus is the
TrickRank of A vs K, with A's trick-rank > K's trick-rank in any
non-trump probe. So Hokm-Carré-A beats Hokm-Carré-K on tie-break.

For Hokm-Carré-A vs sequence-of-5 (value=100): the carré gets the +1000
class bonus, beating the sequence regardless of value. Correct per
Source I A1.

Per `xref_X5_meld_coverage.md` line 23, "Carré-J is just 100 like the
others; in Sun the Aces carré is the highest at 200 raw" — *that* table
note is now stale (Aces in Sun = 400 raw post-R5, and Aces in Hokm = 100
raw post-X5). The CODE handles all combos correctly via meldRank's
tie-break; the doc note is outdated.

**Confidence: HIGH non-issue.** Code is correct; the X5-cascade-flip
in `CompareMelds` outcomes IS the intent.

---

## Issue 5 — Belote cancellation with Hokm-Carré-A in `R.ScoreRound` (NON-ISSUE if Issue 1 fixed)

**Question raised**: with Carré-A now emitting in Hokm, the trump-K+Q
holder might cancel their own Belote via Carré-A. Does this fire?

**Answer**: in `R.ScoreRound` it would — if the meld actually existed in
`meldsByTeam`. The cancellation predicate at Rules.lua:738-746 iterates
the team's list and cancels on any `(m.value or 0) >= 100`. A Hokm
Carré-A (value=100) qualifies.

**But** per Issue 1, the meld never reaches `meldsByTeam` because
`S.ApplyMeld` drops it. So the cancellation predicate has nothing to
cancel against. The X5 changelog's claim "Belote-cancellation v0.9.0 M5
path (holder's missing 100-meld left Belote uncancelled → silent +20
over-scoring)" is correctly characterized — that was the bug; the
Hokm Carré-A holder's Belote DID over-score by 20. After Issue 1 is
fixed, the cancellation will fire correctly via Rules.lua:738-746.

The test at `test_rules.lua:658-668` verifies the cancellation works
when a meld is provided directly to `R.ScoreRound`. It does NOT verify
the end-to-end path through `S.ApplyMeld` — there is no integration
test confirming a Hokm Carré-A declared via wire actually ends up in
`meldsByTeam`. **A regression test that calls `S.ApplyMeld(seat,
"carre", "", "A", ...)` and asserts `meldsByTeam[team]` has the meld
would catch Issue 1.**

**Confidence: HIGH non-issue *conditional on Issue 1 being fixed*.**
Until Issue 1 is fixed, this scenario is silently still over-scoring
+20 in Hokm rounds where the K+Q-of-trump holder also holds 4 Aces.

---

## Issue 6 — Mathlooth + Carré-A interaction (NON-ISSUE)

**Question raised**: pre-v0.10.0 the K and Q of trump might appear in
BOTH a Carré-K (if 4) AND a Belote (K+Q same hand). With Hokm Carré-A
now emitting, what about Hokm Carré-K? Does the code double-count?

**Answer**: this is unrelated to X5. Carré-K + K+Q-trump-Belote was
ALREADY the pattern for which the v0.9.0 M5 fix exists — the holder of
4 Kings necessarily holds K-of-trump; if they also hold Q-of-trump, they
have Belote. Per Saudi rule (and `R.ScoreRound:738-746`), the 100-meld
(Carré-K) cancels the +20 Belote. No double-count. Code correct.

The "Mathlooth" reference in the prompt appears to conflate two things:
per `glossary.md:333`, مثلوث = "tripled" = a 3-card holding (specifically
J-tripled in Sun, where J + 2 sidekicks lets J win trick 3 after A and T
are spent). This is a STRATEGY pattern about partial holdings, NOT
about meld scoring at all. The K+Q-Belote interaction with Carré-K is a
separate, already-handled cancellation case.

**Confidence: HIGH non-issue.** Carré-K + Belote double-count is
correctly cancelled in `R.ScoreRound`. The Net.lua paths have the same
predicate gap as Issue 2 (player-level vs team-level), so a same-player
Carré-K + Belote scenario IS correctly handled in those paths too
(self-declaration → `m.declaredBy == kWho` matches → cancel fires).

---

## Issue 7 — Trump-implicit Carré-J (NON-ISSUE; already documented)

The CLAUDE.md remark "Carré J only counts trump-implicit" is doc drift,
already addressed in the v0.10.0 review per `xref_X5_meld_coverage.md`
Bug 3 and CHANGELOG.md:292-293. Code never had trump-conditional gating
on Carré-J — `K.MELD_CARRE_OTHER = 100` for J in any contract. The
`meldRank` tie-break (Rules.lua:309-321) only orders trump-J carré
above non-trump-J carré on equal value via `rk * 0.01`; the value
itself is 100 either way.

**Confidence: HIGH non-issue.** Code correct; CLAUDE.md doc was already
flagged for cleanup in v0.10.0.

---

## Issue 8 — Strict-majority threshold flip (NON-ISSUE)

**Question raised**: with Carré-A in Hokm now adding 100 meld points to
scoring, edge cases around 81/162 trick points where MELDS push scoring
past threshold — does R.ScoreRound's "strict majority" check ONLY look
at trick points (not melds)?

**Answer**: the check at `Rules.lua:763-767` includes melds AND belote
in the bidder/opp totals:
```lua
local bidderTotal = teamPoints[bidderTeam] +
    (bidderTeam == "A" and (effMeldA + beloteA) or (effMeldB + beloteB))
local oppTotal = teamPoints[oppTeam] +
    (oppTeam == "A" and (effMeldA + beloteA) or (effMeldB + beloteB))
```

Per Source I §C13 + Source L L40: bidder needs strict-majority of
**total points** (tricks + own-side meld bonus + own-side belote). NOT
strict-majority of trick points alone. The code matches the rule.

The Hokm Carré-A emit now correctly adds 100 to the bidder's total
(when the bidder team holds 4-A AND wins the meld comparison via
`R.CompareMelds`). Per the canonical rule this is the correct flip
direction: a bidder team that scrapes 75 trick points + 100 Carré-A
meld now totals 175 vs (assuming opponents have nothing) 87 — clear
make. Pre-X5 the bidder showed 75 vs 87 — wrongly failed. Fix produces
correct outcome. **Verified per `xref_X5_meld_coverage.md` Bug 7 row.**

**Confidence: HIGH non-issue.** Code correct (and X5 fixes the bug
the prompt was probing for here, modulo Issue 1's storage gap).

---

## Issue 9 — HostResolveTakweesh meld-zeroing (v0.10.1 M1) (PARTIAL non-issue)

**Question raised**: with offender melds now zeroed, does the offender
team STILL retain any Carré-A score?

**Answer**: in `HostResolveTakweesh` at `Net.lua:2216-2218`:
```lua
local offenderTeam = (winnerTeam == "A") and "B" or "A"
local mpA = (offenderTeam == "A") and 0 or meldA
local mpB = (offenderTeam == "B") and 0 or meldB
```

`mpA/mpB` is 0 for the offender team. `meldA/meldB` is the SUM of all
declared meld values (`R.SumMeldValue`). If a Hokm Carré-A entry made
it into `meldsByTeam[offender]` (which per Issue 1 it currently does
NOT), it would be in `meldA` and zeroed-out by this branch. So *if*
Issue 1 is fixed, the offender's Carré-A would correctly forfeit.

**Edge case**: the "winner team" still adds their own `meldA/meldB` × mult
to their pile. If the WINNER (non-offender) holds a Carré-A in Hokm,
they correctly score it — *if* Issue 1 is fixed. Currently they don't.

**Confidence: HIGH non-issue *in zeroing logic itself***. Conditional on
Issue 1: Net.lua's zero-meld path is correct and triggers cleanly. The
upstream gap is `S.ApplyMeld` not storing the Carré-A in the first place.

---

## Severity ranking

| # | Severity | What | Cascade impact |
|---|---|---|---|
| 1 | **HIGH** | `S.ApplyMeld` drops Hokm Carré-A | X5 fix is **functionally inert** in real gameplay; meld never enters meldsByTeam |
| 2 | **HIGH** | Net.lua belote-cancel uses player-level predicate | Pre-v0.9.0-M5 cascade missed in 2 sites; partner's ≥100 meld doesn't cancel Belote in takweesh / invalid-SWA paths |
| 3 | low | Bot emits OK but storage gap | Subsidiary to Issue 1 |
| 4 | n/a | CompareMelds tie-break | Working correctly |
| 5 | conditional | Belote-cancel via Hokm Carré-A | Works after Issue 1 fix |
| 6 | n/a | Mathlooth confusion | Misframed in prompt |
| 7 | n/a | Carré-J trump-implicit | Doc-only, already cleaned up |
| 8 | n/a | Strict-majority + meld | Code correct (and X5 fixes the right direction) |
| 9 | conditional | Takweesh meld-zeroing | Works after Issue 1 fix |

**Net cascade status**: of the v0.10.0 X5 fix's claimed three-way
cascade (strict-majority, CompareMelds, Belote-cancel-M5), all three
are **logically correct in `Rules.lua`** but **silently dead in
production** because `S.ApplyMeld` drops the meld at the storage layer.

Issue 1 is the highest-impact fix — closing it activates the X5
cascade for the first time. Issue 2 is a separate v0.7.1-vintage bug
that the X5 patch was claimed to "interact with" but did not actually
touch (M5 was applied to one of three sites only).

---

## Recommended fixes (NOT applied — audit only)

1. **State.lua:1167-1183**: rewrite the Carré-A branch in
   `S.ApplyMeld` to mirror the post-X5 `R.DetectMelds`:
   ```lua
   elseif kind == "carre" then
       if K.CARRE_RANKS[top] then
           if top == "A" and s.contract and s.contract.type == K.BID_SUN then
               value = K.MELD_CARRE_A_SUN
           else
               value = K.MELD_CARRE_OTHER          -- T/K/Q/J + Hokm-A
           end
       end
   end
   ```
   Replace inline comment "Hokm 4-Aces: doesn't score (per Pagat-strict)"
   — that's no longer true post-X5.

2. **Net.lua:2240 + Net.lua:2972**: drop `m.declaredBy == kWho` from
   both belote-cancellation predicates. Reduces to:
   ```lua
   for _, m in ipairs(list) do
       if (m.value or 0) >= 100 then belote = nil; break end
   end
   ```

3. **Refactor (defense-in-depth)**: extract `R.BeloteCancelled(team)`
   helper used by `R.ScoreRound`, `HostResolveTakweesh`, and
   `HostResolveSWA`. Single source of truth prevents the next M5-style
   cascade miss. Same DRY argument applies to the meld value-derivation
   logic — extract `R.MeldValue(kind, top, contract)` used by both
   `R.DetectMelds` and `S.ApplyMeld` (and any future caller).

4. **Tests to add**:
   - `S.ApplyMeld(seat, "carre", "", "A", encodedAces)` in Hokm contract
     → assert `meldsByTeam[team]` has the meld with value 100.
   - End-to-end: declare Hokm Carré-A, run `R.ScoreRound` on a Hokm
     round where the same player holds K+Q-of-trump Belote; assert
     `result.belote == nil`.
   - `HostResolveTakweesh` with partner-declared Carré-A and K+Q
     holder's belote → assert belote cancelled (currently fails).
