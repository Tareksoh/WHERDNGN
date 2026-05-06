# B-Bot-07 — `pickFollow` deep audit (v0.10.2)

**Reviewer:** Code-track agent (B-Bot-07)
**File reviewed:** `C:\CLAUDE\WHEREDNGN\Bot.lua` lines **2484-3252** (full
`pickFollow`) plus the WRITE-side recorders at **484-562** (touching-
honors + bait-ledger), called from `Bot.OnPlayObserved` (Bot.lua:331+).
**Cross-refs read:**
- `B-Bot-02_hokmFaranka.md` (v0.10.2 code-track on the Hokm Faranka
  block)
- `B-Bot-03_akaReceiver_m4live.md` (v0.10.2 M4 LIVE branch audit)
- `D-RT-03_faranka_edges.md` (red-team Faranka edges, post-v0.10.2)
- `Rules.lua:89-210` (`R.IsLegalPlay` with M4 `akaCalled` param)
- `State.lua:1238-1264` (`S.ApplyPlay` false-AKA detection),
  `State.lua:1327` (`s.akaCalled = nil` on trick end)
- `BotMaster.lua:580-898` (`heuristicPick` ISMCTS rollout policy —
  parallel to `pickFollow`, never reaches the heuristics audited here)
- `docs/strategy/decision-trees.md` Sections 4, 5, 6, 8, 9, 10, 11
- `CHANGELOG.md` v0.5.x — v0.10.2 entries

**Severity legend:** **BUG** = behaviour-wrong on the canonical case
or against Source-doc intent. **EV-LEAK** = sub-optimal but legal /
not strictly wrong. **NIT** = cosmetic / minor. **OK** = predicate
behaves as intended. **DEFER** = real concern out of scope for v0.10.2.

---

## TL;DR

Eleven findings across the requested audit scope. **The single new bug
of substance is D-RT-03 S-1**: F-16 (no-K-of-trump → don't Faranka)
over-fires on F-30b (both opps observed-void in trump), surrendering a
risk-free Faranka. Everything else is either correct, defensible, or
already-flagged-as-deferred from prior audits.

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| 1 | Hokm Faranka block — 3 of 6 source-C exceptions wired, gating consistent | OK | Verified intact |
| 2 | **F-16 over-fires on F-30b risk-free path (D-RT-03 S-1)** | **EV-LEAK / BUG** | **Recommend fix** |
| 3 | AKA-receiver branch (line 2546-2558) now LIVE post-v0.10.2 M4 | OK | Verified |
| 4 | M4 R.IsLegalPlay AKA passthrough — passthrough at this site correct | OK | Verified |
| 5 | Sun pos-4 Faranka (Section 5) — gating + cover-pick correct | OK | Verified |
| 6 | Touching-honors WRITE site (484-507) — partner-still-winning gate MISSING | **BUG** | **Carry-forward; D-RT-07** |
| 7 | Bait-ledger WRITE site (510-562) — v0.9.2 #46 gate present; D-RT-12 still-vulnerable carry-forward | NIT | Defer |
| 8 | Tahreeb signal recording (564+) — partner-pre-winning check + style.tahreebSent | OK | Verified |
| 9 | "Don't waste a high card" lowestByRank fallthrough (2848) | OK | Verified |
| 10 | Section 4 rule 1B wouldWin gate (v0.9.5) — correct | OK | Verified |
| 11 | Tahreeb sender T-1 Bargiya / Want-arm / T-4 dump-ordering ordering correctness | OK | Verified |

---

## Audit findings

### Finding 1 — Hokm Faranka block (lines 2857-3022): wired vs unwired triggers, gating consistency

**Severity:** OK (carry-forward of B-Bot-02).

**What was probed:** All 3 wired triggers, 3 unwired exceptions, F-16
veto, J+8 anti-trigger, order of evaluation.

**Quote (gate, line 2880-2881):**
```lua
if Bot.IsM3lm() and contract.type == K.BID_HOKM and contract.trump
   and trick.leadSuit and #winners > 0 then
```

**Quote (`onBidderTeam` shared predicate, line 2898-2899):**
```lua
local onBidderTeam = (contract.bidder
                      and R.TeamOf(contract.bidder) == R.TeamOf(seat))
```

**Quote (Trigger #2 / F-27, line 2900-2902):**
```lua
if myTrumpCount == 2 and onBidderTeam then
    farankaTriggered = true
end
```

**Quote (Trigger #3 / F-29, line 2922-2932):**
```lua
if not farankaTriggered and onBidderTeam
   and S.HighestUnplayedRank
   and S.HighestUnplayedRank(contract.trump) == "9" then
    local hold9 = false
    for _, c in ipairs(hand) do
        if C.Suit(c) == contract.trump and C.Rank(c) == "9" then
            hold9 = true; break
        end
    end
    if hold9 then farankaTriggered = true end
end
```

**Quote (Trigger #4 / F-30b, line 2943-2955):**
```lua
if not farankaTriggered and onBidderTeam then
    local oppTrumpExhausted = true
    for s2 = 1, 4 do
        if R.TeamOf(s2) ~= R.TeamOf(seat) then
            local m = Bot._memory and Bot._memory[s2]
            if not (m and m.void and m.void[contract.trump]) then
                oppTrumpExhausted = false
                break
            end
        end
    end
    if oppTrumpExhausted then farankaTriggered = true end
end
```

**Verdict:** Gating is **consistent**. All 3 enable-sites short-circuit
on `not farankaTriggered`, all are guarded by `onBidderTeam`. No path
to `farankaTriggered = true` bypasses the bidder-team gate (B-Bot-02 F2
exhaustively enumerated this). v0.9.2 #49 + v0.10.0 X3 closures intact
post-v0.10.2.

**Reproduction notes:** for tests, `WHEREDNGNDB.m3lmBots = true`,
`S.s.contract = {type=K.BID_HOKM, trump="S", bidder=1}`, hand with 2
trumps + 6 non-trumps for the seat-3 partner-of-bidder probe. See
B-Bot-02 F10 for fixture pattern.

---

### Finding 2 — F-16 over-fires on F-30b risk-free path (D-RT-03 S-1)

**Severity:** **EV-LEAK / BUG (low–medium)** — recommend fix in next
release.

**What was probed:** When both opps are observed-void in trump (Trigger
#4 fires), Source-C's F-16 "no K of trump → don't Faranka" anti-rule
is no longer needed (the threat model "opp punishes withhold with their
remaining trump" is extinct because they have none). But the code
applies F-16 universally to all 3 triggers.

**Quote (F-16 veto, line 2964-2972):**
```lua
if farankaTriggered then
    local hasKtrump = false
    for _, c in ipairs(hand) do
        if C.IsTrump(c, contract) and C.Rank(c) == "K" then
            hasKtrump = true; break
        end
    end
    if not hasKtrump then farankaTriggered = false end
end
```

**Repro (from D-RT-03 S-1, verified):**
- Tier: M3lm+. Hokm; trump = S; bidder = seat 3 (us); our team = bidder team.
- `Bot._memory[2].void["S"] = true`, `Bot._memory[4].void["S"] = true`
  (both opps observed void in trump).
- Hand: `{ JS, 9S, 7S, AH, KH, AD, QC, 8C }` (3 trumps; **no KS**).
- Opp leads QH; we have winners (AH, KH).

**Trace:**
1. Line 2898-2899: `onBidderTeam = true`.
2. Line 2900-2902: Trigger #2 — `myTrumpCount == 3`, doesn't fire.
3. Line 2922-2932: Trigger #3 — `S.HighestUnplayedRank("S") == "J"`,
   doesn't fire.
4. Line 2943-2955: Trigger #4 — `oppTrumpExhausted = true`,
   `farankaTriggered = true`.
5. Line 2964-2972: Loop hand; no KS found; `farankaTriggered = false`.
6. Block falls through to natural play; we play a winner instead of
   the risk-free Faranka.

**Why this is wrong:** F-16's premise is "the K is the cover card
backing up the withhold". By F-30b's predicate, opps have **zero
trump remaining** — the threat F-16 protects against (opp A-of-trump
attacking the preserved card) is structurally extinct. Withholding
top trump is risk-free. F-16 has no useful work to do here.

**Recommended fix (one-line):** scope F-16 to non-F-30b paths. E.g.:

```lua
-- Pseudocode, do NOT modify code per audit scope.
if farankaTriggered and not oppTrumpExhausted then
    -- existing F-16 K-scan
end
```

Hoisting `oppTrumpExhausted` to a wider scope. Or per D-RT-03 option
(A): track which trigger fired and gate F-16 to triggers #2/#3 only.

**Confidence:** **HIGH**. Source C F-16 reasoning + F-30b predicate
both unambiguous. D-RT-03 explicitly verified end-to-end.

---

### Finding 3 — AKA-receiver branch (lines 2546-2558) post-v0.10.2 M4

**Severity:** OK — branch verified LIVE.

**What was probed:** Pre-v0.10.2 the explicit-AKA leg of this branch
was structurally dead because `R.IsLegalPlay` filtered non-trumps out
of `legal` (must-trump-ruff fired) before `discards` could be filtered.
v0.10.2 M4 patched `R.IsLegalPlay` to honour `akaCalled` and exempt
the receiver from must-trump-ruff (Rules.lua:115-121, 175). Confirmed
that `legalPlaysFor` (Bot.lua:1607) reads live `S.s.akaCalled` and
forwards it.

**Quote (executable gate, line 2546-2558):**
```lua
if Bot.IsAdvanced() and contract.type == K.BID_HOKM and contract.trump
   and trick.leadSuit and partnerWinning
   and (explicitAKA or implicitAKA) then
    local discards = {}
    for _, c in ipairs(legal) do
        if not C.IsTrump(c, contract) then
            discards[#discards + 1] = c
        end
    end
    if #discards > 0 then
        return lowestByRank(discards, contract)
    end
end
```

**Quote (`explicitAKA` capture, line 2512-2514):**
```lua
local explicitAKA = S.s.akaCalled
                    and S.s.akaCalled.seat == R.Partner(seat)
                    and S.s.akaCalled.suit == trick.leadSuit
```

**Verdict:** the canonical case `void+has-trump+AKA-active` now reaches
the discard filter with non-trump cards in `legal`, and `lowestByRank`
correctly picks the cheapest dispensable non-trump. B-Bot-03 verified
this end-to-end against test pins `tests/test_rules.lua:1107-1156`
(Section Q, 8 pins, all pass).

**Carry-forward (B-Bot-03 F2):** AKA-on-T trick lock (J-067 part 1)
is still NOT implemented in `R.CurrentTrickWinner` (Rules.lua:34-59).
The `Rules.lua:108-110` comment claiming the 10-substitutes-for-Ace
semantic "collapses to the same rule" is **misleading**: M4 implements
the receiver-relief side only, not the trick-lock side. Rule
interpretation ambiguous between "convention" and "lock"; documentation
fix recommended.

**Confidence:** HIGH on the LIVE-branch claim. MEDIUM on the
trick-lock interpretation question.

---

### Finding 4 — v0.10.2 M4 R.IsLegalPlay AKA-aware passthrough at this site

**Severity:** OK.

**What was probed:** Does `legalPlaysFor` (which `pickFollow` reads
through) pass `S.s.akaCalled` to `R.IsLegalPlay`?

**Quote (Bot.lua:1600-1614):**
```lua
local function legalPlaysFor(hand, trick, contract, seat)
    -- v0.10.2 M4: pass live `s.akaCalled` to R.IsLegalPlay so the
    -- AKA-receiver relief (J-066/J-067) is honored at the legality
    -- layer.
    local aka = S and S.s and S.s.akaCalled or nil
    local out = {}
    for _, c in ipairs(hand) do
        local ok = R.IsLegalPlay(c, hand, trick, contract, seat, aka)
        if ok then out[#out + 1] = c end
    end
    return out
end
```

**Verdict:** correct passthrough. Live AKA banner is consulted on every
legality query inside `pickFollow`. Trickle-through chain:
`Bot.PickPlay` → `legalPlaysFor` → `R.IsLegalPlay(card, ..., akaCalled)`
→ AKA-relief gate at Rules.lua:115-121 → the receiver discard filter
at line 2549.

**Note (defensive):** Simulator callers (e.g. `R.SunCanRolloff`) pass
`nil` for `akaCalled`, deliberately getting AKA-blind semantics —
correct for rollouts. The live-play `legalPlaysFor` is the only path
that surfaces `S.s.akaCalled` here.

**Confidence:** HIGH.

---

### Finding 5 — Sun pos-4 Faranka (v0.5.21 Section 5)

**Severity:** OK.

**What was probed:** The Sun bidder-team Faranka rule — Sun + last seat
+ partner-winning + we hold A + cover (T or K) of led suit + EXACTLY 2
cards of led suit → duck with the cover.

**Quote (line 2584-2613):**
```lua
if contract.type == K.BID_SUN and lastSeat and partnerWinning
   and trick.leadSuit
   and R.TeamOf(seat) == R.TeamOf(contract.bidder) then
    local lead = trick.leadSuit
    local hasA = false
    local cover = nil
    local coverRank = -1
    local suitCount = 0
    for _, c in ipairs(legal) do
        if C.Suit(c) == lead then
            suitCount = suitCount + 1
            local r = C.Rank(c)
            if r == "A" then hasA = true
            elseif r == "T" or r == "K" then
                local cr = C.TrickRank(c, contract)
                if cr > coverRank then
                    cover = c
                    coverRank = cr
                end
            end
        end
    end
    if hasA and cover and suitCount == 2 then
        return cover
    end
end
```

**Verdict:** all 4 anti-trigger guards intact:
- Rule 4 anti-trigger: `suitCount == 2` strict (avoids ≥3-card case
  where T drops naturally).
- Rule 9 anti-trigger: `R.TeamOf(seat) == R.TeamOf(contract.bidder)`.
- Pos-4 only: `lastSeat`.
- Partner-winning: `partnerWinning`.

**Source-C F-17 enforced** via `suitCount == 2`. **Source-C F-14** (the
verbal "must Faranka" trap) handled by the precondition `partnerWinning`
— when opp is winning, this block is skipped and the seat falls through
to the winners branch, taking the trick (B-Bot-02 F4 verified this is
the corrected reading).

**Cover-pick logic:** picks the highest-trick-rank cover (T preferred
over K when both held), which matches the canonical "A+T mardoofa"
shape per video #06.

**Confidence:** HIGH. Block stable since v0.5.21; no regression in
v0.10.2.

---

### Finding 6 — Touching-honors WRITE site (lines 484-507): partner-still-winning gate MISSING

**Severity:** **BUG (medium)** — carry-forward of D-RT-07.

**What was probed:** The touching-honors WRITE site at line 484-507
records seat-side inferences when partner leads Ace and seat plays
T/K/Q/7-9 of same suit. The READER (BotMaster.lua) is gated on
team-trust; the WRITER is symmetric (records observations for any seat).

**Quote (line 484-507):**
```lua
local touchContext = false
if lead.seat == R.Partner(seat)
   and C.Suit(lead.card) == cardSuit
   and C.Rank(lead.card) == "A" then
    touchContext = true
elseif S.s.akaCalled and S.s.akaCalled.seat == R.Partner(seat)
       and S.s.akaCalled.suit == cardSuit then
    touchContext = true
end
if touchContext then
    local entry = style.topTouchSignal[cardSuit] or {}
    if theirRank == "T" then
        entry.nextDown = "K"                       -- rule 1
    elseif theirRank == "K" then
        -- v0.10.0 R6 fix: K-signal = K-singleton, not has-Q.
        entry.cleared = { "Q", "J" }               -- rule 2
    elseif theirRank == "Q" then
        entry.nextDown = "J"                       -- rule 3
    elseif theirRank == "7" or theirRank == "8"
        or theirRank == "9" then
        entry.broke = true                         -- rule 4
    end
    style.topTouchSignal[cardSuit] = entry
end
```

**Why this is wrong:** Per D-RT-07 (and the Saudi convention), the
touching-honors signal is only *intended* when partner is **STILL
winning** the trick at the moment of seat's play — i.e. seat is signaling
"I'm telling you what I have under your boss". When an opp has already
over-trumped or over-played partner's Ace before this seat's play,
the seat is no longer signaling — they're playing a normal must-follow,
and ranks T/K/Q/7-9 carry no convention-meaning.

The current writer captures the lead and AKA contexts but does **not**
check whether partner is still winning at the time of seat's play. So
on the (rare) case where partner led A, opp 2nd-seat over-trumped (in
Hokm, where someone is void in lead suit and ruffs), and seat 3rd is
must-follow with whatever they have — the writer falsely classifies
seat 3's K as "K-singleton" when it's really just must-follow.

**Frequency:** Hokm-side only (Sun has no trump). Requires a void
+ trump on the 2nd seat between partner and us in the order — uncommon
but not vanishing. EV cost: false `entry.cleared = {Q, J}` poisons
the ledger for the rest of the round, biasing later decisions against
suits where partner actually still holds Q or J.

**Recommended fix:** add a `R.CurrentTrickWinner(prevTrick) ==
R.Partner(seat)` check before recording. The bait-ledger WRITE site
at line 523-562 already does this pattern (constructs a `prePlays`
trick from `trickPlays[1..#-1]` and queries `R.CurrentTrickWinner`);
mirror that pattern here.

**Quote (the pattern to mirror, from bait-ledger at line 525-530):**
```lua
local prePlays = {}
for i = 1, #trickPlays - 1 do prePlays[i] = trickPlays[i] end
if #prePlays >= 1 then
    local prevTrick = { plays = prePlays, leadSuit = leadSuit }
    local prevWinner = R.CurrentTrickWinner(prevTrick, contract)
    if prevWinner == R.Partner(seat) then
        -- ... record
    end
end
```

**Confidence:** HIGH on the gap. MEDIUM on EV severity — false-positive
rate depends on opp tier and trick-ordering, but every false write is
a multi-trick poison.

---

### Finding 7 — Bait-ledger WRITE site (lines 510-562) — v0.9.2 #46 forced-J gate present, D-RT-12 still-vulnerable

**Severity:** NIT — D-RT-12 is a known carry-forward.

**What was probed:** v0.9.2 #46 added a "forced-J" gate (suppress
classification when J might have been the only legal card). D-RT-12
flagged that the gate's "lower seen by THIS seat in `mem.played`"
heuristic is too tight — it misses cases where the seat's `mem.played`
doesn't contain a lower-rank but they did hold lowers (e.g. lower
played by a different seat, or lower not played at all).

**Quote (line 523-561):**
```lua
if not wasIllegal and contract and #trickPlays >= 2
   and C.Rank(card) == "J" and style.baitedSuit then
    local prePlays = {}
    for i = 1, #trickPlays - 1 do prePlays[i] = trickPlays[i] end
    if #prePlays >= 1 then
        local prevTrick = { plays = prePlays, leadSuit = leadSuit }
        local prevWinner = R.CurrentTrickWinner(prevTrick, contract)
        if prevWinner == R.Partner(seat) then
            -- v0.9.2 #46 forced-J gate
            local lowerSeen = false
            local plain = K.RANK_PLAIN
            local jr = plain["J"] or 0
            if mem and mem.played then
                for _, low in ipairs({ "7", "8", "9" }) do
                    if mem.played[low .. cardSuit] then
                        lowerSeen = true; break
                    end
                end
            end
            if lowerSeen then
                style.baitedSuit[cardSuit] =
                    (style.baitedSuit[cardSuit] or 0) + 1
            end
        end
    end
end
```

**Verdict:** v0.9.2 #46's gate is **present and correctly checks
`mem.played`** (the seat's own play history). D-RT-12 carry-forward:
the gate over-suppresses (misses some genuine baits) but never
**over-fires** (never falsely flags a forced-J as bait). Conservative
direction is the right side to err on for a partner-suit-avoid
signal — false positive in the bait ledger pollutes pickLead's avoid
pipeline; false negative just leaves a real bait undetected.

**Note:** the partner-still-winning check is **CORRECTLY done here**
(see line 528-530). Compare to Finding 6 above — touching-honors
writer is missing this exact check.

**Confidence:** HIGH on gate-present. MEDIUM on D-RT-12 carry-forward
severity.

---

### Finding 8 — Tahreeb signal recording (v0.5.10 Section 8, lines 564+)

**Severity:** OK.

**What was probed:** When seat plays a non-led-suit card (discard) AND
partner was winning the trick BEFORE this play, record (suit, rank) in
`Bot._partnerStyle[seat].tahreebSent[suit]` for the partner-of-seat to
consume later.

**Quote (line 578-595, partial — gate logic):**
```lua
if not wasIllegal and leadSuit and cardSuit ~= leadSuit
   and contract and style.tahreebSent then
    local plays = trickPlays
    if plays and #plays >= 2 then
        local prior = {}
        for i = 1, #plays - 1 do prior[i] = plays[i] end
        local priorTrick = { plays = prior, leadSuit = leadSuit }
        local prevWinner = R.CurrentTrickWinner(priorTrick, contract)
        if prevWinner and R.Partner(seat) == prevWinner then
            -- Discard while partner is winning = Tahreeb signal.
            local list = style.tahreebSent[cardSuit]
            if list then
                -- ... append (suit, rank) event
            end
        end
    end
end
```

**Verdict:** correct partner-pre-winning gate (mirror of bait-ledger
pattern at line 528-530). The wasIllegal guard prevents poisoning
from illegal plays. Discard-vs-led-suit check (`cardSuit ~= leadSuit`)
correct — only off-suit discards carry Tahreeb meaning, in-suit follows
are constrained by must-follow.

**v0.10.2 M7 length-context capture (per CHANGELOG):** new "محشور بلون
واحد" (cornered in one suit, video #14 rule 2) Bargiya promotion needs
the sender's pre-discard suit-length, captured in the same block — see
B-Bot-05 for the M7 audit detail. Not in scope here.

**Confidence:** HIGH.

---

### Finding 9 — "Don't waste a high card" lowestByRank fallthrough (line 2848)

**Severity:** OK.

**What was probed:** The partner-winning fall-through at line 2847-2848:
`return lowestByRank(legal, contract)`.

**Quote (line 2847-2848):**
```lua
-- Otherwise don't waste a high card.
return lowestByRank(legal, contract)
```

**Verdict:** correct fall-through for partner-winning + neither smother
nor Bargiya nor Want-arm nor T-4 nor Section-4-rule-1B fired. Picks
absolute lowest by trick-rank — the safest "don't waste a high card"
default.

Reachability conditions:
- partnerWinning = true,
- smother failed (no A/T/K/Q/J of led suit, OR `feedSafe = false` for
  trump-led-Hokm),
- Bargiya / Want / T-4 not fired (we're not void in led OR not bot-
  partner OR no qualifying suit),
- Section 4 rule 1B (Sun) not fired (we have <2 in-suit follow OR
  second-lowest would steal).

**Note on signal interaction:** the absolute-lowest play DOES indirectly
preserve the Section-4-rule-1B re-entry signal anyway (see line 2837-
2839 comment). Fall-through is safe.

**Confidence:** HIGH.

---

### Finding 10 — Section 4 rule 1B wouldWin gate (v0.9.5)

**Severity:** OK.

**What was probed:** Sun + partner-winning + we must follow + can't
beat lead + smother didn't fire. Default would be `lowestByRank` — but
v0.7.2 introduced "play SECOND-LOWEST" as a re-entry signal. v0.9.5
added a `wouldWin` gate to prevent the second-lowest from STEALING
partner's trick.

**Quote (line 2814-2845):**
```lua
if contract.type == K.BID_SUN and trick.leadSuit then
    local follow = {}
    for _, c in ipairs(legal) do
        if C.Suit(c) == trick.leadSuit then
            follow[#follow + 1] = c
        end
    end
    if #follow >= 2 then
        local sorted = {}
        for _, c in ipairs(follow) do sorted[#sorted + 1] = c end
        table.sort(sorted, function(a, b)
            return C.TrickRank(a, contract) < C.TrickRank(b, contract)
        end)
        -- v0.9.5 wouldWin gate: only return second-lowest if it does
        -- NOT win the trick (partner stays the winner).
        if not wouldWin(sorted[2], trick, contract, seat) then
            return sorted[2]   -- second-lowest = re-entry signal
        end
    end
end
```

**Verdict:** the `wouldWin(sorted[2], trick, contract, seat)` check
correctly prevents the steal. Example from comment: partner leads JH,
we hold {7H, KH}, sorted[2] = KH which beats JH and would steal — the
gate suppresses, fall-through to lowestByRank emits 7H.

The sub-comment ("the 'biggest mistake' rule's mitigation is moot if
our lowest IS the absolute lowest of a 2-card holding anyway") is
accurate: in a 2-card follow, both cards are equally "lowest"; the
distinction only matters with ≥3-card follows (which the `>= 2`
predicate admits but the natural 2-card case degenerates).

**Confidence:** HIGH.

---

### Finding 11 — Tahreeb sender T-1 / Want-arm / T-4 ordering and rank floors

**Severity:** OK — verified 3-arm sender ordering and rank floors.

**What was probed:** Three signals fire in sequence within the
Tahreeb sender block (lines 2697-2796):
1. T-1 Bargiya (Sun only): A-of-side-suit with cover → discard A.
2. Want-arm (v0.9.0): A or T of side-suit with ≥3 cards → lowest
   non-winner.
3. T-4 Dump-ordering: 2-card suit, dump LARGER first (capped at Q).

**Quote (T-1 Bargiya, line 2710-2723):**
```lua
if contract.type == K.BID_SUN then
    for _, su in ipairs({ "S", "H", "D", "C" }) do
        local cards = bySuit[su]
        if #cards >= 2 then
            for _, c in ipairs(cards) do
                if C.Rank(c) == "A" then
                    return c   -- Bargiya
                end
            end
        end
    end
end
```

**Quote (Want-arm, line 2738-2760):**
```lua
for _, su in ipairs({ "S", "H", "D", "C" }) do
    local cards = bySuit[su]
    if #cards >= 3 then
        local hasWinner = false
        for _, c in ipairs(cards) do
            if C.Rank(c) == "A" or C.Rank(c) == "T" then
                hasWinner = true; break
            end
        end
        if hasWinner then
            local lows = {}
            for _, c in ipairs(cards) do
                if C.Rank(c) ~= "A" and C.Rank(c) ~= "T" then
                    lows[#lows + 1] = c
                end
            end
            if #lows > 0 then
                return lowestByRank(lows, contract)
            end
        end
    end
end
```

**Quote (T-4 with v0.5.11 rank floor, line 2779-2795):**
```lua
for _, su in ipairs({ "S", "H", "D", "C" }) do
    local cards = bySuit[su]
    if #cards == 2 then
        local lo, hi = cards[1], cards[2]
        if C.TrickRank(lo, contract) > C.TrickRank(hi, contract) then
            lo, hi = hi, lo
        end
        local hiRank = C.Rank(hi)
        if hiRank ~= "K" and hiRank ~= "T" and hiRank ~= "A" then
            return hi
        end
        -- High-value doubleton: skip Tahreeb encoding,
        -- preserve the card. Continue searching other suits.
    end
end
```

**Verdict:**
- **T-1 Bargiya is Sun-only** (Hokm Bargiya doesn't appear in source).
  Correct.
- **Want-arm fires BEFORE T-4** (per the v0.9.0 comment "Fires BEFORE
  T-4 so want suits win over doubleton dump"). Verified ordering at
  lines 2738 vs 2779.
- **T-4 rank floor at line 2789**: `hiRank ~= "K" and hiRank ~= "T"
  and hiRank ~= "A"` — caps the larger card at Q. Source-correct per
  v0.5.11 audit (low-rank doubletons only).
- **Both arms guard `bySuit[su]` excludes trump in Hokm** (line 2701-
  2707), so Tahreeb encoding never fires through trump discards.
- **All 3 arms tier-gated** at line 2697: `Bot.IsM3lm() and voidInLed
  and Bot.IsBotSeat(R.Partner(seat))`. Bot-partner-only suppresses
  human-noise; void-in-led ensures we have a free choice of suit.

**Note (T-4 over-fire prevention):** the rank floor explicitly
preserves K/T/A doubletons — a sensible EV trade since burning a
high-value card for a 1-trick Tahreeb signal is net-negative.

**Confidence:** HIGH.

---

## Cross-prompt-item summary

| Prompt item | Mapped finding | Severity |
|---|---|---|
| 1. Hokm Faranka exception block (2740-2900) | Finding 1 | OK (carry-forward B-Bot-02) |
| 2. v0.10.0 X3 fixes (#3 bidder-team, #4 relax, F-16) | Finding 1 + Finding 2 | OK + **EV-LEAK on F-30b** |
| 3. **D-RT-03 S-1: F-16 over-fires on F-30b** | **Finding 2** | **EV-LEAK / BUG** |
| 4. AKA-receiver branch | Finding 3 | OK (LIVE post-M4) |
| 5. v0.10.2 M4 R.IsLegalPlay AKA passthrough | Finding 4 | OK |
| 6. Sun pos-4 Faranka (Section 5) | Finding 5 | OK |
| 7. Touching-honors WRITE site (484-507) | **Finding 6** | **BUG (D-RT-07 carry)** |
| 8. Bait-ledger trigger (502-545) | Finding 7 | NIT (D-RT-12 carry) |
| 9. Tahreeb signal recording (Section 8) | Finding 8 | OK |
| 10. "Don't waste a high card" lowestByRank | Finding 9 | OK |
| 11. Section 4 rule 1B wouldWin gate | Finding 10 | OK |
| (bonus) Tahreeb sender ordering | Finding 11 | OK |

---

## Recommendations — ship priority

1. **Finding 2 (F-16 over-fires F-30b)** — single-line fix. **Ship in
   v0.10.3.**
2. **Finding 6 (touching-honors partner-still-winning gate)** —
   pattern-mirror from bait-ledger writer. **Ship in v0.10.3.**
3. **B-Bot-03 F2 (AKA-on-T trick lock)** — out of scope for this
   audit, but the `Rules.lua:108-110` comment is misleading; consider
   documentation fix.
4. **Carry-forward** D-RT-12 (bait-ledger gate over-suppression),
   D-RT-03 S-2..S-5 (NIT-class items), B-Bot-02 F9 (Saudi Master tier
   delegation gap — pickFollow heuristics never run under ISMCTS).

---

## Confidence summary

- **HIGH** for Findings 1, 3, 4, 5, 7, 8, 9, 10, 11 — all probed
  end-to-end against v0.10.2 source; cross-checked against
  B-Bot-02 / B-Bot-03 / D-RT-03 audits.
- **HIGH** for Finding 2 (D-RT-03 S-1) — Source C F-16 reasoning +
  F-30b predicate are both unambiguous; D-RT-03 verified the
  reproduction steps.
- **HIGH** for Finding 6 — direct comparison to the partner-winning
  pattern at the adjacent bait-ledger and Tahreeb writers; the
  touching-honors writer is the lone exception in the same WRITE
  region that does NOT consult `R.CurrentTrickWinner`.
