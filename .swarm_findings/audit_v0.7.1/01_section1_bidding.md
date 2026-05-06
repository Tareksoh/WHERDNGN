# Section 1 (Bidding) coverage audit — v0.7.2

Doc rules numbered B-1..B-6 (Hokm), S-1..S-8 (Sun), A-1..A-6 (Ashkal), G-1..G-4 (goal-discipline). `Bot.PickAshkal` does NOT exist — Ashkal is inline at Bot.lua:1054-1134.

## WIRED-CORRECT
- B-1 (J + cover + side-Ace minimum): `hokmMinShape` Bot.lua:594-611, side-Ace branch line 609.
- B-2 (4+ trumps inc. J self-sufficient): line 608.
- B-4 (no J or ≤2 → pass): line 607.
- B-5 (Hokm preferred unless Sun > Hokm by ≥5): Bot.lua:1198-1209 via `K.BOT_BIDDING_SUN_OVER_HOKM_MARGIN`.
- B-6 (Belote +20 mandatory): `beloteSuit` Bot.lua:646-658, applied at 1162-1164 / 1187.
- S-1 (A+T mardoofa OR 2+ Aces minimum): `sunMinShape` Bot.lua:621-637, gated 1147 / 1198.
- S-3 (3+ Aces strong-Sun bonus): Bot.lua:983.
- S-4 (Carré of Aces mandatory Sun): Bot.lua:955-956 — earliest return.
- S-5/S-6 (anti-trigger bare-Ace / long-no-Ace): subsumed by `sunMinShape` line 630-635.
- S-7 (cumulative ≥100 Bel-fear bias): Bot.lua:1036-1041, `+8` to thSun.
- S-8 (Sun-Mughataa per-mardoofa bonus): Bot.lua:984-985.
- A-1 (only dealer + dealer's-left): State.lua:1554-1560 `bidPosition < 3`. Bot side mirrors at Bot.lua:1062-1073.
- A-3 (bid-up A → no Ashkal): Bot.lua:1083.
- A-4 (bid-up T + own A same suit → no Ashkal): Bot.lua:1090-1096.
- A-5 (3+ Aces → direct Sun, not Ashkal): Bot.lua:1103.
- A-6 (65/85 pivot to direct Sun): Bot.lua:1112-1114.

## WIRED-WRONG
- B-3 (5+ trumps incl. J → bid + plan Al-Kaboot): doc says set `S.s.pursuitFlagBidder` for trick-3 trigger; code only adds general J+9 bonus at Bot.lua:550-552. No flag is ever set. Effectively NOT-WIRED for the pickLead handoff.
- A-2 (eligible + bid-up small-rank → Ashkal): doc requires explicit small-rank check. Code at Bot.lua:1073-1132 fires Ashkal whenever `bidPos>=3 && partnerBid==Hokm && !anySun && sun>=thAshkal` — no rank-of-bidCard inspection beyond the A and T anti-triggers. Doc's `bidCardRank ∈ {7,8,9,J,Q,singleton-T}` positive predicate is absent.

## NOT-WIRED
- G-2 (round-1-conservative borderline pass): no R1-specific bias; `r1WasAllPass` at Bot.lua:1019 only LOWERS R2 thresholds, doesn't tighten R1.
- G-3 (round-2 commit-the-strongest at minimum threshold): R2 base is still ≥ R1 (Bot.lua:1011-1013) — opposite of doc intent.
- G-4 (do NOT outbid partner's contract / takweesh exception): grep finds no `partnerBid==K.BID_HOKM ⇒ suppress own Sun` gate; Bot.lua:1147 will overcall partner's Hokm with Sun on `sunMinShape && sun>=thSun`.

## CODE-WITHOUT-DOC
- Bot.lua:1116-1129 Advanced-only Ashkal anti-trigger (`hasJflip || sCnt>2 ⇒ skip`) — partner's-bid-bluff guard. No row in Section 1.
- Bot.lua:711-721 sunStrength long-suit-walk +6/card and AKQ-stopper +8 — bidding strength inputs, not surfaced as rules.
- Bot.lua:1019-1021 trap-pass R2 threshold drop (M3lm + r1WasAllPass) — adaptive bid-table model, undocumented.
- Bot.lua:553-558 Advanced damp ×0.4 for J-less short suits — undocumented anti-trigger.

## NOTES
- doc line `Bot.lua:725` for "strength formula" stale (725 lands inside `sunStrength`, not the formula entry; the real entry is `Bot.PickBid` at 942).
- A-1 MAPS-TO line range "State.lua:1464-1487" stale: actual block is 1528-1572.
- B-5 Source 25,26 vague on exact margin (5 was a code calibration choice).
