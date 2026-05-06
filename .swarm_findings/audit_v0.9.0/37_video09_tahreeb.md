# Video #09 Re-verification (v0.9.0 / v0.9.1 HEAD)

Source: `docs/strategy/_transcripts/09_most_essential_tahreeb_extracted.md`.
Raw: `docs/strategy/_transcripts/JUT6N-eZwD8_09_most_essential_tahreeb.ar-orig.txt`.

## Claim 1 — 70/25/5 first-Tahreeb prior (receiver)

**Status: NOT-WIRED (confirmed).**
- `decision-trees.md:203` still ends with `Style ledger read in pickLead Bot.lua:953 (not yet wired)`.
- v0.9.1 audit table (CHANGELOG.md:43) lists "70/25/5 prior" in the Remaining
  Missing-Features column — 6/11 closed, this one still open.
- No grep hit for "70" / "25" / "5" weighting on Tahreeb suit-classification in
  `Bot.lua` or `BotMaster.lua`. `tahreebClassify` returns categorical labels
  (`bargiya` / `want` / `dontwant` / `bargiya_hint`) with integer weights
  (3/2/1) at Bot.lua:1673-1675; no probability prior over the three remaining
  suits is computed.

## Claim 2 — "Biggest mistake" rule, v0.7.2 Section 4 rule 1B

**Status: WIRED (confirmed) — but narrowly scoped.**
- Bot.lua:2569-2600 implements 1B exactly as specified: returns `sorted[2]`
  (second-lowest in-suit) when ALL of: `contract.type == K.BID_SUN`, partner
  is winning the trick, must-follow, can't beat the lead (smother branch
  above did not return), AND `#follow >= 2`.
- Comments cite "video 09 'biggest mistake'" and decision-trees.md
  Section 4 rule 1B.

## Claim 3 — Sender low-from-non-target (Tahreeb want-arm)

**Status: WIRED in v0.9.0 (confirmed).**
- Bot.lua:2496-2531 implements the sender's "want" arm:
  when discarding (PartnerWinning lead-pick), iterates suits S/H/D/C, and
  when we hold A or T of a side suit with ≥3 cards (winner + ≥2 covers),
  returns the LOWEST non-winner from that suit. Comments explicitly cite
  v0.9.0 / "audit missing item #7" / video 10 (extension applies to 09 too
  via the same signal vocabulary).
- Fires BEFORE T-4 (don't-want) so a "want" suit beats a doubleton dump.
- Note: 09's transcript labels the same play ("low from a non-target side
  suit to invite partner to lead the target back") — anchor-video 10, but
  the rule is identical.

## Claim 4 — "Biggest mistake" scope: Tahreeb-receiver only, or general?

**Status: SENDER-side, NOT general partner-winning.**
- Raw transcript lines 100-141: speaker is talking about the SENDER who
  holds Diamond-10 strength; partner has eaten and led; sender now follows.
  The speaker says playing the LOWEST (7) is "اكبر غلط في البلوت" because
  it removes the receiver's re-entry hint — partner can no longer infer the
  sender wants Diamonds back. This is the sender side of the want-arm
  signaling, not a generic partner-wins-trick rule.
- Code matches scope: 1B fires only `contract.type == K.BID_SUN` AND
  partner-winning AND must-follow AND can't-beat AND `#follow >= 2`.
  Hokm partner-winning explicitly excluded (different conventions).
- Doc trail at decision-trees.md Section 4 rule 1B keeps the same Sun-only
  guard. The Hokm path is unaffected.

## Summary

| # | Claim | Status |
|---|-------|--------|
| 1 | 70/25/5 first-Tahreeb prior  | NOT-WIRED (still open) |
| 2 | "Biggest mistake" → 2nd-lowest | WIRED (v0.7.2, Sun-only) |
| 3 | Sender low-from-non-target | WIRED (v0.9.0 want-arm) |
| 4 | Scope of (2) | Correctly Sun-partner-winning only |

No drift; doc and code agree. Open work remains on the categorical->
probabilistic upgrade for receiver-side suit redistribution.
