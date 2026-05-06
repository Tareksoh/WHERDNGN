# Wave 6 C5 Findings — Human Play / Signal Taxonomy, Batch E (B-40, B-41, B-42, B-44, B-45)

---

## B-40 — Human first-card-of-hand tell: suit choice on trick 1 as distribution signal

MISTAKE: Human reveals hand distribution via their opening lead suit.
Expert Gulf players deliberately lead the 3-card suit they want ruffed later;
novices lead their best / longest suit to "cash out" immediately.

SIGNAL: The suit of the first card played on trick 1 (when that seat LEADS
trick 1, i.e. `#trick.plays == 0` at lead time and `trickNum == 1`).

FREQUENCY: Universal — every human hand produces exactly one first lead.
The signal is strongest in novice play; experts intentionally obfuscate it.

BOT-EXPLOITS-IT: PARTIAL, TIER-GATED.
The Fzloky tier (Bot.lua:747-773) reads `Bot._memory[partner].firstDiscard`
— but that is the first *off-suit discard* (failing to follow), not the
first-card-of-hand lead. `OnPlayObserved` (Bot.lua:200-270) only records
`firstDiscard` when `leadSuit ~= nil AND cardSuit ~= leadSuit` (a failing-
to-follow scenario). A seat's very first lead on trick 1 has `leadSuit == nil`
at the time `OnPlayObserved` is called, so it is logged as a normal played
card but its suit is not stored in any "opening lead inference" structure.
`_partnerStyle` (Bot.lua:136-196) records `trumpEarly`/`trumpLate` counts
but only for trump leads (Bot.lua:244-255); plain suit first leads do not
update any distribution-inference counter. The Saudi Master tier
(BotMaster.lua) uses `_partnerStyle` indirectly via bidder-strength biasing
when sampling, but no field tracks "opponent's first lead suit."

FILE:LINE: Bot.lua:200-270 (`OnPlayObserved`), Bot.lua:96-116 (`emptyMemory`
field list), Bot.lua:138-147 (`emptyStyle` field list).

FIX: Add a per-seat `firstLeadSuit` field to `emptyMemory`. Populate it in
`OnPlayObserved` when `leadSuit == nil` (the opening play of a fresh trick)
and `trickNum == 1` (`#S.s.tricks == 0`). At M3lm+ tier, when the bot later
leads against that opponent, skew away from the first-lead suit (novice tell:
they hold strength there, so avoid giving them a point-rich trick) or toward
it (expert tell: they may be short there and setting up a ruff they won't get
to execute if we lead it out first).

---

## B-41 — Human escalation culture mismatch: Gulf vs. non-Gulf Bel frequency

MISTAKE: Gulf-region human players Bel aggressively on threshold hands that
non-Gulf casual players would pass. The bot models escalation tendency per-
seat via `_partnerStyle.bels`, but this counter only updates AFTER observing
a Bel — it has no prior.

SIGNAL: Accumulated `Bot._partnerStyle[seat].bels` counter across the game.

FREQUENCY: Systematic for Gulf-native players across entire match;
indistinguishable from a novice-lucky run until 2+ Bel observations.

BOT-EXPLOITS-IT: PARTIALLY, LATENT ONLY.
`styleBelTendency` (Bot.lua:181-187) exists and returns `1` when `bels >= 2`,
but it is never called anywhere downstream. Bot.lua's comment at line 178-180
explicitly states "Currently unused by the picker code; reserved for future
M3lm-Plus heuristics." No regional/cultural configuration parameter exists.
`PickDouble` (Bot.lua:1153-1179) and `PickTriple`/`PickFour`/`PickGahwa` use
only hand-strength, `partnerBidBonus`, `partnerEscalatedBonus`, and
`scoreUrgency` — none read `styleBelTendency`. There is no "region" or
"aggressiveness_prior" config in `WHEREDNGNDB` (WHEREDNGN.lua:42 shows
`saudiMasterBots = false` is the deepest available preference).

FILE:LINE: Bot.lua:181-187 (`styleBelTendency` — defined but uncalled),
Bot.lua:1153-1179 (`PickDouble` — ignores style ledger),
Bot.lua:1215-1225 (`PickTriple`), WHEREDNGN.lua:38-50 (DB defaults).

FIX: Wire `styleBelTendency` into `PickDouble` and `PickTriple` at the M3lm
tier: when an opponent's `styleBelTendency` returns `1` (observed-aggressive),
subtract 5-8 from the bot's own Bel threshold (lower our bar — they'll
escalate, so meeting their Bel with a Triple on a marginal hand becomes
correct). Conversely, a conservative opponent (bels == 0 after 3+ rounds)
raises our Triple threshold. A "region prior" config is not strictly needed
if the per-seat counter converges within 2-3 rounds of play, but an optional
`WHEREDNGNDB.gulfAggressionPrior = true` could seed `_partnerStyle[s].bels`
to 1 for all opponent seats at game start.

---

## B-42 — Human Sun defender over-pressure: leading trump against Sun contracts

MISTAKE: In Sun, there is no trump. Human defenders unfamiliar with Sun
sometimes lead their "best" card (the Ace of a suit) immediately rather
than playing low from a weak suit. This is not an illegal play but it is
sub-optimal: it burns a high-value card without pressure since in Sun no
trumping is possible and every suit is plain.

SIGNAL: First-trick lead in a Sun contract where the lead card is an Ace
(rank == "A") from a seat that is NOT the contract bidder.

FREQUENCY: Occasional; most common among players accustomed to Hokm
where the Ace-of-non-trump opening is a classic defensive tempo move, but
in Sun it gives away the Ace point without extracting any suit information.

BOT-EXPLOITS-IT: NO explicit Sun-specific first-lead exploitation.
`pickLead` (Bot.lua:720-892) falls through to the "Defenders / bidder's
partner / Sun lead" section (comment at Bot.lua:804) for Sun contracts, using
the same heuristics as Hokm defenders. `OnPlayObserved` (Bot.lua:200-270)
records void inferences and `firstDiscard` but only triggers void logic when
a seat fails to follow suit — a legal Ace-lead in Sun is followed by all
suits (no suit constraint), so no useful void inference fires from trick 1 in
Sun. There is no code that reads "opponent burned an Ace on trick 1 of Sun"
and adjusts the bot's subsequent lead strategy to target that opponent's now-
known weak suit (they over-spent their Ace telling the table they had it, and
now that suit is unprotected at high ranks).

FILE:LINE: Bot.lua:720-892 (`pickLead` — no Sun-Ace-burn exploitation
branch), Bot.lua:200-270 (`OnPlayObserved` — no Sun first-lead capture),
Rules.lua:143 (`if contract.type == K.BID_SUN then return true` — Sun free
play, no suit constraint on any play).

FIX: In `OnPlayObserved`, when the contract is Sun and `leadSuit == nil`
(the seat is opening a trick) and `C.Rank(card) == "A"`, record a
`sunAceBurnedSuit` in that seat's memory entry. In `pickLead` at the Fzloky+
tier, when leading against an opponent with `sunAceBurnedSuit` set, bias
toward leading that suit — the opponent has now exposed their Ace, so leading
it again forces them to shed a lower card from the same suit that they can't
protect with the burned Ace. This is a mild but precise Sun exploitation.

---

## B-44 — Human "I have to save something" discard: minimum-rank discard under pressure

MISTAKE: When a human cannot win a trick, they typically discard their 7 or
8 of the suit they consider most expendable. This discard can carry two
distinct meanings: (a) the seat held only that single 7/8 in the suit
(singleton / void now confirmed), or (b) they hold multiple cards in that
suit but chose the lowest to preserve mid-rank cards. The bot currently
does the same (`lowestByRank`) but does not distinguish the two cases when
observing a human's low discard.

SIGNAL: A human discards a 7 or 8 of suit X when they cannot follow lead.
Cross-reference `suitCardsOutstanding(hand, X)` (Bot.lua:897-913) against
the known remaining card count in that suit:
- If only 1 card of suit X was outstanding before this trick, the discard
  confirms the seat was a singleton — now void, which `OnPlayObserved` sets
  via `mem.void[leadSuit] = true` (Bot.lua:217).
- If 2+ cards of suit X were outstanding, the low discard is ambiguous —
  they may still hold the 9/T/K/A of that suit.

FREQUENCY: Occurs on virtually every trick where a human cannot follow suit,
because `lowestByRank` is the near-universal human strategy under pressure.

BOT-EXPLOITS-IT: PARTIAL — void inference fires correctly (Bot.lua:217),
but the ambiguous case (still holds high cards in the discarded suit) is
not distinguished. The Fzloky `firstDiscard` signal (Bot.lua:750-772)
does read the rank of the first off-suit discard: a "7" or "8" sets
`fzlokyAvoidSuit` (Bot.lua:756-758), steering the bot away from leading
that suit — but this is interpreted as a "partner's suit preference signal,"
not as "opponent is still strong in this suit." The `suitCardsOutstanding`
function (Bot.lua:897-913) exists and is used in the `pos == 2` trump-
counting branch (Bot.lua:981-993), but it is never applied to non-trump
suits to infer whether an opponent's low discard reveals remaining honors.

FILE:LINE: Bot.lua:897-913 (`suitCardsOutstanding` — not used for non-trump
honor inference), Bot.lua:750-772 (`pickLead` Fzloky block — interprets
low discard as suit-avoidance, misses honor-still-held case),
Bot.lua:1053-1068 (can't-win discard path uses `lowestByRank` without
recording anything about it for exploitation).

FIX: At M3lm+ tier, when `OnPlayObserved` sees an opponent discard a 7 or
8 of suit X and `suitCardsOutstanding(bot_hand, X)` was >= 2 before this
trick, set a per-seat `maybeHoldsHonors[X] = true` flag. In `pickLead`,
when targeting an opponent who has `maybeHoldsHonors[X]` set, avoid leading
suit X (they likely have the T/K/A there and will win). This refines the
`fzlokyAvoidSuit` logic which currently makes the same decision but for the
wrong reason (it avoids leading the suit because it thinks PARTNER is weak
there, not because the OPPONENT is strong there).

---

## B-45 — Human Kawesh under-use: humans in casual play often don't call Kawesh

MISTAKE: Human players in casual play frequently fail to recognize or call
Kawesh (the hand-annul rule for an all-7/8/9 opening hand), either due to
unfamiliarity or distraction. They play a hand where the correct action is
to redeal, taking no tricks and often gifting the opponents a sweep.

SIGNAL: A human plays all 8 tricks and wins zero tricks, having held an all-
7/8/9 opening five cards (detectable post-hoc: check `hostHands` at deal time
vs. `C.IsKaweshHand`).

FREQUENCY: Rare per-hand (requires an all-7/8/9 deal), but consequential —
the weak player's team concedes a near-certain kaboot (all-8-tricks sweep).

BOT-EXPLOITS-IT: NOT DIRECTLY. The bot's `PickKawesh` (Bot.lua:1302-1308)
fires correctly and unconditionally for bot seats when eligible: if
`C.IsKaweshHand(hand)` is true, the bot always calls Kawesh (added in the
13th-bot-audit). This means bots never produce the "human missed Kawesh"
scenario. However, when a HUMAN in the session misses Kawesh and plays their
unwinnable hand, there is no code path that recognizes this scenario and
adapts the bot's strategy. Specifically: the bot does not detect that an
opponent is playing with a structurally honor-free hand (all 7/8/9), which
would imply that every trick the bot or its partner wins is uncontested —
they could safely lead low cards and still sweep, saving high-value A/T for
tricks that matter.

The Kawesh eligibility window is `K.PHASE_DEAL1` only (Bot.lua:1305,
Net.lua:2628). By the time play begins (PHASE_PLAY), the window is closed and
no inference mechanism connects "this player missed Kawesh" to "this player's
hand is honor-free." `_partnerStyle` and `_memory` have no "hand quality"
field; `suitCardsOutstanding` provides counts but not rank-range inferences.

FILE:LINE: Bot.lua:1302-1308 (`PickKawesh` — bot always calls; no human-
miss exploitation), Net.lua:2836-2853 (`HostHandleKawesh` — validates host-
side, no inference hook), Cards.lua:160-170 (`IsKaweshHand` — eligibility
check, not called during play).

FIX: At PHASE_DEAL1, the host holds `hostHands[seat]` for all seats. After
the Kawesh eligibility window closes (PHASE_DEAL3 / start of play), if a
human seat that had a Kawesh-eligible hand did NOT call Kawesh, record a
`missedKawesh = true` flag in `Bot._memory[seat]`. During play, any bot
targeting that seat can safely lead any suit (opponent holds no honors —
every lead is essentially a free trick or at worst costs a 0-point 7/8/9).
This flag is most useful for the Saudi Master tier's determinization sampler
(BotMaster.lua:124-273), which could restrict that seat's sampled hand to
only contain 7/8/9 ranks, dramatically tightening the rollout variance.
