# B-Bot-08 — `pickLead` deep audit (v0.10.2)

Track-B comprehensive audit of `pickLead` (`Bot.lua:1703-2461`). This audit
extends and consolidates B-Bot-04 (M8 mardoofa probe scope), D-RT-10
(M8 bidder-perspective red-team), and D-RT-24 (M8 opp-perspective
red-team) and adds 12 distinct audit dimensions across the entire
function.

Files inspected (read-only):
- `C:\CLAUDE\WHEREDNGN\Bot.lua` lines 40-90 (tier gates), 510-660 (`OnPlayObserved` recorders), 662-705 (`opponentsVoidInAll`/`anyOpponentVoidIn`), 1520-1700 (`lowestByRank`/`highestByRank`/`highestByFaceValue`/`tahreebClassify`), 1703-2461 (`pickLead`), 2484+ (`pickFollow` for cross-reference)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-Bot-04_pickLead_m8.md` (M8 scope review)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-10_m8_mardoofa_probe.md` (bidder-perspective)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-24_mardoofa_leak.md` (opp-perspective)
- `C:\CLAUDE\WHEREDNGN\docs\strategy\signals.md` lines 173-200 (Bargiya phase-split source)
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\14_bargiya_ace_tahreeb_extracted.md` lines 26-29, 120-123 (video #14 source)
- `C:\CLAUDE\WHEREDNGN\docs\strategy\decision-trees.md` (Section 8 / Section 11 cross-references)

---

## Branch order in `pickLead` (line numbers)

| # | Lines | Branch | Tier | Contract gate |
|---|---|---|---|---|
| 1 | 1736-1788 | Trick-8 / sweep-pursuit boss-lead | (any) | Hokm distinguishes via `trumpExhausted` |
| 2 | 1806-1823 | **M8 Sun bidder-team mardoofa probe** | Advanced+ | Sun |
| 3 | 1829-1838 | Hokm "highest-unplayed in non-trump" | Advanced+ | Hokm |
| 4 | 1855-1944 | Tahreeb partner-pref / opp-avoid | M3lm+ | (any non-trump) |
| 5 | 1946-1973 | Fzloky partner-pref | Fzloky+ | (any) |
| 6 | 1975-2003 | B-97 opp-meld-suit avoid | M3lm+ | (any) |
| 7 | 2005-2028 | B-82 bait-detected suit avoid | M3lm+ | (any non-trump) |
| 8 | 2029-2042 | Fzloky pref-suit lead-low | Fzloky+ | (any) |
| 9 | 2054-2215 | Bidder-only Hokm trump-pull (with B-96 Ace-exhaust, B-57/71 conservativeOpp, B-98 J9-lock, H-6 Ace-of-trump preserve) | mixed Advanced/M3lm | Hokm |
| 10 | 2284-2295 | B-82 trump-drought defender lead-high-point | M3lm+ | Hokm (defender) |
| 11 | 2298-2312 | Free-trick suit (opps void in all) | Advanced+ | (any) |
| 12 | 2314-2334 | B-77 single-opp-void boss-lead | Advanced+ | Hokm |
| 13 | 2336-2369 | Singleton-low (rank-guarded in Hokm only) | (any) | (any) |
| 14 | 2371-2400 | Sun shortest-suit-low | (any) | Sun |
| 15 | 2402-2441 | Low-from-longest non-trump (with Fzloky avoid) | (any) | (any) |
| 16 | 2443-2459 | saveHighTrump lowest-non-J9 trump | M3lm+ | Hokm |
| 17 | 2460 | Lowest legal (ultimate fallback) | (any) | (any) |

---

## Findings

### F1 — `bidderTeam` is undefined in `pickLead` (BUG, pre-existing)

**Severity: HIGH (Hokm bidder branch).**

Line 2130:
```lua
if R.TeamOf(s2) ~= bidderTeam
   and styleTrumpTempo(s2) == -1 then
```

`bidderTeam` is **not defined anywhere in `pickLead`**. Verified via `Grep "bidderTeam"` on `Bot.lua`:
- Line 1154: defined inside `partnerEscalatedBonus` (different function).
- Line 1155: same, in `partnerEscalatedBonus`.
- Line 1156: same.
- **Line 2130: read inside `pickLead` — undefined identifier.**

Inside `pickLead`, `bidderTeam` evaluates to `nil` (Lua doesn't error on undefined globals — they read as `nil`). So `R.TeamOf(s2) ~= nil` is **always true**. The intended gate "skip own-team seats" never fires. Effect: ALL four seats are checked for `styleTrumpTempo(s2) == -1`, including the bidder's own team. If the bidder's own partner was previously observed conservative (rare but possible), the branch erroneously enters the "cash side-suit Aces" deviation when no opp is actually conservative.

This is contained inside the `if isBidderTeam and isBidder` block (line 2054), so only the Hokm bidder is affected. But the bidder is the most strategically critical seat, and the misfiring is silent.

**Repro:** Hokm contract, bidder = seat 2, seat 4 (bidder's partner) has accumulated `styleTrumpTempo == -1` from prior rounds (4 played K-then-7 of trump in some round). Bidder seat 2 leads on trick 1 (or any later non-pulling trick). Line 2130 sees `R.TeamOf(4) ~= nil` (true) AND `styleTrumpTempo(4) == -1` (true) → `conservativeOpp = true` → bidder dives to side-suit Ace cash instead of trump-pull. Mistakenly reads partner's tempo as opp tempo.

**Code quote (line 2126-2143):**
```lua
if Bot.IsM3lm() and contract.type == K.BID_HOKM
   and contract.trump and contract.bidder then
    local conservativeOpp = false
    for s2 = 1, 4 do
        if R.TeamOf(s2) ~= bidderTeam      -- BUG: bidderTeam is nil here
           and styleTrumpTempo(s2) == -1 then
            conservativeOpp = true
            break
        end
    end
    ...
```

**Fix:** add `local bidderTeam = R.TeamOf(contract.bidder)` at the top of `pickLead` (matching what `partnerEscalatedBonus` does at line 1154).

Already flagged in B-Bot-04 as adj-2 (informational). **Promoted to a real bug here** — the predicate misfires deterministically when a same-team seat is conservative.

---

### F2 — M8 Sun mardoofa probe — see B-Bot-04, D-RT-10, D-RT-24

The M8 branch (lines 1806-1823) was reviewed exhaustively in three sister docs. Summary of inherited findings (no re-derivation):

| Finding | Severity | Source |
|---|---|---|
| M8 trigger conditions (Advanced+, Sun, trick 1, bidder-team leader, A+T pair) all correct | OK | B-Bot-04 F1-F8 |
| Multi-mardoofa hardcoded `{S,H,D,C}` iteration order (no Pro-2 source) | Low (test/strategy) | B-Bot-04 M8-i1; D-RT-24 r4 |
| No partner-of-bidder leader test pin | Low (test) | B-Bot-04 M8-i2 |
| Single-source rule (Pro-2 PDF §2 only) | Source-trail | B-Bot-04 M8-i4 |
| **Cross-suit elimination via `{S,H,D,C}` order**: A♣-led leaks 4 facts, A♠-led leaks 1 | Low-Medium | D-RT-24 r4 |
| **Asymmetric exploit**: M8 leaks vs human opp; bot opp doesn't read `_memory.suspectedMardoofa` (no such field) | Medium | D-RT-24 r2 |
| **Probe wasted on bot partner**: no `pickFollow` mardoofa-aware "preserve T" branch | High (strategy) | D-RT-24 r6 |
| `bidderTeam` is correctly inlined in M8 itself via `myTeam == R.TeamOf(contract.bidder)` (sidesteps F1's bug) | OK | B-Bot-04 F2 |

No new M8 findings beyond those papers.

---

### F3 — Trick-1 strategic lead: A or non-A?

**Severity: Medium-High (strategy).**

Outside the M8 branch, what does `pickLead` do on trick 1?

**Sun bidder-team without mardoofa** (M8 falls through):
- Branch 4 (Tahreeb pref): cannot fire on trick 1 (signals are recorded mid-round; trick 1 leader has no prior partner discard to read). Fzloky same.
- Branch 6-7 (B-97/B-82): can read prior-round style ledger if ≥1 opp had a sequence meld in prior round. Most trick-1 leads from a fresh round will not have these set.
- Branch 11 (free-trick): cannot fire on trick 1 (no `void` populated yet for a fresh round — `Bot.ResetMemory()` clears `_memory`).
- Branch 13 (singleton-low): Sun has no rank-guard → singleton-A returns A. **In Sun, leading a singleton-A on trick 1 is a near-mandatory "good" play** (T cover may be in partner; it is the only single-card winner and getting it out before the 7th card is drawn down is the right play). However, this is also the source of the D-RT-24 r7 confound.
- Branch 14 (Sun shortest-suit-low): defender + non-mardoofa-bidder fall through here. `lowestByRank` of e.g. `{AS, KS}` returns `KS` (A is high in Sun); good — preserves A.
- Branch 15 (low-from-longest): final fallback for defenders.

**Hokm bidder team on trick 1:**
- Branch 3 (highest-unplayed-non-trump) fires for ANY card that's currently the boss in its non-trump suit. **This means a bidder holding A♠ on trick 1 leads it** (as long as A♠ has not been played, which is trivially true on trick 1 in a fresh round and `S.HighestUnplayedRank("S")` returns `"A"`). This is **arguably wrong as a bidder**: bidder typically wants to pull trump first, not cash a side-suit Ace before opps' trump is depleted (then their Ace gets ruffed when led mid-round).
- The branch is gated to `Bot.IsAdvanced() and contract.type == K.BID_HOKM` — fires for ALL Hokm seats, NOT just defenders. The header comment at line 1825 calls it "Advanced (Tier 3 #11): if we hold a card that's currently the HIGHEST UNPLAYED in its non-trump suit, leading that card is a guaranteed trick." It is "guaranteed" only if all opps are void in the suit OR have already played their trump down — neither true on trick 1.
- **A Hokm bidder following this logic on trick 1 leads their non-trump A** instead of pulling trump. Subsequently the bidder block at line 2054+ never gets a chance to run the trump-pull logic. The bidder block contains the v0.5.1 H-6 A-of-trump preserve guard, the B-96 ace-exhaustion deviation, the B-57/71 conservativeOpp side-suit cash, the B-98 J/9-lock cash, and the trump-pull itself — ALL bypassed if Branch 3 fires.

**Why is this strategically suspect?** In Hokm, cashing a side-suit A on trick 1 is fine if opps are out of trump or short on trump. Neither is established by trick 1. Standard pro convention: bidder pulls trump first 2-3 tricks to deplete opp ruff threats, THEN cashes side-suit winners. Branch 3 short-circuits this.

**Code quote (line 1829-1838):**
```lua
if Bot.IsAdvanced() and contract.type == K.BID_HOKM
   and S.HighestUnplayedRank then
    for _, c in ipairs(legal) do
        local r = C.Rank(c)
        local su = C.Suit(c)
        if su ~= contract.trump and S.HighestUnplayedRank(su) == r then
            return c
        end
    end
end
```

**Repro:** Hokm contract, trump = ♠, bidder = seat 2, seat 2 holds `{AS, KS, AC, JD, JS, QD, KD, 9C}` (or similar with A♣ being a side-suit Ace; trick 1, `_memory` populated only with bid-card pin). Branch 3 iterates: A♣ is a non-trump card that is the boss of clubs. Returns A♣. **No trump pull, no Ace-of-trump preservation, no B-96/B-98/B-57 logic runs.**

This is a **pre-existing v0.5 bug** rather than M8-specific, but it interacts with M8 territorially: M8 fires for Sun bidder team (line 1806), Branch 3 fires for ALL Hokm Advanced+ on trick 1. The two branches together imply: "Sun bidder team leads mardoofa-Ace; Hokm bidder team leads boss non-trump-Ace." The Hokm version contradicts standard pulling-trump convention.

**Recommendation:** Branch 3 needs a contract gate or trickNum gate. Either:
- "Only fire on trick 4+" (after typical trump-pull is done), OR
- "Skip if isBidder and ≥2 trump remain in opp pool (i.e. trump-pull still useful)".

Out of M8 scope but found during this audit. **Severity: Medium-High strategic.**

---

### F4 — Tahreeb-detection-driven avoid (Section 8 / N-3): single-side conflict resolution gap

**Severity: Low (logical correctness).**

Lines 1855-1929 implement Section 8 (Tahreeb partner pref) and Section 9 N-3 (opp avoid). The conflict resolution at line 1926-1928:

```lua
if tahreebPrefSuit and tahreebAvoidSet[tahreebPrefSuit] then
    tahreebPrefSuit = nil
end
```

This handles the case where partner's Tahreeb-want suit X is also in opp's avoid set. But there's an **ordering subtlety**: the partner pref scan at lines 1862-1893 sets `tahreebAvoidSet[su] = true` when partner classifies as `dontwant` (line 1886). Then the opp scan at lines 1906-1922 ADDs to the same `tahreebAvoidSet`. At line 1926 we read this combined set.

**Edge case**: if partner signals BOTH a `want` in suit X AND a `dontwant` in suit Y, `tahreebPrefSuit = X` and `tahreebAvoidSet[Y] = true`. Then opp signals `want` in suit X — `tahreebAvoidSet[X] = true` (line 1916). Conflict resolution drops `tahreebPrefSuit`. **Correct so far.**

But: if partner signals `dontwant` in X AND `want` in Y, `tahreebAvoidSet[X] = true` (from partner's dontwant) AND `tahreebPrefSuit = Y`. Opp signals `dontwant` in Y → `tahreebAvoidSet[Y]` is **NOT** set (opp's `dontwant` is filtered out at line 1914 — only `bargiya/want/bargiya_hint` from opps trigger avoid).

The Track-B comment at line 1846 explicitly notes "Opp negative (dontwant) → ignored (low value)." That's a deliberate design choice. But it means: if partner says "want Y" and opp says "dontwant Y" (meaning opp has revealed they DON'T want Y led — which to us is INFORMATION that Y is good for us), we still get `tahreebPrefSuit = Y` and lead Y. This is correct: opp's dontwant is a tempo signal to their own partner, not to us. Good.

**Conclusion:** logic is sound, but the comment at 1844-1846 understates: opp `dontwant` is **doubly ignored** — it's not consumed as avoid AND it's not even consumed as a confirmation signal that the suit is safe for us. There may be additional EV in flipping opp's `dontwant` to a partner-of-opp's `want` proxy (since Saudi Tahreeb is partner-directed, opp's dontwant tells us their partner shouldn't lead it). Out of scope for now but flagged as a missing read.

**No code bug. Severity: Low strategic gap.**

---

### F5 — Bargiya-receiver phase-split NOT implemented

**Severity: Medium-High (strategy gap).**

The strategy docs reference a "receiver phase-split" rule from video #14 that is **documented but not implemented**:

`docs/strategy/glossary.md:226`:
> **Bargiya receiver phase-split** | Endgame (≤4 cards in your hand): lead the Bargiya'd suit immediately. Opening (≥5 cards): burn 1-2 of your own tricks first to set up the eventual lead-back. (Per video #14.)

`docs/strategy/_transcripts/14_bargiya_ace_tahreeb_extracted.md:120-123` (verbatim):
> - Endgame (≤ 4 cards each): lead the Bargiya'd suit on next turn, immediately, without analysis.
> - Opening (≥ 5 cards each): capture one (max two) of your own tricks first to establish position, then lead the Bargiya'd suit. Sender may not hold سوا at depth.
> - No capturing tricks at all: lead Bargiya'd suit immediately, regardless of phase.

Looking at `pickLead` Branch 4 (lines 1855-1944):
- The `tahreebClassify` returning `"bargiya"` or `"bargiya_hint"` triggers `tahreebPrefSuit` (lines 1879-1885).
- When `tahreebPrefSuit` is set, the code at lines 1930-1944 immediately leads low from the pref-suit. **NO phase-check.**

**No code path** in `pickLead` implements:
1. "If hand size ≥ 5, capture 1-2 own tricks first instead of leading the Bargiya'd suit." There's no "delay 1-2 tricks" logic anywhere.
2. "If hand size ≤ 4, lead immediately." This is the default behavior, but it's not gated; it fires for ALL hand sizes.

**Effect:** when partner Bargiya's a suit at trick 1 (rare but happens after an Ace tahreeb on trick 0... wait — no, trick 1 IS the first trick; Bargiya can only fire from trick 2 onwards because the Ace discard requires a prior trick to be in progress with partner winning). So in practice: Bargiya is typically observed at trick 2-3 (hand size 6-7). The phase-split rule says: at hand size 6-7, **delay 1-2 tricks** before leading the Bargiya'd suit. The code does NOT delay — it leads the Bargiya'd suit immediately.

**Repro:**
- Round R, trick 2, partner discarded A♥ on trick 1 while we were winning. `Bot._partnerStyle[partner].tahreebSent["H"] = {"A"}` (length 1, classified as `bargiya_hint` unless `lenAtAce >= 5`).
- M3lm+ bot is on lead at trick 2 (hand size 7). `tahreebClassify` returns `bargiya_hint` → score 1 → `tahreebPrefSuit = "H"` → lead our lowest ♥.
- Per video #14 rule 9, we should have first captured a non-♥ trick of our own (we're at hand size 7, "opening"), THEN led ♥ on trick 3. Instead we led ♥ immediately.

**Cost:** if sender's Bargiya was a defensive shed (not a true invite — distinguished by `lenAtAce` heuristic which closes some cases but not all), our immediate lead-back wastes our tempo. If the sender genuinely had cover, the small delay would have given our partner one more capturing trick before the lead-back. Either way the rule says delay; the code does not.

**Fix:** at the top of the `tahreebPrefSuit` branch (line 1930), check hand size:
```lua
if tahreebPrefSuit and #legal >= 5 and <hasOwnCapturingTrick> then
    -- Skip the immediate lead-back; fall through to next logic
    tahreebPrefSuit = nil
end
```
The "<hasOwnCapturingTrick>" check is fuzzy — it requires evaluating "do I hold a card that is currently the boss in some non-Bargiya suit". This is a real implementation cost, but the source rule is well-attested in video #14.

**Severity: Medium-High (real strategy rule, real EV cost; documented but not implemented).**

This finding may be **out of M8 scope** but is a genuine `pickLead` gap surfaced by the deep audit.

---

### F6 — Fzloky firstDiscard avoid pipeline (lines 2402-2425): logic correct, but interaction subtle

**Severity: Low (correctness verified; stylistic comment).**

Lines 2402-2441 implement low-from-longest with Fzloky avoid:

```lua
local longest, longestN = nil, 0
for _, suit in ipairs({ "S", "H", "D", "C" }) do
    local n = suitCount[suit] or 0
    if suit ~= fzlokyAvoidSuit and n > longestN then
        longest, longestN = suit, n
    end
end
if fzlokyAvoidSuit then
    local avoidN = suitCount[fzlokyAvoidSuit] or 0
    if avoidN >= longestN + 2 then
        longest, longestN = fzlokyAvoidSuit, avoidN
    end
end
```

The comment at 2406-2412 explains the two-pass + tolerance design correctly. Verification:

- **Pass 1**: scan `{S,H,D,C}`, take longest non-avoid suit.
- **Tolerance check**: if avoid suit is ≥2 cards longer than longest non-avoid, switch to avoid.
- **Fallback**: if no `longest` found (all non-trumps are in avoid suit), pass 2 takes longest unconditionally.

**Edge case 1**: what if `fzlokyAvoidSuit` is the trump? Trump cards are excluded from `nonTrumps` already (line 2271-2278), so `suitCount[trump]` = 0 (the count is built only from non-trumps via `nonTrumps[#nonTrumps+1]` at line 2275 with the `not C.IsTrump` gate). Setting `fzlokyAvoidSuit = trump` would be a no-op since the count is 0. Verified safe.

**Edge case 2**: tied lengths. If two non-avoid suits are tied at the longest non-avoid count, the iteration order `{S,H,D,C}` returns Spades first (`n > longestN` strict greater). Deterministic but unsourced — same `{S,H,D,C}` arbitrary tiebreaker as M8. Worth a one-line comment but not a bug.

**Edge case 3**: `fzlokyAvoidSuit` source. Looking up:
- Line 1968-1969: Fzloky-receiver firstDiscard `r in {7,8}` → `fzlokyAvoidSuit = sig.suit`.
- Line 1997-1998: B-97 opp-meld-suit avoid → `fzlokyAvoidSuit = m.suit` (only if not already set).
- Line 2018-2020: B-82 baited-suit avoid → `fzlokyAvoidSuit = suit` (only if not already set).

**Layered-avoid order**: Fzloky wins (set first); B-97 only fires `if not fzlokyAvoidSuit`; B-82 same. The chain is well-commented at lines 1995-1999 ("if both apply ... Fzloky wins"). Correct.

**Potential issue**: only ONE `fzlokyAvoidSuit` slot. If three different signals all point at three different suits to avoid, we can only honor the first. Multiple-avoid is not supported. The Section 11 rule 8 baitedSuit avoidance overrides nothing else but is itself overridden by the earlier two. Functional but limited.

**Recommendation:** consider a `fzlokyAvoidSet = {}` table (similar to `tahreebAvoidSet`) to layer multiple signals. Out of scope for the audit; flagging as a minor architectural smell.

**Severity: Low.**

---

### F7 — v0.8.2 baitedSuit avoid — D-RT-12 forced-J gate: correctly implemented

**Severity: OK (verified).**

The audit prompt asks about "D-RT-12 forced-J gate still-vulnerable." Looking at the relevant code:

`Bot.lua:531-562` — `OnPlayObserved` baitedSuit recorder:
```lua
if not wasIllegal and contract and #trickPlays >= 2
   and C.Rank(card) == "J" and style.baitedSuit then
    ...
    if prevWinner == R.Partner(seat) then
        -- v0.9.2 #46 forced-J gate
        local lowerSeen = false
        ...
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
```

The forced-J gate (v0.9.2 #46) checks: did THIS seat (`mem.played` is keyed to the seat playing the J) previously play a 7/8/9 of the same suit? If yes, they HAD lowers and chose J anyway → genuine bait. If no, J might have been forced (their only card in suit).

**Approximation weakness:** `mem.played` is the **seat's own played pile**. If the seat played J on trick 3 with no prior 7/8/9 of that suit in their own played pile, the gate suppresses (treats as forced). But the seat might have played a NON-suit card on trick 1 (off-suit discard) and held a 7♠ in hand WITHOUT playing it yet. The gate can't distinguish "had no lower" from "had lower but hasn't played it yet" because `mem.played` only records what's been played.

**Repro for a false-negative** (D-RT-12 territory):
- Trick 1: seat 3 (opp) leads ♠. Seat 4 (opp's partner) plays 7♠. We win.
- Trick 2: seat 4 leads ♠ again. Seat 3 (their partner) holds J♠ + 8♠. Seat 3 plays J♠. Their partner (seat 4) was previously winning (led the trick).
- Wait — in trick 2, seat 4 is the leader. The "winner before this play" check at line 530 for seat 3's J♠ play: prior plays in trick 2 = `[{seat=4, card=...}]`. Prior winner = seat 4 = partner of seat 3. Bait check fires. `mem.played` for seat 3 contains... seat 3's prior plays. From trick 1, seat 3 led; what did they play? Suppose seat 3 led K♠ on trick 1 (some scenario). Then `mem.played["K"+cardSuit]` is set, but no 7/8/9 of cardSuit. `lowerSeen = false` → bait suppressed. **Correct** — there's no proof seat 3 had lowers.

But: seat 3 may STILL have an 8♠ in hand. Future bait detection: if seat 3 plays 8♠ on trick 4, the trick-2 J♠ in retrospect was bait. The current gate has no retroactive promotion. This is a known approximation.

**Severity: OK** — the gate is a deliberate approximation; D-RT-12 covers it. No new bug here.

**One small concern**: line 549-553's loop uses `ipairs({"7","8","9"})` and `mem.played[low .. cardSuit]`. The card encoding is `"<rank><suit>"` — verified by `C.Suit("7S")` returning `"S"` per `C.Rank("7S")` returning `"7"`. Format consistent. No bug.

---

### F8 — v0.7.1 B-97 opp-meld suit avoidance (lines 1975-2003): correct

**Severity: OK (verified).**

```lua
if Bot.IsM3lm() and not isBidderTeam and S.s.meldsByTeam then
    local oppTeam = (R.TeamOf(seat) == "A") and "B" or "A"
    for _, m in ipairs(S.s.meldsByTeam[oppTeam] or {}) do
        if m.kind and m.kind:sub(1, 3) == "seq" and m.suit
           and m.suit ~= (contract.trump or "") then
            if not fzlokyAvoidSuit then
                fzlokyAvoidSuit = m.suit
            end
            break
        end
    end
end
```

- Tier-gated to M3lm+: correct (relies on meld observations).
- `not isBidderTeam` gate: defender-only. Comment at line 1981-1982 says "fires for non-bidder defender leads ... we're picking lead = we won the prior trick = temporarily controlling the table." Note: `isBidderTeam` is correctly defined at line 1705 for `K.BID_HOKM`. **For Sun, `isBidderTeam` is FALSE for all seats** (the typo discussed in B-Bot-04 F2). This means the B-97 gate `not isBidderTeam` fires for ALL Sun seats, including the Sun bidder team.
- **Effect on Sun**: Sun bidder-team seat picks lead → B-97 considers opps' melds → potentially sets `fzlokyAvoidSuit` to opp meld suit. This may actually be DESIRABLE (avoiding opp's meld suit is good defense for any team), but it's NOT what the comment says. The comment claims "non-bidder defender leads," which for Sun is incorrect because the gate doesn't distinguish Sun bidder vs Sun defender.

**Severity: OK functionally** (the avoidance is good defense regardless of team), **Doc: misleading** (comment claims defender-only, code applies to all Sun seats).

**Recommendation:** if intent is genuinely "defender-only", inline the team check: `not (myTeam == R.TeamOf(contract.bidder))` (mirroring M8). If intent is "any team avoiding opp meld", update the comment.

---

### F9 — Singleton-A handling (line 2348-2369): D-RT-24 r7 confound is real

**Severity: OK (intentional; flagged for awareness).**

Lines 2348-2369:
```lua
local singletons = {}
for _, c in ipairs(nonTrumps) do
    if suitCount[C.Suit(c)] == 1 then singletons[#singletons + 1] = c end
end
if #singletons > 0 then
    local ledger = singletons
    if contract.type == K.BID_HOKM then
        local lowSingletons = {}
        for _, c in ipairs(singletons) do
            local r = C.Rank(c)
            if r == "7" or r == "8" or r == "9" then
                lowSingletons[#lowSingletons + 1] = c
            end
        end
        ledger = lowSingletons
    end
    if #ledger > 0 then
        return lowestByRank(ledger, contract)
    end
    -- Fall through: all singletons are honors in Hokm — preserve them
end
```

**Hokm**: rank-guards to 7/8/9; honor singletons (A/T/K/Q/J) fall through. v0.6.0 H-3 fix.

**Sun**: NO rank guard. A singleton-A is returned by `lowestByRank` (which returns AS for `{AS}` — only one card, no choice). This means Sun singleton-A is led on trick 1 (or any trick, if M8 didn't fire and we got here).

**D-RT-24 r7 says** this creates a confound for opp inference: "A♠ led" by bidder team can mean either (a) M8 mardoofa, or (b) singleton-A♠. Probabilistically dominated by (a) due to priors but the confound dilutes leak from ~95% to ~85-90%.

**Strategically correct in Sun**: a singleton-A in Sun MUST be led when on lead (otherwise it's discarded later under follow-suit pressure into an opp's lead, with NO control over when). This is the right play.

**Severity: OK** — Sun no rank-guard is correct; documented in code comment at 2342-2343 ("In Sun, A/T are sure stoppers").

**Side observation:** the same line 2364 does `return lowestByRank(ledger, contract)` — note that for Sun, `lowestByRank` of multiple singletons returns the lowest-ranked one. So if a Sun seat has two singletons (e.g. K♠ and 7♣), it returns 7♣ first. **Good** — preserves the honor singleton for later.

---

### F10 — Section 11 rule 8 / rule 1 (deceptive overplay sender): SENDER side not implemented

**Severity: Medium (strategy gap; receiver side correct).**

The B-Bot-08 prompt asks about Section 11 rule 8 / rule 1 in the **deceptive overplay sender** sense. Decoding:

- **Receiver side** (i.e. our bot reads opp's J-overplay as bait avoidance): IMPLEMENTED at line 2005-2028 (B-82 baited-suit avoidance with v0.9.2 forced-J gate). See F7 above.
- **Sender side** (i.e. our bot deliberately plays J of suit X with our partner already winning, to bait opps to re-lead X assuming we're void below J): **NOT implemented anywhere** in `pickLead` or `pickFollow`.

Looking at the comment at lines 519-522:
> Sources: decision-trees.md Section 11 rule 8 (Sometimes, 08); Section 4 rules 4-5 (deceptiveOverplay sender, deferred).

The phrase **"deferred"** confirms sender-side deception is intentionally not implemented yet.

**Why is sender side missing?** The decision is M3lm-tier and requires:
1. Our partner is currently winning the trick (mid-trick state, requires position-aware play).
2. We hold J of led suit (or trump) with lower cards available.
3. We deliberately play J instead of low to bait.

This is a **`pickFollow` decision**, not `pickLead`. So technically out of `pickLead` scope, but the receiver-side baited-suit avoid pipeline at lines 2005-2028 sits in `pickLead` and IS active. The audit prompt asks about "Section 11 rule 8 / rule 1 (deceptive overplay sender)" — the answer is **"deferred / not implemented; receiver-side avoidance only".**

**Severity: Medium strategic gap** (deferred per code comment, not a bug).

**Repro** (illustrative, showing the sender-side absence): Trick 4, partner has just won with K♠. Seat (us) hold `{J♠, 7♠, ...}`. `pickFollow` is called. The follow logic plays our lowest legal — 7♠. Section 4 rule 4-5 sender-deception would say "play J♠ instead to bait opps." Code does not. **Confirmed absent.**

---

### F11 — Last-trick lead (trick 8 specifics, lines 1736-1788): correct, but `safeBosses` interaction with M8 / Sun

**Severity: OK.**

The trick-8 / sweep-pursuit branch (lines 1736-1788) is the FIRST branch reached from `pickLead`'s top. It fires for `trickNum == 8` OR `sweepPursuitEarly` (trickNum 3-7 + bidder team won every prior trick + isBidderTeam).

For trick 8:
- Scans `safeBosses` (cards that are currently HighestUnplayedRank in their suit AND safe — non-Hokm OR is trump OR trumpExhausted).
- If safe boss(es) exist, returns highest by face value.
- Else if sweepPursuit (won 7/7), returns highest by rank.
- Else returns highest by face value.

**Sun on trick 8**: contract type is not Hokm → `isSafe = (contract.type ~= K.BID_HOKM)` = TRUE for any card. So EVERY card with `S.HighestUnplayedRank(su) == r` is a safe boss. In Sun trick 8, "boss" = whatever the current highest-unplayed rank in our suit is.

**Verification**: `S.HighestUnplayedRank("H") == "A"` if A♥ has not been played. If we hold A♥ on trick 8, return A♥. Good — A♥ wins trick 8 + LAST_TRICK_BONUS.

**M8 interaction**: M8 fires on trick 1 (`trickNum == 1`). The trick-8 branch fires on `trickNum == 8`. **No overlap**. For tricks 2-7 with `sweepPursuitEarly=false`, the trick-8 block does NOT fire — neither does M8. Branch ordering is clean.

**Sweep-pursuit-early gate**: `trickNum >= 3 and trickNum <= 7 and isBidderTeam`. For Sun, `isBidderTeam` is FALSE per the line 1705 typo (only Hokm sets it). **So sweep-pursuit-early NEVER fires for Sun**. This is a real bug-or-gap:

**Severity: Medium (Sun-specific gap).** A Sun bidder team that has won 7/7 tricks (clean sweep) should pursue Al-Kaboot Sun (220 face value, ×2 = 440). The sweep-pursuit-early branch is the natural place. But due to the `isBidderTeam` Hokm-typo at line 1705, it doesn't fire for Sun bidder team. Sun bidder-team sweep-pursuit-early is **silent dead code**.

**Code quote (line 1705-1706):**
```lua
local isBidderTeam = (contract.type == K.BID_HOKM
                      and myTeam == R.TeamOf(contract.bidder))
```

**Repro:** Sun contract, bidder = seat 2. Tricks 1-2 won by seat-2 team (good cards). Trick 3 lead. M8 doesn't fire (`trickNum == 1` gate fails). sweepPursuitEarly check at line 1727-1735: `isBidderTeam == false` (Sun) → `sweepPursuitEarly = false`. Branch falls through to trick 8 / sweep-pursuit block: trickNum != 8 AND sweepPursuitEarly = false → branch not entered. Falls all the way down to Sun-shortest-suit-low, leading low. **Wrong** — we should be aggressively pushing for sweep.

**Recommendation:** fix line 1705-1706 to:
```lua
local isBidderTeam = (myTeam == R.TeamOf(contract.bidder))
```
Drop the Hokm-only restriction. This is the same fix B-Bot-04 adj-1 mentioned. Promoted here from "informational" to a **real Sun strategic bug**.

This would also impact the B-97 gate at line 1984 (`not isBidderTeam` — see F8 above). Be careful.

---

### F12 — Bidder-only Hokm trump-pull block: cumulative interaction risks

**Severity: Low (existing logic; flagged for cumulative effects).**

Lines 2054-2215 are the bidder-Hokm trump-pull block. Five layered deviations:

1. **B-96** (Ace-exhaustion, lines 2068-2099): if all 3 non-trump Aces seen + tricks ≥ 3 → cash highest non-trump.
2. **Trump-poor + non-trump Ace** (lines 2102-2108): if trumpCount < 4, return non-trump A.
3. **B-57/71** (conservativeOpp, lines 2126-2143): see F1 — has the `bidderTeam` undefined bug.
4. **B-98** (J/9-lock, lines 2152-2182): if both J and 9 of trump out of pool → cash side-suit Ace.
5. **H-6** (A-of-trump preserve, lines 2192-2214): early tricks (#tricks < 5) AND have non-Ace trump → exclude A-of-trump from candidates.

**Cumulative interaction**: deviations 2, 3, 4 can ALL fire, returning a non-trump Ace. They're sequential — first match wins. Order: B-96 → trump-poor → B-57/71 → B-98 → H-6.

**B-96 deviation 1** at line 2068: requires `S.s.tricks >= 3`. So fires from trick 4 onwards.
**B-57/71** at line 2126: requires M3lm + Hokm + contract.trump + contract.bidder. No trick gate — fires from trick 1.
**B-98** at line 2152: requires `S.HighestUnplayedRank(contract.trump) ~= "J"` (i.e. J of trump has been played). Fires only when J already gone.

The **risk**: B-57/71 is broken via F1 (`bidderTeam` undefined). The deviation can erroneously fire on trick 1 if a same-team seat is `styleTrumpTempo == -1`. Then deviation 1 (B-96) would never have its chance (overrides not stacking — first match returns).

**Severity: Low** (deviations are intentional and individually well-commented; F1 is the actual bug).

---

### F13 — `nonTrumps` building and `suitCount` for Sun: count is total cards per suit, not non-trump cards per suit

**Severity: OK (not a bug; potentially confusing).**

Lines 2271-2278:
```lua
local nonTrumps = {}
local suitCount = { S = 0, H = 0, D = 0, C = 0 }
for _, c in ipairs(legal) do
    if not C.IsTrump(c, contract) then
        nonTrumps[#nonTrumps + 1] = c
        suitCount[C.Suit(c)] = suitCount[C.Suit(c)] + 1
    end
end
```

`suitCount` counts only non-trump cards. For Sun (no trump), all cards are non-trump, so `suitCount[suit]` = total cards of suit. For Hokm with trump = ♠, `suitCount["S"]` = 0 (since spades are filtered).

Then line 2380-2383 (Sun shortest-suit-low):
```lua
if contract.type == K.BID_SUN then
    local count = { S = 0, H = 0, D = 0, C = 0 }
    for _, c in ipairs(legal) do
        count[C.Suit(c)] = count[C.Suit(c)] + 1
    end
```
Builds a SECOND `count` table independent of `suitCount`. For Sun this gives the same result (no trump filter) but they're two separate computations. Cosmetic redundancy; no bug.

**Sun shortest-suit selection** (lines 2384-2399) iterates `{S,H,D,C}` for tied-shortest tiebreaker — returns Spades first. Same arbitrary ordering as M8/F6/D-RT-24 r4. Deterministic but unsourced.

**Severity: OK; cosmetic redundancy.**

---

## Summary table

| ID | Severity | Branch | Issue |
|---|---|---|---|
| **F1** | **HIGH (real bug)** | Hokm bidder block (line 2130) | `bidderTeam` is undefined inside `pickLead`; `R.TeamOf(s2) ~= nil` always true; conservativeOpp deviation misfires when same-team seat has `styleTrumpTempo == -1`. **Fix**: add `local bidderTeam = R.TeamOf(contract.bidder)` at top of `pickLead`. |
| F2 | (deferred to B-Bot-04 / D-RT-10 / D-RT-24) | M8 (lines 1806-1823) | M8 itself correct; multi-mardoofa `{S,H,D,C}` order, leak symmetry, and Bargiya phase-split missing covered separately. |
| **F3** | **Medium-High (strategic)** | Hokm Branch 3 (lines 1829-1838) | Hokm bidder on trick 1 leads non-trump boss-Ace via `S.HighestUnplayedRank` BEFORE pulling trump. Contradicts pro convention (pull trump first 2-3 tricks). Recommend trickNum gate or `not isBidder` gate. |
| F4 | Low (gap) | Tahreeb opp-avoid (lines 1906-1922) | Opp `dontwant` is silently ignored both as avoid AND as positive-confirmation signal. Documented design choice; possible EV improvement to flip-read it. |
| **F5** | **Medium-High (real strategy gap)** | Tahreeb pref (lines 1930-1944) | **Bargiya receiver phase-split (video #14 rule 9) NOT implemented**. Code leads Bargiya-suit immediately even at hand size ≥5 where rule says delay 1-2 tricks. |
| F6 | Low (style) | Fzloky avoid pipeline (lines 2402-2425) | Single-slot `fzlokyAvoidSuit` instead of a set; multiple competing avoid signals can only honor one. Layering correct (Fzloky > B-97 > B-82). |
| F7 | OK (verified) | B-82 baited-suit avoid (lines 2005-2028) + recorder (lines 510-562) | Forced-J gate v0.9.2 #46 is a documented approximation; D-RT-12 confirms the limitation. No new findings. |
| F8 | Low (doc misleading) | B-97 opp-meld avoid (lines 1975-2003) | `not isBidderTeam` for Sun fires for ALL Sun teams (because `isBidderTeam` is Hokm-typo'd at line 1705). Functionally OK (avoiding opp meld is universal); comment misleading. |
| F9 | OK (correct) | Singleton-low (lines 2336-2369) | No rank-guard for Sun → singleton-A in Sun returns A. Correct (singleton-A in Sun must be led). D-RT-24 r7 confound is the consequence. |
| **F10** | Medium (deferred) | (NOT in pickLead — pickFollow gap) | Sender-side deceptive overplay (Section 4 rules 4-5 / Section 11 rule 8 sender) explicitly DEFERRED per code comment line 522. Receiver-side baited-suit avoid IS implemented. |
| **F11** | **Medium (Sun bug)** | sweep-pursuit-early gate (lines 1727-1735) | `isBidderTeam` typo at line 1705 makes `sweepPursuitEarly = false` ALWAYS for Sun. Sun bidder-team sweep-pursuit dead code. **Fix**: drop the `K.BID_HOKM` restriction at line 1705-1706. |
| F12 | Low (interaction risk) | Hokm bidder block (lines 2054-2215) | Five layered deviations (B-96/trump-poor/B-57-71/B-98/H-6) interact sequentially. F1's bug feeds B-57/71 misfires. |
| F13 | OK (cosmetic) | nonTrumps + Sun shortest (lines 2271, 2379) | Two independent suit-count computations for Sun; same result, redundant. Tiebreaker `{S,H,D,C}` arbitrary in Sun shortest-suit branch (consistent with M8 / F6). |

---

## Verdict

**Two real bugs** found beyond the M8 scope:

1. **F1** (`bidderTeam` undefined at line 2130): Hokm bidder's B-57/71 conservativeOpp deviation misfires when a same-team seat has accumulated `styleTrumpTempo == -1`. **Severity: HIGH** because the bidder is the most strategically critical seat and the misfiring is silent (no error, just wrong play).

2. **F11** (`isBidderTeam` is Hokm-only at line 1705-1706): Sun bidder-team sweep-pursuit-early is dead code. A Sun team that has won 7/7 tricks falls through to Sun-shortest-suit-low instead of pursuing Al-Kaboot Sun aggressively. Same root-cause pre-existing typo also makes the F8 B-97 comment misleading and F3 already documented.

**Two real strategy gaps**:

3. **F3** (Hokm Branch 3 boss-non-trump-Ace lead on trick 1): bidder cashes side-suit Aces before pulling trump. Contradicts pro convention. **Severity: Medium-High** (silently negative EV).

4. **F5** (Bargiya receiver phase-split missing): documented in `signals.md` and `glossary.md` and source video #14, but `pickLead` leads the Bargiya'd suit immediately regardless of hand size. **Severity: Medium-High** (real EV cost on every trick-2/3 Bargiya).

**One deferred-by-design gap**:

5. **F10** (sender-side deceptive overplay): Section 4 rules 4-5 / Section 11 rule 8 SENDER side not implemented; code comment at line 522 says "deferred." Receiver side is implemented (B-82 baited-suit avoid).

The M8 scope itself (F2) is correctly implemented per the three sister docs B-Bot-04 / D-RT-10 / D-RT-24. The cross-suit elimination leak and bot-vs-human asymmetry concerns are real strategic issues but no code bugs.

**No code modifications made.**

---

## Confidence

**High** for F1, F11, F5 (verifiable by direct code reading and Grep for absent identifiers/branches).

**Medium-High** for F3, F10 (correct interpretation of pro convention vs source-doc rule).

**High** for F2 (delegated to three thorough sister docs).

**Medium** for F4, F6 (architectural smells, not bugs, and depend on EV measurements).

No code was modified.
