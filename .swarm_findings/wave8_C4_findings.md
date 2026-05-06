# Wave 8 C4 — Partner Coordination Batch C Findings

**Codebase:** WHEREDNGN v0.4.4  
**Angles:** B-89, B-90, B-92, B-93, B-94

---

## B-89 — Bot leading partner's bid suit back (partner-return heuristic)

**SIGNAL/MISTAKE:** Missing. `pickLead` (Bot.lua:720) has no explicit "return partner's bid trump suit" heuristic. When a human partner bids `HOKM:H` in round 1, they have committed to holding J/9 or A+length in Hearts. If the bot then leads as defender or bidder's partner, the standard baloot partner-return play (lead low from 2–3 of partner's bid suit so partner can draw with their boss cards) is entirely absent. The lead priority order at Bot.lua:804–891 is: (1) free-trick suit where both opponents void, (2) singleton low, (3) lowest from longest non-trump, (4) lowest non-trump, (5) lowest trump. None of these steps inspect `S.s.bids[R.Partner(seat)]` to extract a preferred lead suit.

**FREQUENCY:** Every hand at Advanced+ where the human partner bid Hokm. This is a fundamental partnership signal that fires once per round on the first applicable lead.

**BOT-EXPLOITS-IT:** Not applicable — this is a bot-as-partner coordination gap, not an exploit. Opponents benefit passively: by never returning partner's bid suit, the bot fails to establish the trump-side run that the human partner's bid declared they can support.

**FILE:LINE:** `C:/CLAUDE/WHEREDNGN/Bot.lua:804–891` (`pickLead` defender-path / non-bidder path). The `partnerBidBonus` at Bot.lua:410–427 already reads `S.s.bids[partner]` and extracts `bidTrump` from a `BID_HOKM:X` bid, but this logic is confined to escalation strength evaluation and never feeds into `pickLead` suit selection.

**FIX:** In `pickLead`, before the singleton-low and longest-suit steps (after the free-trick check), add an Advanced-gated branch: read `S.s.bids[R.Partner(seat)]`. If the partner bid `HOKM:X` and the contract trump matches `X`, and we hold 2–3 cards in suit `X` (non-trump in the current contract, or trump if we are defenders), collect cards of that suit and return `lowestByRank` from them. Gate on not already being in the bidder-team-lead-trump path (i.e., only fires for the defender team or bidder's partner when not drawing trump). The pattern mirrors the existing Fzloky-pref-suit lead at Bot.lua:760–773 but keyed on `bids[partner]` instead of `firstDiscard`.

---

## B-90 — Human partner Fzloky firstDiscard inference discount

**SIGNAL/MISTAKE:** CONFIRMED BUG. `pickLead` (Bot.lua:747–773) reads `Bot._memory[p].firstDiscard` and treats it as a suit-preference signal unconditionally when `Bot.IsFzloky()` is true. There is zero check of `S.s.seats[p] and S.s.seats[p].isBot`. When the partner is a human player, their first off-suit discard is typically driven by hand management (shedding from a weak suit), not by Fzloky convention. The bot will misread a human's casual high-card discard (e.g., K of Clubs thrown to stay in a suit) as a "lead Clubs" signal and alter its entire lead priority for the round. This is a direct play error propagated through every remaining lead until memory resets. The identical defect in the partner-reads-bot direction (human cannot read bot's Fzloky discard) is a UI gap but not a bot logic error; the code bug is one-way: bot misreads human.

**FREQUENCY:** Every hand at Fzloky or SaudiMaster tier with at least one human partner. The `firstDiscard` is set on the very first off-suit play the partner makes (Bot.lua:222–226), so the signal fires early and persists for the full round. Wave 8 C3 (B-87) identified the same root cause from the opposite direction — prior art confirmed.

**BOT-EXPLOITS-IT:** A human opponent who understands this bug can force the bot to misplay: when sitting as the bot's "opponent" across the table (not partner), the opponent deliberately discards a high card of a suit they want the bot NOT to lead (or to lead low in), steering the bot's lead priority in a harmful direction. Since `Bot._memory` accumulates all 4 seats' discards and `pickLead` reads specifically `Bot._memory[R.Partner(seat)]`, only the partner's discard influences the bot's lead — so the exploit only works if the attacker is in the partner seat (which in a 2v2 game they are not, unless the attacker controls the human partner's play out-of-band).

**FILE:LINE:** `C:/CLAUDE/WHEREDNGN/Bot.lua:747–758` (Fzloky signal read in `pickLead`) and `C:/CLAUDE/WHEREDNGN/Bot.lua:848–869` (Fzloky avoid-suit in longest-suit selection). The `S.IsSeatBot` helper exists at `C:/CLAUDE/WHEREDNGN/State.lua:624–626`.

**FIX:** Wrap the Fzloky signal-read block at Bot.lua:747–773 with `if Bot.IsFzloky() and Bot._memory and S.IsSeatBot(R.Partner(seat)) then`. Only when the partner is a bot seat should `firstDiscard` be treated as a convention signal. Similarly, the `fzlokyAvoidSuit` branch at Bot.lua:848–869 should be suppressed when `not S.IsSeatBot(R.Partner(seat))`. This is a one-line condition change in each of two `if` guards; the `S.IsSeatBot` helper is already present and tested.

---

## B-92 — Human partner under-bidding: PASS penalty over-applied

**SIGNAL/MISTAKE:** CONFIRMED. `partnerBidBonus` (Bot.lua:410–427) returns `-10` whenever `b == K.BID_PASS` (line 418), with no distinction between a bot partner pass (which provably signals weakness — `Bot.PickBid` gates on `suitStrengthAsTrump >= 42` and falls through to `K.BID_PASS` only when the hand is genuinely weak) and a human partner pass (which may reflect either genuine weakness OR overcaution — a human who holds a 38-point hand that "doesn't feel right" will pass where a bot would have bid). The `-10` penalty reduces the bot's combined-team strength estimate and makes it less willing to escalate, which is correct for bot partners but systematically wrong for cautious human partners. This effect propagates into `PickDouble`, `PickTriple`, `PickFour`, `PickGahwa` and `PickPreempt` — every function that calls `escalationStrength` → `partnerBidBonus`.

**FREQUENCY:** In any mixed human-bot game, the human partner will pass at rates higher than the bot's calibration assumes. The overcount is not large per round (10 strength units out of a 90–135 escalation threshold), but on marginal decisions at the Bel/Triple boundary it can tip the decision from yes to no and cost the team a legitimate escalation.

**BOT-EXPLOITS-IT:** No — this is a coordination loss, not an exploit. An opponent human sitting across from the bot could in theory exploit this by noting that the bot is less aggressive after its human partner passed, but the mechanism (timing their own Bel relative to partner's pass) is indirect and probabilistic.

**FILE:LINE:** `C:/CLAUDE/WHEREDNGN/Bot.lua:418` (`if b == K.BID_PASS then return -10 end` in `partnerBidBonus`).

**FIX:** Gate the penalty magnitude on whether the partner is a bot. Suggested change at Bot.lua:418:

```
if b == K.BID_PASS then
    local partnerIsBot = S.s.seats and S.s.seats[partner]
                         and S.s.seats[partner].isBot
    return partnerIsBot and -10 or -5
end
```

This halves the PASS penalty for human partners, reflecting the empirical reality that human overcaution is prevalent at casual play levels while preserving the stronger penalty for bot partners whose PASS is definitively weak. The wave 5 C3 audit (B-09) previously flagged the missing `isBot` gate on `partnerBidBonus` in general; B-92 is the specific PASS-penalty sub-case.

---

## B-93 — Human opponent Bel timing hesitation exploit

**SIGNAL/MISTAKE:** UNIMPLEMENTED — infrastructure does not yet exist. The Bel window is armed by `N.StartBelTimer(belSeat, "double")` (Net.lua:2961) which fires a `C_Timer.NewTimer(K.TURN_TIMEOUT_SEC, ...)` (Net.lua:2794). There is no `phaseEnteredAt` or `escalationOpenedAt` timestamp stored in `S.s` or anywhere in `Bot._partnerStyle`. `Bot.PickTriple` (Bot.lua:1215–1225) receives only `seat` and reads `S.s.contract` plus its own hand — it has no access to "how many seconds elapsed before the human Beled." `GetTime()` is available in the Lua environment (used in Log.lua:22 and Net.lua:1671), but no call to it is inserted at the moment `PHASE_DOUBLE` begins. Prior art: wave 6 C4 (angle B-63) and wave 7 C4 both identified the same missing infrastructure.

**FREQUENCY:** The signal would only be useful in specific games where a human opponent is known to hesitate. Without the timestamp, no hesitation signal is detectable at all — the gap is a hard zero-rate miss, not a partial-signal miss.

**BOT-EXPLOITS-IT:** No — the bot currently cannot access Bel timing. However, this is a high-value addition: in Saudi Baloot, an experienced player who Bels after 40+ seconds is visibly "counting their cards" and has a marginal hand. The bot's `PickTriple` could lower its threshold by 5–8 points when elapsed time > 40s, since a hesitant Bel implies the human was on the fence (borderline strength, not dominant defence). If implemented naively, it could be reverse-exploited: a human with a strong hand could deliberately slow-play the Bel window to bait the bot into Triple.

**FILE:LINE:** `C:/CLAUDE/WHEREDNGN/Net.lua:2787–2797` (`N.StartBelTimer`), `C:/CLAUDE/WHEREDNGN/Bot.lua:1215–1225` (`Bot.PickTriple`), `C:/CLAUDE/WHEREDNGN/Constants.lua:243` (`K.TURN_TIMEOUT_SEC = 60`).

**FIX:** Two-step: (1) At `PHASE_DOUBLE` entry, store `S.s.escalationOpenedAt = GetTime()` — the most natural place is inside `N.StartBelTimer` at Net.lua:2792 before the `C_Timer.NewTimer` call, or inside `State.ApplyContractFinalized` when the phase transitions. (2) When the human Bels (in `N._OnDouble`, the human path), compute `elapsed = GetTime() - (S.s.escalationOpenedAt or 0)` and store it as `Bot._partnerStyle[belSeat].lastBelElapsed`. (3) In `Bot.PickTriple`, check `Bot._partnerStyle and Bot._partnerStyle[defSeat] and Bot._partnerStyle[defSeat].lastBelElapsed`. If `elapsed > 40` and the Bel came from a non-bot seat, reduce `th` by 6 (more aggressive Triple). Guard against reverse-exploit by capping the reduction: if `_partnerStyle[defSeat].bels >= 2` and they always hesitate, do not apply the reduction (established pattern = not hesitation).

---

## B-94 — Human partner void inference leak: bot must not exploit partner's void

**SIGNAL/MISTAKE:** The bot's void tracking correctly fires for ALL four seats via `Bot.OnPlayObserved` (Bot.lua:200–270) — when any seat (human or bot) fails to follow lead suit, `mem.void[leadSuit] = true` is recorded. The `opponentsVoidInAll` helper (Bot.lua:272–281) correctly filters to opposing-team seats only, so a human PARTNER's void is never used to score a free trick against them (since free-trick logic only fires when `R.TeamOf(opp) ~= R.TeamOf(seat)` for both opponents). The concern in B-94 is whether the bot might inadvertently LEAD into a partner's known void in a way that wastes a trick or allows opponents to over-trump. Examining `pickLead` (Bot.lua:804–891): the lead-priority logic does not consult `Bot._memory[R.Partner(seat)].void` anywhere. The longest-suit selection (Bot.lua:849–888) does not exclude suits where the human partner is known void. This is a coordination loss: if the human partner is void in Diamonds (and therefore cannot contribute to winning a Diamonds trick), the bot should prefer leading a suit where the partner has cards.

**FREQUENCY:** Per-round, once the partner's void becomes established (typically tricks 3–6). The signal is always available when `Bot._memory[R.Partner(seat)].void[suit] == true`.

**BOT-EXPLOITS-IT:** No exploitation is currently occurring. The risk vector is the inverse: the bot passively wastes leads into partner's void, reducing team trick-take efficiency. There is no code path that reads `Bot._memory[p].void` during `pickLead` for the partner's benefit (the only consumer of `_memory[opp].void` is the `opponentsVoidInAll` free-trick shortcut). The B-94 concern about bots "exploiting void info to mislead partner" is a non-issue: there is no mechanism by which the bot leads partner's void deliberately to deceive opponents (the bot has no deception model), and doing so would be self-harming (it gives the trick to opponents). The real gap is the complement: bot does not AVOID leading partner's void suit when a better suit is available.

**FILE:LINE:** `C:/CLAUDE/WHEREDNGN/Bot.lua:849–888` (longest-suit selection in `pickLead`), `C:/CLAUDE/WHEREDNGN/Bot.lua:96–116` (`emptyMemory` — void field defined per seat for all 4 seats), `C:/CLAUDE/WHEREDNGN/Bot.lua:272–281` (`opponentsVoidInAll` — only queries opponents, never partner).

**FIX:** In `pickLead`, at the longest-suit selection step (Bot.lua:849–888), add an Advanced-gated partner-void penalty: before the two-pass suit selection, mark any suit where `Bot._memory and Bot._memory[R.Partner(seat)] and Bot._memory[R.Partner(seat)].void[suit]` as a low-preference lead (treat it like `fzlokyAvoidSuit`). The partner is void in that suit, so any card we lead there must be won by us alone or lost to opponents. Concretely, extend the two-pass selection logic: on Pass 1, exclude both `fzlokyAvoidSuit` AND partner-void suits; on Pass 2, restore partner-void suits only if no better alternative exists (same "≥2 more cards" tolerance currently applied to `fzlokyAvoidSuit`). This is a low-risk change: it only fires when the bot already has memory of the partner's void, and it never prevents a necessary lead (if all non-trump suits are partner-void, Pass 2 will restore them).

---

## Summary Table

| Angle | Signal | Frequency | Bot-Exploits | File:Line |
|-------|--------|-----------|--------------|-----------|
| B-89  | MISSING heuristic — no partner-bid-suit return play in pickLead | Every hand (Advanced+, human partner bid Hokm) | N/A — coordination gap | Bot.lua:804–891 |
| B-90  | CONFIRMED BUG — Fzloky reads human partner discard as convention signal | Every Fzloky/SaudiMaster hand with human partner | Indirect: human can steer bot lead | Bot.lua:747–758, 848–869 |
| B-92  | CONFIRMED — PASS penalty -10 not discounted for human overcaution | Every mixed game where human partner passes | No — coordination loss only | Bot.lua:418 |
| B-93  | UNIMPLEMENTED — no Bel timing infrastructure exists | Zero (hard miss) | Reverse-exploit possible if added naively | Net.lua:2787–2797, Bot.lua:1215–1225 |
| B-94  | PARTIAL GAP — bot does not avoid leading partner's known void suit | Tricks 3–6 whenever partner void established | No — bot does not exploit partner voids | Bot.lua:849–888 |
