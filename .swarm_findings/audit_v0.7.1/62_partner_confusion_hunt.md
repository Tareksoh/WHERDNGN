# Audit: partner/opponent confusion hunt

HEAD = v0.7.2. Scope: every site that calls `R.Partner(seat)`,
`R.TeamOf(seat)`, or computes `oppTeam`. Verified against the canonical
mapping `Rules.lua:16-21` (1↔3, 2↔4) and `R.TeamOf` (1,3=A; 2,4=B).

## Verdict: PASS

No partner/opponent confusion bug found. Every audited site computes
the correct seat/team relative to the intended actor.

## Site-by-site

### 1. `Rules.lua:16-21` — `R.Partner` itself
Hard-coded explicit table. Each branch returns the team-mate (different
seat, same team). Self-as-partner impossible.

### 2. `BotMaster.lua:198-368` — `sampleConsistentDeal`
- Line 209: `bidderPartner = R.Partner(bidder)` — the BIDDER's partner,
  receives `partnerDesire` (trump-count or Sun A/K bias).
- Line 210: `partner = R.Partner(seat)` — the CALLER's partner, used
  only for the Fzloky signal-suit override (line 368).
- Line 362: `isBidderPartner = bidderPartner ~= nil and s == bidderPartner`
  — desire-table is applied to seat `s` ONLY when `s` is the bidder's
  partner. Correct.
- Line 358-360: `isDefender = bidder ~= nil and R.TeamOf(s) ~= R.TeamOf(bidder) and s ~= bidder`.
  Correctly excludes both bidder and bidder-partner from defender role.
- Line 389: `sIsOpponent = R.TeamOf(s) ~= R.TeamOf(seat)` — used to gate
  the Kawesh desire-clear. Computed against the SAMPLER caller (`seat`),
  not the bidder. This is the right axis for "preserve our own partner's
  Fzloky bias." Correct.

### 3. `Bot.lua:2164-2166` — `pickFollow`
- `curWinner = R.CurrentTrickWinner(trick, contract)`
- `partnerWinning = curWinner and R.Partner(seat) == curWinner` —
  partner-of-PLAYER. Correct (not `seat == curWinner`, not opponent).

### 4. `Bot.lua:303-518` — `Bot.OnPlayObserved`
- Line 441 (baitedSuit) and line 474 (Tahreeb): both use
  `R.Partner(seat) == prevWinner`. `seat` here is the seat we're
  RECORDING about — the signal direction is "seat signals to
  R.Partner(seat)". Correct.
- Implicit AKA detection at `Bot.lua:2192-2212` correctly checks
  `S.s.akaCalled.seat == R.Partner(seat)` and `lead.seat == R.Partner(seat)`.

### 5. `Bot.lua:1664-1666` — B-97 opp-meld avoidance
`oppTeam = (R.TeamOf(seat) == "A") and "B" or "A"`. With
`R.TeamOf(1)=A, TeamOf(2)=B, TeamOf(3)=A, TeamOf(4)=B`, the inverse
returns the opposite team for every seat. `S.s.meldsByTeam[oppTeam]`
then lists OPPONENT-declared melds. Correct.

### 6. `BotMaster.lua:731-732` — rollout score sign
`oppTeam = (myTeam == "A") and "B" or "A"`, `diff = raw[myTeam] -
raw[oppTeam]`. Correct.

### 7. Section 11 rule 4 (Sun-bidder-partner concentration)
`getPartnerCards` (BotMaster.lua:97-129) is invoked at line 208 and
applied at line 366 ONLY when `s == bidderPartner`. Bidder himself
gets `strong` (line 364); other-team seats get `defenderDesire` (line
365); leftover seat (the caller `seat`, but `s ~= seat` is enforced by
the surrounding loop) gets `{}`. Concentration applied to bidder's
partner only. Correct.

### 8. Seat iteration order
All seat loops are `for s = 1, 4 do` and condition on
team/equality, not index order. CCW order is irrelevant because no
loop assumes "next seat" is `s+1`. The single CCW dependency is
`R.NextSeat(seat) = (seat % 4) + 1` for play order, and rollout
play-order at `BotMaster.lua:705`: `nextSeat = (prev.seat % 4) + 1`.
Both correct.

## Notes
- Self-as-partner cannot occur: `R.Partner(seat) ~= seat` for all
  seats 1-4 by construction.
- No site treats `R.Partner(R.Partner(seat))` (which equals `seat`)
  as a partner — i.e., no double-application bug.
- The `bidderPartner` vs caller-`partner` split in the sampler is
  documented in code comments (lines 205-210) — guards against the
  most likely bug class.
