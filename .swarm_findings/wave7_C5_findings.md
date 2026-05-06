# Wave 7 C5 — Dynamic Adaptation Against Humans

## B-68 — Bot card memory vs human forgetting (Ace/Ten stoppers)

| Field | Detail |
|---|---|
| SIGNAL/MISTAKE | BOT ADVANTAGE (correctly implemented — no bug) |
| FREQUENCY | Every game where a suit stopper (A or T) has already been played |
| BOT-EXPLOITS-IT | Confirmed exploitable. `Bot._memory[seat].played` is a full per-card hash maintained by `Bot.OnPlayObserved` (Bot.lua:204). `suitCardsOutstanding` (Bot.lua:897–913) counts remaining unplayed cards in any suit. `pickFollow` pos-2 duck logic (Bot.lua:978–1026) specifically checks whether outstanding trump <= 1 before committing a stopper — the same outstanding-count pattern applies to non-trump suits when `HighestUnplayedRank` is used in `pickLead` (Bot.lua:731–738). Humans frequently believe an Ace is still live when it has been played; the bot has perfect recall and will lead into suits where the human's only stopper is gone. |
| file:line | Bot.lua:897–913, Bot.lua:731–738, Bot.lua:204 |
| fix | No fix needed — this is correct, intended asymmetry. Document as a known human-disadvantage for UX/help text. |

---

## B-69 — Human score miscount: asymmetric target visibility

| Field | Detail |
|---|---|
| SIGNAL/MISTAKE | MISTAKE — target is never broadcast to non-host clients on resync |
| FREQUENCY | Every non-default-target game where a client does /reload or joins mid-game |
| BOT-EXPLOITS-IT | Indirect asymmetry. The bot always reads `S.s.target` (Bot.lua:448, 473) which on the host is correct. A human client who joined late or reloaded will have `s.target` from their own `WHEREDNGNDB.target` (State.lua:75, WHEREDNGN.lua:77) — which defaults to 152 and is never overridden via the wire. `packSnapshot()` in Net.lua:306–351 encodes 25 fields (gameID through botMask) but does not include `target`. The only inter-client target distribution is via the lobby broadcast `MSG_LOBBY`, which also carries no target. If the host set `/baloot target 100`, a late-joining or reloaded human client plays toward 152 — their urgency decisions (whether to push escalation, take risks) are miscalibrated. The bot is immune because it runs on the host. |
| file:line | Net.lua:306–351 (`packSnapshot`), State.lua:75, Bot.lua:448 |
| fix | Add `s.target` to `packSnapshot()` as field 30 (after `botMask`); decode and apply it in `S.ApplyResyncSnapshot`. Also append to `MSG_LOBBY` so clients in the lobby seat correctly before the game starts. |

---

## B-71 — Dynamic Bel threshold when opponent is habitual Beler

| Field | Detail |
|---|---|
| SIGNAL/MISTAKE | MISSING FEATURE — `styleBelTendency` is defined but never wired into any decision path |
| FREQUENCY | Every hand after opponent has Beled 2+ times in the game |
| BOT-EXPLOITS-IT | Not exploitable in current code — this is a gap, not an exploit. `styleBelTendency(seat)` (Bot.lua:181–187) correctly returns 1 when `m.bels >= 2`, but a search across all callers shows it is never called anywhere in Bot.lua, BotMaster.lua, or Net.lua. The comment at Bot.lua:176–180 explicitly marks it "currently unused by the picker code". `Bot.PickTriple` (Bot.lua:1215–1225) computes `th = K.BOT_TRIPLE_TH - urgency` without consulting any opponent style. B-71 proposes that if the opponent's `bels >= 2` the Triple threshold should drop — a habitual Beler's challenge is less informative, so the bot-bidder needs a lower bar to counter. The ledger data (maintained since `Bot.OnEscalation`) is already correct; the threshold logic is simply not reading it. |
| file:line | Bot.lua:181–187 (unused function), Bot.lua:1215–1225 (PickTriple, no style gate) |
| fix | In `Bot.PickTriple`, after computing `th`, add: if `Bot.IsM3lm()` and the calling Bel seat is an opponent (`R.TeamOf(belSeat) ~= R.TeamOf(seat)`), call `styleBelTendency(belSeat)` — if it returns 1, subtract ~8 from `th` (habitual Beler's challenge is discounted). Expose the belSeat via the contract or a parameter passed from `MaybeRunBot`. |

---

## B-72 — Trump tempo tell: humans who lead trump in tricks 1–3

| Field | Detail |
|---|---|
| SIGNAL/MISTAKE | MISSING FEATURE — `styleTrumpTempo` is defined but never consumed by play logic |
| FREQUENCY | Every hand after a human opponent has been observed leading trump aggressively in tricks 1–4 across 2+ rounds |
| BOT-EXPLOITS-IT | Not exploitable in current code — again a gap. `styleTrumpTempo(seat)` (Bot.lua:189–196) returns 1 (aggressive) or -1 (conservative) based on `trumpEarly`/`trumpLate` counters. The counters are correctly maintained in `Bot.OnPlayObserved` (Bot.lua:244–255) using the `trickNum <= 4` boundary. However, neither `pickFollow` nor `pickLead` call `styleTrumpTempo` for any opponent seat. The intended exploit path (save high trumps for tricks 4–8 against an early-trump human) cannot fire. The defensive savings logic in `pickLead` (Bot.lua:720–892) makes no reference to opponent tempo. Note: the boundary is `trickNum <= 4` (tricks 1–4 are "early"), while the prompt says "tricks 1–3". This is a minor calibration gap — leading in trick 4 is still early-game in an 8-trick hand. |
| file:line | Bot.lua:189–196 (unused function), Bot.lua:244–255 (counter fill), Bot.lua:720–892 (pickLead, no tempo gate) |
| fix | In `pickLead` (defenders/partner branch), after building the non-trump candidate list, add an M3lm gate: for each opponent seat, call `styleTrumpTempo(opp)`. If >= 1 (aggressive tempo), prefer saving highest trump by not leading trump at all in tricks <=4, and hold the highest trump winner for tricks 5+. Alternatively, surface the saved trump preference in `pickFollow` pos-2 duck logic by consulting opponent tempo before committing a high-trump counter-ruff early. |

---

## B-73 — Human over-reliance on first-deal (5-card anchoring)

| Field | Detail |
|---|---|
| SIGNAL/MISTAKE | BOT ADVANTAGE (structural, no code gap needed) + MINOR MISSING FEATURE |
| FREQUENCY | Observable in every game against human bidders who committed in round 1 but then hold a very different final 8-card hand |
| BOT-EXPLOITS-IT | Partially exploitable, no active code for it. The bot re-evaluates strength using the full 8-card hand during play (Bot.lua:540 `PickBid` at deal2bid phase uses the complete hand; `pickLead`/`pickFollow` use `S.s.hostHands[seat]` which is the full 8-card hand). Humans who anchor to their 5-card assessment and play/escalate as if nothing changed are readable because their play will follow the pattern implied by the 5-card hand rather than the 8-card hand. The bot has no explicit "anchor bias detector" for human opponents — `_partnerStyle` tracks escalation and trump tempo but not bid-vs-play coherence. There is no comparison between a seat's bid (round 1, 5-card basis) and subsequent play (8-card basis) to score the coherence gap. |
| file:line | Bot.lua:540–656 (PickBid), Bot.lua:95–116 (memory), Bot.lua:126–151 (style ledger) |
| fix | Add an optional `bidCoherence` counter to `emptyStyle()`: when an opponent plays a card that contradicts their declared trump (e.g., throws trump early after bidding Hokm in that suit), increment a "plays weaker than bid" counter. In BotMaster's world-sampler (BotMaster.lua:17), use this to down-weight world samples where the opponent's reconstructed hand is stronger than their observed play — narrowing the search space further against human anchoring. |
