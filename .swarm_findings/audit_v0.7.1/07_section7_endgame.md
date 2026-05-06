# Section 7 Audit — Endgame / SWA / Al-Kaboot (v0.7.2 HEAD)

## Scope
Section 7 of `docs/strategy/decision-trees.md` vs.
`Bot.PickSWA` (Bot.lua:3094), `pickLead` sweep-pursuit branch
(Bot.lua:1359-1444), trick-8 / Bargiya sender (Bot.lua:2231-2289),
and `R.IsValidSWA` (Rules.lua:349-467).

## Rule-by-rule verification

| # | Rule (abbrev) | Status | Evidence |
|---|---|---|---|
| 1 | Bidder, won >=6, promote Al-Kaboot pursuit | **WIRED-CORRECT** | `pickLead` Bot.lua:1392-1443, trick-8 boss-lead + sweep-pursuit (mySwept==7) tie-break to highestByRank. |
| 2 | Trick-3 trigger: bidder team won 1+2 cleanly -> sweep-pursuit early | **WIRED-CORRECT** | Bot.lua:1381-1391 `sweepPursuitEarly = (trickNum>=3 and trickNum<=7 and isBidderTeam and mySwept==trickNum-1)` — landed v0.5.19. Doc still says "partial wire — only trick-8 currently active"; **doc is stale**. Hand-shape predicate (J+9 trump etc.) is NOT checked, but the no-opp-cut proxy is the operational core. |
| 3 | Sun bidder sabotage own sweep when MULT_BEL*hand_total > AL_KABOOT_SUN | **NOT-WIRED** | No score-aware sweep-abandonment branch. Confirmed deferred per CHANGELOG v0.5.19. |
| 4 | Defender Qaid-bait | **NOT-WIRED** | Per doc + CHANGELOG: bot deliberately skips. |
| 5 | Defender prevent Kaboot (primary goal #1) | **WIRED-IMPLICIT** | `pickFollow` winners-branch returns any legal winner against opp-winning trick. Per CHANGELOG: "First success" = winners-branch firing. |
| 6 | Defender force-fail (primary goal #2) | **WIRED-PARTIAL** | `scoreUrgency` Bot.lua:791 biases bidding/escalation; play-side does NOT switch from cheapest-winner to highest-face-value-winner when defender + bidder-making. CHANGELOG flags as future work. |
| 7 | Sun, partner winning, hold A of X -> Bargiya (discard A) | **WIRED-CORRECT** | Bot.lua:2276-2288 T-1 Bargiya: M3lm+, Sun, partner-winning, void-in-led, A of side suit with cover (>=2 cards). Lands v0.5.10. |
| 8 | Sun trick-8 Bargiya followup: lead suit you Bargiya'd | **NOT-WIRED** | No `tahreebSent`/own-Bargiya read in `pickLead`. Confirmed deferred. |
| 9 | Reverse Al-Kaboot (+88 raw to defender sweep vs bidder) | **NOT-WIRED** | `R.ScoreRound` Rules.lua:631-643 routes any `trickCount==8` sweep to bonus 250/220 *regardless of which team is bidder*. No `K.AL_KABOOT_REVERSE`, no `firstLeader==bidder` predicate. Single-source (#16) status unchanged; **no new corroboration in CHANGELOG v0.5.18-v0.7.2**. Still deferred. |
| 10 | SWA card-count thresholds (<=3/4/5+) | **WIRED-LOOSE** | Post-v0.5.17 `Net.LocalSWA` (Net.lua:2365-2399) routes ALL claims through 5-sec permission window — no 5+-mandatory differentiation, but functionally stricter than legacy (no instant-claim path). |
| 11 | SWA = deterministic-or-bust | **WIRED-CORRECT** | `R.IsValidSWA` Rules.lua:460-466 iterates EVERY legal play of every other seat (incl. partner adversarially) and returns false if any leads to a non-callerSeat trick. v0.5.17 tightening matches video #35 convention. Plus v0.5.21 Hokm safety net (Bot.lua:3134-3163): rejects when opp top-trump > caller top-trump. |
| 12 | Opp denies SWA via Takweesh -> Qaid penalty | **WIRED-CORRECT** | `MSG_SWA_OUT` payload + `Net.HostResolveSWA` outcome path. |

## Reverse Al-Kaboot status update
**No new evidence.** CHANGELOG entries v0.5.18 through v0.7.2 do
not introduce `K.AL_KABOOT_REVERSE` or any defender-sweep gate.
v0.5.19 explicitly defers ("single-source; confirm before wiring").
Still single-source from video #16. **Recommendation: keep
deferred.**

## SWA strict-deterministic enforcement — confirmed
Rules.lua:437-459 comment block explicitly documents the v0.5.17
transition from cooperative ("SOME partner play leads to win") to
adversarial ("EVERY partner play leads to win"). Recursion at
:460-466 has no team-aware branch — partner is iterated
identically to opponents. Combined with `winner == callerSeat`
check at :366, enforces deterministic-or-bust. **Matches video
#35 convention.**

## Summary
- **WIRED-CORRECT:** 1, 2, 7, 11, 12 (5/12)
- **WIRED-IMPLICIT/PARTIAL/LOOSE:** 5, 6, 10 (3/12)
- **NOT-WIRED (deferred):** 3, 4, 8, 9 (4/12)

## Headline
v0.5.17 SWA tightening + v0.5.21 Hokm safety net + v0.5.19 trick-3
sweep pursuit are correctly landed. Reverse Al-Kaboot remains
single-source deferred. Doc text on rule 2 ("partial wire — only
trick-8") is stale post-v0.5.19. Rule 3 Sun-sabotage and rule 6
defender force-fail play-side bias are the most impactful gaps.
