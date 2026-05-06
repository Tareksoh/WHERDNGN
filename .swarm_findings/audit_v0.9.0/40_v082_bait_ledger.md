# v0.8.2 — Section 11 rule 8 bait-detected ledger (audit)

Commit: `3acc948` — Bot.lua +63 lines, CHANGELOG.md +39 lines. 319/319 tests pass.

## What it wires

A per-seat per-suit counter `Bot._partnerStyle[seat].baitedSuit[S/H/D/C]`
that increments when a seat plays J of led-suit-or-trump while their
partner was already winning the pre-J trick state. M3lm-gated `pickLead`
defender branch then avoids re-leading any suit any opp has baited.

## 1. Detection (heuristic, not signal-table)

`Bot.lua:483-499`. Conditions:

- `not wasIllegal and contract and #trickPlays >= 2`
- `C.Rank(card) == "J"` (suit irrelevant — J of any suit qualifies)
- Reconstruct pre-J trick (`prePlays = trickPlays[1..n-1]`),
  call `R.CurrentTrickWinner(prevTrick, contract) == R.Partner(seat)`.

Pure heuristic. No check that a lower card was *available* — this is
the documented false-positive vector (see #4).

## 2. Write site

`Bot.OnPlayObserved` at lines 483-499, immediately after the v0.5.10
Section 8 Tahreeb block and the leadCount block. Increment is
unconditional on tier — ledger always accumulates.

## 3. Read site

`pickLead` defender branch, `Bot.lua:1796-1816`. Iterates seats 1..4,
filters `R.TeamOf(s2) ~= R.TeamOf(seat)`, consumes
`m.baitedSuit[suit] >= 1`. Sets `fzlokyAvoidSuit` only if no earlier
avoid set and `suit ~= contract.trump`. Layered: Fzloky avoid >
meld-suit avoid > bait-suit avoid (first non-nil wins).

## 4. False-positive rate — REAL CONCERN

**No `seat == ourSelf` exclusion at write site.** Any seat (including
partners and the bot itself) gets a `baitedSuit` increment when J is
played and their partner was leading. The read site filters via
`R.TeamOf(s2) ~= R.TeamOf(seat)`, so partner increments are never
consumed — but they are stored.

**More serious: no "J was unnecessary" guard.** If opp's only legal
card was J (forced), this still counts as "bait." The detection
conflates voluntary deceptive overplay with forced J-plays. CHANGELOG
acknowledges only the random-property test sweep — no targeted fixture
distinguishes forced-J from voluntary-J. Real games where opp is down
to J + low cards in a suit will systematically flag them.

## 5. Tier gating

Asymmetric. **Write: ungated** (always accumulates). **Read: M3lm+**
(`Bot.IsM3lm()` guard at 1796). Saudi Master inherits M3lm reads via
ISMCTS state. Basic / Advanced bots accumulate but never read — wasted
work but no behavior change.

## 6. Reset semantics

**Game-scoped, NOT round-scoped.** `baitedSuit` lives in `emptyStyle()`
and is only cleared by `Bot.ResetStyle()` (new game) — *not* by
`Bot.ResetMemory()` (per-round). Compare `tahreebSent` at line 150-153,
which is explicitly cleared per-round. Cross-round leakage of bait
flags is a deliberate v0.8.2 choice (see CHANGELOG: "per-suit counter
accumulated across the game") but means a single false-positive J-play
in round 1 suppresses lead-into-X for the rest of the game.

## Verdict

Wire is sound. Detection is brittle (no forced-J guard). Cross-round
accumulation amplifies false-positives.
