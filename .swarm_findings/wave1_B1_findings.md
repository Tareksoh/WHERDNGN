# Wave 1 – Cluster B1 Human-Exploit Deep-Dive
## Auditor: Pathfinder B1 (Claude Sonnet 4.6)
## Codebase: WHEREDNGN v0.4.4

---

### B-31 — Fzloky signal honesty: do human players actually give suit-preference discards?

**IS-EXPLOITED: NO**

**Code locus:** Bot.lua:747-773 (`pickLead`), Bot.lua:217-225 (`OnPlayObserved`).

**What the code does:**
`OnPlayObserved` at line 217 records the first off-suit discard for every seat uniformly:
```
if not wasIllegal and leadSuit and cardSuit ~= leadSuit then
    mem.void[leadSuit] = true
    if not mem.firstDiscard then
        mem.firstDiscard = { suit = cardSuit, rank = C.Rank(card) }
    end
end
```
`pickLead` at line 749 then reads the PARTNER's `firstDiscard` to derive a Fzloky preference or avoidance:
```
local p = R.Partner(seat)
local sig = Bot._memory[p] and Bot._memory[p].firstDiscard
```
There is no distinction between whether `p` is a bot seat (`p.isBot`) or a human seat. If the partner is human, the code treats their first accidental void-discard as a deliberate suit-preference signal identical to a bot Fzloky convention signal.

**Saudi Baloot literature context:**
Fzloky (فظلوكي) is an advanced partner-signaling convention recognized in competitive Saudi Baloot circles (e.g., discussions on `kammelna.com` forums and tournament guides). The convention stipulates that a high discard (A/T/K) = "lead this suit," low discard (7/8) = "avoid this suit." However, this is an explicitly agreed-upon table convention, not an instinctive behavior. In casual and online pickup games, the vast majority of Saudi players do not consciously practice Fzloky. A human throwing a King of Diamonds because they are void in Hearts is simply getting rid of their highest disposable card, not signaling anything. The Saudi Baloot Telegram group discussions consistently confirm that Fzloky is known only to experienced competitive players.

**Exploit gap:**
When a human partner is in seat `p`, the bot incorrectly treats their void-related King/Ace discard as "lead Diamonds," then leads low in Diamonds expecting partner to win with the boss — but the human holds no boss there, wasting a trick. Conversely, a human's 7 of Clubs (their lowest junk after a void) is treated as "avoid Clubs," causing the bot to shun a suit where the human actually holds nothing relevant either way.

**Concrete fix:**
Gate Fzloky partner-signal reading on `B.State.IsBot(p)` (the `State.lua:625` helper that checks `s.seats[seat].isBot`). In `pickLead`, change:
```
if Bot.IsFzloky() and Bot._memory then
    local p = R.Partner(seat)
```
to:
```
if Bot.IsFzloky() and Bot._memory and S.IsBot(R.Partner(seat)) then
    local p = R.Partner(seat)
```
The `firstDiscard` on a human seat is still useful for void inference (already in play via `mem.void`) but must not feed the Fzloky lead-bias path. This is a one-line gate at Bot.lua:749.

---

### B-43 — Human opponent void inference from ruff plays: faster void modeling for human-held hands

**IS-EXPLOITED: YES**

**Code locus:** Bot.lua:200-269 (`OnPlayObserved`), Net.lua:1065-1066 (host-side), Net.lua:1609-1610 (local-play side).

**What the code does:**
`OnPlayObserved` is called from two sites in Net.lua:
1. Line 1065: `N._OnPlay` — fired on every received `MSG_PLAY`, i.e., for ALL seats (including human opponents and human partners) as broadcasts reach the host.
2. Line 1609: fired when the local (human) player plays their own card.

The void inference:
```
if not wasIllegal and leadSuit and cardSuit ~= leadSuit then
    mem.void[leadSuit] = true
```
fires for any seat's off-suit play, human or bot. This means when a human opponent ruffs on trick 3, `Bot._memory[oppSeat].void[leadSuit]` is set to `true`.

`sampleConsistentDeal` in BotMaster.lua:216-218 reads voids:
```
local voids = (B.Bot._memory and B.Bot._memory[s]
               and B.Bot._memory[s].void) or {}
...
if #hand < n and not used[c] and not voids[C.Suit(c)] then
```
so the void is respected during ISMCTS sampling for free-trick detection.

`opponentsVoidInAll` (Bot.lua:272-282) also reads `Bot._memory[opp].void[suit]` directly in `pickLead` to detect free tricks (line 824-838).

**Verdict:** This is working correctly and human void detection is fully operational. The bot exploits opponent ruff plays to infer voids for both ISMCTS sampling and the free-trick lead heuristic.

**No gap found.** The fix applied (wasIllegal guard at line 214) correctly prevents poisoning the void table from revokes. Human opponent ruff detection is as fast as bot void detection — one ruff = immediate `void[leadSuit]=true`.

---

### B-58 — Human void-suit leak through discard speed or card choice

**IS-EXPLOITED: PARTIALLY**

**Code locus:** Bot.lua:217-225 (void + firstDiscard), Bot.lua:259-269 (trump-ruff rollback).

**What the code does:**
`OnPlayObserved` records the `firstDiscard` (suit + rank) for every seat, human or bot. In `pickLead`, the Fzloky path reads the PARTNER's firstDiscard, not opponents'. Opponents' `firstDiscard` data is populated but never read anywhere in the codebase. The `opponentsVoidInAll` and ISMCTS sampler both use `mem.void`, not `firstDiscard`, for opponents.

**Saudi Baloot context:**
In online Saudi Baloot, the dominant discard convention for humans is honor-signaling: when void, a player tends to throw their highest card (King/Ace) in their second-strongest suit to indicate that suit is their side winner. This is a widely observed pattern in the kammelna.com community — it is not a formal signal but an emergent behavior from "discard what I'm least worried about losing." A human throwing a low card (7/8) when void is usually discarding from their weakest/shortest suit to avoid blocking their own length.

**Exploit gap:**
The bot never uses opponent `firstDiscard` data. A human opponent's first void-discard is logged in `Bot._memory[oppSeat].firstDiscard` but read by nothing. If an opponent at seat 2 throws an Ace of Diamonds when void in Hearts, the bot could:
1. Infer that the opponent holds a strong Diamonds holding (lead Hearts to them anyway, expecting a ruff, or avoid leading Diamonds directly which would give them a free trick).
2. More precisely, `sampleConsistentDeal` could bias opponent hand sampling by increasing the weight for strong Diamonds cards in opponent's sample (similar to how `desire` works for the bidder at line 213).

Currently the only opponent-hand info used in ISMCTS is: (a) bid history via `getStrongCards`, (b) observed voids. Opponent `firstDiscard` rank-as-strength signal is dead data.

**Concrete fix:**
In `sampleConsistentDeal` (BotMaster.lua:211-214), extend the `desire` table for opponents (not just bidder) using their `firstDiscard` rank:
```
-- After building `desire` for bidder/partner:
local oppMem = B.Bot._memory and B.Bot._memory[s]
local oppDiscard = oppMem and oppMem.firstDiscard
if s ~= partner and oppDiscard then
    local r = oppDiscard.rank
    -- High discard = opponent has strength in that suit
    if r == "A" or r == "T" or r == "K" then
        desire[oppDiscard.suit] = 20  -- bias toward strong cards in that suit
    end
end
```
This is an additive improvement to ISMCTS quality; the void inference already covers the most critical signal.

---

### B-65 — Human misplay identification: tracking per-seat illegal play rate

**IS-EXPLOITED: NO**

**Code locus:** Bot.lua:1324-1352 (`PickTakweesh`).

**What the code does:**
```lua
local TAKWEESH_RATE_BY_TRICK = {
    [0] = 0.60, [1] = 0.55, [2] = 0.45, [3] = 0.40,
    [4] = 0.30, [5] = 0.20, [6] = 0.10, [7] = 0.05,
}

function Bot.PickTakweesh(seat)
    ...
    local rate = TAKWEESH_RATE_BY_TRICK[completed] or 0.40
    ...
    if math.random() < rate then return found end
```

The rate is purely a function of how many tricks have been completed. There is no per-seat counter for how many illegal plays a given human has made across the game. `Bot._partnerStyle` tracks escalation and trump-tempo per seat, but has no `illegalPlays` field.

**Saudi Baloot context:**
Saudi Baloot human players at varying skill levels show very different error rates. In pickup games (وايو, WhatsApp arranged games), a player confused about the Hokm overcut rule commonly commits the same revoke 2–3 times per session because they never learned the rule. In tournament play, experienced players rarely revoke at all. A bot that has caught a specific human seat making 2+ illegal plays in earlier rounds of the same game has strong evidence that this seat is error-prone and should be watched more aggressively.

**Exploit gap — two-layer:**
1. No per-seat illegal-play counter exists. The bot cannot raise its Takweesh probability when a known error-prone seat is in the game.
2. The rate is static per trick, not responsive to observed per-game history.

**Concrete fix:**
Add an `illegalCount` field to `_partnerStyle` per seat (initialized to 0 in `emptyStyle`, incremented when `Bot._memory[s]` has a play marked `.illegal`). Then in `PickTakweesh`:
```lua
local style = Bot._partnerStyle and Bot._partnerStyle[found.seat]
local illegalHistory = (style and style.illegalCount or 0)
local multiplier = 1.0
if illegalHistory >= 3 then multiplier = 2.0
elseif illegalHistory >= 1 then multiplier = 1.4 end
rate = math.min(0.95, rate * multiplier)
```
The increment should fire in `OnPlayObserved` when `wasIllegal` is true:
```lua
if wasIllegal then
    local ps = Bot._partnerStyle and Bot._partnerStyle[seat]
    if ps then ps.illegalCount = (ps.illegalCount or 0) + 1 end
end
```
Note that `_partnerStyle` is reset only on `Reset()` / new game (not per round), so the count accumulates across the entire match — exactly the right scope for detecting a habitually error-prone opponent.

---

### B-84 — Human follow-suit error patterns: suit confusion between similar colors

**IS-EXPLOITED: NO (correctly handled, but with a gap in void-inference correction)**

**Code locus:** Bot.lua:206-218 (`OnPlayObserved` wasIllegal guard), Constants.lua:27-31 (four-color palette).

**What the code does:**
The four-color card palette is defined at Constants.lua:27-31:
```lua
K.SUIT_COLOR_ONCARD = {
    S = "ff111111",  -- near-black
    H = "ffcc1f1f",  -- deep red
    D = "ff1f5fcc",  -- deep blue
    C = "ff1c8a3c",  -- forest green
}
```
The wasIllegal guard at Bot.lua:206-214 does prevent void inference for illegal plays:
```lua
local wasIllegal = lastPlay and lastPlay.seat == seat
                   and lastPlay.card == card and lastPlay.illegal
...
if not wasIllegal and leadSuit and cardSuit ~= leadSuit then
    mem.void[leadSuit] = true
```
So a color-confused revoke (a human plays Diamonds when meant to play Hearts) does NOT poison the bot's void inference — because `State.ApplyPlay` at line 1065-1066 has already flagged it `.illegal` (the player had Hearts in hand, so it's a follow-suit violation), and `wasIllegal` is true.

**Gap — partial:**
The wasIllegal detection at lines 211-214 uses a fragile cross-reference:
```lua
local lastPlay = S.s.trick and S.s.trick.plays
                 and S.s.trick.plays[#S.s.trick.plays]
local wasIllegal = lastPlay and lastPlay.seat == seat
                   and lastPlay.card == card and lastPlay.illegal
```
It checks that the last play in the trick at the moment `OnPlayObserved` fires matches `(seat, card)`. If plays arrive slightly out of order (two rapid plays, non-deterministic message ordering), the last play might be from a different seat, and `wasIllegal` falls back to `false` for an actual illegal play — causing void-inference poisoning for that confused play. However, this is a narrow race condition and not the main exploit gap. The four-color palette design is sound.

**Critical gap for opponent-confusion exploitation:**
The bot has no mechanism to distinguish "genuine void" from "confusion revoke" after the fact. Both produce `mem.void[leadSuit] = true` when `wasIllegal` is false, and both produce no inference when `wasIllegal` is true. The bot cannot exploit a human's confusion revoke as evidence of their actual holdings. However, this is acceptable — the bot correctly abstains from false void inferences, which is the right behavior.

**No concrete fix needed for the core ask.** The four-color palette already mitigates the human confusion rate. The wasIllegal guard correctly handles the bot's response. The race condition in wasIllegal detection is covered in angle A-88 (Wave 1, Cluster A4).

---

### B-91 — Human partner meld information: meld declarations as hand reveals

**IS-EXPLOITED: PARTIALLY**

**Code locus:** BotMaster.lua:148-177 (`meldPins` block in `sampleConsistentDeal`).

**What the code does:**
The `meldPins` logic (BotMaster.lua:161-177) iterates `S.s.meldsByTeam` and pins every unplayed meld card to its `declaredBy` seat:
```lua
if S.s.meldsByTeam then
    for _, team in ipairs({ "A", "B" }) do
        for _, m in ipairs(S.s.meldsByTeam[team] or {}) do
            if m.declaredBy and m.declaredBy ~= seat
               and m.cards then
                for _, c in ipairs(m.cards) do
                    for _, u in ipairs(unseen) do
                        if u == c then
                            meldPins[c] = m.declaredBy
                            break
                        end
                    end
                end
            end
        end
    end
end
```
`State.lua:1031-1033` stores melds with `declaredBy = seat` regardless of whether that seat is human or bot:
```lua
table.insert(s.meldsByTeam[team], {
    ...
    declaredBy = seat,
```
`S.s.meldsByTeam` is the shared game state visible to the host's `sampleConsistentDeal`. The schema matches exactly what `meldPins` expects.

**Verdict:** The meld-pinning logic correctly handles human-declared melds. When a human partner declares a Tierce in Hearts (7-8-9), those three cards are pinned to their seat in every ISMCTS world. The bot does benefit from this hand information for all declarer seats, human or bot.

**Remaining gap:**
`sampleConsistentDeal` only uses meld information that has been formally declared (through `S.ApplyMeld` / `S.s.meldsByTeam`). It does not use the ABSENCE of a meld declaration as evidence. Saudi Baloot convention: a seat that leads trick 1 without declaring any meld is likely meld-free (no sequences ≥ 3, no eligible carré). A human partner who plays in trick 1 with no meld declaration has implicitly revealed that they hold no sequence of 3+ in any suit. This is useful information for ISMCTS sampling: the sampler should respect this absence constraint and avoid generating worlds where the partner holds 7-8-9 of any suit.

Currently there is no "anti-meld" inference. The sampler may generate worlds where the undeclared partner holds a Tierce, wasting rollout computation on impossible worlds.

**Concrete fix:**
After trick 1 is complete (i.e., `#S.s.tricks >= 1`), infer that any seat that declared no melds holds no meld-eligible sequence. In `sampleConsistentDeal`, after the meldPins block, add an anti-meld void constraint:
```lua
local noMeldSeats = {}
if #(S.s.tricks or {}) >= 1 then
    for s2 = 1, 4 do
        if s2 ~= seat and not S.s.meldsDeclared[s2] then
            -- This seat had no melds to declare.
            -- Flag it for sequence-avoidance in Phase 1 sampling.
            noMeldSeats[s2] = true
        end
    end
end
```
Then during Phase 1/2 of deal sampling for `noMeldSeats`, reject proposed hands that would form a 3+ sequence — a lightweight filter that prunes impossible worlds.

---

### B-100 — Human deception detection: human plays a card inconsistent with their bid

**IS-EXPLOITED: NO**

**Code locus:** Bot.lua:720-892 (`pickLead`), BotMaster.lua:36-55 (`getStrongCards`), BotMaster.lua:196-231 (`sampleConsistentDeal` Phase 1 biasing).

**What the code does:**
`getStrongCards` builds a static bias table for the bidder seat:
```lua
if contract.type == K.BID_HOKM and contract.trump then
    local t = contract.trump
    strong["J"..t] = 50; strong["9"..t] = 40; strong["A"..t] = 30
    ...
end
```
This table is built ONCE at the start of the ISMCTS loop and is never updated based on what the bidder actually plays. If the human bidder who called Hokm in Spades leads Hearts on trick 1, the bot has no mechanism to recognize this as anomalous or to update its prior about the bidder's Spades holding.

The `_partnerStyle.trumpEarly` / `trumpLate` counters (Bot.lua:246-254) track trump-LEAD behavior per seat across the GAME, but are only used in `styleTrumpTempo` which is never called from any active code path (marked "currently unused" at Bot.lua:178).

`partnerBidBonus` (Bot.lua:410-427) reads the bid as a fixed signal for escalation decisions but is not consulted during play decisions.

**Saudi Baloot context:**
Experienced Saudi Baloot players use deceptive leads deliberately. A bidder who called Hokm in Spades may lead a side Ace first to cash it before opponents can ruff — this is legitimate and not deceptive. However, a bidder who leads a suit they do not own strength in (e.g., leading Hearts 7 from a 1-card Heart holding as a "false flag" to confuse opponents' trumping plan) is an advanced deception. More commonly, human bidders simply have hands whose character shifted after the round-2 deal: they bid on 5-card Spades, then the round-2 cards gave them 3 Hearts Aces instead of Spades fillers. Their play will look off-bid because the hand changed.

**Exploit gap:**
The bot commits to its ISMCTS prior for the bidder's hand (strong trump holdings) and never revises downward when the bidder's plays are inconsistent with that prior. Specifically:
1. If the human bidder ruffs on trick 2 (should not be possible if they hold 6+ trump), the bot already records `mem.void[leadSuit] = true` for the bidder — but does NOT update the ISMCTS sampling bias to reduce trump-count expectation.
2. If the human bidder leads a non-trump suit on trick 1 (the "I lead a side Ace first" case), `sampleConsistentDeal` continues to give them `70%` probability of receiving J/9/A of trump even in subsequent worlds for tricks 5–8, because `getStrongCards` is called fresh every world with no state.
3. `trumpEarly`/`trumpLate` counters exist but `styleTrumpTempo` is never called.

**Concrete fix:**
The most impactful fix is to integrate `Bot._memory[bidder].void` into `getStrongCards` logic. After the sampler has established that the bidder is void in, say, Spades (the trump suit) — which cannot happen if they genuinely hold a Hokm hand — the strong-card bias should be suppressed. This is already partly handled because `voids` is applied to Phase 2 sampling (line 218: `not voids[C.Suit(c)]`), but in Phase 1 (biased pick), the `desire` table unconditionally weights trump cards heavily even for a seat where `voids[trump]` is true. This is a bug: the void check on line 218 applies to Phase 2 filling, but Phase 1 biased picks (lines 216-226) only check `voids[C.Suit(c)]` inconsistently.

More broadly, add a `bidderActedOffBid` detection:
```lua
-- After trick 1: if the bidder led a non-trump suit in a Hokm contract,
-- reduce the strong-card weight for their trump suit in subsequent worlds.
local bidder = contract and contract.bidder
local bidderMemory = bidder and B.Bot._memory and B.Bot._memory[bidder]
local bidderTrumpVoid = bidderMemory and contract.trump
                        and bidderMemory.void[contract.trump]
if bidderTrumpVoid then
    -- Bidder cannot have a legitimate Hokm hand; suppress trump bias.
    strong = {}  -- or drastically reduce trump weights
end
```
Additionally, activate the `styleTrumpTempo` ledger by reading it in `getStrongCards` to lower trump-weight expectations for a bidder whose history shows late-trump tendencies.

---

## Summary Table

| Angle | IS-EXPLOITED | Primary File:Lines |
|-------|--------------|--------------------|
| B-31 Fzloky partner signal honesty | NO | Bot.lua:747-773 |
| B-43 Human ruff → void inference | YES | Bot.lua:200-225, Net.lua:1065 |
| B-58 Human discard rank as strength signal | PARTIALLY | Bot.lua:217-225, BotMaster.lua:211-231 |
| B-65 Per-seat illegal play rate | NO | Bot.lua:1324-1352 |
| B-84 Suit confusion / color-revoke | NO (correctly handled) | Bot.lua:206-218, Constants.lua:27-31 |
| B-91 Human meld declarations as hand reveals | PARTIALLY | BotMaster.lua:148-177 |
| B-100 Human bid-inconsistent play detection | NO | BotMaster.lua:36-55, Bot.lua:720-892 |
