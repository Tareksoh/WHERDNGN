# Wave 5 C1 — Integration Edge Cases
**Codebase version:** v0.4.4
**Reviewer:** Wave 5 C1 (code-review specialist)
**Date:** 2026-05-03

---

## A-93 — scoreUrgency: S.s.target default = 152 in Hokm context

**VERDICT: INFO — default is correct, but the meaning of target vs. HAND_TOTAL_HOKM must not be confused**

**Evidence:**

`Constants.lua:54` — `K.HAND_TOTAL_HOKM = 162` is the *card-trick total for one round* (152 card-points + 10 last-trick bonus).

`State.lua:75` — `s.target = (DB and tonumber(DB.target)) or 152` is the *match-win cumulative score* — a completely separate concept. The field is populated unconditionally at `reset()` time. Every path that reads `s.target` in `scoreUrgency` (`Bot.lua:448`) and `matchPointUrgency` (`Bot.lua:473`) therefore always sees a non-nil number.

`Bot.lua:448` — `local target = (S.s.target or 152)` — the `or 152` fallback is thus dead code, but it is harmless rather than wrong: the fallback value 152 matches the default in `State.lua`, so even if `s.target` were somehow nil the urgency math would produce the same output as the intended path.

No semantic confusion with `HAND_TOTAL_HOKM` exists in any caller: all per-round arithmetic that references 162 points uses `K.HAND_TOTAL_HOKM` directly; all match-win thresholds use `s.target`. There is no evidence of cross-contamination.

**Recommendation:** Remove the dead `or 152` guard in `Bot.lua:448` to eliminate a future maintenance trap (someone could change the State default to a different value and not notice the stale inline fallback). This is cosmetic only.

---

## A-94 — R.Partner, R.TeamOf correctness: seats 1+3 vs 2+4

**VERDICT: PASS — no defect found**

**Evidence:**

`Rules.lua:16-28` — `R.Partner` is implemented as an explicit four-branch if/elseif chain:
- seat 1 → 3, seat 2 → 4, seat 3 → 1, seat 4 → 2.

There is no `seat + 2` arithmetic anywhere in this function; no off-by-one at seat 3 is possible.

`Rules.lua:25-28` — `R.TeamOf` uses an explicit guard: `if seat == 1 or seat == 3 then return "A" end; return "B"`. This is correct for the 1+3 / 2+4 split.

All five bot tiers (`Bot.lua`, `BotMaster.lua`) call only `R.Partner(seat)` and `R.TeamOf(seat)` — no direct arithmetic like `seat + 2` is present in either file. Grepping across the codebase confirms zero raw `seat + 2` patterns used in partnership or team contexts.

The escalation-chain seat assignments in `Net.lua` use `(contract.bidder % 4) + 1` to compute the defender seat — this is `R.NextSeat`, not the partner. That formula is also correct (it wraps seat 4 to seat 1).

**Recommendation:** None. Implementation is correct.

---

## A-95 — PickMelds: first-trick gate (#tricks >= 1 returns empty)

**VERDICT: WARNING — gate is correct in isolation but the interaction with meldsDeclared bookkeeping creates a silent no-op window for bots that haven't yet acted**

**Evidence:**

`Bot.lua:1138` — `if (#(S.s.tricks or {})) >= 1 then return {} end`

The comment on lines 1133-1137 is accurate: `S.s.tricks` accumulates *completed* tricks; a trick only enters that array after all four plays land and the trick is resolved. Therefore, throughout trick 1 (while the trick is in progress), `#S.s.tricks == 0`, and the gate does not fire for any seat — the first bot in seat 1, the last bot in seat 4, all see `#tricks == 0` and can declare melds. After trick 1 closes, `#tricks == 1` and the gate correctly blocks. This part of the logic is sound.

The integration concern is in `Net.lua:3332-3338` (MaybeRunBot play branch):

```
if not S.s.meldsDeclared[seat] then
    local melds = B.Bot.PickMelds(seat)
    for _, m in ipairs(melds) do
        S.ApplyMeld(seat, m.kind, m.suit, m.top, ...)
        N.SendMeld(seat, m)
    end
    S.s.meldsDeclared[seat] = true
end
```

`meldsDeclared[seat]` is set to `true` regardless of whether `PickMelds` returned any melds or an empty table. If bot seat X has `#tricks >= 1` at call time and `PickMelds` returns `{}` (gate fired), the bot is silently marked as having declared, which is correct. However, consider the race: if a bot's first MaybeRunBot call runs *after* trick 1 has already closed (e.g., because the three human or bot co-players all played in quick succession and trick resolution plus the next-turn dispatch occurred before this bot's BOT_DELAY_PLAY timer fired), the bot will see `#tricks == 1`, get an empty meld list, be marked declared, and permanently forfeit its meld window — with no error or warning.

This is not a theoretical concern: `BOT_DELAY_PLAY = 1.2` seconds. If the three seats before this bot all played within 1.2 s total (common in an all-bot game), the timing window is real.

**File:line:** `Bot.lua:1138`, `Net.lua:3332`

**Recommendation (warning severity):** Log a debug message when `PickMelds` is called after `#tricks >= 1` so the condition is observable in test runs. Longer-term, consider adding a per-round meld pre-computation at the start of the play phase (before the first BOT_DELAY_PLAY timer fires) so the meld declaration is decoupled from the play-turn timer.

---

## A-96 — PickTakweesh: rate decay by trick number and stale-illegal recheck

**VERDICT: WARNING — a surviving illegal play is rechecked and the rate at which the bot "misses" it decays correctly, but the scan always finds the FIRST illegal play and never revisits the decision**

**Evidence:**

`Bot.lua:1332-1353` — `completed = #(S.s.tricks or {})` is evaluated fresh on each call to `PickTakweesh`. At completed=0, rate=0.60; the table caps at index 7, with `or 0.40` fallback for any out-of-range key. At trick 1 in progress (completed=0) the rate is correctly 0.60.

The scan logic at lines 1341-1348 always finds `found` = the *first* illegal play anywhere in `S.s.tricks` or `S.s.trick.plays`. If `math.random() >= rate` on a given bot turn (the bot "doesn't notice"), the function returns nil without marking anything. On the next trick, `completed` is higher, `rate` is lower, and the same illegal play is found again and subjected to the new (lower) probability.

This means a bot that fails to call Takweesh at trick 0 (40% miss chance) will get another chance at trick 1 at 55% catch rate, then 45%, etc. There is no "forget" mechanism — the bot re-evaluates the same illegal play on every subsequent turn. The probability curve thus represents cumulative detection probability across turns, not a per-turn cliff. This is the intended behavior per the design comment.

One genuine edge: the `or 0.40` fallback at `Bot.lua:1333` for an out-of-range `completed` key means that after trick 7 (completed=8), the bot has a 40% catch rate rather than the documented 5% tail-off. In an 8-trick hand, completed can be 7 at most before the last card is played, so this fallback only fires in edge cases or if the table is accidentally extended. The `TAKWEESH_RATE_BY_TRICK` table covers indices 0-7 (8 entries), so `completed=7` is the last legitimate index. The fallback is reached at completed=8, which only happens if `#S.s.tricks` reaches 8 (all tricks done) — at that point the round is over and PickTakweesh is never called. The fallback is thus unreachable in normal play.

**File:line:** `Bot.lua:1324-1353`

**Recommendation (info severity):** Document or assert that `TAKWEESH_RATE_BY_TRICK` uses 0-based indexing up to 7, and that completed=8 is unreachable when the function is called. The fallback value of 0.40 looks like a copy-paste of an early default rather than a deliberate "off the edge" value; changing it to 0.0 would make the unreachable case explicit.

---

## A-97 — sunStrength invoked for Hokm-contract PickDouble/Triple/Four/Gahwa

**VERDICT: CRITICAL — Hokm defenders with strong trump but weak side suits are systematically blocked from reaching the Bel threshold**

**Evidence:**

`Bot.lua:1154-1162` — `PickDouble` (Bel) evaluates:
```lua
local strength = sunStrength(hand)
if contract.type == K.BID_HOKM and contract.trump then
    local trumpStr = suitStrengthAsTrump(hand, contract.trump)
    strength = strength + trumpStr * 0.5
end
```

`Bot.lua:1191-1194` — `escalationStrength` (used by PickTriple/PickFour/PickGahwa) evaluates:
```lua
local strength = sunStrength(hand)
if contract.type == K.BID_HOKM and contract.trump then
    strength = strength + suitStrengthAsTrump(hand, contract.trump)
end
```

Consider a pure Hokm-context defender hand: J+9+A of trump (suitStrengthAsTrump ≈ 20+14+11+10[J+9 synergy] = 55), with four low-ranked side-suit cards (7/8 in each remaining suit). For such a hand:

- `sunStrength` will score the low side cards at ~2 each (no A/T/K honors), total side-suit contribution ≈ 8. With Advanced mode, the four-suit penalty fires: each suit without an honor loses 10 points, capped at 18, so `sunStrength` → max(8 - 18, 8 - 18) ≈ -10 (floored by the cap at `s - min(penalty, 18)` → roughly -10 to 0).
- Adding `trumpStr * 0.5` for PickDouble: 55 * 0.5 = 27.5. Total ≈ 17–27.
- Adding `partnerBidBonus` (up to +20) and `partnerEscalatedBonus` (up to +13): maximum achievable ≈ 60.
- `K.BOT_BEL_TH = 70` (Constants.lua:252). After jitter (±10) the threshold can be as low as 60.

So a Hokm defender holding J+9+A of trump (which is an extremely strong defensive holding — three of the four top trump cards) can reach the Bel threshold *only* in the best-case scenario where jitter goes to -10 AND both partner bonuses are maxed. In any typical scenario, such a hand is blocked from Beling.

The asymmetry is intentional at the formula level (sunStrength was designed for Sun contract evaluation; it naturally undercounts pure-trump Hokm strength), but the weight of 0.5 on `trumpStr` inside `PickDouble` is too conservative. `escalationStrength` uses a full 1.0 weight for PickTriple/PickFour/PickGahwa, creating an inconsistency: a bot can decide to skip Bel (because 0.5 weight is too low to clear 70) but then be willing to Triple if the opponent does Bel first (because 1.0 weight now clears 90). The logical implication — "I would have skipped Bel but if they Bel I'll Triple" — is strategically incoherent and will produce Triples from bots that should have Beled and wouldn't have.

Additionally, `escalationStrength` for PickFour uses full `trumpStr` weight (1.0) and threshold 110, which is reachable for pure-trump hands (55 trump + up to ~25 side honors + bonuses ≈ 80–110). So the Four/Gahwa escalation correctly captures very-strong-trump hands, but the Bel entry gate at 0.5 weight quietly filters them out before the chain even starts.

**File:line:** `Bot.lua:1161` (0.5 weight in PickDouble), `Bot.lua:1193-1194` (1.0 weight in escalationStrength), `Constants.lua:252` (BOT_BEL_TH = 70)

**Recommendation (critical severity):**
1. Raise the trump weight in `PickDouble` from `0.5` to `1.0` to match `escalationStrength`. This aligns the Bel entry condition with the Triple/Four/Gahwa conditions and prevents the logical incoherence where a bot skips Bel but Triples.
2. Alternatively, lower `K.BOT_BEL_TH` from 70 to ~55 to account for the 0.5 discount on trump strength for Hokm-context Bels. This preserves the intent that Bel requires a weaker standard than Triple, while ensuring pure-trump defenders can still reach the threshold.
3. If the intent is to keep Bel harder than Triple (good conservative design), document the asymmetry explicitly in the comment block on `PickDouble` so future auditors don't confuse the discount with a bug.

---

## Summary Table

| ID   | Severity | File:Line                    | Title                                      |
|------|----------|------------------------------|--------------------------------------------|
| A-93 | info     | Bot.lua:448                  | Dead `or 152` fallback; s.target always set |
| A-94 | pass     | Rules.lua:16-28              | R.Partner / R.TeamOf correct               |
| A-95 | warning  | Bot.lua:1138, Net.lua:3332   | Meld window silently lost if trick 1 closes before bot's timer fires |
| A-96 | info     | Bot.lua:1324-1353            | Fallback rate 0.40 at completed=8 (unreachable) |
| A-97 | critical | Bot.lua:1161, Bot.lua:1193   | 0.5 vs 1.0 trump-weight asymmetry blocks Hokm defenders from Beling |
