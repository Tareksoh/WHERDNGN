# Wave 3 C5 Findings — pickFollow pos-4 + smother + can't-win logic

Auditor: wave3_C5 swarm agent  
Codebase: C:/CLAUDE/WHEREDNGN v0.4.4  
Source file: Bot.lua (pickFollow), BotMaster.lua (BM.PickPlay), Constants.lua  

---

## A-43 — Sun-contract follow when can't beat: lowestByRank vs. lowest point value

**VERDICT: WARNING**

**File:line:** `Bot.lua:1068` (`return lowestByRank(legal, contract)`) and the inner Hokm non-last-seat discard at `Bot.lua:1065`.

**Evidence:**

`lowestByRank` (Bot.lua:662–669) selects by `C.TrickRank(c, contract)`. For Sun (and off-suit in Hokm), `C.TrickRank` uses `K.RANK_PLAIN`:

```
K.RANK_PLAIN = { ["7"]=1, ["8"]=2, ["9"]=3, ["J"]=4, ["Q"]=5, ["K"]=6, ["T"]=7, ["A"]=8 }
```

So rank order (ascending) is: 7, 8, 9, J, Q, K, T, A.

Point values in plain suit (Constants.lua:46–47):

```
K.POINTS_PLAIN = { ["7"]=0, ["8"]=0, ["9"]=0, ["T"]=10, ["J"]=2, ["Q"]=3, ["K"]=4, ["A"]=11 }
```

The prompt's example is exactly correct: in a can't-win situation, the bot discards by trick-rank which means it would throw a 9 (rank 3, 0 pts) over a J (rank 4, 2 pts) — correct — but would throw a J (rank 4, 2 pts) over a Q (rank 5, 3 pts), and would throw a Q (3 pts) over a K (4 pts). The ordering is mostly aligned with point values for the low-rank cards (7/8/9 are both lowest rank and 0 pts), but diverges at J vs Q vs K: rank order J<Q<K while point order J(2)<Q(3)<K(4) — these happen to match. However, rank order puts T at rank 7 and A at rank 8, while point order has T=10 and A=11. The critical divergence is: rank order K(6) < T(7) < A(8), but if we want to minimize points discarded the order should be K(4) < T(10) — rank order does discard K before T, so that is coincidentally correct.

The real issue the prompt raises is the J of an off-suit (2 pts, rank 4) vs 9 (0 pts, rank 3). Since rank 3 < rank 4, `lowestByRank` throws the 9 first, keeping the J — this is correct in terms of minimising points thrown. The prompt's stated concern ("the bot would discard a 9 over a J") appears backwards: RANK_PLAIN has 9=3 < J=4, so the bot actually discards 9 over J, which loses 0 pts instead of 2 pts. This is the correct behavior.

However, a genuine misalignment exists: in Sun, when the bot cannot win and must discard among, say, {Q(5pts,rank-5), K(4pts,rank-6), J(2pts,rank-4)} the bot throws J first (lowest rank), then Q, then K. Ordered by pure point-minimization it would throw J(2), Q(3), K(4) — same order. So for the plain-suit point-vs-rank alignment, the two orderings agree for all non-T, non-A cards.

The actual divergence is for T vs K: RANK_PLAIN puts K=6 < T=7, meaning the bot throws K (4 pts) before T (10 pts). By point value, this is correct: we want to keep T (10 pts) longer. So this is fine.

**Only one concrete misalignment exists:** in Sun, the bot would discard cards of the lead suit (via the Hokm non-last-seat branch at line 1057–1067) when it shouldn't — that branch is guarded by `contract.type == K.BID_HOKM` (line 1057), so Sun correctly falls through to the bare `lowestByRank(legal, contract)` at line 1068. No Sun-specific discard bug confirmed.

**Recommendation:** The rank-vs-point ordering is mostly safe as coded. The warning is: `lowestByRank` is semantically misleading in can't-win contexts since "lowest rank" (trick power) is not the same as "lowest point value", even though they currently agree. If point tables change, this implicit coupling breaks silently. A separate `lowestByPointValue` helper should be introduced for the discard path to make intent explicit and prevent future regressions.

---

## A-44 — Trick points threshold for "decent points, throw lowest-value loser" in pos-4

**VERDICT: WARNING**

**File:line:** `Bot.lua:1052–1068` (the entire can't-win discard block).

**Evidence:**

The comment at line 1052–1056 reads: "If we're closing the trick (4th seat) and the trick already has **decent points**, throw the lowest-value loser." But the condition at line 1057 is only `if not lastSeat` — there is no threshold gate for trick points at all. The `lastSeat` path (lines 1068) also applies without any points check. The comment implies a threshold exists but no code implements it.

There is no call to `R.TrickPoints(trick, contract)` anywhere inside `pickFollow`. For any trick — whether it has 0 points (all 7/8/9) or 30+ points (A + T + K) — the discard behavior is identical: throw `lowestByRank` of non-trump discardable cards (non-last-seat Hokm), or `lowestByRank(legal)` otherwise.

The consequence: when last-seat cannot beat a trick worth 30+ points (e.g., the trick has A+T of a suit and a K, total 25 pts), the bot discards the lowest-rank card regardless of whether it holds a trump. In Hokm, a trump ruff attempt from pos-4 on a very high-value trick is often correct even when the existing winner is an opponent's A or T — because the trump overcuts everything. The bot misses this opportunity entirely since `pickFollow` never evaluates trump-ruffing at pos-4 when it cannot beat with a same-suit card.

Specifically: the `winners` list at line 964 is built via `wouldWin`, which correctly tests whether a card would beat the current winner. If the bot holds trump and the winning card is a plain-suit A, the trump would win. So trump would appear in `winners` and the bot would take it via `lowestByRank(winners)` at line 1049. This means the real gap is narrower than the prompt suggests — trump ruffing IS covered when the trick is currently won by a non-trump.

However the threshold gap stands: the bot has identical behavior on a 0-point trick and a 30-point trick in the specific scenario where it genuinely cannot win (no card in `winners`). A points threshold at, say, 15+ would allow the bot to play differently (e.g., choose which card to sacrifice vs. keeping a high discard for a later trick). No such threshold exists.

**Recommendation:** Add a `R.TrickPoints(trick, contract)` call in the can't-win block. When `trickPts >= 15` and `lastSeat`, attempt a trump ruff if one exists in `legal` (even if currently losing to a higher trump). This is already partially handled by `wouldWin` for plain-suit winners but not for over-trump situations. Introduce a `highValueTrick` flag to drive separate discard logic.

---

## A-45 — pickFollow void inference cross-check: does follow-logic USE Bot._memory?

**VERDICT: INFO**

**File:line:** `Bot.lua:915–1069` (entire `pickFollow` function).

**Evidence:**

`Bot._memory` is read in two places in `Bot.lua`:
1. `opponentsVoidInAll` (line 272–282) — used only in `pickLead` (line 824–837).
2. `Bot._memory[partner].firstDiscard` — used only in `pickLead` (Fzloky signal, lines 748–773).

`pickFollow` never reads `Bot._memory` at any point. The void table per seat (`Bot._memory[s].void`) is accumulated by `Bot.OnPlayObserved` but is invisible to `pickFollow`.

The prompt's scenario is valid: suppose seat 2 (our partner) is known void in Hearts (they failed to follow a Heart lead earlier). In `pickFollow`, if we are in position 3 and an opponent is currently winning with the T of Hearts, we'd play highest-winner (line 1045). If our partner is void in Hearts and would have played a Heart to win the trick (partner-winning branch would smother), the void info is irrelevant here. But consider: we are seat 1, partner is seat 3 (known void in lead suit), seat 2 (opponent) is currently winning. In this case the prompt's concern is whether we should hold back a trump ruff because partner (playing 4th) could over-ruff for more points. `pickFollow` has no awareness of this.

Concrete impact: in pos-2 with opponent winning, the "second hand low" duck logic (line 979–1025) is active but only considers trump-outstanding count and A/T presence. It has no check for "partner is void here and will probably ruff anyway — let them win with a higher trump than mine". A bot sitting pos-2 with the 9 of trump (high, worth 14 pts as trump) could wastefully ruff when partner (pos-4) holds the J of trump and would over-ruff for 20 pts. This is a genuine strategic gap.

No existing code paths in `pickFollow` reference `Bot._memory` directly.

**Recommendation:** In the pos-2 second-hand-low block (lines 979–1026), add an M3lm/Advanced-gated check: if partner is known void in `trick.leadSuit` AND we hold trump, duck the trump (add trump to non-winners / fall through to lowest-legal). This uses the existing `Bot._memory[partner].void[trick.leadSuit]` field already maintained. Low-impact change with clear correctness benefit.

---

## A-46 — Legal plays list: legalPlaysFor called twice for Saudi Master bots

**VERDICT: INFO**

**File:line:** `BotMaster.lua:499–506` and `Bot.lua:1116–1117`.

**Evidence:**

In `Net.lua`'s `MaybeRunBot`, the dispatch for a Saudi Master seat calls `BM.PickPlay(seat)` first (via `Bot.IsSaudiMaster()`), then falls back to `Bot.PickPlay(seat)` if `BM.PickPlay` returns nil.

`BM.PickPlay` (BotMaster.lua:494–534) builds its own `legal` list at lines 499–506:

```lua
local trick = S.s.trick or { leadSuit = nil, plays = {} }
local legal = {}
for _, c in ipairs(hand) do
    local ok = R.IsLegalPlay(c, hand, trick, S.s.contract, seat)
    if ok then legal[#legal + 1] = c end
end
```

`Bot.PickPlay` (Bot.lua:1110–1124) builds its own `legal` list at lines 1116–1117:

```lua
local legal = legalPlaysFor(hand, trick, contract, seat)
```

where `legalPlaysFor` (Bot.lua:702–709) calls `R.IsLegalPlay` for each card in `hand`.

For a Saudi Master bot where `BM.PickPlay` returns a valid card (the normal path), `Bot.PickPlay` is never reached, so there is no double computation in the common case. The double call only occurs if `BM.PickPlay` returns nil (i.e., BM bails out) and `Bot.PickPlay` is then invoked.

Regarding divergence: both callers pass the same inputs — same `hand` (from `S.s.hostHands[seat]`), same `trick` (from `S.s.trick`), same `contract` (from `S.s.contract`), same `seat`. There is one subtle difference: `BM.PickPlay` uses `S.s.trick or { leadSuit = nil, plays = {} }` as a fallback when `S.s.trick` is nil, while `Bot.PickPlay` passes `trick` (which could be nil) into `legalPlaysFor`, and `R.IsLegalPlay` handles a nil trick as "trick is empty → any card is legal" (Rules.lua:96–98). Both paths produce identical legal lists in practice since `R.IsLegalPlay` with `#trick.plays == 0` returns true for any held card. No functional divergence confirmed.

The double computation is a minor performance concern (32 card evaluations instead of 8) but at WoW addon scale this is negligible.

**Recommendation:** Info-only. No correctness bug. For cleanliness, `BM.PickPlay` could accept a pre-built legal list as an optional parameter so the caller can compute it once. Not urgent.

---

## A-47 — pickLead singleton preference (step 2) before longest-suit preference (step 3)

**VERDICT: WARNING**

**File:line:** `Bot.lua:840–847` (singleton detection), `Bot.lua:849–888` (longest-suit logic).

**Evidence:**

The lead priority in `pickLead` (lines 820–891):
1. Free-trick suit if opponents both void (line 823–837).
2. Singleton low non-trump (line 840–847).
3. Low from longest non-trump suit (line 849–888).
4. Lowest non-trump fallback (line 887).
5. Lowest trump if no non-trump (line 890–891).

Step 2 fires unconditionally for any singleton non-trump card. The only filter is "singleton" and "non-trump". There is no check for the rank of the singleton or whether leading it may be strategically harmful.

The prompt's concern about a singleton K-of-offsuit in Hokm is confirmed: if the bot holds exactly one Heart (e.g., KH) and multiple Spades and Clubs, step 2 fires and leads KH. The opponent now knows the bot is void in Hearts (from playing the K and never following again), and can use Hearts as a trump-forcing lead whenever they want. Furthermore, the K is worth 4 points — it's a mid-value card that the bot sacrifices as a lead rather than preserving it.

More problematically: a singleton A (rank 8 in RANK_PLAIN, 11 pts) would also be led at step 2. An Ace of a non-trump suit is a guaranteed trick-winner that should be cashed at the right moment, not spent as a "singleton lead" to clear one's hand. The A would win the trick but the bot burns a guaranteed 11-point card on trick 1 and telegraphs void status.

In contrast, a singleton 7 or 8 (0 pts, lowest rank) is a reasonable lead: losing 0 pts, establishing a ruff possibility early. The current code makes no distinction between singleton 7 (good singleton lead) and singleton A/K (bad singleton lead).

The correct heuristic for Saudi Hokm convention is: lead singleton LOW cards (7, 8, rarely 9) for ruff setup; hold singleton high cards (A, K, Q, even J) and lead from length instead.

The Advanced tier does not override this path (no `Bot.IsAdvanced()` gate in the singleton block at lines 840–847).

**Recommendation:** Severity warning. Filter the singleton list to only low singletons before applying step 2:

```lua
local LOW_SINGLETON_RANKS = { ["7"]=true, ["8"]=true, ["9"]=true }
local singletons = {}
for _, c in ipairs(nonTrumps) do
    if suitCount[C.Suit(c)] == 1 and LOW_SINGLETON_RANKS[C.Rank(c)] then
        singletons[#singletons + 1] = c
    end
end
```

High singletons (A, K, Q, J, T) should fall through to step 3 (lead low from longest suit) rather than being wasted as early singleton leads.

---

## Summary Table

| Angle | Verdict   | File:line                  | Severity |
|-------|-----------|----------------------------|----------|
| A-43  | WARNING   | Bot.lua:1062–1068          | Warning  |
| A-44  | WARNING   | Bot.lua:1052–1068          | Warning  |
| A-45  | INFO      | Bot.lua:915–1069 (absent)  | Info     |
| A-46  | INFO      | BotMaster.lua:499–506      | Info     |
| A-47  | WARNING   | Bot.lua:840–847            | Warning  |

**Critical findings: 0**  
**Warnings: 3 (A-43, A-44, A-47)**  
**Info: 2 (A-45, A-46)**

Most actionable fixes in priority order:
1. A-47: Filter singleton lead to low ranks only (clear correctness/strategy bug, one-liner fix).
2. A-44: Add trick-point threshold in can't-win discard for trump-ruff consideration.
3. A-43: Introduce `lowestByPointValue` helper to make discard intent explicit and future-proof.
4. A-45: Add void-awareness in pos-2 duck logic (M3lm-gated).
5. A-46: No action required.
