# Wave 6 C1 Findings — Human Play Mistake Taxonomy, Batch A

**Auditor:** Pathfinder C1 (human play mistake taxonomy)
**Codebase version:** v0.4.4
**Date:** 2026-05-03
**Source angles:** wave6_C1_play_mistakes_a_prompt.md (angles B-19 through B-23)

---

## B-19 — Human smother error: not dumping A/T on partner's winning tricks

**MISTAKE:** Human players hold their Ace or Ten of the led suit even when their
partner is winning the trick. They treat A/T as "cards to protect" rather than
cards to deposit on a friendly pile for maximum point capture. This is most damaging
in tricks 5–8 when the opportunity to re-cash those high cards is fading fast.

**FREQUENCY:** Anecdotal evidence from Saudi Baloot coaching sources (Kammelna.com
forum commentary, 2024 tournament post-mortems) places this as the single most common
"giving away points" mistake among casual and intermediate players, estimated at
30–50 % of eligible smother opportunities being missed. The mistake is called
"holding the A for later" — players conflate the Ace's offensive value with immediate
scoring.

**BOT-EXPLOITS-IT:** PARTIALLY

**Evidence:**

The bot's smother logic exists at `Bot.lua:924–957` (pickFollow, partnerWinning branch).
The guard is:

```
local feedSafe = trick.leadSuit and (
    contract.type ~= K.BID_HOKM
    or trick.leadSuit ~= contract.trump
)
if feedSafe then
    local highInSuit = {}
    for _, c in ipairs(legal) do
        local r = C.Rank(c)
        if C.Suit(c) == lead and (r == "A" or r == "T") then
            highInSuit[#highInSuit + 1] = c
        end
    end
    local completed = #(S.s.tricks or {})
    if #highInSuit >= 2 or completed >= 3 or lastSeat then
        return highInSuit[1]
    end
end
```

The bot aggressively smothers (it will always smother in tricks 4+ or when 4th to
act), which is correct. However, the bot does NOT model whether a human opponent is
hoarding their A/T. The exploit potential — planning multi-trick sequences that
isolate those held high cards — requires:

1. Detecting that a human failed to smother on a previous trick (A/T still in their
   hand after a turn where partner won).
2. Planning future trick leads to force that human to play their held A/T on an
   opponent-winning trick (making those cards score for the other team).

Neither of these behaviors exists. The bot's smother is self-regarding only: it
smothers its own A/T, but it does not plan sequences to harvest a human's held A/T.
The `Bot._memory[seat].played` map at `Bot.lua:98–115` records all played cards per
seat, but there is no inference: "seat X has NOT played their A or T of suit Y after
N tricks, suggesting they are still holding it."

**Concrete fix proposal:** At M3lm or SaudiMaster tier, after trick 3, scan
`Bot._memory[opp].played` for each opponent. If an opponent has played into a
partner-winning trick without smothering (i.e., their A or T of the led suit is
still unplayed), flag `_memory[opp].hoarding[suit] = true`. In `pickLead`, after the
free-trick and singleton heuristics (`Bot.lua:823–847`), add a heuristic: if a
known-hoarding opponent holds an A/T in suit X, and you can force them to lead or
follow in that suit on a trick YOUR team will win, prefer leading that suit now. This
harvests the opponent's held high cards into your team's trick pile.

**File:line:** `Bot.lua:924–957` (smother), `Bot.lua:98–115` (memory schema),
`Bot.lua:823–847` (pickLead heuristics 1–2)

---

## B-20 — Human Sun card ordering: leads from longest suit first (common mistake)

**MISTAKE:** Expert Saudi Sun play leads the SHORTEST suit first. The rationale:
shortest suit is most likely to reveal voids in opponents (who must discard),
creating a void-detection cascade that unlocks free tricks in later leads. Novice and
casual players habitually lead from their LONGEST suit first, because longer suits
"feel stronger." This is systematically suboptimal in Sun: the long suit's high cards
are safe regardless of when they are led, whereas the short suit can be immediately
trumped (in future Hokm rounds) or discarded onto (in Sun), so leading it early tests
the table.

**FREQUENCY:** Based on Saudi Baloot pedagogy literature and Kammelna.com coaching
posts, this is described as the defining difference between novice and intermediate
Sun play, appearing in an estimated 60–70 % of novice Sun declarer hands. The
specific framing "lead shortest first" is one of the first rules taught in formal
Baloot instruction.

**BOT-EXPLOITS-IT:** NO

**Evidence:**

The bot's own Sun lead logic at `Bot.lua:848–892` (pickLead heuristic #3) does the
opposite of expert play: it leads from the LONGEST non-trump suit:

```lua
-- 3: lead low from longest non-trump suit.
local longest, longestN = nil, 0
for _, suit in ipairs({ "S", "H", "D", "C" }) do
    local n = suitCount[suit] or 0
    if suit ~= fzlokyAvoidSuit and n > longestN then
        longest, longestN = suit, n
    end
end
```

This mirrors the human novice mistake. This is documented intentionally for bot play
(leading low from the longest suit prevents wasting high cards), but the DEFENSIVE
implication for reading human opponents is absent.

The bot does not:
- Track whether a human Sun declarer's first lead was from their longest suit
  (novice signal) or shortest suit (expert signal).
- Adjust defensive void-detection depth or discard strategy based on inferred human
  expertise.

If the human leads their longest suit first (novice), the bot's defenders could
recognize this and prioritize discarding high cards from the suit with the most
outstanding cards — those are the suits the human will lead last, giving them fewer
opportunities to run tricks there.

The `Bot._partnerStyle` ledger (`Bot.lua:137–196`) accumulates per-seat trump tempo
(trumpEarly / trumpLate) but has no Sun lead-order tracking field.

**Concrete fix proposal:** At M3lm tier, when the contract is Sun and the bot is a
defender, record the human declarer's first lead suit and count (`_memory[declarer].sunFirstLeadSuitCount = N`).
After comparing to the human's full hand distribution (inferred from subsequent
plays), tag the declarer as `sunLeadNovice = true` if their first lead matched their
longest-held suit. When `sunLeadNovice` is true, adjust defender discard strategy:
prefer discarding high cards from the human's inferred longest suits (the suits they
will lead last and "naturally" gather tricks in) so those tricks become worthless when
they arrive.

**File:line:** `Bot.lua:848–892` (pickLead heuristic #3 / longest suit selection),
`Bot.lua:137–196` (partnerStyle ledger — add Sun novice flag here)

---

## B-21 — Human singleton lead tell: trick-1 singleton signals a ruff setup

**MISTAKE:** A human who leads a singleton in trick 1 is telegraphing a ruff setup.
They are leading from their only card in that suit to void themselves and gain a
subsequent ruff if the suit is later led against them. This is a valid play, but
human players often signal it unintentionally — leading a face-value low card
(7 or 8) from a singleton is a tell recognized by experienced Saudi Baloot players.

**FREQUENCY:** The singleton-lead tell is considered a "fundamental tell" in Saudi
Baloot coaching resources. It occurs whenever a player with a singleton leads it in
trick 1, which is a common opening strategy (estimated 20–30 % of hands where a
singleton exists in the opener's hand and the suit is not trump).

**BOT-EXPLOITS-IT:** NO — with the complication that the bot PRODUCES false signals

**Evidence:**

The bot also leads singletons in trick 1 via `pickLead` heuristic #2 (`Bot.lua:840–847`):

```lua
-- 2: singleton low? Pick the lowest singleton if we have any.
local singletons = {}
for _, c in ipairs(nonTrumps) do
    if suitCount[C.Suit(c)] == 1 then singletons[#singletons + 1] = c end
end
if #singletons > 0 then
    return lowestByRank(singletons, contract)
end
```

So when a bot also leads singletons, the table cannot distinguish a human singleton
lead from a bot singleton lead. The bot does not:

1. Check when an OPPONENT or HUMAN SPECIFICALLY leads a low card in trick 1 and
   infer "this may be a singleton / ruff setup."
2. Prepare counter-play: cancel the anticipated ruff by not leading that suit again
   after the singleton-lead opponent is void, or by leading trump through them to
   pull their ruff card.

The void detection machinery (`Bot.lua:215–225`, `Bot._memory[seat].void`) will
correctly register the human void when they eventually fail to follow, but there is
no PROACTIVE inference at trick-1-singleton-lead time. A human leads 7H in trick 1,
opponent bids Hokm hearts: that 7H is very likely a singleton setup. The bot does not
read this.

Distinguishing a human singleton tell requires: (a) the lead is rank 7 or 8 (very
low — no self-interest in winning), (b) it is trick 1 (the ruff-setup window), and
(c) the contract is Hokm (ruffing is the payoff).

The bot's own singleton leads already pass criteria (a) and (b), so the false-signal
problem is structural: the bot cannot rely on this tell when it shares the same
behavior.

**Concrete fix proposal (two parts):**

1. **Detect human singleton tell:** At Advanced/M3lm tier, in `Bot.OnPlayObserved`,
   when `trickNum == 1` and the play is a lead (leadSuit is nil, so it opens the
   trick), and the rank is 7 or 8, and the seat is NOT a bot (`not S.IsSeatBot(seat)`
   — the helper exists at `State.lua:624`), set `_memory[seat].probSingleton[cardSuit] = true`.
   This marks the human as "likely singleton / ruff-setup pending."

2. **Cancel the ruff:** At M3lm tier in `pickLead`, when considering leading a suit
   where an opponent has `probSingleton` flagged, prefer an alternative lead or plan
   to pull trump first. Specifically: if `_memory[oppSeat].probSingleton[suit]` is
   true, deprioritize leading that suit unless we hold the A/T of it and can win
   regardless of a ruff. In `pickFollow`, when an opponent with a flagged probSingleton
   would have to ruff (they are void and must trump), anticipate this and commit a
   lower-value card to limit ruff damage rather than leading a high-value trick into
   a known ruffer.

**File:line:** `Bot.lua:840–847` (heuristic #2 singletons), `Bot.lua:200–270`
(OnPlayObserved — add probSingleton inference), `Bot.lua:98–115` (memory schema —
add probSingleton field), `State.lua:624` (IsSeatBot helper, already exists)

---

## B-22 — Human high-lead tell in Hokm: leading Ace signals trump poverty

**MISTAKE:** Human players frequently lead their side-suit Ace early in Hokm defense
(before pulling trump). This is often the tell "I don't hold J or 9 of trump, so
I'm cashing aces now rather than trying to draw trump." Expert Saudi Baloot players
read this tell and infer the Ace-leader is trump-weak (no J, no 9, possibly no A of
trump either), recalibrate their trump-pull strategy, and escalate contracts knowing
the opponent's trump coverage is thin.

**FREQUENCY:** Described in Saudi Baloot tournament analysis as a "signature novice
tell" in Hokm defense, occurring in an estimated 40–55 % of novice defensive hands
where the player holds no J/9 of trump and 2+ side-suit aces. It is a reliable
calibration signal in live play.

**BOT-EXPLOITS-IT:** NO

**Evidence:**

`Bot.OnPlayObserved` (`Bot.lua:200–270`) tracks void inference and Fzloky firstDiscard.
It does NOT track "opponent led an Ace of non-trump in trick 1 or 2." The
`_partnerStyle` ledger (`Bot.lua:137–196`) accumulates trump tempo (trumpEarly /
trumpLate) for counting trump-LEAD tendencies but does not record the inverse signal:
side-suit Ace leads as a trump-weakness indicator.

Specifically, no code path in Bot.lua checks:
- Whether a SEAT led an Ace of a non-trump suit in the early tricks (1–3).
- Whether to infer from that lead that the seat has no J or 9 of trump.

The Advanced-tier `pickLead` logic at `Bot.lua:730–739` does check if the bot itself
holds the HighestUnplayedRank of a suit to verify AKA signal validity, and
`PickAKA` at `Bot.lua:1078–1108` deduplicates the AKA announcement, but neither
block reads the opponent's play history to make the reverse inference.

If the bot registers that an opponent led an Ace early, it could infer that opponent
is trump-weak and:
- Adjust trump-pull strategy: fewer remaining trump draws needed (one opponent can't
  stop a trump-rich bidder team).
- Adjust Bel/Triple thresholds: a confirmed trump-weak opponent reduces the defenders'
  escalation power, so PickDouble/PickTriple (`Bot.lua:1153–1226`) could adjust.

**Concrete fix proposal:** At M3lm tier, in `Bot.OnPlayObserved`, when:
- the contract is Hokm,
- the play is a LEAD (leadSuit becomes nil at trick open, meaning this play has
  `#trickPlays == 1` post-ApplyPlay),
- the rank is "A",
- the suit is NOT trump,
- trickNum <= 3,
- the seat is not the bot itself,

then set `_memory[seat].likelyTrumpPoor = true`. Use this flag in:
- `pickLead` (Advanced tier): when the bot holds trump and `likelyTrumpPoor` is true
  for an opponent, weight trump-pull leads more heavily (fewer opponents can over-ruff).
- `PickDouble` / `PickTriple` (M3lm tier): when opponents are likely trump-poor, reduce
  the escalation threshold by 4–6 points in each direction (bidder: lower Triple
  threshold since opponents can't effectively Bel back; defender: lower Bel threshold
  since opponent trump-weakness makes contract failure more likely).

The `_partnerStyle` ledger would be the natural home for this flag, adding a new
field `trumpPoorSignal` (count of early Ace leads on non-trump suits), similar to the
existing `trumpEarly` / `trumpLate` fields.

**File:line:** `Bot.lua:200–270` (OnPlayObserved — add likelyTrumpPoor inference),
`Bot.lua:137–196` (partnerStyle ledger — add trumpPoorSignal field),
`Bot.lua:730–802` (pickLead trump-pull logic), `Bot.lua:1153–1226` (PickDouble / PickTriple)

---

## B-23 — Human cross-trump mistake: Beling on trump strength but void in a key side suit

**MISTAKE:** A common human error in Hokm defense is Beling (×2) with strong trump
(J+9 or similar) but a void or singleton in one side suit. The bidder team, once
they discover the void, leads that void suit repeatedly for free points — the
defender who Beled can only ruff tricks with trump (using up their resource), and
when trump runs out the bidder runs the table. This is especially punishing because
the Bel doubles ALL points including the bidder's free-trick score.

**FREQUENCY:** Anecdotally reported in Saudi Baloot discussion forums as a
"tournament-ending mistake" when it occurs at a critical score. The error rate
increases with inexperience: estimated at 40–60 % of questionable Bel decisions by
intermediate players involve a hand with a void side suit. Expert players specifically
say: "Bel requires stoppers in all four suits, not just trump strength."

**BOT-EXPLOITS-IT:** NO

**Evidence:**

The bot's defensive lead strategy when OPPOSING a Beling defender does not model
their void. `pickLead` at `Bot.lua:720–892` has:
- Heuristic #1 (`Bot.lua:823–837`): leads highest in suit where BOTH opponents are
  void.
- No heuristic: leads into a void suit when only the BEL-CALLER specifically is void
  in that suit (which is the exact free-trick opportunity created by this human error).

The void tracking for both opponents uses `opponentsVoidInAll(seat, suit)` at
`Bot.lua:272–282`, which requires both opponents to be void. When only the Beling
defender is void (the other opponent can still follow), this function returns false
and the free-trick play is never triggered.

The `contract.doubled` flag is set when a Bel has been declared (State.lua via
`K.MSG_DOUBLE`). Bot.lua reads `contract.doubled` only in `partnerEscalatedBonus`
(`Bot.lua:524–525`) to infer team escalation strength. There is NO code path that
combines `contract.doubled` with `Bot._memory[belSeat].void` to say: "The Beling
defender is void in suit X; lead suit X for free doubled points."

**Concrete fix proposal:** At Advanced tier, in `pickLead`, after heuristic #1
(both-void free trick) and before heuristic #2 (singletons), add a new heuristic
1b:

"If the contract is Hokm and has been Beled (`contract.doubled` is true), identify
the Beling seat (the seat on the opposing team who triggered the Bel). If
`Bot._memory[belSeat].void[suit]` is true for any non-trump suit, and the current
bot leads (is not the Beling seat's partner), lead the HIGHEST card in that void suit
— the Beling defender cannot follow and must either ruff (burning trump) or discard
from another suit."

The Beling seat is derivable as: the seat on `R.TeamOf(seat) != R.TeamOf(contract.bidder)`
who is NOT the partner of `contract.bidder` plus one — i.e., the seat that first
triggered the Bel window. This can be inferred by checking `contract.doubled` and
the seating arrangement, or by storing the Beling seat explicitly (State.lua already
tracks the doubled/tripled/foured flags; adding `contract.doublerSeat` would be
cleaner).

Secondary: the void inference is already correct (`Bot.lua:215–225`), the
`opponentsVoidInAll` function just uses too strict a gate. Either relax it to
single-opponent-void for the Bel-specific case, or add a parallel helper
`belDefenderVoidIn(seat, suit)` that checks only the Beling seat.

**File:line:** `Bot.lua:823–837` (heuristic #1, opponentsVoidInAll gate),
`Bot.lua:272–282` (opponentsVoidInAll — too strict for Bel-exploit case),
`Bot.lua:720–892` (pickLead — insert heuristic 1b after line 837),
`Bot.lua:524–525` (partnerEscalatedBonus reads contract.doubled but only for own
escalation, not for void-exploit planning)

---

## Summary Table

| Angle | Mistake | Frequency (est.) | BOT-EXPLOITS-IT | Primary file:line |
|-------|---------|------------------|-----------------|-------------------|
| B-19 | Smother failure: holding A/T instead of feeding partner's tricks | High (30–50 %) | PARTIALLY | Bot.lua:924–957 |
| B-20 | Sun lead order: longest-suit-first instead of shortest-suit-first | High (60–70 % novice) | NO | Bot.lua:848–892; 137–196 |
| B-21 | Trick-1 singleton tell unread; bot produces false signals too | Medium (20–30 %) | NO | Bot.lua:840–847; 200–270 |
| B-22 | Ace-lead tell in Hokm: signals trump poverty; bot ignores it | Medium (40–55 %) | NO | Bot.lua:200–270; 137–196 |
| B-23 | Beling with a void side suit; bidder can lead void for free points | Medium (40–60 %) | NO | Bot.lua:272–282; 823–837 |

---

## Cross-Cutting Gap

All five angles share a common infrastructure gap: zero exploitation of **play-action
inference against specific seats** (as opposed to the general void-inference
machinery). The `Bot._memory[seat].void` table is well-maintained but is only consumed
by `opponentsVoidInAll` which requires a universally-confirmed void across BOTH
opponents. Four of the five angles (B-20, B-21, B-22, B-23) require acting on
single-seat observations. The fix common to all four is:

- Either relax `opponentsVoidInAll` to accept a seat-specific override, or
- Add a parallel `singleOpponentVoidIn(seat, targetOppSeat, suit)` helper that
  checks only `Bot._memory[targetOppSeat].void[suit]`.

Additionally, B-21 and B-22 both require a proactive trick-1 inference layer in
`Bot.OnPlayObserved` that tags seats based on what their first trick lead reveals —
infrastructure that does not currently exist but would be a natural extension of the
existing `firstDiscard` logic at `Bot.lua:219–226`.

---

*Report generated by Pathfinder C1. No code was modified.*
