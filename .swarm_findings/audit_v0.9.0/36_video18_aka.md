# Video #18 (AKA) — re-verify vs HEAD v0.9.0(+v0.9.1 patch)

**Source transcript:** `docs/strategy/_transcripts/18_when_to_aka_extracted.md`
**Code:** `Bot.lua:2971-3033` (`Bot.PickAKA`), `Bot.lua:2277-2329` (`pickFollow` AKA-receiver)

## Precondition wiring (sender side, `Bot.PickAKA`)

| # | Claim | Status | Evidence |
|---|---|---|---|
| (a) | contract == Hokm | WIRED | Bot.lua:2973 — `S.s.contract.type ~= K.BID_HOKM -> nil` |
| (b) | card.suit != trump | WIRED | Bot.lua:2992 — `if su == trump then return nil end` |
| (c) | card.rank != "A" | WIRED (v0.5.16) | Bot.lua:2999 — `if r == "A" then return nil end` |
| (d) | highest unplayed of suit | WIRED | Bot.lua:3002 — `S.HighestUnplayedRank(su) ~= r -> nil` |
| (e) | leading + 0 plays in trick | WIRED | Bot.lua:2974 — `not S.s.trick or #S.s.trick.plays > 0 -> nil` |
| (f) | NOT (partner certainly void in trump) | **WIRED in v0.9.1** | Bot.lua:3015-3029 — reads `Bot._memory[partner].void[trump]`, returns nil. Commit 83717be (verified via `git show`). |
| (g) | round_stage / scoreUrgency / multiplier override | **STILL MISSING** | No reference to `scoreUrgency`, `matchPointUrgency`, `K.MULT_BEL`, trick-count threshold, or doubled-contract gate inside `Bot.PickAKA`. The only round-position check is `trickNum <= 1 -> skip` (Bot.lua:3013-3014), which is the inverse of the transcript override (transcript says relaxed gating in early round, current code is stricter). Section 2.3 of transcript not implemented. |

## Receiver convention (pickFollow)

- **Implicit AKA on bare-Ace lead:** WIRED (v0.5.16). Bot.lua:2299-2316 — fires when partner-led card has rank=="A", suit==leadSuit, suit!=trump, partner currently winning, and no explicit `S.s.akaCalled`. Same suppress-ruff outcome as explicit AKA (Bot.lua:2317-2329).
- **Verbal-required (silent high-card play does NOT confer relief):** CORRECTLY ENFORCED. Receiver branch fires only on `(explicitAKA or implicitAKA)`. `implicitAKA` is gated to rank=="A". A silent K/Q/J top-of-suit lead bypasses both predicates — partner falls through to normal Hokm forced-ruff logic. No silent-top-card relief path exists.

## Bonus checks

- Per-suit dedup (Bot.lua:3008): re-call on same suit is suppressed; consistent with "the boss" semantics.
- Human-partner suppression (Bot.lua:2988): AKA gated off when partner is human (audit B-33/B-60). Consistent with the "wasted/leak" anti-trigger.
- Trick-1 skip (Bot.lua:3013): conservative; not in transcript but defensible.

## Verdict

5/7 preconditions wired correctly. (f) confirmed patched in v0.9.1 (commit 83717be). (g) — early-stage tolerance + late-stage tightening — remains UNIMPLEMENTED in v0.9.0/v0.9.1. Implicit-AKA receiver and verbal-required gating both correct.
