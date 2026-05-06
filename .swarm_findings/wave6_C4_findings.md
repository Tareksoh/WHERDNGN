# Wave 6 C4 — Human Play Mistake / Signal Taxonomy (Batch D)

Angles B-35 through B-39. Codebase v0.4.4. All file:line references are to absolute paths.

---

## B-35 — Exploiting human predictable second-seat ducking

**MISTAKE/SIGNAL:** Humans at position 2 (second to play in a trick) habitually play their
lowest legal card even when holding A/T, deferring to partner at position 3/4.

**FREQUENCY:** Common in Saudi Baloot convention; "second hand low" is a near-universal
taught heuristic for beginners and intermediate players.

**BOT-EXPLOITS-IT:** Partially, but not strategically from position 3.

The bot already implements "second hand low" for its own position-2 decisions
(`C:/CLAUDE/WHEREDNGN/Bot.lua:968-1026`, `pos == 2` branch in `pickFollow`). It ducks
unless it holds a `sureStopper` (last trump when only 1 remains, or A/T of led suit).
However, there is no counter-logic exploiting the fact that a *human* at pos 2 also tends
to duck. Specifically: when the bot is at position 3 and the human at pos 2 has just played
low, the bot should recognize that the human's low play does NOT necessarily mean the human
lacks a high card in the suit — it is just as likely to be a conventional duck. The bot's
pos-3 logic (`C:/CLAUDE/WHEREDNGN/Bot.lua:1027-1045`) always plays "highest winner" at
pos 3, which is correct mechanically, but it does not reason: "the human at pos 2 ducked,
so I should commit a stronger card to guarantee the trick rather than a minimal winner."
More critically, `_partnerStyle` (`C:/CLAUDE/WHEREDNGN/Bot.lua:138-147`) tracks only
`bels, triples, fours, gahwas, trumpEarly, trumpLate` — there is **no** per-seat duck
frequency counter (no `duckLow`, `pos2Low`, or equivalent field). The bot cannot
distinguish a human who always ducks from one who only ducks when genuinely weak.

**file:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:138-147` (`emptyStyle`), `968-1026` (pos-2 own
duck logic), `1027-1045` (pos-3 follow — no human-duck adjustment).

**Fix:** Add `duckCount` and `duckOpportunity` counters to `emptyStyle` for each seat.
In `OnPlayObserved`, when `pos == 2` (second play of trick) and the card played is NOT a
winner (rank < current leader), increment `duckCount[seat]`. Track `duckOpportunity`
whenever the seat had a legal winner available (requires inspecting `hostHands[seat]`
at call time — host-only). In `pickFollow` at pos 3, when the previous pos-2 player is a
known high-frequency duck human, prefer committing a card one rank higher than the minimum
winner instead of the cheapest winner.

---

## B-36 — Human tendency to lead partner's bid suit back

**MISTAKE/SIGNAL:** Human players, upon winning a trick, frequently return to the suit
their partner originally bid as Hokm trump on the next non-trump lead opportunity.

**FREQUENCY:** Very common at novice/intermediate level; returning "partner's suit" is an
explicit bidding convention taught in Saudi Baloot guidance.

**BOT-EXPLOITS-IT:** No. The bot has zero logic reading or anticipating human suit-return
patterns.

`_partnerStyle` contains no `suitReturnCount`, `returnedBidSuit`, or analogous field
(`C:/CLAUDE/WHEREDNGN/Bot.lua:138-147`). `OnPlayObserved` records every card into
`mem.played` and infers voids via `mem.void`, but it does not cross-reference "is this the
same suit the partner bid as Hokm?" or count how many times a seat has returned the
partner-bid suit after winning a trick (`C:/CLAUDE/WHEREDNGN/Bot.lua:200-270`). The
`pickLead` function (`C:/CLAUDE/WHEREDNGN/Bot.lua:720-892`) at M3lm tier already reads
`S.s.bids` for `partnerBidBonus` in the escalation path, but does not use bid history
to anticipate that an opponent human's next lead will be the partner-bid suit. The bot at
pos 4 therefore cannot pre-plan "discard from the partner-bid suit since it's coming back
to me anyway."

**file:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:138-147` (emptyStyle — no return counter),
`200-270` (OnPlayObserved — no suit-return tracking), `720-892` (pickLead — no anticipation
of human return lead).

**Fix:** In `emptyStyle`, add `partnerSuitReturns = 0` and `partnerSuitLeadOpportunities = 0`
per seat. In `OnPlayObserved`, when `leadSuit == nil` (the card opens a trick — it's a lead)
and `C.Suit(card)` matches `S.s.contract.trump` or the original Hokm bid suit for that seat's
partner, increment the counter. In `pickFollow` at pos 4, when the current trick's lead suit
matches the expected human-return pattern for the pos-1 seat, factor this into the discard
choice (do not waste a high card in that suit since the human is "gifting" tricks there).

---

## B-37 — Human "honor-trap" lead: leading K hoping to capture A

**MISTAKE/SIGNAL:** Humans lead the K of a side suit expecting the bot (or opponent holding
A) to "cover" with the A, wasting it to beat the K. The human then walks the Q/J as boss.

**FREQUENCY:** Moderate; a known intermediate-level probe play in trick-taking games.

**BOT-EXPLOITS-IT:** Yes — the human's trap succeeds against the bot, and the bot has no
counter-strategy.

The bot's `pickFollow` always plays its cheapest winner when at pos 2/4 and the trick has
a winner available (`C:/CLAUDE/WHEREDNGN/Bot.lua:1048-1049`). Because A is the highest
rank by `K.RANK_PLAIN` (`C:/CLAUDE/WHEREDNGN/Constants.lua:51`), and K would be a legal
winner the bot could beat with A, the bot at pos 2 with A will duck only if there is a
"sure stopper" ambiguity check — but the pos-2 `sureStopper` path at
`C:/CLAUDE/WHEREDNGN/Bot.lua:1003-1012` actually **forces** the bot to play its A when
that A is in the led suit and ranks as A/T: `if C.Suit(c) == trick.leadSuit and (r == "A" or r == "T") then sureStopper = c`. This means a human leading K will always extract the
bot's A at pos 2, succeeding in the honor-trap. The bot's "second hand low" exception
specifically carves out A/T to avoid ducking them — but this carve-out is precisely what
makes the trap work. There is no logic to recognize "an opponent leads K into my A, which
is a known human trap pattern; I could duck and let partner handle." Nor does `_partnerStyle`
track `kLeadCount` or `honorTrapAttempts` per seat.

**file:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:1003-1012` (sureStopper forces A play at pos 2),
`1048-1049` (cheapest winner default — A always wins over K), `C:/CLAUDE/WHEREDNGN/Constants.lua:51` (K.RANK_PLAIN — A outranks K absolutely).

**Fix:** Add optional M3lm/SaudiMaster-gated K-lead detection: when at pos 2, trick.plays[1]
is a K (by rank string), no trump has been played, and the bot holds A of the same suit,
consider ducking if (a) the bot has already counted >= 2 king-leads from this seat across
the game (per `_partnerStyle`), AND (b) the bot's partner has not yet played and might hold
Q/J as a cheaper cover. This requires adding `kLeadCount[seat]` to `emptyStyle` and
incrementing it in `OnPlayObserved` when the played card is a K and it's a lead (leadSuit
== nil on that call).

---

## B-38 — Human "denial" discard: throwing A of side suit defensively

**MISTAKE/SIGNAL:** Humans sometimes discard a side-suit Ace (onto an opponent's or neutral
trick) to avoid being "end-played" into leading that suit later. The A goes to waste
deliberately.

**FREQUENCY:** Rare and advanced; seen in experienced Saudi Baloot players when they hold
a bare A in a suit where leading it later would be forced and disadvantageous.

**BOT-EXPLOITS-IT:** Memory update is CORRECT but the bot cannot predict or anticipate the
pattern.

When a human discards an A off-suit (e.g., throws AH onto a spade trick because void in
spades), `OnPlayObserved` correctly records `mem.played["AH"] = true` at
`C:/CLAUDE/WHEREDNGN/Bot.lua:204`. The `suitCardsOutstanding` function at
`C:/CLAUDE/WHEREDNGN/Bot.lua:897-913` then subtracts that from the suit's outstanding
count (starting from 8, minus own cards, minus all played). So the bot's count of
outstanding hearts correctly decreases by 1 — **the memory update is correct** for this
case. However, the bot does not recognize that a prematurely-discarded A is itself an
exploitable signal: the human did NOT have a better card to throw, meaning they were void in
the led suit AND chose to sacrifice the A rather than a low card, implying they consider
the suit dangerous. The bot never flags or reads this pattern. `_partnerStyle` has no
`denialDiscardCount` or `prematureAceCount` field. `opponentsVoidInAll`
(`C:/CLAUDE/WHEREDNGN/Bot.lua:272-282`) only checks `mem.void[suit]`, not whether the A
of that suit has been discarded, so the bot doesn't upgrade its free-trick assessment for
that suit.

**file:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:204` (played recorded correctly),
`897-913` (suitCardsOutstanding — correctly decrements),
`272-282` (opponentsVoidInAll — no A-discard upgrade),
`138-147` (emptyStyle — no prematureAce counter).

**Fix (minor):** Add `prematureAceDiscard[suit]` flag per seat in `emptyStyle`. In
`OnPlayObserved`, when `leadSuit` is set, `cardSuit != leadSuit`, and `C.Rank(card) == "A"`,
set the flag. In `pickLead`, if an opponent has a `prematureAceDiscard[suit]` flag, that
suit is now a free-trick candidate even without the full `opponentsVoidInAll` check —
adjust `opponentsVoidInAll`-equivalent logic to recognize single-opponent A-discard as a
partial free-trick opportunity.

---

## B-39 — Human wantOpen leaks: hesitation timing on escalation decisions

**MISTAKE/SIGNAL:** Humans who hesitate before Beling (slow response to the escalation
window) signal a borderline hand; humans who Bel immediately signal confidence.

**FREQUENCY:** Present in human play; a well-known "tell" in live Saudi Baloot.

**BOT-EXPLOITS-IT:** Not implemented at all. No timing data is captured anywhere in the
codebase.

The escalation window for Bel is driven by `N.StartBelTimer` in
`C:/CLAUDE/WHEREDNGN/Net.lua:2787-2797`. This arms a `C_Timer.NewTimer(K.TURN_TIMEOUT_SEC,
...)` (60s AFK), but no timestamp of when the window *opened* is stored. `N.SendTurn` at
`C:/CLAUDE/WHEREDNGN/Net.lua:144-149` records nothing about when the turn began. `S.s` state
(see `C:/CLAUDE/WHEREDNGN/State.lua:31-126`) has no `turnOpenedAt`, `belWindowOpenedAt`, or
equivalent timestamp field. The only `GetTime()` usage in State.lua is for the redeal
announcement banner (`ts` field at `State.lua:144`) and meld-hold timer
(`State.lua:809`), neither of which is turn-response timing. `_partnerStyle`
(`C:/CLAUDE/WHEREDNGN/Bot.lua:138-147`) stores no `avgBelResponseMs` or `quickBelCount`
field. When `N._OnDouble` fires (`C:/CLAUDE/WHEREDNGN/Net.lua:801-828`), there is no
elapsed-time calculation. The `wantOpen` response from `Bot.PickDouble` is transmitted as
part of the escalation message but its timing is never measured. This exploitation
opportunity is **completely unimplemented**.

**file:line:** `C:/CLAUDE/WHEREDNGN/Net.lua:144-149` (SendTurn — no timestamp stored),
`C:/CLAUDE/WHEREDNGN/Net.lua:2787-2797` (StartBelTimer — arms 60s AFK, no open-time
capture), `C:/CLAUDE/WHEREDNGN/Net.lua:801-828` (_OnDouble — no elapsed-time read),
`C:/CLAUDE/WHEREDNGN/Bot.lua:138-147` (emptyStyle — no timing fields),
`C:/CLAUDE/WHEREDNGN/State.lua:31-126` (state reset — no turnOpenedAt field).

**Fix:** In `N.SendTurn` and `N.StartBelTimer`, store `S.s.turnOpenedAt = GetTime()` (or a
new `s.escalationOpenedAt` field). In `N._OnDouble` / `_OnTriple` / etc., compute
`elapsed = GetTime() - (S.s.escalationOpenedAt or 0)` and pass to
`Bot.OnEscalation(seat, kind, elapsed)`. In `emptyStyle`, add `quickBelCount` (elapsed < 5s)
and `slowBelCount` (elapsed > 20s). Gate exploitation in `pickLead` / `pickFollow` at
SaudiMaster tier: if an opponent has `quickBelCount >= 2`, they are a confirmed confident
Bel-er — avoid leading tricks into them; if `slowBelCount >= 2`, they borderline-Beled —
their defensive hand is likely weaker than the raw escalation count suggests.

---

## Summary Table

| Angle | Mistake/Signal | Frequency | Bot Exploits? | Key File:Line |
|-------|---------------|-----------|---------------|---------------|
| B-35 | Human pos-2 duck even with A | Common | Partially (own duck only; no opponent duck tracking) | Bot.lua:138-147, 968-1026 |
| B-36 | Human returns partner's bid suit | Very common | No | Bot.lua:138-147, 200-270, 720-892 |
| B-37 | Human K-lead honor trap extracts bot A | Moderate | Trap succeeds (bot always plays A at pos-2 per sureStopper exception) | Bot.lua:1003-1012, Constants.lua:51 |
| B-38 | Human denial A-discard | Rare/Advanced | Memory update correct; pattern not anticipated | Bot.lua:204, 897-913, 272-282 |
| B-39 | Human Bel hesitation timing | Common tell | Not implemented — zero timing infrastructure | Net.lua:144-149, 2787-2797, Bot.lua:138-147 |
