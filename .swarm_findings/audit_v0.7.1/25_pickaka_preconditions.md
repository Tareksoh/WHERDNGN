# Bot.PickAKA preconditions audit (HEAD = v0.7.2)

**File:** `C:/CLAUDE/WHEREDNGN/Bot.lua` lines 2606-2653
**Reference:** decision-trees.md Section 6, video 18

## Precondition coverage matrix

| # | Precondition | Wired? | Line(s) | Notes |
|---|---|---|---|---|
| (a) | contract == Hokm | YES | 2608 | `S.s.contract.type ~= K.BID_HOKM` early-return |
| (b) | card.suit != trump | YES | 2627 | `if su == trump then return nil` |
| (c) | card.rank != "A" | YES | 2634 | S6-10(c) gate (v0.5.16) |
| (d) | hold HIGHEST UNPLAYED of suit | YES | 2637 | `S.HighestUnplayedRank(su) ~= r` |
| (e) | leading + 0 plays in trick | YES | 2609 | `#S.s.trick.plays > 0` early-return |
| (f) | NOT partner certainly void in trump | **NO** | -- | No reference to partner void state in PickAKA. `partnerVoid`, `PartnerVoid`, `certainlyVoid` not wired anywhere in Bot.lua (only generic `partner-avoid`/`opp-avoid` suit logic at lines 1527, 1897, 1982 — different concept). |
| (g) | round_stage allows (early+lowUrgency OR top-of-suit certain) | **NO** | -- | Only `trickNum <= 1` skip at line 2649. No `combinedUrgency()` call inside PickAKA (compare to PickDouble line 2777). No "top-of-suit confidence is certain" branch — confidence isn't computed beyond the binary highest-unplayed check (d). |

Additional gates present (defensible but outside the spec list): bot-partner-only gate (line 2623), per-round per-suit dedup (line 2643), and Advanced-tier requirement (line 2607).

## v0.5.16 "AKA signaling refinements" — what it actually refined

CHANGELOG v0.5.16 entry covers exactly two items, both video-18 derived:

1. **S6-6 implicit-AKA receiver** — extended `pickFollow` H-5 branch to fire on partner's bare-Ace non-trump lead without explicit `MSG_AKA`. Receiver-side change.
2. **S6-10(c) sender skip on Ace** — the `r == "A"` gate at line 2634. Sender-side change. This is precondition (c).

**v0.5.16 closes (c) only.** It does NOT touch (f) or (g). The release notes explicitly scope to S6-6 and S6-10(c); no partner-void check, no urgency gate, no round-stage logic was added to `PickAKA`.

## Summary

- (a)-(e): all wired.
- (f): missing. No partner-trump-void inference is consulted.
- (g): partial. Only a coarse `trickNum <= 1` floor at line 2649 — no urgency-modulated stage gate, no confidence/certainty term.

Earlier Section 6 audit conclusion stands: (f) and (g) gaps remain open at HEAD v0.7.2.
