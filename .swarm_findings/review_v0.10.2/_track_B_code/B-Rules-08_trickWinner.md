# B-Rules-08 — `R.TrickWinner` / `R.TrickPoints` / `R.CurrentTrickWinner`

**Version**: v0.10.2
**Track**: B (code, no modifications)
**Scope**: trick-resolution and per-trick point sum in `Rules.lua` lines 30-73 (with cross-checks against last-trick / sweep / AKA paths elsewhere).
**Date**: 2026-05-05

---

## Reference map

| Symbol | Path |
|---|---|
| `R.CurrentTrickWinner` | `C:/CLAUDE/WHEREDNGN/Rules.lua:34-59` |
| `R.TrickWinner` (alias) | `C:/CLAUDE/WHEREDNGN/Rules.lua:62-64` |
| `R.TrickPoints` | `C:/CLAUDE/WHEREDNGN/Rules.lua:67-73` |
| `C.TrickRank` | `C:/CLAUDE/WHEREDNGN/Cards.lua:107-114` |
| `C.PointValue` | `C:/CLAUDE/WHEREDNGN/Cards.lua:116-123` |
| `C.IsTrump` | `C:/CLAUDE/WHEREDNGN/Cards.lua:125-128` |
| `K.RANK_TRUMP_HOKM` | `C:/CLAUDE/WHEREDNGN/Constants.lua:50` (J=8, 9=7, A=6, T=5, K=4, Q=3, 8=2, 7=1) |
| `K.RANK_PLAIN` | `C:/CLAUDE/WHEREDNGN/Constants.lua:51` (A=8, T=7, K=6, Q=5, J=4, 9=3, 8=2, 7=1) |
| `K.POINTS_TRUMP_HOKM` | `C:/CLAUDE/WHEREDNGN/Constants.lua:42-44` (J=20, 9=14, A=11, T=10, K=4, Q=3, 8/7=0; sum 62) |
| `K.POINTS_PLAIN` | `C:/CLAUDE/WHEREDNGN/Constants.lua:45-47` (A=11, T=10, K=4, Q=3, J=2, 9/8/7=0; sum 30/suit) |
| `K.LAST_TRICK_BONUS` | `C:/CLAUDE/WHEREDNGN/Constants.lua:53` = 10 |
| `K.HAND_TOTAL_HOKM` | `C:/CLAUDE/WHEREDNGN/Constants.lua:54` = 162 (152 + 10 last) |
| `K.HAND_TOTAL_SUN` | `C:/CLAUDE/WHEREDNGN/Constants.lua:55` = 130 (120 + 10 last) |
| `K.AL_KABOOT_HOKM` | `C:/CLAUDE/WHEREDNGN/Constants.lua:114` = 250 |
| `K.AL_KABOOT_SUN` | `C:/CLAUDE/WHEREDNGN/Constants.lua:115` = 220 |
| Test cases | `C:/CLAUDE/WHEREDNGN/tests/test_rules.lua:191-240` (Section C) |
| Source — video #41 (Sun) | `C:/CLAUDE/WHEREDNGN/docs/strategy/_transcripts/41_play_sun_basics_extracted.md` |
| Source — video #42 (Hokm) | `C:/CLAUDE/WHEREDNGN/docs/strategy/_transcripts/42_play_hokm_basics_extracted.md` |
| Source — video #43 (Scoring) | `C:/CLAUDE/WHEREDNGN/docs/strategy/_transcripts/43_score_calculation_extracted.md` |
| Last-trick bonus apply | `C:/CLAUDE/WHEREDNGN/Rules.lua:670-673` (inside `R.ScoreRound`) |
| Sweep detection | `C:/CLAUDE/WHEREDNGN/Rules.lua:711-714` (inside `R.ScoreRound`) |
| AKA-on-T trick lock gap | `C:/CLAUDE/WHEREDNGN/.swarm_findings/review_v0.10.0/_phase2_xref/xref_X2_aka.md:64-89, 130-132` (B5) |
| `wouldWin` heuristic caller | `C:/CLAUDE/WHEREDNGN/Bot.lua:1617-1622` |
| Tahreeb-recorder caller | `C:/CLAUDE/WHEREDNGN/Bot.lua:584-590` (priorTrick winner reconstruction) |
| Bait-ledger caller | `C:/CLAUDE/WHEREDNGN/Bot.lua:525-530` |
| pickFollow caller | `C:/CLAUDE/WHEREDNGN/Bot.lua:2484-2486` |
| BotMaster rollout caller | `C:/CLAUDE/WHEREDNGN/BotMaster.lua:675, 695, 760` |
| UI live winner highlight | `C:/CLAUDE/WHEREDNGN/UI.lua:2616` |
| Net trick-end resolution | `C:/CLAUDE/WHEREDNGN/Net.lua:1640-1643` |
| `R.IsValidSWA` re-use | `C:/CLAUDE/WHEREDNGN/Rules.lua:398` |
| `R.IsLegalPlay` re-use | `C:/CLAUDE/WHEREDNGN/Rules.lua:138, 166` |

---

## Function bodies (verbatim, abridged)

### `R.CurrentTrickWinner(trick, contract)` — `Rules.lua:34-59`

```
if not trick or not trick.plays or #trick.plays == 0 then return nil end
local plays = trick.plays
local leadSuit = trick.leadSuit
local bestSeat, bestRank = nil, -1
local trumpPlayed = false
if contract.type == K.BID_HOKM then
    for _, p in ipairs(plays) do
        if C.IsTrump(p.card, contract) then trumpPlayed = true; break end
    end
end
for _, p in ipairs(plays) do
    local s = C.Suit(p.card)
    local eligible
    if trumpPlayed then
        eligible = C.IsTrump(p.card, contract)
    else
        eligible = (s == leadSuit)
    end
    if eligible then
        local rk = C.TrickRank(p.card, contract)
        if rk > bestRank then bestRank, bestSeat = rk, p.seat end
    end
end
return bestSeat
```

### `R.TrickWinner(trick, contract)` — `Rules.lua:62-64`

Pure alias to `R.CurrentTrickWinner`. No 4-play guard, no defensive trimming; the alias trusts the caller (`Net.lua:1639` does `#S.s.trick.plays < 4` short-circuit BEFORE calling `R.TrickWinner`, so this is safe in practice).

### `R.TrickPoints(trick, contract)` — `Rules.lua:67-73`

```
local total = 0
for _, p in ipairs(trick.plays) do
    total = total + (C.PointValue(p.card, contract) or 0)
end
return total
```

No nil-guard on `trick` or `trick.plays`; the `or 0` is on the `PointValue` return. Will throw on `R.TrickPoints(nil, c)` or `R.TrickPoints({}, c)` (the latter actually iterates zero times and returns 0 — fine).

---

## Findings

### F1 — Trump precedence (Hokm): correctly enforced

**Severity**: NONE — clean.

The pre-scan loop at `Rules.lua:40-44` flips `trumpPlayed = true` if **any** play in the trick has `C.IsTrump(p.card, contract)`. `C.IsTrump` (`Cards.lua:125-128`) requires `contract.type == K.BID_HOKM AND C.Suit(card) == contract.trump`, so it correctly returns false in Sun for any card. Once `trumpPlayed` is set, the eligibility filter at L48-49 promotes ONLY trump cards as candidates regardless of who led — i.e. any trump beats any non-trump.

Test C-2 at `test_rules.lua:202-205` exercises the canonical case (spades led, hearts trump, seat-2 plays `7H` while others play higher non-trump spades) and asserts seat-2 wins. The lowest trump (`7H`, rank-1 in `K.RANK_TRUMP_HOKM`) beats `AS` (rank-8 in `K.RANK_PLAIN`). Verified.

Cross-source: video #42 R3 (Daqq) — "any trump beats any non-trump" is the implicit Hokm primitive. Source-J #42 row R3 maps to `R.IsLegalPlay` enforcement; the trick-resolution side is implicitly covered (the only way a non-trump could win is if no trump appears in the trick, which `Rules.lua:42` correctly classifies).

### F2 — Trump rank order (Hokm): correctly applied via `K.RANK_TRUMP_HOKM`

**Severity**: NONE — clean.

The trump-eligibility branch at `Rules.lua:48-49` selects only trumps when `trumpPlayed`. Then `C.TrickRank(p.card, contract)` at `Cards.lua:107-114` returns `K.RANK_TRUMP_HOKM[r]` when `s == contract.trump` (and `K.RANK_PLAIN[r]` otherwise). Constants table at `Constants.lua:50`: J=8 > 9=7 > A=6 > T=5 > K=4 > Q=3 > 8=2 > 7=1. Matches Saudi Hokm trump ordering per video #42 ordering primer ("ولد تسعه بعدين اكه" = J → 9 → A; transcript file `42_play_hokm_basics_extracted.md` line 102).

Test C-1 at `test_rules.lua:196-199`: hearts trump, hearts led, plays `AH/JH/9H/KH`. Asserts seat-2 wins with `JH`. Per `K.RANK_TRUMP_HOKM`: JH=8, 9H=7, AH=6, KH=4 → JH highest → seat-2. Verified.

**Subtle correctness**: when trump is led (rather than discarded as a ruff), `trumpPlayed` becomes true on the FIRST iteration of L40-44 (the lead card). Then ALL plays are evaluated as trumps. Since they all are trumps (everyone follows trump in the must-follow path), the highest-rank trump wins — same as Hokm trump-led case in `K.RANK_TRUMP_HOKM`. No logic forks for trump-led-vs-trump-ruffed. Correct.

### F3 — Off-trump rank (Hokm + Sun): correctly applied via `K.RANK_PLAIN`

**Severity**: NONE — clean.

Off-trump cards in Hokm (i.e. follow-suit lead trick where no trump appears) hit the `s == leadSuit` branch at L51 and route through `C.TrickRank` which returns `K.RANK_PLAIN[r]` (since `s ~= contract.trump`). Sun cards always route through `K.RANK_PLAIN` (`C.TrickRank` returns the plain table whenever `contract.type ~= K.BID_HOKM` or `s ~= contract.trump`).

Constants table `K.RANK_PLAIN` at `Constants.lua:51`: A=8 > T=7 > K=6 > Q=5 > J=4 > 9=3 > 8=2 > 7=1. Matches video #41 row 5 ("Sun rank order A → T → K → Q → J") and #43 card-value cross-check rows (transcript `43_score_calculation_extracted.md` lines 58-65).

Test C-3 at `test_rules.lua:208-211`: spades led, hearts trump, no trump played, plays `AS/9D/KS/QS`. Asserts seat-1 wins. By `K.RANK_PLAIN`: AS=8, KS=6, QS=5, 9D=3 (off-suit, but eligibility filter excludes — only S cards are eligible). Highest spade is AS → seat-1. Verified.

Test C-4 at `test_rules.lua:214-217`: Sun, hearts led, plays `AH/TS/KH/QH`. Asserts seat-1 (`AH`). Eligible cards (suit=H): AH=8, KH=6, QH=5; TS off-suit excluded. AH wins. Verified.

### F4 — Lead-suit precedence: correctly enforced via two-stage eligibility

**Severity**: NONE — clean.

The `eligible = (s == leadSuit)` branch at L51 fires when `trumpPlayed == false`. It excludes any card whose suit is not the lead suit. In Sun this is the only branch (Hokm pre-scan stays false because `C.IsTrump` requires Hokm). Test C-5 at `test_rules.lua:220-223` exercises Sun with one lead-suit card (`9H`) and three off-suit (`AS/TC/JD`); asserts seat-1 wins despite holding the LOWEST plain-rank card on table. The off-suit cards are excluded entirely, so `bestRank` only ever sees `9H` (rank-3) and seat-1 wins. Verified.

In Hokm with no trump played, the same logic applies — non-trump non-lead-suit discards are completely ineligible to win. This correctly matches video #24 row "Off-suit discard while a trump exists on table — Off-suit card has value 0 to trick-resolution" (`24_trick_fundamentals_extracted.md:20`). The phrasing "value 0" in the transcript is informal; the code's mechanism is "ineligible" rather than "rank 0", but the outcome is identical.

### F5 — "Tied highest" impossibility AND defensive behavior on duplicates

**Severity**: NONE — robust by accident, with a subtle observation.

A 4-card trick with 4 unique seats and a unique-card-deck cannot produce two cards with the same `(suit, rank)` pair. This is the design invariant. Within the trick-resolution loop at `Rules.lua:45-57`, the comparison is strict-greater-than (`if rk > bestRank`), so on any legitimate trick exactly one card has the highest rank.

**Defensive behavior on duplicates**: if a buggy simulator somehow injects two identical cards into `trick.plays`, the loop still works — the first card with the highest rank wins (later equal-rank entries are dropped by the `>` predicate). The seat returned would be the **earlier** seat in `plays` order. There is no nil-return path on duplicate ranks. The `bestSeat` is initialized `nil`, but it gets set as soon as any eligible play is seen, so as long as at least one card is eligible, `bestSeat` is non-nil at return. No defensive crash.

**Subtle observation**: if the trick is non-empty but contains only ineligible cards (i.e. nobody followed lead AND no trump played), `bestSeat` would stay `nil` and L58 returns `nil`. This is impossible under correct legal-play enforcement (a leader always plays SOMETHING that defines `leadSuit`, so the lead card itself is always eligible), but defensively returns nil rather than crashing. **However**, the leader's own card is `s == leadSuit` by definition (since `leadSuit = C.Suit(plays[1].card)` in normal flow), so the leader is always eligible. Confirmed nil-return is unreachable in normal flow.

The illegal-play simulator path (e.g. SWA validator at `Rules.lua:383-501`) calls `R.IsLegalPlay` first to filter; duplicates would be screened out by the legal-play layer before reaching `R.CurrentTrickWinner`. No defensive issue.

### F6 — Last-trick +10 bonus: applied at `R.ScoreRound`, NOT inside `TrickPoints`

**Severity**: NONE — clean. Worth documenting because the brief explicitly asks.

`R.TrickPoints` itself is a pure card-sum: `Rules.lua:67-73`. It returns ONLY the sum of `C.PointValue(card, contract)` for the 4 cards. No `+10` injection.

The +10 last-trick bonus is applied at `R.ScoreRound` at `Rules.lua:670-673`:
```
if i == #tricks then
    lastTrickTeam = team
    teamPoints[team] = teamPoints[team] + K.LAST_TRICK_BONUS
end
```
This is per-team bookkeeping, awarded to whoever won the last trick. `K.LAST_TRICK_BONUS = 10` is at `Constants.lua:53`; `K.HAND_TOTAL_HOKM = 162` at `Constants.lua:54` is documented inline as `152 cards + 10 last trick`; `K.HAND_TOTAL_SUN = 130` at `Constants.lua:55` is `120 + 10 last trick`. Cross-source video #43 transcript `43_score_calculation_extracted.md:80-82` confirms 130/162/10 against Saudi convention; section 3b of that transcript walks the arithmetic and matches.

So: `TrickPoints` is bonus-blind by design. The +10 is added once-per-round during the per-team aggregation pass, NOT baked into trick 8's per-card sum. This is the right separation — `TrickPoints` is reused by `Net.SendTrick` (`Net.lua:1641`) to broadcast the per-trick raw to all clients, and broadcasting `pts + 10` for trick 8 would double-count when the receiver re-runs `R.ScoreRound`. Confirmed correct.

### F7 — Sun rank-only winner: correctly enforced

**Severity**: NONE — clean.

In Sun, `contract.type == K.BID_HOKM` is false, so `Rules.lua:40` skips the trump pre-scan; `trumpPlayed` stays `false` for the entire trick. Eligibility falls through to `eligible = (s == leadSuit)` at L51. `C.TrickRank` always returns `K.RANK_PLAIN` (Sun branch at `Cards.lua:111-113`). Result: only lead-suit cards are eligible, ranked by `K.RANK_PLAIN`. Confirms video #41 row 6 ("Winner = highest-rank card OF THE LED SUIT only. Off-suit discards CANNOT win"). Tests C-4 and C-5 exercise this end-to-end; verified.

There is no code path where Sun could erroneously promote an off-suit card to winner — the Hokm pre-scan is gated behind `contract.type == K.BID_HOKM`, and `C.IsTrump` returns false for non-Hokm contracts regardless. No accidental "Sun trump" path exists.

### F8 — Sweep detection: handled OUTSIDE trick functions, in `R.ScoreRound`

**Severity**: NONE — clean.

`R.CurrentTrickWinner` and `R.TrickWinner` have no sweep awareness. `R.TrickPoints` has no sweep awareness. Sweep is a round-level concept and is detected at `R.ScoreRound` at `Rules.lua:711-714`:
```
local sweepTeam
if trickCount.A == 8 then sweepTeam = "A"
elseif trickCount.B == 8 then sweepTeam = "B" end
```
The trickCount is accumulated at `Rules.lua:669` (`trickCount[team] = trickCount[team] + 1`) where `team = R.TeamOf(t.winner)`. `t.winner` is set elsewhere (read-side of `R.ScoreRound`); the function trusts the caller's pre-resolved per-trick winner.

Sweep replaces normal scoring at `Rules.lua:817-822` (Al-Kaboot bonus from `K.AL_KABOOT_HOKM = 250` or `K.AL_KABOOT_SUN = 220`). The `R.TrickPoints` per-trick sums are still computed but discarded when `sweepTeam` is set — the tricks themselves don't need to know they're part of a sweep.

This separation is correct: trick-resolution is per-trick and stateless; sweep is a 8-trick aggregate. No double-counting.

### F9 — Defensive nil-check on empty `trick.plays`

**Severity**: NONE — clean for `CurrentTrickWinner`; minor inconsistency for `TrickPoints`.

`R.CurrentTrickWinner` at `Rules.lua:35` defends explicitly: `if not trick or not trick.plays or #trick.plays == 0 then return nil end`. This is the only nil-tolerant entry path; called from many sites (`Bot.lua:529, 589, 1622, 2485`, `BotMaster.lua:675, 695, 760`, `Rules.lua:138, 166, 398`, `UI.lua:2616`).

`R.TrickPoints` at `Rules.lua:67-73` does NOT defend. It does `for _, p in ipairs(trick.plays) do`, which crashes on `trick == nil` and quietly returns 0 on `trick.plays == nil` (ipairs on nil returns no iterations in Lua 5.1, but actually in Lua 5.1 `ipairs(nil)` errors with "bad argument #1 to 'ipairs' (table expected, got nil)"). The latter is the practical concern.

**Why this is fine in practice**: every caller (`Net.lua:1641`, `tests/test_rules.lua` Section C, `Bot.lua` rollout sites, `BotMaster.lua` rollout sites) constructs or reads `trick` from a non-nil source — `S.s.trick` is always `{ plays = {...}, leadSuit = ... }` or absent (in which case `Net.lua:1639` short-circuits). The bot/master rollout sites copy `trick.plays` into a fresh table before mutating, so they have a guaranteed non-nil `plays`.

**Asymmetry observation (not a bug)**: `CurrentTrickWinner` defends but `TrickPoints` doesn't. The asymmetry is harmless given current call sites, but a future caller that passes a synthesized `{}` (no `plays` key) to `TrickPoints` would crash. Worth noting for future contributors.

### F10 — `CurrentTrickWinner` mid-trick: used by signal-recorder, correct

**Severity**: NONE — clean.

The brief flags partner-winning detection in the signal-recorder. Two recorder sites call `R.CurrentTrickWinner` on a SUB-trick (the trick BEFORE the play being observed):

1. **Bait-detected ledger** at `Bot.lua:525-530`. Builds `prevTrick = { plays = prePlays, leadSuit = leadSuit }` where `prePlays` is `trickPlays[1..#trickPlays-1]` (excluding the J just played). Calls `R.CurrentTrickWinner(prevTrick, contract)` to determine if partner was winning before the J landed. Correctness: the leadSuit is preserved correctly; only the most-recent play is excluded.

2. **Tahreeb signal recorder** at `Bot.lua:584-590`. Same pattern: builds `priorTrick = { plays = prior, leadSuit = leadSuit }` where `prior` is everything except the most-recent play. Calls `R.CurrentTrickWinner` and checks `R.Partner(seat) == prevWinner`.

Both reconstructions are correct because:
- `R.CurrentTrickWinner` is order-independent within `plays` (it scans for trumpPlayed first, then iterates all eligible plays for the highest rank — neither depends on the index ordering). Truncating the latest play and re-running gives the correct pre-state winner.
- `leadSuit` is invariant over the trick (set once on first play, copied for the truncation).
- The `trumpPlayed` pre-scan correctly recomputes when a trump card was the one truncated — if seat-3 ruffed and seat-4 over-trumped, truncating seat-4's play still leaves seat-3's trump in `prior`, so `trumpPlayed` stays true. Eligible-set still trump-only. Correct.

3. **`pickFollow` mid-trick winner read** at `Bot.lua:2485-2486`. Same primitive — `R.CurrentTrickWinner(trick, contract)` is called on the IN-FLIGHT trick (some plays in, not all 4). Returns the seat currently winning the partial trick. Correct because the eligibility logic (trumpPlayed pre-scan + leadSuit eligibility) works for ANY non-empty plays length, not just `#plays == 4`.

4. **`wouldWin` simulator** at `Bot.lua:1617-1622`. Constructs a scratch trick with the candidate card APPENDED to `trick.plays` and reuses `trick.leadSuit`. Verified correct in `wave3_C4_findings.md:158-162` — when seat-1 leads with trump, `trick.leadSuit` is the trump suit; the sim inherits this; `CurrentTrickWinner` correctly switches to trump-only eligibility. No bug.

5. **UI live highlight** at `UI.lua:2616`. Uses `CurrentTrickWinner` to highlight the seat currently winning. Mid-trick; same primitive. Correct.

All five callers depend on the correctness of partial-trick resolution. The function delivers it because eligibility + rank-comparison are stateless within a single trick.

### F11 — AKA-on-T trick-locking (J-067 part 1, X2 B5): **CONFIRMED NOT IMPLEMENTED**

**Severity**: LOW (per prior review classification) — the gap is real and matches the v0.10.0 review's M4/B5 row; v0.10.2 partially addressed via `R.IsLegalPlay`'s `akaCalled` parameter (M4) but did NOT touch trick-resolution.

**The gap**. `R.CurrentTrickWinner` at `Rules.lua:34-59` is purely highest-rank-by-`C.TrickRank`. It NEVER consults `S.s.akaCalled` or any AKA-aware state. There is no parameter that could signal "this trick has been locked by an AKA call on T".

**What J-067 part 1 requires**. Source-J `42_play_hokm_basics_extracted.md` row R4 (AKA Daqq-relief) plus `xref_X2_aka.md:64-89, 130-132`:
> "AKA on 10 = 10 substitutes for Ace ... the trick is closed for over-trumping requirements"

Translated to code semantics: when an AKA caller leads `T` of a side suit AND announces AKA on it, the T should function as the boss of that trick — not just for the receiver-relief side (which IS now wired in v0.10.2 M4 at `Rules.lua:115-122`), but also for the WINNER-DETERMINATION side. If an opp ruffs over the AKA'd T with a trump, `R.CurrentTrickWinner` will award the trick to the ruffer. Saudi rule per the cited source says the trick was already locked by the AKA — the opp's ruff should NOT win the trick.

**Concrete scenario where it matters** (constructed for this audit; not pulled from existing tests):

```
Contract: { type = K.BID_HOKM, trump = "S", bidder = 1 }
S.s.akaCalled = { seat = 1, suit = "H" }     -- caller (S1) AKA'd hearts
trick = {
  leadSuit = "H",
  plays = {
    { seat = 1, card = "TH" },   -- caller leads T of hearts (boss after A is dead)
    { seat = 2, card = "9H" },   -- opp follows (forced)
    { seat = 3, card = "JH" },   -- partner's trump? no wait...
    -- ...assume seat-4 is void in H and ruffs:
    { seat = 4, card = "7S" },   -- opp ruffs with low trump
  }
}
```

Per `R.CurrentTrickWinner`:
1. Pre-scan L40-44: `trumpPlayed = true` (seat-4's `7S` is trump in S-trump Hokm).
2. Eligibility loop L45-57: only trump cards eligible. `7S` is the only trump → `bestSeat = 4`.
3. Returns 4. **Opp wins the trick**.

Per Saudi rule (J-067 part 1): the AKA on TH should have locked the trick for seat-1's team. Opp's ruff is illegal (must-trump-but-AKA-relieved-the-receiver — wait, the opp is NOT the receiver; the opp's must-trump is unconditional; the opp legally CAN ruff). The point is the opp ruffing over an AKA'd T was supposed to be ineffective — the AKA'd card is the boss "for trick-resolution purposes". But the code's must-trump enforcement at `Rules.lua:177-184` correctly forces opp to ruff (ruffer is NOT the AKA-receiver's partner; the receiver-relief gate at L116-122 applies only when `seat`'s partner is the AKA caller). So the ruff is legal AND wins the trick under current code.

**Whether this gap actually fires in real play**:
- The receiver-side relief (`Rules.lua:115-122`) means partner of caller can discard freely; the canonical AKA-partner-relief path is now wired (v0.10.2 M4).
- The OPPONENTS still have must-trump obligations independent of AKA (no carve-out for opps), and if they have trump, they MUST ruff. The ruff legally wins under `R.CurrentTrickWinner`.
- Under the J-067 part 1 reading, the opp's ruff would either be illegal or non-winning. Code does neither.
- In practice, if the AKA'd card is the actual highest live (per `S.HighestUnplayedRank`), the speaker's intent is "you've thrown a card no one can beat" — the speaker is implicitly assuming opps have NO legal trump-ruff because they have followed the led suit. In practice in late-game AKA on T fires when the A is dead AND opps are tracked by `playedCardsThisRound`; the bot only AKAs when `S.HighestUnplayedRank(suit) == cardRank` (`Bot.PickAKA` line 3139). Whether opps actually CAN ruff depends on their hand state. If both opps still have trump AND are void in led suit, the speaker would say AKA is wasted.
- The code's heuristic side (`Bot.PickAKA`) doesn't track "opps are void in led suit" before allowing AKA. So the bot can call AKA in a state where an opp ruffing kills it — and `R.CurrentTrickWinner` will award the trick to the ruffer.

**What "implementing part 1" would require** (out of scope for this Track-B audit):
- Either: extend `R.CurrentTrickWinner` to take `akaCalled` and override the trump-pre-scan when the AKA'd card matches a play (lock that play as winner).
- Or: extend `R.IsLegalPlay` to forbid an opp ruff over an AKA'd card unless they have no other legal play. (More invasive; would change must-trump semantics for opps, not just receiver.)
- Either approach requires plumbing `S.s.akaCalled` into both functions consistently. v0.10.2's M4 plumbed it into `R.IsLegalPlay` for the receiver path only. Trick-resolution side remains unchanged.

**Confirmed gap**. This is the X2 B5 finding from `xref_X2_aka.md:130-132` carried forward unchanged. Severity per prior review = LOW, because:
- It only diverges from canonical Saudi rule when an opp actually ruffs over an AKA'd card.
- In the bot vs bot world, this almost never happens — AKAs only fire when the bot believes the suit is closed (`HighestUnplayedRank` check) AND opps trail in trump distribution. For human play, the divergence would surface; the prior review accepted the LOW severity classification given the rarity in practice.

**Recommended scenario for documentation**: video #18 (`18_when_to_aka_extracted.md`) walks through "AKA on T when A is dead" — a single source. Extracted rule 7 of that video explicitly states the AKA caller's intent: "the T is now the boss; opps cannot beat it because they've followed the suit already". The implicit assumption is opps WERE tracked as void-in-trump or following-suit-out. Code does not enforce this. Sources J-066 and J-067 in `xref_X2_aka.md` formalize the rule as written above.

### F12 — Test coverage thinness for trick-resolution edge cases

**Severity**: LOW — Section C is small (5 winner cases + 3 points cases) for a function called from 13+ sites.

`tests/test_rules.lua:191-240` covers:
- C-1: Hokm trump-led, J-of-trump wins.
- C-2: Hokm side-led, ruff beats lead.
- C-3: Hokm side-led, no trump, highest spade.
- C-4: Sun side-led, highest of led suit.
- C-5: Sun side-led, only lead suit eligible (3 off-suit discards).
- TrickPoints C-1: Hokm trump JH+9H+AH+TH = 55.
- TrickPoints C-2: Hokm off-trump AS+KS+QS+JS = 20.
- TrickPoints C-3: Sun AH+TH+KH+QH = 28.

**Gaps**:
- No mid-trick winner test (1, 2, or 3 plays only). All 5 cases have `#plays == 4`. The signal-recorder reconstructs partial tricks; no direct test for `CurrentTrickWinner({plays={p1,p2}, leadSuit="H"}, contract)`.
- No empty-trick test for `CurrentTrickWinner`. The L35 nil-defense is not exercised.
- No nil-trick test for `TrickPoints`. The function would crash on `nil`; no test asserts the absence of a defense (test would need `assertError`).
- No "everyone trumps" Hokm test (lead suit X led, all 4 ruff because all are void in X). This exercises the trumpPlayed-on-non-lead path with 4 trumps.
- No AKA-related trick-resolution test. F11's gap has no regression coverage.
- No T-substitution-for-A test (the J-067 part 1 case from F11). The gap is invisible to automated CI.

The 5 cases cover the canonical happy paths but leave most of the partial-trick / signal-recorder paths to integration tests in `test_state_bot.lua` (`L581`), `test_baseline_metrics.lua` (`L332`), etc. These end-to-end tests are statistical, not unit-precise.

---

## Verdict

| Question | Answer |
|---|---|
| Trump precedence (Hokm) — any trump beats any non-trump? | **YES** (F1) — pre-scan at `Rules.lua:40-44` flips eligibility to trump-only the moment any trump appears. Test C-2 exercises canonical case. |
| Trump rank order J=8 > 9=7 > A=6 > T=5 > K=4 > Q=3 > 8=2 > 7=1? | **YES** (F2) — `K.RANK_TRUMP_HOKM` at `Constants.lua:50` matches Saudi convention; `C.TrickRank` correctly routes Hokm-trump cards to this table. Test C-1 verifies. |
| Off-trump rank A=8 > T=7 > K=6 > Q=5 > J=4 > 9=3 > 8=2 > 7=1? | **YES** (F3) — `K.RANK_PLAIN` at `Constants.lua:51`; tests C-3 (Hokm off-trump), C-4 (Sun) verify. |
| Lead-suit precedence: only lead-suit cards or trump cards eligible? | **YES** (F4) — eligibility split at `Rules.lua:48-52`. When no trump played, only `s == leadSuit` is eligible; off-suit non-trump discards are excluded entirely (not ranked). |
| Tied-highest impossibility / defensive on duplicate plays? | **N/A in practice; defensively safe** (F5) — uniqueness invariant prevents ties; the `>` predicate would deterministically select the EARLIER seat on a duplicate (no nil-return crash). The `bestSeat == nil` early-return only fires on empty-eligible-set, unreachable in normal flow. |
| Last-trick +10 bonus: applied somewhere; baked or computed at trick 8? | **Computed at `R.ScoreRound`, NOT in `TrickPoints`** (F6) — `Rules.lua:670-673` adds `K.LAST_TRICK_BONUS = 10` to the team that won the LAST trick. `TrickPoints` returns the pure card-sum (matters for `Net.SendTrick` broadcasts to avoid double-counting). |
| Sun A>T>K>Q>J ordering per source #41? | **YES** (F7) — `K.RANK_PLAIN` matches; Sun has no trump pre-scan, so all cards route through `K.RANK_PLAIN`. Test C-4 verifies. |
| Sweep detection — 8/8 tricks by same team → sweepTeam. Where? | **`R.ScoreRound` at `Rules.lua:711-714`** (F8). Trick functions are sweep-blind; sweep is a round-level aggregate evaluated AFTER all tricks resolve. Al-Kaboot bonus replaces normal scoring at `Rules.lua:817-822`. |
| Empty `trick.plays` defensive nil-check? | **`CurrentTrickWinner` defends; `TrickPoints` does NOT** (F9). Asymmetry is harmless under current call sites because every caller hands in a non-nil `plays` table or short-circuits earlier (e.g. `Net.lua:1639`). Worth flagging for future contributors. |
| `CurrentTrickWinner` mid-trick (signal-recorder partner-winning detection) correct? | **YES** (F10). Five callers (`Bot.lua:525/584/1617/2484`, `UI.lua:2616`) all rely on partial-trick resolution. The eligibility-and-rank logic is stateless within the trick, so truncating the latest play and re-running gives the correct pre-state winner. The `trumpPlayed` pre-scan correctly recomputes per call. |
| **AKA-on-T trick-locking (J-067 part 1, X2 B5) implemented?** | **NO** (F11) — confirmed gap. `R.CurrentTrickWinner` is purely highest-rank-by-`C.TrickRank` and ignores `S.s.akaCalled`. v0.10.2 M4 wired AKA-receiver relief into `R.IsLegalPlay` (`Rules.lua:115-122`), but trick-resolution side was NOT touched. An opp ruffing over an AKA'd T legally wins the trick under code; canonical Saudi rule says the AKA'd card should be the trick's boss. Documented scenario in F11 above. Severity LOW per prior review (rare in practice given bot's `HighestUnplayedRank` AKA-gate). |

**Overall**: The trick-resolution surface (`CurrentTrickWinner`, `TrickWinner`, `TrickPoints`) is correct under the standard Saudi rule set in all canonical paths. The Hokm trump precedence, trump rank order, off-trump rank order, lead-suit precedence, and Sun rank-only ordering are all faithfully implemented. The function is clean enough that 13+ callers (bot heuristic, ISMCTS rollout, signal-recorder, UI live highlight, host trick-end resolution, SWA validator) all rely on the same primitive correctly.

The +10 last-trick bonus is correctly externalized to `R.ScoreRound` (computed at trick 8 by team-aggregate, NOT baked into per-trick sums). Sweep detection is similarly externalized.

**The single material gap** is F11 — AKA-on-T trick-locking (J-067 part 1) is NOT implemented. This is the X2 B5 finding from the v0.10.0 review carried forward; v0.10.2 M4 addressed only the receiver-relief side (in `R.IsLegalPlay`), not the trick-winner side (in `R.CurrentTrickWinner`). Severity LOW per prior review classification because the divergence only fires when an opp actually ruffs over an AKA'd card, which is rare given the bot's pre-call gating.

**Test coverage** (F12) is thin: 5 winner cases + 3 points cases for a primitive called from 13+ sites. Mid-trick partial-resolution, defensive empty-input, all-ruff Hokm case, and AKA-aware trick-resolution are uncovered. Adding three or four tests would harden the suite without changing semantics.

---

## Confidence

- **HIGH** on F1-F4 (direct code reads + tests verifying each canonical path).
- **HIGH** on F5 (analytical — uniqueness invariant + `>` predicate behavior is mechanical).
- **HIGH** on F6 (direct code read at `Rules.lua:670-673`; cross-source video #43 transcript confirms 130/162/10).
- **HIGH** on F7-F8 (direct code reads).
- **HIGH** on F9 (confirmed asymmetric defense by direct read).
- **HIGH** on F10 (analytical walk-through across 5 caller sites; matches `wave3_C4_findings.md` prior audit).
- **HIGH** on F11 (gap is direct absence-of-evidence in `R.CurrentTrickWinner`; corroborated by `xref_X2_aka.md:130-132` and `xref_X2_aka.md:71-72`).
- **HIGH** on F12 (direct count of test cases in Section C).

No execution / harness was run; all conclusions derive from static reading of `Rules.lua`, `Cards.lua`, `Constants.lua`, `Bot.lua`, `BotMaster.lua`, `Net.lua`, `UI.lua`, `tests/test_rules.lua`, the cited transcripts in `docs/strategy/_transcripts/`, and the previous audit reports under `.swarm_findings/`.
