# Wave 4 C5 — Memory Integrity Findings
**Auditor:** C5 (memory integrity continuation)
**Version:** v0.4.4
**Files reviewed:** Bot.lua, Net.lua, BotMaster.lua, State.lua

---

## A-78 — AKA signal back-propagation into pickLead?

**VERDICT: CLEAN — no back-propagation bug**

**Evidence:**

`Bot.PickAKA` (Bot.lua:1078–1108) is called in `Net.lua:MaybeRunBot` at line 3353–3358, AFTER `Bot.PickPlay` (line 3348) has already selected the lead card. The call sequence is:

```
card = B.BotMaster.PickPlay(seat)  -- or falls through
if not card then card = B.Bot.PickPlay(seat) end
...
local akaSuit = B.Bot.PickAKA(seat, card)
```

`PickAKA` receives `card` as its `leadCard` argument and checks only: (a) whether the card is the highest unplayed rank of its suit (`S.HighestUnplayedRank(su) ~= r`), and (b) whether the per-round dedup flag `akaSent[su]` has already been set. It does not modify `card`, does not re-invoke `pickLead`, and does not alter any state that `pickLead` reads (the `akaSent` flag is set here for dedup, but `pickLead` does not read `akaSent`).

`pickLead` (Bot.lua:720–892) is a pure function of `legal`, `contract`, and `seat` — it does not consult `_memory[seat].akaSent`. There is therefore no feedback path from `PickAKA` back into `pickLead`.

**Consistency check on the logic inconsistency worry:** the audit prompt asks whether "bot leads a non-boss card but PickAKA returns non-nil" is possible. It is not: `PickAKA` at line 1092 explicitly checks `S.HighestUnplayedRank(su) ~= r` and returns nil if the lead card is not the current boss of its suit. The gate is accurate.

**Recommendation:** None. The flow is correct.

---

## A-82 — ResetMemory timing relative to deal3 / OnPlayObserved

**VERDICT: CLEAN — reset happens before any new-round plays can arrive**

**Evidence:**

`Bot.ResetMemory` is called at `Net.lua:1364`:

```lua
-- Net.lua:1363-1364  (HostStartRound)
if B.Bot and B.Bot.ResetMemory then B.Bot.ResetMemory() end
S.ApplyStart(roundNum, dealer)
```

This is the very first action inside `N.HostStartRound()`. It precedes `S.ApplyStart`, which resets `s.tricks`, `s.hostHands`, and `s.meldsByTeam`. It also precedes `S.HostDealInitial()` (which populates `s.hostHands` for the new round) and `N.SendTurn` (which triggers the first bot bid). No `OnPlayObserved` call can arrive before `ResetMemory` because:

1. `OnPlayObserved` is called only from `N._OnPlay` (Net.lua:1065–1066), which requires `PHASE_PLAY`.
2. `PHASE_PLAY` is only entered via `S.ApplyPlayPhase()`, which is called from `N.HostFinishDeal()` (Net.lua:1574) — well after the entire bidding pipeline.
3. The redeal path (`N._HostRedeal`) also calls `ResetMemory` (Net.lua:1328) before `S.ApplyStart`.

There is no path through which `deal3`-phase play messages could arrive for the new round before `ResetMemory` runs.

**Recommendation:** None. The ordering is correct.

---

## A-83 — ResetStyle granularity: round-reset must NOT call ResetStyle

**VERDICT: CLEAN — ResetStyle is correctly scoped to new-game only**

**Evidence:**

`Bot.ResetStyle` (Bot.lua:149–151) resets `Bot._partnerStyle` to a fresh per-seat zero table. It is called in exactly one place in Net.lua:

```lua
-- Net.lua:1365-1370  (HostStartRound)
if roundNum == 1 and B.Bot and B.Bot.ResetStyle then
    B.Bot.ResetStyle()
end
```

The guard `roundNum == 1` limits the reset to the very first round of a new game. This matches the comment on `_partnerStyle` at Bot.lua:126: "accumulated ACROSS the entire GAME (not reset per round). Reset on Reset() / new game."

`Bot.ResetMemory` (the per-round reset) at Bot.lua:118–120 only resets `Bot._memory`; it does not touch `Bot._partnerStyle`. No other call site for `ResetStyle` exists in the codebase (confirmed by the grep coverage above).

The `Bot.OnPlayObserved` function (Bot.lua:228–255) accumulates `trumpEarly` / `trumpLate` counters into `_partnerStyle` on every play throughout the entire game, which is the intended cross-round accumulation behavior.

**Minor observation (info):** `S.Reset()` at State.lua:659–664 is called when a `MSG_LOBBY` arrives for a new game (peer side). On the host the equivalent path is `HostStartRound` with `roundNum == 1`. There is no direct call to `Bot.ResetStyle()` from `S.Reset()` itself — style resets are driven entirely from Net.lua. This is architecturally fine since bots only run on the host, but if `S.Reset()` were ever called on the host for a new-game scenario (not a new-round), `ResetStyle` could be missed. At v0.4.4 this path does not exist for the host.

**Recommendation:** None at current. Consider a defensive `Bot.ResetStyle()` inside `S.Reset()` if host-side Reset paths are ever added.

---

## A-86 — mem.played tracking: own-seat cards and suitCardsOutstanding loop

**VERDICT: CLEAN — all four seats' played tables iterated, including own seat**

**Evidence:**

`Bot.OnPlayObserved` (Bot.lua:200–270) is called by Net.lua:1065–1066 for every play dispatched through `N._OnPlay`, including plays by the bot's own seat:

```lua
-- Net.lua:1064-1066
S.ApplyPlay(seat, card)
if B.Bot and B.Bot.OnPlayObserved then
    B.Bot.OnPlayObserved(seat, card, leadBefore)
end
```

There is no seat-filter — `OnPlayObserved` receives `seat` (1–4) and at line 204 does `mem.played[card] = true` into `Bot._memory[seat].played`. This means the bot's own seat's played cards are recorded there just like any other seat's.

`suitCardsOutstanding` (Bot.lua:897–913) iterates all four seats unconditionally:

```lua
if Bot._memory then
    for s = 1, 4 do
        local mem = Bot._memory[s]
        if mem then
            for card in pairs(mem.played) do
                if C.Suit(card) == suit then out = out - 1 end
            end
        end
    end
end
```

The loop starts at `s = 1` and ends at `s = 4` — the calling seat's own plays are included at whatever seat number they live at. The initial `out = 8` and the "own hand" subtraction (`for _, c in ipairs(hand)`) correctly handle the calling bot's current hand. So the total is: 8 − (bot's current cards in suit) − (all observed plays in suit across all seats including bot's own). This is the correct "cards still unknown to us" count.

**Recommendation:** None. The tracking and iteration are correct.

---

## A-90 — S.s.meldsByTeam structure compatibility with meldPins (BotMaster)

**VERDICT: CLEAN — schema is compatible; one minor inefficiency noted**

**Evidence:**

**State.lua schema:** `S.ApplyMeld` (State.lua:998–1034) inserts melds as:

```lua
table.insert(s.meldsByTeam[team], {
    kind = kind, value = value, suit = nsuit,
    top = top, cards = cards, len = #cards, declaredBy = seat,
})
```

The structure is `{ kind, value, suit, top, cards, len, declaredBy }` where `cards` is a Lua array of card strings and `declaredBy` is the seat number (1–4). Teams are keyed as `"A"` and `"B"`.

**BotMaster.lua meldPins:** (BotMaster.lua:161–178) iterates:

```lua
if S.s.meldsByTeam then
    for _, team in ipairs({ "A", "B" }) do
        for _, m in ipairs(S.s.meldsByTeam[team] or {}) do
            if m.declaredBy and m.declaredBy ~= seat
               and m.cards then
                for _, c in ipairs(m.cards) do
                    ...
                end
            end
        end
    end
end
```

This accesses `m.declaredBy` and `m.cards` — both present in the State.lua schema. The team keys `"A"` and `"B"` match exactly. The `or {}` guards against a nil team bucket. The per-card inner loop checks `m.cards` is non-nil before iterating.

No schema mismatch exists. The meldPins build will correctly skip all melds for which `declaredBy == seat` (own melds are already in the bot's hand, not in `unseen`) or `cards == nil` (not possible with the ApplyMeld insert, but guarded defensively).

**Info — O(n²) linear search inside meldPins:** For each meld card `c`, the code performs a linear scan of `unseen` to confirm the card is still in the unseen pool (BotMaster.lua:168–174):

```lua
for _, u in ipairs(unseen) do
    if u == c then
        meldPins[c] = m.declaredBy
        break
    end
end
```

`unseen` can be up to 32 cards (full unplayed deck) and the total number of meld cards across all declared melds in a game is typically 3–12. The worst-case O(m × n) = O(12 × 32) = O(384) comparisons is trivially cheap in Lua at this scale and runs only once per `sampleConsistentDeal` call. Not a real performance concern, but a hash set would be cleaner. Not flagged as a bug.

**Recommendation:** None blocking. The schema is fully compatible and pins will fire correctly.

---

## Summary Table

| Angle | Verdict | Severity | File:Line |
|-------|---------|----------|-----------|
| A-78: AKA back-propagates into pickLead? | CLEAN | — | Bot.lua:1078; Net.lua:3353 |
| A-82: ResetMemory before deal3 plays | CLEAN | — | Net.lua:1364; Net.lua:1372 |
| A-83: ResetStyle not called on round-reset | CLEAN | info | Net.lua:1368 |
| A-86: suitCardsOutstanding own-seat loop | CLEAN | — | Bot.lua:897–913 |
| A-90: meldsByTeam schema vs meldPins | CLEAN | info | BotMaster.lua:161–178; State.lua:1031–1034 |

No critical or warning-severity issues found in this wave. The two info notes (A-83 defensive Reset and A-90 linear scan) are not correctness issues.
